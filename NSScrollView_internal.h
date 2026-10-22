/*
 * NSScrollView_internal.h — the header seam a table uses.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE HEADER IS A SIBLING OF THE CLIP VIEW.** It does not scroll vertically with the document and it does follow the
 * horizontal offset; that is a property of the scroll view's layout, so the scroll view is where the header lives.
 * Apple's 10.6 scroll view keeps a private header clip view for exactly this; this tier's scroll view keeps the header
 * as a plain subview in the top strip, which is the same relationship with one less object.
 */
#ifndef AGORA_APPKIT_NSSCROLLVIEW_INTERNAL_H
#define AGORA_APPKIT_NSSCROLLVIEW_INTERNAL_H

#import <AppKit/NSScrollView.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSScrollView (AGTableHeader)

/* Install (or remove) the view in the top strip of the content area. The view's frame height is the strip's height;
 * the scroll view sets its width and position during `-tile` and syncs its horizontal bounds in
 * `-reflectScrolledClipView:`.
 *
 * NOT A PUBLIC APPLE DOOR: `NSTableView` is the only caller. */
- (void)cg_setHeaderView:(nullable NSView *)headerView;
- (nullable NSView *)cg_headerView;

@end

NS_ASSUME_NONNULL_END

#endif /* AGORA_APPKIT_NSSCROLLVIEW_INTERNAL_H */
