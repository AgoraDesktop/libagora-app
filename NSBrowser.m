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
#import <AppKit/NSScroller.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSScroller.h>
#import <Foundation/NSIndexSet.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSView.h>
#import "NSWindow_internal.h"
#import "AppKitRefusal.h"	/* the refused doors say what they need. */
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
/* THE DOCUMENT-COORDINATE HALVES THE DOCUMENT VIEW NEEDS: the strip's rect where it draws, and the title itself. */
- (NSRect)cg_titleStripFrameForColumnInDocument:(NSInteger)column;
- (NSRect)cg_columnFrameInDocument:(NSInteger)column;
- (CGFloat)fn_xOriginForColumn:(NSInteger)column;
- (CGFloat)fn_frameWidthForColumn:(NSInteger)column;
@end

@implementation NSBrowserDocumentView

/* **THE DOCUMENT IS FLIPPED, WHICH IT WAS NOT, AND THE TITLE STRIP IS WHY.** A column's title belongs ABOVE its list, and
 * a flipped document says that with y = 0 at the top; the alternative was arithmetic against the bounds height at every
 * site and a text draw in an unflipped context, which is the mirror this tree has paid for before (`HANDOFF-2.md` §4).
 * The table inside each column is flipped too, so a row's rect converts to the document without a mirror, and the
 * gutters — which span the whole height — are unaffected. */
- (BOOL)isFlipped
{
	return YES;
}

- (void)setBrowser:(NSBrowser *)browser
{
	_browser = browser;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger count, i;

	(void)dirtyRect;
	if (_browser == nil) {
		return;
	}
	/* **THE TITLES ARE DRAWN BY THE DOCUMENT, ONE PER COLUMN, IN THE STRIP THE BROWSER LAID OUT.** The columns are
	 * subviews and draw themselves; the strip is above where they start, so nothing but this view could own it — and
	 * the browser's `-drawTitleOfColumn:inRect:` is the door so a subclass can change how a title looks. */
	if ([_browser isTitled]) {
		count = [_browser cg_columnCount];
		for (i = 0; i < count; i++) {
			NSRect strip = [_browser cg_titleStripFrameForColumnInDocument:i];

			if (NSIsEmptyRect(strip) || NSMinX(strip) >= NSMaxX([self bounds])) {
				continue;
			}
			[_browser drawTitleOfColumn:i inRect:strip];
		}
	}
	if (![_browser separatesColumns]) {
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
	/* **ONE DRAG, EVERY COLUMN, WHEN THE CALLER ASKS FOR IT.** `-prefersAllColumnUserResizing` is the era's knob for a
	 * browser whose columns are meant to stay the same width; without it a divider drag resizes the column it is on. */
	if ([_browser prefersAllColumnUserResizing]) {
		NSInteger i, count = [_browser cg_columnCount];

		for (i = 0; i < count; i++) {
			if (i != _dragColumn) {
				[_browser setWidth:width ofColumn:i];
			}
		}
	}
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
	/* **APPLE'S DEFAULTS, INCLUDING THE ONE THIS CLASS DID NOT HAVE.** A browser's columns are TITLED unless a caller says
	 * otherwise, and no click has happened yet — which `-clickedRow`/`-clickedColumn` answer as -1. */
	_titled = YES;
	_clickedRow = -1;
	_clickedColumn = -1;
	/* **AND THE REST OF THE ERA'S DEFAULTS, WHICH ARE APPLE'S WHERE APPLE STATS ONE.** `-lastColumn` unset means "wherever
	 * the selection chain ends"; the drag mask is Copy/Generic, which is the source operation Apple's own browser offers;
	 * `-allowsBranchSelection` is NO and `-allowsTypeSelect` is YES, both Apple's defaults; and
	 * `-prefersAllColumnUserResizing` is NO, so a divider drag resizes the column it is dragged on. */
	_loadedZero = NO;
	_lastColumn = -1;
	_localDragMask = NSDragOperationCopy | NSDragOperationGeneric;
	_nonLocalDragMask = NSDragOperationCopy | NSDragOperationGeneric;
	_allowsBranchSelection = NO;
	_allowsTypeSelect = YES;
	_prefersAllColumnUserResizing = NO;
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
	[_columnsAutosaveName release];
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

/* **THE ROW COUNT COMES FROM THE ITEM MODEL WHEN THE DELEGATE SPEAKS IT.** Column zero asks for the children of nil —
 * the root — and every later column for the children of the item selected in the column to its left, which is what makes
 * the browser a hierarchy rather than a list of lists. The cell-based door is the fallback, and a delegate that answers
 * neither yields an empty column rather than a wrong one. */
- (NSInteger)rowsForColumn:(NSInteger)column
{
	if ([self cg_isItemBased]) {
		return [_delegate browser:self numberOfChildrenOfItem:[self parentForItemsInColumn:column]];
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:numberOfRowsInColumn:)]) {
		return [_delegate browser:self numberOfRowsInColumn:column];
	}
	return 0;
}


/* ============================================================================================ *
 * THE ITEM-BASED MODEL: WALKING FROM NIL, AND THE ROWS IT PRODUCES                              *
 *                                                                                              *
 * **THE DELEGATE OWNS EVERY ITEM AND THE BROWSER RETAINS NONE**, which is why nothing here is  *
 * cached: each reading door follows `-browser:child:ofItem:` from the root, and the only state  *
 * the walk consumes is the selected rows this class already keeps. That is also why a path that *
 * runs out answers nil instead of a stale object — the walk has nowhere to go.                    *
 * ============================================================================================ */

/* WHETHER THE DELEGATE WANTS THE 10.6 MODEL. The count door is the test, because a browser cannot ask for children
 * without it; `-browser:child:ofItem:` alone would give it nothing to iterate. */
- (BOOL)cg_isItemBased
{
	return (_delegate != nil && [_delegate respondsToSelector:@selector(browser:numberOfChildrenOfItem:)]);
}

- (id)cg_childOfItem:(id)item atIndex:(NSInteger)index
{
	if (index < 0 || _delegate == nil || ![_delegate respondsToSelector:@selector(browser:child:ofItem:)]) {
		return nil;
	}
	return [_delegate browser:self child:index ofItem:item];
}

/* **THE ITEM WHOSE CHILDREN A COLUMN SHOWS.** Column zero's parent is the ROOT, which is nil; every later column's is the
 * item at the selected row of the column before it. A column before the selection chain has no parent, and the walk
 * stops there rather than guessing. */
- (id)parentForItemsInColumn:(NSInteger)column
{
	id item = nil;
	NSInteger i;

	if (column <= 0) {
		return nil;
	}
	for (i = 0; i < column; i++) {
		NSInteger row;

		if (i >= (NSInteger)[_selectedRows count]) {
			return nil;
		}
		row = [[_selectedRows objectAtIndex:(NSUInteger)i] integerValue];
		if (row < 0) {
			return nil;
		}
		item = [self cg_childOfItem:item atIndex:row];
	}
	return item;
}

- (id)itemAtRow:(NSInteger)row inColumn:(NSInteger)column
{
	id parent;

	if (row < 0) {
		return [self parentForItemsInColumn:column];
	}
	parent = [self parentForItemsInColumn:column];
	return [self cg_childOfItem:parent atIndex:row];
}

- (id)itemAtIndexPath:(NSIndexPath *)indexPath
{
	id item = nil;
	NSUInteger i, length;

	if (indexPath == nil) {
		return nil;
	}
	length = [indexPath length];
	for (i = 0; i < length; i++) {
		item = [self cg_childOfItem:item atIndex:(NSInteger)[indexPath indexAtPosition:i]];
		if (item == nil) {
			return nil;
		}
	}
	return item;
}

- (BOOL)isLeafItem:(id)item
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:isLeafItem:)]) {
		return [_delegate browser:self isLeafItem:item];
	}
	return NO;
}

/* THE PARENT'S PATH: one index per column BEFORE this one, taken from the selected rows. */
- (NSIndexPath *)indexPathForColumn:(NSInteger)column
{
	NSUInteger indexes[AG_BROWSER_COLUMN_POOL];
	NSInteger i;

	if (column <= 0 || column > (NSInteger)[_selectedRows count]) {
		return [NSIndexPath indexPathWithIndexes:indexes length:0];
	}
	for (i = 0; i < column; i++) {
		NSInteger row = [[_selectedRows objectAtIndex:(NSUInteger)i] integerValue];

		if (row < 0) {
			return [NSIndexPath indexPathWithIndexes:indexes length:0];
		}
		indexes[i] = (NSUInteger)row;
	}
	return [NSIndexPath indexPathWithIndexes:indexes length:(NSUInteger)column];
}

/* **THE SAME CHAIN AS A STRING, WHICH IS WHAT A CALLER SAVING A LOCATION WANTS.** Each step is a column's selected
 * cell's string, joined by `-pathSeparator`; the cells are the browser's own, so the string agrees with what is on
 * screen rather than with what the items would print. */
- (NSString *)pathToColumn:(NSInteger)column
{
	NSMutableString *answer = [NSMutableString string];
	NSInteger i;

	if (column <= 0) {
		return @"";
	}
	for (i = 0; i < column; i++) {
		NSInteger row = [[_selectedRows objectAtIndex:(NSUInteger)i] integerValue];
		NSString *part;

		if (row < 0) {
			break;
		}
		part = [self stringForCellAtRow:row column:i];
		if (part == nil) {
			break;
		}
		if ([answer length] > 0) {
			[answer appendString:((_pathSeparator != nil) ? _pathSeparator : @"/")];
		}
		[answer appendString:part];
	}
	return answer;
}

/* THE SELECTION AS ONE PATH — the last column's row last. */
- (NSIndexPath *)selectionIndexPath
{
	NSUInteger indexes[AG_BROWSER_COLUMN_POOL];
	NSInteger count = 0;
	NSInteger i;

	if (_selectedColumn < 0) {
		return nil;
	}
	for (i = 0; i <= _selectedColumn && i < (NSInteger)[_selectedRows count]; i++) {
		NSInteger row = [[_selectedRows objectAtIndex:(NSUInteger)i] integerValue];

		if (row < 0) {
			break;
		}
		indexes[count++] = (NSUInteger)row;
	}
	return (count > 0) ? [NSIndexPath indexPathWithIndexes:indexes length:(NSUInteger)count] : nil;
}

/* **SELECTING A PATH IS SELECTING EACH COLUMN IN TURN**, which loads the next column the way a click does — the rows are
 * the browser's own state, so `-selectRow:inColumn:` is the one door that has to be used, and it already truncates
 * whatever was to the right. A path whose row is out of range stops the walk rather than selecting a phantom. */
- (void)setSelectionIndexPath:(NSIndexPath *)path
{
	NSUInteger i, length;

	if (path == nil) {
		for (i = 0; i < (NSUInteger)[_selectedRows count]; i++) {
			(void)[self selectRowIndexes:nil inColumn:(NSInteger)i];
		}
		_selectedColumn = -1;
		return;
	}
	length = [path length];
	for (i = 0; i < length; i++) {
		NSInteger row = (NSInteger)[path indexAtPosition:i];
		NSInteger rows;

		if (i >= (NSUInteger)[_tables count]) {
			break;
		}
		rows = [self numberOfRowsInColumn:(NSInteger)i];
		if (row < 0 || row >= rows) {
			break;
		}
		[self selectRow:row inColumn:(NSInteger)i];
	}
}

/* AND THE PLURAL FORM IS APPLE'S, EVEN THOUGH A BROWSER HAS ONE SELECTION: the array holds the one path this class can
 * represent, or nothing at all. Saying so is better than pretending several selections exist. */
- (NSArray *)selectionIndexPaths
{
	NSIndexPath *path = [self selectionIndexPath];

	return (path != nil) ? [NSArray arrayWithObject:path] : [NSArray array];
}

- (void)setSelectionIndexPaths:(NSArray *)paths
{
	[self setSelectionIndexPath:([paths count] > 0) ? [paths objectAtIndex:0] : nil];
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
	[table setAllowsTypeSelect:_allowsTypeSelect];
	[table setDraggingSourceOperationMask:_localDragMask forLocal:YES];
	[table setDraggingSourceOperationMask:_nonLocalDragMask forLocal:NO];
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
	_lastColumn = -1;
	_loadedZero = YES;
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

/* **A ROW'S CELL IS THE ITEM'S CELL WHEN THE DELEGATE IS ITEM-BASED, AND THE DELEGATE MAY THEN STYLE IT.** The browser
 * asks `-browser:objectValueForItem:` for what the cell shows and `-browser:isLeafItem:` for whether a branch triangle
 * belongs — that is the browser making the cell, which is the entire point of the 10.6 model — and only afterwards does
 * `-browser:willDisplayCell:atRow:column:` get its chance, which is the one overlap Apple allows between the two
 * contracts. A cell-based delegate sees exactly what it saw before. */
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSInteger column = [self columnForTable:tableView];

	(void)tableColumn;
	if (column < 0) {
		return;
	}
	if ([self cg_isItemBased] && _delegate != nil) {
		id item = [self itemAtRow:row inColumn:column];

		if (item != nil) {
			if ([_delegate respondsToSelector:@selector(browser:objectValueForItem:)]) {
				[cell setObjectValue:[_delegate browser:self objectValueForItem:item]];
			}
			if ([cell isKindOfClass:[NSBrowserCell class]]) {
				[(NSBrowserCell *)cell setLeaf:[self isLeafItem:item]];
			}
		}
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:willDisplayCell:atRow:column:)]) {
		[_delegate browser:self willDisplayCell:cell atRow:row column:column];
	}
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	NSInteger column = [self columnForTable:tableView];

	if (column < 0) {
		return NO;
	}
	/* **THE CLICK IS RECORDED WHERE IT HAPPENS, NOT WHERE THE ACTION IS SENT.** This is the table's proposal path — the one
	 * a press goes through — so a target that reads `-clickedRow`/`-clickedColumn` sees the row under the pointer even
	 * when the browser has no action at all. `-doClick:` records them again from the SELECTION when it sends, which is
	 * the same pair for a real click and the only answer for a synthetic one. */
	_clickedColumn = column;
	_clickedRow = row;
	/* **A BRANCH MAY BE REFUSED BEFORE THE DELEGATE IS ASKED.** With `-allowsBranchSelection` off, a row whose item has
	 * children is not selectable — the era's rule, and the reason a browser can be a pure navigation surface. Only the
	 * ITEM model knows which rows are branches; a cell-based delegate has no leaf fact here, which is stated in the
	 * header. */
	if (!_allowsBranchSelection && !_inProgrammaticSelection && [self cg_isItemBased]) {
		id item = [self itemAtRow:row inColumn:column];

		if (item != nil && ![self isLeafItem:item]) {
			/* **A BRANCH OPENS WITHOUT BEING SELECTED.** That is the era's rule with this flag off: the click still
			 * builds the column to the right, and what it does NOT do is leave the branch highlighted. The chain is
			 * recorded anyway — `_selectedRows` is what the NEXT column is built from, so refusing the table's
			 * selection while forgetting the row would leave a browser that cannot navigate two levels deep. */
			[_selectedRows replaceObjectAtIndex:(NSUInteger)column
						 withObject:[NSNumber numberWithInteger:row]];
			_selectedColumn = column;
			[self cg_openBranchAtRow:row inColumn:column];
			return NO;
		}
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
		[self doClick:self];
	}
}

- (void)cg_tableDoubleClicked:(id)sender
{
	[self doDoubleClick:sender];
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

/* **A COLUMN'S FRAME IN THE DOCUMENT IS THE SAME RECT THE STRIP AND THE LIST ARE CUT FROM.** Three frames, one sum: the
 * whole column is (x, 0, width, height), the list is the bottom part, and the title strip is the top `-titleHeight`.
 * The document is flipped, so y = 0 IS the top and the strip needs no arithmetic against the height. */
- (NSRect)cg_columnFrameInDocument:(NSInteger)column
{
	return NSMakeRect([self fn_xOriginForColumn:column], 0.0, [self fn_frameWidthForColumn:column],
			  NSHeight([_documentView bounds]));
}

- (NSRect)cg_titleStripFrameInDocument:(NSInteger)column
{
	NSRect columnFrame;

	if (!_titled) {
		return NSZeroRect;
	}
	columnFrame = [self cg_columnFrameInDocument:column];
	if (NSIsEmptyRect(columnFrame)) {
		return NSZeroRect;
	}
	return NSMakeRect(NSMinX(columnFrame), NSMinY(columnFrame), NSWidth(columnFrame), _titleHeight);
}

/* THE SAME RECT AS THE DOCUMENT VIEW DRAWS IT, answered by name because the drawing is that view's and the arithmetic is
 * this one's — one place, so a title cannot be drawn a strip away from the frame the door publishes. */
- (NSRect)cg_titleStripFrameForColumnInDocument:(NSInteger)column
{
	return [self cg_titleStripFrameInDocument:column];
}

/* **AND THE THREE PUBLIC FRAMES CONVERT OUT OF THE DOCUMENT**, because a caller asking where a column is wants the place
 * in the browser it can see — not the place in a document that has been scrolled sideways. The conversion is the scroll
 * view's own, so a scrolled browser answers a NEGATIVE x for a column scrolled off the left, which is the truth. */
- (NSRect)frameOfColumn:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_tables count] || NSIsEmptyRect([_documentView bounds])) {
		return NSZeroRect;
	}
	return [self convertRect:[self cg_columnFrameInDocument:column] fromView:_documentView];
}

- (NSRect)frameOfInsideOfColumn:(NSInteger)column
{
	NSRect frame = [self frameOfColumn:column];
	CGFloat strip = _titled ? _titleHeight : 0.0;

	if (NSIsEmptyRect(frame)) {
		return NSZeroRect;
	}
	if (NSHeight(frame) <= strip) {
		return NSZeroRect;
	}
	/* THE STRIP IS AT THE TOP OF THE BROWSER'S FRAME, which is the frame's LARGER y (the browser is unflipped): so the
	 * list is the same rect with its height reduced, keeping its origin at the bottom. */
	return NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), NSHeight(frame) - strip);
}

- (NSRect)titleFrameOfColumn:(NSInteger)column
{
	NSRect strip;
	NSRect frame;
	CGFloat height;

	if (!_titled || column < 0 || column >= (NSInteger)[_tables count]) {
		return NSZeroRect;
	}
	strip = [self convertRect:[self cg_titleStripFrameInDocument:column] fromView:_documentView];
	frame = [self frameOfColumn:column];
	height = NSHeight(frame);
	if (NSIsEmptyRect(strip) || NSHeight(strip) > height) {
		return NSZeroRect;
	}
	/* IN THE BROWSER'S COORDINATES THE STRIP IS THE TOP OF THE COLUMN, which is the frame's upper edge. */
	return NSMakeRect(NSMinX(frame), NSMaxY(frame) - NSHeight(strip), NSWidth(frame), NSHeight(strip));
}

/* **A ROW'S RECT, WHICH IS THE TABLE'S OWN ROW RECT CONVERTED THROUGH TWO SCROLL VIEWS.** `convertRect:fromView:` walks
 * the whole chain (the table's vertical scroll offset, the document's horizontal one, the flip between them), so this is
 * one call rather than four subtractions that would have to be kept in step with `-tile`. A row scrolled out of its
 * column still answers its place, which is Apple's contract and what a drag's image origin needs. */
- (NSRect)frameOfRow:(NSInteger)row inColumn:(NSInteger)column
{
	NSTableView *table;

	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return NSZeroRect;
	}
	table = [_tables objectAtIndex:(NSUInteger)column];
	if (row < 0 || row >= [table numberOfRows]) {
		return NSZeroRect;
	}
	return [self convertRect:[table rectOfRow:row] fromView:table];
}

/* **THE INVERSE, BY WALKING THE COLUMNS' x BANDS.** The point goes into the document first (one conversion), then the
 * bands are walked exactly the way `-tile` laid them out — same widths, same gap — and the column's own table answers the
 * row. A point in the title strip belongs to a COLUMN and to no row, which is why the two out-parameters are set
 * independently rather than the door refusing the whole answer. */
- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)column forPoint:(NSPoint)point
{
	NSPoint inDocument;
	CGFloat gap = _separatesColumns ? AG_BROWSER_GAP : 0.0;
	CGFloat x = 0.0;
	NSInteger found = -1;
	NSInteger i;

	if (row != NULL) {
		*row = -1;
	}
	if (column != NULL) {
		*column = -1;
	}
	if (_documentView == nil) {
		return NO;
	}
	inDocument = [self convertPoint:point toView:_documentView];
	/* **A POINT OUTSIDE THE DOCUMENT IS OUTSIDE EVERY COLUMN**, which the band walk below cannot answer for itself: the
	 * pool has 256 slots laid out end to end, so without this a point beyond the browser's right edge would land in slot
	 * 3 or 4 — a column that is not on screen and that the caller never asked about. */
	if (inDocument.x < 0.0 || inDocument.x >= NSWidth([_documentView bounds])) {
		return NO;
	}
	for (i = 0; i < (NSInteger)[_tables count]; i++) {
		CGFloat width = [self fn_frameWidthForColumn:i];

		if (inDocument.x >= x && inDocument.x < x + width) {
			found = i;
			break;
		}
		x += width + gap;
	}
	if (found < 0) {
		return NO;
	}
	if (column != NULL) {
		*column = found;
	}
	if (row != NULL) {
		NSRect strip = [self cg_titleStripFrameInDocument:found];
		NSTableView *table = [_tables objectAtIndex:(NSUInteger)found];

		if (!NSIsEmptyRect(strip) && inDocument.y < NSMaxY(strip)) {
			*row = -1;	/* the title strip: a column but no row */
		} else {
			*row = [table rowAtPoint:[self convertPoint:point toView:table]];
		}
	}
	return YES;
}

/* ============================================================================================ *
 * THE TITLE STRIP: WHAT DECIDES IT, WHAT IS DRAWN IN IT, AND HOW WIDE A COLUMN'S CONTENT IS       *
 * ============================================================================================ */

- (BOOL)isTitled
{
	return _titled;
}

/* **TURNING THE STRIP ON OR OFF IS A RELAYOUT**, because it is the list's height that changes: with the strip the column's
 * scroll view starts `-titleHeight` down and is that much shorter, so `-tile` is what makes the flag true of the pixels
 * as well as of the answer. */
- (void)setTitled:(BOOL)flag
{
	BOOL wanted = flag ? YES : NO;

	if (wanted == _titled) {
		return;
	}
	_titled = wanted;
	[self tile];
	[_documentView setNeedsDisplay:YES];
}

/* **THE TITLE'S LOOK, IN THE RECT IT IS GIVEN.** A band in the control's background colour, a one-point rule along the
 * strip's BOTTOM edge (the edge the list is under), and the title itself inset and vertically centred — the era's
 * column header, drawn by the browser rather than by a cell because the strip is the browser's and not a control's.
 *
 * THE RECT'S COORDINATE SPACE IS WHATEVER CONTEXT IS CURRENT, which is the document view's (flipped) when the view draws
 * it and any caller's own when it is called directly; the drawing above is written in the rect's terms and needs no
 * flip of its own. A title nobody set draws the band and the rule and no text, which is what an empty column's header
 * looks like. */
- (void)drawTitleOfColumn:(NSInteger)column inRect:(NSRect)rect
{
	NSString *title;
	NSFont *font;
	CGFloat textHeight;
	NSPoint textOrigin;

	if (NSIsEmptyRect(rect)) {
		return;
	}
	[[NSColor colorWithCalibratedWhite:0.92 alpha:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:rect] fill];
	[[NSColor controlDarkShadowColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), 1.0)] fill];

	title = [self titleOfColumn:column];
	if (title == nil || [title length] == 0) {
		return;
	}
	font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	textHeight = [font ascender] - [font descender];
	textOrigin = NSMakePoint(NSMinX(rect) + 6.0, NSMidY(rect) - textHeight / 2.0);
	[title drawAtPoint:textOrigin withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
									font, NSFontAttributeName,
									[NSColor controlTextColor], NSForegroundColorAttributeName, nil]];
}

/* **THE TWO WIDTH CONVERSIONS ARE ONE NUMBER APART, AND IT IS THE COLUMN'S OWN BAR.** A column's frame width includes the
 * vertical scroller that lives INSIDE it (that is what `-widthOfColumn:` answers and what `-tile` gives the scroll
 * view), so the content width is the frame less the bar when the bar is showing. The overhead is measured from the
 * browser's own first column rather than assumed, because this tier's scroller width is the theme's — and a browser with
 * no columns yet answers the width unchanged, which says "nothing known to subtract" rather than inventing a number. */
- (CGFloat)fn_columnChromeWidth
{
	NSUInteger i;

	for (i = 0; i < [_columnScrollViews count]; i++) {
		NSScrollView *columnScroll = [_columnScrollViews objectAtIndex:i];
		CGFloat overhead = NSWidth([columnScroll frame]) - [columnScroll contentSize].width;

		if (overhead > 0.0) {
			return overhead;
		}
	}
	return 0.0;
}

- (CGFloat)columnContentWidthForColumnWidth:(CGFloat)columnWidth
{
	CGFloat content = columnWidth - [self fn_columnChromeWidth];

	return (content < 0.0) ? 0.0 : content;
}

- (CGFloat)columnWidthForColumnContentWidth:(CGFloat)contentWidth
{
	return contentWidth + [self fn_columnChromeWidth];
}

/* **THE DEFAULT WIDTH IS THE WIDTH NEW COLUMNS GET**, and `-setDefaultColumnWidth:` is the door that changes it WITHOUT
 * touching the columns that exist — the distinction from `-setColumnWidth:`, which re-widths every one of them. */
- (CGFloat)defaultColumnWidth
{
	return _columnWidth;
}

- (void)setDefaultColumnWidth:(CGFloat)width
{
	_columnWidth = width;
}

/* ============================================================================================ *
 * THE CLICK: WHO WAS CLICKED, AND THE TWO ACTIONS                                              *
 * ============================================================================================ */

- (NSInteger)clickedRow
{
	return _clickedRow;
}

- (NSInteger)clickedColumn
{
	return _clickedColumn;
}

/* **THE PAIR, ON THE CONTROL RATHER THAN IN A CELL** — `NSControl`'s own comment says the pair is "the cell's" in this
 * tree, and a browser has no cell, so its `-action` would be NULL and its `-target` nil for ever. A click that recorded
 * where it landed and then sent nothing is worse than no door at all, so the four below are the browser's own. */
- (id)target
{
	return _browserTarget;
}

- (void)setTarget:(id)target
{
	_browserTarget = target;
}

- (SEL)action
{
	return _browserAction;
}

- (void)setAction:(SEL)action
{
	_browserAction = action;
}

/* **A CLICK RECORDS WHERE IT LANDED AND THEN SENDS THE ACTION.** The selection is the click's result, so the row and
 * column are read from it rather than passed in: a caller with a synthetic click selects first and sends this, which is
 * what the table's own selection path does. `sender` is handed on when there is one, because `-sendAction:to:from:`
 * passes it to the target and Apple's own callers pass the control. */
- (void)doClick:(id)sender
{
	if (_selectedColumn >= 0) {
		_clickedColumn = _selectedColumn;
		_clickedRow = [self selectedRowInColumn:_selectedColumn];
	} else {
		_clickedColumn = -1;
		_clickedRow = -1;
	}
	if ([self action] != NULL) {
		[[NSApplication sharedApplication] sendAction:[self action] to:[self target]
							  from:((sender != nil) ? sender : self)];
	}
}

- (void)doDoubleClick:(id)sender
{
	if (_selectedColumn >= 0) {
		_clickedColumn = _selectedColumn;
		_clickedRow = [self selectedRowInColumn:_selectedColumn];
	}
	if (_doubleAction != NULL) {
		[[NSApplication sharedApplication] sendAction:_doubleAction to:[self target]
							  from:((sender != nil) ? sender : self)];
	}
}

/* **UPDATING THE SCROLLER HERE IS RE-TILING**, because the outer bar's presence and range are exactly what `-tile`
 * computes from the column count and the document's width. Apple's door exists because its browser keeps a scroller of
 * its own to poke; this one has the scroll view do that, so the poke is the re-tiling. */
- (void)updateScroller
{
	[self tile];
}

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
	[self cg_saveColumnWidths];
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
			/* **THE COLUMN'S LIST STARTS BELOW THE TITLE STRIP, and the strip is reserved from the same height the column
			 * had before it existed — so a browser that is not titled tiles exactly as it always did, and a titled one gives
			 * up `-titleHeight` at the top rather than growing. A column shorter than the strip keeps no list at all rather
			 * than a negative frame. */
			{
				CGFloat strip = _titled ? _titleHeight : 0.0;
				CGFloat listHeight = available.height - strip;

				if (listHeight < 0.0) {
					listHeight = 0.0;
				}
				[columnScroll setFrame:NSMakeRect(x, strip, frameWidth, listHeight)];
			}
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
	/* **A NEW TITLE IS NEW INK IN THE STRIP.** Nothing else marks the document dirty for it: the title is not a subview
	 * and does not change a frame, so the drawing has to be asked for. */
	[_documentView setNeedsDisplay:YES];
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


/* ============================================================================================ *
 * THE REST OF THE ERA'S SURFACE                                                                *
 * ============================================================================================ */

/* THE COLUMN A ROW LIVES IN, OR NIL. Every one of these answers nil for a column that does not exist rather than
 * raising, because a caller asking about a column it has not loaded is asking a question with an honest answer. */
- (NSTableView *)cg_tableIfAnyForColumn:(NSInteger)column
{
	if (column < 0 || column >= (NSInteger)[_tables count]) {
		return nil;
	}
	return [_tables objectAtIndex:(NSUInteger)column];
}

/* ---- THE RELOAD TRIO ------------------------------------------------------------------------- */

- (void)reloadDataForRowIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column
{
	NSTableView *table = [self cg_tableIfAnyForColumn:column];

	if (table == nil || rowIndexes == nil) {
		return;
	}
	[table reloadDataForRowIndexes:rowIndexes
		       columnIndexes:[NSIndexSet indexSetWithIndex:0]];
	/* THE RELOADED ROWS KEEP THE COUNT, so the column's height and the document's width do not change; a re-tile would
	 * be work for nothing, and the table has already marked what changed. */
}

- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)indexSet inColumn:(NSInteger)column
{
	NSTableView *table = [self cg_tableIfAnyForColumn:column];

	if (table == nil || indexSet == nil) {
		return;
	}
	[table noteHeightOfRowsWithIndexesChanged:indexSet];
	[self tile];
}

/* **ASKING THE DELEGATE WHETHER EACH VISIBLE COLUMN STILL HOLDS.** Apple's door is a validity pass after something
 * outside the browser changed: the delegate answers `-browser:isColumnValid:` and a column that says NO is reloaded. The
 * range is the visible one, which is the only range a person can see. */
- (void)validateVisibleColumns
{
	NSInteger first = [self firstVisibleColumn];
	NSInteger last = [self lastVisibleColumn];
	NSInteger column;

	for (column = first; column <= last; column++) {
		if (column < 0 || column >= (NSInteger)[_tables count]) {
			continue;
		}
		if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:isColumnValid:)]) {
			if (![_delegate browser:self isColumnValid:column]) {
				[self reloadColumn:column];
			}
		}
	}
}

/* ---- THE DISPLAY AND COLUMN DOORS ------------------------------------------------------------ */

- (BOOL)isLoaded
{
	return _loadedZero;
}

/* **THE LAST COLUMN THE BROWSER MAY GROW TO.** Unset means "wherever the selection chain ends"; `-setLastColumn:` states a
 * boundary and truncates anything past it, which is how a caller allows `-addColumn` exactly as far as it wants. */
- (NSInteger)lastColumn
{
	NSInteger i;

	if (_lastColumn >= 0) {
		return _lastColumn;
	}
	for (i = (NSInteger)[_tables count] - 1; i >= 0; i--) {
		if ([[_columnCounts objectAtIndex:(NSUInteger)i] integerValue] > 0) {
			return i;
		}
	}
	return 0;
}

- (void)setLastColumn:(NSInteger)column
{
	if (column < 0) {
		column = 0;
	}
	_lastColumn = column;
	[self truncateColumnsAfter:column];
	[self tile];
}

/* **ONE MORE COLUMN, LOADED FROM WHATEVER THE LAST ONE HAS SELECTED.** With nothing selected there is nothing to add;
 * with a selection, the new column is the selected item's children and the selection moves into it, which is what a
 * person means by "go one deeper" without navigating. */
/* **OPENING A BRANCH WITHOUT SELECTING IT** — the branch-selection path above. The next column's rows are the item's
 * children, asked directly rather than through `-rowsForColumn:`, because that door reads the very chain this call is
 * establishing. */
- (void)cg_openBranchAtRow:(NSInteger)row inColumn:(NSInteger)column
{
	id item = [self itemAtRow:row inColumn:column];
	NSInteger rows;

	if (item == nil || _delegate == nil) {
		return;
	}
	rows = [_delegate browser:self numberOfChildrenOfItem:item];
	[self truncateColumnsAfter:column];
	if (rows > 0) {
		[self ensureColumn:column + 1 rows:rows];
		if (column + 1 < (NSInteger)[_columnCounts count]) {
			[_columnCounts replaceObjectAtIndex:(NSUInteger)(column + 1)
						 withObject:[NSNumber numberWithInteger:rows]];
			[[_tables objectAtIndex:(NSUInteger)(column + 1)] reloadData];
		}
	}
	[self tile];
	[self scrollColumnToVisible:column + 1];
}

- (void)addColumn
{
	NSInteger next = [self lastColumn] + 1;
	NSInteger rows;

	if (_selectedColumn < 0 || next >= AG_BROWSER_COLUMN_POOL) {
		return;
	}
	rows = [self rowsForColumn:next];
	[self ensureColumn:next rows:rows];
	if (next < (NSInteger)[_columnCounts count]) {
		[_columnCounts replaceObjectAtIndex:(NSUInteger)next withObject:[NSNumber numberWithInteger:rows]];
		[[_tables objectAtIndex:(NSUInteger)next] reloadData];
	}
	_lastColumn = next;
	[self tile];
	[self scrollColumnToVisible:next];
}

- (void)displayColumn:(NSInteger)column
{
	[self scrollColumnToVisible:column];
}

- (void)displayAllColumns
{
	[self scrollColumnToVisible:[self lastColumn]];
}

/* ---- THE SCROLL FAMILY ----------------------------------------------------------------------- */

- (void)scrollColumnsLeftBy:(NSInteger)shiftAmount
{
	[self scrollColumnToVisible:[self firstVisibleColumn] - shiftAmount];
}

- (void)scrollColumnsRightBy:(NSInteger)shiftAmount
{
	[self scrollColumnToVisible:[self firstVisibleColumn] + shiftAmount];
}

/* **THE OUTER SCROLLER'S OWN ACTION, WHICH IS A FRACTION OF THE HORIZONTAL TRAVEL.** A scroller's value is where its knob
 * sits in [0, 1]; multiplying that by the document's scrollable width is the one place the two agree, and it is the same
 * arithmetic the scroll view's own action performs. */
- (void)scrollViaScroller:(NSScroller *)sender
{
	NSClipView *clip;
	CGFloat travel;
	CGFloat x;

	if (sender == nil || _scrollView == nil) {
		return;
	}
	clip = [_scrollView contentView];
	travel = NSWidth([_documentView bounds]) - NSWidth([clip bounds]);
	if (travel <= 0.0) {
		return;
	}
	x = (CGFloat)[sender floatValue] * travel;
	[clip scrollToPoint:NSMakePoint(x, 0.0)];
	[_scrollView reflectScrolledClipView:clip];
}

- (void)scrollRowToVisible:(NSInteger)row inColumn:(NSInteger)column
{
	NSTableView *table = [self cg_tableIfAnyForColumn:column];

	if (table == nil || row < 0) {
		return;
	}
	[table scrollRowToVisible:row];
}

/* AND THE OUTER BAR'S AUTOHIDE, which is the scroll view's own policy. */
- (BOOL)autohidesScroller
{
	return [_scrollView autohidesScrollers];
}

- (void)setAutohidesScroller:(BOOL)flag
{
	[_scrollView setAutohidesScrollers:flag];
	[self tile];
}

/* ---- THE CELL READS -------------------------------------------------------------------------- */

- (NSCell *)selectedCellInColumn:(NSInteger)column
{
	NSInteger row = [self selectedRowInColumn:column];

	return (row >= 0) ? [self loadedCellAtRow:row column:column] : nil;
}

/* **THE CELL THE COLUMN WOULD DRAW, MADE THE SAME WAY A DRAW MAKES IT** — the table's own `-preparedCellAtColumn:row:`,
 * so the answer includes the item value and the delegate's styling rather than only what the data source returned. */
- (NSCell *)loadedCellAtRow:(NSInteger)row column:(NSInteger)column
{
	NSTableView *table = [self cg_tableIfAnyForColumn:column];

	if (table == nil || row < 0 || row >= [table numberOfRows]) {
		return nil;
	}
	return [table preparedCellAtColumn:0 row:row];
}

/* ---- THE BEHAVIOUR FLAGS, EACH READ WHERE THE BROWSER DECIDES -------------------------------- */

- (BOOL)allowsBranchSelection
{
	return _allowsBranchSelection;
}

/* READ IN `-tableView:shouldSelectRow:`: a branch row is refused when the flag is off and the delegate is item-based
 * (the cell contract has no leaf/branch fact to consult, which is stated there). */
- (void)setAllowsBranchSelection:(BOOL)flag
{
	_allowsBranchSelection = flag ? YES : NO;
}

/* READ BY EVERY COLUMN'S TABLE: this is the browser's flag, and the type-select itself is the table's. */
- (BOOL)allowsTypeSelect
{
	return _allowsTypeSelect;
}

- (void)setAllowsTypeSelect:(BOOL)flag
{
	NSUInteger i;

	_allowsTypeSelect = flag ? YES : NO;
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setAllowsTypeSelect:_allowsTypeSelect];
	}
}

/* **THE COLUMNS ARE A POOL AND ARE REUSED BY CONSTRUCTION**, so the answer is always YES and the setter refuses: a
 * caller cannot ask this browser for columns that are not reused. */
- (BOOL)reusesColumns
{
	return YES;
}

- (void)setReusesColumns:(BOOL)flag
{
	(void)flag;
	fn_refuse_workspace("NSBrowser -setReusesColumns:",
			    "columns that are not reused - this browser's columns are a fixed 256-slot pool, "
			    "reused by construction");
}

- (BOOL)prefersAllColumnUserResizing
{
	return _prefersAllColumnUserResizing;
}

- (void)setPrefersAllColumnUserResizing:(BOOL)flag
{
	_prefersAllColumnUserResizing = flag ? YES : NO;
}

/* ---- THE COLUMN-WIDTH AUTOSAVE, IN THE TABLE'S OWN STORE -------------------------------------- */

- (NSString *)columnsAutosaveName
{
	return _columnsAutosaveName;
}

/* **SETTING A NAME RESTORES WHAT WAS SAVED** — the same order the table uses for its own columns, and the same store
 * (`NSUserDefaults`), under a key of this class's own so a browser and a table never read each other's array. */
- (void)setColumnsAutosaveName:(NSString *)name
{
	NSString *copy = [name copy];

	[_columnsAutosaveName release];
	_columnsAutosaveName = copy;
	if (_columnsAutosaveName == nil || [_columnsAutosaveName length] == 0) {
		return;
	}
	{
		NSString *key = [NSString stringWithFormat:@"NSBrowser Columns %@", _columnsAutosaveName];
		NSArray *widths = [[NSUserDefaults standardUserDefaults] objectForKey:key];
		NSUInteger i;

		for (i = 0; i < [widths count] && i < [_columnWidths count]; i++) {
			[_columnWidths replaceObjectAtIndex:i
						 withObject:[NSNumber numberWithDouble:
								[[widths objectAtIndex:i] doubleValue]]];
		}
	}
	[self tile];
}

- (void)removeSavedColumnsWithAutosaveName:(NSString *)name
{
	if (name == nil) {
		return;
	}
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:
		[NSString stringWithFormat:@"NSBrowser Columns %@", name]];
}

- (void)cg_saveColumnWidths
{
	NSMutableArray *widths;
	NSUInteger i;

	if (_columnsAutosaveName == nil || [_columnsAutosaveName length] == 0) {
		return;
	}
	widths = [NSMutableArray array];
	for (i = 0; i < [_columnWidths count]; i++) {
		[widths addObject:[_columnWidths objectAtIndex:i]];
	}
	[[NSUserDefaults standardUserDefaults] setObject:widths
						  forKey:[NSString stringWithFormat:@"NSBrowser Columns %@",
							       _columnsAutosaveName]];
}

/* ---- THE ACTION AND THE EDIT ------------------------------------------------------------------ */

/* **THE ACTION SEND, WHICH IS WHAT `-doClick:` DOES ONCE IT HAS RECORDED THE CLICK.** A caller with a synthetic click
 * (a keyboard shortcut, a menu row) asks for the same thing without inventing a location. */
- (void)sendAction
{
	if (_browserAction != NULL) {
		[[NSApplication sharedApplication] sendAction:_browserAction to:_browserTarget from:self];
	}
}

/* **BEGINNING AN EDIT AT AN ITEM'S PATH.** The path is selected first — every column down to the item loads, exactly as a
 * click loads them — and then the last column's table starts the field editor over that row, which is the browser's only
 * editable surface: the cells are the table's. */
- (void)editItemAtIndexPath:(NSIndexPath *)indexPath withEvent:(NSEvent *)event select:(BOOL)select
{
	NSTableView *table;
	NSInteger column;
	NSInteger row;

	if (indexPath == nil || [indexPath length] == 0) {
		return;
	}
	[self setSelectionIndexPath:indexPath];
	column = (NSInteger)[indexPath length] - 1;
	row = (NSInteger)[indexPath indexAtPosition:[indexPath length] - 1];
	table = [self cg_tableIfAnyForColumn:column];
	if (table == nil || row < 0 || row >= [table numberOfRows]) {
		return;
	}
	[table editColumn:0 row:row withEvent:event select:select];
}

/* ---- THE DRAG SOURCE -------------------------------------------------------------------------- */

/* **WHETHER A DRAG MAY START, ASKED OF THE DELEGATE FIRST AND THE COLUMN'S TABLE SECOND.** The delegate's answer is
 * Apple's own door; with none, the table decides (its data source must be able to write the rows), which is the same rule
 * the table applies to its own rows. */
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes inColumn:(NSInteger)column withEvent:(NSEvent *)event
{
	NSTableView *table = [self cg_tableIfAnyForColumn:column];
	NSPoint point = NSZeroPoint;

	if (table == nil || rowIndexes == nil || [rowIndexes count] == 0) {
		return NO;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(browser:canDragRowsWithIndexes:inColumn:withEvent:)]) {
		return [_delegate browser:self canDragRowsWithIndexes:rowIndexes inColumn:column withEvent:event];
	}
	if (event != nil) {
		point = [table convertPoint:[event locationInWindow] fromView:nil];
	}
	return [table canDragRowsWithIndexes:rowIndexes atPoint:point];
}

/* **THE IMAGE THE DRAG CARRIES, DRAWN FROM THE ROWS THEMSELVES.** Each row's cell is asked for its string, the block is
 * measured with the browser's font, and the image is that block with every row's text on its own line — a picture of what
 * is being dragged rather than a generic icon. The offset is where the pointer was inside the block, which is what makes
 * the image appear to be picked up where it was grabbed rather than at its corner. */
- (NSImage *)draggingImageForRowsWithIndexes:(NSIndexSet *)rowIndexes
				    inColumn:(NSInteger)column
				   withEvent:(NSEvent *)event
				      offset:(NSPointPointer)dragImageOffset
{
	NSTableView *table = [self cg_tableIfAnyForColumn:column];
	NSMutableArray *lines = [NSMutableArray array];
	NSFont *font;
	NSSize size;
	NSImage *image;
	NSUInteger index;
	CGFloat lineHeight;

	if (table == nil || rowIndexes == nil || [rowIndexes count] == 0) {
		return nil;
	}
	font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	lineHeight = [font ascender] - [font descender] + 2.0;
	for (index = [rowIndexes firstIndex]; index != NSNotFound; index = [rowIndexes indexGreaterThanIndex:index]) {
		NSCell *cell = [self loadedCellAtRow:(NSInteger)index column:column];
		NSString *text = [cell stringValue];

		[lines addObject:(text != nil) ? text : @""];
	}
	size = NSMakeSize(1.0, lineHeight * (CGFloat)[lines count]);
	for (index = 0; index < [lines count]; index++) {
		NSSize lineSize = [[lines objectAtIndex:index] sizeWithAttributes:
			[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];

		if (lineSize.width + 6.0 > size.width) {
			size.width = lineSize.width + 6.0;
		}
	}
	image = [[[NSImage alloc] initWithSize:size] autorelease];
	[image lockFocus];
	[[NSColor colorWithCalibratedWhite:0.95 alpha:0.9] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, size.width, size.height)] fill];
	for (index = 0; index < [lines count]; index++) {
		CGFloat y = size.height - lineHeight * (CGFloat)(index + 1);

		[[lines objectAtIndex:index] drawAtPoint:NSMakePoint(3.0, y + 1.0) withAttributes:
			[NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
				[NSColor controlTextColor], NSForegroundColorAttributeName, nil]];
	}
	[image unlockFocus];
	if (dragImageOffset != NULL) {
		*dragImageOffset = NSMakePoint(3.0, size.height - lineHeight + 1.0);
	}
	return image;
}

/* **THE MASK IS STORED AND HANDED TO EVERY COLUMN'S TABLE**, because each column IS the drag's source: a drag starts in a
 * table, and the table asks this question of itself. */
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask forLocal:(BOOL)isLocal
{
	NSUInteger i;

	if (isLocal) {
		_localDragMask = mask;
	} else {
		_nonLocalDragMask = mask;
	}
	for (i = 0; i < [_tables count]; i++) {
		[[_tables objectAtIndex:i] setDraggingSourceOperationMask:mask forLocal:isLocal];
	}
}

/* ---- AND THE FOUR THAT REFUSE ------------------------------------------------------------------ */

- (Class)matrixClass
{
	fn_refuse_workspace("NSBrowser -matrixClass",
			    "a matrix - this browser's columns are NSTableViews in per-column scroll views");
	return Nil;
}

- (void)setMatrixClass:(Class)matrixClass
{
	(void)matrixClass;
	fn_refuse_workspace("NSBrowser -setMatrixClass:",
			    "a matrix - this browser's columns are NSTableViews in per-column scroll views");
}

- (id)matrixInColumn:(NSInteger)column
{
	(void)column;
	fn_refuse_workspace("NSBrowser -matrixInColumn:",
			    "a matrix - this browser's columns are NSTableViews; ask -cg_tableForColumn: for the view");
	return nil;
}

- (NSInteger)columnOfMatrix:(id)matrix
{
	(void)matrix;
	fn_refuse_workspace("NSBrowser -columnOfMatrix:",
			    "a matrix - this browser's columns are NSTableViews; ask -columnForTable: is private, "
			    "and -cg_tableForColumn: is the seam");
	return -1;
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
