/*
 * drag_seam — the drag IMAGE on the glass, against Agora's own headless window server.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE OFFSCREEN PROBE MEASURES THE SESSION; THIS ONE MEASURES THE WINDOW.** A borderless, transparent, floating
 * window is what a client-side compositor gives a drag image, and none of that can be asked without a connection.
 * The window is made by `NSDragging.m` when the source begins a drag, moves with the pointer, and is ordered out
 * when the drag ends. Exit 77 means SKIP (no server on this machine).
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

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

@interface NSWindow (APPKITDragSeamProbe)
+ (BOOL)cg_hasWindowServer;
@end

@interface AGSeamView : NSView
@end
@implementation AGSeamView
@end

/* **A FLIPPED VIEW, WHICH IS THE SHAPE AN ICON GRID HAS.** Its y grows downward, so a point in it and the same point in
 * the window's space differ by a mirror — which is exactly the difference that used to be lost. */
@interface AGFlippedView : AGSeamView
@end
@implementation AGFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface AGSeamSource : NSObject <NSDraggingSource>
@end
@implementation AGSeamSource
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	(void)isLocal;
	return NSDragOperationEvery;
}
@end

static NSEvent *mouse(NSEventType type, NSPoint where)
{
	return [NSEvent mouseEventWithType:type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:0 context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	AGSeamView *view;
	AGSeamSource *source;
	NSImage *image;
	NSDraggingItem *item;
	NSDraggingSession *session;
	NSWindow *dragWindow;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 200.0)
					     styleMask:NSBorderlessWindowMask
					       backing:NSBackingStoreBuffered defer:NO];
	view = [[AGSeamView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
	[window setContentView:view];
	[window orderFront:nil];
	if (![NSWindow cg_hasWindowServer]) {
		printf("drag_seam: SKIP — no window server connection\n");
		return 77;
	}

	source = [[AGSeamSource alloc] init];
	image = [[[NSImage alloc] initWithSize:NSMakeSize(40.0, 20.0)] autorelease];
	item = [[[NSDraggingItem alloc] initWithPasteboardWriter:nil] autorelease];
	[item setDraggingFrame:NSMakeRect(10.0, 10.0, 40.0, 20.0) contents:image];

	session = [view beginDraggingSessionWithItems:[NSArray arrayWithObject:item]
					       event:mouse(NSLeftMouseDown, NSMakePoint(20.0, 20.0))
					      source:source];
	check(session != nil, "a session begins on a connected server");
	dragWindow = [[session cg_draggingWindow] retain];
	check(dragWindow != nil, "and it makes a drag image window");
	check([dragWindow isVisible], "the image window is ordered in");
	check([dragWindow ignoresMouseEvents], "and it never takes the pointer");
	check([dragWindow level] == NSFloatingWindowLevel, "at the floating level");
	check(([dragWindow styleMask] & NSTitledWindowMask) == 0, "with no chrome");
	check(![dragWindow isOpaque], "and a transparent ground for the image's alpha");
	check(near([dragWindow frame].size.width, 40.0) && near([dragWindow frame].size.height, 20.0),
	      "the window is the composed image's size");
	check(near([dragWindow frame].origin.x, 10.0) && near([dragWindow frame].origin.y, 10.0),
	      "and sits where the item's frame and the pointer's offset put it");

	/* THE IMAGE FOLLOWS THE POINTER, by the same offset, wherever the pointer goes. */
	[window sendEvent:mouse(NSLeftMouseDragged, NSMakePoint(100.0, 80.0))];
	check(near([dragWindow frame].origin.x, 90.0) && near([dragWindow frame].origin.y, 70.0),
	      "a motion moves the image window with the pointer");

	/* THE END ORDERS IT OUT AND LETS IT GO. */
	[window sendEvent:mouse(NSLeftMouseUp, NSMakePoint(100.0, 80.0))];
	check([NSDraggingSession cg_activeSession] == nil, "the release ends the session");
	check(![dragWindow isVisible], "and the image window is ordered out");
	[dragWindow release];

	/* **AND A FLIPPED SOURCE VIEW — THE SHAPE EVERY ICON GRID IN THIS TREE HAS — PUTS ITS IMAGE UNDER THE HAND.** Two
	 * things were wrong for it, and both were invisible while the source was an unflipped view filling its window:
	 *
	 *   - the drag's starting point was handed over in the WINDOW's space and read as the VIEW's, so a flipped view
	 *     mirrored it and the offset between pointer and image came out as (10, -170) — the floating icon flew to the
	 *     top of the screen the moment the hand moved;
	 *   - the item's frame was converted by its ORIGIN alone, which in a y-down view is the item's TOP-left corner;
	 *     used as an unflipped rect's bottom-left it lifted the image by the item's own height.
	 *
	 * Here the view is flipped, the item sits 10 points down from its top, and the pointer is 10 points inside it — so
	 * the image must start on the icon and stay there. One session at a time, so this waits for the first to end. */
	{
		/* **THE FLIPPED VIEW IS A SUBVIEW OF A PLAIN CONTENT VIEW, WHICH IS THE SHAPE WORKSPACE ACTUALLY HAS** — a
		 * window's content is not flipped and an icon grid inside it is — because this tier defines the null view's
		 * space as the ROOT's own, so a flipped ROOT would be a different question. */
		NSView *plainContent = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		AGFlippedView *flipped = [[AGFlippedView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSDraggingItem *frameItem = [[[NSDraggingItem alloc] initWithPasteboardWriter:nil] autorelease];
		NSWindow *second = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 200.0)
							       styleMask:NSBorderlessWindowMask
								backing:NSBackingStoreBuffered defer:NO];
		NSDraggingSession *secondSession;
		NSWindow *secondWindow;

		[second setContentView:plainContent];
		[plainContent addSubview:flipped];
		[second orderFront:nil];
		[frameItem setDraggingFrame:NSMakeRect(10.0, 10.0, 40.0, 20.0) contents:image];
		/* THE POINTER IS AT WINDOW (20,180), WHICH IS VIEW (20,20) — 10 points inside the item's top-left corner. */
		secondSession = [flipped beginDraggingSessionWithItems:[NSArray arrayWithObject:frameItem]
								event:mouse(NSLeftMouseDown, NSMakePoint(20.0, 180.0))
							       source:source];
		check(secondSession != nil, "a flipped source view begins a session too");
		secondWindow = [[secondSession cg_draggingWindow] retain];
		check(secondWindow != nil && near([secondWindow frame].origin.x, 10.0)
		      && near([secondWindow frame].origin.y, 170.0),
		      "the image starts where the item is, 170 points up from the window's floor");
		[second sendEvent:mouse(NSLeftMouseDragged, NSMakePoint(120.0, 140.0))];
		check(secondWindow != nil && near([secondWindow frame].origin.x, 110.0)
		      && near([secondWindow frame].origin.y, 130.0),
		      "and it stays the same 10 points under the pointer when the hand moves");
		[second sendEvent:mouse(NSLeftMouseUp, NSMakePoint(120.0, 140.0))];
		[secondWindow release];
		[second close];
		[second release];
		[flipped release];
		[plainContent release];
	}


	[source release];
	[view release];
	[window release];
	printf("drag_seam: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
