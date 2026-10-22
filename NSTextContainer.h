/*
 * NSTextContainer.h — WHERE TEXT IS ALLOWED TO GO: A REGION, AND THE FRAGMENTS THAT FIT IN IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THIS IS THE MIDDLE OF THE TEXT SYSTEM'S TRIO AND IT IS THE SMALLEST OF THE THREE.** Apple's own header says what
 * it is in one line: "defines a region in which to lay out text. Its main responsibility is to calculate line
 * fragments which fall within the region it represents." So it holds FOUR FACTS — a size, a line-fragment padding, two
 * flags about tracking a view's size, and the view it is drawn in — and one PIECE OF GEOMETRY: given a proposed
 * fragment, answer the part of it that falls inside. The text itself is `NSTextStorage`'s; the thing that ASKS for
 * fragments and draws them is `NSLayoutManager`, which is the next slice.
 *
 * **AND THE FOUR FACTS ARE WHAT MAKE THE WEBS WORK.** `-containerSize` is the MAXIMUM flowable area and not the size
 * of anything on screen — Apple's own prose is emphatic that the view's size has little to do with it — and
 * `-widthTracksTextView`/`-heightTracksTextView` are how a container keeps ONE dimension in step with the view while
 * the other floats, which is the difference between a fixed-width page and a column. `-lineFragmentPadding` is the
 * inset a FRAGMENT's text takes, and it is applied along the SWEEP direction, which is why it is a padding and not a
 * margin: it belongs to the line's own rectangle rather than to the region.
 *
 * **AND THE LAYOUT MANAGER'S END OF THE WEB IS HERE NOW, BECAUSE THE CLASS IS.** `-layoutManager`/`-setLayoutManager:`
 * used to be REFUSED on the ground that declaring them would have taken a class that did not exist — `NSLayoutManager`
 * does, and what the container holds is a BORROWED pointer, because the MANAGER retains the container (its array does)
 * and not the other way round, which is the split that keeps the web from being a cycle. `-replaceLayoutManager:`
 * DOES THE HALF THAT CROSSES THE OBJECT BOUNDARY — off the old manager's list and onto the new one's — which is why it
 * exists beside the primitive.
 *
 * **AND THE CONTAINER IS ONLY A RECTANGLE BY DEFAULT: `-isSimpleRectangularTextContainer` ANSWERS YES.** Apple's
 * default returns YES and a SUBCLASS overrides it to NO when its region has holes or concavities. THAT ANSWER IS
 * READ NOW: the layout manager keeps the cheap arithmetic for a YES — the container's width less its padding, at x=0,
 * with a ZERO HEIGHT meaning unbounded, which is what a scrolling text view's container carries — and for a NO it
 * ASKS `-lineFragmentRectForProposedRect:sweepDirection:movementDirection:remainingRect:` for each line's band and
 * lays the line in the subrect's x and width, continuing into the remaining rect when the region hands one back.
 */
#ifndef APPKIT_NSTEXTCONTAINER_H
#define APPKIT_NSTEXTCONTAINER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTextView;
@class NSLayoutManager;

/* **THE TWO DIRECTIONS A FRAGMENT IS PLACED BY, IN APPLE'S OWN ORDER.** The SWEEP direction is which edge of the
 * proposed rectangle the fragment starts from — left, right, down, up, numbered 0 through 3 — and the MOVEMENT
 * direction is which way the rectangle may be carried when it does not fit, with `NSLineDoesntMove` FIRST. The two
 * orders are Apple's and are kept: they are small integers a caller compares, so a reordering would be a silent
 * change of meaning rather than a compile error. */
enum {
	NSLineSweepLeft = 0,
	NSLineSweepRight = 1,
	NSLineSweepDown = 2,
	NSLineSweepUp = 3
};
typedef NSUInteger NSLineSweepDirection;

enum {
	NSLineDoesntMove = 0,
	NSLineMovesLeft = 1,
	NSLineMovesRight = 2,
	NSLineMovesDown = 3,
	NSLineMovesUp = 4
};
typedef NSUInteger NSLineMovementDirection;

@interface NSTextContainer : NSObject
{
	/* **FOUR FACTS AND TWO BORROWED POINTERS.** Neither is retained: the view is the same relationship a subview has to
	 * its superview, and the MANAGER retains the CONTAINER (its array does) rather than the other way round, because a
	 * container that owned its manager would make the web a cycle. */
	NSLayoutManager *_layoutManager;	/* NOT RETAINED */
	NSTextView *_textView;		/* NOT RETAINED */
	NSSize _size;
	CGFloat _lineFragmentPadding;
	BOOL _widthTracksTextView;
	BOOL _heightTracksTextView;
}

/* **THE ONE WAY IN, AND IT TAKES THE SIZE RATHER THAN SETTING A DEFAULT.** A container's region IS what it was made
 * with, so `-init` gives a ZERO size (a container that can hold nothing until it is told otherwise) and this door is
 * the one that says what the region is. */
- (instancetype)initWithContainerSize:(NSSize)size;

/* ---- THE MANAGER THAT LAYS THIS CONTAINER OUT, WHICH IS BORROWED -------------------------------------- */

/* **THE PRIMITIVE IS THE MANAGER'S TO CALL, NOT A CALLER'S** — Apple's comment says the set method is called when a
 * container is added to a manager — so `[manager addTextContainer:container]` is the way to tie the two, and this pair
 * is what that call writes. `-replaceLayoutManager:` is the one a CALLER uses to move a container between managers,
 * and it does the two halves the primitive cannot: out of the old manager's list and into the new one's. */
- (nullable NSLayoutManager *)layoutManager;
- (void)setLayoutManager:(nullable NSLayoutManager *)layoutManager;
- (void)replaceLayoutManager:(nullable NSLayoutManager *)newLayoutManager;

/* ---- THE REGION, AND THE PADDING ITS LINES TAKE ------------------------------------------------------ */

/* THE MAXIMUM FLOWABLE AREA — a fact about the container and NOT about how much text is in it, which a container is
 * "not in a position to know" (Apple's own words, kept because they are the whole reason this is `NSSize` and not a
 * rectangle in anyone's coordinates). */
- (NSSize)containerSize;
- (void)setContainerSize:(NSSize)size;

/* THE AIR A FRAGMENT'S TEXT TAKES, applied along the sweep direction. Ten points is Apple's default. */
- (CGFloat)lineFragmentPadding;
- (void)setLineFragmentPadding:(CGFloat)pad;

/* ---- AND THE VIEW IT IS DRAWN IN, WHICH IS OPTIONAL AND WHICH ITS FLAGS TRACK ------------------------ */

- (nullable NSTextView *)textView;
- (void)setTextView:(nullable NSTextView *)aTextView;

/* **THE TWO TRACKING FLAGS, WHICH KEEP ONE DIMENSION IN STEP WITH THE VIEW'S FRAME.** Both default to NO: a container
 * made by this initialiser has a size and keeps it, and a container that follows its view is what a text view makes
 * when it sets one up. */
- (BOOL)widthTracksTextView;
- (void)setWidthTracksTextView:(BOOL)flag;
- (BOOL)heightTracksTextView;
- (void)setHeightTracksTextView:(BOOL)flag;

/* ---- THE GEOMETRY, WHICH IS THIS CLASS'S ONE COMPUTATION -------------------------------------------- */

/* **"THE FIRST AND LARGEST SUBRECT OF `proposedRect` WHICH FALLS WITHIN THE CONTAINER'S REGION."** For a SIMPLE
 * RECTANGULAR container that is the intersection with the region — the sweep direction changes nothing because a
 * rectangle has no edges to start from — and `remainingRect` is EMPTY, because a rectangle has no holes for a fragment
 * to leave behind. THE MOVEMENT DIRECTION IS THE ONE REAL COMPLICATION: when the proposed rectangle misses the region
 * entirely, the container may CARRY it back along that direction until it meets the edge, which is how a typesetter
 * asks "is there room if I move this line over". `NSLineDoesntMove` refuses to try; the four directions give the
 * nearest edge on that side. */
- (NSRect)lineFragmentRectForProposedRect:(NSRect)proposedRect
			   sweepDirection:(NSLineSweepDirection)sweepDirection
		       movementDirection:(NSLineMovementDirection)movementDirection
			    remainingRect:(nullable NSRect *)remainingRect;

/* **YES, AND A SUBCLASS SAYS NO WHEN ITS REGION HAS A SHAPE.** The answer is what a layout manager uses to decide
 * whether it may take the cheap route, so it is a promise about the GEOMETRY rather than an opinion. */
- (BOOL)isSimpleRectangularTextContainer;

/* AND THE HIT TEST, in the container's own coordinates. */
- (BOOL)containsPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTCONTAINER_H */
