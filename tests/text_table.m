/*
 * text_table.m — THE BOX A PARAGRAPH IS SET IN: `NSTextBlock`, its table cell, and the ground the manager draws.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE BLOCK IS A VALUE AND THE MANAGER IS ITS READER.** `NSTextBlock` measures three layers on four edges, holds a
 * ground and four border colours, and knows how to draw itself; the layout manager finds the block a line carries in
 * its paragraph style and draws the box around the lines that share it. So the probe reads the value (the ledger, the
 * bounds arithmetic, the copy), the cell's place in its table, the style's array, and — the part that matters — the
 * GROUND AND THE BORDER as pixels where the block's lines are.
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

static int count_colour(NSBitmapImageRep *rep, CGFloat r, CGFloat g, CGFloat b)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && fabs([c redComponent] - r) < 0.2 && fabs([c greenComponent] - g) < 0.2
			    && fabs([c blueComponent] - b) < 0.2) {
				count++;
			}
		}
	}
	return count;
}

static NSBitmapImageRep *draw_block(NSLayoutManager *manager, NSRange range)
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
	[manager drawBackgroundForGlyphRange:range atPoint:NSMakePoint(0.0, 0.0)];
	return rep;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextBlock *block = [[NSTextBlock alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE LEDGER AND THE BOUNDS ARITHMETIC.** */
	{
		NSRect content = NSMakeRect(10.0, 10.0, 30.0, 10.0);
		NSRect container = NSMakeRect(0.0, 0.0, 100.0, 100.0);
		NSRect bounds;

		check([block backgroundColor] == nil && [block widthForLayer:NSTextBlockBorder] == 0.0,
		      "a fresh block has no ground and no widths");
		[block setBackgroundColor:[NSColor greenColor]];
		[block setWidth:2.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockBorder];
		[block setWidth:3.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding];
		[block setBorderColor:[NSColor redColor] forEdge:NSTextBlockMinXEdge];
		check([block widthForLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge] == 2.0
		      && [block widthForLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge] == 2.0,
		      "a per-layer width sets all four edges");
		check([block borderColorForEdge:NSTextBlockMinXEdge] == [NSColor redColor]
		      && [block borderColorForEdge:NSTextBlockMaxXEdge] == nil,
		      "and a per-edge colour is answered for that edge alone");
		bounds = [block boundsRectForContentRect:content inRect:container textContainer:nil
					 characterRange:NSMakeRange(0, 1)];
		printf("  (note: content (10,10 30x10) with 5 on every side gave bounds (%g,%g %gx%g))\n",
		       (double)bounds.origin.x, (double)bounds.origin.y, (double)bounds.size.width, (double)bounds.size.height);
		check(bounds.origin.x == 5.0 && bounds.origin.y == 5.0
		      && bounds.size.width == 40.0 && bounds.size.height == 20.0,
		      "`-boundsRectForContentRect:` grows it by the three layers on every edge");
	}

	/* 2. **AND THE CELL KNOWS ITS PLACE IN THE TABLE.** */
	{
		NSTextTable *table = [[NSTextTable alloc] init];
		NSTextTableBlock *cell;

		check([table numberOfColumns] == 1 && [table layoutAlgorithm] == NSTextTableAutomaticLayoutAlgorithm,
		      "a fresh table is one column, laid out automatically");
		[table setNumberOfColumns:3];
		check([table numberOfColumns] == 3, "and the column count is settable");
		cell = [[NSTextTableBlock alloc] initWithTable:table startingRow:1 rowSpan:2 startingColumn:1 columnSpan:2];
		check([cell table] == table && [cell startingRow] == 1 && [cell rowSpan] == 2
		      && [cell startingColumn] == 1 && [cell columnSpan] == 2,
		      "a cell answers the table and its place in it");
		check([cell isKindOfClass:[NSTextBlock class]], "and IS a block, so it has a ground and edges");
		[cell release];
		[table release];
	}

	/* 3. **AND A PARAGRAPH STYLE CARRIES THEM.** */
	{
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		NSParagraphStyle *frozen;

		check([[style textBlocks] count] == 0, "a fresh style has no blocks");
		[style addTextBlock:block];
		check([[style textBlocks] count] == 1 && [[style textBlocks] objectAtIndex:0] == block,
		      "`-addTextBlock:` puts one in");
		frozen = [style copy];
		check([[frozen textBlocks] count] == 1, "and a copy of the style carries it");
		[style release];
		[frozen release];
	}

	/* 4. **AND THE MANAGER DRAWS THE GROUND AND THE BORDER WHERE THE BLOCK'S LINES ARE.** */
	{
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"ab"];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 100.0)];
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		NSBitmapImageRep *rep;
		int green, red;

		[style addTextBlock:block];
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, 2)];
		rep = draw_block(manager, NSMakeRange(0, 2));
		green = count_colour(rep, 0.0, 1.0, 0.0);
		red = count_colour(rep, 1.0, 0.0, 0.0);
		printf("  (note: the block put %d green and %d red pixel(s) around `ab`)\n", green, red);
		check(green > 0, "the block's GROUND is drawn around the paragraph");
		check(red > 0, "and its BORDER is drawn on the frame's edge");
		[rep release];
		[style release];
		[container release];
		[manager release];
		[store release];
	}

	[block release];
	[pool release];
	printf("text_table: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
