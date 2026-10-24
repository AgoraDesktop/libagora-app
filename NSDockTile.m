/*
 * NSDockTile.m — the badge the application pushes, and the Dock's lookup of what the others published.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE BADGE IS PUSHED THROUGH ONE WINDOW AND APPLIED TO EVERY ONE OF THEM.** `agora-shell` 8's `set_badge` is a
 * request on a window, and the server gives it to every window of the connection, because the connection is the
 * application. So this class needs one window id — any of the application's — and it takes the last the window list
 * gave, which is the same choice `NSDockMenu` makes for the same reason: the ids are the only names the two sides
 * share.
 *
 * **A BADGE SET BEFORE THERE IS A WINDOW IS KEPT, NOT LOST.** There is nowhere on the server for it to live until the
 * application has a surface, so the tile holds the label and `-display` sends it again; that is what the door is for.
 * The alternative — refusing to hold it — would make the ordinary "set the badge at launch" order wrong.
 */
#import <AppKit/NSDockTile.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWorkspace.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

#import "platform/AGWindowServer.h"

/* THE DOCK'S TILE METRIC IN THIS TIER. Apple's `-size` reports the tile's current size, which changes with the Dock's
 * own setting; no request carries that yet, and `dock` draws a 48-point tile (its README's own number). */
#define FN_DOCK_TILE_SIZE 48.0

@implementation NSDockTile

- (id)init
{
	self = [super init];
	if (self != nil) {
		_owner = [NSApplication sharedApplication];	/* NOT retained: the application owns the tile */
		_showsApplicationBadge = YES;
	}
	return self;
}

- (void)dealloc
{
	[_badgeLabel release];
	[_contentView release];
	[super dealloc];
}

- (NSApplication *)owner
{
	return _owner;
}

/* WHAT THE SERVER SHOULD HOLD: the label when the badge is shown, and the empty string when it is not — a hidden badge
 * is not a different label, it is nothing to show. */
- (NSString *)fn_effectiveLabel
{
	return (_showsApplicationBadge && _badgeLabel != nil) ? _badgeLabel : @"";
}

- (void)fn_push
{
	NSArray *ids = [[NSRunningApplication currentApplication] cg_windowIDs];

	if ([ids count] == 0) {
		return;		/* no window yet: the label is kept, and -display sends it once there is one */
	}
	{
		int sent = AGWindowSetDockBadge(AGWindowServerShared(),
					       (unsigned int)[[ids lastObject] unsignedIntValue],
					       [[self fn_effectiveLabel] UTF8String]);

		(void)sent;	/* 0 means there is nowhere to send it yet; the label is kept either way */
	}
}

- (NSString *)badgeLabel
{
	return _badgeLabel;
}

- (void)setBadgeLabel:(NSString *)label
{
	NSString *copy = [label copy];

	[_badgeLabel release];
	_badgeLabel = copy;
	[self fn_push];
}

- (BOOL)showsApplicationBadge
{
	return _showsApplicationBadge;
}

- (void)setShowsApplicationBadge:(BOOL)flag
{
	_showsApplicationBadge = flag;
	[self fn_push];
}

- (NSView *)contentView
{
	return _contentView;
}

- (void)setContentView:(NSView *)view
{
	[view retain];
	[_contentView release];
	_contentView = view;
	/* STORED AND NOT DRAWN — see the header's OWED note: the Dock would have to ask this process to render. */
}

- (void)display
{
	[self fn_push];
}

- (NSSize)size
{
	return NSMakeSize(FN_DOCK_TILE_SIZE, FN_DOCK_TILE_SIZE);
}

/* **THE DOCK'S HALF: THE BADGES OF THE RUNNING APPLICATIONS, BY BUNDLE IDENTIFIER.** The running-application list gives
 * each application its window ids (the AppKit already fills them from the window list), and the seam's snapshot gives
 * each id its badge; the first window that has one names the application's label. An application with no badge is
 * absent from the answer, and a compositor that says nothing yields an empty dictionary rather than nil. */
+ (NSDictionary *)badgeLabelsByApplicationIdentifier
{
	NSMutableDictionary *answer = [NSMutableDictionary dictionary];
	AGWindowServer *server = AGWindowServerShared();
	const AGWindowInfo *rows;
	NSArray *applications;
	int count = 0;
	NSUInteger i;

	rows = AGWindowListRows(server, &count);
	if (rows == NULL || count == 0) {
		return answer;
	}
	applications = [[NSWorkspace sharedWorkspace] runningApplications];
	for (i = 0; i < [applications count]; i++) {
		NSRunningApplication *application = [applications objectAtIndex:i];
		NSArray *ids = [application cg_windowIDs];
		NSUInteger j;

		for (j = 0; j < [ids count]; j++) {
			unsigned int id = (unsigned int)[[ids objectAtIndex:j] unsignedIntValue];
			int k;

			for (k = 0; k < count; k++) {
				if (rows[k].id != id) {
					continue;
				}
				if (rows[k].badge[0] != '\0' && [application bundleIdentifier] != nil) {
					[answer setObject:[NSString stringWithUTF8String:rows[k].badge]
						   forKey:[application bundleIdentifier]];
				}
				break;	/* one answer per application: the first window that has one */
			}
			if ([answer objectForKey:[application bundleIdentifier]] != nil) {
				break;
			}
		}
	}
	return answer;
}

@end
