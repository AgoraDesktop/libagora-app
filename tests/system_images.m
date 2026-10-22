/*
 * system_images — the platform's named images: that every name answers, that it is a template, and that a
 * template really is drawn in the ink it is given.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE NAMES EXISTED BEFORE THE PICTURES DID, AND THIS IS WHAT KEEPS THEM TOGETHER.** `NSImageNameGoLeftTemplate`
 * and its siblings are strings in `NSImage.h`; `AGSystemImages` draws twenty of them from a generated table of
 * coverage, and `+[NSImage imageNamed:]` asks it before it asks the bundle. Four things are asserted, and each of
 * them is a way the arrangement can come apart:
 *
 *   1. EVERY name in the table answers, with an image rather than nil.
 *   2. Every one of those is a TEMPLATE — the flag `NSButtonCell` and `NSToolbar` consult to decide the ink.
 *   3. A template drawn through the tint door paints in THE INK IT WAS GIVEN, at both sizes: red pixels where a
 *      red arrow was asked for, and none where white paper is. This is the one behaviour that cannot be checked
 *      by looking at the image object — the stencil and the fill have to meet in the context.
 *   4. A name this tier does NOT draw still answers nil, so a caller's bundle lookup keeps its meaning.
 *
 * Offscreen: a bitmap context as the canvas, no window and no compositor.
 */
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>

#import <AppKit/AGSystemImages.h>
#import <AppKit/NSImage_internal.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* A CANVAS WITH WHITE PAPER ON IT, so "no ink here" is a pixel this probe can recognise. */
static NSBitmapImageRep *new_canvas(int wide, int high)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:wide
								      pixelsHigh:high bitsPerSample:8 samplesPerPixel:4
								      hasAlpha:YES isPlanar:NO
								      colorSpaceName:NSDeviceRGBColorSpace
								      bytesPerRow:wide * 4 bitsPerPixel:32];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)wide, (CGFloat)high)] fill];
	return rep;
}

/* HOW MANY PIXELS ARE PAINTED MOSTLY IN ONE CHANNEL — a red glyph is a pixel where red is high and the other two
 * are low, and this is what "the ink arrived" means without asking the drawing code what it thinks it did. */
static int count_ink(NSBitmapImageRep *rep, int channel)
{
	unsigned char *pixels = [rep bitmapData];
	int wide = (int)[rep pixelsWide], high = (int)[rep pixelsHigh];
	int x, y, count = 0;

	for (y = 0; y < high; y++) {
		for (x = 0; x < wide; x++) {
			unsigned char *p = pixels + ((size_t)y * (size_t)wide + (size_t)x) * 4u;

			if (p[channel] > 170 && p[(channel + 1) % 3] < 90 && p[(channel + 2) % 3] < 90) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		unsigned count = AGSystemImageCount();
		unsigned i;
		int missing = 0, plain = 0;

		/* 1-2. EVERY NAME, AND EVERY ONE OF THEM A TEMPLATE. */
		check(count == 20, "the platform draws twenty of Apple's named images");
		for (i = 0; i < count; i++) {
			NSString *name = AGSystemImageNameAtIndex(i);
			NSImage *image = (name != nil) ? [NSImage imageNamed:name] : nil;

			if (image == nil) {
				printf("  (no image for %s)\n", (name != nil) ? [name UTF8String] : "(nil name)");
				missing++;
			} else if (![image isTemplate]) {
				printf("  (not a template: %s)\n", [name UTF8String]);
				plain++;
			}
		}
		check(missing == 0, "every one of them answers an image rather than nil");
		check(plain == 0, "and every one is a TEMPLATE, which is what makes its ink the control's");

		/* 2b. **THREE SIZES, AND EACH DRAWS ITS OWN STENCIL.** The toolbar's regular item is 24 points and its
		 * small one 16; a stencil drawn at a size it was not made for is scaled, and a scaled stencil is either
		 * blocky or soft — MEASURED both ways, which is why the table carries the sizes that are asked for. The
		 * reps declare their own sizes in points, so `-bestRepresentationForRect:` picks by the same rule. */
		{
			NSImage *back = [NSImage imageNamed:NSImageNameGoLeftTemplate];
			NSArray *reps = [back representations];
			NSMutableString *sizes = [NSMutableString string];
			NSUInteger r;

			for (r = 0; r < [reps count]; r++) {
				[sizes appendFormat:@"%@%.0fx%.0f", (r > 0) ? @", " : @"",
				 (double)[[reps objectAtIndex:r] size].width,
				 (double)[[reps objectAtIndex:r] size].height];
			}
			check([reps count] == 3 && [sizes isEqual:@"16x16, 24x24, 32x32"],
			      "the image carries all three sizes the tier draws at (16, 24 and 32 points)");
			check([[back bestRepresentationForRect:NSMakeRect(0.0, 0.0, 24.0, 24.0) context:nil hints:nil] size].width
			      == 24.0,
			      "and a 24-point draw chooses the 24-point stencil rather than scaling a smaller one");
		}

		/* 3. THE TINT, AT EACH SIZE. Back is an arrow: a red one leaves red pixels, and the paper around it is
		 * untouched — which is the stencil meeting the fill, not a picture of a red arrow. */
		{
			NSBitmapImageRep *canvas = new_canvas(80, 40);
			NSImage *back = [NSImage imageNamed:NSImageNameGoLeftTemplate];
			BOOL drewSmall = [back cg_drawInRect:NSMakeRect(6.0, 12.0, 16.0, 16.0) ink:[NSColor redColor]];
			BOOL drewLarge = [back cg_drawInRect:NSMakeRect(40.0, 4.0, 32.0, 32.0) ink:[NSColor blueColor]];
			int red = count_ink(canvas, 0);
			int blue = count_ink(canvas, 2);

			check(drewSmall && drewLarge, "the tint door answers YES for a name this tier draws");
			check(red > 0, "a red arrow at sixteen points paints red pixels");
			check(blue > red, "a blue one at thirty-two paints more of them, which is the larger stencil");
			[canvas release];
		}

		/* 3b. AND A GLYPH WITH A HOLE IN IT KEEPS ITS HOLE: the stop face is a ring around a square, so the ink
		 * count is a fraction of the box rather than all of it. */
		{
			NSBitmapImageRep *canvas = new_canvas(32, 32);
			NSImage *stop = [NSImage imageNamed:NSImageNameStopProgressTemplate];
			int ink;

			[stop cg_drawInRect:NSMakeRect(0.0, 0.0, 32.0, 32.0) ink:[NSColor redColor]];
			ink = count_ink(canvas, 0);
			check(ink > 0 && ink < 32 * 32 / 2,
			      "the stop face paints its ring and its square and leaves the rest of the box alone");
			[canvas release];
		}

		/* 4. A NAME THIS TIER DOES NOT DRAW IS STILL A BUNDLE QUESTION, so it answers nil here and the lookup
		 * in `+imageNamed:` is what a caller's own art goes through. */
		check([NSImage imageNamed:NSImageNameMobileMe] == nil,
		      "a name this tier does not draw falls through to the bundle lookup and answers nil");
		check([NSImage imageNamed:@"NotAnImageNameAtAll"] == nil, "and so does a name nobody has");
	}
	return s_failed != 0;
}
