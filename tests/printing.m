/*
 * printing — the ticket, the printer table, the renderer, the panels and the document doors.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS THAT A PRINT JOB COMES OUT AS A PDF WITH THE RIGHT PAGES**, and every check below is a way of asking
 * that without a printer: the ticket's arithmetic is numbers, the renderer's output is parsed back by `NSPDFImageRep`
 * (which is the same Core Graphics reader a viewer would use), and the panels' sessions are driven without a run loop —
 * the guard they carry for a program with no event source.
 *
 * WHAT IS MEASURED:
 *
 *   1. THE TICKET. A4 and Letter, the four margins, the imageable rect both ways round, landscape swapping the sheet,
 *      the dictionary being the storage, and a document's ticket being a COPY of the shared one.
 *   2. THE PAPER TABLE. A keyword and a friendly name resolve to the same points; an unknown paper is the empty value.
 *   3. THE RENDERER. A view that knows its range gets exactly its pages; a tall view that does not is cut by the
 *      imageable height; the page range selects; save writes a file, preview keeps the bytes, and a spool with no queue
 *      refuses rather than pretending.
 *   4. THE COPYING OPERATIONS. PDF and EPS render one rect to data, and `-isCopyingOperation` says so.
 *   5. THE PANELS. `-runModal` without a run loop answers OK and writes the ticket back; the page layout's read/write
 *      round trip leaves a ticket alone when nothing was changed.
 *   6. THE PANELS AS SHEETS. Both `-beginSheetWithPrintInfo:…` doors ATTACH the panel — which they did not: they called a
 *      two-argument `-beginSheet:modalForWindow:` this tier has never had, so pressing a panel's Print or Page Setup
 *      button aborted the process with "not implemented". The panel's own OK button is driven here, and the caller's
 *      did-end is asserted to be called once with OK's code and its context intact, after which nothing is attached.
 *   7. THE APPLICATION. `-application:printFiles:` tells the delegate and replies with the launch's code.
 */
#import <Foundation/NSAutoreleasePool.h>	/* the pool a caller's local panel dies with */
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPrintPanel.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPageLayout.h>
#import <AppKit/NSPrinter.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSDocument.h>
#import <AppKit/NSPDFImageRep.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSViewController.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

static int g_checks;
static int g_failed;

static void check(int ok, const char *what)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", what);
	} else {
		printf("  [ok]   %s\n", what);
	}
}

static int near(double a, double b)
{
	return fabs(a - b) < 0.01;
}

/* ============================================================================================ *
 * A VIEW THAT KNOWS ITS OWN PAGES: three bands, each a different colour, each its own page.      *
 * ============================================================================================ */

@interface AGPageView : NSView
{
@public
	BOOL sawAContext;
	NSInteger drawnPages;
}
@end

@implementation AGPageView

- (BOOL)knowsPageRange:(NSRangePointer)range
{
	range->location = 1;
	range->length = 3;
	return YES;
}

- (NSRect)rectForPage:(NSInteger)page
{
	/* EACH PAGE'S SOURCE RECT IS A DIFFERENT BAND OF THE VIEW, which is how a paginating view slices itself. */
	return NSMakeRect(0.0, (CGFloat)(page - 1) * 100.0, 200.0, 100.0);
}

- (void)drawRect:(NSRect)rect
{
	NSInteger band = (NSInteger)floor(NSMinY(rect) / 100.0);

	drawnPages++;
	if ([[NSPrintOperation currentOperation] context] != nil) {
		sawAContext = YES;
	}
	[[NSColor colorWithCalibratedRed:0.2 + 0.2 * (double)band green:0.3 blue:0.6 alpha:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:rect] fill];
}

@end

/* AND A VIEW THAT DOES NOT: it is one tall band and the operation has to cut it. */
@interface AGTallView : NSView
@end

@implementation AGTallView
- (void)drawRect:(NSRect)rect
{
	[[NSColor darkGrayColor] setFill];
	[[NSBezierPath bezierPathWithRect:rect] fill];
}
@end

/* ============================================================================================ *
 * THE TICKET.                                                                                   *
 * ============================================================================================ */

static void test_ticket(void)
{
	NSPrintInfo *info = [[NSPrintInfo alloc] init];
	NSPrintInfo *copy;
	NSRect imageable;

	printf("the ticket\n");
	check(near([info paperSize].width, 595.0) && near([info paperSize].height, 842.0),
	      "a fresh ticket is A4");
	check(near([info topMargin], 72.0) && near([info bottomMargin], 72.0)
	      && near([info leftMargin], 72.0) && near([info rightMargin], 72.0),
	      "with one-inch margins");
	check([info orientation] == NSPortraitOrientation && near([info scalingFactor], 1.0),
	      "portrait and unscaled");
	check([info horizontalPagination] == NSAutoPagination && [info verticalPagination] == NSAutoPagination,
	      "and automatic pagination in both directions");
	check([info isHorizontallyCentered] && [info isVerticallyCentered], "and both centres on");
	check([[info jobDisposition] isEqual:NSPrintSpoolJob], "and the era's spool disposition");
	check([info isSelectionOnly] == NO, "and not a selection-only job");

	imageable = [info imageablePageBounds];
	check(near(NSMinX(imageable), 72.0) && near(NSMinY(imageable), 72.0)
	      && near(NSWidth(imageable), 451.0) && near(NSHeight(imageable), 698.0),
	      "the imageable rect is the sheet minus the margins");

	[info setOrientation:NSLandscapeOrientation];
	imageable = [info imageablePageBounds];
	check(near(NSWidth(imageable), 698.0) && near(NSHeight(imageable), 451.0)
	      && near([info paperSize].width, 595.0),
	      "landscape swaps the imageable AXES and leaves the sheet's own size alone");

	[info setOrientation:NSPortraitOrientation];
	[info setPaperName:@"Letter"];
	check(near([info paperSize].width, 612.0) && near([info paperSize].height, 792.0),
	      "a paper NAME sets the size with it");
	check(near([info sizeForPaperName:@"A4"].width, 595.0), "-sizeForPaperName: answers a known paper");
	check(near([info sizeForPaperName:@"NoSuchPaper"].width, 0.0), "and the empty size for an unknown one");

	[info setTopMargin:36.0];
	check(near([[[info dictionary] objectForKey:NSPrintTopMargin] doubleValue], 36.0),
	      "the dictionary IS the storage: a margin lands under its key");
	[info setJobDisposition:NSPrintSaveJob];
	check([[info jobDisposition] isEqual:NSPrintSaveJob], "the disposition round-trips");

	copy = [info copy];
	check(copy != info && near([copy topMargin], 36.0) && [[copy jobDisposition] isEqual:NSPrintSaveJob],
	      "a ticket copies as a ticket");
	[copy setTopMargin:12.0];
	check(near([info topMargin], 36.0), "and the copy is independent");

	{
		NSPrintInfo *built;

		built = [[NSPrintInfo alloc] initWithDictionary:
			[NSDictionary dictionaryWithObject:[NSValue valueWithSize:NSMakeSize(300.0, 400.0)]
						    forKey:NSPrintPaperSize]];
		check(near([built paperSize].width, 300.0) && near([built paperSize].height, 400.0),
		      "-initWithDictionary: carries the sheet");
		[built release];
	}

	check([NSPrintInfo sharedPrintInfo] == [NSPrintInfo sharedPrintInfo], "the shared ticket is one object");
	check([info PMPrintSession] == NULL && [info PMPageFormat] == NULL && [info PMPrintSettings] == NULL,
	      "the Carbon handles are NULL, which is what this tier has");
	[info release];
}

/* ============================================================================================ *
 * THE PRINTER TABLE.                                                                            *
 * ============================================================================================ */

static void test_printers(void)
{
	NSArray *names = [NSPrinter printerNames];
	NSArray *standard = [NSPrinter cg_standardPaperNames];
	NSSize keyword;
	NSSize friendly;

	printf("the printer table and the queue list\n");
	check([names isKindOfClass:[NSArray class]], "+printerNames answers a list");
	check([NSPrinter printerWithName:@"NoSuchQueueAgora"] == nil, "a queue nobody has answers nil");
	check([NSPrinter printerWithType:@"NoSuchType"] == nil, "and so does a type nobody has");

	keyword = [NSPrinter cg_paperSizeForName:@"na_letter_8.5x11in"];
	friendly = [NSPrinter cg_paperSizeForName:@"Letter"];
	check(near(keyword.width, 612.0) && near(keyword.height, 792.0),
	      "an IPP keyword resolves to points");
	check(near(keyword.width, friendly.width) && near(keyword.height, friendly.height),
	      "and the keyword and the friendly name are the same paper");
	check(near([NSPrinter cg_paperSizeForName:@"A4"].width, 595.0), "A4 is 595 points wide");
	check(near([NSPrinter cg_paperSizeForName:@"Tabloid"].width, 792.0), "an alias resolves to its sheet");
	check(near([NSPrinter cg_paperSizeForName:@"NoSuchPaper"].width, 0.0), "an unknown paper is NSZeroSize");
	check([[NSPrinter cg_paperNameForKeyword:@"iso_a4_210x297mm"] isEqual:@"A4"], "a keyword names its paper");
	check([[NSPrinter cg_standardPaperNames] containsObject:@"A4"] && [standard count] >= 8,
	      "the standard list has the papers the panel offers");

	if ([names count] > 0) {
		NSPrinter *printer = [NSPrinter printerWithName:[names objectAtIndex:0]];

		check(printer != nil && [[printer name] isEqual:[names objectAtIndex:0]],
		      "a listed queue resolves by name");
		check([[printer type] length] > 0 && [printer printerTypes] != nil,
		      "and answers a type and its type list");
		check([printer pageSizeForPaper:@"A4"].width > 0.0, "and a page size through its own table");
	} else {
		check(YES, "this machine has no queues, which every printer door answers for");
	}
}

/* ============================================================================================ *
 * THE RENDERER.                                                                                 *
 * ============================================================================================ */

static void test_render(void)
{
	NSPrintInfo *info = [[NSPrintInfo alloc] init];
	AGPageView *view = [[AGPageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 300.0)];
	NSPrintOperation *operation;
	NSData *pdf;
	NSPDFImageRep *rep;

	printf("the renderer\n");
	[info setJobDisposition:NSPrintPreviewJob];
	operation = [NSPrintOperation printOperationWithView:view printInfo:info];
	[operation setShowsPrintPanel:NO];
	check([operation isCopyingOperation] == NO, "a print operation is not a copying one");
	check([operation view] == view && [operation printInfo] == info, "it carries its view and ticket");
	check([operation runOperation], "a preview job runs");
	check([operation currentPage] == 3, "and reports the last page it drew");
	check(view->sawAContext, "the view was drawn with an operation context, which is what -context: answers");

	pdf = [operation cg_resultData];
	check([pdf length] > 0, "the result is a PDF");
	rep = [[NSPDFImageRep alloc] initWithData:pdf];
	check(rep != nil && [rep pageCount] == 3, "and the reader counts the view's three pages");
	[rep release];

	/* THE PAGE RANGE SELECTS BY THE VIEW'S OWN PAGE NUMBER. */
	{
		NSPrintOperation *ranged = [NSPrintOperation printOperationWithView:view printInfo:info];

		[ranged setShowsPrintPanel:NO];
		[ranged setPageRange:NSMakeRange(2, 1)];
		[ranged runOperation];
		rep = [[NSPDFImageRep alloc] initWithData:[ranged cg_resultData]];
		check(rep != nil && [rep pageCount] == 1, "a one-page range renders one page");
		[rep release];
	}

	/* A VIEW THAT DOES NOT KNOW ITS RANGE IS CUT BY THE IMAGEABLE HEIGHT. */
	{
		AGTallView *tall = [[AGTallView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 2000.0)];
		NSPrintOperation *cut = [NSPrintOperation printOperationWithView:tall printInfo:info];

		[cut setShowsPrintPanel:NO];
		check([cut runOperation], "a tall view prints");
		rep = [[NSPDFImageRep alloc] initWithData:[cut cg_resultData]];
		check(rep != nil && [rep pageCount] == 3,
		      "2000 points at 698 per page is three pages (the last one short)");
		[rep release];
		[tall release];
	}

	/* SAVE WRITES A FILE. */
	{
		NSString *path = @"/tmp/agora-print-probe.pdf";
		NSPrintOperation *saving = [NSPrintOperation printOperationWithView:view printInfo:info];

		[info setJobDisposition:NSPrintSaveJob];
		[[info dictionary] setObject:path forKey:NSPrintSavePath];
		[saving setShowsPrintPanel:NO];
		check([saving runOperation], "a save job runs");
		check([[NSFileManager defaultManager] fileExistsAtPath:path], "and writes its file");
		rep = [[NSPDFImageRep alloc] initWithData:[NSData dataWithContentsOfFile:path]];
		check(rep != nil && [rep pageCount] == 3, "which is the same three-page PDF");
		[rep release];
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	}

	/* A SAVE WITH NO PATH REFUSES RATHER THAN GUESSING ONE. */
	{
		NSPrintOperation *nowhere = [NSPrintOperation printOperationWithView:view printInfo:info];

		[[info dictionary] removeObjectForKey:NSPrintSavePath];
		[nowhere setShowsPrintPanel:NO];
		check(![nowhere runOperation], "a save job with no path refuses");
	}

	/* AND A SPOOL WITH NO QUEUE REFUSES. */
	if ([[NSPrinter printerNames] count] == 0) {
		NSPrintOperation *spool = [NSPrintOperation printOperationWithView:view printInfo:info];

		[info setJobDisposition:NSPrintSpoolJob];
		[spool setShowsPrintPanel:NO];
		check(![spool runOperation], "a spool job with no queue refuses rather than silently saving");
	}

	[view release];
	[info release];
}

/* ============================================================================================ *
 * THE COPYING OPERATIONS.                                                                       *
 * ============================================================================================ */

static void test_copying(void)
{
	AGPageView *view = [[AGPageView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 300.0)];
	NSMutableData *pdfData = [NSMutableData data];
	NSMutableData *epsData = [NSMutableData data];
	NSPrintOperation *pdfOperation;
	NSPrintOperation *epsOperation;

	printf("the copying operations\n");
	pdfOperation = [NSPrintOperation PDFOperationWithView:view insideRect:NSMakeRect(0.0, 0.0, 200.0, 300.0)
						      toData:pdfData];
	check(pdfOperation != nil && [pdfOperation isCopyingOperation],
	      "a PDF operation is a copying operation");
	check([pdfOperation runOperation] && [pdfData length] > 0, "and fills the caller's data");
	{
		NSPDFImageRep *rep = [[NSPDFImageRep alloc] initWithData:pdfData];

		check(rep != nil && [rep pageCount] == 1, "with one page, which is the rectangle it was given");
		[rep release];
	}

	epsOperation = [NSPrintOperation EPSOperationWithView:view insideRect:NSMakeRect(0.0, 0.0, 200.0, 300.0)
						      toData:epsData];
	check([epsOperation runOperation] && [epsData length] > 0, "an EPS operation fills its data");
	{
		char head[4] = { 0, 0, 0, 0 };

		[epsData getBytes:head length:3];
		check(strcmp(head, "%!P") == 0, "and the bytes begin with a PostScript magic number");
	}

	[view release];
}

/* ============================================================================================ *
 * THE PANELS.                                                                                   *
 * ============================================================================================ */

@interface AGPrintAccessory : NSViewController <NSPrintPanelAccessorizing>
@end

/* **THE TWO PRIVATE DOORS THIS FILE DRIVES, AND WHY A PRIVATE DOOR IS THE HONEST WAY TO DRIVE THEM.** A panel's
 * buttons send `-fn_ok:`/`-fn_cancel:`, and those are the actions that answer the session — the same ones a person's
 * press reaches, and the only route to the sheet's reply. They are declared in the implementations' class extensions,
 * so this is the tree's usual redeclaration of a private contract by the probe that needs it. */
@interface NSPrintPanel (AGPrintingSheetTest)
- (void)fn_ok:(id)sender;
@end

@interface NSPageLayout (AGPrintingSheetTest)
- (void)fn_ok:(id)sender;
@end

@implementation AGPrintAccessory
- (NSArray *)localizedSummaryItems { return [NSArray array]; }
- (void)loadView { [self setView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)] autorelease]]; }
@end

static void test_panels(void)
{
	NSPrintInfo *info = [[NSPrintInfo alloc] init];
	NSPrintPanel *panel = [NSPrintPanel printPanel];
	NSPageLayout *layout = [NSPageLayout pageLayout];
	NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
	AGPrintAccessory *controller = [[AGPrintAccessory alloc] init];

	printf("the panels\n");
	check(panel != nil && layout != nil, "both panels are made");
	[panel setPrintInfo:info];
	check([panel printInfo] == info, "the print panel carries the ticket");
	[panel setOptions:(NSPrintPanelShowsCopies | NSPrintPanelShowsPageRange)];
	check([panel options] == (NSPrintPanelShowsCopies | NSPrintPanelShowsPageRange), "and its options word");
	[panel setDefaultButtonTitle:@"Print It"];
	check([[panel defaultButtonTitle] isEqual:@"Print It"], "and the default button's title");

	[panel setAccessoryView:accessory];
	check([panel accessoryView] == accessory, "an accessory view round-trips");
	[panel addAccessoryController:(id)controller];
	check([[panel accessoryControllers] count] == 1, "and an accessory controller is listed");
	[panel removeAccessoryController:(id)controller];
	check([[panel accessoryControllers] count] == 0, "and can be removed");
	check([panel cg_pageRange].length == 0, "the range starts as every page (an empty range)");

	[info setJobDisposition:NSPrintSaveJob];
	check([panel runModalWithPrintInfo:info] == NSOKButton, "a modal session without a run loop answers OK");
	check([[[info dictionary] objectForKey:NSPrintCopies] integerValue] == 1,
	      "and writes the ticket's copies back");

	/* THE PAGE LAYOUT'S ROUND TRIP: read, change nothing, write. */
	[layout setPrintInfo:info];
	[layout readPrintInfo];
	[layout writePrintInfo];
	check(near([info paperSize].width, 595.0) && [info orientation] == NSPortraitOrientation,
	      "the page layout's read/write round trip leaves an untouched ticket alone");
	[info setOrientation:NSLandscapeOrientation];
	[layout readPrintInfo];
	[layout writePrintInfo];
	check([info orientation] == NSLandscapeOrientation, "and carries a landscape choice through");
	check([layout runModalWithPrintInfo:info] == NSOKButton, "its modal session answers OK without a run loop");

	[panel setAccessoryView:nil];
	[accessory release];
	[controller release];
	[info release];
}

/* ============================================================================================ *
 * THE DOCUMENT AND THE APPLICATION.                                                             *
 * ============================================================================================ */

@interface AGPrintDelegate : NSObject
{
@public
	NSInteger calls;
}
- (NSApplicationPrintReply)application:(NSApplication *)application printFiles:(NSArray *)fileNames
			  withSettings:(NSDictionary *)printSettings showPrintPanels:(BOOL)showPrintPanels;
@end

@implementation AGPrintDelegate
- (NSApplicationPrintReply)application:(NSApplication *)application printFiles:(NSArray *)fileNames
			  withSettings:(NSDictionary *)printSettings showPrintPanels:(BOOL)showPrintPanels
{
	(void)application;
	(void)fileNames;
	(void)printSettings;
	(void)showPrintPanels;
	calls++;
	return NSPrintingSuccess;
}
@end

/* **THE SHEET'S REPLY, AS THE CALLER OF A PANEL SEES IT.** Apple's did-end selector is
 * `panelDidEnd:returnCode:contextInfo:` for the print panel and the same shape for the page layout, and the whole
 * point of the session is that this method is called ONCE, with the code of the button that ended it. */
@interface AGPrintSheetReception : NSObject
{
@public
	NSInteger calls;
	NSInteger code;
	id endedPanel;
	void *context;
}
@end

@implementation AGPrintSheetReception
- (void)panelDidEnd:(id)panel returnCode:(NSInteger)aCode contextInfo:(void *)aContext
{
	calls++;
	code = aCode;
	endedPanel = panel;
	context = aContext;
}
@end

/* **AND THE SHEET FORMS OF BOTH PANELS, WHICH ARE THE DOORS THAT WERE BROKEN.** `-beginSheetWithPrintInfo:…` on
 * `NSPrintPanel` and on `NSPageLayout` called `-[NSApplication beginSheet:modalForWindow:]` — a selector this tier's
 * `NSApplication` does NOT have — so pressing a panel's Print or Page Setup button raised "not implemented" from the
 * runtime and ABORTED the process. MEASURED, from the gallery's own Print Panel button:
 *
 *   Foundation: -[NSApplication beginSheet:modalForWindow:] is not implemented
 *   *** Terminating due to uncaught exception 'NSInvalidArgumentException'
 *
 * It compiled, which is the interesting part: an unknown selector on a typed receiver is a WARNING
 * (`-Wobjc-method-access`) and the build's own noise hid it. So this test drives the doors end to end rather than
 * checking that a selector exists: attach, the panel's own window is the sheet, the panel's OK button answers the
 * CALLER'S did-end with NSOKButton (the panel replies itself, so the session must be begun with no reply of its own),
 * and the attachment is gone afterwards. */
static void test_panel_sheets(void)
{
	NSPrintInfo *info = [[NSPrintInfo alloc] init];
	NSPrintPanel *panel = [NSPrintPanel printPanel];
	NSPageLayout *layout = [NSPageLayout pageLayout];
	NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(100.0, 100.0, 420.0, 320.0)
						      styleMask:NSTitledWindowMask
							backing:NSBackingStoreBuffered
							  defer:NO];
	AGPrintSheetReception *reception = [[AGPrintSheetReception alloc] init];

	printf("the panels as sheets\n");
	check(parent != nil && reception != nil, "a parent to hang a panel on, and a caller to be answered");
	[panel beginSheetWithPrintInfo:info
			modalForWindow:parent
			      delegate:reception
			didEndSelector:@selector(panelDidEnd:returnCode:contextInfo:)
			   contextInfo:(void *)0x5];
	check([parent attachedSheet] != nil && [[parent attachedSheet] isSheet],
	      "`-beginSheetWithPrintInfo:…` ATTACHES the panel to the window rather than raising a runtime error");
	check(reception->calls == 0, "the session is asynchronous: nothing has been answered yet");
	[panel fn_ok:nil];
	check(reception->calls == 1, "the panel's OK button calls the caller's did-end ONCE");
	check(reception->code == NSOKButton, "with OK's code");
	check(reception->endedPanel == panel, "and with the panel itself as the window");
	check(reception->context == (void *)0x5, "and the caller's own context pointer, untouched");
	check([parent attachedSheet] == nil, "and the attachment is gone: the session ended as it should");

	/* **AND THE PANEL SURVIVES THE POOL THAT MADE IT, WHICH IS THE REPORTED SEGFAULT.** `+printPanel` answers an
	 * AUTORELEASED panel, and a sheet is asynchronous: the run loop drains a pool a pass later, and a panel that died
	 * there released the views of a window that was still attached and still being displayed — MEASURED as a SIGSEGV
	 * inside `-[NSView cg_dirtyRegionRecursive:…]` (and, from a pointer motion, inside
	 * `-[NSView cg_rebuildStaleCursorRects]`). The session now retains its panel until it ends, so this drains a pool
	 * with the sheet up and asks the sheet afterwards: a dead window would be a crash here rather than a failed check,
	 * which is exactly the shape of the bug. */
	{
		NSAutoreleasePool *pass = [[NSAutoreleasePool alloc] init];
		NSPrintPanel *transient = [NSPrintPanel printPanel];	/* autoreleased, as a caller's local would be */
		NSWindow *sheet;

		[transient beginSheetWithPrintInfo:info
				     modalForWindow:parent
					   delegate:reception
				     didEndSelector:@selector(panelDidEnd:returnCode:contextInfo:)
					contextInfo:(void *)0x7];
		sheet = [parent attachedSheet];
		check(sheet != nil, "a panel from the factory attaches a sheet");
		[pass release];		/* the pass that made the panel ends with the sheet still up */
		check([parent attachedSheet] == sheet, "and the sheet is STILL attached after the pool that made its panel");
		check([[parent attachedSheet] isSheet], "and it is still a sheet: the session owns the panel, not the caller");
		check(reception->calls == 1, "nothing has been answered while the sheet is up");
		[transient fn_ok:nil];
		check(reception->calls == 2 && reception->code == NSOKButton,
		      "and its OK still answers the caller — the panel lived to end its own session");
		check([parent attachedSheet] == nil, "with the attachment gone afterwards");
	}

	/* AND THE PAGE LAYOUT'S HALF OF IT, which had the same call and the same crash. */
	[layout beginSheetWithPrintInfo:info
			 modalForWindow:parent
			       delegate:reception
			 didEndSelector:@selector(panelDidEnd:returnCode:contextInfo:)
			    contextInfo:NULL];
	check([parent attachedSheet] != nil, "`-NSPageLayout beginSheetWithPrintInfo:…` attaches too");
	[layout fn_ok:nil];
	check(reception->calls == 3 && reception->code == NSOKButton, "and its OK answers the caller with OK's code");
	check([parent attachedSheet] == nil, "and the session is over");

	[reception release];
	[parent release];
	[info release];
}

static void test_document_and_application(void)
{
	NSPrintInfo *shared = [NSPrintInfo sharedPrintInfo];
	NSDocument *document = [[NSDocument alloc] init];
	NSPrintInfo *ticket;
	NSPrintOperation *operation;
	NSError *error = nil;
	AGPrintDelegate *delegate = [[AGPrintDelegate alloc] init];
	NSApplication *app = [NSApplication sharedApplication];

	printf("the document and the application\n");
	[shared setPaperName:@"A4"];
	ticket = [document printInfo];
	check(ticket != nil && ticket != shared, "a document's ticket is its own object");
	check(near([ticket paperSize].width, 595.0), "and begins as a copy of the shared one");
	[ticket setPaperName:@"Letter"];
	check(near([shared paperSize].width, 595.0), "changing it does not change the shared ticket");
	check([document shouldChangePrintInfo:ticket], "a document lets its ticket change");

	operation = [document printOperationWithSettings:nil error:&error];
	check(operation == nil || [operation printInfo] == ticket,
	      "a document's print operation carries the document's ticket");
	check([document handlePrintScriptCommand:nil] == nil,
	      "the print script command answers nil rather than crashing");

	[app setDelegate:(id)delegate];
	[app application:app printFiles:[NSArray arrayWithObject:@"/tmp/no-such-file"]];
	check(delegate->calls == 1, "a print request reaches a delegate that implements the door");
	check([app cg_lastOpenOrPrintReply] == NSApplicationDelegateReplySuccess,
	      "and the launch replies with the delegate's answer");
	[app setDelegate:nil];

	[delegate release];
	[document release];
}

int main(void)
{
	printf("printing — the ticket, the renderer and the panels\n");
	test_ticket();
	test_printers();
	test_render();
	test_copying();
	test_panels();
	test_panel_sheets();
	test_document_and_application();

	printf("\n%d checks, %d failed\n", g_checks, g_failed);
	return g_failed == 0 ? 0 : 1;
}
