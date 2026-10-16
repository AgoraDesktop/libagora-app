/*
 * text_table_collapse.m — `-collapsesBorders`: AN EDGE TWO CELLS SHARE IS DRAWN ONCE, NOT TWICE.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS ABOUT INK, SO THE PROBE READS PIXELS.** A cell's box is its CELL (its column's width), not the extent
 * of its glyphs, so two cells side by side actually meet at the column boundary. When the table collapses its borders
 * the manager draws that shared edge once — by the LEFT cell's MaxX edge — and the right cell's MinX edge is left
 * undrawn, so the doubled seam becomes a single one. The probe draws the same table twice, with the flag off and on,
 * and looks at the columns either side of the seam: the left side must carry the edge in both drawings, and the right
 * side must carry it ONLY when the borders are not collapsed. The outer edge is checked to be untouched, and a lone
 * cell (nothing to share a border with) must come out identical either way. A fourth case gives the two cells
 * DIFFERENT border weights and colours and reads which one owns the shared edge: the HEAVIER cell's, not simply the
 * left cell's. A fifth gives the TABLE itself a border and shows it joining the collapse on its OUTER edges, where it
 * competes with the outer cells by the same rule.
 *
 * THE GEOMETRY IS FIXED LAYOUT ON PURPOSE: two equal columns make every column boundary an integer, so the seam is a
 * pixel column and not a fraction its fill would antialias across.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextBlock.h>
#import <AppKit/NSTextTable.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
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

/* THE STORE: ONE PARAGRAPH PER CELL, each style carrying its cell and an optional integer line height (0 leaves the
 * font's own, which is fractional and would put the row boundaries between pixel rows). */
static NSTextStorage *new_table_store(NSArray *paragraphs, NSArray *cells, CGFloat lineHeight)
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
		if (lineHeight > 0.0) {
			[style setMinimumLineHeight:lineHeight];
			[style setMaximumLineHeight:lineHeight];
		}
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

static NSBitmapImageRep *draw(NSLayoutManager *manager, NSUInteger length)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
	NSGraphicsContext *ctx;
	CGContextRef cg;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	cg = (CGContextRef)[ctx graphicsPort];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[manager drawBackgroundForGlyphRange:NSMakeRange(0, length) atPoint:NSMakePoint(0.0, 0.0)];
	return rep;
}

static int is_pure(NSColor *c, CGFloat r, CGFloat g, CGFloat b)
{
	return c != nil && fabs([c redComponent] - r) < 0.2 && fabs([c greenComponent] - g) < 0.2
		&& fabs([c blueComponent] - b) < 0.2;
}

static int is_red(NSColor *c)
{
	return is_pure(c, 1.0, 0.0, 0.0);
}

static int count_red(NSBitmapImageRep *rep)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			if (is_red([rep colorAtX:x y:y])) {
				count++;
			}
		}
	}
	return count;
}

/* THE PIXELS A VERTICAL LINE CARRIES, in a named colour — which is the whole subject of the row cases. */
static int count_pure_in_column(NSBitmapImageRep *rep, int column, CGFloat r, CGFloat g, CGFloat b)
{
	int y, count = 0;

	if (column < 0 || column >= W) {
		return 0;
	}
	for (y = 0; y < H; y++) {
		if (is_pure([rep colorAtX:column y:y], r, g, b)) {
			count++;
		}
	}
	return count;
}

static int count_red_in_column(NSBitmapImageRep *rep, int column)
{
	return count_pure_in_column(rep, column, 1.0, 0.0, 0.0);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **TWO CELLS IN ONE ROW: THE SHARED VERTICAL EDGE MOVES TO ONE SIDE.** Borders on MinX and MaxX only, so
	 * the seam is two bare vertical strips and nothing else can put ink there. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextTableBlock *left;
		NSTextTableBlock *right;
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSBitmapImageRep *flat;
		NSBitmapImageRep *collapsed;
		NSRect zero, one;
		CGFloat seam;
		int outerCol, flatTotal, collapsedTotal;
		int outerKept, seamByLeft, seamByRightFlat, seamByRightCollapsed, seamBandWhite = 1;
		int x;

		[table setNumberOfColumns:2];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		left = cell(table, 0, 0);
		right = cell(table, 0, 1);
		[left setWidth:4.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder
			 edge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		[right setWidth:4.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder
			  edge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		[left setBorderColor:[NSColor redColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		[right setBorderColor:[NSColor redColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		store = new_table_store([NSArray arrayWithObjects:@"aaaa", @"bbbb", nil],
					[NSArray arrayWithObjects:left, right, nil], 0.0);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];

		flat = draw(manager, [store length]);
		[table setCollapsesBorders:YES];
		collapsed = draw(manager, [store length]);

		zero = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];
		one = [manager lineFragmentUsedRectForGlyphAtIndex:5 effectiveRange:NULL];
		/* THE CELL'S BOX IS ITS COLUMN, so the right cell's frame begins at its content x less its left inset —
		 * four points here — and that is the seam the two boxes share. */
		seam = one.origin.x - 4.0;
		outerCol = (int)(zero.origin.x - 4.0) + 1;

		flatTotal = count_red(flat);
		collapsedTotal = count_red(collapsed);
		outerKept = count_red_in_column(collapsed, outerCol) > 0;
		seamByLeft = count_red_in_column(collapsed, (int)seam - 1) > 0;
		seamByRightFlat = count_red_in_column(flat, (int)seam) > 0;
		seamByRightCollapsed = count_red_in_column(collapsed, (int)seam) > 0;
		for (x = 0; x < 4; x++) {
			if (count_red_in_column(collapsed, (int)seam + x) > 0) {
				seamBandWhite = 0;
			}
		}

		printf("  (note: row — flat %d red pixel(s), collapsed %d; the seam is column %d)\n",
		       flatTotal, collapsedTotal, (int)seam);
		check(flatTotal > 0 && collapsedTotal > 0, "both drawings put border ink down");
		check(collapsedTotal < flatTotal, "collapsing draws FEWER border pixels — a shared edge is drawn once");
		check(seamByRightFlat, "WITHOUT collapse the seam carries the right cell's side of the border");
		check(!seamByRightCollapsed, "and WITH collapse that side is not drawn");
		check(seamByLeft, "while the left cell still draws the one shared edge");
		check(seamBandWhite, "the right cell's whole border band at the seam is left blank");
		check(outerKept, "and the table's outer edge is untouched by the collapse");

		[flat release];
		[collapsed release];
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 2. **TWO CELLS IN ONE COLUMN: THE SHARED HORIZONTAL EDGE MOVES TO ONE SIDE.** The row boundaries are put on
	 * integer points by an integer line height, so the difference between the two drawings is exactly one strip of
	 * border — 4 points tall and as wide as the single column. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextTableBlock *top;
		NSTextTableBlock *bottom;
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSBitmapImageRep *flat;
		NSBitmapImageRep *collapsed;
		int flatTotal, collapsedTotal, difference;
		const int oneStrip = 4 * 180;	/* the border's 4 points across the 180-point column */

		[table setNumberOfColumns:1];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		top = cell(table, 0, 0);
		bottom = cell(table, 1, 0);
		[top setWidth:4.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder
			 edge:(NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
		[bottom setWidth:4.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder
			    edge:(NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
		[top setBorderColor:[NSColor redColor] forEdge:(NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
		[bottom setBorderColor:[NSColor redColor] forEdge:(NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
		store = new_table_store([NSArray arrayWithObjects:@"aaaa", @"bbbb", nil],
					[NSArray arrayWithObjects:top, bottom, nil], 20.0);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];

		flat = draw(manager, [store length]);
		[table setCollapsesBorders:YES];
		collapsed = draw(manager, [store length]);

		flatTotal = count_red(flat);
		collapsedTotal = count_red(collapsed);
		difference = flatTotal - collapsedTotal;
		printf("  (note: column — flat %d, collapsed %d, difference %d (one strip is %d))\n",
		       flatTotal, collapsedTotal, difference, oneStrip);
		check(collapsedTotal > 0, "the collapsed table still draws its borders");
		check(collapsedTotal < flatTotal, "collapsing the horizontal borders removes one of the two shared strips");
		check(fabs((double)difference - (double)oneStrip) <= 8.0,
		      "and the difference is EXACTLY one strip of border, not two and not zero");

		[flat release];
		[collapsed release];
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 3. **AND A LONE CELL HAS NOTHING TO SHARE, SO COLLAPSING CHANGES NOTHING.** A cell with no neighbour keeps
	 * all four of its edges; a collapse that dropped an outer edge would fail this. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextTableBlock *only;
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSBitmapImageRep *flat;
		NSBitmapImageRep *collapsed;
		int flatTotal, collapsedTotal;

		[table setNumberOfColumns:1];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		only = cell(table, 0, 0);
		[only setWidth:4.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
		[only setBorderColor:[NSColor redColor]
			     forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
		store = new_table_store([NSArray arrayWithObject:@"aaaa"], [NSArray arrayWithObject:only], 20.0);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];

		flat = draw(manager, [store length]);
		[table setCollapsesBorders:YES];
		collapsed = draw(manager, [store length]);

		flatTotal = count_red(flat);
		collapsedTotal = count_red(collapsed);
		printf("  (note: lone cell — flat %d, collapsed %d)\n", flatTotal, collapsedTotal);
		check(flatTotal > 0, "a lone cell draws its four edges");
		check(flatTotal == collapsedTotal, "and collapsing a table with nothing to share leaves every edge alone");

		[flat release];
		[collapsed release];
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 4. **AND A SHARED EDGE FOLLOWS THE HEAVIER BORDER, NOT JUST THE LEFT CELL.** The left cell's shared edge is 2
	 * points and the right cell's is 6, so the RIGHT cell is the one that owns the collapsed edge — 6 points wide and
	 * in ITS colour — and the left cell's 2-point edge is the one suppressed. With the flag off both are drawn, which
	 * is what makes the suppression legible. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextTableBlock *left;
		NSTextTableBlock *right;
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSBitmapImageRep *flat;
		NSBitmapImageRep *collapsed;
		int blueLeftFlat, blueLeftCollapsed, redSeam, redSeamWidth = 1;
		int x;

		[table setNumberOfColumns:2];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		left = cell(table, 0, 0);
		right = cell(table, 0, 1);
		[left setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder
			 edge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		[right setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge];
		[right setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge];
		[left setBorderColor:[NSColor blueColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		[right setBorderColor:[NSColor blueColor] forEdge:NSTextBlockMaxXEdge];
		[right setBorderColor:[NSColor redColor] forEdge:NSTextBlockMinXEdge];
		store = new_table_store([NSArray arrayWithObjects:@"aaaa", @"bbbb", nil],
					[NSArray arrayWithObjects:left, right, nil], 0.0);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];

		flat = draw(manager, [store length]);
		[table setCollapsesBorders:YES];
		collapsed = draw(manager, [store length]);

		/* The fixed two-column layout puts the boundary at column 100: the left cell's 2-point MaxX border sits just
		 * left of it and the right cell's 6-point MinX border runs to its right. */
		blueLeftFlat = count_pure_in_column(flat, 99, 0.0, 0.0, 1.0);
		blueLeftCollapsed = count_pure_in_column(collapsed, 99, 0.0, 0.0, 1.0);
		redSeam = count_red_in_column(collapsed, 100);
		for (x = 0; x < 6; x++) {
			if (count_red_in_column(collapsed, 100 + x) == 0) {
				redSeamWidth = 0;
			}
		}
		printf("  (note: unequal — left blue at x=99 is %d flat / %d collapsed; red seam at x=100 is %d)\n",
		       blueLeftFlat, blueLeftCollapsed, redSeam);
		check(blueLeftFlat > 0, "without collapse the left cell draws its own 2-point edge");
		check(blueLeftCollapsed == 0,
		      "with collapse the heavier RIGHT cell owns the edge, so the left cell's is suppressed");
		check(redSeam > 0 && redSeamWidth, "and the shared edge is the right cell's 6-point red border, not the left's blue");

		[flat release];
		[collapsed release];
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	/* 5. **AND THE TABLE'S OWN BORDER JOINS THE COLLAPSE.** The table block draws a 6-point green border and its one
	 * cell a 2-point red one. Collapsed, the HEAVIER table border owns the outer edge and the cell's red edge is
	 * suppressed; uncollapsed, both are drawn. The table's own box is the box around the CELLS, so its frame sits
	 * OUTSIDE the cells' frames and its border is where an outer frame belongs. */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextTableBlock *only;
		NSTextStorage *store;
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 300.0)];
		NSBitmapImageRep *flat;
		NSBitmapImageRep *collapsed;
		int redFlat, redCollapsed, greenTable;

		[table setNumberOfColumns:1];
		[table setLayoutAlgorithm:NSTextTableFixedLayoutAlgorithm];
		[table setWidth:6.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder
			  edge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		[table setBorderColor:[NSColor greenColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		only = cell(table, 0, 0);
		[only setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder
			 edge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		[only setBorderColor:[NSColor redColor] forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge)];
		store = new_table_store([NSArray arrayWithObject:@"aaaa"], [NSArray arrayWithObject:only], 0.0);
		[store addLayoutManager:manager];
		[manager addTextContainer:container];

		flat = draw(manager, [store length]);
		[table setCollapsesBorders:YES];
		collapsed = draw(manager, [store length]);

		redFlat = count_red(flat);
		redCollapsed = count_red(collapsed);
		greenTable = count_pure_in_column(collapsed, 5, 0.0, 1.0, 0.0);
		printf("  (note: table border — red cell edges %d flat / %d collapsed; table green at x=5 is %d)\n",
		       redFlat, redCollapsed, greenTable);
		check(redFlat > 0, "without collapse the cell draws its red edges beside the table's green ones");
		check(redCollapsed == 0, "with collapse the heavier TABLE border wins, so the cell's red edges are suppressed");
		check(greenTable > 0, "and the table's own 6-point green border is the outer edge, at the frame around the cells");
		[flat release];
		[collapsed release];
		[container release];
		[manager release];
		[store release];
		[table release];
	}

	[pool release];
	printf("text_table_collapse: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
