/*
 * NSView — a rectangle in a tree, and the coordinate systems that tree implies.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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
#import <AppKit/NSCursor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#include <stdio.h>
#include <string.h>

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
	_hidden = NO;
	/* A VIEW NOTHING HAS DRAWN NEEDS DISPLAY, which is the truthful initial state rather than a choice. */
	_needsDisplay = YES;
	_cursorRectsStale = YES;
	_subviews = nil;
	_superview = nil;
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

- (void)scrollPoint:(NSPoint)aPoint
{
	(void)aPoint;
}

- (BOOL)scrollRectToVisible:(NSRect)aRect
{
	(void)aRect;
	return NO;
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
	/* THE LAYOUT PASS APPLE'S DOOR DESCRIBES: this tier lays a view out from frames and parent-relative masks, so a
	 * plain view has no second pass to run and this is where a subclass would add one. */
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
	return nil;	/* no NSMenu in this tier */
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

- (void)beginDocument
{
	fn_refuse_window("-beginDocument", "the printing system (NSPrintOperation)");
}

- (void)endDocument
{
	fn_refuse_window("-endDocument", "the printing system (NSPrintOperation)");
}

- (void)beginPageInRect:(NSRect)aRect atPlacement:(NSPoint)location
{
	(void)aRect; (void)location;
	fn_refuse_window("-beginPageInRect:atPlacement:", "the printing system (NSPrintOperation)");
}

- (void)endPage
{
	fn_refuse_window("-endPage", "the printing system (NSPrintOperation)");
}

- (void)drawPageBorderWithSize:(NSSize)borderSize
{
	(void)borderSize;
	fn_refuse_window("-drawPageBorderWithSize:", "the printing system (NSPrintOperation)");
}

- (void)drawSheetBorderWithSize:(NSSize)borderSize
{
	(void)borderSize;
	fn_refuse_window("-drawSheetBorderWithSize:", "the printing system (NSPrintOperation)");
}

- (BOOL)knowsPageRange:(NSRangePointer)range
{
	(void)range;
	fn_refuse_window("-knowsPageRange:", "the printing system (NSPrintOperation)");
	return NO;
}

- (void)adjustPageWidthNew:(CGFloat *)newRight left:(CGFloat)oldLeft right:(CGFloat)oldRight limit:(CGFloat)rightLimit
{
	(void)newRight; (void)oldLeft; (void)oldRight; (void)rightLimit;
	fn_refuse_window("-adjustPageWidthNew:left:right:limit:", "the printing system (NSPrintOperation)");
}

- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)oldTop bottom:(CGFloat)oldBottom limit:(CGFloat)bottomLimit
{
	(void)newBottom; (void)oldTop; (void)oldBottom; (void)bottomLimit;
	fn_refuse_window("-adjustPageHeightNew:top:bottom:limit:", "the printing system (NSPrintOperation)");
}

- (NSRect)rectForPage:(NSInteger)page
{
	(void)page;
	fn_refuse_window("-rectForPage:", "the printing system (NSPrintOperation)");
	return NSZeroRect;
}

- (NSPoint)locationOfPrintRect:(NSRect)aRect
{
	(void)aRect;
	fn_refuse_window("-locationOfPrintRect:", "the printing system (NSPrintOperation)");
	return NSZeroPoint;
}

- (nullable id)rulerView
{
	return nil;	/* no NSRulerView in this tier */
}

- (void)showDefinitionForAttributedString:(NSAttributedString *)attrString atPoint:(NSPoint)textBaselineOrigin
{
	(void)attrString; (void)textBaselineOrigin;
	fn_refuse_window("-showDefinitionForAttributedString:atPoint:", "the definition look-up, and a text substrate to show it in");
}

- (void)writeEPSInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard
{
	(void)rect; (void)pasteboard;
	fn_refuse_window("-writeEPSInsideRect:toPasteboard:", "a PDF/EPS producer, which this tree's CoreGraphics has not got");
}

- (void)writePDFInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard
{
	(void)rect; (void)pasteboard;
	fn_refuse_window("-writePDFInsideRect:toPasteboard:", "the PDF substrate, which this tree parked");
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

- (nullable NSView *)enclosingScrollView
{
	/* **THE WALK THAT COULD NOT BE WRITTEN UNTIL THE CLASS EXISTED.** This door used to answer nil BECAUSE THERE WAS
	 * NO `NSScrollView` — a scroll view is the frame, the scrollers and the ruler, and only the clip view was here —
	 * and the comment recorded the compiler's own answer (`use of undeclared identifier 'NSScrollView'`). The class
	 * exists now, so the walk does too: the nearest ancestor that IS a scroll view, exactly as `-opaqueAncestor`
	 * above walks for the nearest opaque one. */
	NSView *v = [self superview];

	while (v != nil) {
		if ([v isKindOfClass:[NSScrollView class]]) {
			return v;
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
	return NO;	/* Apple's answer for a plain view, and there is no panel here to need */
}

- (BOOL)inFullScreenMode
{
	/* THE FULL-SCREEN MODE IS THE MANAGER'S — the keys this class declares name its dictionary — and nothing here
	 * enters one. */
	return NO;
}

- (BOOL)rotatedFromBase
{
	return NO;	/* this tier's frames are not rotated from a base frame */
}

- (BOOL)rotatedOrScaledFromBase
{
	return NO;	/* the same, and nothing scales one either */
}

- (CGFloat)boundsRotation
{
	return 0.0;
}

- (CGFloat)frameRotation
{
	return 0.0;
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

- (nullable id)inputContext
{
	return nil;	/* no NSTextInputContext: this tier has no text system */
}

- (nullable id)defaultMenu
{
	return nil;	/* no NSMenu in this tier */
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
	/* NIL RATHER THAN A MADE-UP TITLE: a print job title belongs to a print job, and `-print:` refuses to make one. */
	return nil;
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
	(void)rect;
	fn_refuse_window("-dataWithEPSInsideRect:", "a PDF/EPS producer, which this tree's CoreGraphics has not got");
	return nil;
}

- (nullable NSData *)dataWithPDFInsideRect:(NSRect)rect
{
	(void)rect;
	fn_refuse_window("-dataWithPDFInsideRect:", "the PDF substrate, which this tree parked");
	return nil;
}

- (void)print:(id)sender
{
	(void)sender;
	fn_refuse_window("-print:", "the printing system (NSPrintOperation)");
}

- (void)dragImage:(NSImage *)anImage at:(NSPoint)viewLocation offset:(NSSize)initialOffset event:(NSEvent *)event
       pasteboard:(NSPasteboard *)pboard source:(id)sourceObj slideBack:(BOOL)slideFlag
{
	(void)anImage; (void)viewLocation; (void)initialOffset; (void)event; (void)pboard; (void)sourceObj;
	(void)slideFlag;
	fn_refuse_window("-dragImage:at:offset:event:pasteboard:source:slideBack:",
			 "a drag session (the window server's drag loop)");
}

/* AND THE THREE THAT ANSWER RATHER THAN REFUSE. */

- (NSInteger)gState
{
	/* A VALUE, NOT A MISSING ONE: this tier draws through a `CGContext`, so there is no graphics-state ID, and 0 is
	 * the truth about that rather than a stand-in for one. */
	return 0;
}

- (void)registerForDraggedTypes:(NSArray *)newTypes
{
	/* RECORDED, AND ON THE VIEW THIS IS THE REAL CONTRACT'S HALF: what would consume the set is this view's own drag
	 * acceptance. There is still no drag session to exercise it, so the set is kept and read back through a seam. */
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


- (void)setFrame:(NSRect)frameRect
{
	NSRect previousFrame = _frame;

	_frame = frameRect;
	/* THE SIZE IS SHARED AND THE ORIGINS ARE NOT — see the header for what this deliberately does not
	 * model (a bounds origin that is a scroll offset). */
	_bounds = NSMakeRect(_bounds.origin.x, _bounds.origin.y, frameRect.size.width,
			     frameRect.size.height);
	_needsDisplay = YES;
	[self cg_frameDidChangeFrom:previousFrame];
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
	_hidden = flag ? YES : NO;
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
	/* THE ARRAY OWNS IT (it retains), and the borrowed link is set from here because `_superview` is
	 * PROTECTED and only a method of this class may write another instance's. */
	[_subviews addObject:aView];
	aView->_superview = self;
	[aView cg_setWindow:_window];
	[aView viewDidMoveToSuperview];
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
	} else {
		/* THE UNION, because two invalidations that do not touch are still two reasons to draw and the region
		 * this view keeps is one rect — Apple's own simplification, and the reason a view that invalidates two
		 * opposite corners draws their bounding box. */
		_dirtyRect = NSUnionRect(_dirtyRect, invalidRect);
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

- (void)cg_clearDirtyRegion
{
	_hasDirtyRect = NO;
	_needsDisplay = NO;
	{
		NSUInteger i;

		for (i = 0; i < [_subviews count]; i++) {
			[[_subviews objectAtIndex:i] cg_clearDirtyRegion];
		}
	}
}

/* ---- DRAWING A TREE ------------------------------------------------------------------------ */

/* THE RECURSION, AND THE RECT IS IN THE RECEIVER'S COORDINATES — the child's is CONVERTED rather than
 * subtracted, so a superview with an offset bounds or a flipped child still lands in the right place. */
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

- (void)displayRectIgnoringOpacity:(NSRect)rect context:(NSGraphicsContext *)context
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
	[self setNeedsDisplay:YES];
	/* A FRAME CHANGE IS THE ONLY THING THAT REARRANGES SUBVIEWS, which is why the hook is called here and
	 * nowhere else. */
	[self resizeSubviewsWithOldSize:old];

	[self cg_frameDidChangeFrom:previousFrame];
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
 * a subclass's override has somewhere to run. THE AUTORESIZING MASKS THEMSELVES ARE NOT HERE — that is the
 * springs-and-struts slice, and `-resizeWithOldSuperviewSize:`'s default doing nothing is exactly what Apple's
 * does when no mask is set. */
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
