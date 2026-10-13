/*
 * appkit_menu_draw — a POPPED-UP MENU, on a real display, for a person to look at.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THIS IS A DEMO RATHER THAN A TEST, AND IT IS HERE BECAUSE "CAN I SEE IT" IS A REASON.** The ink tests assert
 * pixels offscreen; this one puts a menu up on a display so that what they assert can also be LOOKED at. It is
 * run against Agora's own window server nested on an X11 desktop, which grabs nothing — unlike a nested
 * gnome-shell, which takes the host's pointer.
 *
 * The menu is popped up when the application is NOT running its own loop, so `-popUpMenuPositioningItem:...`
 * returns at once and leaves the session UP; this program then pumps events itself, which is what makes the
 * menu's own window draw.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSEvent.h>
#import <Foundation/NSDate.h>

#include <stdio.h>
#include <time.h>

int main(void)
{
	NSApplication *app = [NSApplication sharedApplication];
	NSWindow *window;
	NSMenu *menu;
	int i;

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80.0, 80.0, 420.0, 260.0)
					     styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	[window setTitle:@"Agora AppKit"];
	[window setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 260)] autorelease]];
	[window orderFront:nil];

	/* **AND THE APPLICATION'S OWN MENUS, IN THE BAR — WHICH IS WHAT `-setMainMenu:` COULD NOT DO BEFORE.** The
	 * server says where the bar's free space begins; this application's menus go there, in a window of its own at
	 * `NSMainMenuWindowLevel`. THE WINDOW IS ONLY AS WIDE AS THE MENUS, because a bar stretched across the whole
	 * free space would swallow clicks meant for the status items. */
	{
		NSMenu *bar = [[NSMenu alloc] initWithTitle:@"MainMenu"];

		/* **AND HELP IS PUT SECOND ON PURPOSE.** The HIG says it belongs LAST, and a main menu that already had it
		 * last would be a demonstration that proves nothing: this way the bar has to MOVE it, and the picture says
		 * whether it did. */
		[bar addItemWithTitle:@"File" action:NULL keyEquivalent:@""];
		[bar addItemWithTitle:@"Help" action:NULL keyEquivalent:@""];
		[bar addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
		[bar addItemWithTitle:@"View" action:NULL keyEquivalent:@""];
		[app setMainMenu:bar];
	}

	menu = [[NSMenu alloc] initWithTitle:@"File"];
	[menu addItemWithTitle:@"New Window" action:NULL keyEquivalent:@"n"];
	[menu addItemWithTitle:@"Open Recent" action:NULL keyEquivalent:@"o"];
	[menu addItemWithTitle:@"Save a Copy" action:NULL keyEquivalent:@"s"];
	[menu addItemWithTitle:@"Close" action:NULL keyEquivalent:@"w"];

	/* NOT RUNNING, SO THIS RETURNS AND LEAVES THE MENU UP — the door's own documented behaviour. */
	[menu popUpMenuPositioningItem:[menu itemAtIndex:1] atLocation:NSMakePoint(180.0, 240.0) inView:nil];

	/* AND THE PUMPING IS THE TEST'S OWN, because nothing else will do it: every frame the menu's window draws on
	 * comes from the seam's frame callback, and those are dispatched here. */
	for (i = 0; i < 200; i++) {
		NSEvent *event = [app nextEventMatchingMask:NSAnyEventMask
						  untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
						     inMode:nil dequeue:YES];

		(void)event;
	}
	printf("appkit_menu_draw: a menu with %ld items was up for %d passes\n", (long)[menu numberOfItems], i);
	return 0;
}
