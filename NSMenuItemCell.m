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

		/* THE STATE IMAGE'S WIDTH STAYS ZERO, AND FOR A REASON THAT IS NOT THE TEXT'S: `NSMenuItem` in this tier
		 * has no state-image door — the item's own rows have not carried it — so there is nothing here to
		 * measure. Calling one would be worse than leaving the zero: THIS PROJECT'S RUNTIME RAISES on a selector
		 * an object does not implement, so the honest zero beats an abort. When that row lands, this is the line
		 * that measures it.
		 *
		 * AND THE IMAGE'S WIDTH IS A REAL MEASUREMENT: an image answers `-size`, and this tier has NSImage. */
		if (image != nil) {
			_imageWidth = [image size].width;
		}
		/* AND THE TWO TEXT WIDTHS STAY ZERO, WHICH IS THE HONEST ANSWER RATHER THAN A GUESS: the title's width
		 * and the key equivalent's width are font measurements, and this tier has no metrics on this side of the
		 * library — the same gap `NSMenu`'s `-sizeToFit` refuses over, one class over. A number invented here
		 * would be a guess wearing a measurement's clothes, and the drawing half that lands a font replaces both
		 * of these lines. */
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
	fprintf(stderr, "APPKIT-REFUSE: -drawSeparatorItemWithFrame:inView: needs THE INK — the separator's own "
			"style (Apple's is a themed groove, not a line) and the menu view's frame plumbing\n");
}

- (void)drawStateImageWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
	fprintf(stderr, "APPKIT-REFUSE: -drawStateImageWithFrame:inView: needs THE INK — an image destination and a "
			"compositing operation; the RECT this would draw into is real (-stateImageRectForBounds:)\n");
}

- (void)drawImageWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
	fprintf(stderr, "APPKIT-REFUSE: -drawImageWithFrame:inView: needs THE INK — the same missing compositing "
			"path as the state image's door\n");
}

- (void)drawTitleWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
	fprintf(stderr, "APPKIT-REFUSE: -drawTitleWithFrame:inView: needs TEXT METRICS AND A TEXT RUN — the font "
			"this tier has not got on this side of the library, which is also why `-titleWidth` is zero\n");
}

- (void)drawKeyEquivalentWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	(void)cellFrame;
	(void)controlView;
	fprintf(stderr, "APPKIT-REFUSE: -drawKeyEquivalentWithFrame:inView: needs TEXT METRICS AND A TEXT RUN, the "
			"same ground the title's door refuses on\n");
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
