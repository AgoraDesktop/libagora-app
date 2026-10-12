/*
 * menu_view_ink — does a MENU VIEW lay rows out and call the cells that draw them?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THIS IS THE TEST THE CLASS WAS MISSING.** The tree had a menu, items and a cell that could draw a title, and
 * nothing that arranged cells into rows — so nothing ever called one. What is asserted here is the arrangement:
 * one row per item, IN ORDER, each with its title drawn in it, and the HIGHLIGHTED row distinguished from its
 * neighbours. Offscreen, so it runs anywhere.
 */
#import <AppKit/NSMenuView.h>
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

/* Ink anywhere in a row's band, and whether the row carries the highlight colour. */
static void scan(NSBitmapImageRep *rep, int top_row, int *ink, int *highlight)
{
	int x, y;
	int y0 = (VIEW_ROWS - 1 - top_row) * 22;	/* Cocoa y counts up from the bottom */
	int y1 = y0 + 22;

	*ink = 0;
	*highlight = 0;
	for (y = y0; y < y1; y++) {
		for (x = 0; x < VIEW_W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c == nil) {
				continue;
			}
			if ([c blueComponent] > 0.6 && [c redComponent] < 0.4) {
				(*highlight)++;
			} else if ([c redComponent] < 0.5) {
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
		pixelsHigh:VIEW_ROWS * 22 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:VIEW_W * 4 bitsPerPixel:32];
	if (rep == nil) {
		printf("FAIL: no bitmap rep\n");
		return 1;
	}
	view = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)VIEW_W,
							   (CGFloat)(VIEW_ROWS * 22))];
	[view setMenu:menu];
	check([view isHorizontal] == NO, "a menu view is a DROPDOWN unless it is told otherwise");
	check([view requiredHeight] == (CGFloat)(VIEW_ROWS * 22), "and it asks for one row per item");

	/* THE MIDDLE ROW IS THE HIGHLIGHTED ONE, so a view that highlighted the first row every time would fail. */
	[view setHighlightedItem:[menu itemAtIndex:1]];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[view drawRect:[view bounds]];

	for (row = 0; row < VIEW_ROWS; row++) {
		scan(rep, row, &ink[row], &hi[row]);
	}
	check(ink[0] > 0 && ink[1] > 0 && ink[2] > 0,
	      "every row was DRAWN: three items, three rows with their own titles in them");
	check(hi[1] > 0, "and the HIGHLIGHTED row carries the highlight");
	check(hi[0] == 0 && hi[2] == 0, "and its neighbours do not");
	printf("  (note: ink %d/%d/%d, highlight %d/%d/%d, rows top to bottom)\n",
	       ink[0], ink[1], ink[2], hi[0], hi[1], hi[2]);

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
					if ([c blueComponent] > 0.6 && [c redComponent] < 0.4) { bar_hi[row]++; }
					else if ([c redComponent] < 0.5) { bar_ink[row]++; }
				}
			}
			x0f += wf[row];
		}
		check(bar_ink[0] > 0 && bar_ink[1] > 0 && bar_ink[2] > 0,
		      "every COLUMN was drawn, left to right, each with its own title");
		check(bar_hi[1] > 0 && bar_hi[0] == 0 && bar_hi[2] == 0,
		      "and the highlight is on the middle COLUMN only");
		printf("  (note: bar columns %d/%d/%d px wide, ink %d/%d/%d, highlight %d/%d/%d)\n",
		       w[0], w[1], w[2], bar_ink[0], bar_ink[1], bar_ink[2], bar_hi[0], bar_hi[1], bar_hi[2]);
	}
	printf("menu_view_ink: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
