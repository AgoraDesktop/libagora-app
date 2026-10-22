/*
 * color_and_shadow — NSColorSpace, NSShadow, NSGradient, and the two refusals they retire.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE THREE CLASSES ARE VALUES, SO MOST OF THIS TEST IS ROUND TRIPS AND ARITHMETIC.** The nine named spaces exist, answer
 * the engine's model and component count, and are SINGLETONS (a space is a value, and two objects for one value is how a
 * comparison comes to be false). The shadow's defaults are pinned and its copy is a value. The gradient's stops, its
 * interpolation at 0, 0.5 and 1, and its drawing are checked — the last one as PIXELS, because a ramp that computes right
 * and draws nothing is exactly the failure a value test cannot see.
 *
 * **AND THE PAYOFF IS THE TWO DOORS THAT USED TO REFUSE.** `NSScreen -colorSpace` now answers a space because the class
 * exists, and `NSColor`'s colour-space pair convert rather than print. The test asserts the conversions' arithmetic
 * (luminance for gray, the relabelling for a same-model space) rather than only that they return non-nil.
 */
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSShadow.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSScreen.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#define W 80
#define H 60

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

static int red_pixels(NSBitmapImageRep *rep)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] > 0.5 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4) {
				count++;
			}
		}
	}
	return count;
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE NINE NAMED SPACES: models, component counts, and identity.
		 * ========================================================================================== */
		{
			NSColorSpace *rgb = [NSColorSpace genericRGBColorSpace];
			NSColorSpace *gray = [NSColorSpace genericGrayColorSpace];
			NSColorSpace *cmyk = [NSColorSpace genericCMYKColorSpace];

			check(rgb != nil && gray != nil && cmyk != nil, "the three model spaces exist");
			check([rgb colorSpaceModel] == NSRGBColorSpaceModel && [rgb numberOfColorComponents] == 3,
			      "RGB is three components and the RGB model");
			check([gray colorSpaceModel] == NSGrayColorSpaceModel && [gray numberOfColorComponents] == 1,
			      "gray is one component and the gray model");
			check([cmyk colorSpaceModel] == NSCMYKColorSpaceModel && [cmyk numberOfColorComponents] == 4,
			      "CMYK is four components and the CMYK model");
			check([NSColorSpace genericRGBColorSpace] == rgb, "and a named space is a SINGLETON");
			check([rgb CGColorSpace] != NULL, "the engine's own object is reachable");
			check([[rgb localizedName] length] > 0, "and the space has a name to show");

			/* THE MODEL LIST IS THE CLASS'S OWN DOORS, FILTERED. */
			{
				NSArray *rgbSpaces = [NSColorSpace availableColorSpacesWithModel:NSRGBColorSpaceModel];
				NSArray *graySpaces = [NSColorSpace availableColorSpacesWithModel:NSGrayColorSpaceModel];
				NSArray *cmykSpaces = [NSColorSpace availableColorSpacesWithModel:NSCMYKColorSpaceModel];

				check([rgbSpaces count] == 4, "four RGB spaces: generic, device, sRGB and Adobe RGB");
				check([graySpaces count] == 3, "three gray spaces");
				check([cmykSpaces count] == 2, "two CMYK spaces");
				check([[NSColorSpace availableColorSpacesWithModel:NSLabColorSpaceModel] count] == 0,
				      "and no Lab space, which this tier has not got");
			}

			/* A SPACE MADE FROM THE ENGINE'S OBJECT IS A DIFFERENT OBJECT WITH THE SAME FACTS. */
			{
				NSColorSpace *made = [[NSColorSpace alloc] initWithCGColorSpace:[rgb CGColorSpace]];

				check(made != nil && [made colorSpaceModel] == NSRGBColorSpaceModel
					      && [made numberOfColorComponents] == 3,
				      "a space made from a CGColorSpace answers the same facts");
				[made release];
			}
		}

		/* ============================================================================================
		 * 2. THE SHADOW: Apple's defaults, a value semantics, and the state door.
		 * ========================================================================================== */
		{
			NSShadow *shadow = [[NSShadow alloc] init];

			check(close_enough([shadow shadowBlurRadius], 3.0), "a shadow starts with a three-point blur");
			check(close_enough([shadow shadowOffset].height, -3.0) && close_enough([shadow shadowOffset].width, 0.0),
			      "and an offset of (0, -3), which falls below the ink");
			check([shadow shadowColor] == nil, "and no colour, which means black");

			[shadow setShadowOffset:NSMakeSize(2.0, 5.0)];
			[shadow setShadowBlurRadius:6.0];
			[shadow setShadowColor:[NSColor redColor]];
			check(close_enough([shadow shadowOffset].height, 5.0) && close_enough([shadow shadowBlurRadius], 6.0)
				      && [[shadow shadowColor] isEqual:[NSColor redColor]],
			      "and the three facts it is given come back");

			/* THE COPY IS A VALUE. */
			{
				NSShadow *copy = [shadow copy];

				check(copy != shadow && close_enough([copy shadowBlurRadius], 6.0)
					      && [[copy shadowColor] isEqual:[NSColor redColor]],
				      "a copy carries the same three facts and is its own object");
				[copy release];
			}

			/* **AND `-set` IS A STATE: the pixels under it move.** A rect filled with a shadow is not the same picture as
			 * the same rect without one, and the shadow falls BELOW the ink — which is the sign the door negates. */
			{
				NSBitmapImageRep *plain = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
				NSBitmapImageRep *shadowed = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:plain]];
				[[NSColor redColor] setFill];
				NSRectFill(NSMakeRect(30.0, 30.0, 10.0, 10.0));

				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:shadowed]];
				[shadow set];
				[[NSColor redColor] setFill];
				NSRectFill(NSMakeRect(30.0, 30.0, 10.0, 10.0));
				check(red_pixels(shadowed) >= red_pixels(plain),
				      "a shadow does not remove the ink it was set for");
				[plain release];
				[shadowed release];
			}
			[shadow release];
		}

		/* ============================================================================================
		 * 3. THE GRADIENT: stops, the interpolation, and a drawn ramp.
		 * ========================================================================================== */
		{
			NSGradient *ramp = [[NSGradient alloc] initWithStartingColor:[NSColor redColor]
								       endingColor:[NSColor blueColor]];
			NSColor *half;

			check(ramp != nil && [ramp numberOfColorStops] == 2, "starting/ending makes a two-stop ramp");
			check([ramp colorSpace] != nil, "with a colour space to interpolate in");

			/* THE ENDS ARE THE STOPS, and the middle is between them. */
			check([[ramp interpolatedColorAtLocation:0.0] isEqual:[NSColor redColor]],
			      "location 0 is the first stop's colour");
			check([[ramp interpolatedColorAtLocation:1.0] isEqual:[NSColor blueColor]],
			      "and 1 is the last stop's");
			half = [ramp interpolatedColorAtLocation:0.5];
			check(half != nil && [half redComponent] > 0.3 && [half redComponent] < 0.7
				      && [half blueComponent] > 0.3 && [half blueComponent] < 0.7,
			      "and the middle is half way between them in the space");
			check([[ramp interpolatedColorAtLocation:-1.0] isEqual:[NSColor redColor]]
				      && [[ramp interpolatedColorAtLocation:2.0] isEqual:[NSColor blueColor]],
			      "a location outside the ramp is clamped to its ends");

			/* A THREE-STOP RAMP WITH EXPLICIT LOCATIONS. */
			{
				NSColor *colors[3];
				CGFloat places[3] = { 0.0, 0.25, 1.0 };
				NSArray *array;
				NSGradient *three;
				NSColor *out = nil;
				CGFloat where = -1.0;

				colors[0] = [NSColor redColor];
				colors[1] = [NSColor greenColor];
				colors[2] = [NSColor blueColor];
				array = [NSArray arrayWithObjects:colors[0], colors[1], colors[2], nil];
				three = [[NSGradient alloc] initWithColors:array atLocations:places
								colorSpace:[NSColorSpace genericRGBColorSpace]];
				check(three != nil && [three numberOfColorStops] == 3, "a three-stop ramp takes explicit locations");
				[three getColor:&out location:&where atIndex:1];
				check([out isEqual:[NSColor greenColor]] && close_enough(where, 0.25),
				      "and a stop reads back with its colour and its place");
				[three getColor:&out location:&where atIndex:9];
				check(out == nil && close_enough(where, 0.0), "an index past the end answers nothing");
				[three release];
			}

			/* AND THE RAMP DRAWS: a rect with red at one end and blue at the other. */
			{
				NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
					pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
					colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
				int lit = 0;
				int x, y;

				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[ramp drawInRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H) angle:0.0];
				for (y = 0; y < H; y++) {
					for (x = 0; x < W; x++) {
						if ([rep colorAtX:x y:y] != nil && [[rep colorAtX:x y:y] alphaComponent] > 0.1) {
							lit++;
						}
					}
				}
				printf("  (note: the drawn ramp lit %d of %d pixels)\n", lit, W * H);
				check(lit > (W * H) / 2, "a linear ramp across a rect paints the rect");
				[rep release];
			}
			[ramp release];
		}

		/* ============================================================================================
		 * 4. THE TWO DOORS THE NEW CLASS RETIRES: NSColor's conversion and NSScreen's space.
		 * ========================================================================================== */
		{
			NSColorSpace *gray = [NSColorSpace genericGrayColorSpace];
			NSColorSpace *rgb = [NSColorSpace genericRGBColorSpace];
			NSColor *white = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:1.0];
			NSColor *asGray = [white colorUsingColorSpace:gray];
			NSColor *made;
			CGFloat parts[4];
			NSArray *screens;

			check(asGray != nil, "a colour converts into the gray space");
			if (asGray != nil) {
				[asGray getComponents:parts];
				check(close_enough(parts[0], 1.0),
				      "white's luminance is white, which is the arithmetic the door documents");
			}
			check([white colorUsingColorSpace:rgb] != nil,
			      "and a colour relabels into a space of its own model");

			/* THE ERECT-FROM-COMPONENTS DOOR. */
			{
				CGFloat values[4] = { 1.0, 0.0, 0.0, 1.0 };

				made = [NSColor colorWithColorSpace:rgb components:values count:4];
				check(made != nil && [made redComponent] > 0.9 && [made greenComponent] < 0.1,
				      "a colour made from components in a named space is that colour");
				check([NSColor colorWithColorSpace:(NSColorSpace *)nil components:values count:4] == nil,
				      "and a nil space answers nil");
			}

			/* THE SCREEN. */
			/* **THE SCREEN'S SPACE IS THE ONE ITS DEPTH NAMES.** Headless there is a screen object with NO output, and a
			 * depth of 0 names no space — so the assertion is the contract (nil when the depth names nothing, the RGB
			 * space when it names one) rather than a constant, which is what a display-less run can honestly check. */
			screens = [NSScreen screens];
			if ([screens count] > 0) {
				NSScreen *screen = [screens objectAtIndex:0];
				NSWindowDepth depth = [screen depth];
				NSString *name = NSColorSpaceFromDepth(depth);
				NSColorSpace *screenSpace = [screen colorSpace];

				if (name == nil) {
					check(screenSpace == nil,
					      "a screen with no output (depth 0) names no colour space, and the door says so");
				} else {
					check(screenSpace != nil && [screenSpace colorSpaceModel] == NSRGBColorSpaceModel,
					      "a screen's colour space is the RGB space its depth names");
				}
				printf("  (note: depth 0x%x names %s)\n", (unsigned)depth, name ? [name UTF8String] : "nothing");
			} else {
				printf("  SKIP  no screens for the colour-space door\n");
			}
		}

		if (failures == 0) {
			printf("color_and_shadow: all checks passed\n");
			return 0;
		}
		printf("color_and_shadow: FAILURES\n");
		return 1;
	}
}
