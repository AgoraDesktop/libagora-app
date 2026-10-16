/*
 * text_attachment.m — AN ATTACHMENT: A CHARACTER THAT STANDS FOR A PICTURE, AND THE CELL THAT DRAWS IT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE MODEL IS A CHARACTER AND AN ATTRIBUTE, AND THE PROBE CHECKS BOTH ENDS.** `NSAttachmentCharacter` (U+FFFC) is
 * the character; `NSAttachmentAttributeName` carries the `NSTextAttachment`; and the layout manager draws the
 * attachment's CELL at that character's place instead of setting its glyph. So the probe reads the value object (a
 * picture gives an attachment a cell whose size is the picture's), draws the cell directly, and then draws a STORE
 * that has an attachment in it and reads the picture's own colour at the character's own x.
 *
 * **AND THE LINE'S ADVANCE IS THE ENGINE'S NOW.** A `CTRunDelegate` over the attachment character makes Core Text
 * reserve the cell's width, so the advance past the character IS the box and the text after it flows around rather
 * than over it — `tests/text_attachment_flow.m` is the probe for that. This probe keeps its attachment alone on a line
 * so the drawing it reads at the character's own x is the cell's and not a neighbour's.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
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

/* A PICTURE THAT IS ONE FLAT COLOUR, so a pixel read says whether it was drawn. */
static NSImage *red_image(CGFloat w, CGFloat h)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)w * 4 bitsPerPixel:32];
	NSImage *image;
	NSGraphicsContext *ctx;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, w, h)] fill];
	(void)ctx;
	image = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
	[image addRepresentation:rep];
	[rep release];
	return image;
}

static int has_red(NSBitmapImageRep *rep)
{
	int x, y;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4) {
				return 1;
			}
		}
	}
	return 0;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSImage *image = red_image(12.0, 12.0);
	NSTextAttachment *attachment = [[NSTextAttachment textAttachmentWithImage:image] retain];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE VALUE OBJECT: A PICTURE GIVES THE ATTACHMENT A CELL THAT IS THE PICTURE'S SIZE.** */
	{
		NSCell<NSTextAttachmentCell> *cell = [attachment attachmentCell];
		NSSize size = (cell != nil) ? [cell cellSize] : NSZeroSize;

		printf("  (note: an attachment over a 12x12 picture answered cell size %gx%g)\n",
		       (double)size.width, (double)size.height);
		check(cell != nil, "`+textAttachmentWithImage:` gives the attachment a cell to draw with");
		check(size.width == 12.0 && size.height == 12.0, "and the cell's size is the picture's own");
		check([attachment image] == image, "and the attachment answers the picture it was made with");
	}

	/* 2. **AND THE CELL DRAWS WHERE IT IS TOLD.** Direct, offscreen: the picture's colour lands inside the frame. */
	{
		NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
		NSCell<NSTextAttachmentCell> *cell = [attachment attachmentCell];

		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
		[cell drawWithFrame:NSMakeRect(20.0, 20.0, 12.0, 12.0) inView:nil];
		printf("  (note: drawing the cell at (20,20) put red in the frame: %s)\n", has_red(rep) ? "yes" : "no");
		check(has_red(rep), "`-drawWithFrame:inView:` draws the picture in the frame it was given");
		[rep release];
	}

	/* 3. **AND A STORE WITH AN ATTACHMENT DRAWS IT AT THE CHARACTER's OWN PLACE.** The store is one
	 * `NSAttachmentCharacter` carrying the attachment; the manager's draw is what puts the picture down. */
	{
		unichar character = (unichar)NSAttachmentCharacter;
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:[NSString stringWithCharacters:&character length:1]];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 100.0)];
		NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
		NSGraphicsContext *ctx;
		CGContextRef cg;

		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		[store addAttribute:NSAttachmentAttributeName value:attachment range:NSMakeRange(0, 1)];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
		ctx = [NSGraphicsContext currentContext];
		cg = (CGContextRef)[ctx graphicsPort];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
		CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
		CGContextScaleCTM(cg, 1.0, -1.0);
		[manager drawGlyphsForGlyphRange:NSMakeRange(0, 1) atPoint:NSMakePoint(0.0, 0.0)];
		printf("  (note: a store carrying one attachment drew red: %s)\n", has_red(rep) ? "yes" : "no");
		check(has_red(rep), "the manager draws the attachment's CELL where its character is");
		[rep release];
		[container release];
		[manager release];
		[store release];
	}

	/* 4. **AND A CALLER'S OWN CELL REPLACES THE CONVENIENCE ONE.** */
	{
		NSTextAttachmentCell *cell = [[NSTextAttachmentCell alloc] init];

		[cell setImage:image];
		[attachment setAttachmentCell:cell];
		check([attachment attachmentCell] == cell, "`-setAttachmentCell:` replaces the cell the picture made");
		[cell release];
	}

	[attachment release];
	[image release];
	[pool release];
	printf("text_attachment: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
