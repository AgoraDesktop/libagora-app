/*
 * NSTreeController.m — the model tree, the node graph rebuilt from it, and the paths in between.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE NODES ARE REBUILT, NOT PATCHED.** A tree controller's model is the caller's; the `NSTreeNode` graph is this
 * class's own reading of it. Every change — content, children key path, leaf key path, sort descriptors, an insertion or
 * a removal — rebuilds the graph from the model in the settle step, and the SELECTION is what crosses that boundary:
 * when `preservesSelection` is on it is re-found by represented-object identity, exactly the way the array controller
 * re-finds a row, and the paths are recomputed because a rebuild renumbers them.
 *
 * **A REBUILD HAPPENS BETWEEN THE WILL AND DID HALVES OF ONE ANNOUNCEMENT.** The derived-key hook the base class owns is
 * extended here, so a content change announces the arrangement and the selection once: the will half snapshots the old
 * selected OBJECTS (the old graph is still standing), the mutation lands, and the did half rebuilds the graph, re-finds
 * the selection and announces. A criteria change (the key paths, the sort descriptors) uses the same shape with its own
 * key list, because it does not touch `content` and must not claim to.
 */
#import <AppKit/NSTreeController.h>
#import <AppKit/NSTreeNode.h>
#import <AppKit/AppKitRefusal.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/NSObjectController_internal.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSIndexPath.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSString.h>

#include <stdio.h>

/* A MODEL TREE IS NOT ALLOWED TO BE CYCLIC, AND THE DEPTH CAP IS HOW THAT IS SAID WITHOUT A VISITED SET: a cycle would
 * otherwise be an infinite build, and a 512-level tree is already far past what a view can show. */
#define FN_TREE_MAX_DEPTH 512

/* ---- THE ANNOUNCED KEYS -------------------------------------------------------------------------------------- */

/* What a content or shape change adds to the base class's own five (`contentObject`, `selection`, `selectedObjects`,
 * `canAdd`, `canRemove`). */
static NSString * const kTreeExtraKeys[] = {
	@"arrangedObjects", @"canInsert", @"canInsertChild", @"canAddChild",
	@"selectionIndexPaths", @"selectionIndexPath", @"selectedNodes",
};

/* What a criteria change announces: the extra keys, plus the three the base class would have covered for a content
 * change — a criteria change does not go through the base hook, so it names them itself. */
static NSString * const kTreeCriteriaKeys[] = {
	@"arrangedObjects", @"canInsert", @"canInsertChild", @"canAddChild",
	@"selectionIndexPaths", @"selectionIndexPath", @"selectedNodes",
	@"selectedObjects", @"contentObject", @"selection",
};

/* What a selection change announces: every selection key EXCEPT `selectionIndexPaths`. **THAT ONE IS KVO'S.** The
 * observer registered for `selectionIndexPaths` makes KVO wrap `-setSelectionIndexPaths:`, so the wrapper announces the
 * key itself; announcing it here as well delivered every selection change twice — measured by the probe, exactly the
 * "one write, one notification" rule the controllers' `content` follows. The settle step, which changes the selection
 * without going through that setter, announces `selectionIndexPaths` in its own criteria/derived list. */
static NSString * const kTreeSelectionKeys[] = {
	@"selectionIndexPath", @"selectedNodes", @"selectedObjects", @"contentObject", @"selection",
};

@implementation NSTreeController

+ (void)initialize
{
	static NSString * const bindings[] = {
		@"arrangedObjects", @"childrenKeyPath", @"countKeyPath", @"leafKeyPath", @"sortDescriptors",
		@"selectionIndexPaths", @"selectionIndexPath", @"selectedNodes",
		@"canInsert", @"canInsertChild", @"canAddChild", @"preservesSelection",
		@"selectsInsertedObjects", @"avoidsEmptySelection", @"alwaysUsesMultipleValuesMarker",
	};
	NSUInteger i;

	if (self != [NSTreeController class]) {
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
		_rootNode = [[NSTreeNode alloc] initWithRepresentedObject:nil];
		_selectionIndexPaths = [[NSArray alloc] init];
		_avoidsEmptySelection = YES;
		_preservesSelection = YES;
		_selectsInsertedObjects = YES;
	}
	return self;
}

- (void)dealloc
{
	[_rootNode release];
	[_roots release];
	[_selectionIndexPaths release];
	[_selectionBeforeChange release];
	[_childrenKeyPath release];
	[_countKeyPath release];
	[_leafKeyPath release];
	[_sortDescriptors release];
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

/* THE OLD SELECTION, AS OBJECTS, BEFORE THE GRAPH IS REPLACED. */
- (void)fn_snapshotSelection
{
	if (_preservesSelection) {
		[_selectionBeforeChange release];
		_selectionBeforeChange = [[self selectedObjects] retain];
	}
}

- (void)fn_willChangeDerivedKeys
{
	[self fn_snapshotSelection];
	[super fn_willChangeDerivedKeys];
	[self fn_willChangeKeys:kTreeExtraKeys count:sizeof(kTreeExtraKeys) / sizeof(kTreeExtraKeys[0])];
}

- (void)fn_didChangeDerivedKeys
{
	[self fn_settle];
	[self fn_didChangeKeys:kTreeExtraKeys count:sizeof(kTreeExtraKeys) / sizeof(kTreeExtraKeys[0])];
	[super fn_didChangeDerivedKeys];
}

- (void)fn_willChangeCriteriaKeys
{
	[self fn_snapshotSelection];
	[self fn_willChangeKeys:kTreeCriteriaKeys count:sizeof(kTreeCriteriaKeys) / sizeof(kTreeCriteriaKeys[0])];
}

- (void)fn_didChangeCriteriaKeys
{
	[self fn_settle];
	[self fn_didChangeKeys:kTreeCriteriaKeys count:sizeof(kTreeCriteriaKeys) / sizeof(kTreeCriteriaKeys[0])];
}

- (void)fn_willChangeSelectionKeys
{
	[self fn_willChangeKeys:kTreeSelectionKeys count:sizeof(kTreeSelectionKeys) / sizeof(kTreeSelectionKeys[0])];
}

- (void)fn_didChangeSelectionKeys
{
	[self fn_didChangeKeys:kTreeSelectionKeys count:sizeof(kTreeSelectionKeys) / sizeof(kTreeSelectionKeys[0])];
}

/* THE PROXY'S FLAG: `alwaysUsesMultipleValuesMarker` is the one question the inherited selection proxy asks. */
- (BOOL)fn_selectionAlwaysUsesMultipleValuesMarker
{
	return _alwaysUsesMultipleValuesMarker;
}

/* ---- BUILDING THE GRAPH ------------------------------------------------------------------------------- */

- (NSArray *)fn_rootObjects
{
	id content = [self content];

	return (content != nil) ? (NSArray *)content : [NSArray array];
}

- (NSString *)fn_childrenKeyForNode:(NSTreeNode *)node
{
	return (NSString *)[self childrenKeyPathForNode:node];
}

/* **THE MODEL ANSWERS, AND A WRONG ANSWER IS NAMED.** A children key whose value is not an array is a model that cannot
 * be a tree; saying so at the build is better than an empty disclosure triangle that never opens. */
- (NSTreeNode *)fn_buildNodeForObject:(id)object depth:(NSUInteger)depth
{
	NSTreeNode *node;
	NSString *leafKey;
	NSString *childrenKey;
	NSArray *children;
	NSUInteger i;

	node = [[[NSTreeNode alloc] initWithRepresentedObject:object] autorelease];
	if (depth > FN_TREE_MAX_DEPTH) {
		/* **THE NODE IS ASSIGNED BEFORE THIS RETURN, AND THAT WAS THE BUG THAT MADE A CYCLE A SEGFAULT.** The first
		 * version returned the local before assigning it, so the parent added an UNINITIALISED pointer as a child and the
		 * graph walked into garbage. An early return of an uninitialised local is invisible in review and fatal in a
		 * tree walk. */
		fprintf(stderr, "APPKIT-REFUSE: NSTreeController stopped %d levels below %s — is a childrenKeyPath "
				"cycle? the deeper children are not built\n", FN_TREE_MAX_DEPTH,
			[[NSString stringWithFormat:@"%@", object] UTF8String]);
		return node;
	}
	leafKey = [self leafKeyPathForNode:node];
	if (leafKey != nil && [[object valueForKey:leafKey] boolValue]) {
		return node;
	}
	childrenKey = [self fn_childrenKeyForNode:node];
	if (childrenKey == nil) {
		return node;
	}
	children = [object valueForKey:childrenKey];
	if (children == nil) {
		return node;
	}
	if (![children isKindOfClass:[NSArray class]]) {
		fprintf(stderr, "APPKIT-REFUSE: NSTreeController: -valueForKey:%s answered a %s, and childrenKeyPath "
				"must be an array-valued key; the node is built without children\n",
			[childrenKey UTF8String],
			[[NSString stringWithFormat:@"%@", [children class]] UTF8String]);
		return node;
	}
	if ([_sortDescriptors count] > 0) {
		children = [children sortedArrayUsingDescriptors:_sortDescriptors];
	}
	for (i = 0; i < [children count]; i++) {
		[[node mutableChildNodes] addObject:[self fn_buildNodeForObject:[children objectAtIndex:i] depth:depth + 1]];
	}
	return node;
}

- (void)fn_rebuild
{
	NSArray *roots = [self fn_rootObjects];
	NSMutableArray *nodes = [NSMutableArray array];
	NSArray *built;
	NSUInteger i;

	for (i = 0; i < [roots count]; i++) {
		[nodes addObject:[self fn_buildNodeForObject:[roots objectAtIndex:i] depth:0]];
	}
	built = [[nodes copy] autorelease];
	[_roots release];
	_roots = [built retain];
	/* THE HIDDEN ROOT HOLDS THEM, which is what gives each root a path `{i}`. */
	[[_rootNode mutableChildNodes] setArray:_roots];
}

/* THE NODE AT A PATH: the first position indexes the roots and each later one a child. nil when it does not resolve —
 * a path is a position in a tree that a rebuild can renumber, so "no such node" is an answer, not an exception. */
- (NSTreeNode *)fn_nodeAtIndexPath:(NSIndexPath *)indexPath
{
	NSTreeNode *node;
	NSUInteger position;
	NSUInteger length;

	if (indexPath == nil) {
		return nil;
	}
	length = [indexPath length];
	if (length == 0) {
		return nil;
	}
	if ([indexPath indexAtPosition:0] >= [[self arrangedObjects] count]) {
		return nil;
	}
	node = [[self arrangedObjects] objectAtIndex:[indexPath indexAtPosition:0]];
	for (position = 1; position < length; position++) {
		NSArray *children = [node childNodes];

		if ([indexPath indexAtPosition:position] >= [children count]) {
			return nil;
		}
		node = [children objectAtIndex:[indexPath indexAtPosition:position]];
	}
	return node;
}

/* THE NODE FOR A REPRESENTED OBJECT, by identity, depth first. The first match wins, which is what "the selection is
 * re-found" has to mean when a model repeats an object. */
- (NSTreeNode *)fn_findNodeForObject:(id)object inNodes:(NSArray *)nodes
{
	NSUInteger i;

	for (i = 0; i < [nodes count]; i++) {
		NSTreeNode *node = [nodes objectAtIndex:i];
		NSTreeNode *found;

		if ([node representedObject] == object) {
			return node;
		}
		found = [self fn_findNodeForObject:object inNodes:[node childNodes]];
		if (found != nil) {
			return found;
		}
	}
	return nil;
}

- (NSTreeNode *)fn_findNodeForObject:(id)object
{
	return [self fn_findNodeForObject:object inNodes:[self arrangedObjects]];
}

/* THE DID HALF OF EVERY CHANGE: rebuild, then put the selection back. */
- (void)fn_settle
{
	NSArray *oldObjects = _selectionBeforeChange;
	NSMutableArray *paths = [NSMutableArray array];
	NSUInteger i;

	_selectionBeforeChange = nil;
	[_roots release];
	_roots = nil;
	[self fn_rebuild];	/* replaces the hidden root's children as well */

	if (oldObjects != nil) {
		for (i = 0; i < [oldObjects count]; i++) {
			NSTreeNode *found = [self fn_findNodeForObject:[oldObjects objectAtIndex:i]];

			if (found != nil) {
				[paths addObject:[found indexPath]];
			}
		}
		[oldObjects release];
	} else {
		for (i = 0; i < [_selectionIndexPaths count]; i++) {
			NSIndexPath *path = [_selectionIndexPaths objectAtIndex:i];

			if ([self fn_nodeAtIndexPath:path] != nil) {
				[paths addObject:path];
			}
		}
	}
	if ([paths count] == 0 && _avoidsEmptySelection && [[self arrangedObjects] count] > 0) {
		[paths addObject:[NSIndexPath indexPathWithIndex:0]];
	}
	{
		NSArray *settled = [[paths copy] autorelease];

		[_selectionIndexPaths release];
		_selectionIndexPaths = [settled retain];
	}
}

/* ---- CONTENT, SHAPE AND ARRANGEMENT ------------------------------------------------------------------- */

/* **THE KIND IS REFUSED BEFORE THE CONTENT MOVES**, the rule the array and dictionary controllers state: a rejected
 * content must leave the previous one in place and the controller able to arrange it. */
- (void)setContent:(id)content
{
	if (content != nil && ![content isKindOfClass:[NSArray class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"NSTreeController content must be an array of root objects; %@ is not an array",
				   [content class]];
	}
	[super setContent:content];
}

- (NSArray *)arrangedObjects
{
	if (_roots == nil) {
		[self fn_rebuild];
	}
	return _roots;
}

- (void)rearrangeObjects
{
	[self fn_willChangeCriteriaKeys];
	[_roots release];
	_roots = nil;
	[self fn_didChangeCriteriaKeys];
}

- (id)childrenKeyPath
{
	return _childrenKeyPath;
}

- (void)setChildrenKeyPath:(id)keyPath
{
	if (keyPath == _childrenKeyPath || [keyPath isEqual:_childrenKeyPath]) {
		return;
	}
	[self fn_willChangeCriteriaKeys];
	[_childrenKeyPath release];
	_childrenKeyPath = [keyPath copy];
	[self fn_didChangeCriteriaKeys];
}

- (NSString *)childrenKeyPathForNode:(NSTreeNode *)node
{
	(void)node;
	return (NSString *)_childrenKeyPath;
}

- (id)countKeyPath
{
	return _countKeyPath;
}

- (void)setCountKeyPath:(id)keyPath
{
	if (keyPath == _countKeyPath || [keyPath isEqual:_countKeyPath]) {
		return;
	}
	/* **STORED AND ANSWERED, AND NOTHING READS IT**: this Foundation's KVC has no `countOf<Key>`/`objectIn<Key>AtIndex:`
	 * synthesis, so children come from an array-valued `childrenKeyPath`. */
	[_countKeyPath release];
	_countKeyPath = [keyPath copy];
}

- (NSString *)countKeyPathForNode:(NSTreeNode *)node
{
	(void)node;
	return (NSString *)_countKeyPath;
}

- (id)leafKeyPath
{
	return _leafKeyPath;
}

- (void)setLeafKeyPath:(id)keyPath
{
	if (keyPath == _leafKeyPath || [keyPath isEqual:_leafKeyPath]) {
		return;
	}
	[self fn_willChangeCriteriaKeys];
	[_leafKeyPath release];
	_leafKeyPath = [keyPath copy];
	[self fn_didChangeCriteriaKeys];
}

- (NSString *)leafKeyPathForNode:(NSTreeNode *)node
{
	(void)node;
	return (NSString *)_leafKeyPath;
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

/* ---- THE SELECTION ------------------------------------------------------------------------------------ */

- (NSIndexPath *)selectionIndexPath
{
	return ([_selectionIndexPaths count] > 0) ? [_selectionIndexPaths objectAtIndex:0] : nil;
}

- (void)setSelectionIndexPath:(NSIndexPath *)indexPath
{
	[self setSelectionIndexPaths:(indexPath != nil ? [NSArray arrayWithObject:indexPath] : [NSArray array])];
}

- (NSArray *)selectionIndexPaths
{
	return _selectionIndexPaths;
}

- (void)setSelectionIndexPaths:(NSArray *)indexPaths
{
	NSUInteger i;

	if (indexPaths == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-setSelectionIndexPaths: needs an array of paths; nil is not one"];
	}
	for (i = 0; i < [indexPaths count]; i++) {
		if ([self fn_nodeAtIndexPath:[indexPaths objectAtIndex:i]] == nil) {
			[NSException raise:NSInvalidArgumentException
				    format:@"selection path %@ does not name a node in the tree",
					   [indexPaths objectAtIndex:i]];
		}
	}
	if (indexPaths == _selectionIndexPaths || [indexPaths isEqual:_selectionIndexPaths]) {
		return;
	}
	[self fn_willChangeSelectionKeys];
	[_selectionIndexPaths release];
	_selectionIndexPaths = [indexPaths copy];
	[self fn_didChangeSelectionKeys];
}

- (void)addSelectionIndexPaths:(NSArray *)indexPaths
{
	NSMutableArray *next;

	if (indexPaths == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-addSelectionIndexPaths: needs an array of paths; nil is not one"];
	}
	next = [[_selectionIndexPaths mutableCopy] autorelease];
	{
		NSUInteger i;

		for (i = 0; i < [indexPaths count]; i++) {
			if (![next containsObject:[indexPaths objectAtIndex:i]]) {
				[next addObject:[indexPaths objectAtIndex:i]];
			}
		}
	}
	[self setSelectionIndexPaths:next];
}

- (void)removeSelectionIndexPaths:(NSArray *)indexPaths
{
	NSMutableArray *next;

	if (indexPaths == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-removeSelectionIndexPaths: needs an array of paths; nil is not one"];
	}
	next = [[_selectionIndexPaths mutableCopy] autorelease];
	[next removeObjectsInArray:indexPaths];
	[self setSelectionIndexPaths:next];
}

- (NSArray *)selectedNodes
{
	NSMutableArray *nodes = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [_selectionIndexPaths count]; i++) {
		NSTreeNode *node = [self fn_nodeAtIndexPath:[_selectionIndexPaths objectAtIndex:i]];

		if (node != nil) {
			[nodes addObject:node];
		}
	}
	return nodes;
}

- (NSArray *)selectedObjects
{
	NSArray *nodes = [self selectedNodes];
	NSMutableArray *objects = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [nodes count]; i++) {
		id object = [[nodes objectAtIndex:i] representedObject];

		if (object != nil) {
			[objects addObject:object];
		}
	}
	return objects;
}

/* ---- THE COLLECTIONS THE MUTATIONS WRITE TO --------------------------------------------------------- */

/* The roots: created on demand, and refused when the content is an immutable array. */
- (NSMutableArray *)fn_mutableRoots
{
	id content = [self content];

	if (content == nil) {
		[self setContent:[NSMutableArray array]];
		content = [self content];
	}
	if (![content isKindOfClass:[NSMutableArray class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"this tree controller's content is a %@, so its roots cannot be changed",
				   [content class]];
	}
	return (NSMutableArray *)content;
}

- (NSMutableArray *)fn_mutableChildrenOfNode:(NSTreeNode *)node
{
	NSString *key = [self fn_childrenKeyForNode:node];
	id children;

	if (key == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"a node cannot take a child without a childrenKeyPath"];
	}
	children = [[node representedObject] valueForKey:key];
	if (![children isKindOfClass:[NSMutableArray class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"the children of %@ are a %@; an insertion needs a mutable array",
				   [node representedObject], [children class]];
	}
	return (NSMutableArray *)children;
}

/* THE COLLECTION A PARENT PATH NAMES, for the three `can…` questions. nil means "not writable". */
- (BOOL)fn_parentPathIsWritable:(NSIndexPath *)parentPath
{
	if ([parentPath length] == 0) {
		id content = [self content];

		return (content == nil || [content isKindOfClass:[NSMutableArray class]]);
	}
	{
		NSTreeNode *parent = [self fn_nodeAtIndexPath:parentPath];
		NSString *key;
		id children;

		if (parent == nil) {
			return NO;
		}
		key = [self fn_childrenKeyForNode:parent];
		if (key == nil) {
			return NO;
		}
		children = [[parent representedObject] valueForKey:key];
		return [children isKindOfClass:[NSMutableArray class]];
	}
}

- (NSIndexPath *)fn_rootPath
{
	NSUInteger none = 0;

	return [NSIndexPath indexPathWithIndexes:&none length:0];
}

- (NSIndexPath *)fn_parentPathForSelection
{
	NSIndexPath *selected = [self selectionIndexPath];

	return (selected != nil) ? [selected indexPathByRemovingLastIndex] : [self fn_rootPath];
}

- (BOOL)canInsert
{
	return [self fn_parentPathIsWritable:[self fn_parentPathForSelection]];
}

- (BOOL)canInsertChild
{
	NSIndexPath *selected = [self selectionIndexPath];

	return [self fn_parentPathIsWritable:(selected != nil) ? selected : [self fn_rootPath]];
}

- (BOOL)canAddChild
{
	return [self canInsertChild];
}

/* ---- INSERTING, REMOVING AND MOVING ------------------------------------------------------------------ */

- (void)fn_noteContentMutationWillChange
{
	[self willChangeValueForKey:@"content"];
	[self fn_willChangeDerivedKeys];
}

- (void)fn_noteContentMutationDidChange
{
	[self fn_didChangeDerivedKeys];
	[self didChangeValueForKey:@"content"];
}

- (void)insertObject:(id)object atArrangedObjectIndexPath:(NSIndexPath *)indexPath
{
	NSIndexPath *parentPath;
	NSUInteger index;

	if (object == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-insertObject:atArrangedObjectIndexPath: needs an object"];
	}
	if (indexPath == nil || [indexPath length] == 0) {
		[NSException raise:NSInvalidArgumentException
			    format:@"an empty index path names no position to insert at"];
	}
	parentPath = [indexPath indexPathByRemovingLastIndex];
	index = [indexPath indexAtPosition:[indexPath length] - 1];
	if ([parentPath length] == 0) {
		NSMutableArray *roots = [self fn_mutableRoots];

		if (index > [roots count]) {
			[NSException raise:NSRangeException
				    format:@"root index %lu is past the end of a %lu-root tree",
					   (unsigned long)index, (unsigned long)[roots count]];
		}
		[self fn_noteContentMutationWillChange];
		[roots insertObject:object atIndex:index];
		[self fn_noteContentMutationDidChange];
	} else {
		NSTreeNode *parent = [self fn_nodeAtIndexPath:parentPath];
		NSMutableArray *children;

		if (parent == nil) {
			[NSException raise:NSRangeException
				    format:@"the parent path %@ does not name a node in the tree", parentPath];
		}
		children = [self fn_mutableChildrenOfNode:parent];
		if (index > [children count]) {
			[NSException raise:NSRangeException
				    format:@"child index %lu is past the end of a %lu-object children array",
					   (unsigned long)index, (unsigned long)[children count]];
		}
		[self fn_noteContentMutationWillChange];
		[children insertObject:object atIndex:index];
		[self fn_noteContentMutationDidChange];
	}
	if (_selectsInsertedObjects) {
		NSTreeNode *inserted = [self fn_findNodeForObject:object];

		if (inserted != nil) {
			[self setSelectionIndexPaths:[NSArray arrayWithObject:[inserted indexPath]]];
		}
	}
}

- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexPaths:(NSArray *)indexPaths
{
	NSUInteger i;

	if (objects == nil || indexPaths == nil || [objects count] != [indexPaths count]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-insertObjects:atArrangedObjectIndexPaths: takes one path for each object"];
	}
	/* EACH PATH IS READ AFTER THE PREVIOUS INSERTION, like the plural move: a batch is a sequence of single inserts,
	 * which is the reading that cannot leave a gap where a caller expected an object. */
	for (i = 0; i < [objects count]; i++) {
		id object = [objects objectAtIndex:i];

		[self insertObject:object atArrangedObjectIndexPath:[indexPaths objectAtIndex:i]];
	}
}

- (void)removeObjectAtArrangedObjectIndexPath:(NSIndexPath *)indexPath
{
	NSTreeNode *node = [self fn_nodeAtIndexPath:indexPath];
	NSIndexPath *parentPath;
	NSUInteger index;

	if (node == nil) {
		[NSException raise:NSRangeException format:@"%@ does not name a node in the tree", indexPath];
	}
	parentPath = [indexPath indexPathByRemovingLastIndex];
	index = [indexPath indexAtPosition:[indexPath length] - 1];
	if ([parentPath length] == 0) {
		NSMutableArray *roots = [self fn_mutableRoots];

		[self fn_noteContentMutationWillChange];
		[roots removeObjectAtIndex:index];
		[self fn_noteContentMutationDidChange];
	} else {
		NSTreeNode *parent = [self fn_nodeAtIndexPath:parentPath];
		NSMutableArray *children;

		if (parent == nil) {
			[NSException raise:NSRangeException
				    format:@"the parent path %@ does not name a node in the tree", parentPath];
		}
		children = [self fn_mutableChildrenOfNode:parent];
		[self fn_noteContentMutationWillChange];
		[children removeObjectAtIndex:index];
		[self fn_noteContentMutationDidChange];
	}
}

- (void)removeObjectsAtArrangedObjectIndexPaths:(NSArray *)indexPaths
{
	NSArray *descending;
	NSUInteger i;

	if (indexPaths == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-removeObjectsAtArrangedObjectIndexPaths: needs an array of paths; nil is not one"];
	}
	/* **DESCENDING, SO A REMOVAL CANNOT RENUMBER A LATER PATH IN THE SAME PARENT.** Two paths under different parents
	 * are independent; two under one parent are not. */
	descending = [indexPaths sortedArrayUsingSelector:@selector(compare:)];
	for (i = [descending count]; i > 0; i--) {
		[self removeObjectAtArrangedObjectIndexPath:[descending objectAtIndex:i - 1]];
	}
}

- (void)moveNode:(NSTreeNode *)node toIndexPath:(NSIndexPath *)indexPath
{
	id object;
	NSTreeNode *current;

	if (node == nil || indexPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-moveNode:toIndexPath: needs a node and a destination path"];
	}
	object = [node representedObject];
	current = [self fn_findNodeForObject:object];
	if (current == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"the node's object is not in the tree"];
	}
	/* **THE DESTINATION IS READ AFTER THE REMOVAL**, which is why a same-parent move lands in the gap the removal left. */
	[self removeObjectAtArrangedObjectIndexPath:[current indexPath]];
	[self insertObject:object atArrangedObjectIndexPath:indexPath];
}

- (void)moveNodes:(NSArray *)nodes toIndexPath:(NSIndexPath *)indexPath
{
	NSIndexPath *parentPath;
	NSUInteger base;
	NSUInteger i;

	if (nodes == nil || indexPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-moveNodes:toIndexPath: needs nodes and a destination path"];
	}
	parentPath = [indexPath indexPathByRemovingLastIndex];
	base = [indexPath indexAtPosition:[indexPath length] - 1];
	for (i = 0; i < [nodes count]; i++) {
		NSIndexPath *target = [parentPath indexPathByAddingIndex:base + i];

		[self moveNode:[nodes objectAtIndex:i] toIndexPath:target];
	}
}

/* ---- THE ACTIONS ------------------------------------------------------------------------------------- */

- (void)add:(id)sender
{
	NSUInteger count = [[self arrangedObjects] count];

	(void)sender;
	[self insertObject:[self newObject]
	   atArrangedObjectIndexPath:[NSIndexPath indexPathWithIndex:count]];
}

- (void)addChild:(id)sender
{
	NSIndexPath *selected = [self selectionIndexPath];

	(void)sender;
	if (selected == nil) {
		[self add:nil];
		return;
	}
	[self insertObject:[self newObject]
	   atArrangedObjectIndexPath:[selected indexPathByAddingIndex:[[[self fn_nodeAtIndexPath:selected] childNodes]
									count]]];
}

- (void)insertChild:(id)sender
{
	[self insert:sender];
}

- (void)insert:(id)sender
{
	NSIndexPath *selected = [self selectionIndexPath];

	(void)sender;
	if (selected == nil) {
		[self add:nil];
		return;
	}
	[self insertObject:[self newObject] atArrangedObjectIndexPath:selected];
}

- (void)remove:(id)sender
{
	(void)sender;
	[self removeObjectsAtArrangedObjectIndexPaths:[self selectionIndexPaths]];
}

/* ---- THE POLICY -------------------------------------------------------------------------------------- */

- (BOOL)alwaysUsesMultipleValuesMarker
{
	return _alwaysUsesMultipleValuesMarker;
}

- (void)setAlwaysUsesMultipleValuesMarker:(BOOL)flag
{
	_alwaysUsesMultipleValuesMarker = flag;
}

- (BOOL)avoidsEmptySelection
{
	return _avoidsEmptySelection;
}

- (void)setAvoidsEmptySelection:(BOOL)flag
{
	_avoidsEmptySelection = flag;
}

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

@end
