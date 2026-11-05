/*
 * menu_view_ink — does a MENU VIEW lay rows out and call the cells that draw them?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THIS IS THE TEST THE CLASS WAS MISSING.** The tree had a menu, items and a cell that could draw a title, and
 * nothing that arranged cells into rows — so nothing ever called one. What is asserted here is the arrangement:
 * one row per item, IN ORDER, each with its title drawn in it, and the HIGHLIGHTED row distinguished from its
 * neighbours. Offscreen, so it runs anywhere.
 */
#import <AppKit/NSMenuView.h>
/* **THE CELL'S OWN HEADER, NOT JUST THE VIEW'S FORWARD DECLARATION OF IT.** `NSMenuView.h` says `@class
 * NSMenuItemCell` — enough to hold a pointer and not enough to ask it anything: without this the compiler answers
 * `id` for `-titleWidth` and then refuses to cast a pointer to a double. THE SECOND TIME TODAY, one class over from
 * `NSMenu` in the application, and the same reading both times: the error looks like arithmetic. */
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

#include <stdio.h>

#define VIEW_W 200
#define VIEW_ROWS 3

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* **THE BAR'S FACE, WHICH IS WHAT A BAR IS DRAWN ON.** A bar paints no panel of its own — the window's background is
 * the menu bar's — so a test has to stand in for it, and the stand-in has to be the COLOUR IT REALLY IS: 235/255 grey.
 * These two bitmaps used to be filled WHITE, which was fine while every title was dark and is not while a highlighted
 * title is white. */
#define BAR_FACE (235.0 / 255.0)

/* **INK, ON A PANEL OR ON THE ACCENT CHIP.** A row's title is dark on the panel and WHITE on the chip, so "dark" is
 * only half the question: white counts, the panel's own 0.92 face does not, and this is the criterion every count in
 * this file uses. */
static BOOL is_ink(NSColor *c)
{
	if (c == nil) {
		return NO;
	}
	if ([c redComponent] < 0.5) {
		return YES;
	}
	return [c redComponent] > 0.97 && [c greenComponent] > 0.97 && [c blueComponent] > 0.97;
}

/* Ink anywhere in a row's band, and whether the row carries the highlight colour. */
static void scan(NSBitmapImageRep *rep, int top_row, int *ink, int *highlight)
{
	int x, y;
	int y0 = (int)NSMenuPanelPadding + (VIEW_ROWS - 1 - top_row) * 22;	/* y up from the bottom, one padding in */
	int y1 = y0 + 22;

	*ink = 0;
	*highlight = 0;
	for (y = y0; y < y1; y++) {
		for (x = 0; x < VIEW_W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c == nil) {
				continue;
			}
			/* **THE CHIP IS THE ACCENT COLOUR, WHICH IS (0.64, 0.60, 1.00) — NOT SOMETHING RED CAN BE
			 * EXCLUDED BY.** This test counted a pixel as highlight when its blue was above 0.6 AND its red below
			 * 0.4, which the accent's own red of 0.64 fails: the criterion could never match the chip it was
			 * looking for. It passed anyway, on TWO stray pixels in the title's antialiasing — MEASURED, by
			 * dumping the row: the chip reads (0.64, 0.60, 1.00) at every sample and the count was 2. So the
			 * count is now taken against the accent the view actually fills with, and the assertion below asks for
			 * a STRIP worth of it rather than for a non-zero number, because a stray pixel is exactly what the old
			 * one was measuring. */
			if ([c blueComponent] > 0.90 && [c blueComponent] - [c redComponent] > 0.20) {
				(*highlight)++;
			} else if (is_ink(c)) {
				/* **WHITE IS INK TOO, AND THIS COUNT USED TO MISS IT.** A highlighted row's title is
				 * `+selectedMenuItemTextColor` — white on the accent chip — and ink used to be counted as "red below
				 * 0.5", which white is not: the highlighted row's title would have counted ZERO. */
				(*ink)++;
			}
		}
	}
}

int main(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Test"];
	NSMenuView *view;
	NSBitmapImageRep *rep;
	int row, ink[VIEW_ROWS], hi[VIEW_ROWS];

	[menu addItemWithTitle:@"Open Recent" action:NULL keyEquivalent:@"o"];
	[menu addItemWithTitle:@"Save" action:NULL keyEquivalent:@"s"];
	[menu addItemWithTitle:@"Close" action:NULL keyEquivalent:@"w"];

	rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:VIEW_W
		pixelsHigh:VIEW_ROWS * 22 + (int)(2 * NSMenuPanelPadding) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:VIEW_W * 4 bitsPerPixel:32];
	if (rep == nil) {
		printf("FAIL: no bitmap rep\n");
		return 1;
	}
	view = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)VIEW_W,
							   (CGFloat)(VIEW_ROWS * 22) + 2.0 * NSMenuPanelPadding)];
	[view setMenu:menu];
	check([view isHorizontal] == NO, "a menu view is a DROPDOWN unless it is told otherwise");
	check([view requiredHeight] == (CGFloat)(VIEW_ROWS * 22) + 2.0 * NSMenuPanelPadding,
	      "and it asks for a row per item PLUS the panel's own padding");

	/* THE MIDDLE ROW IS THE HIGHLIGHTED ONE, so a view that highlighted the first row every time would fail. */
	[view setHighlightedItem:[menu itemAtIndex:1]];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[view drawRect:[view bounds]];

	for (row = 0; row < VIEW_ROWS; row++) {
		scan(rep, row, &ink[row], &hi[row]);
	}
	check(ink[0] > 0 && ink[1] > 0 && ink[2] > 0,
	      "every row was DRAWN: three items, three rows with their own titles in them");
	/* A CHIP IS A BAND ACROSS THE ROW, so the count is a fraction of it: a handful of pixels would be a stray
	 * antialiased pixel wearing the accent's clothes, which is what the old `> 0` was in fact accepting. */
	check(hi[1] > 200, "and the HIGHLIGHTED row carries the highlight — a CHIP, not a stray pixel");
	check(hi[0] == 0 && hi[2] == 0, "and its neighbours do not");
	printf("  (note: ink %d/%d/%d, highlight %d/%d/%d, rows top to bottom)\n",
	       ink[0], ink[1], ink[2], hi[0], hi[1], hi[2]);

	/* ---- AND A ROW THAT OPENS A MENU WEARS THE TRIANGLE ------------------------------------------------
	 *
	 * The mark is the row's own, drawn in the trailing column the cell reserved for it; without one a menu asks a person
	 * to discover the submenu by hovering. The rect is asked of the cell, which is what the drawing asks, and the ink is
	 * counted inside it — which is also the check that the triangle is not drawn over the title. */
	{
		NSMenu *parent = [[NSMenu alloc] initWithTitle:@"Parent"];
		NSMenu *child = [[NSMenu alloc] initWithTitle:@"Child"];
		NSMenuView *withSubmenu;
		NSBitmapImageRep *shot;
		NSMenuItemCell *submenuCell;
		NSMenuItem *more;
		NSRect indicator;
		int found = 0;
		int x, y;

		[child addItemWithTitle:@"Inside" action:NULL keyEquivalent:@""];
		[parent addItemWithTitle:@"Plain" action:NULL keyEquivalent:@""];
		more = [parent addItemWithTitle:@"More" action:NULL keyEquivalent:@""];
		[more setSubmenu:child];
		shot = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:240
			pixelsHigh:2 * 22 + (int)(2 * NSMenuPanelPadding) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:240 * 4 bitsPerPixel:32];
		withSubmenu = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0,
									  2.0 * 22.0 + 2.0 * NSMenuPanelPadding)];
		[withSubmenu setMenu:parent];
		submenuCell = [withSubmenu cellForItemAtIndex:1];
		check([submenuCell submenuWidth] > 0.0, "a row with a submenu reserves the indicator's column");
		check([[withSubmenu cellForItemAtIndex:0] submenuWidth] == 0.0,
		      "and a row without one reserves nothing");
		check([submenuCell keyEquivalentWidth] == 0.0
		      && NSMaxX([submenuCell submenuIndicatorRectForBounds:[withSubmenu rectForItemAtIndex:1]]) > 0.0,
		      "the column sits at the trailing edge, where a shortcut would be");
		indicator = [submenuCell submenuIndicatorRectForBounds:[withSubmenu rectForItemAtIndex:1]];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:shot]];
		[withSubmenu drawRect:[withSubmenu bounds]];
		for (y = (int)NSMinY(indicator); y < (int)NSMaxY(indicator); y++) {
			/* **THE BITMAP IS NOT FLIPPED AND THE VIEW IS**, so a view's y counts from the other end here — the same
			 * correction `-scan` makes for the rows. */
			int row = (int)[shot pixelsHigh] - 1 - y;

			for (x = (int)NSMinX(indicator); x < (int)NSMaxX(indicator); x++) {
				if (is_ink([shot colorAtX:x y:row])) {
					found++;
				}
			}
		}
		printf("  (note: %d ink pixels inside the indicator rect)\n", found);
		check(found > 4, "and the row that opens a menu wears a triangle in it");
	}

	/* ---- AND THE SAME ITEMS AS A BAR ---------------------------------------------------------------
	 * A MENU BAR IS THE SAME CLASS, and what changes is not the drawing but the ARRANGEMENT: columns running
	 * RIGHT from the left edge, each as wide as its own title, instead of rows stacking down from the top. */
	{
		NSBitmapImageRep *bar = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400
			pixelsHigh:22 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:400 * 4 bitsPerPixel:32];
		NSMenuView *hv = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 22.0)];
		/* **THE WIDTHS ARE KEPT AS THEY COME.** A bar's columns are as wide as their titles, which is a
		 * FRACTIONAL number, and the first version of this scan truncated them to `int` and then walked up to
		 * that boundary — so the neighbour's first pixel column, one pixel wide and 22 tall, was counted as the
		 * neighbour's highlight. MEASURED: highlight 0/972/22, where the 22 was exactly one column edge. */
		CGFloat wf[VIEW_ROWS];
		int w[VIEW_ROWS], x, y, bar_ink[VIEW_ROWS], bar_hi[VIEW_ROWS];

		CGFloat x0f = 0.0;

		/* **AND THE ITEMS WEAR SUBMENUS, BECAUSE A REAL BAR'S DO.** Every title in the menu bar opens a menu, so an item
		 * that opens one is the ordinary case and not the exception — and it is what the alignment check below is for:
		 * the submenu's trailing column is a DROPDOWN's, and subtracting it from a BAR's title rect is exactly the defect
		 * that leaned every title in the session's bar eight points out of its chip. */
		{
			NSUInteger index;

			for (index = 0; index < VIEW_ROWS; index++) {
				NSMenu *inside = [[[NSMenu alloc] initWithTitle:@"Inside"] autorelease];

				[inside addItemWithTitle:@"An Item" action:NULL keyEquivalent:@""];
				[[menu itemAtIndex:(NSInteger)index] setSubmenu:inside];
			}
		}
		[hv setMenu:menu];
		[hv setHorizontal:YES];
		[hv setHighlightedItem:[menu itemAtIndex:1]];
		check([hv isHorizontal], "a view told it is a BAR says so");
		for (row = 0; row < VIEW_ROWS; row++) {
			wf[row] = [hv widthForItemAtIndex:row];
			w[row] = (int)wf[row];
		}
		check([hv requiredWidth] == wf[0] + wf[1] + wf[2],
		      "and it asks for the SUM of its items' widths, which a bar cannot know by arithmetic");
		check(w[0] > 0 && w[1] > 0 && w[2] > 0, "each column is as wide as its title");
		check([hv requiredWidth] < 400.0, "and the three together still fit the bar");

		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bar]];
		/* **AND THE CANVAS IS FILLED FIRST, WHICH THIS SECTION DID NOT DO AND THE OTHER ONE DOES.** A BAR PAINTS
		 * NO PANEL OF ITS OWN — the window's background is the menu bar's, told to it by the server — so a test
		 * that drew a bar onto an untouched bitmap was measuring UNINITIALISED MEMORY. MEASURED: "ink" of 2046
		 * pixels in a column 93 wide and 22 tall, which is the whole rectangle, because a zeroed bitmap is black
		 * and black is ink. The fill stands in for the window's background, which is what a bar is drawn on. */
		[[NSColor colorWithCalibratedRed:BAR_FACE green:BAR_FACE blue:BAR_FACE alpha:1.0] setFill];
		[[NSBezierPath bezierPathWithRect:[hv bounds]] fill];
		[hv drawRect:[hv bounds]];

		x0f = 0.0;
		for (row = 0; row < VIEW_ROWS; row++) {
			int from = (int)x0f + 1;			/* INSIDE the column, so a fractional edge is nobody's */
			int to = (int)(x0f + wf[row]) - 1;

			bar_ink[row] = 0;
			bar_hi[row] = 0;
			for (y = 0; y < 22; y++) {
				for (x = from; x <= to && x < 400; x++) {
					NSColor *c = [bar colorAtX:x y:y];

					if (c == nil) { continue; }
					if ([c blueComponent] > 0.90 && [c blueComponent] - [c redComponent] > 0.20) { bar_hi[row]++; }
					else if (is_ink(c)) { bar_ink[row]++; }
				}
			}
			x0f += wf[row];
		}
		check(bar_ink[0] > 0 && bar_ink[1] > 0 && bar_ink[2] > 0,
		      "every COLUMN was drawn, left to right, each with its own title");

		/* **AND EVERY TITLE SITS IN THE MIDDLE OF ITS COLUMN, WHICH IS WHERE ITS CHIP IS.** A bar's column is its
		 * title plus the bar's own padding, and the highlight chip is that column inset by a point — so a title drawn
		 * from a rect NARROWER than the column leans out of its chip. MEASURED, and this is the defect the check is
		 * for: the cells of a real bar carry submenus, the submenu's column was subtracted from the title's rect, and
		 * every title in the session's menu bar leaned eight points to the left of the chip it sat in.
		 *
		 * The tolerance is the glyphs' own: the ink starts at the first stem's side bearing and stops before the last
		 * glyph's, so the two edges are never equal. Three pixels either way is the bearing, not an alignment — and the
		 * defect this catches put every title EIGHT pixels out, so the two cannot be confused. */
		{
			NSUInteger column;
			BOOL centred = YES;

			for (column = 0; column < VIEW_ROWS; column++) {
				NSRect cellRect = [hv rectForItemAtIndex:(NSInteger)column];
				NSRect titleRect = [[hv cellForItemAtIndex:(NSInteger)column] titleRectForBounds:cellRect];
				int from = (int)NSMinX(cellRect);
				int to = (int)NSMaxX(cellRect);
				int first = -1, last = -1;
				int at, y;

				for (at = from; at < to; at++) {
					for (y = 0; y < 22; y++) {
						if (is_ink([bar colorAtX:at y:y])) {
							if (first < 0) first = at;
							last = at;
							break;
						}
					}
				}
				if (first < 0 || last < 0) {
					centred = NO;
					continue;
				}
				if (fabs((double)((first + last) / 2.0) - (double)NSMidX(titleRect)) > 3.0) {
					centred = NO;
				}
			}
			check(centred, "and each title's ink is centred in the rect its own cell says it draws into");
		}
		/* **AND THE FIRST COLUMN OF A BAR IS SET IN BOLD, WHICH IS THE APPLICATION MENU'S DUE.**
		 *
		 * THE MEASURE IS THE SAME TITLE TWICE, AND IT HAD TO BE. The first version of this compared the first
		 * column's INK PER PIXEL against its neighbours' — and the neighbours are DIFFERENT STRINGS: `Open
		 * Recent` is a denser word than `Close` whatever face it is set in, so that check could have passed with
		 * no bold anywhere. A weight is a property of a face applied to a string, and the only way to ask about it
		 * is to set THE SAME STRING both ways.
		 *
		 * Two questions, because they fail for different reasons: the bold face must MEASURE wider (a
		 * `-calcSize` question, and the column is what would clip it), and it must DRAW denser (a `-drawRect:`
		 * question). Width alone would pass on a face that measured bold and drew regular. */
		{
			NSMenuItemCell *plain = [[NSMenuItemCell alloc] initTextCell:@""];
			NSBitmapImageRep *other;
			double bold_ink, plain_ink;

			[plain setMenuItem:[menu itemAtIndex:0]];
			[plain setNeedsSizing:YES];
			[plain calcSize];
			NSMenuItemCell *bold_cell = [hv cellForItemAtIndex:0];

			/* **AND THE CELLS ARE ASKED, NOT THE PICTURE — because a weight is the cell's own answer.** The
			 * surroundings are read into locals first: `check([a && [b c]], ...)` parses its leading bracket as a
			 * MESSAGE SEND, which is a compile error that reads like a mistake in `check`. */
			check(![plain bold], "a cell is NOT bold until it is told to be");
			check(bold_cell != nil && [bold_cell bold], "and the BAR's first cell says it is");
			check(bold_cell != nil && [bold_cell titleWidth] > [plain titleWidth],
			      "the BOLD face measures wider than the plain one for the same title");

			other = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400 pixelsHigh:22
				bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:400 * 4 bitsPerPixel:32];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:other]];
			[[NSColor colorWithCalibratedRed:BAR_FACE green:BAR_FACE blue:BAR_FACE alpha:1.0] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 400.0, 22.0)] fill];
			[plain drawTitleWithFrame:NSMakeRect(0.0, 0.0, 400.0, 22.0) inView:nil];

			plain_ink = 0.0;
			for (y = 0; y < 22; y++) {
				for (x = 0; x < 400; x++) {
					if (is_ink([other colorAtX:x y:y])) {
						plain_ink += 1.0;
					}
				}
			}
			/* the bar's first column, over the width THAT cell measured */
			bold_ink = (double)bar_ink[0] / (double)w[0];
			plain_ink = plain_ink / (double)[plain titleWidth];
			check(bold_ink > plain_ink,
			      "and it DRAWS denser for the same title, which is what bold means to a reader");
			printf("  (note: the same title — ink per column pixel, bold %.2f vs plain %.2f; the bar's "
			       "column is %.1f wide with %d inked, the plain cell's title %.1f wide with %.0f "
			       "inked)\n", bold_ink, plain_ink, (double)w[0], bar_ink[0],
			       (double)[plain titleWidth], plain_ink * (double)[plain titleWidth]);
			check(w[0] > 0, "and the bar's first column has a width to divide by");
		}
		check(bar_hi[1] > 0 && bar_hi[0] == 0 && bar_hi[2] == 0,
		      "and the highlight is on the middle COLUMN only");

		/* **AND THE TITLES ARE CENTRED IN THE BAR, WHICH IS A THING A PICTURE SHOWED AND NO TEST SAID.** A bar's
		 * items are as tall as the BAR and a title is placed on its font's ascent and descent — because Core Text
		 * fills a frame from its rect's TOP DOWNWARD, so the ink hangs from wherever it is told to start, and
		 * centring the MEASURED LINE centres a box that contains leading the ink never uses. MEASURED before the
		 * fix: ink on rows 2..12 of a 24-pixel bar, a centre of 7.0 where the bar's is 11.5. */
		{
			int first = -1, last = -1, row_ink = 0;

			for (y = 0; y < 22; y++) {
				row_ink = 0;
				for (x = 0; x < 400; x++) {
					NSColor *c = [bar colorAtX:x y:y];

					if (is_ink(c) && !([c blueComponent] > 0.90 && [c blueComponent] - [c redComponent] > 0.20)) {
						row_ink++;
					}
				}
				if (row_ink > 0) {
					if (first < 0) { first = y; }
					last = y;
				}
			}
			check(first >= 0, "the bar's titles put ink on some row");
			if (first >= 0) {
				/* **THE CENTRE IS THIS VIEW'S, NOT A NUMBER FROM SOMEWHERE ELSE.** This bar is 22 pixels tall,
				 * so its centre is 10.5 — and the first version of this check compared against 11.5, which is
				 * the centre of the 24-pixel MENU BAR the real thing sits in. An assertion carrying another
				 * geometry's constant passes for the wrong reason or fails for one. */
				double centre = (first + last) / 2.0;
				double want = (22.0 - 1.0) / 2.0;

				check(centre >= want - 1.0 && centre <= want + 1.0,
				      "and that ink is CENTRED in the bar, not hanging from its top");
				printf("  (note: bar ink on rows %d..%d, centre %.1f, this bar's centre %.1f)\n",
				       first, last, centre, want);
			}
		}
		printf("  (note: bar columns %d/%d/%d px wide, ink %d/%d/%d, highlight %d/%d/%d)\n",
		       w[0], w[1], w[2], bar_ink[0], bar_ink[1], bar_ink[2], bar_hi[0], bar_hi[1], bar_hi[2]);
	}
	printf("menu_view_ink: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
