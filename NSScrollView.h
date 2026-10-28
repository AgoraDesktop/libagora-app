/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * WHAT IS NOT HERE, STATED RATHER THAN STUBBED: the header view is not an Apple door and lives in the private seam the
 * table uses, and `-scrollWheel:` is not declared either: the seam reports no wheel axis yet, so a door taking a wheel
 * event would have nothing to read. THE RULERS ARE HERE — `NSRulerView` arrived with the text slice, and the scroll view
 * tiles the two strips it names and keeps their bounds on the document, which is the whole of the relationship.
 */
#ifndef APPKIT_NSSCROLLVIEW_H
#define APPKIT_NSSCROLLVIEW_H

#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>

NS_ASSUME_NONNULL_BEGIN

@class NSClipView;
@class NSScroller;
@class NSEvent;
@class NSCursor;
@class NSRulerView;

@interface NSScrollView : NSView <NSSecureCoding>
{
	/* **ALL THREE ARE BORROWED, BECAUSE THE TREE OWNS EVERY ONE OF THEM.** The content view and the scrollers are
	 * SUBVIEWS — `-addSubview:` is what retains them — so a second owning pointer would be a second owner of a thing
	 * the tree already keeps. The clip view is the exception to "the scroll view owns its content": it is the
	 * container the document is put INTO, and the document is a subview of IT. */
	NSClipView *_contentView;
	/* **THE TABLE HEADER, WHEN THERE IS ONE.** RETAINED here as well as by the table, because a scroll view that
	 * keeps a header must own it while it lays it out; `-cg_setHeaderView:` is the private seam in the internal
	 * header. A plain scroll view has none. */
	NSView *_headerView;
	NSScroller *_vScroller;
	NSScroller *_hScroller;
	/* **THE TWO RULERS, BORROWED LIKE THE HEADER.** `-addSubview:` retains them, and a second owning pointer would be a
	 * second owner of a thing the view hierarchy already keeps; the flag is whether they are in the strip at all, which
	 * is a different question from whether they exist. */
	NSRulerView *_vRuler;
	NSRulerView *_hRuler;
	/* **"HAS" AND "SHOWS" ARE TWO FLAGS AND THE VIEWS ARE A THIRD THING.** Apple's `-verticalRulerView` CREATES the
	 * ruler on demand when the scroll view has been told it has one, so what a caller sets is an INTENTION and what
	 * `-tile` builds is the object; a ruler that exists while hidden keeps its markers, which is the whole reason
	 * visibility is not the same question. */
	BOOL _wantsVerticalRuler;
	BOOL _wantsHorizontalRuler;
	BOOL _rulersVisible;
	NSBorderType _borderType;
	NSColor *_backgroundColor;	/* RETAINED: this class's own, not a subview's */
	BOOL _drawsBackground;
	BOOL _autohidesScrollers;
	BOOL _inTile;
	/* **THE SCROLL AMOUNTS ARE PER AXIS, WHICH IS THE ERA'S OWN SPLIT.** `-lineScroll`/`-pageScroll` are the 10.0 doors
	 * and they are the VERTICAL pair (see the header); the four axis-specific doors below are what a scroller's action
	 * actually reads, so a scroll view can step by ten points sideways and by a page vertically without one of the two
	 * numbers having to stand for both. `_scrollsDynamically` is whether a scroll redraws as it goes — YES here, and
	 * the only value this tier has a mode for. */
	CGFloat _horizontalLineScroll;
	CGFloat _verticalLineScroll;
	CGFloat _horizontalPageScroll;
	CGFloat _verticalPageScroll;
	BOOL _scrollsDynamically;
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

/* THE CONTENT VIEW, WHICH IS AN `NSClipView` AND THE PARENT OF THE DOCUMENT — AND IS DECLARED AS THE CLASS IT IS.
 * **A LOOSE `NSView *` HERE IS NOT A CONVENIENCE, IT IS A CROSSING.** Everything a caller does with the answer is
 * clip-view work: `-scrollToPoint:`, `-bounds`, handing it back to `-reflectScrolledClipView:`, which takes an
 * `NSClipView` and cannot take a plain view. Declared loosely, each of those sites becomes an implicit narrowing the
 * compiler must reject ("incompatible pointer types sending 'NSView *' to parameter of type 'NSClipView *'") — the
 * error lands on the CALLER for a fact the class has always known, and every caller pays a cast to say it. The ivar
 * is an `NSClipView *`, `-contentView` returns it, and Apple's 10.6 signature names `NSClipView`; so does this one. */
- (nullable NSClipView *)contentView;
- (void)setContentView:(nullable NSClipView *)aView;

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

/* **A CONFIGURED SCROLLER CAN HIDE WHEN THE DOCUMENT FITS.** `-hasVerticalScroller`/`-hasHorizontalScroller`
 * answer whether a bar EXISTS; `-autohidesScrollers` decides whether it is drawn when the clip view already shows
 * the whole document. A hidden bar still exists and still answers `-verticalScroller`/`-horizontalScroller`; the
 * content expands into the space it would have taken. The default is NO, Apple's own default, so a caller opts
 * in. */
- (BOOL)autohidesScrollers;
- (void)setAutohidesScrollers:(BOOL)flag;

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

/* **THE DOCUMENT'S CURSOR IS THE CLIP VIEW'S, AND THIS IS THE FORWARD** — Apple declares it on both classes, and a
 * caller holding the scroll view must not have to reach through `-contentView` to say what the document's cursor is. */
- (nullable NSCursor *)documentCursor;
- (void)setDocumentCursor:(nullable NSCursor *)anObj;

/* **THE TWO STEPS A PAGE OR A LINE MOVES BY.** `-pageScroll` of 0 means "page by the visible extent", which is the
 * era's default and the reason a page is not a fixed number of points.
 *
 * **AND THE SPLIT IS THE ERA'S**: `-lineScroll`/`-pageScroll` are the 10.0 doors and they name the VERTICAL amount,
 * while `-horizontalLineScroll` and its three siblings are the axis-specific ones the action reads. The 10.0 pair is
 * therefore an ALIAS rather than a fifth and sixth number — two fields that a caller can set apart and that disagree
 * are exactly how a scroll comes to step sideways when it was told to step down. */
- (CGFloat)lineScroll;
- (void)setLineScroll:(CGFloat)aFloat;
- (CGFloat)pageScroll;
- (void)setPageScroll:(CGFloat)aFloat;
- (CGFloat)horizontalLineScroll;
- (void)setHorizontalLineScroll:(CGFloat)aFloat;
- (CGFloat)verticalLineScroll;
- (void)setVerticalLineScroll:(CGFloat)aFloat;
- (CGFloat)horizontalPageScroll;
- (void)setHorizontalPageScroll:(CGFloat)aFloat;
- (CGFloat)verticalPageScroll;
- (void)setVerticalPageScroll:(CGFloat)aFloat;

/* **AND WHETHER A SCROLL DRAWS AS IT GOES.** The flag round-trips and YES is the default; NO is REFUSED BY NAME, because
 * a deferred mode means scrolling the clip view's BOUNDS without moving its ink and drawing the difference when the
 * gesture ends — and this tier's clip view draws from the current origin, so a deferred scroll would leave the content
 * where it was and the knob saying it had moved. See `-setScrollsDynamically:`. */
- (BOOL)scrollsDynamically;
- (void)setScrollsDynamically:(BOOL)flag;

/* **THE WHEEL IS `-scrollWheel:`, AND IT IS A LINE STEPPER LIKE THE SCROLLER'S INCREMENT LINE.** It is inherited from
 * `NSResponder` and declared nowhere — Apple's rule — but the AMOUNT it moves by is the pair above: one wheel line is
 * `-verticalLineScroll` or `-horizontalLineScroll`, so a scroll view whose lines are ten points moves ten points per
 * notch and a caller that wants a coarser one sets those, not a wheel-specific property (there is none, on this era or
 * any other). `NSEvent -deltaY` counts lines and is positive UP; the clip view's origin runs the other way, which is why
 * the arithmetic reads as a subtraction. An axis the document cannot move in is NOT consumed: the event goes on up the
 * responder chain, which is what lets a horizontal scroller inside a vertical one work. */

/* **THE RULERS, WHICH ARE THE THIRD KIND OF STRIP A SCROLL VIEW CAN WEAR.** `-hasVerticalRuler` says whether one EXISTS,
 * `-setHasVerticalRuler:` creates or removes it, and `-rulersVisible` says whether the ones that exist are SHOWING —
 * which is the era's split and the reason hiding a ruler does not throw away its markers.
 *
 * `+rulerViewClass`/`+setRulerViewClass:` ARE CLASS METHODS, as Apple's are: they name the class a scroll view
 * instantiates when a caller asks for a ruler without handing one over, so a subclass with its own ruler gets it
 * everywhere without each scroll view being configured. */
+ (Class)rulerViewClass;
+ (void)setRulerViewClass:(Class)aClass;

- (BOOL)hasVerticalRuler;
- (void)setHasVerticalRuler:(BOOL)flag;
- (BOOL)hasHorizontalRuler;
- (void)setHasHorizontalRuler:(BOOL)flag;
- (nullable NSRulerView *)verticalRulerView;
- (void)setVerticalRulerView:(nullable NSRulerView *)aRulerView;
- (nullable NSRulerView *)horizontalRulerView;
- (void)setHorizontalRulerView:(nullable NSRulerView *)aRulerView;
- (BOOL)rulersVisible;
- (void)setRulersVisible:(BOOL)flag;

/* **THE LOOP'S TWO HALVES, AS PUBLIC DOORS.** `-reflectScrolledClipView:` is what the clip view calls when it has
 * moved (the default `NSView` answer does nothing); `-scrollClipView:toPoint:` is what the scroller's action calls to
 * move it. A subclass can override either to watch or to change what a scroll means. */
- (void)reflectScrolledClipView:(NSClipView *)aClipView;
- (void)scrollClipView:(NSClipView *)aClipView toPoint:(NSPoint)aPoint;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSCROLLVIEW_H */
