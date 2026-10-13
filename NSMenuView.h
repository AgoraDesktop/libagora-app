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
 * AND BOTH ORIENTATIONS ARE IMPLEMENTED. A vertical view draws rows the width of the menu, stacking DOWN from the
 * top; a horizontal one draws columns the width of each item's title, running RIGHT from the left edge, and does
 * NOT draw key equivalents — a menu bar shows titles, and the key equivalents belong to the menu each title opens.
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

/* **THE BOX AN ITEM OCCUPIES, AND IT IS NOT CALLED A ROW** because in a bar there are none: vertical is a ROW of
 * the menu, horizontal is a COLUMN of the bar, and one door answers both rather than two doors that callers have
 * to choose between. Vertical: the menu's FIRST item is the TOP row, so the index counts down while the Cocoa y
 * counts up from the bottom. Horizontal: the FIRST item is the LEFTMOST column, and the widths are the items'. */
- (NSRect)rectForItemAtIndex:(NSInteger)index;

/* **A CLICK ON ONE OF THE BAR'S TITLES OPENS THAT TITLE'S MENU.** Before this the bar was a picture: `NSWindow
 * -sendEvent:` hit-tested correctly and delivered `-mouseDown:` to this view, and the view had no such method, so
 * every click on the menu bar did nothing at all — the responder chain forwarded it to the next responder and the
 * next responder was the application, which had no opinion either.
 *
 * IT IS THE BAR'S OWN DOOR BECAUSE THE BAR IS WHAT KNOWS WHERE ITS ITEMS ARE: `-rectForItemAtIndex:` is this
 * view's arithmetic, and the item under a point is a question only this view can answer. A DROPDOWN forwards to
 * `super`, because a dropdown is tracked by `NSMenu` and its rows are not click-to-open. */
- (void)mouseDown:(NSEvent *)event;

/* **AND A CLICK ON AN INACTIVE BAR OPENS THE MENU RATHER THAN ONLY WAKING THE WINDOW.** The Mac's own behaviour,
 * and the reason `-acceptsFirstMouse:` exists at all: the click that brings a window forward should do what the
 * person meant it to do, not be spent on the wake-up. */
- (BOOL)acceptsFirstMouse:(nullable NSEvent *)event;
- (NSMenuItem *)highlightedItem;

- (BOOL)isHorizontal;
- (void)setHorizontal:(BOOL)flag;

/* How big the menu has to be to show every item, which is what its window is sized to: a dropdown is as TALL as
 * its rows and a bar is as WIDE as its columns, and the caller knows which it is building. */
- (CGFloat)requiredHeight;
- (CGFloat)requiredWidth;

/* The width of one item's column in a bar, which is its title and the air either side of it — A MENU BAR'S ITEMS
 * ARE AS WIDE AS THEIR TITLES, which is why a bar's layout cannot be arithmetic alone and has to ask a cell. */
- (CGFloat)widthForItemAtIndex:(NSInteger)index;

@end

#endif /* APPKIT_NSMENUVIEW_H */
