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
 * shape the sample draws. MEASURED, and the first pass over the sample got BOTH of these wrong by taking the knob's
 * edge for the track's: the track is 39 x 20 (its outline at x=752 and x=790 on one pill, x=799 and x=837 on the next),
 * and the knob is 15 across INCLUDING its ring, which leaves 2.5 of track showing on every side — the same band above
 * and below as beside. */
#define AG_SWITCH_ASPECT       1.95	/* 39/20: the track's width against the cell's own height */
#define AG_SWITCH_HEIGHT       20.0	/* the sample's 20 points tall, and the height the width is derived from */
#define AG_SWITCH_KNOB_FRACTION 0.75	/* 15/20 of the track's height, INCLUDING the ring drawn round it */
#define AG_SWITCH_OUTLINE      1.0	/* the track's edge and the knob's ring, both one point and both the border grey */

@implementation AGSwitchCell

/* **AND THE TRACK IS A PILL BECAUSE ITS RADIUS IS DERIVED RATHER THAN CHOSEN.** MEASURED on the sample: 32 x 20 with
 * both ends round, which is a radius of ten — half the height. A constant here would be right at one size and wrong at
 * every other, and the sample gives the SHAPE rather than a number to copy. */
/* **AND BOTH PIECES ARE OUTLINED, IN THE TIER'S ONE BORDER GREY.** MEASURED on the sample, and thrown away by the
 * first pass over it: every scan that looked for runs of three pixels or more MISSED the outlines, which are one point
 * wide — the track's at x=754 and x=789 and the tire height, the knob's at x=768, all `#BCBCBC`, which is
 * `+controlDarkShadowColor` and the same grey a bezel, a field's edge and a checkbox's box are drawn in.
 *
 * **AND THE RING IS WHAT MAKES THE KNOB VISIBLE, WHICH IS WHY THE SAMPLE NEEDS IT.** The knob's own fill at rest is
 * THE TRACK'S OWN COLOUR — `#E7E7E7` on `#E7E7E7`, measured — so a knob and a track of one grey are told apart by
 * nothing but the circle around the knob. This tier's control grey is `+controlColor`, the same kind of grey, and the
 * ring draws the knob rather than the fill doing it.
 *
 * **THE KNOB GOES WHITE WHEN IT IS DOING SOMETHING**: measured, the pressed pill's knob is `#FFFFFF` on a grey track,
 * and the sample's accent-filled pill's knob is white too. So the fill is white while the switch is held down or while
 * its track is the full accent, and the track's own grey otherwise. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	BOOL on = ([self state] == NSOnState);
	CGFloat h = NSHeight(cellFrame);
	CGFloat radius = h / 2.0;
	CGFloat knob = h * AG_SWITCH_KNOB_FRACTION;
	NSBezierPath *track;
	NSBezierPath *ring;
	NSRect knobRect;
	NSRect trackRect = NSInsetRect(cellFrame, AG_SWITCH_OUTLINE / 2.0, AG_SWITCH_OUTLINE / 2.0);
	NSColor *fill;
	NSColor *knobFill;

	(void)controlView;
	track = [NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:radius yRadius:radius];

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
	[[NSColor controlDarkShadowColor] setStroke];
	[track setLineWidth:AG_SWITCH_OUTLINE];
	[track stroke];

	/* **AND THE KNOB SITS AT THE END THE VALUE SAYS, WITH AN EVEN BAND OF TRACK SHOWING ALL ROUND IT.** There is no text
	 * and no glyph: OFF is the knob at the left and ON is the knob at the right, and the two are the same circle a
	 * fraction of the height across, so the control reads at any size.
	 *
	 * **AND THE BAND IS THE SAME ON EVERY SIDE, WHICH IS WHAT THE SAMPLE MEASURES RATHER THAN WHAT FILLS THE ROOM.** The
	 * first pass said the knob was FLUSH with its end, having taken the knob's edge for the track's; measuring the
	 * outlines instead puts the track at 39 wide and the knob at 15 of it, so the air beside the knob is 2.5 — the same
	 * as the air above and below, which comes from the knob being smaller than the track. A knob that touched the end
	 * would have been a knob with its own outline sitting on the track's, which is what an even band avoids. */
	CGFloat knobInset = (h - knob) / 2.0;

	knobRect = NSMakeRect(on ? (NSMaxX(trackRect) - knobInset - knob) : (NSMinX(trackRect) + knobInset),
			      NSMidY(cellFrame) - knob / 2.0, knob, knob);
	knobFill = ([self isHighlighted] || (on && ![self cg_mouseIsInside]))
		   ? [NSColor controlBackgroundColor] : [NSColor controlColor];
	[knobFill setFill];
	[[NSBezierPath bezierPathWithOvalInRect:knobRect] fill];
	ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(knobRect, AG_SWITCH_OUTLINE / 2.0,
								  AG_SWITCH_OUTLINE / 2.0)];
	[[NSColor controlDarkShadowColor] setStroke];
	[ring setLineWidth:AG_SWITCH_OUTLINE];
	[ring stroke];
}

/* **AND WHAT IT MEASURES IS THE SAMPLE'S 32 x 20, WITH THE CALLER'S RECT AS A BOUND RATHER THAN AS AN INPUT.** That is
the base's own contract — "a caller's rectangle is the bound", see `NSCell -cellSizeForBounds:` — and MEASURED, the
first draft broke it by deriving the height FROM the rect: `-sizeToFit` reaches this door through `-cellSize`, which
asks with the NO-OPINION rectangle of 10000 x 10000, so the switch was fitted to 16000 points across and the
demonstration drew nothing at all. A rect SMALLER than the natural size still clamps, which is what a bound means.
 *
 * AND A CALLER WHO WANTS A BIGGER SWITCH SETS A BIGGER FRAME: the drawing reads the frame it is handed and takes its
 * radius and its knob as fractions of that, so a switch drawn into a taller rectangle comes out proportionally larger
 * even though its measured size is the sample's. */
- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = NSMakeSize(AG_SWITCH_HEIGHT * AG_SWITCH_ASPECT, AG_SWITCH_HEIGHT);

	if (size.width > NSWidth(aRect)) {
		size.width = NSWidth(aRect);
	}
	if (size.height > NSHeight(aRect)) {
		size.height = NSHeight(aRect);
	}
	return size;
}

@end
