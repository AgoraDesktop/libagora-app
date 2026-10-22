/*
 * NSEPSImageRep.h — A REP FOR AN ENCAPSULATED POSTSCRIPT FILE: its bytes, its bounding box, and the drawing it cannot do.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE HEADER IS PARSEABLE AND THE LANGUAGE IS NOT.** An EPS file begins with comments — `%!PS-Adobe-3.0 EPSF-3.0` and the
 * `%%BoundingBox:` line that says how big the drawing is — and that is a real, testable fact: this class reads the bounds,
 * answers them through `-boundingBox` and `-size`, and hands the bytes back through `-EPSRepresentation`. What it cannot do
 * is RENDER, because rendering PostScript needs an interpreter, and Apple's own route (`CGPSConverter`) is not in this
 * tier. `-drawInRect:` therefore refuses by name: a rep that silently drew nothing would look like a corrupt file.
 *
 * **AND THE SIZE FOLLOWS THE BOUNDING BOX**, which is the whole reason to read it: an EPS that says `%%BoundingBox: 0 0 612
 * 792` is a letter page, and a caller laying one out needs that number before it can place it.
 *
 * **`-prepareGState` IS TAKEN AND DOES NOTHING**, which is stated rather than implied: the era's door exists because
 * PostScript drawing happened through the graphics state of a Display PostScript window server, and there is no such state
 * here.
 */
#ifndef APPKIT_NSEPSIMAGEREP_H
#define APPKIT_NSEPSIMAGEREP_H

#import <AppKit/NSImageRep.h>

NS_ASSUME_NONNULL_BEGIN

@class NSData;

@interface NSEPSImageRep : NSImageRep
{
	NSData *_data;		/* RETAINED: the PostScript the rep was made from */
	NSRect _boundingBox;
}

/* FROM THE BYTES. A rep whose header carries no BoundingBox still exists — the bytes are the file — but its box is empty,
 * and `+canInitWithData:` is what decides whether a caller gets one at all. */
+ (nullable instancetype)imageRepWithData:(nullable NSData *)epsData;
- (nullable instancetype)initWithData:(nullable NSData *)epsData;

/* THE POSTSCRIPT ITSELF, as it was given. */
- (nullable NSData *)EPSRepresentation;

/* THE DRAWING'S BOUNDS FROM THE HEADER, origin included. */
- (NSRect)boundingBox;

/* Declared because Apple declares it; there is no Display PostScript state here for it to prepare. */
- (void)prepareGState;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSEPSIMAGEREP_H */
