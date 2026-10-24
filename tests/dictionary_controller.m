/*
 * dictionary_controller — the key/value projection, one live pair per key, and the visible-key rules.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE TESTS THE PROJECTION AND THE IDENTITY.** A pair is measured by its three KVC properties and by where its
 * writes LAND (the content dictionary), the visible-key rules by which keys survive included and excluded, and the
 * cached pair by IDENTITY across a content replacement — because that identity is what the inherited settle step uses to
 * keep a selection, and a controller that minted a fresh pair per rebuild would pass every value test and lose every
 * selection.
 */
#import <AppKit/NSDictionaryController.h>
#import <AppKit/NSArrayController.h>
#import <AppKit/NSKeyValueBinding.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

@interface AGObserver : NSObject
{
@public
	int calls;
	id newValue;
}
@end

@implementation AGObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	(void)keyPath;
	(void)object;
	(void)context;
	calls++;
	[newValue release];
	newValue = [[change objectForKey:NSKeyValueChangeNewKey] retain];
}
- (void)dealloc
{
	[newValue release];
	[super dealloc];
}
@end

/* THE PAIR FOR A KEY, found through the arrangement — the caller's view of it is the three KVC names, not the class. */
static id pairForKey(NSArrayController *controller, NSString *key)
{
	NSArray *arranged = [controller arrangedObjects];
	NSUInteger i;

	for (i = 0; i < [arranged count]; i++) {
		id pair = [arranged objectAtIndex:i];

		if ([[pair valueForKey:@"key"] isEqual:key]) {
			return pair;
		}
	}
	return nil;
}

static NSArray *keysOf(NSArrayController *controller)
{
	NSArray *arranged = [controller arrangedObjects];
	NSMutableArray *keys = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [arranged count]; i++) {
		[keys addObject:[[arranged objectAtIndex:i] valueForKey:@"key"]];
	}
	return keys;
}

int main(void)
{
	@autoreleasepool {
		NSMutableDictionary *content = [NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"one", @"a", @"two", @"b", @"three", @"c", nil];
		NSDictionaryController *controller = [[NSDictionaryController alloc] init];

		/* --------------------------------------------------------------------------------- *
		 * 1. THE PROJECTION                                                                   *
		 * --------------------------------------------------------------------------------- */
		check([[controller arrangedObjects] count] == 0, "a fresh dictionary controller arranges nothing");
		[controller setContent:content];
		check([[controller arrangedObjects] count] == 3, "one pair per key");
		check([[[controller arrangedObjects] objectAtIndex:0] valueForKey:@"localizedKey"] != nil,
		      "a pair answers localizedKey, key and value through KVC");
		check([[pairForKey(controller, @"a") valueForKey:@"value"] isEqual:@"one"],
		      "a pair's value is the content's value for its key");

		/* --------------------------------------------------------------------------------- *
		 * 2. THE ARRANGEMENT RUNS OVER THE PAIRS                                              *
		 * --------------------------------------------------------------------------------- */
		[controller setSortDescriptors:
			[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"key" ascending:YES]]];
		check([keysOf(controller) isEqual:[NSArray arrayWithObjects:@"a", @"b", @"c", nil]],
		      "a sort descriptor orders the pairs by key");
		[controller setFilterPredicate:[NSPredicate predicateWithFormat:@"key BEGINSWITH \"b\""]];
		check([[controller arrangedObjects] count] == 1
		      && [[[[controller arrangedObjects] objectAtIndex:0] valueForKey:@"key"] isEqual:@"b"],
		      "a filter predicate runs over the pairs");
		[controller setFilterPredicate:nil];
		[controller setSortDescriptors:nil];

		/* --------------------------------------------------------------------------------- *
		 * 3. includedKeys AND excludedKeys                                                    *
		 * --------------------------------------------------------------------------------- */
		[controller setIncludedKeys:[NSArray arrayWithObjects:@"a", @"c", nil]];
		check([[controller arrangedObjects] count] == 2, "includedKeys limits the arrangement");
		[controller setExcludedKeys:[NSArray arrayWithObject:@"c"]];
		check([[controller arrangedObjects] count] == 1
		      && [[[[controller arrangedObjects] objectAtIndex:0] valueForKey:@"key"] isEqual:@"a"],
		      "and excludedKeys subtracts from what survived");
		[controller setExcludedKeys:nil];
		[controller setIncludedKeys:nil];
		check([[controller arrangedObjects] count] == 3, "nil includedKeys means every key again");

		/* --------------------------------------------------------------------------------- *
		 * 4. THE DISPLAYED NAME                                                               *
		 * --------------------------------------------------------------------------------- */
		[controller setLocalizedKeyDictionary:
			[NSDictionary dictionaryWithObject:@"The A" forKey:@"a"]];
		check([[pairForKey(controller, @"a") valueForKey:@"localizedKey"] isEqual:@"The A"],
		      "localizedKeyDictionary supplies the displayed name");
		check([[pairForKey(controller, @"b") valueForKey:@"localizedKey"] isEqual:@"b"],
		      "and a key it does not name displays as itself");
		[controller setLocalizedKeyTable:@"Probe"];
		check([[controller localizedKeyTable] isEqual:@"Probe"], "localizedKeyTable is stored and answered");

		/* --------------------------------------------------------------------------------- *
		 * 5. A PAIR IS LIVE, AND WRITES THE DICTIONARY                                         *
		 * --------------------------------------------------------------------------------- */
		{
			id pair = pairForKey(controller, @"a");
			AGObserver *observer = [[AGObserver alloc] init];

			[content setObject:@"changed outside" forKey:@"a"];
			check([[pair valueForKey:@"value"] isEqual:@"changed outside"],
			      "a pair reads through to the content, so an outside write is visible");

			[controller addObserver:observer forKeyPath:@"arrangedObjects" options:NSKeyValueObservingOptionNew context:NULL];
			[pair setValue:@"written through" forKey:@"value"];
			check([[content objectForKey:@"a"] isEqual:@"written through"],
			      "a pair's write lands in the content");
			check(observer->calls == 1, "and announces the arrangement once");
			[controller removeObserver:observer forKeyPath:@"arrangedObjects"];

			[pair setValue:@"renamed" forKey:@"key"];
			check([content objectForKey:@"a"] == nil
			      && [[content objectForKey:@"renamed"] isEqual:@"written through"],
			      "renaming a pair moves its entry");
			check([[pair valueForKey:@"key"] isEqual:@"renamed"] && [[pair valueForKey:@"value"] isEqual:@"written through"],
			      "and the pair answers its new key and the value that moved with it");
			[pair setValue:@"renamed" forKey:@"key"];	/* a no-op rename is not a change */
			[observer release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 6. THE NEW PAIR, AND THE ADD DOORS                                                  *
		 * --------------------------------------------------------------------------------- */
		[controller setContent:[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"one", @"a", @"two", @"b", nil]];
		[controller setInitialKey:@"d"];
		[controller setInitialValue:@"four"];
		{
			id made = [controller newObject];

			check([[made valueForKey:@"key"] isEqual:@"d"] && [[made valueForKey:@"value"] isEqual:@"four"],
			      "newObject carries the initial key and value");
			check([[controller arrangedObjects] count] == 2, "and is not in the content until it is added");
			[controller addObject:made];
			check([[controller content] count] == 3
			      && [[[controller content] objectForKey:@"d"] isEqual:@"four"],
			      "adding it writes the entry");
			check([[controller selectedObjects] count] == 1
			      && [[controller selectedObjects] objectAtIndex:0] == made,
			      "and the added pair is selected");
			check(pairForKey(controller, @"d") == made,
			      "the arrangement holds the SAME pair object that was added");
		}
		{
			BOOL raised = NO;

			[controller setInitialKey:nil];
			@try {
				[controller addObject:[controller newObject]];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "a pair with no key is refused by name");
			raised = NO;
			@try {
				[controller addObject:@"not a pair"];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "and so is an object that is not a pair");
		}
		{
			id second = [[[controller newObject] retain] autorelease];
			id third;

			[second setValue:@"x" forKey:@"key"];
			[second setValue:@"ex" forKey:@"value"];
			[controller insertObject:second atArrangedObjectIndex:0];
			check([[[controller content] objectForKey:@"x"] isEqual:@"ex"],
			      "insertObject:atArrangedObjectIndex: adds the entry; the index has no order to land in");
			third = [controller newObject];
			[third setValue:@"y" forKey:@"key"];
			[third setValue:@"why" forKey:@"value"];
			[controller insertObjects:[NSArray arrayWithObject:third]
			   atArrangedObjectIndexes:[NSIndexSet indexSetWithIndex:0]];
			check([[[controller content] objectForKey:@"y"] isEqual:@"why"], "and so does the plural door");
		}

		/* --------------------------------------------------------------------------------- *
		 * 7. REMOVAL                                                                          *
		 * --------------------------------------------------------------------------------- */
		[controller setContent:[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"one", @"a", @"two", @"b", @"three", @"c", nil]];
		[controller removeObject:pairForKey(controller, @"b")];
		check([[controller content] count] == 2 && [[controller content] objectForKey:@"b"] == nil,
		      "removeObject: removes that pair's entry");
		[controller setSelectedObjects:[NSArray arrayWithObjects:pairForKey(controller, @"a"), nil]];
		[controller removeSelectedObjects:nil];
		check([[controller content] count] == 1, "removeSelectedObjects: removes the selection");
		check([[controller selectionIndexes] count] == 1,
		      "and avoidsEmptySelection leaves something selected");

		/* --------------------------------------------------------------------------------- *
		 * 8. THE PAIR'S IDENTITY SURVIVES A CONTENT REPLACEMENT                                *
		 * --------------------------------------------------------------------------------- */
		{
			id pair = pairForKey(controller, @"c");

			[controller setSelectedObjects:[NSArray arrayWithObject:pair]];
			[controller setContent:[NSMutableDictionary dictionaryWithObjectsAndKeys:
				@"three", @"c", @"four", @"d", nil]];
			check([[controller selectedObjects] count] == 1
			      && [[controller selectedObjects] objectAtIndex:0] == pair,
			      "preservesSelection keeps the SAME pair across a replacement content");
			check(pairForKey(controller, @"c") == pair, "because the pair cache answers one object per key");
		}

		/* --------------------------------------------------------------------------------- *
		 * 9. WHAT THE CONTENT'S KIND ALLOWS                                                   *
		 * --------------------------------------------------------------------------------- */
		check([controller canAdd] && [controller canRemove],
		      "a mutable dictionary content can be added to and removed from");
		[controller setContent:[NSDictionary dictionaryWithObject:@"fixed" forKey:@"f"]];
		check(![controller canAdd] && ![controller canRemove],
		      "an immutable dictionary can do neither");
		{
			BOOL raised = NO;
			id pair = [[controller newObject] retain];

			[pair setValue:@"g" forKey:@"key"];
			[pair setValue:@"gee" forKey:@"value"];
			@try {
				[controller addObject:pair];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "and an add raises rather than silently doing nothing");
			[pair release];
		}
		[controller setContent:nil];
		check([controller canAdd] && ![controller canRemove], "nil content can take a first pair and has nothing to remove");
		{
			BOOL raised = NO;

			/* THE RAISE COMES FROM `-setContent:` ITSELF: a content change announces the arrangement, and the
			 * announcement reads it — the same shape the array controller documents for a non-collection. */
			@try {
				[controller setContent:[NSArray array]];
				(void)[controller arrangedObjects];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "an array content raises: a dictionary controller arranges pairs over a dictionary");
			/* **AND THE REFUSAL LEAVES THE CONTROLLER USABLE**, because the setter validates BEFORE it stores: a
			 * rejected content that had been stored would make every later arrangement raise. */
			[controller setContent:[NSMutableDictionary dictionaryWithObject:@"one" forKey:@"a"]];
			check([[controller arrangedObjects] count] == 1,
			      "and the controller still arranges after a refused content");
		}

		/* 10. THE BINDINGS AND THE CRITERIA ANNOUNCEMENT. */
		[controller setContent:[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"one", @"a", @"two", @"b", nil]];
		check([[controller exposedBindings] containsObject:@"includedKeys"]
		      && [[controller exposedBindings] containsObject:@"localizedKeyDictionary"]
		      && [[controller exposedBindings] containsObject:@"initialKey"],
		      "the dictionary bindings are exposed");
		check([[controller exposedBindings] containsObject:@"arrangedObjects"],
		      "and the inherited arrangement binding is still there");
		{
			AGObserver *observer = [[AGObserver alloc] init];

			[controller addObserver:observer forKeyPath:@"arrangedObjects" options:NSKeyValueObservingOptionNew context:NULL];
			[controller setIncludedKeys:[NSArray arrayWithObject:@"a"]];
			check(observer->calls == 1 && [observer->newValue count] == 1,
			      "changing includedKeys announces the re-arranged pairs");
			[controller removeObserver:observer forKeyPath:@"arrangedObjects"];
			[observer release];
		}

		printf("dictionary_controller: %d case(s) failed\n", s_failed);
		[controller release];
	}
	return s_failed != 0;
}
