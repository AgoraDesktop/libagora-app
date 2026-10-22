/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSBezierPath.h — a path, and the first thing in this tree that DRAWS (C8.5).
 *
 * THE PATH IS A CGPath AND THE LINE STATE IS THE PATH'S OWN, WHICH IS THE ONE STRUCTURAL DIFFERENCE
 * FROM `CGContext`. Core Graphics keeps the line width, the caps, the joins, the dash and the winding
 * rule in the CONTEXT's graphics state, and a stroke is a context operation; AppKit keeps them ON THE
 * PATH, and `-stroke` is a message to the path. So this object owns a mutable `CGPath` PLUS the six
 * pieces of line state, and drawing means: hand the path to the current context, set the context's
 * line state from OURS, and ask the context to draw it. Nothing else is stored and nothing is cached,
 * which is why `-CGPath` can be handed back whole (Apple has the same pair, `+bezierPathWithCGPath:`
 * and `-CGPath`, on macOS 10.13+ and the ledger has both as live rows).
 *
 * THAT ASYMMETRY HAS A CONSEQUENCE A CALLER CAN SEE, so it is stated rather than discovered: a stroke
 * OVERWRITES the current context's line width, caps and joins with the path's. Apple does the same and
 * this library does not save and restore around it, because a save/restore the caller did not ask for
 * would hide their own state changes from them.
 *
 * THE SURFACE IS PINNED, NOT RECALLED, and the selectors came from Apple's navigator tree — the
 * ledger reduces a method to its FIRST selector component, so a header written from the ledger alone
 * would have guessed every tail. Three enums (`NSLineCapStyle`, `NSLineJoinStyle`, `NSWindingRule`)
 * and their seven cases are here, because Apple's index files them under this class.
 *
 * WHAT IS NOT HERE, EACH WITH ITS REASON — AND TWO ENTRIES THAT USED TO STAND HERE ARE GONE BECAUSE THE
 * REASONS WERE WRONG RATHER THAN BECAUSE THE WORK BECAME EASY. Both are recorded where they were corrected,
 * so a reader who remembers the old text finds out what happened to it:
 *
 *   THE FLATNESS FAMILY WAS NOT A SILENT NO-OP, and it ships now. It used to read: "This library's flattener
 *   picks its own tolerance from the CTM ... A path flatness would therefore be stored and never read.
 *   Making it real means threading a tolerance through `CGContextDrawPath`, which is CoreGraphics work and
 *   not this class's." HALF OF THAT WAS TRUE AND THE HALF THAT DECIDED WAS FALSE: this tier's CoreGraphics
 *   HAS `CGContextSetFlatness`, so a path's flatness has a real destination — the current context's fill
 *   tolerance — exactly as `-setShouldAntialias:` has `CGContextSetShouldAntialias` behind it. See the
 *   declaration further down and appkit-plan.md §A10o.
 *
 *   AND `-bezierPathByReversingPath` SHIPS NOW. It used to read: "`CGPath` here has no reversing operation,
 *   and synthesising one is a real piece of geometry rather than a forward." BOTH HALVES WERE TRUE, AND THE
 *   SECOND IS THE PROBLEM: it describes the WORK rather than a missing substrate, and "that would be work"
 *   is not a ground this ledger parks a row on — a row is shipped or struck. The element model was already
 *   read back, so the synthesis had somewhere to start. See the declaration, which names the three things a
 *   naive order-reversal gets wrong, and §A10p.
 *
 *   AND THE PATH CLIP, WHICH IS HERE NOW BECAUSE COREGRAPHICS GREW ONE (C8.6): `-addClip`,
 *   `-setClip` and `+clipRect:` all forward to `CGContextClip`/`CGContextEOClip`/`CGContextClipToRect`,
 *   which did not exist when this class was first written. THEY INHERIT THAT CLIP'S BOUNDARY, and it is
 *   worth restating where a path author will meet it: a RECTILINEAR path clips EXACTLY, and a slanted
 *   or curved one clips too, through CoreGraphics' COVERAGE MASK half — which did not exist when this
 *   class was written and does now, so all three of these take any path shape. What remains refused at
 *   the CoreGraphics level is a clip under a ROTATED CTM, and the reason is stated there.
 *
 *   AND ONE SENTENCE OF THIS PARAGRAPH WAS WRONG AND STAYS CORRECTED: it said `-setClip` could not be
 *   built from reset-then-intersect because that "would be wrong under a transform". It is not wrong —
 *   the clip CoreGraphics stores is built in DEVICE space from the already-transformed path, so
 *   resetting and re-intersecting replaces the clip exactly, which is what `-setClip` means. The first
 *   version reasoned about the transform in USER space and drew the wrong conclusion.
 *
 *   AND DRAWING WITH NO CURRENT `NSGraphicsContext` DRAWS NOTHING, silently. That is Apple's
 *   behaviour by omission (there is no context to draw into) and it is stated here so a caller is not
 *   left wondering. The alternative — raising — would make an ordinary mistake fatal, and this tree's
 *   CoreGraphics entry points take the same position on a NULL context.
 *
 *   AND TWO OF THESE ARE NO LONGER TRUE, WHICH IS WHY THEY ARE STRUCK THROUGH HERE RATHER THAN DELETED:
 *   `-containsPoint:` was said to need a point-in-path test CoreGraphics does not have, and
 *   `-elementAtIndex:` to need its own slice — both are implemented now. The point-in-path test is a
 *   crossing count over the FLATTENED path (which this class can already produce), so it needs nothing
 *   from CoreGraphics that is not here; and the element model is declared above. The glyph constructors
 *   (`appendBezierPathWithCGGlyph…`, `+drawPackedGlyphs:atPoint:`) need `CGFont`, which this tree
 *   does not have.
 *
 * A DEVIATION, STATED: Apple's arc constructors take DEGREES with 0° along the positive x axis and
 * increasing counterclockwise; `CGPathAddArc` takes RADIANS. The conversion is here, in one place, and
 * the probe checks an arc's endpoint rather than trusting the arithmetic.
 */
#ifndef APPKIT_NSBEZIERPATH_H
#define APPKIT_NSBEZIERPATH_H

#import <CoreGraphics/CGAffineTransform.h>
#import <CoreGraphics/CGPath.h>
#import <Foundation/NSAffineTransform.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * THE THREE ENUMS APPLE FILES UNDER THIS CLASS. Every case maps one-to-one onto Core Graphics —
 * `NSLineCapStyleButt` IS `kCGLineCapButt` and so on — which is what makes the forwards below
 * one-liners. THE VALUES ARE OURS (Apple publishes case names and no numbers, the rule this tree
 * follows everywhere) and the mapping is an explicit switch rather than a cast, so an ordering that
 * differed could not silently swap two cases.
 */
typedef enum {
	NSLineCapStyleButt = 0,
	NSLineCapStyleRound,
	NSLineCapStyleSquare
} NSLineCapStyle;

typedef enum {
	NSLineJoinStyleMiter = 0,
	NSLineJoinStyleRound,
	NSLineJoinStyleBevel
} NSLineJoinStyle;

typedef enum {
	NSWindingRuleNonZero = 0,
	NSWindingRuleEvenOdd
} NSWindingRule;

/* NOT HERE, AND EACH AN OPEN ROW: the four glyph doors (`+drawPackedGlyphs:`,
 * `-appendBezierPathWithGlyph:inFont:`, `-appendBezierPathWithGlyphs:count:inFont:`,
 * `-appendBezierPathWithPackedGlyphs:`) each take an `NSFont` or an `NSGlyph`, and `NSFont` is a class this
 * tree does not have — a forward `@class NSFont;` written purely to satisfy those signatures would flip the
 * ledger's `class NSFont` row to shipped and claim a class we do not ship. They stay open, which is the same
 * ground NSImage's `-initWithIconRef:` and NSColor's two colour-space doors stand on.
 */
/* THE ELEMENT MODEL: WHAT A PATH IS MADE OF, one step at a time.
 *
 * **AND `NSBezierPathElementCurveTo` IS DELIBERATELY ABSENT BECAUSE IT IS A `struck` ROW** — Apple
 * deprecates it at the vintage this tree pins, and it has no legitimate producer: a curve element is
 * either QUADRATIC or CUBIC, and Apple's own paths never come back as the ambiguous one. So this is a
 * model without an unreachable value rather than a model with a hole, and `-elementAtIndex:` can
 * therefore be total. THE NUMBERS ARE OURS (the policy: Apple publishes case names, never values). */
typedef enum {
	NSBezierPathElementMoveTo = 0,
	NSBezierPathElementLineTo = 1,
	NSBezierPathElementQuadraticCurveTo = 2,
	NSBezierPathElementCubicCurveTo = 3,
	NSBezierPathElementClosePath = 4
} NSBezierPathElement;


/* ============================================================================================ *
 * THE ERA'S CASE NAMES, WHICH ARE NOT THE MODERN SPELLINGS OF THE SAME ENUMERATION.             *
 *                                                                                                *
 * 10.2 THROUGH 10.6 DECLARE THESE AS THE ENUM'S OWN CASES — `typedef enum { NSButtLineCapStyle,   *
 * NSRoundLineCapStyle, … } NSLineCapStyle;` — while the modern index names the same cases          *
 * `NSLineCapStyleButt` and so on. The ledger holds both families, and these rows are OWED          *
 * (deprecated, and therefore owed, per the 2026-09-26 policy), so the legacy spellings are here   *
 * as CONSTANTS carrying their live case's value — Apple's `var` shape, which is how the            *
 * `NSComposite…` aliases in NSGraphicsContext.h are declared and for the same reason.            *
 *                                                                                                *
 * **TWO OF THEM CANNOT BE ALIASES, AND THE REASON IS A MEASURED COLLISION RATHER THAN A PREFERENCE.** *
 * The era's element enumeration is MoveTo = 0, LineTo = 1, CurveTo = 2, ClosePath = 3, and the    *
 * modern one is MoveTo = 0, LineTo = 1, QuadraticCurveTo = 2, CubicCurveTo = 3, ClosePath = 4 —   *
 * the quadratic case was INSERTED in the middle and everything after it shifted. So the era's     *
 * `NSCurveToBezierPathElement` (2) would land on this tree's QUADRATIC case and its                  *
 * `NSClosePathBezierPathElement` (3) on the CUBIC one: each would name a curve of the wrong kind,  *
 * which is the silent wrongness this tier refuses to ship. Both rows therefore stay OPEN rather   *
 * than aliased — era API we have not shipped, and the visible form of that decision.              *
 */
extern const NSLineCapStyle NSButtLineCapStyle;
extern const NSLineCapStyle NSRoundLineCapStyle;
extern const NSLineCapStyle NSSquareLineCapStyle;
extern const NSLineJoinStyle NSMiterLineJoinStyle;
extern const NSLineJoinStyle NSRoundLineJoinStyle;
extern const NSLineJoinStyle NSBevelLineJoinStyle;
extern const NSWindingRule NSNonZeroWindingRule;
extern const NSWindingRule NSEvenOddWindingRule;
extern const NSBezierPathElement NSMoveToBezierPathElement;
extern const NSBezierPathElement NSLineToBezierPathElement;

@interface NSBezierPath : NSObject <NSCopying>
{
	CGMutablePathRef _path;     /* RETAINED, and the geometry */
	NSWindingRule _windingRule;
	NSLineCapStyle _capStyle;
	NSLineJoinStyle _joinStyle;
	CGFloat _lineWidth;
	CGFloat _miterLimit;
	/* A BOUNDED DASH ARRAY IN THE OBJECT, for the reason the graphics state's is bounded: a dash
	 * pattern is a handful of numbers, and a caller's array must not become a pointer this object
	 * keeps after the call returns. */
	CGFloat _dash[16];
	NSUInteger _dashCount;
	CGFloat _dashPhase;
	/* THE CACHE SWITCH, RECORDED AND NOT ACTED ON — there is no cache here, so what the getter
	 * can truthfully answer is what its setter was told. Apple deprecated the pair and its own
	 * documentation says a caller can drop its use, which is the ground NSImage's four cache
	 * switches stand on. */
	BOOL _cachesBezierPath;
	/* AND THE FLATNESS THE PATH WAS TOLD, with the flag that tells "never told" from "told zero" — a
	 * sentinel value could not tell those apart, and zero is a legal flatness. */
	CGFloat _flatness;
	BOOL _flatnessSet;
}

/* ============================================================================================ *
 * THE FLATNESS PAIR, WHICH THIS HEADER ONCE CALLED A SILENT NO-OP AND MEASUREMENT DISPROVED.     *
 * ============================================================================================ *
 *
 * The note above said the family "would be stored and never read ... this library's flattener picks its own
 * tolerance from the CTM and the CONTEXT's fill is what flattens". THAT IS HALF TRUE, AND THE HALF THAT IS
 * FALSE IS THE ONE THAT DECIDES: **this tier's CoreGraphics HAS `CGContextSetFlatness`** (`CGContext.h:520`,
 * whose own comment says what it does to the fill's tolerance), so a path's flatness has somewhere real to
 * go — the current context's fill tolerance — exactly as `NSGraphicsContext`'s `-setShouldAntialias:` has
 * `CGContextSetShouldAntialias` behind it.
 *
 * SO IT IS STORED **AND APPLIED**, THE SHAPE `-miterLimit` BESIDE IT ALREADY HAS: remembered per path
 * (Apple's own contract — a path's flatness is the path's), the class default is what a path answers when it
 * has no opinion of its own, and the setter also pushes the value to the current context when there is one.
 *
 * AND THE DEFAULT IS APPLE'S DOCUMENTED **0.6**, the same way `-miterLimit`'s 10.0 is.
 *
 * ONE DEVIATION IS STATED RATHER THAN HIDDEN: the five defaults beside this one are SNAPSHOTTED into a path
 * when it is created, and flatness is READ LIVE while the path has no opinion of its own — so
 * `+setDefaultFlatness:` reaches an existing path that has never set one, where Apple's rule ("the defaults
 * are consulted when a path is created") would not. The fix is one line in `-init`, beside its five
 * siblings, and it is NAMED HERE because a reader comparing the two behaviours would otherwise find it
 * unexplained. */
@property CGFloat flatness;
+ (CGFloat)defaultFlatness;
+ (void)setDefaultFlatness:(CGFloat)flatness;

/* THE DOOR AND THE BRIDGE. `+bezierPath` is the empty one Apple's callers use; `+bezierPathWithCGPath:`
 * wraps an existing path (retaining it, so the caller may let go), and `-CGPath` hands it back whole
 * rather than as a copy — there is one representation and no second model to be lossy about. */
+ (NSBezierPath *)bezierPath;
+ (NSBezierPath *)bezierPathWithCGPath:(CGPathRef)cgPath;
@property (nullable, readonly) CGPathRef CGPath;

/* THE SHAPE CONSTRUCTORS, which are the common cases as one message each. */
+ (NSBezierPath *)bezierPathWithRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithOvalInRect:(NSRect)rect;
+ (NSBezierPath *)bezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xRadius
				    yRadius:(CGFloat)yRadius;

/* BUILDING IT. The relative forms are relative to the CURRENT POINT, which is why `-currentPoint` is
 * the query that makes them usable. */
- (void)moveToPoint:(NSPoint)point;
- (void)lineToPoint:(NSPoint)point;
- (void)curveToPoint:(NSPoint)point controlPoint1:(NSPoint)controlPoint1
	controlPoint2:(NSPoint)controlPoint2;
- (void)curveToPoint:(NSPoint)point controlPoint:(NSPoint)controlPoint;
- (void)closePath;
- (void)relativeMoveToPoint:(NSPoint)point;
- (void)relativeLineToPoint:(NSPoint)point;
- (void)relativeCurveToPoint:(NSPoint)point controlPoint1:(NSPoint)controlPoint1
	     controlPoint2:(NSPoint)controlPoint2;
- (void)relativeCurveToPoint:(NSPoint)point controlPoint:(NSPoint)controlPoint;
- (void)removeAllPoints;

/* APPENDING, WHICH IS HOW A PATH IS COMPOSED rather than built point by point. The arc's angles are
 * DEGREES — see the header note — and the four-argument form sweeps counterclockwise, which is
 * Apple's default. */
- (void)appendBezierPath:(NSBezierPath *)path;
- (void)appendBezierPathWithPoints:(const NSPoint *)points count:(NSInteger)count;
- (void)appendBezierPathWithRect:(NSRect)rect;
- (void)appendBezierPathWithOvalInRect:(NSRect)rect;
- (void)appendBezierPathWithRoundedRect:(NSRect)rect xRadius:(CGFloat)xRadius yRadius:(CGFloat)yRadius;
- (void)appendBezierPathWithArcFromPoint:(NSPoint)point1 toPoint:(NSPoint)point2 radius:(CGFloat)radius;
- (void)appendBezierPathWithArcWithCenter:(NSPoint)center radius:(CGFloat)radius
			       startAngle:(CGFloat)startAngle endAngle:(CGFloat)endAngle;
- (void)appendBezierPathWithArcWithCenter:(NSPoint)center radius:(CGFloat)radius
			       startAngle:(CGFloat)startAngle endAngle:(CGFloat)endAngle
				clockwise:(BOOL)clockwise;

/* WHAT IT IS. `bounds` is the bounding box including the control points, which is Apple's reading —
 * `controlPointBounds` is the same box under the name Apple gives the path's own. */
@property (readonly) NSRect bounds;
@property (readonly) NSRect controlPointBounds;
@property (readonly) NSPoint currentPoint;
@property (readonly, getter=isEmpty) BOOL empty;
@property (readonly) NSInteger elementCount;

/* THE LINE STATE, WHICH IS THE PATH'S OWN — see the header note. A NEW PATH TAKES THE CLASS'S
 * CURRENT DEFAULTS, which is Apple's contract and the reason the defaults exist as settable state
 * rather than constants. */
@property NSWindingRule windingRule;
@property NSLineCapStyle lineCapStyle;
@property NSLineJoinStyle lineJoinStyle;
@property CGFloat lineWidth;
@property CGFloat miterLimit;
- (void)setLineDash:(nullable const CGFloat *)pattern count:(NSInteger)count phase:(CGFloat)phase;
- (void)getLineDash:(nullable CGFloat *)pattern count:(nullable NSInteger *)count
	      phase:(nullable CGFloat *)phase;

/* AND THE DEFAULTS THEMSELVES, consulted when a path is CREATED. */
+ (NSWindingRule)defaultWindingRule;
+ (void)setDefaultWindingRule:(NSWindingRule)windingRule;
+ (NSLineCapStyle)defaultLineCapStyle;
+ (void)setDefaultLineCapStyle:(NSLineCapStyle)lineCapStyle;
+ (NSLineJoinStyle)defaultLineJoinStyle;
+ (void)setDefaultLineJoinStyle:(NSLineJoinStyle)lineJoinStyle;
+ (CGFloat)defaultLineWidth;
+ (void)setDefaultLineWidth:(CGFloat)lineWidth;
+ (CGFloat)defaultMiterLimit;
+ (void)setDefaultMiterLimit:(CGFloat)miterLimit;

/* DRAWING, INTO THE CURRENT GRAPHICS CONTEXT. `-fill` uses the path's winding rule; `-stroke` sets
 * the context's line state from ours first (see the header note). */

/* THE CACHE SWITCH, WHICH RECORDS. Apple deprecated the pair at the vintage this tree pins and its own
 * note says a caller can drop their use, so the honest maximum is what a getter can answer: what its
 * setter was told.
 *
 * THE SETTER IS SPELLED OUT AS WELL AS THE PROPERTY, which is not redundant here: the ledger holds
 * `-setCachesBezierPath:` as its OWN row, and a `@property` declaration does not put that token in a
 * header — so the two spellings are both written, which is also what Apple's own header does for the
 * methods its properties pair with. */
@property BOOL cachesBezierPath;
- (void)setCachesBezierPath:(BOOL)flag;

/* AND THE ONE CONSTRUCTION DOOR THAT CANNOT BE HONOURED HERE, DECLARED AND REFUSING BY NAME. Apple's
 * `-setAssociatedPoints:` REWRITES the points of the element most recently added; this class adds elements
 * straight to a `CGMutablePathRef`, and a CGPath is APPEND-ONLY — there is no call that changes an existing
 * element's points. A door that silently did nothing would leave a caller's geometry where it was and look
 * like it had moved it. */
- (void)setAssociatedPoints:(nullable NSPointArray)points;

/* **AND THE INDEXED SPELLING REFUSES FOR THE SAME REASON, NOT A SECOND ONE.** `-setAssociatedPoints:atIndex:` names the
 * element to rewrite, which changes WHICH element a caller is asking about and not WHETHER the substrate can rewrite one:
 * a CGPath is append-only, so there is still no element to reach. Apple's 10.6 header declares the pair together; so does
 * this one, and both doors say the same thing on stderr. */
- (void)setAssociatedPoints:(nullable NSPointArray)points atIndex:(NSInteger)index;

- (void)fill;
- (void)stroke;

/* THE ELEMENT MODEL, READ BACK. `-elementAtIndex:` answers what the step AT that index is, and
 * `-elementAtIndex:associatedPoints:` also writes the points that go with it — 1 for a move or a line,
 * 2 for a quadratic, 3 for a cubic, 0 for a close — into a caller's array, or skips them if the array is
 * NULL. AN INDEX PAST THE END IS REFUSED BY NAME rather than raising, which is this tree's rule for an
 * ordinary mistake; Apple raises. */
- (NSBezierPathElement)elementAtIndex:(NSInteger)index;
- (NSBezierPathElement)elementAtIndex:(NSInteger)index associatedPoints:(nullable NSPointArray)points;

/* AND WHETHER A POINT IS INSIDE THE PATH, by the path's own WINDING RULE — the same question the fill
 * asks, answered in AppKit because CoreGraphics here tests coverage rather than membership. The test is
 * run on the FLATTENED path, which is what makes it a polygon crossing count rather than an area. */
- (BOOL)containsPoint:(NSPoint)point;
/* THE CLIP FAMILY: `-addClip` INTERSECTS with this path, `-setClip` REPLACES the clip with it, and
 * `+clipRect:` intersects with a rectangle. The receiver's path is untouched by either — CoreGraphics'
 * clip consumes the copy the CONTEXT was given, not this object's. */
- (void)addClip;
- (void)setClip;
+ (void)clipRect:(NSRect)rect;

/* THE COPY THAT KEEPS ITS CURVES, flattened — the one copy operation Core Graphics has. */
@property (readonly, strong) NSBezierPath *bezierPathByFlatteningPath;

/* AND THE COPY THAT REVERSES THEM, WHICH IS SYNTHESISED HERE RATHER THAN DELEGATED: `CGPath` has no
 * reversing operation, so this walks the element model and rebuilds the path backwards — see the
 * implementation, where the three things a naive order-reversal gets wrong are named (a cubic's control
 * points swap, a quadratic's does not, and a CLOSED contour starts at its move point and emits the reversed
 * closing line first).
 *
 * THE NOTE AT THE TOP OF THIS FILE STILL LISTS THIS DOOR UNDER "WHAT IS NOT HERE", and that is now stale:
 * the reason it gave — "synthesising one is a real piece of geometry rather than a forward" — was a
 * statement about the WORK rather than about a missing substrate, and the work is done. THE SENTENCE ITSELF
 * IS OWED A CORRECTION on the next pass through this header, and it is named here so a reader who finds it
 * knows which reading is current.
 *
 * AND THAT CORRECTION HAS SINCE BEEN MADE, WHICH IS WHY THIS PARAGRAPH READS IN THE PAST TENSE: the opening
 * note's entry is gone, and it was replaced with a record of WHAT IT USED TO SAY and why that was wrong —
 * the same treatment the flatness family got, since both were reasons this header had to retract rather than
 * work it had deferred. §A10p is the ledger's account of it. */
@property (readonly, strong) NSBezierPath *bezierPathByReversingPath;

/* AND THE TRANSFORM, which transforms the POINTS rather than recording a matrix, exactly as
 * `CGPathCreateMutableCopyByTransformingPath` does — there is no matrix stored in a path. */
- (void)transformUsingAffineTransform:(NSAffineTransform *)transform;

/* ============================================================================================ *
 * THE FOUR GLYPH DOORS, WHICH REFUSE BY NAME — AND WHAT STOPS THEM IS A CLASS, NOT A TECHNIQUE.  *
 * ============================================================================================ *
 *
 * EACH OF THE FOUR TAKES SOMETHING THIS TIER HAS NOT GOT, AND IT IS NOT THE CLASS: three take an `NSFont` and the
 * fourth takes the glyphs a font would have produced. THIS USED TO SAY "a class this tier has not got" AND THAT HAS
 * BEEN FALSE SINCE `NSFont` SHIPPED — what is missing is the GLYPH-OUTLINE MACHINERY inside it, which `NSFont.h` names
 * as its own second slice, because it needs `NSGlyph`. The distinction matters to a reader deciding whether to write
 * the door: there is a class to ask now, and nothing in it that answers. A REFUSAL IS THE RIGHT ANSWER RATHER THAN A WITHDRAWAL: a door that quietly appended
 * nothing would hand back a path the caller believes contains letterforms, which is the silent wrongness
 * this tier refuses — and the alternative, inventing outlines without a font's metrics, would be a wrong
 * shape rather than a missing one.
 *
 * TWO SPELLINGS ARE NAMED RATHER THAN GLOSSED: the font parameter is `id`, and the reason it USED TO GIVE — that
 * `NSFont` is a class this tier does not ship, so that naming it "would have the ledger credit its class row" — is no
 * longer the reason, because the class HAS shipped and its row is credited. The parameter stays `id` for the honest
 * one: typing it `NSFont *` would promise a font that can answer for a glyph, and no font here can yet. THE TIGHTENING
 * IS OWED WITH THE MACHINERY, and is named here so it is not mistaken for an oversight — the rule this header states
 * wherever an unshipped type would otherwise appear), and the glyph is spelled `unsigned int` because
 * `NSGlyph` is a typedef in that same missing header. Apple's `NSGlyph` IS an `unsigned int`, so a caller
 * passing a glyph — or `NSNullGlyph` — compiles and means what it says. */
+ (void)drawPackedGlyphs:(const char *)packedGlyphs atPoint:(NSPoint)point;
- (void)appendBezierPathWithGlyph:(unsigned int)glyph inFont:(id)font;
- (void)appendBezierPathWithGlyphs:(const unsigned int *)glyphs
			     count:(NSInteger)count
			    inFont:(id)font;
- (void)appendBezierPathWithPackedGlyphs:(const char *)packedGlyphs;

/* THE FOUR CLASS-LEVEL DRAWING HELPERS, each of which is a path built and drawn in one call. */
+ (void)fillRect:(NSRect)rect;
+ (void)strokeRect:(NSRect)rect;
+ (void)strokeLineFromPoint:(NSPoint)point1 toPoint:(NSPoint)point2;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBEZIERPATH_H */
