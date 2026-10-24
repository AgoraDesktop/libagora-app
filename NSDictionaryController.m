/*
 * NSDictionaryController.m — the key/value projection, one live pair per key, and the visible-key rules.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE ARRANGEMENT'S INPUT IS THE ONE DOOR A DICTIONARY SUBCLASS HAS TO CHANGE.** Everything else — the sorted and
 * filtered arrangement, the selection into it, the arrow keys, the policy flags — is `NSArrayController`'s, and it works
 * unchanged because a pair is an object like any other. `-fn_contentObjects` answers the PAIRS for the visible keys, and
 * the base class does the rest.
 *
 * **ONE PAIR PER KEY, KEPT.** The pair objects are cached by key, so a table's row is the same object across a rebuild.
 * That is not an optimisation: the base class's settle step re-finds the selection by IDENTITY (`-indexOfObjectIdenticalTo:`),
 * because two equal model objects are two rows; a controller that minted a fresh pair per rebuild would lose the
 * selection on every content change and would make `-setSelectedObjects:` unable to find the row a caller is holding.
 */
#import <AppKit/NSDictionaryController.h>
#import <AppKit/NSArrayController_internal.h>
#import <AppKit/NSObjectController_internal.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>

/* ---- THE DOORS THE PAIR CALLS, PRIVATE TO THIS FILE ---------------------------------------------------------- */

@interface NSDictionaryController (AGPairSeam)
- (id)fn_pairValueForKey:(id)key;
- (void)fn_setPairValue:(id)value forKey:(id)key;
- (id)fn_renameKey:(id)oldKey to:(id)newKey;
- (id)fn_localizedKeyForKey:(id)key;
@end

/* ---- THE PAIR ------------------------------------------------------------------------------------------------ */

/* **THREE NAMES ARE THE CONTRACT; THE CLASS IS NOT.** `key`, `value` and `localizedKey` are what a column binds to and
 * what the arrangement sorts and filters on, and Apple's own pair class is private, so this one is too. A pair is LIVE:
 * attached to its controller it reads and writes the content dictionary through it, and only a pair that has not been
 * added yet (`-newObject`'s answer) keeps a value of its own. */
@interface FNDictionaryPair : NSObject
{
	__unsafe_unretained NSDictionaryController *_controller;	/* nil while detached; NOT retained either way */
	id _key;						/* RETAINED (copied by the setters) */
	id _value;						/* RETAINED, and used ONLY while detached */
}
- (id)initDetachedWithKey:(id)key value:(id)value;
- (id)initWithController:(NSDictionaryController *)controller key:(id)key;
- (void)fn_attachToController:(NSDictionaryController *)controller;
@end

@implementation FNDictionaryPair

- (id)initDetachedWithKey:(id)key value:(id)value
{
	self = [super init];
	if (self != nil) {
		_key = [key copy];
		_value = [value retain];
	}
	return self;
}

- (id)initWithController:(NSDictionaryController *)controller key:(id)key
{
	self = [super init];
	if (self != nil) {
		_controller = controller;
		_key = [key copy];
	}
	return self;
}

- (void)dealloc
{
	[_key release];
	[_value release];
	[super dealloc];
}

- (void)fn_attachToController:(NSDictionaryController *)controller
{
	_controller = controller;
	[_value release];
	_value = nil;		/* the content is the value now; a detached copy would be a second truth */
}

- (id)key
{
	return _key;
}

- (void)setKey:(id)key
{
	if (_controller != nil) {
		id renamed = [_controller fn_renameKey:_key to:key];

		[renamed retain];
		[_key release];
		_key = renamed;
		return;
	}
	key = [key copy];
	[_key release];
	_key = key;
}

- (id)value
{
	if (_controller != nil) {
		return [_controller fn_pairValueForKey:_key];
	}
	return _value;
}

- (void)setValue:(id)value
{
	if (_controller != nil) {
		[_controller fn_setPairValue:value forKey:_key];
		return;
	}
	[value retain];
	[_value release];
	_value = value;
}

- (id)localizedKey
{
	if (_controller != nil) {
		return [_controller fn_localizedKeyForKey:_key];
	}
	return _key;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@: key %@ = %@>", [self class], _key, [self value]];
}

@end

/* ---- THE CONTROLLER ------------------------------------------------------------------------------------------ */

@implementation NSDictionaryController

+ (void)initialize
{
	static NSString * const bindings[] = {
		@"includedKeys", @"excludedKeys", @"initialKey", @"initialValue",
		@"localizedKeyDictionary", @"localizedKeyTable",
	};
	NSUInteger i;

	if (self != [NSDictionaryController class]) {
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
		_pairs = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_pairs release];
	[_includedKeys release];
	[_excludedKeys release];
	[_localizedKeyDictionary release];
	[_localizedKeyTable release];
	[_initialKey release];
	[_initialValue release];
	[super dealloc];
}

/* ---- THE CONTENT, AND THE KEYS THAT ARE VISIBLE ------------------------------------------------------ */

/* **THE CONTENT KIND, ANSWERED FOR THIS CLASS.** The inherited setter validates before it stores, so the only thing a
 * dictionary controller has to say is which kinds it arranges — and the refusal names that phrase. */
- (BOOL)fn_acceptsContent:(id)content
{
	return (content == nil || [content isKindOfClass:[NSDictionary class]]);
}

- (NSString *)fn_contentRule
{
	return @"a dictionary";
}

/* **A DICTIONARY OR NOTHING.** Any other content is a caller using the wrong class, and an empty list of rows is the
 * worst way to say so — the same rule, and the same raise, the array controller states for a non-collection. */
- (NSDictionary *)fn_contentDictionary
{
	id content = [self content];

	if (content == nil) {
		return nil;
	}
	if (![content isKindOfClass:[NSDictionary class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"NSDictionaryController content must be a dictionary; this controller's content is a %@",
				   [content class]];
	}
	return content;
}

- (NSMutableDictionary *)fn_mutableContent
{
	NSDictionary *content = [self fn_contentDictionary];

	if (![content isKindOfClass:[NSMutableDictionary class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"this dictionary controller's content is immutable (a %@), so it cannot be changed",
				   [content class]];
	}
	return (NSMutableDictionary *)content;
}

/* **INCLUDED FIRST, THEN EXCLUDED.** A non-nil included set limits the arrangement to those keys; the excluded set is
 * then subtracted from whatever survived, so a key in both is hidden. */
- (NSArray *)fn_visibleKeys
{
	NSDictionary *content = [self fn_contentDictionary];
	NSMutableArray *keys = [NSMutableArray array];
	NSEnumerator *enumerator;
	id key;

	if (content == nil) {
		return keys;
	}
	enumerator = [content keyEnumerator];
	while ((key = [enumerator nextObject]) != nil) {
		if (_includedKeys != nil && ![_includedKeys containsObject:key]) {
			continue;
		}
		if (_excludedKeys != nil && [_excludedKeys containsObject:key]) {
			continue;
		}
		[keys addObject:key];
	}
	return keys;
}

/* THE ARRANGEMENT'S INPUT: one pair per visible key, from the cache so the object is stable. */
- (NSArray *)fn_contentObjects
{
	NSArray *keys = [self fn_visibleKeys];
	NSMutableArray *pairs = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [keys count]; i++) {
		[pairs addObject:[self fn_pairForKey:[keys objectAtIndex:i]]];
	}
	return pairs;
}

- (FNDictionaryPair *)fn_pairForKey:(id)key
{
	FNDictionaryPair *pair = [_pairs objectForKey:key];

	if (pair == nil) {
		pair = [[[FNDictionaryPair alloc] initWithController:self key:key] autorelease];
		[_pairs setObject:pair forKey:key];
	}
	return pair;
}

/* ---- THE PAIR'S OWN DOORS ---------------------------------------------------------------------------- */

- (id)fn_pairValueForKey:(id)key
{
	return [[self fn_contentDictionary] objectForKey:key];
}

- (id)fn_localizedKeyForKey:(id)key
{
	id localized = [_localizedKeyDictionary objectForKey:key];

	return (localized != nil) ? localized : key;
}

/* **A MUTATION ANNOUNCES `content` AND THE ARRANGEMENT.** A dictionary has no to-many change kind, so a setting change
 * is the honest report that the (same) content object's entries moved; the derived pair then tells the arrangement and
 * the selection, exactly as it does for the base class's own mutations. */
- (void)fn_assignValue:(id)value forKey:(id)key
{
	NSMutableDictionary *content;

	if (key == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"a dictionary controller's pair needs a key; nil is not one"];
	}
	content = [self fn_mutableContent];
	[self willChangeValueForKey:@"content"];
	[self fn_willChangeDerivedKeys];
	if (value != nil) {
		[content setObject:value forKey:key];
	} else {
		[content removeObjectForKey:key];
	}
	[self fn_didChangeDerivedKeys];
	[self didChangeValueForKey:@"content"];
}

- (void)fn_setPairValue:(id)value forKey:(id)key
{
	[self fn_assignValue:value forKey:key];
}

- (void)fn_removeKey:(id)key
{
	NSMutableDictionary *content;

	if (key == nil || [[self fn_contentDictionary] objectForKey:key] == nil) {
		return;		/* nothing there is not an error, and it is not a change */
	}
	content = [self fn_mutableContent];
	[self willChangeValueForKey:@"content"];
	[self fn_willChangeDerivedKeys];
	[content removeObjectForKey:key];
	[self fn_didChangeDerivedKeys];
	[self didChangeValueForKey:@"content"];
	/* THE CACHE ENTRY GOES AFTER THE ANNOUNCEMENTS: the settle step has already re-found the selection, so a pair the
	 * caller still holds stays alive with its holder and simply reads nil, which is what a removed key is. */
	[_pairs removeObjectForKey:key];
}

/* **A RENAME IS A REMOVE AND AN INSERT, ANNOUNCED ONCE.** The value is read before the removal, so renaming a key to
 * one that already exists overwrites it the way an assignment would. */
- (id)fn_renameKey:(id)oldKey to:(id)newKey
{
	NSMutableDictionary *content;
	id value;

	if (newKey == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"a dictionary controller's pair needs a key; nil is not one"];
	}
	if ([newKey isEqual:oldKey]) {
		return oldKey;
	}
	value = [[self fn_contentDictionary] objectForKey:oldKey];
	content = [self fn_mutableContent];
	[self willChangeValueForKey:@"content"];
	[self fn_willChangeDerivedKeys];
	[content removeObjectForKey:oldKey];
	if (value != nil) {
		[content setObject:value forKey:newKey];
	}
	[self fn_didChangeDerivedKeys];
	[self didChangeValueForKey:@"content"];
	{
		FNDictionaryPair *pair = [[_pairs objectForKey:oldKey] retain];

		[_pairs removeObjectForKey:oldKey];
		if (pair != nil) {
			[_pairs setObject:pair forKey:newKey];
			[pair release];
		}
	}
	return newKey;
}

/* ---- THE ADDING AND REMOVING DOORS ------------------------------------------------------------------- */

- (BOOL)canAdd
{
	id content = [self content];

	return (content == nil || [content isKindOfClass:[NSMutableDictionary class]]);
}

- (BOOL)canRemove
{
	id content = [self content];

	return ([content isKindOfClass:[NSMutableDictionary class]] && [(NSDictionary *)content count] != 0);
}

- (id)newObject
{
	return [[[FNDictionaryPair alloc] initDetachedWithKey:_initialKey value:_initialValue] autorelease];
}

- (void)addObject:(id)object
{
	FNDictionaryPair *pair;
	id key;
	id value;

	if (![object isKindOfClass:[FNDictionaryPair class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-addObject: takes the key/value pair -newObject answers, not a %@", [object class]];
	}
	pair = (FNDictionaryPair *)object;
	key = [pair key];
	if (key == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-addObject: cannot add a pair with no key; set -initialKey or the pair's key first"];
	}
	/* **THE CACHE TAKES THE PAIR BEFORE THE CONTENT TAKES THE VALUE**, so the arrangement the assignment rebuilds
	 * already holds THIS object and `selectsInsertedObjects` can select it by identity. The value is read while the pair
	 * is still detached, because once it is attached it reads the content — which does not have the key yet. */
	value = [pair value];
	[_pairs setObject:pair forKey:key];
	[pair fn_attachToController:self];
	[self fn_assignValue:value forKey:key];
	if ([self selectsInsertedObjects]) {
		[self setSelectedObjects:[NSArray arrayWithObject:pair]];
	}
}

- (void)addObjects:(NSArray *)objects
{
	NSMutableArray *added = [NSMutableArray array];
	NSUInteger i;

	if (objects == nil) {
		[NSException raise:NSInvalidArgumentException format:@"-addObjects: needs an array; nil is not one"];
	}
	for (i = 0; i < [objects count]; i++) {
		id object = [objects objectAtIndex:i];

		[self addObject:object];
		[added addObject:object];
	}
	if ([self selectsInsertedObjects] && [added count] > 1) {
		[self setSelectedObjects:added];	/* one selection for the batch, not one per object */
	}
}

/* A DICTIONARY HAS NO ORDER: the index is accepted for the API's sake and has no effect, which the header says. */
- (void)insertObject:(id)object atArrangedObjectIndex:(NSUInteger)index
{
	(void)index;
	[self addObject:object];
}

- (void)insertObjects:(NSArray *)objects atArrangedObjectIndexes:(NSIndexSet *)indexes
{
	NSUInteger i;

	if (objects == nil || indexes == nil || [objects count] != [indexes count]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-insertObjects:atArrangedObjectIndexes: takes one index for each object"];
	}
	for (i = 0; i < [objects count]; i++) {
		[self addObject:[objects objectAtIndex:i]];
	}
}

- (void)removeObject:(id)object
{
	if (![object isKindOfClass:[FNDictionaryPair class]]) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-removeObject: takes a key/value pair, not a %@", [object class]];
	}
	[self fn_removeKey:[(FNDictionaryPair *)object key]];
}

/* ---- THE VISIBLE-KEY SETS AND THE NAMES -------------------------------------------------------------- */

- (NSArray *)includedKeys
{
	return _includedKeys;
}

- (void)setIncludedKeys:(NSArray *)keys
{
	if (keys == _includedKeys || [keys isEqual:_includedKeys]) {
		return;
	}
	/* **THE CRITERIA PAIR BRACKETS THE STORE.** `-rearrangeObjects` would announce an arrangement it had already
	 * rebuilt; this pair captures the old selection and drops the cache BEFORE the field is assigned, so the Old side of
	 * the announcement is the arrangement that was there. */
	[self fn_willChangeCriteriaKeys];
	[_includedKeys release];
	_includedKeys = [keys copy];
	[self fn_didChangeCriteriaKeys];
}

- (NSArray *)excludedKeys
{
	return _excludedKeys;
}

- (void)setExcludedKeys:(NSArray *)keys
{
	if (keys == _excludedKeys || [keys isEqual:_excludedKeys]) {
		return;
	}
	[self fn_willChangeCriteriaKeys];
	[_excludedKeys release];
	_excludedKeys = [keys copy];
	[self fn_didChangeCriteriaKeys];
}

- (NSDictionary *)localizedKeyDictionary
{
	return _localizedKeyDictionary;
}

- (void)setLocalizedKeyDictionary:(NSDictionary *)dictionary
{
	if (dictionary == _localizedKeyDictionary || [dictionary isEqual:_localizedKeyDictionary]) {
		return;
	}
	/* A sort descriptor may name `localizedKey`, so the names ARE an arrangement criterion. */
	[self fn_willChangeCriteriaKeys];
	[_localizedKeyDictionary release];
	_localizedKeyDictionary = [dictionary copy];
	[self fn_didChangeCriteriaKeys];
}

- (NSString *)localizedKeyTable
{
	return _localizedKeyTable;
}

- (void)setLocalizedKeyTable:(NSString *)table
{
	if (table == _localizedKeyTable || [table isEqual:_localizedKeyTable]) {
		return;
	}
	/* STORED AND ANSWERED; NOTHING LOADS IT. This Foundation has no `.strings` reader — the same withdrawal
	 * `NSRuleEditor`'s `-setFormattingStringsFilename:` refuses by name — so `localizedKeyDictionary` is the only
	 * source of a displayed name here. */
	[_localizedKeyTable release];
	_localizedKeyTable = [table copy];
}

- (id)initialKey
{
	return _initialKey;
}

- (void)setInitialKey:(id)key
{
	[key retain];
	[_initialKey release];
	_initialKey = key;
}

- (id)initialValue
{
	return _initialValue;
}

- (void)setInitialValue:(id)value
{
	[value retain];
	[_initialValue release];
	_initialValue = value;
}

@end
