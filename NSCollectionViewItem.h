/*
 * NSCollectionViewItem.h — ONE ITEM'S VIEW CONTROLLER.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **COLLECTION VIEWS WORK BY RECYCLING CONTROLLERS, AND THIS IS THE CONTROLLER.** A collection view shows a grid of items
 * that are made, shown, scrolled out of sight and REUSED; each item is an `NSViewController` whose view is the tile, which is
 * why this class derives from the view controller rather than from the view. Two facts are its own: the collection view it
 * belongs to (borrowed) and whether it is SELECTED, which is what a tile's highlight reads.
 *
 * **`NSCollectionView` HAS ARRIVED, AND IT COPIES THIS CLASS TO MAKE ITS TILES.** The view's default factory copies the
 * prototype item, which is why this class conforms to `NSCopying`: the copy carries the item's CLASS, its view's class and
 * frame, the represented object and the selected bit. **IT DOES NOT CARRY A SUBCLASS'S OWN IVARS** — this tier has no
 * archiving copy of a controller — so a prototype with state either overrides `-copyWithZone:` or a caller
 * overrides `-newItemForRepresentedObject:` on the view. That is named here because it is the difference between a prototype that is a
 * template and one that is a bag of state.
 */
#ifndef APPKIT_NSCOLLECTIONVIEWITEM_H
#define APPKIT_NSCOLLECTIONVIEWITEM_H

#import <AppKit/NSViewController.h>

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSCollectionView;

@interface NSCollectionViewItem : NSViewController <NSCopying>
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

/* **THE LOADED VIEW, OR NIL, WITHOUT ASKING `-view` — WHICH WOULD LOAD OR RAISE.** A collection view must decide whether
 * an item has a tile before it frames or adopts it, and `-view` is the door that loads a nib or raises when there is
 * nothing to load. This one answers the stored view and nothing else; `cg_` because it is this tier's spelling, like the
 * other `cg_` doors. */
- (nullable NSView *)cg_viewIfLoaded;

/* AND THE COPY'S CONTRACT IS `NSCOPYING`'S: a +1 object of the same class, with the view's class and frame, the
 * represented object and the selected bit. See the header for what it does not carry. */
- (id)copyWithZone:(nullable NSZone *)zone;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLLECTIONVIEWITEM_H */
