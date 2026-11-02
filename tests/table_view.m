/*
 * table_view — the cell-based table: its columns, rows, header, selection and drawing.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE TABLE IS A GEOMETRY AND A MODEL, SO BOTH ARE ASKED.** The model questions are the data source's row count,
 * the columns' widths and the selection; the geometry questions are where a row, a column, a cell and a header sit,
 * and whether the header's divider drag changes a column. The drawing check is read back from a bitmap rep, because
 * "the table draws its values" is not a fact about the code that asked for them.
 *
 * The window check at the top is the other half of this slice: a window's content view now follows EVERY frame set,
 * not only a frame that carries a toolbar.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderCell.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSScrollView_internal.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

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
	return fabs(a - b) < 0.01;
}

static int eqr(NSRect a, NSRect b)
{
	return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y)
		&& near(a.size.width, b.size.width) && near(a.size.height, b.size.height);
}

static int eqc(NSColor *a, NSColor *b, double tol)
{
	return a != nil && b != nil
		&& fabs([a redComponent] - [b redComponent]) < tol
		&& fabs([a greenComponent] - [b greenComponent]) < tol
		&& fabs([a blueComponent] - [b blueComponent]) < tol;
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

/* **WHERE THE FIRST ROW'S TEXT ACTUALLY LANDS, IN THE VIEW'S OWN Y, FOR A CHOSEN CTM DIRECTION.**
 *
 * The claim this measures is the one a person reads off the screen: a cell's line of text is centred on the cell, so
 * a disclosure triangle centred on the row (or a combo box's chip) points at the middle of the words. It is
 * measured in BOTH directions because the tabular views are flipped and a plain content view is not, and the first
 * version of the baseline arithmetic assumed one of them — MEASURED: the y-up copy drew a flipped table's rows one
 * ascent too high and clipped their tops, while the offscreen render happened to use the direction it assumed.
 *
 * `flipped` applies the same translate-and-scale the ink test above uses; without it the context keeps the bitmap's
 * own y-down CTM, which is what a window's flipped view draws in. The band is returned in view coordinates, so the
 * two directions are compared against the same number. Returns 0 if no ink was found. */
static int text_band_in_row(NSTableView *table, BOOL flip, int row, double *centreOut)
{
	int w = (int)[table frame].size.width;
	int h = (int)[table frame].size.height;
	NSRect rowRect = [table rectOfRow:row];
	NSBitmapImageRep *rep = new_rep(w, h);
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	int deviceFirst = -1, deviceLast = -1;
	int y0, y1, y;

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
	if (flip) {
		CGContextRef cg = (CGContextRef)[ctx graphicsPort];

		CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	[table displayRect:[table bounds]];
	/* ONLY ROW `row`'S BAND. The bitmap's own context is y-DOWN (MEASURED: d = -1); the translate-and-scale
	 * turns it into y-up, where device y IS view y, and leaves the unflipped case mirrored about the image. */
	y0 = flip ? (int)NSMinY(rowRect) : h - (int)NSMaxY(rowRect) - 1;
	y1 = flip ? (int)NSMaxY(rowRect) - 1 : h - (int)NSMinY(rowRect) - 1;
	for (y = y0; y <= y1; y++) {
		int x, dark = 0;

		for (x = 4; x < 60; x++) {
			NSColor *pixel = [rep colorAtX:x y:y];

			if (pixel != nil && [pixel redComponent] < 0.4 && [pixel greenComponent] < 0.4
			    && [pixel blueComponent] < 0.4) {
				dark++;
			}
		}
		if (dark > 0) {
			if (deviceFirst < 0) {
				deviceFirst = y;
			}
			deviceLast = y;
		}
	}
	[rep release];
	[NSGraphicsContext setCurrentContext:nil];
	if (deviceFirst < 0) {
		return 0;
	}
	/* Device y -> view y: identity in the y-up context the flip makes, mirrored in the bitmap's own y-down one. */
	*centreOut = flip ? ((double)deviceFirst + (double)deviceLast) / 2.0
			  : (double)h - 1.0 - ((double)deviceFirst + (double)deviceLast) / 2.0;
	(void)rowRect;
	return 1;
}

@interface AGTableProbe : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
@public
	int willDisplay;
	int sortChanges;
	int selectionChanges;
	int dragWrites;		/* how many times the drag source was asked for rows */
}
@end

@implementation AGTableProbe

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return 5;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *identifier = [tableColumn identifier];

	(void)tableView;
	if ([identifier isEqualToString:@"name"]) {
		return [NSString stringWithFormat:@"row %ld", (long)row];
	}
	if ([identifier isEqualToString:@"date"]) {
		return @"2026-10-18";
	}
	return @"1 KB";
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	(void)cell;
	(void)tableColumn;
	(void)row;
	willDisplay++;
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return YES;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	(void)tableView;
	return row != 4;	/* one row refuses, so the delegate's answer is exercised */
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes
   toPasteboard:(NSPasteboard *)pasteboard
{
	(void)tableView;
	(void)rowIndexes;
	(void)pasteboard;
	dragWrites++;
	return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	selectionChanges++;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	(void)tableView;
	(void)oldDescriptors;
	sortChanges++;
}
@end

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

static NSEvent *mouseWithFlags(int type, NSPoint where, NSInteger windowNumber, NSUInteger flags)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:flags
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

/* **THE HEADER'S INK, IN ONE RECTANGLE.** The header is painted into the probe's own bitmap (the helper the title check
 * above uses), and the dark pixels inside `rect` are counted — the sort mark is the only dark thing in that right-hand
 * zone, which is what makes "is it there, and which way does it point" answerable without a screenshot. */
/* **THE MARK'S INK IN ONE COLUMN'S RIGHT-HAND ZONE.** The header is painted into the probe's own bitmap (the same door
 * the title check uses) and the dark pixels inside the column's last fourteen points are counted — clear of the centred
 * title, inside the one-point edge, which is the strip a sort mark lives in. `centroidY`, when wanted, is the mean y of
 * that ink, so "is it there" and "which way does it point" are one measurement. */
static int headerMarkInk(NSView *header, NSBitmapImageRep *rep, NSInteger column, CGFloat *centroidY)
{
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	NSRect rect = [(NSTableHeaderView *)header headerRectOfColumn:column];
	int x, y, ink = 0;
	long sumY = 0;

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:[header bounds]] fill];
	{
		CGContextRef cg = (CGContextRef)[ctx graphicsPort];

		CGContextTranslateCTM(cg, 0.0, [header bounds].size.height);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	[header displayRect:[header bounds]];
	for (x = (int)(NSMaxX(rect) - 14.0); x < (int)NSMaxX(rect) - 1; x++) {
		for (y = 0; y < (int)NSHeight([header bounds]); y++) {
			NSColor *pixel = (x >= 0 && x < (int)[rep pixelsWide] && y < (int)[rep pixelsHigh])
				? [rep colorAtX:x y:y] : nil;

			if (pixel != nil && [pixel redComponent] < 0.4 && [pixel greenComponent] < 0.4
			    && [pixel blueComponent] < 0.4) {
				ink++;
				sumY += y;
			}
		}
	}
	if (centroidY != NULL) {
		*centroidY = (ink > 0) ? (CGFloat)sumY / (CGFloat)ink : 0.0;
	}
	return ink;
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	AGTableProbe *probe = [[AGTableProbe alloc] init];
	NSWindow *window;
	NSWindow *plainWindow;
	NSView *plainContent;
	NSScrollView *scroll;
	NSTableView *table;
	NSTableColumn *name;
	NSTableColumn *date;
	NSTableColumn *size;
	NSTableHeaderView *header;
	NSRect frame;
	int checks;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];

	/* 0. **A WINDOW'S CONTENT VIEW FOLLOWS A FRAME SET WITHOUT A TOOLBAR.** Borderless, so the frame and content are
	 * the same rectangle and the answer is not confused by the title bar. */
	plainWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 200.0, 100.0)
						 styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	plainContent = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 100.0)] autorelease];
	[plainWindow setContentView:plainContent];
	[plainWindow setFrame:NSMakeRect(0.0, 0.0, 200.0, 150.0) display:NO];
	check(near([plainContent frame].size.height, 150.0),
	      "a borderless window's content view follows a frame set with no toolbar");

	/* 1. THE TABLE, ITS COLUMNS AND ITS SCROLL VIEW. */
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
					     styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
	[scroll setHasVerticalScroller:YES];
	[window setContentView:scroll];
	table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
	[table setRowHeight:20.0];
	[table setIntercellSpacing:NSMakeSize(3.0, 2.0)];
	[table setDataSource:probe];
	[table setDelegate:probe];
	name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	date = [[NSTableColumn alloc] initWithIdentifier:@"date"];
	size = [[NSTableColumn alloc] initWithIdentifier:@"size"];
	[name setWidth:150.0];
	[date setWidth:100.0];
	[size setWidth:80.0];
	[date setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES]];
	[table addTableColumn:name];
	[table addTableColumn:date];
	[table addTableColumn:size];
	[scroll setDocumentView:table];
	[table reloadData];
	header = [table headerView];

	check([table numberOfColumns] == 3 && [table numberOfRows] == 5,
	      "the table has three columns and the five rows the data source reports");
	check([header tableView] == table, "the table's default header knows its table");
	check([scroll cg_headerView] == header, "the header is installed in the scroll view");
	check(near([[scroll contentView] frame].size.height, 280.0),
	      "the clip view gives the header its 20-point strip (300 - 20 header)");
	check(near([table frame].size.width, 385.0) && near([table frame].size.height, 280.0),
	      "the table fills the clip view's width and height");

	/* 2. THE GEOMETRY. */
	check(eqr([table rectOfColumn:0], NSMakeRect(0.0, 0.0, 150.0, 280.0)),
	      "column 0 starts at x=0 and is 150 wide");
	check(eqr([table rectOfColumn:1], NSMakeRect(153.0, 0.0, 100.0, 280.0)),
	      "column 1 begins after column 0 and the 3-point intercell gap");
	check(eqr([table rectOfColumn:2], NSMakeRect(256.0, 0.0, 80.0, 280.0)),
	      "column 2 begins after column 1");
	check(eqr([table rectOfRow:2], NSMakeRect(0.0, 44.0, 385.0, 20.0)),
	      "row 2 is 20 points tall at y = 2 * (20 + 2)");
	check(eqr([table frameOfCellAtColumn:1 row:2], NSMakeRect(153.0, 44.0, 100.0, 20.0)),
	      "a cell's frame is its column's x and its row's y");
	check([table rowAtPoint:NSMakePoint(10.0, 45.0)] == 2
	      && [table columnAtPoint:NSMakePoint(160.0, 10.0)] == 1,
	      "rowAtPoint: and columnAtPoint: find the row and column under a point");
	check(eqr([header headerRectOfColumn:1], NSMakeRect(153.0, 0.0, 100.0, 20.0))
	      && [header columnAtPoint:NSMakePoint(160.0, 10.0)] == 1,
	      "the header's column geometry is the table's x with the header's height");
	{
		NSRange rows = [table rowsInRect:NSMakeRect(0.0, 0.0, 100.0, 45.0)];

		check(rows.location == 0 && rows.length == 3,
		      "rowsInRect: includes every row the rect touches (rows 0, 1 and the start of 2)");
	}

	/* 3. SELECTION, INCLUDING THE DELEGATE'S REFUSAL. */
	checks = probe->selectionChanges;
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
	check([table selectedRow] == 2 && [table numberOfSelectedRows] == 1
	      && [[table selectedRowIndexes] containsIndex:2],
	      "selecting row 2 makes it the one selected row");
	check(probe->selectionChanges == checks + 1, "and announces the change");
	[table setAllowsMultipleSelection:YES];
	[table selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 4)]
	       byExtendingSelection:NO];
	check([table numberOfSelectedRows] == 3 && [table isRowSelected:1] && [table isRowSelected:2]
	      && [table isRowSelected:3] && ![table isRowSelected:4],
	      "a multiple selection keeps the rows the delegate allows and drops the one it refuses");
	[table deselectAll:nil];
	check([table numberOfSelectedRows] == 0, "deselectAll: clears the selection");

	/* 3a. **A CONTROL-CLICK TOGGLES A ROW, WHICH IS WHAT IT DOES EVERYWHERE ELSE.** Command is the Mac's spelling of
	 * "add this one too" and Control is every other desktop's; both must reach the same selection rule, or a person who
	 * pressed the one their habits taught them gets nothing. Shift-click is the run between the anchor and the row. */
	{
		/* Row 1 is 20 points tall at y = 22, so 32 is inside it; row 2 starts at 44. */
		NSPoint rowOne = [table convertPoint:NSMakePoint(10.0, 32.0) toView:nil];
		NSInteger number = [window windowNumber];

		[table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
		[table mouseDown:mouseWithFlags(NSLeftMouseDown, rowOne, number, NSControlKeyMask)];
		check([table numberOfSelectedRows] == 2 && [table isRowSelected:1] && [table isRowSelected:2],
		      "a Control-click adds a row to the selection, as a Command-click does");
		[table mouseDown:mouseWithFlags(NSLeftMouseDown, rowOne, number, NSControlKeyMask)];
		check([table numberOfSelectedRows] == 1 && ![table isRowSelected:1] && [table isRowSelected:2],
		      "and a second one on the same row takes it away again");
		[table mouseDown:mouseWithFlags(NSLeftMouseDown, rowOne, number, NSCommandKeyMask)];
		check([table numberOfSelectedRows] == 2 && [table isRowSelected:1] && [table isRowSelected:2],
		      "a Command-click toggles too, so neither modifier is the only one that works");
		[table deselectAll:nil];
		[table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
		[table mouseDown:mouseWithFlags(NSLeftMouseDown, rowOne, number, NSShiftKeyMask)];
		check([table numberOfSelectedRows] == 2 && [table isRowSelected:1] && [table isRowSelected:2],
		      "and a Shift-click takes the run between the anchor and the row clicked");
		[table deselectAll:nil];
	}

	/* 3b. **A CLICK CANNOT BECOME A DRAG.** The threshold is the row: a hand's tremor during an ordinary click crosses a
	 * four-point threshold, and in a file manager a table drag that ends one row lower MOVES the file into that row's
	 * folder — MEASURED on this machine, a click whose pointer drifted sixteen device pixels took a folder into the
	 * folder below it. So a press whose pointer stays inside its own row writes nothing to the pasteboard and starts no
	 * session; only leaving the row can begin one. */
	{
		NSPoint press = [table convertPoint:NSMakePoint(10.0, 54.0) toView:nil];	/* inside row 2 */
		NSPoint within = [table convertPoint:NSMakePoint(24.0, 58.0) toView:nil];	/* still row 2 */
		NSInteger before = probe->dragWrites;

		[table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
		[table mouseDown:mouseWithFlags(NSLeftMouseDown, press, [window windowNumber], 0)];
		[table mouseDragged:mouse(NSLeftMouseDragged, within, [window windowNumber])];
		check(probe->dragWrites == before,
		      "a drag that never leaves the row it began in writes nothing: a click cannot move a row");
		check([table numberOfSelectedRows] == 1 && [table isRowSelected:2],
		      "and the selection is the row that was clicked");
	}

	/* 4. THE HEADER'S DIVIDER DRAG. */
	{
		NSPoint grab = [header convertPoint:NSMakePoint(252.0, 10.0) toView:nil];
		NSPoint moved = [header convertPoint:NSMakePoint(272.0, 10.0) toView:nil];
		NSEvent *down = mouse(NSLeftMouseDown, grab, [window windowNumber]);
		NSEvent *drag = mouse(NSLeftMouseDragged, moved, [window windowNumber]);
		NSEvent *up = mouse(NSLeftMouseUp, moved, [window windowNumber]);

		[header mouseDown:down];
		[header mouseDragged:drag];
		[header mouseUp:up];
		check(near([date width], 120.0), "dragging the divider 20 points widens the column by 20");
		check(near([table rectOfColumn:2].origin.x, 276.0),
		      "and the columns after it move with it");
	}

	/* 5. A HEADER CLICK ON A SORTABLE COLUMN. */
	{
		NSPoint click = [header convertPoint:NSMakePoint(193.0, 10.0) toView:nil];
		NSEvent *down = mouse(NSLeftMouseDown, click, [window windowNumber]);
		NSEvent *up = mouse(NSLeftMouseUp, click, [window windowNumber]);
		NSArray *descriptors;

		probe->sortChanges = 0;
		[header mouseDown:down];
		[header mouseUp:up];
		descriptors = [table sortDescriptors];
		check([descriptors count] == 1
		      && [[[descriptors objectAtIndex:0] key] isEqualToString:@"date"]
		      && [[descriptors objectAtIndex:0] ascending],
		      "clicking a column with a sort prototype makes an ascending descriptor");
		check(probe->sortChanges == 1, "and tells the data source the sort changed");
	}

	/* 6. THE INK: A ROW'S TEXT, AND A SELECTED ROW'S PLATE. */
	[table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
	{
		int w = (int)[table frame].size.width;
		int h = (int)[table frame].size.height;
		NSBitmapImageRep *rep = new_rep(w, h);
		NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
		int x, y;
		int textInk = 0;
		int selectedPlate = 0;

		[NSGraphicsContext setCurrentContext:ctx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
		{
			CGContextRef cg = (CGContextRef)[ctx graphicsPort];

			CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
			CGContextScaleCTM(cg, 1.0, -1.0);
		}
		[table displayRect:[table bounds]];
		for (x = 0; x < w; x += 2) {
			for (y = 0; y < (int)(2.0 * 22.0); y += 2) {
				NSColor *pixel = [rep colorAtX:x y:y];

				if (pixel != nil && [pixel redComponent] < 0.4 && [pixel greenComponent] < 0.4
				    && [pixel blueComponent] < 0.4) {
					textInk++;
				}
			}
		}
		check(textInk > 0, "the first two rows draw their values as ink");
		{
			/* THE SAME ROW, DRAWN IN BOTH CTM DIRECTIONS: the line is centred on the cell either way, which is
			 * what keeps a triangle (or a chip) centred on the row pointing at the middle of the words. */
			double rowCentre = NSHeight([table rectOfRow:0]) / 2.0;
			double up = 0.0, down = 0.0;
			int haveUp = text_band_in_row(table, YES, 0, &up);
			int haveDown = text_band_in_row(table, NO, 0, &down);

			printf("  [band] rowCentre=%.2f y-up=%.2f y-down=%.2f\n", rowCentre, up, down);
			check(haveUp && fabs(up - rowCentre) < 1.5,
			      "a y-up render centres the row's line on the cell");
			check(haveDown && fabs(down - rowCentre) < 1.5,
			      "and a y-down one (a flipped view's own CTM) does too");
		}
		check(eqc([rep colorAtX:100 y:(int)(1.0 * 22.0 + 10.0)], [NSColor cg_accentColor], 0.03),
		      "the selected row's plate is the platform's accent");
		check(probe->willDisplay > 0, "the delegate was asked to display cells");
		[rep release];
	}

	/* 7. THE HEADER'S OWN INK. */
	{
		int w = (int)[header frame].size.width;
		int h = (int)[header frame].size.height;
		NSBitmapImageRep *rep = new_rep(w, h);
		NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
		int x, y, ink = 0;

		[NSGraphicsContext setCurrentContext:ctx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
		{
			CGContextRef cg = (CGContextRef)[ctx graphicsPort];

			CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
			CGContextScaleCTM(cg, 1.0, -1.0);
		}
		[header displayRect:[header bounds]];
		for (x = 0; x < w; x++) {
			for (y = 0; y < h; y++) {
				NSColor *pixel = [rep colorAtX:x y:y];

				if (pixel != nil && [pixel redComponent] < 0.4 && [pixel greenComponent] < 0.4
				    && [pixel blueComponent] < 0.4) {
					ink++;
				}
			}
		}
		check(ink > 0, "the header draws its column titles");

		/* **AND THE SORT MARK NAMES THE COLUMN THE TABLE IS SORTED BY, AND POINTS THE WAY IT IS SORTED.** The header
		 * view draws it — it is the only object that knows which column a descriptor names — and the mark moves with the
		 * direction. MEASURED as "the triangle is stuck in the name column, and never changes direction": the header CELL
		 * used to guess its own column and left a second, motionless mark on the first one.
		 *
		 * The mark lives in the column's right-hand zone, clear of the centred title and inside the one-point edge, so
		 * that band is where the ink is counted — and WHERE in it (the mean y) is the direction. */
		{
			int sizeInk, nameInk, upInk;
			CGFloat downCentroid = 0.0, upCentroid = 0.0;

			[table setSortDescriptors:[NSArray arrayWithObject:
				[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES]]];
			sizeInk = headerMarkInk(header, rep, 1, &downCentroid);
			nameInk = headerMarkInk(header, rep, 0, NULL);
			check(sizeInk > 0, "the sorted column wears the sort mark");
			check(nameInk == 0, "and the name column does not wear one");

			[table setSortDescriptors:[NSArray arrayWithObject:
				[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]]];
			upInk = headerMarkInk(header, rep, 1, &upCentroid);
			check(upInk > 0 && fabs((double)(upCentroid - downCentroid)) > 1.0,
			      "and the mark moves when the direction does, rather than standing still");
		}
	}

	/* 8. A HIDDEN COLUMN TAKES NO WIDTH. */
	[size setHidden:YES];
	check(eqr([table rectOfColumn:2], NSZeroRect) && near([header headerRectOfColumn:2].size.width, 0.0),
	      "a hidden column has no table or header geometry");
	[size setHidden:NO];

	[table release];
	[scroll release];
	[window release];
	[plainWindow release];
	[probe release];
	printf("table_view: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
