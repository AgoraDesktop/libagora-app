/*
 * NSFont.m — the AppKit font object, and it is a VIEW of a Core Text font rather than a second font.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * ONE FACTORY, ONE IVAR, AND NO MEASURING. Every door in this file either asks the substrate (`CTFontGetAscent`,
 * `…CopyCharacterSet`, `…GetBoundingBox`) or names a `CTFontUIFontType` — which is why the file is short: the
 * engine was built first on purpose (`docs/design/coretext-plan.md`), and a second font implementation here is
 * exactly what `dec-7dca575a46b17524` decided against.
 *
 * **AND THE UI FAMILY IS A TABLE RATHER THAN TWELVE DOORS.** §51 shipped Apple's 28 `CTFontUIFontType` names with
 * Apple's values, so each of these class methods is one line naming one of them. Their SIZE is the caller's; this
 * tier has ONE UI font to answer with, which is §M6e's recorded divergence and not an accident of this file.
 */
#import "NSFont.h"
#import "NSFontDescriptor.h"
#import "NSGlyphInfo.h"
#import "NSAttributedString.h"
#import "NSStringDrawing.h"
#import "NSCell.h"	/* the two control sizes the size door maps */
#import "NSGraphicsContext.h"
#import <Foundation/NSAffineTransform.h>
#import "AppKitRefusal.h"
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSCharacterSet.h>
#import <CoreText/CTFont.h>
#import <CoreText/CTLine.h>
#include <math.h>
#include <stdlib.h>

#include <CoreText/CTFont.h>

#include <stdlib.h>

/* **THE STYLE NAMES ARE THIS TIER'S, AND THE CONVENTION IS APPLE'S**: no era artifact fixes these literals (the
 * text-style API is AppKit 11), so they follow the AppKit's habit of naming what they are. */
/* THE WEIGHT AND WIDTH VALUES — see the header for why the ORDER is the part that is checked. */
NSFontWeight NSFontWeightUltraLight = (CGFloat)-0.80;
NSFontWeight NSFontWeightThin = (CGFloat)-0.60;
NSFontWeight NSFontWeightLight = (CGFloat)-0.40;
NSFontWeight NSFontWeightRegular = (CGFloat)0.0;
NSFontWeight NSFontWeightMedium = (CGFloat)0.23;
NSFontWeight NSFontWeightSemibold = (CGFloat)0.30;
NSFontWeight NSFontWeightBold = (CGFloat)0.40;
NSFontWeight NSFontWeightHeavy = (CGFloat)0.56;
NSFontWeight NSFontWeightBlack = (CGFloat)0.62;

NSFontWidth NSFontWidthCompressed = (CGFloat)-0.40;
NSFontWidth NSFontWidthCondensed = (CGFloat)-0.20;
NSFontWidth NSFontWidthStandard = (CGFloat)0.0;
NSFontWidth NSFontWidthExpanded = (CGFloat)0.20;

NSFontTextStyle NSFontTextStyleBody = @"NSFontTextStyleBody";
NSFontTextStyle NSFontTextStyleCallout = @"NSFontTextStyleCallout";
NSFontTextStyle NSFontTextStyleCaption1 = @"NSFontTextStyleCaption1";
NSFontTextStyle NSFontTextStyleCaption2 = @"NSFontTextStyleCaption2";
NSFontTextStyle NSFontTextStyleFootnote = @"NSFontTextStyleFootnote";
NSFontTextStyle NSFontTextStyleHeadline = @"NSFontTextStyleHeadline";
NSFontTextStyle NSFontTextStyleLargeTitle = @"NSFontTextStyleLargeTitle";
NSFontTextStyle NSFontTextStyleSubheadline = @"NSFontTextStyleSubheadline";
NSFontTextStyle NSFontTextStyleTitle1 = @"NSFontTextStyleTitle1";
NSFontTextStyle NSFontTextStyleTitle2 = @"NSFontTextStyleTitle2";
NSFontTextStyle NSFontTextStyleTitle3 = @"NSFontTextStyleTitle3";

/* THE SIZES, IN ONE TABLE, because they are one decision: Apple's scale in points, stated here rather than spread
 * through eleven doors. A style this tier does not know answers the BODY size, which is what "the default style"
 * means and what keeps a caller's typo from drawing nothing. */
static CGFloat fn_text_style_size(NSFontTextStyle style)
{
	if (style == nil) {
		return (CGFloat)13.0;
	}
	if ([style isEqual:NSFontTextStyleLargeTitle]) {
		return (CGFloat)26.0;
	}
	if ([style isEqual:NSFontTextStyleTitle1]) {
		return (CGFloat)22.0;
	}
	if ([style isEqual:NSFontTextStyleTitle2]) {
		return (CGFloat)17.0;
	}
	if ([style isEqual:NSFontTextStyleTitle3]) {
		return (CGFloat)15.0;
	}
	if ([style isEqual:NSFontTextStyleSubheadline]) {
		return (CGFloat)11.0;
	}
	if ([style isEqual:NSFontTextStyleCallout]) {
		return (CGFloat)12.0;
	}
	if ([style isEqual:NSFontTextStyleFootnote]) {
		return (CGFloat)10.0;
	}
	if ([style isEqual:NSFontTextStyleCaption1]) {
		return (CGFloat)10.0;
	}
	if ([style isEqual:NSFontTextStyleCaption2]) {
		return (CGFloat)10.0;
	}
	return (CGFloat)13.0;	/* Body, HEADLINE, and anything a caller invents */
}

@implementation NSFont

/* ============================================================================================
 * ARCHIVING: A FONT IS ITS NAME AND ITS SIZE.
 * ============================================================================================ */

/* **THE CLASS'S STATE IS A `CTFontRef`, WHICH IS A LIVE HANDLE AND NOT AN ARCHIVABLE VALUE — so a font is archived as
 * the two things a design file can actually specify and the two things `+fontWithName:size:` can rebuild it from.** The
 * matrix is not archived: a design that needs a transformed font is a design this format does not express, and saying so
 * here is cheaper than a transformed archive that decodes into the identity. */
static NSString * const AGCoderFontNameKey = @"fontName";
static NSString * const AGCoderFontSizeKey = @"pointSize";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:[self fontName] forKey:AGCoderFontNameKey];
	[aCoder encodeDouble:(double)[self pointSize] forKey:AGCoderFontSizeKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	NSString *name = [aDecoder decodeObjectForKey:AGCoderFontNameKey];
	CGFloat size = (CGFloat)[aDecoder decodeDoubleForKey:AGCoderFontSizeKey];
	NSFont *font = nil;

	if ([name isKindOfClass:[NSString class]]) {
		font = [NSFont fontWithName:name size:size];
	}
	if (font == nil) {
		/* A NAME THIS MACHINE HAS NOT GOT IS THE FONT SYSTEM'S ANSWER RATHER THAN AN ARCHIVE'S FAILURE: a design file
		 * written on one machine is read on another, and `+fontWithName:size:` already substitutes. Answering nil here
		 * would fail the whole nib over a missing typeface. */
		font = [NSFont systemFontOfSize:size];
	}
	return [font retain];
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

- (void)dealloc
{
	/* THE ONE THING THIS CLASS OWNS. `_matrix` is a plain array and needs nothing. */
	if (_font != NULL) {
		CFRelease(_font);
	}
	[super dealloc];
}


/* **TAKE, NOT RETAIN**: every caller below creates a `CTFontRef` (+1) and hands it over, so the wrapper adopts
 * that reference instead of taking a second one — the difference between one release and a leak per font. */
static NSFont *apk_font_take(CTFontRef ct)
{
	NSFont *font;
	CGAffineTransform m;

	if (ct == NULL) {
		return nil;
	}
	font = [[NSFont alloc] init];
	if (font == nil) {
		CFRelease(ct);
		return nil;
	}
	font->_font = ct;
	/* THE MATRIX IS COPIED OUT ONCE, because `-matrix` answers a POINTER (Apple's 10.6 signature) and the
	 * substrate's transform lives in the font object. `CGAffineTransform`'s six values in Apple's own order. */
	m = CTFontGetMatrix(ct);
	font->_matrix[0] = m.a;
	font->_matrix[1] = m.b;
	font->_matrix[2] = m.c;
	font->_matrix[3] = m.d;
	font->_matrix[4] = m.tx;
	font->_matrix[5] = m.ty;
	return [font autorelease];
}

/* AND THE UI FAMILY'S ONE LINE, ONCE. */
/* **ASKING FOR A UI FONT ENUMERATES THE ENTIRE FONT REGISTRY, SO THE ANSWER IS KEPT.** `CTFontCreateUIFontForLanguage`
 * builds its candidate list by WALKING EVERY FONT FILE THE REGISTRY CAN FIND — 118 of them on this host, each
 * opened and read — and `+[NSFont systemFontOfSize:]` has no cache, so a drawing pass that asks once per cell per
 * frame re-reads the whole font directory for every row of every frame.
 *
 * MEASURED, and it is what this fixes: a menu drawing four rows DID NOT FINISH IN TWELVE SECONDS, and the stack
 * was here —
 *
 *     #12 +[NSFont systemFontOfSize:]              libagora-app
 *     #13 -[NSMenuItemCell drawKeyEquivalentWithFrame:inView:]
 *     #11 CTFontCreateUIFontForLanguage            libagora-text
 *     #10 CTFontMatchingCopyAvailableDescriptors
 *     #9  cg_font_enumerate                        libagora-drawing   <- 118 files
 *
 * — under `NSMenuView -drawRect:`, which is to say the "hang" was never a deadlock: it was the font directory
 * being read again and again. THE MAC CACHES UI FONTS FOR THE SAME REASON. A fixed table rather than a dictionary
 * because the key is two scalars and the number of distinct UI faces an application uses is small; a miss after
 * the table fills simply re-measures rather than growing without bound. */
#define APK_UI_FONT_CACHE 16

static struct {
	CTFontUIFontType type;
	CGFloat size;
	NSFont *font;		/* retained by this table for the process's life, which is what a font cache is */
} s_ui_fonts[APK_UI_FONT_CACHE];
static int s_ui_font_count;

static NSFont *apk_ui_font(CTFontUIFontType type, CGFloat size)
{
	int i;

	for (i = 0; i < s_ui_font_count; i++) {
		if (s_ui_fonts[i].type == type && s_ui_fonts[i].size == size) {
			return s_ui_fonts[i].font;
		}
	}
	{
		NSFont *font = apk_font_take(CTFontCreateUIFontForLanguage(type, size, NULL));

		if (font != nil && s_ui_font_count < APK_UI_FONT_CACHE) {
			s_ui_fonts[s_ui_font_count].type = type;
			s_ui_fonts[s_ui_font_count].size = size;
			s_ui_fonts[s_ui_font_count].font = [font retain];
			s_ui_font_count++;
		}
		return font;
	}
}


+ (NSFont *)fontWithName:(NSString *)fontName size:(CGFloat)fontSize
{
	if (fontName == nil) {
		return nil;
	}
	/* A NAME THE REGISTRY CANNOT RESOLVE ANSWERS nil, which is `CTFontCreateWithName`'s own NULL — Apple's
	 * "or NULL if no font is found" reaching the AppKit spelling unchanged. */
	return apk_font_take(CTFontCreateWithName((CFStringRef)fontName, fontSize, NULL));
}

+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)fontDescriptor size:(CGFloat)fontSize
{
	if (fontDescriptor == nil) {
		return nil;
	}
	/* THE DESCRIPTOR'S OWN SUBSTRATE, WHICH THE TWO CLASSES SHARE AS A PRIVATE IVAR */
	return apk_font_take(CTFontCreateWithFontDescriptor(fontDescriptor->_descriptor, fontSize, NULL));
}

/* **THE USER'S FACE IS THE ONE THE DEFAULTS NAME, AND THE UI FONT IS THE FALLBACK.** `+setUserFont:` stores a name and a
 * size (a font object is not a defaults value); this door reads the name back and makes the font at the size asked for,
 * falling back to the platform's UI font when nothing has been stored — which is what the door answered before the
 * setter existed, so a caller that never stored one sees no change. */
+ (NSFont *)userFontOfSize:(CGFloat)fontSize
{
	NSString *name = nil;
	NSFont *font = nil;

	@try {
		name = [[NSUserDefaults standardUserDefaults] objectForKey:@"NSFontUserFontName"];
	} @catch (id exception) {
		(void)exception;
		name = nil;
	}
	if ([name length] > 0) {
		font = [self fontWithName:name size:fontSize];
	}
	return (font != nil) ? font : apk_ui_font(kCTFontUserFontType, fontSize);
}

+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)fontSize
{
	NSString *name = nil;
	NSFont *font = nil;

	@try {
		name = [[NSUserDefaults standardUserDefaults] objectForKey:@"NSFontUserFixedPitchName"];
	} @catch (id exception) {
		(void)exception;
		name = nil;
	}
	if ([name length] > 0) {
		font = [self fontWithName:name size:fontSize];
	}
	return (font != nil) ? font : apk_ui_font(kCTFontUserFixedPitchFontType, fontSize);
}

+ (NSFont *)systemFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontSystemFontType, fontSize);
}

+ (NSFont *)boldSystemFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontEmphasizedSystemFontType, fontSize);
}

+ (NSFont *)labelFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontLabelFontType, fontSize);
}

+ (NSFont *)titleBarFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontWindowTitleFontType, fontSize);
}

+ (NSFont *)menuFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontMenuItemFontType, fontSize);
}

+ (NSFont *)menuBarFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontMenuTitleFontType, fontSize);
}

+ (NSFont *)messageFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontMessageFontType, fontSize);
}

+ (NSFont *)paletteFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontPaletteFontType, fontSize);
}

+ (NSFont *)toolTipsFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontToolTipFontType, fontSize);
}

+ (NSFont *)controlContentFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontControlContentFontType, fontSize);
}

/* **THE THREE STANDARD SIZES, AND THEIR VALUES ARE THIS TIER'S** — Apple's era header gives the sentences and no
 * numbers. 13.0 is not invented here: it is the same default `CTFontCreateUIFontForLanguage` applies when a size
 * of 0.0 is passed, so the standard System font is one number in two places, and the other two follow it down. */
+ (NSFont *)preferredFontForTextStyle:(NSFontTextStyle)style
{
	return apk_ui_font(kCTFontSystemFontType, fn_text_style_size(style));
}

+ (NSFont *)monospacedSystemFontOfSize:(CGFloat)fontSize weight:(NSFontWeight)weight
{
	/* **THE FIXED-PITCH ROLE, NOT A HARDCODED DISTRIBUTION FACE.** This door used to name `DejaVuSansMono`
	 * directly, which made one host's default the AppKit's answer on every machine and put the choice in the wrong
	 * tier: Core Text owns the fixed-pitch preference list now (`AGORA_MONO_FONT`, defaulting to IBM Plex Mono),
	 * and this door asks for the role. The emphasized case copies the role's face WITH the bold trait, so it
	 * answers NULL rather than passing a regular face off as bold when the family has no bold member — the same
	 * rule `CTFontCreateUIFontForLanguage` applies to its own emphasized roles. */
	NSFont *base = apk_ui_font(kCTFontUserFixedPitchFontType, fontSize);

	if (base != nil && weight >= NSFontWeightSemibold) {
		CTFontRef bold = CTFontCreateCopyWithSymbolicTraits((CTFontRef)base->_font, fontSize, NULL,
							   kCTFontBoldTrait, kCTFontBoldTrait);

		if (bold != NULL) {
			NSFont *answer = apk_font_take(bold);

			if (answer != nil) {
				return answer;
			}
		}
	}
	return base;
}

+ (CGFloat)systemFontSize
{
	return (CGFloat)13.0;
}

+ (CGFloat)smallSystemFontSize
{
	return (CGFloat)11.0;
}

+ (CGFloat)labelFontSize
{
	return (CGFloat)10.0;
}



- (NSString *)fontName
{
	return [(NSString *)CTFontCopyPostScriptName(_font) autorelease];
}

- (NSString *)familyName
{
	return [(NSString *)CTFontCopyFamilyName(_font) autorelease];
}

- (NSString *)displayName
{
	/* THE FULL NAME, which is Apple's own reading ("usually the full name") and this tier's only name between
	 * the PostScript one and the family. */
	return [(NSString *)CTFontCopyFullName(_font) autorelease];
}

- (CGFloat)pointSize
{
	return CTFontGetSize(_font);
}

- (const CGFloat *)matrix
{
	return _matrix;
}

- (NSUInteger)numberOfGlyphs
{
	return (NSUInteger)CTFontGetGlyphCount(_font);
}

- (NSCharacterSet *)coveredCharacterSet
{
	return [(NSCharacterSet *)CTFontCopyCharacterSet(_font) autorelease];
}

- (NSRect)boundingRectForFont
{
	return CTFontGetBoundingBox(_font);
}

/* **THE ONE DOOR THAT COMPUTES RATHER THAN ASKS, AND IT IS O(glyphs) PER CALL.** Core Text has no
 * "maximum advancement" door — Apple's own is an AppKit-side answer — so this scans every glyph's advance. The
 * boundary is stated here rather than left for a caller to discover by timing it. */
- (NSSize)maximumAdvancement
{
	long count = CTFontGetGlyphCount(_font);
	CGGlyph *glyphs;
	CGSize *advances;
	NSSize maximum = { 0.0, 0.0 };
	long i;

	if (count <= 0) {
		return maximum;
	}
	glyphs = (CGGlyph *)malloc(sizeof(CGGlyph) * (size_t)count);
	advances = (CGSize *)malloc(sizeof(CGSize) * (size_t)count);
	if (glyphs == NULL || advances == NULL) {
		free(glyphs);
		free(advances);
		return maximum;
	}
	for (i = 0; i < count; i++) {
		glyphs[i] = (CGGlyph)i;
	}
	CTFontGetAdvancesForGlyphs(_font, kCTFontDefaultOrientation, glyphs, advances, count);
	for (i = 0; i < count; i++) {
		if (advances[i].width > maximum.width) {
			maximum.width = advances[i].width;
		}
		if (advances[i].height > maximum.height) {
			maximum.height = advances[i].height;
		}
	}
	free(glyphs);
	free(advances);
	return maximum;
}

- (CGFloat)ascender
{
	return CTFontGetAscent(_font);
}

/* **THE ONE METRIC WHOSE SIGN THIS CLASS OWNS, AND IT IS NEGATIVE — APPLE'S OWN CONTRACT.** Every other door here
 * forwards a Core Text answer, and `CTFontGetDescent` (like `CGFontGetDescent` under it) answers a descent as a
 * MAGNITUDE, because the line arithmetic that consumes it is `ascent + descent + leading`. THIS door's contract is
 * the other one: Apple's own sentence for `NSFont -descender` is "the value is negative", so the sign is put back
 * here and nowhere else — one negation, in the one layer whose documentation asks for it. It is also why a caller
 * measuring a text line must use `fabs` on this door, which is what `NSButtonCell` already does when it centres a
 * title in its bezel. */
- (CGFloat)descender
{
	return -CTFontGetDescent(_font);
}

- (CGFloat)leading
{
	return CTFontGetLeading(_font);
}

- (CGFloat)underlinePosition
{
	return CTFontGetUnderlinePosition(_font);
}

- (CGFloat)underlineThickness
{
	return CTFontGetUnderlineThickness(_font);
}

- (CGFloat)italicAngle
{
	return CTFontGetSlantAngle(_font);
}

- (CGFloat)capHeight
{
	return CTFontGetCapHeight(_font);
}

- (CGFloat)xHeight
{
	return CTFontGetXHeight(_font);
}

- (BOOL)isFixedPitch
{
	/* THE SUBSTRATE'S OWN BIT, which §M7f derived from the face's OS/2 table — so the answer agrees with
	 * `CTFontCopyTraits`' dictionary by construction rather than by a second reading of the face. */
	return (CTFontGetSymbolicTraits(_font) & kCTFontMonoSpaceTrait) ? YES : NO;
}

/* **THE FONT'S OWN DESCRIPTION, TAKEN THROUGH PUBLIC DOORS**: Core Text copies the descriptor out of the font,
 * this class copies ITS attributes out of that, and the AppKit door builds a descriptor from them — so the
 * bridge is one attribute dictionary rather than a shared private type, which is the same interface Apple's era
 * object exposes (`_attributes`). */
- (NSFontDescriptor *)fontDescriptor
{
	CTFontDescriptorRef ct = CTFontCopyFontDescriptor(_font);
	NSDictionary *attributes;
	NSFontDescriptor *descriptor;

	if (ct == NULL) {
		return nil;
	}
	attributes = (NSDictionary *)CTFontDescriptorCopyAttributes(ct);
	CFRelease(ct);
	descriptor = [NSFontDescriptor fontDescriptorWithFontAttributes:attributes];
	[attributes release];
	return descriptor;
}

- (NSFont *)fontWithSize:(CGFloat)fontSize
{
	return apk_font_take(CTFontCreateCopyWithAttributes(_font, fontSize, NULL, NULL));
}

/* ============================================================================================ *
 * THE ERA'S REST: METRICS FROM THE FACE, THE VARIANTS THAT ARE THIS FONT, AND FIVE REFUSALS     *
 * ============================================================================================ */

/* ---- GLYPH METRICS, FROM THE FACE -------------------------------------------------------------- */

/* **CORE TEXT ANSWERS EVERY ONE OF THESE**, which is the whole reason this class is a view of a `CTFontRef` rather than
 * a second table: `CTFontGetAdvancesForGlyphs`, `CTFontGetBoundingRectsForGlyphs`, `CTFontGetGlyphWithName`, and a
 * `CTLine` for the width of a string. The GLYPH TYPE is Apple's `unsigned short`, so the cast to `CGGlyph` is the same
 * width by construction. */
- (NSSize)advancementForGlyph:(NSGlyph)glyph
{
	CGGlyph cgGlyph = (CGGlyph)glyph;
	CGSize advance = CGSizeZero;

	if (_font == NULL) {
		return NSZeroSize;
	}
	CTFontGetAdvancesForGlyphs(_font, kCTFontHorizontalOrientation, &cgGlyph, &advance, 1);
	return NSMakeSize(advance.width, advance.height);
}

- (void)getAdvancements:(NSSizeArray)advancements forGlyphs:(const NSGlyph *)glyphs count:(NSUInteger)count
{
	CGSize *sizes;
	NSUInteger i;

	if (advancements == NULL || glyphs == NULL || count == 0 || _font == NULL) {
		return;
	}
	sizes = (CGSize *)malloc(sizeof(CGSize) * count);
	if (sizes == NULL) {
		return;
	}
	CTFontGetAdvancesForGlyphs(_font, kCTFontHorizontalOrientation, (const CGGlyph *)glyphs, sizes, (CFIndex)count);
	for (i = 0; i < count; i++) {
		advancements[i] = NSMakeSize(sizes[i].width, sizes[i].height);
	}
	free(sizes);
}

/* A PACKED GLYPH STRING IS UNPACKED FIRST, and the packing decides the width: the one-, two- and four-byte cases are the
 * three this tree can read (the two EUC packings are refused by `NSConvertGlyphsToPackedGlyphs` for the same reason). */
- (void)getAdvancements:(NSSizeArray)advancements forPackedGlyphs:(const void *)packedGlyphs length:(NSUInteger)length
{
	NSGlyph *glyphs;
	NSUInteger width = 1, count, i;

	if (packedGlyphs == NULL || advancements == NULL || length == 0) {
		return;
	}
	switch ([self glyphPacking]) {
	case NSTwoByteGlyphPacking: width = 2; break;
	case NSFourByteGlyphPacking: width = 4; break;
	default: width = 1; break;
	}
	count = length / width;
	glyphs = (NSGlyph *)malloc(sizeof(NSGlyph) * count);
	if (glyphs == NULL) {
		return;
	}
	for (i = 0; i < count; i++) {
		if (width == 1) {
			glyphs[i] = (NSGlyph)((const unsigned char *)packedGlyphs)[i];
		} else if (width == 2) {
			glyphs[i] = ((const unsigned short *)packedGlyphs)[i];
		} else {
			glyphs[i] = (NSGlyph)((const unsigned int *)packedGlyphs)[i];
		}
	}
	[self getAdvancements:advancements forGlyphs:glyphs count:count];
	free(glyphs);
}

- (NSRect)boundingRectForGlyph:(NSGlyph)glyph
{
	CGGlyph cgGlyph = (CGGlyph)glyph;
	CGRect rect = CGRectZero;

	if (_font == NULL) {
		return NSZeroRect;
	}
	CTFontGetBoundingRectsForGlyphs(_font, kCTFontHorizontalOrientation, &cgGlyph, &rect, 1);
	return NSMakeRect(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
}

- (void)getBoundingRects:(NSRectArray)bounds forGlyphs:(const NSGlyph *)glyphs count:(NSUInteger)count
{
	CGRect *rects;
	NSUInteger i;

	if (bounds == NULL || glyphs == NULL || count == 0 || _font == NULL) {
		return;
	}
	rects = (CGRect *)malloc(sizeof(CGRect) * count);
	if (rects == NULL) {
		return;
	}
	CTFontGetBoundingRectsForGlyphs(_font, kCTFontHorizontalOrientation, (const CGGlyph *)glyphs, rects,
					(CFIndex)count);
	for (i = 0; i < count; i++) {
		bounds[i] = NSMakeRect(rects[i].origin.x, rects[i].origin.y, rects[i].size.width, rects[i].size.height);
	}
	free(rects);
}

/* **A LINE, LAID OUT AND MEASURED** — which is what a string's width is: the sum of the glyphs' advances with kerning,
 * not the sum of the characters' widths. */
/* **THE STRING IS MEASURED THROUGH THE APPKIT'S OWN DOOR**, not by a second `CTLine`: `-sizeWithAttributes:` is what this
 * tree's drawing asks for the same question (and what the kerning and the fallback face go through), so the width a
 * caller gets here is the width the string will occupy when it is drawn. */
- (CGFloat)widthOfString:(NSString *)string
{
	if (string == nil || [string length] == 0) {
		return 0.0;
	}
	return [string sizeWithAttributes:[NSDictionary dictionaryWithObject:self forKey:NSFontAttributeName]].width;
}

- (CGFloat)defaultLineHeightForFont
{
	return [self ascender] - [self descender] + [self leading];
}

- (NSGlyphInfo *)glyphWithName:(NSString *)glyphName
{
	CGGlyph glyph;

	if (glyphName == nil || _font == NULL) {
		return nil;
	}
	glyph = CTFontGetGlyphWithName(_font, (CFStringRef)glyphName);
	if (glyph == 0) {
		return nil;
	}
	/* THE NAME IS CARRIED, not the index: a glyph info whose name is known is what a caller can round-trip through
	 * `-glyphName`, and the name it was asked for is the name it answers. */
	return [NSGlyphInfo glyphInfoWithGlyphName:glyphName forFont:self baseString:@"A"];
}

/* **A GLYPH IS "ENCODED" WHEN THE FACE HAS IT**, which is the only sense this tier can give Apple's door: the font knows
 * no encoding table, and a glyph index past its count is one it cannot draw. */
- (BOOL)glyphIsEncoded:(NSGlyph)glyph
{
	return (glyph < [self numberOfGlyphs]) ? YES : NO;
}

/* **THE PACKING IS DERIVED FROM HOW MANY GLYPHS THE FACE HAS**, which is what makes an integer-width packing correct:
 * a face of at most 255 glyphs fits one byte, one of at most 65535 two, and anything larger four. */
- (NSMultibyteGlyphPacking)glyphPacking
{
	NSUInteger glyphs = [self numberOfGlyphs];

	if (glyphs <= 255) {
		return NSOneByteGlyphPacking;
	}
	if (glyphs <= 65535) {
		return NSTwoByteGlyphPacking;
	}
	return NSFourByteGlyphPacking;
}

/* AND THE TWO CHARACTER-ENCODING ANSWERS: this tier's faces are Core Text faces, so they are Unicode, and the encoding
 * scheme is the one every one of them reports. */
- (BOOL)isBaseFont
{
	/* NO SCREEN OR PRINTER VARIANTS EXIST HERE (see the variant doors below), so every font IS a base font. */
	return YES;
}

- (NSStringEncoding)mostCompatibleStringEncoding
{
	return NSUnicodeStringEncoding;
}

- (NSString *)encodingScheme
{
	return @"ISO10646-1";
}

/* **THE ONE POSITION DOOR A FONT CAN ANSWER: THE PRECEDING GLYPH'S ADVANCEMENT.** Apple's nominal position of a glyph is
 * where it sits after the one before it, and Core Text knows exactly that number. */
- (NSPoint)positionOfGlyph:(NSGlyph)glyph precededByGlyph:(NSGlyph)previousGlyph isNominal:(BOOL *)isNominal
{
	NSSize advance;

	(void)glyph;
	advance = [self advancementForGlyph:previousGlyph];
	if (isNominal != NULL) {
		*isNominal = YES;
	}
	return NSMakePoint(advance.width, 0.0);
}

/* ---- THE TRANSFORM CONSTRUCTORS, AND THE VARIANTS THAT ARE THIS FONT ---------------------------- */

/* **A MATRIX OR A TRANSFORM IS A SCALE, HERE.** This class's `-matrix` answers the identity and its fonts are made at a
 * size, so the only thing a caller's transform can mean is the point size it scales to: the size is taken from the
 * matrix (or the transform's scale) and the font is made at it. Anything else the caller passes is not representable,
 * and the header says so. */
+ (NSFont *)fontWithName:(NSString *)fontName matrix:(const CGFloat *)matrix
{
	CGFloat size = 12.0;

	if (matrix != NULL) {
		size = sqrt((double)(matrix[0] * matrix[0] + matrix[1] * matrix[1]));
		if (size <= 0.0) {
			size = 12.0;
		}
	}
	return [self fontWithName:fontName size:size];
}

+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)descriptor textTransform:(NSAffineTransform *)transform
{
	CGFloat size = [descriptor pointSize];

	if (transform != NULL) {
		CGFloat scale = sqrt((double)([transform transformStruct].m11 * [transform transformStruct].m11
					      + [transform transformStruct].m12 * [transform transformStruct].m12));

		if (scale > 0.0) {
			size *= scale;
		}
	}
	if (size <= 0.0) {
		size = 12.0;
	}
	return [self fontWithDescriptor:descriptor size:size];
}

- (NSFont *)screenFont
{
	return self;
}

- (NSFont *)screenFontWithRenderingMode:(NSFontRenderingMode)mode
{
	(void)mode;
	return self;
}

- (NSFont *)printerFont
{
	return self;
}

- (NSFontRenderingMode)renderingMode
{
	return NSFontDefaultRenderingMode;
}

- (NSAffineTransform *)textTransform
{
	return nil;
}

/* ---- THE DRAWING FONT --------------------------------------------------------------------------- */

/* **`-set` MAKES THIS THE FONT THE CONTEXT DRAWS WITH.** This tier's `NSGraphicsContext` has no font stack (Core Text
 * takes the font from each attributed string), so the door records the choice where the drawing can find it and the
 * header says that is what it means: `+fontWithName:size:` remains the way to get a face, and this is the way to say
 * "this is the current one". */
/* **THERE IS NO DRAWING FONT TO SET, AND THE DOOR SAYS SO RATHER THAN PRETENDING.** Apple's `NSGraphicsContext` carries a
 * current font that `-set` and `-setInContext:` install; this tier's drawing takes the font from each ATTRIBUTED STRING
 * (Core Text's runs), so a context has no font slot and a door that wrote one would be storing a bit nobody reads — the
 * failure this tree keeps re-learning. `+fontWithName:size:` remains how a caller makes a face, and the string's
 * attributes are how it gets drawn. */
- (void)set
{
	fn_refuse_workspace("NSFont -set",
			    "a current font on the graphics context - this tier draws from each string's attributes");
}

- (void)setInContext:(NSGraphicsContext *)graphicsContext
{
	(void)graphicsContext;
	fn_refuse_workspace("NSFont -setInContext:",
			    "a current font on the graphics context - this tier draws from each string's attributes");
}

/* ---- THE USER-FONT DEFAULTS, IN THE DEFAULTS DOMAIN --------------------------------------------- */

/* **THE USER'S CHOICES ARE PREFERENCES, SO THEY LIVE IN THE PREFERENCES DOMAIN** — the same `NSUserDefaults` the table's
 * autosave uses. The two SETTERS store the face's name and size (a font object is not a defaults value); the two
 * `…OfSize:` constructors already in this class read them.
 */
/* **A DEFAULTS WRITE THAT CANNOT LAND IS NOT A REASON TO ABORT A CALLER.** This tree's `NSUserDefaults` writes under
 * `$FNX_CONFIG_ROOT/Users/<name>/Configuration` (libagora-base's rule), so a process launched without that variable — a
 * probe, a command-line tool, an application whose launcher forgot it — throws from `-setObject:forKey:`. The doors below
 * catch that and carry on: the value simply does not persist, which is the honest outcome and not a crash in a font
 * preference. It is the same rule the rest of this library states about platform pieces: answer, and say what is missing. */
+ (NSArray *)preferredFontNames
{
	NSArray *names = nil;

	@try {
		names = [[NSUserDefaults standardUserDefaults] objectForKey:@"NSFontPreferredFontNames"];
	} @catch (id exception) {
		(void)exception;
		names = nil;
	}
	return (names != nil) ? names : [NSArray array];
}

+ (void)setPreferredFontNames:(NSArray *)names
{
	@try {
		[[NSUserDefaults standardUserDefaults] setObject:(names != nil) ? names : [NSArray array]
							  forKey:@"NSFontPreferredFontNames"];
	} @catch (id exception) {
		(void)exception;
	}
}

+ (void)setUserFont:(NSFont *)font
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	@try {
		if (font == nil) {
			[defaults removeObjectForKey:@"NSFontUserFontName"];
			[defaults removeObjectForKey:@"NSFontUserFontSize"];
		} else {
			[defaults setObject:[font fontName] forKey:@"NSFontUserFontName"];
			[defaults setObject:[NSNumber numberWithDouble:[font pointSize]] forKey:@"NSFontUserFontSize"];
		}
	} @catch (id exception) {
		(void)exception;
	}
}

+ (void)setUserFixedPitchFont:(NSFont *)font
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	@try {
		if (font == nil) {
			[defaults removeObjectForKey:@"NSFontUserFixedPitchName"];
			[defaults removeObjectForKey:@"NSFontUserFixedPitchSize"];
		} else {
			[defaults setObject:[font fontName] forKey:@"NSFontUserFixedPitchName"];
			[defaults setObject:[NSNumber numberWithDouble:[font pointSize]] forKey:@"NSFontUserFixedPitchSize"];
		}
	} @catch (id exception) {
		(void)exception;
	}
}

/* **THE SYSTEM'S SIZE FOR A CONTROL SIZE**, which is the era's three-step table: regular is the system size, small and mini
 * are two points and four points below it, and nothing else is asked.
 */
+ (CGFloat)systemFontSizeForControlSize:(NSFontControlSize)controlSize
{
	CGFloat regular = [self systemFontSize];

	if (controlSize == (NSFontControlSize)NSSmallControlSize) {
		return regular - 2.0;
	}
	if (controlSize == (NSFontControlSize)NSMiniControlSize) {
		return regular - 4.0;
	}
	return regular;
}

/* AND THE PARSER: "Name Size" in, the font it names out — nil when either half is missing or the face is not there. */
+ (NSFont *)useFont:(NSString *)fontDescription
{
	NSArray *parts;
	NSString *name;
	CGFloat size;

	if (fontDescription == nil) {
		return nil;
	}
	parts = [fontDescription componentsSeparatedByString:@" "];
	if ([parts count] < 2) {
		return nil;
	}
	size = (CGFloat)[[parts lastObject] doubleValue];
	if (size <= 0.0) {
		return nil;
	}
	name = [[parts subarrayWithRange:NSMakeRange(0, [parts count] - 1)] componentsJoinedByString:@" "];
	return [self fontWithName:name size:size];
}

/* ---- AND THE FIVE THAT REFUSE -------------------------------------------------------------------- */

/* **NO AFM METRICS EXIST IN THIS TIER**, and the four ATTACHMENT doors need a shaping context's metrics rather than a
 * face's — Core Text exposes those only through a laid-out line, which is the line's business and not a font's. */

- (NSDictionary *)afmDictionary
{
	fn_refuse_workspace("NSFont -afmDictionary", "AFM metrics, which no component in this tier produces");
	return nil;
}

- (BOOL)positionOfGlyph:(NSGlyph)glyph struckOverGlyph:(NSGlyph)overlayGlyph metricsExist:(BOOL *)exists
{
	(void)glyph;
	(void)overlayGlyph;
	if (exists != NULL) {
		*exists = NO;
	}
	fn_refuse_workspace("NSFont -positionOfGlyph:struckOverGlyph:metricsExist:",
			    "attachment metrics, which a laid-out line has and a face does not");
	return NO;
}

- (BOOL)positionOfGlyph:(NSGlyph)glyph struckOverRect:(NSRect)overlayRect metricsExist:(BOOL *)exists
{
	(void)glyph;
	(void)overlayRect;
	if (exists != NULL) {
		*exists = NO;
	}
	fn_refuse_workspace("NSFont -positionOfGlyph:struckOverRect:metricsExist:",
			    "attachment metrics, which a laid-out line has and a face does not");
	return NO;
}

- (NSInteger)positionOfGlyph:(NSGlyph)glyph
		withRelation:(NSGlyphRelation)relation
		 toBaseGlyph:(NSGlyph)baseGlyph
	    totalAdvancement:(NSSizePointer)advancement
		metricsExist:(BOOL *)exists
{
	(void)glyph;
	(void)relation;
	(void)baseGlyph;
	if (advancement != NULL) {
		*advancement = NSZeroSize;
	}
	if (exists != NULL) {
		*exists = NO;
	}
	fn_refuse_workspace("NSFont -positionOfGlyph:withRelation:toBaseGlyph:totalAdvancement:metricsExist:",
			    "attachment metrics, which a laid-out line has and a face does not");
	return 0;
}

- (void)positionsForCompositeSequence:(const NSGlyph *)someGlyphs
		      numberOfGlyphs:(NSInteger)count
			   pointArray:(NSPointArray)points
{
	(void)someGlyphs;
	(void)count;
	(void)points;
	fn_refuse_workspace("NSFont -positionsForCompositeSequence:numberOfGlyphs:pointArray:",
			    "a shaping context's composite sequence, which a face does not carry");
}

@end
