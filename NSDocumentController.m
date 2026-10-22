/*
 * NSDocumentController — the open documents, the type table, and the one place a document is made.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The type table is read from `CFBundleDocumentTypes` once, lazily: each entry is a dictionary with a `CFBundleTypeName`,
 * an `NSDocumentClass` and a `CFBundleTypeExtensions` array. A subclass that wants a table it owns overrides
 * `-documentClassForType:`/`-defaultType`/`-typeFromFileExtension:`, and every other door here goes through those three, so
 * one override is enough. The open documents are a plain ordered array; the recent ones are in memory for the session.
 */
#import "NSDocumentController.h"
#import "NSDocument.h"
#import "NSWindow.h"
#import "NSWindowController.h"
#import "NSOpenPanel.h"

#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <stdio.h>

static NSString *const AGDocumentControllerErrorDomain = @"com.agora.appkit.documentcontroller";
enum {
	AGControllerErrorNoClass = 1,
	AGControllerErrorNoType = 2,
	AGControllerErrorOpen = 3
};

static void fn_controller_error(NSError * _Nullable * _Nullable outError, NSInteger code, NSString *description)
{
	if (outError != NULL) {
		*outError = [NSError errorWithDomain:AGDocumentControllerErrorDomain
						code:code
					    userInfo:[NSDictionary dictionaryWithObject:description
									    forKey:NSLocalizedDescriptionKey]];
	}
}

/* One Info.plist entry's type name and extensions. The name is `CFBundleTypeName`; the extensions are the era's list. */
static NSString *fn_entry_name(NSDictionary *entry)
{
	id name = [entry objectForKey:@"CFBundleTypeName"];

	return [name isKindOfClass:[NSString class]] ? (NSString *)name : nil;
}

static NSArray *fn_entry_extensions(NSDictionary *entry)
{
	id extensions = [entry objectForKey:@"CFBundleTypeExtensions"];

	return [extensions isKindOfClass:[NSArray class]] ? (NSArray *)extensions : [NSArray array];
}

static NSString *fn_entry_document_class(NSDictionary *entry)
{
	id name = [entry objectForKey:@"NSDocumentClass"];

	return [name isKindOfClass:[NSString class]] ? (NSString *)name : nil;
}

static BOOL fn_entry_matches_type(NSDictionary *entry, NSString *typeName)
{
	NSString *name = fn_entry_name(entry);
	NSArray *extensions;
	NSUInteger i;

	if (name != nil && [name isEqualToString:typeName]) {
		return YES;
	}
	extensions = fn_entry_extensions(entry);
	for (i = 0; i < [extensions count]; i++) {
		NSString *extension = [extensions objectAtIndex:i];

		if ([extension caseInsensitiveCompare:typeName] == NSOrderedSame) {
			return YES;
		}
	}
	return NO;
}

typedef void (*AGControllerDidCloseAllIMP)(id, SEL, id, BOOL, void *);

@implementation NSDocumentController

/* The first controller made is the shared one, which is Apple's rule and the reason a subclass installed first wins. */
static NSDocumentController *s_sharedDocumentController = nil;

+ (NSDocumentController *)sharedDocumentController
{
	if (s_sharedDocumentController == nil) {
		s_sharedDocumentController = [[NSDocumentController alloc] init];
	}
	return s_sharedDocumentController;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_documents = [[NSMutableArray alloc] init];
		_recentDocumentURLs = [[NSMutableArray alloc] init];
		_currentDirectory = nil;
		_cg_documentTypes = nil;
		_shouldCreateUI = YES;
		if (s_sharedDocumentController == nil) {
			s_sharedDocumentController = self;
		}
	}
	return self;
}

- (void)dealloc
{
	[_documents release];
	[_recentDocumentURLs release];
	[_currentDirectory release];
	[_cg_documentTypes release];
	[super dealloc];
}

/* ---- THE TYPE TABLE ------------------------------------------------------------------------------- */

- (NSArray *)cg_documentTypes
{
	if (_cg_documentTypes == nil) {
		id types = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];

		_cg_documentTypes = [([types isKindOfClass:[NSArray class]] ? (NSArray *)types : [NSArray array]) copy];
	}
	return _cg_documentTypes;
}

- (NSArray *)documentClassNames
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *entries = [self cg_documentTypes];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSString *className = fn_entry_document_class([entries objectAtIndex:i]);

		if (className != nil && ![names containsObject:className]) {
			[names addObject:className];
		}
	}
	return names;
}

- (Class)documentClassForType:(NSString *)typeName
{
	NSArray *entries = [self cg_documentTypes];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSDictionary *entry = [entries objectAtIndex:i];

		if (fn_entry_matches_type(entry, typeName)) {
			NSString *className = fn_entry_document_class(entry);

			return (className != nil) ? NSClassFromString(className) : Nil;
		}
	}
	return Nil;
}

- (NSString *)displayNameForType:(NSString *)typeName
{
	NSArray *entries = [self cg_documentTypes];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSDictionary *entry = [entries objectAtIndex:i];

		if (fn_entry_matches_type(entry, typeName)) {
			NSString *name = fn_entry_name(entry);

			return (name != nil) ? name : typeName;
		}
	}
	return typeName;
}

- (NSString *)defaultType
{
	NSArray *entries = [self cg_documentTypes];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSDictionary *entry = [entries objectAtIndex:i];
		id role = [entry objectForKey:@"CFBundleTypeRole"];

		if ([role isKindOfClass:[NSString class]] && [role isEqualToString:@"Editor"]) {
			return fn_entry_name(entry);
		}
	}
	/* NO EDITOR ROLE: the first type is still the honest default, and a bundle with no document types answers nil. */
	return ([entries count] > 0) ? fn_entry_name([entries objectAtIndex:0]) : nil;
}

- (NSString *)typeFromFileExtension:(NSString *)fileNameExtension
{
	NSArray *entries = [self cg_documentTypes];
	NSUInteger i;

	if (fileNameExtension == nil) {
		return nil;
	}
	for (i = 0; i < [entries count]; i++) {
		NSDictionary *entry = [entries objectAtIndex:i];
		NSArray *extensions = fn_entry_extensions(entry);
		NSUInteger j;

		for (j = 0; j < [extensions count]; j++) {
			if ([[extensions objectAtIndex:j] caseInsensitiveCompare:fileNameExtension] == NSOrderedSame) {
				return fn_entry_name(entry);
			}
		}
	}
	return nil;
}

- (NSArray *)fileExtensionsFromType:(NSString *)typeName
{
	NSArray *entries = [self cg_documentTypes];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSDictionary *entry = [entries objectAtIndex:i];

		if (fn_entry_matches_type(entry, typeName)) {
			return fn_entry_extensions(entry);
		}
	}
	return [NSArray array];
}

- (NSString *)typeForContentsOfURL:(NSURL *)inAbsoluteURL error:(NSError **)outError
{
	NSString *extension = [[inAbsoluteURL path] pathExtension];
	NSString *type = (extension != nil) ? [self typeFromFileExtension:extension] : nil;

	if (type == nil) {
		fn_controller_error(outError, AGControllerErrorNoType,
				    [NSString stringWithFormat:@"No document type is registered for \"%@\".",
					     (extension != nil) ? extension : [inAbsoluteURL path]]);
	}
	return type;
}

/* ---- THE OPEN DOCUMENTS --------------------------------------------------------------------------- */

- (NSArray *)documents
{
	return [NSArray arrayWithArray:_documents];
}

- (id)currentDocument
{
	NSUInteger i;

	for (i = 0; i < [_documents count]; i++) {
		NSDocument *document = [_documents objectAtIndex:i];
		NSArray *controllers = [document windowControllers];
		NSUInteger j;

		for (j = 0; j < [controllers count]; j++) {
			NSWindow *window = [[controllers objectAtIndex:j] window];

			if (window != nil && [window isKeyWindow]) {
				return document;
			}
		}
	}
	for (i = 0; i < [_documents count]; i++) {
		NSDocument *document = [_documents objectAtIndex:i];
		NSArray *controllers = [document windowControllers];
		NSUInteger j;

		for (j = 0; j < [controllers count]; j++) {
			NSWindow *window = [[controllers objectAtIndex:j] window];

			if (window != nil && [window isMainWindow]) {
				return document;
			}
		}
	}
	return nil;
}

- (NSString *)currentDirectory
{
	NSDocument *current = (NSDocument *)[self currentDocument];
	NSURL *url = (current != nil) ? [current fileURL] : nil;

	if (url != nil) {
		NSString *path = [url path];

		return (path != nil) ? [path stringByDeletingLastPathComponent] : nil;
	}
	return _currentDirectory;
}

- (id)documentForURL:(NSURL *)absoluteURL
{
	NSUInteger i;

	if (absoluteURL == nil) {
		return nil;
	}
	for (i = 0; i < [_documents count]; i++) {
		NSDocument *document = [_documents objectAtIndex:i];

		if ([[document fileURL] isEqual:absoluteURL]) {
			return document;
		}
	}
	return nil;
}

- (id)documentForWindow:(NSWindow *)window
{
	NSUInteger i;

	if (window == nil) {
		return nil;
	}
	for (i = 0; i < [_documents count]; i++) {
		NSDocument *document = [_documents objectAtIndex:i];
		NSArray *controllers = [document windowControllers];
		NSUInteger j;

		for (j = 0; j < [controllers count]; j++) {
			if ([[controllers objectAtIndex:j] window] == window) {
				return document;
			}
		}
	}
	return nil;
}

- (void)addDocument:(NSDocument *)document
{
	if (document == nil || [_documents containsObject:document]) {
		return;
	}
	[_documents addObject:document];
	[document cg_setDocumentController:self];
}

- (void)removeDocument:(NSDocument *)document
{
	if (document == nil) {
		return;
	}
	if ([document cg_documentController] == self) {
		[document cg_setDocumentController:nil];
	}
	[_documents removeObject:document];
}

/* ---- MAKING AND OPENING --------------------------------------------------------------------------- */

- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError
{
	Class documentClass = [self documentClassForType:typeName];
	id document;

	if (documentClass == Nil) {
		fn_controller_error(outError, AGControllerErrorNoClass,
				    [NSString stringWithFormat:@"No document class is registered for type \"%@\".",
					     (typeName != nil) ? typeName : @"(nil)"]);
		return nil;
	}
	document = [[documentClass alloc] initWithType:typeName error:outError];
	return [document autorelease];
}

- (id)makeDocumentWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	Class documentClass = [self documentClassForType:typeName];
	id document;

	if (documentClass == Nil) {
		fn_controller_error(outError, AGControllerErrorNoClass,
				    [NSString stringWithFormat:@"No document class is registered for type \"%@\".",
					     (typeName != nil) ? typeName : @"(nil)"]);
		return nil;
	}
	document = [[documentClass alloc] initWithContentsOfURL:absoluteURL ofType:typeName error:outError];
	return [document autorelease];
}

- (id)makeDocumentForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL
		  ofType:(NSString *)typeName error:(NSError **)outError
{
	Class documentClass = [self documentClassForType:typeName];
	id document;

	if (documentClass == Nil) {
		fn_controller_error(outError, AGControllerErrorNoClass,
				    [NSString stringWithFormat:@"No document class is registered for type \"%@\".",
					     (typeName != nil) ? typeName : @"(nil)"]);
		return nil;
	}
	document = [[documentClass alloc] initForURL:absoluteDocumentURL
			       withContentsOfURL:absoluteDocumentContentsURL
					  ofType:typeName
					   error:outError];
	return [document autorelease];
}

- (id)openUntitledDocumentAndDisplay:(BOOL)displayDocument error:(NSError **)outError
{
	NSString *typeName = [self defaultType];
	id document;

	if (typeName == nil) {
		fn_controller_error(outError, AGControllerErrorNoType,
				    @"This application declares no document type to make a new document of.");
		return nil;
	}
	document = [self makeUntitledDocumentOfType:typeName error:outError];
	if (document == nil) {
		return nil;
	}
	[self addDocument:document];
	if (displayDocument) {
		[document makeWindowControllers];
		[document showWindows];
	}
	return document;
}

- (id)openDocumentWithContentsOfURL:(NSURL *)absoluteURL display:(BOOL)displayDocument error:(NSError **)outError
{
	id existing = [self documentForURL:absoluteURL];
	NSString *typeName;
	id document;

	if (existing != nil) {
		if (displayDocument) {
			[existing showWindows];
		}
		return existing;
	}
	typeName = [self typeForContentsOfURL:absoluteURL error:outError];
	if (typeName == nil) {
		return nil;
	}
	document = [self makeDocumentWithContentsOfURL:absoluteURL ofType:typeName error:outError];
	if (document == nil) {
		return nil;
	}
	[self addDocument:document];
	if (displayDocument) {
		[document makeWindowControllers];
		[document showWindows];
	}
	[self noteNewRecentDocumentURL:absoluteURL];
	return document;
}

- (BOOL)reopenDocumentForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL
		       error:(NSError **)outError
{
	NSString *typeName = [self typeForContentsOfURL:absoluteDocumentContentsURL error:outError];
	id document;

	if (typeName == nil) {
		return NO;
	}
	document = [self makeDocumentForURL:absoluteDocumentURL
			  withContentsOfURL:absoluteDocumentContentsURL
				     ofType:typeName
				      error:outError];
	if (document == nil) {
		return NO;
	}
	[self addDocument:document];
	[document makeWindowControllers];
	[document showWindows];
	if (absoluteDocumentURL != nil) {
		[self noteNewRecentDocumentURL:absoluteDocumentURL];
	}
	return YES;
}

- (void)newDocument:(id)sender
{
	(void)sender;
	(void)[self openUntitledDocumentAndDisplay:YES error:NULL];
}

/* **THE FILE MENU'S OPEN ITEM, NOW THAT THE PANEL EXISTS.** The URLs the panel answers are opened in turn; the first
 * failure stops the walk and is printed, because there is no error panel in this controller yet. */
- (void)openDocument:(id)sender
{
	NSArray *urls = [self URLsFromRunningOpenPanel];
	NSUInteger i;

	(void)sender;
	for (i = 0; i < [urls count]; i++) {
		NSError *error = nil;

		if ([self openDocumentWithContentsOfURL:[urls objectAtIndex:i] display:YES error:&error] == nil) {
			fprintf(stderr, "document controller: could not open %s: %s\n",
				[[[urls objectAtIndex:i] path] UTF8String],
				(error != nil) ? [[error localizedDescription] UTF8String] : "no reason given");
			break;
		}
	}
}

/* **THE PANEL IS FILTERED BY THE TYPES THE BUNDLE DECLARES.** Every CFBundleDocumentTypes entry contributes its
 * extensions; a bundle that declares none gets no filter rather than a filter that matches nothing. */
- (NSArray *)URLsFromRunningOpenPanel
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	NSMutableArray *extensions = [NSMutableArray array];
	NSArray *entries = [self cg_documentTypes];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSArray *types = fn_entry_extensions([entries objectAtIndex:i]);

		[extensions addObjectsFromArray:types];
	}
	if ([self runModalOpenPanel:panel forTypes:([extensions count] > 0) ? extensions : nil] == NSOKButton) {
		return [panel URLs];
	}
	return [NSArray array];
}

- (NSInteger)runModalOpenPanel:(NSOpenPanel *)openPanel forTypes:(NSArray *)types
{
	if (types != nil) {
		[openPanel setAllowedFileTypes:types];
	}
	return [openPanel runModal];
}

/* THE 10.3 SPELLINGS. */
- (id)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)type
{
	return [self makeDocumentWithContentsOfURL:url ofType:type error:NULL];
}

- (id)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)display
{
	return [self openDocumentWithContentsOfURL:url display:display error:NULL];
}

- (id)makeDocumentWithContentsOfFile:(NSString *)fileName ofType:(NSString *)type
{
	return [self makeDocumentWithContentsOfURL:[NSURL fileURLWithPath:fileName] ofType:type error:NULL];
}

- (id)openDocumentWithContentsOfFile:(NSString *)fileName display:(BOOL)display
{
	return [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath:fileName] display:display error:NULL];
}

- (id)openUntitledDocumentOfType:(NSString *)type display:(BOOL)display
{
	id document = [self makeUntitledDocumentOfType:type error:NULL];

	if (document != nil) {
		[self addDocument:document];
		if (display) {
			[document makeWindowControllers];
			[document showWindows];
		}
	}
	return document;
}

- (id)documentForFileName:(NSString *)fileName
{
	return [self documentForURL:[NSURL fileURLWithPath:fileName]];
}

- (void)setShouldCreateUI:(BOOL)flag
{
	_shouldCreateUI = flag;
}

- (BOOL)shouldCreateUI
{
	return _shouldCreateUI;
}

/* ---- SAVING AND CLOSING THE SET ------------------------------------------------------------------- */

- (BOOL)hasEditedDocuments
{
	NSUInteger i;

	for (i = 0; i < [_documents count]; i++) {
		if ([[_documents objectAtIndex:i] isDocumentEdited]) {
			return YES;
		}
	}
	return NO;
}

- (void)saveAllDocuments:(id)sender
{
	NSArray *documents = [[NSArray alloc] initWithArray:_documents];
	NSUInteger i;

	for (i = 0; i < [documents count]; i++) {
		NSDocument *document = [documents objectAtIndex:i];

		if ([document isDocumentEdited]) {
			[document saveDocument:sender];
		}
	}
	[documents release];
}

- (void)closeAllDocumentsWithDelegate:(id)delegate didCloseAllSelector:(SEL)didCloseAllSelector
			  contextInfo:(void *)contextInfo
{
	BOOL allClosed = ![self hasEditedDocuments];

	/* **NO ALERT YET, SO AN EDITED SET IS LEFT ALONE.** Discarding edits silently would be the one failure mode of a close
	 * all that a user cannot undo; the delegate is told NO and nothing moves. */
	if (allClosed) {
		NSArray *documents = [[NSArray alloc] initWithArray:_documents];
		NSUInteger i;

		for (i = 0; i < [documents count]; i++) {
			[[documents objectAtIndex:i] close];
		}
		[documents release];
	}
	if (delegate != nil && didCloseAllSelector != NULL
	    && [delegate respondsToSelector:didCloseAllSelector]) {
		AGControllerDidCloseAllIMP imp = (AGControllerDidCloseAllIMP)[delegate methodForSelector:didCloseAllSelector];

		imp(delegate, didCloseAllSelector, self, allClosed, contextInfo);
	}
}

/* ---- RECENT DOCUMENTS ----------------------------------------------------------------------------- */

- (NSUInteger)maximumRecentDocumentCount
{
	return 10;
}

- (void)noteNewRecentDocumentURL:(NSURL *)absoluteURL
{
	NSUInteger i;

	if (absoluteURL == nil) {
		return;
	}
	for (i = 0; i < [_recentDocumentURLs count]; i++) {
		if ([[_recentDocumentURLs objectAtIndex:i] isEqual:absoluteURL]) {
			[_recentDocumentURLs removeObjectAtIndex:i];
			break;
		}
	}
	[_recentDocumentURLs insertObject:absoluteURL atIndex:0];
	while ([_recentDocumentURLs count] > [self maximumRecentDocumentCount]) {
		[_recentDocumentURLs removeObjectAtIndex:[_recentDocumentURLs count] - 1];
	}
}

- (void)noteNewRecentDocument:(NSDocument *)document
{
	NSURL *url = (document != nil) ? [document fileURL] : nil;

	if (url != nil) {
		[self noteNewRecentDocumentURL:url];
	}
}

- (NSArray *)recentDocumentURLs
{
	return [NSArray arrayWithArray:_recentDocumentURLs];
}

- (void)clearRecentDocuments:(id)sender
{
	(void)sender;
	[_recentDocumentURLs removeAllObjects];
}

/* ---- VALIDATION ----------------------------------------------------------------------------------- */

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	SEL action = [anItem action];

	return action == @selector(newDocument:)
		|| action == @selector(openDocument:)
		|| action == @selector(saveAllDocuments:)
		|| action == @selector(clearRecentDocuments:);
}

@end
