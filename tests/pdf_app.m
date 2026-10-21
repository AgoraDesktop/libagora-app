/*
 * pdf_app — AppKit's PDF doors, end to end: a view writes a page, a rep reads it, a pasteboard carries it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE THREE DOORS THAT WERE REFUSALS ARE NOW ONE CHAIN, AND THIS IS THE CHAIN.** `-[NSView
 * dataWithPDFInsideRect:]` opens a `CGPDFContext`, gives the view a `NSGraphicsContext` over it and lets the
 * ordinary `-displayRect:` walk draw; `NSPDFImageRep` parses the bytes back with `CGPDFDocument` and draws the
 * page through `CGContextDrawPDFPage`; `-writePDFInsideRect:toPasteboard:` puts the same bytes on a board as
 * `NSPDFPboardType`. The probe checks the PIXELS from the rep's own drawing as well as the structure, because a
 * writing bug and a drawing bug can otherwise cancel out.
 *
 * THE VIEW IS EXPLICITLY FLIPPED. `-dataWithPDFInsideRect:` gives the page a y-down space, which is the
 * orientation the window's surface and `-cacheDisplayInRect:` use; a flipped view means the numbers in
 * `-drawRect:` are the page's numbers read from the top-left, and the assertions below are written against that.
 */
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImageRep.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSPDFImageRep.h>
#import <AppKit/NSView.h>

#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGDataConsumer.h>
#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGImage.h>
#import <CoreGraphics/CGPDFContext.h>
#import <CoreGraphics/CGPDFDocument.h>
#import <CoreGraphics/CGPDFPage.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSData.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *format, ...)
{
	va_list ap;

	printf("  %s   ", ok ? "ok  " : "FAIL");
	va_start(ap, format);
	vprintf(format, ap);
	va_end(ap);
	printf("\n");
	if (!ok) {
		s_failed++;
	}
}

/* A VIEW THAT DRAWS THREE RECTANGLES IN ITS OWN (FLIPPED) COORDINATES. */
@interface AgoraPDFProbeView : NSView
@end

@implementation AgoraPDFProbeView

- (BOOL)isFlipped
{
	return YES;
}

- (void)drawRect:(NSRect)rect
{
	CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];

	(void)rect;
	if (cg == NULL) {
		return;
	}
	CGContextSetRGBFillColor(cg, 0.0, 0.0, 1.0, 1.0);
	CGContextFillRect(cg, NSMakeRect(10.0, 10.0, 50.0, 30.0));
	CGContextSetRGBFillColor(cg, 1.0, 0.0, 0.0, 1.0);
	CGContextFillRect(cg, NSMakeRect(70.0, 10.0, 20.0, 20.0));
	CGContextSetRGBFillColor(cg, 0.0, 1.0, 0.0, 1.0);
	CGContextFillRect(cg, NSMakeRect(150.0, 50.0, 30.0, 20.0));
}

@end

/* A PIXEL AT A POINT IN PDF USER SPACE, read from the context's memory. */
static void pixel_at(const unsigned char *buffer, size_t width, size_t height, CGFloat x, CGFloat y,
		     unsigned char out[4])
{
	int col = (int)x;
	int row = (int)(height - 1.0 - y);

	if (col < 0 || row < 0 || (size_t)col >= width || (size_t)row >= height) {
		out[0] = out[1] = out[2] = out[3] = 0;
		return;
	}
	memcpy(out, buffer + ((size_t)row * width + (size_t)col) * 4, 4);
}

static CGContextRef fn_render_page(CGPDFPageRef page, unsigned char *buffer, size_t width, size_t height)
{
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef cg = CGBitmapContextCreate(buffer, width, height, 8, width * 4, space,
					       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);

	CGColorSpaceRelease(space);
	if (cg != NULL) {
		CGAffineTransform transform = CGPDFPageGetDrawingTransform(page, kCGPDFCropBox,
									  CGRectMake(0, 0, (CGFloat)width,
										     (CGFloat)height),
									  0, true);

		CGContextConcatCTM(cg, transform);
		CGContextDrawPDFPage(cg, page);
	}
	return cg;
}

/* A TWO-PAGE PDF, FOR THE PAGE COUNT AND `-setCurrentPage:` — the view path above only writes one page. */
static NSData *fn_two_page_pdf(void)
{
	CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
	CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData(data);
	CGRect box = CGRectMake(0, 0, 60, 40);
	CGContextRef cg;
	NSData *result;

	if (data == NULL || consumer == NULL) {
		if (consumer != NULL) CGDataConsumerRelease(consumer);
		if (data != NULL) CFRelease(data);
		return nil;
	}
	cg = CGPDFContextCreate(consumer, &box, NULL);
	CGDataConsumerRelease(consumer);
	if (cg == NULL) {
		CFRelease(data);
		return nil;
	}
	CGPDFContextBeginPage(cg, NULL);
	CGContextSetRGBFillColor(cg, 1, 0, 0, 1);
	CGContextFillRect(cg, CGRectMake(0, 0, 60, 40));
	CGPDFContextEndPage(cg);
	CGPDFContextBeginPage(cg, NULL);
	CGContextSetRGBFillColor(cg, 0, 0, 1, 1);
	CGContextFillRect(cg, CGRectMake(0, 0, 60, 40));
	CGPDFContextEndPage(cg);
	CGPDFContextClose(cg);
	CGContextRelease(cg);
	result = [NSData dataWithBytes:CFDataGetBytePtr(data) length:(NSUInteger)CFDataGetLength(data)];
	CFRelease(data);
	return result;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	AgoraPDFProbeView *view;
	NSData *data;
	unsigned char buffer[200 * 100 * 4];
	unsigned char px[4];
	CGDataProviderRef provider;
	CGPDFDocumentRef document;
	CGPDFPageRef page;
	CGContextRef cg;
	NSPDFImageRep *rep;
	CGImageRef image;
	NSPasteboard *board;
	NSData *pasted;
	NSData *two;

	view = [[AgoraPDFProbeView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
	check(view != nil, "the probe view was created");
	data = [view dataWithPDFInsideRect:NSMakeRect(0, 0, 200, 100)];
	check(data != nil && [data length] > 100, "-dataWithPDFInsideRect: returned data");
	check(data != nil && [data length] >= 8 && memcmp([data bytes], "%PDF-1.4", 8) == 0,
	      "the data begins with a PDF 1.4 header");

	provider = data != nil ? CGDataProviderCreateWithData(NULL, [data bytes], (size_t)[data length], NULL) : NULL;
	document = provider != NULL ? CGPDFDocumentCreateWithProvider(provider) : NULL;
	if (provider != NULL) {
		CGDataProviderRelease(provider);
	}
	check(document != NULL, "the written bytes reopen through CGPDFDocument");
	check(document != NULL && CGPDFDocumentGetNumberOfPages(document) == 1,
	      "the document has one page");
	page = document != NULL ? CGPDFDocumentGetPage(document, 1) : NULL;
	if (page != NULL) {
		CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);

		check((int)box.size.width == 200 && (int)box.size.height == 100,
		      "the page is 200x100 points");
	}

	/* THE PIXELS, THROUGH THE PAGE THE VIEW WROTE. The view is flipped and draws 10 points down from the top
	 * for the blue rectangle, so in the page's y-up space that is y 60..90. */
	memset(buffer, 0, sizeof buffer);
	cg = page != NULL ? fn_render_page(page, buffer, 200, 100) : NULL;
	check(cg != NULL, "the written page renders");
	if (cg != NULL) {
		pixel_at(buffer, 200, 100, 35, 75, px);
		check(px[3] > 200 && px[0] > 200 && px[1] < 60 && px[2] < 60,
		      "the view's blue rectangle is on the page (B=%u G=%u R=%u A=%u)", px[0], px[1], px[2], px[3]);
		pixel_at(buffer, 200, 100, 80, 80, px);
		check(px[3] > 200 && px[2] > 200 && px[0] < 60 && px[1] < 60,
		      "the view's red rectangle is on the page (B=%u G=%u R=%u A=%u)", px[0], px[1], px[2], px[3]);
		pixel_at(buffer, 200, 100, 165, 40, px);
		check(px[3] > 200 && px[1] > 200 && px[0] < 60 && px[2] < 60,
		      "the view's green rectangle is on the page (B=%u G=%u R=%u A=%u)", px[0], px[1], px[2], px[3]);
		pixel_at(buffer, 200, 100, 120, 90, px);
		check(px[3] < 20, "the page is empty where the view drew nothing (A=%u)", px[3]);
		CGContextRelease(cg);
	}

	/* THE PASTEBOARD DOOR, carrying the same bytes under the PDF type. */
	board = [NSPasteboard pasteboardWithUniqueName];
	[view writePDFInsideRect:NSMakeRect(0, 0, 200, 100) toPasteboard:board];
	pasted = [board dataForType:NSPDFPboardType];
	check(pasted != nil && [pasted length] > 100, "-writePDFInsideRect:toPasteboard: put PDF data on the board");
	check(pasted != nil && [pasted length] >= 8 && memcmp([pasted bytes], "%PDF-", 5) == 0,
	      "the pasteboard data has a PDF header");

	/* THE REP: parses the view's own output, counts its pages and draws the page as VECTOR. */
	rep = [NSPDFImageRep imageRepWithData:data];
	check(rep != nil, "NSPDFImageRep accepted the view's PDF data");
	check(rep != nil && [rep pageCount] == 1, "the rep counts one page");
	check(rep != nil && (int)[rep size].width == 200 && (int)[rep size].height == 100,
	      "the rep's size is the page's");
	check([NSPDFImageRep canInitWithData:data], "the rep's sniff accepts PDF bytes");
	check(![NSPDFImageRep canInitWithData:[NSData dataWithBytes:"PNG" length:3]],
	      "the rep's sniff rejects three bytes of not-PDF");
	image = rep != nil ? [rep CGImage] : NULL;
	check(image != NULL && CGImageGetWidth(image) == 200 && CGImageGetHeight(image) == 100,
	      "the rendered fallback is the page's size");

	if (rep != nil) {
		NSGraphicsContext *graphics;
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

		memset(buffer, 0, sizeof buffer);
		cg = CGBitmapContextCreate(buffer, 200, 100, 8, 200 * 4, space,
					   kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
		CGColorSpaceRelease(space);
		graphics = cg != NULL ? [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES] : nil;
		if (graphics != nil) {
			NSGraphicsContext *previous = [[NSGraphicsContext currentContext] retain];

			[NSGraphicsContext setCurrentContext:graphics];
			check([rep drawInRect:NSMakeRect(0, 0, 200, 100)], "the rep drew its page");
			[NSGraphicsContext setCurrentContext:previous];
			[previous release];
			pixel_at(buffer, 200, 100, 35, 75, px);
			check(px[3] > 200 && px[0] > 200 && px[1] < 60 && px[2] < 60,
			      "the rep's vector draw put the blue rectangle in the same place (B=%u G=%u R=%u A=%u)",
			      px[0], px[1], px[2], px[3]);
		} else {
			check(0, "the rep's draw had no context");
		}
		if (cg != NULL) {
			CGContextRelease(cg);
		}
	}

	/* TWO PAGES, AND THE CURRENT-PAGE DOOR. */
	two = fn_two_page_pdf();
	if (two != nil) {
		NSPDFImageRep *pages = [NSPDFImageRep imageRepWithData:two];

		check(pages != nil && [pages pageCount] == 2, "a two-page PDF is counted as two");
		if (pages != nil) {
			[pages setCurrentPage:1];
			check([pages currentPage] == 1, "the rep's current page can be moved");
			[pages setCurrentPage:99];
			check([pages currentPage] == 1, "the current page is clamped to the last page");
		}
	} else {
		check(0, "the two-page PDF was not written");
	}

	if (document != NULL) {
		CGPDFDocumentRelease(document);
	}
	[view release];
	[pool drain];
	if (s_failed != 0) {
		fprintf(stderr, "%d PDF/AppKit check(s) failed\n", s_failed);
		return 1;
	}
	printf("pdf_app: all checks passed\n");
	return 0;
}
