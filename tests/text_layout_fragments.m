/*
 * text_layout_fragments.m — THE FRAGMENTS: A STORE LAID INTO A CONTAINER'S LINES.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS GEOMETRY, SO THE PROBE READS POINTS.** A store with three newlines in a wide container is three
 * line fragments; the same paragraph in a narrow one is more, because the width is the container's; `-usedRectFor...`
 * is the union of what those fragments fill and is the size a view would need; and a glyph's fragment is the line it is
 * on. THE CHARACTER-TO-GLYPH MAP is checked as the identity it is, including the CLAMPING Apple's contract needs.
 *
 * **AND THE STALE RECORD IS WHAT DRIVES IT.** A layout asked for when nothing is stale is not rebuilt — Apple says
 * `-usedRectForTextContainer:` causes neither glyph generation nor layout — and a layout asked for after an edit IS, so
 * the count grows by exactly the line the edit added.
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
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\nthree"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *wide = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 400.0)];
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	CGFloat lineHeight = [font ascender] - [font descender];

	setvbuf(stdout, NULL, _IONBF, 0);
	[store addLayoutManager:manager];
	[manager addTextContainer:wide];

	/* 1. **THE CHARACTER-TO-GLYPH MAP IS THE IDENTITY, WITH THE CLAMP APPLE'S CONTRACT NEEDS.** There is no glyph
	 * store here — Core Text does that mapping inside `CTLine` — so both doors answer what they were given, and the
	 * "actual" range is the same range. */
	check([manager numberOfGlyphs] == [[store string] length],
	      "the glyph count IS the character count, which is what a one-to-one map means");
	{
		NSRange actual = NSMakeRange(99, 99);
		NSRange glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(2, 3) actualCharacterRange:&actual];

		check(range_is(glyphs, 2, 3) && range_is(actual, 2, 3),
		      "a character range converts to itself, and reports itself as the actual range");
		glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(11, 500) actualCharacterRange:&actual];
		printf("  (note: a range running past the store came back (%lu,%lu))\n",
		       (unsigned long)glyphs.location, (unsigned long)glyphs.length);
		check(range_is(glyphs, 11, 2), "a range past the store is CLAMPED to it rather than answered as asked");
		check(range_is([manager characterRangeForGlyphRange:NSMakeRange(4, 3) actualGlyphRange:NULL], 4, 3),
		      "and the inverse door is the same identity");
	}

	/* 2. **AND THE LAYOUT IS ONE FRAGMENT PER LINE THE CONTAINER GIVES.** A 300-point container and a store with two
	 * newlines: three fragments, each the container's whole width and one line high. */
	{
		NSUInteger count = [manager cg_lineFragmentCountForTextContainer:wide];
		NSRange effective = NSMakeRange(99, 99);
		NSRect first = [manager lineFragmentRectForGlyphAtIndex:0 effectiveRange:&effective];

		printf("  (note: three newline-separated lines in a 300-point container gave %lu fragment(s); the first is "
		       "%gx%g at (%g,%g), range (%lu,%lu))\n", (unsigned long)count, (double)first.size.width,
		       (double)first.size.height, (double)first.origin.x, (double)first.origin.y,
		       (unsigned long)effective.location, (unsigned long)effective.length);
		check(count == 3, "a store with two newlines lays into THREE fragments");
		check(first.size.width == 300.0 && fabs(first.size.height - lineHeight) < 0.01,
		      "a fragment is the CONTAINER's whole width and one line high");
		/* **AND THE RANGE INCLUDES THE NEWLINE, WHICH IS THE TYPESETTER'S OWN CONVENTION.** The breaker keeps the
		 * hard break IN the line it ends — `NSTextView` takes it back off only where a GLYPH would be set — so a
		 * fragment's glyph range ends at the separator rather than before it. */
		check(range_is(effective, 0, 4), "and the first fragment's range is the first line AND its newline");
	}

	/* 3. **AND A GLYPH'S FRAGMENT IS THE LINE IT IS ON.** The glyph in the middle of "two" is in the SECOND fragment;
	 * the fragment rect's y is where that line sits, which is a line-height down from the first. */
	{
		NSRange effective = NSMakeRange(99, 99);
		NSRect second = [manager lineFragmentRectForGlyphAtIndex:5 effectiveRange:&effective];

		printf("  (note: glyph 5 is in the fragment at y=%g, range (%lu,%lu))\n", (double)second.origin.y,
		       (unsigned long)effective.location, (unsigned long)effective.length);
		check(range_is(effective, 4, 4), "a glyph in `two` is in the fragment for `two` and its newline");
		check(fabs(second.origin.y - lineHeight) < 0.01,
		      "and that fragment sits one line-height down, in CONTAINER coordinates");
	}

	/* 4. **AND THE USED RECT IS THE UNION — THE SIZE A VIEW WOULD NEED.** The container is 300 wide and the fragment
	 * is 300 wide, but what is USED is the text, so the union's x is the fragment padding and its height is three
	 * lines. */
	{
		NSRect used = [manager usedRectForTextContainer:wide];

		printf("  (note: `-usedRectForTextContainer:` for three lines is (%g,%g) %gx%g, against a line height of %g)\n",
		       (double)used.origin.x, (double)used.origin.y, (double)used.size.width, (double)used.size.height,
		       (double)lineHeight);
		check(used.origin.x == 10.0, "the used rect begins at the container's fragment padding");
		check(fabs(used.size.height - 3.0 * lineHeight) < 0.01, "and is three lines tall");
		check(used.size.width > 0.0 && used.size.width < 300.0,
		      "and as wide as the text rather than as wide as the container");
		check(NSIsEmptyRect([manager usedRectForTextContainer:
			[[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(90.0, 400.0)] autorelease]]),
		      "a container that is not this manager's has nothing used in it");
	}

	/* 5. **AND THE WIDTH IS THE CONTAINER'S, WHICH IS WHAT MAKES A PARAGRAPH WRAP.** The same text in a 90-point
	 * container is more fragments than in a 300-point one — the breaking is `CTTypesetterSuggestLineBreak`'s, asked with
	 * the container's own width. TWO MANAGERS, because a container is laid out in one place (see the web slice) and
	 * because this slice fills the FIRST container only. */
	{
		NSTextStorage *paragraph = [[NSTextStorage alloc] initWithString:@"aaaa bbbb cccc dddd eeee ffff"];
		NSLayoutManager *mw = [[NSLayoutManager alloc] init];
		NSLayoutManager *mn = [[NSLayoutManager alloc] init];
		NSTextContainer *wide2 = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 400.0)];
		NSTextContainer *narrow2 = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(90.0, 400.0)];
		NSUInteger wideCount;
		NSUInteger narrowCount;

		[paragraph addLayoutManager:mw];
		[mw addTextContainer:wide2];
		[paragraph addLayoutManager:mn];
		[mn addTextContainer:narrow2];
		wideCount = [mw cg_lineFragmentCountForTextContainer:wide2];
		narrowCount = [mn cg_lineFragmentCountForTextContainer:narrow2];
		printf("  (note: the same paragraph gave %lu fragment(s) in 300 points and %lu in 90)\n",
		       (unsigned long)wideCount, (unsigned long)narrowCount);
		check(wideCount == 1, "a paragraph that fits is ONE fragment");
		check(narrowCount > wideCount, "and the same paragraph WRAPS when the container is narrower");
		[narrow2 release];
		[wide2 release];
		[mn release];
		[mw release];
		[paragraph release];
	}

	/* 6. **AND THE STALE RECORD IS WHAT DRIVES A REBUILD.** An edit makes the layout stale; asking for the geometry
	 * then rebuilds it, so the count grows by exactly the line the edit added. */
	{
		NSUInteger before = [manager cg_lineFragmentCountForTextContainer:wide];

		[store replaceCharactersInRange:NSMakeRange([[store string] length], 0) withString:@"\nfour"];
		check([manager cg_invalidatedRange].location != NSNotFound, "an edit leaves the layout STALE");
		check([manager cg_lineFragmentCountForTextContainer:wide] == before + 1,
		      "and asking for the geometry rebuilds it, one line taller");
		check([manager cg_invalidatedRange].location == NSNotFound, "with the stale record cleared by the rebuild");
	}

	/* 7. **AND ASKING AGAIN CHANGES NOTHING.** A clean record means the fragments are read rather than remade, which
	 * is what Apple promises `-usedRectForTextContainer:` costs. */
	{
		NSUInteger once = [manager cg_lineFragmentCountForTextContainer:wide];
		NSRect a = [manager usedRectForTextContainer:wide];
		NSRect b;

		[manager ensureLayoutForTextContainer:wide];
		b = [manager usedRectForTextContainer:wide];
		check([manager cg_lineFragmentCountForTextContainer:wide] == once && NSEqualRects(a, b),
		      "a layout asked for twice is the same layout — nothing stale, nothing rebuilt");
	}

	[wide release];
	[manager release];
	[store release];
	[pool release];
	printf("text_layout_fragments: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
