/*
 * save_panel — NSSavePanel and NSOpenPanel: the listing, the filters, the accept, and the three ways to run it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIM IS THAT A PANEL RETURNS THE URL THE LISTING AND THE NAME FIELD SAY.** The probe builds a temp directory with
 * files, a directory and a hidden file, points a save panel at it, and accepts names: a plain one, one that gains the
 * allowed type's extension, one forced by `-requiredFileType`, and one that already exists (accepted, because this tier has
 * no replacement alert and says so). It navigates INTO a selected directory and back out through "..", and it reads the
 * listing through the instrument door so a filtered entry is distinguishable from one that was never there.
 *
 * **THE FILTERS ARE THE DELEGATE'S.** `-panel:shouldShowFilename:`, `-panel:shouldEnableURL:` and the open panel's
 * `-allowedFileTypes` each remove entries; the probe hides a `.skip` file and `secret.txt`, and shows that a `.rtf` file is
 * absent from a text-only open panel but present in a save panel. `-panel:validateURL:error:` is asked to refuse a name, and
 * the panel stays open; `-panel:userEnteredFilename:confirmed:` renames one; the deprecated comparator is counted and its
 * order is checked; selection and directory changes are announced.
 *
 * **AND THE OPEN PANEL IS THE SAME BROWSER WITH ITS FLAGS.** One file, many files, a directory, or files-disabled are the
 * four answers the flags produce from the same accept path. The sheet form attaches to a parent and calls its block with
 * the code; the modeless form calls its block when it is dismissed; the deprecated `-beginSheetForDirectory:…` reaches the
 * same code through a caller's selector.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSOpenPanel.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSWindow.h>
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
 * THE DELEGATE: filters, a veto, a rename, both directory announcements and a reversed comparator.
 * ================================================================================================ */

@interface AGPanelWatcher : NSObject <NSOpenSavePanelDelegate>
{
@public
	int showCalls;
	int enableCalls;
	int validateCalls;
	int userCalls;
	int selectionCalls;
	int directoryCalls;
	int compareCalls;
	int deprecatedEndCalls;
	int deprecatedEndCode;
	BOOL refuseValidation;
	NSString *renamed;
}
- (void)panel:(NSSavePanel *)panel didEnd:(NSInteger)code contextInfo:(void *)contextInfo;
@end

@implementation AGPanelWatcher

- (BOOL)panel:(id)sender shouldShowFilename:(NSString *)filename
{
	(void)sender;
	showCalls++;
	return ![[filename lastPathComponent] hasSuffix:@".skip"];
}

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url
{
	(void)sender;
	enableCalls++;
	return ![[[url path] lastPathComponent] isEqualToString:@"secret.txt"];
}

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError
{
	(void)sender;
	(void)url;
	validateCalls++;
	if (refuseValidation) {
		if (outError != NULL) {
			*outError = [NSError errorWithDomain:@"AGPanelTest"
							code:1
						    userInfo:[NSDictionary dictionaryWithObject:@"Not that name."
										    forKey:NSLocalizedDescriptionKey]];
		}
		return NO;
	}
	return YES;
}

- (NSString *)panel:(id)sender userEnteredFilename:(NSString *)filename confirmed:(BOOL)okFlag
{
	(void)sender;
	(void)okFlag;
	userCalls++;
	return renamed;
}

- (void)panelSelectionDidChange:(id)sender
{
	(void)sender;
	selectionCalls++;
}

- (void)panel:(id)sender didChangeToDirectoryURL:(NSURL *)url
{
	(void)sender;
	(void)url;
	directoryCalls++;
}

- (void)panel:(id)sender directoryDidChange:(NSString *)path
{
	(void)sender;
	(void)path;
	directoryCalls++;
}

/* THE DEPRECATED COMPARATOR, reversing the order so the probe can see that the panel asked it. */
- (NSComparisonResult)panel:(id)sender compareFilename:(NSString *)name1 with:(NSString *)name2
	       caseSensitive:(BOOL)caseSensitive
{
	(void)sender;
	(void)caseSensitive;
	compareCalls++;
	return [name2 caseInsensitiveCompare:name1];
}

- (void)panel:(NSSavePanel *)panel didEnd:(NSInteger)code contextInfo:(void *)contextInfo
{
	(void)panel;
	(void)contextInfo;
	deprecatedEndCalls++;
	deprecatedEndCode = (int)code;
}

@end

/* ================================================================================================== */

static NSData *empty_data(void)
{
	return [NSData data];
}

static void make_file(NSString *directory, NSString *name)
{
	(void)[empty_data() writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES];
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSFileManager *files = [NSFileManager defaultManager];
		NSString *directory = [NSString stringWithFormat:@"/tmp/agora-panel-test-%d", (int)getpid()];
		NSString *subdirectory = [directory stringByAppendingPathComponent:@"sub"];
		AGPanelWatcher *watcher = [[AGPanelWatcher alloc] init];
		NSURL *directoryURL;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];
		[files removeItemAtPath:directory error:NULL];
		(void)[files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
		(void)[files createDirectoryAtPath:subdirectory withIntermediateDirectories:NO attributes:nil error:NULL];
		make_file(directory, @"a.txt");
		make_file(directory, @"b.rtf");
		make_file(directory, @"exists.txt");
		make_file(directory, @"secret.txt");
		make_file(directory, @"c.skip");
		make_file(directory, @".hidden");
		make_file(subdirectory, @"c.txt");
		directoryURL = [NSURL fileURLWithPath:directory];

		/* ============================================================================================
		 * 1. THE SAVE PANEL'S DEFAULTS AND ITS LISTING.
		 * ========================================================================================== */
		{
			NSSavePanel *panel = [NSSavePanel savePanel];
			NSArray *visible;

			check([panel isKindOfClass:[NSSavePanel class]], "+savePanel makes a save panel");
			check([panel directoryURL] != nil, "it has a directory to look at");
			check([[panel title] isEqualToString:@"Save"] && [[panel prompt] isEqualToString:@"Save"],
			      "its title and prompt are Save");
			check([[panel nameFieldLabel] isEqualToString:@"Save As:"], "and its name label is Save As:");
			check([[panel nameFieldStringValue] isEqualToString:@"Untitled"], "the name starts Untitled");
			check([panel canCreateDirectories] && ![panel canSelectHiddenExtension]
				      && ![panel allowsOtherFileTypes] && ![panel showsHiddenFiles],
			      "with Apple's flag defaults");
			check([panel URL] == nil, "and no result before an accept");

			[panel setDirectoryURL:directoryURL];
			check([[[panel directoryURL] path] isEqualToString:directory], "the directory door lands where asked");
			check([[[panel directory] stringByStandardizingPath] isEqualToString:[directory stringByStandardizingPath]],
			      "and the deprecated directory spelling agrees");
			visible = [panel cg_visibleFilenames];
			printf("  (note: %lu entries visible, first \"%s\")\n", (unsigned long)[visible count],
			       [[visible componentsJoinedByString:@", "] UTF8String]);
			check([visible containsObject:@"a.txt"] && [visible containsObject:@"sub/"]
				      && [visible containsObject:@"b.rtf"],
			      "the listing shows files and directories");
			check(![visible containsObject:@".hidden"], "a hidden file is not shown by default");
			[panel setShowsHiddenFiles:YES];
			check([[panel cg_visibleFilenames] containsObject:@".hidden"], "and is shown when asked for");
			[panel setShowsHiddenFiles:NO];
			[panel setCanSelectHiddenExtension:YES];
			check([panel canSelectHiddenExtension], "the hidden-extension flag round-trips");
			[panel setExtensionHidden:YES];
			check([panel isExtensionHidden], "and so does the extension-hidden state");
			[panel setMessage:@"Choose a name"];
			[panel setNameFieldLabel:@"Save As"];
			[panel setPrompt:@"Save It"];
			check([[panel message] isEqualToString:@"Choose a name"]
				      && [[panel nameFieldLabel] isEqualToString:@"Save As"]
				      && [[panel prompt] isEqualToString:@"Save It"],
			      "and the message, label and prompt are stored");
			[panel setTitle:@"A Save Panel"];
			check([[panel title] isEqualToString:@"A Save Panel"], "as is the title");
			[panel validateVisibleColumns];
			check(1, "validateVisibleColumns re-reads the directory without crashing");
		}

		/* ============================================================================================
		 * 2. THE SAVE ACCEPT: THE EXTENSION, THE RENAME, THE VETO AND THE EXISTING FILE.
		 * ========================================================================================== */
		{
			NSSavePanel *panel = [NSSavePanel savePanel];

			[panel setDirectoryURL:directoryURL];
			[panel setNameFieldStringValue:@"report"];
			[panel setAllowedFileTypes:[NSArray arrayWithObject:@"txt"]];
			[panel setDelegate:watcher];
			watcher->validateCalls = 0;
			[panel ok:nil];
			printf("  (note: a plain name with allowed txt -> \"%s\")\n", [[[panel URL] path] UTF8String]);
			check([panel URL] != nil && [[[[panel URL] path] lastPathComponent] isEqualToString:@"report.txt"],
			      "the allowed type's extension is added to a name without one");
			check(watcher->validateCalls == 1, "and the delegate validated the URL once");
			check([[panel nameFieldStringValue] length] > 0, "the name field shows the final name");

			/* REQUIRED FILETYPE, the deprecated forced extension. */
			{
				NSSavePanel *forced = [NSSavePanel savePanel];

				[forced setDirectoryURL:directoryURL];
				[forced setNameFieldStringValue:@"notes"];
				[forced setRequiredFileType:@"md"];
				[forced ok:nil];
				check([[[[forced URL] path] lastPathComponent] isEqualToString:@"notes.md"],
				      "requiredFileType forces its extension");
				[forced setRequiredFileType:@"text"];
				[forced ok:nil];
				check([[[[forced URL] path] lastPathComponent] isEqualToString:@"notes.text"],
				      "and replaces a different one");
			}

			/* THE DELEGATE'S RENAME. */
			{
				NSSavePanel *renamed = [NSSavePanel savePanel];

				watcher->renamed = @"from-delegate.txt";
				[renamed setDirectoryURL:directoryURL];
				[renamed setNameFieldStringValue:@"typed.txt"];
				[renamed setDelegate:watcher];
				[renamed ok:nil];
				check([[[[renamed URL] path] lastPathComponent] isEqualToString:@"from-delegate.txt"],
				      "the delegate's userEnteredFilename: replaces the name");
				watcher->renamed = nil;
			}

			/* THE VETO. */
			{
				NSSavePanel *vetoed = [NSSavePanel savePanel];

				[vetoed setDirectoryURL:directoryURL];
				[vetoed setNameFieldStringValue:@"bad.txt"];
				[vetoed setDelegate:watcher];
				watcher->refuseValidation = YES;
				[vetoed ok:nil];
				check([vetoed URL] == nil, "a refused URL leaves the panel unanswered");
				watcher->refuseValidation = NO;
				[vetoed ok:nil];
				check([vetoed URL] != nil, "and the next accept works");
			}

			/* AN EXISTING FILE IS ACCEPTED: there is no replacement alert in this tier. */
			{
				NSSavePanel *existing = [NSSavePanel savePanel];

				[existing setDirectoryURL:directoryURL];
				[existing setNameFieldStringValue:@"exists.txt"];
				[existing ok:nil];
				check([existing URL] != nil
					      && [[[[existing URL] path] lastPathComponent] isEqualToString:@"exists.txt"],
				      "an existing file's URL is accepted (no replacement alert)");
			}

			/* CANCEL CLEARS THE RESULT. */
			check([panel URL] != nil, "the first panel has a result");
			[panel cancel:nil];
			check([panel URL] == nil, "and cancel clears it");
		}

		/* ============================================================================================
		 * 3. SELECTING AND NAVIGATING.
		 * ========================================================================================== */
		{
			NSSavePanel *panel = [NSSavePanel savePanel];

			[panel setDirectoryURL:directoryURL];
			watcher->selectionCalls = 0;
			watcher->directoryCalls = 0;
			[panel setDelegate:watcher];
			check([panel cg_selectFilename:@"a.txt"], "a row can be selected as a click would");
			check([[panel nameFieldStringValue] isEqualToString:@"a.txt"],
			      "and the name field follows the file");
			check(watcher->selectionCalls > 0, "the delegate heard the selection change");
			check([panel cg_selectFilename:@"sub"], "the directory can be selected");
			[panel ok:nil];
			check([[[[panel directoryURL] path] lastPathComponent] isEqualToString:@"sub"],
			      "Open on a directory in a save panel walks into it");
			check([[panel cg_visibleFilenames] containsObject:@"c.txt"], "and the listing is the new directory");
			check(watcher->directoryCalls >= 2, "the delegate heard the URL and the path");
			check([panel cg_selectFilename:@".."], "the parent is the .. row");
			[panel ok:nil];
			check([[[[panel directoryURL] path] lastPathComponent] isEqualToString:[directory lastPathComponent]],
			      "and it walks back out");
		}

		/* ============================================================================================
		 * 4. THE OPEN PANEL: ONE FILE, MANY FILES, DIRECTORIES, AND THE TYPE FILTER.
		 * ========================================================================================== */
		{
			NSOpenPanel *panel = [NSOpenPanel openPanel];
			NSArray *visible;

			check([panel isKindOfClass:[NSOpenPanel class]] && [panel isKindOfClass:[NSSavePanel class]],
			      "+openPanel makes an open panel, which is a save panel");
			check([[panel title] isEqualToString:@"Open"] && [[panel prompt] isEqualToString:@"Open"]
				      && [[panel nameFieldLabel] isEqualToString:@"Name:"],
			      "its title, prompt and name label are the open panel's");
			check([panel canChooseFiles] && ![panel canChooseDirectories] && ![panel allowsMultipleSelection]
				      && [panel resolvesAliases],
			      "and its flags start where Apple puts them");
			check([[panel URLs] count] == 0, "no URLs before an accept");

			[panel setDirectoryURL:directoryURL];
			[panel setAllowedFileTypes:[NSArray arrayWithObject:@"txt"]];
			[panel setDelegate:watcher];
			visible = [panel cg_visibleFilenames];
			printf("  (note: text-only open panel sees %s)\n",
			       [[visible componentsJoinedByString:@", "] UTF8String]);
			check([visible containsObject:@"a.txt"] && [visible containsObject:@"sub/"],
			      "a matching file and a directory are listed");
			check(![visible containsObject:@"b.rtf"], "a non-matching file is not");
			check(![visible containsObject:@"secret.txt"],
			      "the delegate's shouldEnableURL: removed its file");
			check(![visible containsObject:@"c.skip"], "and shouldShowFilename: removed its");

			check([panel cg_selectFilename:@"a.txt"], "a file can be selected");
			[panel ok:nil];
			check([[panel URLs] count] == 1 && [[[panel URLs] objectAtIndex:0] isEqual:[NSURL fileURLWithPath:
				[directory stringByAppendingPathComponent:@"a.txt"]]],
			      "and Open answers that file's URL");
			check([[[panel filenames] objectAtIndex:0] isEqualToString:
				[directory stringByAppendingPathComponent:@"a.txt"]],
			      "with the deprecated path spelling agreeing");

			/* MULTIPLE SELECTION. */
			{
				NSOpenPanel *many = [NSOpenPanel openPanel];

				[many setDirectoryURL:directoryURL];
				[many setAllowedFileTypes:[NSArray arrayWithObject:@"txt"]];
				[many setAllowsMultipleSelection:YES];
				check([many cg_selectFilenames:[NSArray arrayWithObjects:@"a.txt", @"exists.txt", nil]],
				      "two files can be selected together");
				[many ok:nil];
				check([[many URLs] count] == 2, "and Open answers both URLs");
			}

			/* DIRECTORIES ONLY. */
			{
				NSOpenPanel *dirs = [NSOpenPanel openPanel];

				[dirs setDirectoryURL:directoryURL];
				[dirs setCanChooseFiles:NO];
				[dirs setCanChooseDirectories:YES];
				(void)[dirs cg_selectFilename:@"a.txt"];
				[dirs ok:nil];
				check([[dirs URLs] count] == 0, "a file is refused when files cannot be chosen");
				(void)[dirs cg_selectFilename:@"sub/"];
				[dirs ok:nil];
				check([[dirs URLs] count] == 1
					      && [[[[dirs URLs] objectAtIndex:0] path] hasSuffix:@"/sub"],
				      "and a directory is chosen when directories can be");
			}

			/* A DIRECTORY IS NAVIGATED WHEN IT CANNOT BE CHOSEN. */
			{
				NSOpenPanel *nav = [NSOpenPanel openPanel];

				[nav setDirectoryURL:directoryURL];
				(void)[nav cg_selectFilename:@"sub/"];
				[nav ok:nil];
				check([[[[nav directoryURL] path] lastPathComponent] isEqualToString:@"sub"]
					      && [[nav URLs] count] == 0,
				      "a directory in a files-only open panel is walked into, not chosen");
			}

			/* CANCEL. */
			[panel cancel:nil];
			check([[panel URLs] count] == 0, "cancel empties the open panel's result");
		}

		/* ============================================================================================
		 * 5. THE COMPARATOR SORTS, AND THE LISTING ORDER SHOWS IT.
		 * ========================================================================================== */
		{
			NSSavePanel *panel = [NSSavePanel savePanel];
			NSArray *visible;
			NSUInteger atA = NSNotFound;
			NSUInteger atE = NSNotFound;
			NSUInteger i;

			[panel setDirectoryURL:directoryURL];
			[panel setDelegate:watcher];
			[panel setShowsHiddenFiles:YES];
			[panel validateVisibleColumns];
			visible = [panel cg_visibleFilenames];
			for (i = 0; i < [visible count]; i++) {
				if ([[visible objectAtIndex:i] isEqualToString:@"a.txt"]) atA = i;
				if ([[visible objectAtIndex:i] isEqualToString:@"exists.txt"]) atE = i;
			}
			printf("  (note: reversed comparator put a.txt at %ld and exists.txt at %ld; compare called %d times)\n",
			       (long)atA, (long)atE, watcher->compareCalls);
			check(watcher->compareCalls > 0, "the deprecated comparator is asked when it answers");
			check(atE != NSNotFound && atA != NSNotFound && atE < atA,
			      "and its reversed order is the listing's order");
		}

		/* ============================================================================================
		 * 6. THE SHEET, THE MODELESS FORM AND THE DEPRECATED BEGIN.
		 * ========================================================================================== */
		{
			NSWindow *parent = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
								       styleMask:NSTitledWindowMask
									 backing:NSBackingStoreBuffered
									   defer:NO] autorelease];
			__block NSInteger answer = -1;
			__block int answered = 0;
			NSSavePanel *sheet = [NSSavePanel savePanel];

			[sheet setDirectoryURL:directoryURL];
			[sheet setNameFieldStringValue:@"sheet.txt"];
			[sheet beginSheetModalForWindow:parent completionHandler:^(NSInteger result) {
				answer = result;
				answered++;
			}];
			check([parent attachedSheet] == sheet, "the panel is attached as the parent's sheet");
			[sheet cancel:nil];
			check(answered == 1 && answer == NSCancelButton, "cancel ends the sheet with NSCancelButton");
			check([parent attachedSheet] == nil, "and the parent has no sheet afterwards");

			/* The same sheet, accepted. */
			{
				NSSavePanel *saved = [NSSavePanel savePanel];
				__block NSInteger savedAnswer = -1;

				[saved setDirectoryURL:directoryURL];
				[saved setNameFieldStringValue:@"sheet.txt"];
				[saved beginSheetModalForWindow:parent completionHandler:^(NSInteger result) {
					savedAnswer = result;
				}];
				[saved ok:nil];
				check(savedAnswer == NSOKButton && [saved URL] != nil,
				      "an accepted sheet answers NSOKButton and a URL");
			}

			/* THE MODELESS FORM. */
			{
				NSSavePanel *modeless = [NSSavePanel savePanel];
				__block NSInteger modelessAnswer = -1;

				[modeless beginWithCompletionHandler:^(NSInteger result) {
					modelessAnswer = result;
				}];
				[modeless cancel:nil];
				check(modelessAnswer == NSCancelButton, "the modeless form calls its block on a dismissal");
			}

			/* THE DEPRECATED BEGIN, through a caller's selector. */
			{
				NSSavePanel *legacy = [NSSavePanel savePanel];

				[legacy beginSheetForDirectory:directory file:@"legacy.txt" modalForWindow:parent
					 modalDelegate:watcher
					didEndSelector:@selector(panel:didEnd:contextInfo:) contextInfo:NULL];
				check([parent attachedSheet] == legacy, "the deprecated begin also attaches a sheet");
				[legacy ok:nil];
				check(watcher->deprecatedEndCalls == 1 && watcher->deprecatedEndCode == NSOKButton,
				      "and the caller's did-end selector gets NSOKButton");
			}
		}

		/* ============================================================================================
		 * 7. THE PIECES.
		 * ========================================================================================== */
		{
			NSSavePanel *panel = [NSSavePanel savePanel];
			NSView *accessory = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 40.0)] autorelease];

			[panel setAccessoryView:accessory];
			check([panel accessoryView] == accessory, "the accessory view round-trips");
			[panel setAccessoryView:nil];
			check([panel accessoryView] == nil, "and can be removed");
			[panel selectText:nil];
			check(1, "selectText: opens the name field without crashing");
			[panel setCanCreateDirectories:NO];
			check(![panel canCreateDirectories], "the new-folder flag round-trips");
		}

		[files removeItemAtPath:directory error:NULL];
		[watcher release];

		if (failures == 0) {
			printf("save_panel: all checks passed\n");
			return 0;
		}
		printf("save_panel: FAILURES\n");
		return 1;
	}
}
