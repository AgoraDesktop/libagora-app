/*
 * NSImageComposition.m — the nine-slice and three-slice image composers.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * SPDX-License-Identifier: MIT
 *
 * **A NINE-SLICE ASSET IS HOW THE ERA KEPT A BUTTON'S CORNERS FROM SMEARING**, and the contract is entirely about which
 * rectangle each slice lands in: the four corners at their natural size, the four edges stretched along their axis
 * between them, and the centre stretched both ways. Apple declares the pair in `NSCell.h` because a cell's face was the
 * thing that used them.
 *
 * **THE SCALING COMES FROM `-drawInRect:` AND THE BLEND FROM THE CONTEXT**, which is the only combination this tier
 * can compose: `-drawInRect:` scales but takes no operation or fraction, and `-compositeToPoint:…` takes both but draws
 * at the image's natural size. Setting the alpha and the blend mode on the current `CGContext` around `-drawInRect:`
 * gets all three at once, and restoring the state afterwards means the caller's ink and clip are untouched.
 *
 * **`flipped` IS ACCEPTED AND NOT NEEDED, WHICH IS A DEVIATION WITH A REASON.** Apple's flag says whether the frame is
 * in a flipped coordinate system; `-drawInRect:` draws through the CURRENT transform, so the same rectangle lands
 * correctly in either orientation and re-ordering the slices would be the bug rather than the fix. The parameter stays
 * because a ported caller passes it.
 *
 * **A SLICE WITH NO IMAGE IS SKIPPED RATHER THAN SUBSTITUTED**, so a caller that wants a flat centre passes nil for the
 * fills it has not got and gets a frame with corners only. A negative extent — a frame narrower than its own corners —
 * collapses rather than drawing backwards, which is what `NSIntersectionRect` with the frame gives.
 */
#import <AppKit/NSCell.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/Foundation.h>

#import <CoreGraphics/CGContext.h>

/* The subset of the compositing vocabulary a slice can be drawn with; anything else is source-over, which is the
 * quiet answer and the one a caller asking for a face expects. */
static CGBlendMode fn_slice_blend(NSCompositingOperation op)
{
	switch (op) {
	case NSCompositingOperationCopy:		return kCGBlendModeCopy;
	case NSCompositingOperationSourceIn:		return kCGBlendModeSourceIn;
	case NSCompositingOperationSourceOut:		return kCGBlendModeSourceOut;
	case NSCompositingOperationSourceAtop:		return kCGBlendModeSourceAtop;
	case NSCompositingOperationDestinationOver:	return kCGBlendModeDestinationOver;
	case NSCompositingOperationDestinationIn:	return kCGBlendModeDestinationIn;
	case NSCompositingOperationDestinationOut:	return kCGBlendModeDestinationOut;
	case NSCompositingOperationDestinationAtop:	return kCGBlendModeDestinationAtop;
	case NSCompositingOperationXOR:			return kCGBlendModeXOR;
	case NSCompositingOperationPlusDarker:		return kCGBlendModePlusDarker;
	case NSCompositingOperationPlusLighter:		return kCGBlendModePlusLighter;
	case NSCompositingOperationSourceOver:
	default:					return kCGBlendModeNormal;
	}
}

static void fn_slice(NSImage *image, NSRect destination, NSCompositingOperation op, CGFloat alpha)
{
	NSGraphicsContext *context;
	CGContextRef cg;

	if (image == nil || destination.size.width <= 0.0 || destination.size.height <= 0.0) {
		return;
	}
	context = [NSGraphicsContext currentContext];
	cg = context != nil ? [context CGContext] : NULL;
	if (cg != NULL) {
		CGContextSaveGState(cg);
		CGContextSetAlpha(cg, alpha);
		CGContextSetBlendMode(cg, fn_slice_blend(op));
	}
	[image drawInRect:destination];
	if (cg != NULL) {
		CGContextRestoreGState(cg);
	}
}

/* A slice's natural extent on one axis, or zero when there is no image. */
static CGFloat fn_extent_width(NSImage *image)
{
	return image != nil ? [image size].width : 0.0;
}

static CGFloat fn_extent_height(NSImage *image)
{
	return image != nil ? [image size].height : 0.0;
}

void NSDrawThreePartImage(NSRect frame, NSImage *startCap, NSImage *centerFill, NSImage *endCap, BOOL vertical,
			  NSCompositingOperation op, CGFloat alphaFraction, BOOL flipped)
{
	CGFloat startExtent, endExtent, thickness, middle;
	NSRect startRect, centerRect, endRect;

	(void)flipped;
	if (vertical) {
		startExtent = fn_extent_height(startCap);
		endExtent = fn_extent_height(endCap);
		thickness = frame.size.width;
	} else {
		startExtent = fn_extent_width(startCap);
		endExtent = fn_extent_width(endCap);
		thickness = frame.size.height;
	}
	middle = (vertical ? frame.size.height : frame.size.width) - startExtent - endExtent;
	if (middle < 0.0) {
		middle = 0.0;
	}
	if (vertical) {
		/* Start at the TOP of the frame: a non-flipped frame has its origin at the bottom, so the start cap sits at the
		 * high end and the end cap at the low one — which is what "start" means for a vertical three-part image. */
		startRect = NSMakeRect(frame.origin.x, NSMaxY(frame) - startExtent, thickness, startExtent);
		centerRect = NSMakeRect(frame.origin.x, frame.origin.y + endExtent, thickness, middle);
		endRect = NSMakeRect(frame.origin.x, frame.origin.y, thickness, endExtent);
	} else {
		startRect = NSMakeRect(frame.origin.x, frame.origin.y, startExtent, thickness);
		centerRect = NSMakeRect(frame.origin.x + startExtent, frame.origin.y, middle, thickness);
		endRect = NSMakeRect(NSMaxX(frame) - endExtent, frame.origin.y, endExtent, thickness);
	}
	fn_slice(startCap, startRect, op, alphaFraction);
	fn_slice(centerFill, centerRect, op, alphaFraction);
	fn_slice(endCap, endRect, op, alphaFraction);
}

void NSDrawNinePartImage(NSRect frame, NSImage *topLeftCorner, NSImage *topEdgeFill, NSImage *topRightCorner,
			 NSImage *leftEdgeFill, NSImage *centerFill, NSImage *rightEdgeFill,
			 NSImage *bottomLeftCorner, NSImage *bottomEdgeFill, NSImage *bottomRightCorner,
			 NSCompositingOperation op, CGFloat alphaFraction, BOOL flipped)
{
	CGFloat left = fn_extent_width(topLeftCorner);
	CGFloat right = fn_extent_width(topRightCorner);
	CGFloat top = fn_extent_height(topLeftCorner);
	CGFloat bottom = fn_extent_height(bottomLeftCorner);
	CGFloat horizontal = frame.size.width - left - right;
	CGFloat vertical = frame.size.height - top - bottom;
	CGFloat minX = frame.origin.x, maxX = NSMaxX(frame);
	CGFloat minY = frame.origin.y, maxY = NSMaxY(frame);

	(void)flipped;
	if (horizontal < 0.0) {
		horizontal = 0.0;
	}
	if (vertical < 0.0) {
		vertical = 0.0;
	}

	/* THE CORNERS AT THEIR NATURAL SIZE, in the frame's own corners. */
	fn_slice(topLeftCorner, NSMakeRect(minX, maxY - top, left, top), op, alphaFraction);
	fn_slice(topRightCorner, NSMakeRect(maxX - right, maxY - top, right, top), op, alphaFraction);
	fn_slice(bottomLeftCorner, NSMakeRect(minX, minY, left, bottom), op, alphaFraction);
	fn_slice(bottomRightCorner, NSMakeRect(maxX - right, minY, right, bottom), op, alphaFraction);

	/* THE EDGES STRETCHED ALONG THEIR OWN AXIS between the corners. */
	fn_slice(topEdgeFill, NSMakeRect(minX + left, maxY - top, horizontal, top), op, alphaFraction);
	fn_slice(bottomEdgeFill, NSMakeRect(minX + left, minY, horizontal, bottom), op, alphaFraction);
	fn_slice(leftEdgeFill, NSMakeRect(minX, minY + bottom, left, vertical), op, alphaFraction);
	fn_slice(rightEdgeFill, NSMakeRect(maxX - right, minY + bottom, right, vertical), op, alphaFraction);

	/* AND THE CENTRE STRETCHED BOTH WAYS. */
	fn_slice(centerFill, NSMakeRect(minX + left, minY + bottom, horizontal, vertical), op, alphaFraction);
}
