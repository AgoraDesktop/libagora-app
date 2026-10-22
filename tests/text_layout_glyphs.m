/*
 * text_layout_glyphs.m — THE GLYPH STORE: THE GENERATED LINES, AND THE DOORS THAT WALK THEM.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE MANAGER NOW KEEPS THE GLYPHS IT GENERATED, AND THE MAP IS COMPUTED FROM THEM.** Before this slice `CTLine`
 * was rebuilt at every draw and `-numberOfGlyphs` answered the store's character count by FIAT; now the layout keeps
 * the line it made for each fragment, `-numberOfGlyphs` is the last stored glyph's end, and the two conversion doors
 * find a character's fragment and count the glyphs before it. The arithmetic HAPPENS to come out one to one —
 * `CTLine` maps every character, notdef included — which is the honest answer ARRIVED AT rather than assumed.
 *
 * **AND THE REVERSE LOOKUPS ARE THE STORE SEEN FROM THE OTHER SIDE.** A glyph's x is its fragment's padding plus Core
 * Text's own offset, and the point-to-glyph door is that inverse; the ORDINAL FRAGMENT doors are what let the text
 * view answer "which visual line" without a layout of its own. THE BOUNDARY IS CHECKED ON PURPOSE: a glyph index at the
 * end of one fragment is the START of the next, so index 4 in `one\ntwo` belongs to `two`.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
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

static int range_is(NSRange r, NSUInteger where, NSUInteger length)
{
	return r.location == where && r.length == length;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 400.0)];
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	CGFloat lineHeight = [font ascender] - [font descender];

	setvbuf(stdout, NULL, _IONBF, 0);
	[store addLayoutManager:manager];
	[manager addTextContainer:container];

	/* 1. **THE GLYPH COUNT IS THE STORE'S, COUNTED FROM WHAT WAS GENERATED.** */
	{
		NSUInteger glyphs = [manager numberOfGlyphs];

		printf("  (note: `-numberOfGlyphs` answers %lu for a %lu-character store)\n",
		       (unsigned long)glyphs, (unsigned long)[[store string] length]);
		check(glyphs == [[store string] length], "the glyph count is the character count, one glyph per character");
	}

	/* 2. **AND THE MAP WALKS THE FRAGMENTS RATHER THAN DECLARING THE IDENTITY.** A range inside one line and a range
	 * that SPANS the break both come back with their own length, which is what a one-to-one store means. */
	{
		NSRange actual = NSMakeRange(99, 99);
		NSRange glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(4, 3) actualCharacterRange:&actual];

		check(range_is(glyphs, 4, 3) && range_is(actual, 4, 3),
		      "a range in the SECOND line maps to itself");
		glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(0, 7) actualCharacterRange:NULL];
		check(range_is(glyphs, 0, 7), "and a range spanning the break keeps its length");
		check(range_is([manager characterRangeForGlyphRange:NSMakeRange(4, 3) actualGlyphRange:NULL], 4, 3),
		      "the inverse door walks the same store");
	}

	/* 3. **AND A GLYPH'S x IS ITS FRAGMENT'S PADDING PLUS CORE TEXT'S OFFSET.** The first glyph is at the padding; the
	 * last of `one` is further right; and the first of `two` is back at the padding because it is a NEW LINE. That
	 * last drop is the whole point of the door being per-fragment rather than per-store. */
	{
		CGFloat first = [manager cg_offsetForGlyphAtIndex:0];
		CGFloat endOfOne = [manager cg_offsetForGlyphAtIndex:3];
		CGFloat startOfTwo = [manager cg_offsetForGlyphAtIndex:4];

		printf("  (note: x — glyph 0 %g, glyph 3 %g, glyph 4 %g)\n",
		       (double)first, (double)endOfOne, (double)startOfTwo);
		check(first == 10.0, "the first glyph sits at the container's fragment padding");
		check(endOfOne > first, "an offset grows along a line");
		check(startOfTwo == 10.0 && startOfTwo < endOfOne,
		      "and drops back to the padding at the START of the next fragment");
	}

	/* 4. **AND THE POINT DOOR IS THAT INVERSE.** A point on the second line at the padding is glyph 4; one in the
	 * middle of the first line is past its first character. */
	{
		NSUInteger byPoint = [manager cg_glyphIndexForPoint:NSMakePoint(10.0, lineHeight + lineHeight / 2.0)
							    inTextContainer:container];
		NSUInteger intoOne = [manager cg_glyphIndexForPoint:NSMakePoint(20.0, lineHeight / 2.0)
							    inTextContainer:container];

		printf("  (note: a point at the second line's left edge is glyph %lu; into `one` it is %lu)\n",
		       (unsigned long)byPoint, (unsigned long)intoOne);
		check(byPoint == 4, "the point at the second line's start is ITS first glyph");
		check(intoOne > 0 && intoOne <= 3, "and a point into `one` is one of ITS glyphs");
	}

	/* 5. **AND THE ORDINAL FRAGMENT DOORS NAME THE LINE A GLYPH IS ON.** The boundary index belongs to the line that
	 * STARTS there, which is what makes a caret at the break sit at the top of the next line. */
	{
		NSUInteger firstLine = [manager cg_lineFragmentIndexForGlyphAtIndex:0 inTextContainer:container];
		NSUInteger boundary = [manager cg_lineFragmentIndexForGlyphAtIndex:4 inTextContainer:container];
		NSRange range = [manager cg_lineFragmentRangeAtIndex:1 inTextContainer:container];

		printf("  (note: glyph 0 is fragment %lu, glyph 4 is fragment %lu, fragment 1 is (%lu,%lu))\n",
		       (unsigned long)firstLine, (unsigned long)boundary,
		       (unsigned long)range.location, (unsigned long)range.length);
		check(firstLine == 0, "the first glyph is in the first fragment");
		check(boundary == 1, "and the index at a fragment's END belongs to the fragment that STARTS there");
		check(range_is(range, 4, 3), "the ordinal fragment door answers `two` for line 1");
	}

	[container release];
	[manager release];
	[store release];
	[pool release];
	printf("text_layout_glyphs: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
