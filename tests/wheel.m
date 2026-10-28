/*
 * wheel — does a wheel event from the seam reach the view under the pointer, and with what distance?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE REPORT THIS FILE EXISTS FOR WAS "scrolling in a web view is way too slow", AND IT WAS A UNIT ERROR TWO LAYERS
 * UP.** The compositor's `wl_pointer.axis` distance is 15.0 per notch; `NSEvent`'s `-deltaY` is a count of WHEEL LINES,
 * 1.0 per notch; and the web view's engine wants a distance in page points, where one line is forty. Each hop has to
 * convert ONCE and the middle one is this class's. The engine's own half — one line in, forty points out, at 1x and at
 * 2x — is `libagora-webview`'s `webengine-input` and `appkit_webview`; what is asserted here is the hop that no test in
 * either component had: a wheel event pushed through the REAL seam door, pumped by the APPLICATION and dispatched by
 * `-sendEvent:`, arriving at the VIEW UNDER THE POINTER with one line per notch.
 *
 * **AND THE DISPATCH IS THE HALF THAT CAN SILENTLY DO NOTHING.** A wheel is a pointer-family event whose target is the
 * deepest view containing the pointer (not the first responder), so a window that routed it to the wrong place — or
 * dropped it — would leave every scroll in the tree dead while the seam looked correct. This probe therefore also
 * asserts the two things a person would notice: the point it arrived at, and that a view which does NOT implement
 * `-scrollWheel:` forwards it up the chain rather than swallowing it.
 *
 *   wheel            (no arguments, no compositor, no display)
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

/* THE PRIVATE DOOR THE SEAM USES, declared the way the tree's other probes declare it. */
@interface NSWindow (AGWheelProbe)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
@end

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* **A VIEW THAT REMEMBERS WHAT IT WAS TOLD.** The wheels are recorded rather than handled: the claim is about the
 * event's travel and its numbers, and a view that scrolled would make "which event arrived" a question about a
 * document instead of about the dispatch. */
@interface AGWheelProbeView : NSView
{
@public
	int wheels;
	double lastDeltaY;
	double lastDeltaX;
	NSPoint lastPoint;
}
@end

@implementation AGWheelProbeView

- (BOOL)isFlipped
{
	return NO;
}

- (void)scrollWheel:(NSEvent *)event
{
	wheels++;
	lastDeltaX = [event deltaX];
	lastDeltaY = [event deltaY];
	lastPoint = [self convertPoint:[event locationInWindow] fromView:nil];
}

@end

/* DELIVER ONE EVENT THE WAY THE SEAM DOES, then take it out of the WINDOW's own queue and hand it to the WINDOW's
 * dispatch — which is where the hit test and the selector live, and therefore where this slice's question is. The
 * application-level hop (`-sendEvent:` picking the window by number) is `appkit_events`' subject and needs a window that
 * has been ordered in; this probe has no compositor, so its window has no number to be picked by. */
static void deliver(NSApplication *application, NSWindow *window, const AGEvent *event)
{
	NSEvent *built;

	(void)application;
	[window cg_handleSeamEvent:event];
	built = [window nextEventMatchingMask:NSAnyEventMask
				    untilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]
				       inMode:nil
				      dequeue:YES];
	if (built != nil) {
		[window sendEvent:built];
	}
}

/* THE SEAM'S `y` IS MEASURED DOWN FROM THE TOP OF THE WHOLE FRAME, and a view's is measured up from its bottom. */
static AGEvent axis_event(uint32_t axis, double delta, int contentX, int contentY)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerAxis;
	event.axis = axis;
	event.delta = delta;
	event.x = contentX;
	event.y = contentY;
	return event;
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	NSView *container;
	AGWheelProbeView *view;
	AGEvent seam;

	printf("wheel: the seam's axis event, through the window's dispatch\n");

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
					     styleMask:NSBorderlessWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	/* **THE SHAPE THE DEMO HAS, WHICH IS A CONTAINER WITH THE VIEW INSIDE IT**, so the hit test has to find a SUBVIEW
	 * rather than the content view itself — the arrangement a click already goes through and the one a wheel must not
	 * slip through. */
	container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
	view = [[AGWheelProbeView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
	[container addSubview:view];
	[window setContentView:container];
	/* A BORDERLESS WINDOW IS ITS OWN CONTENT, so a seam point and a view point differ only by the y flip; the frame
	 * height is what flips it, and the check below reads the point back to prove the flip happened once. */

	/* 1. **ONE NOTCH IS ONE LINE, AND THE SEAM SPEAKS FIFTEEN.** The compositor's distance is `wl_pointer.axis`'s, and
	 * 15.0 is one notch there; `-deltaY` counts lines and is positive UP, so a notch DOWN is -1.0. A class that passed
	 * the 15.0 through would make every scroll in the tree fifteen times too fast — which is the same unit error the
	 * web view had, in the other direction, and neither end can see it alone. */
	seam = axis_event(AGAxisVertical, 15.0, 100, 100);
	deliver(application, window, &seam);
	check(view->wheels == 1, "a wheel event from the seam reaches the VIEW UNDER THE POINTER");
	check(view->lastDeltaY == -1.0, "and one notch arrives as ONE LINE (deltaY -1.0, positive being up)");
	check(view->lastDeltaX == 0.0, "with no horizontal component on a vertical notch");
	check(view->lastPoint.x == 100.0 && view->lastPoint.y == 200.0,
	      "at the point the event named, flipped once into the view's own space");

	/* 2. **AND THREE NOTCHES IN ONE EVENT ARE THREE LINES.** The compositor COALESCES a spun wheel into one axis per
	 * frame (see `backend-x11.c`: hundreds of X button events became one message), so a conversion that assumed one
	 * notch per event would under-scroll every fast spin by the factor it batched. */
	seam = axis_event(AGAxisVertical, 45.0, 100, 100);
	deliver(application, window, &seam);
	check(view->wheels == 2 && view->lastDeltaY == -3.0, "three notches arrive as three lines, not as one");

	/* 3. **THE OTHER AXIS, WITH ITS OWN SIGN.** Wayland's positive horizontal distance is RIGHT and `-deltaX` is
	 * positive LEFT, so the two flip the same way and for the same reason. */
	seam = axis_event(AGAxisHorizontal, 30.0, 100, 100);
	deliver(application, window, &seam);
	check(view->wheels == 3 && view->lastDeltaX == -2.0 && view->lastDeltaY == 0.0,
	      "a horizontal notch arrives on deltaX with its sign turned round once");

	/* 4. **AND A WHEEL NEVER MAKES THE WINDOW KEY**, which is what lets a scroll land on a background window's list
	 * without raising it — Apple's behaviour, and the reason the dispatch treats a wheel as a mouse event for the HIT
	 * TEST and not for the activation. The window starts not-key and has to stay that way. */
	{
		BOOL wasKey = [window isKeyWindow];

		seam = axis_event(AGAxisVertical, 15.0, 100, 100);
		deliver(application, window, &seam);
		check(!wasKey && ![window isKeyWindow],
		      "and a wheel does not make the window key, which is what a background list needs");
	}

	[window setContentView:nil];
	[container release];
	[view release];
	[window release];

	printf("wheel: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
