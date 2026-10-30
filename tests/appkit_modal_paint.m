/*
 * appkit_modal_paint — a modal session is a frame, so a view marked for display inside one is painted.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE BUG THIS MEASURES IS AN OPEN PANEL THAT LOOKED FROZEN.** Double-clicking a folder reloads the panel's table —
 * which marks it for display — and nothing painted until the pointer scrolled the table or a click landed somewhere
 * else. The cause was not the panel: `-[NSApplication run]` ends every pass with `-updateWindows` (a window's frame
 * callback declines to draw a window that is not needy, so the run loop is what acts on "needy"), and
 * `-runModalSession:` did not. Every view marked for display inside a modal session — a panel's, a sheet's, an
 * alert's — therefore waited for an unrelated frame.
 *
 * **THE ASSERTION IS CAUSAL AND AGAINST A REAL COMPOSITOR.** After a settling pass (so any paint owed to the window
 * being ordered front has already happened), the view is marked for display and ONE modal pass is run. No event is
 * sent, no frame is pumped by hand, and no timer is involved — so a draw can only come from the pass itself. Before
 * this change the count was zero, deterministically; the headless compositor is supplied by the runner, so a machine
 * without one SKIPS (exit 77).
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>

#include <stdio.h>

static int g_checks;
static int g_failed;
static int g_draws;

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

/* A VIEW THAT COUNTS ITS OWN PAINTS, which is the only thing this case has to know about drawing. */
@interface AGModalPaintView : NSView
@end

@implementation AGModalPaintView

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	g_draws++;
	[[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.6 alpha:1.0] set];
	NSRectFill([self bounds]);
}

@end

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGModalPaintView *view;
		NSModalSession session;
		int drawsBefore;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 420.0, 260.0)
						     styleMask:NSTitledWindowMask
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_modal_paint: NO WINDOW WAS MADE\n");
			return 1;
		}
		view = [[AGModalPaintView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 260.0)];
		[window setContentView:view];
		[window orderFront:nil];
		/* ONE PAINT BY HAND, so the compositor holds a buffer to release and the window is a window and not a request. */
		[window display];

		session = [application beginModalSessionForWindow:window];
		check(session != NULL, "a modal session begins");

		/* SETTLE: the passes that may paint because the window was just ordered front, drained before counting. */
		[application runModalSession:session];
		[application runModalSession:session];
		[application runModalSession:session];

		/* -------------------------------- the one that matters ------------------------------------- */
		drawsBefore = g_draws;
		[view setNeedsDisplay:YES];
		[application runModalSession:session];
		check(g_draws > drawsBefore,
		      "a view marked for display inside a modal pass is PAINTED by that pass, with no event and no frame "
		      "pumped by hand");

		/* AND THE SESSION STILL ENDS THE WAY IT DID, so the paint did not become the only thing a pass does. */
		{
			NSInteger code;

			[application stopModalWithCode:NSOKButton];
			code = [application runModalSession:session];
			check(code == NSOKButton, "and the session still answers the code it was stopped with");
			[application endModalSession:session];
		}

		printf("appkit_modal_paint: %d check(s) failed%s\n", g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");
		[view release];
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
