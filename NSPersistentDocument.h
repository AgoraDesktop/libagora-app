/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPersistentDocument — the ONE AppKit class that touches Core Data (COREDATA-PLAN.md §11, W8.1). Nine selectors,
 * and every one of them is a hook `NSDocument` already provides: this class is a FACTORY AND A LIFETIME, not a
 * document system of its own.
 *
 * THE DEFAULT STORE TYPE IS `NSXMLStoreType`, AND THAT IS 10.6'S ANSWER RATHER THAN A PREFERENCE: Apple's
 * `-persistentStoreTypeForFileType:` returns `NSXMLStoreType` when the Info.plist says nothing (§7.2). A document
 * class that defaulted to SQLite would write a file its own era's applications could not open, so the default here is
 * the XML store and an application that wants SQLite overrides the method.
 *
 * THE STACK IS LAZY AND THE SAVE ORDER IS THE DOCUMENT'S: the context is created on first use, `-readFromURL:` opens
 * the store BEFORE anything is read from it, and `-writeToURL:…` SAVES THE CONTEXT FIRST and only then lets
 * `NSDocument` write — a document whose bytes were written before its graph was saved would be a file that disagrees
 * with itself.
 *
 * WHAT THIS CLASS DOES NOT DO: it does not provide the controllers. `NSObjectController` and `NSArrayController` are
 * the AppKit's own 10.6 debt (§11, W8.2) and are absent from this tree; a document with no controllers is still a
 * document, and the four bindings-facing selectors on those two classes are not this file's business.
 */

#ifndef APPKIT_NSPERSISTENTDOCUMENT_H
#define APPKIT_NSPERSISTENTDOCUMENT_H

#import <AppKit/NSDocument.h>
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSPersistentDocument : NSDocument
{
	NSManagedObjectModel *_managedObjectModel;
	NSManagedObjectContext *_managedObjectContext;
	NSPersistentStoreCoordinator *_coordinator;
}

/* The context the document's graph lives in, created on first use with a coordinator over `-managedObjectModel`. */
- (NSManagedObjectContext *)managedObjectContext;
- (void)setManagedObjectContext:(nullable NSManagedObjectContext *)context;

/* The schema. The default asks the bundle for a compiled model — and when there is none, answers an EMPTY model
 * rather than refusing: a document that cannot open its own model has no graph to show, and `-readFromURL:` reports
 * the store failure with a reason. */
- (NSManagedObjectModel *)managedObjectModel;

/* Open the store for `url`. The two-argument form is Apple's convenience and delegates to the four-argument one. */
- (BOOL)configurePersistentStoreCoordinatorForURL:(NSURL *)url
                                           ofType:(nullable NSString *)fileType
                                            error:(NSError **)outError;
- (BOOL)configurePersistentStoreCoordinatorForURL:(NSURL *)url
                                           ofType:(nullable NSString *)fileType
                               modelConfiguration:(nullable NSString *)configuration
                                     storeOptions:(nullable NSDictionary *)storeOptions
                                            error:(NSError **)outError;

/* `NSXMLStoreType` for every type unless a subclass says otherwise, which is 10.6's documented default. */
- (NSString *)persistentStoreTypeForFileType:(NSString *)fileType;

/* The three document doors, overridden to make the store agree with the file. */
- (BOOL)readFromURL:(NSURL *)url ofType:(nullable NSString *)typeName error:(NSError **)outError;
- (BOOL)revertToContentsOfURL:(NSURL *)url ofType:(nullable NSString *)typeName error:(NSError **)outError;
- (BOOL)writeToURL:(NSURL *)url
            ofType:(nullable NSString *)typeName
  forSaveOperation:(NSSaveOperationType)saveOperation
originalContentsURL:(nullable NSURL *)absoluteOriginalContentsURL
             error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPERSISTENTDOCUMENT_H */
