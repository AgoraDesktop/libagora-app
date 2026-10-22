/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSToolbarItemGroup.h — several toolbar items that move as one.
 *
 * **A GROUP IS STORAGE WITH A UNIT'S BEHAVIOUR.** It is a toolbar item, so inserting, removing or reordering the group
 * moves the whole set; its subitems are displayed ADJACENT to one another, with no gap inserted between them. The
 * 10.6 header gives the class one property — `subitems` — and this tier implements exactly that surface. A group may
 * not contain another group, which the setter refuses by name.
 *
 * A group with a custom `view` is laid out as ONE item wearing that view; its subitems are then storage rather than
 * separate faces. A group without a view contributes its subitems in order, and the toolbar's own layout/ink/pointer
 * code treats each of them as an ordinary item while `-visibleItems` still answers the GROUP, because the group is
 * the unit that is on screen.
 *
 * **THE PARENT'S OWN LABEL/TARGET/ACTION DO NOT OVERRIDE A STANDARD SUBITEM'S.** Apple's sentence says the parent's
 * label and view apply to the entire item; this tier applies the view (a group with one is a single face) and leaves
 * the standard subitems' labels and actions to the subitems, because those are the things a person clicks. A group
 * whose members should share a label or action sets them on the members. The header states the gap rather than
 * letting a caller discover it in a toolbar.
 *
 * Written from `NSToolbarItemGroup.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSTOOLBARITEMGROUP_H
#define APPKIT_NSTOOLBARITEMGROUP_H

#import <AppKit/NSToolbarItem.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSToolbarItemGroup : NSToolbarItem
{
	NSArray *_subitems;	/* RETAINED: the group owns its subitems */
}

/* THE SUBITEMS. An empty array is the default. A member that is not an NSToolbarItem, or that is another
 * NSToolbarItemGroup, is REFUSED with NSInvalidArgumentException. */
- (void)setSubitems:(NSArray *)subitems;
- (NSArray *)subitems;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTOOLBARITEMGROUP_H */
