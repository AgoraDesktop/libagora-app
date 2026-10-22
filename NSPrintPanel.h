/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSPrintPanel.h — THE DIALOG THAT TURNS A TICKET INTO A JOB.
 *
 * **THE PANEL IS NOT A WINDOW; IT OWNS ONE.** Apple's `NSPrintPanel` is an `NSObject` that runs a modal session over a
 * panel it builds, which is why every door here is about the SESSION and the TICKET rather than about views. The face is
 * the queue popup, copies, the page range, the disposition ("Print" / "Save as PDF" / "Preview") and the accessory band
 * a caller fills; the print button is the one that ends the session with `NSOKButton`.
 *
 * **THE PAGE RANGE IS THE ONE VALUE THE TICKET CANNOT HOLD.** Apple keeps it on `NSPrintOperation`, and the panel is
 * what collects it — so the panel keeps the range it read from its two fields and `NSPrintOperation` asks for it through
 * the `cg_` door at the foot of this header after the session ends. That is the tree's convention for a value a session
 * produces and a caller must read back.
 *
 * **THE ACCESSORY BAND HAS TWO SOURCES, AND THEY COMPOSE.** A view set through `-setAccessoryView:` sits at the band's
 * top; each accessory CONTROLLER's view (an `NSViewController` conforming to `NSPrintPanelAccessorizing`) is stacked
 * under it. That is Apple's model: the old one-view door and the controller list are both supported.
 *
 * WHAT THIS TIER DOES NOT DO: there is no preview pane (the era's `NSPrintPanelShowsPreview` option is recorded and not
 * obeyed), and "Save as PDF" needs `NSPrintSavePath` on the ticket — the operation names that rather than a save dialog
 * appearing from inside a print panel.
 *
 * Written from `NSPrintPanel.h` and `NSPrintPanelAccessorizing.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSPRINTPANEL_H
#define APPKIT_NSPRINTPANEL_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSArray;
@class NSMutableArray;
@class NSPrintInfo;
@class NSView;
@class NSViewController;
@class NSWindow;

NS_ASSUME_NONNULL_BEGIN

typedef NSUInteger NSPrintPanelOptions;

/* **THE OPTIONS WORD.** Only the ones this tier's face honours are listed with a behaviour; the rest are recorded so a
 * caller's constant round-trips. `NSPrintPanelShowsPreview` is recorded and NOT obeyed (see the header). */
enum {
	NSPrintPanelShowsCopies		= 1 << 0,
	NSPrintPanelShowsPageRange	= 1 << 1,
	NSPrintPanelShowsPaperSize	= 1 << 2,
	NSPrintPanelShowsOrientation	= 1 << 3,
	NSPrintPanelShowsScaling	= 1 << 4,
	NSPrintPanelShowsPrintSelection	= 1 << 5,
	NSPrintPanelShowsPageSetupAccessory = 1 << 8,
	NSPrintPanelShowsPreview	= 1 << 9
};

/* **THE ACCESSORY CONTROLLER'S PROTOCOL.** A summary is what the panel shows in its collapsed preview line; this tier
 * asks for it and draws nothing with it yet, which the header says rather than leaving a conformer to wonder. */
@protocol NSPrintPanelAccessorizing <NSObject>
@required
- (NSArray *)localizedSummaryItems;
@optional
- (nullable NSArray *)keyPathsForValuesAffectingPreview;
@end

@interface NSPrintPanel : NSObject
{
	NSPrintInfo *_printInfo;		/* RETAINED */
	NSPrintPanelOptions _options;
	NSString *_jobStyleHint;		/* RETAINED */
	NSString *_helpAnchor;			/* RETAINED */
	NSString *_defaultButtonTitle;		/* RETAINED */
	NSView *_accessoryView;			/* RETAINED */
	NSMutableArray *_accessoryControllers;	/* RETAINED */
	id _modalWindow;			/* RETAINED: the panel this object owns */
	id _printerPopup;			/* RETAINED */
	id _copiesField;			/* RETAINED */
	id _fromField;				/* RETAINED */
	id _toField;				/* RETAINED */
	id _dispositionPopup;			/* RETAINED */
	NSRange _pageRange;			/* what the session collected */
	/* THE SHEET'S REPLY, when the session was begun as one. */
	id _sheetParent;			/* ASSIGN */
	id _sheetDelegate;			/* ASSIGN */
	SEL _sheetDidEnd;
	void *_sheetContext;
}

+ (NSPrintPanel *)printPanel;

/* THE TICKET THE PANEL EDITS, AND THE OPTIONS THAT DECIDE WHICH CONTROLS IT SHOWS. */
- (nullable NSPrintInfo *)printInfo;
- (void)setPrintInfo:(NSPrintInfo *)printInfo;
- (NSPrintPanelOptions)options;
- (void)setOptions:(NSPrintPanelOptions)options;

/* THE FACE'S THREE STRINGS. */
- (nullable NSString *)jobStyleHint;
- (void)setJobStyleHint:(nullable NSString *)hint;
- (nullable NSString *)helpAnchor;
- (void)setHelpAnchor:(nullable NSString *)anchor;
- (nullable NSString *)defaultButtonTitle;
- (void)setDefaultButtonTitle:(nullable NSString *)title;

/* THE ACCESSORY BAND. */
- (nullable NSView *)accessoryView;
- (void)setAccessoryView:(nullable NSView *)view;
- (NSArray *)accessoryControllers;
- (void)addAccessoryController:(NSViewController<NSPrintPanelAccessorizing> *)controller;
- (void)removeAccessoryController:(NSViewController<NSPrintPanelAccessorizing> *)controller;

/* **THE TWO WAYS TO RUN IT.** Modal returns `NSOKButton` or `NSCancelButton`; the sheet form calls back on the delegate
 * with the same code after the panel has been dismissed. A program with no run loop gets the modal answer WITHOUT a
 * session — the panel's current values are applied and `NSOKButton` returned — which is the same guard the tree's menu,
 * field and alert sessions carry. */
- (NSInteger)runModal;
- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)printInfo;
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)printInfo
		 modalForWindow:(NSWindow *)docWindow
		       delegate:(nullable id)delegate
		 didEndSelector:(nullable SEL)didEndSelector
		  contextInfo:(nullable void *)contextInfo;

/* THE TWO DOORS THAT MOVE VALUES BETWEEN THE TICKET AND THE CONTROLS — public because Apple publishes them. */
- (void)updateFromPrintInfo;
- (void)finalWritePrintInfo;

/* **THE INSTRUMENT'S DOOR, NOT APPLE'S**: the range the fields collected. `NSPrintOperation` reads it after a session,
 * and a probe reads it to assert what a session would have applied. */
- (NSRange)cg_pageRange;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPRINTPANEL_H */
