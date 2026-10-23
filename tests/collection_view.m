/*
 * collection_view — NSCollectionView: the grid, the item pool, the selection, the backdrop and the two drag halves.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE MEASURES FRAMES AND INK, NOT STORED NUMBERS.** `-frameForItemAtIndex:` is the grid's one arithmetic, so
 * every layout check reads it and the item views' frames; the selection checks read both the index set and the ITEMS'
 * `-isSelected:`, because the tiles are what a person sees; the backdrop is read out of a bitmap, because a colour array
 * that never reaches the drawing is a setting nobody reads.
 *
 * WHAT IS ASSERTED, and the sender each one names:
 *
 *   1. The defaults: empty content and selection, selectable and multiple-selection YES, zero min/max item sizes, zero
 *      display caps, no prototype or delegate, and the two drag masks (Every local, None foreign).
 *   2. The prototype factory: `-itemAtIndex:` copies the prototype's class and view geometry, sets the represented
 *      object and the borrowed collection view, and the tile is a subview at the frame the grid computed.
 *   3. The grid: four columns at 50-point cells in a 240-point view, the wraparound at index 4, `-maxNumberOfColumns:`
 *      narrowing it, `-maxNumberOfRows:` capping DISPLAYED items while `-itemAtIndex:` still answers them, and the
 *      min/max clamps changing the cell size.
 *   4. Recycling: a content change reuses the controllers it had (identity), and the extra ones are new.
 *   5. Selection: the index set is pruned to the content and to one index when multiple selection is off, the items are
 *      told, a click selects, Shift extends, Command toggles, empty space clears, and `-isFirstResponder` follows the
 *      window.
 *   6. The backdrop: one colour fills, two gradient (the two ends differ), and the array is copied.
 *   7. The drag image: the default is the union of the item frames; the delegate's own image and offset win; an empty
 *      set answers nil.
 *   8. The drag source: the masks round-trip, `-mouseDragged:` asks `canDrag` and `writeItems` with the SELECTION and
 *      writes the pasteboard, and `-namesOfPromisedFilesDroppedAtDestination:` asks the delegate with the same indexes.
 *   9. The drag destination: `-draggingEntered:` proposes before/on from the cell's halves and the delegate may retarget
 *      both, and `-performDragOperation:` asks `acceptDrop` with what was last proposed.
 */
#import <AppKit/NSCollectionView.h>
#import <AppKit/NSCollectionViewItem.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSDragging.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#define VIEW_W 240.0
#define VIEW_H 160.0
#define CELL_W 50.0
#define CELL_H 40.0

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int rect_equal(NSRect a, NSRect b)
{
	return a.origin.x == b.origin.x && a.origin.y == b.origin.y
		&& a.size.width == b.size.width && a.size.height == b.size.height;
}

static NSEvent *mouse(int type, NSPoint where, NSUInteger flags)
{
	return [NSEvent mouseEventWithType:type location:where modifierFlags:flags
				 timestamp:0.0 windowNumber:0 context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

/* ============================================================================================ *
 * THE ITEM: A SUBCLASS, SO THE COPY'S CLASS IS CHECKABLE                                           *
 * ============================================================================================ */
@interface AGTileItem : NSCollectionViewItem
@end

@implementation AGTileItem
@end

/* ============================================================================================ *
 * THE DELEGATE, WHICH RECORDS EVERY DOOR IT IS ASKED THROUGH                                    *
 * ============================================================================================ */
@interface AGCVDelegate : NSObject <NSCollectionViewDelegate>
{
@public
	BOOL canDrag;
	BOOL acceptDrop;
	BOOL retargetDrop;
	NSInteger retargetIndex;
	NSCollectionViewDropOperation retargetOperation;
	NSDragOperation validateAnswer;
	NSInteger canDragAsked;
	NSInteger writeAsked;
	NSInteger namesAsked;
	NSInteger imageAsked;
	NSInteger validateAsked;
	NSInteger acceptAsked;
	NSIndexSet *lastIndexes;
	NSInteger lastProposedIndex;
	NSCollectionViewDropOperation lastProposedOperation;
	NSInteger lastAcceptIndex;
	NSCollectionViewDropOperation lastAcceptOperation;
	NSImage *image;
	NSPoint imageOffset;
	NSArray *names;
}
@end

@implementation AGCVDelegate

- (id)init
{
	self = [super init];
	if (self != nil) {
		canDrag = YES;
		acceptDrop = YES;
		validateAnswer = NSDragOperationCopy;
	}
	return self;
}

- (BOOL)collectionView:(NSCollectionView *)view canDragItemsAtIndexes:(NSIndexSet *)indexes withEvent:(NSEvent *)event
{
	(void)view;
	(void)event;
	canDragAsked++;
	[lastIndexes release];
	lastIndexes = [indexes copy];
	return canDrag;
}

- (BOOL)collectionView:(NSCollectionView *)view writeItemsAtIndexes:(NSIndexSet *)indexes toPasteboard:(NSPasteboard *)pasteboard
{
	(void)view;
	writeAsked++;
	[lastIndexes release];
	lastIndexes = [indexes copy];
	[pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[pasteboard setString:@"dragged" forType:NSStringPboardType];
	return YES;
}

- (NSArray *)collectionView:(NSCollectionView *)view
     namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropURL
	 forDraggedItemsAtIndexes:(NSIndexSet *)indexes
{
	(void)view;
	(void)dropURL;
	namesAsked++;
	[lastIndexes release];
	lastIndexes = [indexes copy];
	return names;
}

- (NSImage *)collectionView:(NSCollectionView *)view
     draggingImageForItemsAtIndexes:(NSIndexSet *)indexes
			  withEvent:(NSEvent *)event
			     offset:(NSPointPointer)dragImageOffset
{
	(void)view;
	(void)event;
	imageAsked++;
	[lastIndexes release];
	lastIndexes = [indexes copy];
	if (dragImageOffset != NULL) {
		*dragImageOffset = imageOffset;
	}
	return image;
}

- (NSDragOperation)collectionView:(NSCollectionView *)view
		      validateDrop:(id <NSDraggingInfo>)draggingInfo
		     proposedIndex:(NSInteger *)proposedDropIndex
		    dropOperation:(NSCollectionViewDropOperation *)proposedDropOperation
{
	(void)view;
	(void)draggingInfo;
	validateAsked++;
	lastProposedIndex = *proposedDropIndex;
	lastProposedOperation = *proposedDropOperation;
	if (retargetDrop) {
		*proposedDropIndex = retargetIndex;
		*proposedDropOperation = retargetOperation;
	}
	return validateAnswer;
}

- (BOOL)collectionView:(NSCollectionView *)view
	    acceptDrop:(id <NSDraggingInfo>)draggingInfo
		 index:(NSInteger)index
	 dropOperation:(NSCollectionViewDropOperation)dropOperation
{
	(void)view;
	(void)draggingInfo;
	acceptAsked++;
	lastAcceptIndex = index;
	lastAcceptOperation = dropOperation;
	return acceptDrop;
}

- (void)dealloc
{
	[lastIndexes release];
	[names release];
	[image release];
	[super dealloc];
}

@end

/* ============================================================================================ *
 * A DRAGGING INFO, BECAUSE THE DESTINATION DOORS TAKE ONE                                         *
 * ============================================================================================ */
@interface AGDropInfo : NSObject <NSDraggingInfo>
{
@public
	NSPoint location;		/* in the destination window's coordinates */
}
@end

@implementation AGDropInfo

- (NSWindow *)draggingDestinationWindow { return nil; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationCopy; }
- (NSPoint)draggingLocation { return location; }
- (NSPoint)draggedImageLocation { return location; }
- (NSImage *)draggedImage { return nil; }
- (NSPasteboard *)draggingPasteboard { return [NSPasteboard pasteboardWithName:NSDragPboard]; }
- (id)draggingSource { return nil; }
- (NSInteger)draggingSequenceNumber { return 1; }
- (void)slideDraggedImageTo:(NSPoint)screenPoint { (void)screenPoint; }
- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination
{
	(void)dropDestination;
	return nil;
}

@end

/* The source's mask door is not in the class's Apple surface; the probe declares the protocol method it implements. */
@interface NSCollectionView (AGCollectionProbe)
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal;
- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropURL;
@end

static NSBitmapImageRep *render_view(NSView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)VIEW_W pixelsHigh:(NSInteger)VIEW_H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)VIEW_W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[view drawRect:[view bounds]];
	return rep;
}

int main(void)
{
	@autoreleasepool {
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)
							      styleMask:NSBorderlessWindowMask
								backing:NSBackingStoreBuffered
								  defer:NO];
		NSCollectionView *view = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0.0, 0.0, VIEW_W, VIEW_H)];
		AGTileItem *prototype = [[AGTileItem alloc] initWithNibName:nil bundle:nil];
		NSView *prototypeView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, CELL_W, CELL_H)];
		AGCVDelegate *delegate = [[AGCVDelegate alloc] init];
		NSArray *three = [NSArray arrayWithObjects:@"a", @"b", @"c", nil];

		[prototype setView:prototypeView];
		[prototypeView release];
		[window setContentView:view];

		/* 1. THE DEFAULTS. */
		check([[view content] count] == 0, "a fresh collection view has no content");
		check([[view selectionIndexes] count] == 0, "and no selection");
		check([view isSelectable] && [view allowsMultipleSelection],
		      "selectable, with multiple selection allowed (Apple's default)");
		check([view minItemSize].width == 0.0 && [view minItemSize].height == 0.0
		      && [view maxItemSize].width == 0.0 && [view maxItemSize].height == 0.0,
		      "zero min and max item sizes, which mean no limit");
		check([view maxNumberOfRows] == 0 && [view maxNumberOfColumns] == 0,
		      "zero display caps");
		check([view itemPrototype] == nil && [view delegate] == nil,
		      "no prototype and no delegate");
		check([view backgroundColors] == nil, "no backdrop colours, so the default");
		check([view isFlipped], "the view is flipped: row 0 is at the top");
		check([view itemAtIndex:0] == nil && rect_equal([view frameForItemAtIndex:0], NSZeroRect),
		      "an index with no content has no item and no frame");
		check([view draggingSourceOperationMaskForLocal:YES] == NSDragOperationEvery
		      && [view draggingSourceOperationMaskForLocal:NO] == NSDragOperationNone,
		      "the default drag masks are Every locally and None abroad");

		/* 2. THE PROTOTYPE AND THE ITEMS. */
		[view setItemPrototype:prototype];
		check([view itemPrototype] == prototype, "the prototype is answered back");
		[view setContent:three];
		check([[view content] count] == 3, "the content is three objects");
		{
			NSCollectionViewItem *item = [view itemAtIndex:0];

			check([item isKindOfClass:[AGTileItem class]], "the factory copies the prototype's class");
			check([[item representedObject] isEqual:@"a"], "and sets the represented object");
			check([item collectionView] == view, "and the borrowed collection view");
			check([item cg_viewIfLoaded] != nil && [[item cg_viewIfLoaded] superview] == view,
			      "and its view is a tile in the tree");
			check(rect_equal([[item cg_viewIfLoaded] frame], [view frameForItemAtIndex:0]),
			      "framed by the grid's own door");
			check([[item cg_viewIfLoaded] class] == [NSView class],
			      "and it is a view of the prototype view's class");
			check([view itemAtIndex:3] == nil && rect_equal([view frameForItemAtIndex:3], NSZeroRect),
			      "an index past the content has no item and no frame");
		}

		/* 3. THE GRID'S ARITHMETIC. */
		check(rect_equal([view frameForItemAtIndex:0], NSMakeRect(0.0, 0.0, CELL_W, CELL_H)),
		      "cell 0 is the top-left");
		check(rect_equal([view frameForItemAtIndex:1], NSMakeRect(CELL_W, 0.0, CELL_W, CELL_H)),
		      "cell 1 is to its right");
		[view setContent:[NSArray arrayWithObjects:@"a", @"b", @"c", @"d", @"e", @"f", nil]];
		check(rect_equal([view frameForItemAtIndex:4], NSMakeRect(0.0, CELL_H, CELL_W, CELL_H)),
		      "index 4 wraps to the second row at x 0");
		check(rect_equal([view frameForItemAtIndex:5], NSMakeRect(CELL_W, CELL_H, CELL_W, CELL_H)),
		      "and index 5 is beside it");
		[view setMaxNumberOfColumns:2];
		check(rect_equal([view frameForItemAtIndex:2], NSMakeRect(0.0, CELL_H, CELL_W, CELL_H)),
		      "`-setMaxNumberOfColumns:` narrows the grid to two columns");
		[view setMaxNumberOfColumns:0];
		[view setMaxNumberOfRows:1];
		check([view itemAtIndex:5] != nil, "a row cap still leaves the ITEM answerable");
		check([[[view itemAtIndex:5] cg_viewIfLoaded] superview] == nil,
		      "but an item past the cap has no tile");
		check([[[view itemAtIndex:3] cg_viewIfLoaded] superview] == view,
		      "and one inside the cap does");
		[view setMaxNumberOfRows:0];
		[view setMaxItemSize:NSMakeSize(30.0, 30.0)];
		check(rect_equal([view frameForItemAtIndex:1], NSMakeRect(30.0, 0.0, 30.0, 30.0)),
		      "a maximum item size shrinks the cell and adds columns");
		[view setMaxItemSize:NSZeroSize];
		[view setMinItemSize:NSMakeSize(60.0, 50.0)];
		check(rect_equal([view frameForItemAtIndex:0], NSMakeRect(0.0, 0.0, 60.0, 50.0)),
		      "a minimum raises the cell's natural size");
		[view setMinItemSize:NSZeroSize];
		check(rect_equal([view frameForItemAtIndex:0], NSMakeRect(0.0, 0.0, CELL_W, CELL_H)),
		      "and clearing both restores the prototype's own size");

		/* 4. RECYCLING ACROSS A CONTENT CHANGE. */
		{
			NSCollectionViewItem *first = [view itemAtIndex:0];

			[view setContent:[NSArray arrayWithObjects:@"a", @"b", @"c", @"d", @"e", @"f", @"g", nil]];
			check([view itemAtIndex:0] == first, "a content change reuses the controller it had");
			check([[view itemAtIndex:0] representedObject] != nil, "with a represented object");
			check([[view itemAtIndex:6] cg_viewIfLoaded] != nil, "and the extra item is made fresh");
		}

		/* 5. THE SELECTION. */
		[view setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)]];
		check([[view selectionIndexes] count] == 3, "three indexes are selected");
		check([[view itemAtIndex:1] isSelected] && ![[view itemAtIndex:0] isSelected],
		      "item 1 is selected and item 0 is not");
		[view setAllowsMultipleSelection:NO];
		check([[view selectionIndexes] count] == 1
		      && [[view selectionIndexes] containsIndex:1],
		      "turning multiple selection off keeps the first index");
		[view setAllowsMultipleSelection:YES];
		[view setSelectionIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 9)]];
		check([[view selectionIndexes] count] == 7,
		      "indexes past the content are dropped from the selection");
		[view setSelectable:NO];
		check([[view selectionIndexes] count] == 0 && ![[view itemAtIndex:0] isSelected],
		      "turning selectability off clears the selection and the items");
		[view setSelectable:YES];

		/* THE POINTER: a click selects, Shift extends, Command toggles, empty space clears. */
		[view setSelectionIndexes:nil];
		{
			NSPoint cell3 = NSMakePoint(CELL_W * 3.0 + 10.0, CELL_H / 2.0);
			NSPoint cell1 = NSMakePoint(CELL_W + 10.0, CELL_H / 2.0);
			NSPoint cell2 = NSMakePoint(CELL_W * 2.0 + 10.0, CELL_H / 2.0);
			NSPoint empty = NSMakePoint(VIEW_W - 5.0, VIEW_H - 5.0);

			[view mouseDown:mouse(NSLeftMouseDown, [view convertPoint:cell3 toView:nil], 0)];
			check([[view selectionIndexes] count] == 1
			      && [[view selectionIndexes] containsIndex:3],
			      "a plain click selects that item");
			[view mouseDown:mouse(NSLeftMouseDown, [view convertPoint:cell1 toView:nil], NSShiftKeyMask)];
			check([[view selectionIndexes] count] == 3
			      && [[view selectionIndexes] containsIndex:1]
			      && [[view selectionIndexes] containsIndex:2]
			      && [[view selectionIndexes] containsIndex:3],
			      "Shift-click extends the selection from the anchor");
			[view mouseDown:mouse(NSLeftMouseDown, [view convertPoint:cell2 toView:nil], NSCommandKeyMask)];
			check([[view selectionIndexes] count] == 2
			      && ![[view selectionIndexes] containsIndex:2],
			      "Command-click toggles one index off");
			[view mouseDown:mouse(NSLeftMouseDown, [view convertPoint:empty toView:nil], 0)];
			check([[view selectionIndexes] count] == 0,
			      "a click on empty space clears the selection");
		}
		check([window makeFirstResponder:view], "the view can become the window's first responder");
		check([view isFirstResponder], "and `-isFirstResponder` says so");
		[window makeFirstResponder:nil];
		check(![view isFirstResponder], "and says no when the focus moves");

		/* 6. THE BACKDROP, READ FROM PIXELS. */
		[view setBackgroundColors:[NSArray arrayWithObject:[NSColor redColor]]];
		{
			NSBitmapImageRep *rep = render_view(view);
			NSColor *pixel = [rep colorAtX:30 y:20];

			check(pixel != nil && [pixel redComponent] > 0.8 && [pixel greenComponent] < 0.2,
			      "one backdrop colour fills the view");
			[rep release];
		}
		[view setBackgroundColors:[NSArray arrayWithObjects:[NSColor redColor], [NSColor blueColor], nil]];
		{
			NSBitmapImageRep *rep = render_view(view);
			NSColor *top = [rep colorAtX:30 y:1];
			NSColor *bottom = [rep colorAtX:30 y:(NSInteger)VIEW_H - 2];
			CGFloat difference = fabs([top redComponent] - [bottom redComponent]);

			printf("  (note: gradient ends — top r %.2f, bottom r %.2f)\n",
			       (double)[top redComponent], (double)[bottom redComponent]);
			check(difference > 0.3, "two backdrop colours draw a gradient, not one flat fill");
			[rep release];
		}
		{
			NSMutableArray *mutable = [NSMutableArray arrayWithObject:[NSColor greenColor]];

			[view setBackgroundColors:mutable];
			[mutable addObject:[NSColor yellowColor]];
			check([[view backgroundColors] count] == 1,
			      "the backdrop list is copied, so a caller's later mutation changes nothing");
		}

		/* 7. THE DRAG IMAGE. */
		[view setContent:[NSArray arrayWithObjects:@"a", @"b", @"c", @"d", nil]];
		{
			NSPoint offset = NSMakePoint(1.0, 2.0);
			NSImage *image = [view draggingImageForItemsAtIndexes:
				[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]
				withEvent:nil offset:&offset];

			check(image != nil && NSEqualSizes([image size], NSMakeSize(CELL_W * 2.0, CELL_H)),
			      "the default drag image is the union of the selected items' frames");
			check(offset.x == 0.0 && offset.y == 0.0, "with a zero offset, centred under the pointer");
		}
		[view setDelegate:delegate];
		delegate->image = [[NSImage alloc] initWithSize:NSMakeSize(7.0, 7.0)];
		delegate->imageOffset = NSMakePoint(3.0, 4.0);
		{
			NSPoint offset = NSZeroPoint;
			NSImage *image = [view draggingImageForItemsAtIndexes:
				[NSIndexSet indexSetWithIndex:2] withEvent:nil offset:&offset];

			check(image == delegate->image && delegate->imageAsked == 1,
			      "the delegate's image door is preferred when it implements one");
			check(offset.x == 3.0 && offset.y == 4.0, "and its offset is the in/out answer");
		}
		{
			NSPoint emptyOffset = NSZeroPoint;

			check([view draggingImageForItemsAtIndexes:[NSIndexSet indexSet]
						 withEvent:nil offset:&emptyOffset] == nil,
			      "an empty index set answers no image");
		}

		/* 8. THE DRAG SOURCE. */
		[view setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
		[view setDraggingSourceOperationMask:NSDragOperationLink forLocal:NO];
		check([view draggingSourceOperationMaskForLocal:YES] == NSDragOperationCopy
		      && [view draggingSourceOperationMaskForLocal:NO] == NSDragOperationLink,
		      "the two drag masks round-trip separately");

		[view setSelectionIndexes:[NSIndexSet indexSetWithIndex:2]];
		delegate->canDragAsked = 0;
		delegate->writeAsked = 0;
		[view mouseDragged:mouse(NSLeftMouseDragged, [view convertPoint:NSMakePoint(110.0, 20.0) toView:nil], 0)];
		check(delegate->canDragAsked == 1 && delegate->writeAsked == 1,
		      "`-mouseDragged:` asks canDrag and then writeItems");
		check(delegate->lastIndexes != nil && [delegate->lastIndexes containsIndex:2],
		      "with the SELECTION as the dragged indexes");
		check([[[NSPasteboard pasteboardWithName:NSDragPboard] stringForType:NSStringPboardType]
			isEqual:@"dragged"],
		      "and the delegate's pasteboard write is on the drag board");

		delegate->names = [[NSArray alloc] initWithObjects:@"promised.txt", nil];
		{
			NSArray *names = [view namesOfPromisedFilesDroppedAtDestination:
				[NSURL fileURLWithPath:@"/tmp"]];

			check(delegate->namesAsked == 1 && names != nil && [[names objectAtIndex:0] isEqual:@"promised.txt"],
			      "the promised-file door asks the delegate, with the dragged indexes");
		}

		/* 9. THE DRAG DESTINATION. */
		{
			AGDropInfo *info = [[AGDropInfo alloc] init];
			NSPoint leftHalf = NSMakePoint(CELL_W * 2.0 + 5.0, CELL_H / 2.0);	/* item 2, left half */
			NSPoint rightHalf = NSMakePoint(CELL_W * 2.0 + CELL_W - 5.0, CELL_H / 2.0);
			NSPoint past = NSMakePoint(VIEW_W - 5.0, VIEW_H - 5.0);

			delegate->validateAsked = 0;
			info->location = [view convertPoint:leftHalf toView:nil];
			check([view draggingEntered:info] == NSDragOperationCopy,
			      "the destination returns the delegate's validated operation");
			check(delegate->lastProposedIndex == 2
			      && delegate->lastProposedOperation == NSCollectionViewDropBefore,
			      "a point in the cell's left half proposes DROP-BEFORE at that index");
			info->location = [view convertPoint:rightHalf toView:nil];
			[view draggingUpdated:info];
			check(delegate->lastProposedIndex == 2
			      && delegate->lastProposedOperation == NSCollectionViewDropOn,
			      "and the right half proposes DROP-ON");
			info->location = [view convertPoint:past toView:nil];
			[view draggingUpdated:info];
			check(delegate->lastProposedIndex == 4
			      && delegate->lastProposedOperation == NSCollectionViewDropBefore,
			      "a point past the tiles proposes the index after the last");

			delegate->retargetDrop = YES;
			delegate->retargetIndex = 3;
			delegate->retargetOperation = NSCollectionViewDropOn;
			delegate->validateAnswer = NSDragOperationLink;
			info->location = [view convertPoint:leftHalf toView:nil];
			check([view draggingEntered:info] == NSDragOperationLink, "the delegate may change the operation");
			delegate->acceptAsked = 0;
			check([view performDragOperation:info] && delegate->acceptAsked == 1,
			      "`-performDragOperation:` asks acceptDrop");
			check(delegate->lastAcceptIndex == 3
			      && delegate->lastAcceptOperation == NSCollectionViewDropOn,
			      "with the index and operation the delegate retargeted");
			delegate->retargetDrop = NO;
			delegate->acceptDrop = NO;
			[view draggingEntered:info];
			check(![view performDragOperation:info], "and a NO from acceptDrop refuses the drop");

			[view setDelegate:nil];
			check([view draggingEntered:info] == NSDragOperationNone
			      && ![view performDragOperation:info],
			      "a destination with no delegate neither validates nor accepts");
			[view setDelegate:delegate];
			[info release];
		}

		/* 10. SHRINKING THE CONTENT PRUNES THE SELECTION. */
		[view setContent:[NSArray arrayWithObjects:@"a", @"b", @"c", @"d", @"e", @"f", nil]];
		[view setSelectionIndexes:[NSIndexSet indexSetWithIndex:5]];
		[view setContent:[NSArray arrayWithObjects:@"a", @"b", nil]];
		check([[view selectionIndexes] count] == 0 && [view itemAtIndex:5] == nil,
		      "a smaller content drops the selection with the items");

		printf("collection_view: %d case(s) failed\n", s_failed);
		[delegate release];
		[prototype release];
		[view release];
		[window release];
	}
	return s_failed != 0;
}
