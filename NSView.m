/*
 * NSView — a rectangle in a tree, and the coordinate systems that tree implies.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE TREE AND THE COORDINATE SYSTEMS ARE THE WHOLE OF THIS FILE, and both are arithmetic rather than
 * drawing — which is why they can be finished and proved without a window server.
 *
 * THE OWNERSHIP IS ONE RULE AND ONE CONSEQUENCE: a parent OWNS its subviews and a subview BORROWS its
 * superview, so the borrowed link has to be cleared on both sides of the relationship — when a subview
 * leaves (`-removeFromSuperview`) and when the parent is deallocated. Leaving the second out is a
 * dangling pointer that only shows up as a crash much later, which is what `-dealloc` below prevents.
 */
#import "AppKitRefusal.h"
#include <math.h>
#import <AppKit/NSView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSTextInputContext.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSLayoutSolver.h>
#import <AppKit/NSLayoutAnchor_internal.h>
#include <CoreGraphics/CGDataConsumer.h>
#include <CoreGraphics/CGPDFContext.h>
#include <CoreGraphics/CGEPSContext.h>
#include <Foundation/NSData.h>
#include <stdio.h>
#include <string.h>

/* **THE INTRINSIC SIZE'S ONE SENTINEL, IN BOTH OF APPLE'S SPELLINGS.** The value is -1 and the engine compares
 * against the NAME rather than against zero: a view whose content is genuinely nothing has an intrinsic size of
 * zero, which is a different statement from "this view has no opinion". The misspelled spelling is 10.7's and is
 * kept because a ported caller may still use it. */
const CGFloat NSViewNoIntrinsicMetric = -1.0;
const CGFloat NSViewNoInstrinsicMetric = -1.0;

/* A POINT FROM A VIEW'S OWN SYSTEM INTO ITS SUPERVIEW'S, AND BACK. The flip is the entire difference,
 * AND IT IS THE COMPARISON OF TWO FLIPS RATHER THAN ONE VIEW'S — which is the bug the probe found after
 * the first version compared only the CHILD's:
 *
 *   the frame's origin.y is measured in the SUPERVIEW's y direction, while the point is measured in the
 *   view's OWN. So the two agree — and the point needs no mirroring — exactly when the view and its
 *   superview have the SAME y direction, and are mirrored when they do not. A flipped superview with an
 *   unflipped child therefore puts the child's own origin at the BOTTOM of its frame, which is the case a
 *   one-sided test answers as if nothing had flipped at all.
 */
static BOOL fn_same_y_direction(NSView *v)
{
	NSView *s = [v superview];

	/* THE ROOT HAS NO SUPERVIEW, and a view with nothing above it is trivially "the same direction". */
	if (s == nil) {
		return YES;
	}
	return [v isFlipped] == [s isFlipped];
}

/* **THE BOUNDS ORIGIN IS PART OF THE CONVERSION, AND IT IS THE PART A SCROLL NEEDS.** `-bounds`.origin is the point
 * of the view's own coordinates that sits at its frame's origin, so a point given in the view's coordinates is
 * shifted by it before the frame places it; the two functions below are exact inverses and the shift is what makes
 * that true. It was missing while every bounds here was zero, and a scrolled clip view is exactly the caller that
 * makes it matter: without it a click on scrolled content lands where the content USED to be. */
static NSPoint fn_to_super(NSPoint p, NSView *v)
{
	NSRect f = [v frame];
	NSRect b = [v bounds];
	BOOL same = fn_same_y_direction(v);
	CGFloat x = p.x - b.origin.x;
	CGFloat y = p.y - b.origin.y;

	return NSMakePoint(f.origin.x + x, f.origin.y + (same ? y : f.size.height - y));
}

static NSPoint fn_from_super(NSPoint p, NSView *v)
{
	NSRect f = [v frame];
	NSRect b = [v bounds];
	BOOL same = fn_same_y_direction(v);
	CGFloat y = p.y - f.origin.y;

	if (!same) {
		y = f.size.height - y;
	}
	return NSMakePoint(p.x - f.origin.x + b.origin.x, y + b.origin.y);
}

/* THE ROOT VIEW STANDS IN FOR "THE WINDOW'S COORDINATE SYSTEM", which is the one place this slice has to
 * give a NULL view a meaning. Root space IS the root view's own system, so a walk upwards stops BEFORE
 * applying the root's own frame — the root is not placed in anything. */
static NSView *fn_root(NSView *v)
{
	NSView *s = [v superview];

	while (s != nil) {
		v = s;
		s = [v superview];
	}
	return v;
}

static NSPoint fn_up_to_root(NSPoint p, NSView *v)
{
	while (v != nil && [v superview] != nil) {
		p = fn_to_super(p, v);
		v = [v superview];
	}
	return p;
}

static NSPoint fn_down_from_root(NSView *v, NSPoint p)
{
	NSView *s = [v superview];

	if (s == nil) {
		return p;
	}
	return fn_from_super(fn_down_from_root(s, p), v);
}

/* HAND-WRITTEN BECAUSE THE INTERSECTION IS FOUR COMPARISONS and a Foundation function for it would be
 * one more thing this file depends on. A non-overlapping pair answers the empty rect. */
static NSRect fn_intersect(NSRect a, NSRect b)
{
	CGFloat x1 = a.origin.x > b.origin.x ? a.origin.x : b.origin.x;
	CGFloat y1 = a.origin.y > b.origin.y ? a.origin.y : b.origin.y;
	CGFloat x2 = (a.origin.x + a.size.width) < (b.origin.x + b.size.width)
			     ? (a.origin.x + a.size.width) : (b.origin.x + b.size.width);
	CGFloat y2 = (a.origin.y + a.size.height) < (b.origin.y + b.size.height)
			     ? (a.origin.y + a.size.height) : (b.origin.y + b.size.height);

	if (x2 <= x1 || y2 <= y1) {
		return NSMakeRect(0.0, 0.0, 0.0, 0.0);
	}
	return NSMakeRect(x1, y1, x2 - x1, y2 - y1);
}

/* THE PRIVATE CURSOR DOORS: the resolution, the staleness pass, and what `NSWindow` asks of the tree. */
@interface NSView ()
- (NSCursor *)cg_cursorAtPoint:(NSPoint)point;
- (void)cg_markCursorRectsStale;
- (void)cg_rebuildStaleCursorRects;
- (NSUInteger)cg_cursorRectCount;
/* AND THE LAYOUT PASS'S THREE STEPS, which are this file's and not the public header's: the pass guard is what
 * keeps a frame set inside the pass from starting another, and the hooks are the recursion the driver owns. */
- (void)cg_runLayoutPass;
- (void)cg_callLayoutHooks;
- (void)cg_requestLayout;
/* **AND THE DAMAGE REGION'S THREE.** A piece is added to a view's own list, the whole tree's pieces are collected for the
 * window, and one helper adds a piece to either — so the merge rule and the behaviour on a full budget exist once. */
- (void)cg_addToDirtyRegion:(NSRect)rect;
- (void)cg_regionAdd:(NSRect)rect to:(NSRect *)out max:(NSUInteger)max count:(NSUInteger *)count;
@end

/* **THE TRACKING ENGINE'S DOOR INTO AN AREA, declared here because this is the file that writes the verdict.** The
 * bit lives on the area (see `NSTrackingArea.m`), and only two objects ever touch it: the window's engine, which
 * decides whether the pointer moved in or out, and the door below, which clears it on removal. Declared in `NSView.m`
 * AND again in `NSWindow.m` rather than in the public header, which is this tree's shape for a `cg_` door that is
 * nobody's API but the tier's own. */
@interface NSTrackingArea (APPKITTrackingEngine)
- (BOOL)cg_isInside;
- (void)cg_setInside:(BOOL)flag;
@end

/* THE DRAG SESSION'S ONE BEGIN DOOR, declared here because the VIEW is the class that opens a session and the
 * session's internals live in `NSDragging.m`. Everything after the beginning is the session's; this file only hands
 * it the items, the event and the source. */
@interface NSDraggingSession (APPKITDragBegin)
+ (nullable NSDraggingSession *)cg_beginWithItems:(NSArray *)items
					    event:(nullable NSEvent *)event
					   source:(id <NSDraggingSource>)source
					     view:(NSView *)view
				       pasteboard:(nullable NSPasteboard *)pasteboard
					slideBack:(BOOL)slideBack;
@end

/* THE PRIVATE DOOR THE SUPERVIEW USES TO HAND ITS WINDOW DOWN, declared here because this is the file that
 * defines it — and called from `-addSubview:`/`-removeFromSuperview` above it. */
@interface NSView ()
- (void)cg_setWindow:(NSWindow *)aWindow;
@end

/* THE CURSOR-RECT PAIR, PRIVATE TO THIS FILE: a rect and the cursor for it. The cursor is BORROWED — every
 * cursor a view declares comes from one of `NSCursor`'s shared instances, which live as long as the process. */
@interface FNCursorRect : NSObject
{
@public
	NSRect rect;
	NSCursor *cursor;
}
@end

@implementation FNCursorRect
@end

@implementation NSView

/* ============================================================================================
 * ARCHIVING: THE DESIGN SUBSET OF A VIEW, AND THE LINE BETWEEN A DESIGN AND A LIVE TREE.
 * ============================================================================================ */

/* THE KEYS ARE PROPERTY NAMES, so that a design file's vocabulary is the public API and a reader can be checked
 * against the header rather than against a dialect this file invented. */
static NSString * const AGCoderFrameKey = @"frame";
static NSString * const AGCoderHiddenKey = @"hidden";
static NSString * const AGCoderTagKey = @"tag";
static NSString * const AGCoderAutoresizingMaskKey = @"autoresizingMask";
static NSString * const AGCoderAutoresizesSubviewsKey = @"autoresizesSubviews";
static NSString * const AGCoderAlphaValueKey = @"alphaValue";
static NSString * const AGCoderToolTipKey = @"toolTip";
static NSString * const AGCoderTranslatesMaskKey = @"translatesAutoresizingMaskIntoConstraints";
static NSString * const AGCoderPostsFrameChangesKey = @"postsFrameChangedNotifications";
static NSString * const AGCoderPostsBoundsChangesKey = @"postsBoundsChangedNotifications";
static NSString * const AGCoderFocusRingTypeKey = @"focusRingType";
static NSString * const AGCoderHuggingHorizontalKey = @"contentHuggingPriorityHorizontal";
static NSString * const AGCoderHuggingVerticalKey = @"contentHuggingPriorityVertical";
static NSString * const AGCoderResistanceHorizontalKey = @"contentCompressionResistancePriorityHorizontal";
static NSString * const AGCoderResistanceVerticalKey = @"contentCompressionResistancePriorityVertical";
static NSString * const AGCoderSubviewsKey = @"subviews";
static NSString * const AGCoderConstraintsKey = @"constraints";

/* **WHAT IS ARCHIVED IS THE DESIGN, AND WHAT IS NOT IS THE LIVE TREE.** A view's `_window`, `_superview` and
 * `_nextKeyView` are BORROWED LINKS INTO A PROCESS: the parent rebuilds the first two when it adds a child, and the
 * third is a CONNECTION (see `NSNib.h`) rather than a value. The cursor rects, the dirty region, the tracking areas,
 * the registered drag types, the input context and every `_cg_` cache are state of a view that is RUNNING, and a
 * decoded view has not run yet — so they are absent, and their absence is the reason a nib can be read into a fresh
 * process at all.
 *
 * THE CONSTRAINTS ARE ARCHIVED NOW, WHICH IS WHAT MAKES A NIB ABLE TO STATE A RELATIONSHIP RATHER THAN A FRAME.
 * `NSLayoutConstraint` has its coding methods, so a view's `_constraints` travel with it — and the decoder adopts each one
 * through `-addConstraint:`, which is the door that re-establishes the OWNER link and the active flag that a constraint
 * cannot carry (see its own note). The translate-mask flag and the four priorities still travel separately, because they
 * are the view's **mode** rather than its equations.
 *
 * THE ORDER OF THE DECODE MATTERS AND IS THE REASON THE CONSTRAINTS COME LAST: a constraint names two views, and the
 * only way those names resolve is for the views to be IN THE GRAPH already — which the subviews decode above
 * guarantees, because decoding a child's own fields has finished by the time the array hands it back. */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	/* THE CHAIN IS REAL NOW: `NSResponder` gained its coding methods, so a view's archive carries its interface style
	 * and its context menu as well as the view state. */
	[super encodeWithCoder:aCoder];

	[aCoder encodeRect:_frame forKey:AGCoderFrameKey];
	[aCoder encodeBool:_hidden forKey:AGCoderHiddenKey];
	[aCoder encodeInteger:_tag forKey:AGCoderTagKey];
	[aCoder encodeInteger:(NSInteger)_autoresizingMask forKey:AGCoderAutoresizingMaskKey];
	[aCoder encodeBool:_autoresizesSubviews forKey:AGCoderAutoresizesSubviewsKey];
	[aCoder encodeDouble:(double)_alphaValue forKey:AGCoderAlphaValueKey];
	[aCoder encodeObject:_toolTip forKey:AGCoderToolTipKey];
	[aCoder encodeBool:_translatesAutoresizingMaskIntoConstraints forKey:AGCoderTranslatesMaskKey];
	[aCoder encodeBool:_postsFrameChangedNotifications forKey:AGCoderPostsFrameChangesKey];
	[aCoder encodeBool:_postsBoundsChangedNotifications forKey:AGCoderPostsBoundsChangesKey];
	[aCoder encodeInteger:(NSInteger)_focusRingType forKey:AGCoderFocusRingTypeKey];
	[aCoder encodeDouble:(double)_contentHuggingPriority[0] forKey:AGCoderHuggingHorizontalKey];
	[aCoder encodeDouble:(double)_contentHuggingPriority[1] forKey:AGCoderHuggingVerticalKey];
	[aCoder encodeDouble:(double)_contentCompressionResistancePriority[0] forKey:AGCoderResistanceHorizontalKey];
	[aCoder encodeDouble:(double)_contentCompressionResistancePriority[1] forKey:AGCoderResistanceVerticalKey];
	/* AND THE CHILDREN, IN BACK-TO-FRONT ORDER — the array's order IS the drawing and hit-testing order, so it is
	 * archived rather than sorted or derived. */
	[aCoder encodeObject:_subviews forKey:AGCoderSubviewsKey];
	/* AND THE EQUATIONS THE VIEW OWNS, last for the same reason the children are written: the order a reader rebuilds in
	 * is the order a dependency has. */
	[aCoder encodeObject:_constraints forKey:AGCoderConstraintsKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	/* **THE DEFAULTS AN IVAR CANNOT GIVE, REPEATED HERE BECAUSE A DECODE DOES NOT RUN `-initWithFrame:`.** These are
	 * Apple's defaults and the same ones the designated initialiser sets; a view read from a file and a view built in
	 * code must start in the same state, or a nib would be a third semantics. */
	_autoresizesSubviews = YES;
	_postsBoundsChangedNotifications = YES;
	_postsFrameChangedNotifications = YES;
	_wantsDefaultClipping = YES;
	_needsDisplay = YES;
	_cursorRectsStale = YES;
	_cg_unitSquareSize = NSMakeSize(1.0, 1.0);
	_needsUpdateConstraints = YES;
	_needsLayout = YES;
	_contentHuggingPriority[0] = NSLayoutPriorityDefaultLow;
	_contentHuggingPriority[1] = NSLayoutPriorityDefaultLow;
	_contentCompressionResistancePriority[0] = NSLayoutPriorityDefaultHigh;
	_contentCompressionResistancePriority[1] = NSLayoutPriorityDefaultHigh;

	/* AND THEN WHATEVER THE FILE ACTUALLY SAID, which is why every one of these asks `-containsValueForKey:` first: an
	 * ABSENT key must leave the default above standing, and that is what makes an older tree able to read a newer file
	 * (see rule 2 in `NSNib.h`). */
	if ([aDecoder containsValueForKey:AGCoderFrameKey]) {
		_frame = [aDecoder decodeRectForKey:AGCoderFrameKey];
	}
	if ([aDecoder containsValueForKey:AGCoderHiddenKey]) {
		_hidden = [aDecoder decodeBoolForKey:AGCoderHiddenKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTagKey]) {
		_tag = [aDecoder decodeIntegerForKey:AGCoderTagKey];
	}
	if ([aDecoder containsValueForKey:AGCoderAutoresizingMaskKey]) {
		_autoresizingMask = (NSUInteger)[aDecoder decodeIntegerForKey:AGCoderAutoresizingMaskKey];
	}
	if ([aDecoder containsValueForKey:AGCoderAutoresizesSubviewsKey]) {
		_autoresizesSubviews = [aDecoder decodeBoolForKey:AGCoderAutoresizesSubviewsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderAlphaValueKey]) {
		_alphaValue = (CGFloat)[aDecoder decodeDoubleForKey:AGCoderAlphaValueKey];
	}
	if ([aDecoder containsValueForKey:AGCoderToolTipKey]) {
		_toolTip = [[aDecoder decodeObjectForKey:AGCoderToolTipKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderTranslatesMaskKey]) {
		_translatesAutoresizingMaskIntoConstraints =
			[aDecoder decodeBoolForKey:AGCoderTranslatesMaskKey];
	}
	if ([aDecoder containsValueForKey:AGCoderPostsFrameChangesKey]) {
		_postsFrameChangedNotifications = [aDecoder decodeBoolForKey:AGCoderPostsFrameChangesKey];
	}
	if ([aDecoder containsValueForKey:AGCoderPostsBoundsChangesKey]) {
		_postsBoundsChangedNotifications = [aDecoder decodeBoolForKey:AGCoderPostsBoundsChangesKey];
	}
	if ([aDecoder containsValueForKey:AGCoderFocusRingTypeKey]) {
		_focusRingType = (NSFocusRingType)[aDecoder decodeIntegerForKey:AGCoderFocusRingTypeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderHuggingHorizontalKey]) {
		_contentHuggingPriority[0] = (NSLayoutPriority)[aDecoder decodeDoubleForKey:AGCoderHuggingHorizontalKey];
	}
	if ([aDecoder containsValueForKey:AGCoderHuggingVerticalKey]) {
		_contentHuggingPriority[1] = (NSLayoutPriority)[aDecoder decodeDoubleForKey:AGCoderHuggingVerticalKey];
	}
	if ([aDecoder containsValueForKey:AGCoderResistanceHorizontalKey]) {
		_contentCompressionResistancePriority[0] =
			(NSLayoutPriority)[aDecoder decodeDoubleForKey:AGCoderResistanceHorizontalKey];
	}
	if ([aDecoder containsValueForKey:AGCoderResistanceVerticalKey]) {
		_contentCompressionResistancePriority[1] =
			(NSLayoutPriority)[aDecoder decodeDoubleForKey:AGCoderResistanceVerticalKey];
	}
	/* THE BOUNDS ARE THE FRAME'S SIZE AT THE ORIGIN, which is what every view starts as; a scroll offset is runtime
	 * state and is not in a design. */
	_bounds = NSMakeRect(0.0, 0.0, _frame.size.width, _frame.size.height);

	/* **THE CHILDREN GO THROUGH `-addSubview:` AND NOT INTO THE ARRAY DIRECTLY.** That door is what sets each child's
	 * `_superview`, hands it the window and sends the two move calls, so a decoded tree is wired exactly as a built one
	 * is — and its order is the file's order, because it is added in array order. */
	{
		id children = [aDecoder decodeObjectForKey:AGCoderSubviewsKey];
		NSUInteger i;

		if ([children isKindOfClass:[NSArray class]]) {
			for (i = 0; i < [(NSArray *)children count]; i++) {
				id child = [(NSArray *)children objectAtIndex:i];

				if ([child isKindOfClass:[NSView class]]) {
					[self addSubview:child];
				}
			}
		}
	}
	/* **AND THEN THE CONSTRAINTS, WHICH NAME VIEWS AND THEREFORE COME AFTER THEM.** Each one is adopted through
	 * `-addConstraint:` — the door that sets the OWNER and the active flag — and its active flag is cleared first because
	 * that door refuses a constraint it believes another view already owns. The refusal is right for a caller and wrong
	 * here: an archive records the flag, not the owner, so the flag must be re-derived from the adoption itself. */
	{
		id constraints = [aDecoder decodeObjectForKey:AGCoderConstraintsKey];
		NSUInteger i;

		if ([constraints isKindOfClass:[NSArray class]]) {
			for (i = 0; i < [(NSArray *)constraints count]; i++) {
				id constraint = [(NSArray *)constraints objectAtIndex:i];

				if ([constraint isKindOfClass:[NSLayoutConstraint class]]) {
					[(NSLayoutConstraint *)constraint cg_setActiveFlag:NO];
					[self addConstraint:(NSLayoutConstraint *)constraint];
				}
			}
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* ---- THE VIEW'S THREE: ONE STORED, ONE ANSWERED, ONE COMPOSED ------------------------------------- */

- (void)setAlphaValue:(CGFloat)viewAlpha
{
	/* RECORDED, WITH THE EFFECT NAMED: how a view's drawing COMPOSITES is the substrate's business, and this
	 * tier's substrate has not got one to composite into. */
	_alphaValue = viewAlpha;
}

- (CGFloat)alphaValue
{
	return _alphaValue;
}

- (BOOL)isOpaque
{
	/* **NO, AND THAT IS THE ANSWER RATHER THAN A DEFAULT.** Apple's shape here is a GETTER a view overrides to say
	 * whether WHAT IT DRAWS is opaque; a plain view draws nothing, and nothing is not opaque. There is no setter in
	 * Apple's 10.6 header either, which is why there is none here and no ivar behind it. */
	return NO;
}

- (BOOL)preservesContentDuringLiveResize
{
	/* NO, BECAUSE THE YES IS A PROMISE: see the declaration — a view answering YES takes on invalidating its own
	 * dirty rects during a live resize, and a plain view draws nothing to preserve. */
	return NO;
}

- (BOOL)inLiveResize
{
	/* COMPOSED, NOT STORED: the view answers what its window says, and Apple's own comment for this door is that a
	 * view asks it "from drawRect: to decide between cheap and full drawing". `nil` for a detached view answers NO,
	 * which is also the truth for a view that is in no window. */
	return [[self window] inLiveResize];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	/* **THE DEFAULTS AN IVAR CANNOT GIVE.** A view DOES resize its subviews, DOES post bounds changes
	 * and DOES clip by default — Apple's defaults, each a flag a caller may turn off rather than a value
	 * this tier chose. */
	_autoresizesSubviews = YES;
	_postsBoundsChangedNotifications = YES;
	_wantsDefaultClipping = YES;
	/* APPLE'S OWN DEFAULT: a view posts a frame change unless it is told not to. */
	_postsFrameChangedNotifications = YES;
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_frame = frameRect;
	/* THE BOUNDS BEGIN AS THE FRAME'S SIZE AT THE ORIGIN, which is what every view starts as. */
	_bounds = NSMakeRect(0.0, 0.0, frameRect.size.width, frameRect.size.height);
	_flipped = NO;
	/* THE IDENTITY SQUARE, so "is this scaled from its base" is a comparison with 1 and not with a zero this
	 * class forgot to set. */
	_cg_unitSquareSize = NSMakeSize(1.0, 1.0);
	_hidden = NO;
	/* A VIEW NOTHING HAS DRAWN NEEDS DISPLAY, which is the truthful initial state rather than a choice. */
	_needsDisplay = YES;
	_cursorRectsStale = YES;
	_subviews = nil;
	_superview = nil;
	/* **AUTO LAYOUT'S DEFAULTS ARE APPLE'S, AND BOTH ARE STATEMENTS RATHER THAN BLANK FILL.** A view created with a
	 * frame keeps behaving as one: the translated-mask flag is YES until a caller turns it off. Its intrinsic
	 * priorities are the two Apple names — DefaultLow for hugging, DefaultHigh for compression resistance — so a
	 * control that adopts its cell's size is held together more strongly than it is held apart, which is the
	 * asymmetry a stack of labels needs. */
	_translatesAutoresizingMaskIntoConstraints = YES;
	_constraints = nil;
	_needsUpdateConstraints = YES;
	_needsLayout = YES;
	_contentHuggingPriority[NSLayoutConstraintOrientationHorizontal] = NSLayoutPriorityDefaultLow;
	_contentHuggingPriority[NSLayoutConstraintOrientationVertical] = NSLayoutPriorityDefaultLow;
	_contentCompressionResistancePriority[NSLayoutConstraintOrientationHorizontal] = NSLayoutPriorityDefaultHigh;
	_contentCompressionResistancePriority[NSLayoutConstraintOrientationVertical] = NSLayoutPriorityDefaultHigh;
	return self;
}

- (void)dealloc
{
	/* THE BORROWED LINKS ARE CLEARED BEFORE THE CHILDREN ARE RELEASED, and the order matters: a child
	 * holds a POINTER to this view, so releasing the array while those pointers still name a dying object
	 * would leave every child one message away from a use-after-free. THIS IS WHAT A WEAK LINK MEANS WHEN
	 * THE LANGUAGE DOES NOT HAVE ONE, and it is the reason this method is not just a release. */
	if (_subviews != nil) {
		NSUInteger i;

		for (i = 0; i < [_subviews count]; i++) {
			NSView *c = [_subviews objectAtIndex:i];

			c->_superview = nil;
		}
		[_subviews release];
	}
	[_cg_registeredDraggedTypes release];
	[_cg_inputContext release];
	/* **A CONSTRAINT OUTLIVES ITS VIEW ONLY IF SOMEONE ELSE RETAINS IT, AND AN ACTIVE ONE MUST NOT.** The owner's
	 * array is the only retain, so removing every constraint here drops that retain; the flag and the owner link are
	 * cleared first, while the view is still a valid object, so a constraint held by a caller afterwards is honestly
	 * inactive instead of pointing at freed memory. */
	if (_constraints != nil) {
		NSUInteger i;

		for (i = 0; i < [_constraints count]; i++) {
			NSLayoutConstraint *constraint = [_constraints objectAtIndex:i];

			[constraint cg_setOwner:nil];
			[constraint cg_setActiveFlag:NO];
		}
		[_constraints release];
	}
	[super dealloc];
}

- (NSRect)frame
{
	return _frame;
}

/* **THE ANNOUNCEMENT, WHICH IS GATED, REMEMBERED, AND SILENT WHEN NOTHING MOVED.** The four rules are Apple's —
 * see the header — and it takes the OLD frame because by the time a caller could ask, that is gone. */
- (void)cg_frameDidChangeFrom:(NSRect)oldFrame
{
	if (oldFrame.origin.x == _frame.origin.x && oldFrame.origin.y == _frame.origin.y &&
	    oldFrame.size.width == _frame.size.width && oldFrame.size.height == _frame.size.height) {
		return;	/* NO NET CHANGE, NOTHING TO ANNOUNCE. */
	}
	/* **AND THE TRACKING AREAS ARE TOLD, BEFORE THE NOTIFICATION RULE BELOW CAN DECLINE TO ANNOUNCE ANYTHING.** A
	 * caller who muted FRAME notifications has not asked to stop tracking, and Apple's sentence attaches
	 * `-updateTrackingAreas` to the GEOMETRY CHANGE rather than to the announcement — so the two are separate here and
	 * the early return below is about the notification alone. */
	[self updateTrackingAreas];
	if (!_postsFrameChangedNotifications) {
		_cg_frameChangedWhileMuted = YES;	/* remembered, for the rule about the flag coming back */
		return;
	}
	_cg_frameChangedWhileMuted = NO;
	[[NSNotificationCenter defaultCenter] postNotificationName:NSViewFrameDidChangeNotification object:self];
}

- (BOOL)postsFrameChangedNotifications
{
	return _postsFrameChangedNotifications;
}

- (void)setPostsFrameChangedNotifications:(BOOL)flag
{
	if (flag == _postsFrameChangedNotifications) {
		return;
	}
	_postsFrameChangedNotifications = flag;
	if (flag && _cg_frameChangedWhileMuted) {
		/* **APPLE'S EDGE CASE**: a frame that changed while this view was not posting is announced NOW, even though
		 * nothing has changed since — otherwise a caller that turned the flag off around a batch of edits would never
		 * learn the batch happened. */
		_cg_frameChangedWhileMuted = NO;
		[[NSNotificationCenter defaultCenter] postNotificationName:NSViewFrameDidChangeNotification object:self];
	}
}

/* ---- THE VIEW'S LAST SIXTY-FOUR DOORS ----------------------------------------------------------------- */

/* **THE ONES THAT COMPUTE.** */

- (nullable NSView *)ancestorSharedWithView:(NSView *)aView
{
	/* THE STANDARD ANSWER: every ancestor of THIS view is a candidate, and the first one that is also an ancestor
	 * of the other view — or the other view itself — is the shared one. Two chains, no recursion, and no reliance on
	 * a door this class might not have. */
	NSView *mine = self;
	NSView *theirs;

	while (mine != nil) {
		theirs = aView;
		while (theirs != nil) {
			if (theirs == mine) {
				return mine;
			}
			theirs = [theirs superview];
		}
		mine = [mine superview];
	}
	return nil;
}

- (nullable id)viewWithTag:(NSInteger)aTag
{
	/* A SUBTREE SEARCH, DEPTH-FIRST, because that is what Apple's door means: this view, then each subview's
	 * subtree in order. */
	NSUInteger i;

	if (_tag == aTag) {
		return self;
	}
	if (_subviews != nil) {
		for (i = 0; i < [_subviews count]; i++) {
			NSView *found = [[_subviews objectAtIndex:i] viewWithTag:aTag];

			if (found != nil) {
				return found;
			}
		}
	}
	return nil;
}

- (void)replaceSubview:(NSView *)oldView with:(NSView *)newView
{
	/* THE Z-ORDER IS THE POINT: the replacement takes the place the old view had rather than going on top, which a
	 * remove-then-add would do. The window link moves with it, and each view is told what happened. */
	NSUInteger i;

	if (oldView == newView || _subviews == nil) {
		return;
	}
	for (i = 0; i < [_subviews count]; i++) {
		NSView *v = [_subviews objectAtIndex:i];

		if (v != oldView) {
			continue;
		}
		[v retain];
		[self willRemoveSubview:v];
		/* **THE OLD VIEW LOSES THE WINDOW, AND THE PROBE CAUGHT ME NOT DOING IT.** The link this class carries is a
		 * POINTER down a subtree, so a view leaving it has to drop it — `cg_setWindow:nil` clears the subtree — and
		 * without this line a replaced view went on answering `-window` with a window it was no longer in. */
		[v cg_setWindow:nil];
		v->_superview = nil;
		[newView retain];
		[self didAddSubview:newView];
		newView->_superview = self;
		[newView cg_setWindow:_window];
		[_subviews replaceObjectAtIndex:i withObject:newView];
		oldView->_superview = nil;
		[v release];
		return;
	}
}

- (BOOL)needsToDrawRect:(NSRect)aRect
{
	/* THIS CLASS'S OWN DIRTY BOOKKEEPING, which is what Apple's door asks about: a view with no marked rectangle
	 * needs to draw nothing, and one with a marked rectangle needs to draw where the two intersect. */
	return _hasDirtyRect && NSIntersectsRect(aRect, _dirtyRect);
}

- (NSRect)centerScanRect:(NSRect)aRect
{
	/* ARITHMETIC RATHER THAN A SUBSTRATE: a rectangle is snapped so that its edges run through PIXEL CENTRES, which
	 * is Apple's own contract for this door and the reason it is called `centerScan`. */
	CGFloat minX = floor(aRect.origin.x) + 0.5;
	CGFloat minY = floor(aRect.origin.y) + 0.5;
	CGFloat maxX = floor(aRect.origin.x + aRect.size.width) + 0.5;
	CGFloat maxY = floor(aRect.origin.y + aRect.size.height) + 0.5;

	return NSMakeRect(minX, minY, maxX - minX, maxY - minY);
}

- (nullable NSBitmapImageRep *)bitmapImageRepForCachingDisplayInRect:(NSRect)rect
{
	/* **THE REP THE DRAWING DOOR ALREADY FILLS.** `-cacheDisplayInRect:toBitmapImageRep:` is this layer's substrate
	 * answer, so the door that MAKES one is real too: one pixel per point, R, G, B, A, alpha last — the colour order
	 * this class's header states for a bitmap-backed rep. */
	NSInteger w = (NSInteger)rect.size.width;
	NSInteger h = (NSInteger)rect.size.height;

	if (w <= 0 || h <= 0) {
		return nil;
	}
	return [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8
					      samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					      colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w * 4
					      bitsPerPixel:32] autorelease];
}

- (void)getRectsBeingDrawn:(const NSRect **)rects count:(NSInteger *)count
{
	/* THE ADDRESS OF AN IVAR, which is stable for as long as the view lives — the caller only reads it during the
	 * draw, which is exactly what Apple's signature assumes. */
	if (rects != NULL) {
		*rects = &_dirtyRect;
	}
	if (count != NULL) {
		*count = _hasDirtyRect ? 1 : 0;
	}
}

- (void)getRectsExposedDuringLiveResize:(NSRect[4])exposedRects count:(NSInteger *)count
{
	/* NOTHING HAS BEEN EXPOSED BY A RESIZE THIS TIER DID, and zero is the honest count rather than four empty
	 * rectangles. */
	(void)exposedRects;
	if (count != NULL) {
		*count = 0;
	}
}

- (void)translateRectsNeedingDisplayInRect:(NSRect)clipRect by:(NSSize)delta
{
	/* THE DIRTY RECT MOVES WITH THE CONTENT it is part of, so a rect that intersects the clip is shifted by the
	 * same delta rather than being marked again. */
	if (_hasDirtyRect && NSIntersectsRect(clipRect, _dirtyRect)) {
		_dirtyRect.origin.x += delta.width;
		_dirtyRect.origin.y += delta.height;
	}
}

- (void)setKeyboardFocusRingNeedsDisplayInRect:(NSRect)rect
{
	/* RECORDED AS A REPAINT REQUEST: this tier draws no focus ring, and a caller asking for one to be redrawn is
	 * asking for exactly this rectangle to be marked. */
	[self setNeedsDisplayInRect:rect];
}

/* AND THE FOUR SCROLL DOORS. **SCROLLING A VIEW IS ITS CLIP VIEW'S WORK**, and this tier answers rather than
 * reaching into one: a view that is not being clipped has nothing to scroll, so `-scrollRectToVisible:` reports
 * that it did not scroll, `-adjustScroll:` hands back the rectangle it was given unchanged, and the two void doors
 * do nothing. Each says so where it stands rather than pretending a scroll happened. */

/* **BOTH DOORS FIND THE CLOSEST ENCLOSING CLIP VIEW AND MOVE IT, WHICH IS APPLE'S OWN READING OF THEM.** A view does
 * not scroll; a CLIP VIEW does — it is the one whose bounds origin is the visible window into a document — so the
 * only thing a view can do with "make this visible" is hand the question up the superview chain. The walk stops at
 * the first `NSClipView`, which is the same search `-enclosingScrollView` makes one class over for the scroll view
 * that owns one. A view with no clip view above it answers NO rather than pretending: there is nowhere to scroll.
 *
 * **AND THE ARITHMETIC IS IN THE CLIP VIEW'S OWN COORDINATES, WHICH IS WHERE THE DOCUMENT LIVES.** Converting the
 * rectangle into the clip view puts it in the same space as `-bounds`, and that rectangle IS the visible window — so
 * "is it visible" is a containment test and "make it visible" is moving the origin JUST FAR ENOUGH. The far edge
 * moves the origin so the rectangle's MAX edge meets the visible MAX edge rather than putting its minimum there,
 * which is the difference between scrolling a caret into view and scrolling it to the top of the screen. The origin
 * is handed to `-scrollToPoint:`, which CONSTRAINS it — so a rectangle below the document's end scrolls as far as
 * there is and no further. */
- (NSClipView *)fn_enclosingClipView
{
	NSView *view = _superview;

	while (view != nil) {
		if ([view isKindOfClass:[NSClipView class]]) {
			return (NSClipView *)view;
		}
		view = [view superview];
	}
	return nil;
}

- (void)scrollPoint:(NSPoint)aPoint
{
	NSClipView *clip = [self fn_enclosingClipView];

	if (clip != nil) {
		/* **THE POINT IS IN THE RECEIVER'S OWN COORDINATES, AND THE DOCUMENT'S FRAME IS ALREADY IN THE CLIP
		 * VIEW'S** (it is a subview) — so the target origin is the point plus the document's frame origin, which is
		 * the whole of the conversion this door needs. `-convertPoint:toView:` is NOT used here because the clip
		 * view's own coordinate system is offset by the scroll it is performing, and expressing a scroll POSITION
		 * through it would fold the current origin into the answer. */
		NSRect frame = [self frame];

		[clip scrollToPoint:NSMakePoint(aPoint.x + frame.origin.x, aPoint.y + frame.origin.y)];
	}
}

- (BOOL)scrollRectToVisible:(NSRect)aRect
{
	NSClipView *clip = [self fn_enclosingClipView];
	NSRect visible;
	NSRect target;
	NSPoint origin;

	if (clip == nil) {
		return NO;
	}
	target = [self convertRect:aRect toView:clip];
	visible = [clip bounds];
	origin = visible.origin;
	if (NSMinY(target) < NSMinY(visible)) {
		origin.y = NSMinY(target);
	} else if (NSMaxY(target) > NSMaxY(visible)) {
		origin.y = NSMaxY(target) - NSHeight(visible);
	}
	if (NSMinX(target) < NSMinX(visible)) {
		origin.x = NSMinX(target);
	} else if (NSMaxX(target) > NSMaxX(visible)) {
		origin.x = NSMaxX(target) - NSWidth(visible);
	}
	if (NSEqualPoints(origin, visible.origin)) {
		return NO;
	}
	[clip scrollToPoint:origin];
	return YES;
}

/* **AUTOSCROLL IS "MAKE THE POINTER'S POINT VISIBLE", ONE STEP PER EVENT.** Apple scrolls by an amount that grows
 * with the distance outside the visible rectangle; this tier's `-scrollRectToVisible:` moves the origin JUST far
 * enough, and calling it with a zero-size rectangle at the pointer is the same gesture with the step taken out. It
 * returns NO when there is no clip view or the point is already visible, which is what lets a drag loop stop asking. */
- (BOOL)autoscroll:(NSEvent *)event
{
	NSPoint where;

	if (event == nil) {
		return NO;
	}
	where = [self convertPoint:[event locationInWindow] fromView:nil];
	return [self scrollRectToVisible:NSMakeRect(where.x, where.y, 0.0, 0.0)];
}

- (NSRect)adjustScroll:(NSRect)newVisible
{
	return newVisible;
}

- (void)scrollRect:(NSRect)aRect by:(NSSize)delta
{
	(void)aRect;
	(void)delta;
}

/* ---- THE HOOKS, WHICH A PLAIN VIEW MUST DECLARE AND CANNOT INVENT BEHAVIOUR FOR ---------------------- */

- (void)didAddSubview:(NSView *)subview
{
	/* A SUBTREE NOTICE WITH NOTHING TO DO HERE: the body belongs to whoever overrides it, and a plain view has
	 * nothing to say. Declaring it IS the point — a subclass that overrides it must find it declared. */
	(void)subview;
}

- (void)willRemoveSubview:(NSView *)subview
{
	(void)subview;
}

- (void)viewDidHide
{
}

- (void)viewDidUnhide
{
}

- (void)viewWillDraw
{
}

- (void)viewWillStartLiveResize
{
}

- (void)viewDidEndLiveResize
{
}

- (void)layout
{
	/* THE OVERRIDE POINT, AND NOW IT IS CALLED. `-layoutSubtreeIfNeeded` solves the subtree's constraints, writes
	 * their frames, and then calls this on every view whose `-needsLayout` was YES. A plain view has no arithmetic
	 * of its own to add, which is why the body stays empty; a subclass that wants to place something the equations
	 * cannot express overrides this, and a frame set made here does not start a second pass. */
}

- (void)updateTrackingAreas
{
	/* **THE ONE THING THIS DOOR OWES THAT IS NOT NOTHING, AND IT IS THE NOTIFICATION.** Apple's sentence is that a
	 * view whose tracking areas may have gone stale posts `NSViewDidUpdateTrackingAreasNotification`, and this class
	 * posts it — so the constant that used to be declared and never sent is now sent from the door it names. THE REST
	 * OF THE DOOR STAYS EMPTY ON PURPOSE: this engine resolves an area's rectangle against the view's CURRENT position
	 * on every motion rather than baking a screen rectangle at install time, so there is nothing here to repair. */
	[[NSNotificationCenter defaultCenter] postNotificationName:NSViewDidUpdateTrackingAreasNotification object:self];
}

/* ---- THE TRACKING AND TOOL-TIP FAMILY, WHOSE STORAGE THIS CLASS OWNS --------------------------------- */

- (NSTrackingRectTag)addTrackingRect:(NSRect)aRect owner:(id)anObject userData:(void *)data assumeInside:(BOOL)flag
{
	(void)aRect; (void)anObject; (void)data; (void)flag;
	/* A TAG RATHER THAN A NO-OP: the door's contract is an opaque handle the caller hands back to remove it, so
	 * this hands one out and keeps the list — ITS OWN LIST, because the area doors used to share this one and a tag
	 * and an `NSTrackingArea` in the same array is a mixture `-trackingAreas` would answer. */
	if (_cg_trackingRects == nil) {
		_cg_trackingRects = [[NSMutableArray alloc] init];
	}
	[_cg_trackingRects addObject:[NSValue valueWithPointer:(const void *)NULL]];
	return (NSTrackingRectTag)[_cg_trackingRects count];
}

- (void)removeTrackingRect:(NSTrackingRectTag)tag
{
	if (_cg_trackingRects != nil && tag > 0 && (NSUInteger)tag <= [_cg_trackingRects count]) {
		[_cg_trackingRects removeObjectAtIndex:(NSUInteger)tag - 1];
	}
}

- (void)addTrackingArea:(NSTrackingArea *)trackingArea
{
	if (trackingArea == nil) {
		return;
	}
	if (_trackingAreas == nil) {
		_trackingAreas = [[NSMutableArray alloc] init];
	}
	if (![_trackingAreas containsObject:trackingArea]) {
		[_trackingAreas addObject:trackingArea];	/* RETAINED by the array */
		/* **AND THE WINDOW RE-EVALUATES AT ONCE, WHICH IS THE ONE THING INSTALLING AN AREA OWES THE POINTER.** An area
		 * added while the pointer is ALREADY INSIDE its region would otherwise wait for a motion that may never come: a
		 * control that appears under a resting pointer would not prelight until the hand moved. Running the engine once
		 * at the current position is what makes the state true the moment it is asked about — and it is why the pointer's
		 * last position is a door on `NSWindow` rather than something only the event pump knows. */
		NSWindow *w = [self window];

		if (w != nil) {
			[w cg_updateTrackingForPoint:[w mouseLocationOutsideOfEventStream]];
		}
	}
}

- (void)removeTrackingArea:(NSTrackingArea *)trackingArea
{
	if (trackingArea == nil || _trackingAreas == nil) {
		return;
	}
	/* **AN AREA REMOVED WHILE THE POINTER IS INSIDE IT OWES ITS OWNER A FAREWELL**, because nothing will walk it again —
	 * the engine finds areas BY WALKING THE TREE, and this one is leaving the list. Without the exit, a caller who
	 * removes an area out from under the pointer leaves its owner in a state it can never leave: the same stuck
	 * prelight the per-area "inside" bit prevents for a REMOVED VIEW, one level down. */
	if ([trackingArea cg_isInside]) {
		id owner = [trackingArea owner];

		[trackingArea cg_setInside:NO];
		if ([owner respondsToSelector:@selector(mouseExited:)]) {
			[owner mouseExited:nil];
		}
	}
	[_trackingAreas removeObject:trackingArea];	/* RELEASED by the array */
}

- (NSToolTipTag)addToolTipRect:(NSRect)aRect owner:(id)anObject userData:(void *)data
{
	(void)aRect; (void)anObject; (void)data;
	if (_toolTips == nil) {
		_toolTips = [[NSMutableArray alloc] init];
	}
	[_toolTips addObject:[NSValue valueWithPointer:(const void *)NULL]];
	return (NSToolTipTag)[_toolTips count];
}

- (void)removeToolTip:(NSToolTipTag)tag
{
	if (_toolTips != nil && tag > 0 && (NSUInteger)tag <= [_toolTips count]) {
		[_toolTips removeObjectAtIndex:(NSUInteger)tag - 1];
	}
}

- (void)removeAllToolTips
{
	[_toolTips removeAllObjects];
}

/* ---- AND THE HANDS AND FLAGS THAT ANSWER FOR THEMSELVES ---------------------------------------------- */

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	/* APPLE'S OWN DEFAULT FOR A PLAIN VIEW, and the reason it is a door: a subclass that wants a click on an
	 * inactive window to count overrides it. */
	(void)theEvent;
	return NO;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)theEvent
{
	(void)theEvent;
	return NO;
}

- (BOOL)shouldDrawColor
{
	return YES;	/* a colour view is what this layer draws */
}

- (nullable id)menuForEvent:(NSEvent *)theEvent
{
	(void)theEvent;
	/* **AND THE REASON IS THE VIEW'S OWN MENU RATHER THAN A MISSING SUBSYSTEM.** This said "no NSMenu in this tier",
	 * which stopped being true at stage D: menus exist, they are drawn, and the pop-up button beside them raises one.
	 * What a view answers here is ITS OWN menu, and this class gives a caller no way to set one — so nil is the truth
	 * for a plain view either way, and the note now says which truth it is. */
	return nil;
}

- (nullable id)makeBackingLayer
{
	return nil;	/* no CALayer in this tier */
}

- (BOOL)mouse:(NSPoint)aPoint inRect:(NSRect)aRect
{
	/* THE PRE-10.0 DOOR, WHICH ANSWERED WHETHER A POINT IS IN A RECTANGLE: it is arithmetic, so it answers. */
	return NSPointInRect(aPoint, aRect);
}

/* AND THE STATE-STACK DOORS: `-lockFocusIfCanDraw` IS REAL, because it is the question this view's `-canDraw`
 * already answers, and the four state-stack doors REFUSE BY NAME — this tier draws through a `CGContext` and has no
 * stack for them to push. */

- (BOOL)lockFocusIfCanDraw
{
	return [self canDraw];
}

- (BOOL)lockFocusIfCanDrawInContext:(NSGraphicsContext *)context
{
	(void)context;
	return [self canDraw];
}

/* **THE FOCUS LOCK PAIR REFUSES BY NAME.** A view draws into the caller's context — a window's backing store, a
 * bitmap rep — and this tier has no per-view graphics-state stack for a lock to push and an unlock to pop. The
 * question form above is answerable and stays real; these two would have to invent the stack. */
- (void)lockFocus
{
	fn_refuse_window("-lockFocus", "a lockable per-view graphics-state stack; this tier draws into the caller's context");
}

- (void)unlockFocus
{
	fn_refuse_window("-unlockFocus", "a lockable per-view graphics-state stack; this tier draws into the caller's context");
}

/* AND THE COORDINATE-SYSTEM TRIO: RECORDED, WITH THE EFFECT NAMED — no transform is applied to this tier's drawing,
 * and each door keeps what it was asked for. */
- (void)translateOriginToPoint:(NSPoint)translation
{
	_cg_translation = translation;
}

- (void)scaleUnitSquareToSize:(NSSize)newUnitSize
{
	_cg_unitSquareSize = newUnitSize;
}

- (void)rotateByAngle:(CGFloat)angle
{
	_cg_rotation = angle;
}

- (NSPoint)cg_translation
{
	return _cg_translation;
}

- (NSSize)cg_unitSquareSize
{
	return _cg_unitSquareSize;
}

- (CGFloat)cg_rotation
{
	return _cg_rotation;
}

- (void)allocateGState
{
	fn_refuse_window("-allocateGState", "a graphics-state STACK: this tier draws through a CGContext");
}

- (void)releaseGState
{
	fn_refuse_window("-releaseGState", "a graphics-state STACK: this tier draws through a CGContext");
}

- (void)setUpGState
{
	fn_refuse_window("-setUpGState", "a graphics-state STACK: this tier draws through a CGContext");
}

- (void)renewGState
{
	fn_refuse_window("-renewGState", "a graphics-state STACK: this tier draws through a CGContext");
}

/* ---- AND THE PRINTING, DRAG AND FULL-SCREEN FAMILIES, REFUSED BY NAME -------------------------------- */

/* **THE VIEW'S HALF OF A PRINT JOB, AND THE DEFAULTS ARE APPLE'S.** `NSPrintOperation` asks `-knowsPageRange:` first;
 * a view that answers YES supplies `-rectForPage:` per page and the operation draws exactly those rectangles. One that
 * answers NO is cut up vertically by the ticket's imageable height, with the two `-adjustPage…` doors given each proposed
 * break to round — a table view that wants a break between rows is the reason those doors exist.
 *
 * THE DOCUMENT AND PAGE DOORS ARE NOTIFICATIONS. A view that wants a border drawn over its page overrides
 * `-drawPageBorderWithSize:`; the default does nothing, which is what a view with no opinion should do. */
- (void)beginDocument
{
}

- (void)endDocument
{
}

- (void)beginPageInRect:(NSRect)aRect atPlacement:(NSPoint)location
{
	(void)aRect;
	(void)location;
}

- (void)endPage
{
}

- (void)drawPageBorderWithSize:(NSSize)borderSize
{
	(void)borderSize;
}

- (void)drawSheetBorderWithSize:(NSSize)borderSize
{
	(void)borderSize;
}

- (BOOL)knowsPageRange:(NSRangePointer)range
{
	/* **NO IS THE DEFAULT, AND IT MEANS "LET THE OPERATION PAGINATE ME"**, not "I cannot print": the operation then
	 * asks `-rectForPage:` never and the page-adjustment doors instead. */
	(void)range;
	return NO;
}

- (void)adjustPageWidthNew:(CGFloat *)newRight left:(CGFloat)oldLeft right:(CGFloat)oldRight limit:(CGFloat)rightLimit
{
	(void)oldLeft;
	(void)oldRight;
	if (newRight != NULL && *newRight > rightLimit) {
		*newRight = rightLimit;
	}
}

- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)oldTop bottom:(CGFloat)oldBottom limit:(CGFloat)bottomLimit
{
	(void)oldTop;
	(void)oldBottom;
	if (newBottom != NULL && *newBottom > bottomLimit) {
		*newBottom = bottomLimit;
	}
}

- (NSRect)rectForPage:(NSInteger)page
{
	/* PAGE ONE IS THE WHOLE VIEW; any other page is empty, and the operation skips an empty rectangle rather than
	 * drawing it. A view that knows its range overrides this and `-knowsPageRange:` together. */
	return (page == 1) ? [self bounds] : NSZeroRect;
}

- (NSPoint)locationOfPrintRect:(NSRect)aRect
{
	return NSMakePoint(NSMinX(aRect), NSMinY(aRect));
}

- (nullable id)rulerView
{
	/* A PLAIN VIEW IS NOT PART OF A RULER: `NSRulerView` exists, and its CLIENT is a view, but this printing-era door
	 * asks for a ruler attached to the receiver in the sense this tier does not build. Nil is the answer; the ruler's
	 * client protocol is the nine doors on the category in `NSRulerView.h`. */
	return nil;
}

- (void)showDefinitionForAttributedString:(NSAttributedString *)attrString atPoint:(NSPoint)textBaselineOrigin
{
	(void)attrString; (void)textBaselineOrigin;
	fn_refuse_window("-showDefinitionForAttributedString:atPoint:", "the definition look-up, and a text substrate to show it in");
}

- (void)showDefinitionForAttributedString:(NSAttributedString *)attrString range:(NSRange)targetRange
				 options:(NSDictionary *)options
		    baselineOriginProvider:(NSPoint (^)(NSRange adjustedRange))originProvider
{
	(void)attrString; (void)targetRange; (void)options; (void)originProvider;
	fn_refuse_window("-showDefinitionForAttributedString:range:options:baselineOriginProvider:",
			 "the definition look-up, and a text substrate to show it in");
}

- (void)writeEPSInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard
{
	NSData *data;

	if (pasteboard == nil) {
		fn_refuse_window("-writeEPSInsideRect:toPasteboard:", "a pasteboard");
		return;
	}
	data = [self dataWithEPSInsideRect:rect];
	if (data == nil) {
		return;
	}
	[pasteboard declareTypes:[NSArray arrayWithObject:NSPostScriptPboardType] owner:nil];
	[pasteboard setData:data forType:NSPostScriptPboardType];
}

- (void)writePDFInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard
{
	NSData *data;

	if (pasteboard == nil) {
		fn_refuse_window("-writePDFInsideRect:toPasteboard:", "a pasteboard");
		return;
	}
	data = [self dataWithPDFInsideRect:rect];
	if (data == nil) {
		return;
	}
	[pasteboard declareTypes:[NSArray arrayWithObject:NSPDFPboardType] owner:nil];
	[pasteboard setData:data forType:NSPDFPboardType];
}

- (BOOL)dragFile:(NSString *)filename fromRect:(NSRect)rect slideBack:(BOOL)aFlag event:(NSEvent *)event
{
	(void)filename; (void)rect; (void)aFlag; (void)event;
	fn_refuse_window("-dragFile:fromRect:slideBack:event:", "a drag session (the window server's drag loop)");
	return NO;
}

- (BOOL)dragPromisedFilesOfTypes:(NSArray *)typeArray fromRect:(NSRect)rect source:(id)sourceObject
			slideBack:(BOOL)aFlag event:(NSEvent *)event
{
	(void)typeArray; (void)rect; (void)sourceObject; (void)aFlag; (void)event;
	fn_refuse_window("-dragPromisedFilesOfTypes:fromRect:source:slideBack:event:", "a drag session (the window server's drag loop)");
	return NO;
}

- (BOOL)enterFullScreenMode:(NSScreen *)screen withOptions:(NSDictionary *)options
{
	(void)screen; (void)options;
	fn_refuse_window("-enterFullScreenMode:withOptions:", "the full-screen mode, which is the window manager's");
	return NO;
}

- (void)exitFullScreenModeWithOptions:(NSDictionary *)options
{
	(void)options;
	fn_refuse_window("-exitFullScreenModeWithOptions:", "the full-screen mode, which is the window manager's");
}

/* ---- THE VIEW'S PROPERTIES ---------------------------------------------------------------------------- */

- (BOOL)hiddenOrHasHiddenAncestor
{
	NSView *v = self;

	while (v != nil) {
		if ([v isHidden]) {
			return YES;
		}
		v = [v superview];
	}
	return NO;
}

- (nullable NSView *)opaqueAncestor
{
	/* APPLE'S DOOR IS THE CLOSEST ANCESTOR THAT IS OPAQUE, and `-isOpaque` is the door a subclass answers from what
	 * it draws: a plain view answers NO, so a plain chain has no opaque ancestor and nil is the answer. */
	NSView *v = [self superview];

	while (v != nil) {
		if ([v isOpaque]) {
			return v;
		}
		v = [v superview];
	}
	return nil;
}

- (nullable NSScrollView *)enclosingScrollView
{
	/* **THE WALK THAT COULD NOT BE WRITTEN UNTIL THE CLASS EXISTED.** This door used to answer nil BECAUSE THERE WAS
	 * NO `NSScrollView` — a scroll view is the frame, the scrollers and the ruler, and only the clip view was here —
	 * and the comment recorded the compiler's own answer (`use of undeclared identifier 'NSScrollView'`). The class
	 * exists now, so the walk does too: the nearest ancestor that IS a scroll view, exactly as `-opaqueAncestor`
	 * above walks for the nearest opaque one. */
	NSView *v = [self superview];

	while (v != nil) {
		if ([v isKindOfClass:[NSScrollView class]]) {
			return (NSScrollView *)v;
		}
		v = [v superview];
	}
	return nil;
}

- (nullable NSView *)enclosingMenuItem
{
	return nil;	/* this tier has no menus, so there is no item to be enclosed in */
}

- (BOOL)rectPreservedDuringLiveResize
{
	/* ASKED RATHER THAN STORED: the door that answers whether this view preserves its content is the one Apple
	 * declares the promise on. */
	return [self preservesContentDuringLiveResize];
}

- (nullable NSArray *)registeredDraggedTypes
{
	return _cg_registeredDraggedTypes;
}

/* **AND THE THREE KEY-VIEW DOORS, WHICH WALK THE CHAIN THIS CLASS ALREADY OWNS.** `_nextKeyView` is forward-only,
 * so the previous view is the one that POINTS HERE — found by walking from the window's content view through the
 * public door, with a BOUND so that a cycle a caller made cannot hang a getter. The two "valid" doors walk to the
 * neighbour that accepts the key. */
- (nullable NSView *)previousKeyView
{
	NSView *v = [[self window] contentView];
	NSUInteger guard = 0;

	while (v != nil && guard++ < 100000) {
		if ([v nextKeyView] == self) {
			return v;
		}
		v = [v nextKeyView];
	}
	return nil;
}

- (nullable NSView *)nextValidKeyView
{
	NSView *v = [self nextKeyView];
	NSUInteger guard = 0;

	while (v != nil && guard++ < 100000) {
		if ([v canBecomeKeyView]) {
			return v;
		}
		v = [v nextKeyView];
	}
	return nil;
}

- (nullable NSView *)previousValidKeyView
{
	NSView *v = [self previousKeyView];
	NSUInteger guard = 0;

	while (v != nil && guard++ < 100000) {
		if ([v canBecomeKeyView]) {
			return v;
		}
		v = [v previousKeyView];
	}
	return nil;
}

- (BOOL)canBecomeKeyView
{
	/* A VIEW THAT ACCEPTS FIRST RESPONDER AND IS NOT HIDDEN, which is what Apple's door means. */
	return [self acceptsFirstResponder] && ![self hiddenOrHasHiddenAncestor];
}

- (BOOL)canDraw
{
	/* THIS VIEW CAN BE ASKED TO DRAW; the surface it draws into is the caller's, the substrate choice
	 * `-cacheDisplayInRect:toBitmapImageRep:` already records for this layer. */
	return YES;
}

- (BOOL)mouseDownCanMoveWindow
{
	/* NO, BECAUSE MOVING A WINDOW BY ITS BACKGROUND IS THE WINDOW'S DOOR IN THIS TIER
	 * (`-setMovableByWindowBackground:`), not a view's. */
	return NO;
}

- (BOOL)needsPanelToBecomeKey
{
	return NO;	/* Apple's answer for a plain view: a view that needs the key says so by overriding this. */
}

- (BOOL)inFullScreenMode
{
	/* THE FULL-SCREEN MODE IS THE MANAGER'S — the keys this class declares name its dictionary — and nothing here
	 * enters one. */
	return NO;
}

/* **THE ERA'S `is`-PREFIXED SPELLINGS**, aliases of the older ones this class shipped first. */
- (BOOL)isInFullScreenMode { return [self inFullScreenMode]; }
- (BOOL)isHiddenOrHasHiddenAncestor { return [self hiddenOrHasHiddenAncestor]; }

- (BOOL)rotatedFromBase
{
	return (_cg_rotation != 0.0)
		|| (_frameCenterRotation != 0.0);	/* the stored rotation and the separate frame-centre one */
}

- (BOOL)rotatedOrScaledFromBase
{
	return [self rotatedFromBase]
		|| (_cg_unitSquareSize.width != 1.0 || _cg_unitSquareSize.height != 1.0);
}

- (BOOL)isRotatedFromBase { return [self rotatedFromBase]; }
- (BOOL)isRotatedOrScaledFromBase { return [self rotatedOrScaledFromBase]; }

/* **ONE STORED ROTATION, TWO APPLE SPELLINGS.** This tier applies no transform to its drawing, so the frame and
 * bounds rotations are the same record — `-rotateByAngle:` writes it too — and both getters report it rather than two
 * numbers that could disagree. */
- (CGFloat)boundsRotation
{
	return _cg_rotation;
}

- (CGFloat)frameRotation
{
	return _cg_rotation;
}

- (void)setBoundsRotation:(CGFloat)angle
{
	_cg_rotation = angle;
	[self setNeedsDisplay:YES];
}

- (void)setFrameRotation:(CGFloat)angle
{
	_cg_rotation = angle;
	[self setNeedsDisplay:YES];
}

- (CGFloat)heightAdjustLimit
{
	/* ZERO IS THE HONEST LIMIT: Apple's pair say how much of a page may be clipped to make a view fit, and this
	 * tier prints nothing — so it permits no adjustment rather than inventing one. */
	return 0.0;
}

- (CGFloat)widthAdjustLimit
{
	return 0.0;
}

- (CGFloat)frameCenterRotation
{
	return _frameCenterRotation;
}

- (void)setFrameCenterRotation:(CGFloat)angle
{
	_frameCenterRotation = angle;
}

/* ---- THE STORES, THE FLAG PAIRS FIRST ------------------------------------------------------------------ */

#define FN_VIEW_PAIR(setter, getter, ivar)                       \
	- (void)setter:(BOOL)flag { ivar = flag; }               \
	- (BOOL)getter { return ivar; }

FN_VIEW_PAIR(setAcceptsTouchEvents, acceptsTouchEvents, _acceptsTouchEvents)
FN_VIEW_PAIR(setWantsRestingTouches, wantsRestingTouches, _wantsRestingTouches)
FN_VIEW_PAIR(setCanDrawConcurrently, canDrawConcurrently, _canDrawConcurrently)
FN_VIEW_PAIR(setWantsDefaultClipping, wantsDefaultClipping, _wantsDefaultClipping)
FN_VIEW_PAIR(setWantsLayer, wantsLayer, _wantsLayer)
FN_VIEW_PAIR(setAutoresizesSubviews, autoresizesSubviews, _autoresizesSubviews)
FN_VIEW_PAIR(setPostsBoundsChangedNotifications, postsBoundsChangedNotifications, _postsBoundsChangedNotifications)

- (NSInteger)tag
{
	return _tag;
}

- (void)setTag:(NSInteger)anInteger
{
	_tag = anInteger;
}

- (NSUInteger)autoresizingMask
{
	return _autoresizingMask;
}

- (void)setAutoresizingMask:(NSUInteger)mask
{
	_autoresizingMask = mask;
	/* THE GAPS DESCRIBED THE OLD MASK, so the capture no longer describes this view. */
	[self cg_clearCapturedAutoresizingFrame];
}

- (nullable NSString *)toolTip
{
	return _toolTip;
}

- (void)setToolTip:(NSString *)string
{
	[string retain];
	[_toolTip release];
	_toolTip = string;
}

- (nullable NSArray *)trackingAreas
{
	return _trackingAreas;
}

- (NSViewLayerContentsPlacement)layerContentsPlacement
{
	return _layerContentsPlacement;
}

- (void)setLayerContentsPlacement:(NSViewLayerContentsPlacement)placement
{
	_layerContentsPlacement = placement;
}

- (NSViewLayerContentsRedrawPolicy)layerContentsRedrawPolicy
{
	return _layerContentsRedrawPolicy;
}

- (void)setLayerContentsRedrawPolicy:(NSViewLayerContentsRedrawPolicy)policy
{
	_layerContentsRedrawPolicy = policy;
}

- (nullable NSArray *)backgroundFilters
{
	return _backgroundFilters;
}

- (void)setBackgroundFilters:(NSArray *)filters
{
	[filters retain];
	[_backgroundFilters release];
	_backgroundFilters = filters;
}

- (nullable id)compositingFilter
{
	return _compositingFilter;
}

- (void)setCompositingFilter:(id)filter
{
	_compositingFilter = filter;
}

- (nullable NSArray *)contentFilters
{
	return _contentFilters;
}

- (void)setContentFilters:(NSArray *)filters
{
	[filters retain];
	[_contentFilters release];
	_contentFilters = filters;
}

- (nullable id)shadow
{
	return _shadow;
}

- (void)setShadow:(id)shadow
{
	_shadow = shadow;
}

- (nullable id)layer
{
	return nil;	/* no CALayer in this tier: the drawing substrate is a CGContext */
}

- (void)setLayer:(id)newLayer
{
	(void)newLayer;
	fn_refuse_window("-setLayer:", "a layer tree; this tier draws views directly and has no CALayer substrate");
}

- (nullable id)inputContext
{
	/* **A VIEW THAT IS A TEXT INPUT CLIENT OWNS A CONTEXT; EVERY OTHER VIEW ANSWERS NIL.** Apple's door is what
	 * `NSResponder -interpretKeyEvents:` reads to find where a key goes, so a view with no context is a view with no
	 * key handling — which is the truth for everything that is not a text surface. The context is made once and kept,
	 * and its client is this view, borrowed. */
	if (_cg_inputContext == nil && [self conformsToProtocol:@protocol(NSTextInput)]) {
		_cg_inputContext = [[NSTextInputContext alloc] initWithClient:(id <NSTextInput>)self];
	}
	return _cg_inputContext;
}

- (nullable id)defaultMenu
{
	return nil;	/* this view's own default menu, which no caller can set: NOT a missing NSMenu — see -menuForEvent: */
}

- (nullable id)pageHeader
{
	return nil;	/* the printing substrate is not here — `-print:` refuses on the same ground */
}

- (void)setPageHeader:(id)header
{
	_pageHeader = header;	/* RECORDED: nothing reads it, and nothing prints */
}

- (nullable id)pageFooter
{
	return nil;
}

- (void)setPageFooter:(id)footer
{
	_pageFooter = footer;
}

- (nullable NSString *)printJobTitle
{
	/* THE WINDOW'S TITLE WHEN THERE IS ONE, and the empty string otherwise — a printed page with no name is better
	 * than one named after a class. */
	NSString *title = ([self window] != nil) ? [[self window] title] : nil;

	return (title != nil) ? title : @"";
}

- (NSFocusRingType)focusRingType
{
	return _focusRingType;
}

- (void)setFocusRingType:(NSFocusRingType)focusRingType
{
	_focusRingType = focusRingType;
}

+ (NSFocusRingType)defaultFocusRingType
{
	/* THE APPLICATION-WIDE DEFAULT, which this tier has no door to change — so it is the enum's first member, stated
	 * rather than pretending to be a preference. */
	return NSFocusRingTypeDefault;
}

- (nullable NSView *)focusView
{
	return _focusView;
}

- (void)setFocusView:(NSView *)aView
{
	_focusView = aView;	/* NOT RETAINED: a focus view is a reference, not an ownership */
}

/* ---- THE VIEW'S NAMED VALUES -------------------------------------------------------------------------- */

/* THE STRINGS ARE THE NAMES, the house pattern this tree's notifications already use; the two legacy background-style
 * spellings carry the value of the LIVE case they were renamed to, which is what makes a comparison against either
 * spelling answer the same thing. */
NSString *NSViewDidUpdateTrackingAreasNotification = @"NSViewDidUpdateTrackingAreasNotification";
NSString *NSViewFocusDidChangeNotification = @"NSViewFocusDidChangeNotification";
NSString *NSFullScreenModeSetting = @"NSFullScreenModeSetting";
NSString *NSFullScreenModeAllScreens = @"NSFullScreenModeAllScreens";
NSString *NSFullScreenModeApplicationPresentationOptions = @"NSFullScreenModeApplicationPresentationOptions";
NSString *NSDefinitionPresentationTypeKey = @"NSDefinitionPresentationType";
NSString *NSDefinitionPresentationTypeDictionaryApplication = @"DictionaryApplication";
NSString *NSDefinitionPresentationTypeOverlay = @"Overlay";

/* ---- THE DOORS APPLE DECLARES ON THE VIEW ------------------------------------------------------------ */

/* FOUR OF THE SEVEN ARE THE WINDOW'S TWINS, and they are here because these are THIS class's ledger rows: the sweep
 * matches names globally, so they were shipped on NSWindow's declarations until now. The reasons are the shared
 * ones in the shared place — see AppKitRefusal.h — because a second copy of a reason is a second chance for the two
 * classes to disagree about it. */

- (nullable NSData *)dataWithEPSInsideRect:(NSRect)rect
{
	CFMutableDataRef eps;
	CGDataConsumerRef consumer;
	CGContextRef cg;
	NSGraphicsContext *context;
	NSData *data;
	CGRect page;

	if (rect.size.width <= 0.0 || rect.size.height <= 0.0) {
		fn_refuse_window("-dataWithEPSInsideRect:", "a rectangle with a positive width and height");
		return nil;
	}
	eps = CFDataCreateMutable(kCFAllocatorDefault, 0);
	if (eps == NULL) {
		return nil;
	}
	consumer = CGDataConsumerCreateWithCFData(eps);
	if (consumer == NULL) {
		CFRelease(eps);
		return nil;
	}
	page = CGRectMake(0.0, 0.0, rect.size.width, rect.size.height);
	cg = CGEPSContextCreate(consumer, &page, NULL);
	CGDataConsumerRelease(consumer);
	if (cg == NULL) {
		CFRelease(eps);
		return nil;
	}
	context = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];
	if (context == nil) {
		CGContextRelease(cg);
		CFRelease(eps);
		return nil;
	}
	CGEPSContextBeginPage(cg, NULL);
	/* THE SAME PAGE SET-UP AS THE PDF DOOR: the requested rectangle is translated to the EPS origin and then
	 * mirrored, because a view draws y-down and PostScript's user space is y-up. */
	CGContextTranslateCTM(cg, -rect.origin.x, -rect.origin.y);
	CGContextTranslateCTM(cg, 0.0, rect.size.height);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[self displayRectIgnoringOpacity:rect inContext:context];
	CGEPSContextEndPage(cg);
	CGEPSContextClose(cg);
	data = [NSData dataWithBytes:CFDataGetBytePtr(eps) length:(NSUInteger)CFDataGetLength(eps)];
	CGContextRelease(cg);
	CFRelease(eps);
	return data;
}

- (nullable NSData *)dataWithPDFInsideRect:(NSRect)rect
{
	CFMutableDataRef pdf;
	CGDataConsumerRef consumer;
	CGContextRef cg;
	NSGraphicsContext *context;
	NSData *data;
	CGRect page;

	if (rect.size.width <= 0.0 || rect.size.height <= 0.0) {
		fn_refuse_window("-dataWithPDFInsideRect:", "a rectangle with a positive width and height");
		return nil;
	}
	pdf = CFDataCreateMutable(kCFAllocatorDefault, 0);
	if (pdf == NULL) {
		return nil;
	}
	consumer = CGDataConsumerCreateWithCFData(pdf);
	if (consumer == NULL) {
		CFRelease(pdf);
		return nil;
	}
	page = CGRectMake(0.0, 0.0, rect.size.width, rect.size.height);
	cg = CGPDFContextCreate(consumer, &page, NULL);
	CGDataConsumerRelease(consumer);
	if (cg == NULL) {
		CFRelease(pdf);
		return nil;
	}
	context = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];
	if (context == nil) {
		CGContextRelease(cg);
		CFRelease(pdf);
		return nil;
	}
	CGPDFContextBeginPage(cg, NULL);
	/* **THE RECT BECOMES THE PAGE, AND THE VIEW'S SPACE IS Y-DOWN.** A view draws in the orientation its
	 * window's surface gives it, which is the y-down one (`-cacheDisplayInRect:` builds its canvas with
	 * `flipped:YES` for the same reason). The page is y-up, so the requested rectangle is translated to the
	 * page's origin and then mirrored; after this the view's own `-displayRect:` walk needs no changes. */
	CGContextTranslateCTM(cg, -rect.origin.x, -rect.origin.y);
	CGContextTranslateCTM(cg, 0.0, rect.size.height);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[self displayRectIgnoringOpacity:rect inContext:context];
	CGPDFContextEndPage(cg);
	CGPDFContextClose(cg);
	data = [NSData dataWithBytes:CFDataGetBytePtr(pdf) length:(NSUInteger)CFDataGetLength(pdf)];
	CGContextRelease(cg);
	CFRelease(pdf);
	return data;
}

- (void)print:(id)sender
{
	(void)sender;
	[[NSPrintOperation printOperationWithView:self] runOperation];
}

/* AND THE THREE THAT ANSWER RATHER THAN REFUSE. */

- (NSInteger)gState
{
	/* A VALUE, NOT A MISSING ONE: this tier draws through a `CGContext`, so there is no graphics-state ID, and 0 is
	 * the truth about that rather than a stand-in for one. */
	return 0;
}

/* ---- THE DRAG SOURCE'S TWO DOORS ---------------------------------------------------------------- */

/* **THE SESSION IS `NSDragging.m`'S; THE DOORS ARE THE VIEW'S.** A category in the session's file made the class's
 * own `@implementation` incomplete, which is exactly what the compiler said: Apple declares these on NSView, so this
 * is where they belong. The legacy door is the modern one with one item made from the image — and it is ASYNCHRONOUS:
 * the operation reaches the source's ended callback, not this door's return value, which the header states. */
- (nullable NSDraggingSession *)beginDraggingSessionWithItems:(NSArray *)items
							event:(NSEvent *)event
						       source:(id <NSDraggingSource>)source
{
	return [NSDraggingSession cg_beginWithItems:items event:event source:source view:self
				      pasteboard:nil slideBack:YES];
}

- (void)dragImage:(NSImage *)anImage at:(NSPoint)viewLocation offset:(NSSize)initialOffset
	    event:(NSEvent *)event pasteboard:(NSPasteboard *)pboard source:(id)sourceObj
	 slideBack:(BOOL)slideFlag
{
	NSDraggingItem *item;
	NSImage *image = anImage;

	if (image == nil) {
		/* AN IMAGE IS WHAT THE DOOR IS NAMED FOR, and a nil one would make a session whose pointer offset is
		 * undefined. A one-point transparent image is the honest stand-in for "no picture". */
		image = [[[NSImage alloc] initWithSize:NSMakeSize(1.0, 1.0)] autorelease];
	}
	item = [[[NSDraggingItem alloc] initWithPasteboardWriter:nil] autorelease];
	[item setDraggingFrame:NSMakeRect(viewLocation.x, viewLocation.y,
					  [image size].width, [image size].height)
		      contents:image];
	(void)initialOffset;	/* THE OFFSET IS DERIVED FROM THE EVENT: `at:` already says where the image is, and the
				 * event says where the pointer is, which is the pair the session needs. */
	(void)[NSDraggingSession cg_beginWithItems:[NSArray arrayWithObject:item] event:event source:sourceObj
					      view:self pasteboard:pboard slideBack:slideFlag];
}

- (void)registerForDraggedTypes:(NSArray *)newTypes
{
	/* THE SET THE DESTINATION SEARCH READS.** `-registerForDraggedTypes:` REPLACES rather than appends, which is
	 * Apple's contract (the header records it), and the list is read back through `-cg_registeredDraggedTypes`
	 * because Apple declares no getter. */
	if (_cg_registeredDraggedTypes == nil) {
		_cg_registeredDraggedTypes = [[NSMutableArray alloc] init];
	}
	[_cg_registeredDraggedTypes removeAllObjects];
	if (newTypes != nil) {
		[_cg_registeredDraggedTypes addObjectsFromArray:newTypes];
	}
}

- (void)unregisterDraggedTypes
{
	[_cg_registeredDraggedTypes removeAllObjects];
}

- (nullable NSArray *)cg_registeredDraggedTypes
{
	return _cg_registeredDraggedTypes;
}

/* **THE DESTINATION'S DEFAULT ANSWERS, WHICH ARE APPLE'S.** A plain view refuses a drag (None), accepts no drop
 * (perform NO), and says it wants periodic updates even though this tier has no timer to send them — the answer is
 * what a destination expects to read, and the absence of a timer is stated in `NSDragging.h` rather than hidden in
 * a NO. `-prepareForDragOperation:` defaults YES because preparing is the destination's chance to change its mind,
 * not an extra gate. */
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	(void)sender;
	return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
	(void)sender;
	return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	(void)sender;
}

- (void)draggingEnded:(id <NSDraggingInfo>)sender
{
	(void)sender;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
	return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
	return NO;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
}

- (BOOL)wantsPeriodicDraggingUpdates
{
	return YES;
}

- (BOOL)cg_acceptsDraggedTypes:(NSArray *)types
{
	NSUInteger i;

	if (_cg_registeredDraggedTypes == nil || types == nil) {
		return NO;
	}
	for (i = 0; i < [types count]; i++) {
		if ([_cg_registeredDraggedTypes containsObject:[types objectAtIndex:i]]) {
			return YES;
		}
	}
	return NO;
}


- (void)setFrame:(NSRect)frameRect
{
	NSRect previousFrame = _frame;

	_frame = frameRect;
	/* **THE RECTANGLE THE VIEW JUST LEFT BELONGS TO THE SUPERVIEW NOW.** A moved view cannot paint where it no
	 * longer is, so the parent has to repaint the vacated strip; without this a damage-region draw leaves the old
	 * column or pane behind. */
	if (_superview != nil && (previousFrame.origin.x != _frame.origin.x
				  || previousFrame.origin.y != _frame.origin.y
				  || previousFrame.size.width != _frame.size.width
				  || previousFrame.size.height != _frame.size.height)) {
		[_superview setNeedsDisplayInRect:previousFrame];
	}
	/* THE SIZE IS SHARED AND THE ORIGINS ARE NOT — see the header for what this deliberately does not
	 * model (a bounds origin that is a scroll offset). */
	_bounds = NSMakeRect(_bounds.origin.x, _bounds.origin.y, frameRect.size.width,
			     frameRect.size.height);
	_needsDisplay = YES;
	[self cg_frameDidChangeFrom:previousFrame];
	/* **A FRAME SET IS A REQUEST, NOT A VERDICT, FOR A MANAGED VIEW.** If an active constraint names this view its
	 * next layout pass will write the frame the equations want; if none does, the frame stands and the request is
	 * the fast path's single load. */
	_needsLayout = YES;
	[self cg_requestLayout];
}

/* **MOVING A FRAME IS A FRAME CHANGE WITHOUT A SIZE CHANGE.** The old rectangle belongs to the superview for the
 * same reason `-setFrame:` says so, the bounds keep their origin and size, and the notice path is the one
 * `-cg_frameDidChangeFrom:` already owns. */
- (void)setFrameOrigin:(NSPoint)newOrigin
{
	NSRect previousFrame = _frame;

	if (NSEqualPoints(_frame.origin, newOrigin)) {
		return;
	}
	_frame.origin = newOrigin;
	if (_superview != nil) {
		[_superview setNeedsDisplayInRect:previousFrame];
	}
	_needsDisplay = YES;
	[self cg_frameDidChangeFrom:previousFrame];
	_needsLayout = YES;
	[self cg_requestLayout];
}

- (NSRect)bounds
{
	return _bounds;
}

- (void)setBounds:(NSRect)boundsRect
{
	_bounds = boundsRect;
	_frame = NSMakeRect(_frame.origin.x, _frame.origin.y, boundsRect.size.width,
			    boundsRect.size.height);
	_needsDisplay = YES;
}

- (BOOL)isFlipped
{
	return _flipped;
}

- (void)setFlipped:(BOOL)flag
{
	_flipped = flag ? YES : NO;
}

- (BOOL)needsDisplay
{
	return _needsDisplay;
}

- (void)setNeedsDisplay:(BOOL)flag
{
	_needsDisplay = flag ? YES : NO;
	/* THE COARSE FORM MARKS THE WHOLE BOUNDS, so a caller that only ever says "all of it" and one that
	 * invalidates a strip end up in the SAME region — the door below is what consults it. */
	if (flag) {
		_dirtyRect = _bounds;
		_hasDirtyRect = YES;
		_dirtyRects[0] = _bounds;
		_dirtyCount = 1;
		/* **AND THE WINDOW IS TOLD, WHICH IS THE LINE WHOSE ABSENCE MADE A CONTROL'S VALUE INVISIBLE.**
		 * `NSWindow -displayIfNeeded` gates on the WINDOW's `-viewsNeedDisplay`; a view marking ITSELF dirty used to
		 * leave that flag alone, so `[window displayIfNeeded]` — the door a tracking loop calls to make what it just
		 * changed appear — did nothing at all, and the ONLY things that ever set the flag were a compositor
		 * configure and `-update`. MEASURED: a slider's value moved, its action fired on every point, and its knob
		 * sat at 50 through the whole drag, because nothing between the value and the pixels asked the window to
		 * paint. This is the missing half of the pair, and it is one walk up the superview chain. */
		[[self window] setViewsNeedDisplay:YES];
	} else {
		_hasDirtyRect = NO;
	}
}

- (BOOL)isHidden
{
	return _hidden;
}

- (void)setHidden:(BOOL)flag
{
	BOOL hidden = flag ? YES : NO;

	if (_hidden == hidden) {
		return;
	}
	_hidden = hidden;
	/* **THE PIXELS THE VIEW USED TO OCCUPY ARE NOW SOMEONE ELSE'S TO PAINT.** Hiding a subview changes what the
	 * tree draws but does not, by itself, make the parent redraw the rectangle the subview leaves behind — MEASURED
	 * on the browser's autohiding horizontal bar, whose ink stayed on the window after it hid. The frame is in the
	 * SUPERVIEW's coordinates, which is exactly what the invalidation wants. */
	if (_superview != nil) {
		[_superview setNeedsDisplayInRect:_frame];
	} else {
		[self setNeedsDisplay:YES];
	}
}

- (NSArray *)subviews
{
	if (_subviews == nil) {
		return [NSArray array];
	}
	return _subviews;
}

- (NSView *)superview
{
	return _superview;
}

- (void)addSubview:(NSView *)aView
{
	if (aView == nil || aView == self) {
		return;
	}
	/* A VIEW HAS ONE SUPERVIEW, so adding one that has a parent MOVES it — Apple's behaviour, and the
	 * reason this is not just an append. */
	if ([aView superview] != nil) {
		[aView removeFromSuperview];
	}
	if (_subviews == nil) {
		_subviews = [[NSMutableArray alloc] init];
	}
	/* THE TWO MOVE CALLS COME FROM HERE, AND THAT IS THE POINT OF THEM: a view that arrives somewhere is
	 * TOLD, before it is in the array and after, which is what lets a subclass follow its context — the
	 * window it is now in and the superview it now has. */
	[aView viewWillMoveToSuperview:self];
	/* A TRANSLATED MASK IS MEASURED AGAINST ONE PARENT, so a view that arrives somewhere new has its capture thrown
	 * away; the next pass records the gaps in THIS parent. */
	[aView cg_clearCapturedAutoresizingFrame];
	/* THE ARRAY OWNS IT (it retains), and the borrowed link is set from here because `_superview` is
	 * PROTECTED and only a method of this class may write another instance's. */
	[_subviews addObject:aView];
	aView->_superview = self;
	[aView cg_setWindow:_window];
	[aView viewDidMoveToSuperview];
	/* **A NEW CHILD MAY ALREADY BE NAMED BY AN EQUATION** — a constraint can be built before its second view is in a
	 * tree, and it becomes solvable the moment the two views share an ancestor. The parent asks for a pass rather
	 * than leaving the new child at whatever frame its constructor chose. */
	_needsLayout = YES;
	[self cg_requestLayout];
}

/* **A POSITIONED ADD IS AN ADD AND A REORDER.** `-addSubview:` already handles the previous parent, the window link
 * and the two move notices; this door then moves the retained child to the index the mode and the relative view name.
 * A relative view that is not this view's child means the same as nil, and nil means "the top" for Above and "the
 * bottom" for Below — Apple's reading of an unanchored placement. */
- (void)addSubview:(NSView *)aView positioned:(NSWindowOrderingMode)place relativeTo:(NSView *)otherView
{
	NSUInteger index;

	if (aView == nil || aView == self || aView == otherView) {
		return;
	}
	[self addSubview:aView];
	if (_subviews == nil) {
		return;
	}
	if (otherView != nil && [otherView superview] != self) {
		otherView = nil;
	}
	[aView retain];
	[_subviews removeObjectIdenticalTo:aView];
	if (otherView == nil) {
		index = (place == NSWindowBelow) ? 0 : [_subviews count];
	} else {
		index = [_subviews indexOfObjectIdenticalTo:otherView];
		if (place != NSWindowBelow) {
			index++;
		}
	}
	[_subviews insertObject:aView atIndex:index];
	[aView release];
	[self setNeedsDisplay:YES];
}

/* **REPLACING THE LIST IS A REMOVAL AND AN ADD PER VIEW.** The copy is taken because each removal edits the array the
 * loop would otherwise be walking, and the arrivals go through `-addSubview:` so the window link and the two move
 * notices are the same ones a single add performs. */
- (void)setSubviews:(NSArray *)newSubviews
{
	NSArray *old = [[self subviews] copy];
	NSUInteger i;

	for (i = 0; i < [old count]; i++) {
		[[old objectAtIndex:i] removeFromSuperview];
	}
	[old release];
	for (i = 0; i < [newSubviews count]; i++) {
		[self addSubview:[newSubviews objectAtIndex:i]];
	}
	[self setNeedsDisplay:YES];
}

- (void)removeFromSuperview
{
	NSView *parent = _superview;

	if (parent == nil) {
		return;
	}
	[self viewWillMoveToSuperview:nil];
	[self cg_setWindow:nil];
	/* HELD ACROSS THE REMOVAL, because REMOVING A VIEW MAY DEALLOCATE IT — Apple documents exactly that, and
	 * a view with no other owner dies here. The hold is what lets the SECOND of the two move calls happen at
	 * all: `-viewDidMoveToSuperview` is called after the view is out, which is the whole difference between it
	 * and `-viewWillMoveToSuperview:`. (`-cg_setWindow:nil` above does NOT make the window calls for a view
	 * whose window was already nil — they are called when the window CHANGES, which is Apple's rule.) */
	[self retain];
	_superview = nil;
	[parent->_subviews removeObjectIdenticalTo:self];
	[self viewDidMoveToSuperview];
	/* THE PARENT'S EQUATIONS MAY HAVE NAMED THIS VIEW, and they are now unsolvable rather than solved differently:
	 * the constraint is still active, so the next pass will refuse it by name (its item is out of the subtree). A
	 * request here keeps the remaining views consistent immediately, which is what a caller removing a pane wants. */
	[parent cg_requestLayout];
	[self release];
}

- (BOOL)isDescendantOf:(NSView *)aView
{
	NSView *v = _superview;

	while (v != nil) {
		if (v == aView) {
			return YES;
		}
		v = [v superview];
	}
	return NO;
}

/* **A VIEW'S SUCCESSOR IS ITS SUPERVIEW.** `NSApplication.h` names this chain — "`NSView` → its superview →
 * … → the window → the application" — and NOTHING EVER WIRED IT: `-addSubview:` set `_superview` and left
 * this to NSResponder's ivar, which is nil unless somebody sets it. The consequence was not subtle, because
 * EVERY event method NSResponder implements is one line that FORWARDS to `-nextResponder`: a view whose
 * successor was nil SWALLOWED the event it did not itself override, and the chain stopped there. That is why
 * `-makeFirstResponder:` in NSWindow.m carried a workaround linking the first responder straight to the
 * content view, skipping every ancestor between them.
 *
 * AN EXPLICIT LINK STILL WINS, which is Apple's behaviour as well: `-setNextResponder:` on a view overrides
 * the computed answer, so this asks for one before falling back. */
- (NSResponder *)nextResponder
{
	NSResponder *explicit = [super nextResponder];

	if (explicit != nil) {
		return explicit;
	}
	if (_superview != nil) {
		return _superview;
	}
	return (NSResponder *)_window;
}

- (NSView *)hitTest:(NSPoint)point
{
	NSPoint here;
	NSUInteger i;

	if (_hidden) {
		return nil;
	}
	/* THE POINT ARRIVES IN THE SUPERVIEW'S COORDINATES — EXCEPT AT THE ROOT, where there is no superview
	 * and the point is already in this view's own space. That is the same stand-in the conversions use for
	 * a NULL view, and getting it the other way round is a root view that answers NO everywhere. */
	if (_superview != nil && !NSPointInRect(point, _frame)) {
		return nil;
	}
	here = (_superview != nil) ? fn_from_super(point, self) : point;
	if (_subviews != nil) {
		/* TOPMOST FIRST: the array is back-to-front, so a hit is the LAST one that contains the point. */
		for (i = [_subviews count]; i > 0; i--) {
			NSView *hit = [[_subviews objectAtIndex:i - 1] hitTest:here];

			if (hit != nil) {
				return hit;
			}
		}
	}
	return NSPointInRect(here, _bounds) ? self : nil;
}

- (NSPoint)convertPoint:(NSPoint)point toView:(NSView *)view
{
	NSView *target = view != nil ? view : fn_root(self);
	NSPoint p = fn_up_to_root(point, self);

	/* BOTH VIEWS ARE ASSUMED TO SHARE A ROOT. Two views in different trees have no common frame of
	 * reference, and Apple leaves that case undefined; this one converts through each root's own space,
	 * which is arithmetic rather than a raise. */
	return fn_down_from_root(target, p);
}

- (NSPoint)convertPoint:(NSPoint)point fromView:(NSView *)view
{
	NSView *src = view != nil ? view : fn_root(self);
	NSPoint p = fn_up_to_root(point, src);

	return fn_down_from_root(self, p);
}

- (NSRect)convertRect:(NSRect)rect fromView:(NSView *)view
{
	/* THE TWO CORNERS ARE CONVERTED AND THE RECT REBUILT, because a flip can put the origin at what was
	 * the far corner — which is why the result is standardised rather than assembled in order. */
	NSPoint a = [self convertPoint:rect.origin fromView:view];
	NSPoint b = [self convertPoint:NSMakePoint(rect.origin.x + rect.size.width,
						  rect.origin.y + rect.size.height) fromView:view];

	return NSMakeRect(a.x < b.x ? a.x : b.x, a.y < b.y ? a.y : b.y, a.x < b.x ? b.x - a.x : a.x - b.x,
			  a.y < b.y ? b.y - a.y : a.y - b.y);
}

- (NSRect)convertRect:(NSRect)rect toView:(NSView *)view
{
	NSPoint a = [self convertPoint:rect.origin toView:view];
	NSPoint b = [self convertPoint:NSMakePoint(rect.origin.x + rect.size.width,
						  rect.origin.y + rect.size.height) toView:view];

	return NSMakeRect(a.x < b.x ? a.x : b.x, a.y < b.y ? a.y : b.y, a.x < b.x ? b.x - a.x : a.x - b.x,
			  a.y < b.y ? b.y - a.y : a.y - b.y);
}

- (NSRect)visibleRect
{
	NSRect r = _bounds;
	NSView *v = _superview;

	/* EVERY ANCESTOR'S BOUNDS, BROUGHT INTO THIS VIEW'S COORDINATES AND INTERSECTED IN. The conversion is
	 * the same one the rest of the class uses, which is the point: a second implementation of the flip
	 * here is how the two would come to disagree. */
	while (v != nil) {
		r = fn_intersect(r, [v convertRect:[v bounds] toView:self]);
		v = [v superview];
	}
	return r;
}

/* ------------------------------------------------------------------------- */
/* the offscreen render                                                      */
/* ------------------------------------------------------------------------- */

/* ONE VIEW, IN ITS PARENT'S COORDINATE SYSTEM, WITH ITS SUBVIEWS.
 *
 * THE FLIP RULE HERE IS THE SAME ONE `fn_to_super` USES, AND FOR THE SAME REASON: the frame places the
 * view in its parent's y direction, the view's own coordinates run in ITS direction, and the two are the
 * same rectangle read from opposite ends exactly when the directions DIFFER. So a view whose direction
 * differs from its parent's is entered by MIRRORING about its frame — and the ORDER of the two calls is
 * load-bearing, measured in NSImage's canvas: SCALE FIRST, THEN TRANSLATE, because a translate applied
 * after a scale is not itself mirrored.
 *
 * A NON-ZERO BOUNDS ORIGIN IS APPLIED, NOT REFUSED. It used to be the one thing this draw would not
 * model — a scroll offset, refused by name — and that is exactly what a clip view moves: because the
 * refusal covered the WHOLE view, a scrolled clip view drew NEITHER itself nor its document, so the
 * scroll view's arithmetic had no picture at all. The offset is one translate, further down. */
static void fn_draw_view(NSView *v, CGContextRef cg, NSRect dirty)
{
	NSRect f = [v frame];
	NSRect b = [v bounds];
	NSView *parent = [v superview];
	BOOL same = (parent == nil) ? NO : ([v isFlipped] == [parent isFlipped]);
	NSArray *subs;
	NSUInteger i;

	CGContextSaveGState(cg);
	/* ENTER THE VIEW'S RECTANGLE IN THE PARENT'S SYSTEM, then its own.
	 *
	 * TRANSLATE BEFORE SCALE IN THE MIRRORING BRANCHES, and the order is what the calls MEAN: both
	 * change the CTM in the CURRENT USER space (Apple: `CGContextConcatCTM(c, CGAffineTransformMake…)`,
	 * `CTMnew = transform * CTMcontext`). Entering a y-up view means moving the origin to the frame's
	 * BOTTOM-left and then flipping about that new origin; the other order flips first and moves the
	 * origin in the flipped space, which lands the view somewhere else entirely. §46 in the CoreGraphics
	 * plan fixed the CTM doors themselves — these two pairs were written against the old composition and
	 * are corrected with it. */
	if (parent == nil) {
		/* THE ROOT DRAWS IN THE DESTINATION'S OWN SYSTEM, which the canvas gives as y-down — so a root
		 * that is NOT flipped has to be mirrored about its whole frame. */
		if (![v isFlipped]) {
			CGContextTranslateCTM(cg, 0.0, f.origin.y + f.size.height);
			CGContextScaleCTM(cg, 1.0, -1.0);
		}
	} else if (!same) {
		CGContextTranslateCTM(cg, f.origin.x, f.origin.y + f.size.height);
		CGContextScaleCTM(cg, 1.0, -1.0);
	} else {
		CGContextTranslateCTM(cg, f.origin.x, f.origin.y);
	}
	/* **AND THE VIEW'S OWN BOUNDS ORIGIN, WHICH IS WHERE A SCROLL LIVES.** The translate above put the frame's
	 * origin at (0, 0); the bounds origin is the point of the view's own coordinates that belongs THERE, so the
	 * view's coordinates are shifted back by it — after which `b` is the view's rectangle in its own coordinates
	 * and the clip below is the frame region, as it should be. */
	CGContextTranslateCTM(cg, -b.origin.x, -b.origin.y);
	/* THE VIEW'S OWN CLIP, so a subclass cannot draw outside itself. */
	CGContextClipToRect(cg, b);
	[v drawRect:dirty];
	subs = [v subviews];
	for (i = 0; i < [subs count]; i++) {
		fn_draw_view([subs objectAtIndex:i], cg, dirty);
	}
	CGContextRestoreGState(cg);
}

- (void)cacheDisplayInRect:(NSRect)rect toBitmapImageRep:(NSBitmapImageRep *)bitmapImageRep
{
	NSImage *canvas;
	NSArray *reps;
	NSBitmapImageRep *src;
	const unsigned char *sp;
	unsigned char *dp;
	NSInteger rows;
	NSInteger cols;
	NSInteger row;
	size_t sstride;
	size_t dstride;

	if (bitmapImageRep == nil || rect.size.width <= 0.0 || rect.size.height <= 0.0) {
		fprintf(stderr, "APPKIT-REFUSE: -cacheDisplayInRect: needs a bitmap rep and a non-empty "
				"rect\n");
		return;
	}
	dp = [bitmapImageRep bitmapData];
	if (dp == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -cacheDisplayInRect: needs a rep with WRITABLE bytes; this "
				"one is CGIMAGE-BACKED (what +imageRepWithData: produces) and caching into it "
				"would need a second copy of the pixels\n");
		return;
	}
	/* THE CANVAS IS THE REP'S PIXEL SIZE, and `flipped:YES` because that is the destination's own
	 * orientation: y grows down from the top, which is what a bitmap's rows mean. */
	canvas = [NSImage imageWithSize:NSMakeSize((CGFloat)[bitmapImageRep pixelsWide],
						   (CGFloat)[bitmapImageRep pixelsHigh])
				flipped:YES
			 drawingHandler:^BOOL(NSRect dst) {
		CGContextRef c = [[NSGraphicsContext currentContext] CGContext];

		if (c != NULL) {
			[NSGraphicsContext saveGraphicsState];
			fn_draw_view(self, c, rect);
			[NSGraphicsContext restoreGraphicsState];
		}
		(void)dst;
		return YES;
	}];
	if (canvas == nil) {
		return;
	}
	reps = [canvas representations];
	src = ([reps count] > 0) ? [reps objectAtIndex:0] : nil;
	sp = (src != nil) ? [src bitmapData] : NULL;
	if (sp == NULL) {
		return;
	}
	/* ROW BY ROW, BECAUSE THE TWO STRIDES NEED NOT MATCH — and both buffers are R, G, B, A
	 * premultiplied, so the move is a copy rather than a conversion. */
	rows = [bitmapImageRep pixelsHigh];
	cols = [bitmapImageRep pixelsWide];
	if (rows > [src pixelsHigh]) {
		rows = [src pixelsHigh];
	}
	if (cols > [src pixelsWide]) {
		cols = [src pixelsWide];
	}
	sstride = (size_t)[src bytesPerRow];
	dstride = (size_t)[bitmapImageRep bytesPerRow];
	for (row = 0; row < rows; row++) {
		memcpy(dp + (size_t)row * dstride, sp + (size_t)row * sstride, (size_t)cols * 4u);
	}
}

- (void)drawRect:(NSRect)dirtyRect
{
	/* A PLAIN VIEW DRAWS NOTHING, which is also what Apple's does. This exists to be OVERRIDDEN, and the
	 * slice that CALLS it is the next one: it needs a context to pass, and that decision is the substrate
	 * this slice deliberately left open. */
	(void)dirtyRect;
}


/* ============================================================================================ *
 * THE VIEW TREE'S OWN DISPLAY DOORS.                                                             *
 * ============================================================================================ */

/* THE NOTIFICATION NAMES AND THE ONE WINDOW LEVEL. The names' values are their own identifiers, the rule this
 * tier follows; the LEVEL's value is OURS (Apple publishes the symbol and no number, and a level is a
 * floating-point band rather than one of the fixed `NSWindowLevel`s, so there is nothing to transcribe). */
NSString *NSViewFrameDidChangeNotification = @"NSViewFrameDidChangeNotification";
NSString *NSViewBoundsDidChangeNotification = @"NSViewBoundsDidChangeNotification";
NSString *NSViewGlobalFrameDidChangeNotification = @"NSViewGlobalFrameDidChangeNotification";
const CGFloat NSFullScreenModeWindowLevel = 100.0;

/* ---- THE DIRTY REGION ---------------------------------------------------------------------- */

- (void)setNeedsDisplayInRect:(NSRect)invalidRect
{
	_needsDisplay = YES;
	if (!_hasDirtyRect) {
		_dirtyRect = invalidRect;
		_hasDirtyRect = YES;
		_dirtyRects[0] = invalidRect;
		_dirtyCount = 1;
	} else {
		/* **THE BOX IS THE UNION AND THE REGION KEEPS THE PARTS.** Apple's `-dirtyRect` is one rectangle and stays
		 * one here, because every caller that asks "is any of this dirty" wants the box; but the DISPLAY pass paints
		 * what the region names rather than the box, or a scroll's strip and a scroller's knob would be painted as the
		 * whole area between them. See `-cg_addToDirtyRegion:` for what happens when the list fills. */
		_dirtyRect = NSUnionRect(_dirtyRect, invalidRect);
		[self cg_addToDirtyRegion:invalidRect];
	}
	/* AND THE WINDOW IS TOLD HERE TOO, for the same reason `-setNeedsDisplay:` does it: a cell that invalidates a
	 * STRIP — which is every cell, because `-highlight:withFrame:inView:` names the one rect it repainted — is
	 * still a reason for the window to paint, and a half-fixed pair would leave button highlights invisible
	 * while slider knobs moved. */
	[[self window] setViewsNeedDisplay:YES];
}

- (BOOL)needsDisplayInRect:(NSRect)rect
{
	if (!_needsDisplay) {
		return NO;
	}
	if (!_hasDirtyRect) {
		return YES;
	}
	return NSIntersectsRect(_dirtyRect, rect);
}

/* **THE UNION OF EVERY INVALIDATED PART BELOW THIS VIEW, IN THIS VIEW'S COORDINATES.** A window that wants to draw
 * only what changed cannot ask one view's dirty rect: the request may sit on a descendant. This walks the (now
 * small, because offscreen browser columns are detached) tree once and converts each dirty child rectangle up. */
- (NSRect)cg_dirtyUnion
{
	NSRect unionRect = NSZeroRect;
	BOOL any = NO;
	NSUInteger i;

	if (_hasDirtyRect) {
		unionRect = _dirtyRect;
		any = YES;
	}
	for (i = 0; i < [_subviews count]; i++) {
		NSView *child = [_subviews objectAtIndex:i];
		NSRect childRect = [child cg_dirtyUnion];

		if (!NSIsEmptyRect(childRect)) {
			NSRect inSelf = [self convertRect:childRect fromView:child];

			unionRect = any ? NSUnionRect(unionRect, inSelf) : inSelf;
			any = YES;
		}
	}
	return any ? unionRect : NSZeroRect;
}

- (void)cg_clearDirtyRegionRecursive
{
	NSUInteger i;

	[self cg_clearDirtyRegion];
	for (i = 0; i < [_subviews count]; i++) {
		[[_subviews objectAtIndex:i] cg_clearDirtyRegionRecursive];
	}
}

- (void)cg_clearDirtyRegion
{
	_hasDirtyRect = NO;
	_dirtyCount = 0;
	_needsDisplay = NO;
	{
		NSUInteger i;

		for (i = 0; i < [_subviews count]; i++) {
			[[_subviews objectAtIndex:i] cg_clearDirtyRegion];
		}
	}
}

/* **AND THE NARROWING, WHICH IS WHAT MAKES A SCROLL CHEAP.** A view that invalidates all of itself and then discovers
 * that only a strip really changed has one legitimate way to say so; replacing the record rather than intersecting it
 * is the difference between "the whole bounds" and "the strip". `NSClipView` is the caller — its bounds-origin door
 * has to mark everything first, because a plain `NSView` scroll has nothing to copy from, and only then can it ask the
 * window to move the pixels and keep the strip. */
- (void)cg_setDirtyRect:(NSRect)rect
{
	_needsDisplay = YES;
	if (NSIsEmptyRect(rect)) {
		_hasDirtyRect = NO;
		return;
	}
	_dirtyRect = rect;
	_hasDirtyRect = YES;
	_dirtyRects[0] = rect;
	_dirtyCount = 1;
	[[self window] setViewsNeedDisplay:YES];
}

/* **ONE MORE PIECE OF DAMAGE, MERGED WHEN IT TOUCHES WHAT IS ALREADY THERE.** A rectangle that overlaps one already on the
 * list is unioned into it, which is what keeps a dragged cell's series of strips from filling the budget; a rectangle that
 * overlaps nothing is kept beside the others, which is what keeps a scroll's strip from absorbing a scroller's knob. When
 * the list is full every entry collapses into the bounding box — the answer this class gave before the region existed, and
 * a superset of the truth by construction. */
- (void)cg_addToDirtyRegion:(NSRect)rect
{
	NSUInteger i;

	if (NSIsEmptyRect(rect)) {
		return;
	}
	for (i = 0; i < _dirtyCount; i++) {
		if (NSIntersectsRect(_dirtyRects[i], rect)) {
			_dirtyRects[i] = NSUnionRect(_dirtyRects[i], rect);
			return;
		}
	}
	if (_dirtyCount < APPKIT_DAMAGE_RECTS) {
		_dirtyRects[_dirtyCount] = rect;
		_dirtyCount++;
		return;
	}
	for (i = 1; i < _dirtyCount; i++) {
		_dirtyRects[0] = NSUnionRect(_dirtyRects[0], _dirtyRects[i]);
	}
	_dirtyRects[0] = NSUnionRect(_dirtyRects[0], rect);
	_dirtyCount = 1;
}

/* **AND THE TREE'S DAMAGE, IN THE RECEIVER'S COORDINATES, AS A LIST.** The window asks its content view for this and
 * paints each rectangle; a child's pieces are converted on the way up, so the answer is in the space `-displayRect:` and
 * the paint both speak. `max` is the caller's budget: when the collected list would exceed it, everything collapses to the
 * box of what has been gathered, which is the one degenerate answer that is still correct. */
- (void)cg_dirtyRegionRecursive:(NSRect *)out max:(NSUInteger)max count:(NSUInteger *)outCount
{
	NSUInteger i;

	for (i = 0; i < _dirtyCount; i++) {
		[self cg_regionAdd:_dirtyRects[i] to:out max:max count:outCount];
	}
	for (i = 0; i < [_subviews count]; i++) {
		NSView *child = [_subviews objectAtIndex:i];
		NSRect pieces[APPKIT_DAMAGE_RECTS];
		NSUInteger pieceCount = 0;
		NSUInteger j;

		[child cg_dirtyRegionRecursive:pieces max:APPKIT_DAMAGE_RECTS count:&pieceCount];
		for (j = 0; j < pieceCount; j++) {
			[self cg_regionAdd:[self convertRect:pieces[j] fromView:child] to:out max:max count:outCount];
		}
	}
}

/* THE ONE PLACE A RECTANGLE IS ADDED TO A REGION ARRAY, so the tree's collection and this class's own bookkeeping cannot
 * disagree about merging or about what happens when the budget runs out. */
- (void)cg_regionAdd:(NSRect)rect to:(NSRect *)out max:(NSUInteger)max count:(NSUInteger *)count
{
	NSUInteger i;

	if (NSIsEmptyRect(rect)) {
		return;
	}
	for (i = 0; i < *count; i++) {
		if (NSIntersectsRect(out[i], rect)) {
			out[i] = NSUnionRect(out[i], rect);
			return;
		}
	}
	if (*count < max) {
		out[*count] = rect;
		(*count)++;
		return;
	}
	for (i = 1; i < *count; i++) {
		out[0] = NSUnionRect(out[0], out[i]);
	}
	out[0] = NSUnionRect(out[0], rect);
	*count = 1;
}

/* ---- DRAWING A TREE ------------------------------------------------------------------------ */

/* THE RECURSION, AND THE RECT IS IN THE RECEIVER'S COORDINATES — the child's is CONVERTED rather than
 * subtracted, so a superview with an offset bounds or a flipped child still lands in the right place. */
/* **THE FORCED DOORS.** `-display` paints the whole view and its tree NOW, whether or not anything was invalidated,
 * and then clears the damage it just repaired. `-displayIfNeeded` paints only what was invalidated. Both are the existing
 * `…InRect:` doors with the receiver's bounds supplied, which is the whole difference. */
- (void)display
{
	[self displayRect:_bounds];
	[self cg_clearDirtyRegion];
}

- (void)displayIfNeeded
{
	[self displayIfNeededInRect:_bounds];
}

- (void)displayRect:(NSRect)rect
{
	NSUInteger i;
	CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];

	if (_hidden) {
		return;
	}
	/* **THE VIEW'S OWN BOUNDS ORIGIN, WHICH IS WHERE A SCROLL LIVES.** The parent has already put this view's
	 * frame origin at user (0, 0); `_bounds`.origin is the point of THIS view's coordinates that belongs there,
	 * so the coordinates are shifted back by it before anything is drawn — the view's own `-drawRect:` and every
	 * child frame below are both written in that shifted space. This is the one line that makes a scrolled clip
	 * view move on the glass, and it was missing: the arithmetic scrolled and the tree drew where it always had. */
	if (cg != NULL) {
		CGContextSaveGState(cg);
		CGContextTranslateCTM(cg, -_bounds.origin.x, -_bounds.origin.y);
		/* **AND THE RECTANGLE IS A CLIP, NOT ADVICE.** Every view below still draws — the tree is walked whole —
		 * so a partial display was only ever partial in which ROWS were copied: each `-drawRect:` painted its
		 * entire bounds and the rasterizer threw away everything outside the region. MEASURED, that is why a click
		 * in a file window still cost 20-45 ms after the window began drawing "only what changed": the icon view
		 * drew every folder and every name for a selection that moved two cells. The clip is what makes the walk
		 * cheap, and it is the SAME rectangle the caller asked for, converted into this view's coordinates by the
		 * parent's `-convertRect:toView:` and by the bounds translate above. */
		CGContextClipToRect(cg, rect);
	}
	if (NSIntersectsRect(rect, _bounds)) {
		[self drawRect:rect];
	}
	for (i = 0; i < [_subviews count]; i++) {
		NSView *c = [_subviews objectAtIndex:i];
		NSRect cf = [c frame];

		/* **A CHILD IS DRAWN IN ITS OWN COORDINATES, WHICH IS A TRANSLATION AND NOT AN ARGUMENT.** This loop used
		 * to call the child's `-displayRect:` and nothing else, so EVERY SUBVIEW DREW AT ITS SUPERVIEW'S ORIGIN —
		 * `-convertRect:toView:` converts the RECT, and the child's `-drawRect:` draws about ITS OWN origin, so
		 * without moving the CTM the two disagree by exactly the child's frame. It went unnoticed while the only
		 * view a window drew was its content view; the first CONTROL — a subview by definition — stacked under
		 * every other control at the corner, and the live probe is what showed it (five buttons, one place).
		 * THE MIRRORING BRANCH IS `fn_draw_view`'s, in `fn_draw_view`'s ORDER — translate to the frame's TOP edge,
		 * then scale — because a child that flips relative to its parent has to be entered that way round. */
		if (cg != NULL) {
			CGContextSaveGState(cg);
			if ([c isFlipped] != [self isFlipped]) {
				CGContextTranslateCTM(cg, cf.origin.x, cf.origin.y + cf.size.height);
				CGContextScaleCTM(cg, 1.0, -1.0);
			} else {
				CGContextTranslateCTM(cg, cf.origin.x, cf.origin.y);
			}
			/* **AND THE CHILD'S OWN CLIP, IN THE CHILD'S OWN COORDINATES.** `fn_draw_view` has always clipped a
			 * view to its bounds — "so a subclass cannot draw outside itself" — and THIS path did not, and this is
			 * the one a live window draws through. MEASURED: a text view whose string was wider than its frame drew
			 * the overflow straight across its neighbours, because nothing between `-drawRect:` and the surface
			 * said stop. IT BELONGS IN BOTH PATHS because they draw the same tree: a rule that holds in one of them
			 * is a rule a caller cannot rely on, and the two would drift the moment either was touched.
			 *
			 * AND IT IS THE CHILD'S FRAME REGION AND NOT ITS BOUNDS RECT, because the child's OWN bounds origin is
			 * applied inside its own `-displayRect:` a moment from now. Clipping to `[c bounds]` was correct only
			 * while that origin was zero; for a scrolled child it would clip a region the child is not drawn in. */
			CGContextClipToRect(cg, NSMakeRect(0.0, 0.0, cf.size.width, cf.size.height));
		}
		[c displayRect:[self convertRect:rect toView:c]];
		if (cg != NULL) {
			CGContextRestoreGState(cg);
		}
	}
	if (cg != NULL) {
		CGContextRestoreGState(cg);
	}
}

- (void)displayRectIgnoringOpacity:(NSRect)rect
{
	/* THE ONE-ARGUMENT FORM DRAWS IN WHATEVER CONTEXT THE CALLER ALREADY SET — the same drawing as the context
	 * form with a nil context, and the same one `-displayRect:` makes. */
	[self displayRectIgnoringOpacity:rect inContext:nil];
}

- (void)displayRectIgnoringOpacity:(NSRect)rect inContext:(NSGraphicsContext *)context
{
	/* THE `IgnoringOpacity` FORMS DIFFER ONLY IN THAT NO OPACITY LAYER IS ASKED FOR, and this tree asks for
	 * none anywhere — so this is the same drawing under the name a caller used, which is stated rather than
	 * hidden behind a second implementation that would drift from the first. */
	NSGraphicsContext *prev = [[NSGraphicsContext currentContext] retain];

	if (context != nil) {
		[NSGraphicsContext setCurrentContext:context];
	}
	[self displayRect:rect];
	if (context != nil) {
		[NSGraphicsContext setCurrentContext:prev];
	}
	[prev release];
}

- (void)displayIfNeededInRect:(NSRect)rect
{
	if ([self needsDisplayInRect:rect]) {
		/* THE REGION, INTERSECTED WITH WHAT THE CALLER ASKED FOR, which is the whole point of keeping a rect:
		 * a view that invalidated a strip redraws the strip rather than the view. */
		[self displayRect:_hasDirtyRect ? NSIntersectionRect(_dirtyRect, rect) : rect];
		[self cg_clearDirtyRegion];
	}
}

- (void)displayIfNeededInRectIgnoringOpacity:(NSRect)rect
{
	[self displayIfNeededInRect:rect];
}

- (void)displayIfNeededIgnoringOpacity
{
	[self displayIfNeededInRect:_bounds];
}

/* ---- THE GEOMETRY, PIECE BY PIECE ---------------------------------------------------------- */

- (void)setFrameSize:(NSSize)newSize
{
	NSRect previousFrame = _frame;

	NSSize old = _frame.size;

	_frame.size = newSize;
	/* **AND THE BOUNDS MOVE WITH IT, WHICH IS THE HALF OF THE RULE THIS DOOR WAS MISSING.** `-setFrame:` states it
	 * where it does the same work — "THE SIZE IS SHARED AND THE ORIGINS ARE NOT" — and this door changed the FRAME
	 * alone, leaving `_bounds` at whatever size the view was born with. NOTHING NOTICES UNTIL SOMETHING ASKS THE
	 * VIEW HOW BIG IT IS: `-visibleRect` intersects the BOUNDS with its ancestors', and the display walk goes
	 * through that, so a view resized this way is 0x0 as far as drawing is concerned. MEASURED: `[popup
	 * sizeToFit]`, which is this door through `NSControl -sizeToFit`, left a control reporting frame 118x23 and
	 * BOUNDS 0x0 — visibleRect 0x0, never drawn — while an identical control given the same frame in
	 * `-initWithFrame:` drew normally. */
	_bounds.size = newSize;
	[self setNeedsDisplay:YES];
	/* A FRAME CHANGE IS THE ONLY THING THAT REARRANGES SUBVIEWS, which is why the hook is called here and
	 * nowhere else. */
	[self resizeSubviewsWithOldSize:old];

	[self cg_frameDidChangeFrom:previousFrame];
	/* **AND THE EQUATIONS ARE RE-SOLVED, BECAUSE A SIZE CHANGE IS THE MOST COMMON THING THEY EXIST FOR.** A pass is
	 * requested from the topmost view and is a no-op with no active constraint; inside a pass the request returns
	 * immediately, which is what keeps the engine's own frame writes from recursing. */
	_needsLayout = YES;
	[self cg_requestLayout];
}

- (void)setBoundsOrigin:(NSPoint)newOrigin
{
	_bounds.origin = newOrigin;
	[self setNeedsDisplay:YES];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSViewBoundsDidChangeNotification object:self];
}

- (void)setBoundsSize:(NSSize)newSize
{
	_bounds.size = newSize;
	[self setNeedsDisplay:YES];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSViewBoundsDidChangeNotification object:self];
}

/* A SIZE DOES NOT TRANSLATE, ONLY AN ORIGIN DOES — so unless a scale is in play, the answer is the input.
 * That is stated rather than done quietly, because a caller's layout would look wrong rather than obviously
 * unimplemented if this returned something invented. This tree's views have no scale. */
- (NSSize)convertSize:(NSSize)aSize toView:(NSView *)view
{
	(void)view;
	return aSize;
}

- (NSSize)convertSize:(NSSize)aSize fromView:(NSView *)view
{
	(void)view;
	return aSize;
}

/* THE BASE FAMILY FORWARDS, so the six deprecated names cannot drift from the door they rename: a base
 * coordinate IS the window's, which is `toView:nil`. */
- (NSPoint)convertPointToBase:(NSPoint)aPoint
{
	return [self convertPoint:aPoint toView:nil];
}

- (NSPoint)convertPointFromBase:(NSPoint)aPoint
{
	return [self convertPoint:aPoint fromView:nil];
}

- (NSRect)convertRectToBase:(NSRect)aRect
{
	return [self convertRect:aRect toView:nil];
}

- (NSRect)convertRectFromBase:(NSRect)aRect
{
	return [self convertRect:aRect fromView:nil];
}

- (NSSize)convertSizeToBase:(NSSize)aSize
{
	return [self convertSize:aSize toView:nil];
}

- (NSSize)convertSizeFromBase:(NSSize)aSize
{
	return [self convertSize:aSize fromView:nil];
}

/* ---- THE MOVE NOTIFICATIONS, AND THE WINDOW THEY REPORT ------------------------------------- */

- (NSWindow *)window
{
	return _window;
}

/* SETTING THE WINDOW WALKS THE TREE, because a view that arrives in a window brings its subviews with it and
 * every one of them needs the same two calls. */
- (void)cg_setWindow:(NSWindow *)aWindow
{
	NSUInteger i;

	if (_window == aWindow) {
		return;
	}
	[self viewWillMoveToWindow:aWindow];
	_window = aWindow;
	for (i = 0; i < [_subviews count]; i++) {
		[[_subviews objectAtIndex:i] cg_setWindow:aWindow];
	}
	[self viewDidMoveToWindow];
	[self setNeedsDisplay:YES];
}

- (void)viewWillMoveToSuperview:(NSView *)newSuperview
{
	(void)newSuperview;
}

- (void)viewDidMoveToSuperview
{
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
	(void)newWindow;
}

- (void)viewDidMoveToWindow
{
}

/* ---- THE ARRANGEMENT DOORS ------------------------------------------------------------------ */

/* THE HOOK A LAYOUT OVERRIDES, and its default is Apple's: every subview is told the superview's old size, so
 * a subclass's override has somewhere to run. THE AUTORESIZING MASKS ARE NOT INTERPRETED HERE: frame-based layout
 * in this tier is still frames and an override, and a mask reaches the geometry through AUTO LAYOUT, where the
 * engine translates it for the views that participate in constraints. A view that uses neither keeps the frame it
 * was given, which is what `-resizeWithOldSuperviewSize:`'s default does. */
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	NSUInteger i;

	for (i = 0; i < [_subviews count]; i++) {
		[[_subviews objectAtIndex:i] resizeWithOldSuperviewSize:oldSize];
	}
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
	(void)oldSize;
}

/* ============================================================================================ *
 * AUTO LAYOUT — THE STATE, THE ANCHORS, AND THE PASS.                                           *
 *                                                                                                *
 * The equations live in `NSLayoutConstraint.m`, the arithmetic in `NSLayoutSolver.m`, and this    *
 * section is the view's half: the array it owns, the flags a pass reads, the intrinsic-size      *
 * priorities, and the anchors. `-layoutSubtreeIfNeeded` is the driver; every automatic call      *
 * (a frame size, a constraint added or removed, a subview arriving) funnels into the same        *
 * `-cg_requestLayout`, which solves from the TOPMOST view so an equation is never half-solved.   *
 * ============================================================================================ */

/* **THE PASS GUARD IS WHAT MAKES A SOLVE RE-ENTRANT-SAFE.** The engine writes frames with `-setFrame:`, and a
 * `-layout` override may too; either would otherwise ask for another pass while this one is mid-flight, with the
 * first pass's answers half written. The solver's flag is process-wide because a pass is, and the request below is
 * the one place that decides when a pass is due. */
- (void)cg_runLayoutPass
{
	if (AGLayoutIsInPass()) {
		return;
	}
	AGLayoutEnterPass();
	[self updateConstraintsIfNeeded];
	AGLayoutSolveSubtree(self);
	[self cg_callLayoutHooks];
	AGLayoutLeavePass();
}

- (void)cg_callLayoutHooks
{
	NSUInteger i;

	if (_needsLayout) {
		_needsLayout = NO;
		[self layout];
	}
	for (i = 0; i < [_subviews count]; i++) {
		[[_subviews objectAtIndex:i] cg_callLayoutHooks];
	}
}

- (void)cg_requestLayout
{
	NSView *root;

	if (AGLayoutIsInPass()) {
		return;
	}
	/* **NO ACTIVE CONSTRAINT ANYWHERE IS THE FAST PATH, AND IT IS THE COMMON ONE.** Every frame set in this tier asks
	 * this question; with nothing activated the answer is a single load and no tree walk, so the frame-based code
	 * that predates Auto Layout costs what it always did. */
	if ([NSLayoutConstraint cg_activeConstraintCount] == 0) {
		return;
	}
	root = self;
	while ([root superview] != nil) {
		root = [root superview];
	}
	/* **AND THE SUBTREE HAS TO HAVE ONE TOO.** The count is process-wide; a window whose own tree holds no
	 * equation should not run an update pass just because another window has one. The check walks this root only,
	 * and only after the count said there is something active somewhere. */
	if (!AGLayoutSubtreeHasConstraints(root)) {
		return;
	}
	[root cg_runLayoutPass];
}

- (BOOL)cg_getCapturedAutoresizingFrame:(NSRect *)frame parentSize:(NSSize *)parentSize
{
	if (!_cg_autoresizingCaptured) {
		return NO;
	}
	if (frame != NULL) {
		*frame = _cg_autoresizingFrame;
	}
	if (parentSize != NULL) {
		*parentSize = _cg_autoresizingParentSize;
	}
	return YES;
}

- (void)cg_setCapturedAutoresizingFrame:(NSRect)frame parentSize:(NSSize)parentSize
{
	_cg_autoresizingCaptured = YES;
	_cg_autoresizingFrame = frame;
	_cg_autoresizingParentSize = parentSize;
}

- (void)cg_clearCapturedAutoresizingFrame
{
	_cg_autoresizingCaptured = NO;
}

- (BOOL)needsLayout
{
	return _needsLayout;
}

- (void)setNeedsLayout:(BOOL)flag
{
	_needsLayout = flag ? YES : NO;
}

- (void)layoutSubtreeIfNeeded
{
	[self cg_runLayoutPass];
}

- (BOOL)needsUpdateConstraints
{
	return _needsUpdateConstraints;
}

- (void)setNeedsUpdateConstraints:(BOOL)flag
{
	_needsUpdateConstraints = flag ? YES : NO;
}

- (void)updateConstraints
{
	/* A PLAIN VIEW HAS NOTHING TO UPDATE, which is Apple's default and the reason this is an override point rather
	 * than a place the class invents constraints. A subclass that adds equations from its content calls
	 * `-setNeedsUpdateConstraints:YES` when that content changes. */
}

- (void)updateConstraintsIfNeeded
{
	NSUInteger i;

	if (_needsUpdateConstraints) {
		_needsUpdateConstraints = NO;
		[self updateConstraints];
	}
	for (i = 0; i < [_subviews count]; i++) {
		[[_subviews objectAtIndex:i] updateConstraintsIfNeeded];
	}
}

- (NSArray *)constraints
{
	return (_constraints != nil) ? (NSArray *)_constraints : [NSArray array];
}

- (void)addConstraint:(NSLayoutConstraint *)constraint
{
	if (constraint == nil) {
		return;
	}
	if (_constraints == nil) {
		_constraints = [[NSMutableArray alloc] init];
	}
	if ([_constraints indexOfObjectIdenticalTo:constraint] != NSNotFound) {
		return;
	}
	/* **AN ACTIVE CONSTRAINT HAS EXACTLY ONE OWNER.** Adding it to a second view would put two copies of one equation
	 * into a pass whose gather walks the tree, and removing it from one would leave the other solving a constraint
	 * the caller believes is gone. The second add is refused by name rather than silently duplicated. */
	if ([constraint isActive] && [constraint cg_owner] != self) {
		fprintf(stderr, "APPKIT-REFUSE: -[NSView addConstraint:] was handed a constraint that is already owned by "
				"another view; deactivate it there before adding it here\n");
		return;
	}
	[_constraints addObject:constraint];
	[constraint cg_setOwner:self];
	[constraint cg_setActiveFlag:YES];
	_needsLayout = YES;
	[self cg_requestLayout];
}

- (void)removeConstraint:(NSLayoutConstraint *)constraint
{
	NSUInteger index;

	if (constraint == nil || _constraints == nil) {
		return;
	}
	index = [_constraints indexOfObjectIdenticalTo:constraint];
	if (index == NSNotFound) {
		return;
	}
	/* HELD ACROSS THE REMOVAL: the array may be the only retain, and the layout request below names the view that
	 * used to own it. The constraint is released only after that pass has read the tree without it. */
	[constraint retain];
	[_constraints removeObjectAtIndex:index];
	[constraint cg_setOwner:nil];
	[constraint cg_setActiveFlag:NO];
	_needsLayout = YES;
	[self cg_requestLayout];
	[constraint release];
}

- (BOOL)translatesAutoresizingMaskIntoConstraints
{
	return _translatesAutoresizingMaskIntoConstraints;
}

- (void)setTranslatesAutoresizingMaskIntoConstraints:(BOOL)flag
{
	if ((flag ? YES : NO) == _translatesAutoresizingMaskIntoConstraints) {
		return;
	}
	_translatesAutoresizingMaskIntoConstraints = flag ? YES : NO;
	[self cg_clearCapturedAutoresizingFrame];
	_needsLayout = YES;
	[self cg_requestLayout];
}

- (NSSize)intrinsicContentSize
{
	/* NO OPINION IS THE PLAIN VIEW'S ANSWER, and it is the sentinel rather than zero: a zero-size intrinsic view is
	 * a view that wants to be nothing, which is a statement, and this view has none to make. */
	return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

- (void)invalidateIntrinsicContentSize
{
	/* THE SIZE IS COMPUTED WHEN ASKED, so there is no cached number to throw away; what invalidation means here is
	 * that the next pass must ask again, which is exactly a layout request. */
	_needsLayout = YES;
	[self cg_requestLayout];
}

- (NSLayoutPriority)contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)orientation
{
	return _contentHuggingPriority[(orientation == NSLayoutConstraintOrientationVertical) ? 1 : 0];
}

- (void)setContentHuggingPriority:(NSLayoutPriority)priority
		  forOrientation:(NSLayoutConstraintOrientation)orientation
{
	if (!(priority > 0.0f)) {
		priority = 0.0f;
	}
	if (priority > NSLayoutPriorityRequired) {
		priority = NSLayoutPriorityRequired;
	}
	_contentHuggingPriority[(orientation == NSLayoutConstraintOrientationVertical) ? 1 : 0] = priority;
	_needsLayout = YES;
	[self cg_requestLayout];
}

- (NSLayoutPriority)contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)orientation
{
	return _contentCompressionResistancePriority[(orientation == NSLayoutConstraintOrientationVertical) ? 1 : 0];
}

- (void)setContentCompressionResistancePriority:(NSLayoutPriority)priority
				forOrientation:(NSLayoutConstraintOrientation)orientation
{
	if (!(priority > 0.0f)) {
		priority = 0.0f;
	}
	if (priority > NSLayoutPriorityRequired) {
		priority = NSLayoutPriorityRequired;
	}
	_contentCompressionResistancePriority[(orientation == NSLayoutConstraintOrientationVertical) ? 1 : 0] = priority;
	_needsLayout = YES;
	[self cg_requestLayout];
}

/* **THE ANCHORS, EACH A FRESH AUTORELEASED OBJECT.** A view does not cache them: an anchor is four words of state
 * (the view and an attribute), and a cache would have to be invalidated by nothing while keeping four extra objects
 * alive per view. The anchor borrows the view, so the fresh object costs no ownership. */
- (NSLayoutXAxisAnchor *)leadingAnchor
{
	return [NSLayoutXAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeLeading];
}

- (NSLayoutXAxisAnchor *)trailingAnchor
{
	return [NSLayoutXAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeTrailing];
}

- (NSLayoutXAxisAnchor *)leftAnchor
{
	return [NSLayoutXAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeLeft];
}

- (NSLayoutXAxisAnchor *)rightAnchor
{
	return [NSLayoutXAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeRight];
}

- (NSLayoutYAxisAnchor *)topAnchor
{
	return [NSLayoutYAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeTop];
}

- (NSLayoutYAxisAnchor *)bottomAnchor
{
	return [NSLayoutYAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeBottom];
}

- (NSLayoutDimension *)widthAnchor
{
	return [NSLayoutDimension cg_anchorWithItem:self attribute:NSLayoutAttributeWidth];
}

- (NSLayoutDimension *)heightAnchor
{
	return [NSLayoutDimension cg_anchorWithItem:self attribute:NSLayoutAttributeHeight];
}

- (NSLayoutXAxisAnchor *)centerXAnchor
{
	return [NSLayoutXAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeCenterX];
}

- (NSLayoutYAxisAnchor *)centerYAnchor
{
	return [NSLayoutYAxisAnchor cg_anchorWithItem:self attribute:NSLayoutAttributeCenterY];
}

/* AN INSERTION SORT OVER THE COMPARISON FUNCTION, and it is written out rather than delegating because this
 * Foundation's `NSMutableArray` needs the same care about the function's signature — and because the order is
 * the one thing this door is for (the subview order IS the z order, and `-hitTest:` walks it in reverse). */
- (void)sortSubviewsUsingFunction:(NSInteger (*)(id, id, void *))compare context:(void *)context
{
	NSUInteger i, j, n = [_subviews count];

	if (compare == NULL || n < 2) {
		return;
	}
	for (i = 1; i < n; i++) {
		id key = [[_subviews objectAtIndex:i] retain];

		j = i;
		while (j > 0 && compare([_subviews objectAtIndex:j - 1], key, context) > 0) {
			[_subviews replaceObjectAtIndex:j withObject:[_subviews objectAtIndex:j - 1]];
			j--;
		}
		[_subviews replaceObjectAtIndex:j withObject:key];
		[key release];
	}
}

- (void)removeFromSuperviewWithoutNeedingDisplay
{
	/* THE SAME REMOVAL, WITHOUT THE INVALIDATION — a view on its way off screen does not need the area it
	 * occupied redrawn, which is what makes this the cheaper door of the pair. It forwards to THIS class's
	 * `-removeFromSuperview` rather than to `super`: a superview is an `NSView` concern, and `NSResponder`
	 * — the class above — knows nothing about it, which the compiler said. */
	[self removeFromSuperview];
}


/* THE KEY-VIEW CHAIN. Borrowed, so nothing is retained or released here: the tree owns its views and the
 * window owns the tree. */
- (NSView *)nextKeyView
{
	return _nextKeyView;
}

- (void)setNextKeyView:(NSView *)aView
{
	_nextKeyView = aView;	/* BORROWED — see the note in the header */
}

/* ============================================================================================ *
 * THE CURSOR RECTS.                                                                             *
 * ============================================================================================ */

- (void)addCursorRect:(NSRect)aRect cursor:(NSCursor *)aCursor
{
	FNCursorRect *pair;

	if (aCursor == nil) {
		return;	/* a rect with no cursor is a caller's mistake, and storing it would make it un-resolvable */
	}
	if (_cursorRects == nil) {
		_cursorRects = [[NSMutableArray alloc] init];
	}
	pair = [[FNCursorRect alloc] init];
	pair->rect = aRect;
	pair->cursor = aCursor;
	/* THE NEWEST GOES LAST, because **THE LAST DECLARED WINS** when two of one view's rects overlap — Apple's
	 * rule, and the one a view that widens its cursor area relies on. The search below runs backwards. */
	[_cursorRects addObject:pair];
	[pair release];
}

- (void)removeCursorRect:(NSRect)aRect cursor:(NSCursor *)aCursor
{
	NSUInteger i;

	/* ONE PAIR, NOT EVERY EQUAL RECT: a view may declare the same rectangle twice with different cursors, and
	 * this door takes one of them — so the search removes the LAST match and leaves the earlier one standing. */
	for (i = [_cursorRects count]; i > 0; i--) {
		FNCursorRect *pair = [_cursorRects objectAtIndex:i - 1];

		if (pair->cursor == aCursor && NSEqualRects(pair->rect, aRect)) {
			[_cursorRects removeObjectAtIndex:i - 1];
			return;
		}
	}
}

- (void)resetCursorRects
{
	/* THE HOOK, AND ITS DEFAULT DOES NOTHING: a view that wants a cursor over part of itself overrides this and
	 * calls `-addCursorRect:cursor:` from it. That is why this is a hook and not a setter. */
}

- (void)discardCursorRects
{
	[_cursorRects removeAllObjects];
	_cursorRectsStale = NO;	/* nothing to rebuild: the view has just said it wants nothing */
}

/* ---- WHAT THE WINDOW ASKS, ALL PRIVATE ------------------------------------------------------- */

/* **THE RESOLUTION IS A FUNCTION OF THE POINT, WHICH IS WHY IT CAN BE CHECKED WITHOUT A MOUSE.** The point is in
 * the RECEIVER's coordinates. THE VIEW'S OWN RECTS COME FIRST — a view's cursor covers its whole area, subviews
 * included, unless a subview overrides it — and then the SUBVIEWS FRONT TO BACK, because the array's order is
 * back-to-front and a cursor declared by the view drawn on top is what the pointer should show. */
- (NSCursor *)cg_cursorAtPoint:(NSPoint)point
{
	NSUInteger i;
	NSArray *subs = [self subviews];

	/* **THE SUBVIEWS COME FIRST AND THE VIEW'S OWN RECTS LAST, WHICH IS APPLE'S RULE AND NOT AN ARBITRARY
	 * ORDER**: a subview is drawn OVER its superview, so a cursor it declares is what the pointer should show —
	 * and a parent whose own rect covered everything would otherwise make every subview's cursor unreachable.
	 * The first version of this searched the other way round and the probe caught it. */
	for (i = [subs count]; i > 0; i--) {
		NSView *sub = [subs objectAtIndex:i - 1];
		NSCursor *c = [sub cg_cursorAtPoint:[self convertPoint:point toView:sub]];

		if (c != nil) {
			return c;
		}
	}
	{
		FNCursorRect *pair;

		for (i = [_cursorRects count]; i > 0; i--) {
			pair = [_cursorRects objectAtIndex:i - 1];
			if (NSPointInRect(point, pair->rect)) {
				return pair->cursor;
			}
		}
	}
	return nil;
}

/* A VIEW WHOSE RECTS ARE STALE SAYS SO, AND SO DOES EVERYTHING UNDER IT: a view that moved has moved its
 * subviews' rects too, and asking each one to notice would be a second traversal that could disagree. */
- (void)cg_markCursorRectsStale
{
	NSArray *subs = [self subviews];
	NSUInteger i;

	_cursorRectsStale = YES;
	for (i = 0; i < [subs count]; i++) {
		[[subs objectAtIndex:i] cg_markCursorRectsStale];
	}
}

/* AND THE REBUILD VISITS ONLY WHAT IS STALE, which is what makes `-invalidateCursorRectsForView:` worth having: a
 * pass that rebuilt the whole tree on every mouse move would call every hook in the window for one view's
 * change. */
- (void)cg_rebuildStaleCursorRects
{
	NSArray *subs = [self subviews];
	NSUInteger i;

	if (_cursorRectsStale) {
		[_cursorRects removeAllObjects];
		_cursorRectsStale = NO;
		[self resetCursorRects];	/* the hook adds them back */
	}
	for (i = 0; i < [subs count]; i++) {
		[[subs objectAtIndex:i] cg_rebuildStaleCursorRects];
	}
}

- (NSUInteger)cg_cursorRectCount
{
	return [_cursorRects count];
}

/* THE PRIVATE DOORS, DECLARED HERE BECAUSE THIS IS THE FILE THAT DEFINES THEM — and because `NSWindow` asks
 * them across the tree. */
@end
