/*
 * NSFont.m — the AppKit font object, and it is a VIEW of a Core Text font rather than a second font.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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
	return apk_font_take(CTFontCreateWithName(fontName, fontSize, NULL));
}

+ (NSFont *)fontWithDescriptor:(NSFontDescriptor *)fontDescriptor size:(CGFloat)fontSize
{
	if (fontDescriptor == nil) {
		return nil;
	}
	/* THE DESCRIPTOR'S OWN SUBSTRATE, WHICH THE TWO CLASSES SHARE AS A PRIVATE IVAR */
	return apk_font_take(CTFontCreateWithFontDescriptor(fontDescriptor->_descriptor, fontSize, NULL));
}

+ (NSFont *)userFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontUserFontType, fontSize);
}

+ (NSFont *)userFixedPitchFontOfSize:(CGFloat)fontSize
{
	return apk_ui_font(kCTFontUserFixedPitchFontType, fontSize);
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
	/* THE TWO FACES THIS TIER SHIPS, chosen by the weight rather than pretending a static face has an axis. */
	return [self fontWithName:(weight >= NSFontWeightSemibold ? @"DejaVuSansMono-Bold" : @"DejaVuSansMono")
			     size:fontSize];
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

- (CGFloat)descender
{
	return CTFontGetDescent(_font);
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

@end
