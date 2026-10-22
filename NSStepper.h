/*
 * NSStepper.h — A PAIR OF ARROWS THAT MOVES ONE NUMBER.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CONTROL IS A SHELL AROUND ITS CELL, WHICH IS WHERE THE FOUR FACTS LIVE.** Range, step and the two policies are
 * `NSStepperCell`'s; this class makes one in `-initWithFrame:` and forwards, which is the same shape `NSSlider` and
 * `NSButton` have one class over. The VALUE is not a door here either: it is `NSControl`'s `-doubleValue`, so a stepper
 * and a text field beside it already agree about what a number is.
 *
 * **AND THE CONTROL IS WHAT SENDS THE ACTION**, because a cell has no target chain of its own — the cell's step asks its
 * control view, which is this class.
 */
#ifndef APPKIT_NSSTEPPER_H
#define APPKIT_NSSTEPPER_H

#import <AppKit/NSControl.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSStepper : NSControl <NSSecureCoding>

/* THE CELL, MADE AND INSTALLED — an `NSStepperCell`, not a plain one. */
- (instancetype)initWithFrame:(NSRect)frameRect;

/* THE FOUR FACTS, EACH ITS CELL'S. */
- (double)minValue;
- (void)setMinValue:(double)aDouble;
- (double)maxValue;
- (void)setMaxValue:(double)aDouble;
- (double)increment;
- (void)setIncrement:(double)increment;
- (BOOL)valueWraps;
- (void)setValueWraps:(BOOL)flag;
- (BOOL)autorepeat;
- (void)setAutorepeat:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSTEPPER_H */
