/*
 * NSBrowser.m — columns of tables, and the selection that opens the next one.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE PRIVATE SHAPE: one `NSScrollView`, one document view, one `NSTableView` per column. The browser is the data
 * source and delegate of every one of those tables and maps a sender back to its column by identity. The public
 * shape is the 10.6 delegate: `-browser:numberOfRowsInColumn:` and
 * `-browser:willDisplayCell:atRow:column:`; selecting a row asks the delegate for the column to its right.
 *
 * THE MATRIX FORM IS THE ONE THING THAT IS NOT HERE. Apple's `-browser:createRowsForColumn:inMatrix:` needs an
 * `NSMatrix`, which this tree has not got; the header names that absence rather than a stub that would never be
 * called. A cell-based delegate using `willDisplayCell` is the supported path.
 */
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <Foundation/NSIndexSet.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSView.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <math.h>
#include <stdio.h>

#define AG_BROWSER_GAP 1.0

@interface NSBrowser () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation NSBrowser

- (instancetype)initWithFrame:(NSRect)frameRect
{
	NSRect documentFrame = NSMakeRect(0.0, 0.0, frameRect.size.width, frameRect.size.height);

	self = [super initWithFrame:frameRect];
	if (self == nil) {
		return nil;
	}
	_tables = [[NSMutableArray alloc] init];
	_columnCounts = [[NSMutableArray alloc] init];
	_selectedRows = [[NSMutableArray alloc] init];
	_titles = [[NSMutableArray alloc] init];
	_columnWidth = 200.0;
	_minColumnWidth = 100.0;
	_rowHeight = 18.0;
	_titleHeight = 18.0;
	_maxVisibleColumns = 3;
	_selectedColumn = -1;
	_firstVisibleColumn = 0;
	_columnResizingType = NSBrowserNoColumnResizing;
	_pathSeparator = [@"/" copy];
	_cellClass = [NSBrowserCell class];
	_separatesColumns = YES;
	_allowsEmptySelection = YES;
	_hasHorizontalScroller = YES;
	_acceptsArrowKeys = YES;
	_backgroundColor = [[NSColor whiteColor] retain];

	_documentView = [[NSView alloc] initWithFrame:documentFrame];
	_scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
	[_scrollView setHasVerticalScroller:YES];
	[_scrollView setHasHorizontalScroller:_hasHorizontalScroller];
	[_scrollView setBorderType:NSNoBorder];
	[_scrollView setDrawsBackground:YES];
	[_scrollView setBackgroundColor:[NSColor colorWithCalibratedWhite:0.82 alpha:1.0]];
	[_scrollView setDocumentView:_documentView];
	[self addSubview:_scrollView];
	return self;
}

- (void)dealloc
{
	[_tables release];
	[_columnCounts release];
	[_selectedRows release];
	[_titles release];
	[_scrollView release];
	[_documentView release];
	[_cellPrototype release];
	[_pathSeparator release];
	[_backgroundColor release];
	[super dealloc];
}

- (id <NSBrowserDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id <NSBrowserDelegate>)delegate { _delegate = delegate; }

/* ---- THE COLUMNS ----------------------------------------------------------------------------- */

- (NSInteger)columnForTable:(NSTableView *)table
{
	NSUInteger index = [_tables indexOfObjectIdenticalTo:table];

	return (index == NSNotFound) ? -1 : (NSInteger)index;
}

- (NSInteger)rowsForColumn:(NSInteger)column
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:numberOfRowsInColumn:)]) {
		return [_delegate browser:self numberOfRowsInColumn:column];
	}
	return 0;
}

- (NSCell *)newDataCell
{
	NSCell *cell;

	if (_cellPrototype != nil) {
		return [[_cellPrototype copy] autorelease];
	}
	cell = [[_cellClass alloc] init];
	return [cell autorelease];
}

- (NSTableView *)createTableForColumn:(NSInteger)column rows:(NSInteger)rows
{
	NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:@"browser"];
	NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, _columnWidth, _rowHeight)];
	NSCell *cell = [self newDataCell];

	[tableColumn setWidth:_columnWidth];
	[tableColumn setDataCell:cell];
	[table addTableColumn:tableColumn];
	[tableColumn release];
	[table setHeaderView:nil];
	[table setRowHeight:_rowHeight];
	[table setIntercellSpacing:NSMakeSize(0.0, 0.0)];
	[table setGridStyleMask:NSTableViewGridNone];
	[table setAllowsColumnReordering:NO];
	[table setAllowsColumnResizing:NO];
	[table setAllowsMultipleSelection:_allowsMultipleSelection];
	[table setAllowsEmptySelection:_allowsEmptySelection];
	[table setBackgroundColor:_backgroundColor];
	[table setDataSource:self];
	[table setDelegate:self];
	[table setDoubleAction:@selector(cg_tableDoubleClicked:)];
	[_documentView addSubview:table];
	[_tables addObject:table];
	[_columnCounts addObject:[NSNumber numberWithInteger:rows]];
	[_selectedRows addObject:[NSNumber numberWithInteger:-1]];
	[_titles addObject:[NSNull null]];
	/* THE COUNT MUST BE IN THE ARRAY BEFORE THE TABLE ASKS FOR ROWS: the table is this browser's data source and
	 * finds its column by identity, so a reload before registration answers zero. */
	[table reloadData];
	[table release];
	return [_tables lastObject];
}

- (void)ensureColumn:(NSInteger)column rows:(NSInteger)rows
{
	if (column < 0) {
		return;
	}
	if (column < (NSInteger)[_tables count]) {
		NSTableView *table = [_tables objectAtIndex:(NSUInteger)column];

		[_columnCounts replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:rows]];
		[table reloadData];
		return;
	}
	(void)[self createTableForColumn:column rows:rows];
}

- (void)truncateColumnsAfter:(NSInteger)column
{
	NSInteger i;

	for (i = (NSInteger)[_tables count] - 1; i > column; i--) {
		NSTableView *table = [_tables objectAtIndex:(NSUInteger)i];

		[table removeFromSuperview];
		[_tables removeObjectAtIndex:(NSUInteger)i];
		[_columnCounts removeObjectAtIndex:(NSUInteger)i];
		[_selectedRows removeObjectAtIndex:(NSUInteger)i];
		[_titles removeObjectAtIndex:(NSUInteger)i];
	}
	if (_selectedColumn > column) {
		_selectedColumn = (column >= 0 && column < (NSInteger)[_tables count]) ? column : -1;
	}
}

- (void)loadColumnZero
{
	NSInteger rows;

	[self truncateColumnsAfter:-1];
	_selectedColumn = -1;
	_firstVisibleColumn = 0;
	rows = [self rowsForColumn:0];
	if (rows > 0) {
		(void)[self createTableForColumn:0 rows:rows];
	}
	[self tile];
	[self scrollColumnToVisible:0];
}

- (void)reloadColumn:(NSInteger)column
{
	NSTableView *table;
	NSInteger rows;
	NSInteger selected;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return;
	}
	table = [_tables objectAtIndex:(NSUInteger)column];
	rows = [self rowsForColumn:column];
	selected = [[_selectedRows objectAtIndex:(NSUInteger)column] integerValue];
	[_columnCounts replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:rows]];
	[self truncateColumnsAfter:column];
	[table reloadData];
	if (selected >= rows) {
		selected = -1;
	}
	[_selectedRows replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:selected]];
	if (selected >= 0) {
		NSInteger nextRows;

		_selectedColumn = column;
		[table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selected]
		   byExtendingSelection:NO];
		/* **A RELOAD KEEPS THE SELECTION, SO NO NOTIFICATION LOADS THE NEXT COLUMN.** The table's selection is
		 * already the row we are restoring, and `-selectRowIndexes:` correctly treats that as no change. The column
		 * to the right is therefore asked for HERE, the same way a fresh selection asks for it. */
		nextRows = [self rowsForColumn:column + 1];
		if (nextRows > 0) {
			[self ensureColumn:column + 1 rows:nextRows];
		}
	} else {
		_selectedColumn = -1;
		[table deselectAll:nil];
	}
	[self tile];
}

- (void)reloadData
{
	[self loadColumnZero];
}

- (NSInteger)numberOfRowsInColumn:(NSInteger)column
{
	if (column >= 0 && column < (NSInteger)[_columnCounts count]) {
		return [[_columnCounts objectAtIndex:(NSUInteger)column] integerValue];
	}
	return 0;
}

/* ---- THE SELECTION --------------------------------------------------------------------------- */

- (NSInteger)selectedColumn { return _selectedColumn; }

- (NSInteger)selectedRowInColumn:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_selectedRows count]) {
		return -1;
	}
	return [[_selectedRows objectAtIndex:(NSUInteger)column] integerValue];
}

- (NSIndexSet *)selectedRowIndexesInColumn:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return nil;
	}
	return [[_tables objectAtIndex:(NSUInteger)column] selectedRowIndexes];
}

- (NSCell *)selectedCell
{
	NSTableView *table;
	NSInteger row;

	if (_selectedColumn < 0 || _selectedColumn >= (NSInteger)[_tables count]) {
		return nil;
	}
	table = [_tables objectAtIndex:(NSUInteger)_selectedColumn];
	row = [self selectedRowInColumn:_selectedColumn];
	return (row >= 0) ? [table preparedCellAtColumn:0 row:row] : nil;
}

- (NSArray *)selectedCells
{
	NSMutableArray *cells = [[NSMutableArray alloc] init];
	NSInteger i;

	for (i = 0; i < (NSInteger)[_tables count]; i++) {
		NSInteger row = [self selectedRowInColumn:i];

		if (row >= 0) {
			NSCell *cell = [[_tables objectAtIndex:(NSUInteger)i] preparedCellAtColumn:0 row:row];

			if (cell != nil) {
				[cells addObject:cell];
			}
		}
	}
	return [cells autorelease];
}

- (void)selectRowIndexes:(NSIndexSet *)indexes inColumn:(NSInteger)column
{
	NSTableView *table;
	BOOL previous = _inProgrammaticSelection;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return;
	}
	table = [_tables objectAtIndex:(NSUInteger)column];
	_inProgrammaticSelection = YES;
	if (indexes == nil || [indexes count] == 0) {
		[table deselectAll:nil];
	} else {
		[table selectRowIndexes:indexes byExtendingSelection:NO];
	}
	_inProgrammaticSelection = previous;
}

- (void)selectRow:(NSInteger)row inColumn:(NSInteger)column
{
	if (row < 0) {
		[self selectRowIndexes:nil inColumn:column];
	} else {
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] inColumn:column];
	}
}

/* ---- THE PATH -------------------------------------------------------------------------------- */

- (NSString *)pathSeparator { return _pathSeparator; }

- (void)setPathSeparator:(NSString *)separator
{
	NSString *copy = [(separator != nil ? separator : @"/") copy];

	[_pathSeparator release];
	_pathSeparator = copy;
}

- (NSString *)stringForCellAtRow:(NSInteger)row column:(NSInteger)column
{
	NSTableView *table;
	NSCell *cell;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return @"";
	}
	table = [_tables objectAtIndex:(NSUInteger)column];
	cell = [table preparedCellAtColumn:0 row:row];
	return ([cell stringValue] != nil) ? [cell stringValue] : @"";
}

- (NSString *)path
{
	NSMutableArray *parts = [[NSMutableArray alloc] init];
	NSInteger i;

	for (i = 0; i < (NSInteger)[_tables count]; i++) {
		NSInteger row = [self selectedRowInColumn:i];

		if (row < 0) {
			break;
		}
		[parts addObject:[self stringForCellAtRow:row column:i]];
	}
	return [parts count] > 0 ? [parts componentsJoinedByString:_pathSeparator] : nil;
}

- (NSString *)selectedPath { return [self path]; }
- (void)setSelectedPath:(NSString *)path { [self setPath:path]; }

- (void)setPath:(NSString *)path
{
	NSArray *parts;
	NSUInteger i;

	[self loadColumnZero];
	if (path == nil || [path length] == 0) {
		return;
	}
	parts = [path componentsSeparatedByString:_pathSeparator];
	for (i = 0; i < [parts count]; i++) {
		NSString *part = [parts objectAtIndex:i];
		NSInteger column = (NSInteger)i;
		NSInteger rows;
		NSInteger row;
		BOOL found = NO;

		if (column >= (NSInteger)[_tables count]) {
			break;
		}
		rows = [self numberOfRowsInColumn:column];
		for (row = 0; row < rows; row++) {
			if ([[self stringForCellAtRow:row column:column] isEqual:part]) {
				found = YES;
				break;
			}
		}
		if (!found) {
			break;
		}
		[self selectRow:row inColumn:column];
	}
}

/* ---- THE TABLE'S DATA SOURCE AND DELEGATE ---------------------------------------------------- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	NSInteger column = [self columnForTable:tableView];

	return (column >= 0) ? [self numberOfRowsInColumn:column] : 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	(void)tableColumn;
	(void)row;
	return nil;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSInteger column = [self columnForTable:tableView];

	(void)tableColumn;
	if (column >= 0 && _delegate != nil
	    && [_delegate respondsToSelector:@selector(browser:willDisplayCell:atRow:column:)]) {
		[_delegate browser:self willDisplayCell:cell atRow:row column:column];
	}
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	NSInteger column = [self columnForTable:tableView];

	if (column < 0) {
		return NO;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:selectRow:inColumn:)]) {
		BOOL answer = [_delegate browser:self selectRow:row inColumn:column];
		return answer;
	}
	return YES;
}

- (NSIndexSet *)tableView:(NSTableView *)tableView
    selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes
{
	NSInteger column = [self columnForTable:tableView];

	if (column >= 0 && _delegate != nil
	    && [_delegate respondsToSelector:@selector(browser:selectionIndexesForProposedSelection:inColumn:)]) {
		return [_delegate browser:self selectionIndexesForProposedSelection:proposedSelectionIndexes
				  inColumn:column];
	}
	return proposedSelectionIndexes;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSTableView *table = [notification object];
	NSInteger column = [self columnForTable:table];
	NSInteger row;
	NSInteger nextRows;

	if (column < 0) {
		return;
	}
	row = [table selectedRow];
	[_selectedRows replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:row]];
	if (row >= 0) {
		_selectedColumn = column;
	} else if (_selectedColumn == column) {
		_selectedColumn = -1;
	}
	[self truncateColumnsAfter:column];
	if (row >= 0) {
		nextRows = [self rowsForColumn:column + 1];
		if (nextRows > 0) {
			[self ensureColumn:column + 1 rows:nextRows];
		}
	}
	[self tile];
	[self scrollColumnToVisible:(row >= 0) ? column : _selectedColumn];
	if (!_inProgrammaticSelection && [self action] != NULL) {
		[[NSApplication sharedApplication] sendAction:[self action] to:[self target] from:self];
	}
}

- (void)cg_tableDoubleClicked:(id)sender
{
	(void)sender;
	if (_doubleAction != NULL) {
		[[NSApplication sharedApplication] sendAction:_doubleAction to:[self target] from:self];
	}
}

- (SEL)doubleAction { return _doubleAction; }
- (void)setDoubleAction:(SEL)action { _doubleAction = action; }

/* ---- GEOMETRY -------------------------------------------------------------------------------- */

- (CGFloat)columnWidth { return _columnWidth; }
- (CGFloat)minColumnWidth { return _minColumnWidth; }
- (NSInteger)maxVisibleColumns { return _maxVisibleColumns; }
- (BOOL)separatesColumns { return _separatesColumns; }
- (BOOL)allowsMultipleSelection { return _allowsMultipleSelection; }
- (BOOL)allowsEmptySelection { return _allowsEmptySelection; }
- (BOOL)takesTitleFromPreviousColumn { return _takesTitleFromPreviousColumn; }
- (BOOL)hasHorizontalScroller { return _hasHorizontalScroller; }
- (BOOL)acceptsArrowKeys { return _acceptsArrowKeys; }
- (BOOL)sendsActionOnArrowKeys { return _sendsActionOnArrowKeys; }
- (CGFloat)rowHeight { return _rowHeight; }
- (CGFloat)titleHeight { return _titleHeight; }
- (NSBrowserColumnResizingType)columnResizingType { return _columnResizingType; }
- (NSColor *)backgroundColor { return _backgroundColor; }

- (void)tile
{
	CGFloat gap = _separatesColumns ? AG_BROWSER_GAP : 0.0;
	CGFloat step = _columnWidth + gap;
	CGFloat maxHeight = [self bounds].size.height;
	NSUInteger i;

	for (i = 0; i < [_tables count]; i++) {
		NSInteger rows = [[_columnCounts objectAtIndex:i] integerValue];
		CGFloat tableHeight = (CGFloat)rows * _rowHeight;

		if (tableHeight > maxHeight) {
			maxHeight = tableHeight;
		}
	}
	{
		/* THE CLIP VIEW CENTRES A DOCUMENT SMALLER THAN ITSELF, so one column in a wide browser would sit in the
		 * middle. The document is made at least as wide as the browser; the column stays at the left edge. */
		CGFloat documentWidth = (CGFloat)[_tables count] * step;

		if (documentWidth < [self bounds].size.width) {
			documentWidth = [self bounds].size.width;
		}
		[_documentView setFrame:NSMakeRect(0.0, 0.0, documentWidth, maxHeight)];
	}
	for (i = 0; i < [_tables count]; i++) {
		NSTableView *table = [_tables objectAtIndex:i];
		NSArray *columns = [table tableColumns];

		[table setFrame:NSMakeRect((CGFloat)i * step, 0.0, _columnWidth, maxHeight)];
		if ([columns count] > 0) {
			[[columns objectAtIndex:0] setWidth:_columnWidth];
		}
	}
	[_scrollView setFrame:[self bounds]];
	[_scrollView setHasHorizontalScroller:_hasHorizontalScroller];
	[_scrollView setBackgroundColor:_separatesColumns ? [NSColor colorWithCalibratedWhite:0.82 alpha:1.0] : _backgroundColor];
	[_scrollView tile];
	_firstVisibleColumn = [self firstVisibleColumn];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	(void)oldSize;
	[self tile];
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self tile];
}

- (void)setColumnWidth:(CGFloat)width
{
	if (width < _minColumnWidth) {
		width = _minColumnWidth;
	}
	_columnWidth = width;
	[self tile];
}

- (void)setMinColumnWidth:(CGFloat)width
{
	_minColumnWidth = (width > 0.0) ? width : 1.0;
	if (_columnWidth < _minColumnWidth) {
		_columnWidth = _minColumnWidth;
	}
	[self tile];
}

- (void)setMaxVisibleColumns:(NSInteger)count
{
	_maxVisibleColumns = (count > 0) ? count : 1;
	[self tile];
}

- (void)setSeparatesColumns:(BOOL)flag
{
	_separatesColumns = flag ? YES : NO;
	[self tile];
}

- (void)setAllowsMultipleSelection:(BOOL)flag
{
	NSUInteger i;

	_allowsMultipleSelection = flag ? YES : NO;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setAllowsMultipleSelection:_allowsMultipleSelection];
	}
}

- (void)setAllowsEmptySelection:(BOOL)flag
{
	NSUInteger i;

	_allowsEmptySelection = flag ? YES : NO;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setAllowsEmptySelection:_allowsEmptySelection];
	}
}

- (void)setTakesTitleFromPreviousColumn:(BOOL)flag { _takesTitleFromPreviousColumn = flag ? YES : NO; }
- (void)setHasHorizontalScroller:(BOOL)flag
{
	_hasHorizontalScroller = flag ? YES : NO;
	[self tile];
}
- (void)setAcceptsArrowKeys:(BOOL)flag { _acceptsArrowKeys = flag ? YES : NO; }
- (void)setSendsActionOnArrowKeys:(BOOL)flag { _sendsActionOnArrowKeys = flag ? YES : NO; }

- (void)setRowHeight:(CGFloat)height
{
	NSUInteger i;

	_rowHeight = (height > 0.0) ? height : 1.0;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setRowHeight:_rowHeight];
	}
	[self tile];
}

- (void)setTitleHeight:(CGFloat)height { _titleHeight = height; }
- (void)setColumnResizingType:(NSBrowserColumnResizingType)type { _columnResizingType = type; }

- (void)setBackgroundColor:(NSColor *)color
{
	NSUInteger i;

	[color retain];
	[_backgroundColor release];
	_backgroundColor = color;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setBackgroundColor:_backgroundColor];
	}
	[self tile];
}

- (NSInteger)numberOfVisibleColumns
{
	CGFloat step = _columnWidth + (_separatesColumns ? AG_BROWSER_GAP : 0.0);
	NSInteger visible = (NSInteger)floor([self bounds].size.width / step);

	if (visible < 1) visible = 1;
	if (visible > (NSInteger)[_tables count]) visible = (NSInteger)[_tables count];
	return visible;
}

- (NSInteger)firstVisibleColumn
{
	CGFloat step = _columnWidth + (_separatesColumns ? AG_BROWSER_GAP : 0.0);
	CGFloat x = [[_scrollView contentView] bounds].origin.x;

	return (NSInteger)floor(x / step);
}

- (NSInteger)lastVisibleColumn
{
	NSInteger first = [self firstVisibleColumn];

	return first + [self numberOfVisibleColumns] - 1;
}

- (void)scrollColumnToVisible:(NSInteger)column
{
	CGFloat step;
	CGFloat x;
	CGFloat origin;
	CGFloat width;
	NSPoint point;

	if (column < 0) {
		return;
	}
	step = _columnWidth + (_separatesColumns ? AG_BROWSER_GAP : 0.0);
	x = (CGFloat)column * step;
	width = [[_scrollView contentView] bounds].size.width;
	origin = [[_scrollView contentView] bounds].origin.x;
	if (x < origin || x + _columnWidth > origin + width) {
		point = NSMakePoint(x, 0.0);
		[[_scrollView contentView] scrollToPoint:point];
		[_scrollView reflectScrolledClipView:[_scrollView contentView]];
	}
	_firstVisibleColumn = [self firstVisibleColumn];
}

/* ---- THE CELL, THE TITLE AND THE SEAMS ------------------------------------------------------- */

- (Class)cellClass { return _cellClass; }

- (void)setCellClass:(Class)cellClass
{
	NSUInteger i;

	_cellClass = (cellClass != Nil) ? cellClass : [NSBrowserCell class];
	for (i = 0; i < [_tables count]; i++) {
		NSArray *columns = [[_tables objectAtIndex:i] tableColumns];

		if ([columns count] > 0) {
			[[columns objectAtIndex:0] setDataCell:[self newDataCell]];
		}
	}
	[self reloadData];
}

- (NSCell *)cellPrototype { return _cellPrototype; }

- (void)setCellPrototype:(NSCell *)cell
{
	NSUInteger i;

	[cell retain];
	[_cellPrototype release];
	_cellPrototype = cell;
	for (i = 0; i < [_tables count]; i++) {
		NSArray *columns = [[_tables objectAtIndex:i] tableColumns];

		if ([columns count] > 0) {
			[[columns objectAtIndex:0] setDataCell:[self newDataCell]];
		}
	}
	[self reloadData];
}

- (void)setTitle:(NSString *)title ofColumn:(NSInteger)column
{
	while ((NSInteger)[_titles count] <= column) {
		[_titles addObject:[NSNull null]];
	}
	[_titles replaceObjectAtIndex:(NSUInteger)column
			     withObject:(title != nil) ? (id)title : (id)[NSNull null]];
}

- (NSString *)titleOfColumn:(NSInteger)column
{
	id title;

	if (column >= 0 && column < (NSInteger)[_titles count]) {
		title = [_titles objectAtIndex:(NSUInteger)column];
		if (title != [NSNull null]) {
			return title;
		}
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:titleOfColumn:)]) {
		return [_delegate browser:self titleOfColumn:column];
	}
	return nil;
}

- (NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column
{
	(void)sender;
	return [self titleOfColumn:column];
}

- (NSInteger)cg_columnCount { return (NSInteger)[_tables count]; }
- (NSTableView *)cg_tableForColumn:(NSInteger)column
{
	return (column >= 0 && column < (NSInteger)[_tables count])
		? [_tables objectAtIndex:(NSUInteger)column] : nil;
}
- (NSView *)cg_documentView { return _documentView; }

@end
