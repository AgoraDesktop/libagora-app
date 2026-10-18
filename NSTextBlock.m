/*
 * NSTextBlock.m — the box: three layers of widths, a ground, and four edges.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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
- (id)copy
{
	NSTextBlock *copy = [[[self class] alloc] init];
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
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_backgroundColor = [fn_colour_from_components([coder decodeObjectForKey:@"NSBackgroundColor"]) retain];
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
