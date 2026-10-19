/*
 * NSTextFieldCell.h — THE CELL THAT OWNS A FIELD'S FACE, ITS STRING, AND THE SESSION THAT EDITS IT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS THE CLASS THE TIER HAS BEEN DRAWING BY HAND.** A text field's face is one point of border at radius four
 * with the text inset from the edge — and until now that face was drawn in TWO places that had no right to agree:
 * `NSPopUpButtonCell` draws it because the sample draws a pop-up as a field rather than a bezel, and `NSComboBoxCell`
 * draws it because a combo box IS one. Both took their measures from `NSCell.h`, which is what kept them honest, but
 * a third control wanting a field would have started a third copy. This class is the one that owns the face, and a
 * control that wants a field wears it.
 *
 * **AND IT IS ALSO WHERE APPLE PUTS A FIELD'S EDITING, WHICH IS THE OTHER HALF OF WHY IT EXISTS.** Apple's
 * `NSComboBoxCell` is an `NSTextFieldCell`; that is not an incidental fact about the hierarchy, it is where a combo
 * box's string, its selection and its edit session come from. This tier had no such class, so `NSComboBoxCell` started
 * at `NSActionCell` and could not be typed into — a row both headers recorded. THE CLASS BELOW CLOSES IT.
 *
 * **THE STRING LIVES IN THE BASE'S `-_objectValue`, WHICH IS APPLE'S OWN ARRANGEMENT AND NOT A SHORTCUT.** `NSCell`'s
 * `-stringValue` already answers an object's text — through a formatter when one is set, through `-description` when
 * there is not, and through `-string` when the object is an `NSAttributedString` — so a field cell that invented a
 * second string of its own would have two answers to "what does this cell say" and a formatter that reached only one
 * of them. `-setStringValue:` is therefore a spelling of `-setObjectValue:`, and it is written out because it is the
 * door a caller actually wants to name.
 *
 * **AND THE EDIT SESSION IS THREE DOORS, BECAUSE THAT IS HOW APPLE SPLITS IT.** `-selectWithFrame:inView:editor:
 * delegate:start:length:` puts an editor over this cell's text and selects a range; `-editWithFrame:inView:editor:
 * delegate:event:` is the same thing with a pointer's event behind it; and `-endEditing:` takes the editor's string
 * back into the cell and takes the editor away. THE CELL DOES NOT CREATE THE EDITOR — the window lends one (see
 * `NSWindow -fieldEditor:forObject:`, whose refusal this slice retires) — and that split is what makes a cell a
 * thing that can be drawn by anyone and edited by a window.
 */
#ifndef APPKIT_NSTEXTFIELDCELL_H
#define APPKIT_NSTEXTFIELDCELL_H

#import <AppKit/NSActionCell.h>

@class NSColor;
@class NSFont;
@class NSText;
@class NSEvent;
@class NSView;

NS_ASSUME_NONNULL_BEGIN

/* **AND A FIELD'S TWO BEZEL SHAPES, WHICH ARE APPLE'S OWN VOCABULARY AND NOT A BUTTON'S.** `NSButtonCell` has
 * `NSBezelStyle` — fifteen values, none of them a field's — and `NSTextFieldCell` has this pair instead, declared in
 * Apple's `NSTextFieldCell.h` rather than in `NSCell.h`. The two cases are the same face drawn twice: SQUARE means the
 * border is a rectangle, ROUNDED means its corners take `NS_CELL_BEZEL_RADIUS`. **ZERO IS SQUARE HERE, WHICH IS THE
 * OPPOSITE OF THE BUTTON'S** — `NSRoundedBezelStyle` IS 1 over there and zero is not a bezel style at all — so the
 * default cannot come from Objective-C's zeroing and is set out loud where the cell is made. */
enum {
	NSTextFieldSquareBezel = 0,
	NSTextFieldRoundedBezel = 1
};
typedef NSUInteger NSTextFieldBezelStyle;

@interface NSTextFieldCell : NSActionCell
{
	/* THE FACE'S OWN TWO COLOURS. The background is what the field shows when it draws one, and it is WHITE by
	 * default because that is what a field is: the surface a value is written ON rather than a control's raised face.
	 * A control that wants the tier's grey — the pop-up, the combo box — overrides `-cg_fieldFillColor` rather than
	 * setting this, so that "what colour is this field" has one answer per cell instead of two that can disagree. */
	NSColor *_backgroundColor;	/* RETAINED */
	NSColor *_textColor;		/* RETAINED */
	BOOL _drawsBackground;
	/* **AND THE SHAPE OF THAT FACE'S BORDER, WHICH IS THIS CLASS'S OWN VOCABULARY (both cases are declared above).**
	 * ROUNDED is the default, which is Apple's for a text field — and it is SET rather than left to the zeroing,
	 * because zero is SQUARE here: the opposite of the button family, where zero is not a bezel style at all. */
	NSTextFieldBezelStyle _bezelStyle;
	/* **AND WHAT AN EMPTY FIELD SAYS IT IS FOR, WHICH IS THE CELL'S RATHER THAN THE CONTROL'S.** Apple declares the
	 * pair on `NSTextFieldCell`; the control's own `-placeholderString` is a 10.10 addition and stays out with the rest
	 * of the after-10.6 surface, so a caller reaches through the cell — which is what the demo does. BOTH ARE COPIES,
	 * the same rule `NSButtonCell` records for its attributed strings: a placeholder is what the field SHOWS, so a
	 * caller who mutates the string it handed over must not be able to change the field underneath. The attributed
	 * one WINS when both are set, being the more specific answer to "what does this say". */
	NSString *_placeholderString;			/* RETAINED (a copy) */
	NSAttributedString *_placeholderAttributedString;	/* RETAINED (a copy) */
	/* **THE CALLER'S DELEGATE FOR THE SESSION IN FLIGHT, WHICH IS NOT THE SAME THING AS THE CELL'S OWN.** This cell
	 * IS the editor's delegate while an edit is running — it has to be, because reading the string back is its job —
	 * so the delegate a caller handed to `-selectWithFrame:...` is kept HERE and told what happened afterwards. NOT
	 * RETAINED: this tree's rule for every delegate. */
	id _editorDelegate;		/* NOT RETAINED */
	/* **AND THE EDITOR ITSELF, WHILE ONE IS SHOWING THIS CELL'S TEXT.** It is NOT RETAINED — during a session it is a
	 * subview of the control being edited, so the VIEW TREE owns it, and the window owns it for the rest of its life.
	 * It is kept because the cell has to be able to reach the thing that is currently displaying its string: a value
	 * that changes underneath a running session has to reach BOTH of them, and the editor is the one a person is
	 * looking at. */
	NSText *_cg_editor;		/* NOT RETAINED */
	/* **AND WHETHER AN EDITOR IS SHOWING THIS CELL'S TEXT, WHICH THE DRAWING HAS TO KNOW.** MEASURED on the
	 * demonstration: typing into a combo box put the editor's words ON TOP of the string the cell had already drawn, so
	 * the field showed both at once — "NSComboBox" with the typed text over it and a selection between them. The cell
	 * draws the string and the EDITOR draws the string; while a session is running it must be only one of them, and it
	 * is the editor's, because it is the one with the caret in it. */
	BOOL _cg_textEditing;
}

/* ---- THE STRING, WHICH IS THE BASE'S OBJECT SEEN AS TEXT -------------------------------------------- */

- (void)setStringValue:(nullable NSString *)aString;
- (nullable NSString *)stringValue;

/* **AND THIS IS THE CLASS THAT ANSWERS `NSCell`'s TWO TEXT DOORS WITH ONE.** A field's text is its VALUE — what a
 * formatter produces, what an edit session reads back, and what this cell draws and measures. The base's default
 * answer is the LABEL, which is what a button or a menu item wants; a field overrides it, and from that one override
 * follow the measurement's size, the drawn words, and the answer an editor is opened with. */
- (nullable NSString *)cg_contentText;

/* ---- WHAT AN EMPTY FIELD SAYS IT IS FOR ----------------------------------------------------------------- */

/* **A PLACEHOLDER IS DRAWN WHEN THE FIELD HAS NO TEXT, IN PLACE OF THE STRING RATHER THAN BESIDE IT.** It is the
 * field's own caption for itself — "type here", a search field's "Search" — and it is NOT a value: it never becomes
 * the field's string, it is not what an edit session is opened with, and ending a session does not commit it. What it
 * IS is drawn in a grey that says so (see the implementation), so a person reading a form can tell a hint from a
 * value at a glance.
 *
 * **AND "EMPTY" MEANS THE LIVE TEXT, WHICH IS WHY A SESSION MATTERS HERE.** With no session running the live text is
 * the cell's own value; while one IS running the words on screen are the EDITOR's, so it is the editor's string that
 * decides. That is what keeps the placeholder on an empty field the moment it is clicked into — Apple's behaviour,
 * and the reason this is not simply "draw it when `-cg_contentText` is nil". A field that empties WHILE being typed in
 * gets its placeholder back for the same reason, which the control makes true by redrawing itself on every edit. */
- (nullable NSString *)placeholderString;
- (void)setPlaceholderString:(nullable NSString *)string;
- (nullable NSAttributedString *)placeholderAttributedString;
- (void)setPlaceholderAttributedString:(nullable NSAttributedString *)string;

/* **AND THE GREY A PLACEHOLDER IS DRAWN IN, WHICH IS A DOOR BECAUSE A SUBCLASS MAY OWE A DIFFERENT ONE.** The era
 * publishes NO placeholder colour — Apple's `+placeholderTextColor` is a 10.10 addition — so this tier answers the
 * closest era colour it has, `+disabledControlTextColor`, and says so rather than inventing a value: a placeholder is
 * text that is NOT the field's value, which is exactly the distinction "disabled" grey already draws. */
- (NSColor *)cg_placeholderColor;

/* ---- THE FACE ---------------------------------------------------------------------------------------- */

/* **THE TWO BEZEL STYLES, WHICH ARE A FACT ABOUT THE BORDER AND NOT ABOUT THE WORDS.** Only the DRAWING reads them:
 * `-drawWithFrame:` builds its border path with `NS_CELL_BEZEL_RADIUS` for a rounded field and with zero for a square
 * one, and `NSBezierPath`'s rounded-rectangle constructor treats a zero radius as the rectangle it is (measured: the
 * zero case is a plain `CGPathAddRect` in `libagora-drawing`). The margin, the radius of anything else, and the text
 * rect are the same at either setting — a square field is the same field with its corners not cut. */
- (NSTextFieldBezelStyle)bezelStyle;
- (void)setBezelStyle:(NSTextFieldBezelStyle)style;

- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)textColor;
- (void)setTextColor:(nullable NSColor *)color;

/* **THE FILL A SUBCLASS MAY WANT TO CHANGE, AND THE REASON IT IS A DOOR RATHER THAN AN IVAR READ.** A field's face
 * is its background; a CONTROL's field — this tier's pop-up and combo box — darkens with the pointer and takes the
 * accent while it is being used, which is a fact about the CONTROL and not about the field. So the border and the
 * inset stay this class's and the FILL is asked for by name, which is what lets the combo box inherit every other
 * line of the face while answering this one. */
- (nullable NSColor *)cg_fieldFillColor;

/* ---- THE INK ---------------------------------------------------------------------------------------- */

/* **AND THE BORDER IS DRAWN HERE RATHER THAN IN EACH CALLER.** `-drawWithFrame:` fills the face and strokes the
 * border in `+controlDarkShadowColor` at `NS_CELL_BEZEL_WIDTH`, inside a path inset by half the stroke so the whole
 * border falls on the field's own edge — the same construction and the same two constants the bezel uses, because a
 * field and a button's face are noticed when their borders are a shade apart. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(nullable id)controlView;

/* **AND THE ONE PLACE A LINE'S VERTICAL CENTRE IS DECIDED.** A field, a placeholder, a table cell and a table header
 * all take their baseline from this door, so the words in a 20-point table row, the value in a combo box's field and
 * a header's title are centred by one rule — which is what makes a disclosure triangle or a chip, centred on its row,
 * point at the middle of the line rather than at its shoulders.
 *
 * It is a door rather than arithmetic repeated in each drawing method because the repetition is how the copies
 * diverged: `NSTableHeaderCell` carried one version and `NSTextFieldCell` another.
 *
 * AND THE MEASUREMENT THAT KEEPS THIS HONEST, in `tests/table_view.m`: the same row is rendered through both of the
 * directions a window uses, and its ink centre must be the cell's `NSHeight / 2` each time. With this caret both
 * read 9.5 of a 20-point cell; with a caret that always subtracts the half-difference (the y-up-only version the
 * table used to carry) the flipped render reads **2.0** — eight points high, which is the clipped row the
 * demonstration showed. A triangle centred on the row then pointed at the words' shoulders instead of their middle. */
- (CGFloat)cg_centredBaselineInFrame:(NSRect)cellFrame font:(NSFont *)font;

/* **THE RECT THE TEXT LIVES IN, WHICH IS THE FACE INSET BY THE MARGIN A FIELD OWES ITS OWN TEXT.** `NSCell`'s
 * `-drawingRectForBounds:` is the face; this adds `NS_CELL_CONTENT_GAP` — the same four points a checkbox leaves
 * before its label and a pop-up before its title, so that every control in this tier that shows words begins them the
 * same distance inside itself. (`NSText`, the VIEW, uses its own two-point inset; reconciling the view and the cell
 * is a row this slice does not open, and it is named here so the difference is known rather than found.) */
- (NSRect)drawingRectForBounds:(NSRect)theRect;

/* AND WHAT IT MEASURES: the string's own size plus the two margins and, for a subclass that draws something at its
 * right end, whatever that takes. */
- (NSSize)cellSizeForBounds:(NSRect)aRect;

/* ---- THE SESSION ------------------------------------------------------------------------------------- */

/* **AND HOW THE EDITOR IS TOLD WHAT KIND OF FIELD IT IS EDITING, WHICH IS ONE DOOR RATHER THAN A ROW OF SETTERS.**
 * Apple's `-setUpFieldEditorAttributes:` is where a cell configures the editor it was lent — the font, the alignment,
 * and the two flags about what the field MAY HOLD — and it RETURNS the editor, because a subclass may hand back a
 * DIFFERENT one. It is a door rather than a block inside the session below for that reason: a subclass wanting its own
 * editor (a secure field, a formatted cell) overrides exactly this and nothing else. */
- (NSText *)setUpFieldEditorAttributes:(NSText *)textObj;

/* **THE THREE DOORS OF AN EDIT, AND THE SPLIT BETWEEN THEM IS APPLE'S.** The cell does not make an editor and does not
 * take the keyboard: it is handed one and told to begin, which is what lets a window own a single editor and lend it
 * to whichever field is being typed into. `start` and `length` are the selection to open with, and the delegate is
 * told what happened when the session ends. */
- (void)selectWithFrame:(NSRect)aRect inView:(nullable NSView *)controlView editor:(NSText *)textObj
	       delegate:(nullable id)anObject start:(NSInteger)selStart length:(NSInteger)selLength;
- (void)editWithFrame:(NSRect)aRect inView:(nullable NSView *)controlView editor:(NSText *)textObj
	     delegate:(nullable id)anObject event:(nullable NSEvent *)theEvent;
/* AND THE SAME TWO AGAIN WITHOUT THE POINTER, which is what a keyboard or a programmatic edit wants and what
 * `-editWithFrame:...` exists to be a spelling of. */
- (void)endEditing:(nullable NSText *)textObj;

/* **AND THE TWO QUESTIONS A CONTROL ASKS ABOUT A SESSION, WHICH ARE THIS CLASS'S TO ANSWER BECAUSE THIS CLASS RUNS
 * IT.** `NSControl -currentEditor` and `-abortEditing` are forwards to these; see `NSCell.h` for why the pair is a
 * base door rather than a fact the control also keeps. `-cg_currentEditor` answers the editor WHILE ONE IS SHOWING
 * THIS CELL'S TEXT and nil otherwise, and `-cg_abortEditing` throws the session away — the same ending Escape performs,
 * with the string left as it was — answering whether there was a session to throw away. */
- (nullable NSText *)cg_currentEditor;
- (BOOL)cg_abortEditing;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTFIELDCELL_H */
