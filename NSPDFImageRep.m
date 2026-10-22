/*
 * NSPDFImageRep — a PDF document as a rep, with its pages and the vector drawing route.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE DOCUMENT IS THE STATE.** The bytes are retained, `CGPDFDocument` parses them once, and every page-sized
 * question (`-pageCount`, `-bounds`, `-setCurrentPage:`) is asked of it. Nothing here re-parses or copies the
 * file, and the rep does not own a pixel buffer until something asks for `-CGImage`.
 *
 * **THE VECTOR ROUTE IS THE REAL ONE.** `-drawInRect:` maps the current page's crop box into the destination
 * rectangle with `CGPDFPageGetDrawingTransform` and calls `CGContextDrawPDFPage`, so the page is drawn at the
 * destination's resolution rather than sampled from a bitmap. THE MIRROR IS THE ONE `NSImageRep`'s own draw has
 * to do: a page is y-up and a flipped destination is y-down, so the y-down case gets a local flip before the
 * page transform; `NSImageRep.m` states the same rule for its CGImage route, and the pair are checked together
 * by `tests/pdf_app.m`.
 *
 * **-CGImage RENDERS THE CURRENT PAGE**, because the base class's single-image seam has nowhere else to go: it
 * is the answer for `NSImage`'s cache and for any consumer that wants pixels. It is deliberately the fallback.
 */
#import <AppKit/NSPDFImageRep.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPasteboard.h>

#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGPDFPage.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@implementation NSPDFImageRep

+ (void)initialize
{
	if (self == [NSPDFImageRep class]) {
		[NSImageRep registerImageRepClass:self];
	}
}

+ (BOOL)canInitWithData:(NSData *)data
{
	const unsigned char *b = data != nil ? (const unsigned char *)[data bytes] : NULL;

	return b != NULL && [data length] >= 5 && memcmp(b, "%PDF-", 5) == 0;
}

+ (NSArray *)imageUnfilteredFileTypes
{
	return [NSArray arrayWithObject:@"pdf"];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	return [NSArray arrayWithObject:NSPDFPboardType];
}

+ (NSArray *)imageUnfilteredTypes
{
	return [self imageUnfilteredFileTypes];
}

+ (NSArray *)imageTypes
{
	return [self imageUnfilteredTypes];
}

+ (nullable instancetype)imageRepWithData:(nullable NSData *)pdfData
{
	return [[[self alloc] initWithData:pdfData] autorelease];
}

- (nullable instancetype)initWithData:(nullable NSData *)pdfData
{
	CGDataProviderRef provider;
	CGPDFDocumentRef document;
	CGPDFPageRef page;

	if (pdfData == nil || [pdfData length] < 5 ||
	    memcmp([pdfData bytes], "%PDF-", 5) != 0) {
		fprintf(stderr, "APPKIT-REFUSE: NSPDFImageRep needs PDF bytes (the header says so)\n");
		[self release];
		return nil;
	}
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_data = [pdfData copy];
	/* THE PROVIDER BORROWS THE RETAINED BYTES, and the document copies what it needs out of them — so the
	 * provider is released here and the rep's own `_data` is what keeps the buffer alive. */
	provider = CGDataProviderCreateWithData(NULL, [_data bytes], (size_t)[_data length], NULL);
	if (provider == NULL) {
		[self release];
		return nil;
	}
	document = CGPDFDocumentCreateWithProvider(provider);
	CGDataProviderRelease(provider);
	if (document == NULL || CGPDFDocumentGetNumberOfPages(document) == 0) {
		if (document != NULL) {
			CGPDFDocumentRelease(document);
		}
		fprintf(stderr, "APPKIT-REFUSE: NSPDFImageRep could not read a page from these PDF bytes\n");
		[self release];
		return nil;
	}
	_document = document;
	_currentPage = 0;
	_cachePage = -1;
	page = CGPDFDocumentGetPage(_document, 1);
	{
		CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);

		if (box.size.width <= 0 || box.size.height <= 0) {
			box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
		}
		[self setSize:NSMakeSize(box.size.width, box.size.height)];
		[self setPixelsWide:(NSInteger)ceil(box.size.width)];
		[self setPixelsHigh:(NSInteger)ceil(box.size.height)];
		[self setColorSpaceName:NSDeviceRGBColorSpace];
		[self setAlpha:YES];
	}
	return self;
}

- (void)dealloc
{
	if (_cachedImage != NULL) {
		CGImageRelease(_cachedImage);
	}
	free(_cacheBytes);
	if (_document != NULL) {
		CGPDFDocumentRelease(_document);
	}
	[_data release];
	[super dealloc];
}

- (NSInteger)pageCount
{
	return _document != NULL ? (NSInteger)CGPDFDocumentGetNumberOfPages(_document) : 0;
}

- (NSInteger)currentPage
{
	return _currentPage;
}

- (void)setCurrentPage:(NSInteger)page
{
	NSInteger count = [self pageCount];

	if (count <= 0) {
		return;
	}
	if (page < 0) {
		page = 0;
	}
	if (page >= count) {
		page = count - 1;
	}
	if (page == _currentPage) {
		return;
	}
	_currentPage = page;
	/* THE RENDERED FALLBACK IS THE PAGE IT WAS MADE FROM; the VECTOR route reads `_currentPage` per draw and
	 * needs no invalidation. */
	if (_cachedImage != NULL) {
		CGImageRelease(_cachedImage);
		_cachedImage = NULL;
	}
	free(_cacheBytes);
	_cacheBytes = NULL;
	_cachePage = -1;
}

- (NSRect)bounds
{
	return NSMakeRect(0.0, 0.0, [self size].width, [self size].height);
}

- (BOOL)drawInRect:(NSRect)rect
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg;
	CGPDFPageRef page;
	CGAffineTransform ctm;
	CGAffineTransform page_transform;

	if (context == nil || _document == NULL || rect.size.width <= 0.0 || rect.size.height <= 0.0) {
		return NO;
	}
	cg = [context CGContext];
	if (cg == NULL) {
		return NO;
	}
	page = CGPDFDocumentGetPage(_document, (size_t)_currentPage + 1);
	if (page == NULL) {
		return NO;
	}
	ctm = CGContextGetCTM(cg);
	/* **WHICH WAY IS DOWN IN THE CALLER'S USER SPACE?** The sign of the CTM's `d` alone cannot say it: a
	 * bitmap's device y runs DOWN and its default user y runs UP (`d < 0`), while a PDF page's device y runs
	 * UP, so the same `d < 0` there means a y-down user space. `CGBitmapContextGetData` answers whether this
	 * context has a surface — NULL for the PDF context — and that, with the sign, is the pair that decides.
	 * A y-down user space gets the page flipped into `rect` so its top is at the caller's top; a y-up one gets
	 * the page transform directly. MEASURED by tests/pdf_app.m, which checks both the bitmap and the PDF case. */
	{
		bool device_y_down = CGBitmapContextGetData(cg) != NULL;
		bool user_y_down = device_y_down ? (ctm.d > 0.0) : (ctm.d < 0.0);

		CGContextSaveGState(cg);
		if (user_y_down) {
			CGContextTranslateCTM(cg, rect.origin.x, rect.origin.y + rect.size.height);
			CGContextScaleCTM(cg, 1.0, -1.0);
			page_transform = CGPDFPageGetDrawingTransform(page, kCGPDFCropBox,
								      CGRectMake(0.0, 0.0, rect.size.width,
										 rect.size.height),
								      0, true);
		} else {
			page_transform = CGPDFPageGetDrawingTransform(page, kCGPDFCropBox, NSRectToCGRect(rect),
								      0, true);
		}
	}
	CGContextConcatCTM(cg, page_transform);
	CGContextDrawPDFPage(cg, page);
	CGContextRestoreGState(cg);
	return YES;
}

- (CGImageRef)CGImage
{
	CGPDFPageRef page;
	CGRect box;
	size_t width;
	size_t height;
	CGColorSpaceRef space;
	CGContextRef cg;
	CGAffineTransform transform;

	if (_document == NULL) {
		return NULL;
	}
	if (_cachedImage != NULL && _cachePage == _currentPage) {
		return _cachedImage;
	}
	if (_cachedImage != NULL) {
		CGImageRelease(_cachedImage);
		_cachedImage = NULL;
	}
	free(_cacheBytes);
	_cacheBytes = NULL;
	page = CGPDFDocumentGetPage(_document, (size_t)_currentPage + 1);
	if (page == NULL) {
		return NULL;
	}
	box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
	if (box.size.width <= 0 || box.size.height <= 0) {
		box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
	}
	width = (size_t)ceil(box.size.width);
	height = (size_t)ceil(box.size.height);
	if (width == 0 || height == 0) {
		return NULL;
	}
	/* THE BUFFER IS THE REP'S, KEPT BESIDE THE IMAGE: this library's CGBitmapContextCreateImage may hand the
	 * image a provider over these bytes rather than a copy, so freeing the buffer with the context would be a
	 * dangling picture. */
	_cacheBytes = calloc(height, width * 4);
	if (_cacheBytes == NULL) {
		return NULL;
	}
	space = CGColorSpaceCreateDeviceRGB();
	cg = CGBitmapContextCreate(_cacheBytes, width, height, 8, width * 4, space,
				   kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	CGColorSpaceRelease(space);
	if (cg == NULL) {
		free(_cacheBytes);
		_cacheBytes = NULL;
		return NULL;
	}
	transform = CGPDFPageGetDrawingTransform(page, kCGPDFCropBox,
						 CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), 0, true);
	CGContextConcatCTM(cg, transform);
	CGContextDrawPDFPage(cg, page);
	_cachedImage = CGBitmapContextCreateImage(cg);
	CGContextRelease(cg);
	_cachePage = _currentPage;
	return _cachedImage;
}

- (NSData *)PDFRepresentation
{
	return _data;
}

@end
