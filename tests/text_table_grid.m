/*
 * text_table_grid.m — THE GRID: CELLS SIDE BY SIDE, COLUMNS MEASURED, ROWS AS TALL AS THEIR TALLEST CELL.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS WHERE THE CELLS LAND, SO THE PROBE READS THE MANAGER'S OWN GEOMETRY.** A table's cells are paragraphs
 * whose style carries a `NSTextTableBlock`; the layout manager lays them out as a grid — each cell inside its own
 * columns' width, placed at its column's x — so the probe asks a glyph in each cell where its line fragment is. TWO
 * CELLS IN ONE ROW share a y and differ in x; two cells in one COLUMN share an x and differ in y; a row of long cells
 * that overflows the container is SCALED and each cell wraps; and a cell whose text is wider than the column the table
 * measured is not narrower than its own columns.
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
static NSTextStorage *new_table_store(NSArray *paragraphs, NSArray *cells, NSTextTable *table)
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
	(void)table;
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

	/* 1. **TWO CELLS IN ONE ROW ARE SIDE BY SIDE AT THE SAME y.** */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSRect zero, one;

		[table setNumberOfColumns:2];
		store = new_table_store([NSArray arrayWithObjects:@"aa", @"bb", nil],
					[NSArray arrayWithObjects:cell(table, 0, 0), cell(table, 0, 1), nil], table);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		zero = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
		one = [manager lineFragmentUsedRectForGlyphAtIndex:3 effectiveRange:NULL];
		printf("  (note: row 0 — cell 0 at x=%g y=%g, cell 1 at x=%g y=%g)\n",
		       (double)zero.origin.x, (double)zero.origin.y, (double)one.origin.x, (double)one.origin.y);
		check([manager cg_lineFragmentCountForTextContainer:container] == 2,
		      "two one-line cells are two fragments");
		check(fabs(zero.origin.y - one.origin.y) < 0.01, "two cells in one ROW share a y");
		check(one.origin.x > zero.origin.x, "and the second is further right — the columns are side by side");
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 2. **AND TWO CELLS IN ONE COLUMN SHARE AN x AND STACK IN y.** */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSRect zero, one;

		[table setNumberOfColumns:1];
		store = new_table_store([NSArray arrayWithObjects:@"aa", @"bb", nil],
					[NSArray arrayWithObjects:cell(table, 0, 0), cell(table, 1, 0), nil], table);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		zero = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
		one = [manager lineFragmentUsedRectForGlyphAtIndex:3 effectiveRange:NULL];
		printf("  (note: column 0 — row 0 at x=%g y=%g, row 1 at x=%g y=%g)\n",
		       (double)zero.origin.x, (double)zero.origin.y, (double)one.origin.x, (double)one.origin.y);
		check(fabs(zero.origin.x - one.origin.x) < 0.01, "two cells in one COLUMN share an x");
		check(one.origin.y > zero.origin.y, "and the second is BELOW the first — the rows stack");
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 3. **AND A ROW WIDER THAN THE CONTAINER IS SCALED, SO EACH CELL WRAPS.** Two long cells in a 200-point
	 * container: their natural widths together exceed it, so the columns are scaled down and each cell's text takes
	 * more than one line. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSUInteger count;
		NSRect zero;
		NSRange secondLine;

		[table setNumberOfColumns:2];
		store = new_table_store([NSArray arrayWithObjects:@"aaaa bbbb cccc dddd", @"eeee ffff gggg hhhh", nil],
					[NSArray arrayWithObjects:cell(table, 0, 0), cell(table, 0, 1), nil], table);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		count = [manager cg_lineFragmentCountForTextContainer:container];
		zero = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
		secondLine = [manager cg_lineFragmentRangeAtIndex:1 inTextContainer:container];
		printf("  (note: a row of two long cells gave %lu fragment(s); the first cell is %g wide)\n",
		       (unsigned long)count, (double)zero.size.width);
		check(count > 2, "the two long cells wrap — more than one line each");
		check(secondLine.location != NSNotFound, "and there is a second line fragment to ask about");
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 4. **AND A CELL'S OWN LAYERS ARE RESERVED, SO ITS TEXT IS INSET AND ITS NEIGHBOUR KEEPS OFF.** A cell with 6
	 * points of padding and 1 of border moves its content IN by 7 and its column grows by 14, so the two cells' texts
	 * are separated by the two adjacent insets rather than touching — which is what the first cut of the demonstration
	 * showed. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextTableBlock *left;
		NSTextTableBlock *right;
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 300.0)];
		NSRect zero, one;

		[table setNumberOfColumns:2];
		left = cell(table, 0, 0);
		right = cell(table, 0, 1);
		[left setWidth:1.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
		[left setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
		[right setWidth:1.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
		[right setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
		store = new_table_store([NSArray arrayWithObjects:@"aa", @"bb", nil],
					[NSArray arrayWithObjects:left, right, nil], table);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		zero = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
		one = [manager lineFragmentUsedRectForGlyphAtIndex:3 effectiveRange:NULL];
		printf("  (note: a padded cell — text 0 at x=%g, text 1 at x=%g, gap %g)\n",
		       (double)zero.origin.x, (double)one.origin.x,
		       (double)(one.origin.x - (zero.origin.x + zero.size.width)));
		check(fabs(zero.origin.x - 17.0) < 0.01, "the first cell's text is inset by its 6+1 points of layers");
		check(one.origin.x - (zero.origin.x + zero.size.width) >= 13.9,
		      "and the two cells' texts are separated by the two adjacent insets rather than touching");
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 5. **AND A FIXED-LAYOUT TABLE DIVIDES THE WIDTH EQUALLY.** */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSRect zero, one;

		[table setNumberOfColumns:2];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		store = new_table_store([NSArray arrayWithObjects:@"aa", @"bb", nil],
					[NSArray arrayWithObjects:cell(table, 0, 0), cell(table, 0, 1), nil], table);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		zero = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
		one = [manager lineFragmentUsedRectForGlyphAtIndex:3 effectiveRange:NULL];
		printf("  (note: fixed — cell 0 at x=%g, cell 1 at x=%g, against a padding of 10)\n",
		       (double)zero.origin.x, (double)one.origin.x);
		check(fabs(zero.origin.x - 10.0) < 0.01, "a fixed table's first column starts at the padding");
		check(fabs(one.origin.x - (10.0 + (200.0 - 20.0) / 2.0)) < 0.01,
		      "and the second at the padding plus half the table's width");
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	[pool release];
	printf("text_table_grid: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
