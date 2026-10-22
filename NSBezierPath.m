/*
 * NSBezierPath — a mutable CGPath, the line state that belongs to the path, and the draw verbs.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * TWO THINGS ARE EASY TO GET SUBTLY WRONG HERE, and each is one helper with a probe check on the
 * RESULT rather than on the arithmetic:
 *
 *   THE ANGLE UNITS. Apple's arc constructors take DEGREES with 0° along the positive x axis and
 *   increasing counterclockwise; `CGPathAddArc` takes RADIANS. `fn_radians` is the whole conversion,
 *   and the probe measures where a quarter-turn arc ENDS.
 *
 *   AND THE ELEMENT REPLAY, WHICH IS THIS TREE'S INSTEAD OF APPLE'S. CoreGraphics here has no
 *   `CGPathAddPath` and no `CGPathCreateCopyByTransformingPath` — I reached for both when this file was
 *   first written, because they are Apple's Core Graphics and not this library's — so APPENDING and
 *   TRANSFORMING are the same operation with one flag: walk the source path with `CGPathApply` and
 *   replay its elements onto a destination, mapping each point when a transform is in force.
 *   TRANSFORMING THE POINTS IS EXACT FOR AN AFFINE MAP (the map of a Bezier's control points is the map
 *   of the Bezier), which is why the replay needs no subdivision.
 *
 *   AND `-stroke` WRITES THE CONTEXT'S LINE STATE from the path's. That is Apple's arrangement — the
 *   line state belongs to the PATH — and it means a caller who set a width on the context and then
 *   stroked a path with its own width gets the path's. Stated in NSBezierPath.h, not discovered.
 */
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>

#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGPath.h>
#import <CoreGraphics/CGPath_internal.h>
#import <CoreGraphics/CGContext_internal.h>

/* THE RENAME TABLE FOR THE CLIP PRIMITIVE — `CGContextResetClip` is not in the 10.6 headers, so
 * its public declaration went in the 2026-10-05 era removal and the code is `cg_context_reset_clip`
 * in CGContext_internal.h. `-setClip:` is a REPLACE and this library's clip is CoreGraphics', so
 * the primitive is what makes the replacement possible at all. */
#define CGContextResetClip cg_context_reset_clip
#import <Foundation/NSAffineTransform.h>

/* THE RENAME TABLE FOR THE ONE PATH OPERATION THIS CLASS NEEDS — `CGPathCreateCopyByFlattening`
 * is macOS 13.0, so its public declaration went in the 2026-10-05 era removal and the code lives
 * under the name in CGPath_internal.h. `-containsPoint:` is a crossing count over a FLATTENED
 * path (an oval has no line segments at all, so a lines-only test would answer NO everywhere),
 * which is why the AppKit reaches into the library's own flattener rather than growing a second
 * one. */
#define CGPathCreateCopyByFlattening cg_path_create_flattened_copy

#include <stdio.h>
#include <stdlib.h>	/* malloc/free: the reversing copy collects the element model into a flat array. */
#include <string.h>

/* THE DASH ARRAY IS BOUNDED IN THE OBJECT, for the reason the graphics state's is: a pattern is a
 * handful of numbers, and a longer one is REFUSED rather than truncated — dashes the caller did not
 * ask for are worse than none. */
#define APPKIT_DASH_MAX 16

/* THE CLASS DEFAULTS, which a new path COPIES at creation (Apple's contract, and what makes
 * `+setDefaultLineWidth:` affect the paths made AFTER it rather than the ones already alive). The values
 * are Apple's documented ones.
 *
 * AND FLATNESS'S DEFAULT IS NOT AMONG THEM, WHICH IS A DEBT RATHER THAN A CHOICE: it stands beside its own
 * accessors further down this file, because the unit that shipped that family did not touch `-init`. The
 * consequence — a path with no opinion of its own reads the default LIVE rather than taking a copy here — is
 * stated in the header, and the fix is one line in `-init` beside these five. */
static CGFloat fn_default_line_width = 1.0;
static CGFloat fn_default_miter_limit = 10.0;
static NSLineCapStyle fn_default_cap = NSLineCapStyleButt;
static NSLineJoinStyle fn_default_join = NSLineJoinStyleMiter;
static NSWindingRule fn_default_winding = NSWindingRuleNonZero;

/* THE THREE ENUM MAPPINGS, AS SWITCHES AND NOT CASTS: the values are ours, so a cast would hide an
 * ordering that differed between the two headers. */
static CGLineCap fn_cap(NSLineCapStyle s)
{
	switch (s) {
	case NSLineCapStyleRound: return kCGLineCapRound;
	case NSLineCapStyleSquare: return kCGLineCapSquare;
	case NSLineCapStyleButt:
	default: return kCGLineCapButt;
	}
}

static CGLineJoin fn_join(NSLineJoinStyle s)
{
	switch (s) {
	case NSLineJoinStyleRound: return kCGLineJoinRound;
	case NSLineJoinStyleBevel: return kCGLineJoinBevel;
	case NSLineJoinStyleMiter:
	default: return kCGLineJoinMiter;
	}
}

/* DEGREES TO RADIANS, in one place — see the file's header note. */
static CGFloat fn_radians(CGFloat degrees)
{
	return degrees * 3.14159265358979323846 / 180.0;
}

/* --- the element walk, which serves BOTH appending and transforming -------------- */

typedef struct {
	CGMutablePathRef dst;
	CGAffineTransform t;
	int transform;      /* 0 for an append, 1 when `t` is in force */
} fn_replay;

static CGPoint fn_mapped(const fn_replay *r, const CGPoint *p)
{
	return r->transform ? CGPointApplyAffineTransform(*p, r->t) : *p;
}

/* ALL FIVE ELEMENT TYPES ARRIVE, and the point counts are Core Graphics': one for a move, one for a
 * line, two for a quadratic, three for a cubic, none for a close. A switch with no default is
 * deliberate — a sixth element type would be a compile error here rather than a silently dropped
 * piece of the path. */
static void fn_replay_element(void *info, const CGPathElement *e)
{
	fn_replay *r = info;
	CGPoint a;
	CGPoint b;
	CGPoint c;

	switch (e->type) {
	case kCGPathElementMoveToPoint:
		a = fn_mapped(r, &e->points[0]);
		CGPathMoveToPoint(r->dst, NULL, a.x, a.y);
		break;
	case kCGPathElementAddLineToPoint:
		a = fn_mapped(r, &e->points[0]);
		CGPathAddLineToPoint(r->dst, NULL, a.x, a.y);
		break;
	case kCGPathElementAddQuadCurveToPoint:
		a = fn_mapped(r, &e->points[0]);
		b = fn_mapped(r, &e->points[1]);
		CGPathAddQuadCurveToPoint(r->dst, NULL, a.x, a.y, b.x, b.y);
		break;
	case kCGPathElementAddCurveToPoint:
		a = fn_mapped(r, &e->points[0]);
		b = fn_mapped(r, &e->points[1]);
		c = fn_mapped(r, &e->points[2]);
		CGPathAddCurveToPoint(r->dst, NULL, a.x, a.y, b.x, b.y, c.x, c.y);
		break;
	case kCGPathElementCloseSubpath:
		CGPathCloseSubpath(r->dst);
		break;
	}
}

/* A FRESH MUTABLE COPY OF A PATH, BY REPLAY — because `CGPathCreateMutableCopy` DOES NOT EXIST here.
 * `CGPath.h` has `CGPathCreateMutable`, the three `CreateWith*` forms, `CGPathCreateCopyBy{Dashing,
 * Flattening,Stroking}` and `CGPathRetain`, and NO mutable copy — the third time in this file that
 * Apple's Core Graphics and this library's were mistaken for each other. */
static CGMutablePathRef fn_copy_path(CGPathRef src)
{
	fn_replay r;
	CGMutablePathRef dst = CGPathCreateMutable();

	if (dst == NULL) {
		return NULL;
	}
	r.dst = dst;
	r.transform = 0;
	if (src != NULL) {
		CGPathApply(src, &r, fn_replay_element);
	}
	return dst;
}

/* AN ELEMENT COUNTER, for the same reason: Core Graphics walks a path by CALLBACK rather than
 * answering a count. */
static void fn_count_element(void *info, const CGPathElement *element)
{
	(void)element;
	(*(NSInteger *)info)++;
}

/* THE TEN LEGACY CASE NAMES, DEFINED HERE. Each carries its LIVE case's value, so the two spellings are one
 * number and a ported caller's `NSButtLineCapStyle` reaches the same cap the modern spelling does. See the
 * header for the two that are NOT here — their era values collide with DIFFERENT modern cases — and for the
 * four glyph doors, which need a class this tree does not have. */
const NSLineCapStyle NSButtLineCapStyle = NSLineCapStyleButt;
const NSLineCapStyle NSRoundLineCapStyle = NSLineCapStyleRound;
const NSLineCapStyle NSSquareLineCapStyle = NSLineCapStyleSquare;
const NSLineJoinStyle NSMiterLineJoinStyle = NSLineJoinStyleMiter;
const NSLineJoinStyle NSRoundLineJoinStyle = NSLineJoinStyleRound;
const NSLineJoinStyle NSBevelLineJoinStyle = NSLineJoinStyleBevel;
const NSWindingRule NSNonZeroWindingRule = NSWindingRuleNonZero;
const NSWindingRule NSEvenOddWindingRule = NSWindingRuleEvenOdd;
const NSBezierPathElement NSMoveToBezierPathElement = NSBezierPathElementMoveTo;
const NSBezierPathElement NSLineToBezierPathElement = NSBezierPathElementLineTo;

@implementation NSBezierPath

+ (NSBezierPath *)bezierPath
{
	return [[[self alloc] init] autorelease];
}

+ (NSBezierPath *)bezierPathWithCGPath:(CGPathRef)cgPath
{
	NSBezierPath *p;

	if (cgPath == NULL) {
		return nil;
	}
	p = [[self alloc] init];
	if (p == nil) {
		return nil;
	}
	/* THE CALLER'S PATH IS COPIED INTO A MUTABLE ONE, because a path this class was handed may be
	 * immutable and this class builds on its own. Retaining it would make `-lineToPoint:` a crash. */
	CGPathRelease((CGPathRef)p->_path);
	p->_path = fn_copy_path(cgPath);
	return [p autorelease];
}

- (nullable CGPathRef)CGPath
{
	return _path;
}

- (instancetype)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_path = CGPathCreateMutable();
	if (_path == NULL) {
		[self release];
		return nil;
	}
	_lineWidth = fn_default_line_width;
	_miterLimit = fn_default_miter_limit;
	_capStyle = fn_default_cap;
	_joinStyle = fn_default_join;
	_windingRule = fn_default_winding;
	return self;
}

- (void)dealloc
{
	CGPathRelease((CGPathRef)_path);
	[super dealloc];
}

- (id)copy
{
	NSBezierPath *c = [[[self class] alloc] init];
	NSUInteger i;

	if (c == nil) {
		return nil;
	}
	CGPathRelease((CGPathRef)c->_path);
	c->_path = fn_copy_path((CGPathRef)_path);
	c->_lineWidth = _lineWidth;
	c->_miterLimit = _miterLimit;
	c->_capStyle = _capStyle;
	c->_joinStyle = _joinStyle;
	c->_windingRule = _windingRule;
	c->_dashCount = _dashCount;
	c->_dashPhase = _dashPhase;
	for (i = 0; i < _dashCount && i < APPKIT_DASH_MAX; i++) {
		c->_dash[i] = _dash[i];
	}
	return c;
}

/* --- the shape constructors --------------------------------------------------- */

+ (NSBezierPath *)bezierPathWithRect:(NSRect)rect
{
	NSBezierPath *p = [self bezierPath];

	[p appendBezierPathWithRect:rect];
	return p;
}

+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)rect
{
	NSBezierPath *p = [self bezierPath];

	[p appendBezierPathWithOvalInRect:rect];
	return p;
}

+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xRadius
				    yRadius:(CGFloat)yRadius
{
	NSBezierPath *p = [self bezierPath];

	[p appendBezierPathWithRoundedRect:rect xRadius:xRadius yRadius:yRadius];
	return p;
}

/* --- building it -------------------------------------------------------------- */

- (void)moveToPoint:(NSPoint)point
{
	CGPathMoveToPoint(_path, NULL, point.x, point.y);
}

- (void)lineToPoint:(NSPoint)point
{
	CGPathAddLineToPoint(_path, NULL, point.x, point.y);
}

- (void)curveToPoint:(NSPoint)point controlPoint1:(NSPoint)controlPoint1
	controlPoint2:(NSPoint)controlPoint2
{
	CGPathAddCurveToPoint(_path, NULL, controlPoint1.x, controlPoint1.y, controlPoint2.x,
			      controlPoint2.y, point.x, point.y);
}

/* THE ONE-CONTROL-POINT FORM IS QUADRATIC, which is why it is not a cubic with a repeated control
 * point — the difference is visible in the curve. */
- (void)curveToPoint:(NSPoint)point controlPoint:(NSPoint)controlPoint
{
	CGPathAddQuadCurveToPoint(_path, NULL, controlPoint.x, controlPoint.y, point.x, point.y);
}

- (void)closePath
{
	CGPathCloseSubpath(_path);
}

- (void)relativeMoveToPoint:(NSPoint)point
{
	NSPoint here = [self currentPoint];

	[self moveToPoint:NSMakePoint(here.x + point.x, here.y + point.y)];
}

- (void)relativeLineToPoint:(NSPoint)point
{
	NSPoint here = [self currentPoint];

	[self lineToPoint:NSMakePoint(here.x + point.x, here.y + point.y)];
}

- (void)relativeCurveToPoint:(NSPoint)point controlPoint1:(NSPoint)controlPoint1
	     controlPoint2:(NSPoint)controlPoint2
{
	NSPoint here = [self currentPoint];

	[self curveToPoint:NSMakePoint(here.x + point.x, here.y + point.y)
	      controlPoint1:NSMakePoint(here.x + controlPoint1.x, here.y + controlPoint1.y)
	      controlPoint2:NSMakePoint(here.x + controlPoint2.x, here.y + controlPoint2.y)];
}

- (void)relativeCurveToPoint:(NSPoint)point controlPoint:(NSPoint)controlPoint
{
	NSPoint here = [self currentPoint];

	[self curveToPoint:NSMakePoint(here.x + point.x, here.y + point.y)
	      controlPoint:NSMakePoint(here.x + controlPoint.x, here.y + controlPoint.y)];
}

- (void)removeAllPoints
{
	CGPathRelease((CGPathRef)_path);
	_path = CGPathCreateMutable();
}

/* --- appending, which is the element replay ------------------------------------ */

- (void)appendBezierPath:(NSBezierPath *)path
{
	fn_replay r;

	if (path == nil || path->_path == NULL) {
		return;
	}
	r.dst = _path;
	r.transform = 0;
	CGPathApply((CGPathRef)path->_path, &r, fn_replay_element);
}

- (void)appendBezierPathWithPoints:(const NSPoint *)points count:(NSInteger)count
{
	NSInteger i;

	if (points == NULL || count <= 0) {
		return;
	}
	CGPathMoveToPoint(_path, NULL, points[0].x, points[0].y);
	for (i = 1; i < count; i++) {
		CGPathAddLineToPoint(_path, NULL, points[i].x, points[i].y);
	}
}

- (void)appendBezierPathWithRect:(NSRect)rect
{
	CGPathAddRect(_path, NULL, rect);
}

- (void)appendBezierPathWithOvalInRect:(NSRect)rect
{
	CGPathAddEllipseInRect(_path, NULL, rect);
}

- (void)appendBezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xRadius yRadius:(CGFloat)yRadius
{
	CGPathAddRoundedRect(_path, NULL, rect, xRadius, yRadius);
}

- (void)appendBezierPathWithArcFromPoint:(NSPoint)point1 toPoint:(NSPoint)point2 radius:(CGFloat)radius
{
	CGPathAddArcToPoint(_path, NULL, point1.x, point1.y, point2.x, point2.y, radius);
}

- (void)appendBezierPathWithArcWithCenter:(NSPoint)center radius:(CGFloat)radius
			       startAngle:(CGFloat)startAngle endAngle:(CGFloat)endAngle
{
	/* THE FOUR-ARGUMENT FORM SWEEPS COUNTERCLOCKWISE, Apple's default. */
	CGPathAddArc(_path, NULL, center.x, center.y, radius, fn_radians(startAngle),
		     fn_radians(endAngle), false);
}

- (void)appendBezierPathWithArcWithCenter:(NSPoint)center radius:(CGFloat)radius
			       startAngle:(CGFloat)startAngle endAngle:(CGFloat)endAngle
				clockwise:(BOOL)clockwise
{
	CGPathAddArc(_path, NULL, center.x, center.y, radius, fn_radians(startAngle),
		     fn_radians(endAngle), clockwise ? true : false);
}

/* --- what it is -------------------------------------------------------------- */

- (NSRect)bounds
{
	/* THE PATH'S OWN BOX; `-controlPointBounds` is the control-point-INCLUSIVE one. That is the
	 * distinction CGPath.h draws between its two functions, attached to the names the way each name
	 * reads. */
	return CGPathGetPathBoundingBox((CGPathRef)_path);
}

- (NSRect)controlPointBounds
{
	return CGPathGetBoundingBox((CGPathRef)_path);
}

- (NSPoint)currentPoint
{
	return CGPathGetCurrentPoint((CGPathRef)_path);
}

- (BOOL)isEmpty
{
	return CGPathIsEmpty((CGPathRef)_path) ? YES : NO;
}

- (NSInteger)elementCount
{
	NSInteger n = 0;

	CGPathApply((CGPathRef)_path, &n, fn_count_element);
	return n;
}

/* --- the line state ---------------------------------------------------------- */

- (NSWindingRule)windingRule
{
	return _windingRule;
}

- (void)setWindingRule:(NSWindingRule)windingRule
{
	_windingRule = windingRule;
}

- (NSLineCapStyle)lineCapStyle
{
	return _capStyle;
}

- (void)setLineCapStyle:(NSLineCapStyle)lineCapStyle
{
	_capStyle = lineCapStyle;
}

- (NSLineJoinStyle)lineJoinStyle
{
	return _joinStyle;
}

- (void)setLineJoinStyle:(NSLineJoinStyle)lineJoinStyle
{
	_joinStyle = lineJoinStyle;
}

- (CGFloat)lineWidth
{
	return _lineWidth;
}

- (void)setLineWidth:(CGFloat)lineWidth
{
	_lineWidth = lineWidth;
}

- (CGFloat)miterLimit
{
	return _miterLimit;
}

- (void)setMiterLimit:(CGFloat)miterLimit
{
	_miterLimit = miterLimit;
}

- (void)setLineDash:(nullable const CGFloat *)pattern count:(NSInteger)count phase:(CGFloat)phase
{
	NSInteger i;

	if (pattern == NULL || count <= 0) {
		_dashCount = 0;
		_dashPhase = 0.0;
		return;
	}
	if (count > APPKIT_DASH_MAX) {
		fprintf(stderr, "APPKIT-REFUSE: a dash pattern of %d entries does not fit this class's "
				"%d, and truncating it would draw dashes the caller did not ask for\n",
			(int)count, APPKIT_DASH_MAX);
		return;
	}
	for (i = 0; i < count; i++) {
		_dash[i] = pattern[i];
	}
	_dashCount = (NSUInteger)count;
	_dashPhase = phase;
}

- (void)getLineDash:(nullable CGFloat *)pattern count:(nullable NSInteger *)count
	      phase:(nullable CGFloat *)phase
{
	NSUInteger i;

	if (pattern != NULL) {
		for (i = 0; i < _dashCount; i++) {
			pattern[i] = _dash[i];
		}
	}
	if (count != NULL) {
		*count = (NSInteger)_dashCount;
	}
	if (phase != NULL) {
		*phase = _dashPhase;
	}
}

/* --- the defaults ------------------------------------------------------------ */

+ (NSWindingRule)defaultWindingRule
{
	return fn_default_winding;
}

+ (void)setDefaultWindingRule:(NSWindingRule)windingRule
{
	fn_default_winding = windingRule;
}

+ (NSLineCapStyle)defaultLineCapStyle
{
	return fn_default_cap;
}

+ (void)setDefaultLineCapStyle:(NSLineCapStyle)lineCapStyle
{
	fn_default_cap = lineCapStyle;
}

+ (NSLineJoinStyle)defaultLineJoinStyle
{
	return fn_default_join;
}

+ (void)setDefaultLineJoinStyle:(NSLineJoinStyle)lineJoinStyle
{
	fn_default_join = lineJoinStyle;
}

+ (CGFloat)defaultLineWidth
{
	return fn_default_line_width;
}

+ (void)setDefaultLineWidth:(CGFloat)lineWidth
{
	fn_default_line_width = lineWidth;
}

+ (CGFloat)defaultMiterLimit
{
	return fn_default_miter_limit;
}

+ (void)setDefaultMiterLimit:(CGFloat)miterLimit
{
	fn_default_miter_limit = miterLimit;
}

/* --- drawing ----------------------------------------------------------------- */

/* THE CONTEXT A PATH DRAWS INTO IS THE CURRENT ONE — there is no argument for it, which is the
 * AppKit's model and the reason this class needs NSGraphicsContext at all. A nil context means there
 * is nothing to draw into, and NSBezierPath.h says so. */
static CGContextRef fn_current(void)
{
	return [[NSGraphicsContext currentContext] CGContext];
}

- (void)fn_apply_line_state:(CGContextRef)ctx
{
	CGContextSetLineWidth(ctx, _lineWidth);
	CGContextSetLineCap(ctx, fn_cap(_capStyle));
	CGContextSetLineJoin(ctx, fn_join(_joinStyle));
	CGContextSetMiterLimit(ctx, _miterLimit);
	CGContextSetLineDash(ctx, _dashPhase, _dashCount > 0 ? _dash : NULL, _dashCount);
}

- (void)fill
{
	CGContextRef ctx = fn_current();

	if (ctx == NULL) {
		return;
	}
	CGContextAddPath(ctx, (CGPathRef)_path);
	CGContextDrawPath(ctx, _windingRule == NSWindingRuleEvenOdd ? kCGPathEOFill : kCGPathFill);
}

- (void)stroke
{
	CGContextRef ctx = fn_current();

	if (ctx == NULL) {
		return;
	}
	[self fn_apply_line_state:ctx];
	CGContextAddPath(ctx, (CGPathRef)_path);
	CGContextDrawPath(ctx, kCGPathStroke);
}

/* THE CLIP FAMILY. Each reaches the CURRENT context, and the refusal a caller may meet is
 * CoreGraphics' own (a non-rectilinear path) rather than a second copy of the rule here. */
- (void)addClip
{
	CGContextRef ctx = fn_current();

	if (ctx == NULL) {
		return;
	}
	/* THE PATH GOES INTO THE CONTEXT AND THE CLIP CONSUMES IT THERE — `_path` is this object's and is
	 * NOT touched, which is why a caller may clip with the same path twice. */
	CGContextAddPath(ctx, (CGPathRef)_path);
	if (_windingRule == NSWindingRuleEvenOdd) {
		CGContextEOClip(ctx);
	} else {
		CGContextClip(ctx);
	}
}

- (void)setClip
{
	CGContextRef ctx = fn_current();

	if (ctx == NULL) {
		return;
	}
	/* RESET THEN INTERSECT IS A REPLACE, and the correction that took: the clip CoreGraphics stores is
	 * built in DEVICE space from the already-transformed path, so there is no transform to be wrong
	 * about. See the header. */
	CGContextResetClip(ctx);
	[self addClip];
}

+ (void)clipRect:(NSRect)rect
{
	CGContextRef ctx = fn_current();

	if (ctx == NULL) {
		return;
	}
	CGContextClipToRect(ctx, rect);
}

/* ------------------------------------------------------------------------- */
/* the element model, read back                                              */
/* ------------------------------------------------------------------------- */

typedef struct {
	NSInteger want;			/* the index being asked for */
	NSInteger seen;			/* how many elements have gone by */
	NSBezierPathElement got;
	CGPoint pts[3];
	int npts;
	BOOL found;
} fn_element_query;

/* THE FIVE CASES ARE THE WHOLE ENUM, which is `NSBezierPathElement`'s payoff for omitting the
 * deprecated `CurveTo`: there is no ambiguous element to fall back to, so this switch is total. */
static NSBezierPathElement fn_element_of(CGPathElementType t, int *npts)
{
	switch (t) {
	case kCGPathElementMoveToPoint:
		*npts = 1;
		return NSBezierPathElementMoveTo;
	case kCGPathElementAddLineToPoint:
		*npts = 1;
		return NSBezierPathElementLineTo;
	case kCGPathElementAddQuadCurveToPoint:
		*npts = 2;
		return NSBezierPathElementQuadraticCurveTo;
	case kCGPathElementAddCurveToPoint:
		*npts = 3;
		return NSBezierPathElementCubicCurveTo;
	case kCGPathElementCloseSubpath:
		break;
	}
	*npts = 0;
	return NSBezierPathElementClosePath;
}

static void fn_element_at(void *info, const CGPathElement *e)
{
	fn_element_query *q = info;
	NSBezierPathElement kind;
	int n = 0;
	int i;

	if (q->found) {
		return;
	}
	kind = fn_element_of(e->type, &n);
	if (q->seen != q->want) {
		q->seen++;
		return;
	}
	/* THE POINTS ARE THE PATH'S OWN, in the space this object was built in: a path has no transform,
	 * so there is nothing to map them through. */
	q->got = kind;
	q->npts = n;
	for (i = 0; i < n; i++) {
		q->pts[i] = e->points[i];
	}
	q->found = YES;
}

- (NSBezierPathElement)elementAtIndex:(NSInteger)index
{
	return [self elementAtIndex:index associatedPoints:NULL];
}

- (NSBezierPathElement)elementAtIndex:(NSInteger)index associatedPoints:(nullable NSPointArray)points
{
	fn_element_query q;
	NSInteger i;

	memset(&q, 0, sizeof(q));
	q.want = index;
	CGPathApply((CGPathRef)_path, &q, fn_element_at);
	if (!q.found) {
		/* REFUSED BY NAME RATHER THAN RAISED: Apple raises for an index past the end, and this tree's
		 * rule for an ordinary mistake is a stated refusal. The answer is MoveTo because that is the
		 * only element with no points, so a caller that ignores the refusal cannot read uninitialised
		 * memory out of `points`. */
		fprintf(stderr, "APPKIT-REFUSE: -elementAtIndex: %ld is past the end of this path (%lu "
				"element(s))\n", (long)index, (unsigned long)[self elementCount]);
		return NSBezierPathElementMoveTo;
	}
	if (points != NULL) {
		for (i = 0; i < q.npts; i++) {
			points[i] = q.pts[i];
		}
	}
	return q.got;
}

/* ------------------------------------------------------------------------- */
/* the point-in-path test                                                    */
/* ------------------------------------------------------------------------- */

typedef struct {
	CGFloat px;
	CGFloat py;
	NSInteger cross;	/* how many edges cross the ray to the right */
	NSInteger wind;		/* and the net direction of those crossings */
	CGPoint prev;
	CGPoint sub;		/* the subpath's first point, for the closing edge */
	BOOL have;
} fn_hit;

/* THE STANDARD HALF-OPEN CROSSING TEST: the ray is the horizontal line through the point, and one
 * endpoint is compared inclusively and the other exclusively (`>` on both) so that a vertex lying
 * exactly at the point's height is counted ONCE rather than twice or not at all. */
static void fn_cross(fn_hit *h, CGPoint a, CGPoint b)
{
	if ((a.y > h->py) != (b.y > h->py)) {
		CGFloat t = (h->py - a.y) / (b.y - a.y);
		CGFloat x = a.x + t * (b.x - a.x);

		if (h->px < x) {
			h->cross++;
			h->wind += (b.y > a.y) ? 1 : -1;
		}
	}
}

static void fn_hit_edge(void *info, const CGPathElement *e)
{
	fn_hit *h = info;
	CGPoint p;

	switch (e->type) {
	case kCGPathElementMoveToPoint:
		h->prev = e->points[0];
		h->sub = e->points[0];
		h->have = YES;
		break;
	case kCGPathElementAddLineToPoint:
		p = e->points[0];
		if (h->have) {
			fn_cross(h, h->prev, p);
		}
		h->prev = p;
		break;
	case kCGPathElementAddQuadCurveToPoint:
	case kCGPathElementAddCurveToPoint:
		/* A FLATTENED PATH SHOULD HOLD NO CURVES AT ALL. One that survived is treated as the straight
		 * line to its ENDPOINT — stated because the alternative, ignoring it, would silently drop an
		 * edge and could turn an inside point into an outside one. */
		p = e->points[e->type == kCGPathElementAddCurveToPoint ? 2 : 1];
		if (h->have) {
			fn_cross(h, h->prev, p);
		}
		h->prev = p;
		break;
	case kCGPathElementCloseSubpath:
		if (h->have) {
			fn_cross(h, h->prev, h->sub);
		}
		h->prev = h->sub;
		break;
	}
}

- (BOOL)containsPoint:(NSPoint)point
{
	CGPathRef flat = CGPathCreateCopyByFlattening((CGPathRef)_path, 0.1);
	fn_hit h;

	if (flat == NULL) {
		return NO;
	}
	h.px = point.x;
	h.py = point.y;
	h.cross = 0;
	h.wind = 0;
	h.have = NO;
	CGPathApply(flat, &h, fn_hit_edge);
	CGPathRelease(flat);
	/* THE PATH'S OWN WINDING RULE DECIDES, which is the promise `-containsPoint:` makes: even-odd
	 * counts the crossings, non-zero asks whether they cancel. */
	if (_windingRule == NSWindingRuleEvenOdd) {
		return (h.cross & 1) != 0;
	}
	return h.wind != 0;
}

/* ---- THE REVERSING COPY, AND IT IS REAL GEOMETRY ---------------------------------------------- *
 * `CGPath` HAS NO REVERSING OPERATION — that was this header's ground for leaving the door out, and it is
 * true. What made the door owed anyway is that the work is SYNTHESISABLE from the element model this class
 * already reads back (`-elementCount`, `-elementAtIndex:associatedPoints:`, and `CGPathApply` underneath),
 * and a row is shipped or struck rather than parked behind "that would be work".
 *
 * THE WALK COLLECTS THE ELEMENTS FIRST and rebuilds them CONTOUR BY CONTOUR, because reversing a whole path's
 * element list is wrong in three ways that are worth naming, since each is a silent wrongness rather than a
 * crash:
 *
 *   A CUBIC'S TWO CONTROL POINTS SWAP. The curve back starts where the forward one ended, so it is guided
 *   by the SECOND control point first: `curveToPoint:P c1:A c2:B` reverses to `curveToPoint:S c1:B c2:A`.
 *   A NAIVE ORDER-REVERSAL keeps A and B in place and draws a different curve.
 *   A QUADRATIC'S ONE CONTROL POINT DOES NOT. It is the same point either way; only the ends trade places.
 *   AND A CLOSED CONTOUR STARTS AT ITS MOVE POINT, not at its last point: the closing line is part of the
 *   contour, so the reversed path emits it FIRST (as a line from the move point to where the contour was
 *   last), walks the segments back, and closes.
 *
 * THE LINE STATE COMES ACROSS TOO, exactly as `-bezierPathByFlatteningPath` carries it: a reversed path is
 * meant to draw the same way, so the width, the limit, the cap, the join, the winding rule, the flatness and
 * the cache switch all survive the copy. */
typedef struct {
	int kind;		/* one of CGPath's kCGPathElement* values */
	NSPoint before;		/* the current point when this element was applied */
	NSPoint p[3];		/* the element's own points; 1, 2 or 3 of them are meaningful */
} fn_rev_elem;

typedef struct {
	fn_rev_elem *elems;
	NSPoint cur;
	NSInteger count;
} fn_rev_ctx;

static void fn_rev_collect(void *info, const CGPathElement *e)
{
	fn_rev_ctx *c = (fn_rev_ctx *)info;
	fn_rev_elem *r = &c->elems[c->count];
	NSInteger i;

	r->kind = (int)e->type;
	r->before = c->cur;
	for (i = 0; i < 3; i++) {
		r->p[i] = NSMakePoint(0.0, 0.0);
	}
	switch (e->type) {
	case kCGPathElementMoveToPoint:
		r->p[0] = e->points[0];
		c->cur = r->p[0];
		break;
	case kCGPathElementAddLineToPoint:
		r->p[0] = e->points[0];
		c->cur = r->p[0];
		break;
	case kCGPathElementAddQuadCurveToPoint:
		r->p[0] = e->points[0];
		r->p[1] = e->points[1];
		c->cur = r->p[1];
		break;
	case kCGPathElementAddCurveToPoint:
		r->p[0] = e->points[0];
		r->p[1] = e->points[1];
		r->p[2] = e->points[2];
		c->cur = r->p[2];
		break;
	default:
		/* A CLOSE MOVES NOTHING, which is why the current point is left alone. */
		break;
	}
	c->count++;
}

static NSPoint fn_rev_end(const fn_rev_elem *r)
{
	switch (r->kind) {
	case kCGPathElementMoveToPoint:
	case kCGPathElementAddLineToPoint:
		return r->p[0];
	case kCGPathElementAddQuadCurveToPoint:
		return r->p[1];
	case kCGPathElementAddCurveToPoint:
		return r->p[2];
	default:
		return r->before;
	}
}

/* AND THE SEGMENT BACK: it starts where the forward segment ended and ends where it started. */
static void fn_rev_emit(CGMutablePathRef out, const fn_rev_elem *r)
{
	switch (r->kind) {
	case kCGPathElementAddLineToPoint:
		CGPathAddLineToPoint(out, NULL, r->before.x, r->before.y);
		break;
	case kCGPathElementAddQuadCurveToPoint:
		CGPathAddQuadCurveToPoint(out, NULL, r->p[0].x, r->p[0].y, r->before.x, r->before.y);
		break;
	case kCGPathElementAddCurveToPoint:
		CGPathAddCurveToPoint(out, NULL, r->p[1].x, r->p[1].y, r->p[0].x, r->p[0].y,
				      r->before.x, r->before.y);
		break;
	default:
		break;
	}
}

- (NSBezierPath *)bezierPathByReversingPath
{
	fn_rev_ctx c;
	fn_rev_elem *elems;
	CGMutablePathRef out;
	NSBezierPath *p;
	NSInteger total, i;

	total = [self elementCount];
	if (total <= 0) {
		/* AN EMPTY PATH REVERSES TO AN EMPTY PATH, which is the whole truth rather than a refusal. */
		return [[self class] bezierPath];
	}
	elems = (fn_rev_elem *)malloc(sizeof(*elems) * (size_t)total);
	if (elems == NULL) {
		return nil;
	}
	c.elems = elems;
	c.count = 0;
	c.cur = NSMakePoint(0.0, 0.0);
	CGPathApply((CGPathRef)_path, &c, fn_rev_collect);

	out = CGPathCreateMutable();
	if (out == NULL) {
		free(elems);
		return nil;
	}
	i = 0;
	while (i < c.count) {
		NSInteger e = i + 1;
		BOOL closed = NO;
		NSInteger j;

		/* THE CONTOUR RUNS TO THE NEXT MOVE ELEMENT, or to the end of the path. */
		while (e < c.count && elems[e].kind != kCGPathElementMoveToPoint) {
			e++;
		}
		if (e > i + 1 && elems[e - 1].kind == kCGPathElementCloseSubpath) {
			closed = YES;
		}
		if (closed) {
			/* THE MOVE POINT IS THE START EITHER WAY, and the reversed CLOSING LINE goes first — from it
			 * to wherever the contour was last, which is the close element's own `before`. */
			CGPathMoveToPoint(out, NULL, elems[i].p[0].x, elems[i].p[0].y);
			CGPathAddLineToPoint(out, NULL, elems[e - 1].before.x, elems[e - 1].before.y);
			for (j = e - 2; j > i; j--) {
				fn_rev_emit(out, &elems[j]);
			}
			CGPathCloseSubpath(out);
		} else {
			NSPoint last = fn_rev_end(&elems[e - 1]);

			CGPathMoveToPoint(out, NULL, last.x, last.y);
			for (j = e - 1; j > i; j--) {
				fn_rev_emit(out, &elems[j]);
			}
		}
		i = e;
	}
	free(elems);

	p = [[self class] bezierPathWithCGPath:out];
	CGPathRelease(out);
	if (p != nil) {
		p->_lineWidth = _lineWidth;
		p->_miterLimit = _miterLimit;
		p->_capStyle = _capStyle;
		p->_joinStyle = _joinStyle;
		p->_windingRule = _windingRule;
		p->_flatness = _flatness;
		p->_flatnessSet = _flatnessSet;
		p->_cachesBezierPath = _cachesBezierPath;
	}
	return p;
}

- (NSBezierPath *)bezierPathByFlatteningPath
{
	NSBezierPath *p;
	CGPathRef flat;

	/* THE TOLERANCE IS THIS LIBRARY'S OWN AND NOT A SETTABLE FLATNESS: the flatness family is deferred
	 * (NSBezierPath.h says why), and 0.1 is the device-space tolerance the context's own flattener
	 * uses. A caller with a different tolerance has no way to say so YET, which is the honest state of
	 * it. */
	flat = CGPathCreateCopyByFlattening((CGPathRef)_path, 0.1);
	if (flat == NULL) {
		return nil;
	}
	p = [[self class] bezierPathWithCGPath:flat];
	CGPathRelease(flat);
	if (p != nil) {
		/* THE LINE STATE COMES ACROSS TOO, because a flattened path is meant to draw the same way. */
		p->_lineWidth = _lineWidth;
		p->_miterLimit = _miterLimit;
		p->_capStyle = _capStyle;
		p->_joinStyle = _joinStyle;
		p->_windingRule = _windingRule;
		p->_dashCount = _dashCount;
		p->_dashPhase = _dashPhase;
	}
	return p;
}

- (void)transformUsingAffineTransform:(NSAffineTransform *)transform
{
	fn_replay r;
	CGMutablePathRef dst;
	NSAffineTransformStruct s;

	if (transform == nil) {
		return;
	}
	s = [transform transformStruct];
	r.t = CGAffineTransformMake(s.m11, s.m12, s.m21, s.m22, s.tX, s.tY);
	r.transform = 1;
	dst = CGPathCreateMutable();
	if (dst == NULL) {
		return;
	}
	r.dst = dst;
	CGPathApply((CGPathRef)_path, &r, fn_replay_element);
	CGPathRelease((CGPathRef)_path);
	_path = dst;
}

/* --- the class helpers ------------------------------------------------------- */

+ (void)fillRect:(NSRect)rect
{
	[[self bezierPathWithRect:rect] fill];
}

+ (void)strokeRect:(NSRect)rect
{
	[[self bezierPathWithRect:rect] stroke];
}

+ (void)strokeLineFromPoint:(NSPoint)point1 toPoint:(NSPoint)point2
{
	NSBezierPath *p = [self bezierPath];

	[p moveToPoint:point1];
	[p lineToPoint:point2];
	[p stroke];
}


/* ---- THE ERA'S LAST DOORS ------------------------------------------------------------------- */

- (BOOL)cachesBezierPath
{
	return _cachesBezierPath;
}

- (void)setCachesBezierPath:(BOOL)flag
{
	_cachesBezierPath = flag;
}

- (void)setAssociatedPoints:(NSPointArray)points
{
	/* REFUSED BY NAME, AND THE REASON IS THE SUBSTRATE RATHER THAN AN OMISSION: an element's points live in
	 * the CGPath this object holds, and a CGPath is APPEND-ONLY — there is no call that changes what an
	 * existing element's points are. Rebuilding the whole path to change one element would be a second
	 * implementation of the geometry this class already delegates, so the door says what it cannot do. */
	(void)points;
	fprintf(stderr, "APPKIT-REFUSE: -setAssociatedPoints: rewrites the points of the last-added element, "
			"and this class adds straight to a CGMutablePathRef — a CGPath is append-only, so there "
			"is no element to rewrite (read them with -elementAtIndex:associatedPoints: instead)\n");
}

/* THE INDEXED SPELLING OF THE SAME REFUSAL. See the header: naming an element does not make a CGPath rewritable. */
- (void)setAssociatedPoints:(NSPointArray)points atIndex:(NSInteger)index
{
	(void)points;
	fprintf(stderr, "APPKIT-REFUSE: -setAssociatedPoints:atIndex: rewrites the points of an existing element "
			"(index %ld) and this class adds straight to a CGMutablePathRef — a CGPath is append-only, so "
			"there is no element to rewrite (read them with -elementAtIndex:associatedPoints: instead)\n",
			(long)index);
}

/* ---- THE FOUR GLYPH DOORS, EACH REFUSED BY NAME ---------------------------------------------- *
 * Every one of them needs a FONT: three take an `NSFont` outright and the fourth takes the glyphs a font
 * would have produced. NSFont is stage F's largest class and the glyph-outline machinery lives there, so
 * there is nothing to synthesise from — and a door that quietly appended NOTHING would hand back a path
 * the caller believes contains letterforms, which is the silent wrongness this class refuses elsewhere
 * (`-setAssociatedPoints:` above is refused for the same kind of reason).
 *
 * NONE OF THEM TOUCHES THE PATH, and that is asserted rather than assumed: the probe checks the element
 * count before and after all four. */
static void fn_refuse_glyph(const char *which)
{
	fprintf(stderr, "APPKIT-REFUSE: %s needs NSFont — and the glyph outlines it would produce — which is "
			"stage F's work and not in this tier; the path is left unchanged\n", which);
}

+ (void)drawPackedGlyphs:(const char *)packedGlyphs atPoint:(NSPoint)point
{
	(void)packedGlyphs;
	(void)point;
	fn_refuse_glyph("+drawPackedGlyphs:atPoint:");
}

- (void)appendBezierPathWithGlyph:(unsigned int)glyph inFont:(id)font
{
	(void)glyph;
	(void)font;
	fn_refuse_glyph("-appendBezierPathWithGlyph:inFont:");
}

- (void)appendBezierPathWithGlyphs:(const unsigned int *)glyphs
			     count:(NSInteger)count
			    inFont:(id)font
{
	(void)glyphs;
	(void)count;
	(void)font;
	fn_refuse_glyph("-appendBezierPathWithGlyphs:count:inFont:");
}

- (void)appendBezierPathWithPackedGlyphs:(const char *)packedGlyphs
{
	(void)packedGlyphs;
	fn_refuse_glyph("-appendBezierPathWithPackedGlyphs:");
}

/* ---- THE FLATNESS PAIR, STORED AND APPLIED ---------------------------------------------------- *
 * The header's old claim was that this family "would be stored and never read"; MEASUREMENT SAYS OTHERWISE
 * (the correction is written out in the header): this tier's CoreGraphics HAS `CGContextSetFlatness`, so the
 * setter has somewhere real to put the value — the current context's fill tolerance — exactly as
 * `-setShouldAntialias:` reaches `CGContextSetShouldAntialias` in NSGraphicsContext.
 *
 * THE DEFAULT IS APPLE'S DOCUMENTED 0.6, and it lives here beside the pair that reads and writes it rather
 * than among the other five at the top of the file, BECAUSE THIS UNIT DOES NOT TOUCH THE INITIALISER: the
 * consequence is the deviation the header states — a path with no opinion of its own reads the default LIVE
 * rather than taking a copy when it was created. One line in `-init`, beside its five siblings, is the fix,
 * and it is named in both places rather than left for a reader to discover. */
static CGFloat fn_default_flatness = 0.6;

- (CGFloat)flatness
{
	/* THIS PATH'S OWN OPINION WINS; without one, the class default — and THE FLAG is what makes "never
	 * told" distinguishable from "told zero", which a sentinel value could not do. */
	return _flatnessSet ? _flatness : fn_default_flatness;
}

- (void)setFlatness:(CGFloat)flatness
{
	NSGraphicsContext *g;

	_flatness = flatness;
	_flatnessSet = YES;
	/* AND IT REACHES THE CONTEXT WHEN THERE IS ONE, which is what makes this real state rather than a
	 * recorded number: the value a path was told becomes the tolerance its fill uses. */
	g = [NSGraphicsContext currentContext];
	if (g != nil && [g CGContext] != NULL) {
		CGContextSetFlatness([g CGContext], flatness);
	}
}

+ (CGFloat)defaultFlatness
{
	return fn_default_flatness;
}

+ (void)setDefaultFlatness:(CGFloat)flatness
{
	fn_default_flatness = flatness;
}

@end
