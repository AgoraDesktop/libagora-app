/*
 * outline_view — the table's tree: roots, children, disclosure, levels and selection.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **AN OUTLINE IS A TABLE WITH A FLATTENED TREE, SO THE TEST ASKS BOTH HALVES.** The tree half is the flattened
 * rows, their levels, the item at a row and the row for an item; the table half is the outline column's inset cell,
 * the disclosure triangle's box, the click that expands, and the selection in item terms. Offscreen, with a window
 * as the coordinate root for the synthetic click.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSColor.h>
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

@interface AGOutlineItem : NSObject
{
@public
	NSString *name;
	NSMutableArray *children;
}
@end

@implementation AGOutlineItem
- (instancetype)initWithName:(NSString *)aName
{
	self = [super init];
	if (self != nil) {
		name = [aName copy];
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

@interface AGOutlineProbe : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
@public
	NSMutableArray *roots;
	AGOutlineItem *A;
	AGOutlineItem *A1;
	AGOutlineItem *A2;
	AGOutlineItem *A2a;
	AGOutlineItem *B;
	AGOutlineItem *B1;
	AGOutlineItem *C;
	int willExpand;
	int didExpand;
	int willCollapse;
	int didCollapse;
	int willDisplay;
	int selectionChanges;
	BOOL refuseExpand;
}
@end

@implementation AGOutlineProbe
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		roots = [[NSMutableArray alloc] init];
		A = [[AGOutlineItem alloc] initWithName:@"A"];
		A1 = [[AGOutlineItem alloc] initWithName:@"A1"];
		A2 = [[AGOutlineItem alloc] initWithName:@"A2"];
		A2a = [[AGOutlineItem alloc] initWithName:@"A2a"];
		B = [[AGOutlineItem alloc] initWithName:@"B"];
		B1 = [[AGOutlineItem alloc] initWithName:@"B1"];
		C = [[AGOutlineItem alloc] initWithName:@"C"];
		[A->children addObject:A1];
		[A->children addObject:A2];
		[A2->children addObject:A2a];
		[B->children addObject:B1];
		[roots addObject:A];
		[roots addObject:B];
		[roots addObject:C];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemWillExpand:)
			name:NSOutlineViewItemWillExpandNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidExpand:)
			name:NSOutlineViewItemDidExpandNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemWillCollapse:)
			name:NSOutlineViewItemWillCollapseNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidCollapse:)
			name:NSOutlineViewItemDidCollapseNotification object:nil];
	}
	return self;
}
- (void)itemWillExpand:(NSNotification *)note { (void)note; willExpand++; }
- (void)itemDidExpand:(NSNotification *)note { (void)note; didExpand++; }
- (void)itemWillCollapse:(NSNotification *)note { (void)note; willCollapse++; }
- (void)itemDidCollapse:(NSNotification *)note { (void)note; didCollapse++; }
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[roots release];
	[A release]; [A1 release]; [A2 release]; [A2a release];
	[B release]; [B1 release]; [C release];
	[super dealloc];
}
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return (NSInteger)[roots count];
	}
	return (NSInteger)[((AGOutlineItem *)item)->children count];
}
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return [roots objectAtIndex:(NSUInteger)index];
	}
	return [((AGOutlineItem *)item)->children objectAtIndex:(NSUInteger)index];
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return [roots count] > 0;
	}
	return [((AGOutlineItem *)item)->children count] > 0;
}
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	(void)outlineView;
	if (item == nil) {
		return @"";
	}
	if ([[tableColumn identifier] isEqualToString:@"name"]) {
		return ((AGOutlineItem *)item)->name;
	}
	return ((AGOutlineItem *)item)->children.count > 0 ? @"folder" : @"leaf";
}
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	(void)outlineView;
	(void)cell;
	(void)tableColumn;
	(void)item;
	willDisplay++;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item
{
	(void)outlineView;
	(void)item;
	return !refuseExpand;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item
{
	(void)outlineView;
	(void)item;
	return YES;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	(void)outlineView;
	return item != C;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	selectionChanges++;
}
@end

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

static void expect_rows(NSOutlineView *outline, NSInteger rows, const char *what)
{
	check([outline numberOfRows] == rows, what);
}

/* **THE TRIANGLE'S MIDDLE AND THE LINE'S MIDDLE, IN THE SAME ROW AND THE SAME RENDER.**
 *
 * The claim is the one a person reads: a closed disclosure triangle points at the middle of the line of text beside
 * it. Both are measured as INK bands — the triangle's in the left gutter, the text's in the cell — and compared with
 * each other, so the check does not depend on where either one's box is.
 *
 * It runs in BOTH CTM directions because a bitmap's own context is y-down (MEASURED: d = -1) while the
 * translate-and-scale the ink test above applies makes it y-up, and a table row's text and its triangle must agree in
 * both. Device y is view y in the y-up case; the y-down case is mirrored about the image. */
static int row_ink_centres(NSOutlineView *outline, BOOL flip, int row,
			   double *triangleOut, double *textOut)
{
	int w = (int)[outline frame].size.width;
	int h = (int)[outline frame].size.height;
	NSRect rowRect = [outline rectOfRow:row];
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w
		pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	double triFirst = -1.0, triLast = -1.0, textFirst = -1.0, textLast = -1.0;
	int y0, y1, y, x, found = 0;

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
	if (flip) {
		CGContextRef cg = (CGContextRef)[ctx graphicsPort];

		CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
		CGContextScaleCTM(cg, 1.0, -1.0);
	}
	[outline displayRect:[outline bounds]];
	y0 = flip ? (int)NSMinY(rowRect) : h - (int)NSMaxY(rowRect) - 1;
	y1 = flip ? (int)NSMaxY(rowRect) - 1 : h - (int)NSMinY(rowRect) - 1;
	for (y = y0; y <= y1; y++) {
		for (x = 2; x < 12; x++) {
			NSColor *pixel = [rep colorAtX:x y:y];

			if (pixel != nil && [pixel redComponent] < 0.4 && [pixel greenComponent] < 0.4
			    && [pixel blueComponent] < 0.4) {
				if (triFirst < 0.0) { triFirst = y; }
				triLast = y;
				break;
			}
		}
		for (x = 16; x < 140; x++) {
			NSColor *pixel = [rep colorAtX:x y:y];

			if (pixel != nil && [pixel redComponent] < 0.4 && [pixel greenComponent] < 0.4
			    && [pixel blueComponent] < 0.4) {
				if (textFirst < 0.0) { textFirst = y; }
				textLast = y;
				break;
			}
		}
	}
	[rep release];
	[NSGraphicsContext setCurrentContext:nil];
	if (triFirst < 0.0 || textFirst < 0.0) {
		return 0;
	}
	*triangleOut = flip ? (triFirst + triLast) / 2.0 : (double)h - 1.0 - (triFirst + triLast) / 2.0;
	*textOut = flip ? (textFirst + textLast) / 2.0 : (double)h - 1.0 - (textFirst + textLast) / 2.0;
	found = 1;
	return found;
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	AGOutlineProbe *probe = [[AGOutlineProbe alloc] init];
	NSWindow *window;
	NSScrollView *scroll;
	NSOutlineView *outline;
	NSTableColumn *name;
	NSTableColumn *kind;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 420.0, 280.0)
					     styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 280.0)];
	[window setContentView:scroll];
	outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 280.0)];
	[outline setRowHeight:20.0];
	[outline setIntercellSpacing:NSMakeSize(3.0, 2.0)];
	[outline setDataSource:probe];
	[outline setDelegate:probe];
	name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	kind = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
	[name setWidth:200.0];
	[kind setWidth:100.0];
	[outline addTableColumn:name];
	[outline addTableColumn:kind];
	[outline setOutlineTableColumn:name];
	[scroll setDocumentView:outline];
	[outline reloadData];

	/* 1. THE FLATTENED ROOTS. */
	expect_rows(outline, 3, "three collapsed roots are three rows");
	check([outline itemAtRow:0] == probe->A && [outline itemAtRow:1] == probe->B
	      && [outline itemAtRow:2] == probe->C,
	      "the rows are the roots in order");
	check([outline levelForRow:0] == 0 && [outline levelForItem:probe->A2a] == 2,
	      "a visible root is level 0 and a hidden grandchild still knows its level");
	check([outline parentForItem:probe->A1] == probe->A
	      && [outline parentForItem:probe->A] == nil,
	      "parentForItem: walks to the root's nil parent");
	check([outline rowForItem:probe->B] == 1 && [outline rowForItem:probe->A1] == -1,
	      "rowForItem: finds a visible item and answers -1 for a collapsed child");

	/* 2. EXPANDING A ROOT AND THEN A CHILD. */
	probe->willExpand = probe->didExpand = 0;
	[outline expandItem:probe->A];
	expect_rows(outline, 5, "expanding A adds its two children");
	check([outline itemAtRow:1] == probe->A1 && [outline itemAtRow:2] == probe->A2
	      && [outline levelForRow:1] == 1 && [outline levelForRow:2] == 1,
	      "the children follow A at level 1");
	check([outline isItemExpanded:probe->A], "A reports itself expanded");
	check(probe->willExpand == 1 && probe->didExpand == 1, "the expand pair was announced");

	[outline expandItem:probe->A2];
	expect_rows(outline, 6, "expanding A2 adds its child");
	check([outline itemAtRow:3] == probe->A2a && [outline levelForRow:3] == 2,
	      "the grandchild is at level 2");

	/* 3. COLLAPSING A ROOT HIDES ITS CHILDREN; COLLAPSING THEM WITH IT CLEARS THEIR STATE. */
	[outline collapseItem:probe->A];
	expect_rows(outline, 3, "collapsing A hides every descendant");
	check(![outline isItemExpanded:probe->A], "A reports itself collapsed");
	[outline expandItem:probe->A];
	expect_rows(outline, 6, "A2 is still expanded, so re-expanding A brings all three back");
	[outline collapseItem:probe->A collapseChildren:YES];
	[outline expandItem:probe->A];
	expect_rows(outline, 5, "collapsing A with its children clears A2's expansion too");
	[outline collapseItem:probe->A];

	/* 4. THE DELEGATE CAN REFUSE AN EXPANSION. */
	probe->refuseExpand = YES;
	[outline expandItem:probe->B];
	expect_rows(outline, 3, "a refused expansion changes no rows");
	probe->refuseExpand = NO;
	[outline expandItem:probe->B];
	expect_rows(outline, 4, "and an allowed one adds B1");
	[outline collapseItem:probe->B];

	/* 5. THE OUTLINE COLUMN'S CELL IS INSET, THE TRIANGLE GETS ITS OWN BOX. */
	[outline expandItem:probe->A];
	check(near([outline frameOfOutlineCellAtRow:1].origin.x, 18.0)
	      && near([outline frameOfOutlineCellAtRow:1].size.width, 9.0),
	      "the disclosure at level 1 starts at 2 + 1 * 16 points");
	check(near([outline frameOfCellAtColumn:0 row:1].origin.x, 31.0),
	      "the outline column's cell is inset by the level and the triangle's box");
	check(near([outline frameOfCellAtColumn:1 row:1].origin.x, 203.0),
	      "the other columns keep their own x");

	/* 6. A CLICK ON THE DISCLOSURE TOGGLES IT. */
	[outline collapseItem:probe->A];
	{
		NSRect triangle = [outline frameOfOutlineCellAtRow:0];
		NSPoint center = NSMakePoint(NSMidX(triangle), NSMidY(triangle));
		NSPoint windowPoint = [outline convertPoint:center toView:nil];
		NSEvent *down = mouse(NSLeftMouseDown, windowPoint, [window windowNumber]);

		[outline mouseDown:down];
		check([outline isItemExpanded:probe->A], "a click on the triangle expands A");
		[outline mouseDown:down];
		check(![outline isItemExpanded:probe->A], "a second click collapses it again");
	}

	/* 7. SELECTION IN ITEM TERMS: THE DELEGATE REFUSES C. */
	[outline deselectAll:nil];
	probe->selectionChanges = 0;
	[outline selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
	check([outline numberOfSelectedRows] == 0, "the delegate's shouldSelectItem: refusal keeps C unselected");
	[outline selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	check([outline selectedRow] == 0 && probe->selectionChanges > 0,
	      "A can be selected and the change is announced");

	/* 8. THE INK: THE OUTLINE'S TEXT AND ITS TRIANGLE. */
	[outline collapseItem:probe->A];
	[outline deselectAll:nil];
	{
		int w = (int)[outline frame].size.width;
		int h = (int)[outline frame].size.height;
		NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w
			pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
		NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
		CGContextRef cg = (CGContextRef)[ctx graphicsPort];
		int x, y, ink = 0;

		[NSGraphicsContext setCurrentContext:ctx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
		CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
		CGContextScaleCTM(cg, 1.0, -1.0);
		[outline displayRect:[outline bounds]];
		for (x = 0; x < w; x++) {
			for (y = 0; y < 22; y++) {
				NSColor *pixel = [rep colorAtX:x y:y];

				if (pixel != nil && [pixel redComponent] < 0.4 && [pixel greenComponent] < 0.4
				    && [pixel blueComponent] < 0.4) {
					ink++;
				}
			}
		}
		check(ink > 0, "the first row draws its disclosure and its value");
		check(probe->willDisplay > 0, "the outline delegate was asked to display cells");
		[rep release];
		{
			/* THE CLAIM A PERSON READS: a closed triangle points at the middle of the line beside it. A is row 0
			 * and is collapsed here, so its disclosure points right. Both render directions are measured. */
			double triUp = 0.0, textUp = 0.0, triDown = 0.0, textDown = 0.0;
			int haveUp = row_ink_centres(outline, YES, 0, &triUp, &textUp);
			int haveDown = row_ink_centres(outline, NO, 0, &triDown, &textDown);

			check(haveUp && fabs(triUp - textUp) < 1.5,
			      "a y-up render: the closed triangle's middle is the line's middle");
			check(haveDown && fabs(triDown - textDown) < 1.5,
			      "and a y-down one (a flipped view's own CTM) agrees with it");
		}
	}

	[outline release];
	[scroll release];
	[window release];
	[probe release];
	printf("outline_view: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
