/*
 * drawer — NSDrawer: the child window, the four states, the geometry and the user's resize.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE MEASURES THE WINDOW, BECAUSE THE DRAWER IS ONE.** Every geometry check reads the FRAME of the child
 * window that holds the content view, not a stored number: a drawer whose `-contentSize` round-trips but whose panel is
 * laid out somewhere else would pass a value test and be wrong on the glass. The parent is a real, offscreen
 * `NSWindow` — no compositor is needed, because a window's frame is this object's own geometry and ordering is the only
 * thing that asks a server.
 *
 * WHAT IS ASSERTED, and the sender each one names:
 *
 *   1. The defaults: a closed drawer on its preferred edge, the content size it was made with, no parent and no
 *      content view; a minimum of zero and an effectively unbounded maximum.
 *   2. The content view is the CHILD WINDOW's content view, and the child is borderless.
 *   3. The parent relationship: `-setParentWindow:` registers in `-drawers`, the parent RETAINS the drawer (a released
 *      drawer is still listed and still usable), and detaching unregisters.
 *   4. Open: the states are observably OPENING inside the Will announcement and OPEN inside the Did one; both the
 *      notification center and the delegate are told; the child is attached to the parent.
 *   5. Geometry and pin: a side drawer is 90% of the parent's height, centred on its vertical axis, with the edge
 *      against the parent tucked 20 points under it AND ADDED TO THE WINDOW, so the content view is inset by the strip
 *      and the visible panel is the full content width; a top/bottom drawer keeps the spanning width; the window shares
 *      the parent's level (the layer ordering is the compositor's, so this probe checks the level and the frame); and a
 *      drawer of an offscreen, non-key parent is attached but not visible.
 *   6. The permission doors: `-drawerShouldOpen:` NO changes nothing; `-drawerShouldClose:` NO leaves it open.
 *   7. Close: the reverse states, the child detached, and `-toggle:`/`-open:`/`-close:` as the action spellings.
 *   8. The edge preference: a closed drawer's edge follows the preference, an open one's does not.
 *   9. The user's resize: the proposal is clamped to the minimum and maximum BEFORE the delegate sees it, the
 *      delegate's answer is what lands, and a programmatic `-setContentSize:` is NOT limited by either.
 *  10. A drawer with no parent refuses to open, a parent swap moves the child, and a close attempted from inside
 *      `-drawerWillOpen:` is ignored because a transition owns itself.
 *
 * The VISIBILITY rule — parent visible, key and in an active application — needs glass, so it lives in
 * `tests/drawer_visibility.m` and runs under the headless compositor.
 */
#import <AppKit/NSDrawer.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
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

static int rect_equal(NSRect a, NSRect b)
{
	return a.origin.x == b.origin.x && a.origin.y == b.origin.y
		&& a.size.width == b.size.width && a.size.height == b.size.height;
}

/* ============================================================================================ *
 * THE DELEGATE, WHICH RECORDS WHAT IT WAS ASKED AND WHAT THE STATE WAS WHEN IT WAS ASKED       *
 * ============================================================================================ */
@interface AGDrawerDelegate : NSObject <NSDrawerDelegate>
{
@public
	BOOL shouldOpen;
	BOOL shouldClose;
	BOOL closeFromWillOpen;
	BOOL resizeAsked;
	NSSize lastProposed;
	NSSize resizeAnswer;
	NSMutableArray *events;		/* "willOpen:1", "didOpen:2", … */
}
@end

@implementation AGDrawerDelegate

- (id)init
{
	self = [super init];
	if (self != nil) {
		shouldOpen = YES;
		shouldClose = YES;
		events = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[events release];
	[super dealloc];
}

- (BOOL)drawerShouldOpen:(NSDrawer *)sender
{
	(void)sender;
	return shouldOpen;
}

- (BOOL)drawerShouldClose:(NSDrawer *)sender
{
	(void)sender;
	return shouldClose;
}

- (NSSize)drawerWillResizeContents:(NSDrawer *)sender toSize:(NSSize)contentSize
{
	(void)sender;
	resizeAsked = YES;
	lastProposed = contentSize;
	return resizeAnswer;
}

- (void)drawerWillOpen:(NSNotification *)notification
{
	NSDrawer *drawer = [notification object];

	[events addObject:[NSString stringWithFormat:@"willOpen:%d", (int)[drawer state]]];
	if (closeFromWillOpen) {
		[drawer close];
	}
}

- (void)drawerDidOpen:(NSNotification *)notification
{
	NSDrawer *drawer = [notification object];

	[events addObject:[NSString stringWithFormat:@"didOpen:%d", (int)[drawer state]]];
}

- (void)drawerWillClose:(NSNotification *)notification
{
	NSDrawer *drawer = [notification object];

	[events addObject:[NSString stringWithFormat:@"willClose:%d", (int)[drawer state]]];
}

- (void)drawerDidClose:(NSNotification *)notification
{
	NSDrawer *drawer = [notification object];

	[events addObject:[NSString stringWithFormat:@"didClose:%d", (int)[drawer state]]];
}

@end

/* ============================================================================================ *
 * AND A CENTER OBSERVER, BECAUSE THE FOUR ANNOUNCEMENTS HAVE TWO FORMS                          *
 * ============================================================================================ */
@interface AGDrawerObserver : NSObject
{
@public
	NSMutableArray *names;
	id lastObject;
}
@end

@implementation AGDrawerObserver

- (id)init
{
	self = [super init];
	if (self != nil) {
		names = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[names release];
	[super dealloc];
}

- (void)note:(NSNotification *)notification
{
	[names addObject:[notification name]];
	lastObject = [notification object];
}

@end

int main(void)
{
	@autoreleasepool {
		NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(100.0, 100.0, 400.0, 300.0)
							      styleMask:NSBorderlessWindowMask
								backing:NSBackingStoreBuffered
								  defer:NO];
		NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 200.0)];
		NSDrawer *drawer = [[NSDrawer alloc] initWithContentSize:NSMakeSize(120.0, 200.0)
							    preferredEdge:NSMinXEdge];
		AGDrawerDelegate *delegate = [[AGDrawerDelegate alloc] init];
		AGDrawerObserver *observer = [[AGDrawerObserver alloc] init];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

		/* 1. THE DEFAULTS. */
		check([parent frame].origin.x == 100.0 && [parent frame].size.width == 400.0,
		      "the test parent's borderless frame is its content rect");
		check([drawer state] == NSDrawerClosedState, "a fresh drawer is closed");
		check([drawer edge] == NSMinXEdge && [drawer preferredEdge] == NSMinXEdge,
		      "on its preferred edge");
		check([drawer contentSize].width == 120.0 && [drawer contentSize].height == 200.0,
		      "with the content size it was made with");
		check([drawer minContentSize].width == 0.0 && [drawer minContentSize].height == 0.0,
		      "a zero minimum");
		check([drawer maxContentSize].width > 1000000.0, "and an effectively unbounded maximum");
		check([drawer leadingOffset] == 0.0 && [drawer trailingOffset] == 0.0,
		      "and no offsets");
		check([drawer parentWindow] == nil && [drawer contentView] == nil && [drawer delegate] == nil,
		      "with no parent, no content view and no delegate");

		/* 2. THE CONTENT VIEW IS THE CHILD WINDOW'S. */
		[drawer setContentView:content];
		check([drawer contentView] == content, "`-setContentView:` is answered back by `-contentView`");
		check([content window] != nil, "and the view has a window — the drawer's own, not the parent's");
		check([[content window] styleMask] == NSBorderlessWindowMask, "which is borderless");
		check([[content window] parentWindow] == nil, "and not yet attached to anything");

		/* 3. THE PARENT, ITS LIST, AND WHO OWNS WHOM. */
		[drawer setParentWindow:parent];
		check([drawer parentWindow] == parent, "`-setParentWindow:` is answered by `-parentWindow`");
		check([[parent drawers] count] == 1 && [[parent drawers] containsObject:drawer],
		      "and registers the drawer in the window's `-drawers`");
		{
			NSDrawer *second = [[NSDrawer alloc] initWithContentSize:NSMakeSize(40.0, 40.0)
								    preferredEdge:NSMaxYEdge];
			NSDrawer *claimed;

			[second setParentWindow:parent];
			check([[parent drawers] count] == 2, "a second drawer joins the same list");
			/* **THE PARENT RETAINS THE DRAWER, SO THE CALLER'S RELEASE DOES NOT DESTROY IT.** The list is the
			 * owner Apple documents; the pointer is still valid because the list holds it. */
			[second release];
			claimed = [[parent drawers] lastObject];
			check(claimed == second, "the parent's list still holds a drawer the caller released");
			[claimed setParentWindow:nil];
			check([[parent drawers] count] == 1, "and detaching unregisters it");
		}

		/* 4. OPEN: THE TWO STATES ARE OBSERVABLE INSIDE THE TWO ANNOUNCEMENTS. */
		[center addObserver:observer selector:@selector(note:) name:NSDrawerWillOpenNotification object:nil];
		[center addObserver:observer selector:@selector(note:) name:NSDrawerDidOpenNotification object:nil];
		[center addObserver:observer selector:@selector(note:) name:NSDrawerWillCloseNotification object:nil];
		[center addObserver:observer selector:@selector(note:) name:NSDrawerDidCloseNotification object:nil];
		[drawer setDelegate:delegate];
		[drawer setLeadingOffset:0.0];
		[drawer setTrailingOffset:0.0];
		[drawer setContentSize:NSMakeSize(120.0, 200.0)];
		[drawer open];
		check([drawer state] == NSDrawerOpenState, "`-open` leaves the drawer open");
		check([delegate->events count] == 2
		      && [[delegate->events objectAtIndex:0] isEqual:@"willOpen:1"]
		      && [[delegate->events objectAtIndex:1] isEqual:@"didOpen:2"],
		      "the delegate sees OPENING inside Will and OPEN inside Did");
		check([observer->names count] == 2
		      && [[observer->names objectAtIndex:0] isEqual:NSDrawerWillOpenNotification]
		      && [[observer->names objectAtIndex:1] isEqual:NSDrawerDidOpenNotification],
		      "and the notification center sees the same pair");
		check(observer->lastObject == drawer, "whose object is the drawer");

		/* 5. THE GEOMETRY, ONE EDGE AT A TIME. The inset is 20 points: a side drawer's edge against the
		 * parent is tucked under it by that much, and the content is inset past the strip; its 90% height
		 * leaves the air above and below. */
		check([[content window] parentWindow] == parent,
		      "the child window is attached to the parent");
		check([[parent childWindows] containsObject:[content window]],
		      "and is in the parent's child list");
		check([[content window] level] == [parent level],
		      "the drawer shares the parent's LEVEL, so it sits over the windows below the parent rather than under all of them");
		check(![[content window] isVisible],
		      "and a drawer of an offscreen, non-key parent is attached but NOT on the glass");
		check(rect_equal([[content window] frame], NSMakeRect(-20.0, 115.0, 140.0, 270.0)),
		      "a left drawer is 90% of the parent's height and a content width PLUS the tucked strip");
		check([[content window] contentView] == content
		      && rect_equal([content frame], NSMakeRect(0.0, 0.0, 120.0, 270.0)),
		      "and its content view fills the panel");

		[drawer setLeadingOffset:10.0];
		[drawer setTrailingOffset:20.0];
		check(rect_equal([[content window] frame], NSMakeRect(-20.0, 110.0, 140.0, 270.0)),
		      "the offsets inset the area the panel is centred in");
		[parent setLevel:NSFloatingWindowLevel];
		check([[content window] level] == [parent level],
		      "a parent that changes level takes its drawer with it");
		[parent setLevel:NSNormalWindowLevel];

		[drawer openOnEdge:NSMaxXEdge];
		check([drawer edge] == NSMaxXEdge, "`-openOnEdge:` moves the edge");
		check(rect_equal([[content window] frame], NSMakeRect(480.0, 110.0, 140.0, 270.0)),
		      "a right drawer adds the 20-point tuck on its LEFT side, under the parent's right edge");
		check(rect_equal([content frame], NSMakeRect(20.0, 0.0, 120.0, 270.0)),
		      "and the content is inset by the tuck, so the visible panel is the full content width");

		[drawer setContentSize:NSMakeSize(120.0, 80.0)];
		[drawer openOnEdge:NSMaxYEdge];
		check(rect_equal([[content window] frame], NSMakeRect(110.0, 400.0, 370.0, 80.0)),
		      "a top drawer sits immediately above, inset left");

		[drawer openOnEdge:NSMinYEdge];
		check(rect_equal([[content window] frame], NSMakeRect(110.0, 20.0, 370.0, 80.0)),
		      "and a bottom drawer immediately below");

		/* 6. THE PARENT CLAMP, IN BOTH AXES. */
		[drawer setLeadingOffset:0.0];
		[drawer setTrailingOffset:0.0];
		[drawer setContentSize:NSMakeSize(500.0, 500.0)];
		[drawer openOnEdge:NSMaxXEdge];
		check(rect_equal([[content window] frame], NSMakeRect(480.0, 115.0, 420.0, 270.0)),
		      "a drawer larger than its parent keeps the 90% height and adds the tuck to its width");
		[drawer setLeadingOffset:200.0];
		[drawer setTrailingOffset:200.0];
		check(NSHeight([[content window] frame]) == 0.0,
		      "offsets that exceed the parent leave a zero transverse extent");

		/* 7. THE PERMISSION DOORS. */
		[drawer close];
		[delegate->events removeAllObjects];
		[observer->names removeAllObjects];
		[drawer setLeadingOffset:0.0];
		[drawer setTrailingOffset:0.0];
		[drawer setContentSize:NSMakeSize(120.0, 200.0)];
		delegate->shouldOpen = NO;
		[drawer open];
		check([drawer state] == NSDrawerClosedState && [delegate->events count] == 0
		      && [observer->names count] == 0,
		      "`-drawerShouldOpen:` NO leaves the drawer closed and announces nothing");
		delegate->shouldOpen = YES;

		/* 8. OPEN AGAIN, THEN A REFUSED CLOSE. */
		[drawer open];
		[delegate->events removeAllObjects];
		[observer->names removeAllObjects];
		delegate->shouldClose = NO;
		[drawer close];
		check([drawer state] == NSDrawerOpenState && [delegate->events count] == 0,
		      "`-drawerShouldClose:` NO leaves an open drawer open");
		delegate->shouldClose = YES;

		/* 9. CLOSE, AND THE CHILD LEAVES THE PARENT. */
		[drawer close];
		check([drawer state] == NSDrawerClosedState, "`-close` closes");
		check([delegate->events count] == 2
		      && [[delegate->events objectAtIndex:0] isEqual:@"willClose:3"]
		      && [[delegate->events objectAtIndex:1] isEqual:@"didClose:0"],
		      "with CLOSING inside Will and CLOSED inside Did");
		check([[content window] parentWindow] == nil
		      && ![[parent childWindows] containsObject:[content window]],
		      "and the child window is detached from the parent");

		/* 10. TOGGLE AND THE ACTION SPELLINGS. */
		[drawer toggle:nil];
		check([drawer state] == NSDrawerOpenState, "`-toggle:` opens a closed drawer");
		[drawer toggle:nil];
		check([drawer state] == NSDrawerClosedState, "and closes an open one");
		[drawer open:nil];
		check([drawer state] == NSDrawerOpenState, "`-open:` is the action spelling of `-open`");
		[drawer close:nil];
		check([drawer state] == NSDrawerClosedState, "and `-close:` of `-close`");

		/* 11. THE PREFERENCE VERSUS THE POSITION. */
		[drawer setPreferredEdge:NSMaxYEdge];
		check([drawer edge] == NSMaxYEdge,
		      "a CLOSED drawer's edge follows the preference");
		[drawer open];
		check([drawer edge] == NSMaxYEdge, "and an open one opens on it");
		[drawer setPreferredEdge:NSMinXEdge];
		check([drawer edge] == NSMaxYEdge,
		      "an OPEN drawer keeps the edge it is on while the preference changes");
		[drawer close];

		/* 12. THE USER'S RESIZE, AND THE LIMITS THAT DO NOT APPLY TO THE PROGRAMMER. */
		[drawer setMinContentSize:NSMakeSize(50.0, 60.0)];
		[drawer setMaxContentSize:NSMakeSize(200.0, 300.0)];
		delegate->resizeAsked = NO;
		delegate->resizeAnswer = NSMakeSize(150.0, 180.0);
		[drawer cg_resizeContentByUserToSize:NSMakeSize(10.0, 999.0)];
		check(delegate->resizeAsked, "the user's resize reaches `-drawerWillResizeContents:toSize:`");
		check(delegate->lastProposed.width == 50.0 && delegate->lastProposed.height == 300.0,
		      "with the proposal clamped to the minimum and maximum FIRST");
		check([drawer contentSize].width == 150.0 && [drawer contentSize].height == 180.0,
		      "and the delegate's answer is the size that lands");
		[drawer setContentSize:NSMakeSize(10.0, 20.0)];
		check([drawer contentSize].width == 10.0 && [drawer contentSize].height == 20.0,
		      "a programmatic `-setContentSize:` is NOT limited by the min/max");

		/* 13. NO PARENT, NO OPEN. */
		{
			NSDrawer *orphan = [[NSDrawer alloc] initWithContentSize:NSMakeSize(10.0, 10.0)
									preferredEdge:NSMinXEdge];

			[orphan open];
			check([orphan state] == NSDrawerClosedState, "a drawer with no parent refuses to open");
			[orphan release];
		}

		/* 14. A PARENT SWAP MOVES THE CHILD. */
		{
			NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(600.0, 200.0, 200.0, 100.0)
								      styleMask:NSBorderlessWindowMask
									backing:NSBackingStoreBuffered
									  defer:NO];

			[drawer setContentSize:NSMakeSize(120.0, 200.0)];
			[drawer openOnEdge:NSMinXEdge];
			[drawer setParentWindow:other];
			check([drawer parentWindow] == other && [[other drawers] containsObject:drawer]
			      && ![[parent drawers] containsObject:drawer],
			      "a parent swap unregisters from the old window and registers with the new");
			check([[content window] parentWindow] == other,
			      "and the attached child moves to the new parent");
			check(rect_equal([[content window] frame], NSMakeRect(480.0, 205.0, 140.0, 90.0)),
			      "with its frame recomputed from the new parent's, centred and inset");
			[drawer close];
			[other release];
			/* **THE PARENT'S DEALLOCATION CLEARS THE BORROWED BACK-POINTER AND DETACHES THE CHILD.** The drawer is
			 * still retained by this probe, so the case is exactly "a drawer outlives its parent": it must answer nil
			 * rather than a freed window, and its child must not keep pointing at one either. */
			check([drawer parentWindow] == nil,
			      "a parent's deallocation clears its drawers' back-pointers");
			check([[content window] parentWindow] == nil,
			      "and detaches the child windows it still had");
		}

		/* 15. A TRANSITION OWNS ITSELF. */
		{
			NSDrawer *guarded = [[NSDrawer alloc] initWithContentSize:NSMakeSize(40.0, 40.0)
									  preferredEdge:NSMinXEdge];
			AGDrawerDelegate *second = [[AGDrawerDelegate alloc] init];

			second->closeFromWillOpen = YES;
			[guarded setParentWindow:parent];
			[guarded setDelegate:second];
			[guarded open];
			check([guarded state] == NSDrawerOpenState,
			      "a `-close` from inside `-drawerWillOpen:` is ignored while the open owns itself");
			check([second->events count] == 2, "so the transition finishes with its own pair of events");
			[guarded setParentWindow:nil];
			[guarded release];
			[second release];
		}

		[center removeObserver:observer];

		printf("drawer: %d case(s) failed\n", s_failed);
		[drawer setParentWindow:nil];
		[drawer release];
		[content release];
		[delegate release];
		[observer release];
		[parent release];
	}
	return s_failed != 0;
}
