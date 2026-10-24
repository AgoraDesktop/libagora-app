/*
 * NSDocument — the file, the contents, the change count, the undo manager and the windows.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The read and write paths are Apple's in Apple's order: a URL becomes a file wrapper, a wrapper's regular-file contents
 * become data, and a subclass overrides the data pair — or the wrapper pair for a package. The deprecated file doors
 * forward to the URL doors, while the modern data pair still falls back to the 10.3 `-loadDataRepresentation:` hooks, which
 * is the one compatibility branch a subclass actually relies on.
 *
 * The change count has one writer and two sources: the application's `-updateChangeCount:` calls, and the undo manager's
 * did-undo/did-redo notifications the document registers for. `-isDocumentEdited` is that count against zero, and every
 * window controller is told the answer whenever it moves.
 */
#import "NSDocument.h"
#import "NSDocumentController.h"
#import "NSSavePanel.h"
#import "NSWindowController.h"
#import "NSWindow.h"
#import "AppKitRefusal.h"

#import <objc/runtime.h>
#import "NSApplication.h"
#import "NSPrintInfo.h"
#import "NSPrintOperation.h"
#import "NSPageLayout.h"
#import "NSAlert.h"
#import "NSView.h"

#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSFileWrapper.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUndoManager.h>
#import <Foundation/NSURL.h>

#include <stdio.h>
#include <objc/message.h>

/* THE ONE ERROR DOMAIN, with a code per kind of failure; the text is what `-localizedDescription` answers. */
static NSString *const AGDocumentErrorDomain = @"com.agora.appkit.document";
enum {
	AGDocumentErrorNoURL = 1,
	AGDocumentErrorRead = 2,
	AGDocumentErrorWrite = 3,
	AGDocumentErrorNoContents = 4
};

static void fn_document_error(NSError * _Nullable * _Nullable outError, NSInteger code, NSString *description)
{
	if (outError != NULL) {
		*outError = [NSError errorWithDomain:AGDocumentErrorDomain
						code:code
					    userInfo:[NSDictionary dictionaryWithObject:description
									    forKey:NSLocalizedDescriptionKey]];
	}
}

/* The on-disk modification date, or nil when the file is not there. */
static NSDate *fn_modification_date(NSURL *url)
{
	NSDictionary *attributes;
	NSString *path = [url path];

	if (path == nil) {
		return nil;
	}
	attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
	return (attributes != nil) ? [attributes objectForKey:NSFileModificationDate] : nil;
}

/* THE DELEGATE CALLBACKS HAVE REAL SIGNATURES, so they are called through the IMP the delegate's method answers rather
 * than through `-performSelector:` (which cannot carry a BOOL and a void *) or `NSInvocation` (which in this tier refuses
 * a 32-byte argument — `NSCustomImageRep`'s finding). */
typedef void (*AGDocumentDidSaveIMP)(id, SEL, id, BOOL, void *);
typedef void (*AGDocumentShouldCloseIMP)(id, SEL, id, BOOL, void *);
typedef void (*AGDocumentDidPresentIMP)(id, SEL, BOOL, void *);
typedef void (*AGDocumentDidReviewIMP)(id, SEL, id, BOOL, void *);
typedef void (*AGDocumentDidLayoutIMP)(id, SEL, id, NSInteger, void *);

/* **THE CLOSE DECISION'S CONTEXT.** The delegate and its selector must survive an asynchronous sheet, so this object
 * retains the delegate for the duration and releases itself when the answer is delivered. The caller allocates one
 * and hands it over; it does NOT release it. */
@interface AGDocumentCloseContext : NSObject
{
@public
	id _delegate;		/* RETAINED while the question is open */
	SEL _selector;
	void *_contextInfo;
}
- (instancetype)initWithDelegate:(id)delegate selector:(SEL)selector contextInfo:(void *)contextInfo;
- (void)finishWithDocument:(NSDocument *)document shouldClose:(BOOL)shouldClose;
@end

/* THE SAVE-BEFORE-CLOSE BRIDGE: one context for the save, holding the close context. */
@interface AGDocumentSaveCloseContext : NSObject
{
@public
	AGDocumentCloseContext *_closeContext;	/* RETAINED */
}
- (instancetype)initWithCloseContext:(AGDocumentCloseContext *)closeContext;
- (void)document:(NSDocument *)document didSave:(BOOL)ok contextInfo:(void *)contextInfo;
@end

/* THE UNDO OBSERVERS, declared before the implementation that registers them. */
@interface NSDocument (AGPrivate)
- (void)cg_closeAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)contextInfo;
- (void)cg_finishCloseWithCode:(NSInteger)code context:(AGDocumentCloseContext *)context;
- (void)cg_pageLayoutDidRun:(NSDocument *)document accepted:(NSInteger)code contextInfo:(void *)contextInfo;
- (void)cg_removeAutosavedContentsFile;
- (void)setCloseDecision:(NSInteger)code;
- (void)cg_noteSavePanelResult:(NSSavePanel *)panel;
- (void)cg_undoManagerDidUndo:(NSNotification *)notification;
- (void)cg_undoManagerDidRedo:(NSNotification *)notification;
@end

@implementation AGDocumentCloseContext

- (instancetype)initWithDelegate:(id)delegate selector:(SEL)selector contextInfo:(void *)contextInfo
{
	self = [super init];
	if (self != nil) {
		_delegate = [delegate retain];
		_selector = selector;
		_contextInfo = contextInfo;
	}
	return self;
}

- (void)dealloc
{
	[_delegate release];
	[super dealloc];
}

- (void)finishWithDocument:(NSDocument *)document shouldClose:(BOOL)shouldClose
{
	if (_delegate != nil && _selector != NULL && [_delegate respondsToSelector:_selector]) {
		AGDocumentShouldCloseIMP imp = (AGDocumentShouldCloseIMP)[_delegate methodForSelector:_selector];

		imp(_delegate, _selector, document, shouldClose, _contextInfo);
	}
	[self release];	/* the context owns itself for the duration; this is the matching release */
}

@end

@implementation AGDocumentSaveCloseContext

- (instancetype)initWithCloseContext:(AGDocumentCloseContext *)closeContext
{
	self = [super init];
	if (self != nil) {
		_closeContext = [closeContext retain];
	}
	return self;
}

- (void)dealloc
{
	[_closeContext release];
	[super dealloc];
}

- (void)document:(NSDocument *)document didSave:(BOOL)ok contextInfo:(void *)contextInfo
{
	(void)contextInfo;
	[_closeContext finishWithDocument:document shouldClose:ok];
}

@end

@implementation NSDocument

/* ---- INITIALIZATION ------------------------------------------------------------------------------- */

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_windowControllers = [[NSMutableArray alloc] init];
		_window = nil;
		_fileURL = nil;
		_fileType = nil;
		_fileModificationDate = nil;
		_undoManager = nil;
		_changeCount = 0;
		/* **APPLE'S DEFAULT IS "HAS ONE", AND THE MANAGER IS STILL MADE LAZILY.** A document that never asks for an undo
		 * manager never pays for one; one that asks gets it, and then the observers that move the change count. */
		_hasUndoManager = YES;
		_cg_documentController = nil;
		_autosavedContentsFileURL = nil;
		_hasUnautosavedChanges = NO;
		_lastComponentOfFileName = nil;
		_fileTypeFromLastRunSavePanel = nil;
		_fileNameExtensionWasHidden = NO;
		_cgSavePanelHasRun = NO;
		_cgCloseDecision = -1;
	}
	return self;
}

- (void)dealloc
{
	[self setUndoManager:nil];
	[_fileURL release];
	[_fileType release];
	[_fileModificationDate release];
	[_autosavedContentsFileURL release];
	[_lastComponentOfFileName release];
	[_fileTypeFromLastRunSavePanel release];
	[_windowControllers release];
	[super dealloc];
}

- (instancetype)initWithType:(NSString *)typeName error:(NSError **)outError
{
	self = [self init];
	if (self != nil) {
		[self setFileType:typeName];
	}
	(void)outError;
	return self;
}

+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)typeName
{
	(void)typeName;
	return NO;
}

- (instancetype)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	self = [self init];
	if (self == nil) {
		return nil;
	}
	if (![self readFromURL:absoluteURL ofType:typeName error:outError]) {
		[self release];
		return nil;
	}
	[self setFileURL:absoluteURL];
	[self setFileType:typeName];
	[self setFileModificationDate:fn_modification_date(absoluteURL)];
	_changeCount = 0;
	return self;
}

- (instancetype)initForURL:(NSURL *)absoluteDocumentURL
	 withContentsOfURL:(NSURL *)absoluteDocumentContentsURL
		    ofType:(NSString *)typeName
		     error:(NSError **)outError
{
	self = [self init];
	if (self == nil) {
		return nil;
	}
	if (![self readFromURL:absoluteDocumentContentsURL ofType:typeName error:outError]) {
		[self release];
		return nil;
	}
	[self setFileURL:absoluteDocumentURL];
	[self setFileType:typeName];
	[self setFileModificationDate:fn_modification_date(absoluteDocumentContentsURL)];
	/* **THE CONTENTS URL IS THE AUTOSAVE URL WHEN THE TWO DIFFER.** Apple's designated initialiser records it, and the
	 * record is what lets a later save delete the obsolete file; when they are equal there is no separate autosave. */
	if (absoluteDocumentURL == nil || ![absoluteDocumentURL isEqual:absoluteDocumentContentsURL]) {
		[self setAutosavedContentsFileURL:absoluteDocumentContentsURL];
	}
	/* **A DOCUMENT REOPENED FROM SOMEWHERE ELSE IS EDITED** — it cannot be in sync with its own file until it is saved. */
	[self updateChangeCount:((absoluteDocumentURL != nil && [absoluteDocumentURL isEqual:absoluteDocumentContentsURL])
		? NSChangeCleared : NSChangeReadOtherContents)];
	return self;
}

- (instancetype)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName
{
	return [self initWithContentsOfURL:absoluteURL ofType:typeName error:NULL];
}

- (instancetype)initWithContentsOfFile:(NSString *)absolutePath ofType:(NSString *)typeName
{
	return [self initWithContentsOfURL:[NSURL fileURLWithPath:absolutePath] ofType:typeName error:NULL];
}

/* ---- ATTRIBUTES ----------------------------------------------------------------------------------- */

- (void)setFileType:(NSString *)typeName
{
	NSString *held = [typeName copy];

	[_fileType release];
	_fileType = held;
}

- (NSString *)fileType { return _fileType; }

- (void)setFileURL:(NSURL *)absoluteURL
{
	NSURL *held = [absoluteURL retain];
	NSString *name = nil;

	[_fileURL release];
	_fileURL = held;
	/* **THE DISPLAYED NAME FOLLOWS THE URL UNLESS A CALLER SETS ONE EXPLICITLY.** A save to a new URL is a new name;
	 * a save panel that hid the extension is handled by `-displayName` from the separate flag. */
	if (_fileURL != nil) {
		name = [[_fileURL path] lastPathComponent];
	}
	[name retain];
	[_lastComponentOfFileName release];
	_lastComponentOfFileName = name;
}

- (NSURL *)fileURL { return _fileURL; }

- (void)setFileModificationDate:(NSDate *)modificationDate
{
	NSDate *held = [modificationDate retain];

	[_fileModificationDate release];
	_fileModificationDate = held;
}

- (NSDate *)fileModificationDate { return _fileModificationDate; }

- (void)setFileName:(NSString *)fileName
{
	[self setFileURL:(fileName != nil) ? [NSURL fileURLWithPath:fileName] : nil];
}

- (NSString *)fileName
{
	return (_fileURL != nil) ? [_fileURL path] : nil;
}

/* ---- READING -------------------------------------------------------------------------------------- */

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	NSFileWrapper *wrapper;
	BOOL ok;

	if (absoluteURL == nil) {
		fn_document_error(outError, AGDocumentErrorNoURL, @"There is no URL to read from.");
		return NO;
	}
	wrapper = [[NSFileWrapper alloc] initWithURL:absoluteURL options:0 error:outError];
	if (wrapper == nil) {
		return NO;
	}
	ok = [self readFromFileWrapper:wrapper ofType:typeName error:outError];
	[wrapper release];
	return ok;
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)fileWrapper ofType:(NSString *)typeName error:(NSError **)outError
{
	NSData *contents = [fileWrapper regularFileContents];

	if (contents == nil) {
		/* A DIRECTORY WRAPPER IS A PACKAGE, which only the deprecated wrapper hook can read in this tier. */
		if ([self loadFileWrapperRepresentation:fileWrapper ofType:typeName]) {
			return YES;
		}
		fn_document_error(outError, AGDocumentErrorNoContents,
				  @"The file wrapper has no regular-file contents and the document does not read packages.");
		return NO;
	}
	{
		NSError *inner = nil;
		BOOL ok = [self readFromData:contents ofType:typeName error:&inner];

		if (ok) {
			return YES;
		}
		/* AND THE 10.3 HOOK, tried only after the modern door declines, so a subclass that overrides either works. */
		if ([self loadFileWrapperRepresentation:fileWrapper ofType:typeName]) {
			if (outError != NULL) {
				*outError = nil;
			}
			return YES;
		}
		if (outError != NULL) {
			*outError = inner;
		}
		return NO;
	}
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	if ([self loadDataRepresentation:data ofType:typeName]) {
		return YES;
	}
	/* APPLE THROWS AN EXCEPTION HERE; THIS TIER REFUSES WITH AN ERROR, which is the disposition the rest of the tree uses
	 * for a subclass that forgot its reading door. */
	fn_document_error(outError, AGDocumentErrorRead,
			  @"This document does not implement -readFromData:ofType:error: or -loadDataRepresentation:ofType:.");
	return NO;
}

- (BOOL)readFromFile:(NSString *)fileName ofType:(NSString *)type
{
	return [self readFromURL:[NSURL fileURLWithPath:fileName] ofType:type error:NULL];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type
{
	return [self readFromURL:url ofType:type error:NULL];
}

/* The 10.3 hooks: NO/NIL by default, the subclass's to override. */
- (BOOL)loadDataRepresentation:(NSData *)data ofType:(NSString *)type
{
	(void)data;
	(void)type;
	return NO;
}

- (BOOL)loadFileWrapperRepresentation:(NSFileWrapper *)wrapper ofType:(NSString *)type
{
	(void)wrapper;
	(void)type;
	return NO;
}

/* ---- WRITING -------------------------------------------------------------------------------------- */

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	NSFileWrapper *wrapper;

	if (absoluteURL == nil) {
		fn_document_error(outError, AGDocumentErrorNoURL, @"There is no URL to write to.");
		return NO;
	}
	wrapper = [self fileWrapperOfType:typeName error:outError];
	if (wrapper == nil) {
		return NO;
	}
	return [wrapper writeToURL:absoluteURL options:NSFileWrapperWritingAtomic
		originalContentsURL:nil error:outError];
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)outError
{
	NSData *data = [self dataOfType:typeName error:outError];

	if (data != nil) {
		return [[[NSFileWrapper alloc] initRegularFileWithContents:data] autorelease];
	}
	/* THE 10.3 WRAPPER HOOK IS TRIED WHEN THE DATA DOOR DECLINES, so a package subclass can answer either way. */
	return [self fileWrapperRepresentationOfType:typeName];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	NSData *data = [self dataRepresentationOfType:typeName];

	if (data == nil) {
		fn_document_error(outError, AGDocumentErrorWrite,
				  @"This document does not implement -dataOfType:error: or -dataRepresentationOfType:.");
	}
	return data;
}

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName
  forSaveOperation:(NSSaveOperationType)saveOperation
originalContentsURL:(NSURL *)absoluteOriginalContentsURL
	     error:(NSError **)outError
{
	/* **THE SIMPLIFICATION IS HERE, ONCE.** Apple stages a temporary directory, copies attributes and swaps; this tier
	 * asks the file wrapper for an ATOMIC write, which is the same promise (a crash leaves the old file or the new one,
	 * never a half-written one) without a second temporary path to get wrong. */
	(void)saveOperation;
	(void)absoluteOriginalContentsURL;
	return [self writeToURL:absoluteURL ofType:typeName error:outError];
}

- (BOOL)writeSafelyToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName
	forSaveOperation:(NSSaveOperationType)saveOperation
		   error:(NSError **)outError
{
	return [self writeToURL:absoluteURL ofType:typeName forSaveOperation:saveOperation
	    originalContentsURL:nil error:outError];
}

- (NSDictionary *)fileAttributesToWriteToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName
			   forSaveOperation:(NSSaveOperationType)saveOperation
			originalContentsURL:(NSURL *)absoluteOriginalContentsURL
				      error:(NSError **)outError
{
	(void)absoluteURL;
	(void)typeName;
	(void)saveOperation;
	(void)absoluteOriginalContentsURL;
	(void)outError;
	return nil;
}

/* THE 10.3 SPELLINGS. */
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type
{
	return [self writeToURL:url ofType:type error:NULL];
}

- (BOOL)writeToFile:(NSString *)fileName ofType:(NSString *)type
{
	return [self writeToURL:[NSURL fileURLWithPath:fileName] ofType:type error:NULL];
}

- (BOOL)writeToFile:(NSString *)fullDocumentPath ofType:(NSString *)documentTypeName
       originalFile:(NSString *)fullOriginalDocumentPath
     saveOperation:(NSSaveOperationType)saveOperationType
{
	return [self writeToURL:[NSURL fileURLWithPath:fullDocumentPath]
			 ofType:documentTypeName
	     forSaveOperation:saveOperationType
	    originalContentsURL:(fullOriginalDocumentPath != nil)
				     ? [NSURL fileURLWithPath:fullOriginalDocumentPath] : nil
			  error:NULL];
}

- (BOOL)writeWithBackupToFile:(NSString *)fullDocumentPath ofType:(NSString *)documentTypeName
		saveOperation:(NSSaveOperationType)saveOperationType
{
	NSSaveOperationType mapped = (saveOperationType == NSAutosaveOperation) ? NSSaveToOperation : saveOperationType;

	return [self writeToURL:[NSURL fileURLWithPath:fullDocumentPath] ofType:documentTypeName
	     forSaveOperation:mapped originalContentsURL:nil error:NULL];
}

- (NSData *)dataRepresentationOfType:(NSString *)type
{
	(void)type;
	return nil;
}

- (NSFileWrapper *)fileWrapperRepresentationOfType:(NSString *)type
{
	(void)type;
	return nil;
}

- (NSDictionary *)fileAttributesToWriteToFile:(NSString *)fullDocumentPath ofType:(NSString *)documentTypeName
				saveOperation:(NSSaveOperationType)saveOperationType
{
	(void)fullDocumentPath;
	(void)documentTypeName;
	(void)saveOperationType;
	return nil;
}

/* ---- SAVING --------------------------------------------------------------------------------------- */

- (BOOL)keepBackupFile
{
	return NO;
}

- (BOOL)saveToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName
 forSaveOperation:(NSSaveOperationType)saveOperation
	    error:(NSError **)outError
{
	if (![self writeSafelyToURL:absoluteURL ofType:typeName forSaveOperation:saveOperation error:outError]) {
		return NO;
	}
	/* **AN AUTOSAVE IS A SEPARATE COPY, NOT THE DOCUMENT'S FILE.** The written URL becomes `-autosavedContentsFileURL`
	 * and the on-disk revision the document's own URL still points at is untouched; the document is still edited (the
	 * autosave merely makes the crash recovery copy current). */
	if (saveOperation == NSAutosaveOperation) {
		[self setAutosavedContentsFileURL:absoluteURL];
		[self updateChangeCount:NSChangeAutosaved];
		return YES;
	}
	/* **AND AN EXPORT IS A COPY TOO.** `NSSaveToOperation` writes where the panel said and stops: the document keeps
	 * its URL and type, stays edited if it was, and is not noted as recent. */
	if (saveOperation == NSSaveToOperation) {
		return YES;
	}
	/* **A REAL SAVE MAKES THE AUTOSAVE OBSOLETE.** Delete it before the new URL becomes the document's own. */
	[self cg_removeAutosavedContentsFile];
	[self setFileURL:absoluteURL];
	[self setFileType:typeName];
	[self setFileModificationDate:fn_modification_date(absoluteURL)];
	[self updateChangeCount:NSChangeCleared];
	{
		/* **THE RECENT LIST IS THE OWNING CONTROLLER'S.** A document made by a controller made by hand belongs to that
		 * controller, not to the shared one; the shared one is only the fallback for a document nobody added. */
		id owner = (_cg_documentController != nil) ? _cg_documentController
							  : [NSDocumentController sharedDocumentController];

		if ([owner respondsToSelector:@selector(noteNewRecentDocument:)]) {
			[owner noteNewRecentDocument:self];
		}
	}
	return YES;
}

- (void)saveToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName
 forSaveOperation:(NSSaveOperationType)saveOperation
	 delegate:(id)delegate
 didSaveSelector:(SEL)didSaveSelector
      contextInfo:(void *)contextInfo
{
	BOOL ok = [self saveToURL:absoluteURL ofType:typeName forSaveOperation:saveOperation error:NULL];

	if (delegate != nil && didSaveSelector != NULL
	    && [delegate respondsToSelector:didSaveSelector]) {
		AGDocumentDidSaveIMP imp = (AGDocumentDidSaveIMP)[delegate methodForSelector:didSaveSelector];

		imp(delegate, didSaveSelector, self, ok, contextInfo);
	}
}

- (void)saveDocumentWithDelegate:(id)delegate didSaveSelector:(SEL)didSaveSelector
		     contextInfo:(void *)contextInfo
{
	if (_fileURL != nil && _fileType != nil) {
		[self saveToURL:_fileURL ofType:_fileType forSaveOperation:NSSaveOperation
			delegate:delegate didSaveSelector:didSaveSelector contextInfo:contextInfo];
		return;
	}
	[self runModalSavePanelForSaveOperation:NSSaveOperation delegate:delegate
			      didSaveSelector:didSaveSelector contextInfo:contextInfo];
}

- (void)saveDocument:(id)sender
{
	(void)sender;
	if (_fileURL != nil && _fileType != nil) {
		(void)[self saveToURL:_fileURL ofType:_fileType forSaveOperation:NSSaveOperation error:NULL];
		return;
	}
	[self runModalSavePanelForSaveOperation:NSSaveOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
}

- (void)saveDocumentAs:(id)sender
{
	(void)sender;
	[self runModalSavePanelForSaveOperation:NSSaveAsOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
}

- (void)saveDocumentTo:(id)sender
{
	(void)sender;
	[self runModalSavePanelForSaveOperation:NSSaveToOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
}

/* **THE SAVE PANEL, CONFIGURED FROM THE DOCUMENT.** The name field starts at the document's file name (or "Untitled"), the
 * directory at its file's (or the controller's), and the types are the writable types' extensions. A document with a
 * window gets a SHEET; one without gets the application-modal panel, which is the only place this tier blocks on a panel.
 * The delegate's did-save selector is called with the write's answer, and the panel is released by the session it runs. */
- (NSArray *)cg_savePanelExtensionsForOperation:(NSSaveOperationType)saveOperation
{
	NSMutableArray *extensions = [NSMutableArray array];
	NSArray *types = [self writableTypesForSaveOperation:saveOperation];
	id controller = (_cg_documentController != nil) ? _cg_documentController
						       : [NSDocumentController sharedDocumentController];
	NSUInteger i;

	for (i = 0; i < [types count]; i++) {
		NSString *type = [types objectAtIndex:i];

		if ([controller respondsToSelector:@selector(fileExtensionsFromType:)]) {
			[extensions addObjectsFromArray:[controller fileExtensionsFromType:type]];
		}
	}
	if ([extensions count] == 0 && _fileType != nil) {
		NSString *extension = [self fileNameExtensionForType:_fileType saveOperation:saveOperation];

		if ([extension length] > 0) {
			[extensions addObject:extension];
		}
	}
	return extensions;
}

- (void)runModalSavePanelForSaveOperation:(NSSaveOperationType)saveOperation delegate:(id)delegate
			  didSaveSelector:(SEL)didSaveSelector contextInfo:(void *)contextInfo
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	NSArray *extensions = [self cg_savePanelExtensionsForOperation:saveOperation];
	NSString *directory = nil;
	NSString *name = nil;
	NSWindow *sheetWindow = [self windowForSheet];

	if (_fileURL != nil) {
		directory = [[_fileURL path] stringByDeletingLastPathComponent];
		name = (_lastComponentOfFileName != nil && [_lastComponentOfFileName length] > 0)
			? _lastComponentOfFileName : [[_fileURL path] lastPathComponent];
	} else {
		id controller = (_cg_documentController != nil) ? _cg_documentController
							       : [NSDocumentController sharedDocumentController];

		directory = [controller currentDirectory];
		name = (_lastComponentOfFileName != nil && [_lastComponentOfFileName length] > 0)
			? _lastComponentOfFileName : @"Untitled";
	}
	if (directory != nil) {
		[panel setDirectory:directory];
	}
	if (name != nil) {
		[panel setNameFieldStringValue:name];
	}
	if ([extensions count] > 0) {
		[panel setAllowedFileTypes:extensions];
	}
	[panel setCanSelectHiddenExtension:YES];
	if (saveOperation == NSSaveToOperation) {
		[panel setTitle:@"Export"];
		[panel setPrompt:@"Export"];
	} else if (saveOperation == NSSaveAsOperation) {
		[panel setTitle:@"Save As"];
		[panel setPrompt:@"Save"];
	} else {
		[panel setTitle:@"Save"];
		[panel setPrompt:@"Save"];
	}
	(void)[self prepareSavePanel:panel];

	if (sheetWindow != nil) {
		[panel beginSheetModalForWindow:sheetWindow completionHandler:^(NSInteger result) {
			BOOL ok = NO;
			NSError *error = nil;

			if (result == NSOKButton) {
				[self cg_noteSavePanelResult:panel];
				ok = [self saveToURL:[panel URL] ofType:[self fileType]
				     forSaveOperation:saveOperation error:&error];
			}
			if (!ok && error != nil) {
				fprintf(stderr, "document: could not save: %s\n", [[error localizedDescription] UTF8String]);
			}
			if (delegate != nil && didSaveSelector != NULL && [delegate respondsToSelector:didSaveSelector]) {
				AGDocumentDidSaveIMP imp = (AGDocumentDidSaveIMP)[delegate methodForSelector:didSaveSelector];

				imp(delegate, didSaveSelector, self, ok, contextInfo);
			}
		}];
		return;
	}
	{
		NSInteger result = [panel runModal];
		BOOL ok = NO;
		NSError *error = nil;

		if (result == NSOKButton) {
			[self cg_noteSavePanelResult:panel];
			ok = [self saveToURL:[panel URL] ofType:[self fileType] forSaveOperation:saveOperation error:&error];
		}
		if (!ok && error != nil) {
			fprintf(stderr, "document: could not save: %s\n", [[error localizedDescription] UTF8String]);
		}
		if (delegate != nil && didSaveSelector != NULL && [delegate respondsToSelector:didSaveSelector]) {
			AGDocumentDidSaveIMP imp = (AGDocumentDidSaveIMP)[delegate methodForSelector:didSaveSelector];

			imp(delegate, didSaveSelector, self, ok, contextInfo);
		}
	}
}

- (BOOL)shouldRunSavePanelWithAccessoryView
{
	return YES;
}

- (BOOL)prepareSavePanel:(id)savePanel
{
	(void)savePanel;
	return YES;
}

- (void)saveToFile:(NSString *)fileName saveOperation:(NSSaveOperationType)saveOperation
	  delegate:(id)delegate didSaveSelector:(SEL)didSaveSelector contextInfo:(void *)contextInfo
{
	[self saveToURL:[NSURL fileURLWithPath:fileName] ofType:_fileType forSaveOperation:saveOperation
		delegate:delegate didSaveSelector:didSaveSelector contextInfo:contextInfo];
}

/* ---- REVERTING ------------------------------------------------------------------------------------ */

- (BOOL)revertToContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	if (![self readFromURL:absoluteURL ofType:typeName error:outError]) {
		return NO;
	}
	[self setFileModificationDate:fn_modification_date(absoluteURL)];
	[self cg_removeAutosavedContentsFile];
	[self updateChangeCount:NSChangeCleared];
	/* AN UNDO STACK OVER CONTENTS THAT ARE NO LONGER THERE WOULD UNDO INTO A MIXTURE. */
	if (_undoManager != nil) {
		[_undoManager removeAllActions];
	}
	return YES;
}

- (void)revertDocumentToSaved:(id)sender
{
	(void)sender;
	if (_fileURL == nil || _fileType == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -[NSDocument revertDocumentToSaved:] needs a file the document was read from, "
				"and this one has never been saved\n");
		return;
	}
	(void)[self revertToContentsOfURL:_fileURL ofType:_fileType error:NULL];
}

- (BOOL)revertToSavedFromURL:(NSURL *)url ofType:(NSString *)type
{
	return [self revertToContentsOfURL:url ofType:type error:NULL];
}

- (BOOL)revertToSavedFromFile:(NSString *)fileName ofType:(NSString *)type
{
	return [self revertToContentsOfURL:[NSURL fileURLWithPath:fileName] ofType:type error:NULL];
}

/* ---- AUTOSAVING, CLOSING, THE NAME, PAGE LAYOUT AND ERRORS --------------------------------------- */

/* ---- AUTOSAVING ----------------------------------------------------------------------------------- */

- (BOOL)hasUnautosavedChanges
{
	return _hasUnautosavedChanges;
}

- (NSURL *)autosavedContentsFileURL
{
	return _autosavedContentsFileURL;
}

/* **SETTING THE AUTOSAVE URL RECORDS IT WITH THE CONTROLLER, WHICH IS WHAT MAKES A CRASH-TIME REOPEN POSSIBLE.** The
 * document owns the URL; the controller owns the list of documents to reopen and the file on disk. Clearing the URL is
 * a withdrawal from that list. */
- (void)setAutosavedContentsFileURL:(NSURL *)absoluteURL
{
	NSURL *held = [absoluteURL retain];
	NSURL *old = _autosavedContentsFileURL;
	id owner;

	owner = (_cg_documentController != nil) ? _cg_documentController : [NSDocumentController sharedDocumentController];
	/* **THE WITHDRAWAL USES THE OLD URL, SO IT HAPPENS BEFORE THE ASSIGNMENT.** The controller finds the record by
	 * the URL the document is about to stop naming. */
	if (held == nil && old != nil && [owner respondsToSelector:@selector(cg_forgetAutosaveForDocument:)]) {
		[owner cg_forgetAutosaveForDocument:self];
	}
	_autosavedContentsFileURL = held;
	if (held != nil && [owner respondsToSelector:@selector(cg_recordAutosaveForDocument:)]) {
		[owner cg_recordAutosaveForDocument:self];
	}
	[old release];
}

- (NSString *)autosavingFileType
{
	return _fileType;
}

/* **THE AUTOSAVE WRITES WHERE THE DOCUMENT ALREADY AUTOSAVED, OR ASKS THE CONTROLLER FOR A NAME.** The controller's
 * name is the one the registry can find again; the type is `-autosavingFileType`, and nil disables the operation (the
 * controller's timer does not send the message for such a document). */
- (void)autosaveDocumentWithDelegate:(id)delegate didAutosaveSelector:(SEL)didAutosaveSelector contextInfo:(void *)contextInfo
{
	NSString *typeName = [self autosavingFileType];
	NSURL *url = _autosavedContentsFileURL;
	id owner;

	if (typeName == nil) {
		if (delegate != nil && didAutosaveSelector != NULL && [delegate respondsToSelector:didAutosaveSelector]) {
			AGDocumentDidSaveIMP imp = (AGDocumentDidSaveIMP)[delegate methodForSelector:didAutosaveSelector];

			imp(delegate, didAutosaveSelector, self, NO, contextInfo);
		}
		return;
	}
	if (url == nil) {
		owner = (_cg_documentController != nil) ? _cg_documentController : [NSDocumentController sharedDocumentController];
		if ([owner respondsToSelector:@selector(cg_autosaveURLForDocument:typeName:)]) {
			url = [owner cg_autosaveURLForDocument:self typeName:typeName];
		}
	}
	if (url == nil) {
		NSError *error = nil;

		fn_document_error(&error, AGDocumentErrorWrite, @"There is no location for this document's autosave.");
		[self presentError:error];
		if (delegate != nil && didAutosaveSelector != NULL && [delegate respondsToSelector:didAutosaveSelector]) {
			AGDocumentDidSaveIMP imp = (AGDocumentDidSaveIMP)[delegate methodForSelector:didAutosaveSelector];

			imp(delegate, didAutosaveSelector, self, NO, contextInfo);
		}
		return;
	}
	[self saveToURL:url ofType:typeName forSaveOperation:NSAutosaveOperation
		delegate:delegate didSaveSelector:didAutosaveSelector contextInfo:contextInfo];
}

/* **DELETING THE AUTOSAVE FILE IS THE DOCUMENT'S JOB, BECAUSE THE DOCUMENT KNOWS WHERE IT PUT IT.** The controller's
 * registry is updated by the URL setter; the unlink happens here. */
- (void)cg_removeAutosavedContentsFile
{
	if (_autosavedContentsFileURL != nil) {
		NSURL *old = [_autosavedContentsFileURL retain];

		[self setAutosavedContentsFileURL:nil];	/* which withdraws the registry record */
		[[NSFileManager defaultManager] removeItemAtURL:old error:NULL];
		[old release];
	}
}

/* ---- CLOSING --------------------------------------------------------------------------------------- */

/* **SAVE / CANCEL / DON'T SAVE, ASYNCHRONOUSLY.** The alert is a sheet when there is a window and the application is
 * running; otherwise it is application-modal, which is the only thing a windowless document can do. The context owns
 * itself for the duration and releases after the delegate is messaged. */
- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void *)contextInfo
{
	AGDocumentCloseContext *context = [[AGDocumentCloseContext alloc] initWithDelegate:delegate
										 selector:shouldCloseSelector
									      contextInfo:contextInfo];
	NSAlert *alert;
	NSWindow *sheet;

	if (![self isDocumentEdited]) {
		[context finishWithDocument:self shouldClose:YES];
		return;
	}
	if (_cgCloseDecision >= 0) {
		NSInteger decision = _cgCloseDecision;

		_cgCloseDecision = -1;
		[self cg_finishCloseWithCode:decision context:context];
		return;
	}
	alert = [NSAlert alertWithMessageText:@"Do you want to save the changes?"
				defaultButton:@"Save"
			      alternateButton:@"Cancel"
				  otherButton:@"Don't Save"
		    informativeTextWithFormat:@"Your changes to “%@” will be lost if you don't save them.",
					     [self displayName]];
	sheet = [self windowForSheet];
	if (sheet != nil && [[NSApplication sharedApplication] isRunning]) {
		[alert beginSheetModalForWindow:sheet modalDelegate:self
				  didEndSelector:@selector(cg_closeAlertDidEnd:returnCode:contextInfo:)
				     contextInfo:context];
		return;
	}
	[self cg_finishCloseWithCode:[alert runModal] context:context];
}

- (void)cg_closeAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)contextInfo
{
	(void)alert;
	[self cg_finishCloseWithCode:code context:(AGDocumentCloseContext *)contextInfo];
}

- (void)cg_finishCloseWithCode:(NSInteger)code context:(AGDocumentCloseContext *)context
{
	if (code == NSAlertFirstButtonReturn) {
		AGDocumentSaveCloseContext *save = [[AGDocumentSaveCloseContext alloc] initWithCloseContext:context];

		[self saveDocumentWithDelegate:save didSaveSelector:@selector(document:didSave:contextInfo:)
				   contextInfo:NULL];
		[save release];
		return;
	}
	[context finishWithDocument:self shouldClose:(code == NSAlertThirdButtonReturn)];
}

- (void)shouldCloseWindowController:(NSWindowController *)windowController delegate:(id)delegate
		shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void *)contextInfo
{
	BOOL ownsClosing = [windowController shouldCloseDocument] || [[self windowControllers] count] <= 1;

	if (ownsClosing) {
		[self canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
		return;
	}
	if (delegate != nil && shouldCloseSelector != NULL && [delegate respondsToSelector:shouldCloseSelector]) {
		AGDocumentShouldCloseIMP imp = (AGDocumentShouldCloseIMP)[delegate methodForSelector:shouldCloseSelector];

		imp(delegate, shouldCloseSelector, self, YES, contextInfo);
	}
}

/* THE TEST SEAM: -1 asks the user; a positive alert return code is used as the answer. */
- (void)setCloseDecision:(NSInteger)code
{
	_cgCloseDecision = code;
}

/* ---- THE NAME AND THE SAVE PANEL'S ANSWERS ---------------------------------------------------------- */

- (NSString *)lastComponentOfFileName
{
	return _lastComponentOfFileName;
}

- (void)setLastComponentOfFileName:(NSString *)fileName
{
	NSString *copy = [fileName copy];

	[_lastComponentOfFileName release];
	_lastComponentOfFileName = copy;
}

/* **THE PANEL'S TWO ANSWERS, RECORDED WHEN IT ACCEPTS.** The document has no type popup in this tier's save panel, so
 * the type the panel was run for is the document's own; the hidden-extension flag and the chosen name are the panel's
 * real answers. */
- (void)cg_noteSavePanelResult:(NSSavePanel *)panel
{
	NSString *name = [[panel URL] path];

	_cgSavePanelHasRun = YES;
	[_fileTypeFromLastRunSavePanel release];
	_fileTypeFromLastRunSavePanel = [_fileType copy];
	_fileNameExtensionWasHidden = [panel isExtensionHidden];
	[name retain];
	[_lastComponentOfFileName release];
	_lastComponentOfFileName = (name != nil) ? [name lastPathComponent] : nil;
	[_lastComponentOfFileName retain];
	[name release];
}

- (NSString *)fileTypeFromLastRunSavePanel
{
	return _cgSavePanelHasRun ? _fileTypeFromLastRunSavePanel : nil;
}

- (BOOL)fileNameExtensionWasHiddenInLastRunSavePanel
{
	return _cgSavePanelHasRun ? _fileNameExtensionWasHidden : NO;
}

/* ---- PAGE LAYOUT ----------------------------------------------------------------------------------- */

- (BOOL)preparePageLayout:(NSPageLayout *)pageLayout
{
	(void)pageLayout;
	return YES;
}

/* **THE PANEL IS THE EXISTING ONE, WITH A COPY OF THE TICKET.** The copy is released by the private callback whether
 * the user accepts or cancels; `-shouldChangePrintInfo:` is the hook between the panel and the document's ticket. */
- (void)runPageLayout:(id)sender
{
	NSPrintInfo *copy = [[self printInfo] copy];

	(void)sender;
	[self runModalPageLayoutWithPrintInfo:copy delegate:self
			      didRunSelector:@selector(cg_pageLayoutDidRun:accepted:contextInfo:)
				 contextInfo:(void *)copy];
}

- (void)cg_pageLayoutDidRun:(NSDocument *)document accepted:(NSInteger)code contextInfo:(void *)contextInfo
{
	NSPrintInfo *printInfo = (NSPrintInfo *)contextInfo;

	(void)document;
	if (code == NSOKButton && [self shouldChangePrintInfo:printInfo]) {
		[self setPrintInfo:printInfo];
	}
	[printInfo release];
}

/* ---- ERROR PRESENTATION ----------------------------------------------------------------------------- */

- (NSError *)willPresentError:(NSError *)error
{
	return error;
}

- (BOOL)presentError:(NSError *)error
{
	NSError *custom = [self willPresentError:error];
	id next = (_cg_documentController != nil) ? _cg_documentController : [NSDocumentController sharedDocumentController];

	if ([next respondsToSelector:@selector(presentError:)]) {
		return [next presentError:custom];
	}
	return [[NSApplication sharedApplication] presentError:custom];
}

- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
   didPresentSelector:(SEL)didPresentSelector contextInfo:(void *)contextInfo
{
	NSError *custom = [self willPresentError:error];
	id next = (_cg_documentController != nil) ? _cg_documentController : [NSDocumentController sharedDocumentController];

	if ([next respondsToSelector:@selector(presentError:modalForWindow:delegate:didPresentSelector:contextInfo:)]) {
		[next presentError:custom modalForWindow:window delegate:delegate didPresentSelector:didPresentSelector
			 contextInfo:contextInfo];
		return;
	}
	[[NSApplication sharedApplication] presentError:custom modalForWindow:window delegate:delegate
				      didPresentSelector:didPresentSelector contextInfo:contextInfo];
}

/* ---- SCRIPTING -------------------------------------------------------------------------------------- */

- (id)handleCloseScriptCommand:(id)command
{
	(void)command;
	fn_refuse_window("-handleCloseScriptCommand:", "the scripting suite (this tree has no NSScriptCommand)");
	return nil;
}

- (id)handleSaveScriptCommand:(id)command
{
	(void)command;
	fn_refuse_window("-handleSaveScriptCommand:", "the scripting suite (this tree has no NSScriptCommand)");
	return nil;
}

- (id)objectSpecifier
{
	fn_refuse_window("-objectSpecifier", "the scripting suite (this tree has no NSScriptObjectSpecifier)");
	return nil;
}

/* ---- CHANGE COUNT AND UNDO ------------------------------------------------------------------------ */

- (BOOL)isDocumentEdited
{
	return _changeCount != 0;
}

- (void)updateChangeCount:(NSDocumentChangeType)change
{
	switch (change) {
	case NSChangeDone:
	case NSChangeRedone:
		_changeCount++;
		_hasUnautosavedChanges = YES;
		break;
	case NSChangeUndone:
		/* **SIGNED, NOT CLAMPED.** An undo below zero is a document whose edits have all been taken back; it is still a
		 * document with an edit history the next redo will walk, and zeroing it would put the count out of step. */
		_changeCount--;
		_hasUnautosavedChanges = YES;
		break;
	case NSChangeCleared:
		_changeCount = 0;
		_hasUnautosavedChanges = NO;
		break;
	case NSChangeReadOtherContents:
		/* **THE REOPENED DOCUMENT IS EDITED BUT NOT "UNAUTOSAVED".** Apple's prose says this change has no effect on
		 * `-hasUnautosavedChanges`; the contents it was reopened from are already the autosave. */
		_changeCount = 1;
		break;
	case NSChangeAutosaved:
		/* An autosave makes the ON-DISK copy current but does not make the document unedited. */
		_hasUnautosavedChanges = NO;
		break;
	}
	{
		NSArray *controllers = [[NSArray alloc] initWithArray:_windowControllers];
		NSUInteger i;

		for (i = 0; i < [controllers count]; i++) {
			[(NSWindowController *)[controllers objectAtIndex:i] setDocumentEdited:[self isDocumentEdited]];
		}
		[controllers release];
	}
}

- (void)setUndoManager:(NSUndoManager *)undoManager
{
	if (undoManager == _undoManager) {
		return;
	}
	if (_undoManager != nil) {
		NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];

		[centre removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:_undoManager];
		[centre removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:_undoManager];
		[_undoManager release];
	}
	_undoManager = [undoManager retain];
	_hasUndoManager = (_undoManager != nil);
	if (_undoManager != nil) {
		NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];

		[centre addObserver:self selector:@selector(cg_undoManagerDidUndo:)
			       name:NSUndoManagerDidUndoChangeNotification object:_undoManager];
		[centre addObserver:self selector:@selector(cg_undoManagerDidRedo:)
			       name:NSUndoManagerDidRedoChangeNotification object:_undoManager];
	}
}

- (NSUndoManager *)undoManager
{
	if (_undoManager == nil && _hasUndoManager) {
		NSUndoManager *created = [[NSUndoManager alloc] init];

		[self setUndoManager:created];
		[created release];
	}
	return _undoManager;
}

- (void)setHasUndoManager:(BOOL)hasUndoManager
{
	if (!hasUndoManager) {
		[self setUndoManager:nil];	/* which also clears the flag and the observers */
		return;
	}
	_hasUndoManager = YES;
}

- (BOOL)hasUndoManager
{
	return _hasUndoManager;
}

- (void)cg_undoManagerDidUndo:(NSNotification *)notification
{
	(void)notification;
	[self updateChangeCount:NSChangeUndone];
}

- (void)cg_undoManagerDidRedo:(NSNotification *)notification
{
	(void)notification;
	[self updateChangeCount:NSChangeRedone];
}

/* ---- WINDOWS -------------------------------------------------------------------------------------- */

- (void)makeWindowControllers
{
	NSString *nibName = [self windowNibName];

	if (nibName != nil) {
		NSWindowController *controller = [[NSWindowController alloc] initWithWindowNibName:nibName owner:self];

		[self addWindowController:controller];
		[controller release];
	}
}

- (NSString *)windowNibName
{
	return nil;
}

- (void)windowControllerWillLoadNib:(NSWindowController *)windowController
{
	(void)windowController;
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController
{
	(void)windowController;
}

- (void)setWindow:(NSWindow *)window
{
	/* NOT RETAINED: an IBOutlet. The window controller owns the window; this is the nib's owner connection. */
	_window = window;
}

- (void)addWindowController:(NSWindowController *)windowController
{
	id previous;

	if (windowController == nil || [_windowControllers containsObject:windowController]) {
		return;
	}
	/* **A CONTROLLER BELONGS TO ONE DOCUMENT**, which is Apple's rule: detach it from wherever it was first. */
	previous = [windowController document];
	if (previous != nil && previous != self
	    && [previous respondsToSelector:@selector(removeWindowController:)]) {
		[previous removeWindowController:windowController];
	}
	[windowController setDocument:self];
	[_windowControllers addObject:windowController];
}

- (void)removeWindowController:(NSWindowController *)windowController
{
	if (windowController == nil || ![_windowControllers containsObject:windowController]) {
		return;
	}
	[windowController setDocument:nil];
	[_windowControllers removeObject:windowController];
}

- (void)showWindows
{
	NSArray *controllers = [[NSArray alloc] initWithArray:_windowControllers];
	NSUInteger i;

	for (i = 0; i < [controllers count]; i++) {
		[(NSWindowController *)[controllers objectAtIndex:i] showWindow:self];
	}
	[controllers release];
}

- (NSArray *)windowControllers
{
	return [NSArray arrayWithArray:_windowControllers];
}

- (NSWindow *)windowForSheet
{
	if ([_windowControllers count] > 0) {
		return [[_windowControllers objectAtIndex:0] window];
	}
	return _window;
}

- (NSString *)displayName
{
	NSString *name = (_lastComponentOfFileName != nil && [_lastComponentOfFileName length] > 0)
		? _lastComponentOfFileName
		: ((_fileURL != nil) ? [[_fileURL path] lastPathComponent] : nil);

	if (name == nil || [name length] == 0) {
		return @"Untitled";
	}
	/* **THE SAVE PANEL MAY HAVE HIDDEN THE EXTENSION**, and Apple's display name honours that choice. */
	if (_cgSavePanelHasRun && _fileNameExtensionWasHidden && [[name pathExtension] length] > 0) {
		return [name stringByDeletingPathExtension];
	}
	return name;
}

- (void)close
{
	NSArray *controllers = [[NSArray alloc] initWithArray:_windowControllers];
	NSUInteger i;
	id owner = _cg_documentController;

	/* A CLOSED DOCUMENT'S AUTOSAVE IS OBSOLETE. */
	[self cg_removeAutosavedContentsFile];

	for (i = 0; i < [controllers count]; i++) {
		[(NSWindowController *)[controllers objectAtIndex:i] close];
	}
	[controllers release];
	if (owner != nil && [owner respondsToSelector:@selector(removeDocument:)]) {
		[owner removeDocument:self];
	} else {
		[[NSDocumentController sharedDocumentController] removeDocument:self];
	}
}

/* ---- TYPES AND VALIDATION ------------------------------------------------------------------------- */

+ (NSArray *)readableTypes
{
	return [NSArray array];
}

+ (NSArray *)writableTypes
{
	return [NSArray array];
}

+ (BOOL)isNativeType:(NSString *)type
{
	(void)type;
	return NO;
}

- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)saveOperation
{
	NSArray *types = [[self class] writableTypes];

	if (saveOperation == NSSaveToOperation) {
		return types;
	}
	{
		NSMutableArray *native = [NSMutableArray array];
		NSUInteger i;

		for (i = 0; i < [types count]; i++) {
			NSString *type = [types objectAtIndex:i];

			if ([[self class] isNativeType:type]) {
				[native addObject:type];
			}
		}
		return native;
	}
}

- (NSString *)fileNameExtensionForType:(NSString *)typeName saveOperation:(NSSaveOperationType)saveOperation
{
	/* **THE CONTROLLER'S TYPE TABLE IS THE DEFAULT SOURCE.** Apple's default asks the workspace for a UTI's preferred
	 * extension or the controller for the type's extension list; this tier has no UTI database, so the list is the
	 * honest answer and its first entry is the extension. */
	id owner = (_cg_documentController != nil) ? _cg_documentController : [NSDocumentController sharedDocumentController];
	(void)saveOperation;
	if (typeName != nil && [owner respondsToSelector:@selector(fileExtensionsFromType:)]) {
		NSArray *extensions = [owner fileExtensionsFromType:typeName];

		if ([extensions count] > 0) {
			return [extensions objectAtIndex:0];
		}
	}
	return nil;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	SEL action = [anItem action];

	/* **`sel_isEqual`, NOT `==`, AND THIS IS THE FIX §9 OF THE HANDOFF OWED.** This runtime gives each image its own
	 * `objc_selector` struct for the same name (only the index inside it is shared), so the selector an APPLICATION's
	 * toolbar item carries is a different ADDRESS from this library's `@selector(saveDocument:)`. `==` answered NO for
	 * every action, which disabled Save and Revert for every caller outside this library; `sel_isEqual` falls back to the
	 * name, which is the comparison the runtime documents for exactly this. */
	if (sel_isEqual(action, @selector(saveDocument:)) || sel_isEqual(action, @selector(revertDocumentToSaved:))) {
		return _fileURL != nil && _fileType != nil;
	}
	/* SAVE AS AND EXPORT NEED THE PANEL, so they are honestly disabled until it exists. */
	return NO;
}

/* ---- THE CONTROLLER'S ASSOCIATION ----------------------------------------------------------------- */

- (id)cg_documentController
{
	return _cg_documentController;
}

- (void)cg_setDocumentController:(id)controller
{
	_cg_documentController = controller;
}

/* ============================================================================================ *
 * THE PRINT DOORS.                                                                              *
 * ============================================================================================ */

/* **THE TICKET IS A COPY OF THE SHARED ONE ON FIRST ASK**, so a document's paper size is its own; the copy is made
 * through `-initWithDictionary:`, which is the same door a caller building a ticket by hand uses. */
- (NSPrintInfo *)printInfo
{
	if (_printInfo == nil) {
		_printInfo = [[NSPrintInfo alloc] initWithDictionary:[[NSPrintInfo sharedPrintInfo] dictionary]];
	}
	return _printInfo;
}

- (void)setPrintInfo:(NSPrintInfo *)printInfo
{
	NSPrintInfo *old = _printInfo;

	_printInfo = [printInfo retain];
	[old release];
}

- (BOOL)shouldChangePrintInfo:(NSPrintInfo *)newPrintInfo
{
	(void)newPrintInfo;
	return YES;
}

/* **THE OPERATION PRINTS THE DOCUMENT'S WINDOW CONTENT, WHICH IS THE ONE ANSWER THIS CLASS CAN GIVE.** A document with a
 * paginated view of its own overrides this door and returns an operation over that view; every other door below then
 * works unchanged, which is why the seam is here rather than in `-printDocument:`. */
- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings error:(NSError **)outError
{
	NSWindow *window = (_window != nil) ? _window : [self windowForSheet];
	NSView *view = ([window contentView] != nil) ? [window contentView] : nil;
	NSPrintOperation *operation;

	if (view == nil) {
		if (outError != NULL) {
			*outError = [NSError errorWithDomain:@"NSDocumentPrintErrorDomain" code:1
						    userInfo:[NSDictionary dictionaryWithObject:
							      @"the document has no window to print"
											    forKey:NSLocalizedDescriptionKey]];
		}
		return nil;
	}
	operation = [NSPrintOperation printOperationWithView:view printInfo:[self printInfo]];
	if (printSettings != nil) {
		[[[self printInfo] dictionary] addEntriesFromDictionary:printSettings];
	}
	[operation setJobTitle:[self displayName]];
	return operation;
}

- (void)printDocument:(id)sender
{
	(void)sender;
	[self printShowingPrintPanel:YES];
}

- (void)printShowingPrintPanel:(BOOL)showPanels
{
	NSPrintOperation *operation = [self printOperationWithSettings:nil error:NULL];

	if (operation == nil) {
		return;
	}
	[operation setShowsPrintPanel:showPanels];
	[operation runOperation];
}

- (void)printDocumentWithSettings:(NSDictionary *)printSettings showPrintPanel:(BOOL)showPrintPanel
			 delegate:(id)delegate didPrintSelector:(SEL)didPrintSelector
		      contextInfo:(void *)contextInfo
{
	NSPrintOperation *operation = [self printOperationWithSettings:printSettings error:NULL];

	if (operation == nil) {
		if (delegate != nil && didPrintSelector != NULL) {
			typedef void (*AGDocumentDidPrint)(id, SEL, id, BOOL, void *);

			((AGDocumentDidPrint)objc_msgSend)(delegate, didPrintSelector, self, NO, contextInfo);
		}
		return;
	}
	[operation setShowsPrintPanel:showPrintPanel];
	[self runModalPrintOperation:operation delegate:delegate didRunSelector:didPrintSelector
			 contextInfo:contextInfo];
}

- (void)runModalPrintOperation:(NSPrintOperation *)printOperation delegate:(id)delegate
		didRunSelector:(SEL)didRunSelector contextInfo:(void *)contextInfo
{
	NSWindow *sheetWindow = [self windowForSheet];

	if (sheetWindow != nil && [[NSApplication sharedApplication] isRunning]) {
		[printOperation runOperationModalForWindow:sheetWindow delegate:delegate
					    didRunSelector:didRunSelector contextInfo:contextInfo];
		return;
	}
	{
		BOOL ok = [printOperation runOperation];

		if (delegate != nil && didRunSelector != NULL) {
			typedef void (*AGDocumentDidPrint)(id, SEL, id, BOOL, void *);

			((AGDocumentDidPrint)objc_msgSend)(delegate, didRunSelector, self, ok, contextInfo);
		}
	}
}

- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)printInfo
{
	[[NSPageLayout pageLayout] runModalWithPrintInfo:printInfo];
}

- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)printInfo delegate:(id)delegate
			 didRunSelector:(SEL)didRunSelector contextInfo:(void *)contextInfo
{
	NSWindow *sheetWindow = [self windowForSheet];
	NSPageLayout *layout = [NSPageLayout pageLayout];

	/* **THE DOCUMENT MAY REFUSE THE PANEL BEFORE IT IS SHOWN.** Apple's hook is `-preparePageLayout:`; a NO leaves the
	 * ticket alone and does not call the caller back. */
	if (![self preparePageLayout:layout]) {
		/* THE HOOK REFUSED THE PANEL, so the caller is told the user did not accept and the run's context (a print
		 * ticket, in `-runPageLayout:`'s case) is released by the same callback. */
		if (delegate != nil && didRunSelector != NULL) {
			AGDocumentDidLayoutIMP imp = (AGDocumentDidLayoutIMP)[delegate methodForSelector:didRunSelector];

			imp(delegate, didRunSelector, self, NSCancelButton, contextInfo);
		}
		return;
	}
	if (sheetWindow != nil && [[NSApplication sharedApplication] isRunning]) {
		[layout beginSheetWithPrintInfo:printInfo modalForWindow:sheetWindow delegate:delegate
				  didEndSelector:didRunSelector contextInfo:contextInfo];
		return;
	}
	{
		NSInteger code = [layout runModalWithPrintInfo:printInfo];

		if (delegate != nil && didRunSelector != NULL) {
			typedef void (*AGDocumentDidLayout)(id, SEL, id, NSInteger, void *);

			((AGDocumentDidLayout)objc_msgSend)(delegate, didRunSelector, self, code, contextInfo);
		}
	}
}

/* THE SCRIPTING DOOR IS A NAMED REFUSAL, because this tree has no `NSScriptCommand` to be given. */
- (id)handlePrintScriptCommand:(id)command
{
	(void)command;
	fn_refuse_window("-handlePrintScriptCommand:", "the scripting suite: this tree has no NSScriptCommand");
	return nil;
}

@end
