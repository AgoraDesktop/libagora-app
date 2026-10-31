/*
 * AGExternalDrag.m — the drag that crosses applications, answered with `NSDraggingInfo`'s protocol.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE SEAM CARRIES THE GESTURE; THIS FILE SPEAKS APPKIT'S HALF OF IT.** A `drag_enter` names a window id and a point
 * in that window's coordinates; a view expects `-draggingEntered:`, a `-draggingLocation` in window space, and a
 * pasteboard it can read during `-performDragOperation:`. One translation, in one place, because a source and a
 * destination both have to agree about it.
 *
 * **AND THE EVENTS ARE QUEUED RATHER THAN CALLED WHERE THEY ARRIVE.** They arrive inside a Wayland dispatch, and a
 * drop's handler reads its payload over the same connection — a pump inside a dispatch is a re-entrant dispatch. The
 * seam's callbacks record what happened; `+cg_processPendingEvents` answers it where an event loop has already returned
 * (`-nextEventMatchingMask:`, the door every loop passes through). One extra pass, and a read that is not already
 * inside a dispatch.
 */

#import "AGExternalDrag.h"

#import <AppKit/NSDragging.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <stdlib.h>
#import <string.h>

#import "platform/AGWindowServer.h"

/* THE PRIVATE DOORS OF THE TWO OBJECTS THIS FILE SPEAKS TO, declared the way their own files declare them: a category,
 * so a method this file misspells is a warning rather than a silent no-op. */
@interface NSPasteboard (AGExternalDrag)
+ (NSPasteboard *)cg_dragDestinationBoard;
- (void)cg_beginDragWithTypes:(NSArray *)types;
- (void)cg_endDrag;
- (void)cg_remoteTakeFd:(int)fd;
- (void)cg_remoteTakeRefusal:(int)reason;
@end

@interface NSDraggingSession (AGExternalDrag)
+ (NSDraggingSession *)cg_activeSession;
- (NSPasteboard *)cg_pasteboard;
@end

/* ==================================================================================================
 * ONE DRAG AT A TIME, WHICH IS THE PROTOCOL'S OWN SHAPE.
 * ================================================================================================== */

static NSWindow *s_window;		/* RETAINED — the window the drag is over */
static NSView *s_view;			/* RETAINED — the view that took it, nil when none did */
static NSPasteboard *s_pasteboard;	/* RETAINED — the drag's own board, never the clipboard */
static NSPoint s_point;			/* in s_window's coordinates */
static NSDragOperation s_operation;	/* what the view last answered, intersected with what the source permits */
static NSDragOperation s_mask;		/* what the source permits, as it was announced with the drag */
static BOOL s_entered;			/* the view has heard `-draggingEntered:` and not yet `-draggingExited:` */
static BOOL s_dropped;			/* the drop has been queued: a later motion names where the hand let go, not where it is */
static NSInteger s_sequence;

/* The queue the seam's callbacks fill: each entry is `@[kind, @(a), @(b), payload]`. */
static NSMutableArray *s_pending;

/* **AND HOW A WINDOW ID BECOMES A WINDOW.** The real answer is the window number the compositor assigned; a test that has
 * no compositor replaces it, which is the only way an enter can be driven without a display. */
static AGExternalDragWindowLookup s_lookup;

static NSWindow *fn_lookup_window(uint32_t windowId)
{
	if (s_lookup != NULL) {
		return s_lookup(windowId);
	}
	/* **THE SEAM'S HANDLE IS THE SURFACE'S**, which is the object this client made for the window — not Apple's
	 * per-application `-windowNumber`, which no compositor has ever heard of. */
	return [NSWindow cg_windowWithSurfaceId:windowId];
}

static void fn_clear_state(void)
{
	s_entered = NO;
	s_dropped = NO;
	s_operation = NSDragOperationNone;
	s_mask = NSDragOperationNone;
	[s_window release];
	s_window = nil;
	[s_view release];
	s_view = nil;
	if (s_pasteboard != nil) {
		/* **THE OFFER GOES WITH THE GESTURE**: a board that kept a finished drag's types would answer `-types` for a
		 * payload nobody can serve any more. */
		[s_pasteboard cg_endDrag];
		[s_pasteboard release];
		s_pasteboard = nil;
	}
}

/* ==================================================================================================
 * THE DRAGGING INFO — WHAT A VIEW IS HANDED, ANSWERED FROM THE GESTURE.
 * ================================================================================================== */

@interface AGExternalDraggingInfo : NSObject <NSDraggingInfo>
@end

@implementation AGExternalDraggingInfo

- (NSWindow *)draggingDestinationWindow { return s_window; }

/* **THE SOURCE'S MASK, AS THE DRAG ANNOUNCED IT.** A destination cannot infer this: it decides whether a drop is a copy
 * or a move, so it comes off the wire rather than being invented here — which is why the protocol carries it. */
- (NSDragOperation)draggingSourceOperationMask { return s_mask; }

- (NSPoint)draggingLocation { return s_point; }

/* ANOTHER APPLICATION'S DRAG HAS NO IMAGE THIS PROCESS CAN SEE. The source draws its own floating image, and a
 * destination that reported a rectangle here would be describing a window it does not own. */
- (NSPoint)draggedImageLocation { return s_point; }
- (NSImage *)draggedImage { return nil; }

/* **THE DRAG'S PAYLOAD, AND IT IS READ ON DEMAND.** `-dataForType:` asks the source through `request_drag_data`, which is
 * what makes a drop's handler able to read the file list without the payload having been copied up front. */
- (NSPasteboard *)draggingPasteboard { return s_pasteboard; }

/* Nil: the source is another process, and no object here stands for it. Apple's own reader checks for an
 * `NSDraggingSession` here only when the drag is local, which this never is. */
- (id)draggingSource { return nil; }

- (NSInteger)draggingSequenceNumber { return s_sequence; }

- (void)slideDraggedImageTo:(NSPoint)screenPoint
{
	/* THE IMAGE IS NOT THIS PROCESS'S TO MOVE. Said here rather than silently ignored by omission, because a destination
	 * that calls this expects the drop to be marked where it asked. */
	(void)screenPoint;
}

- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination
{
	(void)dropDestination;
	return nil;
}

- (NSDraggingFormation)draggingFormation { return NSDraggingFormationNone; }
- (void)setDraggingFormation:(NSDraggingFormation)formation { (void)formation; }

- (NSInteger)numberOfValidItemsForDrop { return 1; }
- (void)setNumberOfValidItemsForDrop:(NSInteger)number { (void)number; }

@end

/* ==================================================================================================
 * THE QUEUE
 * ================================================================================================== */

@implementation AGExternalDrag

static void fn_queue(NSString *kind, int a, int b, id payload)
{
	if (s_pending == nil) {
		s_pending = [[NSMutableArray alloc] init];
	}
	[s_pending addObject:[NSArray arrayWithObjects:kind, [NSNumber numberWithInt:a], [NSNumber numberWithInt:b],
						  (payload != nil) ? payload : (id)[NSNull null], nil]];
}

/* ==================================================================================================
 * THE EIGHT DOORS
 * ================================================================================================== */

+ (void)cg_handleEnterWithWindow:(uint32_t)windowId
			       x:(int)x
			       y:(int)y
			       types:(NSArray *)types
			      mask:(uint32_t)mask
{
	NSWindow *window = fn_lookup_window(windowId);
	AGExternalDraggingInfo *info;
	NSView *view;

	/* **A WINDOW THIS APPLICATION DOES NOT HAVE IS NOT AN ERROR.** The id came off the compositor's window list, so it can
	 * name a window that closed between the motion and this call — and a client that logged that would log a race. */
	if (getenv("AGORA_DRAG_DIAG") != NULL) {
		fprintf(stderr, "  DIAG drag: destination enter, surface %u -> window %p, %d type(s)\n", windowId,
			(void *)window, (int)[types count]);
	}
	if (window == nil || [types count] == 0) {
		fn_clear_state();
		return;
	}
	view = [window cg_destinationViewAtPoint:NSMakePoint((CGFloat)x, (CGFloat)y) forDraggedTypes:types];
	if (view == nil) {
		/* No view registered for these types: the drag is over this window and nobody wants it. Remembering the window
		 * would make a later `-draggingExited:` name a view that never heard an enter. */
		fn_clear_state();
		return;
	}
	fn_clear_state();
	s_window = [window retain];
	s_view = [view retain];
	s_pasteboard = [[NSPasteboard cg_dragDestinationBoard] retain];
	[s_pasteboard cg_beginDragWithTypes:types];
	s_point = NSMakePoint((CGFloat)x, (CGFloat)y);
	s_mask = (NSDragOperation)mask;
	s_sequence++;

	info = [[[AGExternalDraggingInfo alloc] init] autorelease];
	s_operation = NSDragOperationNone;
	if ([view respondsToSelector:@selector(draggingEntered:)]) {
		s_operation = [view draggingEntered:info] & s_mask;
	}
	s_entered = YES;
	s_dropped = NO;
	if (getenv("AGORA_DRAG_DIAG") != NULL) {
		fprintf(stderr, "  DIAG drag: enter answered %lu of mask %lu\n", (unsigned long)s_operation,
			(unsigned long)s_mask);
	}
}

+ (void)cg_handleMotionToX:(int)x y:(int)y
{
	AGExternalDraggingInfo *info;

	/* **A MOTION QUEUED BEHIND A DROP IS NOT A MOTION.** The release's own position can arrive as a motion after the drop
	 * has been delivered — the hand did not move, the gesture ended — and a destination that answered it would be asked to
	 * re-decide a drop it has already taken, with the source's claim gone. */
	if (!s_entered || s_view == nil || s_dropped) {
		return;
	}
	s_point = NSMakePoint((CGFloat)x, (CGFloat)y);
	info = [[[AGExternalDraggingInfo alloc] init] autorelease];
	if ([s_view respondsToSelector:@selector(draggingUpdated:)]) {
		s_operation = [s_view draggingUpdated:info] & s_mask;
	}
	if (getenv("AGORA_DRAG_DIAG") != NULL) {
		fprintf(stderr, "  DIAG drag: motion (%d,%d) answered %lu\n", x, y, (unsigned long)s_operation);
	}
}

+ (void)cg_handleLeave
{
	AGExternalDraggingInfo *info;

	if (!s_entered || s_view == nil) {
		fn_clear_state();
		return;
	}
	info = [[[AGExternalDraggingInfo alloc] init] autorelease];
	if ([s_view respondsToSelector:@selector(draggingExited:)]) {
		/* **THE STATE IS STILL THE DRAG'S WHILE THIS RUNS**, which is why the clear comes after: a view asking its
		 * `draggingInfo` where the pointer was would otherwise be told about a gesture that had been forgotten. */
		[s_view draggingExited:info];
	}
	fn_clear_state();
}

+ (void)cg_handleDropAtX:(int)x y:(int)y
{
	AGExternalDraggingInfo *info;
	BOOL prepared = YES;
	BOOL performed = NO;

	s_point = NSMakePoint((CGFloat)x, (CGFloat)y);
	s_dropped = YES;
	if (getenv("AGORA_DRAG_DIAG") != NULL) {
		fprintf(stderr, "  DIAG drag: destination drop, view %p, operation %lu\n", (void *)s_view,
			(unsigned long)s_operation);
	}
	if (s_view != nil) {
		info = [[[AGExternalDraggingInfo alloc] init] autorelease];
		/* **A DROP NOBODY ACCEPTED IS NOT A DROP.** `-draggingEntered:` (or the last `-draggingUpdated:`) answered
		 * `NSDragOperationNone`, or the source permits nothing this view offered — either way the gesture is not the
		 * view's, and running its prepare would ask it to take a payload it has already declined.
		 *
		 * **AND THE FOUR DOORS THEN RUN IN APPKIT'S OWN ORDER**, each able to stop the sequence: a `prepare` that answers
		 * NO is a refusal that has already drawn its own feedback, and a `perform` that answers NO is a drop the view
		 * declined after looking at the payload. */
		if (s_entered && s_operation != NSDragOperationNone
		    && [s_view respondsToSelector:@selector(prepareForDragOperation:)]) {
			prepared = [s_view prepareForDragOperation:info];
		}
		if (s_entered && s_operation != NSDragOperationNone && prepared
		    && [s_view respondsToSelector:@selector(performDragOperation:)]) {
			performed = [s_view performDragOperation:info];
		}
		if (performed && [s_view respondsToSelector:@selector(concludeDragOperation:)]) {
			[s_view concludeDragOperation:info];
		}
		if ([s_view respondsToSelector:@selector(draggingEnded:)]) {
			[s_view draggingEnded:info];
		}
	}
	/* THE CLEAR COMES LAST, for the reason `-cg_handleLeave` gives — and there is no `-draggingExited:` after a drop,
	 * which is Apple's own sequence. */
	fn_clear_state();
}

+ (void)cg_handleFinished
{
	/* **THE SOURCE'S ANSWER, AND THE SOURCE NEEDS NOTHING FROM IT.** A local drag session ends on its own mouse-up
	 * (`NSDraggingSession`), and this event exists for a source that began a drag the compositor finished some other way —
	 * a destination that went away, a gesture the compositor cancelled. There is nothing here to undo. */
}

/* **THE SOURCE'S PAYLOAD DOOR.** The descriptor is a pipe whose other end the destination holds, so what is written here
 * is what arrives there; a type the pasteboard cannot serve writes nothing and the reader sees EOF, which is the honest
 * answer and the one `-dataForType:` already gives. */
+ (void)cg_handleDataRequestedForType:(NSString *)type fd:(int)fd
{
	NSDraggingSession *session = [NSDraggingSession cg_activeSession];
	NSData *data = (session != nil && type != nil) ? [[session cg_pasteboard] dataForType:type] : nil;

	if (getenv("AGORA_DRAG_DIAG") != NULL) {
		fprintf(stderr, "  DIAG drag: source asked for %s, session %p, %lu byte(s)\n",
			(type != nil) ? [type UTF8String] : "(nil)", (void *)session,
			(unsigned long)[data length]);
	}
	if (fd < 0) {
		return;
	}
	if (data != nil) {
		const char *bytes = (const char *)[data bytes];
		size_t length = [data length];
		size_t written = 0;

		while (written < length) {
			ssize_t n = write(fd, bytes + written, length - written);

			if (n <= 0) {
				break;
			}
			written += (size_t)n;
		}
	}
	close(fd);
}

/* **THE DESTINATION'S ANSWER HANDOFF.** It goes straight into the board's own waiting state — not through the queue —
 * because a reader is inside a bounded pump waiting for exactly this, and a queue would make it wait for a turn that
 * cannot come. */
+ (void)cg_handleDataForType:(NSString *)type fd:(int)fd
{
	if (s_pasteboard == nil) {
		close(fd);
		return;
	}
	(void)type;
	[s_pasteboard cg_remoteTakeFd:fd];
}

+ (void)cg_handleRefusalForType:(NSString *)type reason:(uint32_t)reason
{
	if (s_pasteboard == nil) {
		return;
	}
	(void)type;
	[s_pasteboard cg_remoteTakeRefusal:(int)reason];
}

+ (void)cg_setWindowLookup:(AGExternalDragWindowLookup)lookup
{
	s_lookup = lookup;
}

+ (BOOL)cg_isDragging
{
	return s_entered;
}

/* ==================================================================================================
 * THE QUEUE'S DRAIN, WHICH IS WHERE APPKIT IS ACTUALLY CALLED
 * ================================================================================================== */

+ (void)cg_processPendingEvents
{
	while ([s_pending count] > 0) {
		NSArray *entry = [[s_pending objectAtIndex:0] retain];
		NSString *kind = [entry objectAtIndex:0];
		int a = [[entry objectAtIndex:1] intValue];
		int b = [[entry objectAtIndex:2] intValue];
		id payload = [entry objectAtIndex:3];

		[s_pending removeObjectAtIndex:0];	/* BEFORE the call: a handler that posts another event must not be lost */
		if ([kind isEqualToString:@"enter"]) {
			[self cg_handleEnterWithWindow:(uint32_t)[[payload objectForKey:@"window"] unsignedIntValue]
						     x:[[payload objectForKey:@"x"] intValue]
						     y:[[payload objectForKey:@"y"] intValue]
						 types:[payload objectForKey:@"types"]
						mask:[[payload objectForKey:@"mask"] unsignedIntValue]];
		} else if ([kind isEqualToString:@"motion"]) {
			[self cg_handleMotionToX:a y:b];
		} else if ([kind isEqualToString:@"leave"]) {
			[self cg_handleLeave];
		} else if ([kind isEqualToString:@"drop"]) {
			[self cg_handleDropAtX:a y:b];
		}
		[entry release];
	}
}

/* ==================================================================================================
 * THE SEAM'S EIGHT CALLBACKS
 * ================================================================================================== */

static void fn_drag_enter(void *context, uint32_t window_id, int x, int y, const char *const *types, int count,
			  uint32_t source_mask)
{
	NSMutableArray *list = [NSMutableArray array];
	NSDictionary *entry;
	int i;

	(void)context;
	for (i = 0; i < count; i++) {
		NSString *type = (types[i] != NULL) ? [NSString stringWithUTF8String:types[i]] : nil;

		if (type != nil) {
			[list addObject:type];
		}
	}
	/* **THE FOUR THINGS AN ENTER NEEDS** travel together in the entry's payload slot: a window, a point, a vocabulary and
	 * what the source permits. The queue's other kinds need none of them, so the slot is where they go rather than four
	 * invented fields. */
	entry = [NSDictionary dictionaryWithObjectsAndKeys:
		 [NSNumber numberWithUnsignedInt:window_id], @"window",
		 [NSNumber numberWithInt:x], @"x",
		 [NSNumber numberWithInt:y], @"y",
		 list, @"types",
		 [NSNumber numberWithUnsignedInt:source_mask], @"mask",
		 nil];
	fn_queue(@"enter", 0, 0, entry);
}

static void fn_drag_motion(void *context, int x, int y)
{
	(void)context;
	fn_queue(@"motion", x, y, nil);
}

static void fn_drag_leave(void *context)
{
	(void)context;
	fn_queue(@"leave", 0, 0, nil);
}

static void fn_drag_drop(void *context, int x, int y)
{
	(void)context;
	fn_queue(@"drop", x, y, nil);
}

static void fn_drag_finished(void *context)
{
	(void)context;
	[AGExternalDrag cg_handleFinished];
}

static void fn_drag_data_requested(void *context, const char *mime_type, int fd)
{
	NSString *type = (mime_type != NULL) ? [NSString stringWithUTF8String:mime_type] : nil;

	(void)context;
	[AGExternalDrag cg_handleDataRequestedForType:type fd:fd];
}

static void fn_drag_data(void *context, const char *mime_type, int fd)
{
	NSString *type = (mime_type != NULL) ? [NSString stringWithUTF8String:mime_type] : nil;

	(void)context;
	[AGExternalDrag cg_handleDataForType:type fd:fd];
}

static void fn_drag_refused(void *context, const char *mime_type, uint32_t reason)
{
	NSString *type = (mime_type != NULL) ? [NSString stringWithUTF8String:mime_type] : nil;

	(void)context;
	[AGExternalDrag cg_handleRefusalForType:type reason:reason];
}

+ (void)cg_install
{
	static AGDragHandlers handlers = {
		NULL,
		fn_drag_enter,
		fn_drag_motion,
		fn_drag_leave,
		fn_drag_drop,
		fn_drag_finished,
		fn_drag_data_requested,
		fn_drag_data,
		fn_drag_refused,
	};
	static BOOL installed = NO;
	AGWindowServer *server;

	if (installed) {
		return;
	}
	server = AGWindowServerShared();
	if (server == NULL) {
		return;	/* no compositor: nothing to hear, and this is not an error in a headless probe */
	}
	AGWindowServerSetDragHandlers(server, &handlers);
	installed = YES;
}

@end
