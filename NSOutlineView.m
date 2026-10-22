/*
 * NSOutlineView — the table's tree.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE TREE IS FLATTENED ONCE PER CHANGE, NOT WALKED PER DRAW.** `-reloadData` asks the data source for the roots and
 * then walks every open item depth-first into `_flattenedItems`, with a parallel level array. `-itemAtRow:`,
 * `-rowForItem:` and `-levelForRow:` are then array lookups; a draw never asks the model where anything is. The
 * expanded set is by ITEM IDENTITY, because two equal items in a tree are two rows and an `-isEqual:` set would fold
 * them into one.
 *
 * **THE OUTLINE COLUMN'S CELL IS INSET, THE TRIANGLE IS DRAWN IN THE INSET.** The table draws the cells; this class
 * draws the disclosure and shifts the cell frame in the one column that carries the tree, so the other columns keep
 * their own x. That is the same split `NSTableHeaderView` uses for its divider: the geometry lives where the thing is
 * drawn.
 */
#import "NSOutlineView.h"
#import "NSTableColumn.h"

#import "NSBezierPath.h"
#import "NSColor.h"
#import "NSEvent.h"
#import "NSFont.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

NSString *NSOutlineViewItemKey = @"item";
NSString *NSOutlineViewItemWillExpandNotification = @"NSOutlineViewItemWillExpandNotification";
NSString *NSOutlineViewSelectionDidChangeNotification = @"NSOutlineViewSelectionDidChangeNotification";
NSString *NSOutlineViewSelectionIsChangingNotification = @"NSOutlineViewSelectionIsChangingNotification";
NSString *NSOutlineViewItemDidExpandNotification = @"NSOutlineViewItemDidExpandNotification";
NSString *NSOutlineViewItemWillCollapseNotification = @"NSOutlineViewItemWillCollapseNotification";
NSString *NSOutlineViewItemDidCollapseNotification = @"NSOutlineViewItemDidCollapseNotification";

#define AG_OUTLINE_INDENTATION 16.0
#define AG_OUTLINE_TRIANGLE 9.0
#define AG_OUTLINE_TRIANGLE_INSET 2.0
#define AG_OUTLINE_CELL_INSET 15.0

@interface NSOutlineView ()
- (void)fn_rebuildRoots;
- (void)fn_flatten;
- (void)fn_flattenItem:(id)item level:(NSInteger)level;
- (BOOL)fn_isExpanded:(id)item;
- (NSUInteger)fn_expandedIndex:(id)item;
- (void)fn_removeExpandedItem:(id)item children:(BOOL)children;
- (void)fn_expandItem:(id)item children:(BOOL)children;
- (void)fn_collapseItem:(id)item children:(BOOL)children;
- (void)fn_post:(NSString *)name item:(id)item;
- (NSInteger)fn_outlineColumnIndex;
- (void)fn_selectionDidChangeFrom:(NSIndexSet *)before;
- (id)fn_parentOfItem:(id)wanted inItem:(id)parent source:(id)source depth:(NSInteger)depth;
@end

@implementation NSOutlineView

/* ============================================================================================
 * ARCHIVING: THE INDENTATION AND THE OUTLINE COLUMN, NOT THE TREE.
 * ============================================================================================ */
/* **THE FIVE ARRAYS ARE A TREE THIS VIEW BUILT FROM A DATA SOURCE** — the roots, the flattened rows, their levels and
 * what is expanded — and none of them survives a decode with any meaning, because the source is a connection and the
 * tree is its answer. The outline column and the four indentation flags are the design. */
static NSString * const AGCoderOutlineColumnKey = @"outlineTableColumn";
static NSString * const AGCoderOutlineIndentationKey = @"indentationPerLevel";
static NSString * const AGCoderOutlineMarkerKey = @"indentationMarkerFollowsCell";
static NSString * const AGCoderOutlineAutoresizeKey = @"autoresizesOutlineColumn";
static NSString * const AGCoderOutlineAutosaveKey = @"autosaveExpandedItems";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_outlineTableColumn forKey:AGCoderOutlineColumnKey];
	[aCoder encodeDouble:(double)_indentationPerLevel forKey:AGCoderOutlineIndentationKey];
	[aCoder encodeBool:_indentationMarkerFollowsCell forKey:AGCoderOutlineMarkerKey];
	[aCoder encodeBool:_autoresizesOutlineColumn forKey:AGCoderOutlineAutoresizeKey];
	[aCoder encodeBool:_autosaveExpandedItems forKey:AGCoderOutlineAutosaveKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderOutlineIndentationKey]) {
		_indentationPerLevel = [aDecoder decodeDoubleForKey:AGCoderOutlineIndentationKey];
	}
	if ([aDecoder containsValueForKey:AGCoderOutlineMarkerKey]) {
		_indentationMarkerFollowsCell = [aDecoder decodeBoolForKey:AGCoderOutlineMarkerKey];
	}
	if ([aDecoder containsValueForKey:AGCoderOutlineAutoresizeKey]) {
		_autoresizesOutlineColumn = [aDecoder decodeBoolForKey:AGCoderOutlineAutoresizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderOutlineAutosaveKey]) {
		_autosaveExpandedItems = [aDecoder decodeBoolForKey:AGCoderOutlineAutosaveKey];
	}
	if ([aDecoder containsValueForKey:AGCoderOutlineColumnKey]) {
		id column = [aDecoder decodeObjectForKey:AGCoderOutlineColumnKey];

		if ([column isKindOfClass:[NSTableColumn class]]) {
			[self setOutlineTableColumn:column];
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
		_rootItems = [[NSMutableArray alloc] init];
		_flattenedItems = [[NSMutableArray alloc] init];
		_flattenedLevels = [[NSMutableArray alloc] init];
		_expandedItems = [[NSMutableArray alloc] init];
		_outlineTableColumn = nil;
		_indentationPerLevel = AG_OUTLINE_INDENTATION;
		_indentationMarkerFollowsCell = YES;
		_autoresizesOutlineColumn = YES;
		_autosaveExpandedItems = NO;
	}
	return self;
}

- (void)dealloc
{
	[_rootItems release];
	[_flattenedItems release];
	[_flattenedLevels release];
	[_expandedItems release];
	[super dealloc];
}

/* ---- THE DATA SOURCE AND THE DELEGATE ---------------------------------------------------------- */

- (void)setDataSource:(id <NSOutlineViewDataSource>)aSource
{
	[super setDataSource:(id)aSource];
}

- (id <NSOutlineViewDataSource>)dataSource
{
	return (id <NSOutlineViewDataSource>)[super dataSource];
}

- (void)setDelegate:(id <NSOutlineViewDelegate>)delegate
{
	[super setDelegate:(id)delegate];
}

- (id <NSOutlineViewDelegate>)delegate
{
	return (id <NSOutlineViewDelegate>)[super delegate];
}

/* ---- THE OUTLINE COLUMN ------------------------------------------------------------------------- */

- (void)setOutlineTableColumn:(NSTableColumn *)outlineTableColumn
{
	_outlineTableColumn = outlineTableColumn;	/* NOT RETAINED: the table owns the column */
	[self setNeedsDisplay:YES];
}

- (NSTableColumn *)outlineTableColumn
{
	return _outlineTableColumn;
}

- (NSInteger)fn_outlineColumnIndex
{
	if (_outlineTableColumn == nil) {
		return -1;
	}
	return (NSInteger)[_tableColumns indexOfObjectIdenticalTo:_outlineTableColumn];
}

/* ---- THE FLATTENED TREE ------------------------------------------------------------------------- */

- (void)fn_rebuildRoots
{
	NSInteger count;
	NSInteger i;
	id source = [self dataSource];

	[_rootItems removeAllObjects];
	if (source == nil || ![source respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)]) {
		return;
	}
	count = [source outlineView:self numberOfChildrenOfItem:nil];
	if (count <= 0) {
		return;
	}
	for (i = 0; i < count; i++) {
		id item = [source outlineView:self child:i ofItem:nil];

		if (item != nil) {
			[_rootItems addObject:item];
		}
	}
}

- (void)fn_flatten
{
	NSUInteger i;

	[_flattenedItems removeAllObjects];
	[_flattenedLevels removeAllObjects];
	for (i = 0; i < [_rootItems count]; i++) {
		[self fn_flattenItem:[_rootItems objectAtIndex:i] level:0];
	}
}

- (void)fn_flattenItem:(id)item level:(NSInteger)level
{
	NSInteger count;
	NSInteger i;
	id source = [self dataSource];

	if (item == nil) {
		return;
	}
	[_flattenedItems addObject:item];
	[_flattenedLevels addObject:[NSNumber numberWithInteger:level]];
	if (![self fn_isExpanded:item] || source == nil ||
	    ![source respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)]) {
		return;
	}
	count = [source outlineView:self numberOfChildrenOfItem:item];
	for (i = 0; i < count; i++) {
		id child = [source outlineView:self child:i ofItem:item];

		if (child != nil) {
			[self fn_flattenItem:child level:level + 1];
		}
	}
}

- (void)fn_post:(NSString *)name item:(id)item
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:(item != nil ? item : (id)[NSNull null])
							 forKey:NSOutlineViewItemKey];
	NSNotification *note = [NSNotification notificationWithName:name object:self userInfo:info];

	[[NSNotificationCenter defaultCenter] postNotification:note];
}

- (BOOL)fn_isExpanded:(id)item
{
	return item != nil && [_expandedItems indexOfObjectIdenticalTo:item] != NSNotFound;
}

- (NSUInteger)fn_expandedIndex:(id)item
{
	return (item != nil) ? [_expandedItems indexOfObjectIdenticalTo:item] : NSNotFound;
}

- (void)fn_removeExpandedItem:(id)item children:(BOOL)children
{
	NSUInteger index = [self fn_expandedIndex:item];
	id source = [self dataSource];

	if (index == NSNotFound) {
		return;
	}
	if (children && source != nil &&
	    [source respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)]) {
		NSInteger count = [source outlineView:self numberOfChildrenOfItem:item];
		NSInteger i;

		for (i = 0; i < count; i++) {
			id child = [source outlineView:self child:i ofItem:item];

			if (child != nil) {
				[self fn_removeExpandedItem:child children:YES];
			}
		}
	}
	index = [self fn_expandedIndex:item];
	if (index != NSNotFound) {
		[_expandedItems removeObjectAtIndex:index];
	}
}

- (void)fn_expandItem:(id)item children:(BOOL)children
{
	id source = [self dataSource];

	if (item == nil || [self fn_isExpanded:item] ||
	    ![self isExpandable:item]) {
		return;
	}
	if ([self delegate] != nil &&
	    [[self delegate] respondsToSelector:@selector(outlineView:shouldExpandItem:)] &&
	    ![[self delegate] outlineView:self shouldExpandItem:item]) {
		return;
	}
	[self fn_post:NSOutlineViewItemWillExpandNotification item:item];
	[_expandedItems addObject:item];
	if (children && source != nil &&
	    [source respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)]) {
		NSInteger count = [source outlineView:self numberOfChildrenOfItem:item];
		NSInteger i;

		for (i = 0; i < count; i++) {
			id child = [source outlineView:self child:i ofItem:item];

			if (child != nil) {
				[self fn_expandItem:child children:YES];
			}
		}
	}
	[self fn_post:NSOutlineViewItemDidExpandNotification item:item];
}

- (void)fn_collapseItem:(id)item children:(BOOL)children
{
	if (item == nil || ![self fn_isExpanded:item]) {
		return;
	}
	if ([self delegate] != nil &&
	    [[self delegate] respondsToSelector:@selector(outlineView:shouldCollapseItem:)] &&
	    ![[self delegate] outlineView:self shouldCollapseItem:item]) {
		return;
	}
	[self fn_post:NSOutlineViewItemWillCollapseNotification item:item];
	[self fn_removeExpandedItem:item children:children];
	[self fn_post:NSOutlineViewItemDidCollapseNotification item:item];
}

/* ---- RELOAD AND THE PUBLIC TREE DOORS ------------------------------------------------------------ */

- (void)reloadData
{
	[self fn_rebuildRoots];
	[self fn_flatten];
	_numberOfRows = (NSInteger)[_flattenedItems count];
	if ([_selectedRowIndexes count] > 0 && [_selectedRowIndexes lastIndex] >= (NSUInteger)_numberOfRows) {
		[self deselectAll:nil];
	}
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)noteNumberOfRowsChanged
{
	[self reloadData];
}

- (void)reloadItem:(id)item reloadChildren:(BOOL)reloadChildren
{
	(void)reloadChildren;
	if (item == nil) {
		[self fn_rebuildRoots];
	}
	[self fn_flatten];
	_numberOfRows = (NSInteger)[_flattenedItems count];
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)reloadItem:(id)item
{
	[self reloadItem:item reloadChildren:NO];
}

- (BOOL)isExpandable:(id)item
{
	id source = [self dataSource];

	if (source == nil || ![source respondsToSelector:@selector(outlineView:isItemExpandable:)]) {
		return NO;
	}
	return [source outlineView:self isItemExpandable:item];
}

- (void)expandItem:(id)item expandChildren:(BOOL)expandChildren
{
	[self fn_expandItem:item children:expandChildren];
	[self fn_flatten];
	_numberOfRows = (NSInteger)[_flattenedItems count];
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)expandItem:(id)item
{
	[self expandItem:item expandChildren:NO];
}

- (void)collapseItem:(id)item collapseChildren:(BOOL)collapseChildren
{
	[self fn_collapseItem:item children:collapseChildren];
	[self fn_flatten];
	_numberOfRows = (NSInteger)[_flattenedItems count];
	[self tile];
	[self setNeedsDisplay:YES];
}

- (void)collapseItem:(id)item
{
	[self collapseItem:item collapseChildren:NO];
}

- (id)itemAtRow:(NSInteger)row
{
	if (row < 0 || (NSUInteger)row >= [_flattenedItems count]) {
		return nil;
	}
	return [_flattenedItems objectAtIndex:(NSUInteger)row];
}

- (NSInteger)rowForItem:(id)item
{
	NSUInteger index;

	if (item == nil) {
		return -1;
	}
	index = [_flattenedItems indexOfObjectIdenticalTo:item];
	return (index == NSNotFound) ? -1 : (NSInteger)index;
}

- (id)parentForItem:(id)item
{
	id source = [self dataSource];
	NSUInteger i;

	if (item == nil || source == nil) {
		return nil;
	}
	for (i = 0; i < [_rootItems count]; i++) {
		id root = [_rootItems objectAtIndex:i];
		id found;

		if (root == item) {
			return nil;
		}
		found = [self fn_parentOfItem:item inItem:root source:source depth:0];
		if (found != nil) {
			return found;
		}
	}
	return nil;
}

/* THE SEARCH IS DEPTH-FIRST AND IDENTITY-BASED; the depth cap is a guard against a data source that returns a cycle,
 * not a model limit. */
- (id)fn_parentOfItem:(id)wanted inItem:(id)parent source:(id)source depth:(NSInteger)depth
{
	NSInteger count;
	NSInteger i;

	if (depth > 1024 || parent == nil ||
	    ![source respondsToSelector:@selector(outlineView:numberOfChildrenOfItem:)]) {
		return nil;
	}
	count = [source outlineView:self numberOfChildrenOfItem:parent];
	for (i = 0; i < count; i++) {
		id child = [source outlineView:self child:i ofItem:parent];

		if (child == wanted) {
			return parent;
		}
		if (child != nil) {
			id found = [self fn_parentOfItem:wanted inItem:child source:source depth:depth + 1];

			if (found != nil) {
				return found;
			}
		}
	}
	return nil;
}

- (NSInteger)levelForRow:(NSInteger)row
{
	if (row < 0 || (NSUInteger)row >= [_flattenedLevels count]) {
		return -1;
	}
	return [[_flattenedLevels objectAtIndex:(NSUInteger)row] integerValue];
}

- (NSInteger)levelForItem:(id)item
{
	NSInteger row = [self rowForItem:item];
	NSInteger level = 0;
	id parent;

	if (row >= 0) {
		return [self levelForRow:row];
	}
	if (item == nil) {
		return -1;
	}
	parent = [self parentForItem:item];
	while (parent != nil && level < 1024) {
		level++;
		parent = [self parentForItem:parent];
	}
	return level;
}

- (BOOL)isItemExpanded:(id)item
{
	return [self fn_isExpanded:item];
}

/* ---- THE INDENTATION AND THE DISCLOSURE ---------------------------------------------------------- */

- (void)setIndentationPerLevel:(CGFloat)indentationPerLevel
{
	_indentationPerLevel = (indentationPerLevel > 0.0) ? indentationPerLevel : 1.0;
	[self setNeedsDisplay:YES];
}

- (CGFloat)indentationPerLevel
{
	return _indentationPerLevel;
}

- (void)setIndentationMarkerFollowsCell:(BOOL)drawInCell
{
	_indentationMarkerFollowsCell = drawInCell ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)indentationMarkerFollowsCell
{
	return _indentationMarkerFollowsCell;
}

- (void)setAutoresizesOutlineColumn:(BOOL)resize
{
	_autoresizesOutlineColumn = resize ? YES : NO;
}

- (BOOL)autoresizesOutlineColumn
{
	return _autoresizesOutlineColumn;
}

- (BOOL)autosaveExpandedItems
{
	return _autosaveExpandedItems;
}

- (void)setAutosaveExpandedItems:(BOOL)save
{
	_autosaveExpandedItems = save ? YES : NO;
}

- (NSRect)frameOfOutlineCellAtRow:(NSInteger)row
{
	NSInteger column = [self fn_outlineColumnIndex];
	NSRect columnRect;
	NSRect rowRect;
	NSInteger level;

	if (column < 0 || row < 0 || row >= [self numberOfRows]) {
		return NSZeroRect;
	}
	columnRect = [self rectOfColumn:column];
	rowRect = [self rectOfRow:row];
	if (NSIsEmptyRect(columnRect) || NSIsEmptyRect(rowRect)) {
		return NSZeroRect;
	}
	level = [self levelForRow:row];
	if (!_indentationMarkerFollowsCell) {
		level = 0;
	}
	return NSMakeRect(NSMinX(columnRect) + (CGFloat)level * _indentationPerLevel + AG_OUTLINE_TRIANGLE_INSET,
			  NSMinY(rowRect) + ([self rowHeight] - AG_OUTLINE_TRIANGLE) / 2.0,
			  AG_OUTLINE_TRIANGLE, AG_OUTLINE_TRIANGLE);
}

/* ---- THE CELL AND THE ROW ---------------------------------------------------------------------- */

- (NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
	NSRect rect = [super frameOfCellAtColumn:column row:row];

	if (column == [self fn_outlineColumnIndex] && !NSIsEmptyRect(rect)) {
		NSInteger level = [self levelForRow:row];
		CGFloat inset = (CGFloat)level * _indentationPerLevel + AG_OUTLINE_CELL_INSET;

		rect.origin.x += inset;
		rect.size.width -= inset;
		if (rect.size.width < 0.0) {
			rect.size.width = 0.0;
		}
	}
	return rect;
}

- (NSCell *)preparedCellAtColumn:(NSInteger)column row:(NSInteger)row
{
	NSTableColumn *tableColumn;
	NSCell *cell = nil;
	id item;
	id value = nil;

	if (column < 0 || (NSUInteger)column >= [_tableColumns count] || row < 0 || row >= _numberOfRows) {
		return nil;
	}
	tableColumn = [_tableColumns objectAtIndex:(NSUInteger)column];
	if ([tableColumn isHidden]) {
		return nil;
	}
	item = [self itemAtRow:row];
	if ([self delegate] != nil &&
	    [[self delegate] respondsToSelector:@selector(outlineView:dataCellForTableColumn:item:)]) {
		cell = [[self delegate] outlineView:self dataCellForTableColumn:tableColumn item:item];
	}
	if (cell == nil) {
		cell = [tableColumn dataCellForRow:row];
	}
	if ([self dataSource] != nil &&
	    [[self dataSource] respondsToSelector:@selector(outlineView:objectValueForTableColumn:byItem:)]) {
		value = [[self dataSource] outlineView:self objectValueForTableColumn:tableColumn byItem:item];
	}
	[cell setObjectValue:value];
	if ([self delegate] != nil &&
	    [[self delegate] respondsToSelector:@selector(outlineView:willDisplayCell:forTableColumn:item:)]) {
		[[self delegate] outlineView:self willDisplayCell:cell forTableColumn:tableColumn item:item];
	}
	return cell;
}

- (void)drawRow:(NSInteger)row clipRect:(NSRect)clipRect
{
	NSInteger outlineColumn = [self fn_outlineColumnIndex];
	id item = [self itemAtRow:row];
	NSRect triangle;
	NSBezierPath *path;
	BOOL expanded;

	if (outlineColumn >= 0 && item != nil && [self isExpandable:item]) {
		triangle = [self frameOfOutlineCellAtRow:row];
		if (NSIntersectsRect(triangle, clipRect)) {
			expanded = [self isItemExpanded:item];
			path = [NSBezierPath bezierPath];
			if (expanded) {
				[path moveToPoint:NSMakePoint(NSMinX(triangle), NSMinY(triangle))];
				[path lineToPoint:NSMakePoint(NSMaxX(triangle), NSMinY(triangle))];
				[path lineToPoint:NSMakePoint(NSMidX(triangle), NSMaxY(triangle))];
			} else {
				[path moveToPoint:NSMakePoint(NSMinX(triangle), NSMinY(triangle))];
				[path lineToPoint:NSMakePoint(NSMinX(triangle), NSMaxY(triangle))];
				[path lineToPoint:NSMakePoint(NSMaxX(triangle), NSMidY(triangle))];
			}
			[path closePath];
			[[self isRowSelected:row] ? [NSColor selectedControlTextColor] : [NSColor controlTextColor] setFill];
			[path fill];
		}
	}
	[super drawRow:row clipRect:clipRect];
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger row = [self rowAtPoint:point];
	NSInteger column = [self columnAtPoint:point];
	NSInteger outlineColumn = [self fn_outlineColumnIndex];

	if (row >= 0 && column == outlineColumn) {
		id item = [self itemAtRow:row];

		if (item != nil && [self isExpandable:item]) {
			NSRect triangle = [self frameOfOutlineCellAtRow:row];

			if (NSPointInRect(point, NSInsetRect(triangle, -2.0, -2.0))) {
				if ([self isItemExpanded:item]) {
					[self collapseItem:item];
				} else {
					[self expandItem:item];
				}
				return;
			}
		}
	}
	[super mouseDown:event];
}

/* ---- SELECTION IN ITEM TERMS -------------------------------------------------------------------- */

- (void)fn_selectionDidChangeFrom:(NSIndexSet *)before
{
	NSIndexSet *after = [self selectedRowIndexes];

	if ([before isEqualToIndexSet:after]) {
		return;
	}
	{
		NSNotification *note = [NSNotification notificationWithName:NSOutlineViewSelectionDidChangeNotification
								     object:self];

		if ([self delegate] != nil &&
		    [[self delegate] respondsToSelector:@selector(outlineViewSelectionDidChange:)]) {
			[[self delegate] outlineViewSelectionDidChange:note];
		}
		[[NSNotificationCenter defaultCenter] postNotification:note];
	}
}

- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
	NSMutableIndexSet *allowed = [[NSMutableIndexSet alloc] init];
	NSIndexSet *before = [self selectedRowIndexes];
	NSUInteger row = [indexes firstIndex];

	if ([self delegate] != nil &&
	    [[self delegate] respondsToSelector:@selector(selectionShouldChangeInOutlineView:)] &&
	    ![[self delegate] selectionShouldChangeInOutlineView:self]) {
		return;
	}
	while (row != NSNotFound) {
		id item = [self itemAtRow:(NSInteger)row];

		if ([self delegate] == nil ||
		    ![[self delegate] respondsToSelector:@selector(outlineView:shouldSelectItem:)] ||
		    [[self delegate] outlineView:self shouldSelectItem:item]) {
			[allowed addIndex:row];
		}
		row = [indexes indexGreaterThanIndex:row];
	}
	[super selectRowIndexes:allowed byExtendingSelection:extend];
	[allowed release];
	[self fn_selectionDidChangeFrom:before];
}

- (void)deselectAll:(id)sender
{
	NSIndexSet *before = [self selectedRowIndexes];

	[super deselectAll:sender];
	[self fn_selectionDidChangeFrom:before];
}

- (void)selectAll:(id)sender
{
	NSIndexSet *before = [self selectedRowIndexes];

	[super selectAll:sender];
	[self fn_selectionDidChangeFrom:before];
}

/* THE DROP RECORD. See the header: the item is borrowed and -1 in the index means "on the item". */
- (void)setDropItem:(id)item dropChildIndex:(NSInteger)index
{
	_dropItem = item;
	_dropChildIndex = index;
	[self setNeedsDisplay:YES];
}

- (BOOL)shouldCollapseAutoExpandedItemsForDeposited:(BOOL)deposited
{
	(void)deposited;
	return YES;
}

@end
