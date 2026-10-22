/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSDragging.h — the DRAG VOCABULARY and the IN-PROCESS DRAG SESSION.
 *
 * **THE SESSION IS HERE NOW, AND IT IS THE APPLICATION'S RATHER THAN THE WINDOW SERVER'S.** A drag begins in a
 * view, the view's window takes the pointer for the duration (the seam's own capture, which a window move and a
 * resize already use), and every motion and the release are routed to the session by `NSWindow -sendEvent:`.
 * The destination is found with `+[NSWindow windowNumberAtPoint:belowWindowWithWindowNumber:]` and the hit test of
 * that window's content view, so a drag can cross from one window of this application to another — which is what
 * the shell's icon view needs. WHAT IS STILL ABSENT IS THE CROSS-PROCESS HALF: another application's pasteboard,
 * another application's window as a destination, and the drag image living on the glass of a surface this client
 * does not own. Those need a transport in `window-server`'s protocol rather than a class here, and the README says
 * so where the gap is named.
 *
 * **THE DRAG IMAGE IS A BORDERLESS WINDOW**, moved with the pointer and drawn from the items' images. That is the
 * honest shape for a client-side window server: the image floats over every window of this application, which is
 * what a drag image is for. A machine with no compositor makes no window and the session still runs — the logic, the
 * destination search and the callbacks are all measurable offscreen, which is where most of this belongs.
 *
 * **THE PASTEBOARD IS THE CALLER'S, STATED RATHER THAN IMPLIED.** Apple's `-beginDraggingSessionWithItems:...`
 * builds a pasteboard from each item's PASTEBOARD WRITER; this tree has no `NSPasteboardItem` and no
 * `NSPasteboardWriting` protocol, so an item's writer is RECORDED and not consulted, and the session's pasteboard is
 * `NSDragPboard` (or the pasteboard the legacy door was handed). A source therefore writes its types to the
 * pasteboard before beginning the drag, exactly as the table's data source already does.
 */
#ifndef APPKIT_NSDRAGGING_H
#define APPKIT_NSDRAGGING_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSImage;
@class NSDraggingSession;
@class NSEvent;
@class NSPasteboard;
@class NSView;
@class NSWindow;
@class NSURL;
@class NSArray;

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

/* WHERE A DRAG IS HAPPENING. This tier has only the INSIDE case; the outside value is here because a source is
 * asked for its mask by context and a ported source will answer both. */
typedef NSInteger NSDraggingContext;

enum {
	NSDraggingContextOutsideApplication = 0,
	NSDraggingContextWithinApplication = 1
};

/* HOW SEVERAL DRAGGED ITEMS ARE ARRANGED. `None` means each item keeps the frame it was given, which is the only
 * formation this slice draws; the others are recorded so a caller's choice is not silently lost. */
typedef NSInteger NSDraggingFormation;

enum {
	NSDraggingFormationDefault = 0,
	NSDraggingFormationNone,
	NSDraggingFormationPile,
	NSDraggingFormationList,
	NSDraggingFormationStack
};

typedef NSInteger NSDragState;

enum {
	NSDragStateInactive = 0,
	NSDragStateRunning,
	NSDragStateDone
};

/* ============================================================================================ *
 * THE INFO A DESTINATION READS — 10.6's DOORS, WHICH ARE THE ONES THIS TIER'S SOURCE USES.      *
 * ============================================================================================ */

/* **THE OBJECT BEHIND IT IS THE SESSION'S OWN**, and it is NOT the session itself: Apple's session reports its
 * `-draggingLocation` in SCREEN coordinates while this protocol reports it in the DESTINATION WINDOW's, and one
 * selector cannot be both. So a private object reads the session's state and answers in the destination's terms,
 * which is why every value below moves with the pointer rather than being a snapshot taken at `-draggingEntered:`. */
@protocol NSDraggingInfo <NSObject>
@required
- (nullable NSWindow *)draggingDestinationWindow;
- (NSDragOperation)draggingSourceOperationMask;
- (NSPoint)draggingLocation;
- (NSPoint)draggedImageLocation;
- (nullable NSImage *)draggedImage;
- (nullable NSPasteboard *)draggingPasteboard;
- (nullable id)draggingSource;
- (NSInteger)draggingSequenceNumber;
- (void)slideDraggedImageTo:(NSPoint)screenPoint;
- (nullable NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination;
@optional
- (NSDraggingFormation)draggingFormation;
- (void)setDraggingFormation:(NSDraggingFormation)formation;
- (NSInteger)numberOfValidItemsForDrop;
- (void)setNumberOfValidItemsForDrop:(NSInteger)number;
@end

/* ============================================================================================ *
 * THE TWO SIDES' PROTOCOLS.                                                                    *
 * ============================================================================================ */

/* THE DESTINATION IS A VIEW, informal in 10.6 and formal here so a subclass's override is checked by the compiler
 * rather than by a string. Every door is optional: a view that implements only `-performDragOperation:` is a
 * destination, and `NSView` supplies the defaults the others would have had. */
@protocol NSDraggingDestination <NSObject>
@optional
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;
- (void)draggingExited:(nullable id <NSDraggingInfo>)sender;
- (void)draggingEnded:(id <NSDraggingInfo>)sender;
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
- (void)concludeDragOperation:(nullable id <NSDraggingInfo>)sender;
- (BOOL)wantsPeriodicDraggingUpdates;
@end

/* THE SOURCE ANSWERS ONE QUESTION AND MAY ANSWER THE REST. The required door is 10.6's; the session-shaped pair is
 * 10.7's and is preferred when a source implements it, so a source written for either era works. */
@protocol NSDraggingSource <NSObject>
@required
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal;
@optional
- (BOOL)ignoreModifierKeysWhileDragging;
- (void)draggedImage:(NSImage *)image beganAt:(NSPoint)screenPoint;
- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation;
- (void)draggedImage:(NSImage *)image movedTo:(NSPoint)screenPoint;
- (nullable NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination;
- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context;
- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint;
- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint;
- (void)draggingSession:(NSDraggingSession *)session
	      endedAtPoint:(NSPoint)screenPoint
	       operation:(NSDragOperation)operation;
@end

/* ============================================================================================ *
 * THE ITEM — ONE IMAGE AT ONE PLACE IN THE SOURCE VIEW.                                       *
 * ============================================================================================ */

/* **THE FRAME IS IN THE SOURCE VIEW'S COORDINATE SYSTEM**, which is Apple's contract for the modern pair: the view
 * converts it to the screen when the session begins, so a caller that moves the view before beginning does not have
 * to do screen arithmetic. `-item` is the pasteboard writer a caller handed in; it is stored and not consulted (see
 * the header block), which is why `-initWithPasteboardWriter:` accepts an `id` rather than naming a protocol this
 * tree has not got. */
@interface NSDraggingItem : NSObject
{
	id _item;			/* RETAINED */
	id _contents;			/* RETAINED: an NSImage, or nil */
	NSRect _draggingFrame;
}
- (instancetype)initWithPasteboardWriter:(nullable id)pasteboardWriter;
@property (nullable, readonly) id item;
@property (nonatomic) NSRect draggingFrame;
- (void)setDraggingFrame:(NSRect)frame contents:(nullable id)contents;
@property (nullable, readonly) NSArray *imageComponents;
@end

/* ============================================================================================ *
 * THE SESSION — THE STATE A DRAG CARRIES WHILE THE BUTTON IS DOWN.                             *
 * ============================================================================================ */

/* **THE SESSION IS RETAINED BY THE TIER WHILE IT RUNS**, so a caller may autorelease the object it was handed and
 * still read the ended state in the source's callback. `-draggingLocation` is in SCREEN coordinates, and
 * `-draggingState` moves Inactive -> Running -> Done; the object survives the transition so the source's
 * `-draggingSession:endedAtPoint:operation:` can read it after the drag.
 *
 * `-animatesToStartingPositionsOnCancelOrFail` is recorded and NOT animated: this slice removes the image window at
 * the end of a failed drag instead of sliding it home, and says so rather than dressing the removal as Apple's
 * animation. The same is true of `-slideDraggedImageTo:`, which moves the image and does not animate. */
@interface NSDraggingSession : NSObject
{
	NSMutableArray *_items;		/* RETAINED: NSDraggingItem */
	NSPasteboard *_pasteboard;	/* RETAINED */
	id <NSDraggingSource> _source;	/* RETAINED */
	NSView *_sourceView;		/* RETAINED while the drag runs */
	NSWindow *_sourceWindow;	/* RETAINED while the drag runs */
	NSWindow *_dragWindow;		/* RETAINED while the image is on the glass */
	NSWindow *_destinationWindow;	/* RETAINED while entered */
	NSView *_destinationView;	/* RETAINED while entered */
	NSImage *_image;		/* RETAINED: the composed drag image */
	NSRect _imageFrame;		/* SCREEN coordinates of the composed image at the pointer's press */
	NSPoint _location;		/* SCREEN coordinates of the pointer */
	NSPoint _initialLocation;	/* SCREEN coordinates where the drag began */
	NSPoint _imageOrigin;		/* SCREEN coordinates of the image's lower-left, which a slide changes */
	NSPoint _destinationPoint;	/* the pointer in the DESTINATION window's coordinates */
	NSPoint _pointerOffset;		/* image origin -> pointer, in screen points (an offset, not a size) */
	NSDragOperation _sourceMask;
	NSDragOperation _currentOperation;
	NSInteger _sequenceNumber;
	NSDragState _state;
	NSDraggingFormation _formation;
	BOOL _animatesToStartingPositionsOnCancelOrFail;
	BOOL _slideBack;
	BOOL _entered;
}
- (NSPoint)draggingLocation;
- (nullable NSPasteboard *)draggingPasteboard;
- (nullable id <NSDraggingSource>)draggingSource;
- (NSDragOperation)sourceOperationMask;
- (NSDragOperation)currentOperationMask;
@property (nonatomic) NSDraggingFormation draggingFormation;
@property (nonatomic) BOOL animatesToStartingPositionsOnCancelOrFail;
@property (readonly) NSDragState draggingState;
- (NSInteger)draggingSequenceNumber;

/* **THE TIER'S OWN DOORS, PREFIXED AS EVERY PRIVATE DOOR IN THIS TREE IS.** `+cg_activeSession` is what
 * `NSWindow -sendEvent:` asks before it dispatches; `-cg_handleEvent:` answers YES when the session CONSUMED the
 * event, which is how a drag keeps the mouse-up from also reaching the view under the pointer. The remaining pair
 * exists for the probes: one begins the drag without an event (the offscreen tests drive it a motion at a time), and
 * `-cg_draggingWindow` is the image's window, so a seam test can assert that the glass really moved. */
+ (nullable NSDraggingSession *)cg_activeSession;
- (BOOL)cg_handleEvent:(NSEvent *)event;
- (void)cg_finish;
- (nullable NSWindow *)cg_draggingWindow;
- (nullable NSWindow *)cg_sourceWindow;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDRAGGING_H */
