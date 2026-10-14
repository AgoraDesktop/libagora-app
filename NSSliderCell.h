/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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
 * WHAT IS NOT HERE, STATED RATHER THAN STUBBED:
 *   * `-drawKnob`, the NO-ARGUMENT drawing door. Apple documents it as drawing "the knob" with no rectangle, which
 *     is only answerable while a tracking pass is in flight — the rectangle this cell can compute at any time is
 *     `-knobRect:flipped:`, which is the door below. Declaring a door that has no rectangle to draw into would be
 *     declaring ink that cannot be produced.
 *   * THE CIRCULAR STYLE IS DECLARED AND STORED, NOT DRAWN. `NSCircularSlider` is accepted by `-setSliderType:` and
 *     answered by `-sliderType`, and the face this tier draws is the linear one — named AT that setter rather than
 *     silently drawn as a line, which is this tree's rule for a door whose far side is a whole other drawing.
 */
#ifndef APPKIT_NSSLIDERCELL_H
#define APPKIT_NSSLIDERCELL_H

#import <AppKit/NSActionCell.h>

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

@interface NSSliderCell : NSActionCell
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
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSLIDERCELL_H */
