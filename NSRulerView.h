/*
 * NSRulerView.h — A RULER, AND THE MARKERS THAT SIT ON IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE RULER IS THE STRIP BESIDE A DOCUMENT THAT MEASURES IT, AND IT IS TWO CLASSES RATHER THAN ONE.** The view owns
 * the geometry — which strip of the scroll view it is, how thick it is, what unit its hash marks are in, and where the
 * zero is — and the MARKER owns one thing placed on that geometry: an image, a location along the axis, and whether
 * the pointer may drag it. That split is Apple's and it is the right one, because a ruler with no markers is a
 * perfectly good ruler (a page-layout ruler showing inches) and a marker with no view is just an image and a number.
 *
 * **A RULER DOES NOT SCROLL; IT MOVES ITS WINDOW ONTO THE DOCUMENT.** The view is as thick as its strip and as long as
 * the scroll view's visible area, so it can never be a subview of the scrolling document. What moves instead is its
 * BOUNDS ORIGIN, which the scroll view keeps equal to the client's visible origin — so a marker at document location
 * 300 is drawn 300 points along the ruler's axis, and the ruler's own visible window is what makes the 300 land under
 * the right character. `-originOffset` is the one adjustable part of that mapping: it is added to the document
 * coordinate the ruler counts from, which is how a text ruler puts its zero at the text's left inset rather than at
 * the clip view's left edge.
 *
 * **THE UNIT TABLE IS A CLASS, BECAUSE A UNIT IS A FACT ABOUT MEASUREMENT AND NOT ABOUT ONE RULER.** Four units are
 * built in — inches, centimetres, points and picas — and
 * `+registerUnitWithName:abbreviation:unitToPointsConversionFactor:stepUpCycle:stepDownCycle:` adds a fifth for
 * anybody who wants one. The conversion factor is POINTS PER UNIT, which is the only number that has to be exact
 * (72 to the inch, 12 points to the pica, 72/2.54 to the centimetre); the two cycles are the multiples at which the
 * ticks step up to a longer mark and a label, and at which they subdivide between them.
 *
 * **BOTH ORIENTATIONS ARE FLIPPED, WHICH IS A STATED DEVIATION.** Apple's horizontal ruler is flipped and its vertical
 * one is not, so a vertical marker's location is measured upward from the bottom edge and every client that has a
 * y-down document (a text view, a table) must convert twice. Here the ruler is flipped in both orientations and a
 * marker location is a coordinate in the CLIENT's own direction — right for a horizontal ruler, down for a vertical
 * one — which is what `-isFlipped` then answers. The cost is one documented difference; the benefit is that the
 * geometry the manager computes (a tab stop's x) is the geometry the marker draws at.
 *
 * **THE MARKERS' DELEGATE IS THE CLIENT VIEW, AND IT IS AN INFORMAL PROTOCOL.** `NSRulerView` sends its client view
 * `-rulerView:shouldAddMarker:` and the rest of the eight `NSRulerViewClient` messages; there is no
 * `NSRulerViewDelegate` protocol in the 10.6 artefact (the manifest has no such protocol), which is why these are
 * `respondsToSelector:` questions here exactly as they are there. A client that answers nothing gets the defaults:
 * every add, move and remove is allowed and stays where it was put.
 */
#ifndef APPKIT_NSRULERVIEW_H
#define APPKIT_NSRULERVIEW_H

#import <AppKit/NSView.h>

NS_ASSUME_NONNULL_BEGIN

@class NSScrollView;

@class NSRulerView;
@class NSEvent;
@class NSImage;
@class NSRulerMarker;

/* **WHICH WAY THE RULER RUNS.** The values are Apple's, and the ORDER is the point: a horizontal ruler is the zero
 * case, which is why `NSHorizontalRuler` is 0 and a `memset` of the structure gives a horizontal one. */
enum {
	NSHorizontalRuler = 0,
	NSVerticalRuler = 1
};
typedef NSUInteger NSRulerOrientation;

/* **THE FOUR BUILT-IN UNITS.** Their values are the names Apple publishes, which is what `-measurementUnits` answers
 * and what `-setMeasurementUnits:` takes. */
extern NSString *const NSRulerViewUnitInches;
extern NSString *const NSRulerViewUnitCentimeters;
extern NSString *const NSRulerViewUnitPoints;
extern NSString *const NSRulerViewUnitPicas;

/* ==================================================================================================================
 * THE MARKER: ONE IMAGE AT ONE LOCATION, AND WHETHER THE POINTER MAY MOVE IT.
 * ================================================================================================================ */

@interface NSRulerMarker : NSObject
{
	NSRulerView *_ruler;		/* NOT RETAINED: the ruler owns its markers, so an owning back-pointer would be a cycle */
	CGFloat _markerLocation;	/* along the ruler's axis, in the client's own direction */
	NSImage *_image;		/* RETAINED: a marker may outlive the image it was given */
	NSPoint _imageOrigin;		/* where the image sits ACROSS the ruler, and its nudge along it */
	id _representedObject;		/* RETAINED: what the marker stands for — a tab stop, in the text system */
	BOOL _movable;
	BOOL _removable;
	BOOL _dragging;
}

/* **THE ONE WAY IN.** The image is drawn with its origin at the marker's location, offset by `imageOrigin`; the image's
 * own size is what makes up the rest of the rectangle, so an image is never stretched. `rulerView` is borrowed: the
 * ruler retains the marker when it is added, and a marker that arrived without one has to be added before it has a
 * geometry at all. */
- (instancetype)initWithRulerView:(nullable NSRulerView *)rulerView
		    markerLocation:(CGFloat)markerLocation
			     image:(nullable NSImage *)image
		       imageOrigin:(NSPoint)imageOrigin;

/* WHERE THE MARKER IS, ALONG THE AXIS — the one number a drag changes and the one a client reads back. */
- (CGFloat)markerLocation;
- (void)setMarkerLocation:(CGFloat)markerLocation;

/* THE PICTURE AND WHERE IT HANGS. `-imageRectInRuler` is the geometry the two produce together, in the ruler's own
 * coordinates, and it is what `-drawRect:` fills and what a hit test asks. */
- (nullable NSImage *)image;
- (void)setImage:(nullable NSImage *)image;
- (NSPoint)imageOrigin;
- (void)setImageOrigin:(NSPoint)imageOrigin;
- (NSRect)imageRectInRuler;

/* **HOW MUCH OF THE RULER'S THICKNESS THIS MARKER NEEDS.** A horizontal marker needs the image's height plus the
 * origin's y; a vertical one needs its width plus the origin's x. That is the number a ruler sums into
 * `-requiredThickness`, which is the number a scroll view sizes the strip by. */
- (CGFloat)thicknessRequiredInRuler;

/* **WHAT THE MARKER STANDS FOR.** Apple's text system puts an `NSTextTab` here, which is how a dragged marker becomes
 * a changed tab stop; the ruler never looks at it and a caller is free to put anything in it. */
- (nullable id)representedObject;
- (void)setRepresentedObject:(nullable id)representedObject;

/* WHETHER A DRAG OR A DELETE MAY TOUCH IT. Both default to YES, which is Apple's default. */
- (BOOL)isMovable;
- (void)setMovable:(BOOL)flag;
- (BOOL)isRemovable;
- (void)setRemovable:(BOOL)flag;

/* AND WHETHER IT IS BEING DRAGGED RIGHT NOW, which is a fact about the gesture and not about the marker. */
- (BOOL)isDragging;

/* THE MARKER'S OWN DRAWING, which is the image and nothing else. A marker with no image draws nothing, and its
 * thickness is zero. */
- (void)drawRect:(NSRect)rect;

/* THE RULER THAT OWNS IT — borrowed, and nil until the marker is added to one. */
- (nullable NSRulerView *)ruler;

/* **APPLE'S MODAL TRACKING LOOP, AND THIS TIER'S REFUSAL IS THE SAME ONE `NSCell` MAKES.** The era's implementation
 * runs its own `-nextEventMatchingMask:` loop from the mouse-down until the mouse-up; a loop built from a guessed event
 * source cannot be tested without a display and steals the run loop from the application that already owns it. The
 * DRAG IS REAL AND IT IS THE RULER'S (`-trackMarker:withMouseEvent:`, driven by the ruler's own `-mouseDragged:` and
 * `-mouseUp:`), so what is missing is only the modal spelling of it — and this door says so by name and answers NO. */
- (BOOL)trackMouse:(NSEvent *)theEvent adding:(BOOL)isAdding;

@end

/* ==================================================================================================================
 * THE RULER: A STRIP OF THE SCROLL VIEW, ITS UNITS, AND THE MARKERS ON IT.
 * ================================================================================================================ */

@interface NSRulerView : NSView
{
	NSScrollView *_scrollView;	/* NOT RETAINED: the scroll view owns the ruler as a subview */
	NSRulerOrientation _orientation;
	NSView *_clientView;		/* NOT RETAINED: the document, which the scroll view owns */
	NSMutableArray *_markers;	/* RETAINED */
	NSView *_accessoryView;		/* RETAINED, and also a subview */
	CGFloat _ruleThickness;
	CGFloat _reservedThicknessForMarkers;
	CGFloat _reservedThicknessForAccessoryView;
	CGFloat _originOffset;
	NSString *_measurementUnits;	/* RETAINED: one of the four names above, or a registered one */
	/* **THE DRAG SESSION.** The marker being dragged, where the pointer grabbed it along the axis, and the location
	 * the marker had when the drag began — the last of which is what makes the drag absolute rather than incremental,
	 * so a refused move does not accumulate an error. */
	NSRulerMarker *_draggedMarker;	/* NOT RETAINED: it is in `_markers`, which owns it */
	CGFloat _dragGrabOffset;
	CGFloat _dragStartLocation;
	CGFloat _dragStartAxis;
	BOOL _dragging;
	/* **AND THE TEMPORARY LINE A DRAG DRAWS.** `-moveRulerlineFromLocation:toLocation:` is the era's door for it, and
	 * one location is all it takes: the line exists while `_hasRulerLine` and is drawn in `-drawRect:`. */
	CGFloat _rulerLineLocation;
	BOOL _hasRulerLine;
}

/* **THE WAY IN, WHICH NAMES THE SCROLL VIEW AND THE ORIENTATION TOGETHER.** A ruler is only meaningful beside a
 * scroll view — that is where its thickness comes from and what keeps its bounds on the document — so the initialiser
 * takes one. `nil` is allowed and makes a standalone ruler, which is what a test wants and what a page-layout canvas
 * with its own scrolling would need. */
- (instancetype)initWithScrollView:(nullable NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation;

/* THE TWO HALVES OF THE RELATIONSHIP: the scroll view that hosts the strip, and the view it measures. */
- (nullable NSScrollView *)scrollView;
- (void)setScrollView:(nullable NSScrollView *)scrollView;
- (nullable NSView *)clientView;
- (void)setClientView:(nullable NSView *)clientView;

/* WHICH WAY IT RUNS. Setting it re-orients the view in its strip, which is a layout change and not an ink change. */
- (NSRulerOrientation)orientation;
- (void)setOrientation:(NSRulerOrientation)orientation;

/* ==================================================================================================================
 * THE THICKNESS ARITHMETIC, WHICH IS THE ONE SUM TWO CLASSES HAVE TO AGREE ON.
 *
 * `-requiredThickness` is `ruleThickness + reservedThicknessForMarkers + reservedThicknessForAccessoryView`, and it is
 * what the scroll view sizes the strip by. THE THREE PARTS ARE SEPARATE BECAUSE THEY ARE SPENT DIFFERENTLY: the rule
 * thickness is the hash marks and their labels, the marker reserve is room for marker images that overhang, and the
 * accessory reserve is room for the accessory view, which is a real subview and would otherwise be squeezed.
 * ================================================================================================================ */

- (CGFloat)ruleThickness;
- (void)setRuleThickness:(CGFloat)thickness;
- (CGFloat)reservedThicknessForMarkers;
- (void)setReservedThicknessForMarkers:(CGFloat)thickness;
- (CGFloat)reservedThicknessForAccessoryView;
- (void)setReservedThicknessForAccessoryView:(CGFloat)thickness;
- (CGFloat)requiredThickness;

/* **THE ACCESSORY IS A SUBVIEW IN THE RESERVED STRIP.** Apple draws the accessory at the ruler's outside edge; here it
 * is added as a subview and given the reserved band by `-setAccessoryView:`, which is the same placement with one less
 * drawing path. `nil` removes it and releases the reserve back by answering zero for it. */
- (nullable NSView *)accessoryView;
- (void)setAccessoryView:(nullable NSView *)accessoryView;

/* ==================================================================================================================
 * THE MARKERS, AND THE FOUR QUESTIONS THE CLIENT VIEW IS ASKED ABOUT EACH CHANGE.
 * ================================================================================================================ */

- (NSArray *)markers;
- (void)setMarkers:(NSArray *)markers;
- (void)addMarker:(NSRulerMarker *)marker;
- (void)removeMarker:(NSRulerMarker *)marker;

/* **THE DRAG, SPLIT INTO THE PART A CALLER CAN START AND THE PART THE EVENT STREAM DRIVES.** `-trackMarker:` begins a
 * session from the mouse-down that landed on a marker: it asks the client whether the marker may move, sends it the
 * `willMove` question and returns YES. From then on the ruler's own `-mouseDragged:` and `-mouseUp:` move it and end
 * the session, which is the shape `NSTextAttachment` and `NSTextView` already use for a cell's tracking. */
- (BOOL)trackMarker:(NSRulerMarker *)marker withMouseEvent:(nullable NSEvent *)event;

/* ==================================================================================================================
 * THE UNITS AND THE HASH MARKS.
 * ================================================================================================================ */

- (NSString *)measurementUnits;
- (void)setMeasurementUnits:(NSString *)unitName;

/* **THE ZERO'S PLACE.** The ruler counts from its client's origin plus this offset, so a text ruler that wants its
 * zero at the first character sets the document's left inset here rather than subtracting it at every mark. */
- (CGFloat)originOffset;
- (void)setOriginOffset:(CGFloat)originOffset;

/* **A UNIT IS A CONVERSION, AN ABBREVIATION, AND TWO CYCLES.** Points per unit; the label suffix; the multiples at
 * which ticks step up (longer, and labelled); and the finer multiples drawn between them. Registering a name that is
 * already there REPLACES it, which is what makes a caller able to redefine "Inches" for a scaled canvas. */
+ (void)registerUnitWithName:(NSString *)unitName
	       abbreviation:(NSString *)abbreviation
unitToPointsConversionFactor:(CGFloat)conversionFactor
		stepUpCycle:(NSArray *)stepUpCycle
	      stepDownCycle:(NSArray *)stepDownCycle;

/* **THE INK, IN TWO HALVES A SUBCLASS CAN REPLACE SEPARATELY.** `-drawRect:` fills the ground and then calls these
 * twice, so a subclass that wants different hash marks keeps the markers working and vice versa. The rects are in the
 * ruler's own coordinates, which are the client's coordinates along the axis. */
- (void)drawHashMarksAndLabelsInRect:(NSRect)rect;
- (void)drawMarkersInRect:(NSRect)rect;

/* **THE DRAG'S GUIDE LINE.** Apple's door moves one line from where it was to where it is going, in one call, which is
 * exactly the invalidation a drag wants: two thin bands and no full redraw. */
- (void)moveRulerlineFromLocation:(CGFloat)oldLocation toLocation:(CGFloat)newLocation;

/* **WHERE A LABEL'S BASELINE SITS**, in the ruler's own coordinates. For a horizontal ruler it is the y of the text; for
 * a vertical one, the labels being horizontal too, it is the x the label column starts at. A subclass that overrides
 * `-drawHashMarksAndLabelsInRect:` reads it instead of recomputing the same inset. */
- (CGFloat)baselineLocation;

/* **THE DOCUMENT MOVED, SO THE MARKS UNDER IT DID.** The scroll view calls this when the clip view's origin changes;
 * a caller that changed the client's geometry calls it too. */
- (void)invalidateHashMarks;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSRULERVIEW_H */
