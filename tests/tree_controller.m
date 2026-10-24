/*
 * tree_controller — the model tree, the node graph rebuilt from it, and the paths in between.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE TESTS THE SHAPE AS PATHS AND THE MODEL AS THE TRUTH.** Every node assertion is an `-indexPath` or a
 * `-descendantNodeAtIndexPath:`, because a path is the position a tree view speaks in; every mutation is checked against
 * the MODEL's arrays, because the node graph is this class's reading and the model is what a caller owns. The selection
 * is measured by OBJECT before and after a rebuild that renumbers it — the identity rule the array controller's probe
 * uses, one level deeper — and the two model errors are measured by their REFUSAL (a truncated node), not by an
 * exception, because the build runs inside a KVO announcement.
 */
#import <AppKit/NSTreeController.h>
#import <AppKit/NSTreeNode.h>
#import <AppKit/NSKeyValueBinding.h>
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

/* A PATH FROM A TERMINATED LIST OF INDEXES: `path(0, 1, NSNotFound)` is {0, 1}. */
static NSIndexPath *path(NSUInteger first, ...)
{
	NSUInteger stack[8];
	NSUInteger count = 0;
	va_list args;
	NSUInteger value;

	va_start(args, first);
	for (value = first; value != NSNotFound && count < 8; value = va_arg(args, NSUInteger)) {
		stack[count++] = value;
	}
	va_end(args);
	return [NSIndexPath indexPathWithIndexes:stack length:count];
}

/* ============================================================================================ *
 * A MODEL NODE: A NAME, A MUTABLE CHILDREN ARRAY, AND A LEAF FLAG                              *
 * ============================================================================================ */
@interface AGNode : NSObject
{
	id _name;
	NSMutableArray *_children;
	BOOL _leaf;
}
- (id)name;
- (void)setName:(id)value;
- (id)children;
- (void)setChildren:(id)value;
- (BOOL)isLeaf;
- (void)setIsLeaf:(BOOL)value;
@end

@implementation AGNode
- (id)name { return _name; }
- (void)setName:(id)value { [value retain]; [_name release]; _name = value; }
- (id)children { return _children; }
- (void)setChildren:(id)value { [value retain]; [_children release]; _children = value; }
- (BOOL)isLeaf { return _leaf; }
- (void)setIsLeaf:(BOOL)value { _leaf = value; }
- (void)dealloc { [_name release]; [_children release]; [super dealloc]; }
+ (id)node:(NSString *)name
{
	AGNode *node = [[self alloc] init];

	[node setName:name];
	[node setChildren:[NSMutableArray array]];
	return [node autorelease];
}
+ (id)node:(NSString *)name with:(NSArray *)children
{
	AGNode *node = [[self alloc] init];

	[node setName:name];
	[node setChildren:[NSMutableArray arrayWithArray:children]];
	return [node autorelease];
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
	(void)keyPath;
	(void)object;
	(void)context;
	calls++;
	[newValue release];
	newValue = [[change objectForKey:NSKeyValueChangeNewKey] retain];
}
- (void)dealloc { [newValue release]; [super dealloc]; }
@end

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);	/* the probe prints through a crash, so the last line names the section */
	@autoreleasepool {
		AGNode *a1 = [AGNode node:@"a1"];
		AGNode *a = [AGNode node:@"a" with:[NSArray arrayWithObject:a1]];
		AGNode *b = [AGNode node:@"b"];
		AGNode *root1 = [AGNode node:@"root1" with:[NSArray arrayWithObjects:b, a, nil]];
		AGNode *leafish = [AGNode node:@"leafish" with:[NSArray arrayWithObject:[AGNode node:@"hidden"]]];
		AGNode *root2 = [AGNode node:@"root2" with:[NSArray arrayWithObject:leafish]];
		NSMutableArray *content = [NSMutableArray arrayWithObjects:root1, root2, nil];
		NSTreeController *controller = [[NSTreeController alloc] init];

		/* --------------------------------------------------------------------------------- *
		 * 1. THE CONTENT AND THE SHAPE                                                        *
		 * --------------------------------------------------------------------------------- */
		check([[controller arrangedObjects] count] == 0 && [[controller selectionIndexPaths] count] == 0,
		      "a fresh tree controller arranges nothing and selects nothing");
		[controller setContent:content];
		check([[controller arrangedObjects] count] == 2, "one node per root object");
		check([[[controller arrangedObjects] objectAtIndex:0] representedObject] == root1,
		      "and a root node's represented object is the model's");
		check([[[[controller arrangedObjects] objectAtIndex:0] childNodes] count] == 0,
		      "with no childrenKeyPath a node has no children");

		[controller setChildrenKeyPath:@"children"];
		check([[[[controller arrangedObjects] objectAtIndex:0] childNodes] count] == 2,
		      "childrenKeyPath builds the children");
		check([[[[[controller arrangedObjects] objectAtIndex:0] childNodes] objectAtIndex:1] representedObject] == a,
		      "in the model's order");
		check([[controller selectionIndexPaths] count] == 1, "and avoidsEmptySelection selects the first root");

		/* --------------------------------------------------------------------------------- *
		 * 2. POSITIONS ARE PATHS                                                              *
		 * --------------------------------------------------------------------------------- */
		{
			NSTreeNode *rootNode = [[controller arrangedObjects] objectAtIndex:0];
			NSTreeNode *aNode = [[rootNode childNodes] objectAtIndex:1];
			NSTreeNode *a1Node = [[aNode childNodes] objectAtIndex:0];

			check([[rootNode indexPath] isEqual:path(0, NSNotFound)],
			      "a root's path is its index in the invisible root's children");
			check([[aNode indexPath] isEqual:path(0, 1, NSNotFound)],
			      "a child's path is the chain of child indexes");
			check([[a1Node indexPath] isEqual:path(0, 1, 0, NSNotFound)], "and a grandchild's is one deeper");
			check([aNode parentNode] == rootNode && [a1Node parentNode] == aNode, "parent links walk upward");
			check(![aNode isLeaf] && [a1Node isLeaf], "isLeaf is the absence of children");
			check([[rootNode descendantNodeAtIndexPath:path(1, 0, NSNotFound)] representedObject] == a1,
			      "descendantNodeAtIndexPath: resolves a path below a node");
			check([rootNode descendantNodeAtIndexPath:path(5, NSNotFound)] == nil,
			      "and answers nil for a path that is not there");
		}

		/* --------------------------------------------------------------------------------- *
		 * 3. THE LEAF KEY PATH SHORT-CIRCUITS THE BUILD                                       *
		 * --------------------------------------------------------------------------------- */
		[leafish setIsLeaf:YES];
		check([[[[[controller arrangedObjects] objectAtIndex:1] childNodes] objectAtIndex:0] childNodes].count == 1,
		      "before leafKeyPath the leaf-ish node still has its child");
		[controller setLeafKeyPath:@"isLeaf"];
		check([[[[[controller arrangedObjects] objectAtIndex:1] childNodes] objectAtIndex:0] childNodes].count == 0,
		      "leafKeyPath stops the build without asking for children");
		[controller setLeafKeyPath:nil];

		/* --------------------------------------------------------------------------------- *
		 * 4. SORT DESCRIPTORS NAME THE MODEL'S KEYS                                           *
		 * --------------------------------------------------------------------------------- */
		[controller setSortDescriptors:
			[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
		check([[[[[controller arrangedObjects] objectAtIndex:0] childNodes] objectAtIndex:0] representedObject] == a
		      && [[[[[controller arrangedObjects] objectAtIndex:0] childNodes] objectAtIndex:1] representedObject] == b,
		      "sortDescriptors order each level by the model's keys");
		[controller setSortDescriptors:nil];
		check([[[[[controller arrangedObjects] objectAtIndex:0] childNodes] objectAtIndex:0] representedObject] == b,
		      "and clearing them restores the model's order");

		/* --------------------------------------------------------------------------------- *
		 * 5. THE SELECTION IS PATHS, AND IT SURVIVES A REBUILD BY IDENTITY                     *
		 * --------------------------------------------------------------------------------- */
		[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, 1, NSNotFound)]];
		check([[controller selectionIndexPath] isEqual:path(0, 1, NSNotFound)], "a selection path is stored");
		check([[controller selectedNodes] count] == 1
		      && [[[controller selectedNodes] objectAtIndex:0] representedObject] == a,
		      "selectedNodes answers the node");
		check([[controller selectedObjects] count] == 1
		      && [[controller selectedObjects] objectAtIndex:0] == a,
		      "and selectedObjects its represented object");
		check([controller contentObject] == a, "so the inherited contentObject is the selected model object");
		{
			BOOL raised = NO;

			@try {
				[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(9, NSNotFound)]];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "a path that names no node is refused");
		}
		[controller setSelectionIndexPaths:
			[NSArray arrayWithObjects:path(0, 1, NSNotFound), path(1, 0, NSNotFound), nil]];
		check([[controller selectedObjects] isEqual:[NSArray arrayWithObjects:a, leafish, nil]],
		      "several paths select several objects");
		[controller removeSelectionIndexPaths:[NSArray arrayWithObject:path(1, 0, NSNotFound)]];
		check([[controller selectionIndexPaths] count] == 1, "removeSelectionIndexPaths: subtracts");
		[controller addSelectionIndexPaths:[NSArray arrayWithObject:path(1, 0, NSNotFound)]];
		check([[controller selectionIndexPaths] count] == 2, "and addSelectionIndexPaths: unions");

		/* **A RE-SORT RENUMBERS THE PATHS; THE SELECTION FOLLOWS THE OBJECT.** */
		[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, 1, NSNotFound)]];
		[controller setSortDescriptors:
			[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
		check([[controller selectedObjects] count] == 1
		      && [[controller selectedObjects] objectAtIndex:0] == a,
		      "preservesSelection keeps the selected OBJECT across a re-sort");
		check(![[controller selectionIndexPath] isEqual:path(0, 1, NSNotFound)],
		      "even though its path moved");
		[controller setSortDescriptors:nil];

		/* --------------------------------------------------------------------------------- *
		 * 6. INSERTING INTO THE MODEL                                                         *
		 * --------------------------------------------------------------------------------- */
		[controller setSelectionIndexPaths:[NSArray array]];
		[controller setAvoidsEmptySelection:NO];
		check([controller canInsert] && [controller canInsertChild], "a mutable content is writable");
		{
			AGNode *fresh = [AGNode node:@"fresh"];

			[controller insertObject:fresh atArrangedObjectIndexPath:path(0, 1, NSNotFound)];
			check([[root1 children] objectAtIndex:1] == fresh,
			      "an arranged-index-path insert lands in the parent's children");
			check([[controller selectedObjects] count] == 1
			      && [[controller selectedObjects] objectAtIndex:0] == fresh,
			      "and selectsInsertedObjects selects it");
			check([[[[[controller arrangedObjects] objectAtIndex:0] childNodes] objectAtIndex:1] representedObject] == fresh,
			      "and the rebuilt arrangement shows it");
		}
		{
			AGNode *extra = [AGNode node:@"extra"];

			[controller insertObject:extra atArrangedObjectIndexPath:path(2, NSNotFound)];
			check([content lastObject] == extra, "a root path appends a root to the content");
		}
		{
			BOOL raised = NO;

			@try {
				[controller insertObject:[AGNode node:@"nowhere"]
				   atArrangedObjectIndexPath:path(0, 7, NSNotFound)];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSRangeException];
			}
			check(raised, "an index past a parent's children raises NSRangeException");
		}

		/* AN IMMUTABLE CHILDREN ARRAY IS A MODEL THAT CANNOT TAKE AN INSERT. */
		{
			AGNode *frozen = [AGNode node:@"frozen"];
			AGNode *immutableChild = [AGNode node:@"immutableChild"];

			[frozen setChildren:[NSArray arrayWithObject:immutableChild]];
			[controller setContent:[NSArray arrayWithObject:frozen]];
			[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, NSNotFound)]];
			check(![controller canInsertChild], "an immutable children array is not writable");
			{
				BOOL raised = NO;

				@try {
					[controller insertObject:[AGNode node:@"nope"]
					   atArrangedObjectIndexPath:path(0, 0, NSNotFound)];
				} @catch (NSException *exception) {
					raised = [[exception name] isEqual:NSInvalidArgumentException];
				}
				check(raised, "so an insert there raises by name");
			}
		}

		/* --------------------------------------------------------------------------------- *
		 * 7. REMOVING FROM THE MODEL                                                          *
		 * --------------------------------------------------------------------------------- */
		[controller setContent:content];
		[controller setSortDescriptors:nil];
		[controller removeObjectAtArrangedObjectIndexPath:path(0, 0, NSNotFound)];
		check(![[root1 children] containsObject:b] && [[root1 children] count] == 2,
		      "removeObjectAtArrangedObjectIndexPath: takes it out of the model");

		[controller setContent:content];
		[root1 setChildren:[NSMutableArray arrayWithObjects:b, a, [AGNode node:@"c"], nil]];
		[controller setContent:content];
		{
			NSArray *two = [NSArray arrayWithObjects:path(0, 0, NSNotFound), path(0, 2, NSNotFound), nil];

			[controller removeObjectsAtArrangedObjectIndexPaths:two];
			check([[root1 children] count] == 1 && [[root1 children] objectAtIndex:0] == a,
			      "several paths remove, from the highest index down");
		}

		[controller setContent:content];
		[root1 setChildren:[NSMutableArray arrayWithObjects:b, a, nil]];
		[controller setContent:content];
		[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, 1, NSNotFound)]];
		[controller remove:nil];
		check([[controller selectedObjects] count] == 0 || ![[controller selectedObjects] containsObject:a],
		      "remove: removes the selected nodes");

		/* --------------------------------------------------------------------------------- *
		 * 8. THE ACTIONS MAKE NEW OBJECTS                                                     *
		 * --------------------------------------------------------------------------------- */
		[controller setContent:[NSMutableArray arrayWithObject:[AGNode node:@"solo"]]];
		[controller setChildrenKeyPath:@"children"];
		[controller setObjectClass:[AGNode class]];
		[controller setAvoidsEmptySelection:NO];
		[controller setSelectionIndexPaths:[NSArray array]];
		check([[controller newObject] isKindOfClass:[AGNode class]], "newObject is the class the controller was told about");
		[controller add:nil];
		check([[controller arrangedObjects] count] == 2, "add: appends a new root");
		[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, NSNotFound)]];
		[controller addChild:nil];
		check([[[[controller arrangedObjects] objectAtIndex:0] childNodes] count] == 1,
		      "addChild: appends under the selected node");
		{
			NSUInteger before;

			[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, NSNotFound)]];
			before = [[controller arrangedObjects] count];
			[controller insertChild:nil];
			check([[controller arrangedObjects] count] == before + 1,
			      "insertChild: inserts a new root at the selection");
		}

		/* --------------------------------------------------------------------------------- *
		 * 9. MOVING                                                                           *
		 * --------------------------------------------------------------------------------- */
		[controller setContent:content];
		[root1 setChildren:[NSMutableArray arrayWithObjects:b, a, nil]];
		[controller setContent:content];
		[controller setSelectionIndexPaths:[NSArray array]];
		{
			NSTreeNode *aNode = [[[controller arrangedObjects] objectAtIndex:0] descendantNodeAtIndexPath:path(1, NSNotFound)];

			[controller moveNode:aNode toIndexPath:path(0, 0, NSNotFound)];
			check([[[root1 children] objectAtIndex:0] isEqual:a],
			      "moveNode:toIndexPath: moves the model object to the destination");
		}
		{
			NSArray *roots = [controller arrangedObjects];
			NSTreeNode *bNode = [[roots objectAtIndex:0] descendantNodeAtIndexPath:path(1, NSNotFound)];

			/* root1's children are now [a, b]; move b into root2's children (currently empty). */
			[controller moveNodes:[NSArray arrayWithObject:bNode] toIndexPath:path(1, 0, NSNotFound)];
			check([[root2 children] count] == 2 && [[root2 children] objectAtIndex:0] == b,
			      "moveNodes:toIndexPath: moves a node to another parent");
			check(![[root1 children] containsObject:b], "and it leaves the old one");
		}

		/* --------------------------------------------------------------------------------- *
		 * 10. THE ANNOUNCEMENTS                                                               *
		 * --------------------------------------------------------------------------------- */
		{
			AGObserver *arrangement = [[AGObserver alloc] init];
			AGObserver *selection = [[AGObserver alloc] init];

			[controller addObserver:arrangement
				     forKeyPath:@"arrangedObjects"
					options:NSKeyValueObservingOptionNew
					context:NULL];
			[controller setChildrenKeyPath:nil];
			check(arrangement->calls == 1, "a criteria change announces arrangedObjects once");
			[controller removeObserver:arrangement forKeyPath:@"arrangedObjects"];

			[controller addObserver:selection
				     forKeyPath:@"selectionIndexPaths"
					options:NSKeyValueObservingOptionNew
					context:NULL];
			[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, NSNotFound)]];
			check(selection->calls == 1, "a selection change announces selectionIndexPaths once");
			[controller removeObserver:selection forKeyPath:@"selectionIndexPaths"];
			[arrangement release];
			[selection release];
		}

		/* --------------------------------------------------------------------------------- *
		 * 11. THE CONTENT KIND, countKeyPath, AND THE PROXY'S FLAG                             *
		 * --------------------------------------------------------------------------------- */
		{
			BOOL raised = NO;

			@try {
				[controller setContent:@"not an array"];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "a content that is not an array is refused");
			[controller setContent:[NSMutableArray arrayWithObject:[AGNode node:@"after"]]];
			check([[controller arrangedObjects] count] == 1,
			      "and the refusal leaves the controller able to arrange the next one");
		}
		[controller setCountKeyPath:@"children"];
		check([[controller countKeyPath] isEqual:@"children"], "countKeyPath is stored and answered");
		check([[controller arrangedObjects] count] == 1,
		      "and builds nothing: children come from childrenKeyPath");
		[controller setChildrenKeyPath:@"children"];
		[controller setSelectionIndexPaths:[NSArray arrayWithObject:path(0, NSNotFound)]];
		[controller setAlwaysUsesMultipleValuesMarker:YES];
		check([[controller selection] valueForKey:@"name"] == NSMultipleValuesMarker,
		      "alwaysUsesMultipleValuesMarker reaches the inherited selection proxy");
		[controller setAlwaysUsesMultipleValuesMarker:NO];
		check([[[controller selection] valueForKey:@"name"] isEqual:@"after"],
		      "and turning it off forwards the selected object's value");

		/* 12. THE DEPTH CAP TRUNCATES A CYCLE RATHER THAN THROWING. */
		{
			AGNode *cycle = [AGNode node:@"cycle"];

			[cycle setChildren:[NSMutableArray arrayWithObject:cycle]];
			[controller setContent:[NSArray arrayWithObject:cycle]];
			[controller setSelectionIndexPaths:[NSArray array]];
			[controller rearrangeObjects];	/* the refusal goes to stderr; the tree is truncated */
			check([[controller arrangedObjects] count] == 1,
			      "a cyclic model is truncated at the depth cap instead of hanging");
		}

		printf("tree_controller: %d case(s) failed\n", s_failed);
		[controller release];
	}
	return s_failed != 0;
}
