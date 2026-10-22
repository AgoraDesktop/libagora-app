/*
 * NSTextTable.m — the grid's few facts, and the cell's place in them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE TWO CLASSES ARE LEDGERS TOO.** `NSTextTable` stores four facts (columns, algorithm, and the two flags) and
 * answers them; `NSTextTableBlock` stores a retained table and four integers, and answers them. The cell's inheritance
 * from `NSTextBlock` is what gives it a ground and edges; the table's is what lets the table carry the grid's own
 * border.
 */
#import <AppKit/NSTextTable.h>
#import "NSTextBlock_internal.h"
#import "NSTextTable_internal.h"
#include <string.h>

@implementation NSTextTable

/* APPLE'S DEFAULT IS ONE COLUMN, which is the honest answer for a table nobody has told the width of. */
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_numberOfColumns = 1;
		_layoutAlgorithm = NSTextTableAutomaticLayoutAlgorithm;
		/* THE MASK A TABLE DRAWS WITH UNLESS THE MANAGER SAYS OTHERWISE: all four edges, which is what a table that does
		 * not collapse its borders means. */
		_drawingEdges = (NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge);
		_columnWidths = NULL;
		_columnCount = 0;
		_tablePadding = 0.0;
	}
	return self;
}

/* **THE HOOK**, whose default paints the block with the mask in force. A subclass overriding it takes over entirely. */
- (void)drawBackgroundForBlock:(NSTextTableBlock *)block withFrame:(NSRect)frameRect inView:(NSView *)controlView
		characterRange:(NSRange)charRange layoutManager:(NSLayoutManager *)layoutManager
{
	[block _drawBackgroundWithFrame:frameRect inView:controlView characterRange:charRange
			 layoutManager:layoutManager edges:_drawingEdges];
}

/* **AND THE MASK-CARRYING VARIANT**, which is what `NSTextTableBlock` forwards to: it carries the mask through the hook
 * so that ONE override point exists whether or not the manager is collapsing. */
- (void)drawBackgroundForBlock:(NSTextTableBlock *)block withFrame:(NSRect)frameRect inView:(NSView *)controlView
		characterRange:(NSRange)charRange layoutManager:(NSLayoutManager *)layoutManager
			 edges:(NSTextBlockEdge)edges
{
	NSTextBlockEdge saved = _drawingEdges;

	_drawingEdges = edges;
	[self drawBackgroundForBlock:block withFrame:frameRect inView:controlView characterRange:charRange
		     layoutManager:layoutManager];
	_drawingEdges = saved;
}

/* **THE BOUNDS DELEGATION**: the default is the BLOCK's own growth, reached through the internal door so a block that
 * forwards here does not recurse. */
- (NSRect)boundsRectForBlock:(NSTextTableBlock *)block contentRect:(NSRect)contentRect inRect:(NSRect)rect
	       textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)charRange
{
	return [block _boundsRectForContentRect:contentRect inRect:rect textContainer:textContainer
		       characterRange:charRange];
}

/* **THE GRID, COPIED IN BY THE MANAGER** — see `NSTextTable_internal.h`. */
- (void)_setColumnWidths:(const CGFloat *)widths count:(NSInteger)count padding:(CGFloat)padding
{
	free(_columnWidths);
	_columnWidths = NULL;
	_columnCount = 0;
	_tablePadding = padding;
	if (widths != NULL && count > 0) {
		_columnWidths = (CGFloat *)malloc((size_t)count * sizeof(CGFloat));
		if (_columnWidths != NULL) {
			memcpy(_columnWidths, widths, (size_t)count * sizeof(CGFloat));
			_columnCount = count;
		}
	}
}

- (BOOL)_hasColumnGeometry
{
	return _columnWidths != NULL && _columnCount > 0;
}

/* **AND THE CELL'S CONTENT RECT** — the arithmetic the manager did inline: from the layout point, past the columns before
 * this one, plus the cell's own left layer; as wide as the columns it spans, less both layers. The height is the caller's
 * business (a cell's text decides it and the row's is the tallest), so the door answers 0 there. */
- (NSRect)rectForBlock:(NSTextTableBlock *)block layoutAtPoint:(NSPoint)startingPoint inRect:(NSRect)rect
	 textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)charRange
{
	NSInteger startingColumn = [block startingColumn];
	NSInteger span = [block columnSpan];
	CGFloat x = startingPoint.x + _tablePadding;
	CGFloat width = 0.0;
	CGFloat left, right;
	NSInteger column;

	(void)rect;
	(void)textContainer;
	(void)charRange;
	if (span < 1) {
		span = 1;
	}
	for (column = 0; column < startingColumn && column < _columnCount; column++) {
		x += _columnWidths[column];
	}
	for (column = startingColumn; column < startingColumn + span && column < _columnCount; column++) {
		width += _columnWidths[column];
	}
	left = [block widthForLayer:NSTextBlockPadding edge:NSTextBlockMinXEdge]
	     + [block widthForLayer:NSTextBlockBorder edge:NSTextBlockMinXEdge]
	     + [block widthForLayer:NSTextBlockMargin edge:NSTextBlockMinXEdge];
	right = [block widthForLayer:NSTextBlockPadding edge:NSTextBlockMaxXEdge]
	      + [block widthForLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge]
	      + [block widthForLayer:NSTextBlockMargin edge:NSTextBlockMaxXEdge];
	x += left;
	width -= left + right;
	if (width < 1.0) {
		width = 1.0;
	}
	return NSMakeRect(x, startingPoint.y, width, 0.0);
}

- (NSTextBlockEdge)_drawingEdges
{
	return _drawingEdges;
}

- (void)dealloc
{
	free(_columnWidths);
	[super dealloc];
}

- (NSUInteger)numberOfColumns
{
	return _numberOfColumns;
}

- (void)setNumberOfColumns:(NSUInteger)columns
{
	_numberOfColumns = (columns > 0) ? columns : 1;
}

- (NSTextTableLayoutAlgorithm)layoutAlgorithm
{
	return _layoutAlgorithm;
}

- (void)setLayoutAlgorithm:(NSTextTableLayoutAlgorithm)algorithm
{
	_layoutAlgorithm = algorithm;
}

- (BOOL)collapsesBorders
{
	return _collapsesBorders;
}

- (void)setCollapsesBorders:(BOOL)flag
{
	_collapsesBorders = flag;
}

- (BOOL)hidesEmptyCells
{
	return _hidesEmptyCells;
}

- (void)setHidesEmptyCells:(BOOL)flag
{
	_hidesEmptyCells = flag;
}

@end

@implementation NSTextTableBlock

- (instancetype)initWithTable:(NSTextTable *)table startingRow:(NSInteger)startingRow rowSpan:(NSInteger)rowSpan
	       startingColumn:(NSInteger)startingColumn columnSpan:(NSInteger)columnSpan
{
	self = [super init];
	if (self != nil) {
		_table = [table retain];
		_startingRow = startingRow;
		_rowSpan = (rowSpan > 0) ? rowSpan : 1;
		_startingColumn = startingColumn;
		_columnSpan = (columnSpan > 0) ? columnSpan : 1;
	}
	return self;
}

- (void)dealloc
{
	[_table release];
	[super dealloc];
}

/* **AND A CELL'S COPY CARRIES ITS PLACE ACROSS, which the base's `-copy` cannot know about.** The block's own ledger
 * is copied by the superclass; the table and the four integers are this class's addition. */
- (id)copy
{
	NSTextTableBlock *copy = [[[self class] alloc] initWithTable:_table startingRow:_startingRow
				  rowSpan:_rowSpan startingColumn:_startingColumn columnSpan:_columnSpan];
	NSInteger layer;

	[copy setBackgroundColor:[self backgroundColor]];
	for (layer = -1; layer <= 1; layer++) {
		NSUInteger i;

		for (i = 0; i < 4; i++) {
			NSTextBlockEdge edge = (NSTextBlockEdge)(1 << i);

			[copy setWidth:[self widthForLayer:(NSTextBlockLayer)layer edge:edge]
				  type:[self valueTypeForLayer:(NSTextBlockLayer)layer edge:edge]
			      forLayer:(NSTextBlockLayer)layer edge:edge];
		}
	}
	[copy setBorderColor:[self borderColorForEdge:NSTextBlockMinXEdge] forEdge:NSTextBlockMinXEdge];
	[copy setBorderColor:[self borderColorForEdge:NSTextBlockMaxXEdge] forEdge:NSTextBlockMaxXEdge];
	[copy setBorderColor:[self borderColorForEdge:NSTextBlockMinYEdge] forEdge:NSTextBlockMinYEdge];
	[copy setBorderColor:[self borderColorForEdge:NSTextBlockMaxYEdge] forEdge:NSTextBlockMaxYEdge];
	return copy;
}

/* **AND THE BLOCK FORWARDS ITS DRAWING TO ITS TABLE** — Apple's arrangement, and the reason the table's doors exist: a
 * caller who subclasses the TABLE changes how its cells are drawn without touching the block. A block with no table
 * (one used outside a table) paints itself. */
- (void)drawBackgroundWithFrame:(NSRect)frame inView:(NSView *)view characterRange:(NSRange)charRange
		  layoutManager:(NSLayoutManager *)layoutManager edges:(NSTextBlockEdge)edges
{
	if (_table != nil) {
		[_table drawBackgroundForBlock:self withFrame:frame inView:view characterRange:charRange
			     layoutManager:layoutManager edges:edges];
		return;
	}
	[self _drawBackgroundWithFrame:frame inView:view characterRange:charRange layoutManager:layoutManager
		edges:edges];
}

- (void)drawBackgroundWithFrame:(NSRect)frame inView:(NSView *)view characterRange:(NSRange)charRange
		  layoutManager:(NSLayoutManager *)layoutManager
{
	[self drawBackgroundWithFrame:frame inView:view characterRange:charRange layoutManager:layoutManager
		edges:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
}

/* **AND THE BLOCK FORWARDS ITS GEOMETRY THE SAME WAY IT FORWARDS ITS DRAWING**: a caller who subclasses the TABLE changes
 * how much room its cells take, without touching the block. A block outside a table grows itself. */
- (NSRect)boundsRectForContentRect:(NSRect)contentRect inRect:(NSRect)rect
		    textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)charRange
{
	if (_table != nil) {
		return [_table boundsRectForBlock:self contentRect:contentRect inRect:rect
			       textContainer:textContainer characterRange:charRange];
	}
	return [self _boundsRectForContentRect:contentRect inRect:rect textContainer:textContainer
		       characterRange:charRange];
}

/* **AND THE BLOCK FORWARDS ITS RECT** when its table has a grid to answer from; a block laid out by a caller that never
 * published one keeps its own geometry, which is what it always had. */
- (NSRect)rectForLayoutAtPoint:(NSPoint)point inRect:(NSRect)rect textContainer:(NSTextContainer *)textContainer
		characterRange:(NSRange)charRange
{
	if (_table != nil && [_table _hasColumnGeometry]) {
		return [_table rectForBlock:self layoutAtPoint:point inRect:rect textContainer:textContainer
			      characterRange:charRange];
	}
	return [super rectForLayoutAtPoint:point inRect:rect textContainer:textContainer characterRange:charRange];
}

- (NSTextTable *)table
{
	return _table;
}

- (NSInteger)startingRow
{
	return _startingRow;
}

- (NSInteger)rowSpan
{
	return _rowSpan;
}

- (NSInteger)startingColumn
{
	return _startingColumn;
}

- (NSInteger)columnSpan
{
	return _columnSpan;
}

@end
