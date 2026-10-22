/*
 * NSImageCell — an image, aligned, scaled and framed.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * The drawing is the whole class: the base's `-drawWithFrame:inView:` paints the bezel and then asks
 * `-drawInteriorWithFrame:inView:`, which this class overrides to place the image by the three facts. The frame styles are
 * the platform's drawing helpers where one exists (`NSDrawGrayBezel` and friends) and a path otherwise.
 */
#import "NSImageCell.h"
#import "NSImage.h"
#import "NSColor.h"
#import "NSBezierPath.h"
#import "NSGraphics.h"
#import "NSGraphicsContext.h"

@implementation NSImageCell

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_imageAlignment = NSImageAlignLeft;
		_imageScaling = NSImageScaleNone;
		_imageFrameStyle = NSImageFrameNone;
	}
	return self;
}

- (id)copy
{
	NSImageCell *copy = [super copy];

	copy->_imageAlignment = _imageAlignment;
	copy->_imageScaling = _imageScaling;
	copy->_imageFrameStyle = _imageFrameStyle;
	return copy;
}

- (NSCellImageAlignment)imageAlignment
{
	return _imageAlignment;
}

- (void)setImageAlignment:(NSCellImageAlignment)alignment
{
	_imageAlignment = alignment;
}

- (NSImageScaling)imageScaling
{
	return _imageScaling;
}

- (void)setImageScaling:(NSImageScaling)scaling
{
	_imageScaling = scaling;
}

- (NSImageFrameStyle)imageFrameStyle
{
	return _imageFrameStyle;
}

- (void)setImageFrameStyle:(NSImageFrameStyle)frameStyle
{
	_imageFrameStyle = frameStyle;
}

/* ---- THE INK ------------------------------------------------------------------------------------ */

/* **THE RECT THE IMAGE OCCUPIES, FROM THE TWO FACTS THAT DECIDE IT.** Scaling first: `NSImageScaleNone` keeps the image's own
 * size, `NSImageScaleAxesIndependently` fills the box, and the two proportional modes fit inside it (up-or-down may enlarge,
 * down-only may not). Alignment then places that rect in the box — nine cases, two of which are the mid-edges. */
- (NSRect)cg_imageRectInFrame:(NSRect)frame imageSize:(NSSize)size
{
	NSRect where = NSMakeRect(NSMinX(frame), NSMinY(frame), size.width, size.height);
	CGFloat sx;
	CGFloat sy;
	CGFloat scale;

	if (size.width <= 0.0 || size.height <= 0.0 || NSWidth(frame) <= 0.0 || NSHeight(frame) <= 0.0) {
		return NSZeroRect;
	}
	sx = NSWidth(frame) / size.width;
	sy = NSHeight(frame) / size.height;
	switch (_imageScaling) {
	case NSImageScaleAxesIndependently:
		where.size.width = NSWidth(frame);
		where.size.height = NSHeight(frame);
		break;
	case NSImageScaleProportionallyDown:
		scale = (sx < sy) ? sx : sy;
		if (scale > 1.0) {
			scale = 1.0;
		}
		where.size.width = size.width * scale;
		where.size.height = size.height * scale;
		break;
	case NSImageScaleProportionallyUpOrDown:
		scale = (sx < sy) ? sx : sy;
		where.size.width = size.width * scale;
		where.size.height = size.height * scale;
		break;
	case NSImageScaleNone:
	default:
		break;
	}
	switch (_imageAlignment) {
	case NSImageAlignCenter:
		where.origin.x = NSMidX(frame) - NSWidth(where) / 2.0;
		where.origin.y = NSMidY(frame) - NSHeight(where) / 2.0;
		break;
	case NSImageAlignTop:
		where.origin.x = NSMidX(frame) - NSWidth(where) / 2.0;
		where.origin.y = NSMaxY(frame) - NSHeight(where);
		break;
	case NSImageAlignTopLeft:
		where.origin.x = NSMinX(frame);
		where.origin.y = NSMaxY(frame) - NSHeight(where);
		break;
	case NSImageAlignTopRight:
		where.origin.x = NSMaxX(frame) - NSWidth(where);
		where.origin.y = NSMaxY(frame) - NSHeight(where);
		break;
	case NSImageAlignBottom:
		where.origin.x = NSMidX(frame) - NSWidth(where) / 2.0;
		where.origin.y = NSMinY(frame);
		break;
	case NSImageAlignBottomLeft:
		where.origin.x = NSMinX(frame);
		where.origin.y = NSMinY(frame);
		break;
	case NSImageAlignBottomRight:
		where.origin.x = NSMaxX(frame) - NSWidth(where);
		where.origin.y = NSMinY(frame);
		break;
	case NSImageAlignRight:
		where.origin.x = NSMaxX(frame) - NSWidth(where);
		where.origin.y = NSMidY(frame) - NSHeight(where) / 2.0;
		break;
	case NSImageAlignLeft:
	default:
		where.origin.x = NSMinX(frame);
		where.origin.y = NSMidY(frame) - NSHeight(where) / 2.0;
		break;
	}
	return NSIntersectionRect(where, frame);	/* an image never paints outside the cell it belongs to */
}

/* **THE FRAME IS THE CELL'S FIRST INK**, then the image inside it. The bezel helpers are the platform's own, so a cell's
 * frame looks like every other frame in the tier. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	switch (_imageFrameStyle) {
	case NSImageFrameGrayBezel:
		NSDrawGrayBezel(cellFrame, cellFrame);
		cellFrame = NSInsetRect(cellFrame, 2.0, 2.0);
		break;
	case NSImageFrameGroove:
		NSDrawGroove(cellFrame, cellFrame);
		cellFrame = NSInsetRect(cellFrame, 2.0, 2.0);
		break;
	case NSImageFrameButton:
		NSDrawButton(cellFrame, cellFrame);
		cellFrame = NSInsetRect(cellFrame, 2.0, 2.0);
		break;
	case NSImageFramePhoto:
		/* **A PHOTO'S FRAME IS A THIN LINE AND A WHITE MATTE**, which is what the era drew. */
		[[NSColor whiteColor] setFill];
		NSRectFill(cellFrame);
		[[NSColor blackColor] setStroke];
		[[NSBezierPath bezierPathWithRect:NSInsetRect(cellFrame, 0.5, 0.5)] stroke];
		cellFrame = NSInsetRect(cellFrame, 2.0, 2.0);
		break;
	case NSImageFrameNone:
	default:
		break;
	}
	[self drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSImage *image = [self image];
	NSRect where;

	(void)controlView;
	if (image == nil) {
		return;
	}
	where = [self cg_imageRectInFrame:cellFrame imageSize:[image size]];
	if (NSWidth(where) > 0.0 && NSHeight(where) > 0.0) {
		[image drawInRect:where];
	}
}

@end
