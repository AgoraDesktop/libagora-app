/*
 * NSGraphicsContext — the seam: a CGContextRef behind an object, and the two state stacks.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THERE ARE TWO STACKS HERE AND CONFLATING THEM IS THE ONLY REAL MISTAKE THIS FILE CAN MAKE.
 * `-saveGraphicsState`/`-restoreGraphicsState` are the RECEIVER's, and they are pure forwards to
 * `CGContextSaveGState`/`CGContextRestoreGState` — the C2 state stack inside CoreGraphics, which
 * this file neither owns nor knows the depth of. `+saveGraphicsState`/`+restoreGraphicsState` are
 * the CLASS's, and they push and pop a per-thread stack OF CONTEXTS *as well as* sending the
 * context its own save or restore. A caller can therefore nest either without touching the other,
 * and the probe checks the pair separately for exactly that reason.
 *
 * THE PER-THREAD STORAGE IS `__thread` AND THAT HAS ONE COST, STATED RATHER THAN DISCOVERED: a
 * thread that exits while it holds a current context never releases it, because nothing runs then.
 * The alternative — one global — would make two threads' draws collide, so the leak is the cheaper
 * of the two mistakes, and the caller who set the context owns it anyway (this object does not
 * retain it; see the header).
 */
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBitmapImageRep.h>
#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGContext.h>

#include <stdio.h>

/* THE PER-THREAD CURRENT CONTEXT, and the per-thread stack of saved ones. The depth bound is the
 * same kind of bound the graphics state's dash array has, and it is refused rather than wrapped for
 * the same reason: a stack that silently dropped its bottom entry would restore the wrong context
 * and look deliberate doing it. */
#define APPKIT_GSTATE_STACK_MAX 64

static __thread NSGraphicsContext *fn_current;
static __thread NSGraphicsContext *fn_stack[APPKIT_GSTATE_STACK_MAX];
static __thread int fn_depth;

/* THE THIRTEEN LEGACY ALIASES, DEFINED HERE. Each is the LIVE case's own value, so the two spellings
 * are one number — see the header for why `NSCompositeHighlight` is the one name that cannot be an
 * alias (the era's 12 for Highlight is this enum's 12 for PlusLighter). */
const NSCompositingOperation NSCompositeClear = NSCompositingOperationClear;
const NSCompositingOperation NSCompositeCopy = NSCompositingOperationCopy;
const NSCompositingOperation NSCompositeSourceOver = NSCompositingOperationSourceOver;
const NSCompositingOperation NSCompositeSourceIn = NSCompositingOperationSourceIn;
const NSCompositingOperation NSCompositeSourceOut = NSCompositingOperationSourceOut;
const NSCompositingOperation NSCompositeSourceAtop = NSCompositingOperationSourceAtop;
const NSCompositingOperation NSCompositeDestinationOver = NSCompositingOperationDestinationOver;
const NSCompositingOperation NSCompositeDestinationIn = NSCompositingOperationDestinationIn;
const NSCompositingOperation NSCompositeDestinationOut = NSCompositingOperationDestinationOut;
const NSCompositingOperation NSCompositeDestinationAtop = NSCompositingOperationDestinationAtop;
const NSCompositingOperation NSCompositeXOR = NSCompositingOperationXOR;
const NSCompositingOperation NSCompositePlusDarker = NSCompositingOperationPlusDarker;
const NSCompositingOperation NSCompositePlusLighter = NSCompositingOperationPlusLighter;

/* THE ENUM TO THE OPERATOR, ONE FOR ONE. `CGBlendMode`'s names track `NSCompositingOperation`'s
 * from `Clear` down to `Luminosity`, so this is a switch and not a table — and EVERY declared case
 * has a target now, `PlusDarker` included: CoreGraphics composites it BY HAND (coregraphics-plan
 * §44), so there is no operator-less case left to refuse. `*ok` and the `default` arm are kept as a
 * GUARD for a value outside the declared set — a caller passing one of the struck legacy names
 * numerically — and the setter turns a false `*ok` into a message rather than silently drawing the
 * nearest available thing. */
static CGBlendMode fn_blend_mode(NSCompositingOperation op, int *ok)
{
	*ok = 1;
	switch (op) {
	case NSCompositingOperationClear: return kCGBlendModeClear;
	case NSCompositingOperationCopy: return kCGBlendModeCopy;
	case NSCompositingOperationSourceOver: return kCGBlendModeNormal;
	case NSCompositingOperationSourceIn: return kCGBlendModeSourceIn;
	case NSCompositingOperationSourceOut: return kCGBlendModeSourceOut;
	case NSCompositingOperationSourceAtop: return kCGBlendModeSourceAtop;
	case NSCompositingOperationDestinationOver: return kCGBlendModeDestinationOver;
	case NSCompositingOperationDestinationIn: return kCGBlendModeDestinationIn;
	case NSCompositingOperationDestinationOut: return kCGBlendModeDestinationOut;
	case NSCompositingOperationDestinationAtop: return kCGBlendModeDestinationAtop;
	case NSCompositingOperationXOR: return kCGBlendModeXOR;
	case NSCompositingOperationPlusDarker: return kCGBlendModePlusDarker;
	case NSCompositingOperationPlusLighter: return kCGBlendModePlusLighter;
	case NSCompositingOperationMultiply: return kCGBlendModeMultiply;
	case NSCompositingOperationScreen: return kCGBlendModeScreen;
	case NSCompositingOperationOverlay: return kCGBlendModeOverlay;
	case NSCompositingOperationDarken: return kCGBlendModeDarken;
	case NSCompositingOperationLighten: return kCGBlendModeLighten;
	case NSCompositingOperationColorDodge: return kCGBlendModeColorDodge;
	case NSCompositingOperationColorBurn: return kCGBlendModeColorBurn;
	case NSCompositingOperationSoftLight: return kCGBlendModeSoftLight;
	case NSCompositingOperationHardLight: return kCGBlendModeHardLight;
	case NSCompositingOperationDifference: return kCGBlendModeDifference;
	case NSCompositingOperationExclusion: return kCGBlendModeExclusion;
	case NSCompositingOperationHue: return kCGBlendModeHue;
	case NSCompositingOperationSaturation: return kCGBlendModeSaturation;
	case NSCompositingOperationColor: return kCGBlendModeColor;
	case NSCompositingOperationLuminosity: return kCGBlendModeLuminosity;
	default:
		*ok = 0;
		return kCGBlendModeNormal;
	}
}

@implementation NSGraphicsContext
/* THE FOUR NAMES, DEFINED HERE. Their values are their own identifiers — the rule this tier follows where
 * Apple publishes a symbol and not a string — and the two FORMAT names are what a caller passes as the VALUE
 * of the representation-format attribute. */
NSString *NSGraphicsContextDestinationAttributeName = @"NSGraphicsContextDestinationAttributeName";
NSString *NSGraphicsContextRepresentationFormatAttributeName =
	@"NSGraphicsContextRepresentationFormatAttributeName";
NSString *NSGraphicsContextPSFormat = @"NSGraphicsContextPSFormat";
NSString *NSGraphicsContextPDFFormat = @"NSGraphicsContextPDFFormat";


/* THE DEFAULTS LIVE IN `-init` AND NOT IN THE FACTORY, so that `alloc`/`init` — the path that makes
 * a CONTEXT-LESS object, which the probe covers — starts from the same state as the factory does.
 * AND THEY ARE NOT OPTIONAL, because `alloc` ZEROES THE IVARS: without this a fresh object would
 * report antialiasing OFF (not the context's default of on) and a compositing operation of `Clear`,
 * which is what enum value 0 happens to be and is not `SourceOver`. Three quiet wrong answers, all
 * of them wrong in the direction of "draws nothing". */
- (instancetype)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_shouldAntialias = YES;
	_patternPhase = NSMakePoint(0.0, 0.0);
	_compositingOperation = NSCompositingOperationSourceOver;
	return self;
}

+ (nullable NSGraphicsContext *)graphicsContextWithCGContext:(CGContextRef)cgContext
                                                    flipped:(BOOL)initialFlippedState
{
	NSGraphicsContext *result = [[NSGraphicsContext alloc] init];

	if (result == nil) {
		return nil;
	}
	/* A NULL CONTEXT IS NOT REFUSED, and that is a deliberate difference from this tree's usual
	 * habit of refusing by name: Apple's factory takes a `CGContextRef` and has no documented
	 * refusal, and an object that reports NULL from `-CGContext` is visibly unusable rather than
	 * silently wrong. Every accessor below tolerates it. */
	/* RETAINED, AND THIS IS THE LINE THAT WAS MISSING. Apple's factory takes ownership of the context —
	 * "the NSGraphicsContext object retains the CGContext" — and every caller in this tree wraps its
	 * context and then releases its OWN reference, which is the natural way to write it and is correct
	 * only if the wrapper retained the thing. Without this the wrapper holds a FREED context: the drawing
	 * that follows goes nowhere, silently, and the bug presents as an image that will not be drawn into
	 * (NSImage's focus pair, 8cb7844c) rather than as a crash.
	 *
	 * THE PROBE FOUND IT BY DOING WHAT THE CONSUMERS DO: wrap a context, release the caller's reference,
	 * then draw through `-CGContext` and read the pixels. */
	result->_context = (CGContextRef)CGContextRetain(cgContext);
	result->_flipped = initialFlippedState ? YES : NO;
	return result;
}

/* AND THE OTHER HALF OF THE SAME OWNERSHIP: what the factory retained, this lets go. Until this existed
 * the class released nothing at all, which is consistent with never having retained anything. */
- (void)dealloc
{
	if (_context != NULL) {
		CGContextRelease(_context);
	}
	[super dealloc];
}

- (CGContextRef)CGContext
{
	return _context;
}

- (BOOL)isFlipped
{
	return _flipped;
}

- (BOOL)isDrawingToScreen
{
	/* NO FOR EVERY CONTEXT THIS LIBRARY CAN MAKE — see the header note. It is stored rather than
	 * computed so that the day a screen-backed context exists there is one place to change. */
	return _drawingToScreen;
}

- (void)saveGraphicsState
{
	if (_context != NULL) {
		CGContextSaveGState(_context);
	}
}

- (void)restoreGraphicsState
{
	if (_context != NULL) {
		CGContextRestoreGState(_context);
	}
}

- (void)flushGraphics
{
	if (_context != NULL) {
		CGContextFlush(_context);
	}
}

/* THE RENDERING OPTIONS: EACH SETTER REACHES THE CONTEXT, EACH GETTER ANSWERS FROM STORAGE — which
 * is Apple's arrangement rather than a shortcut, because CoreGraphics has no getter for any of the
 * three (measured; see the header's correction). The `!= NULL` guards are what make a context-less
 * object harmless instead of a crash. */

- (BOOL)shouldAntialias
{
	return _shouldAntialias;
}

- (void)setShouldAntialias:(BOOL)flag
{
	_shouldAntialias = flag ? YES : NO;
	if (_context != NULL) {
		CGContextSetShouldAntialias(_context, _shouldAntialias);
	}
}

- (NSPoint)patternPhase
{
	return _patternPhase;
}

- (void)setPatternPhase:(NSPoint)phase
{
	_patternPhase = phase;
	if (_context != NULL) {
		/* A POINT IN, A SIZE OUT: that is Apple's own asymmetry between this property and
		 * `CGContextSetPatternPhase`, and the conversion is the whole of the difference. */
		CGContextSetPatternPhase(_context, CGSizeMake(phase.x, phase.y));
	}
}

/* THE TWO ENUMS LINE UP BY NAME, SO THIS IS A SWITCH AND NOT A TABLE — and it has to be a switch
 * rather than a cast, because THEIR ORDERINGS DIFFER: `NSImageInterpolationDefault` is 0 while
 * `kCGInterpolationNone` is 0, since the CoreGraphics order is this tree's own choice (`None` first,
 * so a zeroed graphics state means nearest). A cast would map `Default` onto `None` and vice versa,
 * silently, and the property below would then report the opposite of what it was set to. */
static CGInterpolationQuality fn_interpolation(NSImageInterpolation q)
{
	switch (q) {
	case NSImageInterpolationNone: return kCGInterpolationNone;
	case NSImageInterpolationLow: return kCGInterpolationLow;
	case NSImageInterpolationMedium: return kCGInterpolationMedium;
	case NSImageInterpolationHigh: return kCGInterpolationHigh;
	case NSImageInterpolationDefault:
	default:
		return kCGInterpolationDefault;
	}
}

/* AND BACK, because the getter asks the context rather than a stored field: what comes back is one of
 * the three levels CoreGraphics ACCEPTS, and reading it as the AppKit case the caller used is what
 * makes a refused `Low` report the quality in force. */
static NSImageInterpolation fn_interpolation_ns(CGInterpolationQuality q)
{
	switch (q) {
	case kCGInterpolationNone: return NSImageInterpolationNone;
	case kCGInterpolationLow: return NSImageInterpolationLow;
	case kCGInterpolationMedium: return NSImageInterpolationMedium;
	case kCGInterpolationHigh: return NSImageInterpolationHigh;
	case kCGInterpolationDefault:
	default:
		return NSImageInterpolationDefault;
	}
}

- (NSImageInterpolation)imageInterpolation
{
	/* A CONTEXT-LESS OBJECT ANSWERS `None`, which is what a NULL context reads back as - the honest
	 * answer for an object with nothing to ask, and not a stored fallback. */
	return fn_interpolation_ns(CGContextGetInterpolationQuality(_context));
}

- (void)setImageInterpolation:(NSImageInterpolation)q
{
	if (_context != NULL) {
		/* THE REFUSAL IS COREGRAPHICS' AND IS NOT DUPLICATED HERE. `kCGInterpolationLow` and
		 * `…High` are rejected by `CGContextSetInterpolationQuality`, which also leaves the quality
		 * where it was, so the getter above reports the truth afterwards with no second copy of the
		 * rule to drift out of step. */
		CGContextSetInterpolationQuality(_context, fn_interpolation(q));
	}
}

- (NSCompositingOperation)compositingOperation
{
	return _compositingOperation;
}

- (void)setCompositingOperation:(NSCompositingOperation)op
{
	CGBlendMode mode;
	int ok;

	mode = fn_blend_mode(op, &ok);
	if (!ok) {
		fprintf(stderr, "APPKIT-REFUSE: %d is not a declared NSCompositingOperation - the 28 "
				"live cases map one-for-one onto CGBlendMode and the thirteen legacy "
				"NSComposite aliases ARE those same values, so this is neither - and the blend "
				"mode is left as it was rather than set to the nearest available thing\n",
			(int)op);
		return;
	}
	_compositingOperation = op;
	if (_context != NULL) {
		CGContextSetBlendMode(_context, mode);
	}
}

+ (nullable NSGraphicsContext *)currentContext
{
	return fn_current;
}

+ (void)setCurrentContext:(nullable NSGraphicsContext *)context
{
	/* REPLACE, RETAIN THE NEW, RELEASE THE OLD — and in that order, so a caller who sets the
	 * context that is already current does not free it under itself. */
	NSGraphicsContext *old = fn_current;

	fn_current = [context retain];
	[old release];
}

+ (void)saveGraphicsState
{
	if (fn_depth == APPKIT_GSTATE_STACK_MAX) {
		fprintf(stderr, "APPKIT-REFUSE: +saveGraphicsState at depth %d does not fit this "
				"library's stack of %d, and dropping the oldest would restore the wrong "
				"context\n", fn_depth, APPKIT_GSTATE_STACK_MAX);
		return;
	}
	/* THE CURRENT CONTEXT IS PUSHED EVEN WHEN IT IS NIL. A caller who saved with nothing current
	 * and then set one before restoring gets their own context popped back, which is what a
	 * stack of contexts means; skipping the push would make the two calls asymmetric and the
	 * restore would pop something a different save left. */
	fn_stack[fn_depth++] = fn_current;
	if (fn_current != nil) {
		[fn_current saveGraphicsState];
	}
}

+ (void)restoreGraphicsState
{
	if (fn_depth == 0) {
		/* Apple's contract is that an unbalanced restore is a caller error; the cheapest honest
		 * reading is to leave the current context alone rather than read below the stack. */
		return;
	}
	fn_depth--;
	if (fn_current != fn_stack[fn_depth]) {
		/* THE POPPED CONTEXT BECOMES CURRENT, and the one it displaces is released — the pair to
		 * the retain `+setCurrentContext:` took when it was installed. `fn_current` is not
		 * released here when it IS the popped one, because the caller's own reference is what
		 * kept it alive through the save. */
		NSGraphicsContext *displaced = fn_current;

		fn_current = [fn_stack[fn_depth] retain];
		[displaced release];
	}
	fn_stack[fn_depth] = nil;
	if (fn_current != nil) {
		[fn_current restoreGraphicsState];
	}
}

+ (BOOL)currentContextDrawingToScreen
{
	NSGraphicsContext *current = [self currentContext];

	return current == nil ? NO : [current isDrawingToScreen];
}


/* ---------------------------------- THE ERA'S ONE C DRAWING CALL ---------------------------------- */

/* BORROW AND DRAW. The caller's plane 0 is adopted by a rep — adopted, NOT copied, so the buffer must
 * outlive this call, which is what a caller passing a live plane already means — and the rep draws into
 * the current context. The rep is released and does not free what it borrowed (`_ownsData` is NO for an
 * adopted plane; that is what makes this safe rather than a double free).
 *
 * THE TWO REFUSALS ARE THE LAYOUTS THIS TREE'S REP CANNOT HOLD, named rather than approximated: several
 * PLANES (the rep holds one — NSBitmapImageRep.h says so) and a missing plane 0. Everything else — the
 * bit depth, the channel count, the stride, the colour-space name — is passed straight through to the
 * designated initialiser, so a layout the rep cannot hold is refused THERE, by that door's own message,
 * instead of by a second copy of the same rule here.
 *
 * `-drawInRect:` answering NO is reported too, because it is the answer for "no current context" or "the
 * rep has no image", and a C function that silently drew nothing would be the one failure mode this tier
 * refuses to have. */
void NSDrawBitmap(NSRect rect, NSInteger width, NSInteger height, NSInteger bps, NSInteger spp,
                  NSInteger bpp, NSInteger bpr, BOOL isPlanar, BOOL hasAlpha,
                  NSString *colorSpaceName, const unsigned char *const _Nullable data[_Nonnull 5])
{
	unsigned char *planes[1];
	NSBitmapImageRep *rep;

	if (data == NULL || data[0] == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: NSDrawBitmap needs a plane 0 to draw; it was given none\n");
		return;
	}
	if (isPlanar) {
		fprintf(stderr, "APPKIT-REFUSE: NSDrawBitmap cannot draw PLANAR data: this tree's "
				"NSBitmapImageRep holds ONE plane\n");
		return;
	}
	planes[0] = (unsigned char *)(uintptr_t)data[0];
	rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:planes
						     pixelsWide:width
						     pixelsHigh:height
						  bitsPerSample:bps
						samplesPerPixel:spp
						       hasAlpha:hasAlpha
						       isPlanar:NO
						 colorSpaceName:colorSpaceName
						    bytesPerRow:bpr
						   bitsPerPixel:bpp];
	if (rep == NULL) {
		/* THE REP SAID WHY — its own initialiser is the one message for a bad layout. */
		return;
	}
	if (![rep drawInRect:rect]) {
		fprintf(stderr, "APPKIT-REFUSE: NSDrawBitmap built the rep but could not draw it — there is "
				"no current graphics context\n");
	}
	[rep release];
}


/* ----------------------------------- THE COLOUR-SPACE NAMES ----------------------------------- */

/* THE VALUES ARE THE NAMES, which is the rule this tier follows where Apple publishes a symbol and not a
 * string — and for a colour-space NAME that is doubly right, because the string IS the identifier. */
NSString *NSCalibratedRGBColorSpace = @"NSCalibratedRGBColorSpace";
NSString *NSCalibratedWhiteColorSpace = @"NSCalibratedWhiteColorSpace";
NSString *NSDeviceCMYKColorSpace = @"NSDeviceCMYKColorSpace";
NSString *NSDeviceWhiteColorSpace = @"NSDeviceWhiteColorSpace";
NSString *NSCustomColorSpace = @"NSCustomColorSpace";
NSString *NSNamedColorSpace = @"NSNamedColorSpace";
NSString *NSPatternColorSpace = @"NSPatternColorSpace";

/* AND THE COUNT, ONE TABLE, READ OFF THE ERA HEADER'S OWN DESCRIPTIVE BLOCK. The two hues are listed there
 * under their RGB spaces ("Red, green, blue, and alpha components / Hue, saturation, brightness, and alpha
 * components") and have no NAME of their own, so the count is the same four; the three no-space names
 * above answer 0 rather than a count for a space that does not exist here. */
NSInteger NSNumberOfColorComponents(NSString *colorSpaceName)
{
	if (colorSpaceName == nil) {
		return 0;
	}
	if ([colorSpaceName isEqualToString:NSDeviceCMYKColorSpace]) {
		return 5;
	}
	if ([colorSpaceName isEqualToString:NSDeviceRGBColorSpace] ||
	    [colorSpaceName isEqualToString:NSCalibratedRGBColorSpace]) {
		return 4;
	}
	if ([colorSpaceName isEqualToString:NSDeviceWhiteColorSpace] ||
	    [colorSpaceName isEqualToString:NSDeviceGrayColorSpace] ||
	    [colorSpaceName isEqualToString:NSCalibratedWhiteColorSpace]) {
		return 2;
	}
	if ([colorSpaceName isEqualToString:NSNamedColorSpace]) {
		/* A catalog colour is a PAIR — the list's name and the colour's name — which is the one entry in
		 * the era's block that is not a component count at all, and the header says so. */
		return 2;
	}
	return 0;
}

/* ---- THE ERA'S REMAINING DOORS --------------------------------------------------------------- */

/* A CONTEXT THAT DRAWS INTO A REPRESENTATION'S PIXELS, which is the one destination this tree has. Two
 * things are refused and both are Apple's own conditions: a planar rep (its comment: "Only NSBitmapImageRep
 * instances with isPlanar == NO are supported") and a rep with no readable buffer — which is what a
 * rep decoded from bytes is, since its pixels belong to a CGImage rather than to a plane.
 *
 * THE FORMAT IS THE REP'S OWN, and it is stated rather than assumed: `-bitmapData` is R, G, B, A with alpha
 * last and premultiplied (NSBitmapImageRep.h says so), which is `PremultipliedLast | 32Big`. Asking for the
 * same bytes under a different declaration is how a channel order gets silently swapped. */
+ (nullable NSGraphicsContext *)graphicsContextWithBitmapImageRep:(NSBitmapImageRep *)bitmapRep
{
	CGColorSpaceRef cs;
	CGContextRef ctx;
	NSGraphicsContext *g;
	NSInteger w, h, bps, bpp, bpr;
	NSString *spaceName;

	if (bitmapRep == nil || [bitmapRep bitmapData] == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: +graphicsContextWithBitmapImageRep: needs a rep with READABLE "
				"pixels; a rep decoded from bytes keeps them in its CGImage, so there is no plane "
				"to draw into\n");
		return nil;
	}
	if ([bitmapRep isPlanar]) {
		fprintf(stderr, "APPKIT-REFUSE: +graphicsContextWithBitmapImageRep: supports NON-PLANAR reps "
				"only, which is Apple's own condition\n");
		return nil;
	}
	w = [bitmapRep pixelsWide];
	h = [bitmapRep pixelsHigh];
	bps = [bitmapRep bitsPerSample];
	bpp = [bitmapRep bitsPerPixel];
	bpr = [bitmapRep bytesPerRow];
	if (w <= 0 || h <= 0 || bps <= 0 || bpp <= 0 || bpr <= 0) {
		return nil;
	}
	spaceName = [bitmapRep colorSpaceName];
	cs = [spaceName isEqualToString:NSDeviceGrayColorSpace] ? CGColorSpaceCreateDeviceGray()
							       : CGColorSpaceCreateDeviceRGB();
	if (cs == NULL) {
		return nil;
	}
	ctx = CGBitmapContextCreate([bitmapRep bitmapData], (size_t)w, (size_t)h, (size_t)bps, (size_t)bpr, cs,
				    (uint32_t)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
	CGColorSpaceRelease(cs);
	if (ctx == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: +graphicsContextWithBitmapImageRep: CoreGraphics will not make a "
				"bitmap context over this rep's layout\n");
		return nil;
	}
	/* THE WRAPPER RETAINS IT (that is the fix NSGraphicsContext needed, 523ab83d), so the +1 from the
	 * create is given up here. */
	g = [self graphicsContextWithCGContext:ctx flipped:NO];
	CGContextRelease(ctx);
	/* AND ITS ATTRIBUTES ARE THE DESTINATION, because this door IS the attributes door with an
	 * `NSBitmapImageRep` destination — Apple's own equivalence, quoted above — so a context made this way
	 * answers `-attributes` with that dictionary rather than with nil. The dictionary is IMMUTABLE and owned
	 * here (a +1), which is what `-dealloc` releases. */
	if (g != nil) {
		g->_attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
				  bitmapRep, NSGraphicsContextDestinationAttributeName, nil];
	}
	return g;
}

/* AND THE GENERAL FACTORY, WITH ONE DESTINATION. Apple's comment lists four kinds a destination may be —
 * "an instance of NSWindow, NSMutableData, NSBitmapImageRep, or NSURL" — and exactly one of them is a thing
 * this tree has. The other three mean the POSTSCRIPT or PDF output formats, which need an encoder, or a
 * window, which needs the display seam; each is refused by name rather than half-created. */
+ (nullable NSGraphicsContext *)graphicsContextWithAttributes:(NSDictionary *)attributes
{
	id dest = attributes != nil ? [attributes objectForKey:NSGraphicsContextDestinationAttributeName] : nil;
	NSGraphicsContext *g;

	if (dest == nil) {
		fprintf(stderr, "APPKIT-REFUSE: +graphicsContextWithAttributes: needs an object under "
				"NSGraphicsContextDestinationAttributeName\n");
		return nil;
	}
	if ([dest isKindOfClass:[NSBitmapImageRep class]]) {
		g = [self graphicsContextWithBitmapImageRep:dest];
		if (g != nil) {
			/* THE CALLER'S DICTIONARY IS THE ONE REMEMBERED — Apple's contract for `-attributes` is
			 * "attributes used to create this instance" — and it is COPIED rather than retained, the way
			 * NSEvent copies its characters: a caller that hands over a mutable dictionary and then edits it
			 * must not be able to change what a context says it was made from. */
			[g->_attributes release];
			g->_attributes = [attributes copy];
		}
		return g;
	}
	/* THE PDF WRITER EXISTS; THIS DOOR STILL DOES NOT BUILD ONE FROM THESE ATTRIBUTES, and the reason is
	 * the attributes rather than the writer: they carry no page size, and a PDF page is a sized thing. The
	 * sized routes are CGPDFContextCreate and -[NSView dataWithPDFInsideRect:]. A window destination is the
	 * display seam, which is a different subject. */
	fprintf(stderr, "APPKIT-REFUSE: +graphicsContextWithAttributes: has ONE destination it can honour — "
			"an NSBitmapImageRep. A MutableData or URL destination carries no page size, so a PDF page "
			"cannot be made from it here; use CGPDFContextCreate or -[NSView dataWithPDFInsideRect:]. A "
			"window destination is the display seam\n");
	return nil;
}

/* THE DEPRECATED PORT DOOR, FORWARDED SO THE TWO SPELLINGS CANNOT DRIFT. Its parameter is a `void *` in
 * Apple's header and is documented as "usually CGContextRef", so the cast is the documented one. */
+ (nullable NSGraphicsContext *)graphicsContextWithGraphicsPort:(void *)graphicsPort
						       flipped:(BOOL)initialFlippedState
{
	return [self graphicsContextWithCGContext:(CGContextRef)graphicsPort flipped:initialFlippedState];
}

/* ---- AND THE REMAINING ROWS ------------------------------------------------------------------ */

+ (nullable NSGraphicsContext *)graphicsContextWithWindow:(id)window
{
	/* APPLE'S OWN DEFINITION, TAKEN LITERALLY: this IS the attributes door with the window as the
	 * destination — Apple's comment says so in one line — so it forwards rather than inventing a second
	 * path. That door refuses a window destination BY NAME, which is the right answer here too: a window's
	 * drawing is the display seam, reached through `AGWindowServer` in this tier rather than through a `CGContextRef`
	 * this class could hand out. */
	NSDictionary *attrs = window != nil
		? [NSDictionary dictionaryWithObject:window forKey:NSGraphicsContextDestinationAttributeName]
		: nil;

	return [self graphicsContextWithAttributes:attrs];
}

- (NSDictionary *)attributes
{
	return _attributes;
}

- (void *)graphicsPort
{
	/* ONE ACCESSOR READ TWO WAYS: this is the same pointer `-CGContext` answers, under the name Apple used
	 * before 10.0 said Core Graphics. A caller porting a 10.0 application reads the port here; a modern one
	 * reads the context there; neither can drift from the other because there is one field. */
	return (void *)_context;
}

- (NSColorRenderingIntent)colorRenderingIntent
{
	return _colorRenderingIntent;
}

- (void)setColorRenderingIntent:(NSColorRenderingIntent)renderingIntent
{
	_colorRenderingIntent = renderingIntent;
	/* STORED AND ANSWERED — the object remembers what it was asked for, the way the three options above do
	 * — AND NAMED AS UNCONSUMED WHEN IT IS NOT THE DEFAULT, because unlike those three this one cannot be
	 * applied: an intent says how a colour is converted WHILE DRAWING, this library's drawing converts
	 * nothing, and its CoreGraphics has no `CGContextSetRenderingIntent` to apply it with. A silent no-op is
	 * the failure this says out loud. */
	if (renderingIntent != NSColorRenderingIntentDefault) {
		fprintf(stderr, "APPKIT-REFUSE: -setColorRenderingIntent: stores the intent but cannot apply it — "
				"this library's drawing does not convert colours (fills composite device numbers, images "
				"composite their own bytes) and its CoreGraphics has no CGContextSetRenderingIntent\n");
	}
}

- (id)CIContext
{
	/* THERE IS NO CORE IMAGE IN THIS TREE, so there is no CIContext behind this context and nil is the
	 * truth rather than an approximation. The refusal says which subsystem is missing, so a caller can tell
	 * "this tier cannot do that" from "this tier did it and the answer was nil". */
	fprintf(stderr, "APPKIT-REFUSE: -CIContext needs Core Image, which this tree has not got\n");
	return nil;
}

/* ---- THE THREE THAT REFUSE BY NAME ---------------------------------------------------------- */

+ (void)setGraphicsState:(NSInteger)gState
{
	/* A GraphicsState IS A TOKEN APPLE'S OWN MACHINERY HANDS OUT — an id that names a saved context, the
	 * PostScript-ish model of `gsave`/`grestore`. This tree's stack is the object pair
	 * `+saveGraphicsState`/`+restoreGraphicsState` above, which takes no id at all, so there is nothing a
	 * caller's integer could name. */
	fprintf(stderr, "APPKIT-REFUSE: +setGraphicsState: takes an id from the GraphicsState machinery, which "
			"this tree does not have — the context stack here is +saveGraphicsState/+restoreGraphicsState "
			"(asked for %ld)\n", (long)gState);
}

- (id)focusStack
{
	/* THE FOCUS STACK IS HOW A FOCUS RING IS DRAWN: it is pushed by the control that has focus and read by
	 * the drawing that rings it. This tree has no focus ring and no such stack, so the honest answers are
	 * nil and a refusal rather than an opaque object that nothing in the tree could ever put anything in. */
	return nil;
}

- (void)setFocusStack:(id)stack
{
	(void)stack;
	fprintf(stderr, "APPKIT-REFUSE: -setFocusStack: belongs to the focus-ring machinery, and this tree has "
			"no focus ring to ring\n");
}

@end
