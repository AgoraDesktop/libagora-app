/*
 * NSSliderCell — a slider's range, value, geometry and ink.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
#import <AppKit/NSFont.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSString.h>

#include "AppKitRefusal.h"

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

/* **THE TICKS' TWO MEASURES, EACH TAKEN FROM SOMETHING RATHER THAN CHOSEN FROM NOTHING.** A tick begins just clear of
 * the TRACK and ends just clear of the GRABBER — `BREADTH / 2` is exactly where the grabber's outline is — which is
 * the whole reason to have them: a scale that stops inside the grabber is a scale only the gaps between values can
 * show. MEASURING THE FAR END FROM THE GRABBER IS THE POINT: a fixed length would be swallowed whole by a tall
 * grabber and would dwarf a short one, whereas `PEEK` is the same few points of line below the grabber's edge
 * whatever size that grabber is. */
#define NS_SLIDER_TICK_INSET		1.0
#define NS_SLIDER_TICK_PEEK		3.0

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

/* ============================================================================================
 * THE TITLE'S DEFAULT CELL, AND THE PRIVATE ARITHMETIC THE NEW DOORS SHARE.
 * ============================================================================================ */

/* **A TITLE CELL IS AN `NSCell`, AND THE DEFAULT ONE IS THIS PRIVATE TEXT CELL.** Apple's title cell is an `NSCell`,
 * which is what lets a caller replace it and keep the slider's own arithmetic; what a default title needs beyond the
 * base cell is exactly one thing — a COLOUR — because `NSCell` has a font and an alignment but no text colour. So this
 * subclass adds the colour and centres the title on the band it is given. The centre is computed HERE rather than
 * left to `-alignment` because the slider passes a band the width of the whole control and a title cell that honoured
 * only the base's left alignment would draw every title at the slider's left edge. */
@interface AGSliderTitleCell : NSCell
{
	NSColor *_titleColor;		/* RETAINED */
}
- (nullable NSColor *)titleColor;
- (void)setTitleColor:(nullable NSColor *)color;
@end

@implementation AGSliderTitleCell

- (void)dealloc
{
	[_titleColor release];
	[super dealloc];
}

- (NSColor *)titleColor
{
	return _titleColor;
}

- (void)setTitleColor:(NSColor *)color
{
	if (color != _titleColor) {
		[color retain];
		[_titleColor release];
		_titleColor = color;
	}
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSString *title = [self title];
	NSFont *font = (NSFont *)[self font];
	NSColor *ink;
	NSDictionary *attributes;
	NSSize size;
	CGFloat baseline;

	(void)controlView;
	if (title == nil || [title length] == 0 || NSWidth(cellFrame) <= 0.0 || NSHeight(cellFrame) <= 0.0) {
		return;
	}
	if (font == nil) {
		font = [NSFont systemFontOfSize:12.0];
	}
	/* A DISABLED SLIDER'S TITLE IS DRAWN IN THE DISABLED INK, the same reading its knob takes: the label is still
	 * there and it still says what the control is; what changed is that the control will not move. A caller's own
	 * colour is used while the control is enabled, which is what makes `-setTitleColor:` a fact about the face rather
	 * than about storage. */
	ink = ![self isEnabled] ? [NSColor disabledControlTextColor]
			       : ((_titleColor != nil) ? _titleColor : [NSColor controlTextColor]);
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ink,
		      NSForegroundColorAttributeName, nil];
	size = [title sizeWithAttributes:attributes];
	if (size.width <= 0.0 || size.height <= 0.0) {
		return;
	}
	/* THE BASELINE ARITHMETIC IS `NSTextFieldCell`'s, one class over: the line's middle is the band's middle, and
	 * `-drawAtPoint:` takes a BASELINE (not a lower-left corner) in this stack. */
	baseline = NSMidY(cellFrame) + ([font ascender] - (CGFloat)fabs((double)[font descender])) / 2.0;
	[title drawAtPoint:NSMakePoint(NSMidX(cellFrame) - size.width / 2.0, baseline) withAttributes:attributes];
}

@end

/* **THE PRIVATE DOORS, DECLARED BEFORE THEY ARE USED.** The geometric helpers predate this unit and were defined in
 * reading order; the tick and title helpers are shared by a public door and a drawing door, so naming them here keeps
 * a change to the arithmetic in ONE place. */
@interface NSSliderCell (AGSliderPrivate)
- (CGFloat)cg_fraction;
- (CGFloat)fn_grabberAlong;
- (CGFloat)cg_titleBandHeight;
- (NSRect)cg_barRectForCellFrame:(NSRect)cellFrame flipped:(BOOL)flipped;
- (NSRect)cg_trackRectForCellFrame:(NSRect)cellFrame;
- (NSRect)cg_tickRectAtIndex:(NSInteger)index inFrame:(NSRect)cellFrame flipped:(BOOL)flipped;
- (void)cg_drawTickMarks:(NSRect)cellFrame flipped:(BOOL)flipped;
- (void)cg_drawTitleInCellFrame:(NSRect)cellFrame flipped:(BOOL)flipped inView:(id)controlView;
@end

/* THE VALUE THE nth OF n MARKS STANDS FOR: the marks are evenly spaced with BOTH ENDS included, so n == 1 is the
 * minimum and n == 0 is not a division at all. A static function rather than a method because it is arithmetic over
 * three numbers the caller has, and three of the doors below ask it the same question. */
static double fn_tick_value(double lo, double hi, NSInteger index, NSInteger count)
{
	if (count <= 1) {
		return lo;
	}
	return lo + (hi - lo) * ((double)index / (double)(count - 1));
}

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
static NSString * const AGCoderSliderKnobThicknessKey = @"knobThickness";
static NSString * const AGCoderSliderTickValuesOnlyKey = @"allowsTickMarkValuesOnly";
static NSString * const AGCoderSliderTitleFontKey = @"titleFont";
static NSString * const AGCoderSliderTitleColorKey = @"titleColor";

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
	[aCoder encodeDouble:_knobThickness forKey:AGCoderSliderKnobThicknessKey];
	[aCoder encodeBool:_allowsTickMarkValuesOnly forKey:AGCoderSliderTickValuesOnlyKey];
	[aCoder encodeObject:_titleFont forKey:AGCoderSliderTitleFontKey];
	[aCoder encodeObject:_titleColor forKey:AGCoderSliderTitleColorKey];
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
	/* **THE NEW STATE, AND THE DEFAULTS A DECODE DOES NOT GET FROM `-init`.** A decoded cell never runs `-init`, so
	 * the two objects the face needs — a title font and a title colour — are made here FIRST and then overwritten by
	 * the file's own values when it has them. The setters are used rather than the ivars so the title cell (made
	 * lazily below) is kept in step by the same code a caller's setter uses. */
	_titleFont = [[NSFont systemFontOfSize:12.0] retain];
	_titleColor = [[NSColor controlTextColor] retain];
	if ([aDecoder containsValueForKey:AGCoderSliderKnobThicknessKey]) {
		_knobThickness = [aDecoder decodeDoubleForKey:AGCoderSliderKnobThicknessKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderTickValuesOnlyKey]) {
		_allowsTickMarkValuesOnly = [aDecoder decodeBoolForKey:AGCoderSliderTickValuesOnlyKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderTitleFontKey]) {
		[self setTitleFont:[aDecoder decodeObjectForKey:AGCoderSliderTitleFontKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderSliderTitleColorKey]) {
		[self setTitleColor:[aDecoder decodeObjectForKey:AGCoderSliderTitleColorKey]];
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
		/* **ZERO MEANS "THE SHAPE'S OWN THICKNESS"**, which is why this is not initialised to a number here: the
		 * teardrop and the circle have different lengths, and copying one of them into storage would make the other
		 * shape's default a caller's setting. */
		_knobThickness = 0.0;
		_allowsTickMarkValuesOnly = NO;
		/* THE TITLE'S TWO CONVENIENCES, RETAINED, AND THE CELL ITSELF LAZY — see the header's ivar note. */
		_titleFont = [[NSFont systemFontOfSize:12.0] retain];
		_titleColor = [[NSColor controlTextColor] retain];
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
	[_titleCell release];
	[_titleFont release];
	[_titleColor release];
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
	/* **AND THEN THE TICKS, WHEN THE CALLER HAS SAID THE VALUE MAY ONLY BE A MARK.** The snap happens HERE rather
	 * than in each setter for the same reason the clamp does: every value door funnels through this one, including
	 * the re-clamp that moving an end performs, so "values only on ticks" is a property of the cell rather than of
	 * four setters that each have to remember it. `-closestTickMarkValueToValue:` is the arithmetic, and it does not
	 * call back into this door. */
	if (_allowsTickMarkValuesOnly && _numberOfTickMarks > 0) {
		clamped = [self closestTickMarkValueToValue:clamped];
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

/* ---- THE BACKGROUND IMAGE, WHICH THE DRAWING BELOW CONSULTS ------------------------------------------------ */

/* **`-image` IS INHERITED FROM `NSCell`, AND ITS SETTER IS OVERRIDDEN ONLY TO REPAINT.** Apple's slider parameter name
 * is `backgroundImage`, and the face draws it under the track, the knob and the title — so a caller that sets one on the
 * CELL (rather than through the control) must see the face change, which is the one thing the base cell's storage does
 * not do. */
- (void)setImage:(NSImage *)anImage
{
	[super setImage:anImage];
	[(NSView *)[self controlView] setNeedsDisplay:YES];
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
	/* **MOVING OR REMOVING THE MARKS RE-SNAPS A STANDING VALUE, because a value that was on a mark may no longer be
	 * on one.** Removing every mark leaves the value alone: with nothing to snap to, the value is the caller's. */
	if (_allowsTickMarkValuesOnly && _numberOfTickMarks > 0) {
		[self setDoubleValue:_sliderValue];
	}
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

/* ---- THE TICKS AS VALUES: THE ARITHMETIC THE INK AND THE FLAG BOTH USE --------------------------------------- */

- (BOOL)allowsTickMarkValuesOnly
{
	return _allowsTickMarkValuesOnly;
}

- (void)setAllowsTickMarkValuesOnly:(BOOL)flag
{
	_allowsTickMarkValuesOnly = flag;
	/* TURNING IT ON CONSTRAINS THE VALUE THAT IS ALREADY THERE, rather than waiting for the next drag: a knob
	 * between two marks is not a state this flag allows, and leaving it there until something else moved it would
	 * make the flag a question about the future instead of about the cell. Turning it OFF changes nothing. */
	if (flag && _numberOfTickMarks > 0) {
		[self setDoubleValue:_sliderValue];
	}
}

- (double)tickMarkValueAtIndex:(NSInteger)index
{
	/* AN INDEX OUTSIDE THE MARKS ANSWERS THE MINIMUM, which is this type's empty answer — the same disposition every
	 * refusal in this tree takes. There is no tick value to invent, and answering `NAN` or a value off the range
	 * would be a worse lie than the minimum. **APPLE RAISES `NSRangeException` HERE**; this tree has no such
	 * exception in use, and aborting a caller from a measurement door would be the worse failure. The deviation is
	 * stated rather than silent. */
	if (_numberOfTickMarks <= 0 || index < 0 || index >= _numberOfTickMarks) {
		return _minValue;
	}
	return fn_tick_value(_minValue, _maxValue, index, _numberOfTickMarks);
}

- (double)closestTickMarkValueToValue:(double)aValue
{
	double clamped = aValue;
	double span;
	NSInteger index;

	/* THE SAME CLAMP `-setDoubleValue:` APPLIES, repeated here because this door is public and must answer a number
	 * inside the range whatever it was handed. A NAN is pinned to the minimum for the reason that door records. */
	if (clamped != clamped) {
		clamped = _minValue;
	}
	if (clamped < _minValue) {
		clamped = _minValue;
	}
	if (clamped > _maxValue) {
		clamped = _maxValue;
	}
	if (_numberOfTickMarks <= 0) {
		return clamped;		/* no marks: the nearest mark is the value itself, which is the only honest answer */
	}
	if (_numberOfTickMarks == 1) {
		return _minValue;	/* one mark, at the minimum, so every value is it */
	}
	span = _maxValue - _minValue;
	if (span <= 0.0) {
		return _minValue;
	}
	index = (NSInteger)llround(((clamped - _minValue) / span) * (double)(_numberOfTickMarks - 1));
	if (index < 0) {
		index = 0;
	}
	if (index > _numberOfTickMarks - 1) {
		index = _numberOfTickMarks - 1;
	}
	return fn_tick_value(_minValue, _maxValue, index, _numberOfTickMarks);
}

/* ---- THE TITLE: A CELL, AND THE TWO CONVENIENCES OVER IT ------------------------------------------------------ */

/* The default cell is a text cell with a colour; the band above the track is the title's. `-title` and `-setTitle:`
 * are `NSCell`'s and are mirrored into this cell so the label drawn and the label answered cannot drift. */
- (NSCell *)titleCell
{
	if (_titleCell == nil) {
		AGSliderTitleCell *cell = [[AGSliderTitleCell alloc] initTextCell:(_title != nil) ? _title : @""];

		[cell setFont:_titleFont];
		[cell setTitleColor:_titleColor];
		[cell setAlignment:NSCenterTextAlignment];
		_titleCell = cell;
	}
	return _titleCell;
}

- (void)setTitleCell:(NSCell *)aCell
{
	[aCell retain];
	[_titleCell release];
	_titleCell = aCell;
	if (_titleCell != nil) {
		[_titleCell setTitle:(_title != nil) ? _title : @""];
		[_titleCell setFont:_titleFont];
		if ([_titleCell respondsToSelector:@selector(setTitleColor:)]) {
			[(AGSliderTitleCell *)_titleCell setTitleColor:_titleColor];
		}
	}
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (void)setTitle:(NSString *)aString
{
	[super setTitle:aString];	/* which COPIES and clears the mnemonic, the base's own invariants */
	[_titleCell setTitle:(_title != nil) ? _title : @""];
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (NSFont *)titleFont
{
	return _titleFont;
}

- (void)setTitleFont:(NSFont *)font
{
	NSFont *held = [(font != nil) ? font : [NSFont systemFontOfSize:12.0] retain];

	[_titleFont release];
	_titleFont = held;
	[_titleCell setFont:_titleFont];
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (NSColor *)titleColor
{
	return _titleColor;
}

- (void)setTitleColor:(NSColor *)color
{
	NSColor *held = [(color != nil) ? color : [NSColor controlTextColor] retain];

	[_titleColor release];
	_titleColor = held;
	if ([_titleCell respondsToSelector:@selector(setTitleColor:)]) {
		[(AGSliderTitleCell *)_titleCell setTitleColor:_titleColor];
	}
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

/* **THE BAND THE TITLE OCCUPIES, AND THE FRAME THE TRACK AND KNOB GET.** The title sits at the TOP of the cell frame
 * in both orientations; the track and knob then live in what is left. A frame too short for both keeps four points
 * for the track rather than letting the title eat it — a titled slider in a 20-point frame is a real control, and a
 * zero-height bar would be a titled slider that draws nothing you can drag. */
- (CGFloat)cg_titleBandHeight
{
	CGFloat height;

	if (_titleFont == nil || _title == nil || [_title length] == 0) {
		return 0.0;
	}
	height = ceil([_titleFont ascender] - (CGFloat)[_titleFont descender]) + 2.0;
	return (height > 0.0) ? height : 0.0;
}

- (NSRect)cg_barRectForCellFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
	CGFloat band = [self cg_titleBandHeight];
	CGFloat height = NSHeight(cellFrame);

	if (band > 0.0) {
		if (height > 4.0 && band > height - 4.0) {
			band = height - 4.0;
		}
		if (band >= height) {
			band = 0.0;
		}
	}
	if (band <= 0.0) {
		return cellFrame;
	}
	return flipped ? NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame) + band,
				    NSWidth(cellFrame), height - band)
		       : NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame),
				    NSWidth(cellFrame), height - band);
}

- (NSRect)cg_titleRectForCellFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
	CGFloat band = [self cg_titleBandHeight];
	CGFloat height = NSHeight(cellFrame);

	if (band <= 0.0) {
		return NSZeroRect;
	}
	if (band > height) {
		band = height;
	}
	return flipped ? NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), NSWidth(cellFrame), band)
		       : NSMakeRect(NSMinX(cellFrame), NSMaxY(cellFrame) - band, NSWidth(cellFrame), band);
}

- (void)cg_drawTitleInCellFrame:(NSRect)cellFrame flipped:(BOOL)flipped inView:(id)controlView
{
	NSRect band = [self cg_titleRectForCellFrame:cellFrame flipped:flipped];

	if (band.size.width <= 0.0 || band.size.height <= 0.0) {
		return;
	}
	[[self titleCell] drawWithFrame:band inView:controlView];
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
	/* A CALLER'S THICKNESS WINS OVER BOTH SHAPES' DEFAULTS; zero is the "never set" that keeps them. */
	if (_knobThickness > 0.0) {
		return (CGFloat)_knobThickness;
	}
	return (_numberOfTickMarks > 0) ? NS_SLIDER_KNOB_LENGTH : NS_SLIDER_KNOB_BREADTH;
}

- (double)knobThickness
{
	return (double)[self fn_grabberAlong];
}

- (void)setKnobThickness:(double)thickness
{
	/* A THICKNESS BELOW ONE POINT IS NOT A GRABBER, and a zero would read as "the default" instead of "zero" because
	 * that is what the ivar's zero means. One point is the smallest thickness the shape can still be seen at, so a
	 * caller asking for less gets that rather than a knob that vanishes or a setting that silently reverts. */
	if (thickness < 1.0) {
		thickness = 1.0;
	}
	_knobThickness = thickness;
	[(NSView *)[self controlView] setNeedsDisplay:YES];
}

- (NSRect)knobRect:(NSRect)cellFrame flipped:(BOOL)isFlipped
{
	CGFloat fraction = [self cg_fraction];
	CGFloat along = [self fn_grabberAlong];	/* along the track: the dimension the tracking is built on */
	CGFloat across = NS_SLIDER_KNOB_BREADTH;	/* across it: the teardrop's height */
	NSRect knob;

	/* **THE TITLE'S BAND COMES OFF FIRST, HERE AND IN `-cg_valueAtPoint:`, SO THE GEOMETRY AND THE TRACK AGREE.** A
	 * slider with no title has a zero band and the frame passes through untouched — the existing probe's numbers do not
	 * move. */
	cellFrame = [self cg_barRectForCellFrame:cellFrame flipped:isFlipped];

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
	CGFloat along;

	cellFrame = [self cg_barRectForCellFrame:cellFrame flipped:isFlipped];
	along = [self fn_grabberAlong];
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

/* ---- THE TRACK, THE TICK MARKS' RECTANGLES, AND THE POINT THAT NAMES ONE ------------------------------------- */

/* **THE BAR THE KNOB RIDES, WHICH IS `-drawBarInside:flipped:`'s OWN RECTANGLE.** It is computed from the frame the
 * caller gives (with the title's band already taken off by `-drawWithFrame:inView:`), and the two orientations are
 * the same two rectangles the drawing has always used. A helper rather than a local so `-trackRect` and the ink
 * cannot drift apart. */
- (NSRect)cg_trackRectForCellFrame:(NSRect)cellFrame
{
	if (_vertical) {
		return NSMakeRect(NSMidX(cellFrame) - NS_SLIDER_TRACK_THICKNESS / 2.0,
				  NSMinY(cellFrame) + NS_SLIDER_TRACK_INSET,
				  NS_SLIDER_TRACK_THICKNESS,
				  NSHeight(cellFrame) - 2.0 * NS_SLIDER_TRACK_INSET);
	}
	return NSMakeRect(NSMinX(cellFrame),
			  NSMidY(cellFrame) - NS_SLIDER_TRACK_THICKNESS / 2.0,
			  NSWidth(cellFrame),
			  NS_SLIDER_TRACK_THICKNESS);
}

- (NSRect)trackRect
{
	id view = [self controlView];

	if (view == nil) {
		/* APPKIT-REFUSE: with no control view there is no frame to place a track in. A measurement cell can still
		 * answer its VALUE and its knob for a frame it is handed; this door has no frame argument, so the empty
		 * rectangle plus a reason is the honest answer. */
		fn_refuse_window("NSSliderCell -trackRect", "a control view to take the track's frame from");
		return NSZeroRect;
	}
	/* **THE RECTANGLE THE KNOB TRAVELS IN, NOT THE THIN BAR IT RIDES ON.** Apple's header marks this door "only valid
	 * while tracking the mouse", because its own storage is captured during a drawing/tracking pass; this tier can
	 * answer it at any time from the control view, and answers the wider rectangle the knob's own placement uses — the
	 * cell frame with the title's band removed. `-cg_trackRectForCellFrame:` is the four-point bar the ink fills, and
	 * the two are deliberately different questions. */
	return [self cg_barRectForCellFrame:[(NSView *)view bounds] flipped:[(NSView *)view isFlipped]];
}

/* **A TICK'S RECTANGLE, IN THE FRAME IT IS DRAWN IN.** The mark begins just clear of the TRACK and ends just clear of
 * the GRABBER — the same two measures the ink uses — and the along-track position is the value's fraction of the
 * travel. `flipped` is passed rather than read so the drawing door (which is handed a frame and a flip) and the public
 * door (which reads them from the control view) share ONE arithmetic. */
- (NSRect)cg_tickRectAtIndex:(NSInteger)index inFrame:(NSRect)cellFrame flipped:(BOOL)flipped
{
	CGFloat along = [self fn_grabberAlong];
	CGFloat travel = (_vertical ? NSHeight(cellFrame) : NSWidth(cellFrame)) - along;
	CGFloat fraction;
	CGFloat cross = (_vertical ? NSWidth(cellFrame) : NSHeight(cellFrame)) / 2.0;
	CGFloat in0 = NS_SLIDER_TRACK_THICKNESS / 2.0 + NS_SLIDER_TICK_INSET;
	CGFloat out0 = NS_SLIDER_KNOB_BREADTH / 2.0 + NS_SLIDER_TICK_PEEK;
	CGFloat dir = flipped ? -1.0 : 1.0;
	CGFloat inner, outer, lo, len;

	if (_numberOfTickMarks <= 0 || index < 0 || index >= _numberOfTickMarks || travel <= 0.0) {
		return NSZeroRect;
	}
	if (out0 > cross) {
		out0 = cross;
	}
	if (out0 < in0) {
		out0 = in0;
	}
	if (_tickMarkPosition == NSTickMarkAbove) {
		inner = dir * in0;
		outer = dir * out0;
	} else {
		inner = -dir * in0;
		outer = -dir * out0;
	}
	lo = (inner < outer) ? inner : outer;
	len = (outer > inner) ? (outer - inner) : (inner - outer);
	fraction = (_numberOfTickMarks == 1) ? 0.0
		   : (CGFloat)index / (CGFloat)(_numberOfTickMarks - 1);
	if (_vertical) {
		/* **THE VERTICAL MARK FOLLOWS THE KNOB, NOT THE RAW FRACTION.** An unflipped view counts up from the bottom,
		 * so the minimum is at `minY`; a flipped view counts down from the top, so the minimum is at `minY` too but
		 * the fraction has to run DOWNWARD. The old ink used the unflipped formula for both and drew the marks'
		 * scale upside down in a flipped view — a bug with no reader until `-rectOfTickMarkAtIndex:` arrived. */
		CGFloat y = NSMinY(cellFrame) + along / 2.0
			  + (flipped ? (1.0 - fraction) : fraction) * travel;

		return NSMakeRect(NSMidX(cellFrame) + lo, y - 0.5, len, 1.0);
	}
	return NSMakeRect(NSMinX(cellFrame) + along / 2.0 + fraction * travel - 0.5,
			  NSMidY(cellFrame) + lo, 1.0, len);
}

- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index
{
	id view = [self controlView];

	if (view == nil) {
		fn_refuse_window("NSSliderCell -rectOfTickMarkAtIndex:", "a control view to take the marks' frame from");
		return NSZeroRect;
	}
	return [self cg_tickRectAtIndex:index
				inFrame:[self cg_barRectForCellFrame:[(NSView *)view bounds]
							     flipped:[(NSView *)view isFlipped]]
				flipped:[(NSView *)view isFlipped]];
}

- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point
{
	id view = [self controlView];
	NSRect bar;
	BOOL flipped;
	NSInteger i;

	if (view == nil) {
		/* A POINT IS IN A VIEW'S COORDINATES, so with no view there is no coordinate system to answer in. */
		fn_refuse_window("NSSliderCell -indexOfTickMarkAtPoint:", "a control view to take the point's space from");
		return NSNotFound;
	}
	if (_numberOfTickMarks <= 0) {
		return NSNotFound;
	}
	flipped = [(NSView *)view isFlipped];
	bar = [self cg_barRectForCellFrame:[(NSView *)view bounds] flipped:flipped];
	/* **THE HIT IS THE MARK'S OWN RECTANGLE, GROWN BY THREE POINTS.** A mark is one point wide, which is not a
	 * target a person can be asked to hit exactly; the growth is stated here rather than hidden in the arithmetic.
	 * A point between two marks answers `NSNotFound` — this door asks WHICH MARK IS AT THIS POINT, not which is
	 * nearest, and the nearest question has its own door in value space. */
	for (i = 0; i < _numberOfTickMarks; i++) {
		NSRect tick = [self cg_tickRectAtIndex:i inFrame:bar flipped:flipped];

		if (NSPointInRect(point, NSInsetRect(tick, -3.0, -3.0))) {
			return i;
		}
	}
	return NSNotFound;
}

/* ---- AND THE TWO DOORS THAT TAKE THEIR RECTANGLE FROM THE CONTROL VIEW --------------------------------------- */

/* **APPLE'S NO-ARGUMENT DRAWING DOOR IS ANSWERABLE BECAUSE THIS CELL KNOWS ITS VIEW.** `-drawKnob` draws the knob at
 * the rectangle the standing value places it at, and `-knobRectFlipped:` is the deprecated spelling of the same
 * measurement. Both REFUSE BY NAME without a view: there is no frame to place the rectangle in, and inventing one
 * would be ink somewhere no caller asked for. */
- (void)drawKnob
{
	id view = [self controlView];

	if (view == nil) {
		fn_refuse_window("NSSliderCell -drawKnob", "a control view to take the knob's rectangle from");
		return;
	}
	[self drawKnob:[self knobRect:[(NSView *)view bounds] flipped:[(NSView *)view isFlipped]]];
}

- (NSRect)knobRectFlipped:(BOOL)isFlipped
{
	id view = [self controlView];

	if (view == nil) {
		fn_refuse_window("NSSliderCell -knobRectFlipped:", "a control view to take the knob's frame from");
		return NSZeroRect;
	}
	return [self knobRect:[(NSView *)view bounds] flipped:isFlipped];
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
- (void)cg_drawTickMarks:(NSRect)cellFrame flipped:(BOOL)flipped
{
	NSInteger i;

	/* **THE INK ASKS THE SAME RECTANGLE DOOR THE PUBLIC GEOMETRY DOES.** The arithmetic used to live here and in no
	 * other place, which is how the flipped vertical scale came to disagree with the knob; now there is one function
	 * (`-cg_tickRectAtIndex:inFrame:flipped:`) and both callers read it. */
	[[NSColor controlDarkShadowColor] setFill];
	for (i = 0; i < _numberOfTickMarks; i++) {
		NSRect tick = [self cg_tickRectAtIndex:i inFrame:cellFrame flipped:flipped];

		if (tick.size.width > 0.0 && tick.size.height > 0.0) {
			[[NSBezierPath bezierPathWithRect:tick] fill];
		}
	}
}

- (void)drawBarInside:(NSRect)cellFrame flipped:(BOOL)flipped
{
	NSRect track = [self cg_trackRectForCellFrame:cellFrame];
	NSRect filled;
	NSRect knob;

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
	NSRect bar = [self cg_barRectForCellFrame:cellFrame flipped:flipped];

	/* **THE BACKGROUND IMAGE FIRST, WHEN THERE IS ONE — `NSCell`'s `-image` IS THE SLIDER'S BACKGROUND in Apple's
	 * own parameter name (`-setImage:(NSImage *)backgroundImage`), so it goes under everything and the track, the knob
	 * and the title all sit on it. This is what gives the image door a reader rather than a stored value nobody
	 * consults; an image of the wrong size is stretched to the cell, which is the same rule a button's image follows. */
	if ([self image] != nil) {
		[[self image] drawInRect:cellFrame];
	}
	/* **THE TWO HALVES IN ORDER, WHICH IS WHY THEY ARE PUBLIC**: a subclass that wants a different knob overrides
	 * `-drawKnob:` and keeps the track, and the bar goes down first so the knob sits ON it rather than behind it.
	 * THE TITLE GOES LAST, in the band the bar was told to leave alone — so the words sit above the track in both
	 * orientations and the knob can never be drawn over them. */
	[self drawBarInside:bar flipped:flipped];
	[self drawKnob:[self knobRect:cellFrame flipped:flipped]];
	[self cg_drawTitleInCellFrame:cellFrame flipped:flipped inView:controlView];
}

@end
