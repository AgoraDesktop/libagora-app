/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSDragging.h — the DRAG VOCABULARY this tier's path control names, and not yet the drag session.
 *
 * **THE FULL DRAGGING SYSTEM IS ABSENT AND THIS HEADER DOES NOT PRETEND OTHERWISE.** `NSDraggingSession`,
 * `NSDraggingItem`, the destination protocol's animation hooks and the pasteboard-backed cross-process drag loop are
 * their own slice. What `NSPathControl`'s 10.6 declaration needs is `NSDragOperation` and its values, and what the
 * table's LOCAL row drag needs is the three-answer `NSDraggingInfo` slice below; those are here and nothing else is.
 * A cross-process drag does not arrive, which both classes' headers state where a reader meets the gap.
 */
#ifndef APPKIT_NSDRAGGING_H
#define APPKIT_NSDRAGGING_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSPasteboard;

/* THE OPERATION IS A MASK, so the values are bits rather than an order. `Every` is the all-bits value Apple uses. */
typedef NSUInteger NSDragOperation;

enum {
	NSDragOperationNone = 0,
	NSDragOperationCopy = 1,
	NSDragOperationLink = 2,
	NSDragOperationGeneric = 4,
	NSDragOperationPrivate = 8,
	NSDragOperationMove = 16,
	NSDragOperationDelete = 32,
	NSDragOperationEvery = NSUIntegerMax
};

/* **THE PART OF `NSDraggingInfo` A DATA SOURCE NEEDS TO READ A DROP.** The full protocol also carries the source,
 * the image, the destination window and the animation hooks; those belong to the drag session this tier has not
 * built. The table's LOCAL row drag is the one caller here, and it supplies exactly these three answers. */
@protocol NSDraggingInfo <NSObject>
- (NSPasteboard *)draggingPasteboard;
- (NSPoint)draggingLocation;
- (NSDragOperation)draggingSourceOperationMask;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDRAGGING_H */
