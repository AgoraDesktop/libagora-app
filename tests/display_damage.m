/*
 * display_damage — a partial display paints the part, and only the part.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE HALF OF "DRAW ONLY WHAT CHANGED" THAT IS INVISIBLE FROM OUTSIDE.** `NSWindow -displayIfNeeded` asks the
 * content view for the union of every invalidated rectangle and hands it to `-displayRect:`; the window used to
 * pass it on as an ARGUMENT and nothing else, so each `-drawRect:` in the tree still painted its whole bounds and
 * the rasterizer threw the rest away. MEASURED in a live session, that is 20-45 ms of drawing and a full frame
 * across the socket to move a selection wash one cell.
 *
 * So the probe is a view that PAINTS ITS WHOLE BOUNDS ON PURPOSE — the bug's own shape — and three questions
 * about it:
 *
 *   1. The rectangle reaches `-drawRect:` CONVERTED into the view's own coordinates, not the parent's.
 *   2. Pixels inside the requested rectangle are painted.
 *   3. Pixels outside it are NOT: the clip is what makes a partial display partial, and a view that ignores the
 *      rectangle it is given cannot defeat it.
 *
 * Offscreen: a bitmap context as the canvas, no window and no compositor.
 */
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>

#include <stdio.h>

/* THE UNION OF A VIEW'S INVALIDATED RECTANGLES IS THE WINDOW'S PRIVATE SEAM, declared here the way the other
 * probes declare the door they need. */
@interface NSView (AGDamageProbe)
- (NSRect)cg_dirtyUnion;
@end

/* AND THE ONE ARITHMETIC A PARTIAL COPY IS WRONG WITHOUT: a y-up rectangle as top-down buffer rows. */
@interface NSWindow (AGDamageProbe)
+ (NSRange)cg_bufferRowsForDirtyRect:(NSRect)dirty surfaceHeight:(NSInteger)surfaceHeight;
@end

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* A VIEW THAT PAINTS EVERYTHING IT OWNS, WHATEVER DIRTY RECT IT IS GIVEN — and remembers what it was given. */
@interface AGDamageMarker : NSView
{
	NSRect _lastDirty;
	int _draws;
}
- (NSRect)lastDirty;
- (int)draws;
@end

@implementation AGDamageMarker
- (void)drawRect:(NSRect)dirtyRect
{
	_lastDirty = dirtyRect;
	_draws++;
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
}
- (NSRect)lastDirty { return _lastDirty; }
- (int)draws { return _draws; }
@end

static NSBitmapImageRep *new_canvas(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:60 pixelsHigh:60
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:60 * 4 bitsPerPixel:32];
}

/* A RED PIXEL at a DRAWING y: the bitmap counts rows from the top, the drawing from its own origin. */
static int red_at(NSBitmapImageRep *rep, int x, int drawing_y)
{
	NSColor *c = [rep colorAtX:x y:(59 - drawing_y)];

	return c != nil && [c redComponent] > 0.8 && [c greenComponent] < 0.25 && [c blueComponent] < 0.25;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 60.0, 60.0)];
		AGDamageMarker *marker = [[AGDamageMarker alloc] initWithFrame:NSMakeRect(20.0, 20.0, 20.0, 20.0)];
		NSBitmapImageRep *rep;
		NSRect requested = NSMakeRect(25.0, 25.0, 5.0, 5.0);

		[root addSubview:marker];

		/* 1-3. A PARTIAL DISPLAY, PAINTED ONTO A CLEAN CANVAS. */
		rep = new_canvas();
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
		[root displayRect:requested];

		check([marker draws] == 1, "one partial display draws the marker once");
		check(NSEqualRects([marker lastDirty], NSMakeRect(5.0, 5.0, 5.0, 5.0)),
		      "and the rectangle reaches -drawRect: in the VIEW's coordinates (25,25 less its frame at 20,20)");
		check(red_at(rep, 27, 27), "the pixels inside the rectangle are painted");
		check(!red_at(rep, 35, 35),
		      "and a pixel of the SAME view outside it is not — the view painted its whole bounds and the clip refused");
		check(!red_at(rep, 10, 10), "and nothing outside the view is touched either");
		[rep release];

		/* 4. THE SURFACE IS NOT CLEARED UNDER A PARTIAL DISPLAY, which is the other half of the same promise: what
		 * was there before a partial paint has to survive it, or every damaged frame would be drawn on a blank. */
		{
			NSBitmapImageRep *again = new_canvas();

			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:again]];
			/* Through the ROOT, because a rectangle is always in the coordinates of the view it is asked of and
			 * the probe wants a strip of the MARKER: (22,22) in the root is (2,2) inside a frame at (20,20). */
			[root displayRect:NSMakeRect(22.0, 22.0, 4.0, 4.0)];
			check(red_at(again, 23, 23), "a second partial display paints where it was asked");
			check(!red_at(again, 30, 30), "and leaves the rest of the view alone");
			[again release];
		}

		/* 5. THE UNION, WHICH IS WHAT THE WINDOW ASKS A VIEW FOR. Two invalidations that do not touch have one
		 * bounding box, because the region a view keeps is one rectangle — Apple's own simplification. */
		[marker setNeedsDisplayInRect:NSMakeRect(0.0, 0.0, 2.0, 2.0)];
		[marker setNeedsDisplayInRect:NSMakeRect(18.0, 18.0, 2.0, 2.0)];
		check([marker needsDisplayInRect:NSMakeRect(1.0, 1.0, 1.0, 1.0)],
		      "an invalidated corner needs display");
		check([marker needsDisplayInRect:NSMakeRect(19.0, 19.0, 1.0, 1.0)],
		      "and so does the opposite one");
		check(NSEqualRects([marker cg_dirtyUnion], NSMakeRect(0.0, 0.0, 20.0, 20.0)),
		      "and the union of the two is their bounding box, not the view's whole bounds");
		check(![marker needsDisplayInRect:NSMakeRect(40.0, 40.0, 2.0, 2.0)],
		      "and a rectangle the region does not touch answers NO");

		/* 6. **THE MIRROR, WHICH IS THE BUG THAT MADE A PARTIAL PAINT INVISIBLE.** A rectangle is y-up and the
		 * buffer's memory rows are top-down, so the rows a rectangle names are `height - y1 .. height - y0`.
		 * Copying `y0 .. y1` instead copied a band reflected about the window's middle: MEASURED in a live session,
		 * a click two thirds of the way up a window wrote its pixels into a blank band the same distance down, so
		 * the click appeared to do nothing until a full frame repainted the window. This is the arithmetic, and it
		 * fails loudly if it is ever un-mirrored. */
		{
			NSRange rows = [NSWindow cg_bufferRowsForDirtyRect:NSMakeRect(0.0, 436.0, 80.0, 85.0)
							     surfaceHeight:634];

			check(rows.location == 113 && rows.length == 85,
			      "a y-up rectangle at 436..521 of a 634-point window is buffer rows 113..198");
			rows = [NSWindow cg_bufferRowsForDirtyRect:NSMakeRect(0.0, -10.0, 80.0, 20.0)
						 surfaceHeight:634];
			check(rows.location == 624 && rows.length == 10,
			      "and a rectangle hanging off the bottom is clamped to the rows that exist");
		}

		[root release];
		[marker release];
	}
	return s_failed != 0;
}
