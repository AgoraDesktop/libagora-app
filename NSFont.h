/*
 * NSFont.h — a font, as the AppKit spells it: the OBJECT §A10bt measured as missing.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS THE FIRST APPKIT UNIT THE CORE TEXT LAYER WAS BUILT FOR.** §A10bt retracted "a font is ink in this
 * tier" and named the gap as a LAYER rather than an engine; `docs/design/coretext-plan.md` built that layer
 * (1038 rows, 41 probes) and §A10bu measured where this class's rows land on it. **MOST OF THIS FILE IS A
 * MAPPING**, and the parts that are not are named.
 *
 * **THE BRIDGE IS INTERNAL, AND THAT IS A MEASUREMENT RATHER THAN A STYLE.** §A10bu read Apple's `NSFont.h` and
 * `NSFontDescriptor.h` at the 10.2, 10.5 and 10.6 pins: **neither declares a `CTFont`, `CGFont` or `CFTypeRef`
 * type at all**. So there are no CT-typed doors to bridge, `_font` is a PRIVATE ivar, and every signature here is
 * AppKit's own — `-fontDescriptor` (in the next unit) answers an `NSFontDescriptor *`, never a
 * `CTFontDescriptorRef`. Apple's modern pair is toll-free bridged; Apple's 10.6 pair is not declared to be, and a
 * wrapper is what the era's documentation supports (`dec-7dca575a46b17524`).
 *
 * **AND PROSE IN THIS FILE IS READ BY AN INSTRUMENT, SO IT IS WRITTEN CAREFULLY.** The AppKit sweep's
 * "enum member" form is `\bNAME\s*[=,}]`, which matches a COMMA — so the sentence "the character set, the glyph
 * count", which this comment used to contain, credited NSFont's `-set` row from a comment. The Foundation sweep
 * strips comments before it scans names and this one does not (recorded as a defect, not fixed here because
 * changing an instrument mid-unit would flip rows it currently over-credits); this file therefore avoids
 * comma-punctuated prose that could spell a row.
 *
 * **AND THE SIGNATURES ARE THE ERA'S OWN, WHICH MEANS METHODS RATHER THAN PROPERTIES.** 10.6's `NSFont.h`
 * declares `- (CGFloat)ascender;` and not `@property CGFloat ascender` — `@property` reached AppKit later. The
 * modern ledger's `property` rows are credited by the getter-named rule the sweep learned (§A10am), so the
 * era-shaped declaration is the one that answers the modern row.
 *
 * WHAT THIS SLICE DOES NOT CARRY, each with its reason: `-fontDescriptor` and `+fontWithDescriptor:size:` need
 * `NSFontDescriptor`, which is the next unit — declaring them now would be declaring a door that cannot answer;
 * the glyph doors (`-glyphWithName:`, the advance and bounding-rect pairs) are slice two, because they need
 * `NSGlyph`; the text styles, weights and widths are the modern vocabulary (slice three); and `-screenFont`,
 * `-printerFont` and the rendering modes belong to a screen/printer distinction this tier does not make.
 */
#ifndef APP_KIT_NSFONT_H
#define APP_KIT_NSFONT_H

#import <Foundation/Foundation.h>

/* **APPLE FORWARD-DECLARES HERE RATHER THAN IMPORTING, AND SO DOES THIS FILE** (10.6's `NSFont.h` line 13:
 * `@class NSFontDescriptor, NSAffineTransform, NSGraphicsContext;`). §A10bv learned that a forward declaration
 * CREDITS A CLASS ROW — which is only a false claim when the class does not exist, and `NSFontDescriptor.h`
 * declares it now, so this one is true. */
@class NSFontDescriptor;

/* **NO FORWARD DECLARATIONS HERE, AND THE REASON IS THE INSTRUMENT RATHER THAN TASTE.** This slice declares no
 * door taking `NSFontDescriptor` or `NSAffineTransform` — the descriptor doors are the next unit — and a bare
 * `@class NSFontDescriptor;` is not merely dead weight: **the sweep's forward-declaration form credits the CLASS
 * row**, so an unused forward declaration would read as "NSFontDescriptor is declared" and the ledger would be
 * asked to claim a class that does not exist. The declaration goes in when the door does. */

/* **AND THE SUBSTRATE'S TYPE, SPELLED WITHOUT IMPORTING ITS HEADER.** A view of a `CTFont` is a pointer to an
 * incomplete type, and a public AppKit header has no business importing Core Text to say so — which is the same
 * rule `CGPattern.h` records for `CGContextRef`: "a repeated typedef of the same type, which C11 allows and which
 * is what keeps the two headers independent". The spelling is `CTFont.h`'s own, so the two denote one type. */
typedef const struct __CTFont *CTFontRef;

/* **THE TEXT STYLES, AND WHAT THEY MEAN IN A TIER WITH ONE UI FONT.** Apple's AppKit 11 added a set of
 * `NSFontTextStyle*` names — the same vocabulary UIKit's `UIFontTextStyle*` carries — so a caller describes the
 * ROLE of a piece of text and the system picks the face. §M6e already recorded this tier's answer for the twelve
 * `+…FontOfSize:` doors: there is ONE UI font, so every one of them answers it. **THE SAME ANSWER APPLIES HERE AND
 * FOR THE SAME REASON** — a preferred font for any style is this tier's system font at the style's own size — and
 * that is a recorded divergence, not an oversight. */
typedef NSString *NSFontTextStyle;

/* AND THE OPTIONS TYPE beside the styles themselves, which is where Apple declares it. It names the KEYS of the
 * options dictionary the style-aware doors take; no key of that dictionary is in this slice. */
typedef NSString *NSFontTextStyleOptionKey;

/* **THE WEIGHT AND WIDTH SCALES, WHOSE VALUES ARE THIS TIER'S AND WHOSE ORDER IS APPLE'S.** Apple describes a face's
 * weight and width as numbers on a scale where `Regular` and `Standard` are zero; no era artifact in this tree fixes
 * the literals, so they are this tier's — in the long-standing scale, and with the property that actually matters
 * stated plainly: **THE ORDER IS THE CONTRACT**. A caller who asks for something heavier than `Medium` and lighter
 * than `Heavy` is relying on `Medium < Semibold < Bold < Heavy`, and the probe checks that chain rather than the
 * numbers, exactly as the text styles check `LargeTitle > Title1 > Body`. NO DOOR IN THIS TIER CONSUMES ONE YET —
 * `+systemFontOfSize:weight:` would be the first, and it would map this scale onto the `wght` variation axis the
 * engine already ships (100/400/900). */
typedef CGFloat NSFontWeight;
typedef CGFloat NSFontWidth;

extern NSFontWeight NSFontWeightUltraLight;
extern NSFontWeight NSFontWeightThin;
extern NSFontWeight NSFontWeightLight;
extern NSFontWeight NSFontWeightRegular;
extern NSFontWeight NSFontWeightMedium;
extern NSFontWeight NSFontWeightSemibold;
extern NSFontWeight NSFontWeightBold;
extern NSFontWeight NSFontWeightHeavy;
extern NSFontWeight NSFontWeightBlack;

extern NSFontWidth NSFontWidthCompressed;
extern NSFontWidth NSFontWidthCondensed;
extern NSFontWidth NSFontWidthStandard;
extern NSFontWidth NSFontWidthExpanded;

extern NSFontTextStyle NSFontTextStyleBody;
extern NSFontTextStyle NSFontTextStyleCallout;
extern NSFontTextStyle NSFontTextStyleCaption1;
extern NSFontTextStyle NSFontTextStyleCaption2;
extern NSFontTextStyle NSFontTextStyleFootnote;
extern NSFontTextStyle NSFontTextStyleHeadline;
extern NSFontTextStyle NSFontTextStyleLargeTitle;
extern NSFontTextStyle NSFontTextStyleSubheadline;
extern NSFontTextStyle NSFontTextStyleTitle1;
extern NSFontTextStyle NSFontTextStyleTitle2;
extern NSFontTextStyle NSFontTextStyleTitle3;

/* **ANNOTATED WHILE WRITTEN (F6), WITH THE ANNOTATIONS THE PROBES ALREADY ASSERT.** The factories answer nil —
 * `+fontWithName:` for a nil name or an unresolvable face, `+fontWithDescriptor:` for a nil descriptor, and the
 * UI-font doors when the registry has no faces at all (which is not hypothetical: the window probe aborted on
 * exactly that before it learned to set the font path) — so their returns are `nullable`, and the name doors are
 * too, because they come from the engine and the engine can have nothing to say. */
NS_ASSUME_NONNULL_BEGIN

@interface NSFont : NSObject <NSSecureCoding>
{
	@public
	/* **THE SUBSTRATE, AND IT IS PRIVATE — WHICH IS THE WHOLE OF THE BRIDGE** (the `@public` is for this
	 * library's own C factory rather than for a caller, the same rule `CTRun.h` states for its arrays: "a C
	 * function cannot read an Objective-C ivar", and `apk_font_take` is plain C). A `CTFontRef` is where this tier's
	 * font object lives: the metrics, the names, the character coverage and the matrix all come out
	 * of it, so `NSFont` is a VIEW of one rather than a second implementation (`dec-7dca575a46b17524`). It is
	 * retained here and released in `-dealloc`, the one place this class owns anything. */
	CTFontRef _font;
	/* **AND THE MATRIX, CACHED, BECAUSE `-matrix` ANSWERS A POINTER**: Apple's 10.6 signature is
	 * `- (const CGFloat *)matrix;` and `NSFontIdentityMatrix` is the same shape — six `CGFloat`s the caller
	 * reads but does not own. `_matrix` is filled once, at creation, from the substrate's own transform. */
	CGFloat _matrix[6];
}

/* **THE CREATE DOORS, AND THE UI FAMILY IS ONE ENGINE DOOR.** Twelve of the fourteen class methods below differ
 * only in which `CTFontUIFontType` they name — §51 shipped all 28 of those names with Apple's values — so the
 * mapping is a table rather than twelve implementations, and this tier has ONE UI font to give (`§M6e`: every
 * type answers the tree's single face, which is a recorded divergence rather than an accident). */
+ (nullable NSFont *)fontWithName:(nullable NSString *)fontName size:(CGFloat)fontSize;
/* **THE DESCRIPTOR DOOR, AND ITS PRECEDENCE IS APPLE'S OWN SENTENCE**: "If fontSize is greater than 0.0, it has
 * precedence over NSFontSizeAttribute in fontDescriptor" — which is exactly what `CTFontCreateWithFontDescriptor`
 * does with a size argument, so 0.0 here means "the size the descriptor carries". */
+ (nullable NSFont *)fontWithDescriptor:(nullable NSFontDescriptor *)fontDescriptor size:(CGFloat)fontSize;
+ (nullable NSFont *)userFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)userFixedPitchFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)systemFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)boldSystemFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)labelFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)titleBarFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)menuFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)menuBarFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)messageFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)paletteFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)toolTipsFontOfSize:(CGFloat)fontSize;
+ (nullable NSFont *)controlContentFontOfSize:(CGFloat)fontSize;

/* **AND THE THREE STANDARD SIZES** — "the size of the standard System font" and its two siblings. THEIR VALUES
 * ARE THIS TIER'S: Apple publishes no numbers for them (the era's header gives the sentences and nothing more),
 * and the first is the same 13.0 points `CTFontCreateUIFontForLanguage` already defaults to. */
/* **THE STYLE-AWARE DOOR.** Apple's picks the face AND the size from the style; here it is the system font at the
 * style's size, which is the divergence the type's own comment states. */
+ (nullable NSFont *)preferredFontForTextStyle:(NSFontTextStyle)style;

/* **THE MONOSPACED DOOR, AND THE FACE IT ANSWERS WITH.** Apple's returns "a monospaced system font"; this tier now
 * SHIPS one — `DejaVuSansMono`, a Latin subset staged beside the proportional faces — so the door answers that face
 * rather than a refusal.
 *
 * THE WEIGHT CHOOSES A FACE FROM THE FAMILY, which is what a font manager does when a family has no variation axis:
 * DejaVu Sans Mono ships a regular and a bold, so `Semibold` and above answer the bold one and everything below
 * answers the regular. The boundary is this tier's own `NSFontWeightSemibold` rather than a second number, so the
 * scale and the door cannot drift apart.
 *
 * `+monospacedDigitSystemFontOfSize:weight:` IS **NOT** HERE. Its promise is narrower and harder: the SYSTEM font
 * with monospaced DIGITS, which needs a tabular-figures feature this tier's faces carry in GSUB while the feature
 * pipeline reads AAT. It stays on the ledger's work list rather than being answered with a face that would change
 * every glyph instead of the ten that matter. */
+ (nullable NSFont *)monospacedSystemFontOfSize:(CGFloat)fontSize weight:(NSFontWeight)weight;

+ (CGFloat)systemFontSize;
+ (CGFloat)smallSystemFontSize;
+ (CGFloat)labelFontSize;

/* THE THREE NAMES: the POSTSCRIPT name (Apple's own reading of `-fontName`), the family, and the display name,
 * which is the full name here — there is no localization in this tier, and Apple's own doc says the display name
 * is "usually the full name". */
- (nullable NSString *)fontName;
- (nullable NSString *)familyName;
- (nullable NSString *)displayName;

- (CGFloat)pointSize;
- (const CGFloat *)matrix;
- (NSUInteger)numberOfGlyphs;
- (nullable NSCharacterSet *)coveredCharacterSet;

/* **THE METRICS, EACH ONE A SHIPPED CORE TEXT DOOR** — and they came from the face in the first place, which is
 * why this class does not measure anything itself. `-boundingRectForFont` is `CTFontGetBoundingBox` (the FONT's
 * box, not a glyph's). **`-maximumAdvancement` IS THE ONE THAT IS COMPUTED HERE**: Core Text has no such door, so
 * it scans every glyph's advance — stated rather than hidden, and the boundary is that it is O(number of glyphs)
 * per call. */
- (NSRect)boundingRectForFont;
- (NSSize)maximumAdvancement;
- (CGFloat)ascender;
/* NEGATIVE, which is this door's own contract rather than the engine's — see the note in the implementation for why
 * the negation lives at exactly this layer. A caller measuring a line of text wants `-ascender + fabs(descender)`. */
- (CGFloat)descender;
- (CGFloat)leading;
- (CGFloat)underlinePosition;
- (CGFloat)underlineThickness;
- (CGFloat)italicAngle;
- (CGFloat)capHeight;
- (CGFloat)xHeight;
- (BOOL)isFixedPitch;

/* A COPY AT ANOTHER SIZE — `CTFontCreateCopyWithAttributes`, which is the same door the era's `-fontWithSize:`
 * means. It answers a NEW `NSFont`; the receiver is untouched. */
- (nullable NSFont *)fontWithSize:(CGFloat)fontSize;

/* THE FONT'S OWN DESCRIPTION, which is the door `NSCell`'s font pair and `NSWindow`'s title were waiting on. */
- (nullable NSFontDescriptor *)fontDescriptor;

@end

NS_ASSUME_NONNULL_END
#endif /* APP_KIT_NSFONT_H */

