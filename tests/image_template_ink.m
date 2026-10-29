/*
 * image_template_ink — a template image a PROGRAM made can be drawn in a caller's ink.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE FLAG AND THE STENCIL ARE TWO THINGS, AND `-setTemplate:` USED TO SET ONLY THE FIRST.** `-isTemplate` answered YES,
 * `-cg_drawInRect:ink:` found no mask and answered NO, and every caller then drew the raw picture — a black glyph beside a
 * greyed label on each disabled toolbar item, which is what a person reported. A caller's image has no coverage tables, so
 * its ALPHA is the stencil; that is what `-setTemplate:` lifts out now.
 */
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

@interface NSImage (AGCGTemplateInk)
- (BOOL)cg_drawInRect:(NSRect)rect ink:(NSColor *)ink;
@end

/* A PICTURE WITH A SHAPE IN ITS ALPHA: a filled square in the middle of a transparent tile, which is what an icon's
 * stencil is. */
static NSImage *fn_square_icon(void)
{
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(24.0, 24.0)];
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:24 pixelsHigh:24
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
		bytesPerRow:24 * 4 bitsPerPixel:32];
	NSInteger x, y;
	unsigned char *px = [rep bitmapData];

	for (y = 0; y < 24; y++) {
		for (x = 0; x < 24; x++) {
			unsigned char *p = px + (y * [rep bytesPerRow]) + x * 4;

			p[0] = 0;
			p[1] = 0;
			p[2] = 0;
			p[3] = (unsigned char)((x >= 6 && x < 18 && y >= 6 && y < 18) ? 255 : 0);
		}
	}
	[image addRepresentation:rep];
	[rep release];
	[image setTemplate:YES];
	return [image autorelease];
}

int main(void)
{
	@autoreleasepool {
		NSImage *icon = fn_square_icon();
		NSBitmapImageRep *surface = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
			pixelsWide:24 pixelsHigh:24 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:24 * 4 bitsPerPixel:32];
		BOOL inked;
		NSInteger x, y, grey = 0, outside = 0;
		unsigned char *px;

		check([icon isTemplate], "the image says it is a template");

		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:surface]];
		[[NSColor whiteColor] setFill];
		NSRectFill(NSMakeRect(0.0, 0.0, 24.0, 24.0));
		inked = [icon cg_drawInRect:NSMakeRect(0.0, 0.0, 24.0, 24.0)
				       ink:[NSColor colorWithCalibratedWhite:0.5 alpha:1.0]];
		check(inked, "and it can be drawn in a caller's ink");
		px = [surface bitmapData];
		for (y = 0; y < 24; y++) {
			for (x = 0; x < 24; x++) {
				unsigned char *p = px + (y * [surface bytesPerRow]) + x * 4;
				BOOL inside = (x >= 7 && x < 17 && y >= 7 && y < 17);
				BOOL outsideSquare = (x < 5 || x >= 19 || y < 5 || y >= 19);

				if (inside && p[0] > 100 && p[0] < 160) {
					grey++;
				}
				if (outsideSquare && p[0] < 250) {
					outside++;
				}
			}
		}
		check(grey > 40, "with the ink in the shape, at the strength asked for");
		check(outside == 0, "and nothing painted outside the stencil");

		[surface release];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
