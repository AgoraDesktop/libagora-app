/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSScrollView.h — the frame, the scrollers, and the clip view that holds the document (stage E/F).
 *
 * **A SCROLL VIEW IS THE ONE PIECE THAT WAS MISSING BETWEEN THREE THAT EXISTED.** `NSClipView` was the inside of a
 * scroll view and could not be the whole of one; `NSScroller` was the bar and had nothing to drive; and `NSView`'s
 * `-enclosingScrollView` answered nil BY NAME because there was no class to find. This is the class that closes all
 * three: it owns a content view (an `NSClipView`), the vertical and horizontal `NSScroller`s, and the TILING between
 * them, and it is the thing that moves the clip view when a scroller is used and moves the scroller when the clip
 * view is moved.
 *
 * **THE FLOW OF FACTS IS ONE LOOP, AND IT GOES BOTH WAYS.** A scroller's action asks for its value and part and
 * scrolls the clip view (`-scrollClipView:toPoint:`); the clip view, having moved, tells its ENCLOSING VIEW
 * (`-reflectScrolledClipView:`), and the scroll view recomputes both scrollers' values from the clip view's own
 * geometry. That is why a knob dragged to the end and a document scrolled by code end in the same place: both are
 * read back from the clip view rather than remembered anywhere else.
 *
 * WHAT IS NOT HERE, STATED RATHER THAN STUBBED: the ruler (`NSRulerView` and the `-horizontalRulerView` family) and
 * the header view, because neither class exists in this tier; the ruler is the one part `NSClipView.h` names when it
 * says a scroll view is "the frame, the scrollers and the ruler". `-scrollWheel:` is not declared either: the seam
 * reports no wheel axis yet, so a door taking a wheel event would have nothing to read.
 */
#ifndef APPKIT_NSSCROLLVIEW_H
#define APPKIT_NSSCROLLVIEW_H

#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>

NS_ASSUME_NONNULL_BEGIN

@class NSClipView;
@class NSScroller;
@class NSEvent;

@interface NSScrollView : NSView
{
	/* **ALL THREE ARE BORROWED, BECAUSE THE TREE OWNS EVERY ONE OF THEM.** The content view and the scrollers are
	 * SUBVIEWS — `-addSubview:` is what retains them — so a second owning pointer would be a second owner of a thing
	 * the tree already keeps. The clip view is the exception to "the scroll view owns its content": it is the
	 * container the document is put INTO, and the document is a subview of IT. */
	NSClipView *_contentView;
	NSScroller *_vScroller;
	NSScroller *_hScroller;
	NSBorderType _borderType;
	NSColor *_backgroundColor;	/* RETAINED: this class's own, not a subview's */
	BOOL _drawsBackground;
	CGFloat _lineScroll;
	CGFloat _pageScroll;
}

/* **THE TWO CLASS DOORS THAT CONVERT A CONTENT SIZE TO A FRAME AND BACK.** They are exact inverses and both must
 * agree with `-tile`, because a caller sizing a scroll view for a document uses one and the layout uses the other —
 * the class of bug where a view is a scroller's width too small and nobody can see why. */
+ (NSSize)frameSizeForContentSize:(NSSize)contentSize
	     hasHorizontalScroller:(BOOL)hFlag
	       hasVerticalScroller:(BOOL)vFlag
		       borderType:(NSBorderType)aType;
+ (NSSize)contentSizeForFrameSize:(NSSize)frameSize
	     hasHorizontalScroller:(BOOL)hFlag
	       hasVerticalScroller:(BOOL)vFlag
		       borderType:(NSBorderType)aType;

- (instancetype)initWithFrame:(NSRect)frameRect;

/* THE CONTENT VIEW, WHICH IS AN `NSClipView` AND THE PARENT OF THE DOCUMENT. */
- (nullable NSView *)contentView;
- (void)setContentView:(nullable NSView *)aView;

/* **AND THE DOCUMENT ITSELF, WHICH IS THE CLIP VIEW'S AND FORWARDED FROM HERE.** A caller talks to the scroll view
 * and never has to find the clip view to put a document in it. */
- (nullable NSView *)documentView;
- (void)setDocumentView:(nullable NSView *)aView;

/* **THE TWO SCROLLERS AND WHETHER THEY ARE THERE.** Setting either creates or removes the bar, and every one of the
 * four doors re-tiles, because a scroller's presence is a change to the content's size and not merely to the ink. */
- (BOOL)hasVerticalScroller;
- (void)setHasVerticalScroller:(BOOL)flag;
- (BOOL)hasHorizontalScroller;
- (void)setHasHorizontalScroller:(BOOL)flag;
- (nullable NSScroller *)verticalScroller;
- (void)setVerticalScroller:(nullable NSScroller *)anObject;
- (nullable NSScroller *)horizontalScroller;
- (void)setHorizontalScroller:(nullable NSScroller *)anObject;

/* AND THE LAYOUT ITSELF, WHICH IS PUBLIC BECAUSE A CALLER THAT CHANGES A BORDER OR A FRAME WANTS IT RE-RUN. */
- (void)tile;

/* THE CONTENT'S SIZE — what a caller measures a document against — and what of it is showing. */
- (NSSize)contentSize;
- (NSRect)documentVisibleRect;

- (NSBorderType)borderType;
- (void)setBorderType:(NSBorderType)aType;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;

/* **THE TWO STEPS A PAGE OR A LINE MOVES BY.** `-pageScroll` of 0 means "page by the visible extent", which is the
 * era's default and the reason a page is not a fixed number of points. */
- (CGFloat)lineScroll;
- (void)setLineScroll:(CGFloat)aFloat;
- (CGFloat)pageScroll;
- (void)setPageScroll:(CGFloat)aFloat;

/* **THE LOOP'S TWO HALVES, AS PUBLIC DOORS.** `-reflectScrolledClipView:` is what the clip view calls when it has
 * moved (the default `NSView` answer does nothing); `-scrollClipView:toPoint:` is what the scroller's action calls to
 * move it. A subclass can override either to watch or to change what a scroll means. */
- (void)reflectScrolledClipView:(NSClipView *)aClipView;
- (void)scrollClipView:(NSClipView *)aClipView toPoint:(NSPoint)aPoint;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSCROLLVIEW_H */
