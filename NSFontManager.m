/*
 * NSFontManager — the font query engine, the conversions and the action sender.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE ENUMERATION IS ONE CACHED ARRAY, AND EVERY NAME QUESTION READS IT.** Core Text answers "every face" through a
 * collection, so `-fn_allDescriptors` asks once, keeps the descriptors, and the family, member, name and trait doors
 * are all projections of that array. The cache is never invalidated: a face registered after first use is invisible
 * until relaunch, which is a stated limit rather than a bug, because the era's manager offers no reload door either.
 *
 * **THE CONVERSIONS GO THROUGH FACE NAMES RATHER THAN THROUGH A MATCHING DESCRIPTOR.** A descriptor carrying a changed
 * symbolic-traits dictionary is a QUESTION for the matcher, and a matcher's nearest answer is not a promise about the
 * face a caller wanted; the member list is. So `-convertFont:toHaveTrait:` looks for a member of the SAME family with
 * the wanted bit, picks the one whose weight is closest, and builds it by PostScript name — the one Core Text creation
 * path this tier trusts completely.
 *
 * THE TWO MAPPINGS (trait mask ↔ symbolic traits, and weight ↔ the normalised weight trait) are file-static functions,
 * so the question and the conversion cannot disagree.
 */
#import <AppKit/NSFontManager.h>

#import <AppKit/NSFont.h>
#import <AppKit/NSFontDescriptor.h>
#import <AppKit/NSFontPanel.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSApplication.h>
#import <AppKit/AppKitRefusal.h>

#import <CoreText/CTFont.h>
#import <CoreText/CTFontCollection.h>
#import <CoreText/CTFontDescriptor.h>
#import <CoreText/CTFontTraits.h>

#include <math.h>
#include <stdlib.h>

static Class s_managerFactory = Nil;
static NSFontManager *s_sharedFontManager = nil;

/* ============================================================================================ *
 * THE TWO MAPPINGS.                                                                             *
 * ============================================================================================ */

/* **THE MASK'S POSITIVE BITS ARE THE ONES THE ENGINE HAS.** Core Text's symbolic traits carry italic, bold, expanded,
 * condensed and monospaced; the era's small-caps, poster, compressed and narrow masks have no bit to be read from, so
 * they are never REPORTED — and the two "un-" masks are the remove spellings a menu item carries, not properties. */
static NSFontTraitMask fn_traitsFromSymbolic(NSFontSymbolicTraits symbolic, BOOL monospaced)
{
	NSFontTraitMask mask = 0;

	if ((symbolic & kCTFontItalicTrait) != 0) {
		mask |= NSItalicFontMask;
	}
	if ((symbolic & kCTFontBoldTrait) != 0) {
		mask |= NSBoldFontMask;
	}
	if ((symbolic & kCTFontExpandedTrait) != 0) {
		mask |= NSExpandedFontMask;
	}
	if ((symbolic & kCTFontCondensedTrait) != 0) {
		mask |= NSCondensedFontMask;
	}
	if (monospaced) {
		mask |= NSFixedPitchFontMask;
	}
	return mask;
}

static NSFontSymbolicTraits fn_symbolicFromTraits(NSFontTraitMask mask)
{
	NSFontSymbolicTraits symbolic = 0;

	if ((mask & NSItalicFontMask) != 0) {
		symbolic |= kCTFontItalicTrait;
	}
	if ((mask & NSBoldFontMask) != 0) {
		symbolic |= kCTFontBoldTrait;
	}
	if ((mask & NSExpandedFontMask) != 0) {
		symbolic |= kCTFontExpandedTrait;
	}
	if ((mask & NSCondensedFontMask) != 0) {
		symbolic |= kCTFontCondensedTrait;
	}
	return symbolic;
}

/* **THE WEIGHT IS THE ERA'S 0…15 AND THE ENGINE'S IS -1…1**, with 5 standing for regular and 9 for bold — Apple's own
 * two landmarks. A face with no weight trait falls back to its bold bit, which is the only other thing it says about
 * weight. The inverse is the affine map the same two landmarks imply. */
/* **THE TWO LANDMARKS ARE THE MAPPING.** The engine's normalised weight puts 0.0 at OS/2's `usWeightClass` 400 (regular)
 * and 0.6 at 700 (bold); the era's scale puts 5 at regular and 9 at bold. So the map is the line through those two
 * points, clamped — which makes 100 (thin) land at 0 and 900 (black) at 12, both inside the era's 0…15 word.
 * A face that states no weight falls back to its bold bit, the only other thing it says about weight. */
static NSInteger fn_weightFromNormalized(double normalized, BOOL bold)
{
	double weight = 5.0 + normalized * (4.0 / 0.6);

	if (weight < 0.0) {
		weight = 0.0;
	}
	if (weight > 15.0) {
		weight = 15.0;
	}
	if (normalized == 0.0) {
		/* A NORMALISED ZERO IS REGULAR, AND THE BOLD BIT IS THE TIE-BREAK — one point on the engine's scale means both
		 * "regular" and "no weight stated", so the symbolic bit decides which. */
		return bold ? 9 : 5;
	}
	return (NSInteger)llround(weight);
}

/* **THE TRAITS AND THE WEIGHT COME FROM THE FACE'S OWN TABLES, NOT FROM ITS DESCRIPTOR.** MEASURED, and it is the
 * reason this is a CTFont read rather than a dictionary lookup: the descriptors this tree's matcher returns carry
 * exactly three facts — URL, PostScript name and family — so `kCTFontTraitsAttribute` is ALWAYS absent from them, and a
 * reader that trusted it would report every face on the machine as regular. `CTFontGetSymbolicTraits` reads the OS/2
 * and `head` tables and `CTFontCopyTraits` computes the normalised weight from `usWeightClass`, so the face knows what
 * its descriptor does not. */
static NSArray *fn_faceInfo(NSString *postScriptName)
{
	CTFontRef font;
	CTFontSymbolicTraits symbolic = 0;
	CFDictionaryRef traits;
	double normalized = 0.0;
	BOOL hasWeight = NO;
	BOOL bold;

	if (postScriptName == nil) {
		return [NSArray arrayWithObjects:[NSNumber numberWithInteger:5], [NSNumber numberWithUnsignedInteger:0], nil];
	}
	font = CTFontCreateWithName((CFStringRef)postScriptName, 12.0, NULL);
	if (font == NULL) {
		return [NSArray arrayWithObjects:[NSNumber numberWithInteger:5], [NSNumber numberWithUnsignedInteger:0], nil];
	}
	symbolic = CTFontGetSymbolicTraits(font);
	traits = CTFontCopyTraits(font);
	if (traits != NULL) {
		CFNumberRef weight = (CFNumberRef)CFDictionaryGetValue(traits, kCTFontWeightTrait);

		if (weight != NULL) {
			hasWeight = CFNumberGetValue(weight, kCFNumberDoubleType, &normalized);
		}
		CFRelease(traits);
	}
	CFRelease(font);
	bold = (symbolic & kCTFontBoldTrait) != 0;
	return [NSArray arrayWithObjects:
		[NSNumber numberWithInteger:(hasWeight ? fn_weightFromNormalized(normalized, bold) : (bold ? 9 : 5))],
		[NSNumber numberWithUnsignedInteger:fn_traitsFromSymbolic(symbolic,
			(symbolic & kCTFontMonoSpaceTrait) != 0)],
		nil];
}

/* ============================================================================================ *
 * THE PRIVATE DOORS.                                                                            *
 * ============================================================================================ */

@interface NSFontManager ()
- (NSArray *)fn_allDescriptors;
- (NSArray *)fn_memberRowsForFamily:(NSString *)family;
- (NSArray *)fn_faceInfoForName:(nullable NSString *)postScriptName;
- (nullable NSFont *)fn_bestMemberOfFamily:(NSString *)family traits:(NSFontTraitMask)wanted
				    weight:(NSInteger)weight size:(CGFloat)size avoid:(NSFontTraitMask)avoid;
- (nullable NSFont *)fn_fontForPostScriptName:(nullable NSString *)name size:(CGFloat)size;
- (void)fn_noteAction:(NSFontAction)action trait:(NSFontTraitMask)trait;
- (NSString *)fn_faceNameOfFont:(NSFont *)font;
- (nullable NSFont *)fn_fontOfFamily:(nullable NSString *)family weight:(NSInteger)weight
				size:(CGFloat)size like:(NSFont *)like;
@end

@implementation NSFontManager

/* ============================================================================================ *
 * THE SINGLETON.                                                                                *
 * ============================================================================================ */

+ (NSFontManager *)sharedFontManager
{
	if (s_sharedFontManager == nil) {
		Class factory = (s_managerFactory != Nil) ? s_managerFactory : [NSFontManager class];

		s_sharedFontManager = [[factory alloc] init];
	}
	return s_sharedFontManager;
}

+ (void)setFontManagerFactory:(Class)factory
{
	/* **A FACTORY SET AFTER THE SHARED MANAGER EXISTS IS RECORDED AND NOT APPLIED**, which is Apple's rule by
	 * consequence rather than by sentence: swapping the live singleton would leave every target holding the old one. */
	s_managerFactory = factory;
}

+ (void)setFontPanelFactory:(Class)factory
{
	/* **THE PANEL'S OWN CLASS DOOR IS WHAT THIS REACHES**, because the shared panel is created by `+sharedFontPanel`
	 * on `NSFontPanel` — a copy of the factory kept here would be a second answer to one question. */
	[NSFontPanel setSharedPanelFactory:factory];
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_enabled = YES;
		_currentFontAction = NSNoFontChangeAction;
		_collections = [[NSMutableDictionary alloc] init];
		_collectionOptions = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_selectedFont release];
	[_selectedAttributes release];
	[_fontMenu release];
	[_allDescriptors release];
	[_faceInfo release];
	[_collections release];
	[_collectionOptions release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE ENUMERATION.                                                                              *
 * ============================================================================================ */

- (NSArray *)fn_allDescriptors
{
	CTFontCollectionRef collection;
	CFArrayRef matches;
	NSMutableArray *wrapped;
	CFIndex i;

	if (_allDescriptors != nil) {
		return _allDescriptors;
	}
	collection = CTFontCollectionCreateFromAvailableFonts(NULL);
	matches = (collection != NULL) ? CTFontCollectionCreateMatchingFontDescriptors(collection) : NULL;
	if (collection != NULL) {
		CFRelease(collection);
	}
	wrapped = [NSMutableArray array];
	for (i = 0; matches != NULL && i < CFArrayGetCount(matches); i++) {
		CTFontDescriptorRef descriptor = (CTFontDescriptorRef)CFArrayGetValueAtIndex(matches, i);
		NSDictionary *attributes = (NSDictionary *)CTFontDescriptorCopyAttributes(descriptor);
		NSFontDescriptor *wrapper = [NSFontDescriptor fontDescriptorWithFontAttributes:attributes];

		[attributes release];
		if (wrapper != nil) {
			[wrapped addObject:wrapper];
		}
	}
	if (matches != NULL) {
		CFRelease(matches);
	}
	_allDescriptors = [wrapped copy];
	return _allDescriptors;
}

- (NSArray *)availableFonts
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *descriptors = [self fn_allDescriptors];
	NSUInteger i;

	for (i = 0; i < [descriptors count]; i++) {
		NSString *name = [[descriptors objectAtIndex:i] postscriptName];

		if (name != nil && ![names containsObject:name]) {
			[names addObject:name];
		}
	}
	return names;
}

- (NSArray *)availableFontFamilies
{
	NSMutableArray *families = [NSMutableArray array];
	NSArray *descriptors = [self fn_allDescriptors];
	NSUInteger i;

	for (i = 0; i < [descriptors count]; i++) {
		NSString *family = [[descriptors objectAtIndex:i] objectForKey:(NSString *)kCTFontFamilyNameAttribute];

		if ([family isKindOfClass:[NSString class]] && ![families containsObject:family]) {
			[families addObject:family];
		}
	}
	return families;
}

/* **A MEMBER ROW IS APPLE'S FOUR FIELDS**: `[fontName, faceName, weight, traits]`, in that order, which is what
 * `-availableMembersOfFontFamily:` documents and what a family menu is built from. The face name is the style name
 * where the engine has one and the PostScript name otherwise. */
- (NSArray *)fn_faceInfoForName:(NSString *)postScriptName
{
	NSArray *info;

	if (postScriptName == nil) {
		return fn_faceInfo(nil);
	}
	if (_faceInfo == nil) {
		_faceInfo = [[NSMutableDictionary alloc] init];
	}
	info = [_faceInfo objectForKey:postScriptName];
	if (info == nil) {
		info = fn_faceInfo(postScriptName);
		[_faceInfo setObject:info forKey:postScriptName];
	}
	return info;
}

- (NSArray *)fn_memberRowsForFamily:(NSString *)family
{
	NSMutableArray *rows = [NSMutableArray array];
	NSArray *descriptors = [self fn_allDescriptors];
	NSUInteger i;

	if (family == nil) {
		return rows;
	}
	for (i = 0; i < [descriptors count]; i++) {
		NSFontDescriptor *descriptor = [descriptors objectAtIndex:i];
		NSString *name = [descriptor postscriptName];
		NSString *familyName = [descriptor objectForKey:(NSString *)kCTFontFamilyNameAttribute];
		NSString *style;

		if (![familyName isEqual:family] || name == nil) {
			continue;
		}
		style = [descriptor objectForKey:(NSString *)kCTFontStyleNameAttribute];
		if (![style isKindOfClass:[NSString class]] || [style length] == 0) {
			style = name;
		}
		{
			NSArray *info = [self fn_faceInfoForName:name];

			[rows addObject:[NSArray arrayWithObjects:name, style,
				[info objectAtIndex:0], [info objectAtIndex:1], nil]];
		}
	}
	return rows;
}

- (NSArray *)availableMembersOfFontFamily:(NSString *)family
{
	return [self fn_memberRowsForFamily:family];
}

- (NSArray *)availableFontNamesWithTraits:(NSFontTraitMask)mask
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *fonts = [self availableFonts];
	NSUInteger i;

	for (i = 0; i < [fonts count]; i++) {
		NSString *name = [fonts objectAtIndex:i];

		if ([self fontNamed:name hasTraits:mask]) {
			[names addObject:name];
		}
	}
	return names;
}

- (NSArray *)availableFontNamesMatchingFontDescriptor:(NSFontDescriptor *)descriptor
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *matches;
	NSUInteger i;

	if (descriptor == nil) {
		return names;
	}
	matches = [descriptor matchingFontDescriptorsWithMandatoryKeys:nil];
	for (i = 0; i < [matches count]; i++) {
		NSString *name = [[matches objectAtIndex:i] postscriptName];

		if (name != nil) {
			[names addObject:name];
		}
	}
	return names;
}

/* ============================================================================================ *
 * ONE FONT'S TRAITS AND WEIGHT.                                                                 *
 * ============================================================================================ */

- (NSFontTraitMask)traitsOfFont:(NSFont *)font
{
	if (font == nil) {
		return 0;
	}
	return (NSFontTraitMask)[(NSNumber *)[[self fn_faceInfoForName:[font fontName]] objectAtIndex:1]
				  unsignedIntegerValue];
}

- (NSInteger)weightOfFont:(NSFont *)font
{
	if (font == nil) {
		return 5;
	}
	return [(NSNumber *)[[self fn_faceInfoForName:[font fontName]] objectAtIndex:0] integerValue];
}

- (BOOL)fontNamed:(NSString *)fontName hasTraits:(NSFontTraitMask)mask
{
	NSFont *font;
	NSFontTraitMask traits;

	if (fontName == nil) {
		return NO;
	}
	/* THE "UN-" BITS ARE THE REMOVE SPELLINGS RATHER THAN PROPERTIES, so they are removed from the QUESTION: asking
	 * whether a font "is not bold" is not a property any face has. */
	mask &= ~(NSUnboldFontMask | NSUnitalicFontMask);
	font = [NSFont fontWithName:fontName size:12.0];
	if (font == nil) {
		return NO;
	}
	traits = [self traitsOfFont:font];
	return (traits & mask) == mask;
}

/* THE MEMBER MATCH, WHICH IS THE ONE PLACE A FAMILY IS SEARCHED. `avoid` is the trait a removal asks the result not to
 * have; `wanted` must be present; the weight's distance decides between the members that qualify. */
- (NSFont *)fn_bestMemberOfFamily:(NSString *)family traits:(NSFontTraitMask)wanted
			   weight:(NSInteger)weight size:(CGFloat)size avoid:(NSFontTraitMask)avoid
{
	NSArray *rows = [self fn_memberRowsForFamily:family];
	NSString *best = nil;
	NSInteger bestDistance = 0;
	NSUInteger i;

	wanted &= ~(NSUnboldFontMask | NSUnitalicFontMask);
	avoid &= ~(NSUnboldFontMask | NSUnitalicFontMask);
	for (i = 0; i < [rows count]; i++) {
		NSArray *row = [rows objectAtIndex:i];
		NSFontTraitMask traits = (NSFontTraitMask)[(NSNumber *)[row objectAtIndex:3] unsignedIntegerValue];
		NSInteger memberWeight = [(NSNumber *)[row objectAtIndex:2] integerValue];
		NSInteger distance = labs(memberWeight - weight);

		if ((traits & wanted) != wanted || (traits & avoid) != 0) {
			continue;
		}
		if (best == nil || distance < bestDistance) {
			best = [row objectAtIndex:0];
			bestDistance = distance;
		}
	}
	return [self fn_fontForPostScriptName:best size:size];
}

- (NSFont *)fn_fontForPostScriptName:(NSString *)name size:(CGFloat)size
{
	if (name == nil) {
		return nil;
	}
	return [NSFont fontWithName:name size:(size > 0.0 ? size : [NSFont systemFontSize])];
}

- (NSFont *)fontWithFamily:(NSString *)family traits:(NSFontTraitMask)mask
		     weight:(NSInteger)weight size:(CGFloat)size
{
	NSFont *member = [self fn_bestMemberOfFamily:family traits:mask weight:weight size:size avoid:0];

	if (member != nil) {
		return member;
	}
	/* **A NAME THAT IS NOT A FAMILY MAY STILL BE A FACE**, which is how Apple's own door is worded ("the family name
	 * or, if the family has only one member, the font name"); the fallback is the name itself. */
	return [self fn_fontForPostScriptName:family size:size];
}

/* ============================================================================================ *
 * THE CONVERSIONS.                                                                              *
 * ============================================================================================ */

- (void)fn_noteAction:(NSFontAction)action trait:(NSFontTraitMask)trait
{
	_currentFontAction = action;
	_pendingTrait = trait;
}

- (NSFont *)convertFont:(NSFont *)font toSize:(CGFloat)size
{
	if (font == nil || size <= 0.0) {
		return font;
	}
	return [font fontWithSize:size];
}

- (NSFont *)convertFont:(NSFont *)font toFamily:(NSString *)family
{
	NSFontTraitMask traits;
	NSInteger weight;
	NSFont *converted;

	if (font == nil || family == nil) {
		return font;
	}
	/* THE SOURCE FONT'S EMPHASIS IS KEPT: "convert to this family" means the same weight, the same slant, a different
	 * typeface — not a reset to regular. */
	traits = [self traitsOfFont:font] & (NSItalicFontMask | NSBoldFontMask | NSExpandedFontMask | NSCondensedFontMask);
	weight = [self weightOfFont:font];
	converted = [self fn_bestMemberOfFamily:family traits:traits weight:weight size:[font pointSize] avoid:0];
	return (converted != nil) ? converted : font;
}

- (NSFont *)convertFont:(NSFont *)font toFace:(NSString *)face
{
	NSString *family;
	NSArray *rows;
	NSUInteger i;

	if (font == nil || face == nil) {
		return font;
	}
	family = [font familyName];
	rows = [self fn_memberRowsForFamily:family];
	for (i = 0; i < [rows count]; i++) {
		NSArray *row = [rows objectAtIndex:i];
		NSString *name = [row objectAtIndex:0];
		NSString *style = [row objectAtIndex:1];

		/* THE FACE MAY BE SPELLED EITHER WAY — a style name or a PostScript name — and both are compared without case,
		 * because a menu's title and the face a caller passes come from different places. */
		if ([style caseInsensitiveCompare:face] == NSOrderedSame
		    || [name caseInsensitiveCompare:face] == NSOrderedSame) {
			return [self fn_fontForPostScriptName:name size:[font pointSize]];
		}
	}
	/* AND A FULL FACE NAME FROM ANOTHER FAMILY IS STILL A NAME**: Core Text resolves it or it does not, and a font
	 * that does not resolve leaves the input alone rather than becoming a nil a caller would have to test for. */
	{
		NSFont *named = [self fn_fontForPostScriptName:face size:[font pointSize]];

		return (named != nil) ? named : font;
	}
}

- (NSFont *)convertFont:(NSFont *)font toHaveTrait:(NSFontTraitMask)trait
{
	NSFontTraitMask wanted;
	NSFontTraitMask current;
	NSFont *converted;

	if (font == nil) {
		return nil;
	}
	wanted = trait & ~(NSUnboldFontMask | NSUnitalicFontMask);
	current = [self traitsOfFont:font];
	converted = [self fn_bestMemberOfFamily:[font familyName] traits:(current | wanted)
					 weight:[self weightOfFont:font] + (((wanted & NSBoldFontMask) != 0) ? 1 : 0)
					   size:[font pointSize] avoid:0];
	return (converted != nil) ? converted : font;
}

- (NSFont *)convertFont:(NSFont *)font toNotHaveTrait:(NSFontTraitMask)trait
{
	NSFontTraitMask avoid;
	NSFont *converted;

	if (font == nil) {
		return nil;
	}
	/** A REMOVAL IS SPELLED EITHER WAY: the era's menu carries `NSUnboldFontMask`/`NSUnitalicFontMask`, and a caller
	 * passing the positive bit means the same thing when the door is NAMED "not have". */
	avoid = trait & (NSItalicFontMask | NSBoldFontMask | NSExpandedFontMask | NSCondensedFontMask);
	if ((trait & NSUnboldFontMask) != 0) {
		avoid |= NSBoldFontMask;
	}
	if ((trait & NSUnitalicFontMask) != 0) {
		avoid |= NSItalicFontMask;
	}
	converted = [self fn_bestMemberOfFamily:[font familyName] traits:0
					 weight:[self weightOfFont:font] - (((avoid & NSBoldFontMask) != 0) ? 1 : 0)
					   size:[font pointSize] avoid:avoid];
	return (converted != nil) ? converted : font;
}

/* **AND THE DOOR WITH NO ARGUMENT, WHICH IS WHAT A `-changeFont:` HANDLER CALLS BACK THROUGH.** The recorded action
 * decides: the panel's choice, a trait added or removed, a size step, or a weight step. `NSNoFontChangeAction` returns
 * the font unchanged, which is the honest answer for "nothing was asked". */
- (NSFont *)convertFont:(NSFont *)font
{
	NSFont *selected;
	NSString *family;
	CGFloat size;

	if (font == nil) {
		return nil;
	}
	switch (_currentFontAction) {
	case NSNoFontChangeAction:
		return font;
	case NSViaPanelFontAction:
		selected = _selectedFont;
		if (selected == nil) {
			return font;
		}
		family = [selected familyName];
		{
			NSFont *inFamily = [self convertFont:font toFamily:family];
			NSFont *inFace = [self convertFont:inFamily toFace:[self fn_faceNameOfFont:selected]];

			return (inFace != nil) ? inFace : font;
		}
	case NSAddTraitFontAction:
		return [self convertFont:font toHaveTrait:_pendingTrait];
	case NSRemoveTraitFontAction:
		return [self convertFont:font toNotHaveTrait:_pendingTrait];
	case NSSizeUpFontAction:
	case NSSizeDownFontAction:
		size = [font pointSize] + ((_currentFontAction == NSSizeUpFontAction) ? 1.0 : -1.0);
		return [self convertFont:font toSize:(size > 1.0 ? size : 1.0)];
	case NSHeavierFontAction:
	case NSLighterFontAction:
		return [self fn_fontOfFamily:[font familyName] weight:[self weightOfFont:font]
					       + ((_currentFontAction == NSHeavierFontAction) ? 1 : -1)
					size:[font pointSize] like:font];
	}
	return font;
}

- (NSFont *)fn_fontOfFamily:(NSString *)family weight:(NSInteger)weight size:(CGFloat)size like:(NSFont *)like
{
	NSFontTraitMask traits = [self traitsOfFont:like] & (NSItalicFontMask | NSExpandedFontMask | NSCondensedFontMask);
	NSFont *converted;

	if (weight < 0) {
		weight = 0;
	}
	if (weight > 15) {
		weight = 15;
	}
	converted = [self fn_bestMemberOfFamily:family traits:traits weight:weight size:size avoid:0];
	return (converted != nil) ? converted : like;
}

- (NSString *)fn_faceNameOfFont:(NSFont *)font
{
	NSString *name = [font fontName];
	NSArray *rows = [self fn_memberRowsForFamily:[font familyName]];
	NSUInteger i;

	for (i = 0; i < [rows count]; i++) {
		NSArray *row = [rows objectAtIndex:i];

		if ([[row objectAtIndex:0] isEqual:name]) {
			return [row objectAtIndex:1];
		}
	}
	return name;
}

- (NSFontTraitMask)convertFontTraits:(NSFontTraitMask)traits
{
	/* **THE MASK'S PROJECTION ONTO WHAT THE ENGINE CAN REPRESENT.** Every bit is carried through the engine's symbolic
	 * vocabulary and back, so a mask with no engine-side counterpart comes back without it — which is the truthful
	 * answer to "convert these traits" in a tier whose faces have no small-caps bit. */
	return fn_traitsFromSymbolic(fn_symbolicFromTraits(traits), (traits & NSFixedPitchFontMask) != 0);
}

- (NSInteger)convertWeight:(BOOL)upFlag ofFont:(NSFont *)font
{
	NSInteger weight = [self weightOfFont:font] + (upFlag ? 1 : -1);

	if (weight < 0) {
		weight = 0;
	}
	if (weight > 15) {
		weight = 15;
	}
	return weight;
}

- (NSDictionary *)convertAttributes:(NSDictionary *)attributes
{
	NSMutableDictionary *converted;
	id font;

	if (attributes == nil) {
		return nil;
	}
	converted = [NSMutableDictionary dictionaryWithDictionary:attributes];
	font = [attributes objectForKey:NSFontAttributeName];
	if (font != nil && [font isKindOfClass:[NSFont class]]) {
		[converted setObject:[self convertFont:(NSFont *)font] forKey:NSFontAttributeName];
	}
	return converted;
}

/* ============================================================================================ *
 * THE ACTION.                                                                                   *
 * ============================================================================================ */

- (void)setSelectedFont:(NSFont *)fontObj isMultiple:(BOOL)flag
{
	NSFont *old = _selectedFont;

	_selectedFont = [fontObj retain];
	[old release];
	_multiple = flag ? YES : NO;
}

- (NSFont *)selectedFont
{
	return _selectedFont;
}

- (void)setSelectedAttributes:(NSDictionary *)attributes isMultiple:(BOOL)flag
{
	NSDictionary *old = _selectedAttributes;
	id font;

	_selectedAttributes = [attributes retain];
	[old release];
	_multiple = flag ? YES : NO;
	font = [attributes objectForKey:NSFontAttributeName];
	if (font != nil && [font isKindOfClass:[NSFont class]]) {
		[self setSelectedFont:(NSFont *)font isMultiple:flag];
	}
}

- (BOOL)isMultiple
{
	return _multiple;
}

- (void)modifyFont:(id)sender
{
	/* **A FAMILY MENU ITEM CARRIES ITS INDEX AS THE TAG**, and this is the door that reads it: the built menu's items
	 * target the manager with this action, so a click has to become a selected font before the change is sent. */
	if (sender != nil && [sender respondsToSelector:@selector(tag)]) {
		NSArray *families = [self availableFontFamilies];
		NSInteger tag = [sender tag];

		if (tag >= 0 && tag < (NSInteger)[families count]) {
			CGFloat size = (_selectedFont != nil) ? [_selectedFont pointSize] : [NSFont systemFontSize];

			[self setSelectedFont:[self fontWithFamily:[families objectAtIndex:(NSUInteger)tag]
							   traits:0 weight:5 size:size]
				   isMultiple:NO];
		}
	}
	[self fn_noteAction:NSViaPanelFontAction trait:0];
	[self sendAction];
}

- (void)modifyFontViaPanel:(id)sender
{
	(void)sender;
	[self fn_noteAction:NSViaPanelFontAction trait:0];
	[self sendAction];
}

- (void)addFontTrait:(id)sender
{
	NSFontTraitMask trait = NSBoldFontMask;

	if (sender != nil && [sender respondsToSelector:@selector(tag)]) {
		NSInteger tag = [sender tag];

		if (tag != 0) {
			trait = (NSFontTraitMask)tag;
		}
	}
	[self fn_noteAction:NSAddTraitFontAction trait:trait];
	[self sendAction];
}

- (void)removeFontTrait:(id)sender
{
	NSFontTraitMask trait = NSBoldFontMask;

	if (sender != nil && [sender respondsToSelector:@selector(tag)]) {
		NSInteger tag = [sender tag];

		if (tag != 0) {
			trait = (NSFontTraitMask)tag;
		}
	}
	[self fn_noteAction:NSRemoveTraitFontAction trait:trait];
	[self sendAction];
}

- (void)sendAction
{
	SEL action = (_action != NULL) ? _action : @selector(changeFont:);

	if (!_enabled) {
		return;
	}
	[[NSApplication sharedApplication] sendAction:action to:_target from:self];
}

- (NSFontAction)currentFontAction
{
	return _currentFontAction;
}

- (void)setTarget:(id)aTarget
{
	_target = aTarget;
}

- (id)target
{
	return _target;
}

- (void)setAction:(SEL)aSelector
{
	_action = aSelector;
}

- (SEL)action
{
	return _action;
}

- (void)setDelegate:(id)anObject
{
	_delegate = anObject;
}

- (id)delegate
{
	return _delegate;
}

- (void)setEnabled:(BOOL)flag
{
	_enabled = flag ? YES : NO;
}

- (BOOL)isEnabled
{
	return _enabled;
}

/* ============================================================================================ *
 * THE FONT MENU AND THE PANEL.                                                                  *
 * ============================================================================================ */

- (NSMenu *)fontMenu:(BOOL)create
{
	NSArray *families;
	NSUInteger i;

	if (_fontMenu != nil) {
		return _fontMenu;
	}
	if (!create) {
		return nil;
	}
	_fontMenu = [[NSMenu alloc] initWithTitle:@"Font"];
	families = [self availableFontFamilies];
	for (i = 0; i < [families count]; i++) {
		NSString *family = [families objectAtIndex:i];
		NSMenuItem *item;

		/* **THE DELEGATE DECLINES A FAMILY BY NAME, WHICH IS THE ERA'S ONE DELEGATE DOOR**, and it is why the
		 * delegate is not a stored bit. */
		if (_delegate != nil && [_delegate respondsToSelector:@selector(fontManager:willIncludeFont:)]
		    && ![_delegate fontManager:self willIncludeFont:family]) {
			continue;
		}
		item = [[NSMenuItem alloc] initWithTitle:family action:@selector(modifyFont:) keyEquivalent:@""];
		[item setTarget:self];
		[item setTag:(NSInteger)i];
		[_fontMenu addItem:item];
		[item release];
	}
	return _fontMenu;
}

- (void)setFontMenu:(NSMenu *)newMenu
{
	NSMenu *old = _fontMenu;

	_fontMenu = [newMenu retain];
	[old release];
}

- (void)orderFrontFontPanel:(id)sender
{
	NSFontPanel *panel = [self fontPanel:YES];

	[panel setPanelFont:(_selectedFont != nil ? _selectedFont : [NSFont systemFontOfSize:[NSFont systemFontSize]])
		 isMultiple:_multiple];
	[panel orderFront:sender];
}

- (void)orderFrontStylesPanel:(id)sender
{
	(void)sender;
	fn_refuse_window("-orderFrontStylesPanel:",
			 "the era's styles panel, a separate window this tier has not built; the font panel's family and "
			 "size lists are the font choice that exists");
}

- (NSFontPanel *)fontPanel:(BOOL)create
{
	if (create) {
		return [NSFontPanel sharedFontPanel];
	}
	return [NSFontPanel sharedFontPanelExists] ? [NSFontPanel sharedFontPanel] : nil;
}

- (NSString *)localizedNameForFamily:(NSString *)family face:(NSString *)face
{
	NSArray *rows;
	NSUInteger i;

	if (face == nil) {
		return family;
	}
	rows = [self fn_memberRowsForFamily:family];
	for (i = 0; i < [rows count]; i++) {
		NSArray *row = [rows objectAtIndex:i];

		if ([[row objectAtIndex:0] isEqual:face] || [[row objectAtIndex:1] isEqual:face]) {
			return [row objectAtIndex:1];
		}
	}
	return face;
}

/* ============================================================================================ *
 * THE COLLECTIONS.                                                                              *
 * ============================================================================================ */

- (NSArray *)collectionNames
{
	return [[_collections allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)addCollection:(NSString *)collectionName options:(NSUInteger)options
{
	if (collectionName == nil) {
		return;
	}
	if ([_collections objectForKey:collectionName] == nil) {
		[_collections setObject:[NSMutableArray array] forKey:collectionName];
	}
	/* **THE OPTION IS RECORDED AND NOT OBEYED**: it is a visibility flag for a collection browser this tier has not
	 * built, and the header says so rather than this comment hiding it. */
	[_collectionOptions setObject:[NSNumber numberWithUnsignedInteger:options] forKey:collectionName];
}

- (void)removeCollection:(NSString *)collectionName
{
	if (collectionName == nil) {
		return;
	}
	[_collections removeObjectForKey:collectionName];
	[_collectionOptions removeObjectForKey:collectionName];
}

- (NSArray *)fontDescriptorsInCollection:(NSString *)collectionName
{
	NSArray *descriptors;

	if (collectionName == nil) {
		return nil;
	}
	descriptors = [_collections objectForKey:collectionName];
	return (descriptors != nil) ? [NSArray arrayWithArray:descriptors] : nil;
}

- (void)addFontDescriptors:(NSArray *)descriptors toCollection:(NSString *)collectionName
{
	NSMutableArray *collection;
	NSUInteger i;

	if (collectionName == nil || descriptors == nil) {
		return;
	}
	collection = [_collections objectForKey:collectionName];
	if (collection == nil) {
		collection = [NSMutableArray array];
		[_collections setObject:collection forKey:collectionName];
	}
	for (i = 0; i < [descriptors count]; i++) {
		id descriptor = [descriptors objectAtIndex:i];

		if (![collection containsObject:descriptor]) {
			[collection addObject:descriptor];
		}
	}
}

- (void)removeFontDescriptor:(NSFontDescriptor *)descriptor fromCollection:(NSString *)collectionName
{
	NSMutableArray *collection;

	if (descriptor == nil || collectionName == nil) {
		return;
	}
	collection = [_collections objectForKey:collectionName];
	[collection removeObject:descriptor];
}

@end
