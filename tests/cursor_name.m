/*
 * cursor_name — the pointer's NAME, which is the only thing about a cursor a display can act on.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE BUG THIS FILE EXISTS FOR WAS "the pointer never changes".** A web view installed the right `NSCursor` for a link
 * and for a paragraph of text, the window resolved the right one on every motion — and nothing changed on the glass,
 * because every shared `NSCursor` was an object with NO IMAGE and nothing else: twenty-one singletons that a display
 * could not tell apart. What a cursor carries now is its NAME, the Xcursor vocabulary the desktop's theme is written in,
 * and `-[NSWindow cg_applyCursor:]` is the one place it becomes a request (`AGWindowSetCursor`).
 *
 * **SO TWO THINGS ARE ASSERTED HERE, AND NEITHER NEEDS A COMPOSITOR.** First the mapping: every shared cursor answers a
 * name, and every one of those names is a file in the vendored Vimix theme — checked against the theme's own directory
 * rather than against a second copy of the table, because a typo in a name is exactly the failure that would otherwise
 * be invisible (the compositor falls back to the arrow and says nothing to the client).
 *
 * Second the WINDOW's half, driven through the real seam entry point (`-cg_handleSeamEvent:`) with pointer events this
 * file builds: a motion resolves through the view tree, installs the cursor and asks for its name; a second motion over
 * the same ground asks for NOTHING, which is the guard against a request per motion at sixty events a second; a drag
 * leaves the cursor alone, because the drag's owner has already pushed its own; and a view that changes its answer under
 * a RESTING pointer — a page finishing a load, a player hiding its pointer — reaches the compositor without a motion,
 * which is what `-invalidateCursorRectsForView:` is for.
 *
 *   cursor_name [THEME-CURSORS-DIR]
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* **THE THREE PRIVATE DOORS THIS FILE DRIVES, declared the way the tree's other probes declare them.** The seam entry
 * point is what a real window's event handler calls; the other two are the bookkeeping the claim "and it does not ask
 * again" is measured by. None of them is public API — see `NSWindow.m`'s own extension — and a probe that could only
 * reach the public surface could not see a request at all. */
@interface NSWindow (AGCursorNameProbe)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
- (NSString *)cg_sentCursorName;
- (NSUInteger)cg_cursorRequests;
@end

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* **A VIEW WHOSE ANSWER CAN CHANGE, WHICH IS THE WHOLE OF THE RESTING-POINTER CASE.** `-resetCursorRects` is the hook
 * AppKit gives a view for "these are the cursors over my ground"; `cursorForLeftHalf` is this probe's stand-in for a page
 * that has just been told what is under the pointer. */
@interface AGCursorNameView : NSView
{
	BOOL _leftIsHand;
}
- (void)setLeftIsHand:(BOOL)flag;
@end

@implementation AGCursorNameView

- (BOOL)isFlipped
{
	return NO;
}

- (void)setLeftIsHand:(BOOL)flag
{
	_leftIsHand = flag;
}

- (void)resetCursorRects
{
	/* TWO HALVES, FULL HEIGHT: a point in either one is unambiguous, and neither is near an edge (where the window's own
	 * resize handle answers first — a rule of its own, tested by `appkit_window_resize`). */
	[self addCursorRect:NSMakeRect(0, 0, 200, 300)
		     cursor:(_leftIsHand ? [NSCursor pointingHandCursor] : [NSCursor IBeamCursor])];
	[self addCursorRect:NSMakeRect(200, 0, 200, 300)
		     cursor:(_leftIsHand ? [NSCursor IBeamCursor] : [NSCursor pointingHandCursor])];
}

@end

/* A POINTER EVENT, built the way the seam builds one: window-relative output coordinates, measured DOWN. */
static AGEvent motion_event(int x, int y)
{
	AGEvent e;

	memset(&e, 0, sizeof e);
	e.type = AGEventPointerMotion;
	e.x = x;
	e.y = y;
	return e;
}

static AGEvent button_event(int x, int y, int pressed)
{
	AGEvent e;

	memset(&e, 0, sizeof e);
	e.type = AGEventPointerButton;
	e.x = x;
	e.y = y;
	e.pressed = pressed;
	e.button = 0x110;	/* BTN_LEFT, which is what the seam carries */
	e.modifiers = 0;
	return e;
}

/* THE ONE CHECK THAT CANNOT BE MADE AGAINST A SECOND COPY OF THE TABLE: does the theme have this name? */
static int theme_has(const char *directory, NSString *name)
{
	char path[4096];

	if (directory == NULL || name == nil) {
		return 1;	/* nothing to check against, and a nil name is the documented "no name" answer */
	}
	snprintf(path, sizeof path, "%s/%s", directory, [name UTF8String]);
	return access(path, R_OK) == 0;
}

int main(int argc, char **argv)
{
	const char *cursors = (argc > 1) ? argv[1] : NULL;
	NSWindow *window;
	AGCursorNameView *view;
	AGEvent e;
	NSCursor *imageCursor;
	NSImage *image;

	printf("cursor_name: the pointer's name, from the cursor to the window server\n");

	/* **AND THE ARTWORK HAS TO BE WHERE THIS TEST WAS TOLD IT IS**, or every name below fails for a reason that says
	 * nothing about the mapping — one clear line rather than seventeen. The theme is DATA this tree vendors, and the
	 * alternative (silently skipping the check) would make the strongest assertion in this file vacuous. */
	if (cursors != NULL) {
		check(access(cursors, R_OK) == 0, "the vendored Vimix theme is where the test was told it is");
	}

	/* 1. **EVERY SHARED CURSOR ANSWERS A NAME, AND THE ONES THAT MATTER ARE THE ONES A PAGE ASKS FOR.** The four here are
	 * the whole of the acceptance test one layer up — a link, a paragraph, a divider and a refused drop — and the rest of
	 * the class follows the same shape. */
	check([[NSCursor arrowCursor].name isEqualToString:@"left_ptr"], "the arrow's name is the theme's arrow");
	check([[NSCursor IBeamCursor].name isEqualToString:@"text"], "the I-beam's name is the theme's text cursor");
	check([[NSCursor pointingHandCursor].name isEqualToString:@"pointer"], "the hand's name is the theme's pointer");
	check([[NSCursor operationNotAllowedCursor].name isEqualToString:@"not-allowed"],
	      "and the refused drop is `not-allowed`");

	/* 2. **AND EVERY NAME IS A CURSOR THE VENDORED THEME ACTUALLY CARRIES.** A name the theme does not have costs a silent
	 * fallback to the arrow — a pointer that simply does not change, which is the failure this whole file is about — so the
	 * table is checked against the artwork rather than against itself. */
	{
		NSCursor *all[] = {
			[NSCursor arrowCursor], [NSCursor IBeamCursor], [NSCursor pointingHandCursor],
			[NSCursor closedHandCursor], [NSCursor openHandCursor], [NSCursor resizeLeftCursor],
			[NSCursor resizeRightCursor], [NSCursor resizeLeftRightCursor], [NSCursor resizeUpCursor],
			[NSCursor resizeDownCursor], [NSCursor resizeUpDownCursor], [NSCursor crosshairCursor],
			[NSCursor operationNotAllowedCursor], [NSCursor dragLinkCursor], [NSCursor dragCopyCursor],
			[NSCursor contextualMenuCursor], [NSCursor cg_resizeNorthWestSouthEastCursor],
			[NSCursor cg_resizeNorthEastSouthWestCursor]
		};
		size_t i;
		int named = 0, missing = 0;

		for (i = 0; i < sizeof all / sizeof all[0]; i++) {
			NSString *name = [all[i] name];

			if (name == nil) {
				missing++;
				continue;
			}
			named++;
			if (!theme_has(cursors, name)) {
				printf("  FAIL  `%s` is not a cursor in %s\n", [name UTF8String],
				       cursors != NULL ? cursors : "(no theme given)");
				s_failed++;
			}
		}
		check(missing == 0, "every shared cursor in this set answers a name");
		check(named == 18, "and the eighteen of them are the theme's own cursors");

		/* `disappearingItemCursor` IS THE DOCUMENTED EXCEPTION, and it is asserted so that "no name" stays a decision
		 * rather than an oversight: a poof of smoke is not in an Xcursor theme, and the default arrow is a better answer
		 * than the `no-drop` entry, which means a refused drop. */
		check([[NSCursor disappearingItemCursor] name] == nil,
		      "the disappearing-item cursor has NO name, because no theme has that shape");
	}

	/* 3. **AND A CURSOR MADE FROM AN IMAGE HAS NO NAME EITHER**, which is the honest answer for a custom pointer whose
	 * pixels cannot cross the protocol yet: the window asks for the compositor's DEFAULT, so the theme's arrow shows
	 * instead of a shape invented for an image nobody can see. */
	image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
	imageCursor = [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(1, 1)];
	check([imageCursor name] == nil, "a cursor made from an image has no name, so the default is asked for");
	[imageCursor release];
	[image release];

	/* 4. **THE WINDOW'S HALF, THROUGH THE REAL EVENT DOOR.** A borderless window so that the seam's coordinates and the
	 * content view's are the same pair, which is what makes the two halves below unambiguous. */
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
					     styleMask:NSBorderlessWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	view = [[AGCursorNameView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
	[view setLeftIsHand:YES];
	[window setContentView:view];
	[window resetCursorRects];
	check([window cg_cursorRequests] == 0, "a window whose pointer has never moved has asked for nothing");

	/* the left half says hand; y=150 is 300-150 in the seam's own downward coordinates */
	e = motion_event(50, 150);
	[window cg_handleSeamEvent:&e];
	check([[NSCursor currentCursor] name] != nil && [[[NSCursor currentCursor] name] isEqualToString:@"pointer"],
	      "a motion over the hand's ground INSTALLS the hand");
	check([window cg_cursorRequests] == 1 && [[window cg_sentCursorName] isEqualToString:@"pointer"],
	      "and asks the window server for the hand's NAME");

	/* 5. **AND THE SAME GROUND AGAIN ASKS FOR NOTHING.** This is the half that keeps a motion from being a request: sixty
	 * events a second over one link is one request, not sixty. */
	e = motion_event(60, 140);
	[window cg_handleSeamEvent:&e];
	check([window cg_cursorRequests] == 1, "a second motion over the same cursor asks NOTHING — a request per motion is noise");

	/* 6. **A DIFFERENT VIEW'S CURSOR IS A DIFFERENT NAME.** The right half says I-beam. */
	e = motion_event(350, 150);
	[window cg_handleSeamEvent:&e];
	check([[window cg_sentCursorName] isEqualToString:@"text"] && [window cg_cursorRequests] == 2,
	      "moving onto the text half asks for `text`, once");

	/* 7. **A DRAG LEAVES THE CURSOR ALONE.** The owner of a drag has already pushed its own resize cursor, so the window
	 * must not fight it — measured by asking for nothing while a button is down, which is the behaviour that was there
	 * before the name existed. */
	e = button_event(350, 150, 1);
	[window cg_handleSeamEvent:&e];
	e = motion_event(50, 150);
	[window cg_handleSeamEvent:&e];
	check([window cg_cursorRequests] == 2 && [[window cg_sentCursorName] isEqualToString:@"text"],
	      "a motion with a button down does NOT resolve the cursor — the drag's owner has already said what it is");
	e = button_event(50, 150, 0);
	[window cg_handleSeamEvent:&e];
	/* and the release gives the hover answer back: the left half is the hand's */
	e = motion_event(50, 150);
	[window cg_handleSeamEvent:&e];
	check([window cg_cursorRequests] == 3 && [[window cg_sentCursorName] isEqualToString:@"pointer"],
	      "and the RELEASE resumes the hover resolution — the left half is the hand again");

	/* 8. **AND A VIEW THAT CHANGES ITS ANSWER UNDER A RESTING POINTER REACHES THE SERVER WITHOUT A MOTION.** The hand is
	 * in the left half and stops; the view is then told the left half is text now — which is what a page says when the
	 * engine announces a different cursor, and what `-invalidateCursorRectsForView:` is the door for. */
	[view setLeftIsHand:NO];
	[window invalidateCursorRectsForView:view];
	check([window cg_cursorRequests] == 4 && [[window cg_sentCursorName] isEqualToString:@"text"],
	      "invalidating the rects re-resolves the pointer where it RESTS, so a page's cursor changes with no motion");

	/* and invalidating when nothing changed asks for nothing, which is the dedup again on a different path */
	[window invalidateCursorRectsForView:view];
	check([window cg_cursorRequests] == 4, "and invalidating again without a change asks for nothing");

	/* 9. **AND THE WINDOW'S OWN EDGES, WHICH ARE THE ONE CURSOR THIS TIER RESOLVES WITHOUT A VIEW'S HELP.** A
	 * RESIZABLE window answers a resize cursor within five points of an edge, and the name it asks for is the theme's:
	 * `sb_h_double_arrow` for a side, `sb_v_double_arrow` for the top or the bottom. This is an ordinary `NSWindow`
	 * with a title bar, so the frame is taller than its content and the point has to be flipped with the FRAME's
	 * height — the same conversion the window's own dispatch does. */
	{
		NSWindow *framed = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
							       styleMask:(NSTitledWindowMask | NSResizableWindowMask)
								 backing:NSBackingStoreBuffered
								   defer:NO];
		NSView *empty = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
		CGFloat frameHeight;

		[framed setContentView:empty];
		frameHeight = [framed frame].size.height;

		/* the LEFT edge, at mid height */
		e = motion_event(2, (int)(frameHeight - 150.0));
		[framed cg_handleSeamEvent:&e];
		check([[framed cg_sentCursorName] isEqualToString:@"sb_h_double_arrow"],
		      "a pointer two points from the LEFT edge asks for the horizontal resize cursor");

		/* the BOTTOM edge, mid width */
		e = motion_event(200, (int)(frameHeight - 2.0));
		[framed cg_handleSeamEvent:&e];
		check([[framed cg_sentCursorName] isEqualToString:@"sb_v_double_arrow"],
		      "and two points from the BOTTOM edge asks for the vertical one");

		/* **AND EVERY CORNER IS A DIAGONAL, WHICH IT WAS NOT.** A press on a corner has always started a resize, and the
		 * pointer there used to be the arrow: the era's public cursor set has a left-right and an up-down shape and nothing
		 * diagonal, so `fn_resizeCursor` answered nil and the handle said "nothing here". The corner squares are twelve
		 * points, and each pair of bands has to answer the diagonal that joins it. */
		e = motion_event(2, (int)(frameHeight - 2.0));
		[framed cg_handleSeamEvent:&e];
		check([[framed cg_sentCursorName] isEqualToString:@"nesw-resize"],
		      "the BOTTOM-LEFT corner is the NE-SW diagonal, which is the one that joins it to the top-right");

		e = motion_event(398, (int)(frameHeight - 2.0));
		[framed cg_handleSeamEvent:&e];
		check([[framed cg_sentCursorName] isEqualToString:@"nwse-resize"],
		      "and the BOTTOM-RIGHT corner is the NW-SE one");

		e = motion_event(398, 2);
		[framed cg_handleSeamEvent:&e];
		check([[framed cg_sentCursorName] isEqualToString:@"nesw-resize"],
		      "the TOP-RIGHT is the same diagonal as the bottom-left, as it must be");

		e = motion_event(2, 2);
		[framed cg_handleSeamEvent:&e];
		check([[framed cg_sentCursorName] isEqualToString:@"nwse-resize"],
		      "and the TOP-LEFT the other, so NO corner is the arrow any more");

		/* the middle is the arrow again */
		e = motion_event(200, (int)(frameHeight - 150.0));
		[framed cg_handleSeamEvent:&e];
		check([[framed cg_sentCursorName] isEqualToString:@"left_ptr"],
		      "and the middle of the same window is the arrow, so the edge is not the whole frame");

		/* AND A WINDOW THAT MAY NOT BE RESIZED HAS NO EDGE TO TAKE. */
		{
			NSWindow *fixed = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
								      styleMask:NSTitledWindowMask
									backing:NSBackingStoreBuffered
									  defer:NO];
			NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];

			[fixed setContentView:plain];
			e = motion_event(2, (int)([fixed frame].size.height - 150.0));
			[fixed cg_handleSeamEvent:&e];
			check([[fixed cg_sentCursorName] isEqualToString:@"left_ptr"],
			      "and an unresizable window's edge is the arrow, because the style mask is the question");
			[fixed setContentView:nil];
			[plain release];
			[fixed release];
		}

		[framed setContentView:nil];
		[empty release];
		[framed release];
	}

	[window setContentView:nil];
	[view release];
	[window release];

	printf("cursor_name: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
