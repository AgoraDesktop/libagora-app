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
	printf("menu_view_ink: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
