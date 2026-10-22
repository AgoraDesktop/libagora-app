/*
 * NSPDFImageRep.h — a PDF document as an image representation: pages, and the current one.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A PDF REP IS THE ONE REP THAT IS NOT ONE IMAGE**, which is why Apple gives it a page count and a current
 * page rather than a pixel width. The bytes are parsed by `CGPDFDocument` from Core Graphics; `-pageCount` is its
 * page count and `-currentPage` selects which one `-drawInRect:` paints.
 *
 * TWO DRAWING ROUTES, AND THE DIFFERENCE IS A CHOICE THIS BUILD MAKES. `-drawInRect:` draws the PAGE through
 * `CGContextDrawPDFPage`, so a PDF rep stays VECTOR at any scale — the reason to keep a PDF around rather than a
 * PNG of it. `-CGImage` is the route the base class's single-image drawing seam asks for, and it RENDERS the
 * current page at its natural size into a bitmap, which is what `NSImage` caches and what a consumer that insists
 * on pixels gets. The vector route is what a view draws with; the rendered one is the fallback, not the substrate.
 *
 * THE CLASS REGISTERS ITSELF with `NSImageRep` in `+initialize` and answers the format questions
 * (`+canInitWithData:` on the `%PDF-` header, `NSPDFPboardType` and `pdf` as its types), so `NSImage`'s registry
 * finds it the same way it finds `NSBitmapImageRep`.
 */
#import <AppKit/NSImageRep.h>

#import <CoreGraphics/CGImage.h>
#import <CoreGraphics/CGPDFDocument.h>

#import <Foundation/NSData.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSPDFImageRep : NSImageRep
{
	NSData *_data;			/* RETAINED: the bytes the document is parsed from */
	CGPDFDocumentRef _document;	/* owned */
	NSInteger _currentPage;		/* zero-based */

	/* THE RENDERED FALLBACK, ONE PAGE AT A TIME. The buffer is kept because `CGBitmapContextCreateImage` may
	 * share it rather than copy it; replacing or releasing the rep frees both together. */
	CGImageRef _cachedImage;
	unsigned char *_cacheBytes;
	NSInteger _cachePage;
}

/* THE TWO DOORS THE REGISTRY AND A CALLER USE. nil for bytes that are not a readable PDF. */
+ (nullable instancetype)imageRepWithData:(nullable NSData *)pdfData;
- (nullable instancetype)initWithData:(nullable NSData *)pdfData;

@property (readonly) NSInteger pageCount;

/* ZERO-BASED, CLAMPED TO THE DOCUMENT. Setting it invalidates the rendered fallback, not the document. */
@property NSInteger currentPage;

/* THE CURRENT PAGE'S CROP BOX, ORIGIN AT ZERO — the rectangle `-drawInRect:` maps the page into. */
@property (readonly) NSRect bounds;

/* **THE BYTES THE REP WAS MADE FROM, WHICH IS WHAT A WRITE PATH NEEDS.** `NSPDFImageRep` is the one image rep whose
 * source is a document rather than pixels, so a caller serialising a pasteboard entry or an RTFD package asks for the
 * document back rather than a re-encode. The rep holds the data it parsed, so the answer is that object — the SAME bytes,
 * not a copy — and nil for a rep that was not made from data (which this class cannot be, but the door's type allows). */
- (nullable NSData *)PDFRepresentation;

@end

NS_ASSUME_NONNULL_END
