/*
 * NSTextTable.m — the grid's few facts, and the cell's place in them.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE TWO CLASSES ARE LEDGERS TOO.** `NSTextTable` stores four facts (columns, algorithm, and the two flags) and
 * answers them; `NSTextTableBlock` stores a retained table and four integers, and answers them. The cell's inheritance
 * from `NSTextBlock` is what gives it a ground and edges; the table's is what lets the table carry the grid's own
 * border.
 */
#import <AppKit/NSTextTable.h>
#import "NSTextBlock_internal.h"
#import "NSTextTable_internal.h"

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

- (NSTextBlockEdge)_drawingEdges
{
	return _drawingEdges;
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
