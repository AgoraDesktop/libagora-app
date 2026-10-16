/*
 * AGSwitchCell.h — a track, a knob, and the four states the sample draws.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A SWITCH IS A TRACK AND A KNOB, AND THE SAMPLE MEASURES BOTH.** `Argentum Mockup.png` draws four of them beside its
 * four-state legend, and the numbers are the sample's rather than this file's:
 *
 *   * THE TRACK IS 32 x 20 AND IS A PILL — a rounded rectangle whose radius is half its height, MEASURED at x=756..787,
 *     y=603..622. So the radius is not a constant here; it is the height's other half, and a switch asked for at any
 *     height comes out a pill rather than a rounded box.
 *   * THE KNOB IS 12 ACROSS, INSET 4 FROM THE END IT SITS AT — white, a circle, and the only thing on the track with a
 *     curve that is not the track's own.
 *   * WHAT THE TRACK IS FILLED WITH IS THE STATE, and the four the sample shows are its legend's four: the control's
 *     grey when it is OFF, the ACCENT when it is ON, the accent LIGHTENED when the pointer is on an ON switch, and the
 *     disabled grey when it is out of action.
 *
 * **AND THE STATES ARE THE CELL'S OWN, WHICH IS WHY THERE IS NO IVAR HERE.** `NSCell` already carries `-_state`, and a
 * switch's value IS a state — off or on — so the value, the drawing and the action all read one field that the base
 * already has rather than a second one that would have to be kept in step with it.
 */
#ifndef AG_SWITCH_CELL_H
#define AG_SWITCH_CELL_H

#import <AppKit/NSActionCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGSwitchCell : NSActionCell

- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (NSSize)cellSizeForBounds:(NSRect)aRect;

@end

NS_ASSUME_NONNULL_END

#endif /* AG_SWITCH_CELL_H */
