/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSActionCell.h — THE CELL THAT CARRIES A TARGET AND AN ACTION (stage E).
 *
 * THIS CLASS ADDS NO MEMBER OF ITS OWN, AND THAT IS APPLE'S SHAPE RATHER THAN A SHORTCUT. Apple's `NSActionCell`
 * declares exactly three things — `target`, `action` and `tag` — and THIS TREE'S `NSCell` ALREADY DECLARES ALL
 * THREE, because the era's own `NSCell.h` does (which is why the plan's earlier slices shipped them there). SO THE
 * CLASS IS A MARKER, and it says so instead of copying three doors down one level to look busy: what it exists FOR
 * is the hierarchy, and in this tree the hierarchy is the whole of what it contributes.
 *
 * AND ITS THREE LEDGER ROWS ARE CREDITED BY THE ANCESTOR RULE THE SWEEP ALREADY APPLIES to every member — a row is
 * declared when the owner's own block OR AN ANCESTOR'S declares it. Which means this class is the first one in stage
 * E whose rows were satisfied before it existed, and the honest thing to do with that is to say it plainly rather
 * than to look for work to do.
 *
 * IT IS ALSO THE CHAIN'S NEXT LINK, which is why it lands before the class that needs it: `NSCell` -> NSActionCell
 * -> `NSButtonCell`, and `NSButtonCell` is what `NSMenuItemCell` will eventually be re-based onto so that this plan
 * stops carrying a superclass deviation it does not want.
 */
#ifndef APPKIT_NSACTIONCELL_H
#define APPKIT_NSACTIONCELL_H

#import <AppKit/NSCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSActionCell : NSCell <NSSecureCoding>

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSACTIONCELL_H */
