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
#import <Foundation/NSArray.h>
#import <AppKit/NSMenuView.h>	/* the bar, and the boxes its items occupy */
#import <AppKit/NSWindow.h>
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

		/* **AND EVERY TITLE CARRIES A MENU, BECAUSE A BAR TITLE WITH NOTHING BEHIND IT HAS NOTHING TO OPEN.**
		 * `-addItemWithTitle:action:keyEquivalent:` makes a LEAF — an item you can click and that is that — and the
		 * first version of this demonstration used four of them and then wondered why clicking the bar did nothing.
		 * A menu bar's titles are MENUS; the leaf items are what is INSIDE them.
		 *
		 * **AND HELP IS PUT SECOND ON PURPOSE.** The HIG says it belongs LAST, and a main menu that already had it
		 * last would be a demonstration that proves nothing: this way the bar has to MOVE it, and the picture says
		 * whether it did. */
		{
			NSArray *titles = [NSArray arrayWithObjects:@"File", @"Help", @"Edit", @"View", nil];
			NSUInteger t;

			for (t = 0; t < [titles count]; t++) {
				NSString *name = [titles objectAtIndex:t];
				NSMenuItem *title = [[NSMenuItem alloc] initWithTitle:name action:NULL
									 keyEquivalent:@""];
				NSMenu *contents = [[NSMenu alloc] initWithTitle:name];

				[contents addItemWithTitle:[NSString stringWithFormat:@"%@ Item One", name]
						    action:NULL keyEquivalent:@""];
				[contents addItemWithTitle:[NSString stringWithFormat:@"%@ Item Two", name]
						    action:NULL keyEquivalent:@""];
				[title setSubmenu:contents];
				[bar addItem:title];
				[title release];
			}
		}
		[app setMainMenu:bar];
	}

	menu = [[NSMenu alloc] initWithTitle:@"File"];
	[menu addItemWithTitle:@"New Window" action:NULL keyEquivalent:@"n"];
	[menu addItemWithTitle:@"Open Recent" action:NULL keyEquivalent:@"o"];
	[menu addItemWithTitle:@"Save a Copy" action:NULL keyEquivalent:@"s"];
	[menu addItemWithTitle:@"Close" action:NULL keyEquivalent:@"w"];

	/* **AND A CLICK ON ONE OF THE BAR'S TITLES, CONSTRUCTED AND SENT THE WAY A REAL ONE ARRIVES.**
	 *
	 * The click goes through `-[NSApplication sendEvent:]` rather than being handed to the view, so what is
	 * exercised is the whole path a person's click takes: the application looks the window up BY NUMBER, the
	 * window hit-tests its content view, and the view opens the menu of the item under the point. Sending it
	 * straight to the view would prove the last step and skip the two that the user's report was about.
	 *
	 * The bar is found by its LEVEL, which is what makes it the bar — nothing else is at
	 * `NSMainMenuWindowLevel` — and the item is the third, which after the application menu is `Edit`. */
	{
		NSArray *windows = [app windows];
		NSWindow *bar_window = nil;
		NSUInteger i;

		for (i = 0; i < [windows count]; i++) {
			NSWindow *w = [windows objectAtIndex:i];

			if ([w level] == NSMainMenuWindowLevel) {
				bar_window = w;
				break;
			}
		}
		if (bar_window == nil) {
			printf("appkit_menu_draw: no window is at the menu bar's level\n");
		} else {
			NSMenuView *view = (NSMenuView *)[bar_window contentView];
			NSMenuItem *item = (NSMenuItem *)[[view menu] itemAtIndex:2];
			NSRect box = [view rectForItemAtIndex:2];
			NSPoint at = NSMakePoint(box.origin.x + box.size.width / 2.0,
						 box.origin.y + box.size.height / 2.0);
			NSEvent *click = [NSEvent mouseEventWithType:NSLeftMouseDown location:at
						       modifierFlags:0 timestamp:0
							windowNumber:[bar_window windowNumber]
							     context:nil eventNumber:0 clickCount:1 pressure:1.0];

			printf("appkit_menu_draw: clicking \"%s\" in the bar (window %ld, at x=%.0f, y=%.0f)\n",
			       [[item title] UTF8String], (long)[bar_window windowNumber], (double)at.x, (double)at.y);
			[app sendEvent:click];
		}
	}

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
