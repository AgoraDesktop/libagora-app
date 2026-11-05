/*
 * menu_caller_driven.m — a menu opened by an application whose loop somebody else pumps.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DEFECT THIS EXISTS FOR WAS "MENUS GET STUCK OPEN AND DON'T RESPOND".** Every tracking loop in this tier asks
 * `-[NSApplication isRunning]` — the question is "is there an event source, will events be delivered" — and a BOUNDED
 * run (a probe that stops after N seconds, a session's own launcher, `Preview file --seconds 900`) pumps
 * `-nextEventMatchingMask:` itself and used never to set the flag. So the bar began a session, its loop declined to
 * drive it, the session stayed up with its window and its pointer grab, and every later click was refused with
 * "cannot begin a session while one is already up": a menu that is open, and an application that does not answer.
 *
 * `-cg_beginCallerDrivenRun`/`-cg_endCallerDrivenRun` is the answer, and both halves are measured here: WITH the pair
 * a menu tracks, WITHOUT it the same menu closes itself, which is the behaviour a program that has no loop to give it
 * must keep.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>

#include <stdio.h>

static int s_checks;
static int s_failures;

static void check(int condition, const char *what)
{
	s_checks++;
	if (!condition) {
		s_failures++;
		printf("  FAIL   %s\n", what);
	} else {
		printf("  ok     %s\n", what);
	}
}

/* A MENU WITH ONE ROW, so a session has something to show and something to pick. */
static NSMenu *fn_menu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Probe"];

	[menu addItemWithTitle:@"A Row" action:NULL keyEquivalent:@""];
	return menu;
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];

		(void)[application finishLaunching];

		check(![application isRunning], "an application that has not been run is not running");

		/* 1. A POPUP IN AN APPLICATION THAT IS NOT RUNNING HAS NO LOOP TO GIVE IT, SO IT CLOSES ITSELF. That is the
		 * rule that keeps a probe from leaving a menu on the glass for ever — and `-cg_beginSessionAt:` is the
		 * exception by name: it hands the session to a caller that asked to drive it. */
		{
			NSMenu *menu = fn_menu();

			[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(200.0, 300.0) inView:nil];
			check(![menu cg_isTracking],
			      "a popup opened by an application with no loop closes itself");
			[menu release];
		}

		/* 2. A PUMP THE CALLER DRIVES IS THE APPLICATION RUNNING, and the same menu then stays up. */
		[application cg_beginCallerDrivenRun];
		check([application isRunning], "a caller-driven pump makes the application RUNNING");
		{
			NSMenu *menu = fn_menu();

			[menu cg_beginSessionAt:NSMakePoint(200.0, 300.0)];
			check([menu cg_isTracking], "and a menu opened inside it tracks instead of closing itself");
			[menu cancelTracking];
			check(![menu cg_isTracking], "until it is dismissed");
			[menu release];
		}
		[application cg_endCallerDrivenRun];
		check(![application isRunning], "and the application stops running when the pump ends");

		/* 3. THE PAIR IS COUNTED, so two pumps cannot clear the flag from under each other. */
		[application cg_beginCallerDrivenRun];
		[application cg_beginCallerDrivenRun];
		[application cg_endCallerDrivenRun];
		check([application isRunning], "an inner pump ending leaves the outer one running");
		[application cg_endCallerDrivenRun];
		check(![application isRunning], "and the outermost ending is what stops it");

		printf("menu_caller_driven: %d checks, %d fail%s\n", s_checks, s_failures,
		       (s_failures == 1) ? "" : "s");
	}
	return (s_failures == 0) ? 0 : 1;
}
