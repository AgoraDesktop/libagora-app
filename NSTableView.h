/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * **THE SECOND HALF IS HERE NOW: EDITING, TYPE-SELECT, VARIABLE HEIGHTS, COLUMN REORDERING, AUTOSAVE AND A LOCAL ROW
 * DRAG.** The field editor is the window's; `-editColumn:row:withEvent:select:` starts a session and the data source's
 * `-tableView:setObjectValue:...` receives the result. Type-select searches the prepared cells' strings (or the
 * delegate's), variable heights come from `-tableView:heightOfRow:` and are cached, the header reorders a column when
 * dragged past its threshold, and the autosave name persists column widths, order, hidden state and sort descriptors.
 * The row drag is LOCAL: the data source writes the pasteboard, validates and accepts, and the table draws the
 * insertion line — there is no `NSDraggingSession` and no cross-application destination yet. The later view-based API
 * (`NSTableCellView`, `-viewForTableColumn:row:`) is still absent. `NSOutlineView` subclasses this class.
 *
 * Written from `NSTableView.h` in the MacOSX10.6 SDK (see PROVENANCE.md). The delegate and data-source protocols are
 * the era's; every method beyond the row count is declared `@optional` so a caller implements the part it uses.
 */
#ifndef APPKIT_NSTABLEVIEW_H
#define APPKIT_NSTABLEVIEW_H

#import <AppKit/NSControl.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSIndexSet.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSColor;
@class NSEnumerator;
@class NSEvent;
@class NSImage;
@class NSPasteboard;
@class NSMutableArray;
@class NSMutableIndexSet;
@class NSSortDescriptor;
@class NSTableColumn;
@class NSTableHeaderView;
@class NSTableView;
@class NSURL;
@class NSView;
@protocol NSDraggingInfo;

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

/* THE TWO DROP POSITIONS. `DropOn` replaces the row under the pointer; `DropAbove` inserts before it — and
 * `-setDropRow:dropOperation:` is how a data source re-targets `-validateDrop:`. */
enum {
	NSTableViewDropOn = 0,
	NSTableViewDropAbove = 1
};
typedef NSInteger NSTableViewDropOperation;

/* **THE DRAG DESTINATION'S FEEDBACK STYLE.** The 10.6 header names three: none (no insertion mark), regular (the
 * table's line) and source list (the sidebar's, which the selection style can choose on a caller's behalf). */
enum {
	NSTableViewDraggingDestinationFeedbackStyleNone = -1,
	NSTableViewDraggingDestinationFeedbackStyleRegular = 0,
	NSTableViewDraggingDestinationFeedbackStyleSourceList = 1
};
typedef NSInteger NSTableViewDraggingDestinationFeedbackStyle;

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

/* THE DRAG SOURCE AND DESTINATION CONTRACT. The table's LOCAL row drag calls these with a pasteboard and a small
 * `NSDraggingInfo`, and the drag itself is the tier's session (`NSDragging.h`). The CROSS-PROCESS half is still
 * absent — a drop from another application does not arrive — because that is the window server's transport rather than
 * this class. */
- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pboard;
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info
		 proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation;
- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info
	      row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation;
@end

@protocol NSTableViewDelegate <NSControlTextEditingDelegate>
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
- (void)tableView:(NSTableView *)tableView didDragTableColumn:(NSTableColumn *)tableColumn;
- (BOOL)tableView:(NSTableView *)tableView shouldReorderColumn:(NSInteger)columnIndex
	     toColumn:(NSInteger)newColumnIndex;
- (nullable NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(nullable NSTableColumn *)tableColumn
			     row:(NSInteger)row;
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row;
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row;
- (nullable NSString *)tableView:(NSTableView *)tableView
   typeSelectStringForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row;
- (NSInteger)tableView:(NSTableView *)tableView nextTypeSelectMatchFromRow:(NSInteger)startRow
			   toRow:(NSInteger)endRow forString:(NSString *)searchString;
- (BOOL)tableView:(NSTableView *)tableView shouldTypeSelectForEvent:(NSEvent *)event
   withCurrentSearchString:(nullable NSString *)searchString;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)tableViewColumnDidMove:(NSNotification *)notification;
- (void)tableViewColumnDidResize:(NSNotification *)notification;
- (void)tableViewSelectionIsChanging:(NSNotification *)notification;
@end

@interface NSTableView : NSControl <NSUserInterfaceValidations, NSSecureCoding>
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
	/* VARIABLE ROW HEIGHTS: one top and one extent per row, rebuilt from the delegate's `-tableView:heightOfRow:`
	 * (or `_rowHeight` when it does not answer). */
	NSMutableArray *_cgRowTops;		/* RETAINED: NSNumber doubles */
	NSMutableArray *_cgRowHeights;		/* RETAINED: NSNumber doubles */
	/* THE EDIT SESSION. The cell is retained for the duration and the row/column answer -1 outside one. */
	NSInteger _editedRow;
	NSInteger _editedColumn;
	NSCell *_cgEditingCell;			/* RETAINED while editing */
	/* TYPE-SELECT: the accumulated prefix and when the last key arrived. */
	NSMutableString *_cgTypeSelectString;	/* RETAINED */
	NSTimeInterval _cgTypeSelectTime;
	/* AUTOSAVE: the name and whether column geometry/sort order are saved under it. */
	NSString *_autosaveName;		/* COPIED */
	BOOL _autosaveTableColumns;
	/* DRAG/DROP VOCABULARY: the source masks and the current proposed drop, recorded for the session's arrival. */
	NSDragOperation _cgLocalDragMask;
	NSDragOperation _cgNonLocalDragMask;
	NSInteger _cgDropRow;
	NSTableViewDropOperation _cgDropOperation;
	/* THE LOCAL ROW DRAG: the rows, the pasteboard they wrote and the press they began at. */
	NSIndexSet *_cgDragRows;		/* RETAINED while a drag is in flight */
	NSPasteboard *_cgDragPasteboard;	/* RETAINED while a drag is in flight */
	NSPoint _cgDragStartPoint;
	BOOL _cgDragging;
	NSTableViewColumnAutoresizingStyle _columnAutoresizingStyle;
	/* THE DEPRECATED AUTORESIZE FLAG IS A SPELLING OF THE STYLE, and `tile` is the reader of both: Uniform fills the
	 * width proportionally, LastColumnOnly gives the difference to the last column, and the sequential pair walks from
	 * one end. The guard is what keeps `-setWidth:` (which calls `-tile`) from recursing through the autoresize pass. */
	BOOL _cgAutoresizingColumns;
	NSTableViewSelectionHighlightStyle _selectionHighlightStyle;
	NSTableViewDraggingDestinationFeedbackStyle _draggingDestinationFeedbackStyle;
	/* THE FOCUS RING'S COLUMN, or -1. The ring is drawn around the SELECTED ROW's cell in this column, which is the
	 * shape Apple's header describes. */
	NSInteger _focusedColumn;
	/* Whether a VERTICAL drag can begin a row drag, or is a drag-select instead. YES is Apple's default. */
	BOOL _verticalMotionCanBeginDrag;
	/* THE HEADER INDICATOR IMAGES, keyed by a pointer to the column — a per-column association Apple keeps on the
	 * table rather than on `NSTableColumn`, which is why these are table doors. */
	NSMutableDictionary *_cgIndicatorImages;	/* RETAINED */
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
/* **THE DEPRECATED FLAG IS A SPELLING OF THE STYLE, NOT A SECOND FIELD.** YES sets
 * `NSTableViewUniformColumnAutoresizingStyle`; NO sets `NSTableViewLastColumnOnlyAutoresizingStyle`. The getter answers
 * YES exactly for Uniform, so a table in either sequential style reads NO. */
- (void)setAutoresizesAllColumnsToFit:(BOOL)flag;
- (BOOL)autoresizesAllColumnsToFit;
- (void)setGridStyleMask:(NSUInteger)gridType;
- (NSUInteger)gridStyleMask;
/* THE DEPRECATED BOOLEAN SPELLING OF THE GRID MASK: YES is both solid line masks, NO is none. */
- (void)setDrawsGrid:(BOOL)flag;
- (BOOL)drawsGrid;
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

/* THE CLICK AND EDIT STATE. The edited pair answers the session's row/column, or -1 outside one. */
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

/* EDITING. `-editColumn:row:withEvent:select:` starts the window's field editor over the cell; the data source's
 * `-tableView:setObjectValue:forTableColumn:row:` is what receives the result when the session ends. */
- (void)editColumn:(NSInteger)column row:(NSInteger)row withEvent:(nullable NSEvent *)theEvent select:(BOOL)select;
/* **A CLICK ON A CELL, WHICH IS THE CELL'S ACTION RATHER THAN THE TABLE'S.** The prepared cell is copied (with its
 * target/action carried over), clicked, and its object value written back to the data source when the click changed
 * it. Apple's door does no enabled-check; neither does this one. */
- (void)performClickOnCellAtColumn:(NSInteger)column row:(NSInteger)row;
- (BOOL)shouldFocusCell:(NSCell *)cell atColumn:(NSInteger)column row:(NSInteger)row;
- (nullable NSText *)currentEditor;
- (BOOL)abortEditing;

/* AUTOSAVE. The name plus the flag save column widths, order, hidden state and sort descriptors in defaults. */
- (void)setAutosaveName:(nullable NSString *)name;
- (nullable NSString *)autosaveName;
- (void)setAutosaveTableColumns:(BOOL)save;
- (BOOL)autosaveTableColumns;

/* THE DRAG SOURCE AND DESTINATION DOORS. The masks are stored; `-setDropRow:dropOperation:` is a data source's
 * re-target during `-validateDrop:`. A row drag runs through the tier's `NSDraggingSession` and the table is its own
 * destination; the CROSS-PROCESS half is not in this tier. */
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes atPoint:(NSPoint)mouseDownPoint;
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask forLocal:(BOOL)isLocal;
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal;
- (void)setDropRow:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation;
/* THE DESTINATION'S FEEDBACK, THE FOCUSED COLUMN, AND THE HEADER'S INDICATOR IMAGE. A source list selection style
 * sets the feedback style to SourceList, which is Apple's documented coupling; `-setDraggingDestinationFeedbackStyle:`
 * can still override it afterwards. */
- (void)setDraggingDestinationFeedbackStyle:(NSTableViewDraggingDestinationFeedbackStyle)style;
- (NSTableViewDraggingDestinationFeedbackStyle)draggingDestinationFeedbackStyle;
- (void)setFocusedColumn:(NSInteger)focusedColumn;
- (NSInteger)focusedColumn;
- (nullable NSImage *)indicatorImageInTableColumn:(NSTableColumn *)tableColumn;
- (void)setIndicatorImage:(nullable NSImage *)anImage inTableColumn:(NSTableColumn *)tableColumn;

/* **THE TWO DRAG IMAGES.** The modern door builds a snapshot of the named rows and columns through
 * `-cacheDisplayInRect:toBitmapImageRep:`; the deprecated one takes an array of row numbers and forwards. The offset
 * is in/out: the caller hands NSZeroPoint and may be given a re-positioning, which this tier leaves at zero (Apple's
 * "centred under the mouse"). */
- (nullable NSImage *)dragImageForRowsWithIndexes:(NSIndexSet *)dragRows
				     tableColumns:(nullable NSArray *)tableColumns
					    event:(nullable NSEvent *)dragEvent
					   offset:(NSPointPointer)dragImageOffset;
- (nullable NSImage *)dragImageForRows:(NSArray *)dragRows
				 event:(nullable NSEvent *)dragEvent
		       dragImageOffset:(NSPointPointer)dragImageOffset;
/* Whether a vertical motion can START a row drag; NO makes it a drag-select, which this tier's click loop does not
 * implement, so the motion simply does not begin a drag. */
- (void)setVerticalMotionCanBeginDrag:(BOOL)flag;
- (BOOL)verticalMotionCanBeginDrag;

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
/* THE DEPRECATED SINGLE-INDEX SPELLINGS, and the two enumerators over the selected sets. The enumerators answer
 * NSNumber objects, which is what Apple's deprecated doors have always yielded. */
- (void)selectColumn:(NSInteger)column byExtendingSelection:(BOOL)extend;
- (void)selectRow:(NSInteger)row byExtendingSelection:(BOOL)extend;
- (NSEnumerator *)selectedColumnEnumerator;
- (NSEnumerator *)selectedRowEnumerator;
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
/* THE DEPRECATED RANGE SPELLING of the index-set door: the first through the last column the rect touches. */
- (NSRange)columnsInRect:(NSRect)rect;
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
