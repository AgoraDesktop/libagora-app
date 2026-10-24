/*
 * controller_base — NSController's editing bookkeeping, and NSObjectController's content and selection.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE TESTS THE CLAIM, NOT THE CODE.** The editing section is a VALUE test of who was asked and in what
 * order — a commit that walked a stale registration list would pass a "returns YES" check and fail this one. The
 * content section is a value test of `contentObject`/`selection`/`selectedObjects` over the three content kinds
 * (nothing, one object, a collection) and of the agreement rule; the KVO section is a DELIVERY test of the dependent
 * announcements this file's controller sends by hand; the Core Data section is an EMPTY-VALUE test of doors that
 * refuse by name (the refusal itself is the refusal census's to count, not this probe's).
 *
 * **AND THE WITHDRAWAL CASE EXISTS BECAUSE THE SNAPSHOT IS THE SUBTLE PART.** An editor whose commit ends ANOTHER
 * editor's editing must leave that editor uncommitted: iterating the live array would commit it anyway.
 */
#import <AppKit/NSController.h>
#import <AppKit/NSObjectController.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * A MODEL WITH A KVO-OBSERVABLE NAME, A SOURCE WITH AN ITEMS ARRAY, AN EDITOR THAT COUNTS         *
 * ============================================================================================ */
@interface AGModel : NSObject
{
	id _name;
}
- (id)name;
- (void)setName:(id)value;
+ (id)modelWithName:(id)name;
@end

@implementation AGModel
- (id)name { return _name; }
- (void)setName:(id)value { [value retain]; [_name release]; _name = value; }
- (void)dealloc { [_name release]; [super dealloc]; }
+ (id)modelWithName:(id)name
{
	AGModel *model = [[self alloc] init];

	[model setName:name];
	return [model autorelease];
}
@end

@interface AGSource : NSObject
{
	id _items;
}
- (id)items;
- (void)setItems:(id)value;
@end

@implementation AGSource
- (id)items { return _items; }
- (void)setItems:(id)value { [value retain]; [_items release]; _items = value; }
- (void)dealloc { [_items release]; [super dealloc]; }
@end

/* THE EDITOR: what it was asked, how often, and whether it refuses. The two hooks make the withdraw-during-commit
 * case expressible without a subclass per scenario. */
@interface AGEditor : NSObject
{
@public
	int commits;
	int discards;
	BOOL refuse;
	id withdrawAfterCommit;		/* NOT retained */
	NSController *controller;	/* NOT retained */
}
@end

@implementation AGEditor
- (BOOL)commitEditing
{
	commits++;
	if (withdrawAfterCommit != nil && controller != nil) {
		[controller objectDidEndEditing:withdrawAfterCommit];
	}
	return !refuse;
}
- (void)discardEditing
{
	discards++;
}
@end

/* A KVO OBSERVER THAT KEEPS THE LAST CHANGE. The change dictionary is copied field by field, because the dictionary
 * itself is reused by nobody but is owned by the sender. */
@interface AGObserver : NSObject
{
@public
	int calls;
	NSString *path;
	id newValue;
	id oldValue;
	NSUInteger kind;
	NSIndexSet *indexes;
}
@end

@implementation AGObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	id value;

	(void)object;
	(void)context;
	calls++;
	[path release];
	path = [keyPath copy];
	value = [change objectForKey:NSKeyValueChangeNewKey];
	[newValue release];
	newValue = [value retain];
	value = [change objectForKey:NSKeyValueChangeOldKey];
	[oldValue release];
	oldValue = [value retain];
	value = [change objectForKey:NSKeyValueChangeKindKey];
	kind = (value != nil) ? [value unsignedIntegerValue] : 0;
	value = [change objectForKey:NSKeyValueChangeIndexesKey];
	[indexes release];
	indexes = [value retain];
}
- (void)dealloc
{
	[path release];
	[newValue release];
	[oldValue release];
	[indexes release];
	[super dealloc];
}
@end

@interface AGEditorDelegateProbe : NSObject
{
@public
	int calls;
	id controller;		/* NOT retained */
	BOOL committed;
	void *context;
}
@end

@implementation AGEditorDelegateProbe
- (void)controller:(id)aController didCommit:(BOOL)flag contextInfo:(void *)contextInfo
{
	calls++;
	controller = aController;
	committed = flag;
	context = contextInfo;
}
@end

/* THE VALIDATED ITEM: a selector and a tag, which is the protocol's whole surface. */
@interface AGItem : NSObject <NSValidatedUserInterfaceItem>
{
	SEL _action;
	NSInteger _tag;
}
- (id)initWithAction:(SEL)action;
@end

@implementation AGItem
- (id)initWithAction:(SEL)action
{
	self = [super init];
	if (self != nil) {
		_action = action;
	}
	return self;
}
- (SEL)action { return _action; }
- (NSInteger)tag { return _tag; }
@end

/* ============================================================================================ *
 * THE PROBE                                                                                     *
 * ============================================================================================ */
int main(void)
{
	@autoreleasepool {
		/* --------------------------------------------------------------------------------- *
		 * 1. NSController: REGISTRATION AND THE THREE COMMIT DOORS                            *
		 * --------------------------------------------------------------------------------- */
		{
			NSController *controller = [[NSController alloc] init];
			AGEditor *first = [[AGEditor alloc] init];
			AGEditor *second = [[AGEditor alloc] init];

			check(![controller isEditing], "a fresh controller is not editing");
			check([controller commitEditing], "and its commit answers YES with no editors to refuse");

			[controller objectDidBeginEditing:first];
			check([controller isEditing], "registering an editor makes it editing");
			[controller objectDidBeginEditing:first];
			check([controller commitEditing] && first->commits == 1,
			      "registering the same editor twice is one registration, so one commit");
			[controller objectDidBeginEditing:second];
			check([controller commitEditing] && first->commits == 2 && second->commits == 1,
			      "a second editor is committed too");

			second->refuse = YES;
			check(![controller commitEditing] && first->commits == 3 && second->commits == 2,
			      "one refusing editor makes the commit answer NO, and every editor is still asked");
			second->refuse = NO;

			[controller discardEditing];
			check(first->discards == 1 && second->discards == 1, "discarding reaches both editors");

			[controller objectDidEndEditing:first];
			check([controller isEditing], "withdrawing one of two editors leaves it editing");
			check([controller commitEditing] && first->commits == 3 && second->commits == 3,
			      "and the withdrawn editor is not asked again");
			[controller objectDidEndEditing:second];
			check(![controller isEditing], "withdrawing the last editor ends the editing");
			check([controller commitEditing] && first->commits == 3 && second->commits == 3,
			      "a commit with no editors asks nobody and answers YES");

			[first release];
			[second release];
			[controller release];
		}

		/* 2. THE DELEGATE FORM, AND THE WITHDRAWAL DURING A COMMIT. */
		{
			NSController *controller = [[NSController alloc] init];
			AGEditor *first = [[AGEditor alloc] init];
			AGEditor *second = [[AGEditor alloc] init];
			AGEditorDelegateProbe *delegate = [[AGEditorDelegateProbe alloc] init];

			[controller objectDidBeginEditing:first];
			[controller objectDidBeginEditing:second];
			[controller commitEditingWithDelegate:delegate
					     didCommitSelector:@selector(controller:didCommit:contextInfo:)
						  contextInfo:(void *)0x77];
			check(delegate->calls == 1 && delegate->controller == controller && delegate->committed
			      && delegate->context == (void *)0x77,
			      "the delegate form sends the controller, the result and the context");

			second->refuse = YES;
			[controller commitEditingWithDelegate:delegate
					     didCommitSelector:@selector(controller:didCommit:contextInfo:)
						  contextInfo:(void *)0x78];
			check(delegate->calls == 2 && !delegate->committed && delegate->context == (void *)0x78,
			      "and reports a refusal as NO");
			[controller commitEditingWithDelegate:nil didCommitSelector:NULL contextInfo:NULL];
			check(delegate->calls == 2, "a nil delegate is a silent no-op, not a crash");

			[controller objectDidEndEditing:first];
			[controller objectDidEndEditing:second];

			/* THE WITHDRAWAL: `first`'s commit ends `second`'s editing, so `second` must not be committed. */
			second->refuse = NO;
			second->commits = 0;
			first->commits = 0;
			first->controller = controller;
			first->withdrawAfterCommit = second;
			[controller objectDidBeginEditing:first];
			[controller objectDidBeginEditing:second];
			check([controller commitEditing] && first->commits == 1 && second->commits == 0,
			      "an editor withdrawn during the commit is not committed by it");
			check([controller commitEditing] && first->commits == 2 && second->commits == 0,
			      "and it stays out of the list for the next commit");

			[delegate release];
			[first release];
			[second release];
			[controller release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 3. NSObjectController: CONTENT AND THE SELECTION PROXY OVER A SINGLE OBJECT         *
		 * --------------------------------------------------------------------------------- */
		{
			NSObjectController *controller = [[NSObjectController alloc] init];
			AGModel *model = [[AGModel alloc] init];

			[model setName:@"alpha"];
			[controller setContent:model];
			check([controller content] == model, "content is the object it was given");
			check([controller contentObject] == model, "and a single object is the content object");
			check([[controller selectedObjects] count] == 1
			      && [[controller selectedObjects] objectAtIndex:0] == model,
			      "with the content as its one selected object");
			check([controller isEditable], "a controller is editable by default");
			check([controller objectClass] == [NSMutableDictionary class],
			      "and makes mutable dictionaries by default");
			check(![controller automaticallyPreparesContent], "and does not prepare content by itself");
			check([[controller exposedBindings] containsObject:@"content"]
			      && [[controller exposedBindings] containsObject:@"selection"]
			      && [[controller exposedBindings] containsObject:@"canRemove"],
			      "the controller's bindings are exposed");

			check([[controller selection] valueForKey:@"name"] != nil, "the selection proxy forwards a read");
			check([[[controller selection] valueForKey:@"name"] isEqual:@"alpha"],
			      "and answers the object's value");
			[[controller selection] setValue:@"beta" forKey:@"name"];
			check([[model name] isEqual:@"beta"], "and a write through it lands on the object");
			check([controller selection] == [controller selection],
			      "the proxy is the same object every time it is asked for");

			[controller setEditable:NO];
			check(![controller isEditable], "editable is stored");

			[model release];
			[controller release];
		}

		/* 4. A COLLECTION CONTENT: EVERY OBJECT IS SELECTED, AND SEVERAL MUST AGREE. */
		{
			NSObjectController *controller = [[NSObjectController alloc] init];
			AGModel *one = [[AGModel alloc] init];
			AGModel *two = [[AGModel alloc] init];
			NSMutableArray *items = [NSMutableArray array];

			[one setName:@"same"];
			[two setName:@"same"];
			[items addObject:one];
			[items addObject:two];
			[controller setContent:items];
			check([controller content] == items, "a collection is kept as the content");
			check([[controller selectedObjects] isEqual:items], "and every object in it is selected");
			check([controller contentObject] == NSMultipleValuesMarker,
			      "several objects make the content object a marker");
			check([[[controller selection] valueForKey:@"name"] isEqual:@"same"],
			      "the proxy answers a value every selected object agrees on");
			[[controller selection] setValue:@"agreed" forKey:@"name"];
			check([[one name] isEqual:@"agreed"] && [[two name] isEqual:@"agreed"],
			      "and a write goes to every selected object");
			[one setName:@"one"];
			[two setName:@"two"];
			check([[controller selection] valueForKey:@"name"] == NSMultipleValuesMarker,
			      "a value the objects disagree on is the multiple-values marker");

			[controller setContent:[NSMutableArray arrayWithObject:one]];
			check([controller contentObject] == one, "one object in a collection is the content object");
			check([[[controller selection] valueForKey:@"name"] isEqual:@"one"],
			      "and the proxy forwards to it alone");

			[controller setContent:[NSArray array]];
			check([controller contentObject] == NSNoSelectionMarker,
			      "an empty collection makes the content object the no-selection marker");
			check([[controller selection] valueForKey:@"name"] == NSNoSelectionMarker,
			      "and the proxy answers it for any key");
			{
				BOOL raised = NO;

				@try {
					[[controller selection] setValue:@"x" forKey:@"name"];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "but a write with no selection raises rather than pretending");
			}

			[controller setContent:nil];
			check([controller content] == nil && [controller contentObject] == nil
			      && [[controller selectedObjects] count] == 0,
			      "no content is no content object and an empty selection");

			[one release];
			[two release];
			[controller release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 5. ADDING AND REMOVING: THE CONTENT'S KIND DECIDES, AND A REFUSAL IS LOUD           *
		 * --------------------------------------------------------------------------------- */
		{
			NSObjectController *controller = [[NSObjectController alloc] init];
			AGModel *model = [[AGModel alloc] init];
			NSMutableArray *items = [NSMutableArray array];

			check([controller canAdd] && ![controller canRemove] && [controller content] == nil,
			      "a nil content can be added to and has nothing to remove");
			[controller addObject:model];
			check([[controller content] isKindOfClass:[NSMutableArray class]]
			      && [[controller selectedObjects] objectAtIndex:0] == model,
			      "the first object makes a one-object mutable array");
			check([controller canRemove], "and now there is something to remove");
			[controller removeObject:model];
			check([[controller content] count] == 0, "removing it empties the array but keeps it");
			check([[controller content] isKindOfClass:[NSMutableArray class]],
			      "the collection survives its last object");
			[controller remove:nil];
			check([[controller content] count] == 0, "and remove: with an empty selection is a no-op");

			[items addObject:[NSMutableDictionary dictionary]];
			[controller setContent:items];
			[controller add:nil];
			check([[controller content] count] == 2
			      && [[[controller content] objectAtIndex:1] isKindOfClass:[NSMutableDictionary class]],
			      "add: appends a new object of objectClass");
			[controller remove:nil];
			check([[controller content] count] == 0, "remove: removes every selected object");

			[controller setObjectClass:[NSMutableString class]];
			check([[controller newObject] isKindOfClass:[NSMutableString class]],
			      "newObject is an instance of the class the controller was told about");
			{
				BOOL raised = NO;

				@try {
					[controller setObjectClass:Nil];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "and a nil class raises");
			}

			/* A SINGLE OBJECT IS NOT A COLLECTION: both questions are NO and both doors refuse. */
			[controller setContent:model];
			check(![controller canAdd] && ![controller canRemove],
			      "a single object is not something to add to or remove from");
			{
				BOOL raised = NO;

				@try {
					[controller addObject:model];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "addObject: on a single object raises");
				raised = NO;
				@try {
					[controller removeObject:model];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "and so does removeObject:");
			}

			/* AN IMMUTABLE ARRAY IS A COLLECTION FOR SELECTION AND NOT FOR MUTATION. */
			[controller setContent:[NSArray arrayWithObject:model]];
			check([[controller selectedObjects] count] == 1,
			      "an immutable array still selects its objects");
			check(![controller canAdd], "but it cannot be added to");
			{
				BOOL raised = NO;

				@try {
					[controller addObject:model];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "and addObject: on it raises");
			}

			/* A SET IS A COLLECTION, AND ITS MUTATION IS THE SET FORM. */
			{
				NSMutableSet *set = [NSMutableSet set];

				[controller setContent:set];
				[controller addObject:model];
				check([set count] == 1, "a mutable set content takes an added object");
				[controller removeObject:model];
				check([set count] == 0, "and loses it again");
			}

			/* PREPARING CONTENT. */
			[controller setContent:nil];
			[controller setObjectClass:[NSMutableDictionary class]];
			[controller prepareContent];
			check([[controller content] isKindOfClass:[NSMutableDictionary class]],
			      "prepareContent fills a nil content with a new object of objectClass");
			[controller setContent:nil];
			[controller setAutomaticallyPreparesContent:YES];
			[controller setContent:nil];
			check([[controller content] isKindOfClass:[NSMutableDictionary class]],
			      "and automaticallyPreparesContent does it on the set");

			[model release];
			[controller release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 6. THE DEPENDENT ANNOUNCEMENTS: A VIEW BOUND TO SELECTION HEARS ABOUT CONTENT        *
		 * --------------------------------------------------------------------------------- */
		{
			NSObjectController *controller = [[NSObjectController alloc] init];
			AGModel *model = [[AGModel alloc] init];
			AGObserver *derived = [[AGObserver alloc] init];
			AGObserver *content = [[AGObserver alloc] init];
			AGObserver *tomany = [[AGObserver alloc] init];
			NSMutableArray *items = [NSMutableArray array];

			[controller addObserver:derived
				     forKeyPath:@"contentObject"
					options:NSKeyValueObservingOptionNew
					context:NULL];
			[controller setContent:model];
			check(derived->calls == 1 && [derived->path isEqual:@"contentObject"],
			      "setting content announces contentObject");
			check(derived->newValue == model, "and the new value is the object");
			[controller removeObserver:derived forKeyPath:@"contentObject"];

			[controller addObserver:content
				     forKeyPath:@"content"
					options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
					context:NULL];
			[controller setContent:nil];
			check(content->calls == 1 && content->newValue == [NSNull null] && content->oldValue == model,
			      "an observer of content gets one change, with the old and new values");
			[controller removeObserver:content forKeyPath:@"content"];

			/* THE TO-MANY FORM: an insertion is announced at the content's index, not as a replacement. */
			[items addObject:model];
			[controller setContent:items];
			[controller addObserver:tomany
				     forKeyPath:@"content"
					options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
					context:NULL];
			{
				AGModel *added = [[AGModel alloc] init];

				[controller addObject:added];
				check(tomany->calls == 1 && tomany->kind == NSKeyValueChangeInsertion,
				      "addObject: announces an insertion on content");
				check([tomany->indexes isEqual:[NSIndexSet indexSetWithIndex:1]],
				      "at the index the object landed at");
				check([tomany->newValue isEqual:[NSArray arrayWithObject:added]]
				      && tomany->oldValue == [NSNull null],
				      "with the inserted object as New and NSNull as the absent Old");
				[controller removeObject:added];
				check(tomany->calls == 2 && tomany->kind == NSKeyValueChangeRemoval,
				      "removeObject: announces a removal");
				check([tomany->newValue isEqual:[NSNull null]]
				      && [tomany->oldValue isEqual:[NSArray arrayWithObject:added]],
				      "with the removed object as Old");
				[added release];
			}
			[controller removeObserver:tomany forKeyPath:@"content"];

			[derived release];
			[content release];
			[tomany release];
			[controller release];
		}

		/* 7. A BINDING IS HOW THE CONTENT ARRIVES: the controller is a KVO client of its own content. */
		{
			AGSource *source = [[AGSource alloc] init];
			NSObjectController *controller = [[NSObjectController alloc] init];
			AGModel *model = [[AGModel alloc] init];
			NSMutableArray *items = [NSMutableArray arrayWithObject:model];

			[model setName:@"bound"];
			[source setItems:items];
			[controller bind:@"content" toObject:source withKeyPath:@"items" options:nil];
			check([controller content] == items, "binding content writes the source's value through KVC");
			check([[[controller selection] valueForKey:@"name"] isEqual:@"bound"],
			      "and the selection proxy reads the content the binding delivered");

			[source setItems:[NSMutableArray arrayWithObject:[AGModel modelWithName:@"later"]]];
			check([[controller content] count] == 1
			      && [[[[controller content] objectAtIndex:0] name] isEqual:@"later"],
			      "a later write to the source delivers a new content");
			[controller unbind:@"content"];

			[controller release];
			[source release];
			[model release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 8. VALIDATION, AND THE CORE DATA DOORS' EMPTY VALUES                                *
		 * --------------------------------------------------------------------------------- */
		{
			NSObjectController *controller = [[NSObjectController alloc] init];
			AGItem *addItem = [[AGItem alloc] initWithAction:@selector(add:)];
			AGItem *removeItem = [[AGItem alloc] initWithAction:@selector(remove:)];
			AGItem *otherItem = [[AGItem alloc] initWithAction:@selector(selectAll:)];
			NSError *error = (NSError *)0x1;

			[controller setContent:[NSMutableArray array]];
			check([controller validateUserInterfaceItem:addItem], "add: is enabled when the content can grow");
			check(![controller validateUserInterfaceItem:removeItem],
			      "remove: is disabled when there is nothing to remove");
			check([controller validateUserInterfaceItem:otherItem],
			      "an action the controller does not own is enabled");

			check([controller managedObjectContext] == nil && [controller entityName] == nil
			      && [controller fetchPredicate] == nil && [controller defaultFetchRequest] == nil,
			      "the Core Data getters answer nil");
			check(![controller usesLazyFetching] && ![controller fetch:nil]
			      && ![controller fetchWithRequest:nil merge:NO error:&error] && error == nil,
			      "and the Core Data flags and fetch doors answer NO, leaving the error nil");
			[controller setManagedObjectContext:nil];
			[controller setEntityName:nil];
			[controller setFetchPredicate:nil];
			[controller setUsesLazyFetching:YES];
			check([controller managedObjectContext] == nil && [controller entityName] == nil
			      && [controller fetchPredicate] == nil && ![controller usesLazyFetching],
			      "and the setters refuse without storing anything");

			[addItem release];
			[removeItem release];
			[otherItem release];
			[controller release];
		}

		printf("controller_base: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
