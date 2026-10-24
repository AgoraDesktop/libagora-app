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

#import <AppKit/NSView.h>

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

/* **THE LOADED VIEW WITHOUT THE LOADING.** `-view` is the door that loads a nib or raises when there is none; a collection
 * view deciding whether an item has a tile must not trip that. `_view` is `NSViewController`'s protected ivar, so the
 * subclass can answer it directly. */
- (NSView *)cg_viewIfLoaded
{
	return _view;
}

/* **THE COPY A PROTOTYPE IS FOR: THE CLASS, THE VIEW'S CLASS AND FRAME, THE OBJECT AND THE SELECTED BIT.** Apple's own
 * item copies through an archive; this tier has no controller archive, so the copy is written out rather than implied —
 * and the header names what a subclass with its own ivars must do to keep them. */
- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	NSCollectionViewItem *copy = [[[self class] allocWithZone:zone] initWithNibName:nil bundle:nil];

	if (_view != nil) {
		NSView *viewCopy = [[[_view class] alloc] initWithFrame:[_view frame]];

		[copy setView:viewCopy];
		[viewCopy release];
	}
	[copy setRepresentedObject:[self representedObject]];
	[copy setSelected:[self isSelected]];
	return copy;
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
