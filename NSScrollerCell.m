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

/* **A HELD PAGE REPEATS, AND THESE TWO NUMBERS ARE THE FEEL OF IT.** The first repeat waits out a hand that meant ONE
 * page; after that the steps come fast enough to read as motion. Both belong to the CELL rather than to the tracking
 * loop, so the loop never learns one control's timing — it only asks whether the cell has something more to say. */
#define NS_SCROLLER_REPEAT_DELAY	0.35
#define NS_SCROLLER_REPEAT_INTERVAL	0.05

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
		_repeatDeadline = 0.0;
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
	/* **A PART THAT STEPS ARMS THE REPEAT, AND THE KNOB DOES NOT.** A drag is already a value per point, so repeating
	 * it would only re-apply a value that has not moved; a PAGE or a LINE is the part that has nothing to say until
	 * time passes. Anything else — the bare slot, no part — has no action to repeat at all. */
	if (_hitPart == NSScrollerDecrementPage || _hitPart == NSScrollerIncrementPage ||
	    _hitPart == NSScrollerDecrementLine || _hitPart == NSScrollerIncrementLine) {
		_repeatDeadline = [NSDate timeIntervalSinceReferenceDate] + NS_SCROLLER_REPEAT_DELAY;
	} else {
		_repeatDeadline = 0.0;
	}
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
	} else {
		/* **A PAGE OR A LINE HAS ALREADY ACTED, AND THE POINT THE BUTTON CAME UP AT IS NOT A SECOND ACT.**
		 * `NSControl -mouseDown:` sends a continuous cell's action on the PRESS AND AGAIN on the release, because
		 * for a SLIDER those are the same question — its value is ABSOLUTE, so setting it twice is setting it once.
		 * A PAGE IS A STEP, so the same loop scrolls twice per click: MEASURED, one click on the increment page
		 * moved the clip view to the document's end (215) instead of one page (175). The PART is the press's fact,
		 * so it is reported ONCE: clearing it here makes the release's action read `NSScrollerNoPart` and do nothing.
		 * The KNOB keeps its part, because a drag really is a value that follows every point, the last included. */
		_hitPart = NSScrollerNoPart;
		_repeatDeadline = 0.0;	/* AND A HELD PAGE STOPS REPEATING THE MOMENT THE BUTTON MOVES OR COMES UP. */
	}
	return YES;
}

/* ---- AND THE REPEAT, WHICH THE LOOP POLLS --------------------------------------------------------------- */

- (BOOL)cg_trackingShouldRepeat
{
	return [self cg_trackingShouldRepeatAtTime:[NSDate timeIntervalSinceReferenceDate]];
}

- (BOOL)cg_trackingShouldRepeatAtTime:(NSTimeInterval)now
{
	if (_repeatDeadline > 0.0 && now >= _repeatDeadline) {
		_repeatDeadline = now + NS_SCROLLER_REPEAT_INTERVAL;
		return YES;
	}
	return NO;
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

/* **AN ARROW IS RASTERIZED A POINT AT A TIME, AND THAT IS THE WHOLE FIX.** A seven-point triangle filled as an
 * ANTI-ALIASED PATH comes out a grey smudge — MEASURED on the live window: the two arrows did not even match each
 * other, the top one five points wide at its base and the bottom three, because a fractional vertex lands
 * differently on the pixel grid depending on which way the point faces. WHOLE-POINT ROWS have no such freedom: the
 * arrow is CRISP, it is SYMMETRIC about its axis by construction, and the up one is exactly the down one turned
 * over. A scroll button is small enough that every edge is half the drawing, which is the size at which a path
 * stops being a shape and starts being a blur. */
static void fn_fill_arrow_rows(CGContextRef c, int centre_x, int top, int box, BOOL points_up)
{
	int row;

	for (row = 0; row < box; row++) {
		/* THE WIDTH STEPS BY WHOLE POINTS, so the sides are a staircase and not a blur; the `box / 2` half-steps
		 * keep it centred, which is what makes the apex a SINGLE point rather than a two-point flat. */
		int step = points_up ? row : (box - 1 - row);
		int wide = 1 + 2 * ((step * (box / 2)) / (box > 1 ? box - 1 : 1));

		if (wide > box) {
			wide = box;
		}
		CGContextFillRect(c, CGRectMake((CGFloat)(centre_x - wide / 2), (CGFloat)(top + row),
						(CGFloat)wide, 1.0));
	}
}

static void fn_fill_arrow_cols(CGContextRef c, int centre_y, int left, int box, BOOL points_left)
{
	int col;

	for (col = 0; col < box; col++) {
		int step = points_left ? col : (box - 1 - col);
		int high = 1 + 2 * ((step * (box / 2)) / (box > 1 ? box - 1 : 1));

		if (high > box) {
			high = box;
		}
		CGContextFillRect(c, CGRectMake((CGFloat)(left + col), (CGFloat)(centre_y - high / 2),
						1.0, (CGFloat)high));
	}
}

/* ONE ARROW, POINTING THE WAY ITS PART SCROLLS. The decrement arrow points to the smaller values — up in a vertical
 * scroller, left in a horizontal one — which in a flipped view is the smaller y or x, so no flip arithmetic is
 * needed here: the coordinates are already the reader's. */
- (void)drawArrow:(NSScrollerArrow)whichArrow highlight:(BOOL)flag
{
	NSRect r = [self rectForPart:(whichArrow == NSScrollerDecrementArrow) ? NSScrollerDecrementLine
									     : NSScrollerIncrementLine];
	CGContextRef c = [[NSGraphicsContext currentContext] CGContext];
	BOOL decrement = (whichArrow == NSScrollerDecrementArrow);
	int side;
	int box;
	int inset;

	if (c == NULL || r.size.width <= 0.0 || r.size.height <= 0.0) {
		return;
	}
	side = (int)(NSWidth(r) < NSHeight(r) ? NSWidth(r) : NSHeight(r));
	inset = (int)NS_SCROLLER_ARROW_INSET;
	box = side - 2 * inset;
	if (box < 3) {
		inset = 1;
		box = side - 2;
	}
	if (box < 1) {
		return;
	}
	if (flag && [self isEnabled]) {
		CGContextSetFillColorWithColor(c, [[NSColor controlDarkShadowColor] CGColor]);
	} else {
		CGContextSetFillColorWithColor(c, [[NSColor controlShadowColor] CGColor]);
	}
	if (![self fn_horizontalInFrame:[self cg_frame]]) {
		int top = (int)NSMinY(r) + ((int)NSHeight(r) - box) / 2;

		fn_fill_arrow_rows(c, (int)NSMidX(r), top, box, decrement);
	} else {
		int left = (int)NSMinX(r) + ((int)NSWidth(r) - box) / 2;

		fn_fill_arrow_cols(c, (int)NSMidY(r), left, box, decrement);
	}
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
