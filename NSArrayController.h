/*
 * NSArrayController.h — a controller over a collection: an arranged view of it, and a selection inside that view.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE SUBCLASS ADDS ONE IDEA TO `NSObjectController`: THE ARRANGEMENT.** The content is a collection; the controller
 * presents it as `arrangedObjects` — the content FILTERED by `filterPredicate` and then SORTED by `sortDescriptors` —
 * and the selection is `selectionIndexes` INTO THAT ARRAY, not into the content. Every door that takes or answers a
 * position speaks in arranged indexes; `-insertObject:atArrangedObjectIndex:` is the one that translates, and a
 * removal translates by object identity, so there is exactly one place where an arranged index becomes a content
 * index.
 *
 * **THE CONTENT MUST BE A COLLECTION.** An `NSArray` is used as it stands; an `NSSet` contributes `-allObjects` (a
 * set has no order to arrange, so its own iteration order is the input); nil arranges to nothing. Anything else — a
 * single object — raises `NSInvalidArgumentException` from `-arrangedObjects`, naming the rule, because an array
 * controller over one object is a caller using the wrong class and a silent empty table is the worst way to say so.
 *
 * **THE ARRANGEMENT IS CACHED AND REBUILT, NOT KEPT IN STEP BY HAND.** `-arrangedObjects` answers a retained cache;
 * every mutation (content, sort, filter, and the base class's add/remove pair) drops the cache in its will phase and
 * lets the next ask rebuild it, so a rebuild always reflects the state the did phase is about to announce. The
 * dependent keys `arrangedObjects`, `selectionIndexes`, `selectionIndex`, `selectedObjects`, `contentObject`,
 * `selection`, `canInsert`, `canSelectNext` and `canSelectPrevious` are announced around those changes, which is what
 * a table bound to `arrangedObjects` and a form bound to `selection.name` both need.
 *
 * **THE POLICY IS FIVE FLAGS, APPLIED IN ONE SETTLE STEP AFTER EVERY ARRANGEMENT CHANGE.** The defaults are Apple's:
 * `preservesSelection` YES (the old selection is re-found by object identity, so a re-sort keeps the same rows
 * selected), `selectsInsertedObjects` YES (an inserted object becomes the selection), `avoidsEmptySelection` YES (a
 * non-empty arrangement is never left with nothing selected), `clearsFilterPredicateOnInsertion` YES (an insertion is
 * a user act, and a newly added row that the filter would hide looks like a lost row), and
 * `alwaysUsesMultipleValuesMarker` NO (`-selection` forwards a single object's value; YES makes it answer
 * `NSMultipleValuesMarker` for reads even then, which is how a multi-selection form is made read-only).
 *
 * **TWO DOORS ARE STORED AND ANSWERED WITH NO READER, AND THAT IS SAID HERE RATHER THAN LEFT TO BE DISCOVERED.**
 * `automaticallyRearrangesObjects` and `automaticRearrangementKeyPaths` are the live-rearrangement pair: the real
 * implementation observes every arranged object for those key paths and re-arranges when one changes. **OWED: the
 * observation half.** `-automaticRearrangementKeyPaths` answers nil unless a subclass overrides it, the flag is
 * stored, and a caller that needs live rearrangement calls `-rearrangeObjects` after its write (or
 * `-didChangeArrangementCriteria` when it changed the criteria). Nothing in this tier watches the arranged objects.
 */
#ifndef APPKIT_NSARRAYCONTROLLER_H
#define APPKIT_NSARRAYCONTROLLER_H

#import <AppKit/NSObjectController.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSIndexSet;
@class NSPredicate;
@class NSSortDescriptor;
@class NSString;

@interface NSArrayController : NSObjectController
{
	NSArray *_arrangedObjects;		/* RETAINED; nil means "rebuild on the next ask" */
	NSArray *_sortDescriptors;		/* COPIED: a caller's mutable array must not steer the arrangement */
	NSPredicate *_filterPredicate;		/* RETAINED; nil means no filter */
	NSIndexSet *_selectionIndexes;		/* RETAINED: indexes into the ARRANGEMENT, never into the content */
	NSArray *_selectionBeforeChange;	/* RETAINED only while a change is in flight (preservesSelection) */
	BOOL _avoidsEmptySelection;
	BOOL _preservesSelection;
	BOOL _selectsInsertedObjects;
	BOOL _alwaysUsesMultipleValuesMarker;
	BOOL _clearsFilterPredicateOnInsertion;
	BOOL _automaticallyRearrangesObjects;
}

/* ---- THE ARRANGEMENT ---------------------------------------------------------------------------------------- */

/* THE ARRANGED VIEW: filtered, then sorted, cached. Never nil; empty when there is no content. */
- (NSArray *)arrangedObjects;

/* THE PURE FUNCTION, for a caller that wants its own array arranged: filter first (so a dropped object is never
 * sorted), then the descriptor chain. `-arrangedObjects` is this over the content. */
- (NSArray *)arrangeObjects:(NSArray *)objects;

- (nullable NSArray *)sortDescriptors;
- (void)setSortDescriptors:(nullable NSArray *)sortDescriptors;

/* **A REAL FILTER.** This Foundation's predicate family landed with `-filteredArrayUsingPredicate:`, so the door
 * filters rather than refusing; a nil predicate means no filter. */
- (nullable NSPredicate *)filterPredicate;
- (void)setFilterPredicate:(nullable NSPredicate *)filterPredicate;

/* An insertion clears the filter first when this is YES (the default), so a row the user just added cannot be
 * invisible. It is cleared by the ADD doors (`-add:`, `-addObject:`, `-addObjects:`, `-insert:`), not by
 * `-insertObject:atArrangedObjectIndex:`, whose index would change meaning under the caller's feet. */
- (BOOL)clearsFilterPredicateOnInsertion;
- (void)setClearsFilterPredicateOnInsertion:(BOOL)flag;

/* THE LIVE-REARRANGEMENT PAIR: stored and answered, with no reader here — see the header block's OWED note. */
- (nullable NSArray *)automaticRearrangementKeyPaths;
- (BOOL)automaticallyRearrangesObjects;
- (void)setAutomaticallyRearrangesObjects:(BOOL)flag;

/* THE TWO DOORS A CALLER USES INSTEAD: `-rearrangeObjects` rebuilds from the content as it stands (and re-applies
 * the selection policy); `-didChangeArrangementCriteria` is the same door under the name Apple gives the hook. */
- (void)rearrangeObjects;
- (void)didChangeArrangementCriteria;

/* ---- THE SELECTION ------------------------------------------------------------------------------------------ */

/* THE INDEXES INTO `arrangedObjects`. `-selectionIndex` is the FIRST one (NSNotFound when empty).
 * `-setSelectionIndex:` with NSNotFound empties the selection; an index past the end raises `NSRangeException`. */
- (NSUInteger)selectionIndex;
- (void)setSelectionIndex:(NSUInteger)index;
- (NSIndexSet *)selectionIndexes;
- (void)setSelectionIndexes:(NSIndexSet *)indexes;

/* The union and the difference, validated the same way `-setSelectionIndexes:` validates. */
- (void)addSelectionIndexes:(NSIndexSet *)indexes;
- (void)removeSelectionIndexes:(NSIndexSet *)indexes;

/* **THE SELECTED OBJECTS ARE THE ARRANGEMENT SUBSET**, which is the base class's `-selectedObjects` narrowed: the
 * selection proxy inherited from `NSObjectController` needs no change, because it asks this door. */
- (NSArray *)selectedObjects;
- (void)setSelectedObjects:(NSArray *)objects;

/* The first/last object in the arrangement, for a keyboard's Up and Down. With no selection they choose the first and
 * the last object; `-canSelectNext`/`-canSelectPrevious` are the guarded questions the actions check. */
- (BOOL)canSelectNext;
- (BOOL)canSelectPrevious;
- (void)selectNext:(nullable id)sender;
- (void)selectPrevious:(nullable id)sender;

/* ---- ADDING AND REMOVING ------------------------------------------------------------------------------------ */

/* THE INSERTION DOORS. `-insertObject:atArrangedObjectIndex:` takes an ARRANGED position (an index equal to the
 * arrangement's count appends); `-insertObjects:atArrangedObjectIndexes:` places each object immediately before the
 * object that was at its index, and inserts from the highest content index down so an earlier insertion cannot move a
 * later anchor. Both select what they insert when `selectsInsertedObjects` says so. */
- (BOOL)canInsert;
- (void)insert:(nullable id)sender;
- (void)insertObject:(id)object atArrangedObjectIndex:(NSUInteger)index;
- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexes:(NSIndexSet *)indexes;

/* THE BULK AND SELECTION FORMS. `-addObject:`/`-removeObject:` are the base class's through the arrangement (declared
 * here because Apple declares them and because their EFFECT is now "and the selection follows"); the plural forms are
 * one selection change rather than one per object. `-addSelectedObjects:` adds the selected objects through
 * `-addObject:` — it is the door for a selection that came from another controller. */
- (void)add:(nullable id)sender;
- (void)addObject:(id)object;
- (void)addObjects:(NSArray *)objects;
- (void)addSelectedObjects:(nullable id)sender;
- (void)remove:(nullable id)sender;
- (void)removeObject:(id)object;
- (void)removeObjects:(NSArray *)objects;
- (void)removeSelectedObjects:(nullable id)sender;
- (void)removeObjectAtArrangedObjectIndex:(NSUInteger)index;
- (void)removeObjectsAtArrangedObjectIndexes:(NSIndexSet *)indexes;

/* ---- THE POLICY --------------------------------------------------------------------------------------------- */

- (BOOL)preservesSelection;
- (void)setPreservesSelection:(BOOL)flag;
- (BOOL)selectsInsertedObjects;
- (void)setSelectsInsertedObjects:(BOOL)flag;
- (BOOL)avoidsEmptySelection;
- (void)setAvoidsEmptySelection:(BOOL)flag;
- (BOOL)alwaysUsesMultipleValuesMarker;
- (void)setAlwaysUsesMultipleValuesMarker:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSARRAYCONTROLLER_H */
