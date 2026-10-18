/*
 * NSTextBlock_internal.h — the painter, as a door a table can reach without re-entering a block's own override.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * NOT INSTALLED, and this tier's own door. `NSTextBlock` draws its ground and its edges; `NSTextTableBlock` forwards its
 * drawing to its TABLE, so that subclassing `NSTextTable` and overriding its
 * `-drawBackgroundForBlock:withFrame:inView:characterRange:layoutManager:` changes how cells are drawn. The table's default
 * implementation must then paint the BLOCK — and if it reached that through the block's public door it would land back in
 * `NSTextTableBlock`'s forwarding override and recurse. So the painter lives here.
 */
#ifndef APPKIT_NSTEXTBLOCK_INTERNAL_H
#define APPKIT_NSTEXTBLOCK_INTERNAL_H

#import <AppKit/NSTextBlock.h>
#import <AppKit/NSLayoutManager.h>

@interface NSTextBlock (NSTextBlockInternal)
- (void)_drawBackgroundWithFrame:(NSRect)frame inView:(nullable NSView *)view
		  characterRange:(NSRange)charRange layoutManager:(nullable NSLayoutManager *)layoutManager
			   edges:(NSTextBlockEdge)edges;
@end

#endif /* APPKIT_NSTEXTBLOCK_INTERNAL_H */
