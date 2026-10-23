/*
 * NSDocument.h — A FILE, THE TEXT OF ITS CONTENTS, ITS CHANGE COUNT, AND THE WINDOWS THAT SHOW IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A DOCUMENT IS A FILE PLUS THE HISTORY OF ITS EDITS.** That is the whole model: a URL, a type, a modification date, a
 * CHANGE COUNT that answers `-isDocumentEdited`, an undo manager that moves that count as the user undoes and redoes, and
 * an ordered list of window controllers. The controller (`NSDocumentController`) makes, opens, remembers and closes them;
 * this class owns one document's contents and the hooks a subclass overrides to read and write them.
 *
 * **THE SUBCLASS OVERRIDES THE DATA PAIR, AND THE URL DOORS ARE THE FRAME AROUND IT.** A plain data document overrides
 * `-readFromData:ofType:error:` and `-dataOfType:error:` and nothing else; the default `-readFromURL:` builds an
 * `NSFileWrapper` and hands its `-regularFileContents` to the data door, and the default `-writeToURL:ofType:error:` asks
 * `-fileWrapperOfType:error:` for a wrapper around that data. A PACKAGE document overrides the wrapper pair instead. Both
 * paths are the era's, in the era's order, and `tests/document.m` drives a data document all the way around a temp file.
 *
 * **THE DEPRECATED (10.3) FILE DOORS FORWARD TO THE URL ONES**, so a caller that still spells `-initWithContentsOfFile:`
 * or `-writeToFile:ofType:` reaches the same code. The one compatibility hook that is honoured is the modern data pair's
 * fallback to `-loadDataRepresentation:ofType:` / `-dataRepresentationOfType:` — that is what makes a 10.3-shaped subclass
 * work at all. A subclass that overrides only a deprecated URL door is NOT consulted by the modern one; the header says so
 * at the pair rather than leaving it to be discovered.
 *
 * **THE PRINT DOORS LANDED WITH THE PRINT SYSTEM, AND THEY ARE REAL.** A document's ticket is its own (`-printInfo`,
 * made from the shared one on first ask), `-printOperationWithSettings:error:` builds an operation over the document's
 * window content, `-printDocument:` shows the panel, `-printShowingPrintPanel:` does not have to, and the two
 * `runModal…` doors are the page-layout and operation sheets. A subclass that draws its own pages overrides
 * `-printOperationWithSettings:error:` and keeps everything else.
 *
 * **AUTOSAVE, THE SAVE PANEL, CLOSE REVIEW, PAGE LAYOUT AND THE ERROR CHAIN ARE HERE NOW.** Autosave writes a
 * separate contents file and asks the owning controller for its location and its crash-time registry; the save panel
 * records its chosen name and hidden-extension answer; close is an asynchronous Save/Cancel/Don't Save review; page
 * layout uses the existing panel with the `-preparePageLayout:`/`-shouldChangePrintInfo:` hooks; and errors walk
 * document -> controller -> application. The scripting suite is still absent, so its three doors refuse by name.
 *
 * **THE CHANGE COUNT IS THE DOCUMENT'S, NOT THE UNDO MANAGER'S.** `-updateChangeCount:` is the one writer; the document
 * registers for the undo manager's did-undo/did-redo notifications so the count follows an undo the application never
 * mentioned, and `-isDocumentEdited` is a harmless predicate over it. The window controllers are told the edited state
 * whenever the predicate moves, which is what puts the dot in a title bar.
 */
#ifndef APPKIT_NSDOCUMENT_H
#define APPKIT_NSDOCUMENT_H

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <AppKit/NSUserInterfaceValidation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSData, NSDate, NSDictionary, NSError, NSFileWrapper, NSPageLayout, NSPrintInfo, NSPrintOperation, NSString, NSUndoManager, NSURL, NSWindow, NSWindowController;

/* WHAT A CHANGE DID, in Apple's order and with Apple's numbers. `NSChangeRedone` is the 10.5 addition and sits at 5 because
 * 4 was already `NSChangeAutosaved`. */
typedef NSUInteger NSDocumentChangeType;
enum {
	NSChangeDone = 0,
	NSChangeUndone = 1,
	NSChangeCleared = 2,
	NSChangeReadOtherContents = 3,
	NSChangeAutosaved = 4,
	NSChangeRedone = 5
};

/* HOW A SAVE IS BEING DONE. `NSSaveToOperation` is Export (a copy that does NOT become the document's file); `NSSaveAs`
 * does. The distinction is the caller's to honour in a write override; the default write path treats both as a write. */
typedef NSUInteger NSSaveOperationType;
enum {
	NSSaveOperation = 0,
	NSSaveAsOperation = 1,
	NSSaveToOperation = 2,
	NSAutosaveOperation = 3
};

@interface NSDocument : NSObject <NSUserInterfaceValidations>
{
	NSWindow *_window;			/* NOT RETAINED: an IBOutlet, set by a nib's owner connection */
	NSMutableArray *_windowControllers;	/* RETAINED: the controllers attached with -addWindowController: */
	NSURL *_fileURL;			/* RETAINED, or nil for an untitled document */
	NSString *_fileType;			/* RETAINED */
	NSDate *_fileModificationDate;		/* RETAINED */
	NSUndoManager *_undoManager;		/* RETAINED, created lazily */
	NSInteger _changeCount;			/* signed: undone changes below zero are still "not equal to zero" */
	BOOL _hasUndoManager;
	id _cg_documentController;		/* NOT RETAINED: the controller that added this document */
	NSPrintInfo *_printInfo;		/* RETAINED: made from the shared ticket on first ask */
	/* **THE AUTOSAVE FAMILY'S STATE.** `_autosavedContentsFileURL` is the separate file the contents were last
	 * autosaved to; `_hasUnautosavedChanges` is the history flag `-hasUnautosavedChanges` answers, which is NOT
	 * `-isDocumentEdited` (an autosaved document is still edited until it is saved or reverted). */
	NSURL *_autosavedContentsFileURL;	/* RETAINED */
	BOOL _hasUnautosavedChanges;
	/* **THE NAME AND THE LAST SAVE PANEL'S ANSWERS.** `_lastComponentOfFileName` is the name to display/save, which
	 * can differ from the URL's last component; the other two record what a panel run chose, and the flag says a
	 * panel has actually run (so "nil" and "no panel yet" are different answers). */
	NSString *_lastComponentOfFileName;	/* RETAINED */
	NSString *_fileTypeFromLastRunSavePanel;	/* RETAINED */
	BOOL _fileNameExtensionWasHidden;
	BOOL _cgSavePanelHasRun;
	/* A TEST SEAM: -1 means "ask the user"; a return code from the close alert means "use this answer". */
	NSInteger _cgCloseDecision;
}

/* ---- INITIALIZATION ------------------------------------------------------------------------------- */

- (instancetype)init;
- (nullable instancetype)initWithType:(nullable NSString *)typeName
			       error:(NSError * _Nullable * _Nullable)outError;

/* Whether a class can read concurrently. This tier reads on the calling thread, so NO — and the NO is the documented
 * answer, not an unimplemented branch. */
+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)typeName;

- (nullable instancetype)initWithContentsOfURL:(NSURL *)absoluteURL
				       ofType:(nullable NSString *)typeName
					error:(NSError * _Nullable * _Nullable)outError;
/* THE REOPENING INITIALISER: the document LIVES at `absoluteDocumentURL` but its contents came from
 * `absoluteDocumentContentsURL` (an autosave file). The two differing marks the document edited, which is Apple's rule. */
- (nullable instancetype)initForURL:(nullable NSURL *)absoluteDocumentURL
		 withContentsOfURL:(NSURL *)absoluteDocumentContentsURL
			    ofType:(nullable NSString *)typeName
			     error:(NSError * _Nullable * _Nullable)outError;

/* THE 10.3 SPELLINGS. Both forward to the error-taking initialisers; neither consults an override of the other. */
- (nullable instancetype)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName;
- (nullable instancetype)initWithContentsOfFile:(NSString *)absolutePath ofType:(nullable NSString *)typeName;

/* ---- ATTRIBUTES ----------------------------------------------------------------------------------- */

- (void)setFileType:(nullable NSString *)typeName;
- (nullable NSString *)fileType;

- (void)setFileURL:(nullable NSURL *)absoluteURL;
- (nullable NSURL *)fileURL;

- (void)setFileModificationDate:(nullable NSDate *)modificationDate;
- (nullable NSDate *)fileModificationDate;

- (void)setFileName:(nullable NSString *)fileName;	/* deprecated: the URL's path */
- (nullable NSString *)fileName;			/* deprecated */

/* ---- READING -------------------------------------------------------------------------------------- */

/* **THE MODERN READ PATH.** `-readFromURL:` makes an `NSFileWrapper` and calls `-readFromFileWrapper:`, whose default
 * hands `-regularFileContents` to `-readFromData:ofType:error:`. A data document overrides only the last of the three. The
 * default `-readFromData:` falls back to `-loadDataRepresentation:ofType:` and, if that is the base implementation, REFUSES
 * with an error rather than raising Apple's exception. */
- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(nullable NSString *)typeName
		      error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)readFromData:(NSData *)data ofType:(nullable NSString *)typeName
	       error:(NSError * _Nullable * _Nullable)outError;

/* THE 10.3 SPELLINGS: forwards. */
- (BOOL)readFromFile:(NSString *)fileName ofType:(nullable NSString *)type;
- (BOOL)readFromURL:(NSURL *)url ofType:(nullable NSString *)type;
- (BOOL)loadDataRepresentation:(NSData *)data ofType:(nullable NSString *)type;
- (BOOL)loadFileWrapperRepresentation:(NSFileWrapper *)wrapper ofType:(nullable NSString *)type;

/* ---- WRITING -------------------------------------------------------------------------------------- */

/* **THE MODERN WRITE PATH.** `-writeToURL:ofType:error:` asks `-fileWrapperOfType:error:` for a wrapper (whose default is
 * the data door plus a regular-file wrapper) and writes it atomically. `-writeToURL:…forSaveOperation:…` and
 * `-writeSafelyToURL:…` both funnel into it: this tier writes atomically through `NSFileWrapper` rather than Apple's
 * temporary-directory dance, which is a simplification stated at the door. */
- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName
	     error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSFileWrapper *)fileWrapperOfType:(nullable NSString *)typeName
					error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSData *)dataOfType:(nullable NSString *)typeName
			  error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName
  forSaveOperation:(NSSaveOperationType)saveOperation
originalContentsURL:(nullable NSURL *)absoluteOriginalContentsURL
	     error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)writeSafelyToURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName
	forSaveOperation:(NSSaveOperationType)saveOperation
		   error:(NSError * _Nullable * _Nullable)outError;
- (nullable NSDictionary *)fileAttributesToWriteToURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName
				     forSaveOperation:(NSSaveOperationType)saveOperation
				  originalContentsURL:(nullable NSURL *)absoluteOriginalContentsURL
						error:(NSError * _Nullable * _Nullable)outError;

/* THE 10.3 SPELLINGS: forwards, with the base data pair's fallback hooks. */
- (BOOL)writeToURL:(NSURL *)url ofType:(nullable NSString *)type;
- (BOOL)writeToFile:(NSString *)fileName ofType:(nullable NSString *)type;
- (BOOL)writeToFile:(NSString *)fullDocumentPath ofType:(nullable NSString *)documentTypeName
       originalFile:(nullable NSString *)fullOriginalDocumentPath
     saveOperation:(NSSaveOperationType)saveOperationType;
- (BOOL)writeWithBackupToFile:(NSString *)fullDocumentPath ofType:(nullable NSString *)documentTypeName
		saveOperation:(NSSaveOperationType)saveOperationType;
- (nullable NSData *)dataRepresentationOfType:(nullable NSString *)type;
- (nullable NSFileWrapper *)fileWrapperRepresentationOfType:(nullable NSString *)type;
- (nullable NSDictionary *)fileAttributesToWriteToFile:(NSString *)fullDocumentPath
					       ofType:(nullable NSString *)documentTypeName
					saveOperation:(NSSaveOperationType)saveOperationType;

/* ---- SAVING --------------------------------------------------------------------------------------- */

/* NO BACKUP FILES AND NO AUTO-SAVE YET: `-keepBackupFile` is NO, and the two panel-shaped doors refuse by name. */
- (BOOL)keepBackupFile;
- (void)saveDocument:(nullable id)sender;
- (void)saveDocumentAs:(nullable id)sender;
- (void)saveDocumentTo:(nullable id)sender;
- (void)saveDocumentWithDelegate:(nullable id)delegate didSaveSelector:(nullable SEL)didSaveSelector
		     contextInfo:(nullable void *)contextInfo;
- (void)runModalSavePanelForSaveOperation:(NSSaveOperationType)saveOperation delegate:(nullable id)delegate
			  didSaveSelector:(nullable SEL)didSaveSelector contextInfo:(nullable void *)contextInfo;
- (BOOL)shouldRunSavePanelWithAccessoryView;
- (BOOL)prepareSavePanel:(nullable id)savePanel;

/* THE REAL SAVE. The error form writes, records the URL/type/modification date, clears the change count and notes the
 * document as recent; the delegate form calls the error form and then sends the delegate `-document:didSave:contextInfo:`
 * through its own IMP (an `NSInvocation` in this tier refuses a 32-byte argument — the image rep family's finding). */
- (BOOL)saveToURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName
 forSaveOperation:(NSSaveOperationType)saveOperation
	    error:(NSError * _Nullable * _Nullable)outError;
- (void)saveToURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName
 forSaveOperation:(NSSaveOperationType)saveOperation
	 delegate:(nullable id)delegate
 didSaveSelector:(nullable SEL)didSaveSelector
      contextInfo:(nullable void *)contextInfo;
- (void)saveToFile:(NSString *)fileName saveOperation:(NSSaveOperationType)saveOperation
	  delegate:(nullable id)delegate didSaveSelector:(nullable SEL)didSaveSelector
       contextInfo:(nullable void *)contextInfo;	/* deprecated */

/* ---- REVERTING ------------------------------------------------------------------------------------ */

- (void)revertDocumentToSaved:(nullable id)sender;
- (BOOL)revertToContentsOfURL:(NSURL *)absoluteURL ofType:(nullable NSString *)typeName
			error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)revertToSavedFromURL:(NSURL *)url ofType:(nullable NSString *)type;	/* deprecated */
- (BOOL)revertToSavedFromFile:(NSString *)fileName ofType:(nullable NSString *)type;	/* deprecated */

/* ---- CHANGE COUNT AND UNDO ------------------------------------------------------------------------ */

- (BOOL)isDocumentEdited;
- (void)updateChangeCount:(NSDocumentChangeType)change;

/* The manager is created on demand when `-hasUndoManager` is YES (its default). Setting either one keeps the document's
 * observers on the manager it actually has. */
- (void)setUndoManager:(nullable NSUndoManager *)undoManager;
- (nullable NSUndoManager *)undoManager;
- (void)setHasUndoManager:(BOOL)hasUndoManager;
- (BOOL)hasUndoManager;

/* ---- WINDOWS -------------------------------------------------------------------------------------- */

- (void)makeWindowControllers;
- (nullable NSString *)windowNibName;
- (void)windowControllerWillLoadNib:(NSWindowController *)windowController;
- (void)windowControllerDidLoadNib:(NSWindowController *)windowController;
- (void)setWindow:(nullable NSWindow *)window;
- (void)addWindowController:(NSWindowController *)windowController;
- (void)removeWindowController:(NSWindowController *)windowController;
- (void)showWindows;
- (NSArray *)windowControllers;
- (nullable NSWindow *)windowForSheet;
- (nullable NSString *)displayName;

/* Discard and detach: the attached controllers close, and the document removes itself from the controller that owns it. */
- (void)close;

/* ---- TYPES AND VALIDATION ------------------------------------------------------------------------- */

/* The base answers the empty array: the type registry is the CONTROLLER's (it reads `CFBundleDocumentTypes`), and these
 * class doors exist for a subclass to answer precisely. `+isNativeType:` is NO for the same reason. */
+ (NSArray *)readableTypes;
+ (NSArray *)writableTypes;
+ (BOOL)isNativeType:(NSString *)type;
- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)saveOperation;
- (nullable NSString *)fileNameExtensionForType:(nullable NSString *)typeName
				  saveOperation:(NSSaveOperationType)saveOperation;
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;

/* ---- AUTOSAVING ----------------------------------------------------------------------------------- */

/* **THE AUTOSAVE FILE IS SEPARATE FROM THE DOCUMENT'S FILE.** `-autosavedContentsFileURL` is the location of the
 * contents written by `NSAutosaveOperation`; `-setAutosavedContentsFileURL:` also tells the owning controller to
 * remember the document for a crash-time reopen. `-autosavingFileType` answers the file type used for the autosave and
 * may be overridden to nil to disable autosaving for one document. */
- (BOOL)hasUnautosavedChanges;
- (void)autosaveDocumentWithDelegate:(nullable id)delegate didAutosaveSelector:(nullable SEL)didAutosaveSelector
			 contextInfo:(nullable void *)contextInfo;
- (nullable NSURL *)autosavedContentsFileURL;
- (void)setAutosavedContentsFileURL:(nullable NSURL *)absoluteURL;
- (nullable NSString *)autosavingFileType;

/* ---- CLOSING, AND THE SAVE PANEL'S TWO ANSWERS ----------------------------------------------------- */

/* **THE CLOSE CONFIRMATION IS ASYNCHRONOUS, AS APPLE'S IS.** A document with changes presents Save/Cancel/Don't Save,
 * and the delegate is messaged with `-document:shouldClose:contextInfo:` when the decision (and any save it implies)
 * is complete. `-shouldCloseWindowController:…` is the window's half: it asks the document when the controller owns
 * the document's closing or when it is the only controller, and answers YES otherwise. */
- (void)canCloseDocumentWithDelegate:(nullable id)delegate shouldCloseSelector:(nullable SEL)shouldCloseSelector
			 contextInfo:(nullable void *)contextInfo;
- (void)shouldCloseWindowController:(NSWindowController *)windowController delegate:(nullable id)delegate
		shouldCloseSelector:(nullable SEL)shouldCloseSelector contextInfo:(nullable void *)contextInfo;

/* **THE NAME THE USER SEES, AND WHAT THE LAST SAVE PANEL DECIDED.** `-lastComponentOfFileName` is a stored override
 * (set by a panel or a caller) that `-displayName` prefers; the two panel answers are nil/NO until a panel has run. */
- (nullable NSString *)lastComponentOfFileName;
- (void)setLastComponentOfFileName:(nullable NSString *)fileName;
- (nullable NSString *)fileTypeFromLastRunSavePanel;
- (BOOL)fileNameExtensionWasHiddenInLastRunSavePanel;

/* ---- PAGE LAYOUT AND ERROR PRESENTATION ----------------------------------------------------------- */

/* **PAGE SETUP IS THE EXISTING PANEL'S, WITH THE DOCUMENT'S HOOKS.** `-preparePageLayout:` may refuse the panel; an
 * accepted panel asks `-shouldChangePrintInfo:` before the document takes the new ticket. */
- (BOOL)preparePageLayout:(NSPageLayout *)pageLayout;
- (void)runPageLayout:(nullable id)sender;

/* **THE ERROR CHAIN APPLE DOCUMENTS: DOCUMENT -> CONTROLLER -> APPLICATION.** `-willPresentError:` is the hook at each
 * link; the modal form presents in a sheet when there is a window and application-modally otherwise. */
- (NSError *)willPresentError:(NSError *)error;
- (BOOL)presentError:(NSError *)error;
- (void)presentError:(NSError *)error modalForWindow:(nullable NSWindow *)window delegate:(nullable id)delegate
   didPresentSelector:(nullable SEL)didPresentSelector contextInfo:(nullable void *)contextInfo;

/* ---- SCRIPTING ------------------------------------------------------------------------------------ */

/* **THERE IS NO SCRIPTING SUITE IN THIS TIER**, so the two command handlers REFUSE BY NAME and `-objectSpecifier`
 * answers nil; a caller porting a scripted document learns that at the call rather than at a link error. */
- (nullable id)handleCloseScriptCommand:(nullable id)command;
- (nullable id)handleSaveScriptCommand:(nullable id)command;
- (nullable id)objectSpecifier;

/* ---- THE CONTROLLER'S ASSOCIATION (cg_) ------------------------------------------------------------ */

/* **THE CONTROLLER TELLS THE DOCUMENT WHO OWNS IT.** Apple's `-close` removes the document from the SHARED controller; this
 * tier also supports a controller made by hand (which is how the test keeps its documents to itself), so `-addDocument:`
 * records itself here and `-close` removes from the owner it actually has. A `cg_` door because Apple has no such pair. */
- (nullable id)cg_documentController;
- (void)cg_setDocumentController:(nullable id)controller;

/* ============================================================================================ *
 * THE PRINT DOORS.                                                                              *
 * ============================================================================================ */

/* **A DOCUMENT'S TICKET IS ITS OWN AND BEGINS AS A COPY OF THE SHARED ONE.** That is Apple's rule and it matters:
 * setting one document's paper size must not change every other document's. */
- (NSPrintInfo *)printInfo;
- (void)setPrintInfo:(NSPrintInfo *)printInfo;
- (BOOL)shouldChangePrintInfo:(NSPrintInfo *)newPrintInfo;

/* **THE OPERATION IS THE SEAM A SUBCLASS OVERRIDES.** The default prints the document's window content; a subclass
 * with a paginated view returns an operation over that view instead, and every door below keeps working. */
- (nullable NSPrintOperation *)printOperationWithSettings:(nullable NSDictionary *)printSettings
						    error:(NSError **)outError;
- (void)printDocument:(nullable id)sender;
- (void)printShowingPrintPanel:(BOOL)showPanels;
- (void)printDocumentWithSettings:(nullable NSDictionary *)printSettings showPrintPanel:(BOOL)showPrintPanel
			 delegate:(nullable id)delegate didPrintSelector:(nullable SEL)didPrintSelector
		      contextInfo:(nullable void *)contextInfo;
- (void)runModalPrintOperation:(NSPrintOperation *)printOperation delegate:(nullable id)delegate
		didRunSelector:(nullable SEL)didRunSelector contextInfo:(nullable void *)contextInfo;
- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)printInfo;
- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)printInfo delegate:(nullable id)delegate
			 didRunSelector:(nullable SEL)didRunSelector contextInfo:(nullable void *)contextInfo;

/* THE SCRIPTING DOOR STAYS WHAT IT WAS: this tree has no NSScriptCommand, so the print script command answers nil. */
- (nullable id)handlePrintScriptCommand:(nullable id)command;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDOCUMENT_H */
