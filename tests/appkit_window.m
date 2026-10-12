/*
 * appkit_window — a real NSWindow, drawn by a real NSView, on Agora's window server.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * WHAT THIS IS FOR. `tests/window.c` drives the SEAM. This drives APPkit: it makes an `NSWindow`, gives it an
 * `NSView` that overrides `-drawRect:`, orders it front and pumps events — so a passing run means the whole
 * chain works, from a view's drawing out through the window, the backing store and the compositor to a real
 * screen.
 *
 * WHAT IT DRAWS, and why those shapes: an R gradient rising left to right and a G gradient rising top to
 * bottom prove the pixels are this view's AND that they are the right way up, because Core Graphics' origin is
 * bottom-left and the frame buffer's first row is the top; a RED square at the TOP-left of the screen and a
 * GREEN one at the BOTTOM-right prove the size and the orientation together; and a bar that moves with the
 * clock can only move if the compositor keeps asking for frames.
 *
 *   appkit_window [--seconds N] [--width W] [--height H]
 *
 * It exits 0 after N seconds (default 3), and prints what it saw so a headless run can assert on it.
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSScreen.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define EVDEV_KEY_ESC 1

/* HOW MANY TIMES THE VIEW WAS ASKED TO DRAW. This is the assertion: `-drawRect:` is reached only through the
 * seam's frame callback, which fires only after the compositor has CONFIGURED the window — so a non-zero count
 * means a window was really made, really configured and really painted. */
static int s_draws;

static uint32_t now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint32_t)((uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u);
}

/* ONE VIEW, WHICH DRAWS THE WHOLE PATTERN ITSELF — and it is the only place in this test that knows what the
 * window looks like, which is what makes it an AppKit test rather than a seam test with a view bolted on. */
@interface AGSmokeView : NSView
@end

@implementation AGSmokeView

- (void)fillRect:(NSRect)rect red:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
	[[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:rect] fill];
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect b = [self bounds];
	CGFloat w = b.size.width;
	CGFloat h = b.size.height;
	const int N = 16;
	int row, column;

	(void)dirtyRect;
	s_draws++;
	/* 1. THE GRID: R rises to the right, G rises DOWNWARD. `row` counts SCREEN rows from the top, so the Cocoa
	 *    y is `h - (row + 1) * h / N` — the conversion is written once, here, because a view's coordinates are
	 *    Cocoa's and the assertion is about the screen. */
	for (row = 0; row < N; row++) {
		for (column = 0; column < N; column++) {
			CGFloat red = (CGFloat)(32 + (200 * column) / N) / 255.0;
			CGFloat green = (CGFloat)(40 + (120 * row) / N) / 255.0;

			[self fillRect:NSMakeRect((CGFloat)column * w / N,
						  h - (CGFloat)(row + 1) * h / N,
						  w / N + 1.0, h / N + 1.0)
				   red:red green:green blue:0.35];
		}
	}
	/* 2. THE TWO MARKERS: red at the screen's top-left, green at its bottom-right. */
	[self fillRect:NSMakeRect(0.0, h - 48.0, 48.0, 48.0) red:0.878 green:0.188 blue:0.188];
	[self fillRect:NSMakeRect(w - 48.0, 0.0, 48.0, 48.0) red:0.208 green:0.753 blue:0.290];
	/* 3. THE BAR, whose position is the clock's — nothing else can move it. */
	{
		int bar = (int)(w / 10.0);
		int span = (int)w + bar;
		int x = (int)((now_ms() / 6u) % (uint32_t)(span > 0 ? span : 1)) - bar;

		[self fillRect:NSMakeRect((CGFloat)x, h / 5.0, (CGFloat)bar, h - 2.0 * (h / 5.0))
			   red:1.0 green:1.0 blue:1.0];
	}
}

@end

int main(int argc, char **argv)
{
	int seconds = 3;
	int width = 640;
	int height = 400;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
			seconds = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
			width = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
			height = atoi(argv[++i]);
		} else {
			fprintf(stderr, "usage: %s [--seconds N] [--width W] [--height H]\n", argv[0]);
			return 2;
		}
	}

	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGSmokeView *view;
		NSDate *deadline;
		int events = 0;

		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_window: NO WINDOW WAS MADE\n");
			return 1;
		}
		[window setTitle:@"Agora AppKit"];
		view = [[AGSmokeView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height)];
		[window setContentView:view];
		[window orderFront:nil];

		fprintf(stderr, "appkit_window: ordered front, windowNumber %ld\n", (long)[window windowNumber]);

		/* THE PUMP IS THE APPLICATION'S, not the seam's: that is the point of the test — the events have to
		 * travel through NSApplication and NSWindow to get here. */
		deadline = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds];
		while ([deadline timeIntervalSinceNow] > 0.0) {
			NSEvent *event = [application nextEventMatchingMask:NSAnyEventMask
								  untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
								     inMode:nil
								    dequeue:YES];

			if (event != nil) {
				[application sendEvent:event];
				events++;
			}
		}

		/* **THE WORK AREA, WHICH ONLY A WINDOW SERVER THAT OWNS FURNITURE CAN ANSWER.** `-frame` is what the
		 * screen IS and `-visibleFrame` is what is LEFT of it — the menu bar and the Dock taken out — so this
		 * prints both and refuses only an impossible answer: a work area is never BIGGER than the screen it is
		 * part of. The exact reserve is checked by the script that runs this against Agora's own server, because
		 * a stock compositor has no furniture to subtract and answers the frame. */
		{
			NSScreen *screen = [NSScreen mainScreen];
			NSRect whole = [screen frame];
			NSRect work = [screen visibleFrame];

			fprintf(stderr, "appkit_window: frame %gx%g, visibleFrame %gx%g at (%g,%g)\n",
				(double)whole.size.width, (double)whole.size.height, (double)work.size.width,
				(double)work.size.height, (double)work.origin.x, (double)work.origin.y);
			if (work.size.width > whole.size.width || work.size.height > whole.size.height) {
				fprintf(stderr, "appkit_window: THE WORK AREA IS BIGGER THAN THE SCREEN\n");
				return 1;
			}
		}
		fprintf(stderr, "appkit_window: %d event(s), drew %d frame(s); frame now %gx%g\n", events, s_draws,
			(double)[window frame].size.width, (double)[window frame].size.height);
		if (s_draws == 0) {
			fprintf(stderr, "appkit_window: NO FRAME WAS EVER DRAWN\n");
			return 1;
		}

		[window close];
		[view release];
	}
	return 0;
}
