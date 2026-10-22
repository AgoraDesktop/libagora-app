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

		if (failures == 0) {
			printf("image_rep_family: all checks passed\n");
			return 0;
		}
		printf("image_rep_family: FAILURES\n");
		return 1;
	}
}
