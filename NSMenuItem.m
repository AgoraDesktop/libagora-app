/*
 * NSMenuItem — one row of a menu, and almost entirely storage.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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

/* ---- AND THE DECODER DOOR ---------------------------------------------------------------------- */

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
	(void)coder;
	/* APPLE'S KEY SET IS NOT PUBLISHED, and this tree will not guess it: a guessed key set is a WRONG MENU
	 * rather than an unfinished door, which is the same ground NSNib's decoding doors stand on. A caller that
	 * built its menu in code gets the same menu; a caller that archived one gets this sentence. */
	fprintf(stderr, "APPKIT-REFUSE: -initWithCoder: needs Apple's published key set for an archived menu "
			"item, and this duplication has not got one — a guessed key set is a wrong menu rather than "
			"an unfinished one. Build the menu in code instead\n");
	return nil;
}

@end
