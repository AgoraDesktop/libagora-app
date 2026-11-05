/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSBundleAdditions.h — AppKit's category on NSBundle (§63.52). MOVED HERE FROM FOUNDATION.
 *
 * ⚠ WHY THEY ARE NOT FOUNDATION'S, MEASURED RATHER THAN ASSUMED (the user's directive, 2026-10-01: *"removing
 * from our Foundation implementation anything which does not belong in Foundation … CoreGraphics or the like
 * are not"*): `-pathForImageResource:` and `-URLForImageResource:` are declared by **AppKit's `NSImage.h`** and
 * `-pathForSoundResource:` by **AppKit's `NSSound.h`** — the macOS 14.5 SDK headers settle it, and Apple's own
 * doc index has **no rows for any of the three**, which is why the ledger never asked for them and why they sat
 * in Foundation unchallenged. They are AppKit's because what a "image resource" and a "sound resource" ARE is
 * decided by `NSImage` and `NSSound`, and neither class is Foundation's.
 *
 * ✅ AND THE SPLIT HAS HAPPENED: Apple puts the image pair in `NSImage.h` and the sound door in `NSSound.h`,
 * and `-pathForSoundResource:` is now declared in `NSSound.h` (this header said it would move "when a real
 * `NSSound` arrives"). What stays here is the *implementation*, because both doors share one lookup — a name
 * with an optional extension, the literal name winning — and that lookup is not worth having twice. The image
 * pair is still here rather than in `NSImage.h` for a smaller reason: `NSImage.h` is Foundation-adjacent and
 * already large, and moving two declarations changes no behaviour. */

#ifndef APPKIT_NSBUNDLEADDITIONS_H
#define APPKIT_NSBUNDLEADDITIONS_H

#import <Foundation/NSBundle.h>

NS_ASSUME_NONNULL_BEGIN

/* The name parameter is Apple's `NSImageName`, a `typedef` of `NSString`. `-pathForSoundResource:` and its
 * `NSSoundName` are declared in `NSSound.h`, which is where Apple declares them. */
@interface NSBundle (NSBundleAppKitAdditions)

/* THE NAME'S EXTENSION IS OPTIONAL, which is the whole point of the door: `@"pic"` finds `pic.png` and
 * `@"logo.png"` finds itself (the literal name wins). A miss is nil. */
- (nullable NSString *)pathForImageResource:(NSString *)name;
- (nullable NSURL *)URLForImageResource:(NSString *)name;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBUNDLEADDITIONS_H */
