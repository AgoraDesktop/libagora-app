/*
 * NSMenuView.h — the view that lays out a menu's items and draws them.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE CALLER `NSMenuItemCell` WAS WRITTEN FOR.** This tree had the menu, the items and the CELL — 1,900 lines of
 * working tracking, item data and per-item geometry — and no VIEW. That is why `NSMenu -menuRepresentation`
 * refused by name, and why a tracked menu painted a panel, its separators and a blue highlight, and NOT ONE
 * TITLE: the class that arranges cells into rows did not exist, so nothing ever called a cell's drawing.
 *
 * TWO ORIENTATIONS, AND THEY ARE ONE CLASS ON THE MAC. Vertical is a dropdown — the rows of a poppped-up menu.
 * Horizontal is the menu BAR — the same items as a row of titles across the top of the screen. `-isHorizontal`
 * says which, and it is the reason the drawing half is a view rather than a function: a hand-drawn panel at a
 * frame can express a dropdown and CANNOT express a bar.
 *
 * WHAT IS NOT HERE YET, AND IT IS THE NEXT ROW: the horizontal layout. `-isHorizontal` answers, and `-drawRect:`
 * lays out vertically whatever that answer is — so a horizontal view draws as a column of rows today, which is
 * wrong and is RECORDED rather than left to be discovered.
 */

#ifndef APPKIT_NSMENUVIEW_H
#define APPKIT_NSMENUVIEW_H

#import <AppKit/NSView.h>
#import <Foundation/NSGeometry.h>

@class NSMenu;
@class NSMenuItem;
@class NSMenuItemCell;
@class NSMutableArray;

/* **THE ROW HEIGHT, DECLARED ONCE.** `NSMenu` measures its own tracking window with it and this view lays its rows
 * out with it, so the two MUST agree: a second copy here is how a menu's window and a menu's contents come to
 * disagree about how tall the menu is. It was a file-static in `NSMenu.m` until a second file needed it. */
extern const CGFloat NSMenuRowHeight;

@interface NSMenuView : NSView
{
@private
	/* **NOT `_menu`, WHICH IS THE SUPERCLASS'S OWN** — `NSView` already carries one for contextual menus, and
	 * this view's menu is a different relationship: it does not own what it draws. */
	NSMenu *_shownMenu;
	NSMutableArray *_cells;		/* one NSMenuItemCell per row, made on demand */
	NSMenuItem *_highlightedItem;
	BOOL _horizontal;
}

- (void)setMenu:(NSMenu *)menu;
- (NSMenu *)menu;

/* THE CELL FOR A ROW, MADE ON FIRST ASK and kept, because a cell carries measured widths and a menu that
 * re-measured every item on every pass would measure the same strings forever. */
- (NSMenuItemCell *)cellForItemAtIndex:(NSInteger)index;

/* THE ROW A ROW OCCUPIES, in this view's own coordinates. Vertical: the menu's FIRST item is the TOP row, so the
 * count runs down from the top and the Cocoa y runs up from the bottom. */
- (NSRect)rectForRowAtIndex:(NSInteger)index;

- (void)setHighlightedItem:(NSMenuItem *)item;
- (NSMenuItem *)highlightedItem;

- (BOOL)isHorizontal;
- (void)setHorizontal:(BOOL)flag;

/* How tall the menu has to be to show every item, which is what its window is sized to. */
- (CGFloat)requiredHeight;

@end

#endif /* APPKIT_NSMENUVIEW_H */
