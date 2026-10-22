/*
 * NSTabView.h — A SET OF PANES WITH TABS ALONG ONE EDGE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A TAB VIEW IS A SELECTION OVER VIEWS, AND THE TABS ARE ITS LABELS.** It holds an ordered list of `NSTabViewItem`s; each
 * item carries a VIEW and a LABEL; exactly one item is selected, and its view is the one in the tab view's own hierarchy.
 * Changing the selection is what swaps which child is showing — a tab view does not hide the others, it REMOVES them, which
 * is the difference between a tab view and a pile of hidden views.
 *
 * **THE TABS SIT ON ONE OF FOUR EDGES, OR NOWHERE.** `NSTabViewType` names the four bezel-border placements and three
 * borderless kinds; `-contentRect` is the rectangle that is left for the selected view, which is the bounds less the border
 * and less the TAB STRIP on whichever edge the type puts it. The strip's height is the label's own line height plus the
 * padding a tab needs, so a view with a bigger font has a bigger strip — one number, not two.
 *
 * **THE DELEGATE IS ASKED BEFORE THE CHANGE**, which is what makes a tab view refuseable: `-tabView:shouldSelectTabViewItem:`
 * answers NO and the selection does not move; `-tabView:willSelectTabViewItem:` is the notification that it is about to; and
 * `-tabView:didSelectTabViewItem:` is the one after. The protocol is declared here (Apple's home for it) and the view's
 * delegate is typed with it — so the three messages are a contract rather than an informal spelling.
 */
#ifndef APPKIT_NSTABVIEW_H
#define APPKIT_NSTABVIEW_H

#import <AppKit/NSView.h>
/* FOR `NSControlSize` AND `NSControlTint`, the two 10.0 appearance doors this class stores. They live in `NSCell.h`, which
 * is where a control's size and tint are declared. */
#import <AppKit/NSCell.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTabViewItem;
@class NSTabView;
@class NSFont;
@class NSTabView;

/* **WHERE THE TABS GO AND WHAT BORDER IS DRAWN.** The four `…BezelBorder` kinds place the strip and draw a bezel round the
 * content; `NSNoTabs…` draw a border with no strip at all. */
typedef NSUInteger NSTabViewType;
enum {
	NSTopTabsBezelBorder = 0,
	NSLeftTabsBezelBorder = 1,
	NSBottomTabsBezelBorder = 2,
	NSRightTabsBezelBorder = 3,
	NSNoTabsBezelBorder = 4,
	NSNoTabsLineBorder = 5,
	NSNoTabsNoBorder = 6
};

/* **AND HOW A TAB LOOKS**: the selected one, one being pressed, and the rest. */
typedef NSUInteger NSTabState;
enum {
	NSSelectedTab = 0,
	NSPressedTab = 1,
	NSBackgroundTab = 2
};

/* ==================================================================================================================
 * THE ITEM: A VIEW AND A LABEL.
 * ================================================================================================================ */

@interface NSTabViewItem : NSObject
{
	@public
	/* **`@public` FOR THE TAB VIEW'S OWN USE**, which is the same rule `NSFont`'s substrate ivar states: the view is the only
	 * thing that sets an item's state and adopts its pane, and a private setter pair would be two doors to keep in step with
	 * three fields. A caller reaches these through the accessors below, not through the ivars. */
	id _identifier;			/* RETAINED: whatever the caller used to name it */
	NSString *_label;		/* RETAINED */
	NSView *_view;			/* RETAINED: the pane this item shows */
	NSColor *_color;		/* RETAINED */
	NSString *_toolTip;		/* RETAINED */
	NSView *_initialFirstResponder;	/* BORROWED */
	NSTabView *_tabView;		/* NOT RETAINED: the view owns its items */
	NSTabState _tabState;
}

/* THE ONE WAY IN: an identifier is what `-selectTabViewItemWithIdentifier:` and
 * `-indexOfTabViewItemWithIdentifier:` look up, and Apple's initialiser takes nothing else. */
- (instancetype)initWithIdentifier:(nullable id)identifier;

- (nullable id)identifier;
- (void)setIdentifier:(nullable id)identifier;

/* THE VISIBLE LABEL AND THE PANE. Setting the view does NOT install it: the tab view installs the SELECTED item's view, and
 * an item that is not selected has no view in the hierarchy at all. */
- (nullable NSString *)label;
- (void)setLabel:(nullable NSString *)label;
- (nullable NSView *)view;
- (void)setView:(nullable NSView *)view;

- (nullable NSColor *)color;
- (void)setColor:(nullable NSColor *)color;
- (nullable NSString *)toolTip;
- (void)setToolTip:(nullable NSString *)toolTip;
- (nullable NSView *)initialFirstResponder;
- (void)setInitialFirstResponder:(nullable NSView *)view;

/* **WHICH VIEW OWNS IT AND WHAT STATE ITS TAB IS IN.** `-tabState` is the view's answer, not the caller's: an item is
 * selected, pressed or in the background because the tab view decided so. */
- (nullable NSTabView *)tabView;
- (NSTabState)tabState;

/* THE TAB'S OWN INK AND MEASURE: how big its label is, and the label drawn into a rectangle. The tab view calls both, so a
 * subclass that draws its own label needs to override only these. */
- (NSSize)sizeOfLabel:(BOOL)shouldTruncateLabel;
- (void)drawLabel:(BOOL)shouldTruncateLabel inRect:(NSRect)tabRect;

@end

/* ==================================================================================================================
 * THE DELEGATE, WHICH IS ASKED BEFORE THE CHANGE.
 * ================================================================================================================ */

@protocol NSTabViewDelegate <NSObject>
@optional
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(nullable NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(nullable NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(nullable NSTabViewItem *)tabViewItem;
@end

/* ==================================================================================================================
 * THE VIEW.
 * ================================================================================================================ */

@interface NSTabView : NSView
{
	NSMutableArray *_items;		/* RETAINED: NSTabViewItem objects, in order */
	NSTabViewItem *_selectedItem;	/* NOT RETAINED: the array owns it */
	NSTabViewType _tabViewType;
	NSFont *_font;			/* RETAINED */
	id _delegate;			/* NOT RETAINED: this tree's rule for every delegate */
	BOOL _drawsBackground;
	BOOL _allowsTruncatedLabels;
	NSSize _minimumSize;
}

/* THE ITEMS: the list, the count, and the two ways to add one (the end, or a place). */
- (NSArray *)tabViewItems;
- (NSUInteger)numberOfTabViewItems;
- (nullable NSTabViewItem *)tabViewItemAtIndex:(NSInteger)index;
- (void)addTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)insertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(NSInteger)index;
- (void)removeTabViewItem:(NSTabViewItem *)tabViewItem;

/* BY IDENTITY, NOT EQUALITY — two items can hold the same label and still be two panes. */
- (NSInteger)indexOfTabViewItem:(NSTabViewItem *)tabViewItem;
- (NSInteger)indexOfTabViewItemWithIdentifier:(id)identifier;

/* THE SELECTION, IN FIVE SPELLINGS: by item, by index, by identifier, the first and the last, and the two that step (which
 * WRAP, because a tab strip is a ring and Apple's own do). */
- (nullable NSTabViewItem *)selectedTabViewItem;
- (void)selectTabViewItem:(nullable NSTabViewItem *)tabViewItem;
- (void)selectTabViewItemAtIndex:(NSInteger)index;
- (void)selectTabViewItemWithIdentifier:(id)identifier;
- (void)selectFirstTabViewItem:(nullable id)sender;
- (void)selectLastTabViewItem:(nullable id)sender;
- (void)selectNextTabViewItem:(nullable id)sender;
- (void)selectPreviousTabViewItem:(nullable id)sender;
/* The action a segmented control or a menu item sends: the sender's TAG is the index. */
- (void)takeSelectedTabViewItemFromSender:(nullable id)sender;

/* THE GEOMETRY: what is left for the selected view, where a point lands, and the least size the tabs need. */
- (NSRect)contentRect;
- (nullable NSTabViewItem *)tabViewItemAtPoint:(NSPoint)point;
- (NSSize)minimumSize;

/* THE FACE: which edge the tabs sit on, what font and background it uses, and whether labels may be cut short. */
- (NSTabViewType)tabViewType;
- (void)setTabViewType:(NSTabViewType)tabViewType;
- (nullable NSFont *)font;
- (void)setFont:(nullable NSFont *)font;
- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;
- (BOOL)allowsTruncatedLabels;
- (void)setAllowsTruncatedLabels:(BOOL)flag;

/* THE DELEGATE AND THE TWO 10.0 CONTROL APPEARANCE DOORS, stored and answered. */
- (nullable id <NSTabViewDelegate>)delegate;
- (void)setDelegate:(nullable id <NSTabViewDelegate>)delegate;
- (NSControlSize)controlSize;
- (void)setControlSize:(NSControlSize)controlSize;
- (NSControlTint)controlTint;
- (void)setControlTint:(NSControlTint)controlTint;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTABVIEW_H */
