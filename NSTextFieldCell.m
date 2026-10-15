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
	[self setObjectValue:aString];
	[self setTitle:(aString != nil ? aString : @"")];
}

- (NSString *)stringValue
{
	return [super stringValue];
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
	NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:faceRect
							     xRadius:NS_CELL_BEZEL_RADIUS
							     yRadius:NS_CELL_BEZEL_RADIUS];
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

/* **AND THE WORDS ARE LEFT-ALIGNED AND CLIPPED TO THE ROOM THE FIELD GIVES THEM.** `NSActionCell` draws nothing, so
 * everything here is this class's: the string is taken at its own height, placed at the text rect's left edge and
 * centred vertically on the field, and the drawing is clipped to the rect — so a string longer than its field stops
 * at the edge rather than running out of the control, which is what a field does at its far end. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSString *string = [self stringValue];
	NSFont *font = (NSFont *)[self font];
	NSDictionary *attributes;
	NSRect room = [self drawingRectForBounds:cellFrame];
	NSSize tsize;

	(void)controlView;
	if (string == nil || [string length] == 0) {
		/* NOTHING TO SAY: an empty field is its face and its border, which is a state a field starts in. */
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

	/* **AND THE MARGIN IS `NS_CELL_CONTENT_GAP`, WHICH IS THE TIER'S ONE ANSWER TO "HOW FAR IN DO THE WORDS BEGIN".**
	 * MEASURED on the sample: its own label starts two points inside its pop-up's border. This tier begins it four —
	 * the same margin a checkbox leaves between its box and its label — because the pop-up, the combo box and a field
	 * all begin their words at the same distance here, and three controls in one window that each answered the question
	 * differently would be three answers a person can see. */
	r.origin.x += NS_CELL_CONTENT_GAP;
	r.size.width -= NS_CELL_CONTENT_GAP;
	return NSInsetRect(r, 0.0, NS_CELL_BORDER_INSET);
}

- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = [super cellSizeForBounds:aRect];

	/* **AND THE MARGIN IS ALREADY IN THE BASE'S ANSWER.** MEASURED: a cell with the same title is 91.67 points bare
	 * and 95.67 bordered, so `NSCell` pays a bordered cell's margin once. This class draws the text INSIDE the field
	 * at the same margin, so the two agree without a second addition — which is the defect `NSPopUpButtonCell`'s
	 * version of this door shipped once and records. */
	(void)aRect;
	return size;
}

/* ---- THE SESSION ------------------------------------------------------------------------------------- */

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
	[textObj setFrame:room];
	[textObj setFieldEditor:YES];
	/* **AND THE EDITOR DOES NOT DRAW A BACKGROUND OF ITS OWN, WHICH IS WHAT MAKES A FIELD ONE FIELD.** The face under
	 * the editor is the one this cell drew a moment ago; an editor that painted white would cover the accent a combo
	 * box's field takes while it is being used, and the ink this cell chose for that face would then be white on white.
	 * The editor is text ON the field, not a second field. */
	[textObj setDrawsBackground:NO];
	[textObj setEditable:YES];
	[textObj setSelectable:YES];
	if ([self font] != nil) {
		[textObj setFont:[self font]];
	}
	[textObj setAlignment:[self alignment]];
	[textObj setString:(string != nil ? string : @"")];
	[textObj setDelegate:self];
	[controlView addSubview:textObj];
	[[controlView window] makeFirstResponder:textObj];
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
- (void)endEditing:(NSText *)textObj
{
	id caller = _editorDelegate;
	NSString *edited = [textObj string];

	if (edited != nil) {
		[self setStringValue:edited];
	}
	_editorDelegate = nil;
	[textObj setDelegate:nil];
	[textObj removeFromSuperview];
	if (caller != nil && [caller respondsToSelector:@selector(textDidEndEditing:)]) {
		[caller textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification
								      object:textObj]];
	}
}

/* **AND THIS IS HOW THE CELL HEARS THAT A SESSION IS OVER**, because it is the editor's delegate while one is running:
 * `NSText` posts this when it stops editing, and the cell's answer is to take its string back. A cell that did not
 * implement this would leave the editor's text on screen and the cell's own value behind it, which is a field that
 * shows one thing and holds another. */
- (void)textDidEndEditing:(NSNotification *)notification
{
	[self endEditing:[notification object]];
}

@end
