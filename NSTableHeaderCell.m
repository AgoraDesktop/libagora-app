/*
 * NSTableHeaderCell — a word in the table header's box.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 */
#import "NSTableHeaderCell.h"

#import "NSColor.h"
#import "NSFont.h"
#import "NSBezierPath.h"
#import "NSStringDrawing.h"

#include <math.h>

#define AG_HEADER_INDICATOR_SIZE 7.0
#define AG_HEADER_INDICATOR_RIGHT 6.0

@implementation NSTableHeaderCell

- (instancetype)initTextCell:(NSString *)aString
{
	self = [super initTextCell:aString];
	if (self != nil) {
		[self setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
		[self setAlignment:NSCenterTextAlignment];
		[self setBordered:NO];
		[self setBezeled:NO];
		[self setDrawsBackground:NO];
	}
	return self;
}

/* THE FACE, THEN THE WORD. The face is the control grey with a dark bottom and right edge; the top edge is left
 * alone so a row of headers reads as one strip rather than a row of raised buttons. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	[[NSColor controlColor] setFill];
	[[NSBezierPath bezierPathWithRect:cellFrame] fill];
	[[NSColor controlDarkShadowColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(NSMinX(cellFrame), NSMaxY(cellFrame) - 1.0,
						     NSWidth(cellFrame), 1.0)] fill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(NSMaxX(cellFrame) - 1.0, NSMinY(cellFrame),
						     1.0, NSHeight(cellFrame))] fill];
	[self drawInteriorWithFrame:cellFrame inView:controlView];
}

/* **THE WORD IS CENTRED HERE RATHER THAN BY `NSTextFieldCell`.** A field draws from its left inset, which is right
 * for a value and wrong for a header; the header's own door is the one that knows its box. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	NSString *string = [self cg_contentText];
	NSFont *font = (NSFont *)[self font];
	NSDictionary *attributes;
	NSSize size;
	CGFloat x, baseline;

	(void)controlView;
	if (string == nil || [string length] == 0) {
		return;
	}
	if (font == nil) {
		font = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
		      [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
	size = [string sizeWithAttributes:attributes];
	if (size.width <= 0.0 || size.height <= 0.0) {
		return;
	}
	x = NSMidX(cellFrame) - size.width / 2.0;
	if (x < NSMinX(cellFrame) + 3.0) {
		x = NSMinX(cellFrame) + 3.0;
	}
	baseline = NSMidY(cellFrame) - (([font ascender] + (CGFloat)fabs((double)[font descender])) / 2.0)
		   + (CGFloat)fabs((double)[font descender]);
	[string drawAtPoint:NSMakePoint(x, baseline) withAttributes:attributes];
}

/* ---- THE SORT INDICATOR ------------------------------------------------------------------------ */

- (NSRect)sortIndicatorRectForBounds:(NSRect)theRect
{
	return NSMakeRect(NSMaxX(theRect) - AG_HEADER_INDICATOR_RIGHT - AG_HEADER_INDICATOR_SIZE,
			  NSMidY(theRect) - AG_HEADER_INDICATOR_SIZE / 2.0,
			  AG_HEADER_INDICATOR_SIZE, AG_HEADER_INDICATOR_SIZE);
}

- (void)drawSortIndicatorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
			 ascending:(BOOL)ascending priority:(NSInteger)priority
{
	NSRect box = [self sortIndicatorRectForBounds:cellFrame];
	NSBezierPath *triangle = [NSBezierPath bezierPath];

	(void)controlView;
	(void)priority;
	if (ascending) {
		[triangle moveToPoint:NSMakePoint(NSMinX(box), NSMaxY(box))];
		[triangle lineToPoint:NSMakePoint(NSMaxX(box), NSMaxY(box))];
		[triangle lineToPoint:NSMakePoint(NSMidX(box), NSMinY(box))];
	} else {
		[triangle moveToPoint:NSMakePoint(NSMinX(box), NSMinY(box))];
		[triangle lineToPoint:NSMakePoint(NSMaxX(box), NSMinY(box))];
		[triangle lineToPoint:NSMakePoint(NSMidX(box), NSMaxY(box))];
	}
	[triangle closePath];
	[[NSColor controlTextColor] setFill];
	[triangle fill];
}

@end
