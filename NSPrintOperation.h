/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSPrintOperation.h — THE JOB: PAGINATE A VIEW, RENDER IT, DELIVER IT.
 *
 * **A PRINT JOB IS THREE ANSWERS WITH A RENDER IN THE MIDDLE.** Which pages the view has (the pagination doors), where
 * the bytes go (the ticket's disposition: a queue, a file, or a preview), and what the caller sees while it happens (the
 * print panel and the optional progress panel). This class asks the first, draws the second into a `CGPDFContext`, and
 * hands the result to `platform/AGPrintService.h` or to a file.
 *
 * **THE PDF IS THE JOB, AND IT IS ALSO THE PDF/EPS OPERATIONS.** `+PDFOperationWithView:insideRect:toData:` and its
 * EPS sibling are the same renderer with a one-page rect and a destination that is data or a path — which is why they
 * are constructed here rather than in `NSView`, and why `-isCopyingOperation` is YES for them: a copying operation
 * renders and never spools.
 *
 * **THE PAGINATION PROTOCOL IS APPLE'S, IN THE ORDER THE OPERATION ASKS IT.** A view that says YES to
 * `-knowsPageRange:` gets `-rectForPage:` once per page number; a view that says NO is paginated vertically, one
 * imageable height at a time, with `-adjustPageHeightNew:top:bottom:limit:` given the chance to round each break. The
 * imageable height comes from the ticket (`-imageablePageBounds`), so the margins and the orientation decide how many
 * pages a tall view has.
 *
 * WHAT THIS TIER DOES NOT DO, at the door: horizontal pagination (a view wider than the page is centred and clipped
 * rather than split into columns — `NSPrintInfo`'s horizontal mode is carried and not obeyed), a separate rendering
 * thread (`-canSpawnSeparateThread` is recorded; rendering is synchronous), and the progress panel (recorded; nothing is
 * drawn because a page is rendered faster than a panel could be shown).
 *
 * Written from `NSPrintOperation.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSPRINTOPERATION_H
#define APPKIT_NSPRINTOPERATION_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSData;
@class NSMutableData;
@class NSGraphicsContext;
@class NSWindow;
@class NSPrintInfo;
@class NSPrintPanel;
@class NSString;
@class NSView;

NS_ASSUME_NONNULL_BEGIN

/* THE PAGE ORDER. `NSAscendingPageOrder` and `NSDescendingPageOrder` are negative because the era's enum says so; the
 * two "unknown" values are orders this class treats as ascending. */
enum {
	NSAscendingPageOrder = -1,
	NSDescendingPageOrder = -2,
	NSSpecialPageOrder = 0,
	NSUnknownPageOrder = 1
};
typedef NSInteger NSPrintingPageOrder;

@interface NSPrintOperation : NSObject
{
	NSView *_view;			/* ASSIGN: the caller owns the view, as Apple documents */
	NSPrintInfo *_printInfo;	/* RETAINED */
	NSPrintPanel *_printPanel;	/* RETAINED, made on demand */
	NSString *_jobTitle;		/* RETAINED (a copy) */
	NSString *_jobStyleHint;	/* RETAINED (a copy) */
	NSData *_result;		/* RETAINED: the rendered PDF, kept for a preview */
	NSGraphicsContext *_context;	/* ASSIGN while a page is being drawn */
	NSRange _pageRange;		/* 0,0 means every page */
	NSInteger _currentPage;
	NSPrintingPageOrder _pageOrder;
	BOOL _showsPrintPanel;
	BOOL _showsProgressPanel;
	BOOL _canSpawnSeparateThread;
	BOOL _copying;			/* a PDF/EPS operation */
	BOOL _eps;			/* the EPS flavour of a copying operation */
	NSRect _copyRect;		/* the rectangle a copying operation renders */
	NSString *_copyPath;		/* RETAINED: the file a copying operation writes, or nil for data */
	id _targetData;			/* RETAINED: the caller's NSMutableData for a copying operation */
	void *_cgContext;		/* the PDF/EPS context while a job runs */
	void *_cgData;			/* the CFMutableDataRef the context writes into */
	/* THE SHEET'S REPLY, for the modal-for-window form. */
	id _sheetDelegate;		/* ASSIGN */
	SEL _sheetDidRun;
	void *_sheetContext;
	id _sheetWindow;		/* ASSIGN */
}

/* ============================================================================================ *
 * THE CONSTRUCTORS.                                                                             *
 * ============================================================================================ */

+ (NSPrintOperation *)printOperationWithView:(NSView *)view;
+ (NSPrintOperation *)printOperationWithView:(NSView *)view printInfo:(NSPrintInfo *)printInfo;

/* **THE COPYING OPERATIONS: ONE RECTANGLE, ONE PAGE, A DESTINATION THAT IS DATA OR A FILE.** A nil `printInfo` uses the
 * shared ticket, so a caller that only wants a PDF does not have to make one. */
+ (nullable NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data;
+ (nullable NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect
					   toData:(NSMutableData *)data printInfo:(NSPrintInfo *)printInfo;
+ (nullable NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect
					   toPath:(NSString *)path printInfo:(NSPrintInfo *)printInfo;
+ (nullable NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data;
+ (nullable NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect
					   toData:(NSMutableData *)data printInfo:(NSPrintInfo *)printInfo;
+ (nullable NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect
					   toPath:(NSString *)path printInfo:(NSPrintInfo *)printInfo;

/* THE ONE OPERATION THAT IS RUNNING, which a view's pagination doors may ask for. */
+ (nullable NSPrintOperation *)currentOperation;
+ (void)setCurrentOperation:(nullable NSPrintOperation *)operation;

/* ============================================================================================ *
 * THE JOB'S PARTS.                                                                              *
 * ============================================================================================ */

- (nullable NSView *)view;
- (NSPrintInfo *)printInfo;
- (void)setPrintInfo:(NSPrintInfo *)printInfo;

/* **THE RANGE IS 1-BASED AND INCLUSIVE**, Apple's contract: `{1, 3}` is pages 1, 2 and 3. A length of 0 means every
 * page the view has. `-currentPage` is the page being drawn while a job runs. */
- (NSRange)pageRange;
- (void)setPageRange:(NSRange)pageRange;
- (NSInteger)currentPage;
- (NSPrintingPageOrder)pageOrder;
- (void)setPageOrder:(NSPrintingPageOrder)order;

- (nullable NSString *)jobTitle;
- (void)setJobTitle:(nullable NSString *)title;
- (nullable NSString *)jobStyleHint;
- (void)setJobStyleHint:(nullable NSString *)hint;

/* THE PANEL AND THE PROGRESS PANEL. `-setShowPanels:` is the older spelling of the same switch. */
- (BOOL)showsPrintPanel;
- (void)setShowsPrintPanel:(BOOL)flag;
- (BOOL)showsProgressPanel;
- (void)setShowsProgressPanel:(BOOL)flag;
- (BOOL)showPanels;
- (void)setShowPanels:(BOOL)flag;
- (NSPrintPanel *)printPanel;
- (void)setPrintPanel:(NSPrintPanel *)panel;
- (nullable NSView *)accessoryView;
- (void)setAccessoryView:(nullable NSView *)view;

- (BOOL)canSpawnSeparateThread;
- (void)setCanSpawnSeparateThread:(BOOL)flag;
- (BOOL)isCopyingOperation;

/* ============================================================================================ *
 * RUNNING IT.                                                                                   *
 * ============================================================================================ */

/* **THE PHASES ARE PUBLIC BECAUSE A SUBCLASS MAY OVERRIDE THEM**, which is Apple's own contract for this class:
 * `-createContext` prepares, the pages are drawn, `-deliverResult` sends the bytes where the ticket says, and
 * `-destroyContext`/`-cleanUpOperation` tear down. `-runOperation` is those phases in order and answers whether the job
 * was delivered. */
- (BOOL)runOperation;
- (BOOL)createContext;
- (void)destroyContext;
- (BOOL)deliverResult;
- (void)cleanUpOperation;
- (nullable NSGraphicsContext *)context;

/* **THE MODAL-FOR-WINDOW FORM**: the print panel is attached to the window as a sheet, and when it ends the job runs
 * and the delegate is told with the result. The selector takes `(NSPrintOperation *, BOOL, void *)`. */
- (void)runOperationModalForWindow:(nullable NSWindow *)docWindow
			  delegate:(nullable id)delegate
		    didRunSelector:(nullable SEL)didRunSelector
		       contextInfo:(nullable void *)contextInfo;

/* **THE INSTRUMENT'S DOOR, NOT APPLE'S**: the rendered PDF. A preview keeps it (that is what a preview IS), and a probe
 * reads it to assert the pages without a file. */
- (nullable NSData *)cg_resultData;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPRINTOPERATION_H */
