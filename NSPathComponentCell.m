/*
 * NSPathComponentCell — one component of a path bar.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * The title is the inherited string value. This file adds the picture and the URL and the one piece of drawing the
 * path cell asks for: `-drawInteriorWithFrame:inView:`. The background and the separators belong to the path cell,
 * so a component never paints a field's bezel across a breadcrumb bar.
 */
#import <AppKit/NSPathComponentCell.h>

#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <math.h>

#define AG_PATH_COMPONENT_PADDING	4.0
#define AG_PATH_COMPONENT_GAP		4.0

@implementation NSPathComponentCell

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		[self setBordered:NO];
		[self setBezeled:NO];
		[self setDrawsBackground:NO];
		[self setEditable:NO];
		[self setAlignment:NSLeftTextAlignment];
		_url = nil;
	}
	return self;
}

- (void)dealloc
{
	[_url release];
	[super dealloc];
}

- (NSImage *)image
{
	return [super image];
}

- (void)setImage:(NSImage *)value
{
	[super setImage:value];
	if (_controlView != nil && [_controlView respondsToSelector:@selector(setNeedsDisplay:)]) {
		[(NSView *)_controlView setNeedsDisplay:YES];
	}
}

- (NSURL *)URL
{
	return _url;
}

- (void)setURL:(NSURL *)url
{
	[url retain];
	[_url release];
	_url = url;
}

/* THE PICTURE'S BOX FOLLOWS THE CONTROL SIZE, which is what the era's path bar does: 16 points regular, 14 small,
 * 12 mini. A component with no image reserves no width for one. */
- (CGFloat)cg_imageSide
{
	switch ([self controlSize]) {
	case NSSmallControlSize:
		return 14.0;
	case NSMiniControlSize:
		return 12.0;
	default:
		return 16.0;
	}
}

- (NSFont *)cg_font
{
	NSFont *font = (NSFont *)[self font];

	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	return font;
}

- (NSSize)cg_contentSize
{
	NSFont *font = [self cg_font];
	NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
	NSString *text = [self stringValue];
	NSSize textSize = NSZeroSize;
	NSSize imageSize = NSZeroSize;
	CGFloat width;
	CGFloat height;

	if (text != nil && [text length] > 0) {
		textSize = [text sizeWithAttributes:attributes];
	}
	if ([self image] != nil) {
		CGFloat side = [self cg_imageSide];

		imageSize = NSMakeSize(side, side);
	}
	width = imageSize.width + (imageSize.width > 0.0 && textSize.width > 0.0 ? AG_PATH_COMPONENT_GAP : 0.0)
		+ textSize.width;
	height = fmax(imageSize.height, textSize.height);
	if (width <= 0.0) {
		width = 16.0;
	}
	if (height <= 0.0) {
		height = [font ascender] + (CGFloat)fabs((double)[font descender]);
	}
	return NSMakeSize(width, height);
}

- (NSSize)cellSize
{
	return [self cellSizeForBounds:NSMakeRect(0.0, 0.0, 10000.0, 10000.0)];
}

- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize content = [self cg_contentSize];
	NSSize result = NSMakeSize(content.width + 2.0 * AG_PATH_COMPONENT_PADDING,
				   content.height + 4.0);

	if (aRect.size.width > 0.0 && result.width > aRect.size.width) {
		result.width = aRect.size.width;
	}
	if (aRect.size.height > 0.0 && result.height > aRect.size.height) {
		result.height = aRect.size.height;
	}
	return result;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSFont *font = [self cg_font];
	NSDictionary *attributes;
	NSString *text = [self stringValue];
	NSSize content = [self cg_contentSize];
	NSRect contentRect;
	CGFloat x;
	NSColor *ink;

	(void)controlView;
	if (![self isEnabled]) {
		ink = [NSColor disabledControlTextColor];
	} else if ([self isHighlighted]) {
		ink = [NSColor selectedControlTextColor];
	} else {
		ink = [NSColor controlTextColor];
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:
		font, NSFontAttributeName, ink, NSForegroundColorAttributeName, nil];
	contentRect = NSMakeRect(NSMinX(cellFrame) + AG_PATH_COMPONENT_PADDING,
				 NSMidY(cellFrame) - content.height / 2.0,
				 NSMaxX(cellFrame) - NSMinX(cellFrame) - 2.0 * AG_PATH_COMPONENT_PADDING,
				 content.height);
	if (contentRect.size.width < 0.0) {
		contentRect.size.width = 0.0;
	}
	x = NSMinX(contentRect);
	if ([self image] != nil) {
		CGFloat side = [self cg_imageSide];
		NSRect imageRect = NSMakeRect(x, NSMidY(contentRect) - side / 2.0, side, side);

		[[self image] drawInRect:imageRect];
		x += side + ((text != nil && [text length] > 0) ? AG_PATH_COMPONENT_GAP : 0.0);
	}
	if (text != nil && [text length] > 0) {
		CGFloat ascender = [font ascender];
		CGFloat descent = (CGFloat)fabs((double)[font descender]);
		CGFloat baseline = NSMidY(contentRect) - (ascender - descent) / 2.0;

		[text drawAtPoint:NSMakePoint(x, baseline) withAttributes:attributes];
	}
}

@end
