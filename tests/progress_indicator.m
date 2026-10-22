/*
 * progress_indicator — the bar's range, clamp and ink.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) s_failed++;
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSProgressIndicator *bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 16.0)];
	NSBitmapImageRep *rep;
	NSGraphicsContext *context;
	unsigned char *pixels;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];
	check([bar minValue] == 0.0 && [bar maxValue] == 100.0, "the default range is 0..100");
	[bar setMinValue:10.0];
	[bar setMaxValue:20.0];
	check([bar minValue] == 10.0 && [bar maxValue] == 20.0, "the range is settable");
	[bar setDoubleValue:5.0];
	check([bar doubleValue] == 10.0, "a value below the minimum is clamped");
	[bar setDoubleValue:25.0];
	check([bar doubleValue] == 20.0, "and above the maximum");
	[bar setDoubleValue:15.0];
	[bar incrementBy:2.0];
	check([bar doubleValue] == 17.0, "incrementBy moves within the range");
	[bar setIndeterminate:YES];
	check([bar isIndeterminate], "the indeterminate flag is recorded");
	[bar setStyle:NSProgressIndicatorSpinningStyle];
	check([bar style] == NSProgressIndicatorSpinningStyle, "the spinner style is recorded");
	[bar startAnimation:nil];
	check([bar isAnimating], "startAnimation starts");
	[bar stopAnimation:nil];
	check(![bar isAnimating], "and stopAnimation stops");

	/* THE BAR'S FILL IS PROPORTIONAL: a rep 200 points wide at value 15 of 10..20 is half filled. */
	[bar setStyle:NSProgressIndicatorBarStyle];
	[bar setIndeterminate:NO];
	[bar setMinValue:0.0];
	[bar setMaxValue:100.0];
	[bar setDoubleValue:50.0];
	rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:200 pixelsHigh:16
						    bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						    colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:800 bitsPerPixel:32];
	context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	(void)context;
	[bar cacheDisplayInRect:[bar bounds] toBitmapImageRep:rep];
	pixels = [rep bitmapData];
	check(pixels != NULL, "the bar draws into a bitmap");
	check(pixels != NULL && pixels[8 * 800 + 50 * 4] != pixels[8 * 800 + 150 * 4],
	      "the filled half and the empty half are different ink");
	[rep release];

	/* ---- AND THE SWEEP'S DOORS: THE SPINNER'S FRAME, THE TWO APPEARANCE DOORS, THE RECESS AND THE ONE REFUSAL ---- */

	/* THE SPINNER'S PICTURE IS A TRACK RING AND ONE ARC, AND `-animate:` MOVES THE ARC. The claim is made in PIXELS,
	 * because a phase that advanced and did not reach the drawing would pass any read-back of a number: the spun
	 * spinner is compared with the still one over the whole bitmap, and the animation DELAY is the interval a driver
	 * uses between frames (the class has no clock, so the delay is a value rather than a timer). */
	{
		NSProgressIndicator *spin = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];
		NSBitmapImageRep *before;
		NSBitmapImageRep *after;
		int i;
		int differing = 0;
		int x, y;

		[spin setStyle:NSProgressIndicatorSpinningStyle];
		[spin startAnimation:nil];
		before = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:20 pixelsHigh:20
						 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						 colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:80 bitsPerPixel:32];
		after = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:20 pixelsHigh:20
						bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:80 bitsPerPixel:32];
		[spin cacheDisplayInRect:[spin bounds] toBitmapImageRep:before];
		for (i = 0; i < 3; i++) {
			[spin animate:nil];
		}
		[spin cacheDisplayInRect:[spin bounds] toBitmapImageRep:after];
		for (y = 0; y < 20; y++) {
			for (x = 0; x < 20; x++) {
				NSColor *a = [before colorAtX:x y:y];
				NSColor *b = [after colorAtX:x y:y];

				if (a != nil && b != nil && [a redComponent] != [b redComponent]) {
					differing++;
				}
			}
		}
		printf("  (note: three `-animate:` frames moved %d of 400 points of the spinner)\n", differing);
		check(differing > 10, "`-animate:` advances the spinner's ARC, which is the frame a caller pumps");

		check([spin animationDelay] > 0.0, "the animation delay has a default a driver can read");
		[spin setAnimationDelay:0.5];
		check([spin animationDelay] == 0.5, "and `-setAnimationDelay:` round-trips");
		[spin setAnimationDelay:0.0];
		check([spin animationDelay] > 0.0,
		      "a zero delay is refused in favour of the default — a frame every zero seconds is not a delay");

		/* THE SIZE IS THE SPINNER'S INSET: a MINI spinner's ring is two points larger in diameter than a regular one's. */
		{
			/* **THE RING'S EXTENT, NOT ITS POINT COUNT.** The bitmap starts EMPTY (zeroed, alpha 0) and the spinner
			 * paints a ring over it, so "inked" is "not the untouched pixel" — and the claim is that the MINI ring is
			 * BIGGER, because a smaller control keeps less inset around the same box. A count of inked points would
			 * move with the stroke's length rather than with the ring's diameter, which is the wrong thing to hold. */
			int regular_min = 99, regular_max = -1;
			int mini_min = 99, mini_max = -1;

			[spin setControlSize:NSRegularControlSize];
			check([spin controlSize] == NSRegularControlSize, "the control size round-trips");
			[spin cacheDisplayInRect:[spin bounds] toBitmapImageRep:before];
			[spin setControlSize:NSMiniControlSize];
			[spin cacheDisplayInRect:[spin bounds] toBitmapImageRep:after];
			for (y = 0; y < 20; y++) {
				for (x = 0; x < 20; x++) {
					NSColor *a = [before colorAtX:x y:y];
					NSColor *b = [after colorAtX:x y:y];

					if (a != nil && [a alphaComponent] > 0.2) {
						if (x < regular_min) regular_min = x;
						if (x > regular_max) regular_max = x;
					}
					if (b != nil && [b alphaComponent] > 0.2) {
						if (x < mini_min) mini_min = x;
						if (x > mini_max) mini_max = x;
					}
				}
			}
			printf("  (note: the ring spans x %d..%d regular and %d..%d mini)\n",
			       regular_min, regular_max, mini_min, mini_max);
			check(regular_max > regular_min && mini_max > mini_min, "the spinner draws a ring at both sizes");
			check((mini_max - mini_min) > (regular_max - regular_min),
			      "a MINI spinner's ring is WIDER, because the inset is what the control size changes");
			[spin setControlSize:NSRegularControlSize];
		}

		[before release];
		[after release];
		[spin release];
	}

	/* THE TINT IS THE FILL'S COLOUR AND `-isBezeled` IS THE RECESS. Both are read off the bar's own pixels: graphite
	 * must change the filled half's colour, and unbezelled must leave the EMPTY half unpainted. */
	{
		NSProgressIndicator *b = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 16.0)];
		NSBitmapImageRep *plain = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:200 pixelsHigh:16
							 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
							 colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:800 bitsPerPixel:32];
		NSBitmapImageRep *tinted = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:200 pixelsHigh:16
							 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
							 colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:800 bitsPerPixel:32];
		NSBitmapImageRep *bare = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:200 pixelsHigh:16
						       bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						       colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:800 bitsPerPixel:32];
		NSColor *default_fill;
		NSColor *graphite_fill;

		[b setDoubleValue:50.0];
		check([b isBezeled], "a bar is BEZELED by default — the recess is the era's picture");
		check([b controlTint] == NSDefaultControlTint, "and wears the default tint, which is the platform's accent");
		[b cacheDisplayInRect:[b bounds] toBitmapImageRep:plain];
		default_fill = [plain colorAtX:50 y:8];
		[b setControlTint:NSGraphiteControlTint];
		check([b controlTint] == NSGraphiteControlTint, "`-setControlTint:` round-trips");
		[b cacheDisplayInRect:[b bounds] toBitmapImageRep:tinted];
		graphite_fill = [tinted colorAtX:50 y:8];
		printf("  (note: the fill is %.2f/%.2f/%.2f at the default tint and %.2f/%.2f/%.2f at graphite)\n",
		       (double)[default_fill redComponent], (double)[default_fill greenComponent],
		       (double)[default_fill blueComponent],
		       (double)[graphite_fill redComponent], (double)[graphite_fill greenComponent],
		       (double)[graphite_fill blueComponent]);
		check(fabs([default_fill redComponent] - [graphite_fill redComponent]) > 0.1 ||
		      fabs([default_fill blueComponent] - [graphite_fill blueComponent]) > 0.1,
		      "and the tint reaches the FILL, which is the only thing it colours");

		[b setControlTint:NSDefaultControlTint];
		[b setDoubleValue:0.0];
		/* **THE EMPTY HALF IS WHAT THE RECESS PAINTS, WHICH IS THE ONE THING `-isBezeled` DECIDES.** The control is
		 * an EMPTY bar at value 0, drawn twice: bezeled, the recess covers the whole track; unbezelled, nothing does.
		 * The bitmap starts transparent, so "not painted" is an ALPHA of zero rather than a colour. */
		[b cacheDisplayInRect:[b bounds] toBitmapImageRep:plain];
		check([[plain colorAtX:150 y:8] alphaComponent] > 0.2 &&
		      [[plain colorAtX:150 y:8] redComponent] > 0.9,
		      "bezeled at value 0, the track is painted — the recess is the whole bar");
		[b setBezeled:NO];
		check(![b isBezeled], "`-setBezeled:NO` round-trips");
		[b cacheDisplayInRect:[b bounds] toBitmapImageRep:bare];
		check([[bare colorAtX:150 y:8] alphaComponent] < 0.2,
		      "and with no bezel the EMPTY half is not painted at all, which is what the recess was drawing");
		[plain release];
		[tinted release];
		[bare release];
		[b release];
	}

	/* THE ONE REFUSAL. `-usesThreadedAnimation` asks for an animation thread this tier has not got, so the getter
	 * answers what is RUNNING — NO — rather than storing a flag nothing honours. */
	{
		NSProgressIndicator *b = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];

		check(![b usesThreadedAnimation], "a fresh indicator does not animate on a thread");
		[b setUsesThreadedAnimation:YES];
		check(![b usesThreadedAnimation],
		      "`-setUsesThreadedAnimation:YES` is REFUSED by name and the getter still answers NO");
		[b release];
	}

	[bar release];
	printf("progress_indicator: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
