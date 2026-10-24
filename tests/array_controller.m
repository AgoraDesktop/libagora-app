/*
 * array_controller — the arrangement, the selection into it, and the arranged-to-content index translation.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE TESTS THE ARRANGEMENT AS A VALUE AND THE SELECTION AS A VALUE, AND THE KVO SECTION AS DELIVERY.**
 * The arrangement is measured by its ORDER (a sort that silently did nothing would pass a count test), the filter by
 * which objects survive, and the insertion doors by where the object landed in the CONTENT — because the arranged
 * index is the door's argument and the content is where the translation's correctness is visible. The policy flags are
 * measured one at a time, each against the behaviour it changes.
 */
#import <AppKit/NSArrayController.h>
#import <AppKit/NSObjectController.h>
#import <AppKit/NSKeyValueBinding.h>
#import <AppKit/NSController.h>
#import <Foundation/Foundation.h>

#include <stdarg.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * A MODEL WITH A KVO-OBSERVABLE NAME, AN OBSERVER, AND A TARGET WITH AN ITEMS ARRAY                *
 * ============================================================================================ */
@interface AGModel : NSObject
{
	id _name;
}
- (id)name;
- (void)setName:(id)value;
@end

@implementation AGModel
- (id)name { return _name; }
- (void)setName:(id)value { [value retain]; [_name release]; _name = value; }
- (void)dealloc { [_name release]; [super dealloc]; }
+ (id)modelWithName:(id)name
{
	AGModel *model = [[self alloc] init];

	[model setName:name];
	return [model autorelease];
}
@end

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
	id value;

	(void)keyPath;
	(void)object;
	(void)context;
	calls++;
	value = [change objectForKey:NSKeyValueChangeNewKey];
	[newValue release];
	newValue = [value retain];
}
- (void)dealloc
{
	[newValue release];
	[super dealloc];
}
@end

@interface AGTarget : NSObject
{
	id _items;
}
- (id)items;
- (void)setItems:(id)value;
@end

@implementation AGTarget
- (id)items { return _items; }
- (void)setItems:(id)value { [value retain]; [_items release]; _items = value; }
- (void)dealloc { [_items release]; [super dealloc]; }
@end

/* A NAME-ORDERED ARRAY, spelled once: `names(@"c", @"a", @"b", nil)`. The nil TERMINATES, so it is not an object. */
static NSMutableArray *names(NSString *first, ...)
{
	NSMutableArray *out = [NSMutableArray array];
	va_list args;
	NSString *name;

	va_start(args, first);
	for (name = first; name != nil; name = va_arg(args, NSString *)) {
		[out addObject:[AGModel modelWithName:name]];
	}
	va_end(args);
	return out;
}

int main(void)
{
	@autoreleasepool {
		/* --------------------------------------------------------------------------------- *
		 * 1. THE ARRANGEMENT: ORDER, FILTER, AND THE PURE FUNCTION                            *
		 * --------------------------------------------------------------------------------- */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];
			NSMutableArray *content = names(@"c", @"a", @"b", nil);
			AGModel *a = [content objectAtIndex:1];
			NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];

			check([[controller arrangedObjects] count] == 0, "a fresh controller arranges nothing");
			check([[controller selectionIndexes] count] == 0 && [controller selectionIndex] == NSNotFound,
			      "and has no selection");
			check([controller canInsert] && ![controller canRemove],
			      "nil content can take an insertion and has nothing to remove");

			[controller setContent:content];
			check([[controller arrangedObjects] isEqual:content],
			      "with no sort the arrangement is the content's own order");
			check([controller selectionIndex] == 0,
			      "and avoidsEmptySelection selects the first object of a non-empty arrangement");

			[controller setSortDescriptors:[NSArray arrayWithObject:byName]];
			check([[[controller arrangedObjects] objectAtIndex:0] isEqual:a],
			      "a sort puts the object named 'a' first");
			check([[[controller arrangedObjects] objectAtIndex:2] isEqual:[content objectAtIndex:0]],
			      "and the one named 'c' last");
			check([[controller content] isEqual:content], "the content itself is not re-ordered by the arrangement");

			[controller setFilterPredicate:[NSPredicate predicateWithFormat:@"name == \"b\""]];
			check([[controller arrangedObjects] count] == 1
			      && [[[[controller arrangedObjects] objectAtIndex:0] name] isEqual:@"b"],
			      "a filter drops every object that does not match");
			check([[controller content] count] == 3, "and the content keeps all of them");

			[controller setFilterPredicate:nil];
			check([[controller arrangedObjects] count] == 3, "a nil filter means no filter");

			check([[controller arrangeObjects:content] count] == 3,
			      "arrangeObjects: arranges the array it is handed");
			{
				NSArray *one = [controller arrangeObjects:[NSArray arrayWithObject:[content objectAtIndex:0]]];

				check([one count] == 1 && [one objectAtIndex:0] == [content objectAtIndex:0],
				      "and answers that array's objects, not the content's");
			}

			[controller setContent:nil];
			check([[controller arrangedObjects] count] == 0 && [[controller selectionIndexes] count] == 0,
			      "nil content is an empty arrangement and an empty selection");

			[controller setSortDescriptors:nil];
			[controller setContent:[NSSet setWithArray:content]];
			check([[controller arrangedObjects] count] == 3, "a set content contributes its objects to the arrangement");

			{
				BOOL raised = NO;

				/* **THE RAISE COMES FROM `-setContent:` ITSELF**, because a content change announces the arrangement
				 * and the announcement reads it — so the wrong class's content is refused at the door that set it,
				 * not later at the first draw. Both spellings are checked for that reason. */
				@try {
					[controller setContent:a];
					(void)[controller arrangedObjects];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "a single object as content raises rather than arranging as nothing");
			}

			[controller release];
		}

		/* 2. THE ARRANGEMENT IS ANNOUNCED WHEN A CRITERION CHANGES. */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];
			AGObserver *observer = [[AGObserver alloc] init];

			[controller setContent:names(@"c", @"a", @"b", nil)];
			[controller addObserver:observer
				     forKeyPath:@"arrangedObjects"
					options:NSKeyValueObservingOptionNew
					context:NULL];
			[controller setSortDescriptors:
				[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
			check(observer->calls == 1, "a sort change announces arrangedObjects once");
			check([observer->newValue isKindOfClass:[NSArray class]] && [observer->newValue count] == 3
			      && [[[observer->newValue objectAtIndex:0] name] isEqual:@"a"],
			      "and the new value is the re-arranged array");
			[controller setFilterPredicate:[NSPredicate predicateWithFormat:@"name == \"b\""]];
			check(observer->calls == 2 && [observer->newValue count] == 1,
			      "a filter change announces the filtered arrangement");
			[controller removeObserver:observer forKeyPath:@"arrangedObjects"];

			[observer release];
			[controller release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 3. THE SELECTION INTO THE ARRANGEMENT                                             *
		 * --------------------------------------------------------------------------------- */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];
			NSMutableArray *content = names(@"a", @"b", @"c", nil);
			AGModel *a = [content objectAtIndex:0];
			AGModel *b = [content objectAtIndex:1];
			AGModel *c = [content objectAtIndex:2];
			NSMutableIndexSet *two = [[NSMutableIndexSet alloc] init];

			[controller setContent:content];
			[controller setSelectionIndex:1];
			check([controller selectionIndex] == 1
			      && [[controller selectedObjects] count] == 1
			      && [[controller selectedObjects] objectAtIndex:0] == b,
			      "a selection index selects that arranged object");
			check([controller contentObject] == b, "and a one-object selection makes the content object that object");
			check([[[controller selection] valueForKey:@"name"] isEqual:@"b"],
			      "the inherited selection proxy forwards to it");

			[two addIndex:0];
			[two addIndex:2];
			[controller setSelectionIndexes:two];
			check([[controller selectedObjects] isEqual:[NSArray arrayWithObjects:a, c, nil]],
			      "an index set selects every object it names");
			check([controller contentObject] == NSMultipleValuesMarker,
			      "two selected objects make the content object a marker");
			check([[controller selection] valueForKey:@"name"] == NSMultipleValuesMarker,
			      "and the proxy answers the marker for a value they disagree on");

			[a setName:@"same"];
			[c setName:@"same"];
			check([[[controller selection] valueForKey:@"name"] isEqual:@"same"],
			      "the proxy answers a value every selected object agrees on");
			[[controller selection] setValue:@"agreed" forKey:@"name"];
			check([[a name] isEqual:@"agreed"] && [[c name] isEqual:@"agreed"],
			      "and a write through it reaches all of them");

			[controller setSelectedObjects:[NSArray arrayWithObject:b]];
			check([controller selectionIndex] == 1, "setSelectedObjects: maps an object back to its arranged index");

			{
				BOOL raised = NO;

				@try {
					[controller setSelectionIndex:3];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSRangeException];
				}
				check(raised, "an index past the arrangement raises NSRangeException");
			}

			[controller setSelectionIndex:1];
			[controller addSelectionIndexes:[NSIndexSet indexSetWithIndex:2]];
			check([[controller selectionIndexes] containsIndex:1]
			      && [[controller selectionIndexes] containsIndex:2],
			      "addSelectionIndexes: unions");
			[controller removeSelectionIndexes:[NSIndexSet indexSetWithIndex:1]];
			check(![[controller selectionIndexes] containsIndex:1], "removeSelectionIndexes: subtracts");

			[controller setSelectionIndex:NSNotFound];
			check([[controller selectionIndexes] count] == 0 && [controller selectionIndex] == NSNotFound,
			      "NSNotFound empties the selection");
			check([[controller selection] valueForKey:@"name"] == NSNoSelectionMarker,
			      "and the proxy answers the no-selection marker");
			{
				BOOL raised = NO;

				@try {
					[[controller selection] setValue:@"x" forKey:@"name"];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "and a write with no selection raises");
			}

			/* THE ARROW KEYS, FROM AN EMPTY SELECTION AND AT BOTH ENDS. */
			[controller selectNext:nil];
			check([controller selectionIndex] == 0, "selectNext: from no selection takes the first object");
			[controller selectNext:nil];
			[controller selectNext:nil];
			check([controller selectionIndex] == 2, "and walks forward");
			check(![controller canSelectNext], "at the last object it cannot go further");
			[controller selectNext:nil];
			check([controller selectionIndex] == 2, "and the action is a no-op there");
			check([controller canSelectPrevious], "backwards it can");
			[controller selectPrevious:nil];
			check([controller selectionIndex] == 1, "selectPrevious: walks back");

			[controller setSelectionIndex:NSNotFound];
			[controller selectPrevious:nil];
			check([controller selectionIndex] == 2, "from no selection, previous takes the last object");

			/* alwaysUsesMultipleValuesMarker: ONE object, A MARKER ON READS, A WRITE THAT STILL LANDS. */
			[controller setSelectionIndex:1];
			[controller setAlwaysUsesMultipleValuesMarker:YES];
			check([[controller selection] valueForKey:@"name"] == NSMultipleValuesMarker,
			      "alwaysUsesMultipleValuesMarker makes the proxy answer the marker even for one object");
			[[controller selection] setValue:@"written" forKey:@"name"];
			check([[b name] isEqual:@"written"], "and the write still reaches the selected object");
			[controller setAlwaysUsesMultipleValuesMarker:NO];
			check([[[controller selection] valueForKey:@"name"] isEqual:@"written"],
			      "and turning the flag off forwards the value again");

			[two release];
			[controller release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 4. THE POLICY FLAGS, ONE AT A TIME                                                *
		 * --------------------------------------------------------------------------------- */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];
			NSMutableArray *content = names(@"a", @"b", @"c", nil);
			AGModel *b = [content objectAtIndex:1];
			NSSortDescriptor *ascending = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
			NSSortDescriptor *descending = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO];

			/* preservesSelection: ON — the same OBJECT is selected after a re-sort. */
			[controller setContent:content];
			[controller setSortDescriptors:[NSArray arrayWithObject:ascending]];
			[controller setSelectedObjects:[NSArray arrayWithObject:b]];
			[controller setSortDescriptors:[NSArray arrayWithObject:descending]];
			check([[controller selectedObjects] count] == 1
			      && [[controller selectedObjects] objectAtIndex:0] == b,
			      "preservesSelection keeps the selected OBJECT across a re-sort");
			check([controller selectionIndex] == 1, "even though its index changed");

			/* preservesSelection: OFF — the index is what is kept. */
			[controller setPreservesSelection:NO];
			[controller setSortDescriptors:[NSArray arrayWithObject:ascending]];
			[controller setSelectionIndex:0];
			[controller setSortDescriptors:[NSArray arrayWithObject:descending]];
			check([controller selectionIndex] == 0
			      && [[[[controller selectedObjects] objectAtIndex:0] name] isEqual:@"c"],
			      "with the flag off the INDEX is kept, which is now a different object");
			[controller setPreservesSelection:YES];

			/* avoidsEmptySelection: OFF — an empty selection stays empty. */
			[controller setSelectionIndex:NSNotFound];
			[controller setAvoidsEmptySelection:NO];
			[controller rearrangeObjects];
			check([[controller selectionIndexes] count] == 0, "with the flag off an empty selection stays empty");
			[controller setAvoidsEmptySelection:YES];
			[controller rearrangeObjects];
			check([controller selectionIndex] == 0, "and with it on the first object is selected again");

			/* selectsInsertedObjects: ON — an added object becomes the selection. */
			[controller setSortDescriptors:nil];
			[controller setContent:names(@"a", @"b", nil)];
			{
				AGModel *inserted = [AGModel modelWithName:@"z"];

				[controller addObject:inserted];
				check([[controller selectedObjects] count] == 1
				      && [[controller selectedObjects] objectAtIndex:0] == inserted,
				      "selectsInsertedObjects selects what was added");

				[controller setSelectsInsertedObjects:NO];
				[controller setSelectionIndex:0];
				[controller addObject:[AGModel modelWithName:@"y"]];
				check([controller selectionIndex] == 0, "and with the flag off the selection does not move");
			}

			/* clearsFilterPredicateOnInsertion: ON — the row the user adds is not hidden. */
			[controller setContent:names(@"a", @"b", nil)];
			[controller setFilterPredicate:[NSPredicate predicateWithFormat:@"name == \"a\""]];
			{
				AGModel *hidden = [AGModel modelWithName:@"c"];

				[controller addObject:hidden];
				check([controller filterPredicate] == nil, "an insertion clears the filter when the flag says so");
				check([[controller arrangedObjects] lastObject] == hidden,
				      "so the inserted object is visible");
			}
			[controller setContent:names(@"a", @"b", nil)];
			[controller setFilterPredicate:[NSPredicate predicateWithFormat:@"name == \"a\""]];
			[controller setClearsFilterPredicateOnInsertion:NO];
			{
				AGModel *filtered = [AGModel modelWithName:@"c"];

				[controller addObject:filtered];
				check([controller filterPredicate] != nil && [[controller arrangedObjects] count] == 1,
				      "and with the flag off the filter stands and the object stays hidden");
			}

			[controller release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 5. THE INSERTION DOORS: ARRANGED INDEX IN, CONTENT ORDER OUT                      *
		 * --------------------------------------------------------------------------------- */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];

			[controller setContent:names(@"a", @"b", @"c", nil)];
			{
				AGModel *x = [AGModel modelWithName:@"x"];

				[controller insertObject:x atArrangedObjectIndex:1];
				check([[controller content] count] == 4
				      && [[controller content] objectAtIndex:1] == x,
				      "an arranged index is translated to the content position");
				check([[controller selectedObjects] count] == 1
				      && [[controller selectedObjects] objectAtIndex:0] == x,
				      "and the inserted object is selected");
			}
			{
				AGModel *tail = [AGModel modelWithName:@"tail"];

				[controller insertObject:tail atArrangedObjectIndex:[[controller arrangedObjects] count]];
				check([[controller content] lastObject] == tail, "an index equal to the count appends");
			}

			/* TWO OBJECTS AT TWO ANCHORS, APPLIED FROM THE HIGHEST CONTENT INDEX DOWN. */
			[controller setContent:names(@"a", @"b", @"c", nil)];
			{
				NSMutableIndexSet *where = [[NSMutableIndexSet alloc] init];
				AGModel *x = [AGModel modelWithName:@"x"];
				AGModel *y = [AGModel modelWithName:@"y"];
				NSArray *contentNow;

				[where addIndex:0];
				[where addIndex:2];
				[controller insertObjects:[NSArray arrayWithObjects:x, y, nil]
				   atArrangedObjectIndexes:where];
				contentNow = [controller content];
				check([contentNow count] == 5
				      && [contentNow objectAtIndex:0] == x
				      && [contentNow objectAtIndex:3] == y,
				      "two insertions land before their own anchors, not before each other's");
				check([[controller selectedObjects] count] == 2,
				      "and both inserted objects are selected");
				[where release];
			}
			{
				BOOL raised = NO;

				@try {
					[controller insertObjects:[NSArray arrayWithObject:
						[AGModel modelWithName:@"q"]]
					   atArrangedObjectIndexes:[NSIndexSet indexSetWithIndex:9]];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSRangeException];
				}
				check(raised, "an insertion index past the arrangement raises NSRangeException");
				raised = NO;
				@try {
					[controller insertObjects:[NSArray arrayWithObjects:
						[AGModel modelWithName:@"q"], [AGModel modelWithName:@"r"], nil]
					   atArrangedObjectIndexes:[NSIndexSet indexSetWithIndex:0]];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "and a count mismatch between objects and indexes raises");
			}

			/* REMOVAL BY ARRANGED POSITION, AND THE SELECTION'S POLICY AFTER IT. */
			[controller setContent:names(@"a", @"b", @"c", nil)];
			{
				AGModel *doomed = [[controller arrangedObjects] objectAtIndex:1];

				[controller setSelectionIndex:1];
				[controller removeObjectAtArrangedObjectIndex:1];
				check([[controller content] count] == 2
				      && ![[controller content] containsObject:doomed],
				      "removing an arranged index removes that object from the content");
				check([[controller selectionIndexes] count] == 1,
				      "and avoidsEmptySelection leaves something selected");
			}

			[controller setContent:names(@"a", @"b", @"c", nil)];
			{
				NSMutableIndexSet *where = [[NSMutableIndexSet alloc] init];
				AGModel *keep = [[controller arrangedObjects] objectAtIndex:1];

				[where addIndex:0];
				[where addIndex:2];
				[controller removeObjectsAtArrangedObjectIndexes:where];
				check([[controller content] count] == 1
				      && [[controller content] objectAtIndex:0] == keep,
				      "removing an index set removes exactly those objects");
				[where release];
			}

			/* SELECTED-OBJECTS REMOVAL, AND THE INSERT ACTION. */
			[controller setContent:names(@"a", @"b", @"c", nil)];
			[controller setSelectedObjects:[NSArray arrayWithObject:[[controller arrangedObjects] objectAtIndex:0]]];
			[controller removeSelectedObjects:nil];
			check([[controller content] count] == 2, "removeSelectedObjects: removes the selection");
			[controller setSelectionIndex:1];
			[controller insert:nil];
			check([[controller content] count] == 3
			      && [[[controller content] objectAtIndex:1] isKindOfClass:[NSMutableDictionary class]]
			      && [[controller selectedObjects] count] == 1
			      && [[[controller selectedObjects] objectAtIndex:0] isKindOfClass:[NSMutableDictionary class]],
			      "insert: creates a newObject and places it at the selection");

			/* A CONTENT THAT REPEATS AN OBJECT STILL TRANSLATES POSITIONALLY. */
			{
				NSMutableArray *repeated = [NSMutableArray array];
				AGModel *same = [AGModel modelWithName:@"same"];
				AGModel *other = [AGModel modelWithName:@"other"];
				AGModel *x = [AGModel modelWithName:@"x"];

				[repeated addObject:same];
				[repeated addObject:same];
				[repeated addObject:other];
				[controller setContent:repeated];
				[controller insertObject:x atArrangedObjectIndex:1];
				check([[controller content] count] == 4
				      && [[controller content] objectAtIndex:0] == same
				      && [[controller content] objectAtIndex:1] == x
				      && [[controller content] objectAtIndex:2] == same,
				      "the SECOND occurrence of a repeated object is the one translated to");
			}

			[controller release];
		}

		/* 6. THE ARRANGEMENT IS ANNOUNCED AFTER A CONTENT CHANGE, AND THE SELECTION AFTER A SELECTION CHANGE. */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];
			AGObserver *arrangement = [[AGObserver alloc] init];
			AGObserver *selection = [[AGObserver alloc] init];

			[controller setContent:names(@"b", @"a", nil)];
			[controller addObserver:arrangement
				     forKeyPath:@"arrangedObjects"
					options:NSKeyValueObservingOptionNew
					context:NULL];
			[controller setContent:names(@"c", @"a", @"b", nil)];
			check(arrangement->calls == 1 && [arrangement->newValue count] == 3,
			      "a content change announces the re-arranged array");
			[controller addObserver:selection
				     forKeyPath:@"selectedObjects"
					options:NSKeyValueObservingOptionNew
					context:NULL];
			[controller setSelectionIndex:1];
			check(selection->calls == 1 && [selection->newValue count] == 1,
			      "a selection change announces selectedObjects");

			[controller removeObserver:arrangement forKeyPath:@"arrangedObjects"];
			[controller removeObserver:selection forKeyPath:@"selectedObjects"];
			[arrangement release];
			[selection release];
			[controller release];
		}

		/* 7. THE BINDINGS THE CONTROLLER EXPOSES, AND ONE OF THEM DELIVERING. */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];
			AGTarget *target = [[AGTarget alloc] init];

			check([[controller exposedBindings] containsObject:@"arrangedObjects"]
			      && [[controller exposedBindings] containsObject:@"sortDescriptors"]
			      && [[controller exposedBindings] containsObject:@"selectionIndexes"],
			      "the arrangement and selection bindings are exposed");
			check([[controller exposedBindings] containsObject:@"content"],
			      "and the inherited content binding is still there");

			[controller setContent:names(@"c", @"a", @"b", nil)];
			[target bind:@"items" toObject:controller withKeyPath:@"arrangedObjects" options:nil];
			check([[target items] count] == 3, "a binding delivers arrangedObjects");
			[controller setSortDescriptors:
				[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
			check([[target items] count] == 3 && [[[[target items] objectAtIndex:0] name] isEqual:@"a"],
			      "and delivers the re-arranged array when a criterion changes");
			[target unbind:@"items"];

			[controller release];
			[target release];
		}

		/* 8. THE INHERITED DOORS STILL ANSWER FOR A COLLECTION. */
		{
			NSArrayController *controller = [[NSArrayController alloc] init];
			NSMutableArray *content = names(@"a", @"b", nil);

			[controller setContent:content];
			check([controller canAdd] && [controller canRemove] && [controller canInsert],
			      "a mutable array content can be added to, removed from and inserted into");
			[controller setSelectionIndex:NSNotFound];
			check([controller contentObject] == NSNoSelectionMarker,
			      "an empty selection makes the content object the no-selection marker");
			[controller setSelectionIndex:0];
			check([controller contentObject] == [content objectAtIndex:0],
			      "and one selected object is the content object");

			[controller release];
		}

		printf("array_controller: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
