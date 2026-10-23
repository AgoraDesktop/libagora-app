/*
 * NSBrowser.h — a chain of columns: a list, and the next list for the selected row.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS IS A TABLE-BACKED BROWSER, AND THE TABLES ARE PRIVATE.** Apple's class is a matrix of `NSBrowserCell`s per
 * column; each column here is an `NSTableView` inside one horizontal `NSScrollView`, and the browser is the table data
 * source and delegate. The PUBLIC surface is the 10.6 one: the delegate answers how many rows a column has, the
 * `-browser:willDisplayCell:atRow:column:` door fills each `NSBrowserCell`, and selecting a row loads the column to
 * its right. The old `-browser:createRowsForColumn:inMatrix:` form is the one part that is not here, and **ITS REASON
 * HAS CHANGED RATHER THAN EXPIRED**: `NSMatrix` now exists, but a matrix is what APPLE'S browser's columns ARE, and
 * this tree's columns are tables — so there is no matrix for the delegate to fill, and handing it a temporary one it
 * does not own would be a stub with a real signature. The header names that absence rather than a door nobody could
 * use; a cell-based delegate using `willDisplayCell` is the supported path.
 *
 * **THE COLUMNS ARE A 256-SLOT POOL, AND THE EMPTY ONES ARE VISIBLE.** A browser builds all of its column slots
 * when it loads rather than growing and shrinking the view list: Finder's own shape, and the reason a column's width
 * survives navigating away from it. The document is only as wide as the active columns OR the visible area,
 * whichever is wider, so the empty slots to the right show as empty columns while the scrollable document does not
 * become 256 columns of blank space.
 *
 * **COLUMNS ARE LAID OUT SIDE BY SIDE AND SCROLL HORIZONTALLY.** Each column carries its own vertical
 * `NSScrollView`, so a long folder scrolls without moving its neighbours; the browser's outer scroll view is the
 * horizontal one. Column widths are per column, and a `NSBrowserUserColumnResizing` browser draws the same
 * eighteen-point, three-ring gutter `NSSplitView`'s pane splitter uses and makes it a drag handle.
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

@interface NSBrowser : NSControl <NSSecureCoding>
{
	id <NSBrowserDelegate> _delegate;	/* NOT RETAINED */
	NSMutableArray *_tables;		/* RETAINED: NSTableView, one per column */
	NSMutableArray *_columnScrollViews;	/* RETAINED: NSScrollView, one per column */
	NSMutableArray *_columnWidths;		/* RETAINED: NSNumber content width per column */
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
	/* **THE TITLE STRIP AND THE LAST CLICK.** `_titled` is whether each column reserves a strip above its list (Apple's
	 * default is YES, and this class drew no strip until §11 of `HANDOFF-4.md`), and the two clicked fields are the row
	 * and column of the most recent click — -1 before the first one, which is Apple's own "no click" value. */
	BOOL _titled;
	NSInteger _clickedRow;
	NSInteger _clickedColumn;
	/* **AND THE TARGET/ACTION PAIR IS THE BROWSER'S OWN, WHICH IS A DEVIATION WITH A REASON.** `NSControl` keeps that pair
	 * on its CELL in this tree — a button's action lives in the button cell — and a browser has NO cell, so `-action` would
	 * answer NULL for ever and every click would send nothing. Apple's `NSControl` keeps the pair on the control, which is
	 * why an `NSBrowser` has one there; these four doors are that answer, and they are the only place this class does not
	 * take what its superclass says. */
	id _browserTarget;		/* NOT RETAINED, Apple's contract for a target */
	SEL _browserAction;
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

/* GEOMETRY AND COLUMN STATE. `-columnWidth` is the width a NEW column gets and the width
 * `-setColumnWidth:` gives every existing one; `-widthOfColumn:`/`-setWidth:ofColumn:` are the per-column pair.
 * A column's width is its FRAME's: the vertical scroller lives inside it, so a visible bar narrows the table
 * rather than widening the column. */
- (CGFloat)columnWidth;
- (void)setColumnWidth:(CGFloat)width;
- (CGFloat)widthOfColumn:(NSInteger)column;
- (void)setWidth:(CGFloat)width ofColumn:(NSInteger)column;
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

/* TITLES ARE STORED, ANSWERED **AND DRAWN**. A titled browser reserves its `-titleHeight` above each column's list and
 * draws the column's title there; `-isTitled` is what decides, and the three geometry doors below answer the strip's
 * frame as well as the column's. */
- (void)setTitle:(nullable NSString *)title ofColumn:(NSInteger)column;
- (nullable NSString *)titleOfColumn:(NSInteger)column;
- (nullable NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column;
- (BOOL)isTitled;
- (void)setTitled:(BOOL)flag;
- (void)drawTitleOfColumn:(NSInteger)column inRect:(NSRect)rect;

/* ---- WHERE A COLUMN AND A ROW ARE, AND THE INVERSE --------------------------------------------------------- */

/* **ALL THREE FRAMES ARE IN THE BROWSER'S OWN COORDINATES** (unflipped, y=0 at the bottom, Apple's for a control),
 * converted out of the scrolling document so a caller gets the place on screen rather than a place in a scrolled
 * view: `-frameOfColumn:` is the whole column INCLUDING its title strip, `-frameOfInsideOfColumn:` is the list part
 * under the strip, and `-titleFrameOfColumn:` is the strip itself (empty when the browser is not titled).
 * `-frameOfRow:inColumn:` is the row's rect there — which can be outside the column's visible part, because a row
 * scrolled out of view still has a place. */
- (NSRect)frameOfColumn:(NSInteger)column;
- (NSRect)frameOfInsideOfColumn:(NSInteger)column;
- (NSRect)titleFrameOfColumn:(NSInteger)column;
- (NSRect)frameOfRow:(NSInteger)row inColumn:(NSInteger)column;

/* **AND THE INVERSE, WHICH IS WHAT A CLICK OR A MENU ASKS.** Answers YES when the point fell in a column, and writes -1
 * to the row for a point above the list (in the title strip) or below the last row. */
- (BOOL)getRow:(nullable NSInteger *)row column:(nullable NSInteger *)column forPoint:(NSPoint)point;

/* THE TWO WIDTH CONVERSIONS: a column's frame width against the width its table actually gets, which is the frame
 * less the column's own vertical scroller when that bar is showing. `-defaultColumnWidth` is the width a NEW column
 * gets; `-setDefaultColumnWidth:` leaves the columns that exist alone, which is the one difference from
 * `-setColumnWidth:` (that one re-widths every column). */
- (CGFloat)columnContentWidthForColumnWidth:(CGFloat)columnWidth;
- (CGFloat)columnWidthForColumnContentWidth:(CGFloat)contentWidth;
- (CGFloat)defaultColumnWidth;
- (void)setDefaultColumnWidth:(CGFloat)width;

/* THE CLICK AND ITS TWO ACTIONS. `-doClick:` records the clicked row and column from the selection and sends the
 * action; `-doDoubleClick:` sends the double action. Both are what the table's own paths call, and both are public
 * because Apple publishes them: a caller with a synthetic click has nowhere else to put it.
 *
 * **AND THE PAIR ITSELF IS HERE, BECAUSE A BROWSER HAS NO CELL.** `NSControl`'s target/action live in the cell in this
 * tree, so a cell-less control answers NULL and sends nothing; these four doors keep the pair on the control, which is
 * where Apple has it. */
- (nullable id)target;
- (void)setTarget:(nullable id)target;
- (nullable SEL)action;
- (void)setAction:(nullable SEL)action;
- (NSInteger)clickedRow;
- (NSInteger)clickedColumn;
- (void)doClick:(nullable id)sender;
- (void)doDoubleClick:(nullable id)sender;

/* **THE OUTER SCROLLER IS RE-TILED, WHICH IS WHAT UPDATING IT MEANS HERE** — the column count and the document width
 * are what it reads, and `-tile` is the one door that recomputes both. */
- (void)updateScroller;

/* DOUBLE-CLICK AND THE ACTION. A selection sends the control's target/action; a double-click sends -doubleAction. */
- (nullable SEL)doubleAction;
- (void)setDoubleAction:(nullable SEL)action;

/* **THE TIER'S SEAMS.** The table-backed columns are private; a probe asks how many there are and which table a
 * column owns. */
- (NSInteger)numberOfRowsInColumn:(NSInteger)column;
- (NSInteger)cg_columnCount;
- (NSInteger)cg_activeColumnCount;
- (nullable NSTableView *)cg_tableForColumn:(NSInteger)column;
- (nullable NSScrollView *)cg_scrollViewForColumn:(NSInteger)column;
- (NSRect)cg_dividerFrameForColumn:(NSInteger)column;
- (nullable NSView *)cg_documentView;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBROWSER_H */
