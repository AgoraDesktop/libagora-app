/*
 * drag_session — the in-process drag: the source, the destination, the masks and the image.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **EVERY DOOR HERE IS ASKED WHERE IT LIVES.** The source begins a session with
 * `-beginDraggingSessionWithItems:event:source:` and the legacy `-dragImage:...`; the application's own dispatch
 * (`-[NSWindow sendEvent:]`) drives the motions and the release; the destination answers the protocol and records the
 * `NSDraggingInfo` it was handed; and the source's ended callback carries the operation the drop negotiated. Two
 * windows are used because the point of the session is a drag that crosses one — the destination search is by SCREEN
 * point, not by event routing.
 *
 * **THE WINDOWS ARE REGISTERED WITH THE APPLICATION RATHER THAN ORDERED IN.** No compositor is needed for any of
 * this: the search falls back to the application's own window registry when there is no connection, which is the
 * same geometry a running application has, minus the glass. The image is therefore composed and measurable (a
 * destination reads it through `-draggedImage`) while `-cg_draggingWindow` is nil — the floating window exists only
 * where a compositor does, and `drag_session_seam` is the probe that asks about it there.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

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
	return fabs(a - b) < 0.05;
}

/* THE PRIVATE REGISTRATION DOOR, the same one `+windowNumberAtPoint:` reads. Declared here because an offscreen
 * probe's windows are never ordered in and therefore never enter the registry by the ordinary path. */
@interface NSApplication (APPKITDragProbe)
- (void)cg_addWindow:(NSWindow *)window;
- (void)cg_removeWindow:(NSWindow *)window;
@end

static NSEvent *mouse(int type, NSPoint where, NSUInteger flags)
{
	return [NSEvent mouseEventWithType:type location:where modifierFlags:flags
				 timestamp:0.0 windowNumber:0 context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

static NSImage *plate(CGFloat width, CGFloat height)
{
	/* A SIZE IS WHAT THE SESSION READS AND COMPOSES, so the picture itself is deliberately empty: the arithmetic
	 * under test is the union of the items' frames, not the pixels inside them. */
	return [[[NSImage alloc] initWithSize:NSMakeSize(width, height)] autorelease];
}

/* ---- THE DESTINATION, WHICH RECORDS EVERY CALLBACK -------------------------------------------- */

@interface AGDragDestination : NSView <NSDraggingDestination>
{
@public
	NSDragOperation answer;
	NSDragOperation modifierAnswer;
	int entered, updated, exited, ended, prepared, performed, concluded;
	NSPoint enteredLocation;
	NSPoint lastLocation;
	NSInteger sequence;
	NSSize imageSize;
	id source;
	NSString *pasteboardName;
	NSWindow *destinationWindow;
	NSPasteboard *pasteboard;
}
@end

@implementation AGDragDestination
- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		answer = NSDragOperationMove;
	}
	return self;
}
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	entered++;
	enteredLocation = [sender draggingLocation];
	lastLocation = enteredLocation;
	sequence = [sender draggingSequenceNumber];
	imageSize = [[sender draggedImage] size];
	source = [sender draggingSource];
	pasteboard = [sender draggingPasteboard];
	pasteboardName = [pasteboard name];
	destinationWindow = [sender draggingDestinationWindow];
	return answer;
}
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
	updated++;
	lastLocation = [sender draggingLocation];
	return answer;
}
- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	(void)sender;
	exited++;
}
- (void)draggingEnded:(id <NSDraggingInfo>)sender
{
	(void)sender;
	ended++;
}
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
	prepared++;
	return YES;
}
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
	performed++;
	return answer != NSDragOperationNone;
}
- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
	(void)sender;
	concluded++;
}
@end

/* ---- THE SOURCE ------------------------------------------------------------------------------- */

@interface AGDragSource : NSObject <NSDraggingSource>
{
@public
	int began, moved, finished;
	NSPoint beganAt;
	NSPoint movedTo;
	NSPoint endedAt;
	NSDragOperation endOperation;
	NSDragOperation mask;
	BOOL ignoreModifiers;
}
@end

@implementation AGDragSource
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		mask = NSDragOperationEvery;
	}
	return self;
}
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	(void)isLocal;
	return mask;
}
- (BOOL)ignoreModifierKeysWhileDragging { return ignoreModifiers; }
- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint
{
	(void)session;
	began++;
	beganAt = screenPoint;
}
- (void)draggingSession:(NSDraggingSession *)session movedToPoint:(NSPoint)screenPoint
{
	(void)session;
	moved++;
	movedTo = screenPoint;
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint
	      operation:(NSDragOperation)operation
{
	(void)session;
	finished++;
	endedAt = screenPoint;
	endOperation = operation;
}
@end

/* ---- THE FIXTURE ------------------------------------------------------------------------------ */

struct probe {
	NSWindow *sourceWindow;
	NSWindow *destinationWindow;
	NSView *sourceView;
	AGDragDestination *destination;
	AGDragSource *source;
	NSDraggingItem *item;
};

static void make_probe(struct probe *probe)
{
	NSDragOperation unused;

	probe->sourceWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 200.0)
							   styleMask:NSBorderlessWindowMask
							     backing:NSBackingStoreBuffered defer:NO];
	probe->destinationWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(400.0, 0.0, 300.0, 200.0)
								styleMask:NSBorderlessWindowMask
								  backing:NSBackingStoreBuffered defer:NO];
	probe->sourceView = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
	probe->destination = [[AGDragDestination alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
	probe->source = [[AGDragSource alloc] init];
	probe->item = [[NSDraggingItem alloc] initWithPasteboardWriter:nil];
	[probe->sourceWindow setContentView:probe->sourceView];
	[probe->destinationWindow setContentView:probe->destination];
	[probe->destination registerForDraggedTypes:[NSArray arrayWithObject:@"AgoraDragType"]];
	[probe->item setDraggingFrame:NSMakeRect(10.0, 10.0, 40.0, 20.0) contents:plate(40.0, 20.0)];
	(void)unused;
}

static void release_probe(struct probe *probe)
{
	[probe->item release];
	[probe->source release];
	[probe->destination release];
	[probe->sourceView release];
	[probe->sourceWindow release];
	[probe->destinationWindow release];
}

static void register_probe_windows(struct probe *probe)
{
	NSApplication *app = [NSApplication sharedApplication];

	/* SOURCE FIRST, DESTINATION SECOND: `-cg_addWindow:` inserts at the front, so the destination is in front of the
	 * source — which is the order a drag crossing onto it needs. */
	[app cg_addWindow:probe->sourceWindow];
	[app cg_addWindow:probe->destinationWindow];
}

static void unregister_probe_windows(struct probe *probe)
{
	NSApplication *app = [NSApplication sharedApplication];

	[app cg_removeWindow:probe->sourceWindow];
	[app cg_removeWindow:probe->destinationWindow];
}

static void put_type(NSString *type)
{
	NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];

	[pasteboard declareTypes:[NSArray arrayWithObject:type] owner:nil];
	[pasteboard setString:@"payload" forType:type];
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	struct probe probe;
	NSDraggingSession *session;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];
	make_probe(&probe);
	register_probe_windows(&probe);

	/* 1. THE SOURCE BEGINS A SESSION, AND THE SESSION KNOWS WHERE IT STARTED. */
	put_type(@"AgoraDragType");
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);

		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
	}
	check(session != nil && [NSDraggingSession cg_activeSession] == session,
	      "beginDraggingSessionWithItems: returns the running session");
	check([session draggingState] == NSDragStateRunning, "and its state is Running");
	check(near([session draggingLocation].x, 20.0) && near([session draggingLocation].y, 20.0),
	      "the initial location is the event's, in screen coordinates");
	check([session sourceOperationMask] == NSDragOperationEvery,
	      "the source's mask is asked through the source protocol");
	check([[[session draggingPasteboard] name] isEqual:NSDragPboard],
	      "the modern door uses NSDragPboard when no pasteboard is handed in");
	check([session draggingSequenceNumber] > 0, "the session has a sequence number");
	check(probe.source->began == 1 && near(probe.source->beganAt.x, 20.0),
	      "the source is told the drag began, at the same point");

	/* 2. THE SOURCE'S OWN WINDOW IS NOT A DESTINATION, SO NOTHING IS ASKED YET. */
	check(probe.destination->entered == 0, "a drag over a view that registered nothing enters nothing");

	/* 3. A MOTION INTO THE DESTINATION WINDOW FINDS THE DESTINATION BY SCREEN POINT. */
	{
		NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), 0);

		[probe.sourceWindow sendEvent:drag];
	}
	check(probe.destination->entered == 1, "crossing into the other window sends draggingEntered:");
	check(near(probe.destination->enteredLocation.x, 20.0)
	      && near(probe.destination->enteredLocation.y, 100.0),
	      "and the info's location is in the DESTINATION window's coordinates");
	check(probe.destination->destinationWindow == probe.destinationWindow,
	      "the info names the destination window");
	check(probe.destination->pasteboardName != nil
	      && [probe.destination->pasteboardName isEqual:NSDragPboard],
	      "and the pasteboard the source wrote");
	check(probe.destination->source == probe.source, "and the source object");
	check(probe.destination->sequence == [session draggingSequenceNumber],
	      "and the session's sequence number");
	check(probe.destination->imageSize.width > 0.0 && probe.destination->imageSize.height > 0.0,
	      "and a composed drag image");
	check(probe.source->moved == 1 && near(probe.source->movedTo.x, 420.0),
	      "the source is told the pointer moved, in screen coordinates");
	check([session currentOperationMask] == NSDragOperationMove,
	      "the destination's Move, intersected with the source's Every, is the current operation");

	/* 4. A SECOND MOTION UPDATES RATHER THAN ENTERING AGAIN. */
	{
		NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(430.0, 110.0), 0);

		[probe.sourceWindow sendEvent:drag];
	}
	check(probe.destination->entered == 1 && probe.destination->updated == 1,
	      "moving inside the destination sends draggingUpdated:, not a second entered");
	check(near(probe.destination->lastLocation.x, 30.0) && near(probe.destination->lastLocation.y, 110.0),
	      "and the updated location follows the pointer");

	/* 5. THE RELEASE PERFORMS THE DROP AND TELLS BOTH SIDES THE NEGOTIATED OPERATION. */
	{
		NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(430.0, 110.0), 0);

		[probe.sourceWindow sendEvent:up];
	}
	check(probe.destination->prepared == 1 && probe.destination->performed == 1,
	      "the release prepares and performs the drop");
	check(probe.destination->concluded == 1, "and concludes it after the destination said YES");
	check(probe.destination->ended == 1 && probe.destination->exited == 0,
	      "draggingEnded: is sent, and not draggingExited:, after a drop");
	check(probe.source->finished == 1 && probe.source->endOperation == NSDragOperationMove,
	      "the source is told the drag ended with Move");
	check([session draggingState] == NSDragStateDone, "and the session's state is Done");
	check([NSDraggingSession cg_activeSession] == nil, "and no session is active");
	check([session cg_draggingWindow] == nil || [[session cg_draggingWindow] ignoresMouseEvents],
	      "the drag image window never takes the pointer");

	/* 6. A DESTINATION THAT SAYS NO IS LEFT WITH NO OPERATION, AND THE SOURCE HEARS None. */
	probe.destination->answer = NSDragOperationNone;
	probe.destination->entered = probe.destination->updated = probe.destination->exited = 0;
	probe.destination->prepared = probe.destination->performed = probe.destination->concluded = 0;
	probe.destination->ended = 0;
	probe.source->finished = 0;
	probe.source->endOperation = NSDragOperationEvery;
	put_type(@"AgoraDragType");
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
		NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), 0);
		NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(420.0, 100.0), 0);

		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
		[probe.sourceWindow sendEvent:drag];
		check(probe.destination->entered == 1 && [session currentOperationMask] == NSDragOperationNone,
		      "a destination answering None makes the current operation None");
		[probe.sourceWindow sendEvent:up];
	}
	check(probe.destination->prepared == 0 && probe.destination->performed == 0,
	      "and a refused drop is never prepared or performed");
	check(probe.destination->ended == 1, "the destination still hears that the drag ended");
	check(probe.source->finished == 1 && probe.source->endOperation == NSDragOperationNone,
	      "and the source hears None");

	/* 7. AN ALT-DRAG TURNS THE DESTINATION'S MOVE INTO A COPY — the modifier rule, with Every as the source mask. */
	probe.destination->answer = NSDragOperationMove;
	probe.destination->entered = probe.destination->updated = probe.destination->exited = 0;
	probe.destination->prepared = probe.destination->performed = probe.destination->concluded = 0;
	probe.destination->ended = 0;
	probe.source->finished = 0;
	put_type(@"AgoraDragType");
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
		NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), NSAlternateKeyMask);
		NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(420.0, 100.0), NSAlternateKeyMask);

		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
		[probe.sourceWindow sendEvent:drag];
		check([session currentOperationMask] == NSDragOperationCopy,
		      "Option turns a permitted Move into Copy");
		[probe.sourceWindow sendEvent:up];
	}
	check(probe.source->endOperation == NSDragOperationCopy, "and the source hears Copy");
	probe.source->ignoreModifiers = YES;
	put_type(@"AgoraDragType");
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
		NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), NSAlternateKeyMask);
		NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(420.0, 100.0), NSAlternateKeyMask);

		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
		[probe.sourceWindow sendEvent:drag];
		check([session currentOperationMask] == NSDragOperationMove,
		      "a source that ignores modifiers keeps the destination's Move");
		[probe.sourceWindow sendEvent:up];
	}
	probe.source->ignoreModifiers = NO;

	/* 8. LEAVING THE DESTINATION SENDS draggingExited:, AND AN ESCAPE CANCELS THE DRAG. */
	probe.destination->entered = probe.destination->updated = probe.destination->exited = 0;
	probe.destination->prepared = probe.destination->performed = probe.destination->concluded = 0;
	probe.destination->ended = 0;
	probe.source->finished = 0;
	probe.source->endOperation = NSDragOperationEvery;
	put_type(@"AgoraDragType");
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
		NSEvent *in = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), 0);
		NSEvent *out = mouse(NSLeftMouseDragged, NSMakePoint(320.0, 100.0), 0);
		NSEvent *escape = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:0
						  timestamp:0.0 windowNumber:0 context:nil
						  characters:@"\x1b" charactersIgnoringModifiers:@"\x1b"
						  isARepeat:NO keyCode:53];

		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
		[probe.sourceWindow sendEvent:in];
		[probe.sourceWindow sendEvent:out];
		check(probe.destination->exited == 1 && [session currentOperationMask] == NSDragOperationNone,
		      "leaving the destination sends draggingExited: and clears the operation");
		[probe.sourceWindow sendEvent:escape];
	}
	check(probe.source->finished == 1 && probe.source->endOperation == NSDragOperationNone,
	      "Escape ends the drag with no operation");
	check(probe.destination->performed == 0 && probe.destination->concluded == 0,
	      "and a cancelled drag performs nothing");
	check([NSDraggingSession cg_activeSession] == nil, "the cancelled session is no longer active");

	/* 9. AN UNREGISTERED CHILD IS CAUGHT BY ITS REGISTERED PARENT, WHICH IS THE SOURCE-LIST SHAPE. */
	{
		NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];

		[probe.destination addSubview:child];
		[child release];
	}
	probe.destination->entered = probe.destination->updated = probe.destination->exited = 0;
	probe.destination->prepared = probe.destination->performed = probe.destination->concluded = 0;
	probe.destination->ended = 0;
	probe.source->finished = 0;
	put_type(@"AgoraDragType");
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
		NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), 0);
		NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(420.0, 100.0), 0);

		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
		[probe.sourceWindow sendEvent:drag];
		check(probe.destination->entered == 1,
		      "a drag over an unregistered child climbs to the registered parent");
		[probe.sourceWindow sendEvent:up];
	}

	/* 10. THE REGISTRATION IS A TYPE FILTER, NOT A VIEW FILTER. */
	probe.destination->entered = probe.destination->updated = probe.destination->exited = 0;
	probe.destination->prepared = probe.destination->performed = probe.destination->concluded = 0;
	probe.destination->ended = 0;
	probe.source->finished = 0;
	put_type(@"AgoraOtherType");
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
		NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), 0);
		NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(420.0, 100.0), 0);

		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
		[probe.sourceWindow sendEvent:drag];
		check(probe.destination->entered == 0,
		      "a type the destination did not register reaches nothing");
		[probe.sourceWindow sendEvent:up];
	}
	check(probe.source->endOperation == NSDragOperationNone, "and the drag ends with None");

	/* 11. TWO ITEMS COMPOSE ONE IMAGE THE SIZE OF THEIR UNION — the formation this slice draws. */
	{
		NSDraggingItem *second = [[NSDraggingItem alloc] initWithPasteboardWriter:nil];
		NSArray *items;

		[second setDraggingFrame:NSMakeRect(20.0, 5.0, 10.0, 10.0)
				contents:plate(10.0, 10.0)];
		items = [NSArray arrayWithObjects:probe.item, second, nil];
		probe.destination->entered = probe.destination->updated = probe.destination->exited = 0;
		probe.destination->prepared = probe.destination->performed = probe.destination->concluded = 0;
		probe.destination->ended = 0;
		probe.source->finished = 0;
		put_type(@"AgoraDragType");
		{
			NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
			NSEvent *drag = mouse(NSLeftMouseDragged, NSMakePoint(420.0, 100.0), 0);
			NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(420.0, 100.0), 0);

			session = [probe.sourceView beginDraggingSessionWithItems:items event:down
									  source:probe.source];
			[probe.sourceWindow sendEvent:drag];
			check(near(probe.destination->imageSize.width, 40.0)
			      && near(probe.destination->imageSize.height, 25.0),
			      "two items at (10,10,40,20) and (20,5,10,10) compose a 40x25 image");
			[probe.sourceWindow sendEvent:up];
		}
		[second release];
	}

	/* 12. THE LEGACY DOOR BEGINS THE SAME SESSION, WITH THE PASTEBOARD IT WAS HANDED. */
	{
		NSPasteboard *custom = [NSPasteboard pasteboardWithUniqueName];
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);

		[custom declareTypes:[NSArray arrayWithObject:@"AgoraDragType"] owner:nil];
		[custom setString:@"legacy" forType:@"AgoraDragType"];
		[probe.sourceView dragImage:plate(30.0, 30.0)
					 at:NSMakePoint(10.0, 10.0)
				     offset:NSMakeSize(5.0, 5.0)
				      event:down
				 pasteboard:custom
				     source:probe.source
				  slideBack:YES];
		session = [NSDraggingSession cg_activeSession];
		check(session != nil, "dragImage:at:offset:event:pasteboard:source:slideBack: begins a session");
		check([[[session draggingPasteboard] name] isEqual:[custom name]],
		      "the legacy door keeps the pasteboard it was given");
		{
			NSEvent *up = mouse(NSLeftMouseUp, NSMakePoint(20.0, 20.0), 0);

			[probe.sourceWindow sendEvent:up];
		}
		check([NSDraggingSession cg_activeSession] == nil, "and the release ends it");
	}

	/* 13. A WINDOW'S REGISTRATION IS ITS CONTENT VIEW'S — Apple's contract, and the search's. */
	{
		NSWindow *third = [[NSWindow alloc] initWithContentRect:NSMakeRect(800.0, 0.0, 200.0, 200.0)
							       styleMask:NSBorderlessWindowMask
								 backing:NSBackingStoreBuffered defer:NO];
		AGDragDestination *thirdView = [[AGDragDestination alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
		NSEvent *down;
		NSEvent *drag;
		NSEvent *up;

		[third setContentView:thirdView];
		[third registerForDraggedTypes:[NSArray arrayWithObject:@"AgoraWindowType"]];
		check([[thirdView cg_registeredDraggedTypes] containsObject:@"AgoraWindowType"],
		      "registerForDraggedTypes: on a window reaches its content view");
		[[NSApplication sharedApplication] cg_addWindow:third];
		put_type(@"AgoraWindowType");
		down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);
		drag = mouse(NSLeftMouseDragged, NSMakePoint(820.0, 100.0), 0);
		up = mouse(NSLeftMouseUp, NSMakePoint(820.0, 100.0), 0);
		session = [probe.sourceView beginDraggingSessionWithItems:[NSArray arrayWithObject:probe.item]
								  event:down source:probe.source];
		[probe.sourceWindow sendEvent:drag];
		check(thirdView->entered == 1, "and a drag finds a window-registered destination");
		[probe.sourceWindow sendEvent:up];
		[[NSApplication sharedApplication] cg_removeWindow:third];
		[thirdView release];
		[third release];
	}

	/* 14. THE WINDOW'S LEGACY DOOR IS THE CONTENT VIEW'S, AND BEGINS THE SAME SESSION. */
	{
		NSEvent *down = mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0), 0);

		put_type(@"AgoraDragType");
		[probe.sourceWindow dragImage:plate(20.0, 20.0) at:NSMakePoint(20.0, 20.0)
				     offset:NSZeroSize event:down pasteboard:nil source:probe.source slideBack:YES];
		session = [NSDraggingSession cg_activeSession];
		check(session != nil, "NSWindow's dragImage: forwards to its content view");
		[probe.sourceWindow sendEvent:mouse(NSLeftMouseUp, NSMakePoint(20.0, 20.0), 0)];
	}

	unregister_probe_windows(&probe);
	release_probe(&probe);
	printf("drag_session: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
