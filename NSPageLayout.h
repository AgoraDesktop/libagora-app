/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSPageLayout.h — THE DIALOG THAT EDITS THE PAGE: PAPER, ORIENTATION, MARGINS.
 *
 * **IT EDITS A TICKET'S PAGE HALF AND NOTHING ELSE.** The queue, copies and disposition belong to `NSPrintPanel`; this
 * panel's four controls are the paper (a list of the sizes the printer or the built-in table knows), portrait versus
 * landscape, and the four margins. `-readPrintInfo` fills them from the ticket and `-writePrintInfo` writes them back —
 * the two doors Apple publishes, and the only ones a caller needs besides running it.
 *
 * **THE PAPER LIST IS THE PRINTER'S WHEN THERE IS ONE.** A queue's media keywords are offered first (mapped to the
 * friendly names `NSPrinter` knows), and the built-in list fills the rest, so the panel never shows an empty popup on a
 * machine with no queues.
 *
 * Written from `NSPageLayout.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSPAGELAYOUT_H
#define APPKIT_NSPAGELAYOUT_H

#import <Foundation/NSObject.h>

@class NSArray;
@class NSMutableArray;
@class NSPrintInfo;
@class NSView;
@class NSViewController;
@class NSWindow;

NS_ASSUME_NONNULL_BEGIN

@interface NSPageLayout : NSObject
{
	NSPrintInfo *_printInfo;		/* RETAINED */
	NSView *_accessoryView;			/* RETAINED */
	NSMutableArray *_accessoryControllers;	/* RETAINED */
	id _modalWindow;			/* RETAINED */
	id _paperPopup;				/* RETAINED */
	id _orientationPopup;			/* RETAINED */
	id _topField;				/* RETAINED */
	id _bottomField;			/* RETAINED */
	id _leftField;				/* RETAINED */
	id _rightField;				/* RETAINED */
	id _sheetParent;			/* ASSIGN */
	id _sheetDelegate;			/* ASSIGN */
	SEL _sheetDidEnd;
	void *_sheetContext;
}

+ (NSPageLayout *)pageLayout;

- (nullable NSPrintInfo *)printInfo;
- (void)setPrintInfo:(NSPrintInfo *)printInfo;

- (nullable NSView *)accessoryView;
- (void)setAccessoryView:(nullable NSView *)view;
- (NSArray *)accessoryControllers;
- (void)addAccessoryController:(NSViewController *)controller;
- (void)removeAccessoryController:(NSViewController *)controller;

/* THE TWO DIRECTIONS BETWEEN THE TICKET AND THE CONTROLS. */
- (void)readPrintInfo;
- (void)writePrintInfo;

/* THE SESSION: modal, or a sheet that calls the delegate back with the reply code. */
- (NSInteger)runModal;
- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)printInfo;
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)printInfo
		 modalForWindow:(NSWindow *)docWindow
		       delegate:(nullable id)delegate
		 didEndSelector:(nullable SEL)didEndSelector
		  contextInfo:(nullable void *)contextInfo;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPAGELAYOUT_H */
