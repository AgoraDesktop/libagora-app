/*
 * popup_anchor — where a pop-up button's menu and a combo box's list actually open.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE BUG THIS FILE EXISTS FOR WAS "the menus attached to popup buttons and combo boxes are appearing in the wrong
 * place".** The two controls share `-cg_popUpAnchorForFrame:inView:`, which answered the cell's bottom-left corner
 * already carried into WINDOW coordinates. `NSMenu -popUpMenuPositioningItem:atLocation:inView:` had meanwhile been
 * corrected to take the point in the VIEW's coordinates and carry it to the screen itself, so the shared door was a
 * second conversion: every raised window opened one window-origin too far right and too far up.
 *
 * The assertions are therefore two pairs:
 *
 *   1. the shared anchor is the cell frame's bottom-left IN THE CONTROL VIEW'S COORDINATES, for both cells; and
 *   2. the panel a cell raises is placed at the window's origin plus the control's origin — not at the sum twice.
 *
 * The menu's own conversion is what `menu_placement.m` measures; this file measures the two controls that call it.
 * No compositor is needed: `NSMenu` keeps its tracking frame even when there is no screen to show the panel on.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSAutoreleasePool.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

static int near_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.5;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	NSView *content;
	NSView *holder;
	NSPopUpButtonCell *popup;
	NSComboBoxCell *combo;
	NSMenu *menu;
	NSMenu *list;
	NSRect inner = NSMakeRect(0.0, 0.0, 140.0, 23.0);
	NSRect frame;
	NSPoint where;
	CGFloat baseX;
	CGFloat baseY;

	(void)application;
	printf("popup_anchor\n");

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(900.0, 100.0, 400.0, 300.0)
					     styleMask:NSBorderlessWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
	holder = [[NSView alloc] initWithFrame:NSMakeRect(60.0, 80.0, 140.0, 23.0)];
	[window setContentView:content];
	[content addSubview:holder];

	/* THE PLACE THE PANEL MUST OPEN FROM: the window's origin plus the holder's origin, on the screen. */
	baseX = [window frame].origin.x + [holder frame].origin.x;
	baseY = [window frame].origin.y + [holder frame].origin.y;

	/* ---- 1. THE POP-UP BUTTON ---------------------------------------------------------------- */
	popup = [[NSPopUpButtonCell alloc] initTextCell:@"Popup" pullsDown:NO];
	menu = [[NSMenu alloc] initWithTitle:@"Popup Menu"];
	[menu addItemWithTitle:@"First" action:NULL keyEquivalent:@""];
	[menu addItemWithTitle:@"Second" action:NULL keyEquivalent:@""];
	[popup setMenu:menu];

	where = [popup cg_popUpAnchorForFrame:inner inView:holder];
	printf("  pop-up anchor in the view: %.0f,%.0f (the window is at %.0f,%.0f)\n",
	       (double)where.x, (double)where.y, (double)[window frame].origin.x, (double)[window frame].origin.y);
	check(where.x == NSMinX(inner) && where.y == NSMinY(inner),
	      "the pop-up's anchor is the cell's bottom-left IN THE VIEW's coordinates");

	[popup attachPopUpWithFrame:inner inView:holder];
	frame = [menu cg_trackingFrame];
	printf("  pop-up menu at %.0f,%.0f %.0fx%.0f (expected x %.0f, top %.0f)\n",
	       (double)frame.origin.x, (double)frame.origin.y, (double)frame.size.width,
	       (double)frame.size.height, (double)baseX, (double)baseY);
	check(near_enough(frame.origin.x, baseX),
	      "and the menu opens at the WINDOW's x plus the control's x — one conversion, not two");
	check(near_enough(frame.origin.y, baseY - frame.size.height),
	      "with its top at the control's bottom edge in the window");

	/* ---- 2. THE COMBO BOX -------------------------------------------------------------------- */
	combo = [[NSComboBoxCell alloc] initTextCell:@"Combo"];
	[combo addItemWithObjectValue:@"First"];
	[combo addItemWithObjectValue:@"Second"];

	where = [combo cg_popUpAnchorForFrame:inner inView:holder];
	check(where.x == NSMinX(inner) && where.y == NSMinY(inner),
	      "the combo box's anchor is the SAME point, because the pair shares one door");

	list = [combo cg_buildListMenu];
	[list popUpMenuPositioningItem:nil atLocation:where inView:holder];
	frame = [list cg_trackingFrame];
	printf("  combo list at %.0f,%.0f %.0fx%.0f\n",
	       (double)frame.origin.x, (double)frame.origin.y, (double)frame.size.width,
	       (double)frame.size.height);
	check(near_enough(frame.origin.x, baseX),
	      "and the list opens at the control's left edge, carried once");
	check(near_enough(frame.origin.y, baseY - frame.size.height),
	      "with its top at the control's bottom edge");

	[combo release];
	[popup release];
	[menu release];
	[holder release];
	[content release];
	[window release];
	[pool release];
	printf("popup_anchor: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
