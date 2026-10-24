/*
 * NSDictionaryController.h — an array controller over a DICTIONARY, whose arranged objects are key/value pairs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CONTENT IS A DICTIONARY AND THE ARRANGEMENT IS A LIST OF PAIRS.** `NSArrayController` gives this class its
 * arrangement, its selection, its sort/filter descriptors and its policy flags; what a dictionary controller adds is the
 * PROJECTION — one pair per visible key, in the order the arrangement puts them. A pair is a small object with three
 * KVC-compliant properties (`key`, `value`, `localizedKey`), which is what a table's columns bind to; **the pair class
 * is private because Apple's is**, and the three names are the contract rather than the class.
 *
 * **A PAIR IS LIVE, AND THERE IS ONE PAIR PER KEY.** The controller keeps a pair for every key it has handed out, so a
 * pair reads and writes the content dictionary through the controller: `-setValue:` changes the dictionary's entry and
 * announces the arrangement, and `-setKey:` renames the entry. Two consequences a caller should rely on: a table's row
 * object stays THE SAME OBJECT across a rebuild (which is what lets `preservesSelection` keep the row selected by
 * identity, and lets `-setSelectedObjects:` find it), and a pair taken out of the content and put back is the same
 * object again.
 *
 * **`includedKeys` AND `excludedKeys` DECIDE WHAT IS VISIBLE, AND EXCLUDED WINS.** A non-nil `includedKeys` limits the
 * arrangement to those keys (intersected with the content's); `excludedKeys` then subtracts from whatever survived. The
 * sort descriptors and the filter predicate run AFTER that, over the pairs, so a predicate reads `key`, `value` or
 * `localizedKey`.
 *
 * **WHAT A DICTIONARY CANNOT DO, SAID AT THE DOOR.** A dictionary has no order, so
 * `-insertObject:atArrangedObjectIndex:` and its plural accept the index and IGNORE it: the pair's position is whatever
 * the arrangement gives it (the key order, or the sort descriptors). Adding a pair whose key is nil raises, because a
 * dictionary entry cannot have one. And **`localizedKeyTable` IS STORED AND NOTHING LOADS IT**: this Foundation withdrew
 * its `.strings` reader (the same withdrawal `NSRuleEditor`'s `-setFormattingStringsFilename:` refuses by name), so
 * `localizedKeyDictionary` is the only source of a localized name here and `-localizedKey` falls back to the key.
 */
#ifndef APPKIT_NSDICTIONARYCONTROLLER_H
#define APPKIT_NSDICTIONARYCONTROLLER_H

#import <AppKit/NSArrayController.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>

NS_ASSUME_NONNULL_BEGIN

@class NSSet;
@class NSString;

@interface NSDictionaryController : NSArrayController
{
	NSMutableDictionary *_pairs;		/* RETAINED: key -> the ONE pair object for that key */
	NSArray *_includedKeys;			/* COPIED: nil means "every key the content has" */
	NSArray *_excludedKeys;			/* COPIED: nil means "exclude nothing" */
	NSDictionary *_localizedKeyDictionary;	/* COPIED: key -> the name to display */
	NSString *_localizedKeyTable;		/* COPIED: stored; nothing loads a .strings file — see the header block */
	id _initialKey;				/* RETAINED: the key a new pair starts with */
	id _initialValue;			/* RETAINED: the value it starts with */
}

/* ---- WHAT IS VISIBLE ---------------------------------------------------------------------------------------- */

/* THE KEY SETS. `includedKeys` nil means every key; `excludedKeys` is subtracted after the inclusion. Setting either
 * one re-arranges (the announcement is the same criteria pair the base class's sort and filter setters use), and the
 * selection is re-found by identity, so the rows that survive stay selected. */
- (nullable NSArray *)includedKeys;
- (void)setIncludedKeys:(nullable NSArray *)keys;
- (nullable NSArray *)excludedKeys;
- (void)setExcludedKeys:(nullable NSArray *)keys;

/* ---- THE NAME A ROW SHOWS ----------------------------------------------------------------------------------- */

/* `localizedKeyDictionary` maps a key to the name to display; a key it does not name displays as itself. The table is
 * stored and answered, and **nothing loads it** — this Foundation has no `.strings` reader. */
- (nullable NSDictionary *)localizedKeyDictionary;
- (void)setLocalizedKeyDictionary:(nullable NSDictionary *)dictionary;
- (nullable NSString *)localizedKeyTable;
- (void)setLocalizedKeyTable:(nullable NSString *)table;

/* ---- THE PAIR `-add:` CREATES ------------------------------------------------------------------------------- */

/* The key and value a new pair starts with. `-newObject` answers a DETACHED pair (it is not in the content until it is
 * added), and adding it with a nil key raises. */
- (nullable id)initialKey;
- (void)setInitialKey:(nullable id)key;
- (nullable id)initialValue;
- (void)setInitialValue:(nullable id)value;

/* THE NEW PAIR: detached, carrying `initialKey` and `initialValue`, and becoming the live pair for its key when it is
 * added. Adding a pair whose key is nil raises `NSInvalidArgumentException`. */
- (id)newObject;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDICTIONARYCONTROLLER_H */
