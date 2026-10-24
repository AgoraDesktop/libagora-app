/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * persistent_document — the AppKit seam (COREDATA-PLAN.md §11, W8.1; §15.2's seventh item).
 *
 * A DOCUMENT OPENS, SAVES, REVERTS AND REOPENS A REAL FILE, over the XML store 10.6's default names — the store
 * type is part of the contract, because a document class that defaulted to SQLite would write a file its own era's
 * applications could not open.
 *
 * THE MODEL IS THE TEST'S OWN, not the bundle's: this suite must not depend on a compiled model existing (there is
 * no model compiler in this tree — §0.20), so a subclass supplies one in code and the rest of the document machinery
 * is the thing under test.
 */

#import <AppKit/NSPersistentDocument.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>
#include <unistd.h>

static int failures = 0;
static int checks = 0;

#define CHECK(cond, what) do { \
	checks++; \
	if (!(cond)) { failures++; fprintf(stderr, "FAIL %s:%d  %s\n", __FILE__, __LINE__, (what)); } \
} while (0)

@interface PersonDocument : NSPersistentDocument
{
	NSManagedObjectModel *_testModel;
}
@end

@implementation PersonDocument

/* CACHED, like the real `-managedObjectModel`: a fresh model per call would give every fetch an ENTITY FROM A
 * DIFFERENT MODEL, and matching by identity would then find nothing — which is exactly what the first version of this
 * fixture did, and the suite reported it as "the saved row is not there". */
- (NSManagedObjectModel *)managedObjectModel
{
	NSManagedObjectModel *model;

	if (_testModel != nil) {
		return _testModel;
	}
	model = [[NSManagedObjectModel alloc] init];
	NSEntityDescription *person = [[[NSEntityDescription alloc] init] autorelease];
	NSAttributeDescription *name = [[[NSAttributeDescription alloc] init] autorelease];

	[name setName:@"name"];
	[name setAttributeType:NSStringAttributeType];
	[name setOptional:YES];
	[person setName:@"Person"];
	[person setProperties:[NSArray arrayWithObject:name]];
	[model setEntities:[NSArray arrayWithObject:person]];
	_testModel = model;
	return model;
}

- (void)dealloc
{
	[_testModel release];
	[super dealloc];
}

@end

static NSUInteger CountPeople(NSPersistentDocument *document)
{
	NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
	NSEntityDescription *entity =
	    [[[document managedObjectModel] entitiesByName] objectForKey:@"Person"];

	[request setEntity:entity];
	return [[[document managedObjectContext] executeFetchRequest:request error:NULL] count];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *path = @"/tmp/libagora-data-document.xmlstore";
	NSURL *url = [NSURL fileURLWithPath:path];
	NSError *error = nil;

	unlink([path fileSystemRepresentation]);

	/* 1. the default store type is 10.6's */
	{
		PersonDocument *document = [[PersonDocument alloc] init];

		CHECK([[document persistentStoreTypeForFileType:@"agoradoc"] isEqual:NSXMLStoreType],
		      "the default store type is the XML store (10.6's documented default)");
		[document release];
	}

	/* 2. a new document opens its file and records where it lives */
	{
		PersonDocument *document = [[PersonDocument alloc] init];

		CHECK([document readFromURL:url ofType:@"agoradoc" error:&error] == YES, "a document opens a new file");
		CHECK([[document managedObjectContext] persistentStoreCoordinator] != nil,
		      "and its context has a coordinator");
		CHECK([[document fileURL] isEqual:url], "and the document recorded where it lives");
		[document release];
	}

	/* 3. write a row through the document's context, then save through the DOCUMENT door */
	{
		PersonDocument *document = [[PersonDocument alloc] init];
		NSEntityDescription *entity;

		(void)[document readFromURL:url ofType:@"agoradoc" error:&error];
		entity = [[[document managedObjectModel] entitiesByName] objectForKey:@"Person"];
		{
			NSManagedObject *person = [[NSManagedObject alloc] initWithEntity:entity
			                                      insertIntoManagedObjectContext:
			                                      [document managedObjectContext]];

			[person setValue:@"alice" forKey:@"name"];
			[person release];
		}
		CHECK([document writeToURL:url ofType:@"agoradoc" forSaveOperation:NSSaveOperation
		     originalContentsURL:nil error:&error] == YES, "the document saves its graph");
		[document release];
	}

	/* 4. a fresh document reads the row back — the file, not the context, is what proves it */
	{
		PersonDocument *document = [[PersonDocument alloc] init];

		CHECK([document readFromURL:url ofType:@"agoradoc" error:&error] == YES, "the file reopens");
		CHECK(CountPeople(document) == 1, "and the saved row is there");
		[document release];
	}

	/* 5. revert drops the graph and reads the file again */
	{
		PersonDocument *document = [[PersonDocument alloc] init];
		NSEntityDescription *entity;

		(void)[document readFromURL:url ofType:@"agoradoc" error:&error];
		entity = [[[document managedObjectModel] entitiesByName] objectForKey:@"Person"];
		{
			NSManagedObject *scratch = [[NSManagedObject alloc] initWithEntity:entity
			                                       insertIntoManagedObjectContext:
			                                       [document managedObjectContext]];

			[scratch setValue:@"not saved" forKey:@"name"];
			[scratch release];
		}
		CHECK(CountPeople(document) == 2, "an unsaved insertion is visible in the context");
		CHECK([document revertToContentsOfURL:url ofType:@"agoradoc" error:&error] == YES, "revert succeeds");
		CHECK(CountPeople(document) == 1, "and the unsaved insertion is gone, the file's row is not");
		[document release];
	}

	printf("persistent_document: %d checks, %d failure(s)\n", checks, failures);
	[pool release];
	return (failures == 0) ? 0 : 1;
}
