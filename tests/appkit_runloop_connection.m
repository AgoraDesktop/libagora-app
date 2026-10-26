/*
 * appkit_runloop_connection — the compositor's descriptor is one of the run loop's sources.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHAT THIS HOLDS UP, AND WHY IT NEEDS A COMPOSITOR. Until this change the application's loop had TWO waits: the run
 * loop waited on timers and sources, and `-nextEventMatchingMask:` waited on the compositor's descriptor. Neither
 * knew about the other, which is why a timer could not fire while the loop was waiting for input and why the main
 * dispatch queue was dead. The descriptor is now registered with the run loop like any other source, so ONE wait
 * serves both.
 *
 * THE ASSERTION IS CAUSAL, NOT COSMETIC. A VIEW DRAWS ONLY WHEN THE COMPOSITOR ASKS FOR A FRAME: the frame callback
 * arrives on the connection, and `-cg_frameCallback` is what paints. Nothing else in a `-runUntilDate:` wait touches
 * the seam. So the sequence below — mark the view dirty from a timer, then sit in a run-loop wait for half a second
 * WITHOUT pumping events by hand — can only produce a draw if the compositor's frame callbacks were delivered by the
 * RUN LOOP. Before this change it produced zero draws, deterministically.
 *
 * AND THE SECOND HALF IS THE LOOP ITSELF: `-[NSApplication run]` reaches the same wait, so the window still
 * configures and draws, a timer still fires, `-stop:` still ends it, and the seam's own deadline (a held key's
 * repeat) does not starve either.
 *
 * THE RUNNER STARTS A HEADLESS COMPOSITOR, so a machine without one SKIPS (exit 77) rather than failing.
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>

#include "AGWindowServer.h"

#include <stdio.h>

static int g_checks;
static int g_failed;

/* THE TWO COUNTERS THE ASSERTION RESTS ON: how many times the view was painted, and how many seam events the window
 * was handed (a configure, a frame, an enter — any of them prove the connection was serviced). */
static int g_draws;
static int g_seamEvents;
static int g_ticks;
static int g_watchdog;

static void check(int ok, const char *what)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", what);
	} else {
		printf("  [ok]   %s\n", what);
	}
}

@interface AGPaintCountingView : NSView
@end

@implementation AGPaintCountingView

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	g_draws++;
	[[NSColor redColor] set];
	NSRectFill([self bounds]);
}

@end

/* THE WINDOW COUNTS WHAT THE SEAM HANDS IT. `-cg_handleSeamEvent:` is the one door every non-NSEvent arrival goes
 * through (a configure, a close, a reopen, a dock-menu ask), and it is sent by the seam's own C callback — so an
 * override here counts exactly the deliveries that travelled over the connection. */
@interface AGCountingWindow : NSWindow
@end

@interface NSWindow (AGSeamEventDoor)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
@end

@implementation AGCountingWindow

- (void)cg_handleSeamEvent:(const AGEvent *)event
{
	g_seamEvents++;
	[super cg_handleSeamEvent:event];
}

@end

@interface AGDriver : NSObject
{
@public
	NSView *view;
}
- (void)tick:(NSTimer *)timer;
- (void)markDirty:(NSTimer *)timer;
- (void)stop:(NSTimer *)timer;
- (void)watchdog:(NSTimer *)timer;
@end

@implementation AGDriver

- (void)tick:(NSTimer *)timer
{
	(void)timer;
	g_ticks++;
}

/* A TIMER IS WHAT MAKES THE VIEW STALE DURING A WAIT, and it is the second thing that could only happen if the run
 * loop were awake — so it is a check of its own as well as the setup for the draw. */
- (void)markDirty:(NSTimer *)timer
{
	(void)timer;
	[view setNeedsDisplay:YES];
}

- (void)stop:(NSTimer *)timer
{
	(void)timer;
	[NSApp stop:nil];
}

- (void)watchdog:(NSTimer *)timer
{
	(void)timer;
	g_watchdog = 1;
	[NSApp stop:nil];
}

@end

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		AGCountingWindow *window;
		AGPaintCountingView *view;
		AGDriver *driver = [[AGDriver alloc] init];
		NSTimer *dirty;
		NSTimer *ticks;
		int drawsBefore;

		setvbuf(stdout, NULL, _IONBF, 0);

		[application finishLaunching];

		window = [[AGCountingWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 480.0, 320.0)
							    styleMask:(NSTitledWindowMask | NSClosableWindowMask)
							      backing:NSBackingStoreBuffered
								defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_runloop_connection: NO WINDOW WAS MADE\n");
			return 1;
		}
		view = [[AGPaintCountingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 320.0)];
		[window setContentView:view];
		[window orderFront:nil];
		driver->view = view;

		check([NSWindow cg_connectionFd] >= 0, "the connection answers a descriptor once a window exists");
		check(AGWindowServerGetFd([NSWindow cg_sharedServer]) == [NSWindow cg_connectionFd],
		      "and it is the seam's own descriptor");

		/* ONE PAINT BY HAND, so the compositor has a buffer to release and therefore a frame callback to send. */
		[window display];

		/* ============================================================================================
		 * THE CAUSAL ONE: a run-loop wait, no manual pumping, and a timer that keeps the view stale.
		 * ============================================================================================ */
		g_draws = 0;
		g_seamEvents = 0;
		dirty = [NSTimer scheduledTimerWithTimeInterval:0.01
							 target:driver
						       selector:@selector(markDirty:)
						       userInfo:nil
							repeats:YES];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
		[dirty invalidate];
		drawsBefore = g_draws;

		check(g_seamEvents > 0, "the connection was serviced DURING a run-loop wait");
		check(g_draws > 0, "and the compositor's frame callbacks painted the stale view from that wait");

		/* ============================================================================================
		 * AND THEN THE APPLICATION'S OWN LOOP, which reaches the same wait.
		 * ============================================================================================ */
		ticks = [NSTimer scheduledTimerWithTimeInterval:0.01
							 target:driver
						       selector:@selector(tick:)
						       userInfo:nil
							repeats:YES];
		[NSTimer scheduledTimerWithTimeInterval:0.4
						 target:driver
					       selector:@selector(stop:)
					       userInfo:nil
						repeats:NO];
		[NSTimer scheduledTimerWithTimeInterval:5.0
						 target:driver
					       selector:@selector(watchdog:)
					       userInfo:nil
						repeats:NO];

		g_draws = 0;
		[application run];

		check(g_watchdog == 0, "the application's loop was stopped by the test, not by the watchdog");
		check(g_ticks > 0, "a timer fired inside -[NSApplication run]");
		check(g_draws > 0, "and the window painted inside it, which is the compositor being serviced there too");
		check(![application isRunning], "-run returned after -stop:");
		ticks = nil;
		(void)drawsBefore;

		[window close];
		printf("%s (%d check%s)\n", g_failed ? "FAILURES" : "all checks passed", g_checks,
		       (g_checks == 1) ? "" : "s");
	}
	return g_failed ? 1 : 0;
}
