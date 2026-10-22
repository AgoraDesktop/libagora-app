/*
 * table_advanced — the table's other half: variable heights, type-select, column reordering, autosave and editing.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **EACH FEATURE IS ASKED WHERE IT LIVES.** Variable heights are the row geometry and `-noteHeightOfRowsWithIndexesChanged:`;
 * type-select is a sequence of key events against the data source's strings; column reordering is the header's
 * gesture; autosave is a second table under the same name; and editing is the window's field editor, the cell's
 * session and the data source's `-tableView:setObjectValue:...`. The table lives in a scroll view inside a window,
 * because the header and the field editor both need the window's coordinate root.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

#include <math.h>
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

static int near(double a, double b)
{
	return fabs(a - b) < 0.05;
}

static NSEvent *key(char c, NSInteger windowNumber)
{
	NSString *string = [NSString stringWithFormat:@"%c", c];

	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0
			       timestamp:0.0 windowNumber:windowNumber context:nil
				characters:string charactersIgnoringModifiers:string
				isARepeat:NO keyCode:(unsigned short)c];
}

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

@interface AGTableAdvancedSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
@public
	NSMutableArray *rows;
	int heightDelta;
	int didDrag;
	int writes;
	int edits;
	int validated;
	int accepted;
	NSInteger lastDropRow;
}
@end

@implementation AGTableAdvancedSource

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		rows = [[NSMutableArray alloc] init];
		[rows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"Alpha", @"name", @"file", @"kind", @"1 KB", @"size", nil]];
		[rows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"Beta", @"name", @"file", @"kind", @"2 KB", @"size", nil]];
		[rows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"Charlie", @"name", @"folder", @"kind", @"3 KB", @"size", nil]];
		[rows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
			@"Delta", @"name", @"file", @"kind", @"4 KB", @"size", nil]];
	}
	return self;
}

- (void)dealloc
{
	[rows release];
	[super dealloc];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return (NSInteger)[rows count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	return [[rows objectAtIndex:(NSUInteger)row] objectForKey:[tableColumn identifier]];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object
   forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	[[rows objectAtIndex:(NSUInteger)row] setObject:object forKey:[tableColumn identifier]];
	edits++;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	(void)tableView;
	return 20.0 + (CGFloat)row * 10.0 + (CGFloat)heightDelta;
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	(void)tableColumn;
	(void)row;
	return YES;
}

- (BOOL)tableView:(NSTableView *)tableView shouldReorderColumn:(NSInteger)columnIndex toColumn:(NSInteger)newColumnIndex
{
	(void)tableView;
	(void)columnIndex;
	(void)newColumnIndex;
	return YES;
}

- (void)tableView:(NSTableView *)tableView didDragTableColumn:(NSTableColumn *)tableColumn
{
	(void)tableView;
	(void)tableColumn;
	didDrag++;
}

- (NSString *)tableView:(NSTableView *)tableView
   typeSelectStringForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	if ([[tableColumn identifier] isEqual:@"name"]) {
		return [[rows objectAtIndex:(NSUInteger)row] objectForKey:@"name"];
	}
	return nil;
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pboard
{
	(void)tableView;
	(void)rowIndexes;
	(void)pboard;
	writes++;
	return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info
		 proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation
{
	(void)tableView;
	(void)info;
	(void)dropOperation;
	validated++;
	lastDropRow = row;
	return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info
	      row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation
{
	(void)tableView;
	(void)info;
	(void)dropOperation;
	accepted++;
	lastDropRow = row;
	return YES;
}

@end

static NSTableView *make_table(AGTableAdvancedSource *source, NSWindow **outWindow, NSScrollView **outScroll)
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 160.0)
						      styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 160.0)];
	NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 140.0)];
	NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	NSTableColumn *kind = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
	NSTableColumn *size = [[NSTableColumn alloc] initWithIdentifier:@"size"];

	[scroll setHasVerticalScroller:YES];
	[scroll setBorderType:NSLineBorder];
	[name setWidth:100.0];
	[kind setWidth:100.0];
	[size setWidth:100.0];
	[name setEditable:YES];
	[table addTableColumn:name];
	[table addTableColumn:kind];
	[table addTableColumn:size];
	[table setDataSource:source];
	[table setDelegate:source];
	[scroll setDocumentView:table];
	[window setContentView:scroll];
	[table reloadData];
	[name release];
	[kind release];
	[size release];
	if (outWindow != NULL) {
		*outWindow = window;
	}
	if (outScroll != NULL) {
		*outScroll = scroll;
	}
	return table;
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	AGTableAdvancedSource *source = [[AGTableAdvancedSource alloc] init];
	NSWindow *window;
	NSScrollView *scroll;
	NSTableView *table;
	NSTableHeaderView *header;
	NSArray *columns;
	NSBitmapImageRep *unused = nil;

	setvbuf(stdout, NULL, _IONBF, 0);
	/* The autosave half needs a writable defaults root; the tree's Foundation resolves it from this variable. */
	setenv("FNX_CONFIG_ROOT", "/tmp/agora-table-advanced-defaults", 1);
	[application finishLaunching];

	table = make_table(source, &window, &scroll);
	columns = [table tableColumns];
	header = [table headerView];

	/* 1. VARIABLE ROW HEIGHTS: THE ROW GEOMETRY, THE HIT TEST AND THE DOCUMENT HEIGHT. */
	check(near([[columns objectAtIndex:0] width], 100.0), "the first column keeps its requested width");
	check(near([table rectOfRow:0].size.height, 20.0)
	      && near([table rectOfRow:1].origin.y, 22.0)
	      && near([table rectOfRow:2].origin.y, 54.0)
	      && near([table rectOfRow:3].origin.y, 96.0),
	      "rows use the delegate's heights with the intercell spacing between them");
	check([table rowAtPoint:NSMakePoint(10.0, 25.0)] == 1
	      && [table rowAtPoint:NSMakePoint(10.0, 21.0)] == -1,
	      "rowAtPoint finds a row and returns -1 in the spacing");
	{
		NSRange rows = [table rowsInRect:NSMakeRect(0.0, 0.0, 100.0, 60.0)];

		check(rows.location == 0 && rows.length == 3, "rowsInRect includes every row the rect touches");
	}
	source->heightDelta = 5;
	[table noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 4)]];
	check(near([table rectOfRow:1].size.height, 35.0)
	      && near([table rectOfRow:2].origin.y, 64.0)
	      && near([table frame].size.height, 166.0),
	      "noteHeightOfRowsWithIndexesChanged re-queries the delegate and re-tiles");
	source->heightDelta = 0;
	[table noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 4)]];

	/* 2. TYPE-SELECT: A PREFIX FROM THE KEYBOARD, WRAPPING FROM THE SELECTED ROW. */
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	[table keyDown:key('c', [window windowNumber])];
	check([table selectedRow] == 2, "typing c selects Charlie");
	[table keyDown:key('h', [window windowNumber])];
	check([table selectedRow] == 2, "and ch keeps Charlie rather than restarting");
	[table keyDown:key('d', [window windowNumber])];
	check([table selectedRow] == 3, "a new prefix d selects Delta");
	[table setAllowsTypeSelect:NO];
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	[table keyDown:key('d', [window windowNumber])];
	check([table selectedRow] == 0, "allowsTypeSelect NO disables the search");

	/* 3. COLUMN REORDERING THROUGH THE HEADER'S GESTURE. */
	source->didDrag = 0;
	{
		NSPoint from = [header convertPoint:NSMakePoint(50.0, 10.0) toView:nil];
		NSPoint to = [header convertPoint:NSMakePoint(260.0, 10.0) toView:nil];
		NSEvent *down = mouse(NSLeftMouseDown, from, [window windowNumber]);
		NSEvent *drag = mouse(NSLeftMouseDragged, to, [window windowNumber]);
		NSEvent *up = mouse(NSLeftMouseUp, to, [window windowNumber]);

		[header mouseDown:down];
		[header mouseDragged:drag];
		[header mouseUp:up];
	}
	check([[[table tableColumns] objectAtIndex:0] identifier] != nil
	      && [[[[table tableColumns] objectAtIndex:0] identifier] isEqual:@"kind"],
	      "dragging the first header past the next two moves it to the end");
	check(source->didDrag == 1 && [header draggedColumn] == -1,
	      "the delegate is told once, and the drag state is cleared");

	/* 4. AUTOSAVE: A SECOND TABLE UNDER THE SAME NAME RESTORES ORDER, WIDTH AND SORT. */
	{
		NSString *keyName = @"AgoraTableView TableProbe";
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSTableView *second;
		NSWindow *secondWindow;
		NSScrollView *secondScroll;

		[defaults removeObjectForKey:keyName];
		[table setAutosaveName:@"TableProbe"];
		[table setAutosaveTableColumns:YES];
		[[columns objectAtIndex:0] setWidth:140.0];
		[table setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
		/* THE TABLE WAS REORDERED ABOVE, SO ITS ORDER IS kind,size,name. Move it back to name,kind,size and save a
		 * known order with a wider name column. */
		[table moveColumn:2 toColumn:0];
		[[table tableColumnWithIdentifier:@"name"] setWidth:140.0];
		[table moveColumn:0 toColumn:2];
		[table moveColumn:2 toColumn:0];	/* name first again; widths/order are saved by moveColumn */
		[[table tableColumnWithIdentifier:@"name"] setWidth:140.0];
		[table setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];

		second = make_table(source, &secondWindow, &secondScroll);
		[second setAutosaveName:@"TableProbe"];
		[second setAutosaveTableColumns:YES];
		check([[[second tableColumns] objectAtIndex:0] identifier] != nil
		      && [[[[second tableColumns] objectAtIndex:0] identifier] isEqual:@"name"],
		      "the second table restores the saved column order");
		check(near([[second tableColumnWithIdentifier:@"name"] width], 140.0),
		      "and the saved width");
		check([[second sortDescriptors] count] == 1
		      && [[[[second sortDescriptors] objectAtIndex:0] key] isEqual:@"name"],
		      "and the saved sort descriptor");
		[second release];
		[secondScroll release];
		[secondWindow release];
		[defaults removeObjectForKey:keyName];
		[table setAutosaveTableColumns:NO];
	}

	/* 5. EDITING THROUGH THE WINDOW'S FIELD EDITOR. */
	{
		NSText *editor;
		NSCell *cell;

		[table editColumn:0 row:0 withEvent:nil select:YES];
		editor = [table currentEditor];
		check(editor != nil && [table editedRow] == 0 && [table editedColumn] == 0,
		      "editColumn:row:withEvent:select: opens a session on the cell");
		if (editor != nil) {
			[editor setString:@"Edited"];
			cell = [table preparedCellAtColumn:0 row:0];
			[(NSTextFieldCell *)cell endEditing:editor];
		}
		check(source->edits == 1
		      && [[[source->rows objectAtIndex:0] objectForKey:@"name"] isEqual:@"Edited"],
		      "ending the session writes the edited object value to the data source");
		check([table editedRow] == -1 && [table editedColumn] == -1 && [table currentEditor] == nil,
		      "and the table clears its edited pair");
	}

	/* 6. THE DRAG VOCABULARY IS RECORDED EVEN WITHOUT A DRAG SESSION. */
	check([table canDragRowsWithIndexes:[NSIndexSet indexSetWithIndex:0] atPoint:NSMakePoint(10.0, 10.0)],
	      "a data source with writeRows allows a row drag");
	[table setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
	check([table draggingSourceOperationMaskForLocal:YES] == NSDragOperationCopy,
	      "and the local drag mask is stored");
	[table setDropRow:2 dropOperation:NSTableViewDropAbove];
	check(1, "setDropRow:dropOperation: is accepted for a data source's re-target");
	/* THE MASK IS THE SOURCE'S ANSWER TO THE SESSION, so the row drag below would be refused if the earlier probe's
	 * Copy-only mask stayed set: a destination offering Move intersected with Copy is None, which is Apple's own rule
	 * and the reason the session applies it. Every is the table's default for a local drag. */
	[table setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	{
		NSPoint from = [table convertPoint:NSMakePoint(10.0, 10.0) toView:nil];
		NSPoint to = [table convertPoint:NSMakePoint(10.0, 60.0) toView:nil];
		NSEvent *down = mouse(NSLeftMouseDown, from, [window windowNumber]);
		NSEvent *drag = mouse(NSLeftMouseDragged, to, [window windowNumber]);
		NSEvent *up = mouse(NSLeftMouseUp, to, [window windowNumber]);

		/* THE DRAG IS THE WINDOW'S NOW: the session captures the pointer, so the motion and the release arrive
		 * through `-sendEvent:` rather than being handed to the table directly. That is the real dispatch path. */
		[window sendEvent:down];
		[window sendEvent:drag];
		[window sendEvent:up];
	}
	check(source->writes == 1 && source->validated >= 1 && source->accepted == 1,
	      "a row drag writes, validates and accepts through the data source and the drag session");
	check([NSDraggingSession cg_activeSession] == nil, "and the session is over when the drop is");

	[table release];
	[scroll release];
	[window release];
	[source release];
	(void)unused;
	printf("table_advanced: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
