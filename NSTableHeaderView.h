/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSTableHeaderView.h — the row of column headers above a table.
 *
 * **THE HEADER IS A SIBLING OF THE CLIP VIEW, NOT A SUBVIEW OF THE TABLE.** A table's rows scroll; its headers do
 * not. This view is installed by `NSTableView` into its enclosing `NSScrollView` (through the scroll view's private
 * header seam), takes the top strip of the scroll view's content area, and follows the clip view's horizontal
 * offset only. That is what keeps a column's title over its column while the rows move underneath.
 *
 * A DIVIDER DRAG IS THE HEADER'S OWN GESTURE. The right few points of a column's header begin a resize; the width is
 * clamped by the column's min/max, the table is re-tiled, and the scroll view's header width stays the visible width.
 *
 * Written from `NSTableHeaderView.h` in the MacOSX10.6 SDK (see PROVENANCE.md). Column REORDERING is not in this
 * slice, so `-draggedColumn` answers -1 and `-draggedDistance` answers 0.
 */
#ifndef APPKIT_NSTABLEHEADERVIEW_H
#define APPKIT_NSTABLEHEADERVIEW_H

#import <AppKit/NSView.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTableView;

@interface NSTableHeaderView : NSView
{
	NSTableView *_tableView;		/* NOT RETAINED: the table owns its header view */
	NSInteger _resizedColumn;
	NSInteger _pressedColumn;
	CGFloat _resizeStartX;
	CGFloat _resizeStartWidth;
	BOOL _resizing;
}

- (void)setTableView:(nullable NSTableView *)tableView;
- (nullable NSTableView *)tableView;

/* THE REORDERING STATE, WHICH THIS SLICE DOES NOT REACH. */
- (NSInteger)draggedColumn;
- (CGFloat)draggedDistance;

/* THE COLUMN CURRENTLY BEING RESIZED, or -1. */
- (NSInteger)resizedColumn;

/* THE GEOMETRY THE TABLE AND THE POINTER SHARE. */
- (NSRect)headerRectOfColumn:(NSInteger)column;
- (NSInteger)columnAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTABLEHEADERVIEW_H */
