/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSBitmapImageRep.h — pixels you can hold, and the door between AppKit and Core Graphics (C8.9).
 *
 * THIS IS THE REPRESENTATION THAT OWNS PIXELS, so it is also the one that has to say WHAT the pixels
 * are: a bit depth, a channel count, whether there is an alpha channel, a colour space, a row stride.
 * Every one of those is a caller's choice at the designated initialiser and a read-only fact after.
 *
 * AND IT IS ONE PIECE OF STATE, NOT TWO REPRESENTATIONS IN A COAT: a rep is either
 *   * BITMAP-BACKED — it holds a byte buffer (`-bitmapData` answers it), or
 *   * CGIMAGE-BACKED — its pixels are a `CGImage`'s (the case `+imageRepWithData:` produces),
 * and `-bitmapData` answers NULL in the second case rather than unpacking a second copy. THAT IS A
 * STATED DEVIATION and it is the honest one: the decoded image's pixels live in the CGImage, and
 * copying them into a plane would be a second owner of the same bytes with no way to tell which is
 * authoritative. Apple always exposes a bitmap because its decoder always produces one; this layer
 * decodes straight into a CGImage (that is the only decoder it has), so it says so.
 *
 * **THE READ SIDE IS REAL AND THE WRITE SIDE WRITES PNG NOW, WHICH CORRECTS WHAT THIS HEADER SAID.** It used to
 * record, correctly at the time, that CoreGraphics here had the two decoders and NO ENCODER — "there is no
 * `CGImageDestination` in this tree, and no `libpng`/`libjpeg` write path behind one". Core Graphics grew one
 * (`libagora-drawing/CGImageDestination.[ch]`, over the same simplified libpng API its PNG decoder reads with), so
 * `-representationUsingType:properties:` answers for `NSPNGFileType` by handing the rep's `CGImage` to that
 * destination. MEASURED, and the measurement is a round trip through this class's own decoder: a 2x2 image goes out
 * as 97 bytes beginning `89 50 4E 47` and comes back at 2x2.
 *
 * AND WHAT IS STILL NOT ANSWERED IS REFUSED BY NAME, as before: `NSJPEGFileType` and the rest are types this build
 * does not write, a non-empty `properties` dictionary is refused rather than ignored (a caller that asked for an
 * interlaced PNG must not silently get a plain one), and `+representationOfImageRepsInArray:usingType:properties:`
 * answers ONE rep — because a PNG carries one image — and refuses an array of more rather than dropping pictures.
 * The two `+TIFFRepresentationOfImageRepsInArray:` forms still refuse, and so do `-canBeCompressedUsing:` (NO for
 * every compression) and `+getTIFFCompressionTypes:count:` (an EMPTY LIST): TIFF is not written here, and a list of
 * compressions this class cannot write would be a lie about it.
 *
 * AND WHAT THE PIXEL LAYOUT IS, SINCE A BUFFER NEEDS ONE: non-planar only (`isPlanar:YES` is refused
 * by name), one plane (`planes[0]`), and for a rep built FROM a CGImage the layout is READ OFF that
 * image (`CGImageGetBitsPerComponent` and friends) rather than assumed.
 *
 * **THE COLOUR ORDER OF A BITMAP-BACKED REP IS `R, G, B, A`, ALPHA LAST AND PREMULTIPLIED** — stated
 * here because a caller writing bytes needs it, and because getting it wrong is SILENT rather than
 * loud: the bytes are declared to Core Graphics with an explicit `kCGBitmapByteOrder32Big`, which stores
 * the 32-bit word in the order named. `kCGImageAlphaPremultipliedLast` ALONE would mean the DEFAULT
 * byte order, which is little-endian, and that reads the same bytes as `A, B, G, R` — so an opaque RED
 * pixel, whose byte 0 is 0, came out fully TRANSPARENT. That is not a hypothetical: it is what this
 * class shipped first, and the probe could not see it. An 8-bit grey rep (`samplesPerPixel:1`) has one
 * channel and no alpha byte.
 */

#import <AppKit/NSImageRep.h>
#import <Foundation/NSData.h>

NS_ASSUME_NONNULL_BEGIN

/* THE TIFF COMPRESSION CODES, WHICH ARE THE TIFF SPECIFICATION'S OWN NUMBERS rather than ours — the
 * only enum in this tier whose values are published by somebody other than Apple, and they are
 * published by the format. That is why they are transcribed exactly (1, 3, 4, 5, 6, 32766, 32773,
 * 32865) instead of being numbered from zero in declaration order, which is the rule everywhere else
 * in this tier. Apple files the type here; `NSImage`'s `-TIFFRepresentationUsingCompression:factor:`
 * is the door that takes one, and it refuses — see that header for the measured reason. */
typedef enum {
	NSTIFFCompressionNone = 1,
	NSTIFFCompressionCCITTFAX3 = 3,
	NSTIFFCompressionCCITTFAX4 = 4,
	NSTIFFCompressionLZW = 5,
	NSTIFFCompressionJPEG = 6,
	NSTIFFCompressionNEXT = 32766,
	NSTIFFCompressionPackBits = 32773,
	NSTIFFCompressionOldJPEG = 32865
} NSTIFFCompression;

/* THE LOAD STATUS OF AN INCREMENTAL LOAD, AND ITS VALUES ARE NEGATIVE — a fact about the header and not
 * a style choice: 10.2 and 10.6 both spell them `-1` … `-6`, so each is transcribed rather than
 * numbered in declaration order, and the type is SIGNED (`NSInteger`) because of it.
 *
 * IT IS NOT THE SAME FAMILY AS `NSImageLoadStatus` IN NSImage.h, AND THE DIFFERENCE IS REAL: that one
 * is `NSUInteger` running 0…4 with `Cancelled` and `ReadError` in it; this one is negative, and has
 * `UnknownType`, `ReadingHeader` and `WillNeedAllData` where the other has none of those. Apple
 * declares both at 10.6, in two headers, so this tier declares both too rather than folding them. */
typedef enum {
	NSImageRepLoadStatusUnknownType = -1,
	NSImageRepLoadStatusReadingHeader = -2,
	NSImageRepLoadStatusWillNeedAllData = -3,
	NSImageRepLoadStatusInvalidData = -4,
	NSImageRepLoadStatusUnexpectedEOF = -5,
	NSImageRepLoadStatusCompleted = -6
} NSImageRepLoadStatus;

/* THE FILE FORMATS, NUMBERED FROM ZERO IN THE HEADER'S OWN ORDER — Apple gives these no values, so the
 * order is the artefact's, the standing rule for an enum nobody publishes values for.
 *
 * **ALL SIX THE ERA DECLARES ARE HERE, AND THE SIXTH WAS LEFT OUT ON A NOTE THAT WAS WRONG.** The note
 * said `NSJPEG2000FileType` "arrives past 10.6" and the ledger struck it as post-10.6 to match. THE
 * CORPUS REFUTES BOTH: Apple's 10.6 header declares it INSIDE THIS VERY ENUM, behind `#if
 * MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4` — so 10.4 is when it arrives, and the strike
 * was an artefact of the guard, not a fact about the format. A class that cannot WRITE a format is still
 * not missing it from its vocabulary, and the encoder refuses every type except `NSPNGFileType` by name. */
typedef enum {
	NSTIFFFileType = 0,
	NSBMPFileType,
	NSGIFFileType,
	NSJPEGFileType,
	NSPNGFileType,
	NSJPEG2000FileType
} NSBitmapImageFileType;

/* AND THE FLAGS THAT DESCRIBE A PIXEL LAYOUT RATHER THAN A FORMAT. THESE values ARE published — bits,
 * `1 << n` — so they are transcribed, and the third is why the type exists in the era at all: it is
 * what says a rep's samples are floats instead of integers. */
typedef enum {
	NSAlphaFirstBitmapFormat = 1 << 0,
	NSAlphaNonpremultipliedBitmapFormat = 1 << 1,
	NSFloatingPointSamplesBitmapFormat = 1 << 2
} NSBitmapFormat;

/* THE PROPERTY KEYS, AND WHAT EACH ONE CARRIES. Apple declares fourteen, all of them for the ENCODER
 * half — the options a caller hands `-representationUsingType:properties:`, and the values a decoder
 * leaves behind — so on a class whose encoder reads none of them their VALUES are ours (the standing choice, the one the
 * named images make) while their meaning is Apple's, handed to `-setProperty:withValue:` and read back
 * with `-valueForProperty:` as the bag they were designed for. Declared rather than dropped for the same
 * reason the encoding doors are: a ported caller reads them BY NAME, and a name that does not exist is a
 * compile error where a name that does nothing is a documented no-op. */
extern NSString *NSImageCompressionMethod;         /* TIFF in/out — an NSTIFFCompression in an NSNumber */
extern NSString *NSImageCompressionFactor;         /* TIFF/JPEG in/out — a float in an NSNumber */
extern NSString *NSImageDitherTransparency;        /* GIF out — a BOOL in an NSNumber */
extern NSString *NSImageRGBColorTable;             /* GIF in/out — packed RGB in an NSData */
extern NSString *NSImageInterlaced;                /* PNG out — a BOOL in an NSNumber */
extern NSString *NSImageColorSyncProfileData;      /* TIFF in/out — an NSData */
extern NSString *NSImageFrameCount;                /* GIF in (read-only) — an int in an NSNumber */
extern NSString *NSImageCurrentFrame;              /* GIF in — an int in an NSNumber */
extern NSString *NSImageCurrentFrameDuration;      /* GIF in (read-only) — a float in an NSNumber */
extern NSString *NSImageGamma;                     /* PNG in/out — a float in an NSNumber */
extern NSString *NSImageProgressive;               /* JPEG in/out — a BOOL in an NSNumber */
extern NSString *NSImageEXIFData;                  /* JPEG in — an NSDictionary */
extern NSString *NSImageFallbackBackgroundColor;   /* JPEG out — an NSColor */
extern NSString *NSImageLoopCount;                 /* GIF out — an int in an NSNumber */

/* FORWARDED: all three are only ever pointer parameters or return types here, and naming them claims
 * nothing — a `@class` is a forward declaration and not an `@interface`. */
@class NSArray;
@class NSColor;
@class NSColorSpace;
@class NSDictionary;

@interface NSBitmapImageRep : NSImageRep
{
	unsigned char *_bits;       /* the pixels of a BITMAP-BACKED rep, or NULL */
	BOOL _ownsData;             /* NO when the caller's plane was adopted rather than allocated */
	NSInteger _bitsPerSample;
	NSInteger _samplesPerPixel;
	BOOL _hasAlpha;
	BOOL _isPlanar;
	NSInteger _bytesPerRow;
	NSInteger _bitsPerPixel;
	CGImageRef _cgImage;        /* RETAINED: a CGIMAGE-BACKED rep's pixels ARE this image */
	/* THE PROPERTY BAG AND THE TWO COMPRESSION FIELDS. The bag is a real dictionary — Apple's is a
	 * plist-ish bag hung off the rep, and the fourteen key constants above are its vocabulary — while the
	 * compression pair is RECORDED rather than used, because there is nothing to compress WITH: see the
	 * header's note on the encoder half. `-getCompression:factor:` answering what `-setCompression:factor:`
	 * was told is the whole of what it can truthfully do. */
	NSMutableDictionary *_properties;
	NSTIFFCompression _compression;
	float _compressionFactor;
	/* THE INCREMENTAL LOAD'S BUFFER, and it exists because this decoder has no incremental path: the
	 * status values are what let the class SAY so (see `-incrementalLoadFromData:complete:`). */
	NSMutableData *_incremental;
}

/* THE DESIGNATED INITIALISER, APPLE'S AND IN APPLE'S ORDER. A NULL `planes` (or a NULL `planes[0]`)
 * means ALLOCATE — that is Apple's contract and it is the useful default, so it is kept — and a
 * non-NULL one is ADOPTED: the buffer must outlive the rep, which is the same borrow the context
 * makes of a bitmap context's data. Returns nil for a layout this class cannot hold, and says why. */
- (nullable instancetype)initWithBitmapDataPlanes:(unsigned char * _Nullable * _Nullable)planes
				       pixelsWide:(NSInteger)pixelsWide
				       pixelsHigh:(NSInteger)pixelsHigh
				    bitsPerSample:(NSInteger)bitsPerSample
				  samplesPerPixel:(NSInteger)samplesPerPixel
					 hasAlpha:(BOOL)hasAlpha
					 isPlanar:(BOOL)isPlanar
				   colorSpaceName:(nullable NSString *)colorSpaceName
				      bytesPerRow:(NSInteger)bytesPerRow
				     bitsPerPixel:(NSInteger)bitsPerPixel;

/* THE CORE GRAPHICS DOOR, BOTH WAYS: `-initWithCGImage:` takes an image's pixels (retaining the image
 * rather than copying them), and `-CGImage` hands one back — the same image for a CGIMAGE-BACKED rep,
 * and for a BITMAP-BACKED one an image built over the rep's own bytes, CACHED so that two calls do not
 * produce two images. */
- (nullable instancetype)initWithCGImage:(CGImageRef)cgImage;

/* **AND THE TWO INITIALISERS THE 10.5 SURFACE ADDED.** `-initWithData:` takes ENCODED bytes and decodes them — it is
 * `+imageRepWithData:` as an initialiser, with the same two decoders and the same named refusal for anything else.
 * `-initWithBitmapDataPlanes:...bitmapFormat:...` is the 10.0 initialiser plus the format word, and it VALIDATES that
 * word: this class's own buffers are alpha-LAST and premultiplied, so a layout asking for alpha first, for
 * non-premultiplied samples or for floating-point samples is refused by name rather than accepted and drawn as though
 * it had been honoured — which is the silent wrong answer a format word exists to prevent. */
- (nullable instancetype)initWithData:(nullable NSData *)data;
- (nullable instancetype)initWithBitmapDataPlanes:(unsigned char * _Nullable * _Nullable)planes
				       pixelsWide:(NSInteger)pixelsWide
				       pixelsHigh:(NSInteger)pixelsHigh
				    bitsPerSample:(NSInteger)bitsPerSample
				  samplesPerPixel:(NSInteger)samplesPerPixel
					 hasAlpha:(BOOL)hasAlpha
					 isPlanar:(BOOL)isPlanar
				   colorSpaceName:(nullable NSString *)colorSpaceName
				    bitmapFormat:(NSBitmapFormat)bitmapFormat
				      bytesPerRow:(NSInteger)bytesPerRow
				     bitsPerPixel:(NSInteger)bitsPerPixel;
+ (nullable instancetype)imageRepWithCGImage:(CGImageRef)cgImage;

/* THE DECODE. The format is taken from the data's own first bytes rather than from a parameter — a
 * caller with PNG bytes should not have to say "these are PNG bytes" — and anything this library
 * cannot decode answers NIL, with the reason printed, rather than a rep with no pixels in it. */
+ (nullable instancetype)imageRepWithData:(NSData *)data;

/* THE LAYOUT, AS FACTS. `-bitmapData` is NULL for a CGIMAGE-BACKED rep (see the note above). */
@property (nullable, readonly) unsigned char *bitmapData;
/* **AND THE DEPTH IS THE BYTES' HERE, WHICH IS WHY THE PAIR IS SPELLED AS METHODS RATHER THAN A READONLY PROPERTY.**
 * `NSImageRep` declares `bitsPerSample` read-write now; a readonly property here would both restrict it (the compiler
 * measured exactly that mismatch) and leave a caller's `-setBitsPerSample:` writing the BASE's recorded value while
 * `-bitsPerSample` read this class's. Two methods, one ivar, and the pair cannot disagree. */
- (NSInteger)bitsPerSample;
- (void)setBitsPerSample:(NSInteger)bitsPerSample;

/* **AND THE REP'S SPACE AS AN OBJECT, WHICH THIS CLASS COULD NOT ANSWER UNTIL `NSColorSpace` EXISTED.** The name is what
 * this class stores; the mapping to a space is by NAME, and only the names this layer can be in are mapped — the two
 * device spaces this header exports and the calibrated pair the field decodes too. A rep carrying a name with no space
 * behind it answers nil AND SAYS WHICH NAME, because a guess here would be a colour conversion away from being wrong. */
- (nullable NSColorSpace *)colorSpace;

/* **AND THE TIFF PAIR, WHICH IS THE ONE PART OF THIS CLASS THAT IS A NAMED REFUSAL RATHER THAN A DOOR.** Writing a TIFF
 * needs an encoder, and this tree's CoreGraphics has exactly one: PNG (`CGImageDestination`, in libagora-drawing). The
 * compression and factor arguments would select among TIFF's codecs, and there are none to select between — so both
 * doors answer nil and say what they would need. A TIFF writer is a slice in libagora-drawing, not a stub here. */
+ (nullable NSData *)TIFFRepresentation;
+ (nullable NSData *)TIFFRepresentationUsingCompression:(NSTIFFCompression)compression factor:(float)factor;
@property (readonly) NSInteger samplesPerPixel;
@property (readonly) BOOL hasAlpha;
@property (readonly) BOOL isPlanar;
@property (readonly) NSInteger bytesPerRow;
@property (readonly) NSInteger bitsPerPixel;

/* ============================================================================================ *
 * THE ERA'S REMAINING DOORS. Three kinds again, each stated where it lands: real pixel access,  *
 * state an encoder would have read, and refusals by name.                                       *
 * ============================================================================================ */

/* THE PIXEL ACCESSORS, WHICH ARE THE C-LEVEL VIEW OF THE SAME BUFFER. `-getPixel:atX:y:` fills the
 * caller's array with the pixel's SAMPLES in this rep's own order (R, G, B, A for the common layout,
 * stated in the header above), and `-setPixel:atX:y:` writes them back. Both REFUSE BY NAME rather than
 * faulting when there is no readable buffer: a CGIMAGE-BACKED rep's pixels are the CGImage's, and this
 * class does not believe in a second writable copy of them.
 *
 * `-colorAtX:y:` is the object view of the same read and `-setColor:atX:y:` the object view of the
 * write, over an `NSColor` converted to components on the way in. */
- (void)getPixel:(NSUInteger *)p atX:(NSInteger)x y:(NSInteger)y;
- (void)setPixel:(NSUInteger *)p atX:(NSInteger)x y:(NSInteger)y;
- (nullable NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y;
- (void)setColor:(nullable NSColor *)color atX:(NSInteger)x y:(NSInteger)y;

/* AND THE PLANES THEMSELVES, for a caller who wants the buffer rather than a pixel. Non-planar here, so
 * `data[0]` is the buffer and the rest are NULL — the same fact `-isPlanar` answers. */
- (void)getBitmapDataPlanes:(unsigned char * _Nullable * _Nullable)data;

/* THE ONE PIECE OF PIXEL ARITHMETIC IN THIS CLASS, and it is real: every grey level is mapped through a
 * three-point ramp — `shadowColor` at 0, `midPointColor` at `midPoint`, `lightColor` at 1 — so a caller
 * can tint a grey image without touching its alpha. A rep with no readable buffer refuses by name. */
- (void)colorizeByMappingGray:(CGFloat)midPoint
		      toColor:(nullable NSColor *)midPointColor
		 blackMapping:(nullable NSColor *)shadowColor
		 whiteMapping:(nullable NSColor *)lightColor;

/* THE PROPERTY BAG, WHICH IS A REAL DICTIONARY. The fourteen keys above are its vocabulary; a nil value
 * REMOVES the key rather than storing a null in it, which is Apple's contract and the only reading that
 * makes `-valueForProperty:`'s answers mean anything. */
- (void)setProperty:(NSString *)property withValue:(nullable id)value;
- (nullable id)valueForProperty:(NSString *)property;

/* THE COMPRESSION PAIR. RECORDED, NOT USED — this build writes PNG, which has no compression setting to give, so
 * the only thing these can honestly do is remember what they were told and hand it back; see the header's note. */
- (void)getCompression:(NSTIFFCompression *)compression factor:(float *)factor;
- (void)setCompression:(NSTIFFCompression)compression factor:(float)factor;

/* AND WHAT CAN BE COMPRESSED, WHICH IS NOTHING, with `+getTIFFCompressionTypes:count:` answering an
 * EMPTY LIST for the same reason. A non-empty list would be the class claiming a capability it does not
 * have, which is the one kind of wrong answer this tier refuses to give. */
- (BOOL)canBeCompressedUsing:(NSTIFFCompression)compression;
+ (void)getTIFFCompressionTypes:(const NSTIFFCompression * _Nullable * _Nullable)list
			  count:(NSInteger *)numTypes;
+ (nullable NSString *)localizedNameForTIFFCompressionType:(NSTIFFCompression)compression;

/* THE INCREMENTAL LOAD. This decoder has no incremental path — PNG and JPEG here are decoded whole, by
 * CoreGraphics — so the pair is honest about it: `-incrementalLoadFromData:complete:` BUFFERS what it is
 * given and answers `WillNeedAllData` until the caller says the data is complete, and only then decodes
 * and answers `Completed`, `InvalidData` or `UnexpectedEOF`. That is exactly what the era's status
 * values mean, which is why they are declared above rather than invented. */
- (nullable instancetype)initForIncrementalLoad;
- (NSInteger)incrementalLoadFromData:(NSData *)data complete:(BOOL)complete;

/* READING PIXELS OUT OF THE CURRENT CONTEXT'S RECT. Apple's grabs a screen region; this one builds a
 * CGImage from the CURRENT BITMAP CONTEXT (`CGBitmapContextCreateImage`) and adopts it, so the new rep
 * carries the context's own layout instead of a byte copy this class would have to swizzle by hand — a
 * format assumption is where a silent channel swap lives, and this door does not make one. A non-bitmap
 * context, or no context at all, refuses by name. */
- (nullable instancetype)initWithFocusedViewRect:(NSRect)rect;

/* THE PLURAL DECODE. Apple's multi-image door — TIFF and GIF can carry several frames — answering an
 * array of ONE here, because both decoders in this tree produce a single image and an empty answer for
 * a good PNG would be the wrong lie. Data that decodes to nothing answers nil. */
+ (nullable NSArray *)imageRepsWithData:(NSData *)data;

/* AND THE ENCODER DOORS, WHICH REFUSE BY NAME — see the header's note. Each prints why and answers nil,
 * so a ported caller meets a reason rather than a crash or a silently empty buffer. */
- (nullable NSData *)representationUsingType:(NSBitmapImageFileType)storageType
				  properties:(nullable NSDictionary *)properties;
+ (nullable NSData *)representationOfImageRepsInArray:(NSArray *)imageReps
					   usingType:(NSBitmapImageFileType)storageType
					  properties:(nullable NSDictionary *)properties;
+ (nullable NSData *)TIFFRepresentationOfImageRepsInArray:(NSArray *)array;
+ (nullable NSData *)TIFFRepresentationOfImageRepsInArray:(NSArray *)array
					 usingCompression:(NSTIFFCompression)comp
						   factor:(float)factor;

/* ============================================================================================ *
 * THE REMAINING ROWS: TWO QUESTIONS THE CLASS CAN ANSWER EXACTLY, ONE IT DERIVES,                *
 * AND THREE DOORS INTO SOFTWARE THIS TIER HAS NOT GOT.                                           *
 * ============================================================================================ */

/* HOW MANY PLANES, AND HOW BIG ONE IS. BOTH ARE EXACT RATHER THAN APPROXIMATE, and the reason is the
 * same for each: this class holds ONE plane — `isPlanar:YES` is REFUSED by the initialiser, because there
 * is nowhere to put the others — so the plane is the whole image and its size is the row stride times the
 * height. Apple's own definitions, with the only arrangement this tier can be in. */
@property (readonly) NSInteger numberOfPlanes;
@property (readonly) NSInteger bytesPerPlane;

/* AND THE PIXEL LAYOUT, WHICH IS THE ONE PROPERTY HERE THAT IS DERIVED RATHER THAN STORED — see the
 * implementation, where the derivation is written out. The short version: the three flags in
 * `NSBitmapFormat` describe the ALPHA position, whether it is premultiplied and whether the samples are
 * floats, and the first two are readable off the layout (a rep that owns its bytes is alpha-LAST and
 * premultiplied; an image-backed one reports its own alpha info), while the third is never set because
 * this tier's CoreGraphics has no floating-point bitmap layout for a rep to have. */
@property (readonly) NSBitmapFormat bitmapFormat;

/* AND THE COLOUR-SPACE PAIR, WHICH REFUSES BY NAME. Both take an `NSColorSpace`, A CLASS THIS TIER DOES
 * NOT SHIP, and that is what decides it: the space here is a NAME (`-colorSpaceName`, and the string the
 * initialiser was given), so there is nothing to compare a caller's object against, and a conversion that
 * guessed the target from a string would be the silent wrong answer this tier refuses. The parameter is
 * spelled `id` for the over-crediting rule — naming NSColorSpace would have the ledger credit its class
 * row — and the honest answer to both doors is nil with the reason printed.
 *
 * AND THE INTENT IS SPELLED `NSInteger` WHERE APPLE SAYS `NSColorRenderingIntent`, which is the SAME TYPE
 * under a name this header cannot see: that typedef lives in NSGraphicsContext.h (Apple declares it there
 * too), and importing that file from here would close a cycle in the other direction — it `@class`-declares
 * THIS class. `NSColorRenderingIntent` IS an `NSInteger` typedef, so a caller passing
 * `NSColorRenderingIntentDefault` or any of its siblings compiles and means exactly what it says. */
- (nullable NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(id)targetSpace
						     renderingIntent:(NSInteger)renderingIntent;
- (nullable NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(id)newSpace;

/* AND THE CORE IMAGE INITIALISER, WHICH HAS NO SUBSTRATE: there is no Core Image in this tree, so there is
 * no CIImage to decode and the door answers nil with a refusal that says so. */
- (nullable instancetype)initWithCIImage:(id)ciImage;

@end

NS_ASSUME_NONNULL_END
