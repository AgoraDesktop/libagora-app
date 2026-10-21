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
#import "NSText.h"
#import "NSImage.h"
#import "NSBitmapImageRep.h"
#import "NSWindow.h"
#import "NSPasteboard.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSSortDescriptor.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#include <math.h>

NSString *NSTableViewSelectionDidChangeNotification = @"NSTableViewSelectionDidChangeNotification";
NSString *NSTableViewSelectionIsChangingNotification = @"NSTableViewSelectionIsChangingNotification";
NSString *NSTableViewColumnDidMoveNotification = @"NSTableViewColumnDidMoveNotification";
NSString *NSTableViewColumnDidResizeNotification = @"NSTableViewColumnDidResizeNotification";

/* THE LOCAL DRAG'S INFO. `NSDraggingInfo` is a protocol, not a class, so the table's own drag needs an object that
 * answers the three questions its data source reads. The type, the pasteboard and the operation mask are enough for
 * the data-source contract; the cross-process session remains absent. */
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
- (void)cg_rebuildRowHeights;
- (CGFloat)cg_rowHeightAtIndex:(NSInteger)row;
- (void)cg_saveAutosave;
- (void)cg_loadAutosave;
- (NSString *)cg_autosaveKey;
- (BOOL)cg_typeSelectWithEvent:(NSEvent *)event;
- (void)doneDragging;
- (NSDragOperation)cg_validateDrop:(id <NSDraggingInfo>)info;
- (NSString *)cg_typeSelectStringForRow:(NSInteger)row;
@end

@implementation NSTableView

/* ============================================================================================
 * ARCHIVING: THE COLUMNS AND THE LOOK, NOT THE ROWS THE DATA SOURCE SUPPLIES.
 * ============================================================================================ */
/* **A TABLE'S ROWS ARE NOT IN IT.** The row count, the selected indexes, the edited row and column, the cached row tops
 * and heights, the type-select buffer and the drag's five pieces of state are all what happens when a table is RUNNING
 * against a data source; the data source and delegate are CONNECTIONS. What a design says is its COLUMNS (which are
 * archivable objects), its geometry, its colours, its grid, its selection style and its behaviour flags. The columns go
 * back through `-addTableColumn:`, which is the door that re-parents each column onto this table. */
static NSString * const AGCoderTableColumnsKey = @"tableColumns";
static NSString * const AGCoderTableHeaderViewKey = @"headerView";
static NSString * const AGCoderTableCornerViewKey = @"cornerView";
static NSString * const AGCoderTableBackgroundKey = @"backgroundColor";
static NSString * const AGCoderTableGridColorKey = @"gridColor";
static NSString * const AGCoderTableRowHeightKey = @"rowHeight";
static NSString * const AGCoderTableIntercellKey = @"intercellSpacing";
static NSString * const AGCoderTableGridStyleKey = @"gridStyleMask";
static NSString * const AGCoderTableAutosaveKey = @"autosaveName";
static NSString * const AGCoderTableAutosaveColumnsKey = @"autosaveTableColumns";
static NSString * const AGCoderTableAutoresizeKey = @"columnAutoresizingStyle";
static NSString * const AGCoderTableHighlightKey = @"selectionHighlightStyle";
static NSString * const AGCoderTableDoubleActionKey = @"doubleAction";
static NSString * const AGCoderTableReorderKey = @"allowsColumnReordering";
static NSString * const AGCoderTableResizeKey = @"allowsColumnResizing";
static NSString * const AGCoderTableMultipleKey = @"allowsMultipleSelection";
static NSString * const AGCoderTableEmptyKey = @"allowsEmptySelection";
static NSString * const AGCoderTableColumnSelectionKey = @"allowsColumnSelection";
static NSString * const AGCoderTableAlternatingKey = @"usesAlternatingRowBackgroundColors";
static NSString * const AGCoderTableTypeSelectKey = @"allowsTypeSelect";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_tableColumns forKey:AGCoderTableColumnsKey];
	[aCoder encodeObject:_headerView forKey:AGCoderTableHeaderViewKey];
	[aCoder encodeObject:_cornerView forKey:AGCoderTableCornerViewKey];
	[aCoder encodeObject:_backgroundColor forKey:AGCoderTableBackgroundKey];
	[aCoder encodeObject:_gridColor forKey:AGCoderTableGridColorKey];
	[aCoder encodeDouble:(double)_rowHeight forKey:AGCoderTableRowHeightKey];
	[aCoder encodeSize:_intercellSpacing forKey:AGCoderTableIntercellKey];
	[aCoder encodeInteger:(NSInteger)_gridStyleMask forKey:AGCoderTableGridStyleKey];
	[aCoder encodeObject:_autosaveName forKey:AGCoderTableAutosaveKey];
	[aCoder encodeBool:_autosaveTableColumns forKey:AGCoderTableAutosaveColumnsKey];
	[aCoder encodeInteger:(NSInteger)_columnAutoresizingStyle forKey:AGCoderTableAutoresizeKey];
	[aCoder encodeInteger:(NSInteger)_selectionHighlightStyle forKey:AGCoderTableHighlightKey];
	[aCoder encodeObject:(_doubleAction != NULL) ? NSStringFromSelector(_doubleAction) : nil
		      forKey:AGCoderTableDoubleActionKey];
	[aCoder encodeBool:_allowsColumnReordering forKey:AGCoderTableReorderKey];
	[aCoder encodeBool:_allowsColumnResizing forKey:AGCoderTableResizeKey];
	[aCoder encodeBool:_allowsMultipleSelection forKey:AGCoderTableMultipleKey];
	[aCoder encodeBool:_allowsEmptySelection forKey:AGCoderTableEmptyKey];
	[aCoder encodeBool:_allowsColumnSelection forKey:AGCoderTableColumnSelectionKey];
	[aCoder encodeBool:_usesAlternatingRowBackgroundColors forKey:AGCoderTableAlternatingKey];
	[aCoder encodeBool:_allowsTypeSelect forKey:AGCoderTableTypeSelectKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderTableHeaderViewKey]) {
		_headerView = [[aDecoder decodeObjectForKey:AGCoderTableHeaderViewKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderTableCornerViewKey]) {
		_cornerView = [[aDecoder decodeObjectForKey:AGCoderTableCornerViewKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderTableBackgroundKey]) {
		_backgroundColor = [[aDecoder decodeObjectForKey:AGCoderTableBackgroundKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderTableGridColorKey]) {
		_gridColor = [[aDecoder decodeObjectForKey:AGCoderTableGridColorKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderTableRowHeightKey]) {
		_rowHeight = [aDecoder decodeDoubleForKey:AGCoderTableRowHeightKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableGridStyleKey]) {
		_gridStyleMask = [aDecoder decodeIntegerForKey:AGCoderTableGridStyleKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableAutosaveKey]) {
		_autosaveName = [[aDecoder decodeObjectForKey:AGCoderTableAutosaveKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderTableAutosaveColumnsKey]) {
		_autosaveTableColumns = [aDecoder decodeBoolForKey:AGCoderTableAutosaveColumnsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableAutoresizeKey]) {
		_columnAutoresizingStyle = (NSTableViewColumnAutoresizingStyle)[aDecoder decodeIntegerForKey:AGCoderTableAutoresizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableHighlightKey]) {
		_selectionHighlightStyle = (NSTableViewSelectionHighlightStyle)[aDecoder decodeIntegerForKey:AGCoderTableHighlightKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableReorderKey]) {
		_allowsColumnReordering = [aDecoder decodeBoolForKey:AGCoderTableReorderKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableResizeKey]) {
		_allowsColumnResizing = [aDecoder decodeBoolForKey:AGCoderTableResizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableMultipleKey]) {
		_allowsMultipleSelection = [aDecoder decodeBoolForKey:AGCoderTableMultipleKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableEmptyKey]) {
		_allowsEmptySelection = [aDecoder decodeBoolForKey:AGCoderTableEmptyKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableColumnSelectionKey]) {
		_allowsColumnSelection = [aDecoder decodeBoolForKey:AGCoderTableColumnSelectionKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableAlternatingKey]) {
		_usesAlternatingRowBackgroundColors = [aDecoder decodeBoolForKey:AGCoderTableAlternatingKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableTypeSelectKey]) {
		_allowsTypeSelect = [aDecoder decodeBoolForKey:AGCoderTableTypeSelectKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableIntercellKey]) {
		_intercellSpacing = [aDecoder decodeSizeForKey:AGCoderTableIntercellKey];
	}
	if ([aDecoder containsValueForKey:AGCoderTableDoubleActionKey]) {
		NSString *name = [aDecoder decodeObjectForKey:AGCoderTableDoubleActionKey];

		if ([name isKindOfClass:[NSString class]]) {
			_doubleAction = NSSelectorFromString(name);
		}
	}
	if ([aDecoder containsValueForKey:AGCoderTableColumnsKey]) {
		id columns = [aDecoder decodeObjectForKey:AGCoderTableColumnsKey];
		NSUInteger i;

		if ([columns isKindOfClass:[NSArray class]]) {
			for (i = 0; i < [(NSArray *)columns count]; i++) {
				id column = [(NSArray *)columns objectAtIndex:i];

				if ([column isKindOfClass:[NSTableColumn class]]) {
					[self addTableColumn:column];
				}
			}
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


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
		_cgRowTops = [[NSMutableArray alloc] init];
		_cgRowHeights = [[NSMutableArray alloc] init];
		_editedRow = -1;
		_editedColumn = -1;
		_cgEditingCell = nil;
		_cgTypeSelectString = [[NSMutableString alloc] init];
		_cgTypeSelectTime = 0.0;
		_autosaveName = nil;
		_autosaveTableColumns = NO;
		_cgLocalDragMask = NSDragOperationEvery;
		_cgNonLocalDragMask = NSDragOperationNone;
		_cgDropRow = -1;
		_cgDropOperation = NSTableViewDropOn;
		_cgDragRows = nil;
		_cgDragPasteboard = nil;
		_cgDragging = NO;
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
	[_cgRowTops release];
	[_cgRowHeights release];
	[_cgEditingCell release];
	[_cgTypeSelectString release];
	[_autosaveName release];
	[_cgDragRows release];
	[_cgDragPasteboard release];
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
	[self cg_rebuildRowHeights];
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

/* **ROW HEIGHTS ARE CACHED, BECAUSE THE GEOMETRY ASKS FOR THEM CONSTANTLY.** One top and one extent per row are
 * rebuilt from the delegate's `-tableView:heightOfRow:` (or `_rowHeight` when it does not answer); `-rectOfRow:`,
 * `-rowAtPoint:`, `-rowsInRect:` and `-tile` then read the cache rather than asking the model. `-reloadData`,
 * `-noteNumberOfRowsChanged` and `-noteHeightOfRowsWithIndexesChanged:` invalidate it, which is Apple's rule. */
- (CGFloat)cg_rowHeightAtIndex:(NSInteger)row
{
	if (row < 0 || (NSUInteger)row >= [_cgRowHeights count]) {
		return _rowHeight;
	}
	return (CGFloat)[[_cgRowHeights objectAtIndex:(NSUInteger)row] doubleValue];
}

- (void)cg_rebuildRowHeights
{
	CGFloat top = 0.0;
	NSInteger row;

	[_cgRowTops removeAllObjects];
	[_cgRowHeights removeAllObjects];
	for (row = 0; row < _numberOfRows; row++) {
		CGFloat height = _rowHeight;

		if (_delegate != nil && [_delegate respondsToSelector:@selector(tableView:heightOfRow:)]) {
			height = [_delegate tableView:self heightOfRow:row];
		}
		if (height < 1.0) {
			height = 1.0;
		}
		height = ceil(height);
		[_cgRowTops addObject:[NSNumber numberWithDouble:(double)top]];
		[_cgRowHeights addObject:[NSNumber numberWithDouble:(double)height]];
		top += height + _intercellSpacing.height;
	}
}

- (void)setRowHeight:(CGFloat)rowHeight
{
	_rowHeight = (rowHeight > 0.0) ? rowHeight : 1.0;
	[self cg_rebuildRowHeights];
	[self tile];
}

- (CGFloat)rowHeight { return _rowHeight; }

- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)indexSet
{
	(void)indexSet;
	[self cg_rebuildRowHeights];
	[self tile];
	[self setNeedsDisplay:YES];
}

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
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tableViewColumnDidMove:)]) {
		[_delegate tableViewColumnDidMove:
			[NSNotification notificationWithName:NSTableViewColumnDidMoveNotification object:self]];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:NSTableViewColumnDidMoveNotification object:self];
	[self cg_saveAutosave];
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
	if ((NSInteger)[_cgRowHeights count] != _numberOfRows) {
		[self cg_rebuildRowHeights];
	}
	height = 0.0;
	if ([_cgRowTops count] > 0) {
		height = (CGFloat)[[_cgRowTops lastObject] doubleValue]
			+ (CGFloat)[[_cgRowHeights lastObject] doubleValue];
	}
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

	if ((NSInteger)[_cgRowHeights count] != _numberOfRows) {
		[self cg_rebuildRowHeights];
	}
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
	{
		CGFloat height = 0.0;

		if ([_cgRowTops count] > 0) {
			height = (CGFloat)[[_cgRowTops lastObject] doubleValue]
				+ (CGFloat)[[_cgRowHeights lastObject] doubleValue];
		}
		[self setFrameSize:NSMakeSize(width, height)];
	}
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
	[self cg_rebuildRowHeights];
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
	[self cg_rebuildRowHeights];
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)reloadDataForRowIndexes:(NSIndexSet *)rowIndexes columnIndexes:(NSIndexSet *)columnIndexes
{
	(void)rowIndexes;
	(void)columnIndexes;
	[self setNeedsDisplay:YES];
}

- (NSInteger)editedColumn { return _editedColumn; }
- (NSInteger)editedRow { return _editedRow; }
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
	[self cg_saveAutosave];
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

- (void)setAllowsTypeSelect:(BOOL)value
{
	_allowsTypeSelect = value ? YES : NO;
	if (!_allowsTypeSelect) {
		[_cgTypeSelectString setString:@""];
	}
}
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
			/* **THE DELEGATE MAY RETURN THE PROPOSED SET ITSELF.** It is `allowed`, and releasing it before copying
			 * was a use-after-free: the copy read a deallocated set and the selection became EMPTY. MEASURED through
			 * `NSBrowser`, whose delegate returns the proposal unchanged. The retain keeps the same object alive
			 * across the release, and the copy is the table's own either way. */
			[answer retain];
			[allowed release];
			allowed = [[NSMutableIndexSet alloc] initWithIndexSet:answer];
			[answer release];
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
	if (row < 0 || row >= _numberOfRows || (NSUInteger)row >= [_cgRowTops count]) {
		return NSZeroRect;
	}
	return NSMakeRect(0.0, (CGFloat)[[_cgRowTops objectAtIndex:(NSUInteger)row] doubleValue],
			  [self frame].size.width, [self cg_rowHeightAtIndex:row]);
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
	NSInteger low = 0;
	NSInteger high = _numberOfRows - 1;

	if (point.y < 0.0 || _numberOfRows == 0 || (NSInteger)[_cgRowTops count] != _numberOfRows) {
		return -1;
	}
	while (low <= high) {
		NSInteger mid = (low + high) / 2;
		CGFloat top = (CGFloat)[[_cgRowTops objectAtIndex:(NSUInteger)mid] doubleValue];
		CGFloat bottom = top + [self cg_rowHeightAtIndex:mid];

		if (point.y < top) {
			high = mid - 1;
		} else if (point.y >= bottom) {
			low = mid + 1;
		} else {
			return mid;
		}
	}
	return -1;
}

- (NSRange)rowsInRect:(NSRect)rect
{
	NSInteger first;
	NSInteger last;

	if (_numberOfRows == 0 || NSIsEmptyRect(rect)) {
		return NSMakeRange(NSNotFound, 0);
	}
	if ((NSInteger)[_cgRowTops count] != _numberOfRows) {
		return NSMakeRange(NSNotFound, 0);
	}
	first = 0;
	while (first < _numberOfRows &&
	       (CGFloat)[[_cgRowTops objectAtIndex:(NSUInteger)first] doubleValue]
		       + [self cg_rowHeightAtIndex:first] <= NSMinY(rect)) {
		first++;
	}
	last = first;
	while (last + 1 < _numberOfRows &&
	       (CGFloat)[[_cgRowTops objectAtIndex:(NSUInteger)(last + 1)] doubleValue] < NSMaxY(rect)) {
		last++;
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
			/* **A SELECTED ROW IS A SELECTION, SO IT WEARS THE PLATFORM'S ACCENT** — the menu's chip says the same
			 * thing in a smaller shape, and its own note asks for the accent "on the whole row" in a list. The
			 * SOURCE-LIST style is the exception and stays a grey, because that style is a sidebar's, not a
			 * table's. The selected row's ink is `+selectedControlTextColor`, the white a text selection wears on
			 * this accent; `+selectedControlColor`, the era's blue, is a different colour on purpose and nothing in
			 * this tier paints a highlight with it any more. */
			NSColor *selection = (_selectionHighlightStyle == NSTableViewSelectionHighlightStyleSourceList)
				? [NSColor controlHighlightColor] : [NSColor cg_accentColor];

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
			/* **AND THE SELECTED ROW KEEPS THE DARK INK THE OTHER ROWS HAVE.** The plate is the platform's accent —
			 * a LIGHT periwinkle — and white on it is a wash, MEASURED: the row was legible and read as faded. The
			 * plate is what says "this row", the same division the segmented control's chip and the menu's chip
			 * make; white is a pressed button's ink, for the moment it is held, and a selection is not that.
			 *
			 * IT WAS `+selectedControlTextColor` (white) while the plate was the era's BLUE, and that pairing was
			 * right for a blue. A colour change is a whole pairing. */
			saved = [[(id)cell textColor] retain];
			[(id)cell setTextColor:[NSColor controlTextColor]];
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
	if (_cgDragging && _cgDropRow >= 0) {
		CGFloat y = 0.0;

		if (_cgDropRow < _numberOfRows) {
			y = NSMinY([self rectOfRow:_cgDropRow]);
		} else if (_numberOfRows > 0) {
			y = NSMaxY([self rectOfRow:_numberOfRows - 1]);
		}
		[[NSColor cg_accentColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, y - 1.0, [self frame].size.width, 2.0)] fill];
	}
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

	[_cgTypeSelectString setString:@""];
	_cgTypeSelectTime = 0.0;
	_cgDragStartPoint = point;
	_clickedRow = [self rowAtPoint:point];
	_clickedColumn = [self columnAtPoint:point];
	if ([event clickCount] >= 2) {
		if (_doubleAction != NULL) {
			[[NSApplication sharedApplication] sendAction:_doubleAction to:nil from:self];
		} else if (_clickedRow >= 0 && _clickedColumn >= 0) {
			[self editColumn:_clickedColumn row:_clickedRow withEvent:event select:YES];
		}
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

/* ---- THE ROW DRAG, THROUGH THE TIER'S DRAG SESSION ---------------------------------------------- */

/* **THE TABLE IS A DRAG SOURCE AND A DRAG DESTINATION, AND THE SESSION IS THE TIER'S RATHER THAN THIS FILE'S.**
 * The old half tracked its own motions, its own drop row and its own mouse-up; this one writes the data source's
 * pasteboard, snapshots the dragged rows into an image and calls `-dragImage:...`, and from then on the session owns
 * the pointer. The data source's three-answer contract is unchanged: `-tableView:validateDrop:...` is asked on every
 * `-draggingUpdated:`, and `-tableView:acceptDrop:...` is asked once when the destination is this table. The
 * difference is that the same drag can now be dropped on ANOTHER view that registered for the types — the point of
 * the session — and that the insertion line follows the session's pointer rather than a private one.
 *
 * THE IMAGE IS THE ROWS' OWN INK, captured through `-cacheDisplayInRect:toBitmapImageRep:` so it is a snapshot of
 * what the table drew (the selection plate included) rather than a second drawing routine that could disagree. */
- (void)mouseDragged:(NSEvent *)event
{
	NSPoint point;
	NSIndexSet *rows;
	NSPasteboard *pasteboard;
	NSRect unionRect = NSZeroRect;
	NSBitmapImageRep *rep;
	NSImage *image;
	NSUInteger row;
	BOOL first = YES;

	if (_clickedRow < 0 || _dataSource == nil || _cgDragging) {
		if (!_cgDragging) {
			[super mouseDragged:event];
		}
		return;
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	if (fabs((double)(point.x - _cgDragStartPoint.x)) < 4.0
	    && fabs((double)(point.y - _cgDragStartPoint.y)) < 4.0) {
		return;
	}
	rows = _selectedRowIndexes;
	if ([rows count] == 0 || ![rows containsIndex:(NSUInteger)_clickedRow]) {
		rows = [NSIndexSet indexSetWithIndex:(NSUInteger)_clickedRow];
	}
	if (![self canDragRowsWithIndexes:rows atPoint:_cgDragStartPoint]) {
		return;
	}
	pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
	if (pasteboard == nil) {
		return;
	}
	[pasteboard clearContents];
	if (![_dataSource tableView:self writeRowsWithIndexes:rows toPasteboard:pasteboard]) {
		return;
	}
	for (row = [rows firstIndex]; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
		NSRect rowRect = [self rectOfRow:(NSInteger)row];

		unionRect = first ? rowRect : NSUnionRect(unionRect, rowRect);
		first = NO;
	}
	if (first) {
		return;
	}
	rep = [self bitmapImageRepForCachingDisplayInRect:unionRect];
	if (rep == nil) {
		return;
	}
	[self cacheDisplayInRect:unionRect toBitmapImageRep:rep];
	image = [[NSImage alloc] initWithSize:unionRect.size];
	[image addRepresentation:rep];
	[_cgDragRows release];
	_cgDragRows = [rows copy];
	[_cgDragPasteboard release];
	_cgDragPasteboard = [pasteboard retain];
	_cgDragging = YES;
	[self dragImage:image at:unionRect.origin offset:NSZeroSize event:event pasteboard:pasteboard source:self
		 slideBack:YES];
	[image release];
	if ([NSDraggingSession cg_activeSession] == nil) {
		/* THE SESSION REFUSED (no window, no items), so the press remains an ordinary one rather than a table that
		 * believes a drag is in flight for ever. */
		_cgDragging = NO;
		[_cgDragRows release];
		_cgDragRows = nil;
		[_cgDragPasteboard release];
		_cgDragPasteboard = nil;
	}
}

/* THE SOURCE'S ENDED CALLBACK, in both eras' spellings: one of them fires, and either clears the local state. */
- (void)doneDragging
{
	_cgDragging = NO;
	_cgDropRow = -1;
	[_cgDragRows release];
	_cgDragRows = nil;
	[_cgDragPasteboard release];
	_cgDragPasteboard = nil;
	[self setNeedsDisplay:YES];
}

- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation
{
	(void)image; (void)screenPoint; (void)operation;
	[self doneDragging];
}

- (void)draggingSession:(NSDraggingSession *)session
	   endedAtPoint:(NSPoint)screenPoint
	    operation:(NSDragOperation)operation
{
	(void)session; (void)screenPoint; (void)operation;
	[self doneDragging];
}

/* ---- THE TABLE AS A DRAG DESTINATION ------------------------------------------------------------ */

/* **A TABLE IS A DESTINATION FOR ANY TYPE ITS DATA SOURCE WILL VALIDATE.** There is no pasteboard type to register:
 * the data source's `-tableView:validateDrop:...` IS the table's contract, and Apple's table accepts the drop on the
 * same terms. That is why `-cg_acceptsDraggedTypes:` is overridden rather than a list being registered in `-init`. */
- (BOOL)cg_acceptsDraggedTypes:(NSArray *)types
{
	(void)types;
	if (_dataSource != nil
	    && [_dataSource respondsToSelector:@selector(tableView:validateDrop:proposedRow:proposedDropOperation:)]) {
		return YES;
	}
	return [super cg_acceptsDraggedTypes:types];
}

/* THE PROPOSED ROW COMES FROM THE POINTER, exactly as it did in the private drag: above the midpoint is above the
 * row, below it is below. The operation is the data source's answer, and None clears the insertion line rather than
 * drawing a drop that will not happen. */
- (NSDragOperation)cg_validateDrop:(id <NSDraggingInfo>)info
{
	NSPoint point = [self convertPoint:[info draggingLocation] fromView:nil];
	NSInteger row = [self rowAtPoint:point];
	NSInteger proposedRow;
	NSDragOperation operation = NSDragOperationNone;

	if (row < 0) {
		proposedRow = (point.y < 0.0) ? 0 : _numberOfRows;
	} else {
		NSRect rowRect = [self rectOfRow:row];

		proposedRow = (point.y < NSMidY(rowRect)) ? row : row + 1;
	}
	_cgDropRow = proposedRow;
	_cgDropOperation = NSTableViewDropAbove;
	if ([_dataSource respondsToSelector:@selector(tableView:validateDrop:proposedRow:proposedDropOperation:)]) {
		operation = [_dataSource tableView:self validateDrop:info proposedRow:_cgDropRow
			       proposedDropOperation:_cgDropOperation];
	}
	if (operation == NSDragOperationNone) {
		_cgDropRow = -1;
	}
	[self setNeedsDisplay:YES];
	return operation;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)info
{
	return [self cg_validateDrop:info];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)info
{
	return [self cg_validateDrop:info];
}

- (void)draggingExited:(id <NSDraggingInfo>)info
{
	(void)info;
	_cgDropRow = -1;
	[self setNeedsDisplay:YES];
}

- (void)draggingEnded:(id <NSDraggingInfo>)info
{
	(void)info;
	_cgDropRow = -1;
	[self setNeedsDisplay:YES];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)info
{
	(void)info;
	return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)info
{
	BOOL accepted = NO;

	if (_cgDropRow >= 0
	    && [_dataSource respondsToSelector:@selector(tableView:acceptDrop:row:dropOperation:)]) {
		accepted = [_dataSource tableView:self acceptDrop:info row:_cgDropRow dropOperation:_cgDropOperation];
	}
	_cgDropRow = -1;
	[self setNeedsDisplay:YES];
	return accepted;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)info
{
	(void)info;
	_cgDropRow = -1;
	[self setNeedsDisplay:YES];
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
		if ([self cg_typeSelectWithEvent:event]) {
			return;
		}
		[super keyDown:event];
		return;
	}
	[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
	[self scrollRowToVisible:next];
}

/* ---- TYPE SELECT, EDITING, AUTOSAVE AND THE DRAG VOCABULARY ------------------------------------- */

/* **TYPE SELECT SEARCHES THE CELLS THE TABLE WOULD DRAW.** A delegate may name the string per column/row; without it,
 * the prepared cell's `-stringValue` is the text — Apple's default. The first visible column with text wins, and the
 * search starts at the selected row (or 0) and wraps. A one-second pause starts a new prefix, which is the standard
 * type-select rule. */
- (NSString *)cg_typeSelectStringForRow:(NSInteger)row
{
	NSInteger column;

	for (column = 0; column < (NSInteger)[_tableColumns count]; column++) {
		NSTableColumn *tableColumn = [_tableColumns objectAtIndex:(NSUInteger)column];
		NSString *string = nil;

		if ([tableColumn isHidden]) {
			continue;
		}
		if (_delegate != nil && [_delegate respondsToSelector:
					 @selector(tableView:typeSelectStringForTableColumn:row:)]) {
			string = [_delegate tableView:self typeSelectStringForTableColumn:tableColumn row:row];
		} else {
			NSCell *cell = [self preparedCellAtColumn:column row:row];

			string = [cell stringValue];
		}
		if (string != nil && [string length] > 0) {
			return string;
		}
	}
	return nil;
}

- (BOOL)cg_typeSelectWithEvent:(NSEvent *)event
{
	NSString *characters;
	unichar key;
	NSInteger start;
	NSInteger i;
	NSTimeInterval now;

	if (!_allowsTypeSelect || _numberOfRows == 0) {
		return NO;
	}
	if (([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask)) != 0) {
		return NO;
	}
	characters = [event charactersIgnoringModifiers];
	if ([characters length] == 0) {
		return NO;
	}
	key = [characters characterAtIndex:0];
	if (key < 0x20 || key == 0x7f) {
		return NO;
	}
	if (_delegate != nil && [_delegate respondsToSelector:
				 @selector(tableView:shouldTypeSelectForEvent:withCurrentSearchString:)]) {
		NSString *current = [_cgTypeSelectString length] > 0 ? _cgTypeSelectString : nil;

		if (![_delegate tableView:self shouldTypeSelectForEvent:event withCurrentSearchString:current]) {
			return NO;
		}
	}
	now = [NSDate timeIntervalSinceReferenceDate];
	if (now - _cgTypeSelectTime > 1.0) {
		[_cgTypeSelectString setString:@""];
	}
	_cgTypeSelectTime = now;
	[_cgTypeSelectString appendString:characters];
	start = [self selectedRow];
	if (start < 0 || start >= _numberOfRows) {
		start = 0;
	}
	for (;;) {
		for (i = 0; i < _numberOfRows; i++) {
			NSInteger row = (start + i) % _numberOfRows;
			NSString *string = [self cg_typeSelectStringForRow:row];

			if (string != nil
			    && [[string lowercaseString] hasPrefix:[_cgTypeSelectString lowercaseString]]) {
				[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
				     byExtendingSelection:NO];
				[self scrollRowToVisible:row];
				return YES;
			}
		}
		/* **A KEY THAT DOES NOT EXTEND THE PREFIX STARTS A NEW ONE.** Typing `c`, `h` selects "Charlie"; the next
		 * `d` makes `chd`, which matches nothing, so the search restarts at `d` — Apple's type-select behaviour,
		 * and the reason a fast typist can move from one name to another without waiting out the timeout. */
		if ([_cgTypeSelectString length] <= 1) {
			return NO;
		}
		{
			unichar last = [_cgTypeSelectString characterAtIndex:[_cgTypeSelectString length] - 1];

			[_cgTypeSelectString setString:[NSString stringWithCharacters:&last length:1]];
		}
	}
	return NO;
}

- (BOOL)shouldFocusCell:(NSCell *)cell atColumn:(NSInteger)column row:(NSInteger)row
{
	(void)column;
	(void)row;
	if (cell == nil || ![cell isEnabled]) {
		return NO;
	}
	if ([cell isKindOfClass:[NSTextFieldCell class]] && ![cell isEditable] && ![cell isSelectable]) {
		return NO;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tableView:shouldEditTableColumn:row:)]) {
		NSTableColumn *tableColumn = (column >= 0 && (NSUInteger)column < [_tableColumns count])
						   ? [_tableColumns objectAtIndex:(NSUInteger)column] : nil;

		return [_delegate tableView:self shouldEditTableColumn:tableColumn row:row];
	}
	return YES;
}

- (void)editColumn:(NSInteger)column row:(NSInteger)row withEvent:(NSEvent *)theEvent select:(BOOL)select
{
	NSTableColumn *tableColumn;
	NSCell *cell;
	NSText *editor;
	NSRect rect;

	if (row < 0 || row >= _numberOfRows || column < 0 || (NSUInteger)column >= [_tableColumns count]
	    || [self window] == nil) {
		return;
	}
	tableColumn = [_tableColumns objectAtIndex:(NSUInteger)column];
	if ([tableColumn isHidden]) {
		return;
	}
	cell = [self preparedCellAtColumn:column row:row];
	if (![self shouldFocusCell:cell atColumn:column row:row]
	    || ![cell respondsToSelector:@selector(selectWithFrame:inView:editor:delegate:start:length:)]) {
		return;
	}
	editor = [[self window] fieldEditor:YES forObject:self];
	if (editor == nil) {
		return;
	}
	[cell retain];
	[_cgEditingCell release];
	_cgEditingCell = cell;
	_editedRow = row;
	_editedColumn = column;
	rect = [self frameOfCellAtColumn:column row:row];
	if ([cell isKindOfClass:[NSTextFieldCell class]]) {
		if (select) {
			[(NSTextFieldCell *)cell selectWithFrame:rect inView:self editor:editor delegate:self start:0
							  length:(NSInteger)[[cell stringValue] length]];
		} else {
			[(NSTextFieldCell *)cell editWithFrame:rect inView:self editor:editor delegate:self
							 event:theEvent];
		}
	}
	[self setNeedsDisplay:YES];
}

- (NSText *)currentEditor
{
	if (_cgEditingCell != nil && [_cgEditingCell respondsToSelector:@selector(cg_currentEditor)]) {
		return [(NSTextFieldCell *)_cgEditingCell cg_currentEditor];
	}
	return nil;
}

- (BOOL)abortEditing
{
	BOOL aborted = NO;

	if (_cgEditingCell != nil && [_cgEditingCell respondsToSelector:@selector(cg_abortEditing)]) {
		aborted = [(NSTextFieldCell *)_cgEditingCell cg_abortEditing];
	}
	[_cgEditingCell release];
	_cgEditingCell = nil;
	_editedRow = -1;
	_editedColumn = -1;
	[self setNeedsDisplay:YES];
	return aborted;
}

/* **THE TABLE IS THE CELL'S CALLER DELEGATE, SO THE SESSION'S FIVE EVENTS ARRIVE HERE.** The two questions go on to
 * the table's delegate; the end is where the edited cell's value reaches the DATA SOURCE, which is the whole point of
 * an edit. `NSTextFieldCell` has already written the editor's string back into the cell by the time this is called. */
- (BOOL)textShouldBeginEditing:(NSText *)textObject
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(control:textShouldBeginEditing:)]) {
		return [_delegate control:self textShouldBeginEditing:textObject];
	}
	return YES;
}

- (BOOL)textShouldEndEditing:(NSText *)textObject
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(control:textShouldEndEditing:)]) {
		return [_delegate control:self textShouldEndEditing:textObject];
	}
	return YES;
}

- (void)textDidBeginEditing:(NSNotification *)notification
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:[notification object] forKey:NSFieldEditorUserInfoKey];

	[[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidBeginEditingNotification
							    object:self userInfo:info];
}

- (void)textDidChange:(NSNotification *)notification
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:[notification object] forKey:NSFieldEditorUserInfoKey];

	[[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification
							    object:self userInfo:info];
	[self setNeedsDisplayInRect:[self rectOfRow:_editedRow]];
}

- (void)textDidEndEditing:(NSNotification *)notification
{
	NSInteger row = _editedRow;
	NSInteger column = _editedColumn;
	NSCell *cell = _cgEditingCell;
	NSDictionary *info;

	_cgEditingCell = nil;
	_editedRow = -1;
	_editedColumn = -1;
	if (cell != nil && row >= 0 && column >= 0 && row < _numberOfRows
	    && (NSUInteger)column < [_tableColumns count]) {
		NSTableColumn *tableColumn = [_tableColumns objectAtIndex:(NSUInteger)column];

		if (_dataSource != nil && [_dataSource respondsToSelector:
					   @selector(tableView:setObjectValue:forTableColumn:row:)]) {
			[_dataSource tableView:self setObjectValue:[cell objectValue]
				  forTableColumn:tableColumn row:row];
		}
		[self setNeedsDisplayInRect:[self rectOfRow:row]];
	}
	info = [NSDictionary dictionaryWithObject:[notification object] forKey:NSFieldEditorUserInfoKey];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidEndEditingNotification
							    object:self userInfo:info];
	[cell release];
}

/* ---- AUTOSAVE ------------------------------------------------------------------------------------ */

- (NSString *)cg_autosaveKey
{
	return [NSString stringWithFormat:@"AgoraTableView %@", _autosaveName];
}

- (void)cg_saveAutosave
{
	NSMutableArray *order;
	NSMutableDictionary *widths;
	NSMutableArray *hidden;
	NSMutableArray *sort;
	NSMutableDictionary *dictionary;
	NSUInteger i;

	if (_autosaveName == nil || [_autosaveName length] == 0 || !_autosaveTableColumns) {
		return;
	}
	order = [NSMutableArray array];
	widths = [NSMutableDictionary dictionary];
	hidden = [NSMutableArray array];
	sort = [NSMutableArray array];
	for (i = 0; i < [_tableColumns count]; i++) {
		NSTableColumn *column = [_tableColumns objectAtIndex:i];
		NSString *identifier = [[column identifier] description];

		[order addObject:identifier];
		[widths setObject:[NSNumber numberWithDouble:(double)[column width]] forKey:identifier];
		if ([column isHidden]) {
			[hidden addObject:identifier];
		}
	}
	for (i = 0; i < [_sortDescriptors count]; i++) {
		NSSortDescriptor *descriptor = [_sortDescriptors objectAtIndex:i];
		NSMutableDictionary *entry = [NSMutableDictionary dictionary];

		if ([descriptor key] != nil) {
			[entry setObject:[descriptor key] forKey:@"key"];
		}
		[entry setObject:[NSNumber numberWithBool:[descriptor ascending]] forKey:@"ascending"];
		[sort addObject:entry];
	}
	dictionary = [NSMutableDictionary dictionary];
	[dictionary setObject:order forKey:@"order"];
	[dictionary setObject:widths forKey:@"widths"];
	[dictionary setObject:hidden forKey:@"hidden"];
	[dictionary setObject:sort forKey:@"sort"];
	[[NSUserDefaults standardUserDefaults] setObject:dictionary forKey:[self cg_autosaveKey]];
}

- (void)cg_loadAutosave
{
	NSDictionary *dictionary;
	NSArray *order;
	NSDictionary *widths;
	NSArray *hidden;
	NSArray *sort;
	NSMutableArray *reordered;
	NSMutableArray *descriptors;
	NSUInteger i;

	if (_autosaveName == nil || [_autosaveName length] == 0 || !_autosaveTableColumns) {
		return;
	}
	dictionary = [[NSUserDefaults standardUserDefaults] dictionaryForKey:[self cg_autosaveKey]];
	if (dictionary == nil) {
		return;
	}
	order = [dictionary objectForKey:@"order"];
	widths = [dictionary objectForKey:@"widths"];
	hidden = [dictionary objectForKey:@"hidden"];
	sort = [dictionary objectForKey:@"sort"];
	reordered = [NSMutableArray array];
	for (i = 0; order != nil && i < [order count]; i++) {
		NSString *identifier = [order objectAtIndex:i];
		NSUInteger j;

		for (j = 0; j < [_tableColumns count]; j++) {
			NSTableColumn *column = [_tableColumns objectAtIndex:j];

			if ([[[column identifier] description] isEqual:identifier]
			    && [reordered indexOfObjectIdenticalTo:column] == NSNotFound) {
				[reordered addObject:column];
				break;
			}
		}
	}
	for (i = 0; i < [_tableColumns count]; i++) {
		NSTableColumn *column = [_tableColumns objectAtIndex:i];

		if ([reordered indexOfObjectIdenticalTo:column] == NSNotFound) {
			[reordered addObject:column];
		}
	}
	[_tableColumns removeAllObjects];
	[_tableColumns addObjectsFromArray:reordered];
	for (i = 0; i < [_tableColumns count]; i++) {
		NSTableColumn *column = [_tableColumns objectAtIndex:i];
		NSString *identifier = [[column identifier] description];
		NSNumber *width = [widths objectForKey:identifier];

		if (width != nil) {
			[column setWidth:(CGFloat)[width doubleValue]];
		}
		[column setHidden:(hidden != nil && [hidden containsObject:identifier])];
	}
	descriptors = [NSMutableArray array];
	for (i = 0; sort != nil && i < [sort count]; i++) {
		NSDictionary *entry = [sort objectAtIndex:i];
		NSString *key = [entry objectForKey:@"key"];
		NSNumber *ascending = [entry objectForKey:@"ascending"];

		if (key != nil) {
			[descriptors addObject:[NSSortDescriptor sortDescriptorWithKey:key
									    ascending:[ascending boolValue]]];
		}
	}
	[_sortDescriptors release];
	_sortDescriptors = [[NSArray alloc] initWithArray:descriptors];
	[self cg_rebuildRowHeights];
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)setAutosaveName:(NSString *)name
{
	NSString *copy = [name copy];

	[_autosaveName release];
	_autosaveName = copy;
	[self cg_loadAutosave];
}

- (NSString *)autosaveName { return _autosaveName; }
- (void)setAutosaveTableColumns:(BOOL)save
{
	_autosaveTableColumns = save ? YES : NO;
	if (_autosaveTableColumns) {
		[self cg_loadAutosave];
	}
}
- (BOOL)autosaveTableColumns { return _autosaveTableColumns; }

/* ---- THE DRAG VOCABULARY ------------------------------------------------------------------------ */

- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes atPoint:(NSPoint)mouseDownPoint
{
	(void)mouseDownPoint;
	if ([rowIndexes count] == 0 || _dataSource == nil) {
		return NO;
	}
	return [_dataSource respondsToSelector:@selector(tableView:writeRowsWithIndexes:toPasteboard:)];
}

- (void)setDraggingSourceOperationMask:(NSDragOperation)mask forLocal:(BOOL)isLocal
{
	if (isLocal) {
		_cgLocalDragMask = mask;
	} else {
		_cgNonLocalDragMask = mask;
	}
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	return isLocal ? _cgLocalDragMask : _cgNonLocalDragMask;
}

- (void)setDropRow:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation
{
	_cgDropRow = row;
	_cgDropOperation = dropOperation;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	(void)anItem;
	return YES;
}

@end
