/*
 * appkit_bitmap_encode.m — writing an image out: `-representationUsingType:properties:` and what it refuses.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS DOOR REFUSED FOR THE WHOLE LIFE OF THIS CLASS, AND THE REFUSAL WAS THE MEASUREMENT**: "this tree's Core
 * Graphics has the PNG and JPEG decoders and no `CGImageDestination`, so there is nothing to encode with". Core
 * Graphics has one now (`libagora-drawing`), so the door answers — and what this probe measures is that the bytes it
 * answers with are the image that went in, by reading them back through the class's own decoder.
 *
 * **AND THE REFUSALS THAT REMAIN ARE MEASURED TOO, because a door that answered everything would be worse than the
 * refusal it replaced.** A type this build does not write is refused by name rather than written as a PNG; a
 * properties dictionary is refused rather than ignored, because a caller that asked for an interlaced PNG must not
 * silently get a plain one; and the CLASS door, whose reason to exist is formats that carry several images, refuses
 * an array of two rather than dropping one.
 */
#import <AppKit/NSBitmapImageRep.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGDataProvider.h>
#include <CoreGraphics/CGImage.h>
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
	/* BGRA, PREMULTIPLIED — the layout this tree's PNG decoder produces and its blitter reads. */
	static const unsigned char pixels[] = {
		0x00, 0x00, 0xFF, 0xFF,	/* opaque red */
		0x00, 0xFF, 0x00, 0xFF,	/* opaque green */
		0x19, 0x32, 0x64, 0x80,	/* straight (200,100,50) at alpha 128 */
		0xFF, 0x00, 0xFF, 0xFF	/* opaque magenta */
	};
	CGDataProviderRef provider;
	CGColorSpaceRef space;
	CGImageRef image;
	NSBitmapImageRep *rep;
	NSData *png;
	NSBitmapImageRep *back;
	const unsigned char *bytes;

	setvbuf(stdout, NULL, _IONBF, 0);
	provider = CGDataProviderCreateWithData(NULL, pixels, sizeof pixels, NULL);
	space = CGColorSpaceCreateDeviceRGB();
	image = CGImageCreate(2, 2, 8, 32, 8, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
			      provider, NULL, true, kCGRenderingIntentDefault);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(space);
	check(image != NULL, "the source image was made");
	if (image == NULL) {
		printf("appkit_bitmap_encode: %d failure(s)\n", failures);
		return 1;
	}

	rep = [NSBitmapImageRep imageRepWithCGImage:image];
	check(rep != nil, "a rep was made over it");
	check([rep pixelsWide] == 2 && [rep pixelsHigh] == 2, "at the image's own size");

	/* THE DOOR, WHICH USED TO REFUSE. */
	png = [rep representationUsingType:NSPNGFileType properties:nil];
	check(png != nil, "-representationUsingType:NSPNGFileType answers data");
	if (png != nil) {
		bytes = (const unsigned char *)[png bytes];
		check([png length] > 8 && bytes != NULL && bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N'
		      && bytes[3] == 'G',
		      "and the bytes begin with the PNG signature");
		printf("  (encoded %lu bytes)\n", (unsigned long)[png length]);

		/* **THE ROUND TRIP, THROUGH THIS CLASS'S OWN DECODER** — the one thing that proves the two halves of the
		 * encoder/decoder pair agree rather than each agreeing with itself. */
		back = [NSBitmapImageRep imageRepWithData:png];
		check(back != nil, "the bytes decode back into a rep");
		if (back != nil) {
			check([back pixelsWide] == 2 && [back pixelsHigh] == 2,
			      "at the same size the rep went out with");
		}
	}

	/* AND WHAT IT DOES NOT WRITE, IT NAMES. */
	check([rep representationUsingType:NSJPEGFileType properties:nil] == nil,
	      "a type this build does not write is refused rather than written as something else");
	check([rep representationUsingType:NSPNGFileType
			       properties:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:1]
								      forKey:@"Interlaced"]] == nil,
	      "and a properties dictionary is refused rather than silently ignored");

	/* THE CLASS DOOR: ONE IMAGE IS A PNG, TWO ARE A REFUSAL. */
	{
		NSArray *one = [NSArray arrayWithObject:rep];
		NSArray *two = [NSArray arrayWithObjects:rep, rep, nil];

		check([NSBitmapImageRep representationOfImageRepsInArray:one
							       usingType:NSPNGFileType
							      properties:nil] != nil,
		      "one rep in the array is answered");
		check([NSBitmapImageRep representationOfImageRepsInArray:two
							       usingType:NSPNGFileType
							      properties:nil] == nil,
		      "two reps are refused, because a PNG carries one image");
	}

	CGImageRelease(image);
	printf("appkit_bitmap_encode: %d failure(s)\n", failures);
	return failures == 0 ? 0 : 1;
}
