/*
 * image_view — NSImageView: the image cell's face, the two edit flags, and the standard commands.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE VIEW IS MOSTLY FORWARDS, SO THE PROBE ASKS THE CELL AS WELL AS THE VIEW.** The image, alignment, scaling,
 * frame and editable flag are the cell's; the animation and cut/copy/paste flags are the view's. The ink check is a
 * rendered image at two alignments, because a stored alignment that never changes the drawing is a setting nobody
 * reads. The commands are checked on both sides of their gates: paste with the flags off does nothing, with them on
 * it reads a PNG from the pasteboard, delete clears, and cut does not clear because this tree cannot encode a TIFF.
 */
#import <AppKit/NSImageView.h>
#import <AppKit/NSImageCell.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

#define W 100
#define H 100
#define IMAGE_SIDE 20

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSImage *make_image(NSColor *colour)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:IMAGE_SIDE pixelsHigh:IMAGE_SIDE bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:IMAGE_SIDE * 4 bitsPerPixel:32];
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(IMAGE_SIDE, IMAGE_SIDE)];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[colour setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, IMAGE_SIDE, IMAGE_SIDE)] fill];
	[image addRepresentation:rep];
	[rep release];
	return image;
}

static NSBitmapImageRep *render(NSView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, W, H)] fill];
	[view drawRect:[view bounds]];
	return rep;
}

static void red_box(NSBitmapImageRep *rep, int *x0, int *x1)
{
	int x, y;

	*x0 = W;
	*x1 = -1;
	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.8 && [c greenComponent] < 0.3 && [c blueComponent] < 0.3) {
				if (x < *x0) *x0 = x;
				if (x > *x1) *x1 = x;
			}
		}
	}
}

int main(void)
{
	@autoreleasepool {
		NSImageView *view = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, W, H)];
		NSImage *image = make_image([NSColor redColor]);
		NSImageCell *cell = (NSImageCell *)[view cell];

		/* 1. THE CELL AND THE DEFAULTS. */
		check([NSImageView cellClass] == [NSImageCell class], "`+cellClass` names NSImageCell");
		check([cell isKindOfClass:[NSImageCell class]], "a fresh image view owns an image cell");
		check([view image] == nil, "with no image");
		check([view imageAlignment] == NSImageAlignLeft, "alignment defaults to left");
		check([view imageScaling] == NSImageScaleNone, "scaling defaults to none");
		check([view imageFrameStyle] == NSImageFrameNone, "the frame defaults to none");
		check(![view isEditable] && ![view allowsCutCopyPaste] && ![view animates],
		      "and the two edit flags and the animation flag start NO");

		/* 2. THE FORWARDS, AND THE ALIGNMENT'S INK. */
		[view setImage:image];
		check([view image] == image && [[view cell] image] == image,
		      "the image is the cell's image");
		{
			NSBitmapImageRep *rep = render(view);
			int x0, x1;

			red_box(rep, &x0, &x1);
			printf("  (note: left alignment puts the red box at x %d..%d)\n", x0, x1);
			check(x1 >= 0 && x0 < W / 2, "and the left-aligned image draws at the left");
			[rep release];
		}
		[view setImageAlignment:NSImageAlignRight];
		check([view imageAlignment] == NSImageAlignRight
		      && [cell imageAlignment] == NSImageAlignRight,
		      "`-setImageAlignment:` forwards to the cell");
		{
			NSBitmapImageRep *rep = render(view);
			int x0, x1;

			red_box(rep, &x0, &x1);
			printf("  (note: right alignment puts the red box at x %d..%d)\n", x0, x1);
			check(x0 > W / 2 && x1 >= W - 1, "and the right-aligned image draws at the right");
			[rep release];
		}
		[view setImageScaling:NSImageScaleAxesIndependently];
		[view setImageFrameStyle:NSImageFrameGrayBezel];
		check([view imageScaling] == NSImageScaleAxesIndependently
		      && [cell imageScaling] == NSImageScaleAxesIndependently,
		      "the scaling forwards");
		check([view imageFrameStyle] == NSImageFrameGrayBezel
		      && [cell imageFrameStyle] == NSImageFrameGrayBezel,
		      "and the frame style forwards");

		/* 3. THE EDIT FLAGS AND THE COMMANDS. */
		[view setEditable:YES];
		check([view isEditable] && [[view cell] isEditable], "editable forwards to the cell");
		[view setAnimates:YES];
		check([view animates], "the animation flag round-trips");
		check(![view allowsCutCopyPaste], "cut/copy/paste is still gated off");

		{
			NSImage *replacement = make_image([NSColor blueColor]);
			NSBitmapImageRep *rep = [[replacement representations] objectAtIndex:0];
			NSData *png = [rep representationUsingType:NSPNGFileType properties:nil];
			NSPasteboard *board = [NSPasteboard generalPasteboard];

			check(png != nil, "the probe can encode a PNG for the pasteboard");
			[board declareTypes:[NSArray arrayWithObject:NSPasteboardTypePNG] owner:nil];
			[board setData:png forType:NSPasteboardTypePNG];

			[view paste:nil];
			check([view image] == image, "paste does nothing while cut/copy/paste is off");
			[view setAllowsCutCopyPaste:YES];
			check([view allowsCutCopyPaste], "the cut/copy/paste flag round-trips");
			[view paste:nil];
			check([view image] != nil && [view image] != image,
			      "with the flag on, paste reads the pasteboard's image");

			[view copy:nil];	/* refuses through -TIFFRepresentation: no encoder */
			[view cut:nil];
			check([view image] != nil, "cut leaves the image because the encoder refused the copy");

			[view delete:nil];
			check([view image] == nil, "delete clears the image field");
			[replacement release];
		}

		printf("image_view: %d case(s) failed\n", failures);
		[view release];
		[image release];
	}
	return failures != 0;
}
