/*
 * image_draw — the one rule an image rep's `-drawInRect:` has to keep: UP IS UP IN BOTH KINDS OF VIEW.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
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
#import <AppKit/NSImage.h>
#import <AppKit/NSImageRep.h>
#import <AppKit/NSColor.h>
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

/* **A DELEGATE THAT ANSWERS WITH A REP, AND COUNTS THE QUESTION.** The protocol's answer is the rep to draw instead,
 * so a probe can prove the substitute was USED (the picture) rather than only that a method ran (the count). */
@interface AGRepDelegate : NSObject <NSImageDelegate>
{
@public
	int calls;
	NSImageRep *substitute;
}
- (id)initWithRep:(NSImageRep *)rep;
@end

@implementation AGRepDelegate
- (id)initWithRep:(NSImageRep *)rep
{
	if ((self = [super init]) != nil) {
		substitute = [rep retain];
	}
	return self;
}
- (void)dealloc
{
	[substitute release];
	[super dealloc];
}
- (NSImageRep *)imageDidNotDraw:(id)sender inRect:(NSRect)aRect
{
	(void)sender;
	(void)aRect;
	calls++;
	return substitute;
}
@end

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

/* **AND A CONTEXT OF ANY SIZE, BECAUSE THE WIDE DOOR SCALES.** The helper above is pinned to the image's own size,
 * which is right for the orientation claim; the compositing claims below need a destination that is BIGGER than the
 * source so a hint has something to interpolate over. */
static CGContextRef newContext(BOOL yDown, int side)
{
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef cg = CGBitmapContextCreate(NULL, (size_t)side, (size_t)side, 8, (size_t)side * 4, space,
					       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	NSGraphicsContext *g;

	CGColorSpaceRelease(space);
	if (cg == NULL) {
		return NULL;
	}
	CGContextClearRect(cg, CGRectMake(0.0, 0.0, (CGFloat)side, (CGFloat)side));
	if (yDown) {
		CGContextTranslateCTM(cg, 0.0, (CGFloat)side);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	(void)g;
	return cg;
}

/* AND ONE DOOR THAT PUTS THE CONTEXT IN PLACE, DRAWS, AND PUTS THE LAST ONE BACK — so a block cannot leave the probe
 * drawing into somebody else's surface. */
static void drawWith(CGContextRef cg, BOOL flipped, NSImage *image, NSRect dst, NSRect src,
		     NSCompositingOperation op, CGFloat delta, BOOL respectFlipped, NSDictionary *hints)
{
	NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:flipped];
	NSGraphicsContext *previous = [[NSGraphicsContext currentContext] retain];

	[NSGraphicsContext setCurrentContext:g];
	[image drawInRect:dst fromRect:src operation:op fraction:delta respectFlipped:respectFlipped hints:hints];
	[NSGraphicsContext setCurrentContext:previous];
	[previous release];
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

		/* ============================================================================================
		 * AND THE WIDE DOOR: WHAT PART, HOW, HOW MUCH, WHICH WAY UP, AND WITH WHAT HINTS.
		 * ============================================================================================ */
		{
			NSImage *pic = [[NSImage alloc] initWithSize:NSMakeSize(IMAGE_SIDE, IMAGE_SIDE)];
			CGContextRef cg;
			unsigned char *px;
			NSRect whole = NSMakeRect(0.0, 0.0, IMAGE_SIDE, IMAGE_SIDE);

			[rep setSize:NSMakeSize(IMAGE_SIDE, IMAGE_SIDE)];
			[pic addRepresentation:rep];
			check([pic backgroundColor] == nil && [pic delegate] == nil,
			      "a fresh image has no background colour and no delegate");

			/* 1. A CROP OF THE TOP HALF, STRETCHED OVER THE WHOLE DESTINATION, IS ALL RED. The source rect is in the
			 * REP's own space and a CGImage's rows run DOWN from its top, so y 0..4 is the red half. */
			cg = newContext(NO, IMAGE_SIDE);
			drawWith(cg, NO, pic, whole, NSMakeRect(0.0, 0.0, IMAGE_SIDE, IMAGE_SIDE / 2.0),
				 NSCompositingOperationCopy, 1.0, YES, nil);
			px = CGBitmapContextGetData(cg);
			printf("  (note: a top-half crop drew red at row 0: %d, at row 7: %d)\n",
			       row_is_red(px), row_is_red(px + (IMAGE_SIDE - 1) * ROW_BYTES));
			check(row_is_red(px) && row_is_red(px + (IMAGE_SIDE - 1) * ROW_BYTES),
			      "`fromRect:` takes the source's own rows — a crop of the top half stretched is all red");
			CGContextRelease(cg);

			cg = newContext(NO, IMAGE_SIDE);
			drawWith(cg, NO, pic, whole, NSMakeRect(0.0, IMAGE_SIDE / 2.0, IMAGE_SIDE, 4.0),
				 NSCompositingOperationCopy, 1.0, YES, nil);
			px = CGBitmapContextGetData(cg);
			check(row_is_blue(px) && row_is_blue(px + (IMAGE_SIDE - 1) * ROW_BYTES),
			      "and the BOTTOM half's crop is all blue — the rect selects which half, not which way up");
			CGContextRelease(cg);

			/* 2. THE FRACTION AND THE OPERATION. Over a GREEN ground: SourceOver at half strength blends, and Copy
			 * at full strength does not. MEASURED with the green written FIRST, so the two draws see the same
			 * destination. */
			{
				int i;

				for (i = 0; i < 2; i++) {
					cg = newContext(NO, IMAGE_SIDE);
					px = CGBitmapContextGetData(cg);
					CGContextSetRGBFillColor(cg, 0.0, 1.0, 0.0, 1.0);
					CGContextFillRect(cg, CGRectMake(0.0, 0.0, IMAGE_SIDE, IMAGE_SIDE));
					drawWith(cg, NO, pic, whole, NSZeroRect,
						 i == 0 ? NSCompositingOperationCopy : NSCompositingOperationSourceOver,
						 i == 0 ? 1.0 : 0.5, YES, nil);
					if (i == 0) {
						unsigned char *first = CGBitmapContextGetData(cg);

						check(row_is_red(first) || row_is_blue(first),
						      "Copy at full strength REPLACES the ground — the picture, not a blend");
						CGContextRelease(cg);
					} else {
						unsigned char *half = CGBitmapContextGetData(cg);
						int blended = !row_is_red(half) && !row_is_blue(half) && half[1] > 40;

						printf("  (note: half-strength SourceOver over green gave B=%d G=%d R=%d)\n",
						       half[0], half[1], half[2]);
						check(blended, "and half-strength SourceOver BLENDS with the ground");
						CGContextRelease(cg);
					}
				}
			}

			/* 3. THE BACKGROUND IS PUT DOWN FIRST. A rep whose bytes are all zero is fully TRANSPARENT, so a white
			 * ground behind a red background must come out RED — which is what makes the door more than storage. */
			{
				NSImage *clear = [[NSImage alloc] initWithSize:NSMakeSize(IMAGE_SIDE, IMAGE_SIDE)];
				NSBitmapImageRep *blank = [[NSBitmapImageRep alloc]
					initWithBitmapDataPlanes:NULL pixelsWide:IMAGE_SIDE pixelsHigh:IMAGE_SIDE
						   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						 colorSpaceName:NSDeviceRGBColorSpace
						    bytesPerRow:ROW_BYTES bitsPerPixel:32];

				[clear addRepresentation:blank];
				[clear setBackgroundColor:[NSColor redColor]];
				check([[clear backgroundColor] isEqual:[NSColor redColor]],
				      "`-setBackgroundColor:` round-trips through the image");
				cg = newContext(NO, IMAGE_SIDE);
				px = CGBitmapContextGetData(cg);
				CGContextSetRGBFillColor(cg, 1.0, 1.0, 1.0, 1.0);
				CGContextFillRect(cg, CGRectMake(0.0, 0.0, IMAGE_SIDE, IMAGE_SIDE));
				drawWith(cg, NO, clear, whole, NSZeroRect, NSCompositingOperationSourceOver, 1.0, YES, nil);
				printf("  (note: over a white ground, a transparent image with a red background gave R=%d)\n", px[2]);
				check(px[2] > 200 && px[1] < 60 && px[0] < 60,
				      "a transparent image over a RED background leaves red — the colour goes down first");
				CGContextRelease(cg);
				[blank release];
				[clear release];
			}

			/* 4. THE HINT IS THE CONTEXT'S INTERPOLATION FOR ONE DRAW, AND THE QUALITY THIS TIER CANNOT FILTER IS
			 * REFUSED RATHER THAN FAKED. MEASURED while writing this: `NSImageInterpolationHigh` maps to
			 * `kCGInterpolationHigh`, and this library's sampler has NEAREST and BILINEAR only — so the quality is
			 * REJECTED (with CoreGraphics' own refusal on stderr) and the context keeps what it had. The measurable
			 * pair is therefore None against MEDIUM: None leaves hard blocks and Medium blends, which is counted across
			 * a 4x upscale of a two-colour picture. */
			{
				NSMutableDictionary *none = [NSMutableDictionary dictionary];
				NSMutableDictionary *high = [NSMutableDictionary dictionary];
				int blendedNone = 0;
				int blendedHigh = 0;
				int x, y;

				[none setObject:[NSNumber numberWithInteger:NSImageInterpolationNone]
					 forKey:NSImageHintInterpolation];
				[high setObject:[NSNumber numberWithInteger:NSImageInterpolationMedium]
					 forKey:NSImageHintInterpolation];
				cg = newContext(NO, IMAGE_SIDE * 4);
				drawWith(cg, NO, pic, NSMakeRect(0.0, 0.0, IMAGE_SIDE * 4, IMAGE_SIDE * 4), NSZeroRect,
					 NSCompositingOperationCopy, 1.0, YES, none);
				px = CGBitmapContextGetData(cg);
				for (y = 0; y < IMAGE_SIDE * 4; y++) {
					for (x = 0; x < IMAGE_SIDE * 4; x++) {
						unsigned char *p = px + y * IMAGE_SIDE * 16 + x * 4;

						if (!row_is_red(p) && !row_is_blue(p) && p[3] > 0) {
							blendedNone++;
						}
					}
				}
				CGContextRelease(cg);
				cg = newContext(NO, IMAGE_SIDE * 4);
				drawWith(cg, NO, pic, NSMakeRect(0.0, 0.0, IMAGE_SIDE * 4, IMAGE_SIDE * 4), NSZeroRect,
					 NSCompositingOperationCopy, 1.0, YES, high);
				px = CGBitmapContextGetData(cg);
				for (y = 0; y < IMAGE_SIDE * 4; y++) {
					for (x = 0; x < IMAGE_SIDE * 4; x++) {
						unsigned char *p = px + y * IMAGE_SIDE * 16 + x * 4;

						if (!row_is_red(p) && !row_is_blue(p) && p[3] > 0) {
							blendedHigh++;
						}
					}
				}
				printf("  (note: a 4x upscale has %d blended points at interpolation None and %d at Medium)\n",
				       blendedNone, blendedHigh);
				check(blendedHigh > 0, "an `NSImageHintInterpolation` of Medium blends the upscale");
				check(blendedNone < blendedHigh,
				      "and None does not — so the hint reaches the context rather than being stored");
				CGContextRelease(cg);
			}

			/* 5. THE DELEGATE, WHICH IS ASKED WHEN NOTHING CAN DRAW. An image with NO representations has no rep to
			 * choose; the delegate answers with one, and the picture proves the substitute was used rather than
			 * merely that a method ran. */
			{
				NSImage *empty = [[NSImage alloc] initWithSize:NSMakeSize(IMAGE_SIDE, IMAGE_SIDE)];
				AGRepDelegate *watcher = [[AGRepDelegate alloc] initWithRep:rep];

				[empty setDelegate:(id <NSImageDelegate>)watcher];
				check([empty delegate] == (id)watcher, "`-setDelegate:` round-trips through the image");
				cg = newContext(NO, IMAGE_SIDE);
				drawWith(cg, NO, empty, whole, NSZeroRect, NSCompositingOperationCopy, 1.0, YES, nil);
				px = CGBitmapContextGetData(cg);
				printf("  (note: an image with no reps asked its delegate %d time(s))\n", watcher->calls);
				check(watcher->calls == 1, "an image with NO representation asks its delegate once");
				check(row_is_red(px) && row_is_blue(px + (IMAGE_SIDE - 1) * ROW_BYTES),
				      "and the rep the delegate answered is the picture that was drawn");
				CGContextRelease(cg);
				[watcher release];
				[empty release];
			}

			[pic release];
		}

		[rep release];
		CGImageRelease(image);
	}
	printf("image_draw: %d check(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
