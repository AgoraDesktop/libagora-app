/*
 * view_offset — the one thing a scroll moves: a non-zero BOUNDS ORIGIN.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A `bounds` ORIGIN THAT IS NOT ZERO IS WHAT "SCROLLED" MEANS**, and it is read in exactly three places: the
 * coordinate conversions a click goes through, the `-displayRect:` a live window draws through, and the
 * `fn_draw_view` an offscreen cache draws through. All three used to ignore it (and the offscreen one refused it by
 * name), which is why the scroll view's arithmetic was right and nothing moved: a clip view that had scrolled
 * answered every geometry door correctly and drew the unscrolled tree.
 *
 * WHAT IS ASSERTED:
 *
 *   1. `-convertPoint:toView:` SHIFTS BY THE BOUNDS ORIGIN — a point at the origin of the view's own coordinates
 *      lands at the frame's origin, not at the frame's origin plus the origin.
 *   2. The inverse conversion adds it back, so the round trip is exact — and the same for a FLIPPED view, where the
 *      shift and the mirror are applied in one formula and an error in either shows up here.
 *   3. `-displayRect:` DRAWS THE OFFSET: a marker at one place in a view's own coordinates is drawn somewhere else
 *      once that view has scrolled, by exactly the origin.
 *   4. `-cacheDisplayInRect:` no longer REFUSES such a view: it draws it, which the old code would not have.
 *
 * Offscreen, with a bitmap rep as the destination — the same substrate the control and chrome probes draw into.
 */
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>

#include <math.h>
#include <stdio.h>

#define W 100
#define H 100

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int near(double a, double b)
{
	return fabs(a - b) < 0.01;
}

/* **A VIEW THAT MARKS ONE PLACE IN ITS OWN COORDINATES.** A 10-point red strip at the TOP of its bounds (y 90..100
 * in the drawing's own, bottom-up terms), so a scroll of the view's bounds origin can be read as the strip MOVING. */
@interface AGMarker : NSView
@end

@implementation AGMarker
- (void)drawRect:(NSRect)r
{
	(void)r;
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 90.0, 100.0, 10.0)] fill];
}
@end

/* AND THE SAME MARK, IN A VIEW THAT IS FLIPPED — so the bounds shift and the mirror are exercised together. */
@interface AGFlippedMarker : AGMarker
@end

@implementation AGFlippedMarker
- (BOOL)isFlipped
{
	return YES;
}
@end

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* A RED PIXEL, read at a DRAWING y (the bitmap's rows count from the top, the drawing's from the bottom). */
static int red_at(NSBitmapImageRep *rep, int x, int drawing_y)
{
	NSColor *c = [rep colorAtX:x y:(H - 1 - drawing_y)];

	return c != nil && [c redComponent] > 0.8 && [c greenComponent] < 0.25 && [c blueComponent] < 0.25;
}

static int red_ink(NSBitmapImageRep *rep)
{
	int x, y, n = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.8 && [c greenComponent] < 0.25 && [c blueComponent] < 0.25) {
				n++;
			}
		}
	}
	return n;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

		/* 1 AND 2. **THE CONVERSION, WITH AND WITHOUT A FLIP.** A point at the origin of the marker's own
		 * coordinates is at the frame's origin once converted — the whole meaning of a bounds origin. */
		{
			AGMarker *m = [[AGMarker alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSPoint q;

			[root addSubview:m];
			[m setBoundsOrigin:NSMakePoint(0.0, 30.0)];
			q = [m convertPoint:NSMakePoint(10.0, 80.0) toView:root];
			printf("  (note: (10,80) in a view scrolled to y=30 converts to (%.0f,%.0f) in the root)\n",
			       (double)q.x, (double)q.y);
			check(near(q.x, 10.0) && near(q.y, 50.0),
			      "a point in a scrolled view converts 30 points UP, by the bounds origin");
			check(near([m convertPoint:q fromView:root].y, 80.0),
			      "and the inverse conversion adds it back, so the round trip is exact");
			[m release];
		}
		{
			AGFlippedMarker *f = [[AGFlippedMarker alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSPoint q;

			[root addSubview:f];
			[f setBoundsOrigin:NSMakePoint(0.0, 30.0)];
			q = [f convertPoint:NSMakePoint(10.0, 80.0) toView:root];
			printf("  (note: the same point in a FLIPPED view converts to (%.0f,%.0f))\n",
			       (double)q.x, (double)q.y);
			check(near(q.x, 10.0) && near(q.y, 50.0),
			      "in a FLIPPED view the bounds shift and the mirror are one formula, and it lands the same way");
			check(near([f convertPoint:q fromView:root].y, 80.0),
			      "and its inverse round-trips too");
			[f release];
		}

		/* 3. **THE DRAWING.** The marker's strip is at its bounds y 90..100; scrolled by 30 it must be drawn at
		 * device y 60..70 and NOT at 90..95. */
		{
			AGMarker *m = [[AGMarker alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSBitmapImageRep *rep;

			[root addSubview:m];
			[m setBoundsOrigin:NSMakePoint(0.0, 30.0)];
			rep = new_rep();
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[m displayRect:[m bounds]];
			check(red_at(rep, 50, 65), "`-displayRect:` DRAWS the bounds offset: the mark is at 90-30, not at 90");
			check(!red_at(rep, 50, 92), "and it is NOT still where the unscrolled view would have put it");
			[rep release];
			[m release];
		}

		/* 4. **AND THE OFFSCREEN PATH, WHICH USED TO REFUSE.** With no shim, `fn_draw_view` printed APPKIT-REFUSE
		 * and drew nothing; now it draws, so there is red ink in the rep. */
		{
			AGMarker *m = [[AGMarker alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSBitmapImageRep *rep;

			[root addSubview:m];
			[m setBoundsOrigin:NSMakePoint(0.0, 30.0)];
			rep = new_rep();
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[m cacheDisplayInRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H) toBitmapImageRep:rep];
			check(red_ink(rep) > 0,
			      "`-cacheDisplayInRect:` DRAWS a scrolled view instead of refusing it by name");
			[rep release];
			[m release];
		}

		[root release];
		printf("view_offset: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
