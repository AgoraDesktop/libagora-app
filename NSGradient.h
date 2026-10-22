/*
 * NSGradient.h — A RAMP BETWEEN COLOURS: the stops, the interpolation, and the four drawing doors.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A GRADIENT IS STOPS IN A COLOUR SPACE, AND EVERY OTHER DOOR IS A CONSEQUENCE.** The stops are colours and locations
 * along 0..1; the space decides what "half way between" means, which is why it is a constructor argument rather than a
 * property — Apple's designated initialiser takes it, and the other three default to the device RGB space. The ENGINE holds
 * the ramp (`CGGradientCreateWithColors`), so drawing is one call per door and this class never interpolates for the
 * pixels; `-interpolatedColorAtLocation:` is the ONE place this file does arithmetic, because a caller asking "what colour
 * is 40% along" wants a colour object rather than ink.
 *
 * **THE FOUR DRAWING DOORS ARE TWO SHAPES AND TWO PLACEMENTS.** A gradient runs between two points (linear) or between two
 * circles (radial); it can be placed by naming those, or by naming a RECTANGLE and an angle — which is the same linear ramp
 * with the points computed across the rect's diagonal — or by naming a rectangle and a CENTRE for a radial one. The
 * `NSGradientDrawingOptions` bits say whether the ramp extends past its ends or stops there, which is the engine's own
 * behaviour and is passed through unchanged.
 *
 * **AND THE BEZIER-PATH DOORS CLIP TO THEIR PATH.** Apple's pair draws the ramp inside a shape, which is the clip the path
 * makes; the placement is the path's bounds. That is stated because a caller expecting the ramp to follow the shape's
 * CURVE would be surprised by a bounding-box ramp — which is what Apple's does too.
 */
#ifndef APPKIT_NSGRADIENT_H
#define APPKIT_NSGRADIENT_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
/* FOR `CGGradientRef` IN THE IVAR. The header names the type it stores, and a forward typedef would be the same
 * dependency one indirection further out. */
#import <CoreGraphics/CGGradient.h>

NS_ASSUME_NONNULL_BEGIN

@class NSColor;
@class NSColorSpace;
@class NSBezierPath;
@class NSArray;

/* **WHETHER THE RAMP RUNS PAST ITS ENDS.** The first point's colour before the start (or the last one's after the end) is
 * painted only when the matching bit is set; without it the region beyond the ramp is untouched. */
typedef NSUInteger NSGradientDrawingOptions;
enum {
	NSGradientDrawsBeforeStartingLocation = (1 << 0),
	NSGradientDrawsAfterEndingLocation = (1 << 1)
};

@interface NSGradient : NSObject <NSCopying>
{
	NSColorSpace *_colorSpace;	/* RETAINED: the space "between" is measured in */
	NSArray *_colors;		/* RETAINED: the stops, in order */
	CGFloat *_locations;		/* OWNED: one per stop, ascending, 0..1 */
	NSInteger _numberOfColorStops;
	CGGradientRef _gradient;	/* OWNED; built at construction from the stops */
}

/* **THE FOUR WAYS IN, AND ALL OF THEM END AT THE SAME THREE FACTS.** Starting/ending colour is the two-stop case; the
 * colours alone are evenly spaced; the colours plus locations is the general one; and the designated initialiser adds the
 * space. Apple's varargs door is `-initWithColorsAndLocations:` — a colour, a location, and so on, nil-terminated. */
- (nullable instancetype)initWithStartingColor:(NSColor *)startingColor endingColor:(NSColor *)endingColor;
- (nullable instancetype)initWithColors:(NSArray *)colorArray;
- (nullable instancetype)initWithColorsAndLocations:(NSColor *)firstColor, ... NS_REQUIRES_NIL_TERMINATION;
- (nullable instancetype)initWithColors:(NSArray *)colorArray
			   atLocations:(const CGFloat *)locations
			    colorSpace:(NSColorSpace *)colorSpace;

/* THE STOPS, READ BACK: how many, and one stop's colour and place. An index past the end answers nil rather than raising,
 * which is this tier's rule for an ordinary mistake. */
- (NSInteger)numberOfColorStops;
- (void)getColor:(NSColor * _Nullable * _Nullable)color location:(nullable CGFloat *)location atIndex:(NSInteger)index;

/* **AND THE COLOUR AT A POINT ALONG THE RAMP**, which is the one computation this class does rather than the engine: a
 * location of 0 is the first stop, 1 the last, and a value between them is linearly interpolated in the gradient's space.
 * A location outside 0..1 is CLAMPED — the ramp has no colour past its ends. */
- (nullable NSColor *)interpolatedColorAtLocation:(CGFloat)location;

/* THE SPACE THE INTERPOLATION HAPPENS IN. */
- (nullable NSColorSpace *)colorSpace;

/* ---- THE FOUR DRAWING DOORS, EACH ONE ENGINE CALL ------------------------------------------------ */

/* Linear between two points, and radial between two circles. */
- (void)drawFromPoint:(NSPoint)startingPoint toPoint:(NSPoint)endingPoint
	      options:(NSGradientDrawingOptions)options;
- (void)drawFromCenter:(NSPoint)startCenter radius:(CGFloat)startRadius
		toCenter:(NSPoint)endCenter radius:(CGFloat)endRadius
		 options:(NSGradientDrawingOptions)options;

/* **AND THE TWO PLACEMENTS.** An angle is degrees clockwise from the positive x axis (the era's convention, which is the
 * same one `NSAffineTransform` rotates by); the ramp spans the rectangle's extent along that direction. A relative centre
 * is (-1..1) offsets from the rectangle's middle, times half its size. */
- (void)drawInRect:(NSRect)rect angle:(CGFloat)startingAngle;
- (void)drawInRect:(NSRect)rect relativeCenterPosition:(NSPoint)relativeCenterPosition;

/* The same two inside a shape, clipped to it. */
- (void)drawInBezierPath:(NSBezierPath *)path angle:(CGFloat)startingAngle;
- (void)drawInBezierPath:(NSBezierPath *)path relativeCenterPosition:(NSPoint)relativeCenterPosition;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSGRADIENT_H */
