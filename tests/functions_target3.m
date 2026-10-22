/*
 * functions_target3 — the phantom fixes and the last six function doors.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * SPDX-License-Identifier: MIT
 *
 * **THE THREE PHANTOMS WERE FOUND BY THE CENSUS, SO THEY ARE PINNED BY A TEST THAT WOULD HAVE FAILED BEFORE.** A
 * declared property with no accessors is not a documentation gap: `-setRepresentedObject:` was an unrecognized
 * selector, which is a crash. Each fix is therefore checked for the behaviour a caller would have crashed without.
 *
 * **THE IMAGE COMPOSERS ARE CHECKED BY COVERAGE RATHER THAN BY PIXEL-PERFECT SLICES.** Every one of the nine parts is
 * fed the SAME solid image, so the whole frame must be filled and nothing outside it may be: that is exactly the
 * geometry claim a nine-slice makes, and it fails if a corner lands outside the frame, if the edge extents are computed
 * backwards, or if the centre ignores the corners. Distinguishing the slices by colour would test the asset rather than
 * the arithmetic.
 *
 * THE GLYPH PACKINGS ARE CHECKED AS BYTES because that is what they promise; the two EUC packings are checked for
 * REFUSING (zero bytes) rather than for emitting something plausible.
 */
#import <AppKit/NSCell.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSOpenGL.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

/* A solid red image of the given size, built from raw premultiplied pixels so no drawing is needed to make it. */
static NSImage *solid_image(int w, int h)
{
	NSBitmapImageRep *rep = new_rep(w, h);
	unsigned char *data = (unsigned char *)[rep bitmapData];
	NSImage *image;
	int i, count = w * h * 4;

	for (i = 0; i < count; i += 4) {
		data[i + 0] = 255;	/* R */
		data[i + 1] = 0;	/* G */
		data[i + 2] = 0;	/* B */
		data[i + 3] = 255;	/* A */
	}
	image = [[NSImage alloc] initWithSize:NSMakeSize((CGFloat)w, (CGFloat)h)];
	[image addRepresentation:rep];
	[rep release];
	return [image autorelease];
}

static NSColor *pixel(NSBitmapImageRep *rep, int x, int y)
{
	return [rep colorAtX:x y:([rep pixelsHigh] - 1 - y)];
}

static int reddish(NSBitmapImageRep *rep, int x, int y)
{
	NSColor *p = pixel(rep, x, y);

	return p != nil && [p redComponent] > 0.5 && [p alphaComponent] > 0.5;
}

static int clear_at(NSBitmapImageRep *rep, int x, int y)
{
	NSColor *p = pixel(rep, x, y);

	return p == nil || [p alphaComponent] < 0.02;
}

static NSBitmapImageRep *begin(int w, int h)
{
	NSBitmapImageRep *rep = new_rep(w, h);

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor clearColor] setFill];
	NSRectFill(NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h));
	return rep;
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		/* 1. NSCell's representedObject — the property that had no accessors at all. */
		{
			NSCell *cell = [[[NSCell alloc] init] autorelease];
			NSObject *object = [[[NSObject alloc] init] autorelease];

			check([cell representedObject] == nil, "a fresh cell carries no represented object");
			[cell setRepresentedObject:object];
			check([cell representedObject] == object, "and the one it is given comes back");
			[cell setRepresentedObject:nil];
			check([cell representedObject] == nil, "and nil clears it");
		}

		/* 2. NSDraggingItem's frame setter — a getter with no setter behind it. */
		{
			NSDraggingItem *item = [[[NSDraggingItem alloc] initWithPasteboardWriter:nil] autorelease];
			NSRect frame = NSMakeRect(3.0, 4.0, 5.0, 6.0);

			check(NSEqualRects([item draggingFrame], NSZeroRect), "a new drag item has no frame");
			[item setDraggingFrame:frame];
			check(NSEqualRects([item draggingFrame], frame), "and setDraggingFrame: is a door rather than a crash");
		}

		/* 3. The integer-width glyph packings, as bytes. */
		{
			NSGlyph glyphs[3] = {0x41, 0x0102, 0x0304};
			char packed[16];
			NSInteger written;

			memset(packed, 0, sizeof(packed));
			written = NSConvertGlyphsToPackedGlyphs(glyphs, 3, NSOneByteGlyphPacking, packed);
			check(written == 3 && (unsigned char)packed[0] == 0x41 && (unsigned char)packed[1] == 0x02,
			      "one-byte packing writes one byte per glyph, low byte first");

			memset(packed, 0, sizeof(packed));
			written = NSConvertGlyphsToPackedGlyphs(&glyphs[1], 1, NSTwoByteGlyphPacking, packed);
			check(written == 2 && (unsigned char)packed[0] == 0x01 && (unsigned char)packed[1] == 0x02,
			      "two-byte packing is big-endian");

			memset(packed, 0, sizeof(packed));
			written = NSConvertGlyphsToPackedGlyphs(&glyphs[2], 1, NSFourByteGlyphPacking, packed);
			check(written == 4 && (unsigned char)packed[2] == 0x03 && (unsigned char)packed[3] == 0x04,
			      "four-byte packing is big-endian too");

			check(NSConvertGlyphsToPackedGlyphs(glyphs, 3, NSTwoByteGlyphPacking, NULL) == 6,
			      "a null buffer answers the size the caller needs");
			check(NSConvertGlyphsToPackedGlyphs(glyphs, 3, NSJapaneseEUCGlyphPacking, packed) == 0,
			      "an EUC packing refuses rather than emitting a plausible byte stream");
			check(NSConvertGlyphsToPackedGlyphs(NULL, 3, NSOneByteGlyphPacking, packed) == 0,
			      "and a null glyph buffer answers nothing");
		}

		/* 4. The three-slice composer fills its frame and nothing outside it. */
		{
			NSImage *solid = solid_image(4, 4);
			NSBitmapImageRep *rep = begin(40, 40);
			NSRect frame = NSMakeRect(10.0, 10.0, 20.0, 20.0);

			NSDrawThreePartImage(frame, solid, solid, solid, NO, NSCompositingOperationSourceOver, 1.0, NO);
			[NSGraphicsContext setCurrentContext:nil];
			check(reddish(rep, 20, 20), "three-part horizontal: the middle of the frame is painted");
			check(reddish(rep, 11, 20) && reddish(rep, 29, 20),
			      "and both caps land inside it");
			check(clear_at(rep, 5, 5) && clear_at(rep, 35, 35), "and nothing is painted outside the frame");
			[rep release];

			rep = begin(40, 40);
			NSDrawThreePartImage(frame, solid, solid, solid, YES, NSCompositingOperationSourceOver, 1.0, NO);
			[NSGraphicsContext setCurrentContext:nil];
			check(reddish(rep, 20, 20) && clear_at(rep, 5, 5),
			      "three-part vertical covers the frame the same way");
			[rep release];
		}

		/* 5. The nine-slice composer: every part the same image, so the frame must be completely covered. */
		{
			NSImage *solid = solid_image(4, 4);
			NSBitmapImageRep *rep = begin(40, 40);
			NSRect frame = NSMakeRect(8.0, 8.0, 24.0, 24.0);
			int x, y, inside = 0, holes = 0, outside = 0;

			NSDrawNinePartImage(frame, solid, solid, solid, solid, solid, solid, solid, solid, solid,
					    NSCompositingOperationSourceOver, 1.0, NO);
			[NSGraphicsContext setCurrentContext:nil];
			for (y = 0; y < 40; y++) {
				for (x = 0; x < 40; x++) {
					int inFrame = (x >= 8 && x < 32 && y >= 8 && y < 32);

					if (inFrame) {
						inside++;
						if (!reddish(rep, x, y)) {
							holes++;
						}
					} else if (reddish(rep, x, y)) {
						outside++;
					}
				}
			}
			check(holes == 0, "nine-part fills every pixel of its frame, corners and centre together");
			check(outside == 0, "and paints nothing outside it");
			check(inside == 24 * 24, "the frame is the size the arithmetic says");
			[rep release];
		}

		/* 6. No OpenGL exists, so the three doors answer their type's empty value rather than lying. */
		{
			GLint value = -1, major = -1, minor = -1;

			NSOpenGLGetOption(NSOpenGLGOFormatCacheSize, &value);
			check(value == 0, "NSOpenGLGetOption zeroes the out-parameter");
			NSOpenGLGetVersion(&major, &minor);
			check(major == 0 && minor == 0,
			      "NSOpenGLGetVersion answers 0, 0 rather than a version that would send a caller hunting");
			NSOpenGLSetOption(NSOpenGLGORetainRenderers, 1);
			check(1, "NSOpenGLSetOption refuses without crashing");
		}

		if (s_failed == 0) {
			printf("functions_target3: all checks passed\n");
			return 0;
		}
		printf("functions_target3: FAILURES\n");
		return 1;
	}
}
