/*
 * menu_pick_dismisses — a picked menu is GONE before its action runs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DEFECT THIS MEASURES WAS A MENU HANGING IN THE AIR OVER A MODAL PANEL.** The pick ran the item's action first and
 * ended the session afterwards, so an action that opens a modal loop — Forge's `Project Info…` runs an alert — started
 * it with the menu's tracking window still up, and the menu stayed on the glass until the panel was answered. Apple's
 * order is the other one: the session ends, then the item is performed.
 *
 * The claim is read from INSIDE the action, which is the only place it matters: at that moment the menu must no longer
 * be tracking. A torn-off menu is the one exception, and it is asserted too — the palette sends and stays.
 *
 * **AND THE RELEASE THAT OPENED THE MENU IS THE GESTURE THAT IS CONSUMED, WHICHEVER BUTTON MADE IT.** The session keeps
 * `_openedByPress` so that the press that opened it does not pick the row under the pointer — and that release is a
 * LEFT one only for a menu opened by a click on a title. A right-click opens a context menu with a right press, and
 * the flag used to survive it, eating the NEXT left release instead: MEASURED in a session, the first click on a Dock
 * tile's `Remove from Dock` did nothing and the second one acted. The last case below is that click.
 */
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

@interface AGMenuRecorder : NSObject
{
@public
	int picks;
	BOOL trackingWhenSent;
	id menu;
}
@end

@implementation AGMenuRecorder

- (void)takePick:(id)sender
{
	[self takePick:sender tracking:NO];
}

/* TWO SELECTORS, because `-performActionForItemAtIndex:` uses `-performSelector:withObject:` and that has no return
 * type to offer: the recorder asks the menu what it needs to know and stores the answer. */
- (void)takePick:(id)sender tracking:(BOOL)ignored
{
	(void)sender;
	(void)ignored;
	picks++;
	trackingWhenSent = [(NSMenu *)menu cg_isTracking];
}

@end

static NSEvent *fn_mouse_up(NSPoint at, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:NSLeftMouseUp location:at modifierFlags:0 timestamp:0.0
			      windowNumber:windowNumber context:nil eventNumber:0 clickCount:1 pressure:1.0];
}

/* THE RELEASE OF A RIGHT PRESS, which is the gesture that opens a context menu. */
static NSEvent *fn_right_mouse_up(NSPoint at, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:NSRightMouseUp location:at modifierFlags:0 timestamp:0.0
			      windowNumber:windowNumber context:nil eventNumber:0 clickCount:1 pressure:1.0];
}

/* A MENU WITH ONE ROW, WHOSE ACTION IS THE RECORDER'S. */
static NSMenu *fn_menu(id target, SEL action)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Pick"];
	NSMenuItem *item = [menu addItemWithTitle:@"Pick Me" action:action keyEquivalent:@""];

	[item setTarget:target];
	return menu;
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		AGMenuRecorder *recorder = [[AGMenuRecorder alloc] init];
		NSMenu *menu = fn_menu(recorder, @selector(takePick:tracking:));

		(void)[application finishLaunching];
		recorder->menu = menu;

		/* 1. THE PICK ENDS THE SESSION BEFORE THE ACTION. */
		[menu cg_beginSessionAt:NSMakePoint(40.0, 40.0)];
		check([menu cg_isTracking], "the session began");
		{
			BOOL stillTracking = [menu cg_trackOneEvent:fn_mouse_up(NSMakePoint(10.0, 10.0), 0)];

			check(recorder->picks == 1, "the release over a row sent its action");
			check(recorder->trackingWhenSent == NO,
			      "and the menu was NOT tracking when the action ran");
			check(stillTracking == NO, "the tracking step reports the session ended");
			check(![menu cg_isTracking], "and the menu is not tracking afterwards");
		}

		/* 2. A TORN-OFF MENU IS A PALETTE: it sends and STAYS, which is the one exception to the rule above. */
		{
			AGMenuRecorder *second = [[AGMenuRecorder alloc] init];
			NSMenu *torn = fn_menu(second, @selector(takePick:tracking:));

			second->menu = torn;
			[torn cg_setTornOff:YES];
			[torn cg_beginSessionAt:NSMakePoint(40.0, 40.0)];
			check([torn cg_isTracking], "the torn-off session began");
			check([torn cg_trackOneEvent:fn_mouse_up(NSMakePoint(10.0, 10.0), 0)] == YES,
			      "a pick in a torn-off menu does not end it");
			check(second->picks == 1, "and the action was still sent");
			check([torn cg_isTracking], "the torn-off menu is still up");
			[torn cancelTracking];
			[torn release];
			[second release];
		}

		/* 3. AND A RELEASE OVER NOTHING IS A DISMISSAL THAT SENDS NOTHING — the other half of the same branch. */
		{
			AGMenuRecorder *third = [[AGMenuRecorder alloc] init];
			NSMenu *empty = fn_menu(third, @selector(takePick:tracking:));

			third->menu = empty;
			[empty cg_beginSessionAt:NSMakePoint(40.0, 40.0)];
			check([empty cg_trackOneEvent:fn_mouse_up(NSMakePoint(-40.0, -40.0), 0)] == NO,
			      "a release outside the menu ends it");
			check(third->picks == 0, "and sends nothing");
			check(![empty cg_isTracking], "with the menu dismissed");
			[empty release];
			[third release];
		}

		/* 4. **THE RELEASE THAT OPENED A RIGHT-CLICK'S MENU IS A RIGHT ONE.** A session that drives itself keeps the
		 * `_openedByPress` flag so its opening release cannot pick a row — and the case that goes wrong is the one
		 * nobody wrote down: a context menu opened by a RIGHT press releases the right button, so a flag cleared only
		 * by a left release stays set and eats the first click on a row. The session here is a SUBMENU whose parent is
		 * tracking, which is the only way a probe can hold a self-driving session open without an application loop
		 * (see `-popUpMenuPositioningItem:`'s own note on that). */
		{
			AGMenuRecorder *fourth = [[AGMenuRecorder alloc] init];
			NSMenu *parent = [[NSMenu alloc] initWithTitle:@"Parent"];
			NSMenu *child = fn_menu(fourth, @selector(takePick:tracking:));
			NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:@"More" action:NULL keyEquivalent:@""];
			NSRect frame;

			fourth->menu = child;
			/* THE PAIRING DOOR, BOTH WAYS: an item that holds a menu and a menu that knows its holder. The
			 * one-directional `-setSubmenu:` on the item leaves the menu a root, and a root that drives itself closes
			 * at once in a process with no run loop. */
			[parent addItem:holder];
			[parent setSubmenu:child forItem:holder];
			[holder release];
			[parent cg_beginSessionAt:NSMakePoint(40.0, 40.0)];
			[child popUpMenuPositioningItem:nil atLocation:NSMakePoint(120.0, 120.0) inView:nil];
			check([child cg_isTracking], "a submenu opened over a tracking parent is a session of its own");
			frame = [child cg_trackingFrame];
			{
				/* THE EVENT SPEAKS THE WINDOW'S OWN SPACE, and `-cg_itemAtPoint:` adds the frame's origin to it —
				 * so a point in the middle of the frame's SIZE is the middle of the row, while the frame's
				 * midpoint in SCREEN coordinates would be one frame too far. */
				NSPoint row = NSMakePoint(NSWidth(frame) / 2.0, NSHeight(frame) / 2.0);

				check([child cg_trackOneEvent:fn_right_mouse_up(row, 0)] == YES && fourth->picks == 0,
				      "the right release that opened the menu is consumed and picks nothing");
				check([child cg_trackOneEvent:fn_mouse_up(row, 0)] == NO && fourth->picks == 1,
				      "and the FIRST left release after it is the pick, not the second");
			}
			[child cancelTracking];
			[parent cancelTracking];
			[parent release];
			[fourth release];
		}

		[menu release];
		[recorder release];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
