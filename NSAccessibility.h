/*
 * NSAccessibility.h — the tree utilities an accessibility client asks of an element.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE FUNCTIONS ARE HERE AND THE PROTOCOLS ARE NOT, WHICH IS THE PLAN'S ORDER RATHER THAN AN OMISSION.** The 10.11
 * plan stages accessibility as "a tree, then a bridge": the tree utilities are answerable over this tier's view
 * hierarchy today, while the twenty `NSAccessibility*` protocols and the AT-SPI bridge are their own slice. Declaring
 * only what is implemented keeps the API census honest instead of moving twenty protocol rows to "present" as empty
 * shells.
 *
 * **THE ELEMENT DOORS ASK THE ELEMENT AND DO NOT ASSUME ITS CLASS.** An accessibility element in Cocoa is any object
 * answering the informal selectors — `-accessibilityRole`, `-accessibilitySubrole`, `-accessibilityIsIgnored`,
 * `-accessibilityChildren`, `-accessibilityParent` — and this tier's views are objects that may answer them. So
 * `NSAccessibilityUnignoredAncestor` walks whatever answers `-accessibilityParent` rather than walking `-superview`,
 * which would make it wrong for any element that is not a view.
 *
 * ONE DOOR REFUSES BY NAME: `NSAccessibilityPostNotification` needs a runtime to notify, and the bridge that would be
 * it is the separate deliverable the plan names.
 */

#ifndef APPKIT_NSACCESSIBILITY_H
#define APPKIT_NSACCESSIBILITY_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;
@class NSArray;

/* THE ROLE AND ACTION VOCABULARIES, AS WORDS RATHER THAN CONSTANTS. Apple's 10.6 header spells the roles as plain
 * strings (`@"AXButton"`), not as an enum, so these take and answer strings and a caller's own role is not rejected for
 * being one Apple did not list. */

/* The human-readable description of a role, and of a role with a subrole. Answers nil for a role in neither table. */
NSString * _Nullable NSAccessibilityRoleDescription(NSString *role, NSString * _Nullable subrole);
/* The same, asked of an element — its own `-accessibilityRole` and `-accessibilitySubrole`. */
NSString * _Nullable NSAccessibilityRoleDescriptionForUIElement(id element);
/* The human-readable description of an action, or the action itself when it is one this table does not name. */
NSString * _Nullable NSAccessibilityActionDescription(NSString *action);

/* THE UNIGNORED TREE. An "ignored" element is one whose attributes are not exposed; the era's convention is to walk
 * past them so a client sees the contents rather than the wrapper. */
id NSAccessibilityUnignoredAncestor(id element);
id _Nullable NSAccessibilityUnignoredDescendant(id element);
NSArray *NSAccessibilityUnignoredChildren(NSArray *originalChildren);
NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id originalChild);

/* THE REFUSAL. Announcing a change needs a runtime to announce it to. */
void NSAccessibilityPostNotification(id element, NSString *notification);
/* And the era's argument check, which IS answerable: it raises for a bad attribute. */
void NSAccessibilityRaiseBadArgumentException(id element, NSString *attribute, id value);

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSACCESSIBILITY_H */
