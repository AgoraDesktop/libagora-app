/*
 * control_drag — how many times does a window DRAW while a slider is being dragged?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **"LAGGY TO DRAG AND SNAPPY TO CLICK" IS A NUMBER, AND THIS IS THE INSTRUMENT.** A click is one event and one
 * frame; a drag at a hand's rate is a HUNDRED events, and the question is how many frames the window commits for
 * them. A control's tracking is a MODAL LOOP — `NSControl -mouseDown:` runs its own `-nextEventMatchingMask:`
 * until the button comes up — so while it runs the application's run loop is not turning, and everything the loop
 * does once per pass has to be done here by hand. What it did was draw AND COMMIT once per event: one full redraw
 * of the view tree, one `AGWindowBeginFrame` and one frame copied per motion, which is a rate the compositor
 * cannot take and does not have to.
 *
 * HOW IT IS COUNTED. `-displayRect:` draws the receiver and every subview, and the window calls it once per
 * committed frame — so a content view that counts its own `-drawRect:` is counting FRAMES, and the counter is the
 * measurement rather than a proxy for it.
 *
 * AND THE EVENTS ARE QUEUED BEFORE THE LOOP STARTS. The tracking loop lives inside `-sendEvent:`, and there is no
 * way to run code beside a run loop in a test; so the whole drag is put in the window's queue first and the
 * application's OWN loop is then started, which is the only way to reach the loop at all (`-mouseDown:` does the
 * tracking only when `-isRunning`, which is what the reachable-`-run` guard below is for).
 *
 * WHAT IS ASSERTED:
 *
 *   1. Every motion was APPLIED — the action fired for each one and the value ended at the far end of the range.
 *      A tier that dropped motions to make the drawing cheap would pass every check about frames and fail this.
 *   2. The window drew A HANDFUL OF TIMES, not once per motion.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

/* THE PRIVATE DOOR THE SEAM CALLS, redeclared here: this tree's own pattern for a private contract a second file
 * has to reach. */
@interface NSWindow (AGControlDragTestDoor)
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

/* **THE FRAME COUNTER, AND THE TWO WAYS THE RUN ENDS.** `-drawRect:` fires once for the tree on every commit, so
 * this counts frames — and it is also the end of the run: with `stopOnDraw` armed, the FIRST frame drawn after the
 * drag began stops the application, which is what makes the measurement "the frames this drag cost" rather than
 * "the frames drawn before the app was stopped by something else". MEASURED, that distinction is the whole test:
 * stopping from the action instead gave ZERO draws, because a frame the compositor is still holding is not drawn
 * at all (`AGWindowBeginFrame`) and the run ended before the buffer came back.
 *
 * `-mouseUp:` is the watchdog for the other failure: if the tracking loop never ran, the release is delivered
 * HERE instead, and stops the application — so a drag that never reaches the control FAILS rather than hanging. */
@interface AGCountingView : NSView
{
@public
	int draws;
	int mouseUps;
	BOOL stopOnDraw;
}
@end

@implementation AGCountingView
- (void)drawRect:(NSRect)rect
{
	(void)rect;
	draws++;
	if (stopOnDraw) {
		[NSApp stop:nil];
	}
}

- (void)mouseUp:(NSEvent *)event
{
	(void)event;
	mouseUps++;
	[NSApp stop:nil];
}
@end

/* WHAT THE SLIDER TELLS, counted: one call per value it speaks with, which is what a continuous control owes. */
@interface AGDragController : NSObject
{
@public
	int actions;
	double last;
}
@end

@implementation AGDragController
- (void)sliderMoved:(id)sender
{
	actions++;
	last = [(NSSlider *)sender doubleValue];
}
@end

static AGEvent pointer_button(uint32_t button, int pressed, int x, int y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerButton;
	event.button = button;			/* BTN_LEFT */
	event.pressed = pressed;
	event.x = x;
	event.y = y;
	return event;
}

static AGEvent pointer_motion(int x, int y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerMotion;
	event.x = x;
	event.y = y;
	return event;
}

/* THE SEAM'S `y` IS MEASURED DOWN FROM THE TOP OF THE FRAME and this is written in CONTENT coordinates, which start
 * at the frame's bottom — the conversion `tests/appkit_events.m` writes once for the same reason. */
static int seam_y(NSWindow *window, CGFloat contentY)
{
	return (int)([window frame].size.height - contentY);
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGCountingView *content;
		NSSlider *slider;
		AGDragController *controller;
		const CGFloat sliderY = 80.0;
		const int motions = 40;
		int i;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 200.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "control_drag: NO WINDOW WAS MADE\n");
			return 1;
		}
		content = [[AGCountingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 200.0)];
		slider = [[NSSlider alloc] initWithFrame:NSMakeRect(50.0, sliderY, 300.0, 28.0)];
		controller = [[AGDragController alloc] init];
		[slider setMinValue:0.0];
		[slider setMaxValue:100.0];
		[slider setDoubleValue:50.0];
		[slider setTarget:controller];
		[slider setAction:@selector(sliderMoved:)];
		[content addSubview:slider];
		[window setContentView:content];
		[window orderFront:nil];

		/* LET THE COMPOSITOR CONFIGURE IT, so the frame the seam's coordinates are measured against is the real one. */
		{
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];

			while ([deadline timeIntervalSinceNow] > 0.0) {
				NSEvent *e = [application nextEventMatchingMask:NSAnyEventMask
								      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
									 inMode:nil
									dequeue:YES];

				if (e != nil) {
					[application sendEvent:e];
				}
			}
		}
		printf("control_drag: window %ld, frame %gx%g, slider %gx%g\n", (long)[window windowNumber],
		       (double)[window frame].size.width, (double)[window frame].size.height,
		       (double)[slider frame].size.width, (double)[slider frame].size.height);

		/* THE WHOLE DRAG, QUEUED BEFORE THE LOOP STARTS: a press on the track, `motions` moves across it, and the
		 * release. The knob's y is the slider's middle. */
		{
			AGEvent e = pointer_button(0x110, 1, 60, seam_y(window, sliderY + 14.0));

			[window cg_handleSeamEvent:&e];
		}
		for (i = 1; i <= motions; i++) {
			CGFloat x = 60.0 + (CGFloat)i * (280.0 / (CGFloat)motions);
			AGEvent e = pointer_motion((int)x, seam_y(window, sliderY + 14.0));

			[window cg_handleSeamEvent:&e];
		}
		{
			AGEvent e = pointer_button(0x110, 0, 340, seam_y(window, sliderY + 14.0));

			[window cg_handleSeamEvent:&e];
		}

		content->draws = 0;		/* the configure above drew; the drag is what is being measured */
		content->stopOnDraw = YES;	/* and the first frame the drag commits is where the measurement ends */
		[application run];

		printf("control_drag: %d motions -> %d draw(s), %d action(s), value %.1f, mouseUps %d\n",
		       motions, content->draws, controller->actions, controller->last, content->mouseUps);
		check(controller->actions >= motions, "every motion reached the control and was spoken");
		check(controller->last > 95.0, "and the drag ended at the far end of the range");
		check(content->draws >= 1, "the window drew the drag at all");
		check(content->draws <= 6, "a drag of 40 motions drew the window a HANDFUL of times, not once per motion");

		printf("control_drag: %d checks, %d failed%s\n", g_checks, g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");
		[controller release];
		[slider release];
		[content release];
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
