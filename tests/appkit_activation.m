/*
 * appkit_activation — does only the ACTIVE application's menu bar show?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
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
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int g_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		g_failed++;
	}
}

int main(void)
{
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		NSWindow *window;
		NSWindow *barWindow = nil;
		NSMenu *bar;
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

		/* 5. **THERE IS ALWAYS A KEY APPLICATION.** Hiding the window that HAS the keyboard does not leave the
		 * desktop with none: the compositor moves it to the topmost window that is left — here the menu bar window
		 * itself, which is this application's too — so the application is STILL active and its menus stay. A desk
		 * with no key window is a desk with no menu bar at all, which is the state this forbids. */
		[window orderOut:nil];
		for (i = 0; i < 60; i++) {
			NSEvent *e = [app nextEventMatchingMask:NSAnyEventMask
						      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
							 inMode:nil dequeue:YES];

			if (e != nil) {
				[app sendEvent:e];
			}
		}
		check([app isActive],
		      "hiding the KEY window moves the keyboard to another of this application's windows, not to nobody");
		check(barWindow != nil && [barWindow isVisible],
		      "so the menu bar stays — the desktop is never left without a key application");

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
