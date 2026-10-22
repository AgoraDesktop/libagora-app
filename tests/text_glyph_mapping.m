/*
 * text_glyph_mapping — the glyph-to-character mapping and the point doors.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE MAPPING IS NOT THE IDENTITY, AND THAT IS THE CLAIM WORTH TESTING.** A fragment keeps a CHARACTER span and a
 * GLYPH span separately because they differ — a ligature is one glyph for two characters — so these doors go through
 * the shaper's cluster table rather than subtracting. For plain ASCII the two spans coincide, which is what makes a
 * round trip a real check: if the mapping were arithmetic the round trip would pass trivially, and if it were wrong it
 * would fail on the first character.
 *
 * **THE POINT DOORS ARE CHECKED AGAINST A POINT BUILT FROM `-locationForGlyphAtIndex:`**, so the two halves have to
 * agree: the location says where glyph 0 sits inside its fragment, the fragment rect says where that fragment sits in
 * the container, and the point made of those two must hit character 0 and glyph 0. A sign error in either half breaks
 * the other's answer rather than hiding.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSAttributedString.h>
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

int main(void)
{
	@autoreleasepool {
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(240.0, 120.0)];
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:
			@"The quick brown fox jumps over the lazy dog."];
		NSUInteger length, i, glyphs;
		int roundTrips = 1, increasing = 1;
		NSRange firstFragment = NSMakeRange(NSNotFound, 0);
		NSRect fragmentRect;
		NSPoint location;
		NSUInteger charUnder = NSNotFound, glyphUnder = NSNotFound, glyphZero;
		CGFloat fraction = -1.0;

		[manager addTextContainer:container];
		[manager setTextStorage:store];

		length = [store length];
		glyphs = [manager numberOfGlyphs];
		check(length > 20 && glyphs > 0, "the store has text and the manager has laid it out");

		/* 1. The round trip. Plain ASCII is one glyph per character, so every index must survive the pair. */
		for (i = 0; i < length; i++) {
			NSUInteger glyph = [manager glyphIndexForCharacterAtIndex:i];
			NSUInteger back;

			if (glyph == NSNotFound) {
				roundTrips = 0;
				break;
			}
			back = [manager characterIndexForGlyphAtIndex:glyph];
			if (back != i) {
				roundTrips = 0;
				printf("        DBG char %lu -> glyph %lu -> char %lu\n", (unsigned long)i,
				       (unsigned long)glyph, (unsigned long)back);
				break;
			}
		}
		check(roundTrips, "every character survives glyphIndexForCharacterAtIndex: -> characterIndexForGlyphAtIndex:");

		/* 2. An index the manager has not got is NSNotFound rather than an exception. */
		check([manager glyphIndexForCharacterAtIndex:length] == NSNotFound,
		      "a character index past the end answers NSNotFound instead of raising");
		check([manager characterIndexForGlyphAtIndex:glyphs] == NSNotFound,
		      "and so does a glyph index past the end");

		/* 3. The locations advance along the line, and sit inside the fragment. */
		glyphZero = [manager glyphIndexForCharacterAtIndex:0];
		location = [manager locationForGlyphAtIndex:glyphZero];
		fragmentRect = [manager lineFragmentRectForGlyphAtIndex:glyphZero effectiveRange:&firstFragment];
		check(location.x >= 0.0 && location.x < fragmentRect.size.width,
		      "glyph 0's location is inside its own line fragment");
		for (i = 1; i < 10; i++) {
			NSUInteger g = [manager glyphIndexForCharacterAtIndex:i];
			NSPoint here = [manager locationForGlyphAtIndex:g];

			if (!(here.x > [manager locationForGlyphAtIndex:[manager glyphIndexForCharacterAtIndex:i - 1]].x)) {
				increasing = 0;
				break;
			}
		}
		check(increasing, "and successive glyphs advance to the right");

		/* 4. A point built from those two halves hits character 0 and glyph 0. */
		{
			NSPoint point = NSMakePoint(fragmentRect.origin.x + location.x + 1.0,
						    fragmentRect.origin.y + fragmentRect.size.height * 0.5);

			charUnder = [manager characterIndexForPoint:point inTextContainer:container
					fractionOfDistanceBetweenInsertionPoints:&fraction];
			check(charUnder == 0, "a point just inside the first glyph hits character 0");
			check(fraction >= 0.0 && fraction <= 1.0, "and the insertion fraction is a fraction");

			glyphUnder = [manager glyphIndexForPoint:point inTextContainer:container];
			check(glyphUnder == glyphZero, "the glyph door agrees with the character door about the same point");

			check([manager fractionOfDistanceThroughGlyphForPoint:point inTextContainer:container] >= 0.0,
			      "and the through-glyph fraction is a fraction too");
			check([manager glyphIndexForPoint:point inTextContainer:container
					 fractionOfDistanceThroughGlyph:NULL] == glyphZero,
			      "the two-argument glyph door answers the same index");
		}

		/* 5. A point far past the end still answers a nearest character rather than nonsense. */
		{
			NSPoint far = NSMakePoint(fragmentRect.origin.x + fragmentRect.size.width + 400.0,
						  fragmentRect.origin.y + fragmentRect.size.height * 0.5);
			NSUInteger nearest = [manager characterIndexForPoint:far inTextContainer:container
						fractionOfDistanceBetweenInsertionPoints:NULL];

			check(nearest != NSNotFound && nearest <= length,
			      "a point past the line answers the nearest character, not NSNotFound");
		}

		[manager release];
		[store release];
		[container release];

		if (failures == 0) {
			printf("text_glyph_mapping: all checks passed\n");
			return 0;
		}
		printf("text_glyph_mapping: FAILURES\n");
		return 1;
	}
}
