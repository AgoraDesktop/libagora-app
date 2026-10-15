/*
 * AGComboListView.h — A MENU'S SESSION WITH A LIST'S MARK: the row a combo box currently holds.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A COMBO BOX'S LIST IS NOT A MENU, AND THE TWO THINGS THEY DISAGREE ABOUT ARE BOTH ANSWERED HERE.**
 *
 *   * WHICH ROW IS MARKED — a menu marks only the row the POINTER is on, and a combo box opens its list to answer
 *     "which one am I on", so the held row wears the mark too. `-cg_isItemMarked:` is that answer.
 *   * WHAT A ROW LOOKS LIKE — a menu's row carries a check-mark gutter and a shortcut column, and its highlight is a
 *     chip INSET inside the row, because that inset-and-round is most of what makes a Mac menu read as a menu. A
 *     list's row is plain text with a full-width fill. `-cg_makeItemCell` names the cell those rows are drawn by and
 *     `-cg_markRectForRow:` says how far the fill reaches; `AGComboListCell` is the cell.
 *
 * **AND THE MARK IS THE SAME ACCENT THE POINTER WEARS, WHICH THE SHAPE CHANGE DOES NOT TOUCH.** The highlight of this
 * session is painted by `NSMenuView -drawRect:` — its colour, its inset and its radius all live there — so a subclass
 * that invented a second kind of highlight would be a session drawing two vocabularies for one question. The row under
 * the pointer and the row the box holds differ in WHY they are marked, not in what a mark looks like: both are the
 * accent, and here both are the whole row.
 *
 * THE SESSION IS `NSMenu`'s AND IS NOT DUPLICATED. One traversal loop, one tracking window, one dismissal, one pick —
 * this tier has learned repeatedly that a second copy of a mechanism is how two of them come to disagree, and a combo
 * box's list does not need a second copy of anything except the appearance of a row.
 */
#ifndef AG_COMBO_LIST_VIEW_H
#define AG_COMBO_LIST_VIEW_H

#import <AppKit/NSMenuView.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGComboListView : NSMenuView

@end

NS_ASSUME_NONNULL_END

#endif /* AG_COMBO_LIST_VIEW_H */
