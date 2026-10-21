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
#import <Foundation/NSNotification.h>
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

			if (![c respondsToSelector:sel]) {
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

- (BOOL)drawInRect:(NSRect)rect
{
	NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
	CGImageRef img = [self CGImage];
	CGContextRef cg;
	CGAffineTransform ctm;

	/* NO CONTEXT OR NO PIXELS IS A NO, NOT A RAISE — the same rule the context's own members follow. */
	if (ctx == nil || img == NULL) {
		return NO;
	}
	cg = [ctx CGContext];
	if (cg == NULL) {
		return NO;
	}
	/* **AN IMAGE IS DRAWN UP-RIGHT IN BOTH A FLIPPED VIEW AND AN UNFLIPPED ONE.** `CGContextDrawImage`
	 * paints through the current CTM, so the SAME bytes arrive mirrored in the two cases; the Desktop
	 * (an unflipped view in its own y-up space) and the file window's `WSIconView` (flipped, y-down) are
	 * exactly that pair. MEASURED: before this, Frost's folder icons were up-right on the Desktop and
	 * upside-down in the file window. The existing generic art was made for the y-down path, so the
	 * y-up one is the case that needs the extra mirror. The sign of `d` is the CTM's y direction, and
	 * it is the value the view walk actually puts there; `NSGraphicsContext -isFlipped` is the
	 * WINDOW's statement and stays NO for both. */
	ctm = CGContextGetCTM(cg);
	if (ctm.d > 0.0) {
		CGContextSaveGState(cg);
		CGContextTranslateCTM(cg, rect.origin.x, rect.origin.y + rect.size.height);
		CGContextScaleCTM(cg, 1.0, -1.0);
		CGContextDrawImage(cg, CGRectMake(0.0, 0.0, rect.size.width, rect.size.height), img);
		CGContextRestoreGState(cg);
	} else {
		CGContextDrawImage(cg, NSRectToCGRect(rect), img);
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
