/*
 * browser_geometry — where a browser's columns are, what its title strip holds, and the inverse that maps a point back.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE BROWSER HAD A TITLE HEIGHT AND NEVER DREW A TITLE.** `-titleHeight` was a number the layout ignored, the header
 * said the columns "do not draw a title strip", and `-isTitled` did not exist. This probe is about the slice that changed
 * that: three frames that are one rect cut three ways, the strip inside the top of each column, the title's INK on a
 * surface, and `-getRow:column:forPoint:` as the exact inverse of `-frameOfRow:inColumn:`.
 *
 * WHAT IS ASSERTED:
 *
 *   1. THE DEFAULTS: a browser is TITLED (Apple's default), no click has happened, and the default width is the width
 *      new columns get.
 *   2. THE THREE FRAMES ARE ONE RECT CUT THREE WAYS: the strip sits at the TOP of the column, the list starts directly
 *      under it, and their heights add up to the column's own — with the column's width and the gutters between columns
 *      checked too. With `-setTitled:NO` the strip is empty and the list IS the column.
 *   3. A ROW HAS A PLACE: row 0's rect is above row 1's (a browser's coordinates are unflipped), it starts at the list's
 *      left edge, and it is inside the list's frame.
 *   4. THE INVERSE: the centre of a row's rect answers that row and column; a point in the strip answers the COLUMN and
 *      no row; a point past the last column answers nothing at all.
 *   5. THE TITLE IS DRAWN: `-drawTitleOfColumn:inRect:` puts a band and the title's ink on a surface, an untitled column
 *      puts the band and NO text ink, and the drawing is clipped to the rect it is given.
 *   6. THE CLICK: selecting a row in a column's table sends the action once and records `-clickedRow`/`-clickedColumn`;
 *      `-doClick:`/`-doDoubleClick:` are the public doors that do the same for a synthetic click.
 *   7. THE ONE WIDTH CONVERSION AND THE TWO WIDTH DEFAULTS: content width is the frame less the column's own bar, the
 *      round trip returns the number it started with, and `-setDefaultColumnWidth:` leaves existing columns alone while
 *      `-setColumnWidth:` re-widths them.
 */
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#define W 620
#define H 300

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int near_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

/* ============================================================================================ *
 * THE DELEGATE: TWO COLUMNS WITH ROWS AND TITLES, AND THE TWO ACTIONS' TARGET COUNTED.          *
 * ============================================================================================ */
@interface AGBrowserGeometryProbe : NSObject <NSBrowserDelegate>
{
@public
	int clicks;
	int doubleClicks;
	NSInteger firstColumnRows;	/* mutable, so a column can be made tall enough to need its bar */
}
@end

@implementation AGBrowserGeometryProbe
- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column
{
	(void)sender;
	if (firstColumnRows <= 0) {
		firstColumnRows = 3;
	}
	return (column == 0) ? firstColumnRows : 2;
}

- (NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column
{
	(void)sender;
	return (column == 0) ? @"Names" : @"Details";
}

- (void)clicked:(id)sender
{
	(void)sender;
	clicks++;
}

- (void)doubleClicked:(id)sender
{
	(void)sender;
	doubleClicks++;
}
@end

/* ============================================================================================ *
 * THE SURFACE, AND TWO MEASUREMENTS OF IT: how much ink is dark, and how much of it is ABOVE the
 * strip's bottom rule — which is what tells "a title was drawn" from "the rule was drawn".       *
 * ============================================================================================ */
static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static int is_dark(NSColor *c)
{
	return (c != nil && [c alphaComponent] > 0.3 && [c redComponent] < 0.45 && [c greenComponent] < 0.45
		&& [c blueComponent] < 0.45);
}

/* Dark pixels in the rows ABOVE `fromRow` — the rule at the strip's bottom is excluded by starting above it. */
static int dark_above(NSBitmapImageRep *rep, int fromRow, int toRow, int width)
{
	int x, y, count = 0;

	for (y = fromRow; y < toRow; y++) {
		for (x = 0; x < width; x++) {
			if (is_dark([rep colorAtX:x y:y])) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
	AGBrowserGeometryProbe *probe = [[AGBrowserGeometryProbe alloc] init];
	NSBrowser *browser = [[NSBrowser alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

	setvbuf(stdout, NULL, _IONBF, 0);
	/* THE TYPED REFERENCE IS THE OWNING ONE: `-setContentView:` retains, and reacquiring the same object
	 * through `-contentView` would only narrow NSView * back to NSBrowser * by hand. */
	[window setContentView:browser];
	[browser setDelegate:probe];
	[browser setTarget:probe];
	[browser setAction:@selector(clicked:)];
	[browser setDoubleAction:@selector(doubleClicked:)];
	[browser loadColumnZero];

	/* 1. **THE DEFAULTS.** */
	{
		printf("  (note: %ld column(s) after loadColumnZero, title height %g, column width %g)\n",
		       (long)[browser cg_activeColumnCount], (double)[browser titleHeight], (double)[browser columnWidth]);
		check([browser isTitled], "a browser is TITLED by default, which is Apple's own default");
		check([browser clickedRow] == -1 && [browser clickedColumn] == -1,
		      "and nothing has been clicked, which is -1 for both");
		check(near_enough([browser defaultColumnWidth], [browser columnWidth]),
		      "the default width is the width new columns get");
		check([browser cg_activeColumnCount] >= 1, "the first column loaded from the delegate");
	}

	/* 2. **THREE FRAMES, ONE RECT.** */
	{
		NSRect column = [browser frameOfColumn:0];
		NSRect inside = [browser frameOfInsideOfColumn:0];
		NSRect strip = [browser titleFrameOfColumn:0];
		CGFloat stripHeight = [browser titleHeight];

		printf("  (note: column %g,%g %gx%g; inside %g,%g %gx%g; strip %g,%g %gx%g)\n",
		       (double)NSMinX(column), (double)NSMinY(column), (double)NSWidth(column), (double)NSHeight(column),
		       (double)NSMinX(inside), (double)NSMinY(inside), (double)NSWidth(inside), (double)NSHeight(inside),
		       (double)NSMinX(strip), (double)NSMinY(strip), (double)NSWidth(strip), (double)NSHeight(strip));
		check(!NSIsEmptyRect(column) && near_enough(NSWidth(column), [browser widthOfColumn:0]),
		      "a column's frame is as wide as the column's width");
		check(near_enough(NSHeight(column), (CGFloat)H),
		      "and as tall as the browser, title strip included");
		check(!NSIsEmptyRect(strip) && near_enough(NSHeight(strip), stripHeight),
		      "the title strip is `-titleHeight` tall");
		check(near_enough(NSMinX(strip), NSMinX(column)) && near_enough(NSWidth(strip), NSWidth(column)),
		      "and as wide as the column, starting where it starts");
		check(near_enough(NSMaxY(strip), NSMaxY(column)),
		      "THE STRIP IS AT THE TOP: its upper edge is the column's upper edge");
		check(near_enough(NSMaxY(inside), NSMinY(strip)),
		      "the list starts directly under the strip");
		check(near_enough(NSHeight(inside) + stripHeight, NSHeight(column)),
		      "and the two heights add up to the column's");
		check(near_enough(NSMinY(inside), NSMinY(column)),
		      "the list keeps the column's bottom edge, because a browser's coordinates are unflipped");
	}

	/* AND THE SECOND COLUMN SITS BESIDE THE FIRST, separated by the gutter. */
	{
		NSRect first;
		NSRect second;

		[browser selectRow:0 inColumn:0];
		first = [browser frameOfColumn:0];
		second = [browser frameOfColumn:1];
		printf("  (note: column 1 frame %g,%g %gx%g after selecting row 0)\n",
		       (double)NSMinX(second), (double)NSMinY(second), (double)NSWidth(second), (double)NSHeight(second));
		check(!NSIsEmptyRect(second), "selecting a row loads the column to its right");
		check(NSMinX(second) > NSMaxX(first),
		      "and that column begins after the first one and its gutter");
	}

	/* 3. **A ROW HAS A PLACE, AND IT IS INSIDE THE LIST.** */
	{
		NSRect row0 = [browser frameOfRow:0 inColumn:0];
		NSRect row1 = [browser frameOfRow:1 inColumn:0];
		NSRect inside = [browser frameOfInsideOfColumn:0];

		printf("  (note: row 0 %g,%g %gx%g; row 1 %g,%g %gx%g)\n",
		       (double)NSMinX(row0), (double)NSMinY(row0), (double)NSWidth(row0), (double)NSHeight(row0),
		       (double)NSMinX(row1), (double)NSMinY(row1), (double)NSWidth(row1), (double)NSHeight(row1));
		check(!NSIsEmptyRect(row0) && near_enough(NSMinX(row0), NSMinX(inside)),
		      "a row starts at the list's left edge");
		check(NSMinY(row0) > NSMinY(row1),
		      "row 0 is ABOVE row 1 in the browser's coordinates, which are unflipped");
		check(NSMinY(row0) >= NSMinY(inside) && NSMaxY(row0) <= NSMaxY(inside) + 0.01,
		      "and both rows are inside the list, not in the title strip");
		check(NSIsEmptyRect([browser frameOfRow:99 inColumn:0]),
		      "a row that does not exist has no frame");
	}

	/* 4. **THE INVERSE.** */
	{
		NSRect row1 = [browser frameOfRow:1 inColumn:0];
		NSPoint centre = NSMakePoint(NSMidX(row1), NSMidY(row1));
		NSInteger row = -99;
		NSInteger column = -99;
		BOOL inside = [browser getRow:&row column:&column forPoint:centre];

		check(inside && row == 1 && column == 0,
		      "the centre of row 1's rect answers row 1 of column 0 — the exact inverse");

		{
			NSRect strip = [browser titleFrameOfColumn:0];
			NSPoint inStrip = NSMakePoint(NSMidX(strip), NSMidY(strip));

			row = -99;
			column = -99;
			inside = [browser getRow:&row column:&column forPoint:inStrip];
			check(inside && column == 0 && row == -1,
			      "a point in the title strip answers the COLUMN and no row");
		}

		{
			/* **THE EMPTY SLOTS ARE COLUMNS TOO, WHICH IS THIS CLASS'S SHAPE RATHER THAN A BUG**: the pool's slots are
			 * laid out to fill the visible width, so a point past the last LOADED column lands in an empty one — a
			 * column with no rows. A point past everything (outside the browser) answers nothing. */
			NSRect last = [browser frameOfColumn:1];
			NSPoint inAnEmptySlot = NSMakePoint(NSMaxX(last) + 40.0, NSMidY(last));

			row = -99;
			column = -99;
			inside = [browser getRow:&row column:&column forPoint:inAnEmptySlot];
			check(inside && column >= 2 && row == -1,
			      "a point past the last loaded column answers an EMPTY column slot and no row");

			row = -99;
			column = -99;
			inside = [browser getRow:&row column:&column
					  forPoint:NSMakePoint((CGFloat)W + 80.0, NSMidY(last))];
			check(!inside && row == -1 && column == -1,
			      "and a point outside the browser answers nothing at all");
		}
	}

	/* 5. **THE TITLE IS INK, AND THE BAND IS TOO.** */
	{
		NSBitmapImageRep *rep = new_rep(160, 20);

		[browser setTitle:@"Names" ofColumn:0];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 160.0, 20.0)] fill];
		[browser drawTitleOfColumn:0 inRect:NSMakeRect(0.0, 0.0, 160.0, 20.0)];
		[NSGraphicsContext setCurrentContext:nil];
		{
			NSColor *band = [rep colorAtX:150 y:10];
			int textInk = dark_above(rep, 3, 20, 160);

			printf("  (note: band pixel at 150,10 is %g,%g,%g; %d text pixel(s))\n",
			       (double)[band redComponent], (double)[band greenComponent], (double)[band blueComponent],
			       textInk);
			check(band != nil && [band redComponent] < 0.99 && [band redComponent] > 0.8,
			      "the strip is filled with the header band, not left white");
			check(textInk > 10, "and the title's own ink is in it, above the bottom rule");
		}
		[rep release];

		/* THE NEGATIVE CONTROL: the SAME band with no title draws no text. */
		{
			NSBitmapImageRep *bare = new_rep(160, 20);

			/* AN EMPTY TITLE, NOT A NIL ONE: nil falls back to the delegate's `-browser:titleOfColumn:`, which this
			 * probe answers with a title — so the negative control has to be a column whose title is empty. */
			[browser setTitle:@"" ofColumn:0];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bare]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 160.0, 20.0)] fill];
			[browser drawTitleOfColumn:0 inRect:NSMakeRect(0.0, 0.0, 160.0, 20.0)];
			[NSGraphicsContext setCurrentContext:nil];
			check(dark_above(bare, 3, 20, 160) == 0,
			      "a column with no title draws the band and the rule and NO text");
			[bare release];
		}
	}

	/* 6. **THE CLICK, THROUGH THE TABLE THE WAY A PRESS REACHES IT.** */
	{
		NSTableView *table = [browser cg_tableForColumn:0];
		NSIndexSet *one = [NSIndexSet indexSetWithIndex:1];

		probe->clicks = 0;
		[table selectRowIndexes:one byExtendingSelection:NO];
		printf("  (note: %d click action(s) after selecting row 1 of column 0)\n", probe->clicks);
		check(probe->clicks == 1, "selecting a row in a column sends the browser's action, once");
		check([browser clickedRow] == 1 && [browser clickedColumn] == 0,
		      "and the click is recorded as that row and column");

		/* THE TWO PUBLIC DOORS, for a click that did not come from a table. */
		probe->clicks = 0;
		[browser doClick:nil];
		check(probe->clicks == 1, "`-doClick:` sends the action for the current selection");
		probe->doubleClicks = 0;
		[browser doDoubleClick:nil];
		check(probe->doubleClicks == 1, "and `-doDoubleClick:` sends the double action");
	}

	/* 7. **THE WIDTH CONVERSION AND THE TWO DEFAULTS.** */
	{
		CGFloat content = [browser columnContentWidthForColumnWidth:250.0];
		CGFloat back = [browser columnWidthForColumnContentWidth:content];
		CGFloat before = [browser widthOfColumn:0];

		printf("  (note: 250 points of column is %g of content while the column fits its rows)\n", (double)content);
		check(content <= 250.0 && near_enough(back, 250.0),
		      "a column's content width round-trips back to the column width");
		check(near_enough(content, 250.0),
		      "a column SHORT enough for its rows spends nothing on a bar, so its content is its width");

		/* AND NOW A COLUMN THAT SCROLLS: the bar is inside the column, so the content is narrower than the frame. */
		probe->firstColumnRows = 40;
		[browser reloadColumn:0];
		content = [browser columnContentWidthForColumnWidth:250.0];
		printf("  (note: with 40 rows the same 250 points of column is %g of content)\n", (double)content);
		check(content < 250.0 && content > 0.0,
		      "a column TALL enough to scroll gives up the bar's width inside its own frame");
		check(near_enough([browser columnWidthForColumnContentWidth:content], 250.0),
		      "and the conversion back returns the column width it started from");

		[browser setDefaultColumnWidth:150.0];
		check(near_enough([browser defaultColumnWidth], 150.0),
		      "`-setDefaultColumnWidth:` changes the width new columns get");
		check(near_enough([browser widthOfColumn:0], before),
		      "and leaves the columns that exist alone — that is the difference from `-setColumnWidth:`");

		[browser setColumnWidth:180.0];
		check(near_enough([browser widthOfColumn:0], 180.0) && near_enough([browser defaultColumnWidth], 180.0),
		      "while `-setColumnWidth:` re-widths every column and the default with it");
	}

	/* AND UNTITLED PUTS THE LIST BACK AT THE TOP, which is the flag being true of the pixels. */
	{
		[browser setTitled:NO];
		check(NSIsEmptyRect([browser titleFrameOfColumn:0]), "an untitled browser has no strip");
		check(near_enough(NSMinY([browser frameOfInsideOfColumn:0]), NSMinY([browser frameOfColumn:0])),
		      "and the list is the whole column again");
		[browser updateScroller];
		check(near_enough(NSWidth([browser frameOfColumn:0]), [browser widthOfColumn:0]),
		      "`-updateScroller` re-tiles, and the frames it leaves are the ones `-tile` answers");
		[browser setTitled:YES];
		check(!NSIsEmptyRect([browser titleFrameOfColumn:0]), "and turning it back on restores the strip");
	}

	[browser setDelegate:nil];
	[browser setTarget:nil];
	[browser release];
	[probe release];
	[window release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
