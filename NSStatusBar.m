/*
 * NSStatusBar.m — the status area, whose items the SERVER places.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */

#import "NSStatusBar.h"
#import "NSStatusItem.h"
#import "NSScreen.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSGeometry.h>

static NSStatusBar *s_systemStatusBar = nil;

@implementation NSStatusBar

+ (NSStatusBar *)systemStatusBar
{
	/* ONE BAR, MADE ON FIRST USE. The Mac has a system status bar and no way to make a second one, because there
	 * is one menu bar and it belongs to the screen. */
	if (s_systemStatusBar == nil) {
		s_systemStatusBar = [[NSStatusBar alloc] init];
	}
	return s_systemStatusBar;
}

- (id)init
{
	self = [super init];
	if (self != nil) {
		_items = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_items release];
	[super dealloc];
}

- (NSStatusItem *)statusItemWithLength:(CGFloat)length
{
	NSStatusItem *item = [[NSStatusItem alloc] cg_initWithStatusBar:self length:length];

	if (item == nil) {
		return nil;
	}
	/* THE BAR OWNS ITS ITEMS: the Mac's `-statusItemWithLength:` returns an item the caller does not release,
	 * and `-removeStatusItem:` is how it goes away. */
	[_items addObject:item];
	[item release];
	return item;
}

- (void)removeStatusItem:(NSStatusItem *)item
{
	if (item == nil) {
		return;
	}
	[_items removeObjectIdenticalTo:item];
}

- (BOOL)isVertical
{
	return NO;
}

- (CGFloat)thickness
{
	/* **ASKED, NOT ASSUMED, AND THROUGH THE SAME DOOR `-visibleFrame` USES.** The menu bar's height is what the
	 * screen's work area leaves out, so this is the window server's number arriving twice by two routes — and the
	 * `appkit-work-area` test asserts the two agree. 0 when there is no screen to ask, which is a state and not a
	 * thickness; a caller that makes an item anyway gets an item of no width, not a guess. */
	NSScreen *screen = [NSScreen mainScreen];
	NSRect whole, work;
	CGFloat reserved;

	if (screen == nil) {
		return 0.0;
	}
	whole = [screen frame];
	work = [screen visibleFrame];
	reserved = whole.size.height - work.size.height;
	return reserved > 0.0 ? reserved : 0.0;
}

@end
