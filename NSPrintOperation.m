/*
 * NSPrintOperation — the job: paginate a view, render it, deliver it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE RENDER IS ONE `CGPDFContext` AND A LOOP OVER PAGE RECTANGLES.** The rectangles come from the view's own
 * pagination doors when it knows its range, and from the ticket's imageable height when it does not; each page is drawn
 * with the same transform `NSView -dataWithPDFInsideRect:` already uses — translate to where the page wants the rect,
 * scale, flip the view's y-down space, then `-displayRectIgnoringOpacity:context:` — so a view that prints and a view
 * that exports a PDF go through one drawing path.
 *
 * **THE DISPOSITION IS THE LAST DECISION AND IT IS EXPLICIT.** Spool hands the PDF to the seam; save writes
 * `NSPrintSavePath` (or `NSPrintJobSavingURL`); preview keeps the bytes and answers YES. A spool with no queue REFUSES
 * BY NAME rather than silently turning into a file — the caller asked for a printer and did not get one.
 */
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPanel.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintPanel.h>
#import <AppKit/NSPrinter.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/AppKitRefusal.h>

#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSValue.h>

#import <CoreGraphics/CGPDFContext.h>
#import <CoreGraphics/CGEPSContext.h>
#import <CoreGraphics/CGDataConsumer.h>

#include "../platform/AGPrintService.h"

#include <objc/message.h>

static NSPrintOperation *s_currentOperation = nil;

@interface NSPrintOperation ()
- (void)fn_renderPagesIntoContext:(CGContextRef)cg;
- (CGContextRef)fn_createPDFContext:(CGRect)mediaBox into:(CFMutableDataRef *)outData;
- (BOOL)fn_deliverPDF:(NSData *)pdf;
- (BOOL)fn_spoolPDF:(NSData *)pdf;
- (void)fn_sheetDidEnd:(id)panel returnCode:(NSInteger)code contextInfo:(void *)contextInfo;
@end

@implementation NSPrintOperation

/* ============================================================================================ *
 * THE CONSTRUCTORS.                                                                             *
 * ============================================================================================ */

+ (NSPrintOperation *)printOperationWithView:(NSView *)view
{
	return [self printOperationWithView:view printInfo:[NSPrintInfo sharedPrintInfo]];
}

+ (NSPrintOperation *)printOperationWithView:(NSView *)view printInfo:(NSPrintInfo *)printInfo
{
	NSPrintOperation *operation = [[[self alloc] init] autorelease];

	operation->_view = view;
	operation->_printInfo = [(printInfo != nil ? printInfo : [NSPrintInfo sharedPrintInfo]) retain];
	return operation;
}

+ (NSPrintOperation *)fn_copyingOperationWithView:(NSView *)view rect:(NSRect)rect
{
	NSPrintOperation *operation = [[[self alloc] init] autorelease];

	operation->_view = view;
	operation->_copying = YES;
	operation->_copyRect = rect;
	operation->_printInfo = [[NSPrintInfo sharedPrintInfo] retain];
	operation->_showsPrintPanel = NO;
	return operation;
}

+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
{
	return [self PDFOperationWithView:view insideRect:rect toData:data printInfo:nil];
}

+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect
				   toData:(NSMutableData *)data printInfo:(NSPrintInfo *)printInfo
{
	NSPrintOperation *operation = [self fn_copyingOperationWithView:view rect:rect];

	[operation setPrintInfo:printInfo];
	operation->_targetData = [data retain];
	return operation;
}

+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect
				   toPath:(NSString *)path printInfo:(NSPrintInfo *)printInfo
{
	NSPrintOperation *operation = [self fn_copyingOperationWithView:view rect:rect];

	[operation setPrintInfo:printInfo];
	operation->_copyPath = [path copy];
	return operation;
}

+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
{
	return [self EPSOperationWithView:view insideRect:rect toData:data printInfo:nil];
}

+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect
				   toData:(NSMutableData *)data printInfo:(NSPrintInfo *)printInfo
{
	NSPrintOperation *operation = [self fn_copyingOperationWithView:view rect:rect];

	[operation setPrintInfo:printInfo];
	operation->_eps = YES;
	operation->_targetData = [data retain];
	return operation;
}

+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect
				   toPath:(NSString *)path printInfo:(NSPrintInfo *)printInfo
{
	NSPrintOperation *operation = [self fn_copyingOperationWithView:view rect:rect];

	[operation setPrintInfo:printInfo];
	operation->_eps = YES;
	operation->_copyPath = [path copy];
	return operation;
}

+ (NSPrintOperation *)currentOperation
{
	return s_currentOperation;
}

+ (void)setCurrentOperation:(NSPrintOperation *)operation
{
	/* ASSIGN, NOT RETAINED: the operation is running, its caller holds it, and a static retaining it would keep a view's
	 * operation (and the view's tree) alive after the job. */
	s_currentOperation = operation;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_pageRange = NSMakeRange(0, 0);
		_pageOrder = NSAscendingPageOrder;
		_showsPrintPanel = YES;
		_showsProgressPanel = NO;
	}
	return self;
}

- (void)dealloc
{
	[_printInfo release];
	[_printPanel release];
	[_jobTitle release];
	[_jobStyleHint release];
	[_result release];
	[_copyPath release];
	[_targetData release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE JOB'S PARTS.                                                                              *
 * ============================================================================================ */

- (NSView *)view
{
	return _view;
}

- (NSPrintInfo *)printInfo
{
	return _printInfo;
}

- (void)setPrintInfo:(NSPrintInfo *)printInfo
{
	NSPrintInfo *old = _printInfo;

	_printInfo = [(printInfo != nil ? printInfo : [NSPrintInfo sharedPrintInfo]) retain];
	[old release];
}

- (NSRange)pageRange
{
	return _pageRange;
}

- (void)setPageRange:(NSRange)pageRange
{
	_pageRange = pageRange;
}

- (NSInteger)currentPage
{
	return _currentPage;
}

- (NSPrintingPageOrder)pageOrder
{
	return _pageOrder;
}

- (void)setPageOrder:(NSPrintingPageOrder)order
{
	_pageOrder = order;
}

- (NSString *)jobTitle
{
	if (_jobTitle != nil) {
		return _jobTitle;
	}
	if (_view != nil) {
		NSString *title = [_view printJobTitle];

		if (title != nil) {
			return title;
		}
		if ([_view window] != nil && [[_view window] title] != nil) {
			return [[_view window] title];
		}
	}
	return @"Print";
}

- (void)setJobTitle:(NSString *)title
{
	NSString *old = _jobTitle;

	_jobTitle = [title copy];
	[old release];
}

- (NSString *)jobStyleHint
{
	return _jobStyleHint;
}

- (void)setJobStyleHint:(NSString *)hint
{
	NSString *old = _jobStyleHint;

	_jobStyleHint = [hint copy];
	[old release];
}

- (BOOL)showsPrintPanel
{
	return _showsPrintPanel;
}

- (void)setShowsPrintPanel:(BOOL)flag
{
	_showsPrintPanel = flag ? YES : NO;
}

- (BOOL)showsProgressPanel
{
	return _showsProgressPanel;
}

- (void)setShowsProgressPanel:(BOOL)flag
{
	/* RECORDED: the render is synchronous and faster than a panel could be shown. The header says so. */
	_showsProgressPanel = flag ? YES : NO;
}

- (BOOL)showPanels
{
	return _showsPrintPanel;
}

- (void)setShowPanels:(BOOL)flag
{
	_showsPrintPanel = flag ? YES : NO;
}

- (NSPrintPanel *)printPanel
{
	if (_printPanel == nil) {
		_printPanel = [[NSPrintPanel printPanel] retain];
		[_printPanel setPrintInfo:_printInfo];
	}
	return _printPanel;
}

- (void)setPrintPanel:(NSPrintPanel *)panel
{
	NSPrintPanel *old = _printPanel;

	_printPanel = [panel retain];
	[old release];
}

- (NSView *)accessoryView
{
	return [[self printPanel] accessoryView];
}

- (void)setAccessoryView:(NSView *)view
{
	[[self printPanel] setAccessoryView:view];
}

- (BOOL)canSpawnSeparateThread
{
	return _canSpawnSeparateThread;
}

- (void)setCanSpawnSeparateThread:(BOOL)flag
{
	/* RECORDED: rendering is synchronous in this tier, and the header says so. */
	_canSpawnSeparateThread = flag ? YES : NO;
}

- (BOOL)isCopyingOperation
{
	return _copying;
}

- (NSGraphicsContext *)context
{
	return _context;
}

- (NSData *)cg_resultData
{
	return _result;
}

/* ============================================================================================ *
 * THE PAGINATION.                                                                               *
 * ============================================================================================ */

/* **THE PAGE RECTANGLES, IN DRAWING ORDER.** A view that knows its range is asked for each page's rect; one that does
 * not is cut into imageable heights with `-adjustPageHeightNew:top:bottom:limit:` given each break. `-pageRange` then
 * filters by 1-BASED page number, and `-pageOrder` decides the direction. */
- (NSArray *)fn_pageRects
{
	NSMutableArray *rects = [NSMutableArray array];
	NSRect bounds = (_view != nil) ? [_view bounds] : NSZeroRect;
	NSRect imageable = [_printInfo imageablePageBounds];
	CGFloat scale = [_printInfo scalingFactor];
	NSRange range = NSMakeRange(0, 0);
	BOOL knows = NO;

	if (scale <= 0.0) {
		scale = 1.0;
	}
	if (_view != nil) {
		knows = [_view knowsPageRange:&range];
	}
	if (knows && range.length > 0) {
		NSInteger count = (NSInteger)range.length;
		NSInteger i;

		for (i = 0; i < count; i++) {
			NSInteger offset = (_pageOrder == NSDescendingPageOrder) ? (count - 1 - i) : i;
			NSInteger page = (NSInteger)range.location + offset;
			NSRect rect = [_view rectForPage:page];

			if (NSIsEmptyRect(rect)) {
				continue;
			}
			[rects addObject:[NSValue valueWithRect:rect]];
		}
	} else {
		CGFloat available = NSHeight(imageable) / scale;
		CGFloat y = 0.0;

		if (available <= 1.0) {
			available = NSHeight(bounds);
		}
		while (y < NSHeight(bounds)) {
			CGFloat proposed = MIN(available, NSHeight(bounds) - y);
			CGFloat bottom = y + proposed;

			[_view adjustPageHeightNew:&bottom top:y bottom:y + proposed limit:NSHeight(bounds)];
			if (bottom <= y) {
				break;	/* NO PROGRESS: a view that refuses to grow would otherwise loop forever */
			}
			[rects addObject:[NSValue valueWithRect:NSMakeRect(NSMinX(bounds), y, NSWidth(bounds), bottom - y)]];
			y = bottom;
		}
		if ([rects count] == 0) {
			[rects addObject:[NSValue valueWithRect:bounds]];
		}
	}
	/* THE RANGE FILTER IS BY THE VIEW'S PAGE ORDINAL, not by the position in this array — so a range means the same
	 * thing whichever order the pages are drawn in. */
	if (_pageRange.length > 0 && knows && range.length > 0) {
		NSMutableArray *kept = [NSMutableArray array];
		NSUInteger i;

		for (i = 0; i < [rects count]; i++) {
			NSInteger ordinal = (NSInteger)i + 1;	/* the position in ascending order */

			if (ordinal >= (NSInteger)_pageRange.location
			    && ordinal < (NSInteger)NSMaxRange(_pageRange)) {
				[kept addObject:[rects objectAtIndex:i]];
			}
		}
		rects = kept;
	}
	return rects;
}

/* ============================================================================================ *
 * THE RENDER.                                                                                   *
 * ============================================================================================ */

/* **THE PAGE'S MEDIA BOX IS THE TICKET'S SHEET, LANDSCAPE APPLIED.** For a copying operation it is the rectangle the
 * caller asked for, at the origin, because a PDF of a view's rect is that rect's size and nothing else. */
- (CGRect)fn_mediaBox
{
	if (_copying) {
		return CGRectMake(0.0, 0.0, NSWidth(_copyRect), NSHeight(_copyRect));
	}
	{
		NSSize paper = [_printInfo paperSize];
		CGFloat width = paper.width;
		CGFloat height = paper.height;

		if (width <= 0.0 || height <= 0.0) {
			width = 612.0;
			height = 792.0;
		}
		if ([_printInfo orientation] == NSLandscapeOrientation) {
			CGFloat swap = width;

			width = height;
			height = swap;
		}
		return CGRectMake(0.0, 0.0, width, height);
	}
}

- (CGContextRef)fn_createPDFContext:(CGRect)mediaBox into:(CFMutableDataRef *)outData
{
	CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
	CGDataConsumerRef consumer;
	CGContextRef cg;
	CFDictionaryRef info;
	CFStringRef title = (CFStringRef)[self jobTitle];

	if (data == NULL) {
		return NULL;
	}
	consumer = CGDataConsumerCreateWithCFData(data);
	if (consumer == NULL) {
		CFRelease(data);
		return NULL;
	}
	/* THE TITLE TRAVELS IN THE PDF'S INFO DICTIONARY, which is the one place a printed document's name survives. */
	info = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&kCGPDFContextTitle, (const void **)&title, 1,
				  &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	cg = CGPDFContextCreate(consumer, &mediaBox, info);
	if (info != NULL) {
		CFRelease(info);
	}
	CGDataConsumerRelease(consumer);
	if (cg == NULL) {
		CFRelease(data);
		return NULL;
	}
	*outData = data;
	return cg;
}

/* **THE LOOP, AND THE TRANSFORM IS `NSView -dataWithPDFInsideRect:`'S.** Each page is the source rect placed in the
 * imageable area (centred if the ticket says so), scaled, and flipped, so the view's y-down drawing lands the right way
 * up on the y-up page. */
- (void)fn_renderPagesIntoContext:(CGContextRef)cg
{
	NSArray *rects;
	NSRect imageable;

	/* **A COPYING OPERATION IS EXACTLY ONE PAGE, AND ITS PAGE IS THE RECTANGLE IT WAS GIVEN.** The view's own
	 * pagination is not asked: `+PDFOperationWithView:insideRect:toData:` is "this rectangle, as a document", and a
	 * view that knows its range would otherwise render three pages into an EPS file that has one. */
	if (_copying) {
		rects = [NSArray arrayWithObject:[NSValue valueWithRect:_copyRect]];
		imageable = NSMakeRect(0.0, 0.0, NSWidth(_copyRect), NSHeight(_copyRect));
	} else {
		rects = [self fn_pageRects];
		imageable = [_printInfo imageablePageBounds];
	}
	CGFloat scale = [_printInfo scalingFactor];
	NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];
	NSUInteger i;

	if (scale <= 0.0) {
		scale = 1.0;
	}
	[NSPrintOperation setCurrentOperation:self];
	_context = context;
	for (i = 0; i < [rects count]; i++) {
		NSRect src = [[rects objectAtIndex:i] rectValue];
		CGFloat placeX = NSMinX(imageable);
		CGFloat placeY = NSMinY(imageable);

		_currentPage = (_pageRange.length > 0) ? (NSInteger)_pageRange.location + (NSInteger)i : (NSInteger)i + 1;
		if ([_printInfo isHorizontallyCentered] && NSWidth(src) * scale < NSWidth(imageable)) {
			placeX += (NSWidth(imageable) - NSWidth(src) * scale) / 2.0;
		}
		if ([_printInfo isVerticallyCentered] && NSHeight(src) * scale < NSHeight(imageable)) {
			placeY += (NSHeight(imageable) - NSHeight(src) * scale) / 2.0;
		}
		CGPDFContextBeginPage(cg, NULL);
		CGContextSaveGState(cg);
		CGContextTranslateCTM(cg, placeX, placeY);
		CGContextScaleCTM(cg, scale, scale);
		CGContextTranslateCTM(cg, 0.0, NSHeight(src));
		CGContextScaleCTM(cg, 1.0, -1.0);
		CGContextTranslateCTM(cg, -NSMinX(src), -NSMinY(src));
		[_view displayRectIgnoringOpacity:src context:context];
		CGContextRestoreGState(cg);
		CGPDFContextEndPage(cg);
	}
	_context = nil;
	[NSPrintOperation setCurrentOperation:nil];
}

/* ============================================================================================ *
 * THE PHASES.                                                                                   *
 * ============================================================================================ */

- (BOOL)createContext
{
	CGRect mediaBox = [self fn_mediaBox];

	if (_view == nil) {
		fn_refuse_window("-createContext", "a view to print");
		return NO;
	}
	if (_copying && _eps) {
		CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
		CGDataConsumerRef consumer = (data != NULL) ? CGDataConsumerCreateWithCFData(data) : NULL;

		if (consumer == NULL) {
			if (data != NULL) {
				CFRelease(data);
			}
			return NO;
		}
		_cgContext = CGEPSContextCreate(consumer, &mediaBox, NULL);
		CGDataConsumerRelease(consumer);
		if (_cgContext == NULL) {
			CFRelease(data);
			return NO;
		}
		_cgData = data;
		return YES;
	}
	_cgContext = [self fn_createPDFContext:mediaBox into:&_cgData];
	return _cgContext != NULL;
}

- (void)destroyContext
{
	if (_cgContext == NULL) {
		return;
	}
	CGPDFContextClose(_cgContext);
	if (_cgData != NULL) {
		_result = [[NSData alloc] initWithBytes:CFDataGetBytePtr(_cgData) length:(NSUInteger)CFDataGetLength(_cgData)];
	}
	CGContextRelease(_cgContext);
	_cgContext = NULL;
	if (_cgData != NULL) {
		CFRelease(_cgData);
		_cgData = NULL;
	}
}

- (BOOL)deliverResult
{
	if (_result == nil) {
		fn_refuse_window("-deliverResult", "a rendered document");
		return NO;
	}
	if (_copying) {
		if (_copyPath != nil) {
			return [_result writeToFile:_copyPath atomically:YES];
		}
		if (_targetData != nil) {
			[_targetData setData:_result];
			return YES;
		}
		return NO;
	}
	return [self fn_deliverPDF:_result];
}

- (void)cleanUpOperation
{
	/* **`-currentPage` IS LEFT WHERE THE LAST PAGE PUT IT.** A caller asking after a job gets the page the renderer
	 * finished on, which is more use than zero and is the state the operation was in when it stopped. */
	[_targetData release];
	_targetData = nil;
}

/* ============================================================================================ *
 * THE DISPOSITIONS.                                                                             *
 * ============================================================================================ */

- (BOOL)fn_deliverPDF:(NSData *)pdf
{
	NSString *disposition = [_printInfo jobDisposition];

	if ([disposition isEqual:NSPrintCancelJob]) {
		return NO;
	}
	if ([disposition isEqual:NSPrintSaveJob]) {
		NSString *path = [[_printInfo dictionary] objectForKey:NSPrintSavePath];
		id url = [[_printInfo dictionary] objectForKey:NSPrintJobSavingURL];

		if (path == nil && [url isKindOfClass:[NSURL class]]) {
			path = [(NSURL *)url path];
		}
		if (path == nil) {
			fn_refuse_window("-runOperation", "NSPrintSavePath (or NSPrintJobSavingURL) on the ticket for a save job");
			return NO;
		}
		return [pdf writeToFile:path atomically:YES];
	}
	if ([disposition isEqual:NSPrintPreviewJob]) {
		/* A PREVIEW IS THE BYTES, KEPT: `-cg_resultData` is where a caller (and the probe) reads them. */
		return YES;
	}
	return [self fn_spoolPDF:pdf];
}

- (BOOL)fn_spoolPDF:(NSData *)pdf
{
	NSPrinter *printer = [_printInfo printer];
	const char *name;
	int index = -1;
	int count;
	int i;
	int copies;
	char *jobID = NULL;
	int status;

	if (printer == nil) {
		printer = [NSPrintInfo defaultPrinter];
	}
	if (printer == nil) {
		fn_refuse_window("-runOperation", "a print queue — this machine has none, so a spool job has nowhere to go "
				 "(save it with NSPrintSaveJob, or preview it)");
		return NO;
	}
	name = [[printer name] UTF8String];
	count = AGPrintServicePrinterCount();
	for (i = 0; i < count; i++) {
		const char *queue = AGPrintServicePrinterName(i);

		if (queue != NULL && strcmp(queue, name) == 0) {
			index = i;
			break;
		}
	}
	if (index < 0) {
		fn_refuse_window("-runOperation", "a print queue that still exists — the ticket names one this machine no "
				 "longer has");
		return NO;
	}
	copies = [[[ _printInfo dictionary] objectForKey:NSPrintCopies] intValue];
	status = AGPrintServiceSubmitPDF(index, [[self jobTitle] UTF8String], copies,
					 (int)_pageRange.location,
					 (_pageRange.length > 0) ? (int)NSMaxRange(_pageRange) - 1 : 0,
					 [pdf bytes], (size_t)[pdf length], &jobID);
	if (jobID != NULL) {
		AGPrintServiceFree(jobID);
	}
	if (status != 0) {
		fn_refuse_window("-runOperation", AGPrintServiceLastError());
		return NO;
	}
	return YES;
}

/* ============================================================================================ *
 * RUNNING IT.                                                                                   *
 * ============================================================================================ */

- (BOOL)runOperation
{
	NSApplication *app = [NSApplication sharedApplication];
	BOOL delivered;

	/* **THE PANEL COMES FIRST, AND A CANCEL RUNS NOTHING.** A program with no run loop has no session to show, so the
	 * ticket's own values are used — the same guard the panels themselves carry. */
	if (_showsPrintPanel && ![self isCopyingOperation] && [app isRunning]) {
		NSInteger code;

		[[self printPanel] setPrintInfo:_printInfo];
		code = [[self printPanel] runModalWithPrintInfo:_printInfo];
		if (code != NSOKButton) {
			return NO;
		}
		{
			NSRange chosen = [[self printPanel] cg_pageRange];

			if (chosen.length > 0) {
				_pageRange = chosen;
			}
		}
	}
	if (![self createContext]) {
		[self cleanUpOperation];
		return NO;
	}
	[self fn_renderPagesIntoContext:(CGContextRef)_cgContext];
	[self destroyContext];
	delivered = [self deliverResult];
	[self cleanUpOperation];
	return delivered;
}

- (void)runOperationModalForWindow:(NSWindow *)docWindow
			  delegate:(id)delegate
		    didRunSelector:(SEL)didRunSelector
		       contextInfo:(void *)contextInfo
{
	_sheetDelegate = delegate;
	_sheetDidRun = didRunSelector;
	_sheetContext = contextInfo;
	_sheetWindow = docWindow;
	[[self printPanel] setPrintInfo:_printInfo];
	[[self printPanel] beginSheetWithPrintInfo:_printInfo modalForWindow:docWindow delegate:self
				    didEndSelector:@selector(fn_sheetDidEnd:returnCode:contextInfo:)
					 contextInfo:NULL];
}

- (void)fn_sheetDidEnd:(id)panel returnCode:(NSInteger)code contextInfo:(void *)contextInfo
{
	id delegate = _sheetDelegate;
	SEL didRun = _sheetDidRun;
	void *context = _sheetContext;
	BOOL ok = NO;

	(void)contextInfo;
	if (code == NSOKButton) {
		NSRange chosen = [(NSPrintPanel *)panel cg_pageRange];

		if (chosen.length > 0) {
			_pageRange = chosen;
		}
		_showsPrintPanel = NO;	/* the panel has already been answered */
		ok = [self runOperation];
	}
	_sheetDelegate = nil;
	_sheetDidRun = NULL;
	_sheetContext = NULL;
	_sheetWindow = nil;
	if (didRun != NULL) {
		typedef void (*AGPrintDidRun)(id, SEL, id, BOOL, void *);

		((AGPrintDidRun)objc_msgSend)(delegate, didRun, self, ok, context);
	}
}

@end
