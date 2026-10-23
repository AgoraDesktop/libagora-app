/*
 * NSDocumentController.h — THE DOCUMENTS AN APPLICATION HAS OPEN, AND THE TYPES IT CAN MAKE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CONTROLLER IS THE APPLICATION'S DOCUMENT LIST AND ITS TYPE TABLE.** It makes documents (untitled or from a URL),
 * hands them to the window machinery, remembers the open ones, notes the recent ones, and answers which subclass and which
 * type a file name or extension maps to. The type table is `CFBundleDocumentTypes` from the main bundle's Info.plist — the
 * era's own format — and a subclass overrides `-documentClassForType:`, `-defaultType` and `-typeFromFileExtension:` when
 * it wants a table it owns (which is how `tests/document.m` keeps its types to itself).
 *
 * **OPENING IS A URL DOOR, WITH A PANEL ABOVE IT.** `-openDocumentWithContentsOfURL:display:error:` reads a file, adds the
 * document and shows its windows; `-openDocument:` — the File menu's action — asks `-URLsFromRunningOpenPanel` (a real
 * `NSOpenPanel`, filtered by the bundle's document types) and opens each URL it answers.
 *
 * **THE RECENT LIST IS IN MEMORY FOR NOW, AND THAT IS STATED RATHER THAN HIDDEN.** Apple persists it in
 * `NSUserDefaults` and builds an Open Recent menu from it; this tier keeps the URLs for the session and has no menu. The
 * doors (`-noteNewRecentDocumentURL:`, `-recentDocumentURLs`, `-clearRecentDocuments:`, `-maximumRecentDocumentCount`) are
 * real and are what the persistence and the menu will be built on.
 *
 * **CLOSING ALL IS A WALK, AND THE DOCUMENT OWNS THE QUESTION.** `-closeAllDocumentsWithDelegate:…` asks each open
 * document's `-canCloseDocumentWithDelegate:…` in order, closing the ones that answer YES and stopping at the first NO;
 * `-reviewUnsavedDocumentsWithAlertTitle:…` adds the multi-document Save All/Cancel/Don't Save alert above that walk.
 * An unedited document before a refusal is closed, because the walk is not a transaction.
 */
#ifndef APPKIT_NSDOCUMENTCONTROLLER_H
#define APPKIT_NSDOCUMENTCONTROLLER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <AppKit/NSUserInterfaceValidation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSDocument, NSError, NSOpenPanel, NSString, NSURL, NSWindow;

@interface NSDocumentController : NSObject <NSUserInterfaceValidations>
{
	NSMutableArray *_documents;		/* RETAINED: the open documents, in opening order */
	NSMutableArray *_recentDocumentURLs;	/* RETAINED: newest first */
	NSString *_currentDirectory;		/* RETAINED, or nil: the last directory an open/save touched */
	NSArray *_cg_documentTypes;		/* RETAINED: the Info.plist entries, read once */
	BOOL _shouldCreateUI;			/* stored; this tier always shows the UI it makes */
	/* **THE AUTOSAVE TIMER AND THE CRASH-TIME REGISTRY.** `_autosavingDelay` is Apple's interval (0 disables); the
	 * registry is the list of documents whose autosaved contents should be reopened at launch. */
	NSTimeInterval _autosavingDelay;
	id _autosaveTimer;			/* RETAINED while scheduled */
	NSMutableArray *_cgAutosaveRecords;	/* RETAINED: dictionaries with documentURL/contentsURL */
	NSUInteger _cgAutosaveIndex;
	NSString *_cgAutosaveDirectoryOverride;	/* RETAINED: a test seam, else nil */
	/* A TEST SEAM for the error chain: nil means the application. */
	id _cgErrorPresenter;			/* NOT RETAINED */
}

/* ---- THE SHARED CONTROLLER ------------------------------------------------------------------------ */

+ (NSDocumentController *)sharedDocumentController;
- (instancetype)init;

/* ---- THE OPEN DOCUMENTS --------------------------------------------------------------------------- */

- (NSArray *)documents;
- (nullable id)currentDocument;			/* the key window's, then the main window's */
- (nullable NSString *)currentDirectory;
- (nullable id)documentForURL:(NSURL *)absoluteURL;
- (nullable id)documentForWindow:(nullable NSWindow *)window;
- (void)addDocument:(NSDocument *)document;
- (void)removeDocument:(NSDocument *)document;

/* ---- MAKING AND OPENING --------------------------------------------------------------------------- */

- (void)newDocument:(nullable id)sender;
- (nullable id)openUntitledDocumentAndDisplay:(BOOL)displayDocument
					error:(NSError * _Nullable * _Nullable)outError;
- (nullable id)makeUntitledDocumentOfType:(NSString *)typeName
				    error:(NSError * _Nullable * _Nullable)outError;
/* THE 10.3 SPELLING: the same document without the error out-parameter. */
- (nullable id)makeUntitledDocumentOfType:(NSString *)typeName;

/* **THE OPEN PANEL'S ACTION, AND THE TWO DOORS UNDER IT.** `-openDocument:` asks `-URLsFromRunningOpenPanel` and opens
 * each answer; a caller that has a panel of its own can use `-runModalOpenPanel:forTypes:` and read `-URLs` itself. */
- (void)openDocument:(nullable id)sender;
- (NSArray *)URLsFromRunningOpenPanel;
/* THE 10.3 SPELLING: the paths of the URLs the open panel answered. */
- (NSArray *)fileNamesFromRunningOpenPanel;
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)openPanel forTypes:(nullable NSArray *)types;

- (nullable id)openDocumentWithContentsOfURL:(NSURL *)absoluteURL
				    display:(BOOL)displayDocument
				      error:(NSError * _Nullable * _Nullable)outError;
- (nullable id)makeDocumentWithContentsOfURL:(NSURL *)absoluteURL
				      ofType:(NSString *)typeName
				       error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)reopenDocumentForURL:(NSURL *)absoluteDocumentURL
	   withContentsOfURL:(NSURL *)absoluteDocumentContentsURL
		       error:(NSError * _Nullable * _Nullable)outError;
- (nullable id)makeDocumentForURL:(nullable NSURL *)absoluteDocumentURL
		withContentsOfURL:(NSURL *)absoluteDocumentContentsURL
			   ofType:(NSString *)typeName
			    error:(NSError * _Nullable * _Nullable)outError;

/* ---- SAVING AND CLOSING THE SET ------------------------------------------------------------------- */

- (void)saveAllDocuments:(nullable id)sender;
- (BOOL)hasEditedDocuments;
- (void)closeAllDocumentsWithDelegate:(nullable id)delegate
		  didCloseAllSelector:(nullable SEL)didCloseAllSelector
			  contextInfo:(nullable void *)contextInfo;
/* **THE MULTI-DOCUMENT REVIEW AT QUIT TIME.** One edited document is handed to the document's own close confirmation;
 * several get the application-modal Save All/Cancel/Don't Save alert first. `cancellable:NO` removes Cancel, which is
 * what an unconditional quit path wants. */
- (void)reviewUnsavedDocumentsWithAlertTitle:(nullable NSString *)title
				  cancellable:(BOOL)cancellable
				     delegate:(nullable id)delegate
		       didReviewAllSelector:(nullable SEL)didReviewAllSelector
				  contextInfo:(nullable void *)contextInfo;

/* ---- AUTOSAVING ----------------------------------------------------------------------------------- */

/* **THE TIMER IS THE CONTROLLER'S.** Apple's `-autosavingDelay` is the interval between passes over the open documents;
 * 0 (the default) disables it. A document is autosaved only when `-hasUnautosavedChanges` is YES and its
 * `-autosavingFileType` is not nil. */
- (NSTimeInterval)autosavingDelay;
- (void)setAutosavingDelay:(NSTimeInterval)autosavingDelay;

/* ---- ERROR PRESENTATION --------------------------------------------------------------------------- */

/* **THE CONTROLLER IS THE DOCUMENT'S NEXT LINK.** `-willPresentError:` is the hook; the two present doors forward to
 * the application (which is the end of the chain), or to the test seam when one is set. */
- (NSError *)willPresentError:(NSError *)error;
- (BOOL)presentError:(NSError *)error;
- (void)presentError:(NSError *)error modalForWindow:(nullable NSWindow *)window delegate:(nullable id)delegate
   didPresentSelector:(nullable SEL)didPresentSelector contextInfo:(nullable void *)contextInfo;

/* ---- RECENT DOCUMENTS ----------------------------------------------------------------------------- */

- (NSUInteger)maximumRecentDocumentCount;
- (void)clearRecentDocuments:(nullable id)sender;
- (void)noteNewRecentDocument:(NSDocument *)document;
- (void)noteNewRecentDocumentURL:(NSURL *)absoluteURL;
- (NSArray *)recentDocumentURLs;

/* ---- DOCUMENT TYPES ------------------------------------------------------------------------------- */

- (nullable NSString *)defaultType;
- (nullable NSString *)typeForContentsOfURL:(NSURL *)inAbsoluteURL
				      error:(NSError * _Nullable * _Nullable)outError;
- (NSArray *)documentClassNames;
- (nullable Class)documentClassForType:(NSString *)typeName;
- (nullable NSString *)displayNameForType:(NSString *)typeName;

/* THE 10.5-DEPRECATED SPELLINGS, over the same table. */
- (nullable NSString *)typeFromFileExtension:(NSString *)fileNameExtension;
- (NSArray *)fileExtensionsFromType:(NSString *)typeName;

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;

/* ---- THE 10.3 SPELLINGS --------------------------------------------------------------------------- */

- (nullable id)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)type;
- (nullable id)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)display;
- (nullable id)makeDocumentWithContentsOfFile:(NSString *)fileName ofType:(NSString *)type;
- (nullable id)openDocumentWithContentsOfFile:(NSString *)fileName display:(BOOL)display;
- (nullable id)openUntitledDocumentOfType:(NSString *)type display:(BOOL)display;
- (nullable id)documentForFileName:(NSString *)fileName;
- (void)setShouldCreateUI:(BOOL)flag;
- (BOOL)shouldCreateUI;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDOCUMENTCONTROLLER_H */
