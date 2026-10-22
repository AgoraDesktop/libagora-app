/*
 * NSToolbarItem.m — one thing in a toolbar, and the four decisions it makes.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The storage is the header's; what lives here is the fallbacks, the forwarding to a custom view, and `-validate`.
 * The validation order is Apple's and it is the whole point of the class: a validator that answers
 * `-validateToolbarItem:` decides alone, one that answers `-validateUserInterfaceItem:` is the generic AppKit answer,
 * and a target that answers neither is enabled exactly when it answers the action. `NSMenu.m` implements the same
 * three-step rule for menu items; these are two callers of one convention, not two conventions.
 */
#import "NSToolbarItem.h"
#import "NSToolbar.h"
#import "NSToolbar_internal.h"

#import "NSApplication.h"
#import "NSImage.h"
#import "NSMenuItem.h"
#import "NSView.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

/* THE STANDARD IDENTIFIERS ARE THE TOOLBAR'S, but their values are an item-level fact: a delegate returns them in
 * arrays and `-itemIdentifier` compares them, so they live beside the item that knows how to be one. The header
 * declares them; this file defines them once. */
NSString *NSToolbarSeparatorItemIdentifier = @"NSToolbarSeparatorItem";
NSString *NSToolbarSpaceItemIdentifier = @"NSToolbarSpaceItem";
NSString *NSToolbarFlexibleSpaceItemIdentifier = @"NSToolbarFlexibleSpaceItem";
NSString *NSToolbarShowColorsItemIdentifier = @"NSToolbarShowColorsItem";
NSString *NSToolbarShowFontsItemIdentifier = @"NSToolbarShowFontsItem";
NSString *NSToolbarCustomizeToolbarItemIdentifier = @"NSToolbarCustomizeToolbarItem";
NSString *NSToolbarPrintItemIdentifier = @"NSToolbarPrintItem";

@implementation NSToolbarItem

- (instancetype)initWithItemIdentifier:(NSString *)itemIdentifier
{
	self = [super init];
	if (self != nil) {
		/* THE IDENTIFIER IS COPIED AND IS NEVER NIL. An item with no identifier cannot be found by the delegate,
		 * selected, removed or autosaved, so an empty string is the honest answer rather than a nil that every
		 * caller would have to test. */
		_itemIdentifier = [(itemIdentifier != nil ? itemIdentifier : @"") copy];
		_label = nil;
		_paletteLabel = nil;
		_toolTip = nil;
		_image = nil;
		_menuFormRepresentation = nil;
		_view = nil;
		_target = nil;
		_action = NULL;
		_tag = 0;
		/* ITEMS START ENABLED, which is Apple's default and the one that lets a program with no validation show a
		 * working toolbar. A target that cannot answer its action is disabled by `-validate`, not by construction. */
		_enabled = YES;
		_autovalidates = YES;
		_visibilityPriority = NSToolbarItemVisibilityPriorityStandard;
		_minSize = NSMakeSize(0.0, 0.0);
		_maxSize = NSMakeSize(0.0, 0.0);
	}
	return self;
}

- (void)dealloc
{
	[_itemIdentifier release];
	[_label release];
	[_paletteLabel release];
	[_toolTip release];
	[_image release];
	[_menuFormRepresentation release];
	[_view release];
	[super dealloc];
}

- (NSString *)itemIdentifier
{
	return _itemIdentifier;
}

- (NSToolbar *)toolbar
{
	return _toolbar;
}

/* ---- THE LABELS AND THE TOOL TIP ---------------------------------------------------------------- */

- (void)setLabel:(NSString *)label
{
	NSString *copy = [label copy];

	[_label release];
	_label = copy;
	[self cg_changed];
}

- (NSString *)label
{
	return _label;
}

- (void)setPaletteLabel:(NSString *)paletteLabel
{
	NSString *copy = [paletteLabel copy];

	[_paletteLabel release];
	_paletteLabel = copy;
	[self cg_changed];
}

- (NSString *)paletteLabel
{
	/* **THE FALLBACK IS APPLE'S AND IT IS THE ONLY USEFUL ONE.** Every item must have a palette label, and the
	 * ordinary case is that the label a person sees in the toolbar is also the one they look for in the palette. */
	return (_paletteLabel != nil) ? _paletteLabel : _label;
}

- (void)setToolTip:(NSString *)toolTip
{
	NSString *copy = [toolTip copy];

	[_toolTip release];
	_toolTip = copy;
}

- (NSString *)toolTip
{
	/* A CUSTOM VIEW MAY HAVE ITS OWN TOOL TIP, and Apple's contract is that the item asks it first. The view has a
	 * real `-toolTip` in `NSView`; a view without one falls back to the item's string. */
	if (_view != nil && [_view respondsToSelector:@selector(toolTip)]) {
		NSString *viewTip = [(id)_view toolTip];

		if (viewTip != nil) {
			return viewTip;
		}
	}
	return _toolTip;
}

/* ---- THE MENU FORM ------------------------------------------------------------------------------ */

- (void)setMenuFormRepresentation:(NSMenuItem *)menuItem
{
	[menuItem retain];
	[_menuFormRepresentation release];
	_menuFormRepresentation = menuItem;
}

- (NSMenuItem *)menuFormRepresentation
{
	/* **MADE ON FIRST ASK, AS A SINGLETON CARRYING THE ITEM'S OWN STATE.** Apple documents the default as a menu item
	 * with the label, target and action; making it lazily means a caller that supplies one never pays for this one,
	 * and a caller that does not still gets a representation the moment a menu asks. */
	if (_menuFormRepresentation == nil) {
		NSString *title = (_label != nil) ? _label : @"";

		_menuFormRepresentation = [[NSMenuItem alloc] initWithTitle:title action:_action keyEquivalent:@""];
		[_menuFormRepresentation setTarget:_target];
		[_menuFormRepresentation setTag:_tag];
		if (_image != nil) {
			[_menuFormRepresentation setImage:_image];
		}
	}
	return _menuFormRepresentation;
}

/* ---- THE ACTION, THE TAG AND THE ENABLED FLAG --------------------------------------------------- */

- (void)setTag:(NSInteger)tag
{
	_tag = tag;
	if (_view != nil && [_view respondsToSelector:@selector(setTag:)]) {
		[(id)_view setTag:tag];
	}
}

- (NSInteger)tag
{
	return _tag;
}

- (void)setTarget:(id)target
{
	_target = target;	/* NOT RETAINED: the target/action convention, as for NSMenuItem */
	if (_view != nil && [_view respondsToSelector:@selector(setTarget:)]) {
		[(id)_view setTarget:target];
	}
}

- (id)target
{
	return _target;
}

- (void)setAction:(SEL)action
{
	_action = action;
	if (_view != nil && [_view respondsToSelector:@selector(setAction:)]) {
		[(id)_view setAction:action];
	}
}

- (SEL)action
{
	return _action;
}

- (void)setEnabled:(BOOL)enabled
{
	_enabled = enabled ? YES : NO;
	if (_view != nil && [_view respondsToSelector:@selector(setEnabled:)]) {
		[(id)_view setEnabled:_enabled];
	}
	[self cg_changed];
}

- (BOOL)isEnabled
{
	return _enabled;
}

/* ---- THE PICTURE AND THE CUSTOM VIEW ------------------------------------------------------------ */

- (void)setImage:(NSImage *)image
{
	[image retain];
	[_image release];
	_image = image;
	if (_view != nil && [_view respondsToSelector:@selector(setImage:)]) {
		[(id)_view setImage:image];
	}
	[self cg_changed];
}

- (NSImage *)image
{
	return _image;
}

- (void)setView:(NSView *)view
{
	if (view == _view) {
		return;
	}
	[view retain];
	[_view release];
	_view = view;
	/* **A VIEW'S FRAME IS THE ITEM'S MINIMUM, WHEN THE CALLER DID NOT SAY OTHERWISE.** Apple's guidance is that a
	 * custom item sets a minimum and a maximum; a view with a size and an item with none can only mean the view's
	 * own size, so the layout reads the frame as the fallback. */
	[self cg_changed];
}

- (NSView *)view
{
	return _view;
}

/* ---- THE SIZE RANGE ----------------------------------------------------------------------------- */

- (void)setMinSize:(NSSize)size
{
	_minSize = size;
	[self cg_changed];
}

- (NSSize)minSize
{
	return _minSize;
}

- (void)setMaxSize:(NSSize)size
{
	_maxSize = size;
	[self cg_changed];
}

- (NSSize)maxSize
{
	return _maxSize;
}

/* ---- THE PRIORITY AND THE TWO FLAGS ------------------------------------------------------------- */

- (void)setVisibilityPriority:(NSInteger)visibilityPriority
{
	_visibilityPriority = visibilityPriority;
	[self cg_changed];
}

- (NSInteger)visibilityPriority
{
	return _visibilityPriority;
}

- (void)setAutovalidates:(BOOL)flag
{
	_autovalidates = flag ? YES : NO;
}

- (BOOL)autovalidates
{
	return _autovalidates;
}

- (BOOL)allowsDuplicatesInToolbar
{
	/* THE SPACERS ARE THE ONE DUPLICATE THAT MAKES SENSE, and Apple's own prose says a separator always drags in as
	 * a duplicate. This tier has no drag session, but the answer is read by callers that do their own arrangement. */
	if ([_itemIdentifier isEqualToString:NSToolbarSeparatorItemIdentifier] ||
	    [_itemIdentifier isEqualToString:NSToolbarSpaceItemIdentifier] ||
	    [_itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
		return YES;
	}
	return NO;
}

/* ---- VALIDATION --------------------------------------------------------------------------------- */

- (void)validate
{
	id target;
	SEL action = _action;

	/* A CUSTOM VIEW OWNS ITS OWN ENABLED STATE, which is Apple's rule and not an omission: a control has its own
	 * target and its own idea of whether it can act, and a toolbar guessing for it would fight the control. */
	if (_view != nil) {
		return;
	}
	if (action == NULL) {
		return;
	}
	target = _target;
	if (target == nil) {
		/* **A NIL TARGET MEANS THE RESPONDER CHAIN, WHICH THE APPLICATION WALKS.** The same resolution `NSMenu`
		 * performs, and for the same reason: an item that did not name a target is validated against WHOEVER WOULD
		 * RECEIVE ITS ACTION, so it enables and disables as the first responder changes. */
		target = [[NSApplication sharedApplication] targetForAction:action];
	}
	if ([target respondsToSelector:@selector(validateToolbarItem:)]) {
		[self setEnabled:[(id)target validateToolbarItem:self]];
	} else if ([target respondsToSelector:@selector(validateUserInterfaceItem:)]) {
		[self setEnabled:[(id <NSUserInterfaceValidations>)target validateUserInterfaceItem:self]];
	} else {
		[self setEnabled:(target != nil && [target respondsToSelector:action])];
	}
}

/* ---- COPYING ------------------------------------------------------------------------------------ */

/* **`-copy` AND NOT `-copyWithZone:`, BECAUSE THIS TREE HAS NO ZONES** — `NSZone` is deliberately absent and
 * `NSCopying`'s only member is `-copy` (NSObject.h states the decision), so a Cocoa class spelling the zone door
 * would not conform. The copy is a NEW ITEM, not a retain: an item is mutable, and the palette Apple describes is
 * the reason a copy has to be independent. */
- (id)copy
{
	NSToolbarItem *copy = [[[self class] alloc] initWithItemIdentifier:_itemIdentifier];

	[copy setLabel:_label];
	[copy setPaletteLabel:_paletteLabel];
	[copy setToolTip:_toolTip];
	[copy setImage:_image];
	[copy setTarget:_target];
	[copy setAction:_action];
	[copy setTag:_tag];
	[copy setEnabled:_enabled];
	[copy setAutovalidates:_autovalidates];
	[copy setVisibilityPriority:_visibilityPriority];
	[copy setMinSize:_minSize];
	[copy setMaxSize:_maxSize];
	if (_menuFormRepresentation != nil) {
		[copy setMenuFormRepresentation:_menuFormRepresentation];
	}
	/* **THE VIEW IS NOT COPIED, AND THAT IS THE HONEST ANSWER.** A view has one superview, so copying the pointer
	 * would MOVE the original item's control rather than duplicate it; Apple's header instead requires a custom view
	 * to be archivable so the palette can make its own. This tier has no palette (see `NSToolbar.h`), and inventing
	 * an unarchiver here would be a second kind of object the item never claims to be. */
	return copy;
}

/* ---- THE TOOLBAR'S OWN SEAM --------------------------------------------------------------------- */

- (void)cg_setToolbar:(NSToolbar *)toolbar
{
	_toolbar = toolbar;	/* NOT RETAINED: see the header */
}

- (void)cg_changed
{
	[_toolbar cg_layoutChanged];
}

@end
