/*
 * appkit_scroll — what a wheel does once it reaches the AppKit: which view gets it, and in what units.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE WHEEL HAD NOWHERE TO GO.** The seam delivered keys, motion and buttons, and a scroll had no event type at
 * all — so `wl_pointer.axis` reached the platform and stopped there. `-scrollWheel:` existed on `NSResponder` and
 * was never called by anything. Two claims are made here, and they are separate claims:
 *
 *   1. **IT GOES WHERE THE POINTER IS, LIKE A CLICK AND UNLIKE A KEY**, through `-hitTest:` — so scrolling a list
 *      works without the list being key or the window in front.
 *   2. **THE UNITS AND SIGNS ARE DECIDED ONCE.** The seam carries the compositor's distance, where one wheel notch
 *      is 15.0 and a finger's movement is a fraction of one; Cocoa's `-deltaX`/`-deltaY` count in wheel LINES, one
 *      per notch, and their positive sense is the OPPOSITE of the protocol's. Both conversions happen at the seam,
 *      and the checks below pin each side of them: a notch is one line, a finger's fraction is a fraction of a line,
 *      and a scroll DOWN is a NEGATIVE `-deltaY`.
 *
 * **AND A WHEEL IS NOT A PRESS.** It must not make the window key, must not activate the application and must not
 * raise anything — checked here, because the dispatch path it rides is the mouse family's and the cheapest way to
 * get this wrong is to inherit the click's window management with it.
 *
 * **THE FIXTURE IS THE SEAM'S OWN EVENT**, exactly as `appkit_events.m` builds its keys: `AGEvent` is public, the
 * door is the one a real compositor calls, and everything after it is the application's own code.
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

@interface NSWindow (AGEventTestDoor)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
@end

static int g_checks;
static int g_failed;

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

/* A VIEW THAT RECORDS THE WHEEL IT WAS SENT. The numbers are kept as well as the count: the whole point of the case
 * is that a notch arrives as one line and that the sign is Cocoa's, so a counter alone would not be a measurement. */
@interface AGScrollingView : NSView
{
@public
	int scrolls;
	CGFloat lastDeltaX;
	CGFloat lastDeltaY;
	CGFloat totalDeltaY;
}
@end

@implementation AGScrollingView

- (void)scrollWheel:(NSEvent *)event
{
	scrolls++;
	lastDeltaX = [event deltaX];
	lastDeltaY = [event deltaY];
	totalDeltaY += [event deltaY];
}

@end

/* AND ONE THAT DECLINES IT, so the bubbling path is measured rather than assumed: `NSResponder`'s default forwards
 * to the next responder, which is what a control that does not scroll relies on. */
@interface AGDeafView : NSView
@end

@implementation AGDeafView
@end

/* THE SEAM'S EVENT, with the fields the platform fills in for a scroll. */
static AGEvent axis_event(uint32_t axis, double delta, uint32_t source, int32_t discrete, int32_t value120,
			  int x, int y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerAxis;
	event.axis = axis;
	event.delta = delta;
	event.source = source;
	event.discrete = discrete;
	event.value120 = value120;
	event.has_discrete = (value120 != 0 || discrete != 0);
	event.x = x;
	event.y = y;
	return event;
}

/* ONE EVENT THROUGH THE SEAM'S DOOR, THEN THE APPLICATION'S OWN PUMP AND DISPATCH — the path a real wheel takes. */
static void deliver(NSApplication *application, NSWindow *window, const AGEvent *event)
{
	NSDate *deadline;

	[window cg_handleSeamEvent:event];
	deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
	for (;;) {
		NSEvent *built = [application nextEventMatchingMask:NSAnyEventMask
							 untilDate:deadline
							    inMode:nil
							   dequeue:YES];

		if (built == nil) {
			break;
		}
		[application sendEvent:built];
		if ([built type] == NSScrollWheel || [built type] == NSKeyDown) {
			break;	/* ONE EVENT PER CALL, so each assertion is about one gesture */
		}
	}
}

/* THE SEAM MEASURES y DOWN FROM THE TOP OF THE FRAME; Cocoa's content view measures up from the bottom. */
static int seam_y(NSWindow *window, CGFloat contentY)
{
	return (int)([window frame].size.height - contentY);
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGScrollingView *left;
		AGScrollingView *right;
		AGDeafView *deaf;
		AGEvent event;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 400.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_scroll: NO WINDOW WAS MADE\n");
			return 1;
		}
		[window orderFront:nil];
		/* LET THE COMPOSITOR CONFIGURE IT, because the seam's coordinates are the frame's. */
		{
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];

			while ([deadline timeIntervalSinceNow] > 0.0) {
				NSEvent *e = [application nextEventMatchingMask:NSAnyEventMask
								      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
									 inMode:nil
									dequeue:YES];

				if (e != nil) {
					[application sendEvent:e];
				}
			}
		}

		/* **TWO SCROLLING VIEWS SIDE BY SIDE**, so "it went to the one under the pointer" is a measurement rather
		 * than an assumption about there being only one candidate. */
		left = [[AGScrollingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 400.0)];
		right = [[AGScrollingView alloc] initWithFrame:NSMakeRect(320.0, 0.0, 320.0, 400.0)];
		deaf = [[AGDeafView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 100.0)];

		[window setContentView:left];
		[left addSubview:right];
		[right addSubview:deaf];

		/* ============================================================================================
		 * 1. A NOTCH DOWN IS ONE LINE, NEGATIVE.
		 * ============================================================================================ */
		event = axis_event(AGAxisVertical, 15.0, AGAxisSourceWheel, 1, 120, 100,
				   seam_y(window, 300.0));	/* over `left` */
		deliver(application, window, &event);
		check(left->scrolls == 1, "a wheel notch reaches the view under the pointer");
		check(left->lastDeltaY == -1.0, "as ONE line, negative for a scroll DOWN");
		check(left->lastDeltaX == 0.0, "with no horizontal delta on a vertical gesture");

		/* ============================================================================================
		 * 2. THE SIGN AND THE AXIS: a horizontal notch is a horizontal line, and its sense is the other one.
		 * ============================================================================================ */
		event = axis_event(AGAxisHorizontal, 30.0, AGAxisSourceWheel, 2, 240, 100,
				   seam_y(window, 300.0));
		deliver(application, window, &event);
		check(left->scrolls == 2, "a horizontal notch reaches it too");
		check(left->lastDeltaX == -2.0, "two notches as TWO lines, negative for a scroll RIGHT");
		check(left->lastDeltaY == 0.0, "and no vertical delta on a horizontal gesture");

		/* ============================================================================================
		 * 3. A FINGER HAS NO STEPS, AND ITS DISTANCE IS A FRACTION OF A LINE.
		 * ============================================================================================ */
		event = axis_event(AGAxisVertical, 7.5, AGAxisSourceFinger, 0, 0, 100, seam_y(window, 300.0));
		deliver(application, window, &event);
		check(left->scrolls == 3, "a trackpad gesture is delivered as a scroll");
		check(left->lastDeltaY == -0.5, "half a notch being half a line, not one click");

		/* ============================================================================================
		 * 4. IT IS ROUTED BY HIT TEST, NOT BY WHO IS KEY.
		 * ============================================================================================ */
		{
			int right_before = right->scrolls;
			int left_before = left->scrolls;

			event = axis_event(AGAxisVertical, 15.0, AGAxisSourceWheel, 1, 120, 480,
					   seam_y(window, 300.0));	/* over `right` */
			deliver(application, window, &event);
			check(right->scrolls == right_before + 1, "a scroll over the RIGHT view goes to it");
			check(left->scrolls == left_before, "and NOT to the content view that is merely the window's");
		}

		/* ============================================================================================
		 * 5. A VIEW THAT DOES NOT IMPLEMENT IT BUBBLES, through `NSResponder`'s own forwarding.
		 * ============================================================================================ */
		{
			int right_before = right->scrolls;

			event = axis_event(AGAxisVertical, 15.0, AGAxisSourceWheel, 1, 120, 480,
					   seam_y(window, 50.0));	/* over `deaf`, inside `right` */
			deliver(application, window, &event);
			check(right->scrolls == right_before + 1,
			      "a view that does not take the wheel passes it UP the responder chain");
		}

		/* ============================================================================================
		 * 6. AND A WHEEL IS NOT A PRESS: no activation, no key window, no raise.
		 * ============================================================================================ */
		{
			[application deactivate];
			[window resignKeyWindow];
			check(![application isActive], "the application is inactive before the wheel");
			check(![window isKeyWindow], "and the window is not key");

			event = axis_event(AGAxisVertical, 15.0, AGAxisSourceWheel, 1, 120, 100,
					   seam_y(window, 300.0));
			deliver(application, window, &event);
			check(![application isActive], "a wheel does NOT activate the application");
			check(![window isKeyWindow], "and does NOT make the window key");
		}

		printf("appkit_scroll: %d checks, %d failed%s\n", g_checks, g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");

		[deaf release];
		[right release];
		[left release];
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
