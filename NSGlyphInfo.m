/*
 * NSGlyphInfo — a glyph named by something other than its index.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The three factories store the three facts; the name factory also RESOLVES through the engine, so a name that the font
 * does not have answers nil rather than a glyph info that names nothing.
 */
#import "NSGlyphInfo.h"
#import "NSFont.h"
#import "AppKitRefusal.h"

#import <CoreText/CTFont.h>

@implementation NSGlyphInfo

- (void)dealloc
{
	[_glyphName release];
	[_baseString release];
	[super dealloc];
}

/* **THE NAME FACTORY RESOLVES, WHICH IS THE ONE PIECE OF REAL WORK HERE.** `CTFontGetGlyphWithName` answers 0 (`.notdef`) for
 * a name the face has not got, and a glyph info naming `.notdef` is a wrong answer dressed as one — so a name that does not
 * resolve answers nil and says why. */
+ (NSGlyphInfo *)glyphInfoWithGlyphName:(NSString *)glyphName forFont:(NSFont *)font
			     baseString:(NSString *)theString
{
	NSGlyphInfo *info;
	CGGlyph glyph;

	if (theString == nil) {
		return nil;
	}
	if (glyphName == nil || font == nil) {
		fn_refuse_window("+NSGlyphInfo glyphInfoWithGlyphName:forFont:baseString:",
				 "a glyph name and a font; one of them is missing");
		return nil;
	}
	/* **THE SUBSTRATE IS THE FONT'S OWN PRIVATE `CTFontRef`**, which this header exposes `@public` for exactly this kind of
	 * library-internal use (the manager reads it the same way). There is no `-cgFont` door in this tier's `NSFont`, and a
	 * public one would be a CT type on an AppKit class, which the 10.6 header has not got. */
	glyph = CTFontGetGlyphWithName(font->_font, (CFStringRef)glyphName);
	/* **BOTH "NO GLYPH" ANSWERS ARE REFUSED.** The engine says `.notdef` (0) for a face that maps the name to nothing and
	 * `kCGFontIndexInvalid` (0xFFFF) for a name it has never heard of; either way a glyph info would be naming a glyph that
	 * is not the one asked for. */
	if (glyph == 0 || glyph == (CGGlyph)kCGFontIndexInvalid) {
		fn_refuse_window("+NSGlyphInfo glyphInfoWithGlyphName:forFont:baseString:",
				 "a name the font has a glyph for; this face does not have that glyph");
		return nil;
	}
	info = [[[self alloc] init] autorelease];
	info->_glyphName = [glyphName copy];
	info->_characterIdentifier = (NSUInteger)glyph;
	info->_collection = NSIdentityMappingCharacterCollection;
	info->_baseString = [theString copy];
	return info;
}

/* **THE INDEX FACTORY STORES WHAT IT WAS GIVEN.** The name cannot be recovered here (the engine has no glyph-to-name lookup
 * in this tier), which is the one documented gap; the identifier is the index, so a caller that asks for it gets the number
 * it passed. */
+ (NSGlyphInfo *)glyphInfoWithGlyph:(unsigned int)glyph forFont:(NSFont *)font baseString:(NSString *)theString
{
	NSGlyphInfo *info;

	if (theString == nil) {
		return nil;
	}
	(void)font;	/* the face is not consulted: the index is already a glyph of SOME face */
	info = [[[self alloc] init] autorelease];
	info->_glyphName = nil;
	info->_characterIdentifier = (NSUInteger)glyph;
	info->_collection = NSIdentityMappingCharacterCollection;
	info->_baseString = [theString copy];
	return info;
}

+ (NSGlyphInfo *)glyphInfoWithCharacterIdentifier:(NSUInteger)characterIdentifier
				       collection:(NSCharacterCollection)characterCollection
				       baseString:(NSString *)theString
{
	NSGlyphInfo *info;

	if (theString == nil) {
		return nil;
	}
	info = [[[self alloc] init] autorelease];
	info->_glyphName = nil;
	info->_characterIdentifier = characterIdentifier;
	info->_collection = characterCollection;
	info->_baseString = [theString copy];
	return info;
}

- (NSString *)glyphName
{
	return _glyphName;
}

- (NSCharacterCollection)characterCollection
{
	return _collection;
}

- (NSUInteger)characterIdentifier
{
	return _characterIdentifier;
}

@end
