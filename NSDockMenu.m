/*
 * NSDockMenu.m — the wire between an application's dock menu and the Dock's panel.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **TWO HALVES, ONE FORMAT, AND THE ID IS THE WHOLE CONTRACT.** The application's half walks an `NSMenu` and writes
 * a JSON array of rows; the Dock's half reads that array and builds an `NSMenu` whose rows carry the application's
 * ids. Nothing else crosses — not a target, not an action, not an image — because an id is enough to name a row in
 * the application's own object graph, and naming it is all either side needs. The format is documented on
 * `+cg_descriptionForMenu:` in the header, and it is deliberately the WHOLE of it: a reader that meets a key it does
 * not know ignores it, and this file writes none it does not read.
 *
 * **THE DESCRIPTION'S IDS ARE A PRE-ORDER WALK AND SO IS THE LOOKUP**, which is what lets one side find the row the
 * other named without a table to keep in step. An item that opens a submenu has no id — nothing is sent when it is
 * chosen, its submenu is what opens — and neither does a separator.
 *
 * **AND THE WAIT IS BOUNDED AND SAID OUT LOUD.** The Dock asks inside a right-click handler, so it cannot return to
 * a run loop it is not in; it dispatches in place until the answer arrives or `NSDOCKMENU_TIMEOUT` passes. That is
 * the one place in this class that is a loop rather than a call, and it exists because the answer is asynchronous
 * by nature: the application has to receive an event, ask its own delegate, and answer.
 */
#import <AppKit/NSDockMenu.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSRunningApplication.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSJSONSerialization.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#import "platform/AGWindowServer.h"

#include <stdio.h>
#include <string.h>

/* THE FOUR KEYS, NAMED ONCE, because they are the format and a typo in one of them is a menu that quietly loses a
 * row rather than a build that fails. */
static NSString *const NSDockMenuTitleKey = @"title";
static NSString *const NSDockMenuEnabledKey = @"enabled";
static NSString *const NSDockMenuStateKey = @"state";
static NSString *const NSDockMenuIDKey = @"id";
static NSString *const NSDockMenuSubmenuKey = @"submenu";
static NSString *const NSDockMenuSeparatorKey = @"separator";

/* ============================================================================================ *
 * THE APPLICATION'S HALF: A MENU BECOMES ROWS.
 * ============================================================================================ */

/* `next_id` is the walk's counter and it is shared across submenus, so an id names one row in the whole document
 * and not one row within a menu. */
static NSArray *fn_rowsForMenu(NSMenu *menu, NSInteger *next_id)
{
	NSMutableArray *rows;
	NSArray *items;
	NSUInteger i;

	if (menu == nil) {
		return [NSArray array];
	}
	rows = [NSMutableArray array];
	items = [menu itemArray];
	for (i = 0; i < [items count]; i++) {
		NSMenuItem *item = [items objectAtIndex:i];
		NSMutableDictionary *row = [NSMutableDictionary dictionary];

		/* A SEPARATOR IS A ROW WITH NOTHING ON IT, and it is the one row whose title nobody reads: AppKit's own
		 * `+separatorItem` has a lone hyphen for one, and carrying that hyphen to the Dock would draw a mark
		 * instead of a rule. */
		if ([item isSeparatorItem]) {
			[row setObject:[NSNumber numberWithBool:YES] forKey:NSDockMenuSeparatorKey];
			[rows addObject:row];
			continue;
		}
		[row setObject:([[item title] length] > 0 ? [item title] : @"") forKey:NSDockMenuTitleKey];
		[row setObject:[NSNumber numberWithBool:[item isEnabled]] forKey:NSDockMenuEnabledKey];
		[row setObject:[NSNumber numberWithInteger:[item state]] forKey:NSDockMenuStateKey];
		if ([item submenu] != nil) {
			[row setObject:fn_rowsForMenu([item submenu], next_id) forKey:NSDockMenuSubmenuKey];
		} else {
			[row setObject:[NSNumber numberWithInteger:*next_id] forKey:NSDockMenuIDKey];
			*next_id = *next_id + 1;
		}
		[rows addObject:row];
	}
	return rows;
}

/* ============================================================================================ *
 * THE DOCK'S HALF: ROWS BECOME A MENU.
 * ============================================================================================ */
static void fn_addRowsToMenu(NSMenu *menu, NSArray *rows)
{
	NSUInteger i;

	if (menu == nil || ![rows isKindOfClass:[NSArray class]]) {
		return;
	}
	for (i = 0; i < [rows count]; i++) {
		id object = [rows objectAtIndex:i];
		NSDictionary *row;
		NSMenuItem *item;
		id submenuRows;
		id identifier;

		if (![object isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		row = object;
		if ([[row objectForKey:NSDockMenuSeparatorKey] boolValue]) {
			[menu addItem:[NSMenuItem separatorItem]];
			continue;
		}
		item = [[NSMenuItem alloc] initWithTitle:([row objectForKey:NSDockMenuTitleKey] != nil
							? [row objectForKey:NSDockMenuTitleKey]
							: @"")
						 action:NULL
					  keyEquivalent:@""];
		[item setEnabled:[[row objectForKey:NSDockMenuEnabledKey] boolValue]];
		[item setState:[[row objectForKey:NSDockMenuStateKey] integerValue]];
		/* **A ROW THAT OPENS A SUBMENU IS RECURSED INTO AND NEVER SENT BACK.** Its id would name nothing a pick
		 * could act on — the pick opens it — which is why the writer gives it none and the reader does not ask. */
		submenuRows = [row objectForKey:NSDockMenuSubmenuKey];
		if (submenuRows != nil) {
			NSMenu *submenu = [[NSMenu alloc] initWithTitle:[item title]];

			fn_addRowsToMenu(submenu, submenuRows);
			[menu setSubmenu:submenu forItem:item];
			[submenu release];
		} else {
			identifier = [row objectForKey:NSDockMenuIDKey];

			if (identifier != nil) {
				[item setRepresentedObject:[NSNumber numberWithInteger:[identifier integerValue]]];
			}
		}
		[menu addItem:item];
		[item release];
	}
}

/* THE ROW AN ID NAMES, FOUND BY THE SAME WALK THAT NUMBERED IT. `next_id` is the counter the description used, so
 * this and `fn_rowsForMenu` cannot disagree about which row is which even after an edit — the numbering is a
 * property of the tree as it is now, and the answer the Dock holds was made from it a moment ago. */
static NSMenuItem *fn_itemForID(NSMenu *menu, NSInteger *next_id, NSInteger wanted)
{
	NSArray *items;
	NSUInteger i;

	if (menu == nil) {
		return nil;
	}
	items = [menu itemArray];
	for (i = 0; i < [items count]; i++) {
		NSMenuItem *item = [items objectAtIndex:i];
		NSMenuItem *found;

		if ([item isSeparatorItem]) {
			continue;
		}
		if ([item submenu] != nil) {
			found = fn_itemForID([item submenu], next_id, wanted);
			if (found != nil) {
				return found;
			}
			continue;
		}
		if (*next_id == wanted) {
			return item;
		}
		*next_id = *next_id + 1;
	}
	return nil;
}

/* ============================================================================================ *
 * THE DOCK'S ASK, AND THE ANSWER'S ARRIVAL.
 * ============================================================================================ */
typedef struct {
	NSString *description;		/* the answer, or nil while there is none */
	int answered;
} NSDockMenuAnswer;

static void fn_answer(void *context, const char *app_id, const char *description)
{
	NSDockMenuAnswer *answer = context;

	(void)app_id;
	answer->answered = 1;
	if (description != NULL) {
		answer->description = [[NSString alloc] initWithUTF8String:description];
	}
}

/* ============================================================================================ *
 * AND THE APPLICATION'S HALF OF THE ROUND TRIP, WHICH IS NOT THIS FILE'S.
 *                                                                                                *
 * **THE PUBLISHING SIDE IS `NSApplication`'s, BECAUSE THE DELEGATE IS.** The menu is the       *
 * answer to `-applicationDockMenu:`, so `-[NSApplication cg_dockMenu]` puts the question and    *
 * KEEPS the tree — the ids that come back name rows in it. `NSWindow`'s dock-menu handler asks  *
 * the application, describes the menu here and answers with `AGWindowSetDockMenu`; a pick       *
 * comes back in through `-cg_performDockMenuItem:`, which finds the row with                    *
 * `+cg_itemForID:inMenu:` and lets the owning menu send its action. The numbering above and     *
 * that lookup are the same walk, which is why both live in THIS file.
 * ============================================================================================ */
@implementation NSDockMenu

+ (NSMenu *)menuForApplication:(NSRunningApplication *)application
{
	NSArray *windows;

	if (application == nil) {
		return nil;
	}
	/* **THE FRONTMOST WINDOW IS THE ADDRESS.** A window id is the only name the two sides share, and the ask is
	 * about the APPLICATION rather than any one of its windows — so the last id the list gave is the one to name,
	 * which is the same choice a click on the tile makes. An application with no window at all cannot be asked, and
	 * has no menu to give. */
	windows = [application cg_windowIDs];
	if ([windows count] == 0) {
		return nil;
	}
	return [self menuForWindowID:[[windows lastObject] unsignedIntValue]];
}

+ (NSMenu *)menuForWindowID:(unsigned int)windowID
{
	AGWindowServer *server = AGWindowServerShared();
	NSDockMenuAnswer answer;
	NSDate *deadline;
	NSMenu *menu = nil;

	if (server == NULL || windowID == 0) {
		return nil;
	}
	memset(&answer, 0, sizeof answer);
	AGWindowServerSetDockMenuHandler(server, fn_answer, &answer);
	if (!AGWindowRequestDockMenu(server, windowID)) {
		/* NO QUESTION WAS ASKED, SO NOTHING IS WAITED FOR: an older window server simply has no dock menus. */
		AGWindowServerSetDockMenuHandler(server, NULL, NULL);
		return nil;
	}
	/* **DISPATCH UNTIL THE ANSWER OR THE DEADLINE**, in small steps so that a menu answered in ten milliseconds is
	 * a menu shown in ten milliseconds. The connection going away ends the wait for the same reason a timeout does:
	 * there is nothing left to be told. */
	deadline = [NSDate dateWithTimeIntervalSinceNow:NSDOCKMENU_TIMEOUT];
	while (!answer.answered && [deadline timeIntervalSinceNow] > 0.0) {
		if (AGWindowServerDispatchTimeout(server, 10) < 0) {
			break;
		}
	}
	AGWindowCancelDockMenu(server);
	AGWindowServerSetDockMenuHandler(server, NULL, NULL);

	if ([answer.description length] > 0) {
		NSMenu *described = [self cg_menuWithDescription:answer.description];

		/* **A MENU WITH NO ROWS IS NO MENU.** "[]" is what an application that answered with nothing sends, and
		 * the two sides have no way to tell it from an empty `NSMenu` — so the door answers nil, which is what the
		 * header promises and what a caller's single `if` can act on. */
		if ([described numberOfItems] > 0) {
			menu = described;
		}
	}
	/* **AN EMPTY DESCRIPTION IS AN ANSWER AND NOT A FAILURE**, and it ends here: nil, which the caller shows as its
	 * own items alone. An application that answered with nothing and one that never answered differ only in how long
	 * the person waited — which is the whole of what the timeout is allowed to know. */
	[answer.description release];
	return menu;
}

+ (void)dispatchActionForItem:(NSInteger)item toApplication:(NSRunningApplication *)application
{
	NSArray *windows;

	if (application == nil) {
		return;
	}
	windows = [application cg_windowIDs];
	if ([windows count] == 0) {
		return;
	}
	[self dispatchActionForItem:item toWindowID:[[windows lastObject] unsignedIntValue]];
}

+ (void)dispatchActionForItem:(NSInteger)item toWindowID:(unsigned int)windowID
{
	AGWindowServer *server = AGWindowServerShared();

	if (server == NULL || windowID == 0) {
		return;
	}
	/* ASKED OF THE SAME WINDOW THE MENU WAS, so the application finds it where it left it. The server forwards the
	 * id and nothing else; what choosing the row means is the application's answer. */
	AGWindowActivateDockMenuItem(server, windowID, (int)item);
}

+ (NSString *)cg_descriptionForMenu:(NSMenu *)menu
{
	NSInteger next_id = 1;
	NSArray *rows;
	NSData *data;
	NSString *description = nil;

	if (menu == nil) {
		/* **NO MENU IS "NO ITEMS", AND IT IS SAID RATHER THAN LEFT UNSAID.** The Dock is holding a panel open for
		 * this answer; an empty array is the answer that lets the panel be drawn now. */
		return @"[]";
	}
	rows = fn_rowsForMenu(menu, &next_id);
	if (![NSJSONSerialization isValidJSONObject:rows]) {
		return @"[]";
	}
	data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:NULL];
	if (data != nil) {
		description = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	}
	if (description == nil) {
		return @"[]";
	}
	return [description autorelease];
}

+ (NSMenu *)cg_menuWithDescription:(NSString *)description
{
	NSData *data;
	id rows;
	NSMenu *menu;

	if ([description length] == 0) {
		return nil;
	}
	data = [description dataUsingEncoding:NSUTF8StringEncoding];
	if (data == nil) {
		return nil;
	}
	rows = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![rows isKindOfClass:[NSArray class]]) {
		/* A DESCRIPTION THIS CLASS DID NOT WRITE IS REFUSED RATHER THAN GUESSED AT: it crossed a protocol, and a
		 * half-understood one would be a menu with rows nobody asked for. */
		return nil;
	}
	menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	fn_addRowsToMenu(menu, rows);
	return menu;
}

+ (NSMenuItem *)cg_itemForID:(NSInteger)identifier inMenu:(NSMenu *)menu
{
	NSInteger next_id = 1;

	if (menu == nil) {
		return nil;
	}
	return fn_itemForID(menu, &next_id, identifier);
}

@end
