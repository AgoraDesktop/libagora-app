/*
 * NSStepper — the shell around its cell.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * Ten doors, all forwards. The initialiser makes the cell; everything else answers it or tells it, which is the same rule
 * `NSSlider` records: a control whose face is its cell should not also keep the values.
 */
#import "NSStepper.h"
#import "NSStepperCell.h"
#import "NSCell.h"

@implementation NSStepper

- (instancetype)initWithFrame:(NSRect)frameRect
{
	NSStepperCell *cell = [[NSStepperCell alloc] init];

	self = [super initWithFrame:frameRect];
	if (self != nil) {
		[self setCell:cell];
	}
	[cell release];
	return self;
}

/* THE CELL THE FORWARDS REACH, typed — and nil when a caller replaced the cell with something else, which is why every
 * door below checks the class rather than assuming. */
- (NSStepperCell *)cg_stepperCell
{
	id cell = [self cell];

	return [cell isKindOfClass:[NSStepperCell class]] ? (NSStepperCell *)cell : nil;
}

- (double)minValue
{
	return [[self cg_stepperCell] minValue];
}

- (void)setMinValue:(double)aDouble
{
	[[self cg_stepperCell] setMinValue:aDouble];
}

- (double)maxValue
{
	return [[self cg_stepperCell] maxValue];
}

- (void)setMaxValue:(double)aDouble
{
	[[self cg_stepperCell] setMaxValue:aDouble];
}

- (double)increment
{
	return [[self cg_stepperCell] increment];
}

- (void)setIncrement:(double)increment
{
	[[self cg_stepperCell] setIncrement:increment];
}

- (BOOL)valueWraps
{
	return [[self cg_stepperCell] valueWraps];
}

- (void)setValueWraps:(BOOL)flag
{
	[[self cg_stepperCell] setValueWraps:flag];
}

- (BOOL)autorepeat
{
	return [[self cg_stepperCell] autorepeat];
}

- (void)setAutorepeat:(BOOL)flag
{
	[[self cg_stepperCell] setAutorepeat:flag];
}

@end
