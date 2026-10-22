/*
 * NSDockMenu.h — an application's dock menu, and the Dock's half of showing it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THIS IS NOT APPLE'S CLASS, AND IT EXISTS BECAUSE TWO PROCESSES HAVE TO AGREE ABOUT A MENU.** On the Mac the
 * Dock is Apple's and asks an application for its tile's items over a private channel; Agora's Dock is a program of
 * its own, and the only channel there is is the window server's. So the two halves of this class are the two
 * directions of that conversation, one per side:
 *
 *   1. THE APPLICATION publishes the menu `-applicationDockMenu:` answers with, as a DESCRIPTION — a property list
 *      shaped JSON document naming each item's title, its state and the id it may be chosen by (`see the format
 *      note in the .m`). It is the answer to `agora_window.dock_menu_requested`, sent with
 *      `AGWindowSetDockMenu`.
 *
 *   2. THE DOCK asks for that description, waits for it, and builds an `NSMenu` out of it: the same items, in the
 *      same order, each carrying the application's id in `-representedObject` so the Dock can tell the
 *      application's rows from its own. The Dock then adds its own items under them — Quit is the Dock's, not the
 *      application's — and pops the whole panel up. A row the person picks that carries an id goes back through
 *      `+dispatchActionForItem:toApplication:`, and the APPLICATION sends its own action.
 *
 * **WHY THE MENU IS THE DOCK'S TO DRAW AND NOT THE APPLICATION'S.** Two windows cannot be one panel. An
 * application cannot draw at the Dock's edge, inside the Dock's window, under the Dock's items — and a menu
 * assembled out of two processes' panels would be two panels that look like one only while nothing moves. Apple's
 * answer is the same: the Dock draws the menu, the application says what is on it.
 *
 * **AND WHY THE ROUND TRIP IS NOT CACHED.** A tile's menu is a picture of what the application can do AT THIS
 * MOMENT — "Open Recent" changes with the documents, a Play/Pause row changes with the player — which is why
 * `-applicationDockMenu:` is a METHOD on Apple's delegate and not a stored property. Asking when the menu is about
 * to be shown is the only moment the answer is certain to be true.
 */
#ifndef APPKIT_NSDOCKMENU_H
#define APPKIT_NSDOCKMENU_H

#import <Foundation/Foundation.h>
#import <AppKit/NSMenu.h>

@class NSRunningApplication;

/* **THE DOCK WAITS THIS LONG FOR AN ANSWER, AND THE NUMBER IS A DECISION.** Half a second is far longer than a
 * round trip between two processes on one machine — the application is idle and the window server is between them —
 * and far shorter than a person will hold a right-click before wondering whether it worked. An application that
 * does not answer in that window (a hung one, or one that implemented nothing and never replies) gets the Dock's
 * own items alone, which is what the panel would have shown anyway. */
#define NSDOCKMENU_TIMEOUT 0.5

@interface NSDockMenu : NSObject

/* ============================================================================================ *
 * THE DOCK'S HALF.
 * ============================================================================================ */

/* **ASK AN APPLICATION FOR ITS TILE'S MENU.** `application` is the tile's application; the ask is addressed to its
 * frontmost window, because a window id is the only name the two sides share. Answers an AUTORELEASED menu whose
 * items are the application's — each carrying an `NSNumber` id in `-representedObject` — or nil when the application
 * has no dock menu, is not running, or did not answer inside `NSDOCKMENU_TIMEOUT`.
 *
 * **THE ANSWER IS THE APPLICATION'S AND THE PANEL IS THE CALLER'S**, which is why this returns the application's
 * items ALONE: what goes under them (Quit, and whatever a shell grows) belongs to the shell, and a menu that
 * arrived with somebody else's rows mixed in could not be told apart from one that did not.
 *
 * CALLING THIS DISPATCHES while it waits, because the answer arrives on the same connection as everything else —
 * a caller must be somewhere it can afford that, which a right-click handler is. */
+ (nullable NSMenu *)menuForApplication:(nullable NSRunningApplication *)application;

/* **AND THE SAME QUESTION ABOUT A WINDOW, WHICH IS WHAT THE TWO DOORS BECOME ONE LAYER DOWN.** A tile's application
 * is what the Dock HAS, and a window id is what it can SAY; this is the ask in the vocabulary the protocol speaks,
 * and the door a test drives when the process asking is also the process answering. */
+ (nullable NSMenu *)menuForWindowID:(unsigned int)windowID;

/* **AND THE ROW'S WAY HOME.** The person chose the item the application published under `item`; the application
 * finds the `NSMenuItem` it gave that id and sends its action, exactly as its own tracking loop would have. A
 * caller holds the item's id in its `-representedObject` — that is the whole contract between the two halves of
 * this class, and the reason the Dock does not need to know what an item MEANS. */
+ (void)dispatchActionForItem:(NSInteger)item toApplication:(nullable NSRunningApplication *)application;
+ (void)dispatchActionForItem:(NSInteger)item toWindowID:(unsigned int)windowID;

/* ============================================================================================ *
 * THE FORMAT, AND ITS TWO CONVERSIONS.
 *
 * **A JSON ARRAY OF ROWS, EACH A DICTIONARY, AND ONLY WHAT THE DOCK CAN READ BACK.** A row is
 *
 *     { "title": <string>, "enabled": <bool>, "state": <number>, "id": <number>, "submenu": [ <row>, … ] }
 *
 * and a separator is `{ "separator": true }`. `id` is present exactly when the row may be CHOSEN — a separator and
 * a row that opens a submenu have none — and the ids are assigned by the description, in the order a walk of the
 * menu finds the rows: 1, 2, 3, … The Dock sends one back and the application finds it by walking in the same
 * order, so the two sides agree without a table to keep in step.
 *
 * **AND NOTHING ELSE CROSSES, WHICH IS THE TREE'S RULE ABOUT FIELDS WITH NO READER.** A key equivalent, an image, a
 * hidden flag or a tag would all be a claim the Dock had to honour and a menu it had to draw differently; the four
 * above are what a row of a dock menu is. A field this class cannot carry is not lost silently by a caller who
 * reads this note: an item's action and its target never cross at all, because they are the application's own
 * objects and the id is what stands in for them.
 * ============================================================================================ */
+ (nullable NSString *)cg_descriptionForMenu:(nullable NSMenu *)menu;
+ (nullable NSMenu *)cg_menuWithDescription:(nullable NSString *)description;

/* **AND THE ROW AN ID NAMES**, found by walking the same tree in the same order the description was written in. This
 * is the application's half of `+dispatchActionForItem:toApplication:`: the id came back from the Dock and this
 * turns it into the `NSMenuItem` whose action can be sent. nil when the menu has been edited since the answer and the
 * id names nothing — a stale pick, and doing nothing is the honest answer to it. */
+ (nullable NSMenuItem *)cg_itemForID:(NSInteger)identifier inMenu:(nullable NSMenu *)menu;

@end

#endif /* APPKIT_NSDOCKMENU_H */
