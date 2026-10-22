/*
 * glyph_info_image_cell — NSGlyphInfo, NSImageCell, NSCollectionViewItem, and the three pasteboard protocols.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE GLYPH INFO'S CLAIM IS THAT A NAME RESOLVES THROUGH THE FACE OR NOT AT ALL.** The probe asks a real font for a glyph by
 * name (a name the face has, and one it has not), then checks the identifier pair and the base-string refusal. The
 * glyph-index factory is checked for the one documented gap: its `-glyphName` is nil because the engine here has no
 * glyph-to-name lookup.
 *
 * **THE IMAGE CELL'S CLAIM IS WHERE THE IMAGE LANDS**, so the probe renders it in each alignment and reads the pixels — a
 * stored alignment the drawing ignores would pass every value check and fail these.
 *
 * **AND THE PROTOCOLS ARE CHECKED BY CONFORMANCE**, which is the whole reason to declare them: `NSPasteboardItem` says it is
 * an `NSPasteboardWriting`, and the provider object says it is an `NSPasteboardItemDataProvider` — so the `@optional` methods
 * it answers are declared rather than guessed.
 */
#import <AppKit/NSGlyphInfo.h>
#import <AppKit/NSImageCell.h>
#import <AppKit/NSCollectionViewItem.h>
#import <AppKit/NSPasteboardItem.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSView.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

#define W 60
#define H 40

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
	NSRectFill(NSMakeRect(0.0, 0.0, w, h));
	image = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
	[image addRepresentation:rep];
	[rep release];
	return image;
}

/* THE EXTENT OF THE RED INK, in the bitmap's own rows (which run opposite to the drawing's). */
static void red_extent(NSBitmapImageRep *rep, int *minX, int *maxX, int *minY, int *maxY)
{
	int x, y;

	*minX = W; *maxX = -1; *minY = H; *maxY = -1;
	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4) {
				if (x < *minX) *minX = x;
				if (x > *maxX) *maxX = x;
				if (y < *minY) *minY = y;
				if (y > *maxY) *maxY = y;
			}
		}
	}
}

@interface AGProvider : NSObject <NSPasteboardItemDataProvider>
@end
@implementation AGProvider
- (void)pasteboard:(NSPasteboard *)board item:(NSPasteboardItem *)item provideDataForType:(NSString *)type
{
	(void)board;
	[item setData:[@"late" dataUsingEncoding:NSUTF8StringEncoding] forType:type];
}
@end

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE GLYPH INFO: a name that resolves, a name that does not, and the index gap.
		 * ========================================================================================== */
		{
			NSFont *font = [NSFont fontWithName:@"Helvetica" size:12.0];
			NSGlyphInfo *info;

			if (font == nil) {
				font = [NSFont systemFontOfSize:12.0];
			}
			/* A NAME THE FACE HAS. "A" is a glyph name in every PostScript-named font. */
			info = [NSGlyphInfo glyphInfoWithGlyphName:@"A" forFont:font baseString:@"A"];
			check(info != nil, "a glyph name the font has makes a glyph info");
			if (info != nil) {
				check([[info glyphName] isEqual:@"A"], "and the name comes back");
				check([info characterCollection] == NSIdentityMappingCharacterCollection,
				      "with the identity collection, which is what a by-name glyph means");
				check([info characterIdentifier] != 0, "and a glyph index as the identifier");
			}
			check([NSGlyphInfo glyphInfoWithGlyphName:@"no-such-glyph-name" forFont:font baseString:@"A"] == nil,
			      "a name the face has NOT got answers nil rather than .notdef");
			check([NSGlyphInfo glyphInfoWithGlyphName:@"A" forFont:font baseString:nil] == nil,
			      "and a nil base string answers nil, because the attribute could never apply");

			/* THE INDEX FACTORY: the name is the documented gap. */
			info = [NSGlyphInfo glyphInfoWithGlyph:36 forFont:font baseString:@"A"];
			check(info != nil && [info characterIdentifier] == 36 && [info glyphName] == nil,
			      "the index factory stores the index and has no name, which the header states");

			/* THE CHARACTER-COLLECTION FACTORY, which is a plain record. */
			info = [NSGlyphInfo glyphInfoWithCharacterIdentifier:1234
								collection:NSAdobeJapan1CharacterCollection
								baseString:@"あ"];
			check(info != nil && [info characterIdentifier] == 1234
				      && [info characterCollection] == NSAdobeJapan1CharacterCollection,
			      "a character identifier and its collection are stored and answered");
		}

		/* ============================================================================================
		 * 2. THE IMAGE CELL: the image lands where the ALIGNMENT says.
		 * ========================================================================================== */
		{
			NSImage *image = red_image(10.0, 10.0);
			NSImageCell *cell = [[NSImageCell alloc] init];
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, W, H)];

			[cell setImage:image];
			check([cell imageAlignment] == NSImageAlignLeft && [cell imageScaling] == NSImageScaleNone
				      && [cell imageFrameStyle] == NSImageFrameNone,
			      "the three facts start at Apple's defaults");

			/* NO SCALING, ALIGNED LEFT: the ink is at x 0..9, whatever the cell's height. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
				int minX, maxX, minY, maxY;

				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, W, H) inView:view];
				red_extent(rep, &minX, &maxX, &minY, &maxY);
				printf("  (note: left-aligned image at x %d..%d, y %d..%d)\n", minX, maxX, minY, maxY);
				check(minX == 0 && maxX == 9, "a left-aligned, unscaled image sits at the cell's left edge");
				[rep release];
			}

			/* ALIGNED RIGHT: the ink moves to the far edge. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
				int minX, maxX, minY, maxY;

				[cell setImageAlignment:NSImageAlignRight];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, W, H) inView:view];
				red_extent(rep, &minX, &maxX, &minY, &maxY);
				check(maxX == W - 1 && minX == W - 10, "a right-aligned image sits at the far edge");
				[rep release];
			}

			/* SCALED INDEPENDENTLY: it fills the cell. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
				int minX, maxX, minY, maxY;

				[cell setImageAlignment:NSImageAlignBottomLeft];
				[cell setImageScaling:NSImageScaleAxesIndependently];
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[cell drawWithFrame:NSMakeRect(0.0, 0.0, W, H) inView:view];
				red_extent(rep, &minX, &maxX, &minY, &maxY);
				check(minX == 0 && maxX == W - 1 && minY == 0 && maxY == H - 1,
				      "axes-independent scaling fills the cell, which is where a stored-and-ignored mode would fail");
				[rep release];
			}

			[cell release];
			[image release];
			[view release];
		}

		/* ============================================================================================
		 * 3. THE COLLECTION VIEW ITEM: two facts, and a redraw when the selection moves.
		 * ========================================================================================== */
		{
			NSCollectionViewItem *item = [[NSCollectionViewItem alloc] initWithNibName:nil bundle:nil];
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];

			[item setView:view];
			check([item collectionView] == nil, "an item starts with no collection view");
			check(![item isSelected], "and unselected");
			[item setSelected:YES];
			check([item isSelected], "a selection is stored");
			check([view needsDisplay], "and asks the tile to redraw, which is what a selection MEANS");
			[item release];
			[view release];
		}

		/* ============================================================================================
		 * 4. THE THREE PROTOCOLS, CHECKED AS CONFORMANCE.
		 * ========================================================================================== */
		{
			NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
			AGProvider *provider = [[AGProvider alloc] init];

			check([item conformsToProtocol:@protocol(NSPasteboardWriting)],
			      "the pasteboard item declares the writer protocol it implements");
			check([provider conformsToProtocol:@protocol(NSPasteboardItemDataProvider)],
			      "and a provider declares the provider protocol");

			/* THE OPTIONAL METHOD THE PROTOCOL DECLARES IS REACHABLE, which is what conformance buys. */
			[item setDataProvider:provider forTypes:[NSArray arrayWithObject:@"com.example.late"]];
			check([[item stringForType:@"com.example.late"] isEqual:@"late"],
			      "an item's provider is asked through the declared protocol");

			/* AND THE READER PROTOCOL EXISTS, with the class-method shape Apple's doors ask for. */
			/* **YES REQUIRED, NO INSTANCE** — the fourth argument is `isInstanceMethod`, and a reader's type list is a CLASS
			 * method; asking for the instance half finds nothing and would fail for the wrong reason. */
			check(protocol_getMethodDescription(@protocol(NSPasteboardReading),
							   @selector(readableTypesForPasteboard:), YES, NO).name != NULL,
			      "the reader protocol declares a REQUIRED class method, which is the sign a reader needs");
			[item release];
			[provider release];
		}

		if (failures == 0) {
			printf("glyph_info_image_cell: all checks passed\n");
			return 0;
		}
		printf("glyph_info_image_cell: FAILURES\n");
		return 1;
	}
}
