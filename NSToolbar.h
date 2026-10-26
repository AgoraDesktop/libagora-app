/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSToolbar.h — the strip of items between a window's title bar and its content.
 *
 * **THE TOOLBAR IS THE WINDOW'S, AND THE BAND IT TAKES IS CARVED OUT OF THE FRAME.** `NSWindow` already owns a
 * client-drawn title bar; this class owns the row below it, and `NSWindow -contentRectForFrameRect:` shrinks by the
 * toolbar's height while the toolbar is visible. The arithmetic therefore stays in one place: the content view is
 * laid out in the rect the window says is the content, the chrome is painted above the toolbar, and the toolbar is
 * painted in the band between them. Showing or hiding it preserves the CONTENT's size and changes the FRAME's, which
 * is what a person expects from a toolbar toggle: the document does not get shorter, the window gets taller.
 *
 * **THE ITEMS ARE THE DELEGATE'S, UNLESS THE ARCHIVE SUPPLIED THEM.** A toolbar asks its delegate for a default
 * identifier list, for an item when an identifier is inserted, and for the set of identifiers a user may choose from.
 * A nib, however, carries pre-made `NSToolbarItem`s (Apple's `NSToolbarIBIdentifiedItems`), and Apple's toolbar keeps
 * them in an item database consulted before the delegate — the same shape is here, in `_identifiedItems`. The three
 * standard spacers (`NSToolbarSeparatorItemIdentifier`, `NSToolbarSpaceItemIdentifier`,
 * `NSToolbarFlexibleSpaceItemIdentifier`) are made here because they are not items a delegate can usefully own;
 * the four "standard commands" are asked of the delegate first, and a toolbar with no delegate item for one answers
 * a plain item carrying the command's own action. A decoded toolbar with no delegate loads its own identifier list,
 * so an archived toolbar is not empty merely because it is unattached.
 *
 * **WHAT IS DELIBERATELY NOT HERE: THE CUSTOMIZATION PALETTE.** The palette is a second window with a drag-and-drop
 * editing session, and this tier has neither a panel class nor a drag session. `-runCustomizationPalette:` refuses
 * by name, `-customizationPaletteIsRunning` answers NO, and `-allowsUserCustomization` is still recorded and still
 * read by the layout — so a program that sets it is not claiming a palette exists. THE CONFIGURATION DICTIONARY IS
 * IMPLEMENTED, because its contents are data rather than a window: Apple keeps the keys private, so this tier
 * documents its own (`NSToolbarItemIdentifiers` and friends, named on the doors below) and says so.
 *
 * Written from `NSToolbar.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSTOOLBAR_H
#define APPKIT_NSTOOLBAR_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSDictionary;
@class NSMutableArray;
@class NSNotification;
@class NSString;
@class NSWindow;
@class NSToolbar;
@class NSToolbarItem;

/* THE ERA'S ENUMERATIONS, WITHOUT NUMBERS BECAUSE THE HEADER GIVES NONE. `Default` means "the toolbar chooses",
 * which is icon-and-label for display and regular for size. */
enum {
	NSToolbarDisplayModeDefault = 0,
	NSToolbarDisplayModeIconAndLabel = 1,
	NSToolbarDisplayModeIconOnly = 2,
	NSToolbarDisplayModeLabelOnly = 3
};
typedef NSUInteger NSToolbarDisplayMode;

enum {
	NSToolbarSizeModeDefault = 0,
	NSToolbarSizeModeRegular = 1,
	NSToolbarSizeModeSmall = 2
};
typedef NSUInteger NSToolbarSizeMode;

/* THE TWO ANNOUNCEMENTS. Each names an item in its userInfo under `NSToolbarItemKey`, which is this tree's own key
 * spelling for the dictionary Apple's header describes as `@"item"`. */
extern NSString *NSToolbarWillAddItemNotification;
extern NSString *NSToolbarDidRemoveItemNotification;
extern NSString *NSToolbarItemKey;

/* **THE CONFIGURATION DICTIONARY'S KEYS, WHICH ARE THIS TIER'S BECAUSE APPLE'S ARE PRIVATE.** A dictionary written
 * by this class and read back by it is stable across a process; one written by Apple's AppKit is not promised to be
 * understood, and `-setConfigurationFromDictionary:` says what it does with a key it does not know: it ignores it.
 * The item list is the only required key. */
extern NSString *NSToolbarItemIdentifiers;
extern NSString *NSToolbarSelectedItemIdentifier;
extern NSString *NSToolbarDisplayModeKey;
extern NSString *NSToolbarSizeModeKey;
extern NSString *NSToolbarShowsBaselineSeparatorKey;
extern NSString *NSToolbarAllowsUserCustomizationKey;

/* THE DELEGATE. All of it is optional in the era's own header, including the three the prose calls required for a
 * programmatic toolbar — a toolbar with no delegate is empty, not broken. The notification methods are the ones
 * Apple documents as the place to cache an item or tear a cache down. */
@protocol NSToolbarDelegate <NSObject>
@optional
- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar
	     itemForItemIdentifier:(NSString *)itemIdentifier
	 willBeInsertedIntoToolbar:(BOOL)flag;
- (nullable NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar;
- (nullable NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar;
- (nullable NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar;
- (void)toolbarWillAddItem:(NSNotification *)notification;
- (void)toolbarDidRemoveItem:(NSNotification *)notification;
@end

@interface NSToolbar : NSObject <NSSecureCoding>
{
	NSString *_identifier;			/* COPIED: the toolbar's name, and the defaults key's stem */
	NSMutableArray *_items;			/* RETAINED: the toolbar owns the items it was given */
	NSMutableArray *_itemIdentifiers;	/* RETAINED, parallel to `_items` */
	NSMutableDictionary *_identifiedItems;	/* RETAINED: pre-made items a nib supplied, by identifier */
	id _delegate;				/* NOT RETAINED: this tree's rule for every delegate */
	NSWindow *_window;			/* NOT RETAINED: the window owns the toolbar */
	NSString *_selectedItemIdentifier;	/* COPIED, or nil */
	NSToolbarDisplayMode _displayMode;
	NSToolbarSizeMode _sizeMode;
	BOOL _visible;
	BOOL _allowsUserCustomization;
	BOOL _autosavesConfiguration;
	BOOL _showsBaselineSeparator;
	BOOL _didLoadItems;
	BOOL _suppressAutosave;
	id _toolbarView;			/* RETAINED: the private view, made on first use */
}

/* THE ONE WAY IN. The identifier is the toolbar's name and the stem of its autosave key; two toolbars with the same
 * identifier are NOT synchronized in this tier (that would need a process-wide registry), which is stated at
 * `-setAutosavesConfiguration:` rather than implied by a shared string. */
- (instancetype)initWithIdentifier:(NSString *)identifier;
- (NSString *)identifier;

/* THE PRIMITIVES. An insertion asks the toolbar's identified items first and then the delegate (and for one that is
 * not in the allowed list, it asks anyway: the allowed list is the PALETTE's rule, and this tier has no palette).
 * `-items` is the live order and loads an archived identifier list even when the toolbar has no window. */
- (void)insertItemWithItemIdentifier:(NSString *)itemIdentifier atIndex:(NSInteger)index;
- (void)removeItemAtIndex:(NSInteger)index;
- (NSArray *)items;
- (NSArray *)visibleItems;

/* THE DELEGATE, AND THE TWO ATTRIBUTES THE LAYOUT READS. */
- (void)setDelegate:(nullable id <NSToolbarDelegate>)delegate;
- (nullable id <NSToolbarDelegate>)delegate;
- (void)setDisplayMode:(NSToolbarDisplayMode)displayMode;
- (NSToolbarDisplayMode)displayMode;
- (void)setSizeMode:(NSToolbarSizeMode)sizeMode;
- (NSToolbarSizeMode)sizeMode;

/* VISIBILITY. Showing grows the window's frame by the toolbar's height and hiding shrinks it, in both cases keeping
 * the content's size — see the note at the top of the file for why that is the contract. */
- (void)setVisible:(BOOL)shown;
- (BOOL)isVisible;

/* SELECTION. The delegate's `-toolbarSelectableItemIdentifiers:` decides which identifiers may be selected; setting
 * an identifier not in that list is recorded anyway, because the delegate may answer differently later. */
- (void)setSelectedItemIdentifier:(nullable NSString *)itemIdentifier;
- (nullable NSString *)selectedItemIdentifier;

/* THE BASELINE SEPARATOR AND THE CUSTOMIZATION FLAGS. */
- (void)setShowsBaselineSeparator:(BOOL)flag;
- (BOOL)showsBaselineSeparator;
- (void)setAllowsUserCustomization:(BOOL)allowCustomization;
- (BOOL)allowsUserCustomization;

/* **THE PALETTE IS A NAMED REFUSAL, NOT A STUB.** See the note at the top of this file: the panel and its drag
 * session are absent, so the door says so and the question answers NO. */
- (void)runCustomizationPalette:(nullable id)sender;
- (BOOL)customizationPaletteIsRunning;

/* AUTOSAVE AND THE CONFIGURATION DICTIONARY. Autosaving writes to `NSUserDefaults` under
 * `@"NSToolbar Configuration <identifier>"`; the dictionary's keys are the `…Key` constants above. */
- (void)setAutosavesConfiguration:(BOOL)flag;
- (BOOL)autosavesConfiguration;
- (void)setConfigurationFromDictionary:(NSDictionary *)configDict;
- (NSDictionary *)configurationDictionary;

/* VALIDATION. `-validateVisibleItems` is what a window's update pass calls; each item decides through its own
 * target, which is where `NSToolbarItemValidation` and `NSUserInterfaceValidations` are asked. */
- (void)validateVisibleItems;

@end

/* THE STANDARD IDENTIFIERS, WITH APPLE'S OWN STRINGS — a caller writes them in a delegate's array, so their values
 * are part of the contract rather than an implementation detail. */
extern NSString *NSToolbarSeparatorItemIdentifier;
extern NSString *NSToolbarSpaceItemIdentifier;
extern NSString *NSToolbarFlexibleSpaceItemIdentifier;
extern NSString *NSToolbarShowColorsItemIdentifier;
extern NSString *NSToolbarShowFontsItemIdentifier;
extern NSString *NSToolbarCustomizeToolbarItemIdentifier;
extern NSString *NSToolbarPrintItemIdentifier;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTOOLBAR_H */
