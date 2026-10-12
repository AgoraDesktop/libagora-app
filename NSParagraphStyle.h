/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSParagraphStyle.h — THE LINE-BREAK VOCABULARY, IN THE FILE APPLE PUTS IT IN.
 *
 * **ONE TYPE AND NO CLASSES YET, WHICH IS THE HONEST SHAPE OF A HEADER WHOSE CLASS IS STILL OWED.** `NSLineBreakMode`
 * is what `NSCell`'s `-lineBreakMode` is declared in terms of, and Apple declares it here — in the same file as the
 * `NSParagraphStyle` class that is its chief user — because a line-break mode IS a paragraph property. The blanket
 * rule this unit works under is "match Apple, including which header", so the type arrives in a header named after the
 * class that will follow it rather than beside the cell that happens to need it first.
 *
 * AND THE IMPORT BELOW IS APPLE'S OWN INCLUDE GRAPH, which is worth keeping because it says why the split is real: the
 * era's `NSParagraphStyle.h` imports `AppKit/NSText.h`, because a paragraph style has an ALIGNMENT — so the two
 * headers this unit adds depend on each other in the same direction Apple's do.
 *
 * THE VALUES ARE THE 10.6 HEADER'S, TRANSCRIBED IN ORDER: the mode is `NSUInteger` and the six cases run 0 through 5,
 * with `NSLineBreakByWordWrapping` first — WHICH IS ALSO THE TYPE'S ZERO, so a fresh cell's line-break mode needs no
 * initialiser, unlike the alignment one file over, whose default is not its zero. The era's short gloss on each case is
 * kept, because "truncating head" and "truncating tail" are not shapes a reader can guess from the names alone.
 *
 * WHAT IS NOT HERE, AND ITS ROWS STAY OPEN: `NSTextTab`, `NSParagraphStyle` and `NSMutableParagraphStyle` — three
 * classes with ledgers of their own — and `NSTabColumnTerminatorsAttributeName`, the attribute key naming the
 * `NSCharacterSet` that terminates a tab column.
 */
#ifndef APPKIT_NSPARAGRAPHSTYLE_H
#define APPKIT_NSPARAGRAPHSTYLE_H

#import <AppKit/NSText.h>

NS_ASSUME_NONNULL_BEGIN

/* WHAT TO DO WITH A LINE THAT IS TOO LONG. The era comments each case with the shape a caller gets, and the first
 * entry is the default — the class this type belongs to states that in as many words. */
enum {
	NSLineBreakByWordWrapping = 0,		/* Wrap at word boundaries; the default */
	NSLineBreakByCharWrapping,		/* Wrap at character boundaries */
	NSLineBreakByClipping,			/* Simply clip the overflow */
	NSLineBreakByTruncatingHead,		/* Truncate at the head: "...wxyz" */
	NSLineBreakByTruncatingTail,		/* Truncate at the tail: "abcd..." */
	NSLineBreakByTruncatingMiddle		/* Truncate the middle: "ab...yz" */
};
typedef NSUInteger NSLineBreakMode;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPARAGRAPHSTYLE_H */
