/*
 * NSTreeController.h — a controller over a tree of model objects, whose arranged objects are `NSTreeNode`s.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CONTENT IS A COLLECTION OF ROOT OBJECTS; THE SHAPE IS A KEY PATH.** `-content` is an array of the model's roots
 * and the tree under each is built by asking every object for its children through `childrenKeyPath` — an
 * array-valued KVC key — and stopping early where `leafKeyPath` says a node is a leaf. **A model that cannot be a tree is
 * REFUSED, not thrown**: a children key whose value is not an array, and a tree deeper than 512 levels (a cycle), print
 * `APPKIT-REFUSE` and build the node without the children they cannot represent, because the build runs inside a KVO
 * announcement and an exception there would leave the will half's records open. The controller builds the
 * `NSTreeNode` graph from that model on every change and hands out its roots as `-arrangedObjects`; a caller never keeps
 * a second graph in step with the model.
 *
 * **THE ROOTS ARE CHILDREN OF AN INVISIBLE ROOT NODE.** `-arrangedObjects` answers that node's children, and the hidden
 * node is what makes a root's path `{i}` rather than the empty path: an empty path names no position at all, and every
 * root would share it.
 *
 * **EVERY POSITION IS AN `NSIndexPath`.** The selection is `selectionIndexPaths` (indexes from the root), `selectedNodes`
 * answers the nodes at those paths and `selectedObjects` their represented objects; `-selectionIndexPath` is the first.
 * The arrange-and-settle shape the array controller uses is here one level deeper: a rebuild re-finds the old selection by
 * OBJECT IDENTITY when `preservesSelection` is on, and `avoidsEmptySelection` keeps a non-empty tree from having no
 * selection at all.
 *
 * **`countKeyPath` IS STORED AND NOTHING READS IT, AND THAT IS A STATEMENT ABOUT THIS FOUNDATION.** Apple's count key
 * path builds children from a count plus indexed accessors (`countOf<Key>`, `objectIn<Key>AtIndex:`); this Foundation's
 * KVC does not synthesise those accessors, so a model must expose `childrenKeyPath` as an ARRAY-valued key. The door is
 * kept because the API has it and a subclass may override `-countKeyPathForNode:`; it does not build anything here.
 *
 * **MUTATIONS ARE MODEL MUTATIONS, AND A DESTINATION PATH IS READ AFTER THE REMOVAL.** `-insertObject:atArrangedObjectIndexPath:`
 * inserts into the parent's mutable children array (or into `-content` for a root path);
 * `-moveNode:toIndexPath:` removes the object first and then inserts it at the destination, which is why a same-parent
 * move lands in the gap the removal left — that is the reading that makes a single "move to this path" mean the same
 * thing for one node and for `-moveNodes:toIndexPath:`, where each node lands one index after the previous.
 *
 * **WHAT THE ARRANGEMENT ANNOUNCES.** A content or shape change announces the arrangement, the two
 * `canInsert`/`canInsertChild`/`canAddChild` questions and the selection keys; a selection change announces the
 * selection keys alone. `-childrenKeyPath`, `-leafKeyPath` and `-sortDescriptors` are ARRANGEMENT CRITERIA: changing one
 * re-arranges, and the selection is re-found by identity like any other rebuild.
 */
#ifndef APPKIT_NSTREECONTROLLER_H
#define APPKIT_NSTREECONTROLLER_H

#import <AppKit/NSObjectController.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSIndexPath;
@class NSString;
@class NSTreeNode;

@interface NSTreeController : NSObjectController
{
	NSTreeNode *_rootNode;			/* RETAINED: the INVISIBLE root; its children are -arrangedObjects */
	NSArray *_roots;			/* RETAINED: the root NSTreeNodes, rebuilt from the model */
	NSArray *_selectionIndexPaths;		/* RETAINED: NSIndexPath objects into the tree */
	NSArray *_selectionBeforeChange;	/* RETAINED only while a rebuild is in flight (preservesSelection) */
	id _childrenKeyPath;			/* COPIED: the array-valued key that gives an object its children */
	id _countKeyPath;			/* COPIED: stored and answered; nothing reads it — see the header block */
	id _leafKeyPath;			/* COPIED: a YES here means "do not ask for children" */
	NSArray *_sortDescriptors;		/* COPIED: applied to each node's represented objects */
	BOOL _avoidsEmptySelection;
	BOOL _preservesSelection;
	BOOL _selectsInsertedObjects;
	BOOL _alwaysUsesMultipleValuesMarker;
}

/* ---- THE SHAPE ---------------------------------------------------------------------------------------------- */

- (nullable id)childrenKeyPath;
- (void)setChildrenKeyPath:(nullable id)keyPath;
/* The per-node questions a subclass overrides; each answers its own stored key path by default. */
- (nullable NSString *)childrenKeyPathForNode:(NSTreeNode *)node;
- (nullable id)countKeyPath;
- (void)setCountKeyPath:(nullable id)keyPath;
- (nullable NSString *)countKeyPathForNode:(NSTreeNode *)node;
- (nullable id)leafKeyPath;
- (void)setLeafKeyPath:(nullable id)keyPath;
- (nullable NSString *)leafKeyPathForNode:(NSTreeNode *)node;

/* THE CHILDREN'S ORDER. The descriptors name the MODEL's keys; they are applied to each node's represented objects, at
 * every level. */
- (nullable NSArray *)sortDescriptors;
- (void)setSortDescriptors:(nullable NSArray *)sortDescriptors;

/* THE ROOTS, as nodes; and the door that rebuilds them (what the array controller calls `-rearrangeObjects`). */
- (NSArray *)arrangedObjects;
- (void)rearrangeObjects;

/* ---- THE SELECTION ------------------------------------------------------------------------------------------ */

- (nullable NSIndexPath *)selectionIndexPath;
- (void)setSelectionIndexPath:(nullable NSIndexPath *)indexPath;
- (NSArray *)selectionIndexPaths;
- (void)setSelectionIndexPaths:(NSArray *)indexPaths;
- (void)addSelectionIndexPaths:(NSArray *)indexPaths;
- (void)removeSelectionIndexPaths:(NSArray *)indexPaths;

/* The nodes at the selected paths, and their represented objects. */
- (NSArray *)selectedNodes;
- (NSArray *)selectedObjects;

/* ---- INSERTING, REMOVING AND MOVING ------------------------------------------------------------------------- */

/* The questions a menu item or `-validateUserInterfaceItem:` asks: is the collection the door would write to mutable? */
- (BOOL)canInsert;
- (BOOL)canInsertChild;
- (BOOL)canAddChild;

/* THE ACTIONS. `-add:` appends a new root object; `-addChild:` appends a new object under the selection (or at the root
 * when there is none); `-insertChild:` and `-insert:` insert a new object AT the selection; `-remove:` removes the
 * selected nodes. */
- (void)add:(nullable id)sender;
- (void)remove:(nullable id)sender;
- (void)addChild:(nullable id)sender;
- (void)insertChild:(nullable id)sender;
- (void)insert:(nullable id)sender;

/* THE PATH DOORS. A root path has one position; a deeper one names the parent's child index last. */
- (void)insertObject:(id)object atArrangedObjectIndexPath:(NSIndexPath *)indexPath;
- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexPaths:(NSArray *)indexPaths;
- (void)removeObjectAtArrangedObjectIndexPath:(NSIndexPath *)indexPath;
- (void)removeObjectsAtArrangedObjectIndexPaths:(NSArray *)indexPaths;

/* `-moveNode:toIndexPath:` moves one; the plural moves them consecutively, the first at the destination's position. */
- (void)moveNode:(NSTreeNode *)node toIndexPath:(NSIndexPath *)indexPath;
- (void)moveNodes:(NSArray *)nodes toIndexPath:(NSIndexPath *)indexPath;

/* ---- THE POLICY --------------------------------------------------------------------------------------------- */

- (BOOL)alwaysUsesMultipleValuesMarker;
- (void)setAlwaysUsesMultipleValuesMarker:(BOOL)flag;
- (BOOL)avoidsEmptySelection;
- (void)setAvoidsEmptySelection:(BOOL)flag;
- (BOOL)preservesSelection;
- (void)setPreservesSelection:(BOOL)flag;
- (BOOL)selectsInsertedObjects;
- (void)setSelectsInsertedObjects:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTREECONTROLLER_H */
