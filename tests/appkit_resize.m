/*
 * appkit_resize — the compositor's configure and the application's frame set are one resize, or they are two bugs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **WHAT WAS WRONG, SPLIT INTO THE TWO HALVES THAT WERE WRONG SEPARATELY.**
 *
 * A compositor configure was handled inside libwayland's listener dispatch: assign the size, mark the window dirty,
 * and DRAW. So the frame was painted with the content view still at its OLD rectangle (the layout tail had not run),
 * the resize was never announced to the delegate at all — the compositor's resize and the application's took two
 * different paths through the same file — and a delegate reached from that draw could close the window while the
 * surface's own callbacks were still on the stack.
 *
 * And the application's own path announced `-windowDidResize:` BEFORE re-laying the content view, so a resize
 * observer — which is what a scroll view, a table or a document registers — read the new frame and the old content
 * bounds in the same callback and laid out for a size the window no longer had.
 *
 * **THE SHAPE OF THE FIX IS WHAT THIS MEASURES.** The size is taken in the listener, because the input events behind
 * it in the same native batch are measured in it; the layout, the repaint and the notification happen in the pump,
 * once per batch, after the listener has unwound. So the assertions are about WHEN each half is visible:
 *
 *   1. right after the seam delivers a configure, the FRAME is already the new size and the CONTENT is not;
 *   2. after one pump turn the content is re-laid, and the delegate has been told exactly once;
 *   3. three configures in one batch are one notification, at the size the batch settled on;
 *   4. a batch that settles where it started is no resize at all;
 *   5. a delegate that CLOSES the window from the notification is fine, because the notification is not inside the
 *      dispatch — which is the crash this ordering exists to prevent.
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

@interface NSWindow (AGEventTestDoor)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
@end

static int g_checks;
static int g_failed;

static void check(int ok, const char *what)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", what);
	} else {
		printf("  [ok]   %s\n", what);
	}
}

/* A DELEGATE THAT RECORDS THE GEOMETRY IT SAW, because the claim is about what an observer can read from inside the
 * callback, and a bare counter could not tell a re-laid window from a stale one. It can also close the window from
 * the notification, which is case 5. */
@interface AGResizeObserver : NSObject
{
@public
	int resizes;
	NSSize lastFrameSize;
	NSSize lastContentSize;
	BOOL closeOnResize;
}
@end

@implementation AGResizeObserver

- (void)windowDidResize:(NSNotification *)notification
{
	NSWindow *window = [notification object];

	resizes++;
	lastFrameSize = [window frame].size;
	lastContentSize = [[window contentView] frame].size;
	if (closeOnResize && resizes == 1) {
		[window close];
	}
}

@end

static void pump(NSApplication *application)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.4];

	while ([deadline timeIntervalSinceNow] > 0.0) {
		NSEvent *e = [application nextEventMatchingMask:NSAnyEventMask
						      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
							 inMode:nil
							dequeue:YES];

		if (e != nil) {
			[application sendEvent:e];
		}
	}
}

/* THE COMPOSITOR'S OWN EVENT, built here because the headless compositor has no window manager to send one. */
static void configure(NSWindow *window, CGFloat width, CGFloat height)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventConfigure;
	event.x = (int)width;
	event.y = (int)height;
	[window cg_handleSeamEvent:&event];
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		NSView *content;
		AGResizeObserver *observer;
		NSRect contentRect;
		NSSize settled;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 400.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_resize: NO WINDOW WAS MADE\n");
			return 1;
		}
		content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 400.0)];
		[window setContentView:content];
		observer = [[AGResizeObserver alloc] init];
		[window setDelegate:(id)observer];
		[window orderFront:nil];
		pump(application);
		observer->resizes = 0;

		/* ============================================================================================
		 * 1. THE SIZE IS TAKEN IN THE LISTENER; THE CONTENT IS NOT.
		 * ============================================================================================ */
		configure(window, 800, 500);
		check([window frame].size.width == 800.0 && [window frame].size.height == 500.0,
		      "the FRAME takes the configured size immediately, so the batch's input is measured in it");
		check([[window contentView] frame].size.width == 640.0,
		      "the CONTENT view is still at its old size, because the layout is deferred");
		check(observer->resizes == 0, "and the delegate has not been told anything yet");

		/* ============================================================================================
		 * 2. ONE PUMP TURN LANDS IT — LAYOUT FIRST, THEN THE NOTIFICATION.
		 * ============================================================================================ */
		pump(application);
		contentRect = [window contentRectForFrameRect:[window frame]];
		check([[window contentView] frame].size.width == contentRect.size.width,
		      "after the pump the content view is re-laid to the new geometry");
		check(observer->resizes == 1, "and the delegate is told, exactly once");
		check(observer->lastContentSize.width == contentRect.size.width,
		      "the delegate sees the NEW content bounds from inside the callback, not the old ones");
		check(observer->lastFrameSize.width == 800.0, "and the new frame beside them");

		/* ============================================================================================
		 * 3. A BATCH OF CONFIGURES IS ONE RESIZE.
		 * ============================================================================================ */
		observer->resizes = 0;
		configure(window, 700, 450);
		configure(window, 900, 550);
		configure(window, 820, 520);
		pump(application);
		check(observer->resizes == 1, "three configures in one batch are ONE notification");
		settled = [window frame].size;
		check(settled.width == 820.0 && settled.height == 520.0, "at the size the batch settled on");
		check([[window contentView] frame].size.width == [window contentRectForFrameRect:[window frame]].size.width,
		      "and the content is laid out for that one size, not each of them");

		/* ============================================================================================
		 * 4. A BATCH THAT SETTLES WHERE IT STARTED IS NOT A RESIZE.
		 * ============================================================================================ */
		observer->resizes = 0;
		configure(window, 1000, 600);
		configure(window, 820, 520);
		pump(application);
		check(observer->resizes == 0, "a batch that ends at the size it began is not announced as a resize");

		/* AND ONE THAT REALLY MOVES IS ANNOUNCED — the check above must not have made every configure silent. */
		observer->resizes = 0;
		configure(window, 1000, 600);
		pump(application);
		check(observer->resizes == 1, "while a batch that does move is announced");

		/* ============================================================================================
		 * 5. THE DELEGATE MAY CLOSE THE WINDOW FROM THE NOTIFICATION.
		 * ============================================================================================ */
		{
			NSWindow *doomed = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
								       styleMask:NSTitledWindowMask
									 backing:NSBackingStoreBuffered
									   defer:NO];
			AGResizeObserver *closer = [[AGResizeObserver alloc] init];

			[doomed setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)] autorelease]];
			closer->closeOnResize = YES;
			[doomed setDelegate:(id)closer];
			[doomed orderFront:nil];
			pump(application);

			configure(doomed, 600, 400);
			pump(application);
			check(closer->resizes == 1, "the delegate is asked about the resize");
			check([doomed windowNumber] == -1,
			      "and CLOSING the window from inside that callback is survivable — the notification is not "
			      "inside the native dispatch, so there is no surface callback left on the stack");
			/* AND THE PUMP STILL WORKS AFTERWARDS, which is the practical half of surviving it. */
			configure(window, 900, 560);
			pump(application);
			check([window frame].size.width == 900.0, "and the rest of the application keeps working");
			[doomed release];
			[closer release];
		}

		printf("appkit_resize: %d checks, %d failed%s\n", g_checks, g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");

		[observer release];
		[content release];
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
