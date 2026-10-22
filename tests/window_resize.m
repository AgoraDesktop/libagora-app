/*
 * window_resize — does a drag on the frame's EDGE resize the window, and only the edge it took?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A WINDOW THAT CAN BE MOVED BY ITS CHROME AND NOT RESIZED IS HALF A WINDOW.** The move was built first
 * (a press on the bar that misses a button) and the resize is the same gesture on the same handle — so what this
 * asks is the pair of questions that gesture has: DOES THE EDGE MOVE, and DOES THE OPPOSITE ONE STAY WHERE IT WAS.
 * The second is the one a plausible implementation gets wrong, because a size and an origin are two numbers and
 * only one of them is what the hand is holding.
 *
 * HOW IT ASKS. Exactly the way `tests/chrome_buttons.m` does: `AGEvent` is the seam's own public struct, so this
 * builds the pointer events a compositor would have sent and hands them to the window through the seam's private
 * door, then pumps them with the application's own pump. THE PASS IS MADE BY HAND — `-cg_applyPendingResize` — for
 * the reason that test's does it: a resize is applied ONCE PER PASS at the latest pointer, and the pass belongs to a
 * run loop this test is not inside.
 *
 * WHAT IS ASSERTED, each one a way the wiring can be wrong:
 *
 *   1. A drag on the RIGHT edge grows the width by exactly the pointer's travel and does not move the origin.
 *   2. A drag on the LEFT edge grows the width and moves the origin by the SAME amount, the other way — so the
 *      right edge is a constant.
 *   3. The same pair for the BOTTOM and the TOP.
 *   4. A CORNER takes both axes at once.
 *   5. A press in the MIDDLE of the bar still MOVES the window: the bands must not eat the handle.
 *   6. A window whose style mask does not allow resizing does not resize.
 *   7. The DELEGATE is asked — `-windowWillResize:toSize:` — and its answer is the size USED, so a delegate that
 *      refuses by answering the current size leaves the window alone.
 *   8. The MINIMUM size is honoured, and the edge the hand did NOT take still does not move when the clamp bites.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>

#include "AGWindowServer.h"

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

/* THE PRIVATE DOORS, redeclared here: this tree's own pattern for a private contract a second file has to reach. */
@interface NSWindow (AGWindowResizeTestDoor)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
/* **AND WHETHER THE WINDOW IS WAITING TO BE PAINTED**, which is the half of a resize that is not the geometry: a
 * frame change remakes the backing store, so a window that is not marked stale has no buffer at its new size. */
- (BOOL)cg_needsDisplay;
@end

static int g_checks;
static int g_failed;

/* THE MESSAGE CARRIES THE MEASUREMENT, which is this tree's habit and the reason this is variadic: a check that
 * says "want 40" and not what it got is a check that has to be re-run to be read. */
static void check(int ok, const char *fmt, ...)
{
	char text[512];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(text, sizeof text, fmt, ap);
	va_end(ap);
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", text);
	} else {
		printf("  [ok]   %s\n", text);
	}
}

/* **THE DELEGATE THAT IS ASKED, AND THAT CAN REFUSE.** Nothing here is a mock: this is the real
 * `-windowWillResize:toSize:` the drag sends, and the flags are how the test sees it happen. */
@interface AGResizeDelegate : NSObject <NSWindowDelegate>
{
@public
	int asked;
	BOOL refuse;
	NSSize lastProposed;
}
@end

@implementation AGResizeDelegate
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize
{
	asked++;
	lastProposed = frameSize;
	if (refuse) {
		return [sender frame].size;	/* the size it already has, which is how a refusal is spelled */
	}
	return frameSize;
}
@end

static AGEvent pointer_button(uint32_t button, int pressed, int x, int y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerButton;
	event.button = button;			/* BTN_LEFT */
	event.pressed = pressed;
	event.x = x;
	event.y = y;
	return event;
}

static AGEvent pointer_motion(int x, int y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerMotion;
	event.x = x;
	event.y = y;
	return event;
}

static void deliver(NSApplication *application, NSWindow *window, const AGEvent *event)
{
	NSEvent *built;
	NSDate *deadline;

	[window cg_handleSeamEvent:event];
	deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
	while ((built = [application nextEventMatchingMask:NSAnyEventMask
						 untilDate:deadline
						    inMode:nil
						   dequeue:YES]) != nil) {
		[application sendEvent:built];
		if ([built type] != NSFlagsChanged && [built windowNumber] != 0) {
			break;
		}
	}
}

/* **EVERY EVENT IS BUILT FROM THE FRAME AS IT IS WHEN IT IS DELIVERED**, which a resize makes load-bearing rather
 * than tidy: the seam measures y DOWN from the frame's top and a resize changes that top on every pass, so an event
 * built from the frame the drag started on describes a place the edge is no longer at. */
static void deliver_window_point(NSApplication *application, NSWindow *window, NSPoint p, int pressed)
{
	AGEvent e = pointer_button(0x110, pressed, (int)p.x, (int)([window frame].size.height - p.y));

	deliver(application, window, &e);
}

static void deliver_move(NSApplication *application, NSWindow *window, NSPoint p)
{
	AGEvent e = pointer_motion((int)p.x, (int)([window frame].size.height - p.y));

	deliver(application, window, &e);
}

/* THE FRAME'S OWN RECTANGLE IN WINDOW COORDINATES: the content's width, and the content's height plus the chrome's
 * — which is the space every point below is written in. */
static NSSize frame_extent(NSWindow *window)
{
	NSRect content = [window contentRectForFrameRect:[window frame]];

	return NSMakeSize(content.size.width, [window frame].size.height);
}

/* A POINT ON ONE OF THE FRAME'S EDGES, two points inside the band, so a check is asking about the band and not
 * about which side of it a coordinate happens to fall. */
static NSPoint edge_point(NSWindow *window, int which)
{
	NSSize extent = frame_extent(window);
	CGFloat x = extent.width / 2.0;
	CGFloat y = extent.height / 2.0;

	if (which == 1) {
		x = extent.width - 2.0;		/* right */
	} else if (which == 2) {
		x = 2.0;			/* left */
	} else if (which == 3) {
		y = 2.0;			/* bottom */
	} else if (which == 4) {
		y = extent.height - 2.0;	/* top */
	} else if (which == 5) {
		x = extent.width - 2.0;		/* bottom-right corner */
		y = 2.0;
	} else if (which == 6) {
		NSRect content = [window contentRectForFrameRect:[window frame]];

		x = extent.width / 2.0;		/* the middle of the BAR, which is the move's handle */
		y = content.size.height + (extent.height - content.size.height) / 2.0;
	}
	return NSMakePoint(x, y);
}

/* A DRAG: press on an edge, one motion, THE PASS, the release. **THE PASS IS THE APPLICATION'S OWN DOOR**, which
 * is what makes this a test of the whole path rather than of the arithmetic: `-updateWindows` is where a pending
 * resize is applied and where a stale window is painted, and the two belong together — a pass that resized without
 * painting is exactly the bug this test now holds down. */
static void drag_edge(NSApplication *application, NSWindow *window, int which, CGFloat dx, CGFloat dy)
{
	NSPoint from = edge_point(window, which);
	NSPoint to = NSMakePoint(from.x + dx, from.y + dy);

	deliver_window_point(application, window, from, 1);
	deliver_move(application, window, to);
	[application updateWindows];		/* the pass: the aim applied, the window painted */
	deliver_window_point(application, window, to, 0);
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		NSWindow *fixed;
		AGResizeDelegate *delegate;
		NSRect before;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(60.0, 60.0, 300.0, 200.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask |
								NSMiniaturizableWindowMask | NSResizableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "window_resize: NO WINDOW WAS MADE\n");
			return 1;
		}
		[window setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)] autorelease]];
		[window orderFront:nil];

		fixed = [[NSWindow alloc] initWithContentRect:NSMakeRect(400.0, 400.0, 200.0, 120.0)
						    styleMask:(NSTitledWindowMask)
						      backing:NSBackingStoreBuffered
							defer:NO];
		if (fixed != nil) {
			[fixed setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)] autorelease]];
			[fixed orderFront:nil];
		}

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
		printf("window_resize: window %ld, frame %gx%g at (%g,%g)\n", (long)[window windowNumber],
		       (double)[window frame].size.width, (double)[window frame].size.height,
		       (double)[window frame].origin.x, (double)[window frame].origin.y);

		/* 1. THE RIGHT EDGE, WHICH GROWS THE WIDTH AND LEAVES THE ORIGIN ALONE. */
		before = [window frame];
		drag_edge(application, window, 1, 40.0, 0.0);
		printf("  (the right edge +40: %gx%g at (%g,%g))\n", (double)[window frame].size.width,
		       (double)[window frame].size.height, (double)[window frame].origin.x,
		       (double)[window frame].origin.y);
		check(fabs([window frame].size.width - (before.size.width + 40.0)) < 1.5,
		      "a drag on the RIGHT edge grew the width by %g, want 40",
		      (double)([window frame].size.width - before.size.width));
		check([window frame].origin.x == before.origin.x && [window frame].origin.y == before.origin.y,
		      "and only a left or bottom edge moves the ORIGIN — the right edge left it alone");

		/* 1b. **AND A RESIZE MARKS THE WINDOW STALE, WHERE A MOVE DOES NOT.** That asymmetry is the half of this
		 * door that is not geometry, and it is the one that was WRONG: a move changes no surface, so its window
		 * follows the pointer with the buffer it already has — while a RESIZE remakes the backing store, so the
		 * pixels the compositor last saw belong to a store that no longer exists and the window has NO BUFFER AT
		 * ITS NEW SIZE until one is attached. MEASURED before this was fixed: a window dragged by its edge
		 * disappeared for the whole drag, the desktop showing through where it had been, and it came back on the
		 * release because the release was what marked it stale. */
		{
			NSRect f = [window frame];

			[window setNeedsDisplay:NO];
			check(![window cg_needsDisplay], "the window could not be marked clean, so the pair cannot judge");
			[window setFrame:NSMakeRect(f.origin.x, f.origin.y, f.size.width + 30.0, f.size.height)
				 display:NO];
			check([window cg_needsDisplay],
			      "a RESIZE marks the window stale, so it is painted at the size it just took");
			[window setNeedsDisplay:NO];
			[window setFrameOrigin:NSMakePoint(f.origin.x + 10.0, f.origin.y)];
			check(![window cg_needsDisplay],
			      "and a MOVE leaves that alone, because a move changes no surface");
			[window setFrame:f display:NO];
			[window setNeedsDisplay:NO];
		}

		/* 2. THE LEFT EDGE, WHICH MOVES THE ORIGIN BY WHAT IT TAKES FROM THE WIDTH — the right edge is a
		 * constant, and that is the assertion. */
		before = [window frame];
		drag_edge(application, window, 2, -30.0, 0.0);
		printf("  (the left edge -30: %gx%g at (%g,%g), right edge %g)\n", (double)[window frame].size.width,
		       (double)[window frame].size.height, (double)[window frame].origin.x,
		       (double)[window frame].origin.y, (double)NSMaxX([window frame]));
		check(fabs([window frame].size.width - (before.size.width + 30.0)) < 1.5,
		      "a drag on the LEFT edge grew the width by %g, want 30",
		      (double)([window frame].size.width - before.size.width));
		check(fabs([window frame].origin.x - (before.origin.x - 30.0)) < 1.5,
		      "and moved the origin by %g, want -30", (double)([window frame].origin.x - before.origin.x));
		check(fabs(NSMaxX([window frame]) - NSMaxX(before)) < 0.01,
		      "so the RIGHT edge stayed where it was (%g against %g)", (double)NSMaxX([window frame]),
		      (double)NSMaxX(before));

		/* 3. THE BOTTOM AND THE TOP, the same pair on the other axis. */
		before = [window frame];
		drag_edge(application, window, 3, 0.0, -20.0);
		check(fabs([window frame].size.height - (before.size.height + 20.0)) < 1.5,
		      "a drag on the BOTTOM edge grew the height by %g, want 20",
		      (double)([window frame].size.height - before.size.height));
		check(fabs([window frame].origin.y - (before.origin.y - 20.0)) < 1.5,
		      "and moved the origin by %g, want -20", (double)([window frame].origin.y - before.origin.y));
		check(fabs(NSMaxY([window frame]) - NSMaxY(before)) < 0.01, "so the TOP edge stayed where it was");

		before = [window frame];
		drag_edge(application, window, 4, 0.0, 15.0);
		check(fabs([window frame].size.height - (before.size.height + 15.0)) < 1.5,
		      "a drag on the TOP edge grew the height by %g, want 15",
		      (double)([window frame].size.height - before.size.height));
		check([window frame].origin.y == before.origin.y, "and left the origin alone");

		/* 4. A CORNER TAKES BOTH AXES AT ONCE. */
		before = [window frame];
		drag_edge(application, window, 5, 25.0, -25.0);
		printf("  (the bottom-right corner +25,-25: %gx%g at (%g,%g))\n", (double)[window frame].size.width,
		       (double)[window frame].size.height, (double)[window frame].origin.x,
		       (double)[window frame].origin.y);
		check(fabs([window frame].size.width - (before.size.width + 25.0)) < 1.5
		      && fabs([window frame].size.height - (before.size.height + 25.0)) < 1.5,
		      "a drag on a CORNER moved both axes (%gx%g, want +25 on each)",
		      (double)([window frame].size.width - before.size.width),
		      (double)([window frame].size.height - before.size.height));

		/* 5. THE MIDDLE OF THE BAR IS STILL THE MOVE'S. */
		before = [window frame];
		{
			NSPoint from = edge_point(window, 6);
			NSPoint to = NSMakePoint(from.x + 20.0, from.y);

			deliver_window_point(application, window, from, 1);
			deliver_move(application, window, to);
			deliver_window_point(application, window, to, 0);
		}
		check([window frame].size.width == before.size.width
		      && [window frame].size.height == before.size.height,
		      "a drag in the MIDDLE of the bar MOVES the window rather than resizing it");
		check(fabs([window frame].origin.x - (before.origin.x + 20.0)) < 1.5,
		      "and it moved the window by %g, want +20",
		      (double)([window frame].origin.x - before.origin.x));

		/* 6. A WINDOW THAT MAY NOT BE RESIZED DOES NOT. */
		if (fixed != nil) {
			before = [fixed frame];
			drag_edge(application, fixed, 1, 40.0, 0.0);
			check([fixed frame].size.width == before.size.width
			      && [fixed frame].size.height == before.size.height,
			      "a window without NSResizableWindowMask keeps its size (%g of travel did nothing)",
			      (double)([fixed frame].size.width - before.size.width));
		}

		/* 7. THE DELEGATE IS ASKED, AND ITS ANSWER IS THE SIZE USED. */
		delegate = [[AGResizeDelegate alloc] init];
		[window setDelegate:delegate];
		before = [window frame];
		drag_edge(application, window, 1, 40.0, 0.0);
		check(delegate->asked > 0, "a resize drag asks -windowWillResize:toSize:");
		check(fabs([window frame].size.width - (before.size.width + 40.0)) < 1.5,
		      "and a delegate that AGREED gets the size it agreed to");
		delegate->refuse = YES;
		before = [window frame];
		drag_edge(application, window, 1, 40.0, 0.0);
		check(delegate->asked > 1, "and a refusal is asked for too");
		check([window frame].size.width == before.size.width
		      && [window frame].size.height == before.size.height,
		      "a delegate that REFUSED keeps its window as it was (%g of travel did nothing)",
		      (double)([window frame].size.width - before.size.width));

		/* 8. AND THE MINIMUM SIZE, WITH THE OPPOSITE EDGE STILL A CONSTANT. */
		delegate->refuse = NO;
		[window setMinSize:NSMakeSize(200.0, 150.0)];
		before = [window frame];
		drag_edge(application, window, 2, 500.0, 0.0);	/* drag the left edge far to the RIGHT */
		printf("  (the left edge shoved +500 against a 200-point minimum: %g wide, right edge %g)\n",
		       (double)[window frame].size.width, (double)NSMaxX([window frame]));
		check([window frame].size.width >= 199.5, "the MINIMUM size is honoured (%g wide, want no less than 200)",
		      (double)[window frame].size.width);
		check(fabs(NSMaxX([window frame]) - NSMaxX(before)) < 1.5,
		      "and the RIGHT edge stays put while the clamp bites (%g against %g)",
		      (double)NSMaxX([window frame]), (double)NSMaxX(before));

		printf("window_resize: %d checks, %d failed%s\n", g_checks, g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");
		[delegate release];
		if (fixed != nil) {
			[fixed release];
		}
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
