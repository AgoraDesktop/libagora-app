/*
 * NSTextField.h — THE CONTROL THAT PUTS A FIELD EDITOR OVER A FIELD CELL.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE ROW THIS CLASS CLOSES WAS NAMED BY THE CONTROL BESIDE IT.** `NSComboBox.h` says in as many words that Apple
 * builds a combo box on a text field — "which is where its editing and its string live" — and that this tier had
 * neither, so the combo box started at `NSControl` and the row was left open. The CELL closed first
 * (`NSTextFieldCell`, whose own header records the same row one level down); what was left is the VIEW: a control
 * whose cell is a field cell and whose click opens a session with the window's field editor.
 *
 * **THIS CLASS OWNS ALMOST NOTHING, AND THAT IS APPLE'S SHAPE FOR IT.** Every face and value door below is a forward
 * to the cell, exactly as `NSPopUpButton`'s are; the cell owns the string, the face, and the three doors of an edit.
 * What the VIEW contributes is the two things a cell cannot have: a coordinate space to put the editor in, and a
 * window to borrow the editor from. That is the whole of `-mouseDown:` and `-selectText:`, and it is why the class is
 * short.
 *
 * **AND A FIELD'S FIRST RESPONDER IS NOT THE FIELD.** The editor is what takes the keyboard; the window owns it, and a
 * field borrows it for the length of a session. So `-becomeFirstResponder` below does not become the responder — it
 * opens the session that does — and its answer is whether a session opened. `-acceptsFirstResponder` follows from the
 * same fact: only an editable field has a session to open, so only an editable field says yes.
 *
 * WHAT IS DELIBERATELY NOT HERE, EACH FOR ITS OWN REASON AND NAMED RATHER THAN GUESSED:
 *
 *   * `NSUserInterfaceValidations` CONFORMANCE, `-validateUserInterfaceItem:`, AND THE `-errorAction` FAMILY. Apple
 *     declares `NSTextField : NSControl <NSUserInterfaceValidations>` and keeps a separate action for a value a
 *     formatter REJECTED; this tier has neither that protocol nor a formatter-driven editing path, so both are named
 *     rather than half-declared.
 *   * THE AFTER-10.6 CONSTRUCTORS (`+labelWithString:`, `+textFieldWithString:`, `+wrappingLabelWithString:`), which
 *     postdate 10.6 and would be this tier inventing a spelling the era does not have.
 *   * READ-ONLY SELECTION. A field that is selectable but not editable opens a NON-editable editor in Apple, so a
 *     person can copy out of a label. This tier's cell sets its editor editable when a session begins, so the
 *     distinction has no meaning here yet; `-isSelectable` is stored and forwarded, and this is the door that would
 *     read it.
 */
#ifndef APPKIT_NSTEXTFIELD_H
#define APPKIT_NSTEXTFIELD_H

#import <AppKit/NSControl.h>
/* **AND THE CELL'S HEADER, WHICH IS WHERE `NSTextFieldBezelStyle` LIVES — APPLE IMPORTS IT AND SO DOES THIS.** A
 * field's bezel vocabulary is declared one class down, so the control's header has to reach it; the import is
 * one-directional (`NSTextFieldCell.h` imports `NSActionCell.h` and never this file), so it closes no cycle. */
#import <AppKit/NSTextFieldCell.h>

@class NSColor;
@class NSEvent;

/* **AND ONE PROTOCOL FORWARD DECLARED, BECAUSE THE DELEGATE'S TYPE NAMES IT BEFORE ITS OWN DECLARATION BELOW.**
 * `NSTextFieldDelegate` adds nothing to `NSControlTextEditingDelegate` and is defined at the foot of this file; Apple
 * declares it the same way, for the same reason — a header that lists a class's doors in Apple's order reaches the
 * delegate property before the protocol it names. */
@protocol NSTextFieldDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface NSTextField : NSControl <NSSecureCoding>
{
	/* **THE DELEGATE IS THE FIELD'S OWN, WHICH IS WHY IT IS HERE AND NOT ON `NSControl`.** Not every control edits text
	 * — a button has no session to be told about — so a delegate is a fact about the controls that do, and Apple keeps
	 * it on `NSTextField` for exactly that reason. NOT RETAINED, this tree's rule for every delegate: a field that
	 * retained its delegate would be an owner cycle whenever the delegate owned the field. */
	id _delegate;		/* NOT RETAINED */
}

/* **THE DESIGNATED INITIALISER IS THE INHERITED ONE, AND IT MAKES A FIELD CELL RATHER THAN A PLAIN ONE.** Apple's
 * `NSControl -initWithFrame:` makes a cell with no idea what it is; a text field needs the one that owns a face, a
 * string and a session, so this class replaces it and re-measures when the caller gave a degenerate frame — the same
 * shape `NSComboBox` and `NSPopUpButton` record one class over. A default field is EDITABLE, SELECTABLE, bordered and
 * bezeled, which is what makes it a field rather than a label. */
- (instancetype)initWithFrame:(NSRect)frameRect;

/* ---- WHAT MAY BE DONE TO IT ------------------------------------------------------------------------- */

/* **THE TWO FLAGS THAT DECIDE WHETHER A CLICK IS AN EDIT.** `-isEditable` is the one `-mouseDown:` reads: a field
 * that is not editable draws its string and ignores the pointer. `-isSelectable` is stored and forwarded for the
 * read-only case the header names as not here. Both are the cell's, because the cell is what shows the string and
 * what would be typed into. */
- (BOOL)isEditable;
- (void)setEditable:(BOOL)flag;
- (BOOL)isSelectable;
- (void)setSelectable:(BOOL)flag;

/* ---- THE FACE, WHICH IS THE CELL'S ------------------------------------------------------------------ */

/* A field's surface, and the ink on it. `-drawsBackground` and `-backgroundColor` are the field cell's own pair —
 * the surface a value is written on — and `-textColor` is how those words are drawn. The two border flags are the
 * era's `-isBezeled` and `-isBordered`; a field is both by default, which is the difference between a field and a
 * label. */
- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;
- (nullable NSColor *)textColor;
- (void)setTextColor:(nullable NSColor *)color;
- (BOOL)isBezeled;
- (void)setBezeled:(BOOL)flag;
- (BOOL)isBordered;
- (void)setBordered:(BOOL)flag;

/* **AND THE TWO BORDER SHAPES, WHICH ARE THE ONE PART OF A FIELD'S FACE A CALLER PICKS.** `NSTextFieldBezelStyle`'s
 * two cases — square and rounded — are declared in `NSTextFieldCell.h`, and this pair is the same forward as the flags
 * above. UNLIKE A BUTTON'S BEZEL, A FIELD'S CHANGES NO METRIC: the border is the same width on the same rect and only
 * the corners differ, so nothing here has to re-measure. */
- (NSTextFieldBezelStyle)bezelStyle;
- (void)setBezelStyle:(NSTextFieldBezelStyle)style;

/* ---- THE KEYBOARD, WHICH A FIELD SURRENDERS TO ITS EDITOR ------------------------------------------- */

/* **A FIELD ACCEPTS THE KEYBOARD ONLY BY OPENING A SESSION, SO THESE TWO ARE ONE DECISION.** `-acceptsFirstResponder`
 * is YES exactly while the field is editable and enabled — a label has nowhere to put a caret. `-becomeFirstResponder`
 * opens the session and answers whether one opened, because the responder the window should end up with is the EDITOR
 * and not the field. */
- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;

/* ---- THE POINTER, WHICH IS THE OTHER WAY INTO AN EDIT ------------------------------------------------ */

/* **AND THE PRESS IS WHERE A FIELD'S BEHAVIOUR LIVES, BECAUSE IT IS THE VIEW'S AND NOT THE CELL'S.** `NSControl`'s
 * press runs the button tracking loop — highlight, follow the pointer, act on the release — which is a push button's
 * gesture and not a field's. A field's press opens an EDIT SESSION instead, and it needs two things only this class
 * has: the window to borrow an editor from, and this view's bounds to give the cell the rectangle the editor shows in.
 * `-selectText:` is the same session without a pointer, which is what a keyboard focus or a programmatic edit wants.
 *
 * A FIELD THAT IS NOT EDITABLE IS A LABEL, and a press on a label does nothing: there is no session to open and the
 * tracking loop is the wrong gesture for any field. */
- (void)mouseDown:(nullable NSEvent *)event;
- (void)selectText:(nullable id)sender;

/* ---- THE DELEGATE, WHICH IS TOLD ABOUT EVERY SESSION AND MAY REFUSE TWO OF THEM --------------------- */

/* **THE DELEGATE IS TYPED, AND THE FIVE RECEIVERS BELOW ARE THE `NSText` PROTOCOL'S — ONE CABLED THROUGH THIS
 * CONTROL.** The editor's delegate is the CELL (it owns the string and reads it back); the cell reports every
 * session event through THIS control, because a caller set a TARGET on the control and writes its handler against the
 * control. So these five are what the cell calls, and they are Apple's own five doors on this class — which is the
 * reason they are declared rather than kept private: a subclass that wants to watch the session overrides them. */
- (nullable id <NSTextFieldDelegate>)delegate;
- (void)setDelegate:(nullable id <NSTextFieldDelegate>)anObject;
- (BOOL)textShouldBeginEditing:(NSText *)textObject;
- (BOOL)textShouldEndEditing:(NSText *)textObject;
- (void)textDidBeginEditing:(NSNotification *)notification;
- (void)textDidEndEditing:(NSNotification *)notification;
- (void)textDidChange:(NSNotification *)notification;

/* **THE DEPRECATED MNEMONIC DOOR, WHICH IS REAL BECAUSE ITS RULE IS SIMPLE.** Apple deprecated it in 10.0 (use
 * `-setStringValue:`), and its behaviour is not a stub: the marker is `&`, a doubled `&&` is one literal ampersand, and a
 * single one introduces the mnemonic character and is REMOVED from the title. Since this tier has no keyboard-mnemonic
 * machinery, the visible half is the whole of it. */
- (void)setTitleWithMnemonic:(nullable NSString *)title;

@end

/* **AND THE TWO FLAGS ABOUT WHAT THIS FIELD MAY HOLD, IN THE CATEGORY APPLE PUTS THEM IN.**
 * `-allowsEditingTextAttributes:` says whether a person may change the text's ATTRIBUTES while editing, and
 * `-importsGraphics:` whether an image may be dropped into it; both are the CELL's (its rows, not this class's) and
 * both are FORWARDS, like every other face and value door here. **THEY ARE ALSO THE PART THAT WAS NOT WIRED:** a cell
 * has carried them since the cell family's first slice and the field EDITOR has carried `-isRichText` and
 * `-isImportsGraphics` since the text view's, and nothing connected the two — so a caller could set a field rich and
 * get a plain editor. `-setUpFieldEditorAttributes:` copies them now, and what still does not happen is named at that
 * door rather than implied here: the tier has no RTF reader, no attachment drawing and no paragraph model, so the
 * flags travel and nothing obeys them yet. */
@interface NSTextField (NSTextFieldAttributedStringMethods)
- (BOOL)allowsEditingTextAttributes;
- (void)setAllowsEditingTextAttributes:(BOOL)flag;
- (BOOL)importsGraphics;
- (void)setImportsGraphics:(BOOL)flag;
@end

/* **AND THE PROTOCOL ITSELF, WHICH IS EMPTY, AND THAT IS APPLE'S OWN SHAPE.** `NSTextFieldDelegate` adds nothing to
 * `NSControlTextEditingDelegate` — Apple's declaration is literally `<NSControlTextEditingDelegate> @end` — and the
 * empty sub-protocol is the point: a caller writing `id <NSTextFieldDelegate>` says "a delegate for a TEXT FIELD",
 * which is a narrower and truer statement than re-listing seven methods that already exist one header over. It is
 * declared HERE because Apple declares it here, which is the rule the whole tree follows. */
@protocol NSTextFieldDelegate <NSControlTextEditingDelegate>

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTFIELD_H */
