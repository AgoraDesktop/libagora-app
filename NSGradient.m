/*
 * NSGradient — the ramp, its stops, and the six ways to place it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The engine holds the ramp; this class holds the stops (so `-getColor:location:atIndex:` and
 * `-interpolatedColorAtLocation:` can answer WITHOUT the engine) and the space the interpolation is measured in. Drawing
 * is one `CGContext` call per door, with the placement arithmetic for the rect and path forms done here because Core
 * Graphics has no "draw this ramp across that rectangle at this angle".
 */
#import "NSGradient.h"
#import "NSColor.h"
#import "NSColorSpace.h"
#import "NSBezierPath.h"
#import "NSGraphicsContext.h"
#import "AppKitRefusal.h"

#import <CoreGraphics/CGGradient.h>
#import <CoreGraphics/CGColor.h>
#import <CoreGraphics/CGColorSpace.h>
#import <CoreGraphics/CGContext.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSValue.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define AG_DEGREES_TO_RADIANS(d) ((d) * (CGFloat)M_PI / 180.0)

/* THE COLOUR SPACE A GRADIENT DEFAULTS TO, made once. Apple's three convenience initialisers use the device RGB space, and
 * a device space is per-process, so one object is exactly right. */
static NSColorSpace *fn_default_space(void)
{
	static NSColorSpace *space = nil;

	if (space == nil) {
		space = [[NSColorSpace deviceRGBColorSpace] retain];
	}
	return space;
}

/* **ONE COLOUR'S COMPONENTS IN THE GRADIENT'S SPACE, FOR THE INTERPOLATION.** `NSColor` stores a `CGColor`, so the numbers
 * are the engine's; a colour whose model is not the gradient's is CONVERTED for the three models that have an obvious
 * arithmetic (gray to RGB replicates the channel; RGB to gray uses the sRGB luminance weights; RGB to CMYK uses the naive
 * black-generation formula), and anything else (Lab, indexed, pattern) is refused by name because guessing there would be
 * a colour nobody measured. */
static BOOL fn_components_of(NSColor *color, NSColorSpaceModel model, CGFloat out[4])
{
	const CGFloat *parts;
	size_t count;
	CGColorRef cg;
	CGColorSpaceRef space;

	out[0] = out[1] = out[2] = out[3] = 0.0;
	if (color == nil) {
		return NO;
	}
	cg = [color CGColor];
	if (cg == NULL) {
		return NO;
	}
	space = CGColorGetColorSpace(cg);
	parts = CGColorGetComponents(cg);
	count = CGColorGetNumberOfComponents(cg);
	if (space == NULL || parts == NULL || count < 2) {
		return NO;
	}
	{
		CGColorSpaceModel source = CGColorSpaceGetModel(space);
		CGFloat alpha = parts[count - 1];

		if ((source == kCGColorSpaceModelMonochrome) && model == NSGrayColorSpaceModel) {
			out[0] = parts[0];
			out[3] = alpha;
			return YES;
		}
		if (source == kCGColorSpaceModelMonochrome && model == NSRGBColorSpaceModel) {
			out[0] = out[1] = out[2] = parts[0];
			out[3] = alpha;
			return YES;
		}
		if (source == kCGColorSpaceModelRGB && model == NSRGBColorSpaceModel) {
			out[0] = parts[0];
			out[1] = parts[1];
			out[2] = parts[2];
			out[3] = alpha;
			return YES;
		}
		if (source == kCGColorSpaceModelRGB && model == NSGrayColorSpaceModel) {
			out[0] = 0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2];
			out[3] = alpha;
			return YES;
		}
		if (source == kCGColorSpaceModelRGB && model == NSCMYKColorSpaceModel) {
			CGFloat k = 1.0 - fmax(parts[0], fmax(parts[1], parts[2]));

			if (k < 1.0) {
				out[0] = (1.0 - parts[0] - k) / (1.0 - k);
				out[1] = (1.0 - parts[1] - k) / (1.0 - k);
				out[2] = (1.0 - parts[2] - k) / (1.0 - k);
			}
			out[3] = k;
			return YES;
		}
		if (source == kCGColorSpaceModelCMYK && model == NSCMYKColorSpaceModel) {
			out[0] = parts[0];
			out[1] = parts[1];
			out[2] = parts[2];
			out[3] = parts[3];
			return YES;
		}
	}
	return NO;
}

/* AN NSColor FROM FOUR NUMBERS IN A MODEL, which is how the interpolation's answer is packaged. */
static NSColor *fn_color_from(NSColorSpaceModel model, const CGFloat c[4])
{
	switch (model) {
	case NSGrayColorSpaceModel:
		return [NSColor colorWithCalibratedWhite:c[0] alpha:c[3]];
	case NSCMYKColorSpaceModel:
		return [NSColor colorWithCalibratedRed:(1.0 - c[0]) * (1.0 - c[3])
						 green:(1.0 - c[1]) * (1.0 - c[3])
						  blue:(1.0 - c[2]) * (1.0 - c[3]) alpha:c[3]];
	case NSRGBColorSpaceModel:
	default:
		return [NSColor colorWithCalibratedRed:c[0] green:c[1] blue:c[2] alpha:c[3]];
	}
}

@implementation NSGradient

/* **THE DESIGNATED INITIALISER, AND EVERY OTHER DOOR GOES THROUGH IT.** The stops are checked here once: at least one
 * colour, ascending locations inside 0..1, and a space to measure in. Anything else answers nil, which is a refusal at the
 * CALL rather than an object that fails later. */
- (instancetype)initWithColors:(NSArray *)colorArray atLocations:(const CGFloat *)locations colorSpace:(NSColorSpace *)colorSpace
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	if ([colorArray count] == 0) {
		[self release];
		return nil;
	}
	_colorSpace = [(colorSpace != nil) ? colorSpace : fn_default_space() retain];
	_colors = [colorArray copy];
	_numberOfColorStops = (NSInteger)[colorArray count];
	_locations = malloc(sizeof(CGFloat) * (size_t)_numberOfColorStops);
	{
		NSInteger i;

		for (i = 0; i < _numberOfColorStops; i++) {
			CGFloat location = (locations != NULL) ? locations[i]
				: (_numberOfColorStops == 1) ? 0.0
				: (CGFloat)i / (CGFloat)(_numberOfColorStops - 1);

			if (location < 0.0) {
				location = 0.0;
			}
			if (location > 1.0) {
				location = 1.0;
			}
			_locations[i] = location;
		}
	}
	/* AND THE ENGINE'S RAMP, built once from the stops as CGColors in the gradient's own space. */
	{
		CFMutableArrayRef cgColors = CFArrayCreateMutable(kCFAllocatorDefault, (CFIndex)_numberOfColorStops,
								  &kCFTypeArrayCallBacks);
		NSInteger i;

		for (i = 0; i < _numberOfColorStops; i++) {
			CGColorRef cg = [[_colors objectAtIndex:(NSUInteger)i] CGColor];

			if (cg != NULL) {
				CFArrayAppendValue(cgColors, cg);
			}
		}
		_gradient = CGGradientCreateWithColors([_colorSpace CGColorSpace], cgColors, _locations);
		CFRelease(cgColors);
	}
	if (_gradient == NULL) {
		[self release];
		return nil;
	}
	return self;
}

- (instancetype)initWithStartingColor:(NSColor *)startingColor endingColor:(NSColor *)endingColor
{
	NSArray *pair;

	if (startingColor == nil || endingColor == nil) {
		return nil;
	}
	pair = [NSArray arrayWithObjects:startingColor, endingColor, nil];
	return [self initWithColors:pair atLocations:NULL colorSpace:fn_default_space()];
}

- (instancetype)initWithColors:(NSArray *)colorArray
{
	return [self initWithColors:colorArray atLocations:NULL colorSpace:fn_default_space()];
}

/* THE VARARGS DOOR: a colour, its location, and so on until nil. The engine has no varargs form, so the pairs are read
 * into two arrays and the designated initialiser does the rest — which is also where the validation lives. */
- (instancetype)initWithColorsAndLocations:(NSColor *)firstColor, ...
{
	va_list args;
	NSMutableArray *colors;
	NSMutableArray *places;
	NSColor *color = firstColor;
	CGFloat *locations;
	NSInteger count;
	NSInteger i;

	if (firstColor == nil) {
		return nil;
	}
	colors = [NSMutableArray array];
	places = [NSMutableArray array];
	va_start(args, firstColor);
	while (color != nil) {
		double location = va_arg(args, double);	/* a CGFloat is promoted to double in a varargs list */

		[colors addObject:color];
		[places addObject:[NSNumber numberWithDouble:location]];
		color = va_arg(args, id);
	}
	va_end(args);

	count = (NSInteger)[places count];
	locations = malloc(sizeof(CGFloat) * (size_t)count);
	for (i = 0; i < count; i++) {
		locations[i] = (CGFloat)[[places objectAtIndex:(NSUInteger)i] doubleValue];
	}
	self = [self initWithColors:colors atLocations:locations colorSpace:fn_default_space()];
	free(locations);
	return self;
}

- (void)dealloc
{
	if (_gradient != NULL) {
		CGGradientRelease(_gradient);
	}
	free(_locations);
	[_colors release];
	[_colorSpace release];
	[super dealloc];
}

- (id)copy
{
	/* A GRADIENT IS A VALUE: the copy is a second object with the same stops and its own engine ramp. */
	return [[NSGradient alloc] initWithColors:_colors atLocations:_locations colorSpace:_colorSpace];
}

/* ---- THE STOPS ------------------------------------------------------------------------------------ */

- (NSInteger)numberOfColorStops
{
	return _numberOfColorStops;
}

- (void)getColor:(NSColor **)color location:(CGFloat *)location atIndex:(NSInteger)index
{
	if (index < 0 || index >= _numberOfColorStops) {
		if (color != NULL) {
			*color = nil;
		}
		if (location != NULL) {
			*location = 0.0;
		}
		return;
	}
	if (color != NULL) {
		*color = [_colors objectAtIndex:(NSUInteger)index];
	}
	if (location != NULL) {
		*location = _locations[index];
	}
}

- (NSColorSpace *)colorSpace
{
	return _colorSpace;
}

/* **THE ONE COMPUTATION, AND IT IS THE RAMP'S DEFINITION.** A location before the first stop is the first stop's colour and
 * one after the last is the last's (the ramp has no colour past its ends), and in between it is a linear interpolation
 * between the two stops that bracket it, in the gradient's space. Two stops at the SAME location make a hard edge, which
 * is what a caller writing one asks for. */
- (NSColor *)interpolatedColorAtLocation:(CGFloat)location
{
	NSColorSpaceModel model;
	CGFloat lower[4];
	CGFloat upper[4];
	NSInteger i;

	if (_numberOfColorStops == 0) {
		return nil;
	}
	if (location <= _locations[0]) {
		return [_colors objectAtIndex:0];
	}
	if (location >= _locations[_numberOfColorStops - 1]) {
		return [_colors objectAtIndex:(NSUInteger)(_numberOfColorStops - 1)];
	}
	model = [_colorSpace colorSpaceModel];
	for (i = 0; i + 1 < _numberOfColorStops; i++) {
		CGFloat span;
		CGFloat t;
		CGFloat mix[4];
		NSUInteger k;

		if (location < _locations[i] || location > _locations[i + 1]) {
			continue;
		}
		span = _locations[i + 1] - _locations[i];
		t = (span > 0.0) ? (location - _locations[i]) / span : 0.0;
		if (!fn_components_of([_colors objectAtIndex:(NSUInteger)i], model, lower)
		    || !fn_components_of([_colors objectAtIndex:(NSUInteger)i + 1], model, upper)) {
			fn_refuse_window("-NSGradient -interpolatedColorAtLocation:",
					 "stops whose colours can be converted into the gradient's space; Lab, indexed and "
					 "pattern colours have no arithmetic here");
			return nil;
		}
		for (k = 0; k < 4; k++) {
			mix[k] = lower[k] + (upper[k] - lower[k]) * t;
		}
		return fn_color_from(model, mix);
	}
	return [_colors objectAtIndex:(NSUInteger)(_numberOfColorStops - 1)];
}

/* ---- THE DRAWING DOORS ----------------------------------------------------------------------------- */

static CGContextRef fn_current_context(void)
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];

	return (context != nil) ? (CGContextRef)[context CGContext] : NULL;
}

- (void)drawFromPoint:(NSPoint)startingPoint toPoint:(NSPoint)endingPoint options:(NSGradientDrawingOptions)options
{
	CGContextRef cg = fn_current_context();

	if (cg == NULL) {
		fn_refuse_window("-NSGradient -drawFromPoint:toPoint:options:", "a current graphics context");
		return;
	}
	CGContextDrawLinearGradient(cg, _gradient, CGPointMake(startingPoint.x, startingPoint.y),
				    CGPointMake(endingPoint.x, endingPoint.y), (CGGradientDrawingOptions)options);
}

- (void)drawFromCenter:(NSPoint)startCenter radius:(CGFloat)startRadius toCenter:(NSPoint)endCenter
		radius:(CGFloat)endRadius options:(NSGradientDrawingOptions)options
{
	CGContextRef cg = fn_current_context();

	if (cg == NULL) {
		fn_refuse_window("-NSGradient -drawFromCenter:radius:toCenter:radius:options:", "a current graphics context");
		return;
	}
	CGContextDrawRadialGradient(cg, _gradient, CGPointMake(startCenter.x, startCenter.y), startRadius,
				    CGPointMake(endCenter.x, endCenter.y), endRadius, (CGGradientDrawingOptions)options);
}

/* **AN ANGLE ACROSS A RECTANGLE IS THE RAMP'S LINE THROUGH THE MIDDLE.** The direction is (cos, sin) of the angle; the
 * length is the rectangle's extent along it (|w cos| + |h sin|), which is what makes a 0-degree ramp span the width and a
 * 90-degree one span the height. The two points are the middle plus and minus half that length. */
- (void)drawInRect:(NSRect)rect angle:(CGFloat)startingAngle
{
	CGFloat radians = AG_DEGREES_TO_RADIANS(startingAngle);
	CGFloat dx = (CGFloat)cos((double)radians);
	CGFloat dy = (CGFloat)sin((double)radians);
	CGFloat length = (CGFloat)fabs((double)(NSWidth(rect) * dx)) + (CGFloat)fabs((double)(NSHeight(rect) * dy));
	NSPoint middle = NSMakePoint(NSMidX(rect), NSMidY(rect));
	NSPoint from = NSMakePoint(middle.x - dx * length / 2.0, middle.y - dy * length / 2.0);
	NSPoint to = NSMakePoint(middle.x + dx * length / 2.0, middle.y + dy * length / 2.0);

	[self drawFromPoint:from toPoint:to options:0];
}

/* **A RADIAL PLACEMENT IS A CENTRE AND A RADIUS.** The relative centre is (-1..1) offsets from the middle, times half the
 * rectangle, and the radius is half the diagonal so the ramp reaches every corner. Zero at both starts and ends is a
 * degenerate circle the engine draws as a flat fill of the first stop, which is what a caller asking for it gets. */
- (void)drawInRect:(NSRect)rect relativeCenterPosition:(NSPoint)relativeCenterPosition
{
	NSPoint center = NSMakePoint(NSMidX(rect) + relativeCenterPosition.x * NSWidth(rect) / 2.0,
				     NSMidY(rect) + relativeCenterPosition.y * NSHeight(rect) / 2.0);
	CGFloat radius = (CGFloat)(sqrt((double)(NSWidth(rect) * NSWidth(rect) + NSHeight(rect) * NSHeight(rect))) / 2.0);

	[self drawFromCenter:center radius:0.0 toCenter:center radius:radius options:0];
}

- (void)drawInBezierPath:(NSBezierPath *)path angle:(CGFloat)startingAngle
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = fn_current_context();

	if (cg == NULL || path == nil) {
		fn_refuse_window("-NSGradient -drawInBezierPath:angle:", "a current graphics context and a path");
		return;
	}
	[NSGraphicsContext saveGraphicsState];
	[path addClip];
	[self drawInRect:[path bounds] angle:startingAngle];
	[NSGraphicsContext restoreGraphicsState];
	(void)context;
}

- (void)drawInBezierPath:(NSBezierPath *)path relativeCenterPosition:(NSPoint)relativeCenterPosition
{
	CGContextRef cg = fn_current_context();

	if (cg == NULL || path == nil) {
		fn_refuse_window("-NSGradient -drawInBezierPath:relativeCenterPosition:",
				 "a current graphics context and a path");
		return;
	}
	[NSGraphicsContext saveGraphicsState];
	[path addClip];
	[self drawInRect:[path bounds] relativeCenterPosition:relativeCenterPosition];
	[NSGraphicsContext restoreGraphicsState];
}

@end
