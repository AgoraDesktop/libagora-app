/*
 * AGComboListView.m — one door, answered from the item's own state.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import "AGComboListView.h"
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

@end
