/*
 * text_table_delegation.m — the TABLE draws its cells: subclassing `NSTextTable` changes what is drawn.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * `NSTextTable` carries the delegation doors 10.6 declares — a cell's rect, its bounds, and
 * `-drawBackgroundForBlock:withFrame:inView:characterRange:layoutManager:` — and `NSTextTableBlock` is documented as
 * forwarding to its table, which is what makes subclassing the TABLE the way to customise one. The manager used to ask
 * the BLOCK, so a table subclass had nothing to override.
 *
 * **AND THE PROBE MEASURES THE OVERRIDE RATHER THAN ITS EXISTENCE**: the cell's own ground is GREEN, the table subclass
 * paints BLUE over the frame it is handed, and the pixels are read — green means the block drew, blue means the TABLE did.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextBlock.h>
#import <AppKit/NSTextTable.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
#include <math.h>
#include <stdio.h>

#define W 200
#define H 60

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *draw(NSLayoutManager *manager, NSUInteger length)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
	NSGraphicsContext *ctx;
	CGContextRef cg;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	cg = (CGContextRef)[ctx graphicsPort];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[manager drawBackgroundForGlyphRange:NSMakeRange(0, length) atPoint:NSMakePoint(0.0, 0.0)];
	return rep;
}

static int count_of(NSBitmapImageRep *rep, CGFloat r, CGFloat g, CGFloat b)
{
	int count = 0, x, y;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (fabs([c redComponent] - r) < 0.1 && fabs([c greenComponent] - g) < 0.1
			    && fabs([c blueComponent] - b) < 0.1) {
				count++;
			}
		}
	}
	return count;
}

@interface FNPaintingTable : NSTextTable
@end

@implementation FNPaintingTable
- (void)drawBackgroundForBlock:(NSTextTableBlock *)block withFrame:(NSRect)frameRect inView:(NSView *)controlView
		characterRange:(NSRange)charRange layoutManager:(NSLayoutManager *)layoutManager
{
	(void)block;
	(void)controlView;
	(void)charRange;
	(void)layoutManager;
	[[NSColor blueColor] setFill];
	[[NSBezierPath bezierPathWithRect:frameRect] fill];
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	FNPaintingTable *table = [[FNPaintingTable alloc] init];
	NSTextTableBlock *only = [[[NSTextTableBlock alloc] initWithTable:table startingRow:0 rowSpan:1
							    startingColumn:0 columnSpan:1] autorelease];
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	NSTextStorage *store;
	NSTextContainer *container;
	NSLayoutManager *manager;
	NSBitmapImageRep *painted;
	int blue, green;

	setvbuf(stdout, NULL, _IONBF, 0);
	[table setNumberOfColumns:1];
	[only setBackgroundColor:[NSColor greenColor]];

	[style addTextBlock:only];
	[style setMinimumLineHeight:20.0];
	[style setMaximumLineHeight:20.0];
	store = [[NSTextStorage alloc] initWithString:@"ab"];
	[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, 2)];
	container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize((CGFloat)W, (CGFloat)H)];
	manager = [[NSLayoutManager alloc] init];
	[manager addTextContainer:container];
	[store addLayoutManager:manager];

	painted = draw(manager, [store length]);
	blue = count_of(painted, 0.0, 0.0, 1.0);
	green = count_of(painted, 0.0, 1.0, 0.0);
	printf("  (the cell's frame came out %d blue pixel(s) and %d green)\n", blue, green);
	check(blue > 100, "the TABLE's override painted the cell, so a table subclass is reachable");
	check(green == 0, "and the block's own green ground was never drawn");

	[painted release];
	[manager release];
	[container release];
	[store release];
	[style release];
	[table release];
	[pool release];
	printf("text_table_delegation: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
