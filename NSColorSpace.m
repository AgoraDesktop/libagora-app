/*
 * NSColorSpace — the model a colour's numbers are numbers IN.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The class is thin on purpose: every fact it answers is the `CGColorSpace`'s own, and the only state here is that
 * object. The nine named spaces are made on first ask and held for the process — one object per space, because a space is
 * a value and two objects for one value is how a comparison comes to be false. The two profile doors refuse by name: an
 * ICC parser and ColorSync are subsystems this tier has not got.
 */
#import "NSColorSpace.h"
#import "AppKitRefusal.h"

#import <Foundation/NSData.h>
#import <Foundation/NSArray.h>

#include <string.h>

/* THE NINE, MADE ONCE. A NULL slot means "not made yet"; a space this process cannot make stays NULL and its door answers
 * nil, which is the honest answer for a named space the engine refused. */
static NSColorSpace *sNamedSpaces[9];

static NSColorSpace *fn_named_space(NSUInteger slot, CGColorSpaceRef space)
{
	if (sNamedSpaces[slot] == nil && space != NULL) {
		sNamedSpaces[slot] = [[NSColorSpace alloc] initWithCGColorSpace:space];
		CGColorSpaceRelease(space);
	}
	return sNamedSpaces[slot];
}

/* THE MODEL, TRANSLATED CASE FOR CASE. The engine's enum and AppKit's are the same numbers, which is why this is a cast
 * with a guard rather than a table: an engine model this class has no case for is NSUnknownColorSpaceModel. */
static NSColorSpaceModel fn_model(CGColorSpaceModel model)
{
	switch (model) {
	case kCGColorSpaceModelMonochrome: return NSGrayColorSpaceModel;
	case kCGColorSpaceModelRGB: return NSRGBColorSpaceModel;
	case kCGColorSpaceModelCMYK: return NSCMYKColorSpaceModel;
	case kCGColorSpaceModelLab: return NSLabColorSpaceModel;
	case kCGColorSpaceModelDeviceN: return NSDeviceNColorSpaceModel;
	case kCGColorSpaceModelIndexed: return NSIndexedColorSpaceModel;
	case kCGColorSpaceModelPattern: return NSPatternColorSpaceModel;
	default: return NSUnknownColorSpaceModel;
	}
}

@implementation NSColorSpace

- (instancetype)initWithCGColorSpace:(CGColorSpaceRef)cgColorSpace
{
	self = [super init];
	if (self != nil) {
		if (cgColorSpace == NULL) {
			[self release];
			return nil;
		}
		_cgColorSpace = CGColorSpaceRetain(cgColorSpace);
	}
	return self;
}

- (void)dealloc
{
	if (_cgColorSpace != NULL) {
		CGColorSpaceRelease(_cgColorSpace);
	}
	[super dealloc];
}

/* **THE PROFILE DOORS REFUSE BY NAME.** An ICC profile is a parsed document and ColorSync is a colour-management system;
 * neither is here, so the initialiser answers nil and says what it wants — the same vocabulary every other gap in this
 * tier uses. */
- (instancetype)initWithICCProfileData:(NSData *)iccData
{
	(void)iccData;
	fn_refuse_window("-initWithICCProfileData:",
			 "an ICC profile parser; this tier's spaces are the engine's named and device spaces");
	[self release];
	return nil;
}

- (instancetype)initWithColorSyncProfile:(void *)prof
{
	(void)prof;
	fn_refuse_window("-initWithColorSyncProfile:",
			 "ColorSync; this tier's spaces are the engine's named and device spaces");
	[self release];
	return nil;
}

/* ---- THE NINE NAMED SPACES ------------------------------------------------------------------------ */

+ (NSColorSpace *)genericRGBColorSpace
{
	return fn_named_space(0, CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB));
}

+ (NSColorSpace *)genericGrayColorSpace
{
	return fn_named_space(1, CGColorSpaceCreateWithName(kCGColorSpaceGenericGray));
}

+ (NSColorSpace *)genericCMYKColorSpace
{
	return fn_named_space(2, CGColorSpaceCreateWithName(kCGColorSpaceGenericCMYK));
}

+ (NSColorSpace *)deviceRGBColorSpace
{
	return fn_named_space(3, CGColorSpaceCreateDeviceRGB());
}

+ (NSColorSpace *)deviceGrayColorSpace
{
	return fn_named_space(4, CGColorSpaceCreateDeviceGray());
}

+ (NSColorSpace *)deviceCMYKColorSpace
{
	return fn_named_space(5, CGColorSpaceCreateDeviceCMYK());
}

+ (NSColorSpace *)sRGBColorSpace
{
	return fn_named_space(6, CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
}

+ (NSColorSpace *)adobeRGB1998ColorSpace
{
	return fn_named_space(7, CGColorSpaceCreateWithName(kCGColorSpaceAdobeRGB1998));
}

+ (NSColorSpace *)genericGamma22GrayColorSpace
{
	return fn_named_space(8, CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2));
}

/* **THE LIST IS THE CLASS'S OWN NINE, FILTERED BY MODEL.** Apple's door answers the spaces it knows whose model matches;
 * iterating this class's own doors is what keeps the list and the doors from disagreeing about which spaces exist. */
+ (NSArray *)availableColorSpacesWithModel:(NSColorSpaceModel)model
{
	NSColorSpace *all[9];
	NSMutableArray *out = [NSMutableArray array];
	NSUInteger i;

	all[0] = [self genericRGBColorSpace];
	all[1] = [self genericGrayColorSpace];
	all[2] = [self genericCMYKColorSpace];
	all[3] = [self deviceRGBColorSpace];
	all[4] = [self deviceGrayColorSpace];
	all[5] = [self deviceCMYKColorSpace];
	all[6] = [self sRGBColorSpace];
	all[7] = [self adobeRGB1998ColorSpace];
	all[8] = [self genericGamma22GrayColorSpace];
	for (i = 0; i < 9; i++) {
		if (all[i] != nil && [all[i] colorSpaceModel] == model && ![out containsObject:all[i]]) {
			[out addObject:all[i]];
		}
	}
	return out;
}

/* ---- WHAT THE ENGINE SAYS ------------------------------------------------------------------------- */

- (CGColorSpaceRef)CGColorSpace
{
	return _cgColorSpace;
}

/* **THE COUNT EXCLUDES ALPHA.** AppKit's `-numberOfColorComponents` is the number of colour channels — 1 for gray, 3 for
 * RGB, 4 for CMYK — and CoreGraphics counts alpha in `CGColorSpaceGetNumberOfComponents` only for spaces that carry it.
 * The engine's answer is passed through unchanged and the subtraction that AppKit means is done nowhere, because the
 * engine's count IS the colour channels for a colour space (alpha is a property of the COLOUR, not the space). */
- (NSInteger)numberOfColorComponents
{
	return (_cgColorSpace != NULL) ? (NSInteger)CGColorSpaceGetNumberOfComponents(_cgColorSpace) : 0;
}

- (NSColorSpaceModel)colorSpaceModel
{
	return (_cgColorSpace != NULL) ? fn_model(CGColorSpaceGetModel(_cgColorSpace)) : NSUnknownColorSpaceModel;
}

/* **THE NAME IS THE ENGINE'S WHEN IT HAS ONE.** A device space has no name in CoreGraphics (it is made per process), so
 * the answer falls back to the model's own name rather than to nil: a caller asking "what is this space" learns something
 * either way, which is the difference between an unnamed space and an unknown one. */
- (NSString *)localizedName
{
	CFStringRef name = (_cgColorSpace != NULL) ? CGColorSpaceCopyName(_cgColorSpace) : NULL;

	if (name != NULL) {
		NSString *answer = [[(NSString *)name copy] autorelease];

		CFRelease(name);
		return answer;
	}
	switch ([self colorSpaceModel]) {
	case NSGrayColorSpaceModel: return @"Gray";
	case NSRGBColorSpaceModel: return @"RGB";
	case NSCMYKColorSpaceModel: return @"CMYK";
	case NSLabColorSpaceModel: return @"Lab";
	default: return @"Unknown";
	}
}

- (NSData *)ICCProfileData
{
	fn_refuse_window("-ICCProfileData", "an ICC profile parser; this tier's spaces are the engine's, not profiles");
	return nil;
}

- (void *)colorSyncProfile
{
	fn_refuse_window("-colorSyncProfile", "ColorSync; this tier has no colour-management system");
	return NULL;
}

@end
