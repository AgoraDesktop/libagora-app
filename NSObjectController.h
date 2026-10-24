/*
 * NSObjectController.h — a controller over one object, or over a collection whose every object is selected.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CONTROLLER IS A KVO CLIENT AND A KVC CITIZEN, AND THAT IS THE WHOLE OF ITS JOB.** Its `content` is a value
 * like any other: a binding can write it (`-bind:toObject:withKeyPath:options:` on an `NSObjectController` is how a
 * master/detail arrangement is built), KVO can observe it, and the controller derives `contentObject`, `selection`,
 * `selectedObjects`, `canAdd` and `canRemove` from it. Every one of those derivations is ANNOUNCED as a dependent of
 * `content`, so a view bound to `selection.name` hears about a new content object without the controller knowing the
 * view exists.
 *
 * **THE CONTENT'S KIND DECIDES WHAT THE CONTROLLER IS.** A content that is an `NSArray` or an `NSSet` — mutable or
 * not — is a COLLECTION, and every object in it is selected; that is what `NSObjectController` means by a selection,
 * and `NSArrayController` is the subclass that narrows it with `selectionIndexes` into `arrangedObjects`. Anything
 * else is a SINGLE OBJECT and is the selection itself. nil is neither: nothing is selected and nothing is shown.
 *
 * **THE SELECTION IS A REAL PROXY, WITH APPLE'S AGREEMENT RULE.** `-selection` answers one object per controller that
 * forwards KVC to the selected objects:
 *
 *   * one object selected — the value (and the write) goes straight through to it;
 *   * several selected — a read answers the value when EVERY selected object agrees on it, and
 *     `NSMultipleValuesMarker` when they do not; a write goes to every selected object;
 *   * none selected — a read answers `NSNoSelectionMarker`, and a write RAISES, because there is nothing to write to
 *     and a silent success would be a lie;
 *   * a key none of the selected objects has — `NSNotApplicableMarker`, which is what that marker is for.
 *
 * That is the multi-value question `HANDOFF-7.md` §6 left open, answered here: the first slice does the agreement
 * check rather than handing the whole selection one marker, because the check is four lines and a form bound to a
 * multiple selection is the common case.
 *
 * **ADDING AND REMOVING IS DEFINED AGAINST THE CONTENT'S KIND, AND SAYS SO.** `-canAdd` is YES when the content is
 * nil (a first object makes a collection), an `NSMutableArray`, or an `NSMutableSet`; `-canRemove` is YES when one of
 * those collections actually holds something. `-addObject:` on nil content makes a one-object `NSMutableArray`;
 * `-removeObject:` on nil content is a no-op, because nothing there is not an error. **A single object is not a
 * collection**, so both questions answer NO and a caller that ignores them and asks to add or remove anyway gets an
 * `NSInvalidArgumentException` naming the reason — refused loudly rather than ignored.
 *
 * **`-newObject` IS THE CLASS THE CONTROLLER IS TOLD ABOUT.** `-objectClass` defaults to `NSMutableDictionary`, which
 * is what a detail form edits; `-newObject` is a fresh instance of it. `-prepareContent` fills a nil content with one
 * `-newObject`, and `-automaticallyPreparesContent` makes `-setContent:` do that by itself. The default is NO: a
 * controller that invented content a caller had just set to nil would be deciding what the caller meant.
 *
 * **CORE DATA IS REFUSED BY NAME, NOT APPROXIMATED.** `managedObjectContext`, `entityName`, `fetchPredicate`,
 * `usesLazyFetching`, `defaultFetchRequest`, `fetch:` and `fetchWithRequest:merge:error:` all print
 * `APPKIT-REFUSE` and answer their type's empty value. The reason is not that this tier lacks Core Data — it has a
 * store and `NSPersistentDocument` — but that a controller's fetch loop (live result sets, lazy faults, merge
 * policy) is a different piece of machinery, and a stub that fetched once and called it live would be worse than a
 * refusal. The useful eighty percent — content, selection, add/remove, bindings — is real.
 */
#ifndef APPKIT_NSOBJECTCONTROLLER_H
#define APPKIT_NSOBJECTCONTROLLER_H

#import <AppKit/NSController.h>
#import <AppKit/NSUserInterfaceValidation.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSError;
@class NSFetchRequest;
@class NSSet;
@class NSString;

@interface NSObjectController : NSController <NSUserInterfaceValidations>
{
	id _content;				/* RETAINED: the object or collection this controller stands for */
	Class _objectClass;			/* NOT retained: a class object is immortal */
	id _selection;				/* RETAINED: the proxy `-selection` hands out, made on first ask */
	BOOL _editable;				/* stored; YES by default */
	BOOL _automaticallyPreparesContent;	/* stored; NO by default */
}

/* THE DESIGNATED INITIALISER, and the plain one is `-initWithContent:nil`. The content is RETAINED, not copied. */
- (instancetype)initWithContent:(nullable id)content;

/* ---- CONTENT ------------------------------------------------------------------------------------------------ */

- (nullable id)content;
- (void)setContent:(nullable id)content;

/* THE ONE OBJECT THIS CONTROLLER STANDS FOR: the content itself when it is a single object; the single selected
 * object when it is a collection; `NSMultipleValuesMarker` when a collection holds several; `NSNoSelectionMarker`
 * when a collection is empty; nil when there is no content at all. */
- (nullable id)contentObject;

/* ---- SELECTION ---------------------------------------------------------------------------------------------- */

/* THE PROXY described in the header block. It is the same object for the controller's whole life, so a binding or a
 * caller can hold it across content changes. */
- (id)selection;

/* The selected objects as an array: every object of a collection content, the content itself for a single object,
 * empty when there is no content. */
- (NSArray *)selectedObjects;

/* ---- MAKING AND ADDING -------------------------------------------------------------------------------------- */

/* THE CLASS `-newObject` INSTANTIATES. Default `NSMutableDictionary`; a nil class RAISES rather than leaving the
 * controller answering nothing forever, which is why the parameter is nullable in this declaration — the door takes
 * the argument and refuses it, rather than promising it will not arrive. */
- (Class)objectClass;
- (void)setObjectClass:(nullable Class)objectClass;
- (id)newObject;

/* `-prepareContent` acts only when the content is nil: it sets one `-newObject` as the content. */
- (void)prepareContent;
- (BOOL)automaticallyPreparesContent;
- (void)setAutomaticallyPreparesContent:(BOOL)flag;

/* THE TWO QUESTIONS THE MENU ITEMS AND `-validateUserInterfaceItem:` ARE BUILT ON, and the two pairs of doors.
 * `-add:` is `-newObject` plus `-addObject:`; `-remove:` removes every selected object. See the header block for the
 * collection rules and for what a call the questions said NO to does. */
- (BOOL)canAdd;
- (BOOL)canRemove;
- (void)add:(nullable id)sender;
- (void)addObject:(id)object;
- (void)remove:(nullable id)sender;
- (void)removeObject:(id)object;

/* ---- EDITING AND VALIDATION --------------------------------------------------------------------------------- */

- (BOOL)isEditable;
- (void)setEditable:(BOOL)flag;

/* add:/remove: answer their own questions; every other action is YES (the target/action machinery this controller
 * does not own decides those). */
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem;

/* ---- CORE DATA, REFUSED BY NAME ---------------------------------------------------------- */

/* Every one of these prints `APPKIT-REFUSE` and answers its type's empty value: nil for the four object getters,
 * NO for `-usesLazyFetching` and the two fetch doors. The setters take their argument and refuse it. */
- (nullable id)managedObjectContext;
- (void)setManagedObjectContext:(nullable id)managedObjectContext;
- (nullable NSString *)entityName;
- (void)setEntityName:(nullable NSString *)entityName;
- (nullable id)fetchPredicate;
- (void)setFetchPredicate:(nullable id)fetchPredicate;
- (BOOL)usesLazyFetching;
- (void)setUsesLazyFetching:(BOOL)flag;
- (nullable NSFetchRequest *)defaultFetchRequest;
- (BOOL)fetch:(nullable id)sender;
- (BOOL)fetchWithRequest:(nullable NSFetchRequest *)fetchRequest
		   merge:(BOOL)merge
		   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSOBJECTCONTROLLER_H */
