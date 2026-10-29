/*
 * clip_view_clips — a clip view's document may not draw outside the clip view.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DEFECT THIS MEASURES WAS THE PANE ABOVE A SCROLLED LOG WEARING THE LOG'S TEXT.** `NSView -displayRect:` clips
 * each child to the child's FRAME region, and a document view taller than its clip has a frame region BIGGER than the
 * visible band — so on any full repaint the document drew its whole height and the overflow landed on its neighbour.
 * A clip view exists to prevent exactly that, and it did not clip.
 *
 * The claim is measured in pixels: a document that paints a strong band 700 points down (far below the 150-point clip)
 * is displayed through the window's own paint path, and the surface above the clip must be untouched.
 */
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

#define SURFACE_W 400
#define SURFACE_H 300
#define CLIP_W 200
#define CLIP_H 150

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* A DOCUMENT THAT PAINTS ITS WHOLE HEIGHT, with a band far below the visible part. The band is what a scrolled log's
 * last lines are: ink at document coordinates the clip is supposed to hide. */
@interface AGTallDocument : NSView
@end

@implementation AGTallDocument

- (BOOL)isFlipped
{
	return YES;
}

- (void)drawRect:(NSRect)rect
{
	(void)rect;
	/* EVERYTHING, in a colour nothing else uses, and a second colour only in the band at 700. */
	[[NSColor colorWithCalibratedRed:0.05 green:0.65 blue:0.10 alpha:1.0] setFill];
	NSRectFill(NSMakeRect(0.0, 0.0, [self bounds].size.width, [self bounds].size.height));
	[[NSColor colorWithCalibratedRed:0.95 green:0.05 blue:0.05 alpha:1.0] setFill];
	NSRectFill(NSMakeRect(0.0, 700.0, [self bounds].size.width, 100.0));
}

@end

/* THE COLOUR AT A POINT OF THE RENDERED SURFACE, in 0-255. The surface is the window's content view drawn into a
 * bitmap, so the coordinates are the content view's — flipped into the bitmap's own space here. */
static void surface_size(NSBitmapImageRep *rep, NSInteger *w, NSInteger *h)
{
	*w = [rep pixelsWide];
	*h = [rep pixelsHigh];
}

static void colour_at(NSBitmapImageRep *rep, NSInteger x, NSInteger y, int *r, int *g, int *b)
{
	NSInteger w, h;
	unsigned char *data = [rep bitmapData];

	surface_size(rep, &w, &h);
	if (x < 0 || y < 0 || x >= w || y >= h) {
		*r = -1;
		*g = -1;
		*b = -1;
		return;
	}
	{
		unsigned char *px = data + (y * [rep bytesPerRow]) + (x * 4);

		*r = px[0];
		*g = px[1];
		*b = px[2];
	}
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		NSView *content;
		NSScrollView *scroll;
		NSClipView *clip;
		AGTallDocument *document;
		NSBitmapImageRep *surface;
		NSGraphicsContext *context;
		int r = 0, g = 0, b = 0;

		(void)[application finishLaunching];
		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, SURFACE_W, SURFACE_H)
						     styleMask:NSTitledWindowMask
						       backing:NSBackingStoreBuffered
							 defer:NO];
		content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, SURFACE_W, SURFACE_H)];
		/* WHITE, so anything drawn on it is unambiguous. */
		{
			NSView *backdrop = content;

			[window setContentView:backdrop];
			[backdrop setNeedsDisplay:YES];
		}
		scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(100.0, 100.0, CLIP_W, CLIP_H)];
		document = [[AGTallDocument alloc] initWithFrame:NSMakeRect(0.0, 0.0, CLIP_W, 900.0)];
		[scroll setDocumentView:document];
		[content addSubview:scroll];
		clip = [scroll contentView];

		surface = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:SURFACE_W pixelsHigh:SURFACE_H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:SURFACE_W * 4 bitsPerPixel:32];

		/* START FROM WHITE, so "untouched" means white rather than "whatever was there". */
		{
			NSGraphicsContext *blank = [NSGraphicsContext graphicsContextWithBitmapImageRep:surface];

			[NSGraphicsContext saveGraphicsState];
			[NSGraphicsContext setCurrentContext:blank];
			[[NSColor whiteColor] setFill];
			NSRectFill(NSMakeRect(0.0, 0.0, SURFACE_W, SURFACE_H));
			[NSGraphicsContext restoreGraphicsState];
		}

		/* **THE WHOLE CONTENT VIEW, WHICH IS THE PAINT A WINDOW DOES AFTER A RESIZE OR A FULL INVALIDATION.** That is
		 * the paint that leaked: a strip-limited scroll never showed it. */
		context = [NSGraphicsContext graphicsContextWithBitmapImageRep:surface];
		[NSGraphicsContext saveGraphicsState];
		[NSGraphicsContext setCurrentContext:context];
		/* **`-displayRect:` AND NOT `-displayRectIgnoringOpacity:`.** The latter paints through the other path
		 * (`fn_draw_view`), which clips every view to its own bounds and therefore cannot leak — a test that used it
		 * passed against the defect and taught nothing. The window's dirty pass draws through THIS door. */
		(void)context;
		[content displayRect:NSMakeRect(0.0, 0.0, SURFACE_W, SURFACE_H)];
		[NSGraphicsContext restoreGraphicsState];

		check(clip != nil, "the clip view exists");
		check([document frame].size.height > CLIP_H, "the document is taller than the clip");

		/* 1. THE DOCUMENT IS VISIBLE INSIDE THE CLIP — otherwise a blank surface would pass every test below. */
		{
			NSRect clipInContent = [clip convertRect:[clip bounds] toView:content];
			NSInteger cx = (NSInteger)NSMidX(clipInContent);
			NSInteger cy = (NSInteger)(SURFACE_H - NSMidY(clipInContent));

			colour_at(surface, cx, cy, &r, &g, &b);
			if (!(g > 100 && r < 100)) {
				printf("       inside the clip the colour is (%d,%d,%d)\n", r, g, b);
			}
			check(g > 100 && r < 100, "the document's own ink is inside the clip");
		}

		/* 2. AND NOTHING OF IT IS ABOVE THE CLIP. The band lives at document y=700, far below the band the clip shows;
		 * the row directly above the clip is where the overflow used to land. */
		{
			NSRect clipInContent = [clip convertRect:[clip bounds] toView:content];
			NSInteger x = (NSInteger)NSMidX(clipInContent);
			NSInteger yAbove = (NSInteger)(SURFACE_H - NSMaxY(clipInContent) - 5.0);

			colour_at(surface, x, yAbove, &r, &g, &b);
			if (!(r > 240 && g > 240 && b > 240)) {
				printf("       above the clip the colour is (%d,%d,%d), expected white\n", r, g, b);
			}
			check(r > 240 && g > 240 && b > 240, "nothing the document painted above the clip reached the surface");
		}

		/* 3. AND NONE OF THE BAND'S RED, ANYWHERE ON THE SURFACE. The band cannot be shown at all with an unscrolled
		 * clip, so a single red pixel is a document that drew outside its window. */
		{
			NSInteger w, h, x, y;
			NSInteger red = 0;

			surface_size(surface, &w, &h);
			for (y = 0; y < h; y += 3) {
				for (x = 0; x < w; x += 3) {
					colour_at(surface, x, y, &r, &g, &b);
					if (r > 200 && g < 90 && b < 90) {
						red++;
					}
				}
			}
			if (red > 0) {
				printf("       %ld sampled point(s) carry the off-screen band\n", (long)red);
			}
			check(red == 0, "the off-screen band is nowhere on the surface");
		}

		[document release];
		[scroll release];
		[content release];
		[window release];
		[surface release];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
