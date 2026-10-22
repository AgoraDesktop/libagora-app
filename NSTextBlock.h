/*
 * NSTextBlock.h — THE RECTANGLE A RUN OF PARAGRAPHS IS SET IN: PADDING, BORDER, MARGIN AND A GROUND.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A BLOCK IS WHAT MAKES A PARAGRAPH MORE THAN ITS LINES: A BOX AROUND THEM.** Apple's own sentence for the class is
 * "a rectangular area... that is used to lay out a portion of text", and the three things a box can have are the
 * three LAYERS this class measures — PADDING (between the text and the border), BORDER (the edge itself) and MARGIN
 * (outside the border) — each measured per EDGE, so a block can be bounded on one side and open on another. A block
 * also has a BACKGROUND and a BORDER COLOUR, which is what a table cell is: a `NSTextTableBlock` is a block that
 * knows which cell of a grid it is.
 *
 * **AND THE BOX IS DRAWN BY THE BLOCK, NOT BY THE LAYOUT MANAGER.** `-drawBackgroundWithFrame:...` is the door the
 * manager calls once it has computed the frame from the lines the block covers; the block fills its ground and draws
 * its four edges. That is the same division the rules and the attachment cell use: the manager knows WHERE, the
 * object knows WHAT.
 *
 * **WHAT THIS SLICE DOES NOT DO IS RESOLVE A PERCENTAGE AGAINST ANYTHING BUT THE CONTAINING RECT**, and the value
 * type is stored and answered so a caller that sets one is not lied to; the geometry resolves it against the `inRect`
 * it is handed. The GRID — several cells side by side with shared column widths — is `NSTextTable`'s, and its layout
 * is the slice above this one.
 */
#ifndef APPKIT_NSTEXTBLOCK_H
#define APPKIT_NSTEXTBLOCK_H

#import <AppKit/NSView.h>

@class NSColor;
@class NSTextContainer;
@class NSLayoutManager;

NS_ASSUME_NONNULL_BEGIN

/* **THE TWO WAYS A WIDTH CAN BE SPELLED, AND THE THREE LAYERS IT CAN BE FOR.** A width is absolute points or a
 * percentage of the containing rect; the layers run padding, border, margin, in that order from the text outward. */
enum {
	NSTextBlockAbsoluteValueType = 0,
	NSTextBlockPercentageValueType = 1
};
typedef NSUInteger NSTextBlockValueType;

enum {
	NSTextBlockPadding = -1,
	NSTextBlockBorder = 0,
	NSTextBlockMargin = 1
};
typedef NSInteger NSTextBlockLayer;

/* THE FOUR EDGES AS BITS, so a caller can name one or all of them in a mask. Apple's values are the four low bits of a
 * direction word, and the naming is MIN/MAX rather than TOP/BOTTOM because a block is measured in a view's coordinates
 * and a view may be flipped. */
enum {
	NSTextBlockMinXEdge = 1 << 0,
	NSTextBlockMaxXEdge = 1 << 1,
	NSTextBlockMinYEdge = 1 << 2,
	NSTextBlockMaxYEdge = 1 << 3
};
typedef NSUInteger NSTextBlockEdge;

/* **AND THE DIMENSION WORD, WHICH NAMES WHAT A GENERIC VALUE IS ABOUT.** Apple packs two things into one integer: the
 * four CONTENT dimensions (a width, or a height, or the minimum or maximum of either) are small numbers, and the three
 * LAYER dimensions are a bit that is OR-ed WITH AN EDGE — so `NSTextBlockBorder | NSTextBlockMinXEdge` names the left
 * border's width. The layer bits are the era's own values (0x1000, 0x2000, 0x4000), which is what makes the OR safe:
 * they are far above the four edges' low bits and the four content dimensions' small numbers.
 *
 * **THE LAYER CONSTANTS SHARE THEIR NAMES WITH `NSTextBlockLayer` AND THAT IS APPLE'S HEADER, NOT A TYPO** — a layer and
 * its dimension bit are two spellings of one thing, and C puts them in one namespace, so this header declares the
 * DIMENSION ones here and the LAYER ones (as -1, 0 and 1, for the `…forLayer:` doors) above. The two casts in
 * `-setValue:type:forDimension:` are how the object tells them apart: a negative value is a layer, a value with a layer
 * bit is a layer dimension, and anything else is a content dimension. */
enum {
	NSTextBlockWidth = 0,
	NSTextBlockMinimumWidth = 1,
	NSTextBlockMaximumWidth = 2,
	NSTextBlockHeight = 4,
	NSTextBlockMinimumHeight = 5,
	NSTextBlockMaximumHeight = 6,
	NSTextBlockPaddingDimension = 0x1000,
	NSTextBlockBorderDimension = 0x2000,
	NSTextBlockMarginDimension = 0x4000
};
typedef NSInteger NSTextBlockDimension;

/* **HOW A BLOCK'S CONTENT SITS IN ITS ROW**, which is a table's question asked of a block: the vertical alignment of the
 * content inside the cell. Apple's four members, in its order; `Middle` is the default its documentation names for a
 * table cell. */
typedef NSInteger NSTextBlockVerticalAlignment;
enum {
	NSTextBlockTopAlignment = 0,
	NSTextBlockMiddleAlignment = 1,
	NSTextBlockBottomAlignment = 2,
	NSTextBlockBaselineAlignment = 3
};

@interface NSTextBlock : NSObject <NSCoding, NSCopying>
{
	NSColor *_backgroundColor;			/* RETAINED */
	NSMutableDictionary *_borderColors;		/* RETAINED; edge bit -> NSColor */
	/* **AND THE WIDTHS, ONE PER LAYER AND EDGE.** Three layers times four edges; the value type travels beside each
	 * because an absolute 20 and a 20-percent are different widths. */
	CGFloat _widths[3][4];
	NSTextBlockValueType _valueTypes[3][4];
	/* **AND THE SWEEP'S THREE.** `_contentWidth` is the block's own width — the CONTENT dimension Apple keeps beside the
	 * twelve layer widths — with its value type; `_verticalAlignment` is where the content sits in its row. Both are
	 * READ: the content width clamps the rectangle `-boundsRectForContentRect:…` grows, and the alignment is what a
	 * table's cell asks when its content is shorter than the row (see `-valueForDimension:`, which answers it for the
	 * height dimensions it cannot size). */
	CGFloat _contentWidth;
	NSTextBlockValueType _contentWidthType;
	NSTextBlockVerticalAlignment _verticalAlignment;
}

/* THE GROUND THE BLOCK SITS ON, and the colour of each edge. A nil colour means the edge is not drawn. */
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)borderColorForEdge:(NSTextBlockEdge)edge;
- (void)setBorderColor:(nullable NSColor *)color forEdge:(NSTextBlockEdge)edge;

/* AND THE WIDTHS, PER LAYER AND EDGE. The per-layer door sets all four edges at once, which is the common case. */
- (void)setWidth:(CGFloat)width type:(NSTextBlockValueType)type forLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge;

/* **AND THE ARCHIVE DOORS, WHICH 10.6 DECLARES IN `NSTextTable.h`**: `@interface NSTextBlock : NSObject <NSCoding,
 * NSCopying>` — note that the SDK keeps this class in the TABLE's header rather than its own, which is where the
 * declaration was checked. What an archive carries is the ground, the four edge colours, the twelve widths and the
 * twelve value types.
 *
 * **AND A COLOUR IS WRITTEN AS ITS FOUR COMPONENTS**, which is a deviation with a reason rather than a shortcut: this
 * layer's `NSColor` conforms to `NSCopying` and NOT to `NSCoding`, so archiving the OBJECT would produce an archive this
 * tree could not read back. The components are what a colour IS, so a decoded block answers the same colour — and the
 * day `NSColor` archives, this key can carry the object instead and old archives will still decode. */
- (void)encodeWithCoder:(NSCoder *)coder;
- (nullable instancetype)initWithCoder:(NSCoder *)coder;
- (CGFloat)widthForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge;
- (NSTextBlockValueType)valueTypeForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge;
- (void)setWidth:(CGFloat)width type:(NSTextBlockValueType)type forLayer:(NSTextBlockLayer)layer;
- (CGFloat)widthForLayer:(NSTextBlockLayer)layer;

/* ---- AND THE TEN THE SWEEP ADDS: ONE VALUE DOOR, AND NAMES FOR THE PIECES ------------------------- */

/* **ONE DOOR FOR EVERY DIMENSION, WHICH IS APPLE'S ARGUMENT FOR THE DIMENSION WORD.** `-setValue:type:forDimension:` is
 * the generic form of the twelve `-setWidth:type:forLayer:edge:` calls, and `-valueForDimension:` /
 * `-valueTypeForDimension:` read it back; the content dimensions are `-contentWidth:`/`-contentWidthValueType:` under
 * their own names. A dimension this class has no storage for (a HEIGHT, which a block cannot size: its height is its
 * content's) is RECORDED NOWHERE and answered with 0 — see the implementation, where the refusal is stated rather than
 * printed, because zero is a legitimate width and a message per call would be noise. */
- (void)setValue:(CGFloat)value type:(NSTextBlockValueType)type forDimension:(NSTextBlockDimension)dimension;
- (CGFloat)valueForDimension:(NSTextBlockDimension)dimension;
- (NSTextBlockValueType)valueTypeForDimension:(NSTextBlockDimension)dimension;

/* **AND THE CONTENT WIDTH IS READ BY THE GEOMETRY.** `-boundsRectForContentRect:…` clamps the content to this width when
 * one is set — absolute points, or a percentage of the containing rectangle — and grows it by the three layers as
 * before. */
- (CGFloat)contentWidth;
- (NSTextBlockValueType)contentWidthValueType;
- (void)setContentWidth:(CGFloat)width type:(NSTextBlockValueType)type;

/* THE FOUR EDGES AT ONCE, which is the shorthand a caller who wants one border colour writes. */
- (void)setBorderColor:(nullable NSColor *)color;

/* **AND WHERE THE CONTENT SITS IN ITS ROW.** Read by a table cell's layout when its content is shorter than the row; the
 * block itself has no row to align in, which is why this is storage with a READER one class over rather than a stored
 * value nothing reads. */
- (NSTextBlockVerticalAlignment)verticalAlignment;
- (void)setVerticalAlignment:(NSTextBlockVerticalAlignment)alignment;

/* AND THE OLDER SPELLING OF THE VALUE TYPE, which is the same information under Apple's 10.3 name. It answers what
 * `-valueTypeForLayer:edge:` answers, and this header says so rather than keeping a second table. */
- (NSTextBlockValueType)widthValueTypeForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge;

/* **AND THE TWO GEOMETRY DOORS THE LAYOUT ASKS.** `-boundsRectForContentRect:` grows a content rectangle by the three
 * layers on every edge — the box a caller draws; `-rectForLayoutAtPoint:` is the inverse, the content rectangle a
 * block has room for at a point inside a containing rectangle. Both resolve a percentage against the CONTAINING
 * rectangle they are given. */
- (NSRect)boundsRectForContentRect:(NSRect)contentRect inRect:(NSRect)rect
		    textContainer:(nullable NSTextContainer *)textContainer characterRange:(NSRange)charRange;
- (NSRect)rectForLayoutAtPoint:(NSPoint)point inRect:(NSRect)rect
		 textContainer:(nullable NSTextContainer *)textContainer characterRange:(NSRange)charRange;

/* THE GROUND AND THE FOUR EDGES, drawn by the block into the frame the manager computed. */
- (void)drawBackgroundWithFrame:(NSRect)frame inView:(nullable NSView *)view characterRange:(NSRange)charRange
		  layoutManager:(nullable NSLayoutManager *)layoutManager;

/* **AND THE SAME DRAW WITH THE EDGES THE CALLER WANTS**, which is how a table that collapses its borders asks a cell
 * for only the edges the cell does not SHARE with a neighbour — so a shared edge is drawn ONCE rather than by both
 * cells. The GROUND is drawn whole either way, because a background is a rectangle and not an edge. The door above is
 * this one with all four edges, which is what a block outside a collapsing table gets. */
- (void)drawBackgroundWithFrame:(NSRect)frame inView:(nullable NSView *)view characterRange:(NSRange)charRange
		  layoutManager:(nullable NSLayoutManager *)layoutManager edges:(NSTextBlockEdge)edges;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTBLOCK_H */
