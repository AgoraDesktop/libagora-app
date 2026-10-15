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

/* **AND THE AIR A DROPDOWN KEEPS BETWEEN ITS PANEL'S EDGE AND ITS ROWS.** `NSMenu` sizes its window with it and this
 * view insets its rows by it, for the same reason the row height is shared: a second copy of the number is how a
 * menu's window and a menu's contents come to disagree about how tall the menu is. THE BAR HAS NO SUCH PADDING —
 * its height is the server's strip, and a seam there is exactly what the strip exists to avoid. */
extern const CGFloat NSMenuPanelPadding;

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

/* **AND WHETHER A ROW WEARS THE MARK WITHOUT THE POINTER BEING ON IT — THE ONE THING A LIST INSIDE A MENU'S SESSION
 * NEEDS THAT A MENU DOES NOT.** A menu marks the row under the pointer and nothing else; a LIST also shows the row its
 * owner currently holds, which is a different fact and a different item. The highlight is painted by THIS VIEW (see
 * `-drawRect:`), so the question belongs here rather than in a cell: the chip's shape, its colour and its inset are the
 * view's, and a subclass that wants a row marked answers this instead of redrawing the panel.
 *
 * THE DEFAULT IS NO, so every menu in the tier is unaffected by the door existing. */
- (BOOL)cg_isItemMarked:(nullable NSMenuItem *)item;

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

/* ============================================================================================ *
 * AND THE ONE THING A MENU BAR STILL CANNOT DO, WRITTEN DOWN AS A DECIDED PLAN.                  *
 * ============================================================================================ *
 *
 * **DRAGGING ACROSS THE BAR WHILE THE BUTTON IS HELD TURNS A MENU INSTEAD OF MOVING IT.** On the Mac you press
 * `File`, slide to `View` and the menu under the pointer changes without releasing. Here the menu closes and you have
 * to click again.
 *
 * WHY, EXACTLY: the opened menu's tracking loop OWNS THE EVENTS while it is up, so this view is blocked inside the
 * call that opened it and never sees the movement. The bar cannot switch a menu whose events it is not given.
 *
 * AND WHY IT IS NOT A PATCH: the half-measure — let the menu end on a drag and have this view re-open for whatever
 * the pointer is over — WAS TRIED, and it produces exactly what was reported: the session ends on the smallest
 * movement, the dropdown is ordered out and built again, and a hand that jitters destroys and remakes the menu
 * several times a second. A menu that flickers is worse than one that does not follow.
 *
 * THE SHAPE OF THE FIX, so the next attempt starts from a decision rather than a derivation:
 *
 *   1. `NSMenu` gains a door that BEGINS A SESSION WITHOUT RUNNING IT — the tracking window made, the session marked,
 *      the first repaint done, and the loop left to the caller. Everything `-popUpMenuPositioningItem:` does up to
 *      the loop, and nothing after it.
 *   2. THIS VIEW becomes the session's owner: it fetches events, calls `-[NSApplication updateWindows]` (a tracking
 *      loop that stops painting is its own bug — see `NSMenu.m`), and dispatches —
 *        - an event in the open menu's window goes to `-cg_trackOneEvent:`, which already handles rows, submenus,
 *          picks and Escape;
 *        - an event over the BAR moves the session: end the open menu, begin the one under the pointer, and keep
 *          the chip down across the change so nothing flickers;
 *        - a press or a release with no menu under it ends the session.
 *   3. AND THE RULE ALREADY BUILT FOR SUBMENUS KEEPS WORKING UNCHANGED: a menu whose PARENT IS TRACKING is the
 *      parent's to drive, so a child opened by hovering inside an open menu never starts a loop of its own — which
 *      is the same question `NSMenu -popUpMenuPositioningItem:` asks before it tracks, and the reason it can be
 *      reused here rather than re-decided.
 *
 * IT IS A PIECE OF WORK AND NOT A LINE, and it is the last one between this menu bar and the Mac's. */

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
