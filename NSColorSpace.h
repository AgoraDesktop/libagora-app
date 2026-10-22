/*
 * NSColorSpace.h — A COLOUR SPACE: the model a colour's numbers are numbers IN.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE THIRD THING A COLOUR IS, BESIDE ITS NUMBERS AND ITS ALPHA.** `NSColor`'s getters answer components in a space,
 * and `-colorUsingColorSpace:` converts between them; both need this object to name WHICH space, which is why the class
 * arrived after the colours that use it. The values are CoreGraphics' — this class wraps a `CGColorSpaceRef` and answers
 * what the engine says about it rather than keeping a second table of models and component counts, because a table that
 * disagreed with the engine would be a second truth about the same space.
 *
 * **THE NAMED SPACES ARE NINE, AND EACH IS A CACHED SINGLETON.** Seven are the engine's own named spaces
 * (`kCGColorSpaceGenericRGB`, `kCGColorSpaceSRGB`, `kCGColorSpaceAdobeRGB1998`, the two grays and the two CMYKs) and two
 * are the DEVICE spaces, which are per-process rather than per-profile. `+availableColorSpacesWithModel:` answers the ones
 * whose engine model matches, which is the era's own definition of that door.
 *
 * **THE TWO PROFILE DOORS REFUSE BY NAME.** An `NSColorSpace` can be made from an ICC profile or a ColorSync profile in
 * Apple's class; this tier has neither an ICC parser nor ColorSync, so the initialisers answer nil and say which
 * subsystem they want. That is a stated gap rather than a silent nil: a caller porting a profile-based colour workflow
 * should learn it at the call.
 *
 * **AND THE MODEL VOCABULARY IS APPLE'S, INCLUDING ITS NEGATIVE UNKNOWN.** `NSUnknownColorSpaceModel` is -1, which is
 * also the engine's own `kCGColorSpaceModelUnknown` — the two agree by construction because this tier's models ARE the
 * engine's, translated case for case.
 */
#ifndef APPKIT_NSCOLORSPACE_H
#define APPKIT_NSCOLORSPACE_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSString.h>
#import <CoreGraphics/CGColorSpace.h>

NS_ASSUME_NONNULL_BEGIN

@class NSData;
@class NSArray;

/* **THE MODEL, IN APPLE'S ORDER AND WITH APPLE'S NEGATIVE UNKNOWN.** The values are the engine's own `CGColorSpaceModel`
 * numbers, which is not a coincidence but the mapping this class is: a space's model is `CGColorSpaceGetModel` answered. */
typedef NSInteger NSColorSpaceModel;
enum {
	NSUnknownColorSpaceModel = -1,
	NSGrayColorSpaceModel = 0,
	NSRGBColorSpaceModel = 1,
	NSCMYKColorSpaceModel = 2,
	NSLabColorSpaceModel = 3,
	NSDeviceNColorSpaceModel = 4,
	NSIndexedColorSpaceModel = 5,
	NSPatternColorSpaceModel = 6
};

@interface NSColorSpace : NSObject
{
	/* THE ENGINE'S OBJECT, RETAINED HERE AND HANDED BACK BY `-CGColorSpace`. */
	CGColorSpaceRef _cgColorSpace;
}

/* FROM THE ENGINE'S OBJECT, which is the one initialiser that can wrap anything — including a space this class has no
 * named door for. Retained rather than copied: a `CGColorSpaceRef` is immutable in every way a caller can observe. */
- (nullable instancetype)initWithCGColorSpace:(CGColorSpaceRef)cgColorSpace;

/* THE TWO PROFILE DOORS, DECLARED AND REFUSED. See this header's note. */
- (nullable instancetype)initWithICCProfileData:(nullable NSData *)iccData;
- (nullable instancetype)initWithColorSyncProfile:(nullable void *)prof;

/* THE NINE NAMED SPACES. Seven are the engine's named spaces and two are the device ones. Each answers the SAME object
 * every time, because a space is a value and two objects for one value is how a comparison comes to be false. */
+ (NSColorSpace *)genericRGBColorSpace;
+ (NSColorSpace *)genericGrayColorSpace;
+ (NSColorSpace *)genericCMYKColorSpace;
+ (NSColorSpace *)deviceRGBColorSpace;
+ (NSColorSpace *)deviceGrayColorSpace;
+ (NSColorSpace *)deviceCMYKColorSpace;
+ (NSColorSpace *)sRGBColorSpace;
+ (NSColorSpace *)adobeRGB1998ColorSpace;
+ (NSColorSpace *)genericGamma22GrayColorSpace;

/* **THE ONES WHOSE MODEL IS THE ONE NAMED**, which is Apple's definition: the device and named spaces whose engine model
 * matches, in the order this class declares them. An unknown model answers an empty array rather than nil. */
+ (NSArray *)availableColorSpacesWithModel:(NSColorSpaceModel)model;

/* THE ENGINE'S OBJECT, BORROWED. A caller that needs `CGColorCreate` hands this straight to it. */
- (CGColorSpaceRef)CGColorSpace;

/* AND WHAT THE ENGINE SAYS ABOUT IT. The component count EXCLUDES alpha, which is what AppKit's door means and what
 * `CGColorGetNumberOfComponents` (which counts it) does not — the translation is here so a caller does not have to know. */
- (NSInteger)numberOfColorComponents;
- (NSColorSpaceModel)colorSpaceModel;

/* THE NAME THE ENGINE KNOWS IT BY, or a description of the model when the space is unnamed (the device spaces). */
- (nullable NSString *)localizedName;

/* THE TWO PROFILE GETTERS, ANSWERING nil WITH A REASON. See the header's note. */
- (nullable NSData *)ICCProfileData;
- (nullable void *)colorSyncProfile;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLORSPACE_H */
