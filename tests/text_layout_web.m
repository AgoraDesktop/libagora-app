/*
 * text_layout_web.m — THE WEB: A STORE, THE MANAGERS IT TELLS, AND THE CONTAINERS A MANAGER OWNS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **SLICE ONE OF THE LAYOUT MANAGER HAS NO GLYPHS, SO WHAT IT HAS IS THE WIRING — AND WIRING IS EXACTLY THE THING THAT
 * CAN BE TESTED IN BOTH DIRECTIONS.** Each pair of objects is checked from BOTH sides (the manager knows its store and
 * the store's list has the manager; the manager owns the container and the container's borrowed pointer names the
 * manager), because a web that agrees from one side and not the other is the bug this slice exists to make impossible.
 *
 * **AND THE ONE THING THAT MOVES IS STALENESS.** An edit in the store reaches every manager on its list, is folded into
 * one invalidated range, and is announced to a delegate. THAT is what the glyph slice will hang everything on, and it is
 * the only observable behaviour here that is a computation rather than a pointer.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int range_is(NSRange r, NSUInteger where, NSUInteger length)
{
	return r.location == where && r.length == length;
}

/* A DELEGATE THAT COUNTS THE ONE CALLBACK THIS SLICE CAN SEND. */
@interface LayoutWatcher : NSObject <NSLayoutManagerDelegate>
{
@public
	int invalidated;
}
@end

@implementation LayoutWatcher
- (void)layoutManagerDidInvalidateLayout:(NSLayoutManager *)sender
{
	(void)sender;
	invalidated++;
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"hello"];
	NSTextStorage *other = [[NSTextStorage alloc] initWithString:@"second store"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSLayoutManager *second = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 200.0)];
	LayoutWatcher *watcher = [[LayoutWatcher alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **A MANAGER STARTS WITHOUT A STORE, WHICH IS APPLE'S OWN DESIGNATED-INITIALISER NOTE.** Nothing is stale
	 * either — `NSNotFound` and not a zero-length range at the start. */
	check([manager textStorage] == nil, "a fresh manager has no store");
	check([[manager textContainers] count] == 0, "and no containers");
	check([manager attributedString] == nil, "and its attributed string — the store seen as one — is nil");
	check([manager cg_invalidatedRange].location == NSNotFound, "and NOTHING is stale");

	/* 2. **AND THE STORAGE HANDS ITSELF OVER, WHICH IS THE DIRECTION APPLE'S COMMENT GIVES.** Checked from BOTH
	 * sides: the manager's pointer and the store's list. */
	[manager setDelegate:watcher];
	[store addLayoutManager:manager];
	check([manager textStorage] == store, "adding a manager to a store gives the manager that store");
	check([[store layoutManagers] containsObject:manager], "and puts the manager on the store's own list");
	check([manager attributedString] == store, "and the store seen as an attributed string IS the store");
	printf("  (note: wiring a 5-character store invalidated (%lu,%lu) and told the delegate %d time(s))\n",
	       (unsigned long)[manager cg_invalidatedRange].location, (unsigned long)[manager cg_invalidatedRange].length,
	       watcher->invalidated);
	check(range_is([manager cg_invalidatedRange], 0, 5), "and wiring it marks the whole store stale");

	/* 3. **THE CONTAINER IS OWNED BY THE MANAGER AND BORROWS IT BACK**, again checked from both sides. */
	[manager addTextContainer:container];
	check([[manager textContainers] containsObject:container], "adding a container puts it in the manager's list");
	check([container layoutManager] == manager, "and gives the container a borrowed pointer to the manager");
	check([manager attributedString] == store, "with the store untouched by any of it");

	/* 4. **AND AN EDIT IN THE STORE REACHES THE MANAGER.** That is the whole web: a character changes and the thing
	 * that would lay the characters out is told — through the ONE door Apple's header names, with the store's own record
	 * still standing for anyone who reads it. */
	{
		int before = watcher->invalidated;

		[store replaceCharactersInRange:NSMakeRange(5, 0) withString:@" world"];
		printf("  (note: an edit told the delegate %d more time(s); stale is (%lu,%lu))\n",
		       watcher->invalidated - before, (unsigned long)[manager cg_invalidatedRange].location,
		       (unsigned long)[manager cg_invalidatedRange].length);
		check(watcher->invalidated > before, "an edit in the store INVALIDATES the manager's layout, through its delegate");
		check([manager cg_invalidatedRange].location <= 5
		      && [manager cg_invalidatedRange].location + [manager cg_invalidatedRange].length >= 11,
		      "and the stale range covers what changed");
	}

	/* 5. **AND THE UNION IS THE ACCUMULATION**, which is the one computation in the slice: two reports become one
	 * range. A manager with no store is used so that the WIRING's own invalidation is not part of the answer. */
	{
		NSLayoutManager *fresh = [[NSLayoutManager alloc] init];
		NSRange actual = NSMakeRange(99, 99);

		[fresh invalidateLayoutForCharacterRange:NSMakeRange(2, 3) actualCharacterRange:&actual];
		check(range_is([fresh cg_invalidatedRange], 2, 3), "one report becomes the stale range");
		check(range_is(actual, 2, 3), "and the actual range it reports back is the one asked for");
		[fresh invalidateLayoutForCharacterRange:NSMakeRange(10, 5) actualCharacterRange:NULL];
		check(range_is([fresh cg_invalidatedRange], 2, 13),
		      "and a second report is UNIONED with the first rather than replacing it");
		[fresh release];
	}

	/* 6. **AND TAKING A MANAGER OFF A STORE CLEARS ITS POINTER.** The list owns the manager and the store owns the
	 * pointer, so one door has to clear both — which is what stops a manager pointing at a store that no longer lists
	 * it. */
	[store removeLayoutManager:manager];
	check([manager textStorage] == nil, "taking a manager off a store clears the manager's pointer");
	check(![[store layoutManagers] containsObject:manager], "and drops it from the store's list");
	check([container layoutManager] == manager, "while the container is still the manager's — the two webs are separate");

	/* 7. **AND A MANAGER CAN BE MOVED BETWEEN STORES, WHICH IS THE ONE DOOR THAT CROSSES BOTH BOUNDARIES.** */
	[second addTextContainer:container];
	check([container layoutManager] == second, "adding the container to a second manager re-points the container");
	check(![[manager textContainers] containsObject:container],
	      "and takes it off the first — a container is laid out in ONE place");
	[manager replaceTextStorage:other];
	check([manager textStorage] == other, "`-replaceTextStorage:` moves a manager onto the new store");
	check([[other layoutManagers] containsObject:manager], "and onto the new store's list");
	[other removeLayoutManager:manager];
	check([manager textStorage] == nil, "and off it again");

	/* 8. **AND A CARRIED CONTAINER TAKES THE WHOLE WEB WITH IT.** `-replaceLayoutManager:` is the door a caller uses
	 * when a container moves between managers, and Apple's contract is that the old manager's containers go too. */
	[manager addTextContainer:container];
	check([container layoutManager] == manager, "the container is the first manager's again");
	[container replaceLayoutManager:second];
	check([container layoutManager] == second, "`-replaceLayoutManager:` re-points the container");
	check([[second textContainers] containsObject:container], "and the new manager owns it");
	check(![[manager textContainers] containsObject:container],
	      "and the old one no longer does — the containers are TRANSFERRED, not shared");

	/* 9. **AND ONE CONTAINER AT A TIME IS `-setTextContainer:`.** Apple's door replaces the list with the single one. */
	[second setTextContainer:[[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(100.0, 50.0)] autorelease]];
	check([[second textContainers] count] == 1, "`-setTextContainer:` leaves exactly one container");
	check([container layoutManager] == nil, "and the one it replaced has no manager any more");

	[watcher release];
	[container release];
	[second release];
	[manager release];
	[other release];
	[store release];
	[pool release];
	printf("text_layout_web: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
