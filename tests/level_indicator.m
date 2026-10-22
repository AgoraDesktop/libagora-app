/*
 * level_indicator — NSLevelIndicator and NSLevelIndicatorCell: a bar, segments, stars, and the colour opinion.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIM IS THAT THE VALUE BECOMES A PICTURE AND THE THRESHOLDS BECOME A COLOUR.** The probe renders the cell at three
 * values and reads what the pixels say: half full is a bar whose left half is the color and whose right half is the ground;
 * above the warning threshold the fill is the platform's orange; above the critical one it is red. That is what separates a
 * level indicator from a progress bar, and it is invisible to a value check.
 *
 * **AND THE FOUR STYLES ARE FOUR PICTURES**: the discrete style lights segments (two of four, checked by counting lit
 * columns), and the rating style draws stars (a filled one uses the level colour, an empty one the shadow colour). The
 * VALUE PAIR is overridden on the cell — `NSCell -setDoubleValue:` answers only for text cells — and the clamp is checked at
 * both ends and through the control's forwards.
 */
#import <AppKit/NSLevelIndicator.h>
#import <AppKit/NSView.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

/* A COLUMN'S DOMINANT INK, sampled down the cell's middle — which is where a bar's fill is and where a segment is. */
static void column_colour(NSBitmapImageRep *rep, int x, int height, CGFloat *r, CGFloat *g, CGFloat *b)
{
	NSColor *c = [rep colorAtX:x y:height / 2];

	*r = (c != nil) ? [c redComponent] : 0.0;
	*g = (c != nil) ? [c greenComponent] : 0.0;
	*b = (c != nil) ? [c blueComponent] : 0.0;
}

static int is_green(CGFloat r, CGFloat g, CGFloat b) { return g > 0.5 && r < 0.5 && b < 0.5; }
static int is_orange(CGFloat r, CGFloat g, CGFloat b) { return r > 0.7 && g > 0.3 && g < 0.8 && b < 0.4; }
static int is_red(CGFloat r, CGFloat g, CGFloat b) { return r > 0.7 && g < 0.4 && b < 0.4; }

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE CELL'S FACTS: the style, the range, the clamp, and the ticks.
		 * ========================================================================================== */
		{
			NSLevelIndicatorCell *cell = [[NSLevelIndicatorCell alloc]
				initWithLevelIndicatorStyle:NSContinuousCapacityLevelIndicatorStyle];

			check([cell levelIndicatorStyle] == NSContinuousCapacityLevelIndicatorStyle,
			      "the initialiser names the style");
			check([cell minValue] == 0.0 && [cell maxValue] == 100.0,
			      "and the range starts at Apple's 0 to 100");
			check([cell warningValue] == 0.0 && [cell criticalValue] == 0.0,
			      "with both thresholds at zero, which means NO threshold");

			/* **THE VALUE IS CLAMPED AT BOTH ENDS** — and it is the CELL's own number, because NSCell's belongs to text
			 * cells (the stepper's slice found the same door). */
			[cell setDoubleValue:150.0];
			check([cell doubleValue] == 100.0, "a value past the maximum is clamped to it");
			[cell setDoubleValue:-20.0];
			check([cell doubleValue] == 0.0, "and one below the minimum to that");
			[cell setDoubleValue:40.0];
			[cell setMaxValue:30.0];
			check([cell doubleValue] == 30.0, "narrowing the range re-clamps the standing value");

			/* THE TICKS: N marks, N-1 intervals, both ends included. */
			[cell setMinValue:0.0];
			[cell setMaxValue:100.0];
			[cell setNumberOfTickMarks:5];
			check([cell tickMarkValueAtIndex:0] == 0.0 && [cell tickMarkValueAtIndex:4] == 100.0,
			      "the first tick is the minimum and the last the maximum");
			check([cell tickMarkValueAtIndex:2] == 50.0, "and they are evenly spaced between");
			check(NSWidth([cell rectOfTickMarkAtIndex:2]) == 1.0
				      && NSMinX([cell rectOfTickMarkAtIndex:2]) > NSMinX([cell rectOfTickMarkAtIndex:1]),
			      "a tick's rectangle is a one-point mark that moves along the bar");
			[cell setNumberOfMajorTickMarks:2];
			check([cell numberOfMajorTickMarks] == 2, "and the major-tick count is stored");

			/* A STYLE AND AN IMAGE ROUND TRIP. */
			[cell setLevelIndicatorStyle:NSRatingLevelIndicatorStyle];
			check([cell levelIndicatorStyle] == NSRatingLevelIndicatorStyle, "the style can be changed");
			[cell setImage:nil];
			check(1, "setImage: accepts nil without crashing");
			[cell release];
		}

		/* ============================================================================================
		 * 2. THE CONTROL FORWARDS.
		 * ========================================================================================== */
		{
			NSLevelIndicator *indicator = [[NSLevelIndicator alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];

			check([[indicator cell] isKindOfClass:[NSLevelIndicatorCell class]],
			      "a level indicator is made with its cell");
			[indicator setMinValue:10.0];
			[indicator setMaxValue:20.0];
			[indicator setWarningValue:15.0];
			[indicator setCriticalValue:18.0];
			[indicator setNumberOfTickMarks:3];
			check([indicator minValue] == 10.0 && [indicator maxValue] == 20.0
				      && [indicator warningValue] == 15.0 && [indicator criticalValue] == 18.0
				      && [indicator numberOfTickMarks] == 3,
			      "and every property forwards to the cell and back");
			check([indicator tickMarkValueAtIndex:1] == 15.0, "including a tick's value");
			[indicator setDoubleValue:20.0];
			check([indicator doubleValue] == 20.0, "and the value the control answers is the cell's");
			[indicator release];
		}

		/* ============================================================================================
		 * 3. THE PICTURES: the bar at three colours, the segments, the stars.
		 * ========================================================================================== */
		{
			NSLevelIndicatorCell *cell = [[NSLevelIndicatorCell alloc]
				initWithLevelIndicatorStyle:NSContinuousCapacityLevelIndicatorStyle];
			NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];

			[cell setMinValue:0.0];
			[cell setMaxValue:100.0];
			[cell setWarningValue:50.0];
			[cell setCriticalValue:80.0];

			/* HALF FULL, BELOW THE WARNING: the left is green and the right is the ground. */
			{
				NSBitmapImageRep *rep = new_rep(100, 20);
				CGFloat lr, lg, lb, rr, rg, rb;

				[cell setDoubleValue:40.0];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:host];
				column_colour(rep, 20, 20, &lr, &lg, &lb);
				column_colour(rep, 80, 20, &rr, &rg, &rb);
				printf("  (note: 40%% fill: left %.2f/%.2f/%.2f, right %.2f/%.2f/%.2f)\n",
				       (double)lr, (double)lg, (double)lb, (double)rr, (double)rg, (double)rb);
				check(is_green(lr, lg, lb), "below the warning threshold the fill is green");
				check(!is_green(rr, rg, rb), "and past the value the bar is the ground, not the fill");
				[rep release];
			}

			/* ABOVE WARNING: ORANGE. ABOVE CRITICAL: RED. */
			{
				NSBitmapImageRep *rep = new_rep(100, 20);
				CGFloat r, g, b;

				[cell setDoubleValue:60.0];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:host];
				column_colour(rep, 30, 20, &r, &g, &b);
				printf("  (note: 60%% fill: %.2f/%.2f/%.2f)\n", (double)r, (double)g, (double)b);
				check(is_orange(r, g, b), "above the warning threshold the fill is the platform's orange");
				[rep release];
			}
			{
				NSBitmapImageRep *rep = new_rep(100, 20);
				CGFloat r, g, b;

				[cell setDoubleValue:90.0];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:host];
				column_colour(rep, 30, 20, &r, &g, &b);
				check(is_red(r, g, b), "and above the critical one it is red");
				[rep release];
			}

			/* **THE DISCRETE STYLE LIGHTS SEGMENTS.** Four marks and a value of two: the first two segments are the level
			 * colour and the rest are the ground. */
			{
				NSBitmapImageRep *rep = new_rep(100, 20);
				NSInteger i;
				int lit = 0;

				[cell setLevelIndicatorStyle:NSDiscreteCapacityLevelIndicatorStyle];
				[cell setNumberOfTickMarks:4];
				[cell setWarningValue:0.0];
				[cell setCriticalValue:0.0];
				[cell setDoubleValue:50.0];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:host];
				for (i = 0; i < 4; i++) {
					CGFloat r, g, b;
					int x = (int)(12.5 + 25.0 * (double)i);

					column_colour(rep, x, 20, &r, &g, &b);
					if (is_green(r, g, b)) {
						lit++;
					}
				}
				printf("  (note: %d of 4 segments are lit at 50%%)\n", lit);
				check(lit == 2, "a discrete indicator lights HALF its segments at half its range");
				[rep release];
			}

			/* **AND THE RATING STYLE DRAWS STARS**, filled ones in the level colour. */
			{
				NSBitmapImageRep *rep = new_rep(100, 20);
				int x, y, coloured = 0;

				[cell setLevelIndicatorStyle:NSRatingLevelIndicatorStyle];
				[cell setMaxValue:5.0];
				[cell setNumberOfTickMarks:0];
				[cell setDoubleValue:3.0];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:host];
				for (y = 0; y < 20; y++) {
					for (x = 0; x < 100; x++) {
						NSColor *c = [rep colorAtX:x y:y];

						if (c != nil && (is_green([c redComponent], [c greenComponent], [c blueComponent])
								 || is_red([c redComponent], [c greenComponent], [c blueComponent]))) {
							coloured++;
						}
					}
				}
				printf("  (note: the rating drew %d coloured pixels of 3 filled stars)\n", coloured);
				check(coloured > 20, "a rating indicator fills its stars in the level colour");
				[rep release];
			}

			[cell release];
			[host release];
		}

		if (failures == 0) {
			printf("level_indicator: all checks passed\n");
			return 0;
		}
		printf("level_indicator: FAILURES\n");
		return 1;
	}
}
