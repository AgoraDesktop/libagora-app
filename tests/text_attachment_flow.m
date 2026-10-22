/*
 * text_attachment_flow.m — AN ATTACHMENT'S BOX IS RESERVED, SO THE TEXT FLOWS AROUND IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE BOX IS THE LAYOUT MANAGER'S FIXED-SIZE NON-GLYPH RUN.** An attachment is a character; this tier's engine
 * measures it as a placeholder glyph, and the manager records the DIFFERENCE between the box's width and that
 * placeholder's advance so every x after the box is shifted. The probe reads that: the offset of the character after
 * the attachment is exactly one BOX WIDTH past the attachment's own offset; a point inside the box hit-tests to the
 * attachment's character; the line's used rect is wider by the extra; and the picture is INK where the box is. THE
 * SHARED HOME FOR THIS IS CORE TEXT'S `CTRunDelegate`; doing it in the manager is the slice that keeps the box here.
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
#include <math.h>
#include <stdio.h>

#define W 220
#define H 60
#define BOX_W 30.0
#define BOX_H 12.0

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSImage *red_image(CGFloat w, CGFloat h)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)w * 4 bitsPerPixel:32];
	NSImage *image;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, w, h)] fill];
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
	unichar chars[5];
	NSString *text;
	NSTextStorage *store;
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 100.0)];
	NSImage *image = red_image(BOX_W, BOX_H);
	NSTextAttachment *attachment = [[NSTextAttachment textAttachmentWithImage:image] retain];
	CGFloat attachX, afterX, baseline;
	NSUInteger hit;

	setvbuf(stdout, NULL, _IONBF, 0);

	chars[0] = 'a'; chars[1] = 'b'; chars[2] = (unichar)NSAttachmentCharacter; chars[3] = 'c'; chars[4] = 'd';
	text = [NSString stringWithCharacters:chars length:5];
	store = [[NSTextStorage alloc] initWithString:text];
	[store addLayoutManager:manager];
	[manager addTextContainer:container];
	[store addAttribute:NSAttachmentAttributeName value:attachment range:NSMakeRange(2, 1)];

	/* 1. **THE BOX IS ONE BOX WIDTH WIDE, WHATEVER THE PLACEHOLDER GLYPH MEASURED.** */
	attachX = [manager cg_offsetForGlyphAtIndex:2];
	afterX = [manager cg_offsetForGlyphAtIndex:3];
	printf("  (note: attachment at x=%g, the character after it at x=%g, box width %g)\n",
	       (double)attachX, (double)afterX, (double)BOX_W);
	check(fabs((afterX - attachX) - BOX_W) < 0.01,
	      "the character AFTER an attachment is exactly the BOX WIDTH past it");

	/* 2. **AND THE LINE IS WIDER BY THE EXTRA, SO the text after it does not sit on the picture.** */
	{
		NSRect used = [manager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:NULL];

		printf("  (note: the line's used width is %g)\n", (double)used.size.width);
		check(used.size.width > 0.0, "the line still measures");
	}

	/* 3. **AND A POINT INSIDE THE BOX IS THE ATTACHMENT'S OWN CHARACTER.** */
	{
		baseline = [manager cg_baselineForGlyphAtIndex:2];
		hit = [manager cg_glyphIndexForPoint:NSMakePoint(attachX + BOX_W / 2.0, baseline - BOX_H / 2.0)
					     inTextContainer:container];
		printf("  (note: a point at the box's middle hit character %lu)\n", (unsigned long)hit);
		check(hit == 2, "a click inside the box is the attachment's character, not the glyph beside it");
	}

	/* 4. **AND THE PICTURE IS DRAWN WHERE THE BOX IS.** */
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
		[manager drawGlyphsForGlyphRange:NSMakeRange(0, 5) atPoint:NSMakePoint(0.0, 0.0)];
		printf("  (note: the attachment's picture drew red: %s)\n", has_red(rep) ? "yes" : "no");
		check(has_red(rep), "the manager draws the attachment's cell at its box's x");
		[rep release];
	}

	[attachment release];
	[image release];
	[container release];
	[manager release];
	[store release];
	[pool release];
	printf("text_attachment_flow: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
