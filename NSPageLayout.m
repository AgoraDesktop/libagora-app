/*
 * NSPageLayout — the dialog that edits the page.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The same shape as `NSPrintPanel`: a window this object owns, built once; `-readPrintInfo` filling the controls and
 * `-writePrintInfo` writing them back; a modal session with the no-run-loop guard. The paper list is the queue's media
 * keywords first and `NSPrinter`'s standard names after them, de-duplicated by friendly name.
 */
#import <AppKit/NSPageLayout.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrinter.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <AppKit/NSViewController.h>
#import <AppKit/NSWindow.h>

#include <objc/message.h>

#define AG_PAGE_LAYOUT_WIDTH  360.0
#define AG_PAGE_LAYOUT_HEIGHT 240.0
#define AG_PAGE_LAYOUT_MARGIN  16.0

@interface NSPageLayout ()
- (void)fn_buildWindow;
- (void)fn_ok:(id)sender;
- (void)fn_cancel:(id)sender;
- (void)fn_finishWithCode:(NSInteger)code;
@end

@implementation NSPageLayout

+ (NSPageLayout *)pageLayout
{
	return [[[self alloc] init] autorelease];
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_accessoryControllers = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_printInfo release];
	[_accessoryView release];
	[_accessoryControllers release];
	[_modalWindow release];
	[_paperPopup release];
	[_orientationPopup release];
	[_topField release];
	[_bottomField release];
	[_leftField release];
	[_rightField release];
	[super dealloc];
}

- (NSPrintInfo *)printInfo
{
	return _printInfo;
}

- (void)setPrintInfo:(NSPrintInfo *)printInfo
{
	NSPrintInfo *old = _printInfo;

	_printInfo = [printInfo retain];
	[old release];
}

/* ============================================================================================ *
 * THE ACCESSORY BAND.                                                                           *
 * ============================================================================================ */

- (NSView *)accessoryView
{
	return _accessoryView;
}

- (void)setAccessoryView:(NSView *)view
{
	NSView *old = _accessoryView;

	if (old != nil) {
		[old removeFromSuperview];
	}
	_accessoryView = [view retain];
	[old release];
	if (_accessoryView != nil && _modalWindow != nil) {
		[(NSView *)[(NSWindow *)_modalWindow contentView] addSubview:_accessoryView];
		[_accessoryView setFrame:NSMakeRect(AG_PAGE_LAYOUT_MARGIN, 56.0,
						    AG_PAGE_LAYOUT_WIDTH - 2.0 * AG_PAGE_LAYOUT_MARGIN, 40.0)];
	}
}

- (NSArray *)accessoryControllers
{
	return [NSArray arrayWithArray:_accessoryControllers];
}

- (void)addAccessoryController:(NSViewController *)controller
{
	if (controller == nil) {
		return;
	}
	if ([controller respondsToSelector:@selector(loadView)]) {
		[controller loadView];
	}
	[_accessoryControllers addObject:controller];
	if (_modalWindow != nil) {
		[(NSView *)[(NSWindow *)_modalWindow contentView] addSubview:[controller view]];
		[[controller view] setFrame:NSMakeRect(AG_PAGE_LAYOUT_MARGIN, 56.0,
						      AG_PAGE_LAYOUT_WIDTH - 2.0 * AG_PAGE_LAYOUT_MARGIN, 40.0)];
	}
}

- (void)removeAccessoryController:(NSViewController *)controller
{
	if (controller == nil) {
		return;
	}
	[[controller view] removeFromSuperview];
	[_accessoryControllers removeObject:controller];
}

/* ============================================================================================ *
 * THE FACE.                                                                                     *
 * ============================================================================================ */

- (NSTextField *)fn_label:(NSString *)text at:(NSRect)frame
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];

	[label setStringValue:text];
	[label setEditable:NO];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:NSRightTextAlignment];
	[(NSView *)[(NSWindow *)_modalWindow contentView] addSubview:label];
	return [label autorelease];
}

- (NSTextField *)fn_field:(NSRect)frame
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:frame];

	[field setEditable:YES];
	[field setBordered:YES];
	[field setBezeled:YES];
	[(NSView *)[(NSWindow *)_modalWindow contentView] addSubview:field];
	return [field autorelease];
}

- (void)fn_buildWindow
{
	NSView *content;
	NSPopUpButton *popup;
	NSButton *ok;
	NSButton *cancel;

	if (_modalWindow != nil) {
		return;
	}
	_modalWindow = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, AG_PAGE_LAYOUT_WIDTH,
								       AG_PAGE_LAYOUT_HEIGHT)
						  styleMask:NSTitledWindowMask
						    backing:NSBackingStoreBuffered
						      defer:NO];
	[(NSWindow *)_modalWindow setTitle:@"Page Setup"];
	[(NSWindow *)_modalWindow setReleasedWhenClosed:NO];
	[(NSWindow *)_modalWindow setFloatingPanel:YES];
	content = [(NSWindow *)_modalWindow contentView];
	/* **A WINDOW MADE BY `-initWithContentRect:…` HAS NO CONTENT VIEW UNTIL ONE IS SET.** MEASURED here: every
	 * control added to a nil content view was a no-op, the factory's `-release` freed it, and the next allocation
	 * reused its memory — which surfaced as an NSTextField receiving `-removeAllItems:`. */
	if (content == nil) {
		content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, AG_PAGE_LAYOUT_WIDTH, AG_PAGE_LAYOUT_HEIGHT)] autorelease];
		[(NSWindow *)_modalWindow setContentView:content];
	}

	[self fn_label:@"Paper:" at:NSMakeRect(AG_PAGE_LAYOUT_MARGIN, 196.0, 80.0, 18.0)];
	popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(100.0, 192.0, 244.0, 24.0) pullsDown:NO];
	_paperPopup = popup;
	[content addSubview:popup];
	[popup release];

	[self fn_label:@"Orientation:" at:NSMakeRect(AG_PAGE_LAYOUT_MARGIN, 162.0, 80.0, 18.0)];
	popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(100.0, 158.0, 140.0, 24.0) pullsDown:NO];
	[popup addItemWithTitle:@"Portrait"];
	[popup addItemWithTitle:@"Landscape"];
	_orientationPopup = popup;
	[content addSubview:popup];
	[popup release];

	[self fn_label:@"Top:" at:NSMakeRect(AG_PAGE_LAYOUT_MARGIN, 128.0, 60.0, 18.0)];
	_topField = [self fn_field:NSMakeRect(80.0, 124.0, 60.0, 20.0)];
	[self fn_label:@"Bottom:" at:NSMakeRect(152.0, 128.0, 60.0, 18.0)];
	_bottomField = [self fn_field:NSMakeRect(216.0, 124.0, 60.0, 20.0)];
	[self fn_label:@"Left:" at:NSMakeRect(AG_PAGE_LAYOUT_MARGIN, 100.0, 60.0, 18.0)];
	_leftField = [self fn_field:NSMakeRect(80.0, 96.0, 60.0, 20.0)];
	[self fn_label:@"Right:" at:NSMakeRect(152.0, 100.0, 60.0, 18.0)];
	_rightField = [self fn_field:NSMakeRect(216.0, 96.0, 60.0, 20.0)];

	cancel = [[NSButton alloc] initWithFrame:NSMakeRect(148.0, 16.0, 96.0, 26.0)];
	[cancel setTitle:@"Cancel"];
	[cancel setBezelStyle:NSRoundedBezelStyle];
	[cancel setTarget:self];
	[cancel setAction:@selector(fn_cancel:)];
	[content addSubview:cancel];
	[cancel release];

	ok = [[NSButton alloc] initWithFrame:NSMakeRect(248.0, 16.0, 96.0, 26.0)];
	[ok setTitle:@"OK"];
	[ok setBezelStyle:NSRoundedBezelStyle];
	[ok setTarget:self];
	[ok setAction:@selector(fn_ok:)];
	[content addSubview:ok];
	[ok release];

	if (_accessoryView != nil) {
		[content addSubview:_accessoryView];
		[_accessoryView setFrame:NSMakeRect(AG_PAGE_LAYOUT_MARGIN, 56.0,
						    AG_PAGE_LAYOUT_WIDTH - 2.0 * AG_PAGE_LAYOUT_MARGIN, 34.0)];
	}
	{
		NSUInteger i;

		for (i = 0; i < [_accessoryControllers count]; i++) {
			[content addSubview:[[_accessoryControllers objectAtIndex:i] view]];
		}
	}
}

/* ============================================================================================ *
 * THE TWO DIRECTIONS.                                                                           *
 * ============================================================================================ */

/* **THE PAPER LIST: THE QUEUE'S KEYWORDS FIRST, THEN THE STANDARD NAMES, BY FRIENDLY NAME.** A keyword the table does
 * not know is offered as itself, because a queue naming a paper this tier cannot measure is still a paper a person may
 * choose — and `-pageSizeForPaper:` answering zero for it is the honest consequence. */
- (void)fn_fillPaperPopup
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *standard = [NSPrinter cg_standardPaperNames];
	NSPrinter *printer = (_printInfo != nil) ? [_printInfo printer] : nil;
	NSUInteger i;

	if (printer != nil) {
		NSArray *keywords = [printer cg_mediaKeywords];

		for (i = 0; i < [keywords count]; i++) {
			NSString *friendly = [NSPrinter cg_paperNameForKeyword:[keywords objectAtIndex:i]];

			if (friendly != nil && ![names containsObject:friendly]) {
				[names addObject:friendly];
			}
		}
	}
	for (i = 0; i < [standard count]; i++) {
		if (![names containsObject:[standard objectAtIndex:i]]) {
			[names addObject:[standard objectAtIndex:i]];
		}
	}
	[(NSPopUpButton *)_paperPopup removeAllItems];
	for (i = 0; i < [names count]; i++) {
		[(NSPopUpButton *)_paperPopup addItemWithTitle:[names objectAtIndex:i]];
	}
}

- (void)readPrintInfo
{
	NSPrintInfo *info = _printInfo;

	if (info == nil) {
		return;
	}
	/* **THE DOOR BUILDS THE FACE IF IT IS NOT THERE**, so reading or writing a ticket does not require the panel to
	 * have been run — which is what Apple's two doors are for. */
	[self fn_buildWindow];
	[self fn_fillPaperPopup];
	if ([info paperName] != nil) {
		[(NSPopUpButton *)_paperPopup selectItemWithTitle:[info paperName]];
	}
	[(NSPopUpButton *)_orientationPopup selectItemAtIndex:([info orientation] == NSLandscapeOrientation) ? 1 : 0];
	[(NSTextField *)_topField setStringValue:[NSString stringWithFormat:@"%g", (double)[info topMargin]]];
	[(NSTextField *)_bottomField setStringValue:[NSString stringWithFormat:@"%g", (double)[info bottomMargin]]];
	[(NSTextField *)_leftField setStringValue:[NSString stringWithFormat:@"%g", (double)[info leftMargin]]];
	[(NSTextField *)_rightField setStringValue:[NSString stringWithFormat:@"%g", (double)[info rightMargin]]];
}

- (void)writePrintInfo
{
	NSPrintInfo *info = _printInfo;
	NSString *paper;

	if (info == nil) {
		return;
	}
	[self fn_buildWindow];
	paper = [(NSPopUpButton *)_paperPopup titleOfSelectedItem];
	if (paper != nil) {
		[info setPaperName:paper];
	}
	[info setOrientation:([(NSPopUpButton *)_orientationPopup indexOfSelectedItem] == 1)
		? NSLandscapeOrientation : NSPortraitOrientation];
	[info setTopMargin:(CGFloat)[[(NSTextField *)_topField stringValue] doubleValue]];
	[info setBottomMargin:(CGFloat)[[(NSTextField *)_bottomField stringValue] doubleValue]];
	[info setLeftMargin:(CGFloat)[[(NSTextField *)_leftField stringValue] doubleValue]];
	[info setRightMargin:(CGFloat)[[(NSTextField *)_rightField stringValue] doubleValue]];
}

/* ============================================================================================ *
 * THE SESSION.                                                                                  *
 * ============================================================================================ */

- (void)fn_ok:(id)sender
{
	(void)sender;
	[self writePrintInfo];
	[self fn_finishWithCode:NSOKButton];
}

- (void)fn_cancel:(id)sender
{
	(void)sender;
	[self fn_finishWithCode:NSCancelButton];
}

- (void)fn_finishWithCode:(NSInteger)code
{
	NSApplication *app = [NSApplication sharedApplication];

	if (_sheetParent != nil) {
		id delegate = _sheetDelegate;
		SEL didEnd = _sheetDidEnd;
		void *context = _sheetContext;

		[app endSheet:_modalWindow returnCode:code];
		[_modalWindow orderOut:nil];
		_sheetParent = nil;
		_sheetDelegate = nil;
		_sheetDidEnd = NULL;
		_sheetContext = NULL;
		if (didEnd != NULL) {
			typedef void (*AGPageLayoutDidEnd)(id, SEL, id, NSInteger, void *);

			((AGPageLayoutDidEnd)objc_msgSend)(delegate, didEnd, self, code, context);
		}
		/* **THE SESSION'S RETAIN GOES BACK AFTER THE REPLY, BECAUSE THE REPLY MAY DROP THE CALLER'S.** By the time the
		 * callback runs the sheet is ended and the panel is out of the way, so the caller is free to forget it — and a
		 * panel released BEFORE its own did-end ran would be a use-after-free in the callback it just called. The
		 * autorelease, rather than a release, is what keeps `self` alive for the rest of this method's own unwind. */
		[self autorelease];
		return;
	}
	[app stopModalWithCode:code];
}

- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)printInfo
{
	[self setPrintInfo:printInfo];
	return [self runModal];
}

- (NSInteger)runModal
{
	NSApplication *app = [NSApplication sharedApplication];

	if (_printInfo == nil) {
		[self setPrintInfo:[NSPrintInfo sharedPrintInfo]];
	}
	[self fn_buildWindow];
	[self readPrintInfo];
	if (![app isRunning]) {
		[self writePrintInfo];
		return NSOKButton;
	}
	[_modalWindow center];
	[_modalWindow makeKeyAndOrderFront:nil];
	{
		NSInteger code = [app runModalForWindow:_modalWindow];

		[_modalWindow orderOut:nil];
		[self writePrintInfo];
		return code;
	}
}

- (void)beginSheetWithPrintInfo:(NSPrintInfo *)printInfo
		 modalForWindow:(NSWindow *)docWindow
		       delegate:(id)delegate
		 didEndSelector:(SEL)didEndSelector
		  contextInfo:(void *)contextInfo
{
	NSApplication *app = [NSApplication sharedApplication];

	if (printInfo == nil) {
		printInfo = [NSPrintInfo sharedPrintInfo];
	}
	[self setPrintInfo:printInfo];
	[self fn_buildWindow];
	[self readPrintInfo];
	_sheetParent = docWindow;
	_sheetDelegate = delegate;
	_sheetDidEnd = didEndSelector;
	_sheetContext = contextInfo;
	/* **THE SESSION OWNS THE PANEL, SO THE CALLER DOES NOT HAVE TO.** `+printPanel`/`+pageLayout` answer an
	 * AUTORELEASED panel — Apple's factory idiom — and a sheet is ASYNCHRONOUS: it is still on the glass a run-loop pass
	 * later, when the pool that made the panel drains. A panel that died there released its window's views while the
	 * window was still attached and still displayed, and the next pass that walked that tree sent a message to freed
	 * memory — MEASURED as `SIGSEGV` inside `-[NSView cg_dirtyRegionRecursive:…]` (and, from a pointer motion, inside
	 * `-[NSView cg_rebuildStaleCursorRects]`, which is how it was reported). THIS RETAIN IS THE SESSION'S, and
	 * `-fn_finishWithCode:` gives it back where the session ends. */
	[self retain];
	/* **AND THE SESSION IS BEGUN WITH NO REPLY OF ITS OWN, BECAUSE THE PANEL IS THE ONE THAT REPLIES.** `-fn_finishWithCode:`
	 * calls the caller's did-end itself — after `-endSheet:returnCode:` and after ordering the panel out — so passing
	 * the caller's delegate here would call it twice: once by the application, once by this class. It is the same
	 * division `-beginModalSessionForWindow:relativeToWindow:` makes, and the FIVE arguments are the whole point:
	 * `-beginSheet:modalForWindow:` does not exist in this tier, and calling it raised
	 * `-[NSApplication beginSheet:modalForWindow:] is not implemented` the moment a person pressed a panel's Print or
	 * Page Setup button. MEASURED, from the gallery's own Print Panel button. */
	[app beginSheet:_modalWindow
	 modalForWindow:docWindow
	  modalDelegate:nil
	 didEndSelector:NULL
	    contextInfo:NULL];
}

@end
