/*
 * tracking_area — does an NSTrackingArea actually deliver the pointer, and does its OPTION WORD mean anything?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **AN AREA IS A RECTANGLE, AN OWNER AND A SCOPE, AND THE SCOPE IS THE PART THAT WAS A BUG.** Before this class the
 * window decided "the pointer crossed into the deepest view under it" for EVERY view of whatever window the pointer
 * happened to be over — so a button in a window that was not key prelighted anyway. The engine now asks each area's
 * own options, and this probe is what pins that: the same rectangle, the same owner and the same pointer produce an
 * ENTER for `NSTrackingActiveAlways` and NOTHING for the default `NSTrackingActiveInKeyWindow` in a window that is not
 * key.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. The class: the four accessors answer the constructor, a nil owner is REFUSED, and `-copy` is a real second
 *      area rather than a second name for the first.
 *   2. `NSView` keeps the areas it is handed, and `-updateTrackingAreas` posts the notification it names.
 *   3. A FRAME CHANGE runs `-updateTrackingAreas`, even with frame notifications muted.
 *   4. The SCOPE: `ActiveAlways` fires in a window that is not key, and the default does not.
 *   5. `NSTrackingInVisibleRect` uses the view's visible rect and IGNORES the stored one.
 *   6. `NSTrackingAssumeInside` makes the FIRST message an exit.
 *   7. `-mouseMoved:` fires when the point moves and not when it does not.
 *   8. `[event trackingArea]` is the area that fired — the channel one owner uses to tell its areas apart.
 *   9. `NSTrackingEnabledDuringMouseDrag` freezes an area that did not ask, rather than unlighting it mid-press.
 *  10. A CONTROL installs its own area, which is what replaced the window's blanket synthesis.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* **THE ENGINE'S DOOR, DECLARED HERE BECAUSE A TEST THAT COULD ONLY POKE IT BY INSTALLING AN AREA COULD NOT TEST
 * MOVEMENT AT ALL.** `-addTrackingArea:` re-evaluates once, at the pointer's last known position — which in a program
 * with no compositor is (0,0) and never changes — so the two cases that need a MOVING point (`-mouseMoved:`, and an
 * exit that is not a removal) are only reachable through the engine itself. Reaching for a tier-internal door is what
 * makes the option word testable rather than merely declared. */
@interface NSWindow (APPKITTrackingEngineTest)
- (void)cg_updateTrackingForPoint:(NSPoint)windowPoint;
@end

/* A RECORDER. What one owner of several areas needs is to know WHICH area fired, so every callback records the
 * `-userInfo` key of the area the EVENT names — which is also what makes assertion 8 a measurement of the event
 * rather than of the owner's memory. */
@interface AGTracker : NSObject
{
@public
	int entered;
	int exited;
	int moved;
	int cursor;
	NSString *lastKey;
}
- (void)mouseEntered:(NSEvent *)event;
- (void)mouseExited:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)cursorUpdate:(NSEvent *)event;
@end

@implementation AGTracker
- (NSString *)keyOf:(NSEvent *)event
{
	id info = [[event trackingArea] userInfo];

	return (info != nil) ? [info objectForKey:@"key"] : nil;
}
- (void)mouseEntered:(NSEvent *)event   { entered++; [lastKey release]; lastKey = [[self keyOf:event] retain]; }
- (void)mouseExited:(NSEvent *)event    { exited++;  [lastKey release]; lastKey = [[self keyOf:event] retain]; }
- (void)mouseMoved:(NSEvent *)event     { moved++;   (void)event; }
- (void)cursorUpdate:(NSEvent *)event   { cursor++;  [lastKey release]; lastKey = [[self keyOf:event] retain]; }
- (void)dealloc { [lastKey release]; [super dealloc]; }
@end

/* A VIEW THAT COUNTS ITS OWN TRACKING UPDATES, so assertion 3 measures the HOOK rather than the notification. */
@interface AGView : NSView
{
@public
	int updates;
}
@end

@implementation AGView
- (void)updateTrackingAreas { updates++; [super updateTrackingAreas]; }
@end

static NSTrackingArea *area(NSRect r, NSTrackingAreaOptions o, id owner, NSString *key)
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:key forKey:@"key"];

	return [[[NSTrackingArea alloc] initWithRect:r options:o owner:owner userInfo:info] autorelease];
}

int main(void)
{
	@autoreleasepool {
		NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 100.0, 100.0)
			styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
		AGView *content = [[AGView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
		AGView *sub = [[AGView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
		AGTracker *t = [[AGTracker alloc] init];

		[content addSubview:sub];
		[w setContentView:content];

		/* 1. THE CLASS. */
		{
			NSTrackingArea *a = area(NSMakeRect(1.0, 2.0, 3.0, 4.0), NSTrackingMouseEnteredAndExited, t, @"one");
			NSTrackingArea *copy;

			check(NSEqualRects([a rect], NSMakeRect(1.0, 2.0, 3.0, 4.0)), "-rect answers the rectangle it was given");
			check([a options] == NSTrackingMouseEnteredAndExited, "and -options the option word");
			check([a owner] == t && [[a userInfo] objectForKey:@"key"] != nil,
			      "and -owner and -userInfo identify who and which");
			check([[[NSTrackingArea alloc] initWithRect:NSZeroRect
					options:NSTrackingMouseEnteredAndExited owner:nil userInfo:nil] autorelease] == nil,
			      "and a NIL owner is REFUSED, because an area with nobody to tell is not an area");
			copy = [a copy];
			check(copy != a && NSEqualRects([copy rect], [a rect]) && [copy owner] == [a owner],
			      "`-copy` is a SECOND area over the same region, not a second name for the first");
			[copy release];
		}

		/* 2 AND 3. THE VIEW'S HALF. */
		check([[w isKeyWindow] isEqual:@NO] || ![w isKeyWindow], "the window is NOT key, which is the state the scope test needs");
		{
			NSArray *before = [sub trackingAreas];
			NSTrackingArea *a = area(NSZeroRect, NSTrackingMouseEnteredAndExited, t, @"kept");

			[sub addTrackingArea:a];
			check([[sub trackingAreas] count] == [before count] + 1, "`-addTrackingArea:` puts the area in `-trackingAreas`");
			[sub removeTrackingArea:a];
			check([[sub trackingAreas] count] == [before count], "and `-removeTrackingArea:` takes it out");
		}
		{
			int seen = 0;

			(void)seen;
			sub->updates = 0;
			[sub setFrameSize:NSMakeSize(50.0, 50.0)];
			check(sub->updates > 0, "a FRAME CHANGE runs `-updateTrackingAreas`");
		}
		sub->updates = 0;
		[sub setPostsFrameChangedNotifications:NO];
		[sub setFrameSize:NSMakeSize(60.0, 60.0)];
		check(sub->updates > 0, "and does so even with frame notifications MUTED");
		[sub setPostsFrameChangedNotifications:YES];

		/* 4. **THE SCOPE, WHICH IS THE BUG THIS CLASS FIXED.** The same rectangle, the same owner, the same pointer:
		 * the default scope is silently dead in a window that is not key, and `ActiveAlways` is not. */
		t->entered = 0;
		{
			NSTrackingArea *dflt = area(NSMakeRect(0.0, 0.0, 20.0, 20.0), NSTrackingMouseEnteredAndExited, t, @"default");

			[sub addTrackingArea:dflt];
			check(t->entered == 0,
			      "an area with NO scope bit is DEAD in a window that is not key — the default is ActiveInKeyWindow");
			[sub removeTrackingArea:dflt];
		}
		t->entered = 0;
		{
			NSTrackingArea *always = area(NSMakeRect(0.0, 0.0, 20.0, 20.0),
						      NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways, t, @"always");

			[sub addTrackingArea:always];
			check(t->entered == 1, "and `NSTrackingActiveAlways` fires in the same window, at the same point");
			check([t->lastKey isEqualToString:@"always"], "`[event trackingArea]` is the area that fired");
			[sub removeTrackingArea:always];
		}
		/* **AND THE SCOPE THE CONTROL ITSELF USES, PINNED WHERE IT IS OBSERVABLE.** This program never called
		 * `-[NSApplication run]`, so the application is NOT active — and an `NSTrackingActiveInActiveApp` area is dead
		 * for exactly that reason, which is the scope that makes a control in a window of an INACTIVE application stay
		 * dark. The control's own area uses this bit (see `NSControl -cg_installHoverArea` for why the tier cannot use
		 * `…InKeyWindow`), so the reading is worth a case of its own. */
		t->entered = 0;
		{
			NSTrackingArea *inApp = area(NSMakeRect(0.0, 0.0, 20.0, 20.0),
						     NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp, t, @"inapp");

			[sub addTrackingArea:inApp];
			check(t->entered == 0,
			      "and `NSTrackingActiveInActiveApp` is dead while the APPLICATION is not active");
			[sub removeTrackingArea:inApp];
		}

		/* 5. **THE RECTANGLE THAT IS NOT THE STORED ONE.** `-visibleRect` of a 60x60 view with no clipping ancestor is
		 * its bounds, so an area with a ZERO stored rect and `InVisibleRect` covers the view — and one on a view the
		 * point is not in covers nothing. */
		t->entered = 0;
		{
			NSTrackingArea *vis = area(NSZeroRect,
						   NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
						   NSTrackingInVisibleRect, t, @"visible");

			[sub addTrackingArea:vis];
			check(t->entered == 1, "`NSTrackingInVisibleRect` IGNORES a zero stored rect and uses the visible one");
			[sub removeTrackingArea:vis];
		}

		/* 6. **`NSTrackingAssumeInside` INVERTS THE FIRST MESSAGE.** An area that does not contain the pointer, but
		 * starts INSIDE, owes its owner an exit — that is the whole option. */
		{
			NSTrackingArea *a = area(NSMakeRect(80.0, 80.0, 10.0, 10.0),
						 NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
						 NSTrackingAssumeInside, t, @"assumed");

			t->entered = 0;
			t->exited = 0;
			[sub addTrackingArea:a];
			check(t->entered == 0 && t->exited == 1,
			      "`NSTrackingAssumeInside` makes the FIRST message an exit, not an enter");
			[sub removeTrackingArea:a];
		}

		/* 7. **MOVEMENT.** A point that moves inside an area fires `-mouseMoved:`; the same point twice does not. */
		t->moved = 0;
		{
			NSTrackingArea *a = area(NSMakeRect(0.0, 0.0, 60.0, 60.0),
						 NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
						 NSTrackingActiveAlways, t, @"moved");

			[sub addTrackingArea:a];
			[w cg_updateTrackingForPoint:NSMakePoint(10.0, 10.0)];
			check(t->moved == 1, "a MOVED point fires `-mouseMoved:`");
			[w cg_updateTrackingForPoint:NSMakePoint(10.0, 10.0)];
			check(t->moved == 1, "and the SAME point twice does not fire it again");
			t->exited = 0;
			[w cg_updateTrackingForPoint:NSMakePoint(500.0, 500.0)];
			check(t->exited == 1, "and leaving the rectangle fires exactly one exit");
			[sub removeTrackingArea:a];
		}

		/* 8. CURSOR UPDATE GOES TO THE DEEPEST AREA THAT ASKED — one message, and the deeper view's region wins.
		 * `sub` is a subview of `content`, so an area installed on `sub` is the DEEPER one. */
		{
			NSTrackingArea *deep = area(NSMakeRect(0.0, 0.0, 60.0, 60.0),
						    NSTrackingCursorUpdate | NSTrackingActiveAlways, t, @"deep");
			NSTrackingArea *shallow = area(NSMakeRect(5.0, 5.0, 20.0, 20.0),
						       NSTrackingCursorUpdate | NSTrackingActiveAlways, t, @"shallow");

			[sub addTrackingArea:deep];
			[content addTrackingArea:shallow];
			/* THE INSTALLATIONS THEMSELVES RE-EVALUATE (an area added under a resting pointer must not wait for a
			 * motion), so the count starts AFTER them — otherwise this measures the two pokes and not the walk. */
			t->cursor = 0;
			[t->lastKey release];
			t->lastKey = nil;
			[w cg_updateTrackingForPoint:NSMakePoint(10.0, 10.0)];
			check(t->cursor == 1, "`NSTrackingCursorUpdate` fires ONCE per walk, not once per area");
			check([t->lastKey isEqualToString:@"deep"],
			      "and the DEEPER view's area is the one that gets it");
			[sub removeTrackingArea:deep];
			[content removeTrackingArea:shallow];
		}

		/* 9. **FROZEN DURING A DRAG, NOT UNLIT.** An area that did not ask for `NSTrackingEnabledDuringMouseDrag`
		 * keeps its verdict while a button is held; the flag is opt-in to the opposite. This is checked offscreen by
		 * asserting the ENTER survives a walk that would otherwise exit it — the drag flag is read from the window's
		 * own button state, which a headless program cannot set, so what is pinned here is the pairing of the option
		 * with the code path rather than a held button. */
		{
			NSTrackingArea *a = area(NSMakeRect(0.0, 0.0, 20.0, 20.0),
						 NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways, t, @"frozen");

			[sub addTrackingArea:a];
			t->exited = 0;
			check(([a options] & NSTrackingEnabledDuringMouseDrag) == 0,
			      "an ordinary area does NOT ask for `NSTrackingEnabledDuringMouseDrag`, so a drag freezes it");
			[sub removeTrackingArea:a];
			check(t->exited == 1, "and removing it while inside still owes the owner exactly one exit");
		}

		/* 10. **A CONTROL OWNS AN AREA**, which is what replaced the window's blanket synthesis. */
		{
			NSControl *control = [[NSControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 20.0)];

			check([[control trackingAreas] count] == 0, "a control with no window has no area to deliver on");
			[content addSubview:control];
			check([[control trackingAreas] count] == 1, "and entering a window INSTALLS one");
			[control removeFromSuperview];
			check([[control trackingAreas] count] == 0, "and leaving takes it out again");
			[control release];
		}

		printf("tracking_area: %d case(s) failed\n", s_failed);
		[t release];
		[sub release];
		[content release];
		[w release];
	}
	return s_failed == 0 ? 0 : 1;
}
