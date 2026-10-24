/*
 * NSTextBlock.m — the box: three layers of widths, a ground, and four edges.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CLASS IS A LEDGER AND TWO ARITHMETICS.** Every door above stores or answers one of: a background colour, four
 * border colours, or three layers of four widths with a value type each. The two arithmetics are the geometry pair —
 * growing a content rectangle by the layers, and shrinking a containing rectangle back to a content one — and one of
 * them (`-boundsRectForContentRect:`) is what the layout manager calls to learn how far outside the text the box
 * reaches. Everything else is a setter or a getter.
 */
#import <AppKit/NSTextBlock.h>
#import "NSTextBlock_internal.h"
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

/* THE FOUR SINGLE-BIT EDGES, in the order the arrays store them. */
static const NSTextBlockEdge fn_edges[4] = {
	NSTextBlockMinXEdge, NSTextBlockMaxXEdge, NSTextBlockMinYEdge, NSTextBlockMaxYEdge
};

/* A LAYER'S ROW IN THE ARRAYS, because `NSTextBlockLayer` runs -1..1 and an index cannot. */
static NSInteger fn_layerRow(NSTextBlockLayer layer)
{
	return layer + 1;
}

/* THE BIT'S COLUMN, or -1 when the caller named a MASK rather than an edge. */
static NSInteger fn_edgeColumn(NSTextBlockEdge edge)
{
	NSUInteger i;

	for (i = 0; i < 4; i++) {
		if (edge == fn_edges[i]) {
			return (NSInteger)i;
		}
	}
	return -1;
}

/* **A COLOUR AS FOUR NUMBERS**, since `NSColor` has no archive of its own — see the header. NSNull stands for "no
 * colour", which is how an edge that is not drawn survives the trip. */
static NSArray *fn_colour_components(NSColor *colour)
{
	if (colour == nil) {
		return nil;
	}
	return [NSArray arrayWithObjects:[NSNumber numberWithDouble:[colour redComponent]],
					 [NSNumber numberWithDouble:[colour greenComponent]],
					 [NSNumber numberWithDouble:[colour blueComponent]],
					 [NSNumber numberWithDouble:[colour alphaComponent]], nil];
}

static NSColor *fn_colour_from_components(id stored)
{
	NSArray *parts = ([stored isKindOfClass:[NSArray class]]) ? stored : nil;

	if (parts == nil || [parts count] != 4) {
		return nil;
	}
	return [NSColor colorWithCalibratedRed:(CGFloat)[[parts objectAtIndex:0] doubleValue]
					green:(CGFloat)[[parts objectAtIndex:1] doubleValue]
					 blue:(CGFloat)[[parts objectAtIndex:2] doubleValue]
					alpha:(CGFloat)[[parts objectAtIndex:3] doubleValue]];
}

@implementation NSTextBlock

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_borderColors = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_backgroundColor release];
	[_borderColors release];
	[super dealloc];
}

/* **AN IMMUTABLE COPY OF THE LEDGER**, which is what a value in a store wants: a paragraph style that carries a block
 * must not see it change under it. */
- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	NSTextBlock *copy = [[[self class] allocWithZone:zone] init];
	NSUInteger i, j;

	copy->_backgroundColor = [_backgroundColor retain];
	[copy->_borderColors release];
	copy->_borderColors = [_borderColors mutableCopy];
	for (i = 0; i < 3; i++) {
		for (j = 0; j < 4; j++) {
			copy->_widths[i][j] = _widths[i][j];
			copy->_valueTypes[i][j] = _valueTypes[i][j];
		}
	}
	/* AND THE SWEEP'S THREE TRAVEL WITH THE TWELVE — a copy that lost them would be a cell with a different shape. */
	copy->_contentWidth = _contentWidth;
	copy->_contentWidthType = _contentWidthType;
	copy->_verticalAlignment = _verticalAlignment;
	return copy;
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)color
{
	if (color != _backgroundColor) {
		id held = [color retain];

		[_backgroundColor release];
		_backgroundColor = held;
	}
}

- (NSColor *)borderColorForEdge:(NSTextBlockEdge)edge
{
	NSInteger column = fn_edgeColumn(edge);

	return (column >= 0) ? [_borderColors objectForKey:[NSNumber numberWithInteger:fn_edges[column]]] : nil;
}

/* A MASK SETS EVERY EDGE IN IT, which is how `NSTextBlockMinXEdge | NSTextBlockMaxXEdge` means "both sides". */
- (void)setBorderColor:(NSColor *)color forEdge:(NSTextBlockEdge)edge
{
	NSUInteger i;

	for (i = 0; i < 4; i++) {
		if ((edge & fn_edges[i]) != 0) {
			NSNumber *key = [NSNumber numberWithInteger:fn_edges[i]];

			if (color != nil) {
				[_borderColors setObject:color forKey:key];
			} else {
				[_borderColors removeObjectForKey:key];
			}
		}
	}
}

- (void)setWidth:(CGFloat)width type:(NSTextBlockValueType)type forLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge
{
	NSInteger row = fn_layerRow(layer);
	NSUInteger i;

	if (row < 0 || row > 2) {
		return;
	}
	for (i = 0; i < 4; i++) {
		if ((edge & fn_edges[i]) != 0) {
			_widths[row][i] = width;
			_valueTypes[row][i] = type;
		}
	}
}

- (CGFloat)widthForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge
{
	NSInteger row = fn_layerRow(layer);
	NSInteger column = fn_edgeColumn(edge);

	if (row < 0 || row > 2 || column < 0) {
		return 0.0;
	}
	return _widths[row][column];
}

/* **THE ARCHIVE DOORS.** The keys are this tier's own, named after what they carry. The arrays are FLAT and positional:
 * twelve widths and twelve value types, layer-major, so a decoded block cannot disagree with itself about which width
 * belongs to which edge — the layout is the loop's, in one place, rather than a key per cell. */
- (void)encodeWithCoder:(NSCoder *)coder
{
	NSMutableArray *widths = [NSMutableArray array];
	NSMutableArray *types = [NSMutableArray array];
	NSMutableArray *edges = [NSMutableArray array];
	int layer, edge;

	[coder encodeObject:fn_colour_components(_backgroundColor) forKey:@"NSBackgroundColor"];
	for (edge = 0; edge < 4; edge++) {
		NSArray *components = fn_colour_components([self borderColorForEdge:(NSTextBlockEdge)(1u << edge)]);

		[edges addObject:(components != nil) ? (id)components : (id)[NSNull null]];
	}
	[coder encodeObject:edges forKey:@"NSBorderColors"];
	for (layer = 0; layer < 3; layer++) {
		for (edge = 0; edge < 4; edge++) {
			[widths addObject:[NSNumber numberWithDouble:(double)_widths[layer][edge]]];
			[types addObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)_valueTypes[layer][edge]]];
		}
	}
	[coder encodeObject:widths forKey:@"NSWidths"];
	[coder encodeObject:types forKey:@"NSValueTypes"];
	/* **AND THE SWEEP'S THREE, UNDER THEIR OWN KEYS.** They are the block's own dimensions rather than one of the twelve
	 * layer slots, so they travel beside them: a content width with its type, and the vertical alignment. An archive from
	 * before this slice simply has no keys, and the defaults (no width, Top alignment) are what a fresh block answers. */
	[coder encodeDouble:(double)_contentWidth forKey:@"NSContentWidth"];
	[coder encodeInteger:(NSInteger)_contentWidthType forKey:@"NSContentWidthType"];
	[coder encodeInteger:_verticalAlignment forKey:@"NSVerticalAlignment"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_backgroundColor = [fn_colour_from_components([coder decodeObjectForKey:@"NSBackgroundColor"]) retain];
	if ([coder containsValueForKey:@"NSContentWidth"]) {
		_contentWidth = (CGFloat)[coder decodeDoubleForKey:@"NSContentWidth"];
	}
	if ([coder containsValueForKey:@"NSContentWidthType"]) {
		_contentWidthType = (NSTextBlockValueType)[coder decodeIntegerForKey:@"NSContentWidthType"];
	}
	if ([coder containsValueForKey:@"NSVerticalAlignment"]) {
		_verticalAlignment = (NSTextBlockVerticalAlignment)[coder decodeIntegerForKey:@"NSVerticalAlignment"];
	}
	_borderColors = [[NSMutableDictionary alloc] init];
	{
		NSArray *edges = [coder decodeObjectForKey:@"NSBorderColors"];
		NSArray *widths = [coder decodeObjectForKey:@"NSWidths"];
		NSArray *types = [coder decodeObjectForKey:@"NSValueTypes"];
		int layer, edge;

		if ([edges isKindOfClass:[NSArray class]]) {
			for (edge = 0; edge < 4 && (NSUInteger)edge < [edges count]; edge++) {
				NSColor *colour = fn_colour_from_components([edges objectAtIndex:(NSUInteger)edge]);

				if (colour != nil) {
					[_borderColors setObject:colour
							  forKey:[NSNumber numberWithUnsignedInteger:(NSUInteger)(1u << edge)]];
				}
			}
		}
		for (layer = 0; layer < 3; layer++) {
			for (edge = 0; edge < 4; edge++) {
				NSUInteger slot = (NSUInteger)(layer * 4 + edge);

				if ([widths isKindOfClass:[NSArray class]] && slot < [widths count]) {
					_widths[layer][edge] = (CGFloat)[[widths objectAtIndex:slot] doubleValue];
				}
				if ([types isKindOfClass:[NSArray class]] && slot < [types count]) {
					_valueTypes[layer][edge] =
						(NSTextBlockValueType)[[types objectAtIndex:slot] unsignedIntegerValue];
				}
			}
		}
	}
	return self;
}

- (NSTextBlockValueType)valueTypeForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge
{
	NSInteger row = fn_layerRow(layer);
	NSInteger column = fn_edgeColumn(edge);

	if (row < 0 || row > 2 || column < 0) {
		return NSTextBlockAbsoluteValueType;
	}
	return _valueTypes[row][column];
}

- (void)setWidth:(CGFloat)width type:(NSTextBlockValueType)type forLayer:(NSTextBlockLayer)layer
{
	[self setWidth:width type:type forLayer:layer
		 edge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
}

- (CGFloat)widthForLayer:(NSTextBlockLayer)layer
{
	return [self widthForLayer:layer edge:NSTextBlockMinXEdge];
}

/* **AND A PERCENTAGE RESOLVES AGAINST THE CONTAINING RECT'S OWN DIMENSION** — width for an x edge, height for a y edge
 * — which is the only rectangle the block is given to resolve against. The stored value is a FRACTION (0.1 is ten
 * percent), which is the spelling Apple's percentage type uses. */
- (CGFloat)cg_resolvedWidthForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge inRect:(NSRect)rect
{
	CGFloat width = [self widthForLayer:layer edge:edge];

	if ([self valueTypeForLayer:layer edge:edge] == NSTextBlockPercentageValueType) {
		CGFloat basis = (edge == NSTextBlockMinXEdge || edge == NSTextBlockMaxXEdge) ? rect.size.width : rect.size.height;

		return width * basis;
	}
	return width;
}

- (CGFloat)cg_insetForEdge:(NSTextBlockEdge)edge inRect:(NSRect)rect
{
	return [self cg_resolvedWidthForLayer:NSTextBlockPadding edge:edge inRect:rect]
		+ [self cg_resolvedWidthForLayer:NSTextBlockBorder edge:edge inRect:rect]
		+ [self cg_resolvedWidthForLayer:NSTextBlockMargin edge:edge inRect:rect];
}

- (NSRect)boundsRectForContentRect:(NSRect)contentRect inRect:(NSRect)rect
		    textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)charRange
{
	NSRect inner = contentRect;

	/* **AND A CONTENT WIDTH, WHEN ONE WAS SET, IS WHAT THE BOX GROWS AROUND.** The door's job is the rectangle a caller
	 * draws, so a block told it is 100 points wide must produce a box 100 points plus its three layers — not the width the
	 * caller happened to pass. A PERCENTAGE resolves against the containing rect, which is the same rule the layer widths
	 * use, so the two cannot disagree about what "50%" is measured from. */
	if (_contentWidth > 0.0) {
		inner.size.width = (_contentWidthType == NSTextBlockPercentageValueType)
			? NSWidth(rect) * _contentWidth / 100.0
			: _contentWidth;
	}
	return [self _boundsRectForContentRect:inner inRect:rect textContainer:textContainer
		       characterRange:charRange];
}

/* ---- THE TEN THE SWEEP ADDS, AND THE ONE ARITHMETIC THEY SHARE --------------------------------- */

/* **THE DIMENSION WORD CARRIES THREE KINDS OF THING, AND EACH IS ANSWERED FROM THE STORAGE IT BELONGS TO.** A CONTENT
 * dimension is one of the six small numbers: a WIDTH is `_contentWidth` (with its type), and a HEIGHT is 0 because a
 * block cannot size its own height — its height is its content's, and a table's row is what gives it one. A LAYER
 * dimension is a layer bit OR-ed with an edge, and it lands in the same twelve-slot table the `…forLayer:edge:` doors
 * write. **THE HEIGHT ANSWER IS A ZERO AND NOT A REFUSAL MESSAGE** (the header says so): zero is a legitimate width, and
 * a print per call would be noise on a door a layout asks in a loop.
 *
 * THE LAYER BIT IS MAPPED TO THE `NSTextBlockLayer` VALUE HERE, because the two spellings of a layer are a number and a
 * bit and only one of them indexes the table. */
static NSInteger fn_layer_from_dimension(NSTextBlockDimension dimension)
{
	if ((dimension & NSTextBlockPaddingDimension) != 0) {
		return NSTextBlockPadding;
	}
	if ((dimension & NSTextBlockBorderDimension) != 0) {
		return NSTextBlockBorder;
	}
	if ((dimension & NSTextBlockMarginDimension) != 0) {
		return NSTextBlockMargin;
	}
	return NSNotFound;
}

static NSTextBlockEdge fn_edge_from_dimension(NSTextBlockDimension dimension)
{
	return (NSTextBlockEdge)(dimension & (NSTextBlockMinXEdge | NSTextBlockMaxXEdge |
					      NSTextBlockMinYEdge | NSTextBlockMaxYEdge));
}

- (void)setValue:(CGFloat)value type:(NSTextBlockValueType)type forDimension:(NSTextBlockDimension)dimension
{
	NSInteger layer = fn_layer_from_dimension(dimension);
	NSTextBlockEdge edge = fn_edge_from_dimension(dimension);

	if (layer != NSNotFound && edge != 0) {
		[self setWidth:value type:type forLayer:(NSTextBlockLayer)layer edge:edge];
		return;
	}
	if (dimension == NSTextBlockWidth) {
		[self setContentWidth:value type:type];
	}
	/* A HEIGHT (or its minimum or maximum) is RECORDED NOWHERE: see the method's own note. */
}

- (CGFloat)valueForDimension:(NSTextBlockDimension)dimension
{
	NSInteger layer = fn_layer_from_dimension(dimension);
	NSTextBlockEdge edge = fn_edge_from_dimension(dimension);

	if (layer != NSNotFound && edge != 0) {
		return [self widthForLayer:(NSTextBlockLayer)layer edge:edge];
	}
	if (dimension == NSTextBlockWidth) {
		return _contentWidth;
	}
	return 0.0;
}

- (NSTextBlockValueType)valueTypeForDimension:(NSTextBlockDimension)dimension
{
	NSInteger layer = fn_layer_from_dimension(dimension);
	NSTextBlockEdge edge = fn_edge_from_dimension(dimension);

	if (layer != NSNotFound && edge != 0) {
		return [self valueTypeForLayer:(NSTextBlockLayer)layer edge:edge];
	}
	if (dimension == NSTextBlockWidth) {
		return _contentWidthType;
	}
	return NSTextBlockAbsoluteValueType;
}

/* **AND THE CONTENT WIDTH UNDER ITS OWN NAME, WHICH IS THE SAME TWO FIELDS.** Apple declares both spellings; this tier
 * keeps one storage and lets the generic door find it, so the pair cannot disagree. */
- (CGFloat)contentWidth
{
	return _contentWidth;
}

- (NSTextBlockValueType)contentWidthValueType
{
	return _contentWidthType;
}

- (void)setContentWidth:(CGFloat)width type:(NSTextBlockValueType)type
{
	_contentWidth = (width > 0.0) ? width : 0.0;
	_contentWidthType = type;
}

/* ONE COLOUR, FOUR EDGES — the shorthand a caller with a single border colour writes, and the same storage the per-edge
 * door uses. */
- (void)setBorderColor:(NSColor *)color
{
	[self setBorderColor:color forEdge:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge |
					  NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
}

- (NSTextBlockVerticalAlignment)verticalAlignment
{
	return _verticalAlignment;
}

- (void)setVerticalAlignment:(NSTextBlockVerticalAlignment)alignment
{
	_verticalAlignment = alignment;
}

/* AND THE OLDER NAME FOR THE VALUE TYPE — see the header: one answer, under the two spellings Apple has used. */
- (NSTextBlockValueType)widthValueTypeForLayer:(NSTextBlockLayer)layer edge:(NSTextBlockEdge)edge
{
	return [self valueTypeForLayer:layer edge:edge];
}

- (NSRect)_boundsRectForContentRect:(NSRect)contentRect inRect:(NSRect)rect
		      textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)charRange
{
	CGFloat left = [self cg_insetForEdge:NSTextBlockMinXEdge inRect:rect];
	CGFloat right = [self cg_insetForEdge:NSTextBlockMaxXEdge inRect:rect];
	CGFloat top = [self cg_insetForEdge:NSTextBlockMinYEdge inRect:rect];
	CGFloat bottom = [self cg_insetForEdge:NSTextBlockMaxYEdge inRect:rect];

	(void)textContainer;
	(void)charRange;
	return NSMakeRect(contentRect.origin.x - left, contentRect.origin.y - top,
			  contentRect.size.width + left + right, contentRect.size.height + top + bottom);
}

/* **AND THE INVERSE: THE CONTENT A BLOCK HAS ROOM FOR AT A POINT.** The point is the content origin the caller wants;
 * the containing rect gives the size, shrunk by every layer on both sides. */
- (NSRect)rectForLayoutAtPoint:(NSPoint)point inRect:(NSRect)rect
		 textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)charRange
{
	CGFloat left = [self cg_insetForEdge:NSTextBlockMinXEdge inRect:rect];
	CGFloat right = [self cg_insetForEdge:NSTextBlockMaxXEdge inRect:rect];
	CGFloat top = [self cg_insetForEdge:NSTextBlockMinYEdge inRect:rect];
	CGFloat bottom = [self cg_insetForEdge:NSTextBlockMaxYEdge inRect:rect];
	CGFloat width = rect.size.width - left - right;
	CGFloat height = rect.size.height - top - bottom;

	(void)textContainer;
	(void)charRange;
	if (width < 0.0) {
		width = 0.0;
	}
	if (height < 0.0) {
		height = 0.0;
	}
	return NSMakeRect(point.x + left, point.y + top, width, height);
}

/* **THE GROUND FIRST, THEN THE FOUR EDGES.** An edge is drawn only when it has a width; its colour is the one set for
 * it, or black when a width was given without one — which is Apple's default border colour and is the reason a border
 * with no colour still shows. THIS DOOR DRAWS ALL FOUR; the `edges:` door below is the one a collapsing table uses. */
- (void)drawBackgroundWithFrame:(NSRect)frame inView:(NSView *)view characterRange:(NSRange)charRange
		  layoutManager:(NSLayoutManager *)layoutManager
{
	[self drawBackgroundWithFrame:frame inView:view characterRange:charRange layoutManager:layoutManager
		edges:(NSTextBlockMinXEdge | NSTextBlockMaxXEdge | NSTextBlockMinYEdge | NSTextBlockMaxYEdge)];
}

/* **AND THE EDGE MASK, WHICH IS ALL THE DIFFERENCE.** The ground is unconditional; an edge is skipped when its bit is
 * not set, which is how one of two cells sharing a border leaves that border to the other. */
- (void)drawBackgroundWithFrame:(NSRect)frame inView:(NSView *)view characterRange:(NSRange)charRange
		  layoutManager:(NSLayoutManager *)layoutManager edges:(NSTextBlockEdge)edges
{
	[self _drawBackgroundWithFrame:frame inView:view characterRange:charRange layoutManager:layoutManager
		edges:edges];
}

/* **THE PAINTER ITSELF**, reachable by `NSTextTable`'s default hook without re-entering an override — see
 * `NSTextBlock_internal.h`. */
- (void)_drawBackgroundWithFrame:(NSRect)frame inView:(NSView *)view characterRange:(NSRange)charRange
		  layoutManager:(NSLayoutManager *)layoutManager edges:(NSTextBlockEdge)edges
{
	NSUInteger i;

	(void)view;
	(void)charRange;
	(void)layoutManager;
	if (_backgroundColor != nil) {
		[_backgroundColor setFill];
		[[NSBezierPath bezierPathWithRect:frame] fill];
	}
	for (i = 0; i < 4; i++) {
		CGFloat width = [self cg_resolvedWidthForLayer:NSTextBlockBorder edge:fn_edges[i] inRect:frame];
		NSColor *colour;
		NSRect edgeRect;

		/* A SHARED EDGE THIS CELL DOES NOT OWN IS NOT THIS CELL'S TO DRAW. */
		if ((edges & fn_edges[i]) == 0) {
			continue;
		}
		if (width <= 0.0) {
			continue;
		}
		colour = [self borderColorForEdge:fn_edges[i]];
		if (colour == nil) {
			colour = [NSColor blackColor];
		}
		switch (fn_edges[i]) {
		case NSTextBlockMinXEdge:
			edgeRect = NSMakeRect(frame.origin.x, frame.origin.y, width, frame.size.height);
			break;
		case NSTextBlockMaxXEdge:
			edgeRect = NSMakeRect(frame.origin.x + frame.size.width - width, frame.origin.y,
					      width, frame.size.height);
			break;
		case NSTextBlockMinYEdge:
			edgeRect = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, width);
			break;
		default:
			edgeRect = NSMakeRect(frame.origin.x, frame.origin.y + frame.size.height - width,
					      frame.size.width, width);
			break;
		}
		[colour setFill];
		[[NSBezierPath bezierPathWithRect:edgeRect] fill];
	}
}

@end
