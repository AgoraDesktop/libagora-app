/*
 * AGSwitch.m — the control: a cell, a value, and one press.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import "AGSwitch.h"
#import "AGSwitchCell.h"
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

@implementation AGSwitch

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		AGSwitchCell *cell = [[AGSwitchCell alloc] initTextCell:@""];

		[cell setBordered:NO];
		[cell setBezeled:NO];
		[cell setState:NSOffState];
		[self setCell:cell];
		[cell release];
		if (frameRect.size.width <= 0.0 || frameRect.size.height <= 0.0) {
			[self sizeToFit];
		}
	}
	return self;
}

- (NSInteger)state
{
	return [[self cell] state];
}

- (void)setState:(NSInteger)state
{
	[[self cell] setState:state];
	[self setNeedsDisplay:YES];
}

/* **AND A PRESS FLIPS THE VALUE AND THEN LETS THE BASE DO THE REST.** `NSControl -mouseDown:` is the tier's tracking
 * loop — it highlights the cell, follows the pointer and sends the action on the RELEASE — and a switch that ran its
 * own loop would be a second copy of that machinery, which is the mistake this unit keeps finding in other shapes. So
 * the state is flipped FIRST, on the press, and the action the base sends on release then carries the value the person
 * just set rather than the one they were looking at.
 *
 * WHAT IS NOT HERE AND IS NAMED RATHER THAN PRETENDED: dragging the pointer back off the switch before releasing does
 * NOT put the value back — the flip has already happened — where a Mac's own switch treats that as "never mind". That
 * needs the release's location, and it is the next thing this control owes. */
- (void)mouseDown:(NSEvent *)event
{
	[self setState:([[self cell] state] == NSOnState ? NSOffState : NSOnState)];
	[super mouseDown:event];
}

@end
