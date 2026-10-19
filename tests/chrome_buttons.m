/*
 * chrome_buttons — does a click on the title bar's X, minus and plus DO anything, and only when it should?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE CHROME HAD THREE ANSWERS AND ONLY TWO OF THEM EXISTED.** Where a button is (`fn_chrome_layout`) and what it
 * is DRAWN in (`fn_chrome_state`) were both wired — a press lit the theme's pressed art — and the third, what a
 * button DOES, was not: the release cleared the press and performed nothing. That is the half a person notices, and
 * it is invisible to every test that asks about pixels, so it needs a test that asks what HAPPENED.
 *
 * HOW IT ASKS WITHOUT A HAND. Exactly the way `tests/appkit_events.m` does: `AGEvent` is the seam's own public
 * struct, so this builds the pointer events a compositor would have sent, hands them to the window through the
 * seam's private door, and pumps them with the application's own pump. What is exercised from end to end is the
 * pointer's journey through `-sendEvent:` — the coordinate flip into window space, the hit test, the press, the
 * release and the action — and the only synthetic link is the compositor calling that door.
 *
 * **AND THE POINTS COME FROM THE WINDOW ITSELF, AT THE MOMENT THEY ARE USED.** The button rectangles are asked of
 * `-cg_chromeButtonAtPoint:`, the door the event path itself uses, by scanning the strip for each answer — a test
 * that recomputed the layout would keep passing after every button moved. THEY ARE ASKED AGAIN FOR EACH EVENT,
 * because a button's rectangle in window coordinates moves with the window's own height and one of these buttons
 * RESIZES the window: a release built from the press-time frame describes a place the button is no longer at, and
 * the click lands on the content with nothing to show for it. MEASURED — that is how the first version of this
 * test failed, and it read exactly like buttons that were never wired.
 *
 * WHAT IS ASSERTED — each one a way the wiring can be wrong while looking right:
 *
 *   1. The plus ZOOMS, and a second click UNZOOMS: the action reaches `-zoom:`, which alternates.
 *   2. A press that slides OFF the button and releases there does NOTHING, so a hand can change its mind.
 *   3. A press that slides off and comes BACK does perform it, which is the same pair read the other way and the
 *      reason the pressed ink is the POINTER's state rather than the press's.
 *   4. The minus MINIATURIZES.
 *   5. The pill performs NOTHING ON THIS WINDOW: it is the toolbar toggle and this window has no toolbar, so it must
 *      not stand in for another button. (`tests/toolbar.m` is the other half: the same pill toggles a window that has
 *      one.)
 *   6. The X ASKS THE DELEGATE: a refused `-windowShouldClose:` leaves the window open, and an allowed one closes
 *      it — which is the whole difference between performing `-performClose:` and calling `-close` directly.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/AGChromeTheme.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>

/* THE PRIVATE DOORS, redeclared here: this tree's own pattern for a private contract a second file has to reach. */
@interface NSWindow (AGChromeButtonTestDoor)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
- (NSInteger)cg_chromeButtonAtPoint:(NSPoint)windowPoint;
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

/* **THE DELEGATE THAT REFUSES, WHICH IS HOW A CLOSE IS TOLD FROM A DESTRUCTION.** Nothing here is a mock: this is
 * the real `-windowShouldClose:` AppKit sends, and the counter is how the test sees that it was asked at all. */
@interface AGChromeButtonDelegate : NSObject <NSWindowDelegate>
{
@public
	int shouldCloseCalls;
	BOOL allowClose;
}
@end

@implementation AGChromeButtonDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender
{
	(void)sender;
	shouldCloseCalls++;
	return allowClose;
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

/* DELIVER ONE EVENT: hand it to the window the way the seam does, then run the application's own pump and dispatch,
 * so what is under test is the path a real event takes. */
static void deliver(NSApplication *application, NSWindow *window, const AGEvent *event)
{
	NSEvent *built;
	NSDate *deadline;

	[window cg_handleSeamEvent:event];
	deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
	while ((built = [application nextEventMatchingMask:NSAnyEventMask
						 untilDate:deadline
						    inMode:nil
						   dequeue:YES]) != nil) {
		[application sendEvent:built];
		/* ONE EVENT PER CALL: the loop is here to drain a configure if one is waiting, not to batch. */
		if ([built type] != NSFlagsChanged && [built windowNumber] != 0) {
			break;
		}
	}
}

/* **THE SEAM'S `y` COMES DOWN FROM THE TOP OF THE FRAME AND COCOA'S GOES UP FROM THE BOTTOM**, and it is not
 * incidental here: the chrome is the TOP of the frame, so a test that got this backwards would be pressing on the
 * bottom edge of the window and every check would fail for a reason that has nothing to do with buttons. */
static AGEvent press_at(NSWindow *window, NSPoint p)
{
	return pointer_button(0x110, 1, (int)p.x, (int)([window frame].size.height - p.y));
}

static AGEvent release_at(NSWindow *window, NSPoint p)
{
	return pointer_button(0x110, 0, (int)p.x, (int)([window frame].size.height - p.y));
}

static AGEvent move_to(NSWindow *window, NSPoint p)
{
	return pointer_motion((int)p.x, (int)([window frame].size.height - p.y));
}

/* **A POINT IN A BUTTON, ASKED OF THE DOOR THE POINTER ITSELF USES.** The strip is scanned rather than the layout
 * recomputed: that arithmetic belongs to `fn_chrome_layout`, and a test repeating it would keep passing after every
 * button moved. What comes back is the box, so a caller can use its CENTRE and depend on no edge pixel. */
static NSRect button_box(NSWindow *window, NSInteger which)
{
	NSRect content = [window contentRectForFrameRect:[window frame]];
	CGFloat top = [window frame].size.height;
	CGFloat minx = 1.0e9, miny = 1.0e9, maxx = -1.0e9, maxy = -1.0e9;
	CGFloat x, y;

	for (y = content.size.height; y < top; y += 1.0) {
		for (x = 0.0; x < content.size.width; x += 1.0) {
			if ([window cg_chromeButtonAtPoint:NSMakePoint(x, y)] == which) {
				if (x < minx) minx = x;
				if (y < miny) miny = y;
				if (x > maxx) maxx = x;
				if (y > maxy) maxy = y;
			}
		}
	}
	if (maxx < 0.0) {
		return NSMakeRect(-1.0, -1.0, 0.0, 0.0);
	}
	return NSMakeRect(minx, miny, maxx - minx, maxy - miny);
}

static NSPoint button_centre(NSWindow *window, NSInteger which)
{
	NSRect box = button_box(window, which);

	return NSMakePoint(NSMidX(box), NSMidY(box));
}

/* A POINT IN THE STRIP THAT IS IN NO BUTTON — the window's handle, and where a hand that has changed its mind takes
 * a button's drag. */
static NSPoint bare_chrome_point(NSWindow *window)
{
	NSRect content = [window contentRectForFrameRect:[window frame]];
	CGFloat y = content.size.height + ([window frame].size.height - content.size.height) / 2.0;
	CGFloat x;

	for (x = NSMidX(content); x < NSMaxX(content) - 1.0; x += 1.0) {
		if ([window cg_chromeButtonAtPoint:NSMakePoint(x, y)] < 0) {
			return NSMakePoint(x, y);
		}
	}
	return NSMakePoint(NSMidX(content), y);
}

/* THE THREE MOVES THIS TEST MAKES, EACH BUILT FROM THE FRAME AS IT IS WHEN IT IS DELIVERED. See the header: the
 * plus RESIZES the window, so the press-time frame answers for a button that has moved by the time of the release. */
static void press_button(NSApplication *application, NSWindow *window, NSInteger which)
{
	AGEvent e = press_at(window, button_centre(window, which));

	deliver(application, window, &e);
}

static void release_button(NSApplication *application, NSWindow *window, NSInteger which)
{
	AGEvent e = release_at(window, button_centre(window, which));

	deliver(application, window, &e);
}

static void click_button(NSApplication *application, NSWindow *window, NSInteger which)
{
	press_button(application, window, which);
	release_button(application, window, which);
}

static void drag_to(NSApplication *application, NSWindow *window, NSPoint where)
{
	AGEvent e = move_to(window, where);

	deliver(application, window, &e);
}

/* THE CLOSE IS ACTED ON INSIDE THE DISPATCH, so this only guards against a later build deferring it. */
static void pump_until_closed(NSApplication *application, NSWindow *window)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];

	while ([deadline timeIntervalSinceNow] > 0.0 && [window windowNumber] != -1) {
		NSEvent *e = [application nextEventMatchingMask:NSAnyEventMask
						      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
							 inMode:nil
							dequeue:YES];

		if (e != nil) {
			[application sendEvent:e];
		}
	}
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGChromeButtonDelegate *delegate;
		NSRect before;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 420.0, 280.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask |
								NSMiniaturizableWindowMask | NSResizableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "chrome_buttons: NO WINDOW WAS MADE\n");
			return 1;
		}
		[window setContentView:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 280.0)] autorelease]];
		[window orderFront:nil];

		/* LET THE COMPOSITOR CONFIGURE IT, because the seam's coordinates are the frame's and the frame is not its
		 * requested size until a configure has arrived. */
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
		printf("chrome_buttons: window %ld, frame %gx%g, content %gx%g\n", (long)[window windowNumber],
		       (double)[window frame].size.width, (double)[window frame].size.height,
		       (double)[[window contentView] frame].size.width,
		       (double)[[window contentView] frame].size.height);

		/* THE FOUR BUTTONS HAVE TO EXIST BEFORE ANYTHING CAN BE PRESSED, and a strip with none in it would make
		 * every check below fail for the wrong reason. The style mask asks for all four. */
		check(button_box(window, AGChromeButtonClose).size.width > 0.0
		      && button_box(window, AGChromeButtonHide).size.width > 0.0
		      && button_box(window, AGChromeButtonMaximize).size.width > 0.0
		      && button_box(window, AGChromeButtonMenu).size.width > 0.0
		      && bare_chrome_point(window).x > 0.0,
		      "the window's style mask puts four buttons and a bare handle in the strip");

		/* 1. THE PLUS ZOOMS, AND A SECOND CLICK UNZOOMS. */
		before = [window frame];
		click_button(application, window, AGChromeButtonMaximize);
		printf("  (the zoom took the frame from %gx%g to %gx%g)\n", (double)before.size.width,
		       (double)before.size.height, (double)[window frame].size.width,
		       (double)[window frame].size.height);
		check([window isZoomed], "a click on the ZOOM button zooms the window");
		click_button(application, window, AGChromeButtonMaximize);
		check(![window isZoomed], "and a second click restores it — the action reaches `-zoom:`, which alternates");

		/* 2. A PRESS THAT SLIDES OFF AND RELEASES THERE DOES NOTHING. The release is on the bare strip, not on the
		 * button, which is the whole of the rule. */
		press_button(application, window, AGChromeButtonMaximize);
		drag_to(application, window, bare_chrome_point(window));
		{
			AGEvent up = release_at(window, bare_chrome_point(window));

			deliver(application, window, &up);
		}
		check(![window isZoomed], "a press that slides OFF the button and releases there does NOTHING");

		/* 3. AND ONE THAT COMES BACK DOES — the same pair read the other way. */
		press_button(application, window, AGChromeButtonMaximize);
		drag_to(application, window, bare_chrome_point(window));
		drag_to(application, window, button_centre(window, AGChromeButtonMaximize));
		release_button(application, window, AGChromeButtonMaximize);
		check([window isZoomed], "and one that slides off and comes BACK does perform it");
		click_button(application, window, AGChromeButtonMaximize);
		check(![window isZoomed], "the window is left unzoomed for the checks that follow");

		/* 4. THE MINUS MINIATURIZES. What the tier does with the state is its own recorded business — there is no
		 * Dock and no iconify in the protocol — but the BUTTON must reach the door. */
		click_button(application, window, AGChromeButtonHide);
		check([window isMiniaturized], "a click on the MINIMIZE button miniaturizes the window");

		/* 5. THE FOURTH MARK PERFORMS NOTHING ON A WINDOW WITH NO TOOLBAR. It is the toolbar toggle, there is nothing attached,
		 * and the one thing it must not do in the meantime is stand in for another button. */
		before = [window frame];
		click_button(application, window, AGChromeButtonMenu);
		check(![window isZoomed] && [window isMiniaturized]
		      && [window frame].origin.x == before.origin.x && [window frame].origin.y == before.origin.y
		      && [window frame].size.width == before.size.width
		      && [window frame].size.height == before.size.height,
		      "a click on the TOOLBAR MARK changes nothing — it is the toggle and this window has no toolbar");
		check([window windowNumber] != -1, "and the window is still here");

		/* 6. THE X ASKS THE DELEGATE, WHICH IS THE DIFFERENCE BETWEEN THE BUTTON AND `-close`. */
		delegate = [[AGChromeButtonDelegate alloc] init];
		delegate->allowClose = NO;
		[window setDelegate:delegate];
		click_button(application, window, AGChromeButtonClose);
		check(delegate->shouldCloseCalls == 1, "a click on the CLOSE button asks the delegate first");
		check([window windowNumber] != -1, "and a REFUSED close leaves the window open");

		delegate->allowClose = YES;
		click_button(application, window, AGChromeButtonClose);
		check(delegate->shouldCloseCalls == 2, "an allowed click asks it again");
		pump_until_closed(application, window);
		check([window windowNumber] == -1, "and the window closes");

		printf("chrome_buttons: %d checks, %d failed%s\n", g_checks, g_failed,
		       g_failed == 0 ? " -- all checks passed" : "");
		[delegate release];
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
