/*
 * NSFontDescriptor.h — the AppKit's font description: the value an `NSFont` is asked for by.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THIS IS THE SECOND HALF OF `NSFont` AND THE FIRST HALF OF NOTHING ELSE.** §A10bv could not ship
 * `+fontWithDescriptor:size:` or `-fontDescriptor` because this class did not exist; §A10bu's measurement is why
 * the object is a WRAPPER rather than a bridge: Apple's era `NSFontDescriptor.h` declares no `CTFontDescriptor`
 * either, so the descriptor underneath is a private ivar and every signature here is AppKit's own.
 *
 * **APPLE'S ERA OBJECT IS AN ATTRIBUTES DICTIONARY, AND THAT IS THE WHOLE DESIGN.** Its ivar is
 * `NSMutableDictionary *_attributes` (line 64 of the 10.6 header) and every derived descriptor —
 * `-fontDescriptorByAddingAttributes:`, `-fontDescriptorWithSize:`, `-fontDescriptorWithFace:`,
 * `-fontDescriptorWithFamily:`, `-fontDescriptorWithSymbolicTraits:` — is "the same attributes with one thing
 * changed". Core Text's `CTFontDescriptor` is the same idea with a smarter backing store, so the attributes
 * dictionary IS the interface between the two, and `-fontAttributes` answers Core Text's own copy of it.
 *
 * **THE VOCABULARY QUESTION IS LEFT OPEN ON PURPOSE, AND IT IS A REAL ONE.** Apple's era header publishes the
 * AppKit NAMES (`NSFontFamilyAttribute`, `NSFontFaceAttribute`, …) and no LITERALS, so whether those names are
 * the same strings Core Text's `kCTFont…Attribute` keys carry is not answerable from the era artifacts — the
 * first draft of this file's own probe asserted they were, and had to withdraw the claim because the test it
 * used read an object's address rather than its characters. What IS settled is which core text key each door
 * means: family is `kCTFontFamilyNameAttribute`, face is `kCTFontStyleNameAttribute`, and `-fontAttributes`
 * answers Core Text's own dictionary. If the literals turn out to differ, the mapping becomes a table here; the
 * probe prints both sides' Core Text strings so the slice that declares the AppKit constants starts from
 * evidence rather than from this comment.
 *
 * **TWO DOORS ARE DELIBERATELY NOT HERE, AND BOTH ARE NAMED RATHER THAN SILENT**: the era's `-matrix` and
 * `+fontDescriptorWithName:matrix:` take and answer an `NSAffineTransform`, whose attribute form is a
 * `CGAffineTransform` inside a `CFData` — a CONVERSION of its own, and one whose exact wire shape must be
 * measured against Core Text rather than assumed. They arrive with that measurement.
 */
#ifndef APP_KIT_NSFONTDESCRIPTOR_H
#define APP_KIT_NSFONTDESCRIPTOR_H

#import <Foundation/Foundation.h>

/* THE SUBSTRATE'S TYPE, SPELLED WITHOUT IMPORTING ITS HEADER — the rule `NSFont.h` follows and `CGPattern.h`
 * records for `CGContextRef`: a repeated typedef of the same type, in the spelling `CTFontDescriptor.h` uses
 * (line 58: `typedef CTFontDescriptor *CTFontDescriptorRef;`). */
typedef const struct __CTFontDescriptor *CTFontDescriptorRef;

/* **THE TRAITS TYPE IS DECLARED HERE BECAUSE THIS IS WHERE APPLE DECLARES IT** (10.6's `NSFontDescriptor.h` line
 * 21) — a `uint32_t` whose upper four bits are the family class and whose lower sixteen are the appearance, which
 * is why `-fontDescriptorWithSymbolicTraits:` can take one and `-symbolicTraits` can answer one. The trait and
 * class VALUES are the next slice; this slice needs the NAME of the type and nothing more. */
typedef uint32_t NSFontSymbolicTraits;

/* **THE FAMILY CLASS: THE UPPER FOUR BITS.** Apple's own doc on this type says where they live — "the class
 * values are bundled in the upper four bits of the NSFontSymbolicTraits and can be accessed via
 * NSFontFamilyClassMask", and that they "correspond closely to the font class values in the OpenType 'OS/2'
 * table". So the shift is not a choice: 28 is where Apple puts them, and the values below are the era header's
 * own literals (10.6 `NSFontDescriptor.h`), not a transcription of a document that rounds them. */
typedef uint32_t NSFontFamilyClass;

enum {
	NSFontUnknownClass = 0 << 28,
	NSFontOldStyleSerifsClass = 1 << 28,
	NSFontTransitionalSerifsClass = 2 << 28,
	NSFontModernSerifsClass = 3 << 28,
	NSFontClarendonSerifsClass = 4 << 28,
	NSFontSlabSerifsClass = 5 << 28,
	NSFontFreeformSerifsClass = 7 << 28,
	NSFontSansSerifClass = 8 << 28,
	NSFontOrnamentalsClass = 9 << 28,
	NSFontScriptsClass = 10 << 28,
	NSFontSymbolicClass = 12 << 28
};

enum {
	NSFontFamilyClassMask = 0xF0000000
};

/* **AND THE APPEARANCE BITS, IN THE LOWER SIXTEEN.** Apple's comment on the two mutually-exclusive ones is kept
 * where it belongs, on the pair itself: "expanded and condensed traits are mutually exclusive". */
enum {
	NSFontItalicTrait = (1 << 0),
	NSFontBoldTrait = (1 << 1),
	NSFontExpandedTrait = (1 << 5),		/* expanded and condensed traits are mutually exclusive */
	NSFontCondensedTrait = (1 << 6),
	NSFontMonoSpaceTrait = (1 << 10),	/* Use fixed-pitch glyphs if available */
	NSFontVerticalTrait = (1 << 11),	/* Use vertical glyph variants and metrics */
	NSFontUIOptimizedTrait = (1 << 12)	/* Synthesize attributes for UI rendering */
};

/* **THE MODERN SPELLINGS OF THE SAME BITS, IN ONE ENUM, AND THEY ARE ALIASES BY CONSTRUCTION.** Apple's API
 * today names the SAME values `NSFontDescriptorTrait*` and `NSFontDescriptorClass*` under
 * `NSFontDescriptorSymbolicTraits`; the era header does not carry them, and its own sentence is the ground for
 * giving them the same bits: "The corresponding values are kept compatible between NSFontTraitMask and
 * NSFontSymbolicTraits." The probe checks that against Core Text's own trait constants rather than trusting this
 * comment — `kCTFontBoldTrait` and `NSFontBoldTrait` are one value in one library. */
enum {
	NSFontDescriptorTraitItalic = (1 << 0),
	NSFontDescriptorTraitBold = (1 << 1),
	NSFontDescriptorTraitExpanded = (1 << 5),
	NSFontDescriptorTraitCondensed = (1 << 6),
	NSFontDescriptorTraitMonoSpace = (1 << 10),
	NSFontDescriptorTraitVertical = (1 << 11),
	NSFontDescriptorTraitUIOptimized = (1 << 12),
	/* **THREE MODERN CASES ARE DELIBERATELY NOT HERE, AND THE REASON IS THE TREE'S OWN RULE.** Apple's current API
	 * also names `NSFontDescriptorTraitEmphasized`, `…LooseLeading` and `…TightLeading`; the era header does not,
	 * so no artifact in this tree fixes their BITS — and the first draft of this block invented three (one of them
	 * colliding with `Bold`) and wrote a confident comment explaining the choice. There is no reading of the era
	 * that yields a value for them, so they stay on the ledger's work list rather than being guessed: a wrong
	 * constant is a WRONG VALUE, which is the same ground this tier's title refusal stood on for three years.
	 * When a source that fixes them arrives, they are three lines here and three rows flipped. */
	NSFontDescriptorClassUnknown = 0 << 28,
	NSFontDescriptorClassOldStyleSerifs = 1 << 28,
	NSFontDescriptorClassTransitionalSerifs = 2 << 28,
	NSFontDescriptorClassModernSerifs = 3 << 28,
	NSFontDescriptorClassClarendonSerifs = 4 << 28,
	NSFontDescriptorClassSlabSerifs = 5 << 28,
	NSFontDescriptorClassFreeformSerifs = 7 << 28,
	NSFontDescriptorClassSansSerif = 8 << 28,
	NSFontDescriptorClassOrnamentals = 9 << 28,
	NSFontDescriptorClassScripts = 10 << 28,
	NSFontDescriptorClassSymbolic = 12 << 28,
	NSFontDescriptorClassMask = 0xF0000000
};

typedef uint32_t NSFontDescriptorSymbolicTraits;

/* **THE ATTRIBUTE KEYS, AND WHAT THEIR VALUES ARE — WITH THE OPEN QUESTION ANSWERED THE ONLY WAY IT CAN BE.**
 * §A10bw asked whether Apple's `NSFontFamilyAttribute` and Core Text's `kCTFontFamilyNameAttribute` are the same
 * string and had to withdraw the question, because Apple's era header publishes the AppKit NAMES and no literals.
 * **THE TREE ANSWERS IT FOR ITSELF**: the engine's own keys are `@"CTFont"`, `@"CTFontFamilyName"`, … (measured in
 * `CTFontDescriptor.m`/`CTStringAttributes.m`), the AppKit's are `@"NSFont"`, `@"NSFontFamily"`, … — so the two
 * vocabularies ARE distinct here, and the translation the drawing layer does for the font key is not a formality:
 * it is the bridge. These values follow the AppKit's own convention (the name, roughly, as the string), and the
 * mapping into the engine lives in `NSFontDescriptor.m`, where the dictionary the caller supplied is translated on
 * its way to `CTFontDescriptorCreateWithAttributes`.
 *
 * **AND FOUR OF THESE ARE NOT THE ERA'S**: `NSFontDescriptorSystemDesign*` are modern, so no artifact here fixes
 * their values either — they follow the same convention and are stated as this tier's. */
extern NSString *NSFontFamilyAttribute;
extern NSString *NSFontNameAttribute;
extern NSString *NSFontFaceAttribute;
extern NSString *NSFontSizeAttribute;
extern NSString *NSFontVisibleNameAttribute;
extern NSString *NSFontMatrixAttribute;
extern NSString *NSFontVariationAttribute;
extern NSString *NSFontCharacterSetAttribute;
extern NSString *NSFontCascadeListAttribute;
extern NSString *NSFontTraitsAttribute;
extern NSString *NSFontFixedAdvanceAttribute;
extern NSString *NSFontFeatureSettingsAttribute;
extern NSString *NSFontColorAttribute;		/* Apple deprecated this in 10.4: "use NSForegroundColorAttributeName" */
extern NSString *NSFontSymbolicTrait;
extern NSString *NSFontWeightTrait;
extern NSString *NSFontWidthTrait;
extern NSString *NSFontSlantTrait;
extern NSString *NSFontVariationAxisIdentifierKey;
extern NSString *NSFontVariationAxisMinimumValueKey;
extern NSString *NSFontVariationAxisMaximumValueKey;
extern NSString *NSFontVariationAxisDefaultValueKey;
extern NSString *NSFontVariationAxisNameKey;
extern NSString *NSFontFeatureTypeIdentifierKey;
extern NSString *NSFontFeatureSelectorIdentifierKey;
extern NSString *NSFontDescriptorSystemDesignDefault;
extern NSString *NSFontDescriptorSystemDesignMonospaced;
extern NSString *NSFontDescriptorSystemDesignRounded;
extern NSString *NSFontDescriptorSystemDesignSerif;

/* THE STYLE TYPE'S OWN SPELLING, repeated the way this library repeats `CGContextRef` rather than importing the
 * framework header that declares it — one type, two headers, no dependency between them. */
typedef NSString *NSFontTextStyle;

/* **ANNOTATED WHILE WRITTEN (F6), AND EVERY `nullable` BELOW SAYS WHAT THE IMPLEMENTATION ACTUALLY DOES.** This
 * file's first version had no region at all, which the `foundation-cov` gate refuses — and the region is only half
 * the standing practice: the annotations must match the code, which is why the probe's own assertions are the
 * evidence for them. `+fontDescriptorWithName:` answers nil for a nil name and an unresolvable face, the derived
 * descriptors answer nil for nil arguments, and `-matrix` answers the IDENTITY rather than nil when there is no
 * matrix attribute — so that one is NOT nullable and the others are. */
NS_ASSUME_NONNULL_BEGIN

@interface NSFontDescriptor : NSObject <NSCopying, NSCoding>
{
	/* THE SUBSTRATE, PRIVATE — the same seam `NSFont` has, and for the same measured reason. Retained here and
	 * released in `-dealloc`; `@public` for this library's own C factory, the rule `CTRun.h` states. */
	@public
	CTFontDescriptorRef _descriptor;
}

/* THE FOUR NAME AND SIZE DOORS. `+fontDescriptorWithName:size:` is the one `NSFont`'s own class methods use to
 * ask for "this face at this size" — Apple's doc calls its first argument the font's name, which is the
 * PostScript name Core Text's `kCTFontNameAttribute` carries. A SIZE OF ZERO MEANS "the font's own size", which
 * is Core Text's own reading of the attribute and the reason `-pointSize` can answer 0.0 honestly. */
+ (nullable NSFontDescriptor *)fontDescriptorWithFontAttributes:(nullable NSDictionary<NSString *, id> *)attributes;
+ (nullable NSFontDescriptor *)fontDescriptorWithName:(nullable NSString *)fontName size:(CGFloat)fontSize;
- (nullable id)initWithFontAttributes:(nullable NSDictionary<NSString *, id> *)attributes;

/* THE READS: the attributes themselves, one attribute by key, the PostScript name, the size, the traits. */
- (nullable NSDictionary<NSString *, id> *)fontAttributes;
- (nullable id)objectForKey:(nullable NSString *)anAttribute;
- (nullable NSString *)postscriptName;
- (CGFloat)pointSize;
- (NSFontSymbolicTraits)symbolicTraits;

/* **THE FIVE DERIVED DESCRIPTORS**, each "the same attributes with one thing changed" — and
 * `-fontDescriptorByAddingAttributes:` is the one that says it out loud: "the new attributes take precedence
 * over the existing ones in the receiver". */
- (nullable NSFontDescriptor *)fontDescriptorByAddingAttributes:(nullable NSDictionary<NSString *, id> *)attributes;
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(NSFontSymbolicTraits)symbolicTraits;
- (nullable NSFontDescriptor *)fontDescriptorWithSize:(CGFloat)newPointSize;
- (nullable NSFontDescriptor *)fontDescriptorWithFace:(nullable NSString *)newFace;
- (nullable NSFontDescriptor *)fontDescriptorWithFamily:(nullable NSString *)newFamily;

/* **THE MATRIX PAIR, WHICH §A10bw REFUSED BY NAME RATHER THAN GUESSING.** The refusal was right at the time: the
 * era declares `-matrix` and `+fontDescriptorWithName:matrix:` in terms of an `NSAffineTransform`, and the
 * ATTRIBUTE's wire shape was unmeasured. It is measured now — `kCTFontMatrixAttribute` carries an `NSData` holding
 * a `CGAffineTransform`, and the engine's own comment on it says "of which only the a, b, c, and d fields are
 * used", so a translation packed into the data comes back ZEROED. That is a property worth a check rather than a
 * footnote, and the probe has one. */
- (NSAffineTransform *)matrix;
- (nullable NSFontDescriptor *)fontDescriptorWithMatrix:(nullable NSAffineTransform *)matrix;

/* **AND THE CLASS DOOR THAT BUILDS ONE FROM A NAME AND A MATRIX**, which is the pair Apple gives a caller starting from
 * nothing rather than deriving from an existing descriptor. It composes the two measured facts: the name is
 * `kCTFontNameAttribute` and the matrix is the data `fn_matrix_data` packs. */
+ (nullable NSFontDescriptor *)fontDescriptorWithName:(nullable NSString *)fontName
					      matrix:(nullable NSAffineTransform *)matrix;

/* **THE DESCRIPTOR'S STYLE DOOR, COMPOSED RATHER THAN DUPLICATED**: the font answers the style, and the descriptor
 * is that font's own `-fontDescriptor` — so the two doors cannot disagree about which face a style names, which is
 * the whole reason this one is written through the other. */
+ (nullable NSFontDescriptor *)preferredFontDescriptorForTextStyle:(NSFontTextStyle)style;

/* **THE MATCHING PAIR.** Core Text answers the PLURAL (an array, in its own preference order); Apple's era
 * declares both, and the singular one is answered here as the array's FIRST member — stated, because the plural
 * is the shipped path and a second Core Text door for the same question would be a second implementation. */
- (nullable NSArray *)matchingFontDescriptorsWithMandatoryKeys:(nullable NSSet *)mandatoryKeys;
- (nullable NSFontDescriptor *)matchingFontDescriptorWithMandatoryKeys:(nullable NSSet *)mandatoryKeys;

@end

NS_ASSUME_NONNULL_END

#endif /* APP_KIT_NSFONTDESCRIPTOR_H */
