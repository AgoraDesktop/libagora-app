/*
 * menu_highlight_burst — a moving pointer repaints a menu ONCE per burst, not once per event.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE COMPLAINT THIS MEASURES: "I move the mouse over an open menu and the highlight lags behind the pointer."** A
 * full menu paint is 3.6 ms over twelve rows (MEASURED, one cell and one Core Text line per row), and the session's
 * loop used to take ONE event and paint, then take the next and paint again. An X11 pointer emits motion faster than
 * one paint per sample, so the queue grew, and every paint drew the row under where the pointer was when that event was
 * QUEUED — the lag was the queue, and it grew with the speed of the hand.
 *
 * The fix is that a pass takes everything already queued and paints once: only the LAST motion in a burst can matter.
 * Here that is counted rather than argued — the menu says how many times it has painted its session, and a burst of
 * five motion events has to cost ONE more paint, with the highlight on the row the fifth named.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

/* **AN ITEM WITH NO ACTION IS ONE THE MENU'S UPDATE PASS DISABLES**, and a disabled row takes no highlight — so a test
 * about a highlight needs rows that could actually be chosen. This is the target they all point at. */
@interface AGMenuBurstTarget : NSObject
- (void)takeRow:(id)sender;
@end

@implementation AGMenuBurstTarget
- (void)takeRow:(id)sender
{
	(void)sender;
}
@end


static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* A move to the middle of a row. The menu's own geometry answers where that is — no test should re-derive the pitch.
 * The point is WINDOW-relative and the row rect is in the frame's screen space, which is why the origin comes off. */
static NSEvent *fn_move_to_row(NSMenu *menu, NSInteger row)
{
	NSRect frame = [menu cg_trackingFrame];
	NSRect rect = [menu cg_rowRectAtIndex:row inFrame:frame];
	NSPoint where = NSMakePoint(NSMidX(rect) - frame.origin.x, NSMidY(rect) - frame.origin.y);

	/* WINDOW ZERO IS THE PARENT'S OWN: an event that names no window is the menu's, which is the routing rule
	 * `-cg_trackOneEvent:` states. Nothing here needs a server to give the menu a window number. */
	return [NSEvent mouseEventWithType:NSMouseMoved location:where modifierFlags:0 timestamp:0.0
			      windowNumber:0 context:nil eventNumber:0 clickCount:0 pressure:0.0];
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Move"];
		AGMenuBurstTarget *target = [[[AGMenuBurstTarget alloc] init] autorelease];
		NSInteger before;
		NSInteger after;
		BOOL stillUp;
		int i;

		(void)[application finishLaunching];
		for (i = 0; i < 6; i++) {
			NSMenuItem *item = [menu addItemWithTitle:[NSString stringWithFormat:@"Row %d", i]
							  action:@selector(takeRow:)
						   keyEquivalent:@""];

			/* **A ROW THAT CANNOT BE CHOSEN DOES NOT LIGHT UP** — `-cg_itemTakesHighlight:` — and the menu's update
			 * pass disables an item with no target and no action. These rows point at one, the way a real menu's do. */
			[item setTarget:target];
		}
		[menu cg_beginSessionAt:NSMakePoint(200.0, 300.0)];
		check([menu cg_isTracking], "the session began");
		{
			NSRect f = [menu cg_trackingFrame];
			NSRect r = [menu cg_rowRectAtIndex:0 inFrame:f];

			printf("  (note: frame (%.0f,%.0f %.0fx%.0f) row0 (%.0f,%.0f %.0fx%.0f) pitch %.0f)\n",
			       (double)f.origin.x, (double)f.origin.y, (double)f.size.width, (double)f.size.height,
			       (double)r.origin.x, (double)r.origin.y, (double)r.size.width, (double)r.size.height,
			       (double)[menu cg_rowPitch]);
		}

		/* 1. ONE MOTION IS ONE PAINT, AND IT IS IMMEDIATE: the row under the pointer lights up on that event, not on
		 * the next one. */
		before = [menu cg_sessionRepaintCount];
		(void)[menu cg_trackOneEvent:fn_move_to_row(menu, 0)];
		after = [menu cg_sessionRepaintCount];
		check(after == before + 1, "a motion event paints the session once");
		check([[menu highlightedItem] isEqual:[[menu itemArray] objectAtIndex:0]],
		      "and the highlight is on the row under it by the time the event returns");

		/* 2. FIVE MOTION EVENTS ALREADY QUEUED ARE ONE PAINT. That is what a pointer in motion looks like: the loop
		 * wakes with one event and the rest are already behind it. */
		before = [menu cg_sessionRepaintCount];
		for (i = 0; i < 5; i++) {
			[application postEvent:fn_move_to_row(menu, i + 1) atStart:NO];
		}
		stillUp = [menu cg_trackEventBurst:nil using:application];
		after = [menu cg_sessionRepaintCount];
		check(stillUp, "the session is still up after a burst of motion");
		check(after == before + 1, "five queued motion events cost ONE repaint, not five");
		check([[menu highlightedItem] isEqual:[[menu itemArray] objectAtIndex:5]],
		      "and the highlight is on the row the LAST of them named");

		/* 3. AND AN IDLE PASS PAINTS NOTHING: the counter is the probe's, and a loop that repainted on every wake-up
		 * would be a menu that burns a core with the pointer still. */
		before = [menu cg_sessionRepaintCount];
		(void)[menu cg_trackEventBurst:nil using:application];
		check([menu cg_sessionRepaintCount] == before, "a pass with nothing queued paints nothing");

		[menu cancelTracking];
		[menu release];
		printf("menu_highlight_burst: %d case(s) failed\n", s_failed);
	}
	return s_failed == 0 ? 0 : 1;
}
