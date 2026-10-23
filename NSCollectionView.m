/*
 * NSCollectionView.m — the grid, the item pool, the selection, and the two halves of a drag.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE GRID IS ONE ARITHMETIC AND EVERYTHING ELSE ASKS IT.** `-frameForItemAtIndex:` is the only place a cell's
 * rectangle is computed from the item size and the column count; the layout paints the item views there, the hit test
 * asks which frame contains a point, and the drag image takes the union of the frames it is given. A second copy of
 * the arithmetic would be a tile that is drawn in one place and clicked in another.
 *
 * **THE ITEMS ARE CONTROLLERS THE VIEW OWNS, AND THE POOL IS WHAT REBUILDS REUSE.** `_items` is parallel to the
 * content and holds NSNull for an index whose controller has not been made; `_recycled` holds the controllers whose
 * tiles left the tree on the last rebuild. A content or geometry change moves the live items to the pool and takes
 * them back out in order, so the common case — the same grid with one more object — reuses every controller it had.
 *
 * **AND THE DRAG IS BOTH DIRECTIONS, EACH WITH ITS DELEGATE DOORS.** The source starts in `-mouseDragged:` and goes
 * through `canDrag`, `writeItems`, the image door and `-dragImage:...`; the destination answers the four NSView drag
 * doors by asking `validateDrop`/`acceptDrop` with a proposed index computed from the pointer. A collection view with
 * no delegate is a view that neither starts nor accepts a drag, which is what Apple's optional doors mean.
 */
#import <AppKit/NSCollectionView.h>
#import <AppKit/NSCollectionViewItem.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSString.h>

#include <math.h>	/* floor, ceil, MIN/MAX via NSGeometry's macros */

/* THE PRIVATE CONFORMANCE AND THE PRIVATE DOORS. `NSDraggingSource` is a real protocol in this tree, and the source's
 * one required method is what `-dragImage:...` will ask; the class does not publish the conformance because Apple does
 * not — the same arrangement `NSDrawer` uses for its cell delegate. */
@interface NSCollectionView () <NSDraggingSource>
- (NSSize)cg_itemSize;
- (NSUInteger)cg_columnCount;
- (NSUInteger)cg_displayedCount;
- (NSCollectionViewItem *)cg_itemAtIndex:(NSUInteger)index create:(BOOL)create;
- (void)cg_rebuildItems;
- (void)cg_pruneSelection;
- (void)cg_applySelectionToItems;
- (NSInteger)cg_itemIndexAtPoint:(NSPoint)point;
- (NSDragOperation)cg_updateDrop:(id <NSDraggingInfo>)info;
@end

@implementation NSCollectionView

/* ============================================================================================
 * INITIALISE, AND THE DEFAULTS APPLE STATES RATHER THAN LEAVES TO ZEROING.
 * ============================================================================================ */
- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_content = [[NSArray alloc] init];
		_items = [[NSMutableArray alloc] init];
		_recycled = [[NSMutableArray alloc] init];
		_selectionIndexes = [[NSMutableIndexSet alloc] init];
		_selectable = YES;
		/* **`-allowsMultipleSelection` DEFAULTS TO YES, WHICH IS APPLE'S OWN DEFAULT** (the 10.6 header says so in
		 * the setter's comment). The masks are Apple's too: every operation for a local destination, none for a
		 * foreign one. */
		_allowsMultipleSelection = YES;
		_localDragMask = NSDragOperationEvery;
		_nonLocalDragMask = NSDragOperationNone;
		_anchorIndex = NSNotFound;
		_dropIndex = -1;
		_dropOperation = NSCollectionViewDropBefore;
	}
	return self;
}

- (void)dealloc
{
	[_content release];
	[_items release];
	[_recycled release];
	[_itemPrototype release];
	[_selectionIndexes release];
	[_backgroundColors release];
	[_draggedIndexes release];
	[super dealloc];
}

/* **THE VIEW IS FLIPPED, LIKE A TABLE, SO ROW 0 IS AT THE TOP AND A FRAME'S Y GROWS DOWNWARD.** The choice is stated
 * once here because every frame, every hit test and every drag image reads it. */
- (BOOL)isFlipped
{
	return YES;
}

/* ============================================================================================
 * THE CONTENT, THE FACTORY AND THE POOL.
 * ============================================================================================ */

- (void)setContent:(NSArray *)content
{
	NSArray *copy = [[NSArray alloc] initWithArray:(content != nil ? content : [NSArray array])];

	[_content release];
	_content = copy;
	[self cg_rebuildItems];
	[self cg_pruneSelection];
	[self setNeedsDisplay:YES];
}

- (NSArray *)content
{
	return _content;
}

- (void)setItemPrototype:(NSCollectionViewItem *)prototype
{
	if (prototype == _itemPrototype) {
		return;
	}
	[prototype retain];
	[_itemPrototype release];
	_itemPrototype = prototype;
	[self cg_rebuildItems];
}

- (NSCollectionViewItem *)itemPrototype
{
	return _itemPrototype;
}

/* **THE DEFAULT FACTORY IS "COPY THE PROTOTYPE", AND THE COPY IS +1 BECAUSE APPLE SAYS SO** ("the returned object
 * should not be autoreleased"). The view stores it in `_items` — which retains — and balances the +1, so the copy's
 * ownership is this class's between those two lines and nobody else's. A subclass that wants a different factory
 * overrides this door and keeps the same ownership contract. */
- (NSCollectionViewItem *)newItemForRepresentedObject:(id)object
{
	NSCollectionViewItem *item;

	if (_itemPrototype == nil) {
		return nil;
	}
	item = [_itemPrototype copy];
	[item setRepresentedObject:object];
	return item;
}

/* **AN ITEM IS MADE ON DEMAND AND REMEMBERED.** The slot array is parallel to the content and starts as NSNull; a
 * request either finds the controller, takes one from the pool, or asks the factory. A recycled controller keeps its
 * class and view and gets the new represented object — the pool's whole point — and work a custom factory does BEYOND
 * setting the object happens only for a fresh one, which is the difference the header names. */
- (NSCollectionViewItem *)cg_itemAtIndex:(NSUInteger)index create:(BOOL)create
{
	id slot;

	if (index >= [_content count]) {
		return nil;
	}
	if (index >= [_items count]) {
		return nil;
	}
	slot = [_items objectAtIndex:index];
	if (slot != [NSNull null]) {
		return (NSCollectionViewItem *)slot;
	}
	if (!create) {
		return nil;
	}
	{
		NSCollectionViewItem *item = nil;

		if ([_recycled count] > 0) {
			item = [[_recycled lastObject] retain];
			[_recycled removeLastObject];
			[item setRepresentedObject:[_content objectAtIndex:index]];
		} else {
			item = [self newItemForRepresentedObject:[_content objectAtIndex:index]];
		}
		if (item == nil) {
			return nil;
		}
		[_items replaceObjectAtIndex:index withObject:item];
		[item setCollectionView:self];
		[item release];		/* the array is the owner now; the answer is borrowed */
		return [_items objectAtIndex:index];
	}
}

- (NSCollectionViewItem *)itemAtIndex:(NSUInteger)index
{
	return [self cg_itemAtIndex:index create:YES];
}

/* ============================================================================================
 * THE GRID'S ARITHMETIC.
 * ============================================================================================ */
/* **THE CELL IS THE PROTOTYPE VIEW'S SIZE, CLAMPED.** The prototype is the only object that can say how big a tile is
 * naturally, so its view's frame is the base; a positive minimum raises it and a positive maximum lowers it. A prototype
 * with no view, or one whose frame is empty, leaves a zero-sized cell and therefore no tiles — which is honest: a
 * collection view with no idea how big its items are cannot lay them out. */
- (NSSize)cg_itemSize
{
	NSSize natural = NSZeroSize;
	NSView *prototypeView = [_itemPrototype cg_viewIfLoaded];

	if (prototypeView != nil) {
		natural = [prototypeView frame].size;
	}
	if (_minItemSize.width > 0.0 && natural.width < _minItemSize.width) {
		natural.width = _minItemSize.width;
	}
	if (_minItemSize.height > 0.0 && natural.height < _minItemSize.height) {
		natural.height = _minItemSize.height;
	}
	if (_maxItemSize.width > 0.0 && natural.width > _maxItemSize.width) {
		natural.width = _maxItemSize.width;
	}
	if (_maxItemSize.height > 0.0 && natural.height > _maxItemSize.height) {
		natural.height = _maxItemSize.height;
	}
	return natural;
}

/* **COLUMNS COME FROM THE WIDTH, AND THERE IS ALWAYS AT LEAST ONE** — a collection view narrower than one tile still
 * shows a column rather than nothing. `-maxNumberOfColumns` caps it when non-zero. */
- (NSUInteger)cg_columnCount
{
	NSSize size = [self cg_itemSize];
	NSUInteger columns;

	if (size.width <= 0.0) {
		return 0;
	}
	columns = (NSUInteger)floor(NSWidth([self bounds]) / size.width);
	if (columns < 1) {
		columns = 1;
	}
	if (_maxColumns > 0 && columns > _maxColumns) {
		columns = _maxColumns;
	}
	return columns;
}

/* **THE DISPLAY CAP IS ROWS TIMES COLUMNS, AND IT LIMITS TILES, NOT ITEMS.** An item past the cap is still answerable
 * by `-itemAtIndex:`; it simply has no view. */
- (NSUInteger)cg_displayedCount
{
	NSUInteger columns = [self cg_columnCount];
	NSUInteger count = [_content count];

	if (columns == 0) {
		return 0;
	}
	if (_maxRows > 0) {
		NSUInteger cap = _maxRows * columns;

		if (count > cap) {
			count = cap;
		}
	}
	return count;
}

- (NSRect)frameForItemAtIndex:(NSUInteger)index
{
	NSUInteger columns = [self cg_columnCount];
	NSSize size = [self cg_itemSize];
	NSUInteger column;
	NSUInteger row;

	if (index >= [_content count] || columns == 0 || size.width <= 0.0 || size.height <= 0.0) {
		return NSZeroRect;
	}
	column = index % columns;
	row = index / columns;
	return NSMakeRect((CGFloat)column * size.width, (CGFloat)row * size.height, size.width, size.height);
}

/* ============================================================================================
 * THE REBUILD: TILES OUT, POOL IN, TILES BACK.
 * ============================================================================================ */
/* **A REBUILD IS NOT A RELOAD.** The controllers already made are moved to the pool with their views taken out of the
 * tree; the slots become NSNull again; and the displayed indexes are filled from the pool first. The item objects
 * therefore survive a content change, which is Apple's recycling in the small and enough for a view with no scroll
 * source. The guard stops a rebuild caused by `-setFrameSize:` from re-entering itself while it is laying a tile out. */
- (void)cg_rebuildItems
{
	NSUInteger i;
	NSUInteger newCount = [_content count];
	NSUInteger oldCount = [_items count];
	NSUInteger displayed;

	if (_rebuilding) {
		return;
	}
	_rebuilding = YES;
	/* **THE SLOTS ARE KEPT BY INDEX, AND ONLY THE TAIL LEAVES.** Growing the content appends empty slots; shrinking
	 * it pools the controllers whose indexes no longer exist — which is the recycling, done where the change is rather
	 * than by emptying the grid and filling it again. That is why the same index answers the same controller after a
	 * content change, which is what a caller holding an item expects. */
	if (newCount < oldCount) {
		for (i = newCount; i < oldCount; i++) {
			id slot = [_items objectAtIndex:i];

			if (slot != [NSNull null]) {
				NSView *view = [(NSCollectionViewItem *)slot cg_viewIfLoaded];

				[view removeFromSuperview];
				[(NSCollectionViewItem *)slot setSelected:NO];
				[_recycled addObject:slot];
			}
		}
		while ([_items count] > newCount) {
			[_items removeLastObject];
		}
	} else {
		for (i = oldCount; i < newCount; i++) {
			[_items addObject:[NSNull null]];
		}
	}
	/* EACH TILE LEAVES THE TREE AND THE DISPLAYED ONES COME BACK, because a geometry change moves every frame and a
	 * content change may have added or removed tiles. The controllers are NOT pooled here — only the ones whose indexes
	 * ceased to exist were. */
	for (i = 0; i < [_items count]; i++) {
		id slot = [_items objectAtIndex:i];

		if (slot != [NSNull null]) {
			[[(NSCollectionViewItem *)slot cg_viewIfLoaded] removeFromSuperview];
			[(NSCollectionViewItem *)slot setSelected:NO];
		}
	}
	displayed = [self cg_displayedCount];
	for (i = 0; i < displayed; i++) {
		NSCollectionViewItem *item = [self cg_itemAtIndex:i create:YES];
		NSView *view;

		if (item == nil) {
			continue;
		}
		view = [item cg_viewIfLoaded];
		if (view == nil) {
			continue;
		}
		[view setFrame:[self frameForItemAtIndex:i]];
		[self addSubview:view];
		[item setSelected:[_selectionIndexes containsIndex:i]];
	}
	_rebuilding = NO;
}

/* **A FRAME CHANGE IS A LAYOUT CHANGE, AND THE ITEMS ARE RELAID OUT RATHER THAN STRETCHED.** The cell size is fixed,
 * so a wider view has more columns and the tiles move; the comparison against the old size keeps a pure move from
 * rebuilding for nothing. */
- (void)setFrameSize:(NSSize)newSize
{
	NSSize old = [self frame].size;

	[super setFrameSize:newSize];
	if (old.width != newSize.width || old.height != newSize.height) {
		[self cg_rebuildItems];
		[self setNeedsDisplay:YES];
	}
}

- (void)setFrame:(NSRect)frameRect
{
	NSSize old = [self frame].size;

	[super setFrame:frameRect];
	if (old.width != frameRect.size.width || old.height != frameRect.size.height) {
		[self cg_rebuildItems];
		[self setNeedsDisplay:YES];
	}
}

/* ---- THE ITEM SIZE AND THE TWO CAPS ---------------------------------------------------------------- */

- (void)setMinItemSize:(NSSize)size
{
	_minItemSize = size;
	[self cg_rebuildItems];
}

- (NSSize)minItemSize
{
	return _minItemSize;
}

- (void)setMaxItemSize:(NSSize)size
{
	_maxItemSize = size;
	[self cg_rebuildItems];
}

- (NSSize)maxItemSize
{
	return _maxItemSize;
}

- (void)setMaxNumberOfRows:(NSUInteger)number
{
	_maxRows = number;
	[self cg_rebuildItems];
	[self cg_pruneSelection];
}

- (NSUInteger)maxNumberOfRows
{
	return _maxRows;
}

- (void)setMaxNumberOfColumns:(NSUInteger)number
{
	_maxColumns = number;
	[self cg_rebuildItems];
}

- (NSUInteger)maxNumberOfColumns
{
	return _maxColumns;
}

/* ============================================================================================
 * THE SELECTION.
 * ============================================================================================ */
- (void)setSelectionIndexes:(NSIndexSet *)indexes
{
	NSMutableIndexSet *snapshot = [[NSMutableIndexSet alloc] initWithIndexSet:indexes];

	[_selectionIndexes release];
	_selectionIndexes = snapshot;
	[self cg_pruneSelection];
	[self cg_applySelectionToItems];
	[self setNeedsDisplay:YES];
}

- (NSIndexSet *)selectionIndexes
{
	/* AN IMMUTABLE SNAPSHOT, because `NSIndexSet -copy` in this Foundation answers `[self retain]` even for a mutable
	 * set — handing out the internal mutable set would let a caller change the selection behind the view's back. */
	return [[[NSIndexSet alloc] initWithIndexSet:_selectionIndexes] autorelease];
}

- (void)setSelectable:(BOOL)flag
{
	_selectable = flag ? YES : NO;
	if (!_selectable) {
		[self setSelectionIndexes:nil];
	}
}

- (BOOL)isSelectable
{
	return _selectable;
}

- (void)setAllowsMultipleSelection:(BOOL)flag
{
	_allowsMultipleSelection = flag ? YES : NO;
	if (!_allowsMultipleSelection && [_selectionIndexes count] > 1) {
		NSUInteger first = [_selectionIndexes firstIndex];

		[self setSelectionIndexes:[NSIndexSet indexSetWithIndex:first]];
	}
}

- (BOOL)allowsMultipleSelection
{
	return _allowsMultipleSelection;
}

/* **THE PRUNE IS THE ONE PLACE THE SET MEETS THE CONTENT AND THE MULTIPLE-SELECTION RULE.** Indexes past the end go
 * (a shrunken content has no such items); more than one index collapses to the first when the flag is off. Both are
 * done on a fresh set so the loops cannot read what they are writing. */
- (void)cg_pruneSelection
{
	NSMutableIndexSet *pruned = [[NSMutableIndexSet alloc] init];
	NSUInteger index = [_selectionIndexes firstIndex];
	NSUInteger count = [_content count];

	while (index != NSNotFound) {
		if (index < count) {
			[pruned addIndex:index];
		}
		index = [_selectionIndexes indexGreaterThanIndex:index];
	}
	if (!_allowsMultipleSelection && [pruned count] > 1) {
		NSUInteger first = [pruned firstIndex];

		[pruned removeAllIndexes];
		[pruned addIndex:first];
	}
	[_selectionIndexes release];
	_selectionIndexes = pruned;
}

- (void)cg_applySelectionToItems
{
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		id slot = [_items objectAtIndex:i];

		if (slot != [NSNull null]) {
			[(NSCollectionViewItem *)slot setSelected:[_selectionIndexes containsIndex:i]];
		}
	}
}

/* ============================================================================================
 * THE POINTER: SELECTION, THE FIRST RESPONDER, AND THE HIT TEST.
 * ============================================================================================ */
- (BOOL)acceptsFirstResponder
{
	return _selectable;
}

- (BOOL)becomeFirstResponder
{
	return YES;
}

- (BOOL)isFirstResponder
{
	return [[self window] firstResponder] == self;
}

- (NSInteger)cg_itemIndexAtPoint:(NSPoint)point
{
	NSUInteger displayed = [self cg_displayedCount];
	NSUInteger i;

	for (i = 0; i < displayed; i++) {
		if (NSPointInRect(point, [self frameForItemAtIndex:i])) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

/* **A CLICK IS A SELECTION, WITH THE THREE MODIFIER MEANINGS A GRID SHARES WITH A TABLE.** Command toggles one index
 * (when multiple selection is allowed), Shift extends from the last plain click, and a plain click replaces. A click on
 * empty space clears unless a modifier is down, which is the table's own rule. The click also makes this view the first
 * responder — the door `-isFirstResponder` reports — because a tile's focused highlight is worth having. */
- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger index = [self cg_itemIndexAtPoint:point];
	NSUInteger modifiers = [event modifierFlags];

	if ([self window] != nil) {
		[[self window] makeFirstResponder:self];
	}
	if (!_selectable) {
		return;
	}
	if (index == NSNotFound) {
		if ((modifiers & (NSCommandKeyMask | NSShiftKeyMask)) == 0) {
			[self setSelectionIndexes:nil];
			_anchorIndex = NSNotFound;
		}
		return;
	}
	if ((modifiers & NSCommandKeyMask) != 0) {
		if (_allowsMultipleSelection) {
			NSMutableIndexSet *next = [[NSMutableIndexSet alloc] initWithIndexSet:_selectionIndexes];

			if ([next containsIndex:(NSUInteger)index]) {
				[next removeIndex:(NSUInteger)index];
			} else {
				[next addIndex:(NSUInteger)index];
			}
			[self setSelectionIndexes:next];
			[next release];
		} else {
			[self setSelectionIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index]];
		}
		_anchorIndex = index;
		return;
	}
	if ((modifiers & NSShiftKeyMask) != 0 && _anchorIndex != NSNotFound) {
		NSUInteger low = (NSUInteger)MIN(_anchorIndex, index);
		NSUInteger high = (NSUInteger)MAX(_anchorIndex, index);

		[self setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(low, high - low + 1)]];
		return;
	}
	[self setSelectionIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index]];
	_anchorIndex = index;
}

/* ============================================================================================
 * THE BACKGROUND.
 * ============================================================================================ */
- (void)setBackgroundColors:(NSArray *)colors
{
	NSArray *copy = nil;

	if (colors != nil && [colors count] > 0) {
		copy = [[NSArray alloc] initWithArray:colors];
	}
	[_backgroundColors release];
	_backgroundColors = copy;
	[self setNeedsDisplay:YES];
}

- (NSArray *)backgroundColors
{
	return _backgroundColors;
}

/* **ONE COLOUR FILLS, TWO OR MORE GRADIENT, NONE MEANS THE DEFAULT.** The gradient runs bottom-to-top in this flipped
 * view (angle 90), so the array's first colour is at the top — the order a caller reads top-down. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];

	(void)dirtyRect;
	if (_backgroundColors == nil) {
		[[NSColor controlBackgroundColor] setFill];
		[[NSBezierPath bezierPathWithRect:bounds] fill];
		return;
	}
	if ([_backgroundColors count] == 1) {
		[[_backgroundColors objectAtIndex:0] setFill];
		[[NSBezierPath bezierPathWithRect:bounds] fill];
		return;
	}
	{
		NSGradient *gradient = [[NSGradient alloc] initWithColors:_backgroundColors];

		if (gradient != nil) {
			[gradient drawInRect:bounds angle:90.0];
			[gradient release];
		} else {
			[[_backgroundColors objectAtIndex:0] setFill];
			[[NSBezierPath bezierPathWithRect:bounds] fill];
		}
	}
}

/* ============================================================================================
 * THE DRAG SOURCE.
 * ============================================================================================ */
- (void)setDraggingSourceOperationMask:(NSDragOperation)dragOperationMask forLocal:(BOOL)localDestination
{
	if (localDestination) {
		_localDragMask = dragOperationMask;
	} else {
		_nonLocalDragMask = dragOperationMask;
	}
}

/* THE `NSDraggingSource` REQUIRED DOOR, asked by the session `-dragImage:...` begins. */
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	return isLocal ? _localDragMask : _nonLocalDragMask;
}

/* **THE PROMISED-FILES DOOR IS THE DELEGATE'S, WITH THE INDEXES THE LAST SOURCE DRAG CARRIED.** Apple implements this
 * on NSCollectionView exactly so a delegate does not have to be the dragging source itself. */
- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropURL
{
	NSIndexSet *indexes = (_draggedIndexes != nil) ? _draggedIndexes : _selectionIndexes;

	if (_delegate != nil && [_delegate respondsToSelector:
		@selector(collectionView:namesOfPromisedFilesDroppedAtDestination:forDraggedItemsAtIndexes:)]) {
		return [_delegate collectionView:self namesOfPromisedFilesDroppedAtDestination:dropURL
			 forDraggedItemsAtIndexes:indexes];
	}
	return nil;
}

/* **THE DEFAULT IMAGE IS THE UNION OF THE ITEMS' FRAMES, RENDERED TILE BY TILE.** The delegate's matching door is
 * preferred when it implements one; otherwise each item's view draws itself into a bitmap at its frame's offset from
 * the union's origin. The offset is an in/out parameter, set to zero (centred under the pointer) when this class
 * composes the image. */
- (NSImage *)draggingImageForItemsAtIndexes:(NSIndexSet *)indexes
				  withEvent:(NSEvent *)event
				     offset:(NSPointPointer)dragImageOffset
{
	NSRect unionRect = NSZeroRect;
	BOOL haveRect = NO;
	NSUInteger index;
	NSBitmapImageRep *rep;
	NSImage *image;
	CGContextRef cg;

	if (indexes == nil || [indexes count] == 0) {
		return nil;
	}
	if (dragImageOffset != NULL) {
		*dragImageOffset = NSZeroPoint;
	}
	if (_delegate != nil && [_delegate respondsToSelector:
		@selector(collectionView:draggingImageForItemsAtIndexes:withEvent:offset:)]) {
		return [_delegate collectionView:self draggingImageForItemsAtIndexes:indexes
					 withEvent:event offset:dragImageOffset];
	}
	index = [indexes firstIndex];
	while (index != NSNotFound) {
		if (index < [_content count]) {
			NSRect frame = [self frameForItemAtIndex:index];

			if (frame.size.width > 0.0 && frame.size.height > 0.0) {
				unionRect = haveRect ? NSUnionRect(unionRect, frame) : frame;
				haveRect = YES;
			}
		}
		index = [indexes indexGreaterThanIndex:index];
	}
	if (!haveRect) {
		return nil;
	}
	rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)ceil(unionRect.size.width)
		pixelsHigh:(NSInteger)ceil(unionRect.size.height)
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace
		bytesPerRow:(NSInteger)ceil(unionRect.size.width) * 4
		bitsPerPixel:32];
	if (rep == nil) {
		return nil;
	}
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	index = [indexes firstIndex];
	while (index != NSNotFound) {
		NSCollectionViewItem *item = [self itemAtIndex:index];

		if (item != nil) {
			NSView *view = [item cg_viewIfLoaded];

			if (view != nil) {
				NSRect frame = [self frameForItemAtIndex:index];

				[NSGraphicsContext saveGraphicsState];
				if (cg != NULL) {
					CGContextTranslateCTM(cg, frame.origin.x - unionRect.origin.x,
							     frame.origin.y - unionRect.origin.y);
				}
				[view drawRect:[view bounds]];
				[NSGraphicsContext restoreGraphicsState];
			}
		}
		index = [indexes indexGreaterThanIndex:index];
	}
	image = [[NSImage alloc] initWithSize:unionRect.size];
	if (image != nil) {
		[image addRepresentation:rep];
	}
	[rep release];
	return [image autorelease];
}

/* **A DRAG BEGINS FROM THE SELECTION, AND ONLY FROM A SELECTION.** Apple's collection view drags the selected items;
 * with nothing selected there is nothing to carry. `-canDragItemsAtIndexes:` defaults to YES, but
 * `-writeItemsAtIndexes:toPasteboard:` has no default — Apple's sentence is that a collection view without it "cannot
 * be a drag source". The pasteboard is the shared `NSDragPboard`, and the delegate writes the types and data. */
- (void)mouseDragged:(NSEvent *)event
{
	NSPasteboard *board;
	NSPoint offset = NSZeroPoint;
	NSImage *image;
	NSRect first;
	NSIndexSet *indexes = [[NSIndexSet alloc] initWithIndexSet:_selectionIndexes];

	if ([indexes count] == 0 || _draggedIndexes != nil) {
		[indexes release];
		return;
	}
	if (_delegate == nil || ![_delegate respondsToSelector:
		@selector(collectionView:writeItemsAtIndexes:toPasteboard:)]) {
		[indexes release];
		return;
	}
	if ([_delegate respondsToSelector:@selector(collectionView:canDragItemsAtIndexes:withEvent:)] &&
	    ![_delegate collectionView:self canDragItemsAtIndexes:indexes withEvent:event]) {
		[indexes release];
		return;
	}
	board = [NSPasteboard pasteboardWithName:NSDragPboard];
	if (board == nil || ![_delegate collectionView:self writeItemsAtIndexes:indexes toPasteboard:board]) {
		[indexes release];
		return;
	}
	image = [self draggingImageForItemsAtIndexes:indexes withEvent:event offset:&offset];
	if (image == nil) {
		[indexes release];
		return;
	}
	first = [self frameForItemAtIndex:[indexes firstIndex]];
	[_draggedIndexes release];
	_draggedIndexes = indexes;		/* ownership moves to the ivar */
	[self dragImage:image
		     at:first.origin
		 offset:NSMakeSize(offset.x, offset.y)
		  event:event
	     pasteboard:board
		 source:self
	      slideBack:YES];
}

/* ============================================================================================
 * THE DRAG DESTINATION.
 * ============================================================================================ */
/* **THE PROPOSED INDEX IS THE ONE UNDER THE POINTER, AND THE HALF OF THE CELL DECIDES BEFORE-OR-ON.** A point in the
 * left half of a tile is "before it"; the right half is "on it" — Apple's "closer to the middle of the item than either
 * of its edges", reduced to the axis a grid reads. A point past the tiles proposes the item after the last one, and an
 * empty grid proposes zero. The delegate may retarget both values, and its answer is the operation the drop will use. */
- (NSDragOperation)cg_updateDrop:(id <NSDraggingInfo>)info
{
	NSPoint point = [self convertPoint:[info draggingLocation] fromView:nil];
	NSInteger index = [self cg_itemIndexAtPoint:point];
	NSCollectionViewDropOperation operation = NSCollectionViewDropBefore;
	NSInteger proposed;

	if (index == NSNotFound) {
		NSSize size = [self cg_itemSize];
		NSUInteger columns = [self cg_columnCount];

		if (columns > 0 && size.width > 0.0 && size.height > 0.0) {
			NSRect bounds = [self bounds];
			NSInteger column = (NSInteger)floor((point.x - NSMinX(bounds)) / size.width);
			NSInteger row = (NSInteger)floor((point.y - NSMinY(bounds)) / size.height);

			if (column < 0) {
				column = 0;
			}
			if (column >= (NSInteger)columns) {
				column = (NSInteger)columns - 1;
			}
			if (row < 0) {
				row = 0;
			}
			index = row * (NSInteger)columns + column;
			if (index > (NSInteger)[self cg_displayedCount]) {
				index = (NSInteger)[self cg_displayedCount];
			}
		} else {
			index = 0;
		}
	} else {
		NSRect frame = [self frameForItemAtIndex:(NSUInteger)index];

		operation = (point.x > NSMidX(frame)) ? NSCollectionViewDropOn : NSCollectionViewDropBefore;
	}
	proposed = index;
	if (_delegate != nil && [_delegate respondsToSelector:
		@selector(collectionView:validateDrop:proposedIndex:dropOperation:)]) {
		NSDragOperation answer = [_delegate collectionView:self validateDrop:info
							proposedIndex:&proposed
						       dropOperation:&operation];

		_dropIndex = proposed;
		_dropOperation = operation;
		return answer;
	}
	_dropIndex = proposed;
	_dropOperation = operation;
	return NSDragOperationNone;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	return [self cg_updateDrop:sender];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
	return [self cg_updateDrop:sender];
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	(void)sender;
	_dropIndex = -1;
	_dropOperation = NSCollectionViewDropBefore;
}

/* **PERFORMING THE DROP IS THE DELEGATE'S DECISION, WITH THE INDEX AND OPERATION IT LAST APPROVED.** A collection view
 * with no `acceptDrop` door accepts nothing, which is Apple's contract for a destination. */
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	if (_delegate != nil && [_delegate respondsToSelector:
		@selector(collectionView:acceptDrop:index:dropOperation:)]) {
		return [_delegate collectionView:self acceptDrop:sender index:_dropIndex
				   dropOperation:_dropOperation];
	}
	return NO;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
	/* Nothing beyond the delegate's own model update: this tier has no drop animation or drop feedback of its own. */
}

/* ============================================================================================
 * THE DELEGATE.
 * ============================================================================================ */
- (void)setDelegate:(id <NSCollectionViewDelegate>)aDelegate
{
	_delegate = aDelegate;	/* NOT RETAINED, this tree's rule for every delegate */
}

- (id <NSCollectionViewDelegate>)delegate
{
	return _delegate;
}

@end
