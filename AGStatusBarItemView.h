/*
 * AGStatusBarItemView.h — the view a status item makes for itself: its face, and its press.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A STATUS ITEM IS A WINDOW, AND SOMETHING IN IT HAS TO TAKE THE PRESS.** Apple's is a private button
 * (`NSStatusBarButton`); this tier's is this view, and it is the reader for four doors that were otherwise stored values:
 * `-isEnabled` (a disabled item draws dimmed and sends nothing), `-sendActionOn:` (which event sends the action),
 * the tooltip (`NSView`'s own, since a tooltip is a view's property here) and the action/target/doubleAction pair — plus
 * `-highlightMode:`, which decides whether the pressed state is DRAWN.
 *
 * IT IS PUBLIC IN THIS TREE'S SENSE — a class with a header rather than a class hidden in one `.m` — for the same reason
 * `AGComboListView` is: a probe can then build one and drive a press, which is the only way the send path is assertable
 * without a pointer. Nothing in the API proper names it; a caller with its own view hands that to `-setView:` instead and
 * this one steps aside.
 */
#ifndef AG_STATUS_BAR_ITEM_VIEW_H
#define AG_STATUS_BAR_ITEM_VIEW_H

#import <AppKit/NSView.h>

@class NSStatusItem;

NS_ASSUME_NONNULL_BEGIN

@interface AGStatusBarItemView : NSView
{
	NSStatusItem *_item;	/* NOT RETAINED: the item owns this view */
	BOOL _pressed;
}

/* THE ITEM IS BORROWED, and it is told to this view rather than the other way round so that a caller can make the view
 * FIRST and hand it to `-setView:` afterwards. An itemless view draws nothing and sends nothing. */
- (instancetype)initWithStatusItem:(nullable NSStatusItem *)item frame:(NSRect)frame;
- (void)cg_setStatusItem:(nullable NSStatusItem *)item;

@end

NS_ASSUME_NONNULL_END

#endif /* AG_STATUS_BAR_ITEM_VIEW_H */
