/*
 * text_layout_draw.m — THE INK: THE LAYOUT MANAGER DRAWING WHAT IT LAID OUT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS WHERE THE INK LANDS, SO THE PROBE READS PIXELS.** Two lines are two bands of ink; the ORIGIN the
 * caller gives moves them; a glyph range over ONE line draws that line and not the other; and a foreground colour in
 * the STORE is the colour the glyphs come out — which is the one thing a count of bands cannot see and a colour read
 * can.
 *
 * **AND THE RECT A RANGE OCCUPIES IS CHECKED AS EXACT POINTS**, because that is what an invalidation is spelled in:
 * the whole store is two lines tall from y=0, the first line is one line tall from y=0, and the second starts a line
 * down.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
#include <math.h>
#include <stdio.h>

#define W 220
#define H 70

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* **THE MANAGER DRAWS IN A FLIPPED CONTAINER'S COORDINATES (y DOWN), AND A REP'S CONTEXT IS NOT FLIPPED** — so the
 * mirror a superview would apply is applied here, in the same order the text view's probes use. WITHOUT it the lines
 * come out in reverse order and every band claim is about the wrong one. */
static NSBitmapImageRep *draw(NSLayoutManager *manager, NSRange range, NSPoint origin)
{
	NSBitmapImageRep *rep = new_rep();
	NSGraphicsContext *ctx;
	CGContextRef cg;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	cg = (CGContextRef)[ctx graphicsPort];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[manager drawGlyphsForGlyphRange:range atPoint:origin];
	return rep;
}

/* THE NUMBER OF BANDS OF INK, which is orientation-independent and is what "two lines" means. */
static int ink_bands(NSBitmapImageRep *rep)
{
	int y, bands = 0, inRun = 0;

	for (y = 0; y < H; y++) {
		int x, has = 0;

		for (x = 0; x < W && !has; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			has = (c != nil && [c redComponent] < 0.6 && [c greenComponent] < 0.6);
		}
		if (has && !inRun) {
			bands++;
			inRun = 1;
		} else if (!has) {
			inRun = 0;
		}
	}
	return bands;
}

/* THE FIRST COLUMN AND ROW CARRYING INK, so "the origin moved it" is a number rather than a guess. */
static void first_ink(NSBitmapImageRep *rep, int *xOut, int *yOut)
{
	int x, y;

	*xOut = -1;
	*yOut = -1;
	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5 && [c greenComponent] < 0.5) {
				if (*yOut < 0) {
					*yOut = y;
				}
				if (*xOut < 0 || x < *xOut) {
					*xOut = x;
				}
			}
		}
	}
}

/* **THE TOP AND BOTTOM ROWS CARRYING INK, WHICH IS HOW TWO LINES ARE TOLD APART WITHOUT GUESSING WHERE THE SPLIT IS.**
 * A partition at the middle of a rep is a guess about where a line ends, and a two-line layout in a 70-point rep puts
 * the split THROUGH the second line — MEASURED, which is how this helper replaced the halves. */
static void ink_bounds(NSBitmapImageRep *rep, int *topOut, int *bottomOut)
{
	int x, y;

	*topOut = -1;
	*bottomOut = -1;
	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5 && [c greenComponent] < 0.5) {
				if (*topOut < 0) {
					*topOut = y;
				}
				*bottomOut = y;
				break;
			}
		}
	}
}

static int has_red(NSBitmapImageRep *rep)
{
	int x, y;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4) {
				return 1;
			}
		}
	}
	return 0;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 100.0)];
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	CGFloat lineHeight = [font ascender] - [font descender];

	setvbuf(stdout, NULL, _IONBF, 0);
	[store addLayoutManager:manager];
	[manager addTextContainer:container];

	/* 1. **TWO LINES ARE TWO BANDS OF INK**, which is the whole claim of drawing a layout rather than a string. */
	{
		NSBitmapImageRep *rep = draw(manager, NSMakeRange(0, [[store string] length]), NSMakePoint(0.0, 0.0));

		printf("  (note: two lines drawn at the origin gave %d band(s) of ink)\n", ink_bands(rep));
		check(ink_bands(rep) == 2, "the manager DRAWS the two lines it laid out as two bands of ink");
		[rep release];
	}

	/* 2. **AND THE ORIGIN IS THE CONTAINER'S PLACE IN THE VIEW, SO IT MOVES THE INK.** Apple's contract: "The origin
	 * point … is that container's origin in the currently focused view's coordinates." */
	{
		int x0, y0, x1, y1;
		NSBitmapImageRep *a = draw(manager, NSMakeRange(0, 3), NSMakePoint(0.0, 0.0));
		NSBitmapImageRep *b = draw(manager, NSMakeRange(0, 3), NSMakePoint(30.0, 12.0));

		first_ink(a, &x0, &y0);
		first_ink(b, &x1, &y1);
		printf("  (note: one line at (0,0) begins at (%d,%d); at (30,12) at (%d,%d))\n", x0, y0, x1, y1);
		check(x1 > x0 && y1 > y0, "the origin the caller gives MOVES the ink");
		check(fabs((double)(x1 - x0) - 30.0) < 2.0 && fabs((double)(y1 - y0) - 12.0) < 2.0,
		      "by exactly the origin's own offset");
		[a release];
		[b release];
	}

	/* 3. **AND A GLYPH RANGE DRAWS THE GLYPHS IN IT AND NO OTHERS.** Each line is drawn alone, and the two ink extents
	 * must not meet: the range's own line is drawn and the other is not, which is what makes this a draw of a RANGE
	 * rather than of a string. */
	{
		NSBitmapImageRep *firstOnly = draw(manager, NSMakeRange(0, 3), NSMakePoint(0.0, 0.0));
		NSBitmapImageRep *secondOnly = draw(manager, NSMakeRange(4, 3), NSMakePoint(0.0, 0.0));
		int topFirst, bottomFirst, topSecond, bottomSecond;

		ink_bounds(firstOnly, &topFirst, &bottomFirst);
		ink_bounds(secondOnly, &topSecond, &bottomSecond);
		printf("  (note: the FIRST line's ink spans rows %d..%d and the SECOND's %d..%d)\n",
		       topFirst, bottomFirst, topSecond, bottomSecond);
		check(bottomFirst >= 0 && topSecond >= 0 && bottomFirst < topSecond,
		      "the second line's glyph range draws BELOW the first line's and does not overlap it");
		[firstOnly release];
		[secondOnly release];
	}

	/* 4. **AND THE BOUNDING RECT IS THE UNION OF THE FRAGMENTS A RANGE TOUCHES**, in container coordinates and in
	 * exact points — which is what an invalidation is spelled in. */
	{
		NSRect all = [manager boundingRectForGlyphRange:NSMakeRange(0, 7) inTextContainer:container];
		NSRect first = [manager boundingRectForGlyphRange:NSMakeRange(0, 3) inTextContainer:container];
		NSRect second = [manager boundingRectForGlyphRange:NSMakeRange(4, 3) inTextContainer:container];

		printf("  (note: bounding rects — all (%g,%g %gx%g), first (%g,%g %gx%g), second (%g,%g %gx%g))\n",
		       (double)all.origin.x, (double)all.origin.y, (double)all.size.width, (double)all.size.height,
		       (double)first.origin.x, (double)first.origin.y, (double)first.size.width, (double)first.size.height,
		       (double)second.origin.x, (double)second.origin.y, (double)second.size.width, (double)second.size.height);
		check(fabs(all.size.height - 2.0 * lineHeight) < 0.01 && all.origin.y == 0.0,
		      "the whole store's bounding rect is TWO lines tall from the container's top");
		check(fabs(first.size.height - lineHeight) < 0.01 && first.origin.y == 0.0,
		      "the first line's is ONE line tall from the top");
		check(fabs(second.origin.y - lineHeight) < 0.01, "and the second line's begins a line down");
	}

	/* 5. **AND A COLOUR IN THE STORE IS THE COLOUR THE GLYPHS COME OUT.** A count of bands cannot see this and a read
	 * of one pixel can, which is why the probe does both. */
	{
		NSBitmapImageRep *plain;
		NSBitmapImageRep *red;

		plain = draw(manager, NSMakeRange(0, 3), NSMakePoint(0.0, 0.0));
		check(!has_red(plain), "with no colour attribute the glyphs are drawn in the control's own ink");
		[plain release];
		[store addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, [[store string] length])];
		red = draw(manager, NSMakeRange(0, 3), NSMakePoint(0.0, 0.0));
		check(has_red(red), "and a RED foreground attribute makes them red — the store's attributes reach the ink");
		[red release];
	}

	[container release];
	[manager release];
	[store release];
	[pool release];
	printf("text_layout_draw: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
