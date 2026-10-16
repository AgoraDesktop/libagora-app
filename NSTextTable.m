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

@implementation NSTextTable

/* APPLE'S DEFAULT IS ONE COLUMN, which is the honest answer for a table nobody has told the width of. */
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_numberOfColumns = 1;
		_layoutAlgorithm = NSTextTableAutomaticLayoutAlgorithm;
	}
	return self;
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
	NSTextTableBlock *copy = [[NSTextTableBlock alloc] initWithTable:_table startingRow:_startingRow
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
