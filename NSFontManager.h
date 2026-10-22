/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSFontManager.h — THE FONT QUERY ENGINE, AND THE TARGET THE FONT PANEL TALKS TO.
 *
 * **THE CLASS IS FOUR THINGS AND THE ORDER MATTERS.** A LIST of every face the system can produce (enumerated through
 * Core Text once and kept); a SET OF CONVERSIONS over a font — size, family, face, trait, weight — that are pure
 * functions of an `NSFont` and a request; a NAMED COLLECTION store; and an ACTION SENDER, which is how a font panel or
 * a Font menu changes the font of whatever is the current target. The conversions are the heart: `-convertFont:` with
 * no argument is the door a text view calls back through after the manager sends `-changeFont:`, and it applies THE
 * LAST ACTION the manager was asked to perform (`-modifyFont:`, `-addFontTrait:`, `-removeFontTrait:`,
 * `-modifyFontViaPanel:`) or the panel's selection.
 *
 * **THE ENUMERATION IS REAL DATA RATHER THAN A STUB.** `CTFontCollectionCreateFromAvailableFonts` plus the collection's
 * matching door is this tree's path to "every face", and the families, faces, PostScript names and traits below all
 * come from it. What the engine does NOT expose is recorded rather than faked: this Core Text's symbolic traits carry
 * italic, bold, expanded, condensed, monospaced and vertical, so `-traitsOfFont:` reports those and the era's
 * `NSSmallCapsFontMask`, `NSPosterFontMask`, `NSCompressedFontMask` and `NSNarrowFontMask` are NOT reported — there is
 * no bit for them to be read from.
 *
 * **WEIGHTS ARE THE ERA'S 0–15, MAPPED FROM THE ENGINE'S NORMALISED TRAIT.** Core Text's weight trait runs -1.0…1.0;
 * `-weightOfFont:` maps it onto 0…15 with 5 for regular and 9 for bold, and a face with no weight trait falls back to
 * its bold bit. `-convertFont:toHaveTrait:`/`toNotHaveTrait:` go the other way through the symbolic traits. The two
 * mappings live in one place (two file-static functions) so a conversion cannot disagree with the question that
 * reports it.
 *
 * WHAT THIS CLASS DOES NOT DO, at the door: `-orderFrontStylesPanel:` refuses by name (the era's styles panel is not in
 * this tier), a collection's visibility OPTION is recorded and not obeyed (there is no collection browser), and
 * `-localizedNameForFamily:face:` answers the names it was given because this tier has no localization tables.
 *
 * Written from `NSFontManager.h` in the MacOSX10.6 SDK. The trait-mask and action values are the header's own, declared
 * here because 10.6 declares them in this class's header.
 */
#ifndef APPKIT_NSFONTMANAGER_H
#define APPKIT_NSFONTMANAGER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSArray;
@class NSDictionary;
@class NSFont;
@class NSFontDescriptor;
@class NSFontPanel;
@class NSMenu;
@class NSMutableDictionary;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

/* THE ERA'S TRAIT WORD. The bits ARE `NSFontTraitMask`'s, and the two 0x01000000 masks are the "remove" spellings a
 * menu item carries rather than properties a font has. */
enum {
	NSItalicFontMask			= 0x00000001,
	NSBoldFontMask				= 0x00000002,
	NSUnboldFontMask			= 0x00000004,
	NSNonStandardCharacterSetFontMask	= 0x00000008,
	NSNarrowFontMask			= 0x00000010,
	NSExpandedFontMask			= 0x00000020,
	NSCondensedFontMask			= 0x00000040,
	NSSmallCapsFontMask			= 0x00000080,
	NSPosterFontMask			= 0x00000100,
	NSCompressedFontMask			= 0x00000200,
	NSFixedPitchFontMask			= 0x00000400,
	NSUnitalicFontMask			= 0x01000000
};
typedef NSUInteger NSFontTraitMask;

/* AND THE ACTION WORD — what the LAST request was, which is what `-convertFont:` applies. */
typedef enum {
	NSNoFontChangeAction = 0,
	NSViaPanelFontAction = 1,
	NSAddTraitFontAction = 2,
	NSSizeUpFontAction = 3,
	NSSizeDownFontAction = 4,
	NSHeavierFontAction = 5,
	NSLighterFontAction = 6,
	NSRemoveTraitFontAction = 7
} NSFontAction;

@interface NSFontManager : NSObject
{
	NSFont *_selectedFont;			/* RETAINED */
	NSDictionary *_selectedAttributes;	/* RETAINED: the panel's selection, as attributes */
	BOOL _multiple;
	BOOL _enabled;
	id _delegate;				/* ASSIGN */
	id _target;				/* ASSIGN */
	SEL _action;
	NSFontAction _currentFontAction;
	NSFontTraitMask _pendingTrait;
	NSMenu *_fontMenu;			/* RETAINED */
	NSArray *_allDescriptors;		/* RETAINED: the enumeration, once */
	NSMutableDictionary *_faceInfo;		/* RETAINED: PostScript name -> [weight, traits] */
	NSMutableDictionary *_collections;	/* RETAINED: name -> NSMutableArray of NSFontDescriptor */
	NSMutableDictionary *_collectionOptions;/* RETAINED: name -> NSNumber (recorded, not obeyed) */
}

/* THE SINGLETON, AND THE TWO FACTORY HOOKS APPLE DECLARES ON THE CLASS.** The factories let a caller substitute a
 * subclass for the shared manager or the shared panel; both are applied only if the shared object does not exist yet,
 * which is Apple's own rule and the reason the doors are class methods. */
+ (NSFontManager *)sharedFontManager;
+ (void)setFontManagerFactory:(nullable Class)factory;
+ (void)setFontPanelFactory:(nullable Class)factory;

/* ============================================================================================ *
 * THE ENUMERATION.                                                                              *
 * ============================================================================================ */

/* Every face (PostScript names), every family, and a family's members. A member is Apple's four-field row —
 * `[fontName, faceName, weight, traits]` — which is why `-availableMembersOfFontFamily:` is the door a family menu is
 * built from. */
- (NSArray *)availableFonts;
- (NSArray *)availableFontFamilies;
- (nullable NSArray *)availableMembersOfFontFamily:(NSString *)family;
- (NSArray *)availableFontNamesWithTraits:(NSFontTraitMask)mask;
- (NSArray *)availableFontNamesMatchingFontDescriptor:(NSFontDescriptor *)descriptor;

/* AND THE THREE QUESTIONS ABOUT ONE FONT. */
- (NSFontTraitMask)traitsOfFont:(nullable NSFont *)font;
- (NSInteger)weightOfFont:(nullable NSFont *)font;
- (BOOL)fontNamed:(NSString *)fontName hasTraits:(NSFontTraitMask)mask;
- (nullable NSFont *)fontWithFamily:(NSString *)family traits:(NSFontTraitMask)mask
			     weight:(NSInteger)weight size:(CGFloat)size;

/* ============================================================================================ *
 * THE CONVERSIONS.                                                                              *
 * ============================================================================================ */

/* `-convertFont:` APPLIES THE LAST ACTION; the rest are the explicit requests. Each answers the converted font (or the
 * receiver's argument when the conversion cannot be made), which is Apple's contract for every one of them. */
- (nullable NSFont *)convertFont:(nullable NSFont *)font;
- (nullable NSFont *)convertFont:(nullable NSFont *)font toSize:(CGFloat)size;
- (nullable NSFont *)convertFont:(nullable NSFont *)font toFamily:(NSString *)family;
- (nullable NSFont *)convertFont:(nullable NSFont *)font toFace:(NSString *)face;
- (nullable NSFont *)convertFont:(nullable NSFont *)font toHaveTrait:(NSFontTraitMask)trait;
- (nullable NSFont *)convertFont:(nullable NSFont *)font toNotHaveTrait:(NSFontTraitMask)trait;
- (NSFontTraitMask)convertFontTraits:(NSFontTraitMask)traits;

/* **THE WEIGHT STEP ANSWERS A WEIGHT, NOT A FONT.** Apple's door returns the new 0…15 value, and it is the arithmetic
 * `-convertFont:`'s two weight actions use — `-convertFont:` is the door that answers a face. */
- (NSInteger)convertWeight:(BOOL)upFlag ofFont:(nullable NSFont *)font;
- (nullable NSDictionary *)convertAttributes:(NSDictionary *)attributes;

/* ============================================================================================ *
 * THE ACTION: WHAT A FONT PANEL OR A FONT MENU ASKS FOR.                                        *
 * ============================================================================================ */

- (void)setSelectedFont:(nullable NSFont *)fontObj isMultiple:(BOOL)flag;
- (nullable NSFont *)selectedFont;
- (void)setSelectedAttributes:(nullable NSDictionary *)attributes isMultiple:(BOOL)flag;
- (BOOL)isMultiple;

/* THE FOUR REQUESTS THAT BECOME AN ACTION, AND THE DOOR THAT SENDS IT. **THE SENDER IS THE MANAGER ITSELF** — the
 * convention the era's `-changeFont:` handler is written against — and `-convertFont:` is what the handler calls back
 * through, which is why the action is recorded before the message goes out. */
- (void)modifyFont:(nullable id)sender;
- (void)modifyFontViaPanel:(nullable id)sender;
- (void)addFontTrait:(nullable id)sender;
- (void)removeFontTrait:(nullable id)sender;
- (void)sendAction;
- (NSFontAction)currentFontAction;

/* THE TARGET, THE ACTION AND THE DELEGATE. The delegate is told when the selected font changes; the target is the
 * object `-sendAction` sends `-changeFont:` to. */
- (void)setTarget:(nullable id)aTarget;
- (nullable id)target;
- (void)setAction:(nullable SEL)aSelector;
- (nullable SEL)action;
- (void)setDelegate:(nullable id)anObject;
- (nullable id)delegate;

/* ENABLE AND DISABLE: a disabled manager's `-sendAction` does nothing and its font menu is empty. */
- (void)setEnabled:(BOOL)flag;
- (BOOL)isEnabled;

/* ============================================================================================ *
 * THE FONT MENU AND THE PANEL.                                                                  *
 * ============================================================================================ */

/* **`-fontMenu:` BUILDS A MENU FROM THE FAMILIES**, one item each, tagged with the family's index and sending
 * `-modifyFont:` to this manager. The era's menu has more structure (sizes, styles, a "Show Fonts" item); this is the
 * family half, and the header says so. */
- (nullable NSMenu *)fontMenu:(BOOL)create;
- (void)setFontMenu:(nullable NSMenu *)newMenu;

- (void)orderFrontFontPanel:(nullable id)sender;
- (void)orderFrontStylesPanel:(nullable id)sender;
- (nullable NSFontPanel *)fontPanel:(BOOL)create;

/* THE ERA'S LOCALIZED NAME PAIR, WHICH THIS TIER ANSWERS AS ITSELF: there are no localization tables, so a face's name
 * is its name. */
- (nullable NSString *)localizedNameForFamily:(nullable NSString *)family face:(nullable NSString *)face;

/* ============================================================================================ *
 * THE COLLECTIONS.                                                                              *
 * ============================================================================================ */

- (NSArray *)collectionNames;
- (void)addCollection:(NSString *)collectionName options:(NSUInteger)options;
- (void)removeCollection:(NSString *)collectionName;
- (nullable NSArray *)fontDescriptorsInCollection:(NSString *)collectionName;
- (void)addFontDescriptors:(NSArray *)descriptors toCollection:(NSString *)collectionName;
- (void)removeFontDescriptor:(NSFontDescriptor *)descriptor fromCollection:(NSString *)collectionName;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSFONTMANAGER_H */
