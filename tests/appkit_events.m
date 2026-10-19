/*
 * appkit_events — an event's journey: the seam's `AGEvent`, through `NSWindow`, to the view that should get it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * WHY THIS EXISTS. `tests/appkit_window.m` proves a window appears and paints. It does NOT prove anything
 * arrives at it: the headless compositor has no seat, so a run of that test sees zero events and says so. The
 * input path is the half of the port that was REWRITTEN — the key translation moved out of `XLookupString`
 * into xkbcommon, the event pump out of `XNextEvent` into the seam's callback, and the dispatch out of X's
 * window ids — and it had never been asked a single question.
 *
 * HOW IT ASKS THEM WITHOUT A SEAT. `AGEvent` is the seam's own public struct, so this test builds the events a
 * compositor would have sent and hands them to the window through the seam's private door, then pumps them
 * with the APPLICATION's own pump and dispatches them with `-sendEvent:`. The one link that is not exercised
 * is the compositor calling that door — and that link IS exercised elsewhere, because a headless run reaches
 * `640x422` only by way of a configure event arriving through it.
 *
 * WHAT IS ASSERTED, and each one was a bug or a dead branch before it passed:
 *
 *   1. A key goes to the FIRST RESPONDER and carries its characters.
 *   2. A MODIFIER arrives as `-flagsChanged:` rather than as a key down.
 *   3. A click goes to THE VIEW UNDER THE POINTER, not to the first responder.
 *   4. A view that does not implement the event method BUBBLES it up the responder chain, which is what
 *      `NSResponder`'s forwarding methods are for and what an unwired chain silently swallowed.
 *   5. A move is DELIVERED ONLY TO A WINDOW THAT ASKED FOR IT — the default drops it, and a window that says
 *      `-setAcceptsMouseMovedEvents:YES` (the menu bar and every menu window now do) receives it. Without the
 *      request every move over a menu was thrown away, so a row never highlighted under the pointer.
 *   6. The compositor's close request closes the window.
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

/* THE PRIVATE DOOR THE SEAM CALLS, redeclared here. That is this tree's own pattern for a private contract a
 * second file has to reach — NSWindow.m does it for NSView's cursor doors, for the same reason. */
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

/* A VIEW THAT RECORDS WHAT IT IS SENT. Nothing here is a mock: these are the real callbacks AppKit delivers,
 * and the counters are how the test sees them. */
@interface AGRecordingView : NSView
{
@public
	int keyDowns;
	int keyUps;
	int flagsChangeds;
	int mouseDowns;
	int mouseUps;
	int mouseMoveds;
	NSString *lastCharacters;
	NSUInteger lastModifiers;
	NSPoint lastPoint;
}
@end

@implementation AGRecordingView

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)keyDown:(NSEvent *)event
{
	keyDowns++;
	[lastCharacters release];
	lastCharacters = [[event characters] copy];
	lastModifiers = [event modifierFlags];
}

- (void)keyUp:(NSEvent *)event
{
	(void)event;
	keyUps++;
}

- (void)flagsChanged:(NSEvent *)event
{
	flagsChangeds++;
	lastModifiers = [event modifierFlags];
}

- (void)mouseDown:(NSEvent *)event
{
	mouseDowns++;
	lastPoint = [event locationInWindow];
}

- (void)mouseUp:(NSEvent *)event
{
	(void)event;
	mouseUps++;
}

- (void)mouseMoved:(NSEvent *)event
{
	(void)event;
	mouseMoveds++;
}

- (void)dealloc
{
	[lastCharacters release];
	[super dealloc];
}

@end

/* A VIEW THAT IMPLEMENTS NOTHING, so the event has to BUBBLE: NSResponder's own `-mouseDown:` forwards to
 * `-nextResponder`, and this class is what makes that path the one under test. */
@interface AGPassiveView : NSView
@end

@implementation AGPassiveView
@end

/* ---------------------------------------------------------------------------------------------------
 * the seam's own events, built here and delivered through the private door
 * --------------------------------------------------------------------------------------------------- */

static AGEvent evdev_key(uint32_t code, const char *text, int pressed, int modifier, uint32_t modifiers)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventKey;
	event.keycode = code;
	event.pressed = pressed;
	event.modifier = modifier;
	event.modifiers = modifiers;
	snprintf(event.text, sizeof event.text, "%s", text != NULL ? text : "");
	return event;
}

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

/* DELIVER ONE EVENT: hand it to the window the way the seam does, then run the APPLICATION's own pump and
 * dispatch, so what is being tested is the path a real event takes and not a shortcut into the view. */
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
		/* ONE EVENT PER CALL: the loop is here to drain a configure if one is waiting, not to batch. */
		if ([built type] != NSFlagsChanged && [built windowNumber] != 0) {
			break;
		}
	}
}

/* THE SEAM'S `y` IS MEASURED DOWN FROM THE TOP OF THE WHOLE FRAME, and Cocoa's content view starts at the
 * BOTTOM — so a content point becomes a seam point through the frame's height. Written once, here, for the
 * same reason NSWindow writes it once. */
static AGEvent click_at_content_point(NSWindow *window, CGFloat x, CGFloat y)
{
	return pointer_button(0x110, 1, (int)x, (int)([window frame].size.height - y));
}

/* A MOVE, in the same space the click is built in. There is no button, so the seam sees a plain motion and not
 * a drag. */
static AGEvent motion_at_content_point(NSWindow *window, CGFloat x, CGFloat y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerMotion;
	event.x = (int)x;
	event.y = (int)([window frame].size.height - y);
	return event;
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGRecordingView *content;
		AGRecordingView *inner;
		AGPassiveView *passive;
		AGEvent event;
		int before;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 400.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_events: NO WINDOW WAS MADE\n");
			return 1;
		}
		content = [[AGRecordingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 400.0)];
		[window setContentView:content];
		/* ONE SUBVIEW THAT HANDLES THE EVENT, and one that does not, so bubbling is measurable and not assumed. */
		inner = [[AGRecordingView alloc] initWithFrame:NSMakeRect(10.0, 10.0, 100.0, 50.0)];
		passive = [[AGPassiveView alloc] initWithFrame:NSMakeRect(150.0, 10.0, 100.0, 50.0)];
		[content addSubview:inner];
		[content addSubview:passive];
		[window orderFront:nil];

		/* LET THE COMPOSITOR CONFIGURE IT, because the seam's coordinates are the frame's and the frame is not
		 * its requested size until it has been configured. */
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
		printf("appkit_events: window %ld, frame %gx%g, content %gx%g\n", (long)[window windowNumber],
		       (double)[window frame].size.width, (double)[window frame].size.height,
		       (double)[content frame].size.width, (double)[content frame].size.height);

		/* **THE FIRST RESPONDER IS THE CONTENT VIEW AND NOT THE SUBVIEW THAT WILL BE CLICKED**, which is the
		 * whole point of separating these checks: with the subview as the first responder, a click would reach
		 * it whether or not the window hit-tests, and the check could not tell the two apart. MEASURED — the
		 * first version of this test made that mistake and the hit-test check passed with the hit test REMOVED. */
		[window makeFirstResponder:content];

		/* 1. A KEY GOES TO THE FIRST RESPONDER, with its characters. */
		event = evdev_key(30 /* KEY_A */, "a", 1, 0, 0);
		deliver(application, window, &event);
		check(content->keyDowns == 1, "a key reaches the FIRST RESPONDER");
		check(content->lastCharacters != nil && [content->lastCharacters isEqual:@"a"],
		      "and it carries the character xkbcommon produced");
		event = evdev_key(30, "a", 0, 0, 0);
		deliver(application, window, &event);
		check(content->keyUps == 1, "a key release reaches it too");

		/* 2. A MODIFIER IS `-flagsChanged:`, NOT A KEYSTROKE. */
		before = content->keyDowns;
		event = evdev_key(42 /* KEY_LEFTSHIFT */, "", 1, 1, AGModifierShift);
		deliver(application, window, &event);
		check(content->flagsChangeds == 1, "a MODIFIER arrives as -flagsChanged:");
		check(content->keyDowns == before, "and NOT as a key down");
		check((content->lastModifiers & NSShiftKeyMask) != 0, "and the flag it carries is the shift bit");

		/* **3. A CLICK IS ALSO WINDOW MANAGEMENT: it activates the application, makes the clicked window key and
		 * main, and asks for it to be frontmost.** Deactivating first makes the activation half observable even in
		 * a headless run where the seat has already delivered a keyboard-enter. Before this door was fixed, the
		 * click wrote the application's two ivars and left `-isKeyWindow`/`-isMainWindow` NO. */
		[application deactivate];
		[window resignKeyWindow];
		[window resignMainWindow];
		check(![application isActive], "the application is INACTIVE before the click");
		check(![window isKeyWindow] && ![window isMainWindow], "and the window is neither key nor main");
		event = click_at_content_point(window, 60.0, 30.0);	/* inside `inner` */
		deliver(application, window, &event);
		check(inner->mouseDowns == 1, "a click lands on the SUBVIEW it is over");
		check(content->mouseDowns == 0, "and not on the content view behind it");
		check([application isActive], "and the click ACTIVATES the application");
		check([application keyWindow] == window && [window isKeyWindow],
		      "the clicked window becomes KEY, and the application agrees");
		check([application mainWindow] == window && [window isMainWindow],
		      "and MAIN, through the doors that announce it");

		/* 4. AND A VIEW THAT DOES NOT HANDLE IT BUBBLES UP THE CHAIN. */
		before = content->mouseDowns;
		event = click_at_content_point(window, 200.0, 30.0);	/* inside `passive` */
		deliver(application, window, &event);
		check(content->mouseDowns == before + 1,
		      "a click on a view that does not handle it BUBBLES to its superview");

		/* Release the button the check above left down, so the move below is a MOVE and not a drag. */
		event = pointer_button(0x110, 0, 200, 30);
		deliver(application, window, &event);

		/* 5. A PLAIN MOVE IS DROPPED UNLESS THE WINDOW ASKED FOR IT, and that request is what lets a menu row
		 * light up under the pointer: a window's default is NO, the menu bar and every menu window now say YES,
		 * and before they did, EVERY move over a menu was thrown away — the row never highlighted and a submenu
		 * never opened by hovering. Both halves are asserted, because only the pair catches a tier that dropped
		 * the event for a window that asked, or delivered it for one that did not. */
		before = inner->mouseMoveds;
		event = motion_at_content_point(window, 60.0, 30.0);	/* over `inner` */
		deliver(application, window, &event);
		check(inner->mouseMoveds == before, "a move the window did NOT ask for is dropped");
		[window setAcceptsMouseMovedEvents:YES];
		event = motion_at_content_point(window, 60.0, 30.0);
		deliver(application, window, &event);
		check(inner->mouseMoveds == before + 1, "and a move it DID ask for reaches the view under the pointer");

		/* 6. THE COMPOSITOR'S CLOSE REQUEST CLOSES THE WINDOW. The close is deferred by design — it is acted
		 * on by the pump, not inside the seam's dispatch — so it takes one more pass to be seen. */
		memset(&event, 0, sizeof event);
		event.type = AGEventClose;
		[window cg_handleSeamEvent:&event];
		{
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];

			while ([deadline timeIntervalSinceNow] > 0.0 && [window windowNumber] != -1) {
				NSEvent *e = [application nextEventMatchingMask:NSAnyEventMask
								      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
									 inMode:nil
									dequeue:YES];

				if (e != nil) {
					[application sendEvent:e];
				}
			}
		}
		check([window windowNumber] == -1, "the compositor's close request closes the window");

		printf("appkit_events: %d checks, %d failed%s\n", g_checks, g_failed,
	       g_failed == 0 ? " -- all checks passed" : "");
		[inner release];
		[passive release];
		[content release];
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
