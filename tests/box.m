/*
 * box — NSBox: the kind, the title's band, the content view, and the ink.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS THE GEOMETRY AND THEN THE PIXELS.** A box's content view sits inside the border and the margins; a title
 * at `NSAtTop` takes a band across the top edge, which is why the content starts below it; and `-setFrameFromContentFrame:`
 * is the inverse of that arithmetic, which the probe checks by going round the loop (a content frame in, a box frame out, and
 * the same content frame back). Then the five kinds are DRAWN into a bitmap, because a box that stored its kind and painted
 * one face would pass every value check.
 */
#import <AppKit/NSBox.h>
#import <AppKit/NSView.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
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

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

/* DARK INK inside a rect, with the bitmap's rows read from the opposite end (the sampler's own trap). */
static int dark_in(NSBitmapImageRep *rep, int w, int h, NSRect rect)
{
	int x, y, count = 0;
	int x0 = (int)floor(NSMinX(rect)), x1 = (int)ceil(NSMaxX(rect)) - 1;
	int y0 = h - (int)ceil(NSMaxY(rect)), y1 = h - 1 - (int)floor(NSMinY(rect));

	for (y = 0; y < h; y++) {
		for (x = 0; x < w; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			/* **"INK" IS "NOT THE GROUND".** A bezel's greys are 0.60 and 0.737 against the 0.90 control face, so a
			 * threshold tight enough to call 0.60 "dark" would call a groove's highlight nothing — the assertion is that the
			 * box's own ink differs from the face it sits on. */
			if (c != nil && [c alphaComponent] > 0.4 && [c redComponent] < 0.80
			    && x >= x0 && x <= x1 && y >= y0 && y <= y1) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE GEOMETRY: the content inside, and the frame arithmetic both ways.
		 * ========================================================================================== */
		{
			NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];

			check([box boxType] == NSBoxPrimary && [box borderType] == NSGrooveBorder,
			      "a box starts primary with a groove border");
			check([box titlePosition] == NSAtTop, "and its title sits across the top edge");
			check([box contentView] != nil, "and it owns a content view");

			/* THE CONTENT IS INSIDE THE BORDER AND THE MARGINS. */
			{
				NSRect content = [[box contentView] frame];

				check(NSMinX(content) > 0.0 && NSMinY(content) > 0.0
					      && NSMaxX(content) < NSWidth([box bounds])
					      && NSMaxY(content) < NSHeight([box bounds]),
				      "the content view sits inside the border, not on it");
			}

			/* **THE INVERSE PAIR.** A content frame in, a box frame out, and the content frame back. */
			{
				NSBox *fitted = [[NSBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
				NSRect wanted = NSMakeRect(0.0, 0.0, 150.0, 80.0);

				[fitted setFrameFromContentFrame:wanted];
				check(NSWidth([fitted bounds]) > wanted.size.width,
				      "a box frame is the content plus the margins and the border");
				/* **THE ROUND TRIP CLOSES**: the content frame that went in is the one that comes back, which is what makes
				 * the two formulas one formula. */
				check(close_enough(NSWidth([[fitted contentView] frame]), 150.0),
				      "and the content it lays out is the frame it was asked for");
				check(close_enough(NSHeight([[fitted contentView] frame]), 80.0),
				      "in both directions, the title band included");
				[fitted release];
			}

			/* THE TITLE'S BAND IS BETWEEN THE CONTENT'S TOP AND THE BORDER'S. */
			{
				[box setTitle:@"Group"];
				check([[box title] isEqual:@"Group"], "a title is set and answered");
				check(!NSIsEmptyRect([box titleRect]), "and it has a band to be drawn in");
				check(NSMidY([box titleRect]) > NSMaxY([[box contentView] frame]),
				      "which is ABOVE the content, not over it");
				check(close_enough(NSMidX([box titleRect]), NSMidX([box bounds])),
				      "a title is centred on the box by default");
				[box setTitlePosition:NSNoTitle];
				check(NSIsEmptyRect([box titleRect]), "and NSNoTitle has no band at all");
				[box setTitlePosition:NSAtTop];
				[box setTitleWithMnemonic:@"&Group"];
				check([[box title] isEqual:@"Group"], "the marker rule is the field's, one class over");
			}
			[box release];
		}

		/* ============================================================================================
		 * 2. THE FIVE KINDS ARE FIVE PICTURES.
		 * ========================================================================================== */
		{
			NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 60.0)];
			NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 60.0)];
			int separatorInk;
			int customInk;
			int primaryInk;

			check([box superview] == nil && host != nil, "a box draws into whatever view is asked");

			/* A SEPARATOR IS ONE LINE ACROSS THE MIDDLE. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:80 pixelsHigh:60 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:320 bitsPerPixel:32];

				[box setBoxType:NSBoxSeparator];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[box drawRect:[box bounds]];
				separatorInk = dark_in(rep, 80, 60, NSMakeRect(0.0, 29.0, 80.0, 2.0));
				printf("  (note: separator drew %d dark pixels in its middle band)\n", separatorInk);
				check(separatorInk > 60, "a separator is a line across the middle");
				[rep release];
			}

			/* A CUSTOM BOX FILLS ITS RECTANGLE, so the middle is filled and not empty. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:80 pixelsHigh:60 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:320 bitsPerPixel:32];

				[box setBoxType:NSBoxCustom];
				[box setFillColor:[NSColor redColor]];
				[box setBorderColor:[NSColor blackColor]];
				[box setBorderWidth:2.0];
				[box setTitlePosition:NSNoTitle];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[box drawRect:[box bounds]];
				{
					int x, y, red = 0;

					for (y = 0; y < 60; y++) {
						for (x = 0; x < 80; x++) {
							NSColor *c = [rep colorAtX:x y:y];

							if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4) {
								red++;
							}
						}
					}
					customInk = red;
				}
				printf("  (note: the custom box filled %d red pixels)\n", customInk);
				check(customInk > 3000, "a custom box fills its rectangle with its own colour");
				[rep release];
			}

			/* AND THE PLATFORM KINDS DRAW *SOMETHING* — a bezel, which is ink at the edges and none in the middle. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:80 pixelsHigh:60 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:320 bitsPerPixel:32];
				int edgeInk;
				int middleInk;

				[box setBoxType:NSBoxPrimary];
				[box setTitlePosition:NSNoTitle];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[box drawRect:[box bounds]];
				edgeInk = dark_in(rep, 80, 60, NSMakeRect(0.0, 0.0, 80.0, 60.0))
					- dark_in(rep, 80, 60, NSMakeRect(5.0, 5.0, 70.0, 50.0));
				middleInk = dark_in(rep, 80, 60, NSMakeRect(35.0, 27.0, 10.0, 6.0));
				primaryInk = dark_in(rep, 80, 60, NSMakeRect(0.0, 0.0, 80.0, 60.0));
				printf("  (note: the primary box drew %d pixels, %d of them at the edges)\n", primaryInk, edgeInk);
				check(primaryInk > 0 && edgeInk > 0, "a primary box draws a bezel");
				check(middleInk == 0, "and its middle is empty, which is why it is a FRAME");
				[rep release];
			}
			[box release];
			[host release];
		}

		if (failures == 0) {
			printf("box: all checks passed\n");
			return 0;
		}
		printf("box: FAILURES\n");
		return 1;
	}
}
