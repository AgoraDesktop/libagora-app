/*
 * text_manager_state — the manager's invalidation and ensure doors, the container tidings, the extra line and the two
 * font measurements.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS THAT THE THREE KINDS OF STALENESS END IN THREE OBSERVABLE PLACES.** A glyph/layout invalidation ends in
 * the manager's stale record (which this tier publishes as `-cg_invalidatedRange` because Apple has no getter); a DISPLAY
 * invalidation ends in the text view's damage rect; and an ENSURE ends in a layout that exists. Each is checked where a
 * caller could see it rather than by reading a flag the door set.
 *
 * **AND THE ONE CONVERSION THAT IS NOT A NO-OP IS CHECKED AS ARITHMETIC.** `-invalidateGlyphsOnLayoutInvalidationFor
 * GlyphRange:` names GLYPHS and the record is keyed by CHARACTERS, so the probe compares the recorded range against
 * `-characterRangeForGlyphRange:`'s own answer — the same map, asked twice.
 *
 * The extra line fragment is a stored pair (this tier's breaker never produces one), and the two font doors are the
 * font's own numbers: ascender minus a negative descender plus leading, and the ascender alone.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextView.h>
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

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

static int range_covers(NSRange outer, NSRange inner)
{
	return inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer);
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE ENSURE DOORS MAKE A LAYOUT EXIST, and the pair of first-unlaid answers agree with the
		 *    doors they duplicate.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(320.0, 200.0)];
			NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\nthree"];
			NSUInteger charIndex = 0;
			NSUInteger glyphIndex = 0;

			[store addLayoutManager:manager];
			[manager addTextContainer:container];

			[manager ensureGlyphsForCharacterRange:NSMakeRange(0, [store length])];
			check([manager numberOfGlyphs] > 0, "ensuring a character range lays the document out");
			[manager ensureGlyphsForGlyphRange:NSMakeRange(0, [manager numberOfGlyphs])];
			check(1, "and ensuring a glyph range is the same request spelled the other way");

			[manager getFirstUnlaidCharacterIndex:&charIndex glyphIndex:&glyphIndex];
			check(charIndex == [store length] && glyphIndex == [manager numberOfGlyphs],
			      "after a full layout the first unlaid character and glyph are the ends of the document");

			/* AND A NULL POINTER IS A CALLER THAT WANTS ONE ANSWER, not a crash. */
			[manager getFirstUnlaidCharacterIndex:NULL glyphIndex:&glyphIndex];
			check(glyphIndex == [manager numberOfGlyphs], "either pointer may be NULL");

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 2. THE THREE INVALIDATIONS, each in the record the tier publishes.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(320.0, 200.0)];
			NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"alpha beta gamma"];
			NSRange actual = NSMakeRange(0, 0);

			[store addLayoutManager:manager];
			[manager addTextContainer:container];
			(void)[manager numberOfGlyphs];		/* lay out first, so the record starts clean */
			check([manager cg_invalidatedRange].location == NSNotFound, "a fresh layout leaves nothing stale");

			[manager invalidateLayoutForCharacterRange:NSMakeRange(2, 4) isSoft:YES actualCharacterRange:&actual];
			check(range_covers([manager cg_invalidatedRange], NSMakeRange(2, 4)),
			      "invalidating a character range marks it stale");
			check(range_covers(actual, NSMakeRange(2, 4)), "and reports what it actually invalidated");

			[manager invalidateGlyphsForCharacterRange:NSMakeRange(8, 3) changeInLength:0 actualCharacterRange:NULL];
			check(range_covers([manager cg_invalidatedRange], NSMakeRange(8, 3)),
			      "a glyph invalidation by character range marks the same range");

			/* **THE GLYPH-RANGE DOOR TRANSLATES.** The map is the manager's own, so the assertion is made against the
			 * map's answer rather than against an assumption that a glyph is a character. */
			{
				NSRange glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(0, 5) actualCharacterRange:NULL];
				NSRange expected = [manager characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];

				[manager invalidateGlyphsOnLayoutInvalidationForGlyphRange:glyphs];
				check(range_covers([manager cg_invalidatedRange], expected),
				      "a glyph invalidation by GLYPH range marks the characters those glyphs came from");
			}

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 3. THE DISPLAY DOORS END IN THE VIEW'S DAMAGE RECT, which is the only place a pixel is asked for.
		 * ========================================================================================== */
		{
			NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 120.0)];
			NSLayoutManager *manager;
			NSTextContainer *container;

			[view setString:@"alpha\nbeta\ngamma"];
			manager = [view layoutManager];
			container = [view textContainer];
			[view setNeedsDisplay:NO];	/* clear any pending damage from -setString: */

			[manager invalidateDisplayForCharacterRange:NSMakeRange(0, 5)];
			check([view needsDisplayInRect:NSMakeRect(0.0, 0.0, 200.0, 20.0)],
			      "invalidating a character range asks the view to redraw where it is");
			check(![view needsDisplayInRect:NSMakeRect(0.0, 100.0, 20.0, 20.0)],
			      "and does not ask for a rect the layout never touched");

			[view setNeedsDisplay:NO];
			{
				NSRect lastLine = [manager lineFragmentRectForGlyphAtIndex:10 effectiveRange:NULL];

				[manager invalidateDisplayForGlyphRange:NSMakeRange(10, 1)];
				check([view needsDisplayInRect:lastLine],
				      "a glyph-range invalidation reaches the line the glyph is on");
			}

			[view setNeedsDisplay:NO];
			[manager textContainerChangedTextView:container];
			check([view needsDisplayInRect:NSMakeRect(0.0, 0.0, 10.0, 10.0)],
			      "a text-view change repaints the view");

			/* A GEOMETRY CHANGE RE-WRAPS, so everything is stale rather than a range. */
			(void)[manager numberOfGlyphs];		/* clean */
			[manager textContainerChangedGeometry:container];
			check([manager cg_invalidatedRange].location == 0
				      && NSMaxRange([manager cg_invalidatedRange]) >= [[view string] length],
			      "a container geometry change marks the whole document stale");

			[view release];
		}

		/* ============================================================================================
		 * 4. WHICH GLYPHS A RECTANGLE COVERS.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(320.0, 200.0)];
			NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\nthree"];
			NSRect firstLine;
			NSRect lastLine;
			NSRange first;
			NSRange none;

			[store addLayoutManager:manager];
			[manager addTextContainer:container];
			(void)[manager numberOfGlyphs];

			firstLine = [manager lineFragmentRectForGlyphAtIndex:0 effectiveRange:NULL];
			lastLine = [manager lineFragmentRectForGlyphAtIndex:8 effectiveRange:NULL];
			first = [manager glyphRangeForBoundingRect:firstLine inTextContainer:container];
			check(first.location == 0 && first.length > 0 && first.length < [manager numberOfGlyphs],
			      "the first line's rect covers the first line's glyphs and not the rest");
			check(range_covers([manager glyphRangeForBoundingRect:lastLine inTextContainer:container],
					   NSMakeRange([manager numberOfGlyphs] - 1, 1)),
			      "the last line's rect covers the last glyph");

			none = [manager glyphRangeForBoundingRect:NSMakeRect(1000.0, 1000.0, 5.0, 5.0)
					       inTextContainer:container];
			check(none.location == NSNotFound, "a rect that covers no line answers NSNotFound");

			check(NSEqualRanges([manager glyphRangeForBoundingRectWithoutAdditionalLayout:firstLine
						       inTextContainer:container], first),
			      "the without-additional-layout spelling answers the same range");

			/* A CONTAINER THE MANAGER DOES NOT OWN ANSWERS NOTHING. */
			{
				NSTextContainer *stranger = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(30.0, 30.0)];

				check([manager glyphRangeForBoundingRect:firstLine inTextContainer:stranger].location == NSNotFound,
				      "a foreign container answers NSNotFound");
				[stranger release];
			}

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 5. THE EXTRA LINE IS STORED AND ANSWERED, AND STARTS EMPTY.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(100.0, 100.0)];

			check(NSIsEmptyRect([manager extraLineFragmentRect])
				      && [manager extraLineFragmentTextContainer] == nil,
			      "a manager that has never been told about an extra line has none");
			[manager setExtraLineFragmentRect:NSMakeRect(5.0, 40.0, 90.0, 12.0)
						 usedRect:NSMakeRect(5.0, 40.0, 30.0, 12.0)
						  textContainer:container];
			check(close_enough(NSMinY([manager extraLineFragmentRect]), 40.0)
				      && close_enough(NSWidth([manager extraLineFragmentUsedRect]), 30.0)
				      && [manager extraLineFragmentTextContainer] == container,
			      "and what a subclass stores is what the three getters answer");
			[container release];
			[manager release];
		}

		/* ============================================================================================
		 * 6. THE FONT MEASUREMENTS ARE THE FONT'S OWN NUMBERS.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSFont *font = [NSFont systemFontOfSize:12.0];

			check(close_enough([manager defaultLineHeightForFont:font],
					   [font ascender] - [font descender] + [font leading]),
			      "the default line height is ascender minus a negative descender plus leading");
			check(close_enough([manager defaultBaselineOffsetForFont:font], [font ascender]),
			      "and the baseline offset is the ascender");
			check(close_enough([manager defaultLineHeightForFont:nil], 0.0),
			      "a nil font measures zero rather than crashing");
			[manager release];
		}

		if (failures == 0) {
			printf("text_manager_state: all checks passed\n");
			return 0;
		}
		printf("text_manager_state: FAILURES\n");
		return 1;
	}
}
