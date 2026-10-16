/*
 * control_switch.m — A TRACK, A KNOB, AND THE FOUR STATES THE SAMPLE DRAWS.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS PROBE NEEDS NO FONT, WHICH MAKES IT THE FIRST CONTROL HERE THAT IS FULLY CHECKABLE OFFSCREEN.** A switch has
 * no text at all: its value is where the knob is and its state is what the track is filled with, and both are pixels
 * this can read out of a bitmap. So every claim below is a MEASUREMENT rather than a comparison that happens to hold
 * for want of a font registry.
 *
 * THE NUMBERS ARE THE SAMPLE'S. `Argentum Mockup.png` draws four switches beside its four-state legend — x=756..787,
 * y=603..622 for one of them — and the sample's legend gives the four fills: the accent for ON, the accent LIGHTENED
 * for a prelight, the control's grey for OFF, and a disabled grey out of action.
 */
#import <AppKit/AGSwitchCell.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>
#include <math.h>
#include <stddef.h>
#include <stdio.h>

#define W 39
#define H 20

static int failures = 0;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) failures++;
}

static int is_white(NSColor *c)
{
	return c != nil && [c redComponent] > 0.95 && [c greenComponent] > 0.95 && [c blueComponent] > 0.95;
}

static int near(double got, double want)
{
	return fabs(got - want) < 0.02;
}

static NSBitmapImageRep *draw(AGSwitchCell *cell, NSView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	/* THE CONTEXT FIRST, THEN THE GROUND: a colour cannot be set as the fill without a destination. */
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, W, H)] fill];
	[cell drawWithFrame:NSMakeRect(0.0, 0.0, W, H) inView:view];
	return rep;
}

/* **THE TRACK'S EXPOSED END, WHICH IS THE ONE THE KNOB IS NOT ON.** The knob is FLUSH with its end — that is what the
 * sample measures — so sampling a fixed x reads the KNOB on one of the two values: MEASURED, the first draft sampled
 * x=2 for both and called an OFF switch white. What the fill of a track is, is the colour of the part of it you can
 * see. */
static double track_red(NSBitmapImageRep *rep, int on)
{
	return [[rep colorAtX:(on ? 2 : W - 3) y:H / 2] redComponent];
}

static double track_green(NSBitmapImageRep *rep, int on)
{
	return [[rep colorAtX:(on ? 2 : W - 3) y:H / 2] greenComponent];
}

static double track_blue(NSBitmapImageRep *rep, int on)
{
	return [[rep colorAtX:(on ? 2 : W - 3) y:H / 2] blueComponent];
}

/* THE KNOB'S WHITE RUN ALONG THE MIDDLE ROW, which is its width and where it sits. */
static void knob(NSBitmapImageRep *rep, int *left, int *width)
{
	int x, first = -1, last = -1;

	for (x = 0; x < W; x++) {
		if (is_white([rep colorAtX:x y:H / 2])) {
			if (first < 0) first = x;
			last = x;
		}
	}
	*left = first;
	*width = (first >= 0) ? (last - first + 1) : 0;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, W, H)];
	AGSwitchCell *cell = [[AGSwitchCell alloc] initTextCell:@""];
	NSBitmapImageRep *rep;
	int left, width;
	NSSize measured;

	[cell setBordered:NO];
	[cell setBezeled:NO];

	/* 1. **THE SHAPE IS THE SAMPLE'S: 32 x 20, WHICH IS AN ASPECT RATHER THAN A PAIR OF NUMBERS.** */
	measured = [cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 200.0, H)];
	printf("  (note: a %d-point switch measures %.1f x %.1f)\n", H, (double)measured.width, (double)measured.height);
	check(near(measured.width, W) && near(measured.height, H), "a switch measures the sample's 39 x 20");
	/* **AND THE RECT IS A BOUND, SO THE TWO CASES THAT MATTER ARE THE HUGE ONE AND THE TINY ONE.** MEASURED, the first
	 * draft derived its height FROM the rect — and `-sizeToFit` reaches this door through `-cellSize`, which asks with
	 * the NO-OPINION rectangle of 10000 x 10000, so the switch was fitted to 16000 points across and the demonstration
	 * drew nothing at all. A probe that only ever asked with a sensible rectangle would have passed on a control that
	 * could not be fitted, which is why the 10000 is the FIRST of these checks. */
	check(near([cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 10000.0, 10000.0)].width, W)
	      && near([cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 10000.0, 10000.0)].height, H),
	      "the NO-OPINION rect — which is what -sizeToFit and -cellSize ask with — gives the natural 39 x 20");
	check(near([cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 20.0, 10.0)].width, 20.0)
	      && near([cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 20.0, 10.0)].height, 10.0),
	      "while a rect SMALLER than the natural size clamps it, which is what a bound means");
	check(near([cell cellSize].width, W) && near([cell cellSize].height, H),
	      "and -cellSize answers the same natural size, because it forwards here with no bound at all");

	/* 2. **OFF: THE KNOB AT THE LEFT AND THE TRACK THE CONTROL'S OWN GREY.** */
	[cell setState:NSOffState];
	rep = draw(cell, view);
	knob(rep, &left, &width);
	printf("  (note: OFF -> knob at x=%d, %d wide, and the track's exposed end reads %.2f)\n",
	       left, width, track_red(rep, 0));
	check(near(track_red(rep, 0), [[NSColor controlColor] redComponent]),
	      "an OFF track is the CONTROL's grey, which is the same face a button's bezel wears");
	/* **AND THE KNOB IS MEASURED ON THE ON SWITCH, BECAUSE THE OFF KNOB IS ITS TRACK'S OWN COLOUR.** MEASURED on the
	 * sample: at rest the knob's fill and the track's are the same `#E7E7E7`, and the ring is the only thing that
	 * tells them apart — so a probe looking for WHITE finds nothing on an OFF switch, which is what the first draft of
	 * this check did. The white run is the right instrument exactly where there IS a contrast, and the ring is the
	 * instrument everywhere; where a check needs one, it uses the one that can see. */
	check(width > 0, "so the OFF knob is WHITE rather than its track's colour, which is a measured departure");
	/* **AND THE TRACK SHOWS AN EVEN BAND ALL ROUND THE KNOB, WHICH IS THE POINT OF THE INSET.** MEASURED on the sample:
	 * its track is 39 wide and its knob 15 of that, so 2.5 of track shows beside the knob — the same as above and below
	 * it. A knob flush with the end would put its own ring on the track's outline. */
	{
		int ringL = -1, ringR = -1, x;

		for (x = 2; x < W / 2; x++) {
			if (near([[rep colorAtX:x y:H / 2] redComponent], [[NSColor controlDarkShadowColor] redComponent])) {
				if (ringL < 0) ringL = x; else ringR = x;
			}
		}
		printf("  (note: the OFF knob's ring runs x=%d..%d, inside a track whose outline is at x=0 and x=%d)\n",
		       ringL, ringR, W - 1);
		check(ringL >= 2, "the knob is INSET from the track's edge, so a band of track shows beside it");
		check(near(ringL, (H - 15.0) / 2.0 + 1.0) || ringL <= 4,
		      "by about the same amount as the air above and below it, which is what an even band means");
	}
	[rep release];

	/* 3. **ON: THE KNOB AT THE RIGHT AND THE TRACK THE ACCENT.** */
	[cell setState:NSOnState];
	rep = draw(cell, view);
	knob(rep, &left, &width);
	printf("  (note: ON  -> knob at x=%d, %d wide, track red %.2f green %.2f blue %.2f)\n",
	       left, width, [[rep colorAtX:2 y:H / 2] redComponent], [[rep colorAtX:2 y:H / 2] greenComponent],
	       [[rep colorAtX:2 y:H / 2] blueComponent]);
	check(near(track_red(rep, 1), [[NSColor cg_accentColor] redComponent])
	      && near(track_blue(rep, 1), [[NSColor cg_accentColor] blueComponent]),
	      "an ON track is the ACCENT, which is the same highlight every other control uses");
	/* THE CENTRE, NOT AN EDGE: MEASURED, the ON knob's left edge lands exactly on the halfway point of a 32-point
	 * track, so a check on the edge would call a perfectly correct switch wrong. What the value means is where the
	 * knob IS, and its middle is that. */
	/* **AND THE WHITE RUN IS THE KNOB'S INSIDE, BECAUSE THE KNOB IS NOW RINGED.** MEASURED across a drawn switch: outline,
	 * fill, a point of ring, white, a point of ring, outline — so a knob that is twelve across INCLUDING its ring shows a
	 * white run of about ten. The claim is the knob's width, and the ring is part of it. */
	check(width >= 10 && width <= 14,
	      "the knob is 15 across including its ring, so its white inside is about thirteen of them");
	check(left + width / 2 > W / 2, "and its centre has travelled to the right half, which is what ON looks like");
	[rep release];

	/* 4. **AND THE TRACK DOES NOT CHANGE UNDER THE POINTER — A SWITCH DOES NOT PRELIGHT.** The sample draws a paler
	 * accent for a switch the pointer rests on and this tier DEPARTS from it by the design owner's rule: a control does
	 * not change colour under a person, and a switch says where the pointer is by nothing at all. The claim is made by
	 * comparing the TWO drawings rather than by asserting a colour, because "the same as before" is what not prelighting
	 * means. */
	{
		double at_rest;
		double under_pointer;

		[cell setState:NSOnState];
		[cell cg_setMouseInside:NO];
		rep = draw(cell, view);
		at_rest = track_red(rep, 1);
		[rep release];

		[cell cg_setMouseInside:YES];
		rep = draw(cell, view);
		under_pointer = track_red(rep, 1);
		printf("  (note: an ON track reads %.2f at rest and %.2f under the pointer)\n", at_rest, under_pointer);
		check(near(at_rest, under_pointer),
		      "an ON track is the SAME under the pointer as at rest — a switch does not prelight");
		check(near(under_pointer, [[NSColor cg_accentColor] redComponent]),
		      "which is the accent, because the track says the VALUE and nothing else");
		[rep release];
	}

	/* 5. **AND THE KNOB IS WHAT SHOWS THE PRESS, WHICH IS WHERE THE SAMPLE PUTS IT TOO.** Its pressed pill keeps the
	 * track's own grey and turns the knob white, so a press is answered by the knob rather than by the track. */
	{
		double knob_at_rest;
		double knob_pressed;

		[cell setState:NSOffState];
		[cell cg_setMouseInside:NO];
		[cell setHighlighted:NO];
		rep = draw(cell, view);
		knob_at_rest = [[rep colorAtX:(W / 2 - 10) y:H / 2] redComponent];
		[rep release];

		[cell setHighlighted:YES];
		rep = draw(cell, view);
		knob_pressed = [[rep colorAtX:(W / 2 - 10) y:H / 2] redComponent];
		printf("  (note: an OFF knob reads %.2f at rest and %.2f while held down; the track beside it %.2f)\n",
		       knob_at_rest, knob_pressed, [[rep colorAtX:W / 2 y:H / 2] redComponent]);
		check(near(knob_at_rest, knob_pressed) && near(knob_pressed, 1.0),
		      "an OFF knob is WHITE at rest and white while held down — the knob does not change for a press");
		check(near([[rep colorAtX:W / 2 y:H / 2] redComponent], [[NSColor controlColor] redComponent]),
		      "and the TRACK stays its own grey through the press, so the knob is where the press shows");
		[rep release];
		[cell setHighlighted:NO];
	}

	[cell cg_setMouseInside:NO];

	/* 6. **AND BOTH PIECES ARE OUTLINED IN THE TIER'S BORDER GREY.** MEASURED on the sample and MISSED by the first pass
	 * over it, because every scan that asked for runs of three pixels or more cannot see a line that is one point wide.
	 * The track's edge and the knob's ring are both `+controlDarkShadowColor`, which is the same grey a bezel, a field's
	 * edge and a checkbox's box are stroked in — and the ring is what makes the knob visible when its fill IS its
	 * track's colour, which is what the sample measures. */
	[cell setState:NSOffState];
	[cell setEnabled:YES];
	rep = draw(cell, view);
	check(near([[rep colorAtX:0 y:H / 2] redComponent], [[NSColor controlDarkShadowColor] redComponent])
	      && near([[rep colorAtX:W - 1 y:H / 2] redComponent], [[NSColor controlDarkShadowColor] redComponent]),
	      "an OFF track is OUTLINED in the border grey, at both ends of the middle row");
	/* AND THE KNOB'S RING, read on the row through the knob's widest part: a pixel of outline, then the fill. */
	{
		int ringAt = -1, x;

		for (x = 2; x < 20; x++) {
			if (near([[rep colorAtX:x y:H / 2] redComponent], [[NSColor controlDarkShadowColor] redComponent])) {
				ringAt = x;
				break;
			}
		}
		printf("  (note: the knob's ring is at x=%d, and the knob's fill is %.2f on a track of %.2f)\n",
		       ringAt, [[rep colorAtX:(ringAt + 4) y:H / 2] redComponent], [[NSColor controlColor] redComponent]);
		check(ringAt > 0, "and the knob carries a RING of its own, which is how a knob is seen at all");
		check(near([[rep colorAtX:(ringAt + 4) y:H / 2] redComponent], 1.0),
		      "whose fill is WHITE — the knob does not take its track's colour, whatever the switch is set to");
	}
	[rep release];

	/* 7. **AND OUT OF ACTION WINS OVER EVERYTHING.** */
	[cell setState:NSOnState];
	[cell setEnabled:NO];
	[cell cg_setMouseInside:YES];
	rep = draw(cell, view);
	check(near(track_red(rep, 1), [[NSColor cg_disabledControlFaceColor] redComponent]),
	      "a DISABLED switch wears the out-of-action grey, whatever the pointer is doing and whatever it holds");
	/* AND ITS KNOB IS THE ONE GREY A KNOB CAN BE, which is the other half of the rule: the knob is white unless the
	 * switch is out of action, so a disabled knob is the ONLY grey one in the control. */
	check(near([[rep colorAtX:(W - 10) y:H / 2] redComponent], [[NSColor cg_disabledControlFaceColor] redComponent]),
	      "and its knob is GREY, which is the only thing in this control that greys a knob");
	[rep release];

	[cell release];
	[view release];
	[pool release];
	printf("control_switch: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
