/*
 * NSTextTable.h — THE GRID A BLOCK BELONGS TO, AND THE BLOCK THAT KNOWS ITS CELL.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * cell, THE VERTICAL LAYERS INCLUDED. **AND A TABLE CAN COLLAPSE ITS BORDERS**: with `-collapsesBorders` YES the
 * manager draws an edge two blocks share ONCE, awarded to the block whose border ON THAT EDGE is WIDER (a tie goes to
 * the min-side one), so a doubled seam becomes one border as heavy as the heavier of the two. THE TABLE'S OWN BORDER
 * IS PART OF THAT: it competes with the outer cells on its four outer edges, and the table's box is the box around the
 * CELLS, so a collapsed table ends up with ONE outer border. AND A TABLE FLOWS ACROSS CONTAINERS AT A ROW BOUNDARY,
 * its columns measured from EVERY cell; a cell of several paragraphs lays out, and its row is the tallest cell's height.
 */
#ifndef APPKIT_NSTEXTTABLE_H
#define APPKIT_NSTEXTTABLE_H

#import <AppKit/NSTextBlock.h>

@class NSTextTableBlock;
@class NSLayoutManager;
@class NSView;

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
	/* **AND THE EDGE MASK BEING DRAWN**, which Apple's signature has no room for and a collapsing table needs: the mask
	 * travels THROUGH `-drawBackgroundForBlock:...` so a subclass overrides one door and still sees what the manager handed
	 * down. All four edges otherwise. */
	NSTextBlockEdge _drawingEdges;
	/* **AND THE COLUMN GEOMETRY THE RECT DOOR NEEDS.** A cell's rect is a function of where its columns begin and how wide
	 * they are, and that arithmetic is measured across EVERY cell — which is the layout manager's pass, not the table's.
	 * So the manager PUBLISHES the widths it measured and this door reads them: one measurement, one place to override. A
	 * column count of 0 means no grid has been published yet. */
	CGFloat *_columnWidths;	/* malloc'd, _columnCount entries */
	NSInteger _columnCount;
	CGFloat _tablePadding;
}

- (NSUInteger)numberOfColumns;
- (void)setNumberOfColumns:(NSUInteger)columns;
- (NSTextTableLayoutAlgorithm)layoutAlgorithm;
- (void)setLayoutAlgorithm:(NSTextTableLayoutAlgorithm)algorithm;
- (BOOL)collapsesBorders;
- (void)setCollapsesBorders:(BOOL)flag;
- (BOOL)hidesEmptyCells;
- (void)setHidesEmptyCells:(BOOL)flag;

/* **THE DOOR A TABLE SUBCLASS OVERRIDES TO DRAW ITS OWN CELLS** — 10.6 declares it on `NSTextTable`, and
 * `NSTextTableBlock` is documented as forwarding to it. The default draws the block: its ground and its edges. */
- (void)drawBackgroundForBlock:(NSTextTableBlock *)block withFrame:(NSRect)frameRect inView:(nullable NSView *)controlView
		characterRange:(NSRange)charRange layoutManager:(nullable NSLayoutManager *)layoutManager;

/* **AND THE SECOND OF THE THREE**: how far outside its text a cell's box reaches, which is the growth by the block's own
 * three layers. The default grows the content rect as the block does; a subclass that returns something else gets that
 * box drawn AND measured, because the manager asks this door for the frame it paints into. */
- (NSRect)boundsRectForBlock:(NSTextTableBlock *)block contentRect:(NSRect)contentRect inRect:(NSRect)rect
	       textContainer:(nullable NSTextContainer *)textContainer characterRange:(NSRange)charRange;

/* **AND THE THIRD: WHERE A CELL'S CONTENT GOES**, given the point the table is being laid out at. The default is the
 * arithmetic the manager used to do inline — the columns before the cell, the columns it spans, its own layers — so a
 * subclass that overrides this one door moves its cells and the manager follows, because the manager ASKS this door for
 * the rect it then places the cell's text in. */
- (NSRect)rectForBlock:(NSTextTableBlock *)block layoutAtPoint:(NSPoint)startingPoint inRect:(NSRect)rect
	 textContainer:(nullable NSTextContainer *)textContainer characterRange:(NSRange)charRange;

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
