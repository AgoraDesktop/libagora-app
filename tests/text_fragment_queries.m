/*
 * text_fragment_queries — the layout manager's fragment queries.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THIS IS THE FIRST SLAB OF THE TEXT SYSTEM'S REMAINING SURFACE**, and it is the one that needs no cluster mapping:
 * the manager already keeps a fragment per line carrying the character span, the glyph span, two rects and a baseline,
 * so "is this index real", "how much is laid out", "which line holds this glyph" and "which container holds it" are
 * arithmetic over that record rather than a new model.
 *
 * **THE TWO CLAIMS THE HEADER MAKES ARE ASSERTED HERE**, because a documented deviation that nothing checks is how a
 * comment and a behaviour drift apart:
 *
 *   1. `withoutAdditionalLayout:` answers the SAME rect as the two-argument door — asserted directly.
 *   2. the container door answers the CONTAINER's range, not the line's — asserted by comparing it against the range
 *      the line door gives, which must be a SUBSET of it.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

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
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 100.0)];
		const char *text = "The quick brown fox jumps over the lazy dog, and then keeps on running for a while.";
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:
			[NSString stringWithUTF8String:text]];
		NSUInteger glyphs, length, i;
		NSRange containerRange = NSMakeRange(NSNotFound, 0);
		NSRange lineRange = NSMakeRange(NSNotFound, 0);
		NSTextContainer *found;

		[manager addTextContainer:container];
		[manager setTextStorage:store];

		glyphs = [manager numberOfGlyphs];
		length = [store length];
		check(glyphs > 0, "the manager reports glyphs after a layout is forced");
		check(length > 0, "and the store carries text");

		/* 1. isValidGlyphIndex is the guard the other doors need. */
		check([manager isValidGlyphIndex:0], "glyph 0 is valid");
		check([manager isValidGlyphIndex:glyphs - 1], "the last glyph is valid");
		check(![manager isValidGlyphIndex:glyphs], "one past the last glyph is not");

		/* 2. The unlaid pair, which for an on-demand full layout are the totals. */
		check([manager firstUnlaidCharacterIndex] == length,
		      "firstUnlaidCharacterIndex is the store's length once everything is laid out");
		check([manager firstUnlaidGlyphIndex] == glyphs,
		      "firstUnlaidGlyphIndex is the glyph count for the same reason");

		/* 3. The three-argument rect doors agree with the two-argument ones, which is the documented deviation. */
		for (i = 0; i < glyphs; i += 5) {
			NSRange plain = NSMakeRange(NSNotFound, 0);
			NSRange flagged = NSMakeRange(NSNotFound, 0);
			NSRect a = [manager lineFragmentRectForGlyphAtIndex:i effectiveRange:&plain];
			NSRect b = [manager lineFragmentRectForGlyphAtIndex:i effectiveRange:&flagged
						  withoutAdditionalLayout:YES];

			if (!NSEqualRects(a, b) || plain.location != flagged.location
			    || plain.length != flagged.length) {
				check(0, "withoutAdditionalLayout: answers the same line fragment rect and range");
				goto rects_done;
			}
		}
		check(1, "withoutAdditionalLayout: answers the same line fragment rect and range");
rects_done:
		for (i = 0; i < glyphs; i += 5) {
			NSRange plain = NSMakeRange(NSNotFound, 0);
			NSRange flagged = NSMakeRange(NSNotFound, 0);
			NSRect a = [manager lineFragmentUsedRectForGlyphAtIndex:i effectiveRange:&plain];
			NSRect b = [manager lineFragmentUsedRectForGlyphAtIndex:i effectiveRange:&flagged
						      withoutAdditionalLayout:YES];

			if (!NSEqualRects(a, b)) {
				check(0, "and the same used rect");
				goto used_done;
			}
		}
		check(1, "and the same used rect");
used_done:

		/* 4. The container door: the container, and the CONTAINER's range rather than the line's. */
		found = [manager textContainerForGlyphAtIndex:0 effectiveRange:&containerRange];
		check(found == container, "textContainerForGlyphAtIndex: finds the container that holds the glyph");
		check(containerRange.location == 0 && containerRange.length >= glyphs,
		      "and its effective range is the container's, which covers every glyph");

		[manager lineFragmentRectForGlyphAtIndex:0 effectiveRange:&lineRange];
		check(lineRange.location >= containerRange.location
		      && lineRange.location + lineRange.length <= containerRange.location + containerRange.length,
		      "the line's range is a SUBSET of the container's, which is what distinguishes the two doors");

		found = [manager textContainerForGlyphAtIndex:0 effectiveRange:NULL];
		check(found == container, "and the same door without an out-parameter");
		{
			NSRange flagged = NSMakeRange(NSNotFound, 0);

			found = [manager textContainerForGlyphAtIndex:0 effectiveRange:&flagged
					       withoutAdditionalLayout:YES];
			check(found == container && flagged.location == containerRange.location
			      && flagged.length == containerRange.length,
			      "and its withoutAdditionalLayout: form agrees");
		}

		/* 5. A glyph index that does not exist answers nil rather than a container. */
		check([manager textContainerForGlyphAtIndex:glyphs effectiveRange:NULL] == nil,
		      "a glyph index past the end answers no container");

		[manager release];
		[store release];
		[container release];

		if (failures == 0) {
			printf("text_fragment_queries: all checks passed\n");
			return 0;
		}
		printf("text_fragment_queries: FAILURES\n");
		return 1;
	}
}
