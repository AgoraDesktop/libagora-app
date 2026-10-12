/*
 * menu_cell_ink — does a menu item cell put INK on a surface, in the column its own geometry names?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **WHY THIS IS AN OFFSCREEN TEST, AND WHY IT IS THE RIGHT SHAPE.** Every one of `NSMenuItemCell`'s six drawing
 * doors refused for "THE INK" until this row: the geometry was real and the ink was refused, and the refusal was
 * honest for months because the font stack underneath it answered nil. What that means is the door had never once
 * been called — so the assertion that matters is not that a menu looks nice, it is THAT THE DOOR DRAWS AT ALL,
 * and that what it draws lands where the GEOMETRY says.
 *
 * A bitmap rep and a graphics context over it answer both without a compositor, a window or a running loop: fill
 * the bitmap, ask the cell to draw its title, then read the pixels back. THE GEOMETRY IS THE CHECK AND NOT A
 * SECOND OPINION — `-titleRectForBounds:` is the door this class's real half is made of, and ink outside the
 * column it names would mean the drawing and the geometry disagree about where a menu row's title lives.
 */
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

#include <stdio.h>
#include <string.h>

#define INK_W 200
#define INK_H 24

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

int main(void)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:INK_W pixelsHigh:INK_H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:INK_W * 4 bitsPerPixel:32];
	NSMenuItemCell *cell = [[NSMenuItemCell alloc] initTextCell:@""];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:NULL keyEquivalent:@"o"];
	NSRect frame = NSMakeRect(0.0, 0.0, (CGFloat)INK_W, (CGFloat)INK_H);
	NSRect title;
	int x, y, ink = 0, outside_frame = 0;

	if (rep == nil) {
		printf("FAIL: no bitmap rep — nothing to draw on\n");
		return 1;
	}
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:frame] fill];

	[cell setMenuItem:item];
	[cell setNeedsSizing:YES];
	[cell calcSize];
	title = [cell titleRectForBounds:frame];

	/* **THE MEASUREMENT FIRST, BECAUSE A DOOR WITH A ZERO-WIDE TITLE HAS NOTHING TO DRAW AND WOULD PROVE
	 * NOTHING BY NOT DRAWING IT.** */
	check([cell titleWidth] > 0.0, "the cell MEASURES its title, so there is ink to place");
	check([cell keyEquivalentWidth] > 0.0, "and it measures its key equivalent");

	[cell drawTitleWithFrame:frame inView:nil];

	for (y = 0; y < INK_H; y++) {
		for (x = 0; x < INK_W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c == nil || [c redComponent] >= 0.5) {
				continue;	/* the white the test filled with */
			}
			ink++;
			if ((CGFloat)x < title.origin.x || (CGFloat)x > title.origin.x + title.size.width) {
				outside_frame++;
			}
		}
	}
	check(ink > 0, "the door DREW: a menu title is ink on a surface, where it used to refuse by name");
	check(outside_frame == 0, "and every ink pixel is INSIDE the column `-titleRectForBounds:` named");
	printf("  (note: %d ink pixel(s), in a %g-wide column)\n", ink, (double)[cell titleWidth]);
	printf("menu_cell_ink: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
