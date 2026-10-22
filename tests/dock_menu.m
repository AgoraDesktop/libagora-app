/*
 * dock_menu — a tile's menu, from the delegate's answer to the class that sends the item back.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE WHOLE ROUND TRIP, THROUGH BOTH PROCESSES' WORTH OF MACHINERY, IN ONE PROCESS.** The Dock asking and the
 * application answering are two programs in a session; a test cannot be two programs and stay a sequence, so this
 * probe is both ends on one connection — which is exactly what the protocol allows, because the ask names a WINDOW
 * and the server does not care who owns it:
 *
 *   1. the application's half is this probe's own `-applicationDockMenu:` — a delegate method that has been declared
 *      in this tree for longer than there was a Dock to ask it, and that this test is the first caller of;
 *   2. the Dock's half is `+[NSDockMenu menuForWindowID:]`, which asks the server, waits for the answer, and builds
 *      an `NSMenu` out of the description that comes back;
 *   3. a pick is `+[NSDockMenu dispatchActionForItem:toWindowID:]`, and the assertion is that the row's own target
 *      and action run — the application's objects, in the application's process, chosen by an id.
 *
 * **AND THE WINDOW IS FOUND THE WAY A DOCK FINDS IT.** The probe has no bundle, so `NSWorkspace` groups it under no
 * identifier at all (a window whose application declared none is skipped there, on purpose). What it has is the
 * window list itself, so that is what it reads: one row, whose title it set, whose server id is then the address of
 * every ask below. That is also the honest demonstration that a window id is all the two halves share.
 *
 *   dock_menu            (no arguments)
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSDockMenu.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSAutoreleasePool.h>

#import "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* THE DELEGATE: two choosable rows, a separator, and a row that opens a submenu — one of everything the description
 * carries — with a flag that says whether it is answering at all, so the "no dock menu" path can be driven too. */
@interface ProbeDelegate : NSObject
{
@public
	int menuAsks;
	int actions;		/* how many of the rows' own actions ran */
	int lastTag;		/* which row ran, by its tag */
	BOOL answers;
}
@end

@implementation ProbeDelegate

- (id)applicationDockMenu:(NSApplication *)sender
{
	NSMenu *menu;
	NSMenu *recent;
	NSMenuItem *item;

	(void)sender;
	menuAsks++;
	if (!answers) {
		return nil;
	}
	menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	item = [[NSMenuItem alloc] initWithTitle:@"Send Feedback" action:@selector(rowChosen:) keyEquivalent:@""];
	[item setTarget:self];
	[item setTag:1];
	[menu addItem:item];
	[item release];
	[menu addItem:[NSMenuItem separatorItem]];
	/* **A ROW THE APPLICATION ITSELF SAYS IS UNAVAILABLE.** It HAS an action and a target, and its validator says
	 * NO — which is the case the two sides have to agree about: the enabling decision is made in THIS process, by
	 * `-update`, and the Dock must not re-make it with its own target. */
	item = [[NSMenuItem alloc] initWithTitle:@"Buy Pro" action:@selector(rowChosen:) keyEquivalent:@""];
	[item setTarget:self];
	[item setTag:3];
	[menu addItem:item];
	[item release];
	recent = [[[NSMenu alloc] initWithTitle:@"Recent"] autorelease];
	item = [[NSMenuItem alloc] initWithTitle:@"notes.txt" action:@selector(rowChosen:) keyEquivalent:@""];
	[item setTarget:self];
	[item setTag:2];
	[recent addItem:item];
	[item release];
	item = [[NSMenuItem alloc] initWithTitle:@"Recent" action:NULL keyEquivalent:@""];
	[menu setSubmenu:recent forItem:item];
	[menu addItem:item];
	[item release];
	return menu;
}

- (void)rowChosen:(id)sender
{
	actions++;
	lastTag = (int)[(NSMenuItem *)sender tag];
}

/* THE VALIDATOR, WHICH IS WHY `-update` HAS TO RUN IN THIS PROCESS: the item is enabled exactly when this answers YES
 * for it, and no other process can ask. */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	return [menuItem tag] != 3;
}

@end

/* **THE WINDOW LIST, READ AS A DOCK READS IT.** The probe is its own shell component here: one row carries its
 * window's server id, and that number is the address of every ask below. */
static unsigned int s_window_id;

static void list_rows(void *context, const AGWindowInfo *rows, int count)
{
	int i;

	(void)context;
	for (i = 0; i < count; i++) {
		if (strcmp(rows[i].title, "Dock Menu Probe") == 0) {
			s_window_id = rows[i].id;
		}
	}
}

/* THE APPLICATION'S OWN PUMP, which is where both halves of the round trip make their progress: the ask dispatches
 * inside `NSDockMenu`, and a pick lands on the connection and is dispatched by this. */
static void pump_for(NSTimeInterval interval)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:interval];

	while ([deadline timeIntervalSinceNow] > 0.0) {
		NSEvent *event = [application nextEventMatchingMask:NSAnyEventMask
						  untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
						     inMode:nil
						    dequeue:YES];

		if (event != nil) {
			[application sendEvent:event];
		}
	}
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application = [NSApplication sharedApplication];
	ProbeDelegate *delegate = [[ProbeDelegate alloc] init];
	NSWindow *window;
	NSMenu *menu;
	NSDate *deadline;

	printf("dock_menu\n");
	[application setActivationPolicy:NSApplicationActivationPolicyAccessory];
	[application setDelegate:delegate];
	[application finishLaunching];

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 40.0, 240.0, 120.0)
					     styleMask:NSBorderlessWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	[window setTitle:@"Dock Menu Probe"];
	[window orderFront:nil];

	/* **THE WINDOW'S ID, FROM THE LIST.** The handler is asked for before the first pump; the snapshot that names
	 * the window arrives with it. The probe reads the list ITSELF rather than through `NSWorkspace`, because a test
	 * binary declares no bundle identifier and is therefore not an application as far as the list is concerned. */
	AGWindowListSetHandler(AGWindowServerShared(), list_rows, NULL);
	deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	while (s_window_id == 0 && [deadline timeIntervalSinceNow] > 0.0) {
		pump_for(0.02);
	}
	check(s_window_id != 0, "the window list names the probe's own window");
	if (s_window_id == 0) {
		printf("dock_menu: the window list never named the window — nothing else can be asked\n");
		[delegate release];
		[window release];
		[pool release];
		return 1;
	}

	/* ---- 1. the ask, the delegate, the description, and the menu that comes back ---------------------- */
	delegate->answers = YES;
	menu = [NSDockMenu menuForWindowID:s_window_id];
	check(delegate->menuAsks == 1, "-applicationDockMenu: was asked, once");
	check(menu != nil, "the application's answer came back as a menu");
	check([menu numberOfItems] == 4, "three rows and a separator crossed");
	if ([menu numberOfItems] == 4) {
		check([[[menu itemAtIndex:0] title] isEqualToString:@"Send Feedback"], "the first row keeps its title");
		check([[menu itemAtIndex:1] isSeparatorItem], "the separator is a separator");
		check([[[menu itemAtIndex:3] submenu] numberOfItems] == 1, "the submenu came with its row");
		check(![[menu itemAtIndex:2] isEnabled], "a row the application's validator refused arrives disabled");
	} else {
		check(0, "the rows could not be checked: the menu is the wrong size");
	}

	/* ---- 2. a row that opens a submenu is not choosable, and a row that is carries an id --------------- */
	if ([menu numberOfItems] == 4) {
		check([[menu itemAtIndex:0] representedObject] != nil, "a choosable row carries an id");
		check([[menu itemAtIndex:3] representedObject] == nil, "a submenu's row carries none");
	}

	/* ---- 3. the pick, and the row's own action running in this process -------------------------------- */
	if ([menu numberOfItems] == 4) {
		NSInteger identifier = [[[menu itemAtIndex:0] representedObject] integerValue];

		[NSDockMenu dispatchActionForItem:identifier toWindowID:s_window_id];
		/* THE DISPATCH IS A ROUND TRIP, so the action runs on a later pass — which is the same shape as the Dock's
		 * own: it sends a pick and returns to its loop. */
		deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
		while (delegate->actions == 0 && [deadline timeIntervalSinceNow] > 0.0) {
			pump_for(0.02);
		}
		check(delegate->actions == 1, "the chosen row's action ran");
		check(delegate->lastTag == 1, "and it was the row the id named, not another");
	}

	/* ---- 4. and no dock menu is an ANSWER, not a hang ------------------------------------------------ */
	delegate->answers = NO;
	check([NSDockMenu menuForWindowID:s_window_id] == nil, "an application with no dock menu answers nothing");
	check(delegate->menuAsks == 2, "and it was asked again rather than remembered");

	printf("dock_menu: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	[delegate release];
	[window release];
	[pool release];
	return s_failed == 0 ? 0 : 1;
}
