/*
 * NSObjectController.m — content, selection, the add/remove pair, and the named Core Data refusals.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE DEPENDENT KEYS ARE ANNOUNCED BY HAND, BECAUSE THIS FOUNDATION DOES NOT COMPUTE THEM.** KVO here does not
 * implement `+keyPathsForValuesAffectingValueForKey:` (its header says so by name), so `-setContent:` sends the
 * will/did pair itself for `contentObject`, `selection`, `selectedObjects`, `canAdd` and `canRemove`. `content`
 * itself is NOT announced here: KVO's automatic setter wrapper already brackets `-setContent:` when anyone observes
 * `content`, and a second pair inside the method would deliver every change twice — the exact failure mode the
 * Foundation slice's `fn_kvo_auto_notifies` seam exists to prevent, arrived at from the AppKit side.
 *
 * **THE TO-MANY PAIR IS USED FOR A COLLECTION CONTENT.** `-addObject:` and `-removeObject:` mutate the caller's
 * array or set in place, so the change is announced at the content's own index (or as a set mutation) instead of as a
 * whole-content replacement. A view bound to `content` then sees the row arrive, not the table reload.
 *
 * **THE SELECTION PROXY IS ONE PRIVATE CLASS WITH NO STORAGE.** It asks the controller for `selectedObjects` on every
 * message, so content changes need no invalidation step, and the controller owns the proxy (which holds the
 * controller WITHOUT retaining it, or the pair would keep each other alive forever).
 */
#import <AppKit/NSObjectController.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/AppKitRefusal.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>

#import <objc/runtime.h>

/* ---- THE SELECTION PROXY ------------------------------------------------------------------------------------- */

@interface FNControllerSelectionProxy : NSObject
{
	__unsafe_unretained NSObjectController *_controller;	/* NOT retained: the controller owns the proxy */
}
- (id)initWithController:(NSObjectController *)controller;
@end

@implementation FNControllerSelectionProxy

- (id)initWithController:(NSObjectController *)controller
{
	self = [super init];
	if (self != nil) {
		_controller = controller;
	}
	return self;
}

/* **ONE OBJECT IS A FORWARDER; SEVERAL ARE AN AGREEMENT TEST.** The first answer is the candidate, and every later
 * object must agree with it or the answer is `NSMultipleValuesMarker`. Identity is checked before `-isEqual:` because
 * two selected objects often share a value object outright (the same font, the same colour).
 *
 * **AN UNKNOWN KEY IS NOT A MARKER HERE, AND THAT IS STATED RATHER THAN IMPLIED.** A key the selected object does
 * not answer raises this Foundation's `NSInvalidArgumentException` from KVC and the exception propagates, so a
 * mismatched selection is loud. Apple's proxy answers `NSNotApplicableMarker` there; this tier's cannot ask "is this
 * key coding-compliant" without either raising or duplicating KVC's private search order, and a duplicated rule is
 * the kind that drifts. The marker remains declared and unused by this file. */
- (id)valueForKey:(NSString *)key
{
	NSArray *objects = [_controller selectedObjects];
	id first = nil;
	BOOL haveFirst = NO;
	NSUInteger i;

	if ([objects count] == 0) {
		return NSNoSelectionMarker;
	}
	for (i = 0; i < [objects count]; i++) {
		id value = [[objects objectAtIndex:i] valueForKey:key];

		if (!haveFirst) {
			first = value;
			haveFirst = YES;
			continue;
		}
		if (first == value) {
			continue;
		}
		if (first == nil || value == nil || ![first isEqual:value]) {
			return NSMultipleValuesMarker;
		}
	}
	return first;
}

/* **A WRITE GOES TO EVERY SELECTED OBJECT, AND A WRITE WITH NO SELECTION RAISES.** There is nothing to write to, and
 * answering success would tell a control its edit landed when it did not. */
- (void)setValue:(id)value forKey:(NSString *)key
{
	NSArray *objects = [_controller selectedObjects];
	NSUInteger i;

	if ([objects count] == 0) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-setValue:%@ forKey:%@: the controller has no selection to write to", value, key];
	}
	for (i = 0; i < [objects count]; i++) {
		[[objects objectAtIndex:i] setValue:value forKey:key];
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<selection proxy of a %@>", [_controller class]];
}

@end

/* ---- THE CONTROLLER ------------------------------------------------------------------------------------------ */

/* A collection for selection purposes: mutable or not, an array or a set is a set of objects to select. */
static BOOL fn_content_is_collection(id content)
{
	return ([content isKindOfClass:[NSArray class]] || [content isKindOfClass:[NSSet class]]);
}

/* A collection that can be changed in place — the only content `-addObject:` and `-removeObject:` can act on. */
static BOOL fn_content_is_mutable_collection(id content)
{
	return ([content isKindOfClass:[NSMutableArray class]] ||
		[content isKindOfClass:[NSMutableSet class]]);
}

@implementation NSObjectController

+ (void)initialize
{
	static NSString * const bindings[] = {
		@"content", @"contentObject", @"selection", @"selectedObjects",
		@"editable", @"canAdd", @"canRemove",
	};
	NSUInteger i;

	/* **THE CLASS-SIDE REGISTRY IS PER CLASS, SO ONLY THE CLASS THAT DECLARES THE NAMES RUNS THIS.** A subclass
	 * inherits `-exposedBindings`' walk up the chain; exposing the same names again on `NSArrayController` would
	 * duplicate them in the answer. */
	if (self != [NSObjectController class]) {
		return;
	}
	for (i = 0; i < sizeof(bindings) / sizeof(bindings[0]); i++) {
		[self exposeBinding:bindings[i]];
	}
}

- (id)init
{
	return [self initWithContent:nil];
}

- (id)initWithContent:(id)content
{
	self = [super init];
	if (self != nil) {
		_content = [content retain];
		_objectClass = [NSMutableDictionary class];	/* a class object is immortal: no retain */
		_editable = YES;
		_automaticallyPreparesContent = NO;
	}
	return self;
}

- (void)dealloc
{
	[_content release];
	[_selection release];
	[super dealloc];
}

/* ---- THE DEPENDENT-KEY PAIR ------------------------------------------------------------------------- */

/* The five keys derived from `content`, in the order they are announced (and the reverse for the `did` half). */
- (void)fn_willChangeDerivedKeys
{
	[self willChangeValueForKey:@"contentObject"];
	[self willChangeValueForKey:@"selection"];
	[self willChangeValueForKey:@"selectedObjects"];
	[self willChangeValueForKey:@"canAdd"];
	[self willChangeValueForKey:@"canRemove"];
}

- (void)fn_didChangeDerivedKeys
{
	[self didChangeValueForKey:@"canRemove"];
	[self didChangeValueForKey:@"canAdd"];
	[self didChangeValueForKey:@"selectedObjects"];
	[self didChangeValueForKey:@"selection"];
	[self didChangeValueForKey:@"contentObject"];
}

/* ---- CONTENT ---------------------------------------------------------------------------------------- */

- (id)content
{
	return _content;
}

- (void)setContent:(id)content
{
	[self fn_willChangeDerivedKeys];
	[content retain];
	[_content release];
	_content = content;
	[self fn_didChangeDerivedKeys];
	if (_automaticallyPreparesContent) {
		[self prepareContent];
	}
}

- (id)contentObject
{
	NSArray *objects;

	if (_content == nil) {
		return nil;		/* no content at all is not the same as an empty collection */
	}
	if (!fn_content_is_collection(_content)) {
		return _content;	/* a single object stands for itself */
	}
	objects = [self selectedObjects];
	if ([objects count] == 0) {
		return NSNoSelectionMarker;
	}
	if ([objects count] == 1) {
		return [objects objectAtIndex:0];
	}
	return NSMultipleValuesMarker;
}

/* ---- SELECTION -------------------------------------------------------------------------------------- */

- (id)selection
{
	if (_selection == nil) {
		_selection = [[FNControllerSelectionProxy alloc] initWithController:self];
	}
	return _selection;
}

- (NSArray *)selectedObjects
{
	if (_content == nil) {
		return [NSArray array];
	}
	if ([_content isKindOfClass:[NSSet class]]) {
		/* A SET HAS NO ORDER, so the array is the set's own `-allObjects`; the proxy's agreement test does not care
		 * about order, and a caller that does has a set content by choice. */
		return [(NSSet *)_content allObjects];
	}
	if ([_content isKindOfClass:[NSArray class]]) {
		return (NSArray *)_content;	/* the content IS the selection: no copy to drift from it */
	}
	return [NSArray arrayWithObject:_content];
}

/* ---- MAKING AND ADDING ------------------------------------------------------------------------------ */

- (Class)objectClass
{
	return _objectClass;
}

- (void)setObjectClass:(Class)objectClass
{
	if (objectClass == Nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-setObjectClass: needs a class; nil would make -newObject answer nothing"];
	}
	_objectClass = objectClass;
}

- (id)newObject
{
	return [[[_objectClass alloc] init] autorelease];
}

- (void)prepareContent
{
	if (_content == nil) {
		[self setContent:[self newObject]];
	}
}

- (BOOL)automaticallyPreparesContent
{
	return _automaticallyPreparesContent;
}

- (void)setAutomaticallyPreparesContent:(BOOL)flag
{
	_automaticallyPreparesContent = flag;
}

- (BOOL)canAdd
{
	return (_content == nil || fn_content_is_mutable_collection(_content));
}

- (BOOL)canRemove
{
	if ([_content isKindOfClass:[NSArray class]] || [_content isKindOfClass:[NSSet class]]) {
		return [(id)_content count] != 0;
	}
	return NO;
}

- (void)add:(id)sender
{
	(void)sender;
	[self addObject:[self newObject]];
}

- (void)addObject:(id)object
{
	if (object == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-addObject: needs an object; nil is not one"];
	}
	if (_content == nil) {
		/* **THE FIRST OBJECT MAKES THE COLLECTION.** `-canAdd` says YES for nil content, so this is the door that
		 * makes that answer true; the change is a SETTING change for `content` (there was none), not an insertion. */
		NSMutableArray *array = [NSMutableArray array];

		[array addObject:object];
		[self setContent:array];
		return;
	}
	if ([_content isKindOfClass:[NSMutableArray class]]) {
		NSMutableArray *array = (NSMutableArray *)_content;
		NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:[array count]];

		[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"content"];
		[self fn_willChangeDerivedKeys];
		[array addObject:object];
		[self fn_didChangeDerivedKeys];
		[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"content"];
		return;
	}
	if ([_content isKindOfClass:[NSMutableSet class]]) {
		NSSet *added = [NSSet setWithObject:object];

		[self willChangeValueForKey:@"content" withSetMutation:NSKeyValueUnionSetMutation usingObjects:added];
		[self fn_willChangeDerivedKeys];
		[(NSMutableSet *)_content unionSet:added];
		[self fn_didChangeDerivedKeys];
		[self didChangeValueForKey:@"content" withSetMutation:NSKeyValueUnionSetMutation usingObjects:added];
		return;
	}
	/* A SINGLE OBJECT IS NOT A COLLECTION, and `-canAdd` said NO. Refused by name rather than ignored. */
	[NSException raise:NSInvalidArgumentException
		    format:@"-addObject: needs a mutable array or set as content (or nil); this controller's content is "
			   "a %@", [_content class]];
}

- (void)remove:(id)sender
{
	NSArray *selected;
	NSUInteger i;

	(void)sender;
	/* A COPY: removing an object mutates the very collection `-selectedObjects` answers for a collection content. */
	selected = [[self selectedObjects] copy];
	for (i = 0; i < [selected count]; i++) {
		[self removeObject:[selected objectAtIndex:i]];
	}
	[selected release];
}

- (void)removeObject:(id)object
{
	if (object == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-removeObject: needs an object; nil is not one"];
	}
	if (_content == nil) {
		return;		/* nothing there is not an error; `-canRemove` said NO and remove is idempotent */
	}
	if ([_content isKindOfClass:[NSMutableArray class]]) {
		NSMutableArray *array = (NSMutableArray *)_content;
		NSUInteger index = [array indexOfObjectIdenticalTo:object];

		if (index != NSNotFound) {
			NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:index];

			[self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@"content"];
			[self fn_willChangeDerivedKeys];
			[array removeObjectAtIndex:index];
			[self fn_didChangeDerivedKeys];
			[self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@"content"];
		}
		return;
	}
	if ([_content isKindOfClass:[NSMutableSet class]]) {
		NSMutableSet *set = (NSMutableSet *)_content;

		if ([set containsObject:object]) {
			NSSet *removed = [NSSet setWithObject:object];

			[self willChangeValueForKey:@"content"
				    withSetMutation:NSKeyValueMinusSetMutation
				       usingObjects:removed];
			[self fn_willChangeDerivedKeys];
			[set minusSet:removed];
			[self fn_didChangeDerivedKeys];
			[self didChangeValueForKey:@"content"
				   withSetMutation:NSKeyValueMinusSetMutation
				      usingObjects:removed];
		}
		return;
	}
	[NSException raise:NSInvalidArgumentException
		    format:@"-removeObject: needs a mutable array or set as content; this controller's content is a %@",
			   [_content class]];
}

/* ---- EDITING AND VALIDATION ------------------------------------------------------------------------- */

- (BOOL)isEditable
{
	return _editable;
}

- (void)setEditable:(BOOL)flag
{
	_editable = flag;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	SEL action = [anItem action];

	/* **A SELECTOR FROM ANOTHER IMAGE IS NOT `==` ITS LITERAL HERE, AND THIS IS THE TRAP THE FIRST RUN FOUND.** The
	 * runtime gives each compilation unit its own `objc_selector` struct for the same NAME (the index inside it is
	 * shared, so dispatch is right), which means the menu item an APPLICATION built carries a different `SEL`
	 * pointer from this library's `@selector(add:)` — MEASURED in `tests/controller_base.m`, where the item is in
	 * the test binary. `==` answered YES for every action, so `-validateUserInterfaceItem:` enabled `remove:` with
	 * nothing to remove. `sel_isEqual` is the comparison the runtime documents for exactly this case: it falls back
	 * to the name. **The same comparison is a hazard in `NSDocument` and `NSDocumentController`, which still use
	 * `==`; it is harmless only while every item they validate is built in this library.** */
	if (sel_isEqual(action, @selector(add:))) {
		return [self canAdd];
	}
	if (sel_isEqual(action, @selector(remove:))) {
		return [self canRemove];
	}
	return YES;
}

/* ---- CORE DATA, REFUSED BY NAME --------------------------------------------------------------------- */

- (id)managedObjectContext
{
	fn_refuse_controller("-managedObjectContext", "a managed object context and the fetch loop that watches it");
	return nil;
}

- (void)setManagedObjectContext:(id)managedObjectContext
{
	(void)managedObjectContext;
	fn_refuse_controller("-setManagedObjectContext:", "a managed object context and the fetch loop that watches it");
}

- (NSString *)entityName
{
	fn_refuse_controller("-entityName", "a managed object context and the fetch loop that watches it");
	return nil;
}

- (void)setEntityName:(NSString *)entityName
{
	(void)entityName;
	fn_refuse_controller("-setEntityName:", "a managed object context and the fetch loop that watches it");
}

- (id)fetchPredicate
{
	fn_refuse_controller("-fetchPredicate", "a predicate family this stack's Foundation has not got");
	return nil;
}

- (void)setFetchPredicate:(id)fetchPredicate
{
	(void)fetchPredicate;
	fn_refuse_controller("-setFetchPredicate:", "a predicate family this stack's Foundation has not got");
}

- (BOOL)usesLazyFetching
{
	fn_refuse_controller("-usesLazyFetching", "a managed object context and the fetch loop that watches it");
	return NO;
}

- (void)setUsesLazyFetching:(BOOL)flag
{
	(void)flag;
	fn_refuse_controller("-setUsesLazyFetching:", "a managed object context and the fetch loop that watches it");
}

- (NSFetchRequest *)defaultFetchRequest
{
	fn_refuse_controller("-defaultFetchRequest", "a managed object context and the fetch loop that watches it");
	return nil;
}

- (BOOL)fetch:(id)sender
{
	(void)sender;
	fn_refuse_controller("-fetch:", "a managed object context and the fetch loop that watches it");
	return NO;
}

- (BOOL)fetchWithRequest:(NSFetchRequest *)fetchRequest merge:(BOOL)merge error:(NSError **)error
{
	(void)fetchRequest;
	(void)merge;
	if (error != NULL) {
		*error = nil;
	}
	fn_refuse_controller("-fetchWithRequest:merge:error:", "a managed object context and the fetch loop that "
			     "watches it");
	return NO;
}

@end
