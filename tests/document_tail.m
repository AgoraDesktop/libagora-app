/*
 * document_tail — NSDocument's autosave, close review, filename state, page-layout hooks and error chain, plus
 * NSDocumentController's timer, close-all review and error forwarder.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE AUTOSAVE FILE IS SEPARATE FROM THE DOCUMENT'S FILE, AND THE PROBE PROVES BOTH HALVES.** A document with no
 * URL autosaves to a controller-chosen location; its `fileURL` stays nil, its `autosavedContentsFileURL` names the
 * copy, and `hasUnautosavedChanges` clears while `isDocumentEdited` stays YES. A reopened document reads that copy
 * through `-initForURL:withContentsOfURL:`, and a real save deletes the copy and clears the record.
 *
 * **MODAL PROMPTS ARE DRIVEN THROUGH PRIVATE SEAMS.** `-setCloseDecision:` is the alert's return code without a
 * panel; the error chain is checked with a recorder as the controller's next presenter. That keeps the Apple-shaped
 * asynchronous paths in the implementation while making the decisions testable offscreen.
 */
#import <AppKit/NSDocument.h>
#import <AppKit/NSDocumentController.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSWindowController.h>
#import <AppKit/NSAlert.h>
#import <Foundation/NSError.h>
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

/* ---- PRIVATE SEAMS THE IMPLEMENTATION PROVIDES FOR EXACTLY THIS KIND OF PROBE ---------------------- */

@interface NSDocument (AGTailSeams)
- (void)setCloseDecision:(NSInteger)code;
@end

@interface NSDocumentController (AGTailSeams)
- (void)cg_setAutosaveDirectoryPath:(NSString *)path;
- (void)cg_setErrorPresenter:(id)presenter;
- (void)cg_reopenAutosavedDocuments;
- (NSString *)cg_autosaveDirectory;
- (NSURL *)cg_autosaveURLForDocument:(NSDocument *)document typeName:(NSString *)typeName;
@end

/* ---- THE DOCUMENT AND CONTROLLER THE PROBE OWNS ---------------------------------------------------- */

@interface AGTailDocument : NSDocument
{
	NSString *_text;
}
- (NSString *)text;
- (void)setText:(NSString *)text;
@end

@implementation AGTailDocument

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

- (NSString *)text { return _text; }
- (void)setText:(NSString *)text
{
	NSString *copy = [(text != nil) ? text : @"" copy];

	[_text release];
	_text = copy;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

	(void)typeName;
	if (text == nil) {
		if (outError != NULL) {
			*outError = [NSError errorWithDomain:@"AGTail" code:1
						    userInfo:[NSDictionary dictionaryWithObject:@"not UTF-8"
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
	(void)typeName; (void)outError;
	return [_text dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSError *)willPresentError:(NSError *)error
{
	NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:[error userInfo]];

	[info setObject:@"document" forKey:@"seenBy"];
	return [NSError errorWithDomain:[error domain] code:[error code] userInfo:info];
}

@end

@interface AGTailController : NSDocumentController
@end

@implementation AGTailController
- (Class)documentClassForType:(NSString *)typeName
{
	(void)typeName;
	return [AGTailDocument class];
}
- (NSString *)defaultType { return @"AGTailText"; }
- (NSString *)displayNameForType:(NSString *)typeName { (void)typeName; return @"Tail Document"; }
- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)outError
{
	(void)url; (void)outError;
	return @"AGTailText";
}
- (NSArray *)fileExtensionsFromType:(NSString *)typeName
{
	(void)typeName;
	return [NSArray arrayWithObject:@"agtail"];
}
@end

/* THE ERROR CHAIN'S END, and the recorder the controller forwards to. */
@interface AGErrorRecorder : NSObject
{
@public
	int presentCalls;
	NSError *lastError;
}
@end

@implementation AGErrorRecorder
- (void)dealloc { [lastError release]; [super dealloc]; }
- (BOOL)presentError:(NSError *)error
{
	presentCalls++;
	[error retain];
	[lastError release];
	lastError = error;
	return YES;
}
@end

/* THE CALLBACK RECORDER for save/autosave/close/review. */
@interface AGTailWatcher : NSObject
{
@public
	int saves;
	int autosaves;
	int closes;
	int closeAlls;
	int reviews;
	BOOL lastSaveOK;
	BOOL lastAutosaveOK;
	BOOL lastShouldClose;
	BOOL lastCloseAll;
	BOOL lastReviewAll;
}
@end

@implementation AGTailWatcher
- (void)document:(NSDocument *)document didSave:(BOOL)ok contextInfo:(void *)contextInfo
{
	(void)document; (void)contextInfo;
	saves++;
	lastSaveOK = ok;
}
- (void)document:(NSDocument *)document didAutosave:(BOOL)ok contextInfo:(void *)contextInfo
{
	(void)document; (void)contextInfo;
	autosaves++;
	lastAutosaveOK = ok;
}
- (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
{
	(void)document; (void)contextInfo;
	closes++;
	lastShouldClose = shouldClose;
}
- (void)controller:(NSDocumentController *)controller didCloseAll:(BOOL)allClosed contextInfo:(void *)contextInfo
{
	(void)controller; (void)contextInfo;
	closeAlls++;
	lastCloseAll = allClosed;
}
- (void)controller:(NSDocumentController *)controller didReviewAll:(BOOL)allReviewed contextInfo:(void *)contextInfo
{
	(void)controller; (void)contextInfo;
	reviews++;
	lastReviewAll = allReviewed;
}
@end

int main(void)
{
	@autoreleasepool {
		NSString *root = [[NSString stringWithFormat:@"/tmp/agora-document-tail-%d", (int)getpid()] retain];
		NSString *autosaveDir = [root stringByAppendingPathComponent:@"Autosave"];
		NSFileManager *files = [NSFileManager defaultManager];
		AGTailController *controller = [[AGTailController alloc] init];
		AGTailWatcher *watcher = [[AGTailWatcher alloc] init];
		AGTailDocument *document;
		AGTailDocument *reopened;
		NSURL *realURL;
		NSURL *autosaveURL;
		NSError *error = nil;

		(void)[files createDirectoryAtPath:autosaveDir withIntermediateDirectories:YES attributes:nil error:NULL];
		[controller cg_setAutosaveDirectoryPath:autosaveDir];
		realURL = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"saved.agtail"]];

		/* 1. AUTOSAVE A NEVER-SAVED DOCUMENT. */
		document = [controller openUntitledDocumentAndDisplay:NO error:&error];
		check(document != nil && error == nil, "the controller makes an untitled document");
		check([[document fileType] isEqualToString:@"AGTailText"] && [document fileURL] == nil,
		      "it has a type and no URL");
		check([[document displayName] isEqualToString:@"Untitled"], "and its display name is Untitled");
		[document setText:@"autosaved text"];
		[document updateChangeCount:NSChangeDone];
		check([document hasUnautosavedChanges], "a change is unautosaved");
		check([document isDocumentEdited], "and the document is edited");
		[document autosaveDocumentWithDelegate:watcher didAutosaveSelector:@selector(document:didAutosave:contextInfo:)
					 contextInfo:NULL];
		autosaveURL = [[document autosavedContentsFileURL] retain];
		{
			AGTailController *crash = [[AGTailController alloc] init];

			[crash cg_setAutosaveDirectoryPath:autosaveDir];
			[crash cg_reopenAutosavedDocuments];
			check([[crash documents] count] == 1,
			      "a fresh controller reopens the document recorded in the autosave registry");
			check([[[[crash documents] objectAtIndex:0] text] isEqualToString:@"autosaved text"],
			      "with the autosaved text");
			check([[[crash documents] objectAtIndex:0] fileURL] == nil,
			      "as an untitled document");
			[crash release];
		}
		check(watcher->autosaves == 1 && watcher->lastAutosaveOK,
		      "the autosave calls its delegate with YES");
		check(autosaveURL != nil && [files fileExistsAtPath:[autosaveURL path]],
		      "and a separate autosave file exists");
		check([document fileURL] == nil, "the document's own URL is still nil");
		check(![document hasUnautosavedChanges], "the autosave clears the unautosaved flag");
		check([document isDocumentEdited], "but the document is still edited");

		/* 2. REOPEN FROM THE AUTOSAVE, THEN SAVE FOR REAL. */
		reopened = [[AGTailDocument alloc] initForURL:nil withContentsOfURL:autosaveURL ofType:@"AGTailText"
							 error:&error];
		check(reopened != nil && error == nil, "the autosaved contents reopen");
		check([[reopened text] isEqualToString:@"autosaved text"], "with the saved text");
		check([reopened fileURL] == nil, "as an untitled document");
		check([[reopened autosavedContentsFileURL] isEqual:autosaveURL],
		      "whose autosaved URL is the file it came from");
		check([reopened isDocumentEdited] && ![reopened hasUnautosavedChanges],
		      "and it is edited but has nothing further to autosave");

		[document setText:@"saved text"];
		[document saveToURL:realURL ofType:@"AGTailText" forSaveOperation:NSSaveOperation error:&error];
		check(error == nil && [[document fileURL] isEqual:realURL], "a real save takes the document's URL");
		check([[document fileURL] isEqual:realURL] && ![document isDocumentEdited],
		      "and clears the edited state");
		check([document autosavedContentsFileURL] == nil, "the autosaved URL is cleared");
		check(![files fileExistsAtPath:[autosaveURL path]], "and the autosave file is deleted");
		[document close];
		[reopened release];

		/* 3. THE CONTROLLER'S TIMER IS REAL. */
		{
			AGTailDocument *timed = [controller openUntitledDocumentAndDisplay:NO error:NULL];

			[timed setText:@"timer text"];
			[timed updateChangeCount:NSChangeDone];
			[controller setAutosavingDelay:0.05];
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
			[controller setAutosavingDelay:0.0];
			check([timed autosavedContentsFileURL] != nil
			      && [files fileExistsAtPath:[[timed autosavedContentsFileURL] path]],
			      "the controller's autosaving delay writes an autosave file");
			[timed setCloseDecision:NSAlertThirdButtonReturn];
			[timed close];
		}

		/* 4. CLOSE DECISIONS, SYNCHRONOUSLY THROUGH THE SEAM. */
		{
			AGTailDocument *clean = [controller openUntitledDocumentAndDisplay:NO error:NULL];

			watcher->closes = 0;
			[clean canCloseDocumentWithDelegate:watcher
					 shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:NULL];
			check(watcher->closes == 1 && watcher->lastShouldClose,
			      "an unedited document closes without a prompt");

			[clean setText:@"edited"];
			[clean updateChangeCount:NSChangeDone];
			[clean setCloseDecision:NSAlertSecondButtonReturn];	/* Cancel */
			[clean canCloseDocumentWithDelegate:watcher
					 shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:NULL];
			check(watcher->closes == 2 && !watcher->lastShouldClose, "Cancel answers NO");

			[clean setCloseDecision:NSAlertThirdButtonReturn];	/* Don't Save */
			[clean canCloseDocumentWithDelegate:watcher
					 shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:NULL];
			check(watcher->closes == 3 && watcher->lastShouldClose, "Don't Save answers YES");
			[clean close];
		}

		/* 5. SAVE-FROM-CLOSE: THE SAVE HAPPENS AND THE ANSWER IS THE SAVE'S. */
		{
			AGTailDocument *dirty = [controller openUntitledDocumentAndDisplay:NO error:NULL];
			NSURL *closeURL = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"closed.agtail"]];

			[dirty setText:@"close-save"];
			[dirty saveToURL:closeURL ofType:@"AGTailText" forSaveOperation:NSSaveOperation error:NULL];
			[dirty setText:@"close-save edited"];
			[dirty updateChangeCount:NSChangeDone];
			[dirty setCloseDecision:NSAlertFirstButtonReturn];	/* Save */
			watcher->closes = 0;
			[dirty canCloseDocumentWithDelegate:watcher
					  shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:NULL];
			check(watcher->closes == 1 && watcher->lastShouldClose,
			      "Save in the close alert saves and answers YES");
			check(![dirty isDocumentEdited] && [files fileExistsAtPath:[closeURL path]],
			      "the file on disk is the edited contents");
			[dirty close];
		}

		/* 6. CLOSE-ALL WALKS THE DOCUMENTS AND STOPS AT A REFUSAL. */
		{
			AGTailDocument *a = [controller openUntitledDocumentAndDisplay:NO error:NULL];
			AGTailDocument *b = [controller openUntitledDocumentAndDisplay:NO error:NULL];

			[a setText:@"a"];
			[a updateChangeCount:NSChangeDone];
			[b setText:@"b"];
			[b updateChangeCount:NSChangeDone];
			[a setCloseDecision:NSAlertThirdButtonReturn];	/* Don't Save */
			[b setCloseDecision:NSAlertThirdButtonReturn];
			watcher->closeAlls = 0;
			[controller closeAllDocumentsWithDelegate:watcher
				       didCloseAllSelector:@selector(controller:didCloseAll:contextInfo:)
					      contextInfo:NULL];
			check(watcher->closeAlls == 1 && watcher->lastCloseAll,
			      "close-all with Don't Save on every document closes the set");
			check([[controller documents] count] == 0, "and the controller is empty");
		}

		/* 7. THE WINDOW CONTROLLER'S HALF AND THE REVIEW DOOR. */
		{
			AGTailDocument *doc = [controller openUntitledDocumentAndDisplay:NO error:NULL];
			NSWindowController *first = [[NSWindowController alloc] init];
			NSWindowController *second = [[NSWindowController alloc] init];

			[first setDocument:doc];
			[first setShouldCloseDocument:YES];
			[doc addWindowController:first];
			watcher->closes = 0;
			[doc shouldCloseWindowController:first delegate:watcher
				 shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:NULL];
			check(watcher->closes == 1 && watcher->lastShouldClose,
			      "a controller that owns the document's closing asks the document, which answers YES when clean");

			[second setDocument:doc];
			[second setShouldCloseDocument:NO];
			[doc addWindowController:second];
			watcher->closes = 0;
			[doc shouldCloseWindowController:second delegate:watcher
				 shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:NULL];
			check(watcher->closes == 1 && watcher->lastShouldClose,
			      "a second controller that does not own the closing answers YES without a prompt");

			[doc removeWindowController:first];
			[doc removeWindowController:second];
			[first release];
			[second release];
			[doc close];
		}
		{
			AGTailDocument *edited = [controller openUntitledDocumentAndDisplay:NO error:NULL];

			[edited setText:@"review"];
			[edited updateChangeCount:NSChangeDone];
			[edited setCloseDecision:NSAlertSecondButtonReturn];	/* Cancel */
			watcher->reviews = 0;
			[controller reviewUnsavedDocumentsWithAlertTitle:@"Quit" cancellable:YES
				 delegate:watcher didReviewAllSelector:@selector(controller:didReviewAll:contextInfo:)
				 contextInfo:NULL];
			check(watcher->reviews == 1 && !watcher->lastReviewAll,
			      "reviewing one edited document hands it to the document's close question, and Cancel answers NO");
			[edited setCloseDecision:NSAlertThirdButtonReturn];
			[edited close];
		}

		/* 8. THE FILENAME STATE AND THE SCRIPTING REFUSALS. */
		{
			AGTailDocument *named = [controller openUntitledDocumentAndDisplay:NO error:NULL];

			check([[named displayName] isEqualToString:@"Untitled"], "a fresh document is Untitled");
			[named setLastComponentOfFileName:@"Report"];
			check([[named displayName] isEqualToString:@"Report"], "a stored last component is the display name");
			[named saveToURL:realURL ofType:@"AGTailText" forSaveOperation:NSSaveOperation error:NULL];
			check([[named displayName] isEqualToString:@"saved.agtail"],
			      "saving to a URL updates the displayed name");
			[named setLastComponentOfFileName:@"Renamed"];
			check([[named displayName] isEqualToString:@"Renamed"], "and a caller's override wins afterwards");
			check([named fileTypeFromLastRunSavePanel] == nil
			      && ![named fileNameExtensionWasHiddenInLastRunSavePanel],
			      "no save panel has run, so its two answers are empty");
			check([named handleCloseScriptCommand:nil] == nil
			      && [named handleSaveScriptCommand:nil] == nil
			      && [named objectSpecifier] == nil,
			      "the scripting doors refuse without a scripting suite");
			[named close];
		}

		/* 9. THE ERROR CHAIN: DOCUMENT HOOK -> CONTROLLER HOOK -> PRESENTER. */
		{
			AGTailDocument *erring = [controller openUntitledDocumentAndDisplay:NO error:NULL];
			AGErrorRecorder *recorder = [[AGErrorRecorder alloc] init];
			NSError *original = [NSError errorWithDomain:@"AGTail" code:7
							   userInfo:[NSDictionary dictionaryWithObject:@"original"
											   forKey:@"seenBy"]];

			[controller cg_setErrorPresenter:recorder];
			(void)[erring presentError:original];
			check(recorder->presentCalls == 1, "the document forwards its error to the controller's presenter");
			check([[[recorder->lastError userInfo] objectForKey:@"seenBy"] isEqual:@"document"],
			      "after the document's -willPresentError: hook");
			[controller cg_setErrorPresenter:nil];
			[recorder release];
			[erring close];
		}

		printf("document_tail: %d case(s) failed\n", failures);
		[controller release];
		[watcher release];
		[autosaveURL release];
		[files removeItemAtPath:root error:NULL];
		[root release];
	}
	return failures != 0;
}
