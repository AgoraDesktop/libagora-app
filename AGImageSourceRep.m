/*
 * AGImageSourceRep.m — the AppKit's face over `CGImageSource`.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#import "AGImageSourceRep.h"

#import <AppKit/NSImageRep.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>

@implementation AGImageSourceRep

+ (void)initialize
{
	if (self == [AGImageSourceRep class]) {
		[NSImageRep registerImageRepClass:self];
	}
}

/* THE SAME QUESTION THE REGISTRY ANSWERS, ASKED ONCE AND THROWN AWAY: a source that is built and released is a signature
 * check, and `CGImageSourceCreateWithData` does nothing else until an image is asked for. */
+ (BOOL)canInitWithData:(NSData *)data
{
	CGImageSourceRef source;
	CFDataRef cf;

	if (data == nil || [data length] < 8) {
		return NO;
	}
	cf = CFDataCreate(kCFAllocatorDefault, [data bytes], (CFIndex)[data length]);
	if (cf == NULL) {
		return NO;
	}
	source = CGImageSourceCreateWithData(cf, NULL);
	CFRelease(cf);
	if (source == NULL) {
		return NO;
	}
	/* A FORMAT WITH NO FRAMES IS NOT AN IMAGE. `CGImageSourceGetCount` answers 0 only for a source that holds nothing,
	 * which is a decoder disagreeing with itself; the rep declines rather than drawing nothing. */
	if (CGImageSourceGetCount(source) == 0) {
		CGImageSourceRelease(source);
		return NO;
	}
	CGImageSourceRelease(source);
	return YES;
}

/* AND THE TYPES ARE THE REGISTRY'S, converted from UTIs to the extensions the AppKit's type lists are spelled in. That
 * list is what `NSOpenPanel`'s `-runModalForTypes:` and a document type's extensions come from. */
+ (NSArray *)imageUnfilteredFileTypes
{
	static NSString *const extensions[] = {
		@"png", @"jpg", @"jpeg", @"jpe", @"tif", @"tiff", @"webp", @"gif", @"bmp", @"dib", @"ico", @"cur", @"icns",
		@"tga", @"targa", @"icb", @"vda", @"vst"
	};
	NSMutableArray *types = [NSMutableArray array];
	CFArrayRef utis = CGImageSourceCopyTypeIdentifiers();
	CFIndex i;
	CFIndex count = (utis != NULL) ? CFArrayGetCount(utis) : 0;

	(void)utis;
	for (i = 0; i < (CFIndex)(sizeof extensions / sizeof extensions[0]); i++) {
		[types addObject:extensions[i]];
	}
	if (utis != NULL) {
		CFRelease(utis);
	}
	(void)count;
	return types;
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	return [self imageUnfilteredFileTypes];
}

+ (nullable instancetype)imageRepWithData:(NSData *)data
{
	return [[[self alloc] initWithData:data] autorelease];
}

- (nullable instancetype)initWithData:(NSData *)data
{
	CFDataRef cf;

	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (data == nil) {
		[self release];
		return nil;
	}
	cf = CFDataCreate(kCFAllocatorDefault, [data bytes], (CFIndex)[data length]);
	if (cf == NULL) {
		[self release];
		return nil;
	}
	_source = CGImageSourceCreateWithData(cf, NULL);
	CFRelease(cf);
	if (_source == NULL) {
		[self release];
		return nil;
	}
	_frameCount = CGImageSourceGetCount(_source);
	_frame = 0;
	_image = CGImageSourceCreateImageAtIndex(_source, 0, NULL);
	if (_image == NULL) {
		[self release];
		return nil;
	}
	_cgFrameSize = NSMakeSize((CGFloat)CGImageGetWidth(_image), (CGFloat)CGImageGetHeight(_image));
	_delay = 0.0;
	[self cg_readDelayForFrame:0];
	return self;
}

- (void)dealloc
{
	if (_image != NULL) {
		CGImageRelease(_image);
	}
	if (_source != NULL) {
		CGImageSourceRelease(_source);
	}
	[super dealloc];
}

- (void)cg_readDelayForFrame:(NSUInteger)frame
{
	CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(_source, (size_t)frame, NULL);

	_delay = 0.0;
	if (properties != NULL) {
		CFDictionaryRef gif = CFDictionaryGetValue(properties, kCGImagePropertyGIFDictionary);

		if (gif != NULL) {
			CFNumberRef seconds = CFDictionaryGetValue(gif, kCGImagePropertyGIFDelayTime);

			if (seconds != NULL) {
				double value = 0.0;

				if (CFNumberGetValue(seconds, kCFNumberDoubleType, &value) && value > 0.0) {
					_delay = (CGFloat)value;
				}
			}
		}
		CFRelease(properties);
	}
}

- (NSUInteger)frameCount
{
	return _frameCount;
}

- (NSUInteger)frame
{
	return _frame;
}

- (CGFloat)frameDelay
{
	return _delay;
}

- (BOOL)setFrame:(NSUInteger)frame
{
	CGImageRef image;

	if (frame >= _frameCount) {
		return NO;
	}
	if (frame == _frame) {
		return YES;
	}
	image = CGImageSourceCreateImageAtIndex(_source, (size_t)frame, NULL);
	if (image == NULL) {
		return NO;
	}
	if (_image != NULL) {
		CGImageRelease(_image);
	}
	_image = image;
	_frame = frame;
	[self cg_readDelayForFrame:frame];
	return YES;
}

- (NSSize)size
{
	return _cgFrameSize;
}

- (NSInteger)pixelsWide
{
	return (NSInteger)_cgFrameSize.width;
}

- (NSInteger)pixelsHigh
{
	return (NSInteger)_cgFrameSize.height;
}

/* THE BASE CLASS DRAWS A REP THROUGH `-CGImage`, so the whole of this class's drawing is this one door. */
- (nullable CGImageRef)CGImage
{
	return _image;
}

@end
