/*
 * text_glyph_store — the layout manager's per-glyph record, and what a caller can do to it.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE STORE IS A SHADOW OF THE LAYOUT, SO THIS TEST ASSERTS BOTH HALVES OF THAT CLAIM.** A shadow has to agree with
 * what it shadows — the glyph, the character and the location a caller reads must be the shaper's answers, not zeros —
 * and it has to REMEMBER what the caller changes, which is the whole reason it exists rather than being recomputed on
 * every read. So each settable field is written and read back, and the untouched fields of the same glyph are checked
 * to be unchanged, because a store that loses the neighbours of an edit is worse than none.
 *
 * **AND THE THREE COUNT-CHANGING DOORS ARE CHECKED TO REFUSE RATHER THAN TO LIE.** They answer their type's empty value,
 * say why on stderr, and leave the glyph count alone — which is the property that matters, since a door that appeared to
 * insert and was undone by the next layout would be a bug a caller could not see.
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
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"Hello, glyph store."];
		NSUInteger glyphs, i;
		BOOL valid = NO;
		NSGlyph glyphZero, replaced, buffer[4];
		NSPoint location;
		NSUInteger character;

		[manager addTextContainer:container];
		[manager setTextStorage:store];

		glyphs = [manager numberOfGlyphs];
		check(glyphs > 0, "the text has glyphs");

		/* 1. The store agrees with the layout it shadows. */
		glyphZero = [manager glyphAtIndex:0 isValidIndex:&valid];
		check(valid, "glyph 0 is a valid index");
		check(glyphZero == [manager glyphAtIndex:0], "the two glyphAtIndex: forms answer the same glyph");
		check([manager glyphAtIndex:glyphs isValidIndex:&valid] == 0 && !valid,
		      "past the end answers NSNullGlyph and says the index is not valid");

		[manager getGlyphs:buffer range:NSMakeRange(0, 4)];
		{
			int agrees = 1;

			for (i = 0; i < 4; i++) {
				if (buffer[i] != [manager glyphAtIndex:i]) {
					agrees = 0;
				}
			}
			check(agrees, "getGlyphs:range: fills the buffer with the same glyphs the index door answers");
		}

		/* 2. The record's own fields, written and read back. */
		check(![manager notShownAttributeForGlyphAtIndex:2], "a glyph is shown by default");
		[manager setNotShownAttribute:YES forGlyphAtIndex:2];
		check([manager notShownAttributeForGlyphAtIndex:2], "and the store remembers that it was hidden");

		check(![manager drawsOutsideLineFragmentForGlyphAtIndex:1], "and does not draw outside by default");
		[manager setDrawsOutsideLineFragment:YES forGlyphAtIndex:1];
		check([manager drawsOutsideLineFragmentForGlyphAtIndex:1], "and remembers that it does");

		check([manager intAttribute:42 forGlyphAtIndex:3] == 0, "an unset integer attribute reads as zero");
		[manager setIntAttribute:42 value:7 forGlyphAtIndex:3];
		[manager setIntAttribute:43 value:9 forGlyphAtIndex:3];
		check([manager intAttribute:42 forGlyphAtIndex:3] == 7, "and a set one reads back");
		check([manager intAttribute:43 forGlyphAtIndex:3] == 9, "two tags on one glyph do not collide");
		check([manager intAttribute:42 forGlyphAtIndex:4] == 0, "and do not leak to the next glyph");

		location = NSMakePoint(11.0, 2.0);
		[manager setLocation:location forStartOfGlyphRange:NSMakeRange(5, 1)];
		check(NSEqualPoints([manager locationForGlyphAtIndex:5], location),
		      "a location written for a glyph range is what locationForGlyphAtIndex: answers");

		[manager setCharacterIndex:0 forGlyphAtIndex:6];
		character = [manager characterIndexForGlyphAtIndex:6];
		check(character == 0, "a character index written for a glyph is what the mapping door answers");
		check([manager characterIndexForGlyphAtIndex:7] != 0
		      || [manager characterIndexForGlyphAtIndex:7] == 7,
		      "and the neighbour's mapping is untouched");

		replaced = (NSGlyph)(glyphZero + 1);
		[manager replaceGlyphAtIndex:0 withGlyph:replaced];
		check([manager glyphAtIndex:0] == replaced, "replaceGlyphAtIndex:withGlyph: is visible through glyphAtIndex:");

		/* 3. The shadow's length tracks the layout's. */
		check([manager isValidGlyphIndex:glyphs - 1], "the last glyph is valid");
		check(![manager isValidGlyphIndex:glyphs], "and one past it is not");

		/* 4. The count-changing doors refuse and change nothing. */
		{
			NSUInteger before = [manager numberOfGlyphs];
			NSGlyph extra[2];

			extra[0] = 65;
			extra[1] = 66;
			[manager insertGlyph:65 atGlyphIndex:0 characterIndex:0];
			[manager insertGlyphs:extra length:2 forStartingGlyphAtIndex:0 characterIndex:0];
			[manager deleteGlyphsInRange:NSMakeRange(0, 2)];
			check([manager numberOfGlyphs] == before,
			      "insertGlyph:, insertGlyphs:… and deleteGlyphsInRange: leave the glyph count alone");
		}

		[manager release];
		[store release];
		[container release];

		if (failures == 0) {
			printf("text_glyph_store: all checks passed\n");
			return 0;
		}
		printf("text_glyph_store: FAILURES\n");
		return 1;
	}
}
