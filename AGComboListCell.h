/*
 * AGComboListCell.h — A LIST'S ROW: no check-mark gutter, no shortcut column, and the marked row filled edge to edge.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A MENU'S ROW AND A LIST'S ROW ARE THE SAME ROW WITH TWO COLUMNS TAKEN OFF.** `NSMenuItemCell` lays a row out in
 * four strips: a state-image GUTTER for the check mark, the item's image, the title, and a key-equivalent column
 * pinned to the trailing edge. A menu needs all four — a check mark is how a menu says "this is the current choice"
 * and a shortcut is how it says which key does the same thing. A combo box's list needs none of the first, third or
 * fourth: it has no shortcuts to advertise and its mark is not a check mark, and the two columns it does not draw are
 * two columns it should not MEASURE either, or its rows would be wider than the words in them.
 *
 * **SO THIS CELL OVERRIDES THREE DOORS AND NOTHING ELSE.** The title's column becomes the whole row (the menu's
 * arithmetic subtracts the gutters from it), and the two DRAWING doors that ink a column this control has none of
 * answer with nothing. Everything else — the font, the ink, the disabled state, the left alignment, the row's own
 * padding inside the title's column — is `NSMenuItemCell`'s and is inherited on purpose: a list and a menu disagree
 * about WHICH COLUMNS a row has, not about how a piece of text is drawn in one.
 *
 * **AND WHY A DOOR WITH NOTHING TO SAY IS NOT A REFUSAL.** `-drawTitleWithFrame:` says it in its own words — a
 * separator has no title, an image-only item has none, and a row too narrow for its own parts has an empty rect, and
 * all three are correct answers. A row with no gutter to draw is the same kind of answer, so nothing here prints.
 */
#ifndef AG_COMBO_LIST_CELL_H
#define AG_COMBO_LIST_CELL_H

#import <AppKit/NSMenuItemCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGComboListCell : NSMenuItemCell

@end

NS_ASSUME_NONNULL_END

#endif /* AG_COMBO_LIST_CELL_H */
