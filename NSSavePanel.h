/*
 * NSSavePanel.h — A PANEL OVER THE FILE SYSTEM: WHERE TO SAVE, OR WHAT TO OPEN.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A SAVE PANEL IS A FILE BROWSER THAT RETURNS A URL.** It is a real `NSPanel` (so it floats, hides on deactivate and is
 * never main), with the era's shape: a directory path at the top, a list of what is in it, a name field and two buttons.
 * `NSOpenPanel` is the same machine with the open panel's flags — one or many files, files or directories — and a
 * different default prompt. The result is `-URL` (and `-URLs` for a multi-file open), and `-runModal` answers `NSOKButton`
 * or `NSCancelButton`.
 *
 * **THE THREE WAYS TO RUN IT ARE THE THREE THE ERA OFFERS.** `-runModal` runs an application-modal session and returns the
 * answer; `-beginSheetModalForWindow:completionHandler:` attaches it to a window as a sheet and calls the block with the
 * answer; `-beginWithCompletionHandler:` shows it modelessly and calls the block when it is dismissed. The deprecated
 * `-beginSheetForDirectory:…modalDelegate:didEndSelector:contextInfo:` and `-runModalForDirectory:file:` forward to the
 * same code, so a 10.3-shaped caller works.
 *
 * **THE LISTING IS FILTERED BY THE DELEGATE AND BY THE ALLOWED TYPES, AND THE FILTER IS REAL.** `-panel:shouldShowFilename:`
 * and `-panel:shouldEnableURL:` both remove an entry from the list (this tier's table has no disabled row, so "do not
 * enable" is "do not show", stated rather than silently inventing a grey state); the open panel additionally keeps only the
 * extensions in `-allowedFileTypes` unless `-allowsOtherFileTypes` is YES. `-panel:compareFilename:with:caseSensitive:`
 * sorts the list when the delegate answers it, `-panel:isValidFilename:` and `-panel:validateURL:error:` veto an accept,
 * `-panel:userEnteredFilename:confirmed:` may rename it, `-panel:didChangeToDirectoryURL:` and the deprecated
 * `-panel:directoryDidChange:` hear navigation, and `-panelSelectionDidChange:` hears a selection.
 *
 * **WHAT THIS TIER DOES NOT DO, NAMED.** There is no expanded save panel (`-isExpanded`/`-setExpanded:` are not declared),
 * no file packages (`-treatsFilePackagesAsDirectories` is not declared), no sidebar, no icon grid and no replacement
 * confirmation: the panel accepts an existing file's URL and the caller's save overwrites it. The sandbox powerbox and
 * iCloud are refused by their absence, as the plan says. The accessory view gets a fixed 44-point band at the bottom.
 *
 * **AND THE PANEL IS ONE CLASS WITH THE OPEN PANEL'S BITS IN IT.** `NSOpenPanel` is a subclass that exposes the flags; the
 * accepted results and the flags live here, so there is one browser, one accept path and one place a result is set.
 */
#ifndef APPKIT_NSSAVEPANEL_H
#define APPKIT_NSSAVEPANEL_H

#import <AppKit/NSPanel.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray, NSError, NSString, NSURL, NSView, NSWindow;
@class NSButton, NSScrollView, NSTableView, NSTextField;
@protocol NSOpenSavePanelDelegate;

/* AND THE SAVE PANEL'S OWN SPELLINGS OF THE SAME TWO ANSWERS. */
enum {
	NSFileHandlingPanelCancelButton = NSCancelButton,
	NSFileHandlingPanelOKButton = NSOKButton
};

/* ==================================================================================================================
 * THE DELEGATE.
 *
 * The six modern methods of the era's protocol, minus `-panel:willExpand:` — this tier has no expanded pane, and a
 * protocol message nobody can be sent is a contract nobody can honour. The four deprecated informal methods are in the
 * category below, because that is where Apple declares them.
 * ================================================================================================================ */

@protocol NSOpenSavePanelDelegate <NSObject>
@optional
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url;
- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)outError;
- (void)panel:(id)sender didChangeToDirectoryURL:(NSURL *)url;
- (nullable NSString *)panel:(id)sender userEnteredFilename:(NSString *)filename confirmed:(BOOL)okFlag;
- (void)panelSelectionDidChange:(id)sender;
@end

/* THE 10.2 INFORMAL HOOKS, declared where Apple declares them. `-panel:shouldShowFilename:` takes a PATH and is asked
 * before `-panel:shouldEnableURL:`; `-panel:directoryDidChange:` takes the path and is asked beside the URL door. */
@interface NSObject (NSSavePanelDelegateDeprecated)
- (BOOL)panel:(id)sender isValidFilename:(NSString *)filename;
- (void)panel:(id)sender directoryDidChange:(NSString *)path;
- (NSComparisonResult)panel:(id)sender compareFilename:(NSString *)name1 with:(NSString *)name2
	       caseSensitive:(BOOL)caseSensitive;
- (BOOL)panel:(id)sender shouldShowFilename:(NSString *)filename;
@end

@interface NSSavePanel : NSPanel
{
	NSURL *_directoryURL;		/* RETAINED: where the list is looking */
	NSURL *_url;			/* RETAINED: the accepted file (save) or the first accepted URL (open) */
	NSArray *_urls;			/* RETAINED: every accepted URL (open panel, multiple selection) */
	NSArray *_allowedFileTypes;	/* RETAINED: extensions, no dot */
	NSString *_requiredFileType;	/* RETAINED: the deprecated forced extension */
	NSString *_prompt;		/* RETAINED: the OK button's title */
	NSString *_nameFieldLabel;	/* RETAINED */
	NSString *_message;		/* RETAINED: the line under the title */
	NSView *_accessoryView;		/* RETAINED: in the 44-point band */
	id _panelDelegate;		/* ASSIGNED, the tree's rule for delegates; `_delegate` is NSWindow's */
	NSArray *_entries;		/* RETAINED: dictionaries with `name` and `dir` */
	NSTableView *_table;
	NSScrollView *_scroll;
	NSTextField *_nameField;
	NSTextField *_nameLabel;
	NSTextField *_pathLabel;
	NSTextField *_messageLabel;
	NSButton *_okButton;
	NSButton *_cancelButton;
	NSButton *_upButton;
	NSButton *_newFolderButton;
	NSButton *_extensionButton;
	id _source;			/* RETAINED: the table's data source and delegate */
	id _completionHandler;		/* RETAINED (copied) block */
	NSInteger _modalReturnCode;
	BOOL _runningModal;
	BOOL _sessionRetained;
	NSWindow *_sheetParent;		/* NOT RETAINED: the window the sheet is attached to */
	BOOL _isOpenPanel;
	BOOL _allowsOtherFileTypes;
	BOOL _canCreateDirectories;
	BOOL _canSelectHiddenExtension;
	BOOL _extensionHidden;
	BOOL _showsHiddenFiles;
	/* THE OPEN PANEL'S BITS, in the base so the one accept path can read them. */
	BOOL _canChooseFiles;
	BOOL _canChooseDirectories;
	BOOL _allowsMultipleSelection;
	BOOL _resolvesAliases;
}

+ (NSSavePanel *)savePanel;

/* ---- THE RESULT AND WHERE IT CAME FROM ------------------------------------------------------------- */

- (nullable NSURL *)URL;
- (nullable NSURL *)directoryURL;
- (void)setDirectoryURL:(nullable NSURL *)url;

/* ---- THE LIST AND ITS FILTER ---------------------------------------------------------------------- */

- (nullable NSArray *)allowedFileTypes;
- (void)setAllowedFileTypes:(nullable NSArray *)types;
- (BOOL)allowsOtherFileTypes;
- (void)setAllowsOtherFileTypes:(BOOL)flag;
- (BOOL)showsHiddenFiles;
- (void)setShowsHiddenFiles:(BOOL)flag;
- (void)validateVisibleColumns;

/* ---- THE PANEL'S PIECES --------------------------------------------------------------------------- */

- (nullable NSView *)accessoryView;
- (void)setAccessoryView:(nullable NSView *)view;
- (nullable id <NSOpenSavePanelDelegate>)delegate;
- (void)setDelegate:(nullable id <NSOpenSavePanelDelegate>)delegate;
- (BOOL)canCreateDirectories;
- (void)setCanCreateDirectories:(BOOL)flag;
- (BOOL)canSelectHiddenExtension;
- (void)setCanSelectHiddenExtension:(BOOL)flag;
- (BOOL)isExtensionHidden;
- (void)setExtensionHidden:(BOOL)flag;
- (nullable NSString *)prompt;
- (void)setPrompt:(nullable NSString *)prompt;
- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)title;
- (nullable NSString *)nameFieldLabel;
- (void)setNameFieldLabel:(nullable NSString *)label;
- (nullable NSString *)nameFieldStringValue;
- (void)setNameFieldStringValue:(nullable NSString *)value;
- (nullable NSString *)message;
- (void)setMessage:(nullable NSString *)message;

/* ---- RUNNING IT ----------------------------------------------------------------------------------- */

- (void)ok:(nullable id)sender;
- (void)cancel:(nullable id)sender;
- (void)beginSheetModalForWindow:(NSWindow *)window
	      completionHandler:(nullable void (^)(NSInteger result))handler;
- (void)beginWithCompletionHandler:(nullable void (^)(NSInteger result))handler;
- (NSInteger)runModal;
- (void)selectText:(nullable id)sender;

/* ---- THE 10.3 SPELLINGS --------------------------------------------------------------------------- */

- (nullable NSString *)filename;
- (nullable NSString *)directory;
- (void)setDirectory:(nullable NSString *)path;
- (nullable NSString *)requiredFileType;
- (void)setRequiredFileType:(nullable NSString *)type;
- (void)beginSheetForDirectory:(nullable NSString *)path file:(nullable NSString *)name
		modalForWindow:(NSWindow *)docWindow modalDelegate:(nullable id)delegate
	       didEndSelector:(nullable SEL)didEndSelector contextInfo:(nullable void *)contextInfo;
- (NSInteger)runModalForDirectory:(nullable NSString *)path file:(nullable NSString *)name;

/* ---- THE INSTRUMENT'S DOORS (cg_, NOT APPLE'S) ---------------------------------------------------- */

/* What the list shows, in display form (a directory carries a trailing slash), and a way to select rows as a click
 * would. They exist because the panel's result depends on the LISTING, and a probe that can only see `-URL` cannot tell
 * a filtered entry from one that was never there. */
- (NSArray *)cg_visibleFilenames;
- (BOOL)cg_selectFilename:(NSString *)name;
- (BOOL)cg_selectFilenames:(NSArray *)names;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSAVEPANEL_H */
