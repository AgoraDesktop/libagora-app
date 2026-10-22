/*
 * browser — columns of rows, and the selection that opens the next column.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PUBLIC CONTRACT IS THE DELEGATE'S.** A column asks how many rows it has; a row's cell is filled by
 * `-browser:willDisplayCell:atRow:column:`; selecting a row loads the column to its right; a leaf has no right-hand
 * column. Offscreen: the browser's private tables are asked through the tier's seams, and the path is the selected
 * cells' strings.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>
#import <Foundation/NSIndexSet.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSWindow.h>
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
	[browser setColumnWidth:220.0];
	probe = [[AGBrowserProbe alloc] init];
	[browser setDelegate:probe];
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 600.0, 300.0)
					     styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	[window setContentView:browser];
	[browser loadColumnZero];

	check([browser cg_columnCount] == 256 && [browser cg_activeColumnCount] == 1,
	      "loadColumnZero builds the 256-column pool with the root active");
	check([browser numberOfRowsInColumn:1] == 0 && [browser numberOfVisibleColumns] >= 2,
	      "and the empty slots beside the root are visible columns");
	check([[browser cg_scrollViewForColumn:1] superview] != nil
	      && [[browser cg_scrollViewForColumn:200] superview] == nil,
	      "but only the visible empty slots are attached to the document");
	table = [browser cg_tableForColumn:0];
	check(table != nil && [table numberOfRows] == 3, "the first column has the root's three rows");
	check([browser selectedColumn] == -1 && [browser selectedRowInColumn:0] == -1,
	      "and nothing is selected at birth");

	check([[table preparedCellAtColumn:0 row:0] isKindOfClass:[NSBrowserCell class]],
	      "a row is drawn by an NSBrowserCell");
	check([[[browser cg_scrollViewForColumn:0] verticalScroller] isHidden],
	      "a column whose rows fit hides its vertical bar");
	{
		NSView *document = [browser cg_documentView];
		NSScrollView *outer = (NSScrollView *)[[document superview] superview];

		check([outer autohidesScrollers] && [[outer horizontalScroller] isHidden],
		      "and a one-column browser hides its outer horizontal bar");
	}
	cell = (NSBrowserCell *)[table preparedCellAtColumn:0 row:0];
	check([[cell stringValue] isEqual:@"A"] && ![cell isLeaf],
	      "the cell's title is the delegate's and A is a branch");
	cell = (NSBrowserCell *)[table preparedCellAtColumn:0 row:1];
	check([[cell stringValue] isEqual:@"B"] && [cell isLeaf], "B is a leaf");

	[browser selectRow:0 inColumn:0];
	check([browser selectedColumn] == 0 && [browser selectedRowInColumn:0] == 0,
	      "selecting a row records the column and the row");
	check([browser cg_activeColumnCount] == 2 && [[browser cg_tableForColumn:1] numberOfRows] == 2,
	      "and loads the selected branch's two children into column 1");
	check([[browser path] isEqual:@"A"], "the path is the selected cell's title");

	[browser selectRow:0 inColumn:1];
	check([browser cg_activeColumnCount] == 3 && [[browser cg_tableForColumn:2] numberOfRows] == 1,
	      "selecting A1 loads its one child");
	check([[browser path] isEqual:@"A/A1"], "and the path follows both columns");
	{
		/* **THE NEW COLUMN IS THE ONE TO SHOW.** Selecting a branch opens the column to its right; the clip view must
		 * go to the document's end so that column is against the right edge rather than off it. */
		NSView *document = [browser cg_documentView];
		NSView *clip = [document superview];
		CGFloat maxX = [document frame].size.width - [clip bounds].size.width;

		if (maxX < 0.0) {
			maxX = 0.0;
		}
		check(fabs([clip bounds].origin.x - maxX) < 0.01,
		      "opening a column scrolls the browser all the way to the end");
	}

	[browser selectRow:0 inColumn:2];
	check([browser cg_activeColumnCount] == 3, "a leaf adds no active column to its right");
	check([browser selectedColumn] == 2 && [[[browser selectedCell] stringValue] isEqual:@"leaf"],
	      "the leaf is the selected cell");
	check([[browser path] isEqual:@"A/A1/leaf"], "and the path reaches the leaf");

	[browser reloadColumn:0];
	check([browser selectedColumn] == 0 && [browser selectedRowInColumn:0] == 0,
	      "reloading a column keeps a still-valid selection");
	check([browser cg_activeColumnCount] == 2, "and rebuilds the column to its right");

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

	/* **A FRAME CHANGE RE-TILES THE BROWSER'S OWN SCROLL VIEW.** `NSView -setFrame:` does not call the resize hook,
	 * and the browser's face is that scroll view: a containing view that sets the browser's frame — Workspace lays
	 * one out beside a preview panel — would otherwise leave the scroll view at its old width and open a gap. */
	{
		NSView *document = [browser cg_documentView];
		NSView *scroll = [[document superview] superview];

		[browser setFrame:NSMakeRect(0.0, 0.0, 900.0, 400.0)];
		check(scroll != nil && fabs([scroll frame].size.width - 900.0) < 0.01,
		      "a frame change re-tiles the browser's scroll view");
	}

	/* **EACH COLUMN HAS ITS OWN VERTICAL SCROLL VIEW, AND ITS OWN WIDTH.** The browser height is made smaller
	 * than a column's rows so the inner scroll has somewhere to move; scrolling the first column must not move
	 * the second, and a width set on one must not be applied to the other. */
	{
		NSScrollView *scroll0;
		NSScrollView *scroll1;
		CGFloat defaultWidth;
		NSRect gap;
		NSView *document;
		NSWindow *browserWindow = [browser window];
		NSPoint dividerPoint;
		NSPoint windowPoint;
		NSInteger windowNumber = (browserWindow != nil) ? [browserWindow windowNumber] : 0;

		[browser setPath:@"A"];
		[browser setRowHeight:40.0];
		[browser setFrame:NSMakeRect(0.0, 0.0, 600.0, 80.0)];
		scroll0 = [browser cg_scrollViewForColumn:0];
		scroll1 = [browser cg_scrollViewForColumn:1];
		check(scroll0 != nil && [scroll0 hasVerticalScroller]
		      && ![[scroll0 verticalScroller] isHidden]
		      && [[browser cg_tableForColumn:0] frame].size.height > [scroll0 contentSize].height,
		      "a column taller than the browser shows its own vertical scroller");
		check(scroll1 != nil && [scroll1 hasVerticalScroller], "and so does the column beside it");
		if (scroll0 != nil && scroll1 != nil) {
			[[scroll0 contentView] scrollToPoint:NSMakePoint(0.0, 40.0)];
			[scroll0 reflectScrolledClipView:[scroll0 contentView]];
			check([scroll0 documentVisibleRect].origin.y > 0.0,
			      "scrolling one column moves its own clip view");
			check([scroll1 documentVisibleRect].origin.y == 0.0,
			      "and leaves the column beside it where it was");
		}

		defaultWidth = [browser columnWidth];
		[browser setWidth:150.0 ofColumn:0];
		check([browser widthOfColumn:0] == 150.0 && [browser widthOfColumn:1] == defaultWidth,
		      "a width set on one column is not applied to the others");
		{
			NSScroller *bar = [[browser cg_scrollViewForColumn:0] verticalScroller];
			CGFloat contentWidth = 150.0 - ((bar != nil && ![bar isHidden])
				? [NSScroller scrollerWidth] : 0.0);

			check([[[[browser cg_tableForColumn:0] tableColumns] objectAtIndex:0] width] == contentWidth,
			      "and the table takes the column's content width, inside its visible bar");
		}

		/* **THE SEPARATOR IS A DRAG HANDLE.** A mouse down in the gap and a forty-point drag widen the LEFT
		 * column; the browser is not running a loop in this probe, so the drag is delivered as its own events. */
		[browser setColumnResizingType:NSBrowserUserColumnResizing];
		gap = [browser cg_dividerFrameForColumn:0];
		document = [browser cg_documentView];
		check(!NSIsEmptyRect(gap) && gap.size.width > 0.0, "the gap after a column is a divider frame");
		dividerPoint = NSMakePoint(NSMidX(gap), 10.0);
		windowPoint = [document convertPoint:dividerPoint toView:nil];
		if (!NSIsEmptyRect(gap) && browserWindow != nil) {
			NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown location:windowPoint
							 modifierFlags:0 timestamp:0.0 windowNumber:windowNumber
							 context:nil eventNumber:0 clickCount:1 pressure:1.0f];
			NSEvent *drag = [NSEvent mouseEventWithType:NSLeftMouseDragged
							 location:NSMakePoint(windowPoint.x + 40.0, windowPoint.y)
							 modifierFlags:0 timestamp:0.0 windowNumber:windowNumber
							 context:nil eventNumber:1 clickCount:1 pressure:1.0f];
			NSEvent *up = [NSEvent mouseEventWithType:NSLeftMouseUp
						       location:NSMakePoint(windowPoint.x + 40.0, windowPoint.y)
						       modifierFlags:0 timestamp:0.0 windowNumber:windowNumber
						       context:nil eventNumber:2 clickCount:1 pressure:0.0f];

			[document mouseDown:down];
			[document mouseDragged:drag];
			[document mouseUp:up];
			check([browser widthOfColumn:0] == 190.0,
			      "dragging the separator forty points widens the column by forty");
			check([browser widthOfColumn:1] == defaultWidth,
			      "and the right-hand column keeps its width");

			/* **THE GUTTER IS THE SPLIT VIEW'S THREE-RING GRIP, AND THE PIXELS ARE COUNTED.** The same
			 * eighteen-point band, ring radius and spacing `NSSplitView`'s pane splitter uses are drawn here;
			 * rendering the document view offscreen and counting the dark row clusters in the gutter is what
			 * makes "three circles" a measurement rather than a claim. */
			{
				NSRect gutter = [browser cg_dividerFrameForColumn:0];
				NSRect bounds = [document bounds];
				NSInteger w = (NSInteger)ceil(bounds.size.width);
				NSInteger h = (NSInteger)ceil(bounds.size.height);
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
					initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8
					     samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					     colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
				NSGraphicsContext *g = (rep != nil)
					? [NSGraphicsContext graphicsContextWithBitmapImageRep:rep] : nil;

				check(gutter.size.width == 18.0, "the browser gutter is the split view's eighteen points");
				if (g != nil) {
					NSGraphicsContext *previous = [[NSGraphicsContext currentContext] retain];
					unsigned char *px;
					NSInteger stride, x, y, runs = 0;
					BOOL inRun = NO;

					[NSGraphicsContext setCurrentContext:g];
					[document drawRect:bounds];
					[NSGraphicsContext setCurrentContext:previous];
					[previous release];
					px = [rep bitmapData];
					stride = [rep bytesPerRow];
					for (y = 0; y < h; y++) {
						BOOL dark = NO;

						for (x = (NSInteger)NSMinX(gutter); x < (NSInteger)NSMaxX(gutter); x++) {
							unsigned char *p = px + (size_t)y * (size_t)stride + (size_t)x * 4u;

							if ((p[0] + p[1] + p[2]) / 3 < 220) {
								dark = YES;
								break;
							}
						}
						if (dark && !inRun) {
							runs++;
							inRun = YES;
						} else if (!dark && inRun) {
							inRun = NO;
						}
					}
					check(runs == 3, "and it carries the split view's three rings");
				}
				[rep release];
			}
		}
	}

	/* 15. **AND THE BROWSER CELL'S OWN SIX DOORS: TWO PICTURES, TWO BRANCH MARKS, A HIGHLIGHT COLOUR AND `-set`.**
	 * The mark is checked in PIXELS at the cell's trailing edge, because "a branch wears a chevron and a leaf does not"
	 * is a claim about ink and not about a flag. */
	{
		NSBrowserCell *branch = [[NSBrowserCell alloc] initTextCell:@"Row"];
		NSBrowserCell *leaf = [[NSBrowserCell alloc] initTextCell:@"Row"];
		NSImage *alt = [[NSImage alloc] initWithSize:NSMakeSize(8.0, 8.0)];
		NSBitmapImageRep *branchRep;
		NSBitmapImageRep *leafRep;
		int branchInk = 0;
		int leafInk = 0;
		int x, y;

		[branch setLeaf:NO];
		[leaf setLeaf:YES];
		check([NSBrowserCell branchImage] != nil && [NSBrowserCell highlightedBranchImage] != nil,
		      "the two branch marks are images rather than nil");
		check([NSBrowserCell branchImage] != [NSBrowserCell highlightedBranchImage],
		      "and they are DIFFERENT images — one for a plain row and one for a selected one");
		check([branch alternateImage] == nil, "a fresh browser cell has no alternate picture");
		[branch setAlternateImage:alt];
		check([branch alternateImage] == alt, "`-setAlternateImage:` round-trips");
		check([[branch highlightColorInView:nil] isEqual:[NSColor selectedControlColor]],
		      "`-highlightColorInView:` answers the selection colour a highlighted row is drawn with");
		[branch set];
		check([branch state] == NSOnState && [branch isHighlighted],
		      "`-set` is the era's shorthand for selected: the state goes ON and the cell is highlighted");
		[branch setHighlighted:NO];

		branchRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:100 pixelsHigh:20
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:400 bitsPerPixel:32];
		leafRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:100 pixelsHigh:20
			bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
			colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:400 bitsPerPixel:32];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:branchRep]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 100.0, 20.0)] fill];
		[branch drawWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:nil];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:leafRep]];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 100.0, 20.0)] fill];
		[leaf drawWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0) inView:nil];
		for (y = 0; y < 20; y++) {
			for (x = 88; x < 100; x++) {
				if ([[branchRep colorAtX:x y:y] redComponent] < 0.6) branchInk++;
				if ([[leafRep colorAtX:x y:y] redComponent] < 0.6) leafInk++;
			}
		}
		printf("  (note: the trailing 12 points hold %d dark points for a branch and %d for a leaf)\n",
		       branchInk, leafInk);
		check(branchInk > 0, "a BRANCH draws its chevron at the trailing edge");
		check(leafInk == 0, "and a LEAF draws nothing there — that is what being a leaf means");
		[branchRep release];
		[leafRep release];
		[alt release];
		[branch release];
		[leaf release];
	}

	[window release];
	[browser release];
	[probe release];
	printf("browser: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
