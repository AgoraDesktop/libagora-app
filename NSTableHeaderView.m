/*
 * NSTableHeaderView — the row of column headers, and the divider gesture.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The header draws through the columns' own header cells, so a column's title and face are the column's rather than a
 * second copy here. It has TWO gestures: a divider drag resizes the column within its min/max, and a drag on the body
 * of a header reorders the column once the pointer crosses the threshold — with the table's delegate allowed to
 * refuse through `-tableView:shouldReorderColumn:toColumn:`. `-draggedColumn`/`-draggedDistance` report the second.
 */
#import "NSTableHeaderView.h"
#import "NSTableHeaderCell.h"
#import "NSTableColumn.h"
#import "NSTableView.h"

#import "NSColor.h"
#import "NSBezierPath.h"
#import "NSEvent.h"
#import <Foundation/NSSortDescriptor.h>
#import "NSWindow.h"

#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>

#include <math.h>

#define AG_HEADER_RESIZE_GRAB 3.0
#define AG_HEADER_REORDER_THRESHOLD 4.0

@interface NSTableView (AGHeaderAutosave)
- (void)cg_saveAutosave;
@end

@implementation NSTableHeaderView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* THE HEADER IS A TOP-DOWN STRIP, like the rows it labels. */
		[self setFlipped:YES];
		_tableView = nil;
		_resizedColumn = -1;
		_pressedColumn = -1;
		_resizing = NO;
		_draggedColumn = -1;
		_draggedDistance = 0.0;
		_dragStartX = 0.0;
		_didDrag = NO;
	}
	return self;
}

- (void)setTableView:(NSTableView *)tableView
{
	_tableView = tableView;	/* NOT RETAINED */
}

- (NSTableView *)tableView
{
	return _tableView;
}

- (NSInteger)draggedColumn
{
	return _draggedColumn;
}

- (CGFloat)draggedDistance
{
	return _draggedDistance;
}

- (NSInteger)resizedColumn
{
	return _resizing ? _resizedColumn : -1;
}

/* THE COLUMN'S BOX IN THIS VIEW'S COORDINATES. The table's column rectangles are in the table's document
 * coordinates; the header is the same horizontal space, so x carries over and the height is the header's own. */
- (NSRect)headerRectOfColumn:(NSInteger)column
{
	NSRect columnRect;

	if (_tableView == nil || column < 0 || column >= [_tableView numberOfColumns]) {
		return NSZeroRect;
	}
	columnRect = [_tableView rectOfColumn:column];
	return NSMakeRect(NSMinX(columnRect), 0.0, NSWidth(columnRect), [self bounds].size.height);
}

- (NSInteger)columnAtPoint:(NSPoint)point
{
	if (_tableView == nil) {
		return -1;
	}
	return [_tableView columnAtPoint:NSMakePoint(point.x, 0.0)];
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)acceptsFirstResponder
{
	return NO;
}

/* ---- THE INK ------------------------------------------------------------------------------------ */

- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger i;
	NSArray *columns;

	if (_tableView == nil) {
		return;
	}
	[[NSColor controlColor] setFill];
	[[NSBezierPath bezierPathWithRect:dirtyRect] fill];
	columns = [_tableView tableColumns];
	for (i = 0; i < (NSInteger)[columns count]; i++) {
		NSTableColumn *column = [columns objectAtIndex:(NSUInteger)i];
		NSCell *cell = [column headerCell];
		NSRect rect = [self headerRectOfColumn:i];
		NSArray *descriptors;
		NSSortDescriptor *descriptor = nil;
		BOOL selected = [_tableView isColumnSelected:i];

		if ([column isHidden] || NSIsEmptyRect(rect) || !NSIntersectsRect(rect, dirtyRect)) {
			continue;
		}
		if (selected) {
			/* A SELECTED COLUMN IS A SELECTION, so it wears the platform's accent like every other one. */
			[[NSColor cg_accentColor] setFill];
			[[NSBezierPath bezierPathWithRect:rect] fill];
		}
		if (cell != nil) {
			[cell drawWithFrame:rect inView:self];
		}
		/* THE SORT MARK IS THE HEADER'S, because only it knows which column the table's first descriptor names. */
		descriptors = [_tableView sortDescriptors];
		if ([descriptors count] > 0) {
			descriptor = [descriptors objectAtIndex:0];
		}
		if (descriptor != nil && [cell isKindOfClass:[NSTableHeaderCell class]]) {
			NSSortDescriptor *prototype = [column sortDescriptorPrototype];
			NSString *key = [prototype key];

			if (key != nil && [[descriptor key] isEqualToString:key]) {
				[(NSTableHeaderCell *)cell drawSortIndicatorWithFrame:rect inView:self
									 ascending:[descriptor ascending] priority:0];
			}
		}
	}
}

/* ---- THE POINTER --------------------------------------------------------------------------------- */

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger column = [self columnAtPoint:point];
	NSRect rect;

	_pressedColumn = column;
	_resizedColumn = -1;
	_resizing = NO;
	_draggedColumn = -1;
	_draggedDistance = 0.0;
	_didDrag = NO;
	if (column < 0 || _tableView == nil) {
		return;
	}
	rect = [self headerRectOfColumn:column];
	/* THE DIVIDER IS THE RIGHT FEW POINTS, and the column's own mask and the table's flag both have to allow it. */
	if ([_tableView allowsColumnResizing] && NSMaxX(rect) - point.x <= AG_HEADER_RESIZE_GRAB &&
	    ([[[_tableView tableColumns] objectAtIndex:(NSUInteger)column] resizingMask] & NSTableColumnUserResizingMask) != 0) {
		_resizedColumn = column;
		_resizing = YES;
		_resizeStartX = point.x;
		_resizeStartWidth = [[[_tableView tableColumns] objectAtIndex:(NSUInteger)column] width];
		[self setNeedsDisplay:YES];
		return;
	}
	/* A PRESS ON THE BODY OF A HEADER IS A REORDER CANDIDATE. The initial `toColumn:-1` is Apple's question: it asks
	 * whether this column may be dragged AT ALL. A delegate that says no still gets the click and the sort below. */
	if ([_tableView allowsColumnReordering]) {
		BOOL allowed = YES;

		if ([[_tableView delegate] respondsToSelector:@selector(tableView:shouldReorderColumn:toColumn:)]) {
			allowed = [[_tableView delegate] tableView:_tableView shouldReorderColumn:column toColumn:-1];
		}
		if (allowed) {
			_draggedColumn = column;
			_dragStartX = point.x;
		}
	}
	if ([_tableView delegate] != nil &&
	    [[_tableView delegate] respondsToSelector:@selector(tableView:mouseDownInHeaderOfTableColumn:)]) {
		[[_tableView delegate] tableView:_tableView mouseDownInHeaderOfTableColumn:
			[[_tableView tableColumns] objectAtIndex:(NSUInteger)column]];
	}
	if ([_tableView allowsColumnSelection]) {
		[_tableView selectColumnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)column]
			      byExtendingSelection:NO];
	}
}

- (void)mouseDragged:(NSEvent *)event
{
	NSPoint point;
	NSArray *columns;
	NSTableColumn *column;
	CGFloat width;

	if (_tableView == nil) {
		return;
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	if (!_resizing && _draggedColumn >= 0) {
		NSInteger target;

		_draggedDistance = point.x - _dragStartX;
		if (fabs((double)_draggedDistance) < AG_HEADER_REORDER_THRESHOLD) {
			return;
		}
		target = [self columnAtPoint:point];
		if (target < 0) {
			target = (point.x < 0.0) ? 0 : [_tableView numberOfColumns] - 1;
		}
		if (target != _draggedColumn && target >= 0 && target < [_tableView numberOfColumns]) {
			BOOL allowed = YES;

			if ([[_tableView delegate] respondsToSelector:
					 @selector(tableView:shouldReorderColumn:toColumn:)]) {
				allowed = [[_tableView delegate] tableView:_tableView
							shouldReorderColumn:_draggedColumn toColumn:target];
			}
			if (allowed) {
				[_tableView moveColumn:_draggedColumn toColumn:target];
				_draggedColumn = target;
				_didDrag = YES;
				[self setNeedsDisplay:YES];
			}
		}
		return;
	}
	if (!_resizing || _resizedColumn < 0) {
		return;
	}
	columns = [_tableView tableColumns];
	if ((NSUInteger)_resizedColumn >= [columns count]) {
		return;
	}
	column = [columns objectAtIndex:(NSUInteger)_resizedColumn];
	width = _resizeStartWidth + (point.x - _resizeStartX);
	[column setWidth:width];
	[_tableView tile];
	[self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
	NSPoint point;
	NSInteger column;

	if (_resizing) {
		NSInteger resized = _resizedColumn;
		CGFloat original = _resizeStartWidth;
		NSTableColumn *column = nil;

		_resizing = NO;
		_resizedColumn = -1;
		[self setNeedsDisplay:YES];
		if (resized >= 0 && (NSUInteger)resized < [[_tableView tableColumns] count]) {
			column = [[_tableView tableColumns] objectAtIndex:(NSUInteger)resized];
		}
		if (column != nil && [column width] != original) {
			NSNotification *note = [NSNotification notificationWithName:NSTableViewColumnDidResizeNotification
									     object:_tableView];

			if ([[_tableView delegate] respondsToSelector:@selector(tableViewColumnDidResize:)]) {
				[[_tableView delegate] tableViewColumnDidResize:note];
			}
			[[NSNotificationCenter defaultCenter] postNotification:note];
			[_tableView cg_saveAutosave];
		}
		return;
	}
	if (_draggedColumn >= 0 && _didDrag) {
		NSTableColumn *dragged = ([_tableView numberOfColumns] > 0
					  && _draggedColumn < [_tableView numberOfColumns])
					 ? [[_tableView tableColumns] objectAtIndex:(NSUInteger)_draggedColumn] : nil;

		if (dragged != nil && [[_tableView delegate] respondsToSelector:@selector(tableView:didDragTableColumn:)]) {
			[[_tableView delegate] tableView:_tableView didDragTableColumn:dragged];
		}
		_draggedColumn = -1;
		_draggedDistance = 0.0;
		_didDrag = NO;
		_pressedColumn = -1;
		[self setNeedsDisplay:YES];
		return;
	}
	_draggedColumn = -1;
	_draggedDistance = 0.0;
	_didDrag = NO;
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	column = [self columnAtPoint:point];
	if (column >= 0 && column == _pressedColumn && _tableView != nil) {
		NSTableColumn *tableColumn = [[_tableView tableColumns] objectAtIndex:(NSUInteger)column];

		if ([[_tableView delegate] respondsToSelector:@selector(tableView:didClickTableColumn:)]) {
			[[_tableView delegate] tableView:_tableView didClickTableColumn:tableColumn];
		}
		/* A SORT PROTOTYPE IS THE COLUMN'S PERMISSION TO SORT, and the header is the click that uses it. */
		if ([tableColumn sortDescriptorPrototype] != nil) {
			NSArray *old = [_tableView sortDescriptors];
			NSSortDescriptor *prototype = [tableColumn sortDescriptorPrototype];
			NSSortDescriptor *current = [old count] > 0 ? [old objectAtIndex:0] : nil;
			BOOL ascending = YES;

			if (current != nil && [[current key] isEqualToString:[prototype key]]) {
				ascending = ![current ascending];
			}
			[_tableView setSortDescriptors:[NSArray arrayWithObject:
				[NSSortDescriptor sortDescriptorWithKey:[prototype key] ascending:ascending]]];
			if ([[_tableView dataSource] respondsToSelector:@selector(tableView:sortDescriptorsDidChange:)]) {
				[[_tableView dataSource] tableView:_tableView sortDescriptorsDidChange:old];
			}
		}
	}
	_pressedColumn = -1;
}

@end
