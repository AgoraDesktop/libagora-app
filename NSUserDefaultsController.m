/*
 * NSUserDefaultsController.m — the values proxy, the three-level read, and the pending store.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE VALUES PROXY HOLDS NOTHING AND ASKS THE CONTROLLER FOR EVERYTHING.** It is one object per controller, so a
 * binding or a caller can hold it across writes, and its two KVC doors call the controller's own read/write chain —
 * which is the only place the three-level fallback and the pending store are decided. A proxy with its own copy of the
 * values would be a second source of truth for the same settings, and the first bug would be a stale one.
 *
 * **THE `values.` KEY PATH IS INTERCEPTED IN TWO PLACES, AND THEY ARE DIFFERENT PLACES ON PURPOSE.** KVC's single-key
 * doors (`-valueForKey:`/`-setValue:forKey:`) answer the prefix directly, because that is how a caller who already has
 * `"values.fontSize"` in one string (the binding layer does) reaches the store. KVO's registration doors are
 * intercepted separately, because this Foundation keeps a registration keyed by the STRING it was given and does not
 * walk a path: a `values.fontSize` observation is registered on the STORE under `fontSize`, where the store's own
 * announcements (landed in `libagora-base` for exactly this) deliver correct Old and New values.
 */
#import <AppKit/NSUserDefaultsController.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSUserDefaults.h>

/* `values.` AND ONE SEGMENT: the bare key, or nil when the path is not this controller's. A key that itself contains
 * a dot cannot be spelled as a path here, and the two doors below say so rather than half-resolving it. */
static NSString *fn_values_key(NSString *keyPath)
{
	static NSString * const prefix = @"values.";
	NSString *key;

	if (keyPath == nil || ![keyPath hasPrefix:prefix]) {
		return nil;
	}
	key = [keyPath substringFromIndex:[prefix length]];
	if ([key length] == 0) {
		return nil;
	}
	if ([key rangeOfString:@"."].location != NSNotFound) {
		[NSException raise:NSInvalidArgumentException
			    format:@"\"%@\" is a key path below a defaults key; this Foundation's KVO does not decompose "
				   "key paths, so observe \"values.<key>\" (one segment) and reach a dotted key through "
				   "-values", keyPath];
	}
	return key;
}

/* ---- THE PROXY ---------------------------------------------------------------------------------------------- */

/* THE CONTROLLER'S READ/WRITE CHAIN, PRIVATE TO THIS FILE: the proxy calls it and no caller should. It is a category
 * rather than an internal header because nothing outside this implementation file may name it. */
@interface NSUserDefaultsController (AGValuesChain)
- (id)fn_valueForKey:(NSString *)key;
- (void)fn_setValue:(id)value forKey:(NSString *)key;
@end

@interface FNUserDefaultsValues : NSObject
{
	__unsafe_unretained NSUserDefaultsController *_controller;	/* NOT retained: the controller owns the proxy */
}
- (id)initWithController:(NSUserDefaultsController *)controller;
@end

@implementation FNUserDefaultsValues

- (id)initWithController:(NSUserDefaultsController *)controller
{
	self = [super init];
	if (self != nil) {
		_controller = controller;
	}
	return self;
}

- (id)valueForKey:(NSString *)key
{
	return [_controller fn_valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
	[_controller fn_setValue:value forKey:key];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<values proxy of a %@>", [_controller class]];
}

@end

/* ---- THE CONTROLLER ----------------------------------------------------------------------------------------- */

@implementation NSUserDefaultsController

static NSUserDefaultsController *fn_shared_defaults_controller = nil;

+ (NSUserDefaultsController *)sharedUserDefaultsController
{
	if (fn_shared_defaults_controller == nil) {
		fn_shared_defaults_controller = [[NSUserDefaultsController alloc] init];
	}
	return fn_shared_defaults_controller;
}

- (id)init
{
	return [self initWithDefaults:[NSUserDefaults standardUserDefaults] initialValues:nil];
}

- (id)initWithDefaults:(NSUserDefaults *)defaults initialValues:(NSDictionary *)initialValues
{
	self = [super init];
	if (self != nil) {
		_defaults = [(defaults != nil ? defaults : [NSUserDefaults standardUserDefaults]) retain];
		_initialValues = [initialValues copy];
		_pending = [[NSMutableDictionary alloc] init];
		_appliesImmediately = YES;
	}
	return self;
}

- (void)dealloc
{
	[_defaults release];
	[_initialValues release];
	[_pending release];
	[_values release];
	[super dealloc];
}

- (NSUserDefaults *)defaults
{
	return _defaults;
}

- (NSDictionary *)initialValues
{
	return _initialValues;
}

- (void)setInitialValues:(NSDictionary *)initialValues
{
	if (initialValues == _initialValues || [initialValues isEqual:_initialValues]) {
		return;
	}
	[_initialValues release];
	_initialValues = [initialValues copy];	/* a caller's mutable dictionary must not steer the fallback */
}

- (id)values
{
	if (_values == nil) {
		_values = [[FNUserDefaultsValues alloc] initWithController:self];
	}
	return _values;
}

/* ---- THE READ AND WRITE CHAIN ------------------------------------------------------------------------ */

/* **PENDING, THEN THE STORE, THEN THE INITIAL VALUES.** NSNull in the pending dictionary is a pending REMOVAL: the
 * key is being taken out of the store, so the read must not fall through to the store's old value, but to the initial
 * values. */
- (id)fn_valueForKey:(NSString *)key
{
	id held;

	if (key == nil) {
		[NSException raise:NSInvalidArgumentException format:@"a defaults key must be a string, not nil"];
	}
	held = [_pending objectForKey:key];
	if (held != nil) {
		return (held == [NSNull null]) ? [_initialValues objectForKey:key] : held;
	}
	held = [_defaults objectForKey:key];
	if (held != nil) {
		return held;
	}
	return [_initialValues objectForKey:key];
}

- (void)fn_setValue:(id)value forKey:(NSString *)key
{
	if (key == nil) {
		[NSException raise:NSInvalidArgumentException format:@"a defaults key must be a string, not nil"];
	}
	if (_appliesImmediately) {
		[_defaults setValue:value forKey:key];	/* the store's own door: one announcement, from the store */
		return;
	}
	{
		/* A PENDING WRITE IS NOT A STORE CHANGE, so the only key that moves is `hasUnappliedChanges`, and only when
		 * it crosses from "nothing held" to "something held". */
		BOOL wasPending = [self hasUnappliedChanges];

		if (!wasPending) {
			[self willChangeValueForKey:@"hasUnappliedChanges"];
		}
		[_pending setObject:(value != nil ? value : (id)[NSNull null]) forKey:key];
		if (!wasPending) {
			[self didChangeValueForKey:@"hasUnappliedChanges"];
		}
	}
}

/* THE `values.` SPELLING, IN BOTH DIRECTIONS. A key path that is exactly `values` answers the proxy; `values.<key>`
 * is the store's key through the same chain; anything else is the controller's own business and goes to `super`. */
- (id)valueForKey:(NSString *)key
{
	NSString *defaultsKey;

	if ([key isEqual:@"values"]) {
		return [self values];
	}
	defaultsKey = fn_values_key(key);
	if (defaultsKey != nil) {
		return [self fn_valueForKey:defaultsKey];
	}
	return [super valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
	NSString *defaultsKey = fn_values_key(key);

	if (defaultsKey != nil) {
		[self fn_setValue:value forKey:defaultsKey];
		return;
	}
	[super setValue:value forKey:key];
}

/* ---- KVO: A `values.` PATH IS THE STORE'S KEY -------------------------------------------------------- */

/* **THE REGISTRATION GOES TO THE STORE, NOT TO THIS CONTROLLER** — the store announces its own keys (a
 * `libagora-base` row), and it is the object whose value the change dictionary must describe. The alternative, keeping
 * a relay here, would have to synthesise a change after the store had already reported it, which cannot produce a
 * correct Old value. See the header for what the caller therefore sees as the change's object and key path. */
- (void)addObserver:(NSObject *)observer
	 forKeyPath:(NSString *)keyPath
	    options:(NSKeyValueObservingOptions)options
	    context:(void *)context
{
	NSString *defaultsKey = fn_values_key(keyPath);

	if (defaultsKey != nil) {
		[_defaults addObserver:observer forKeyPath:defaultsKey options:options context:context];
		return;
	}
	[super addObserver:observer forKeyPath:keyPath options:options context:context];
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
	NSString *defaultsKey = fn_values_key(keyPath);

	if (defaultsKey != nil) {
		[_defaults removeObserver:observer forKeyPath:defaultsKey];
		return;
	}
	[super removeObserver:observer forKeyPath:keyPath];
}

- (void)removeObserver:(NSObject *)observer
	    forKeyPath:(NSString *)keyPath
	       context:(void *)context
{
	NSString *defaultsKey = fn_values_key(keyPath);

	if (defaultsKey != nil) {
		[_defaults removeObserver:observer forKeyPath:defaultsKey context:context];
		return;
	}
	[super removeObserver:observer forKeyPath:keyPath context:context];
}

/* ---- THE APPLY POLICY -------------------------------------------------------------------------------- */

- (BOOL)appliesImmediately
{
	return _appliesImmediately;
}

- (void)setAppliesImmediately:(BOOL)flag
{
	if (flag == _appliesImmediately) {
		return;
	}
	_appliesImmediately = flag;
	if (flag) {
		/* THE MODE NOW SAYS "APPLY", so the writes it was holding are applied rather than stranded: nothing would
		 * ever flush them after this, because the pending store is only written when this flag is NO. */
		[self save:nil];
	}
}

- (BOOL)hasUnappliedChanges
{
	return [_pending count] != 0;
}

/* **THE FLUSH IS A SERIES OF STORE WRITES, ONE ANNOUNCEMENT EACH** — that is the point of it: a UI bound to
 * `values.<key>` hears the change when the write that produces it happens, not when the snapshot was taken. */
- (void)save:(id)sender
{
	NSDictionary *snapshot;
	NSEnumerator *keys;
	NSString *key;

	(void)sender;
	if ([_pending count] == 0) {
		return;
	}
	snapshot = [[_pending copy] autorelease];
	keys = [snapshot keyEnumerator];
	while ((key = [keys nextObject]) != nil) {
		id value = [snapshot objectForKey:key];

		[_defaults setValue:((value == [NSNull null]) ? nil : value) forKey:key];
	}
	{
		BOOL wasPending = [self hasUnappliedChanges];

		if (wasPending) {
			[self willChangeValueForKey:@"hasUnappliedChanges"];
		}
		[_pending removeAllObjects];
		if (wasPending) {
			[self didChangeValueForKey:@"hasUnappliedChanges"];
		}
	}
}

- (void)revert:(id)sender
{
	BOOL wasPending;

	(void)sender;
	wasPending = [self hasUnappliedChanges];
	if (!wasPending) {
		return;
	}
	[self willChangeValueForKey:@"hasUnappliedChanges"];
	[_pending removeAllObjects];
	[self didChangeValueForKey:@"hasUnappliedChanges"];
	/* NOTHING ELSE IS ANNOUNCED, AND THAT IS THE HONEST ANSWER: the store never changed, the pending writes were the
	 * only thing that had, and they are gone. A `values.` observer is registered on the store and is correctly silent. */
}

- (void)revertToInitialValues:(id)sender
{
	NSEnumerator *keys;
	NSString *key;

	(void)sender;
	/* THE PENDING WRITES GO FIRST: a reset button means "the initial values, not what I typed". */
	[self revert:nil];
	keys = [_initialValues keyEnumerator];
	while ((key = [keys nextObject]) != nil) {
		[_defaults setValue:[_initialValues objectForKey:key] forKey:key];
	}
}

@end
