/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSForm.h — A ONE-COLUMN MATRIX OF `NSFormCell`s: A FORM.
 *
 * **THE FORM IS A MATRIX WITH A SHAPE AND A SET OF EDITORIAL POLICIES**, which is why this class is small: it is ONE
 * column, its cells are `NSFormCell`s, its mode is RADIO (an entry is chosen, not a set of them), and every door below
 * is either "do this to the cell at index i" or "do this to every cell". The row index IS the entry index, which is
 * the whole of the address arithmetic; `-cellAtIndex:` and its three siblings exist because Apple publishes them and
 * because a form's caller thinks in ENTRIES rather than in rows and columns.
 *
 * **`-addEntry:` IS THE DOOR THAT MAKES ONE**, and it returns the cell it made so a caller can set its value in the
 * same expression: `[[form addEntry:@"Name"] setStringValue:@"Agora"]`. The label is the cell's TITLE and the value is
 * its string — two strings, one cell, exactly as `NSFormCell` documents.
 *
 * **THE FOUR "EVERY CELL" DOORS ARE THE FORM'S EDITORIAL VOICE**, and `-setEntryWidth:` is the interesting one: it
 * fixes the VALUE band's width instead of letting each cell measure its own label, which is what makes a form's
 * fields line up in a column. It is arithmetic over the cells' own widths, so a form resized after it keeps the
 * relationship — which is why `-setFrameSize:` is overridden here rather than inherited.
 *
 * WHAT THIS CLASS DOES NOT DO: a form has no scrolling and no multi-column layout of its own (it is ONE column by
 * definition), and `-setFrameSize:` will not narrow an entry below zero — a form dragged narrower than its entry width
 * clamps the value band rather than drawing backwards.
 *
 * Written from `NSForm.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSFORM_H
#define APPKIT_NSFORM_H

#import <AppKit/NSMatrix.h>

@class NSFormCell;
@class NSFont;

NS_ASSUME_NONNULL_BEGIN

@interface NSForm : NSMatrix <NSSecureCoding>

/* ============================================================================================ *
 * THE ENTRIES.                                                                                  *
 * ============================================================================================ */

/* **ADD AND INSERT TAKE THE LABEL AND ANSWER THE CELL.** The new entry's title is the label; its value is empty; it is
 * a bordered `NSFormCell`, because a form's value band is something a person types into and an unbordered one does not
 * say so. `-insertEntry:atIndex:` places it and grows the form by one row. */
- (NSFormCell *)addEntry:(nullable NSString *)title;
- (NSFormCell *)insertEntry:(nullable NSString *)title atIndex:(NSInteger)index;
- (void)removeEntryAtIndex:(NSInteger)index;

/* THE ENTRY DOORS, BY INDEX — the same four questions the matrix asks by (row, column), with the column removed. */
- (nullable NSFormCell *)cellAtIndex:(NSInteger)index;
- (void)drawCellAtIndex:(NSInteger)index;
- (void)selectTextAtIndex:(NSInteger)index;
- (NSInteger)indexOfSelectedItem;
- (NSInteger)indexOfCellWithTag:(NSInteger)tag;

/* ============================================================================================ *
 * THE FORM'S VOICE: EVERY CELL AT ONCE.                                                         *
 * ============================================================================================ */

/* **THE LABEL'S FONT AND THE VALUE'S ARE TWO DOORS**, not one: a form's labels are emphasized and its values are not,
 * which is exactly the distinction `NSFormCell` keeps two fonts for. `-setTextFont:` sets the cell's own `-font`. */
- (void)setTitleFont:(nullable NSFont *)font;
- (void)setTextFont:(nullable NSFont *)font;
- (void)setTitleAlignment:(NSTextAlignment)mode;
- (void)setTextAlignment:(NSTextAlignment)mode;
- (void)setTitleBaseWritingDirection:(NSWritingDirection)mode;
- (void)setTextBaseWritingDirection:(NSWritingDirection)mode;

/* **THE TWO WIDTHS A FORM HAS, AND THEY ARE DIFFERENT.** `-setEntryWidth:` fixes the VALUE band and lets each label
 * take the rest; `-setInterlineSpacing:` fixes the air BETWEEN entries. Both leave the cell height alone, because a
 * form's rows are as tall as its cells and that is the caller's `-setCellSize:` to decide. */
- (void)setEntryWidth:(CGFloat)width;
- (void)setInterlineSpacing:(CGFloat)spacing;

/* AND THE TWO FACE FLAGS, APPLIED TO EVERY CELL — a form of bezeled entries is the whole-cell look, and a form of
 * bordered ones is the era's older field. */
- (void)setBezeled:(BOOL)flag;
- (void)setBordered:(BOOL)flag;

/* **A FORM RESIZES ITS ENTRIES WHEN ITS FRAME CHANGES**, which is Apple's rule and the reason this is a door on the
 * form rather than on the matrix: one column means a width change is entirely the entry's business. */
- (void)setFrameSize:(NSSize)newSize;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSFORM_H */
