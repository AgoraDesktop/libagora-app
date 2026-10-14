/*
 * NSScrollerCell — a fraction in, a knob out; a point in, a part out.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE GEOMETRY IS WRITTEN ONCE AND ASKED TWO WAYS.** `-testPart:` and `-rectForPart:` are not two implementations
 * of the same layout: every part's rectangle comes from one of the four private `fn_` helpers below, and `-testPart:`
 * only ever asks those helpers whether a point is inside one. That is what keeps a press and a painting from
 * disagreeing about where the knob is — the class of bug a scroller is especially good at hiding, because the two
 * are read at different times.
 */
#import <AppKit/NSScrollerCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>
#import <Foundation/NSGeometry.h>

/* THE TWO NUMBERS OF THE FACE. The arrow's inset is how far the triangle is held off its button; the knob's corner
 * radius is the platform's bezel radius for a small control, named here rather than reached for. */
#define NS_SCROLLER_ARROW_INSET 4.0
#define NS_SCROLLER_KNOB_RADIUS 2.0

@implementation NSScrollerCell

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		/* **THE VALUE PAIR'S QUIET STATE IS "AT THE START, SEEING EVERYTHING".** A knob that fills the track is the
		 * honest answer for a scroller nobody has set — there is nowhere to scroll — and it is what keeps a
		 * freshly-made scroller from drawing a zero-length knob the moment it is put on screen. */
		_floatValue = 0.0;
		_knobProportion = 1.0;
		_hitPart = NSScrollerNoPart;
		_grabDelta = 0.0;
		_arrowsPosition = NSScrollerArrowsMaxEnd;
		_lastFrame = NSZeroRect;
		_controlSize = NSRegularControlSize;
		/* **AND A SCROLLER IS CONTINUOUS, WHICH IS WHAT MAKES THE KNOB FOLLOW.** Its value is set BY the pointer, so
		 * a value that only spoke when the button came up would be a knob that jumped once at the end; the same
		 * reading, and the same reason, `NSSliderCell` takes. */
		_continuous = YES;
	}
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

/* ---- THE VALUE PAIR ------------------------------------------------------------------------------------- */

- (void)setFloatValue:(CGFloat)value knobProportion:(CGFloat)proportion
{
	CGFloat v = value;
	CGFloat p = proportion;

	/* **BOTH NUMBERS ARE CLAMPED HERE AND NOWHERE ELSE**, so every caller gets the same answer: a fraction outside
	 * [0, 1] is not a place a knob can be, and a proportion outside it is not a share of a track. A NAN is caught
	 * first, because `NaN < 0.0` and `NaN > 1.0` are both false and a NAN would otherwise slip through unclamped. */
	if (v != v) {
		v = 0.0;
	}
	if (p != p) {
		p = 0.0;
	}
	if (v < 0.0) {
		v = 0.0;
	}
	if (v > 1.0) {
		v = 1.0;
	}
	if (p < 0.0) {
		p = 0.0;
	}
	if (p > 1.0) {
		p = 1.0;
	}
	_floatValue = v;
	_knobProportion = p;
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (CGFloat)floatValue
{
	return _floatValue;
}

- (CGFloat)knobProportion
{
	return _knobProportion;
}

- (NSScrollerPart)hitPart
{
	return _hitPart;
}

- (NSScrollArrowPosition)arrowsPosition
{
	return _arrowsPosition;
}

- (void)setArrowsPosition:(NSScrollArrowPosition)where
{
	_arrowsPosition = where;
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

/* ---- THE GEOMETRY, IN ONE PLACE ------------------------------------------------------------------------- */

/* THE FRAME THE GEOMETRY IS ANSWERED AGAINST. Apple's `-rectForPart:` takes no rectangle, so the cell asks its
 * control view — and a cell with no view falls back to the last frame it was drawn into, which is what lets an
 * offscreen probe ask about a frame it supplied. */
- (NSRect)cg_frame
{
	id view = [self controlView];

	if (view != nil && [view respondsToSelector:@selector(bounds)]) {
		return [(NSView *)view bounds];
	}
	return _lastFrame;
}

/* A scroller is horizontal when it is wider than it is tall — the only thing that decides it, and the reason
 * `-isFlipped` on the control matters for which END the decrement is. */
- (BOOL)fn_horizontalInFrame:(NSRect)frame
{
	return NSWidth(frame) > NSHeight(frame);
}

/* THE THICKNESS: the short side, which is also the size of an arrow button and the floor under the knob's length. */
- (CGFloat)fn_thicknessInFrame:(NSRect)frame
{
	CGFloat w = NSWidth(frame);
	CGFloat h = NSHeight(frame);

	return (w < h) ? w : h;
}

- (CGFloat)fn_arrowLengthInFrame:(NSRect)frame
{
	if (_arrowsPosition == NSScrollerArrowsNone) {
		return 0.0;
	}
	return [self fn_thicknessInFrame:frame];
}

/* **THE SLOT: THE FRAME LESS AN ARROW AT EACH END.** With no arrows it is the whole frame, which is the one value of
 * `NSScrollerArrowsNone` that changes geometry rather than ink. A negative extent clamps to zero rather than
 * inverting the rectangle — a scroller too small for its own arrows is a degenerate case and not a crash. */
- (NSRect)fn_slotRectInFrame:(NSRect)frame
{
	CGFloat arrow = [self fn_arrowLengthInFrame:frame];
	CGFloat w = NSWidth(frame);
	CGFloat h = NSHeight(frame);

	if ([self fn_horizontalInFrame:frame]) {
		CGFloat sw = w - 2.0 * arrow;

		if (sw < 0.0) {
			sw = 0.0;
		}
		return NSMakeRect(NSMinX(frame) + arrow, NSMinY(frame), sw, h);
	}
	{
		CGFloat sh = h - 2.0 * arrow;

		if (sh < 0.0) {
			sh = 0.0;
		}
		return NSMakeRect(NSMinX(frame), NSMinY(frame) + arrow, w, sh);
	}
}

/* **THE KNOB'S LENGTH, WITH ITS FLOOR.** `-knobProportion` of the slot, but never shorter than the scroller is thick
 * and never longer than the slot: the first keeps a one-row document grabbable, the second keeps a proportion of 1
 * from spilling past the track it fills. */
- (CGFloat)fn_knobLengthForSlot:(CGFloat)slotLength
{
	CGFloat length = _knobProportion * slotLength;
	CGFloat floor = [self fn_thicknessInFrame:[self cg_frame]];

	if (floor > slotLength) {
		floor = slotLength;
	}
	if (length < floor) {
		length = floor;
	}
	if (length > slotLength) {
		length = slotLength;
	}
	if (length < 0.0) {
		length = 0.0;
	}
	return length;
}

- (NSRect)fn_knobRectInFrame:(NSRect)frame
{
	NSRect slot = [self fn_slotRectInFrame:frame];

	if ([self fn_horizontalInFrame:frame]) {
		CGFloat slotLen = NSWidth(slot);
		CGFloat knobLen = [self fn_knobLengthForSlot:slotLen];
		CGFloat travel = slotLen - knobLen;
		CGFloat x = NSMinX(slot) + _floatValue * travel;

		return NSMakeRect(x, NSMinY(slot), knobLen, NSHeight(slot));
	}
	{
		CGFloat slotLen = NSHeight(slot);
		CGFloat knobLen = [self fn_knobLengthForSlot:slotLen];
		CGFloat travel = slotLen - knobLen;
		CGFloat y = NSMinY(slot) + _floatValue * travel;

		return NSMakeRect(NSMinX(slot), y, NSWidth(slot), knobLen);
	}
}

/* **A LINE BUTTON, AT THE END THE DECREMENT IS.** The decrement end is the TOP of a vertical scroller and the LEFT of
 * a horizontal one, because a scroller is flipped: the smaller values are the way the arrows point. */
- (NSRect)fn_lineRectInFrame:(NSRect)frame decrement:(BOOL)decrement
{
	CGFloat arrow = [self fn_arrowLengthInFrame:frame];

	if (arrow <= 0.0) {
		return NSZeroRect;
	}
	if ([self fn_horizontalInFrame:frame]) {
		if (decrement) {
			return NSMakeRect(NSMinX(frame), NSMinY(frame), arrow, NSHeight(frame));
		}
		return NSMakeRect(NSMaxX(frame) - arrow, NSMinY(frame), arrow, NSHeight(frame));
	}
	if (decrement) {
		return NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), arrow);
	}
	return NSMakeRect(NSMinX(frame), NSMaxY(frame) - arrow, NSWidth(frame), arrow);
}

- (NSRect)rectForPart:(NSScrollerPart)part
{
	NSRect frame = [self cg_frame];
	NSRect slot;
	NSRect knob;
	BOOL horizontal;

	switch (part) {
	case NSScrollerKnobSlot:
		return [self fn_slotRectInFrame:frame];
	case NSScrollerKnob:
		return [self fn_knobRectInFrame:frame];
	case NSScrollerDecrementLine:
		return [self fn_lineRectInFrame:frame decrement:YES];
	case NSScrollerIncrementLine:
		return [self fn_lineRectInFrame:frame decrement:NO];
	default:
		break;
	}
	slot = [self fn_slotRectInFrame:frame];
	knob = [self fn_knobRectInFrame:frame];
	horizontal = [self fn_horizontalInFrame:frame];
	if (part == NSScrollerDecrementPage) {
		if (horizontal) {
			return NSMakeRect(NSMinX(slot), NSMinY(slot), NSMinX(knob) - NSMinX(slot), NSHeight(slot));
		}
		return NSMakeRect(NSMinX(slot), NSMinY(slot), NSWidth(slot), NSMinY(knob) - NSMinY(slot));
	}
	if (part == NSScrollerIncrementPage) {
		if (horizontal) {
			return NSMakeRect(NSMaxX(knob), NSMinY(slot), NSMaxX(slot) - NSMaxX(knob), NSHeight(slot));
		}
		return NSMakeRect(NSMinX(slot), NSMaxY(knob), NSWidth(slot), NSMaxY(slot) - NSMaxY(knob));
	}
	return NSZeroRect;
}

/* **THE POINT'S PART, WHICH IS THE SAME RECTANGLES READ THE OTHER WAY.** The buttons are tried first, then the knob,
 * then the slot split at the knob — so a point on the knob is never reported as a page even though the knob sits
 * inside the slot's rectangle. */
- (NSScrollerPart)testPart:(NSPoint)point
{
	NSRect frame = [self cg_frame];
	NSRect slot;
	NSRect knob;
	BOOL horizontal;

	if (_arrowsPosition != NSScrollerArrowsNone) {
		if (NSPointInRect(point, [self fn_lineRectInFrame:frame decrement:YES])) {
			return NSScrollerDecrementLine;
		}
		if (NSPointInRect(point, [self fn_lineRectInFrame:frame decrement:NO])) {
			return NSScrollerIncrementLine;
		}
	}
	knob = [self fn_knobRectInFrame:frame];
	if (NSPointInRect(point, knob)) {
		return NSScrollerKnob;
	}
	slot = [self fn_slotRectInFrame:frame];
	if (NSPointInRect(point, slot)) {
		horizontal = [self fn_horizontalInFrame:frame];
		if (horizontal) {
			return (point.x < NSMinX(knob)) ? NSScrollerDecrementPage : NSScrollerIncrementPage;
		}
		return (point.y < NSMinY(knob)) ? NSScrollerDecrementPage : NSScrollerIncrementPage;
	}
	return NSScrollerNoPart;
}

/* ---- THE TRACKING, WHICH IS THE CELL'S HALF OF `NSControl`'S LOOP --------------------------------------- */

/* **A PRESS REMEMBERS TWO THINGS AND CHANGES NOTHING.** The part it landed on is what the action will read, and — if
 * it landed on the knob — how far along the knob it landed, so the drag can keep that same point under the hand.
 * A press on a page or a line does NOT move the knob here: the enclosing scroll view performs the scrolling and calls
 * `-setFloatValue:knobProportion:` with the result, which is the split that keeps this cell a control and no more. */
- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	NSRect frame = (controlView != nil) ? [controlView bounds] : _lastFrame;

	_lastFrame = frame;
	_hitPart = [self testPart:startPoint];
	if (_hitPart == NSScrollerKnob) {
		NSRect knob = [self fn_knobRectInFrame:frame];

		_grabDelta = [self fn_horizontalInFrame:frame] ? (startPoint.x - NSMinX(knob))
							       : (startPoint.y - NSMinY(knob));
	}
	return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
	(void)lastPoint;
	if (_hitPart == NSScrollerKnob) {
		NSRect frame = (controlView != nil) ? [controlView bounds] : _lastFrame;
		BOOL horizontal = [self fn_horizontalInFrame:frame];
		NSRect slot = [self fn_slotRectInFrame:frame];
		CGFloat slotLen = horizontal ? NSWidth(slot) : NSHeight(slot);
		CGFloat knobLen = [self fn_knobLengthForSlot:slotLen];
		CGFloat travel = slotLen - knobLen;
		CGFloat slotStart = horizontal ? NSMinX(slot) : NSMinY(slot);
		CGFloat along = (horizontal ? currentPoint.x : currentPoint.y) - _grabDelta;
		CGFloat value = 0.0;

		if (travel > 0.0) {
			value = (along - slotStart) / travel;
		}
		if (value < 0.0) {
			value = 0.0;
		}
		if (value > 1.0) {
			value = 1.0;
		}
		[self setFloatValue:value knobProportion:_knobProportion];
	}
	return YES;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
	/* NOTHING TO CLOSE: the value is already where the last point put it, and the part stays answered for the action
	 * that follows this. Declared rather than omitted so the three hooks read as a set. */
	(void)lastPoint;
	(void)stopPoint;
	(void)controlView;
	(void)flag;
}

/* ---- THE INK -------------------------------------------------------------------------------------------- */

/* ONE ARROW, POINTING THE WAY ITS PART SCROLLS. The decrement arrow points to the smaller values — up in a vertical
 * scroller, left in a horizontal one — which in a flipped view is the smaller y or x, so no flip arithmetic is
 * needed here: the coordinates are already the reader's. */
- (void)drawArrow:(NSScrollerArrow)whichArrow highlight:(BOOL)flag
{
	NSRect r = [self rectForPart:(whichArrow == NSScrollerDecrementArrow) ? NSScrollerDecrementLine
									     : NSScrollerIncrementLine];
	CGFloat inset = NS_SCROLLER_ARROW_INSET;
	NSBezierPath *p;

	if (r.size.width <= 0.0 || r.size.height <= 0.0) {
		return;
	}
	if (2.0 * inset >= NSWidth(r) || 2.0 * inset >= NSHeight(r)) {
		inset = 1.0;
	}
	p = [NSBezierPath bezierPath];
	if (![self fn_horizontalInFrame:[self cg_frame]]) {
		if (whichArrow == NSScrollerDecrementArrow) {
			[p moveToPoint:NSMakePoint(NSMinX(r) + inset, NSMaxY(r) - inset)];
			[p lineToPoint:NSMakePoint(NSMaxX(r) - inset, NSMaxY(r) - inset)];
			[p lineToPoint:NSMakePoint(NSMidX(r), NSMinY(r) + inset)];
		} else {
			[p moveToPoint:NSMakePoint(NSMinX(r) + inset, NSMinY(r) + inset)];
			[p lineToPoint:NSMakePoint(NSMaxX(r) - inset, NSMinY(r) + inset)];
			[p lineToPoint:NSMakePoint(NSMidX(r), NSMaxY(r) - inset)];
		}
	} else {
		if (whichArrow == NSScrollerDecrementArrow) {
			[p moveToPoint:NSMakePoint(NSMaxX(r) - inset, NSMinY(r) + inset)];
			[p lineToPoint:NSMakePoint(NSMaxX(r) - inset, NSMaxY(r) - inset)];
			[p lineToPoint:NSMakePoint(NSMinX(r) + inset, NSMidY(r))];
		} else {
			[p moveToPoint:NSMakePoint(NSMinX(r) + inset, NSMinY(r) + inset)];
			[p lineToPoint:NSMakePoint(NSMinX(r) + inset, NSMaxY(r) - inset)];
			[p lineToPoint:NSMakePoint(NSMaxX(r) - inset, NSMidY(r))];
		}
	}
	[p closePath];
	if (flag && [self isEnabled]) {
		[[NSColor controlDarkShadowColor] setFill];
	} else {
		[[NSColor controlShadowColor] setFill];
	}
	[p fill];
}

- (void)drawKnob
{
	NSRect r = [self rectForPart:NSScrollerKnob];
	NSBezierPath *p;

	if (r.size.width <= 0.0 || r.size.height <= 0.0) {
		return;
	}
	p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:NS_SCROLLER_KNOB_RADIUS
					    yRadius:NS_SCROLLER_KNOB_RADIUS];
	/* A DISABLED SCROLLER STILL DRAWS ITS KNOB, in the background colour rather than the face — the position is
	 * still worth showing, it simply stops claiming to be grabbable. A PRESSED one wears the dark shadow. */
	if (![self isEnabled]) {
		[[NSColor controlBackgroundColor] setFill];
		[p fill];
		[[NSColor controlDarkShadowColor] setStroke];
	} else if ([self isHighlighted]) {
		[[NSColor controlDarkShadowColor] setFill];
		[p fill];
		[[NSColor controlShadowColor] setStroke];
	} else {
		[[NSColor controlColor] setFill];
		[p fill];
		[[NSColor controlShadowColor] setStroke];
	}
	[p stroke];
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
	(void)flag;
	if (slotRect.size.width <= 0.0 || slotRect.size.height <= 0.0) {
		return;
	}
	/* **THE SLOT IS THE RECESS, SO IT IS DRAWN FIRST AND UNDER EVERYTHING.** The arrows are then drawn on top of it,
	 * and the knob last of all — which is the order a raised knob over a hollow groove reads as. */
	[[NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:slotRect] fill];
	if (_arrowsPosition != NSScrollerArrowsNone) {
		[self drawArrow:NSScrollerDecrementArrow highlight:NO];
		[self drawArrow:NSScrollerIncrementArrow highlight:NO];
	}
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	(void)controlView;
	/* **THE SLOT IS FILLED OVER THE WHOLE FRAME, NOT JUST THE GROOVE.** With arrows present the groove is the middle
	 * of the frame and the arrows sit at the ends; with them absent the groove IS the frame. Filling the slot's own
	 * rectangle and then drawing the arrows leaves the arrow buttons as part of the slot's ground rather than as
	 * bare background, which is what keeps the three pieces reading as one control. */
	_lastFrame = cellFrame;
	[[NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:cellFrame] fill];
	[self drawKnobSlotInRect:[self rectForPart:NSScrollerKnobSlot] highlight:[self isHighlighted]];
	[self drawKnob];
}

@end
