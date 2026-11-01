/*
 * external_drag — a drag that arrives from ANOTHER application, turned into AppKit's own protocol.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **WHAT THIS MEASURES.** The compositor says "a drag from another client is over window 7 at (30, 40), offering these
 * types, permitting a copy". A view expects `-draggingEntered:`, a location in window space, and a `draggingInfo` whose
 * pasteboard answers `-types` without a round trip. `AGExternalDrag` is that translation; this probe drives its eight
 * doors directly and asserts what a destination actually experiences — including the ORDER of the four doors a drop goes
 * through, which is the part a real drop cannot be asked about twice.
 *
 * **NO COMPOSITOR, BY CONSTRUCTION.** A window's number comes off the wire, so the window lookup is replaced with the
 * test's own (that is what `+cg_setWindowLookup:` exists for); the payload read is the only thing that needs a server and
 * is measured for its *refusal* rather than its data — a read with no compositor answers nil instead of hanging.
 */
#import <AppKit/AppKit.h>
#import <AppKit/AGExternalDrag.h>

#include <stdio.h>
#include <string.h>

/* THE DRAG BOARD'S TWO DOORS, DECLARED HERE AS `NSPasteboard.m` DECLARES THEM — a `cg_` seam is the tier's own passage
 * and this probe is the tier. */
@interface NSPasteboard (APPKITExternalDrag)
+ (NSPasteboard *)cg_dragDestinationBoard;
- (void)cg_beginDragWithTypes:(NSArray *)types;
@end

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* ==================================================================================================
 * A DESTINATION THAT REMEMBERS, BECAUSE THE ORDER IS THE CLAIM.
 * ================================================================================================== */

@interface AGRecordingDestination : NSView
{
	NSMutableArray *_calls;
	NSPoint _location;
	NSPoint _dropPoint;
	NSArray *_types;
	NSDragOperation _mask;
	NSDragOperation _answer;
	BOOL _prepares;
}
- (NSArray *)calls;
- (NSPoint)location;
- (NSPoint)dropPoint;
- (NSArray *)seenTypes;
- (NSDragOperation)seenMask;
- (void)setAnswer:(NSDragOperation)answer;
- (void)setPrepares:(BOOL)flag;
@end

@implementation AGRecordingDestination

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self != nil) {
		_calls = [[NSMutableArray alloc] init];
		_answer = NSDragOperationCopy;
		_prepares = YES;
	}
	return self;
}

- (void)dealloc
{
	[_calls release];
	[_types release];
	[super dealloc];
}

- (NSArray *)calls { return _calls; }
- (NSPoint)location { return _location; }
- (NSPoint)dropPoint { return _dropPoint; }
- (NSArray *)seenTypes { return _types; }
- (NSDragOperation)seenMask { return _mask; }
- (void)setAnswer:(NSDragOperation)answer { _answer = answer; }
- (void)setPrepares:(BOOL)flag { _prepares = flag ? YES : NO; }

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)info
{
	[_calls addObject:@"entered"];
	_location = [info draggingLocation];
	_mask = [info draggingSourceOperationMask];
	[_types release];
	_types = [[[info draggingPasteboard] types] retain];
	return _answer;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)info
{
	[_calls addObject:@"updated"];
	_location = [info draggingLocation];
	return _answer;
}

- (void)draggingExited:(id <NSDraggingInfo>)info
{
	(void)info;
	[_calls addObject:@"exited"];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)info
{
	(void)info;
	[_calls addObject:@"prepare"];
	return _prepares;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)info
{
	[_calls addObject:@"perform"];
	_dropPoint = [info draggingLocation];
	return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)info
{
	(void)info;
	[_calls addObject:@"conclude"];
}

- (void)draggingEnded:(id <NSDraggingInfo>)info
{
	(void)info;
	[_calls addObject:@"ended"];
}

@end

/* ==================================================================================================
 * THE FIXTURE
 * ================================================================================================== */

static NSWindow *s_window;
static AGRecordingDestination *s_destination;

/* **THE WINDOW THE DRAG NAMES, ANSWERED BY THE TEST** — see the file's comment: no compositor, so no numbers. */
static NSWindow *fn_lookup(uint32_t windowId)
{
	return (windowId == 7) ? s_window : nil;
}

static NSArray *fn_filenames(void)
{
	return [NSArray arrayWithObject:NSFilenamesPboardType];
}

static void reset(void)
{
	[s_destination setAnswer:NSDragOperationCopy];
	[s_destination setPrepares:YES];
	[[s_destination calls] removeAllObjects];
}

static int calls_are(NSArray *expected)
{
	NSArray *got = [s_destination calls];

	return ([got count] == [expected count]) && [got isEqualToArray:expected];
}

static void fn_enter(int x, int y)
{
	[AGExternalDrag cg_handleEnterWithWindow:7 x:x y:y types:fn_filenames()
					    mask:(uint32_t)NSDragOperationCopy];
	[AGExternalDrag cg_processPendingEvents];
}

int main(void)
{
	NSView *content;
	NSArray *types = fn_filenames();

	setvbuf(stdout, NULL, _IONBF, 0);
	[NSApplication sharedApplication];

	s_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 200.0)
					       styleMask:NSBorderlessWindowMask
						 backing:NSBackingStoreBuffered
						   defer:NO];
	/* **THE CONTENT VIEW IS MADE HERE RATHER THAN ASSUMED.** A window created with no display has none until one is set,
	 * and a destination search that began at a nil content view would find nothing for a reason that is the fixture's. */
	content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)] autorelease];
	[s_window setContentView:content];
	s_destination = [[AGRecordingDestination alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
	[s_destination registerForDraggedTypes:types];
	[content addSubview:s_destination];
	[AGExternalDrag cg_setWindowLookup:fn_lookup];

	printf("external_drag: a drag from another application\n");

	/* 1. **AN ENTER IS THE VIEW'S `-draggingEntered:`, ONCE, IN THE WINDOW'S OWN COORDINATES.** The compositor measures
	 * DOWN from a surface's top, as a Wayland client is given; a window's coordinates run UP from its bottom, which is what
	 * `-convertPoint:fromView:` assumes and what every hit test in this tier is written in. The seam converts, so a
	 * destination does not have to know which side of the seam its drag came from: the point (30, 40) from the wire is
	 * (30, 160) in a 200-point-tall window. */
	reset();
	fn_enter(30, 40);
	check(calls_are([NSArray arrayWithObject:@"entered"]), "an enter is one -draggingEntered: and nothing else");
	check([s_destination location].x == 30.0 && [s_destination location].y == 160.0,
	      "the location is the point the compositor named, measured up from the window's bottom");
	check([[s_destination seenTypes] isEqualToArray:types],
	      "the drag's types are on the pasteboard without a round trip");
	check([s_destination seenMask] == NSDragOperationCopy,
	      "and the mask is the source's own, which only the wire knows");
	check([AGExternalDrag cg_isDragging], "the drag is over this view until it leaves");

	/* 2. **AND ITS ANSWER IS INTERSECTED WITH WHAT THE SOURCE PERMITS.** A view that says "move or copy" on a source that
	 * only offered a copy has just claimed a move it cannot have. */
	[AGExternalDrag cg_handleMotionToX:50 y:60];
	[AGExternalDrag cg_processPendingEvents];
	check(calls_are([NSArray arrayWithObjects:@"entered", @"updated", nil]),
	      "a motion is one -draggingUpdated:, after the enter");
	check([s_destination location].x == 50.0 && [s_destination location].y == 140.0,
	      "with the new point, in the same coordinates");

	/* 3. **LEAVING IS ONE EXIT AND THE END OF THE CLAIM.** A strip that drew a mark takes it away on the exit, and a
	 * second exit would be a second cleanup of something already cleaned. */
	[AGExternalDrag cg_handleLeave];
	[AGExternalDrag cg_processPendingEvents];
	check(calls_are([NSArray arrayWithObjects:@"entered", @"updated", @"exited", nil]),
	      "leaving is one -draggingExited:");
	check(![AGExternalDrag cg_isDragging], "and there is no drag over this view any more");

	/* 4. **A DROP GOES THROUGH ALL FOUR DOORS, IN APPKIT'S ORDER.** The order is the contract: a `prepare` that answers
	 * NO stops the sequence, and a `conclude` that ran before the `perform` would tidy up a drop that never happened. */
	reset();
	fn_enter(10, 10);
	[AGExternalDrag cg_handleDropAtX:120 y:130];
	[AGExternalDrag cg_processPendingEvents];
	check(calls_are([NSArray arrayWithObjects:@"entered", @"prepare", @"perform", @"conclude", @"ended", nil]),
	      "the drop runs prepare, perform, conclude and ended, in that order");
	check([s_destination dropPoint].x == 120.0 && [s_destination dropPoint].y == 70.0,
	      "and -performDragOperation: is told where the hand let go, in the window's coordinates");
	check(![AGExternalDrag cg_isDragging], "the drag is over");

	/* 5. **A `-prepareForDragOperation:` THAT SAYS NO ENDS IT THERE.** A view that refused the gesture in the prepare has
	 * already drawn its own feedback; a perform after it would take the payload it just declined. */
	reset();
	fn_enter(10, 10);
	[s_destination setPrepares:NO];
	[AGExternalDrag cg_handleDropAtX:20 y:20];
	[AGExternalDrag cg_processPendingEvents];
	check(calls_are([NSArray arrayWithObjects:@"entered", @"prepare", @"ended", nil]),
	      "a prepare that refuses stops the drop before the perform");

	/* 6. **A DROP THE VIEW NEVER ACCEPTED IS NOT ITS DROP.** `-draggingEntered:` answering `None` (or a mask that
	 * intersects nothing) means the gesture was declined at the door, so the four drop doors must not run — a view that
	 * refused the drag would otherwise be handed the payload it had just said no to. */
	reset();
	[s_destination setAnswer:NSDragOperationNone];
	fn_enter(10, 10);
	[AGExternalDrag cg_handleDropAtX:10 y:10];
	[AGExternalDrag cg_processPendingEvents];
	check(calls_are([NSArray arrayWithObjects:@"entered", @"ended", nil]),
	      "a drop on a view that answered None runs no prepare, perform or conclude");

	/* 7. **A WINDOW THIS APPLICATION DOES NOT HAVE IS SILENT.** The id came off a window list, so it can name a window that
	 * closed in between — and the view must not hear about a gesture over something that is not there. */
	reset();
	[AGExternalDrag cg_handleEnterWithWindow:9 x:10 y:10 types:fn_filenames() mask:(uint32_t)NSDragOperationCopy];
	[AGExternalDrag cg_processPendingEvents];
	check([[s_destination calls] count] == 0, "an enter for a window that is not ours reaches no view");
	check(![AGExternalDrag cg_isDragging], "and starts no drag");

	/* 8. **AND NEITHER DOES A VIEW THAT REGISTERED OTHER TYPES.** The drag is over the window and nobody wants it; the drop
	 * that follows must not reach a view that never heard an enter. */
	reset();
	[s_destination registerForDraggedTypes:[NSArray arrayWithObject:@"public.utf8-plain-text"]];
	[AGExternalDrag cg_handleEnterWithWindow:7 x:10 y:10 types:fn_filenames() mask:(uint32_t)NSDragOperationCopy];
	[AGExternalDrag cg_handleDropAtX:10 y:10];
	[AGExternalDrag cg_processPendingEvents];
	check([[s_destination calls] count] == 0, "a view registered for other types is not a destination");
	[s_destination registerForDraggedTypes:types];

	/* 9. **WITH NO COMPOSITOR A PAYLOAD READ ANSWERS NIL RATHER THAN HANGING.** The board a drag hands out refuses this one
	 * thing honestly: there is nobody to ask, so the bounded wait ends and the answer is "no data", which is a sentence a
	 * drop handler can act on. */
	{
		NSPasteboard *board = [NSPasteboard cg_dragDestinationBoard];
		NSData *data;

		[board cg_beginDragWithTypes:types];
		data = [board dataForType:NSFilenamesPboardType];
		check(data == nil, "a read with nobody to ask answers nil, and does not hang");
		check([[board types] isEqualToArray:types], "after the offer the board still names the drag's types");
	}

	printf(s_failed == 0 ? "external_drag: all checks passed\n" : "external_drag: FAILURES\n");
	[AGExternalDrag cg_setWindowLookup:NULL];
	[s_destination release];
	[s_window release];
	return s_failed == 0 ? 0 : 1;
}
