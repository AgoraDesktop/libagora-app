/*
 * browser — columns of rows, and the selection that opens the next column.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE PUBLIC CONTRACT IS THE DELEGATE'S.** A column asks how many rows it has; a row's cell is filled by
 * `-browser:willDisplayCell:atRow:column:`; selecting a row loads the column to its right; a leaf has no right-hand
 * column. Offscreen: the browser's private tables are asked through the tier's seams, and the path is the selected
 * cells' strings.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>
#import <Foundation/NSIndexSet.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSWindow.h>
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

@interface AGNode : NSObject
{
@public
	NSString *name;
	BOOL leaf;
	NSMutableArray *children;
}
@end

@implementation AGNode
- (instancetype)initWithName:(NSString *)aName leaf:(BOOL)isLeaf
{
	self = [super init];
	if (self != nil) {
		name = [aName copy];
		leaf = isLeaf;
		children = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[name release];
	[children release];
	[super dealloc];
}
@end

@interface AGBrowserProbe : NSObject <NSBrowserDelegate>
{
@public
	NSArray *roots;
	int selections;
	int displays;
}
@end

@implementation AGBrowserProbe
- (instancetype)init
{
	AGNode *a;
	AGNode *b;
	AGNode *c;
	AGNode *a1;
	AGNode *a2;
	AGNode *leaf;

	self = [super init];
	if (self != nil) {
		a = [[AGNode alloc] initWithName:@"A" leaf:NO];
		b = [[AGNode alloc] initWithName:@"B" leaf:YES];
		c = [[AGNode alloc] initWithName:@"C" leaf:NO];
		a1 = [[AGNode alloc] initWithName:@"A1" leaf:NO];
		a2 = [[AGNode alloc] initWithName:@"A2" leaf:YES];
		leaf = [[AGNode alloc] initWithName:@"leaf" leaf:YES];
		[a1->children addObject:leaf];
		[a->children addObject:a1];
		[a->children addObject:a2];
		roots = [[NSArray alloc] initWithObjects:a, b, c, nil];
		[a release];
		[b release];
		[c release];
		[a1 release];
		[a2 release];
		[leaf release];
	}
	return self;
}
- (void)dealloc
{
	[roots release];
	[super dealloc];
}
- (AGNode *)nodeAtRow:(NSInteger)row column:(NSInteger)column browser:(NSBrowser *)browser
{
	if (column == 0) {
		return [roots objectAtIndex:(NSUInteger)row];
	}
	{
		NSInteger parentRow = [browser selectedRowInColumn:column - 1];
		AGNode *parent;

		if (parentRow < 0 || parentRow >= (NSInteger)[roots count]) {
			return nil;
		}
		parent = [self nodeAtRow:parentRow column:column - 1 browser:browser];
		return (row < (NSInteger)[parent->children count]) ? [parent->children objectAtIndex:(NSUInteger)row] : nil;
	}
}
- (NSInteger)browser:(NSBrowser *)browser numberOfRowsInColumn:(NSInteger)column
{
	if (column == 0) {
		return (NSInteger)[roots count];
	}
	{
		NSInteger parentRow = [browser selectedRowInColumn:column - 1];
		AGNode *parent;
		NSInteger rows = 0;

		if (parentRow < 0 || parentRow >= (NSInteger)[roots count]) {
			return 0;
		}
		parent = [self nodeAtRow:parentRow column:column - 1 browser:browser];
		rows = (parent != nil && !parent->leaf) ? (NSInteger)[parent->children count] : 0;
		return rows;
	}
}
- (void)browser:(NSBrowser *)browser willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column
{
	AGNode *node = [self nodeAtRow:row column:column browser:browser];

	displays++;
	if (node != nil) {
		[cell setStringValue:node->name];
		[cell setLeaf:node->leaf];
		[cell setLoaded:YES];
	}
}
- (BOOL)browser:(NSBrowser *)browser selectRow:(NSInteger)row inColumn:(NSInteger)column
{
	(void)browser;
	(void)row;
	(void)column;
	selections++;
	return YES;
}
@end

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSBrowser *browser;
	AGBrowserProbe *probe;
	NSWindow *window;
	NSTableView *table;
	NSBrowserCell *cell;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];
	browser = [[NSBrowser alloc] initWithFrame:NSMakeRect(0.0, 0.0, 600.0, 300.0)];
	probe = [[AGBrowserProbe alloc] init];
	[browser setDelegate:probe];
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 600.0, 300.0)
					     styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	[window setContentView:browser];
	[browser loadColumnZero];

	check([browser cg_columnCount] == 1, "loadColumnZero makes exactly one column");
	table = [browser cg_tableForColumn:0];
	check(table != nil && [table numberOfRows] == 3, "the first column has the root's three rows");
	check([browser selectedColumn] == -1 && [browser selectedRowInColumn:0] == -1,
	      "and nothing is selected at birth");

	check([[table preparedCellAtColumn:0 row:0] isKindOfClass:[NSBrowserCell class]],
	      "a row is drawn by an NSBrowserCell");
	cell = (NSBrowserCell *)[table preparedCellAtColumn:0 row:0];
	check([[cell stringValue] isEqual:@"A"] && ![cell isLeaf],
	      "the cell's title is the delegate's and A is a branch");
	cell = (NSBrowserCell *)[table preparedCellAtColumn:0 row:1];
	check([[cell stringValue] isEqual:@"B"] && [cell isLeaf], "B is a leaf");

	[browser selectRow:0 inColumn:0];
	check([browser selectedColumn] == 0 && [browser selectedRowInColumn:0] == 0,
	      "selecting a row records the column and the row");
	check([browser cg_columnCount] == 2 && [[browser cg_tableForColumn:1] numberOfRows] == 2,
	      "and loads the selected branch's two children into column 1");
	check([[browser path] isEqual:@"A"], "the path is the selected cell's title");

	[browser selectRow:0 inColumn:1];
	check([browser cg_columnCount] == 3 && [[browser cg_tableForColumn:2] numberOfRows] == 1,
	      "selecting A1 loads its one child");
	check([[browser path] isEqual:@"A/A1"], "and the path follows both columns");

	[browser selectRow:0 inColumn:2];
	check([browser cg_columnCount] == 3, "a leaf adds no column to its right");
	check([browser selectedColumn] == 2 && [[[browser selectedCell] stringValue] isEqual:@"leaf"],
	      "the leaf is the selected cell");
	check([[browser path] isEqual:@"A/A1/leaf"], "and the path reaches the leaf");

	[browser reloadColumn:0];
	check([browser selectedColumn] == 0 && [browser selectedRowInColumn:0] == 0,
	      "reloading a column keeps a still-valid selection");
	check([browser cg_columnCount] == 2, "and rebuilds the column to its right");

	[browser setPath:@"C"];
	check([[browser path] isEqual:@"C"] && [browser selectedRowInColumn:0] == 2,
	      "setPath selects the row whose cell carries the component");
	[browser setPath:@"A/A1/leaf"];
	check([[browser path] isEqual:@"A/A1/leaf"], "and a multi-component path walks the columns");

	[browser setColumnWidth:120.0];
	check([browser columnWidth] == 120.0
	      && [[[browser cg_tableForColumn:0] tableColumns] count] == 1
	      && [[[[browser cg_tableForColumn:0] tableColumns] objectAtIndex:0] width] == 120.0,
	      "the column width reaches the private table's column");
	check(probe->displays > 0 && probe->selections > 0,
	      "the delegate was asked to display cells and to allow selections");

	[window release];
	[browser release];
	[probe release];
	printf("browser: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
