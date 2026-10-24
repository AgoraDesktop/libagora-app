/*
 * dock_tile — an application's tile: the badge it keeps, and what the Dock is told.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROBE IS THE APPLICATION'S HALF, BECAUSE THE BADGE'S TRAVEL IS THE SERVER'S.** With no compositor there is
 * nowhere for a label to go, so what is measured here is the contract a caller relies on: the tile is one object per
 * application and `-owner` names it, the label is kept whether or not a window exists yet, `-showsApplicationBadge`
 * hides rather than forgets, the content view is stored and answered, and the Dock's lookup answers an empty dictionary
 * rather than nil when nobody has published anything. The end-to-end path — set, sent, drawn — is the window server's
 * `window_list` probe plus `dock`'s own drawing, each at its own end.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSDockTile.h>
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

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSDockTile *tile = [application dockTile];
		NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];

		check(tile != nil && [application dockTile] == tile,
		      "an application has ONE dock tile, made on first ask");
		check([tile owner] == application, "and the tile's owner is the application");

		check([tile badgeLabel] == nil && [tile showsApplicationBadge],
		      "a fresh tile has no label and shows the badge");
		check([tile contentView] == nil, "and no content view");

		[tile setBadgeLabel:@"3"];
		check([[tile badgeLabel] isEqual:@"3"], "setting the label keeps it");

		[tile setShowsApplicationBadge:NO];
		check(![tile showsApplicationBadge] && [[tile badgeLabel] isEqual:@"3"],
		      "hiding the badge keeps the label rather than forgetting it");
		[tile setShowsApplicationBadge:YES];
		check([tile showsApplicationBadge], "and showing it again is a flag, not a re-set");

		[tile setContentView:view];
		check([tile contentView] == view, "a content view is stored and answered");

		[tile display];
		check([[tile badgeLabel] isEqual:@"3"], "display with no compositor is harmless and keeps the label");

		check([tile size].width == 48.0 && [tile size].height == 48.0,
		      "the tile's size is the Dock's 48-point metric");

		{
			NSDictionary *badges = [NSDockTile badgeLabelsByApplicationIdentifier];

			check(badges != nil && [badges isKindOfClass:[NSDictionary class]],
			      "the Dock's lookup answers a dictionary even with no compositor");
			check([badges count] == 0, "and it is empty when nothing has been published");
		}

		[tile setBadgeLabel:nil];
		check([tile badgeLabel] == nil, "a nil label clears it");

		printf("dock_tile: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
