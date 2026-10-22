/*
 * NSStatusBar.h — the menu bar's status area, which is a set of items the SERVER places.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * WHAT THIS IS. `NSStatusBar` is the object a status item is made from, and the answers here are the WindowServer's
 * rather than AppKit's: `-thickness` is how much of the screen the menu bar takes, which is precisely what
 * `NSScreen -visibleFrame` leaves out. Two doors onto one number, which is a cross-check worth having.
 *
 * Written from `NSStatusBar.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSStatusItem;
@class NSMutableArray;

@interface NSStatusBar : NSObject
{
@private
	NSMutableArray *_items;
}

/* THE ONE BAR THERE IS. The Mac has a system status bar and no way to make a second one, because there is one menu
 * bar and it belongs to the screen. */
+ (NSStatusBar *)systemStatusBar;

- (NSStatusItem *)statusItemWithLength:(CGFloat)length;
- (void)removeStatusItem:(NSStatusItem *)item;

/* Whether the bar runs down a screen edge instead of along the top. NO, and not by omission: a Wayland output has
 * no orientation this could be derived from, and a vertical menu bar is a thing the Mac cannot express. */
- (BOOL)isVertical;

/* **HOW MUCH OF THE SCREEN THE MENU BAR TAKES — ASKED, NOT ASSUMED.** It is the difference between the screen's
 * frame and its work area, so it is the server's number arriving through the same door `-visibleFrame` uses. 0 when
 * there is no window server to ask, which is a state and not a thickness. */
- (CGFloat)thickness;

@end
