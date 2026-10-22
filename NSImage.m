/*
 * NSImage — a container of representations that answers drawing requests by choosing one.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE OWNERSHIP IS THE WHOLE OF THIS FILE'S DIFFICULTY, and it is small: this class owns `_reps` and
 * nothing else. `-addRepresentation:` RETAINS its argument (an image outlives the local that made the
 * rep), and the array itself is REPLACED rather than mutated, so `-representations` can hand out a
 * snapshot without a caller changing this image's contents through it.
 */
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSURL.h>
#import <AppKit/NSBundleAdditions.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGColorSpace.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphics.h>	/* NSRectFill, the background a composite puts down first */
#import <CoreGraphics/CGContext.h>
#import "AGSystemImages.h"
#import "NSImage_internal.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

/* THE PRIVATE SEAM, DECLARED HERE AND NOT INSIDE THE IMPLEMENTATION. */
@interface NSImage ()
- (void)fnAdoptFocusBuffer:(unsigned char *)buf;
@end

NSString *NSImageNameFollowLinkFreestandingTemplate = @"NSImageNameFollowLinkFreestandingTemplate";
NSString *NSImageNameGoLeftTemplate = @"NSImageNameGoLeftTemplate";

@implementation NSImage

/* ============================================================================================
 * ARCHIVING: AN IMAGE IS A REFERENCE BY NAME, NOT ITS PIXELS.
 * ============================================================================================ */

/* **A DESIGN FILE NAMES AN IMAGE AND DOES NOT CARRY IT.** The alternative — archiving the representations and their
 * bytes — would turn a text-mergeable design into a binary blob and duplicate what `+imageNamed:` already resolves, so
 * what is written is the NAME and what is rebuilt is `+imageNamed:`'s answer. An image with no name is one nothing can
 * look up, and it decodes as the empty image this class's `-init` makes rather than as a failure of the whole nib. */
static NSString * const AGCoderImageNameKey = @"name";
/* **AND THE BACKGROUND, WHICH IS A DESIGN PROPERTY; THE DELEGATE IS NOT.** A colour is part of how an image is meant to
 * look and a design file can carry it; a delegate is a live connection to an object in the running program, and every
 * other class in this tree leaves those out of its archive for the same reason. */
static NSString * const AGCoderImageBackgroundKey = @"backgroundColor";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:[self name] forKey:AGCoderImageNameKey];
	[aCoder encodeObject:_backgroundColor forKey:AGCoderImageBackgroundKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	NSString *name = [aDecoder decodeObjectForKey:AGCoderImageNameKey];
	NSImage *named = nil;

	if ([name isKindOfClass:[NSString class]]) {
		named = [NSImage imageNamed:name];
	}
	if (named != nil) {
		return [named retain];
	}
	self = [super init];
	if (self != nil) {
		if ([name isKindOfClass:[NSString class]]) {
			[self setName:name];
		}
		if ([aDecoder containsValueForKey:AGCoderImageBackgroundKey]) {
			[self setBackgroundColor:[aDecoder decodeObjectForKey:AGCoderImageBackgroundKey]];
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* THE NAMED IMAGES: the same values the header declares, defined here because a constant is a
 * definition and this tree's rule is that nothing is declared without one. THE COMPOSITING OPERATIONS
 * ARE NOT HERE — NSGraphicsContext.h declares and defines them. */

NSString *NSImageNameActionTemplate = @"NSImageNameActionTemplate";
NSString *NSImageNameAddTemplate = @"NSImageNameAddTemplate";
NSString *NSImageNameAdvanced = @"NSImageNameAdvanced";
NSString *NSImageNameApplicationIcon = @"NSImageNameApplicationIcon";
NSString *NSImageNameBluetoothTemplate = @"NSImageNameBluetoothTemplate";
NSString *NSImageNameBonjour = @"NSImageNameBonjour";
NSString *NSImageNameBookmarksTemplate = @"NSImageNameBookmarksTemplate";
NSString *NSImageNameCaution = @"NSImageNameCaution";
NSString *NSImageNameColorPanel = @"NSImageNameColorPanel";
NSString *NSImageNameColumnViewTemplate = @"NSImageNameColumnViewTemplate";
NSString *NSImageNameComputer = @"NSImageNameComputer";
NSString *NSImageNameDotMac = @"NSImageNameDotMac";
NSString *NSImageNameEnterFullScreenTemplate = @"NSImageNameEnterFullScreenTemplate";
NSString *NSImageNameEveryone = @"NSImageNameEveryone";
NSString *NSImageNameExitFullScreenTemplate = @"NSImageNameExitFullScreenTemplate";
NSString *NSImageNameFlowViewTemplate = @"NSImageNameFlowViewTemplate";
NSString *NSImageNameFolder = @"NSImageNameFolder";
NSString *NSImageNameFolderBurnable = @"NSImageNameFolderBurnable";
NSString *NSImageNameFolderSmart = @"NSImageNameFolderSmart";
NSString *NSImageNameFontPanel = @"NSImageNameFontPanel";
NSString *NSImageNameGoRightTemplate = @"NSImageNameGoRightTemplate";
NSString *NSImageNameHomeTemplate = @"NSImageNameHomeTemplate";
NSString *NSImageNameIChatTheaterTemplate = @"NSImageNameIChatTheaterTemplate";
NSString *NSImageNameIconViewTemplate = @"NSImageNameIconViewTemplate";
NSString *NSImageNameInfo = @"NSImageNameInfo";
NSString *NSImageNameInvalidDataFreestandingTemplate = @"NSImageNameInvalidDataFreestandingTemplate";
NSString *NSImageNameLeftFacingTriangleTemplate = @"NSImageNameLeftFacingTriangleTemplate";
NSString *NSImageNameListViewTemplate = @"NSImageNameListViewTemplate";
NSString *NSImageNameLockLockedTemplate = @"NSImageNameLockLockedTemplate";
NSString *NSImageNameLockUnlockedTemplate = @"NSImageNameLockUnlockedTemplate";
NSString *NSImageNameMenuOnStateTemplate = @"NSImageNameMenuOnStateTemplate";
NSString *NSImageNameMenuMixedStateTemplate = @"NSImageNameMenuMixedStateTemplate";
NSString *NSImageNameMobileMe = @"NSImageNameMobileMe";
NSString *NSImageNameMultipleDocuments = @"NSImageNameMultipleDocuments";
NSString *NSImageNameNetwork = @"NSImageNameNetwork";
NSString *NSImageNamePathTemplate = @"NSImageNamePathTemplate";
NSString *NSImageNamePreferencesGeneral = @"NSImageNamePreferencesGeneral";
NSString *NSImageNameQuickLookTemplate = @"NSImageNameQuickLookTemplate";
NSString *NSImageNameRefreshFreestandingTemplate = @"NSImageNameRefreshFreestandingTemplate";
NSString *NSImageNameRefreshTemplate = @"NSImageNameRefreshTemplate";
NSString *NSImageNameRemoveTemplate = @"NSImageNameRemoveTemplate";
NSString *NSImageNameRevealFreestandingTemplate = @"NSImageNameRevealFreestandingTemplate";
NSString *NSImageNameRightFacingTriangleTemplate = @"NSImageNameRightFacingTriangleTemplate";
NSString *NSImageNameSlideshowTemplate = @"NSImageNameSlideshowTemplate";
NSString *NSImageNameSmartBadgeTemplate = @"NSImageNameSmartBadgeTemplate";
NSString *NSImageNameStatusAvailable = @"NSImageNameStatusAvailable";
NSString *NSImageNameStatusNone = @"NSImageNameStatusNone";
NSString *NSImageNameStatusPartiallyAvailable = @"NSImageNameStatusPartiallyAvailable";
NSString *NSImageNameStatusUnavailable = @"NSImageNameStatusUnavailable";
NSString *NSImageNameStopProgressFreestandingTemplate = @"NSImageNameStopProgressFreestandingTemplate";
NSString *NSImageNameStopProgressTemplate = @"NSImageNameStopProgressTemplate";
NSString *NSImageNameTrashEmpty = @"NSImageNameTrashEmpty";
NSString *NSImageNameTrashFull = @"NSImageNameTrashFull";
NSString *NSImageNameUser = @"NSImageNameUser";
NSString *NSImageNameUserAccounts = @"NSImageNameUserAccounts";
NSString *NSImageNameUserGroup = @"NSImageNameUserGroup";
NSString *NSImageNameUserGuest = @"NSImageNameUserGuest";

/* THE BUNDLE LOOKUP, and it uses the SAME resource list `-pathForImageResource:` does, which is the class
 * this tree already has for exactly this question. NO CACHE: a second call re-reads the file rather than
 * answering a copy it owns and never invalidates. */
+ (nullable NSImage *)imageNamed:(NSString *)name
{
	NSString *path;
	NSImage *system;

	if (name == nil) {
		return nil;
	}
	/* **THE PLATFORM'S OWN NAMES COME FIRST, BECAUSE THEY ARE THE PLATFORM'S.** `NSImageNameGoLeftTemplate` is
	 * not a resource anybody ships — it is AppKit's, and on the Mac it answers whether or not the application
	 * has a bundle at all. The twenty names `AGSystemImages` draws are answered here; everything else falls
	 * through to the bundle lookup below, unchanged, which is still the right question for a caller's own art. */
	system = AGSystemImageNamed(name);
	if (system != nil) {
		return system;
	}
	path = [[NSBundle mainBundle] pathForImageResource:name];
	if (path == nil) {
		return nil;
	}
	return [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
}


+ (instancetype)image
{
	return [[[self alloc] initWithSize:NSMakeSize(0.0, 0.0)] autorelease];
}

- (instancetype)init
{
	return [self initWithSize:NSMakeSize(0.0, 0.0)];
}

- (instancetype)initWithSize:(NSSize)size
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_reps = nil;
	_size = size;
	/* AN EXPLICIT SIZE EVEN WHEN IT IS ZERO: `-initWithSize:` means "this is the size", which is what
	 * `+image`'s empty canvas needs — otherwise it would answer a rep's size the moment one was added. */
	_sizeIsExplicit = YES;
	return self;
}

- (nullable instancetype)initWithData:(NSData *)data
{
	NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];

	if (rep == nil) {
		[self release];
		return nil;
	}
	self = [self initWithSize:NSMakeSize(0.0, 0.0)];
	if (self == nil) {
		return nil;
	}
	/* A DECODED IMAGE'S SIZE IS ITS PIXELS UNTIL SOMEONE SAYS OTHERWISE, so this is NOT explicit: the
	 * size follows the representation, which is what `-size`'s precedence is for. */
	_sizeIsExplicit = NO;
	[self addRepresentation:rep];
	return self;
}

- (nullable instancetype)initWithContentsOfFile:(NSString *)path
{
	NSData *data = [NSData dataWithContentsOfFile:path];

	if (data == nil) {
		[self release];
		return nil;
	}
	return [self initWithData:data];
}

- (nullable instancetype)initWithCGImage:(CGImageRef)cgImage size:(NSSize)size
{
	NSBitmapImageRep *rep;

	if (cgImage == NULL) {
		[self release];
		return nil;
	}
	rep = [NSBitmapImageRep imageRepWithCGImage:cgImage];
	if (rep == nil) {
		[self release];
		return nil;
	}
	self = [self initWithSize:size];
	if (self == nil) {
		return nil;
	}
	[self addRepresentation:rep];
	return self;
}

/* ADOPTING THE CANVAS FROM A CLASS METHOD, which cannot touch this instance's ivars: the class method
 * makes the buffer and this instance owns it, and the seam is a private method rather than a
 * friend-style ivar poke. The DECLARATION is in the extension ABOVE `@implementation`, because an
 * `@interface` that opens inside an implementation ENDS it — which the compiler said plainly the first
 * time this was written the other way round. */
- (void)fnAdoptFocusBuffer:(unsigned char *)buf
{
	/* THE OLD ONE GOES FIRST — it was this object's, and the rep that borrowed it has already been
	 * dropped by the caller path that replaces it. */
	if (_focusBuffer != NULL) {
		free(_focusBuffer);
	}
	_focusBuffer = buf;
}

/* ------------------------------------------------------------------------- */
/* Focus: drawing INTO this image                                             */
/* ------------------------------------------------------------------------- */

/* THE REP A LOCK MAKES WHEN THERE IS NONE. It ALLOCATES ITS OWN PIXELS rather than adopting a buffer of
 * ours, and that is the corrected design rather than a preference: the context the drawing goes through and
 * the buffer the rep hands back have to be ONE allocation, and the surest way to be sure of that is for the
 * object that reads them to be the object that owns them. An earlier version had the image own the buffer
 * and hand it over; it is not needed and it left two pointers to keep in step.
 *
 * The format is fixed at 8 bits per sample, four samples, alpha, not planar, device RGB — what Core
 * Graphics' own bitmap context takes without a conversion. */
- (NSBitmapImageRep *)cg_focusRepOfWidth:(NSInteger)w height:(NSInteger)h
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
								      pixelsWide:w
								      pixelsHigh:h
								   bitsPerSample:8
								 samplesPerPixel:4
									hasAlpha:YES
									isPlanar:NO
								  colorSpaceName:NSDeviceRGBColorSpace
								     bytesPerRow:w * 4
								    bitsPerPixel:32];

	if (rep != nil) {
		[self addRepresentation:rep];
		[rep release];
	}
	return rep;
}

/* THE LOCK IS ONE IMPLEMENTATION AND TWO DOORS. `-lockFocus` picks the canvas (the FIRST
 * representation, made if there is none) and `-lockFocusOnRepresentation:` is handed one; everything
 * after that choice is `cg_lockRep:flipped:`, which is below with the rest of the era's doors.
 *
 * THE PIXEL DIMENSIONS COME FROM THE REP AND NOT FROM `_size`, which is the correction the split
 * bought: an image can be 16 points across with an 8-pixel rep, and a context built from `_size` over
 * that rep's buffer writes two rows' worth of pixels past the end of each row it owns. */
- (void)lockFocusFlipped:(BOOL)flipped
{
	NSInteger w = (NSInteger)(_size.width + 0.5);
	NSInteger h = (NSInteger)(_size.height + 0.5);
	NSImageRep *rep;

	/* ONE LOCK AT A TIME, which is Apple's rule too: a nested lock is a caller error, and the honest
	 * response is to leave the first one in force rather than stack contexts nothing can unwind. */
	if (_focusContext != nil) {
		return;
	}
	/* AN IMAGE MADE BY `-initWithSize:` DELIBERATELY HAS NO REPRESENTATION, so the canvas is made here
	 * — and only when there is no rep to make it from. */
	if ([_reps count] == 0) {
		if (w <= 0 || h <= 0) {
			return;
		}
		if ([self cg_focusRepOfWidth:w height:h] == nil) {
			return;
		}
	}
	rep = [_reps objectAtIndex:0];
	if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
		[self cg_lockRep:(NSBitmapImageRep *)rep flipped:flipped];
	}
}

- (void)lockFocus
{
	[self lockFocusFlipped:NO];
}

- (void)unlockFocus
{
	if (_focusContext == nil) {
		return;
	}
	/* PUT BACK WHAT WAS CURRENT, which is nil when this lock was the first thing on the thread — and nil is
	 * right there, because a context that was not current before must not be left current. */
	[NSGraphicsContext setCurrentContext:_focusPrevious];
	[_focusPrevious release];
	_focusPrevious = nil;
	[_focusContext release];
	_focusContext = nil;
	[_focusRep release];
	_focusRep = nil;
}

- (BOOL)isFlipped
{
	return _focusFlipped;
}

- (void)dealloc
{
	[_reps release];
	[_name release];
	/* THE STENCILS A TEMPLATE CARRIES, if it is one: an image made by `AGSystemImageNamed` owns up to three. */
	{
		NSUInteger slot;

		for (slot = 0; slot < 3; slot++) {
			if (_templateMasks[slot] != NULL) {
				CGImageRelease(_templateMasks[slot]);
			}
		}
	}
	/* AND THE DESCRIPTION, which `-setAccessibilityDescription:` COPIED: a copy is this object's to release,
	 * and the first version of this unit forgot it — a leak per image that had ever been given one. */
	[_accessibilityDescription release];
	/* A LOCK THAT WAS NEVER RELEASED: its two contexts and the rep. */
	if (_focusContext != nil) {
		[_focusContext release];
	}
	if (_focusPrevious != nil) {
		[_focusPrevious release];
	}
	if (_focusRep != nil) {
		[_focusRep release];
	}
	/* THE CANVAS IS OURS, AND MUST OUTLIVE THE REP THAT BORROWS IT — which is why it lives here rather
	 * than on the class method's stack. */
	if (_focusBuffer != NULL) {
		free(_focusBuffer);
	}
	[super dealloc];
}

- (void)addRepresentation:(NSImageRep *)imageRep
{
	NSMutableArray *next;

	if (imageRep == nil) {
		return;
	}
	/* A NEW ARRAY EACH TIME, so the snapshot handed out by `-representations` is never the one being
	 * mutated. The copy is `+arrayWithArray:` rather than a hand-rolled move for the ordinary reason:
	 * a hand-rolled one is where the retain/autorelease bug lives. */
	next = [NSMutableArray arrayWithArray:_reps != nil ? _reps : [NSArray array]];
	[next addObject:imageRep];
	[_reps release];
	_reps = [next copy];
}

- (void)removeRepresentation:(NSImageRep *)imageRep
{
	NSMutableArray *next;

	if (imageRep == nil || _reps == nil) {
		return;
	}
	next = [NSMutableArray arrayWithArray:_reps];
	[next removeObjectIdenticalTo:imageRep];
	[_reps release];
	_reps = [next copy];
}

- (NSArray *)representations
{
	/* A NEW, AUTORELEASED ARRAY, AND NOT `_reps` ITSELF. `-addRepresentation:` and
	 * `-removeRepresentation:` REPLACE `_reps` (releasing the array that was there), so a getter that
	 * handed out `_reps` would give the caller a snapshot that the NEXT add or remove INVALIDATES.
	 * THAT WAS THE BUG, MEASURED (2026-10-07): `appkit_image` takes the array, adds a representation, and
	 * reads the array it took — Apple's own contract is that the first array is unaffected — and the HOST
	 * process SEGFAULTED on the freed array. On the guest it would have read bytes that still look like an
	 * array, which is the musl-vs-glibc silence this tree has recorded before.
	 *
	 * `[_reps copy]` WOULD NOT FIX IT: this tree's `-copy` on an immutable array is `[self retain]`
	 * (NSArray.m: "copy is an OWNED family — immutable"), so an autoreleased copy would still be the very
	 * array the next add releases. `+arrayWithArray:` is the call that makes a distinct one. */
	return _reps != nil ? [NSArray arrayWithArray:_reps] : [NSArray array];
}

- (NSSize)size
{
	if (_sizeIsExplicit) {
		return _size;
	}
	if (_reps != nil && [_reps count] > 0) {
		return [[_reps objectAtIndex:0] size];
	}
	return _size;
}

- (void)setSize:(NSSize)s
{
	_size = s;
	_sizeIsExplicit = YES;
}

- (BOOL)isValid
{
	return _reps != nil && [_reps count] > 0;
}

- (nullable NSImageRep *)bestRepresentationForRect:(NSRect)rect
					   context:(nullable NSGraphicsContext *)referenceContext
					     hints:(nullable NSDictionary *)hints
{
	/* THE CLOSEST IN POINTS, ties to the FIRST — the decision this class is allowed to make. A caller
	 * who wants a different rule can walk `-representations` itself, which is why this stays simple
	 * rather than growing a scoring model. */
	NSImageRep *best = nil;
	double bestDist = 0.0;
	NSUInteger i;

	(void)referenceContext;
	(void)hints;
	if (_reps == nil) {
		return nil;
	}
	for (i = 0; i < [_reps count]; i++) {
		NSImageRep *rep = [_reps objectAtIndex:i];
		NSSize s = [rep size];
		double d = fabs(s.width - rect.size.width) + fabs(s.height - rect.size.height);

		if (best == nil || d < bestDist) {
			best = rep;
			bestDist = d;
		}
	}
	return best;
}

/* ---- TEMPLATES AND THEIR INK --------------------------------------------------------------- */

- (void)cg_setTemplateMask:(CGImageRef)mask forSize:(NSInteger)points
{
	NSUInteger slot;

	_template = YES;
	/* THE SLOT FOR THIS SIZE, or the first empty one: the table is filled once, by size, and a second call for a
	 * size that is already there replaces it (and releases what it replaced, because this image owns the mask). */
	for (slot = 0; slot < 3; slot++) {
		if (_templateMasks[slot] == NULL || _templateMaskSizes[slot] == points) {
			if (mask != NULL) {
				CGImageRetain(mask);
			}
			if (_templateMasks[slot] != NULL) {
				CGImageRelease(_templateMasks[slot]);
			}
			_templateMasks[slot] = mask;
			_templateMaskSizes[slot] = points;
			return;
		}
	}
}

/* **THE STENCIL CLOSEST TO THE RECTANGLE, PREFERRING ONE AT LEAST AS BIG.** A stencil SCALED UP is the case that
 * looks wrong — it invents pixels the glyph never had — so 24 points wants the 24 stencil, and anything between 24
 * and 32 gets the 32 (drawn down), not the 24 (drawn up). The sampler interpolates when it has to, and a native
 * size is untouched by that. */
- (CGImageRef)cg_templateMaskForRect:(NSRect)rect
{
	CGFloat wanted = rect.size.width;
	CGImageRef best = NULL;
	NSInteger bestDistance = 0;
	NSInteger bestSize = 0;
	NSUInteger slot;

	for (slot = 0; slot < 3; slot++) {
		NSInteger distance;

		if (_templateMasks[slot] == NULL) {
			continue;
		}
		distance = (NSInteger)labs((long)(_templateMaskSizes[slot] - (NSInteger)(wanted + 0.5)));
		/* THE CLOSEST, AND ON A TIE THE LARGER: 20 points is as near to 16 as to 24, and the 24 drawn down is a
		 * better picture than the 16 drawn up. */
		if (best == NULL || distance < bestDistance ||
		    (distance == bestDistance && _templateMaskSizes[slot] > bestSize)) {
			best = _templateMasks[slot];
			bestDistance = distance;
			bestSize = _templateMaskSizes[slot];
		}
	}
	return best;
}

- (BOOL)cg_drawInRect:(NSRect)rect ink:(NSColor *)ink
{
	CGImageRef mask = [self cg_templateMaskForRect:rect];
	NSGraphicsContext *ctx = [NSGraphicsContext currentContext];
	CGContextRef cg;

	if (mask == NULL || ink == nil || ctx == nil) {
		return NO;
	}
	cg = [ctx CGContext];
	if (cg == NULL) {
		return NO;
	}
	/* **AND THE RECTANGLE IS SNAPPED TO WHOLE POINTS, WHICH IS WHAT KEEPS A GLYPH SHARP.** A toolbar lays its
	 * items out from measured label widths, so an icon lands at x.2 or x.6; a stencil sampled at a fractional
	 * offset is either blocky (nearest) or soft (interpolated) — MEASURED both ways, and both look wrong at sixteen
	 * points. Snapping the ORIGIN and leaving the SIZE alone is the half that matters: a 24-point stencil drawn in
	 * a 24-point box on a whole point is a 1:1 sample of its own texels, with no blending at all. */
	rect.origin.x = floor((double)rect.origin.x + 0.5);
	rect.origin.y = floor((double)rect.origin.y + 0.5);
	/* **CLIP TO THE GLYPH AND FILL THE WHOLE RECTANGLE: that IS a template image.** The stencil carries the
	 * shape, the ink carries the colour, and the two come together here rather than in twenty pre-tinted copies
	 * of the same picture. `CGContextClipToMask`'s rectangle is in USER space, so a flipped view needs nothing
	 * extra — the caller's rect is already in the space it draws in. */
	CGContextSaveGState(cg);
	CGContextClipToMask(cg, CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height), mask);
	[ink setFill];
	/* **THE FILL IS INSET BY HALF A POINT SO ITS OWN EDGE LANDS INSIDE THE STENCIL.** A clipped fill still
	 * antialiases its own outline, and a stencil only governs the pixels INSIDE the rectangle it was given —
	 * outside it, CoreGraphics leaves the clip as it was, by design. So a fill whose edge sits on the stencil's
	 * edge paints a one-pixel fringe where no stencil applies: MEASURED as a vertical line beside every toolbar
	 * icon, at about a third of the ink's strength. Half a point pulls that fringe in among the glyph's own
	 * margin, where the coverage is zero and nothing shows. */
	[[NSBezierPath bezierPathWithRect:NSInsetRect(rect, 0.5, 0.5)] fill];
	CGContextRestoreGState(cg);
	return YES;
}

/* **THE COMPOSITE'S ONE WORKER, WHICH IS WHERE THE BACKGROUND, THE DELEGATE AND THE REP MEET.** The rep is chosen for
 * the destination rect (the best one for the size that is wanted); if there is none, the DELEGATE is asked for one, and
 * a delegate that answers nil has drawn the picture itself — which is Apple's contract and the reason this returns YES
 * in that case. The background goes down FIRST and only when one was set, so nil leaves the destination exactly as it
 * was and every picture this class drew before this door existed is unchanged. */
- (BOOL)cg_drawInRect:(NSRect)dstRect
	     fromRect:(NSRect)srcRect
	    operation:(NSCompositingOperation)op
	     fraction:(CGFloat)delta
       respectFlipped:(BOOL)respectFlipped
		hints:(NSDictionary *)hints
{
	NSImageRep *rep = [self bestRepresentationForRect:dstRect context:nil hints:hints];

	if (rep == nil && _delegate != nil && [_delegate respondsToSelector:@selector(imageDidNotDraw:inRect:)]) {
		NSImageRep *substitute = [(id <NSImageDelegate>)_delegate imageDidNotDraw:self inRect:dstRect];

		if (substitute == nil) {
			return YES;	/* it drew the picture itself, which is Apple's reading of a nil answer */
		}
		rep = substitute;
	}
	if (rep == nil) {
		return NO;
	}
	if (_backgroundColor != nil) {
		NSGraphicsContext *ctx = [NSGraphicsContext currentContext];

		if (ctx != nil) {
			[(NSColor *)_backgroundColor setFill];
			NSRectFill(dstRect);
		}
	}
	return [rep drawInRect:dstRect fromRect:srcRect operation:op fraction:delta
	       respectFlipped:respectFlipped hints:hints];
}

- (BOOL)drawInRect:(NSRect)rect
{
	/* THE 10.0 DOOR IS THE WIDE ONE WITH ITS ARGUMENTS FILLED IN, so there is one drawing path rather than four. */
	return [self drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0
		 respectFlipped:YES hints:nil];
}

- (BOOL)drawAtPoint:(NSPoint)point fromRect:(NSRect)srcRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta
{
	NSSize extent = (srcRect.size.width > 0.0 && srcRect.size.height > 0.0) ? srcRect.size : [self size];

	return [self drawInRect:NSMakeRect(point.x, point.y, extent.width, extent.height)
		       fromRect:srcRect operation:op fraction:delta respectFlipped:YES hints:nil];
}

- (BOOL)drawInRect:(NSRect)dstRect
	  fromRect:(NSRect)srcRect
	 operation:(NSCompositingOperation)op
	  fraction:(CGFloat)delta
{
	return [self drawInRect:dstRect fromRect:srcRect operation:op fraction:delta respectFlipped:YES hints:nil];
}

- (BOOL)drawInRect:(NSRect)dstRect
	  fromRect:(NSRect)srcRect
	 operation:(NSCompositingOperation)op
	  fraction:(CGFloat)delta
    respectFlipped:(BOOL)respectFlipped
	     hints:(NSDictionary *)hints
{
	return [self cg_drawInRect:dstRect fromRect:srcRect operation:op fraction:delta
		  respectFlipped:respectFlipped hints:hints];
}

/* ---- THE BACKGROUND AND THE DELEGATE ------------------------------------------------------------ */

- (NSColor *)backgroundColor
{
	return (NSColor *)_backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)aColor
{
	if (aColor != _backgroundColor) {
		id held = [aColor retain];

		[_backgroundColor release];
		_backgroundColor = held;
	}
}

- (id <NSImageDelegate>)delegate
{
	return (id <NSImageDelegate>)_delegate;
}

- (void)setDelegate:(id <NSImageDelegate>)anObject
{
	_delegate = anObject;	/* NOT RETAINED — see the ivar */
}

/* THE TYPE LISTS. The FILTERED ones are what this class can actually read — PNG and JPEG, which is what
 * the rep decodes — and the UNFILTERED ones are the same set, stated with the reason rather than padded with
 * formats nothing here decodes: a caller consults the filtered list before handing over bytes, so a longer
 * list would only move the failure from the list to the call.
 *
 * ANSI C PICKED THE SIZES: `const char *` arrays compiled in, wrapped in an autoreleased NSArray per call
 * rather than cached, because the array is four strings and a cache would be a lifetime to own. */
+ (NSArray *)imageFileTypes
{
	return [NSArray arrayWithObjects:@"png", @"jpg", @"jpeg", nil];
}

/* **AND THE UTI LISTS ARE THE REGISTRY'S.** A class that decodes a format declares its types where its decoder is
 * (`NSBitmapImageRep` does, and would again for a second format), so writing a second table here would be the same fact
 * in two places and a divergence waiting to happen. The filtered pair is one list for the reason the rep header gives. */
+ (NSArray *)imageTypes
{
	return [NSImageRep imageTypes];
}

+ (NSArray *)imageUnfilteredTypes
{
	return [NSImageRep imageUnfilteredTypes];
}

+ (NSArray *)imageUnfilteredFileTypes
{
	return [self imageFileTypes];
}

/* **AND THE PASTEBOARD LIST IS THE REGISTRY'S TOO, WHICH CORRECTS A LIST THAT PREDATED THE DECODERS.** It said
 * `NSStringPboardType` and `NSTIFFPboardType`: neither is a format this layer decodes — TIFF has no decoder and a string
 * is not an image — while PNG and JPEG, which it does decode, were absent. So `+canInitWithPasteboard:` answered NO for
 * a board holding a PNG and YES for one holding a TIFF it would then fail to read. The list that belongs here is the
 * one the classes that decode publish; see `+imageTypes` next door for the same reasoning. */
+ (NSArray *)imagePasteboardTypes
{
	return [NSImageRep imagePasteboardTypes];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	return [self imagePasteboardTypes];
}

/* ASKING THE PASTEBOARD IS ASKING WHETHER ANY OF ITS TYPES IS ONE OF OURS — the same question as the lists
 * above, asked of a live board rather than of a table. */
+ (BOOL)canInitWithPasteboard:(NSPasteboard *)pasteboard
{
	if (pasteboard == nil) {
		return NO;
	}
	return [pasteboard availableTypeFromArray:[self imagePasteboardTypes]] != nil;
}

- (void)addRepresentations:(NSArray *)imageReps
{
	NSUInteger i;

	if (imageReps == nil) {
		return;
	}
	for (i = 0; i < [imageReps count]; i++) {
		[self addRepresentation:[imageReps objectAtIndex:i]];
	}
}

/* DRAWING ONE REP: the rep is asked to draw in the CURRENT context, which is the one the caller has made
 * current, and the rect is passed through unchanged. A nil rep or an empty rect is a refusal rather than a
 * crash, and the answer says which happened. */
- (BOOL)drawRepresentation:(NSImageRep *)imageRep inRect:(NSRect)rect
{
	if (imageRep == nil || rect.size.width <= 0.0 || rect.size.height <= 0.0) {
		return NO;
	}
	return [imageRep drawInRect:rect];
}

- (NSImageRep *)bestRepresentationForDevice:(NSDictionary *)deviceDescription
{
	(void)deviceDescription;
	/* NO DEVICE IS DESCRIBED HERE: this tree draws to one surface, so "the best rep for this device" is the
	 * best rep for the rect it will be drawn in — which is the method the class already has. */
	return (_reps != nil && [_reps count] > 0) ? [_reps objectAtIndex:0] : nil;
}

/* THE TWO EAGER REFERENCE DOORS. Apple's defer the read; a deferred read is a lifetime this class would
 * have to own and invalidate, and the caller already asked for the image — so these read and answer. */
- (instancetype)initWithContentsOfURL:(NSURL *)url
{
	if (url == nil || ![url isFileURL]) {
		[self release];
		return nil;
	}
	return [self initWithContentsOfFile:[url path]];
}

- (instancetype)initByReferencingFile:(NSString *)fileName
{
	[self release];
	return [[NSImage alloc] initWithContentsOfFile:fileName];
}

- (instancetype)initByReferencingURL:(NSURL *)url
{
	[self release];
	return [[NSImage alloc] initWithContentsOfURL:url];
}

- (void)setFlipped:(BOOL)flag
{
	/* THE ORIENTATION THE NEXT LOCK USES, which is what the focus pair reads and what `-isFlipped` answers. */
	_focusFlipped = flag;
}

- (void)cancelIncrementalLoad
{
	/* NOTHING LOADS IN STAGES HERE: `-initWithContentsOfFile:` reads the file whole, so there is no partial
	 * load to cancel and a no-op is the honest answer rather than an invented cancellation. */
}

- (BOOL)drawAtPoint:(NSPoint)point
{
	NSSize s = [self size];

	return [self drawInRect:NSMakeRect(point.x, point.y, s.width, s.height)];
}

/* BGRA -> RGBA, PREMULTIPLIED ON BOTH SIDES SO NO UN-PREMULTIPLY IS OWED. The source is this tree's
 * bitmap-context format (alpha first in a little-endian word, which in MEMORY is B, G, R, A) and the
 * destination is what a rep's `-CGImage` is built with (alpha last, so R, G, B, A). Getting this
 * backwards is not subtle for long: red comes back blue, which is exactly what the probe checks. */
static void fn_swizzle_bgra_to_rgba(const unsigned char *src, unsigned char *dst, size_t pixels)
{
	size_t i;

	for (i = 0; i < pixels; i++) {
		dst[0] = src[2];
		dst[1] = src[1];
		dst[2] = src[0];
		dst[3] = src[3];
		src += 4;
		dst += 4;
	}
}

+ (nullable instancetype)imageWithSize:(NSSize)size
			       flipped:(BOOL)flipped
			drawingHandler:(nullable BOOL (^)(NSRect dstRect))drawingHandler
{
	NSImage *im = nil;
	unsigned char *canvas;
	unsigned char *buf;
	CGColorSpaceRef cs;
	CGContextRef ctx = NULL;
	NSGraphicsContext *gstate = nil;
	NSGraphicsContext *prev = nil;
	NSInteger w = (NSInteger)ceil(size.width);
	NSInteger h = (NSInteger)ceil(size.height);
	size_t n;

	if (drawingHandler == nil) {
		fprintf(stderr, "APPKIT-REFUSE: +imageWithSize:flipped:drawingHandler: needs a handler\n");
		return nil;
	}
	if (w <= 0 || h <= 0) {
		fprintf(stderr, "APPKIT-REFUSE: +imageWithSize:flipped:drawingHandler: with a size of "
				"%gx%g has no pixels to draw into\n", (double)size.width, (double)size.height);
		return nil;
	}
	n = (size_t)w * (size_t)h * 4u;
	canvas = calloc(1, n);
	buf = malloc(n);
	if (canvas == NULL || buf == NULL) {
		free(canvas);
		free(buf);
		return nil;
	}
	cs = CGColorSpaceCreateDeviceRGB();
	/* THE HANDLER'S CANVAS KEEPS ITS OWN BYTE ORDER, which is NOT the focus path's: this one becomes a rep
	 * through a different door, and its probe's colour round trip — "with the RED still RED", which that
	 * path already had — passes with B, G, R, A. Changing it to match the focus path broke that check
	 * immediately, which is the measurement and not a guess. */
	ctx = CGBitmapContextCreate(canvas, (size_t)w, (size_t)h, 8, (size_t)w * 4u, cs,
				    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	CGColorSpaceRelease(cs);
	if (ctx == NULL) {
		free(canvas);
		free(buf);
		return nil;
	}
	/* A FRESH CANVAS IS EMPTY, not whatever the allocator had. */
	CGContextClearRect(ctx, CGRectMake(0.0, 0.0, (CGFloat)w, (CGFloat)h));
	/* THE FLAG IS HONOURED BY FLIPPING THE CTM, because NSGraphicsContext's `flipped` is a STATEMENT
	 * about the context rather than a transform it applies to it — and the transform is needed for
	 * `flipped:YES`, which is AppKit's y-DOWN system.
	 *
	 * **THE CONDITION WAS INVERTED FOR A WHOLE SLICE, AND THIS IS THE SECOND CORRECTION TO IT.** The
	 * first version applied the mirror for YES and pushed the handler's rect to y-2h — an EMPTY canvas,
	 * silently — and the fix for THAT swapped the branch as well as correcting the ORDER. That made the
	 * code self-consistent and the LABELS WRONG: YES produced a y-up space and NO a y-down one, exactly
	 * backwards. C8.12's probe could not see it because it asserted only that the two land in OPPOSITE
	 * halves — never WHICH half each means — and a swapped pair satisfies that just as well.
	 *
	 * WHAT FINALLY MEASURED IT was the view probe's subview placement: a child of a flipped view drew
	 * into the BOTTOM of its frame instead of the top, with the CTM printed and correct
	 * (`a=1 d=-1 tx=4 ty=8`), which left the canvas's own orientation as the only remaining
	 * explanation.
	 *
	 * THE GROUND TRUTH, and it is what the probe now PINS rather than merely compares: with NO
	 * transform the canvas's user y grows UP (the ordinary Core Graphics convention), so a handler
	 * filling its own y in [0, 2) lands in the BOTTOM rows; with the mirror below it lands in the TOP
	 * rows, which is what AppKit's flipped:YES means.
	 */
	if (flipped) {
		/* TRANSLATE FIRST, THEN SCALE — and the order is not a style choice, it is what each call
		 * MEANS. `CGContextTranslateCTM` and `CGContextScaleCTM` change the CTM in the CURRENT USER
		 * space, which Apple states as `CGContextConcatCTM(c, CGAffineTransformMake…)` — "the resulting
		 * CTM in the context is `CTMnew = transform * CTMcontext`" (`concatenate(_:)`). From the bitmap
		 * default (d=-1, ty=h):
		 *     Translate(0,h)      -> d=-1, ty=0
		 *     then Scale(1,-1)    -> d=1,  ty=0    == IDENTITY, which here is y-DOWN.
		 * THE COMMENT HERE USED TO SAY THE OTHER ORDER WAS THE ONE THAT WORKED, AND IT WAS RIGHT ABOUT
		 * THE OLD IMPLEMENTATION: the two doors composed the transform on the side that makes it act on
		 * DEVICE coordinates, so `Scale(1,-1)` then `Translate(0,h)` was the pair that reached the
		 * identity. This file was written to match that, measured from the printed CTM. The doors were
		 * fixed (coregraphics-plan §46) and this call order and this comment were corrected with them. */
		CGContextTranslateCTM(ctx, 0.0, (CGFloat)h);
		CGContextScaleCTM(ctx, 1.0, -1.0);
	}
	gstate = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:flipped];
	if (gstate == nil) {
		CGContextRelease(ctx);
		free(canvas);
		free(buf);
		return nil;
	}
	prev = [[NSGraphicsContext currentContext] retain];
	[NSGraphicsContext setCurrentContext:gstate];
	/* THE HANDLER DRAWS; ITS ANSWER IS DISCARDED, as Apple's is. */
	(void)drawingHandler(NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h));
	[NSGraphicsContext setCurrentContext:prev];
	[prev release];

	im = [[self alloc] initWithSize:size];
	if (im != nil) {
		unsigned char *planes[1];
		NSBitmapImageRep *rep;

		fn_swizzle_bgra_to_rgba(canvas, buf, (size_t)w * (size_t)h);
		planes[0] = buf;
		rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:planes pixelsWide:w
					pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
					isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
					bytesPerRow:w * 4 bitsPerPixel:32];
		if (rep == nil) {
			[im release];
			im = nil;
			free(buf);
		} else {
			[im addRepresentation:rep];
			[im fnAdoptFocusBuffer:buf];
			[rep release];
		}
	} else {
		free(buf);
	}
	CGContextRelease(ctx);
	free(canvas);
	return [im autorelease];
}

/* ============================================================================================ *
 * THE ERA'S REMAINING DOORS. Everything below is 10.2-through-10.6 surface the ledger owes, and it *
 * divides into three kinds, each of which is stated where it lands: doors that WORK (the snapshot, *
 * the hit test, the composite, the pasteboard), doors that RECORD state a cache would have read (the *
 * four switches, the name), and doors that REFUSE by name (TIFF).                              *
 * ============================================================================================ */

/* THE HINTS. Their values are their own identifiers, the same choice the named images make. */
NSString *NSImageHintCTM = @"NSImageHintCTM";
NSString *NSImageHintInterpolation = @"NSImageHintInterpolation";

/* THE SNAPSHOT. Apple's own text says the rect is IN AND OUT: the caller proposes a destination and
 * the method answers the pixel-INTEGRAL rect the returned image actually covers, because a CGImage
 * has whole pixels and an NSImage need not. The ROUNDING is the REP's, since the rep is what knows
 * what it can produce; what this class contributes is the CHOICE of representation. */
- (nullable CGImageRef)CGImageForProposedRect:(nullable NSRect *)proposedDestRect
				      context:(nullable NSGraphicsContext *)referenceContext
					hints:(nullable NSDictionary *)hints
{
	NSRect want;
	NSImageRep *rep;

	if (proposedDestRect != NULL) {
		want = *proposedDestRect;
	} else {
		NSSize s = [self size];

		want = NSMakeRect(0.0, 0.0, s.width, s.height);
	}
	rep = [self bestRepresentationForRect:want context:referenceContext hints:hints];
	if (rep == nil) {
		return NULL;
	}
	/* THE REP ANSWERS, because that is where the pixels are: this class chooses WHICH representation
	 * and the rep produces the image and does the rect rounding. Two implementations of the outward
	 * rect would be two chances to disagree about it. */
	return [rep CGImageForProposedRect:proposedDestRect context:referenceContext hints:hints];
}

/* THE HIT TEST, AND THE ONE DECISION IN IT IS WHAT "READABLE PIXELS" MEANS. Apple asks whether the
 * test rect would touch a NON-TRANSPARENT part of the image; the only way to answer without drawing is
 * to read the chosen representation's own bytes, so this works for a representation that HAS readable
 * pixels and answers NO for one that does not — stated rather than discovered, because a rep built
 * from a CGImage with no data provider would otherwise be a silent NO.
 *
 * THE MAPPING IS THE INTERESTING PART AND IT IS THE SAME PAIR `flipped:` MEANS EVERYWHERE ELSE:
 * with flipped NO the destination's y grows UP, so the image's FIRST row (its top) lands at the rect's
 * TOP; with flipped YES the destination is AppKit's y-DOWN space and the first row lands at the
 * rect's LOWER y. Getting this backwards moves the test by a whole image height and would still pass
 * a check that only asked "does it intersect the middle". */
- (BOOL)hitTestRect:(NSRect)testRectDestSpace
withImageDestinationRect:(NSRect)imageRectDestSpace
	    context:(nullable NSGraphicsContext *)context
	      hints:(nullable NSDictionary *)hints
	    flipped:(BOOL)flipped
{
	NSImageRep *rep = [self bestRepresentationForRect:imageRectDestSpace context:context hints:hints];
	NSBitmapImageRep *bitmap;
	NSRect overlap;
	double sx, sy;
	NSInteger pw, ph, stride, spp;
	NSInteger x0, x1, y0, y1, x, yl;
	unsigned char *px;

	if (rep == nil || imageRectDestSpace.size.width <= 0.0 || imageRectDestSpace.size.height <= 0.0) {
		return NO;
	}
	if (![rep isKindOfClass:[NSBitmapImageRep class]]) {
		return NO;
	}
	bitmap = (NSBitmapImageRep *)rep;
	overlap = NSIntersectionRect(testRectDestSpace, imageRectDestSpace);
	if (overlap.size.width <= 0.0 || overlap.size.height <= 0.0) {
		return NO;
	}
	pw = [bitmap pixelsWide];
	ph = [bitmap pixelsHigh];
	px = [bitmap bitmapData];
	stride = [bitmap bytesPerRow];
	spp = [bitmap samplesPerPixel];
	if (px == NULL || pw <= 0 || ph <= 0 || stride <= 0 || spp <= 0) {
		return NO;
	}
	/* A REP WITH NO ALPHA CHANNEL IS ENTIRELY OPAQUE, so the answer is YES and no bytes need reading. */
	if (![bitmap hasAlpha] || spp < 4) {
		return YES;
	}
	sx = (double)pw / (double)imageRectDestSpace.size.width;
	sy = (double)ph / (double)imageRectDestSpace.size.height;
	x0 = (NSInteger)floor(((double)NSMinX(overlap) - (double)NSMinX(imageRectDestSpace)) * sx);
	x1 = (NSInteger)ceil(((double)NSMaxX(overlap) - (double)NSMinX(imageRectDestSpace)) * sx);
	y0 = (NSInteger)floor(((double)NSMinY(overlap) - (double)NSMinY(imageRectDestSpace)) * sy);
	y1 = (NSInteger)ceil(((double)NSMaxY(overlap) - (double)NSMinY(imageRectDestSpace)) * sy);
	if (x0 < 0) {
		x0 = 0;
	}
	if (y0 < 0) {
		y0 = 0;
	}
	if (x1 > pw) {
		x1 = pw;
	}
	if (y1 > ph) {
		y1 = ph;
	}
	for (yl = y0; yl < y1; yl++) {
		/* THE ROW, FROM THE DISTANCE UP THE RECT: rows are stored top-first. */
		NSInteger row = flipped ? yl : (ph - 1 - yl);

		for (x = x0; x < x1; x++) {
			if (px[(size_t)row * (size_t)stride + (size_t)x * (size_t)spp + 3u] != 0) {
				return YES;
			}
		}
	}
	return NO;
}

/* THE COMPOSITE DOORS, AND THE SUBSTRATE'S ONE LIMIT IS STATED RATHER THAN HIDDEN. Each sets the
 * composition on the CURRENT context — through `NSGraphicsContext`, which owns the enum-to-operator
 * mapping and its own refusal arm — and then draws. The draw goes through `CGContextDrawImage`, whose
 * sampler applies `Normal` and `Copy` and REFUSES every other operation by name (it has no blend
 * matrix; coregraphics-plan §46). So `NSCompositeCopy` and the `SourceOver` forms are real here and
 * the rest are refused with a message that says why, which is this tree's standing preference over
 * approximating a blend it cannot do. */
- (void)cg_compositeToPoint:(NSPoint)point
		     source:(NSRect)src
		  hasSource:(BOOL)hasSource
		  operation:(NSCompositingOperation)op
		   fraction:(CGFloat)delta
{
	NSGraphicsContext *g = [NSGraphicsContext currentContext];
	CGContextRef c;
	CGImageRef image = NULL;
	CGImageRef crop = NULL;
	NSSize s;

	if (g == nil) {
		return;
	}
	c = [g CGContext];
	if (c == NULL) {
		return;
	}
	s = [self size];
	image = [self CGImageForProposedRect:NULL context:g hints:nil];
	if (image == NULL) {
		return;
	}
	if (hasSource) {
		crop = CGImageCreateWithImageInRect(image, CGRectMake(src.origin.x, src.origin.y,
								      src.size.width, src.size.height));
		if (crop == NULL) {
			return;
		}
		image = crop;
	}
	[g setCompositingOperation:op];
	CGContextSetAlpha(c, delta);
	CGContextDrawImage(c, CGRectMake(point.x, point.y, s.width, s.height), image);
	CGContextSetAlpha(c, 1.0);
	if (crop != NULL) {
		CGImageRelease(crop);
	}
}

- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op
{
	[self cg_compositeToPoint:point source:NSZeroRect hasSource:NO operation:op fraction:1.0];
}

- (void)compositeToPoint:(NSPoint)point fromRect:(NSRect)rect operation:(NSCompositingOperation)op
{
	[self cg_compositeToPoint:point source:rect hasSource:YES operation:op fraction:1.0];
}

- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op fraction:(CGFloat)delta
{
	[self cg_compositeToPoint:point source:NSZeroRect hasSource:NO operation:op fraction:delta];
}

- (void)compositeToPoint:(NSPoint)point
		fromRect:(NSRect)rect
	       operation:(NSCompositingOperation)op
		fraction:(CGFloat)delta
{
	[self cg_compositeToPoint:point source:rect hasSource:YES operation:op fraction:delta];
}

/* "DISSOLVE" IS SOURCE-OVER WITH A FRACTION, which is the whole of the difference — the name is the
 * era's, the arithmetic is the composite above. */
- (void)dissolveToPoint:(NSPoint)point fraction:(CGFloat)aFloat
{
	[self cg_compositeToPoint:point source:NSZeroRect hasSource:NO
			operation:NSCompositingOperationSourceOver fraction:aFloat];
}

- (void)dissolveToPoint:(NSPoint)point fromRect:(NSRect)rect fraction:(CGFloat)aFloat
{
	[self cg_compositeToPoint:point source:rect hasSource:YES
			operation:NSCompositingOperationSourceOver fraction:aFloat];
}

/* THE NAME. `-setName:` answers YES, and clearing the name with nil is the same success — there is no
 * failure this door has, so the era's BOOL is always YES rather than a fiction about validating. */
- (BOOL)setName:(nullable NSString *)string
{
	NSString *copy = [string copy];

	[_name release];
	_name = copy;
	return YES;
}

- (nullable NSString *)name
{
	return _name;
}

/* THE FOUR CACHE SWITCHES, RECORDED AND NOT ACTED ON — see the header for why that is the honest
 * maximum rather than a stub. */
- (void)setScalesWhenResized:(BOOL)flag
{
	_scalesWhenResized = flag;
}

- (BOOL)scalesWhenResized
{
	return _scalesWhenResized;
}

- (void)setDataRetained:(BOOL)flag
{
	_dataRetained = flag;
}

- (BOOL)isDataRetained
{
	return _dataRetained;
}

- (void)setCachedSeparately:(BOOL)flag
{
	_cachedSeparately = flag;
}

- (BOOL)isCachedSeparately
{
	return _cachedSeparately;
}

- (void)setCacheDepthMatchesImageDepth:(BOOL)flag
{
	_cacheDepthMatchesImageDepth = flag;
}

- (BOOL)cacheDepthMatchesImageDepth
{
	return _cacheDepthMatchesImageDepth;
}

- (void)recache
{
	/* NOTHING TO THROW AWAY: this class keeps no cache, which is the same reason the four switches
	 * above record rather than act. Apple's own note says a caller can drop the call. */
}

/* THE ENCODING DOORS, WHICH REFUSE BY NAME. Not "not implemented" but a reason with a measurement in
 * it: this tree's CoreGraphics has the two DECODERS and no `CGImageDestination`, so there is nothing
 * to encode WITH and an answer of nil is the truth rather than an approximation of TIFF. */
- (nullable NSData *)TIFFRepresentation
{
	fprintf(stderr, "APPKIT-REFUSE: -TIFFRepresentation needs an ENCODER; this tree's CoreGraphics "
			"has the PNG and JPEG decoders and no CGImageDestination, so there is nothing to "
			"encode with\n");
	return nil;
}

- (nullable NSData *)TIFFRepresentationUsingCompression:(NSTIFFCompression)comp factor:(float)aFloat
{
	(void)comp;
	(void)aFloat;
	return [self TIFFRepresentation];
}

/* THE PASTEBOARD DOOR, AND IT NEEDS NO TYPE TABLE: Apple's contract is "the first type the board
 * carries that this class can use", so the question is asked of the board rather than answered from a
 * list — each of the board's types is offered to the decoder and the first that decodes wins. A board
 * holding only text answers nil, which is the same answer an image class should give for text. */
- (nullable instancetype)initWithPasteboard:(nullable NSPasteboard *)pasteboard
{
	NSArray *types;
	NSUInteger i;

	if (pasteboard == nil) {
		[self release];
		return nil;
	}
	types = [pasteboard types];
	for (i = 0; i < [types count]; i++) {
		NSData *data = [pasteboard dataForType:[types objectAtIndex:i]];
		NSBitmapImageRep *rep;

		if (data == nil) {
			continue;
		}
		rep = [NSBitmapImageRep imageRepWithData:data];
		if (rep == nil) {
			continue;
		}
		self = [self initWithSize:NSMakeSize(0.0, 0.0)];
		if (self == nil) {
			return nil;
		}
		/* THE SIZE FOLLOWS THE REP, as it does for `-initWithData:`. */
		_sizeIsExplicit = NO;
		[self addRepresentation:rep];
		return self;
	}
	[self release];
	return nil;
}

/* ORIENTATION IS ALREADY IGNORED — this decoder reads PNG and JPEG pixels and applies no EXIF
 * rotation at all — so the "ignoring orientation" door IS `-initWithData:` and forwarding says so
 * rather than pretending there is a second path. */
- (nullable instancetype)initWithDataIgnoringOrientation:(NSData *)data
{
	return [self initWithData:data];
}

/* LOCKING ONTO ONE REPRESENTATION, which is Apple's deprecated door and the one whose replacement its
 * own release notes give as "lock focus on the image and draw the rep in it". The difference from
 * `-lockFocus` is WHICH pixels become the canvas, so the two share one implementation. */
- (void)cg_lockRep:(NSBitmapImageRep *)rep flipped:(BOOL)flipped
{
	NSGraphicsContext *g;
	CGColorSpaceRef cs;
	CGContextRef ctx;
	NSInteger w, h;

	if (_focusContext != nil || rep == nil) {
		return;
	}
	w = [rep pixelsWide];
	h = [rep pixelsHigh];
	if (w <= 0 || h <= 0 || [rep bitmapData] == NULL || [rep bytesPerRow] <= 0) {
		return;
	}
	_focusRep = [rep retain];
	cs = CGColorSpaceCreateDeviceRGB();
	/* THE REP'S OWN STRIDE, NOT w * 4: a rep built over a caller's plane may be padded, and a context
	 * built with the wrong stride writes each row into the middle of the one before it. */
	ctx = CGBitmapContextCreate([rep bitmapData], (size_t)w, (size_t)h, 8, (size_t)[rep bytesPerRow], cs,
				    (uint32_t)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
	CGColorSpaceRelease(cs);
	if (ctx == NULL) {
		[_focusRep release];
		_focusRep = nil;
		return;
	}
	if (flipped) {
		CGContextTranslateCTM(ctx, 0.0, (CGFloat)h);
		CGContextScaleCTM(ctx, 1.0, -1.0);
	}
	g = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:flipped];
	CGContextRelease(ctx);
	if (g == nil) {
		[_focusRep release];
		_focusRep = nil;
		return;
	}
	_focusPrevious = [NSGraphicsContext currentContext];
	if (_focusPrevious != g) {
		[_focusPrevious retain];
	} else {
		_focusPrevious = nil;
	}
	_focusContext = g;
	_focusFlipped = flipped;
	[NSGraphicsContext setCurrentContext:g];
}

- (void)lockFocusOnRepresentation:(nullable NSImageRep *)imageRepresentation
{
	if (![imageRepresentation isKindOfClass:[NSBitmapImageRep class]]) {
		fprintf(stderr, "APPKIT-REFUSE: -lockFocusOnRepresentation: needs a representation with "
				"readable pixels; this one is %s\n",
			imageRepresentation == nil ? "nil" : "of a kind whose pixels this class cannot "
							"address");
		return;
	}
	[self cg_lockRep:(NSBitmapImageRep *)imageRepresentation flipped:_focusFlipped];
}

/* ---- THE ALIGNMENT RECT, WHICH IS REAL GEOMETRY ------------------------------------------------ *
 * Apple's contract is exact and is implemented as written: the DEFAULT is `{{0,0}, imageSize}`, which is why
 * a rect that was never set is ANSWERED FROM THE SIZE rather than stored — so `-setSize:` moves it without
 * this class doing anything, which is what "the rect is adjusted when -setSize: is called" means for an
 * image nobody has given a rect to.
 *
 * AND THE ONE PART APPLE DOES NOT PUBLISH IS A STATED DEVIATION RATHER THAN A GUESS: it does not say HOW an
 * explicitly-set rect is adjusted when the size changes, so this tier leaves an explicit rect ALONE. */
- (NSRect)alignmentRect
{
	if (_alignmentRectSet) {
		return _alignmentRect;
	}
	return NSMakeRect(0.0, 0.0, _size.width, _size.height);
}

- (void)setAlignmentRect:(NSRect)rect
{
	_alignmentRect = rect;
	_alignmentRectSet = YES;
}

- (NSString *)accessibilityDescription
{
	return _accessibilityDescription;
}

- (void)setAccessibilityDescription:(NSString *)description
{
	/* COPIED, like `-setName:`: the string is metadata a caller may hand over from a mutable source, and
	 * an image that changed its own description afterwards would be describing something else. */
	if (description != _accessibilityDescription) {
		NSString *copy = [description copy];

		[_accessibilityDescription release];
		_accessibilityDescription = copy;
	}
}

/* ---- AND THE FIVE RECORDED FACTS --------------------------------------------------------------- *
 * Each is what its setter was told, with APPLE'S OWN DOCUMENTED DEFAULT where nothing has been set — cited
 * in the header, and for two of them the default is YES, which is why a flag travels with the value: a
 * sentinel could not tell "never set" from "set to NO". Nothing here ACTS on any of the five (there is no
 * cache model and no representation chooser in this tier), which is the same honest maximum the four older
 * cache switches beside them make. */
- (BOOL)matchesOnMultipleResolution
{
	return _matchesOnMultipleResolutionSet ? _matchesOnMultipleResolution : YES;
}

- (void)setMatchesOnMultipleResolution:(BOOL)flag
{
	_matchesOnMultipleResolution = flag ? YES : NO;
	_matchesOnMultipleResolutionSet = YES;
}

- (BOOL)prefersColorMatch
{
	return _prefersColorMatchSet ? _prefersColorMatch : YES;
}

- (void)setPrefersColorMatch:(BOOL)flag
{
	_prefersColorMatch = flag ? YES : NO;
	_prefersColorMatchSet = YES;
}

- (BOOL)usesEPSOnResolutionMismatch
{
	return _usesEPSOnResolutionMismatch;
}

- (void)setUsesEPSOnResolutionMismatch:(BOOL)flag
{
	_usesEPSOnResolutionMismatch = flag ? YES : NO;
}

- (BOOL)isTemplate
{
	return _template;
}

- (void)setTemplate:(BOOL)flag
{
	_template = flag ? YES : NO;
}

/* SPELLED `NSUInteger` IN BOTH DIRECTIONS, AND THAT IS REQUIRED RATHER THAN PREFERRED: the header's ivar and
 * property are spelled this way because `NSImageCacheMode`'s declaration sits BELOW the class body (where
 * Apple declares it), and an implementation whose types disagree with its declaration EARNED TWO WARNINGS
 * when this was first written — measured, `-Wmismatched-return-types` and `-Wmismatched-parameter-types`. An
 * enum converts to `NSUInteger` and back, so `NSImageCacheDefault` and its three siblings still work from a
 * caller's side. */
- (NSUInteger)cacheMode
{
	return _cacheMode;
}

- (void)setCacheMode:(NSUInteger)mode
{
	_cacheMode = mode;
}

/* ---- AND THE CARBON DOOR ----------------------------------------------------------------------- */

- (nullable instancetype)initWithIconRef:(void *)iconRef
{
	(void)iconRef;
	/* NO ICON SERVICES IN THIS TREE: an `IconRef` is a Carbon handle, and there is neither the type nor
	 * anything that could produce one — so there is no image to make and nil is the honest answer. */
	fprintf(stderr, "APPKIT-REFUSE: -initWithIconRef: needs the Carbon Icon Services manager, which this "
			"tree has not got\n");
	return nil;
}

@end
