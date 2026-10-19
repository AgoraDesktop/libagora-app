/*
 * NSBrowser.h — a chain of columns: a list, and the next list for the selected row.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS A TABLE-BACKED BROWSER, AND THE TABLES ARE PRIVATE.** Apple's class is a matrix of `NSBrowserCell`s per
 * column; this tree has no `NSMatrix` (and no `NSBrowserCell` before this slice), so each column is an `NSTableView`
 * inside one horizontal `NSScrollView`, and the browser is the table data source and delegate. The PUBLIC surface is
 * the 10.6 one: the delegate answers how many rows a column has, the `-browser:willDisplayCell:atRow:column:` door
 * fills each `NSBrowserCell`, and selecting a row loads the column to its right. The old
 * `-browser:createRowsForColumn:inMatrix:` form is the one part that cannot exist without `NSMatrix` and is named
 * as absent rather than stubbed.
 *
 * **COLUMNS ARE LAID OUT SIDE BY SIDE AND SCROLL HORIZONTALLY.** The vertical direction is shared by the whole
 * browser: the document view is as tall as the tallest column, and all columns move together. That is the shape this
 * tree's scroll view can give without a second scroll per column.
 *
 * Written from `NSBrowser.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSBROWSER_H
#define APPKIT_NSBROWSER_H

#import <AppKit/NSControl.h>

NS_ASSUME_NONNULL_BEGIN

@class NSBrowser;
@class NSBrowserCell;
@class NSColor;
@class NSIndexSet;
@class NSMutableArray;
@class NSCell;
@class NSScrollView;
@class NSTableView;
@class NSString;
@class NSView;

typedef NSInteger NSBrowserColumnResizingType;
enum {
	NSBrowserNoColumnResizing = 0,
	NSBrowserAutoColumnResizing = 1,
	NSBrowserUserColumnResizing = 2
};

typedef NSInteger NSBrowserDropOperation;
enum {
	NSBrowserDropOn = 0,
	NSBrowserDropAbove = 1
};

/* **THE LAST THREE SIZE HOOKS ARE DECLARED AND NOT ASKED IN THIS SLICE.** Rows have the browser's fixed row height
 * and columns its fixed width; `-browser:heightOfRow:inColumn:`, `-browser:shouldSizeColumn:…` and
 * `-browser:sizeToFitWidthOfColumn:` are here because the era's protocol declares them, and a delegate that answers
 * them will be called when those rules arrive rather than now. */
@protocol NSBrowserDelegate <NSObject>
@optional
- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column;
- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column;
- (nullable NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column;
- (BOOL)browser:(NSBrowser *)sender isColumnValid:(NSInteger)column;
- (BOOL)browser:(NSBrowser *)sender selectRow:(NSInteger)row inColumn:(NSInteger)column;
- (nullable NSIndexSet *)browser:(NSBrowser *)sender
    selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes
			      inColumn:(NSInteger)column;
- (CGFloat)browser:(NSBrowser *)sender heightOfRow:(NSInteger)row inColumn:(NSInteger)column;
- (BOOL)browser:(NSBrowser *)sender shouldSizeColumn:(NSInteger)column forUserResize:(BOOL)forUserResize
	  toWidth:(CGFloat)proposedWidth;
- (CGFloat)browser:(NSBrowser *)sender sizeToFitWidthOfColumn:(NSInteger)column;
@end

@interface NSBrowser : NSControl
{
	id <NSBrowserDelegate> _delegate;	/* NOT RETAINED */
	NSMutableArray *_tables;		/* RETAINED: NSTableView, one per column */
	NSMutableArray *_columnCounts;		/* RETAINED: NSNumber rows per column */
	NSMutableArray *_selectedRows;		/* RETAINED: NSNumber, -1 when none */
	NSMutableArray *_titles;		/* RETAINED: NSString or NSNull per column */
	NSScrollView *_scrollView;		/* RETAINED */
	NSView *_documentView;			/* RETAINED */
	Class _cellClass;
	NSCell *_cellPrototype;			/* RETAINED */
	CGFloat _columnWidth;
	CGFloat _minColumnWidth;
	CGFloat _rowHeight;
	CGFloat _titleHeight;
	NSInteger _maxVisibleColumns;
	NSInteger _selectedColumn;
	NSInteger _firstVisibleColumn;
	NSBrowserColumnResizingType _columnResizingType;
	NSString *_pathSeparator;		/* COPIED */
	SEL _doubleAction;
	BOOL _separatesColumns;
	BOOL _allowsMultipleSelection;
	BOOL _allowsEmptySelection;
	BOOL _hasHorizontalScroller;
	BOOL _takesTitleFromPreviousColumn;
	BOOL _acceptsArrowKeys;
	BOOL _sendsActionOnArrowKeys;
	BOOL _inProgrammaticSelection;
	NSColor *_backgroundColor;		/* RETAINED */
}

- (nullable id <NSBrowserDelegate>)delegate;
- (void)setDelegate:(nullable id <NSBrowserDelegate>)delegate;

/* THE TREE. `-loadColumnZero` asks the delegate and builds the first column; a selection builds the next one. */
- (void)loadColumnZero;
- (void)reloadColumn:(NSInteger)column;
- (void)reloadData;

/* SELECTION. A row is a row in a column; -selectedColumn is the column the selection is IN (not the one to its
 * right), and -selectedCell is that row's cell. */
- (NSInteger)selectedColumn;
- (NSInteger)selectedRowInColumn:(NSInteger)column;
- (nullable NSIndexSet *)selectedRowIndexesInColumn:(NSInteger)column;
- (nullable NSCell *)selectedCell;
- (NSArray *)selectedCells;
- (void)selectRow:(NSInteger)row inColumn:(NSInteger)column;
- (void)selectRowIndexes:(NSIndexSet *)indexes inColumn:(NSInteger)column;

/* THE PATH IS THE SELECTED CELLS' STRINGS, joined by `-pathSeparator` (default `/`). */
- (nullable NSString *)path;
- (void)setPath:(nullable NSString *)path;
- (nullable NSString *)selectedPath;
- (void)setSelectedPath:(nullable NSString *)path;
- (nullable NSString *)pathSeparator;
- (void)setPathSeparator:(nullable NSString *)separator;

/* GEOMETRY AND COLUMN STATE. */
- (CGFloat)columnWidth;
- (void)setColumnWidth:(CGFloat)width;
- (CGFloat)minColumnWidth;
- (void)setMinColumnWidth:(CGFloat)width;
- (NSInteger)maxVisibleColumns;
- (void)setMaxVisibleColumns:(NSInteger)count;
- (NSInteger)numberOfVisibleColumns;
- (NSInteger)firstVisibleColumn;
- (NSInteger)lastVisibleColumn;
- (BOOL)separatesColumns;
- (void)setSeparatesColumns:(BOOL)flag;
- (void)scrollColumnToVisible:(NSInteger)column;
- (void)tile;

/* THE LOOK AND THE BEHAVIOUR. */
- (BOOL)allowsMultipleSelection;
- (void)setAllowsMultipleSelection:(BOOL)flag;
- (BOOL)allowsEmptySelection;
- (void)setAllowsEmptySelection:(BOOL)flag;
- (BOOL)takesTitleFromPreviousColumn;
- (void)setTakesTitleFromPreviousColumn:(BOOL)flag;
- (BOOL)hasHorizontalScroller;
- (void)setHasHorizontalScroller:(BOOL)flag;
- (BOOL)acceptsArrowKeys;
- (void)setAcceptsArrowKeys:(BOOL)flag;
- (BOOL)sendsActionOnArrowKeys;
- (void)setSendsActionOnArrowKeys:(BOOL)flag;
- (CGFloat)rowHeight;
- (void)setRowHeight:(CGFloat)height;
- (CGFloat)titleHeight;
- (void)setTitleHeight:(CGFloat)height;
- (NSBrowserColumnResizingType)columnResizingType;
- (void)setColumnResizingType:(NSBrowserColumnResizingType)type;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;

/* THE CELL THE ROWS ARE MADE WITH. The default is `NSBrowserCell`. */
- (nullable Class)cellClass;
- (void)setCellClass:(Class)cellClass;
- (nullable NSCell *)cellPrototype;
- (void)setCellPrototype:(nullable NSCell *)cell;

/* TITLES ARE STORED AND ANSWERED; this slice's columns do not draw a title strip. */
- (void)setTitle:(nullable NSString *)title ofColumn:(NSInteger)column;
- (nullable NSString *)titleOfColumn:(NSInteger)column;
- (nullable NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column;

/* DOUBLE-CLICK AND THE ACTION. A selection sends the control's target/action; a double-click sends -doubleAction. */
- (nullable SEL)doubleAction;
- (void)setDoubleAction:(nullable SEL)action;

/* **THE TIER'S SEAMS.** The table-backed columns are private; a probe asks how many there are and which table a
 * column owns. */
- (NSInteger)numberOfRowsInColumn:(NSInteger)column;
- (NSInteger)cg_columnCount;
- (nullable NSTableView *)cg_tableForColumn:(NSInteger)column;
- (nullable NSView *)cg_documentView;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBROWSER_H */
