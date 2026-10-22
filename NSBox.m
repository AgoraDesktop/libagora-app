/*
 * NSBox — a frame around other views, with an optional title.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * The box is geometry and ink: `-borderRect` and `-titleRect` are the two rectangles everything else is derived from, the
 * content view is a subview laid out inside them, and the five kinds are drawn with the platform's own helpers. The title
 * is an `NSCell`, so its face and alignment are the cell's — which is what makes `-titleFont` a convenience rather than a
 * second source of truth.
 */
#import "NSBox.h"
#import "NSCell.h"
#import "NSColor.h"
#import "NSFont.h"
#import "NSBezierPath.h"
#import "NSGraphicsContext.h"
#import "NSStringDrawing.h"
#import "NSAttributedString.h"

#define AG_BOX_TITLE_GAP 3.0

@implementation NSBox

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_boxType = NSBoxPrimary;
		_borderType = NSGrooveBorder;
		_borderWidth = 1.0;
		_cornerRadius = 0.0;
		_titlePosition = NSAtTop;
		_titleCell = [[NSCell alloc] initTextCell:@""];
		_titleFont = [[NSFont systemFontOfSize:12.0] retain];
		[_titleCell setFont:_titleFont];
		[_titleCell setAlignment:NSCenterTextAlignment];
		_contentViewMargins = NSMakeSize(8.0, 6.0);
		_transparent = NO;
		_fillColor = nil;
		_borderColor = nil;
		_contentView = [[NSView alloc] initWithFrame:[self contentRect]];
		[self addSubview:_contentView];
	}
	return self;
}

- (void)dealloc
{
	[_titleCell release];
	[_titleFont release];
	[_fillColor release];
	[_borderColor release];
	[_contentView release];
	[super dealloc];
}

/* ---- THE KIND AND THE NUMBERS --------------------------------------------------------------------- */

- (NSBoxType)boxType { return _boxType; }
- (void)setBoxType:(NSBoxType)boxType { _boxType = boxType; [self setNeedsDisplay:YES]; }
- (NSBorderType)borderType { return _borderType; }
- (void)setBorderType:(NSBorderType)borderType { _borderType = borderType; [self setNeedsDisplay:YES]; }
- (CGFloat)borderWidth { return _borderWidth; }
- (void)setBorderWidth:(CGFloat)borderWidth { _borderWidth = borderWidth; [self setNeedsDisplay:YES]; }
- (CGFloat)cornerRadius { return _cornerRadius; }
- (void)setCornerRadius:(CGFloat)radius { _cornerRadius = radius; [self setNeedsDisplay:YES]; }

- (NSColor *)fillColor { return _fillColor; }
- (void)setFillColor:(NSColor *)color
{
	NSColor *held = [color retain];

	[_fillColor release];
	_fillColor = held;
	[self setNeedsDisplay:YES];
}

- (NSColor *)borderColor { return _borderColor; }
- (void)setBorderColor:(NSColor *)color
{
	NSColor *held = [color retain];

	[_borderColor release];
	_borderColor = held;
	[self setNeedsDisplay:YES];
}

- (BOOL)isTransparent { return _transparent; }
- (void)setTransparent:(BOOL)flag { _transparent = flag ? YES : NO; [self setNeedsDisplay:YES]; }

/* ---- THE TITLE ------------------------------------------------------------------------------------ */

- (NSString *)title { return [_titleCell stringValue]; }
- (void)setTitle:(NSString *)title
{
	[_titleCell setStringValue:(title != nil) ? title : @""];
	[self cg_layOutContent];
	[self setNeedsDisplay:YES];
}

/* THE MARKER RULE, ONCE (the same one the field's `-setTitleWithMnemonic:` uses). */
- (void)setTitleWithMnemonic:(NSString *)title
{
	NSMutableString *plain = [NSMutableString string];
	NSUInteger i = 0;

	while (title != nil && i < [title length]) {
		unichar c = [title characterAtIndex:i];

		if (c == '&') {
			if (i + 1 < [title length] && [title characterAtIndex:i + 1] == '&') {
				[plain appendString:@"&"];
				i += 2;
				continue;
			}
			i += 1;
			continue;
		}
		[plain appendFormat:@"%C", c];
		i += 1;
	}
	[self setTitle:plain];
}

- (NSTitlePosition)titlePosition { return _titlePosition; }
- (void)setTitlePosition:(NSTitlePosition)position
{
	_titlePosition = position;
	[self cg_layOutContent];
	[self setNeedsDisplay:YES];
}

- (NSCell *)titleCell { return _titleCell; }

- (NSFont *)titleFont { return _titleFont; }
- (void)setTitleFont:(NSFont *)font
{
	NSFont *held = [(font != nil) ? font : [NSFont systemFontOfSize:12.0] retain];

	[_titleFont release];
	_titleFont = held;
	[_titleCell setFont:_titleFont];
	[self cg_layOutContent];
	[self setNeedsDisplay:YES];
}

/* ---- THE CONTENT VIEW ----------------------------------------------------------------------------- */

- (void)setContentView:(NSView *)view
{
	if (view == _contentView) {
		return;
	}
	[_contentView removeFromSuperview];
	[_contentView release];
	_contentView = [view retain];
	if (_contentView != nil) {
		[_contentView setFrame:[self contentRect]];
		[self addSubview:_contentView];
	}
}

- (NSView *)contentView { return _contentView; }
- (NSSize)contentViewMargins { return _contentViewMargins; }
- (void)setContentViewMargins:(NSSize)offsetSize
{
	_contentViewMargins = offsetSize;
	[self cg_layOutContent];
	[self setNeedsDisplay:YES];
}

/* ---- THE THREE RECTANGLES ------------------------------------------------------------------------- */

/* **THE BORDER IS THE BOX'S OWN BOUNDS**, because a box's frame IS its border — which is why `-borderRect` answers the
 * bounds rather than an inset. The one adjustment is the title band at the top: `NSAboveTop` draws the title OUTSIDE the
 * border, so the border starts below the title band there. */
- (NSRect)borderRect
{
	return [self bounds];
}

/* **THE TITLE'S BAND.** A title is drawn in a band the height of its font, at the position asked for: above the top edge
 * (outside), across the top edge (the classic form, in a gap in the border), below it, or at the bottom's three positions.
 * `NSNoTitle` answers an empty rect, which is what "there is no title" means. */
- (NSRect)titleRect
{
	NSRect bounds = [self bounds];
	CGFloat height = [_titleFont ascender] - [_titleFont descender];
	CGFloat width = 0.0;
	NSRect band;

	if (_titlePosition == NSNoTitle || [[self title] length] == 0) {
		return NSZeroRect;
	}
	if ([_titleCell respondsToSelector:@selector(cellSize)]) {
		width = [_titleCell cellSize].width;
	}
	if (width <= 0.0) {
		width = [[self title] sizeWithAttributes:
			[NSDictionary dictionaryWithObject:_titleFont forKey:NSFontAttributeName]].width;
	}
	width += 2.0 * AG_BOX_TITLE_GAP;
	band = NSMakeRect(NSMidX(bounds) - width / 2.0, 0.0, width, height + 2.0);
	switch (_titlePosition) {
	case NSAboveTop:
		band.origin.y = NSMaxY(bounds);
		break;
	case NSAtTop:
		band.origin.y = NSMaxY(bounds) - height / 2.0;
		break;
	case NSBelowTop:
		band.origin.y = NSMaxY(bounds) - height - 2.0;
		break;
	case NSAboveBottom:
		band.origin.y = NSMinY(bounds) + height + 2.0;
		break;
	case NSAtBottom:
		band.origin.y = NSMinY(bounds) - height / 2.0;
		break;
	case NSBelowBottom:
		band.origin.y = NSMinY(bounds) - height - 2.0;
		break;
	case NSNoTitle:
	default:
		return NSZeroRect;
	}
	return NSIntersectionRect(band, NSInsetRect(bounds, -width, -height));
}

/* **THE CONTENT'S RECTANGLE IS THE BORDER'S LESS THE MARGINS AND THE TITLE'S BAND**, and it is private because Apple has no
 * public door for it — `-contentView`'s frame is the answer a caller reads. */
- (NSRect)contentRect
{
	NSRect bounds = [self bounds];
	NSRect content;
	CGFloat titleBand = 0.0;

	switch (_titlePosition) {
	case NSAtTop:
		titleBand = ([_titleFont ascender] - [_titleFont descender]) / 2.0;
		break;
	case NSBelowTop:
		titleBand = [_titleFont ascender] - [_titleFont descender] + 2.0;
		break;
	case NSAboveTop:
	case NSNoTitle:
	default:
		titleBand = 0.0;
		break;
	}
	/* **THE TITLE'S BAND IS TAKEN OFF THE TOP ONLY**, which is the arithmetic `-setFrameFromContentFrame:` inverts: an
	 * `NSInsetRect` with the band in BOTH margins would subtract it twice and the round trip would not close — MEASURED, it
	 * left the content 7 points shorter than the frame it was asked for. */
	content = NSMakeRect(NSMinX(bounds) + _borderWidth + _contentViewMargins.width,
			     NSMinY(bounds) + _borderWidth + _contentViewMargins.height,
			     NSWidth(bounds) - 2.0 * (_borderWidth + _contentViewMargins.width),
			     NSHeight(bounds) - 2.0 * (_borderWidth + _contentViewMargins.height) - titleBand);
	return content;
}

- (void)cg_layOutContent
{
	if (_contentView != nil) {
		[_contentView setFrame:[self contentRect]];
	}
}

/* THE INVERSE: given a content rectangle, what frame makes the box? It is the content plus the margins, the border and the
 * title band — the same numbers `-contentRect` subtracts, in the other direction. */
- (void)setFrameFromContentFrame:(NSRect)contentFrame
{
	NSRect frame = [self frame];
	CGFloat titleBand = 0.0;

	switch (_titlePosition) {
	case NSAtTop:
		titleBand = ([_titleFont ascender] - [_titleFont descender]) / 2.0;
		break;
	case NSBelowTop:
		titleBand = [_titleFont ascender] - [_titleFont descender] + 2.0;
		break;
	case NSAboveTop:
		titleBand = [_titleFont ascender] - [_titleFont descender] + 2.0;
		break;
	default:
		break;
	}
	frame.size.width = NSWidth(contentFrame) + 2.0 * (_borderWidth + _contentViewMargins.width);
	frame.size.height = NSHeight(contentFrame) + 2.0 * (_borderWidth + _contentViewMargins.height) + titleBand;
	[self setFrame:frame];
}

- (void)sizeToFit
{
	NSSize contentSize = NSZeroSize;

	if (_contentView != nil) {
		contentSize = [_contentView frame].size;
	}
	[self setFrameFromContentFrame:NSMakeRect(0.0, 0.0, contentSize.width, contentSize.height)];
}

/* ---- THE INK ------------------------------------------------------------------------------------ */

/* **FIVE KINDS, THREE DRAWING PATHS.** A primary or secondary box is a bezel in the control face; a separator is one line
 * across the middle; an old-style box is a square frame; and a CUSTOM box fills and strokes its own rounded rectangle from
 * the four numbers. THE FILL COMES FIRST and the title LAST, so a title drawn across the top edge sits in its gap rather
 * than under the border. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	NSRect border = [self borderRect];

	(void)dirtyRect;
	switch (_boxType) {
	case NSBoxSeparator:
		[[NSColor controlShadowColor] setFill];
		NSRectFill(NSMakeRect(NSMinX(bounds), NSMidY(bounds), NSMaxX(bounds) - NSMinX(bounds), 1.0));
		break;
	case NSBoxPrimary:
	case NSBoxSecondary:
		NSDrawGrayBezel(border, border);
		break;
	case NSBoxOldStyle:
		NSFrameRect(border);
		break;
	case NSBoxCustom:
	default: {
		NSRect faceRect = NSInsetRect(border, _borderWidth / 2.0, _borderWidth / 2.0);
		NSBezierPath *path;

		/* **ONE PATH, TWO CONSTRUCTORS**: a corner radius of zero is a rectangle, which `bezierPathWithRect:` says without
		 * asking a rounded constructor to treat zero as one (the field cell's own note records the same choice). */
		path = (_cornerRadius > 0.0)
			? [NSBezierPath bezierPathWithRoundedRect:faceRect xRadius:_cornerRadius yRadius:_cornerRadius]
			: [NSBezierPath bezierPathWithRect:faceRect];

		if (!_transparent) {
			[( _fillColor != nil) ? _fillColor : [NSColor controlColor] setFill];
			[path fill];
		}
		if (_borderWidth > 0.0) {
			[(_borderColor != nil) ? _borderColor : [NSColor controlShadowColor] setStroke];
			[path setLineWidth:_borderWidth];
			[path stroke];
		}
		break;
	}
	}
	/* AND THE TITLE, THROUGH ITS CELL. */
	{
		NSRect title = [self titleRect];

		if (!NSIsEmptyRect(title)) {
			/* **THE GAP IN THE BORDER**, for the classic `NSAtTop`: clearing the title's band before the cell draws keeps the
			 * border from striking through the words. The clear is the FILL colour (or the window's ground), which is what
			 * makes a title look cut out of the frame rather than laid over it. */
			if (_titlePosition == NSAtTop) {
				[(_fillColor != nil) ? _fillColor : [NSColor controlColor] setFill];
				NSRectFill(title);
			}
			[_titleCell setAlignment:NSCenterTextAlignment];
			[_titleCell drawWithFrame:title inView:self];
		}
	}
}

/* **A BOX'S SIZE IS ITS CONTENT'S**, so a frame change re-lays the content out and an inner layout pass happens here rather
 * than in every setter. */
- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self cg_layOutContent];
}

- (void)setFrame:(NSRect)frameRect
{
	[super setFrame:frameRect];
	[self cg_layOutContent];
}

@end
