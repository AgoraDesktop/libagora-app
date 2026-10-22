/*
 * NSProgressIndicator.h — a value shown as a bar, or a spinner that says "working".
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE DETERMINATE BAR IS THE ONE THE FILE OPERATIONS NEED: a minimum, a maximum and a value.** The bar's track
 * and fill are drawn here (the accent is `+cg_accentColor`, the same one a selection wears), and the value is clamped
 * to the range on the way in. The INDETERMINATE/SPINNING style is a small arc that turns while `-isAnimating`; this
 * tier has no animation timer, so the arc is drawn for the current state and `-startAnimation`/`-stopAnimation` keep
 * the state a caller reads.
 *
 * Written from `NSProgressIndicator.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSPROGRESSINDICATOR_H
#define APPKIT_NSPROGRESSINDICATOR_H

#import <AppKit/NSControl.h>

NS_ASSUME_NONNULL_BEGIN

/* `NSControlSize` AND `NSControlTint` COME WITH `NSCell.h`, which a control's header already reaches: they are the two
 * 10.0 appearance doors and a progress indicator answers both of them by name (the bar's height and the spinner's
 * stroke come from the SIZE, the fill's colour from the TINT). */

typedef NSInteger NSProgressIndicatorStyle;
enum {
	NSProgressIndicatorBarStyle = 0,
	NSProgressIndicatorSpinningStyle = 1
};

@interface NSProgressIndicator : NSControl <NSSecureCoding>
{
	double _minValue;
	double _maxValue;
	double _doubleValue;
	BOOL _indeterminate;
	BOOL _animating;
	BOOL _displayedWhenStopped;
	NSProgressIndicatorStyle _style;
	/* **AND THE FIVE PIECES THE SWEEP ADDS.** `_animationPhase` is where the spinner's arc is, in [0, 1) of a turn, and
	 * it is what makes `-animate:` a REAL door rather than a name: this tier has no animation timer, so a caller pumps
	 * the frames and each pump advances the arc by a twelfth of a turn. `_animationDelay` is the interval a driver should
	 * leave between those pumps (the class has no clock to apply it itself). `_controlSize` and `_controlTint` are the
	 * two appearance doors the drawing reads, and `_bezeled` is whether the bar draws its recess at all. */
	NSTimeInterval _animationDelay;
	double _animationPhase;
	NSControlSize _controlSize;
	NSControlTint _controlTint;
	BOOL _bezeled;
	BOOL _usesThreadedAnimation;
}
- (NSProgressIndicatorStyle)style;
- (void)setStyle:(NSProgressIndicatorStyle)style;

- (BOOL)isIndeterminate;
- (void)setIndeterminate:(BOOL)flag;

- (double)doubleValue;
- (void)setDoubleValue:(double)value;
- (void)incrementBy:(double)delta;

- (double)minValue;
- (void)setMinValue:(double)value;
- (double)maxValue;
- (void)setMaxValue:(double)value;

- (void)startAnimation:(nullable id)sender;
- (void)stopAnimation:(nullable id)sender;
- (BOOL)isAnimating;

- (BOOL)isDisplayedWhenStopped;
- (void)setDisplayedWhenStopped:(BOOL)flag;

/* **AND THE SPINNER'S ONE FRAME, WHICH IS THE DOOR A CALLER PUMPS.** Apple's `-animate:` advances the animation one
 * frame; this tier has no timer to do it on its own, so the door is real and the CALLER is the clock: each send moves
 * the arc a twelfth of a turn and redraws. `-animationDelay` is how long a driver should leave between sends, which is
 * `1/30` by default — a number this class cannot apply itself because nothing in it runs on a clock. */
- (void)animate:(nullable id)sender;
- (NSTimeInterval)animationDelay;
- (void)setAnimationDelay:(NSTimeInterval)delay;

/* **THE TWO APPEARANCE DOORS THE DRAWING READS.** The SIZE picks the spinner's inset and its stroke width (the bar's
 * own height is its frame, as it always was); the TINT picks the fill's colour, with the DEFAULT keeping the platform's
 * accent so a bar nobody tuned looks the way it always did. */
- (NSControlSize)controlSize;
- (void)setControlSize:(NSControlSize)size;
- (NSControlTint)controlTint;
- (void)setControlTint:(NSControlTint)tint;

/* **AND WHETHER THE BAR WEARS ITS RECESS.** `-isBezeled` YES draws the background, the frame and (for the bar) the
 * unfilled track — the picture this class has always drawn. NO draws the filled part alone, which is what a caller
 * putting the indicator on a plate of its own wants. */
- (BOOL)isBezeled;
- (void)setBezeled:(BOOL)flag;

/* **AND THE ONE NAMED REFUSAL OF THIS SLICE.** `-usesThreadedAnimation` asks for an animation driven by its own thread;
 * this tier has no thread and no timer for it, so the flag is refused by name when set to YES and the getter answers NO
 * — which is the truth of what is running, not a stored bit nobody honours. */
- (BOOL)usesThreadedAnimation;
- (void)setUsesThreadedAnimation:(BOOL)flag;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPROGRESSINDICATOR_H */
