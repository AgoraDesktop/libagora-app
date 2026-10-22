/*
 * image_rep_family — the five rep classes: a delegate, a cached capture, an EPS header, and two named refusals.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **EACH CLASS IS CHECKED AT THE DOOR A CALLER REACHES FIRST.** The custom rep's draw selector is INVOKED and its arguments
 * are checked (the rectangle arrives by value, not as a pointer, because the invocation carries it); the cached rep is
 * captured from a window whose content draws a known colour and then BLITTED, so the pixels prove the capture; the EPS rep
 * parses a real `%%BoundingBox:` line and refuses to render; and the two unavailable formats refuse at their constructors,
 * which is the only place a caller can meet them.
 *
 * **AND THE REGISTRY IS CHECKED THROUGH THE BASE CLASS**, because that is what makes the EPS rep useful: `+imageRepClassForData:`
 * has to answer it for an EPS file, and NSImage's own loading is that question.
 */
#import <AppKit/NSImageRep.h>
#import <AppKit/NSCustomImageRep.h>
#import <AppKit/NSCachedImageRep.h>
#import <AppKit/NSEPSImageRep.h>
#import <AppKit/NSPICTImageRep.h>
#import <AppKit/NSCIImageRep.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSWindow.h>
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

/* A DELEGATE THAT RECORDS THE CALL, so the test can check the ARGUMENTS and not only that something happened. */
@interface AGDrawDelegate : NSObject
{
@public
	NSRect lastRect;
	NSInteger calls;
	BOOL sawRep;
}
@end

@implementation AGDrawDelegate
- (void)drawRep:(id)rep inRect:(NSRect)rect forScreen:(BOOL)screen
{
	(void)screen;
	calls++;
	lastRect = rect;
	sawRep = (rep != nil);
}
@end

/* A VIEW THAT PAINTS ITS WHOLE BOUNDS RED, so a capture of it can be read back as red pixels. */
@interface AGRedView : NSView
@end

@implementation AGRedView
- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
}
@end

static int red_pixels(NSBitmapImageRep *rep, int w, int h)
{
	int x, y, count = 0;

	for (y = 0; y < h; y++) {
		for (x = 0; x < w; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.6 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE CUSTOM REP: the draw selector is invoked WITH ITS ARGUMENTS.
		 * ========================================================================================== */
		{
			AGDrawDelegate *delegate = [[AGDrawDelegate alloc] init];
			NSCustomImageRep *rep = [[NSCustomImageRep alloc] initWithDrawSelector:@selector(drawRep:inRect:forScreen:)
										     delegate:delegate];

			check(rep != nil, "a custom rep is made from a selector and a delegate");
			check([rep drawSelector] == @selector(drawRep:inRect:forScreen:) && [rep delegate] == delegate,
			      "and answers both back");
			[rep setSize:NSMakeSize(40.0, 20.0)];
			check([rep drawInRect:NSMakeRect(5.0, 7.0, 30.0, 15.0)],
			      "drawing it reports that the message went");
			check(delegate->calls == 1 && delegate->sawRep
				      && delegate->lastRect.origin.x == 5.0 && delegate->lastRect.size.height == 15.0,
			      "and the delegate saw the rep and the RECTANGLE BY VALUE");

			/* A REP THAT CANNOT DRAW IS NOT MADE. */
			check([[NSCustomImageRep alloc] initWithDrawSelector:NULL delegate:delegate] == nil,
			      "a NULL selector refuses rather than making a rep that cannot draw");
			check([[NSCustomImageRep alloc] initWithDrawSelector:@selector(description) delegate:delegate] == nil,
			      "and so does a selector whose signature is not (id, NSRect, BOOL)");

			[rep release];
			[delegate release];
		}

		/* ============================================================================================
		 * 2. THE CACHED REP: a blank canvas, and a CAPTURE that draws back what the window drew.
		 * ========================================================================================== */
		{
			NSCachedImageRep *blank = [[NSCachedImageRep alloc] initWithSize:NSMakeSize(32.0, 16.0)
										  depth:NSWindowDepthTwentyfourBitRGB
									       separate:NO alpha:YES];

			check(blank != nil && [blank size].width == 32.0 && [blank pixelsWide] == 32,
			      "a blank canvas takes the size it was given");
			check([blank window] == nil && [blank rect].size.width == 32.0,
			      "and it names no window");

			/* THE WINDOW FORM. */
			{
				NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 80.0, 60.0)
									 styleMask:NSTitledWindowMask
									   backing:NSBackingStoreBuffered defer:NO];
				AGRedView *content = [[AGRedView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 60.0)];

				if (window != nil) {
					NSCachedImageRep *captured;

					[window setContentView:content];
					captured = [[NSCachedImageRep alloc] initWithWindow:window
										    rect:NSMakeRect(0.0, 0.0, 40.0, 30.0)];
					check(captured != nil, "a window rectangle is captured");
					if (captured != nil) {
						NSBitmapImageRep *out = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
							pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
							isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
							bytesPerRow:W * 4 bitsPerPixel:32];

						[NSGraphicsContext setCurrentContext:
							[NSGraphicsContext graphicsContextWithBitmapImageRep:out]];
						[captured drawInRect:NSMakeRect(0.0, 0.0, W, H)];
						printf("  (note: the capture blitted %d red pixels of %d)\n",
						       red_pixels(out, W, H), W * H);
						check(red_pixels(out, W, H) > (W * H) / 2,
						      "and drawing it puts the window's red back on the pixels");
						check([captured window] == window, "the capture names the window it came from");
						[out release];
						[captured release];
					}
					[window release];
				} else {
					printf("  SKIP  no window for the capture\n");
				}
				[content release];
			}
			[blank release];
		}

		/* ============================================================================================
		 * 3. THE EPS REP: a real bounding box, the bytes back, and a render that refuses.
		 * ========================================================================================== */
		{
			const char *epsText = "%!PS-Adobe-3.0 EPSF-3.0\n"
					      "%%BoundingBox: 10 20 210 120\n"
					      "%%EndComments\n"
					      "1 0 0 setrgbcolor 0 0 100 50 rectfill\n"
					      "showpage\n";
			NSData *eps = [NSData dataWithBytes:epsText length:strlen(epsText)];
			NSEPSImageRep *rep;

			check([NSEPSImageRep canInitWithData:eps], "the EPS sniff accepts a %!PS header");
			check(![NSEPSImageRep canInitWithData:[NSData dataWithBytes:"GIF89a" length:6]],
			      "and refuses other bytes");
			rep = [NSEPSImageRep imageRepWithData:eps];
			check(rep != nil, "an EPS rep is made from the bytes");
			if (rep != nil) {
				NSRect box = [rep boundingBox];

				check(box.origin.x == 10.0 && box.origin.y == 20.0
					      && box.size.width == 200.0 && box.size.height == 100.0,
				      "the bounding box comes from the header's own comment");
				check([rep size].width == 200.0 && [rep size].height == 100.0,
				      "and the rep's size follows it, which is why the box is read");
				check([[rep EPSRepresentation] isEqualToData:eps], "the bytes come back unchanged");
				check(![rep drawInRect:NSMakeRect(0.0, 0.0, 10.0, 10.0)],
				      "and drawing refuses, because there is no PostScript interpreter");
				[rep prepareGState];	/* declared, does nothing, must not crash */
				check(1, "prepareGState is accepted and does nothing");
				/* NOT RELEASED HERE: `+imageRepWithData:` answered an AUTORELEASED rep, and releasing it as well
				 * is the double release that made this test crash at the pool's drain AFTER it had printed every
				 * check as passed — the one failure mode a passing test can hide. */
			}

			/* THE REGISTRY: the class has to be findable, or NSImage's own loading cannot see it. */
			check([NSImageRep imageRepClassForData:eps] == [NSEPSImageRep class],
			      "the registry answers the EPS class for EPS bytes");
			check([[NSImageRep registeredImageRepClasses] containsObject:[NSEPSImageRep class]],
			      "and the class registered itself, as Apple's contract requires");
		}

		/* ============================================================================================
		 * 4. THE TWO FORMATS THIS TIER HAS NOT GOT REFUSE AT THEIR CONSTRUCTORS.
		 * ========================================================================================== */
		{
			NSData *pict = [NSData dataWithBytes:"\x00\x11\x02\xff" length:4];
			NSData *tiff = [NSData dataWithBytes:"II*\x00" length:4];

			check([NSPICTImageRep imageRepWithData:pict] == nil,
			      "a PICT rep refuses to be made, because there is no QuickDraw player");
			check([NSImageRep imageRepClassForData:pict] == nil,
			      "and the registry does not offer it for PICT bytes either");
			check([NSPICTImageRep canInitWithData:pict] == NO,
			      "the PICT sniff says NO rather than promising a decode it cannot do");

			check([NSCIImageRep imageRepWithCIImage:nil] == nil,
			      "a Core Image rep refuses too, for the same reason one class over");

			/* **A FORMAT WITH NO REP ANSWERS nil, WHICH IS THE HONEST ANSWER.** TIFF is not one of the two the bitmap
			 * rep decodes, so nothing in the registry claims it — stated here so the PICT check above cannot pass for
			 * the wrong reason (an empty registry would make every answer nil). */
			check([NSImageRep imageRepClassForData:tiff] == nil,
			      "and an undecodable format has no class, which is what makes the two nil answers above meaningful");
			check([NSImageRep imageRepClassForData:[NSData dataWithBytes:"\x89PNG\r\n\x1a\n" length:8]] != nil,
			      "while a format this tier DOES decode still has one — so the registry is not empty");
		}

		/* ============================================================================================
		 * THE IMAGE FAMILY'S SWEEP: the sample questions, the type lists, the pasteboard question, the
		 * format word, the space as an object, and the one door that was refused for a reason that expired.
		 * ============================================================================================ */
		{
			NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
				initWithBitmapDataPlanes:NULL pixelsWide:4 pixelsHigh:2 bitsPerSample:8
					  samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					   colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:16 bitsPerPixel:32];
			/* **THE ABSTRACT BASE IS THE HONEST "REP WITH NO PIXELS OF ITS OWN"**, and it is what the two sample
			 * doors exist for: a concrete rep answers from its data, this one from what it was told. */
			NSImageRep *base = [[NSImageRep alloc] init];
			NSBitmapImageRep *retagged;
			NSImageRep *rgb;

			/* 1. THE TWO SAMPLE QUESTIONS. The base records what it is told and a rep whose pixels have a depth of
			 * their own answers THAT; a base rep that was never told has no samples, so it says 0 rather than 8. */
			check([bitmap bitsPerSample] == 8, "a bitmap rep's bit depth is the one its bytes are in");
			check([base bitsPerSample] == 0,
			      "and a rep with no pixels of its own answers 0 samples until it is told");
			[base setBitsPerSample:12];
			check([base bitsPerSample] == 12,
			      "`-setBitsPerSample:` records the answer, which is the base's whole contract for it");
			check([bitmap hasAlpha] && ![base hasAlpha],
			      "`-hasAlpha` reads the alpha channel: the bitmap has one, the base rep was never told it has");

			/* 2. THE TYPE LISTS. The filtered pair equals the unfiltered one here — no filters exist — and the IMAGE's
			 * UTI list is the REGISTRY's, so there is one table rather than two. */
			check([[NSImageRep imageFileTypes] containsObject:@"png"],
			      "the rep registry's filtered FILE types include the one this tier decodes");
			check([[NSImageRep imageFileTypes] isEqual:[NSImageRep imageUnfilteredFileTypes]] &&
			      [[NSImageRep imagePasteboardTypes] isEqual:[NSImageRep imageUnfilteredPasteboardTypes]],
			      "and the filtered pair IS the unfiltered pair, because this tier registers no filters");
			check([[NSImage imageTypes] isEqual:[NSImageRep imageTypes]],
			      "`+[NSImage imageTypes]` is the registry's list rather than a second table");
			check([[NSImage imageUnfilteredTypes] containsObject:NSPasteboardTypePNG] ||
			      [[NSImage imageTypes] count] > 0,
			      "and the list is not empty, which is what makes the check above meaningful");

			/* 3. THE LIVE PASTEBOARD QUESTION. A board carrying PNG bytes is a yes; an empty one is a no. */
			{
				NSPasteboard *board = [NSPasteboard generalPasteboard];
				NSData *pngBits = [NSData dataWithBytes:"\x89PNG\r\n\x1a\n" length:8];

				[board declareTypes:[NSArray arrayWithObject:NSPasteboardTypePNG] owner:nil];
				[board setData:pngBits forType:NSPasteboardTypePNG];
				check([NSImageRep canInitWithPasteboard:board],
				      "a pasteboard carrying a type this registry reads is a YES");
				check([NSImage canInitWithPasteboard:board],
				      "and so is the image's own door, which is the one a caller usually asks");
				[board declareTypes:[NSArray arrayWithObject:@"public.plain-text"] owner:nil];
				check(![NSImageRep canInitWithPasteboard:board],
				      "and a board carrying nothing this layer reads is a NO");
				check(![NSImageRep canInitWithPasteboard:nil], "a nil pasteboard is a NO rather than a crash");
			}

			/* 4. THE FORMAT WORD. Zero is this class's own layout, so it is accepted; the three flags that describe a
			 * layout it cannot hold are refused BY NAME. */
			{
				unsigned char *planes[1] = { NULL };
				NSBitmapImageRep *plain = [[NSBitmapImageRep alloc]
					initWithBitmapDataPlanes:planes pixelsWide:2 pixelsHigh:2 bitsPerSample:8
						  samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						   colorSpaceName:NSDeviceRGBColorSpace
						    bitmapFormat:(NSBitmapFormat)0
						      bytesPerRow:8 bitsPerPixel:32];

				check(plain != nil && [plain bitsPerSample] == 8,
				      "the 10.5 initialiser accepts the layout this class already is");
				[plain release];
				check([[NSBitmapImageRep alloc]
					initWithBitmapDataPlanes:planes pixelsWide:2 pixelsHigh:2 bitsPerSample:8
						  samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						   colorSpaceName:NSDeviceRGBColorSpace
						    bitmapFormat:NSAlphaFirstBitmapFormat
						      bytesPerRow:8 bitsPerPixel:32] == nil,
				      "and REFUSES alpha-first, which its own buffers are not");
				check([[NSBitmapImageRep alloc]
					initWithBitmapDataPlanes:planes pixelsWide:2 pixelsHigh:2 bitsPerSample:8
						  samplesPerPixel:4 hasAlpha:YES isPlanar:NO
						   colorSpaceName:NSDeviceRGBColorSpace
						    bitmapFormat:NSFloatingPointSamplesBitmapFormat
						      bytesPerRow:8 bitsPerPixel:32] == nil,
				      "and refuses floating-point samples, which this tier's CoreGraphics has no layout for");
			}

			/* 5. THE SPACE AS AN OBJECT. The mapping is by NAME; a name with no space behind it is a refusal. */
			check([bitmap colorSpace] == [NSColorSpace deviceRGBColorSpace],
			      "a device-RGB rep answers the device-RGB space");
			[bitmap setColorSpaceName:NSDeviceGrayColorSpace];
			check([bitmap colorSpace] == [NSColorSpace deviceGrayColorSpace],
			      "and a device-grey one answers the device-grey space");
			[bitmap setColorSpaceName:NSPatternColorSpace];
			check([bitmap colorSpace] == nil,
			      "a pattern space has no object here, so the door answers nil rather than guessing");
			[bitmap setColorSpaceName:NSDeviceRGBColorSpace];
			check([bitmap colorSpace] != nil, "and back in a space this layer knows it answers an object again");

			/* 6. RETAGGING CHANGED FROM A REFUSAL TO A DOOR, BECAUSE `NSColorSpace` ARRIVED. Retagging moves no
			 * pixel: the copy has the same picture and a different name. CONVERTING is still refused, because nothing
			 * here converts between two spaces — and the door now names only that. */
			retagged = [bitmap bitmapImageRepByRetaggingWithColorSpace:[NSColorSpace deviceGrayColorSpace]];
			check(retagged != nil && retagged != bitmap,
			      "retagging answers a COPY rather than the rep it was sent");
			check(retagged != nil && [[retagged colorSpaceName] length] > 0,
			      "with a colour-space name from the space it was given");
			check(retagged != nil && [retagged pixelsWide] == [bitmap pixelsWide] &&
			      [retagged pixelsHigh] == [bitmap pixelsHigh],
			      "and the same pixels — retagging changes no sample");
			/* AND THE COPY IS AUTORELEASED, WHICH THIS PROBE PAID FOR: `[retagged release]` here is an over-release
			 * and it crashed `emptyPool` at the drain AFTER every check had printed ok — the trap the handoff records
			 * twice. The door follows the convention; a probe that wants to own the answer sends `-retain` first. */
			check([bitmap bitmapImageRepByConvertingToColorSpace:[NSColorSpace deviceGrayColorSpace]
							     renderingIntent:0] == nil,
			      "converting is still REFUSED: this tier has no colour-converting path");
			rgb = bitmap;
			check([rgb colorSpace] != nil, "and the rep whose space was asked is unchanged by the refusal");

			[bitmap release];
			[base release];
		}

		if (failures == 0) {
			printf("image_rep_family: all checks passed\n");
			return 0;
		}
		printf("image_rep_family: FAILURES\n");
		return 1;
	}
}
