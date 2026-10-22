/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSImageRep.h — ONE REPRESENTATION OF AN IMAGE, and the layer that owns the drawing seam (C8.9).
 *
 * THE HIERARCHY IS APPLE'S: a rep is a piece of image data with a known pixel layout, and `NSImage`
 * above it is a container of reps. This file is the ABSTRACT half — the metadata every rep has (how
 * many pixels, how big that is in points, which colour space) and the ONE drawing rule they share.
 *
 * AND THE DRAWING RULE IS WHY THIS IS A CLASS RATHER THAN A STRUCT: `-drawInRect:` needs the current
 * graphics context and an image to put in it, so the base asks itself for `-CGImage` — a member the
 * SUBCLASS answers — and draws that once. Every rep type therefore gets drawing for free and has only
 * one question to answer, which is the same shape as `NSGraphicsContext`'s read-through properties.
 *
 * WHAT IS NOT HERE, AND WHY, so the ledger's open rows are a decision rather than an omission:
 * `-representationUsingType:properties:` and `-TIFFRepresentation` need an ENCODER, and CoreGraphics
 * in this tree has only the two DECODERS (`CGImageCreateWithPNGDataProvider`,
 * `CGImageCreateWithJPEGDataProvider` — measured, and there is no `CGImageDestination` here); the
 * `NSImageRep` registry, `-canInitWithData:` and `+imageRepsWithData:` need the class registry that
 * does not exist; the NSCoding members need an archive format; `-colorSpace` needs `NSColorSpace`;
 * and the `NSBitmapImageFileType`/`NSImageRepLoadStatus`/`NSImageRepHintKey` enumerations ride with
 * the encoder and the registry they belong to. Each is absent rather than stubbed, and the reason is
 * written next to it.
 *
 * THE COLOUR-SPACE NAMES ARE STRINGS, as Apple's are, and they live here because a rep's designated
 * initialiser takes one. `NSColorSpaceName` is a typed extensible enum in Apple and a plain
 * `NSString *` here: the extra type is a spelling, and the constant is the substance.
 */

#import <CoreGraphics/CGImage.h>
/* **AND THE CONTEXT'S HEADER, FOR ONE ENUM.** `-drawInRect:fromRect:operation:fraction:respectFlipped:hints:` takes an
 * `NSCompositingOperation`, which `NSGraphicsContext.h` declares — and importing it here closes no cycle because that
 * header's AppKit references are all `@class` forward declarations. Typing the parameter `NSInteger` instead (the
 * over-crediting rule this tree uses where a type is not reachable) would make an OPERATION indistinguishable from any
 * other number at the one door where a wrong operation is a wrong picture. */
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

/* FORWARDED: both are only ever pointer parameters here, so the rep's header needs no import of either. */
@class NSDictionary;
@class NSPasteboard;
@class NSURL;
@class NSGraphicsContext;

/* THE TWO NAMES THIS LAYER CAN ANSWER FOR, which are the two colour spaces the pixels here can be
 * in — the same two CoreGraphics creates device spaces for. The calibrated and generic names are
 * absent because nothing distinguishes them at this layer. */
extern NSString *const NSDeviceRGBColorSpace;
extern NSString *const NSDeviceGrayColorSpace;


/* THE DEVICE-VARIABLE SENTINEL, WHOSE VALUE THE ERA HEADER PUBLISHES (`= 0`): "NSImageRepMatchesDevice
 * indicates the value is variable, depending on the output device. It can be passed in (or received back)
 * as the value of bitsPerSample, pixelsWide, and pixelsHigh." It is a CASE with no enum around it, which
 * is how the header declares it. */
enum {
	NSImageRepMatchesDevice = 0
};

/* THE REGISTRY'S OWN NOTIFICATION, and the obsolete spelling Apple keeps as a `#define` to it — a macro
 * whose value IS in the header, so both rows ship. */
extern NSString *NSImageRepRegistryDidChangeNotification;
#define NSImageRepRegistryChangedNotification NSImageRepRegistryDidChangeNotification

@interface NSImageRep : NSObject
{
	/* THE PIXELS ARE THE SUBCLASS'S; THESE ARE THE METADATA. `_size` is in POINTS and is deliberately
	 * independent of the pixel count — a rep can be 4 pixels wide and 100 points wide, which is
	 * resolution independence and the reason `setSize:` is not a synonym for the pixel dims. */
	NSSize _size;
	NSInteger _pixelsWide;
	NSInteger _pixelsHigh;
	NSString *_colorSpaceName;
	BOOL _opaque;
	BOOL _alpha;
	/* **AND THE SAMPLE SIZE, WHICH IS A RECORDED VALUE ON THE BASE AND A FACT ON A BITMAP.** Apple stores
	 * `-setBitsPerSample:` here and says a subclass may refuse to set it; this base therefore remembers what it was
	 * told, and a rep whose pixels have a depth of their own OVERRIDES both accessors so the two can never disagree.
	 * The name carries the distinction: `_repBitsPerSample` is what the base was TOLD, while `NSBitmapImageRep`'s own
	 * `_bitsPerSample` is the depth its bytes are in. */
	NSInteger _repBitsPerSample;
}

@property NSInteger pixelsWide;
@property NSInteger pixelsHigh;
/* THE SIZE IN POINTS. A newly initialised rep answers its PIXEL dimensions, which is what Apple's do
 * — so a 4x4 rep is 4x4 points until someone says otherwise. */
@property NSSize size;
@property (copy) NSString *colorSpaceName;


/* ============================================================================================ *
 * THE REGISTRY. Apple's header states the contract in one sentence, and it is the sentence this  *
 * implementation is built on: "Subclasses which deal with file & pasteboard types should register  *
 * themselves. These classes should also implement imageUnfilteredFileTypes,                        *
 * imageUnfilteredPasteboardTypes, initWithData:, canInitWithData:, imageRepWithData:, and, if they  *
 * have the ability to read multiple images from a file, imageRepsWithData:."                       *
 *                                                                                                 *
 * SO THE BASE CLASS QUERIES AND ITS SUBCLASSES ANSWER. Nothing here knows that a PNG exists: every  *
 * question is put to the registered classes and a class that cannot answer is skipped, so the        *
 * answers are right for the SECOND registrant as well as the first. This tree registers ONE          *
 * (NSBitmapImageRep, which registers itself in its own `+initialize`).                              *
 * ============================================================================================ */

+ (void)registerImageRepClass:(Class)imageRepClass;
+ (void)unregisterImageRepClass:(Class)imageRepClass;
+ (NSArray *)registeredImageRepClasses;

/* THE FOUR QUESTIONS ABOUT BYTES AND TYPES. Each answers the FIRST registered class that can, which is
 * registration order — a stated rule, since Apple leaves the tie to the class. */
+ (BOOL)canInitWithData:(nullable NSData *)data;
+ (nullable Class)imageRepClassForData:(nullable NSData *)data;
+ (nullable Class)imageRepClassForType:(nullable NSString *)type;
+ (nullable Class)imageRepClassForFileType:(NSString *)type;
+ (nullable Class)imageRepClassForPasteboardType:(NSString *)type;

/* THE UNION ACROSS THE REGISTERED CLASSES, which is what Apple's own documentation of NSImage's filtered
 * list says it is. NOTHING IS FILTERED HERE — no filter services exist in this tree, which is the same
 * fact `+typesFilterableTo:` in NSPasteboard refuses on — so the two lists are one list, stated rather
 * than hidden. */
+ (NSArray *)imageUnfilteredTypes;
+ (NSArray *)imageTypes;
+ (NSArray *)imageUnfilteredFileTypes;
+ (NSArray *)imageUnfilteredPasteboardTypes;
/* **AND THE FILTERED PAIR, WHICH IS THE UNFILTERED ONE HERE FOR THE REASON THE LINES ABOVE GIVE** — no filter services
 * exist in this tier — but is still a separate door, because a caller asking "what can I OPEN" and a caller asking
 * "what can I DECODE" are different questions even on the day the answers match. A registrant that gains a filter
 * overrides this pair alone. */
+ (NSArray *)imageFileTypes;
+ (NSArray *)imagePasteboardTypes;

/* **AND WHETHER A LIVE PASTEBOARD HOLDS ANYTHING THIS REGISTRY CAN READ.** The same question as the lists above, asked
 * of a board rather than of a table: the board's own `-types` are matched against `+imagePasteboardTypes`. NSImage has
 * had this door for its own list since the pasteboard slice; this is the registry's answer, and it is the one a rep
 * class can be asked for directly. */
+ (BOOL)canInitWithPasteboard:(nullable NSPasteboard *)pasteboard;

/* AND THE TWO DOORS A REGISTRANT ANSWERS WITH, named by the same sentence. The base's own answers
 * are nil, because an abstract rep has no format — every registered class overrides them, which is
 * what makes the registry's questions answerable at all. */
+ (nullable id)imageRepWithData:(NSData *)data;
+ (nullable NSArray *)imageRepsWithData:(NSData *)data;

/* AND THE SIX CONTENT DOORS: a file, a URL and a pasteboard, each in a singular and a plural form. The
 * plural answers an array of ONE for a class with no `+imageRepsWithData:`, which is the same honesty the
 * singular door has. */
+ (nullable id)imageRepWithContentsOfFile:(nullable NSString *)filename;
+ (nullable NSArray *)imageRepsWithContentsOfFile:(nullable NSString *)filename;
+ (nullable id)imageRepWithContentsOfURL:(nullable NSURL *)url;
+ (nullable NSArray *)imageRepsWithContentsOfURL:(nullable NSURL *)url;
+ (nullable id)imageRepWithPasteboard:(nullable NSPasteboard *)pasteboard;
+ (nullable NSArray *)imageRepsWithPasteboard:(nullable NSPasteboard *)pasteboard;

/* THE DRAWING SEAM. `-drawInRect:` is implemented once here and every rep inherits it: it asks the
 * current context and `-CGImage`, which is the SUBCLASS's answer. `-draw` and `-drawAtPoint:` are the
 * two Apple calls that sit either side of it. All three answer NO when there is nothing to draw or no
 * context to draw into, rather than raising — the same choice `NSGraphicsContext` makes.
 *
 * **AND THE ONE DOOR THAT SAYS EVERYTHING ABOUT A DRAW: WHERE, WHAT PART, HOW, HOW MUCH, WHICH WAY UP, WITH WHAT
 * HINTS.** The four simpler doors are this one with its arguments filled in, so there is one drawing path rather than
 * six; `-drawInRect:`, `-drawAtPoint:` and `-draw` are unchanged in WHAT THEY PAINT by being expressed through it.
 *
 * `fromRect:` IS IN THE REP'S OWN POINTS, like every rect a rep speaks in, and the crop is converted to pixels at the
 * one place the two differ. `operation:` and `fraction:` go through the CONTEXT (`-setCompositingOperation:` and a
 * CGContext alpha), which is where this tier keeps the enum-to-blend mapping and its own refusal for the operations
 * CoreGraphics cannot do. `respectFlipped:` is the one argument that changes ORIENTATION: YES is the rule these doors
 * have always followed — an image is drawn UP-RIGHT in a flipped view and in an unflipped one — and NO is the raw
 * `CGContextDrawImage`, which is upright in a y-up context and upside down in a y-down one. `hints:` reads
 * `NSImageHintInterpolation` and sets the context's interpolation quality for the draw, then puts it back. */
- (BOOL)draw;
- (BOOL)drawAtPoint:(NSPoint)point;
- (BOOL)drawInRect:(NSRect)rect;
- (BOOL)drawInRect:(NSRect)dstRect
	  fromRect:(NSRect)srcRect
	 operation:(NSCompositingOperation)op
	  fraction:(CGFloat)delta
    respectFlipped:(BOOL)respectFlipped
	     hints:(nullable NSDictionary *)hints;

/* **AND THE TWO SAMPLE QUESTIONS** — the bits each sample is, and whether there is an alpha channel. Both are the
 * base's storage (see the ivars) and a rep with pixels of its own overrides them, which is the same contract
 * `-setOpaque:` and `-setAlpha:` above carry. `-hasAlpha` is `-alpha` under Apple's name for the same fact, so the two
 * doors answer one flag rather than two. */
@property NSInteger bitsPerSample;
- (void)setBitsPerSample:(NSInteger)bitsPerSample;
- (BOOL)hasAlpha;

/* THE QUESTION A SUBCLASS ANSWERS, and the only one. The base answers NULL because an abstract rep has
 * no pixels; every concrete rep here overrides it, so `-drawInRect:` works for all of them at once. */
@property (nullable, readonly) CGImageRef CGImage;

/* THE SNAPSHOT, AND THE RECT IS IN AND OUT. `NSImage` has this door too and this is where its answer
 * comes from: the class above chooses WHICH rep and this one produces the image. The proposal is read
 * as the rect the caller wants to draw into and the pixel-INTEGRAL rect the returned image actually
 * covers is written back — the two differ because a CGImage has whole pixels and a rep need not. */
- (nullable CGImageRef)CGImageForProposedRect:(nullable NSRect *)proposedDestRect
				      context:(nullable NSGraphicsContext *)referenceContext
					hints:(nullable NSDictionary *)hints;


/* **WHETHER THIS REP'S SAMPLES ARE OPAQUE, IN APPLE'S OWN SPELLING** — the accessor is `-isOpaque`, which is what
 * the ledger's `opaque` row is answered by. The base STORES the flag (Apple declares `-setOpaque:` here); a subclass
 * whose samples can answer the question itself overrides the getter. */
- (void)setOpaque:(BOOL)flag;
- (BOOL)isOpaque;

/* **AND `alpha` IS THE SAME KIND OF DOOR, WHICH ITS OWN HEADER SAYS IN PROSE.** Apple groups `-setSize:`, `-size`,
 * `-setAlpha:` and this getter under one comment: "Methods to return info about the image. NSImageRep provides
 * storage for all of these; however, it's illegal to set them in some subclasses." So the base STORES the flag and
 * a subclass that owns the data records what it knows — which is also why that sentence is DOCUMENTED here rather
 * than enforced: it is a constraint on who may call the setter, not a promise this tier can attest.
 *
 * THE DEFAULT IS NO, AND THAT IS STATED RATHER THAN PRESENTED AS APPLE'S: Apple publishes no default for a
 * storage-only base, and a rep that was never told anything has not been told it has an alpha channel. */
- (void)setAlpha:(BOOL)flag;
- (BOOL)alpha;

@end

NS_ASSUME_NONNULL_END
