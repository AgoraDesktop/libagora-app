/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSText.h — THE ALIGNMENT AND WRITING-DIRECTION VOCABULARIES, IN THE FILE APPLE PUTS THEM IN.
 *
 * **THIS FILE EXISTS BECAUSE OF WHERE APPLE DECLARES THE TWO TYPES, NOT BECAUSE THIS LIBRARY WANTED A NEW HEADER.**
 * `NSTextAlignment` and `NSWritingDirection` are the types behind `NSCell`'s `-alignment` and `-baseWritingDirection`,
 * and Apple declares them HERE — in `AppKit/NSText.h` — which is also the file every one of their ledger rows names as
 * the ground. THE BLANKET RULE THIS UNIT WORKS UNDER IS "MATCH APPLE, INCLUDING WHICH HEADER", so a header named
 * `NSText.h` is the answer rather than an extra block of types inside `NSCell.h`: the alternative would have declared
 * fifteen ledger rows in a file the ledger does not hold them against.
 *
 * THE VALUES ARE THE 10.6 HEADER'S, TRANSCRIBED. `NSTextAlignment` is `NSUInteger` and its five cases run 0 to 4 in
 * Apple's own order; `NSWritingDirection` is `NSInteger` — SIGNED — because its first case is `-1`, which is the whole
 * reason the two types cannot share a spelling.
 *
 * WHAT IS NOT HERE, AND ITS ROWS STAY OPEN: the `NSText` CLASS itself (a view, and the biggest thing this header holds
 * in Apple's tree), the text-movement codes of `NSTextDidEndEditing`, the notification keys, and the two
 * `NSTextWritingDirection*` values that modify a direction "when used with `NSWritingDirectionAttributeName`" — that
 * pair is a vocabulary whose user (an attributed-string attribute key) this tier does not have, so it is named here
 * and left for the unit that brings its user.
 */
#ifndef APPKIT_NSTEXT_H
#define APPKIT_NSTEXT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* **THE ALIGNMENT, IN APPLE'S ORDER — AND THE ORDER IS WHAT MAKES THE VALUES MEANINGFUL**, which is why the era's
 * own trailing comments are kept: the last case is not a position on the line at all, it is "the default alignment for
 * script", and a reader who assumed it was the fifth position would get the RTL case wrong. */
enum {
	NSLeftTextAlignment = 0,	/* Visually left aligned */
	NSRightTextAlignment = 1,	/* Visually right aligned */
	NSCenterTextAlignment = 2,	/* Visually centered */
	NSJustifiedTextAlignment = 3,	/* Fully justified; the last line is natural-aligned */
	NSNaturalTextAlignment = 4	/* The default alignment for script */
};
typedef NSUInteger NSTextAlignment;

/* **AND THE WRITING DIRECTION, WHOSE FIRST CASE IS WHY THE TYPE IS SIGNED.** The era's comment gives the rule that
 * makes `-1` the right spelling rather than a sentinel this library invented: the natural direction is determined by
 * the Unicode Bidi Algorithm, not by a caller. */
enum {
	NSWritingDirectionNatural = -1,		/* Determined by the Unicode Bidi Algorithm, rules P2 and P3 */
	NSWritingDirectionLeftToRight = 0,
	NSWritingDirectionRightToLeft = 1
};
typedef NSInteger NSWritingDirection;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXT_H */
