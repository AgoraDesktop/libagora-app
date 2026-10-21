/*
 * image_draw — the one rule an image rep's `-drawInRect:` has to keep: UP IS UP IN BOTH KINDS OF VIEW.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE BUG THIS PINS WAS VISIBLE IN WORKSPACE AND MEASURED THERE.** The Desktop and the file window's
 * `WSIconView` are the two coordinate systems AppKit builds: the first draws in a y-up space, the second is
 * flipped and draws in a y-down one. `CGContextDrawImage` paints through the current CTM, so the SAME image
 * bytes arrived vertically mirrored in the two; Frost's folder icons were upright on the Desktop and
 * upside-down in the file window. `NSImageRep -drawInRect:` now adds the mirror for a y-up CTM, and this test
 * is the offscreen version of that pair: one rep, two contexts, and the same ink at the top in both.
 *
 * The image is composed here as bytes rather than loaded, so the probe needs no file and no decoder: eight
 * rows of red over eight rows of blue in this tree's `kCGImageAlphaPremultipliedFirst | 32Little` format.
 * Each context is the full image, so a correct draw puts red at the top of BOTH destination buffers; before
 * the fix one buffer had red at the top and the other at the bottom.
 */
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphics.h>

#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGImage.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define IMAGE_SIDE 8
#define ROW_BYTES (IMAGE_SIDE * 4)

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) s_failed++;
}

/* The test's own format is B, G, R, A — the one `CGBitmapContextCreate` pins for this tree. */
static int row_is_red(const unsigned char *p)
{
	return p[0] < 40 && p[1] < 40 && p[2] > 200;
}

static int row_is_blue(const unsigned char *p)
{
	return p[0] > 200 && p[1] < 40 && p[2] < 40;
}

static CGImageRef makeRedOverBlue(void)
{
	size_t size = (size_t)ROW_BYTES * IMAGE_SIDE;
	unsigned char *pixels = malloc(size);
	CGColorSpaceRef space;
	CGDataProviderRef provider;
	CGImageRef image;
	size_t y;

	if (pixels == NULL) return NULL;
	for (y = 0; y < IMAGE_SIDE; y++) {
		unsigned char *row = pixels + y * ROW_BYTES;
		size_t x;
		int red = (y < IMAGE_SIDE / 2);
		for (x = 0; x < IMAGE_SIDE; x++) {
			row[x * 4 + 0] = red ? 0 : 255;		/* B */
			row[x * 4 + 1] = 0;			/* G */
			row[x * 4 + 2] = red ? 255 : 0;		/* R */
			row[x * 4 + 3] = 255;			/* A */
		}
	}
	space = CGColorSpaceCreateDeviceRGB();
	provider = CGDataProviderCreateWithData(NULL, pixels, size, NULL);
	image = CGImageCreate((size_t)IMAGE_SIDE, (size_t)IMAGE_SIDE, 8, 32, ROW_BYTES, space,
			      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
			      provider, NULL, false, kCGRenderingIntentDefault);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(space);
	/* The provider does not own the bytes, so the image keeps them alive only by this pointer; the probe
	 * leaks the block deliberately rather than teach the decoder a release callback it does not need. */
	return image;
}

/* Draw the rep into a fresh context whose y direction is `yDown`, and answer the context so its rows can be
 * read. The CTM is what `fn_draw_view` puts on a flipped or unflipped view; the `flipped:` flag on the
 * graphics context is the window's statement and is deliberately not what the fix consults. */
static CGContextRef drawInto(BOOL yDown, NSBitmapImageRep *rep)
{
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef cg = CGBitmapContextCreate(NULL, IMAGE_SIDE, IMAGE_SIDE, 8, ROW_BYTES, space,
					       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	NSGraphicsContext *g;

	CGColorSpaceRelease(space);
	if (cg == NULL) return NULL;
	CGContextClearRect(cg, CGRectMake(0.0, 0.0, IMAGE_SIDE, IMAGE_SIDE));
	if (yDown) {
		CGContextTranslateCTM(cg, 0.0, (CGFloat)IMAGE_SIDE);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	g = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:yDown];
	if (g != nil) {
		NSGraphicsContext *previous = [[NSGraphicsContext currentContext] retain];
		[NSGraphicsContext setCurrentContext:g];
		[rep drawInRect:NSMakeRect(0.0, 0.0, IMAGE_SIDE, IMAGE_SIDE)];
		[NSGraphicsContext setCurrentContext:previous];
		[previous release];
	}
	return cg;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		CGImageRef image = makeRedOverBlue();
		NSBitmapImageRep *rep = image != NULL
			? [[NSBitmapImageRep alloc] initWithCGImage:image] : nil;
		CGContextRef up;
		CGContextRef down;
		unsigned char *upPixels;
		unsigned char *downPixels;

		check(image != NULL && rep != nil, "the probe's red-over-blue image is made");
		if (image == NULL || rep == nil) return 1;

		up = drawInto(NO, rep);
		down = drawInto(YES, rep);
		check(up != NULL && down != NULL, "an image rep draws into a y-up and a y-down context");
		if (up == NULL || down == NULL) return 1;

		upPixels = CGBitmapContextGetData(up);
		downPixels = CGBitmapContextGetData(down);
		check(upPixels != NULL && downPixels != NULL, "both destination buffers are readable");
		if (upPixels == NULL || downPixels == NULL) return 1;

		check(row_is_red(upPixels) && row_is_blue(upPixels + (IMAGE_SIDE - 1) * ROW_BYTES),
		      "a y-up context puts the image's top at the top of the buffer");
		check(row_is_red(downPixels) && row_is_blue(downPixels + (IMAGE_SIDE - 1) * ROW_BYTES),
		      "a y-down context puts the SAME top at the top — the two agree");
		check(row_is_red(upPixels) == row_is_red(downPixels),
		      "and the two destinations are not vertical mirrors of one another");

		CGContextRelease(up);
		CGContextRelease(down);
		[rep release];
		CGImageRelease(image);
	}
	printf("image_draw: %d check(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
