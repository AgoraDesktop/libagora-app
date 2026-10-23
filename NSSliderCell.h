/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSliderCell.h — the cell that fills a slider's track and puts its knob where the value is (stage E).
 *
 * **A SLIDER IS A CONTROL WHOSE VALUE IS A POSITION, AND THE TWO HALVES FOLLOW FROM THAT ONE SENTENCE.** This cell
 * holds the first half: the RANGE (`-minValue`/`-maxValue`), the VALUE, the orientation, the ticks, and the two
 * geometric answers a face needs — `-knobRect:flipped:`, which turns a value into a rectangle, and
 * `-cg_valueAtPoint:inRect:flipped:`, which turns a rectangle back into a value. The CONTROL holds the other half:
 * the tracking loop, which feeds this cell the points the pointer is at. `-drawBarInside:flipped:` and `-drawKnob:`
 * are the ink, and they are what `-drawWithFrame:inView:` calls.
 *
 * **WHO SENDS THE ACTION IS THE CONTROL'S QUESTION AND NOT THIS CELL'S.** `-target`/`-action` are declared here
 * (through `NSActionCell`) because that is where Apple's own storage is, but the SENDING is `NSControl`'s
 * `-sendAction:to:` (§A10cc). This cell only updates its value when a point arrives; the control decides when a
 * changed value is worth a message, which is what keeps `-isContinuous` meaning one thing in one place.
 *
 * **AND THE ONE THING THAT MAKES "A SLIDER" DIFFERENT FROM "A BUTTON" IS THAT ITS VALUE FOLLOWS THE POINTER**, which
 * is why this cell answers the two tracking hooks `NSCell` already declares: `-startTrackingAt:inView:` takes the
 * press and `-continueTracking:at:inView:` takes every point after it. Both answer YES, because a drag on a slider is
 * a drag the slider intends to serve — the yes/no an unmodified cell computes from `-isContinuous` is about DRAGS,
 * and a slider is not a button that cancels when dragged.
 *
 * **THE TICKS ARE A VALUE FAMILY AND NOT ONLY INK, WHICH IS THE HALF THIS CLASS USED TO LACK.** The marks were drawn
 * before this unit, but a caller could not ask WHERE one was (`-rectOfTickMarkAtIndex:`), which one a point names
 * (`-indexOfTickMarkAtPoint:`), or what value the nth mark stands for (`-tickMarkValueAtIndex:`). With those here,
 * `-allowsTickMarkValuesOnly` can mean something: when it is set, every value the cell stores is snapped to the
 * nearest mark, so the knob can only come to rest on a tick. `-closestTickMarkValueToValue:` is the arithmetic that
 * snapping is defined by, and the probe checks the round trip rather than the flag's storage.
 *
 * **AND THE TITLE IS A CELL, APPLE'S SHAPE, DRAWN IN A BAND ABOVE THE TRACK.** `-titleCell` answers the `NSCell` that
 * draws the words (a text cell by default, so a caller can change its face and alignment), while `-titleFont` and
 * `-titleColor` are the conveniences over it. The band is taken off the TOP of the cell frame before the track and the
 * knob are placed, so a titled slider's knob is on its track rather than under its label; an untitled slider's
 * geometry is EXACTLY what it was, which is the property the existing probe pins.
 *
 * WHAT IS NOT HERE, STATED RATHER THAN STUBBED:
 *   * `-drawKnob` — the NO-ARGUMENT drawing door — is answerable now because this tier's cell knows its control view:
 *     it asks that view for its bounds and draws `-knobRect:flipped:` there, and REFUSES BY NAME when it has no view
 *     (a measurement, an offscreen cell) because there is no rectangle to draw into.
 *   * THE CIRCULAR STYLE IS DECLARED AND STORED, NOT DRAWN. `NSCircularSlider` is accepted by `-setSliderType:` and
 *     answered by `-sliderType`, and the face this tier draws is the linear one — named AT that setter rather than
 *     silently drawn as a line, which is this tree's rule for a door whose far side is a whole other drawing.
 */
#ifndef APPKIT_NSSLIDERCELL_H
#define APPKIT_NSSLIDERCELL_H

#import <AppKit/NSActionCell.h>

@class NSColor;
@class NSFont;

NS_ASSUME_NONNULL_BEGIN

/* **THE TWO ENUMERATIONS A SLIDER'S FACE IS CHOSEN FROM**, spelled with Apple's own constant names rather than
 * renamed: `NSSliderType` and `NSTickMarkPosition`. `NSTickMarkLeft` and `NSTickMarkRight` are ALIASES of the above
 * and below members because a vertical slider's ticks are the same two places rotated a quarter turn — Apple's own
 * choice, kept so that a caller's `NSTickMarkLeft` means what it means on the other platform. */
typedef enum {
	NSLinearSlider = 0,
	NSCircularSlider = 1
} NSSliderType;

typedef enum {
	NSTickMarkBelow = 0,
	NSTickMarkAbove = 1,
	NSTickMarkLeft = NSTickMarkAbove,
	NSTickMarkRight = NSTickMarkBelow
} NSTickMarkPosition;

@interface NSSliderCell : NSActionCell <NSSecureCoding>
{
	/* THE RANGE, THE VALUE AND THE LIE OF THE TRACK. `_sliderValue` is the value ITSELF rather than a fraction, so
	 * that `-setMinValue:`/`-setMaxValue:` moving the ends under a standing value is a visible clamp rather than a
	 * silent rescale — which is what a caller setting a maximum expects. */
	double _minValue;
	double _maxValue;
	double _sliderValue;
	BOOL _vertical;
	NSSliderType _sliderType;
	/* THE TICKS AND THE ALTERNATE INCREMENT. `_altIncrementValue` is the step an Option-drag takes, kept as a
	 * number rather than as behaviour because the modifier's reach into a drag is the TRACKING's question. */
	NSInteger _numberOfTickMarks;
	NSTickMarkPosition _tickMarkPosition;
	double _altIncrementValue;
	/* **THE KNOB'S THICKNESS, AND ZERO MEANS "THE SHAPE'S OWN".** The face has two grabbers — a teardrop when there
	 * are ticks to point at and a circle when there are not — and each has its own length along the track. A caller
	 * that sets a thickness overrides both; a caller that never sets one keeps the shapes' own defaults. The getter
	 * answers the EFFECTIVE length, so it is a measurement rather than a stored zero. */
	double _knobThickness;
	/* Whether every value stored is snapped to a tick mark. The reader is `-setDoubleValue:`, which is the one door
	 * every value goes through. */
	BOOL _allowsTickMarkValuesOnly;
	/* THE TITLE'S CELL AND THE TWO CONVENIENCES OVER IT. The cell is made lazily, because most sliders have no title
	 * and a cell per slider is not a cost worth paying before one is asked for. */
	NSCell *_titleCell;		/* RETAINED */
	NSFont *_titleFont;		/* RETAINED */
	NSColor *_titleColor;		/* RETAINED */
}

/* **THE ENDS OF THE RANGE.** Setting either RE-CLAMPS the standing value, because a value outside its range is not a
 * state this class has: `-doubleValue` promises a number the knob can be at. */
- (double)minValue;
- (void)setMinValue:(double)aDouble;
- (double)maxValue;
- (void)setMaxValue:(double)aDouble;

/* **AND THE VALUE ITSELF, IN THE FIVE SHAPES A CALLER ASKS FOR IT.** These OVERRIDE `NSCell`'s, whose rule is "does
 * nothing if the receiver isn't a text cell" — a slider is not a text cell and its value is not an object, so the
 * numeric family is the whole of its value surface and the string doors are not forwarded to it. Every setter
 * clamps to the range and marks the control for redisplay, which is what makes the knob follow. */
- (double)doubleValue;
- (void)setDoubleValue:(double)aDouble;
- (float)floatValue;
- (void)setFloatValue:(float)aFloat;
- (int)intValue;
- (void)setIntValue:(int)anInt;
- (NSInteger)integerValue;
- (void)setIntegerValue:(NSInteger)anInteger;

/* THE STEP AN OPTION-DRAG TAKES, AND THE FOUR PROPERTIES OF THE FACE A CALLER SETS. */
- (double)altIncrementValue;
- (void)setAltIncrementValue:(double)increment;
- (BOOL)isVertical;
- (void)setVertical:(BOOL)flag;
- (NSSliderType)sliderType;
- (void)setSliderType:(NSSliderType)aType;
- (NSInteger)numberOfTickMarks;
- (void)setNumberOfTickMarks:(NSInteger)count;
- (NSTickMarkPosition)tickMarkPosition;
- (void)setTickMarkPosition:(NSTickMarkPosition)position;

/* **THE TICKS AS SOMETHING A CALLER CAN ASK ABOUT, AND THE FLAG THAT MAKES THEM MANDATORY.**
 *
 * The marks are evenly spaced across the range INCLUSIVE of both ends, so the nth mark of n is the maximum and the
 * zeroth is the minimum; a single mark is the minimum, and no marks means "there are no tick values" rather than a
 * division by zero. `-allowsTickMarkValuesOnly` snaps every stored value to the nearest mark — including the value
 * standing when the flag is turned on, and including the re-clamp that moving an end performs. */
- (BOOL)allowsTickMarkValuesOnly;
- (void)setAllowsTickMarkValuesOnly:(BOOL)flag;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (double)closestTickMarkValueToValue:(double)aValue;

/* WHERE A MARK IS AND WHICH MARK A POINT NAMES, measured in the control view's coordinates. The two answer
 * `NSZeroRect` and `NSNotFound` when there are no marks, and both take the title's band off the frame first so a
 * titled slider's marks and knob are placed on the same track. */
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point;

/* **THE KNOB'S LENGTH ALONG THE TRACK.** The getter answers the effective length (the shape's own when nothing has
 * been set); the setter stores a thickness and the travel shrinks or grows by exactly the difference, because a
 * longer grabber can slide less far before its own end stops it. */
- (double)knobThickness;
- (void)setKnobThickness:(double)thickness;

/* **THE TITLE.** The string itself is `NSCell`'s `-title`/`-setTitle:`, because a slider's title is a cell's label and
 * not a second field; these are the cell that draws it and the two conveniences over that cell. */
- (NSCell *)titleCell;
- (void)setTitleCell:(nullable NSCell *)aCell;
- (nullable NSFont *)titleFont;
- (void)setTitleFont:(nullable NSFont *)font;
- (nullable NSColor *)titleColor;
- (void)setTitleColor:(nullable NSColor *)color;

/* **THE TRACK'S OWN RECTANGLE**, which is the bar the knob rides rather than the area the knob travels through. It is
 * the rectangle `-drawBarInside:flipped:` fills and the one the title band has already been taken off. */
- (NSRect)trackRect;

/* **THE TWO GEOMETRIC DOORS, WHICH ARE EXACT INVERSES OF EACH OTHER.** `-knobRect:flipped:` places the knob's
 * rectangle for the standing value; both measure the travel from the KNOB'S CENTRE, so that
 * `-cg_valueAtPoint:inRect:flipped:` applied to that rectangle's midpoint answers the value it was placed for. That
 * round trip is the property this pair is defined by, and the probe measures it rather than the ink. */
- (NSRect)knobRect:(NSRect)cellFrame flipped:(BOOL)isFlipped;
- (double)cg_valueAtPoint:(NSPoint)aPoint inRect:(NSRect)cellFrame flipped:(BOOL)isFlipped;

/* **AND THE INK.** `-drawBarInside:flipped:` is the track and the ticks, `-drawKnob:` is the knob at a rectangle the
 * caller has — and `-drawWithFrame:inView:` is the two in order, which is what makes the pair usable by a subclass
 * that wants to draw one of them differently. */
- (void)drawBarInside:(NSRect)aRect flipped:(BOOL)flipped;
- (void)drawKnob:(NSRect)knobRect;
/* THE NO-ARGUMENT SPELLING, WHICH TAKES ITS RECTANGLE FROM THE CONTROL VIEW — see the header's note above. */
- (void)drawKnob;
/* THE DEPRECATED SPELLING OF `-knobRect:flipped:`, which likewise has no frame argument and asks the control view. */
- (NSRect)knobRectFlipped:(BOOL)isFlipped;
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSLIDERCELL_H */
