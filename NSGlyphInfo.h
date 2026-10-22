/*
 * NSGlyphInfo.h — A GLYPH NAMED BY SOMETHING OTHER THAN ITS INDEX.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE ATTRIBUTE THAT SURVIVES A FONT CHANGE.** A run of text is a sequence of characters; a glyph is what a FONT made of
 * them, and the same character is a different glyph in a different face. `NSGlyphInfo` is the era's way to say "this
 * character is THIS glyph" — by name, by index, or by a character identifier in a named collection — so an attribute can
 * survive a substitution or a round trip through a document format that names glyphs rather than characters.
 *
 * **THE THREE FACTORIES ARE THREE KINDS OF NAME FOR THE SAME THING**, and this tier can honour two of them exactly:
 * `+glyphInfoWithGlyphName:forFont:baseString:` turns a name into the font's glyph through `CTFontGetGlyphWithName`, and
 * `+glyphInfoWithCharacterIdentifier:collection:baseString:` stores an identifier and its collection. The third,
 * `+glyphInfoWithGlyph:forFont:baseString:`, takes an index the caller already has; answering its NAME needs a
 * glyph-to-name lookup the engine here has not got, so `-glyphName` answers nil for a glyph made that way — stated at the
 * door rather than approximated.
 *
 * **`NSCharacterCollection` IS THE ERA'S VOCABULARY FOR WHAT AN IDENTIFIER IS AN IDENTIFIER IN.** The identity mapping is
 * Unicode's own; the other five name Adobe's collections, which are the ones a glyph-named document carries.
 */
#ifndef APPKIT_NSGLYPHINFO_H
#define APPKIT_NSGLYPHINFO_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

@class NSFont;

/* **A COLLECTION, IN APPLE'S ORDER AND WITH APPLE'S VALUES.** The identity mapping is zero, which is what makes a glyph
 * info made without saying otherwise mean "the character's own glyph". */
typedef NSUInteger NSCharacterCollection;
enum {
	NSIdentityMappingCharacterCollection = 0,
	NSAdobeCNS1CharacterCollection = 1,
	NSAdobeGB1CharacterCollection = 2,
	NSAdobeJapan1CharacterCollection = 3,
	NSAdobeJapan2CharacterCollection = 4,
	NSAdobeKorea1CharacterCollection = 5
};

@interface NSGlyphInfo : NSObject
{
	NSString *_glyphName;		/* RETAINED; nil when the info was made from an index */
	NSCharacterCollection _collection;
	NSUInteger _characterIdentifier;
	NSString *_baseString;		/* RETAINED: the character this glyph stands for, which is what the attribute applies to */
}

/* **THE THREE WAYS IN.** All three answer nil for a nil base string, because a glyph info with no character to attach to is
 * an attribute that can never apply. */
+ (nullable NSGlyphInfo *)glyphInfoWithGlyphName:(nullable NSString *)glyphName
					 forFont:(nullable NSFont *)font
				      baseString:(nullable NSString *)theString;
+ (nullable NSGlyphInfo *)glyphInfoWithGlyph:(unsigned int)glyph
				     forFont:(nullable NSFont *)font
				  baseString:(nullable NSString *)theString;
+ (nullable NSGlyphInfo *)glyphInfoWithCharacterIdentifier:(NSUInteger)characterIdentifier
						collection:(NSCharacterCollection)characterCollection
						baseString:(nullable NSString *)theString;

/* THE NAME, WHEN THERE IS ONE. See this header's note about the index-made case. */
- (nullable NSString *)glyphName;

/* AND THE IDENTIFIER PAIR, which is what a character-collection glyph info carries. */
- (NSCharacterCollection)characterCollection;
- (NSUInteger)characterIdentifier;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSGLYPHINFO_H */
