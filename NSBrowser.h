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
#import <AppKit/NSDragging.h>	/* NSDragOperation, which the drag doors take and answer. */

NS_ASSUME_NONNULL_BEGIN

@class NSBrowser;
@class NSBrowserCell;
@class NSColor;
@class NSImage;
@class NSIndexPath;
@class NSIndexSet;
@class NSMutableArray;
@class NSCell;
@class NSScrollView;
@class NSTableView;
@class NSString;
@class NSScroller;
@class NSEvent;
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

/* ==================================================================================================================
 * THE ADVERTISED MODEL IS THE 10.6 ONE: ITEMS, NOT CELLS AND NOT MATRICES.
 *
 * **APPLE SHIPPED TWO DELEGATE CONTRACTS IN ONE CLASS, AND THIS HEADER NOW ADVERTISES THE LATER ONE.** The NeXT-era
 * contract is CELL-based: the delegate counts ROWS per column and fills each cell through
 * `-browser:willDisplayCell:atRow:column:`, and the browser's columns were matrices of `NSBrowserCell`s. 10.6 added an
 * ITEM-based contract: the delegate answers with model objects — how many children an item has, which child is at an
 * index, whether an item is a leaf, and what an item's cell should show — and the browser makes the cells itself.
 *
 * **THE ITEM DOORS ARE THE ONES THIS CLASS ASKS FIRST, AND THE CELL DOORS ARE THE FALLBACK.** That is Apple's own order
 * and the reason both are declared: a delegate that implements `-browser:numberOfChildrenOfItem:`,
 * `-browser:child:ofItem:`, `-browser:isLeafItem:` and `-browser:objectValueForItem:` drives the browser — one object
 * per row, no cells to configure — while a delegate written for the older API keeps working unchanged. **A DELEGATE
 * SHOULD IMPLEMENT ONE OR THE OTHER, NOT BOTH** (an item-based delegate may still implement
 * `-browser:willDisplayCell:atRow:column:` to STYLE the cells the browser made, which is the one overlap Apple allows).
 *
 * **AND THE ROOT IS `nil`.** The item-based model has no root object: column zero shows `-browser:numberOfChildrenOfItem:`
 * for NIL, and every later column shows the children of the item selected in the column to its left. That is why
 * `-indexPathForColumn:` answers the path of the item WHOSE CHILDREN are in that column, and why every reading door
 * below can walk to its answer from nil without the browser caching anything: an item belongs to the delegate, and the
 * browser never retains one.
 *
 * The CELL-based doors are still asked when the item ones are absent — `WSColumnView`, in the Workspace repository, is
 * written against them — and they are documented here as the older alternative rather than removed, because Apple kept
 * them and a ported delegate may use either.
 *
 * **THE LAST THREE SIZE HOOKS ARE DECLARED AND NOT ASKED IN THIS SLICE.** Rows have the browser's fixed row height
 * and columns its fixed width; `-browser:heightOfRow:inColumn:`, `-browser:shouldSizeColumn:…` and
 * `-browser:sizeToFitWidthOfColumn:` are here because the era's protocol declares them, and a delegate that answers
 * them will be called when those rules arrive rather than now.
 * ================================================================================================================ */
@protocol NSBrowserDelegate <NSObject>
@optional
/* ---- THE 10.6 ITEM-BASED CONTRACT, WHICH THIS CLASS ASKS FIRST ------------------------------------------------ */
/* How many children the item has. `nil` is the ROOT, so column zero's row count comes from this with nil. */
- (NSInteger)browser:(NSBrowser *)browser numberOfChildrenOfItem:(nullable id)item;
/* The child of `item` at `index` — one call per row, and the object the browser hands back from `-itemAtRow:inColumn:`. */
- (nullable id)browser:(NSBrowser *)browser child:(NSInteger)index ofItem:(nullable id)item;
/* Whether an item has no children, which is what draws a row without a branch triangle. */
- (BOOL)browser:(NSBrowser *)browser isLeafItem:(nullable id)item;
/* What the item's cell should show. The browser sets it on the cell it makes; a string is the ordinary answer. */
- (nullable id)browser:(NSBrowser *)browser objectValueForItem:(nullable id)item;

/* Whether a drag may start from these rows. Asked by `-canDragRowsWithIndexes:inColumn:withEvent:`; a delegate that
 * does not answer leaves the decision to the column's table, which asks its own data source. */
- (BOOL)browser:(NSBrowser *)browser
    canDragRowsWithIndexes:(NSIndexSet *)rowIndexes
	      inColumn:(NSInteger)column
	     withEvent:(nullable NSEvent *)event;

/* ---- THE CELL-BASED CONTRACT, KEPT AS THE FALLBACK ------------------------------------------------------------ */
/* Rows per column, for a delegate that does not answer `-browser:numberOfChildrenOfItem:`. */
- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column;
/* Filling a cell the browser made — either as the whole cell contract (no item doors) or to STYLE what the item doors
 * produced, which is the one overlap Apple's documentation allows. */
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
	/* **AND THE REST OF THE ERA'S STATE, ONE IVAR PER DOOR THAT HAS ONE.** `_loadedZero` is whether column zero has ever
	 * been built (`-isLoaded`); `_lastColumn` is the highest column the browser will grow to (`-lastColumn`, default -1
	 * meaning "not set"); the two drag masks are the local and non-local operations (`-setDraggingSourceOperationMask:`);
	 * and the three flags below are read where the browser makes a decision — the branch-selection gate, the type-select
	 * the columns' tables do, and the divider drag that may resize every column at once. */
	BOOL _loadedZero;
	NSInteger _lastColumn;
	NSDragOperation _localDragMask;
	NSDragOperation _nonLocalDragMask;
	BOOL _allowsBranchSelection;
	BOOL _allowsTypeSelect;
	BOOL _prefersAllColumnUserResizing;
	NSString *_columnsAutosaveName;	/* COPIED, or nil for "no autosave" */
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

/* ==================================================================================================================
 * THE ITEM-BASED READING DOORS — the 10.6 half of the model, over the same columns.
 *
 * **EVERY ONE OF THEM WALKS FROM `nil` THROUGH THE DELEGATE, SO NOTHING IS CACHED AND NO ITEM IS RETAINED.** An item
 * belongs to the delegate; the browser asks `-browser:child:ofItem:` for each step of the path it is following, which is
 * what Apple's own documentation means by "the browser does not retain items". A path that runs out (a column with no
 * selection) answers nil rather than a wrong object.
 *
 * `-itemAtRow:inColumn:` is the row's item; `-parentForItemsInColumn:` is the item WHOSE CHILDREN the column shows;
 * `-indexPathForColumn:` is that parent's path; `-pathToColumn:` is the same chain as a `-path`-style string; and
 * `-isLeafItem:` asks the delegate whether the chain ends there. The two selection doors read and write the selected
 * rows as one index path, which is what a caller restoring a folder's selection needs.
 * ================================================================================================================ */
- (nullable id)itemAtRow:(NSInteger)row inColumn:(NSInteger)column;
- (nullable id)itemAtIndexPath:(nullable NSIndexPath *)indexPath;
- (nullable id)parentForItemsInColumn:(NSInteger)column;
- (BOOL)isLeafItem:(nullable id)item;
- (nullable NSIndexPath *)indexPathForColumn:(NSInteger)column;
- (nullable NSString *)pathToColumn:(NSInteger)column;
- (nullable NSIndexPath *)selectionIndexPath;
- (void)setSelectionIndexPath:(nullable NSIndexPath *)path;
- (NSArray *)selectionIndexPaths;
- (void)setSelectionIndexPaths:(NSArray *)paths;

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

/* ==================================================================================================================
 * THE REST OF THE ERA'S SURFACE — what a browser does to a column or a row once it has one.
 *
 * **FOUR KINDS, AND EACH IS MEASURABLE RATHER THAN STORED.** The DRAG quartet is the source half of the tier's
 * `NSDraggingSession` (the destination half is the table's, which each column already is): whether a drag may start, the
 * image it carries, the operation mask, and beginning an edit at an item's path. The RELOAD trio re-reads rows without
 * rebuilding the column. The DISPLAY and SCROLL family moves the viewport and the outer scroller — `-displayColumn:`,
 * `-displayAllColumns`, `-scrollColumnsLeftBy:`, `-scrollColumnsRightBy:`, `-scrollViaScroller:`,
 * `-scrollRowToVisible:inColumn:`, `-autohidesScroller` — because a browser wider than its columns has two axes to move
 * on and only one of them is a column's own. And the FURNITURE: `-addColumn` grows the chain by one, `-lastColumn` says
 * how far it may grow, `-isLoaded` says whether column zero exists, `-sendAction` is the action send `-doClick:` uses,
 * and `-validateVisibleColumns` asks the delegate whether each visible column still holds.
 *
 * **THE COLUMN-WIDTH AUTOSAVE IS THE TABLE'S MECHANISM, REUSED.** `-columnsAutosaveName` stores the widths under a
 * `NSUserDefaults` key of its own (`NSBrowser Columns <name>`), so setting a name RESTORES the saved widths and later
 * column resizes persist them; `-removeSavedColumnsWithAutosaveName:` deletes the key. Nothing else is autosaved: the
 * selected rows are the caller's to remember.
 *
 * **AND THREE DOORS REFUSE BY NAME, BECAUSE THIS BROWSER'S COLUMNS ARE TABLES.** `-matrixClass`, `-setMatrixClass:`,
 * `-matrixInColumn:` and `-columnOfMatrix:` describe Apple's implementation — a matrix of `NSBrowserCell`s per column —
 * and this class has no matrix to hand out. A caller that wants a column's view asks `-cg_tableForColumn:`, which is the
 * tier's own seam and says what it is. **`-setReusesColumns:` refuses for the same kind of reason**: the browser's
 * columns ARE a fixed 256-slot pool and are reused by construction, so `-reusesColumns` answers YES and a caller cannot
 * ask for anything else.
 * ================================================================================================================ */
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column withEvent:(nullable NSEvent *)event;
- (nullable NSImage *)draggingImageForRowsWithIndexes:(NSIndexSet *)rowIndexes
					    inColumn:(NSInteger)column
					   withEvent:(nullable NSEvent *)event
					      offset:(nullable NSPointPointer)dragImageOffset;
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask forLocal:(BOOL)isLocal;
- (void)editItemAtIndexPath:(NSIndexPath *)indexPath withEvent:(nullable NSEvent *)event select:(BOOL)select;

- (void)reloadDataForRowIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column;
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)indexSet inColumn:(NSInteger)column;
- (void)validateVisibleColumns;

- (void)addColumn;
- (void)displayColumn:(NSInteger)column;
- (void)displayAllColumns;
- (NSInteger)lastColumn;
- (void)setLastColumn:(NSInteger)column;
- (BOOL)isLoaded;

- (void)scrollColumnsLeftBy:(NSInteger)shiftAmount;
- (void)scrollColumnsRightBy:(NSInteger)shiftAmount;
- (void)scrollViaScroller:(nullable NSScroller *)sender;
- (void)scrollRowToVisible:(NSInteger)row inColumn:(NSInteger)column;
- (BOOL)autohidesScroller;
- (void)setAutohidesScroller:(BOOL)flag;

- (nullable NSCell *)selectedCellInColumn:(NSInteger)column;
- (nullable NSCell *)loadedCellAtRow:(NSInteger)row column:(NSInteger)column;

- (BOOL)allowsBranchSelection;
- (void)setAllowsBranchSelection:(BOOL)flag;
- (BOOL)allowsTypeSelect;
- (void)setAllowsTypeSelect:(BOOL)flag;
- (BOOL)reusesColumns;
- (void)setReusesColumns:(BOOL)flag;
- (BOOL)prefersAllColumnUserResizing;
- (void)setPrefersAllColumnUserResizing:(BOOL)flag;

- (nullable NSString *)columnsAutosaveName;
- (void)setColumnsAutosaveName:(nullable NSString *)name;
- (void)removeSavedColumnsWithAutosaveName:(NSString *)name;

/* Sends the control's action — the one `-doClick:` performs after it records where the click landed. */
- (void)sendAction;

/* AND THE FOUR THAT REFUSE: see the block note above for why this browser has no matrix to answer with. */
- (nullable Class)matrixClass;
- (void)setMatrixClass:(nullable Class)matrixClass;
- (nullable id)matrixInColumn:(NSInteger)column;
- (NSInteger)columnOfMatrix:(nullable id)matrix;

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
