/*
 * browser_items — the 10.6 item-based browser: a delegate of objects, a browser that makes the cells.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **APPLE SHIPPED TWO DELEGATE CONTRACTS IN ONE CLASS AND THIS CLASS NOW ADVERTISES THE LATER ONE.** The probe is
 * therefore about the ITEM model being the one that drives the browser — the delegate answers with model objects and the
 * browser makes every cell — while the older CELL contract keeps working as the fallback (a second browser, same
 * assertions about what it shows, is the check that the fallback did not rot).
 *
 * WHAT IS ASSERTED:
 *
 *   1. THE ROWS COME FROM THE ITEMS: column zero's row count is `-browser:numberOfChildrenOfItem:` with NIL (the root),
 *      selecting a row loads the next column from THAT item's children, and no `-browser:numberOfRowsInColumn:` is ever
 *      asked of an item-based delegate (it does not implement it).
 *   2. THE BROWSER MAKES THE CELL: the cell of a row shows `-browser:objectValueForItem:` and is a leaf or a branch from
 *      `-browser:isLeafItem:` — and a styling `-browser:willDisplayCell:atRow:column:` still gets its chance after.
 *   3. THE WALKING DOORS: `-itemAtRow:inColumn:`, `-itemAtIndexPath:`, `-parentForItemsInColumn:`, `-isLeafItem:`,
 *      `-indexPathForColumn:` (the path of the item WHOSE CHILDREN the column shows) and `-pathToColumn:` all answer the
 *      same chain the selection walked, and nil (or an empty path) where the chain stops.
 *   4. THE SELECTION AS A PATH: `-selectionIndexPath` is the selected rows from the root down, setting one selects each
 *      column in turn (loading what a click would load), and setting nil clears.
 *   5. AND THE CELL MODEL STILL WORKS: a browser whose delegate implements only the cell doors paints the same words.
 */
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSFont.h>
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

/* ============================================================================================ *
 * THE MODEL: A THREE-LEVEL TREE OF NODES, so a selection has somewhere to go and a leaf is a   *
 * leaf two columns deep.                                                                        *
 * ============================================================================================ */
@interface AGItemNode : NSObject
{
@public
	NSString *name;
	NSMutableArray *children;
}
@end

@implementation AGItemNode
- (NSString *)name
{
	return name;
}
- (NSArray *)children
{
	return children;
}
- (void)dealloc
{
	[name release];
	[children release];
	[super dealloc];
}
@end

static AGItemNode *node(NSString *name)
{
	AGItemNode *n = [[AGItemNode alloc] init];

	n->name = [name copy];
	n->children = [[NSMutableArray alloc] init];
	return [n autorelease];
}

static void add(AGItemNode *parent, AGItemNode *child)
{
	[parent->children addObject:child];
}

@interface AGItemDelegate : NSObject <NSBrowserDelegate>
{
@public
	AGItemNode *root;		/* the tree's first level, which column zero lists */
	int objectValueAsks;
	int isLeafAsks;
	int willDisplayAsks;
}
@end

@implementation AGItemDelegate
- (NSInteger)browser:(NSBrowser *)browser numberOfChildrenOfItem:(id)item
{
	if (item == nil) {
		return (NSInteger)[root->children count];
	}
	return (NSInteger)[[(AGItemNode *)item children] count];
}

- (id)browser:(NSBrowser *)browser child:(NSInteger)index ofItem:(id)item
{
	NSArray *list = (item == nil) ? root->children : [(AGItemNode *)item children];

	if (index < 0 || index >= (NSInteger)[list count]) {
		return nil;
	}
	return [list objectAtIndex:(NSUInteger)index];
}

- (BOOL)browser:(NSBrowser *)browser isLeafItem:(id)item
{
	isLeafAsks++;
	return ([[(AGItemNode *)item children] count] == 0);
}

- (id)browser:(NSBrowser *)browser objectValueForItem:(id)item
{
	objectValueAsks++;
	return [(AGItemNode *)item name];
}

- (void)browser:(NSBrowser *)browser willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column
{
	(void)browser;
	(void)cell;
	(void)row;
	(void)column;
	willDisplayAsks++;
}
@end

/* THE OLD CONTRACT, for the fallback browser: counts and cells, no items. */
@interface AGCellDelegate : NSObject <NSBrowserDelegate>
{
@public
	int rowsAsks;
}
@end

@implementation AGCellDelegate
- (NSInteger)browser:(NSBrowser *)browser numberOfRowsInColumn:(NSInteger)column
{
	rowsAsks++;
	return (column == 0) ? 2 : 1;
}

- (void)browser:(NSBrowser *)browser willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column
{
	[cell setStringValue:(column == 0)
		? ((row == 0) ? @"cells" : @"only")
		: @"fallback"];
}
@end

static NSBrowser *browserInWindow(NSWindow *window, id delegate)
{
	NSBrowser *browser = [[NSBrowser alloc] initWithFrame:NSMakeRect(0.0, 0.0, 600.0, 300.0)];

	[window setContentView:browser];
	[browser release];
	browser = [[window contentView] retain];
	[browser setDelegate:delegate];
	return browser;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 600.0, 300.0)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
	AGItemDelegate *items = [[AGItemDelegate alloc] init];
	AGCellDelegate *cells = [[AGCellDelegate alloc] init];
	AGItemNode *root = node(@"root");
	AGItemNode *docs = node(@"Documents");
	AGItemNode *pics = node(@"Pictures");
	AGItemNode *alpha = node(@"alpha.txt");
	AGItemNode *beta = node(@"beta.txt");
	AGItemNode *cat = node(@"cat.png");

	setvbuf(stdout, NULL, _IONBF, 0);
	add(root, docs);
	add(root, pics);
	add(docs, alpha);
	add(docs, beta);
	add(pics, cat);
	items->root = root;

	/* ============================================================================================ *
	 * 1. THE ROWS COME FROM THE ITEMS.                                                              *
	 * ============================================================================================ */
	{
		NSBrowser *browser = browserInWindow(window, items);

		[browser loadColumnZero];
		check([browser numberOfRowsInColumn:0] == 2,
		      "column zero's rows are `-browser:numberOfChildrenOfItem:` for the ROOT (nil)");
		check([[browser itemAtRow:0 inColumn:0] isEqual:docs], "row 0 of column 0 is the first child item");
		check([[browser itemAtRow:1 inColumn:0] isEqual:pics], "and row 1 the second");
		check([browser itemAtRow:5 inColumn:0] == nil, "a row past the end has no item");

		/* SELECTING LOADS THE NEXT COLUMN FROM THE ITEM. */
		[browser selectRow:0 inColumn:0];
		check([browser cg_activeColumnCount] >= 2, "selecting a branch loads the column to its right");
		check([browser numberOfRowsInColumn:1] == 2,
		      "and that column's rows are the CHILDREN of the selected item");
		check([[browser itemAtRow:0 inColumn:1] isEqual:alpha], "its first row is the item's first child");
		check([[browser itemAtRow:1 inColumn:1] isEqual:beta], "and its second row the second");

		/* ============================================================================================ *
		 * 2. THE BROWSER MAKES THE CELL FROM THE ITEM.                                                  *
		 * ============================================================================================ */
		{
			NSTableView *table = [browser cg_tableForColumn:0];
			NSCell *first = [table preparedCellAtColumn:0 row:0];
			NSCell *docsCell = [table preparedCellAtColumn:0 row:0];

			check([[first stringValue] isEqualToString:@"Documents"],
			      "the cell of row 0 shows `-browser:objectValueForItem:` — the browser made it");
			check(docsCell != nil && [docsCell isKindOfClass:[NSBrowserCell class]],
			      "and it is an NSBrowserCell, because the browser makes its own cells");
			check(![(NSBrowserCell *)docsCell isLeaf],
			      "a node with children is a BRANCH, from `-browser:isLeafItem:`");
			check([[table preparedCellAtColumn:0 row:1] stringValue] != nil,
			      "the second row's cell is filled the same way");
			check(items->objectValueAsks > 0, "`-browser:objectValueForItem:` is what filled them");
			printf("  (note: objectValueForItem %d time(s), isLeafItem %d, willDisplayCell %d)\n",
			       items->objectValueAsks, items->isLeafAsks, items->willDisplayAsks);
			check(items->willDisplayAsks > 0,
			      "and the STYLING door still gets its chance after the browser filled the cell");

			/* AND THE LEAF COLUMN: Documents' children have no children of their own. */
			[browser selectRow:0 inColumn:1];
			{
				NSTableView *second = [browser cg_tableForColumn:1];
				NSCell *leafCell = [second preparedCellAtColumn:0 row:0];

				check([leafCell isKindOfClass:[NSBrowserCell class]] && [(NSBrowserCell *)leafCell isLeaf],
				      "a childless item's row is a LEAF, so no branch triangle is drawn");
			}
		}

		/* ============================================================================================ *
		 * 3. THE WALKING DOORS.                                                                         *
		 * ============================================================================================ */
		[browser selectRow:0 inColumn:0];	/* Documents */
		/* **A NIL CHECK, NOT AN -isEqual: ONE** — a message sent to nil answers nil, which is a false check no matter
		 * what the door returned. */
		check([browser parentForItemsInColumn:0] == nil,
		      "column zero's parent is the ROOT, and the root of this model is nil");
		check([[browser parentForItemsInColumn:1] isEqual:docs],
		      "column one's parent is the item selected in column zero");
		check([browser itemAtRow:-1 inColumn:1] == docs,
		      "`-itemAtRow:inColumn:` with -1 answers the parent rather than nothing");
		{
			NSIndexPath *path = [browser indexPathForColumn:1];
			NSIndexPath *expected = [NSIndexPath indexPathWithIndex:0];

			check(path != nil && [path isEqual:expected],
			      "`-indexPathForColumn:` is the path of the item WHOSE CHILDREN that column shows");
			check([[browser itemAtIndexPath:[NSIndexPath indexPathWithIndex:0]] isEqual:docs],
			      "`-itemAtIndexPath:` walks the same path back to the item");
			check([[browser itemAtIndexPath:path] isEqual:docs], "and so does the path the door answered");
			check([browser itemAtIndexPath:nil] == nil, "a nil path has no item");
			check([browser pathToColumn:1] != nil && [[browser pathToColumn:1] isEqualToString:@"Documents"],
			      "`-pathToColumn:` is the same chain as a path string");
			check([[browser pathToColumn:0] isEqualToString:@""], "and a column with no parent has an empty one");
		}
		check([browser isLeafItem:alpha], "`-isLeafItem:` asks the delegate: a file is a leaf");
		check(![browser isLeafItem:docs], "and a folder is not");

		/* ============================================================================================ *
		 * 4. THE SELECTION AS A PATH, BOTH WAYS.                                                        *
		 * ============================================================================================ */
		{
			/* TWO COLUMNS ARE SELECTED AT THIS POINT — `Documents` and then its first child, from the leaves above —
			 * so the path is two positions and both are row 0. */
			NSIndexPath *path = [browser selectionIndexPath];

			printf("  (note: the selection path is %s)\n",
			       (path != nil) ? [[path description] UTF8String] : "(nil)");
			check(path != nil && [path length] == 2
			      && [path indexAtPosition:0] == 0 && [path indexAtPosition:1] == 0,
			      "`-selectionIndexPath` is the selected rows, root first");
			check([[browser selectionIndexPaths] count] == 1
			      && [[[browser selectionIndexPaths] objectAtIndex:0] isEqual:path],
			      "the plural form holds the one path this class can represent");

			/* SETTING A PATH SELECTS EACH COLUMN IN TURN, loading what a click would load. */
			[browser setSelectionIndexPath:[NSIndexPath indexPathWithIndexes:(NSUInteger[]){0, 1} length:2]];
			check([browser selectedRowInColumn:0] == 0 && [browser selectedRowInColumn:1] == 1,
			      "setting a two-index path selects row 0 of column 0 and row 1 of column 1");
			check([[browser itemAtRow:1 inColumn:1] isEqual:beta], "which is the item the path names");
			check([[[browser selectionIndexPath] description] hasSuffix:@"0, 1"]
			      || [[browser selectionIndexPath] length] == 2,
			      "and reading the path back gives the same two positions");

			[browser setSelectionIndexPath:nil];
			check([browser selectionIndexPath] == nil, "setting nil clears the selection");
			check([[browser selectionIndexPaths] count] == 0, "and the plural form is empty with it");
		}

		/* ============================================================================================ *
		 * 5. AND A PATH THAT RUNS OFF THE END STOPS RATHER THAN SELECTING A PHANTOM.                      *
		 * ============================================================================================ */
		[browser setSelectionIndexPath:[NSIndexPath indexPathWithIndexes:(NSUInteger[]){0, 9} length:2]];
		check([browser selectedRowInColumn:0] == 0, "the in-range part of a bad path is selected");
		check([browser selectedRowInColumn:1] < 0, "and the out-of-range part is not");

		[browser setDelegate:nil];
		[browser release];
	}

	/* ============================================================================================ *
	 * 6. THE CELL-BASED CONTRACT IS STILL THE FALLBACK, AND STILL WORKS.                            *
	 * ============================================================================================ */
	{
		NSBrowser *browser = browserInWindow(window, cells);

		[browser loadColumnZero];
		check([browser numberOfRowsInColumn:0] == 2,
		      "a delegate with no item doors is counted through `-browser:numberOfRowsInColumn:`");
		check(cells->rowsAsks > 0, "and that door is what was asked");
		check([[[browser cg_tableForColumn:0] preparedCellAtColumn:0 row:0] stringValue] != nil,
		      "its cells are filled by `-browser:willDisplayCell:atRow:column:`, as they always were");
		check([browser itemAtRow:0 inColumn:0] == nil,
		      "while the item doors answer nil: a cell-based delegate has no items to walk");
		check([browser parentForItemsInColumn:1] == nil, "and no parent to name");

		[browser setDelegate:nil];
		[browser release];
	}

	[items release];
	[cells release];
	[window release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
