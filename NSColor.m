/*
 * NSColor — one retained CGColorRef, and every member a mapping onto it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE ENGINE IS WHAT MAKES THE GETTERS POSSIBLE, and it is also what makes them a stated deviation:
 * Apple raises from `-redComponent` for a colour outside an RGB space, while this file asks
 * `CGColorCreateCopyByMatchingToColorSpace` for the value in the space the getter needs. A raise is
 * left for the one case the engine cannot answer, so a caller who would have crashed gets a number
 * and a caller who asked for the impossible still hears about it.
 *
 * AND THE HDR CONSTRUCTORS ARE ABSENT, not forgotten: `+colorWithRed:green:blue:alpha:exposure:` and
 * its `…:linearExposure:` sibling are extended-range entry points, and this layer has no such
 * pipeline — the same reason CoreGraphics' `ContentHeadroom` rows are unimplemented.
 */
#import <AppKit/NSColor.h>
#import <CoreGraphics/CGColor.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGContext.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImageRep.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#include <math.h>
#import <Foundation/NSException.h>

/* FOR THE REFUSAL BELOW AND NOTHING ELSE: the class-side diagnostics this tree writes go to stderr
 * by hand, because a refusal that is not printed is a refusal nobody can attribute. */
#include <stdio.h>

/* THE FIELD IS SET FROM INSIDE THE CLASS, which is not fastidiousness: the ivar is PROTECTED, and a
 * free function cannot touch it — the compiler said exactly that when the first version of this file
 * set `c->_cgColor` from `fn_color` below. A private initialiser is the way in for a helper that is a
 * function rather than a method. */
@interface NSColor ()
- (instancetype)initWithOwnedCGColor:(CGColorRef)cg;
@end

/* THE COLOUR OBJECT, TAKING OWNERSHIP OF A +1 CGColor — or nil for a NULL one, which is what
 * `+colorWithCGColor:` documents rather than an object wrapping nothing. */
static NSColor *fn_color(CGColorRef cg)
{
	NSColor *c;

	if (cg == NULL) {
		return nil;
	}
	c = [[NSColor alloc] initWithOwnedCGColor:cg];
	if (c == nil) {
		/* THE OWNERSHIP WAS HANDED OVER, so a failed allocation is the one path where this function
		 * still owns it. */
		CGColorRelease(cg);
	}
	return c;
}

/* A COLOUR IN A NAMED SPACE, which is where the three spaces that are NOT device spaces come from:
 * `CGColorSpaceCreateWithName` answers the shared object for a name it knows and NULL otherwise, so
 * there is no second check to write. */
static CGColorRef fn_named(NSString *name, CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
	CGColorSpaceRef space = CGColorSpaceCreateWithName(name);
	CGFloat comp[4];
	CGColorRef cg;

	if (space == NULL) {
		return NULL;
	}
	comp[0] = r;
	comp[1] = g;
	comp[2] = b;
	comp[3] = a;
	cg = CGColorCreate(space, comp);
	CGColorSpaceRelease(space);
	return cg;
}

/* THE FIFTEEN SINGLETONS, BUILT ONCE AND HELD FOREVER — the shape the device colour spaces already
 * have in CoreGraphics, and for the same reason: these are VALUES, not resources, so a caller who
 * asks twice should get the same object. `+colorWithDeviceRed:` answers +1, which the static keeps. */
static NSColor *fn_singleton(NSColor **slot, CGFloat r, CGFloat g, CGFloat b, CGFloat a)
{
	if (*slot == nil) {
		*slot = [NSColor colorWithDeviceRed:r green:g blue:b alpha:a];
	}
	return *slot;
}

/* THE COMPONENTS IN A GIVEN KIND OF SPACE, converting when the colour is not already there. Returns
 * the count written, or 0 when even the engine cannot make the trip; `out` receives them with ALPHA
 * LAST, the order both of CoreGraphics' arrays and of the pointer forms below use. */
static size_t fn_components_in(CGColorRef c, int want_rgb, CGFloat *out)
{
	CGColorSpaceRef space;
	int model;
	const CGFloat *comp;
	size_t i;

	if (c == NULL) {
		return 0;
	}
	/* A COLOUR ALREADY IN THE RIGHT KIND OF SPACE IS READ DIRECTLY, and A GREY VALUE IS
	 * REPLICATED INTO THE THREE RGB CHANNELS and nothing more — the reordering inside a family is
	 * not a colour-space transform, and `-[NSColor whiteComponent]` and
	 * `CGContextSetGrayFillColor` are 10.0-era doors built on it.
	 *
	 * !! THE CONVERSION IS GONE (2026-10-05) and so is the arm that asked for it:
	 * `CGColorCreateCopyByMatchingToColorSpace` is macOS 10.11 against a 10.6-era surface, so a
	 * colour whose MODEL is neither RGB nor gray answers 0 below and the callers raise, which is
	 * what this file's header note describes.
	 *
	 * AND THE TEST IS NOW THE MODEL RATHER THAN THE COMPONENT COUNT, which is A REAL BUG THIS
	 * REMOVAL EXPOSED: three components matched the RGB test, so a LAB colour — three components,
	 * and nothing about them a light value — would have had its a* and b* read out as green and
	 * blue. It was invisible only because the conversion intercepted that case first. */
	space = CGColorGetColorSpace(c);
	if (space != NULL) {
		size_t have = CGColorSpaceGetNumberOfComponents(space);

		model = CGColorSpaceGetModel(space);
		if ((want_rgb && model == kCGColorSpaceModelRGB) ||
		    (!want_rgb && model == kCGColorSpaceModelMonochrome)) {
			comp = CGColorGetComponents(c);
			for (i = 0; i < have; i++) {
				out[i] = comp[i];
			}
			out[have] = CGColorGetAlpha(c);
			return have + 1;
		}
		if (want_rgb && model == kCGColorSpaceModelMonochrome) {
			comp = CGColorGetComponents(c);
			out[0] = comp[0];
			out[1] = comp[0];
			out[2] = comp[0];
			out[3] = CGColorGetAlpha(c);
			return 4;
		}
	}
		if (!want_rgb && model == kCGColorSpaceModelRGB) {
			/* AN RGB COLOUR'S LUMINANCE IS COMPUTED HERE RATHER THAN CONVERTED, AND THAT IS THE
			 * ERA'S ANSWER RATHER THAN A LOOPHOLE: `-whiteComponent` on an RGB colour is a 10.0-era
			 * door, and Apple's own NSColor answers it with the three channels' weighted sum. What
			 * went with the conversion (2026-10-05) was the trip through a COLOUR SPACE — an RGB
			 * colour in a profile is no longer interpreted — so the arithmetic that needs no
			 * profile, on numbers that are already device numbers, stays. THE WEIGHTS ARE Rec.601's,
			 * which is what a device RGB colour means here: device RGB IS sRGB, and every check in
			 * the probe is about equal channels, where the weights cancel.
			 *
			 * A PROFILE-BACKED RGB SPACE REACHES THIS ARM TOO, and that is the same stated
			 * deviation the C probe records for its ICC and calibrated cases: its numbers are read
			 * as device numbers, because the alternative is the conversion that is gone. */
			comp = CGColorGetComponents(c);
			out[0] = 0.299 * comp[0] + 0.587 * comp[1] + 0.114 * comp[2];
			out[1] = CGColorGetAlpha(c);
			return 2;
		}
	/* AND A COLOUR IT CANNOT READ IS REFUSED, WITH THE REASON ON stderr SO THE RAISE THAT FOLLOWS
	 * IS ATTRIBUTABLE. A device-CMYK colour is the case that existed before; now it is the whole
	 * class, which is the era's answer rather than this file's. */
	fprintf(stderr, "APPKIT-REFUSE: -NSColor component getters cannot read a colour in this "
			"space — this library has no colour conversion\n");
	return 0;
}

/* AND THE RAISE, for the case the engine could not answer — see the file's header note. */
static void fn_raise_for(const char *what)
{
	[NSException raise:@"NSInternalInconsistencyException"
		    format:@"-NSColor %s: this colour cannot be expressed in that space", what];
}

/* THE FOUR NAMED GREYS AND THE TWO NOTIFICATIONS, DEFINED HERE. The greys are DEVICE greys at the
 * documented fractions; the notification NAMES are their own strings, which is the universal convention for
 * a notification and the same rule the rest of this tier follows. */
NSColor *NSBlack = nil;
NSColor *NSDarkGray = nil;
NSColor *NSLightGray = nil;
NSColor *NSWhite = nil;

NSString *NSControlTintDidChangeNotification = @"NSControlTintDidChangeNotification";
NSString *NSSystemColorsDidChangeNotification = @"NSSystemColorsDidChangeNotification";

@implementation NSColor

/* THE FOUR GREYS ARE BUILT ONCE, LAZILY, AND KEPT FOREVER — the same shape the fifteen singletons below
 * have, and for the same reason: they are VALUES, so a caller who asks twice should get the same object.
 * `+initialize` is the place because the names are globals a caller may read at any time. */
+ (void)initialize
{
	if (self == [NSColor class]) {
		/* ONE RETAIN EACH ON PURPOSE: these live for the life of the process, and an over-retain of a
		 * global is cheaper than guessing at the ownership the constructors answer with. */
		NSBlack = [[NSColor colorWithDeviceWhite:0.0 alpha:1.0] retain];
		NSDarkGray = [[NSColor colorWithDeviceWhite:1.0 / 3.0 alpha:1.0] retain];
		NSLightGray = [[NSColor colorWithDeviceWhite:2.0 / 3.0 alpha:1.0] retain];
		NSWhite = [[NSColor colorWithDeviceWhite:1.0 alpha:1.0] retain];
	}
}

- (instancetype)initWithOwnedCGColor:(CGColorRef)cg
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_cgColor = cg;      /* takes the caller's +1 */
	return self;
}

+ (nullable NSColor *)colorWithCGColor:(CGColorRef)cgColor
{
	/* THE CALLER'S REFERENCE IS RETAINED, which is what makes the returned colour independent of it —
	 * the rule `CGColorCreateCopy` follows, and the reason this is not a borrow. */
	return fn_color(CGColorRetain(cgColor));
}

- (CGColorRef)CGColor
{
	return _cgColor;
}

+ (nullable NSColor *)colorWithDeviceRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				   alpha:(CGFloat)alpha
{
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGFloat comp[4];
	CGColorRef cg;

	if (space == NULL) {
		return nil;
	}
	comp[0] = red;
	comp[1] = green;
	comp[2] = blue;
	comp[3] = alpha;
	cg = CGColorCreate(space, comp);
	CGColorSpaceRelease(space);
	return fn_color(cg);
}

+ (nullable NSColor *)colorWithDeviceWhite:(CGFloat)white alpha:(CGFloat)alpha
{
	CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
	CGFloat comp[2];
	CGColorRef cg;

	if (space == NULL) {
		return nil;
	}
	comp[0] = white;
	comp[1] = alpha;
	cg = CGColorCreate(space, comp);
	CGColorSpaceRelease(space);
	return fn_color(cg);
}

/* THE THREE RGB STORIES ARE ONE STORY HERE — see NSColor.h's deviation note. `Calibrated` and the
 * generic `colorWithRed:` route through the device constructor rather than pretending to a profile
 * this library does not ship. */
+ (nullable NSColor *)colorWithCalibratedRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				       alpha:(CGFloat)alpha
{
	return [self colorWithDeviceRed:red green:green blue:blue alpha:alpha];
}

+ (nullable NSColor *)colorWithCalibratedWhite:(CGFloat)white alpha:(CGFloat)alpha
{
	return [self colorWithDeviceWhite:white alpha:alpha];
}

+ (nullable NSColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
			     alpha:(CGFloat)alpha
{
	return [self colorWithDeviceRed:red green:green blue:blue alpha:alpha];
}

/* THE GENERIC WHITE IS THE ONE WHITE THAT HAS A PROFILE OF ITS OWN HERE, so the generic constructor
 * takes it and `+colorWithWhite:` — which Apple defines in terms of the generic space — follows. */
+ (nullable NSColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha
{
	return [self colorWithGenericGamma22White:white alpha:alpha];
}

+ (nullable NSColor *)colorWithSRGBRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				 alpha:(CGFloat)alpha
{
	return fn_color(fn_named(kCGColorSpaceSRGB, red, green, blue, alpha));
}

/* !! `+colorWithDisplayP3Red:green:blue:alpha:` STOOD HERE AND NOW REFUSES (2026-10-05). It was
 * built on `kCGColorSpaceDisplayP3`, which CoreGraphics no longer has — the name is macOS 10.11.2
 * and the duplication is a 10.6-era surface — so there is no space to build it in. THE REFUSAL IS
 * SAID OUT LOUD rather than answered with device RGB, because device RGB IS sRGB and a P3 colour
 * silently built in sRGB is a different colour with the same numbers: the caller would get a wrong
 * answer that looks right. (Apple's own `+colorWithDisplayP3Red:…` is 10.12 API, so an application
 * of the era this AppKit targets does not call it; what is owed is a decision about the AppKit's
 * own era, which is measured separately — see the AppKit ledger.) */
+ (nullable NSColor *)colorWithDisplayP3Red:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
				      alpha:(CGFloat)alpha
{
	(void)red;
	(void)green;
	(void)blue;
	(void)alpha;
	fprintf(stderr, "APPKIT-REFUSE: +colorWithDisplayP3Red:green:blue:alpha: needs "
			"kCGColorSpaceDisplayP3, which CoreGraphics removed as out of era\n");
	return nil;
}

+ (nullable NSColor *)colorWithGenericGamma22White:(CGFloat)white alpha:(CGFloat)alpha
{
	CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
	CGFloat comp[2];
	CGColorRef cg;

	if (space == NULL) {
		return nil;
	}
	comp[0] = white;
	comp[1] = alpha;
	cg = CGColorCreate(space, comp);
	CGColorSpaceRelease(space);
	return fn_color(cg);
}

- (NSUInteger)numberOfComponents
{
	return _cgColor == NULL ? 0 : (NSUInteger)CGColorGetNumberOfComponents(_cgColor);
}

- (CGFloat)alphaComponent
{
	return _cgColor == NULL ? 0.0 : CGColorGetAlpha(_cgColor);
}

/* ---- THE HSB AND CMYK TERMS, COMPUTED FROM THE RGB TRIPLE ------------------------------------- *
 * THIS LIBRARY'S ENGINE HAS NO HSB OR CMYK SPACE (C4 refuses CMYK), so these seven getters cannot ask it and
 * COMPUTE instead — which is what the header's second deviation says they do, and what `-redComponent` already
 * does for a gray colour: Apple documents an exception and converts anyway, and this tier converts in every
 * case.
 *
 * THE TWO CONVERSIONS AND THEIR GROUNDS ARE NAMED IN THE HEADER: HSB by the standard definition (brightness
 * the largest component, saturation its range over that, hue which side of the hexagon the largest falls on),
 * and CMYK by the standard subtractive separation with full black generation. BOTH ARE EXACT FOR A PURE
 * COLOUR, which is what the probe asserts — red is hue 0, saturation 1, brightness 1, and c=0, m=1, y=1, k=0.
 *
 * AND EVERY ONE OF THEM GOES THROUGH `-getRed:green:blue:alpha:`, the SHIPPED pointer form, so a grey or a
 * colour in another space is converted by the same engine path the RGB getters use rather than by a second
 * reading of the colour. */
static void fn_hsb_of(NSColor *self, CGFloat hsb[3])
{
	CGFloat r = 0.0, g = 0.0, b = 0.0;
	CGFloat max, min, range;

	[self getRed:&r green:&g blue:&b alpha:NULL];
	max = r > g ? (r > b ? r : b) : (g > b ? g : b);
	min = r < g ? (r < b ? r : b) : (g < b ? g : b);
	range = max - min;

	if (range == 0.0) {
		hsb[0] = 0.0;			/* a GREY has no side to be on; Apple's own answers 0 */
	} else if (max == r) {
		hsb[0] = (g - b) / range;	/* in [-1,1], because the range is what divides it */
		if (hsb[0] < 0.0) {
			hsb[0] += 6.0;
		}
		hsb[0] /= 6.0;
	} else if (max == g) {
		hsb[0] = ((b - r) / range + 2.0) / 6.0;
	} else {
		hsb[0] = ((r - g) / range + 4.0) / 6.0;
	}
	hsb[1] = (max == 0.0) ? 0.0 : (range / max);
	hsb[2] = max;
}

static void fn_cmyk_of(NSColor *self, CGFloat cmyk[4])
{
	CGFloat r = 0.0, g = 0.0, b = 0.0;
	CGFloat max, k;

	[self getRed:&r green:&g blue:&b alpha:NULL];
	max = r > g ? (r > b ? r : b) : (g > b ? g : b);
	k = 1.0 - max;
	if (k >= 1.0) {
		/* BLACK: every other ink is empty, which is the separation's own edge case rather than a guess. */
		cmyk[0] = cmyk[1] = cmyk[2] = 0.0;
	} else {
		cmyk[0] = (1.0 - r - k) / (1.0 - k);
		cmyk[1] = (1.0 - g - k) / (1.0 - k);
		cmyk[2] = (1.0 - b - k) / (1.0 - k);
	}
	cmyk[3] = k;
}

- (CGFloat)hueComponent
{
	CGFloat hsb[3];

	fn_hsb_of(self, hsb);
	return hsb[0];
}

- (CGFloat)saturationComponent
{
	CGFloat hsb[3];

	fn_hsb_of(self, hsb);
	return hsb[1];
}

- (CGFloat)brightnessComponent
{
	CGFloat hsb[3];

	fn_hsb_of(self, hsb);
	return hsb[2];
}

- (CGFloat)cyanComponent
{
	CGFloat cmyk[4];

	fn_cmyk_of(self, cmyk);
	return cmyk[0];
}

- (CGFloat)magentaComponent
{
	CGFloat cmyk[4];

	fn_cmyk_of(self, cmyk);
	return cmyk[1];
}

- (CGFloat)yellowComponent
{
	CGFloat cmyk[4];

	fn_cmyk_of(self, cmyk);
	return cmyk[2];
}

- (CGFloat)blackComponent
{
	CGFloat cmyk[4];

	fn_cmyk_of(self, cmyk);
	return cmyk[3];
}

- (CGFloat)redComponent
{
	CGFloat comp[4];

	if (fn_components_in(_cgColor, 1, comp) < 4) {
		fn_raise_for("redComponent");
	}
	return comp[0];
}

- (CGFloat)greenComponent
{
	CGFloat comp[4];

	if (fn_components_in(_cgColor, 1, comp) < 4) {
		fn_raise_for("greenComponent");
	}
	return comp[1];
}

- (CGFloat)blueComponent
{
	CGFloat comp[4];

	if (fn_components_in(_cgColor, 1, comp) < 4) {
		fn_raise_for("blueComponent");
	}
	return comp[2];
}

- (CGFloat)whiteComponent
{
	CGFloat comp[2];

	if (fn_components_in(_cgColor, 0, comp) < 2) {
		fn_raise_for("whiteComponent");
	}
	return comp[0];
}

- (void)getRed:(nullable CGFloat *)red green:(nullable CGFloat *)green blue:(nullable CGFloat *)blue
	 alpha:(nullable CGFloat *)alpha
{
	CGFloat comp[4];

	if (fn_components_in(_cgColor, 1, comp) < 4) {
		fn_raise_for("getRed:green:blue:alpha:");
	}
	if (red != NULL) {
		*red = comp[0];
	}
	if (green != NULL) {
		*green = comp[1];
	}
	if (blue != NULL) {
		*blue = comp[2];
	}
	if (alpha != NULL) {
		*alpha = comp[3];
	}
}

- (void)getWhite:(nullable CGFloat *)white alpha:(nullable CGFloat *)alpha
{
	CGFloat comp[2];

	if (fn_components_in(_cgColor, 0, comp) < 2) {
		fn_raise_for("getWhite:alpha:");
	}
	if (white != NULL) {
		*white = comp[0];
	}
	if (alpha != NULL) {
		*alpha = comp[1];
	}
}

- (void)getComponents:(CGFloat *)components
{
	const CGFloat *comp;
	size_t n;
	size_t i;

	if (components == NULL || _cgColor == NULL) {
		return;
	}
	/* THE COLOUR'S OWN COMPONENTS PLUS ITS ALPHA, and NO conversion: this form is documented as "the
	 * colour's components", and a caller asking for those does not want a space change. */
	comp = CGColorGetComponents(_cgColor);
	n = CGColorSpaceGetNumberOfComponents(CGColorGetColorSpace(_cgColor));
	for (i = 0; i < n; i++) {
		components[i] = comp[i];
	}
	components[n] = CGColorGetAlpha(_cgColor);
}

- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha
{
	return fn_color(CGColorCreateCopyWithAlpha(_cgColor, alpha));
}

/* A VALUE CLASS COMPARES BY VALUE, and `CGColorEqualToColor` is the comparison this library already
 * defines (space model plus components) — which is why two colours made by different constructors
 * with the same numbers ARE equal here. NSColor.h's deviation note says why that follows. */
- (BOOL)isEqual:(id)other
{
	if (other == self) {
		return YES;
	}
	if (![other isKindOfClass:[NSColor class]]) {
		return NO;
	}
	return CGColorEqualToColor(_cgColor, ((NSColor *)other)->_cgColor) ? YES : NO;
}

- (NSUInteger)hash
{
	const CGFloat *c;
	size_t n;
	size_t i;
	unsigned long h = 0;

	if (_cgColor == NULL) {
		return 0;
	}
	c = CGColorGetComponents(_cgColor);
	n = CGColorGetNumberOfComponents(_cgColor);
	for (i = 0; i < n && i < 8; i++) {
		h = h * 31u + (unsigned long)(c[i] * 1000.0 + 0.5);
	}
	return (NSUInteger)h;
}

/* `-copy` AND NOT `-copyWithZone:`, BECAUSE THIS TREE HAS NO ZONES: `NSZone` is deliberately
 * undeclared here and `NSCopying`'s only member is `-copy` (NSObject.h states the decision and its
 * cost — a Cocoa class implementing `-copyWithZone:` would not conform). A colour is immutable, so
 * the copy IS a retain, which is what a `NSCopying` value class should do. */
- (id)copy
{
	return [self retain];
}

- (void)dealloc
{
	CGColorRelease(_cgColor);
	[super dealloc];
}

+ (NSColor *)blackColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 0.0, 1.0);
}

+ (NSColor *)whiteColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)redColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 0.0, 0.0, 1.0);
}

+ (NSColor *)greenColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 1.0, 0.0, 1.0);
}

+ (NSColor *)blueColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 1.0, 1.0);
}

+ (NSColor *)cyanColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)yellowColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 0.0, 1.0);
}

+ (NSColor *)magentaColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 0.0, 1.0, 1.0);
}

+ (NSColor *)orangeColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 0.5, 0.0, 1.0);
}

+ (NSColor *)purpleColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.5, 0.0, 0.5, 1.0);
}

+ (NSColor *)brownColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.6, 0.4, 0.2, 1.0);
}

+ (NSColor *)grayColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.5, 0.5, 0.5, 1.0);
}

+ (NSColor *)darkGrayColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 1.0);
}

+ (NSColor *)lightGrayColor
{
	static NSColor *s;
	return fn_singleton(&s, 2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1.0);
}

/* THE CHROME'S TWO COLOURS, in the one kind of space this whole file builds its named colours in — and through
 * the same `fn_singleton`, so a caller that asks twice gets the object it got the first time. */
+ (NSColor *)windowFrameColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.82, 0.82, 0.84, 1.0);
}

+ (NSColor *)windowBackgroundColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.93, 0.93, 0.93, 1.0);
}

/* ---- AND THE SEMANTIC PALETTE, WHICH IS THIS TREE'S ------------------------------------------- *
 * THE HEADER STATES THE GROUND AND IT DOES NOT WEAKEN FOR THIRTY MORE COLOURS: Apple publishes no
 * components for a system colour, so a system that HAS an appearance is the authority for its own — and
 * this one does. What is Apple's is the VOCABULARY and the SHAPE (a class method, one object per colour,
 * the pairs that must contrast); what is ours is every component below.
 *
 * SO EACH LINE CARRIES THE RELATION IT EXISTS TO KEEP, because a palette whose values are ours is only
 * checkable through its relations — and the probe asserts exactly these:
 *
 *   TEXT AND ITS BACKGROUND ARE OPPOSITE, and so are the SELECTED pair: a system that drew white on
 *   white would be wrong in a way no individual value could show.
 *   THE FOUR CONTROL SHADES ARE ORDERED — dark shadow, shadow, highlight, light highlight — which is the
 *   one relation a shadow family has to keep.
 *   THE SELECTION BLUE IS ONE COLOUR IN FOUR PLACES (the selected text's background, a selected control,
 *   a selected menu item and the keyboard focus ring): Apple's own palette does the same, and a caller
 *   that tints one of them expects the others to move with it.
 *   AND DISABLED TEXT IS LIGHTER THAN ENABLED TEXT, which is the only thing "disabled" means visually. */
+ (NSColor *)textColor			/* black on white, the pair a text system starts from */
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 0.0, 1.0);
}

+ (NSColor *)textBackgroundColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)selectedTextColor		/* white on the selection blue */
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)selectedTextBackgroundColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.20, 0.42, 0.80, 1.0);
}

+ (NSColor *)controlTextColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 0.0, 1.0);
}

+ (NSColor *)disabledControlTextColor	/* lighter than the enabled one, which is all "disabled" means */
{
	static NSColor *s;
	return fn_singleton(&s, 0.50, 0.50, 0.50, 1.0);
}

+ (NSColor *)controlColor
{
	static NSColor *s;
	/* **A CONTROL'S FACE IS SLIGHTLY DARKER THAN THE WINDOW IT SITS ON, AND THE GREYS ARE ONE DIRECTION.**
	 * The window is 0.93, a control's face is 0.90, the face under the pointer is 0.88, and a disabled control's is
	 * 0.86 — four STEPS DOWN from the surface rather than a face on each side of it.
	 *
	 * IT WAS 0.95, ABOVE THE WINDOW, AND THAT ARGUMENT WAS ABOUT RAISING RATHER THAN ABOUT READING. "A button is a
	 * raised thing and raised means the light falls on it" is a reason to put a face above its surface, and 0.90 had
	 * been rejected here on the way past for reading "as a hole rather than as a button" — which is a judgement about
	 * ONE face on its own. A control is read against the one BESIDE it, though, and with the face above the window
	 * and the disabled face below it, ENABLED and DISABLED sat on opposite sides of the surface's own grey: "quieter"
	 * and "raised" pointed in two different directions and neither could be read as a step. 0.93 over 0.90 over 0.88
	 * over 0.86 is an order; what it replaces was a shape.
	 *
	 * The margin is still deliberately small — the border is what separates two shapes, and the fill only has to say
	 * which side of the surface a thing is on. */
	return fn_singleton(&s, 0.90, 0.90, 0.90, 1.0);
}

+ (NSColor *)controlBackgroundColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

/* **AND A CONTROL UNDER THE POINTER IS A STEP FURTHER DOWN — A DARKER GREY, NOT A LIGHTER ACCENT.** The pointer
 * resting on a control used to lighten its face TOWARD the accent, which gave the tier one hue meaning two different
 * things: everywhere else the accent says "being pressed" (the menu's selection chip, a selected segment, a button
 * held down), and on a prelight it said "being pointed at" instead, at a different lightness, so the same colour
 * carried two claims and neither was the stronger for it. A prelight is a shade of the SURFACE a control already sits
 * on, so it is a GREY — one step under `+controlColor`'s 0.90 and one step over `+cg_disabledControlFaceColor`'s 0.86,
 * which reads as "quieter than at rest, louder than out of action". The accent is left to mean the press.
 *
 * THE STEP IS SMALL ON PURPOSE. 0.88 against 0.90 is five levels: enough to see a face change, and far less than the
 * ink changes by, so the two channels stay separate things — the FILL says where the pointer is and the INK says
 * whether the control is being used. */
+ (NSColor *)cg_prelightControlFaceColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.88, 0.88, 0.88, 1.0);
}

/* **AND IT IS THE BOTTOM OF THE SAME SCALE RATHER THAN THE OTHER SIDE OF THE WINDOW.** 0.86 against the prelight's
 * 0.88, a control's 0.90 and `+windowBackgroundColor`'s 0.93: four steps DOWN from the surface, so a disabled face
 * is the far end of the direction an enabled one has already started in. It used to be the mirror of `+controlColor` — that face above the
 * window and this one below it — and a scale with the surface in the middle of it is a shape rather than a scale. A
 * disabled face that matched an enabled one would say nothing at all until its title was read.
 * THE INK THEN HAS TO CLEAR THE FACE, which is `disabledControlTextColor`'s 0.50 — the darkest of the greys here, and
 * the only one of them that is text. */
+ (NSColor *)cg_disabledControlFaceColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.86, 0.86, 0.86, 1.0);
}

+ (NSColor *)cg_chromeInkColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.50, 0.50, 0.50, 1.0);
}

/* **THE CHROME'S ONE SURFACE — #DEDEDE, sampled from the theme's bar and shared by BOTH halves of it.** The title bar
 * and the toolbar band are one strip, so they are one colour; a window that painted them from two doors grew a seam
 * where the numbers drifted, and the seam is what this exists to make impossible. Neutral rather than
 * `+windowFrameColor`'s faint blue: a bare grey is what the theme's own art is, and one surface has nothing to be
 * distinguished FROM. */
+ (NSColor *)cg_chromeFaceColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.871, 0.871, 0.871, 1.0);
}

/* **THE GROOVE, WHICH IS SAMPLED RATHER THAN CHOSEN.** The header carries why a scroller needs a door of its own at
 * all; the number is `Argentum Mockup.png`'s own — 217 for the track the knob runs in. THE KNOB'S EDGE IS NOT HERE:
 * it measured 188, which is `+controlDarkShadowColor`'s value, and one grey with two names is exactly the drift this
 * file's comments are about. */
+ (NSColor *)cg_scrollerTrackColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.85, 0.85, 0.85, 1.0);
}

+ (NSColor *)controlShadowColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.60, 0.60, 0.60, 1.0);
}

/* **THE BORDER'S GREY, AND ITS VALUE IS THE SAMPLE'S RATHER THAN A STEP THIS FILE PICKED.** This is the ink a bezel, a
 * checkbox's box, a field's edge and a slider's track are STROKED or filled with — the outline that says where a
 * control's surface ENDS.
 *
 * IT WAS 0.55, AND THE ARGUMENT FOR THAT WAS THE RIGHT ONE ARGUED ON THE WRONG EVIDENCE. 0.40 had read as a hard line
 * drawn ON the face rather than as the edge OF it, so the value came up until it did not — which is a judgement, and a
 * judgement is the thing `Argentum Mockup.png` exists to end. The sample answers with a NUMBER, and it answers the
 * same number everywhere the question can be asked: the border of its `NSPopUpButton`'s field (x=919, x=1069 and
 * y=398 of that row, one point each) and the outline of its scroller's knob both measure `#BCBCBC` — 188, 0.737.
 *
 * AND IT LANDS ON A VALUE THIS FILE WAS ALREADY CARRYING UNDER ANOTHER NAME. `+cg_scrollerKnobEdgeColor` was measured
 * off the same sample at the same 0.737, so that door is GONE: a knob's outline and a field's border are one grey, and
 * the scroller has one fewer name for one more thing, which is the trade this file spends its comments arguing for. */
+ (NSColor *)controlDarkShadowColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.737, 0.737, 0.737, 1.0);
}

+ (NSColor *)controlHighlightColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.95, 0.95, 0.95, 1.0);
}

+ (NSColor *)controlLightHighlightColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)selectedControlColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.20, 0.42, 0.80, 1.0);
}

/* **THE ACCENT, AND WHY IT IS A LITERAL HERE RATHER THAN A BLEND ANYWHERE ELSE.** 164/255 = 0.643, 154/255 = 0.604
 * and 255/255 = 1.0, which is the platform's own chip as it was SAMPLED — so the numbers are the record, not a
 * formula that happens to land near them. `NSMenuView`'s gradient used to carry this same triple as six `#define`s of
 * its own (§A10..); it now asks this door, which is the difference between one accent and two that agree today. */
+ (NSColor *)cg_accentColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.643, 0.604, 1.0, 1.0);
}

+ (NSColor *)selectedControlTextColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)secondarySelectedControlColor	/* the same colour, drained, for a background selection */
{
	static NSColor *s;
	return fn_singleton(&s, 0.55, 0.65, 0.85, 1.0);
}

+ (NSColor *)alternateSelectedControlColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.35, 0.55, 0.90, 1.0);
}

+ (NSColor *)alternateSelectedControlTextColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)keyboardFocusIndicatorColor	/* the selection blue again: one colour, four places */
{
	static NSColor *s;
	return fn_singleton(&s, 0.20, 0.42, 0.80, 1.0);
}

+ (NSColor *)headerColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.90, 0.90, 0.90, 1.0);
}

+ (NSColor *)headerTextColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 0.0, 1.0);
}

+ (NSColor *)gridColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.80, 0.80, 0.80, 1.0);
}

+ (NSColor *)shadowColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 0.0, 1.0);
}

+ (NSColor *)highlightColor		/* a TRANSLUCENT white, which is what a highlight is for: the one
					 * non-opaque value in the palette, and it is deliberate */
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 0.5);
}

+ (NSColor *)knobColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.80, 0.80, 0.80, 1.0);
}

+ (NSColor *)selectedKnobColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.60, 0.60, 0.60, 1.0);
}

+ (NSColor *)scrollBarColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.85, 0.85, 0.85, 1.0);
}

+ (NSColor *)selectedMenuItemColor	/* the selection blue, a third time */
{
	static NSColor *s;
	return fn_singleton(&s, 0.20, 0.42, 0.80, 1.0);
}

+ (NSColor *)selectedMenuItemTextColor
{
	static NSColor *s;
	return fn_singleton(&s, 1.0, 1.0, 1.0, 1.0);
}

+ (NSColor *)windowFrameTextColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 0.0, 1.0);
}

/* AND THE ONE THAT IS AN ARRAY RATHER THAN A COLOUR: a table's alternating rows are TWO colours, and Apple's
 * accessor answers them in one call. It is built through the same singletons, so the pair is stable too. */
+ (NSArray *)controlAlternatingRowBackgroundColors
{
	return [NSArray arrayWithObjects:[NSColor controlBackgroundColor],
					 [NSColor windowBackgroundColor], nil];
}

/* AND THE USER SETTING THIS TIER HAS NO HOLDER FOR. A control tint is which tint a PERSON chose, and an
 * appearance system is what remembers one — the same ground the three key-repeat intervals stand on in
 * NSEvent: the value exists on a real system, belongs to the window server, and a second copy here would
 * drift. The empty value is answered and the reason is printed. */
+ (NSUInteger)currentControlTint
{
	fprintf(stderr, "APPKIT-REFUSE: +currentControlTint needs an appearance system to hold the user's "
			"choice of tint; this tier has none, so the answer is the empty value rather than a "
			"tint nobody chose\n");
	return 0;
}

+ (NSColor *)clearColor
{
	static NSColor *s;
	return fn_singleton(&s, 0.0, 0.0, 0.0, 0.0);
}

/* ============================================================================================ *
 * THE ERA'S REMAINING DOORS.                                                                     *
 * ============================================================================================ */

/* THE COLOUR-SPACE NAME THAT CAN BE MADE, or NULL for one this layer has no space for. It is ONE
 * function because four doors need the same answer: two component getters, the conversion door and the
 * pasteboard round trip. The two CALIBRATED names go through `CGColorSpaceCreateWithName`, which is where
 * this tree's generic (gamma-2.2/D50) spaces live — the same pair the file's header note measures. */
static CGColorSpaceRef fn_space_for_name(NSString *name)
{
	if (name == nil) {
		return NULL;
	}
	if ([name isEqualToString:NSDeviceRGBColorSpace]) {
		return CGColorSpaceCreateDeviceRGB();
	}
	if ([name isEqualToString:NSDeviceWhiteColorSpace] ||
	    [name isEqualToString:NSDeviceGrayColorSpace]) {
		return CGColorSpaceCreateDeviceGray();
	}
	if ([name isEqualToString:NSDeviceCMYKColorSpace]) {
		return CGColorSpaceCreateDeviceCMYK();
	}
	if ([name isEqualToString:NSCalibratedRGBColorSpace]) {
		return CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
	}
	if ([name isEqualToString:NSCalibratedWhiteColorSpace]) {
		return CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
	}
	/* `NSNamedColorSpace`, `NSPatternColorSpace` and `NSCustomColorSpace` are DECLARED names with no
	 * space behind them here — a catalog list, a tiled pattern and a custom gstate respectively — so
	 * they answer NULL rather than a space that would mean something else. */
	return NULL;
}

/* HUE/SATURATION/BRIGHTNESS OUT OF RGB, and back. The forward direction is the standard piecewise ramp;
 * the reverse is the maximum/minimum form. Both take and give a hue in TURNS (0…1), which is the unit
 * Apple's own doors use, and both are here rather than in a getter because three doors need them (two
 * constructors and `-getHue:…`). */
static void fn_rgb_to_hsv(CGFloat r, CGFloat g, CGFloat b, CGFloat *h, CGFloat *s, CGFloat *v)
{
	CGFloat max = r > g ? (r > b ? r : b) : (g > b ? g : b);
	CGFloat min = r < g ? (r < b ? r : b) : (g < b ? g : b);
	CGFloat d = max - min;

	*v = max;
	*s = max <= 0.0 ? 0.0 : d / max;
	if (d <= 0.0) {
		*h = 0.0;
		return;
	}
	if (max == r) {
		*h = (g - b) / d;
	} else if (max == g) {
		*h = 2.0 + (b - r) / d;
	} else {
		*h = 4.0 + (r - g) / d;
	}
	*h /= 6.0;
	if (*h < 0.0) {
		*h += 1.0;
	}
}

static void fn_hsv_to_rgb(CGFloat h, CGFloat s, CGFloat v, CGFloat *r, CGFloat *g, CGFloat *b)
{
	CGFloat i, f, p, q, t;

	if (s <= 0.0) {
		*r = *g = *b = v;
		return;
	}
	h = h - floor(h);          /* the hue is in turns, so a value outside 0…1 wraps rather than clamps */
	h *= 6.0;
	i = floor(h);
	f = h - i;
	p = v * (1.0 - s);
	q = v * (1.0 - s * f);
	t = v * (1.0 - s * (1.0 - f));
	switch ((int)i) {
	case 0: *r = v; *g = t; *b = p; break;
	case 1: *r = q; *g = v; *b = p; break;
	case 2: *r = p; *g = v; *b = t; break;
	case 3: *r = p; *g = q; *b = v; break;
	case 4: *r = t; *g = p; *b = v; break;
	default: *r = v; *g = p; *b = q; break;
	}
}

+ (nullable NSColor *)colorWithCalibratedHue:(CGFloat)hue saturation:(CGFloat)saturation
				  brightness:(CGFloat)brightness alpha:(CGFloat)alpha
{
	CGFloat r, g, b;

	fn_hsv_to_rgb(hue, saturation, brightness, &r, &g, &b);
	return fn_color(fn_named(kCGColorSpaceGenericRGB, r, g, b, alpha));
}

+ (nullable NSColor *)colorWithDeviceHue:(CGFloat)hue saturation:(CGFloat)saturation
			      brightness:(CGFloat)brightness alpha:(CGFloat)alpha
{
	CGFloat r, g, b;

	fn_hsv_to_rgb(hue, saturation, brightness, &r, &g, &b);
	return [self colorWithDeviceRed:r green:g blue:b alpha:alpha];
}

/* CMYK IN, RGB OUT. Cyan/magenta/yellow are the ink amounts and black is the black plate, so the
 * subtractive pair is `(1 - ink) * (1 - black)` per channel — the standard conversion, and OURS in the
 * sense that Apple's goes through a colour engine this layer does not have. The reverse door below uses
 * the same arithmetic in the other direction. */
+ (nullable NSColor *)colorWithDeviceCyan:(CGFloat)cyan magenta:(CGFloat)magenta yellow:(CGFloat)yellow
				    black:(CGFloat)black alpha:(CGFloat)alpha
{
	return [self colorWithDeviceRed:(1.0 - cyan) * (1.0 - black)
				  green:(1.0 - magenta) * (1.0 - black)
				   blue:(1.0 - yellow) * (1.0 - black)
				  alpha:alpha];
}

- (void)getHue:(nullable CGFloat *)hue saturation:(nullable CGFloat *)saturation
    brightness:(nullable CGFloat *)brightness alpha:(nullable CGFloat *)alpha
{
	CGFloat c[4];
	CGFloat h, s, v;

	if (fn_components_in(_cgColor, 1, c) < 4) {
		fn_raise_for("getHue:saturation:brightness:alpha:");
		return;
	}
	fn_rgb_to_hsv(c[0], c[1], c[2], &h, &s, &v);
	if (hue != NULL) *hue = h;
	if (saturation != NULL) *saturation = s;
	if (brightness != NULL) *brightness = v;
	if (alpha != NULL) *alpha = c[3];
}

- (void)getCyan:(nullable CGFloat *)cyan magenta:(nullable CGFloat *)magenta yellow:(nullable CGFloat *)yellow
	  black:(nullable CGFloat *)black alpha:(nullable CGFloat *)alpha
{
	CGFloat c[4];
	CGFloat k, denom;

	if (fn_components_in(_cgColor, 1, c) < 4) {
		fn_raise_for("getCyan:magenta:yellow:black:alpha:");
		return;
	}
	k = 1.0 - (c[0] > c[1] ? (c[0] > c[2] ? c[0] : c[2]) : (c[1] > c[2] ? c[1] : c[2]));
	denom = 1.0 - k;
	if (cyan != NULL) *cyan = denom <= 0.0 ? 0.0 : (1.0 - c[0] - k) / denom;
	if (magenta != NULL) *magenta = denom <= 0.0 ? 0.0 : (1.0 - c[1] - k) / denom;
	if (yellow != NULL) *yellow = denom <= 0.0 ? 0.0 : (1.0 - c[2] - k) / denom;
	if (black != NULL) *black = k;
	if (alpha != NULL) *alpha = c[3];
}

/* THE THREE RAMP DOORS. `fraction` and `level` are both "how far toward the other end", and the ends are
 * Apple's own sentence for this pair: `level = 0` is the receiver and `1` is the highlight or shadow
 * colour — which for these two doors is white and black, so the arithmetic is a scalar move in RGB. A
 * colour that cannot be read as RGB refuses by name rather than raising. */
- (nullable NSColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(nullable NSColor *)color
{
	CGFloat a[4], b[4], out[4];
	int i;

	if (color == nil) {
		return nil;
	}
	if (fn_components_in(_cgColor, 1, a) < 4 || fn_components_in([color CGColor], 1, b) < 4) {
		fprintf(stderr, "APPKIT-REFUSE: -blendedColorWithFraction:ofColor: needs both colours "
				"expressible as RGB\n");
		return nil;
	}
	for (i = 0; i < 4; i++) {
		out[i] = a[i] + (b[i] - a[i]) * fraction;
	}
	return [NSColor colorWithDeviceRed:out[0] green:out[1] blue:out[2] alpha:out[3]];
}

- (nullable NSColor *)highlightWithLevel:(CGFloat)val
{
	CGFloat c[4];
	int i;

	if (fn_components_in(_cgColor, 1, c) < 4) {
		fprintf(stderr, "APPKIT-REFUSE: -highlightWithLevel: needs a colour expressible as RGB\n");
		return nil;
	}
	for (i = 0; i < 3; i++) {
		c[i] = c[i] + (1.0 - c[i]) * val;
	}
	return [NSColor colorWithDeviceRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
}

- (nullable NSColor *)shadowWithLevel:(CGFloat)val
{
	CGFloat c[4];
	int i;

	if (fn_components_in(_cgColor, 1, c) < 4) {
		fprintf(stderr, "APPKIT-REFUSE: -shadowWithLevel: needs a colour expressible as RGB\n");
		return nil;
	}
	for (i = 0; i < 3; i++) {
		c[i] = c[i] * (1.0 - val);
	}
	return [NSColor colorWithDeviceRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
}

/* AND THE CASE THE RAMP CONVENTION NAMES: `level = 0` answers the RECEIVER, which is worth a check
 * because an implementation that blended toward white unconditionally would pass every other case. */
+ (nullable NSColor *)colorForControlTint:(NSControlTint)controlTint
{
	/* THE THREE TINTS AND THE FALLBACK, and the fallback is Apple's own sentence: an INVALID tint answers
	 * the default. The values are OURS — an appearance's exact blues and greys are Apple's artwork — and
	 * the probe asserts the SHAPE (graphite is grey, clear is not, an invalid tint equals the default)
	 * rather than a pixel nobody published. */
	switch (controlTint) {
	case NSGraphiteControlTint:
		return [self colorWithDeviceWhite:0.55 alpha:1.0];
	case NSClearControlTint:
		return [self colorWithDeviceRed:0.45 green:0.62 blue:0.85 alpha:1.0];
	case NSBlueControlTint:
	case NSDefaultControlTint:
	default:
		return [self colorWithDeviceRed:0.20 green:0.42 blue:0.90 alpha:1.0];
	}
}

/* THE CATALOG AND THE PATTERN REFUSE BY NAME. A catalog colour needs `NSColorList` — a named collection
 * read from disk — and a pattern colour needs a `CGPattern`-backed `CGColor` to draw through; this tree
 * has neither, and a colour object holding an image it cannot tile would be a half-implementation. */
+ (nullable NSColor *)colorWithCatalogName:(NSString *)listName colorName:(NSString *)colorName
{
	(void)colorName;
	fprintf(stderr, "APPKIT-REFUSE: +colorWithCatalogName:colorName: needs NSColorList, the catalog "
			"colour collections read from disk, and this tree has none (asked for \"%s\")\n",
		listName == nil ? "" : [listName UTF8String]);
	return nil;
}

+ (nullable NSColor *)colorWithPatternImage:(NSImage *)image
{
	(void)image;
	fprintf(stderr, "APPKIT-REFUSE: +colorWithPatternImage: needs a CGPattern-backed CGColor to draw "
			"a tiled image through, and this tree's CGColor bridge has none — holding the image "
			"without a way to tile it would be a half-implementation\n");
	return nil;
}

/* ---- THE PASTEBOARD PAIR, OVER A FORMAT THAT IS OURS ---------------------------------------- */
/* APPLE'S PASTEBOARD COLOUR FORMAT IS ITS OWN PROPERTY LIST, so this pair writes a plist of OUR shape:
 * the colour-space MODEL as a number and the components as numbers, which is everything needed to build
 * the same CGColor back. That is a stated deviation in the DATA rather than in the API, and the probe
 * asserts the round trip rather than the bytes. A colour whose space this layer cannot name refuses. */
- (void)writeToPasteboard:(NSPasteboard *)pasteBoard
{
	CGColorSpaceRef space;
	NSMutableArray *comps;
	const CGFloat *c;
	size_t i, n;
	NSDictionary *plist;

	if (pasteBoard == nil || _cgColor == NULL) {
		return;
	}
	space = CGColorGetColorSpace(_cgColor);
	c = CGColorGetComponents(_cgColor);
	n = CGColorGetNumberOfComponents(_cgColor);
	if (space == NULL || c == NULL || n == 0) {
		return;
	}
	comps = [NSMutableArray array];
	for (i = 0; i < n; i++) {
		[comps addObject:[NSNumber numberWithDouble:(double)c[i]]];
	}
	plist = [NSDictionary dictionaryWithObjectsAndKeys:
		 [NSNumber numberWithInt:(int)CGColorSpaceGetModel(space)], @"model",
		 comps, @"components", nil];
	[pasteBoard declareTypes:[NSArray arrayWithObject:NSColorPboardType] owner:nil];
	[pasteBoard setPropertyList:plist forType:NSColorPboardType];
}

+ (nullable NSColor *)colorFromPasteboard:(NSPasteboard *)pasteBoard
{
	id plist;
	NSArray *comps;
	NSNumber *model;
	CGColorSpaceRef space;
	CGFloat c[5];
	NSUInteger i, n;
	CGColorRef cg;

	if (pasteBoard == nil) {
		return nil;
	}
	plist = [pasteBoard propertyListForType:NSColorPboardType];
	if (![plist isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	model = [(NSDictionary *)plist objectForKey:@"model"];
	comps = [(NSDictionary *)plist objectForKey:@"components"];
	if (model == nil || ![comps isKindOfClass:[NSArray class]]) {
		return nil;
	}
	switch ([model intValue]) {
	case kCGColorSpaceModelRGB: space = CGColorSpaceCreateDeviceRGB(); break;
	case kCGColorSpaceModelMonochrome: space = CGColorSpaceCreateDeviceGray(); break;
	case kCGColorSpaceModelCMYK: space = CGColorSpaceCreateDeviceCMYK(); break;
	default:
		fprintf(stderr, "APPKIT-REFUSE: +colorFromPasteboard: this board's colour is in a space this "
				"layer cannot rebuild\n");
		return nil;
	}
	n = [comps count];
	if (n == 0 || n > 5 || space == NULL) {
		if (space != NULL) {
			CGColorSpaceRelease(space);
		}
		return nil;
	}
	for (i = 0; i < n; i++) {
		c[i] = (CGFloat)[(NSNumber *)[comps objectAtIndex:i] doubleValue];
	}
	cg = CGColorCreate(space, c);
	CGColorSpaceRelease(space);
	return fn_color(cg);
}

/* ---- SETTING THE COLOUR IN A CONTEXT ------------------------------------------------------- */
/* `-setFill` AND `-setStroke` REACH THE CURRENT CONTEXT'S STATE, which is what makes them different from
 * the `-set` of the drawing classes: this is the colour the NEXT fill or stroke uses. With no context the
 * door prints why rather than doing nothing quiet. */
/* ---- AND +IGNORESALPHA, WHOSE READERS ARE THE TWO DOORS BELOW ---------------------------------- *
 * THIS IS THE ONE ROW THE CLASS LEFT OWED UNTIL THIS UNIT, and it was left owed for the right reason: a
 * stored flag with no reader is what this tree refuses, so the flag waited for the doors that would read it.
 * Apple's own words are that the alpha component is IGNORED when the colour is used — a global switch on how
 * a colour is DRAWN — and this class has exactly two doors that put a colour into a context, which are
 * `-setFill` and `-setStroke` immediately below. Each writes the colour OPAQUE while the flag is on, through
 * the class's own `-colorWithAlphaComponent:` rather than a Core Graphics copy constructor, so the two places
 * a colour reaches a context cannot disagree about what "opaque" means.
 *
 * THE DEFAULT IS OFF, which is what makes "the alpha is ignored" opt-in. */
static BOOL s_ignoresAlpha;

+ (BOOL)ignoresAlpha
{
	return s_ignoresAlpha;
}

+ (void)setIgnoresAlpha:(BOOL)flag
{
	s_ignoresAlpha = flag ? YES : NO;
}

- (void)setFill
{
	NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
	CGContextRef c = ctx != nil ? [ctx CGContext] : NULL;

	if (c == NULL || _cgColor == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -setFill needs a current graphics context and a colour\n");
		return;
	}
	/* +IGNORESALPHA IS READ HERE, WHICH IS THE WHOLE REASON THE FLAG SHIPS AT ALL. */
	CGContextSetFillColorWithColor(c, s_ignoresAlpha ? [[self colorWithAlphaComponent:1.0] CGColor]
							 : _cgColor);
}

- (void)setStroke
{
	NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
	CGContextRef c = ctx != nil ? [ctx CGContext] : NULL;

	if (c == NULL || _cgColor == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -setStroke needs a current graphics context and a colour\n");
		return;
	}
	/* AND HERE TOO, because a stroke is the other way a colour is drawn. */
	CGContextSetStrokeColorWithColor(c, s_ignoresAlpha ? [[self colorWithAlphaComponent:1.0] CGColor]
							   : _cgColor);
}

/* AND THE SWATCH, which is the one DRAWING door on this class: the rect is filled with the colour in the
 * current context. A colour that cannot be expressed there is refused by the context's own path. */
- (void)drawSwatchInRect:(NSRect)rect
{
	NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
	CGContextRef c = ctx != nil ? [ctx CGContext] : NULL;

	if (c == NULL || _cgColor == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -drawSwatchInRect: needs a current graphics context and a "
				"colour\n");
		return;
	}
	/* **AND IT GOES THROUGH `-setFill` RATHER THAN REACHING FOR THE CONTEXT'S FILL COLOUR ITSELF**, which is
	 * what it used to do and is a defect once `+ignoresAlpha` exists: that flag is a global switch on HOW A
	 * COLOUR IS DRAWN, so a door that draws a colour and ignores the switch is a door the switch does not
	 * reach. THE FIX IS NOT A SECOND READ OF THE FLAG — it is to make the swatch USE the fill door, so there
	 * is one place in this class where a fill colour is decided and no third copy to keep in step. */
	[self setFill];
	CGContextFillRect(c, NSRectToCGRect(rect));
}

/* THE CONVERSION DOOR, OVER THE FIVE NAMES THIS LAYER CAN MAKE A SPACE FOR. Apple's takes a NAME and an
 * optional device description; the description is a hint about the output device and this tree draws to
 * one surface, so it is taken and unused rather than silently reinterpreted. A name with no space behind
 * it refuses by name instead of answering a colour in the wrong space. */
- (nullable NSColor *)colorUsingColorSpaceName:(NSString *)colorSpace
{
	return [self colorUsingColorSpaceName:colorSpace device:nil];
}

- (nullable NSColor *)colorUsingColorSpaceName:(NSString *)colorSpace device:(nullable NSDictionary *)deviceDescription
{
	CGColorSpaceRef space;
	CGColorRef cg = NULL;
	CGFloat c[5];
	int model;

	(void)deviceDescription;
	if (colorSpace == nil) {
		return nil;
	}
	space = fn_space_for_name(colorSpace);
	if (space == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -colorUsingColorSpaceName: has no space for THIS name — "
				"NSNamedColorSpace, NSPatternColorSpace and NSCustomColorSpace are declared names "
				"with no space behind them here\n");
		return nil;
	}
	model = CGColorSpaceGetModel(space);
	if (model == kCGColorSpaceModelRGB) {
		if (fn_components_in(_cgColor, 1, c) < 4) {
			CGColorSpaceRelease(space);
			return nil;
		}
	} else if (model == kCGColorSpaceModelMonochrome) {
		if (fn_components_in(_cgColor, 0, c) < 2) {
			CGColorSpaceRelease(space);
			return nil;
		}
	} else if (model == kCGColorSpaceModelCMYK) {
		CGFloat rgb[4];
		CGFloat k, denom;

		if (fn_components_in(_cgColor, 1, rgb) < 4) {
			CGColorSpaceRelease(space);
			return nil;
		}
		/* THE SUBTRACTIVE TRIP, the inverse of `+colorWithDeviceCyan:…` above. */
		k = 1.0 - (rgb[0] > rgb[1] ? (rgb[0] > rgb[2] ? rgb[0] : rgb[2])
					   : (rgb[1] > rgb[2] ? rgb[1] : rgb[2]));
		denom = 1.0 - k;
		c[0] = denom <= 0.0 ? 0.0 : (1.0 - rgb[0] - k) / denom;
		c[1] = denom <= 0.0 ? 0.0 : (1.0 - rgb[1] - k) / denom;
		c[2] = denom <= 0.0 ? 0.0 : (1.0 - rgb[2] - k) / denom;
		c[3] = k;
		c[4] = rgb[3];
	} else {
		CGColorSpaceRelease(space);
		return nil;
	}
	cg = CGColorCreate(space, c);
	CGColorSpaceRelease(space);
	return fn_color(cg);
}

/* ---- THE CATALOG NAMES, WHICH THIS TIER ANSWERS RATHER THAN RAISES ----------------------------- *
 * THE ERA'S OWN NOTE SAYS WHAT APPLE DOES: "Not all of the methods apply to all colors; if called, they
 * raise." This tier's rule for a component it cannot answer is the one this class's own header states —
 * CONVERT RATHER THAN RAISE — and here there is nothing to convert: a catalog is a list of NAMED colours
 * looked up on a device, and this tree has no catalog at all. So the answer is nil with the reason printed,
 * which is the shape every other refusal in this file takes. */
static void fn_refuse_catalog(const char *which)
{
	fprintf(stderr, "APPKIT-REFUSE: %s needs a colour catalog — a list of named colours looked up on a "
			"device — and this tree has none, so the answer is nil rather than a name nobody gave\n",
		which);
}

- (NSString *)catalogNameComponent
{
	fn_refuse_catalog("-catalogNameComponent");
	return nil;
}

- (NSString *)colorNameComponent
{
	fn_refuse_catalog("-colorNameComponent");
	return nil;
}

- (NSString *)localizedCatalogNameComponent
{
	fn_refuse_catalog("-localizedCatalogNameComponent");
	return nil;
}

- (NSString *)localizedColorNameComponent
{
	fn_refuse_catalog("-localizedColorNameComponent");
	return nil;
}

/* AND THIS ONE IS NOT A REFUSAL, WHICH IS WHY IT IS NOT WITH THE FOUR ABOVE: nil is the WHOLE TRUTH here.
 * A pattern colour cannot exist in this class at all — `+colorWithPatternImage:` refuses for want of a
 * `CGPattern`-backed `CGColor` to tile an image through — so NO colour this tree can make has an image
 * behind it. That is a fact about the CLASS rather than about the caller, which is why no reason is
 * printed: every caller asking gets the same honest answer. */
- (NSImage *)patternImage
{
	return nil;
}

/* ---- AND THE THREE THAT TAKE A TYPE THIS TREE HAS NOT GOT -------------------------------------- *
 * Two take an `NSColorSpace` and one a `CIColor`, AND BOTH TYPES ARE SPELLED `id` FOR THE OVER-CREDITING
 * RULE this tree states wherever an unshipped class would otherwise be named: the ledger counts a forward
 * declaration as declaring the class, so `@class NSColorSpace;` would credit twenty-eight of that class's
 * rows to this one. Each answers nil with the subsystem it needs. */
+ (nullable NSColor *)colorWithCIColor:(id)ciColor
{
	(void)ciColor;
	fprintf(stderr, "APPKIT-REFUSE: +colorWithCIColor: needs Core Image, which this tree has not got\n");
	return nil;
}

+ (nullable NSColor *)colorWithColorSpace:(id)space
			       components:(const CGFloat *)components
				    count:(NSInteger)numberOfComponents
{
	(void)space;
	(void)components;
	(void)numberOfComponents;
	fprintf(stderr, "APPKIT-REFUSE: +colorWithColorSpace:components:count: takes an NSColorSpace, a class "
			"this tier does not ship; the spaces it DOES have are the rgb and gray models its own "
			"constructors name\n");
	return nil;
}

- (nullable NSColor *)colorUsingColorSpace:(id)space
{
	(void)space;
	fprintf(stderr, "APPKIT-REFUSE: -colorUsingColorSpace: takes an NSColorSpace, a class this tier does "
			"not ship; a colour converts through the engine only into the spaces this class's own "
			"getters ask for\n");
	return nil;
}

@end
