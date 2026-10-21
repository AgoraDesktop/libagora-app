/*
 * AGSystemImages.m — a name, a glyph, and the pixels in between.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE COVERAGE IS TURNED INTO TWO THINGS PER NAME, AND THEY ARE DIFFERENT ON PURPOSE:
 *
 *   an `NSBitmapImageRep` per size, black on transparency, which is what `-drawInRect:` draws when a caller
 *   asks for the picture and does not say what ink it wants; and
 *   a CGImage MASK per size, which is what `-cg_drawInRect:ink:` clips to before filling with the caller's ink.
 *
 * The first is a picture and the second is a stencil of it. Keeping both costs a few kilobytes per name and
 * buys the one behaviour that matters — a template image is allowed to be drawn in any ink — without a
 * second rasterizer or a per-colour cache.
 *
 * THE MASK IS THE INVERSE OF THE COVERAGE, and that is CoreGraphics' convention rather than a choice here:
 * an IMAGE MASK's samples are "1 blocks, 0 paints", so a glyph's solid pixel (coverage 255) has to become
 * mask sample 0. `fn_mask_from_coverage` is the one place that knows it, and it says so.
 */
#import "AGSystemImages.h"

#import "NSImage_internal.h"
#import "SystemImageMasks.h"
#import "SystemImageNames.h"

#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImage.h>

#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGImage.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDictionary.h>

#include <stdlib.h>
#include <string.h>

/* ONE NAME'S PICTURE, already made: the image a caller gets, and the two masks it carries. */
typedef struct {
	NSImage *image;			/* RETAINED by the cache */
} AGSystemImageEntry;

static AGSystemImageEntry *s_entries;
static unsigned s_entryCount;

/* THE COVERAGE, AS A MASK. `CGImageMaskCreate` takes 8 bits per pixel and one byte per row per pixel; the
 * samples are INVERTED here because a CG image mask's zero is "paint". The bytes are this glyph's own, so the
 * provider is given a COPY that it owns — the table is `const` and lives for the process's lifetime, which
 * would make a provider over it safe today and a dangling pointer the first time anything reloaded the table. */
static CGImageRef fn_mask_from_coverage(const unsigned char *coverage, int side)
{
	size_t size = (size_t)side * (size_t)side;
	unsigned char *samples = malloc(size);
	CGDataProviderRef provider;
	CGImageRef mask;

	if (samples == NULL) {
		return NULL;
	}
	{
		size_t i;

		for (i = 0; i < size; i++) {
			samples[i] = (unsigned char)(255u - coverage[i]);
		}
	}
	provider = CGDataProviderCreateWithData(NULL, samples, size, NULL);
	if (provider == NULL) {
		free(samples);
		return NULL;
	}
	/* **`shouldInterpolate` IS TRUE, AND THAT IS THE DIFFERENCE BETWEEN A SCALED GLYPH AND A BLOCKY ONE.** A stencil
	 * drawn at a size the table does not carry is scaled; nearest-neighbour sampling made that look like a low
	 * resolution version of the picture (MEASURED, and it is what "the arrows look like crap" was). At a native
	 * size the sample lands on texel centres, so this costs nothing there. */
	mask = CGImageMaskCreate((size_t)side, (size_t)side, 8, 8, (size_t)side, provider, NULL, true);
	CGDataProviderRelease(provider);
	if (mask == NULL) {
		free(samples);
	}
	/* THE PROVIDER KEEPS THE BYTES when it was made over them without a release callback; `CGDataProviderCreate-
	 * WithData` with a NULL release function does NOT take ownership, so the mask's provider owns `samples` only
	 * for as long as this image lives — and the image is the cache's, which is the process's. */
	return mask;
}

/* THE PICTURE: black ink, coverage for alpha, one row at a time. It is what a plain `-drawInRect:` paints. */
static NSBitmapImageRep *fn_rep_from_coverage(const unsigned char *coverage, int side)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:side
								      pixelsHigh:side bitsPerSample:8 samplesPerPixel:4
								      hasAlpha:YES isPlanar:NO
								      colorSpaceName:NSDeviceRGBColorSpace
								      bytesPerRow:side * 4 bitsPerPixel:32];
	unsigned char *pixels;
	int y;

	if (rep == nil) {
		return nil;
	}
	pixels = [rep bitmapData];
	if (pixels == NULL) {
		[rep release];
		return nil;
	}
	/* PREMULTIPLIED, because that is the format an NSBitmapImageRep's CGImage declares: black ink means the
	 * colour channels are ZERO wherever the glyph is, and the alpha byte is the coverage. */
	for (y = 0; y < side; y++) {
		int x;

		for (x = 0; x < side; x++) {
			unsigned char *p = pixels + (size_t)y * (size_t)side * 4u + (size_t)x * 4u;

			p[0] = 0;
			p[1] = 0;
			p[2] = 0;
			p[3] = coverage[(size_t)y * (size_t)side + (size_t)x];
		}
	}
	return rep;
}

static NSImage *fn_image_for_glyph(const AGSystemImageGlyph *glyph)
{
	NSBitmapImageRep *rep16 = fn_rep_from_coverage(glyph->coverage16, 16);
	NSBitmapImageRep *rep24 = fn_rep_from_coverage(glyph->coverage24, 24);
	NSBitmapImageRep *rep32 = fn_rep_from_coverage(glyph->coverage32, 32);
	CGImageRef mask16 = fn_mask_from_coverage(glyph->coverage16, 16);
	CGImageRef mask24 = fn_mask_from_coverage(glyph->coverage24, 24);
	CGImageRef mask32 = fn_mask_from_coverage(glyph->coverage32, 32);
	NSImage *image;

	if (rep16 == nil || rep24 == nil || rep32 == nil ||
	    mask16 == NULL || mask24 == NULL || mask32 == NULL) {
		[rep16 release];
		[rep24 release];
		[rep32 release];
		if (mask16 != NULL) {
			CGImageRelease(mask16);
		}
		if (mask24 != NULL) {
			CGImageRelease(mask24);
		}
		if (mask32 != NULL) {
			CGImageRelease(mask32);
		}
		return nil;
	}
	image = [[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)];
	/* **EACH REP DECLARES ITS OWN SIZE IN POINTS, WHICH IS WHAT MAKES `-bestRepresentationForRect:` CHOOSE.**
	 * The rule is "closest in points", so a 24-point draw picks the 24-pixel rep and gets a 1:1 sample of the
	 * glyph; three reps all claiming sixteen would make the choice arbitrary and draw the smallest of them into
	 * every size the tier asks for. The IMAGE's own size stays sixteen — that is the size a caller measures when
	 * it asks how big this picture is, and the era's template images are sixteen points. */
	[rep24 setSize:NSMakeSize(24.0, 24.0)];
	[rep32 setSize:NSMakeSize(32.0, 32.0)];
	[image addRepresentation:rep16];
	[image addRepresentation:rep24];
	[image addRepresentation:rep32];
	/* THE TEMPLATE FLAG AND THE STENCILS, TOGETHER: an image is a template BECAUSE it can be drawn in any ink,
	 * and the flag without the masks would be a promise with nothing behind it. */
	[image cg_setTemplateMask:mask16 forSize:16];
	[image cg_setTemplateMask:mask24 forSize:24];
	[image cg_setTemplateMask:mask32 forSize:32];
	[image setName:[NSString stringWithUTF8String:glyph->name]];
	[rep16 release];
	[rep24 release];
	[rep32 release];
	CGImageRelease(mask16);
	CGImageRelease(mask24);
	CGImageRelease(mask32);
	return image;
}

NSImage *AGSystemImageNamed(NSString *name)
{
	const char *wanted;
	unsigned i;

	if (name == nil) {
		return nil;
	}
	wanted = [name UTF8String];
	if (wanted == NULL) {
		return nil;
	}
	for (i = 0; i < AGSystemImageNameCount; i++) {
		/* THE TABLE HOLDS THE ADDRESS OF EACH CONSTANT, so the comparison dereferences it — and the constant's
		 * own VALUE is what `+imageNamed:` was handed. */
		if (strcmp([*AGSystemImageNames[i].appleName UTF8String], wanted) != 0) {
			continue;
		}
		if (s_entries == NULL) {
			s_entries = calloc(AGSystemImageNameCount, sizeof *s_entries);
			if (s_entries == NULL) {
				return nil;
			}
			s_entryCount = (unsigned)AGSystemImageNameCount;
		}
		if (s_entries[i].image == nil) {
			unsigned g;

			for (g = 0; g < AGSystemImageGlyphCount; g++) {
				if (strcmp(AGSystemImageGlyphs[g].name, AGSystemImageNames[i].glyph) == 0) {
					s_entries[i].image = fn_image_for_glyph(&AGSystemImageGlyphs[g]);
					break;
				}
			}
		}
		return s_entries[i].image;
	}
	return nil;
}

unsigned AGSystemImageCount(void)
{
	return (unsigned)AGSystemImageNameCount;
}

NSString *AGSystemImageNameAtIndex(unsigned index)
{
	if (index >= AGSystemImageNameCount) {
		return nil;
	}
	return *AGSystemImageNames[index].appleName;
}
