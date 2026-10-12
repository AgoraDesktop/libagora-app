/* NSGraphics.m — the window-depth vocabulary.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 */
#import <AppKit/NSGraphics.h>
#import <Foundation/NSString.h>

/* THE ONE TABLE, because the depths ARE a closed set Apple publishes: three constants and nothing else. The
 * extractors answer from it, so their answers cannot disagree with the constants — which a bit-shuffle of the
 * same encoding could, silently, on the day a fourth depth appears. */
typedef struct {
	NSWindowDepth depth;
	NSInteger bitsPerSample;
	NSInteger bitsPerPixel;
	BOOL planar;
	NSString *colorSpace;
} FNDepthFacts;

static FNDepthFacts s_depths[] = {
	{ NSWindowDepthTwentyfourBitRGB,             8,  32, NO, @"NSCalibratedRGBColorSpace" },
	{ NSWindowDepthSixtyfourBitRGB,             16,  64, NO, @"NSCalibratedRGBColorSpace" },
	{ NSWindowDepthOnehundredtwentyeightBitRGB, 32, 128, NO, @"NSCalibratedRGBColorSpace" },
};

#define FN_DEPTH_COUNT ((NSInteger)(sizeof(s_depths) / sizeof(s_depths[0])))

static FNDepthFacts *fn_facts(NSWindowDepth depth)
{
	NSInteger i;

	for (i = 0; i < FN_DEPTH_COUNT; i++) {
		if (s_depths[i].depth == depth) {
			return &s_depths[i];
		}
	}
	return NULL;
}

/* AND THE DEFAULT DEPTH IS THE 24-BIT ONE, which Apple states in its own header ("NSWindowDepthTwentyfourBitRGB
 * is the default") — so a window that never set a limit answers this rather than zero. */
static NSWindowDepth fn_resolve(NSWindowDepth depth)
{
	return (depth == 0) ? NSWindowDepthTwentyfourBitRGB : depth;
}

NSInteger NSBitsPerSampleFromDepth(NSWindowDepth depth)
{
	FNDepthFacts *f = fn_facts(fn_resolve(depth));

	return (f != NULL) ? f->bitsPerSample : -1;	/* -1 REFUSES rather than guessing — see the header */
}

NSInteger NSBitsPerPixelFromDepth(NSWindowDepth depth)
{
	FNDepthFacts *f = fn_facts(fn_resolve(depth));

	return (f != NULL) ? f->bitsPerPixel : -1;
}

BOOL NSPlanarFromDepth(NSWindowDepth depth)
{
	FNDepthFacts *f = fn_facts(fn_resolve(depth));

	return (f != NULL) ? f->planar : NO;
}

NSString *NSColorSpaceFromDepth(NSWindowDepth depth)
{
	FNDepthFacts *f = fn_facts(fn_resolve(depth));

	return (f != NULL) ? f->colorSpace : nil;
}

/* THE SENTINEL IS THE ZERO, which is the same value that MEANS "the default" everywhere else in this
 * vocabulary — so a caller that walked past the end and took the zero as a depth would get the default rather
 * than a crash. That is Apple's own choice of sentinel and it is worth saying out loud. */
static const NSWindowDepth s_available[] = {
	NSWindowDepthTwentyfourBitRGB,
	NSWindowDepthSixtyfourBitRGB,
	NSWindowDepthOnehundredtwentyeightBitRGB,
	0
};

const NSWindowDepth *NSAvailableWindowDepths(void)
{
	return s_available;
}

NSWindowDepth NSBestDepth(NSString *colorSpace, NSInteger bps, NSInteger bpp, BOOL isPlanar, BOOL *exactMatch)
{
	FNDepthFacts *best = NULL;
	BOOL bestExact = NO;
	NSInteger i;

	for (i = 0; i < FN_DEPTH_COUNT; i++) {
		FNDepthFacts *f = &s_depths[i];
		BOOL cs = (colorSpace == nil) || [f->colorSpace isEqual:colorSpace];
		/* "MATCH OR BETTER", which is Apple's wording: a depth that offers AT LEAST what was asked for is a
		 * candidate, and the smallest such candidate is the answer. */
		BOOL ok = cs && f->bitsPerSample >= bps &&
			  (bpp <= 0 || f->bitsPerPixel >= bpp) && (f->planar == isPlanar);

		if (ok) {
			best = f;
			/* THE EXACT MATCH IS ALL FOUR, which is what the flag reports — a depth that accommodated a larger
			 * request is an answer, and not an exact one. */
			bestExact = cs && (f->bitsPerSample == bps) &&
				    (bpp <= 0 || f->bitsPerPixel == bpp) && (f->planar == isPlanar);
			break;	/* ascending order, so the FIRST candidate is the smallest that fits */
		}
	}
	if (best == NULL) {
		if (exactMatch != NULL) {
			*exactMatch = NO;
		}
		return 0;	/* NOTHING FITS, and zero is the vocabulary's "no depth" — see the sentinel note above */
	}
	if (exactMatch != NULL) {
		*exactMatch = bestExact;
	}
	return best->depth;
}
