/*
 * appkit_activation — does only the ACTIVE application's menu bar show?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A MENU BAR IS THE ACTIVE APPLICATION'S, AND AN APPLICATION IS ACTIVE WHEN IT HAS THE KEYBOARD.** The
 * compositor already says which CLIENT has the keyboard — `wl_keyboard.enter` to the one whose surface is
 * focused, `wl_keyboard.leave` when it gives it up — so this needs no protocol of its own: the application is
 * active exactly while one of its windows holds the keyboard, and it shows its menu bar window then and not
 * otherwise. THAT IS WHAT MAKES "ONLY THE ACTIVE APP'S MENUS SHOW" TRUE: every application draws its own menus
 * in its own window, and only the active one has that window on the glass.
 *
 * THE COMPOSITOR IS AGORA'S OWN, because only it has a menu bar for an application to put menus in (the strip
 * and the System menu are the server's; the rest is the client's). It runs headless, so this is an ordinary
 * ctest rather than a demonstration.
 *
 * WHAT IS ASSERTED:
 *
 *   1. The application is ACTIVE — the compositor gave this client the keyboard when its window was mapped.
 *   2. Its menu bar window is SHOWN while it is active.
 *   3. DEACTIVATING hides it, which is the whole feature.
 *   4. ACTIVATING shows it again — a window ordered out is not destroyed.
 *   5. "BRING ALL TO FRONT" arranges the application's windows and LEAVES THE MENU BAR WHERE IT IS.
 *   6. THE KEYBOARD GOES TO A WINDOW, NEVER TO THE BAR, and an application with no window left gives it up rather
 *      than handing it to its own chrome. That rule is what stops the bar of an application nobody activated from
 *      becoming the bar on the screen.
 *   7a. **AND A PRESS OUTSIDE AN OPEN MENU DOES NOT EITHER.** A click on another window — the desktop, another
 *      application, or the invisible window a Dock puts up to catch it — dismisses a pop-up menu without making the
 *      window it landed on the active one. Read from the menu's own session step and from the application's state.
 *   7. **CLICKING A MENU ITEM DOES NOT CHANGE THE APPLICATION THAT HAS THE KEYBOARD.** A picked row is a press on
 *      the menu's own window, and a press is what gives a window the keyboard — so a menu that said nothing took it
 *      for as long as it was up and handed it on when it went away, which is exactly "choosing File > New left
 *      somebody else's menus in the bar". Read from the compositor's own window list, whose `active` field is the
 *      only notion of "frontmost" this tree has.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

#include "AGWindowServer.h"

#include <stdio.h>

static int g_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		g_failed++;
	}
}

/* DRAIN THE QUEUE, so a request has been read by the compositor and its answer is in the seam's own storage. */
static void fn_pump(NSApplication *app, int passes)
{
	int i;

	for (i = 0; i < passes; i++) {
		NSEvent *e = [app nextEventMatchingMask:NSAnyEventMask
					      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
						 inMode:nil dequeue:YES];

		if (e != nil) {
			[app sendEvent:e];
		}
	}
}

/* A HANDLER IS WHAT ASKS FOR THE LIST — the snapshot is sent to a listener, and a listener exists only once somebody
 * has registered. The owner function below reads the seam's copy of the last snapshot, so the callback itself has
 * nothing left to do. */
static void fn_window_list(void *context, const AGWindowInfo *windows, int count)
{
	(void)context;
	(void)windows;
	(void)count;
}

/* **WHICH WINDOW HAS THE KEYBOARD, ASKED OF THE COMPOSITOR RATHER THAN OF THE APPLICATION.** The window list's
 * `active` flag is the same answer a Dock draws its indicator from, and it is per WINDOW rather than per client —
 * which is what makes it able to see a menu stealing the keyboard at all, since the menu and the window it was
 * opened from belong to one application. */
static unsigned int fn_keyboard_owner(AGWindowServer *server)
{
	int count = 0, i;
	const AGWindowInfo *rows = AGWindowListRows(server, &count);

	for (i = 0; i < count; i++) {
		if (rows[i].active) {
			return rows[i].id;
		}
	}
	return 0;
}

int main(void)
{
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		NSWindow *window;
		NSWindow *barWindow = nil;
		NSMenu *bar;
		AGWindowServer *server = NULL;
		int i;

		setvbuf(stdout, NULL, _IONBF, 0);
		[app finishLaunching];

		/* THE APPLICATION'S OWN MENUS FIRST, so a bar window exists BEFORE anything is active — which is the
		 * only way to see that it is not shown yet. */
		bar = [[NSMenu alloc] initWithTitle:@"MainMenu"];
		[bar addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
		[bar addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
		[app setMainMenu:bar];

		/* AND A WINDOW, ordered front so the compositor hands this client the keyboard. */
		/* A TITLED WINDOW, so the one-window rule has a window that CAN be key and main; a borderless window
		 * would make the key-state checks below untestable by design. */
		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80.0, 80.0, 300.0, 200.0)
						     styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
		[window setTitle:@"Activation"];
		[window setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)] autorelease]];
		[window orderFront:nil];

		/* PUMP, so the compositor's `wl_keyboard.enter` is read and turned into the application's active state. */
		for (i = 0; i < 150; i++) {
			NSEvent *e = [app nextEventMatchingMask:NSAnyEventMask
						      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
							 inMode:nil dequeue:YES];

			if (e != nil) {
				[app sendEvent:e];
			}
		}

		/* THE BAR IS FOUND BY ITS LEVEL, which is what makes it the bar — nothing else is at
		 * `NSMainMenuWindowLevel`. */
		{
			NSArray *windows = [app windows];
			NSUInteger k;

			for (k = 0; k < [windows count]; k++) {
				NSWindow *w = [windows objectAtIndex:k];

				if ([w level] == NSMainMenuWindowLevel) {
					barWindow = w;
					break;
				}
			}
		}

		/* **AND THE COMPOSITOR'S OWN ANSWER ABOUT WHO HAS THE KEYBOARD IS ASKED FOR HERE**, once, because two of
		 * the sections below are questions only it can answer: the list's `active` flag is per WINDOW rather than per
		 * client, which is what lets it see a menu taking the keyboard from a window of the menu's own application. An
		 * application's `-isActive` cannot — the keyboard never left the application. */
		server = AGWindowServerShared();
		if (server != NULL) {
			AGWindowListSetHandler(server, fn_window_list, NULL);
		}

		check(barWindow != nil, "the application has a MENU BAR window holding its own menus");
		check([app isActive], "and it is ACTIVE — the compositor gave this client the keyboard");
		check(barWindow != nil && [barWindow isVisible],
		      "so its menu bar is SHOWN while it is the active application");
		/* **ONE WINDOW, AND IT IS THE ONE THE APPLICATION SPEAKS THROUGH.** Activating must make it key and main
		 * without a click, which is what keeps its chrome active and its menu commands routed. */
		check([window isKeyWindow] && [app keyWindow] == window,
		      "the application's ONLY window is KEY as soon as the application is active");
		check([window isMainWindow] && [app mainWindow] == window,
		      "and MAIN, without waiting for a click");

		/* 3. DEACTIVATING — what another application taking the keyboard does — TAKES THE MENUS AWAY. */
		[app deactivate];
		check(![app isActive], "deactivating clears the active state");
		check(barWindow != nil && ![barWindow isVisible],
		      "and HIDES the menu bar, so only the active application's menus show");

		/* 4. AND ACTIVATING BRINGS THEM BACK, because the window was ordered out and not destroyed. */
		[app activate];
		check([app isActive], "activating sets the active state again");
		check(barWindow != nil && [barWindow isVisible], "and the menu bar comes back with it");

		/* 5. **"BRING ALL TO FRONT" MUST NOT MOVE THE MENU BAR.** The bar is an `NSWindow` in this tier and is in
		 * the application's registry, so a cascade over that registry used to drag it off its strip. It is FURNITURE,
		 * not one of the windows being arranged, and the application's own window is what must still move. */
		if (barWindow != nil) {
			NSRect barBefore = [barWindow frame];
			NSRect windowBefore = [window frame];

			[app arrangeInFront:nil];
			check(NSEqualRects([barWindow frame], barBefore),
			      "\"Bring All to Front\" leaves the MENU BAR where it was");
			check(!NSEqualRects([window frame], windowBefore),
			      "and still arranges the application's own window");
		}

		/* 6. **THE KEYBOARD GOES TO A WINDOW, NEVER TO THE BAR.** The compositor gives the keyboard to the window the
		 * application is working in, and when that window goes away it gives it to the topmost WINDOW that is left —
		 * a BAR is not a candidate, because a bar is the active application's CHROME and handing it the keyboard is
		 * handing it the menu bar. So an application that still has a window keeps the keyboard through the loss of
		 * its key one, and an application with nothing left gives it up; neither outcome is "the bar takes over". */
		{
			NSWindow *other = [[NSWindow alloc]
				initWithContentRect:NSMakeRect(120.0, 320.0, 240.0, 160.0)
					  styleMask:NSTitledWindowMask
					    backing:NSBackingStoreBuffered
					      defer:NO];

			[other setTitle:@"Second"];
			[other setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 160.0)] autorelease]];
			[other orderFront:nil];
			/* THE NEW WINDOW IS THE TOPMOST AND THE OLD ONE IS KEY: two windows, and the keyboard deliberately not
			 * on the front one. */
			[window makeKeyWindow];
			fn_pump(app, 30);
			check([window isKeyWindow], "the keyboard is on the window that was made key");

			[window orderOut:nil];
			fn_pump(app, 30);
			check([app isActive],
			      "hiding the KEY window moves the keyboard to another of this application's windows");
			check(server != NULL && fn_keyboard_owner(server) == (unsigned int)[other windowNumber],
			      "and the compositor gave it to that one, not to the menu bar");
			check(barWindow != nil && [barWindow isVisible], "so the menu bar stays, which is the active one's");

			[other orderOut:nil];
			fn_pump(app, 30);
			check(![app isActive],
			      "and with no window left the application gives the keyboard up rather than to its bar");
			[other release];
			/* AND SAID BACK ON, because a bar window that is not on the glass is not a bar window. */
			[app activate];
			fn_pump(app, 10);
		}

		/* 7. **A MENU IS NOT A PLACE TO PUT THE KEYBOARD EITHER.** A picked row is a press on the menu's own window,
		 * and the compositor gives a press's window the keyboard. A menu that said nothing therefore took the keyboard
		 * for as long as it was up, and when the session ended the compositor had to give it to somebody — the topmost
		 * WINDOW underneath, which need not be the one the menu belongs to. That is the report this measures: choosing
		 * a row changed the application in front, and the other application's menus appeared in the strip.
		 *
		 * THE SCENE IS THE STATE THAT MAKES IT VISIBLE: two ordinary windows, the TOPMOST one NOT the key one — which
		 * is what a second application's window is, in a rule the compositor states in levels and windows rather than
		 * in clients. The press itself is asked for through `AGWindowActivate`, the door a Dock's tile click uses; the
		 * click path and that door meet in one gate (`aws_seat_set_keyboard_focus`), so a window that refuses this
		 * refuses a press. */
		{
			NSWindow *lower, *upper;
			NSWindow *menuWindow = nil;
			NSMenu *popup;
			unsigned int lowerID;

			lower = [[NSWindow alloc] initWithContentRect:NSMakeRect(500.0, 100.0, 260.0, 180.0)
							     styleMask:NSTitledWindowMask
							       backing:NSBackingStoreBuffered
								 defer:NO];
			upper = [[NSWindow alloc] initWithContentRect:NSMakeRect(600.0, 320.0, 260.0, 180.0)
							     styleMask:NSTitledWindowMask
							       backing:NSBackingStoreBuffered
								 defer:NO];
			[lower setTitle:@"Lower"];
			[upper setTitle:@"Upper"];
			[lower orderFront:nil];
			[upper orderFront:nil];
			[lower makeKeyWindow];

			fn_pump(app, 30);
			lowerID = (unsigned int)[lower windowNumber];
			check(server != NULL && fn_keyboard_owner(server) == lowerID,
			      "the keyboard is on the key window even though another window is stacked above it");

			popup = [[NSMenu alloc] initWithTitle:@"Popup"];
			[popup addItemWithTitle:@"Row" action:NULL keyEquivalent:@""];
			[popup cg_beginSessionAt:NSMakePoint(200.0, 200.0)];
			check([popup cg_isTracking], "a menu session is up");
			{
				NSArray *windows = [app windows];
				NSUInteger k;

				for (k = 0; k < [windows count]; k++) {
					NSWindow *w = [windows objectAtIndex:k];

					if ([w level] == NSPopUpMenuWindowLevel) {
						menuWindow = w;
						break;
					}
				}
			}
			check(menuWindow != nil, "and it has a window of its own, above everything");

			if (server != NULL && menuWindow != nil) {
				AGWindowActivate(server, (unsigned int)[menuWindow windowNumber]);
				fn_pump(app, 30);
				check(fn_keyboard_owner(server) == lowerID,
				      "a press on a menu does NOT take the keyboard from the window that had it");

				[popup cancelTracking];
				fn_pump(app, 30);
				check(fn_keyboard_owner(server) == lowerID,
				      "so choosing a row leaves the SAME window with the keyboard — the same application active");
			} else {
				check(0, "the menu's window could not be asked about the keyboard");
			}
			[popup release];
			[lower release];
			[upper release];
		}

		/* 8. **A PRESS IN ANOTHER WINDOW DISMISSES A MENU AND ACTIVATES NOBODY.** The menu is a caller-driven session,
		 * so it has a real tracking window (and therefore a window number) without a loop. The press is ADDRESSED to
		 * the application's key window — "somewhere else" — at a point that maps INSIDE the menu by the coordinate
		 * rule, which is what makes the window the reason it dismisses rather than the position. */
		{
			NSMenu *popup = [[NSMenu alloc] initWithTitle:@"Outside"];
			NSWindow *menuWindow = nil;
			NSWindow *keyBefore = [app keyWindow];
			NSEvent *press;
			BOOL stillTracking = YES;

			[popup addItemWithTitle:@"Row" action:NULL keyEquivalent:@""];
			[popup cg_beginSessionAt:NSMakePoint(200.0, 200.0)];
			{
				NSArray *windows = [app windows];
				NSUInteger k;

				for (k = 0; k < [windows count]; k++) {
					NSWindow *w = [windows objectAtIndex:k];

					if ([w level] == NSPopUpMenuWindowLevel) {
						menuWindow = w;
					}
				}
			}
			check([popup cg_isTracking] && menuWindow != nil,
			      "a menu is up, with a window and a window number of its own");
			if (menuWindow != nil && keyBefore != nil) {
				NSRect m = [menuWindow frame];
				NSRect k = [keyBefore frame];
				NSPoint p = NSMakePoint(NSMidX(m) - m.origin.x, NSMidY(m) - m.origin.y);

				/* THE POINT IS IN THE KEY WINDOW'S SPACE AND LANDS INSIDE THE MENU WHEN READ AS A MENU POINT —
				 * if it is not, the case would pass for the coordinate reason instead of the window one. */
				check(NSMidX(m) >= m.origin.x && NSMidY(m) >= m.origin.y &&
				      p.x <= k.size.width && p.y <= k.size.height,
				      "the fixture's press is inside the key window and maps inside the menu");
				press = [NSEvent mouseEventWithType:NSLeftMouseDown location:p modifierFlags:0
							  timestamp:0.0 windowNumber:(NSInteger)[keyBefore windowNumber]
							 context:nil eventNumber:0 clickCount:1 pressure:1.0];
				stillTracking = [popup cg_trackOneEvent:press];
				check(stillTracking == NO && ![popup cg_isTracking],
				      "and a press in ANOTHER WINDOW dismisses it, whatever the coordinates say");
				check([app isActive], "the application that was in front is still in front");
				check([app keyWindow] == keyBefore && [keyBefore isKeyWindow],
				      "and the window the press landed in did not take the keyboard");
			}
			[popup release];
		}

		/* **AND THE APPLICATION'S SEVEN SWEEP DOORS.** Three are questions about the responder chain and a string, two
		 * are one-line answers, and one is a named refusal — none of them needs a compositor to be worth asserting. */
		{
			NSView *content = [window contentView];
			id target;

			/* 1. `-targetForAction:to:from:`: a named target wins when it can take the action, a RESPONDER SENDER
			 * starts the walk from itself, and a nil action finds nobody. */
			target = [app targetForAction:@selector(hide:) to:app from:nil];
			check(target == app, "a named target that can take the action is the answer");
			target = [app targetForAction:@selector(noSuchActionAnywhere:) to:app from:nil];
			check(target == nil, "and a target that cannot is nil");
			check([app targetForAction:@selector(setNeedsDisplay:) to:nil from:content] == content,
			      "a responder sender answers from ITS OWN chain, which is how the view a click came from is found");
			check([app targetForAction:NULL] == nil, "and a nil action has no target");

			/* 2. THE HELP SEARCH: the match inside the range, case-insensitively, with the title's `&` SKIPPED. */
			{
				NSRange found = NSMakeRange(NSNotFound, 0);
				NSString *matched;

				matched = [app searchString:@"open" inUserInterfaceItemString:@"&Open Recent"
						 searchRange:NSMakeRange(0, 12) foundRange:&found];
				check(matched != nil && [[matched lowercaseString] isEqual:@"open"],
				      "the search finds the typed string in an item's title, in the case it was typed");
				check(found.location != NSNotFound,
				      "and writes the range it found — the mnemonic mark is not part of the string searched");
				check([app searchString:@"zzz" inUserInterfaceItemString:@"&Open Recent"
					   searchRange:NSMakeRange(0, 12) foundRange:&found] == nil &&
				      found.location == NSNotFound,
				      "and a string that is not there answers nil with a not-found range");
			}

			/* 3. THE THREE ONE-LINERS. */
			check(![app isHidden], "the application is not hidden to begin with");
			[app hide:nil];
			check([app isHidden], "and `-hide:` sets the flag `-isHidden` answers");
			[app unhide:nil];
			check(![app isHidden], "which `-unhide:` clears");
			check([app context] == nil, "`-context` answers nil, which is Apple's own documented answer");
			[app application:app printFiles:[NSArray arrayWithObject:@"/tmp/nothing"]];
			check(1, "and `-application:printFiles:` is a refusal rather than a crash");
		}

		printf("appkit_activation: %d check(s) failed%s\n", g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");
	}
	return g_failed == 0 ? 0 : 1;
}
