/*
 * NSCollectionViewItem — one item's view controller.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * Two facts and their accessors; everything else is `NSViewController`'s. See the header for why the class exists before the
 * view it belongs to does.
 */
#import "NSCollectionViewItem.h"

@implementation NSCollectionViewItem

- (NSCollectionView *)collectionView
{
	return _collectionView;
}

- (void)setCollectionView:(NSCollectionView *)collectionView
{
	_collectionView = collectionView;	/* NOT RETAINED */
}

- (BOOL)isSelected
{
	return _selected;
}

- (void)setSelected:(BOOL)selected
{
	if (_selected == (selected ? YES : NO)) {
		return;
	}
	_selected = selected ? YES : NO;
	/* **A SELECTION CHANGE IS A PICTURE CHANGE**, which is the whole reason a tile wants to know: the view it controls draws
	 * its highlight differently. Asking the view to redraw here is what makes `-setSelected:` more than a stored bit. */
	[[self view] setNeedsDisplay:YES];
}

@end
