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

/* **ARGENTUM'S NUMBERS FOR THE FACE, MEASURED FROM `Argentum Mockup.png` — WHICH IS A BITMAP EXPORTED FROM AFFINITY
 * DESIGNER, so its SHAPES are the design and its blended edges are not.** The mockup's scroller is 17 points thick;
 * these are its shapes at the 15-point width this tree builds scrollers at. ONE radius covers the knob and the two
 * buttons — the sample's knob has flat sides and rounds only in its last three points — and THE GROOVE IS NOT ROUNDED
 * AT ALL: it is the recess the knob runs in, and a rounded recess reads as one more raised thing. */
/* **THE ARROW'S TWO NUMBERS, AS FRACTIONS OF ITS BUTTON.** The sample draws an arrow 6 points across and 4 tall on a
 * 17-point bar, so these are 6/17 and half of it — and the shape is WIDER THAN IT IS TALL, which is a thing a PATH
 * can carry and a staircase could not. */
#define NS_SCROLLER_ARROW_HALF		0.176	/* of the button's short side: half of 6/17 across */
#define NS_SCROLLER_ARROW_HEIGHT	0.235	/* of it: 4/17, apex to base */
#define NS_SCROLLER_BAR_RADIUS		3.0	/* ONE radius, used three times: the knob and both buttons */
#define NS_SCROLLER_GRIP_RADIUS		2.0	/* the knob's dimples — three of them, down its centre */
#define NS_SCROLLER_GRIP_SPACING	8.0	/* centre to centre, which is what makes them read as a grip */

/* **A HELD PAGE REPEATS, AND THESE TWO NUMBERS ARE THE FEEL OF IT.** The first repeat waits out a hand that meant ONE
 * page; after that the steps come fast enough to read as motion. Both belong to the CELL rather than to the tracking
 * loop, so the loop never learns one control's timing — it only asks whether the cell has something more to say. */
#define NS_SCROLLER_REPEAT_DELAY	0.35
#define NS_SCROLLER_REPEAT_INTERVAL	0.05

@implementation NSScrollerCell

/* ============================================================================================
 * ARCHIVING: THE KNOB'S VALUE AND ITS SHARE, NOT THE DRAG.
 * ============================================================================================ */
/* **A DRAG IN PROGRESS IS NOT A DESIGN.** `_hitPart`, `_grabDelta`, `_lastFrame` and `_repeatDeadline` are the state of a
 * tracked knob and a decoded cell has never been touched; what a file can say is where the knob sits and how much of the
 * track it takes. `_arrowsPosition` is a look, so it is here too. */
static NSString * const AGCoderScrollerValueKey = @"floatValue";
static NSString * const AGCoderScrollerProportionKey = @"knobProportion";
static NSString * const AGCoderScrollerArrowsKey = @"arrowsPosition";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeDouble:_floatValue forKey:AGCoderScrollerValueKey];
	[aCoder encodeDouble:_knobProportion forKey:AGCoderScrollerProportionKey];
	[aCoder encodeInteger:(NSInteger)_arrowsPosition forKey:AGCoderScrollerArrowsKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderScrollerValueKey]) {
		_floatValue = [aDecoder decodeDoubleForKey:AGCoderScrollerValueKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollerProportionKey]) {
		_knobProportion = [aDecoder decodeDoubleForKey:AGCoderScrollerProportionKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollerArrowsKey]) {
		_arrowsPosition = [aDecoder decodeIntegerForKey:AGCoderScrollerArrowsKey];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


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

/* **EVERY PIECE OF THIS BAR IS A RECTANGLE, ROUNDED OR SQUARE, AND THE GRIP IS THREE RINGS.** The sample is a
 * bitmap exported from Affinity Designer, so its edges are the EXPORT's rather than the design's and cannot be asked
 * how sharp anything should be; what it settles is the SHAPE LANGUAGE — a rounded knob and rounded arrow buttons, a
 * SQUARE groove for them to sit in, and three rings down the knob's centre. EVERY PIECE OF IT IS A SHAPE, the arrow
 * included — and the arrow is the one place antialiasing is turned OFF, which `-drawArrow:` argues. */
static void fn_draw_grip(NSRect knob, BOOL horizontal)
{
	CGFloat radius = NS_SCROLLER_GRIP_RADIUS;
	CGFloat spacing = NS_SCROLLER_GRIP_SPACING;
	CGFloat length = horizontal ? NSWidth(knob) : NSHeight(knob);
	CGFloat cx;
	CGFloat cy;
	int i;

	/* NOTHING TO HOLD: a knob with no room for the three would be all grip and no knob. */
	if (length < 2.0 * spacing + 4.0 * radius) {
		return;
	}
	cx = floor(NSMidX(knob)) + 0.5;
	cy = floor(NSMidY(knob)) + 0.5;
	/* **THREE RINGS, WHICH IS THE WHOLE GRIP.** The sample's dimple is HOLLOW — its darkest value is 188 and its middle
	 * is 255 — so what shows through the centre of each is the knob's OWN white rather than a fifth grey. A filled dot
	 * would be the simpler mark and would lose exactly the thing the sample is drawing. */
	[[NSColor controlDarkShadowColor] setStroke];
	for (i = -1; i <= 1; i++) {
		NSBezierPath *ring;
		NSRect dot;

		if (horizontal) {
			dot = NSMakeRect(cx + i * spacing - radius, cy - radius, 2.0 * radius, 2.0 * radius);
		} else {
			dot = NSMakeRect(cx - radius, cy + i * spacing - radius, 2.0 * radius, 2.0 * radius);
		}
		ring = [NSBezierPath bezierPathWithOvalInRect:dot];
		[ring setLineWidth:1.0];
		[ring stroke];
	}
}

/* ONE ARROW, POINTING THE WAY ITS PART SCROLLS. The decrement arrow points to the smaller values — up in a vertical
 * scroller, left in a horizontal one — which in a flipped view is the smaller y or x, so no flip arithmetic is
 * needed here: the coordinates are already the reader's. */
- (void)drawArrow:(NSScrollerArrow)whichArrow highlight:(BOOL)flag
{
	NSRect r = [self rectForPart:(whichArrow == NSScrollerDecrementArrow) ? NSScrollerDecrementLine
									     : NSScrollerIncrementLine];
	BOOL decrement = (whichArrow == NSScrollerDecrementArrow);
	BOOL horizontal = [self fn_horizontalInFrame:[self cg_frame]];
	NSBezierPath *button;
	NSBezierPath *p;
	CGFloat side;
	CGFloat half;
	CGFloat height;
	CGFloat cx;
	CGFloat cy;

	if (r.size.width <= 0.0 || r.size.height <= 0.0) {
		return;
	}
	/* **THE BUTTON'S FACE, AND IT IS THE ONE THING A PRESS MOVES.** The sample's ink for an arrow is pure black — there
	 * is nothing darker for a press to go to — so the press has to be said by the GROUND, which is also the order the
	 * two are painted in: the face first, the glyph on top of it. */
	button = [NSBezierPath bezierPathWithRoundedRect:r xRadius:NS_SCROLLER_BAR_RADIUS
						 yRadius:NS_SCROLLER_BAR_RADIUS];
	if (flag && [self isEnabled]) {
		[[NSColor controlShadowColor] setFill];
	} else {
		[[NSColor controlBackgroundColor] setFill];
	}
	/* **AND IT IS STROKED, BECAUSE ITS FACE IS THE FRAME'S OWN WHITE.** An unoutlined rounded corner on a white
	 * ground is a corner nobody can see, so the button states its shape the way the knob does. */
	[button fill];
	[[NSColor controlDarkShadowColor] setStroke];
	[button setLineWidth:1.0];
	[button stroke];

	/* **THE GLYPH IS A PATH, AND THE SHAPE IS THE SAMPLE'S RATHER THAN A BOX.** It is a triangle WIDER THAN IT IS
	 * TALL — 6 points across and 4 tall on the sample's 17-point bar — and a path is what that needs: a staircase has
	 * to choose its steps out of the width it is handed, where a path is re-solved at whatever size it is asked for.
	 * That is what gives the 11-point small-control-size bar an arrow of its own instead of a shrunken 15-point one.
	 *
	 * IT WAS RASTERIZED FOR AS LONG AS `cg_sweep` FILLED A TRAPEZOID'S TOP EDGE AT THE WIDTH OF ITS BAND'S MIDDLE,
	 * which drew every triangle wrong at every size — a 16-point base came out with a missing apex. That is fixed in
	 * libagora-drawing, so the shape is back.
	 *
	 * **AND IT IS FILLED WITH ANTIALIASING OFF, WHICH IS THE ONE THING THE RASTERIZATION WAS ALSO BUYING.** A triangle
	 * this small is almost entirely edge, so a blended fill reads as GREY rather than as ink — "mushy" was the word for
	 * it. Turning it off leaves the seam where the filler puts it, and the filler is right now: the arrow is HARD-edged
	 * without being a staircase. The state is saved and restored rather than left off, because the button behind it and
	 * the knob after it are curves that want the antialiasing this does not.
	 *
	 * THE INK IS BLACK AND DOES NOT CHANGE WITH THE PRESS: the press is already said by the button's face darkening
	 * above, and a glyph that also dimmed would be two answers to one question. */
	side = (NSWidth(r) < NSHeight(r)) ? NSWidth(r) : NSHeight(r);
	half = side * NS_SCROLLER_ARROW_HALF;
	height = side * NS_SCROLLER_ARROW_HEIGHT;
	if (half < 1.0 || height < 1.0) {
		return;
	}
	/* HALF-POINT CENTRES, so the apex is ONE point rather than a two-point flat. */
	cx = floor(NSMidX(r)) + 0.5;
	cy = floor(NSMidY(r)) + 0.5;
	p = [NSBezierPath bezierPath];
	if (!horizontal) {
		CGFloat apex = decrement ? (cy - height / 2.0) : (cy + height / 2.0);
		CGFloat base = decrement ? (cy + height / 2.0) : (cy - height / 2.0);

		[p moveToPoint:NSMakePoint(cx, apex)];
		[p lineToPoint:NSMakePoint(cx + half, base)];
		[p lineToPoint:NSMakePoint(cx - half, base)];
	} else {
		CGFloat apex = decrement ? (cx - height / 2.0) : (cx + height / 2.0);
		CGFloat base = decrement ? (cx + height / 2.0) : (cx - height / 2.0);

		[p moveToPoint:NSMakePoint(apex, cy)];
		[p lineToPoint:NSMakePoint(base, cy + half)];
		[p lineToPoint:NSMakePoint(base, cy - half)];
	}
	[p closePath];
	{
		CGContextRef c = [[NSGraphicsContext currentContext] CGContext];

		if (c == NULL) {
			return;
		}
		CGContextSaveGState(c);
		CGContextSetShouldAntialias(c, false);
		[[NSColor blackColor] setFill];
		[p fill];
		CGContextRestoreGState(c);
	}
}
- (void)drawKnob
{
	NSRect r = [self rectForPart:NSScrollerKnob];
	NSBezierPath *p;

	if (r.size.width <= 0.0 || r.size.height <= 0.0) {
		return;
	}
	p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:NS_SCROLLER_BAR_RADIUS
					    yRadius:NS_SCROLLER_BAR_RADIUS];
	/* **THE KNOB IS THE BRIGHTEST THING ON THE BAR, AND THAT IS THE SAMPLE'S ONE INVERSION OF THE USUAL ARRANGEMENT.**
	 * Everywhere else a raised thing is lighter than the window under it; here the ground is the GROOVE, so the knob
	 * takes the white and the groove takes the grey. A DISABLED SCROLLER STILL DRAWS ITS KNOB — the position is still
	 * worth showing, it simply stops claiming to be grabbable. **AND A DRAGGED KNOB KEEPS ITS FILL.** The handle is
	 * already the thing the hand is holding and the pointer is the feedback; recolouring it as well says the knob has
	 * become a different object rather than that it is being moved. */
	if (![self isEnabled]) {
		[[NSColor controlBackgroundColor] setFill];
		/* **AND A DISABLED KNOB'S OUTLINE IS NOW A STEP THIS FILE HAS TO ASK FOR BY NAME.** It was
		 * `+controlDarkShadowColor`, which was the darker of the pair; that colour is now 0.737 — the sample's border
		 * grey, and the same grey an ENABLED knob's outline takes — so leaving this line alone would have made a
		 * disabled scroller EXACTLY the enabled one, which is the sort of thing a palette change does quietly.
		 * `+controlShadowColor`'s 0.60 is the next grey down, so the RELATIONSHIP is the one it always was: a knob
		 * that has stopped claiming to be grabbable says so with a heavier edge. */
		[[NSColor controlShadowColor] setStroke];
	} else {
		[[NSColor controlBackgroundColor] setFill];
		[[NSColor controlDarkShadowColor] setStroke];
	}
	[p fill];
	[p stroke];
	fn_draw_grip(r, [self fn_horizontalInFrame:[self cg_frame]]);
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
	(void)flag;
	if (slotRect.size.width <= 0.0 || slotRect.size.height <= 0.0) {
		return;
	}
	/* **THE SLOT IS THE RECESS, SO IT IS DRAWN FIRST AND UNDER EVERYTHING.** The arrows are then drawn on top of it,
	 * and the knob last of all — which is the order a raised knob over a hollow groove reads as. **AND IT IS A SQUARE
	 * RECTANGLE**, the one piece of this bar that is: the knob and the two buttons are rounded because they are things
	 * the pointer can take hold of, and the groove is the hole they sit in. */
	[[NSColor cg_scrollerTrackColor] setFill];
	[[NSBezierPath bezierPathWithRect:slotRect] fill];
	if (_arrowsPosition != NSScrollerArrowsNone) {
		[self drawArrow:NSScrollerDecrementArrow highlight:NO];
		[self drawArrow:NSScrollerIncrementArrow highlight:NO];
	}
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	(void)controlView;
	/* **THE FRAME IS THE ARROW BUTTONS' FACE, AND THE GROOVE IS PAINTED OVER IT.** The whole frame takes the buttons'
	 * white first, so the two ends and the bar read as ONE control; `-drawKnobSlotInRect:` then lays the groove into the
	 * middle of it, and each arrow repaints its own button on top of that — which is also what lets a press darken just
	 * the one button it landed on. */
	_lastFrame = cellFrame;
	[[NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:cellFrame] fill];
	[self drawKnobSlotInRect:[self rectForPart:NSScrollerKnobSlot] highlight:[self isHighlighted]];
	[self drawKnob];
}

@end
