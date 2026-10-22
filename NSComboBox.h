/*
 * NSComboBox.h — a field with a chip, a list, and one triangle.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **ALMOST EVERY DOOR HERE IS A FORWARD**, in the shape `NSPopUpButton` records for its own: a cell can decide and
 * draw, and what a view contributes is a coordinate space and a window to put a list in. THE PRESS IS THE ONE DOOR
 * THAT IS NOT — a combo box is two things in one frame, so `-mouseDown:` asks the cell where its CHIP is and either
 * opens the list or hands the press to the field base below — and that split is the class's whole behaviour.
 *
 * **AND THE BASE IS APPLE'S NOW: `NSTextField`.** This class started at `NSControl`, and the header said why in as
 * many words — the tier had no `NSTextField` and no text-field CELL, so a combo box began where the control layer
 * began and the row that would close it was named. BOTH HAVE SINCE ARRIVED: `NSTextFieldCell` is what
 * `NSComboBoxCell` already derives from, and `NSTextField` is the control above it. So the hierarchy matches Apple's,
 * and the ONE thing the base changes is the press — a click in the field opens a session through `NSTextField`'s own
 * `-mouseDown:` rather than through a copy of that logic kept here — while the CHIP's press stays this class's,
 * because opening a list is the one thing a text field cannot do.
 */
#ifndef APPKIT_NSCOMBOBOX_H
#define APPKIT_NSCOMBOBOX_H

#import <AppKit/NSTextField.h>

@class NSComboBox;
@class NSComboBoxCell;

NS_ASSUME_NONNULL_BEGIN

/* **THE VIEW'S DATA SOURCE, WHICH IS THE CELL'S PROTOCOL ONE NOUN UP.** Apple keeps two protocols because the two
 * classes ask about themselves — `-numberOfItemsInComboBox:` here and `-numberOfItemsInComboBoxCell:` there — and this
 * tier keeps both for the same reason: a source written for a VIEW is handed to a view, and the view is the CELL's
 * source by adapting the three calls (see `NSComboBox`'s `-numberOfItemsInComboBoxCell:`), so neither protocol has to
 * pretend to be the other. THE VIEW DOES NOT RETAIN ITS SOURCE; see the cell's header for the same rule and why. */
@protocol NSComboBoxDataSource <NSObject>
@required
- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox;
- (nullable id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index;
@optional
- (NSUInteger)comboBox:(NSComboBox *)aComboBox indexOfItemWithStringValue:(nullable NSString *)string;
- (nullable NSString *)comboBox:(NSComboBox *)aComboBox completedString:(nullable NSString *)string;
@end

/* **AND THE DELEGATE, WHICH IS A TEXT FIELD'S DELEGATE PLUS FOUR QUESTIONS ABOUT THE LIST.** Apple derives it from
 * `NSTextFieldDelegate`, and so does this header: a combo box IS a field, and a caller who already answers the
 * session's questions should not have to write a second delegate to hear about the list.
 *
 * **WHICH OF THE FOUR THIS TIER ACTUALLY SENDS, STATED HERE BECAUSE A PROTOCOL NOBODY SENDS IS A CONTRACT NOBODY
 * HONOURS:** `-comboBoxWillPopUp:` and `-comboBoxWillDismiss:` are sent around the list's session (a press on the
 * chip), and `-comboBoxSelectionDidChange:` is sent when a row is PICKED from that list. `-comboBoxSelectionIsChanging:`
 * is NOT sent: it belongs to the moment the pointer moves over a row, and the highlight walk belongs to the session's
 * view (`NSMenuView`), which has no seam to the menu's owner yet. The message is declared rather than omitted so a
 * caller that implements it compiles against the era's protocol, and the day the walk gets a seam this line changes. */
@protocol NSComboBoxDelegate <NSTextFieldDelegate>
@optional
- (void)comboBoxWillPopUp:(NSNotification *)notification;
- (void)comboBoxWillDismiss:(NSNotification *)notification;
- (void)comboBoxSelectionDidChange:(NSNotification *)notification;
- (void)comboBoxSelectionIsChanging:(NSNotification *)notification;
@end

@interface NSComboBox : NSTextField <NSSecureCoding>
{
	/* **THE ONE PIECE OF STATE A COMBO BOX OWNS RATHER THAN ITS CELL.** Everything a caller thinks of as the box's —
	 * its rows, its selection, the shape of its list — is the cell's, which is why this class had no storage at all
	 * until the data source arrived. A source is the VIEW's because the view's protocol names the view, and the cell's
	 * own source is this view, ADAPTING the three calls: so the object the caller set lives here. NOT RETAINED — see
	 * the protocol above — and NOT ARCHIVED, which is why this class now implements both coding methods below. */
	id _dataSource;		/* NOT RETAINED */
}

- (instancetype)initWithFrame:(NSRect)frameRect;

/* ---- THE LIST -------------------------------------------------------------------------------------- */

- (NSInteger)numberOfItems;
- (void)addItemWithObjectValue:(nullable id)object;
- (void)addItemsWithObjectValues:(nullable NSArray *)objects;
- (void)insertItemWithObjectValue:(nullable id)object atIndex:(NSInteger)index;
- (void)removeAllItems;
- (void)removeItemAtIndex:(NSInteger)index;
- (void)removeItemWithObjectValue:(nullable id)object;
- (nullable id)itemObjectValueAtIndex:(NSInteger)index;
- (nullable NSArray *)objectValues;
- (NSInteger)indexOfItemWithObjectValue:(nullable id)object;

/* ---- WHAT IS CHOSEN -------------------------------------------------------------------------------- */

/* The three spellings of one fact, and the title the box therefore wears — which is the cell's own `-title`, so it is
 * declared here rather than re-derived. See the cell's header for why only the first of these writes. */
- (NSInteger)indexOfSelectedItem;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)selectItemWithObjectValue:(nullable id)object;
- (nullable id)objectValueOfSelectedItem;
- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)aTitle;

/* ---- THE TWO SHAPE FLAGS, WHICH ARE STORED AND OBEY NOTHING YET ------------------------------------- */

- (NSInteger)numberOfVisibleItems;
- (void)setNumberOfVisibleItems:(NSInteger)count;
- (BOOL)completes;
- (void)setCompletes:(BOOL)flag;
- (BOOL)usesDataSource;
- (void)setUsesDataSource:(BOOL)flag;
- (BOOL)isEditable;
- (void)setEditable:(BOOL)flag;

/* ---- THE DATA SOURCE, AND THE TWO TIDINGS ------------------------------------------------------- */

/* **A BOX WITH A SOURCE TAKES ITS ROWS FROM THE SOURCE, AND THE VIEW IS THE CELL'S SOURCE.** The three rows doors that
 * read (count, value, index, completion) go through the cell, and the cell asks ITS source — which is this view — so the
 * adaptation happens once, here, and every row door below inherits it without knowing. The array doors refuse while
 * the source is in use, as the cell's header says. */
- (void)setDataSource:(nullable id <NSComboBoxDataSource>)aSource;
- (nullable id <NSComboBoxDataSource>)dataSource;
- (void)reloadData;
- (void)noteNumberOfItemsChanged;

/* **AND THE DELEGATE IS TYPED AS THE COMBO BOX'S OWN, WHICH IS APPLE'S SPELLING** — a caller with an
 * `id <NSComboBoxDelegate>` should be able to hand it over without a cast. The implementation is the text field's
 * (one ivar, one assign), so these two doors are declared here and inherited below; the type is what changed. */
- (nullable id <NSComboBoxDelegate>)delegate;
- (void)setDelegate:(nullable id <NSComboBoxDelegate>)anObject;

/* ---- THE LIST'S SHAPE, ALL OF IT THE CELL'S ------------------------------------------------------ */

- (CGFloat)itemHeight;
- (void)setItemHeight:(CGFloat)itemHeight;
- (NSSize)intercellSpacing;
- (void)setIntercellSpacing:(NSSize)aSize;
- (BOOL)isButtonBordered;
- (void)setButtonBordered:(BOOL)flag;
/* AND THE THREE THE SESSION HAS NO MECHANISM FOR: refused by name here as they are on the cell. */
- (BOOL)hasVerticalScroller;
- (void)setHasVerticalScroller:(BOOL)flag;
- (void)scrollItemAtIndexToTop:(NSInteger)index;
- (void)scrollItemAtIndexToVisible:(NSInteger)index;

/* AND THE ONE LIST DOOR THAT IS REAL WITHOUT A SCROLLER — it un-chooses, when the index given is the one held. */
- (void)deselectItemAtIndex:(NSInteger)index;

/* **AND THE SEAM THE CELL SENDS THROUGH WHEN A ROW IS PICKED.** `NSComboBoxCell -itemSelected:` is where a pick lands
 * (the list is a menu, and the row's action points there), and the DELEGATE message is the VIEW's to send because the
 * delegate is the view's. So the cell asks its control whether it wants to hear it, by this name, and the view builds
 * the notification. It is public because the cell is a different file and the probe drives the same path; it is named
 * `cg_` because Apple has no such door. */
- (void)cg_didSelectItemAtIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOMBOBOX_H */
