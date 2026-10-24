/*
 * user_defaults_controller — the values proxy, the three-level read, and the pending store.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE TESTS THE CHAIN, NOT THE CLASS.** Every read is asked in the three spellings a caller has — the proxy,
 * the `values.` key, the `values.` key PATH — because they reach the same chain through three different doors, and a
 * controller that answered two of them would pass a one-spelling test. The policy half is measured by where the value
 * LANDED (the store or the pending dictionary) and by the two announcements that describe that: the store's own for a
 * committed write, and `hasUnappliedChanges` for a held one.
 *
 * **AND THE OBSERVATION BOUNDARY IS PINNED RATHER THAN ASSUMED.** The header says a `values.<key>` observation is
 * registered on the STORE, so the change's object is the store and its key path is the bare key; the probe asserts
 * exactly that, and asserts that `initialValues` is a READ-TIME fallback (its key has no initial notification).
 */
#import <AppKit/NSUserDefaultsController.h>
#import <AppKit/NSKeyValueBinding.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * AN OBSERVER THAT KEEPS THE LAST CHANGE, AND A TARGET WITH A VALUE                            *
 * ============================================================================================ */
@interface AGObserver : NSObject
{
@public
	int calls;
	id newValue;
	id oldValue;
	id observedObject;
	NSString *path;
}
@end

@implementation AGObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	id value;

	(void)context;
	calls++;
	[path release];
	path = [keyPath copy];
	observedObject = object;	/* NOT retained */
	value = [change objectForKey:NSKeyValueChangeNewKey];
	[newValue release];
	newValue = [value retain];
	value = [change objectForKey:NSKeyValueChangeOldKey];
	[oldValue release];
	oldValue = [value retain];
}
- (void)reset
{
	calls = 0;
	[newValue release];
	newValue = nil;
	[oldValue release];
	oldValue = nil;
	[path release];
	path = nil;
}
- (void)dealloc
{
	[newValue release];
	[oldValue release];
	[path release];
	[super dealloc];
}
@end

@interface AGTarget : NSObject
{
	id _value;
}
- (id)value;
- (void)setValue:(id)value;
@end

@implementation AGTarget
- (id)value { return _value; }
- (void)setValue:(id)value { [value retain]; [_value release]; _value = value; }
- (void)dealloc { [_value release]; [super dealloc]; }
@end

int main(void)
{
	@autoreleasepool {
		char scratch[] = "/tmp/agora-defaults-controller-XXXXXX";
		NSUserDefaults *store;
		NSUserDefaultsController *controller;
		AGObserver *observer = [[AGObserver alloc] init];
		NSMutableDictionary *starts;

		if (mkdtemp(scratch) == NULL) {
			printf("user_defaults_controller: cannot make a scratch directory\n");
			return 1;
		}
		setenv("FNX_CONFIG_ROOT", scratch, 1);
		store = [[NSUserDefaults alloc] initWithSuiteName:@"AgoraDefaultsControllerProbe"];
		starts = [NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"fallback", @"onlyInitial", @"forty", @"size", @"goneValue", @"gone", nil];
		controller = [[NSUserDefaultsController alloc] initWithDefaults:store initialValues:starts];

		/* --------------------------------------------------------------------------------- *
		 * 1. THE SHARED ONE, AND THE STORE THE CONTROLLER SPEAKS TO                           *
		 * --------------------------------------------------------------------------------- */
		check([NSUserDefaultsController sharedUserDefaultsController]
		      == [NSUserDefaultsController sharedUserDefaultsController],
		      "the shared controller is one object");
		check([[NSUserDefaultsController sharedUserDefaultsController] defaults]
		      == [NSUserDefaults standardUserDefaults],
		      "over the process's standard defaults");
		check([controller defaults] == store && [controller values] == [controller values],
		      "a controller keeps its store and answers one values proxy");
		check([controller appliesImmediately] && ![controller hasUnappliedChanges],
		      "it applies writes immediately by default and has nothing held");

		/* --------------------------------------------------------------------------------- *
		 * 2. THE READ CHAIN: STORE, THEN THE INITIAL VALUES, IN ALL THREE SPELLINGS          *
		 * --------------------------------------------------------------------------------- */
		[store setObject:@"stored" forKey:@"name"];
		check([[controller valueForKey:@"values.name"] isEqual:@"stored"],
		      "the values. key reads the store");
		check([[controller valueForKeyPath:@"values.name"] isEqual:@"stored"],
		      "and so does the values. key path");
		check([[[controller values] valueForKey:@"name"] isEqual:@"stored"],
		      "and the proxy itself");
		check([[controller valueForKey:@"values.onlyInitial"] isEqual:@"fallback"],
		      "a key the store has not got falls back to initialValues");
		check([controller valueForKey:@"values.nothing"] == nil,
		      "and a key in neither place answers nil");

		/* --------------------------------------------------------------------------------- *
		 * 3. WRITES THROUGH EACH SPELLING LAND IN THE STORE                                   *
		 * --------------------------------------------------------------------------------- */
		[[controller values] setValue:@"by proxy" forKey:@"byProxy"];
		check([[store objectForKey:@"byProxy"] isEqual:@"by proxy"], "a proxy write goes to the store");
		[controller setValue:@"by key" forKey:@"values.byKey"];
		check([[store objectForKey:@"byKey"] isEqual:@"by key"], "a values. key write goes to the store");
		[controller setValue:@"by path" forKeyPath:@"values.byPath"];
		check([[store objectForKey:@"byPath"] isEqual:@"by path"], "a values. key path write goes to the store");
		[controller setValue:nil forKey:@"values.byProxy"];
		check([store objectForKey:@"byProxy"] == nil, "a nil write removes the key from the store");

		/* --------------------------------------------------------------------------------- *
		 * 4. THE OBSERVATION: REGISTERED ON THE STORE, WITH THE BARE KEY                       *
		 * --------------------------------------------------------------------------------- */
		[controller addObserver:observer
			     forKeyPath:@"values.name"
				options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
				context:NULL];
		check(observer->calls == 0, "registering with no Initial option announces nothing yet");
		[controller setValue:@"renamed" forKey:@"values.name"];
		check(observer->calls == 1 && [observer->newValue isEqual:@"renamed"]
		      && [observer->oldValue isEqual:@"stored"],
		      "a write through the controller delivers one change with the old and new values");
		check(observer->observedObject == store && [observer->path isEqual:@"name"],
		      "the change's object is the STORE and its path is the bare key, as the header states");

		[observer reset];
		[store setObject:@"outside" forKey:@"name"];
		check(observer->calls == 1, "a write made straight to the store is delivered too");
		[controller removeObserver:observer forKeyPath:@"values.name"];

		[observer reset];
		[controller addObserver:observer
			     forKeyPath:@"values.name"
				options:NSKeyValueObservingOptionInitial
				context:NULL];
		check(observer->calls == 1, "Initial delivers immediately");
		[controller removeObserver:observer forKeyPath:@"values.name" context:NULL];
		[observer reset];
		[store setObject:@"after removal" forKey:@"name"];
		check(observer->calls == 0, "and the context form of removal stops the delivery");

		{
			BOOL raised = NO;

			@try {
				[controller addObserver:observer forKeyPath:@"values.a.b" options:0 context:NULL];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "a path deeper than one segment under values. is refused by name");
		}

		/* THE FALLBACK IS READ-TIME, WHICH IS TO SAY NOT IN THE CHANGE STREAM. */
		[observer reset];
		[controller addObserver:observer
			     forKeyPath:@"values.onlyInitial"
				options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial)
				context:NULL];
		check(observer->calls == 1 && observer->newValue == [NSNull null],
		      "initialValues is a read-time fallback: its key's Initial is the store's nil");
		[controller removeObserver:observer forKeyPath:@"values.onlyInitial"];

		/* --------------------------------------------------------------------------------- *
		 * 5. A BINDING NAMES values.<key>                                                     *
		 * --------------------------------------------------------------------------------- */
		{
			AGTarget *target = [[AGTarget alloc] init];

			[store setObject:@"outside" forKey:@"name"];
			[target bind:@"value" toObject:controller withKeyPath:@"values.name" options:nil];
			check([[target value] isEqual:@"outside"], "a binding delivers the store's value at bind time");
			[store setObject:@"bound" forKey:@"name"];
			check([[target value] isEqual:@"bound"], "and follows the store");
			[target unbind:@"value"];
			[target release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 6. appliesImmediately NO: THE PENDING STORE                                         *
		 * --------------------------------------------------------------------------------- */
		{
			AGObserver *pending = [[AGObserver alloc] init];

			[controller addObserver:pending
				     forKeyPath:@"hasUnappliedChanges"
					options:NSKeyValueObservingOptionNew
					context:NULL];
			[controller addObserver:observer
				     forKeyPath:@"values.name"
					options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
					context:NULL];
			[observer reset];
			[controller setAppliesImmediately:NO];
			[controller setValue:@"typed" forKey:@"values.name"];
			check([[store objectForKey:@"name"] isEqual:@"bound"], "with the flag off the store has not changed");
			check([[controller valueForKey:@"values.name"] isEqual:@"typed"],
			      "but a read sees the pending value");
			check([controller hasUnappliedChanges], "and there are unapplied changes");
			check(pending->calls == 1, "which is announced once");
			check(observer->calls == 0, "and the values observer is silent, because the store did not change");

			[controller setValue:@"typed again" forKey:@"values.name"];
			check(pending->calls == 1, "a second held write does not announce the flag again");
			check([[controller valueForKey:@"values.name"] isEqual:@"typed again"],
			      "and the newest held value wins");

			[controller save:nil];
			check([[store objectForKey:@"name"] isEqual:@"typed again"], "save: writes the held value to the store");
			check(![controller hasUnappliedChanges] && pending->calls == 2,
			      "and clears the flag, announcing it");
			check(observer->calls == 1 && [observer->newValue isEqual:@"typed again"],
			      "the store's write is what the values observer hears");

			/* A HELD REMOVAL FALLS BACK TO THE INITIAL VALUES ON A READ, AND REMOVES ON SAVE. */
			[controller setValue:nil forKey:@"values.onlyInitial"];
			check([[controller valueForKey:@"values.onlyInitial"] isEqual:@"fallback"],
			      "a held removal reads through to what is left");
			[controller revert:nil];
			check(![controller hasUnappliedChanges], "revert: discards the held writes");
			check([[controller valueForKey:@"values.onlyInitial"] isEqual:@"fallback"],
			      "so the pending removal is gone and the fallback answers");

			[controller removeObserver:pending forKeyPath:@"hasUnappliedChanges"];
			[controller removeObserver:observer forKeyPath:@"values.name"];
			[pending release];
		}

		/* 7. TURNING THE FLAG BACK ON APPLIES WHAT WAS HELD, AND revertToInitialValues: RESETS. */
		{
			[controller setAppliesImmediately:NO];
			[controller setValue:@"held" forKey:@"values.name"];
			[controller setAppliesImmediately:YES];
			check([[store objectForKey:@"name"] isEqual:@"held"],
			      "turning appliesImmediately back on applies the held write");
			check(![controller hasUnappliedChanges], "and leaves nothing held");
		}
		[controller setValue:@"overwritten" forKey:@"values.size"];
		[controller revertToInitialValues:nil];
		check([[store objectForKey:@"size"] isEqual:@"forty"],
		      "revertToInitialValues: writes the initial values into the store");
		check([[controller valueForKey:@"values.size"] isEqual:@"forty"], "so a read sees them");

		/* 8. REPLACING THE INITIAL VALUES REPLACES THE FALLBACK. */
		[controller setInitialValues:[NSDictionary dictionaryWithObjectsAndKeys:
			@"freshValue", @"fresh", @"replaced", @"onlyInitial", nil]];
		check([[controller valueForKey:@"values.fresh"] isEqual:@"freshValue"],
		      "an initial value supplies a key the store has never had");
		check([[controller valueForKey:@"values.onlyInitial"] isEqual:@"fallback"]
		      && [[store objectForKey:@"onlyInitial"] isEqual:@"fallback"],
		      "and the fallback is not the store: the store's own value still wins where it has one");
		[controller setInitialValues:[NSDictionary dictionaryWithObject:@"replaced" forKey:@"onlyInitial"]];
		check([controller valueForKey:@"values.fresh"] == nil,
		      "setInitialValues: replaces the fallback dictionary");

		printf("user_defaults_controller: %d case(s) failed\n", s_failed);
		[observer release];
		[controller release];
		[store release];
		[[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithUTF8String:scratch] error:NULL];
	}
	return s_failed != 0;
}
