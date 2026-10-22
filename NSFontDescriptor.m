/*
 * NSFontDescriptor.m — the attributes dictionary, as Core Text holds it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **EVERY DOOR HERE IS ONE OF TWO THINGS**: a `CTFontDescriptorCopy…` read, or a
 * `CTFontDescriptorCreateCopyWithAttributes` write whose attributes are the receiver's with one entry changed.
 * That is Apple's own design — its era object IS a mutable dictionary with derived copies — so Core Text's
 * descriptor and this class are the same shape and no translation layer exists between them.
 *
 * **THE ONE DERIVATION THAT IS MORE THAN ONE ENTRY** is `-fontDescriptorWithSymbolicTraits:`, because Core Text
 * keeps symbolic traits INSIDE its traits dictionary (`kCTFontTraitsAttribute` → `kCTFontSymbolicTrait` →
 * a number), so a trait change is a change to a sub-dictionary rather than to a key. Stated here because a
 * caller comparing attribute dictionaries would otherwise not know why one key's value looks like a dictionary.
 */
#import "NSFontDescriptor.h"
#import "NSFont.h"

#include <CoreText/CTFontDescriptor.h>
/* **THE TRAITS VOCABULARY, WHICH THIS FILE NEEDS AND `CTFontDescriptor.h` DOES NOT BRING**: the
 * symbolic-trait KEY is declared in `CTFontTraits.h` (line 51) with the rest of the trait names, and that
 * header is written to be reached THROUGH `CTFont.h` (it uses `kCTFontClassMaskShift`, which `CTFont.h`
 * declares first) -- so this includes what `NSFont.m` includes rather than the header by itself. */
#include <CoreText/CTFont.h>
#include <string.h>
/* **AND AFTER IT, BECAUSE `CTFontTraits.h` IS WRITTEN TO BE REACHED THROUGH `CTFont.h`**: this file needs the
 * symbolic-trait KEY (an `NSString`, `CTFontTraits.h:51`) and that header uses `kCTFontClassMaskShift`, which
 * `CTFont.h` declares (line 85) along with the trait enum itself. #include order matters here and is measured. */
#include <CoreText/CTFontTraits.h>

/* **THE KEY VALUES.** Apple's era header publishes the NAMES and no literals, so these follow the AppKit's own
 * convention — the name, roughly, as the string — and they are deliberately NOT Core Text's strings (which are
 * `@"CTFontFamilyName"` and friends). See the header for why that matters. */
NSString *NSFontFamilyAttribute = @"NSFontFamily";
NSString *NSFontNameAttribute = @"NSFontName";
NSString *NSFontFaceAttribute = @"NSFontFace";
NSString *NSFontSizeAttribute = @"NSFontSize";
NSString *NSFontVisibleNameAttribute = @"NSFontVisibleName";
NSString *NSFontMatrixAttribute = @"NSFontMatrix";
NSString *NSFontVariationAttribute = @"NSFontVariation";
NSString *NSFontCharacterSetAttribute = @"NSFontCharacterSet";
NSString *NSFontCascadeListAttribute = @"NSFontCascadeList";
NSString *NSFontTraitsAttribute = @"NSFontTraits";
NSString *NSFontFixedAdvanceAttribute = @"NSFontFixedAdvance";
NSString *NSFontFeatureSettingsAttribute = @"NSFontFeatureSettings";
NSString *NSFontColorAttribute = @"NSFontColor";
NSString *NSFontSymbolicTrait = @"NSFontSymbolic";
NSString *NSFontWeightTrait = @"NSFontWeight";
NSString *NSFontWidthTrait = @"NSFontWidth";
NSString *NSFontSlantTrait = @"NSFontSlant";
NSString *NSFontVariationAxisIdentifierKey = @"NSFontVariationAxisIdentifier";
NSString *NSFontVariationAxisMinimumValueKey = @"NSFontVariationAxisMinimumValue";
NSString *NSFontVariationAxisMaximumValueKey = @"NSFontVariationAxisMaximumValue";
NSString *NSFontVariationAxisDefaultValueKey = @"NSFontVariationAxisDefaultValue";
NSString *NSFontVariationAxisNameKey = @"NSFontVariationAxisName";
NSString *NSFontFeatureTypeIdentifierKey = @"NSFontFeatureTypeIdentifier";
NSString *NSFontFeatureSelectorIdentifierKey = @"NSFontFeatureSelectorIdentifier";
NSString *NSFontDescriptorSystemDesignDefault = @"NSFontDescriptorSystemDesignDefault";
NSString *NSFontDescriptorSystemDesignMonospaced = @"NSFontDescriptorSystemDesignMonospaced";
NSString *NSFontDescriptorSystemDesignRounded = @"NSFontDescriptorSystemDesignRounded";
NSString *NSFontDescriptorSystemDesignSerif = @"NSFontDescriptorSystemDesignSerif";

/* **THE BRIDGE: THIS TIER'S KEY TO THE ENGINE'S, AND IT IS A TABLE BECAUSE TWO VOCABULARIES ARE TWO.** The values
 * the engine reads are `kCTFont…` strings (measured, not assumed); the values a caller here writes are the
 * AppKit's. A key the engine already knows passes through untouched, so a caller who speaks Core Text is not
 * translated into something else, and a key NOBODY maps — `NSFontColorAttribute`, whose own era note says Apple
 * deprecated it in favour of `NSForegroundColorAttributeName`, and the four modern `SystemDesign*` values that have
 * no engine counterpart — reaches the engine and is ignored there rather than being silently dropped here. */
static NSString *fn_core_text_key(NSString *appkitKey)
{
	if (appkitKey == nil) {
		return nil;
	}
	if ([appkitKey isEqual:NSFontFamilyAttribute]) {
		return (NSString *)kCTFontFamilyNameAttribute;
	}
	if ([appkitKey isEqual:NSFontNameAttribute]) {
		return (NSString *)kCTFontNameAttribute;
	}
	if ([appkitKey isEqual:NSFontFaceAttribute]) {
		return (NSString *)kCTFontStyleNameAttribute;
	}
	if ([appkitKey isEqual:NSFontSizeAttribute]) {
		return (NSString *)kCTFontSizeAttribute;
	}
	if ([appkitKey isEqual:NSFontVisibleNameAttribute]) {
		return (NSString *)kCTFontDisplayNameAttribute;
	}
	if ([appkitKey isEqual:NSFontMatrixAttribute]) {
		return (NSString *)kCTFontMatrixAttribute;
	}
	if ([appkitKey isEqual:NSFontVariationAttribute]) {
		return (NSString *)kCTFontVariationAttribute;
	}
	if ([appkitKey isEqual:NSFontCharacterSetAttribute]) {
		return (NSString *)kCTFontCharacterSetAttribute;
	}
	if ([appkitKey isEqual:NSFontCascadeListAttribute]) {
		return (NSString *)kCTFontCascadeListAttribute;
	}
	if ([appkitKey isEqual:NSFontTraitsAttribute]) {
		return (NSString *)kCTFontTraitsAttribute;
	}
	if ([appkitKey isEqual:NSFontFixedAdvanceAttribute]) {
		return (NSString *)kCTFontFixedAdvanceAttribute;
	}
	if ([appkitKey isEqual:NSFontFeatureSettingsAttribute]) {
		return (NSString *)kCTFontFeatureSettingsAttribute;
	}
	/* THE TRAITS SUB-KEYS: these live INSIDE the traits dictionary, which is why the translation has two levels. */
	if ([appkitKey isEqual:NSFontSymbolicTrait]) {
		return (NSString *)kCTFontSymbolicTrait;
	}
	if ([appkitKey isEqual:NSFontWeightTrait]) {
		return (NSString *)kCTFontWeightTrait;
	}
	if ([appkitKey isEqual:NSFontWidthTrait]) {
		return (NSString *)kCTFontWidthTrait;
	}
	if ([appkitKey isEqual:NSFontSlantTrait]) {
		return (NSString *)kCTFontSlantTrait;
	}
	if ([appkitKey isEqual:NSFontVariationAxisIdentifierKey]) {
		return (NSString *)kCTFontVariationAxisIdentifierKey;
	}
	if ([appkitKey isEqual:NSFontVariationAxisMinimumValueKey]) {
		return (NSString *)kCTFontVariationAxisMinimumValueKey;
	}
	if ([appkitKey isEqual:NSFontVariationAxisMaximumValueKey]) {
		return (NSString *)kCTFontVariationAxisMaximumValueKey;
	}
	if ([appkitKey isEqual:NSFontVariationAxisDefaultValueKey]) {
		return (NSString *)kCTFontVariationAxisDefaultValueKey;
	}
	if ([appkitKey isEqual:NSFontVariationAxisNameKey]) {
		return (NSString *)kCTFontVariationAxisNameKey;
	}
	if ([appkitKey isEqual:NSFontFeatureTypeIdentifierKey]) {
		return (NSString *)kCTFontFeatureTypeIdentifierKey;
	}
	if ([appkitKey isEqual:NSFontFeatureSelectorIdentifierKey]) {
		return (NSString *)kCTFontFeatureSelectorIdentifierKey;
	}
	return appkitKey;
}

/* AND THE DICTIONARY, WITH THE TRAITS RESOLVED ONE LEVEL IN — because those sub-keys are keys too, and a caller who
 * wrote `NSFontSymbolicTrait` inside `NSFontTraitsAttribute` meant what the engine calls `kCTFontSymbolicTrait`. */
static NSDictionary *fn_core_text_attributes(NSDictionary *appkitAttributes)
{
	NSMutableDictionary *translated;
	NSEnumerator *keys;
	NSString *key;

	if (appkitAttributes == nil) {
		return nil;
	}
	translated = [NSMutableDictionary dictionary];
	keys = [appkitAttributes keyEnumerator];
	while ((key = [keys nextObject]) != nil) {
		id value = [appkitAttributes objectForKey:key];

		if (value == nil) {
			continue;
		}
		if ([key isEqual:NSFontTraitsAttribute] && [value isKindOfClass:[NSDictionary class]]) {
			NSMutableDictionary *traits = [NSMutableDictionary dictionary];
			NSEnumerator *subKeys = [(NSDictionary *)value keyEnumerator];
			NSString *subKey;

			while ((subKey = [subKeys nextObject]) != nil) {
				id subValue = [(NSDictionary *)value objectForKey:subKey];

				if (subValue != nil) {
					[traits setObject:subValue forKey:fn_core_text_key(subKey)];
				}
			}
			value = traits;
		}
		[translated setObject:value forKey:fn_core_text_key(key)];
	}
	return translated;
}

@interface NSFontDescriptor (APKPrivate)
+ (NSFontDescriptor *)apk_descriptorWithCTDescriptor:(CTFontDescriptorRef)ct;
@end

@implementation NSFontDescriptor

/* **`-copy` AND NOT `-copyWithZone:`, BECAUSE THIS TREE HAS NO ZONES** — the rule `NSColor.h` states and this
 * file follows: `NSZone` is deliberately undeclared here and `NSCopying`'s only member is `-copy` (`NSObject.h`
 * states the decision and its copyright). A Cocoa class that spelled `-copyWithZone:` would need a type this
 * tree does not have.
 *
 * AND THE COPY IS A RETAIN, which is what a `NSCopying` VALUE class should do: the attributes dictionary cannot
 * change — every door that would change one answers a NEW descriptor — so an independent copy would be
 * indistinguishable from this object. */
- (id)copy
{
	return [self retain];
}

/* **AND THE ARCHIVE FORM IS THIS TIER'S OWN**, the rule every `NSCoding` class here follows: Apple's own keys are
 * private and unmeasurable, so the round trip is the attributes dictionary under a key this file names. What is
 * NOT this tier's own is the CONFORMANCE — 10.6's header declares `<NSCopying, NSCoding>`, and a conformance
 * without the two methods would be a declaration that lies. */
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:[self fontAttributes] forKey:@"NSFontDescriptorAttributes"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	return [self initWithFontAttributes:[coder decodeObjectForKey:@"NSFontDescriptorAttributes"]];
}

- (void)dealloc
{
	if (_descriptor != NULL) {
		CFRelease(_descriptor);
	}
	[super dealloc];
}

/* THE ONE FACTORY TAKING OWNERSHIP, for the doors that ask Core Text and get a `+1` reference back. */
+ (NSFontDescriptor *)apk_descriptorWithCTDescriptor:(CTFontDescriptorRef)ct
{
	NSFontDescriptor *descriptor;

	if (ct == NULL) {
		return nil;
	}
	descriptor = [[NSFontDescriptor alloc] init];
	if (descriptor == nil) {
		CFRelease(ct);
		return nil;
	}
	descriptor->_descriptor = ct;
	return [descriptor autorelease];
}

- (id)initWithFontAttributes:(NSDictionary *)attributes
{
	CTFontDescriptorRef ct;

	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* THE CALLER'S DICTIONARY IS TRANSLATED ON ITS WAY TO THE ENGINE: see `fn_core_text_attributes`. */
	ct = CTFontDescriptorCreateWithAttributes((CFDictionaryRef)fn_core_text_attributes(attributes));
	if (ct == NULL) {
		[self release];
		return nil;
	}
	_descriptor = ct;
	return self;
}


+ (NSFontDescriptor *)fontDescriptorWithFontAttributes:(NSDictionary *)attributes
{
	return [[[self alloc] initWithFontAttributes:attributes] autorelease];
}

/* **THE NAME AND SIZE PAIR**, which is how `NSFont`'s own class methods ask for a face: Apple's doc calls the
 * first argument the font's name and Core Text carries it as `kCTFontNameAttribute`. **A SIZE OF 0.0 IS NOT
 * PASSED ON AS A SIZE** — Core Text reads an absent `kCTFontSizeAttribute` as "the font's own size", and 0.0 is
 * the value the attribute API uses to say so, so the pair is written exactly as Core Text documents it. */
+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)fontName size:(CGFloat)fontSize
{
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];

	if (fontName == nil) {
		return nil;
	}
	[attributes setObject:fontName forKey:(NSString *)kCTFontNameAttribute];
	[attributes setObject:[NSNumber numberWithDouble:(double)fontSize]
		       forKey:(NSString *)kCTFontSizeAttribute];
	return [self fontDescriptorWithFontAttributes:attributes];
}


- (NSDictionary *)fontAttributes
{
	return [(NSDictionary *)CTFontDescriptorCopyAttributes(_descriptor) autorelease];
}

- (id)objectForKey:(NSString *)anAttribute
{
	if (anAttribute == nil) {
		return nil;
	}
	return [(id)CTFontDescriptorCopyAttribute(_descriptor, (CFStringRef)anAttribute) autorelease];
}

- (NSString *)postscriptName
{
	return [self objectForKey:(NSString *)kCTFontNameAttribute];
}

/* **ZERO IS A REAL ANSWER HERE.** A descriptor built from a name alone has no size attribute, and Apple's own
 * reading of that is "the font's own size" — which is what makes `+fontWithDescriptor:size:`'s 0.0 argument mean
 * "keep the descriptor's", and the probe checks that pair of doors against each other. */
- (CGFloat)pointSize
{
	NSNumber *size = [self objectForKey:(NSString *)kCTFontSizeAttribute];

	return size == nil ? (CGFloat)0.0 : (CGFloat)[size doubleValue];
}

- (NSFontSymbolicTraits)symbolicTraits
{
	NSDictionary *traits = [self objectForKey:(NSString *)kCTFontTraitsAttribute];
	NSNumber *value;

	if (traits == nil) {
		return (NSFontSymbolicTraits)0;
	}
	value = [traits objectForKey:(NSString *)kCTFontSymbolicTrait];
	return value == nil ? (NSFontSymbolicTraits)0 : (NSFontSymbolicTraits)[value unsignedIntValue];
}


/* **"THE NEW ATTRIBUTES TAKE PRECEDENCE"** — Apple's own comment on this door, and it is also the engine every
 * other derivation in this file is built on. `addEntriesFromDictionary:` replaces what it finds and adds what it
 * does not, which is that sentence exactly. */
/* **THE MATRIX'S WIRE SHAPE, MEASURED FROM THE ENGINE AND SAID HERE ONCE.** `kCTFontMatrixAttribute`'s value is an
 * `NSData` holding a `CGAffineTransform`, and `CTFontDescriptor.m` reads it with a length check and a `memcpy` —
 * so the packing below is the inverse of what the engine does, field for field: `NSAffineTransform`'s `m11, m12,
 * m21, m22` are Core Graphics' `a, b, c, d`. */
static NSData *fn_matrix_data(NSAffineTransform *transform)
{
	NSAffineTransformStruct s;
	CGAffineTransform m;

	if (transform == nil) {
		return nil;
	}
	s = [transform transformStruct];
	m.a = s.m11;
	m.b = s.m12;
	m.c = s.m21;
	m.d = s.m22;
	m.tx = s.tX;
	m.ty = s.tY;
	return [NSData dataWithBytes:&m length:sizeof m];
}

+ (NSFontDescriptor *)preferredFontDescriptorForTextStyle:(NSFontTextStyle)style
{
	NSFont *font = [NSFont preferredFontForTextStyle:style];

	return font == nil ? nil : [font fontDescriptor];
}

- (NSFontDescriptor *)fontDescriptorByAddingAttributes:(NSDictionary *)attributes
{
	NSMutableDictionary *merged = [[[self fontAttributes] mutableCopy] autorelease];

	if (merged == nil) {
		return nil;
	}
	if (attributes != nil) {
		[merged addEntriesFromDictionary:attributes];
	}
	return [NSFontDescriptor apk_descriptorWithCTDescriptor:
		CTFontDescriptorCreateCopyWithAttributes(_descriptor, (CFDictionaryRef)fn_core_text_attributes(merged))];
}

- (NSFontDescriptor *)fontDescriptorWithMatrix:(NSAffineTransform *)matrix
{
	NSData *data = fn_matrix_data(matrix);

	if (data == nil) {
		return nil;
	}
	return [self fontDescriptorByAddingAttributes:
		[NSDictionary dictionaryWithObject:data forKey:(NSString *)kCTFontMatrixAttribute]];
}

/* THE CLASS DOOR: a name attribute and a matrix attribute in one descriptor, which is the same composition
 * `-fontDescriptorWithMatrix:` performs on an existing one. A nil name or a nil matrix is nil, as the header states. */
+ (NSFontDescriptor *)fontDescriptorWithName:(NSString *)fontName matrix:(NSAffineTransform *)matrix
{
	NSData *data = fn_matrix_data(matrix);
	NSMutableDictionary *attributes;

	if (fontName == nil || data == nil) {
		return nil;
	}
	attributes = [NSMutableDictionary dictionary];
	[attributes setObject:fontName forKey:(NSString *)kCTFontNameAttribute];
	[attributes setObject:data forKey:(NSString *)kCTFontMatrixAttribute];
	return [self fontDescriptorWithFontAttributes:attributes];
}

- (NSFontDescriptor *)fontDescriptorWithSize:(CGFloat)newPointSize
{
	return [self fontDescriptorByAddingAttributes:
		[NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:(double)newPointSize]
					    forKey:(NSString *)kCTFontSizeAttribute]];
}

/* THE FACE IS CORE TEXT'S STYLE NAME — that mapping is what this door relies on, and it is the one the probe
 * checks. Whether Apple's AppKit literal coincides with Core Text's key string is left to the slice that
 * declares the AppKit constants (see the header). */
/* **THE READ SIDE ANSWERS THE IDENTITY WHEN THERE IS NO MATRIX, WHICH IS WHAT "NO MATRIX" MEANS**: a descriptor
 * built from a name alone carries no matrix attribute, and a caller asking for its matrix wants the transform that
 * leaves the glyphs where they were rather than nil. */
- (NSAffineTransform *)matrix
{
	NSData *data = [self objectForKey:(NSString *)kCTFontMatrixAttribute];
	NSAffineTransform *transform = [[[NSAffineTransform alloc] init] autorelease];
	CGAffineTransform m;
	NSAffineTransformStruct s;

	if (transform == nil) {
		return nil;
	}
	if (data == nil || [data length] < sizeof m) {
		s.m11 = 1.0;
		s.m12 = 0.0;
		s.m21 = 0.0;
		s.m22 = 1.0;
		s.tX = 0.0;
		s.tY = 0.0;
	} else {
		memcpy(&m, [data bytes], sizeof m);
		s.m11 = m.a;
		s.m12 = m.b;
		s.m21 = m.c;
		s.m22 = m.d;
		s.tX = m.tx;
		s.tY = m.ty;
	}
	[transform setTransformStruct:s];
	return transform;
}

- (NSFontDescriptor *)fontDescriptorWithFace:(NSString *)newFace
{
	if (newFace == nil) {
		return nil;
	}
	return [self fontDescriptorByAddingAttributes:
		[NSDictionary dictionaryWithObject:newFace forKey:(NSString *)kCTFontStyleNameAttribute]];
}

- (NSFontDescriptor *)fontDescriptorWithFamily:(NSString *)newFamily
{
	if (newFamily == nil) {
		return nil;
	}
	return [self fontDescriptorByAddingAttributes:
		[NSDictionary dictionaryWithObject:newFamily forKey:(NSString *)kCTFontFamilyNameAttribute]];
}

/* **A TRAIT CHANGE REACHES INTO THE TRAITS SUB-DICTIONARY**, because that is where Core Text keeps the bits —
 * so the receiver's traits are copied, one entry inside them is replaced, and the result goes back under the
 * traits key. A descriptor that had no traits dictionary gets one. */
- (NSFontDescriptor *)fontDescriptorWithSymbolicTraits:(NSFontSymbolicTraits)symbolicTraits
{
	NSMutableDictionary *traits =
		[[[self objectForKey:(NSString *)kCTFontTraitsAttribute] mutableCopy] autorelease];

	if (traits == nil) {
		traits = [NSMutableDictionary dictionary];
	}
	[traits setObject:[NSNumber numberWithUnsignedInt:(unsigned int)symbolicTraits]
		   forKey:(NSString *)kCTFontSymbolicTrait];
	return [self fontDescriptorByAddingAttributes:
		[NSDictionary dictionaryWithObject:traits forKey:(NSString *)kCTFontTraitsAttribute]];
}


- (NSArray *)matchingFontDescriptorsWithMandatoryKeys:(NSSet *)mandatoryKeys
{
	NSArray *matches = (NSArray *)CTFontDescriptorCreateMatchingFontDescriptors(_descriptor, (CFSetRef)mandatoryKeys);
	NSMutableArray *wrapped;
	NSUInteger i;

	if (matches == nil) {
		return nil;
	}
	wrapped = [NSMutableArray arrayWithCapacity:[matches count]];
	for (i = 0; i < [matches count]; i++) {
		/* **THE ELEMENT IS THE ARRAY'S, SO IT IS RETAINED FIRST**: the factory above ADOPTS a `+1` reference,
		 * and handing it one the array owns would release someone else's object when the wrapper died. */
		[wrapped addObject:[NSFontDescriptor apk_descriptorWithCTDescriptor:
			CFRetain((CTFontDescriptorRef)[matches objectAtIndex:i])]];
	}
	[matches release];
	return wrapped;
}

/* **THE SINGULAR DOOR IS THE ARRAY'S FIRST MEMBER, AND THAT IS A STATED DERIVATION.** Core Text's own singular
 * door exists but the plural is the shipped path; answering the same question twice from two engines is how two
 * engines drift. `nil` when nothing matches, which is the array's own empty case. */
- (NSFontDescriptor *)matchingFontDescriptorWithMandatoryKeys:(NSSet *)mandatoryKeys
{
	NSArray *matches = [self matchingFontDescriptorsWithMandatoryKeys:mandatoryKeys];

	return [matches count] == 0 ? nil : [matches objectAtIndex:0];
}

@end
