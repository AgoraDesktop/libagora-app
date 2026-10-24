/*
 * appkit_hidpi — does a window render at the resolution the screen has, or does it render at half of it?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CLIENT'S HALF OF HIDPI IS ONE QUESTION: IS A POINT WORTH ONE PIXEL OR TWO?** The compositor says with
 * `wl_output.scale`; this file draws a shape at a known POINT position and the accompanying checker measures where it
 * landed in DEVICE pixels. A window whose context was made at the frame's size and told nothing about the scale puts
 * the shape at half the distance and half the size — which on a 2x screen is a UI drawn in the corner of itself.
 *
 * **THE SHAPE IS 20 POINTS AT (20, 20)**, and the window is 200x100 points at (50, 40) — a placement chosen so every
 * number is distinct and none of them is 1. On a 2x output the shape must be 40x40 DEVICE pixels at a distance of 40
 * from the window's own corner, which is what `check_hidpi.py` asserts against the compositor's photograph.
 *
 *   appkit_hidpi [--seconds N] [--x X] [--y Y] [--width W] [--height H]
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_draws;

/* **A VIEW THAT FILLS ITSELF WHITE AND PUTS ONE RED SQUARE AT A KNOWN POINT.** White because the checker has to be able
 * to say "the window is here" without knowing what the compositor's desktop looks like, and one square because one
 * measurement is enough: its DISTANCE from the window's corner proves the transform's offset and its SIZE proves the
 * transform's scale. */
@interface AGScaleProbeView : NSView
@end

@implementation AGScaleProbeView

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	g_draws++;
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
	[[NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(20.0, 20.0, 20.0, 20.0)] fill];
}

@end

int main(int argc, char **argv)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGScaleProbeView *view;
		double seconds = 1.0;
		int x = 50, y = 40, width = 200, height = 100;
		int i;

		setvbuf(stdout, NULL, _IONBF, 0);
		for (i = 1; i < argc; i++) {
			if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
				seconds = atof(argv[++i]);
			} else if (strcmp(argv[i], "--x") == 0 && i + 1 < argc) {
				x = atoi(argv[++i]);
			} else if (strcmp(argv[i], "--y") == 0 && i + 1 < argc) {
				y = atoi(argv[++i]);
			} else if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
				width = atoi(argv[++i]);
			} else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
				height = atoi(argv[++i]);
			}
		}
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height)
						     styleMask:NSTitledWindowMask
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_hidpi: NO WINDOW WAS MADE\n");
			return 1;
		}
		view = [[AGScaleProbeView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height)];
		[window setContentView:view];
		[window setFrameOrigin:NSMakePoint((CGFloat)x, (CGFloat)y)];
		[window orderFront:nil];
		[window makeKeyAndOrderFront:nil];

		/* THE SCALE THIS CLIENT DECIDED ON, printed so a failure says whether the window was told the right number or
		 * drew the right number. */
		printf("appkit_hidpi: window %dx%d points at (%d,%d), output scale %g, userSpaceScaleFactor %g\n",
		       width, height, x, y, AGWindowServerScale(AGWindowServerShared()),
		       (double)[window userSpaceScaleFactor]);

		{
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];

			while ([deadline timeIntervalSinceNow] > 0.0) {
				NSEvent *event = [application nextEventMatchingMask:NSAnyEventMask
									  untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
									     inMode:nil
									    dequeue:YES];

				if (event != nil) {
					[application sendEvent:event];
				}
			}
		}
		/* AND ONE LAST FRAME, so the photograph cannot catch a window that never painted after its first configure. */
		[view setNeedsDisplay:YES];
		[window displayIfNeeded];

		printf("appkit_hidpi: drew %d time(s); window frame %gx%g\n", g_draws,
		       (double)[window frame].size.width, (double)[window frame].size.height);
		[view release];
		[window release];
	}
	return 0;
}
