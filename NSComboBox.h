/*
 * NSComboBox.h — a field with a chip, a list, and one triangle.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **EVERY DOOR HERE IS A FORWARD**, in the shape `NSPopUpButton` records for its own: a cell can decide and draw, and
 * what a view contributes is a coordinate space and a window to put a list in. Unlike the pop-up there is no press to
 * hand over yet — the list this control's chip promises does not open, for the reason the cell's header gives — so
 * every door below ends at the cell and nothing here has behaviour of its own.
 *
 * **AND THE BASE IS `NSControl` RATHER THAN APPLE'S `NSTextField`.** Apple builds a combo box on a text field, which
 * is where its editing and its string live; this tier has no `NSTextField` and no text-field CELL, so the class
 * starts where the tier's control layer starts — the same choice, for the same reason, the cell's header records one
 * level down, and the row that closes it is the field cell that would make this control editable.
 */
#ifndef APPKIT_NSCOMBOBOX_H
#define APPKIT_NSCOMBOBOX_H

#import <AppKit/NSControl.h>

@class NSComboBoxCell;

NS_ASSUME_NONNULL_BEGIN

@interface NSComboBox : NSControl

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
