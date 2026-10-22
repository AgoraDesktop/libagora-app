/*
 * AGComboListView.m — one door, answered from the item's own state.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
#import "AGComboListView.h"
#import "AGComboListCell.h"
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSCell.h>	/* NSOnState, the item state this mark reads */

@implementation AGComboListView

/* **AND THE HELD ROW IS THE ONE WHOSE ITEM IS ON, WHICH IS THE MENU'S OWN WAY OF SAYING "THIS ONE".** A menu item's
 * `-state` is what a menu uses to show that an item is the current choice, and a combo box's list is built with the
 * held row's item turned on — so the answer needs no second channel between the cell and the view, no index stored on
 * the view, and nothing to keep in step: the item the cell already had to mark is the item that gets drawn marked.
 *
 * A CHECKMARK IS WHAT A MENU DRAWS FOR THAT STATE, and it is not what this draws — see the header for why. The state
 * is read here as "this is the held row" and rendered as the chip the pointer also gets, because the chip is this
 * session's mark; a checkmark would need a state IMAGE, and `NSMenuItemCell` measures that column from the image's own
 * width, so an item with no image gets a zero-width column and no mark at all — MEASURED, which is why the state is
 * not simply handed to the cell and left there. */
- (BOOL)cg_isItemMarked:(NSMenuItem *)item
{
	return item != nil && [item state] == NSOnState;
}

/* **AND THE MARK IS THE WHOLE ROW RATHER THAN A CHIP INSIDE IT.** This is the one thing a list's row does that a
 * menu's does not, and it is a question about PAINTING, so it is answered here with the other mark question rather
 * than by the cell: the chip's colour and its radius live in the view's `-drawRect:`, and a cell has no say in them.
 * The row needs no inset — the rows already sit inside the panel's own padding — so the answer is the row itself. */
- (NSRect)cg_markRectForRow:(NSRect)row
{
	return row;
}

/* **AND THE ROWS ARE THIS LIST'S CELL, WHICH IS WHERE A LIST'S ROW DIFFERS FROM A MENU'S.** See `AGComboListCell` for
 * the three doors it answers; what matters here is that the class is ASKED FOR rather than named — a class named at
 * its construction site is a class nobody can replace, which is the same correction `NSMenu -cg_setMenuViewClass:`
 * makes one level up. AND IT IS A +1 DOOR, like the one it overrides — see that door's note for what an autoreleased
 * cell cost the first time a list was drawn. */
- (NSMenuItemCell *)cg_newItemCell
{
	return [[AGComboListCell alloc] initTextCell:@""];
}

@end
