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
@class NSText;
@class NSEvent;
@class NSView;

NS_ASSUME_NONNULL_BEGIN

@interface NSTextFieldCell : NSActionCell
{
	/* THE FACE'S OWN TWO COLOURS. The background is what the field shows when it draws one, and it is WHITE by
	 * default because that is what a field is: the surface a value is written ON rather than a control's raised face.
	 * A control that wants the tier's grey — the pop-up, the combo box — overrides `-cg_fieldFillColor` rather than
	 * setting this, so that "what colour is this field" has one answer per cell instead of two that can disagree. */
	NSColor *_backgroundColor;	/* RETAINED */
	NSColor *_textColor;		/* RETAINED */
	BOOL _drawsBackground;
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

/* ---- THE FACE ---------------------------------------------------------------------------------------- */

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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTFIELDCELL_H */
