/*
 * NSTableHeaderCell — a word in the table header's box.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import "NSTableHeaderCell.h"

#import "NSTableHeaderView.h"
#import "NSTableView.h"
#import "NSTableColumn.h"
#import "NSColor.h"
#import "NSFont.h"
#import "NSBezierPath.h"
#import "NSStringDrawing.h"
#import "NSGraphicsContext.h"

#include <math.h>

#define AG_HEADER_INDICATOR_SIZE 7.0
#define AG_HEADER_INDICATOR_RIGHT 6.0

@implementation NSTableHeaderCell

/* ============================================================================================
 * ARCHIVING: NOTHING EITHER: A HEADER CELL IS ITS FIELD CELL.
 * ============================================================================================ */
/* The same shape as `NSActionCell`: no instance storage of its own, so the inherited coding is complete by measurement
 * rather than by assumption. */
+ (BOOL)supportsSecureCoding
{
	return YES;
}

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
	/* **AND THE INDICATOR, WHEN THIS COLUMN IS THE ONE SORTED.** `-drawSortIndicatorWithFrame:…` has been on this class
	 * since it was written and nothing called it: a header could sort a table and never say so, which reads as a header
	 * that did nothing. The column knows its own prototype, so the match is between that key and the table's first
	 * descriptor — Apple's rule, and the one a click produces. */
	{
		NSTableHeaderView *header = [controlView isKindOfClass:[NSTableHeaderView class]]
			? (NSTableHeaderView *)controlView : nil;
		NSTableView *table = [header tableView];
		NSSortDescriptor *first = ([[table sortDescriptors] count] > 0)
			? [[table sortDescriptors] objectAtIndex:0] : nil;
		NSTableColumn *column = nil;
		NSUInteger i;

		if (table != nil && first != nil) {
			for (i = 0; i < [[table tableColumns] count] && column == nil; i++) {
				NSTableColumn *candidate = [[table tableColumns] objectAtIndex:i];

				if ([candidate headerCell] == self) {
					column = candidate;
				}
			}
		}
		if (column != nil && [[[column sortDescriptorPrototype] key] isEqual:[first key]]) {
			[self drawSortIndicatorWithFrame:cellFrame inView:controlView ascending:[first ascending]
						priority:0];
		}
	}
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
	/* THE HEADER'S WORD IS CENTRED BY THE BASE CELL'S ONE DOOR — the same one a field, a placeholder and a table
	 * data cell use, so a header's title and its sort indicator cannot disagree about the middle of the line; see
	 * `NSTextFieldCell.h` for the measurement and for why the arithmetic is not repeated here. */
	baseline = [self cg_centredBaselineInFrame:cellFrame font:font];
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
