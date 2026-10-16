/*
 * NSTextBlock.h — THE RECTANGLE A RUN OF PARAGRAPHS IS SET IN: PADDING, BORDER, MARGIN AND A GROUND.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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

@interface NSTextBlock : NSObject <NSCopying>
{
	NSColor *_backgroundColor;			/* RETAINED */
	NSMutableDictionary *_borderColors;		/* RETAINED; edge bit -> NSColor */
	/* **AND THE WIDTHS, ONE PER LAYER AND EDGE.** Three layers times four edges; the value type travels beside each
	 * because an absolute 20 and a 20-percent are different widths. */
	CGFloat _widths[3][4];
	NSTextBlockValueType _valueTypes[3][4];
}

/* THE GROUND THE BLOCK SITS ON, and the colour of each edge. A nil colour means the edge is not drawn. */
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)borderColorForEdge:(NSTextBlockEdge)edge;
- (void)setBorderColor:(nullable NSColor *)color forEdge:(NSTextBlockEdge)edge;

/* AND THE WIDTHS, PER LAYER AND EDGE. The per-layer door sets all four edges at once, which is the common case. */
- (void)setWidth:(CGFloat)width type:(NSTextBlockValueType)type forLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge;
- (CGFloat)widthForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge;
- (NSTextBlockValueType)valueTypeForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge;
- (void)setWidth:(CGFloat)width type:(NSTextBlockValueType)type forLayer:(NSTextBlockLayer)layer;
- (CGFloat)widthForLayer:(NSTextBlockLayer)layer;

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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTBLOCK_H */
