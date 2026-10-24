/*
 * NSArrayController.m — the arrangement, the selection into it, and the index translation.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CACHE IS DROPPED IN THE WILL PHASE AND REBUILT IN THE DID PHASE, AND THE WILL PHASE REPOPULATES IT.**
 * `fn_beginChange` drops the cache before the announcements so the Old side is computed from the state that is still
 * current; but the Old side READS `-arrangedObjects`, so the cache is full again by the time the mutation lands.
 * `fn_settle` therefore drops it a second time before rebuilding — the first version of this file did not, and a
 * re-sort announced the OLD arrangement as its new value while the content change had already happened underneath.
 *
 * **THE SELECTION IS STORED, NOT DERIVED, AND IT IS SETTLED IN ONE PLACE.** `_selectionIndexes` is the stored answer;
 * `-selectionIndexes`/`-selectedObjects` clamp it against the arrangement so a read can never raise after an external
 * mutation of the content array, and `fn_settle` is what actually re-founds the selection by identity when
 * `preservesSelection` is on. Every door that changes the arrangement calls the settle through the same key pair.
 */
#import <AppKit/NSArrayController.h>
#import <AppKit/NSArrayController_internal.h>
#import <AppKit/NSObjectController_internal.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSSortDescriptor.h>
#import <Foundation/NSString.h>

/* ---- THE KEYS ANNOUNCED AROUND EACH KIND OF CHANGE ----------------------------------------------------------- */

/* What a CONTENT change adds to the base class's own five (`contentObject`, `selection`, `selectedObjects`, `canAdd`,
 * `canRemove`): the arrangement and the selection's position in it. */
static NSString * const kDerivedExtraKeys[] = {
	@"arrangedObjects", @"canInsert", @"selectionIndexes", @"selectionIndex",
	@"canSelectNext", @"canSelectPrevious",
};

/* What a SELECTION change announces: the indexes, the objects they select, and the three values derived from them. */
static NSString * const kSelectionKeys[] = {
	@"selectionIndexes", @"selectionIndex", @"selectedObjects", @"contentObject", @"selection",
	@"canSelectNext", @"canSelectPrevious",
};

/* What an ARRANGEMENT-CRITERIA change (sort, filter, an explicit rearrange) announces: the arrangement, and the
 * selection keys, because re-arranging re-maps the selection. */
static NSString * const kCriteriaKeys[] = {
	@"arrangedObjects", @"canInsert", @"selectionIndexes", @"selectionIndex", @"selectedObjects",
	@"contentObject", @"selection", @"canSelectNext", @"canSelectPrevious",
};

@implementation NSArrayController

+ (void)initialize
{
	static NSString * const bindings[] = {
		@"arrangedObjects", @"selectionIndexes", @"selectionIndex", @"sortDescriptors", @"filterPredicate",
		@"canInsert", @"canSelectNext", @"canSelectPrevious", @"preservesSelection",
		@"selectsInsertedObjects", @"avoidsEmptySelection", @"alwaysUsesMultipleValuesMarker",
		@"automaticallyRearrangesObjects",
	};
	NSUInteger i;

	if (self != [NSArrayController class]) {
		return;
	}
	for (i = 0; i < sizeof(bindings) / sizeof(bindings[0]); i++) {
		[self exposeBinding:bindings[i]];
	}
}

- (id)init
{
	self = [super init];
	if (self != nil) {
		_selectionIndexes = [[NSIndexSet alloc] init];
		_avoidsEmptySelection = YES;
		_preservesSelection = YES;
		_selectsInsertedObjects = YES;
		_clearsFilterPredicateOnInsertion = YES;
		_automaticallyRearrangesObjects = NO;
		_alwaysUsesMultipleValuesMarker = NO;
	}
	return self;
}

- (void)dealloc
{
	[_arrangedObjects release];
	[_sortDescriptors release];
	[_filterPredicate release];
	[_selectionIndexes release];
	[_selectionBeforeChange release];
	[super dealloc];
}

/* ---- THE ANNOUNCEMENT HELPERS ------------------------------------------------------------------------- */

- (void)fn_willChangeKeys:(NSString * const *)keys count:(NSUInteger)count
{
	NSUInteger i;

	for (i = 0; i < count; i++) {
		[self willChangeValueForKey:keys[i]];
	}
}

- (void)fn_didChangeKeys:(NSString * const *)keys count:(NSUInteger)count
{
	NSUInteger i;

	for (i = count; i > 0; i--) {
		[self didChangeValueForKey:keys[i - 1]];
	}
}

- (void)fn_invalidateArrangement
{
	[_arrangedObjects release];
	_arrangedObjects = nil;
}

/* THE WILL HALF OF EVERY ARRANGEMENT CHANGE: capture the old selection (so it can be re-found by identity) and drop
 * the cache, so the Old side of the announcements below is computed from the state that is still current. */
- (void)fn_beginChange
{
	if (_preservesSelection) {
		[_selectionBeforeChange release];
		_selectionBeforeChange = [[self selectedObjects] retain];
	}
	[self fn_invalidateArrangement];
}

/* THE DID HALF: rebuild from the state the mutation left behind, re-find the selection, and apply the empty-selection
 * policy. **THE CACHE IS DROPPED AGAIN HERE** because the will phase's Old reads put it back; see the file header. */
- (void)fn_settle
{
	NSArray *arranged;
	NSMutableIndexSet *next = [[NSMutableIndexSet alloc] init];

	[self fn_invalidateArrangement];
	arranged = [self arrangedObjects];

	if (_selectionBeforeChange != nil) {
		NSUInteger i;

		for (i = 0; i < [_selectionBeforeChange count]; i++) {
			NSUInteger found = [arranged indexOfObjectIdenticalTo:[_selectionBeforeChange objectAtIndex:i]];

			if (found != NSNotFound) {
				[next addIndex:found];
			}
		}
		[_selectionBeforeChange release];
		_selectionBeforeChange = nil;
	} else {
		NSUInteger index;

		for (index = [_selectionIndexes firstIndex]; index != NSNotFound;
		     index = [_selectionIndexes indexGreaterThanIndex:index]) {
			if (index < [arranged count]) {
				[next addIndex:index];
			}
		}
	}
	if ([next count] == 0 && _avoidsEmptySelection && [arranged count] > 0) {
		[next addIndex:0];
	}
	[_selectionIndexes release];
	_selectionIndexes = [next copy];
	[next release];
}

/* ---- THE DERIVED-KEY HOOK, EXTENDED ------------------------------------------------------------------- */

- (void)fn_willChangeDerivedKeys
{
	[self fn_beginChange];
	[super fn_willChangeDerivedKeys];
	[self fn_willChangeKeys:kDerivedExtraKeys count:sizeof(kDerivedExtraKeys) / sizeof(kDerivedExtraKeys[0])];
}

- (void)fn_didChangeDerivedKeys
{
	[self fn_settle];
	[self fn_didChangeKeys:kDerivedExtraKeys count:sizeof(kDerivedExtraKeys) / sizeof(kDerivedExtraKeys[0])];
	[super fn_didChangeDerivedKeys];
}

- (void)fn_willChangeCriteriaKeys
{
	[self fn_beginChange];
	[self fn_willChangeKeys:kCriteriaKeys count:sizeof(kCriteriaKeys) / sizeof(kCriteriaKeys[0])];
}

- (void)fn_didChangeCriteriaKeys
{
	[self fn_settle];
	[self fn_didChangeKeys:kCriteriaKeys count:sizeof(kCriteriaKeys) / sizeof(kCriteriaKeys[0])];
}

- (void)fn_willChangeSelectionKeys
{
	[self fn_willChangeKeys:kSelectionKeys count:sizeof(kSelectionKeys) / sizeof(kSelectionKeys[0])];
}

- (void)fn_didChangeSelectionKeys
{
	[self fn_didChangeKeys:kSelectionKeys count:sizeof(kSelectionKeys) / sizeof(kSelectionKeys[0])];
}

/* THE PROXY'S FLAG, ANSWERED FROM STORAGE: see `alwaysUsesMultipleValuesMarker`. */
- (BOOL)fn_selectionAlwaysUsesMultipleValuesMarker
{
	return _alwaysUsesMultipleValuesMarker;
}

/* ---- THE ARRANGEMENT ---------------------------------------------------------------------------------- */

- (NSArray *)fn_contentObjects
{
	id content = [self content];

	if (content == nil) {
		return [NSArray array];
	}
	if ([content isKindOfClass:[NSSet class]]) {
		return [content allObjects];	/* a set has no order of its own: its iteration order is the input */
	}
	if ([content isKindOfClass:[NSArray class]]) {
		return content;
	}
	/* A SINGLE OBJECT IS THE WRONG CLASS'S CONTENT, and a silent empty table would be the worst way to say so. */
	[NSException raise:NSInvalidArgumentException
		    format:@"NSArrayController content must be an array or a set; this controller's content is a %@",
			   [content class]];
	return nil;
}

/* **THE WRONG KIND IS REFUSED BEFORE THE CONTENT MOVES.** `-fn_contentObjects` raises for a content it cannot arrange,
 * and that is the guard for a content that got in some other way; but a content change ANNOUNCES the arrangement, so a
 * setter that stored first and arranged second would raise out of its own did phase and leave the controller holding a
 * content it can never arrange again. The door asks the VIRTUAL question first (a dictionary controller answers
 * differently), then hands the content to the base class. */
- (BOOL)fn_acceptsContent:(id)content
{
	return (content == nil || [content isKindOfClass:[NSArray class]] || [content isKindOfClass:[NSSet class]]);
}

- (NSString *)fn_contentRule
{
	return @"an array or a set";
}

- (void)setContent:(id)content
{
	if (![self fn_acceptsContent:content]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ content must be %@; %@ is not", [self class], [self fn_contentRule],
				   [content class]];
	}
	[super setContent:content];
}

- (NSArray *)arrangeObjects:(NSArray *)objects
{
	NSArray *arranged = objects;

	/* FILTER FIRST, THEN SORT: an object the predicate drops is never compared, and the sort's stability is spent on
	 * the rows that survive rather than on ones nobody will see. */
	if (_filterPredicate != nil) {
		arranged = [arranged filteredArrayUsingPredicate:_filterPredicate];
	}
	if ([_sortDescriptors count] != 0) {
		arranged = [arranged sortedArrayUsingDescriptors:_sortDescriptors];
	}
	return arranged;
}

- (NSArray *)arrangedObjects
{
	if (_arrangedObjects == nil) {
		_arrangedObjects = [[self arrangeObjects:[self fn_contentObjects]] retain];
	}
	return _arrangedObjects;
}

- (NSArray *)sortDescriptors
{
	return _sortDescriptors;
}

- (void)setSortDescriptors:(NSArray *)sortDescriptors
{
	NSArray *copy = [sortDescriptors copy];

	if (copy == _sortDescriptors || (copy != nil && [copy isEqual:_sortDescriptors])) {
		[copy release];
		return;
	}
	[self fn_willChangeCriteriaKeys];
	[_sortDescriptors release];
	_sortDescriptors = copy;
	[self fn_didChangeCriteriaKeys];
}

- (NSPredicate *)filterPredicate
{
	return _filterPredicate;
}

- (void)setFilterPredicate:(NSPredicate *)filterPredicate
{
	if (filterPredicate == _filterPredicate
	    || (filterPredicate != nil && [filterPredicate isEqual:_filterPredicate])) {
		return;
	}
	[self fn_willChangeCriteriaKeys];
	[filterPredicate retain];
	[_filterPredicate release];
	_filterPredicate = filterPredicate;
	[self fn_didChangeCriteriaKeys];
}

- (BOOL)clearsFilterPredicateOnInsertion
{
	return _clearsFilterPredicateOnInsertion;
}

- (void)setClearsFilterPredicateOnInsertion:(BOOL)flag
{
	_clearsFilterPredicateOnInsertion = flag;
}

- (NSArray *)automaticRearrangementKeyPaths
{
	/* Apple's default is nil: a subclass names the key paths it wants watched. **OWED: nothing watches them here.** */
	return nil;
}

- (BOOL)automaticallyRearrangesObjects
{
	return _automaticallyRearrangesObjects;
}

- (void)setAutomaticallyRearrangesObjects:(BOOL)flag
{
	_automaticallyRearrangesObjects = flag;
}

- (void)rearrangeObjects
{
	[self fn_willChangeCriteriaKeys];
	[self fn_didChangeCriteriaKeys];
}

- (void)didChangeArrangementCriteria
{
	[self rearrangeObjects];
}

/* ---- THE SELECTION ------------------------------------------------------------------------------------ */

/* THE STORED SET, CLAMPED TO THE ARRANGEMENT. The clamp is what makes a read safe after something outside this
 * controller mutated the content array: an index past the end is dropped rather than raised through
 * `-objectsAtIndexes:`. */
- (NSIndexSet *)fn_clampedSelection
{
	NSUInteger count = [[self arrangedObjects] count];

	if ([_selectionIndexes count] == 0 || [_selectionIndexes lastIndex] < count) {
		return _selectionIndexes;
	}
	{
		NSMutableIndexSet *clamped = [[NSMutableIndexSet alloc] init];
		NSUInteger index;

		for (index = [_selectionIndexes firstIndex]; index != NSNotFound;
		     index = [_selectionIndexes indexGreaterThanIndex:index]) {
			if (index < count) {
				[clamped addIndex:index];
			}
		}
		return [clamped autorelease];
	}
}

- (NSUInteger)selectionIndex
{
	return [[self fn_clampedSelection] firstIndex];	/* NSNotFound when the selection is empty */
}

- (void)setSelectionIndex:(NSUInteger)index
{
	NSMutableIndexSet *set = [[NSMutableIndexSet alloc] init];

	if (index != NSNotFound) {
		[set addIndex:index];
	}
	[self setSelectionIndexes:set];
	[set release];
}

- (NSIndexSet *)selectionIndexes
{
	return [self fn_clampedSelection];
}

/* THE VALIDATING DOOR. An index past the end is the caller's error and raises; an index set equal to the current one
 * is not a change and does not announce. */
- (void)setSelectionIndexes:(NSIndexSet *)indexes
{
	NSUInteger count = [[self arrangedObjects] count];
	NSUInteger index;

	if (indexes == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-setSelectionIndexes: needs an index set; nil is not one"];
	}
	for (index = [indexes firstIndex]; index != NSNotFound; index = [indexes indexGreaterThanIndex:index]) {
		if (index >= count) {
			[NSException raise:NSRangeException
				    format:@"selection index %lu is past the end of a %lu-object arrangement",
					   (unsigned long)index, (unsigned long)count];
		}
	}
	if ([indexes isEqualToIndexSet:_selectionIndexes]) {
		return;
	}
	[self fn_willChangeSelectionKeys];
	[_selectionIndexes release];
	_selectionIndexes = [indexes copy];	/* a caller's mutable set must not steer the selection */
	[self fn_didChangeSelectionKeys];
}

- (void)addSelectionIndexes:(NSIndexSet *)indexes
{
	NSMutableIndexSet *set;

	if (indexes == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-addSelectionIndexes: needs an index set; nil is not one"];
	}
	set = [[_selectionIndexes mutableCopy] autorelease];
	[set addIndexes:indexes];
	[self setSelectionIndexes:set];	/* the range check lives there, once */
}

- (void)removeSelectionIndexes:(NSIndexSet *)indexes
{
	NSMutableIndexSet *set;

	if (indexes == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-removeSelectionIndexes: needs an index set; nil is not one"];
	}
	set = [[_selectionIndexes mutableCopy] autorelease];
	[set removeIndexes:indexes];
	[self setSelectionIndexes:set];
}

- (NSArray *)selectedObjects
{
	return [[self arrangedObjects] objectsAtIndexes:[self fn_clampedSelection]];
}

/* THE IDENTITY MAP, WHICH IS WHY A REPLACEMENT CONTENT KEEPS ITS SELECTION: two equal objects are not the same row. */
- (NSMutableIndexSet *)fn_indexesForObjects:(NSArray *)objects
{
	NSArray *arranged = [self arrangedObjects];
	NSMutableIndexSet *set = [[[NSMutableIndexSet alloc] init] autorelease];
	NSUInteger i;

	for (i = 0; i < [objects count]; i++) {
		NSUInteger found = [arranged indexOfObjectIdenticalTo:[objects objectAtIndex:i]];

		if (found != NSNotFound) {
			[set addIndex:found];
		}
	}
	return set;
}

- (void)setSelectedObjects:(NSArray *)objects
{
	if (objects == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-setSelectedObjects: needs an array; nil is not one"];
	}
	[self setSelectionIndexes:[self fn_indexesForObjects:objects]];
}

/* SELECT WHAT WAS JUST INSERTED, WITHOUT CLEARING THE SELECTION WHEN THE OBJECT IS NOT IN THE ARRANGEMENT (it was
 * filtered out, or the content refused it) — an insertion that selects nothing is still a successful insertion. */
- (void)fn_selectObjects:(NSArray *)objects
{
	NSIndexSet *set = [self fn_indexesForObjects:objects];

	if ([set count] != 0) {
		[self setSelectionIndexes:set];
	}
}

- (BOOL)canSelectNext
{
	NSUInteger count = [[self arrangedObjects] count];
	NSUInteger last = [_selectionIndexes lastIndex];

	if (count == 0) {
		return NO;
	}
	if (last == NSNotFound) {
		return YES;		/* nothing selected: the first object is next */
	}
	return (last + 1) < count;
}

- (BOOL)canSelectPrevious
{
	NSUInteger first = [_selectionIndexes firstIndex];

	if ([[self arrangedObjects] count] == 0) {
		return NO;
	}
	if (first == NSNotFound) {
		return YES;		/* nothing selected: the last object is previous */
	}
	return first > 0;
}

- (void)selectNext:(id)sender
{
	NSUInteger last;

	(void)sender;
	if (![self canSelectNext]) {
		return;
	}
	last = [_selectionIndexes lastIndex];
	[self setSelectionIndex:(last == NSNotFound) ? 0 : last + 1];
}

- (void)selectPrevious:(id)sender
{
	NSUInteger first;
	NSUInteger count;

	(void)sender;
	if (![self canSelectPrevious]) {
		return;
	}
	count = [[self arrangedObjects] count];
	first = [_selectionIndexes firstIndex];
	[self setSelectionIndex:(first == NSNotFound) ? count - 1 : first - 1];
}

/* ---- ADDING AND REMOVING ------------------------------------------------------------------------------ */

- (BOOL)canInsert
{
	return [self canAdd];
}

/* AN INSERTION IS A USER ACT, SO THE FILTER GOES FIRST when the policy says so: a row the user just added and cannot
 * see is a lost row. Only the add doors clear it; an insertion at an arranged index does not, because the index would
 * change meaning while the caller was still holding it. */
- (void)fn_clearFilterForInsertion
{
	if (_clearsFilterPredicateOnInsertion && _filterPredicate != nil) {
		[self setFilterPredicate:nil];
	}
}

- (void)addObject:(id)object
{
	[self fn_clearFilterForInsertion];
	[super addObject:object];
	if (_selectsInsertedObjects) {
		[self fn_selectObjects:[NSArray arrayWithObject:object]];
	}
}

- (void)addObjects:(NSArray *)objects
{
	NSUInteger i;

	if (objects == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-addObjects: needs an array; nil is not one"];
	}
	[self fn_clearFilterForInsertion];
	for (i = 0; i < [objects count]; i++) {
		[super addObject:[objects objectAtIndex:i]];	/* one content mutation each; the selection is applied once */
	}
	if (_selectsInsertedObjects) {
		[self fn_selectObjects:objects];
	}
}

- (void)addSelectedObjects:(id)sender
{
	(void)sender;
	[self addObjects:[self selectedObjects]];
}

- (void)insert:(id)sender
{
	NSArray *arranged;
	NSUInteger index;

	(void)sender;
	arranged = [self arrangedObjects];
	index = ([_selectionIndexes count] > 0) ? [_selectionIndexes firstIndex] : [arranged count];
	[self insertObject:[self newObject] atArrangedObjectIndex:index];
}

/* **A POSITIONAL TRANSLATION, SO A CONTENT THAT HOLDS THE SAME OBJECT TWICE STILL TRANSLATES EXACTLY.** Identity
 * alone would send the second occurrence to the first one's content index; counting the identical objects that come
 * before it is what keeps the two apart, and an array is allowed to repeat an object. */
- (NSUInteger)fn_contentIndexForArrangedObjectAtIndex:(NSUInteger)arrangedIndex
{
	NSArray *arranged = [self arrangedObjects];
	id object = [arranged objectAtIndex:arrangedIndex];
	NSArray *content = [self fn_contentObjects];
	NSUInteger occurrence = 0;
	NSUInteger seen = 0;
	NSUInteger i;

	for (i = 0; i < arrangedIndex; i++) {
		if ([arranged objectAtIndex:i] == object) {
			occurrence++;
		}
	}
	for (i = 0; i < [content count]; i++) {
		if ([content objectAtIndex:i] == object) {
			if (seen == occurrence) {
				return i;
			}
			seen++;
		}
	}
	return NSNotFound;
}

- (void)insertObject:(id)object atArrangedObjectIndex:(NSUInteger)index
{
	NSArray *arranged = [self arrangedObjects];
	NSUInteger contentIndex;

	if (index > [arranged count]) {
		[NSException raise:NSRangeException
			    format:@"arranged index %lu is past the end of a %lu-object arrangement",
				   (unsigned long)index, (unsigned long)[arranged count]];
	}
	if (index == [arranged count]) {
		contentIndex = [[self content] count];		/* append: the one position with no anchor to find */
	} else {
		contentIndex = [self fn_contentIndexForArrangedObjectAtIndex:index];
		if (contentIndex == NSNotFound) {
			[NSException raise:NSInternalInconsistencyException
				    format:@"the arrangement holds an object the content does not: %@",
					   [arranged objectAtIndex:index]];
		}
	}
	[self fn_insertObject:object atContentIndex:contentIndex];
	if (_selectsInsertedObjects) {
		[self fn_selectObjects:[NSArray arrayWithObject:object]];
	}
}

/* **EACH OBJECT GOES IMMEDIATELY BEFORE THE OBJECT THAT WAS AT ITS INDEX.** The anchors are translated against the
 * arrangement AS IT STANDS, then the insertions run from the highest CONTENT index down, so inserting at a lower
 * index cannot move a higher one out from under its anchor. */
- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexes:(NSIndexSet *)indexes
{
	NSArray *arranged = [self arrangedObjects];
	NSMutableDictionary *byContentIndex = [NSMutableDictionary dictionary];
	NSMutableArray *sortedKeys;
	NSUInteger arrangedIndex;
	NSUInteger count = 0;
	NSUInteger i;

	if (objects == nil || indexes == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-insertObjects:atArrangedObjectIndexes: needs objects and indexes"];
	}
	if ([objects count] != [indexes count]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-insertObjects:atArrangedObjectIndexes: takes %lu objects for %lu indexes",
				   (unsigned long)[objects count], (unsigned long)[indexes count]];
	}
	for (arrangedIndex = [indexes firstIndex]; arrangedIndex != NSNotFound;
	     arrangedIndex = [indexes indexGreaterThanIndex:arrangedIndex]) {
		NSUInteger contentIndex;
		NSNumber *key;

		if (arrangedIndex > [arranged count]) {
			[NSException raise:NSRangeException
				    format:@"arranged index %lu is past the end of a %lu-object arrangement",
					   (unsigned long)arrangedIndex, (unsigned long)[arranged count]];
		}
		contentIndex = (arrangedIndex == [arranged count])
			? [[self content] count]
			: [self fn_contentIndexForArrangedObjectAtIndex:arrangedIndex];
		if (contentIndex == NSNotFound) {
			[NSException raise:NSInternalInconsistencyException
				    format:@"the arrangement holds an object the content does not: %@",
					   [arranged objectAtIndex:arrangedIndex]];
		}
		key = [NSNumber numberWithUnsignedInteger:contentIndex];
		[byContentIndex setObject:[objects objectAtIndex:count] forKey:key];
		count++;
	}
	sortedKeys = [[byContentIndex allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (i = [sortedKeys count]; i > 0; i--) {
		NSUInteger key = [[sortedKeys objectAtIndex:i - 1] unsignedIntegerValue];

		[self fn_insertObject:[byContentIndex objectForKey:[sortedKeys objectAtIndex:i - 1]]
		       atContentIndex:key];
	}
	if (_selectsInsertedObjects) {
		[self fn_selectObjects:objects];
	}
}

- (void)removeObjectAtArrangedObjectIndex:(NSUInteger)index
{
	NSArray *arranged = [self arrangedObjects];

	if (index >= [arranged count]) {
		[NSException raise:NSRangeException
			    format:@"arranged index %lu is past the end of a %lu-object arrangement",
				   (unsigned long)index, (unsigned long)[arranged count]];
	}
	[self removeObject:[arranged objectAtIndex:index]];
}

- (void)removeObjectsAtArrangedObjectIndexes:(NSIndexSet *)indexes
{
	NSArray *arranged = [self arrangedObjects];
	NSMutableArray *doomed = [NSMutableArray array];
	NSUInteger index;

	if (indexes == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-removeObjectsAtArrangedObjectIndexes: needs an index set; nil is not one"];
	}
	for (index = [indexes firstIndex]; index != NSNotFound; index = [indexes indexGreaterThanIndex:index]) {
		if (index >= [arranged count]) {
			[NSException raise:NSRangeException
				    format:@"arranged index %lu is past the end of a %lu-object arrangement",
					   (unsigned long)index, (unsigned long)[arranged count]];
		}
		[doomed addObject:[arranged objectAtIndex:index]];
	}
	[self removeObjects:doomed];
}

- (void)removeObjects:(NSArray *)objects
{
	NSUInteger i;

	if (objects == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-removeObjects: needs an array; nil is not one"];
	}
	for (i = 0; i < [objects count]; i++) {
		[self removeObject:[objects objectAtIndex:i]];
	}
}

- (void)removeSelectedObjects:(id)sender
{
	(void)sender;
	[self removeObjects:[self selectedObjects]];
}

/* ---- THE POLICY --------------------------------------------------------------------------------------- */

- (BOOL)preservesSelection
{
	return _preservesSelection;
}

- (void)setPreservesSelection:(BOOL)flag
{
	_preservesSelection = flag;
}

- (BOOL)selectsInsertedObjects
{
	return _selectsInsertedObjects;
}

- (void)setSelectsInsertedObjects:(BOOL)flag
{
	_selectsInsertedObjects = flag;
}

- (BOOL)avoidsEmptySelection
{
	return _avoidsEmptySelection;
}

- (void)setAvoidsEmptySelection:(BOOL)flag
{
	_avoidsEmptySelection = flag;
}

- (BOOL)alwaysUsesMultipleValuesMarker
{
	return _alwaysUsesMultipleValuesMarker;
}

- (void)setAlwaysUsesMultipleValuesMarker:(BOOL)flag
{
	_alwaysUsesMultipleValuesMarker = flag;
}

@end
