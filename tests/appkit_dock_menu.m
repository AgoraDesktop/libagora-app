/*
 * appkit_dock_menu — the format a tile's menu crosses by, and the ids it comes back by.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE TRANSPORT HAS TWO HALVES AND NEITHER OF THEM NEEDS A COMPOSITOR.** An application writes a menu as a JSON
 * description and the Dock reads one back into an `NSMenu`; that is a pure conversion of a tree into a string and
 * back, so it runs anywhere — which is what makes the interesting failures testable at all:
 *
 *   1. THE ROUND TRIP IS A FIXED POINT. A menu described, rebuilt and described again must produce the SAME string,
 *      or the two halves have an opinion the other does not. A title with a quote, a backslash and a non-ASCII
 *      letter is in the tree on purpose: the description is JSON and the escaping is not this tree's invention.
 *
 *   2. THE ROWS THAT MAY BE CHOSEN ARE NUMBERED, AND ONLY THOSE. Separators and rows that open a submenu have no id
 *      — nothing is sent when they are chosen — and the ids are consecutive from 1 across the WHOLE tree, not one
 *      sequence per menu. `+cg_itemForID:inMenu:` then finds each of them, which is the application's half of a pick.
 *
 *   3. EVERYTHING THE DOCK DRAWS CROSSES AND NOTHING ELSE DOES. Title, enabled, state and the submenu tree arrive;
 *      an action and a target do not — they are the application's objects and the id stands in for them.
 *
 *   4. AND THE EMPTY ANSWERS ARE ANSWERS. No menu is `[]`, an empty array is an empty menu, and a description this
 *      class did not write is refused rather than guessed at.
 */
#import <AppKit/NSDockMenu.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSCell.h>	/* NSOnState and NSMixedState, the two values this file asserts */
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* A MENU WITH ONE OF EVERYTHING: a plain row, a disabled one, a separator, a row with a state, and a submenu two
 * deep-ish — plus a title that has to be escaped to survive a JSON string. */
static NSMenu *sampleMenu(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
	NSMenu *recent;
	NSMenuItem *item;

	item = [[NSMenuItem alloc] initWithTitle:@"New Window" action:NULL keyEquivalent:@""];
	[menu addItem:item];
	[item release];

	item = [[NSMenuItem alloc] initWithTitle:@"A \"quoted\" \\ title — ünicode" action:NULL keyEquivalent:@""];
	[item setEnabled:NO];
	[menu addItem:item];
	[item release];

	[menu addItem:[NSMenuItem separatorItem]];

	item = [[NSMenuItem alloc] initWithTitle:@"Play" action:NULL keyEquivalent:@""];
	[item setState:NSOnState];
	[menu addItem:item];
	[item release];

	recent = [[NSMenu alloc] initWithTitle:@"Open Recent"];
	item = [[NSMenuItem alloc] initWithTitle:@"notes.txt" action:NULL keyEquivalent:@""];
	[recent addItem:item];
	[item release];
	item = [[NSMenuItem alloc] initWithTitle:@"draft.txt" action:NULL keyEquivalent:@""];
	[item setState:NSMixedState];
	[recent addItem:item];
	[item release];
	item = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:NULL keyEquivalent:@""];
	[menu setSubmenu:recent forItem:item];
	[menu addItem:item];
	[item release];
	[recent release];

	return [menu autorelease];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMenu *menu;
	NSMenu *rebuilt;
	NSString *description;
	NSString *again;
	NSMenuItem *found;

	(void)[NSApplication sharedApplication];
	printf("appkit_dock_menu\n");

	/* ---- 1. the round trip is a fixed point ---------------------------------------------- */
	menu = sampleMenu();
	description = [NSDockMenu cg_descriptionForMenu:menu];
	check(description != nil && [description length] > 0, "a menu describes itself");
	rebuilt = [NSDockMenu cg_menuWithDescription:description];
	check(rebuilt != nil, "the description builds a menu");
	check([rebuilt numberOfItems] == 5, "five rows cross: four items and the separator");
	again = [NSDockMenu cg_descriptionForMenu:rebuilt];
	check(again != nil && [again isEqualToString:description],
	      "describing what was rebuilt gives the same description");

	/* ---- 2. and the rows are the same rows ---------------------------------------------- */
	check([[[rebuilt itemAtIndex:0] title] isEqualToString:@"New Window"], "the first row keeps its title");
	check([[[rebuilt itemAtIndex:1] title] isEqualToString:@"A \"quoted\" \\ title — ünicode"],
	      "a quoted, escaped, non-ASCII title survives");
	check(![[rebuilt itemAtIndex:1] isEnabled], "a disabled row arrives disabled");
	check([[rebuilt itemAtIndex:2] isSeparatorItem], "the separator arrives a separator");
	check([[rebuilt itemAtIndex:3] state] == NSOnState, "an ON row arrives ON");
	check([[[rebuilt itemAtIndex:4] submenu] numberOfItems] == 2, "the submenu arrives with its two rows");

	/* ---- 3. the chosen rows are numbered, and only those ---------------------------------- */
	check([[rebuilt itemAtIndex:2] representedObject] == nil, "a separator carries no id");
	check([[rebuilt itemAtIndex:4] representedObject] == nil, "a submenu's row carries no id");

	/* 1 New Window, 2 the disabled row, 3 Play, 4 and 5 the submenu's rows — the numbering runs across the tree, so
	 * the submenu's first row is NOT 1. */
	check([[[rebuilt itemAtIndex:0] representedObject] integerValue] == 1, "the first choosable row is 1");
	check([[[rebuilt itemAtIndex:1] representedObject] integerValue] == 2, "a DISABLED row is still numbered");
	check([[[rebuilt itemAtIndex:3] representedObject] integerValue] == 3, "the separator takes no number");
	check([[[[[rebuilt itemAtIndex:4] submenu] itemAtIndex:0] representedObject] integerValue] == 4,
	      "the submenu's first row continues the numbering");

	/* ---- 4. and the id finds its row, which is the application's half of a pick ------------ */
	found = [NSDockMenu cg_itemForID:1 inMenu:rebuilt];
	check(found == [rebuilt itemAtIndex:0], "id 1 is the first row of the menu");
	found = [NSDockMenu cg_itemForID:5 inMenu:rebuilt];
	check(found == [[[rebuilt itemAtIndex:4] submenu] itemAtIndex:1], "id 5 is the submenu's second row");
	check([NSDockMenu cg_itemForID:99 inMenu:rebuilt] == nil, "an id nothing answers finds nothing");
	check([NSDockMenu cg_itemForID:1 inMenu:nil] == nil, "and neither does an id asked of no menu");

	/* ---- 5. the empty answers ------------------------------------------------------------- */
	check([[NSDockMenu cg_descriptionForMenu:nil] isEqualToString:@"[]"], "no menu describes as an empty array");
	check([[NSDockMenu cg_menuWithDescription:@"[]"] numberOfItems] == 0, "an empty array builds an empty menu");
	check([NSDockMenu cg_menuWithDescription:@""] == nil, "an empty answer is no menu");
	check([NSDockMenu cg_menuWithDescription:@"{\"not\":\"an array\"}"] == nil,
	      "a description that is not an array is refused");
	check([NSDockMenu cg_menuWithDescription:@"[\"not a row\"]"] != nil,
	      "a row that is not a dictionary is skipped, not fatal");

	printf("appkit_dock_menu: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	[pool release];
	return s_failed == 0 ? 0 : 1;
}
