/*
 * progress_indicator — the bar's range, clamp and ink.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

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
	[bar release];
	printf("progress_indicator: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
