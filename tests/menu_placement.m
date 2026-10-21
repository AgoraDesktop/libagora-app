/*
 * menu_placement — where a popped-up menu's panel actually goes.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE BUG THIS FILE EXISTS FOR WAS REPORTED AS "right-click menus from the dock are appearing on the left side of
 * the screen".** The Dock's window is 64 points wide at x = 1216, a tile is clicked at about x = 20 IN THAT WINDOW,
 * and the menu opened at x = 20 — because `-popUpMenuPositioningItem:atLocation:inView:` took the point as if it were
 * already in screen coordinates and threw the view away. A menu is placed by its window's FRAME, and a frame is
 * absolute.
 *
 * So the assertions are two conversions and one edge:
 *
 *   1. a point in a view in a window at (900, 100) puts the menu at 900 + x, 100 + y - height;
 *   2. a view that fills its window (the ordinary case, where the two coordinate systems agree) keeps working;
 *   3. and a menu opened at the RIGHT edge is moved left to stay on the screen, because that is where a Dock is.
 *
 * The third needs a screen to clamp against, so it skips when no compositor has described one — the first two are
 * pure arithmetic and run everywhere.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSAutoreleasePool.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* A MENU WITH ONE ROW, because the placement is what this is about and not the contents. */
static NSMenu *oneItemMenu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Test"];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Quit" action:NULL keyEquivalent:@""];

	[menu addItem:item];
	[item release];
	return [menu autorelease];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	NSView *view;
	NSMenu *menu;
	NSRect frame;

	(void)application;
	printf("menu_placement\n");

	/* ---- 1. a window away from the origin puts the menu where the window is --------------- */
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(900.0, 100.0, 200.0, 200.0)
					     styleMask:NSBorderlessWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
	[window setContentView:view];
	menu = oneItemMenu();
	[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(20.0, 30.0) inView:view];
	frame = [menu cg_trackingFrame];
	printf("  window at 900,100; point 20,30 in the view -> menu at %.0f,%.0f %.0fx%.0f\n",
	       (double)frame.origin.x, (double)frame.origin.y, (double)frame.size.width,
	       (double)frame.size.height);
	check(frame.origin.x == 920.0, "the menu's x is the WINDOW's x plus the view's x");
	check(frame.origin.y == 130.0 - frame.size.height, "and its top is the window's y plus the view's y");
	[menu cancelTracking];

	/* ---- 2. and a point in SCREEN coordinates when there is no view ---------------------- */
	menu = oneItemMenu();
	[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(300.0, 400.0) inView:nil];
	frame = [menu cg_trackingFrame];
	check(frame.origin.x == 300.0 && frame.origin.y == 400.0 - frame.size.height,
	      "a nil view means the point is already on the screen");
	[menu cancelTracking];

	/* ---- 3. the right edge, which is where the Dock is ---------------------------------- */
	{
		NSRect screen = [[NSScreen mainScreen] frame];

		if (screen.size.width <= 0.0 || screen.size.height <= 0.0) {
			printf("  [skip] no screen has described itself, so there is no edge to clamp to\n");
		} else {
			NSWindow *edgeWindow = [[NSWindow alloc]
				initWithContentRect:NSMakeRect(NSMaxX(screen) - 64.0, 100.0, 64.0, 400.0)
					  styleMask:NSBorderlessWindowMask
					    backing:NSBackingStoreBuffered
					      defer:NO];
			NSView *edgeView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 64.0, 400.0)];

			[edgeWindow setContentView:edgeView];
			menu = oneItemMenu();
			[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(20.0, 300.0) inView:edgeView];
			frame = [menu cg_trackingFrame];
			printf("  at the right edge: menu at %.0f..%.0f, screen ends at %.0f\n",
			       (double)frame.origin.x, (double)NSMaxX(frame), (double)NSMaxX(screen));
			check(frame.origin.x > NSMaxX(screen) - 200.0,
			      "a menu opened at the right edge is on the RIGHT of the screen, not the left");
			check(NSMaxX(frame) <= NSMaxX(screen) + 0.5,
			      "and it is moved left far enough not to hang off the edge");
			[menu cancelTracking];
			[edgeView release];
			[edgeWindow release];
		}
	}

	[view release];
	[window release];
	[pool release];
	printf("menu_placement: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
