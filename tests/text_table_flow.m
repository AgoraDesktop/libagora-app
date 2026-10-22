/*
 * text_table_flow.m — A TABLE THAT DOES NOT FIT ONE CONTAINER GOES ON IN THE NEXT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A TABLE FLOWS AT A ROW BOUNDARY, AND ITS COLUMNS DO NOT MOVE.** A row that does not fit the container it is being
 * laid into begins the next container, so a tall table is not clipped whole and a short one is not moved. The probe
 * reads the fragments each container took, the glyph range that landed in each, and the y of the row that resumed —
 * which must be the NEW container's top. It also reads the COLUMN geometry across the break: because the resumed call
 * measures its columns from EVERY cell of the table (not only the cells still to place), a cell in column two sits at
 * the same x before and after the container break — which it would not if the widest cell lived in the dropped row.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextBlock.h>
#import <AppKit/NSTextTable.h>
#import <AppKit/NSParagraphStyle.h>
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

/* A STORE OF ONE-CHARACTER-AN-A-PARAGRAPH CELLS, each paragraph's style carrying the cell the caller names. */
static NSTextStorage *new_table_store(NSArray *paragraphs, NSArray *cells)
{
	NSMutableString *joined = [NSMutableString string];
	NSMutableArray *starts = [NSMutableArray array];
	NSMutableArray *styles = [NSMutableArray array];
	NSTextStorage *store;
	NSUInteger i;

	for (i = 0; i < [paragraphs count]; i++) {
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];

		[starts addObject:[NSNumber numberWithUnsignedInteger:[joined length]]];
		[style addTextBlock:[cells objectAtIndex:i]];
		[styles addObject:style];
		[style release];
		[joined appendString:[paragraphs objectAtIndex:i]];
		if (i + 1 < [paragraphs count]) {
			[joined appendString:@"\n"];
		}
	}
	store = [[NSTextStorage alloc] initWithString:joined];
	for (i = 0; i < [paragraphs count]; i++) {
		NSUInteger start = [[starts objectAtIndex:i] unsignedIntegerValue];
		NSUInteger length = [[paragraphs objectAtIndex:i] length];

		[store addAttribute:NSParagraphStyleAttributeName value:[styles objectAtIndex:i]
			      range:NSMakeRange(start, length)];
	}
	return store;
}

static NSTextTableBlock *cell(NSTextTable *table, NSInteger row, NSInteger column)
{
	return [[[NSTextTableBlock alloc] initWithTable:table startingRow:row rowSpan:1
				     startingColumn:column columnSpan:1] autorelease];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **A THREE-ROW TABLE OVER A SHORT CONTAINER AND A TALL ONE.** The first holds two rows, so the third begins
	 * the SECOND container, at ITS top. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSMutableArray *cells = [NSMutableArray array];
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *first = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 45.0)];
		NSTextContainer *second = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSUInteger countFirst, countSecond;
		NSRange rangeFirst, rangeSecond;
		NSRect thirdRow;

		[table setNumberOfColumns:1];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		[cells addObject:cell(table, 0, 0)];
		[cells addObject:cell(table, 1, 0)];
		[cells addObject:cell(table, 2, 0)];
		store = new_table_store([NSArray arrayWithObjects:@"aa", @"bb", @"cc", nil], cells);
		[store addLayoutManager:manager];
		[manager addTextContainer:first];
		[manager addTextContainer:second];
		countFirst = [manager cg_lineFragmentCountForTextContainer:first];
		countSecond = [manager cg_lineFragmentCountForTextContainer:second];
		rangeFirst = [manager glyphRangeForTextContainer:first];
		rangeSecond = [manager glyphRangeForTextContainer:second];
		thirdRow = [manager lineFragmentUsedRectForGlyphAtIndex:6 effectiveRange:NULL];
		printf("  (note: 3 rows over two containers gave %lu + %lu fragment(s); the third row is at y=%g)\n",
		       (unsigned long)countFirst, (unsigned long)countSecond, (double)thirdRow.origin.y);
		check(countFirst == 2, "a table taller than its container breaks at a ROW boundary — two rows fit");
		check(countSecond == 1, "and the third row is laid into the NEXT container");
		/* **THE NUMBERS ARE THE LINES' GLYPH COUNTS NOW, AND THEY ARE CONTIGUOUS.** They used to be string
		 * LOCATIONS — 0 and 5, then 6 — because the table path wrote a paragraph's character index into a glyph
		 * base, which was never this class's glyph space. A cell's line is its paragraph WITHOUT the separator, so
		 * three rows of `aa`, `bb`, `cc` are 2 + 2 + 2 glyphs: the first container holds the first two (0,4) and the
		 * next holds the third (4,2). */
		printf("  (note: the containers' glyphs are (%lu,%lu) and (%lu,%lu); %lu in all)\n",
		       (unsigned long)rangeFirst.location, (unsigned long)rangeFirst.length,
		       (unsigned long)rangeSecond.location, (unsigned long)rangeSecond.length,
		       (unsigned long)[manager numberOfGlyphs]);
		check(rangeFirst.location == 0 && rangeFirst.length == 4,
		      "the first container's glyphs are the first two rows");
		check(rangeSecond.location == 4 && rangeSecond.length == 2,
		      "and the next container's are the third row alone");
		check([manager numberOfGlyphs] == 6, "six glyphs for the three rows, which is the lines' own count");
		check(fabs(thirdRow.origin.y) < 0.01, "which starts at the TOP of the new container, not below the old one");
		[first release];
		[second release];
		[manager release];
		[store release];
		[table release];
	}

	/* 2. **AND THE COLUMNS DO NOT MOVE ACROSS THE BREAK.** Column two's x is the same in the first container's row
	 * and in the row that resumed, because the resumed call measures the columns from EVERY cell — the dropped row's
	 * cell is the widest, so measuring only the remaining cells would narrow column one and pull column two left. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSMutableArray *cells = [NSMutableArray array];
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *first = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 30.0)];
		NSTextContainer *second = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSRect row0col1, row1col1;

		[table setNumberOfColumns:2];
		[cells addObject:cell(table, 0, 0)];
		[cells addObject:cell(table, 0, 1)];
		[cells addObject:cell(table, 1, 0)];
		[cells addObject:cell(table, 1, 1)];
		[cells addObject:cell(table, 2, 0)];
		[cells addObject:cell(table, 2, 1)];
		store = new_table_store([NSArray arrayWithObjects:@"wwwwww", @"x", @"a", @"b", @"c", @"d", nil], cells);
		[store addLayoutManager:manager];
		[manager addTextContainer:first];
		[manager addTextContainer:second];
		/* **AND THE GLYPH INDICES ARE THE LINES' OWN NOW, NOT THE PARAGRAPHS' STRING LOCATIONS.** The cells of the
		 * first row are `wwwwww` and `x`, so column two's fragment begins at glyph SIX; the dropped row's cells are
		 * `a` and `b`, so that column's fragment begins at glyph EIGHT. The old 7 and 11 were the paragraph starts in
		 * the STRING, which is a different index space and was only the same while a glyph was a character. */
		row0col1 = [manager lineFragmentUsedRectForGlyphAtIndex:6 effectiveRange:NULL];
		row1col1 = [manager lineFragmentUsedRectForGlyphAtIndex:8 effectiveRange:NULL];
		printf("  (note: column two starts at x=%g in container one and x=%g after the resume)\n",
		       (double)row0col1.origin.x, (double)row1col1.origin.x);
		check(fabs(row0col1.origin.x - row1col1.origin.x) < 0.01,
		      "a resumed table keeps the SAME column widths — the columns are measured from every cell");
		[first release];
		[second release];
		[manager release];
		[store release];
		[table release];
	}

	/* 3. **AND A TABLE TALLER THAN EVERY CONTAINER IS CLIPPED AT THE LAST ONE.** Two rows fit (one each); the third
	 * has nowhere to go and is dropped, which is the same rule text past the last container follows. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSMutableArray *cells = [NSMutableArray array];
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *first = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 20.0)];
		NSTextContainer *second = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 20.0)];
		NSUInteger countFirst, countSecond;
		NSRange rangeSecond;

		[table setNumberOfColumns:1];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		[cells addObject:cell(table, 0, 0)];
		[cells addObject:cell(table, 1, 0)];
		[cells addObject:cell(table, 2, 0)];
		store = new_table_store([NSArray arrayWithObjects:@"aa", @"bb", @"cc", nil], cells);
		[store addLayoutManager:manager];
		[manager addTextContainer:first];
		[manager addTextContainer:second];
		countFirst = [manager cg_lineFragmentCountForTextContainer:first];
		countSecond = [manager cg_lineFragmentCountForTextContainer:second];
		rangeSecond = [manager glyphRangeForTextContainer:second];
		printf("  (note: 3 rows over two 20-point containers gave %lu + %lu fragment(s))\n",
		       (unsigned long)countFirst, (unsigned long)countSecond);
		check(countFirst == 1 && countSecond == 1, "a table taller than both containers gives each one row");
		check(rangeSecond.location == 2 && rangeSecond.length == 2,
		      "the last container holds the SECOND row, and the third is dropped");
		[first release];
		[second release];
		[manager release];
		[store release];
		[table release];
	}

	[pool release];
	printf("text_table_flow: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
