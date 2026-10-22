/*
 * NSTextTable_internal.h — the collapse-aware drawing door, which Apple's signature has no room for.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * NOT INSTALLED. Apple's `-drawBackgroundForBlock:withFrame:inView:characterRange:layoutManager:` has no edge mask, and a
 * collapsing table needs one: a shared edge is drawn by ONE of the two cells that meet there. The mask is carried in
 * `-_drawingEdges` THROUGH the Apple-shaped door, so a subclass overrides one door and still sees what the manager handed
 * down.
 */
#ifndef APPKIT_NSTEXTTABLE_INTERNAL_H
#define APPKIT_NSTEXTTABLE_INTERNAL_H

#import <AppKit/NSTextTable.h>

@interface NSTextTable (NSTextTableInternal)
- (void)drawBackgroundForBlock:(NSTextTableBlock *)block withFrame:(NSRect)frameRect inView:(nullable NSView *)controlView
		characterRange:(NSRange)charRange layoutManager:(nullable NSLayoutManager *)layoutManager
			 edges:(NSTextBlockEdge)edges;
- (NSTextBlockEdge)_drawingEdges;
/* **THE GRID THE MANAGER MEASURED**, published so `-rectForBlock:layoutAtPoint:...` can answer: one width per column and
 * the container's line-fragment padding, which is where column zero begins. The table COPIES the widths, because the
 * manager's array is freed when its pass ends and a table outlives its layout. */
- (void)_setColumnWidths:(const CGFloat *)widths count:(NSInteger)count padding:(CGFloat)padding;
- (BOOL)_hasColumnGeometry;
@end

#endif /* APPKIT_NSTEXTTABLE_INTERNAL_H */
