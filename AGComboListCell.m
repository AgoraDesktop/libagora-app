/*
 * AGComboListCell.m — three doors: two that ink nothing, and one that gives the title the whole row.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import "AGComboListCell.h"

@implementation AGComboListCell

/* **AND THE TITLE'S COLUMN IS THE WHOLE ROW.** `NSMenuItemCell` takes the gutter, the image and the key equivalent off
 * the row's width and gives the title what is left, which is right for a menu and wrong for a list: MEASURED, a row
 * whose title is the only thing in it would have been laid out as though two other columns existed, and a list of
 * short words would have been as wide as a menu full of shortcut-bearing items. The row's own padding is NOT added
 * here — it is added by the drawing, one door down, which is where `NSMenuItemCell` puts it and why this answers with
 * the row rather than with the row inset twice. */
- (NSRect)titleRectForBounds:(NSRect)cellFrame
{
	return cellFrame;
}

/* **AND THE TWO COLUMNS A LIST HAS NOT GOT ARE NOT DRAWN.** The view calls these per row whether or not there is
 * anything to ink — the state one is called whenever the item's state is anything but OFF, which is exactly the row
 * this control marks — so a cell that answered with a check mark would put a menu's mark inside a list's row and
 * beside the list's own mark, which is the same fact said twice in two vocabularies. */
- (void)drawStateImageWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
}

- (void)drawKeyEquivalentWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
}

@end
