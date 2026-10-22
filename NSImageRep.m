/*
 * NSImageRep — the metadata every representation has, and the one drawing rule they share.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE MRC OWNERSHIP IS SMALL AND EXPLICIT: this class owns exactly `_colorSpaceName` (copied in, so a
 * caller may pass a mutable string and let it go) and nothing else — the pixels belong to the
 * subclass, which knows whether it owns them.
 */
#import <AppKit/NSImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreGraphics/CGContext.h>

#include <math.h>
#include <stdio.h>
#import <AppKit/NSPasteboard.h>
/* **AND `NSImage.h` FOR THE TWO HINT KEYS, WHICH ARE NSImage'S VOCABULARY THAT A REP READS.** Apple declares
 * `NSImageHintInterpolation` there and documents that a rep may interpret the hints it is handed; importing the header
 * from this IMPLEMENTATION is a dependency in one direction only — `NSImage.h` imports this one, and its guard closes
 * the loop. */
#import <AppKit/NSImage.h>
#import <Foundation/NSNotification.h>
#include <objc/runtime.h>	/* class_getMethodImplementation: which classes ANSWER a registry list */
#import <Foundation/NSURL.h>

NSString *const NSDeviceRGBColorSpace = @"NSDeviceRGBColorSpace";
NSString *const NSDeviceGrayColorSpace = @"NSDeviceGrayColorSpace";

NSString *NSImageRepRegistryDidChangeNotification = @"NSImageRepRegistryDidChangeNotification";

/* THE REGISTRATION ORDER IS THE ANSWER ORDER, which is the one thing an array buys over a set here. */
static NSMutableArray *s_repClasses;

/* ONE QUESTION PUT TO EVERY REGISTERED CLASS, and the FIRST yes wins. `id` rather than `Class` in the
 * signatures because -respondsToSelector: has to be asked of the class OBJECT. */
static Class fn_first_class_that_can_init(NSData *d)
{
	NSUInteger i;

	if (s_repClasses == nil || d == nil) {
		return Nil;
	}
	for (i = 0; i < [s_repClasses count]; i++) {
		Class c = (Class)[s_repClasses objectAtIndex:i];

		/* ASKED TYPED, NOT THROUGH `performSelector:`, and the compiler is why: the answer is a BOOL, and
		 * reading one out of an `id` return is a cast the compiler is right to complain about. `self` is
		 * NOT among the classes asked — the base's own answer is NO, and a registry that asked itself
		 * would answer YES for every format the moment one subclass existed. */
		if ([c respondsToSelector:@selector(canInitWithData:)] && [c canInitWithData:d]) {
			return c;
		}
	}
	return Nil;
}

/* **"DOES THIS CLASS ANSWER THIS LIST ITSELF, OR DOES IT ONLY INHERIT THE UNION?"** A plain
 * `class_getMethodImplementation(c, sel)` searches the class's INSTANCE methods, and every selector in this registry is
 * a CLASS method — so the first version of this test compared two NULLs, called every class "inherited", and answered
 * an EMPTY union. MEASURED twice over: the list came back empty, and the union's own body still recursed. The
 * metaclass is what has to be asked: `object_getClass` on a class gives it, and the two implementations are the two
 * class methods. */
static BOOL fn_class_answers_for_itself(Class c, SEL sel)
{
	IMP own = class_getMethodImplementation(object_getClass(c), sel);
	IMP inherited = class_getMethodImplementation(object_getClass([NSImageRep class]), sel);

	return own != NULL && own != inherited;
}

/* AND THE UNION OF A LIST EVERY REGISTERED CLASS CAN NAME. */
static NSArray *fn_union_of(SEL sel)
{
	NSMutableArray *out = [NSMutableArray array];

	if (s_repClasses == nil) {
		return out;
	}
	{
		NSUInteger i, j;
		for (i = 0; i < [s_repClasses count]; i++) {
			Class c = (Class)[s_repClasses objectAtIndex:i];
			NSArray *list;

			/* **AND A CLASS THAT ONLY INHERITS THE UNION'S OWN DOOR IS SKIPPED, WHICH IS THE ONE BUG THIS HELPER
			 * HAD.** `+imageUnfilteredTypes` (and the two lists below it) IS this function; a registrant that does
			 * not override it still `-respondsToSelector:`, so the first version called it, which called this
			 * function, which called it — MEASURED as a segfault the first time anything asked for the UTI list.
			 * `+imageUnfilteredFileTypes` escaped it only because every registrant happened to override that one. The
			 * test is whether the class's implementation is the BASE's: equal means "inherited, not answered" and the
			 * class contributes nothing. */
			if (![c respondsToSelector:sel]) {
				continue;
			}
			if (!fn_class_answers_for_itself(c, sel)) {
				continue;
			}
			list = [c performSelector:sel];
			for (j = 0; list != nil && j < [list count]; j++) {
				id t = [list objectAtIndex:j];

				if (t != nil && ![out containsObject:t]) {
					[out addObject:t];
				}
			}
		}
	}
	return out;
}

static Class fn_class_for_list_member(SEL sel, NSString *want)
{
	NSUInteger i, j;

	if (s_repClasses == nil || want == nil) {
		return Nil;
	}
	for (i = 0; i < [s_repClasses count]; i++) {
		Class c = (Class)[s_repClasses objectAtIndex:i];
		NSArray *list;

		if (![c respondsToSelector:sel]) {
			continue;
		}
		list = [c performSelector:sel];
		for (j = 0; list != nil && j < [list count]; j++) {
			if ([[list objectAtIndex:j] isEqual:want]) {
				return c;
			}
		}
	}
	return Nil;
}

@implementation NSImageRep

/* ---- WHETHER THE SAMPLES ARE OPAQUE ---------------------------------------------------------------- */

/* THE BASE STORES IT, in Apple's own spelling (`-isOpaque` and `-setOpaque:`, which its 10.6 header declares here).
 * A subclass whose samples can answer the question itself overrides the getter — the flag exists so that a rep with
 * no way to tell has somewhere to keep the answer. */
- (void)setOpaque:(BOOL)flag
{
	_opaque = flag;
}

- (BOOL)isOpaque
{
	return _opaque;
}

/* AND THE ALPHA PAIR, ON THE SAME GROUND — Apple's header groups both under "NSImageRep provides storage for all of
 * these; however, it's illegal to set them in some subclasses", so the base keeps the flag and a subclass records
 * what it knows. The two are INDEPENDENT: opacity is about the samples and the alpha flag is about the channel. */
- (void)setAlpha:(BOOL)flag
{
	_alpha = flag;
}

- (BOOL)alpha
{
	return _alpha;
}

/* **AND THE TWO SAMPLE DOORS, WHICH ARE ONE PAIR OF IVARS UNDER TWO NAMES.** `-hasAlpha` is what Apple calls the
 * question `-alpha` answers here, so it answers the SAME flag rather than a second one; `-bitsPerSample` is the value
 * `-setBitsPerSample:` recorded, and a rep whose pixels have a depth of their own overrides both accessors (see
 * `NSBitmapImageRep`, where the depth is a fact about the bytes). A rep that was told nothing answers 0 — "no samples"
 * — rather than a plausible 8, because 8 would be a claim about pixels this base has not got. */
- (BOOL)hasAlpha
{
	return _alpha;
}

- (NSInteger)bitsPerSample
{
	return _repBitsPerSample;
}

- (void)setBitsPerSample:(NSInteger)bitsPerSample
{
	_repBitsPerSample = bitsPerSample;
}

- (instancetype)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_size = NSMakeSize(0.0, 0.0);
	_pixelsWide = 0;
	_pixelsHigh = 0;
	_colorSpaceName = nil;
	return self;
}

- (void)dealloc
{
	[_colorSpaceName release];
	[super dealloc];
}

- (NSInteger)pixelsWide
{
	return _pixelsWide;
}

- (void)setPixelsWide:(NSInteger)n
{
	_pixelsWide = n;
}

- (NSInteger)pixelsHigh
{
	return _pixelsHigh;
}

- (void)setPixelsHigh:(NSInteger)n
{
	_pixelsHigh = n;
}

- (NSSize)size
{
	return _size;
}

- (void)setSize:(NSSize)s
{
	_size = s;
}

- (NSString *)colorSpaceName
{
	return _colorSpaceName;
}

- (void)setColorSpaceName:(NSString *)name
{
	if (name != _colorSpaceName) {
		NSString *copy = [name copy];

		[_colorSpaceName release];
		_colorSpaceName = copy;
	}
}

/* AN ABSTRACT REP HAS NO PIXELS, so there is no image to answer with. This is not a stub to be filled
 * in later: it is the contract, and every concrete rep overrides it. */
- (CGImageRef)CGImage
{
	return NULL;
}

/* THE SNAPSHOT, WHICH IS THE SAME DOOR `NSImage` HAS AND FOR THE SAME REASON: a caller with no drawing
 * context still needs the pixels, and the rect is IN AND OUT — the proposal is read and the
 * pixel-INTEGRAL rect the returned image actually covers is written back (Apple's own contract, and the
 * reason a caller who asks for an 8x8 image at a fractional size gets told 8x8). */
- (nullable CGImageRef)CGImageForProposedRect:(nullable NSRect *)proposedDestRect
				      context:(nullable NSGraphicsContext *)referenceContext
					hints:(nullable NSDictionary *)hints
{
	CGImageRef image = [self CGImage];

	(void)referenceContext;
	(void)hints;
	if (image == NULL) {
		return NULL;
	}
	if (proposedDestRect != NULL) {
		NSRect want = *proposedDestRect;
		CGFloat x0 = (CGFloat)floor((double)NSMinX(want));
		CGFloat y0 = (CGFloat)floor((double)NSMinY(want));
		CGFloat x1 = (CGFloat)ceil((double)NSMaxX(want));
		CGFloat y1 = (CGFloat)ceil((double)NSMaxY(want));

		*proposedDestRect = NSMakeRect(x0, y0, x1 - x0, y1 - y0);
	}
	return image;
}

/* **THE FOUR SIMPLER DOORS ARE THIS ONE WITH ITS ARGUMENTS FILLED IN, WHICH IS WHY THE ORIENTATION RULE BELOW IS IN
 * ONE PLACE.** `-drawInRect:` is the whole rep, SourceOver at full strength, respecting the context's flip and with no
 * hints — the same picture these doors painted before the wide door existed, because the wide door's body IS the old
 * body with the crop, the blend and the hints added around it. */
- (BOOL)drawInRect:(NSRect)rect
{
	return [self drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
			fraction:1.0 respectFlipped:YES hints:nil];
}

- (BOOL)drawInRect:(NSRect)dstRect
	  fromRect:(NSRect)srcRect
	 operation:(NSCompositingOperation)op
	  fraction:(CGFloat)delta
    respectFlipped:(BOOL)respectFlipped
	     hints:(NSDictionary *)hints
{
	NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
	CGImageRef img = [self CGImage];
	CGImageRef crop = NULL;
	CGContextRef cg;
	CGAffineTransform ctm;
	id quality = [hints objectForKey:NSImageHintInterpolation];
	CGInterpolationQuality previousQuality = kCGInterpolationDefault;
	BOOL hadQuality = NO;

	/* NO CONTEXT OR NO PIXELS IS A NO, NOT A RAISE — the same rule the context's own members follow. */
	if (ctx == nil || img == NULL) {
		return NO;
	}
	cg = [ctx CGContext];
	if (cg == NULL) {
		return NO;
	}
	/* **THE CROP IS IN PIXELS AND THE CALLER SPEAKS POINTS**, which are the same number until a rep is given a size
	 * different from its pixel count — resolution independence, and the one place the conversion belongs. A source
	 * rect with no area is NO CROP rather than an empty picture: that is what the three simple doors pass. */
	if (srcRect.size.width > 0.0 && srcRect.size.height > 0.0) {
		CGFloat sizeW = (_size.width > 0.0) ? _size.width : (CGFloat)_pixelsWide;
		CGFloat sizeH = (_size.height > 0.0) ? _size.height : (CGFloat)_pixelsHigh;
		CGFloat sx = (sizeW > 0.0) ? (CGFloat)_pixelsWide / sizeW : 1.0;
		CGFloat sy = (sizeH > 0.0) ? (CGFloat)_pixelsHigh / sizeH : 1.0;

		crop = CGImageCreateWithImageInRect(img, CGRectMake(srcRect.origin.x * sx, srcRect.origin.y * sy,
								    srcRect.size.width * sx, srcRect.size.height * sy));
		if (crop == NULL) {
			return NO;
		}
		img = crop;
	}
	/* THE HINT IS THE CONTEXT'S QUALITY FOR THIS DRAW ONLY, and it is put back because a hint is a statement about
	 * one call rather than a change to the caller's context. */
	if (quality != nil) {
		previousQuality = CGContextGetInterpolationQuality(cg);
		hadQuality = YES;
		[ctx setImageInterpolation:(NSImageInterpolation)[quality integerValue]];
	}
	[ctx setCompositingOperation:op];
	CGContextSetAlpha(cg, delta);
	/* **AN IMAGE IS DRAWN UP-RIGHT IN BOTH A FLIPPED VIEW AND AN UNFLIPPED ONE.** `CGContextDrawImage`
	 * paints through the current CTM, so the SAME bytes arrive mirrored in the two cases; the Desktop
	 * (an unflipped view in its own y-up space) and the file window's `WSIconView` (flipped, y-down) are
	 * exactly that pair. MEASURED: before this, Frost's folder icons were up-right on the Desktop and
	 * upside-down in the file window. The existing generic art was made for the y-down path, so the
	 * y-up one is the case that needs the extra mirror. The sign of `d` is the CTM's y direction, and
	 * it is the value the view walk actually puts there; `NSGraphicsContext -isFlipped` is the
	 * WINDOW's statement and stays NO for both. */
	ctm = CGContextGetCTM(cg);
	if (respectFlipped && ctm.d > 0.0) {
		CGContextSaveGState(cg);
		CGContextTranslateCTM(cg, dstRect.origin.x, dstRect.origin.y + dstRect.size.height);
		CGContextScaleCTM(cg, 1.0, -1.0);
		CGContextDrawImage(cg, CGRectMake(0.0, 0.0, dstRect.size.width, dstRect.size.height), img);
		CGContextRestoreGState(cg);
	} else {
		CGContextDrawImage(cg, NSRectToCGRect(dstRect), img);
	}
	CGContextSetAlpha(cg, 1.0);
	if (hadQuality) {
		CGContextSetInterpolationQuality(cg, previousQuality);
	}
	if (crop != NULL) {
		CGImageRelease(crop);
	}
	return YES;
}

- (BOOL)drawAtPoint:(NSPoint)point
{
	return [self drawInRect:NSMakeRect(point.x, point.y, _size.width, _size.height)];
}

- (BOOL)draw
{
	return [self drawInRect:NSMakeRect(0.0, 0.0, _size.width, _size.height)];
}


/* ============================================================================================ *
 * THE REGISTRY.                                                                                 *
 * ============================================================================================ */

+ (void)registerImageRepClass:(Class)imageRepClass
{
	if (imageRepClass == Nil) {
		return;
	}
	if (s_repClasses == nil) {
		s_repClasses = [[NSMutableArray alloc] init];
	}
	if ([s_repClasses containsObject:imageRepClass]) {
		return;                 /* idempotent, so a class that registers twice is ONE registrant */
	}
	[s_repClasses addObject:imageRepClass];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSImageRepRegistryDidChangeNotification
							    object:self];
}

+ (void)unregisterImageRepClass:(Class)imageRepClass
{
	if (imageRepClass == Nil || s_repClasses == nil ||
	    ![s_repClasses containsObject:imageRepClass]) {
		return;
	}
	[s_repClasses removeObject:imageRepClass];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSImageRepRegistryDidChangeNotification
							    object:self];
}

+ (NSArray *)registeredImageRepClasses
{
	/* A COPY, so a caller walking the registry cannot change it behind this class's back. */
	return s_repClasses != nil ? [NSArray arrayWithArray:s_repClasses] : [NSArray array];
}

+ (BOOL)canInitWithData:(NSData *)data
{
	/* THE BASE'S OWN ANSWER IS NO — an abstract rep has no format — and the YES comes from a registered
	 * subclass. Asking `self` rather than the registry would be asking the base, which is the bug this
	 * shape exists to prevent. */
	if (data == nil) {
		return NO;
	}
	return fn_first_class_that_can_init(data) != Nil;
}

+ (Class)imageRepClassForData:(NSData *)data
{
	if (data == nil) {
		return Nil;
	}
	return fn_first_class_that_can_init(data);
}

+ (Class)imageRepClassForType:(NSString *)type
{
	return fn_class_for_list_member(@selector(imageUnfilteredTypes), type);
}

+ (Class)imageRepClassForFileType:(NSString *)type
{
	return fn_class_for_list_member(@selector(imageUnfilteredFileTypes), type);
}

+ (Class)imageRepClassForPasteboardType:(NSString *)type
{
	return fn_class_for_list_member(@selector(imageUnfilteredPasteboardTypes), type);
}

+ (NSArray *)imageUnfilteredTypes
{
	return fn_union_of(@selector(imageUnfilteredTypes));
}

+ (NSArray *)imageTypes
{
	/* NO FILTERING HERE, and that is a fact about this tree rather than a shortcut: filtering is a
	 * pasteboard SERVICE (`+typesFilterableTo:` in NSPasteboard refuses for the same reason), so the
	 * filtered list IS the unfiltered one. */
	return [self imageUnfilteredTypes];
}

+ (NSArray *)imageUnfilteredFileTypes
{
	return fn_union_of(@selector(imageUnfilteredFileTypes));
}

/* **AND THE FILTERED PAIR, WHICH IS THE UNFILTERED ONE IN THIS TIER.** Filtering is a pasteboard SERVICE (see
 * `+typesFilterableTo:`, which refuses for the same reason) and this tree registers no filters — so the two lists are
 * one list, and they are TWO DOORS because the day a filter exists only this pair changes. The same reasoning
 * `+imageTypes` states one door up. */
+ (NSArray *)imageFileTypes
{
	return [self imageUnfilteredFileTypes];
}

+ (NSArray *)imagePasteboardTypes
{
	return [self imageUnfilteredPasteboardTypes];
}

/* **AND THE LIVE QUESTION, WHICH IS THE SAME LIST ASKED OF A BOARD.** NSImage has had this door for its own list since
 * the pasteboard slice; this is the registry's, and the difference is WHICH list is consulted: a rep class answers with
 * the types its registrants claim, while `NSImage` answers with the two the whole image layer will hand a board. Both
 * are real, and neither guesses: a board with no types answers NO. */
+ (BOOL)canInitWithPasteboard:(NSPasteboard *)pasteboard
{
	if (pasteboard == nil) {
		return NO;
	}
	return [pasteboard availableTypeFromArray:[self imagePasteboardTypes]] != nil;
}

+ (id)imageRepWithData:(NSData *)data
{
	/* AN ABSTRACT REP HAS NO FORMAT — see the header. A registrant overrides this. */
	(void)data;
	return nil;
}

+ (NSArray *)imageRepsWithData:(NSData *)data
{
	(void)data;
	return nil;
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	return fn_union_of(@selector(imageUnfilteredPasteboardTypes));
}

/* ---- THE CONTENT DOORS --------------------------------------------------------------------- */

/* THE ONE PLACE THAT TURNS BYTES INTO A REP, so the four doors below cannot disagree about which class
 * answered. A format no registered class claims is refused by NAME with the list of what is registered,
 * which is the difference between "this file is not an image" and "nothing here reads this". */
static id fn_rep_from_data(NSData *d, int plural)
{
	Class c;

	if (d == nil) {
		return nil;
	}
	c = [NSImageRep imageRepClassForData:d];
	if (c == Nil) {
		fprintf(stderr, "APPKIT-REFUSE: no registered NSImageRep class can read these bytes; "
				"registered: %s\n",
			[[[NSImageRep registeredImageRepClasses] valueForKey:@"description"]
			 componentsJoinedByString:@", "].UTF8String ?: "");
		return nil;
	}
	if (plural && [c respondsToSelector:@selector(imageRepsWithData:)]) {
		NSArray *reps = [c imageRepsWithData:d];

		if (reps != nil) {
			return reps;
		}
	}
	if ([c respondsToSelector:@selector(imageRepWithData:)]) {
		id one = [c imageRepWithData:d];

		if (one == nil) {
			return nil;
		}
		return plural ? [NSArray arrayWithObject:one] : one;
	}
	return nil;
}

+ (id)imageRepWithContentsOfFile:(NSString *)filename
{
	if (filename == nil) {
		return nil;
	}
	return fn_rep_from_data([NSData dataWithContentsOfFile:filename], 0);
}

+ (NSArray *)imageRepsWithContentsOfFile:(NSString *)filename
{
	if (filename == nil) {
		return nil;
	}
	return fn_rep_from_data([NSData dataWithContentsOfFile:filename], 1);
}

/* A URL DOOR THAT IS A FILE URL OR NOTHING, which is the same boundary NSImage draws: this tree has no
 * network image loading, so a remote URL is refused rather than half-fetched. */
+ (id)imageRepWithContentsOfURL:(NSURL *)url
{
	if (url == nil || ![url isFileURL]) {
		fprintf(stderr, "APPKIT-REFUSE: +imageRepWithContentsOfURL: reads FILE urls only; this tree "
				"has no network image loading\n");
		return nil;
	}
	return [self imageRepWithContentsOfFile:[url path]];
}

+ (NSArray *)imageRepsWithContentsOfURL:(NSURL *)url
{
	if (url == nil || ![url isFileURL]) {
		fprintf(stderr, "APPKIT-REFUSE: +imageRepsWithContentsOfURL: reads FILE urls only; this tree "
				"has no network image loading\n");
		return nil;
	}
	return [self imageRepsWithContentsOfFile:[url path]];
}

+ (id)imageRepWithPasteboard:(NSPasteboard *)pasteboard
{
	NSArray *types;
	NSUInteger i;

	if (pasteboard == nil) {
		return nil;
	}
	/* ASKED OF THE BOARD RATHER THAN ANSWERED FROM A TABLE: the first type it carries that a registered
	 * class claims is the one tried, which is Apple's contract and the same shape NSImage's own
	 * pasteboard door has. */
	types = [pasteboard types];
	for (i = 0; types != nil && i < [types count]; i++) {
		NSString *t = [types objectAtIndex:i];

		if ([self imageRepClassForPasteboardType:t] != Nil) {
			return fn_rep_from_data([pasteboard dataForType:t], 0);
		}
	}
	return nil;
}

+ (NSArray *)imageRepsWithPasteboard:(NSPasteboard *)pasteboard
{
	NSArray *types;
	NSUInteger i;

	if (pasteboard == nil) {
		return nil;
	}
	types = [pasteboard types];
	for (i = 0; types != nil && i < [types count]; i++) {
		NSString *t = [types objectAtIndex:i];

		if ([self imageRepClassForPasteboardType:t] != Nil) {
			return fn_rep_from_data([pasteboard dataForType:t], 1);
		}
	}
	return nil;
}

@end
