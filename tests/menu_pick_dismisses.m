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

		[menu release];
		[recorder release];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
