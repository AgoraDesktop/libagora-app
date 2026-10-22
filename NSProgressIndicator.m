/*
 * NSProgressIndicator.m — the bar, the track and the clamped value.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
#import <AppKit/NSProgressIndicator.h>

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import "AppKitRefusal.h"

#include <math.h>

@implementation NSProgressIndicator

/* ============================================================================================
 * ARCHIVING: THE RANGE, THE STYLE AND WHETHER IT SPINS.
 * ============================================================================================ */
/* **THIS ONE IS ALL DESIGN, WHICH IS THE OTHER HALF OF THE POINT.** An indicator has no cell in this tier: its range, its
 * value, its style and whether it is determinate are its OWN state, so every one of them is here. `_animating` is
 * included because "spins when the window opens" is a design decision, not a timestamp. */
static NSString * const AGCoderProgressMinKey = @"minValue";
static NSString * const AGCoderProgressMaxKey = @"maxValue";
static NSString * const AGCoderProgressValueKey = @"doubleValue";
static NSString * const AGCoderProgressIndeterminateKey = @"indeterminate";
static NSString * const AGCoderProgressAnimatingKey = @"animating";
static NSString * const AGCoderProgressDisplayedKey = @"displayedWhenStopped";
static NSString * const AGCoderProgressStyleKey = @"style";
static NSString * const AGCoderProgressDelayKey = @"animationDelay";
static NSString * const AGCoderProgressPhaseKey = @"animationPhase";
static NSString * const AGCoderProgressSizeKey = @"controlSize";
static NSString * const AGCoderProgressTintKey = @"controlTint";
static NSString * const AGCoderProgressBezeledKey = @"bezeled";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeDouble:_minValue forKey:AGCoderProgressMinKey];
	[aCoder encodeDouble:_maxValue forKey:AGCoderProgressMaxKey];
	[aCoder encodeDouble:_doubleValue forKey:AGCoderProgressValueKey];
	[aCoder encodeBool:_indeterminate forKey:AGCoderProgressIndeterminateKey];
	[aCoder encodeBool:_animating forKey:AGCoderProgressAnimatingKey];
	[aCoder encodeBool:_displayedWhenStopped forKey:AGCoderProgressDisplayedKey];
	[aCoder encodeInteger:(NSInteger)_style forKey:AGCoderProgressStyleKey];
	[aCoder encodeDouble:_animationDelay forKey:AGCoderProgressDelayKey];
	[aCoder encodeDouble:_animationPhase forKey:AGCoderProgressPhaseKey];
	[aCoder encodeInteger:(NSInteger)_controlSize forKey:AGCoderProgressSizeKey];
	[aCoder encodeInteger:(NSInteger)_controlTint forKey:AGCoderProgressTintKey];
	[aCoder encodeBool:_bezeled forKey:AGCoderProgressBezeledKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderProgressMinKey]) {
		_minValue = [aDecoder decodeDoubleForKey:AGCoderProgressMinKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressMaxKey]) {
		_maxValue = [aDecoder decodeDoubleForKey:AGCoderProgressMaxKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressValueKey]) {
		_doubleValue = [aDecoder decodeDoubleForKey:AGCoderProgressValueKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressIndeterminateKey]) {
		_indeterminate = [aDecoder decodeBoolForKey:AGCoderProgressIndeterminateKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressAnimatingKey]) {
		_animating = [aDecoder decodeBoolForKey:AGCoderProgressAnimatingKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressDisplayedKey]) {
		_displayedWhenStopped = [aDecoder decodeBoolForKey:AGCoderProgressDisplayedKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressStyleKey]) {
		_style = (NSProgressIndicatorStyle)[aDecoder decodeIntegerForKey:AGCoderProgressStyleKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressDelayKey]) {
		_animationDelay = [aDecoder decodeDoubleForKey:AGCoderProgressDelayKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressPhaseKey]) {
		_animationPhase = [aDecoder decodeDoubleForKey:AGCoderProgressPhaseKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressSizeKey]) {
		_controlSize = (NSControlSize)[aDecoder decodeIntegerForKey:AGCoderProgressSizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressTintKey]) {
		_controlTint = (NSControlTint)[aDecoder decodeIntegerForKey:AGCoderProgressTintKey];
	}
	if ([aDecoder containsValueForKey:AGCoderProgressBezeledKey]) {
		_bezeled = [aDecoder decodeBoolForKey:AGCoderProgressBezeledKey];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_minValue = 0.0;
		_maxValue = 100.0;
		_doubleValue = 0.0;
		_style = NSProgressIndicatorBarStyle;
		_displayedWhenStopped = YES;
		/* **AND THE FOUR DEFAULTS THAT ARE NOT ZERO.** A bar is BEZELED unless told otherwise (the recess is the era's
		 * picture), it is REGULAR sized, it wears the DEFAULT tint — which is the accent, see `fn_fillColor` — and a
		 * frame's delay is a thirtieth of a second, Apple's own cadence for this control. The phase's zero IS correct. */
		_bezeled = YES;
		_controlSize = NSRegularControlSize;
		_controlTint = NSDefaultControlTint;
		_animationDelay = 1.0 / 30.0;
		_usesThreadedAnimation = NO;
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

/* ---- THE SPINNER'S FRAME, AND THE TWO APPEARANCE DOORS -------------------------------------------- */

- (void)animate:(id)sender
{
	(void)sender;
	/* **ONE FRAME IS A TWELFTH OF A TURN**, which is where a spinner's twelve positions come from; the phase is kept in
	 * [0, 1) so a caller pumping this a thousand times never loses precision to a growing angle. See the header on why
	 * the caller is the clock: `-animationDelay` is the interval it should use, and nothing here can apply it. */
	_animationPhase = fmod(_animationPhase + 1.0 / 12.0, 1.0);
	if (_animationPhase < 0.0) {
		_animationPhase += 1.0;
	}
	[self setNeedsDisplay:YES];
}

- (NSTimeInterval)animationDelay { return _animationDelay; }
- (void)setAnimationDelay:(NSTimeInterval)delay
{
	_animationDelay = (delay > 0.0) ? delay : 1.0 / 30.0;
}

- (NSControlSize)controlSize { return _controlSize; }
- (void)setControlSize:(NSControlSize)size
{
	_controlSize = size;
	[self setNeedsDisplay:YES];
}

- (NSControlTint)controlTint { return _controlTint; }
- (void)setControlTint:(NSControlTint)tint
{
	_controlTint = tint;
	[self setNeedsDisplay:YES];
}

- (BOOL)isBezeled { return _bezeled; }
- (void)setBezeled:(BOOL)flag
{
	_bezeled = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)usesThreadedAnimation
{
	/* THE TRUTH OF WHAT IS RUNNING: there is no animation thread, so there is nothing to answer YES about. */
	return NO;
}

- (void)setUsesThreadedAnimation:(BOOL)flag
{
	if (flag) {
		fn_refuse_window("-[NSProgressIndicator setUsesThreadedAnimation:]",
				 "an animation thread (this tier has no timer; `-animate:` is pumped by the caller, one frame a send)");
	}
	_usesThreadedAnimation = NO;
}

/* **THE TWO APPEARANCE NUMBERS, WHICH THE DRAWING ASKS FOR RATHER THAN REPEATING.** The spinner's inset and its
 * stroke's width are the only things a control size changes here: the BAR's height is its frame, as it has always been,
 * because a determinate bar is sized by the caller's layout rather than by a control metric. */
- (CGFloat)fn_spinnerInset
{
	switch (_controlSize) {
	case NSSmallControlSize:
		return 2.0;
	case NSMiniControlSize:
		return 1.0;
	case NSRegularControlSize:
	default:
		return 3.0;
	}
}

- (CGFloat)fn_spinnerStroke
{
	return (_controlSize == NSMiniControlSize) ? 0.75 : 1.0;
}

/* **AND THE FILL'S COLOUR, WHICH IS WHERE THE TINT IS HONOURED.** The DEFAULT is the platform's accent — the same
 * colour a selection wears — and asking for a tint asks for that tint's colour out of `NSColor`, which is the tree's
 * one table of them. A CLEAR tint is a real answer there, not a synonym for the default. */
- (NSColor *)fn_fillColor
{
	if (_controlTint == NSDefaultControlTint) {
		return [NSColor cg_accentColor];
	}
	return [NSColor colorForControlTint:_controlTint];
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	NSRect track = NSInsetRect(bounds, 1.0, 1.0);

	(void)dirtyRect;
	if (_style == NSProgressIndicatorSpinningStyle) {
		NSRect box = NSInsetRect(bounds, [self fn_spinnerInset], [self fn_spinnerInset]);
		CGFloat radius = (box.size.width < box.size.height ? box.size.width : box.size.height) / 2.0;
		CGFloat stroke = [self fn_spinnerStroke];
		NSRect ring = NSInsetRect(box, radius * 0.25, radius * 0.25);

		/* **A SPINNER IS A TRACK RING AND ONE ARC, AND THE ARC IS THE ONE THING THAT MOVES.** The old drawing had two
		 * concentric circles and a state bit, which said only "spinning" or "stopped" — it could not show a FRAME.
		 * `-animate:` advances `_animationPhase`, and the arc's START is a quarter turn plus that phase, so a caller
		 * pumping frames sees the gap go round. A stopped spinner keeps its arc where it stops, which is why the
		 * phase is not reset by `-stopAnimation:`. */
		[[NSColor colorWithCalibratedWhite:0.55 alpha:1.0] setStroke];
		{
			NSBezierPath *outer = [NSBezierPath bezierPathWithOvalInRect:ring];

			[outer setLineWidth:stroke];
			[outer stroke];
		}
		if (_animating) {
			NSBezierPath *arc = [NSBezierPath bezierPath];
			CGFloat start = 90.0 + _animationPhase * 360.0;

			[[self fn_fillColor] setStroke];
			[arc setLineWidth:stroke];
			[arc appendBezierPathWithArcWithCenter:NSMakePoint(NSMidX(ring), NSMidY(ring))
							radius:(NSWidth(ring) < NSHeight(ring) ? NSWidth(ring) : NSHeight(ring)) / 2.0
						     startAngle:start endAngle:start + 270.0];
			[arc stroke];
		}
		return;
	}

	/* **AND THE BAR: A RECESS, A FILL, AND A BORDER — OR JUST THE FILL WHEN IT IS NOT BEZELED.** The recess is what
	 * `-isBezeled` means, so turning it off removes the background and the frame with it and leaves the coloured part on
	 * whatever the caller put behind it. */
	if (_bezeled) {
		[[NSColor controlBackgroundColor] setFill];
		[[NSBezierPath bezierPathWithRect:track] fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[[NSBezierPath bezierPathWithRect:track] stroke];
	}
	if (!_indeterminate && _maxValue > _minValue) {
		CGFloat fraction = (CGFloat)((_doubleValue - _minValue) / (_maxValue - _minValue));
		NSRect fill = _bezeled ? track : NSInsetRect(bounds, 0.0, 0.0);

		fill.size.width = floor(fill.size.width * (fraction < 0.0 ? 0.0 : (fraction > 1.0 ? 1.0 : fraction)));
		[[self fn_fillColor] setFill];
		[[NSBezierPath bezierPathWithRect:fill] fill];
	}
}

@end
