/*
 * AGSwitch.h — a control that is off or on, and says so with a knob.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **APPLE HAS NO DOOR FOR THIS IN THE ERA THIS TREE PINS.** A switch arrived as `NSSwitch` in 10.15; in 10.5 and 10.6
 * the only thing shaped like one is `NSSwitchButton`, which is a CHECKBOX with a label and not a track. So this is the
 * tier's own control, named `AG` the way `AGChromeTheme` and the combo box's list are, and it is `NSControl` with a
 * cell under it for the same reason every other control here is: the cell decides and draws, and the control is the
 * thing with a frame and a window.
 *
 * **AND ITS VALUE IS ITS CELL'S STATE.** `NSCell` already carries one, off or on is exactly what a switch's value is,
 * and a second field for it would be a second thing to keep in step — so `-state` and `-setState:` are forwards and the
 * cell has no value of its own.
 */
#ifndef AG_SWITCH_H
#define AG_SWITCH_H

#import <AppKit/NSControl.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGSwitch : NSControl

- (nullable instancetype)initWithFrame:(NSRect)frameRect;

/* OFF OR ON, in the base's own vocabulary rather than a boolean of this class's: `NSOffState` and `NSOnState` are what
 * a cell's state already means, and a switch with a `-isOn` would be a second spelling of one fact. */
- (NSInteger)state;
- (void)setState:(NSInteger)state;

@end

NS_ASSUME_NONNULL_END

#endif /* AG_SWITCH_H */
