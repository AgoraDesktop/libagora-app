/*
 * NSArrayController_internal.h — the two seams an `NSArrayController` SUBCLASS needs, and no caller does.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A SUBCLASS WHOSE CONTENT IS NOT AN ARRAY HAS TO SAY SO AT ONE DOOR, NOT EIGHT.** `NSDictionaryController` arranges
 * key/value PAIRS over a dictionary content: the arrangement's INPUT is no longer the content object, and the criteria
 * (its included/excluded key sets and the localized names) are its own. This header declares exactly those two facts —
 * the input door and the criteria announcement pair — so the subclass extends the base class's arrangement rather than
 * reimplementing `-arrangedObjects`, the settle step and the selection policy beside it. **The criteria pair, not
 * `-rearrangeObjects`, is what the subclass needs:** the announcement has to bracket the field it stores, and
 * `-rearrangeObjects` would announce an arrangement it had already rebuilt.
 *
 * **NOTHING HERE IS APPLE'S API**, and the names are prefixed `fn_` for the reason the tree prefixes its own private
 * doors. The header is not imported by any public header.
 */
#ifndef AGORA_APPKIT_NSARRAYCONTROLLER_INTERNAL_H
#define AGORA_APPKIT_NSARRAYCONTROLLER_INTERNAL_H

#import <AppKit/NSArrayController.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSArrayController (AGArrangementSeam)

/* THE OBJECTS THE ARRANGEMENT IS BUILT FROM: the content's objects, for an array or a set content. A subclass whose
 * content is not a collection answers its own arrangement's input here. It is asked on every rebuild, so it must be
 * cheap and it must not mutate anything. */
- (NSArray *)fn_contentObjects;

/* THE CRITERIA ANNOUNCEMENT PAIR: call the `will` half before storing the field that changes the arrangement and the
 * `did` half after. It captures the old selection (for `preservesSelection`), drops the arrangement cache, and
 * announces the criteria keys — the same pair the base class's own sort and filter setters use. */
- (void)fn_willChangeCriteriaKeys;
- (void)fn_didChangeCriteriaKeys;

/* **THE CONTENT KIND IS A QUESTION, NOT AN `isKindOfClass:` IN THE SETTER.** A subclass whose content is not a
 * collection (a dictionary controller) has to be able to say so, and the setter has to refuse a wrong kind BEFORE it
 * stores it — a content change announces the arrangement, so a stored-then-refused content would leave the controller
 * unable to arrange anything again. `-fn_contentRule` is the phrase the refusal names. */
- (BOOL)fn_acceptsContent:(nullable id)content;
- (NSString *)fn_contentRule;

@end

NS_ASSUME_NONNULL_END

#endif /* AGORA_APPKIT_NSARRAYCONTROLLER_INTERNAL_H */
