/*
 * NSUserDefaultsController.h — a controller over a settings store, and the `values` proxy a binding names.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CONTROLLER IS A THIN LAYER OVER `NSUserDefaults`, AND `values` IS WHERE THE LAYER SHOWS.** The store is a
 * key/value bag with no properties, so the controller gives it one: `-values` answers a proxy whose KVC doors read and
 * write the store, and that is the object a binding names — `values.<key>` on the CONTROLLER is the same key on the
 * proxy, and `-valueForKey:`/`-setValue:forKey:` on the controller answer the `values.` spelling directly so a binding
 * layer that hands over one string (this one does) can use it.
 *
 * **A READ HAS THREE FALLBACKS, IN THIS ORDER, AND THE ORDER IS THE FEATURE.** The controller's own UNAPPLIED writes
 * come first (see below), then the store, then `initialValues` — the dictionary Apple documents as the value to use
 * "when the user defaults does not contain a value for the key". `-revertToInitialValues:` writes those values INTO the
 * store, which is what makes a Reset button a store write rather than a private state.
 *
 * **`appliesImmediately` DECIDES WHERE A WRITE GOES.** YES (the default) hands it to the store at once. NO keeps it in
 * the controller's pending dictionary and answers `-hasUnappliedChanges` YES until `-save:` flushes the pending keys
 * through the store or `-revert:` discards them; a read in that mode sees the pending value, so the UI shows the edit
 * before it is committed. Turning the flag back ON with pending writes applies them, because the mode then says so.
 *
 * **AND THE OBSERVATION BOUNDARY IS STATED RATHER THAN HIDDEN, BECAUSE THIS FOUNDATION'S KVO DOES NOT DECOMPOSE
 * PATHS.** `-addObserver:forKeyPath:@"values.fontSize"` is registered on the STORE with the bare key `fontSize`, so
 * the change dictionary's object is the store and its key path is the bare key; the New and Old values are correct,
 * which is what a binding reads. **A pending write does not notify a `values.` observer** — the store has not changed —
 * so a UI in that mode watches `-hasUnappliedChanges` on the controller instead, and `-save:` produces the store's
 * notifications. `initialValues` is a READ-TIME fallback and not part of the store, so a key only it supplies has no
 * change notification until something writes the key. A key path deeper than one segment under `values.` is refused by
 * name, because observing it would need the path decomposition this KVO has not got.
 */
#ifndef APPKIT_NSUSERDEFAULTSCONTROLLER_H
#define APPKIT_NSUSERDEFAULTSCONTROLLER_H

#import <AppKit/NSController.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSUserDefaults;

@interface NSUserDefaultsController : NSController
{
	NSUserDefaults *_defaults;	/* RETAINED: the store this controller speaks to */
	NSDictionary *_initialValues;	/* COPIED: the read-time fallback, and what -revertToInitialValues: writes */
	NSMutableDictionary *_pending;	/* RETAINED: unapplied writes; NSNull means "remove on save" */
	id _values;			/* RETAINED: the proxy -values answers */
	BOOL _appliesImmediately;
}

/* **THE PROCESS-WIDE ONE, OVER `+standardUserDefaults`.** Built on first ask and kept, which is Apple's contract: a
 * nib or a binding names it, so it has to be the same object every time. */
+ (NSUserDefaultsController *)sharedUserDefaultsController;

/* THE DESIGNATED INITIALISER. A nil store means `+standardUserDefaults`; a nil initial-values dictionary means none.
 * Both are RETAINED/COPIED as their headers say. */
- (instancetype)initWithDefaults:(nullable NSUserDefaults *)defaults
		   initialValues:(nullable NSDictionary *)initialValues;

- (NSUserDefaults *)defaults;

- (nullable NSDictionary *)initialValues;
- (void)setInitialValues:(nullable NSDictionary *)initialValues;

/* THE PROXY: one object per controller, the same one every time it is asked for, and the thing a binding's key path
 * starts with. Its KVC doors are the read/write chain described above. */
- (id)values;

/* ---- THE APPLY POLICY --------------------------------------------------------------------------------------- */

- (BOOL)appliesImmediately;
- (void)setAppliesImmediately:(BOOL)flag;

/* YES while writes are held in the controller. A pure question about the pending dictionary, announced when it
 * CROSSES — a second unapplied write is not a second change. */
- (BOOL)hasUnappliedChanges;

/* Flush the pending writes through the store (`-save:`), or discard them (`-revert:`). Both are actions, so both take
 * a sender; both are no-ops when nothing is pending. */
- (void)save:(nullable id)sender;
- (void)revert:(nullable id)sender;

/* Write every `initialValues` entry into the store, discarding any pending writes first. An action, like the other
 * two. */
- (void)revertToInitialValues:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSUSERDEFAULTSCONTROLLER_H */
