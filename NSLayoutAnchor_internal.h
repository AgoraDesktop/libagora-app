/*
 * NSLayoutAnchor_internal.h — how a view makes an anchor.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **AN ANCHOR HAS NO PUBLIC INITIALISER, BECAUSE AN ANCHOR WITH NO ITEM IS NOT AN ANCHOR.** Apple's class is made
 * only by a view's anchor doors, and this tier keeps that shape: `NSView` calls the factory below, and a caller who
 * wants an anchor asks the view for one. The factory is in an internal header rather than beside the public
 * declarations so the public surface is Apple's, and it is one door rather than four because the RECEIVER is the
 * subclass — `[NSLayoutDimension cg_anchorWithItem:attribute:]` answers a dimension, which is what the compiler
 * checks at the call site.
 */
#ifndef APPKIT_NSLAYOUTANCHOR_INTERNAL_H
#define APPKIT_NSLAYOUTANCHOR_INTERNAL_H

#import <AppKit/NSLayoutAnchor.h>

NS_ASSUME_NONNULL_BEGIN

@class NSView;

@interface NSLayoutAnchor (APPKITAnchorCreation)
/* THE ONE INITIALISER. A nil item is refused by the caller rather than here: every anchor this tier makes comes
 * from an `NSView`, and a view is never nil at that door. */
- (instancetype)cg_initWithItem:(NSView *)item attribute:(NSLayoutAttribute)attribute;
/* AND THE AUTORELEASED FORM, on the subclass the caller names. */
+ (instancetype)cg_anchorWithItem:(NSView *)item attribute:(NSLayoutAttribute)attribute;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSLAYOUTANCHOR_INTERNAL_H */
