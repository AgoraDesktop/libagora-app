/*
 * text_layout_overflow.m — THE SECOND CONTAINER: TEXT THAT DOES NOT FIT THE FIRST IS CARRIED TO THE NEXT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A CONTAINER'S OWN HEIGHT IS THE OVERFLOW EDGE, AND THIS PROBE PUTS IT THERE ON PURPOSE.** `NSTextContainer` is a
 * region with a size, and until now every probe gave it a height taller than the text so the height never mattered —
 * one container took everything because nothing ever did not fit. Here the FIRST container is exactly TWO lines tall,
 * so the third line has nowhere to go but the SECOND container; the claim is that it goes there, that each container
 * answers the glyphs that landed in IT, and that the flow order is the list order.
 *
 * **AND A SINGLE CONTAINER STILL TAKES EVERYTHING**, because a scrolling text view is the common case and its
 * container is unbounded or taller than its text; a document with no second container and text that overruns the first
 * is CLIPPED at the last line that fit, which is stated rather than half-done.
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
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	CGFloat lineHeight = [font ascender] - [font descender];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **TWO CONTAINERS, THE FIRST TWO LINES TALL.** "one\ntwo\nthree\nfour" is four fragments; the first container
	 * takes the first two and the second takes the last two. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\nthree\nfour"];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *first = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 2.0 * lineHeight)];
		NSTextContainer *second = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 400.0)];
		NSRange firstGlyphs, secondGlyphs;
		NSUInteger firstCount, secondCount;

		[store addLayoutManager:manager];
		[manager addTextContainer:first];
		[manager addTextContainer:second];
		firstCount = [manager cg_lineFragmentCountForTextContainer:first];
		secondCount = [manager cg_lineFragmentCountForTextContainer:second];
		firstGlyphs = [manager glyphRangeForTextContainer:first];
		secondGlyphs = [manager glyphRangeForTextContainer:second];
		printf("  (note: container 0 has %lu fragment(s) over glyphs (%lu,%lu); container 1 has %lu over (%lu,%lu))\n",
		       (unsigned long)firstCount, (unsigned long)firstGlyphs.location, (unsigned long)firstGlyphs.length,
		       (unsigned long)secondCount, (unsigned long)secondGlyphs.location, (unsigned long)secondGlyphs.length);
		check(firstCount == 2 && secondCount == 2,
		      "a store of FOUR lines in a first container TWO lines tall fills 2 fragments and overflows 2");
		check(range_is(firstGlyphs, 0, 8), "the first container's glyphs are `one\\ntwo\\n` — (0,8)");
		check(range_is(secondGlyphs, 8, 10), "and the second's are the REST, `three\\nfour` — (8,10)");

		/* **AND THE OVERFLOW LINE IS IN THE SECOND CONTAINER'S OWN COORDINATES.** Glyph 10 is the `t` of `three`, which
		 * is the second container's FIRST line, so its fragment is at y=0 in THAT container — not a line down. */
		{
			NSRange effective = NSMakeRange(99, 99);
			NSRect rect = [manager lineFragmentRectForGlyphAtIndex:10 effectiveRange:&effective];

			printf("  (note: glyph 10's fragment is at y=%g, range (%lu,%lu))\n", (double)rect.origin.y,
			       (unsigned long)effective.location, (unsigned long)effective.length);
			check(rect.origin.y == 0.0, "a glyph carried to the second container sits at ITS top, y=0");
			check(range_is(effective, 8, 6), "and its fragment is `three\\n`");
		}

		/* **AND EACH CONTAINER'S USED RECT IS ITS OWN TWO LINES.** */
		{
			NSRect usedFirst = [manager usedRectForTextContainer:first];
			NSRect usedSecond = [manager usedRectForTextContainer:second];

			printf("  (note: used rects — first %g tall, second %g tall, against a line height of %g)\n",
			       (double)usedFirst.size.height, (double)usedSecond.size.height, (double)lineHeight);
			check(fabs(usedFirst.size.height - 2.0 * lineHeight) < 0.01
			      && fabs(usedSecond.size.height - 2.0 * lineHeight) < 0.01,
			      "each container's used rect is the TWO lines it took, not the whole store");
		}

		[second release];
		[first release];
		[manager release];
		[store release];
	}

	/* 2. **AND A SINGLE CONTAINER TALLER THAN THE TEXT STILL TAKES ALL OF IT**, which is the property every earlier
	 * slice relied on and which the flow must not have broken. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\nthree"];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 400.0)];

		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		check([manager cg_lineFragmentCountForTextContainer:container] == 3,
		      "one tall container takes all THREE lines");
		check(range_is([manager glyphRangeForTextContainer:container], 0, [[store string] length]),
		      "and answers the whole store's glyphs");
		[container release];
		[manager release];
		[store release];
	}

	/* 3. **AND TEXT BEYOND THE LAST CONTAINER IS CLIPPED AT THE LAST LINE THAT FIT.** One container two lines tall and
	 * three lines of text: the third line has no container to go to, so it is not laid — which is what a document with
	 * no more room means, and is named rather than silently wrong. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\nthree"];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 2.0 * lineHeight)];

		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		printf("  (note: one two-line container and a three-line store gave %lu fragment(s))\n",
		       (unsigned long)[manager cg_lineFragmentCountForTextContainer:container]);
		check([manager cg_lineFragmentCountForTextContainer:container] == 2,
		      "the line that did not fit is CLIPPED — there is no next container to carry it to");
		[container release];
		[manager release];
		[store release];
	}

	[pool release];
	printf("text_layout_overflow: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
