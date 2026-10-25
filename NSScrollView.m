/*
 * NSScrollView — the frame, the scrollers, and the clip view that holds the document.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
#import <AppKit/NSRulerView.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSGeometry.h>
#import "AppKitRefusal.h"

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

/* ============================================================================================
 * ARCHIVING: THE DOCUMENT VIEW, THE TWO SCROLLERS AND THE LOOK.
 * ============================================================================================ */
/* **A SCROLL VIEW IS THE ONE VIEW WHOSE MOST IMPORTANT CHILD IS NOT IN `_subviews`.** `_contentView` is the clip view the
 * document lives in, and it is put back through `-setContentView:` — the door that re-parents and re-tiles — rather than
 * by adding a subview, which is the same "use the door that has the side effect" rule the rest of this format follows.
 * `_inTile` is the layout pass's re-entry flag and is absent. */
static NSString * const AGCoderScrollContentViewKey = @"contentView";
static NSString * const AGCoderScrollHeaderViewKey = @"headerView";
static NSString * const AGCoderScrollVScrollerKey = @"verticalScroller";
static NSString * const AGCoderScrollHScrollerKey = @"horizontalScroller";
static NSString * const AGCoderScrollBorderKey = @"borderType";
static NSString * const AGCoderScrollBackgroundKey = @"backgroundColor";
static NSString * const AGCoderScrollDrawsBackgroundKey = @"drawsBackground";
static NSString * const AGCoderScrollAutohideKey = @"autohidesScrollers";
static NSString * const AGCoderScrollHLineKey = @"horizontalLineScroll";
static NSString * const AGCoderScrollVLineKey = @"verticalLineScroll";
static NSString * const AGCoderScrollHPageKey = @"horizontalPageScroll";
static NSString * const AGCoderScrollVPageKey = @"verticalPageScroll";
static NSString * const AGCoderScrollDynamicallyKey = @"scrollsDynamically";
/* **AND THE TWO OLD KEYS ARE KEPT FOR READING, WHICH IS A COMPATIBILITY STATEMENT RATHER THAN LEFT-OVERS.** They were
 * the 10.0 pair before the axes split; an archive written then carries one number for both, and `-initWithCoder:`
 * still reads it as the vertical amount. Nothing writes them any more. */
static NSString * const AGCoderScrollLineKey = @"lineScroll";
static NSString * const AGCoderScrollPageKey = @"pageScroll";
static NSString * const AGCoderScrollVRulerKey = @"verticalRuler";
static NSString * const AGCoderScrollHRulerKey = @"horizontalRuler";
static NSString * const AGCoderScrollRulersVisibleKey = @"rulersVisible";
static NSString * const AGCoderScrollWantsVRulerKey = @"wantsVerticalRuler";
static NSString * const AGCoderScrollWantsHRulerKey = @"wantsHorizontalRuler";

/* **THE CLASS A SCROLL VIEW INSTANTIATES FOR A RULER IT WAS NOT HANDED.** One per process, as Apple's is, and
 * `NSRulerView` itself is the default — a caller with a subclass (a ruler that knows about its own document) installs it
 * once and every scroll view built afterwards gets it. */
static Class gRulerViewClass = Nil;

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_contentView forKey:AGCoderScrollContentViewKey];
	[aCoder encodeObject:_headerView forKey:AGCoderScrollHeaderViewKey];
	[aCoder encodeObject:_vScroller forKey:AGCoderScrollVScrollerKey];
	[aCoder encodeObject:_hScroller forKey:AGCoderScrollHScrollerKey];
	[aCoder encodeInteger:(NSInteger)_borderType forKey:AGCoderScrollBorderKey];
	[aCoder encodeObject:_backgroundColor forKey:AGCoderScrollBackgroundKey];
	[aCoder encodeBool:_drawsBackground forKey:AGCoderScrollDrawsBackgroundKey];
	[aCoder encodeBool:_autohidesScrollers forKey:AGCoderScrollAutohideKey];
	[aCoder encodeDouble:(double)_horizontalLineScroll forKey:AGCoderScrollHLineKey];
	[aCoder encodeDouble:(double)_verticalLineScroll forKey:AGCoderScrollVLineKey];
	[aCoder encodeDouble:(double)_horizontalPageScroll forKey:AGCoderScrollHPageKey];
	[aCoder encodeDouble:(double)_verticalPageScroll forKey:AGCoderScrollVPageKey];
	[aCoder encodeBool:_scrollsDynamically forKey:AGCoderScrollDynamicallyKey];
	[aCoder encodeObject:_vRuler forKey:AGCoderScrollVRulerKey];
	[aCoder encodeObject:_hRuler forKey:AGCoderScrollHRulerKey];
	[aCoder encodeBool:_rulersVisible forKey:AGCoderScrollRulersVisibleKey];
	[aCoder encodeBool:_wantsVerticalRuler forKey:AGCoderScrollWantsVRulerKey];
	[aCoder encodeBool:_wantsHorizontalRuler forKey:AGCoderScrollWantsHRulerKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderScrollHeaderViewKey]) {
		_headerView = [[aDecoder decodeObjectForKey:AGCoderScrollHeaderViewKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollVScrollerKey]) {
		_vScroller = [[aDecoder decodeObjectForKey:AGCoderScrollVScrollerKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollHScrollerKey]) {
		_hScroller = [[aDecoder decodeObjectForKey:AGCoderScrollHScrollerKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollBorderKey]) {
		_borderType = (NSBorderType)[aDecoder decodeIntegerForKey:AGCoderScrollBorderKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollBackgroundKey]) {
		_backgroundColor = [[aDecoder decodeObjectForKey:AGCoderScrollBackgroundKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollDrawsBackgroundKey]) {
		_drawsBackground = [aDecoder decodeBoolForKey:AGCoderScrollDrawsBackgroundKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollAutohideKey]) {
		_autohidesScrollers = [aDecoder decodeBoolForKey:AGCoderScrollAutohideKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollLineKey]) {
		_verticalLineScroll = [aDecoder decodeDoubleForKey:AGCoderScrollLineKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollPageKey]) {
		_verticalPageScroll = [aDecoder decodeDoubleForKey:AGCoderScrollPageKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollHLineKey]) {
		_horizontalLineScroll = [aDecoder decodeDoubleForKey:AGCoderScrollHLineKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollVLineKey]) {
		_verticalLineScroll = [aDecoder decodeDoubleForKey:AGCoderScrollVLineKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollHPageKey]) {
		_horizontalPageScroll = [aDecoder decodeDoubleForKey:AGCoderScrollHPageKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollVPageKey]) {
		_verticalPageScroll = [aDecoder decodeDoubleForKey:AGCoderScrollVPageKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollDynamicallyKey]) {
		_scrollsDynamically = [aDecoder decodeBoolForKey:AGCoderScrollDynamicallyKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollWantsVRulerKey]) {
		_wantsVerticalRuler = [aDecoder decodeBoolForKey:AGCoderScrollWantsVRulerKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollWantsHRulerKey]) {
		_wantsHorizontalRuler = [aDecoder decodeBoolForKey:AGCoderScrollWantsHRulerKey];
	}
	if ([aDecoder containsValueForKey:AGCoderScrollContentViewKey]) {
		id clip = [aDecoder decodeObjectForKey:AGCoderScrollContentViewKey];

		if ([clip isKindOfClass:[NSClipView class]]) {
			[self setContentView:clip];
		}
	}
	/* **THE RULERS COME BACK THROUGH THEIR OWN DOORS, WHICH IS WHAT RE-ESTABLISHES THE RELATIONSHIP.** Decoding the view
	 * alone would give a ruler with no scroll view, no orientation and no client — three nils a caller would have to
	 * repair by hand. */
	if ([aDecoder containsValueForKey:AGCoderScrollVRulerKey]) {
		id ruler = [aDecoder decodeObjectForKey:AGCoderScrollVRulerKey];

		if ([ruler isKindOfClass:[NSRulerView class]]) {
			[self setVerticalRulerView:ruler];
		}
	}
	if ([aDecoder containsValueForKey:AGCoderScrollHRulerKey]) {
		id ruler = [aDecoder decodeObjectForKey:AGCoderScrollHRulerKey];

		if ([ruler isKindOfClass:[NSRulerView class]]) {
			[self setHorizontalRulerView:ruler];
		}
	}
	if ([aDecoder containsValueForKey:AGCoderScrollRulersVisibleKey]) {
		[self setRulersVisible:[aDecoder decodeBoolForKey:AGCoderScrollRulersVisibleKey]];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


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
		/* APPLE'S DEFAULT IS NO, and this tree keeps it: a caller that wants bars to come and go opts in. */
		_autohidesScrollers = NO;
		/* THE LINE STEP IS TEN POINTS AND THE PAGE STEP IS ZERO, which is the era's pair: zero means "page by the
		 * visible extent", so a page is a fraction of the window rather than a fixed number of points. THE SAME PAIR
		 * IS WRITTEN ON BOTH AXES, because a scroll view that said ten one way and zero the other would step
		 * differently depending on which scroller the hand used. */
		_horizontalLineScroll = 10.0;
		_verticalLineScroll = 10.0;
		_horizontalPageScroll = 0.0;
		_verticalPageScroll = 0.0;
		/* AND A SCROLL DRAWS AS IT GOES: the only mode this tier has (see `-setScrollsDynamically:`). */
		_scrollsDynamically = YES;
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
	[_vScroller release];
	[_hScroller release];
	[super dealloc];
}

/* ---- THE CONTENT VIEW AND THE DOCUMENT ------------------------------------------------------------------ */

- (NSClipView *)contentView
{
	return _contentView;
}

- (void)setContentView:(NSClipView *)aView
{
	if (aView == _contentView) {
		return;
	}
	if (_contentView != nil) {
		[_contentView removeFromSuperview];
	}
	/* BORROWED: `-addSubview:` below is what owns it, which is the rule `NSClipView` follows for its own document. */
	_contentView = aView;
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
	/* **THE RULERS MEASURE THE DOCUMENT, SO THEY ARE TOLD WHICH ONE IT IS.** A ruler's client is the thing its markers
	 * sit beside; leaving the previous document there would make a tab stop land at an offset from a view that is no
	 * longer on screen. */
	[_vRuler setClientView:aView];
	[_hRuler setClientView:aView];
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
		[_vScroller release];
	}
	_vScroller = [anObject retain];	/* OWNED: it may be detached while it is configured but hidden */
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
		[_hScroller release];
	}
	_hScroller = [anObject retain];
	if (anObject != nil) {
		[self addSubview:anObject];
		[anObject setTarget:self];
		[anObject setAction:@selector(cg_scrollerAction:)];
	}
	[self tile];
}

- (BOOL)autohidesScrollers
{
	return _autohidesScrollers;
}

- (void)setAutohidesScrollers:(BOOL)flag
{
	BOOL value = flag ? YES : NO;

	if (_autohidesScrollers == value) {
		return;
	}
	_autohidesScrollers = value;
	[self tile];
}

/* ---- THE RULERS ------------------------------------------------------------------------------------------ */

+ (Class)rulerViewClass
{
	return (gRulerViewClass != Nil) ? gRulerViewClass : [NSRulerView class];
}

+ (void)setRulerViewClass:(Class)aClass
{
	gRulerViewClass = (aClass != Nil) ? aClass : [NSRulerView class];
}

- (BOOL)hasVerticalRuler
{
	return _wantsVerticalRuler;
}

- (void)setHasVerticalRuler:(BOOL)flag
{
	BOOL value = flag ? YES : NO;

	if (value == _wantsVerticalRuler) {
		return;
	}
	_wantsVerticalRuler = value;
	if (!value) {
		[self setVerticalRulerView:nil];
		return;
	}
	/* **BUILT ON DEMAND AND ONLY WHEN IT WOULD BE SEEN.** A hidden ruler that was never shown costs nothing to defer;
	 * `-verticalRulerView` builds it the moment a caller asks, and `-setRulersVisible:YES` does the same. */
	if (_rulersVisible) {
		(void)[self verticalRulerView];
	}
	[self tile];
}

- (BOOL)hasHorizontalRuler
{
	return _wantsHorizontalRuler;
}

- (void)setHasHorizontalRuler:(BOOL)flag
{
	BOOL value = flag ? YES : NO;

	if (value == _wantsHorizontalRuler) {
		return;
	}
	_wantsHorizontalRuler = value;
	if (!value) {
		[self setHorizontalRulerView:nil];
		return;
	}
	if (_rulersVisible) {
		(void)[self horizontalRulerView];
	}
	[self tile];
}

- (NSRulerView *)verticalRulerView
{
	if (_vRuler == nil && _wantsVerticalRuler) {
		NSRulerView *ruler = [[[[self class] rulerViewClass] alloc] initWithScrollView:self
										orientation:NSVerticalRuler];

		[self setVerticalRulerView:ruler];
		[ruler release];
	}
	return _vRuler;
}

- (void)setVerticalRulerView:(NSRulerView *)aRulerView
{
	if (aRulerView == _vRuler) {
		return;
	}
	[_vRuler removeFromSuperview];
	_vRuler = aRulerView;
	if (_vRuler != nil) {
		_wantsVerticalRuler = YES;
		[_vRuler setScrollView:self];
		[_vRuler setOrientation:NSVerticalRuler];
		[_vRuler setClientView:[self documentView]];
		[_vRuler setHidden:!_rulersVisible];
		[self addSubview:_vRuler];
	} else {
		_wantsVerticalRuler = NO;
	}
	[self tile];
}

- (NSRulerView *)horizontalRulerView
{
	if (_hRuler == nil && _wantsHorizontalRuler) {
		NSRulerView *ruler = [[[[self class] rulerViewClass] alloc] initWithScrollView:self
										orientation:NSHorizontalRuler];

		[self setHorizontalRulerView:ruler];
		[ruler release];
	}
	return _hRuler;
}

- (void)setHorizontalRulerView:(NSRulerView *)aRulerView
{
	if (aRulerView == _hRuler) {
		return;
	}
	[_hRuler removeFromSuperview];
	_hRuler = aRulerView;
	if (_hRuler != nil) {
		_wantsHorizontalRuler = YES;
		[_hRuler setScrollView:self];
		[_hRuler setOrientation:NSHorizontalRuler];
		[_hRuler setClientView:[self documentView]];
		[_hRuler setHidden:!_rulersVisible];
		[self addSubview:_hRuler];
	} else {
		_wantsHorizontalRuler = NO;
	}
	[self tile];
}

- (BOOL)rulersVisible
{
	return _rulersVisible;
}

- (void)setRulersVisible:(BOOL)flag
{
	BOOL value = flag ? YES : NO;

	if (value == _rulersVisible) {
		return;
	}
	_rulersVisible = value;
	/* **SHOWING CREATES WHAT THE SCROLL VIEW HAS BEEN TOLD IT HAS.** The two `-verticalRulerView`/`-horizontalRulerView`
	 * calls are the creation path, so the flag and the object can never disagree about whether a ruler exists. */
	if (value) {
		(void)[self verticalRulerView];
		(void)[self horizontalRulerView];
	}
	[_vRuler setHidden:!value];
	[_hRuler setHidden:!value];
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
	/* **THE TWO RULER STRIPS, WHICH ARE PART OF THE LAYOUT AND NOT ONLY OF THE INK.** A visible ruler takes its whole
	 * required thickness out of the content: the vertical one off the left, the horizontal one off the top. A HIDDEN
	 * ruler takes nothing, which is what makes hiding one give the document its room back. */
	CGFloat vrulerW = (_rulersVisible && _vRuler != nil) ? [_vRuler requiredThickness] : 0.0;
	CGFloat hrulerH = (_rulersVisible && _hRuler != nil) ? [_hRuler requiredThickness] : 0.0;
	CGFloat usedVW;
	CGFloat usedHH;
	NSRect content;
	BOOL visibilityChanged = NO;
	NSSize oldContent = (_contentView != nil) ? [_contentView frame].size : NSZeroSize;
	BOOL showV = YES;
	BOOL showH = YES;

	if (_inTile) {
		return;
	}
	_inTile = YES;
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
	/* **A CONFIGURED BAR THAT THE DOCUMENT DOES NOT NEED STEPS ASIDE.** The visibility is decided against the
	 * document's own frame, and it is decided as a PAIR because a vertical bar takes width that can make a
	 * horizontal one necessary and vice versa; three passes are enough for those two to settle. */
	[self cg_scrollerVisibility:&showV :&showH];
	/* **A HIDDEN BAR LEAVES THE TREE, and its object is retained by this view while it is away.** A configured
	 * scroller still answers `-hasVerticalScroller`/`-verticalScroller`, but a view that is not a subview cannot
	 * leave ink behind, which is what a merely `-isHidden` bar did on the window. */
	if (_vScroller != nil) {
		BOOL changed = (([_vScroller superview] == self) != showV);
		[_vScroller setHidden:!showV];
		if (showV) {
			if ([_vScroller superview] != self) {
				[self addSubview:_vScroller];
			}
		} else if ([_vScroller superview] == self) {
			[_vScroller removeFromSuperview];
		}
		visibilityChanged = visibilityChanged || changed;
	}
	if (_hScroller != nil) {
		BOOL changed = (([_hScroller superview] == self) != showH);
		[_hScroller setHidden:!showH];
		if (showH) {
			if ([_hScroller superview] != self) {
				[self addSubview:_hScroller];
			}
		} else if ([_hScroller superview] == self) {
			[_hScroller removeFromSuperview];
		}
		visibilityChanged = visibilityChanged || changed;
	}
	usedVW = showV ? vw : 0.0;
	usedHH = showH ? hh : 0.0;
	/* **THE HEADER TAKES THE TOP STRIP; THE CLIP VIEW TAKES WHAT IS BELOW IT.** The header's height is already
	 * subtracted from the content's, so the content starts at the bottom and ends at the header's bottom — NOT at
	 * the scroll view's top. The first version also ADDED the header's height to the content's origin, which put the
	 * header above the scroll view's own frame and clipped it away. */
	content = NSMakeRect(NSMinX(frame) + border + vrulerW, NSMinY(frame) + border + usedHH,
			     NSWidth(frame) - 2.0 * border - usedVW - vrulerW,
			     NSHeight(frame) - 2.0 * border - usedHH - headerHeight - hrulerH);
	if (content.size.width < 0.0) {
		content.size.width = 0.0;
	}
	if (content.size.height < 0.0) {
		content.size.height = 0.0;
	}
	/* **AND THE CLIP VIEW IS LAID OUT WHERE THE LAYOUT SAYS, NOT SNAPPED TO THE DEVICE GRID.** Snapping the content
	 * view's rectangle to whole device pixels made a scroll's copy exact — its edges became whole columns and rows — but
	 * it MOVES EVERY CONTROL in the document by up to one pixel, and MEASURED that is not free: at 1.332 the demo's
	 * gallery grew a one-pixel white line through the panel buttons and the caption above them, a latent sub-pixel
	 * artefact of the drawing layer that the shift walked into. A rendering fix is not this change's to make, so the
	 * layout is untouched and the copy takes the fractional edges it is given — see `-cg_copyRect:from:stride:delta:`,
	 * which rounds INWARD for that reason and leaves the sub-pixel sliver to the repaint. */
	[_contentView setFrame:content];
	/* **THE CORNER SQUARE BELONGS TO THE VERTICAL RULER.** It runs the full height of the content area — including the
	 * strip the horizontal ruler takes — so the two never overlap and there is no fourth view to draw the corner. The
	 * horizontal ruler starts to the right of it, which is what puts a text ruler's zero in line with the text. */
	if (_vRuler != nil) {
		[_vRuler setFrame:NSMakeRect(NSMinX(frame) + border, NSMinY(frame) + border + usedHH,
					     vrulerW, NSHeight(frame) - 2.0 * border - usedHH)];
	}
	if (_hRuler != nil) {
		[_hRuler setFrame:NSMakeRect(NSMinX(frame) + border + vrulerW, NSMaxY(frame) - border - hrulerH,
					     NSWidth(frame) - 2.0 * border - usedVW - vrulerW, hrulerH)];
	}
	if (_headerView != nil) {
		NSRect header = NSMakeRect(NSMinX(content), NSMaxY(content), NSWidth(content), headerHeight);

		if ([_headerView superview] != self) {
			[self addSubview:_headerView];
		}
		[_headerView setFrame:header];
	}
	if (_vScroller != nil) {
		[_vScroller setFrame:showV ? NSMakeRect(NSMaxX(frame) - border - vw,
							NSMinY(frame) + border + usedHH,
							vw, NSHeight(frame) - 2.0 * border - usedHH) : NSZeroRect];
	}
	if (_hScroller != nil) {
		[_hScroller setFrame:showH ? NSMakeRect(NSMinX(frame) + border, NSMinY(frame) + border,
							NSWidth(frame) - 2.0 * border - usedVW, hh) : NSZeroRect];
	}
	if (visibilityChanged) {
		[self setNeedsDisplay:YES];
		[[self superview] setNeedsDisplay:YES];
	}
	if (_contentView != nil) {
		NSView *doc = [_contentView documentView];

		/* **A DOCUMENT THAT FILLS THE CLIP HAS TO BE TOLD THE CLIP CHANGED.** Hiding a bar gives the clip more
		 * room; a table sizes itself from `-contentSize`, so without this call the sidebar's rows would keep the
		 * narrow width they had beside a visible bar. */
		if ((oldContent.width != content.size.width || oldContent.height != content.size.height)
		    && doc != nil && [doc respondsToSelector:@selector(tile)]) {
			[doc tile];
		}
		/* The clip's visible origin may be past the end of a document that just got room to shrink. */
		[_contentView scrollToPoint:[_contentView bounds].origin];
		[self reflectScrolledClipView:_contentView];
	}
	_inTile = NO;
}

/* WHAT THE AUTOHIDE RULE WOULD SHOW. `-tile` uses it to lay the bars out; `-reflectScrolledClipView:` uses it
 * to notice that a document whose frame changed now fits (or no longer fits) and needs a re-tile. */
- (void)cg_scrollerVisibility:(BOOL *)showVertical :(BOOL *)showHorizontal
{
	BOOL wantV = (_vScroller != nil);
	BOOL wantH = (_hScroller != nil);
	NSView *doc = [_contentView documentView];
	NSSize docSize = (doc != nil) ? [doc frame].size : NSZeroSize;
	CGFloat border = fn_border_width(_borderType);
	CGFloat vw = wantV ? NSWidth([_vScroller frame]) : 0.0;
	CGFloat hh = wantH ? NSHeight([_hScroller frame]) : 0.0;
	CGFloat headerHeight = (_headerView != nil) ? NSHeight([_headerView frame]) : 0.0;
	CGFloat vrulerW = (_rulersVisible && _vRuler != nil) ? [_vRuler requiredThickness] : 0.0;
	CGFloat hrulerH = (_rulersVisible && _hRuler != nil) ? [_hRuler requiredThickness] : 0.0;
	BOOL showV = wantV;
	BOOL showH = wantH;
	NSInteger pass;

	if (!_autohidesScrollers) {
		*showVertical = showV;
		*showHorizontal = showH;
		return;
	}
	if (vw <= 0.0) {
		vw = [NSScroller scrollerWidth];
	}
	if (hh <= 0.0) {
		hh = [NSScroller scrollerWidth];
	}
	showV = NO;
	showH = NO;
	for (pass = 0; pass < 3; pass++) {
		CGFloat availW = NSWidth([self bounds]) - 2.0 * border - (showV ? vw : 0.0) - vrulerW;
		CGFloat availH = NSHeight([self bounds]) - 2.0 * border - (showH ? hh : 0.0) - headerHeight - hrulerH;
		BOOL needV = wantV && docSize.height > availH;
		BOOL needH = wantH && docSize.width > availW;

		if (needV == showV && needH == showH) {
			break;
		}
		showV = needV;
		showH = needH;
	}
	*showVertical = showV;
	*showHorizontal = showH;
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

/* **THE 10.0 PAIR IS THE VERTICAL AXIS, SPELLED AS AN ALIAS RATHER THAN KEPT AS A SECOND NUMBER.** See the header:
 * `-lineScroll` is the amount a line steps DOWN, and it is `_verticalLineScroll` under its older name. A separate field
 * would let a caller set one and a scroller read the other, which is the same class of bug the axis-specific doors
 * exist to prevent. */
- (CGFloat)lineScroll
{
	return _verticalLineScroll;
}

- (void)setLineScroll:(CGFloat)aFloat
{
	_verticalLineScroll = aFloat;
}

- (CGFloat)pageScroll
{
	return _verticalPageScroll;
}

- (void)setPageScroll:(CGFloat)aFloat
{
	_verticalPageScroll = aFloat;
}

- (CGFloat)horizontalLineScroll
{
	return _horizontalLineScroll;
}

- (void)setHorizontalLineScroll:(CGFloat)aFloat
{
	_horizontalLineScroll = aFloat;
}

- (CGFloat)verticalLineScroll
{
	return _verticalLineScroll;
}

- (void)setVerticalLineScroll:(CGFloat)aFloat
{
	_verticalLineScroll = aFloat;
}

- (CGFloat)horizontalPageScroll
{
	return _horizontalPageScroll;
}

- (void)setHorizontalPageScroll:(CGFloat)aFloat
{
	_horizontalPageScroll = aFloat;
}

- (CGFloat)verticalPageScroll
{
	return _verticalPageScroll;
}

- (void)setVerticalPageScroll:(CGFloat)aFloat
{
	_verticalPageScroll = aFloat;
}

- (BOOL)scrollsDynamically
{
	return _scrollsDynamically;
}

- (void)setScrollsDynamically:(BOOL)flag
{
	/* **YES IS THE ONLY MODE THIS TIER HAS, SO NO IS REFUSED BY NAME RATHER THAN STORED.** A deferred scroll keeps the
	 * clip view's BOUNDS where they were and draws the difference when the gesture ends; this tier's clip view draws
	 * from `-bounds` at draw time, so a deferred scroll would move the DOCUMENT and leave the ink on screen where it
	 * was — a scroll that visibly does nothing until something else forces a redraw. Storing NO and behaving as YES
	 * would be the quiet version of the same lie; this says so and keeps the mode it can honour. */
	if (!flag) {
		fn_refuse_window("-[NSScrollView setScrollsDynamically:]",
				 "a deferred-scroll mode (a scrolled clip view draws from its bounds at draw time here, so a "
				 "deferred scroll would move the document and leave the ink where it was)");
		_scrollsDynamically = YES;
		return;
	}
	_scrollsDynamically = YES;
}

/* **AND THE DOCUMENT'S CURSOR, WHICH IS THE CLIP VIEW'S.** See the header: the pair is declared on both classes and
 * this is the forward, so a caller holding the scroll view never has to find the clip view to say it. */
- (NSCursor *)documentCursor
{
	return [_contentView documentCursor];
}

- (void)setDocumentCursor:(NSCursor *)anObj
{
	[_contentView setDocumentCursor:anObj];
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
	/* **A DOCUMENT THAT CHANGED SIZE CAN CHANGE WHICH BARS ARE NEEDED.** The clip view announces the change through
	 * this same door, so before syncing the knobs the scroll view asks whether the autohide pair is what it is
	 * showing; if it is not, `-tile` is the one pass that lays the new pair out. The guard stops the tile's own
	 * final reflect from starting a second tile. */
	if (!_inTile && _autohidesScrollers) {
		BOOL showV = YES;
		BOOL showH = YES;
		BOOL needsTile = NO;

		[self cg_scrollerVisibility:&showV :&showH];
		if (_vScroller != nil && [_vScroller isHidden] != !showV) {
			needsTile = YES;
		}
		if (_hScroller != nil && [_hScroller isHidden] != !showH) {
			needsTile = YES;
		}
		if (needsTile) {
			[self tile];
			return;
		}
	}
	/* THE HEADER FOLLOWS THE HORIZONTAL OFFSET AND NOT THE VERTICAL ONE. */
	if (_headerView != nil) {
		NSPoint origin = [_headerView bounds].origin;

		origin.x = [aClipView bounds].origin.x;
		[_headerView setBoundsOrigin:origin];
	}
	/* **AND EACH RULER FOLLOWS THE OFFSET ITS OWN AXIS MEASURES.** The vertical ruler moves its window down the document
	 * as the document scrolls up, and the horizontal one does the same with x; the OTHER coordinate is left alone
	 * because a vertical ruler does not care where the page is horizontally. That is what makes a mark drawn at
	 * document coordinate 300 appear under the character at 300. */
	if (_vRuler != nil) {
		NSPoint origin = [_vRuler bounds].origin;

		origin.y = [aClipView bounds].origin.y;
		[_vRuler setBoundsOrigin:origin];
		[_vRuler invalidateHashMarks];
	}
	if (_hRuler != nil) {
		NSPoint origin = [_hRuler bounds].origin;

		origin.x = [aClipView bounds].origin.x;
		[_hRuler setBoundsOrigin:origin];
		[_hRuler invalidateHashMarks];
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
		CGFloat line = vertical ? _verticalLineScroll : _horizontalLineScroll;
		CGFloat page = vertical ? _verticalPageScroll : _horizontalPageScroll;
		CGFloat step = (page > 0.0) ? page : (visLen - line);
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
		CGFloat step = vertical ? _verticalLineScroll : _horizontalLineScroll;

		if (vertical) {
			target.y += sign * step;
		} else {
			target.x += sign * step;
		}
		break;
	}
	default:
		return;
	}
	[self scrollClipView:clip toPoint:target];
}

@end
