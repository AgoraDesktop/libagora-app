/*
 * NSTableView — the cell-based table core.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE TABLE IS A MODEL VIEW, AND THIS FILE IS THE MODEL'S GEOMETRY.** The data source answers how many rows and
 * what each cell's value is; the columns answer how wide they are and which cells draw them; this class answers where
 * every row, column and cell sits, which rows are selected, and how a click or an arrow key changes that. It never
 * copies the model: a cell's object value is set immediately before that cell is drawn, which is why one data cell
 * per column is enough.
 *
 * **FLIPPED, SO ROW 0 IS THE TOP.** The enclosing clip view is flipped too, so the document's origin is its top-left
 * and a scroll down is a larger y. That is Apple's table geometry and it keeps `-rectOfRow:` free of a second flip.
 *
 * **THE HEADER IS INSTALLED INTO THE SCROLL VIEW, NOT INTO THIS VIEW.** Rows scroll and headers do not; the scroll
 * view's private header seam is where `NSTableHeaderView` lives. A table used without a scroll view still owns its
 * header object; it simply has nowhere to show it, which is the same shape as a window with no screen.
 */
#import "NSTableView.h"
#import "NSTableColumn.h"
#import "NSTableHeaderView.h"

#import "NSScrollView.h"
#import "NSScrollView_internal.h"
#import "NSClipView.h"
#import "NSApplication.h"
#import "NSBezierPath.h"
#import "NSColor.h"
#import "NSEvent.h"
#import "NSFont.h"
#import "NSTextFieldCell.h"
#import "NSWindow.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSSortDescriptor.h>
#import <Foundation/NSString.h>

#include <math.h>

NSString *NSTableViewSelectionDidChangeNotification = @"NSTableViewSelectionDidChangeNotification";
NSString *NSTableViewSelectionIsChangingNotification = @"NSTableViewSelectionIsChangingNotification";
NSString *NSTableViewColumnDidMoveNotification = @"NSTableViewColumnDidMoveNotification";
NSString *NSTableViewColumnDidResizeNotification = @"NSTableViewColumnDidResizeNotification";

#define AG_TABLE_DEFAULT_ROW_HEIGHT 17.0
#define AG_TABLE_DEFAULT_HEADER_HEIGHT 20.0

@interface NSTableView ()
- (void)cg_updateHeaderView;
- (void)cg_observeClipView;
- (void)cg_clipFrameChanged:(NSNotification *)notification;
- (void)fn_applySelectedRows:(NSIndexSet *)rows notify:(BOOL)notify;
- (void)fn_announceSelectionIsChanging;
- (void)fn_applySelectedColumns:(NSIndexSet *)columns;
- (NSArray *)fn_visibleColumns;
@end

@implementation NSTableView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_tableColumns = [[NSMutableArray alloc] init];
		_dataSource = nil;
		_delegate = nil;
		_selectedRowIndexes = [[NSMutableIndexSet alloc] init];
		_selectedColumnIndexes = [[NSMutableIndexSet alloc] init];
		_sortDescriptors = [[NSArray alloc] init];
		_backgroundColor = [[NSColor controlBackgroundColor] retain];
		_gridColor = [[NSColor gridColor] retain];
		_rowHeight = AG_TABLE_DEFAULT_ROW_HEIGHT;
		_intercellSpacing = NSMakeSize(3.0, 2.0);
		_gridStyleMask = NSTableViewGridNone;
		_columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
		_selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
		_highlightedTableColumn = -1;
		_clickedRow = -1;
		_clickedColumn = -1;
		_numberOfRows = 0;
		_doubleAction = NULL;
		_allowsColumnReordering = YES;
		_allowsColumnResizing = YES;
		_allowsMultipleSelection = NO;
		_allowsEmptySelection = YES;
		_allowsColumnSelection = NO;
		_usesAlternatingRowBackgroundColors = NO;
		_allowsTypeSelect = YES;
		_observedClipView = nil;
		/* THE TABLE'S ROWS RUN DOWNWARD, so the view's own y axis does too. The clip view is flipped, which makes
		 * the document's origin its top-left and the two directions agree. */
		[self setFlipped:YES];
		_headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 0.0,
										 AG_TABLE_DEFAULT_HEADER_HEIGHT)];
		[_headerView setTableView:self];
		_cornerView = nil;
	}
	return self;
}

- (void)dealloc
{
	if (_observedClipView != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
			name:NSViewFrameDidChangeNotification object:_observedClipView];
		_observedClipView = nil;
	}
	[_headerView setTableView:nil];
	[_headerView release];
	[_cornerView release];
	[_tableColumns release];
	[_selectedRowIndexes release];
	[_selectedColumnIndexes release];
	[_sortDescriptors release];
	[_backgroundColor release];
	[_gridColor release];
	[super dealloc];
}

/* ---- THE DATA SOURCE AND THE DELEGATE ---------------------------------------------------------- */

- (void)setDataSource:(id <NSTableViewDataSource>)aSource
{
	_dataSource = aSource;	/* NOT RETAINED */
	[self reloadData];
}

- (id <NSTableViewDataSource>)dataSource
{
	return _dataSource;
}

- (void)setDelegate:(id <NSTableViewDelegate>)delegate
{
	_delegate = delegate;	/* NOT RETAINED */
}

- (id <NSTableViewDelegate>)delegate
{
	return _delegate;
}

/* ---- THE HEADER AND THE CORNER ------------------------------------------------------------------ */

- (void)setHeaderView:(NSTableHeaderView *)headerView
{
	if (headerView == _headerView) {
		return;
	}
	[_headerView setTableView:nil];
	[headerView retain];
	[_headerView release];
	_headerView = headerView;
	if (_headerView != nil) {
		[_headerView setTableView:self];
		if (NSHeight([_headerView frame]) <= 0.0) {
			[_headerView setFrameSize:NSMakeSize(NSWidth([_headerView frame]), AG_TABLE_DEFAULT_HEADER_HEIGHT)];
		}
	}
	[self cg_updateHeaderView];
	[self tile];
}

- (NSTableHeaderView *)headerView
{
	return _headerView;
}

- (void)setCornerView:(NSView *)cornerView
{
	[cornerView retain];
	[_cornerView release];
	_cornerView = cornerView;
}

- (NSView *)cornerView
{
	return _cornerView;
}

/* THE SCROLL VIEW'S PRIVATE HEADER SEAM. The header is a sibling of the clip view, and this is the one place the
 * table tells the scroll view which view that is. A table outside a scroll view keeps its header object and shows it
 * nowhere, which is the honest state rather than a floating copy. */
- (void)cg_updateHeaderView
{
	NSScrollView *scroll = (NSScrollView *)[self enclosingScrollView];

	if (_headerScrollView != nil && _headerScrollView != scroll) {
		[(NSScrollView *)_headerScrollView cg_setHeaderView:nil];
		_headerScrollView = nil;
	}
	if (scroll != nil) {
		[scroll cg_setHeaderView:_headerView];
		_headerScrollView = scroll;
	}
}

- (void)viewDidMoveToSuperview
{
	[super viewDidMoveToSuperview];
	[self cg_updateHeaderView];
	[self cg_observeClipView];
	[self tile];
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	[self cg_updateHeaderView];
	[self cg_observeClipView];
	[self tile];
}

/* **A WIDER OR NARROWER CLIP VIEW CHANGES WHAT "FILL THE VISIBLE WIDTH" MEANS.** The table listens to the clip view's
 * frame rather than to the scroll view, because the clip view is what the table is actually a document of and it is
 * the view whose frame the scroll view's tiling changes. */
- (void)cg_observeClipView
{
	NSView *clip = [self superview];

	if (_observedClipView == clip) {
		return;
	}
	if (_observedClipView != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
			name:NSViewFrameDidChangeNotification object:_observedClipView];
	}
	_observedClipView = clip;
	if (clip != nil) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cg_clipFrameChanged:)
			name:NSViewFrameDidChangeNotification object:clip];
	}
}

- (void)cg_clipFrameChanged:(NSNotification *)notification
{
	(void)notification;
	[self tile];
}

/* ---- THE FLAGS AND THE FACE --------------------------------------------------------------------- */

- (void)setAllowsColumnReordering:(BOOL)flag	{ _allowsColumnReordering = flag ? YES : NO; }
- (BOOL)allowsColumnReordering			{ return _allowsColumnReordering; }
- (void)setAllowsColumnResizing:(BOOL)flag	{ _allowsColumnResizing = flag ? YES : NO; }
- (BOOL)allowsColumnResizing			{ return _allowsColumnResizing; }
- (void)setColumnAutoresizingStyle:(NSTableViewColumnAutoresizingStyle)style { _columnAutoresizingStyle = style; }
- (NSTableViewColumnAutoresizingStyle)columnAutoresizingStyle { return _columnAutoresizingStyle; }
- (void)setGridStyleMask:(NSUInteger)gridType { _gridStyleMask = gridType; [self setNeedsDisplay:YES]; }
- (NSUInteger)gridStyleMask { return _gridStyleMask; }

- (void)setIntercellSpacing:(NSSize)aSize
{
	_intercellSpacing = aSize;
	[self tile];
}

- (NSSize)intercellSpacing { return _intercellSpacing; }

- (void)setUsesAlternatingRowBackgroundColors:(BOOL)flag
{
	_usesAlternatingRowBackgroundColors = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)usesAlternatingRowBackgroundColors { return _usesAlternatingRowBackgroundColors; }

- (void)setBackgroundColor:(NSColor *)color
{
	[color retain];
	[_backgroundColor release];
	_backgroundColor = color;
	[self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
	return (_backgroundColor != nil) ? _backgroundColor : [NSColor controlBackgroundColor];
}

- (void)setGridColor:(NSColor *)color
{
	[color retain];
	[_gridColor release];
	_gridColor = color;
	[self setNeedsDisplay:YES];
}

- (NSColor *)gridColor
{
	return (_gridColor != nil) ? _gridColor : [NSColor gridColor];
}

- (void)setRowHeight:(CGFloat)rowHeight
{
	_rowHeight = (rowHeight > 0.0) ? rowHeight : 1.0;
	[self tile];
}

- (CGFloat)rowHeight { return _rowHeight; }
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)indexSet { (void)indexSet; [self setNeedsDisplay:YES]; }

/* ---- THE COLUMNS --------------------------------------------------------------------------------- */

- (NSArray *)tableColumns
{
	return [NSArray arrayWithArray:_tableColumns];
}

- (NSInteger)numberOfColumns
{
	return (NSInteger)[_tableColumns count];
}

- (NSInteger)numberOfRows
{
	return _numberOfRows;
}

- (void)addTableColumn:(NSTableColumn *)tableColumn
{
	if (tableColumn == nil) {
		return;
	}
	[_tableColumns addObject:tableColumn];
	[tableColumn setTableView:self];
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)removeTableColumn:(NSTableColumn *)tableColumn
{
	if (tableColumn == nil) {
		return;
	}
	[tableColumn retain];
	[tableColumn setTableView:nil];
	[_tableColumns removeObjectIdenticalTo:tableColumn];
	[tableColumn release];
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)moveColumn:(NSInteger)oldIndex toColumn:(NSInteger)newIndex
{
	NSTableColumn *column;

	if (oldIndex < 0 || (NSUInteger)oldIndex >= [_tableColumns count] ||
	    newIndex < 0 || (NSUInteger)newIndex >= [_tableColumns count] || oldIndex == newIndex) {
		return;
	}
	column = [[_tableColumns objectAtIndex:(NSUInteger)oldIndex] retain];
	[_tableColumns removeObjectAtIndex:(NSUInteger)oldIndex];
	[_tableColumns insertObject:column atIndex:(NSUInteger)newIndex];
	[column release];
	[self tile];
	[self setNeedsDisplay:YES];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSTableViewColumnDidMoveNotification object:self];
}

- (NSInteger)columnWithIdentifier:(id)identifier
{
	NSUInteger i;

	for (i = 0; i < [_tableColumns count]; i++) {
		if ([[[_tableColumns objectAtIndex:i] identifier] isEqual:identifier]) {
			return (NSInteger)i;
		}
	}
	return -1;
}

- (NSTableColumn *)tableColumnWithIdentifier:(id)identifier
{
	NSInteger index = [self columnWithIdentifier:identifier];

	return (index >= 0) ? [_tableColumns objectAtIndex:(NSUInteger)index] : nil;
}

/* A HIDDEN COLUMN IS STILL IN THE ORDER BUT TAKES NO WIDTH. `-tableColumns` answers the real order; the geometry
 * doors skip the hidden ones, which is what makes showing a column again a matter of one flag rather than a re-add. */
- (NSArray *)fn_visibleColumns
{
	NSMutableArray *visible = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [_tableColumns count]; i++) {
		NSTableColumn *column = [_tableColumns objectAtIndex:i];

		if (![column isHidden]) {
			[visible addObject:column];
		}
	}
	return visible;
}

/* ---- THE SIZE AND THE LAYOUT -------------------------------------------------------------------- */

- (void)tile
{
	NSScrollView *scroll = (NSScrollView *)[self enclosingScrollView];
	NSSize clip = (scroll != nil) ? [scroll contentSize] : NSZeroSize;
	CGFloat width = 0.0;
	CGFloat height;
	NSUInteger i;
	BOOL first = YES;

	for (i = 0; i < [_tableColumns count]; i++) {
		NSTableColumn *column = [_tableColumns objectAtIndex:i];

		if ([column isHidden]) {
			continue;
		}
		if (!first) {
			width += _intercellSpacing.width;
		}
		width += [column width];
		first = NO;
	}
	height = (CGFloat)_numberOfRows * (_rowHeight + _intercellSpacing.height);
	if (width < clip.width) {
		width = clip.width;
	}
	if (height < clip.height) {
		height = clip.height;
	}
	[self setFrameSize:NSMakeSize(width, height)];
	[self setNeedsDisplay:YES];
}

- (void)sizeToFit
{
	CGFloat width = 0.0;
	NSUInteger i;
	BOOL first = YES;

	for (i = 0; i < [_tableColumns count]; i++) {
		NSTableColumn *column = [_tableColumns objectAtIndex:i];

		if ([column isHidden]) {
			continue;
		}
		if (!first) {
			width += _intercellSpacing.width;
		}
		width += [column width];
		first = NO;
	}
	[self setFrameSize:NSMakeSize(width, (CGFloat)_numberOfRows * (_rowHeight + _intercellSpacing.height))];
}

- (void)sizeLastColumnToFit
{
	NSScrollView *scroll = (NSScrollView *)[self enclosingScrollView];
	NSArray *visible = [self fn_visibleColumns];
	NSTableColumn *last;
	CGFloat used = 0.0;
	CGFloat width;
	NSUInteger i;

	if ([visible count] == 0) {
		return;
	}
	for (i = 0; i + 1 < [visible count]; i++) {
		used += [[visible objectAtIndex:i] width] + _intercellSpacing.width;
	}
	last = [visible lastObject];
	width = (scroll != nil ? [scroll contentSize].width : [self frame].size.width) - used;
	if (width < [last minWidth]) {
		width = [last minWidth];
	}
	[last setWidth:width];
	[self tile];
}

- (void)scrollRowToVisible:(NSInteger)row
{
	if (row < 0 || row >= _numberOfRows) {
		return;
	}
	[self scrollRectToVisible:[self rectOfRow:row]];
}

- (void)scrollColumnToVisible:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_tableColumns count]) {
		return;
	}
	[self scrollRectToVisible:[self rectOfColumn:column]];
}

/* ---- THE MODEL ---------------------------------------------------------------------------------- */

- (void)reloadData
{
	NSInteger rows = 0;

	if (_dataSource != nil && [_dataSource respondsToSelector:@selector(numberOfRowsInTableView:)]) {
		rows = [_dataSource numberOfRowsInTableView:self];
	}
	if (rows < 0) {
		rows = 0;
	}
	_numberOfRows = rows;
	/* A RELOAD CAN SHRINK THE MODEL UNDER THE SELECTION, so indexes that no longer exist are dropped rather than
	 * left selected and undrawable. */
	if ([_selectedRowIndexes count] > 0 && [_selectedRowIndexes lastIndex] >= (NSUInteger)_numberOfRows) {
		NSMutableIndexSet *kept = [[NSMutableIndexSet alloc] init];
		NSUInteger row = [_selectedRowIndexes firstIndex];

		while (row != NSNotFound) {
			if (row < (NSUInteger)_numberOfRows) {
				[kept addIndex:row];
			}
			row = [_selectedRowIndexes indexGreaterThanIndex:row];
		}
		[self fn_applySelectedRows:kept notify:YES];
		[kept release];
	}
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)noteNumberOfRowsChanged
{
	if (_dataSource != nil && [_dataSource respondsToSelector:@selector(numberOfRowsInTableView:)]) {
		NSInteger rows = [_dataSource numberOfRowsInTableView:self];

		_numberOfRows = (rows > 0) ? rows : 0;
	} else {
		_numberOfRows = 0;
	}
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)reloadDataForRowIndexes:(NSIndexSet *)rowIndexes columnIndexes:(NSIndexSet *)columnIndexes
{
	(void)rowIndexes;
	(void)columnIndexes;
	[self setNeedsDisplay:YES];
}

- (NSInteger)editedColumn { return -1; }
- (NSInteger)editedRow { return -1; }
- (NSInteger)clickedColumn { return _clickedColumn; }
- (NSInteger)clickedRow { return _clickedRow; }

- (void)setDoubleAction:(SEL)aSelector { _doubleAction = aSelector; }
- (SEL)doubleAction { return _doubleAction; }

- (void)setSortDescriptors:(NSArray *)array
{
	NSArray *copy = [array copy];

	[_sortDescriptors release];
	_sortDescriptors = copy;
	[self setNeedsDisplay:YES];
}

- (NSArray *)sortDescriptors { return _sortDescriptors; }

- (void)setHighlightedTableColumn:(NSTableColumn *)tableColumn
{
	NSInteger index = (tableColumn != nil) ? (NSInteger)[_tableColumns indexOfObjectIdenticalTo:tableColumn] : -1;

	_highlightedTableColumn = (index == (NSInteger)NSNotFound) ? -1 : index;
	[self setNeedsDisplay:YES];
}

- (NSTableColumn *)highlightedTableColumn
{
	return (_highlightedTableColumn >= 0 && (NSUInteger)_highlightedTableColumn < [_tableColumns count])
		       ? [_tableColumns objectAtIndex:(NSUInteger)_highlightedTableColumn] : nil;
}

- (void)setAllowsTypeSelect:(BOOL)value { _allowsTypeSelect = value ? YES : NO; }
- (BOOL)allowsTypeSelect { return _allowsTypeSelect; }

/* ---- SELECTION ---------------------------------------------------------------------------------- */

- (void)setAllowsMultipleSelection:(BOOL)flag { _allowsMultipleSelection = flag ? YES : NO; }
- (BOOL)allowsMultipleSelection { return _allowsMultipleSelection; }
- (void)setAllowsEmptySelection:(BOOL)flag { _allowsEmptySelection = flag ? YES : NO; }
- (BOOL)allowsEmptySelection { return _allowsEmptySelection; }
- (void)setAllowsColumnSelection:(BOOL)flag { _allowsColumnSelection = flag ? YES : NO; }
- (BOOL)allowsColumnSelection { return _allowsColumnSelection; }

- (void)fn_applySelectedRows:(NSIndexSet *)rows notify:(BOOL)notify
{
	if ([_selectedRowIndexes isEqualToIndexSet:rows]) {
		return;
	}
	[_selectedRowIndexes removeAllIndexes];
	[_selectedRowIndexes addIndexes:rows];
	[self setNeedsDisplay:YES];
	if (notify) {
		NSNotification *note = [NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification
								     object:self];

		if (_delegate != nil && [_delegate respondsToSelector:@selector(tableViewSelectionDidChange:)]) {
			[_delegate tableViewSelectionDidChange:note];
		}
		[[NSNotificationCenter defaultCenter] postNotification:note];
	}
}

- (void)fn_announceSelectionIsChanging
{
	NSNotification *note = [NSNotification notificationWithName:NSTableViewSelectionIsChangingNotification
							     object:self];

	if (_delegate != nil && [_delegate respondsToSelector:@selector(tableViewSelectionIsChanging:)]) {
		[_delegate tableViewSelectionIsChanging:note];
	}
	[[NSNotificationCenter defaultCenter] postNotification:note];
}

- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
	NSMutableIndexSet *proposed = [[NSMutableIndexSet alloc] init];
	NSMutableIndexSet *allowed = [[NSMutableIndexSet alloc] init];
	NSUInteger row;

	if (extend) {
		[proposed addIndexes:_selectedRowIndexes];
	}
	[proposed addIndexes:indexes];
	row = [proposed firstIndex];
	while (row != NSNotFound) {
		if (row < (NSUInteger)_numberOfRows) {
			[allowed addIndex:row];
		}
		row = [proposed indexGreaterThanIndex:row];
	}
	[proposed release];

	/* ONE ROW AT A TIME WHEN MULTIPLE SELECTION IS OFF, and the FIRST index is the one a caller's set meant. */
	if (!_allowsMultipleSelection && [allowed count] > 1) {
		NSUInteger first = [allowed firstIndex];
		[allowed removeAllIndexes];
		[allowed addIndex:first];
	}
	if (!_allowsEmptySelection && [allowed count] == 0) {
		[allowed release];
		return;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(selectionShouldChangeInTableView:)] &&
	    ![_delegate selectionShouldChangeInTableView:self]) {
		[allowed release];
		return;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tableView:shouldSelectRow:)]) {
		NSMutableIndexSet *selected = [[NSMutableIndexSet alloc] init];

		row = [allowed firstIndex];
		while (row != NSNotFound) {
			if ([_delegate tableView:self shouldSelectRow:(NSInteger)row]) {
				[selected addIndex:row];
			}
			row = [allowed indexGreaterThanIndex:row];
		}
		[allowed release];
		allowed = selected;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tableView:selectionIndexesForProposedSelection:)]) {
		NSIndexSet *answer = [_delegate tableView:self selectionIndexesForProposedSelection:allowed];

		if (answer != nil) {
			[allowed release];
			allowed = [[NSMutableIndexSet alloc] initWithIndexSet:answer];
		}
	}
	[self fn_applySelectedRows:allowed notify:YES];
	[allowed release];
}

- (void)selectColumnIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
	NSMutableIndexSet *proposed = [[NSMutableIndexSet alloc] init];
	NSUInteger column;

	if (extend) {
		[proposed addIndexes:_selectedColumnIndexes];
	}
	[proposed addIndexes:indexes];
	column = [proposed firstIndex];
	while (column != NSNotFound) {
		if (column >= [_tableColumns count]) {
			[proposed removeIndex:column];
		}
		column = [proposed indexGreaterThanIndex:column];
	}
	[self fn_applySelectedColumns:proposed];
	[proposed release];
}

- (void)fn_applySelectedColumns:(NSIndexSet *)columns
{
	if ([_selectedColumnIndexes isEqualToIndexSet:columns]) {
		return;
	}
	[_selectedColumnIndexes removeAllIndexes];
	[_selectedColumnIndexes addIndexes:columns];
	[self setNeedsDisplay:YES];
	if (_headerView != nil) {
		[_headerView setNeedsDisplay:YES];
	}
}

- (void)selectAll:(id)sender
{
	(void)sender;
	if (_allowsMultipleSelection) {
		NSMutableIndexSet *all = [[NSMutableIndexSet alloc] init];

		if (_numberOfRows > 0) {
			[all addIndexesInRange:NSMakeRange(0, (NSUInteger)_numberOfRows)];
		}
		[self fn_applySelectedRows:all notify:YES];
		[all release];
	}
}

- (void)deselectAll:(id)sender
{
	(void)sender;
	[self fn_applySelectedRows:[NSIndexSet indexSet] notify:YES];
	[self fn_applySelectedColumns:[NSIndexSet indexSet]];
}

- (void)deselectRow:(NSInteger)row
{
	if (row < 0) {
		return;
	}
	[_selectedRowIndexes removeIndex:(NSUInteger)row];
	[self setNeedsDisplay:YES];
}

- (void)deselectColumn:(NSInteger)column
{
	if (column < 0) {
		return;
	}
	[_selectedColumnIndexes removeIndex:(NSUInteger)column];
	[self setNeedsDisplay:YES];
}

/* **THE GETTERS ANSWER A FROZEN SNAPSHOT, NOT THE LIVE SET.** `-copy` on an `NSMutableIndexSet` in this Foundation
 * is a RETAIN (an immutable needs no copy), so returning `copy` handed a caller the table's own mutable selection —
 * a caller could edit the selection through the getter by accident, and this table's own outline subclass read a
 * "before" that the selection then mutated underneath it. `initWithIndexSet:` is the genuinely frozen answer. */
- (NSIndexSet *)selectedColumnIndexes
{
	return [[[NSIndexSet alloc] initWithIndexSet:_selectedColumnIndexes] autorelease];
}

- (NSIndexSet *)selectedRowIndexes
{
	return [[[NSIndexSet alloc] initWithIndexSet:_selectedRowIndexes] autorelease];
}

- (NSInteger)selectedColumn
{
	NSUInteger first = [_selectedColumnIndexes firstIndex];

	return (first == NSNotFound) ? -1 : (NSInteger)first;
}

- (NSInteger)selectedRow
{
	NSUInteger first = [_selectedRowIndexes firstIndex];

	return (first == NSNotFound) ? -1 : (NSInteger)first;
}

- (BOOL)isColumnSelected:(NSInteger)column
{
	return (column >= 0) && [_selectedColumnIndexes containsIndex:(NSUInteger)column];
}

- (BOOL)isRowSelected:(NSInteger)row
{
	return (row >= 0) && [_selectedRowIndexes containsIndex:(NSUInteger)row];
}

- (NSInteger)numberOfSelectedColumns { return (NSInteger)[_selectedColumnIndexes count]; }
- (NSInteger)numberOfSelectedRows { return (NSInteger)[_selectedRowIndexes count]; }

- (NSTableViewSelectionHighlightStyle)selectionHighlightStyle { return _selectionHighlightStyle; }
- (void)setSelectionHighlightStyle:(NSTableViewSelectionHighlightStyle)style
{
	_selectionHighlightStyle = style;
	[self setNeedsDisplay:YES];
}

/* ---- THE GEOMETRY --------------------------------------------------------------------------------- */

- (NSRect)rectOfColumn:(NSInteger)column
{
	CGFloat x = 0.0;
	NSInteger i;

	if (column < 0 || column >= (NSInteger)[_tableColumns count]) {
		return NSZeroRect;
	}
	for (i = 0; i < column; i++) {
		NSTableColumn *prior = [_tableColumns objectAtIndex:(NSUInteger)i];

		if (![prior isHidden]) {
			x += [prior width] + _intercellSpacing.width;
		}
	}
	if ([[_tableColumns objectAtIndex:(NSUInteger)column] isHidden]) {
		return NSZeroRect;
	}
	return NSMakeRect(x, 0.0, [[_tableColumns objectAtIndex:(NSUInteger)column] width], [self frame].size.height);
}

- (NSRect)rectOfRow:(NSInteger)row
{
	if (row < 0 || row >= _numberOfRows) {
		return NSZeroRect;
	}
	return NSMakeRect(0.0, (CGFloat)row * (_rowHeight + _intercellSpacing.height),
			  [self frame].size.width, _rowHeight);
}

- (NSInteger)columnAtPoint:(NSPoint)point
{
	CGFloat x = 0.0;
	NSInteger i;

	if (point.x < 0.0) {
		return -1;
	}
	for (i = 0; i < (NSInteger)[_tableColumns count]; i++) {
		NSTableColumn *column = [_tableColumns objectAtIndex:(NSUInteger)i];

		if ([column isHidden]) {
			continue;
		}
		if (point.x < x + [column width]) {
			return i;
		}
		x += [column width] + _intercellSpacing.width;
	}
	return -1;
}

- (NSInteger)rowAtPoint:(NSPoint)point
{
	NSInteger row;

	if (point.y < 0.0 || _numberOfRows == 0) {
		return -1;
	}
	row = (NSInteger)floor((double)(point.y / (_rowHeight + _intercellSpacing.height)));
	return (row < _numberOfRows) ? row : -1;
}

- (NSRange)rowsInRect:(NSRect)rect
{
	NSInteger first;
	NSInteger last;

	if (_numberOfRows == 0 || NSIsEmptyRect(rect)) {
		return NSMakeRange(NSNotFound, 0);
	}
	first = [self rowAtPoint:NSMakePoint(0.0, NSMinY(rect))];
	if (first < 0) {
		first = (NSInteger)floor((double)(NSMinY(rect) / (_rowHeight + _intercellSpacing.height)));
		if (first < 0) {
			first = 0;
		}
	}
	last = [self rowAtPoint:NSMakePoint(0.0, NSMaxY(rect) - 0.001)];
	if (last < 0) {
		last = _numberOfRows - 1;
	}
	if (first >= _numberOfRows || last < first) {
		return NSMakeRange(NSNotFound, 0);
	}
	return NSMakeRange((NSUInteger)first, (NSUInteger)(last - first + 1));
}

- (NSIndexSet *)columnIndexesInRect:(NSRect)rect
{
	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	NSInteger i;

	for (i = 0; i < (NSInteger)[_tableColumns count]; i++) {
		if (NSIntersectsRect(rect, [self rectOfColumn:i])) {
			[indexes addIndex:(NSUInteger)i];
		}
	}
	return indexes;
}

- (NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
	NSRect columnRect = [self rectOfColumn:column];
	NSRect rowRect = [self rectOfRow:row];

	if (NSIsEmptyRect(columnRect) || NSIsEmptyRect(rowRect)) {
		return NSZeroRect;
	}
	return NSMakeRect(NSMinX(columnRect), NSMinY(rowRect), NSWidth(columnRect), NSHeight(rowRect));
}

- (NSCell *)preparedCellAtColumn:(NSInteger)column row:(NSInteger)row
{
	NSTableColumn *tableColumn;
	NSCell *cell = nil;
	id value = nil;

	if (column < 0 || (NSUInteger)column >= [_tableColumns count] || row < 0 || row >= _numberOfRows) {
		return nil;
	}
	tableColumn = [_tableColumns objectAtIndex:(NSUInteger)column];
	if ([tableColumn isHidden]) {
		return nil;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tableView:dataCellForTableColumn:row:)]) {
		cell = [_delegate tableView:self dataCellForTableColumn:tableColumn row:row];
	}
	if (cell == nil) {
		cell = [tableColumn dataCellForRow:row];
	}
	if (_dataSource != nil &&
	    [_dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)]) {
		value = [_dataSource tableView:self objectValueForTableColumn:tableColumn row:row];
	}
	[cell setObjectValue:value];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tableView:willDisplayCell:forTableColumn:row:)]) {
		[_delegate tableView:self willDisplayCell:cell forTableColumn:tableColumn row:row];
	}
	return cell;
}

/* ---- DRAWING ------------------------------------------------------------------------------------ */

- (void)drawBackgroundInClipRect:(NSRect)clipRect
{
	[[self backgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:clipRect] fill];
	if (_usesAlternatingRowBackgroundColors) {
		NSArray *colors = [NSColor controlAlternatingRowBackgroundColors];
		NSRange rows = [self rowsInRect:clipRect];
		NSUInteger row;

		if ([colors count] > 1 && rows.location != NSNotFound) {
			for (row = rows.location; row < NSMaxRange(rows); row++) {
				if ((row % 2u) == 1u) {
					[[colors objectAtIndex:1] setFill];
					[[NSBezierPath bezierPathWithRect:[self rectOfRow:(NSInteger)row]] fill];
				}
			}
		}
	}
}

- (void)highlightSelectionInClipRect:(NSRect)clipRect
{
	NSUInteger row = [_selectedRowIndexes firstIndex];

	if (_selectionHighlightStyle == NSTableViewSelectionHighlightStyleNone) {
		return;
	}
	while (row != NSNotFound) {
		NSRect rect = [self rectOfRow:(NSInteger)row];

		if (NSIntersectsRect(rect, clipRect)) {
			NSColor *selection = (_selectionHighlightStyle == NSTableViewSelectionHighlightStyleSourceList)
				? [NSColor controlHighlightColor] : [NSColor selectedControlColor];

			[selection setFill];
			[[NSBezierPath bezierPathWithRect:rect] fill];
		}
		row = [_selectedRowIndexes indexGreaterThanIndex:row];
	}
}

- (void)drawRow:(NSInteger)row clipRect:(NSRect)clipRect
{
	NSInteger column;

	if (row < 0 || row >= _numberOfRows) {
		return;
	}
	for (column = 0; column < (NSInteger)[_tableColumns count]; column++) {
		NSCell *cell;
		NSRect rect = [self frameOfCellAtColumn:column row:row];
		BOOL selected = [self isRowSelected:row];
		NSColor *saved = nil;
		BOOL canSetInk = NO;

		if (NSIsEmptyRect(rect) || !NSIntersectsRect(rect, clipRect)) {
			continue;
		}
		cell = [self preparedCellAtColumn:column row:row];
		if (cell == nil) {
			continue;
		}
		canSetInk = [cell respondsToSelector:@selector(setTextColor:)];
		if (selected && canSetInk) {
			saved = [[(id)cell textColor] retain];
			[(id)cell setTextColor:[NSColor selectedControlTextColor]];
		}
		[cell drawWithFrame:rect inView:self];
		if (selected && canSetInk) {
			[(id)cell setTextColor:saved];
		}
		[saved release];
	}
}

- (void)drawGridInClipRect:(NSRect)clipRect
{
	NSInteger i;

	if ((_gridStyleMask & NSTableViewSolidVerticalGridLineMask) != 0) {
		for (i = 0; i < (NSInteger)[_tableColumns count]; i++) {
			NSRect rect = [self rectOfColumn:i];

			if (NSIsEmptyRect(rect)) {
				continue;
			}
			[[self gridColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(NSMaxX(rect), NSMinY(clipRect),
								     1.0, NSHeight(clipRect))] fill];
		}
	}
	if ((_gridStyleMask & NSTableViewSolidHorizontalGridLineMask) != 0) {
		NSRange rows = [self rowsInRect:clipRect];
		NSUInteger row;

		if (rows.location == NSNotFound) {
			return;
		}
		[[self gridColor] setFill];
		for (row = rows.location; row < NSMaxRange(rows); row++) {
			NSRect rect = [self rectOfRow:(NSInteger)row];

			[[NSBezierPath bezierPathWithRect:NSMakeRect(NSMinX(clipRect), NSMaxY(rect) - 1.0,
								     NSWidth(clipRect), 1.0)] fill];
		}
	}
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRange rows;

	[self drawBackgroundInClipRect:dirtyRect];
	[self highlightSelectionInClipRect:dirtyRect];
	rows = [self rowsInRect:dirtyRect];
	if (rows.location != NSNotFound) {
		NSUInteger row;

		for (row = rows.location; row < NSMaxRange(rows); row++) {
			[self drawRow:(NSInteger)row clipRect:dirtyRect];
		}
	}
	[self drawGridInClipRect:dirtyRect];
}

/* ---- THE POINTER AND THE KEYBOARD --------------------------------------------------------------- */

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (BOOL)becomeFirstResponder
{
	[self setNeedsDisplay:YES];
	return YES;
}

- (BOOL)resignFirstResponder
{
	[self setNeedsDisplay:YES];
	return YES;
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSUInteger modifiers = [event modifierFlags];

	_clickedRow = [self rowAtPoint:point];
	_clickedColumn = [self columnAtPoint:point];
	if ([event clickCount] >= 2 && _doubleAction != NULL) {
		[[NSApplication sharedApplication] sendAction:_doubleAction to:nil from:self];
		return;
	}
	if (_clickedRow < 0) {
		if (_allowsEmptySelection) {
			[self deselectAll:nil];
		}
		return;
	}
	[self fn_announceSelectionIsChanging];
	if ((modifiers & NSCommandKeyMask) != 0) {
		NSMutableIndexSet *next = [[NSMutableIndexSet alloc] init];

		[next addIndexes:_selectedRowIndexes];
		if ([next containsIndex:(NSUInteger)_clickedRow]) {
			[next removeIndex:(NSUInteger)_clickedRow];
		} else {
			[next addIndex:(NSUInteger)_clickedRow];
		}
		/* THROUGH THE SAME DOOR AS ANY OTHER SELECTION, so the delegate's should-select answer is asked here too. */
		[self selectRowIndexes:next byExtendingSelection:NO];
		[next release];
	} else if ((modifiers & NSShiftKeyMask) != 0) {
		NSInteger anchor = [self selectedRow];
		NSInteger lo, hi;

		if (anchor < 0) {
			anchor = _clickedRow;
		}
		lo = anchor < _clickedRow ? anchor : _clickedRow;
		hi = anchor < _clickedRow ? _clickedRow : anchor;
		[self selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:
			NSMakeRange((NSUInteger)lo, (NSUInteger)(hi - lo + 1))] byExtendingSelection:NO];
	} else {
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)_clickedRow] byExtendingSelection:NO];
	}
}

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	unichar key;
	NSInteger row = [self selectedRow];
	NSInteger next;

	if ([characters length] == 0 || _numberOfRows == 0) {
		[super keyDown:event];
		return;
	}
	key = [characters characterAtIndex:0];
	switch (key) {
	case NSUpArrowFunctionKey:
		next = (row <= 0) ? 0 : row - 1;
		break;
	case NSDownArrowFunctionKey:
		next = (row < 0) ? 0 : ((row + 1 < _numberOfRows) ? row + 1 : _numberOfRows - 1);
		break;
	case NSHomeFunctionKey:
		next = 0;
		break;
	case NSEndFunctionKey:
		next = _numberOfRows - 1;
		break;
	case NSPageUpFunctionKey:
		next = (row < 10) ? 0 : row - 10;
		break;
	case NSPageDownFunctionKey:
		next = (row < 0) ? 0 : row + 10;
		if (next >= _numberOfRows) {
			next = _numberOfRows - 1;
		}
		break;
	default:
		[super keyDown:event];
		return;
	}
	[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
	[self scrollRowToVisible:next];
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	(void)anItem;
	return YES;
}

@end
