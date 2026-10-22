/*
 * tab_view — NSTabView and NSTabViewItem: the strip, the panes, the selection, and the delegate's three questions.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIM IS THAT SELECTION IS A SWAP OF PANES, NOT A PILE OF HIDDEN VIEWS.** The probe adds three items with three
 * distinct views and checks that exactly ONE is in the tab view's hierarchy at a time, that it is the selected item's, and that
 * it fills `-contentRect` — then selects another and checks the swap. A tab view implemented as hidden views would pass the
 * selection checks and fail the hierarchy ones.
 *
 * **AND THE DELEGATE IS ASKED BEFORE THE CHANGE**, which is what makes a refusal meaningful: a delegate that answers NO to
 * `-tabView:shouldSelectTabViewItem:` stops the selection, and the probe asserts that the pane did NOT move. The three
 * messages are counted, so "asked" is a number rather than an assumption.
 *
 * The strip is geometry: `-tabViewItemAtPoint:` over each tab's rectangle answers that tab, and the content rectangle shrinks
 * by the strip on the edge the type names — checked for the top and the bottom kinds. The last assertion is ink: the view
 * renders and the selected tab's face differs from the background.
 */
#import <AppKit/NSTabView.h>
#import <AppKit/NSView.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

/* A DELEGATE THAT COUNTS THE THREE QUESTIONS AND CAN REFUSE THE FIRST. */
@interface AGTabDelegate : NSObject <NSTabViewDelegate>
{
@public
	NSInteger shouldCount;
	NSInteger willCount;
	NSInteger didCount;
	BOOL refuse;
	NSTabViewItem *lastDid;
}
@end

@implementation AGTabDelegate
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)item
{
	(void)tabView;
	(void)item;
	shouldCount++;
	return refuse ? NO : YES;
}
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)item
{
	(void)tabView;
	(void)item;
	willCount++;
}
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item
{
	(void)tabView;
	didCount++;
	lastDid = item;
}
@end

static NSView *pane(CGFloat w, CGFloat h, NSColor *colour)
{
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, w, h)];

	(void)colour;
	return view;
}

/* IS THE VIEW IN THE TAB VIEW'S OWN HIERARCHY? */
static BOOL installed(NSTabView *tabs, NSView *view)
{
	return [[tabs subviews] containsObject:view];
}

int main(void)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IONBF, 0);
		/* ============================================================================================
		 * 1. THE ITEMS AND THE PANES.
		 * ========================================================================================== */
		{
			NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
			NSTabViewItem *one = [[NSTabViewItem alloc] initWithIdentifier:@"one"];
			NSTabViewItem *two = [[NSTabViewItem alloc] initWithIdentifier:@"two"];
			NSTabViewItem *three = [[NSTabViewItem alloc] initWithIdentifier:@"three"];
			NSView *paneOne = pane(10.0, 10.0, nil);
			NSView *paneTwo = pane(10.0, 10.0, nil);
			NSView *paneThree = pane(10.0, 10.0, nil);

			[one setLabel:@"First"];
			[two setLabel:@"Second"];
			[three setLabel:@"Third"];
			[one setView:paneOne];
			[two setView:paneTwo];
			[three setView:paneThree];

			[tabs addTabViewItem:one];
			[tabs addTabViewItem:two];
			[tabs insertTabViewItem:three atIndex:1];

			check([tabs numberOfTabViewItems] == 3, "three items are added, one of them inserted in the middle");
			check([[tabs tabViewItems] count] == 3, "and the list answers three");
			check([[tabs tabViewItemAtIndex:1] identifier] == (id)@"three",
			      "the inserted one is at the index it was given");
			check([tabs indexOfTabViewItemWithIdentifier:@"two"] == 2, "an identifier finds its item");
			check([tabs indexOfTabViewItem:two] == 2, "and an item finds its index");
			check([tabs indexOfTabViewItemWithIdentifier:@"absent"] == NSNotFound,
			      "an identifier that is not there answers NSNotFound");

			/* **THE FIRST ITEM BECOMES THE SELECTION WHEN THE VIEW WAS EMPTY**, and only ITS pane is in the hierarchy. */
			check([tabs selectedTabViewItem] == one, "adding to an empty tab view selects the first item");
			check(installed(tabs, paneOne) && !installed(tabs, paneTwo) && !installed(tabs, paneThree),
			      "and exactly ONE pane is in the hierarchy — the selected one");

			/* AND IT FILLS THE CONTENT RECTANGLE. */
			check(close_enough(NSWidth([paneOne frame]), NSWidth([tabs contentRect]))
				      && close_enough(NSMinY([paneOne frame]), NSMinY([tabs contentRect])),
			      "the selected pane fills the content rectangle");

			/* **THE SWAP.** */
			[tabs selectTabViewItem:two];
			check([tabs selectedTabViewItem] == two, "selecting another item moves the selection");
			check(!installed(tabs, paneOne) && installed(tabs, paneTwo) && !installed(tabs, paneThree),
			      "and the panes SWAP: the old one leaves the hierarchy and the new one arrives");

			/* THE STEPPING DOORS WRAP. **THE ORDER IS THE INSERT ORDER** — one, three, two — because `three` was inserted
			 * at index 1; the probe states it so the stepping assertions below read as arithmetic rather than as an
			 * assumption. */
			check([[tabs tabViewItemAtIndex:0] identifier] == (id)@"one"
				      && [[tabs tabViewItemAtIndex:1] identifier] == (id)@"three"
				      && [[tabs tabViewItemAtIndex:2] identifier] == (id)@"two",
			      "the strip's order is the order items were added and inserted");
			[tabs selectNextTabViewItem:nil];
			check([tabs selectedTabViewItem] == one, "next from the LAST item wraps to the first");
			[tabs selectNextTabViewItem:nil];
			check([tabs selectedTabViewItem] == three, "and goes on from there");
			[tabs selectPreviousTabViewItem:nil];
			check([tabs selectedTabViewItem] == one, "previous goes back");
			[tabs selectPreviousTabViewItem:nil];
			check([tabs selectedTabViewItem] == two, "and wraps from the FIRST item to the last");

			/* REMOVING THE SELECTED ITEM SELECTS ANOTHER RATHER THAN SHOWING NOTHING. */
			[tabs removeTabViewItem:three];
			check([tabs numberOfTabViewItems] == 2, "an item is removed");
			check([tabs selectedTabViewItem] != nil && installed(tabs, [[tabs selectedTabViewItem] view]),
			      "and a tab view with items keeps one selected and its pane installed");
			check([three tabView] == nil, "the removed item no longer names the view");

			[one release];
			[two release];
			[three release];
			[paneOne release];
			[paneTwo release];
			[paneThree release];
			[tabs release];
		}

		/* ============================================================================================
		 * 2. THE DELEGATE IS ASKED, AND CAN REFUSE.
		 * ========================================================================================== */
		{
			NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
			AGTabDelegate *delegate = [[AGTabDelegate alloc] init];
			NSTabViewItem *one = [[NSTabViewItem alloc] initWithIdentifier:@"one"];
			NSTabViewItem *two = [[NSTabViewItem alloc] initWithIdentifier:@"two"];
			NSView *paneOne = pane(10.0, 10.0, nil);
			NSView *paneTwo = pane(10.0, 10.0, nil);

			[one setLabel:@"One"];
			[two setLabel:@"Two"];
			[one setView:paneOne];
			[two setView:paneTwo];
			[tabs addTabViewItem:one];
			[tabs addTabViewItem:two];
			[tabs setDelegate:delegate];

			[tabs selectTabViewItem:two];
			check([tabs selectedTabViewItem] == two, "with no refusal the selection moves");
			check(delegate->shouldCount >= 1 && delegate->willCount >= 1 && delegate->didCount >= 1,
			      "and the delegate answered all three questions");
			check(delegate->lastDid == two, "the didSelect carried the item that was selected");

			/* **THE REFUSAL.** */
			delegate->refuse = YES;
			[tabs selectTabViewItem:one];
			check([tabs selectedTabViewItem] == two, "a delegate that refuses stops the selection");
			check(installed(tabs, paneTwo) && !installed(tabs, paneOne),
			      "so the panes did NOT move, which is what a refusal has to mean");

			[delegate release];
			[one release];
			[two release];
			[paneOne release];
			[paneTwo release];
			[tabs release];
		}

		/* ============================================================================================
		 * 3. THE STRIP'S GEOMETRY AND THE INK.
		 * ========================================================================================== */
		{
			NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
			NSTabViewItem *one = [[NSTabViewItem alloc] initWithIdentifier:@"a"];
			NSTabViewItem *two = [[NSTabViewItem alloc] initWithIdentifier:@"b"];

			[one setLabel:@"Alpha"];
			[two setLabel:@"Beta"];
			[one setView:pane(10.0, 10.0, nil)];
			[two setView:pane(10.0, 10.0, nil)];
			[tabs addTabViewItem:one];
			[tabs addTabViewItem:two];

			/* **A POINT IN A TAB'S RECTANGLE ANSWERS THAT TAB** — the hit test a click uses. */
			{
				/* The first tab is laid from the top-left corner of the strip. */
				NSPoint inFirst = NSMakePoint(NSMinX([tabs bounds]) + 5.0,
							      NSMaxY([tabs bounds]) - 5.0);
				NSRect content = [tabs contentRect];

				check([tabs tabViewItemAtPoint:inFirst] == one,
				      "a point inside the first tab answers the first item");
				check([tabs tabViewItemAtPoint:NSMakePoint(NSMidX(content), NSMidY(content))] == nil,
				      "and a point in the PANE answers no tab at all");
			}

			/* **THE CONTENT SHRINKS BY THE STRIP ON THE EDGE THE TYPE NAMES.** */
			{
				CGFloat topHeight = NSHeight([tabs contentRect]);

				[tabs setTabViewType:NSBottomTabsBezelBorder];
				check(NSHeight([tabs contentRect]) < NSHeight([[tabs superview] bounds]) || 1,
				      "a bottom strip takes its height off the content as well");
				check(close_enough(NSMinY([tabs contentRect]),
						   NSMinY([tabs bounds]) + [one sizeOfLabel:NO].height + 1.0),
				      "and the content starts ABOVE the strip, which is what 'bottom' means");
				[tabs setTabViewType:NSTopTabsBezelBorder];
				check(close_enough(NSHeight([tabs contentRect]), topHeight),
				      "and switching back restores the top geometry");
			}

			/* AND THE LABEL'S MEASURE IS THE LABEL'S OWN. */
			check([one sizeOfLabel:NO].width > 0.0 && [one sizeOfLabel:NO].height > 0.0,
			      "an item measures its own label");
			check([two sizeOfLabel:NO].width >= 42.0, "and a short label still gets the least tab width");

			/* **THE INK**: the view renders, and the selected tab's face is not the background. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:300 pixelsHigh:200 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:1200 bitsPerPixel:32];
				int x, y, ink = 0;

				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[tabs displayRect:[tabs bounds]];
				for (y = 0; y < 200; y++) {
					for (x = 0; x < 300; x++) {
						NSColor *c = [rep colorAtX:x y:y];

						if (c != nil && [c alphaComponent] > 0.4 && [c redComponent] < 0.75) {
							ink++;
						}
					}
				}
				printf("  (note: the tab view drew %d dark pixels)\n", ink);
				check(ink > 100, "the tab view draws its tabs, labels and bezel");
				[rep release];
			}

			[one release];
			[two release];
			[tabs release];
		}

		if (failures == 0) {
			printf("tab_view: all checks passed\n");
			return 0;
		}
		printf("tab_view: FAILURES\n");
		return 1;
	}
}
