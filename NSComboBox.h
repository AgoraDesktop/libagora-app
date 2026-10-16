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

@class NSComboBoxCell;

NS_ASSUME_NONNULL_BEGIN

@interface NSComboBox : NSTextField

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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOMBOBOX_H */
