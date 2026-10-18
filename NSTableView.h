/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSTableView.h — a cell-based table: columns, rows, a header, and a selection.
 *
 * **THIS IS THE FIRST SLICE, AND IT IS CELL-BASED ON PURPOSE.** The era pinned here is 10.6, where a table's rows are
 * drawn by `NSCell`s (`NSTableColumn -dataCellForRow:` and the data source's object value) rather than by the
 * later-era `NSTableCellView`. The tree already has the cell layer, so the table's job is the MODEL and the
 * GEOMETRY: how many rows, how wide each column, which rect a row and a cell occupy, which row is selected, and how
 * the header resizes a column. It is a `NSControl` because Apple's is, but it never uses the control's cell — the
 * table's face is its columns.
 *
 * **THE TABLE IS FLIPPED.** Row 0 is the TOP row, which is what makes `-rectOfRow:` and a scroll view's top-left
 * origin agree without a second coordinate system. The enclosing `NSClipView` is flipped too, so the document's
 * origin is its top-left.
 *
 * **WHAT THIS SLICE DOES NOT DO, STATED RATHER THAN STUBBED.** Editing a cell through the field editor, drag and drop,
 * type-select, variable row heights, column reordering, autosave and the later view-based API are not here. The
 * header can resize a column; it cannot yet drag one to a new position. `-editedRow`/`-editedColumn` answer -1 for
 * the same reason. `NSOutlineView` is the next slice and subclasses this class.
 *
 * Written from `NSTableView.h` in the MacOSX10.6 SDK (see PROVENANCE.md). The delegate and data-source protocols are
 * the era's; every method beyond the row count is declared `@optional` so a caller implements the part it uses.
 */
#ifndef APPKIT_NSTABLEVIEW_H
#define APPKIT_NSTABLEVIEW_H

#import <AppKit/NSControl.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSIndexSet.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSColor;
@class NSEvent;
@class NSMutableArray;
@class NSMutableIndexSet;
@class NSSortDescriptor;
@class NSTableColumn;
@class NSTableHeaderView;
@class NSTableView;
@class NSView;

/* THE ERA'S THREE ENUMERATIONS. Their values are the order the headers give them because none publishes numbers. */
enum {
	NSTableViewNoColumnAutoresizing = 0,
	NSTableViewUniformColumnAutoresizingStyle,
	NSTableViewSequentialColumnAutoresizingStyle,
	NSTableViewReverseSequentialColumnAutoresizingStyle,
	NSTableViewLastColumnOnlyAutoresizingStyle
};
typedef NSUInteger NSTableViewColumnAutoresizingStyle;

enum {
	NSTableViewGridNone = 0,
	NSTableViewSolidVerticalGridLineMask = 1 << 0,
	NSTableViewSolidHorizontalGridLineMask = 1 << 1
};

enum {
	NSTableViewSelectionHighlightStyleNone = -1,
	NSTableViewSelectionHighlightStyleRegular = 0,
	NSTableViewSelectionHighlightStyleSourceList = 1
};
typedef NSInteger NSTableViewSelectionHighlightStyle;

/* THE FOUR ANNOUNCEMENTS THE CORE MAKES. Selection changes are the two every caller listens for; the column pair is
 * for a header that moved or resized a column. */
extern NSString *NSTableViewSelectionDidChangeNotification;
extern NSString *NSTableViewSelectionIsChangingNotification;
extern NSString *NSTableViewColumnDidMoveNotification;
extern NSString *NSTableViewColumnDidResizeNotification;

@protocol NSTableViewDataSource <NSObject>
@required
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
@optional
- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
		      row:(NSInteger)row;
- (void)tableView:(NSTableView *)tableView setObjectValue:(nullable id)object
   forTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row;
- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors;
@end

@protocol NSTableViewDelegate <NSObject>
@optional
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell
   forTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row;
- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(nullable NSTableColumn *)tableColumn
	      row:(NSInteger)row;
- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView;
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row;
- (nullable NSIndexSet *)tableView:(NSTableView *)tableView
    selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes;
- (BOOL)tableView:(NSTableView *)tableView shouldSelectTableColumn:(nullable NSTableColumn *)tableColumn;
- (void)tableView:(NSTableView *)tableView mouseDownInHeaderOfTableColumn:(NSTableColumn *)tableColumn;
- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn;
- (nullable NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(nullable NSTableColumn *)tableColumn
			     row:(NSInteger)row;
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)tableViewColumnDidMove:(NSNotification *)notification;
- (void)tableViewColumnDidResize:(NSNotification *)notification;
- (void)tableViewSelectionIsChanging:(NSNotification *)notification;
@end

@interface NSTableView : NSControl <NSUserInterfaceValidations>
{
	NSMutableArray *_tableColumns;		/* RETAINED: the table owns its columns */
	id _dataSource;				/* NOT RETAINED */
	id _delegate;				/* NOT RETAINED */
	NSTableHeaderView *_headerView;		/* RETAINED: the default header, or a caller's */
	NSView *_cornerView;			/* RETAINED, when a caller sets one */
	NSMutableIndexSet *_selectedRowIndexes;
	NSMutableIndexSet *_selectedColumnIndexes;
	NSArray *_sortDescriptors;		/* RETAINED */
	NSColor *_backgroundColor;		/* RETAINED */
	NSColor *_gridColor;			/* RETAINED */
	CGFloat _rowHeight;
	NSSize _intercellSpacing;
	NSUInteger _gridStyleMask;
	NSTableViewColumnAutoresizingStyle _columnAutoresizingStyle;
	NSTableViewSelectionHighlightStyle _selectionHighlightStyle;
	NSInteger _highlightedTableColumn;
	NSInteger _clickedRow;
	NSInteger _clickedColumn;
	NSInteger _numberOfRows;
	SEL _doubleAction;
	BOOL _allowsColumnReordering;
	BOOL _allowsColumnResizing;
	BOOL _allowsMultipleSelection;
	BOOL _allowsEmptySelection;
	BOOL _allowsColumnSelection;
	BOOL _usesAlternatingRowBackgroundColors;
	BOOL _allowsTypeSelect;
	id _headerScrollView;			/* NOT RETAINED: the scroll view the header was installed into */
	id _observedClipView;			/* NOT RETAINED: the clip view whose frame changes re-tile us */
}

- (void)setDataSource:(nullable id <NSTableViewDataSource>)aSource;
- (nullable id <NSTableViewDataSource>)dataSource;
- (void)setDelegate:(nullable id <NSTableViewDelegate>)delegate;
- (nullable id <NSTableViewDelegate>)delegate;

/* THE HEADER AND THE CORNER. A table makes a default header; nil removes it. The corner is the square above the
 * vertical scroller and is stored for a caller that wants one. */
- (void)setHeaderView:(nullable NSTableHeaderView *)headerView;
- (nullable NSTableHeaderView *)headerView;
- (void)setCornerView:(nullable NSView *)cornerView;
- (nullable NSView *)cornerView;

/* THE FLAGS AND THE FACE. */
- (void)setAllowsColumnReordering:(BOOL)flag;
- (BOOL)allowsColumnReordering;
- (void)setAllowsColumnResizing:(BOOL)flag;
- (BOOL)allowsColumnResizing;
- (void)setColumnAutoresizingStyle:(NSTableViewColumnAutoresizingStyle)style;
- (NSTableViewColumnAutoresizingStyle)columnAutoresizingStyle;
- (void)setGridStyleMask:(NSUInteger)gridType;
- (NSUInteger)gridStyleMask;
- (void)setIntercellSpacing:(NSSize)aSize;
- (NSSize)intercellSpacing;
- (void)setUsesAlternatingRowBackgroundColors:(BOOL)useAlternatingRowColors;
- (BOOL)usesAlternatingRowBackgroundColors;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)backgroundColor;
- (void)setGridColor:(nullable NSColor *)color;
- (nullable NSColor *)gridColor;
- (void)setRowHeight:(CGFloat)rowHeight;
- (CGFloat)rowHeight;
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)indexSet;

/* THE COLUMNS AND THE ROWS. */
- (NSArray *)tableColumns;
- (NSInteger)numberOfColumns;
- (NSInteger)numberOfRows;
- (void)addTableColumn:(NSTableColumn *)tableColumn;
- (void)removeTableColumn:(NSTableColumn *)tableColumn;
- (void)moveColumn:(NSInteger)oldIndex toColumn:(NSInteger)newIndex;
- (NSInteger)columnWithIdentifier:(id)identifier;
- (nullable NSTableColumn *)tableColumnWithIdentifier:(id)identifier;
- (void)tile;
- (void)sizeToFit;
- (void)sizeLastColumnToFit;
- (void)scrollRowToVisible:(NSInteger)row;
- (void)scrollColumnToVisible:(NSInteger)column;
- (void)reloadData;
- (void)noteNumberOfRowsChanged;
- (void)reloadDataForRowIndexes:(NSIndexSet *)rowIndexes columnIndexes:(NSIndexSet *)columnIndexes;

/* THE CLICK AND EDIT STATE. Editing is not in this slice, so the edited pair answers -1. */
- (NSInteger)editedColumn;
- (NSInteger)editedRow;
- (NSInteger)clickedColumn;
- (NSInteger)clickedRow;
- (void)setDoubleAction:(nullable SEL)aSelector;
- (nullable SEL)doubleAction;
- (void)setSortDescriptors:(NSArray *)array;
- (NSArray *)sortDescriptors;
- (void)setHighlightedTableColumn:(nullable NSTableColumn *)tableColumn;
- (nullable NSTableColumn *)highlightedTableColumn;
- (void)setAllowsTypeSelect:(BOOL)value;
- (BOOL)allowsTypeSelect;

/* SELECTION. */
- (void)setAllowsMultipleSelection:(BOOL)flag;
- (BOOL)allowsMultipleSelection;
- (void)setAllowsEmptySelection:(BOOL)flag;
- (BOOL)allowsEmptySelection;
- (void)setAllowsColumnSelection:(BOOL)flag;
- (BOOL)allowsColumnSelection;
- (void)selectAll:(nullable id)sender;
- (void)deselectAll:(nullable id)sender;
- (void)selectColumnIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
- (NSIndexSet *)selectedColumnIndexes;
- (NSIndexSet *)selectedRowIndexes;
- (void)deselectColumn:(NSInteger)column;
- (void)deselectRow:(NSInteger)row;
- (NSInteger)selectedColumn;
- (NSInteger)selectedRow;
- (BOOL)isColumnSelected:(NSInteger)column;
- (BOOL)isRowSelected:(NSInteger)row;
- (NSInteger)numberOfSelectedColumns;
- (NSInteger)numberOfSelectedRows;
- (NSTableViewSelectionHighlightStyle)selectionHighlightStyle;
- (void)setSelectionHighlightStyle:(NSTableViewSelectionHighlightStyle)style;

/* THE GEOMETRY. All rects are in the table's own coordinates. */
- (NSRect)rectOfColumn:(NSInteger)column;
- (NSRect)rectOfRow:(NSInteger)row;
- (NSIndexSet *)columnIndexesInRect:(NSRect)rect;
- (NSRange)rowsInRect:(NSRect)rect;
- (NSInteger)columnAtPoint:(NSPoint)point;
- (NSInteger)rowAtPoint:(NSPoint)point;
- (NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row;
- (nullable NSCell *)preparedCellAtColumn:(NSInteger)column row:(NSInteger)row;

/* THE THREE DRAWING HALVES, so a subclass can change the face without re-implementing the table. */
- (void)drawRow:(NSInteger)row clipRect:(NSRect)clipRect;
- (void)highlightSelectionInClipRect:(NSRect)clipRect;
- (void)drawGridInClipRect:(NSRect)clipRect;
- (void)drawBackgroundInClipRect:(NSRect)clipRect;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTABLEVIEW_H */
