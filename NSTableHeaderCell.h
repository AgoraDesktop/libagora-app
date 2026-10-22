/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSTableHeaderCell.h — the face of one table column's header.
 *
 * It is an `NSTextFieldCell` because a header is a word in a box, and the box is the only thing this class adds: a
 * control-coloured face, a dark bottom and right edge, and centred text. The sort indicator is a public door in the
 * era's header because a caller may draw its own; `NSTableHeaderView` calls it when the column is the sorted one.
 *
 * Written from `NSTableHeaderCell.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSTABLEHEADERCELL_H
#define APPKIT_NSTABLEHEADERCELL_H

#import <AppKit/NSTextFieldCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTableHeaderCell : NSTextFieldCell <NSSecureCoding>

/* THE TWO SORT-INDICATOR DOORS. The rectangle is the room the mark may use; the default is a small square at the
 * right edge. */
- (void)drawSortIndicatorWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView
			 ascending:(BOOL)ascending priority:(NSInteger)priority;
- (NSRect)sortIndicatorRectForBounds:(NSRect)theRect;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTABLEHEADERCELL_H */
