/*
 * NSSplitView — panes, dividers, and the geometry between them.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE LAYOUT IS THE PANES' EXTENTS, NOT A SECOND ARRAY OF DIVIDER POSITIONS.** Every geometry door derives a
 * divider's leading edge from the frames before it: pane 0 starts at 0, each pane adds its extent and one divider,
 * and the last pane takes the remainder. That is why `-setPosition:ofDividerAtIndex:` only has to resize the two
 * panes beside the divider — every later divider keeps its absolute position, and every earlier one is untouched.
 *
 * **THE DRAG IS A DELTA FROM THE PRESS, AND IT RUNS THROUGH THE SAME DOOR AS `-setPosition:`.** A press records the
 * divider and the pointer's point; each motion proposes `startPosition + (point - startPoint)`. The delegate's
 * constraints, the geometric limits and the collapse rule all live in one place (`-cg_moveDividerAtIndex:...`), so
 * a programmatic move and a hand's drag cannot disagree. In a running application the press takes a tracking loop,
 * because a view is not the event's owner across a drag; with no run loop — which is how the probe drives it — the
 * loop is skipped and `-mouseDragged:`/`-mouseUp:` are the same pump, one event at a time.
 *
 * **THE COLLAPSE THRESHOLD IS APPLE'S HALF-MINIMUM RULE.** When a delegate has declared a minimum size for a pane,
 * a drag is allowed past that minimum only if the pane can collapse, and the pane collapses when it has passed
 * halfway between its minimum and zero. With no declared minimum the threshold is the leading edge itself, so the
 * pane collapses when it reaches zero. A double-click uses the delegate's `shouldCollapse` answer and toggles the
 * pane; a pane opened that way returns to the size it had when it collapsed, or to a third of the available room
 * when that size is too small to be useful.
 */
#import "NSSplitView.h"

#import "NSApplication.h"
#import "NSBezierPath.h"
#import "NSColor.h"
#import "NSCursor.h"
#import "NSEvent.h"
#import "NSWindow.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>

#include <math.h>
#include <stdlib.h>

NSString *NSSplitViewWillResizeSubviewsNotification = @"NSSplitViewWillResizeSubviewsNotification";
NSString *NSSplitViewDidResizeSubviewsNotification = @"NSSplitViewDidResizeSubviewsNotification";

/* THE KEY APPLE NAMES IN PROSE IN THE 10.6 HEADER. It is not a declared constant there, so it is not one here. */
#define AG_SPLIT_DIVIDER_INDEX_KEY @"NSSplitViewDividerIndex"

/* **THE THICKNESSES AND THE PANE SPLITTER'S THREE RINGS ARE THIS TIER'S, AND THAT IS STATED RATHER THAN PRESENTED AS
 * APPLE'S.** Apple publishes the three style names and says only that the default thickness "depends on the
 * platform". The mockup this tree is drawn from shows a narrow gutter with three hollow rings down its centre — the
 * SAME GRIP `NSScrollerCell` draws, so the rings are two-point radii eight points apart and the gutter is eighteen
 * points wide; the two ordinary styles keep their one- and six-point bars. A subclass may override
 * `-dividerThickness` or `-drawDividerInRect:` for anything else. */
#define AG_SPLIT_THICK_THICKNESS	6.0
#define AG_SPLIT_THIN_THICKNESS		1.0
#define AG_SPLIT_PANE_THICKNESS		18.0
#define AG_SPLIT_PANE_RING_RADIUS	2.0
#define AG_SPLIT_PANE_RING_SPACING	8.0
/* A collapsed pane opened by a double-click returns to its remembered size when that is at least this large; below
 * it, the pane gets a third of the available room. The number is a usability floor, not a layout rule. */
#define AG_SPLIT_RESTORE_MINIMUM		32.0
/* The thin style's hit area is wider than its ink, which is Apple's own distinction between the drawn and effective
 * rectangles. Two points on each side makes a five-point target without moving the hairline. */
#define AG_SPLIT_THIN_GRAB_PADDING	2.0

#define AG_SPLIT_AUTOSAVE_FRACTIONS	@"fractions"
#define AG_SPLIT_AUTOSAVE_COLLAPSED	@"collapsed"

static CGFloat fn_clamp(CGFloat value, CGFloat low, CGFloat high)
{
	if (high < low) {
		high = low;
	}
	if (value < low) {
		return low;
	}
	if (value > high) {
		return high;
	}
	return value;
}

static CGFloat fn_axis_point(NSPoint point, BOOL vertical)
{
	return vertical ? point.x : point.y;
}

static CGFloat fn_axis_length(NSSize size, BOOL vertical)
{
	return vertical ? size.width : size.height;
}

@interface NSSplitView ()
- (CGFloat)cg_length;
- (NSString *)cg_autosaveKey;
- (void)cg_removeStaleCollapsed;
- (BOOL)cg_isCollapsed:(NSView *)subview;
- (void)cg_collapseSubview:(NSView *)subview;
- (void)cg_uncollapseSubview:(NSView *)subview;
- (CGFloat)cg_savedSizeForSubview:(NSView *)subview;
- (CGFloat)cg_sizeOfSubviewAtIndex:(NSUInteger)index;
- (CGFloat)cg_positionOfDividerAtIndex:(NSInteger)index;
- (NSRect)cg_dividerRectAtIndex:(NSInteger)index;
- (NSRect)cg_effectiveRectForDividerAtIndex:(NSInteger)index;
- (NSInteger)cg_dividerIndexAtPoint:(NSPoint)point;
- (NSCursor *)cg_resizeCursor;
- (void)cg_setFramesFromSizes:(CGFloat *)sizes count:(NSUInteger)count;
- (CGFloat)cg_allowableMinimumForDividerAtIndex:(NSInteger)index;
- (CGFloat)cg_allowableMaximumForDividerAtIndex:(NSInteger)index;
- (BOOL)cg_canCollapseSubview:(NSView *)subview;
- (void)cg_postWillResizeWithDivider:(NSInteger)index;
- (void)cg_postDidResizeWithDivider:(NSInteger)index;
- (void)cg_moveDividerAtIndex:(NSInteger)index toPosition:(CGFloat)position;
- (void)cg_dragToPoint:(NSPoint)point;
- (void)cg_toggleCollapsedSubview:(NSView *)subview atDividerIndex:(NSInteger)index;
- (void)cg_handleDoubleClickAtDivider:(NSInteger)index;
- (void)cg_loadAutosave;
- (void)cg_saveAutosave;
@end

@implementation NSSplitView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_delegate = nil;
		_vertical = NO;
		_dividerStyle = NSSplitViewDividerStyleThick;
		_autosaveName = nil;
		_cg_collapsedSubviews = [[NSMutableArray alloc] init];
		_cg_collapsedSizes = [[NSMutableDictionary alloc] init];
		_cg_draggingDividerIndex = -1;
		_cg_dragStartPoint = NSZeroPoint;
		_cg_dragStartPosition = 0.0;
		_cg_pushedCursor = NO;
		_cg_adjusting = NO;
		_cg_hasLayout = NO;
		_cg_loadingAutosave = NO;
		_cg_autosavePending = NO;
	}
	return self;
}

- (void)dealloc
{
	[_autosaveName release];
	[_cg_collapsedSubviews release];
	[_cg_collapsedSizes release];
	[super dealloc];
}

/* A SPLIT VIEW'S COORDINATES ARE FLIPPED, which is the old documentation's own sentence and what makes subview 0
 * the top pane of a horizontal split. Overridden rather than set through `-setFlipped:` so a caller cannot turn the
 * property off and leave the geometry disagreeing with every rect this class computes. */
- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)isOpaque
{
	return NO;
}

/* ---- THE ORIENTATION AND THE FACE ---------------------------------------------------------------- */

- (BOOL)isVertical
{
	return _vertical;
}

- (void)setVertical:(BOOL)flag
{
	BOOL next = flag ? YES : NO;

	if (next == _vertical) {
		return;
	}
	_vertical = next;
	_cg_hasLayout = NO;
	[self adjustSubviews];
	[self setNeedsDisplay:YES];
	[[self window] invalidateCursorRectsForView:self];
}

- (NSSplitViewDividerStyle)dividerStyle
{
	return _dividerStyle;
}

- (void)setDividerStyle:(NSSplitViewDividerStyle)dividerStyle
{
	if (dividerStyle == _dividerStyle) {
		return;
	}
	_dividerStyle = dividerStyle;
	_cg_hasLayout = NO;
	[self adjustSubviews];
	[self setNeedsDisplay:YES];
	[[self window] invalidateCursorRectsForView:self];
}

- (CGFloat)dividerThickness
{
	switch (_dividerStyle) {
	case NSSplitViewDividerStyleThin:
		return AG_SPLIT_THIN_THICKNESS;
	case NSSplitViewDividerStylePaneSplitter:
		return AG_SPLIT_PANE_THICKNESS;
	case NSSplitViewDividerStyleThick:
	default:
		return AG_SPLIT_THICK_THICKNESS;
	}
}

- (NSColor *)dividerColor
{
	/* ONE COLOUR FOR ALL THREE STYLES — `+controlDarkShadowColor`, the tier's border grey, which the mockup uses
	 * for the pane splitter's rings and for every pane's edge. A subclass that wants another colour overrides this
	 * door; one that wants another drawing overrides `-drawDividerInRect:`. */
	return [NSColor controlDarkShadowColor];
}

- (void)drawDividerInRect:(NSRect)rect
{
	NSColor *color = [self dividerColor];

	if (color == nil) {
		color = [NSColor controlDarkShadowColor];
	}
	if (_dividerStyle == NSSplitViewDividerStylePaneSplitter) {
		CGFloat centerX = NSMidX(rect);
		CGFloat centerY = NSMidY(rect);
		NSInteger i;

		/* THE GUTTER IS THE WINDOW'S FACE, not the divider colour: the rings are the ink and the wide band
		 * between the panes is the surface showing through. */
		[[NSColor windowBackgroundColor] setFill];
		[[NSBezierPath bezierPathWithRect:rect] fill];
		[color setStroke];
		for (i = -1; i <= 1; i++) {
			NSRect ring;
			NSBezierPath *path;

			if (_vertical) {
				ring = NSMakeRect(centerX - AG_SPLIT_PANE_RING_RADIUS,
						  centerY + (CGFloat)i * AG_SPLIT_PANE_RING_SPACING
						  - AG_SPLIT_PANE_RING_RADIUS,
						  AG_SPLIT_PANE_RING_RADIUS * 2.0,
						  AG_SPLIT_PANE_RING_RADIUS * 2.0);
			} else {
				ring = NSMakeRect(centerX + (CGFloat)i * AG_SPLIT_PANE_RING_SPACING
						  - AG_SPLIT_PANE_RING_RADIUS,
						  centerY - AG_SPLIT_PANE_RING_RADIUS,
						  AG_SPLIT_PANE_RING_RADIUS * 2.0,
						  AG_SPLIT_PANE_RING_RADIUS * 2.0);
			}
			path = [NSBezierPath bezierPathWithOvalInRect:ring];
			[path setLineWidth:1.0];
			[path stroke];
		}
		return;
	}
	[color setFill];
	[[NSBezierPath bezierPathWithRect:rect] fill];
}

/* ---- THE DELEGATE AND THE AUTOSAVE NAME --------------------------------------------------------- */

- (id <NSSplitViewDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSSplitViewDelegate>)delegate
{
	_delegate = delegate;	/* NOT RETAINED */
	[self setNeedsDisplay:YES];
	[[self window] invalidateCursorRectsForView:self];
}

- (NSString *)autosaveName
{
	return _autosaveName;
}

- (void)setAutosaveName:(NSString *)autosaveName
{
	NSString *copy;

	/* SETTING THE SAME NAME AGAIN IS A NO-OP, not a second load: the first set already restored the saved frames,
	 * and re-loading would silently undo a divider the caller has moved since. */
	if (autosaveName == _autosaveName || (autosaveName != nil && _autosaveName != nil
	    && [autosaveName isEqualToString:_autosaveName])) {
		return;
	}
	copy = [autosaveName copy];
	[_autosaveName release];
	_autosaveName = copy;
	_cg_autosavePending = (_autosaveName != nil && [_autosaveName length] > 0);
	if (_cg_autosavePending && [[self subviews] count] > 0) {
		_cg_autosavePending = NO;
		[self cg_loadAutosave];
	}
}

/* ---- THE COLLAPSED SET, WHICH IS BY IDENTITY ---------------------------------------------------- */

- (BOOL)cg_isCollapsed:(NSView *)subview
{
	if (subview == nil) {
		return NO;
	}
	return [_cg_collapsedSubviews containsObject:[NSValue valueWithNonretainedObject:subview]];
}

- (CGFloat)cg_savedSizeForSubview:(NSView *)subview
{
	NSNumber *number = [_cg_collapsedSizes objectForKey:[NSValue valueWithNonretainedObject:subview]];

	return number != nil ? (CGFloat)[number doubleValue] : 0.0;
}

- (void)cg_collapseSubview:(NSView *)subview
{
	if (subview == nil || [self cg_isCollapsed:subview]) {
		return;
	}
	{
		CGFloat size = fn_axis_length([subview frame].size, _vertical);

		if (size > 0.0) {
			[_cg_collapsedSizes setObject:[NSNumber numberWithDouble:(double)size]
					       forKey:[NSValue valueWithNonretainedObject:subview]];
		}
	}
	[_cg_collapsedSubviews addObject:[NSValue valueWithNonretainedObject:subview]];
	[subview setHidden:YES];
	[self setNeedsDisplay:YES];
}

- (void)cg_uncollapseSubview:(NSView *)subview
{
	if (subview == nil || ![self cg_isCollapsed:subview]) {
		return;
	}
	[_cg_collapsedSubviews removeObject:[NSValue valueWithNonretainedObject:subview]];
	[_cg_collapsedSizes removeObjectForKey:[NSValue valueWithNonretainedObject:subview]];
	[subview setHidden:NO];
	[self setNeedsDisplay:YES];
}

/* A SUBVIEW MAY BE REMOVED WITHOUT THIS CLASS BEING TOLD, because `NSView -removeFromSuperview` does not send
 * `-willRemoveSubview:` in this tier. The pointer in the collapsed list would then be dangling, so it is swept
 * against the live subview list before every layout — a pointer comparison, no dereference. */
- (void)cg_removeStaleCollapsed
{
	NSArray *subviews = [self subviews];
	NSArray *keys;
	NSUInteger i;

	for (i = [_cg_collapsedSubviews count]; i > 0; i--) {
		id object = [[_cg_collapsedSubviews objectAtIndex:i - 1] nonretainedObjectValue];

		if ([subviews indexOfObjectIdenticalTo:object] == NSNotFound) {
			[_cg_collapsedSubviews removeObjectAtIndex:i - 1];
		}
	}
	keys = [_cg_collapsedSizes allKeys];
	for (i = 0; i < [keys count]; i++) {
		NSValue *key = [keys objectAtIndex:i];
		id object = [key nonretainedObjectValue];

		if ([subviews indexOfObjectIdenticalTo:object] == NSNotFound) {
			[_cg_collapsedSizes removeObjectForKey:key];
		}
	}
}

- (BOOL)isSubviewCollapsed:(NSView *)subview
{
	return [self cg_isCollapsed:subview];
}

/* ---- THE GEOMETRY, ALL OF IT DERIVED FROM THE FRAMES --------------------------------------------- */

- (CGFloat)cg_length
{
	return fn_axis_length([self bounds].size, _vertical);
}

- (CGFloat)cg_sizeOfSubviewAtIndex:(NSUInteger)index
{
	NSView *subview = [[self subviews] objectAtIndex:index];

	if ([self cg_isCollapsed:subview]) {
		return 0.0;
	}
	return fn_axis_length([subview frame].size, _vertical);
}

- (CGFloat)cg_positionOfDividerAtIndex:(NSInteger)index
{
	CGFloat position = 0.0;
	CGFloat thickness = [self dividerThickness];
	NSInteger i;

	if (index < 0) {
		return 0.0;
	}
	for (i = 0; i <= index; i++) {
		position += [self cg_sizeOfSubviewAtIndex:(NSUInteger)i] + thickness;
	}
	return position - thickness;
}

- (NSRect)cg_dividerRectAtIndex:(NSInteger)index
{
	CGFloat leading = [self cg_positionOfDividerAtIndex:index];
	CGFloat thickness = [self dividerThickness];
	NSRect bounds = [self bounds];

	/* A DIVIDER POSITION IS IN THE SPLIT VIEW'S BOUNDS COORDINATES, but a subview frame is in its SUPERVIEW's
	 * coordinates; when the bounds origin is not zero — which a scrolled or offset split view can have — the two
	 * differ by that origin. Everything the delegate sees stays bounds-relative; only the rect adds the origin. */
	if (_vertical) {
		return NSMakeRect(NSMinX(bounds) + leading, NSMinY(bounds), thickness, NSHeight(bounds));
	}
	return NSMakeRect(NSMinX(bounds), NSMinY(bounds) + leading, NSWidth(bounds), thickness);
}

- (NSRect)cg_effectiveRectForDividerAtIndex:(NSInteger)index
{
	NSRect drawn = [self cg_dividerRectAtIndex:index];
	NSRect proposed = drawn;

	/* APPLE'S OWN DISTINCTION: a thick divider proposes its drawn rectangle, a thin one proposes a little more so
	 * a one-point hairline is still grabbable. */
	if (_dividerStyle == NSSplitViewDividerStyleThin) {
		if (_vertical) {
			proposed.origin.x -= AG_SPLIT_THIN_GRAB_PADDING;
			proposed.size.width += AG_SPLIT_THIN_GRAB_PADDING * 2.0;
		} else {
			proposed.origin.y -= AG_SPLIT_THIN_GRAB_PADDING;
			proposed.size.height += AG_SPLIT_THIN_GRAB_PADDING * 2.0;
		}
	}
	if ([_delegate respondsToSelector:@selector(splitView:effectiveRect:forDrawnRect:ofDividerAtIndex:)]) {
		proposed = [_delegate splitView:self effectiveRect:proposed forDrawnRect:drawn
				  ofDividerAtIndex:index];
	}
	if ([_delegate respondsToSelector:@selector(splitView:additionalEffectiveRectOfDividerAtIndex:)]) {
		NSRect additional = [_delegate splitView:self additionalEffectiveRectOfDividerAtIndex:index];

		if (!NSIsEmptyRect(additional)) {
			proposed = NSUnionRect(proposed, additional);
		}
	}
	return proposed;
}

- (NSInteger)cg_dividerIndexAtPoint:(NSPoint)point
{
	NSUInteger count = [[self subviews] count];
	NSUInteger i;

	if (count < 2) {
		return -1;
	}
	for (i = 0; i + 1 < count; i++) {
		if (NSPointInRect(point, [self cg_effectiveRectForDividerAtIndex:(NSInteger)i])) {
			return (NSInteger)i;
		}
	}
	return -1;
}

/* **THE ONE PLACE FRAMES ARE WRITTEN.** The sizes are the panes' extents along the split axis; the cross axis is
 * the split view's whole bounds. A collapsed pane is forced to zero here as well as by its own caller, and the last
 * uncollapsed pane takes whatever rounding left over — which is also what keeps the last divider at the trailing
 * edge after a proportional resize.
 *
 * **THE PANE SPLITTER SNAPS ITS PANES TO WHOLE POINTS, AND THAT IS A COLOUR DECISION AS MUCH AS A GEOMETRIC ONE.**
 * Its panes carry a one-point border, and a border drawn on a fractional edge is antialiased into a LIGHTER grey than
 * the `controlDarkShadowColor` every other control uses — the eye reads that as a different border colour. Rounding
 * each non-final pane's extent to a whole point, then giving the remainder to the final one, puts the vertical card
 * edges on the pixel grid. The hairline and thick styles keep the exact fractional arithmetic because a one- or
 * six-point filled bar has no border to blur. */
- (void)cg_setFramesFromSizes:(CGFloat *)sizes count:(NSUInteger)count
{
	CGFloat thickness = [self dividerThickness];
	CGFloat length = [self cg_length];
	CGFloat cross = _vertical ? NSHeight([self bounds]) : NSWidth([self bounds]);
	CGFloat crossOrigin = _vertical ? NSMinY([self bounds]) : NSMinX([self bounds]);
	CGFloat available = length - thickness * (CGFloat)(count > 0 ? count - 1 : 0);
	CGFloat sum = 0.0;
	CGFloat position = _vertical ? NSMinX([self bounds]) : NSMinY([self bounds]);
	BOOL snap = (_dividerStyle == NSSplitViewDividerStylePaneSplitter);
	CGFloat trailing = position + length;
	NSInteger last = -1;
	NSUInteger i;

	if (available < 0.0) {
		available = 0.0;
	}
	for (i = 0; i < count; i++) {
		NSView *subview = [[self subviews] objectAtIndex:i];

		if ([self cg_isCollapsed:subview]) {
			sizes[i] = 0.0;
			continue;
		}
		if (sizes[i] < 0.0) {
			sizes[i] = 0.0;
		}
		sum += sizes[i];
		last = (NSInteger)i;
	}
	if (last >= 0 && !snap) {
		sizes[last] += available - sum;
		if (sizes[last] < 0.0) {
			sizes[last] = 0.0;
		}
	}
	for (i = 0; i < count; i++) {
		NSView *subview = [[self subviews] objectAtIndex:i];
		NSRect frame;
		CGFloat size = sizes[i];

		if (snap) {
			CGFloat maximum = trailing - thickness * (CGFloat)(count - 1 - i) - position;

			if ((NSInteger)i == last) {
				size = maximum;
			} else {
				size = floor(size + 0.5);
				if (size > maximum) {
					size = maximum;
				}
			}
			if (size < 0.0) {
				size = 0.0;
			}
		}
		if (_vertical) {
			frame = NSMakeRect(position, crossOrigin, size, cross);
		} else {
			frame = NSMakeRect(crossOrigin, position, cross, size);
		}
		[subview setFrame:frame];
		position += size + thickness;
	}
}

- (void)adjustSubviews
{
	NSUInteger count = [[self subviews] count];
	CGFloat length;
	CGFloat thickness;
	CGFloat available;
	CGFloat fixed = 0.0;
	CGFloat adjustableOld = 0.0;
	NSUInteger adjustableCount = 0;
	CGFloat *sizes;
	BOOL *adjustable;
	NSUInteger i;

	if (_cg_adjusting) {
		return;
	}
	[self cg_removeStaleCollapsed];
	if (count == 0) {
		_cg_hasLayout = YES;
		return;
	}
	if (_cg_autosavePending) {
		_cg_autosavePending = NO;
		[self cg_loadAutosave];
	}

	_cg_adjusting = YES;
	[self cg_postWillResizeWithDivider:-1];

	length = [self cg_length];
	thickness = [self dividerThickness];
	available = length - thickness * (CGFloat)(count > 0 ? count - 1 : 0);
	if (available < 0.0) {
		available = 0.0;
	}
	sizes = (CGFloat *)malloc(sizeof(CGFloat) * count);
	adjustable = (BOOL *)malloc(sizeof(BOOL) * count);

	for (i = 0; i < count; i++) {
		NSView *subview = [[self subviews] objectAtIndex:i];
		BOOL canAdjust = YES;

		adjustable[i] = NO;
		if ([self cg_isCollapsed:subview]) {
			sizes[i] = 0.0;
			continue;
		}
		sizes[i] = fn_axis_length([subview frame].size, _vertical);
		if (sizes[i] < 0.0) {
			sizes[i] = 0.0;
		}
		if ([_delegate respondsToSelector:@selector(splitView:shouldAdjustSizeOfSubview:)]) {
			canAdjust = [_delegate splitView:self shouldAdjustSizeOfSubview:subview];
		}
		adjustable[i] = canAdjust ? YES : NO;
		if (adjustable[i]) {
			adjustableOld += sizes[i];
			adjustableCount++;
		} else {
			fixed += sizes[i];
		}
	}

	if (fixed > available) {
		/* A delegate that refuses to resize everything can still leave the view over-full after a shrink. The
		 * fixed panes are then scaled proportionally, which is the least surprising way to restore a valid
		 * layout, and the adjustable ones get nothing. */
		for (i = 0; i < count; i++) {
			if (!adjustable[i]) {
				sizes[i] = fixed > 0.0 ? sizes[i] / fixed * available : 0.0;
			}
		}
		for (i = 0; i < count; i++) {
			if (adjustable[i]) {
				sizes[i] = 0.0;
			}
		}
	} else if (adjustableCount > 0) {
		CGFloat remaining = available - fixed;

		if (remaining < 0.0) {
			remaining = 0.0;
		}
		if (adjustableOld > 0.0) {
			for (i = 0; i < count; i++) {
				if (adjustable[i]) {
					sizes[i] = sizes[i] / adjustableOld * remaining;
				}
			}
		} else {
			for (i = 0; i < count; i++) {
				if (adjustable[i]) {
					sizes[i] = remaining / (CGFloat)adjustableCount;
				}
			}
		}
	}

	[self cg_setFramesFromSizes:sizes count:count];
	free(sizes);
	free(adjustable);

	_cg_hasLayout = YES;
	[self setNeedsDisplay:YES];
	_cg_adjusting = NO;
	[self cg_postDidResizeWithDivider:-1];
	[self cg_saveAutosave];
}

/* **THE FRAME DOORS RE-LAY THE PANES, AND THIS IS THE ONE HOOK THEY ALL END AT.** `NSView -setFrame:` does not call
 * `-resizeSubviewsWithOldSize:` in this tier, which is why it is overridden explicitly; `-setFrameSize:` does, so a
 * size-only set is already covered. The delegate takes precedence and OWNS the layout when it answers the resize
 * door, which is Apple's contract. */
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	if (_cg_adjusting) {
		return;
	}
	if ([_delegate respondsToSelector:@selector(splitView:resizeSubviewsWithOldSize:)]) {
		_cg_adjusting = YES;
		[self cg_postWillResizeWithDivider:-1];
		[_delegate splitView:self resizeSubviewsWithOldSize:oldSize];
		_cg_hasLayout = YES;
		[self setNeedsDisplay:YES];
		_cg_adjusting = NO;
		[self cg_postDidResizeWithDivider:-1];
		[self cg_saveAutosave];
		return;
	}
	[self adjustSubviews];
}

- (void)setFrame:(NSRect)frameRect
{
	NSSize oldSize = [self frame].size;

	[super setFrame:frameRect];
	if (oldSize.width != frameRect.size.width || oldSize.height != frameRect.size.height) {
		[self resizeSubviewsWithOldSize:oldSize];
	}
}

- (void)setBoundsSize:(NSSize)newSize
{
	NSSize oldSize = [self bounds].size;

	[super setBoundsSize:newSize];
	if (oldSize.width != newSize.width || oldSize.height != newSize.height) {
		[self resizeSubviewsWithOldSize:oldSize];
	}
}

- (void)addSubview:(NSView *)aView
{
	[super addSubview:aView];
	/* NO AUTOMATIC ADJUSTMENT. A caller that adds panes in order may give each its intended size; adjusting after
	 * every insertion would renormalise the first pane to the whole width before the second arrived. The wait is
	 * ended by the first `-adjustSubviews`, frame set or draw. */
	_cg_hasLayout = NO;
	[self setNeedsDisplay:YES];
}

- (void)willRemoveSubview:(NSView *)subview
{
	[super willRemoveSubview:subview];
	_cg_hasLayout = NO;
	[_cg_collapsedSubviews removeObject:[NSValue valueWithNonretainedObject:subview]];
	[_cg_collapsedSizes removeObjectForKey:[NSValue valueWithNonretainedObject:subview]];
}

/* ---- THE POSSIBLE AND ALLOWABLE RANGES ------------------------------------------------------------ */

- (CGFloat)minPossiblePositionOfDividerAtIndex:(NSInteger)dividerIndex
{
	NSUInteger count = [[self subviews] count];

	if (count < 2 || dividerIndex < 0 || dividerIndex >= (NSInteger)count - 1) {
		return 0.0;
	}
	if (!_cg_hasLayout) {
		[self adjustSubviews];
	}
	if (dividerIndex == 0) {
		return 0.0;
	}
	return [self cg_positionOfDividerAtIndex:dividerIndex - 1] + [self dividerThickness];
}

- (CGFloat)maxPossiblePositionOfDividerAtIndex:(NSInteger)dividerIndex
{
	NSUInteger count = [[self subviews] count];
	CGFloat maximum;

	if (count < 2 || dividerIndex < 0 || dividerIndex >= (NSInteger)count - 1) {
		maximum = [self cg_length] - [self dividerThickness];
		return maximum > 0.0 ? maximum : 0.0;
	}
	if (!_cg_hasLayout) {
		[self adjustSubviews];
	}
	if (dividerIndex == (NSInteger)count - 2) {
		maximum = [self cg_length] - [self dividerThickness];
	} else {
		maximum = [self cg_positionOfDividerAtIndex:dividerIndex + 1] - [self dividerThickness];
	}
	return maximum > 0.0 ? maximum : 0.0;
}

- (CGFloat)cg_allowableMinimumForDividerAtIndex:(NSInteger)index
{
	CGFloat minimum = [self minPossiblePositionOfDividerAtIndex:index];
	CGFloat maximum = [self maxPossiblePositionOfDividerAtIndex:index];

	if ([_delegate respondsToSelector:@selector(splitView:constrainMinCoordinate:ofSubviewAt:)]) {
		minimum = [_delegate splitView:self constrainMinCoordinate:minimum ofSubviewAt:index];
	}
	return fn_clamp(minimum, [self minPossiblePositionOfDividerAtIndex:index], maximum);
}

- (CGFloat)cg_allowableMaximumForDividerAtIndex:(NSInteger)index
{
	CGFloat minimum = [self minPossiblePositionOfDividerAtIndex:index];
	CGFloat maximum = [self maxPossiblePositionOfDividerAtIndex:index];

	if ([_delegate respondsToSelector:@selector(splitView:constrainMaxCoordinate:ofSubviewAt:)]) {
		maximum = [_delegate splitView:self constrainMaxCoordinate:maximum ofSubviewAt:index];
	}
	return fn_clamp(maximum, minimum, [self maxPossiblePositionOfDividerAtIndex:index]);
}

/* ---- THE ANNOUNCEMENTS -------------------------------------------------------------------------- */

- (void)cg_postWillResizeWithDivider:(NSInteger)index
{
	NSDictionary *info = nil;
	NSNotification *notification;

	if (index >= 0) {
		info = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:index]
						   forKey:AG_SPLIT_DIVIDER_INDEX_KEY];
	}
	notification = [NSNotification notificationWithName:NSSplitViewWillResizeSubviewsNotification
						     object:self userInfo:info];
	[[NSNotificationCenter defaultCenter] postNotification:notification];
	if ([_delegate respondsToSelector:@selector(splitViewWillResizeSubviews:)]) {
		[_delegate splitViewWillResizeSubviews:notification];
	}
}

- (void)cg_postDidResizeWithDivider:(NSInteger)index
{
	NSDictionary *info = nil;
	NSNotification *notification;

	if (index >= 0) {
		info = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:index]
						   forKey:AG_SPLIT_DIVIDER_INDEX_KEY];
	}
	notification = [NSNotification notificationWithName:NSSplitViewDidResizeSubviewsNotification
						     object:self userInfo:info];
	[[NSNotificationCenter defaultCenter] postNotification:notification];
	if ([_delegate respondsToSelector:@selector(splitViewDidResizeSubviews:)]) {
		[_delegate splitViewDidResizeSubviews:notification];
	}
}

/* ---- MOVING A DIVIDER --------------------------------------------------------------------------- */

- (BOOL)cg_canCollapseSubview:(NSView *)subview
{
	if (subview == nil || _delegate == nil) {
		return NO;
	}
	if (![_delegate respondsToSelector:@selector(splitView:canCollapseSubview:)]) {
		return NO;
	}
	return [_delegate splitView:self canCollapseSubview:subview];
}

/* **ONE DOOR FOR A DRAG AND FOR `-setPosition:`, WHICH IS WHY THEY CANNOT DISAGREE.** The order is Apple's: the
 * delegate's split-position constraint first, then the geometric range narrowed by the delegate's min/max, then the
 * collapse decision. The two panes beside the divider absorb the whole delta, so no other divider moves. */
- (void)cg_moveDividerAtIndex:(NSInteger)index toPosition:(CGFloat)position
{
	NSArray *subviews = [self subviews];
	NSUInteger count = [subviews count];
	NSView *previous;
	NSView *next;
	CGFloat geometricMinimum;
	CGFloat geometricMaximum;
	CGFloat allowableMinimum;
	CGFloat allowableMaximum;
	CGFloat current;
	CGFloat delta;
	CGFloat low;
	CGFloat high;
	CGFloat collapsePreviousAt = -1.0;
	CGFloat collapseNextAt = -1.0;
	CGFloat finalPosition;
	CGFloat previousSize;
	CGFloat nextSize;
	BOOL previousCollapsed;
	BOOL nextCollapsed;
	BOOL canCollapsePrevious;
	BOOL canCollapseNext;
	BOOL collapsePrevious = NO;
	BOOL collapseNext = NO;
	CGFloat *sizes;
	NSUInteger i;

	if (index < 0 || index >= (NSInteger)count - 1) {
		return;
	}
	if (!_cg_hasLayout) {
		[self adjustSubviews];
	}

	if ([_delegate respondsToSelector:@selector(splitView:constrainSplitPosition:ofSubviewAt:)]) {
		position = [_delegate splitView:self constrainSplitPosition:position ofSubviewAt:index];
	}

	geometricMinimum = [self minPossiblePositionOfDividerAtIndex:index];
	geometricMaximum = [self maxPossiblePositionOfDividerAtIndex:index];
	allowableMinimum = [self cg_allowableMinimumForDividerAtIndex:index];
	allowableMaximum = [self cg_allowableMaximumForDividerAtIndex:index];

	previous = [subviews objectAtIndex:(NSUInteger)index];
	next = [subviews objectAtIndex:(NSUInteger)index + 1];
	previousCollapsed = [self cg_isCollapsed:previous];
	nextCollapsed = [self cg_isCollapsed:next];
	canCollapsePrevious = [self cg_canCollapseSubview:previous];
	canCollapseNext = [self cg_canCollapseSubview:next];

	current = [self cg_positionOfDividerAtIndex:index];
	delta = position - current;

	/* THE RANGE DEPENDS ON WHICH SIDE IS SHRINKING. Moving toward the leading edge can violate the previous
	 * pane's minimum; moving toward the trailing edge can violate the next pane's. A pane that may collapse is
	 * allowed past its declared minimum, down to the geometric edge, because the half-minimum rule needs the room
	 * between the minimum and zero to exist. */
	low = geometricMinimum;
	high = geometricMaximum;
	if (delta < 0.0) {
		if (canCollapsePrevious) {
			CGFloat minimumSize = allowableMinimum - geometricMinimum;

			if (minimumSize < 0.0) {
				minimumSize = 0.0;
			}
			collapsePreviousAt = geometricMinimum + minimumSize / 2.0;
		} else {
			low = allowableMinimum;
		}
	} else if (delta > 0.0) {
		if (canCollapseNext) {
			CGFloat minimumSize = geometricMaximum - allowableMaximum;

			if (minimumSize < 0.0) {
				minimumSize = 0.0;
			}
			collapseNextAt = geometricMaximum - minimumSize / 2.0;
		} else {
			high = allowableMaximum;
		}
	} else {
		low = allowableMinimum;
		high = allowableMaximum;
	}

	finalPosition = fn_clamp(position, low, high);

	/* A COLLAPSED PANE OPENS AS SOON AS THE DIVIDER MOVES INTO IT. Its frame stays zero here; the delta below is
	 * measured from the collapsed position, so the pane grows from nothing in the direction the hand is moving. */
	if (previousCollapsed && finalPosition > current + 0.0001) {
		[self cg_uncollapseSubview:previous];
	}
	if (nextCollapsed && finalPosition < current - 0.0001) {
		[self cg_uncollapseSubview:next];
	}

	previousSize = previousCollapsed ? 0.0 : fn_axis_length([previous frame].size, _vertical);
	nextSize = nextCollapsed ? 0.0 : fn_axis_length([next frame].size, _vertical);

	if (delta < 0.0 && !previousCollapsed && canCollapsePrevious
	    && collapsePreviousAt >= geometricMinimum && finalPosition <= collapsePreviousAt + 0.0001) {
		collapsePrevious = YES;
		finalPosition = geometricMinimum;
	}
	if (delta > 0.0 && !nextCollapsed && canCollapseNext
	    && collapseNextAt >= geometricMinimum && finalPosition >= collapseNextAt - 0.0001) {
		collapseNext = YES;
		finalPosition = geometricMaximum;
	}

	delta = finalPosition - current;
	previousSize += delta;
	nextSize -= delta;
	if (previousSize < 0.0) {
		previousSize = 0.0;
	}
	if (nextSize < 0.0) {
		nextSize = 0.0;
	}
	if (collapsePrevious) {
		previousSize = 0.0;
	}
	if (collapseNext) {
		nextSize = 0.0;
	}

	if (fabs(finalPosition - current) < 0.0001 && !collapsePrevious && !collapseNext
	    && !(previousCollapsed && finalPosition > current) && !(nextCollapsed && finalPosition < current)) {
		return;
	}

	sizes = (CGFloat *)malloc(sizeof(CGFloat) * count);
	for (i = 0; i < count; i++) {
		sizes[i] = [self cg_sizeOfSubviewAtIndex:i];
	}
	sizes[index] = previousSize;
	sizes[index + 1] = nextSize;

	[self cg_postWillResizeWithDivider:index];
	if (collapsePrevious) {
		[self cg_collapseSubview:previous];
	}
	if (collapseNext) {
		[self cg_collapseSubview:next];
	}
	[self cg_setFramesFromSizes:sizes count:count];
	free(sizes);
	[self setNeedsDisplay:YES];
	[self cg_postDidResizeWithDivider:index];
	[self cg_saveAutosave];
}

- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex
{
	if (!_cg_hasLayout) {
		[self adjustSubviews];
	}
	[self cg_moveDividerAtIndex:dividerIndex toPosition:position];
}

/* ---- COLLAPSING BY A DOUBLE-CLICK ----------------------------------------------------------------- */

- (void)cg_toggleCollapsedSubview:(NSView *)subview atDividerIndex:(NSInteger)index
{
	NSArray *subviews = [self subviews];
	NSUInteger count = [subviews count];
	NSUInteger position = [subviews indexOfObjectIdenticalTo:subview];
	NSInteger neighbor;
	CGFloat *sizes;
	CGFloat available;
	NSUInteger i;

	if (position == NSNotFound || index < 0 || index >= (NSInteger)count - 1) {
		return;
	}
	sizes = (CGFloat *)malloc(sizeof(CGFloat) * count);
	for (i = 0; i < count; i++) {
		sizes[i] = [self cg_sizeOfSubviewAtIndex:i];
	}
	/* `neighbor` is the OTHER pane beside the divider, which gives up the room the toggled pane takes. */
	neighbor = ((NSInteger)position == index) ? index + 1 : index;

	available = [self cg_length] - [self dividerThickness] * (CGFloat)(count > 0 ? count - 1 : 0);
	if (available < 0.0) {
		available = 0.0;
	}

	[self cg_postWillResizeWithDivider:index];
	if ([self cg_isCollapsed:subview]) {
		CGFloat restore = [self cg_savedSizeForSubview:subview];

		if (restore < AG_SPLIT_RESTORE_MINIMUM) {
			restore = available / 3.0;
		}
		sizes[position] = restore;
		sizes[neighbor] = sizes[neighbor] - restore;
		if (sizes[neighbor] < 0.0) {
			sizes[neighbor] = 0.0;
		}
		[self cg_uncollapseSubview:subview];
	} else {
		CGFloat old = sizes[position];

		sizes[position] = 0.0;
		sizes[neighbor] += old;
		[self cg_collapseSubview:subview];
	}
	[self cg_setFramesFromSizes:sizes count:count];
	free(sizes);
	[self setNeedsDisplay:YES];
	[self cg_postDidResizeWithDivider:index];
	[self cg_saveAutosave];
}

- (void)cg_handleDoubleClickAtDivider:(NSInteger)index
{
	NSArray *subviews = [self subviews];
	NSView *previous;
	NSView *next;
	BOOL previousWants = NO;
	BOOL nextWants = NO;

	if (_delegate == nil || index < 0 || index >= (NSInteger)[subviews count] - 1) {
		return;
	}
	if (![_delegate respondsToSelector:
		      @selector(splitView:shouldCollapseSubview:forDoubleClickOnDividerAtIndex:)]) {
		return;
	}
	previous = [subviews objectAtIndex:(NSUInteger)index];
	next = [subviews objectAtIndex:(NSUInteger)index + 1];
	if ([self cg_canCollapseSubview:previous]) {
		previousWants = [_delegate splitView:self shouldCollapseSubview:previous
			     forDoubleClickOnDividerAtIndex:index];
	}
	if ([self cg_canCollapseSubview:next]) {
		nextWants = [_delegate splitView:self shouldCollapseSubview:next
			     forDoubleClickOnDividerAtIndex:index];
	}
	/* Apple calls the answer for BOTH sides and leaves the both-yes case undefined. This tier prefers the pane
	 * BEFORE the divider, which is the sidebar rather than the content in the shape this class exists for. */
	if (previousWants) {
		[self cg_toggleCollapsedSubview:previous atDividerIndex:index];
	} else if (nextWants) {
		[self cg_toggleCollapsedSubview:next atDividerIndex:index];
	}
}

/* ---- THE POINTER -------------------------------------------------------------------------------- */

- (NSCursor *)cg_resizeCursor
{
	return _vertical ? [NSCursor resizeLeftRightCursor] : [NSCursor resizeUpDownCursor];
}

- (void)resetCursorRects
{
	NSUInteger count = [[self subviews] count];
	NSUInteger i;

	if (count < 2) {
		return;
	}
	for (i = 0; i + 1 < count; i++) {
		NSRect rect = [self cg_effectiveRectForDividerAtIndex:(NSInteger)i];

		if (!NSIsEmptyRect(rect)) {
			[self addCursorRect:rect cursor:[self cg_resizeCursor]];
		}
	}
}

- (void)cg_dragToPoint:(NSPoint)point
{
	CGFloat where;
	CGFloat start;
	CGFloat position;

	if (_cg_draggingDividerIndex < 0) {
		return;
	}
	where = fn_axis_point(point, _vertical);
	start = fn_axis_point(_cg_dragStartPoint, _vertical);
	position = _cg_dragStartPosition + (where - start);
	[self cg_moveDividerAtIndex:_cg_draggingDividerIndex toPosition:position];
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point;
	NSInteger index;

	if (!_cg_hasLayout) {
		[self adjustSubviews];
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	index = [self cg_dividerIndexAtPoint:point];
	if (index < 0) {
		[super mouseDown:event];
		return;
	}
	if ([event clickCount] >= 2) {
		_cg_draggingDividerIndex = -1;
		[self cg_handleDoubleClickAtDivider:index];
		return;
	}

	_cg_draggingDividerIndex = index;
	_cg_dragStartPoint = point;
	_cg_dragStartPosition = [self cg_positionOfDividerAtIndex:index];
	_cg_pushedCursor = NO;

	/* **A PROGRAM WITH NO RUN LOOP HAS NO EVENT SOURCE.** The state above is then the whole of the press, and the
	 * probe drives `-mouseDragged:` and `-mouseUp:` itself; a running application takes the tracking loop, which
	 * owns every motion and the release even when the pointer leaves the split view. */
	if (![[NSApplication sharedApplication] isRunning]) {
		return;
	}

	[[self cg_resizeCursor] push];
	_cg_pushedCursor = YES;
	for (;;) {
		NSEvent *next;
		NSPoint where;
		NSWindow *window = [self window];

		next = [[NSApplication sharedApplication]
			nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
				    untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
				       inMode:nil dequeue:YES];
		if (next == nil) {
			/* Nothing arrived, but a frame's worth of time passed: draw what is owed and keep tracking. */
			[window displayIfNeeded];
			continue;
		}
		where = [self convertPoint:[next locationInWindow] fromView:nil];
		[self cg_dragToPoint:where];
		if ([next type] == NSLeftMouseUp) {
			break;
		}
		[window displayIfNeeded];
	}
	[NSCursor pop];
	_cg_pushedCursor = NO;
	_cg_draggingDividerIndex = -1;
	[self cg_saveAutosave];
	[self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event
{
	if (_cg_draggingDividerIndex < 0) {
		[super mouseDragged:event];
		return;
	}
	[self cg_dragToPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)mouseUp:(NSEvent *)event
{
	if (_cg_draggingDividerIndex < 0) {
		[super mouseUp:event];
		return;
	}
	[self cg_dragToPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	if (_cg_pushedCursor) {
		[NSCursor pop];
		_cg_pushedCursor = NO;
	}
	_cg_draggingDividerIndex = -1;
	[self cg_saveAutosave];
	[self setNeedsDisplay:YES];
}

/* ---- DRAWING ------------------------------------------------------------------------------------ */

- (void)drawRect:(NSRect)dirtyRect
{
	NSUInteger count = [[self subviews] count];
	NSUInteger i;

	if (!_cg_hasLayout) {
		[self adjustSubviews];
	}
	if (count < 2) {
		return;
	}
	for (i = 0; i + 1 < count; i++) {
		NSRect rect = [self cg_dividerRectAtIndex:(NSInteger)i];

		if (NSIntersectsRect(rect, dirtyRect)) {
			[self drawDividerInRect:rect];
		}
	}
}

/* ---- AUTOSAVE ----------------------------------------------------------------------------------- */

- (NSString *)cg_autosaveKey
{
	return [NSString stringWithFormat:@"AgoraSplitView %@", _autosaveName];
}

- (void)cg_saveAutosave
{
	NSArray *subviews = [self subviews];
	NSUInteger count = [subviews count];
	CGFloat available;
	NSMutableArray *fractions;
	NSMutableArray *collapsed;
	NSMutableDictionary *dictionary;
	NSUInteger i;

	if (_cg_loadingAutosave || _autosaveName == nil || [_autosaveName length] == 0 || count == 0) {
		return;
	}
	available = [self cg_length] - [self dividerThickness] * (CGFloat)(count - 1);
	if (available <= 0.0) {
		return;
	}
	fractions = [NSMutableArray array];
	collapsed = [NSMutableArray array];
	for (i = 0; i < count; i++) {
		NSView *subview = [subviews objectAtIndex:i];

		if ([self cg_isCollapsed:subview]) {
			[fractions addObject:[NSNumber numberWithDouble:0.0]];
			[collapsed addObject:[NSNumber numberWithInteger:(NSInteger)i]];
		} else {
			[fractions addObject:[NSNumber numberWithDouble:
				(double)([self cg_sizeOfSubviewAtIndex:i] / available)]];
		}
	}
	dictionary = [NSMutableDictionary dictionary];
	[dictionary setObject:fractions forKey:AG_SPLIT_AUTOSAVE_FRACTIONS];
	[dictionary setObject:collapsed forKey:AG_SPLIT_AUTOSAVE_COLLAPSED];
	[[NSUserDefaults standardUserDefaults] setObject:dictionary forKey:[self cg_autosaveKey]];
}

- (void)cg_loadAutosave
{
	NSDictionary *dictionary;
	NSArray *fractions;
	NSArray *collapsed;
	NSUInteger count = [[self subviews] count];
	CGFloat available;
	CGFloat *sizes;
	NSUInteger i;

	if (_autosaveName == nil || [_autosaveName length] == 0 || count == 0) {
		return;
	}
	dictionary = [[NSUserDefaults standardUserDefaults] dictionaryForKey:[self cg_autosaveKey]];
	if (dictionary == nil) {
		return;
	}
	fractions = [dictionary objectForKey:AG_SPLIT_AUTOSAVE_FRACTIONS];
	collapsed = [dictionary objectForKey:AG_SPLIT_AUTOSAVE_COLLAPSED];
	if (fractions == nil || [fractions count] != count) {
		return;
	}

	_cg_loadingAutosave = YES;
	/* ONLY PANES THIS CLASS COLLAPSED ARE UNHIDDEN: a pane the caller hid for its own reasons is not part of the
	 * autosave record and must not come back because a layout pass ran. */
	for (i = 0; i < count; i++) {
		NSView *subview = [[self subviews] objectAtIndex:i];

		if ([self cg_isCollapsed:subview]) {
			[subview setHidden:NO];
		}
	}
	[_cg_collapsedSubviews removeAllObjects];
	[_cg_collapsedSizes removeAllObjects];
	if (collapsed != nil) {
		for (i = 0; i < [collapsed count]; i++) {
			NSInteger index = [[collapsed objectAtIndex:i] integerValue];

			if (index >= 0 && index < (NSInteger)count) {
				NSView *subview = [[self subviews] objectAtIndex:(NSUInteger)index];

				[_cg_collapsedSubviews addObject:[NSValue valueWithNonretainedObject:subview]];
				[subview setHidden:YES];
			}
		}
	}

	available = [self cg_length] - [self dividerThickness] * (CGFloat)(count - 1);
	if (available < 0.0) {
		available = 0.0;
	}
	sizes = (CGFloat *)malloc(sizeof(CGFloat) * count);
	for (i = 0; i < count; i++) {
		NSView *subview = [[self subviews] objectAtIndex:i];

		if ([self cg_isCollapsed:subview]) {
			sizes[i] = 0.0;
		} else {
			sizes[i] = (CGFloat)[[fractions objectAtIndex:i] doubleValue] * available;
		}
	}
	[self cg_setFramesFromSizes:sizes count:count];
	free(sizes);
	_cg_loadingAutosave = NO;
	_cg_hasLayout = YES;
	[self setNeedsDisplay:YES];
}

@end

/* THE DEPRECATED PAIR. The 10.6 header says the property "has no effect" in 10.5, but an application written for
 * the older spelling expects a pane splitter to look like one, so the flag is the style here. */
@implementation NSSplitView (NSDeprecated)

- (void)setIsPaneSplitter:(BOOL)flag
{
	[self setDividerStyle:flag ? NSSplitViewDividerStylePaneSplitter : NSSplitViewDividerStyleThick];
}

- (BOOL)isPaneSplitter
{
	return _dividerStyle == NSSplitViewDividerStylePaneSplitter;
}

@end
