/*
 * NSText — a view that holds a string and lets a person type into it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * **ONE RUN, ONE LINE, AND EVERY EDIT SPELLED AS A RANGE REPLACEMENT.** That is the whole of this class's model, and it
 * is deliberately less than Apple's: Apple's `NSText` carries an `NSTextContainer` chain and lays out as many lines as
 * fit, and everything downstream of that (paragraphs, word movement, wrapping) comes from a layout manager this tier
 * does not have. A single line is what a FIELD EDITOR is, so that is what this is — and it is the base rather than the
 * whole of the family because a multi-line text view can be built on it by replacing the one line with a stack of
 * them, which is a change to the geometry and not to the editing.
 *
 * **THE VIEW IS NOT FLIPPED, WHICH IS A DECISION ABOUT THE TEXT ENGINE AND NOT ABOUT TASTE.** Text views in AppKit
 * count y downward so that the first line is at the top; this tier's text drawing is CoreText's, which draws in a Y-UP
 * space, and it has been verified in that space by every label and menu row in the library. A flipped view would have
 * to mirror the text back with its own transform on every draw, and for ONE LINE that buys nothing: the baseline is
 * measured down from the top of the view either way. A multi-line version will have to flip and mirror, and this note
 * is where that is recorded rather than rediscovered.
 *
 * **AND THE GEOMETRY COMES OUT OF THE TEXT ENGINE RATHER THAN OUT OF ARITHMETIC ON THE STRING.** Where the caret goes
 * for a character index, and which character a click landed on, are the two questions a text view is asked constantly
 * and the two a hand-rolled advance-sum would get wrong for every kerning pair and every ligature. Both come from the
 * `CTLine`: `-createLine` builds it, `CTLineGetOffsetForStringIndex` answers the first, and
 * `CTLineGetStringIndexForPosition` the second.
 */
#import <AppKit/NSText.h>
#import <AppKit/NSCell.h>	/* NS_CELL_BEZEL_RADIUS — the bezel a field shares with a button */
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>

#include <CoreGraphics/CGContext.h>
#include <CoreText/CTLine.h>
#include <CoreText/CTStringAttributes.h>

/* THE AIR THE TEXT KEEPS INSIDE ITS OWN FRAME, on every side. Named rather than repeated because the baseline, the
 * caret, the hit test and `-sizeToFit` all have to agree about it — and they agree by all reading this one number. */

/* THE AIR A SCROLLED-TO RANGE KEEPS AT THE EDGE IT WAS SCROLLED TO. A caret exactly on the border is legible but reads
 * as clipped, so the field stops a few points short — and the value is the same on both sides, because a caret moved
 * back to the left should stop short of that border too. */
#define NS_TEXT_SCROLL_GAP 2.0

NSString *NSTextDidBeginEditingNotification = @"NSTextDidBeginEditingNotification";
NSString *NSTextDidEndEditingNotification = @"NSTextDidEndEditingNotification";
/* THE STRING IS THE ERA'S LITERAL, under a name this tier gives it — see the header for why. */
NSString *NSTextMovementUserInfoKey = @"NSTextMovement";
NSString *NSTextDidChangeNotification = @"NSTextDidChangeNotification";

/* ONE NOTIFICATION, POSTED AND HANDED TO THE DELEGATE. Both halves always happen together — the notification is the
 * PUBLIC record of a change and the delegate method is the private one, and a caller that registers for the
 * notification and a delegate that implements the method must not be able to disagree about whether something
 * happened. The notification is built once and used twice for exactly that reason. */
static void fn_announce(NSText *text, NSString *name, SEL delegateSelector)
{
	NSNotification *note = [NSNotification notificationWithName:name object:text];
	id delegate = [text delegate];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (delegate != nil && [delegate respondsToSelector:delegateSelector]) {
		[delegate performSelector:delegateSelector withObject:note];
	}
}

@implementation NSText

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* **THE DEFAULTS ARE THE ONES THAT MAKE THE VIEW USEFUL WHEN NOBODY CONFIGURES IT**: an empty string, a caret
		 * at its start, a system font, editable and selectable, and NO background — because a text view inside a
		 * window is usually meant to show the window's surface rather than a box of its own. `-isFieldEditor` is NO:
		 * that is a role a window assigns, not a property a view starts with. */
		_string = [[NSMutableString alloc] init];
		_selectedRange = NSMakeRange(0, 0);
		_font = [[NSFont systemFontOfSize:[NSFont systemFontSize]] retain];
		_backgroundColor = nil;
		_alignment = NSLeftTextAlignment;
		_delegate = nil;
		_editable = YES;
		_selectable = YES;
		_drawsBackground = NO;
		_fieldEditor = NO;
		/* **RICH TEXT AND GRAPHICS ARE OFF, WHICH IS THE ERA'S OWN DEFAULT AND ALSO THE ONLY HONEST ONE HERE**: this
		 * tier has no RTF reader and no attachment model, so a view that claimed to be rich would be claiming
		 * something it cannot draw. They are stored and answered because Apple declares them. */
		_richText = NO;
		_importsGraphics = NO;
		_editing = NO;
		_dragging = NO;
		_dragAnchor = 0;
		_originX = 0.0;
	}
	return self;
}

- (void)dealloc
{
	[_string release];
	[_font release];
	[_backgroundColor release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE LINE, WHICH IS WHERE EVERY GEOMETRIC ANSWER BELOW COMES FROM                               *
 * ============================================================================================ */

/* **BUILT FRESH EVERY TIME, AND THE CALLER OWNS IT — the `Create` in the name is the Core Foundation rule and it is
 * spelled that way on purpose.** A cache would have to be invalidated by every edit, every font change, every resize
 * and every string replacement, and this class has exactly ONE line to build; the cost of building it is one
 * attributed string and one shape pass, which is what a text view does per draw anyway.
 *
 * **AND IT ANSWERS NULL FOR AN EMPTY STRING, WHICH IS NOT A FAILURE.** `CTLineCreateWithAttributedString` refuses a
 * zero-length string by design — there is no character to carry the font attribute — and an empty text view is the
 * state every field starts in. So every caller below treats NULL as "a line with no glyphs": the caret sits at the
 * inset, a click lands at index 0, and the width is zero. That is the honest geometry of nothing, and it is cheaper
 * than a sentinel line nobody can see. */
- (CTLineRef)createLine
{
	NSFont *font = [self font];
	CFMutableDictionaryRef attributes;
	CFAttributedStringRef s;
	CTLineRef line;

	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	attributes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(attributes, kCTFontAttributeName, ((NSFont *)font)->_font);
	s = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)_string, attributes);
	CFRelease(attributes);
	if (s == NULL) {
		return NULL;
	}
	line = CTLineCreateWithAttributedString(s);
	CFRelease(s);
	return line;
}

/* THE FONT IN USE, resolved once so the three doorways that need one cannot disagree. */
- (NSFont *)fn_font
{
	NSFont *font = [self font];

	return (font != nil) ? font : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

/* **THE BASELINE, MEASURED DOWN FROM THE TOP OF THE VIEW** — which is a y-up view's height less the inset and the
 * ascender. Every vertical answer below starts here: the caret spans the ascender above it and the descender below,
 * and the hit test measures a point relative to it. */
- (CGFloat)fn_baseline
{
	NSFont *font = [self fn_font];

	return NSMaxY([self bounds]) - NS_TEXT_INSET - [font ascender];
}

/* THE X OF A CHARACTER INDEX, in the view's own coordinates. `-1` is the answer for an index the line cannot place
 * (an empty line), which a caller reads as "at the inset". */
- (CGFloat)fn_xForIndex:(NSUInteger)index
{
	CTLineRef line = [self createLine];
	CGFloat x = -1.0;

	if (line != NULL) {
		x = (CGFloat)CTLineGetOffsetForStringIndex(line, (CFIndex)index, NULL);
		CFRelease(line);
	}
	return (x < 0.0) ? 0.0 : x;
}

/* **AND THE INVERSE, WHICH IS WHAT A CLICK ASKS.** Core Text measures a position FROM THE LINE'S ORIGIN ON THE
 * BASELINE and counts y upward, so the point has to have the inset taken off its x and the baseline off its y before
 * it means anything — AND THE SCROLL ORIGIN PUT BACK, because the point a caller clicked is in the VIEW's coordinates
 * while the index it wants is in the TEXT's. Getting any of the three wrong is a caret that lands a line away from
 * the pointer, or a field's width away from it. */
- (NSUInteger)fn_indexForPoint:(NSPoint)point
{
	CTLineRef line = [self createLine];
	CFIndex index = 0;

	if (line != NULL) {
		CGPoint where = CGPointMake(point.x - NS_TEXT_INSET + _originX, point.y - [self fn_baseline]);

		index = CTLineGetStringIndexForPosition(line, where);
		CFRelease(line);
	}
	if (index < 0) {
		index = 0;
	}
	if ((NSUInteger)index > [_string length]) {
		index = (NSUInteger)[_string length];
	}
	return (NSUInteger)index;
}

/* THE TEXT'S OWN WIDTH — the number the scroll arithmetic clamps against, in one place, so that `-sizeToFit` and
 * `-scrollRangeToVisible:` cannot measure the view two ways. */
- (CGFloat)fn_textWidth
{
	CTLineRef line = [self createLine];
	CGFloat width = 0.0;

	if (line != NULL) {
		width = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
		CFRelease(line);
	}
	return width;
}

/* **THE X OF A CHARACTER INDEX IN THE VIEW'S OWN COORDINATES: THE INSET, THE CHARACTER'S OFFSET, AND THE SCROLL ORIGIN
 * SUBTRACTED.** One expression in one place, because it places ALL FOUR of the things this class draws — the run of
 * text, the selection's two ends, and the caret — and a fifth site that forgot the origin would be a mark drawn half a
 * field away from the text it belongs to. That is exactly the bug this shape exists to make impossible. */
- (CGFloat)fn_viewXForIndex:(NSUInteger)index
{
	return NS_TEXT_INSET + [self fn_xForIndex:index] - _originX;
}

/* ============================================================================================ *
 * THE SCROLLING, WHICH THIS FIELD DOES TO ITSELF                                             *
 * ============================================================================================ */

/* **A SINGLE-LINE FIELD SCROLLS ITS OWN TEXT, BECAUSE IT IS A FIELD AND NOT A DOCUMENT.** Apple's `NSText` lives
 * inside an `NSScrollView`/`NSClipView` pair and `-scrollRangeToVisible:` moves THAT; this tier's `NSText` is the
 * single-line editable base under a control, so what it does is carry its own horizontal origin — the text, the
 * selection and the caret are all drawn at `x - _originX` (see `-fn_viewXForIndex:`) and a click puts it back — and
 * that is what this door sets. (The drawing layer renders a non-zero bounds origin now, so a clip view scrolls
 * visibly; moving THIS view's scrolling onto an enclosing clip view is a later slice, and a change worth making on
 * its own.)
 *
 * WHAT IT IS NOT: it moves nothing outside this view, so a caller expecting a scroll view to have moved has not been
 * given one. WHEN THIS BECOMES THE CLIP VIEW'S QUESTION the arithmetic below becomes a
 * `-scrollToPoint:` on whatever ancestor owns the offset — which is why the offset has a NAME here rather than being
 * folded into each of the four draws.
 *
 * **THE RULE IS THAT THE RANGE'S END STAYS INSIDE, WITH A MARGIN**, and the origin is CLAMPED to the text's own
 * width: scrolling past the end would show blank space where a person expects the last character, so the end of the
 * text is as far as this ever goes — which is why a caret AT the end sits flush against the border rather than a `GAP`
 * short of it. */
- (void)scrollRangeToVisible:(NSRange)range
{
	CGFloat visible = NSWidth([self bounds]) - 2.0 * NS_TEXT_INSET;
	CGFloat startX = [self fn_xForIndex:range.location];
	CGFloat endX = [self fn_xForIndex:range.location + range.length];
	CGFloat limit;
	CGFloat origin = _originX;

	if (visible <= 0.0) {
		/* A FRAME WITH NO ROOM SHOWS NOTHING, so the honest origin is none at all rather than a fraction of a line. */
		if (_originX != 0.0) {
			_originX = 0.0;
			[self setNeedsDisplay:YES];
		}
		return;
	}
	if (endX + NS_TEXT_SCROLL_GAP > origin + visible) {
		origin = endX + NS_TEXT_SCROLL_GAP - visible;	/* the end ran off the right: bring it back */
	}
	if (startX - NS_TEXT_SCROLL_GAP < origin) {
		origin = startX - NS_TEXT_SCROLL_GAP;		/* the start ran off the left: push it back */
	}
	limit = [self fn_textWidth] - visible;
	if (limit < 0.0) {
		limit = 0.0;	/* the text fits, so there is nothing to scroll and the origin belongs at zero */
	}
	if (origin > limit) {
		origin = limit;
	}
	if (origin < 0.0) {
		origin = 0.0;
	}
	if (origin != _originX) {
		_originX = origin;
		[self setNeedsDisplay:YES];
	}
}

/* ============================================================================================ *
 * THE STRING, AND THE ONE EDIT EVERY OTHER EDIT IS SPELLED IN                                   *
 * ============================================================================================ */

- (NSString *)string
{
	return _string;
}

- (void)setString:(NSString *)string
{
	[_string setString:(string != nil) ? string : @""];
	/* THE CARET GOES TO THE END, because the text is now this and the old selection may point past it — and the END
	 * is brought into view, which is what makes a field set to a long string show its last character rather than its
	 * first. */
	_selectedRange = NSMakeRange([_string length], 0);
	[self scrollRangeToVisible:_selectedRange];
	fn_announce(self, NSTextDidChangeNotification, @selector(textDidChange:));
	[self setNeedsDisplay:YES];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string
{
	NSUInteger length = [_string length];

	/* **AN OUT-OF-RANGE EDIT IS CLAMPED RATHER THAN REFUSED.** A caller's arithmetic can be wrong about a string that
	 * changed under it — a selection taken before an edit and applied after is the ordinary way this happens — and the
	 * alternative to clamping is an exception in a view that was only trying to show some text. A range that starts
	 * past the end becomes an INSERTION at the end, which is what the caller meant. */
	if (range.location > length) {
		range.location = length;
	}
	if (range.location + range.length > length) {
		range.length = length - range.location;
	}
	[_string replaceCharactersInRange:range withString:(string != nil) ? string : @""];
	/* AND THE CARET ENDS UP AFTER WHAT WAS INSERTED, which is the rule typing depends on: the next keystroke goes
	 * where the last one left off, not back at the range that was replaced. IT GOES THROUGH `-setSelectedRange:`
	 * RATHER THAN STRAIGHT INTO THE IVAR, which is not tidiness: that door is where the caret is CLAMPED to the text
	 * and where it is BROUGHT BACK INTO VIEW, so an edit that wrote the field directly would leave a caret past the
	 * end of its own string and — MEASURED — a field whose text scrolled on every keystroke EXCEPT the typing. */
	[self setSelectedRange:NSMakeRange(range.location + [(string != nil) ? string : @"" length], 0)];
	fn_announce(self, NSTextDidChangeNotification, @selector(textDidChange:));
	[self setNeedsDisplay:YES];
}

/* ============================================================================================ *
 * THE SELECTION                                                                                 *
 * ============================================================================================ */

- (NSRange)selectedRange
{
	return _selectedRange;
}

- (void)setSelectedRange:(NSRange)range
{
	NSUInteger length = [_string length];

	if (range.location > length) {
		range.location = length;
	}
	if (range.location + range.length > length) {
		range.length = length - range.location;
	}
	_selectedRange = range;
	/* **AND THE CARET IS BROUGHT BACK INTO VIEW, WHICH IS WHY EVERY MOVEMENT AND EVERY EDIT SCROLLS.** A caret that
	 * walked off the right edge and stayed there is a caret a person cannot see, and putting this here rather than at
	 * each of the two dozen doors that move one is what makes that impossible to forget — every edit ends in a
	 * selection change and so does every arrow key. */
	[self scrollRangeToVisible:_selectedRange];
	[self setNeedsDisplay:YES];
}

- (void)selectAll:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(0, [_string length])];
}

/* ============================================================================================ *
 * THE FACE, AND THE FIVE FLAGS                                                                  *
 * ============================================================================================ */

- (id)font
{
	return _font;
}

- (void)setFont:(id)font
{
	if (font != _font) {
		id held = [font retain];

		[_font release];
		_font = held;
		[self setNeedsDisplay:YES];
	}
}

- (NSTextAlignment)alignment
{
	return _alignment;
}

- (void)setAlignment:(NSTextAlignment)alignment
{
	_alignment = alignment;
	/* APPKIT-REFUSE: the alignment is STORED and ANSWERED and does not move the glyphs, because moving them needs a
	 * width to align WITHIN and this view's width is whatever its frame says — one line, drawn from the inset. The
	 * three non-default cases are the ones this leaves undone, and saying so is the difference between a door with a
	 * far side and a door that quietly draws the wrong thing. `NSTextView` OVERRIDES THIS DOOR and does move them,
	 * because the manager gave it a width to align within. */
	[self setNeedsDisplay:YES];
}

/* **AND THE FOUR COMMANDS, WHICH ARE ONE LINE EACH BECAUSE THE PROPERTY IS WHERE THE BEHAVIOUR LIVES.** A key binding
 * (or an input context) reaches for the command; the command sets the alignment; the alignment is the fact a caller
 * reads back. Keeping them apart is what lets a subclass change WHAT aligning does without shadowing four selectors. */
- (void)alignLeft:(id)sender
{
	(void)sender;
	[self setAlignment:NSLeftTextAlignment];
}

- (void)alignRight:(id)sender
{
	(void)sender;
	[self setAlignment:NSRightTextAlignment];
}

- (void)alignCenter:(id)sender
{
	(void)sender;
	[self setAlignment:NSCenterTextAlignment];
}

- (void)alignJustified:(id)sender
{
	(void)sender;
	[self setAlignment:NSJustifiedTextAlignment];
}

- (BOOL)drawsBackground
{
	return _drawsBackground;
}

- (void)setDrawsBackground:(BOOL)flag
{
	_drawsBackground = flag;
	[self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)color
{
	if (color != _backgroundColor) {
		NSColor *held = [color retain];

		[_backgroundColor release];
		_backgroundColor = held;
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)isEditable
{
	return _editable;
}

- (void)setEditable:(BOOL)flag
{
	_editable = flag;
}

- (BOOL)isSelectable
{
	return _selectable;
}

- (void)setSelectable:(BOOL)flag
{
	_selectable = flag;
}

- (BOOL)isRichText
{
	return _richText;
}

- (void)setRichText:(BOOL)flag
{
	_richText = flag;
}

- (BOOL)importsGraphics
{
	return _importsGraphics;
}

- (void)setImportsGraphics:(BOOL)flag
{
	_importsGraphics = flag;
}

- (BOOL)isFieldEditor
{
	return _fieldEditor;
}

- (void)setFieldEditor:(BOOL)flag
{
	_fieldEditor = flag;
}

- (id)delegate
{
	return _delegate;
}

- (void)setDelegate:(id)delegate
{
	_delegate = delegate;	/* NOT retained, and not released on the way out: this tree's rule for every delegate */
}

- (void)sizeToFit
{
	NSFont *font = [self fn_font];
	CGFloat width = [self fn_textWidth];

	/* THE HEIGHT IS THE FONT'S BAND AND NOT THE TEXT'S, so an empty field is the same size as a full one and a form
	 * does not jump when its first character arrives. */
	[self setFrameSize:NSMakeSize(width + 2.0 * NS_TEXT_INSET,
				      [font ascender] - [font descender] + 2.0 * NS_TEXT_INSET)];
}

/* ============================================================================================ *
 * THE DRAWING: A BACKGROUND, A SELECTION, THE TEXT, AND A CARET                                 *
 * ============================================================================================ */

- (void)drawRect:(NSRect)dirtyRect
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;
	NSFont *font = [self fn_font];
	CTLineRef line;
	CGFloat baseline = [self fn_baseline];
	/* **THE BAND'S RECTANGLE IS COMPUTED ONCE AND USED TWICE** — it is what the accent is filled with and what the white
	 * ink is clipped to, and those two must be the same rectangle to the pixel or a glyph's edge is drawn in one colour
	 * over a band that stops somewhere else. */
	NSRect selRect = NSZeroRect;
	BOOL hasSelection = NO;

	(void)dirtyRect;
	if (cg == NULL) {
		return;		/* a draw with no context draws nothing, which is Apple's behaviour rather than a crash */
	}
	if (_drawsBackground) {
		NSRect faceRect = NSInsetRect([self bounds], NS_CELL_BEZEL_WIDTH / 2.0, NS_CELL_BEZEL_WIDTH / 2.0);
		NSBezierPath *bezel = [NSBezierPath bezierPathWithRoundedRect:faceRect
								      xRadius:NS_CELL_BEZEL_RADIUS
								      yRadius:NS_CELL_BEZEL_RADIUS];

		/* **AND THE FIELD WEARS THE SAME BEZEL A BUTTON DOES, WHICH IS WHY THE TWO NUMBERS ARE THE CELL FAMILY'S.**
		 * A text field and a push button sit next to each other in every form on this platform, and a border that is
		 * a point rounder or a shade lighter than its neighbour's is the thing a person notices without being able to
		 * say what is wrong. So the radius, the stroke colour and the stroke width all come from the same place
		 * `NSButtonCell` draws ITS face from (`NS_CELL_BEZEL_RADIUS`/`_WIDTH`), and the path is INSET BY HALF THE
		 * STROKE for the same reason the button's is: a stroke is centred on its path, and the drawing layer clips a
		 * view to its bounds.
		 *
		 * THE FILL IS THE FIELD'S AND NOT THE BUTTON'S. A button's face is `controlColor` — it is a thing you press —
		 * while a field is WHITE, which is what makes a form read as a form: the two share a BORDER and not a surface.
		 * A field that never asked to draw a background draws no bezel either, which is what an inline editor over a
		 * custom surface depends on. */
		[[self backgroundColor] != nil ? [self backgroundColor] : [NSColor controlBackgroundColor] setFill];
		[bezel fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[bezel setLineWidth:NS_CELL_BEZEL_WIDTH];
		[bezel stroke];
	}
	/* **THE SELECTION IS DRAWN UNDER THE TEXT AND IN THE PLATFORM'S ACCENT**, which is the same colour the menu's
	 * highlight and a pressed button wear — one selection colour rather than a text view's — and the ink on top of it
	 * is `controlTextColor`, which this tier makes black, so the pair is legible by construction. A selection of zero
	 * length is a CARET and is drawn as one: a bar at the same place, so the two states share every measurement. */
	/* **THE BAND'S ORIGIN IS THE BASELINE LESS THE DESCENT, NOT LESS THE ASCENT** — which is the whole of why a
	 * caret floats half a line below the text it belongs to. The rect's HEIGHT is the entire band (`ascender -
	 * descender`, 15.7 points for the 13-point system font), so its ORIGIN has to be the BOTTOM of that band:
	 * `baseline + descender`, and the descender is NEGATIVE (that is `NSFont`'s contract), so the subtraction is a
	 * sum. `baseline - ascender` instead puts the band's TOP at the baseline and drops the whole thing by
	 * `ascender - |descender|` — MEASURED, 9.5 points, which is what "half a line height or so" is. THE GLYPHS ARE
	 * DRAWN AT THE BASELINE AND NEVER MOVED, so the ink was right and the two marks that share this expression
	 * were the ones that were wrong: the caret and the selection both come from here. */
	if ([self isSelectable] && _selectedRange.length > 0) {
		CGFloat x0 = [self fn_viewXForIndex:_selectedRange.location];
		CGFloat x1 = [self fn_viewXForIndex:_selectedRange.location + _selectedRange.length];

		selRect = NSMakeRect(x0, baseline + [font descender], x1 - x0, [font ascender] - [font descender]);
		hasSelection = YES;
		[[NSColor cg_accentColor] setFill];
		[[NSBezierPath bezierPathWithRect:selRect] fill];
	}
	line = [self createLine];
	if (line != NULL) {
		[[NSColor controlTextColor] setFill];
		/* **THE TEXT POSITION IS THE BASELINE'S LEFT END, which is what Core Text measures from** — and the vertical
		 * placement is already in `-fn_baseline`, measured down from the view's top because this view counts y
		 * upward. */
		CGContextSetTextPosition(cg, [self fn_viewXForIndex:0], baseline);
		CTLineDraw(line, cg);
		/* **AND THE GLYPHS THE SELECTION COVERS ARE DRAWN A SECOND TIME, IN WHITE, THROUGH A CLIP ON THE BAND.**
		 * Black ink on the accent is legible and still wrong: every platform this one is modelled on puts the selected
		 * text in the SURFACE colour, and the reason is the same reason the accent exists — a selection is a thing you
		 * are meant to be able to read AT A GLANCE, and the eye picks the band up first either way, so the ink's job
		 * on top of it is contrast against the band rather than against the page.
		 *
		 * THE SECOND PASS IS THE WHOLE LINE RATHER THAN THE SELECTED RUN, and that is a deliberate simplification
		 * bought with a redraw: this view holds ONE run in ONE line (see the note at the top of the file), so there is
		 * no attributed-range machinery here to recolour part of it with, and splitting the line in two would mean two
		 * `CTLine`s per frame and a boundary that has to agree with the band's. The clip does the splitting instead:
		 * the same glyphs at the same position, drawn again where they are covered, so what is outside the band is
		 * untouched and what is inside is overpainted exactly. The white lands ON the black it replaces, which is why
		 * the order matters and why this cannot be done before the first pass. */
		if (hasSelection) {
			CGContextSaveGState(cg);
			CGContextClipToRect(cg, selRect);
			[[NSColor whiteColor] setFill];
			CGContextSetTextPosition(cg, [self fn_viewXForIndex:0], baseline);
			CTLineDraw(line, cg);
			CGContextRestoreGState(cg);
		}
		CFRelease(line);
	}
	/* AND THE CARET, WHICH IS THE ONE PIECE OF THIS VIEW THAT SAYS IT IS LISTENING. It is drawn SOLID rather than
	 * blinking: a blink is a periodic timer, and a view that started one would be starting a clock the run loop knows
	 * nothing about. The caret's absence is the honest signal that nothing is being edited. */
	if (_editing && [self isEditable]) {
		CGFloat x = [self fn_viewXForIndex:_selectedRange.location];

		[[NSColor controlTextColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(x, baseline + [font descender], 1.0,
							     [font ascender] - [font descender])] fill];
	}
}

/* ============================================================================================ *
 * THE POINTER: PUT THE CARET WHERE THE CLICK LANDED, AND DRAG OUT A SELECTION                   *
 * ============================================================================================ */

- (BOOL)acceptsFirstResponder
{
	/* **AN EDITABLE VIEW WANTS THE KEYBOARD AND A READ-ONLY ONE DOES NOT.** A selectable label is a real thing — a
	 * person should be able to copy out of it — and it is not a thing that should take a keystroke away from the field
	 * beside it, so the answer is `-isEditable` rather than YES. */
	return [self isEditable];
}

- (void)mouseDown:(NSEvent *)event
{
	NSUInteger index;

	if (![self isSelectable]) {
		return;
	}
	if ([self isEditable]) {
		/* THE CLICK THAT STARTS AN EDIT SESSION IS ALSO THE CLICK THAT PUTS THE CARET**, and the window's
		 * `-makeFirstResponder:` is what opens the session — the view does not open one itself, because whether this
		 * view may become the first responder is the window's question and not the view's. */
		[[self window] makeFirstResponder:self];
	}
	index = [self fn_indexForPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	/* **THE ANCHOR IS REMEMBERED HERE, AND THAT IS WHAT MAKES A DRAG A DRAG.** A selection has one end that MOVES and
	 * one that does not, and the one that does not is fixed by the press — so it is KEPT rather than recomputed from
	 * the selection on each pass. MEASURED, recomputing it is a drag that works FORWARD and not BACKWARD, and the
	 * reason is what a selection's own location IS: while the pointer moves RIGHT the anchor happens to BE the
	 * location (a range keeps its lower index), so the two agree and the selection grows; the moment the pointer
	 * moves LEFT the location follows the POINTER, so the anchor travels with it and the range stays one character
	 * wide for the whole drag. */
	_dragAnchor = index;
	[self setSelectedRange:NSMakeRange(index, 0)];
	_dragging = YES;
}

/* **AND THE DRAG IS TWO ENDS IN EITHER ORDER.** The moving end is where the pointer is and the fixed one is
 * `_dragAnchor`, so the range is the LOWER of the two and its length is the distance between them — the SAME
 * arithmetic for a drag to the right and a drag to the left, which is why a backward drag highlights exactly as a
 * forward one does. A pointer that has come back to the anchor gives a range of length zero: a caret, which is what
 * "no selection" is. */
- (void)mouseDragged:(NSEvent *)event
{
	NSUInteger here;

	if (!_dragging) {
		return;
	}
	here = [self fn_indexForPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
	[self setSelectedRange:(here < _dragAnchor) ? NSMakeRange(here, _dragAnchor - here)
						    : NSMakeRange(_dragAnchor, here - _dragAnchor)];
}

- (void)mouseUp:(NSEvent *)event
{
	(void)event;
	_dragging = NO;
}

/* **AND A RESIZE RE-SCROLLS, BECAUSE THE ROOM THE CARET HAS IS THE FRAME'S AND NOT THE TEXT'S.** A field that grew
 * may now hold the whole of its text — the clamp puts the origin back at zero — and one that SHRANK may have left the
 * caret outside it. Both are the same question this door already answers, so it is asked again here rather than
 * answered twice. */
- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self scrollRangeToVisible:_selectedRange];
}

/* ============================================================================================ *
 * THE KEYBOARD: WHERE THE COMMANDS LAND                                                         *
 * ============================================================================================ */

- (void)keyDown:(NSEvent *)event
{
	/* **A KEY GOES THROUGH `-interpretKeyEvents:` AND NOT STRAIGHT TO A COMMAND.** That is the whole design of text
	 * input in AppKit — including that an input method can intercept it — and doing it any other way here would make
	 * this view work and every other view that ever wants the same keys work differently. */
	[self interpretKeyEvents:[NSArray arrayWithObject:event]];
}

- (BOOL)becomeFirstResponder
{
	id delegate = [self delegate];
	NSNotification *note;

	/* **THE DELEGATE IS ASKED BEFORE THE SESSION OPENS, AND IT CAN REFUSE.** That is what the `Should` pair is for: a
	 * form that will not let this field be edited says NO here and never sees a caret. */
	if (delegate != nil && [delegate respondsToSelector:@selector(textShouldBeginEditing:)] &&
	    ![delegate textShouldBeginEditing:self]) {
		return NO;
	}
	_editing = YES;
	note = [NSNotification notificationWithName:NSTextDidBeginEditingNotification object:self];
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (delegate != nil && [delegate respondsToSelector:@selector(textDidBeginEditing:)]) {
		[delegate textDidBeginEditing:note];
	}
	[self setNeedsDisplay:YES];
	return YES;
}

- (BOOL)resignFirstResponder
{
	id delegate = [self delegate];
	NSNotification *note;

	if (_editing && delegate != nil && [delegate respondsToSelector:@selector(textShouldEndEditing:)] &&
	    ![delegate textShouldEndEditing:self]) {
		return NO;
	}
	_editing = NO;
	/* **AND THE REASON GOES WITH IT, BECAUSE IT IS THE ONLY MOMENT IT CAN BE SAID.** The movement is carried in the
	 * notification's `userInfo` and then RESET, so a session that ends by a click — which sets nothing — reports
	 * `Other` rather than the reason the previous session ended. A movement that outlived its session would be the
	 * worst kind of bug: a field whose second edit behaves like the first one's. */
	note = [NSNotification notificationWithName:NSTextDidEndEditingNotification object:self
					  userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:(NSInteger)_movement]
									       forKey:NSTextMovementUserInfoKey]];
	_movement = NSTextMovementOther;
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (delegate != nil && [delegate respondsToSelector:@selector(textDidEndEditing:)]) {
		[delegate textDidEndEditing:note];
	}
	[self setNeedsDisplay:YES];
	return YES;
}

/* ---- AND THE COMMANDS THEMSELVES, EACH OVERRIDING THE RESPONDER'S FORWARD ------------------------------------ */

- (void)insertText:(id)insertString
{
	NSString *text = ([insertString isKindOfClass:[NSAttributedString class]])
			 ? [(NSAttributedString *)insertString string] : (NSString *)insertString;

	if (![self isEditable] || text == nil) {
		return;
	}
	/* APPKIT-REFUSE: a NEWLINE inside what is being typed needs a LINE MODEL, and this view has one line by design
	 * (see the file's header). The character is dropped rather than inserted where it cannot be drawn — and rather
	 * than forwarded, which would put it in somebody else's text. `-insertNewline:` is the command that will one day
	 * make a second line, and it is refused below for the same reason. */
	if ([text rangeOfString:@"\n"].location != NSNotFound || [text rangeOfString:@"\r"].location != NSNotFound) {
		fprintf(stderr, "APPKIT-REFUSE: -[NSText insertText:] — the text contains a newline, and this class holds "
				"ONE LINE (a multi-line text view is a stack of them and is a change to the geometry, not to "
				"the editing)\n");
		return;
	}
	[self replaceCharactersInRange:_selectedRange withString:text];
}

/* ============================================================================================ *
 * AND THE `NSTextInput` DOORS, WHICH A ONE-LINE FIELD ANSWERS WITHOUT COMPOSING                   *
 * ============================================================================================ */

/* **A FIELD HAS NO MARKED TEXT, WHICH IS THE HONEST ANSWER RATHER THAN A STUB.** `NSText` is the base for a document
 * view AND for the field editor, and a one-line field never composes — its input context has no source that would. So
 * the marked-text doors answer "none" and `-setMarkedText:` INSERTS what it is handed, which is what a caller that
 * composes into a field would get. `NSTextView` OVERRIDES the four that carry the composition with real ones. */
- (BOOL)hasMarkedText
{
	return NO;
}

- (NSRange)markedRange
{
	return NSMakeRange(NSNotFound, 0);
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange
{
	(void)selectedRange;
	[self insertText:string];
}

- (void)unmarkText
{
}

- (NSArray *)validAttributesForMarkedText
{
	return [NSArray array];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range
{
	NSUInteger n = [_string length];

	if (range.location > n) {
		range.location = n;
	}
	if (range.location + range.length > n) {
		range.length = n - range.location;
	}
	return [[[NSAttributedString alloc] initWithString:[_string substringWithRange:range]] autorelease];
}

/* **AND THE TWO SCREEN DOORS, ANSWERED FROM THE FIELD'S ONE LINE.** The caret's rectangle moved into screen coordinates
 * (the window's frame origin is the whole transformation this tier owns, as in the view), and `-characterIndexForPoint:`
 * as that conversion run backwards into the field's own hit test. */
- (NSRect)firstRectForCharacterRange:(NSRange)range
{
	id font = [self font] != nil ? [self font] : [NSFont systemFontOfSize:[NSFont systemFontSize]];
	NSUInteger index = (range.location < [_string length]) ? range.location : [_string length];
	NSRect rect = NSMakeRect([self fn_viewXForIndex:index], [self fn_baseline] - [font ascender], 1.0,
				 [font ascender] - [font descender]);
	NSRect inWindow = [self convertRect:rect toView:nil];
	NSRect frame = [[self window] frame];

	return NSMakeRect(inWindow.origin.x + frame.origin.x, inWindow.origin.y + frame.origin.y,
			  inWindow.size.width, inWindow.size.height);
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point
{
	NSRect frame = [[self window] frame];
	NSPoint inWindow = NSMakePoint(point.x - frame.origin.x, point.y - frame.origin.y);

	return [self fn_indexForPoint:[self convertPoint:inWindow fromView:nil]];
}

/* **AND WHAT A WORD IS, WHICH IS THE ONE THING THE WORD COMMANDS BELOW HAVE TO DECIDE.** A word is a run of
 * `+alphanumericCharacterSet` members and everything between two runs is not one, so the two doors take an index and
 * walk to the boundary on that side — LEFT first past the NON-word characters and then past the word, RIGHT the same
 * in the other direction. That order is what makes them the same arithmetic a person expects: Option+Left from the
 * MIDDLE of a word goes to ITS start (there were no non-word characters to skip), and from the START of a word goes
 * past the whitespace to the start of the previous one.
 *
 * **IT IS ARITHMETIC OVER THE STRING AND NOT A LAYOUT QUESTION**, which is why it can live in a one-line field: the
 * character set is the STRING's, and no glyph position is consulted. `NSResponder.h` used to name the word commands
 * among the family that "need[s] a LAYOUT MODEL"; that was written about the PARAGRAPH and DOCUMENT commands, whose
 * several lines this class genuinely has not got, and the word pair does not belong in the list. */
- (NSUInteger)fn_wordBoundaryLeftOf:(NSUInteger)index
{
	NSCharacterSet *word = [NSCharacterSet alphanumericCharacterSet];
	NSUInteger i = index;

	while (i > 0 && ![word characterIsMember:[_string characterAtIndex:i - 1]]) {
		i--;
	}
	while (i > 0 && [word characterIsMember:[_string characterAtIndex:i - 1]]) {
		i--;
	}
	return i;
}

- (NSUInteger)fn_wordBoundaryRightOf:(NSUInteger)index
{
	NSCharacterSet *word = [NSCharacterSet alphanumericCharacterSet];
	NSUInteger n = [_string length];
	NSUInteger i = index;

	while (i < n && ![word characterIsMember:[_string characterAtIndex:i]]) {
		i++;
	}
	while (i < n && [word characterIsMember:[_string characterAtIndex:i]]) {
		i++;
	}
	return i;
}

- (void)moveLeft:(id)sender
{
	(void)sender;
	if (_selectedRange.length > 0) {
		/* A MOVEMENT COLLAPSES A SELECTION TO ITS NEAR END rather than stepping from its far one — press Left with
		 * text selected and the caret lands where the selection began, which is what every editor does. */
		[self setSelectedRange:NSMakeRange(_selectedRange.location, 0)];
	} else if (_selectedRange.location > 0) {
		[self setSelectedRange:NSMakeRange(_selectedRange.location - 1, 0)];
	}
}

- (void)moveRight:(id)sender
{
	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(_selectedRange.location + _selectedRange.length, 0)];
	} else if (_selectedRange.location < [_string length]) {
		[self setSelectedRange:NSMakeRange(_selectedRange.location + 1, 0)];
	}
}

- (void)moveLeftAndModifySelection:(id)sender
{
	(void)sender;
	if (_selectedRange.location > 0) {
		[self setSelectedRange:NSMakeRange(_selectedRange.location - 1, _selectedRange.length + 1)];
	}
}

- (void)moveRightAndModifySelection:(id)sender
{
	(void)sender;
	if (_selectedRange.location + _selectedRange.length < [_string length]) {
		[self setSelectedRange:NSMakeRange(_selectedRange.location, _selectedRange.length + 1)];
	}
}

- (void)moveToBeginningOfLine:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(0, 0)];
}

- (void)moveToEndOfLine:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange([_string length], 0)];
}

- (void)moveToBeginningOfLineAndModifySelection:(id)sender
{
	NSUInteger end = _selectedRange.location + _selectedRange.length;

	(void)sender;
	[self setSelectedRange:NSMakeRange(0, end)];
}

- (void)moveToEndOfLineAndModifySelection:(id)sender
{
	(void)sender;
	[self setSelectedRange:NSMakeRange(_selectedRange.location, [_string length] - _selectedRange.location)];
}

/* **AND THE WORD COMMANDS, WHICH ARE THE SAME SHAPE ONE GRANULARITY UP.** Each collapses a selection the way its
 * character counterpart does and otherwise walks to the boundary `-fn_wordBoundaryLeftOf:`/`…RightOf:` answers; the two
 * `AndModifySelection:` forms move only the end the drag has been moving, which is why the left one rewrites the
 * LOCATION and the right one the LENGTH. */
- (void)moveWordLeft:(id)sender
{
	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(_selectedRange.location, 0)];
	} else if (_selectedRange.location > 0) {
		[self setSelectedRange:NSMakeRange([self fn_wordBoundaryLeftOf:_selectedRange.location], 0)];
	}
}

- (void)moveWordRight:(id)sender
{
	(void)sender;
	if (_selectedRange.length > 0) {
		[self setSelectedRange:NSMakeRange(_selectedRange.location + _selectedRange.length, 0)];
	} else if (_selectedRange.location < [_string length]) {
		[self setSelectedRange:NSMakeRange([self fn_wordBoundaryRightOf:_selectedRange.location], 0)];
	}
}

- (void)moveWordLeftAndModifySelection:(id)sender
{
	NSUInteger end = _selectedRange.location + _selectedRange.length;
	NSUInteger target;

	(void)sender;
	if (_selectedRange.location == 0) {
		return;
	}
	target = [self fn_wordBoundaryLeftOf:_selectedRange.location];
	[self setSelectedRange:NSMakeRange(target, end - target)];
}

- (void)moveWordRightAndModifySelection:(id)sender
{
	NSUInteger start = _selectedRange.location;
	NSUInteger end = start + _selectedRange.length;
	NSUInteger target;

	(void)sender;
	if (end >= [_string length]) {
		return;
	}
	target = [self fn_wordBoundaryRightOf:end];
	[self setSelectedRange:NSMakeRange(start, target - start)];
}

- (void)deleteBackward:(id)sender
{
	(void)sender;
	if (![self isEditable]) {
		return;
	}
	if (_selectedRange.length > 0) {
		[self replaceCharactersInRange:_selectedRange withString:@""];
	} else if (_selectedRange.location > 0) {
		[self replaceCharactersInRange:NSMakeRange(_selectedRange.location - 1, 1) withString:@""];
	}
}

- (void)deleteForward:(id)sender
{
	(void)sender;
	if (![self isEditable]) {
		return;
	}
	if (_selectedRange.length > 0) {
		[self replaceCharactersInRange:_selectedRange withString:@""];
	} else if (_selectedRange.location < [_string length]) {
		[self replaceCharactersInRange:NSMakeRange(_selectedRange.location, 1) withString:@""];
	}
}

/* **AND DELETING A WORD DELETES EXACTLY WHAT MOVING BY ONE WOULD HAVE CROSSED**, which is the rule that keeps the two
 * halves from disagreeing: `-deleteWordBackward:` removes the range `-moveWordLeft:` would have stepped over and
 * `-deleteWordForward:` the range `-moveWordRight:` would have. A SELECTION IS DELETED WHOLE first, the same as every
 * other deletion here, because a person who has selected something and pressed a delete key means the selection. */
- (void)deleteWordBackward:(id)sender
{
	(void)sender;
	if (![self isEditable]) {
		return;
	}
	if (_selectedRange.length > 0) {
		[self replaceCharactersInRange:_selectedRange withString:@""];
	} else if (_selectedRange.location > 0) {
		NSUInteger from = [self fn_wordBoundaryLeftOf:_selectedRange.location];

		[self replaceCharactersInRange:NSMakeRange(from, _selectedRange.location - from) withString:@""];
	}
}

- (void)deleteWordForward:(id)sender
{
	(void)sender;
	if (![self isEditable]) {
		return;
	}
	if (_selectedRange.length > 0) {
		[self replaceCharactersInRange:_selectedRange withString:@""];
	} else if (_selectedRange.location < [_string length]) {
		NSUInteger to = [self fn_wordBoundaryRightOf:_selectedRange.location];

		[self replaceCharactersInRange:NSMakeRange(_selectedRange.location, to - _selectedRange.location)
				    withString:@""];
	}
}

- (void)deleteToBeginningOfLine:(id)sender
{
	(void)sender;
	if ([self isEditable]) {
		[self replaceCharactersInRange:NSMakeRange(0, _selectedRange.location + _selectedRange.length)
				    withString:@""];
	}
}

- (void)deleteToEndOfLine:(id)sender
{
	(void)sender;
	if ([self isEditable]) {
		[self replaceCharactersInRange:NSMakeRange(_selectedRange.location,
							   [_string length] - _selectedRange.location) withString:@""];
	}
}

/* **RETURN ENDS THE SESSION, AND THAT IS NOT THE SAME QUESTION AS INSERTING A LINE.** This door used to refuse
 * outright, with the reason that a one-line view has no second line — which is TRUE ABOUT INSERTING and was the wrong
 * answer to the key: in a field, Return means "I am done with this value", and what it produces is an ENDED SESSION
 * carrying `NSTextMovementReturn`, which is how the value reaches the model and how the control's action gets sent. A
 * person pressing Return in a one-line field is not asking for a line break; they are asking to be finished.
 *
 * THE INSERT HALF IS STILL REFUSED, at the door that inserts: `-insertText:` refuses a newline inside a string, and
 * that is where "no second line" belongs. */
- (void)insertNewline:(id)sender
{
	(void)sender;
	_movement = NSTextMovementReturn;
	[[self window] makeFirstResponder:nil];
}

- (void)insertTab:(id)sender
{
	(void)sender;
	/* **TAB IS A FOCUS MOVE AND NOT A CHARACTER**, which is Apple's rule for every field on this platform and the
	 * reason a form can be filled with one hand: the window's key-view loop already knows what comes next, so this
	 * hands it the question rather than answering it with a tab character nobody asked for.
	 *
	 * AND IT SAYS SO ON THE WAY OUT. The focus move ends the session by itself — `-selectNextKeyView:` makes the next
	 * view the first responder, which makes this one resign — so the only thing missing was the REASON, and a session
	 * that ended without one would reach the cell looking like a click into another field. */
	_movement = NSTextMovementTab;
	[[self window] selectNextKeyView:self];
}

- (void)insertBacktab:(id)sender
{
	(void)sender;
	_movement = NSTextMovementBacktab;
	[[self window] selectPreviousKeyView:self];
}

- (void)cancelOperation:(id)sender
{
	(void)sender;
	/* **ESCAPE ENDS THE SESSION AND THROWS AWAY WHAT WAS TYPED**, which is what it means in a field: the window is told
	 * the view is done rather than the view deciding who is next, because making a responder resign is the window's
	 * business — and `NSTextMovementCancel` is what tells whoever owns the string that this ending is a DISCARD.
	 * MEASURED before this code existed: Escape ended the session and the cell took the string back, so the key that is
	 * supposed to undo an edit performed it. */
	_movement = NSTextMovementCancel;
	[[self window] makeFirstResponder:nil];
}

@end
