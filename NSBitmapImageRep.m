/*
 * NSBitmapImageRep — a byte buffer with a layout, or a CGImage with a layout, and the bridge.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreGraphics/CGBitmapContext.h>
#import <CoreGraphics/CGContext.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGDataProvider.h>
#import <CoreGraphics/CGImage.h>
#import <CoreGraphics/CGImageDestination.h>
#import <Foundation/NSString.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* THE COLOUR SPACE A CGImage IS IN, AS ONE OF THIS LAYER'S TWO NAMES. Read off the space rather than
 * guessed from the channel count, because a 1-channel 8-bit image is gray and a 1-channel 32-bit one
 * is not. */
static NSString *fn_name_for(CGColorSpaceRef cs)
{
	if (cs != NULL && CGColorSpaceGetModel(cs) == kCGColorSpaceModelMonochrome) {
		return NSDeviceGrayColorSpace;
	}
	return NSDeviceRGBColorSpace;
}

/* AND THE SPACE ITSELF, FROM THE NAME. The caller owns the +1 result. */
static CGColorSpaceRef fn_space_for(NSString *name)
{
	if (name != nil && [name isEqualToString:NSDeviceGrayColorSpace]) {
		return CGColorSpaceCreateDeviceGray();
	}
	return CGColorSpaceCreateDeviceRGB();
}

/* THE PROPERTY KEYS, DEFINED HERE BECAUSE A CONSTANT IS A DEFINITION. Their values are their own
 * identifiers, the same choice the named images and the image hints make: Apple publishes the symbol
 * and not the string, so the string is ours. */
NSString *NSImageCompressionMethod = @"NSImageCompressionMethod";
NSString *NSImageCompressionFactor = @"NSImageCompressionFactor";
NSString *NSImageDitherTransparency = @"NSImageDitherTransparency";
NSString *NSImageRGBColorTable = @"NSImageRGBColorTable";
NSString *NSImageInterlaced = @"NSImageInterlaced";
NSString *NSImageColorSyncProfileData = @"NSImageColorSyncProfileData";
NSString *NSImageFrameCount = @"NSImageFrameCount";
NSString *NSImageCurrentFrame = @"NSImageCurrentFrame";
NSString *NSImageCurrentFrameDuration = @"NSImageCurrentFrameDuration";
NSString *NSImageGamma = @"NSImageGamma";
NSString *NSImageProgressive = @"NSImageProgressive";
NSString *NSImageEXIFData = @"NSImageEXIFData";
NSString *NSImageFallbackBackgroundColor = @"NSImageFallbackBackgroundColor";
NSString *NSImageLoopCount = @"NSImageLoopCount";

@implementation NSBitmapImageRep

/* ============================================================================================ *
 * THE REGISTRY'S FIRST REGISTRANT. Apple's contract sentence names what a registrant must       *
 * answer, and this is that list: `+canInitWithData:`, the two type lists, `+imageRepWithData:`   *
 * (already here) and `+imageRepsWithData:` (already here). The base class's answers are the       *
 * abstract ones, so THESE are what the registry actually asks.                                    *
 *                                                                                                *
 * A CLASS REGISTERS ITSELF, which is what Apple's own subclasses do and the reason the base's     *
 * `+initialize` cannot do it: the base does not know its subclasses. The notification the base    *
 * posts on registration is how a client learns the list moved.                                    *
 * ============================================================================================ */

+ (void)initialize
{
	if (self == [NSBitmapImageRep class]) {
		[NSImageRep registerImageRepClass:self];
	}
}

/* THE SAME SNIFF THE DECODE USES, so the registry's answer cannot disagree with what a decode will
 * actually do: PNG's eight bytes or JPEG's SOI marker, and nothing else. */
+ (BOOL)canInitWithData:(NSData *)data
{
	const unsigned char *b = data != nil ? (const unsigned char *)[data bytes] : NULL;

	if (b == NULL || [data length] < 8) {
		return NO;
	}
	return (b[0] == 0xff && b[1] == 0xd8) ||
	       (b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G');
}

/* THE TYPES ARE THE TWO FORMATS THIS CLASS DECODES, in the FILE form and in the PASTEBOARD form. The
 * unfiltered list is the same list — nothing here filters — which is the same statement NSImage's own
 * lists make. `public.png` has an era constant; the era declares NO `NSPasteboardTypeJPEG`, so JPEG's UTI
 * is spelled out rather than invented a symbol for. */
+ (NSArray *)imageUnfilteredFileTypes
{
	return [NSArray arrayWithObjects:@"png", @"jpg", @"jpeg", nil];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	return [NSArray arrayWithObjects:NSPasteboardTypePNG, @"public.jpeg", nil];
}

+ (NSArray *)imageUnfilteredTypes
{
	return [self imageUnfilteredFileTypes];
}

+ (NSArray *)imageTypes
{
	return [self imageUnfilteredTypes];
}


- (nullable instancetype)initWithBitmapDataPlanes:(unsigned char * _Nullable * _Nullable)planes
				       pixelsWide:(NSInteger)pixelsWide
				       pixelsHigh:(NSInteger)pixelsHigh
				    bitsPerSample:(NSInteger)bitsPerSample
				  samplesPerPixel:(NSInteger)samplesPerPixel
					 hasAlpha:(BOOL)hasAlpha
					 isPlanar:(BOOL)isPlanar
				   colorSpaceName:(nullable NSString *)colorSpaceName
				      bytesPerRow:(NSInteger)bytesPerRow
				     bitsPerPixel:(NSInteger)bitsPerPixel
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* A LAYOUT THIS CLASS CANNOT HOLD IS REFUSED RATHER THAN HALF-ACCEPTED. Planar is the one that is a
	 * real feature and not a bad argument — it needs several planes and this class holds one — so it is
	 * named as absent rather than silently treated as non-planar. */
	if (isPlanar) {
		fprintf(stderr, "APPKIT-REFUSE: NSBitmapImageRep isPlanar:YES needs several planes, and this "
				"class holds ONE (non-planar only)\n");
		[self release];
		return nil;
	}
	if (pixelsWide <= 0 || pixelsHigh <= 0 || bitsPerSample <= 0 || samplesPerPixel <= 0
	    || bytesPerRow <= 0 || bitsPerPixel <= 0) {
		fprintf(stderr, "APPKIT-REFUSE: NSBitmapImageRep needs positive dimensions, a bit depth, a "
				"channel count and a stride (got %ldx%ld, %ld bits, %ld channels, "
				"%ld per row, %ld per pixel)\n", (long)pixelsWide, (long)pixelsHigh,
			(long)bitsPerSample, (long)samplesPerPixel, (long)bytesPerRow, (long)bitsPerPixel);
		[self release];
		return nil;
	}
	_pixelsWide = pixelsWide;
	_pixelsHigh = pixelsHigh;
	_size = NSMakeSize((CGFloat)pixelsWide, (CGFloat)pixelsHigh);
	_bitsPerSample = bitsPerSample;
	_samplesPerPixel = samplesPerPixel;
	_hasAlpha = hasAlpha;
	_isPlanar = NO;
	_bytesPerRow = bytesPerRow;
	_bitsPerPixel = bitsPerPixel;
	[self setColorSpaceName:colorSpaceName];

	if (planes == NULL || planes[0] == NULL) {
		/* ALLOCATE, ZEROED — an uninitialised buffer would make the first draw of a fresh rep depend on
		 * whatever the allocator had, which is exactly the kind of silent difference this tree refuses. */
		_bits = calloc(1, (size_t)bytesPerRow * (size_t)pixelsHigh);
		if (_bits == NULL) {
			[self release];
			return nil;
		}
		_ownsData = YES;
	} else {
		_bits = planes[0];
		_ownsData = NO;
	}
	_cgImage = NULL;
	[self cg_initEraState];
	return self;
}

/* THE STATE THE ERA'S DOORS NEED, in ONE place so the two initialisers cannot disagree about it. */
- (void)cg_initEraState
{
	_properties = nil;
	/* APPLE'S DEFAULT, and the one that means "the format's own choice": `NSTIFFCompressionNone` is 1
	 * and not 0, which is why this is not left to the zeroed ivars. */
	_compression = NSTIFFCompressionNone;
	_compressionFactor = 1.0f;
	_incremental = nil;
}

- (nullable instancetype)initWithCGImage:(CGImageRef)cgImage
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (cgImage == NULL) {
		[self release];
		return nil;
	}
	/* RETAINED RATHER THAN COPIED: the pixels are the image's and this rep is the second owner, which is
	 * what makes `-bitmapData` answering NULL honest instead of lossy. */
	_cgImage = CGImageRetain(cgImage);
	_pixelsWide = (NSInteger)CGImageGetWidth(cgImage);
	_pixelsHigh = (NSInteger)CGImageGetHeight(cgImage);
	_size = NSMakeSize((CGFloat)_pixelsWide, (CGFloat)_pixelsHigh);
	_bitsPerSample = (NSInteger)CGImageGetBitsPerComponent(cgImage);
	_bitsPerPixel = (NSInteger)CGImageGetBitsPerPixel(cgImage);
	_samplesPerPixel = _bitsPerSample > 0 ? _bitsPerPixel / _bitsPerSample : _bitsPerPixel / 8;
	_bytesPerRow = (_bitsPerPixel / 8) * _pixelsWide;
	_hasAlpha = CGImageGetAlphaInfo(cgImage) != kCGImageAlphaNone;
	_isPlanar = NO;
	_bits = NULL;
	_ownsData = NO;
	[self cg_initEraState];
	[self setColorSpaceName:fn_name_for(CGImageGetColorSpace(cgImage))];
	return self;
}

/* **AND THE TWO INITIALISERS THE 10.5 SURFACE ADDED, EACH ASKING THE EXISTING DOOR TO DO ITS JOB.** `-initWithData:`
 * decodes through `+imageRepWithData:` and ADOPTS the result, which is the same move `-incrementalLoadFromData:` makes
 * at its completion — one decoder, two doors, no second copy of the format sniffing. The bytes' rep is autoreleased and
 * this object takes a retain of its image, so the two lifetimes stay separate. */
- (nullable instancetype)initWithData:(NSData *)data
{
	NSBitmapImageRep *decoded;

	self = [super init];
	if (self == nil) {
		return nil;
	}
	decoded = [NSBitmapImageRep imageRepWithData:data];
	if (decoded == nil) {
		/* THE REFUSAL HAS ALREADY BEEN NAMED BY THE DECODER, which is the one place that knows the signature. */
		[self release];
		return nil;
	}
	[self cg_adoptRep:decoded];
	[self cg_initEraState];
	return self;
}

/* **AND THE FORMAT WORD IS CHECKED AGAINST WHAT THIS CLASS CAN HOLD.** Its own buffers are alpha-LAST and premultiplied
 * (see `-bitmapFormat`, which derives the flags from the layout), and this tier's CoreGraphics has no floating-point
 * bitmap layout — so three of the format's flags describe a rep this class cannot be. Accepting the word and ignoring it
 * would leave a caller believing their layout was honoured; the refusal NAMES the flag, because "your alpha is
 * somewhere else" and "your samples are floats" are different problems with different fixes. */
- (nullable instancetype)initWithBitmapDataPlanes:(unsigned char **)planes
				       pixelsWide:(NSInteger)pixelsWide
				       pixelsHigh:(NSInteger)pixelsHigh
				    bitsPerSample:(NSInteger)bitsPerSample
				  samplesPerPixel:(NSInteger)samplesPerPixel
					 hasAlpha:(BOOL)hasAlpha
					 isPlanar:(BOOL)isPlanar
				   colorSpaceName:(NSString *)colorSpaceName
				    bitmapFormat:(NSBitmapFormat)bitmapFormat
				      bytesPerRow:(NSInteger)bytesPerRow
				     bitsPerPixel:(NSInteger)bitsPerPixel
{
	if ((bitmapFormat & NSAlphaFirstBitmapFormat) != 0) {
		fprintf(stderr, "APPKIT-REFUSE: -initWithBitmapDataPlanes:...bitmapFormat: needs "
				"NSAlphaFirstBitmapFormat, and this class's own buffers are alpha-LAST "
				"(the image-backed layout reports its own, but an initialiser cannot promise one)\n");
		[self release];
		return nil;
	}
	if ((bitmapFormat & NSAlphaNonpremultipliedBitmapFormat) != 0) {
		fprintf(stderr, "APPKIT-REFUSE: -initWithBitmapDataPlanes:...bitmapFormat: needs "
				"NSAlphaNonpremultipliedBitmapFormat, and this class's own buffers are premultiplied\n");
		[self release];
		return nil;
	}
	if ((bitmapFormat & NSFloatingPointSamplesBitmapFormat) != 0) {
		fprintf(stderr, "APPKIT-REFUSE: -initWithBitmapDataPlanes:...bitmapFormat: needs "
				"NSFloatingPointSamplesBitmapFormat, and this tier's CoreGraphics has no "
				"floating-point bitmap layout\n");
		[self release];
		return nil;
	}
	/* EVERYTHING ELSE IS THE 10.0 INITIALISER, whose layout this class already derives the same flags from. */
	return [self initWithBitmapDataPlanes:planes pixelsWide:pixelsWide pixelsHigh:pixelsHigh
				bitsPerSample:bitsPerSample samplesPerPixel:samplesPerPixel
				     hasAlpha:hasAlpha isPlanar:isPlanar colorSpaceName:colorSpaceName
				  bytesPerRow:bytesPerRow bitsPerPixel:bitsPerPixel];
}

+ (nullable instancetype)imageRepWithCGImage:(CGImageRef)cgImage
{
	return [[[self alloc] initWithCGImage:cgImage] autorelease];
}

+ (nullable instancetype)imageRepWithData:(NSData *)data
{
	const unsigned char *b = (const unsigned char *)[data bytes];
	NSUInteger n = [data length];
	CGDataProviderRef prov;
	CGImageRef img = NULL;
	NSBitmapImageRep *rep;

	if (b == NULL || n < 8) {
		fprintf(stderr, "APPKIT-REFUSE: +imageRepWithData: needs at least 8 bytes to identify a "
				"format (got %lu)\n", (unsigned long)n);
		return nil;
	}
	/* THE FORMAT COMES FROM THE DATA, because the two formats this library decodes each begin with an
	 * unambiguous signature — PNG's eight bytes and JPEG's SOI marker. Anything else is refused by
	 * name: this is not "unsupported by accident", it is the whole of what the decoder set here does. */
	if (b[0] == 0xff && b[1] == 0xd8) {
		prov = CGDataProviderCreateWithData(NULL, b, (size_t)n, NULL);
		if (prov == NULL) {
			return nil;
		}
		img = CGImageCreateWithJPEGDataProvider(prov, NULL, false, kCGRenderingIntentDefault);
		CGDataProviderRelease(prov);
	} else if (b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') {
		prov = CGDataProviderCreateWithData(NULL, b, (size_t)n, NULL);
		if (prov == NULL) {
			return nil;
		}
		img = CGImageCreateWithPNGDataProvider(prov, NULL, false, kCGRenderingIntentDefault);
		CGDataProviderRelease(prov);
	} else {
		fprintf(stderr, "APPKIT-REFUSE: +imageRepWithData: decodes PNG and JPEG only, and these "
				"bytes are neither (CoreGraphics in this tree has the two DECODERS and no "
				"encoder)\n");
		return nil;
	}
	if (img == NULL) {
		return nil;
	}
	rep = [[self alloc] initWithCGImage:img];
	CGImageRelease(img);
	return [rep autorelease];
}

- (unsigned char *)bitmapData
{
	return _bits;
}

- (NSInteger)bitsPerSample
{
	return _bitsPerSample;
}

/* **THE SETTER WRITES THE DEPTH THE PIXELS ARE IN, WHICH IS THIS CLASS'S OWN FIELD** — see the header. The base's
 * `_repBitsPerSample` is what a rep with no pixels of its own was told; here the depth is a fact about the bytes, and a
 * caller who sets it is describing the buffer the rep already holds. Nothing re-lays-out the pixels: this is the era's
 * door for "record what these bytes are", not a conversion. */
- (void)setBitsPerSample:(NSInteger)bitsPerSample
{
	_bitsPerSample = bitsPerSample;
}

- (NSInteger)samplesPerPixel
{
	return _samplesPerPixel;
}

- (BOOL)hasAlpha
{
	return _hasAlpha;
}

- (BOOL)isPlanar
{
	return _isPlanar;
}

- (NSInteger)bytesPerRow
{
	return _bytesPerRow;
}

- (NSInteger)bitsPerPixel
{
	return _bitsPerPixel;
}

- (CGImageRef)CGImage
{
	/* A CGIMAGE-BACKED REP ANSWERS ITS OWN IMAGE, which is the one it was built from. */
	if (_cgImage != NULL) {
		return _cgImage;
	}
	if (_bits == NULL) {
		return NULL;
	}
	/* AND A BITMAP-BACKED ONE BUILDS THE IMAGE OVER ITS OWN BYTES, ONCE. The provider is the same
	 * borrow the initialiser made — it does not own the buffer and must not free it — and the result is
	 * cached, so the rep and the image share one buffer rather than two that could drift apart. */
	{
		CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, _bits,
								     (size_t)_bytesPerRow * (size_t)_pixelsHigh,
								     NULL);
		CGColorSpaceRef cs = fn_space_for(_colorSpaceName);
		/* THE PARAMETER IS A PLAIN `uint32_t` IN THIS TREE, not Apple's `CGBitmapInfo` — which
		 * does not exist here (measured at the declaration), and reaching for it was the same
		 * kind of mistake as assuming an Apple CGPath function existed.
		 *
		 * AND THE BYTE ORDER IS SAID OUT LOUD, WHICH IS THE FIX FOR A REAL BUG THIS FILE SHIPPED
		 * WITH: this rep's bytes are R, G, B, A (the swizzle in `NSImage` writes that order and the
		 * caller wrote that order), and `kCGImageAlphaPremultipliedLast` ALONE means the DEFAULT
		 * byte order — which is little-endian, and for this declaration that is memory A, B, G, R.
		 * So byte 0 was read as ALPHA: every opaque RED pixel has R=0 in byte 0 and came out fully
		 * TRANSPARENT. It went unnoticed because the probe filled the rep with opaque WHITE, the
		 * one colour whose channels all agree. 32Big stores the word in the NAMED order, which is
		 * what these bytes are. */
		uint32_t info = _hasAlpha
			? (uint32_t)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big)
			: (uint32_t)kCGBitmapByteOrder32Big;

		if (prov != NULL && cs != NULL) {
			_cgImage = CGImageCreate((size_t)_pixelsWide, (size_t)_pixelsHigh,
						 (size_t)_bitsPerSample, (size_t)_bitsPerPixel,
						 (size_t)_bytesPerRow, cs, info, prov, NULL, false,
						 kCGRenderingIntentDefault);
		}
		if (prov != NULL) {
			CGDataProviderRelease(prov);
		}
		if (cs != NULL) {
			CGColorSpaceRelease(cs);
		}
	}
	return _cgImage;
}

- (void)dealloc
{
	if (_cgImage != NULL) {
		CGImageRelease(_cgImage);
	}
	if (_ownsData && _bits != NULL) {
		free(_bits);
	}
	[_properties release];
	[_incremental release];
	[super dealloc];
}


/* ============================================================================================ *
 * THE ERA'S REMAINING DOORS.                                                                     *
 * ============================================================================================ */

/* THE ONE PIXEL READER, USED BY BOTH PUBLIC READS, AND IT COVERS BOTH BACKINGS. A bitmap-backed rep
 * reads its buffer; a CGIMAGE-backed one — which is what `+imageRepWithData:` produces, and the common
 * case a caller wants to sample — is read by DRAWING THE ONE PIXEL OUT into a 1x1 bitmap context in the
 * rep's own declared order, so what comes back is the convention `-bitmapData` would have handed over.
 * Two readers would be two conventions; this is one.
 *
 * THE SAMPLE WIDTHS ARE 8, 16 AND 32 BITS, which are the widths a rep here can hold; anything else is a
 * NO rather than a guess at a packed layout. */
- (BOOL)cg_readPixelAtX:(NSInteger)x y:(NSInteger)y into:(NSUInteger *)out
{
	NSInteger bps = _bitsPerSample / 8;
	NSInteger i;

	if (out == NULL || _samplesPerPixel <= 0 || x < 0 || y < 0 || x >= _pixelsWide || y >= _pixelsHigh) {
		return NO;
	}
	if (bps != 1 && bps != 2 && bps != 4) {
		return NO;
	}
	if (_bits != NULL) {
		const unsigned char *row = _bits + (size_t)y * (size_t)_bytesPerRow
					   + (size_t)x * (size_t)(bps * _samplesPerPixel);

		for (i = 0; i < _samplesPerPixel; i++) {
			if (bps == 1) {
				out[i] = row[i];
			} else if (bps == 2) {
				uint16_t v;
				memcpy(&v, row + 2 * i, 2);
				out[i] = v;
			} else {
				uint32_t v;
				memcpy(&v, row + 4 * i, 4);
				out[i] = v;
			}
		}
		return YES;
	}
	{
		CGImageRef whole = [self CGImage];
		CGImageRef sub;
		CGContextRef c;
		CGColorSpaceRef cs;
		unsigned char px[4];

		if (whole == NULL) {
			return NO;
		}
		sub = CGImageCreateWithImageInRect(whole, CGRectMake((CGFloat)x, (CGFloat)y, 1.0, 1.0));
		if (sub == NULL) {
			return NO;
		}
		memset(px, 0, sizeof(px));
		cs = CGColorSpaceCreateDeviceRGB();
		c = CGBitmapContextCreate(px, 1, 1, 8, 4, cs,
					  (uint32_t)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
		CGColorSpaceRelease(cs);
		if (c != NULL) {
			CGContextDrawImage(c, CGRectMake(0.0, 0.0, 1.0, 1.0), sub);
			CGContextRelease(c);
		}
		CGImageRelease(sub);
		for (i = 0; i < _samplesPerPixel && i < 4; i++) {
			out[i] = px[i];
		}
		return YES;
	}
}

/* AND THE ONE PIXEL WRITER, WHICH IS BITMAP-ONLY AND SAYS SO. A CGIMAGE-BACKED rep's pixels are the
 * image's; writing into a copy this class made would be a write nobody else can see. */
- (BOOL)cg_writePixel:(const NSUInteger *)in atX:(NSInteger)x y:(NSInteger)y
{
	NSInteger bps = _bitsPerSample / 8;
	NSInteger i;

	if (in == NULL || _bits == NULL || x < 0 || y < 0 || x >= _pixelsWide || y >= _pixelsHigh) {
		return NO;
	}
	if (bps != 1 && bps != 2 && bps != 4) {
		return NO;
	}
	{
		unsigned char *row = _bits + (size_t)y * (size_t)_bytesPerRow
				     + (size_t)x * (size_t)(bps * _samplesPerPixel);

		for (i = 0; i < _samplesPerPixel; i++) {
			if (bps == 1) {
				row[i] = (unsigned char)in[i];
			} else if (bps == 2) {
				uint16_t v = (uint16_t)in[i];
				memcpy(row + 2 * i, &v, 2);
			} else {
				uint32_t v = (uint32_t)in[i];
				memcpy(row + 4 * i, &v, 4);
			}
		}
	}
	return YES;
}

/* THE LARGEST SAMPLE VALUE, which is what turns a stored sample into the 0…1 an NSColor takes. */
- (double)cg_sampleMax
{
	return _bitsPerSample >= 32 ? 4294967295.0
	       : (_bitsPerSample >= 16 ? 65535.0 : 255.0);
}

- (void)getPixel:(NSUInteger *)p atX:(NSInteger)x y:(NSInteger)y
{
	if (![self cg_readPixelAtX:x y:y into:p]) {
		fprintf(stderr, "APPKIT-REFUSE: -getPixel:atX:y: needs a readable buffer and a pixel inside "
				"the rep; this one is %s at (%ld,%ld) in a %ldx%ld rep\n",
			_bits == NULL ? "CGIMAGE-backed with no CGImage" : "bitmap-backed",
			(long)x, (long)y, (long)_pixelsWide, (long)_pixelsHigh);
	}
}

- (void)setPixel:(NSUInteger *)p atX:(NSInteger)x y:(NSInteger)y
{
	if (![self cg_writePixel:p atX:x y:y]) {
		fprintf(stderr, "APPKIT-REFUSE: -setPixel:atX:y: needs a WRITABLE bitmap buffer; %s\n",
			_bits == NULL ? "this rep is CGIMAGE-backed, whose pixels belong to the image"
				      : "and this pixel is outside the rep");
	}
}

- (nullable NSColor *)colorAtX:(NSInteger)x y:(NSInteger)y
{
	NSUInteger s[4] = { 0, 0, 0, 0 };
	double max = [self cg_sampleMax];

	if (![self cg_readPixelAtX:x y:y into:s]) {
		return nil;
	}
	if (_samplesPerPixel >= 3) {
		CGFloat a = _hasAlpha ? (CGFloat)((double)s[3] / max) : 1.0;

		return [NSColor colorWithDeviceRed:(CGFloat)((double)s[0] / max)
					     green:(CGFloat)((double)s[1] / max)
					      blue:(CGFloat)((double)s[2] / max)
					     alpha:a];
	}
	return [NSColor colorWithDeviceWhite:(CGFloat)((double)s[0] / max)
				       alpha:_hasAlpha ? (CGFloat)((double)s[1] / max) : 1.0];
}

- (void)setColor:(nullable NSColor *)color atX:(NSInteger)x y:(NSInteger)y
{
	NSUInteger s[4];
	double max = [self cg_sampleMax];
	CGFloat r = 0.0, g = 0.0, b = 0.0, a = 1.0;

	if (color == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -setColor:atX:y: needs a colour\n");
		return;
	}
	[color getRed:&r green:&g blue:&b alpha:&a];
	if (_samplesPerPixel >= 3) {
		/* PREMULTIPLIED ON THE WAY IN, which is this rep's stated layout: writing straight components
		 * into a premultiplied buffer is how a translucent pixel turns opaque. */
		s[0] = (NSUInteger)(r * a * max + 0.5);
		s[1] = (NSUInteger)(g * a * max + 0.5);
		s[2] = (NSUInteger)(b * a * max + 0.5);
		s[3] = _hasAlpha ? (NSUInteger)(a * max + 0.5) : 0;
	} else {
		s[0] = (NSUInteger)(((r + g + b) / 3.0) * max + 0.5);
		s[1] = _hasAlpha ? (NSUInteger)(a * max + 0.5) : 0;
	}
	if (![self cg_writePixel:s atX:x y:y]) {
		fprintf(stderr, "APPKIT-REFUSE: -setColor:atX:y: needs a WRITABLE bitmap buffer; this rep "
				"is CGIMAGE-backed, whose pixels belong to the image\n");
	}
}

- (void)getBitmapDataPlanes:(unsigned char **)data
{
	if (data == NULL) {
		return;
	}
	/* NON-PLANAR HERE, so plane 0 is the buffer and the rest are NULL — the same fact `-isPlanar`
	 * answers, said in the shape a caller of THIS door expects. */
	data[0] = _bits;
	data[1] = NULL;
	data[2] = NULL;
	data[3] = NULL;
	data[4] = NULL;
}

/* THE GREY RAMP. `t` is the pixel's own grey level: the sample itself for a one-channel rep, and the
 * luminance of the UN-PREMULTIPLIED colour for a multi-channel one (a premultiplied buffer's channels
 * are scaled by alpha, so reading the grey off them directly would make every translucent pixel look
 * dark). The mapping is the three-point ramp Apple's name states, and the result is re-premultiplied.
 * An alpha of zero keeps a zero pixel: there is no colour to map. */
- (void)colorizeByMappingGray:(CGFloat)midPoint
		      toColor:(nullable NSColor *)midPointColor
		 blackMapping:(nullable NSColor *)shadowColor
		 whiteMapping:(nullable NSColor *)lightColor
{
	NSInteger x, y, i;
	double max = [self cg_sampleMax];
	CGFloat mr = 0.5, mg = 0.5, mb = 0.5, sr = 0.0, sg = 0.0, sb = 0.0, lr = 1.0, lg = 1.0, lb = 1.0;

	if (_bits == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -colorizeByMappingGray: needs a WRITABLE bitmap buffer; this "
				"rep is CGIMAGE-backed, whose pixels belong to the image\n");
		return;
	}
	if (!(midPoint > 0.0 && midPoint < 1.0)) {
		fprintf(stderr, "APPKIT-REFUSE: -colorizeByMappingGray: needs a midPoint STRICTLY between 0 "
				"and 1 (got %g); a ramp with a degenerate middle is not a ramp\n",
			(double)midPoint);
		return;
	}
	if (midPointColor != nil) {
		[NSColor class];        /* the colour class must be loaded before the message below */
		[midPointColor getRed:&mr green:&mg blue:&mb alpha:NULL];
	}
	if (shadowColor != nil) {
		[shadowColor getRed:&sr green:&sg blue:&sb alpha:NULL];
	}
	if (lightColor != nil) {
		[lightColor getRed:&lr green:&lg blue:&lb alpha:NULL];
	}
	for (y = 0; y < _pixelsHigh; y++) {
		for (x = 0; x < _pixelsWide; x++) {
			NSUInteger s[4] = { 0, 0, 0, 0 };
			double t, cr, cg, cb, alpha;

			if (![self cg_readPixelAtX:x y:y into:s]) {
				continue;
			}
			alpha = _hasAlpha ? (double)s[3] / max : 1.0;
			if (_samplesPerPixel >= 3) {
				double ur = alpha > 0.0 ? (double)s[0] / max / alpha : 0.0;
				double ug = alpha > 0.0 ? (double)s[1] / max / alpha : 0.0;
				double ub = alpha > 0.0 ? (double)s[2] / max / alpha : 0.0;

				t = 0.299 * ur + 0.587 * ug + 0.114 * ub;
			} else {
				t = (double)s[0] / max;
			}
			if (t <= 0.0) {
				cr = sr; cg = sg; cb = sb;
			} else if (t < midPoint) {
				double f = t / midPoint;

				cr = sr + (mr - sr) * f; cg = sg + (mg - sg) * f; cb = sb + (mb - sb) * f;
			} else {
				double f = (t - midPoint) / (1.0 - midPoint);

				cr = mr + (lr - mr) * f; cg = mg + (lg - mg) * f; cb = mb + (lb - mb) * f;
			}
			if (_samplesPerPixel >= 3) {
				s[0] = (NSUInteger)(cr * alpha * max + 0.5);
				s[1] = (NSUInteger)(cg * alpha * max + 0.5);
				s[2] = (NSUInteger)(cb * alpha * max + 0.5);
			} else {
				s[0] = (NSUInteger)((0.299 * cr + 0.587 * cg + 0.114 * cb) * max + 0.5);
			}
			(void)[self cg_writePixel:s atX:x y:y];
		}
	}
	for (i = 0; i < 1; i++) {
		(void)i;
	}
}

- (void)setProperty:(NSString *)property withValue:(nullable id)value
{
	if (property == nil) {
		return;
	}
	if (value == nil) {
		/* A NIL VALUE REMOVES THE KEY, which is Apple's contract and the only reading under which
		 * `-valueForProperty:`'s answers mean anything. */
		[_properties removeObjectForKey:property];
		return;
	}
	if (_properties == nil) {
		_properties = [[NSMutableDictionary alloc] init];
	}
	[_properties setObject:value forKey:property];
}

- (nullable id)valueForProperty:(NSString *)property
{
	if (property == nil || _properties == nil) {
		return nil;
	}
	return [_properties objectForKey:property];
}

/* ---- THE SPACE AS AN OBJECT, AND THE TIFF PAIR THAT IS NOT A DOOR ------------------------------- */

/* **FOUR NAMES, FOUR SPACES, AND NO GUESS FOR ANY OTHER.** The rep stores a colour-space NAME (that is the era's model
 * here); `NSColorSpace` arrived two slices after this class did, which is why this door is new rather than late. The
 * mapping is by name and covers the spaces a rep in this layer can actually be in — the two device ones this header
 * exports, the calibrated pair a decoded picture is in, and CMYK — and an unrecognised name answers nil with the name
 * printed, because picking a "close" space would be a colour conversion away from being wrong. `NSCustomColorSpace`,
 * `NSNamedColorSpace` and `NSPatternColorSpace` are exactly the names with no space behind them, and they land in that
 * refusal rather than pretending. */
- (NSColorSpace *)colorSpace
{
	NSString *name = [self colorSpaceName];

	if (name == nil) {
		return nil;
	}
	if ([name isEqualToString:NSDeviceRGBColorSpace]) {
		return [NSColorSpace deviceRGBColorSpace];
	}
	if ([name isEqualToString:NSDeviceGrayColorSpace] || [name isEqualToString:NSDeviceWhiteColorSpace]) {
		return [NSColorSpace deviceGrayColorSpace];
	}
	if ([name isEqualToString:NSCalibratedRGBColorSpace]) {
		return [NSColorSpace genericRGBColorSpace];
	}
	if ([name isEqualToString:NSCalibratedWhiteColorSpace]) {
		return [NSColorSpace genericGrayColorSpace];
	}
	if ([name isEqualToString:NSDeviceCMYKColorSpace]) {
		return [NSColorSpace deviceCMYKColorSpace];
	}
	fprintf(stderr, "APPKIT-REFUSE: -colorSpace needs a space behind the rep's colour-space NAME, and this "
			"tier has none for \"%s\" (the names it can map are the device RGB/gray/CMYK ones and the "
			"calibrated pair; a custom, named or pattern space has no object here)\n", [name UTF8String]);
	return nil;
}

/* **AND THE TIFF PAIR IS THE CLASS'S ONE NAMED REFUSAL.** A TIFF is written by an encoder, and this tree's
 * CoreGraphics has one — PNG. The compression and factor arguments would choose among TIFF's codecs; there are none to
 * choose between, and writing an uncompressed TIFF from here would be a second encoder living in the wrong layer. So
 * both answer nil and say what they would need, which is the honest shape of "not this build". */
+ (NSData *)TIFFRepresentation
{
	fprintf(stderr, "APPKIT-REFUSE: +TIFFRepresentation needs a TIFF ENCODER; this tree's CGImageDestination "
			"writes PNG only, and a TIFF writer belongs there rather than here\n");
	return nil;
}

+ (NSData *)TIFFRepresentationUsingCompression:(NSTIFFCompression)compression factor:(float)factor
{
	(void)compression;
	(void)factor;
	fprintf(stderr, "APPKIT-REFUSE: +TIFFRepresentationUsingCompression:factor: needs a TIFF ENCODER with "
			"codecs to choose between; this tree's CGImageDestination writes PNG only\n");
	return nil;
}

- (void)getCompression:(NSTIFFCompression *)compression factor:(float *)factor
{
	if (compression != NULL) {
		*compression = _compression;
	}
	if (factor != NULL) {
		*factor = _compressionFactor;
	}
}

- (void)setCompression:(NSTIFFCompression)compression factor:(float)factor
{
	_compression = compression;
	_compressionFactor = factor;
}

/* NOTHING CAN BE COMPRESSED, AND THAT IS THE ANSWER RATHER THAN A STUB: there is no encoder in this
 * tree, so every compression type is one this class cannot write. */
- (BOOL)canBeCompressedUsing:(NSTIFFCompression)compression
{
	(void)compression;
	return NO;
}

+ (void)getTIFFCompressionTypes:(const NSTIFFCompression **)list count:(NSInteger *)numTypes
{
	/* AN EMPTY LIST, for the same measured reason: the two values a caller can receive are a pointer to
	 * a static list and its length, and the honest pair here is NULL and 0. */
	if (list != NULL) {
		*list = NULL;
	}
	if (numTypes != NULL) {
		*numTypes = 0;
	}
}

+ (nullable NSString *)localizedNameForTIFFCompressionType:(NSTIFFCompression)compression
{
	/* THE NAMES ARE OURS AND THEY ARE THE CONSTANTS, which is the same choice the property keys and the
	 * named images make: Apple's are localized strings, and a localization this tree does not have is
	 * better named than invented. An unknown code answers nil. */
	switch (compression) {
	case NSTIFFCompressionNone: return @"NSTIFFCompressionNone";
	case NSTIFFCompressionCCITTFAX3: return @"NSTIFFCompressionCCITTFAX3";
	case NSTIFFCompressionCCITTFAX4: return @"NSTIFFCompressionCCITTFAX4";
	case NSTIFFCompressionLZW: return @"NSTIFFCompressionLZW";
	case NSTIFFCompressionJPEG: return @"NSTIFFCompressionJPEG";
	case NSTIFFCompressionNEXT: return @"NSTIFFCompressionNEXT";
	case NSTIFFCompressionPackBits: return @"NSTIFFCompressionPackBits";
	case NSTIFFCompressionOldJPEG: return @"NSTIFFCompressionOldJPEG";
	default: return nil;
	}
}

/* THE INCREMENTAL LOAD, WHICH THIS DECODER CANNOT DO INCREMENTALLY — so it says so with the era's own
 * status values instead of pretending. The buffer is real, the answer is honest, and when the caller
 * says `complete:YES` the decode happens and the rep ADOPTS the result, which is what makes the object
 * the caller holds the one with the pixels. */
- (nullable instancetype)initForIncrementalLoad
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_bits = NULL;
	_ownsData = NO;
	_cgImage = NULL;
	[self cg_initEraState];
	_incremental = [[NSMutableData alloc] init];
	return self;
}

- (void)cg_adoptRep:(NSBitmapImageRep *)rep
{
	if (rep == nil || rep->_cgImage == NULL) {
		return;
	}
	if (_cgImage != NULL) {
		CGImageRelease(_cgImage);
	}
	_cgImage = CGImageRetain(rep->_cgImage);
	_pixelsWide = rep->_pixelsWide;
	_pixelsHigh = rep->_pixelsHigh;
	_size = rep->_size;
	_bitsPerSample = rep->_bitsPerSample;
	_samplesPerPixel = rep->_samplesPerPixel;
	_hasAlpha = rep->_hasAlpha;
	_isPlanar = NO;
	_bytesPerRow = rep->_bytesPerRow;
	_bitsPerPixel = rep->_bitsPerPixel;
	[self setColorSpaceName:[rep colorSpaceName]];
}

- (NSInteger)incrementalLoadFromData:(NSData *)data complete:(BOOL)complete
{
	const unsigned char *b;

	if (data != nil) {
		if (_incremental == nil) {
			_incremental = [[NSMutableData alloc] init];
		}
		[_incremental appendData:data];
	}
	b = _incremental != nil ? (const unsigned char *)[_incremental bytes] : NULL;
	if (b == NULL || [_incremental length] < 8) {
		/* NOT ENOUGH DATA TO DETERMINE A FORMAT — the era header's own wording for this value. */
		return NSImageRepLoadStatusReadingHeader;
	}
	if (!((b[0] == 0xff && b[1] == 0xd8) ||
	      (b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G'))) {
		return NSImageRepLoadStatusUnknownType;
	}
	if (!complete) {
		/* "can't read incrementally. will wait for complete data to become avail." */
		return NSImageRepLoadStatusWillNeedAllData;
	}
	{
		NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:_incremental];

		if (rep == nil) {
			/* THE ONLY FAILURE THIS DECODER CAN REPORT, because it decodes whole: a buffer that is
			 * recognisably PNG or JPEG and does not decode is invalid, and it cannot tell a truncated
			 * file from a corrupt one. Stated rather than guessed. */
			return NSImageRepLoadStatusInvalidData;
		}
		[self cg_adoptRep:rep];
		return NSImageRepLoadStatusCompleted;
	}
}

/* THE FOCUSED-RECT READ. `CGBitmapContextCreateImage` is the whole trick: the new rep carries the
 * context's own layout, so nothing here has to assume a channel order. The rect is in the CONTEXT's
 * coordinates (y up) and a CGImage's rows run y DOWN, so a crop converts the y explicitly — the one
 * place in this class a y has to be turned round, and it is stated because getting it wrong would put a
 * cropped region at the mirrored height and look plausible. */
- (nullable instancetype)initWithFocusedViewRect:(NSRect)rect
{
	NSGraphicsContext *g = [NSGraphicsContext currentContext];
	CGContextRef c = g != nil ? [g CGContext] : NULL;
	CGImageRef whole, use;

	if (c == NULL || CGBitmapContextGetData(c) == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -initWithFocusedViewRect: reads pixels from the CURRENT "
				"BITMAP context, and there is %s\n",
			c == NULL ? "no current context" : "a current context that is not bitmap-backed");
		[self release];
		return nil;
	}
	whole = CGBitmapContextCreateImage(c);
	if (whole == NULL) {
		[self release];
		return nil;
	}
	use = whole;
	if (rect.size.width > 0.0 && rect.size.height > 0.0) {
		CGRect cr = CGRectMake(NSMinX(rect),
				       (CGFloat)CGBitmapContextGetHeight(c) - NSMaxY(rect),
				       rect.size.width, rect.size.height);

		use = CGImageCreateWithImageInRect(whole, cr);
		if (use == NULL) {
			CGImageRelease(whole);
			[self release];
			return nil;
		}
	}
	self = [self initWithCGImage:use];
	if (use != whole) {
		CGImageRelease(use);
	}
	CGImageRelease(whole);
	return self;
}

/* THE PLURAL DECODE: ONE IMAGE, IN AN ARRAY. Both decoders in this tree produce a single image, and an
 * empty array for a good PNG would be the wrong lie — the array is the shape of the door, not a claim
 * that the format is multi-frame. */
+ (nullable NSArray *)imageRepsWithData:(NSData *)data
{
	NSBitmapImageRep *rep = [self imageRepWithData:data];

	if (rep == nil) {
		return nil;
	}
	return [NSArray arrayWithObject:rep];
}

/* ---- THE ENCODER DOORS, WHICH REFUSE BY NAME ------------------------------------------------- */

/* THE REFUSAL IS ONE MESSAGE IN ONE PLACE, because four doors say the same measured thing and four
 * copies of a reason is four chances for them to disagree about it. **AND WHAT IT SAYS HAS CHANGED: THE ENCODER
 * EXISTS NOW.** Core Graphics grew `CGImageDestination` (libagora-drawing) and this build writes PNG through it, so
 * the refusals that remain are about the TYPES rather than about having nothing to encode with. */
static void fn_refuseEncoder(const char *which, const char *because)
{
	fprintf(stderr, "APPKIT-REFUSE: %s: %s\n", which, because);
}

/* **ONE IMAGE, ASKED OF CORE GRAPHICS RATHER THAN WRITTEN HERE.** The rep already has a `CGImage` — its own, or one
 * built over its buffer — and `CGImageDestination` is the door that turns one into bytes, so this method has no
 * pixel code and no second opinion about what PNG is. The destination is created over a MUTABLE DATA, one image is
 * added, and `Finalize` is the write; the data is the rep's answer. */
static NSData *fn_png_data_for_image(CGImageRef image)
{
	CFMutableDataRef data;
	CGImageDestinationRef destination;
	NSData *answer = nil;

	if (image == NULL) {
		return nil;
	}
	data = CFDataCreateMutable(kCFAllocatorDefault, 0);
	if (data == NULL) {
		return nil;
	}
	destination = CGImageDestinationCreateWithData(data, CFSTR("public.png"), 1, NULL);
	if (destination != NULL) {
		CGImageDestinationAddImage(destination, image, NULL);
		if (CGImageDestinationFinalize(destination)) {
			/* THE DATA IS THE ANSWER: +1 here, and the bridging cast costs no reference. */
			answer = (NSData *)data;
		} else {
			CFRelease(data);
		}
		CFRelease(destination);
	} else {
		CFRelease(data);
	}
	return answer;
}

- (nullable NSData *)representationUsingType:(NSBitmapImageFileType)storageType
				  properties:(nullable NSDictionary *)properties
{
	/* **THE PROPERTIES ARE REFUSED RATHER THAN IGNORED**, which is this tree's standing rule and the reason the
	 * refusal is a message: a caller that asked for an interlaced PNG would get a plain one without being told. */
	if (storageType != NSPNGFileType) {
		fn_refuseEncoder("-representationUsingType:properties:",
				 "this build writes NSPNGFileType only, through Core Graphics' CGImageDestination");
		return nil;
	}
	if (properties != nil && [properties count] > 0) {
		fn_refuseEncoder("-representationUsingType:properties:",
				 "the encoder does not read the properties dictionary yet, and ignoring it would "
				 "write an image the caller did not ask for");
		return nil;
	}
	return fn_png_data_for_image([self CGImage]);
}

+ (nullable NSData *)representationOfImageRepsInArray:(NSArray *)imageReps
					   usingType:(NSBitmapImageFileType)storageType
					  properties:(nullable NSDictionary *)properties
{
	/* **ONE REP, BECAUSE PNG CARRIES ONE IMAGE.** Apple's door exists for the formats that carry several — TIFF and
	 * PDF — and answering a one-image question for a two-image array would drop a picture without saying so. */
	if (imageReps == nil || [imageReps count] != 1) {
		fn_refuseEncoder("+representationOfImageRepsInArray:usingType:properties:",
				 "a PNG carries ONE image, and this build will not drop the rest of an array");
		return nil;
	}
	return [[imageReps objectAtIndex:0] representationUsingType:storageType properties:properties];
}

+ (nullable NSData *)TIFFRepresentationOfImageRepsInArray:(NSArray *)array
{
	(void)array;
	fn_refuseEncoder("+TIFFRepresentationOfImageRepsInArray:",
			 "this build writes PNG only, and TIFF is not it");
	return nil;
}

+ (nullable NSData *)TIFFRepresentationOfImageRepsInArray:(NSArray *)array
					 usingCompression:(NSTIFFCompression)comp
						   factor:(float)factor
{
	(void)array;
	(void)comp;
	(void)factor;
	fn_refuseEncoder("+TIFFRepresentationOfImageRepsInArray:usingCompression:factor:",
			 "this build writes PNG only, and TIFF is not it");
	return nil;
}

/* ---- THE PLANES, THE SIZE AND THE PIXEL LAYOUT ----------------------------------------------- */

- (NSInteger)numberOfPlanes
{
	/* ONE, AND THAT IS A FACT ABOUT THIS CLASS RATHER THAN A DEFAULT: the initialiser REFUSES
	 * `isPlanar:YES` because this representation holds a single plane of pixels (see its own note), so no
	 * rep in this tree can have a second one. */
	return 1;
}

- (NSInteger)bytesPerPlane
{
	/* THE PLANE IS THE IMAGE, so its size is the row stride times the height — and WHICH STRIDE depends on
	 * which half of the class the rep is: one that owns its bytes knows its own, while an image-backed one
	 * takes the image's, which may differ from anything this class would have chosen. A rep with no pixels
	 * at all answers 0, which is the truth rather than a guess. */
	if (_bits != NULL) {
		return _bytesPerRow * _pixelsHigh;
	}
	if (_cgImage != NULL) {
		return (NSInteger)CGImageGetBytesPerRow(_cgImage) * (NSInteger)CGImageGetHeight(_cgImage);
	}
	return 0;
}

- (NSBitmapFormat)bitmapFormat
{
	unsigned int flags = 0;
	CGImageAlphaInfo alpha;

	/* **DERIVED, NOT STORED, AND THE DERIVATION IS THE WHOLE POINT: the three flags describe the ALPHA
	 * position, whether the alpha is premultiplied, and whether the samples are floats.
	 *
	 * THE FIRST TWO ARE READABLE OFF THE LAYOUT. A rep that OWNS its bytes is built alpha-LAST and
	 * premultiplied (`-CGImage` says why the byte order is stated out loud, and the same line fixes the
	 * alpha position), so neither flag is set. An IMAGE-BACKED rep knows its own alpha info and reports it
	 * through the image, which is why that half reads from `CGImageGetAlphaInfo` rather than from an ivar:
	 * the pixels are the image's, so the layout is the image's too.
	 *
	 * AND THE THIRD IS NEVER SET, WHICH IS A FACT ABOUT THIS TIER RATHER THAN AN OMISSION: the flag says a
	 * rep's samples are floats, and this library's CoreGraphics has no floating-point bitmap layout, so no
	 * representation here can have one. A rep built from someone else's float image could not be constructed
	 * at all. */
	if (_cgImage != NULL) {
		alpha = CGImageGetAlphaInfo(_cgImage);
	} else {
		alpha = _hasAlpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNone;
	}
	switch (alpha) {
	case kCGImageAlphaFirst:
		flags = NSAlphaFirstBitmapFormat | NSAlphaNonpremultipliedBitmapFormat;
		break;
	case kCGImageAlphaPremultipliedFirst:
		flags = NSAlphaFirstBitmapFormat;
		break;
	case kCGImageAlphaLast:
		flags = NSAlphaNonpremultipliedBitmapFormat;
		break;
	default:
		/* alpha last and premultiplied, or no alpha at all: no flags, which is this class's own layout. */
		flags = 0;
		break;
	}
	return (NSBitmapFormat)flags;
}

/* ---- AND THE THREE DOORS INTO SOFTWARE THIS TIER HAS NOT GOT ---------------------------------- */

- (nullable NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:(id)targetSpace
						     renderingIntent:(NSColorRenderingIntent)renderingIntent
{
	(void)targetSpace;
	(void)renderingIntent;
	/* **ONE THING IS MISSING NOW, AND IT IS THE HARD ONE.** `NSColorSpace` ARRIVED (this class answers `-colorSpace`
	 * with it), so the target's name is readable — but nothing in this tree converts PIXELS between two spaces: the
	 * drawing composites device numbers and the decoders produce the space they were told. So the refusal is narrowed
	 * to the conversion, which is the truth; the retagging door below, which changes no pixel, is real. */
	fprintf(stderr, "APPKIT-REFUSE: -bitmapImageRepByConvertingToColorSpace:renderingIntent: needs a "
			"COLOUR-CONVERTING path; this rep's space is a name and nothing here converts pixels between "
			"two of them (retagging, which changes no pixel, is `-bitmapImageRepByRetaggingWithColorSpace:`)\n");
	return nil;
}

- (nullable NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:(id)newSpace
{
	NSString *name;
	NSBitmapImageRep *retagged;

	/* **RETAGGING CHANGES NO PIXEL, WHICH IS WHY IT IS A REAL DOOR NOW.** It says "these bytes are in a different
	 * space": the copy is the same pixels with a different NAME, so the only thing this needs is the new space's name —
	 * and `NSColorSpace` ships now, so the object handed over can supply one. The refusal this replaces said the class
	 * did not exist and was true when it was written; the header's note beside `-colorSpace` records the correction.
	 *
	 * A NAME THE NEW SPACE CANNOT SUPPLY IS A REFUSAL, not a silent no-op: `-localizedName` answers nil for a space the
	 * engine has no name for, and a copy retagged to nothing would look like success. */
	if (newSpace == nil || ![newSpace isKindOfClass:[NSColorSpace class]]) {
		fprintf(stderr, "APPKIT-REFUSE: -bitmapImageRepByRetaggingWithColorSpace: takes an NSColorSpace; this "
				"rep's space is a NAME and there is nothing to retag to\n");
		return nil;
	}
	name = [(NSColorSpace *)newSpace localizedName];
	if (name == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -bitmapImageRepByRetaggingWithColorSpace: needs a space with a NAME; "
				"the one given has none (the engine has no name for a device space), so the copy would be "
				"retagged to nothing\n");
		return nil;
	}
	retagged = [[NSBitmapImageRep alloc] initWithCGImage:[self CGImage]];
	if (retagged != nil) {
		[retagged setColorSpaceName:name];
		[retagged setSize:[self size]];
	}
	return [retagged autorelease];
}

- (nullable instancetype)initWithCIImage:(id)ciImage
{
	(void)ciImage;
	/* NO CORE IMAGE IN THIS TREE, so there is no CIImage to decode and nil is the honest answer rather than
	 * an empty rep that would report a size of zero by zero. */
	fprintf(stderr, "APPKIT-REFUSE: -initWithCIImage: needs Core Image, which this tree has not got\n");
	return nil;
}

@end
