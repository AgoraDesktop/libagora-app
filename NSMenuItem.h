/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSMenuItem.h — one row of a menu (stage D).
 *
 * THIS IS THE FIRST MENU CLASS, AND IT IS A FROM-SCRATCH ONE rather than a class this tree already ships:
 * nothing named `NSMenu*` existed here before it, which is why stage D is the first stage whose work is to
 * BUILD the surface rather than to finish it.
 *
 * A MENU ITEM IS A ROW OF DATA, AND ALMOST ALL OF THIS HEADER IS ITS STORAGE. Apple's item carries a title (or
 * an attributed one), a key equivalent with its modifier mask, an action and a target, a tag, a state, an
 * image, an optional submenu, an optional view, a tool tip, an indentation level and a handful of flags. What
 * the class DECIDES rather than stores is small and is named at each door below: the mnemonic is PARSED out of
 * a title when a caller asks for that spelling, `-hasSubmenu` and `-hiddenOrHasHiddenAncestor` are QUESTIONS
 * about the tree rather than fields, and `-userKeyEquivalent` is the one answer this tier cannot give.
 *
 * THE OWNERSHIP IS APPLE'S AND IT IS NOT UNIFORM, WHICH IS THE THING A READER OF THIS HEADER SHOULD NOTICE:
 *
 *   A TARGET IS NOT RETAINED (`assign`), and that is Apple's contract rather than a shortcut — a menu item
 *   that owned its target would make the common arrangement (an item whose target is its own controller,
 *   which owns the item) a cycle. A PARENT ITEM and the OWNING MENU are not retained either, for the same
 *   reason: the tree points up without owning.
 *   EVERYTHING ELSE IS STRONG: the strings are COPIED (a caller that hands over a mutable title must not be
 *   able to change a menu that is already built), and the images, the submenu, the view and the represented
 *   object are retained.
 *
 * AND TWO MEMBERS ARE SPELLED `id` FOR THE OVER-CREDITING RULE THIS TREE STATES WHEREVER AN UNSHIPPED CLASS
 * WOULD OTHERWISE BE NAMED: `NSMenu` is a class this tier does not ship yet, so the submenu, the owning menu
 * and the parent item are `id` here — writing `@class NSMenu;` would have the ledger credit that class's own
 * eighty-five rows to this one. The view and the images ARE typed, because `NSView` and `NSImage` ship.
 *
 * AND ONE ROW IS DELIBERATELY NOT HERE: `-usesUserKeyEquivalents`. It is a switch on whether the class
 * consults a USER's key-equivalent table, and there is no such table in this tier — so it would be a stored
 * flag with no reader, which is what this tree refuses. It stays owed rather than half-shipped, and it is
 * named here so the gap is visible. (`-userKeyEquivalent`, which is a QUESTION rather than a switch, IS here
 * and answers nil for the same reason: nobody has overridden anything.)
 */
#ifndef APPKIT_NSMENUITEM_H
#define APPKIT_NSMENUITEM_H

#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import <AppKit/NSImage.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMenuItem : NSObject <NSSecureCoding>
{
	NSString *_title;			/* RETAINED (a copy of what was set) */
	NSAttributedString *_attributedTitle;	/* RETAINED (a copy) */
	NSString *_keyEquivalent;		/* RETAINED (a copy) */
	NSUInteger _keyEquivalentModifierMask;
	NSString *_toolTip;			/* RETAINED (a copy) */
	/* NOT RETAINED, AND BOTH ARE APPLE'S CONTRACT RATHER THAN A SHORTCUT — see the header note. */
	id _target;
	id _menu;				/* the menu that owns this item, or nil */
	id _parentItem;				/* the item whose submenu holds this one, or nil */
	/* AND THE ONES THIS OBJECT OWNS. */
	id _submenu;				/* RETAINED (an NSMenu, a class this tier does not ship) */
	id _representedObject;			/* RETAINED */
	NSView *_view;				/* RETAINED */
	NSImage *_image;			/* RETAINED */
	NSImage *_onStateImage;
	NSImage *_offStateImage;
	NSImage *_mixedStateImage;
	SEL _action;
	NSInteger _tag;
	NSInteger _state;
	NSInteger _indentationLevel;
	/* THE MNEMONIC, WHICH THIS CLASS DERIVES RATHER THAN STORES: `_mnemonicLocation` is the index of the
	 * character after an `&` in the title, or NSNotFound when there is none, and `-mnemonic` reads the
	 * character OUT of the title at that index rather than keeping a second copy that could drift. */
	NSUInteger _mnemonicLocation;
	BOOL _enabled;
	BOOL _alternate;
	BOOL _hidden;
	BOOL _highlighted;
	BOOL _separator;
}

/* THE TWO CONSTRUCTORS AND THE ONE FACTORY. Apple's designated initialiser takes the three things a caller
 * almost always has — a title, an action and a key equivalent — and the factory builds the row that draws as
 * a dividing line. */
- (instancetype)initWithTitle:(NSString *)string
		       action:(nullable SEL)selector
		keyEquivalent:(NSString *)charCode;
+ (NSMenuItem *)separatorItem;
- (BOOL)isSeparatorItem;

/* THE TITLE, AND THE MNEMONIC AS A SPELLING OF IT. `-setTitleWithMnemonic:` parses an `&` out of the string
 * (Apple's convention, and `&&` is a literal one), records WHERE it landed, and stores the title without it;
 * `-mnemonic` then answers the character at that location and `-mnemonicLocation` the index — so there is one
 * copy of the title and no second string to keep in step. */
@property (copy) NSString *title;
@property (nullable, copy) NSAttributedString *attributedTitle;
- (void)setTitleWithMnemonic:(nullable NSString *)string;
@property (readonly) unichar mnemonic;
/* AND THE LOCATION IS DECLARED AS A PROPERTY **AND** AS ITS SETTER, which is NOT redundant here: THE LEDGER
 * HOLDS A ROW FOR `-setMnemonicLocation:` ITSELF, and a property declaration does not put its setter's NAME
 * into the header text — so the row would stay open with the door implemented and, as far as the instrument can
 * see, unwritten. This tree's `NSBezierPath` header learned the same thing about `-setLineDash:count:phase:`
 * and says so where it declares that pair. */
@property NSUInteger mnemonicLocation;
- (void)setMnemonicLocation:(NSUInteger)location;

/* THE KEY EQUIVALENT AND ITS MASK. An empty string means the item has none, which is Apple's reading. */
@property (copy) NSString *keyEquivalent;
@property NSUInteger keyEquivalentModifierMask;

/* THE ACTION AND ITS TARGET — and the target is NOT owned (see the header note). */
@property (nullable) SEL action;
@property (nullable, assign) id target;

/* THE TREE AROUND THE ITEM, each an `id` for the over-crediting rule stated above — AND THE TWO APPLE
 * DECLARES READONLY ARE READWRITE HERE, a deviation with a reason rather than a preference: APPLE'S MENU SETS
 * THEM ITSELF from inside the same library, and a second class in THIS tree needs the same seam — so the door
 * is declared where the class that will call it can see it, the arrangement `NSWindow`'s
 * `cg_waitForEventInMilliseconds` and `NSApplication`'s `cg_addWindow:` already use. When `NSMenu` lands it is
 * the caller and nothing else should be: an item's owner and its parent are facts about the TREE, so a caller
 * that sets one by hand is describing a tree that does not exist. */
@property (nullable, strong) id submenu;
@property (nullable, assign) id menu;
@property (nullable, assign) id parentItem;
@property (readonly) BOOL hasSubmenu;

/* THE ROW'S OWN DATA. `state` is an NSInteger rather than an enum this tier has not got (Apple's is an
 * `NSControlStateValue`), and its values are the three Apple publishes: off, on and mixed. */
@property NSInteger tag;
@property NSInteger state;
@property (nullable, strong) NSImage *image;
@property (nullable, strong) NSImage *onStateImage;
@property (nullable, strong) NSImage *offStateImage;
@property (nullable, strong) NSImage *mixedStateImage;
@property (nullable, strong) NSView *view;
@property (nullable, strong) id representedObject;
@property NSInteger indentationLevel;

/* THE FLAGS. `-isHiddenOrHasHiddenAncestor` IS A QUESTION RATHER THAN A FIELD, which is why it has no setter —
 * AND ITS GETTER CARRIES APPLE'S `is` PREFIX, spelled out here because THE LEDGER'S ROW FOR IT DOES NOT (the
 * row is `hiddenOrHasHiddenAncestor`, and this tree's sweep accepts the `is`-affixed getter as its
 * declaration). Same shape as `NSImage`'s `-template`. */
@property (getter=isEnabled) BOOL enabled;
@property (getter=isAlternate) BOOL alternate;
@property (getter=isHidden) BOOL hidden;
@property (readonly, getter=isHiddenOrHasHiddenAncestor) BOOL hiddenOrHasHiddenAncestor;
@property (getter=isHighlighted) BOOL highlighted;
@property (nullable, copy) NSString *toolTip;

/* AND THE TWO ABOUT USER KEY EQUIVALENTS, WHICH ARE ONE MECHANISM RATHER THAN TWO ROWS. **THE SWITCH IS A CLASS
 * METHOD** — Apple declares `+usesUserKeyEquivalents`, not an instance property, because "do menu items consult the
 * user's overrides" is a question about the PROCESS rather than about one row, and the header's own note about the
 * gap is what made it look like a per-item flag. The QUESTION answers the user's override when the switch is on and
 * nil when it is off, and the overrides come from Apple's own documented place: `NSUserDefaults`'
 * `NSUserKeyEquivalents` dictionary, whose keys are menu item TITLES and whose values are key specs like `@~f`
 * (command-option-f). */
+ (BOOL)usesUserKeyEquivalents;
+ (void)setUsesUserKeyEquivalents:(BOOL)flag;
@property (readonly, copy, nullable) NSString *userKeyEquivalent;

/* AND THE DECODER DOOR, WHICH REFUSES BY NAME: Apple archives a menu item as a keyed archive whose key set
 * is not published, and a guessed key set is a wrong menu rather than an unfinished one. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSMENUITEM_H */
