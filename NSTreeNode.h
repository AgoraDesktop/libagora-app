/*
 * NSTreeNode.h — one node of a tree: a represented object, its children, and where it sits.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A NODE IS A POSITION, NOT A COPY.** It stands for a model object (`representedObject`) and for the place that object
 * occupies in a tree, which is what `-indexPath` answers: the chain of child indexes from the root, which is the index
 * path every tree-view door speaks in. The model supplies the CONTENT of the tree; the nodes supply its SHAPE, and the
 * controller rebuilds them from the model rather than asking a caller to keep two graphs in step.
 *
 * **THE CHILDREN ARRAY IS A PROXY THAT MAINTAINS THE PARENT LINKS.** `-mutableChildNodes` answers an array that sets a
 * child's `-parentNode` when it is inserted and clears it when it is removed, because `-indexPath` walks those links
 * upward: a child array that did not maintain them would make every path under it wrong the moment the tree was built
 * by hand. The mutators this tier covers are the ones a caller uses — insert, add, replace, remove (by index, object,
 * or all) and `-setArray:`.
 *
 * **A NODE DOES NOT OWN ITS CHILDREN'S MODEL OBJECTS ANY MORE THAN THE MODEL DOES.** It retains the represented object
 * and its child nodes; a parent link is NOT a retain, or a tree would be a cycle that never frees.
 */
#ifndef APPKIT_NSTREENODE_H
#define APPKIT_NSTREENODE_H

#import <Foundation/NSArray.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSIndexPath;
@class NSString;

@interface NSTreeNode : NSObject
{
	id _representedObject;		/* RETAINED: the model object this node stands for */
	NSMutableArray *_children;	/* RETAINED, made on first ask: the child nodes, in order */
	NSTreeNode *_parent;		/* NOT retained: the node above this one, or nil for a root */
}

/* THE CLASS DOOR, and the designated initialiser: a node for one model object, with no children yet. */
+ (instancetype)treeNodeWithRepresentedObject:(nullable id)object;
- (instancetype)initWithRepresentedObject:(nullable id)object;

/* THE MODEL OBJECT THIS NODE STANDS FOR. Retained, never copied — a node points at the caller's object. */
- (nullable id)representedObject;

/* THE CHILDREN. `-childNodes` is a snapshot (empty for a leaf); `-mutableChildNodes` is the live proxy described in the
 * header block, and it creates the storage on first ask. */
- (NSArray *)childNodes;
- (NSMutableArray *)mutableChildNodes;

/* THE NODE ABOVE, or nil for a root. */
- (nullable NSTreeNode *)parentNode;

/* YES when the node has no children. */
- (BOOL)isLeaf;

/* THE POSITION, as the chain of child indexes from the root: the empty path for a root. */
- (NSIndexPath *)indexPath;

/* THE NODE AT A PATH RELATIVE TO THIS ONE, or nil when the path does not resolve. */
- (nullable NSTreeNode *)descendantNodeAtIndexPath:(NSIndexPath *)indexPath;

/* Sort this node's children (recursively when asked) by the descriptors. The represented objects are the sort keys'
 * receivers, so the descriptors name the MODEL's keys, not the node's. */
- (void)sortWithSortDescriptors:(NSArray *)sortDescriptors recursively:(BOOL)recursively;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTREENODE_H */
