/*
 * NSCIImageRep.h — A REP OVER A CORE IMAGE, DECLARED AND REFUSED.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **CORE IMAGE IS A FILTER GRAPH AND A GPU PIPELINE, AND NEITHER IS HERE.** Apple's rep wraps a `CIImage` so an AppKit image
 * can be produced by a Core Image chain; this tier has no Core Image at all — `NSColor +colorWithCIColor:` refuses for the
 * same reason, and `NSCIImageRep` is the second half of that absence.
 *
 * **THE DOORS ARE DECLARED WITH `id` RATHER THAN `CIImage *`**, which is the tree's rule for a class it has not got: naming
 * the type in a header can credit a class row nothing answers to (the `NSScreen.h` trap), and a caller passing a `CIImage`
 * pointer is passing an `id` either way. The two constructors refuse by name; `-CIImage` answers nil.
 */
#ifndef APPKIT_NSCIIMAGEREP_H
#define APPKIT_NSCIIMAGEREP_H

#import <AppKit/NSImageRep.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSCIImageRep : NSImageRep

/* Both refuse: Core Image is not in this tier. */
+ (nullable instancetype)imageRepWithCIImage:(nullable id)image;
- (nullable instancetype)initWithCIImage:(nullable id)image;

- (nullable id)CIImage;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCIIMAGEREP_H */
