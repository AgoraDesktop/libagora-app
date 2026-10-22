/*
 * document — NSDocument and NSDocumentController: a file, its change count, its undo, its windows, and the controller's
 * type table and recent list.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS THAT A DOCUMENT GOES ROUND A FILE AND COMES BACK THE SAME.** A concrete `NSDocument` subclass implements
 * only `-readFromData:ofType:error:` and `-dataOfType:error:`; the probe creates one untitled, edits it, saves it through
 * the URL doors, opens it with the controller, reverts it from disk, saves it again, and closes it. The default
 * wrapper/data path is exercised in both directions, so a subclass with the modern data pair is enough — which is the point
 * of Apple's layering.
 *
 * **THE CHANGE COUNT IS THE DOCUMENT'S.** After one `NSChangeDone`, `-isDocumentEdited` is YES; the document's own undo
 * manager is asked to undo and redo a registered action, and the count follows through the notifications the document
 * subscribes to. Saving clears it; reverting clears it; opening a file leaves it clean.
 *
 * **AND THE CONTROLLER IS A CONTROLLER, NOT A SHARED GLOBAL IN THIS PROBE.** A subclass supplies a type table of its own
 * (`AGTestText` / `AGDocTextDocument` / `.agdoc`), so the probe does not need an Info.plist: the base's `-typeFromFileExtension:`,
 * `-documentClassForType:` and `-defaultType` are all asked, and the base's make/open paths do the instantiation.
 * `-documentForURL:` must answer the same document for the same URL, opening it twice must not make a third, and the recent
 * list must note what was saved or opened.
 */
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSWindowController.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* ==================================================================================================
 * A TEXT DOCUMENT THAT IMPLEMENTS ONLY THE MODERN DATA PAIR.
 * ================================================================================================ */

@interface AGDocTextDocument : NSDocument
{
	NSString *_text;
}
- (NSString *)text;
- (void)setText:(NSString *)text;
@end

@implementation AGDocTextDocument

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_text = [@"" copy];
	}
	return self;
}

- (void)dealloc
{
	[_text release];
	[super dealloc];
}

- (NSString *)text
{
	return _text;
}

- (void)setText:(NSString *)text
{
	NSString *held = [(text != nil) ? text : @"" copy];

	[_text release];
	_text = held;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

	(void)typeName;
	if (text == nil) {
		if (outError != NULL) {
			*outError = [NSError errorWithDomain:@"AGDocumentTest"
							code:1
						    userInfo:[NSDictionary dictionaryWithObject:@"The file is not UTF-8."
										    forKey:NSLocalizedDescriptionKey]];
		}
		return NO;
	}
	[self setText:text];
	[text release];
	return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	(void)typeName;
	(void)outError;
	return [_text dataUsingEncoding:NSUTF8StringEncoding];
}

/* ONE WINDOW PER DOCUMENT, made by hand rather than from a nib — a document's window machinery is exactly this list. */
- (void)makeWindowControllers
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 200.0, 100.0)
						      styleMask:NSTitledWindowMask
							backing:NSBackingStoreBuffered
							  defer:NO];
	NSWindowController *controller = [[NSWindowController alloc] initWithWindow:window];

	[self addWindowController:controller];
	[controller release];
	[window release];
}

+ (NSArray *)readableTypes
{
	return [NSArray arrayWithObject:@"AGTestText"];
}

+ (NSArray *)writableTypes
{
	return [NSArray arrayWithObject:@"AGTestText"];
}

+ (BOOL)isNativeType:(NSString *)type
{
	return [type isEqualToString:@"AGTestText"];
}

@end

/* ==================================================================================================
 * THE CONTROLLER'S TYPE TABLE, WITHOUT AN INFO.PLIST.
 * ================================================================================================ */

@interface AGDocController : NSDocumentController
@end

@implementation AGDocController

- (NSString *)defaultType
{
	return @"AGTestText";
}

- (NSArray *)documentClassNames
{
	return [NSArray arrayWithObject:@"AGDocTextDocument"];
}

- (Class)documentClassForType:(NSString *)typeName
{
	return [typeName isEqualToString:@"AGTestText"] ? [AGDocTextDocument class] : Nil;
}

- (NSString *)displayNameForType:(NSString *)typeName
{
	(void)typeName;
	return @"Agora Test Document";
}

- (NSString *)typeFromFileExtension:(NSString *)fileNameExtension
{
	return [[fileNameExtension lowercaseString] isEqualToString:@"agdoc"] ? @"AGTestText" : nil;
}

- (NSArray *)fileExtensionsFromType:(NSString *)typeName
{
	return [typeName isEqualToString:@"AGTestText"]
		? [NSArray arrayWithObject:@"agdoc"] : [NSArray array];
}

@end

/* ==================================================================================================
 * A DELEGATE FOR did-save AND did-close-all, and an undo target that counts its calls.
 * ================================================================================================ */

@interface AGDocWatcher : NSObject
{
@public
	int saveCalls;
	int savedOK;
	int closeCalls;
	int closedAll;
	int undoCalls;
	NSUndoManager *undoManager;	/* BORROWED: used by -bump: to register its own inverse */
}
- (void)document:(NSDocument *)document didSave:(BOOL)flag contextInfo:(void *)contextInfo;
- (void)controller:(NSDocumentController *)controller didCloseAll:(BOOL)flag contextInfo:(void *)contextInfo;
- (void)bump:(id)object;
@end

@implementation AGDocWatcher

- (void)document:(NSDocument *)document didSave:(BOOL)flag contextInfo:(void *)contextInfo
{
	(void)document;
	(void)contextInfo;
	saveCalls++;
	savedOK = flag ? 1 : 0;
}

- (void)controller:(NSDocumentController *)controller didCloseAll:(BOOL)flag contextInfo:(void *)contextInfo
{
	(void)controller;
	(void)contextInfo;
	closeCalls++;
	closedAll = flag ? 1 : 0;
}

/* **AN UNDO ACTION THAT REGISTERS ITS OWN INVERSE**, which is what makes redo exist at all: the manager's redo stack is
 * built from the actions the undo runs, and an action that registers nothing leaves nothing to redo. */
- (void)bump:(id)object
{
	(void)object;
	undoCalls++;
	if (undoManager != nil) {
		[undoManager registerUndoWithTarget:self selector:@selector(bump:) object:nil];
	}
}

@end

/* ================================================================================================== */

int main(void)
{
	@autoreleasepool {
		NSFileManager *files = [NSFileManager defaultManager];
		/* **NOT `NSTemporaryDirectory()`: this tree's Foundation answers `/System/Temporary Files/`, which does not exist
		 * on this host** — MEASURED, the directory could not be made and every save failed with ENOENT. The probe is
		 * Linux-hosted, so it names the host's temporary directory itself. */
		NSString *directory = [NSString stringWithFormat:@"/tmp/agora-document-test-%d", (int)getpid()];
		NSString *path = [directory stringByAppendingPathComponent:@"sample.agdoc"];
		NSURL *url = [NSURL fileURLWithPath:path];
		AGDocController *controller = [[AGDocController alloc] init];
		AGDocWatcher *watcher = [[AGDocWatcher alloc] init];

		setvbuf(stdout, NULL, _IONBF, 0);
		[files removeItemAtPath:directory error:NULL];
		(void)[files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];

		/* ============================================================================================
		 * 1. THE TYPE TABLE THE SUBCLASS OWNS.
		 * ========================================================================================== */
		{
			check([[controller documents] count] == 0, "a new controller holds no documents");
			check([[controller defaultType] isEqualToString:@"AGTestText"],
			      "the default type is the subclass's");
			check([controller documentClassForType:@"AGTestText"] == [AGDocTextDocument class],
			      "and the type maps to the document class");
			check([[controller documentClassNames] containsObject:@"AGDocTextDocument"],
			      "the class name is in the controller's list");
			check([[controller displayNameForType:@"AGTestText"] isEqualToString:@"Agora Test Document"],
			      "a display name is answered for the type");
			check([[controller typeFromFileExtension:@"agdoc"] isEqualToString:@"AGTestText"],
			      "an extension maps back to the type");
			check([[[controller fileExtensionsFromType:@"AGTestText"] lastObject] isEqualToString:@"agdoc"],
			      "and the type answers its extensions");
			{
				NSURL *typed = [NSURL fileURLWithPath:@"/tmp/anything.agdoc"];
				NSError *error = nil;

				check([[controller typeForContentsOfURL:typed error:&error] isEqualToString:@"AGTestText"]
					      && error == nil,
				      "a URL's extension finds the type through the same table");
			}
		}

		/* ============================================================================================
		 * 2. AN UNTITLED DOCUMENT, ITS CHANGE COUNT AND ITS UNDO.
		 * ========================================================================================== */
		{
			NSError *error = nil;
			AGDocTextDocument *document = [controller openUntitledDocumentAndDisplay:NO error:&error];

			check(document != nil && error == nil, "the controller makes an untitled document");
			check([document isKindOfClass:[AGDocTextDocument class]], "of the class the type names");
			check([[document fileType] isEqualToString:@"AGTestText"] && [document fileURL] == nil,
			      "with a type and no file URL");
			check(![document isDocumentEdited], "and it starts unedited");
			check([[document displayName] isEqualToString:@"Untitled"], "an untitled document is named Untitled");
			check([[controller documents] count] == 1 && [controller documentForURL:url] == nil,
			      "it is in the list, and no document owns the temp URL yet");

			[document setText:@"first version"];
			[document updateChangeCount:NSChangeDone];
			check([document isDocumentEdited], "one change makes it edited");
			check([document hasUndoManager] && [document undoManager] != nil,
			      "the undo manager is created on demand");

			/* **THE COUNT FOLLOWS THE UNDO MANAGER'S OWN NOTIFICATIONS.** A registered action is undone and redone; the
			 * document hears the notification and moves the count it owns, which is the wiring a value check alone would
			 * not see. */
			watcher->undoManager = [document undoManager];
			[[document undoManager] registerUndoWithTarget:watcher selector:@selector(bump:) object:nil];
			[[document undoManager] undo];
			check(watcher->undoCalls == 1, "the registered action ran when undone");
			check(![document isDocumentEdited], "and the change count came back to zero");
			[[document undoManager] redo];
			check([document isDocumentEdited], "redo makes it edited again");

			/* ============================================================================================
			 * 3. SAVE THROUGH THE URL DOOR, AND THE FILE IT WROTE.
			 * ========================================================================================== */
			{
				NSError *saveError = nil;
				NSData *onDisk;
				NSString *diskText;

				check([document saveToURL:url ofType:@"AGTestText" forSaveOperation:NSSaveAsOperation
						    error:&saveError] && saveError == nil,
				      "a save-as writes the document");
				check([files fileExistsAtPath:path], "the file is there");
				onDisk = [NSData dataWithContentsOfFile:path];
				diskText = [[[NSString alloc] initWithData:onDisk encoding:NSUTF8StringEncoding] autorelease];
				check([diskText isEqualToString:@"first version"], "and holds the document's text");
				check([[document fileURL] isEqual:url] && [[document fileType] isEqualToString:@"AGTestText"],
				      "the document records where and what it now is");
				check([document fileModificationDate] != nil, "and the file's modification date");
				check(![document isDocumentEdited], "a successful save clears the change count");
				check([[document displayName] isEqualToString:@"sample.agdoc"],
				      "the display name is the file's last component");
				check([[controller recentDocumentURLs] containsObject:url],
				      "and the owning controller notes it as recent");
			}

			/* A SAVE (not a save-as) through the same URL, and the delegate form's callback. */
			[document setText:@"second version"];
			[document updateChangeCount:NSChangeDone];
			[document saveToURL:url ofType:@"AGTestText" forSaveOperation:NSSaveOperation
				   delegate:watcher didSaveSelector:@selector(document:didSave:contextInfo:) contextInfo:NULL];
			check(watcher->saveCalls == 1 && watcher->savedOK == 1,
			      "the delegate form calls back with did-save YES");
			check(![document isDocumentEdited], "and the save is real, not only announced");

			/* ============================================================================================
			 * 4. OPEN IT WITH THE CONTROLLER: A NEW DOCUMENT, READ THROUGH THE WRAPPER PATH.
			 * ========================================================================================== */
			[document close];
			check([[controller documents] count] == 0, "closing a document removes it from the controller");
			{
				NSError *openError = nil;
				AGDocTextDocument *opened = [controller openDocumentWithContentsOfURL:url display:NO
											       error:&openError];

				check(opened != nil && openError == nil, "the controller opens the file");
				check(opened != nil && [opened isKindOfClass:[AGDocTextDocument class]],
				      "as a new document of the registered class");
				check([[opened text] isEqualToString:@"second version"],
				      "whose text came back through wrapper -> data -> readFromData:");
				check([[opened fileURL] isEqual:url]
					      && [[opened fileType] isEqualToString:@"AGTestText"],
				      "with the URL and type recorded");
				check(![opened isDocumentEdited], "and a clean change count");
				check([[controller documents] count] == 1, "the opened document is in the list");
				check([controller documentForURL:url] == opened, "the URL answers the opened document");
				check([controller openDocumentWithContentsOfURL:url display:NO error:NULL] == opened
					      && [[controller documents] count] == 1,
				      "opening the same URL twice does not make a second");

				/* REVERT: the buffer is wrong, and the file is right. */
				[opened setText:@"unsaved scribble"];
				[opened updateChangeCount:NSChangeDone];
				[opened revertDocumentToSaved:nil];
				check([[opened text] isEqualToString:@"second version"], "revert reads the file again");
				check(![opened isDocumentEdited], "and clears the change count");
			}
		}

		/* ============================================================================================
		 * 5. WINDOWS, SAVE-ALL, AND CLOSING THE SET.
		 * ========================================================================================== */
		{
			NSError *error = nil;
			AGDocTextDocument *document = [controller openUntitledDocumentAndDisplay:YES error:&error];
			AGDocTextDocument *second = [controller openUntitledDocumentAndDisplay:NO error:NULL];

			check(document != nil && [[document windowControllers] count] == 1,
			      "displaying a document makes its window controller");
			check([document windowForSheet] == [[[document windowControllers] objectAtIndex:0] window],
			      "and the sheet window is that controller's window");

			[document setText:@"edited"];
			[document updateChangeCount:NSChangeDone];
			[second setText:@"edited too"];
			[second updateChangeCount:NSChangeDone];
			check([controller hasEditedDocuments], "the controller sees an edited document");
			[controller closeAllDocumentsWithDelegate:watcher
				       didCloseAllSelector:@selector(controller:didCloseAll:contextInfo:)
					      contextInfo:NULL];
			check(watcher->closeCalls == 1 && watcher->closedAll == 0,
			      "closing all refuses while a document is edited, and says so");
			check([[controller documents] count] == 3, "and nothing was closed");

			[document updateChangeCount:NSChangeCleared];
			[second updateChangeCount:NSChangeCleared];
			[controller closeAllDocumentsWithDelegate:watcher
				       didCloseAllSelector:@selector(controller:didCloseAll:contextInfo:)
					      contextInfo:NULL];
			check(watcher->closeCalls == 2 && watcher->closedAll == 1,
			      "with the edits cleared, the set closes and says YES");
			check([[controller documents] count] == 0, "and the list is empty");
		}

		/* ============================================================================================
		 * 6. THE 10.3 SPELLINGS, AND THE DEPRECATED DATA HOOKS.
		 * ========================================================================================== */
		{
			AGDocTextDocument *made = [controller makeDocumentWithContentsOfFile:path ofType:@"AGTestText"];
			AGDocTextDocument *writer = [controller makeUntitledDocumentOfType:@"AGTestText" error:NULL];
			AGDocTextDocument *opened = [controller openDocumentWithContentsOfFile:path display:NO];

			check(made != nil && [[made text] isEqualToString:@"second version"],
			      "makeDocumentWithContentsOfFile: reads the same file");
			check(opened != nil && [[opened text] isEqualToString:@"second version"],
			      "openDocumentWithContentsOfFile: opens and records it");
			check([controller documentForFileName:path] == opened,
			      "documentForFileName: answers the open document");
			[writer setText:@"written the old way"];
			check([writer writeToFile:path ofType:@"AGTestText"], "writeToFile:ofType: writes it");
			[writer setText:@"changed"];
			check([writer readFromFile:path ofType:@"AGTestText"]
				      && [[writer text] isEqualToString:@"written the old way"],
			      "and readFromFile:ofType: reads it back");
			check([[[writer writableTypesForSaveOperation:NSSaveOperation] lastObject]
				      isEqualToString:@"AGTestText"],
			      "the writable types are filtered through +isNativeType:");
			[opened close];
		}

		/* CLEAN UP: the recent list and the temp directory. */
		[controller clearRecentDocuments:nil];
		check([[controller recentDocumentURLs] count] == 0, "the recent list can be cleared");
		[files removeItemAtPath:directory error:NULL];

		[controller release];
		[watcher release];

		if (failures == 0) {
			printf("document: all checks passed\n");
			return 0;
		}
		printf("document: FAILURES\n");
		return 1;
	}
}
