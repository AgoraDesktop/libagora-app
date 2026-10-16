/*
 * NSTextTable.h — THE GRID A BLOCK BELONGS TO, AND THE BLOCK THAT KNOWS ITS CELL.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A TABLE IS A BLOCK WITH COLUMNS, AND A CELL IS A BLOCK WITH A PLACE IN THEM.** `NSTextTable` is an `NSTextBlock`
 * — it has a ground and edges like any other box — plus the two things a grid adds: how many columns it has and how
 * they are measured (automatically from the content, or fixed). `NSTextTableBlock` is an `NSTextBlock` that names the
 * cell it draws: a starting row and column and a span in each direction.
 *
 * **AND THE BLOCKS REACH THE LAYOUT THROUGH THE PARAGRAPH STYLE, WHICH IS APPLE'S OWN PLACE FOR THEM.** A paragraph
 * in a table cell carries a `NSTextTableBlock` in its `NSParagraphStyle -textBlocks`; the layout manager reads the
 * style, finds the block, and draws the box around the lines that carry it. So a table is not a second document — it
 * is paragraphs whose boxes interlock, which is the same design the rest of this tier's text uses.
 *
 * **AND THE GRID'S OWN LAYOUT IS THE LAYOUT MANAGER'S.** A table's cells are the paragraphs whose styles carry a
 * `NSTextTableBlock`, and the manager lays them out as a grid: columns are MEASURED — automatically from the widest
 * cell in each column, its span divided out, scaled to fit the container, or equally for a fixed table — and each cell
 * lays its text out inside its own columns' width and is PLACED at its column's x. A row is as tall as its tallest
 * cell. WHAT IS STILL OWED IS NAMED WHERE IT WOULD BE: `-collapsesBorders` (shared edges drawn once) and a table that
 * FLOWS across containers; a cell of several paragraphs lays out, and its row is the tallest cell's height.
 */
#ifndef APPKIT_NSTEXTTABLE_H
#define APPKIT_NSTEXTTABLE_H

#import <AppKit/NSTextBlock.h>

NS_ASSUME_NONNULL_BEGIN

/* HOW THE COLUMNS ARE MEASURED: from the widest cell (the default) or from the table's own width. */
enum {
	NSTextTableAutomaticLayoutAlgorithm = 0,
	NSTextTableFixedLayoutAlgorithm = 1
};
typedef NSInteger NSTextTableLayoutAlgorithm;

@interface NSTextTable : NSTextBlock
{
	NSUInteger _numberOfColumns;
	NSTextTableLayoutAlgorithm _layoutAlgorithm;
	BOOL _collapsesBorders;
	BOOL _hidesEmptyCells;
}

- (NSUInteger)numberOfColumns;
- (void)setNumberOfColumns:(NSUInteger)columns;
- (NSTextTableLayoutAlgorithm)layoutAlgorithm;
- (void)setLayoutAlgorithm:(NSTextTableLayoutAlgorithm)algorithm;
- (BOOL)collapsesBorders;
- (void)setCollapsesBorders:(BOOL)flag;
- (BOOL)hidesEmptyCells;
- (void)setHidesEmptyCells:(BOOL)flag;

@end

@interface NSTextTableBlock : NSTextBlock
{
	NSTextTable *_table;		/* RETAINED */
	NSInteger _startingRow;
	NSInteger _rowSpan;
	NSInteger _startingColumn;
	NSInteger _columnSpan;
}

/* **THE CELL IS MADE WITH ITS PLACE KNOWN AND NOT MOVED AFTERWARDS**, which is why Apple's only initialiser takes the
 * span: a block that changed cells would invalidate the grid it is part of. */
- (instancetype)initWithTable:(NSTextTable *)table startingRow:(NSInteger)startingRow rowSpan:(NSInteger)rowSpan
	       startingColumn:(NSInteger)startingColumn columnSpan:(NSInteger)columnSpan;

- (nullable NSTextTable *)table;
- (NSInteger)startingRow;
- (NSInteger)rowSpan;
- (NSInteger)startingColumn;
- (NSInteger)columnSpan;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTTABLE_H */
