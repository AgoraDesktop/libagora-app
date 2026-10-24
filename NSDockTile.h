/*
 * NSDockTile.h — an application's tile in the Dock: the badge it shows, and the view it would draw.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE TILE IS THE APPLICATION'S, AND THE BADGE IS PUSHED.** Apple's `NSDockTile` belongs to `NSApplication` and the
 * Dock draws it; setting a badge asks the Dock to show a label it did not compute. This tier's Dock is a separate
 * program, so the label travels the way `agora-shell` version 8 says: the application sends it
 * (`agora_window.set_badge`), the server keeps it on every window of that connection, and the Dock reads it out of the
 * window list it already takes. Nothing here asks a question and waits — a badge is the application's own answer, and
 * it changes when the application decides.
 *
 * **`-display` IS THE RE-SEND DOOR.** A badge set before the application has a window has nowhere to live on the
 * server, so the tile keeps it and `-display` sends the effective label again; that is also what a caller uses after it
 * knows a window is up. It is the honest reading of Apple's "tell the Dock to redraw this tile" when the tile is drawn
 * by another process.
 *
 * **WHAT THIS TIER DOES NOT DO, SAID AT THE DOOR.** `-contentView` is stored and answered and NOT drawn: a view belongs
 * to this process, and compositing it inside the Dock's tile would need the Dock to ask the application to render into
 * a surface of the Dock's — a second protocol, not a property. Apple's own Dock does exactly that, which is why the door
 * is here and the drawing is not. **OWED: the content view's rendering.** `-size` answers the Dock's tile metric (48
 * points), because a tile's size changes with the Dock's own setting and there is no request for it yet.
 *
 * **AND THE DOCK'S HALF IS THIS CLASS'S CLASS METHOD.** Apple's Dock is a private program; Agora's is `dock`, and it is
 * a client of this library, so the lookup it needs is here: `+badgeLabelsByApplicationIdentifier` answers what the
 * running applications have published, keyed by bundle identifier.
 */
#ifndef APPKIT_NSDOCKTILE_H
#define APPKIT_NSDOCKTILE_H

#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSApplication;
@class NSDictionary;
@class NSString;
@class NSView;

@interface NSDockTile : NSObject
{
	NSApplication *_owner;		/* NOT retained: the application owns its tile */
	NSString *_badgeLabel;		/* COPIED: what the application last set */
	NSView *_contentView;		/* RETAINED, stored and not drawn — see the header block */
	BOOL _showsApplicationBadge;
}

/* THE TILE'S OWNER: the application, which is what Apple's `-owner` means. */
- (nullable NSApplication *)owner;

/* THE LABEL THE DOCK SHOWS OVER THE ICON. An empty or nil label clears it. Setting it pushes the effective label to
 * the server at once; `-display` sends it again. */
- (nullable NSString *)badgeLabel;
- (void)setBadgeLabel:(nullable NSString *)label;

/* **WHETHER THE BADGE IS SHOWN AT ALL**, YES by default. NO sends an empty label — the label is kept, so a later YES
 * (with `-display`) brings it back without the caller re-setting it. */
- (BOOL)showsApplicationBadge;
- (void)setShowsApplicationBadge:(BOOL)flag;

/* THE VIEW THE TILE WOULD DRAW, stored and answered; nothing draws it (OWED). */
- (nullable NSView *)contentView;
- (void)setContentView:(nullable NSView *)view;

/* ASK THE DOCK TO REDRAW: re-send the effective badge label. */
- (void)display;

/* The tile's size in points — the Dock's own tile metric in this tier. */
- (NSSize)size;

/* **THE DOCK'S HALF: WHAT THE RUNNING APPLICATIONS HAVE PUBLISHED.** Keyed by bundle identifier; an application with no
 * badge is absent, and an empty answer (no compositor, or nothing published) is an empty dictionary, not nil. */
+ (NSDictionary *)badgeLabelsByApplicationIdentifier;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDOCKTILE_H */
