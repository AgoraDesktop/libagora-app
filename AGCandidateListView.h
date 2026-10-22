/*
 * AGCandidateListView.h — THE ROW OF READINGS AN INPUT METHOD OFFERS, AND THE ONE PICKED.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THIS IS THE THING THE CANDIDATE WINDOW DRAWS, AND IT IS A VIEW FOR THE SAME REASON A MENU'S ROWS ARE.** A menu's
 * row layout lives in `NSMenuView` and its per-row ink in a cell; a candidate list is smaller but the same shape — a
 * horizontal run of titles, one of them MARKED — so it is a view whose `-drawRect:` is the whole of it. The strings
 * are what it holds; the selected INDEX is what the person is on; and its SIZE is measured from the strings, because
 * a candidate list that clipped its longest reading would be useless.
 *
 * **AND IT MEASURES ITSELF SO THE WINDOW CAN BE SIZED BEFORE IT IS SHOWN.** `-cg_sizeForCandidates` is the answer the
 * window asks for its own content size, and the three measures it uses are exported for the same reason
 * `NSMenuRowHeight` is: a window that padded itself by a second copy of the number would disagree with the rows it
 * frames.
 */
#ifndef AG_CANDIDATE_LIST_VIEW_H
#define AG_CANDIDATE_LIST_VIEW_H

#import <AppKit/NSView.h>

NS_ASSUME_NONNULL_BEGIN

/* THE LIST'S OWN MEASURES, shared with the window that sizes itself around this view. */
extern const CGFloat AGCandidateRowHeight;
extern const CGFloat AGCandidatePanelPadding;
extern const CGFloat AGCandidateTitlePadding;

@interface AGCandidateListView : NSView
{
@private
	NSArray *_candidates;	/* RETAINED: the strings, in order */
	NSInteger _selectedIndex;
}

/* **THE READINGS, AND WHICH ONE IS MARKED.** Setting either redraws; the index is clamped to the list, so a caller
 * that shrinks the list cannot leave the mark off the end. */
- (NSArray *)candidates;
- (void)setCandidates:(nullable NSArray *)candidates;
- (NSInteger)selectedIndex;
- (void)setSelectedIndex:(NSInteger)index;

/* **THE SIZE THIS LIST WANTS FOR WHAT IT HOLDS**, which is the window's content size too: the panel's own padding
 * around a single row, and each title plus the air either side of it. */
- (NSSize)cg_sizeForCandidates;

/* **THE BOX A CANDIDATE OCCUPIES, AND THE INVERSE.** A click asks the second; the first is what the second and the
 * drawing both walk. */
- (NSRect)cg_rectForCandidateAtIndex:(NSInteger)index;
- (NSInteger)cg_indexAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END

#endif /* AG_CANDIDATE_LIST_VIEW_H */
