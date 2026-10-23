/*
 * appkit_dispatch — three dispatch questions the pump answered wrongly: which events a mask selects, whether a
 * compositor's close is allowed to be refused, and whether a key equivalent is offered to the menu bar at all.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHY EACH ONE IS HERE, because each was a real wrong answer rather than a missing feature:
 *
 *   1. **A MASK THAT NAMED ONE EVENT SELECTED ALL OF THEM.** The queue tests read
 *      `(mask & NSAnyEventMask) || (mask & eventBit)`. `NSAnyEventMask` is every bit set, so the FIRST term is
 *      true for any nonzero mask and the second never mattered: a mouse-only peek in a process holding a posted
 *      key-down returned the key-down. Native event tracking, nonblocking dialogs and any loop that polls "has
 *      something happened" all depend on a peek that answers about the events it asked for and leaves the rest
 *      where they are. The discard door and the per-window queue carried the same pattern, so all three are
 *      exercised here — a fix in one of them and not the others is the failure mode worth catching.
 *
 *   2. **A COMPOSITOR'S CLOSE BYPASSED `-windowShouldClose:`.** The seam's close is deferred out of the dispatch
 *      (destroying a window inside libwayland's callback is a use-after-free) and the pump then consumed it with
 *      `-close` — so the same window asked about unsaved changes when its chrome button was clicked and did not
 *      when the shell's `close_window` was used. A veto must hold through either door.
 *
 *   3. **A KEY EQUIVALENT NEVER REACHED THE MENU BAR ON THE ORDINARY ROUTE.** `-sendEvent:` went straight to the
 *      window, so a Command-key menu item only ever fired while a menu was TRACKING. The menu is offered the key
 *      before any window sees it, and a handled event is consumed so the action fires once.
 *
 * HOW IT ASKS. A headless compositor is used for the window, so the window is real and configured; the events are
 * built here, because the compositor has no seat. Everything after the seam's door is the application's own code.
 * A run with no compositor SKIPS (exit 77) through the same runner the other AppKit tests use.
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

/* THE PRIVATE DOOR THE SEAM CALLS, as in `appkit_events.m`. */
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

/* ---------------------------------------------------------------------------------------------------
 * the pieces the three questions need
 * --------------------------------------------------------------------------------------------------- */

/* A FIRST RESPONDER THAT COUNTS KEYSTROKES, because question 3 is "did the responder see a key the menu took".
 * Without it the check could not tell a consumed event from a menu that simply matched nothing. */
@interface AGKeyCountingView : NSView
{
@public
	int keyDowns;
}
@end

@implementation AGKeyCountingView

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)keyDown:(NSEvent *)event
{
	(void)event;
	keyDowns++;
}

@end

/* A DELEGATE THAT ANSWERS THE CLOSE QUESTION AND REMEMBERS BEING ASKED, for question 2 — the answer is the input
 * and the count is what makes "the delegate was consulted" a claim rather than an assumption. */
@interface AGCloseVetoDelegate : NSObject
{
@public
	int asked;
	BOOL answer;
}
@end

@implementation AGCloseVetoDelegate

- (BOOL)windowShouldClose:(id)sender
{
	(void)sender;
	asked++;
	return answer;
}

@end

/* AN ACTION TARGET FOR THE MENU ITEM, for question 3. */
@interface AGMenuTarget : NSObject
{
@public
	int fired;
}
@end

@implementation AGMenuTarget

- (void)fire:(id)sender
{
	(void)sender;
	fired++;
}

@end

static NSEvent *posted_key(NSString *characters)
{
	return [NSEvent keyEventWithType:NSKeyDown
				location:NSZeroPoint
			   modifierFlags:0
			       timestamp:0
			    windowNumber:0
				 context:nil
			      characters:characters
	     charactersIgnoringModifiers:characters
			       isARepeat:NO
				 keyCode:30];
}

static NSEvent *posted_mouse(void)
{
	return [NSEvent mouseEventWithType:NSLeftMouseDown
				  location:NSZeroPoint
			     modifierFlags:0
				 timestamp:0
			      windowNumber:0
				   context:nil
			       eventNumber:0
				clickCount:1
				  pressure:1.0];
}

/* PEEK: the door under test, with a deadline that has already passed so it never waits. */
static NSEvent *peek(NSApplication *application, NSUInteger mask, BOOL dequeue)
{
	return [application nextEventMatchingMask:mask
				       untilDate:[NSDate distantPast]
					  inMode:nil
					 dequeue:dequeue];
}

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

/* DRAIN THE WINDOW'S OWN QUEUE INTO THE APPLICATION'S DISPATCH, for the close case: the close is deferred by the
 * seam and acted on by the pump, so the pump has to run before anything can be said about it. */
static void pump(NSApplication *application, double seconds)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];

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

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGKeyCountingView *content;
		AGCloseVetoDelegate *veto;
		AGMenuTarget *target;
		NSMenu *menu;
		NSMenuItem *item;
		NSEvent *event;
		NSEvent *first;
		NSEvent *second;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 400.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_dispatch: NO WINDOW WAS MADE\n");
			return 1;
		}
		content = [[AGKeyCountingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 400.0)];
		[window setContentView:content];
		[window orderFront:nil];
		[window makeFirstResponder:content];
		/* LET THE COMPOSITOR CONFIGURE IT before anything is claimed about it. */
		pump(application, 1.0);

		/* ============================================================================================
		 * 1. THE QUEUE'S MASKS
		 * ============================================================================================ */

		/* A ZERO MASK SELECTS NOTHING, and it must not consume the event either. */
		[application postEvent:posted_key(@"a") atStart:NO];
		check(peek(application, 0, NO) == nil, "a ZERO mask selects nothing");
		check(peek(application, 0, YES) == nil, "and dequeuing with it takes nothing");
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [event type] == NSKeyDown,
		      "the key posted before those peeks is still there, in order");

		/* A PEEK THAT DOES NOT MATCH RETURNS NIL AND LEAVES EVERYTHING ALONE — the reported bug, exactly: a
		 * mouse-only peek used to return the key-down. */
		[application postEvent:posted_key(@"b") atStart:NO];
		check(peek(application, NSLeftMouseDownMask, NO) == nil,
		      "a MOUSE-ONLY peek returns nil rather than the key-down in the queue");
		check(peek(application, NSLeftMouseDownMask, YES) == nil,
		      "and dequeuing with it takes nothing");
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [[event characters] isEqual:@"b"],
		      "the key it did not ask for is still queued, unchanged");

		/* A MIXED QUEUE: peeking the middle event twice must return it twice, take nothing, and leave the order
		 * alone — that is what "not dequeuing means not taking" buys a tracking loop. */
		[application postEvent:posted_key(@"c") atStart:NO];
		[application postEvent:posted_mouse() atStart:NO];
		[application postEvent:posted_key(@"d") atStart:NO];
		first = peek(application, NSLeftMouseDownMask, NO);
		second = peek(application, NSLeftMouseDownMask, NO);
		check(first != nil && [first type] == NSLeftMouseDown, "a mixed queue yields the event the mask names");
		check(first == second, "and a repeated peek yields the SAME event, because neither took it");
		event = peek(application, NSLeftMouseDownMask, YES);
		check(event == first, "dequeuing then takes exactly that one");
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [[event characters] isEqual:@"c"], "the key before it is still ahead, in order");
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [[event characters] isEqual:@"d"], "and the key after it follows");

		/* `atStart:` IS AN ORDERING CLAIM, so it is checked as one. */
		[application postEvent:posted_key(@"e") atStart:NO];
		[application postEvent:posted_key(@"f") atStart:YES];
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [[event characters] isEqual:@"f"], "`atStart:YES` puts the event in FRONT");
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [[event characters] isEqual:@"e"], "and the one posted before it follows");

		/* DISCARD KEEPS WHAT THE MASK DID NOT NAME. The discard door had the same `mask & NSAnyEventMask` pattern,
		 * so a mouse-only discard used to empty the whole queue. */
		[application postEvent:posted_key(@"g") atStart:NO];
		[application postEvent:posted_mouse() atStart:NO];
		[application postEvent:posted_key(@"h") atStart:NO];
		[application discardEventsMatchingMask:NSLeftMouseDownMask beforeEvent:nil];
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [[event characters] isEqual:@"g"], "a mouse-only discard keeps the first key");
		event = peek(application, NSAnyEventMask, YES);
		check(event != nil && [[event characters] isEqual:@"h"], "and keeps the second, having dropped only the mouse");

		/* **AND THE PER-WINDOW QUEUE, WHICH IS A DIFFERENT QUEUE WITH THE SAME BUG.** The event is handed to the
		 * window's own door and NOT pumped, so it is sitting in the window when the application is asked; the
		 * application's peek must decline it and the window's must answer with it. */
		{
			AGEvent key = evdev_key(30 /* KEY_A */, "i", 1, 0, 0);

			[window cg_handleSeamEvent:&key];
			check(peek(application, NSLeftMouseDownMask, NO) == nil,
			      "an application peek that does not match leaves a WINDOW's queued key alone");
			event = peek(application, NSAnyEventMask, YES);
			check(event != nil && [event type] == NSKeyDown,
			      "and the application's all-events peek collects it");
			check(content->keyDowns == 0, "though it has not been DISPATCHED yet — the peek is not a dispatch");
			[application sendEvent:event];
			check(content->keyDowns == 1, "and dispatching it reaches the first responder");
		}

		/* ============================================================================================
		 * 2. THE COMPOSITOR'S CLOSE AND THE VETO
		 * ============================================================================================ */
		{
			AGEvent close;
			int before = content->keyDowns;

			memset(&close, 0, sizeof close);
			close.type = AGEventClose;
			veto = [[AGCloseVetoDelegate alloc] init];
			veto->answer = NO;
			[window setDelegate:(id)veto];
			[window cg_handleSeamEvent:&close];
			pump(application, 0.5);
			check(veto->asked == 1, "the compositor's close asks the delegate");
			check([window windowNumber] != -1, "and a NO from it KEEPS the window");
			check([window isVisible], "which is still visible");

			/* AND A WINDOW THAT REFUSED STILL WORKS: a refused close must not leave the window half-closed. */
			{
				AGEvent key = evdev_key(30, "j", 1, 0, 0);

				[window cg_handleSeamEvent:&key];
				pump(application, 0.5);
				check(content->keyDowns == before + 1, "and it still takes input afterwards");
			}

			/* A YES CLOSES IT, through the same door. */
			veto->answer = YES;
			[window cg_handleSeamEvent:&close];
			pump(application, 0.5);
			check(veto->asked == 2, "the second close asks again, because the answer is not cached");
			check([window windowNumber] == -1, "and a YES closes it");
		}

		/* A FRESH WINDOW FOR THE MENU QUESTION, since the last one is closed. */
		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 400.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		content = [[AGKeyCountingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 400.0)];
		[window setContentView:content];
		[window orderFront:nil];
		[window makeFirstResponder:content];
		pump(application, 1.0);

		/* ============================================================================================
		 * 3. THE MAIN MENU'S KEY EQUIVALENT ON THE ORDINARY DISPATCH ROUTE
		 * ============================================================================================ */
		target = [[AGMenuTarget alloc] init];
		menu = [[NSMenu alloc] initWithTitle:@"Main"];
		item = [[NSMenuItem alloc] initWithTitle:@"Probe" action:@selector(fire:) keyEquivalent:@"n"];
		[item setKeyEquivalentModifierMask:NSCommandKeyMask];
		[item setTarget:target];
		[item setEnabled:YES];
		[menu addItem:item];
		[application setMainMenu:menu];

		event = [NSEvent keyEventWithType:NSKeyDown
					 location:NSZeroPoint
				    modifierFlags:NSCommandKeyMask
					timestamp:0
				     windowNumber:(NSInteger)[window windowNumber]
					  context:nil
				       characters:@"n"
		      charactersIgnoringModifiers:@"n"
				  isARepeat:NO
				    keyCode:45 /* KEY_N */];
		[application sendEvent:event];
		check(target->fired == 1, "Command-N fires the main menu's item through -sendEvent:");
		check(content->keyDowns == 0, "and the first responder does NOT also see the keystroke");
		[application sendEvent:event];
		check(target->fired == 2, "a second press fires again, once per press");

		/* AND AN ORDINARY KEY STILL REACHES THE RESPONDER, because it matches no equivalent. */
		event = [NSEvent keyEventWithType:NSKeyDown
					 location:NSZeroPoint
				    modifierFlags:0
					timestamp:0
				     windowNumber:(NSInteger)[window windowNumber]
					  context:nil
				       characters:@"n"
		      charactersIgnoringModifiers:@"n"
				  isARepeat:NO
				    keyCode:45];
		[application sendEvent:event];
		check(target->fired == 2, "a bare `n` fires no menu item");
		check(content->keyDowns == 1, "and reaches the first responder as it should");

		printf("appkit_dispatch: %d checks, %d failed%s\n", g_checks, g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");

		[menu release];
		[target release];
		[content release];
		[window release];
		(void)veto;
	}
	return g_failed == 0 ? 0 : 1;
}
