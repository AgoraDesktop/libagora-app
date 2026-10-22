/*
 * NSTextList_internal.h — the one thing a paragraph style must tell a list: which list encloses it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * NOT INSTALLED, and this tier's own door. **`NSTextListPrependEnclosingMarker` NEEDS A FACT THAT NO PUBLIC API CARRIES**:
 * a list that prepends its enclosing marker has to know which list encloses it, and 10.6 gives no setter for that —
 * Apple keeps it in the private `_listSecondary` ivar its own header declares, and fills it when a paragraph style is
 * handed an ARRAY of lists, because the array IS the nesting ("nested from outermost to innermost").
 *
 * **SO THE LINK IS THE PARAGRAPH STYLE'S, AND THIS HEADER IS HOW IT IS MADE.** `libagora-app/NSParagraphStyle.m` links
 * the stack it is given, level by level, so a list only ever knows the one immediately outside it; `-markerForItemNumber:`
 * then walks outwards as far as the options ask. Nothing else in the tree calls these two doors.
 */
#ifndef APPKIT_NSTEXTLIST_INTERNAL_H
#define APPKIT_NSTEXTLIST_INTERNAL_H

#import <AppKit/NSTextList.h>

@interface NSTextList (NSTextListInternal)

/* The list immediately OUTSIDE this one in a paragraph's stack, or nil at the outermost level. NOT RETAINED BY THE
 * CALLER: the reciever retains it, and the paragraph style owns the whole stack. */
- (void)_setEnclosingList:(NSTextList *)enclosing;
- (NSTextList *)_enclosingList;

@end

#endif /* APPKIT_NSTEXTLIST_INTERNAL_H */
