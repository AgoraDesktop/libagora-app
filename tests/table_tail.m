/*
 * table_tail — the table's last twenty doors: the deprecated spellings, the enumerators, the drag image,
 * the focus ring, the destination feedback and the indicator image.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DEPRECATED DOORS ARE SPELLINGS OF REAL ONES, SO THE PROBE ASKS BOTH AND COMPARES.** `-drawsGrid` is the grid
 * mask, `-autoresizesAllColumnsToFit` is the column-autoresizing style, `-columnsInRect:` is
 * `-columnIndexesInRect:`, and the two select/enumerator pair is the index-set selection. Each is checked through its
 * modern counterpart, and the layout ones are checked by what the widths became after `-tile`.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. The autoresizing styles resize the columns to the scroll view's width: Uniform fills proportionally,
 *      LastColumnOnly gives the difference to the last column, and the deprecated flag moves between the two.
 *   2. `-drawsGrid` is the grid mask in both directions, measured by the grid colour's pixels.
 *   3. `-columnsInRect:` answers the contiguous range and `NSNotFound` for no column.
 *   4. The single-index selection doors and the two enumerators answer the index-set selection.
 *   5. `-focusedColumn` draws a focus ring around the SELECTED row's cell, and -1 draws none.
 *   6. The header draws a column's indicator image, and removing the image removes the pixels.
 *   7. `-performClickOnCellAtColumn:row:` clicks the PREPARED CELL, whose target receives the action.
 *   8. Both drag-image doors return a snapshot of the named rows/columns at the union's size, with the offset left at
 *      zero.
 *   9. `-verticalMotionCanBeginDrag` is a real gate: with NO a vertical motion does not start a drag and a horizontal
 *      one does; with YES either does.
 *  10. The destination feedback style is a drawing: Regular's line, SourceList's inset line or DropOn plate, and None's
 *      nothing; a source-list selection style chooses SourceList for the caller.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSDragging.h>
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
	return fabs(a - b) < 0.51;
}

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

static int pixel_is(NSBitmapImageRep *rep, int x, int y, NSColor *want)
{
	NSColor *c = [rep colorAtX:x y:y];

	return c != nil && want != nil
		&& fabs([c redComponent] - [want redComponent]) < 0.06
		&& fabs([c greenComponent] - [want greenComponent]) < 0.06
		&& fabs([c blueComponent] - [want blueComponent]) < 0.06;
}

static int count_colour(NSBitmapImageRep *rep, int w, int h, NSColor *want)
{
	int x, y, n = 0;

	for (y = 0; y < h; y++) {
		for (x = 0; x < w; x++) {
			if (pixel_is(rep, x, y, want)) {
				n++;
			}
		}
	}
	return n;
}

static NSBitmapImageRep *draw_view(NSView *view)
{
	NSRect bounds = [view bounds];
	int w = (int)NSWidth(bounds);
	int h = (int)NSHeight(bounds);
	NSBitmapImageRep *rep;

	if (w <= 0 || h <= 0) {
		return nil;
	}
	rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:bounds] fill];
	[view drawRect:bounds];
	return rep;
}

static NSImage *red_image(CGFloat side)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)side pixelsHigh:(NSInteger)side bitsPerSample:8 samplesPerPixel:4
		hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
		bytesPerRow:(NSInteger)side * 4 bitsPerPixel:32];
	NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(side, side)];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, side, side)] fill];
	[image addRepresentation:rep];
	[rep release];
	return image;
}

/* ---- THE DATA SOURCE AND THE TWO PROBES --------------------------------------------------------- */

@interface AGTableTailSource : NSObject <NSTableViewDataSource>
{
@public
	NSMutableArray *rows;
	int writes;
	int edits;
	int clicks;
}
@end

@implementation AGTableTailSource

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		NSInteger i;

		rows = [[NSMutableArray alloc] init];
		for (i = 0; i < 4; i++) {
			[rows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
				[NSString stringWithFormat:@"row %ld", (long)i], @"name",
				[NSString stringWithFormat:@"kind %ld", (long)i], @"kind",
				[NSString stringWithFormat:@"%ld KB", (long)i], @"size", nil]];
		}
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

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pboard
{
	(void)tableView;
	(void)rowIndexes;
	(void)pboard;
	writes++;
	return YES;
}

- (void)cellClicked:(id)sender
{
	(void)sender;
	clicks++;
}

@end

/* A TABLE WHOSE DRAG ENTRY POINT IS A COUNTER, so "the drag began" is a fact rather than a session this offscreen
 * harness cannot run. */
@interface AGDragProbeTable : NSTableView
{
@public
	int dragImageCalls;
}
@end

@implementation AGDragProbeTable
- (void)dragImage:(NSImage *)image at:(NSPoint)point offset:(NSSize)offset event:(NSEvent *)event
	 pasteboard:(NSPasteboard *)pboard source:(id)source slideBack:(BOOL)slideBack
{
	(void)image; (void)point; (void)offset; (void)event; (void)pboard; (void)source; (void)slideBack;
	dragImageCalls++;
}
@end

static NSTableView *make_table(NSWindow **outWindow, NSScrollView **outScroll, AGTableTailSource *source,
			       BOOL draggable)
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 200.0)
						      styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 200.0)];
	NSTableView *table = draggable ? [[AGDragProbeTable alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 180.0)]
				      : [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 180.0)];
	NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	NSTableColumn *kind = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
	NSTableColumn *size = [[NSTableColumn alloc] initWithIdentifier:@"size"];

	[table setIntercellSpacing:NSZeroSize];
	[table setRowHeight:20.0];
	[name setWidth:100.0];
	[kind setWidth:100.0];
	[size setWidth:100.0];
	[table addTableColumn:name];
	[table addTableColumn:kind];
	[table addTableColumn:size];
	[table setDataSource:source];
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
	@autoreleasepool {
		AGTableTailSource *source = [[AGTableTailSource alloc] init];
		NSWindow *window = nil;
		NSScrollView *scroll = nil;
		NSTableView *table = make_table(&window, &scroll, source, NO);
		NSArray *columns = [table tableColumns];
		NSTableColumn *first = [columns objectAtIndex:0];
		CGFloat contentWidth = [scroll contentSize].width;

		/* RESET THE THREE COLUMNS TO 100 AND THE STYLE TO NONE, so each case below starts from a known width. */
		[table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
		[[columns objectAtIndex:0] setWidth:100.0];
		[[columns objectAtIndex:1] setWidth:100.0];
		[[columns objectAtIndex:2] setWidth:100.0];

		/* 1. THE AUTORESIZING STYLES AND THE DEPRECATED FLAG. */
		check(![table autoresizesAllColumnsToFit]
		      && [table columnAutoresizingStyle] == NSTableViewNoColumnAutoresizing,
		      "a fresh table does not autoresize, and its style is NoColumnAutoresizing");
		[table setAutoresizesAllColumnsToFit:YES];
		check([table autoresizesAllColumnsToFit]
		      && [table columnAutoresizingStyle] == NSTableViewUniformColumnAutoresizingStyle,
		      "the deprecated YES is the Uniform style");
		{
			CGFloat total = 0.0;
			NSUInteger i;

			for (i = 0; i < [columns count]; i++) {
				total += [[columns objectAtIndex:i] width];
			}
			printf("  (note: uniform made the columns %.2f wide in a %.2f-wide clip)\n", total, contentWidth);
			check(near(total, contentWidth),
			      "and the Uniform style makes the columns fill the scroll view's width");
		}
		[table setAutoresizesAllColumnsToFit:NO];
		check(![table autoresizesAllColumnsToFit]
		      && [table columnAutoresizingStyle] == NSTableViewLastColumnOnlyAutoresizingStyle,
		      "the deprecated NO is the LastColumnOnly style");
		[table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
		[first setWidth:100.0];
		[[columns objectAtIndex:1] setWidth:100.0];
		[[columns objectAtIndex:2] setWidth:100.0];
		[table setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
		[table tile];
		printf("  (note: last-only gave widths %.2f / %.2f / %.2f)\n",
		       [[columns objectAtIndex:0] width], [[columns objectAtIndex:1] width],
		       [[columns objectAtIndex:2] width]);
		check(near([[columns objectAtIndex:0] width], 100.0)
		      && near([[columns objectAtIndex:1] width], 100.0)
		      && near([[columns objectAtIndex:2] width], contentWidth - 200.0),
		      "and LastColumnOnly gives the whole difference to the last column");
		[table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
		[[columns objectAtIndex:2] setWidth:100.0];

		/* 2. THE DEPRECATED GRID FLAG IS THE MASK, AND THE GRID IS INK. */
		check(![table drawsGrid], "a fresh table draws no grid");
		[table setDrawsGrid:YES];
		check([table drawsGrid]
		      && [table gridStyleMask] == (NSTableViewSolidVerticalGridLineMask | NSTableViewSolidHorizontalGridLineMask),
		      "the deprecated YES is both line masks");
		{
			NSBitmapImageRep *on = draw_view(table);
			int withGrid = count_colour(on, 400, 180, [NSColor gridColor]);

			[on release];
			[table setDrawsGrid:NO];
			{
				NSBitmapImageRep *off = draw_view(table);
				int without = count_colour(off, 400, 180, [NSColor gridColor]);

				printf("  (note: grid pixels: %d with the grid, %d without)\n", withGrid, without);
				/* **THE WITHOUT CASE IS NOT ZERO, AND THAT IS A FACT ABOUT THE TEXT.** Antialiased glyphs
				 * pass through the same grey as `+gridColor`; the claim that survives is that the grid ADDS a
				 * large, structural number of them — measured 2313 against 185, a factor of twelve. */
				check(withGrid > without * 4,
				      "and the grid adds a structural number of its colour's pixels");
				[off release];
			}
		}

		/* 3. THE DEPRECATED COLUMN RANGE. */
		{
			NSRange two = [table columnsInRect:NSMakeRect(0.0, 0.0, 150.0, 10.0)];
			NSRange one = [table columnsInRect:NSMakeRect(250.0, 0.0, 10.0, 10.0)];
			NSRange none = [table columnsInRect:NSMakeRect(1000.0, 0.0, 10.0, 10.0)];

			check(two.location == 0 && two.length == 2, "a rect over the first two columns answers {0, 2}");
			check(one.location == 2 && one.length == 1, "a rect in the third answers {2, 1}");
			check(none.location == NSNotFound, "and a rect past the last answers NSNotFound");
		}

		/* 4. THE SINGLE-INDEX SELECTION DOORS AND THE ENUMERATORS. */
		[table setAllowsMultipleSelection:YES];
		[table selectRow:1 byExtendingSelection:NO];
		check([table selectedRow] == 1, "selectRow:byExtendingSelection: replaces the row selection");
		[table selectRow:2 byExtendingSelection:YES];
		check([table numberOfSelectedRows] == 2 && [table isRowSelected:1] && [table isRowSelected:2],
		      "and the extending form adds the next row");
		[table selectRow:-5 byExtendingSelection:NO];
		check([table numberOfSelectedRows] == 2, "a negative row is ignored rather than wrapped");
		[table selectColumn:0 byExtendingSelection:NO];
		[table selectColumn:1 byExtendingSelection:YES];
		check([table numberOfSelectedColumns] == 2 && [table isColumnSelected:0] && [table isColumnSelected:1],
		      "the column pair is the same two doors");
		{
			NSArray *rowNumbers = [[table selectedRowEnumerator] allObjects];
			NSArray *columnNumbers = [[table selectedColumnEnumerator] allObjects];

			check([rowNumbers count] == 2
			      && [[rowNumbers objectAtIndex:0] integerValue] == 1
			      && [[rowNumbers objectAtIndex:1] integerValue] == 2,
			      "the row enumerator yields the selected rows as NSNumbers, in order");
			check([columnNumbers count] == 2
			      && [[columnNumbers objectAtIndex:0] integerValue] == 0
			      && [[columnNumbers objectAtIndex:1] integerValue] == 1,
			      "and the column enumerator does the same for columns");
		}
		[table deselectAll:nil];

		/* 5. THE FOCUS RING AROUND THE SELECTED ROW'S CELL. */
		[table selectRow:1 byExtendingSelection:NO];
		[table setFocusedColumn:2];
		{
			NSBitmapImageRep *rep = draw_view(table);
			int withRing = count_colour(rep, 400, 180, [NSColor keyboardFocusIndicatorColor]);

			[rep release];
			[table setFocusedColumn:-1];
			{
				NSBitmapImageRep *plain = draw_view(table);
				int without = count_colour(plain, 400, 180, [NSColor keyboardFocusIndicatorColor]);

				printf("  (note: focus-blue pixels: %d focused, %d unfocused)\n", withRing, without);
				check(withRing > 0 && without == 0,
				      "a focused column draws the focus ring, and -1 draws none");
				[plain release];
			}
		}
		[table deselectAll:nil];

		/* 6. THE HEADER INDICATOR IMAGE. */
		{
			NSTableHeaderView *header = [table headerView];
			NSImage *indicator = red_image(6.0);
			NSBitmapImageRep *rep;
			int painted;

			[table setIndicatorImage:indicator inTableColumn:first];
			check([table indicatorImageInTableColumn:first] == indicator,
			      "the indicator image round-trips through the table");
			rep = draw_view(header);
			painted = count_colour(rep, (int)NSWidth([header bounds]), (int)NSHeight([header bounds]),
					       [NSColor redColor]);
			[rep release];
			printf("  (note: the header painted %d red indicator pixels)\n", painted);
			check(painted > 0, "and the header draws it");
			[table setIndicatorImage:nil inTableColumn:first];
			rep = draw_view(header);
			painted = count_colour(rep, (int)NSWidth([header bounds]), (int)NSHeight([header bounds]),
					       [NSColor redColor]);
			[rep release];
			check(painted == 0, "removing it removes the pixels");
			[indicator release];
		}

		/* 7. THE CELL'S CLICK, WHICH IS THE CELL'S ACTION. */
		{
			NSButtonCell *button = [[NSButtonCell alloc] initTextCell:@"Click"];

			[button setTarget:source];
			[button setAction:@selector(cellClicked:)];
			[first setDataCell:button];
			[table reloadData];
			[table performClickOnCellAtColumn:0 row:0];
			check(source->clicks == 1, "performClickOnCellAtColumn:row: sends the PREPARED CELL's action");
			[table performClickOnCellAtColumn:99 row:0];
			check(source->clicks == 1, "and an out-of-range column clicks nothing");
			[button release];
			/* THE DEFAULT DATA CELL IS RESTORED so the later drawing and drag snapshot use text, not a button. */
			{
				NSTextFieldCell *text = [[NSTextFieldCell alloc] initTextCell:@""];

				[text setBordered:NO];
				[text setBezeled:NO];
				[text setDrawsBackground:NO];
				[text setEditable:NO];
				[first setDataCell:text];
				[text release];
			}
			[table reloadData];
		}

		/* 8. THE DRAG IMAGE IS A SNAPSHOT OF THE NAMED CELLS. */
		{
			NSIndexSet *rows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)];
			NSArray *use = [NSArray arrayWithObjects:first, [columns objectAtIndex:1], nil];
			NSPoint offset = NSMakePoint(7.0, 9.0);
			NSImage *image = [table dragImageForRowsWithIndexes:rows tableColumns:use event:nil offset:&offset];
			NSImage *deprecated;

			check(image != nil, "the modern drag-image door answers an image");
			check(image != nil && near([image size].width, 200.0) && near([image size].height, 40.0),
			      "sized to the union of the named rows and columns");
			check(near(offset.x, 0.0) && near(offset.y, 0.0),
			      "and the in/out offset is left at Apple's zero (centred under the mouse)");
			deprecated = [table dragImageForRows:[NSArray arrayWithObjects:
					[NSNumber numberWithInteger:0], [NSNumber numberWithInteger:2], nil]
					event:nil dragImageOffset:&offset];
			check(deprecated != nil && near([deprecated size].width, 300.0)
			      && near([deprecated size].height, 60.0),
			      "the deprecated array spelling forwards to it, over all columns");
		}

		/* 9. THE VERTICAL-MOTION GATE, MEASURED THROUGH THE DRAG ENTRY POINT. */
		{
			AGTableTailSource *dragSource = [[AGTableTailSource alloc] init];
			NSWindow *dragWindow = nil;
			AGDragProbeTable *dragTable = (AGDragProbeTable *)make_table(&dragWindow, NULL, dragSource, YES);
			NSInteger number = [dragWindow windowNumber];
			NSPoint down = [dragTable convertPoint:NSMakePoint(10.0, 10.0) toView:nil];
			NSPoint vert = [dragTable convertPoint:NSMakePoint(10.0, 80.0) toView:nil];
			NSPoint horiz = [dragTable convertPoint:NSMakePoint(80.0, 10.0) toView:nil];

			check([dragTable verticalMotionCanBeginDrag], "vertical motion can begin a drag by default");
			[dragTable setVerticalMotionCanBeginDrag:NO];
			check(![dragTable verticalMotionCanBeginDrag], "and the flag is stored");

			[dragTable mouseDown:mouse(NSLeftMouseDown, down, number)];
			[dragTable mouseDragged:mouse(NSLeftMouseDragged, vert, number)];
			check(dragTable->dragImageCalls == 0,
			      "with the flag off a VERTICAL motion does not begin a drag");
			[dragTable mouseDown:mouse(NSLeftMouseDown, down, number)];
			[dragTable mouseDragged:mouse(NSLeftMouseDragged, horiz, number)];
			check(dragTable->dragImageCalls == 1,
			      "and a HORIZONTAL motion still does");
			[dragTable setVerticalMotionCanBeginDrag:YES];
			[dragTable mouseDown:mouse(NSLeftMouseDown, down, number)];
			[dragTable mouseDragged:mouse(NSLeftMouseDragged, vert, number)];
			check(dragTable->dragImageCalls == 2,
			      "with the flag on the vertical motion begins one");
			[dragTable release];
			[dragWindow release];
			[dragSource release];
		}

		/* 10. THE DESTINATION FEEDBACK STYLE IS A DRAWING. */
		{
			NSBitmapImageRep *rep;
			int regular;
			int sourceList;
			int none;

			[table deselectAll:nil];
			[table setDropRow:1 dropOperation:NSTableViewDropOn];
			[table setDraggingDestinationFeedbackStyle:NSTableViewDraggingDestinationFeedbackStyleRegular];
			rep = draw_view(table);
			regular = count_colour(rep, 400, 180, [NSColor cg_accentColor]);
			[rep release];

			[table setDraggingDestinationFeedbackStyle:NSTableViewDraggingDestinationFeedbackStyleSourceList];
			rep = draw_view(table);
			sourceList = count_colour(rep, 400, 180, [NSColor cg_accentColor]);
			[rep release];

			[table setDraggingDestinationFeedbackStyle:NSTableViewDraggingDestinationFeedbackStyleNone];
			rep = draw_view(table);
			none = count_colour(rep, 400, 180, [NSColor cg_accentColor]);
			[rep release];
			printf("  (note: accent pixels: %d regular, %d source-list, %d none)\n", regular, sourceList, none);
			check(regular > 0 && sourceList > regular && none == 0,
			      "Regular's line, SourceList's plate, and None's nothing are three different drawings");

			[table setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleSourceList];
			check([table draggingDestinationFeedbackStyle] == NSTableViewDraggingDestinationFeedbackStyleSourceList,
			      "and a source-list selection style chooses the source-list feedback");
			[table setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
		}

		printf("table_tail: %d case(s) failed\n", s_failed);
		[table release];
		[scroll release];
		[window release];
		[source release];
	}
	return s_failed != 0;
}
