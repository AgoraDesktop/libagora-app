/*
 * NSPrintPanel — the dialog that turns a ticket into a job.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE FACE IS BUILT ONCE AND LIVES IN A PANEL THIS OBJECT OWNS.** `-fn_buildWindow` makes the window, the queue popup,
 * copies, the two page fields, the disposition popup, the accessory band and the two buttons; `-updateFromPrintInfo`
 * fills them from the ticket and `-finalWritePrintInfo` writes them back. The session's only interesting rule is the
 * no-run-loop answer: a program with no event source gets `NSOKButton` with the current values applied, which is the
 * same guard the menu, field and alert sessions carry.
 */
#import <AppKit/NSPrintPanel.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSPrinter.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <AppKit/NSViewController.h>
#import <AppKit/NSWindow.h>

#include <objc/message.h>

#define AG_PRINT_PANEL_WIDTH  400.0
#define AG_PRINT_PANEL_HEIGHT 320.0
#define AG_PRINT_PANEL_MARGIN  16.0

@interface NSPrintPanel ()
- (void)fn_buildWindow;
- (void)fn_layoutAccessories;
- (void)fn_ok:(id)sender;
- (void)fn_cancel:(id)sender;
- (void)fn_finishWithCode:(NSInteger)code;
@end

@implementation NSPrintPanel

+ (NSPrintPanel *)printPanel
{
	return [[[self alloc] init] autorelease];
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_options = (NSPrintPanelShowsCopies | NSPrintPanelShowsPageRange | NSPrintPanelShowsPaperSize |
			    NSPrintPanelShowsOrientation | NSPrintPanelShowsScaling);
		_accessoryControllers = [[NSMutableArray alloc] init];
		_pageRange = NSMakeRange(0, 0);	/* 0,0 means "all pages" */
	}
	return self;
}

- (void)dealloc
{
	[_printInfo release];
	[_jobStyleHint release];
	[_helpAnchor release];
	[_defaultButtonTitle release];
	[_accessoryView release];
	[_accessoryControllers release];
	[_modalWindow release];
	[_printerPopup release];
	[_copiesField release];
	[_fromField release];
	[_toField release];
	[_dispositionPopup release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE TICKET AND THE OPTIONS.                                                                   *
 * ============================================================================================ */

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

- (NSPrintPanelOptions)options
{
	return _options;
}

- (void)setOptions:(NSPrintPanelOptions)options
{
	_options = options;
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

- (NSString *)helpAnchor
{
	return _helpAnchor;
}

- (void)setHelpAnchor:(NSString *)anchor
{
	NSString *old = _helpAnchor;

	_helpAnchor = [anchor copy];
	[old release];
}

- (NSString *)defaultButtonTitle
{
	return (_defaultButtonTitle != nil) ? _defaultButtonTitle : @"Print";
}

- (void)setDefaultButtonTitle:(NSString *)title
{
	NSString *old = _defaultButtonTitle;

	_defaultButtonTitle = [title copy];
	[old release];
	if (_modalWindow != nil) {
		NSButton *ok = (NSButton *)[(NSView *)[(NSWindow *)_modalWindow contentView] viewWithTag:1];

		[ok setTitle:[self defaultButtonTitle]];
	}
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
		[self fn_layoutAccessories];
	}
}

- (NSArray *)accessoryControllers
{
	return [NSArray arrayWithArray:_accessoryControllers];
}

- (void)addAccessoryController:(NSViewController<NSPrintPanelAccessorizing> *)controller
{
	if (controller == nil) {
		return;
	}
	[_accessoryControllers addObject:controller];
	if ([controller respondsToSelector:@selector(loadView)]) {
		[controller loadView];
	}
	if (_modalWindow != nil && [controller isKindOfClass:[NSViewController class]]) {
		[(NSView *)[(NSWindow *)_modalWindow contentView] addSubview:[controller view]];
	}
	[self fn_layoutAccessories];
}

- (void)removeAccessoryController:(NSViewController<NSPrintPanelAccessorizing> *)controller
{
	if (controller == nil) {
		return;
	}
	[[controller view] removeFromSuperview];
	[_accessoryControllers removeObject:controller];
	[self fn_layoutAccessories];
}

/* **THE BAND STACKS: the one view at the top, then each controller's view under it, fourty-four points apiece.** A
 * controller whose view is taller than that is clipped rather than overlapping its neighbour, because the band's height
 * is the panel's and not a caller's. */
- (void)fn_layoutAccessories
{
	CGFloat top = 116.0;
	CGFloat stack = 56.0;
	NSUInteger i;

	if (_accessoryView != nil) {
		[_accessoryView setFrame:NSMakeRect(AG_PRINT_PANEL_MARGIN, top, AG_PRINT_PANEL_WIDTH - 2.0 * AG_PRINT_PANEL_MARGIN,
						    50.0)];
		top -= 54.0;
	}
	for (i = 0; i < [_accessoryControllers count]; i++) {
		NSViewController *controller = [_accessoryControllers objectAtIndex:i];

		[[controller view] setFrame:NSMakeRect(AG_PRINT_PANEL_MARGIN, stack,
						      AG_PRINT_PANEL_WIDTH - 2.0 * AG_PRINT_PANEL_MARGIN, 44.0)];
		stack += 46.0;
	}
	(void)top;
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

- (void)fn_buildWindow
{
	NSView *content;
	NSButton *ok;
	NSButton *cancel;
	NSPopUpButton *popup;
	NSTextField *field;

	if (_modalWindow != nil) {
		return;
	}
	_modalWindow = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, AG_PRINT_PANEL_WIDTH,
								       AG_PRINT_PANEL_HEIGHT)
						  styleMask:NSTitledWindowMask
						    backing:NSBackingStoreBuffered
						      defer:NO];
	[(NSWindow *)_modalWindow setTitle:@"Print"];
	[(NSWindow *)_modalWindow setReleasedWhenClosed:NO];
	[(NSWindow *)_modalWindow setFloatingPanel:YES];
	content = [(NSWindow *)_modalWindow contentView];
	/* **A WINDOW MADE BY `-initWithContentRect:…` HAS NO CONTENT VIEW UNTIL ONE IS SET.** MEASURED here: every
	 * control added to a nil content view was a no-op, the factory's `-release` freed it, and the next allocation
	 * reused its memory — which surfaced as an NSTextField receiving `-removeAllItems:`. */
	if (content == nil) {
		content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, AG_PRINT_PANEL_WIDTH, AG_PRINT_PANEL_HEIGHT)] autorelease];
		[(NSWindow *)_modalWindow setContentView:content];
	}

	[self fn_label:@"Printer:" at:NSMakeRect(AG_PRINT_PANEL_MARGIN, 276.0, 80.0, 18.0)];
	popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(100.0, 272.0, 284.0, 24.0) pullsDown:NO];
	_printerPopup = popup;
	[content addSubview:popup];
	[popup release];

	[self fn_label:@"Copies:" at:NSMakeRect(AG_PRINT_PANEL_MARGIN, 244.0, 80.0, 18.0)];
	field = [[NSTextField alloc] initWithFrame:NSMakeRect(100.0, 240.0, 60.0, 20.0)];
	[field setEditable:YES];
	[field setBordered:YES];
	[field setBezeled:YES];
	_copiesField = field;
	[content addSubview:field];
	[field release];

	[self fn_label:@"Pages:" at:NSMakeRect(AG_PRINT_PANEL_MARGIN, 212.0, 80.0, 18.0)];
	field = [[NSTextField alloc] initWithFrame:NSMakeRect(100.0, 208.0, 50.0, 20.0)];
	[field setEditable:YES];
	[field setBezeled:YES];
	_fromField = field;
	[content addSubview:field];
	[field release];
	[self fn_label:@"to" at:NSMakeRect(156.0, 212.0, 20.0, 18.0)];
	field = [[NSTextField alloc] initWithFrame:NSMakeRect(178.0, 208.0, 50.0, 20.0)];
	[field setEditable:YES];
	[field setBezeled:YES];
	_toField = field;
	[content addSubview:field];
	[field release];

	[self fn_label:@"Output:" at:NSMakeRect(AG_PRINT_PANEL_MARGIN, 180.0, 80.0, 18.0)];
	popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(100.0, 176.0, 180.0, 24.0) pullsDown:NO];
	[popup addItemWithTitle:@"Print"];
	[popup addItemWithTitle:@"Save as PDF"];
	[popup addItemWithTitle:@"Preview"];
	_dispositionPopup = popup;
	[content addSubview:popup];
	[popup release];

	cancel = [[NSButton alloc] initWithFrame:NSMakeRect(188.0, 16.0, 96.0, 26.0)];
	[cancel setTitle:@"Cancel"];
	[cancel setBezelStyle:NSRoundedBezelStyle];
	[cancel setTarget:self];
	[cancel setAction:@selector(fn_cancel:)];
	[cancel setTag:2];
	[content addSubview:cancel];
	[cancel release];

	ok = [[NSButton alloc] initWithFrame:NSMakeRect(292.0, 16.0, 96.0, 26.0)];
	[ok setTitle:[self defaultButtonTitle]];
	[ok setBezelStyle:NSRoundedBezelStyle];
	[ok setTarget:self];
	[ok setAction:@selector(fn_ok:)];
	[ok setTag:1];
	[content addSubview:ok];
	[ok release];

	if (_accessoryView != nil) {
		[content addSubview:_accessoryView];
	}
	{
		NSUInteger i;

		for (i = 0; i < [_accessoryControllers count]; i++) {
			NSViewController *controller = [_accessoryControllers objectAtIndex:i];

			if ([controller respondsToSelector:@selector(loadView)]) {
				[controller loadView];
			}
			[content addSubview:[controller view]];
		}
	}
	[self fn_layoutAccessories];
}

/* ============================================================================================ *
 * THE TWO DIRECTIONS BETWEEN THE TICKET AND THE CONTROLS.                                       *
 * ============================================================================================ */

- (void)updateFromPrintInfo
{
	NSPrintInfo *info = _printInfo;
	NSArray *printerNames;
	NSUInteger i;

	if (info == nil) {
		return;
	}
	[self fn_buildWindow];
	printerNames = [NSPrinter printerNames];
	[(NSPopUpButton *)_printerPopup removeAllItems];
	for (i = 0; i < [printerNames count]; i++) {
		[(NSPopUpButton *)_printerPopup addItemWithTitle:[printerNames objectAtIndex:i]];
	}
	if ([printerNames count] == 0) {
		[(NSPopUpButton *)_printerPopup addItemWithTitle:@"No printers"];
	} else {
		NSPrinter *printer = [info printer];

		if (printer != nil) {
			[(NSPopUpButton *)_printerPopup selectItemWithTitle:[printer name]];
		}
	}
	{
		NSNumber *copies = [[info dictionary] objectForKey:NSPrintCopies];

		[(NSTextField *)_copiesField setStringValue:[NSString stringWithFormat:@"%d",
			(int)((copies != nil) ? [copies integerValue] : 1)]];
	}
	[(NSTextField *)_fromField setStringValue:(_pageRange.length > 0)
		? [NSString stringWithFormat:@"%d", (int)_pageRange.location] : @""];
	[(NSTextField *)_toField setStringValue:(_pageRange.length > 0)
		? [NSString stringWithFormat:@"%d", (int)NSMaxRange(_pageRange) - 1] : @""];

	if ([[info jobDisposition] isEqual:NSPrintSaveJob]) {
		[(NSPopUpButton *)_dispositionPopup selectItemAtIndex:1];
	} else if ([[info jobDisposition] isEqual:NSPrintPreviewJob]) {
		[(NSPopUpButton *)_dispositionPopup selectItemAtIndex:2];
	} else {
		[(NSPopUpButton *)_dispositionPopup selectItemAtIndex:0];
	}
	/* THE OPTIONS WORD DECIDES WHICH CONTROLS ARE SHOWN, which is the one reader it has. */
	[(NSTextField *)_copiesField setHidden:((_options & NSPrintPanelShowsCopies) == 0)];
	[(NSTextField *)_fromField setHidden:((_options & NSPrintPanelShowsPageRange) == 0)];
	[(NSTextField *)_toField setHidden:((_options & NSPrintPanelShowsPageRange) == 0)];
}

- (void)finalWritePrintInfo
{
	NSPrintInfo *info = _printInfo;
	NSString *title;
	NSInteger index;
	NSInteger fromValue;
	NSInteger toValue;

	if (info == nil) {
		return;
	}
	[self fn_buildWindow];
	title = [(NSPopUpButton *)_printerPopup titleOfSelectedItem];
	if (title != nil && [title isEqual:@"No printers"] == NO) {
		NSPrinter *printer = [NSPrinter printerWithName:title];

		if (printer != nil) {
			[info setPrinter:printer];
		}
	}
	{
		NSInteger copies = [[(NSTextField *)_copiesField stringValue] integerValue];

		[[info dictionary] setObject:[NSNumber numberWithInteger:(copies > 0 ? copies : 1)]
				      forKey:NSPrintCopies];
	}
	fromValue = [[(NSTextField *)_fromField stringValue] integerValue];
	toValue = [[(NSTextField *)_toField stringValue] integerValue];
	if (fromValue > 0 && toValue >= fromValue) {
		_pageRange = NSMakeRange((NSUInteger)fromValue, (NSUInteger)(toValue - fromValue + 1));
	} else {
		_pageRange = NSMakeRange(0, 0);
	}
	index = [(NSPopUpButton *)_dispositionPopup indexOfSelectedItem];
	if (index == 1) {
		[info setJobDisposition:NSPrintSaveJob];
	} else if (index == 2) {
		[info setJobDisposition:NSPrintPreviewJob];
	} else {
		[info setJobDisposition:NSPrintSpoolJob];
	}
}

- (NSRange)cg_pageRange
{
	return _pageRange;
}

/* ============================================================================================ *
 * THE SESSION.                                                                                  *
 * ============================================================================================ */

- (void)fn_ok:(id)sender
{
	(void)sender;
	[self finalWritePrintInfo];
	[self fn_finishWithCode:NSOKButton];
}

- (void)fn_cancel:(id)sender
{
	(void)sender;
	if (_printInfo != nil) {
		[_printInfo setJobDisposition:NSPrintCancelJob];
	}
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
			typedef void (*AGPrintPanelDidEnd)(id, SEL, id, NSInteger, void *);

			((AGPrintPanelDidEnd)objc_msgSend)(delegate, didEnd, self, code, context);
		}
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
	[self updateFromPrintInfo];
	/* **A PROGRAM WITH NO RUN LOOP HAS NO SESSION TO RUN**: the current values are applied and the panel answers OK,
	 * the same guard the menu, field and alert sessions carry. */
	if (![app isRunning]) {
		[self finalWritePrintInfo];
		return NSOKButton;
	}
	[_modalWindow center];
	[_modalWindow makeKeyAndOrderFront:nil];
	{
		NSInteger code = [app runModalForWindow:_modalWindow];

		[_modalWindow orderOut:nil];
		[self finalWritePrintInfo];
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
	[self updateFromPrintInfo];
	_sheetParent = docWindow;
	_sheetDelegate = delegate;
	_sheetDidEnd = didEndSelector;
	_sheetContext = contextInfo;
	[app beginSheet:_modalWindow modalForWindow:docWindow];
}

@end
