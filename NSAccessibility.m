/*
 * NSAccessibility.m — the tree utilities, over whatever answers the informal protocol.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE ELEMENT IS ASKED RATHER THAN INSPECTED.** Cocoa's accessibility element is a duck type: any object answering
 * `-accessibilityRole`, `-accessibilityParent`, `-accessibilityIsIgnored` and `-accessibilityChildren` is one. So this
 * file declares the informal protocol privately, guards every send with `-respondsToSelector:`, and never assumes an
 * element is an `NSView` — which matters because the first elements a client asks about here WILL be views, and
 * assuming that would make the utilities wrong the moment the protocols land.
 *
 * **AN OBJECT THAT ANSWERS NOTHING IS TREATED AS A VISIBLE LEAF, NOT AS AN ERROR.** `-accessibilityIsIgnored` absent
 * means "not ignored" and `-accessibilityParent` absent means "no parent", which is the era's default for a class that
 * has not opted in. That keeps the walk terminating and the answer useful before the protocols exist.
 *
 * THE ROLE AND ACTION TABLES ARE THIS TIER'S OWN WORDS FOR APPLE'S ROLE NAMES. They are small, they are stated here
 * rather than inferred, and an unknown name answers nil (roles) or itself (actions) instead of a plausible guess.
 */
#import <AppKit/NSAccessibility.h>
#import <AppKit/AppKitRefusal.h>
#import <Foundation/Foundation.h>

/* THE INFORMAL PROTOCOL, DECLARED SO THE SENDS ARE TYPED RATHER THAN ASSumed. */
@protocol AGAccessibilityElementInformal <NSObject>
@optional
- (BOOL)accessibilityIsIgnored;
- (id)accessibilityParent;
- (NSArray *)accessibilityChildren;
- (NSString *)accessibilityRole;
- (NSString *)accessibilitySubrole;
@end

static BOOL fn_ax_ignored(id element)
{
	if (element == nil) {
		return YES;
	}
	if ([element respondsToSelector:@selector(accessibilityIsIgnored)]) {
		return [(id <AGAccessibilityElementInformal>)element accessibilityIsIgnored] ? YES : NO;
	}
	return NO;
}

static id fn_ax_parent(id element)
{
	if (element != nil && [element respondsToSelector:@selector(accessibilityParent)]) {
		return [(id <AGAccessibilityElementInformal>)element accessibilityParent];
	}
	return nil;
}

static NSArray *fn_ax_children(id element)
{
	if (element != nil && [element respondsToSelector:@selector(accessibilityChildren)]) {
		return [(id <AGAccessibilityElementInformal>)element accessibilityChildren];
	}
	return nil;
}

static NSString *fn_ax_string(id element, SEL selector)
{
	return (element != nil && [element respondsToSelector:selector])
		? (NSString *)[element performSelector:selector] : nil;
}

typedef struct {
	const char *role;
	const char *word;
} AGRoleWord;

static const AGRoleWord s_roles[] = {
	{ "AXApplication", "application" },	{ "AXButton", "button" },
	{ "AXCheckBox", "check box" },		{ "AXCloseButton", "close button" },
	{ "AXComboBox", "combo box" },		{ "AXDisclosureTriangle", "disclosure triangle" },
	{ "AXDrawer", "drawer" },		{ "AXGroup", "group" },
	{ "AXHeading", "heading" },		{ "AXHelpTag", "help tag" },
	{ "AXImage", "image" },			{ "AXLink", "link" },
	{ "AXList", "list" },			{ "AXMenu", "menu" },
	{ "AXMenuItem", "menu item" },		{ "AXOutline", "outline" },
	{ "AXPopUpButton", "pop up button" },	{ "AXProgressIndicator", "progress indicator" },
	{ "AXRadioButton", "radio button" },	{ "AXRow", "row" },
	{ "AXScrollArea", "scroll area" },	{ "AXSearchField", "search field" },
	{ "AXSheet", "sheet" },			{ "AXSlider", "slider" },
	{ "AXSplitGroup", "split group" },	{ "AXStaticText", "text" },
	{ "AXTabGroup", "tab group" },		{ "AXTable", "table" },
	{ "AXTextField", "text field" },	{ "AXToolbar", "toolbar" },
	{ "AXValueIndicator", "value indicator" }, { "AXWindow", "window" }
};

static const AGRoleWord s_subroles[] = {
	{ "AXCloseButton", "close button" },	{ "AXMinimizeButton", "minimize button" },
	{ "AXSearchField", "search field" },	{ "AXSortButton", "sort button" },
	{ "AXToolbarButton", "toolbar button" },{ "AXUnknown", "unknown" },
	{ "AXZoomButton", "zoom button" }
};

static const AGRoleWord s_actions[] = {
	{ "AXCancel", "cancel" },	{ "AXConfirm", "confirm" },
	{ "AXDecrement", "decrement" },	{ "AXIncrement", "increment" },
	{ "AXPress", "press" },		{ "AXShowMenu", "show menu" }
};

static NSString *fn_ax_lookup(const AGRoleWord *table, size_t count, NSString *name)
{
	size_t i;

	if (name == nil) {
		return nil;
	}
	for (i = 0; i < count; i++) {
		if ([name isEqualToString:[NSString stringWithUTF8String:table[i].role]]) {
			return [NSString stringWithUTF8String:table[i].word];
		}
	}
	return nil;
}

NSString *NSAccessibilityRoleDescription(NSString *role, NSString *subrole)
{
	NSString *word;

	if ((word = fn_ax_lookup(s_subroles, sizeof(s_subroles) / sizeof(s_subroles[0]), subrole)) != nil) {
		return word;
	}
	return fn_ax_lookup(s_roles, sizeof(s_roles) / sizeof(s_roles[0]), role);
}

NSString *NSAccessibilityRoleDescriptionForUIElement(id element)
{
	NSString *role = fn_ax_string(element, @selector(accessibilityRole));
	NSString *subrole = fn_ax_string(element, @selector(accessibilitySubrole));

	return NSAccessibilityRoleDescription(role, subrole);
}

NSString *NSAccessibilityActionDescription(NSString *action)
{
	NSString *word = fn_ax_lookup(s_actions, sizeof(s_actions) / sizeof(s_actions[0]), action);

	/* AN UNKNOWN ACTION ANSWERS ITSELF rather than nil, because the era's callers put the answer straight into a menu
	 * and a custom action's own name is a better label than an empty one. */
	return word != nil ? word : action;
}

id NSAccessibilityUnignoredAncestor(id element)
{
	id current = element;

	while (current != nil && fn_ax_ignored(current)) {
		id parent = fn_ax_parent(current);

		if (parent == nil) {
			return current;
		}
		current = parent;
	}
	return current;
}

id NSAccessibilityUnignoredDescendant(id element)
{
	NSArray *children;
	NSUInteger i, count;

	if (!fn_ax_ignored(element)) {
		return element;
	}
	children = fn_ax_children(element);
	count = [children count];
	for (i = 0; i < count; i++) {
		id found = NSAccessibilityUnignoredDescendant([children objectAtIndex:i]);

		if (found != nil) {
			return found;
		}
	}
	return nil;
}

NSArray *NSAccessibilityUnignoredChildren(NSArray *originalChildren)
{
	NSMutableArray *out = [NSMutableArray array];
	NSUInteger i, count = [originalChildren count];

	for (i = 0; i < count; i++) {
		id child = [originalChildren objectAtIndex:i];

		if (!fn_ax_ignored(child)) {
			[out addObject:child];
		} else {
			[out addObjectsFromArray:NSAccessibilityUnignoredChildren(fn_ax_children(child))];
		}
	}
	return out;
}

/* **THE ONLY-CHILD DOOR UNWRAPS A WRAPPER**: when an element has exactly one unignored child and that child is itself
 * an ignorable container, the useful answer is the grandchild. More than one child means the caller gets nil, which is
 * Apple's answer for "not a single child". */
NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id originalChild)
{
	NSArray *children = fn_ax_children(originalChild);

	if ([children count] != 1) {
		return nil;
	}
	if (fn_ax_ignored(originalChild)) {
		return NSAccessibilityUnignoredChildrenForOnlyChild([children objectAtIndex:0]);
	}
	return [NSArray arrayWithObject:[children objectAtIndex:0]];
}

void NSAccessibilityPostNotification(id element, NSString *notification)
{
	(void)element; (void)notification;
	fn_refuse_window("NSAccessibilityPostNotification", "an accessibility runtime to notify (the AT-SPI bridge is a "
			 "separate deliverable in the plan)");
}

void NSAccessibilityRaiseBadArgumentException(id element, NSString *attribute, id value)
{
	[NSException raise:NSInvalidArgumentException
		    format:@"invalid accessibility argument: attribute `%@` on %@ cannot take %@",
			   attribute, element, value];
}
