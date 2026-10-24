/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <AppKit/NSPersistentDocument.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>

@implementation NSPersistentDocument

- (void)dealloc
{
	[_managedObjectModel release];
	[_managedObjectContext release];
	[_coordinator release];
	[super dealloc];
}

/* A COMPILED MODEL FROM THE BUNDLE, OR AN EMPTY ONE. `+mergedModelFromBundles:` REFUSES when it finds nothing (it
 * would rather raise than answer an empty model), and a document must not raise from a getter — so the refusal is
 * caught here and the empty model is what an unconfigured document gets. The store door then reports the real failure
 * with a reason, which is where a caller can act on it. */
- (NSManagedObjectModel *)managedObjectModel
{
	if (_managedObjectModel == nil) {
		@try {
			_managedObjectModel = [[NSManagedObjectModel mergedModelFromBundles:nil] retain];
		} @catch (NSException *refusal) {
			_managedObjectModel = [[NSManagedObjectModel alloc] init];
		}
	}
	return _managedObjectModel;
}

- (NSManagedObjectContext *)managedObjectContext
{
	if (_managedObjectContext == nil) {
		_managedObjectContext = [[NSManagedObjectContext alloc] init];
	}
	return _managedObjectContext;
}

- (void)setManagedObjectContext:(NSManagedObjectContext *)context
{
	id previous = _managedObjectContext;

	_managedObjectContext = [context retain];
	[previous release];
	if (_coordinator != nil) {
		[_managedObjectContext setPersistentStoreCoordinator:_coordinator];
	}
}

- (NSString *)persistentStoreTypeForFileType:(NSString *)fileType
{
	(void)fileType;
	/* 10.6'S DEFAULT, AND IT IS THE XML STORE (§7.2). */
	return NSXMLStoreType;
}

- (BOOL)configurePersistentStoreCoordinatorForURL:(NSURL *)url
                                           ofType:(NSString *)fileType
                                            error:(NSError **)outError
{
	return [self configurePersistentStoreCoordinatorForURL:url
	                                                ofType:fileType
	                                    modelConfiguration:nil
	                                          storeOptions:nil
	                                                 error:outError];
}

- (BOOL)configurePersistentStoreCoordinatorForURL:(NSURL *)url
                                           ofType:(NSString *)fileType
                               modelConfiguration:(NSString *)configuration
                                     storeOptions:(NSDictionary *)storeOptions
                                            error:(NSError **)outError
{
	NSPersistentStoreCoordinator *coordinator;
	NSPersistentStore *store;

	coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
	store = [coordinator addPersistentStoreWithType:[self persistentStoreTypeForFileType:fileType]
	                                  configuration:configuration
	                                            URL:url
	                                        options:storeOptions
	                                          error:outError];
	if (store == nil) {
		[coordinator release];
		return NO;
	}
	[_coordinator release];
	_coordinator = coordinator;
	[[self managedObjectContext] setPersistentStoreCoordinator:_coordinator];
	return YES;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError
{
	/* THE STORE OPENS BEFORE ANYTHING READS FROM IT: a document whose context has no store answers faults from
	 * nowhere, and "no rows" would look like an empty document rather than a file that failed to open. */
	if (![self configurePersistentStoreCoordinatorForURL:url ofType:typeName error:outError]) {
		return NO;
	}
	/* THE DOCUMENT HAS TO KNOW WHERE IT NOW LIVES: `-writeToURL:…` compares its own URL with the target to decide
	 * whether a save is a save-as, and a document that never recorded its URL would reconfigure the store on every
	 * save. */
	[self setFileURL:url];
	[self setFileType:typeName];
	return YES;
}

- (BOOL)revertToContentsOfURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError
{
	/* REVERT IS A RESET AND A REOPEN: the graph is dropped, then the file is read again from the top. */
	[[self managedObjectContext] reset];
	if (![self configurePersistentStoreCoordinatorForURL:url ofType:typeName error:outError]) {
		return NO;
	}
	[self setFileURL:url];
	[self setFileType:typeName];
	return YES;
}

- (BOOL)writeToURL:(NSURL *)url
            ofType:(NSString *)typeName
  forSaveOperation:(NSSaveOperationType)saveOperation
originalContentsURL:(NSURL *)absoluteOriginalContentsURL
             error:(NSError **)outError
{
	(void)absoluteOriginalContentsURL;
	/* SAVE-AS MOVES THE STORE'S FILE FIRST, then the context is saved into it: writing the document's bytes for a URL
	 * the coordinator does not know would leave the graph pointing at the OLD file. */
	if (![[[self fileURL] path] isEqualToString:[url path]]) {
		if (![self configurePersistentStoreCoordinatorForURL:url ofType:typeName error:outError]) {
			return NO;
		}
	}
	if (![[self managedObjectContext] save:outError]) {
		return NO;
	}
	/* **AND THAT IS THE WHOLE WRITE: THE STORE IS THE DOCUMENT'S BYTES.** `NSDocument`'s default write asks for
	 * `-dataOfType:error:` or a file wrapper, and a persistent document has neither — it has a store the coordinator
	 * has already written. Calling super was the first version and it answered NO for a document that had in fact
	 * saved, which the suite caught in one run. */
	[self updateChangeCount:NSChangeCleared];
	return YES;
}

@end
