/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSColor.h — a colour as a value, and the first drawing class (C8.4).
 *
 * AN NSCOLOR IS A CGCOLOR, AND THAT IS THE WHOLE DESIGN. Apple's NSColor wraps `CGColorRef` on
 * macOS the same way, and this tree already has the Core Graphics colour: the spaces (device RGB,
 * device gray, sRGB, Display P3, generic gray gamma 2.2), the component accessors, the alpha, and
 * `CGColorCreateCopyByMatchingToColorSpace` — the ENGINE, lcms2, which is what makes conversion
 * below possible at all. So this class OWNS ONE PIECE OF STATE (a retained `CGColorRef`) and every
 * member is a mapping onto it; there is no second colour model hiding in here, which is what keeps
 * `-CGColor` from being a lossy door.
 *
 * THE SURFACE IS PINNED, NOT RECALLED, and the selectors came from Apple's navigator tree
 * (`tools/appkit-sweep.py`), not from memory: the ledger reduces a method to its FIRST selector
 * component, so a header written from the ledger alone would have guessed the tails. Everything
 * Apple documents as DEPRECATED is absent, and the refusals below are named with their reason.
 *
 * WHAT IS NOT HERE, IN FOUR GROUPS:
 *
 *   NOT IN THIS SLICE, AND EACH HAS A HOME: `-colorSpace` and `-colorUsingColorSpace:` need
 *   `NSColorSpace`; `-colorSpaceName` and `-colorUsingColorSpaceName:` need the
 *   `NSColorSpaceName` string constants; `-drawSwatchInRect:` needs `NSRectFill` and the AppKit
 *   rect helpers; `-colorWithSystemEffect:`, `-highlightWithLevel:`, `-blendedColorWithFraction:`
 *   and the `NSColor` SYSTEM colours (`labelColor`, `controlAccentColor`, the 20-odd semantic
 *   colours) need an appearance system this tree does not have. The `HSB` and `CMYK` constructors
 *   and getters are absent too, and for the ordinary reason: this library's colour spaces are RGB
 *   and gray (CMYK is refused by the engine, as C4 records).
 *
 *   NO SUBSTRATE: the pattern, `CIColor`, pasteboard, catalog and named-colour constructors
 *   (`+colorWithPatternImage:`, `+colorWithCIColor:`, `+colorFromPasteboard:`,
 *   `+colorWithCatalogName:`, `+colorNamed:`, `+colorWithName:`) each need a subsystem — an image
 *   class, Core Image, a pasteboard, a colour catalog — that does not exist here yet.
 *
 *   AND TWO THAT ARE HDR AND OUT BY THE SAME REASON AS THE `ContentHeadroom` ROWS:
 *   `+colorWithRed:green:blue:alpha:exposure:` and `…:linearExposure:` ask for an extended-range
 *   pipeline this layer does not have.
 *
 * A DEVIATION, STATED BECAUSE IT IS A CHOICE AND NOT AN OVERSIGHT. Apple has three DISTINCT RGB
 * spaces behind these constructors — device, "calibrated" (the generic RGB profile) and generic —
 * and this library has one RGB story: device RGB, which here IS sRGB (C4 says so). So
 * `+colorWithDeviceRed:`, `+colorWithCalibratedRed:` and `+colorWithRed:` all resolve to it, and the
 * white forms likewise. The CONSEQUENCE is that two colours made by different constructors with the
 * same numbers compare equal, which is the reading this library already takes of a device space
 * ("the numbers are the ones to blend"), and `-colorSpace` — deferred — would not tell them apart.
 * The named spaces that DO carve out a real distinction are used where Apple names them:
 * `+colorWithSRGBRed:` uses the sRGB profile, `+colorWithDisplayP3Red:` Display P3, and
 * `+colorWithGenericGamma22White:` the gamma-2.2 gray profile.
 *
 * AND THE COMPONENT GETTERS CONVERT RATHER THAN RAISING, WHICH IS THE SECOND DEVIATION. Apple's
 * `-redComponent` documents an `NSInternalInconsistencyException` for a colour outside an RGB space;
 * this library asks the ENGINE for the value in the space the getter needs instead, so a white
 * colour has a red component (the same colour in RGB, and NOT the same number: the ENGINE is converting between gamma-2.2 gray
 * against D50 and sRGB, so 0.5 in comes back as 0.5039 — a real transform, which the probe measures) and an RGB colour has a white one (its luminance
 * through the profile). A raise is only left for the case the engine genuinely cannot answer. The
 * reading is that a library with a colour engine and a defined answer should give it.
 *
 * AND THE CONVERSION IS A REAL ONE, WHICH IS WORTH SAYING BECAUSE THE FIRST VERSION OF THIS HEADER
 * SAID THE OPPOSITE. It claimed the gray-to-RGB trip was "the gray value" — i.e. an identity — and the
 * probe measured 0.5039 for a 0.5 gray. Device gray here is gamma-2.2 against D50 and device RGB is
 * sRGB (CoreGraphics' own conversion table says so), so the two spaces disagree by a gamma and the
 * engine is doing the work a colour engine exists to do. Every check that crosses the pair therefore
 * carries a colour-transform tolerance and not an exact one.
 */
#ifndef APPKIT_NSCOLOR_H
#define APPKIT_NSCOLOR_H

#import <AppKit/NSCell.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreGraphics/CGColor.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN


/* **AND THE CONTROL TINT IS NOT DECLARED HERE, WHICH IS A DECISION RATHER THAN AN OMISSION.** `+colorForControlTint:`
 * below takes one, and this header used to declare the enum itself; it is `NSCell.h`'s — the era declares it there,
 * on the cell that carries it, and this tree follows the era — so this file IMPORTS that header instead. Two
 * identical declarations of one enum are a REDEFINITION in any file that includes both, which is what the re-base of
 * `NSMenuItemCell` found. The type means what it always meant: it simply has one home. See appkit-plan.md §A10bf and
 * §A10bg. */

/* THE FOUR NAMED GREYS AND THE TWO NOTIFICATIONS. The GREY VALUES ARE APPLE'S DOCUMENTED FRACTIONS —
 * NSBlack is 0, NSDarkGray a third, NSLightGray two thirds and NSWhite 1 — and they are DEVICE greys, which
 * is a fact about what they look like rather than a detail: `+blackColor` is the CONTROL black and this is
 * the pure one, so the two are deliberately different objects with different values. */
/* FORWARDED: the constants below are declared before the class is, and the two doors that reach the
 * pasteboard and an image name them without importing their headers. */
@class NSColor;
@class NSImage;
@class NSPasteboard;

extern NSColor *NSBlack;
extern NSColor *NSDarkGray;
extern NSColor *NSLightGray;
extern NSColor *NSWhite;

extern NSString *NSControlTintDidChangeNotification;
extern NSString *NSSystemColorsDidChangeNotification;

/* AND THE ONE VERSION NUMBER, WHICH IS A `#define` WITH ITS VALUE IN THE ERA HEADER (`641.0`) — the rare
 * case where a version constant's value IS published, so it is transcribed rather than left open. */
#define NSAppKitVersionNumberWithPatternColorLeakFix 641.0

@interface NSColor : NSObject <NSCopying>
{
	CGColorRef _cgColor;    /* RETAINED, and the only state this class has */
}

/* THE BRIDGE, IN BOTH DIRECTIONS. `-CGColor` returns the retained colour itself rather than a copy,
 * because there is only one representation to hand back; `+colorWithCGColor:` answers nil for a NULL
 * colour rather than wrapping nothing.
 *
 * AND TAKING A NULLABLE COLOUR IS A DELIBERATE DIFFERENCE FROM APPLE: under an assume-non-null region
 * Apple's parameter is non-null, but a CGColorRef in a caller's hand is very often one that came from
 * something which may have failed (`[... CGColor]` on a nil object IS NULL), so the choice here is to
 * answer nil rather than make a caller unwrap an optional a second time. The declaration says
 * `nullable`, so the contract and the behaviour are one sentence — the compiler pointed at the gap
 * when the probe first passed NULL to what the header had called non-null. */
+ (nullable NSColor *)colorWithCGColor:(nullable CGColorRef)cgColor;
@property (nullable, readonly) CGColorRef CGColor;

/* THE COMPONENT CONSTRUCTORS, over the spaces this library has. Each returns nil only if Core
 * Graphics refused to build the colour, which for these spaces means a NULL space — it cannot
 * happen through this header, and returning nil beats returning a colour in no space. */
+ (nullable NSColor *)colorWithDeviceRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				   alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithDeviceWhite:(CGFloat)white alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithCalibratedRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				       alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithCalibratedWhite:(CGFloat)white alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
			     alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithSRGBRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				 alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithDisplayP3Red:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				      alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithGenericGamma22White:(CGFloat)white alpha:(CGFloat)alpha;

/* THE COMPONENTS IN THE COLOUR'S OWN TERMS, converting through the engine when the colour is not
 * already in the space the getter needs — see the header note above. `numberOfComponents` counts
 * ALPHA, which is Apple's reading and this library's (`CGColorGetNumberOfComponents` says the same).
 * `getRed:green:blue:alpha:` and `getWhite:alpha:` are the pointer forms of the same values. */
@property (readonly) NSUInteger numberOfComponents;
@property (readonly) CGFloat alphaComponent;
@property (readonly) CGFloat redComponent;
@property (readonly) CGFloat greenComponent;
@property (readonly) CGFloat blueComponent;
@property (readonly) CGFloat whiteComponent;

/* THE HSB AND CMYK TERMS, WHICH THIS LIBRARY CANNOT GET FROM ITS ENGINE AND THEREFORE COMPUTES — the second
 * deviation the note above describes, applied to seven getters. Apple documents an
 * `NSInternalInconsistencyException` for a component of a colour outside the space the getter needs and then
 * CONVERTS anyway in practice; this tier converts in every case, which is the reading its own note already
 * takes for `-redComponent` from a gray colour.
 *
 * AND THE CONVERSIONS ARE NAMED RATHER THAN LEFT AS ARITHMETIC:
 *
 *   HSB comes from the RGB triple by the standard definition — brightness is the LARGEST of the three,
 *   saturation is their RANGE over that largest (zero when the largest is zero), and hue is which SIDE of the
 *   hexagon the largest falls on, measured from red. A GREY has hue 0, which is what Apple's own conversion
 *   answers and the only defensible choice when there is no side to be on.
 *   CMYK comes from the same triple by the STANDARD SUBTRACTIVE SEPARATION WITH FULL BLACK GENERATION:
 *   black is one minus the largest component, and each of the other three is its own ink minus that black,
 *   rescaled. It is the textbook separation rather than ColorSync's, which is not in this tree — and for a
 *   PURE colour it is exact (red is c=0, m=1, y=1, k=0), which is what the probe asserts. */
@property (readonly) CGFloat hueComponent;
@property (readonly) CGFloat saturationComponent;
@property (readonly) CGFloat brightnessComponent;
@property (readonly) CGFloat cyanComponent;
@property (readonly) CGFloat magentaComponent;
@property (readonly) CGFloat yellowComponent;
@property (readonly) CGFloat blackComponent;
- (void)getRed:(nullable CGFloat *)red green:(nullable CGFloat *)green blue:(nullable CGFloat *)blue
	 alpha:(nullable CGFloat *)alpha;
- (void)getWhite:(nullable CGFloat *)white alpha:(nullable CGFloat *)alpha;
- (void)getComponents:(CGFloat *)components;

/* COPIES THE COLOUR WITH A DIFFERENT ALPHA, which Core Graphics does in one call and which is the
 * only mutation a value class needs. */
- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha;

/* THE FIFTEEN CLASS COLOURS, and they are spelled as PROPERTIES because that is how Apple's index
 * files them (`NSColor.blackColor` rather than `+blackColor`) — the Objective-C accessors are
 * `+blackColor` and friends either way, which is what a caller writes. */
+ (NSColor *)blackColor;
+ (NSColor *)whiteColor;
+ (NSColor *)redColor;
+ (NSColor *)greenColor;
+ (NSColor *)blueColor;
+ (NSColor *)cyanColor;
+ (NSColor *)yellowColor;
+ (NSColor *)magentaColor;
+ (NSColor *)orangeColor;
+ (NSColor *)purpleColor;
+ (NSColor *)brownColor;
+ (NSColor *)grayColor;
+ (NSColor *)darkGrayColor;
+ (NSColor *)lightGrayColor;
+ (NSColor *)clearColor;

/* ============================================================================================ *
 * THE CHROME'S OWN COLOURS, which a window PAINTS WITH rather than merely asks about.            *
 *                                                                                                *
 * THEY ARE HERE, IN THE ORDER APPLE KEEPS THEM, because the WINDOW is what draws a window's      *
 * chrome in this tree: the guest's window manager decorates nothing (appkit-plan §6 D6), so the  *
 * strip above the content and the backdrop behind it are the window's own pixels and these are   *
 * the colours it paints them in.                                                                 *
 *                                                                                                *
 * AND THE VALUES ARE OURS, which is stated rather than implied: Apple publishes no components    *
 * for a system colour — the same ground Foundation's enums stand on — so these are THIS TREE's   *
 * chrome, and a caller that needs Apple's exact shade has to bring it. What is NOT ours is the   *
 * SHAPE: a class method answering the same object every time, which is what these are.           *
 * ============================================================================================ */
+ (NSColor *)windowFrameColor;
+ (NSColor *)windowBackgroundColor;

/* ============================================================================================ *
 * AND THE SEMANTIC PALETTE, WHICH IS THE SAME KIND OF THING UNDER THE SAME RULE. The note      *
 * above states the ground for the chrome's two colours and it does not weaken for thirty more: *
 * APPLE PUBLISHES NO COMPONENTS FOR A SYSTEM COLOUR, so a system that has an appearance is the *
 * authority for its own — and this one does. WHAT IS APPLE'S HERE IS THE VOCABULARY AND THE      *
 * SHAPE (a class method, one object, the pairs that must contrast); WHAT IS OURS IS EVERY       *
 * COMPONENT, which is why each is written down in the implementation with the relation it must *
 * keep (text against its background, the four control shades in order, the alternating pair).   *
 *                                                                                              *
 * THE ONE THAT IS NOT A COLOUR IS REFUSED RATHER THAN ANSWERED, and it is named here so the    *
 * group is not read as finished work: `-currentControlTint` is a USER SETTING — which tint a    *
 * person chose — and there is no appearance system to hold one, exactly the ground the three   *
 * key-repeat intervals stand on in NSEvent. `-controlAlternatingRowBackgroundColors` is an      *
 * ARRAY rather than a colour, and that difference of SHAPE is the only other thing here that   *
 * is not one of the thirty class methods.                                                      *
 * ============================================================================================ */
+ (NSArray *)controlAlternatingRowBackgroundColors;
+ (NSUInteger)currentControlTint;
+ (NSColor *)textColor;
+ (NSColor *)textBackgroundColor;
+ (NSColor *)selectedTextColor;
+ (NSColor *)selectedTextBackgroundColor;
+ (NSColor *)controlTextColor;
+ (NSColor *)disabledControlTextColor;
+ (NSColor *)controlColor;
+ (NSColor *)controlBackgroundColor;
+ (NSColor *)controlShadowColor;
+ (NSColor *)controlDarkShadowColor;
+ (NSColor *)controlHighlightColor;
+ (NSColor *)controlLightHighlightColor;
+ (NSColor *)selectedControlColor;
+ (NSColor *)selectedControlTextColor;
+ (NSColor *)secondarySelectedControlColor;
+ (NSColor *)alternateSelectedControlColor;
+ (NSColor *)alternateSelectedControlTextColor;
+ (NSColor *)keyboardFocusIndicatorColor;
+ (NSColor *)headerColor;
+ (NSColor *)headerTextColor;
+ (NSColor *)gridColor;
+ (NSColor *)shadowColor;
+ (NSColor *)highlightColor;
+ (NSColor *)knobColor;
+ (NSColor *)selectedKnobColor;
+ (NSColor *)scrollBarColor;
+ (NSColor *)selectedMenuItemColor;
+ (NSColor *)selectedMenuItemTextColor;
+ (NSColor *)windowFrameTextColor;

/* **AND THE PLATFORM'S ACCENT, WHICH IS THE ONE COLOUR THIS TIER ADDS RATHER THAN ANSWERS.** Argentum's accent is
 * the periwinkle `(164,154,255)` — SAMPLED from the platform, not chosen here — and NO ERA DOOR CARRIES IT:
 * `+controlAccentColor` is 10.14 and this tree pins 10.5/10.6, while the era's own `+selectedControlColor` is a
 * BLUE (0.20, 0.42, 0.80) that is a different colour on purpose. So the accent is named `cg_`, which is this tree's
 * mark for a door the tier adds, and it is defined ONCE — the menu's selection chip and every control that
 * highlights now read the same two numbers instead of each carrying its own copy of them.
 *
 * AND IT IS NAMED FOR THE PRESS ON EVERY CONTROL WHOSE FACE IS A GREY. What a control the pointer merely rests on
 * wears is a step DOWN the grey scale rather than a second colour (see `+cg_prelightControlFaceColor` below), so a
 * BUTTON's accent means one thing: this control is being used.
 *
 * **AND THE SECOND DOOR IS BACK, BECAUSE A SWITCH IS NOT A GREY-FACED CONTROL.** The same hue LIGHTENED is what the
 * sample's own four-state legend gives for a switch's PRELIGHT — `#E5E3FF` against the `#A49AFF` it lightens, MEASURED
 * in `Argentum Mockup.png` beside the pills — and a switch's track IS the accent when it is ON, so "a step down the
 * grey scale" has nowhere to go: there is no grey to step down FROM. So the door is restored for that one control,
 * and the rule it departed from is left exactly as it was for the controls the rule was about. */
+ (NSColor *)cg_accentColor;
+ (NSColor *)cg_accentPrelightColor;
/* **AND THE ONE FACE THE ERA'S OWN NAMES DO NOT COVER.** `+controlColor` is a raised control, `+controlBackgroundColor`
 * is the surface a control shows THROUGH (a field's white), and a DISABLED control's face is neither: the era dims the
 * title and leaves the face alone, which is a face that still says "press me". So it is named `cg_` with the accent,
 * and its one relationship is stated where it is defined — the BOTTOM of the same scale `+controlColor` opens.
 * THE PRELIGHT'S FACE IS THE SAME KIND OF DOOR and sits between the two: a control the pointer is resting on is
 * neither at rest nor out of action, and the era has no name for that face either. */
+ (NSColor *)cg_prelightControlFaceColor;
+ (NSColor *)cg_disabledControlFaceColor;
/* **AND THE INK THE TITLE BAR'S MARKS ARE DRAWN IN: THE X, THE MINUS, THE PLUS, AND THE TOOLBAR PILL.** All four are
 * one grey, and they get a name of their own because NO ERA COLOUR COVERS THEM: they are neither text
 * (`+windowFrameTextColor` is the TITLE's ink, and a title is read while these are aimed at) nor a control's face nor
 * a border.
 *
 * 0.50, AND THE SAMPLE'S OWN VALUE WAS 0.70 (179 on its `#EBEBEB` strip). The sample is not being ignored — it is
 * being READ AGAINST THE SURFACE IT SITS ON, which is the thing a sampled colour cannot carry with it: ITS strip is
 * 0.92 and OURS is 0.82, so the same grey that reads as a mark there reads as a smudge here, and the ink has to come
 * down with the surface. It started at the title's black, which was too heavy for four small shapes, and stopped at
 * 0.70 on the way past, which was too light for this strip. 0.50 is a DARK grey on a light one — a full step below
 * `+controlShadowColor`'s 0.60 — and still nothing like black. */
+ (NSColor *)cg_chromeInkColor;
/* **AND THE GROOVE A SCROLLER'S KNOB RUNS IN, WHICH IS THE ONE PLACE THIS TREE INVERTS ITS OWN RULE.** Everywhere
 * else a raised thing is lighter than the window it sits on — that is the whole of `+controlColor`'s 0.95. A
 * SCROLLER'S GROUND IS NOT THE WINDOW, THOUGH: it is the GROOVE, so the knob takes the white and the groove takes a
 * grey BELOW both window faces, while the bar's two ends are buttons again. `Argentum Mockup.png` draws all of it as
 * custom ink rather than as a toolkit's widget, so the number IS the design rather than a reading of one: the groove
 * is 0.85 — 217, the sample's track, x=764..780.
 *
 * IT IS NAMED `cg_` BECAUSE NO ERA COLOUR COVERS A GROOVE: `+controlShadowColor`'s 0.60 is a BORDER's grey and at this
 * size reads as a hard line drawn on the face, and `+cg_disabledControlFaceColor`'s 0.86 is a FACE, which is busy
 * saying "not available" — the wrong thing for the ground of a scroller to say.
 *
 * **AND THE KNOB'S EDGE TURNED OUT NOT TO NEED A DOOR OF ITS OWN: IT IS `+controlDarkShadowColor`.** The sample
 * measures 188 there too, and 188 is that colour's value — so a knob's outline, its three dimples and every border in
 * the tier are one grey, and the name this header briefly carried for it is gone rather than kept as a synonym. */
+ (NSColor *)cg_scrollerTrackColor;

/* ============================================================================================ *
 * THE ERA'S REMAINING ROWS, AND WHAT EACH ONE'S ANSWER IS. TWO KINDS, and the difference is     *
 * what a ported program meets — a refusal it can read at the call, or a nil it has to expect:    *
 *                                                                                              *
 *   DECLARED AND REFUSING: the three that need a type this tree has not got — `+colorWithCIColor:` *
 *   (Core Image), `+colorWithColorSpace:components:count:` and `-colorUsingColorSpace:`          *
 *   (`NSColorSpace`, whose parameter is spelled `id` so this header does not credit that         *
 *   class's own rows — the over-crediting rule). Each answers nil and prints the subsystem it    *
 *   needs, so the LINK succeeds and the failure is at the CALL rather than at load.              *
 *   AND THE FOUR CATALOG NAMES, declared and answering nil: Apple's own note says they RAISE     *
 *   for a colour with no catalog, and this tier's rule for a component it cannot convert is to   *
 *   ANSWER. `-patternImage` sits with them and is NOT a refusal of the same kind: no colour this *
 *   class can make has an image behind it, because the pattern constructor itself refuses.       *
 *   STILL ABSENT, AND THE ONLY ROW HERE THAT IS: `-initWithCoder:`, which needs a published key   *
 *   set this duplication has not got.                                                            *
 *                                                                                              *
 * AND `-ignoresAlpha` IS DELIBERATELY LEFT OPEN, which is the one thing this file owes a later   *
 * unit: the flag is a global switch on how a colour is DRAWN, the door that would read it is     *
 * `-setFill`/`-setStroke`, and a stored flag with no reader is what this tree refuses — so the   *
 * row stays owed rather than half-shipped, and it is named here so the gap is visible.           *
 * ============================================================================================ */
- (nullable NSString *)catalogNameComponent;
- (nullable NSString *)colorNameComponent;
- (nullable NSString *)localizedCatalogNameComponent;
- (nullable NSString *)localizedColorNameComponent;
- (nullable NSImage *)patternImage;
+ (nullable NSColor *)colorWithCIColor:(id)ciColor;
+ (nullable NSColor *)colorWithColorSpace:(id)space
			       components:(const CGFloat *)components
				    count:(NSInteger)numberOfComponents;
- (nullable NSColor *)colorUsingColorSpace:(id)space;

/* ============================================================================================ *
 * AND THE LAST ROW OF THIS CLASS, WHOSE READER IS THE DRAWING DOOR. `+ignoresAlpha` is a global  *
 * switch on HOW A COLOUR IS DRAWN — Apple's own words are that the alpha component is ignored  *
 * when the colour is used — and this class has exactly two doors that put a colour into a       *
 * context, so those are where it is read: `-setFill` and `-setStroke`, each of which writes the *
 * colour OPAQUE while the flag is on. IT IS THEREFORE A FLAG WITH A READER rather than a        *
 * recorded bit, which is the only shape this tree ships for a switch: a stored value nothing   *
 * consults is what it refuses.                                                                  *
 *                                                                                              *
 * THE SHAPE IS APPLE'S — a CLASS method pair, because the switch is global — and the DEFAULT IS *
 * OFF, which is what "the alpha component is ignored" being opt-in means.                        *
 * ============================================================================================ */
+ (BOOL)ignoresAlpha;
+ (void)setIgnoresAlpha:(BOOL)flag;

/* THE CONSTRUCTORS. The hue pair is a real HSV-to-RGB trip; the CMYK one is the standard subtractive
 * conversion; `+colorFromPasteboard:` reads the plist this class writes. */
+ (nullable NSColor *)colorWithCalibratedHue:(CGFloat)hue saturation:(CGFloat)saturation
				  brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithDeviceHue:(CGFloat)hue saturation:(CGFloat)saturation
			      brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorWithDeviceCyan:(CGFloat)cyan magenta:(CGFloat)magenta yellow:(CGFloat)yellow
				    black:(CGFloat)black alpha:(CGFloat)alpha;
+ (nullable NSColor *)colorForControlTint:(NSControlTint)controlTint;
+ (nullable NSColor *)colorFromPasteboard:(NSPasteboard *)pasteBoard;

/* THE TWO THAT REFUSE BY NAME, for the reasons in their implementations: a catalog list and a tiled
 * pattern are substrates this tree does not have, and a colour object holding an image it cannot tile
 * would be a half-implementation. */
+ (nullable NSColor *)colorWithCatalogName:(NSString *)listName colorName:(NSString *)colorName;
+ (nullable NSColor *)colorWithPatternImage:(nullable NSImage *)image;

/* THE COMPONENT GETTERS, IN THE TWO SPACES THAT HAVE A SHAPE BEYOND RGB. Both raise through this class's
 * own `fn_raise_for` for a colour the engine cannot convert, which is the rule the existing getters set. */
- (void)getHue:(nullable CGFloat *)hue saturation:(nullable CGFloat *)saturation
    brightness:(nullable CGFloat *)brightness alpha:(nullable CGFloat *)alpha;
- (void)getCyan:(nullable CGFloat *)cyan magenta:(nullable CGFloat *)magenta yellow:(nullable CGFloat *)yellow
	  black:(nullable CGFloat *)black alpha:(nullable CGFloat *)alpha;

/* THE THREE RAMPS. `level = 0` and `fraction = 0` answer the receiver's own colour, which is the end the
 * probe checks: a blend that ignored its fraction would pass every other case. */
- (nullable NSColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(nullable NSColor *)color;
- (nullable NSColor *)highlightWithLevel:(CGFloat)val;
- (nullable NSColor *)shadowWithLevel:(CGFloat)val;

/* THE NAME-BASED CONVERSION — the door this class's own header points a caller at, and the one Apple
 * pairs with a `device:` hint this tree takes and does not use. */
- (nullable NSColor *)colorUsingColorSpaceName:(NSString *)colorSpace;
- (nullable NSColor *)colorUsingColorSpaceName:(NSString *)colorSpace
					device:(nullable NSDictionary *)deviceDescription;

/* AND THE THREE THAT REACH THE CURRENT CONTEXT OR THE BOARD. */
- (void)setFill;
- (void)setStroke;
- (void)drawSwatchInRect:(NSRect)rect;
- (void)writeToPasteboard:(NSPasteboard *)pasteBoard;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLOR_H */
