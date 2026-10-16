/*
 * NSTextFieldCell.m — the field's face, the string, and the three doors of an edit.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSGeometry.h>

@implementation NSTextFieldCell

- (instancetype)initTextCell:(NSString *)stringValue
{
	self = [super initTextCell:stringValue];
	if (self != nil) {
		/* **A FIELD SHOWS A SURFACE UNLESS IT IS TOLD NOT TO, AND IT IS WHITE.** Apple's default for a text field is
		 * `-drawsBackground` YES with `+textBackgroundColor`; this tier's is the same question answered with the colour
		 * a value is written on, which is `+controlBackgroundColor` — white — and that is a DIFFERENT GREY from the
		 * control face a button wears. A field is a hole in the surface that holds something; a button is a thing
		 * standing on it. */
		_drawsBackground = YES;
		/* **AND A FIELD'S BORDER IS ROUNDED UNTIL SOMEBODY SAYS SQUARE.** This is the one default in this class that
		 * Objective-C's zeroing would get wrong — `NSTextFieldSquareBezel` is 0 and `NSTextFieldRoundedBezel` is 1, the
		 * opposite of the button family's convention — so it is set out loud. */
		_bezelStyle = NSTextFieldRoundedBezel;
		/* **AND THE STRING A CELL IS MADE WITH BECOMES ITS VALUE, WHICH THE BASE'S INITIALISER DOES NOT DO.** `NSCell
		 * -initTextCell:` stores what it was given in `-_title`; a FIELD draws and measures `-_objectValue`, so a cell
		 * made with a string would otherwise draw with a value it does not have. `-setStringValue:` writes both doors
		 * and says why — see its own note, which is where the measurement half of the same fact is recorded. */
		[self setStringValue:stringValue];
	}
	return self;
}

- (void)dealloc
{
	[_backgroundColor release];
	[_textColor release];
	[_placeholderString release];
	[_placeholderAttributedString release];
	[super dealloc];
}

/* ---- THE STRING ------------------------------------------------------------------------------------- */

/* **AND IT IS A SPELLING OF THE BASE'S OBJECT, DELIBERATELY.** `NSCell -stringValue` already knows how to turn a value
 * into text — through a formatter, through `-description`, or through an attributed string's `-string` — so this pair
 * writes the value and reads the text, and there is exactly one place a cell's contents live. See the header. */
- (void)setStringValue:(NSString *)aString
{
	/* **AND IT WRITES THE BASE'S OTHER DOOR AS WELL, WHICH IS A MEASURED REQUIREMENT RATHER THAN BELT AND BRACES.**
	 * `NSCell` keeps the text of a cell in TWO places — `-_title` and `-_objectValue` — and the two are read by
	 * different doors: `-stringValue` reads the value (which is what a formatter reaches and what a field draws), and
	 * `-cellSizeForBounds:` measures the TITLE. MEASURED, before this line: a combo box built by its CONTROL, which
	 * makes its cell with an empty string and sets the text later, measured 19.61 points wide and drew a clipped "N" —
	 * because the measurement was looking at a title nobody had ever set. A field cell that wrote one door and not the
	 * other would be a field that shows its value and cannot measure it, so both are written here and the divergence
	 * between them is named where it bites. */
	/* **AND THE VALUE THE CELL KEEPS IS ITS OWN RATHER THAN THE CALLER'S.** `-setObjectValue:` RETAINS what it is
	 * given, which is the right contract for a value and the wrong one for a STRING that somebody else is still
	 * editing in place. MEASURED, and it cost the whole point of a keyboard loop: the editor's `-string` hands out the
	 * view's own MUTABLE buffer, so a session that committed its text left the CELL's value and the EDITOR's buffer as
	 * THE SAME OBJECT — and every later keystroke wrote into the cell's value directly. Escape could not discard
	 * anything, because the typed text had already arrived; the cell reported "thrown away" while its own instrumented
	 * writes said "typed".
	 *
	 * A COPY MAKE THE FIELD'S VALUE THE FIELD'S. It costs nothing for an immutable string (`-copy` answers self) and it
	 * is what makes "the cell holds this" a statement that stays true while something else holds a pointer to a buffer
	 * with the same contents. */
	[self setObjectValue:[[aString copy] autorelease]];
	/* **AND THE LABEL IS NO LONGER WRITTEN BESIDE IT, WHICH IS THE PART THIS REFACTOR TOOK BACK.** An earlier fix for
	 * the same confusion wrote the string into BOTH doors, because the base's measurement read the label while the
	 * drawing read the value — a patch at the point of the bite, and an honest one at the time. The measurement reads
	 * `-cg_contentText` now, so the patch is not needed and its absence is the point: one fact, one place. */
	/* **AND AN EDITOR SHOWING THE OLD TEXT IS TOLD, WHICH IS WHAT "REPLACE IT MID-EDIT" MEANS.** While a session runs,
	 * the editor is what draws the words — the cell stops drawing its own string (see `-drawInteriorWithFrame:`) — so a
	 * value that changed in the CELL alone would be a value nobody could see: MEASURED, choosing a row from a combo
	 * box's list while its field was being edited left the picked value in the cell and the TYPED text on screen, which
	 * is the field and the model disagreeing about what the field says.
	 *
	 * `-setString:` is the whole of the write because that door is documented as replacing the string AND putting the
	 * insertion point at its end, which is exactly where a person who has just been given a value wants to be. */
	if (_cg_editor != nil) {
		[_cg_editor setString:(aString != nil ? aString : @"")];
	}
}

- (NSString *)stringValue
{
	return [super stringValue];
}

/* **AND A FIELD'S TEXT IS ITS VALUE RATHER THAN ITS LABEL, WHICH IS THE WHOLE OF THIS CLASS'S ANSWER TO THE TWO DOORS.**
 * `NSCell` has a label (`-_title`) and a value (`-_objectValue`), and for a field the SECOND is the text: it is what a
 * formatter produces, what an edit session reads back, and what this class draws. Answering `-cg_contentText` here is
 * what makes the base's measurement measure the value too, so "what a field measures" and "what a field shows" stop
 * being two questions with two answers.
 *
 * THE LABEL IS STILL THE FALLBACK, because a field cell given a title and no value has been given something and should
 * show it — and because the base's `-initTextCell:` sets the label, so a caller who makes one that way gets a field
 * that says what they asked for rather than an empty one. */
- (NSString *)cg_contentText
{
	NSString *value = [self stringValue];

	return (value != nil) ? value : [super cg_contentText];
}

/* ---- WHAT AN EMPTY FIELD SAYS IT IS FOR -------------------------------------------------------------- */

- (NSString *)placeholderString
{
	return _placeholderString;
}

/* **A COPY, SO A CALLER CANNOT CHANGE THE FIELD BY KEEPING ITS OWN MUTABLE STRING.** The same rule `NSButtonCell`
 * records for its attributed strings, and it costs nothing for an immutable one (`-copy` answers self). */
- (void)setPlaceholderString:(NSString *)string
{
	if (string != _placeholderString) {
		NSString *copy = [string copy];

		[_placeholderString release];
		_placeholderString = copy;
	}
}

- (NSAttributedString *)placeholderAttributedString
{
	return _placeholderAttributedString;
}

- (void)setPlaceholderAttributedString:(NSAttributedString *)string
{
	if (string != _placeholderAttributedString) {
		NSAttributedString *copy = [string copy];

		[_placeholderAttributedString release];
		_placeholderAttributedString = copy;
	}
}

/* **AND THE GREY A PLACEHOLDER IS DRAWN IN, WHICH IS A DOOR BECAUSE A SUBCLASS MAY OWE A DIFFERENT ONE.** See the
 * header: the era publishes no placeholder colour, so this is the closest era colour rather than an invented value. */
- (NSColor *)cg_placeholderColor
{
	return [NSColor disabledControlTextColor];
}

/* **AND WHAT IS ACTUALLY DRAWN, WHICH IS THE ATTRIBUTED FORM IF THERE IS ONE AND THE PLAIN FORM BUILT INTO THAT SAME
 * KIND OF OBJECT OTHERWISE.** Building the plain one into an `NSAttributedString` is what gives the drawing and the
 * MEASUREMENT one path instead of two that could disagree about where the words sit — and the font is the CELL's own,
 * because a placeholder is the field's text in a different colour and not a different typeface. */
- (NSAttributedString *)cg_placeholderText
{
	NSFont *font;

	if (_placeholderAttributedString != nil) {
		return _placeholderAttributedString;
	}
	if (_placeholderString == nil || [_placeholderString length] == 0) {
		return nil;
	}
	font = (NSFont *)[self font];
	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	return [[[NSAttributedString alloc] initWithString:_placeholderString
		attributes:[NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
			[self cg_placeholderColor], NSForegroundColorAttributeName, nil]] autorelease];
}

/* ---- THE FACE ---------------------------------------------------------------------------------------- */

- (BOOL)drawsBackground
{
	return _drawsBackground;
}

- (void)setDrawsBackground:(BOOL)flag
{
	_drawsBackground = flag;
}

/* **THE TWO BEZEL STYLES, WHICH ARE STORED AND READ BY THE DRAWING ALONE.** See the header for why the pair is a
 * `NSTextFieldBezelStyle` rather than the button family's `NSBezelStyle`; here it is enough that the setter is plain
 * storage — a cell has no view to redraw, and the control that owns it owes the `-setNeedsDisplay:` when it forwards
 * the change. */
- (NSTextFieldBezelStyle)bezelStyle
{
	return _bezelStyle;
}

- (void)setBezelStyle:(NSTextFieldBezelStyle)style
{
	_bezelStyle = style;
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

/* **THE BACKGROUND IS THE TIER'S, NOT A CALLER'S, UNTIL A CALLER SAYS OTHERWISE** — the same rule `NSButtonCell`
 * records for its own `-backgroundColor:`: nil here means "the field's own surface", which is what makes a captured
 * background mean something rather than being the same colour by coincidence. */
- (void)setBackgroundColor:(NSColor *)color
{
	if (color != _backgroundColor) {
		id held = [color retain];

		[_backgroundColor release];
		_backgroundColor = held;
	}
	_drawsBackground = (color != nil);
}

- (NSColor *)textColor
{
	return _textColor;
}

- (void)setTextColor:(NSColor *)color
{
	if (color != _textColor) {
		id held = [color retain];

		[_textColor release];
		_textColor = held;
	}
}

- (NSColor *)cg_fieldFillColor
{
	if (!_drawsBackground) {
		return nil;
	}
	return (_backgroundColor != nil) ? _backgroundColor : [NSColor controlBackgroundColor];
}

/* **AND THE INK THAT CLEARS THAT FILL, IN THE SAME SHAPE THE BUTTON CELLS USE.** A caller who set a colour gets it; a
 * disabled field gets the era's dimmed grey; and everything else gets the control's own text colour. It is the door a
 * subclass overrides when its field's FILL can change under it — the combo box does exactly that for the accent — and
 * it carries the same name as `NSButtonCell`'s and `NSPopUpButtonCell`'s because it is the same question: what colour
 * do the words have to be to be read on what is underneath them. */
- (NSColor *)cg_inkColor
{
	if (_textColor != nil) {
		return _textColor;
	}
	return ![self isEnabled] ? [NSColor disabledControlTextColor] : [NSColor controlTextColor];
}

/* ---- THE INK ---------------------------------------------------------------------------------------- */

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	/* **THE FILL FIRST IF THERE IS ONE, THEN THE BORDER, THEN THE WORDS.** A field that draws no background still
	 * draws its border — that is a transparent field, which is a real thing — and the border is drawn whether or not
	 * the face was, because the two are separate questions and `-isBordered` is only one of them. The path is inset by
	 * half the stroke for the reason `NSText` records: a stroke is centred on its path, so a border drawn AT the edge
	 * spends half its ink outside the control, where a view's own clip would cut it. */
	NSRect faceRect = NSInsetRect(cellFrame, NS_CELL_BEZEL_WIDTH / 2.0, NS_CELL_BEZEL_WIDTH / 2.0);
	/* **AND THE CORNERS ARE THE ONE THING THE BEZEL STYLE CHANGES.** One path constructor does both: a rounded field
	 * passes `NS_CELL_BEZEL_RADIUS` and a square one passes ZERO, which `CGPathAddRoundedRect` treats as the rectangle
	 * it is (MEASURED in `libagora-drawing`: the zero case is a plain `CGPathAddRect`). So a square field is not a
	 * second drawing path — it is the same path with its corners not cut — which is what keeps every other measure
	 * (the border's inset, its width, the text rect) identical between the two. */
	CGFloat radius = (_bezelStyle == NSTextFieldSquareBezel) ? 0.0 : NS_CELL_BEZEL_RADIUS;
	NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:faceRect
							     xRadius:radius
							     yRadius:radius];
	NSColor *fill = [self cg_fieldFillColor];

	if (fill != nil) {
		[fill setFill];
		[face fill];
	}
	if ([self isBezeled] || [self isBordered]) {
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:NS_CELL_BEZEL_WIDTH];
		[face stroke];
	}

	[self drawInteriorWithFrame:cellFrame inView:controlView];
}

/* **AND THE PLACEHOLDER IS DRAWN THE WAY THE STRING IS, BECAUSE IT IS THE SAME SORT OF THING.** Same text rect, same
 * left edge, same vertical centring on the field, same clip — so a hint and a value cannot sit at different heights in
 * the same box, which is the bug a second placement path always grows. What differs is the COLOUR, and that is the
 * whole point of a placeholder. */
- (void)cg_drawPlaceholderInFrame:(NSRect)cellFrame
{
	NSAttributedString *text = [self cg_placeholderText];
	NSRect room = [self drawingRectForBounds:cellFrame];
	NSSize size;

	if (text == nil) {
		return;
	}
	size = [text size];
	if (size.width <= 0.0 || size.height <= 0.0 || NSWidth(room) <= 0.0) {
		return;
	}
	room = NSMakeRect(NSMinX(room), NSMidY(cellFrame) - size.height / 2.0, NSWidth(room), size.height);
	[NSGraphicsContext saveGraphicsState];
	[[NSBezierPath bezierPathWithRect:room] setClip];
	[text drawInRect:room];
	[NSGraphicsContext restoreGraphicsState];
}

/* **AND THE WORDS ARE LEFT-ALIGNED AND CLIPPED TO THE ROOM THE FIELD GIVES THEM.** `NSActionCell` draws nothing, so
 * everything here is this class's: the string is taken at its own height, placed at the text rect's left edge and
 * centred vertically on the field, and the drawing is clipped to the rect — so a string longer than its field stops
 * at the edge rather than running out of the control, which is what a field does at its far end. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	/* **AND WHAT IS DRAWN IS `-cg_contentText`, THE SAME DOOR THE MEASUREMENT ASKS.** A field that measured its value
	 * and drew its label would be a field whose frame and whose words disagreed, which is the shape of every bug this
	 * door exists to end. */
	NSString *string = [self cg_contentText];
	/* **AND WHETHER THIS FIELD IS EMPTY IS A QUESTION ABOUT THE LIVE TEXT, NOT ABOUT THE CELL'S VALUE.** While a
	 * session runs the words on screen are the EDITOR's, so an empty editor is an empty field even when the cell still
	 * holds the value the session began with. See the header for why that distinction is the point. */
	NSString *live = _cg_textEditing ? [(NSText *)_cg_editor string] : string;
	NSFont *font = (NSFont *)[self font];
	NSDictionary *attributes;
	NSRect room = [self drawingRectForBounds:cellFrame];
	NSSize tsize;

	(void)controlView;
	if (live == nil || [live length] == 0) {
		/* **AN EMPTY FIELD SHOWS ITS PLACEHOLDER, WHICH IS THE ONE THING THAT GOES WHERE THE WORDS WOULD.** With no
		 * placeholder set the door draws NOTHING at all, so an empty field is its face and its border — which is what
		 * it always was. */
		[self cg_drawPlaceholderInFrame:cellFrame];
		return;
	}
	/* **AND WHILE AN EDITOR IS UP, THE TEXT IS THE EDITOR'S.** Two objects drawing one string is two strings on
	 * screen the moment the editor's differs from the cell's — which is every keystroke — and the demonstration showed
	 * exactly that. See the ivar's note. */
	if (_cg_textEditing) {
		return;
	}
	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
		      [self cg_inkColor], NSForegroundColorAttributeName, nil];
	tsize = [string sizeWithAttributes:attributes];
	if (tsize.width <= 0.0 || tsize.height <= 0.0 || NSWidth(room) <= 0.0) {
		return;
	}
	room = NSMakeRect(NSMinX(room), NSMidY(cellFrame) - tsize.height / 2.0, NSWidth(room), tsize.height);
	[NSGraphicsContext saveGraphicsState];
	[[NSBezierPath bezierPathWithRect:room] setClip];
	[string drawInRect:room withAttributes:attributes];
	[NSGraphicsContext restoreGraphicsState];
}

/* **AND THE MARGIN IS MEASURED FROM THE FIELD'S OWN EDGE RATHER THAN FROM THE BASE'S INSET RECT.** MEASURED: the ink
 * landed at x=7 when this added its margin to `[super drawingRectForBounds:]`, because `NSCell` insets a bordered cell
 * by `NS_CELL_BORDER_INSET` — a border's own air — and the margin stacked on top of it. The distance a person reads is
 * from the BORDER, which is what the four points are for, so the rect is taken from the frame and the border's air is
 * not paid twice. */
- (NSRect)drawingRectForBounds:(NSRect)theRect
{
	NSRect r = theRect;

	/* **AND THE PADDING IS `NS_TEXT_INSET`, ON ALL FOUR SIDES, BECAUSE IT IS A FIELD'S PADDING AND NOT A CELL'S.**
	 * This used to be `NS_CELL_CONTENT_GAP` across and `NS_CELL_BORDER_INSET` down — two numbers with two other jobs,
	 * neither of them this one — while the VIEW that draws the same kind of field padded by a third number of its own.
	 * MEASURED, the pair disagreed on the vertical axis and the horizontal one was right by coincidence: the gap
	 * happens to be four as well.
	 *
	 * THE CONTENT GAP KEEPS ITS OWN JOB, which is the margin between a control's MARK and its words — a checkbox's box
	 * and its label, a pop-up's arrow and its title. A field has no mark; it has a border, and what it owes that border
	 * is the same air on every side. */
	return NSInsetRect(r, NS_TEXT_INSET, NS_TEXT_INSET);
}

- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = [super cellSizeForBounds:aRect];

	/* **AND THE MARGIN IS ALREADY IN THE BASE'S ANSWER.** MEASURED: a cell with the same title is 91.67 points bare
	 * and 95.67 bordered, so `NSCell` pays a bordered cell's margin once. This class draws the text INSIDE the field
	 * at the same margin, so the two agree without a second addition — which is the defect `NSPopUpButtonCell`'s
	 * version of this door shipped once and records. */
	/* **AND AN EMPTY FIELD IS STILL ONE LINE TALL, WHICH IS THE HEIGHT A PLACEHOLDER IS READ IN.** `NSCell` measures the
	 * cell's TEXT, and an empty string has no LINE in it — MEASURED, an empty field comes back 6.00 points high (the
	 * two padding bands and nothing else) against 21.73 for the same field holding a value. That is not a fact about a
	 * field: a field's height is its FONT's line, whether or not it happens to hold anything, and a field sized while
	 * empty is the NATURAL shape when a placeholder is what it opens with. So the line is measured and the height
	 * raised to it; the WIDTH is left as the base computed it, because "as wide as nothing" is what sizing to an empty
	 * string honestly means. */
	if ([[self cg_contentText] length] == 0) {
		CGFloat pad = NS_CELL_CONTENT_PADDING + (([self isBordered] || [self isBezeled]) ? NS_CELL_BORDER_INSET : 0.0);
		NSFont *font = (NSFont *)[self font];
		CGFloat want;
		NSSize line;

		if (font == nil) {
			font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
		}
		line = [@" " sizeWithAttributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
		want = line.height + 2.0 * pad;
		/* **AND THE SAME CLAMP THE BASE PUTS ON ITS OWN ANSWER**: a cell measures its CONTENTS and the caller's rectangle
		 * bounds them, so a line taller than the rect given is the rect. */
		if (want > aRect.size.height) {
			want = aRect.size.height;
		}
		if (size.height < want) {
			size.height = want;
		}
	}
	return size;
}

/* ---- THE SESSION ------------------------------------------------------------------------------------- */

/* **AND HOW AN EDITOR IS TOLD WHAT KIND OF FIELD IT IS EDITING, WHICH IS THE DOOR THE SESSION BELOW USED TO INLINE.**
 * The font, the alignment, the fact that the editor paints nothing, and the two flags about what the field may hold
 * are all settings about the FIELD and not about one session — so they live here, the session calls this, and a
 * subclass with an editor of its own overrides one method rather than editing a copy of the session.
 *
 * **AND THE TWO ATTRIBUTED-EDITING FLAGS ARE THE PART THAT WAS NOT WIRED.** `NSCell` has carried
 * `-allowsEditingTextAttributes` and `-importsGraphics` since the cell family's first slice, and the EDITOR has carried
 * `-isRichText` and `-isImportsGraphics` since the text view's, and nothing connected them — so a caller could set a
 * field rich and get a plain editor. They are copied here. **WHAT STILL DOES NOT HAPPEN IS NAMED RATHER THAN IMPLIED:**
 * this tier has no RTF reader, no attachment drawing and no paragraph model, so the editor stores both and obeys
 * neither (`NSText.h` says so where the flags live), and this is the door that would make them mean something. */
- (NSText *)setUpFieldEditorAttributes:(NSText *)textObj
{
	/* **AND THE EDITOR PAINTS NOTHING AT ALL, WHICH IS THE ONLY ANSWER THAT CANNOT GO WRONG.** An earlier version of
	 * this setting made the editor draw a background and handed it `-cg_fieldFillColor` — on the theory that one fill
	 * asked for twice would agree with itself. IT DOES NOT AGREE, because the answer DEPENDS ON THE POINTER: the moment
	 * a person clicks into the field the pointer is inside it, so the door answered the PRELIGHT GREY rather than the
	 * field's white, and the editor painted a grey rectangle inside a white field. MEASURED on the demonstration: that
	 * grey box is exactly the editor's own background — inset from the border, stopping at the chip.
	 *
	 * THE CELL ALREADY DRAWS THE FACE and always did; what it stops drawing during a session is its STRING (see
	 * `-drawInteriorWithFrame:`), and that alone is what removes the double text. An editor that draws no background is
	 * text ON a field rather than a second field, which is what a field editor is. */
	[textObj setFieldEditor:YES];
	[textObj setDrawsBackground:NO];
	[textObj setEditable:YES];
	[textObj setSelectable:YES];
	if ([self font] != nil) {
		[textObj setFont:[self font]];
	}
	[textObj setAlignment:[self alignment]];
	[textObj setRichText:[self allowsEditingTextAttributes]];
	[textObj setImportsGraphics:[self importsGraphics]];
	return textObj;
}

/* **THE CELL IS THE EDITOR'S DELEGATE, AND THAT IS THE WHOLE DESIGN OF AN EDIT.** Apple's field editor is ONE object
 * the window owns and lends; the cell is told to begin a session, sets the editor up over its own text, and is the
 * thing the editor reports back to — because the string belongs to the cell and reading it back is the cell's job. The
 * delegate a CALLER passes is kept beside this one and told afterwards, so a control that wants to know when its
 * field was edited hears about it without owning the session. */
- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj
	       delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength
{
	NSRect room = [self drawingRectForBounds:aRect];
	NSString *string = [self stringValue];

	_editorDelegate = anObject;
	_cg_textEditing = YES;
	[textObj setFrame:room];
	/* **AND THE FIELD'S OWN SETTINGS COME FROM THE DOOR ABOVE**, so a subclass that wants a different editor changes
	 * one method rather than editing this one — and the editor that comes back is the one held as this session's, in
	 * case it is not the same object. */
	textObj = [self setUpFieldEditorAttributes:textObj];
	_cg_editor = textObj;
	[textObj setString:(string != nil ? string : @"")];
	[textObj setDelegate:self];
	[controlView addSubview:textObj];
	/* **AND A SESSION THAT WAS REFUSED LEAVES NOTHING STANDING.** The editor's own `-becomeFirstResponder` asks THIS
	 * cell, and this cell passes the question to the caller — so a delegate that answers NO to
	 * `-control:textShouldBeginEditing:` is a form saying "not yet". By the time the answer comes back the editor has
	 * been put in the view and every session flag is set, so the refusal has to be UNDONE here: otherwise a field
	 * nobody is allowed to edit would still show a caret in a view and answer `-currentEditor` with it. MEASURED, the
	 * window's `-makeFirstResponder:` fails in exactly this case and its answer is the signal. */
	if (![[controlView window] makeFirstResponder:textObj]) {
		[textObj setDelegate:nil];
		[textObj removeFromSuperview];
		_editorDelegate = nil;
		_cg_editor = nil;
		_cg_textEditing = NO;
		return;
	}
	[textObj setSelectedRange:NSMakeRange((NSUInteger)selStart, (NSUInteger)selLength)];
}

/* **AND A POINTER'S EDIT SELECTS THE WHOLE STRING, WHICH IS WHAT A FIELD DOES WHEN IT IS CLICKED INTO.** Apple's rule
 * is that the first click into an unselected field takes all of it, so that typing replaces it — a field that put a
 * caret in the middle of somebody's value would make them delete it by hand. The event is taken and unused beyond
 * that, because whether the click landed inside the existing selection is the refinement that makes a second click
 * put a caret down, and this tier does not yet tell those two clicks apart. */
- (void)editWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj
	     delegate:(id)anObject event:(NSEvent *)theEvent
{
	(void)theEvent;
	[self selectWithFrame:aRect inView:controlView editor:textObj delegate:anObject
			start:0 length:(NSInteger)[[self stringValue] length]];
}

/* **AND ENDING THE SESSION IS THE CELL TAKING ITS STRING BACK.** The editor's text becomes the cell's value, the
 * editor stops being this cell's delegate and leaves the view it was put in, and the caller's delegate is told — in
 * that order, because a delegate that reads the cell is entitled to find the new value already in it. NOTHING HERE
 * DISCARDS THE EDITOR: it is the window's and it goes back to the window, which is the whole reason a window lends one
 * rather than each field making its own. */
/* **AND ENDING A SESSION IS ONE PIECE OF WORK WITH TWO ANSWERS, WHICH IS WHY THE MOVEMENT IS AN ARGUMENT.** Everything
 * about ending is the same either way — the editor stops being this cell's delegate, it leaves the view it was put in,
 * and the caller's delegate is told — and the ONE thing that differs is whether the editor's string becomes the cell's
 * value. So the two public answers are this method with a flag, rather than two copies of a teardown that would drift.
 *
 * THE MOVEMENT IS HANDED ON RATHER THAN SWALLOWED. A caller who lent an editor wants to know WHY the session ended —
 * a control sends its action on Return and Tab and must not on Escape — and the caller's notification carries the same
 * code this cell was told, so nobody has to reconstruct it. */
- (void)fn_finishEditing:(NSText *)textObj keep:(BOOL)keep movement:(NSTextMovement)movement
{
	id caller = _editorDelegate;

	/* **AND THE EDITOR IS FORGOTTEN BEFORE THE STRING IS WRITTEN BACK, WHICH IS AN ORDER AND NOT A STYLE.** The
	 * write-back below goes through `-setStringValue:`, which tells the editor about a new value — so forgetting it
	 * first keeps the teardown from telling the editor a string it is standing on, and leaves one rule (a session's
	 * editor hears about changes) rather than an exception to it. */
	_editorDelegate = nil;
	_cg_editor = nil;
	_cg_textEditing = NO;
	if (keep) {
		NSString *edited = [textObj string];

		if (edited != nil) {
			[self setStringValue:edited];
		}
	}
	[textObj setDelegate:nil];
	[textObj removeFromSuperview];
	if (caller != nil && [caller respondsToSelector:@selector(textDidEndEditing:)]) {
		NSDictionary *info = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:(NSInteger)movement]
								 forKey:NSTextMovementUserInfoKey];

		[caller textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification
								       object:textObj
								     userInfo:info]];
	}
}

- (void)endEditing:(NSText *)textObj
{
	/* A DIRECT CALL TAKES THE STRING, because a caller who ends a session by hand is not expressing a cancellation —
	 * there is no key behind it and therefore no reason to discard anything. The reason only exists when a KEY ended
	 * the session, which is the path below. */
	[self fn_finishEditing:textObj keep:YES movement:NSTextMovementOther];
}

/* **AND THE TWO QUESTIONS A CONTROL ASKS, ANSWERED FROM THE ONE RECORD THIS CLASS KEEPS.** The editor and the flag are
 * set together when a session opens and cleared together when it ends, so asking the flag and returning the pointer is
 * one answer rather than two that could disagree: there is never an editor without a session, and the flag is what the
 * DRAWING reads to decide whether the words are the cell's or the editor's. */
- (NSText *)cg_currentEditor
{
	return _cg_textEditing ? _cg_editor : nil;
}

/* **AND AN ABORT IS THE ENDING ESCAPE PERFORMS, REACHED THROUGH A DOOR RATHER THAN A KEY.** That is not a figure of
 * speech: the ending is `-cancelOperation:`, which marks the reason `NSTextMovementCancel` and asks the WINDOW to take
 * the editor down. Going through the window matters, and not for tidiness — a teardown done here in private would
 * remove the editor from the view while the window still believed it was the first responder, so the keyboard would
 * keep going to a detached view. The one ending, `-fn_finishEditing:keep:movement:`, still does the work; this door
 * only supplies the reason and lets the window unwind the focus.
 *
 * NO WHEN THERE IS NOTHING TO ABORT, which is Apple's reading of the BOOL: a caller that aborted an untouched control
 * is told nothing was thrown away rather than that it succeeded. */
- (BOOL)cg_abortEditing
{
	NSText *editor = _cg_editor;

	if (!_cg_textEditing || editor == nil) {
		return NO;
	}
	if ([editor window] != nil) {
		[editor cancelOperation:nil];
	}
	/* **AND THE TEARDOWN IS NOT ASSUMED.** A session opened on a view that has no window — which the session door above
	 * permits, since a field can be built before it is put anywhere — cannot reach the window's door, so whatever is
	 * still running after that attempt is ended here. The fallback is the same ending with the same reason. */
	if (_cg_textEditing) {
		[self fn_finishEditing:editor keep:NO movement:NSTextMovementCancel];
	}
	return YES;
}

/* **AND THE FOUR SESSION EVENTS THE CELL PASSES STRAIGHT THROUGH, BECAUSE THE OBJECT A CALLER WANTS TOLD IS THE
 * CONTROL.** `NSText` sends these to ITS delegate, and the editor's delegate is the CELL — it owns the string and
 * reads it back. But a caller set a target and writes a handler against the CONTROL, so the cell is a RELAY for the
 * four that are about the session rather than about the string, and the caller passes the answer back up: the two
 * `Should` questions are where a delegate refuses, and the refusal is only meaningful if it survives the hop. */
- (BOOL)textShouldBeginEditing:(NSText *)textObject
{
	id caller = _editorDelegate;

	if (caller != nil && [caller respondsToSelector:@selector(textShouldBeginEditing:)]) {
		return [caller textShouldBeginEditing:textObject];
	}
	return YES;
}

- (void)textDidBeginEditing:(NSNotification *)notification
{
	id caller = _editorDelegate;

	if (caller != nil && [caller respondsToSelector:@selector(textDidBeginEditing:)]) {
		[caller textDidBeginEditing:notification];
	}
}

- (BOOL)textShouldEndEditing:(NSText *)textObject
{
	id caller = _editorDelegate;

	if (caller != nil && [caller respondsToSelector:@selector(textShouldEndEditing:)]) {
		return [caller textShouldEndEditing:textObject];
	}
	return YES;
}

- (void)textDidChange:(NSNotification *)notification
{
	id caller = _editorDelegate;

	if (caller != nil && [caller respondsToSelector:@selector(textDidChange:)]) {
		[caller textDidChange:notification];
	}
}

/* **AND THIS IS HOW THE CELL HEARS THAT A SESSION IS OVER, AND WHY.** The editor is this cell's delegate while one is
 * running, so the notification arrives here carrying the movement — and the ONE movement that is not an acceptance is
 * `NSTextMovementCancel`: MEASURED before this, Escape ended the session and the cell took the string back, so the key
 * that exists to undo an edit performed it. Everything else keeps what was typed, which is what Return and Tab mean.
 *
 * A NOTIFICATION WITH NO MOVEMENT IN IT SENDS THE STRING, deliberately: `Other` is what a session that ended by a click
 * elsewhere reports, and a click into another field is an acceptance of what was typed rather than a cancellation. */
- (void)textDidEndEditing:(NSNotification *)notification
{
	id raw = [[notification userInfo] objectForKey:NSTextMovementUserInfoKey];
	NSTextMovement movement = (raw != nil) ? (NSTextMovement)[raw integerValue] : NSTextMovementOther;

	[self fn_finishEditing:[notification object] keep:(movement != NSTextMovementCancel) movement:movement];
}

@end
