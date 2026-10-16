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

#define W 32
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
	check(near(measured.width, W) && near(measured.height, H), "a switch measures the sample's 32 x 20");
	/* **AND THE RECT IS A BOUND, SO THE TWO CASES THAT MATTER ARE THE HUGE ONE AND THE TINY ONE.** MEASURED, the first
	 * draft derived its height FROM the rect — and `-sizeToFit` reaches this door through `-cellSize`, which asks with
	 * the NO-OPINION rectangle of 10000 x 10000, so the switch was fitted to 16000 points across and the demonstration
	 * drew nothing at all. A probe that only ever asked with a sensible rectangle would have passed on a control that
	 * could not be fitted, which is why the 10000 is the FIRST of these checks. */
	check(near([cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 10000.0, 10000.0)].width, W)
	      && near([cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 10000.0, 10000.0)].height, H),
	      "the NO-OPINION rect — which is what -sizeToFit and -cellSize ask with — gives the natural 32 x 20");
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
	check(left < 0, "so the OFF knob is NOT white, which is the sample's own measurement rather than a miss");
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
	check(width >= 8 && width <= 12,
	      "the knob is 12 points across including its ring, so its white inside is about ten of them");
	check(left + width / 2 > W / 2, "and its centre has travelled to the right half, which is what ON looks like");
	[rep release];

	/* 4. **AND THE PRELIGHT IS THE ACCENT LIGHTENED, WHICH IS THE SAMPLE'S OWN ANSWER FOR THIS CONTROL.** MEASURED in
	 * the mockup: its prelight pill's track is `#E5E3FF` against the `#A49AFF` it lightens. This is the one control in
	 * the tier whose prelight is NOT a step down the grey scale, and the reason is that there is no grey to step down
	 * from when the track is the accent. */
	[cell cg_setMouseInside:YES];
	rep = draw(cell, view);
	printf("  (note: ON + pointer -> track red %.2f green %.2f blue %.2f; the accent is %.2f/%.2f/%.2f and its "
	       "prelight %.2f/%.2f/%.2f)\n", track_red(rep, 1), track_green(rep, 1), track_blue(rep, 1),
	       [[NSColor cg_accentColor] redComponent], [[NSColor cg_accentColor] greenComponent],
	       [[NSColor cg_accentColor] blueComponent], [[NSColor cg_accentPrelightColor] redComponent],
	       [[NSColor cg_accentPrelightColor] greenComponent], [[NSColor cg_accentPrelightColor] blueComponent]);
	check(near(track_red(rep, 1), [[NSColor cg_accentPrelightColor] redComponent])
	      && near(track_blue(rep, 1), [[NSColor cg_accentPrelightColor] blueComponent]),
	      "an ON switch under the pointer wears the accent LIGHTENED, as the sample's legend gives it");
	check([[NSColor cg_accentPrelightColor] redComponent] > [[NSColor cg_accentColor] redComponent]
	      && [[NSColor cg_accentPrelightColor] blueComponent] >= [[NSColor cg_accentColor] blueComponent],
	      "which is lighter than the accent component by component, so the two read as one colour in two states");
	[rep release];

	/* 5. **AND AN OFF ONE STEPS DOWN THE GREY SCALE INSTEAD, WHICH IS THIS TIER'S RULE FOR A GREY FACE.** The sample
	 * draws no prelight on an OFF switch, so the tier's own rule applies where the sample is silent. */
	[cell setState:NSOffState];
	rep = draw(cell, view);
	check(near(track_red(rep, 0), [[NSColor cg_prelightControlFaceColor] redComponent]),
	      "an OFF switch under the pointer takes the tier's PRELIGHT grey, one step under its rest");
	/* **AND THE TWO PRELIGHT RULES ARE TELLABLE APART BY THE INK ITSELF, WHICH IS WHY BOTH ARE WORTH HAVING.** The
	 * OFF one is a GREY — its three components are the same number — and the ON one is a TINT, because it is the
	 * accent lightened. A check that both were greys would have been a tautology; this is the claim. */
	check(near(track_red(rep, 0), track_green(rep, 0)) && near(track_green(rep, 0), track_blue(rep, 0)),
	      "and that one is a GREY — one number three times — where the ON switch's prelight is a tint of the accent");
	[rep release];
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
		check(near([[rep colorAtX:(ringAt + 4) y:H / 2] redComponent], [[NSColor controlColor] redComponent]),
		      "whose fill at rest is the TRACK's own grey, as the sample measures it — the ring is the only difference");
	}
	[rep release];

	/* 7. **AND OUT OF ACTION WINS OVER EVERYTHING.** */
	[cell setState:NSOnState];
	[cell setEnabled:NO];
	[cell cg_setMouseInside:YES];
	rep = draw(cell, view);
	check(near(track_red(rep, 1), [[NSColor cg_disabledControlFaceColor] redComponent]),
	      "a DISABLED switch wears the out-of-action grey, whatever the pointer is doing and whatever it holds");
	[rep release];

	[cell release];
	[view release];
	[pool release];
	printf("control_switch: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
