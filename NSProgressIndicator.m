/*
 * NSProgressIndicator.m — the bar, the track and the clamped value.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import <AppKit/NSProgressIndicator.h>

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>

#include <math.h>

@implementation NSProgressIndicator

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_minValue = 0.0;
		_maxValue = 100.0;
		_doubleValue = 0.0;
		_style = NSProgressIndicatorBarStyle;
		_displayedWhenStopped = YES;
	}
	return self;
}

- (NSProgressIndicatorStyle)style { return _style; }
- (void)setStyle:(NSProgressIndicatorStyle)style { _style = style; [self setNeedsDisplay:YES]; }

- (BOOL)isIndeterminate { return _indeterminate; }
- (void)setIndeterminate:(BOOL)flag
{
	_indeterminate = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (double)doubleValue { return _doubleValue; }

- (void)setDoubleValue:(double)value
{
	if (value < _minValue) value = _minValue;
	if (value > _maxValue) value = _maxValue;
	_doubleValue = value;
	[self setNeedsDisplay:YES];
}

- (void)incrementBy:(double)delta
{
	[self setDoubleValue:_doubleValue + delta];
}

- (double)minValue { return _minValue; }

- (void)setMinValue:(double)value
{
	_minValue = value;
	if (_maxValue < _minValue) _maxValue = _minValue;
	[self setDoubleValue:_doubleValue];
}

- (double)maxValue { return _maxValue; }

- (void)setMaxValue:(double)value
{
	_maxValue = value;
	if (_minValue > _maxValue) _minValue = _maxValue;
	[self setDoubleValue:_doubleValue];
}

- (void)startAnimation:(id)sender
{
	(void)sender;
	_animating = YES;
	[self setNeedsDisplay:YES];
}

- (void)stopAnimation:(id)sender
{
	(void)sender;
	_animating = NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)isAnimating { return _animating; }

- (BOOL)isDisplayedWhenStopped { return _displayedWhenStopped; }
- (void)setDisplayedWhenStopped:(BOOL)flag
{
	_displayedWhenStopped = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	NSRect track = NSInsetRect(bounds, 1.0, 1.0);

	(void)dirtyRect;
	if (_style == NSProgressIndicatorSpinningStyle) {
		NSRect box = NSInsetRect(bounds, 3.0, 3.0);
		CGFloat radius = (box.size.width < box.size.height ? box.size.width : box.size.height) / 2.0;

		[[NSColor colorWithCalibratedWhite:0.55 alpha:1.0] setStroke];
		[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, radius * 0.25, radius * 0.25)] stroke];
		if (_animating) {
			[[NSColor controlDarkShadowColor] setStroke];
			[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, radius * 0.55, radius * 0.55)] stroke];
		}
		return;
	}

	[[NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:track] fill];
	[[NSColor controlDarkShadowColor] setStroke];
	[[NSBezierPath bezierPathWithRect:track] stroke];
	if (!_indeterminate && _maxValue > _minValue) {
		CGFloat fraction = (CGFloat)((_doubleValue - _minValue) / (_maxValue - _minValue));
		NSRect fill = track;

		fill.size.width = floor(track.size.width * (fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction)));
		[[NSColor cg_accentColor] setFill];
		[[NSBezierPath bezierPathWithRect:fill] fill];
	}
}

@end
