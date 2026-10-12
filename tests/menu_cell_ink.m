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
#import <AppKit/NSImage.h>

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

	/* ---- AND AN ITEM THAT HAS AN IMAGE: THE OTHER DOOR THAT REFUSED FOR "THE INK" ------------------
	 * An item's icon goes in its OWN column, between the state image's empty strip and the title — and the
	 * title then starts further right, which is the part worth asserting: a door that drew the image OVER the
	 * title would still put ink on the surface. */
	{
		NSBitmapImageRep *icon = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:16
			pixelsHigh:16 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:16 * 4 bitsPerPixel:32];
		NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)];
		NSMenuItem *iitem = [[NSMenuItem alloc] initWithTitle:@"With Icon" action:NULL keyEquivalent:@""];
		NSMenuItemCell *icell = [[NSMenuItemCell alloc] initTextCell:@""];
		NSBitmapImageRep *canvas;
		NSRect ititle;
		int ix, iy, icon_ink = 0, title_ink = 0;

		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:icon]];
		[[NSColor blackColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 16.0, 16.0)] fill];
		[image addRepresentation:icon];
		[iitem setImage:image];
		[icell setMenuItem:iitem];
		[icell setNeedsSizing:YES];
		[icell calcSize];
		ititle = [icell titleRectForBounds:frame];
		check([icell imageWidth] > 0.0, "an item WITH an image measures its image's column");
		check(ititle.origin.x >= [icell imageWidth], "and the title's column starts AFTER it");

		canvas = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:INK_W pixelsHigh:INK_H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:INK_W * 4 bitsPerPixel:32];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:canvas]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
		[icell drawImageWithFrame:frame inView:nil];
		[icell drawTitleWithFrame:frame inView:nil];

		for (iy = 0; iy < INK_H; iy++) {
			for (ix = 0; ix < INK_W; ix++) {
				NSColor *c = [canvas colorAtX:ix y:iy];

				if (c == nil || [c redComponent] >= 0.5) {
					continue;
				}
				if ((CGFloat)ix < [icell imageWidth]) {
					icon_ink++;
				} else if ((CGFloat)ix >= ititle.origin.x) {
					title_ink++;
				}
			}
		}
		check(icon_ink > 0, "the IMAGE door DREW: an item's icon is ink on a surface");
		check(title_ink > 0, "and the title still drew, in the column the image pushed it to");
		printf("  (note: icon %d ink pixel(s) in a %g-wide column; title %d)\n", icon_ink,
		       (double)[icell imageWidth], title_ink);
	}

	/* ---- AND THE CHECKMARK'S COLUMN, WHICH THIS CLASS SAID COULD NOT BE MEASURED ---------------------------------
	 * `-calcSize` claimed "`NSMenuItem` in this tier has no state-image door". It has three, and the `state` that
	 * chooses between them — so the zero was a claim about a door that was there the whole time. */
	{
		NSBitmapImageRep *tick = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:20
			pixelsHigh:20 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:20 * 4 bitsPerPixel:32];
		NSImage *mark = [[NSImage alloc] initWithSize:NSMakeSize(20.0, 20.0)];
		NSMenuItem *sitem = [[NSMenuItem alloc] initWithTitle:@"Checked" action:NULL keyEquivalent:@""];
		NSMenuItemCell *scell = [[NSMenuItemCell alloc] initTextCell:@""];
		NSBitmapImageRep *canvas;
		NSRect srect;
		int sx, sy, mark_ink = 0;

		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:tick]];
		[[NSColor blackColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 20.0, 20.0)] fill];
		[mark addRepresentation:tick];
		[sitem setState:NSOnState];
		[sitem setOnStateImage:mark];
		[scell setMenuItem:sitem];
		[scell setNeedsSizing:YES];
		[scell calcSize];
		srect = [scell stateImageRectForBounds:frame];
		check([scell stateImageWidth] > 0.0, "an item with an ON state image MEASURES the checkmark's column");
		check([scell titleRectForBounds:frame].origin.x >= [scell stateImageWidth],
		      "and the title starts after it");

		canvas = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:INK_W pixelsHigh:INK_H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:INK_W * 4 bitsPerPixel:32];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:canvas]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
		[scell drawStateImageWithFrame:frame inView:nil];

		for (sy = 0; sy < INK_H; sy++) {
			for (sx = 0; sx < INK_W; sx++) {
				NSColor *c = [canvas colorAtX:sx y:sy];

				if (c != nil && [c redComponent] < 0.5 && (CGFloat)sx < srect.origin.x + srect.size.width) {
					mark_ink++;
				}
			}
		}
		check(mark_ink > 0, "the STATE door DREW: the checkmark is ink in its own column");
		printf("  (note: checkmark %d ink pixel(s) in a %g-wide column)\n", mark_ink, (double)[scell stateImageWidth]);
	}
	printf("menu_cell_ink: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
