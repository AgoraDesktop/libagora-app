/*
 * appkit_window — a real NSWindow, drawn by a real NSView, on Agora's window server.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
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
 * **AND IT RESERVES A STRIP AS A DOCK WOULD.** After the window has drawn, a second, borderless window at
 * `NSDockWindowLevel` takes 96 points at the bottom through `-cg_setReservedEdge:amount:` and the test asserts
 * that `-visibleFrame` shrinks by exactly that — then gives it back and asserts it came back. That is the whole
 * of `agora_window.set_reserved` seen from AppKit: the number a Dock has to be able to say, and the number
 * `-constrainFrameRect:toScreen:` is checked against.
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
#import <AppKit/NSStatusBar.h>
#import <AppKit/NSStatusItem.h>
#import <AppKit/AGStatusBarItemView.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define EVDEV_KEY_ESC 1

/* HOW MANY POINTS THE DOCK-SHAPED WINDOW BELOW RESERVES, and the number the script's assertions derive from. */
#define DOCK_RESERVE 96

/* ONE PUMP, REACHED FOR BY THE TWO PLACES THAT HAVE TO WAIT FOR THE SERVER TO ANSWER something that is not an
 * ordinary event: the reserve below and the release after it. It is the application's own pump, not the seam's. */
static void pump_for(NSTimeInterval interval)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:interval];

	while ([deadline timeIntervalSinceNow] > 0.0) {
		NSEvent *event = [application nextEventMatchingMask:NSAnyEventMask
						  untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
						     inMode:nil
						    dequeue:YES];

		if (event != nil) {
			[application sendEvent:event];
		}
	}
}

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

/* **A VIEW THAT BELONGS TO AN ITEM RATHER THAN TO A WINDOW.** It draws a mark nobody could mistake for the bar: a
 * solid field with three lighter notches. If this lands in the strip then an ITEM'S OWN APPLICATION put it there
 * and the server only decided where — which is the whole rule, made visible. */
#define STATUS_ITEM_LENGTH 96

/* AND A TARGET THAT COUNTS, so "the item's action fired" is a number. */
@interface AGPressTarget : NSObject
{
@public
	int fired;
}
- (void)fired:(id)sender;
@end

@implementation AGPressTarget
- (void)fired:(id)sender
{
	(void)sender;
	fired++;
}
@end

@interface AGStatusItemView : NSView
@end

@implementation AGStatusItemView

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect b = [self bounds];
	CGFloat w = b.size.width;
	CGFloat h = b.size.height;
	int i;

	(void)dirtyRect;
	[[NSColor colorWithCalibratedRed:0.95 green:0.35 blue:0.10 alpha:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:b] fill];
	[[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0] setFill];
	for (i = 0; i < 3; i++) {
		[[NSBezierPath bezierPathWithRect:NSMakeRect(w * (0.20 + 0.24 * i), h * 0.30, w * 0.12,
							     h * 0.40)] fill];
	}
}

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

		/* **AND A STRIP RESERVED THE WAY A DOCK RESERVES ONE, THEN GIVEN BACK.** Everything about this is invisible in
		 * the screenshot — no pixel moves and no window moves — so the assertion is the NUMBER `-visibleFrame`
		 * answers. Both directions are checked: a reservation that never arrives and one that never lifts are two
		 * different bugs, and a cache that is only written once would pass a test that asked only the first. */
		{
			NSScreen *screen = [NSScreen mainScreen];
			NSRect before = [screen visibleFrame];
			NSWindow *dock;
			NSRect reserved;
			NSRect released;

			/* **ONLY A COMPOSITOR THAT RESERVES ANYTHING CAN MOVE A WORK AREA.** The other runner for this test
			 * uses a stock headless compositor, whose `-visibleFrame` IS the frame because it owns no furniture
			 * and has no door for a reservation — so there is nothing to move and pretending otherwise would
			 * fail a correct stack. The Agora runner asserts that these lines are PRESENT, so this skip cannot
			 * hide a reservation that stopped working there. */
			if (before.size.height >= [screen frame].size.height) {
				fprintf(stderr, "appkit_dock: skipped — this compositor reserves no furniture, so a reservation "
					"has no work area to move\n");
			} else {
				dock = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, before.size.width, DOCK_RESERVE)
								  styleMask:NSBorderlessWindowMask
								    backing:NSBackingStoreBuffered
								      defer:NO];
				/* THE LEVEL IS THE POINT: this is a DOCK-shaped window, not an ordinary one, and the level is
				 * the only thing that says so — the server orders by the integer and a reservation is not a
				 * special case for it. */
				[dock setLevel:NSDockWindowLevel];
				[dock orderFront:nil];
				[dock cg_setReservedEdge:NSMinYEdge amount:DOCK_RESERVE];
				pump_for(0.3);
				reserved = [screen visibleFrame];
				fprintf(stderr, "appkit_dock: %gx%g -> %gx%g at (%g,%g) with %d reserved at the bottom\n",
					(double)before.size.width, (double)before.size.height,
					(double)reserved.size.width, (double)reserved.size.height,
					(double)reserved.origin.x, (double)reserved.origin.y, DOCK_RESERVE);
				if (reserved.size.height != before.size.height - DOCK_RESERVE
				    || reserved.size.width != before.size.width
				    || reserved.origin.y != before.origin.y + DOCK_RESERVE) {
					fprintf(stderr, "appkit_dock: THE RESERVATION DID NOT SHRINK THE WORK AREA\n");
					return 1;
				}
				/* AND THE WINDOW ITSELF DID NOT MOVE: `-visibleFrame` is a fact about the SCREEN, and a
				 * reservation is not a frame. This is the one line that keeps the two questions apart. */
				if ([dock frame].origin.x != 0.0 || [dock frame].origin.y != 0.0) {
					fprintf(stderr, "appkit_dock: THE RESERVING WINDOW WAS MOVED\n");
					return 1;
				}

				[dock cg_setReservedEdge:NSMinYEdge amount:0];
				pump_for(0.3);
				released = [screen visibleFrame];
				fprintf(stderr, "appkit_dock: released -> %gx%g at (%g,%g)\n", (double)released.size.width,
					(double)released.size.height, (double)released.origin.x, (double)released.origin.y);
				if (!NSEqualRects(released, before)) {
					fprintf(stderr, "appkit_dock: THE WORK AREA DID NOT COME BACK\n");
					return 1;
				}
				[dock close];
				[dock release];
				pump_for(0.1);
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
			/* **AND THE SECOND DOOR ONTO THE SAME NUMBER.** `NSStatusBar -thickness` is the menu bar's height,
			 * which is exactly what `-visibleFrame` leaves out — the WindowServer's answer arriving twice by two
			 * routes. If they ever disagree one of them is wrong, and this is the cheapest place to find out. */
			{
				NSStatusBar *bar = [NSStatusBar systemStatusBar];
				NSStatusItem *item;
				CGFloat reserved = whole.size.height - work.size.height;

				fprintf(stderr, "appkit_status: the bar is %g tall, against a reserve of %g\n",
					(double)[bar thickness], (double)reserved);
				if (reserved > 0.0 && [bar thickness] != reserved) {
					fprintf(stderr, "appkit_status: THE TWO DOORS ONTO THE RESERVE DISAGREE\n");
					return 1;
				}
				item = [bar statusItemWithLength:STATUS_ITEM_LENGTH];
				fprintf(stderr, "appkit_status: an item asked for as %d reads back as %g, its bar is %g\n",
					STATUS_ITEM_LENGTH, (double)[item length],
					(double)[[item statusBar] thickness]);
				if ([item length] != (CGFloat)STATUS_ITEM_LENGTH) {
					fprintf(stderr, "appkit_status: AN ITEM'S LENGTH DID NOT SURVIVE\n");
					return 1;
				}
				/* **AND A VIEW, WHICH IS WHAT MAKES IT VISIBLE.** The server places the item; what is drawn in it
				 * is the application's. This is the last inch of that rule and the reason the screenshot has
				 * something in the strip to look at. */
				{
					AGStatusItemView *mark = [[AGStatusItemView alloc] initWithFrame:
						NSMakeRect(0.0, 0.0, (CGFloat)STATUS_ITEM_LENGTH,
							   [bar thickness])];

					[item setView:mark];
					[mark release];
				}
				/* **AND THE FIVE GATE DOORS, ON AN ITEM THE APPLICATION GAVE NO VIEW.** An item with no view of the
				 * application's DRAWS ITSELF — that is what makes `-isEnabled`, `-sendActionOn:` and the tooltip reachable at
				 * all: they are obeyed by the view the item makes, not stored. The mask door answers the mask it REPLACED,
				 * which is Apple's signature and the only reading under which the answer is useful. */
				{
					NSStatusItem *selfDrawn = [bar statusItemWithLength:24.0];
					NSInteger previous;

					/* **THE VIEW COMES WITH THE WINDOW, AND THE WINDOW NEEDS A STRIP.** With no bar thickness there is no
					 * screen to put an item on — the run above measures that as a reserve of 0 — so the two claims that
					 * need a view are made only when there is one; the item's own doors are checked either way. */
					fprintf(stderr, "appkit_status: a self-drawn item's view is %s, enabled %d\n",
						[selfDrawn view] != nil ? "present" : "ABSENT",
						(int)[selfDrawn isEnabled]);
					if ([bar thickness] > 0.0 && [selfDrawn view] == nil) {
						fprintf(stderr, "appkit_status: AN ITEM WITH NO VIEW DID NOT MAKE ONE\n");
						return 1;
					}
					if (![selfDrawn isEnabled]) {
						fprintf(stderr, "appkit_status: A FRESH ITEM IS NOT ENABLED\n");
						return 1;
					}
					previous = [selfDrawn sendActionOn:NSLeftMouseDownMask];
					fprintf(stderr, "appkit_status: the action mask was %ld and is now %ld\n",
						(long)previous, (long)[selfDrawn sendActionOn:NSLeftMouseUpMask]);
					if (previous != (NSInteger)NSLeftMouseUpMask) {
						fprintf(stderr, "appkit_status: THE DEFAULT MASK IS NOT THE RELEASE\n");
						return 1;
					}
					[selfDrawn setToolTip:@"A status item"];
					if (![[selfDrawn toolTip] isEqualToString:@"A status item"]) {
						fprintf(stderr, "appkit_status: THE TOOLTIP DID NOT ROUND-TRIP\n");
						return 1;
					}
					if ([selfDrawn view] != nil && ![[[selfDrawn view] toolTip] isEqualToString:@"A status item"]) {
						fprintf(stderr, "appkit_status: THE TOOLTIP DID NOT REACH THE VIEW\n");
						return 1;
					}
					[selfDrawn setEnabled:NO];
					if ([selfDrawn isEnabled]) {
						fprintf(stderr, "appkit_status: A DISABLED ITEM STILL READS ENABLED\n");
						return 1;
					}
					/* AND A TITLE, WHICH IS WHAT THE VIEW DRAWS WHEN IT IS NOT A PICTURE. Nothing here can read the
					 * strip's pixels, so the claim is that the item accepts one and still has a view to draw it. */
					[selfDrawn setTitle:@"Item"];
					if (![[selfDrawn title] isEqualToString:@"Item"]) {
						fprintf(stderr, "appkit_status: A TITLED ITEM LOST ITS TITLE\n");
						return 1;
					}
					/* **AND THE ACTION IS ACTUALLY SENT, THROUGH THE VIEW THAT MAKES THE DOORS REAL.** The mask is set
					 * to the PRESS, so the send happens before the press loop's own run-loop guard — which is exactly how
					 * a program with no event source gets a status item's action to fire, and how this probe reaches the
					 * path a pointer would. A DISABLED item then sends nothing through the same press. */
					{
						/* **AND THE VIEW IS BUILT HERE WHEN THE BAR HAS NO STRIP**, because the send path is the claim and
						 * it needs no screen: a view handed the item is the same object the item makes for itself, and the
						 * PRESS mask sends before the loop's own run-loop guard. */
						AGStatusBarItemView *face = [selfDrawn view] != nil
							? (AGStatusBarItemView *)[selfDrawn view]
							: [[[AGStatusBarItemView alloc] initWithStatusItem:selfDrawn
												  frame:NSMakeRect(0.0, 0.0, 24.0, 22.0)] autorelease];
						AGPressTarget *watcher = [[AGPressTarget alloc] init];
						NSEvent *press = [NSEvent mouseEventWithType:NSLeftMouseDown
										    location:NSMakePoint(5.0, 5.0)
									       modifierFlags:0
										   timestamp:0.0
										windowNumber:0
										     context:nil
										 eventNumber:1
										  clickCount:1
										    pressure:1.0];

						[selfDrawn setTarget:watcher];
						[selfDrawn setAction:@selector(fired:)];
						[selfDrawn sendActionOn:NSLeftMouseDownMask];
						[selfDrawn setEnabled:YES];
						[face mouseDown:press];
						fprintf(stderr, "appkit_status: a press on the item fired its action %d time(s)\n",
							watcher->fired);
						if (watcher->fired != 1) {
							fprintf(stderr, "appkit_status: THE ITEM'S ACTION DID NOT FIRE ON THE PRESS\n");
							return 1;
						}
						[selfDrawn setEnabled:NO];
						[face mouseDown:press];
						if (watcher->fired != 1) {
							fprintf(stderr, "appkit_status: A DISABLED ITEM STILL SENT ITS ACTION\n");
							return 1;
						}
						[watcher release];
					}
					[bar removeStatusItem:selfDrawn];
				}
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
