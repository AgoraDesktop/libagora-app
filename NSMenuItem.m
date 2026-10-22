/*
 * NSMenuItem — one row of a menu, and almost entirely storage.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * WHAT THE CLASS DECIDES RATHER THAN STORES IS FOUR THINGS, and each is here because it is the reason the row
 * is not just a field:
 *
 *   THE MNEMONIC IS DERIVED. `-setTitleWithMnemonic:` parses Apple's `&` spelling out of a string, records the
 *   INDEX it landed at, and stores the title without it — so `-mnemonic` reads the character out of the ONE
 *   title rather than keeping a second copy that a later `-setTitle:` would leave stale. That staleness is the
 *   whole argument: a stored mnemonic would have to be cleared by every door that changes a title, and one
 *   missed door is a menu advertising a key that is not there.
 *   THE TWO TREE QUESTIONS. `-hasSubmenu` is whether a submenu is attached, and `-hiddenOrHasHiddenAncestor`
 *   WALKS UP: an item inside a hidden item's submenu is hidden too, which is what a menu builder needs and
 *   what a field could not answer.
 *   AND `-userKeyEquivalent` ANSWERS NIL, because a user key equivalent comes from a table of the user's own
 *   overrides and this tier has none. The SWITCH that would consult one is deliberately not shipped (the
 *   header says why): it would be a flag with no reader.
 *
 * THE MRC OWNERSHIP IS THE HEADER'S AND IT IS NOT UNIFORM: the strings are COPIED, the submenu, the images,
 * the view and the represented object are RETAINED, and the target, the owning menu and the parent item are
 * NOT — a menu tree points up without owning, or an item whose target is its controller (which owns the item)
 * would be a cycle. That is the whole of `-dealloc`.
 */
#import <AppKit/NSMenuItem.h>

#include <stdio.h>

@implementation NSMenuItem

/* ============================================================================================
 * ARCHIVING: AN ITEM IS ITS TITLE, ITS KEY EQUIVALENT AND WHAT IT DOES.
 * ============================================================================================ */

/* **THE ACTION IS ARCHIVED BY NAME AND THE TARGET IS NOT ARCHIVED AT ALL.** A `SEL` is not an object; a target is a
 * CONNECTION (see `NSNib.h`), because the object an item sends its action to is either the file's owner or another
 * object in the same archive. `_menu` and `_parentItem` are BACK-LINKS the containers rebuild, so they are absent for the
 * same reason a view's superview is. `_highlighted` is tracking state and is absent for the same reason a cell's is. */
static NSString * const AGCoderItemTitleKey = @"title";
static NSString * const AGCoderItemAttributedTitleKey = @"attributedTitle";
static NSString * const AGCoderItemKeyEquivalentKey = @"keyEquivalent";
static NSString * const AGCoderItemKeyModifiersKey = @"keyEquivalentModifierMask";
static NSString * const AGCoderItemToolTipKey = @"toolTip";
static NSString * const AGCoderItemSubmenuKey = @"submenu";
static NSString * const AGCoderItemRepresentedKey = @"representedObject";
static NSString * const AGCoderItemViewKey = @"view";
static NSString * const AGCoderItemImageKey = @"image";
static NSString * const AGCoderItemOnImageKey = @"onStateImage";
static NSString * const AGCoderItemOffImageKey = @"offStateImage";
static NSString * const AGCoderItemMixedImageKey = @"mixedStateImage";
static NSString * const AGCoderItemActionKey = @"action";
static NSString * const AGCoderItemTagKey = @"tag";
static NSString * const AGCoderItemStateKey = @"state";
static NSString * const AGCoderItemIndentationKey = @"indentationLevel";
static NSString * const AGCoderItemMnemonicKey = @"mnemonicLocation";
static NSString * const AGCoderItemEnabledKey = @"enabled";
static NSString * const AGCoderItemAlternateKey = @"alternate";
static NSString * const AGCoderItemHiddenKey = @"hidden";
static NSString * const AGCoderItemSeparatorKey = @"separator";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:_title forKey:AGCoderItemTitleKey];
	[aCoder encodeObject:_attributedTitle forKey:AGCoderItemAttributedTitleKey];
	[aCoder encodeObject:_keyEquivalent forKey:AGCoderItemKeyEquivalentKey];
	[aCoder encodeInteger:(NSInteger)_keyEquivalentModifierMask forKey:AGCoderItemKeyModifiersKey];
	[aCoder encodeObject:_toolTip forKey:AGCoderItemToolTipKey];
	[aCoder encodeObject:_submenu forKey:AGCoderItemSubmenuKey];
	[aCoder encodeObject:_representedObject forKey:AGCoderItemRepresentedKey];
	[aCoder encodeObject:_view forKey:AGCoderItemViewKey];
	[aCoder encodeObject:_image forKey:AGCoderItemImageKey];
	[aCoder encodeObject:_onStateImage forKey:AGCoderItemOnImageKey];
	[aCoder encodeObject:_offStateImage forKey:AGCoderItemOffImageKey];
	[aCoder encodeObject:_mixedStateImage forKey:AGCoderItemMixedImageKey];
	[aCoder encodeObject:(_action != NULL) ? NSStringFromSelector(_action) : nil forKey:AGCoderItemActionKey];
	[aCoder encodeInteger:_tag forKey:AGCoderItemTagKey];
	[aCoder encodeInteger:_state forKey:AGCoderItemStateKey];
	[aCoder encodeInteger:_indentationLevel forKey:AGCoderItemIndentationKey];
	[aCoder encodeInteger:(NSInteger)_mnemonicLocation forKey:AGCoderItemMnemonicKey];
	[aCoder encodeBool:_enabled forKey:AGCoderItemEnabledKey];
	[aCoder encodeBool:_alternate forKey:AGCoderItemAlternateKey];
	[aCoder encodeBool:_hidden forKey:AGCoderItemHiddenKey];
	[aCoder encodeBool:_separator forKey:AGCoderItemSeparatorKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	NSString *title = [aDecoder decodeObjectForKey:AGCoderItemTitleKey];
	NSString *equivalent = [aDecoder decodeObjectForKey:AGCoderItemKeyEquivalentKey];
	NSString *actionName = [aDecoder decodeObjectForKey:AGCoderItemActionKey];
	SEL action = NULL;

	if ([actionName isKindOfClass:[NSString class]]) {
		action = NSSelectorFromString(actionName);
	}
	self = [self initWithTitle:([title isKindOfClass:[NSString class]]) ? title : @""
			   action:action
		   keyEquivalent:([equivalent isKindOfClass:[NSString class]]) ? equivalent : @""];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderItemAttributedTitleKey]) {
		[self setAttributedTitle:[aDecoder decodeObjectForKey:AGCoderItemAttributedTitleKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemKeyModifiersKey]) {
		[self setKeyEquivalentModifierMask:
			(NSUInteger)[aDecoder decodeIntegerForKey:AGCoderItemKeyModifiersKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemToolTipKey]) {
		[self setToolTip:[aDecoder decodeObjectForKey:AGCoderItemToolTipKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemSubmenuKey]) {
		[self setSubmenu:[aDecoder decodeObjectForKey:AGCoderItemSubmenuKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemRepresentedKey]) {
		[self setRepresentedObject:[aDecoder decodeObjectForKey:AGCoderItemRepresentedKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemViewKey]) {
		[self setView:[aDecoder decodeObjectForKey:AGCoderItemViewKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemImageKey]) {
		[self setImage:[aDecoder decodeObjectForKey:AGCoderItemImageKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemOnImageKey]) {
		[self setOnStateImage:[aDecoder decodeObjectForKey:AGCoderItemOnImageKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemOffImageKey]) {
		[self setOffStateImage:[aDecoder decodeObjectForKey:AGCoderItemOffImageKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemMixedImageKey]) {
		[self setMixedStateImage:[aDecoder decodeObjectForKey:AGCoderItemMixedImageKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemTagKey]) {
		[self setTag:[aDecoder decodeIntegerForKey:AGCoderItemTagKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemStateKey]) {
		[self setState:[aDecoder decodeIntegerForKey:AGCoderItemStateKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemIndentationKey]) {
		[self setIndentationLevel:[aDecoder decodeIntegerForKey:AGCoderItemIndentationKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemMnemonicKey]) {
		[self setMnemonicLocation:(NSUInteger)[aDecoder decodeIntegerForKey:AGCoderItemMnemonicKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemEnabledKey]) {
		[self setEnabled:[aDecoder decodeBoolForKey:AGCoderItemEnabledKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemAlternateKey]) {
		[self setAlternate:[aDecoder decodeBoolForKey:AGCoderItemAlternateKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemHiddenKey]) {
		[self setHidden:[aDecoder decodeBoolForKey:AGCoderItemHiddenKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderItemSeparatorKey]) {
		_separator = [aDecoder decodeBoolForKey:AGCoderItemSeparatorKey];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* ---- THE CONSTRUCTORS -------------------------------------------------------------------------- */

- (instancetype)initWithTitle:(NSString *)string
		       action:(SEL)selector
		keyEquivalent:(NSString *)charCode
{
	if ((self = [super init]) != nil) {
		_title = [string copy];
		_action = selector;
		_keyEquivalent = [charCode copy];
		/* THE DEFAULTS THAT ARE NOT ZERO, AND EACH IS WHAT A MENU BUILDER EXPECTS: an item is enabled until
		 * something disables it, its state is off (the enum's zero), and its mnemonic location is "none". */
		_enabled = YES;
		_state = 0;
		_mnemonicLocation = NSNotFound;
	}
	return self;
}

+ (NSMenuItem *)separatorItem
{
	NSMenuItem *item = [[[self alloc] initWithTitle:@""
						 action:NULL
					  keyEquivalent:@""] autorelease];

	/* THE FLAG IS WHAT MAKES IT A SEPARATOR, and it is set here rather than by a subclass: Apple's own
	 * separator IS an NSMenuItem that answers YES to `-isSeparatorItem`. */
	item->_separator = YES;
	return item;
}

- (BOOL)isSeparatorItem
{
	return _separator;
}

- (void)dealloc
{
	[_title release];
	[_attributedTitle release];
	[_keyEquivalent release];
	[_toolTip release];
	[_submenu release];
	[_representedObject release];
	[_view release];
	[_image release];
	[_onStateImage release];
	[_offStateImage release];
	[_mixedStateImage release];
	[super dealloc];
}

/* ---- THE TITLE AND THE MNEMONIC ---------------------------------------------------------------- */

- (NSString *)title
{
	return _title;
}

- (void)setTitle:(NSString *)string
{
	/* A NEW TITLE CLEARS THE MNEMONIC, because the location it named was an index into the OLD string —
	 * keeping it would point into a title that no longer exists. */
	if (string != _title) {
		NSString *copy = [string copy];

		[_title release];
		_title = copy;
		_mnemonicLocation = NSNotFound;
	}
}

- (NSAttributedString *)attributedTitle
{
	return _attributedTitle;
}

- (void)setAttributedTitle:(NSAttributedString *)string
{
	if (string != _attributedTitle) {
		NSAttributedString *copy = [string copy];

		[_attributedTitle release];
		_attributedTitle = copy;
	}
}

- (void)setTitleWithMnemonic:(NSString *)string
{
	NSRange amp;

	if (string == nil) {
		[self setTitle:@""];
		return;
	}
	[self setTitle:string];
	amp = [_title rangeOfString:@"&"];
	if (amp.location == NSNotFound) {
		return;			/* no `&`, so no mnemonic — which is the common case */
	}
	if (amp.location + 1 < [_title length] && [_title characterAtIndex:amp.location + 1] == '&') {
		/* `&&` IS A LITERAL AMPERSAND, Apple's convention: the doubled pair stays as ONE `&` and names no
		 * mnemonic. Anything after it is not rescanned, because Apple's parser is one pass. */
		NSString *stripped = [[_title stringByReplacingCharactersInRange:NSMakeRange(amp.location, 2)
								      withString:@"&"] copy];

		[_title release];
		_title = stripped;
		return;
	}
	if (amp.location + 1 >= [_title length]) {
		return;			/* a trailing `&` names nothing */
	}
	_mnemonicLocation = amp.location;
	{
		NSString *stripped = [[_title stringByReplacingCharactersInRange:NSMakeRange(amp.location, 1)
								      withString:@""] copy];

		[_title release];
		_title = stripped;
	}
}

- (unichar)mnemonic
{
	if (_mnemonicLocation == NSNotFound || _mnemonicLocation >= [_title length]) {
		return (unichar)0;
	}
	return [_title characterAtIndex:_mnemonicLocation];
}

- (NSUInteger)mnemonicLocation
{
	return _mnemonicLocation;
}

- (void)setMnemonicLocation:(NSUInteger)location
{
	_mnemonicLocation = location;
}

/* ---- THE KEY EQUIVALENT AND THE ACTION --------------------------------------------------------- */

- (NSString *)keyEquivalent
{
	return _keyEquivalent;
}

- (void)setKeyEquivalent:(NSString *)string
{
	if (string != _keyEquivalent) {
		NSString *copy = [string copy];

		[_keyEquivalent release];
		_keyEquivalent = copy;
	}
}

- (NSUInteger)keyEquivalentModifierMask
{
	return _keyEquivalentModifierMask;
}

- (void)setKeyEquivalentModifierMask:(NSUInteger)mask
{
	_keyEquivalentModifierMask = mask;
}

- (SEL)action
{
	return _action;
}

- (void)setAction:(SEL)selector
{
	_action = selector;
}

- (id)target
{
	return _target;
}

- (void)setTarget:(id)anObject
{
	/* ASSIGNMENT, NOT RETENTION — see the header note: the common arrangement is an item whose target owns
	 * the item, and a retained target would make that a cycle. */
	_target = anObject;
}

/* ---- THE TREE AROUND THE ITEM ------------------------------------------------------------------ */

- (id)submenu
{
	return _submenu;
}

- (void)setSubmenu:(id)aMenu
{
	if (aMenu != _submenu) {
		[aMenu retain];
		[_submenu release];
		_submenu = aMenu;
	}
}

- (id)menu
{
	return _menu;
}

- (void)setMenu:(id)aMenu
{
	/* ALSO NOT RETAINED: the menu owns its items, so an item retaining its menu is the same cycle one level
	 * up. This setter exists because something must tell an item which menu it is in — the menu does. */
	_menu = aMenu;
}

- (id)parentItem
{
	return _parentItem;
}

- (void)setParentItem:(id)anItem
{
	_parentItem = anItem;
}

- (BOOL)hasSubmenu
{
	return _submenu != nil;
}

- (BOOL)isHiddenOrHasHiddenAncestor
{
	id item = self;

	/* **A QUESTION ABOUT THE TREE RATHER THAN A FIELD**: an item inside a HIDDEN item's submenu is hidden
	 * too, which is what a menu builder needs to know before it draws a row. The walk is bounded by the tree
	 * itself and stops at the root. */
	while (item != nil) {
		if ([item isHidden]) {
			return YES;
		}
		item = [item parentItem];
	}
	return NO;
}

/* ---- THE ROW'S OWN DATA ------------------------------------------------------------------------ */

- (NSInteger)tag
{
	return _tag;
}

- (void)setTag:(NSInteger)value
{
	_tag = value;
}

- (NSInteger)state
{
	return _state;
}

- (void)setState:(NSInteger)value
{
	_state = value;
}

- (NSImage *)image
{
	return _image;
}

- (void)setImage:(NSImage *)anImage
{
	if (anImage != _image) {
		[anImage retain];
		[_image release];
		_image = anImage;
	}
}

- (NSImage *)onStateImage
{
	return _onStateImage;
}

- (void)setOnStateImage:(NSImage *)anImage
{
	if (anImage != _onStateImage) {
		[anImage retain];
		[_onStateImage release];
		_onStateImage = anImage;
	}
}

- (NSImage *)offStateImage
{
	return _offStateImage;
}

- (void)setOffStateImage:(NSImage *)anImage
{
	if (anImage != _offStateImage) {
		[anImage retain];
		[_offStateImage release];
		_offStateImage = anImage;
	}
}

- (NSImage *)mixedStateImage
{
	return _mixedStateImage;
}

- (void)setMixedStateImage:(NSImage *)anImage
{
	if (anImage != _mixedStateImage) {
		[anImage retain];
		[_mixedStateImage release];
		_mixedStateImage = anImage;
	}
}

- (NSView *)view
{
	return _view;
}

- (void)setView:(NSView *)aView
{
	if (aView != _view) {
		[aView retain];
		[_view release];
		_view = aView;
	}
}

- (id)representedObject
{
	return _representedObject;
}

- (void)setRepresentedObject:(id)anObject
{
	if (anObject != _representedObject) {
		[anObject retain];
		[_representedObject release];
		_representedObject = anObject;
	}
}

- (NSInteger)indentationLevel
{
	return _indentationLevel;
}

- (void)setIndentationLevel:(NSInteger)level
{
	_indentationLevel = level;
}

/* ---- THE FLAGS --------------------------------------------------------------------------------- */

- (BOOL)isEnabled
{
	return _enabled;
}

- (void)setEnabled:(BOOL)flag
{
	_enabled = flag ? YES : NO;
}

- (BOOL)isAlternate
{
	return _alternate;
}

- (void)setAlternate:(BOOL)flag
{
	_alternate = flag ? YES : NO;
}

- (BOOL)isHidden
{
	return _hidden;
}

- (void)setHidden:(BOOL)flag
{
	_hidden = flag ? YES : NO;
}

- (BOOL)isHighlighted
{
	return _highlighted;
}

- (void)setHighlighted:(BOOL)flag
{
	_highlighted = flag ? YES : NO;
}

- (NSString *)toolTip
{
	return _toolTip;
}

- (void)setToolTip:(NSString *)string
{
	if (string != _toolTip) {
		NSString *copy = [string copy];

		[_toolTip release];
		_toolTip = copy;
	}
}

/* THE USER'S KEY EQUIVALENTS, READ FROM WHERE APPLE PUTS THEM. `NSUserKeyEquivalents` is a defaults dictionary
 * whose keys are menu item TITLES and whose values are key SPECS — `@~f` is command-option-f, because `@` is
 * command, `^` is control, `~` is option and `$` is shift — and Apple's documentation of this door is thinner than
 * the mechanism behind it, SO THE DOOR ANSWERS THE SPEC AS THE DEFAULTS HOLD IT and says so here: a caller
 * comparing it to a single character is comparing it to the wrong thing, and the menu decodes it instead (see
 * `NSMenu`'s matcher, which is where a spec becomes four bits and a key). */
static BOOL s_usesUserKeyEquivalents = NO;	/* OFF, which is Apple's default and the only safe one */

+ (BOOL)usesUserKeyEquivalents
{
	return s_usesUserKeyEquivalents;
}

+ (void)setUsesUserKeyEquivalents:(BOOL)flag
{
	s_usesUserKeyEquivalents = flag;
}

- (NSString *)userKeyEquivalent
{
	NSDictionary *table;

	/* **AND THE SWITCH IS READ HERE, WHICH IS THE WHOLE OF WHY IT IS SHIPPED RATHER THAN OWED**: with it off the
	 * question answers nil for every item — which is what this door did while the row was open and nothing had a
	 * reason to change — and with it on the item's OVERRIDE is what it answers. One reader, in the door the switch
	 * is about, which is the rule this plan has applied to every flag it refused to store-and-ignore. */
	if (!s_usesUserKeyEquivalents) {
		return nil;
	}
	/* A TITLE THAT IS NOT IN THE TABLE HAS NO OVERRIDE, and neither has one whose table is absent: nil answers
	 * both, which is Apple's answer too. */
	table = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NSUserKeyEquivalents"];
	if (table == nil) {
		return nil;
	}
	return [table objectForKey:[self title]];
}


@end
