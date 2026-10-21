/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSImage.h — a CONTAINER OF REPRESENTATIONS, and the class callers actually pass around (C8.10).
 *
 * THE SHAPE IS APPLE'S AND THE SPLIT IS WHY THERE ARE TWO CLASSES: an `NSImage` is not pixels, it is a
 * NAMED THING with a SIZE that answers drawing requests by choosing one of its representations
 * (`NSImageRep`) to hand the work to. That is what makes an image resolution-independent and what makes
 * `-setSize:` mean something different from a rep's pixels: the SIZE is the image's, and the pixels
 * belong to whichever rep draws it.
 *
 * SO `-size` HAS TWO SOURCES AND THE PRECEDENCE IS THE POINT: an EXPLICIT size (from `-initWithSize:`
 * or `-setSize:`) wins; otherwise the image answers the FIRST representation's size, which is what a
 * caller who loaded a PNG expects. `-isValid` asks a different question — whether there is anything to
 * draw at all — and it is NO for an image with a size and no representations, which is exactly the
 * empty canvas `+image` produces.
 *
 * WHAT IS NOT HERE, AND WHY:
 *   THE ENCODING HALF IS ABSENT FOR C8.9's ALREADY-MEASURED REASON: `-TIFFRepresentation` and
 *   `-TIFFRepresentationUsingCompression:factor:` need an ENCODER, and this tree's CoreGraphics has only the two decoders (there is no `CGImageDestination`
 *   in `userland/CoreGraphics/`). The two TIFF doors are declared as the REFUSALS they are — they
 *   answer nil and say why on stderr — rather than left absent, because a ported caller that gets nil
 *   and a reason is better served than one that cannot compile, and because leaving them undeclared
 *   also left the ledger's `TIFFRepresentation` row mis-tagged (see the era-key note in
 *   tools/appkit-sweep.py: a `property` row carries no `+`/`-` sign, so it can never match a signed
 *   era key and was read as post-10.6 although the era work lists carry it as a METHOD).
 *   `-representationUsingType:properties:` is NOT in that list because it is not THIS class's member:
 *   it ships on NSBitmapImageRep, which is where Apple files it, and it refuses there for the same
 *   measured reason.
 *   `-initWithIconRef:` is NOT declared and its row stays open: an `IconRef` is a Carbon type this
 *   tree does not have, and inventing one to satisfy a signature would be claiming surface we do not
 *   ship. `-initWithCoder:` stays OPEN TOO, for the reason `NSImageRep.h` records for its own coding
 *   members and `NSEvent.h` for its: NSKeyedArchiver exists in this tree, but the KEY SET an archived
 *   NSImage uses is Apple's private arrangement (which members are saved by CONTENTS and which by
 *   REFERENCE is documented behaviour with no published keys), so writing one would be inventing an
 *   archive format rather than implementing one. `NSCompositeHighlight` is the one legacy spelling
 *   that cannot be an alias — NSGraphicsContext.h carries the measured value collision that decides
 *   it — and it stays open for the same reason. The `NSImageSymbolConfiguration` and `NSImageSymbol*`
 *   system-image family needs the SF Symbols catalogue and an appearance system. Each of those is
 *   absent rather than stubbed, and every one of them is an OPEN ROW rather than a silent gap.
 */

#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImageRep.h>
#import <CoreGraphics/CGImage.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

/* FORWARDED, because the delegate protocol below names the class before the class exists. */
@class NSImage;
@class NSPasteboard;

/* THE LOAD STATUS, WHICH THE DELEGATE'S LAST CALLBACK REPORTS. The case ORDER is the artefact's (a
 * 10.2 header carries no numbers), which is the standing rule for an enum nobody publishes values for. */
enum {
	NSImageLoadStatusCompleted,
	NSImageLoadStatusCancelled,
	NSImageLoadStatusInvalidData,
	NSImageLoadStatusUnexpectedEOF,
	NSImageLoadStatusReadError
};
typedef NSUInteger NSImageLoadStatus;

/* THE DELEGATE, IN THE 10.6 SHAPE — a real `@protocol` — which is the era decision §9f E-11 records.
 * At the 10.2 and 10.5 pins this surface is an `@interface NSObject (NSImageDelegate)` category
 * instead; the ledgers carry the name either way, and a 10.6 application's `id <NSImageDelegate>`
 * compiles against this. Every member is `@optional`, as Apple's are: a delegate answers the calls it
 * cares about. */
@protocol NSImageDelegate <NSObject>
@optional
- (nullable NSImage *)imageDidNotDraw:(id)sender inRect:(NSRect)aRect;
- (void)image:(NSImage *)image willLoadRepresentation:(NSImageRep *)rep;
- (void)image:(NSImage *)image didLoadRepresentationHeader:(NSImageRep *)rep;
- (void)image:(NSImage *)image didLoadPartOfRepresentation:(NSImageRep *)rep withValidRows:(NSInteger)rows;
- (void)image:(NSImage *)image didLoadRepresentation:(NSImageRep *)rep withStatus:(NSImageLoadStatus)status;
@end

/* THE TWO HINTS `-CGImageForProposedRect:context:hints:` reads. Their values are their identifiers, the
 * same choice the named images make and for the same reason: Apple publishes the constant, not the
 * string. `NSImageHintCTM`'s value is an `NSAffineTransform` and `NSImageHintInterpolation`'s is an
 * `NSNumber` carrying an `NSImageInterpolation`. */
extern NSString *NSImageHintCTM;
extern NSString *NSImageHintInterpolation;

@interface NSImage : NSObject
{
	/* THE REPS, AS AN IMMUTABLE SNAPSHOT: `-representations` hands a caller an array it cannot use to
	 * reach in and change this image behind its back, which is the same rule Apple's accessor keeps. */
	NSArray *_reps;
	NSSize _size;
	BOOL _sizeIsExplicit;
	/* THE SWIZZLED OFFSCREEN CANVAS, WHEN AN IMAGE WAS MADE BY DRAWING INTO ONE. It exists because a
	 * representation BORROWS its bytes rather than owning them, so whoever makes the buffer must keep
	 * it alive for as long as the rep — which is this object. See `+imageWithSize:flipped:drawingHandler:`. */
	unsigned char *_focusBuffer;
	/* THE LOCK'S OWN STATE, three fields because `-lockFocus` has to be REVERSIBLE: the representation it
	 * draws into (retained — it owns the pixels), the graphics context it installed, and the one that was
	 * current before it, retained so `-unlockFocus` can put it back. */
	NSBitmapImageRep *_focusRep;
	NSGraphicsContext *_focusContext;
	NSGraphicsContext *_focusPrevious;
	BOOL _focusFlipped;
	/* THE NAME. Apple's is a plain string kept for `+imageNamed:` lookups and archiving; here it is
	 * only what `-setName:`/`-name` round-trip, and it is COPIED so a caller cannot change it under us. */
	NSString *_name;
	/* THE FOUR CACHE SWITCHES. They are RECORDED rather than acted on, and that is the honest maximum:
	 * they exist to configure a cache this class does not have (there is no cache model here at all —
	 * `-recache` says so too), so what a getter can truthfully answer is what its setter was told.
	 * Apple's own documentation for all four says a caller can remove their use with no replacement. */
	BOOL _scalesWhenResized;
	BOOL _dataRetained;
	BOOL _cachedSeparately;
	BOOL _cacheDepthMatchesImageDepth;
	/* ============================================================================================ *
	 * AND THE SWITCHES AND FIELDS THE REMAINING ROWS NEED. FIVE OF THEM ARE THE SAME FAMILY THE      *
	 * FOUR ABOVE BELONG TO — recorded, because a getter can truthfully answer what its setter was    *
	 * told and nothing here ACTS on them — BUT TWO OF THESE CARRY A DEFAULT THAT IS NOT ZERO, which  *
	 * is why they have a flag of their own: `matchesOnMultipleResolution` and `prefersColorMatch`    *
	 * are YES by default, and a sentinel could not tell "never set" from "set to NO".                *
	 * ============================================================================================ */
	BOOL _matchesOnMultipleResolution;
	BOOL _matchesOnMultipleResolutionSet;
	BOOL _prefersColorMatch;
	BOOL _prefersColorMatchSet;
	BOOL _usesEPSOnResolutionMismatch;	/* default NO, so the zero value IS the default */
	BOOL _template;				/* ditto: an image is a template only when marked */
	/* AND `_cacheMode` IS SPELLED `NSUInteger` RATHER THAN `NSImageCacheMode`, WHICH IS **NOT** THE SAME TYPE
	 * — and that correction is the whole reason this comment is long. The first version of it said the enum
	 * WAS this type, and the compiler said otherwise: an `NSImageCacheMode` is an ENUM, declared below the
	 * class body (where Apple declares it), so it is not visible before the @interface opens — and an ivar's
	 * type has to be. The property and BOTH accessors are therefore spelled the same way, which is what makes
	 * the declared and implemented types AGREE; spelling the accessors in Apple's name instead EARNED TWO
	 * WARNINGS, measured. The VALUES are unaffected: an enum converts to and from `NSUInteger`, and
	 * `NSImageCacheDefault` is its zero. */
	NSUInteger _cacheMode;			/* `NSImageCacheDefault` is the enum's own zero */
	/* AND THE TWO THAT ARE NOT SWITCHES. The alignment rect is REAL STATE with a computed default
	 * (`{{0,0}, imageSize}`, Apple's own words), and the description is a COPIED string like `_name`. */
	NSRect _alignmentRect;
	BOOL _alignmentRectSet;
	NSString *_accessibilityDescription;	/* RETAINED (a copy of what was set) */
	/* **A TEMPLATE'S STENCILS, AND THE REASON `-template` IS NOT JUST A FLAG HERE.** Apple's template image is
	 * ONE INK drawn from a mask: the artwork carries coverage and nothing else, and the colour comes from
	 * whatever draws it — a button's ink, a disabled control's grey, a menu's highlight. That needs a mask to
	 * clip to, so an image that is a template because the PLATFORM made it (see `AGSystemImages`) carries its
	 * own, one per size the tier draws at. OWNED: released in `-dealloc`. */
	/* THREE STENCILS, KEYED BY THE SIZE THEY WERE DRAWN AT (16, 24 and 32 points), because the tier draws a
	 * toolbar's regular item at 24 and its small one at 16 and a scaled stencil is measurably blockier than a
	 * native one. A slot with no stencil is a NULL and a zero. */
	CGImageRef _templateMasks[3];
	NSInteger _templateMaskSizes[3];
}

/* ============================================================================================ *
 * THE REMAINING ROWS: ONE REFUSAL, ONE REAL RECT, ONE STORED STRING, AND FIVE RECORDED FACTS.    *
 * ============================================================================================ */

/* THE ALIGNMENT RECT, WHICH IS THE ONE PIECE OF REAL GEOMETRY HERE. Apple's contract is exact and is
 * implemented as written: the DEFAULT is `{{0,0}, imageSize}` — so an image that has never been given one
 * answers its own size, and `-setSize:` therefore moves it without this class doing anything — and a rect
 * that HAS been set is answered as it was given.
 *
 * ONE PART OF THE CONTRACT IS NOT PUBLISHED AND IS THEREFORE A STATED DEVIATION rather than a guess: Apple
 * says "the rect is adjusted when `-setSize:` is called", and does not say HOW an explicitly-set rect is
 * adjusted. This tier leaves an explicit rect alone. */
@property NSRect alignmentRect;

/* THE ACCESSIBILITY DESCRIPTION: a short localized string, stored. It is metadata for interface elements
 * that display the image, so `-setAccessibilityDescription:` COPIES, the way `-setName:` does. */
@property (nullable, copy) NSString *accessibilityDescription;

/* THE FIVE RECORDED FACTS, each with APPLE'S OWN DOCUMENTED DEFAULT where the artefact is silent — cited
 * because a wrong default here is a silent difference in how an image is chosen for a device:
 *
 *   `-matchesOnMultipleResolution` is **YES** ("the default value is true": a representation whose
 *   resolution is an integral multiple of the device's is a match, and the closest one is chosen).
 *   `-usesEPSOnResolutionMismatch` is **NO** ("the default is false").
 *   `-template` is **NO**, which is what "an image SHOULD BE MARKED as a template if…" means: opt-in.
 *   `-cacheMode` is `NSImageCacheDefault`, the enum's own "unspecified, use the rep's default" zero.
 *   AND `-prefersColorMatch` IS **YES**, WHICH IS THE ONE DEFAULT APPLE'S PAGES DO NOT PRINT: they say the
 *   method "indicates which technique is used first", and the ORDERED SELECTION RULES they do publish put
 *   "choose a colour representation for a colour device" FIRST — so colour matching is preferred unless a
 *   caller says otherwise. That is an INFERENCE FROM A PUBLISHED RULE rather than a quoted default, and it
 *   is said here rather than left for a reader to wonder about. */
@property BOOL matchesOnMultipleResolution;
@property BOOL prefersColorMatch;
@property BOOL usesEPSOnResolutionMismatch;
@property (getter=isTemplate) BOOL template;
/* AND THE CACHE MODE IS SPELLED `NSUInteger` FOR THE REASON ITS IVAR IS (see the brace block) — AND THIS
 * COMMENT EXISTS BECAUSE THE FIRST VERSION OF IT WAS WRONG. It said `NSImageCacheMode` IS an `NSUInteger`
 * typedef. The measured truth is that it is an ENUM TYPE (`typedef enum { NSImageCacheDefault, …
 * NSImageCacheNever } NSImageCacheMode`, declared below the class body where Apple declares it), so it is not
 * visible here and is NOT the same type — which is exactly what two compiler warnings said when the
 * declarations and the accessors disagreed. The spellings now agree with each other (the ivar, this property
 * and both accessors are `NSUInteger`), and THE VALUES ARE UNAFFECTED: an enum converts to and from
 * `NSUInteger`, so a caller passing `NSImageCacheDefault` — or any of the three siblings this header declares
 * a little further down — compiles and means what it says. */
@property NSUInteger cacheMode;

/* AND THE ONE THAT REFUSES BY NAME: `-initWithIconRef:` takes an `IconRef`, a CARBON type from the
 * Icon Services half of the old Toolbox. There is no IconRef in this tree and nothing to make one from, so
 * the door answers nil and says which subsystem is missing.
 *
 * THE PARAMETER IS SPELLED `void *` RATHER THAN `IconRef` because `IconRef` is a typedef in a header this
 * tier does not have — and spelling it would need a forward declaration the ledger would then count. An
 * `IconRef` IS an opaque pointer, so a caller porting a Carbon-era program passes one and means what it
 * says. */
- (nullable instancetype)initWithIconRef:(void *)iconRef;

/* AN EMPTY CANVAS — no representations, no size, `-isValid` NO. */
+ (instancetype)image;

- (instancetype)initWithSize:(NSSize)size;

/* AN IMAGE MADE BY DRAWING INTO AN OFFSCREEN CANVAS — the modern, non-deprecated way to say what
 * `-lockFocus`/`-unlockFocus` used to say, and a deliberate choice rather than a preference: APPLE
 * DEPRECATED THOSE TWO at the vintage this tree pins (macOS 14), and the standing policy is no
 * deprecated APIs. They are therefore NOT declared here, while this is.
 *
 * The handler is called with the canvas's full rect and asked to draw; WHAT IT RETURNS IS IGNORED, as
 * Apple's is — the drawing is the effect, and a handler that returns NO after painting has still
 * painted. `flipped:` decides whether the handler's coordinate system has its origin at the TOP-LEFT
 * (YES) or the bottom-left (NO), which is honoured by flipping the canvas's CTM.
 *
 * Two things are refused by name rather than half-done: a NULL handler, and a size with no pixels. */
+ (nullable instancetype)imageWithSize:(NSSize)size
			       flipped:(BOOL)drawingHandlerShouldBeCalledWithFlippedContext
			drawingHandler:(nullable BOOL (^)(NSRect dstRect))drawingHandler;
- (nullable instancetype)initWithData:(NSData *)data;
- (nullable instancetype)initWithContentsOfFile:(NSString *)path;
- (nullable instancetype)initWithCGImage:(CGImageRef)cgImage size:(NSSize)size;

/* THE REPRESENTATIONS. `-addRepresentation:` RETAINS what it is given, and the FIRST one added is the
 * one `-size` answers from when no explicit size was set. */
- (void)addRepresentation:(NSImageRep *)imageRep;
- (void)removeRepresentation:(NSImageRep *)imageRep;
/* A PLAIN `NSArray`, NOT `NSArray<NSImageRep *> *`: this tree's Foundation has no lightweight generics,
 * so the element type is a comment rather than a type argument. */
@property (readonly, copy) NSArray *representations;

/* THE SIZE IN POINTS, with the precedence described above. */
@property NSSize size;

/* WHETHER THERE IS ANYTHING TO DRAW. An image with a size and NO representations is a valid canvas and
 * an INVALID image, which is the distinction that makes this worth asking. */
@property (readonly, getter=isValid) BOOL valid;

/* WHICH REPRESENTATION WOULD DRAW A RECT. The rule here is the CLOSEST in points, with the first
 * winning ties — stated because Apple leaves it to the class to decide and this is the decision. */
- (nullable NSImageRep *)bestRepresentationForRect:(NSRect)rect
					   context:(nullable NSGraphicsContext *)referenceContext
					     hints:(nullable NSDictionary *)hints;

/* AND DRAWING, WHICH IS THE WHOLE POINT: the chosen representation draws, SCALED to the rectangle.
 * Both answer NO when there is nothing to draw rather than raising. */
/* THE FOCUS PAIR, WHICH IS HOW AN IMAGE IS DRAWN INTO RATHER THAN FROM: lock, draw, unlock. `-lockFocus`
 * creates a bitmap representation if the image has none, because an image made by `-initWithSize:`
 * deliberately has none. With `-lockFocusFlipped:YES` the canvas's y grows DOWNWARD, which is what a view's
 * drawing expects; with NO it grows up, Core Graphics' own convention. */
- (void)lockFocus;
- (void)lockFocusFlipped:(BOOL)flipped;
- (void)unlockFocus;
@property (readonly) BOOL isFlipped;

/* LOCKING ONTO ONE PARTICULAR REPRESENTATION, which is the deprecated door Apple's release notes tell a
 * caller to replace with "lock focus and draw the rep in the image". That is exactly what this does:
 * the NAMED rep's own pixels become the canvas, so `-unlockFocus` writes into the rep the caller chose
 * rather than into the first one. A nil rep, or one with no readable pixels, is a NO — the lock leaves
 * no current context and the answer is visible through `-isFlipped`/`[NSGraphicsContext currentContext]`. */
- (void)lockFocusOnRepresentation:(nullable NSImageRep *)imageRepresentation;

/* THE NAME, AND `-setName:` ANSWERS WHETHER IT TOOK — the era signature (10.2 through 10.6 both declare
 * `- (BOOL)setName:`, which modern AppKit respells as a `name` property). A nil argument CLEARS the name
 * and answers YES, which is the honest reading of "set the name to nothing". */
- (BOOL)setName:(nullable NSString *)string;
- (nullable NSString *)name;

/* AND THE COMPOSITING DOORS, WHICH ARE THE ERA'S WAY OF SAYING `-drawAtPoint:`. Each draws the chosen
 * representation at a point in the CURRENT context with the given operator, and the `fraction:` forms
 * scale the source alpha by it (1.0 is opaque, 0.0 draws nothing). `dissolveToPoint:` is the fraction
 * form with `SourceOver` fixed, which is what "dissolve" means. All four are NO-OPS with no current
 * context rather than raises, the same choice the drawing doors make. */
- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op;
- (void)compositeToPoint:(NSPoint)point fromRect:(NSRect)rect operation:(NSCompositingOperation)op;
- (void)compositeToPoint:(NSPoint)point operation:(NSCompositingOperation)op fraction:(CGFloat)delta;
- (void)compositeToPoint:(NSPoint)point
		fromRect:(NSRect)rect
	       operation:(NSCompositingOperation)op
		fraction:(CGFloat)delta;
- (void)dissolveToPoint:(NSPoint)point fraction:(CGFloat)aFloat;
- (void)dissolveToPoint:(NSPoint)point fromRect:(NSRect)rect fraction:(CGFloat)aFloat;

/* THE QUESTION `-hitTestRect:…` ANSWERS, and the one part of it that is a DECISION rather than a
 * transcription: "would the test rect intersect a NON-TRANSPARENT portion of the image?" The image is
 * mapped into `imageRectDestSpace` first, and the test rect is in the same destination space; a rect
 * that misses the image entirely answers NO. Alpha is READ, and `flipped:` decides which way up the
 * image's rows are laid into that rect — the same flag `-drawInRect:fromRect:operation:fraction:
 * respectFlipped:` carries. */
- (BOOL)hitTestRect:(NSRect)testRectDestSpace
withImageDestinationRect:(NSRect)imageRectDestSpace
	    context:(nullable NSGraphicsContext *)context
	      hints:(nullable NSDictionary *)hints
	    flipped:(BOOL)flipped;

/* A SNAPSHOT OF HOW THIS IMAGE WOULD DRAW, as a `CGImage`. `proposedDestRect` is IN AND OUT: it is read
 * as the rect the caller wants to draw into and written back as the pixel-integral rect the returned
 * image actually covers — the two differ because a CGImage has whole pixels and an NSImage need not.
 * Passing NULL means "the smallest pixel-integral rect containing `{{0,0}, [self size]}`". The `context`
 * and `hints` are HINTS to the choice of representation and are not required; nil answers the first
 * representation's image, which is what a caller who has no context wants. */
- (nullable CGImageRef)CGImageForProposedRect:(nullable NSRect *)proposedDestRect
				      context:(nullable NSGraphicsContext *)referenceContext
					hints:(nullable NSDictionary *)hints;

/* AND THE ENCODING DOORS, WHICH REFUSE BY NAME. This tree's CoreGraphics decodes PNG and JPEG and has
 * no `CGImageDestination`, so there is nothing to encode WITH — the answer is nil and a reason on
 * stderr rather than an approximation. The `NSTIFFCompression` argument is therefore taken and ignored
 * beyond the refusal, which is stated rather than implied. */
- (nullable NSData *)TIFFRepresentation;
- (nullable NSData *)TIFFRepresentationUsingCompression:(NSTIFFCompression)comp factor:(float)aFloat;

/* THE CACHE SWITCHES AND `-recache`. There is no cache model in this class, so each setter RECORDS and
 * each getter answers what was recorded, and `-recache` has nothing to throw away. Apple's own
 * documentation for all five says a caller can drop their use with no replacement. */
- (void)setScalesWhenResized:(BOOL)flag;
- (BOOL)scalesWhenResized;
- (void)setDataRetained:(BOOL)flag;
- (BOOL)isDataRetained;
- (void)setCachedSeparately:(BOOL)flag;
- (BOOL)isCachedSeparately;
- (void)setCacheDepthMatchesImageDepth:(BOOL)flag;
- (BOOL)cacheDepthMatchesImageDepth;
- (void)recache;

/* THE PASTEBOARD AND ORIENTATION DOORS. `-initWithPasteboard:` takes the first type the board carries
 * that this class can read; `-initWithDataIgnoringOrientation:` is `-initWithData:` with the EXIF
 * orientation explicitly disregarded, which is what this decoder does anyway — so it forwards and says
 * so rather than pretending to have a second path. */
- (nullable instancetype)initWithPasteboard:(nullable NSPasteboard *)pasteboard;
- (nullable instancetype)initWithDataIgnoringOrientation:(NSData *)data;


/* THE COMPOSITING OPERATIONS ARE NOT DECLARED HERE: they are already in NSGraphicsContext.h, which
 * owns the drawing state they belong to. This header's rows for them are satisfied by that declaration. */

/* AND THE NAMED IMAGES. The value of each is its own identifier, which is a CHOICE rather than a
 * transcription: Apple publishes the constant and not the string, so the string is ours — chosen once,
 * here, and asserted for every one of them in the probe. A caller that compares against them gets what it
 * asked for; a caller that wants the system's artwork gets whatever `+imageNamed:` finds, which is a
 * BUNDLE lookup rather than an icon theme this tree does not have. */
extern NSString *NSImageNameActionTemplate;
extern NSString *NSImageNameAddTemplate;
extern NSString *NSImageNameAdvanced;
extern NSString *NSImageNameApplicationIcon;
extern NSString *NSImageNameBluetoothTemplate;
extern NSString *NSImageNameBonjour;
extern NSString *NSImageNameBookmarksTemplate;
extern NSString *NSImageNameCaution;
extern NSString *NSImageNameColorPanel;
extern NSString *NSImageNameColumnViewTemplate;
extern NSString *NSImageNameComputer;
extern NSString *NSImageNameDotMac;
extern NSString *NSImageNameEnterFullScreenTemplate;
extern NSString *NSImageNameEveryone;
extern NSString *NSImageNameExitFullScreenTemplate;
extern NSString *NSImageNameFlowViewTemplate;
extern NSString *NSImageNameFolder;
extern NSString *NSImageNameFolderBurnable;
extern NSString *NSImageNameFolderSmart;
extern NSString *NSImageNameFontPanel;
extern NSString *NSImageNameGoRightTemplate;
extern NSString *NSImageNameHomeTemplate;
extern NSString *NSImageNameIChatTheaterTemplate;
extern NSString *NSImageNameIconViewTemplate;
extern NSString *NSImageNameInfo;
extern NSString *NSImageNameInvalidDataFreestandingTemplate;
extern NSString *NSImageNameLeftFacingTriangleTemplate;
extern NSString *NSImageNameListViewTemplate;
extern NSString *NSImageNameLockLockedTemplate;
extern NSString *NSImageNameLockUnlockedTemplate;
extern NSString *NSImageNameMenuOnStateTemplate;
extern NSString *NSImageNameMenuMixedStateTemplate;
extern NSString *NSImageNameMobileMe;
extern NSString *NSImageNameMultipleDocuments;
extern NSString *NSImageNameNetwork;
extern NSString *NSImageNamePathTemplate;
extern NSString *NSImageNamePreferencesGeneral;
extern NSString *NSImageNameQuickLookTemplate;
extern NSString *NSImageNameRefreshFreestandingTemplate;
extern NSString *NSImageNameRefreshTemplate;
extern NSString *NSImageNameRemoveTemplate;
extern NSString *NSImageNameRevealFreestandingTemplate;
extern NSString *NSImageNameRightFacingTriangleTemplate;
extern NSString *NSImageNameSlideshowTemplate;
extern NSString *NSImageNameSmartBadgeTemplate;
extern NSString *NSImageNameStatusAvailable;
extern NSString *NSImageNameStatusNone;
extern NSString *NSImageNameStatusPartiallyAvailable;
extern NSString *NSImageNameStatusUnavailable;
extern NSString *NSImageNameStopProgressFreestandingTemplate;
extern NSString *NSImageNameStopProgressTemplate;
extern NSString *NSImageNameTrashEmpty;
extern NSString *NSImageNameTrashFull;
extern NSString *NSImageNameUser;
extern NSString *NSImageNameUserAccounts;
extern NSString *NSImageNameUserGroup;
extern NSString *NSImageNameUserGuest;

/* AND THE LOOKUP ITSELF. Apple's `+imageNamed:` answers an image from the main bundle's resources, cached
 * per name; this one asks the bundle for the resource and loads it, WITHOUT a cache — an image is not
 * re-read once loaded by the caller, and a cache here would be a second lifetime to get wrong. A name that
 * is not in the bundle answers nil, which is the honest answer and the one the probe checks. */
+ (nullable NSImage *)imageNamed:(nullable NSString *)name;

/* THE TWO NAMES THE FIRST PASS MISSED, and their value is their identifier like the rest. */
extern NSString *NSImageNameFollowLinkFreestandingTemplate;
extern NSString *NSImageNameGoLeftTemplate;

/* HOW THE CLASS MAY CACHE AN OFFSCREEN REPRESENTATION. The FOUR VALUES ARE OURS AND THE ORDER IS THE
 * ARTEFACT'S — Apple publishes the case names in this order and no numbers — which is the standing rule for
 * an enum nobody publishes values for. */
typedef enum {
	NSImageCacheDefault = 0,
	NSImageCacheAlways,
	NSImageCacheBySize,
	NSImageCacheNever
} NSImageCacheMode;

/* THE TYPE LISTS, WHICH ARE WHAT A CALLER ASKS BEFORE HANDING OVER BYTES. THE FILTERED PAIR IS THE HONEST
 * ONE HERE and it is SHORT: this tree's CoreGraphics decodes PNG and JPEG (its own +imageRepWithData: says
 * so when handed anything else), so the filtered lists are those formats and the UNFILTERED ones are the
 * same set rather than Apple's much longer table — a class that advertised a format it cannot read would be
 * lying to the caller that consults the list before calling it. */
+ (NSArray *)imageFileTypes;
+ (NSArray *)imageUnfilteredFileTypes;
+ (NSArray *)imagePasteboardTypes;
+ (NSArray *)imageUnfilteredPasteboardTypes;
+ (BOOL)canInitWithPasteboard:(nullable NSPasteboard *)pasteboard;

/* AND THE DOORS THAT DO REAL WORK. `-initWithContentsOfURL:` is a FILE url or nothing — this tree has no
 * network image loading — and `-initByReferencingFile:` READS EAGERLY rather than referencing, because a
 * reference that loads later is a lifetime nobody here holds. `-drawRepresentation:inRect:` draws the rep
 * into the current context, and `-addRepresentations:` is the plural of a method this class already has. */
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url;
- (nullable instancetype)initByReferencingFile:(NSString *)fileName;
- (nullable instancetype)initByReferencingURL:(NSURL *)url;
- (void)addRepresentations:(nullable NSArray *)imageReps;
- (BOOL)drawRepresentation:(nullable NSImageRep *)imageRep inRect:(NSRect)rect;
- (nullable NSImageRep *)bestRepresentationForDevice:(nullable NSDictionary *)deviceDescription;

/* AND `-setFlipped:` IS NOT A NO-OP: it is the orientation the NEXT lock uses, which is what the focus pair
 * reads. `-cancelIncrementalLoad` has nothing to cancel — nothing here loads in stages. */
- (void)setFlipped:(BOOL)flag;
- (void)cancelIncrementalLoad;

- (BOOL)drawAtPoint:(NSPoint)point;
- (BOOL)drawInRect:(NSRect)rect;

@end

NS_ASSUME_NONNULL_END
