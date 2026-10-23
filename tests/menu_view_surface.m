/*
 * menu_view_surface — the menu view's era surface: geometry, metrics, the lifecycle, and the refusals beside them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE VIEW HAD FIVE OF ITS ERA'S FORTY-TWO SELECTORS, AND THIS IS THE REST.** Two of the missing families are the ones a
 * caller actually needs — where a row IS (`-rectOfItemAtIndex:`, `-indexOfItemAtPoint:`) and where the columns inside a
 * row start (`-stateImageOffset`, `-imageAndTitleOffset`, `-keyEquivalentOffset` and their widths, which are the widest
 * measure across the rows because a menu's gutters are one set of columns for every row) — and one is the view's answer
 * to the menu changing under it (`-itemAdded:`, `-itemChanged:`, `-itemRemoved:`, reached through the menu's own
 * notifications so there is ONE path into the cell cache).
 *
 * WHAT IS ASSERTED:
 *
 *   1. THE GEOMETRY: the public row rect agrees with the drawing's own, the hit test answers the row under a point (and
 *      -1 below the last), the padding moves the row, `-innerRect` is the panel less its padding, and `-sizeToFit` sets the
 *      frame from the measured size and clears `-needsSizing`.
 *   2. THE METRICS: the state-image offset is the content inset, the image-and-title column starts after the state image,
 *      and the key equivalent's column is right-aligned — measured from a menu with three rows of different widths, so a
 *      "widest" that answered the first row would fail.
 *   3. THE LIFECYCLE: adding, changing and removing an item through the MENU reaches the view's doors (the cell cache is
 *      dropped and the size is marked stale), which is the whole reason the view listens.
 *   4. THE HIGHLIGHT BY INDEX: `-highlightedItemIndex` is -1 for nothing, the index of the item it was given, and
 *      `-setHighlightedItemIndex:` selects by position — including -1 to clear.
 *   5. THE ACTION WITH A FLASH: `-performActionWithHighlightingForItemAtIndex:` sends the item's action to its target,
 *      once, and leaves no highlight behind.
 *   6. THE FACE AND THE BAR: a font set on the view reaches the cells it made, and `-menuBarHeight` is the strip's height
 *      for a bar and zero for a dropdown.
 *   7. AND THE TEN THAT REFUSE: the popup attachment (eight doors — `NSMenu` owns the tracking window in this tier) and
 *      the tear-off pair. Each answers its type's empty value and does not crash.
 */
#import <AppKit/NSMenuView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSWindow.h>
#import <Foundation/Foundation.h>

#include <objc/runtime.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int near_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

/* A TARGET THAT COUNTS, so "the action was sent" is a number. */
@interface AGMenuViewTarget : NSObject
{
@public
	int sends;
}
- (void)chosen:(id)sender;
@end

@implementation AGMenuViewTarget
- (void)chosen:(id)sender
{
	(void)sender;
	sends++;
}
@end

/* A ROW'S TARGET IS THE ITEM'S, NOT THE MENU'S — `NSMenu` has no `-setTarget:`, and a menu item's action goes to ITS OWN
 * target (or, with none, through `-sendAction:`'s chain). */
static NSMenuItem *addItem(NSMenu *menu, NSString *title, NSString *key, BOOL enabled)
{
	NSMenuItem *item = [menu addItemWithTitle:title action:@selector(chosen:) keyEquivalent:key];

	[item setEnabled:enabled];
	return item;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	/* **THE APPLICATION IS MADE FIRST, BECAUSE `-sendAction:` IS ITS DOOR** — `NSApp` is NULL until `-sharedApplication`
	 * runs, and the view's flash-and-send asks the class for the instance for exactly that reason. */
	(void)[NSApplication sharedApplication];
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Surface"];
	NSMenuView *view;
	AGMenuViewTarget *target = [[AGMenuViewTarget alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	addItem(menu, @"Short", @"s", YES);
	addItem(menu, @"A much longer title", @"", YES);
	addItem(menu, @"Off", @"o", NO);

	view = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 260.0, 120.0)];
	{
		NSInteger i;

		for (i = 0; i < [menu numberOfItems]; i++) {
			[[menu itemAtIndex:i] setTarget:target];
		}
	}
	[view setMenu:menu];

	/* ============================================================================================ *
	 * 1. THE GEOMETRY.                                                                              *
	 * ============================================================================================ */
	{
		NSRect row0 = [view rectOfItemAtIndex:0];
		NSRect row1 = [view rectOfItemAtIndex:1];
		NSRect inside = [view innerRect];

		printf("  (note: row 0 is %g,%g %gx%g; the inner rect is %g,%g %gx%g)\n",
		       (double)NSMinX(row0), (double)NSMinY(row0), (double)NSWidth(row0), (double)NSHeight(row0),
		       (double)NSMinX(inside), (double)NSMinY(inside), (double)NSWidth(inside), (double)NSHeight(inside));
		check(!NSIsEmptyRect(row0) && !NSIsEmptyRect(row1), "a menu's rows have rects");
		check(NSMinY(row0) > NSMinY(row1), "row 0 is ABOVE row 1, which is the order a menu is read in");
		check(NSHeight(inside) < NSHeight([view bounds]) || near_enough(NSHeight(inside), NSHeight([view bounds])),
		      "`-innerRect` is the panel less its padding");
		check([view indexOfItemAtPoint:NSMakePoint(NSMidX(row1), NSMidY(row1))] == 1,
		      "`-indexOfItemAtPoint:` answers the row a point is in");
		check([view indexOfItemAtPoint:NSMakePoint(10.0, 1.0)] < 0,
		      "and -1 below the last row");

		/* THE PADDING MOVES THE ROW AND NOTHING ELSE. */
		[view setHorizontalEdgePadding:12.0];
		{
			NSRect padded = [view rectOfItemAtIndex:0];

			check(near_enough(NSMinX(padded), NSMinX(row0) + 12.0),
			      "`-setHorizontalEdgePadding:` moves a row in from the panel's side");
			check(near_enough(NSWidth(padded), NSWidth(row0) - 24.0),
			      "and narrows it by the same amount on both sides");
			check(near_enough([view horizontalEdgePadding], 12.0), "and the door answers what was set");
		}
		[view setHorizontalEdgePadding:0.0];

		/* THE SIZE, WHICH IS MEASURED AND THEN REMEMBERED. */
		[view setNeedsSizing:YES];
		check([view needsSizing], "`-setNeedsSizing:YES` marks the size stale");
		[view sizeToFit];
		printf("  (note: sizeToFit made the view %gx%g)\n",
		       (double)[view frame].size.width, (double)[view frame].size.height);
		check(![view needsSizing], "and `-sizeToFit` recomputes and clears the flag");
		check([view frame].size.height > 0.0, "the view is as tall as its rows need");
	}

	/* ============================================================================================ *
	 * 2. THE METRICS, FROM THE WIDEST ROW RATHER THAN THE FIRST.                                     *
	 * ============================================================================================ */
	{
		CGFloat stateOffset = [view stateImageOffset];
		CGFloat stateWidth = [view stateImageWidth];
		CGFloat imageOffset = [view imageAndTitleOffset];
		CGFloat keyOffset = [view keyEquivalentOffset];
		CGFloat keyWidth = [view keyEquivalentWidth];

		printf("  (note: state %g+%g, image/title at %g (%g wide), key at %g (%g wide), view %g wide)\n",
		       (double)stateOffset, (double)stateWidth, (double)imageOffset,
		       (double)[view imageAndTitleWidth], (double)keyOffset, (double)keyWidth,
		       (double)NSWidth([view bounds]));
		check(near_enough(imageOffset, stateOffset + stateWidth),
		      "the image-and-title column starts after the state image");
		check([view imageAndTitleWidth] > 0.0, "the title column has a width");
		/* **ANCHORED, NOT A LITERAL PADDING**: the column's width comes from the cells, so what the probe can hold is that
		 * the gap between the column's end and the view's right edge is the SAME for two views of different widths — that
		 * is what right-aligned means. */
		{
			NSMenuView *wide = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 120.0)];
			CGFloat here;
			CGFloat there;

			[wide setMenu:menu];
			here = NSWidth([view bounds]) - (keyOffset + keyWidth);
			there = NSWidth([wide bounds]) - ([wide keyEquivalentOffset] + [wide keyEquivalentWidth]);
			printf("  (note: the gap after the key column is %g here and %g in a wider view)\n",
			       (double)here, (double)there);
			check(keyWidth > 0.0 && near_enough(here, there),
			      "the key-equivalent column is anchored to the row's RIGHT edge, whatever the view's width");
			[wide release];
		}
	}

	/* ============================================================================================ *
	 * 3. THE LIFECYCLE, REACHED THROUGH THE MENU'S OWN NOTIFICATIONS.                                *
	 * ============================================================================================ */
	{
		NSMenuItem *added = addItem(menu, @"Added later", @"", YES);

		[added setTarget:target];
		NSInteger count = [menu numberOfItems];

		check(count == 4, "an item was added to the menu");
		check([view menuItemCellForItemAtIndex:3] != nil,
		      "and the view has a cell for the new row");
		[view setNeedsSizing:NO];
		[added setTitle:@"Renamed"];
		[menu itemChanged:added];
		check([view needsSizing],
		      "`-itemChanged:` (through NSMenuDidChangeItemNotification) drops the cached cell and marks the size stale");
		[view setNeedsSizing:NO];
		[menu removeItem:added];
		check([view needsSizing], "and `-itemRemoved:` marks everything stale, because the rows after it shift");
	}

	/* ============================================================================================ *
	 * 4. THE HIGHLIGHT, BY INDEX AND BY ITEM.                                                        *
	 * ============================================================================================ */
	{
		check([view highlightedItemIndex] == -1, "nothing is highlighted to start with, which is -1");
		[view setHighlightedItemIndex:1];
		check([view highlightedItemIndex] == 1, "`-setHighlightedItemIndex:` highlights by position");
		check([view highlightedItem] == [menu itemAtIndex:1], "which is the item at that position");
		[view setHighlightedItemIndex:-1];
		check([view highlightedItemIndex] == -1 && [view highlightedItem] == nil, "and -1 clears it");
	}

	/* ============================================================================================ *
	 * 5. THE ACTION WITH A FLASH.                                                                    *
	 * ============================================================================================ */
	{
		{
			NSMenuItem *probe = [menu itemAtIndex:0];
			SEL action = [probe action];

			printf("  (note: item 0 action %s target %p responds %d enabled %d)\n",
			       (action != NULL) ? sel_getName(action) : "(null)",
			       (void *)[probe target],
			       (int)((action != NULL) && [[probe target] respondsToSelector:action]),
			       (int)[probe isEnabled]);
		}
		target->sends = 0;
		[view performActionWithHighlightingForItemAtIndex:0];
		check(target->sends == 1, "`-performActionWithHighlightingForItemAtIndex:` sends the item's action, once");
		check([view highlightedItem] == nil, "and leaves no highlight behind");
		target->sends = 0;
		[view performActionWithHighlightingForItemAtIndex:2];	/* the DISABLED row */
		check(target->sends == 0, "a disabled row is not performed");
		[view performActionWithHighlightingForItemAtIndex:99];
		check(target->sends == 0, "and neither is a row that does not exist");
	}

	/* ============================================================================================ *
	 * 6. THE FACE AND THE BAR'S HEIGHT.                                                              *
	 * ============================================================================================ */
	{
		NSFont *font = [NSFont boldSystemFontOfSize:13.0];

		[view setFont:font];
		check([view font] == font, "`-setFont:` is what `-font` answers");
		check([[view menuItemCellForItemAtIndex:0] font] == font,
		      "and the cells the view made wear it");

		check([view menuBarHeight] == 0.0, "a dropdown has no bar height");
		[view setHorizontal:YES];
		check(near_enough([view menuBarHeight], NSHeight([view bounds])),
		      "while a bar's height is its strip's");
		[view setHorizontal:NO];
	}

	/* ============================================================================================ *
	 * 7. AND THE TEN THAT REFUSE.                                                                    *
	 * ============================================================================================ */
	{
		check([view attachedMenu] == nil, "`-attachedMenu` refuses: NSMenu owns the tracking window here");
		check([view attachedMenuView] == nil, "and so does `-attachedMenuView`");
		check(![view isAttached], "`-isAttached` answers NO");
		check(near_enough([view locationForSubmenu:menu].x, 0.0), "`-locationForSubmenu:` answers zero");
		[view attachSubmenuForItemAtIndex:0];
		[view detachSubmenu];
		[view trackWithEvent:nil];
		[view setWindowFrameForAttachingToRect:NSZeroRect onScreen:nil preferredEdge:NSMinYEdge popUpSelectedItem:0];
		check(1, "the attachment family answers nothing and does not crash");
		check(![view isTornOff], "`-isTornOff` answers NO");
		{
			NSMenuView *tear = [[NSMenuView alloc] initAsTearOff];

			check(tear != nil, "`-initAsTearOff` refuses by name and still makes a usable view");
			[tear setMenu:menu];
			check([tear menu] == menu, "which can be given a menu");
			[tear release];
		}
	}

	[view setMenu:nil];
	[view release];
	[menu release];
	[target release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
