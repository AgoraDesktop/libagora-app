/*
 * NSCollectionView.h — A GRID OF ITEMS, AND THE ITEMS ARE VIEW CONTROLLERS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE CLASS IS THE OTHER HALF OF `NSCollectionViewItem`, WHICH HAS BEEN HERE WAITING FOR IT.** A collection view is
 * a grid of TILES: the caller hands it an array of represented objects (`-setContent:`), a PROTOTYPE item
 * (`-setItemPrototype:`) and a delegate; the view makes one `NSCollectionViewItem` per object, gives each one the
 * object as its `-representedObject`, adds the item's VIEW as a subview at a cell of the grid, and asks the item
 * whether it is selected so the tile can draw its highlight. The item class's own header said the view was absent;
 * this slice is that sentence retired.
 *
 * **THE GRID IS UNIFORM AND FLIPPED, AND THE ITEM SIZE COMES FROM THE PROTOTYPE.** A collection view is the cousin of
 * a table view, and it takes the same coordinate choice: `-isFlipped` is YES, so row 0 is at the TOP and a frame's y
 * grows downward. Every cell has the SAME size — the prototype view's frame, clamped by `-minItemSize` and
 * `-maxItemSize` — and the number of columns is the view's width divided by the cell width, at least one and at most
 * `-maxNumberOfColumns` when that is non-zero. `-maxNumberOfRows` is a DISPLAY cap: items beyond it are still items
 * (`-itemAtIndex:` answers them) but they have no tile. `-frameForItemAtIndex:` is the one place a cell's rectangle is
 * computed, and the layout, the hit test and the drag image all ask it.
 *
 * **RECYCLING IS A POOL ACROSS REBUILDS, NOT A SCROLLING WINDOW.** A content change or a geometry change rebuilds the
 * tiles: the old item VIEWS leave the tree, the items go into a pool, and the next tiles come from that pool before a
 * new item is made. Apple's collection view recycles as tiles scroll out of a clip view; this tier has no
 * scroll-driven item recycling, and the header says so rather than implying it. `-itemAtIndex:` is lazy: an index
 * beyond the display cap is still a valid item, made on demand, but it has no view until it is displayed.
 *
 * **SELECTION IS ONE INDEX SET, AND THE TILE READS IT.** `-selectionIndexes` is the state; `-isSelectable` gates the
 * pointer; `-allowsMultipleSelection` decides whether a plain click replaces or toggles. A click makes this view the
 * first responder (which is what `-isFirstResponder` answers, and what a tile would use to pick a focused highlight),
 * Command toggles, Shift extends from the last plain click, and a click on empty space clears. Every change is copied
 * to the items' `-setSelected:`, so a tile's own drawing is what shows it.
 *
 * **DRAGGING IS WIRED ON BOTH SIDES.** As a SOURCE, `-mouseDragged:` asks the delegate whether the selection may be
 * dragged (`-collectionView:canDragItemsAtIndexes:withEvent:`), builds a `NSDragPboard` through
 * `-collectionView:writeItemsAtIndexes:toPasteboard:`, composes the drag image with
 * `-draggingImageForItemsAtIndexes:withEvent:offset:` (the delegate's own image wins when it implements the matching
 * door) and begins the session with the per-local/non-local masks from
 * `-setDraggingSourceOperationMask:forLocal:`. As a DESTINATION it answers `-draggingEntered:`/`-draggingUpdated:`
 * by proposing an index and operation from the pointer and asking the delegate's
 * `-collectionView:validateDrop:proposedIndex:dropOperation:`, and `-performDragOperation:` asks
 * `-collectionView:acceptDrop:index:dropOperation:`. Both delegate protocols are therefore sent, not merely declared.
 *
 * **WHAT IS DELIBERATELY NOT HERE:** the item nib machinery (`-itemPrototype` is copied by class and view geometry,
 * not by unarchiving a nib), and the scroll-view integration that would make recycling lazy in the Apple sense. Each
 * is named here and at the door that would have to grow it.
 */
#ifndef APPKIT_NSCOLLECTIONVIEW_H
#define APPKIT_NSCOLLECTIONVIEW_H

#import <AppKit/NSView.h>
#import <AppKit/NSCollectionViewItem.h>
#import <AppKit/NSDragging.h>

NS_ASSUME_NONNULL_BEGIN

/* **THE DROP OPERATION, WHICH IS A FACT ABOUT WHERE A DROP LANDS RATHER THAN WHAT IT DOES.** `NSCollectionViewDropOn`
 * replaces the item under the pointer; `NSCollectionViewDropBefore` inserts ahead of it. The proposed value comes from
 * which half of the cell the pointer is in (see `-draggingUpdated:`), and a delegate may change it. */
typedef NSInteger NSCollectionViewDropOperation;
enum {
	NSCollectionViewDropOn = 0,
	NSCollectionViewDropBefore = 1
};

@protocol NSCollectionViewDelegate;

@interface NSCollectionView : NSView
{
	/* THE CONTENT, THE ITEMS AND THE POOL. `_items` is parallel to `_content` and holds NSNull for an index whose item
	 * has not been made; `_recycled` holds items whose views have left the tree, ready for the next rebuild. */
	NSArray *_content;				/* RETAINED */
	NSMutableArray *_items;				/* RETAINED, NSNull or NSCollectionViewItem */
	NSMutableArray *_recycled;			/* RETAINED, NSCollectionViewItem */
	NSCollectionViewItem *_itemPrototype;		/* RETAINED */
	NSMutableIndexSet *_selectionIndexes;		/* RETAINED */
	id <NSCollectionViewDelegate> _delegate;	/* NOT RETAINED */
	NSSize _minItemSize;
	NSSize _maxItemSize;
	NSUInteger _maxRows;
	NSUInteger _maxColumns;
	NSArray *_backgroundColors;			/* RETAINED, nil means the default */
	NSDragOperation _localDragMask;
	NSDragOperation _nonLocalDragMask;
	NSIndexSet *_draggedIndexes;			/* RETAINED, the last source's indexes */
	NSInteger _dropIndex;
	NSCollectionViewDropOperation _dropOperation;
	/* THE ANCHOR SHIFT-EXTENDS FROM: the index of the last plain click, or NSNotFound. */
	NSInteger _anchorIndex;
	BOOL _selectable;
	BOOL _allowsMultipleSelection;
	BOOL _rebuilding;
}

/* THE DESIGNATED INITIALISER IS THE INHERITED ONE; the defaults below are set where a fresh view is made (selectable,
 * multiple selection allowed, no content, no prototype, masks Every for local and None for non-local). */
- (instancetype)initWithFrame:(NSRect)frameRect;

/* ---- THE CONTENT AND THE ITEMS ---------------------------------------------------------------------- */

/* **THE CONTENT IS THE MODEL, AND IT IS RETAINED RATHER THAN COPIED.** The represented objects may be mutable and owned
 * by the caller; the view's job is to show them, not to freeze them. Setting it rebuilds the tiles, keeps the item
 * objects that can be reused, and intersects the selection with the new count. nil means an empty grid. */
- (void)setContent:(nullable NSArray *)content;
- (nullable NSArray *)content;

/* **THE PROTOTYPE IS THE FACTORY'S BLUEPRINT.** `-newItemForRepresentedObject:` copies it (class and view geometry,
 * see `NSCollectionViewItem -copy`), sets the represented object, and answers an item the view owns; a subclass that
 * wants another factory overrides that door. With NO prototype the door answers nil and the grid stays empty, which is
 * Apple's shape — the default is "from the prototype", and a caller with no prototype is a caller with no items. */
- (void)setItemPrototype:(nullable NSCollectionViewItem *)prototype;
- (nullable NSCollectionViewItem *)itemPrototype;

/* **THE ITEM AT AN INDEX, MADE ON DEMAND.** An index beyond the display cap still answers an item — the content is
 * there, only the tile is not — and an index outside the content answers nil. The item is remembered, so two calls
 * answer the same controller. */
- (nullable NSCollectionViewItem *)itemAtIndex:(NSUInteger)index;

/* **THE ONE PLACE A CELL'S RECTANGLE IS COMPUTED.** The frame is in this view's flipped coordinates; row 0 is at the
 * top. An index outside the content answers `NSZeroRect`. The layout, the hit test and the drag image all read this
 * door, so a tile cannot be drawn in one place and clicked in another. */
- (NSRect)frameForItemAtIndex:(NSUInteger)index;

/* THE FACTORY. The default copies `-itemPrototype`, sets the object and answers a +1 item; the view releases it when
 * it stores it. An override that returns nil means "this object has no item", and the grid skips it. */
- (nullable NSCollectionViewItem *)newItemForRepresentedObject:(id)object;

/* ---- THE GRID ------------------------------------------------------------------------------------- */

/* The prototype's own view size is the natural cell; these clamp it. `-maxItemSize` of zero means NO LIMIT (Apple's
 * default), not "zero-sized items". Setting any of them rebuilds the tiles. */
- (void)setMinItemSize:(NSSize)size;
- (NSSize)minItemSize;
- (void)setMaxItemSize:(NSSize)size;
- (NSSize)maxItemSize;

/* **THE DISPLAY CAPS, AND ZERO MEANS NO CAP** (Apple's default for both). Columns also decide the cell width; rows
 * only limit how many tiles are made. An item past the cap is still an item and has no view. */
- (void)setMaxNumberOfRows:(NSUInteger)number;
- (NSUInteger)maxNumberOfRows;
- (void)setMaxNumberOfColumns:(NSUInteger)number;
- (NSUInteger)maxNumberOfColumns;

/* ---- THE SELECTION --------------------------------------------------------------------------------- */

/* **ONE INDEX SET IS THE SELECTION, AND THE ITEMS ARE TOLD.** Setting it drops indexes outside the content, keeps only
 * the first when multiple selection is off, and copies the answer to each item's `-setSelected:` so a tile's own
 * drawing is what changes. An empty set is a valid answer (nothing selected). */
- (void)setSelectionIndexes:(nullable NSIndexSet *)indexes;
- (nullable NSIndexSet *)selectionIndexes;

/* `-isSelectable` gates the pointer and the first responder; `-allowsMultipleSelection` decides whether a plain click
 * replaces the selection or toggles one index. Both default to YES, which is Apple's default for multiple selection
 * and this tier's answer for the other. */
- (void)setSelectable:(BOOL)flag;
- (BOOL)isSelectable;
- (void)setAllowsMultipleSelection:(BOOL)flag;
- (BOOL)allowsMultipleSelection;

/* **WHETHER THIS VIEW IS THE WINDOW'S FIRST RESPONDER.** Apple declares the door because a tile may want a different
 * highlight when the grid has focus; it answers the window's own first-responder slot rather than a stored bit, so it
 * cannot disagree with the keyboard. */
- (BOOL)isFirstResponder;

/* ---- THE BACKGROUND -------------------------------------------------------------------------------- */

/* **THE BACKDROP IS A LIST OF COLOURS, AND ITS LENGTH IS THE RULE.** nil or an empty array restores the default
 * (`+controlBackgroundColor`); one colour fills; two or more draw a vertical gradient from the first to the last. The
 * array is copied, so a caller's mutable array cannot change the picture later. */
- (void)setBackgroundColors:(nullable NSArray *)colors;
- (nullable NSArray *)backgroundColors;

/* ---- DRAGGING: THE SOURCE --------------------------------------------------------------------------- */

/* **THE TWO MASKS ARE STORED SEPARATELY BECAUSE THE QUESTION IS "LOCAL TO THIS APPLICATION?"** Apple's defaults are
 * `NSDragOperationEvery` for a local destination and `NSDragOperationNone` for a foreign one. The stored pair is what
 * this view answers as an `NSDraggingSource`. */
- (void)setDraggingSourceOperationMask:(NSDragOperation)dragOperationMask forLocal:(BOOL)localDestination;

/* **THE DEFAULT DRAG IMAGE IS THE UNION OF THE ITEMS' FRAMES, RENDERED.** The delegate's matching door is preferred
 * when it implements one; the offset is an in/out parameter set to `NSZeroPoint` (the image centred under the
 * pointer). An empty or out-of-range index set answers nil. */
- (nullable NSImage *)draggingImageForItemsAtIndexes:(NSIndexSet *)indexes
					  withEvent:(nullable NSEvent *)event
					     offset:(NSPointPointer)dragImageOffset;

/* ---- THE DELEGATE ---------------------------------------------------------------------------------- */

- (void)setDelegate:(nullable id <NSCollectionViewDelegate>)aDelegate;
- (nullable id <NSCollectionViewDelegate>)delegate;

@end

/* **THE DELEGATE'S SIX OPTIONAL DOORS, EACH WITH A SENDER IN THIS CLASS.** Three are the source (may this drag start,
 * write the pasteboard, name the promised files, supply the image), one is the destination's review, and one accepts
 * the drop. A collection view with no delegate answers "no drag" and "no drop" rather than guessing. */
@protocol NSCollectionViewDelegate <NSObject>

@optional

/* THE SOURCE. Without `-writeItemsAtIndexes:toPasteboard:` a collection view cannot be a drag source (Apple's own
 * sentence); `canDrag` defaulting to YES matters only when that door is implemented. */
- (BOOL)collectionView:(NSCollectionView *)collectionView
     canDragItemsAtIndexes:(NSIndexSet *)indexes
	     withEvent:(NSEvent *)event;
- (BOOL)collectionView:(NSCollectionView *)collectionView
     writeItemsAtIndexes:(NSIndexSet *)indexes
	  toPasteboard:(NSPasteboard *)pasteboard;
- (nullable NSArray *)collectionView:(NSCollectionView *)collectionView
     namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropURL
	 forDraggedItemsAtIndexes:(NSIndexSet *)indexes;
- (nullable NSImage *)collectionView:(NSCollectionView *)collectionView
     draggingImageForItemsAtIndexes:(NSIndexSet *)indexes
			  withEvent:(NSEvent *)event
			     offset:(NSPointPointer)dragImageOffset;

/* THE DESTINATION. The proposed index and operation are IN/OUT: the delegate may retarget the drop, and the answer is
 * the operation it will accept (anything but `NSDragOperationNone`). */
- (NSDragOperation)collectionView:(NSCollectionView *)collectionView
		      validateDrop:(id <NSDraggingInfo>)draggingInfo
		     proposedIndex:(NSInteger *)proposedDropIndex
		    dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation;
- (BOOL)collectionView:(NSCollectionView *)collectionView
	    acceptDrop:(id <NSDraggingInfo>)draggingInfo
		 index:(NSInteger)index
	 dropOperation:(NSCollectionViewDropOperation)dropOperation;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLLECTIONVIEW_H */
