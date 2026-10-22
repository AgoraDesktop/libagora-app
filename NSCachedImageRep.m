/*
 * NSCachedImageRep — the rep for a region already rendered.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * Both shapes end at one JPEG-free bitmap rep, and the base class's `-CGImage` blit does the drawing. The window form
 * renders its rectangle ONCE, through the view's own `-cacheDisplayInRect:toBitmapImageRep:`, which is the same path
 * `tests/image_draw.m` and the control probes use — so the rep cannot disagree with what the window drew.
 */
#import "NSCachedImageRep.h"
#import "NSBitmapImageRep.h"
#import "NSWindow.h"
#import "NSView.h"
#import "AppKitRefusal.h"

@implementation NSCachedImageRep

/* **A BLANK CANVAS IN THE DEPTH ASKED FOR.** `NSWindowDepth` packs bits-per-sample and alpha, and the two doors that read
 * it are the same ones `+[NSBitmapImageRep bitmapRepWithDepth:]`-shaped code would use; the bitmap is 32-bit RGBA when the
 * depth says alpha and 24-bit RGB otherwise. `separate` is a window-server detail with no meaning here — the buffer is
 * always this process's own — and is accepted for compatibility. */
- (instancetype)initWithSize:(NSSize)size depth:(NSWindowDepth)depth separate:(BOOL)separate alpha:(BOOL)alpha
{
	NSBitmapImageRep *bitmap;
	NSInteger samples = alpha ? 4 : 3;

	(void)depth;
	(void)separate;
	bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
							 pixelsWide:(NSInteger)size.width
							 pixelsHigh:(NSInteger)size.height
							  bitsPerSample:8 samplesPerPixel:samples hasAlpha:alpha
							   isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
							    bytesPerRow:(NSInteger)size.width * samples bitsPerPixel:8 * samples];
	if (bitmap == nil) {
		[self release];
		return nil;
	}
	self = [super init];
	if (self != nil) {
		_bitmap = bitmap;	/* OWNED */
		_window = nil;
		_rect = NSMakeRect(0.0, 0.0, size.width, size.height);
		[self setSize:size];
		[self setPixelsWide:(NSInteger)size.width];
		[self setPixelsHigh:(NSInteger)size.height];
		[self setAlpha:alpha];
		return self;
	}
	[bitmap release];
	return nil;
}

/* **THE CAPTURE, TAKEN NOW.** The rectangle is in the window's base coordinates and the capture renders through the content
 * view, so a title bar's rectangle is outside what a view can draw — which is the same limitation Apple's own cache has in
 * a compositing world, and it is stated rather than papered over. */
- (instancetype)initWithWindow:(NSWindow *)window rect:(NSRect)rect
{
	NSView *content;
	NSBitmapImageRep *bitmap;

	if (window == nil || NSIsEmptyRect(rect)) {
		fn_refuse_window("-NSCachedImageRep -initWithWindow:rect:",
				 "a window and a non-empty rectangle; one of them is missing");
		[self release];
		return nil;
	}
	content = [window contentView];
	if (content == nil) {
		[self release];
		return nil;
	}
	bitmap = [content bitmapImageRepForCachingDisplayInRect:rect];
	if (bitmap == nil) {
		[self release];
		return nil;
	}
	[content cacheDisplayInRect:rect toBitmapImageRep:bitmap];
	self = [super init];
	if (self != nil) {
		_bitmap = [bitmap retain];
		_window = window;	/* NOT RETAINED */
		_rect = rect;
		[self setSize:rect.size];
		[self setPixelsWide:[bitmap pixelsWide]];
		[self setPixelsHigh:[bitmap pixelsHigh]];
		[self setAlpha:[bitmap hasAlpha]];
		[self setColorSpaceName:[bitmap colorSpaceName]];
		return self;
	}
	return nil;
}

- (void)dealloc
{
	[_bitmap release];
	[super dealloc];
}

- (NSWindow *)window
{
	return _window;
}

- (NSRect)rect
{
	return _rect;
}

/* **THE PIXELS ARE THE BITMAP'S.** All three drawing doors on the base class go through `-CGImage`, so answering it is the
 * whole of this class's drawing — and it is why a cached rep needs no draw code of its own. */
- (CGImageRef)CGImage
{
	return (_bitmap != nil) ? [_bitmap CGImage] : NULL;
}

- (BOOL)drawInRect:(NSRect)rect
{
	return [super drawInRect:rect];
}

- (BOOL)draw
{
	return [super draw];
}

@end
