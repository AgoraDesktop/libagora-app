/*
 * NSStepperCell.h — THE ARROWS AND THE STEP.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A STEPPER IS A PAIR OF ARROWS THAT MOVES ONE NUMBER.** The control holds the cell, the cell holds the four facts that
 * decide what a press does — the range, the step, whether the value wraps at the ends and whether holding repeats — and
 * the value itself is `NSCell`'s `-doubleValue`, which is what makes a stepper's value the same value a text field beside
 * it has.
 *
 * **THE PRESS IS THE STEP.** Apple's stepper increments as soon as the arrow is pressed (and repeats while it is held),
 * so this cell's `-startTrackingAt:inView:` does the work: which half of the cell the pointer landed in decides the
 * direction, the clamp or the wrap decides the answer, and the action goes to the cell's target. `-stopTracking:…` only
 * clears the pressed ink.
 *
 * **`-autorepeat` IS STORED AND NOT YET LOOPED**, stated here rather than implied: the repeat needs the control's tracking
 * loop to poll a deadline (the slider's page-repeat is the one in this tier that does), and a stepper cell driven by a
 * single press is honest without it. The flag round-trips, so a caller that sets it can read it back.
 *
 * **THE DEFAULTS ARE APPLE'S**: range 0…59, step 1, wrapping ON, autorepeat ON.
 */
#ifndef APPKIT_NSSTEPPERCELL_H
#define APPKIT_NSSTEPPERCELL_H

#import <AppKit/NSActionCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSStepperCell : NSActionCell
{
	double _minValue;
	double _maxValue;
	double _increment;
	BOOL _valueWraps;
	BOOL _autorepeat;
	/* **THE VALUE IS THIS CELL'S OWN, BECAUSE `NSCell`'s IS A TEXT CELL'S.** `NSCell -setDoubleValue:` REFUSES unless the
	 * cell's type is `NSTextCellType` (an empty cell has no number to give), so a stepper that used it would be a control
	 * whose arrows changed nothing — MEASURED: that is exactly what the first version did. The pair is overridden below to
	 * read and write this field instead. */
	double _value;
	/* WHICH ARROW IS PRESSED: +1 upper, -1 lower, 0 neither. It is the pressed INK's state and nothing else — the step
	 * itself happens on the press, not on the release. */
	NSInteger _pressedSide;
}

- (double)minValue;
- (void)setMinValue:(double)aDouble;
- (double)maxValue;
- (void)setMaxValue:(double)aDouble;

/* **THE STEP AND ITS TWO POLICIES.** A step of zero or less is refused (the setter keeps the old one), because a stepper
 * whose arrow does nothing is a broken control rather than a configured one. */
- (double)increment;
- (void)setIncrement:(double)increment;

/* At the ends: wrap to the other end (YES) or stop (NO). */
- (BOOL)valueWraps;
- (void)setValueWraps:(BOOL)flag;

- (BOOL)autorepeat;
- (void)setAutorepeat:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSTEPPERCELL_H */
