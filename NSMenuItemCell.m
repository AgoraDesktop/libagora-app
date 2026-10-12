/*
 * NSMenuItemCell — where each part of a menu item goes, and what it needs before it can be painted.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE ARITHMETIC HERE IS THE WHOLE POINT OF THE CLASS, SO IT IS IN ONE PLACE AND IT IS STATED ONCE: a menu row
 * runs left to right as STATE IMAGE, IMAGE, TITLE, then the KEY EQUIVALENT against the right edge. The three rect
 * doors below are that sentence written three times — each one takes the strip it names, and the title takes what
 * is left between the image and the key equivalent, which is why nothing has to name the gap.
 *
 * AND THE MEASUREMENT IS HONEST ABOUT WHAT IT CANNOT DO. The state image's width and the image's width come from
 * the images, which this tier HAS. The TITLE'S AND THE KEY EQUIVALENT'S DO NOT, because measuring a string needs a
 * font, and this tier has none on this side — so those two widths stay ZERO and the reason is written where the
 * number is produced rather than left for a reader to wonder at. A zero-width title rect is the true answer to
 * "where would this go if nothing were measured", and the drawing half that lands a font will replace it.
 */
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSStringDrawing.h>	/* -sizeWithAttributes:, the measurement -calcSize makes */
/* **THE INK'S OWN HEADERS**, which this file did not need while every drawing door refused: the face the title is
 * set in, the colour it is drawn in, and the path a separator is stroked with. */
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSImage.h>

#include <stdio.h>

@implementation NSMenuItemCell

- (instancetype)init
{
	if ((self = [super init]) != nil) {
		/* A NEW CELL NEEDS BOTH: it has never been measured and has never been drawn. */
		_needsSizing = YES;
		_needsDisplay = YES;
	}
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

/* ---- THE ITEM, THE TAG, AND THE TWO FLAGS ------------------------------------------------------- */

- (id)menuItem
{
	return _menuItem;
}

- (void)setMenuItem:(id)anItem
{
	/* NOT RETAINED — the link runs the other way, which is Apple's arrangement and the header says so. AND THE
	 * ONE CALL SETS BOTH FLAGS, because a different item is both a different size and a different picture: this
	 * is the door that makes `-needsSizing` and `-needsDisplay` have a writer. */
	_menuItem = anItem;
	_needsSizing = YES;
	_needsDisplay = YES;
}

- (NSInteger)tag
{
	/* THE ITEM'S TAG, not a field of this cell's: with no item there is no tag, and zero is the honest answer. */
	return _menuItem != nil ? (NSInteger)[_menuItem tag] : 0;
}

- (BOOL)needsSizing
{
	return _needsSizing;
}

- (void)setNeedsSizing:(BOOL)flag
{
	_needsSizing = flag;
}

- (BOOL)needsDisplay
{
	return _needsDisplay;
}

- (void)setNeedsDisplay:(BOOL)flag
{
	_needsDisplay = flag;
}

/* ---- THE MEASUREMENT ---------------------------------------------------------------------------- */

- (void)calcSize
{
	/* MEASURING ONLY WHEN SOMETHING CHANGED is what the flag is for, and clearing it here is what makes the flag
	 * have a reader. A caller can therefore call this as often as it likes. */
	if (!_needsSizing) {
		return;
	}
	_stateImageWidth = 0.0;
	_imageWidth = 0.0;
	_titleWidth = 0.0;
	_keyEquivalentWidth = 0.0;
	if (_menuItem != nil) {
		id image = [_menuItem image];

		/* **AND THE STATE IMAGE IS MEASURED NOW, WHICH THIS COMMENT SAID COULD NOT BE DONE.** It claimed
		 * "`NSMenuItem` in this tier has no state-image door" — and the item HAS THREE (`onStateImage`,
		 * `offStateImage`, `mixedStateImage`) plus the `state` that chooses between them. The zero here was not
		 * honesty about a missing door; it was a claim about a door that was there the whole time.
		 *
		 * THE IMAGE FOR THE ITEM'S OWN STATE IS WHAT THE COLUMN IS SIZED BY, which is Apple's arrangement: a
		 * menu row's checkmark column is as wide as the picture the item would show, and an item with no such
		 * picture has a column of no width — so a menu of plain items pays nothing for a column none of them
		 * use. THIS TIER SHIPS NO SYSTEM CHECKMARK, so the zero is the answer for an item that named none. */
		{
			NSImage *state = nil;

			switch ([_menuItem state]) {
			case NSOnState:
				state = [_menuItem onStateImage];
				break;
			case NSMixedState:
				state = [_menuItem mixedStateImage];
				break;
			default:
				state = [_menuItem offStateImage];
				break;
			}
			if (state != nil) {
				_stateImageWidth = [state size].width;
			}
		}
		/* AND THE IMAGE'S WIDTH IS A REAL MEASUREMENT: an image answers `-size`, and this tier has NSImage. */
		if (image != nil) {
			_imageWidth = [image size].width;
		}
		/* **AND THE TWO TEXT WIDTHS ARE MEASURED NOW — AND THEY ARE ZERO BECAUSE THERE IS NO FONT, NOT BECAUSE
		 * NOBODY ASKED.** The measurement used to RAISE: `-sizeWithAttributes:` inserted the default font into a
		 * dictionary even when there was none, and `-setObject:` raises on nil. That is fixed one row over in
		 * `NSStringDrawing` — a door that raises where the API it clones permits the call is a crash with a good
		 * excuse rather than a refusal by name — so this call runs now, and what it reports is the truth about
		 * this host:
		 *
		 *     +[NSFont systemFontOfSize:12.0]            -> NIL          (measured)
		 *     [@"Open Recent" sizeWithAttributes:nil]    -> 0 x 0        (measured)
		 *
		 * **SO THE NEXT BLOCKER IS THE FONT SERVICE AND NOT THE DRAWING.** Until `+[NSFont systemFontOfSize:]`
		 * answers a face, every title is zero wide, and a menu laid out from these numbers would be a column of
		 * empty rows — which is what a menu looks like today, for a reason that is now named rather than guessed.
		 *
		 * AND A NIL TITLE MEASURES ZERO BY ARITHMETIC RATHER THAN BY A GUARD, which is a DIFFERENT zero from the
		 * one above and worth keeping distinct: a separator has no title, and neither does an image-only item.
		 * This paragraph's zero is a missing font; that one's is a missing title. */
		{
			NSString *title = [_menuItem title];
			NSString *key = [_menuItem keyEquivalent];

			if (title != nil) {
				_titleWidth = [title sizeWithAttributes:nil].width;
			}
			if (key != nil && [key length] > 0) {
				_keyEquivalentWidth = [key sizeWithAttributes:nil].width;
			}
		}

	}
	_needsSizing = NO;
}

- (CGFloat)stateImageWidth
{
	return _stateImageWidth;
}

- (CGFloat)imageWidth
{
	return _imageWidth;
}

- (CGFloat)titleWidth
{
	return _titleWidth;
}

- (CGFloat)keyEquivalentWidth
{
	return _keyEquivalentWidth;
}

/* ---- THE THREE RECTS: ONE SENTENCE, WRITTEN THREE TIMES ----------------------------------------- */

- (NSRect)stateImageRectForBounds:(NSRect)cellFrame
{
	/* THE LEFTMOST STRIP. A zero width is a zero-width rect rather than a special case: the arithmetic is the same
	 * sentence whether or not there is a state image to put in it. */
	NSRect rect = cellFrame;

	rect.size.width = _stateImageWidth;
	return rect;
}

- (NSRect)titleRectForBounds:(NSRect)cellFrame
{
	/* WHAT IS LEFT BETWEEN THE IMAGE AND THE KEY EQUIVALENT, which is why nothing names the gap: the title takes
	 * everything after the two strips on the left and before the strip on the right, AND THE SUBTRACTION IS
	 * CLAMPED AT ZERO so that a row narrower than its own parts produces an empty rect instead of a negative one
	 * running off the left edge. */
	NSRect rect = cellFrame;
	CGFloat used = _stateImageWidth + _imageWidth + _keyEquivalentWidth;

	rect.origin.x += _stateImageWidth + _imageWidth;
	rect.size.width = (cellFrame.size.width > used) ? (cellFrame.size.width - used) : 0.0;
	return rect;
}

- (NSRect)keyEquivalentRectForBounds:(NSRect)cellFrame
{
	/* THE RIGHTMOST STRIP: the key equivalent is pinned to the trailing edge, so its rect is measured from the
	 * far side rather than from the near one. */
	NSRect rect = cellFrame;

	rect.origin.x += cellFrame.size.width - _keyEquivalentWidth;
	rect.size.width = _keyEquivalentWidth;
	return rect;
}

/* ---- AND THE SIX DRAWING DOORS, EACH REFUSING BY NAME ------------------------------------------- */

/* EACH OF THESE IS ONE CALL AND ONE LINE ON stderr, AND THEY SHARE A GROUND: THE INK. This class owns WHERE a
 * part of a row goes (the three rects above are real, and a caller can use them today); it does not own how the
 * part is painted, which needs a font to measure a string, a text run to draw it, and the menu view's own frame
 * and state plumbing. Present rather than omitted so that a caller can compile against Apple's surface and learn
 * BY NAME what is missing — and NOT A STUB: a stub pretends, and these decline out loud. */

- (void)drawSeparatorItemWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
	{
		/* **A SEPARATOR IS A HAIRLINE ACROSS THE ROW, AND APPLE'S IS A THEMED GROOVE RATHER THAN A LINE** — so
		 * this draws the line and says so, instead of inventing a groove. The colour is a mid grey rather than a
		 * named system colour because this tier has no theme to ask, which is the same reason the system font was
		 * a regular face of no particular family. */
		NSBezierPath *line = [NSBezierPath bezierPath];

		[[NSColor colorWithCalibratedRed:0.55 green:0.55 blue:0.55 alpha:1.0] setStroke];
		[line moveToPoint:NSMakePoint(cellFrame.origin.x, cellFrame.origin.y + cellFrame.size.height / 2.0)];
		[line lineToPoint:NSMakePoint(cellFrame.origin.x + cellFrame.size.width,
					      cellFrame.origin.y + cellFrame.size.height / 2.0)];
		[line stroke];
	}
}

- (void)drawStateImageWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSImage *state;
	NSSize size;
	NSRect rect = [self stateImageRectForBounds:cellFrame];

	(void)controlView;
	if (rect.size.width <= 0.0) {
		return;		/* the column is zero wide because the item named no state image, which is an answer */
	}
	switch ([_menuItem state]) {
	case NSOnState:
		state = [_menuItem onStateImage];
		break;
	case NSMixedState:
		state = [_menuItem mixedStateImage];
		break;
	default:
		state = [_menuItem offStateImage];
		break;
	}
	if (state == nil) {
		return;
	}
	size = [state size];
	[state drawInRect:NSMakeRect(rect.origin.x, cellFrame.origin.y + (cellFrame.size.height - size.height) / 2.0,
				     rect.size.width, size.height)];
}

- (void)drawImageWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSImage *image = [_menuItem image];
	NSSize size;

	(void)controlView;
	/* NOTHING TO DRAW IS NOT A REFUSAL, the rule the title's door keeps: an item without an image is a row with
	 * an empty image column, which is a correct answer. */
	if (image == nil || _imageWidth <= 0.0) {
		return;
	}
	size = [image size];
	/* **AND THE IMAGE IS DRAWN IN ITS OWN COLUMN AND CENTRED IN THE ROW.** `-imageWidth` is the column's width
	 * — measured in `-calcSize` — and the image's own height is what it is: a row is 22 pixels and a menu icon is
	 * rarely that tall, so a picture drawn into the whole row would be stretched to fill a space nobody asked it
	 * to fill. */
	[image drawInRect:NSMakeRect(cellFrame.origin.x + _stateImageWidth,
				     cellFrame.origin.y + (cellFrame.size.height - size.height) / 2.0,
				     _imageWidth, size.height)];
}

- (void)drawTitleWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSString *title = [_menuItem title];
	NSRect rect = [self titleRectForBounds:cellFrame];
	NSFont *font = [NSFont systemFontOfSize:(CGFloat)12.0];
	NSDictionary *attributes;
	CGFloat left, width;

	(void)controlView;
	/* **AND A DOOR WITH NOTHING TO SAY SAYS NOTHING, WHICH IS NOT A REFUSAL.** A separator has no title, an
	 * image-only item has none, and a row too narrow for its own parts has an empty title rect — three correct
	 * answers, and none of them the missing ink this door used to report. */
	if (title == nil || [title length] == 0 || rect.size.width <= 4.0) {
		return;
	}
	/* THE ONE REFUSAL THAT REMAINS, AND IT IS A REAL ONE: text to draw and no face to draw it in. That is the
	 * font registry having found nothing, which is a fact about the host and not about this cell. */
	if (font == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -drawTitleWithFrame:inView: has a title to draw and NO FACE to draw it "
				"in — +[NSFont systemFontOfSize:] answered nil, so the font registry found no fonts\n");
		return;
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
		      [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
	/* **THE INSET IS THE ROW'S OWN PADDING, WHICH IS WHY IT IS DRAWN HERE RATHER THAN SUBTRACTED IN THE RECT
	 * DOOR**: `-titleRectForBounds:` answers where the title's COLUMN is, and how much air an item leaves inside
	 * its own column is a property of the drawing. */
	left = rect.origin.x + 2.0;
	width = rect.size.width - 4.0;
	if (width <= 0.0) {
		return;
	}
	[title drawInRect:NSMakeRect(left, rect.origin.y, width, rect.size.height) withAttributes:attributes];
}

- (void)drawKeyEquivalentWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSString *key = [_menuItem keyEquivalent];
	NSRect rect = [self keyEquivalentRectForBounds:cellFrame];
	NSFont *font = [NSFont systemFontOfSize:(CGFloat)12.0];
	NSDictionary *attributes;
	CGFloat width;

	(void)controlView;
	if (key == nil || [key length] == 0 || rect.size.width <= 2.0) {
		return;
	}
	if (font == nil) {
		return;		/* the title's door has already said why, and saying it twice per row is noise */
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
		      [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
	width = rect.size.width - 2.0;
	if (width <= 0.0) {
		return;
	}
	[key drawInRect:NSMakeRect(rect.origin.x, rect.origin.y, width, rect.size.height)
	 withAttributes:attributes];
}

- (void)drawBorderAndBackgroundWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
	fprintf(stderr, "APPKIT-REFUSE: -drawBorderAndBackgroundWithFrame:inView: needs THE MENU VIEW'S OWN STYLE "
			"(the highlight and the background are the bar's or the dropdown's, and neither has been written)\n");
}

/* ---- AND THE TWO INITIALISERS -------------------------------------------------------------------- */

/* **AND `-initTextCell:` IS NO LONGER OVERRIDDEN AT ALL, WHICH IS THE WHOLE CHANGE THIS UNIT MAKES HERE.** It used to
 * refuse, and the refusal's stated ground was that "this tier has no cell family, so this class stands on `NSObject`"
 * — a ground §A10ax's re-base had already removed when it put this class on `NSButtonCell`, and which §A10bi makes
 * fully false by giving `NSCell` the two designated initialisers Apple declares. A REFUSAL WHOSE REASON HAS EXPIRED IS
 * WORSE THAN NO REFUSAL: it turns a working inherited door into a nil. So the override is gone and the class inherits.
 *
 * AND WHAT THE INHERITED DOOR DOES NOT CHANGE IS WHAT THIS CELL DRAWS: a title stored on the cell is state the
 * drawing doors do not read — the item's title is what `-drawTitleWithFrame:inView:` will use — which is the fact the
 * original refusal was reaching for. It is a fact about the DRAWING, though, not a reason to refuse a constructor. */

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
	(void)coder;
	fprintf(stderr, "APPKIT-REFUSE: -initWithCoder: needs Apple's published key set for an archived cell, and "
			"this duplication has not got one\n");
	return nil;
}

@end
