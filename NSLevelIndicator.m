/*
 * NSLevelIndicator — a bar, a set of segments or a row of stars, showing how full something is.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The cell owns the range, the two thresholds, the value and the ticks; the control forwards. The drawing is one function of
 * the style, and the colour is a function of how the value compares with the thresholds — which is the class's whole opinion.
 */
#import "NSLevelIndicator.h"
#import "NSColor.h"
#import "NSImage.h"
#import "NSFont.h"
#import "NSBezierPath.h"
#import "NSGraphics.h"
#import "NSGraphicsContext.h"
#import "NSStringDrawing.h"
#import "NSAttributedString.h"

/* THE INK'S THREE COLOURS. The platform's own, so a level indicator, a progress bar and an alert agree about what "bad" is. */
static NSColor *fn_level_colour(double value, double warning, double critical)
{
	if (critical > 0.0 && value >= critical) {
		return [NSColor redColor];
	}
	if (warning > 0.0 && value >= warning) {
		return [NSColor orangeColor];
	}
	return [NSColor greenColor];
}

@implementation NSLevelIndicatorCell

- (instancetype)initWithLevelIndicatorStyle:(NSLevelIndicatorStyle)levelIndicatorStyle
{
	self = [super init];
	if (self != nil) {
		_levelIndicatorStyle = levelIndicatorStyle;
		/* **APPLE'S DEFAULTS: 0 to 100, with both thresholds at zero** — which means "no threshold", so a fresh indicator is
		 * green at every value. A threshold of zero that turned the bar red at once would make the default useless. */
		_indicatorMinValue = 0.0;
		_indicatorMaxValue = 100.0;
		_warningValue = 0.0;
		_criticalValue = 0.0;
		_indicatorValue = 0.0;
		_numberOfTickMarks = 0;
		_numberOfMajorTickMarks = 0;
		_tickMarkPosition = NSTickMarkBelow;
		_indicatorImage = nil;
	}
	return self;
}

- (void)dealloc
{
	[_indicatorImage release];
	[super dealloc];
}

- (NSLevelIndicatorStyle)levelIndicatorStyle { return _levelIndicatorStyle; }
- (void)setLevelIndicatorStyle:(NSLevelIndicatorStyle)style { _levelIndicatorStyle = style; }

/* ---- THE RANGE AND THE THRESHOLDS ----------------------------------------------------------------- */

- (double)minValue { return _indicatorMinValue; }
- (void)setMinValue:(double)aDouble
{
	_indicatorMinValue = aDouble;
	if (_indicatorMaxValue < _indicatorMinValue) {
		_indicatorMaxValue = _indicatorMinValue;
	}
	[self setDoubleValue:_indicatorValue];	/* re-clamped */
}

- (double)maxValue { return _indicatorMaxValue; }
- (void)setMaxValue:(double)aDouble
{
	_indicatorMaxValue = aDouble;
	if (_indicatorMinValue > _indicatorMaxValue) {
		_indicatorMinValue = _indicatorMaxValue;
	}
	[self setDoubleValue:_indicatorValue];
}

- (double)warningValue { return _warningValue; }
- (void)setWarningValue:(double)aDouble { _warningValue = aDouble; }
- (double)criticalValue { return _criticalValue; }
- (void)setCriticalValue:(double)aDouble { _criticalValue = aDouble; }

/* **THE VALUE, OVERRIDDEN AND CLAMPED.** `NSCell -setDoubleValue:` refuses for a cell that is not a text cell, so the number
 * lives here; and a value outside the range is not a state an indicator has, so the clamp is at the one door every write goes
 * through. */
- (double)doubleValue
{
	return _indicatorValue;
}

- (void)setDoubleValue:(double)aDouble
{
	if (aDouble < _indicatorMinValue) {
		aDouble = _indicatorMinValue;
	}
	if (aDouble > _indicatorMaxValue) {
		aDouble = _indicatorMaxValue;
	}
	_indicatorValue = aDouble;
}

/* ---- THE TICKS ------------------------------------------------------------------------------------ */

- (NSInteger)numberOfTickMarks { return _numberOfTickMarks; }
- (void)setNumberOfTickMarks:(NSInteger)count { _numberOfTickMarks = (count > 0) ? count : 0; }
- (NSInteger)numberOfMajorTickMarks { return _numberOfMajorTickMarks; }
- (void)setNumberOfMajorTickMarks:(NSInteger)count { _numberOfMajorTickMarks = (count > 0) ? count : 0; }
- (NSTickMarkPosition)tickMarkPosition { return _tickMarkPosition; }
- (void)setTickMarkPosition:(NSTickMarkPosition)position { _tickMarkPosition = position; }

/* **THE VALUE A TICK STANDS FOR**: the range divided evenly, the first tick at the minimum. A count of N marks therefore has
 * N - 1 intervals, which is what makes a tick sit at each END as well as between. */
- (double)tickMarkValueAtIndex:(NSInteger)index
{
	double span = _indicatorMaxValue - _indicatorMinValue;

	if (_numberOfTickMarks <= 0 || index < 0 || index >= _numberOfTickMarks) {
		return _indicatorMinValue;
	}
	if (_numberOfTickMarks == 1) {
		return _indicatorMinValue;
	}
	return _indicatorMinValue + span * (double)index / (double)(_numberOfTickMarks - 1);
}

/* AND ITS RECTANGLE: a one-point mark at the tick's place along the bar, on the side the position names. */
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index
{
	double span = _indicatorMaxValue - _indicatorMinValue;
	NSRect bounds = NSMakeRect(0.0, 0.0, 100.0, 20.0);	/* the cell's own frame is given at draw time */
	NSRect mark;
	CGFloat fraction;
	NSTickMarkPosition position = _tickMarkPosition;

	(void)position;
	if (_numberOfTickMarks <= 0 || index < 0 || index >= _numberOfTickMarks) {
		return NSZeroRect;
	}
	fraction = (span > 0.0) ? (CGFloat)(([self tickMarkValueAtIndex:index] - _indicatorMinValue) / span) : 0.0;
	mark = NSMakeRect(NSMinX(bounds) + fraction * (NSWidth(bounds) - 1.0), NSMaxY(bounds) - 3.0, 1.0, 3.0);
	return mark;
}

- (void)setImage:(NSImage *)image
{
	NSImage *held = [image retain];

	[_indicatorImage release];
	_indicatorImage = held;
}

/* ---- THE INK ------------------------------------------------------------------------------------ */

/* **THE FILL'S FRACTION**, which every style needs: how far the value is between the ends. A zero-width range is answered as
 * full, because a range with no span has nothing to be part-way through. */
- (CGFloat)cg_fraction
{
	double span = _indicatorMaxValue - _indicatorMinValue;

	if (span <= 0.0) {
		return 1.0;
	}
	return (CGFloat)((_indicatorValue - _indicatorMinValue) / span);
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSColor *ink = fn_level_colour(_indicatorValue, _warningValue, _criticalValue);
	NSRect face = NSInsetRect(cellFrame, 1.0, 1.0);
	CGFloat fraction = [self cg_fraction];

	(void)controlView;
	/* THE GROUND AND THE BORDER, the same shape a field uses. */
	[[NSColor controlColor] setFill];
	[[NSBezierPath bezierPathWithRect:face] fill];
	[[NSColor controlDarkShadowColor] setStroke];
	[[NSBezierPath bezierPathWithRect:NSInsetRect(face, 0.5, 0.5)] stroke];

	switch (_levelIndicatorStyle) {
	case NSDiscreteCapacityLevelIndicatorStyle: {
		/* **SEGMENTS, ONE PER TICK** (or one per unit when there are no ticks), lit up to the value. */
		NSInteger segments = (_numberOfTickMarks > 0) ? _numberOfTickMarks : (NSInteger)_indicatorMaxValue;
		NSInteger lit = (NSInteger)floor((double)fraction * (double)segments + 0.5);
		NSInteger i;

		if (segments <= 0) {
			break;
		}
		for (i = 0; i < segments; i++) {
			CGFloat w = NSWidth(face) / (CGFloat)segments;
			NSRect segment = NSMakeRect(NSMinX(face) + w * (CGFloat)i + 1.0, NSMinY(face) + 2.0,
						    w - 2.0, NSHeight(face) - 4.0);

			[((i < lit) ? ink : [NSColor controlShadowColor]) setFill];
			NSRectFill(segment);
		}
		break;
	}
	case NSRatingLevelIndicatorStyle: {
		/* **STARS: `-maxValue` of them, `-value` filled.** The glyph is the font's, and a caller's image replaces it. */
		NSInteger stars = (NSInteger)_indicatorMaxValue;
		NSInteger filled = (NSInteger)floor((double)fraction * (double)stars + 0.5);
		NSInteger i;
		CGFloat w;

		if (stars <= 0) {
			break;
		}
		w = NSWidth(face) / (CGFloat)stars;
		for (i = 0; i < stars; i++) {
			NSRect slot = NSMakeRect(NSMinX(face) + w * (CGFloat)i, NSMinY(face), w, NSHeight(face));

			if (i < filled) {
				if (_indicatorImage != nil) {
					[_indicatorImage drawInRect:NSInsetRect(slot, 1.0, 1.0)];
				} else {
					NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
						ink, NSForegroundColorAttributeName, nil];

					[@"\u2605" drawAtPoint:NSMakePoint(NSMinX(slot) + 1.0, NSMinY(slot) + 1.0)
						withAttributes:attributes];
				}
			} else {
				NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
					[NSColor controlShadowColor], NSForegroundColorAttributeName, nil];

				[@"\u2605" drawAtPoint:NSMakePoint(NSMinX(slot) + 1.0, NSMinY(slot) + 1.0)
					withAttributes:attributes];
			}
		}
		break;
	}
	case NSRelevancyLevelIndicatorStyle:
	case NSContinuousCapacityLevelIndicatorStyle:
	default: {
		/* **ONE BAR**, filled in proportion; the relevancy style is the same bar in the accent colour, which is what makes it
		 * read as "how relevant" rather than "how full". */
		NSRect filledRect = NSMakeRect(NSMinX(face) + 1.0, NSMinY(face) + 1.0,
					       (NSWidth(face) - 2.0) * fraction, NSHeight(face) - 2.0);

		[(_levelIndicatorStyle == NSRelevancyLevelIndicatorStyle) ? [NSColor selectedControlColor] : ink setFill];
		if (NSWidth(filledRect) > 0.0) {
			NSRectFill(filledRect);
		}
		break;
	}
	}
	/* AND THE TICK MARKS ABOVE THE FILL, so they read against it either way. */
	{
		NSInteger i;

		[[NSColor controlTextColor] setFill];
		for (i = 0; i < _numberOfTickMarks; i++) {
			double span = _indicatorMaxValue - _indicatorMinValue;
			CGFloat where = (span > 0.0)
				? (CGFloat)(([self tickMarkValueAtIndex:i] - _indicatorMinValue) / span) : 0.0;
			CGFloat x = NSMinX(face) + 1.0 + where * (NSWidth(face) - 2.0);
			CGFloat height = (i < _numberOfMajorTickMarks) ? 4.0 : 2.0;

			NSRectFill(NSMakeRect(x, NSMinY(face) + 1.0, 1.0, height));
		}
	}
}

@end

/* ==================================================================================================================
 * THE CONTROL.
 * ================================================================================================================ */

@implementation NSLevelIndicator

- (instancetype)initWithFrame:(NSRect)frameRect
{
	NSLevelIndicatorCell *cell = [[NSLevelIndicatorCell alloc]
		initWithLevelIndicatorStyle:NSContinuousCapacityLevelIndicatorStyle];

	self = [super initWithFrame:frameRect];
	if (self != nil) {
		[self setCell:cell];
	}
	[cell release];
	return self;
}

- (NSLevelIndicatorCell *)cg_levelCell
{
	id cell = [self cell];

	return [cell isKindOfClass:[NSLevelIndicatorCell class]] ? (NSLevelIndicatorCell *)cell : nil;
}

- (double)minValue { return [[self cg_levelCell] minValue]; }
- (void)setMinValue:(double)aDouble { [[self cg_levelCell] setMinValue:aDouble]; }
- (double)maxValue { return [[self cg_levelCell] maxValue]; }
- (void)setMaxValue:(double)aDouble { [[self cg_levelCell] setMaxValue:aDouble]; }
- (double)warningValue { return [[self cg_levelCell] warningValue]; }
- (void)setWarningValue:(double)aDouble { [[self cg_levelCell] setWarningValue:aDouble]; }
- (double)criticalValue { return [[self cg_levelCell] criticalValue]; }
- (void)setCriticalValue:(double)aDouble { [[self cg_levelCell] setCriticalValue:aDouble]; }
- (NSInteger)numberOfTickMarks { return [[self cg_levelCell] numberOfTickMarks]; }
- (void)setNumberOfTickMarks:(NSInteger)count { [[self cg_levelCell] setNumberOfTickMarks:count]; }
- (NSInteger)numberOfMajorTickMarks { return [[self cg_levelCell] numberOfMajorTickMarks]; }
- (void)setNumberOfMajorTickMarks:(NSInteger)count { [[self cg_levelCell] setNumberOfMajorTickMarks:count]; }
- (NSTickMarkPosition)tickMarkPosition { return [[self cg_levelCell] tickMarkPosition]; }
- (void)setTickMarkPosition:(NSTickMarkPosition)position { [[self cg_levelCell] setTickMarkPosition:position]; }
- (double)tickMarkValueAtIndex:(NSInteger)index { return [[self cg_levelCell] tickMarkValueAtIndex:index]; }
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index { return [[self cg_levelCell] rectOfTickMarkAtIndex:index]; }

@end
