/*
 * NSPopUpButton.h — A BUTTON THAT RAISES A MENU (stage E).
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS CLASS IS FORWARDS PLUS ONE LINE, WHICH IS APPLE'S SHAPE FOR IT.** Everything a popup button KNOWS — the menu,
 * what is chosen, what the items are, where the arrow sits — is `NSPopUpButtonCell`'s, because a menu is a face's
 * business and not a view's. What the view contributes is the one thing a cell cannot do: the CELL draws and decides,
 * the VIEW has a coordinate space and a window, and RAISING A MENU NEEDS BOTH. So `-mouseDown:` is the whole of this
 * class's own behaviour and the rest is forwarding.
 *
 * THE DESIGNATED INITIALISER TAKES THE ONE FACT THE INHERITED ONE CANNOT, which is Apple's and is the same shape
 * `NSPopUpButtonCell -initTextCell:pullsDown:` has: a pull-down is a different button and the difference is visible
 * before any menu exists.
 *
 * `-menu` IS TYPED `id` WHERE APPLE TYPES `NSMenu`, for the reason `NSPopUpButtonCell.h` records: this header does not
 * include `NSMenu.h`, and a file that includes a pop-up button should not have to carry a framework's menu inventory
 * to name one.
 */
#ifndef APPKIT_NSPOPUPBUTTON_H
#define APPKIT_NSPOPUPBUTTON_H

#import <AppKit/NSButton.h>
#import <AppKit/NSPopUpButtonCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSPopUpButton : NSButton <NSSecureCoding>

/* **THE TWO WAYS IN.** `-initWithFrame:` is inherited and means `pullsDown:NO` — a button whose menu is a list of
 * CHOICES, which is what a caller who says nothing means. `-initWithFrame:pullsDown:` is the other one, and a
 * pull-down is a button whose FIRST ITEM IS ITS TITLE: its menu is a list of COMMANDS and choosing one leaves the
 * title where it was. */
- (instancetype)initWithFrame:(NSRect)frameRect pullsDown:(BOOL)pullDown;

/* THE MENU AND ITS SHAPE. `-setMenu:` is the door with work in it — it re-points every item at the cell (see
 * `NSPopUpButtonCell.h`) — and the other two are forwards. */
- (nullable id)menu;
- (void)setMenu:(nullable id)aMenu;
- (BOOL)pullsDown;
- (void)setPullsDown:(BOOL)flag;
- (NSRectEdge)preferredEdge;
- (void)setPreferredEdge:(NSRectEdge)edge;
- (NSPopUpArrowPosition)arrowPosition;
- (void)setArrowPosition:(NSPopUpArrowPosition)position;

/* WHAT IS IN THE MENU. Every one of these is the cell's and the cell's is the menu's; they are here because Apple
 * declares them here, and a caller holding a popup button should not have to reach through it. */
- (void)addItemWithTitle:(NSString *)title;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeAllItems;
- (NSInteger)numberOfItems;
- (nullable id)itemAtIndex:(NSInteger)index;
- (nullable NSArray *)itemArray;
- (nullable id)lastItem;
- (nullable NSString *)itemTitleAtIndex:(NSInteger)index;
- (NSInteger)indexOfItem:(nullable id)item;
- (NSInteger)indexOfItemWithTitle:(NSString *)title;
- (NSInteger)indexOfItemWithTag:(NSInteger)tag;
- (nullable id)itemWithTitle:(NSString *)title;
- (nullable id)itemWithTag:(NSInteger)tag;

/* WHAT IS CHOSEN — an index, an item, or the title the button therefore wears. All three are one fact. */
- (nullable id)selectedItem;
- (void)setSelectedItem:(nullable id)item;
- (NSInteger)indexOfSelectedItem;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)selectItemWithTitle:(NSString *)title;
- (void)selectItemWithTag:(NSInteger)tag;
- (nullable NSString *)titleOfSelectedItem;
- (void)synchronizeTitleAndSelectedItem;

/* **AND THE TITLE, WHICH IS THE CELL'S WITH ONE WRINKLE ON A PULL-DOWN.** `-setTitle:` on a pull-down also moves the
 * menu's first row, because on a pull-down that row IS the title — the cell says so where it overrides the door, and
 * this forwards to it so there is one copy of the rule. */
- (void)setTitle:(nullable NSString *)aTitle;
- (nullable NSString *)title;

/* **THE PRESS, WHICH IS THE ONLY THING HERE THE CELL COULD NOT DO ALONE.** A menu needs a PLACE, and a place is a
 * view's: the cell is handed this button's bounds and this button, and it carries the bottom-left corner out into the
 * space a window frame lives in. THE SESSION BLOCKS WHILE THE APPLICATION IS RUNNING — that is what a menu does —
 * and returns at once with no run loop, which is what makes the behaviour testable offscreen. */
- (void)mouseDown:(nullable NSEvent *)event;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPOPUPBUTTON_H */
