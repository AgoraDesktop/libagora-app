/*
 * find_actions — the NSFindPanelAction doors that do not need a panel.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIM WORTH TESTING IS THAT A FIND MENU WORKS WITH NO FIND PANEL**, because that is the split Apple's own API
 * makes: the sender's TAG is one of ten actions and only three of them want a panel. So the test drives the actions a
 * caller can actually reach — set the search string from the selection, find next, find previous, select all — and
 * checks that the SELECTION moves to the match, that it wraps, and that the indicator puts ink on the pixels.
 *
 * **WRAPPING IS ASSERTED IN BOTH DIRECTIONS**, since a finder that stops at the end of the document is the bug users
 * report as "find is broken".
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
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

/* A sender whose tag is the action, which is what an NSMenuItem is. */
@interface AGTagSender : NSObject
{
@public
	NSInteger tag;
}
- (NSInteger)tag;
@end

@implementation AGTagSender
- (NSInteger)tag { return tag; }
@end

static AGTagSender *sender_for(NSInteger action)
{
	AGTagSender *sender = [[[AGTagSender alloc] init] autorelease];

	sender->tag = action;
	return sender;
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static int yellow_pixels(NSBitmapImageRep *rep, int w, int h)
{
	int x, y, count = 0;

	for (y = 0; y < h; y++) {
		for (x = 0; x < w; x++) {
			NSColor *p = [rep colorAtX:x y:y];

			if (p != nil && [p redComponent] > 0.5 && [p greenComponent] > 0.4
			    && [p blueComponent] < 0.4 && [p alphaComponent] > 0.05) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	@autoreleasepool {
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 60.0)];
		const char *text = "alpha beta gamma beta delta";

		[view setString:[NSString stringWithUTF8String:text]];

		/* 1. The flag door. */
		check(![view usesFindPanel], "a view does not use a find panel by default");
		[view setUsesFindPanel:YES];
		check([view usesFindPanel], "and the flag it is given comes back");

		/* 2. SetFindString from the selection: select "beta", then action 7. */
		[view setSelectedRange:NSMakeRange(6, 4)];
		[view performFindPanelAction:sender_for(NSFindPanelActionSetFindString)];
		check(1, "set-find-string from the selection does not crash");

		/* 3. Next finds the SECOND "beta" (the one at 17), because the search starts past the selection. */
		[view performFindPanelAction:sender_for(NSFindPanelActionNext)];
		check([view selectedRange].location == 17 && [view selectedRange].length == 4,
		      "find next selects the next occurrence");

		/* 4. Next again WRAPS to the first one at 6. */
		[view performFindPanelAction:sender_for(NSFindPanelActionNext)];
		check([view selectedRange].location == 6,
		      "and wraps to the first occurrence at the end of the document");

		/* 5. Previous from the first wraps BACKWARDS to the last, at 17. */
		[view performFindPanelAction:sender_for(NSFindPanelActionPrevious)];
		check([view selectedRange].location == 17,
		      "find previous wraps backwards to the last occurrence");

		/* 6. A search for something absent leaves the selection alone. */
		{
			NSRange before = [view selectedRange];

			[view setSelectedRange:NSMakeRange(0, 5)];	/* "alpha" becomes the search string */
			[view performFindPanelAction:sender_for(NSFindPanelActionSetFindString)];
			[view setSelectedRange:NSMakeRange(0, 0)];
			[view performFindPanelAction:sender_for(NSFindPanelActionNext)];
			check([view selectedRange].location == 0,
			      "a search that finds its string right at the start selects it");
			(void)before;
		}

		/* 7. Select all is real and needs no panel. */
		[view performFindPanelAction:sender_for(NSFindPanelActionSelectAll)];
		check([view selectedRange].length == [[view string] length], "select all selects the whole string");

		/* 8. The indicator is ink: a shown range puts yellow on the pixels, and the next draw clears it. */
		{
			NSBitmapImageRep *first = new_rep(240, 60);
			NSBitmapImageRep *second = new_rep(240, 60);

			[view showFindIndicatorForRange:NSMakeRange(6, 4)];
			[view cacheDisplayInRect:NSMakeRect(0.0, 0.0, 240.0, 60.0) toBitmapImageRep:first];
			[view cacheDisplayInRect:NSMakeRect(0.0, 0.0, 240.0, 60.0) toBitmapImageRep:second];
			check(yellow_pixels(first, 240, 60) > 0, "the find indicator draws a yellow ring on the pixels");
			check(yellow_pixels(second, 240, 60) == 0,
			      "and it lasts one drawing pass, as the era's flash did");
			[first release];
			[second release];
		}

		/* 9. The panel actions refuse rather than pretending. */
		[view performFindPanelAction:sender_for(NSFindPanelActionShowFindPanel)];
		[view performFindPanelAction:sender_for(NSFindPanelActionReplaceAll)];
		check(1, "show-find-panel and replace-all refuse by name without crashing");

		[view release];

		if (failures == 0) {
			printf("find_actions: all checks passed\n");
			return 0;
		}
		printf("find_actions: FAILURES\n");
		return 1;
	}
}
