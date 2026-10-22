/*
 * NSRulerView — the strip that measures a document, and the markers that sit on it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The file holds BOTH classes because Apple declares both in one header and because the marker's geometry is the
 * ruler's geometry: `-imageRectInRuler` is a location the marker was given and a thickness the ruler reserves. The
 * four functions below are the whole of the arithmetic — the axis of a point, the band a location occupies, the unit
 * table, and the step a tick takes — and everything else in the file spends them.
 */
#import "NSRulerView.h"

#import "NSScrollView.h"
#import "NSClipView.h"
#import "NSImage.h"
#import "NSColor.h"
#import "NSFont.h"
#import "NSBezierPath.h"
#import "NSEvent.h"
#import "NSGraphics.h"
#import "NSStringDrawing.h"
#import "AppKitRefusal.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <math.h>

/* **THE INSIDE INK'S INSETS.** A tick is at most eight points long and a label's baseline sits ten points in from the
 * inside edge, which is where the free space above an eight-point tick ends for a nine-point face. They are constants
 * rather than parameters because a caller does not get to move the marks: a ruler whose ticks are somewhere else is a
 * subclass with its own `-drawHashMarksAndLabelsInRect:`. */
#define AG_RULER_MAJOR_TICK 8.0
#define AG_RULER_MINOR_TICK 4.0
#define AG_RULER_LABEL_INSET 10.0
#define AG_RULER_LABEL_GAP 2.0
#define AG_RULER_FONT_SIZE 9.0
/* **AND THE SMALLEST SPACE A LABEL MAY BE GIVEN.** The step search below walks the unit's own cycle until a step is at
 * least this many points wide, so "1" inches does not become "1.0, 2.0, 3.0" crowded against itself. */
#define AG_RULER_MIN_LABEL_SPACE 44.0

/* ==================================================================================================================
 * THE UNIT TABLE.
 *
 * A unit is four facts: what to call it, what to print after the number, how many points one of it is, and two cycles
 * of multiples. The cycles are what make a ruler readable rather than a wall of evenly spaced lines: `stepUp` names the
 * multiples at which a tick becomes a LONG, LABELLED one, and `stepDown` the finer multiples drawn between them. The
 * table is one Class-level dictionary, because a unit is a fact about measurement and every ruler on the screen shares
 * it — which is also why registering a name REPLACES rather than adds a second entry nobody can reach.
 * ================================================================================================================ */

static NSMutableDictionary *gRulerUnits = nil;

static NSArray *fn_cycle(CGFloat a, CGFloat b, CGFloat c, CGFloat d)
{
	return [NSArray arrayWithObjects:[NSNumber numberWithDouble:(double)a], [NSNumber numberWithDouble:(double)b],
				       [NSNumber numberWithDouble:(double)c], [NSNumber numberWithDouble:(double)d], nil];
}

static NSDictionary *fn_unit(NSString *abbreviation, CGFloat factor, NSArray *up, NSArray *down)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		abbreviation, @"abbreviation",
		[NSNumber numberWithDouble:(double)factor], @"factor",
		up, @"up",
		down, @"down", nil];
}

/* **THE FOUR THE ERA SHIPS, AND THEIR CYCLES ARE THE ERA'S RATHER THAN INVENTED.** An inch subdivides by ten into the
 * tenths a ruler shows and steps up through halves, quarters and eighths; a centimetre steps in tens and subdivides in
 * ten; a point has nothing finer; a pica is twelve points and subdivides in twelve, which is the whole reason the unit
 * exists. */
static NSMutableDictionary *fn_units(void)
{
	if (gRulerUnits == nil) {
		gRulerUnits = [[NSMutableDictionary alloc] init];
		[gRulerUnits setObject:fn_unit(@"in", 72.0, fn_cycle(0.125, 0.25, 0.5, 1.0),
					      fn_cycle(0.1, 0.2, 0.5, 1.0))
				forKey:NSRulerViewUnitInches];
		[gRulerUnits setObject:fn_unit(@"cm", 72.0 / 2.54, fn_cycle(0.5, 1.0, 5.0, 10.0),
					      fn_cycle(0.1, 0.2, 0.5, 1.0))
				forKey:NSRulerViewUnitCentimeters];
		[gRulerUnits setObject:fn_unit(@"", 1.0, fn_cycle(10.0, 20.0, 50.0, 100.0),
					      fn_cycle(0.1, 0.2, 0.5, 1.0))
				forKey:NSRulerViewUnitPoints];
		[gRulerUnits setObject:fn_unit(@"pc", 12.0, fn_cycle(1.0, 2.0, 6.0, 12.0),
					      fn_cycle(0.0833, 0.25, 0.5, 1.0))
				forKey:NSRulerViewUnitPicas];
	}
	return gRulerUnits;
}

NSString *const NSRulerViewUnitInches = @"Inches";
NSString *const NSRulerViewUnitCentimeters = @"Centimeters";
NSString *const NSRulerViewUnitPoints = @"Points";
NSString *const NSRulerViewUnitPicas = @"Picas";

/* ==================================================================================================================
 * THE MARKER.
 * ================================================================================================================ */

@interface NSRulerMarker (AGRulerInternal)
- (void)cg_setRuler:(NSRulerView *)ruler;
- (void)cg_setDragging:(BOOL)flag;
@end

/* **THE CLIENT'S INFORMAL PROTOCOL, TYPED.** Apple's ruler sends its client view eight messages and declares none of
 * them in a protocol, so a caller has to spell `respondsToSelector:` and a caller that then sends the message gets the
 * compiler's "method not found" and a presumed `id` return — which is exactly how `willAddMarker:atLocation:`'s
 * `CGFloat` becomes a pointer. Declaring the shape here costs nothing and makes every send below type-checked. A view
 * that implements them (NSTextView does) conforms whether or not it says so; this protocol is a description, not a
 * requirement, which is why it is not in the header. */
@protocol AGRulerClient <NSObject>
@optional
- (BOOL)rulerView:(NSRulerView *)aRulerView shouldAddMarker:(NSRulerMarker *)marker;
- (CGFloat)rulerView:(NSRulerView *)aRulerView willAddMarker:(NSRulerMarker *)marker atLocation:(CGFloat)location;
- (void)rulerView:(NSRulerView *)aRulerView didAddMarker:(NSRulerMarker *)marker;
- (BOOL)rulerView:(NSRulerView *)aRulerView shouldMoveMarker:(NSRulerMarker *)marker;
- (CGFloat)rulerView:(NSRulerView *)aRulerView willMoveMarker:(NSRulerMarker *)marker toLocation:(CGFloat)location;
- (void)rulerView:(NSRulerView *)aRulerView didMoveMarker:(NSRulerMarker *)marker;
- (BOOL)rulerView:(NSRulerView *)aRulerView shouldRemoveMarker:(NSRulerMarker *)marker;
- (void)rulerView:(NSRulerView *)aRulerView didRemoveMarker:(NSRulerMarker *)marker;
- (void)rulerView:(NSRulerView *)aRulerView handleMouseDown:(NSEvent *)event;
@end

@implementation NSRulerMarker

- (instancetype)initWithRulerView:(NSRulerView *)rulerView
		   markerLocation:(CGFloat)markerLocation
			    image:(NSImage *)image
		      imageOrigin:(NSPoint)imageOrigin
{
	self = [super init];
	if (self != nil) {
		_ruler = rulerView;	/* BORROWED: whoever adds the marker is the owner */
		_markerLocation = markerLocation;
		_image = [image retain];
		_imageOrigin = imageOrigin;
		_representedObject = nil;
		/* **BOTH DEFAULT TO YES, WHICH IS APPLE'S DEFAULT AND THE PERMISSIVE ONE.** A marker nobody has configured is
		 * draggable and removable; a client that wants a permanent one marks it so, rather than every client having to
		 * remember to opt in to the thing markers are for. */
		_movable = YES;
		_removable = YES;
		_dragging = NO;
	}
	return self;
}

- (void)dealloc
{
	[_image release];
	[_representedObject release];
	[super dealloc];
}

- (CGFloat)markerLocation
{
	return _markerLocation;
}

- (void)setMarkerLocation:(CGFloat)markerLocation
{
	_markerLocation = markerLocation;
	[_ruler setNeedsDisplay:YES];
}

- (NSImage *)image
{
	return _image;
}

- (void)setImage:(NSImage *)image
{
	NSImage *old = _image;

	_image = [image retain];
	[old release];
	[_ruler setNeedsDisplay:YES];
}

- (NSPoint)imageOrigin
{
	return _imageOrigin;
}

- (void)setImageOrigin:(NSPoint)imageOrigin
{
	_imageOrigin = imageOrigin;
	[_ruler setNeedsDisplay:YES];
}

/* **THE GEOMETRY, WHICH IS ONE RECTANGLE FROM THREE FACTS.** The marker's location places the image along the ruler's
 * axis and the origin places it across; the image's own size is the extent, so nothing is ever scaled to fill a strip.
 * A marker with no image is a zero rect at the right place, which is the honest answer: there is nothing to draw, and
 * a hit test on it should fail. */
- (NSRect)imageRectInRuler
{
	NSSize size = NSZeroSize;
	NSRect rect;

	if (_image != nil) {
		size = [_image size];
	}
	if (_ruler != nil && [_ruler orientation] == NSVerticalRuler) {
		rect = NSMakeRect(_imageOrigin.x, _markerLocation + _imageOrigin.y, size.width, size.height);
	} else {
		rect = NSMakeRect(_markerLocation + _imageOrigin.x, _imageOrigin.y, size.width, size.height);
	}
	return rect;
}

/* **THE THICKNESS THE MARKER NEEDS IS THE ONE ACROSS THE RULER, NOT ALONG IT.** A horizontal ruler runs left to right,
 * so what a marker spends is its HEIGHT plus the y of its origin; a vertical ruler spends its WIDTH plus the x. That is
 * the number a client sums into `-reservedThicknessForMarkers`, and the reason the two orientations answer differently. */
- (CGFloat)thicknessRequiredInRuler
{
	NSRect rect = [self imageRectInRuler];

	if (_ruler != nil && [_ruler orientation] == NSVerticalRuler) {
		return NSMaxX(rect);
	}
	return NSMaxY(rect);
}

- (id)representedObject
{
	return _representedObject;
}

- (void)setRepresentedObject:(id)representedObject
{
	if (representedObject == _representedObject) {
		return;
	}
	[representedObject retain];
	[_representedObject release];
	_representedObject = representedObject;
}

- (BOOL)isMovable
{
	return _movable;
}

- (void)setMovable:(BOOL)flag
{
	_movable = flag ? YES : NO;
}

- (BOOL)isRemovable
{
	return _removable;
}

- (void)setRemovable:(BOOL)flag
{
	_removable = flag ? YES : NO;
}

- (BOOL)isDragging
{
	return _dragging;
}

- (NSRulerView *)ruler
{
	return _ruler;
}

/* THE MARKER'S INK IS ITS IMAGE AND NOTHING ELSE. Apple's markers are small bitmaps; a marker that wants a rule or a
 * number draws it into the image it was given, which is why this door never grows a second drawing path. */
- (void)drawRect:(NSRect)rect
{
	NSRect imageRect = [self imageRectInRuler];

	if (_image == nil || NSIsEmptyRect(imageRect) || !NSIntersectsRect(imageRect, rect)) {
		return;
	}
	[_image drawInRect:imageRect];
}

/* **THE REFUSAL IS THE DOCUMENTED ONE: THE LOOP, NOT THE DRAG.** The drag is real and the ruler runs it from its own
 * `-mouseDown:`/`-mouseDragged:`/`-mouseUp:`; what this era spelling adds is a private event pump that would take the
 * run loop from the application and cannot be driven by a headless test. Answering NO is the marker's own "empty
 * value" — the drag did not happen — and the reason is printed so a caller is not left guessing. */
- (BOOL)trackMouse:(NSEvent *)theEvent adding:(BOOL)isAdding
{
	(void)theEvent;
	(void)isAdding;
	fn_refuse_window("NSRulerMarker -trackMouse:adding:",
			 "the modal tracking loop NSCell also declines; the ruler's -trackMarker:withMouseEvent: runs the "
			 "same drag from the event stream the application already pumps");
	return NO;
}

/* THE PRIVATE HALF: the ruler that owns the marker, and the drag bit. Neither is an Apple door, and both are declared
 * in a category at the foot of this file so the two classes in one file can talk without a public seam. */
- (void)cg_setRuler:(NSRulerView *)ruler
{
	_ruler = ruler;
}

- (void)cg_setDragging:(BOOL)flag
{
	_dragging = flag ? YES : NO;
}

@end

/* ==================================================================================================================
 * THE RULER.
 * ================================================================================================================ */

@implementation NSRulerView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		[self cg_commonInitWithScrollView:nil orientation:NSHorizontalRuler];
	}
	return self;
}

- (instancetype)initWithScrollView:(NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation
{
	self = [super initWithFrame:NSZeroRect];
	if (self != nil) {
		[self cg_commonInitWithScrollView:scrollView orientation:orientation];
	}
	return self;
}

- (void)cg_commonInitWithScrollView:(NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation
{
	_scrollView = scrollView;	/* BORROWED: the scroll view adds us as a subview, and a view owns its children */
	_orientation = orientation;
	_markers = [[NSMutableArray alloc] init];
	_accessoryView = nil;
	_clientView = nil;
	/* **FIFTEEN IS THE ERA'S RULE STRIP**, and the reserve for markers starts empty because a ruler with no markers
	 * has nothing to reserve for; a text view sets it when it installs tab markers. */
	_ruleThickness = 15.0;
	_reservedThicknessForMarkers = 0.0;
	_reservedThicknessForAccessoryView = 0.0;
	_originOffset = 0.0;
	_measurementUnits = [NSRulerViewUnitInches retain];
	_draggedMarker = nil;
	_dragging = NO;
	_rulerLineLocation = 0.0;
	_hasRulerLine = NO;
	/* **BOTH ORIENTATIONS ARE FLIPPED HERE — see the header's note.** The client's direction is the ruler's. */
	[self setFlipped:YES];
}

- (void)dealloc
{
	[_markers release];
	[_accessoryView release];
	[_measurementUnits release];
	[super dealloc];
}

- (BOOL)isFlipped
{
	/* **STATED DEVIATION.** Apple's vertical ruler is not flipped; this one is, so a vertical marker location grows
	 * DOWNWARD with the text it measures instead of upward against it. See the header for what that buys. */
	return YES;
}

/* ---- THE RELATIONSHIP ------------------------------------------------------------------------------------ */

- (NSScrollView *)scrollView
{
	return _scrollView;
}

- (void)setScrollView:(NSScrollView *)scrollView
{
	_scrollView = scrollView;	/* NOT RETAINED */
}

- (NSView *)clientView
{
	return _clientView;
}

- (void)setClientView:(NSView *)clientView
{
	_clientView = clientView;	/* NOT RETAINED */
	[self setNeedsDisplay:YES];
}

- (NSRulerOrientation)orientation
{
	return _orientation;
}

- (void)setOrientation:(NSRulerOrientation)orientation
{
	if (orientation == _orientation) {
		return;
	}
	_orientation = orientation;
	[self cg_layOutAccessoryView];
	[self setNeedsDisplay:YES];
}

/* ---- THE THICKNESS ARITHMETIC ---------------------------------------------------------------------------- */

- (CGFloat)ruleThickness
{
	return _ruleThickness;
}

- (void)setRuleThickness:(CGFloat)thickness
{
	CGFloat value = (thickness > 0.0) ? thickness : 0.0;

	if (value == _ruleThickness) {
		return;
	}
	_ruleThickness = value;
	[self cg_thicknessChanged];
}

- (CGFloat)reservedThicknessForMarkers
{
	return _reservedThicknessForMarkers;
}

- (void)setReservedThicknessForMarkers:(CGFloat)thickness
{
	CGFloat value = (thickness > 0.0) ? thickness : 0.0;

	if (value == _reservedThicknessForMarkers) {
		return;
	}
	_reservedThicknessForMarkers = value;
	[self cg_thicknessChanged];
}

- (CGFloat)reservedThicknessForAccessoryView
{
	return _reservedThicknessForAccessoryView;
}

- (void)setReservedThicknessForAccessoryView:(CGFloat)thickness
{
	CGFloat value = (thickness > 0.0) ? thickness : 0.0;

	if (value == _reservedThicknessForAccessoryView) {
		return;
	}
	_reservedThicknessForAccessoryView = value;
	[self cg_thicknessChanged];
}

- (CGFloat)requiredThickness
{
	return _ruleThickness + _reservedThicknessForMarkers + _reservedThicknessForAccessoryView;
}

/* **A THICKNESS CHANGE IS A LAYOUT CHANGE.** The strip is one of the things the scroll view tiles around, so the ruler
 * asks it to re-tile rather than merely repainting: a thicker ruler that kept its old frame would draw over the
 * document, and a thinner one would leave a hole. */
- (void)cg_thicknessChanged
{
	if (_scrollView != nil) {
		[_scrollView tile];
	}
	[self cg_layOutAccessoryView];
	[self setNeedsDisplay:YES];
}

/* ---- THE ACCESSORY --------------------------------------------------------------------------------------- */

- (NSView *)accessoryView
{
	return _accessoryView;
}

/* **THE ACCESSORY IS A SUBVIEW IN THE OUTSIDE BAND.** The band is the first `-reservedThicknessForAccessoryView`
 * points of the ruler measured from its OUTSIDE edge (the one away from the document), because that is the only room a
 * caller can give it without colliding with the hash marks. Here the view is simply placed there; a ruler whose reserve
 * is zero places a zero-height view, which is the caller's own arithmetic to fix and not a silently adjusted one. */
- (void)setAccessoryView:(NSView *)accessoryView
{
	if (accessoryView == _accessoryView) {
		return;
	}
	[_accessoryView removeFromSuperview];
	[_accessoryView release];
	_accessoryView = [accessoryView retain];
	if (_accessoryView != nil) {
		[self addSubview:_accessoryView];
	}
	[self cg_layOutAccessoryView];
	[self setNeedsDisplay:YES];
}

- (void)cg_layOutAccessoryView
{
	NSRect frame = [self bounds];
	CGFloat band = _reservedThicknessForAccessoryView;

	if (_accessoryView == nil) {
		return;
	}
	if (_orientation == NSVerticalRuler) {
		[_accessoryView setFrame:NSMakeRect(NSMinX(frame), NSMinY(frame), band, NSHeight(frame))];
	} else {
		[_accessoryView setFrame:NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), band)];
	}
}

- (void)setFrame:(NSRect)frameRect
{
	[super setFrame:frameRect];
	[self cg_layOutAccessoryView];
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self cg_layOutAccessoryView];
}

/* ---- THE MARKERS ----------------------------------------------------------------------------------------- */

- (NSArray *)markers
{
	/* **A COPY, WHICH IS APPLE'S ANSWER AND THE SAFE ONE.** A caller that iterated the live array while removing from it
	 * would be enumerating a thing it was changing; the markers themselves are shared, which is what lets a caller
	 * compare one it kept against the array it came from. */
	return [[_markers copy] autorelease];
}

- (void)setMarkers:(NSArray *)markers
{
	NSUInteger i;

	for (i = 0; i < [_markers count]; i++) {
		[[_markers objectAtIndex:i] cg_setRuler:nil];
	}
	[_markers removeAllObjects];
	for (i = 0; i < [markers count]; i++) {
		NSRulerMarker *marker = [markers objectAtIndex:i];

		if ([_markers containsObject:marker]) {
			continue;
		}
		/* PROGRAMMATIC, SO THE CLIENT IS NOT ASKED: `-setMarkers:` is the answer the client just gave, not a request
		 * for permission. */
		[marker cg_setRuler:self];
		[_markers addObject:marker];
	}
	[self setNeedsDisplay:YES];
}

- (void)addMarker:(NSRulerMarker *)marker
{
	id<AGRulerClient> client = (id<AGRulerClient>)_clientView;
	CGFloat location;

	if (marker == nil || [_markers containsObject:marker]) {
		return;
	}
	if ([client respondsToSelector:@selector(rulerView:shouldAddMarker:)] &&
	    ![client rulerView:self shouldAddMarker:marker]) {
		return;
	}
	location = [marker markerLocation];
	if ([client respondsToSelector:@selector(rulerView:willAddMarker:atLocation:)]) {
		location = [client rulerView:self willAddMarker:marker atLocation:location];
	}
	[marker cg_setRuler:self];
	[marker setMarkerLocation:location];
	[_markers addObject:marker];
	if ([client respondsToSelector:@selector(rulerView:didAddMarker:)]) {
		[client rulerView:self didAddMarker:marker];
	}
	[self setNeedsDisplay:YES];
}

- (void)removeMarker:(NSRulerMarker *)marker
{
	id<AGRulerClient> client = (id<AGRulerClient>)_clientView;

	if (marker == nil || ![_markers containsObject:marker]) {
		return;
	}
	if ([client respondsToSelector:@selector(rulerView:shouldRemoveMarker:)] &&
	    ![client rulerView:self shouldRemoveMarker:marker]) {
		return;
	}
	[marker cg_setRuler:nil];
	[[marker retain] autorelease];	/* the array is about to drop the only other reference */
	[_markers removeObject:marker];
	if ([client respondsToSelector:@selector(rulerView:didRemoveMarker:)]) {
		[client rulerView:self didRemoveMarker:marker];
	}
	[self setNeedsDisplay:YES];
}

/* ---- THE AXIS, WHICH EVERY GEOMETRY DOOR SPENDS ---------------------------------------------------------- */

/* The two ends of a rect along the ruler's axis. Foundation has no oriented min/max, and writing the ternary at each
 * of the four sites is how a horizontal ruler gets the vertical ruler's arithmetic by copy and paste. */
- (CGFloat)cg_axisMinOfRect:(NSRect)rect
{
	return (_orientation == NSVerticalRuler) ? NSMinY(rect) : NSMinX(rect);
}

- (CGFloat)cg_axisMaxOfRect:(NSRect)rect
{
	return (_orientation == NSVerticalRuler) ? NSMaxY(rect) : NSMaxX(rect);
}

/* The coordinate along the ruler's own axis of a point in its BOUNDS — which is the document's coordinate, because the
 * scroll view keeps the ruler's bounds origin equal to the client's. */
- (CGFloat)cg_axisOfPoint:(NSPoint)point
{
	return (_orientation == NSVerticalRuler) ? point.y : point.x;
}

- (CGFloat)cg_axisOfEvent:(NSEvent *)event
{
	return [self cg_axisOfPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (CGFloat)cg_axisLength
{
	return (_orientation == NSVerticalRuler) ? NSHeight([self bounds]) : NSWidth([self bounds]);
}

- (CGFloat)cg_thickness
{
	return (_orientation == NSVerticalRuler) ? NSWidth([self bounds]) : NSHeight([self bounds]);
}

/* THE BAND A LOCATION OCCUPIES, across the whole ruler thickness — the rect a guide line or a repaint needs. */
- (NSRect)cg_bandAtLocation:(CGFloat)location
{
	if (_orientation == NSVerticalRuler) {
		return NSMakeRect(NSMinX([self bounds]), location, NSWidth([self bounds]), 1.0);
	}
	return NSMakeRect(location, NSMinY([self bounds]), 1.0, NSHeight([self bounds]));
}

/* THE MARKER UNDER A POINT, searched from the END of the array because the last one added is the one on top. */
- (NSRulerMarker *)cg_markerAtPoint:(NSPoint)point
{
	NSInteger i;

	for (i = (NSInteger)[_markers count] - 1; i >= 0; i--) {
		NSRulerMarker *marker = [_markers objectAtIndex:(NSUInteger)i];

		if (NSPointInRect(point, [marker imageRectInRuler])) {
			return marker;
		}
	}
	return nil;
}

/* ---- THE GESTURE ----------------------------------------------------------------------------------------- */

/* **A CLICK IS A MARKER'S DRAG OR THE CLIENT'S BUSSINESS, IN THAT ORDER.** The hit test is the markers' own rectangles,
 * so a gap between two markers belongs to the client — which is what lets a text view put its insertion point where a
 * ruler was clicked, the other half of the gesture. */
- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSRulerMarker *marker = [self cg_markerAtPoint:point];
	id<AGRulerClient> client = (id<AGRulerClient>)_clientView;

	if (marker != nil && [self trackMarker:marker withMouseEvent:event]) {
		return;
	}
	if ([client respondsToSelector:@selector(rulerView:handleMouseDown:)]) {
		[client rulerView:self handleMouseDown:event];
	}
}

/* **THE SESSION'S FIRST HALF.** The client is asked whether the marker may move at all, then where it wants it moved
 * to, and then the drag is live: `-mouseDragged:` computes an ABSOLUTE location from where the pointer grabbed the
 * marker, which is the property that stops a refused move from accumulating error. */
- (BOOL)trackMarker:(NSRulerMarker *)marker withMouseEvent:(NSEvent *)event
{
	id<AGRulerClient> client = (id<AGRulerClient>)_clientView;

	if (marker == nil || ![_markers containsObject:marker] || ![marker isMovable]) {
		return NO;
	}
	if ([client respondsToSelector:@selector(rulerView:shouldMoveMarker:)] &&
	    ![client rulerView:self shouldMoveMarker:marker]) {
		return NO;
	}
	_draggedMarker = marker;
	_dragging = YES;
	_dragStartLocation = [marker markerLocation];
	/* A GRAB WITH NO EVENT IS THE PROGRAMMATIC START OF A DRAG: the grab point is the marker's own location, so the
	 * first `-mouseDragged:` with a point P moves it by P minus that point. */
	_dragStartAxis = (event != nil) ? [self cg_axisOfEvent:event] : _dragStartLocation;
	[marker cg_setDragging:YES];
	if ([client respondsToSelector:@selector(rulerView:willMoveMarker:toLocation:)]) {
		CGFloat location = [client rulerView:self willMoveMarker:marker toLocation:_dragStartLocation];

		[marker setMarkerLocation:location];
	}
	return YES;
}

- (void)mouseDragged:(NSEvent *)event
{
	CGFloat axis;
	CGFloat location;
	CGFloat length;
	id client;

	if (!_dragging || _draggedMarker == nil) {
		return;
	}
	client = _clientView;
	axis = [self cg_axisOfEvent:event];
	location = _dragStartLocation + (axis - _dragStartAxis);
	length = [self cg_axisLength];
	if (location < 0.0) {
		location = 0.0;
	}
	if (location > length) {
		location = length;
	}
	if ([client respondsToSelector:@selector(rulerView:shouldMoveMarker:)] &&
	    ![client rulerView:self shouldMoveMarker:_draggedMarker]) {
		return;
	}
	if ([client respondsToSelector:@selector(rulerView:willMoveMarker:toLocation:)]) {
		location = [client rulerView:self willMoveMarker:_draggedMarker toLocation:location];
	}
	[self moveRulerlineFromLocation:[_draggedMarker markerLocation] toLocation:location];
	[_draggedMarker setMarkerLocation:location];
}

/* **AND THE SECOND HALF, WHICH IS ONE `didMove` AND NOT ONE PER PIXEL.** A text client's `didMove` rewrites the
 * paragraph's tab stops; sending it on every dragged event would edit the document a hundred times for one gesture.
 * Apple's wording for the notification is "has been moved", which is true once per drag. */
- (void)mouseUp:(NSEvent *)event
{
	id<AGRulerClient> client = (id<AGRulerClient>)_clientView;

	(void)event;
	if (!_dragging || _draggedMarker == nil) {
		return;
	}
	/* **THE MARKER IS PINNED FOR THE DURATION OF THE NOTIFICATION.** A client's `didMove` may rebuild the marker list
	 * (`NSTextView`'s does), and the array is the only owner — so the callback could release the marker it is being
	 * told about halfway through the sentence. */
	[[_draggedMarker retain] autorelease];
	[_draggedMarker cg_setDragging:NO];
	if ([client respondsToSelector:@selector(rulerView:didMoveMarker:)]) {
		[client rulerView:self didMoveMarker:_draggedMarker];
	}
	[self moveRulerlineFromLocation:_rulerLineLocation toLocation:_rulerLineLocation];
	_draggedMarker = nil;
	_dragging = NO;
	[self setNeedsDisplay:YES];
}

/* ---- THE UNITS ------------------------------------------------------------------------------------------- */

- (NSString *)measurementUnits
{
	return _measurementUnits;
}

/* **AN UNKNOWN NAME IS REFUSED BY NAME RATHER THAN ACCEPTED AND IGNORED.** A ruler that took "Furlongs" and then drew
 * no marks would look broken in a way the caller could not see; the refusal says which name it does not know, and the
 * old unit stays. */
- (void)setMeasurementUnits:(NSString *)unitName
{
	NSDictionary *entry = (unitName != nil) ? [fn_units() objectForKey:unitName] : nil;

	if (entry == nil) {
		fn_refuse_window("NSRulerView -setMeasurementUnits:",
				 "a unit that has not been registered; +registerUnitWithName: is the door for a new one");
		return;
	}
	if (unitName == _measurementUnits) {
		return;
	}
	[unitName retain];
	[_measurementUnits release];
	_measurementUnits = unitName;
	[self invalidateHashMarks];
}

- (CGFloat)originOffset
{
	return _originOffset;
}

- (void)setOriginOffset:(CGFloat)originOffset
{
	if (originOffset == _originOffset) {
		return;
	}
	_originOffset = originOffset;
	[self invalidateHashMarks];
}

+ (void)registerUnitWithName:(NSString *)unitName
	       abbreviation:(NSString *)abbreviation
unitToPointsConversionFactor:(CGFloat)conversionFactor
		stepUpCycle:(NSArray *)stepUpCycle
	      stepDownCycle:(NSArray *)stepDownCycle
{
	NSMutableDictionary *units = fn_units();
	NSDictionary *existing;
	BOOL append = (abbreviation == nil);

	if (unitName == nil || [unitName length] == 0 || conversionFactor <= 0.0 ||
	    [stepUpCycle count] == 0 || [stepDownCycle count] == 0) {
		fn_refuse_window("NSRulerView +registerUnitWithName:...",
				 "a name, a positive conversion factor and two non-empty cycles; it has none of them and the "
				 "unit table is unchanged");
		return;
	}
	existing = [units objectForKey:unitName];
	/* **A RE-REGISTRATION KEEPS THE OLD ABBREVIATION WHEN THE NEW CALL HAS NONE.** Apple's door takes all five
	 * arguments and so does this one; nil is not an Apple spelling, but allowing it costs nothing and lets a caller
	 * replace a unit's cycles without respelling its symbol. */
	if (append && existing != nil) {
		abbreviation = [existing objectForKey:@"abbreviation"];
	}
	if (abbreviation == nil) {
		abbreviation = @"";
	}
	[units setObject:fn_unit(abbreviation, conversionFactor, stepUpCycle, stepDownCycle) forKey:unitName];
	/* EVERY RULER IN THAT UNIT HAS TO REPAINT, and a ruler does not watch the table; the units that are on screen are
	 * reachable only through the views, so a caller that re-registers a unit in use asks for the redraw itself. That is
	 * the one place this door is less than automatic, and it is stated rather than papered over with a registry. */
}

/* ---- THE HASH MARKS -------------------------------------------------------------------------------------- */

/* **THE STEP, WHICH IS THE ONE PLACE A RULER'S LEGIBILITY IS DECIDED.** Walk the unit's step-up cycle in its own order
 * and take the first multiple that is at least `AG_RULER_MIN_LABEL_SPACE` points wide; if every multiple is narrower
 * (a zoomed-out canvas in points), take the last and let the labels crowd rather than draw nothing. The subdivision is
 * the last entry of the step-down cycle, which is the count Apple's cycles read as: five tenths between the inches, ten
 * between the centimetres. */
- (CGFloat)cg_majorStepInUnits
{
	NSDictionary *entry = [fn_units() objectForKey:_measurementUnits];
	NSArray *up;
	CGFloat factor;
	CGFloat chosen = 0.0;
	NSUInteger i;

	if (entry == nil) {
		return 1.0;
	}
	factor = [[entry objectForKey:@"factor"] doubleValue];
	up = [entry objectForKey:@"up"];
	for (i = 0; i < [up count]; i++) {
		CGFloat step = [[up objectAtIndex:i] doubleValue] * factor;

		chosen = [[up objectAtIndex:i] doubleValue];
		if (step >= AG_RULER_MIN_LABEL_SPACE) {
			break;
		}
	}
	return (chosen > 0.0) ? chosen : 1.0;
}

- (NSInteger)cg_subdivisionsPerMajor
{
	NSDictionary *entry = [fn_units() objectForKey:_measurementUnits];
	NSArray *down;
	CGFloat count;

	if (entry == nil) {
		return 1;
	}
	down = [entry objectForKey:@"down"];
	if ([down count] == 0) {
		return 1;
	}
	/* **THE CYCLE'S FIRST ENTRY IS THE FINEST SUBDIVISION, NOT ITS LAST** — the cycle runs from fine to coarse the way
	 * Apple's own does, so the reciprocal of the FIRST entry is how many fit between two major marks. Reading the last
	 * entry instead made every unit with a `1.0` at the end (points, inches) subdivide once, and the ruler drew only its
	 * labelled ticks — a wrong answer that looked like a style choice. */
	count = 1.0 / [[down objectAtIndex:0] doubleValue];
	if (count < 1.0) {
		count = 1.0;
	}
	if (count > 20.0) {
		count = 20.0;
	}
	return (NSInteger)floor((double)count + 0.5);
}

- (CGFloat)baselineLocation
{
	if (_orientation == NSVerticalRuler) {
		/* The label column's right edge: a vertical ruler's labels run horizontally, so what it needs is the x they
		 * end at, which is the inset from the inside edge. */
		return [self cg_thickness] - AG_RULER_LABEL_INSET;
	}
	/* **AND A HORIZONTAL RULER'S LABELS SIT ABOVE THEIR TICKS**, so the baseline is the tick height plus a gap in from
	 * the inside edge. THIS NUMBER IS MEASURED FROM THE INSIDE EDGE INWARD-TO-OUTWARD, which is the direction that does
	 * not change when a reserve is added to the outside: a ruler that reserved 40 points for markers would otherwise put
	 * its numbers in the markers' band. */
	return [self cg_thickness] - AG_RULER_MAJOR_TICK - AG_RULER_LABEL_GAP;
}

/* **THE TICKS AND THEIR NUMBERS, WHICH ARE DOCUMENT COORDINATES.** The loop walks the marks inside the dirty rect in
 * the ruler's own axis, which is the document's: a mark at value v is at `originOffset + v * factor`. Both ends are
 * clamped and the count is capped, so a ruler with a nonsense unit (a huge dirty rect at a tiny factor) cannot spin. */
- (void)drawHashMarksAndLabelsInRect:(NSRect)rect
{
	NSDictionary *entry = [fn_units() objectForKey:_measurementUnits];
	NSDictionary *attributes;
	NSFont *font;
	NSColor *tickColor;
	NSColor *textColor;
	CGFloat factor;
	CGFloat major;
	CGFloat thickness = [self cg_thickness];
	NSInteger subdivisions;
	NSInteger first;
	NSInteger last;
	NSInteger i;

	if (entry == nil || thickness <= 0.0) {
		return;
	}
	factor = [[entry objectForKey:@"factor"] doubleValue];
	major = [self cg_majorStepInUnits];
	subdivisions = [self cg_subdivisionsPerMajor];
	font = [NSFont systemFontOfSize:AG_RULER_FONT_SIZE];
	tickColor = [NSColor controlShadowColor];
	textColor = [NSColor controlTextColor];
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, textColor,
							       NSForegroundColorAttributeName, nil];
	/* **THE FIRST MARK IS THE FIRST MULTIPLE OF THE STEP AT OR AFTER THE DIRTY RECT'S START.** `ceil` on a negative
	 * quotient is what keeps it true to the left of the zero, where a `floor` would put the first mark before the
	 * rectangle and skip the one inside it. */
	first = (NSInteger)ceil((double)(([self cg_axisMinOfRect:rect] - _originOffset) / (major * factor)));
	last = (NSInteger)floor((double)(([self cg_axisMaxOfRect:rect] - _originOffset) / (major * factor)));
	if (last - first > 2000) {
		last = first + 2000;
	}
	[tickColor setFill];
	for (i = first; i <= last; i++) {
		CGFloat location = _originOffset + (CGFloat)i * major * factor;
		NSString *label;
		NSInteger k;

		for (k = 1; k < subdivisions; k++) {
			CGFloat minorLocation = location + (CGFloat)k * (major / (CGFloat)subdivisions) * factor;

			[self cg_fillTickAt:minorLocation length:AG_RULER_MINOR_TICK];
		}
		[self cg_fillTickAt:location length:AG_RULER_MAJOR_TICK];
		label = [self cg_labelForValue:(CGFloat)i * major entry:entry];
		[self cg_drawLabel:label at:location attributes:attributes];
	}
}

/* A NUMBER WITHOUT TRAILING ZEROS, WHICH IS WHAT A RULER SHOWS. A whole value prints as an integer; anything else as
 * `%g`, which drops the zeros the arithmetic produced. */
- (NSString *)cg_labelForValue:(CGFloat)value entry:(NSDictionary *)entry
{
	NSString *abbreviation = [entry objectForKey:@"abbreviation"];
	NSString *number;

	if (fabs((double)(value - round((double)value))) < 0.0005) {
		number = [NSString stringWithFormat:@"%ld", (long)llround((double)value)];
	} else {
		number = [NSString stringWithFormat:@"%g", (double)value];
	}
	if (abbreviation != nil && [abbreviation length] > 0) {
		return [number stringByAppendingString:abbreviation];
	}
	return number;
}

/* A TICK IS A ONE-POINT BAR GROWING IN FROM THE INSIDE EDGE, which is the edge nearest the document: the bottom for a
 * horizontal ruler, the right for a vertical one. */
- (void)cg_fillTickAt:(CGFloat)location length:(CGFloat)length
{
	CGFloat thickness = [self cg_thickness];
	NSRect tick;

	if (_orientation == NSVerticalRuler) {
		tick = NSMakeRect(thickness - length, location, length, 1.0);
	} else {
		tick = NSMakeRect(location, thickness - length, 1.0, length);
	}
	NSRectFill(tick);
}

/* AND A LABEL SITS ABOVE THE TICKS (horizontal) OR TO THE LEFT OF THEM (vertical). The vertical case centres the text
 * on the mark it names, which is the one place the two orientations genuinely read differently. THE HORIZONTAL CASE
 * USES `-baselineLocation`, which is measured from the inside edge so a marker reserve on the outside cannot push the
 * numbers into the markers' band. */
- (void)cg_drawLabel:(NSString *)label at:(CGFloat)location attributes:(NSDictionary *)attributes
{
	NSFont *font = [attributes objectForKey:NSFontAttributeName];
	CGFloat ascent = (font != nil) ? [font ascender] : AG_RULER_FONT_SIZE;
	NSAttributedString *text;

	if (label == nil || [label length] == 0) {
		return;
	}
	text = [[NSAttributedString alloc] initWithString:label attributes:attributes];
	if (_orientation == NSVerticalRuler) {
		NSSize size = [text size];
		CGFloat x = [self cg_thickness] - AG_RULER_LABEL_INSET - size.width;

		[text drawAtPoint:NSMakePoint(x, location + ascent * 0.35)];
	} else {
		[text drawAtPoint:NSMakePoint(location + AG_RULER_LABEL_GAP, [self baselineLocation])];
	}
	[text release];
}

/* ---- THE INK --------------------------------------------------------------------------------------------- */

- (void)drawRect:(NSRect)dirtyRect
{
	/* THE GROUND IS THE PLATFORM'S CONTROL FACE, the same one a table header wears, because a ruler is chrome and not a
	 * document. */
	[[NSColor controlColor] setFill];
	NSRectFill(dirtyRect);
	[self drawHashMarksAndLabelsInRect:dirtyRect];
	[self drawMarkersInRect:dirtyRect];
	if (_hasRulerLine) {
		[[NSColor darkGrayColor] setFill];
		NSRectFill([self cg_bandAtLocation:_rulerLineLocation]);
	}
}

- (void)drawMarkersInRect:(NSRect)rect
{
	NSUInteger i;

	for (i = 0; i < [_markers count]; i++) {
		NSRulerMarker *marker = [_markers objectAtIndex:i];
		NSRect markerRect = [marker imageRectInRuler];

		if (NSIsEmptyRect(markerRect) || !NSIntersectsRect(markerRect, rect)) {
			continue;
		}
		[marker drawRect:rect];
	}
}

/* **THE GUIDE LINE, IN TWO BANDS.** Moving a line means the old band has to lose it and the new one has to gain it, so
 * one call invalidates exactly two thin rectangles instead of the whole ruler. Passing the same location twice is how a
 * caller REMOVES it, which is Apple's own reading of the door and the one `-mouseUp:` uses. */
- (void)moveRulerlineFromLocation:(CGFloat)oldLocation toLocation:(CGFloat)newLocation
{
	NSRect oldBand = [self cg_bandAtLocation:oldLocation];
	NSRect newBand = [self cg_bandAtLocation:newLocation];

	if (_hasRulerLine) {
		[self setNeedsDisplayInRect:oldBand];
	}
	_hasRulerLine = (newLocation == newLocation);	/* NaN would mean "no line", and no caller passes one */
	_rulerLineLocation = newLocation;
	[self setNeedsDisplayInRect:newBand];
}

- (void)invalidateHashMarks
{
	[self setNeedsDisplay:YES];
}

@end
