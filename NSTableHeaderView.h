/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * A COLUMN DRAG IS THE HEADER'S SECOND GESTURE. A press that misses the divider is a reorder candidate; once the
 * pointer has travelled past the threshold the column is moved through `-moveColumn:toColumn:`, and the table's
 * delegate can refuse with `-tableView:shouldReorderColumn:toColumn:`. `-draggedColumn` and `-draggedDistance` report
 * the gesture while it runs.
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
	NSInteger _draggedColumn;
	CGFloat _draggedDistance;
	CGFloat _dragStartX;
	BOOL _didDrag;
}

- (void)setTableView:(nullable NSTableView *)tableView;
- (nullable NSTableView *)tableView;

/* THE REORDERING STATE: the column being dragged, how far the pointer has moved, and whether it has crossed the
 * threshold that turns the press into a drag. */
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
