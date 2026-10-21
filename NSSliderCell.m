/*
 * NSSliderCell — a slider's range, value, geometry and ink.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * **THE CELL IS WHERE "WHAT VALUE IS THIS POINT" LIVES, AND THAT IS THE WHOLE SHAPE OF THIS FILE.** Everything else
 * is derived from the value and the range: the knob's rectangle (a fraction along the travel), the track (the middle
 * of the frame), and the ticks (even fractions across it). The tracking is the CONTROL's loop; this cell is the thing
 * that loop asks, through the two hooks `NSCell` already declares.
 *
 * AND THE GEOMETRY IS MEASURED FROM THE KNOB'S CENTRE RATHER THAN ITS EDGE, which is what makes
 * `-knobRect:flipped:` and `-cg_valueAtPoint:inRect:flipped:` exact inverses: the value that puts the knob at a
 * place is the value that place answers, so a press on the knob moves nothing. Every other choice — measuring from
 * the frame's edge, or from the knob's edge — leaves a slider whose knob jumps when it is grabbed, which is the bug
 * this paragraph exists to not have.
 */
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphics.h>
#import <Foundation/NSGeometry.h>

#include <math.h>

/* THE NUMBERS THE FACE IS BUILT FROM, named rather than repeated inline.
 *
 * **AND THE GRABBER HAS TWO OF THEM BECAUSE A TEARDROP IS NOT SQUARE.** `LENGTH` is the grabber's extent ALONG the
 * track — ITS WIDTH, on the slider this face is drawn for — and it is the one the arithmetic knows about: the travel
 * is the frame's length less this, and both `-knobRect:flipped:` and `-cg_valueAtPoint:inRect:flipped:` measure the
 * grabber's CENTRE from it, which is what makes them exact inverses. SO IT IS ALSO THE LEVER FOR "MAKE IT NARROWER",
 * and narrowing it moves the travel by exactly as much — which is CORRECT rather than a side effect: a narrower
 * grabber really can slide a little further along its track, because what was stopping it was its own width.
 *
 * `BREADTH` IS THE EXTENT ACROSS THE TRACK — the grabber's height on a horizontal slider and its width on a vertical
 * one — and it is a drawing measure only: making the grabber TALLER moved no value at all, because the tracking never
 * asks about this axis. */
#define NS_SLIDER_KNOB_LENGTH		12.0
#define NS_SLIDER_KNOB_BREADTH		18.0
#define NS_SLIDER_TRACK_THICKNESS	4.0
#define NS_SLIDER_TRACK_INSET		6.0
/* **THE CHANNEL'S CORNERS ARE THE PLATFORM'S CORNERS, AND ITS OWN THICKNESS IS THE ONLY THING THAT CAPS THEM.** It
 * is `NS_CELL_BEZEL_RADIUS` for the reason the checkbox's box is: a slider's channel and a button's bezel are the
 * same kind of corner, and a platform whose ONE radius is four should not have a control quietly rounding at two.
 * `NSBezierPath` clamps a corner PER AXIS to half the rectangle, so a channel four points thick keeps the full four
 * along its length and takes two across — the end eases over four points instead of two, which is the most a
 * channel this thin can round and still be the platform's radius. ONE DEFINITION, because the track and the accent
 * fill that covers part of it must round ALIKE, or the fill's end shows through the track's own curve. */
#define NS_SLIDER_TRACK_RADIUS		NS_CELL_BEZEL_RADIUS

/* **AND THE SHAPE'S CONSTANTS. THE GRABBER IS A TEARDROP — ROUND AT THE TOP AND NARROW AT THE BOTTOM — AND THE
 * QUESTION THAT DECIDED THE REST OF THEM IS HOW THE SIDES MEET THE NARROW END.**
 *
 * `TIP_RADIUS` is the narrow cap's radius as a FRACTION of the shape's width, so the narrow end scales with the
 * control instead of being a fixed number of points that would pinch a wide grabber and swallow a narrow one.
 *
 * `TIP_ANGLE` IS THE ONE THAT MATTERS, AND IT IS THE FIX FOR SIDES THAT TURNED CONCAVE. A cap drawn as a SEMICIRCLE
 * meets its sides with a VERTICAL tangent — and so does the wide cap, at the other end — and a cubic whose two end
 * tangents are both vertical IS AN S-SHAPED CURVE: it is concave in one half and convex in the other, no matter where
 * its control points go. MEASURED, that is what the grabber's sides did: they bowed INWARD by about 0.7 of a point
 * just above the narrow end, which is the "neck" a person sees. SO THE NARROW CAP IS AN ARC OF `TIP_ANGLE` EITHER SIDE
 * OF THE BOTTOM RATHER THAN A SEMICIRCLE, which lets the sides leave it at an angle and bow outward all the way up.
 *
 * `ARC_K` is the constant that makes a cubic BÉZIER SIT ON A CIRCLE: it is `(4/3)·tan(90°/4)`, which is exactly the
 * control length a quarter-turn arc wants, and every rounded part here is built from that same rule at its own angle.
 * And `SIDE_BOW` is how much of the available bow the sides actually use — a fraction rather than the maximum,
 * because the maximum is where the curve's control polygon is about to fold and a shape drawn at the limit has its
 * curvature bunched at the joins. */
#define NS_SLIDER_KNOB_TIP_RADIUS	0.22
#define NS_SLIDER_KNOB_TIP_ANGLE	55.0	/* degrees, either side of the bottom */
#define NS_SLIDER_KNOB_ARC_K		0.5523
#define NS_SLIDER_KNOB_SIDE_BOW		0.6	/* of the bow that would just keep the side convex */
#define FN_KNOB_PI			3.14159265358979323846

@implementation NSSliderCell

/* ============================================================================================
 * ARCHIVING: THE RANGE, THE VALUE AND THE TICKS.
 * ============================================================================================ */
/* **`_vertical` IS DERIVED AND IS THEREFORE ABSENT.** A slider's orientation is a fact about the FRAME it is drawn in —
 * a taller-than-wide slider is vertical — so archiving the flag as well would let a file contradict its own geometry, and
 * the decoder would have to choose which one it believed. The range, the value, the tick marks and the increment are
 * what a design actually says. */
static NSString * const AGCoderSliderMinKey = @"minValue";
static NSString * const AGCoderSliderMaxKey = @"maxValue";
static NSString * const AGCoderSliderValueKey = @"sliderValue";
static NSString * const AGCoderSliderTypeKey = @"sliderType";
static NSString * const AGCoderSliderTicksKey = @"numberOfTickMarks";
static NSString * const AGCoderSliderTickPositionKey = @"tickMarkPosition";
static NSString * const AGCoderSliderAltIncrementKey = @"altIncrementValue";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeDouble:_minValue forKey:AGCoderSliderMinKey];
	[aCoder encodeDouble:_maxValue forKey:AGCoderSliderMaxKey];
	[aCoder encodeDouble:_sliderValue forKey:AGCoderSliderValueKey];
	[aCoder encodeInteger:(NSInteger)_sliderType forKey:AGCoderSliderTypeKey];
	[aCoder encodeInteger:_numberOfTickMarks forKey:AGCoderSliderTicksKey];
	[aCoder encodeInteger:(NSInteger)_tickMarkPosition forKey:AGCoderSliderTickPositionKey];
	[aCoder encodeDouble:_altIncrementValue forKey:AGCoderSliderAltIncrementKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderSliderMinKey]) {
		_minValue = [aDecoder decodeDoubleForKey:AGCoderSliderMinKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderMaxKey]) {
		_maxValue = [aDecoder decodeDoubleForKey:AGCoderSliderMaxKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderValueKey]) {
		_sliderValue = [aDecoder decodeDoubleForKey:AGCoderSliderValueKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderTypeKey]) {
		_sliderType = [aDecoder decodeIntegerForKey:AGCoderSliderTypeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderTicksKey]) {
		_numberOfTickMarks = [aDecoder decodeIntegerForKey:AGCoderSliderTicksKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderTickPositionKey]) {
		_tickMarkPosition = [aDecoder decodeIntegerForKey:AGCoderSliderTickPositionKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderAltIncrementKey]) {
		_altIncrementValue = [aDecoder decodeDoubleForKey:AGCoderSliderAltIncrementKey];
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
		/* **THE RANGE APPLE DOCUMENTS AS THE DEFAULT IS 0…1**, and the value starts at the minimum rather than at
		 * the middle: a slider's value is a number the caller set, and a cell that invented one would be answering
		 * before it was told. */
		_minValue = 0.0;
		_maxValue = 1.0;
		_sliderValue = 0.0;
		_vertical = NO;
		_sliderType = NSLinearSlider;
		_numberOfTickMarks = 0;
		_tickMarkPosition = NSTickMarkBelow;
		_altIncrementValue = 0.0;
		/* **AND THE ONE PLACE THIS CELL DEPARTS FROM `NSCell`'S ZEROED `-isContinuous`: A SLIDER IS CONTINUOUS BY
		 * DEFAULT.** The ground is the tracking loop's own shape — a slider's value is set BY the pointer, and a value
		 * that only SPOKE when the button came up is a value the caller cannot watch move, which is the whole point of
		 * a slider over a text field. It is also what lets a drag that ends past the end still speak its clamped final
		 * value (§A10cc): a continuous cell sends on every point including the release, so where the button came up
		 * stops mattering, while a caller who turns the flag off gets the button's one-shot release semantics back. */
		_continuous = YES;
	}
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

/* ---- THE RANGE, AND THE RE-CLAMP MOVING AN END OWES ------------------------------------------------------------ */

- (double)minValue
{
	return _minValue;
}

- (void)setMinValue:(double)aDouble
{
	_minValue = aDouble;
	/* **MOVING AN END MOVES THE VALUE ONLY IF IT HAS TO**, and the clamp is not decoration: `-doubleValue` is the
	 * number the knob is placed from, and a value below the minimum is a knob outside its own track. */
	if (_maxValue < _minValue) {
		_maxValue = _minValue;
	}
	[self setDoubleValue:_sliderValue];
}

- (double)maxValue
{
	return _maxValue;
}

- (void)setMaxValue:(double)aDouble
{
	_maxValue = aDouble;
	if (_minValue > _maxValue) {
		_minValue = _maxValue;
	}
	[self setDoubleValue:_sliderValue];
}

/* ---- AND THE VALUE, IN FIVE SHAPES, EVERY SETTER WRITING THE ONE NUMBER ---------------------------------------- */

- (double)doubleValue
{
	return _sliderValue;
}

- (void)setDoubleValue:(double)aDouble
{
	double clamped = aDouble;

	/* THE CLAMP IS WHERE A VALUE OUTSIDE THE RANGE STOPS, so the four narrower setters below can all funnel here
	 * rather than each clamping in its own way. A NAN IS NOT CLAMPED BY COMPARISON — `NaN < lo` and `NaN > hi` are
	 * both false — so it is caught first and pinned to the minimum, which keeps `-doubleValue` a number the knob can
	 * be placed at. */
	if (clamped != clamped) {
		clamped = _minValue;
	}
	if (clamped < _minValue) {
		clamped = _minValue;
	}
	if (clamped > _maxValue) {
		clamped = _maxValue;
	}
	if (clamped != _sliderValue) {
		_sliderValue = clamped;
		/* **AND THE CONTROL IS MARKED, WHICH IS THE ONE THING A CELL OWES A VIEW IT CHANGED THE FACE OF.** The
		 * cell knows its control view (§A10cc's `-controlView`), so a value that moves the knob is a value that
		 * repaints, and the tracking loop only has to pump events. */
		[(NSView *)[self controlView] setNeedsDisplay:YES];
	}
}

- (float)floatValue
{
	return (float)_sliderValue;
}

- (void)setFloatValue:(float)aFloat
{
	[self setDoubleValue:(double)aFloat];
}

- (int)intValue
{
	return (int)_sliderValue;
}

- (void)setIntValue:(int)anInt
{
	[self setDoubleValue:(double)anInt];
}

- (NSInteger)integerValue
{
	return (NSInteger)_sliderValue;
}

- (void)setIntegerValue:(NSInteger)anInteger
{
	[self setDoubleValue:(double)anInteger];
}

/* ---- THE FACE'S FOUR PROPERTIES, AND THE ALTERNATE INCREMENT ---------------------------------------------------- */

- (double)altIncrementValue
{
	return _altIncrementValue;
}

- (void)setAltIncrementValue:(double)increment
{
	_altIncrementValue = increment;
}

- (BOOL)isVertical
{
	return _vertical;
}

- (void)setVertical:(BOOL)flag
{
	_vertical = flag;
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (NSSliderType)sliderType
{
	return _sliderType;
}

- (void)setSliderType:(NSSliderType)aType
{
	_sliderType = aType;
	/* APPKIT-REFUSE: `NSCircularSlider` names a face this tier does not draw. The VALUE is stored and answered — a
	 * caller's setting is never lost — but the ink below is the linear one, and saying so here is the difference
	 * between a door that has a far side and a door that quietly draws the wrong thing. */
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (NSInteger)numberOfTickMarks
{
	return _numberOfTickMarks;
}

- (void)setNumberOfTickMarks:(NSInteger)count
{
	_numberOfTickMarks = count;
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (NSTickMarkPosition)tickMarkPosition
{
	return _tickMarkPosition;
}

- (void)setTickMarkPosition:(NSTickMarkPosition)position
{
	_tickMarkPosition = position;
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

/* ---- AND THE GEOMETRY: TWO DOORS THAT ARE EXACT INVERSES ------------------------------------------------------- */

/* The value as a FRACTION of the range, which is the shape both geometric doors work in. A degenerate range — a
 * minimum equal to its maximum — has one answer rather than a division by zero: the knob sits at the start. */
- (CGFloat)cg_fraction
{
	double span = _maxValue - _minValue;

	if (span == 0.0) {
		return 0.0;
	}
	return (CGFloat)((_sliderValue - _minValue) / span);
}

/* **THE GRABBER'S EXTENT ALONG THE TRACK, WHICH FOLLOWS ITS SHAPE RATHER THAN BEING ONE NUMBER.** The grabber's
 * rectangle IS the shape's bounding box — `fn_knob_path` says so and the two cannot drift apart — and the two shapes
 * are NOT the same size: the teardrop is `LENGTH` wide and `BREADTH` tall, while the CIRCLE is `BREADTH` across and
 * needs a box to match. So a slider with no tick marks has a grabber `BREADTH` long along its track and one with tick
 * marks has a grabber `LENGTH` long.
 *
 * AND THE TRAVEL FOLLOWS, because the travel is the frame's length less THIS — which is the correct consequence
 * rather than a side effect: a bigger grabber really can slide less far, since what stops it at either end is its own
 * width. IT IS ALSO THE ONE THING THAT MAKES THE CIRCULAR GRABBER BIGGER: `min(width, height) / 2` is the radius both
 * shapes use, so giving the circle a square box is what turns its radius from half the teardrop's width into
 * `BREADTH / 2` — half again as big. */
- (CGFloat)fn_grabberAlong
{
	return (_numberOfTickMarks > 0) ? NS_SLIDER_KNOB_LENGTH : NS_SLIDER_KNOB_BREADTH;
}

- (NSRect)knobRect:(NSRect)cellFrame flipped:(BOOL)isFlipped
{
	CGFloat fraction = [self cg_fraction];
	CGFloat along = [self fn_grabberAlong];	/* along the track: the dimension the tracking is built on */
	CGFloat across = NS_SLIDER_KNOB_BREADTH;	/* across it: the teardrop's height */
	NSRect knob;

	/* **THE KNOB IS ELONGATED ACROSS THE TRACK, WHICH IS WHAT MAKES THE GRABBER TALL.** The travel still runs along
	 * the frame's long side and is still measured against `LENGTH`, so nothing about the value mapping moved when
	 * `BREADTH` grew — only the shape did. THE TWO DIMENSIONS ARE SWAPPED BETWEEN THE ORIENTATIONS rather than
	 * rotated: `along` is always the track's direction and `across` is always perpendicular to it, so a horizontal
	 * slider gets a taller-than-wide grabber and a vertical one a wider-than-tall one. The SHAPE keeps its own axis
	 * vertical either way (round end up), which is what `-drawKnob:` is for. */
	if (_vertical) {
		CGFloat travel = NSHeight(cellFrame) - along;
		CGFloat y;

		if (travel < 0.0) {
			travel = 0.0;
		}
		/* THE MINIMUM IS AT THE BOTTOM, and "bottom" is a different y in a flipped view (§A10aw): a flipped view
		 * counts downward from its origin, so the value that ends at the frame's TOP edge is `fraction == 1.0`. */
		y = isFlipped ? (NSMinY(cellFrame) + (1.0 - fraction) * travel)
			      : (NSMinY(cellFrame) + fraction * travel);
		knob = NSMakeRect(NSMidX(cellFrame) - across / 2.0, y, across, along);
	} else {
		CGFloat travel = NSWidth(cellFrame) - along;
		CGFloat x;

		if (travel < 0.0) {
			travel = 0.0;
		}
		x = NSMinX(cellFrame) + fraction * travel;
		knob = NSMakeRect(x, NSMidY(cellFrame) - across / 2.0, along, across);
	}
	return knob;
}

- (double)cg_valueAtPoint:(NSPoint)aPoint inRect:(NSRect)cellFrame flipped:(BOOL)isFlipped
{
	double span = _maxValue - _minValue;
	CGFloat along = [self fn_grabberAlong];
	CGFloat travel = (_vertical ? NSHeight(cellFrame) : NSWidth(cellFrame)) - along;
	CGFloat fraction;

	if (travel <= 0.0) {
		/* A frame too small to hold the knob has ONE position, and answering the minimum rather than dividing by a
		 * non-positive travel is the difference between a slider and a crash. */
		return _minValue;
	}
	if (_vertical) {
		/* The centre of the knob's travel, which is `along / 2` in from the TOP end — the same measurement
		 * `-knobRect:flipped:` makes, read backwards. In a flipped view the top end is the frame's origin. */
		CGFloat top = isFlipped ? NSMinY(cellFrame) : NSMaxY(cellFrame);
		CGFloat offset = isFlipped ? (aPoint.y - (top + along / 2.0))
					   : ((top - along / 2.0) - aPoint.y);
		fraction = offset / travel;
	} else {
		fraction = (aPoint.x - (NSMinX(cellFrame) + along / 2.0)) / travel;
	}
	if (fraction < 0.0) {
		fraction = 0.0;
	}
	if (fraction > 1.0) {
		fraction = 1.0;
	}
	return _minValue + (double)fraction * span;
}

/* ---- AND THE TRACKING HOOKS, WHICH ARE WHAT MAKES THE VALUE FOLLOW THE POINTER --------------------------------- */

/* **THE TWO HOOKS ARE THE CELL'S HALF OF THE CONTROL'S LOOP, AND THEY BOTH ANSWER YES.** A press sets the value on
 * the point it landed on — a slider's knob JUMPS to a click rather than waiting for a drag — and every point after it
 * does the same. The yes/no an unmodified `NSCell` computes here is a statement about DRAGS (§A10bq), and a slider
 * dragged off and back is still a slider being dragged, so this cell answers the question its own way. */
- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	[self setDoubleValue:[self cg_valueAtPoint:startPoint
					    inRect:[controlView bounds]
					   flipped:[controlView isFlipped]]];
	return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
	[self setDoubleValue:[self cg_valueAtPoint:currentPoint
					    inRect:[controlView bounds]
					   flipped:[controlView isFlipped]]];
	return YES;
}

/* ---- AND THE INK ---------------------------------------------------------------------------------------------- */

/* **THE TICKS ARE THE ONE PART OF THE FACE THE FRAME'S FLIP ACTUALLY CHANGES**, because "above" is a direction and a
 * direction is what a flipped view reverses. The two numbers below are the track's half thickness and the tick's
 * length, and the sign is the flip: a tick drawn "above" grows toward the top, which is a DECREASING y in a flipped
 * view and an increasing one otherwise. */
/* **AND THE TICKS' TWO MEASURES, EACH TAKEN FROM SOMETHING RATHER THAN CHOSEN FROM NOTHING.** A tick begins just
 * clear of the TRACK and ends just clear of the GRABBER — `BREADTH / 2` is exactly where the grabber's outline is —
 * which is the whole reason to have them: a scale that stops inside the grabber is a scale only the gaps between
 * values can show. MEASURING THE FAR END FROM THE GRABBER IS THE POINT: a fixed length would be swallowed whole by a
 * tall grabber and would dwarf a short one, whereas `PEEK` is the same few points of line below the grabber's edge
 * whatever size that grabber is. */
#define NS_SLIDER_TICK_INSET		1.0
#define NS_SLIDER_TICK_PEEK		3.0

- (void)cg_drawTickMarks:(NSRect)cellFrame flipped:(BOOL)flipped
{
	NSInteger i;
	CGFloat travel = (_vertical ? NSHeight(cellFrame) : NSWidth(cellFrame)) - [self fn_grabberAlong];
	CGFloat dir = flipped ? -1.0 : 1.0;
	/* **AND THE REACH IS CLAMPED TO THE FRAME, because a cell only owns the rectangle it was given.** A frame too
	 * short for the grabber plus its peek draws the tick out to the frame's edge instead of below it, which is the
	 * most a tick can honestly do — the alternative is ink outside the cell, on whatever is next to it. */
	CGFloat cross = (_vertical ? NSWidth(cellFrame) : NSHeight(cellFrame)) / 2.0;
	CGFloat in0 = NS_SLIDER_TRACK_THICKNESS / 2.0 + NS_SLIDER_TICK_INSET;
	CGFloat out0 = NS_SLIDER_KNOB_BREADTH / 2.0 + NS_SLIDER_TICK_PEEK;
	CGFloat inner, outer;

	if (_numberOfTickMarks <= 0 || travel <= 0.0) {
		return;
	}
	if (out0 > cross) {
		out0 = cross;
	}
	if (out0 < in0) {
		out0 = in0;	/* a frame thinner than the track keeps the tick's own start rather than inverting it */
	}
	if (_tickMarkPosition == NSTickMarkAbove) {
		inner = dir * in0;
		outer = dir * out0;
	} else {
		inner = -dir * in0;
		outer = -dir * out0;
	}
	[[NSColor controlDarkShadowColor] setFill];
	for (i = 0; i < _numberOfTickMarks; i++) {
		CGFloat fraction = (_numberOfTickMarks == 1) ? 0.0
				   : (CGFloat)i / (CGFloat)(_numberOfTickMarks - 1);
		CGFloat lo = (inner < outer) ? inner : outer;
		CGFloat len = (outer > inner) ? (outer - inner) : (inner - outer);
		NSRect tick;

		if (_vertical) {
			CGFloat y = NSMinY(cellFrame) + [self fn_grabberAlong] / 2.0 + fraction * travel;

			tick = NSMakeRect(NSMidX(cellFrame) + lo, y - 0.5, len, 1.0);
		} else {
			CGFloat x = NSMinX(cellFrame) + [self fn_grabberAlong] / 2.0 + fraction * travel;

			tick = NSMakeRect(x - 0.5, NSMidY(cellFrame) + lo, 1.0, len);
		}
		[[NSBezierPath bezierPathWithRect:tick] fill];
	}
}

- (void)drawBarInside:(NSRect)cellFrame flipped:(BOOL)flipped
{
	NSRect track;
	NSRect filled;
	NSRect knob;

	if (_vertical) {
		track = NSMakeRect(NSMidX(cellFrame) - NS_SLIDER_TRACK_THICKNESS / 2.0,
				   NSMinY(cellFrame) + NS_SLIDER_TRACK_INSET,
				   NS_SLIDER_TRACK_THICKNESS,
				   NSHeight(cellFrame) - 2.0 * NS_SLIDER_TRACK_INSET);
	} else {
		track = NSMakeRect(NSMinX(cellFrame),
				   NSMidY(cellFrame) - NS_SLIDER_TRACK_THICKNESS / 2.0,
				   NSWidth(cellFrame),
				   NS_SLIDER_TRACK_THICKNESS);
	}
	[[NSColor controlDarkShadowColor] setFill];
	[[NSBezierPath bezierPathWithRoundedRect:track xRadius:NS_SLIDER_TRACK_RADIUS
					  yRadius:NS_SLIDER_TRACK_RADIUS] fill];

	/* **AND THE STRETCH THE VALUE HAS ALREADY COVERED IS FILLED WITH THE PLATFORM'S ACCENT.** A slider's whole job is to
	 * say where a number is between two ends, and a bare track says only where the grabber ended up; the filled part
	 * says how far the value has come, which is the same fact read from the other end.
	 *
	 * THE FILL RUNS TO THE GRABBER'S CENTRE RATHER THAN TO ITS EDGE. The grabber is drawn over this a moment later, so
	 * its centre is half its length INSIDE its own outline — reaching past that would put accent ink in the gap on the
	 * far side of it, and stopping short of it would leave a sliver of bare track the grabber does not cover. Stopping
	 * at the centre is what makes the fill look like it comes out from UNDER the grabber.
	 *
	 * AND THE MINIMUM END IS NOT THE LEFT-HAND ONE IN EVERY ORIENTATION: a flipped view counts y downward, and the
	 * arithmetic in `-knobRect:flipped:` puts the minimum at the TOP there — so the fill is measured from that end of
	 * the TRACK, which is why it asks the track's own rectangle rather than the cell's. The horizontal case needs no
	 * such care: `-knobRect:flipped:` places the minimum at the left edge whichever way the view counts. */
	filled = track;
	knob = [self knobRect:cellFrame flipped:flipped];
	if (_vertical) {
		CGFloat chest = NSMidY(knob);	/* the grabber's centre, along the track */

		if (flipped) {
			filled.origin.y = chest;
			filled.size.height = NSMaxY(track) - chest;
		} else {
			filled.origin.y = NSMinY(track);
			filled.size.height = chest - NSMinY(track);
		}
	} else {
		filled.size.width = NSMidX(knob) - NSMinX(track);
	}
	if (filled.size.width > 0.0 && filled.size.height > 0.0) {
		/* **THE SAME `NSColor cg_accentColor` THE MENU'S SELECTION AND A PRESSED BUTTON WEAR**, so the platform has ONE
		 * accent rather than a slider's that happens to look like the menu's. A DISABLED slider gets the same fill in
		 * `controlShadowColor`: the value is still worth showing — which is the reading its grabber takes too, drawn
		 * rather than absent — it simply stops claiming to be the live accent. */
		if ([self isEnabled]) {
			[[NSColor cg_accentColor] setFill];
		} else {
			[[NSColor controlShadowColor] setFill];
		}
		[[NSBezierPath bezierPathWithRoundedRect:filled xRadius:NS_SLIDER_TRACK_RADIUS
						  yRadius:NS_SLIDER_TRACK_RADIUS] fill];
	}
	/* AND THE TICKS GO ON LAST, OVER THE FILL, because the scale is the thing that has to stay readable: a mark the
	 * accent covers is a mark this face stopped drawing for the value's sake. */
	[self cg_drawTickMarks:cellFrame flipped:flipped];
}

/* **THE KNOB'S PATH, WHICH IS SIX CUBIC BÉZIERS AND NO ARCS.** A teardrop is two circular caps joined by two tapering
 * sides, and every piece of it is drawn as a cubic with the control points an arc wants (`NS_SLIDER_KNOB_ARC_K`) — so
 * the whole silhouette is one list of explicit coordinates rather than a mixture of curves and arcs whose angle
 * conventions have to be gotten right twice, once per orientation.
 *
 * `t` IS MEASURED **UP FROM THE RECT'S BOTTOM**, and that is where the orientation is applied and nowhere else: the
 * shape is described the way a person SEES it — round end up, narrow end down — and `fn_knob_t` maps that onto the
 * cell's coordinates at the last moment. A flipped view counts y downward, so a shape drawn in raw coordinates would
 * come out upside down in exactly the windows that flip, which is the sort of thing that looks fine until it does not.
 *
 * THE RECT IS THE SHAPE'S BOUNDING BOX: the wide cap touches the top, the narrow cap's lowest point touches the
 * bottom, and the widest point sits at half height. So the knob is exactly as large as `-knobRect:flipped:` says it
 * is, and the geometry and the ink cannot drift apart. */
static CGFloat fn_knob_t(NSRect rect, BOOL flipped, CGFloat t)
{
	return flipped ? (rect.origin.y + rect.size.height - t) : (rect.origin.y + t);
}

static NSBezierPath *fn_knob_path(NSRect rect, BOOL flipped)
{
	CGFloat w = rect.size.width;
	CGFloat h = rect.size.height;
	CGFloat mid = rect.origin.x + w / 2.0;	/* the grabber's axis of symmetry */
	/* **THE CAP IS HALF THE SHORTER SIDE, WHICH IS WHAT KEEPS A TALL BOX FROM BECOMING A FAT BLOB.** The grabber's box
	 * is elongated across the track, and taking the cap's radius from the WIDTH alone would draw a cap that did not fit
	 * its own height — a wide dome with the taper squeezed out of it. Half the shorter side makes the shape as large as
	 * its box allows and never wider than it is tall: A TALLER BOX GIVES A TALLER TEARDROP, and a box that is merely
	 * wider centres the same shape in it. */
	CGFloat shortSide = (w < h) ? w : h;
	CGFloat rad = shortSide / 2.0;		/* the WIDE cap's radius: a semicircle of half the short side */
	CGFloat cap = h - rad;			/* where that cap's centre sits, measured up from the bottom */
	CGFloat tip = shortSide * NS_SLIDER_KNOB_TIP_RADIUS;	/* the NARROW cap's radius */
	CGFloat k = NS_SLIDER_KNOB_ARC_K;
	CGFloat theta = NS_SLIDER_KNOB_TIP_ANGLE * FN_KNOB_PI / 180.0;
	CGFloat ct = (CGFloat)cos(theta);
	CGFloat st = (CGFloat)sin(theta);
	/* WHERE THE NARROW CAP ENDS, and the control length that makes each of its halves an ARC of `theta`. */
	CGFloat edgeX = tip * st;
	CGFloat edgeY = tip * (1.0 - ct);
	CGFloat bow = (4.0 / 3.0) * (CGFloat)tan(theta / 4.0) * tip;
	CGFloat dx, dy, limit, side;
	NSBezierPath *p = [NSBezierPath bezierPath];

	/* **A RECT TOO SHORT FOR BOTH CAPS IS CLAMPED RATHER THAN DRAWN INSIDE OUT.** The grabber is square by construction
	 * (see `-knobRect:flipped:`), so the two caps always fit — this is a guard against a rectangle a CALLER hands
	 * `-drawKnob:`, where an unclamped `cap` below the narrow cap's shoulder would put the wide cap below the narrow one
	 * and the sides would fold through themselves. */
	if (cap < edgeY + 0.5) {
		cap = edgeY + 0.5;
		if (cap > h) {
			cap = h;
		}
	}

	/* **AND THE SIDE'S CONTROL LENGTH, WHICH IS WHAT MAKES THE BOW CONVEX INSTEAD OF AN S.** The side leaves the narrow
	 * cap along THAT cap's tangent `(cos, sin)` and arrives at the wide one VERTICALLY — the direction the wide cap's
	 * radius points — and a cubic whose control points lie on those two directions turns the same way all the way up,
	 * so that the silhouette bulges outward and never inflects, AS LONG AS THE CONTROL POINTS ARE SHORT ENOUGH THAT THE
	 * CONTROL POLYGON ITSELF TURNS ONE WAY. Working that out: the middle leg of the polygon must point between the two
	 * tangents, which comes to `dy - tan(theta)·dx` — the chord's rise less the rise the narrow cap's tangent would
	 * already account for. A NEGATIVE ANSWER MEANS THE CHORD IS SHALLOWER THAN THE TANGENT IT HAS TO LEAVE ALONG, where
	 * no bow is possible and the honest side is a straight one. */
	dx = rad - edgeX;
	dy = cap - edgeY;
	limit = dy - (CGFloat)tan(theta) * dx;
	side = (limit > 0.0) ? (limit * NS_SLIDER_KNOB_SIDE_BOW) : 0.0;

	/* THE NARROW END, LEFT TO RIGHT, THROUGH ITS LOWEST POINT. Each half is ONE cubic carrying the control length an
	 * arc of `theta` wants, so the end is a circular cap and not a spike — just a SHALLOWER one than a semicircle,
	 * which is the whole of what lets the sides leave it at an angle. */
	[p moveToPoint:NSMakePoint(mid - edgeX, fn_knob_t(rect, flipped, edgeY))];
	[p curveToPoint:NSMakePoint(mid, fn_knob_t(rect, flipped, 0.0))
	  controlPoint1:NSMakePoint(mid - edgeX + bow * ct, fn_knob_t(rect, flipped, edgeY - bow * st))
	  controlPoint2:NSMakePoint(mid - bow, fn_knob_t(rect, flipped, 0.0))];
	[p curveToPoint:NSMakePoint(mid + edgeX, fn_knob_t(rect, flipped, edgeY))
	  controlPoint1:NSMakePoint(mid + bow, fn_knob_t(rect, flipped, 0.0))
	  controlPoint2:NSMakePoint(mid + edgeX - bow * ct, fn_knob_t(rect, flipped, edgeY - bow * st))];
	/* **THE RIGHT SIDE, WHICH BOWS OUTWARD NOW RATHER THAN PINCHING IN.** It leaves the narrow cap along that cap's
	 * tangent and arrives at the wide one vertically, both joins smooth, with the bow bounded above so the curve stays
	 * convex. THIS IS THE SIDE THE FACE WAS ASKED TO FIX: with a semicircular narrow cap it had to leave vertically
	 * too, and a cubic with vertical tangents at both ends is an S whatever else you do to it. */
	[p curveToPoint:NSMakePoint(mid + rad, fn_knob_t(rect, flipped, cap))
	  controlPoint1:NSMakePoint(mid + edgeX + side * ct, fn_knob_t(rect, flipped, edgeY + side * st))
	  controlPoint2:NSMakePoint(mid + rad, fn_knob_t(rect, flipped, cap - side))];
	/* THE WIDE CAP: a semicircle of radius `rad`, which is half the shape — so its topmost point is the rect's top. */
	[p curveToPoint:NSMakePoint(mid, fn_knob_t(rect, flipped, cap + rad))
	  controlPoint1:NSMakePoint(mid + rad, fn_knob_t(rect, flipped, cap + k * rad))
	  controlPoint2:NSMakePoint(mid + k * rad, fn_knob_t(rect, flipped, cap + rad))];
	[p curveToPoint:NSMakePoint(mid - rad, fn_knob_t(rect, flipped, cap))
	  controlPoint1:NSMakePoint(mid - k * rad, fn_knob_t(rect, flipped, cap + rad))
	  controlPoint2:NSMakePoint(mid - rad, fn_knob_t(rect, flipped, cap + k * rad))];
	/* AND THE LEFT SIDE, BACK DOWN TO WHERE THIS STARTED — the mirror of the right one, which is why it carries the
	 * same `side` and the same tangents with x negated. */
	[p curveToPoint:NSMakePoint(mid - edgeX, fn_knob_t(rect, flipped, edgeY))
	  controlPoint1:NSMakePoint(mid - rad, fn_knob_t(rect, flipped, cap - side))
	  controlPoint2:NSMakePoint(mid - edgeX - side * ct, fn_knob_t(rect, flipped, edgeY + side * st))];
	[p closePath];
	return p;
}

- (void)drawKnob:(NSRect)knobRect
{
	/* **"WHICH WAY IS UP" IS A QUESTION FOR THE CONTROL VIEW, BECAUSE THIS DOOR'S ARGUMENT CANNOT ANSWER IT.**
	 * `-drawKnob:` is Apple's and takes a rectangle; a teardrop is ASYMMETRIC, so the cell has to find out whether the
	 * view it is drawing into counts y upward or downward — the same reason `-drawWithFrame:inView:` passes the flip
	 * down to `-drawBarInside:flipped:`. A cell with no view (a measurement, an offscreen probe) is not flipped, which
	 * is the quiet answer. */
	id view = [self controlView];
	BOOL flipped = NO;
	NSBezierPath *body;

	if (view != nil && [view respondsToSelector:@selector(isFlipped)]) {
		flipped = [view isFlipped];
	}
	/* **AND WITH NO TICK MARKS TO POINT AT, THE GRABBER IS A CIRCLE.** The teardrop's point exists to line up with a
	 * tick — it says WHICH mark the value is on — so a slider that has none has nothing for it to point at, and a
	 * circle is the honest shape for a control whose only question is "how far along this track".
	 *
	 * **THE CIRCLE IS THE TEARDROP'S OWN WIDE CAP, AT THE TEARDROP'S OWN WIDTH.** Both take their radius from
	 * `min(width, height) / 2`, so the two shapes differ only in what happens BELOW that cap, and a caller changing the
	 * tick count watches the POINT appear and disappear rather than the whole grabber changing size under their
	 * hand. */
	if (_numberOfTickMarks > 0) {
		body = fn_knob_path(knobRect, flipped);
	} else {
		CGFloat side = (knobRect.size.width < knobRect.size.height) ? knobRect.size.width : knobRect.size.height;
		NSRect circle = NSMakeRect(NSMidX(knobRect) - side / 2.0, NSMidY(knobRect) - side / 2.0,
					   side, side);

		body = [NSBezierPath bezierPathWithOvalInRect:circle];
	}

	/* **A DISABLED SLIDER'S KNOB IS DRAWN IN THE BACKGROUND COLOUR RATHER THAN NOT DRAWN**, which is the same
	 * reading `NSButtonCell` takes for a disabled button: the face is still a slider, and the thing that changed is
	 * that it will not move. */
	if ([self isEnabled]) {
		[[NSColor controlColor] setFill];
		[body fill];
		[[NSColor controlShadowColor] setStroke];
	} else {
		[[NSColor controlBackgroundColor] setFill];
		[body fill];
		[[NSColor controlDarkShadowColor] setStroke];
	}
	[body stroke];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	BOOL flipped = (controlView != nil) ? [controlView isFlipped] : NO;

	/* **THE TWO HALVES IN ORDER, WHICH IS WHY THEY ARE PUBLIC**: a subclass that wants a different knob overrides
	 * `-drawKnob:` and keeps the track, and the bar goes down first so the knob sits ON it rather than behind it. */
	[self drawBarInside:cellFrame flipped:flipped];
	[self drawKnob:[self knobRect:cellFrame flipped:flipped]];
}

@end
