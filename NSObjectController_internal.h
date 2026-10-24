/*
 * NSObjectController_internal.h — the doors `NSArrayController` needs from its superclass, and no caller does.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THREE SEAMS, EACH ONE A FACT THE PUBLIC HEADER SHOULD NOT HAVE TO ADMIT.** A subclass that derives MORE state
 * from `content` than its superclass does has to hook the announcement, not repeat it: the will/did pair below is
 * the single place `NSObjectController` announces its derived keys, so `NSArrayController` extends the pair instead
 * of writing a second one — the "one announcer per key" rule that KVO's automatic setter and `NSKeyValueBinding`
 * both live by. The insertion primitive exists for the same reason: an arranged index is translated to a CONTENT
 * index, and the to-many announcement belongs at the content, once. And the marker question is the selection proxy's
 * one consultation of its controller, which `alwaysUsesMultipleValuesMarker` changes.
 *
 * **NOTHING HERE IS APPLE'S API.** The names are prefixed `fn_` for the reason the whole tree prefixes ITS OWN
 * private doors, and this header is not imported by the public headers.
 */
#ifndef AGORA_APPKIT_NSOBJECTCONTROLLER_INTERNAL_H
#define AGORA_APPKIT_NSOBJECTCONTROLLER_INTERNAL_H

#import <AppKit/NSObjectController.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSObjectController (AGControllerSubstrate)

/* **THE ANNOUNCEMENT SEAM.** A mutation calls the `will` half before it writes and the `did` half after. The base
 * class announces `contentObject`, `selection`, `selectedObjects`, `canAdd` and `canRemove`; a subclass that adds
 * derived state calls `super` and then adds its own keys. The pair is NOT public because a door that lets any caller
 * open a KVO bracket on someone else's object is a trap rather than an API. */
- (void)fn_willChangeDerivedKeys;
- (void)fn_didChangeDerivedKeys;

/* **THE INSERTION PRIMITIVE.** Inserts one object into a mutable array or set content at a CONTENT index, with the
 * to-many announcement on `content` and the derived-key pair around it. It raises `NSRangeException` for an array
 * index past the end, and `NSInvalidArgumentException` for a content that cannot take an insertion — the same rules
 * `-addObject:` states, which is why `-addObject:` is this method at the end of the array. */
- (void)fn_insertObject:(id)object atContentIndex:(NSUInteger)index;

/* **THE PROXY'S ONE QUESTION.** NO here: a single selected object forwards its value and several agree or answer a
 * marker. `NSArrayController` answers `alwaysUsesMultipleValuesMarker` here, which is the only thing that flag means
 * to the proxy. */
- (BOOL)fn_selectionAlwaysUsesMultipleValuesMarker;

@end

NS_ASSUME_NONNULL_END

#endif /* AGORA_APPKIT_NSOBJECTCONTROLLER_INTERNAL_H */
