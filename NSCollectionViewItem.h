/*
 * NSCollectionViewItem.h — ONE ITEM'S VIEW CONTROLLER.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **COLLECTION VIEWS WORK BY RECYCLING CONTROLLERS, AND THIS IS THE CONTROLLER.** A collection view shows a grid of items
 * that are made, shown, scrolled out of sight and REUSED; each item is an `NSViewController` whose view is the tile, which is
 * why this class derives from the view controller rather than from the view. Two facts are its own: the collection view it
 * belongs to (borrowed) and whether it is SELECTED, which is what a tile's highlight reads.
 *
 * **`NSCollectionView` ITSELF IS NOT HERE**, and the class says so rather than implying it: this tier has no collection view,
 * so nothing produces an item — the doors exist so a ported caller's compile line works and so the subclass a caller writes
 * can be compiled and its `-isSelected`/`-setSelected:` pair used. It is the same disposition `NSScreen -colorSpace` had
 * before `NSColorSpace` arrived: declared, answered, and waiting for the class it belongs to.
 */
#ifndef APPKIT_NSCOLLECTIONVIEWITEM_H
#define APPKIT_NSCOLLECTIONVIEWITEM_H

#import <AppKit/NSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class NSCollectionView;

@interface NSCollectionViewItem : NSViewController
{
	NSCollectionView *_collectionView;	/* NOT RETAINED: the view owns its items */
	BOOL _selected;
}

/* THE COLLECTION VIEW IT BELONGS TO, borrowed, and nil until one adopts it. */
- (nullable NSCollectionView *)collectionView;
- (void)setCollectionView:(nullable NSCollectionView *)collectionView;

/* WHETHER THE TILE IS SELECTED, which is the fact a tile's own drawing reads. */
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLLECTIONVIEWITEM_H */
