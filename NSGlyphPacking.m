/*
 * NSGlyphPacking.m — `NSConvertGlyphsToPackedGlyphs`.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * SPDX-License-Identifier: MIT
 *
 * **THE THREE INTEGER-WIDTH PACKINGS ARE REAL AND THE TWO EUC PACKINGS REFUSE.** A glyph buffer in this tier is a run of
 * 16-bit `NSGlyph` values, and moving each into one, two or four bytes is a shift and a store. European/Japanese EUC is
 * a VARIABLE-LENGTH character encoding — it is not a width, and writing it would mean implementing an encoding table
 * this tier has no other use for. So `NSJapaneseEUCGlyphPacking` and `NSAsciiWithDoubleByteEUCGlyphPacking` name what
 * they need instead of emitting a plausible byte stream that a consumer would misread.
 *
 * **WITH A NULL BUFFER THE DOOR ANSWERS THE SIZE**, which is what its documentation says and what a caller asks first:
 * a two-pass caller sizes the buffer here and fills it on the second call.
 */
#import <AppKit/NSFont.h>
#import <AppKit/AppKitRefusal.h>

#include <stddef.h>

static NSInteger fn_bytes_per_glyph(NSMultibyteGlyphPacking packing)
{
	switch (packing) {
	case NSOneByteGlyphPacking:	return 1;
	case NSTwoByteGlyphPacking:	return 2;
	case NSFourByteGlyphPacking:	return 4;
	case NSJapaneseEUCGlyphPacking:
	case NSAsciiWithDoubleByteEUCGlyphPacking:
	default:			return -1;	/* variable-length: no width to multiply by */
	}
}

NSInteger NSConvertGlyphsToPackedGlyphs(NSGlyph *glBuf, NSInteger count, NSMultibyteGlyphPacking packing,
					char *packedGlyphs)
{
	NSInteger width = fn_bytes_per_glyph(packing);
	NSInteger i;

	if (glBuf == NULL || count <= 0) {
		return 0;
	}
	if (width < 0) {
		fn_refuse_window("NSConvertGlyphsToPackedGlyphs", "an EUC encoding table (the two EUC packings are "
				 "variable-length encodings, not widths)");
		return 0;
	}
	if (packedGlyphs == NULL) {
		return count * width;		/* the size the caller needs */
	}
	for (i = 0; i < count; i++) {
		unsigned long glyph = (unsigned long)glBuf[i];
		NSInteger b;

		/* BIG-ENDIAN, high byte first, which is the order the era's byte consumers read. */
		for (b = 0; b < width; b++) {
			packedGlyphs[i * width + b] = (char)((glyph >> (8 * (width - 1 - b))) & 0xFF);
		}
	}
	return count * width;
}
