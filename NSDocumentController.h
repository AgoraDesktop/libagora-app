/*
 * NSDocumentController.h — THE DOCUMENTS AN APPLICATION HAS OPEN, AND THE TYPES IT CAN MAKE.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CONTROLLER IS THE APPLICATION'S DOCUMENT LIST AND ITS TYPE TABLE.** It makes documents (untitled or from a URL),
 * hands them to the window machinery, remembers the open ones, notes the recent ones, and answers which subclass and which
 * type a file name or extension maps to. The type table is `CFBundleDocumentTypes` from the main bundle's Info.plist — the
 * era's own format — and a subclass overrides `-documentClassForType:`, `-defaultType` and `-typeFromFileExtension:` when
 * it wants a table it owns (which is how `tests/document.m` keeps its types to itself).
 *
 * **OPENING IS A URL DOOR, NOT A PANEL DOOR.** `-openDocumentWithContentsOfURL:display:error:` reads a file, adds the
 * document and shows its windows; `-openDocument:` — the File menu's action — needs the open panel this tier has not got, so
 * it REFUSES BY NAME. The panel pair is the slice after this one; nothing here pretends to own a file browser.
 *
 * **THE RECENT LIST IS IN MEMORY FOR NOW, AND THAT IS STATED RATHER THAN HIDDEN.** Apple persists it in
 * `NSUserDefaults` and builds an Open Recent menu from it; this tier keeps the URLs for the session and has no menu. The
 * doors (`-noteNewRecentDocumentURL:`, `-recentDocumentURLs`, `-clearRecentDocuments:`, `-maximumRecentDocumentCount`) are
 * real and are what the persistence and the menu will be built on.
 *
 * **CLOSING ALL IS SAFE, NOT CLEVER.** With no unsaved-changes alert in this tier, `-closeAllDocumentsWithDelegate:…` will
 * not silently discard an edited document: if any document is edited it closes NONE and tells the delegate NO. When the
 * alert exists, that branch becomes the alert.
 */
#ifndef APPKIT_NSDOCUMENTCONTROLLER_H
#define APPKIT_NSDOCUMENTCONTROLLER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <AppKit/NSUserInterfaceValidation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSDocument, NSError, NSString, NSURL, NSWindow;

@interface NSDocumentController : NSObject <NSUserInterfaceValidations>
{
	NSMutableArray *_documents;		/* RETAINED: the open documents, in opening order */
	NSMutableArray *_recentDocumentURLs;	/* RETAINED: newest first */
	NSString *_currentDirectory;		/* RETAINED, or nil: the last directory an open/save touched */
	NSArray *_cg_documentTypes;		/* RETAINED: the Info.plist entries, read once */
	BOOL _shouldCreateUI;			/* stored; this tier always shows the UI it makes */
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

/* **THE OPEN PANEL'S ACTION, REFUSED BY NAME UNTIL THE PANEL EXISTS.** */
- (void)openDocument:(nullable id)sender;

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
