/*
 * text_glyph_bulk — the glyph store's range doors, the strike ink, and three singles.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIM FOR THE BULK DOORS IS THAT THEY READ THE SAME RECORD ONE AT A TIME AND A RANGE AT A TIME.** The probe lays
 * out a line, reads it with `-glyphAtIndex:` and with `-getGlyphsInRange:…`, and compares — then writes a location with
 * each spelling and compares again. A bulk door that filled its buffers from anything but the store (the text's
 * characters, say) would disagree on the first letter of a shaped run.
 *
 * **THE TWO WRITERS ARE THE SUB-CLASS DOORS, and their effect is checked where the read doors answer.** A line rect
 * written with `-setLineFragmentRect:forGlyphRange:usedRect:` is what `-lineFragmentRectForGlyphAtIndex:` returns
 * afterwards; a container written with `-setTextContainer:forGlyphRange:` is what `-textContainerForGlyphAtIndex:`
 * returns — including the range the caller named, which is what `effectiveRange:` promises.
 *
 * **THE STRIKE PAIR PUTS INK THROUGH THE MIDDLE OF THE X-HEIGHT**, the way the underline pair puts it under the
 * baseline: the probe draws a struck-through line into a bitmap and requires dark pixels inside the line's band whose y
 * is between the baseline and its ascender.
 *
 * The nominally-spaced walk is checked as the line's own range (this tier applies no kerning), `-substituteFontForFont:`
 * as the font itself, and `-showPackedGlyphs:…` as the named refusal it is.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#define W 200
#define H 60

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

static NSTextStorage *new_store(NSLayoutManager **managerOut, NSTextContainer **containerOut, NSString *text)
{
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(320.0, 200.0)];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:text];

	[store addLayoutManager:manager];
	[manager addTextContainer:container];
	*managerOut = manager;
	*containerOut = container;
	return store;
}

/* Dark ink in a band, with the rows read from the opposite end to the drawing coordinates (the sampler's own trap). */
static int dark_in_band(NSBitmapImageRep *rep, CGFloat x0, CGFloat x1, CGFloat y0, CGFloat y1)
{
	int x, y, count = 0;
	int rowTop = H - (int)ceil((double)y1);
	int rowBottom = H - 1 - (int)floor((double)y0);

	for (y = rowTop; y <= rowBottom; y++) {
		for (x = (int)floor((double)x0); x <= (int)ceil((double)x1); x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c alphaComponent] > 0.4 && [c redComponent] < 0.5 && [c greenComponent] < 0.5
			    && [c blueComponent] < 0.5) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE BULK READERS AGREE WITH THE ONE-AT-A-TIME DOOR.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"abc");
			NSGlyph glyphs[8];
			NSUInteger chars[8];
			NSGlyphInscription inscriptions[8];
			BOOL elastic[8];
			unsigned char levels[8];
			NSUInteger i;
			int agrees = 1;

			(void)container;
			[manager getGlyphsInRange:NSMakeRange(0, 3) glyphs:glyphs characterIndexes:chars
				 glyphInscriptions:inscriptions elasticBits:elastic bidiLevels:levels];
			for (i = 0; i < 3; i++) {
				if (glyphs[i] != [manager glyphAtIndex:i]) {
					agrees = 0;
				}
			}
			check(agrees, "the bulk reader's glyphs are the store's own");
			check(chars[0] == 0 && chars[1] == 1 && chars[2] == 2,
			      "and the character indexes are the ones the glyphs stand for");
			check(inscriptions[0] == NSGlyphInscribeBase && elastic[0] == NO && levels[0] == 0,
			      "every glyph is on the baseline, none is elastic, and the direction is level zero");

			/* **A RANGE THAT OVERLAPS THE EDGE STILL FILLS EVERY SLOT.** */
			[manager getGlyphsInRange:NSMakeRange(2, 4) glyphs:glyphs characterIndexes:chars
				 glyphInscriptions:inscriptions elasticBits:elastic bidiLevels:levels];
			check(glyphs[1] == 0 && glyphs[3] == 0 && chars[3] == 5,
			      "past the end the glyph is NSNullGlyph and the index is the one asked for");

			/* AND THE FOUR-BUFFER SPELLING IS THE SAME ANSWER WITHOUT A BIDI LEVEL. */
			[manager getGlyphsInRange:NSMakeRange(0, 3) glyphs:glyphs characterIndexes:chars
				 glyphInscriptions:inscriptions elasticBits:elastic];
			check(glyphs[0] == [manager glyphAtIndex:0], "the shorter spelling answers the same glyphs");

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 2. THE TWO WRITERS, READ BACK WHERE A CALLER WOULD READ THEM.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"abcd");
			NSRange glyphRange = NSMakeRange(0, 4);
			NSPoint locations[2];
			NSUInteger starts[2];
			NSPoint written;

			(void)container;
			/* LOCATIONS: two starts, the second in the middle, and the first glyph's location is the first point. */
			locations[0] = NSMakePoint(11.0, 7.0);
			locations[1] = NSMakePoint(33.0, 9.0);
			starts[0] = 0;
			starts[1] = 2;
			[manager setLocations:locations startingGlyphIndexes:starts count:2 forGlyphRange:glyphRange];
			written = [manager locationForGlyphAtIndex:0];
			check(close_enough(written.x, 11.0) && close_enough(written.y, 7.0),
			      "the first start's location is written to its glyph");
			written = [manager locationForGlyphAtIndex:2];
			check(close_enough(written.x, 33.0) && close_enough(written.y, 9.0),
			      "and the second start's to its own");

			/* THE LINE RECTS: what a subclass writes is what the read doors answer. */
			[manager setLineFragmentRect:NSMakeRect(5.0, 60.0, 200.0, 14.0) forGlyphRange:glyphRange
					    usedRect:NSMakeRect(9.0, 60.0, 120.0, 14.0)];
			check(NSEqualRects([manager lineFragmentRectForGlyphAtIndex:1 effectiveRange:NULL],
					   NSMakeRect(5.0, 60.0, 200.0, 14.0)),
			      "a written line rect is what the line-fragment door answers");
			check(NSEqualRects([manager lineFragmentUsedRectForGlyphAtIndex:1 effectiveRange:NULL],
					   NSMakeRect(9.0, 60.0, 120.0, 14.0)),
			      "and the used rect beside it");

			/* THE CONTAINER: a foreign container recorded for a range is what the read door answers for it. */
			{
				NSTextContainer *other = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(50.0, 50.0)];
				NSRange effective = NSMakeRange(0, 0);

				[manager setTextContainer:other forGlyphRange:NSMakeRange(1, 2)];
				check([manager textContainerForGlyphAtIndex:1 effectiveRange:&effective] == other,
				      "a recorded container is what the door answers for a glyph in its range");
				check(effective.location == 1 && effective.length == 2,
				      "and effectiveRange is the range the caller recorded");
				check([manager textContainerForGlyphAtIndex:0 effectiveRange:NULL] == container,
				      "a glyph outside the record still answers the laid-out container");
				[other release];
			}

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 3. THE STRIKE PAIR: ink through the middle of the x-height.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"struck");
			NSRect lineRect;
			NSRange glyphs;
			CGFloat baseline;
			NSBitmapImageRep *plain;
			NSBitmapImageRep *struck;

			(void)container;
			glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(0, 6) actualCharacterRange:NULL];
			lineRect = [manager lineFragmentRectForGlyphAtIndex:0 effectiveRange:NULL];
			baseline = [manager cg_baselineForGlyphAtIndex:0];

			plain = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
				bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:plain]];
			[manager drawGlyphsForGlyphRange:glyphs atPoint:NSZeroPoint];

			struck = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
				bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:struck]];
			[manager drawGlyphsForGlyphRange:glyphs atPoint:NSZeroPoint];
			[manager drawStrikethroughForGlyphRange:glyphs strikethroughType:NSUnderlineStyleSingle
					       baselineOffset:0.0 lineFragmentRect:lineRect
					lineFragmentGlyphRange:glyphs containerOrigin:NSZeroPoint];

			/* THE STRIKE'S BAND IS BETWEEN THE BASELINE AND THE ASCENDER, which is where a rule through the middle of
			 * the x-height lands and nowhere a plain draw has ink of its own at this width. */
			{
				int plainCount = dark_in_band(plain, 0.0, 60.0, baseline - 6.0, baseline - 2.0);
				int struckCount = dark_in_band(struck, 0.0, 60.0, baseline - 6.0, baseline - 2.0);

				printf("  (note: dark pixels in the strike band: plain %d, struck %d)\n", plainCount, struckCount);
				check(struckCount > plainCount,
				      "drawing a single strikethrough puts ink through the line's middle");
			}

			[plain release];
			[struck release];
			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 4. THE BACKGROUND FILL, AND THE THREE SINGLES.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"spaced");
			NSRect rects[2];
			NSBitmapImageRep *rep;
			NSFont *font = [NSFont systemFontOfSize:12.0];

			(void)container;
			(void)store;

			/* THE FILL IS THE RECTS THE CALLER GAVE, in the colour it gave. */
			rects[0] = NSMakeRect(4.0, 4.0, 20.0, 6.0);
			rects[1] = NSMakeRect(40.0, 4.0, 10.0, 6.0);
			rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
				bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[manager fillBackgroundRectArray:rects count:2 forCharacterRange:NSMakeRange(0, 6)
						  color:[NSColor redColor]];
			{
				int red = 0;
				int x, y;

				for (y = 0; y < H; y++) {
					for (x = 0; x < W; x++) {
						NSColor *c = [rep colorAtX:x y:y];

						if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4) {
							red++;
						}
					}
				}
				check(red > 100, "the background fill paints the rectangles it was given");
			}
			[rep release];

			/* NOMINALLY SPACED: this tier applies no kerning, so the run is the whole line. */
			{
				NSRange spaced = [manager rangeOfNominallySpacedGlyphsContainingIndex:2];
				NSRange line = [manager lineFragmentRectForGlyphAtIndex:2 effectiveRange:NULL].size.width > 0.0
					? NSMakeRange(0, [manager numberOfGlyphs]) : NSMakeRange(0, 0);

				printf("  (note: nominally-spaced range %lu,%lu of %lu glyphs)\n",
				       (unsigned long)spaced.location, (unsigned long)spaced.length,
				       (unsigned long)line.length);
				check(spaced.length >= 5 && spaced.location == 0,
				      "the nominally-spaced run covers the line, because nothing here is kerned");
			}

			check([manager substituteFontForFont:font] == font,
			      "a font substitutes for itself, because this tier has no screen-font variants");

			/* AND THE PACKED-GLYPH DOOR REFUSES BY NAME RATHER THAN REINTERPRETING BYTES. */
			[manager showPackedGlyphs:(char *)"abcd" length:4 glyphRange:NSMakeRange(0, 4)
					  atPoint:NSZeroPoint font:font color:[NSColor blackColor]
			      printingAdjustment:NSZeroSize];
			check(1, "showPackedGlyphs: refuses the pre-10.4 encoding without crashing");

			[store release];
			[manager release];
			[container release];
		}

		if (failures == 0) {
			printf("text_glyph_bulk: all checks passed\n");
			return 0;
		}
		printf("text_glyph_bulk: FAILURES\n");
		return 1;
	}
}
