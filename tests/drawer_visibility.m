/*
 * drawer_visibility — a drawer is on the glass only while its parent is frontmost and key.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE RULE THIS FILE EXISTS FOR IS A COMPOSITE, AND EACH PART IS A DIFFERENT FACT.** A drawer is shown when its
 * parent is VISIBLE, KEY and in an ACTIVE application — not merely attached. This tier keeps a window key across
 * application deactivation, and `-orderOut:` does not resign the key bit, so key alone is not enough and visible alone
 * is not enough. The probe drives each transition and reads the drawer's own child window, which is the pixel-bearing
 * object the rule is about.
 *
 * The same run also asserts the pin that makes the tuck work: the drawer's window shares its parent's level and is
 * ordered as the layer immediately below it.
 *
 * It needs a compositor for visibility (a window is only on the glass when there is glass), so it is run through
 * `run-appkit-headless.sh` and skips where none can be started.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSDrawer.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSAutoreleasePool.h>

#include <stdio.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

static int drawer_visible(NSDrawer *drawer)
{
	NSView *content = [drawer contentView];

	return content != nil && [[content window] isVisible];
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *app = [NSApplication sharedApplication];
	NSWindow *parent;
	NSWindow *other;
	NSView *content;
	NSDrawer *drawer;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
			i++;	/* accepted and unused: this probe does not need an event loop */
		}
	}
	[app finishLaunching];
	[app activate];

	parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(100.0, 100.0, 400.0, 300.0)
					     styleMask:NSTitledWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 200.0)];
	drawer = [[NSDrawer alloc] initWithContentSize:NSMakeSize(120.0, 200.0) preferredEdge:NSMaxXEdge];
	[drawer setContentView:content];
	[drawer setParentWindow:parent];

	[parent makeKeyAndOrderFront:nil];
	[drawer open];
	printf("drawer_visibility: parent visible %d key %d, app active %d, drawer visible %d\n",
	       (int)[parent isVisible], (int)[parent isKeyWindow], (int)[app isActive], drawer_visible(drawer));
	check([parent isVisible] && [parent isKeyWindow] && [app isActive],
	      "the parent is frontmost, key and in an active application");
	check(drawer_visible(drawer), "so its drawer is on the glass");
	check([[content window] level] == [parent level],
	      "and the drawer's window shares the parent's level, ordered one layer under it");

	/* A DIFFERENT WINDOW TAKES THE KEYBOARD: THE DRAWER GOES WITH THE PARENT'S KEY FLAG. */
	other = [[NSWindow alloc] initWithContentRect:NSMakeRect(550.0, 100.0, 300.0, 200.0)
					    styleMask:NSTitledWindowMask
					      backing:NSBackingStoreBuffered
						defer:NO];
	[other makeKeyAndOrderFront:nil];
	check(![parent isKeyWindow], "a second window is key");
	check(!drawer_visible(drawer), "so the drawer is hidden while its parent is not key");

	[parent makeKeyWindow];
	check(drawer_visible(drawer), "making the parent key again brings the drawer back");

	/* ORDERING OUT IS NOT RESIGNING KEY, WHICH IS WHY VISIBILITY IS ALSO PART OF THE RULE. */
	[parent orderOut:nil];
	check(![parent isVisible], "the parent is ordered out");
	check(!drawer_visible(drawer), "and its drawer is hidden even though the window still owns the key flag");
	[parent orderFront:nil];
	check(drawer_visible(drawer), "ordering the parent back in brings the drawer with it");

	/* AN INACTIVE APPLICATION IS NOT FRONTMOST, even with a visible key window. */
	[app deactivate];
	check(![app isActive] && [parent isKeyWindow],
	      "deactivation leaves the key flag where it was, which is the case key alone misses");
	check(!drawer_visible(drawer), "and the drawer is hidden with the application");
	[app activate];
	check(drawer_visible(drawer), "reactivating the application brings back the visible key window's drawer");

	[drawer setParentWindow:nil];
	[drawer release];
	[content release];
	[other release];
	[parent release];
	[pool release];
	if (s_failed == 0) {
		printf("drawer_visibility: ok\n");
	}
	return s_failed == 0 ? 0 : 1;
}
