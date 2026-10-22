/*
 * text_coding.m — `NSCoding` on the two text-layout values: an archived list and an archived block.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **BOTH CLASSES DECLARE `<NSCoding, NSCopying>` IN THE 10.6 SDK** — `NSTextList` in its own header and `NSTextBlock` in
 * `NSTextTable.h`, which is where the SDK keeps the block — and neither had the pair until now. The probe archives and
 * unarchives, because the property a conformance promises is a ROUND TRIP, not the existence of two methods: a class
 * that archived nothing would still answer both selectors.
 *
 * **AND IT MEASURES WHAT IS DELIBERATELY NOT CARRIED.** A list's ENCLOSING list is a fact about the paragraph style's
 * stack rather than about the list, so an archive must not pretend to carry it — a decoded list is a level, and the
 * style links it again. That is asserted by giving a list an enclosing one, archiving it, and checking the decoded copy
 * has none.
 *
 * **AND A BLOCK'S COLOURS GO AS COMPONENTS**, because this layer's `NSColor` has no archive of its own; the decoded
 * block answers the same COLOUR, which is what a caller can observe.
 */
#import <AppKit/NSTextBlock.h>
#import <AppKit/NSTextList.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* THE LIST: three facts, and the round trip. */
	{
		NSTextList *list = [[NSTextList alloc] initWithMarkerFormat:@"{upper-roman}"
							     options:NSTextListPrependEnclosingMarker];
		NSFileWrapper *unused = nil;
		NSData *data;
		NSTextList *back;

		(void)unused;
		[list setStartingItemNumber:7];
		data = [NSKeyedArchiver archivedDataWithRootObject:list];
		check(data != nil && [data length] > 0, "the list archives");
		back = (data != nil) ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
		check(back != nil && [back isKindOfClass:[NSTextList class]], "and unarchives as a list");
		if (back != nil) {
			printf("  (the list came back as `%s`, options %lu, start %ld)\n",
			       [[back markerFormat] UTF8String], (unsigned long)[back listOptions],
			       (long)[back startingItemNumber]);
			check([[back markerFormat] isEqualToString:@"{upper-roman}"], "with its marker format");
			check([back listOptions] == NSTextListPrependEnclosingMarker, "its options");
			check([back startingItemNumber] == 7, "and its starting number");
			check([[back markerForItemNumber:4] isEqualToString:@"IV"],
			      "so it computes the same marker the original did");
		}
		/* **AND THE ENCLOSING LIST IS NOT IN THE ARCHIVE**, which is asserted rather than assumed: a list linked into
		 * a stack must come back as a level, not as a stack. */
		{
			NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
			NSTextList *outer = [[[NSTextList alloc] initWithMarkerFormat:@"{decimal}" options:0] autorelease];
			NSTextList *inner = [[[NSTextList alloc] initWithMarkerFormat:@"{lower-alpha}"
									    options:NSTextListPrependEnclosingMarker] autorelease];
			NSData *nested;
			NSTextList *decoded;

			[style setTextLists:[NSArray arrayWithObjects:outer, inner, nil]];
			/* THE STYLE'S OWN COPY IS THE ONE LINKED — archiving the inner one it holds, by index. */
			nested = [NSKeyedArchiver archivedDataWithRootObject:[[style textLists] objectAtIndex:1]];
			decoded = (nested != nil) ? [NSKeyedUnarchiver unarchiveObjectWithData:nested] : nil;
			printf("  (a linked list archives to `%s`)\n",
			       (decoded != nil) ? [[decoded markerForItemNumber:3] UTF8String] : "(nil)");
			check(decoded != nil && [[decoded markerForItemNumber:3] isEqualToString:@"c"],
			      "and comes back WITHOUT its enclosing list, so the marker is the bare one");
			[style release];
		}
		[list release];
	}

	/* THE BLOCK: the ground, an edge colour, and the widths and types per layer and edge. */
	{
		NSTextBlock *block = [[NSTextBlock alloc] init];
		NSData *data;
		NSTextBlock *back;
		NSColor *background = [NSColor colorWithCalibratedRed:0.25 green:0.5 blue:0.75 alpha:1.0];
		NSColor *border = [NSColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:1.0];

		[block setBackgroundColor:background];
		[block setBorderColor:border forEdge:NSTextBlockMinXEdge];
		[block setWidth:12.0 type:NSTextBlockAbsoluteValueType forLayer:NSTextBlockPadding edge:NSTextBlockMaxYEdge];
		[block setWidth:0.5 type:NSTextBlockPercentageValueType forLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge];

		data = [NSKeyedArchiver archivedDataWithRootObject:block];
		check(data != nil && [data length] > 0, "the block archives");
		back = (data != nil) ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
		check(back != nil && [back isKindOfClass:[NSTextBlock class]], "and unarchives as a block");
		if (back != nil) {
			NSColor *ground = [back backgroundColor];
			NSColor *edge = [back borderColorForEdge:NSTextBlockMinXEdge];

			check(ground != nil && fabs([ground redComponent] - 0.25) < 0.01
			      && fabs([ground greenComponent] - 0.5) < 0.01
			      && fabs([ground blueComponent] - 0.75) < 0.01,
			      "the ground comes back as the same colour");
			check(edge != nil && fabs([edge redComponent] - 1.0) < 0.01
			      && fabs([edge greenComponent]) < 0.01,
			      "and the edge colour did");
			check([back borderColorForEdge:NSTextBlockMaxXEdge] == nil,
			      "while an edge that was never drawn is still not drawn");
			check(fabs([back widthForLayer:NSTextBlockPadding edge:NSTextBlockMaxYEdge] - 12.0) < 0.01
			      && [back valueTypeForLayer:NSTextBlockPadding edge:NSTextBlockMaxYEdge]
				 == NSTextBlockAbsoluteValueType,
			      "the absolute width survives with its TYPE");
			check(fabs([back widthForLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge] - 0.5) < 0.01
			      && [back valueTypeForLayer:NSTextBlockBorder edge:NSTextBlockMaxXEdge]
				 == NSTextBlockPercentageValueType,
			      "and a percentage one does too, in its own layer and edge");
		}
		[block release];
	}

	[pool release];
	printf("text_coding: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
