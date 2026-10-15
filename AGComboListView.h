/*
 * AGComboListView.h — A MENU'S SESSION WITH A LIST'S MARK: the row a combo box currently holds.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A COMBO BOX'S LIST IS NOT A MENU, AND THIS IS THE PART OF THAT WHICH THIS TIER CAN HONESTLY SEPARATE.** The two
 * disagree about two things and only one of them is cheap:
 *
 *   * WHAT A ROW LOOKS LIKE — a menu's rows carry a check-mark gutter and a shortcut column, and their highlight is a
 *     chip INSET inside the row, because that inset-and-round is most of what makes a Mac menu read as a menu. A list's
 *     row is plain text with a full-width fill for the row you are on. THIS CLASS DOES NOT CHANGE ANY OF THAT YET, and
 *     the skin is still owed rather than quietly declared done.
 *   * WHICH ROW IS MARKED — and this is the one a person notices, because a combo box opens its list to answer "which
 *     one am I on" and a menu marks only the row the POINTER is on. So the held row wears the mark.
 *
 * **AND THE MARK IS THE SAME CHIP THE POINTER WEARS.** That is deliberate: the highlight of this session is painted by
 * `NSMenuView -drawRect:` — the chip's shape, its colour and its inset all live there — and a subclass that invented a
 * second kind of highlight would be a session drawing two vocabularies for one question. The row under the pointer and
 * the row the box holds differ in WHY they are marked, not in what a mark looks like, so they look the same; the SKIN
 * question above is where a full-width fill would arrive, and it would arrive for both.
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
