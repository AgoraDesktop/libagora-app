/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSearchField.h — the field a person types a query into: a text field whose cell carries a magnifier and a clear
 * button, and whose recents are remembered.
 *
 * **THE CONTROL IS A TEXT FIELD, AND ALMOST EVERYTHING IS THE CELL'S.** Apple's `NSSearchField` adds two forwards to
 * the recents and one initialiser; the ornaments, the text inset, the template menu and the timer that decides when a
 * partial string is sent are all `NSSearchFieldCell`'s. That is the same split `NSTextField` and `NSTextFieldCell`
 * already have in this tier, and it is why this class is short.
 *
 * **THE ONE THING THE CONTROL ADDS IS A PRESS THAT CAN MISS THE TEXT.** A text field's press opens an edit session
 * over its whole bounds; a search field's press first asks the cell whether the point landed on the magnifier or the
 * clear button. If it did, the ornament acts and no editor opens; if it did not, the base class's press runs and the
 * session begins. Without that the clear button would put a caret in front of itself.
 *
 * **AND A SEARCH FIELD IS EDITABLE, SELECTABLE, BORDERED AND BEZELED FROM BIRTH**, with the rounded face and the
 * placeholder "Search" — the same four flags a text field has, plus the two the search field always wants.
 *
 * Written from `NSSearchField.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSSEARCHFIELD_H
#define APPKIT_NSSEARCHFIELD_H

#import <AppKit/NSTextField.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSSearchField : NSTextField <NSSecureCoding>

/* **THE RECENTS ARE THE CELL'S LIST, FORWARDED.** The setter replaces the list (an empty or nil array clears it), and
 * the getter answers a copy, which is Apple's contract and the one that keeps a caller from mutating the field's
 * storage behind its back. */
- (void)setRecentSearches:(nullable NSArray *)searches;
- (NSArray *)recentSearches;

/* **AND THE AUTOSAVE NAME IS BOTH A KEY AND A LOAD.** Setting it stores the name and, when that key holds searches,
 * adopts them; every later change to the list writes back under the same name. Nil means "do not save". */
- (void)setRecentsAutosaveName:(nullable NSString *)string;
- (nullable NSString *)recentsAutosaveName;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSEARCHFIELD_H */
