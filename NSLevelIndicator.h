/*
 * NSLevelIndicator.h — A BAR, A SET OF SEGMENTS OR A ROW OF STARS, SHOWING HOW FULL SOMETHING IS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A LEVEL INDICATOR IS A READ-ONLY MEASURE WITH A COLOUR OPINION.** It shows a value in a range the way a meter does —
 * continuously, as discrete segments, as a row of stars, or as a relevance bar — and it changes the fill's COLOUR at two
 * thresholds: `-warningValue:` and `-criticalValue:`. Above each threshold the ink becomes the platform's yellow or red,
 * which is the whole reason the class exists rather than a plain `NSProgressIndicator`: a progress bar says "how far", a level
 * indicator says "how far, and is that bad".
 *
 * **THE FOUR STYLES ARE FOUR PICTURES**, and the cell draws them:
 *
 *   NSContinuousCapacityLevelIndicatorStyle   a bar filled in proportion to the value
 *   NSDiscreteCapacityLevelIndicatorStyle     a row of segments, lit up to the value
 *   NSRatingLevelIndicatorStyle               stars — `-maxValue` of them, `-value` of them filled
 *   NSRelevancyLevelIndicatorStyle            a bar with a search-relevance shape (the same bar, in the accent colour)
 *
 * **THE THRESHOLD COLOURS ARE THE PLATFORM'S**, so a level indicator beside a progress bar and an alert does not invent a
 * third set of greens and reds.
 *
 * **AND THE VALUE PAIR IS OVERRIDDEN, BECAUSE `NSCell`'s IS A TEXT CELL'S.** `-setDoubleValue:` answers only for an
 * `NSTextCellType` cell, exactly as the stepper's slice found — so this cell keeps its own number and clamps it, and the
 * control's `-doubleValue` reaches that number through the cell.
 */
#ifndef APPKIT_NSLEVELINDICATOR_H
#define APPKIT_NSLEVELINDICATOR_H

#import <AppKit/NSControl.h>
#import <AppKit/NSActionCell.h>
#import <AppKit/NSCell.h>
/* FOR `NSTickMarkPosition`, which the slider cell's header declares — the same four positions a tick mark can take. */
#import <AppKit/NSSliderCell.h>

NS_ASSUME_NONNULL_BEGIN

@class NSImage;

/* THE FOUR STYLES, in Apple's order. */
typedef NSUInteger NSLevelIndicatorStyle;
enum {
	NSRelevancyLevelIndicatorStyle = 0,
	NSContinuousCapacityLevelIndicatorStyle = 1,
	NSDiscreteCapacityLevelIndicatorStyle = 2,
	NSRatingLevelIndicatorStyle = 3
};

/* ==================================================================================================================
 * THE CELL: THE VALUE, THE TWO THRESHOLDS, THE TICKS AND THE INK.
 * ================================================================================================================ */

@interface NSLevelIndicatorCell : NSActionCell
{
	NSLevelIndicatorStyle _levelIndicatorStyle;
	double _indicatorMinValue;
	double _indicatorMaxValue;
	double _warningValue;
	double _criticalValue;
	double _indicatorValue;		/* this cell's own, because NSCell's belongs to text cells */
	NSInteger _numberOfTickMarks;
	NSInteger _numberOfMajorTickMarks;
	NSTickMarkPosition _tickMarkPosition;
	NSImage *_indicatorImage;	/* RETAINED: the picture a RATING indicator uses instead of a star */
}

/* **THE STYLE IS THE INITIALISER'S ARGUMENT**, which is Apple's shape: a level indicator with no style is not a thing a caller
 * asks for, so the designated initialiser names it. */
- (instancetype)initWithLevelIndicatorStyle:(NSLevelIndicatorStyle)levelIndicatorStyle;

- (NSLevelIndicatorStyle)levelIndicatorStyle;
- (void)setLevelIndicatorStyle:(NSLevelIndicatorStyle)levelIndicatorStyle;

/* THE RANGE AND THE TWO THRESHOLDS. Setting either end re-clamps the standing value, because a value outside its range is not
 * a state this cell has; a threshold outside the range is clamped into it for the same reason. */
- (double)minValue;
- (void)setMinValue:(double)aDouble;
- (double)maxValue;
- (void)setMaxValue:(double)aDouble;
- (double)warningValue;
- (void)setWarningValue:(double)aDouble;
- (double)criticalValue;
- (void)setCriticalValue:(double)aDouble;

/* THE VALUE PAIR, OVERRIDDEN. See this header's note. */
- (double)doubleValue;
- (void)setDoubleValue:(double)aDouble;

/* **THE TICKS.** A count, how many of them are MAJOR (drawn longer), which side they sit on, and the two questions a caller
 * asks of one: what value it stands for and what rectangle it occupies. */
- (NSInteger)numberOfTickMarks;
- (void)setNumberOfTickMarks:(NSInteger)count;
- (NSInteger)numberOfMajorTickMarks;
- (void)setNumberOfMajorTickMarks:(NSInteger)count;
- (NSTickMarkPosition)tickMarkPosition;
- (void)setTickMarkPosition:(NSTickMarkPosition)position;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;

/* THE PICTURE A RATING INDICATOR USES FOR A FILLED STAR. There is no getter in Apple's 10.6 header, and there is none here. */
- (void)setImage:(nullable NSImage *)image;

@end

/* ==================================================================================================================
 * THE CONTROL: SIXTEEN FORWARDS.
 * ================================================================================================================ */

@interface NSLevelIndicator : NSControl <NSSecureCoding>

/* THE CELL, MADE AND INSTALLED — a continuous-capacity indicator, which is Apple's default for the control. */
- (instancetype)initWithFrame:(NSRect)frameRect;

- (double)minValue;
- (void)setMinValue:(double)aDouble;
- (double)maxValue;
- (void)setMaxValue:(double)aDouble;
- (double)warningValue;
- (void)setWarningValue:(double)aDouble;
- (double)criticalValue;
- (void)setCriticalValue:(double)aDouble;
- (NSInteger)numberOfTickMarks;
- (void)setNumberOfTickMarks:(NSInteger)count;
- (NSInteger)numberOfMajorTickMarks;
- (void)setNumberOfMajorTickMarks:(NSInteger)count;
- (NSTickMarkPosition)tickMarkPosition;
- (void)setTickMarkPosition:(NSTickMarkPosition)position;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLEVELINDICATOR_H */
