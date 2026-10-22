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
 * **THE PRINT, AUTOSAVE, SCRIPTING AND PANEL DOORS ARE NOT DECLARED YET.** There is no print subsystem, no autosave
 * timer, and no save panel in this tier; declaring those methods and refusing them would put forty rows in the census that
 * answer nothing. `-saveDocument:` REFUSES BY NAME when the document has no URL (that is the save-panel path) and
 * `-saveDocumentAs:`/`-saveDocumentTo:` always refuse; a direct `-saveToURL:…` is real. The next slice is the panel pair.
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

@class NSData, NSDate, NSDictionary, NSError, NSFileWrapper, NSString, NSUndoManager, NSURL, NSWindow, NSWindowController;

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

/* ---- THE CONTROLLER'S ASSOCIATION (cg_) ------------------------------------------------------------ */

/* **THE CONTROLLER TELLS THE DOCUMENT WHO OWNS IT.** Apple's `-close` removes the document from the SHARED controller; this
 * tier also supports a controller made by hand (which is how the test keeps its documents to itself), so `-addDocument:`
 * records itself here and `-close` removes from the owner it actually has. A `cg_` door because Apple has no such pair. */
- (nullable id)cg_documentController;
- (void)cg_setDocumentController:(nullable id)controller;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDOCUMENT_H */
