/*
 * NSTextView.m — many lines where `NSText` holds one, and the layout now READ FROM THE MANAGER rather than computed here.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE VIEW USED TO CARRY ITS OWN LAYOUT AND DOES NOT ANY MORE.** Slice IV built the trio — `NSTextStorage`,
 * `NSTextContainer`, `NSLayoutManager` — and the manager already knew how to break a store into line fragments, place a
 * glyph, hit-test a point and draw the ink. This class had a SECOND copy of that arithmetic (`_cg_visual`, a typesetter
 * walk, a `CTLine` per line), which is exactly the kind of duplication that drifts. So the copy is GONE: the view owns
 * the trio, `-string` is the STORE's string, and every layout question is forwarded to the manager. WHAT THE VIEW
 * KEEPS IS WHAT IS ACTUALLY THE VIEW'S: the selection, the caret, the pointer, the key commands, and the height.
 *
 * **AND THE ONE THING THAT IS NOT A FORWARD IS THE base CLASS'S STRING.** `NSText` holds a `NSMutableString` and its
 * character and word movement read it directly, so the view keeps that string as a MIRROR of the store, refreshed by
 * `NSTextStorageDidProcessEditingNotification`. The store is the authority; the mirror is what lets two decades of
 * `NSText` arithmetic keep working unchanged.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSParagraphStyle.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>

/* ONE NOTIFICATION, POSTED AND HANDED TO THE DELEGATE — the same pair `NSText.m` spells, because this class owns the
 * edit primitive rather than the base and the two halves must still happen together. */
static void cg_announce(NSText *text, NSString *name, SEL delegateSelector)
{
	NSNotification *note = [NSNotification notificationWithName:name object:text];
	id delegate = [text delegate];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (delegate != nil && [delegate respondsToSelector:delegateSelector]) {
		[delegate performSelector:delegateSelector withObject:note];
	}
}

@implementation NSTextView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* APPLE'S DEFAULT FOR A TEXT VIEW, and the one a scroll view needs: the view is as tall as its text. */
		_cg_verticallyResizable = YES;
		_cg_markedRange = NSMakeRange(NSNotFound, 0);
		/* **AND THE TRIO IS BUILT HERE, IN THE ONE DIRECTION THAT CANNOT CYCLE.** The view retains the STORE, the
		 * store retains the MANAGER, the manager retains the CONTAINER, and the container holds a BORROWED pointer
		 * back to this view. The padding is the field's own inset, so the manager's lines start where every other
		 * text surface in this tier starts. */
		_cg_textStorage = [[NSTextStorage alloc] init];
		_cg_layoutManager = [[NSLayoutManager alloc] init];
		_cg_textContainer = [[NSTextContainer alloc] initWithContainerSize:frameRect.size];
		[_cg_textContainer setLineFragmentPadding:NS_TEXT_INSET];
		[_cg_textContainer setTextView:self];
		[_cg_textStorage addLayoutManager:_cg_layoutManager];
		[_cg_layoutManager addTextContainer:_cg_textContainer];
		/* **AND EVERY EDIT THE STORE ANNOUNCES REACHES THE MIRROR.** A direct store edit — a caller adding a run —
		 * and the view's own edits alike, so the base class's string is never older than the store by more than the
		 * synchronous notification itself. */
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cg_textStorageDidProcessEditing:)
			name:NSTextStorageDidProcessEditingNotification object:_cg_textStorage];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageDidProcessEditingNotification
		object:_cg_textStorage];
	[_cg_textContainer setTextView:nil];
	[_cg_textContainer release];
	[_cg_layoutManager release];
	[_cg_textStorage release];
	[super dealloc];
}

/* **AND A TEXT VIEW IS FLIPPED, WHICH IS APPLE'S OWN ANSWER AND THE ONE SCROLLING NEEDS.** y runs DOWN from the top,
 * so the FIRST line sits at the clip view's origin and grows downward as a reader expects. The base, `NSText`, is a
 * y-up single-line field and stays one; what this class flips is ITS OWN coordinates, and every measurement below is
 * written in them. THE MANAGER'S CONTAINER COORDINATES ARE THE SAME ONES, which is why the view adds only its inset. */
- (BOOL)isFlipped
{
	return YES;
}

/* ============================================================================================ *
 * THE TRIO, AND WHAT REACHES IT                                                                 *
 * ============================================================================================ */

- (NSTextStorage *)textStorage
{
	return _cg_textStorage;
}

/* **MOVING THE VIEW TO ANOTHER STORE IS FOUR WIRES AND A MIRROR.** Off the old store's list (which clears the
 * manager's back-pointer), onto the new one's (which sets it), the observer moved, and the base's string re-read — the
 * layout is invalidated by the manager's own `-setTextStorage:` along the way, so there is nothing else to forget. */
- (void)setTextStorage:(NSTextStorage *)storage
{
	if (storage == _cg_textStorage) {
		return;
	}
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSTextStorageDidProcessEditingNotification
		object:_cg_textStorage];
	if (_cg_textStorage != nil) {
		[_cg_textStorage removeLayoutManager:_cg_layoutManager];
	}
	[storage retain];
	[_cg_textStorage release];
	_cg_textStorage = storage;
	if (_cg_textStorage != nil) {
		[_cg_textStorage addLayoutManager:_cg_layoutManager];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cg_textStorageDidProcessEditing:)
			name:NSTextStorageDidProcessEditingNotification object:_cg_textStorage];
	}
	[self cg_mirrorString];
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

- (NSLayoutManager *)layoutManager
{
	return _cg_layoutManager;
}

- (NSTextContainer *)textContainer
{
	return _cg_textContainer;
}

/* THE MIRROR, AND THE TWO THINGS THAT HAPPEN WHEN IT MOVES: the display is stale and the height may be. */
- (void)cg_textStorageDidProcessEditing:(NSNotification *)note
{
	(void)note;
	[self cg_mirrorString];
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

- (void)cg_mirrorString
{
	NSString *current = (_cg_textStorage != nil) ? [_cg_textStorage string] : @"";

	if (![_string isEqualToString:current]) {
		[_string setString:current];
	}
}

/* **AND THE STRING A CALLER READS IS THE STORE'S**, which is the whole point of the slice: a caller that reads
 * `-string` and a caller that reads `-textStorage` get the same characters, and an edit to either is seen by both. */
- (NSString *)string
{
	return (_cg_textStorage != nil) ? [_cg_textStorage string] : @"";
}

/* ============================================================================================ *
 * THE MODEL: A LINE IS A `\n`-TERMINATED RUN                                                *
 * ============================================================================================ */

/* **AND THE COUNT COUNTS BREAKS RATHER THAN RUNS, WHICH IS WHAT MAKES A TRAILING NEWLINE AN EMPTY LAST LINE.** "a\n"
 * has one break in it and therefore TWO lines — "a" and "" — and that is the state a document is in when the caret
 * sits on a fresh line at the end. An EMPTY STRING is one empty line, not none. */
- (NSUInteger)cg_lineCount
{
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger count = 1;
	NSUInteger i;

	for (i = 0; i < n; i++) {
		if ([string characterAtIndex:i] == '\n') {
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
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger line = 0;
	NSUInteger i;

	if (index > n) {
		index = n;
	}
	for (i = 0; i < index; i++) {
		if ([string characterAtIndex:i] == '\n') {
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
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger current = 0;
	NSUInteger start = 0;
	NSUInteger i;
	NSUInteger end;

	for (i = 0; i < n; i++) {
		if ([string characterAtIndex:i] != '\n') {
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
	while (end < n && [string characterAtIndex:end] != '\n') {
		end++;
	}
	return NSMakeRange(start, end - start);
}

/* ============================================================================================ *
 * THE LAYOUT, WHICH IS NOW THE MANAGER'S                                                        *
 * ============================================================================================ */

/* THE FONT A LINE IS MEASURED IN. The store's own attribute at the first character is the authority — that is what
 * makes a run's font reach the layout — and a store with none falls back to this view's own font and then the system's,
 * which is the same chain `NSText` uses. */
- (NSFont *)cg_font
{
	id font = nil;

	if ([_cg_textStorage length] > 0) {
		font = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSFontAttributeName];
	}
	if (font == nil) {
		font = [self font];
	}
	return (font != nil) ? (NSFont *)font : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

/* THE FONT'S OWN BAND, taken from the manager so the view and the lines it draws cannot disagree about it. */
- (CGFloat)cg_lineHeight
{
	return [_cg_layoutManager cg_lineHeight];
}

/* **THE VISUAL LINE IS THE MANAGER'S FRAGMENT, INDEX FOR INDEX** — the same object, not a second layout that happens
 * to agree. A line past the last answers the empty range at the end of the store. */
- (NSUInteger)cg_visualLineCount
{
	return [_cg_layoutManager cg_lineFragmentCountForTextContainer:_cg_textContainer];
}

- (NSRange)cg_visualLineRangeAtIndex:(NSUInteger)line
{
	return [_cg_layoutManager cg_lineFragmentRangeAtIndex:line inTextContainer:_cg_textContainer];
}

/* **AND THE RANGE A LINE DRAWS IS THE LAYOUT'S LESS ITS TRAILING WHITESPACE.** The breaker keeps a trailing space or
 * newline in the range because it is part of what it MEASURED; none of it is ink, and taking it off the range a glyph
 * is set for is what makes the boundary between two visual lines UNAMBIGUOUS. */
- (NSRange)cg_textRangeOfVisualLine:(NSUInteger)line
{
	NSRange r = [self cg_visualLineRangeAtIndex:line];
	NSString *string = [self string];
	NSUInteger n = [string length];
	NSUInteger end;

	if (r.location >= n) {
		return NSMakeRange(n, 0);
	}
	end = r.location + r.length;
	if (end > n) {
		end = n;
	}
	while (end > r.location) {
		unichar c = [string characterAtIndex:end - 1];

		if (c == ' ' || c == '\t' || c == '\n') {
			end--;
		} else {
			break;
		}
	}
	return NSMakeRange(r.location, end - r.location);
}

/* **WHICH VISUAL LINE A CARET INDEX BELONGS TO: THE FIRST FRAGMENT THAT HOLDS IT.** The fragment's own start is the
 * lower bound and the TRIMMED end the upper, which is what keeps the wrapped line's trailing space on the line it
 * ended and the next line's first character a different index. A line with no visible characters holds its own start. */
- (NSUInteger)cg_visualLineIndexForCharacterIndex:(NSUInteger)index
{
	NSUInteger i, count = [self cg_visualLineCount];

	for (i = 0; i < count; i++) {
		NSRange full = [self cg_visualLineRangeAtIndex:i];
		NSRange trimmed = [self cg_textRangeOfVisualLine:i];

		if (full.location <= index && index <= trimmed.location + trimmed.length) {
			return i;
		}
	}
	return (count > 0) ? (count - 1) : 0;
}

/* **A LINE'S BASELINE, MEASURED DOWN FROM THE TOP OF THE VIEW** — the container origin's inset plus the fragment's own
 * place plus the font's ascender. It takes a VISUAL line's index: a wrapped line's second part is a line of its own
 * for every purpose this file has. */
- (CGFloat)cg_baselineForLine:(NSUInteger)line
{
	NSRange range = [self cg_visualLineRangeAtIndex:line];
	NSRect fragment = [_cg_layoutManager lineFragmentRectForGlyphAtIndex:range.location effectiveRange:NULL];

	return NS_TEXT_INSET + fragment.origin.y + [[self cg_font] ascender];
}

/* THE X OF A CHARACTER INDEX, measured from the LEFT EDGE OF THE VISUAL LINE it lands on — the manager's offset less
 * its fragment padding, so every caller adds the one inset itself, exactly as before. */
- (CGFloat)cg_xForIndex:(NSUInteger)index
{
	return [_cg_layoutManager cg_offsetForGlyphAtIndex:index] - NS_TEXT_INSET;
}

/* **THE INVERSE, WHICH IS WHAT A CLICK ASKS: WHICH VISUAL LINE FROM THE y, THEN WHICH CHARACTER FROM THE x.** The
 * manager does both; the view only moves the point out of its own inset and into the container's coordinates. */
- (NSUInteger)cg_indexForPoint:(NSPoint)point
{
	return [_cg_layoutManager cg_glyphIndexForPoint:NSMakePoint(point.x, point.y - NS_TEXT_INSET)
					      inTextContainer:_cg_textContainer];
}

/* THE INDEX ON A GIVEN VISUAL LINE NEAREST TO AN X — the goal column of a vertical movement. The line's own y picks
 * the fragment and the x picks the character, so this is the same hit test aimed at a chosen line. */
- (NSUInteger)cg_indexOnLine:(NSUInteger)line atX:(CGFloat)x
{
	NSRange range = [self cg_visualLineRangeAtIndex:line];
	NSRect fragment = [_cg_layoutManager lineFragmentRectForGlyphAtIndex:range.location effectiveRange:NULL];

	return [_cg_layoutManager cg_glyphIndexForPoint:NSMakePoint(NS_TEXT_INSET + x, fragment.origin.y + [self cg_lineHeight] / 2.0)
					      inTextContainer:_cg_textContainer];
}

/* ============================================================================================ *
 * THE MEASUREMENT: THE HEIGHT THE LAYOUT NEEDS AT THE WIDTH IT HAS                             *
 * ============================================================================================ */

/* **A WRAPPING VIEW'S WIDTH IS THE CALLER'S AND ITS HEIGHT IS ITS OWN.** `-sizeToFit` keeps the frame's width and
 * answers the height the manager's used rect implies, plus the view's own two insets. THE WIDTH IS NEVER TOUCHED — a
 * view that set its own width from its longest line would RE-WRAP ITSELF on the next layout. */
- (BOOL)isVerticallyResizable
{
	return _cg_verticallyResizable;
}

- (void)setVerticallyResizable:(BOOL)flag
{
	_cg_verticallyResizable = flag;
	if (flag) {
		[self cg_setHeightToLayout];
	}
}

- (void)cg_setHeightToLayout
{
	CGFloat width = [self frame].size.width;
	CGFloat height;

	[_cg_layoutManager ensureLayoutForTextContainer:_cg_textContainer];
	height = [_cg_layoutManager usedRectForTextContainer:_cg_textContainer].size.height + 2.0 * NS_TEXT_INSET;
	if (height != [self frame].size.height) {
		/* **THE CONTAINER FOLLOWS THE FRAME IN WIDTH AND NOT IN HEIGHT, AND THAT ASYMMETRY IS THE POINT.** The manager
		 * wraps to the container's width; a ZERO height means UNBOUNDED, which is what a scrolling document is — its
		 * height is the layout's answer rather than an input, so a container that carried the frame's short height would
		 * clip the very lines this method is measuring. `[super setFrameSize:]` is deliberate: the overridden door would
		 * set the container and invalidate the layout this method just asked for. */
		[_cg_textContainer setContainerSize:NSMakeSize(width, 0.0)];
		[super setFrameSize:NSMakeSize(width, height)];
	}
}

- (void)cg_fitHeight
{
	if (_cg_verticallyResizable) {
		[self cg_setHeightToLayout];
	}
}

/* **AND `-sizeToFit` FITS REGARDLESS**, because it is an explicit request rather than the automatic height above. */
- (void)sizeToFit
{
	[self cg_setHeightToLayout];
}

/* **AND BRINGING A RANGE INTO VIEW IS ASKING THE CLIP VIEW.** The caret's rectangle is computed from the manager's
 * fragment, and `-scrollRectToVisible:` walks up to the clip view just far enough. With WRAPPING there is nothing to
 * scroll sideways: every line is inside the width, so the question is vertical and the answer is a line. */
- (NSRect)cg_rectForCharacterIndex:(NSUInteger)index
{
	NSFont *font = [self cg_font];
	NSUInteger line = [self cg_visualLineIndexForCharacterIndex:index];
	CGFloat baseline = [self cg_baselineForLine:line];

	return NSMakeRect(NS_TEXT_INSET + [self cg_xForIndex:index], baseline - [font ascender], 1.0,
			  [font ascender] - [font descender]);
}

- (void)scrollRangeToVisible:(NSRange)range
{
	[self scrollRectToVisible:[self cg_rectForCharacterIndex:range.location]];
}

/* ============================================================================================ *
 * THE THREE DOORS THAT CHANGE THE TEXT OR THE WIDTH                                             *
 * ============================================================================================ */

/* **THE EDIT PRIMITIVE IS THE STORE'S NOW, AND THE BASE'S STRING IS THE MIRROR.** Every other edit in the base class is
 * spelled in this door, so this is the one place a keystroke, a paste and a programmatic replacement all meet. THE
 * INSERTED TEXT INHERITS THE RUN AT THE INSERTION POINT — the character before it, or the first character if the edit
 * is at the start — which is what makes typing into a coloured run stay coloured; a store with no runs takes the view's
 * own font when it has one. */
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
	NSString *text = (string != nil) ? string : @"";
	NSUInteger length = [_cg_textStorage length];
	NSDictionary *inherited = nil;

	/* **A PLAIN EDIT ENDS A COMPOSITION, WHICH IS WHY THE MARK CLEARS HERE.** An input method re-marks on every
	 * keystroke of a composition anyway (`-setMarkedText:` puts the new range back after calling this), so an edit that
	 * is NOT part of a composition is exactly the case where the marked text should stop being marked. */
	_cg_markedRange = NSMakeRange(NSNotFound, 0);

	if (range.location > length) {
		range.location = length;
	}
	if (range.location + range.length > length) {
		range.length = length - range.location;
	}
	if (length > 0 && range.location > 0) {
		/* **AND THE RUN IS RETAINED ACROSS THE EDIT, WHICH IS NOT TIDINESS.** A store's `-attributesAtIndex:` hands back
		 * the RUN'S OWN dictionary rather than a copy, and the `-replaceCharactersInRange:` below can free that run — so a
		 * dictionary read before the edit and applied after it (the inheritance this door is FOR) must own itself or it is
		 * read after it is freed. MEASURED: not retaining it segfaulted on the second keystroke of a composition, inside
		 * the very `-setAttributes:range:` that was applying it. */
		inherited = [[_cg_textStorage attributesAtIndex:range.location - 1 effectiveRange:NULL] retain];
	} else if (length > 0) {
		inherited = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL] retain];
	} else if ([self font] != nil) {
		inherited = [[NSDictionary dictionaryWithObject:[self font] forKey:NSFontAttributeName] retain];
	}
	[_cg_textStorage beginEditing];
	[_cg_textStorage replaceCharactersInRange:range withString:text];
	if (inherited != nil && [text length] > 0) {
		[_cg_textStorage setAttributes:inherited range:NSMakeRange(range.location, [text length])];
	}
	[_cg_textStorage endEditing];
	[inherited release];
	[self setSelectedRange:NSMakeRange(range.location + [text length], 0)];
	cg_announce(self, NSTextDidChangeNotification, @selector(textDidChange:));
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

/* **AND `-setString:` REPLACES THE WHOLE STORE**, keeping the view's font as the run the new text is set in, because a
 * setter is a caller saying what the text is and not throwing the face away with it. */
- (void)setString:(NSString *)string
{
	NSString *text = (string != nil) ? string : @"";
	id font = [self font];

	_cg_markedRange = NSMakeRange(NSNotFound, 0);

	[_cg_textStorage beginEditing];
	[_cg_textStorage replaceCharactersInRange:NSMakeRange(0, [_cg_textStorage length]) withString:text];
	if (font != nil && [text length] > 0) {
		[_cg_textStorage addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, [text length])];
	}
	[_cg_textStorage endEditing];
	[self setSelectedRange:NSMakeRange([text length], 0)];
	cg_announce(self, NSTextDidChangeNotification, @selector(textDidChange:));
	[self setNeedsDisplay:YES];
	[self cg_fitHeight];
}

/* **AND THE ALIGNMENT IS THE STORE'S PARAGRAPH STYLE NOW, WHICH RETIRES THE BASE'S DEFERRAL.** `NSText -setAlignment:`
 * stores and answers and says it does not move the glyphs, because a single-line field has no width to align WITHIN;
 * a text view has the manager's container width, so the style goes into the store and the manager offsets the line
 * inside that width. THE OTHER PROPERTIES OF THE STYLE TRAVEL WITH IT — a caller that set `-lineSpacing` on the run
 * keeps it — because this door takes a MUTABLE COPY of what is there rather than writing a fresh style over it. */
- (NSTextAlignment)alignment
{
	id style = nil;

	if ([_cg_textStorage length] > 0) {
		style = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL]
					objectForKey:NSParagraphStyleAttributeName];
	}
	return (style != nil) ? [style alignment] : [super alignment];
}

- (void)setAlignment:(NSTextAlignment)alignment
{
	NSUInteger n = [_cg_textStorage length];
	id existing;
	NSMutableParagraphStyle *style;

	[super setAlignment:alignment];
	if (n == 0) {
		return;
	}
	existing = [[_cg_textStorage attributesAtIndex:0 effectiveRange:NULL]
				objectForKey:NSParagraphStyleAttributeName];
	style = (existing != nil) ? [existing mutableCopy]
				  : [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[style setAlignment:alignment];
	[_cg_textStorage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, n)];
	[style release];
}

/* **AND THE FONT IS CARRIED INTO THE STORE.** `NSText` answers `-font` from its own ivar and the manager reads the
 * store; setting one without the other would be two answers to one question, so this door writes both: the ivar
 * through the base and the run through the store. */
- (void)setFont:(id)font
{
	[super setFont:font];
	if (font != nil && [_cg_textStorage length] > 0) {
		[_cg_textStorage addAttribute:NSFontAttributeName value:font
					 range:NSMakeRange(0, [_cg_textStorage length])];
	}
}

/* **AND THE WIDTH IS THE CONTAINER'S.** A resize carries the new size into the container, marks the layout stale —
 * a wrap depends on the width and an overflow on the height, so neither is assumed unchanged — and re-fits when the
 * WIDTH moved, because that is what re-wraps. */
- (void)setFrameSize:(NSSize)newSize
{
	BOOL widthChanged = (newSize.width != [self frame].size.width);

	[super setFrameSize:newSize];
	[_cg_textContainer setContainerSize:NSMakeSize(newSize.width, 0.0)];
	[_cg_layoutManager invalidateLayoutForCharacterRange:NSMakeRange(0, [_cg_textStorage length])
					     actualCharacterRange:NULL];
	if (widthChanged) {
		[self cg_fitHeight];
	}
	[self setNeedsDisplay:YES];
}

/* ============================================================================================ *
 * THE DRAWING: THE BACKDROP, THE SELECTION, THE MANAGER'S INK, AND THE CARET                    *
 * ============================================================================================ */

/* **AND THE BEZEL IS GONE, WHICH IS A DIFFERENCE FROM THE BASE WORTH STATING.** `NSText` is the editable surface under
 * a CONTROL, so it draws the field's border; a TEXT VIEW is the document itself, and Apple's draws no bezel either.
 * What it keeps is the BACKGROUND FILL and the SELECTION, both of which are the VIEW's — the selection because only
 * the view knows where it is. THE GLYPHS AND THEIR RUNS ARE THE MANAGER'S: a foreground colour, a background colour and
 * an underline all come out of `NSLayoutManager`'s two draw doors. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	NSFont *font = [self cg_font];
	CGFloat bandHeight = [font ascender] - [font descender];
	NSUInteger n = [[self string] length];

	(void)dirtyRect;
	if (cg == NULL) {
		return;
	}
	if (_drawsBackground) {
		[[self backgroundColor] != nil ? [self backgroundColor] : [NSColor controlBackgroundColor] setFill];
		[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
	}
	/* **THE SELECTION IS CLIPPED TO EACH VISUAL LINE, ONE LINE AT A TIME**, which is what makes a selection that spans
	 * a break or a wrap draw as a band on each line it covers. The newline itself carries no band: there is no glyph
	 * there to highlight. */
	if ([self isSelectable] && _selectedRange.length > 0) {
		NSUInteger selStart = _selectedRange.location;
		NSUInteger selEnd = selStart + _selectedRange.length;
		NSUInteger count = [self cg_visualLineCount];
		NSUInteger i;

		for (i = 0; i < count; i++) {
			NSRange lr = [self cg_textRangeOfVisualLine:i];
			NSUInteger caretEnd = lr.location + lr.length;
			NSUInteger lo = (selStart > lr.location) ? selStart : lr.location;
			NSUInteger hi = (selEnd < caretEnd) ? selEnd : caretEnd;

			if (lo < hi) {
				CGFloat baseline = [self cg_baselineForLine:i];
				CGFloat x0 = NS_TEXT_INSET + [self cg_xForIndex:lo];
				CGFloat x1 = NS_TEXT_INSET + [self cg_xForIndex:hi];

				[[NSColor cg_accentColor] setFill];
				[[NSBezierPath bezierPathWithRect:
					NSMakeRect(x0, baseline - [font ascender], x1 - x0, bandHeight)] fill];
			}
		}
	}
	/* AND THE STORE'S OWN INK, WHICH IS THE MANAGER'S TO LAY DOWN — backgrounds first, then the glyphs and the rules. */
	[_cg_layoutManager drawBackgroundForGlyphRange:NSMakeRange(0, n) atPoint:NSMakePoint(0.0, NS_TEXT_INSET)];
	[_cg_layoutManager drawGlyphsForGlyphRange:NSMakeRange(0, n) atPoint:NSMakePoint(0.0, NS_TEXT_INSET)];
	/* **AND THE MARKED TEXT'S COMPOSITION MARK, WHICH IS THE VIEW'S BECAUSE THE STORE CANNOT CARRY IT.** A one-point rule
	 * below the baseline of every visual line the marked range covers, clipped to the range the way the selection band is
	 * — so a composition split across a wrap is underlined on both lines and a trailing space carries nothing. */
	if ([self hasMarkedText]) {
		NSUInteger markStart = _cg_markedRange.location;
		NSUInteger markEnd = markStart + _cg_markedRange.length;
		NSUInteger count = [self cg_visualLineCount];
		NSUInteger i;

		for (i = 0; i < count; i++) {
			NSRange lr = [self cg_visualLineRangeAtIndex:i];
			NSRange tr = [self cg_textRangeOfVisualLine:i];
			NSUInteger lineEnd = tr.location + tr.length;
			NSUInteger lo = (markStart > lr.location) ? markStart : lr.location;
			NSUInteger hi = (markEnd < lineEnd) ? markEnd : lineEnd;

			if (lo < hi) {
				CGFloat baseline = [self cg_baselineForLine:i];
				CGFloat x0 = NS_TEXT_INSET + [self cg_xForIndex:lo];
				CGFloat x1 = NS_TEXT_INSET + [self cg_xForIndex:hi];

				[[NSColor controlTextColor] setFill];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(x0, baseline + 2.0, x1 - x0, 1.0)] fill];
			}
		}
	}
	/* AND THE CARET, ON WHICHEVER VISUAL LINE IT IS ON — which is the LAST line that starts at or before it, so a caret
	 * just after a hard break sits on the empty line it opened. */
	if (_editing && [self isEditable]) {
		NSUInteger caretLine = [self cg_visualLineIndexForCharacterIndex:_selectedRange.location];
		CGFloat baseline = [self cg_baselineForLine:caretLine];
		CGFloat x = NS_TEXT_INSET + [self cg_xForIndex:_selectedRange.location];

		[[NSColor controlTextColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(x, baseline - [font ascender], 1.0, bandHeight)] fill];
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
 * edit goes through this class's own primitive — which edits the STORE — and the layout follows.
 *
 * **AND AN INSERT THAT CONFIRMS A COMPOSITION REPLACES THE MARKED RANGE RATHER THAN THE SELECTION.** An input method
 * commits what it was composing by calling this door, and the caret sits INSIDE the mark while it does — so replacing
 * the selection would splice the confirmed text into the middle of the composition instead of over it. */
- (void)insertText:(id)insertString
{
	NSString *text = ([insertString isKindOfClass:[NSAttributedString class]])
			 ? [(NSAttributedString *)insertString string] : (NSString *)insertString;
	NSRange target;

	if (![self isEditable] || text == nil) {
		return;
	}
	target = [self hasMarkedText] ? _cg_markedRange : _selectedRange;
	[self replaceCharactersInRange:target withString:text];
}

/* **AND THE TWO KEYS THAT MEANT "I AM DONE WITH THIS FIELD" NOW MEAN "PUT A BREAK HERE" AND "PUT A TAB HERE".** */
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
 * THE MARKED TEXT: WHAT AN INPUT METHOD IS COMPOSING, SAID IN `NSTextInput.h`                     *
 * ============================================================================================ */

/* **THE MARKED CHARACTERS ARE REALLY IN THE STORE**, which is what makes a composition an ordinary edit with an
 * ordinary caret: an input method replaces its marked range on every keystroke, the layout re-wraps, and the caret is
 * placed inside the composition by the range it was told. WHAT IS NOT IN THE STORE IS THE FACT THAT THEY ARE MARKED — a
 * character range cannot carry its own temporary state — so the RANGE lives here and the view draws the composition
 * mark itself (see `-drawRect:`). That is the same division the selection uses: the store holds text and attributes,
 * the view holds the transient facts about it. */
- (BOOL)hasMarkedText
{
	return _cg_markedRange.location != NSNotFound;
}

- (NSRange)markedRange
{
	return (_cg_markedRange.location != NSNotFound) ? _cg_markedRange : NSMakeRange(NSNotFound, 0);
}

/* **EVERY KEYSTROKE OF A COMPOSITION IS ONE CALL, AND THE STRING IS THE WHOLE COMPOSITION SO FAR.** The target is the
 * marked range when there is one — a composition grows by replacing itself — and the SELECTION otherwise, which is how
 * the first keystroke starts one. An EMPTY string clears the marked text, which is the input method taking a
 * composition back. */
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange
{
	NSString *text = ([string isKindOfClass:[NSAttributedString class]])
			 ? [(NSAttributedString *)string string] : (NSString *)string;
	NSRange target = [self hasMarkedText] ? _cg_markedRange : _selectedRange;
	NSUInteger location = target.location;

	if (text == nil) {
		text = @"";
	}
	[self replaceCharactersInRange:target withString:text];
	if ([text length] > 0) {
		_cg_markedRange = NSMakeRange(location, [text length]);
		[self setSelectedRange:NSMakeRange(location + selectedRange.location, selectedRange.length)];
	} else {
		_cg_markedRange = NSMakeRange(NSNotFound, 0);
	}
	[self setNeedsDisplay:YES];
}

- (void)unmarkText
{
	_cg_markedRange = NSMakeRange(NSNotFound, 0);
	[self setNeedsDisplay:YES];
}

/* THE ATTRIBUTES AN INPUT METHOD MAY SET ON WHAT IT INSERTS. This view can draw a foreground, a background and the two
 * rules, so those are what it offers; a view that supported nothing beyond plain text would answer an empty array. */
- (NSArray *)validAttributesForMarkedText
{
	return [NSArray arrayWithObjects:NSUnderlineStyleAttributeName, NSUnderlineColorAttributeName,
			NSBackgroundColorAttributeName, NSForegroundColorAttributeName, nil];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range
{
	NSUInteger n = [_cg_textStorage length];

	if (range.location > n) {
		range.location = n;
	}
	if (range.location + range.length > n) {
		range.length = n - range.location;
	}
	return [_cg_textStorage attributedSubstringFromRange:range];
}

/* **AND THE TWO SCREEN QUESTIONS A CANDIDATE WINDOW ASKS.** `-firstRectForCharacterRange:` is the caret's own rectangle
 * moved into SCREEN coordinates — the view's rectangle, into the window's, plus the window's frame origin — and
 * `-characterIndexForPoint:` is that conversion run backwards. THE CONVERSION IS THE WINDOW'S FRAME ORIGIN because this
 * tier has no `-convertRectToScreen:`; a window on Agora's own server is placed where its frame says, so the origin is
 * the whole of the transformation this tier owns. */
- (NSRect)firstRectForCharacterRange:(NSRange)range
{
	NSRect rect = [self cg_rectForCharacterIndex:range.location];
	NSRect inWindow = [self convertRect:rect toView:nil];
	NSRect frame = [[self window] frame];

	return NSMakeRect(inWindow.origin.x + frame.origin.x, inWindow.origin.y + frame.origin.y,
			  inWindow.size.width, inWindow.size.height);
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
	NSRect frame = [[self window] frame];
	NSPoint inWindow = NSMakePoint(point.x - frame.origin.x, point.y - frame.origin.y);

	return [self cg_indexForPoint:[self convertPoint:inWindow fromView:nil]];
}

/* ============================================================================================ *
 * THE MOVEMENT: "THE LINE" MEANS THE VISUAL LINE, WHICH IS WHAT A PERSON SEES                     *
 * ============================================================================================ */

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

/* **A SELECTION COLLAPSES BEFORE THE STEP, AND TO THE END THE STEP IS GOING AWAY FROM** — the character movements'
 * rule, one line up: Down from a selection starts at its END (the bottom of it) and Up from its START. */
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

/* **AND EXTENDING BY A LINE MOVES THE ONE END THE DIRECTION MOVES.** */
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

/* **AND THE TWO DOCUMENT ENDS, WHICH ARE THE STRING'S OWN TWO ENDS.** */
- (void)moveToBeginningOfDocument:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(0, 0)];
}

- (void)moveToEndOfDocument:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange([[self string] length], 0)];
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
	[self setSelectedRange:NSMakeRange(_selectedRange.location, [[self string] length] - _selectedRange.location)];
}

@end
