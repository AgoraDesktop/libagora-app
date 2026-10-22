/*
 * NSDocument — the file, the contents, the change count, the undo manager and the windows.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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

/* THE UNDO OBSERVERS, declared before the implementation that registers them. */
@interface NSDocument (AGPrivate)
- (void)cg_undoManagerDidUndo:(NSNotification *)notification;
- (void)cg_undoManagerDidRedo:(NSNotification *)notification;
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
	}
	return self;
}

- (void)dealloc
{
	[self setUndoManager:nil];
	[_fileURL release];
	[_fileType release];
	[_fileModificationDate release];
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

	[_fileURL release];
	_fileURL = held;
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
	/* **AN EXPORT IS A COPY, NOT THE DOCUMENT'S FILE.** `NSSaveToOperation` writes where the panel said and stops: the
	 * document keeps its URL and type, stays edited if it was, and is not noted as recent. Only a save or save-as makes
	 * the written file the document's own. */
	if (saveOperation == NSSaveToOperation) {
		return YES;
	}
	[self setFileURL:absoluteURL];
	[self setFileType:typeName];
	[self setFileModificationDate:fn_modification_date(absoluteURL)];
	[self updateChangeCount:(saveOperation == NSAutosaveOperation) ? NSChangeAutosaved : NSChangeCleared];
	if (saveOperation != NSAutosaveOperation) {
		/* **THE RECENT LIST IS THE OWNING CONTROLLER'S.** A document made by a controller made by hand belongs to that
		 * controller, not to the shared one; the shared one is only the fallback for a document nobody added. */
		{
			id owner = (_cg_documentController != nil) ? _cg_documentController
								  : [NSDocumentController sharedDocumentController];

			if ([owner respondsToSelector:@selector(noteNewRecentDocument:)]) {
				[owner noteNewRecentDocument:self];
			}
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
		name = [[_fileURL path] lastPathComponent];
	} else {
		id controller = (_cg_documentController != nil) ? _cg_documentController
							       : [NSDocumentController sharedDocumentController];

		directory = [controller currentDirectory];
		name = @"Untitled";
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
		break;
	case NSChangeUndone:
		/* **SIGNED, NOT CLAMPED.** An undo below zero is a document whose edits have all been taken back; it is still a
		 * document with an edit history the next redo will walk, and zeroing it would put the count out of step. */
		_changeCount--;
		break;
	case NSChangeCleared:
		_changeCount = 0;
		break;
	case NSChangeReadOtherContents:
		_changeCount = 1;
		break;
	case NSChangeAutosaved:
		/* An autosave makes the ON-DISK copy current but does not make the document unedited. */
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
	if (_fileURL != nil) {
		NSString *name = [[_fileURL path] lastPathComponent];

		if (name != nil && [name length] > 0) {
			return name;
		}
	}
	return @"Untitled";
}

- (void)close
{
	NSArray *controllers = [[NSArray alloc] initWithArray:_windowControllers];
	NSUInteger i;
	id owner = _cg_documentController;

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
	(void)typeName;
	(void)saveOperation;
	return nil;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	SEL action = [anItem action];

	if (action == @selector(saveDocument:) || action == @selector(revertDocumentToSaved:)) {
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

@end
