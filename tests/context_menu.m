/*
 * context_menu — a right-click asks a view for its menu, and opens it where the click was.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE BUG THIS FILE EXISTS FOR IS A MENU NOBODY COULD REACH.** `-menuForEvent:` had been answered by views since stage
 * D — the Dock even builds a context menu by hand and pops it — but NOTHING ASKED THE QUESTION: `NSView` did not
 * implement `-rightMouseDown:`, so the event forwarded up the responder chain and a view carrying a menu got no gesture.
 * And the answer itself was nil while `-setMenu:`'s ivar sat unread. So the three cases are the pair Apple's default is
 * made of, plus the override that is the reason the question exists:
 *
 *   1. a right-click on a view with a menu POPS that menu, AT THE CLICK (not at the origin — the placement is the
 *      event's point converted to the view, which is the arithmetic `menu_placement` records);
 *   2. a subclass that answers `-menuForEvent:` itself is what gets popped, not the menu `-setMenu:` wrote — the
 *      question is asked first, which is how a menu about "the thing under the pointer" is built;
 *   3. and a view with no menu forwards the event on and opens nothing, so a plain view is untouched by the fix.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSAutoreleasePool.h>

#include <stdio.h>

static int s_failed;

/* **A SESSION A PROBE OPENS IS CLOSED AT ONCE, AND THAT IS THE TIER'S OWN RULE RATHER THAN A BUG:** a menu whose
 * program has no run loop to track it is closed rather than left standing with a pointer grab nobody releases. So
 * "the menu opened" is measured the way the framework announces it — the begin-tracking notification — and the
 * placement is measured off the tracking frame, which survives the close. */
static int s_began;
static id s_beganMenu;	/* NOT RETAINED: the probe's own menu */

@interface AGMenuWatch : NSObject
@end

@implementation AGMenuWatch
- (void)menuDidBeginTracking:(NSNotification *)note
{
	s_beganMenu = [note object];
	s_began++;
}
@end

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* A MENU WITH ONE ROW, because the dispatch is what this is about and not the contents. */
static NSMenu *oneItemMenu(NSString *title)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Test"];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];

	[menu addItem:item];
	[item release];
	return [menu autorelease];
}

/* A VIEW THAT ANSWERS THE QUESTION ITS OWN WAY: a subclass overrides `-menuForEvent:` when the menu depends on WHERE the
 * click landed, which is every menu that is about an item. */
@interface AGMenuView : NSView
{
	NSMenu *_probeMenu;	/* NOT RETAINED: the probe owns it */
}
- (void)setProbeMenu:(NSMenu *)menu;
@end

@implementation AGMenuView
- (void)setProbeMenu:(NSMenu *)menu
{
	_probeMenu = menu;
}
- (NSMenu *)menuForEvent:(NSEvent *)event
{
	(void)event;
	return _probeMenu;
}
@end

/* AND A VIEW THAT COUNTS WHAT THE CHAIN HANDED IT, so "forwarded on" is measured and not assumed. */
@interface AGCounterView : NSView
{
	int _rightClicks;
}
- (int)rightClicks;
@end

@implementation AGCounterView
- (int)rightClicks
{
	return _rightClicks;
}
- (void)rightMouseDown:(NSEvent *)event
{
	_rightClicks++;
	[super rightMouseDown:event];
}
@end

static NSEvent *rightClick(NSPoint point, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:NSRightMouseDown location:point modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	NSView *view;
	AGMenuWatch *watch = [[AGMenuWatch alloc] init];

	(void)application;
	[[NSNotificationCenter defaultCenter] addObserver:watch selector:@selector(menuDidBeginTracking:)
						     name:NSMenuDidBeginTrackingNotification object:nil];
	printf("context_menu\n");

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(900.0, 100.0, 200.0, 200.0)
					     styleMask:NSBorderlessWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
	[window setContentView:view];

	/* ---- 1. the click opens the menu the view holds, where the click was ------------------ */
	{
		NSMenu *menu = oneItemMenu(@"Get Info");
		NSRect frame;

		[view setMenu:menu];
		[view rightMouseDown:rightClick(NSMakePoint(20.0, 30.0), [window windowNumber])];
		frame = [menu cg_trackingFrame];
		check(s_began == 1 && s_beganMenu == menu, "a right-click on a view with a menu opens that menu");
		printf("  clicked at 20,30 in a window at 900,100 -> menu at %.0f,%.0f\n",
		       (double)frame.origin.x, (double)frame.origin.y);
		check(frame.origin.x == 920.0, "the menu opens at the click's own x, in the window's coordinates");
		check(frame.origin.y == 130.0 - frame.size.height, "and below the click, hanging from its top");
		[menu cancelTracking];
		[view setMenu:nil];
	}

	/* ---- 2. and the subclass's own answer is what pops ---------------------------------- */
	{
		AGMenuView *answerer = [[AGMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
		NSMenu *held = oneItemMenu(@"held");
		NSMenu *answered = oneItemMenu(@"answered");

		[answerer setMenu:held];
		[answerer setProbeMenu:answered];
		[window setContentView:answerer];
		s_began = 0;
		s_beganMenu = nil;
		[answerer rightMouseDown:rightClick(NSMakePoint(40.0, 40.0), [window windowNumber])];
		check(s_began == 1 && s_beganMenu == answered, "a subclass's -menuForEvent: is what gets popped");
		[answered cancelTracking];
		[answerer release];
		[window setContentView:view];
	}

	/* ---- 3. no menu: the event is forwarded and nothing opens ---------------------------- */
	{
		AGCounterView *container = [[AGCounterView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
		NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];

		[container addSubview:plain];
		[window setContentView:container];
		s_began = 0;
		s_beganMenu = nil;
		[plain rightMouseDown:rightClick(NSMakePoint(10.0, 10.0), [window windowNumber])];
		check([container rightClicks] == 1, "a view with no menu forwards the right-click up the responder chain");
		check(s_began == 0, "and nothing was opened");
		[plain release];
		[container release];
		[window setContentView:view];
	}

	[view release];
	[window release];
	[[NSNotificationCenter defaultCenter] removeObserver:watch];
	[watch release];
	[pool release];
	printf("context_menu: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
