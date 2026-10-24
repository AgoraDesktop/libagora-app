/*
 * NSTreeNode.m — the child proxy that keeps the parent links, and the path that walks them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE PROXY IS A SUBCLASS OF `NSMutableArray`, NOT A HAND-WRITTEN COLLECTION.** The node's storage IS a mutable
 * array, and every mutation the base class offers has to be one of the overridden doors or a caller can change the tree
 * without the parent links following. The eight overrides below are the mutation surface this tier's callers use —
 * insert, add, replace, the three removals, `-setArray:` and `-insertObjects:atIndexes:` — and each one does its
 * bookkeeping BEFORE or AFTER the superclass's own write rather than reimplementing storage.
 *
 * **`-setArray:` GOES THROUGH THE OTHER DOORS ON PURPOSE.** A direct `-setArray:` would replace every child at once and
 * leave the old ones' parent links pointing here; rebuilding the array by removing and adding keeps one rule ("a child
 * in this array has this node as its parent") true at every moment.
 */
#import <AppKit/NSTreeNode.h>
#import <Foundation/NSIndexPath.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <stdlib.h>

/* ---- THE CHILD ARRAY ----------------------------------------------------------------------------------------- */

@class FNMutableChildNodes;

/* THE PARENT LINK IS THE NODE'S OWN BUSINESS, so the proxy asks rather than reaching into another object's storage. */
@interface NSTreeNode (AGChildLink)
- (void)fn_setParent:(NSTreeNode *)parent;
- (void)fn_clearParentIf:(NSTreeNode *)parent;
@end

@interface FNMutableChildNodes : NSMutableArray
{
@public
	NSTreeNode *_owner;		/* NOT retained: the node owns this array */
}
@end

/* THE PARENT LINK, SET ONE WAY: a node in the array gets `owner` as its parent, a node removed loses it (only when it
 * was THIS node's child, so a node moved between parents is not left parentless by the old parent's removal). */
static void fn_adopt(NSTreeNode *child, NSTreeNode *owner)
{
	if (child != nil && [child isKindOfClass:[NSTreeNode class]]) {
		[child fn_setParent:owner];
	}
}

static void fn_disown(NSTreeNode *child, NSTreeNode *owner)
{
	if (child != nil && [child isKindOfClass:[NSTreeNode class]]) {
		[child fn_clearParentIf:owner];
	}
}

@implementation FNMutableChildNodes

- (void)insertObject:(id)object atIndex:(NSUInteger)index
{
	[super insertObject:object atIndex:index];
	fn_adopt(object, _owner);
}

- (void)addObject:(id)object
{
	[super addObject:object];
	fn_adopt(object, _owner);
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)object
{
	fn_disown([self objectAtIndex:index], _owner);
	[super replaceObjectAtIndex:index withObject:object];
	fn_adopt(object, _owner);
}

- (void)removeObjectAtIndex:(NSUInteger)index
{
	fn_disown([self objectAtIndex:index], _owner);
	[super removeObjectAtIndex:index];
}

- (void)removeObject:(id)object
{
	NSUInteger index = [self indexOfObjectIdenticalTo:object];

	if (index != NSNotFound) {
		[self removeObjectAtIndex:index];
		return;
	}
	/* The base's `-removeObject:` is by EQUALITY; keep that meaning for objects this tier has not seen. */
	[super removeObject:object];
}

- (void)removeAllObjects
{
	NSUInteger i;

	for (i = 0; i < [self count]; i++) {
		fn_disown([self objectAtIndex:i], _owner);
	}
	[super removeAllObjects];
}

- (void)setArray:(NSArray *)otherArray
{
	[self removeAllObjects];
	[super setArray:otherArray];
	{
		NSUInteger i;

		for (i = 0; i < [self count]; i++) {
			fn_adopt([self objectAtIndex:i], _owner);
		}
	}
}

- (void)insertObjects:(NSArray *)objects atIndexes:(NSIndexSet *)indexes
{
	NSUInteger i = 0;
	NSUInteger index;

	for (index = [indexes firstIndex]; index != NSNotFound; index = [indexes indexGreaterThanIndex:index]) {
		[self insertObject:[objects objectAtIndex:i] atIndex:index];
		i++;
	}
}

@end

/* ---- THE NODE ------------------------------------------------------------------------------------------------ */

@implementation NSTreeNode

+ (instancetype)treeNodeWithRepresentedObject:(id)object
{
	return [[[self alloc] initWithRepresentedObject:object] autorelease];
}

- (instancetype)initWithRepresentedObject:(id)object
{
	self = [super init];
	if (self != nil) {
		_representedObject = [object retain];
	}
	return self;
}

- (void)dealloc
{
	[_representedObject release];
	[_children release];
	[super dealloc];
}

- (void)fn_setParent:(NSTreeNode *)parent
{
	_parent = parent;
}

- (void)fn_clearParentIf:(NSTreeNode *)parent
{
	if (_parent == parent) {
		_parent = nil;
	}
}

- (id)representedObject
{
	return _representedObject;
}

- (NSMutableArray *)mutableChildNodes
{
	if (_children == nil) {
		_children = [[FNMutableChildNodes alloc] init];
		((FNMutableChildNodes *)_children)->_owner = self;
	}
	return _children;
}

- (NSArray *)childNodes
{
	if (_children == nil) {
		return [NSArray array];
	}
	return [[_children copy] autorelease];	/* a snapshot: the tree is mutated through -mutableChildNodes */
}

- (NSTreeNode *)parentNode
{
	return _parent;
}

- (BOOL)isLeaf
{
	return [_children count] == 0;
}

- (NSIndexPath *)indexPath
{
	NSMutableArray *positions = [NSMutableArray array];
	NSTreeNode *node;
	NSIndexPath *path;
	NSUInteger i;

	for (node = self; node->_parent != nil; node = node->_parent) {
		NSUInteger index = [node->_parent->_children indexOfObjectIdenticalTo:node];

		if (index == NSNotFound) {
			/* A node whose parent does not hold it is not in the tree at all; an empty path is the honest answer. */
			NSUInteger none = 0;

			return [NSIndexPath indexPathWithIndexes:&none length:0];
		}
		[positions insertObject:[NSNumber numberWithUnsignedInteger:index] atIndex:0];
	}
	{
		NSUInteger count = [positions count];
		NSUInteger *indexes = (count != 0) ? (NSUInteger *)malloc(count * sizeof(NSUInteger)) : NULL;

		if (count != 0 && indexes == NULL) {
			[NSException raise:NSMallocException format:@"NSTreeNode: no memory for an index path"];
		}
		for (i = 0; i < count; i++) {
			indexes[i] = [[positions objectAtIndex:i] unsignedIntegerValue];
		}
		path = [NSIndexPath indexPathWithIndexes:indexes length:count];
		free(indexes);
	}
	return path;
}

- (NSTreeNode *)descendantNodeAtIndexPath:(NSIndexPath *)indexPath
{
	NSTreeNode *node = self;
	NSUInteger position;
	NSUInteger length;

	if (indexPath == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-descendantNodeAtIndexPath: needs a path; nil is not one"];
	}
	length = [indexPath length];
	for (position = 0; position < length; position++) {
		NSUInteger index = [indexPath indexAtPosition:position];

		if (index >= [node->_children count]) {
			return nil;
		}
		node = [node->_children objectAtIndex:index];
	}
	return node;
}

- (void)sortWithSortDescriptors:(NSArray *)sortDescriptors recursively:(BOOL)recursively
{
	NSMutableArray *sorted;
	NSArray *children = _children;
	NSUInteger i;

	if (sortDescriptors == nil || [sortDescriptors count] == 0) {
		return;
	}
	/* THE DESCRIPTORS NAME THE MODEL'S KEYS, so they sort the REPRESENTED objects and the nodes follow their objects:
	 * sorting nodes by a node key would sort by nothing a caller can name. */
	sorted = [NSMutableArray array];
	for (i = 0; i < [children count]; i++) {
		[sorted addObject:[children objectAtIndex:i]];
	}
	{
		NSMutableArray *objects = [NSMutableArray array];
		NSArray *ordered;

		for (i = 0; i < [sorted count]; i++) {
			[objects addObject:[[sorted objectAtIndex:i] representedObject]];
		}
		ordered = [objects sortedArrayUsingDescriptors:sortDescriptors];
		[sorted removeAllObjects];
		for (i = 0; i < [ordered count]; i++) {
			id object = [ordered objectAtIndex:i];
			NSUInteger j;

			for (j = 0; j < [children count]; j++) {
				NSTreeNode *candidate = [children objectAtIndex:j];

				if ([candidate representedObject] == object) {
					[sorted addObject:candidate];
					break;
				}
			}
		}
	}
	[self setChildrenInOrder:sorted];
	if (recursively) {
		for (i = 0; i < [_children count]; i++) {
			[[_children objectAtIndex:i] sortWithSortDescriptors:sortDescriptors recursively:YES];
		}
	}
}

/* Ordering the children without disturbing the parent links: the array is rebuilt from the same nodes, which are still
 * the same objects, so a node's parent does not change. */
- (void)setChildrenInOrder:(NSArray *)ordered
{
	NSUInteger i;

	if (_children == nil) {
		[self mutableChildNodes];
	}
	[_children removeAllObjects];
	for (i = 0; i < [ordered count]; i++) {
		[_children addObject:[ordered objectAtIndex:i]];
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@: %@>", [self class], _representedObject];
}

@end
