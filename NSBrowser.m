/*
 * NSBrowser.m — columns of tables, and the selection that opens the next one.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE PRIVATE SHAPE: one horizontal `NSScrollView` around a document view, and one `NSScrollView` per column inside
 * it, each with an `NSTableView` as its document. The browser is the data source and delegate of every one of those
 * tables and maps a sender back to its column by identity. The public shape is the 10.6 delegate:
 * `-browser:numberOfRowsInColumn:` and `-browser:willDisplayCell:atRow:column:`; selecting a row asks the delegate
 * for the column to its right. Each column scrolls vertically on its own, and its width is its own.
 *
 * THE MATRIX FORM IS THE ONE THING THAT IS NOT HERE, AND `NSMatrix` NOW EXISTS — so the reason is the browser's
 * SHAPE rather than a missing class. Apple's columns ARE matrices; this tree's are tables, so there is no matrix for
 * `-browser:createRowsForColumn:inMatrix:` to hand a delegate, and a temporary one would be a stub with a real
 * signature. A cell-based delegate using `willDisplayCell` is the supported path.
 */
#import <AppKit/NSBrowser.h>
#import <AppKit/NSBrowserCell.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSScroller.h>
#import <Foundation/NSIndexSet.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSView.h>
#import "NSWindow_internal.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <stdlib.h>

/* **THE GUTTER IS `NSSplitView`'S PANE SPLITTER, DOWN TO ITS THREE RINGS.** The thickness, ring radius and
 * spacing are the same numbers that class uses, and the fill/stroke pair is its pair: the window's face for the
 * band and `controlDarkShadowColor` for the rings. Keeping the numbers here rather than reaching into
 * `NSSplitView.m` is what lets the browser draw the gutter itself while the two still look like one tier. */
#define AG_BROWSER_GUTTER_THICKNESS	18.0
#define AG_BROWSER_GUTTER_RING_RADIUS	2.0
#define AG_BROWSER_GUTTER_RING_SPACING	8.0
#define AG_BROWSER_GAP			AG_BROWSER_GUTTER_THICKNESS
/* Finder's column view pre-builds this many column slots; an empty slot is still a visible column and keeps its
 * width when navigation steps away from it. They do NOT all enter the document: horizontal scrolling is sized by
 * the active columns or the visible area, never by the whole pool. */
#define AG_BROWSER_COLUMN_POOL		256

@class NSBrowser;

@interface NSBrowser (NSBrowserPrivateGeometry)
- (CGFloat)fn_frameWidthForColumn:(NSInteger)column;
- (void)fn_sizeColumnToFit:(NSInteger)column;
@end

@interface NSBrowserDocumentView : NSView
{
	NSBrowser *_browser;	/* NOT RETAINED: the browser owns this view */
	NSInteger _dragColumn;
	CGFloat _dragStartX;
	CGFloat _dragStartWidth;
	CGFloat _dragPreviewX;
	BOOL _dragPreviewActive;
}
- (void)setBrowser:(NSBrowser *)browser;
@end

@interface NSBrowser () <NSTableViewDataSource, NSTableViewDelegate>
- (void)cg_scrollToLastColumn;
@end

@implementation NSBrowserDocumentView

- (void)setBrowser:(NSBrowser *)browser
{
	_browser = browser;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger count, i;

	(void)dirtyRect;
	if (_browser == nil || ![_browser separatesColumns]) {
		return;
	}
	count = [_browser cg_columnCount];
	{
		CGFloat x = 0.0;

	for (i = 0; i + 1 < count; i++) {
		CGFloat frameWidth = [_browser fn_frameWidthForColumn:i];
		NSRect gap = NSMakeRect(x + frameWidth, 0.0, AG_BROWSER_GAP, NSHeight([self bounds]));
		NSColor *ink = [NSColor controlDarkShadowColor];
		CGFloat centerX;
		CGFloat centerY;
		NSInteger ring;

		if (x + frameWidth >= NSMaxX([self bounds])) {
			break;
		}
		/* THE GUTTER IS THE WINDOW'S FACE, not the divider colour: the rings are the ink and the wide band
		 * between the columns is the surface showing through. The three rings are `NSSplitView`'s pane splitter
		 * grip, two-point radii eight points apart down the middle of an eighteen-point gutter. */
		[[NSColor windowBackgroundColor] setFill];
		[[NSBezierPath bezierPathWithRect:gap] fill];
		[ink setStroke];
		centerX = NSMidX(gap);
		centerY = NSMidY(gap);
		for (ring = -1; ring <= 1; ring++) {
			NSRect circle = NSMakeRect(centerX - AG_BROWSER_GUTTER_RING_RADIUS,
						   centerY + (CGFloat)ring * AG_BROWSER_GUTTER_RING_SPACING
						   - AG_BROWSER_GUTTER_RING_RADIUS,
						   AG_BROWSER_GUTTER_RING_RADIUS * 2.0,
						   AG_BROWSER_GUTTER_RING_RADIUS * 2.0);
			NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:circle];

			[path setLineWidth:1.0];
			[path stroke];
		}
		x += frameWidth + AG_BROWSER_GAP;
	}
	}
}

- (void)resetCursorRects
{
	NSInteger count, i;

	[super resetCursorRects];
	if (_browser == nil || ![_browser separatesColumns]
	    || [_browser columnResizingType] != NSBrowserUserColumnResizing) {
		return;
	}
	count = [_browser cg_columnCount];
	{
		CGFloat x = 0.0;

		for (i = 0; i + 1 < count; i++) {
			CGFloat frameWidth = [_browser fn_frameWidthForColumn:i];
			NSRect gap = NSMakeRect(x + frameWidth, 0.0, AG_BROWSER_GAP, NSHeight([self bounds]));

			if (x + frameWidth >= NSMaxX([self bounds])) {
				break;
			}
			[self addCursorRect:gap cursor:[NSCursor resizeLeftRightCursor]];
			x += frameWidth + AG_BROWSER_GAP;
		}
	}
}

- (NSInteger)fn_dividerAtPoint:(NSPoint)point
{
	NSInteger count, i;

	if (_browser == nil || ![_browser separatesColumns]
	    || [_browser columnResizingType] != NSBrowserUserColumnResizing) {
		return -1;
	}
	count = [_browser cg_columnCount];
	{
		CGFloat x = 0.0;

		for (i = 0; i + 1 < count; i++) {
			CGFloat frameWidth = [_browser fn_frameWidthForColumn:i];
			CGFloat gapX = x + frameWidth;

			if (point.x < gapX) {
				break;
			}
			if (point.x <= gapX + AG_BROWSER_GAP) {
				return i;
			}
			x = gapX + AG_BROWSER_GAP;
		}
	}
	return -1;
}

- (void)fn_setPreviewX:(CGFloat)x
{
	NSWindow *window = [self window];

	_dragPreviewX = x;
	_dragPreviewActive = YES;
	if (window != nil) {
		NSView *content = [window contentView];
		NSRect line = NSMakeRect(x - 0.5, NSMinY([self bounds]), 1.0, NSHeight([self bounds]));

		[window cg_setDragGuideRect:[content convertRect:line fromView:self]];
	}
}

- (void)fn_clearPreview
{
	_dragPreviewActive = NO;
	if ([self window] != nil) {
		[[self window] cg_clearDragGuide];
	}
}

- (void)fn_dragToPoint:(NSPoint)point
{
	if (_dragColumn < 0) {
		return;
	}
	[self fn_setPreviewX:point.x];
}

- (void)fn_applyDragWidth
{
	CGFloat width;
	id <NSBrowserDelegate> delegate;

	if (_dragColumn < 0) {
		return;
	}
	width = _dragStartWidth + (_dragPreviewX - _dragStartX);
	delegate = [_browser delegate];
	if (delegate != nil && [delegate respondsToSelector:@selector(browser:shouldSizeColumn:forUserResize:toWidth:)]
	    && ![delegate browser:_browser shouldSizeColumn:_dragColumn forUserResize:YES toWidth:width]) {
		return;
	}
	[_browser setWidth:width ofColumn:_dragColumn];
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger column = [self fn_dividerAtPoint:point];

	if (column < 0) {
		[super mouseDown:event];
		return;
	}
	if ([event clickCount] >= 2) {
		[_browser fn_sizeColumnToFit:column];
		return;
	}
	_dragColumn = column;
	_dragStartX = point.x;
	_dragStartWidth = [_browser widthOfColumn:column];
	[self fn_setPreviewX:NSMidX([_browser cg_dividerFrameForColumn:column])];
	if ([self window] != nil) {
		[[self window] cg_suspendTrackingUpdates];
	}

	/* A PROGRAM WITH NO RUN LOOP HAS NO EVENT SOURCE; the probe drives `-mouseDragged:` and `-mouseUp:`. */
	if (![[NSApplication sharedApplication] isRunning]) {
		return;
	}
	for (;;) {
		NSEvent *next = [[NSApplication sharedApplication]
			nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)
				    untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
				       inMode:nil dequeue:YES];

		if (next == nil) {
			[[self window] displayIfNeeded];
			continue;
		}
		[self fn_dragToPoint:[self convertPoint:[next locationInWindow] fromView:nil]];
		if ([next type] == NSLeftMouseUp) {
			break;
		}
		[[self window] displayIfNeeded];
	}
	[self fn_applyDragWidth];
	_dragColumn = -1;
	[self fn_clearPreview];
	if ([self window] != nil) {
		[[self window] cg_resumeTrackingUpdates];
	}
}

- (void)mouseDragged:(NSEvent *)event
{
	if (_dragColumn < 0) {
		[super mouseDragged:event];
		return;
	}
	[self fn_dragToPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)mouseUp:(NSEvent *)event
{
	if (_dragColumn < 0) {
		[super mouseUp:event];
		return;
	}
	[self fn_dragToPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	[self fn_applyDragWidth];
	_dragColumn = -1;
	[self fn_clearPreview];
	if ([self window] != nil) {
		[[self window] cg_resumeTrackingUpdates];
	}
}

@end

@implementation NSBrowser

/* ============================================================================================
 * ARCHIVING: THE COLUMNS' SHAPE AND THE BROWSER'S BEHAVIOUR, NOT ITS SCROLL VIEWS.
 * ============================================================================================ */
/* **THE THIRTY MEMBERS SPLIT INTO TWO KINDS AND ONLY ONE OF THEM IS A DESIGN.** The tables, column scroll views, column
 * widths and selected rows are what the browser BUILT while it was running — they are recreated from the design the
 * moment the decoded browser is laid out — and the delegate and data source are CONNECTIONS. What a file can state is
 * the geometry, the behaviour flags, the prototype cell, the class whose cells it makes, and the background colour. A
 * `Class` is archived by NAME, which is the only spelling an archive can carry. */
static NSString * const AGCoderBrowserColumnWidthKey = @"columnWidth";
static NSString * const AGCoderBrowserMinColumnWidthKey = @"minColumnWidth";
static NSString * const AGCoderBrowserRowHeightKey = @"rowHeight";
static NSString * const AGCoderBrowserTitleHeightKey = @"titleHeight";
static NSString * const AGCoderBrowserMaxColumnsKey = @"maxVisibleColumns";
static NSString * const AGCoderBrowserResizingTypeKey = @"columnResizingType";
static NSString * const AGCoderBrowserPathSeparatorKey = @"pathSeparator";
static NSString * const AGCoderBrowserDoubleActionKey = @"doubleAction";
static NSString * const AGCoderBrowserSeparatesKey = @"separatesColumns";
static NSString * const AGCoderBrowserMultipleKey = @"allowsMultipleSelection";
static NSString * const AGCoderBrowserEmptyKey = @"allowsEmptySelection";
static NSString * const AGCoderBrowserHScrollerKey = @"hasHorizontalScroller";
static NSString * const AGCoderBrowserTitlesKey = @"takesTitleFromPreviousColumn";
static NSString * const AGCoderBrowserArrowsKey = @"acceptsArrowKeys";
static NSString * const AGCoderBrowserArrowActionKey = @"sendsActionOnArrowKeys";
static NSString * const AGCoderBrowserBackgroundKey = @"backgroundColor";
static NSString * const AGCoderBrowserCellClassKey = @"cellClass";
static NSString * const AGCoderBrowserCellPrototypeKey = @"cellPrototype";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeDouble:_columnWidth forKey:AGCoderBrowserColumnWidthKey];
	[aCoder encodeDouble:_minColumnWidth forKey:AGCoderBrowserMinColumnWidthKey];
	[aCoder encodeDouble:_rowHeight forKey:AGCoderBrowserRowHeightKey];
	[aCoder encodeDouble:_titleHeight forKey:AGCoderBrowserTitleHeightKey];
	[aCoder encodeInteger:_maxVisibleColumns forKey:AGCoderBrowserMaxColumnsKey];
	[aCoder encodeInteger:(NSInteger)_columnResizingType forKey:AGCoderBrowserResizingTypeKey];
	[aCoder encodeObject:_pathSeparator forKey:AGCoderBrowserPathSeparatorKey];
	[aCoder encodeObject:(_doubleAction != NULL) ? NSStringFromSelector(_doubleAction) : nil
		      forKey:AGCoderBrowserDoubleActionKey];
	[aCoder encodeBool:_separatesColumns forKey:AGCoderBrowserSeparatesKey];
	[aCoder encodeBool:_allowsMultipleSelection forKey:AGCoderBrowserMultipleKey];
	[aCoder encodeBool:_allowsEmptySelection forKey:AGCoderBrowserEmptyKey];
	[aCoder encodeBool:_hasHorizontalScroller forKey:AGCoderBrowserHScrollerKey];
	[aCoder encodeBool:_takesTitleFromPreviousColumn forKey:AGCoderBrowserTitlesKey];
	[aCoder encodeBool:_acceptsArrowKeys forKey:AGCoderBrowserArrowsKey];
	[aCoder encodeBool:_sendsActionOnArrowKeys forKey:AGCoderBrowserArrowActionKey];
	[aCoder encodeObject:_backgroundColor forKey:AGCoderBrowserBackgroundKey];
	[aCoder encodeObject:(_cellClass != Nil) ? NSStringFromClass(_cellClass) : nil
		      forKey:AGCoderBrowserCellClassKey];
	[aCoder encodeObject:_cellPrototype forKey:AGCoderBrowserCellPrototypeKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserColumnWidthKey]) {
		_columnWidth = [aDecoder decodeDoubleForKey:AGCoderBrowserColumnWidthKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserMinColumnWidthKey]) {
		_minColumnWidth = [aDecoder decodeDoubleForKey:AGCoderBrowserMinColumnWidthKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserRowHeightKey]) {
		_rowHeight = [aDecoder decodeDoubleForKey:AGCoderBrowserRowHeightKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserTitleHeightKey]) {
		_titleHeight = [aDecoder decodeDoubleForKey:AGCoderBrowserTitleHeightKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserMaxColumnsKey]) {
		_maxVisibleColumns = [aDecoder decodeIntegerForKey:AGCoderBrowserMaxColumnsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserResizingTypeKey]) {
		_columnResizingType = (NSBrowserColumnResizingType)[aDecoder decodeIntegerForKey:AGCoderBrowserResizingTypeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserPathSeparatorKey]) {
		_pathSeparator = [[aDecoder decodeObjectForKey:AGCoderBrowserPathSeparatorKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserSeparatesKey]) {
		_separatesColumns = [aDecoder decodeBoolForKey:AGCoderBrowserSeparatesKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserMultipleKey]) {
		_allowsMultipleSelection = [aDecoder decodeBoolForKey:AGCoderBrowserMultipleKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserEmptyKey]) {
		_allowsEmptySelection = [aDecoder decodeBoolForKey:AGCoderBrowserEmptyKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserHScrollerKey]) {
		_hasHorizontalScroller = [aDecoder decodeBoolForKey:AGCoderBrowserHScrollerKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserTitlesKey]) {
		_takesTitleFromPreviousColumn = [aDecoder decodeBoolForKey:AGCoderBrowserTitlesKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserArrowsKey]) {
		_acceptsArrowKeys = [aDecoder decodeBoolForKey:AGCoderBrowserArrowsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserArrowActionKey]) {
		_sendsActionOnArrowKeys = [aDecoder decodeBoolForKey:AGCoderBrowserArrowActionKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserBackgroundKey]) {
		_backgroundColor = [[aDecoder decodeObjectForKey:AGCoderBrowserBackgroundKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserCellPrototypeKey]) {
		_cellPrototype = [[aDecoder decodeObjectForKey:AGCoderBrowserCellPrototypeKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserDoubleActionKey]) {
		NSString *name = [aDecoder decodeObjectForKey:AGCoderBrowserDoubleActionKey];

		if ([name isKindOfClass:[NSString class]]) {
			_doubleAction = NSSelectorFromString(name);
		}
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserCellClassKey]) {
		NSString *name = [aDecoder decodeObjectForKey:AGCoderBrowserCellClassKey];

		if ([name isKindOfClass:[NSString class]]) {
			_cellClass = NSClassFromString(name);
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)initWithFrame:(NSRect)frameRect
{
	NSRect documentFrame = NSMakeRect(0.0, 0.0, frameRect.size.width, frameRect.size.height);

	self = [super initWithFrame:frameRect];
	if (self == nil) {
		return nil;
	}
	_tables = [[NSMutableArray alloc] init];
	_columnScrollViews = [[NSMutableArray alloc] init];
	_columnWidths = [[NSMutableArray alloc] init];
	_columnCounts = [[NSMutableArray alloc] init];
	_selectedRows = [[NSMutableArray alloc] init];
	_titles = [[NSMutableArray alloc] init];
	_columnWidth = 200.0;
	_minColumnWidth = 100.0;
	_rowHeight = 18.0;
	_titleHeight = 18.0;
	_maxVisibleColumns = 3;
	_selectedColumn = -1;
	_firstVisibleColumn = 0;
	_columnResizingType = NSBrowserNoColumnResizing;
	_pathSeparator = [@"/" copy];
	_cellClass = [NSBrowserCell class];
	_separatesColumns = YES;
	_allowsEmptySelection = YES;
	_hasHorizontalScroller = YES;
	_acceptsArrowKeys = YES;
	_backgroundColor = [[NSColor whiteColor] retain];

	_documentView = [[NSBrowserDocumentView alloc] initWithFrame:documentFrame];
	[(NSBrowserDocumentView *)_documentView setBrowser:self];
	_scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
	/* **THE OUTER SCROLL IS HORIZONTAL; EACH COLUMN IS THE VERTICAL ONE.** A shared vertical scroller was the
	 * shape before the columns got their own scroll views, and it made a tall folder move every column. */
	[_scrollView setHasVerticalScroller:NO];
	[_scrollView setHasHorizontalScroller:_hasHorizontalScroller];
	/* The outer bar is horizontal only, and a browser narrower than its columns keeps it; a browser that
	 * fits its columns does not. */
	[_scrollView setAutohidesScrollers:YES];
	[_scrollView setBorderType:NSNoBorder];
	[_scrollView setDrawsBackground:YES];
	[_scrollView setBackgroundColor:[NSColor colorWithCalibratedWhite:0.82 alpha:1.0]];
	[_scrollView setDocumentView:_documentView];
	[self addSubview:_scrollView];
	return self;
}

- (void)dealloc
{
	[_tables release];
	[_columnScrollViews release];
	[_columnWidths release];
	[_columnCounts release];
	[_selectedRows release];
	[_titles release];
	[_scrollView release];
	[_documentView release];
	[_cellPrototype release];
	[_pathSeparator release];
	[_backgroundColor release];
	[super dealloc];
}

- (id <NSBrowserDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id <NSBrowserDelegate>)delegate { _delegate = delegate; }

/* ---- THE COLUMNS ----------------------------------------------------------------------------- */

- (NSInteger)columnForTable:(NSTableView *)table
{
	NSUInteger index = [_tables indexOfObjectIdenticalTo:table];

	return (index == NSNotFound) ? -1 : (NSInteger)index;
}

- (NSInteger)rowsForColumn:(NSInteger)column
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:numberOfRowsInColumn:)]) {
		return [_delegate browser:self numberOfRowsInColumn:column];
	}
	return 0;
}

- (NSCell *)newDataCell
{
	NSCell *cell;

	if (_cellPrototype != nil) {
		return [[_cellPrototype copy] autorelease];
	}
	cell = [[_cellClass alloc] init];
	return [cell autorelease];
}

- (NSTableView *)createTableForColumn:(NSInteger)column rows:(NSInteger)rows
{
	NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:@"browser"];
	NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, _columnWidth, _rowHeight)];
	NSScrollView *columnScroll;
	NSCell *cell = [self newDataCell];

	[tableColumn setWidth:_columnWidth];
	[tableColumn setDataCell:cell];
	[table addTableColumn:tableColumn];
	[tableColumn release];
	[table setHeaderView:nil];
	[table setRowHeight:_rowHeight];
	[table setIntercellSpacing:NSMakeSize(0.0, 0.0)];
	[table setGridStyleMask:NSTableViewGridNone];
	[table setAllowsColumnReordering:NO];
	[table setAllowsColumnResizing:NO];
	[table setAllowsMultipleSelection:_allowsMultipleSelection];
	[table setAllowsEmptySelection:_allowsEmptySelection];
	[table setBackgroundColor:_backgroundColor];
	[table setDataSource:self];
	[table setDelegate:self];
	[table setDoubleAction:@selector(cg_tableDoubleClicked:)];
	/* **ONE SCROLL VIEW PER COLUMN, AND IT IS THE VERTICAL ONE.** It is the document of the browser's outer
	 * scroll view, not a sibling of it: the outer view still owns the horizontal travel across the columns. A
	 * slot starts at ITS OWN x, not at zero: the pool is built before the first tile, and a column left at zero
	 * would cover the root until it happened to be laid out. */
	columnScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(
						     (CGFloat)column * (_columnWidth
									+ (_separatesColumns ? AG_BROWSER_GAP : 0.0)),
						     0.0, _columnWidth, [self bounds].size.height)];
	[columnScroll setHasVerticalScroller:YES];
	[columnScroll setAutohidesScrollers:YES];
	[columnScroll setHasHorizontalScroller:NO];
	[columnScroll setBorderType:NSNoBorder];
	[columnScroll setDrawsBackground:YES];
	[columnScroll setBackgroundColor:_backgroundColor];
	[columnScroll setDocumentView:table];
	[_documentView addSubview:columnScroll];
	[_tables addObject:table];
	[_columnScrollViews addObject:columnScroll];
	[_columnWidths addObject:[NSNumber numberWithDouble:_columnWidth]];
	[columnScroll release];
	[_columnCounts addObject:[NSNumber numberWithInteger:rows]];
	[_selectedRows addObject:[NSNumber numberWithInteger:-1]];
	[_titles addObject:[NSNull null]];
	/* THE COUNT MUST BE IN THE ARRAY BEFORE THE TABLE ASKS FOR ROWS: the table is this browser's data source and
	 * finds its column by identity, so a reload before registration answers zero. */
	[table reloadData];
	[table release];
	return [_tables lastObject];
}

- (void)ensureColumn:(NSInteger)column rows:(NSInteger)rows
{
	if (column < 0 || column >= AG_BROWSER_COLUMN_POOL) {
		return;
	}
	while (column >= (NSInteger)[_tables count] && (NSInteger)[_tables count] < AG_BROWSER_COLUMN_POOL) {
		(void)[self createTableForColumn:(NSInteger)[_tables count] rows:0];
	}
	if (column < (NSInteger)[_tables count]) {
		NSTableView *table = [_tables objectAtIndex:(NSUInteger)column];

		[_columnCounts replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:rows]];
		[table reloadData];
	}
}

/* **AN EMPTY SLOT IS KEPT, NOT REMOVED.** Navigation back to a shallower column clears the rows in the slots that
 * followed it, but their scroll views, tables and widths stay: that is what lets a folder's column width survive
 * stepping away and back, and it is why the pool is built once. */
- (void)truncateColumnsAfter:(NSInteger)column
{
	NSInteger oldActive = [self cg_activeColumnCount];
	NSInteger i;

	for (i = column + 1; i < oldActive && i < (NSInteger)[_tables count]; i++) {
		NSTableView *table = [_tables objectAtIndex:(NSUInteger)i];

		[_columnCounts replaceObjectAtIndex:(NSUInteger)i withObject:[NSNumber numberWithInteger:0]];
		[_selectedRows replaceObjectAtIndex:(NSUInteger)i withObject:[NSNumber numberWithInteger:-1]];
		[_titles replaceObjectAtIndex:(NSUInteger)i withObject:[NSNull null]];
		[table deselectAll:nil];
		[table reloadData];
	}
	if (_selectedColumn > column) {
		_selectedColumn = (column >= 0 && column < (NSInteger)[_tables count]) ? column : -1;
	}
}

- (void)loadColumnZero
{
	NSInteger rows;
	NSInteger i;

	if ([_tables count] == 0) {
		for (i = 0; i < AG_BROWSER_COLUMN_POOL; i++) {
			(void)[self createTableForColumn:i rows:0];
		}
	} else {
		[self truncateColumnsAfter:-1];
	}
	_selectedColumn = -1;
	_firstVisibleColumn = 0;
	rows = [self rowsForColumn:0];
	if ([_tables count] > 0) {
		[_columnCounts replaceObjectAtIndex:0 withObject:[NSNumber numberWithInteger:rows]];
		[[_tables objectAtIndex:0] reloadData];
	}
	[self tile];
	[self scrollColumnToVisible:0];
}

- (void)reloadColumn:(NSInteger)column
{
	NSTableView *table;
	NSInteger rows;
	NSInteger selected;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return;
	}
	table = [_tables objectAtIndex:(NSUInteger)column];
	rows = [self rowsForColumn:column];
	selected = [[_selectedRows objectAtIndex:(NSUInteger)column] integerValue];
	[_columnCounts replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:rows]];
	[self truncateColumnsAfter:column];
	[table reloadData];
	if (selected >= rows) {
		selected = -1;
	}
	[_selectedRows replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:selected]];
	if (selected >= 0) {
		NSInteger nextRows;

		_selectedColumn = column;
		[table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selected]
		   byExtendingSelection:NO];
		/* **A RELOAD KEEPS THE SELECTION, SO NO NOTIFICATION LOADS THE NEXT COLUMN.** The table's selection is
		 * already the row we are restoring, and `-selectRowIndexes:` correctly treats that as no change. The column
		 * to the right is therefore asked for HERE, the same way a fresh selection asks for it. */
		nextRows = [self rowsForColumn:column + 1];
		if (nextRows > 0) {
			[self ensureColumn:column + 1 rows:nextRows];
		}
	} else {
		_selectedColumn = -1;
		[table deselectAll:nil];
	}
	[self tile];
}

- (void)reloadData
{
	[self loadColumnZero];
}

- (NSInteger)numberOfRowsInColumn:(NSInteger)column
{
	if (column >= 0 && column < (NSInteger)[_columnCounts count]) {
		return [[_columnCounts objectAtIndex:(NSUInteger)column] integerValue];
	}
	return 0;
}

- (NSInteger)cg_activeColumnCount
{
	NSInteger i;

	for (i = (NSInteger)[_columnCounts count] - 1; i >= 0; i--) {
		if ([[_columnCounts objectAtIndex:(NSUInteger)i] integerValue] > 0) {
			return i + 1;
		}
	}
	return 0;
}

/* ---- THE SELECTION --------------------------------------------------------------------------- */

- (NSInteger)selectedColumn { return _selectedColumn; }

- (NSInteger)selectedRowInColumn:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_selectedRows count]) {
		return -1;
	}
	return [[_selectedRows objectAtIndex:(NSUInteger)column] integerValue];
}

- (NSIndexSet *)selectedRowIndexesInColumn:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return nil;
	}
	return [[_tables objectAtIndex:(NSUInteger)column] selectedRowIndexes];
}

- (NSCell *)selectedCell
{
	NSTableView *table;
	NSInteger row;

	if (_selectedColumn < 0 || _selectedColumn >= (NSInteger)[_tables count]) {
		return nil;
	}
	table = [_tables objectAtIndex:(NSUInteger)_selectedColumn];
	row = [self selectedRowInColumn:_selectedColumn];
	return (row >= 0) ? [table preparedCellAtColumn:0 row:row] : nil;
}

- (NSArray *)selectedCells
{
	NSMutableArray *cells = [[NSMutableArray alloc] init];
	NSInteger i;

	for (i = 0; i < (NSInteger)[_tables count]; i++) {
		NSInteger row = [self selectedRowInColumn:i];

		if (row >= 0) {
			NSCell *cell = [[_tables objectAtIndex:(NSUInteger)i] preparedCellAtColumn:0 row:row];

			if (cell != nil) {
				[cells addObject:cell];
			}
		}
	}
	return [cells autorelease];
}

- (void)selectRowIndexes:(NSIndexSet *)indexes inColumn:(NSInteger)column
{
	NSTableView *table;
	BOOL previous = _inProgrammaticSelection;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return;
	}
	table = [_tables objectAtIndex:(NSUInteger)column];
	_inProgrammaticSelection = YES;
	if (indexes == nil || [indexes count] == 0) {
		[table deselectAll:nil];
	} else {
		[table selectRowIndexes:indexes byExtendingSelection:NO];
	}
	_inProgrammaticSelection = previous;
}

- (void)selectRow:(NSInteger)row inColumn:(NSInteger)column
{
	if (row < 0) {
		[self selectRowIndexes:nil inColumn:column];
	} else {
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] inColumn:column];
	}
}

/* ---- THE PATH -------------------------------------------------------------------------------- */

- (NSString *)pathSeparator { return _pathSeparator; }

- (void)setPathSeparator:(NSString *)separator
{
	NSString *copy = [(separator != nil ? separator : @"/") copy];

	[_pathSeparator release];
	_pathSeparator = copy;
}

- (NSString *)stringForCellAtRow:(NSInteger)row column:(NSInteger)column
{
	NSTableView *table;
	NSCell *cell;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return @"";
	}
	table = [_tables objectAtIndex:(NSUInteger)column];
	cell = [table preparedCellAtColumn:0 row:row];
	return ([cell stringValue] != nil) ? [cell stringValue] : @"";
}

- (NSString *)path
{
	NSMutableArray *parts = [[NSMutableArray alloc] init];
	NSInteger i;

	for (i = 0; i < (NSInteger)[_tables count]; i++) {
		NSInteger row = [self selectedRowInColumn:i];

		if (row < 0) {
			break;
		}
		[parts addObject:[self stringForCellAtRow:row column:i]];
	}
	return [parts count] > 0 ? [parts componentsJoinedByString:_pathSeparator] : nil;
}

- (NSString *)selectedPath { return [self path]; }
- (void)setSelectedPath:(NSString *)path { [self setPath:path]; }

- (void)setPath:(NSString *)path
{
	NSArray *parts;
	NSUInteger i;

	[self loadColumnZero];
	if (path == nil || [path length] == 0) {
		return;
	}
	parts = [path componentsSeparatedByString:_pathSeparator];
	for (i = 0; i < [parts count]; i++) {
		NSString *part = [parts objectAtIndex:i];
		NSInteger column = (NSInteger)i;
		NSInteger rows;
		NSInteger row;
		BOOL found = NO;

		if (column >= (NSInteger)[_tables count]) {
			break;
		}
		rows = [self numberOfRowsInColumn:column];
		for (row = 0; row < rows; row++) {
			if ([[self stringForCellAtRow:row column:column] isEqual:part]) {
				found = YES;
				break;
			}
		}
		if (!found) {
			break;
		}
		[self selectRow:row inColumn:column];
	}
}

/* ---- THE TABLE'S DATA SOURCE AND DELEGATE ---------------------------------------------------- */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	NSInteger column = [self columnForTable:tableView];

	return (column >= 0) ? [self numberOfRowsInColumn:column] : 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	(void)tableColumn;
	(void)row;
	return nil;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSInteger column = [self columnForTable:tableView];

	(void)tableColumn;
	if (column >= 0 && _delegate != nil
	    && [_delegate respondsToSelector:@selector(browser:willDisplayCell:atRow:column:)]) {
		[_delegate browser:self willDisplayCell:cell atRow:row column:column];
	}
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	NSInteger column = [self columnForTable:tableView];

	if (column < 0) {
		return NO;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:selectRow:inColumn:)]) {
		BOOL answer = [_delegate browser:self selectRow:row inColumn:column];
		return answer;
	}
	return YES;
}

- (NSIndexSet *)tableView:(NSTableView *)tableView
    selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes
{
	NSInteger column = [self columnForTable:tableView];

	if (column >= 0 && _delegate != nil
	    && [_delegate respondsToSelector:@selector(browser:selectionIndexesForProposedSelection:inColumn:)]) {
		return [_delegate browser:self selectionIndexesForProposedSelection:proposedSelectionIndexes
				  inColumn:column];
	}
	return proposedSelectionIndexes;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSTableView *table = [notification object];
	NSInteger column = [self columnForTable:table];
	NSInteger row;
	NSInteger nextRows;

	if (column < 0) {
		return;
	}
	row = [table selectedRow];
	[_selectedRows replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithInteger:row]];
	if (row >= 0) {
		_selectedColumn = column;
	} else if (_selectedColumn == column) {
		_selectedColumn = -1;
	}
	[self truncateColumnsAfter:column];
	if (row >= 0) {
		nextRows = [self rowsForColumn:column + 1];
		if (nextRows > 0) {
			[self ensureColumn:column + 1 rows:nextRows];
		}
	}
	[self tile];
	/* **A SELECTION IS NAVIGATION, SO THE NEWEST COLUMN IS THE ONE TO SHOW.** Selecting a branch has already created
	 * (or kept) the column to its right above; scrolling to the selected column alone leaves that new column off the
	 * right edge. Deselecting keeps the old rule, because there is no new column to show. */
	if (row >= 0) {
		[self cg_scrollToLastColumn];
	} else {
		[self scrollColumnToVisible:_selectedColumn];
	}
	if (!_inProgrammaticSelection && [self action] != NULL) {
		[[NSApplication sharedApplication] sendAction:[self action] to:[self target] from:self];
	}
}

- (void)cg_tableDoubleClicked:(id)sender
{
	(void)sender;
	if (_doubleAction != NULL) {
		[[NSApplication sharedApplication] sendAction:_doubleAction to:[self target] from:self];
	}
}

- (SEL)doubleAction { return _doubleAction; }
- (void)setDoubleAction:(SEL)action { _doubleAction = action; }

/* ---- GEOMETRY -------------------------------------------------------------------------------- */

- (CGFloat)columnWidth { return _columnWidth; }
- (CGFloat)minColumnWidth { return _minColumnWidth; }
- (NSInteger)maxVisibleColumns { return _maxVisibleColumns; }
- (BOOL)separatesColumns { return _separatesColumns; }
- (BOOL)allowsMultipleSelection { return _allowsMultipleSelection; }
- (BOOL)allowsEmptySelection { return _allowsEmptySelection; }
- (BOOL)takesTitleFromPreviousColumn { return _takesTitleFromPreviousColumn; }
- (BOOL)hasHorizontalScroller { return _hasHorizontalScroller; }
- (BOOL)acceptsArrowKeys { return _acceptsArrowKeys; }
- (BOOL)sendsActionOnArrowKeys { return _sendsActionOnArrowKeys; }
- (CGFloat)rowHeight { return _rowHeight; }
- (CGFloat)titleHeight { return _titleHeight; }
- (NSBrowserColumnResizingType)columnResizingType { return _columnResizingType; }
- (NSColor *)backgroundColor { return _backgroundColor; }

/* ---- THE PER-COLUMN GEOMETRY ---------------------------------------------------------------- */

- (CGFloat)widthOfColumn:(NSInteger)column
{
	if (column >= 0 && column < (NSInteger)[_columnWidths count]) {
		return (CGFloat)[[_columnWidths objectAtIndex:(NSUInteger)column] doubleValue];
	}
	return _columnWidth;
}

- (CGFloat)fn_frameWidthForColumn:(NSInteger)column
{
	/* A COLUMN'S WIDTH IS ITS FRAME'S. The vertical scroller lives INSIDE it, so a visible bar narrows the
	 * table rather than widening the column — which is what makes `-columnWidth` and the visible column the
	 * same measure, and what keeps the width door's old contract with the private table. */
	return [self widthOfColumn:column];
}

- (CGFloat)fn_xOriginForColumn:(NSInteger)column
{
	CGFloat gap = _separatesColumns ? AG_BROWSER_GAP : 0.0;
	CGFloat x = 0.0;
	NSInteger i;

	for (i = 0; i < column && i < (NSInteger)[_tables count]; i++) {
		x += [self fn_frameWidthForColumn:i] + gap;
	}
	return x;
}

/* **A COLUMN THAT CANNOT BE SEEN IS NOT A SUBVIEW.** The pool keeps every slot's state, but only the active slots
 * and the empty ones inside the visible width are attached to the document; the other 250-odd views would otherwise
 * be walked by every draw, hit test and tracking-area pass. */
- (void)fn_attachColumn:(NSInteger)column
{
	NSScrollView *columnScroll;

	if (column < 0 || column >= (NSInteger)[_columnScrollViews count]) {
		return;
	}
	columnScroll = [_columnScrollViews objectAtIndex:(NSUInteger)column];
	if ([columnScroll superview] != _documentView) {
		[_documentView addSubview:columnScroll];
	}
}

- (void)fn_detachColumn:(NSInteger)column
{
	NSScrollView *columnScroll;

	if (column < 0 || column >= (NSInteger)[_columnScrollViews count]) {
		return;
	}
	columnScroll = [_columnScrollViews objectAtIndex:(NSUInteger)column];
	if ([columnScroll superview] == _documentView) {
		[columnScroll removeFromSuperview];
	}
}

- (void)setWidth:(CGFloat)width ofColumn:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_columnWidths count]) {
		return;
	}
	if (width < _minColumnWidth) {
		width = _minColumnWidth;
	}
	[_columnWidths replaceObjectAtIndex:(NSUInteger)column withObject:[NSNumber numberWithDouble:width]];
	[self tile];
}

- (void)fn_sizeColumnToFit:(NSInteger)column
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:sizeToFitWidthOfColumn:)]) {
		CGFloat width = [_delegate browser:self sizeToFitWidthOfColumn:column];

		if (width > 0.0) {
			[self setWidth:width ofColumn:column];
		}
	}
}

- (void)tile
{
	CGFloat gap = _separatesColumns ? AG_BROWSER_GAP : 0.0;
	NSSize available = [NSScrollView contentSizeForFrameSize:[self bounds].size
							  hasHorizontalScroller:_hasHorizontalScroller
							    hasVerticalScroller:NO
								     borderType:NSNoBorder];
	NSInteger pass;
	NSInteger active = [self cg_activeColumnCount];

	[_scrollView setFrame:[self bounds]];
	[_scrollView setHasHorizontalScroller:_hasHorizontalScroller];
	[_scrollView setHasVerticalScroller:NO];
	[_scrollView setBackgroundColor:_separatesColumns ? [NSColor colorWithCalibratedWhite:0.82 alpha:1.0] : _backgroundColor];

	/* **THE OUTER HORIZONTAL BAR CAN HIDE, AND HIDING IT MAKES THE CLIP VIEW TALLER.** The first pass lays
	 * the columns out for the content size the configured bar would leave; if the outer bar chose to hide, the
	 * second pass re-lays them into the taller content and widens the document to the new content width so the
	 * columns stay at the left rather than being centred by the clip view. */
	for (pass = 0; pass < 2; pass++) {
		CGFloat x = 0.0;
		CGFloat documentWidth;
		NSUInteger i;

		/* Laid-out slots are the active ones plus as many empty ones as the visible width holds; the rest stay at
		 * the x they were born at, outside the document. The DOCUMENT is sized by the active columns only, so the
		 * pool never becomes horizontal scroll travel. */
		for (i = 0; i < [_tables count] && ((NSInteger)i < active || x < available.width); i++) {
			NSTableView *table = [_tables objectAtIndex:i];
			NSScrollView *columnScroll = [_columnScrollViews objectAtIndex:i];
			NSArray *columns;
			CGFloat frameWidth = [self fn_frameWidthForColumn:(NSInteger)i];
			NSSize content;
			CGFloat tableHeight;

			/* **THE COLUMN'S OWN SETTINGS ARE ALREADY MADE.** Re-setting the scroller, the autohide
			 * policy and the background here re-tiled the scroll view three more times per column per pass. */
			[columnScroll setFrame:NSMakeRect(x, 0.0, frameWidth, available.height)];
			content = [columnScroll contentSize];
			tableHeight = (CGFloat)[[_columnCounts objectAtIndex:i] integerValue] * _rowHeight;
			if (tableHeight < content.height) {
				tableHeight = content.height;
			}
			[table setFrame:NSMakeRect(0.0, 0.0, content.width, tableHeight)];
			/* THE TABLE'S HEIGHT IS WHAT DECIDES WHETHER THE COLUMN'S BAR IS NEEDED, so the scroll view tiles a
			 * second time now that the height exists. If the bar has just hidden, the content is wider by the
			 * bar's width and the table takes that width; the height cannot change because this scroll view has
			 * no horizontal bar of its own. */
			[columnScroll tile];
			content = [columnScroll contentSize];
			if (tableHeight < content.height) {
				tableHeight = content.height;
			}
			[table setFrame:NSMakeRect(0.0, 0.0, content.width, tableHeight)];
			columns = [table tableColumns];
			if ([columns count] > 0) {
				[[columns objectAtIndex:0] setWidth:content.width];
			}
			[self fn_attachColumn:(NSInteger)i];
			x += frameWidth + gap;
		}
		for (; i < [_tables count]; i++) {
			[self fn_detachColumn:(NSInteger)i];
		}
		/* **ONLY THE ACTIVE COLUMNS (AND THE EMPTIES THAT FIT BESIDE THEM) SIZE THE DOCUMENT.** The 256 slots exist
		 * so navigation keeps their widths, but the ones beyond the visible area do not become horizontal scroll
		 * travel: `documentWidth` ends at the last active column or the visible width, whichever is farther. */
		documentWidth = (active > 0) ? ([self fn_xOriginForColumn:active] - gap) : 0.0;
		if (documentWidth < available.width) {
			documentWidth = available.width;
		}
		[_documentView setFrame:NSMakeRect(0.0, 0.0, documentWidth, available.height)];
		[_scrollView tile];
		{
			NSSize actual = [_scrollView contentSize];

			if (fabs(actual.width - available.width) < 0.01
			    && fabs(actual.height - available.height) < 0.01) {
				break;
			}
			available = actual;
		}
	}
	[_documentView setNeedsDisplay:YES];
	if ([_documentView window] != nil) {
		[[_documentView window] invalidateCursorRectsForView:_documentView];
	}
	_firstVisibleColumn = [self firstVisibleColumn];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
	(void)oldSize;
	[self tile];
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self tile];
}

/* **A FRAME CHANGE RE-TILES, AND `-setFrameSize:` ALONE DID NOT COVER IT.** The browser's whole face is the scroll
 * view inside it, and `-tile` is what gives that scroll view the browser's bounds. `NSView -setFrame:` does not call
 * `-resizeSubviewsWithOldSize:` in this tier, so a caller that set a browser's FRAME — which is what a containing
 * view does when it lays out a browser beside a preview panel — left the scroll view at its old width. MEASURED in
 * Workspace: widening the file window put a gap between the column browser and the preview panel. The class that
 * owns the scroll view is the class that has to re-tile it. */
- (void)setFrame:(NSRect)frameRect
{
	NSSize oldSize = [self frame].size;

	[super setFrame:frameRect];
	if (oldSize.width != frameRect.size.width || oldSize.height != frameRect.size.height) {
		[self tile];
	}
}

- (void)setColumnWidth:(CGFloat)width
{
	NSUInteger i;

	if (width < _minColumnWidth) {
		width = _minColumnWidth;
	}
	_columnWidth = width;
	for (i = 0; i < [_columnWidths count]; i++) {
		[_columnWidths replaceObjectAtIndex:i withObject:[NSNumber numberWithDouble:width]];
	}
	[self tile];
}

- (void)setMinColumnWidth:(CGFloat)width
{
	NSUInteger i;

	_minColumnWidth = (width > 0.0) ? width : 1.0;
	if (_columnWidth < _minColumnWidth) {
		_columnWidth = _minColumnWidth;
	}
	for (i = 0; i < [_columnWidths count]; i++) {
		CGFloat current = (CGFloat)[[_columnWidths objectAtIndex:i] doubleValue];

		if (current < _minColumnWidth) {
			[_columnWidths replaceObjectAtIndex:i
						 withObject:[NSNumber numberWithDouble:_minColumnWidth]];
		}
	}
	[self tile];
}

- (void)setMaxVisibleColumns:(NSInteger)count
{
	_maxVisibleColumns = (count > 0) ? count : 1;
	[self tile];
}

- (void)setSeparatesColumns:(BOOL)flag
{
	_separatesColumns = flag ? YES : NO;
	[self tile];
}

- (void)setAllowsMultipleSelection:(BOOL)flag
{
	NSUInteger i;

	_allowsMultipleSelection = flag ? YES : NO;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setAllowsMultipleSelection:_allowsMultipleSelection];
	}
}

- (void)setAllowsEmptySelection:(BOOL)flag
{
	NSUInteger i;

	_allowsEmptySelection = flag ? YES : NO;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setAllowsEmptySelection:_allowsEmptySelection];
	}
}

- (void)setTakesTitleFromPreviousColumn:(BOOL)flag { _takesTitleFromPreviousColumn = flag ? YES : NO; }
- (void)setHasHorizontalScroller:(BOOL)flag
{
	_hasHorizontalScroller = flag ? YES : NO;
	[self tile];
}
- (void)setAcceptsArrowKeys:(BOOL)flag { _acceptsArrowKeys = flag ? YES : NO; }
- (void)setSendsActionOnArrowKeys:(BOOL)flag { _sendsActionOnArrowKeys = flag ? YES : NO; }

- (void)setRowHeight:(CGFloat)height
{
	NSUInteger i;

	_rowHeight = (height > 0.0) ? height : 1.0;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setRowHeight:_rowHeight];
	}
	[self tile];
}

- (void)setTitleHeight:(CGFloat)height { _titleHeight = height; }
- (void)setColumnResizingType:(NSBrowserColumnResizingType)type
{
	_columnResizingType = type;
	[_documentView setNeedsDisplay:YES];
	if ([_documentView window] != nil) {
		[[_documentView window] invalidateCursorRectsForView:_documentView];
	}
}

- (void)setBackgroundColor:(NSColor *)color
{
	NSUInteger i;

	[color retain];
	[_backgroundColor release];
	_backgroundColor = color;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setBackgroundColor:_backgroundColor];
		[[_columnScrollViews objectAtIndex:i] setBackgroundColor:_backgroundColor];
	}
	[self tile];
}

- (NSInteger)numberOfVisibleColumns
{
	CGFloat origin = [[_scrollView contentView] bounds].origin.x;
	CGFloat right = origin + [[_scrollView contentView] bounds].size.width;
	NSInteger visible = 0;
	NSInteger i;

	for (i = 0; i < (NSInteger)[_tables count]; i++) {
		CGFloat x = [self fn_xOriginForColumn:i];
		CGFloat columnRight = x + [self fn_frameWidthForColumn:i];

		if (columnRight > origin && x < right) {
			visible++;
		}
	}
	if (visible < 1 && [_tables count] > 0) {
		visible = 1;
	}
	if (_maxVisibleColumns > 0 && visible > _maxVisibleColumns) {
		visible = _maxVisibleColumns;
	}
	return visible;
}

- (NSInteger)firstVisibleColumn
{
	CGFloat origin = [[_scrollView contentView] bounds].origin.x;
	NSInteger i;

	for (i = 0; i < (NSInteger)[_tables count]; i++) {
		CGFloat right = [self fn_xOriginForColumn:i] + [self fn_frameWidthForColumn:i];

		if (right > origin) {
			return i;
		}
	}
	return 0;
}

- (NSInteger)lastVisibleColumn
{
	CGFloat origin = [[_scrollView contentView] bounds].origin.x;
	CGFloat right = origin + [[_scrollView contentView] bounds].size.width;
	NSInteger last = [self firstVisibleColumn];
	NSInteger i;

	for (i = last; i < (NSInteger)[_tables count]; i++) {
		CGFloat x = [self fn_xOriginForColumn:i];

		if (x < right) {
			last = i;
		} else {
			break;
		}
	}
	return last;
}

- (void)scrollColumnToVisible:(NSInteger)column
{
	CGFloat x;
	CGFloat origin;
	CGFloat width;
	NSPoint point;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return;
	}
	x = [self fn_xOriginForColumn:column];
	width = [[_scrollView contentView] bounds].size.width;
	origin = [[_scrollView contentView] bounds].origin.x;
	if (x < origin || x + [self fn_frameWidthForColumn:column] > origin + width) {
		point = NSMakePoint(x, 0.0);
		[[_scrollView contentView] scrollToPoint:point];
		[_scrollView reflectScrolledClipView:[_scrollView contentView]];
	}
	_firstVisibleColumn = [self firstVisibleColumn];
}

/* **THE END OF THE DOCUMENT, WHICH IS WHERE A NEW COLUMN BELONGS.** `-scrollColumnToVisible:` answers "is this
 * column in view" by putting its left edge at the clip view's left when it is not, which is right for a column in the
 * middle and wrong for the newest one: the final column would sit at the left with empty document to its right.
 * A selection that opens a column is navigation, and Finder's rule is that the NEW column is the one the person is
 * looking at — so the clip view goes to the document's far end and the last column lands against the right edge. */
- (void)cg_scrollToLastColumn
{
	CGFloat width = [[_scrollView contentView] bounds].size.width;
	CGFloat documentWidth = [_documentView frame].size.width;
	CGFloat origin = documentWidth - width;
	NSPoint point;

	if (origin < 0.0) {
		origin = 0.0;
	}
	point = NSMakePoint(origin, 0.0);
	[[_scrollView contentView] scrollToPoint:point];
	[_scrollView reflectScrolledClipView:[_scrollView contentView]];
	_firstVisibleColumn = [self firstVisibleColumn];
}

/* ---- THE CELL, THE TITLE AND THE SEAMS ------------------------------------------------------- */

- (Class)cellClass { return _cellClass; }

- (void)setCellClass:(Class)cellClass
{
	NSUInteger i;

	_cellClass = (cellClass != Nil) ? cellClass : [NSBrowserCell class];
	for (i = 0; i < [_tables count]; i++) {
		NSArray *columns = [[_tables objectAtIndex:i] tableColumns];

		if ([columns count] > 0) {
			[[columns objectAtIndex:0] setDataCell:[self newDataCell]];
		}
	}
	[self reloadData];
}

- (NSCell *)cellPrototype { return _cellPrototype; }

- (void)setCellPrototype:(NSCell *)cell
{
	NSUInteger i;

	[cell retain];
	[_cellPrototype release];
	_cellPrototype = cell;
	for (i = 0; i < [_tables count]; i++) {
		NSArray *columns = [[_tables objectAtIndex:i] tableColumns];

		if ([columns count] > 0) {
			[[columns objectAtIndex:0] setDataCell:[self newDataCell]];
		}
	}
	[self reloadData];
}

- (void)setTitle:(NSString *)title ofColumn:(NSInteger)column
{
	while ((NSInteger)[_titles count] <= column) {
		[_titles addObject:[NSNull null]];
	}
	[_titles replaceObjectAtIndex:(NSUInteger)column
			     withObject:(title != nil) ? (id)title : (id)[NSNull null]];
}

- (NSString *)titleOfColumn:(NSInteger)column
{
	id title;

	if (column >= 0 && column < (NSInteger)[_titles count]) {
		title = [_titles objectAtIndex:(NSUInteger)column];
		if (title != [NSNull null]) {
			return title;
		}
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:titleOfColumn:)]) {
		return [_delegate browser:self titleOfColumn:column];
	}
	return nil;
}

- (NSString *)browser:(NSBrowser *)sender titleOfColumn:(NSInteger)column
{
	(void)sender;
	return [self titleOfColumn:column];
}

- (NSInteger)cg_columnCount { return (NSInteger)[_tables count]; }
- (NSTableView *)cg_tableForColumn:(NSInteger)column
{
	return (column >= 0 && column < (NSInteger)[_tables count])
		? [_tables objectAtIndex:(NSUInteger)column] : nil;
}
- (NSScrollView *)cg_scrollViewForColumn:(NSInteger)column
{
	return (column >= 0 && column < (NSInteger)[_columnScrollViews count])
		? [_columnScrollViews objectAtIndex:(NSUInteger)column] : nil;
}
- (NSRect)cg_dividerFrameForColumn:(NSInteger)column
{
	NSRect frame;

	if (column < 0 || column + 1 >= (NSInteger)[_tables count] || !_separatesColumns) {
		return NSZeroRect;
	}
	frame = [_documentView frame];
	return NSMakeRect([self fn_xOriginForColumn:column] + [self fn_frameWidthForColumn:column],
			  0.0, AG_BROWSER_GAP, frame.size.height);
}
- (NSView *)cg_documentView { return _documentView; }

@end
