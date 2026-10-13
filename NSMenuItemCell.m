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
/* **THE MENU VIEW'S HEADER, BECAUSE THIS FILE ASKS IT A QUESTION** — whether the row being drawn has a column to be
 * centred in. It imports the AppKit spelling rather than the local path: this file includes its own class the same
 * way, and the generated include directory is what a consumer sees. Forward-declaring it would leave `-isHorizontal`
 * answering `id`, which is the error this tree has already paid for twice. */
#import <AppKit/NSMenuView.h>
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

/* **WHAT A MENU ROW IS SET IN: THE SYSTEM FONT AT THE SYSTEM'S OWN SIZE.** The two halves were 12 and 13 in the
 * wrong order — the drawing doors asked for `systemFontOfSize:12.0`, a number nobody had chosen, while
 * `+[NSFont systemFontSize]` answered 13, which is the Mac's own menu size and had been in this tree all along. The
 * menus came out visibly smaller than the system they are part of.
 *
 * AND IT IS ONE DOOR BECAUSE THE MEASUREMENT HAS TO MOVE WITH THE DRAWING: `-calcSize` computes the columns the
 * titles are drawn into, so a row set in a larger face than it was measured in would clip its own text. That is
 * why this is a method rather than a number written twice. */
- (NSFont *)cg_titleFont
{
	CGFloat size = [NSFont systemFontSize];
	NSFont *font = _bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];

	if (font == nil) {
		font = [NSFont systemFontOfSize:(CGFloat)12.0];
	}
	return font;
}

- (BOOL)bold
{
	return _bold;
}

- (void)setBold:(BOOL)flag
{
	if (flag == _bold) {
		return;
	}
	_bold = flag;
	/* **AND THE MEASUREMENT IS NOW STALE**, which is the other half of this being one door: a bold face is WIDER,
	 * so the column this row was measured into is too narrow for what will be drawn in it. The flag that makes
	 * `-calcSize` measure again is the fix, and forgetting it is how a bold title comes to be clipped by its own
	 * cell. */
	_needsSizing = YES;
}

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
					/* **AND THE TWO TEXT WIDTHS ARE MEASURED IN THE FACE AND THE SIZE THE TITLE IS DRAWN IN.** This block
			 * passed NIL for the attributes, which means THE DEFAULT attributes — `NSStringDrawing`'s own default font
			 * at its own size — while the drawing doors asked for the system font at a size of their own. MEASURED:
			 * twelve and thirteen, so every row was LAID OUT one size and SET IN another. Fixing "the menus are too
			 * small" without this line would have replaced one wrong thing with a CLIPPED one.
			 *
			 * AND THE NIL WAS NOT LAZINESS, which is worth the two lines: this call used to RAISE — the default font
			 * was put into a dictionary even when there was none, and `-setObject:` raises on nil — so the widths
			 * were zero for as long as the font registry found no fonts at all. Nil then was what WORKED, and what
			 * works is not the same question as what a row is set in.
			 *
			 * A NIL TITLE STILL MEASURES ZERO BY ARITHMETIC RATHER THAN BY A GUARD, which is a different zero and
			 * worth keeping apart: a separator has no title, and neither does an image-only item. */
			{
				NSString *title = [_menuItem title];
				NSString *key = [_menuItem keyEquivalent];
				NSFont *font = [self cg_titleFont];
				NSDictionary *attributes = (font != nil)
					? [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]
					: [NSDictionary dictionary];

				if (title != nil) {
					_titleWidth = [title sizeWithAttributes:attributes].width;
				}
				if (key != nil && [key length] > 0) {
					_keyEquivalentWidth = [key sizeWithAttributes:attributes].width;
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
	NSFont *font = [self cg_titleFont];
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
	/* **A BAR'S TITLE IS CENTRED IN ITS COLUMN AND A DROPDOWN'S IS NOT.** The column is the title's own width
	 * plus the bar's padding either side, so a title drawn at the column's LEFT edge puts all the slack on the
	 * right: MEASURED, the accent chip was x=215..260 (46 px) with the title's ink at x=218..238 — three pixels of
	 * air on the left and twenty-two on the right, which is what "aligned to the left of the text" is. A DROPDOWN's
	 * title stays left-aligned, because that is its indent.
	 *
	 * **AND IT IS THE VIEW THAT IS ASKED, NOT A FLAG ON THE CELL.** Whether a row is a bar's title or a dropdown's
	 * is a property of the MENU VIEW the cell is being drawn in — the same division the background door states, one
	 * door down: the parts are the cell's and the arrangement is the view's. A cell with no view (a measurement, a
	 * test drawing one on its own) is therefore left-aligned, which is the dropdown's answer and the safe one. */
	{
		NSSize text = [title sizeWithAttributes:attributes];

		if ([controlView respondsToSelector:@selector(isHorizontal)] &&
		    [(NSMenuView *)controlView isHorizontal]) {
			CGFloat slack = rect.size.width - text.width;

			width = text.width;
			left = rect.origin.x + ((slack > 0.0) ? slack / 2.0 : 0.0);
		} else {
			left = rect.origin.x + 2.0;
			width = rect.size.width - 4.0;
		}
	}
	if (width <= 0.0) {
		return;
	}
	/* **AND A TITLE IS CENTRED VERTICALLY IN ITS ROW, WHICH IS THE MAC'S ANSWER AND WAS NOT THIS ONE.** MEASURED:
	 * the titles in an application's menu bar read as sitting too high, and the reason is two-fold — `drawInRect:`
	 * lays a Core Text frame out FROM THE RECT'S TOP DOWNWARD, and the rect it was given was the row's whole
	 * height. So the ink hung from the top edge of the row instead of being centred in it, and in a 24-pixel bar a
	 * row of 22 put it lower still.
	 *
	 * `-sizeWithAttributes:` is the same measurement `-calcSize` uses for the column's width, so the two agree by
	 * construction: this centres the LINE, and the line is what the cell measured. */
	{
		/* **CENTRED ON THE FONT'S ASCENT AND DESCENT, NOT ON THE MEASURED LINE — AND THE DIFFERENCE IS THE WHOLE
		 * BUG.** `-sizeWithAttributes:` answers a LINE height, which includes the leading above the ascent and
		 * below the descent; the INK hangs from the line's TOP, so centring the line leaves the text visibly high.
		 * MEASURED: centring the line put the titles' ink on rows 2..12 of a 24-pixel bar, a centre of 7.0 where
		 * the bar's is 11.5.
		 *
		 * The baseline is what has an unambiguous place: Apple's own rule for centring text in a box is to put it
		 * so that the ascent-and-descent band is centred, and that band is what a reader sees. Core Text fills a
		 * frame from its rect's top downward, so the rect handed over is exactly that band. */
		CGFloat ascent = [font ascender];
		CGFloat descent = (CGFloat)fabs((double)[font descender]);
		CGFloat band = ascent + descent;
		CGFloat baseline = rect.origin.y + (rect.size.height - band) / 2.0 + descent;

		[title drawInRect:NSMakeRect(left, baseline - descent, width, band) withAttributes:attributes];
	}
}

- (void)drawKeyEquivalentWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSString *key = [_menuItem keyEquivalent];
	NSRect rect = [self keyEquivalentRectForBounds:cellFrame];
	NSFont *font = [self cg_titleFont];
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
