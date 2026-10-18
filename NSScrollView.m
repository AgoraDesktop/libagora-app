/*
 * NSScrollView — the frame, the scrollers, and the clip view that holds the document.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE FILE IS THE TILING AND THE TWO-WAY LOOP.** Everything else a scroll view appears to own is one of the three
 * objects it was built to join: the content view is an `NSClipView` (which owns the document and the scroll
 * arithmetic) and the two scrollers are `NSScroller`s (which own their own value and geometry). What is left for
 * this class is where those three sit (`-tile`), and the two directions a scroll travels: a scroller's action moves
 * the clip view, and a moved clip view updates the scrollers.
 */
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/NSGeometry.h>

/* **THE BORDER'S WIDTH, WHICH IS ALSO HALF OF EVERY SIZE CONVERSION.** A line is a point, a groove and a bezel are
 * two, and none is nothing. It is a function rather than a table because the two class doors and `-tile` all need it
 * and a second copy is how a frame size and a layout come to disagree by a point. */
static CGFloat fn_border_width(NSBorderType type)
{
	switch (type) {
	case NSNoBorder:
		return 0.0;
	case NSLineBorder:
		return 1.0;
	case NSGrooveBorder:
	case NSBezelBorder:
		return 2.0;
	default:
		return 0.0;
	}
}

@implementation NSScrollView

/* ---- THE TWO CONVERSIONS, WHICH MUST AGREE WITH `-tile` ------------------------------------------------- */

+ (NSSize)frameSizeForContentSize:(NSSize)contentSize
	     hasHorizontalScroller:(BOOL)hFlag
	       hasVerticalScroller:(BOOL)vFlag
		       borderType:(NSBorderType)aType
{
	CGFloat border = fn_border_width(aType);
	CGFloat w = contentSize.width + 2.0 * border + (vFlag ? [NSScroller scrollerWidth] : 0.0);
	CGFloat h = contentSize.height + 2.0 * border + (hFlag ? [NSScroller scrollerWidth] : 0.0);

	return NSMakeSize(w, h);
}

+ (NSSize)contentSizeForFrameSize:(NSSize)frameSize
	     hasHorizontalScroller:(BOOL)hFlag
	       hasVerticalScroller:(BOOL)vFlag
		       borderType:(NSBorderType)aType
{
	CGFloat border = fn_border_width(aType);
	CGFloat w = frameSize.width - 2.0 * border - (vFlag ? [NSScroller scrollerWidth] : 0.0);
	CGFloat h = frameSize.height - 2.0 * border - (hFlag ? [NSScroller scrollerWidth] : 0.0);

	if (w < 0.0) {
		w = 0.0;
	}
	if (h < 0.0) {
		h = 0.0;
	}
	return NSMakeSize(w, h);
}

/* ---- MAKING ONE ----------------------------------------------------------------------------------------- */

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSClipView *clip;

		_borderType = NSNoBorder;
		_backgroundColor = [[NSColor controlBackgroundColor] retain];
		_drawsBackground = YES;
		/* THE LINE STEP IS TEN POINTS AND THE PAGE STEP IS ZERO, which is the era's pair: zero means "page by the
		 * visible extent", so a page is a fraction of the window rather than a fixed number of points. */
		_lineScroll = 10.0;
		_pageScroll = 0.0;
		/* **A SCROLL VIEW ALWAYS HAS A CONTENT VIEW, MADE HERE AND NOWHERE ELSE.** A caller who replaces it may,
		 * but a scroll view whose content a caller forgot to set would have nowhere to put a document — and the
		 * whole point of this class is that the document and the bars have a frame to sit in. */
		clip = [[NSClipView alloc] initWithFrame:[self bounds]];
		[self setContentView:clip];
		[clip release];
	}
	return self;
}

- (void)dealloc
{
	[_headerView release];
	[_backgroundColor release];
	[super dealloc];
}

/* ---- THE CONTENT VIEW AND THE DOCUMENT ------------------------------------------------------------------ */

- (NSView *)contentView
{
	return _contentView;
}

- (void)setContentView:(NSView *)aView
{
	if (aView == (NSView *)_contentView) {
		return;
	}
	if (_contentView != nil) {
		[_contentView removeFromSuperview];
	}
	/* BORROWED: `-addSubview:` below is what owns it, which is the rule `NSClipView` follows for its own document. */
	_contentView = (NSClipView *)aView;
	if (aView != nil) {
		[self addSubview:aView];
	}
	[self tile];
}

- (NSView *)documentView
{
	return [_contentView documentView];
}

- (void)setDocumentView:(NSView *)aView
{
	[_contentView setDocumentView:aView];
	/* AND THE BARS ARE TOLD AT ONCE, because a document that arrived may be shorter or longer than the last one and
	 * the knob's size is the visible fraction of it. */
	[self reflectScrolledClipView:_contentView];
}

/* ---- THE TWO SCROLLERS ---------------------------------------------------------------------------------- */

- (BOOL)hasVerticalScroller
{
	return _vScroller != nil;
}

- (void)setHasVerticalScroller:(BOOL)flag
{
	if (flag == (_vScroller != nil)) {
		return;
	}
	if (flag) {
		NSScroller *sc = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, [NSScroller scrollerWidth],
									      [NSScroller scrollerWidth])];

		[self setVerticalScroller:sc];
		[sc release];
	} else {
		[self setVerticalScroller:nil];
	}
}

- (BOOL)hasHorizontalScroller
{
	return _hScroller != nil;
}

- (void)setHasHorizontalScroller:(BOOL)flag
{
	if (flag == (_hScroller != nil)) {
		return;
	}
	if (flag) {
		NSScroller *sc = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, [NSScroller scrollerWidth],
									      [NSScroller scrollerWidth])];

		[self setHorizontalScroller:sc];
		[sc release];
	} else {
		[self setHorizontalScroller:nil];
	}
}

- (NSScroller *)verticalScroller
{
	return _vScroller;
}

/* **THE TARGET/ACTION PAIR IS WHAT MAKES A SCROLLER DO ANYTHING.** A scroller only reports where it was pressed and
 * what its value is; this is the one line that turns that report into a scroll, and it is set here rather than left
 * to a caller so a scroll view's own bars work without anybody wiring them. */
- (void)setVerticalScroller:(NSScroller *)anObject
{
	if (anObject == _vScroller) {
		return;
	}
	if (_vScroller != nil) {
		[_vScroller removeFromSuperview];
	}
	_vScroller = anObject;	/* BORROWED: the subview link owns it */
	if (anObject != nil) {
		[self addSubview:anObject];
		[anObject setTarget:self];
		[anObject setAction:@selector(cg_scrollerAction:)];
	}
	[self tile];
}

- (NSScroller *)horizontalScroller
{
	return _hScroller;
}

- (void)setHorizontalScroller:(NSScroller *)anObject
{
	if (anObject == _hScroller) {
		return;
	}
	if (_hScroller != nil) {
		[_hScroller removeFromSuperview];
	}
	_hScroller = anObject;
	if (anObject != nil) {
		[self addSubview:anObject];
		[anObject setTarget:self];
		[anObject setAction:@selector(cg_scrollerAction:)];
	}
	[self tile];
}

/* ---- THE LAYOUT ----------------------------------------------------------------------------------------- */

/* **A FRAME CHANGE RE-TILES, WHICH IS WHAT MAKES A HEADER AND THE BARS FOLLOW A RESIZE.** `-tile` is the one layout
 * pass and a scroll view is the one view whose whole face is that pass; leaving it to the caller meant a resize moved
 * the frame and not its contents. */
- (void)setFrame:(NSRect)frameRect
{
	[super setFrame:frameRect];
	[self tile];
}

/* **THE CONTENT IS TOP-LEFT AND EVERYTHING ELSE IS INSIDE THE REST.** A vertical scroller runs down the right from
 * above the horizontal scroller to the top; a horizontal one runs along the bottom from the left to the vertical
 * one; and the content takes what is left inside the border. The frame is read in the SCROLL VIEW's own coordinates
 * and this view is not flipped, so the bottom is the smaller y — the clip view and the scrollers are flipped
 * internally and that does not change where their frames go. */
- (void)tile
{
	NSRect frame = [self bounds];
	CGFloat border = fn_border_width(_borderType);
	CGFloat vw = 0.0;
	CGFloat hh = 0.0;
	CGFloat headerHeight = 0.0;
	NSRect content;

	if (_vScroller != nil) {
		vw = NSWidth([_vScroller frame]);
		if (vw <= 0.0) {
			vw = [NSScroller scrollerWidth];
		}
	}
	if (_hScroller != nil) {
		hh = NSHeight([_hScroller frame]);
		if (hh <= 0.0) {
			hh = [NSScroller scrollerWidth];
		}
	}
	if (_headerView != nil) {
		headerHeight = NSHeight([_headerView frame]);
		if (headerHeight < 0.0) {
			headerHeight = 0.0;
		}
	}
	content = NSMakeRect(NSMinX(frame) + border, NSMinY(frame) + border + hh + headerHeight,
			     NSWidth(frame) - 2.0 * border - vw,
			     NSHeight(frame) - 2.0 * border - hh - headerHeight);
	if (content.size.width < 0.0) {
		content.size.width = 0.0;
	}
	if (content.size.height < 0.0) {
		content.size.height = 0.0;
	}
	[_contentView setFrame:content];
	if (_headerView != nil) {
		NSRect header = NSMakeRect(NSMinX(content), NSMaxY(content), NSWidth(content), headerHeight);

		if ([_headerView superview] != self) {
			[self addSubview:_headerView];
		}
		[_headerView setFrame:header];
	}
	if (_vScroller != nil) {
		[_vScroller setFrame:NSMakeRect(NSMaxX(frame) - border - vw, NSMinY(frame) + border + hh,
						vw, NSHeight(frame) - 2.0 * border - hh)];
	}
	if (_hScroller != nil) {
		[_hScroller setFrame:NSMakeRect(NSMinX(frame) + border, NSMinY(frame) + border,
						NSWidth(frame) - 2.0 * border - vw, hh)];
	}
	if (_contentView != nil) {
		[self reflectScrolledClipView:_contentView];
	}
}

- (NSSize)contentSize
{
	if (_contentView == nil) {
		return NSZeroSize;
	}
	return [_contentView frame].size;
}

- (NSRect)documentVisibleRect
{
	if (_contentView == nil) {
		return NSZeroRect;
	}
	return [_contentView documentVisibleRect];
}

/* ---- THE TABLE HEADER ------------------------------------------------------------------------------------ */

- (void)cg_setHeaderView:(NSView *)headerView
{
	if (headerView == _headerView) {
		return;
	}
	[_headerView removeFromSuperview];
	[_headerView release];
	_headerView = [headerView retain];
	if (_headerView != nil) {
		[self addSubview:_headerView];
	}
	[self tile];
}

- (NSView *)cg_headerView
{
	return _headerView;
}

/* ---- THE BORDER AND THE GROUND -------------------------------------------------------------------------- */

- (NSBorderType)borderType
{
	return _borderType;
}

- (void)setBorderType:(NSBorderType)aType
{
	_borderType = aType;
	/* A BORDER IS PART OF THE LAYOUT, not only of the ink: it insets the content by its own width, so changing it
	 * re-tiles rather than merely redrawing. */
	[self tile];
	[self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)color
{
	NSColor *old = _backgroundColor;

	_backgroundColor = [color retain];
	[old release];
	[self setNeedsDisplay:YES];
}

- (BOOL)drawsBackground
{
	return _drawsBackground;
}

- (void)setDrawsBackground:(BOOL)flag
{
	_drawsBackground = flag ? YES : NO;
	[self setNeedsDisplay:YES];
}

- (CGFloat)lineScroll
{
	return _lineScroll;
}

- (void)setLineScroll:(CGFloat)aFloat
{
	_lineScroll = aFloat;
}

- (CGFloat)pageScroll
{
	return _pageScroll;
}

- (void)setPageScroll:(CGFloat)aFloat
{
	_pageScroll = aFloat;
}

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	if (_drawsBackground && _backgroundColor != nil) {
		CGContextRef c = [[NSGraphicsContext currentContext] CGContext];

		if (c != NULL) {
			NSRect b = [self bounds];

			CGContextSetFillColorWithColor(c, [_backgroundColor CGColor]);
			CGContextFillRect(c, CGRectMake(b.origin.x, b.origin.y, b.size.width, b.size.height));
		}
	}
	if (_borderType != NSNoBorder) {
		NSBezierPath *p = [NSBezierPath bezierPathWithRect:NSInsetRect([self bounds], 0.5, 0.5)];

		[[NSColor controlShadowColor] setStroke];
		[p setLineWidth:1.0];
		[p stroke];
	}
}

/* ---- THE LOOP, BOTH WAYS -------------------------------------------------------------------------------- */

/* **THE CLIP VIEW HAS MOVED, SO THE BARS CATCH UP.** This is the door the clip view calls after every scroll (see
 * `NSClipView -scrollToPoint:`), and the only source of truth is the clip view's own geometry: the knob's size is
 * the visible fraction of the document and its place is how far down that fraction is. Nothing here remembers a
 * value, which is why a scroll driven by code and one driven by hand end up saying the same thing. */
- (void)reflectScrolledClipView:(NSClipView *)aClipView
{
	if (aClipView == nil || aClipView != _contentView) {
		return;
	}
	/* THE HEADER FOLLOWS THE HORIZONTAL OFFSET AND NOT THE VERTICAL ONE. */
	if (_headerView != nil) {
		NSPoint origin = [_headerView bounds].origin;

		origin.x = [aClipView bounds].origin.x;
		[_headerView setBoundsOrigin:origin];
	}
	[self cg_syncScroller:_vScroller vertical:YES];
	[self cg_syncScroller:_hScroller vertical:NO];
}

- (void)cg_syncScroller:(NSScroller *)scroller vertical:(BOOL)vertical
{
	NSRect doc;
	NSRect vis;
	CGFloat docLen;
	CGFloat visLen;
	CGFloat proportion;
	CGFloat value = 0.0;

	if (scroller == nil || _contentView == nil) {
		return;
	}
	doc = [_contentView documentRect];
	vis = [_contentView bounds];
	docLen = vertical ? doc.size.height : doc.size.width;
	visLen = vertical ? vis.size.height : vis.size.width;
	proportion = (docLen > 0.0) ? (visLen / docLen) : 1.0;
	if (proportion > 1.0) {
		proportion = 1.0;
	}
	if (proportion < 0.0) {
		proportion = 0.0;
	}
	if (docLen > visLen) {
		CGFloat start = vertical ? (vis.origin.y - doc.origin.y) : (vis.origin.x - doc.origin.x);
		CGFloat range = docLen - visLen;

		if (range > 0.0) {
			value = start / range;
		}
	}
	if (value < 0.0) {
		value = 0.0;
	}
	if (value > 1.0) {
		value = 1.0;
	}
	[scroller setFloatValue:value knobProportion:proportion];
}

/* AND THE OTHER DIRECTION: this is what the scroller's action calls, through the public door so a subclass can
 * intercept a scroll before it happens. */
- (void)scrollClipView:(NSClipView *)aClipView toPoint:(NSPoint)aPoint
{
	[aClipView scrollToPoint:aPoint];
}

/* **WHAT A SCROLLER'S ACTION DOES.** The scroller has already decided its value and part (its own tracking); this
 * turns that into a place for the clip view. A KNOB sets the origin from the value directly; a page or a line steps
 * by the scroll amounts, a page of 0 meaning "by the visible extent", which is the era's own reading. */
- (void)cg_scrollerAction:(NSScroller *)sender
{
	NSClipView *clip = _contentView;
	BOOL vertical = (sender == _vScroller);
	NSScrollerPart part;
	NSRect doc;
	NSRect vis;
	NSPoint target;
	CGFloat docLen;
	CGFloat visLen;
	CGFloat range;
	CGFloat value;

	if (clip == nil) {
		return;
	}
	part = [sender hitPart];
	value = [sender floatValue];
	doc = [clip documentRect];
	vis = [clip bounds];
	target = vis.origin;
	docLen = vertical ? doc.size.height : doc.size.width;
	visLen = vertical ? vis.size.height : vis.size.width;
	range = docLen - visLen;

	switch (part) {
	case NSScrollerKnob:
		if (range > 0.0) {
			if (vertical) {
				target.y = doc.origin.y + value * range;
			} else {
				target.x = doc.origin.x + value * range;
			}
		}
		break;
	case NSScrollerDecrementPage:
	case NSScrollerIncrementPage:
	{
		CGFloat step = (_pageScroll > 0.0) ? _pageScroll : (visLen - _lineScroll);
		CGFloat sign = (part == NSScrollerDecrementPage) ? -1.0 : 1.0;

		if (step <= 0.0) {
			step = visLen;
		}
		if (vertical) {
			target.y += sign * step;
		} else {
			target.x += sign * step;
		}
		break;
	}
	case NSScrollerDecrementLine:
	case NSScrollerIncrementLine:
	{
		CGFloat sign = (part == NSScrollerDecrementLine) ? -1.0 : 1.0;

		if (vertical) {
			target.y += sign * _lineScroll;
		} else {
			target.x += sign * _lineScroll;
		}
		break;
	}
	default:
		return;
	}
	[self scrollClipView:clip toPoint:target];
}

@end
