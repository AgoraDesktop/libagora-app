/*
 * NSTextContainer.m — a region, four facts about it, and the one computation that reads them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLASS IS A STORE AND A SWITCH.** Everything above "THE GEOMETRY" is four values and a borrowed pointer; the
 * geometry below it is one intersection, one clip and one carry-back. There is no state machine, no cache and no
 * notification, which is why this is the smallest of the trio — and why it is the one that can be written before the
 * layout manager that will ask it for fragments.
 */
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSLayoutManager.h>
#import <Foundation/NSGeometry.h>

@implementation NSTextContainer

/* **A ZERO REGION UNTIL SOMEBODY SAYS OTHERWISE, WHICH IS A CONTAINER THAT HOLDS NOTHING.** Apple's `-init` is not
 * documented to pick a size, and inventing the screen's would be this class guessing at something the caller knows;
 * `-initWithContainerSize:` is the door that says what the region is. */
- (instancetype)init
{
	return [self initWithContainerSize:NSMakeSize(0.0, 0.0)];
}

- (instancetype)initWithContainerSize:(NSSize)size
{
	self = [super init];
	if (self != nil) {
		_size = size;
		/* TEN POINTS IS APPLE'S DEFAULT, and it is a PADDING rather than a margin: the typesetter eats it off the
		 * fragment's own rectangle, along the sweep direction, so it belongs to the line rather than to the region. */
		_lineFragmentPadding = 10.0;
		_widthTracksTextView = NO;
		_heightTracksTextView = NO;
	}
	return self;
}

/* ---- THE MANAGER THAT LAYS THIS CONTAINER OUT, WHICH IS BORROWED -------------------------------- */

- (NSLayoutManager *)layoutManager
{
	return _layoutManager;
}

/* **THE PRIMITIVE IS THE MANAGER'S TO CALL, NOT A CALLER'S.** Apple's comment says the set method is called when a
 * container is added to a manager, and that is exactly what this is: `[manager addTextContainer:container]` reaches it, so
 * the pointer and the manager's list are written in one direction and cannot disagree. */
- (void)setLayoutManager:(NSLayoutManager *)layoutManager
{
	_layoutManager = layoutManager;
}

/* **AND THE DOOR A CALLER USES MOVES THE WHOLE WEB, WHICH IS WHY IT CANNOT BE THE PRIMITIVE.** Apple's comment: "All
 * the NSTextContainers on the old NSLayoutManager get transferred to the new one." The manager has no way to remove by
 * POINTER in this era (`-removeTextContainerAtIndex:` is the only door), so the transfer is: take the old list, empty
 * it from the front, and add each container to the new manager — which sets each container's own back-pointer as it
 * goes. A nil new manager clears this container's pointer and leaves the old manager's list alone, which is stated
 * rather than half-done. */
- (void)replaceLayoutManager:(NSLayoutManager *)newLayoutManager
{
	NSLayoutManager *old = _layoutManager;

	if (old == newLayoutManager) {
		return;
	}
	if (old != nil && newLayoutManager != nil) {
		NSArray *containers = [[old textContainers] retain];
		NSUInteger i;

		for (i = 0; i < [containers count]; i++) {
			[old removeTextContainerAtIndex:0];
		}
		for (i = 0; i < [containers count]; i++) {
			[newLayoutManager addTextContainer:[containers objectAtIndex:i]];
		}
		[containers release];
	} else {
		_layoutManager = newLayoutManager;
	}
}

/* ---- THE REGION, AND THE PADDING ITS LINES TAKE ------------------------------------------------------ */

- (NSSize)containerSize
{
	return _size;
}

- (void)setContainerSize:(NSSize)size
{
	_size = size;
}

- (CGFloat)lineFragmentPadding
{
	return _lineFragmentPadding;
}

- (void)setLineFragmentPadding:(CGFloat)pad
{
	_lineFragmentPadding = pad;
}

/* ---- AND THE VIEW IT IS DRAWN IN --------------------------------------------------------------------- */

- (NSTextView *)textView
{
	return _textView;
}

- (void)setTextView:(NSTextView *)aTextView
{
	/* BORROWED, like a subview's `-superview`: the view owns its container, and a container that retained the view
	 * would keep a window alive from a layout object. */
	_textView = aTextView;
}

- (BOOL)widthTracksTextView
{
	return _widthTracksTextView;
}

- (void)setWidthTracksTextView:(BOOL)flag
{
	_widthTracksTextView = flag;
}

- (BOOL)heightTracksTextView
{
	return _heightTracksTextView;
}

- (void)setHeightTracksTextView:(BOOL)flag
{
	_heightTracksTextView = flag;
}

/* ============================================================================================ *
 * THE GEOMETRY                                                                                  *
 * ============================================================================================ */

/* **ONE INTERSECTION, AND A CARRY-BACK WHEN IT IS EMPTY.** The region is the rectangle the container was made with,
 * in the container's own coordinates — which are the text view's, and a text view is FLIPPED, so "down" is LARGER y.
 * The sweep direction changes nothing for a rectangle (there are no edges to start from), and `remainingRect` is
 * always empty (a rectangle has no holes for a fragment to leave behind) — both of which are statements about a
 * SIMPLE RECTANGULAR container and not about containers in general; see `-isSimpleRectangularTextContainer`. */
- (NSRect)lineFragmentRectForProposedRect:(NSRect)proposedRect
			   sweepDirection:(NSLineSweepDirection)sweepDirection
		       movementDirection:(NSLineMovementDirection)movementDirection
			    remainingRect:(NSRect *)remainingRect
{
	NSRect region = NSMakeRect(0.0, 0.0, _size.width, _size.height);
	NSRect fragment = NSIntersectionRect(proposedRect, region);

	(void)sweepDirection;
	/* **AND THE MOVEMENT IS "CARRY THE RECTANGLE BACK UNTIL IT MEETS AN EDGE", WHICH IS THE ONLY READING A RECTANGLE
	 * HAS.** Apple's comment says the direction is where the proposed rect "can be translated if it is necessary to
	 * move the rect to find a non-empty fragment", so the rectangle is put against the region's near edge on that
	 * side and the intersection is taken again — which is a line the typesetter asked about being given the nearest
	 * place it could go. `NSLineDoesntMove` refuses to try, and an empty answer is then the honest one. */
	if (NSIsEmptyRect(fragment)) {
		switch (movementDirection) {
		case NSLineMovesRight:
			proposedRect.origin.x = NSMinX(region);
			break;
		case NSLineMovesLeft:
			proposedRect.origin.x = NSMaxX(region) - NSWidth(proposedRect);
			break;
		case NSLineMovesDown:
			proposedRect.origin.y = NSMinY(region);
			break;
		case NSLineMovesUp:
			proposedRect.origin.y = NSMaxY(region) - NSHeight(proposedRect);
			break;
		default:
			break;
		}
		fragment = NSIntersectionRect(proposedRect, region);
	}
	if (remainingRect != NULL) {
		*remainingRect = NSZeroRect;
	}
	return fragment;
}

- (BOOL)isSimpleRectangularTextContainer
{
	/* APPLE'S OWN DEFAULT, and the promise the rest of this file is written against: a subclass with a hole or a
	 * concavity says NO, and then the fragment arithmetic stops being an intersection. */
	return YES;
}

- (BOOL)containsPoint:(NSPoint)point
{
	return NSPointInRect(point, NSMakeRect(0.0, 0.0, _size.width, _size.height));
}

@end
