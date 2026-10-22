/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSTableColumn.h — one column of a table: its identifier, width, and the two cells that draw it.
 *
 * A column is the unit `NSTableView` measures and lays out. It owns a HEADER CELL (what the header view draws) and a
 * DATA CELL (what a row draws), and the width it reports is the width the table uses. The min/max pair is the range a
 * user resize is clamped to, exactly as it is on the Mac; `-setWidth:` clamps too, so a programmatic width cannot
 * escape the range the column declared.
 *
 * Written from `NSTableColumn.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSTABLECOLUMN_H
#define APPKIT_NSTABLECOLUMN_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSCell;
@class NSSortDescriptor;
@class NSString;
@class NSTableView;

/* THE RESIZING MASK, WITH THE ERA'S VALUES. `Autoresizing` is the table's permission to change the width when it
 * sizes its columns, `UserResizing` is the pointer's permission on the divider — two different questions that a
 * single "resizable" flag would conflate. */
enum {
	NSTableColumnNoResizing = 0,
	NSTableColumnAutoresizingMask = (1 << 0),
	NSTableColumnUserResizingMask = (1 << 1)
};

@interface NSTableColumn : NSObject <NSSecureCoding>
{
	id _identifier;				/* COPIED: the name the delegate and the table find the column by */
	NSTableView *_tableView;		/* NOT RETAINED: the table owns its columns */
	CGFloat _width;
	CGFloat _minWidth;
	CGFloat _maxWidth;
	NSCell *_headerCell;			/* RETAINED: what the header view draws */
	NSCell *_dataCell;			/* RETAINED: what a row draws, and the cell a data source fills */
	NSUInteger _resizingMask;
	BOOL _editable;
	BOOL _hidden;
	NSString *_headerToolTip;		/* COPIED */
	NSSortDescriptor *_sortDescriptorPrototype;	/* RETAINED */
}

- (instancetype)initWithIdentifier:(id)identifier;
- (void)setIdentifier:(id)identifier;
- (id)identifier;

/* THE TABLE THIS COLUMN IS IN, or nil. Not retained: a column is owned by its table. */
- (void)setTableView:(nullable NSTableView *)tableView;
- (nullable NSTableView *)tableView;

/* THE WIDTH AND ITS RANGE. A width set outside the range is CLAMPED rather than refused, and a range change pulls a
 * width that no longer fits back inside it. */
- (void)setWidth:(CGFloat)width;
- (CGFloat)width;
- (void)setMinWidth:(CGFloat)minWidth;
- (CGFloat)minWidth;
- (void)setMaxWidth:(CGFloat)maxWidth;
- (CGFloat)maxWidth;

/* THE TWO CELLS. The defaults are an `NSTableHeaderCell` whose title is the identifier and an unbordered
 * `NSTextFieldCell` for the values. `-dataCellForRow:` is the table's hook for a row-specific cell; the default is
 * the column's one. */
- (void)setHeaderCell:(NSCell *)cell;
- (NSCell *)headerCell;
- (void)setDataCell:(NSCell *)cell;
- (NSCell *)dataCell;
- (NSCell *)dataCellForRow:(NSInteger)row;

/* EDITABILITY, SIZE AND THE RESIZING PERMISSION. */
- (void)setEditable:(BOOL)flag;
- (BOOL)isEditable;
- (void)sizeToFit;
- (void)setResizingMask:(NSUInteger)resizingMask;
- (NSUInteger)resizingMask;

/* **AND THE BOOLEAN SPELLING, WHICH IS THE MASK'S USER BIT RATHER THAN A SECOND FIELD.** Apple's `-isResizable` is "may
 * the user resize this column", which is exactly `NSTableColumnUserResizingMask`; two fields would be two answers to one
 * question, and a view that set one while a header drag read the other would resize a column it was told not to. */
- (BOOL)isResizable;
- (void)setResizable:(BOOL)flag;

/* THE SORT PROTOTYPE. The header turns a click into a descriptor from this key; nil means the column does not sort. */
- (void)setSortDescriptorPrototype:(nullable NSSortDescriptor *)sortDescriptor;
- (nullable NSSortDescriptor *)sortDescriptorPrototype;

/* THE HEADER'S TOOL TIP AND THE HIDDEN FLAG. A hidden column keeps its place in `-tableColumns` but takes no width
 * and draws nothing, which is what makes showing it again cheap. */
- (void)setHeaderToolTip:(nullable NSString *)string;
- (nullable NSString *)headerToolTip;
- (BOOL)isHidden;
- (void)setHidden:(BOOL)hidden;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTABLECOLUMN_H */
