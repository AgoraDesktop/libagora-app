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
 *   * THE FIELD'S OWN DELEGATE, `-delegate`/`-setDelegate:`, AND THE `-text…` RECEIVERS THAT WOULD RELAY TO IT.
 *     Apple's `NSTextFieldDelegate` is not one method: it inherits `NSControlTextEditingDelegate` (seven optional
 *     methods, declared in `NSControl.h`), and the notifications a delegate can watch instead are an `NSObject`
 *     category, `NSControlSubclassNotifications`, with three `controlTextDid…` doors and three published names. That
 *     is a protocol FAMILY and not a door, so it is its own unit's, and this header names it so a reader does not
 *     look for it here. **THE ACTION A CALLER WAITS FOR IS NOT PART OF THAT GAP:** `NSControl -textDidEndEditing:`
 *     already turns a committed session into this control's action, so a field with a target and an action works
 *     today.
 *   * `-bezelStyle`/`-setBezelStyle:` AND THE `NSTextFieldBezelStyle` VOCABULARY. Its two cases place a field's
 *     border square or rounded, which is a DRAWING decision the cell makes — so it belongs with the cell's
 *     `-drawWithFrame:`, which draws one rounded shape today. Shipping the vocabulary without the branch would be a
 *     door that changes a number and nothing on screen.
 *   * `-placeholderString`, `-allowsEditingTextAttributes:`, `-importsGraphics:` AND THE AFTER-10.6 CONSTRUCTORS
 *     (`+labelWithString:`, `+textFieldWithString:`, `+wrappingLabelWithString:`). The placeholders are the CELL's in
 *     the era and this cell draws none; the attributed-string category needs the attribute vocabulary to survive an
 *     edit session; and the constructors postdate 10.6.
 *   * READ-ONLY SELECTION. A field that is selectable but not editable opens a NON-editable editor in Apple, so a
 *     person can copy out of a label. This tier's cell sets its editor editable when a session begins, so the
 *     distinction has no meaning here yet; `-isSelectable` is stored and forwarded, and this is the door that would
 *     read it.
 */
#ifndef APPKIT_NSTEXTFIELD_H
#define APPKIT_NSTEXTFIELD_H

#import <AppKit/NSControl.h>

@class NSColor;
@class NSEvent;

NS_ASSUME_NONNULL_BEGIN

@interface NSTextField : NSControl

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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTFIELD_H */
