/*
 * NSTextView.m — many lines where `NSText` holds one: the line model, and the layout that reads it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE WHOLE OF THIS FILE IS ONE IDEA: A LINE IS A `\n`-TERMINATED RUN, AND EVERYTHING ELSE IS THAT IDEA READ.**
 * `NSText` measured its single line with Core Text directly; this class measures EACH line with the same engine, once
 * per line, and the four things a text view has to place — the glyphs, the selection's band, the caret, and a click —
 * all read the same three numbers (the line's range, its baseline, and the x of a character index within it). That is
 * why there is no separate "layout" object here: the layout is a function of the string, and `-cg_characterRangeOfLine:`
 * is that function.
 *
 * **AND THE ONE THING IT TAKES AWAY FROM ITS BASE IS THE HORIZONTAL ORIGIN.** `NSText` carries its own side-scroll
 * because it is a single-line field with no clip view; a document's scrolling belongs to a clip view, and this tier
 * has not put one around a text view yet — so `-scrollRangeToVisible:` here answers the honest thing for a view that
 * does not scroll, which is an origin of ZERO, and a line wider than the view is CLIPPED. Wrapping and scrolling are
 * slices II and III in the header, and neither is faked here.
 *
 * **THE Y AXIS GOES DOWN FROM THE TOP AND THE VIEW'S OWN GOES UP.** Line 0 is the TOP line, at the same baseline
 * `NSText` places its single line at (`NSMaxY(bounds) - NS_TEXT_INSET - ascender`), and each line after it is one
 * line-height lower — so a document that fits reads top-down while the coordinates underneath stay the y-up ones every
 * other view in this tree uses.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/NSNotification.h>

#include <CoreGraphics/CGContext.h>
#include <CoreText/CTLine.h>
#include <CoreText/CTStringAttributes.h>

@implementation NSTextView

/* ============================================================================================ *
 * THE LINE MODEL: THE ONE FUNCTION EVERY OTHER ANSWER BELOW READS                                *
 * ============================================================================================ */

/* **AND THE COUNT COUNTS BREAKS RATHER THAN RUNS, WHICH IS WHAT MAKES A TRAILING NEWLINE AN EMPTY LAST LINE.** "a\n"
 * has one break in it and therefore TWO lines — "a" and "" — and that is the state a document is in when the caret
 * sits on a fresh line at the end, which a `-componentsSeparatedByString:` would get right by accident and a count of
 * runs would get wrong on purpose. An EMPTY STRING is one empty line, not none: a view with no text still has a place
 * to put the caret. */
- (NSUInteger)cg_lineCount
{
	NSUInteger n = [_string length];
	NSUInteger count = 1;
	NSUInteger i;

	for (i = 0; i < n; i++) {
		if ([_string characterAtIndex:i] == '\n') {
			count++;
		}
	}
	return count;
}

/* THE LINE A CHARACTER INDEX IS ON, counting the breaks before it. An index AT a break belongs to the line the break
 * ends — the caret just after "ab" in "ab\ncd" is index 2, which is still line 0 — and an index one past it is the
 * next line's first character. */
- (NSUInteger)cg_lineIndexForCharacterIndex:(NSUInteger)index
{
	NSUInteger n = [_string length];
	NSUInteger line = 0;
	NSUInteger i;

	if (index > n) {
		index = n;
	}
	for (i = 0; i < index; i++) {
		if ([_string characterAtIndex:i] == '\n') {
			line++;
		}
	}
	return line;
}

/* **AND A LINE'S RANGE EXCLUDES ITS OWN TERMINATOR, WHICH IS THE DECISION THE WHOLE MODEL TURNS ON.** A caller that
 * wants to replace a line's text — a formatter, a highlighter, a spelling pass — must not have to know whether the
 * break is inside the range it was handed; keeping it out means the answer to "what is on this line" never includes
 * the thing that ends it. A line that runs to the end of the string answers a range with no break in it, and a LINE
 * PAST THE LAST answers the empty range at the end rather than a wrong one. */
- (NSRange)cg_characterRangeOfLine:(NSUInteger)line
{
	NSUInteger n = [_string length];
	NSUInteger current = 0;
	NSUInteger start = 0;
	NSUInteger i;
	NSUInteger end;

	for (i = 0; i < n; i++) {
		if ([_string characterAtIndex:i] != '\n') {
			continue;
		}
		if (current == line) {
			return NSMakeRange(start, i - start);
		}
		current++;
		start = i + 1;
	}
	if (current != line) {
		return NSMakeRange(n, 0);
	}
	end = start;
	while (end < n && [_string characterAtIndex:end] != '\n') {
		end++;
	}
	return NSMakeRange(start, end - start);
}

/* ============================================================================================ *
 * THE THREE NUMBERS THE LAYOUT IS MADE OF: THE FONT, THE LINE'S HEIGHT, AND A LINE'S BASELINE    *
 * ============================================================================================ */

- (NSFont *)cg_font
{
	NSFont *font = [self font];

	return (font != nil) ? font : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

/* THE FONT'S OWN BAND, which is a fact about the FONT and not about any line's text — so an empty line is the same
 * height as a full one and a document does not jump when a character arrives on a blank line. */
- (CGFloat)cg_lineHeight
{
	NSFont *font = [self cg_font];

	return [font ascender] - [font descender];
}

/* **LINE 0 SITS WHERE A ONE-LINE VIEW'S WOULD AND EVERY LINE AFTER IT IS ONE BAND LOWER**, so a document that fits the
 * view reads from the top down. The arithmetic is the base's `-fn_baseline` with one line-height subtracted per line,
 * which is what "the same baseline, stepped" means. */
- (CGFloat)cg_baselineForLine:(NSUInteger)line
{
	NSFont *font = [self cg_font];

	return NSMaxY([self bounds]) - NS_TEXT_INSET - [font ascender] - (CGFloat)line * [self cg_lineHeight];
}

/* **AND A `CTLine` IS BUILT FOR A RANGE RATHER THAN FOR THE WHOLE STRING.** That is the one change from the base's
 * `-createLine`, and it is forced by Core Text itself: a `CTLine` does not break at newlines — it lays the string it is
 * given as ONE line — so a multi-line view has to hand it one line's worth at a time. A range with no characters in it
 * answers NULL, which every caller below reads as "an empty line with no glyphs": the caret sits at the inset and the
 * width is zero. */
- (CTLineRef)cg_createLineForRange:(NSRange)range
{
	NSFont *font = [self cg_font];
	NSString *sub = [_string substringWithRange:range];
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;
	CTLineRef line;

	attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(attributes, kCTFontAttributeName, ((NSFont *)font)->_font);
	s = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)sub, attributes);
	CFRelease(attributes);
	if (s == NULL) {
		return NULL;
	}
	line = CTLineCreateWithAttributedString(s);
	CFRelease(s);
	return line;
}

/* THE X OF A CHARACTER INDEX, measured from the LEFT EDGE OF ITS OWN LINE — every line begins at the same inset, so
 * this is also its x in the view. The index is made relative to the line's start before Core Text is asked, because
 * Core Text counts from the start of the line it was given. */
- (CGFloat)cg_xForIndex:(NSUInteger)index
{
	NSRange lineRange = [self cg_characterRangeOfLine:[self cg_lineIndexForCharacterIndex:index]];
	CTLineRef line = [self cg_createLineForRange:lineRange];
	CGFloat x = -1.0;

	if (line != NULL) {
		x = (CGFloat)CTLineGetOffsetForStringIndex(line, (CFIndex)(index - lineRange.location), NULL);
		CFRelease(line);
	}
	return (x < 0.0) ? 0.0 : x;
}

/* **THE INVERSE, WHICH IS WHAT A CLICK ASKS: WHICH LINE FROM THE Y, THEN WHICH CHARACTER FROM THE X.** The line is
 * arithmetic — the distance down from the top of the first line, divided by the band — and only the character is Core
 * Text's, because only the character needs glyph offsets. A click above the first line lands on line 0 and one below
 * the last lands on the last, which is what clamping a document view's pointer means. */
- (NSUInteger)cg_indexForPoint:(NSPoint)point
{
	CGFloat lineHeight = [self cg_lineHeight];
	CGFloat top = NSMaxY([self bounds]) - NS_TEXT_INSET;
	CGFloat offset = top - point.y;
	NSUInteger line;
	NSRange lineRange;
	CTLineRef ctline;
	CFIndex index = 0;

	if (lineHeight <= 0.0 || offset <= 0.0) {
		line = 0;
	} else {
		line = (NSUInteger)(offset / lineHeight);
	}
	if (line >= [self cg_lineCount]) {
		line = [self cg_lineCount] - 1;
	}
	lineRange = [self cg_characterRangeOfLine:line];
	ctline = [self cg_createLineForRange:lineRange];
	if (ctline != NULL) {
		CGPoint where = CGPointMake(point.x - NS_TEXT_INSET, 0.0);

		index = CTLineGetStringIndexForPosition(ctline, where);
		CFRelease(ctline);
	}
	if (index < 0) {
		index = 0;
	}
	if ((NSUInteger)index > lineRange.length) {
		index = (CFIndex)lineRange.length;
	}
	return lineRange.location + (NSUInteger)index;
}

/* ============================================================================================ *
 * THE MEASUREMENT, WHICH IS EVERY LINE'S WIDTH AND EVERY LINE'S HEIGHT                          *
 * ============================================================================================ */

- (void)sizeToFit
{
	CGFloat width = 0.0;
	NSUInteger i, count = [self cg_lineCount];

	for (i = 0; i < count; i++) {
		CTLineRef line = [self cg_createLineForRange:[self cg_characterRangeOfLine:i]];

		if (line != NULL) {
			CGFloat w = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);

			if (w > width) {
				width = w;
			}
			CFRelease(line);
		}
	}
	[self setFrameSize:NSMakeSize(width + 2.0 * NS_TEXT_INSET,
				      (CGFloat)count * [self cg_lineHeight] + 2.0 * NS_TEXT_INSET)];
}

/* **AND A DOCUMENT VIEW DOES NOT CARRY ITS OWN HORIZONTAL ORIGIN, WHICH IS THE ONE THING THIS CLASS TAKES FROM ITS
 * BASE.** `NSText` side-scrolls its single line because it is a field with no clip view; a document's scrolling is the
 * clip view's, and this tier has not put one around a text view yet. So the origin is held at ZERO — a line wider than
 * the view is clipped at the edge rather than dragged sideways — and SCROLLING IS THE SLICE THAT WILL MAKE THIS REAL
 * (the header's slice III), not something inferred from a nonzero origin nobody scrolls. */
- (void)scrollRangeToVisible:(NSRange)range
{
	(void)range;
	_originX = 0.0;
}

/* ============================================================================================ *
 * THE DRAWING: THE BACKGROUND, THEN EVERY LINE'S BAND AND GLYPHS, THEN THE CARET                *
 * ============================================================================================ */

/* **AND THE BEZEL IS GONE, WHICH IS A DIFFERENCE FROM THE BASE WORTH STATING.** `NSText` is the editable surface under
 * a CONTROL, so it draws the field's border; a TEXT VIEW is the document itself — a surface with no frame around it —
 * and Apple's draws no bezel either. What it keeps is the BACKGROUND FILL, because a document over a window's grey
 * wants its own white. The rest of this method is the base's drawing run once per line. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	NSFont *font = [self cg_font];
	CGFloat bandHeight = [font ascender] - [font descender];
	NSUInteger i, count;

	(void)dirtyRect;
	if (cg == NULL) {
		return;
	}
	if (_drawsBackground) {
		[[self backgroundColor] != nil ? [self backgroundColor] : [NSColor controlBackgroundColor] setFill];
		[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
	}
	count = [self cg_lineCount];
	for (i = 0; i < count; i++) {
		NSRange range = [self cg_characterRangeOfLine:i];
		CGFloat baseline = [self cg_baselineForLine:i];
		CTLineRef line = [self cg_createLineForRange:range];
		NSRect band = NSZeroRect;
		NSUInteger selStart = _selectedRange.location;
		NSUInteger selEnd = selStart + _selectedRange.length;
		NSUInteger lo = (selStart > range.location) ? selStart : range.location;
		NSUInteger hi = (selEnd < range.location + range.length) ? selEnd : range.location + range.length;
		BOOL hasBand = NO;

		/* **THE SELECTION IS CLIPPED TO THIS LINE, ONE LINE AT A TIME**, which is what makes a selection that spans a
		 * break draw as a band on each line it covers rather than as one rectangle stretched across the gap. The
		 * intersection excludes the newline itself, so the break carries no band — which is honest: there is no glyph
		 * there to highlight. */
		if ([self isSelectable] && _selectedRange.length > 0 && lo < hi) {
			CGFloat x0 = NS_TEXT_INSET + [self cg_xForIndex:lo];
			CGFloat x1 = NS_TEXT_INSET + [self cg_xForIndex:hi];

			band = NSMakeRect(x0, baseline + [font descender], x1 - x0, bandHeight);
			hasBand = YES;
			[[NSColor cg_accentColor] setFill];
			[[NSBezierPath bezierPathWithRect:band] fill];
		}
		if (line != NULL) {
			[[NSColor controlTextColor] setFill];
			CGContextSetTextPosition(cg, NS_TEXT_INSET, baseline);
			CTLineDraw(line, cg);
			/* AND THE GLYPHS THE BAND COVERS ARE DRAWN AGAIN IN WHITE THROUGH A CLIP — the same second pass the base
			 * makes, for the same reason (selected text is drawn in the surface colour) and with the same limitation:
			 * this view holds ONE run, so the whole line is redrawn and the clip does the splitting. */
			if (hasBand) {
				CGContextSaveGState(cg);
				CGContextClipToRect(cg, band);
				[[NSColor whiteColor] setFill];
				CGContextSetTextPosition(cg, NS_TEXT_INSET, baseline);
				CTLineDraw(line, cg);
				CGContextRestoreGState(cg);
			}
			CFRelease(line);
		}
	}
	/* AND THE CARET, ON WHICHEVER LINE IT IS ON. A caret at a break (the index just before a newline) belongs to the
	 * line the break ends, so it is drawn at that line's right end, which is where a person sees it. */
	if (_editing && [self isEditable]) {
		NSUInteger caretLine = [self cg_lineIndexForCharacterIndex:_selectedRange.location];
		CGFloat baseline = [self cg_baselineForLine:caretLine];
		CGFloat x = NS_TEXT_INSET + [self cg_xForIndex:_selectedRange.location];

		[[NSColor controlTextColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(x, baseline + [font descender], 1.0, bandHeight)] fill];
	}
}

/* ============================================================================================ *
 * THE POINTER: A CLICK LANDS ON THE LINE IT IS OVER                                              *
 * ============================================================================================ */

/* **THE BASE'S PRESS WITH ONE EXPRESSION CHANGED, WHICH IS THE WHOLE DIFFERENCE A MULTI-LINE VIEW NEEDS FROM IT.** The
 * base hit-tests its one line; this one hit-tests the line the y falls in — see `-cg_indexForPoint:`. The anchor and
 * the drag are the base's arithmetic unchanged, because a selection over several lines is still two ends and a
 * pointer. */
- (void)mouseDown:(NSEvent *)event
{
	NSUInteger index;

	if (![self isSelectable]) {
		return;
	}
	if ([self isEditable]) {
		[[self window] makeFirstResponder:self];
	}
	index = [self cg_indexForPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	_dragAnchor = index;
	[self setSelectedRange:NSMakeRange(index, 0)];
	_dragging = YES;
}

- (void)mouseDragged:(NSEvent *)event
{
	NSUInteger here;

	if (!_dragging) {
		return;
	}
	here = [self cg_indexForPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	[self setSelectedRange:(here < _dragAnchor) ? NSMakeRange(here, _dragAnchor - here)
						    : NSMakeRange(_dragAnchor, here - _dragAnchor)];
}

/* ============================================================================================ *
 * THE EDITING: WHAT A ONE-LINE VIEW REFUSES, AND WHY THIS ONE DOES NOT                           *
 * ============================================================================================ */

/* **A NEWLINE IS TEXT HERE, WHICH IS THE ONE REFUSAL THIS CLASS OVERTURNS.** `NSText -insertText:` drops a newline by
 * name because it holds one line; a text view's whole point is that the break is a character like any other, so the
 * edit goes through the base's own primitive and the LINE MODEL picks the new line up on the next read. Everything
 * else about the door is the base's: an `NSAttributedString` is asked for its string, a non-editable view ignores the
 * key, and a nil is nothing to do. */
- (void)insertText:(id)insertString
{
	NSString *text = ([insertString isKindOfClass:[NSAttributedString class]])
			 ? [(NSAttributedString *)insertString string] : (NSString *)insertString;

	if (![self isEditable] || text == nil) {
		return;
	}
	[self replaceCharactersInRange:_selectedRange withString:text];
}

/* **AND THE TWO KEYS THAT MEANT "I AM DONE WITH THIS FIELD" NOW MEAN "PUT A BREAK HERE" AND "PUT A TAB HERE".** In a
 * field, Return ends the session and hands the value to the model; in a document there is no model to hand it to and
 * the person is asking for a second line. Tab is the same reversal: a field's Tab is a focus move, and a text view's
 * is a tab character — which is what makes a text view the place a form's field editor cannot be. */
- (void)insertNewline:(id)sender
{
	(void)sender;
	[self insertText:@"\n"];
}

- (void)insertTab:(id)sender
{
	(void)sender;
	[self insertText:@"\t"];
}

/* ============================================================================================ *
 * THE MOVEMENT: THE BASE'S INDEX ARITHMETIC, PLUS WHAT A LINE MODEL ADDS                        *
 * ============================================================================================ */

/* **"THE LINE" MEANS THE CARET'S OWN LINE HERE, WHERE IT MEANT THE WHOLE STRING FOR A FIELD.** That is the one
 * semantic change the base's four line commands need, and it is why they are overridden rather than inherited: a
 * one-line field's "beginning of line" is index 0 and its "end of line" is the string's end, which for a document are
 * the beginning and end of the DOCUMENT. The document ends have their own doors below. */
- (void)moveToBeginningOfLine:(id)sender
{
	NSRange range = [self cg_characterRangeOfLine:[self cg_lineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location, 0)];
}

- (void)moveToEndOfLine:(id)sender
{
	NSRange range = [self cg_characterRangeOfLine:[self cg_lineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location + range.length, 0)];
}

- (void)moveToBeginningOfLineAndModifySelection:(id)sender
{
	NSRange range = [self cg_characterRangeOfLine:[self cg_lineIndexForCharacterIndex:_selectedRange.location]];
	NSUInteger end = _selectedRange.location + _selectedRange.length;

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location, end - range.location)];
}

- (void)moveToEndOfLineAndModifySelection:(id)sender
{
	NSRange range = [self cg_characterRangeOfLine:[self cg_lineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(_selectedRange.location,
					   range.location + range.length - _selectedRange.location)];
}

/* **AND THE VERTICAL PAIR, WHICH IS THE ONE THING A LINE MODEL EXISTS FOR.** A movement up keeps the caret's COLUMN —
 * its x within its line — rather than its index, because a person stepping down a column of text means the column; the
 * x is turned back into an index on the target line, which is where the line's characters decide where the caret can
 * actually land. A move off either end stays put rather than wrapping to the neighbouring line, which is what every
 * editor does and what makes holding Down at the last line safe. */
- (NSUInteger)cg_indexOnLine:(NSUInteger)line atX:(CGFloat)x
{
	NSRange range = [self cg_characterRangeOfLine:line];
	CTLineRef ctline = [self cg_createLineForRange:range];
	CFIndex index = 0;

	if (ctline != NULL) {
		index = CTLineGetStringIndexForPosition(ctline, CGPointMake(x, 0.0));
		CFRelease(ctline);
	}
	if (index < 0) {
		index = 0;
	}
	if ((NSUInteger)index > range.length) {
		index = (CFIndex)range.length;
	}
	return range.location + (NSUInteger)index;
}

/* **A SELECTION COLLAPSES BEFORE THE STEP, AND TO THE END THE STEP IS GOING AWAY FROM** — the same rule the character
 * movements use, one line up: Down from a selection starts at its END (the bottom of it) and Up from its START, so the
 * caret leaves the selection in the direction it is travelling. The line and the column are then read from the position
 * the caret ACTUALLY has, not the one it had before the collapse. */
- (void)moveUp:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger line;
	CGFloat x;

	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(location, 0)];
	}
	line = [self cg_lineIndexForCharacterIndex:location];
	if (line == 0) {
		return;
	}
	x = [self cg_xForIndex:location];
	[self setSelectedRange:NSMakeRange([self cg_indexOnLine:line - 1 atX:x], 0)];
}

- (void)moveDown:(id)sender
{
	NSUInteger end = _selectedRange.location + _selectedRange.length;
	NSUInteger location = end;
	NSUInteger line;
	CGFloat x;

	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(end, 0)];
	}
	line = [self cg_lineIndexForCharacterIndex:location];
	if (line + 1 >= [self cg_lineCount]) {
		return;
	}
	x = [self cg_xForIndex:location];
	[self setSelectedRange:NSMakeRange([self cg_indexOnLine:line + 1 atX:x], 0)];
}

/* **AND EXTENDING BY A LINE MOVES THE ONE END THE DIRECTION MOVES**, which is the base's Shift rule one line up: the
 * selection's LOCATION is its UPPER end (a range keeps its lower index) and its END is its lower one, so Up rewrites
 * the location and Down the length. */
- (void)moveUpAndModifySelection:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger end = location + _selectedRange.length;
	NSUInteger line = [self cg_lineIndexForCharacterIndex:location];
	NSUInteger target;

	(void)sender;
	if (line == 0) {
		return;
	}
	target = [self cg_indexOnLine:line - 1 atX:[self cg_xForIndex:location]];
	[self setSelectedRange:NSMakeRange(target, end - target)];
}

- (void)moveDownAndModifySelection:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger end = location + _selectedRange.length;
	NSUInteger line = [self cg_lineIndexForCharacterIndex:end];
	NSUInteger target;

	(void)sender;
	if (line + 1 >= [self cg_lineCount]) {
		return;
	}
	target = [self cg_indexOnLine:line + 1 atX:[self cg_xForIndex:end]];
	[self setSelectedRange:NSMakeRange(location, target - location)];
}

/* **AND THE TWO DOCUMENT ENDS, WHICH ARE THE STRING'S OWN TWO ENDS.** They need no line at all — the first character
 * and the one past the last — which is why a one-line field could have implemented them from the start and simply had
 * no reason to: for a field, beginning-of-line and beginning-of-document are the same index. */
- (void)moveToBeginningOfDocument:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(0, 0)];
}

- (void)moveToEndOfDocument:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange([_string length], 0)];
}

- (void)moveToBeginningOfDocumentAndModifySelection:(id)sender
{
	NSUInteger end = _selectedRange.location + _selectedRange.length;

	(void)sender;
	[self setSelectedRange:NSMakeRange(0, end)];
}

- (void)moveToEndOfDocumentAndModifySelection:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(_selectedRange.location, [_string length] - _selectedRange.location)];
}

@end
