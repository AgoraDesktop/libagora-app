/*
 * NSTextView.m — many lines where `NSText` holds one, and each of those wrapped to the view's width.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **TWO UNITS, ONE MODEL.** A MODEL LINE is a `\n`-terminated run — arithmetic over the string, and the three
 * `cg_…OfLine:` doors. A VISUAL LINE is that model LAID OUT at the view's width, so a range a person reads as one line
 * may be several; the layout is a flat array of character ranges in reading order, and everything a text view places
 * (the glyphs, the selection, the caret, a click) reads that array. The BREAKING IS NOT DONE HERE: the tier has a
 * TYPESETTER (`CTTypesetter`, in `libagora-text`), and `-CTTypesetterSuggestLineBreak` answers exactly the question —
 * "how many characters fit" — reading the paragraph style's mode, handling a hard break of its own, and backing off to
 * a word boundary. This class decides WHEN to ask and what to do with the answer; it does not decide where a line
 * ends.
 *
 * **AND RE-WRAPPING IS A DIRTY FLAG RATHER THAN A CALL A CALLER MAKES.** The layout is rebuilt on the next read after
 * the text or the width changes, and the three doors that can change either clear the flag: `-replaceCharactersInRange:`
 * (the one edit primitive), `-setString:` (which writes the buffer directly) and `-setFrameSize:`. Nothing recomputes
 * eagerly, because a view that relaid out on every keystroke of a long document would do it once per character for a
 * frame that has not been drawn yet.
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

#include <stdlib.h>
#include <CoreGraphics/CGContext.h>
#include <CoreText/CTLine.h>
#include <CoreText/CTStringAttributes.h>
#include <CoreText/CTTypesetter.h>

@implementation NSTextView

- (void)dealloc
{
	free(_cg_visual);
	[super dealloc];
}

/* ============================================================================================ *
 * THE MODEL: A LINE IS A `\n`-TERMINATED RUN                                                *
 * ============================================================================================ */

/* **AND THE COUNT COUNTS BREAKS RATHER THAN RUNS, WHICH IS WHAT MAKES A TRAILING NEWLINE AN EMPTY LAST LINE.** "a\n"
 * has one break in it and therefore TWO lines — "a" and "" — and that is the state a document is in when the caret
 * sits on a fresh line at the end. An EMPTY STRING is one empty line, not none: a view with no text still has a place
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

/* **A LINE'S RANGE EXCLUDES ITS OWN TERMINATOR, WHICH IS THE DECISION THE MODEL TURNS ON.** A caller that wants to
 * replace a line's text must not have to know whether the break is inside the range it was handed. A LINE PAST THE
 * LAST answers the empty range at the end rather than a wrong one. */
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
 * THE LAYOUT: THE MODEL AT THE VIEW'S WIDTH, WRAPPED BY THE TYPESETTER                          *
 * ============================================================================================ */

- (void)cg_appendVisualLine:(NSRange)range
{
	if (_cg_visualCount == _cg_visualCapacity) {
		NSUInteger capacity = (_cg_visualCapacity == 0) ? 8 : _cg_visualCapacity * 2;

		_cg_visual = realloc(_cg_visual, capacity * sizeof(NSRange));
		_cg_visualCapacity = capacity;
	}
	_cg_visual[_cg_visualCount] = range;
	_cg_visualCount++;
}

/* **AND THIS IS WHERE THE WIDTH COMES IN.** The content width is the view less the two insets; the typesetter is built
 * once over the whole string and asked for one break at a time, each answer fed straight back as the next start — which
 * is exactly Apple's own description of the loop it is for. A width of zero or less means there is nowhere to wrap TO,
 * so the text is taken a line at a time by its own hard breaks (which the typesetter answers anyway) rather than every
 * character becoming a line.
 *
 * **A TRAILING NEWLINE OWES AN EMPTY LAST LINE.** The typesetter puts a hard break IN the line it ends, so "a\n" comes
 * back as ONE range of two characters — and the position AFTER the break, which is where the caret sits on a fresh
 * last line, would have no line to belong to. The empty range is appended for exactly that position. */
- (void)cg_ensureLayout
{
	CGFloat width = NSWidth([self bounds]) - 2.0 * NS_TEXT_INSET;
	NSUInteger n = [_string length];
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;
	CTTypesetterRef ts;
	CFIndex start = 0;

	if (_cg_layoutValid && width == _cg_layoutWidth) {
		return;
	}
	_cg_layoutWidth = width;
	_cg_layoutValid = YES;
	_cg_visualCount = 0;
	if (n == 0) {
		[self cg_appendVisualLine:NSMakeRange(0, 0)];
		return;
	}
	attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(attributes, kCTFontAttributeName, ((NSFont *)[self cg_font])->_font);
	s = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)_string, attributes);
	CFRelease(attributes);
	ts = (s != NULL) ? CTTypesetterCreateWithAttributedString(s) : NULL;
	if (s != NULL) {
		CFRelease(s);
	}
	if (ts == NULL) {
		[self cg_appendVisualLine:NSMakeRange(0, n)];
		return;
	}
	while (start < (CFIndex)n) {
		CFIndex count = (width > 0.0) ? CTTypesetterSuggestLineBreak(ts, start, (double)width)
					      : (CFIndex)(n - (NSUInteger)start);

		if (count <= 0) {
			count = 1;
		}
		if (start + count > (CFIndex)n) {
			count = (CFIndex)n - start;
		}
		[self cg_appendVisualLine:NSMakeRange((NSUInteger)start, (NSUInteger)count)];
		start += count;
	}
	CFRelease(ts);
	if ([_string characterAtIndex:n - 1] == '\n') {
		[self cg_appendVisualLine:NSMakeRange(n, 0)];
	}
}

- (NSUInteger)cg_visualLineCount
{
	[self cg_ensureLayout];
	return _cg_visualCount;
}

- (NSRange)cg_visualLineRangeAtIndex:(NSUInteger)line
{
	[self cg_ensureLayout];
	if (line >= _cg_visualCount) {
		return NSMakeRange([_string length], 0);
	}
	return _cg_visual[line];
}

/* **AND THE RANGE A LINE DRAWS IS THE LAYOUT'S LESS ITS TRAILING WHITESPACE.** The breaker keeps a trailing space or
 * newline in the range because it is part of what it MEASURED; none of it is ink, and taking it off the range a glyph
 * is set for is what makes the boundary between two visual lines UNAMBIGUOUS — the position after a wrapped space is
 * the NEXT line's start and the position before it is THIS line's end. Without that, both lines claim the same index
 * and a click at the left edge of the second line lands, visibly, at the end of the first. */
- (NSRange)cg_textRangeOfVisualLine:(NSUInteger)line
{
	NSRange r = [self cg_visualLineRangeAtIndex:line];
	NSUInteger end = r.location + r.length;

	while (end > r.location) {
		unichar c = [_string characterAtIndex:end - 1];

		if (c == ' ' || c == '\t' || c == '\n') {
			end--;
		} else {
			break;
		}
	}
	return NSMakeRange(r.location, end - r.location);
}

/* **WHICH VISUAL LINE A CARET INDEX BELONGS TO: THE FIRST ONE WHOSE TEXT RANGE CONTAINS IT.** With trailing whitespace
 * off the range, every index belongs to exactly one line — the wrapped line's own end and the next line's first
 * character are DIFFERENT indices — so this is a lookup rather than a tie-break, and both the caret and a click read
 * it the same way. A line with no visible characters (an empty one, or the line a hard break opened) holds its own
 * start position. */
- (NSUInteger)cg_visualLineIndexForCharacterIndex:(NSUInteger)index
{
	NSUInteger i, count = [self cg_visualLineCount];

	for (i = 0; i < count; i++) {
		NSRange range = [self cg_textRangeOfVisualLine:i];

		if (_cg_visual[i].location <= index && index <= range.location + range.length) {
			return i;
		}
	}
	return count - 1;
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

/* **A LINE'S BASELINE, MEASURED DOWN FROM THE TOP OF THE VIEW** — line 0 at the same baseline `NSText` places its
 * single line at, and each line after it one band lower. It takes a VISUAL line's index: a wrapped line's second part
 * is a line of its own for every purpose this file has. */
- (CGFloat)cg_baselineForLine:(NSUInteger)line
{
	NSFont *font = [self cg_font];

	return NSMaxY([self bounds]) - NS_TEXT_INSET - [font ascender] - (CGFloat)line * [self cg_lineHeight];
}

/* **A `CTLine` IS BUILT FOR A RANGE RATHER THAN FOR THE WHOLE STRING**, because a `CTLine` lays the string it is given
 * as ONE line: the breaking is the typesetter's (above) and this is only the setting. A range with no characters
 * answers NULL, which every caller reads as "an empty line with no glyphs". */
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

/* THE X OF A CHARACTER INDEX, measured from the LEFT EDGE OF THE VISUAL LINE IT LANDS ON — every line begins at the
 * same inset, so this is also its x in the view. The index is made relative to the line's TEXT range before Core Text
 * is asked, because Core Text counts from the start of the line it was given. */
- (CGFloat)cg_xForIndex:(NSUInteger)index
{
	NSUInteger line = [self cg_visualLineIndexForCharacterIndex:index];
	NSRange range = [self cg_textRangeOfVisualLine:line];
	CTLineRef ctline = [self cg_createLineForRange:range];
	CGFloat x = -1.0;

	if (ctline != NULL) {
		CFIndex rel = (CFIndex)(index - range.location);

		if (rel < 0) {
			rel = 0;
		}
		if ((NSUInteger)rel > range.length) {
			rel = (CFIndex)range.length;
		}
		x = (CGFloat)CTLineGetOffsetForStringIndex(ctline, rel, NULL);
		CFRelease(ctline);
	}
	return (x < 0.0) ? 0.0 : x;
}

/* **THE INVERSE, WHICH IS WHAT A CLICK ASKS: WHICH VISUAL LINE FROM THE Y, THEN WHICH CHARACTER FROM THE X.** The line
 * is arithmetic — the distance down from the top of the first line, divided by the band — and only the character is
 * Core Text's. A click above the first line lands on line 0 and one below the last lands on the last. */
- (NSUInteger)cg_indexForPoint:(NSPoint)point
{
	CGFloat lineHeight = [self cg_lineHeight];
	CGFloat top = NSMaxY([self bounds]) - NS_TEXT_INSET;
	CGFloat offset = top - point.y;
	NSUInteger line, count;
	NSRange range;
	CTLineRef ctline;
	CFIndex index = 0;

	[self cg_ensureLayout];
	count = _cg_visualCount;
	if (lineHeight <= 0.0 || offset <= 0.0) {
		line = 0;
	} else {
		line = (NSUInteger)(offset / lineHeight);
	}
	if (line >= count) {
		line = count - 1;
	}
	range = [self cg_textRangeOfVisualLine:line];
	ctline = [self cg_createLineForRange:range];
	if (ctline != NULL) {
		index = CTLineGetStringIndexForPosition(ctline, CGPointMake(point.x - NS_TEXT_INSET, 0.0));
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

/* ============================================================================================ *
 * THE MEASUREMENT: THE HEIGHT THE LAYOUT NEEDS AT THE WIDTH IT HAS                             *
 * ============================================================================================ */

/* **A WRAPPING VIEW'S WIDTH IS THE CALLER'S AND ITS HEIGHT IS ITS OWN.** `-sizeToFit` here keeps the frame's width —
 * which is the container's, or the caller's — and answers the height the wrapped layout needs at it. A view that set
 * its own width from its longest line would RE-WRAP ITSELF the next time it laid out, because that line may only be
 * the longest BECAUSE of the width; the height has no such circle. */
- (void)sizeToFit
{
	[self cg_ensureLayout];
	[self setFrameSize:NSMakeSize([self frame].size.width,
				      (CGFloat)_cg_visualCount * [self cg_lineHeight] + 2.0 * NS_TEXT_INSET)];
}

/* **AND A DOCUMENT VIEW DOES NOT CARRY ITS OWN HORIZONTAL ORIGIN, WHICH IS THE ONE THING THIS CLASS TAKES FROM ITS
 * BASE.** `NSText` side-scrolls its single line because it is a field with no clip view; a document's scrolling is the
 * clip view's, and this tier has not put one around a text view yet. So the origin is held at ZERO — a line wider than
 * the view is CLIPPED, and wrapping is what keeps that from happening — and SCROLLING IS SLICE III. */
- (void)scrollRangeToVisible:(NSRange)range
{
	(void)range;
	_originX = 0.0;
}

/* ============================================================================================ *
 * THE THREE DOORS THAT CHANGE THE TEXT OR THE WIDTH, EACH CLEARING THE LAYOUT                    *
 * ============================================================================================ */

/* **A LAYOUT IS STALE THE MOMENT THE TEXT OR THE WIDTH IS NOT WHAT IT WAS BUILT FROM, AND THESE ARE THE ONLY THREE
 * WAYS EITHER CAN CHANGE.** `-replaceCharactersInRange:` is the one edit primitive every other edit is spelled in;
 * `-setString:` writes the buffer directly and would otherwise be missed; and `-setFrameSize:` is the width. A
 * HEIGHT-ONLY RESIZE DOES NOT INVALIDATE, because a wrap depends on the width alone — which is also why
 * `-sizeToFit`, which sets the height it just measured, does not throw its own work away. */
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
	_cg_layoutValid = NO;
	[super replaceCharactersInRange:range withString:string];
}

- (void)setString:(NSString *)string
{
	_cg_layoutValid = NO;
	[super setString:string];
}

- (void)setFrameSize:(NSSize)newSize
{
	if (newSize.width != [self frame].size.width) {
		_cg_layoutValid = NO;
	}
	[super setFrameSize:newSize];
}

/* ============================================================================================ *
 * THE DRAWING: THE BACKGROUND, THEN EVERY VISUAL LINE'S BAND AND GLYPHS, THEN THE CARET         *
 * ============================================================================================ */

/* **AND THE BEZEL IS GONE, WHICH IS A DIFFERENCE FROM THE BASE WORTH STATING.** `NSText` is the editable surface under
 * a CONTROL, so it draws the field's border; a TEXT VIEW is the document itself, and Apple's draws no bezel either.
 * What it keeps is the BACKGROUND FILL. The rest is the base's drawing run once per VISUAL line. */
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
	[self cg_ensureLayout];
	count = _cg_visualCount;
	for (i = 0; i < count; i++) {
		NSRange lr = _cg_visual[i];
		NSRange range = [self cg_textRangeOfVisualLine:i];
		NSUInteger caretEnd = range.location + range.length;
		CGFloat baseline = [self cg_baselineForLine:i];
		CTLineRef line = [self cg_createLineForRange:range];
		NSRect band = NSZeroRect;
		NSUInteger selStart = _selectedRange.location;
		NSUInteger selEnd = selStart + _selectedRange.length;
		NSUInteger lo = (selStart > lr.location) ? selStart : lr.location;
		NSUInteger hi = (selEnd < caretEnd) ? selEnd : caretEnd;
		BOOL hasBand = NO;

		/* **THE SELECTION IS CLIPPED TO THIS VISUAL LINE, ONE LINE AT A TIME**, which is what makes a selection that
		 * spans a break or a wrap draw as a band on each line it covers. The newline itself carries no band: there is
		 * no glyph there to highlight. */
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
			/* AND THE GLYPHS THE BAND COVERS ARE DRAWN AGAIN IN WHITE THROUGH A CLIP — the base's second pass, for
			 * the same reason (selected text is drawn in the surface colour) and with the same limitation: this view
			 * holds ONE run, so the whole line is redrawn and the clip does the splitting. */
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
	/* AND THE CARET, ON WHICHEVER VISUAL LINE IT IS ON — which is the LAST line that starts at or before it, so a caret
	 * just after a hard break sits on the empty line it opened. */
	if (_editing && [self isEditable]) {
		NSUInteger caretLine = [self cg_visualLineIndexForCharacterIndex:_selectedRange.location];
		CGFloat baseline = [self cg_baselineForLine:caretLine];
		CGFloat x = NS_TEXT_INSET + [self cg_xForIndex:_selectedRange.location];

		[[NSColor controlTextColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(x, baseline + [font descender], 1.0, bandHeight)] fill];
	}
}

/* ============================================================================================ *
 * THE POINTER: A CLICK LANDS ON THE VISUAL LINE IT IS OVER                                      *
 * ============================================================================================ */

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
 * edit goes through the base's own primitive — which clears the layout — and the next read re-wraps. */
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
 * is a tab character. */
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
 * THE MOVEMENT: "THE LINE" MEANS THE VISUAL LINE, WHICH IS WHAT A PERSON SEES                     *
 * ============================================================================================ */

/* **AND THAT IS THE WHOLE SEMANTIC CHANGE FROM THE BASE.** A field's beginning-of-line is index 0 and its end-of-line
 * the string's end; a document's are the CARET's own line — and with wrapping, "the caret's line" is the VISUAL one,
 * because Home goes to the start of what is DISPLAYED, not to the start of the paragraph that was wrapped. */
- (void)moveToBeginningOfLine:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location, 0)];
}

- (void)moveToEndOfLine:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location + range.length, 0)];
}

- (void)moveToBeginningOfLineAndModifySelection:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];
	NSUInteger end = _selectedRange.location + _selectedRange.length;

	(void)sender;
	[self setSelectedRange:NSMakeRange(range.location, end - range.location)];
}

- (void)moveToEndOfLineAndModifySelection:(id)sender
{
	NSRange range = [self cg_textRangeOfVisualLine:
		[self cg_visualLineIndexForCharacterIndex:_selectedRange.location]];

	(void)sender;
	[self setSelectedRange:NSMakeRange(_selectedRange.location,
					   range.location + range.length - _selectedRange.location)];
}

/* THE INDEX ON A GIVEN VISUAL LINE NEAREST TO AN X — the goal column of a vertical movement, turned back into a
 * position by the line's own characters. */
- (NSUInteger)cg_indexOnLine:(NSUInteger)line atX:(CGFloat)x
{
	NSRange range = [self cg_textRangeOfVisualLine:line];
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

/* **A SELECTION COLLAPSES BEFORE THE STEP, AND TO THE END THE STEP IS GOING AWAY FROM** — the character movements'
 * rule, one line up: Down from a selection starts at its END (the bottom of it) and Up from its START. The line and
 * the column are then read from the position the caret ACTUALLY has, not the one it had before the collapse. */
- (void)moveUp:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger line;
	CGFloat x;

	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(location, 0)];
	}
	line = [self cg_visualLineIndexForCharacterIndex:location];
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
	line = [self cg_visualLineIndexForCharacterIndex:location];
	if (line + 1 >= [self cg_visualLineCount]) {
		return;
	}
	x = [self cg_xForIndex:location];
	[self setSelectedRange:NSMakeRange([self cg_indexOnLine:line + 1 atX:x], 0)];
}

/* **AND EXTENDING BY A LINE MOVES THE ONE END THE DIRECTION MOVES**, the base's Shift rule one line up: the selection's
 * LOCATION is its UPPER end (a range keeps its lower index) and its END is its lower one, so Up rewrites the location
 * and Down the length. */
- (void)moveUpAndModifySelection:(id)sender
{
	NSUInteger location = _selectedRange.location;
	NSUInteger end = location + _selectedRange.length;
	NSUInteger line = [self cg_visualLineIndexForCharacterIndex:location];
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
	NSUInteger line = [self cg_visualLineIndexForCharacterIndex:end];
	NSUInteger target;

	(void)sender;
	if (line + 1 >= [self cg_visualLineCount]) {
		return;
	}
	target = [self cg_indexOnLine:line + 1 atX:[self cg_xForIndex:end]];
	[self setSelectedRange:NSMakeRange(location, target - location)];
}

/* **AND THE TWO DOCUMENT ENDS, WHICH ARE THE STRING'S OWN TWO ENDS.** They need no line at all — the first character
 * and the one past the last — which is why a one-line field could have implemented them from the start and simply had
 * no reason to. */
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
