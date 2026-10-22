/*
 * NSPICTImageRep.h — A REP FOR A PICT FILE, DECLARED AND REFUSED.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **PICT IS THE ERA'S VECTOR-METAFILE FORMAT AND THIS TIER HAS NO DECODER FOR IT.** Apple's class parses the picture —
 * its bounds, its resolution, its QuickDraw drawing opcodes — and plays it back through QuickDraw, which is a drawing stack
 * this tier deliberately does not have (the same absence that leaves `NSQuickDrawView` and the QuickDraw C functions
 * declared and refused).
 *
 * **SO THE CONSTRUCTORS REFUSE BY NAME AND THE REST ANSWERS ITS TYPE'S EMPTY VALUE.** That is the disposition the plan's
 * §A11 names for the QuickDraw family: the doors exist so a ported caller's compile line works, the failure is a message at
 * the call rather than an unresolved symbol at load, and nothing pretends to have read a file. `-PICTRepresentation` and
 * `-boundingBox` can only ever answer a rep that exists, and none does.
 */
#ifndef APPKIT_NSPICTIMAGEREP_H
#define APPKIT_NSPICTIMAGEREP_H

#import <AppKit/NSImageRep.h>

NS_ASSUME_NONNULL_BEGIN

@class NSData;

@interface NSPICTImageRep : NSImageRep

/* Both refuse: a PICT decoder is not in this tier. */
+ (nullable instancetype)imageRepWithData:(nullable NSData *)pictData;
- (nullable instancetype)initWithData:(nullable NSData *)pictData;

- (nullable NSData *)PICTRepresentation;
- (NSRect)boundingBox;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPICTIMAGEREP_H */
