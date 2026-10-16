/*
 * AGSwitchCell.m — the track, the knob, and the four fills.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import "AGSwitchCell.h"
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>

/* THE SAMPLE'S OWN MEASURES, as fractions of the track's HEIGHT so that a switch asked for at another size stays the
 * shape the sample draws: the knob is 12 of 20 points, and the air either side of it is the other 8. */
#define AG_SWITCH_ASPECT       1.6	/* 32/20: the track's width against the cell's own height */
#define AG_SWITCH_KNOB_FRACTION 0.6	/* 12/20 of the track's height, and round */

@implementation AGSwitchCell

/* **AND THE TRACK IS A PILL BECAUSE ITS RADIUS IS DERIVED RATHER THAN CHOSEN.** MEASURED on the sample: 32 x 20 with
 * both ends round, which is a radius of ten — half the height. A constant here would be right at one size and wrong at
 * every other, and the sample gives the SHAPE rather than a number to copy. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	BOOL on = ([self state] == NSOnState);
	CGFloat h = NSHeight(cellFrame);
	CGFloat radius = h / 2.0;
	CGFloat knob = h * AG_SWITCH_KNOB_FRACTION;
	NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:cellFrame xRadius:radius yRadius:radius];
	NSRect knobRect;
	NSColor *fill;

	(void)controlView;

	/* **AND THE FILL IS THE STATE, IN THE SAMPLE'S OWN FOUR.** The ORDER matters and is the sample's: being out of
	 * action wins over everything (a disabled switch does not prelight), and the pointer's shade only exists for a
	 * switch that is ON — because that is the only fill the sample draws it against, and because an OFF track is a GREY,
	 * where this tier's own rule applies instead: a grey-faced control the pointer rests on takes a step DOWN the same
	 * scale, which is `+cg_prelightControlFaceColor`. THE PRESS CHANGES NOTHING, which is also the sample's answer: its
	 * "Pressed" pill is the OFF track's own grey, so a press is acknowledged by the knob moving rather than by the track
	 * changing under it. */
	if (![self isEnabled]) {
		fill = [NSColor cg_disabledControlFaceColor];
	} else if (on) {
		fill = [self cg_mouseIsInside] ? [NSColor cg_accentPrelightColor] : [NSColor cg_accentColor];
	} else {
		fill = [self cg_mouseIsInside] ? [NSColor cg_prelightControlFaceColor] : [NSColor controlColor];
	}
	[fill setFill];
	[track fill];

	/* **AND THE KNOB SITS AT THE END THE VALUE SAYS, WHICH IS THE WHOLE OF WHAT A SWITCH SHOWS.** There is no text and
	 * no glyph: OFF is the knob at the left and ON is the knob at the right, and the two are the same circle a
	 * fraction of the height across, so the control reads at any size.
	 *
	 * **AND IT IS FLUSH WITH THE END, WHICH IS WHAT THE SAMPLE MEASURES RATHER THAN WHAT LOOKS TIDY.** MEASURED on its
	 * ON pill: the accent runs x=801..819 and the white knob x=822..833, so the track ENDS where the knob does and the
	 * knob's only inset is the vertical one that comes from being smaller than the track. Putting air at the ends as
	 * well would have been a guess, and the sample had an answer. */
	knobRect = NSMakeRect(on ? (NSMaxX(cellFrame) - knob) : NSMinX(cellFrame),
			      NSMidY(cellFrame) - knob / 2.0, knob, knob);
	[[NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithOvalInRect:knobRect] fill];
}

/* AND WHAT IT MEASURES: the sample's 32 x 20, taken from the height the caller asks for so that the aspect is the
 * sample's rather than a pair of numbers that happens to match it. The base's answer is kept for a NULL cell. */
- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = [super cellSizeForBounds:aRect];
	CGFloat h = NSHeight(aRect);

	if ([self type] != NSNullCellType && h > 0.0) {
		size = NSMakeSize(h * AG_SWITCH_ASPECT, h);
	}
	return size;
}

@end
