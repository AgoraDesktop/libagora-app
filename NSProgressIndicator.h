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

typedef NSInteger NSProgressIndicatorStyle;
enum {
	NSProgressIndicatorBarStyle = 0,
	NSProgressIndicatorSpinningStyle = 1
};

@interface NSProgressIndicator : NSControl
{
	double _minValue;
	double _maxValue;
	double _doubleValue;
	BOOL _indeterminate;
	BOOL _animating;
	BOOL _displayedWhenStopped;
	NSProgressIndicatorStyle _style;
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
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPROGRESSINDICATOR_H */
