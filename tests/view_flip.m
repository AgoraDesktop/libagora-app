/*
 * view_flip — the y direction across the WINDOW's boundary, which is the one transition no view walk owned.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A WINDOW'S SYSTEM IS Y-UP AND A ROOT VIEW'S MAY BE Y-DOWN, AND THAT IS A FLIP LIKE ANY OTHER.** `-convertPoint:`
 * walked the superview chain and stopped at the root, so the last boundary — root to window — was the one place the
 * flip was never applied: `fn_same_y_direction` answers "same" for a view with no superview, and both walks end there.
 * The consequence is not subtle: in a window whose content view is FLIPPED (Amp's skin view is), every pointer y
 * arrived mirrored about the window's height — a click on a control hit the element vertically opposite it, so the
 * buttons did nothing, the title bar would not drag, and hover highlighted the wrong control. MEASURED in a nested
 * session: a click on the transport row at layout y=157 arrived as y=68 in a 225-point window.
 *
 * These cases pin the arithmetic at that boundary, with no window object at all: `nil` means the window's system, and
 * the conversions only need the root's bounds to know how tall the mirror is.
 *
 * (The ivar is `_upsideDown` because `NSView` already has `_flipped` — the same duplicate-member trap the skin view hit
 * with `_hidden`: a subclass may not name an ivar the framework has.)
 */
#import <AppKit/NSView.h>
#import <Foundation/NSArray.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("%s  %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

@interface FNRoot : NSView
{
	BOOL _upsideDown;
}
- (void)setFlipped:(BOOL)flipped;
@end

@implementation FNRoot
- (void)setFlipped:(BOOL)flipped { _upsideDown = flipped; }
- (BOOL)isFlipped { return _upsideDown; }
@end

static BOOL fn_point_is(NSPoint p, CGFloat x, CGFloat y)
{
	return p.x == x && p.y == y;
}

int main(void)
{
	FNRoot *window = [[FNRoot alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 100.0)];

	/* **AN UNFLIPPED ROOT SHARES THE WINDOW'S DIRECTION**, so nothing mirrors: the boundary is transparent. */
	[window setFlipped:NO];
	check(fn_point_is([window convertPoint:NSMakePoint(10.0, 20.0) fromView:nil], 10.0, 20.0),
	      "an unflipped root takes a window point unchanged");
	check(fn_point_is([window convertPoint:NSMakePoint(10.0, 20.0) toView:nil], 10.0, 20.0),
	      "and hands one back unchanged");

	/* **A FLIPPED ROOT MIRRORS ABOUT ITS OWN HEIGHT**, which is the whole of the fix. */
	[window setFlipped:YES];
	check(fn_point_is([window convertPoint:NSMakePoint(10.0, 0.0) fromView:nil], 10.0, 100.0),
	      "the window's bottom is a flipped root's top");
	check(fn_point_is([window convertPoint:NSMakePoint(10.0, 100.0) fromView:nil], 10.0, 0.0),
	      "and its top is the root's bottom");
	check(fn_point_is([window convertPoint:NSMakePoint(10.0, 20.0) toView:nil], 10.0, 80.0),
	      "a root point converts back the same way");
	check(fn_point_is([window convertPoint:[window convertPoint:NSMakePoint(7.0, 23.0) fromView:nil] toView:nil],
	                  7.0, 23.0),
	      "the two conversions are inverses across the boundary");

	/* **AND A CHILD BELOW THE ROOT IS REACHED THROUGH IT**, so a point that crosses two flips (window → flipped root
	 * → flipped child, which agree) has exactly one mirror in it. */
	{
		NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(10.0, 20.0, 30.0, 40.0)];
		NSPoint inChild;

		[child setFlipped:YES];
		[window addSubview:child];

		/* The window's bottom-left is the root's (0,100), which in the child's own space is (0-10, 100-20). */
		inChild = [child convertPoint:NSMakePoint(0.0, 0.0) fromView:nil];
		check(fn_point_is(inChild, -10.0, 80.0),
		      "a window point reaches a child through the root's flip");

		/* And the child's own origin is that same corner in the window: (10, 20) → root (10,20) → window (10,80). */
		check(fn_point_is([child convertPoint:NSMakePoint(0.0, 0.0) toView:nil], 10.0, 80.0),
		      "and the child's origin comes back out the same way");
		[child release];
	}

	[window release];

	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
