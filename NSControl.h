/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSControl.h — A VIEW WITH A CELL IN IT (stage E).
 *
 * **A CONTROL IS A VIEW THAT DELEGATES ITS FACE AND ITS VALUE TO A CELL.** That is the whole of Apple's design and
 * the reason this class is thin: the control owns the geometry a view has, the CELL owns what is drawn, what the
 * value is, whether it may be edited, and where the action goes. So `NSControl` is mostly FORWARDING — every value
 * door below asks its cell — and the two things it owns are the CELL and the tracking: the click that highlights the
 * cell, drags it, and sends its action when the button comes up inside it.
 *
 * THE TARGET/ACTION PAIR LOOKS LIKE IT IS HERE AND IS NOT. Apple declares `-target`/`-action` on `NSControl`, but
 * the STORAGE has been on `NSCell` since this tier's first cell slice, and Apple's own header says so: "the value of
 * the receiver's cell". So the doors below are FORWARDS to the cell — a second copy here would be a second place for
 * the two to disagree.
 *
 * **THE CELL-BASED EDITORS WERE THE FIRST THING THIS LIST NAMED, AND THE FIRST OF THEM HAS ARRIVED.** A window
 * lends a field editor, a field cell opens a session with it, and the two doors that ask about that session —
 * `-currentEditor` and `-abortEditing` — are declared below and answered by the cell that owns it. `-selectText:` is
 * NOT among them: Apple declares it on `NSTextField` rather than here, and it lives there now.
 *
 * **AND THE DELEGATE FAMILY IS AT THE FOOT OF THIS FILE NOW**, which is the second thing the list named: the
 * `NSControlTextEditingDelegate` protocol, the `NSControlSubclassNotifications` category an object that would rather
 * LISTEN than conform is declared on, and the three published notification names.
 *
 * **THE CONTROL IS COMPLETE FOR THE ERA, AND THE TAIL WAS MOSTLY CELL FORWARDS.** The class factory (`+cellClass` and
 * `+setCellClass:`), the one-cell selection (`-selectedCell`, `-selectedTag`, `-selectCell:`), the paint/invalidate
 * quartet (`-drawCell:`, `-drawCellInside:`, `-updateCell:`, `-updateCellInside:`), the six `-take…ValueFrom:` doors,
 * the formatter pair, `-attributedStringValue`, `-baseWritingDirection`, `-refusesFirstResponder`, the deprecated
 * `-calcSize` and floating-point format, and `-validateEditing` are real forwards or the small effects the cell
 * already supports. **A SUBCLASS THAT MAKES A SPECIFIC CELL SHOULD OVERRIDE `+cellClass`**; the base's process-wide
 * factory answers `NSCell` for every control that does not, which is Apple's own shape.
 */
#ifndef APPKIT_NSCONTROL_H
#define APPKIT_NSCONTROL_H

#import <AppKit/NSView.h>
#import <AppKit/NSCell.h>

/* **AND ONE CLASS THAT DOES NOT EXIST YET, FORWARD DECLARED BECAUSE APPLE'S PROTOCOL NAMES IT.** Two methods of
 * `NSControlTextEditingDelegate` below take an `NSTextView` — Apple's multi-line text view, which this tier has not
 * written — and the blanket rule is "match Apple, including the types its header writes". So the name is declared and
 * the two methods are DECLARED BUT NEVER ASKED: nothing here produces an `NSTextView` to hand them. See their note. */
@class NSTextView;

NS_ASSUME_NONNULL_BEGIN

@interface NSControl : NSView <NSSecureCoding>
{

	/* THE CELL IS THE ONLY THING THIS CLASS OWNS. Everything else it appears to hold — the value, the target, the
	 * action, the font, the alignment — is the cell's, and the doors below are forwards. */
	NSCell *_cell;			/* RETAINED */
	BOOL _ignoresMultiClick;
	/* **AND THE TRACKING AREA THAT MAKES THE POINTER VISIBLE TO THE CELL** — installed when the control enters a window
	 * and taken out when it leaves one (see `-viewDidMoveToWindow`), because an area with a window and no view is
	 * nothing the engine can walk. RETAINED here as well as by the view's list so the control always has the handle to
	 * remove it with; the two releases are the list's and this one's, and neither is a second owner of a second thing. */
	NSTrackingArea *_cg_hoverArea;	/* RETAINED while installed */
}

/* **THE CELL CLASS A CONTROL MAKES, WHICH IS A CLASS QUESTION RATHER THAN AN INSTANCE ONE.** The base answers `NSCell`
 * and a subclass that builds a specific cell overrides `+cellClass` (Apple's own shape). `+setCellClass:` is the
 * process-wide factory spelling Apple kept for the pre-10.0 nib machinery; it stores one class, which `+cellClass`
 * answers for every control that does not override it. */
+ (void)setCellClass:(Class)factoryId;
+ (Class)cellClass;

/* THE CELL, AND THE DOOR THAT TELLS IT WHERE IT IS DRAWN. `-setCell:` sets the cell's `-controlView` to this
 * control, which is what lets a cell ask its view to redraw when its state changes, and what `NSButtonCell`'s
 * drawing needs to find the window. A nil cell is a control that draws nothing and does nothing — a real state
 * rather than an error. */
- (nullable NSCell *)cell;
- (void)setCell:(nullable NSCell *)aCell;

/* **THE TARGET/ACTION PAIR, WHICH LIVES ON THE CELL AND IS ASKED THROUGH HERE.** Apple declares these on `NSControl`
 * and its own prose says the storage is the cell's, so these are forwards and not fields. */
- (nullable id)target;
- (void)setTarget:(nullable id)anObject;
- (nullable SEL)action;
- (void)setAction:(nullable SEL)aSelector;

/* ENABLE AND HIGHLIGHT — the cell's state, with the redisplay a VIEW owes when it changes. */
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;
- (BOOL)isHighlighted;
- (void)setHighlighted:(BOOL)flag;

/* **AND THE VALUE, IN EVERY SHAPE A CALLER ASKS FOR IT.** Each is the cell's own coercion — the cell is where the
 * formatter and the type coercion live — so the control neither parses nor formats: it forwards and redraws. */
- (nullable id)objectValue;
- (void)setObjectValue:(nullable id)obj;
- (nullable NSString *)stringValue;
- (void)setStringValue:(nullable NSString *)aString;
- (int)intValue;
- (void)setIntValue:(int)anInt;
- (NSInteger)integerValue;
- (void)setIntegerValue:(NSInteger)anInteger;
- (float)floatValue;
- (void)setFloatValue:(float)aFloat;
- (double)doubleValue;
- (void)setDoubleValue:(double)aDouble;

/* AND THE FACE'S TWO PROPERTIES A CALLER SETS ON THE CONTROL RATHER THAN THE CELL. */
- (nullable id)font;
- (void)setFont:(nullable id)font;
- (NSTextAlignment)alignment;
- (void)setAlignment:(NSTextAlignment)mode;
/* **AND THE WRITING DIRECTION, WHICH IS THE CELL'S AND NOT THE VIEW'S.** `-alignment`'s natural value is resolved by
 * this, so the pair is a forward with a redisplay like the rest. */
- (NSWritingDirection)baseWritingDirection;
- (void)setBaseWritingDirection:(NSWritingDirection)writingDirection;
/* THE ATTRIBUTED VALUE, the cell's own conversion; nil when the cell has no attributed answer. */
- (nullable NSAttributedString *)attributedStringValue;
- (void)setAttributedStringValue:(NSAttributedString *)obj;
/* THE FORMATTER THE CELL CONSULTS BEFORE ITS OWN NUMERIC COERCION, and the deprecated floating-point spelling that is
 * the cell's too. */
- (nullable NSFormatter *)formatter;
- (void)setFormatter:(nullable NSFormatter *)newFormatter;
- (void)setFloatingPointFormat:(BOOL)autoRange left:(NSInteger)leftDigits right:(NSInteger)rightDigits;

/* **AND WHETHER THE CELL SPEAKS WHILE IT IS BEING DRAGGED.** Apple puts `-isContinuous` on `NSControl` and its own
 * prose puts the flag on the cell, so this is a forward like the rest — and the tracking loop below is the door that
 * READS it, which is why it is declared here rather than only on the cell. A non-continuous control sends its action
 * once, when the button comes up inside it; a continuous one sends on the press and on every dragged point. */
- (BOOL)isContinuous;
- (void)setContinuous:(BOOL)flag;

/* THE CONTROL'S OWN TAG IS `NSView`'S — a view already answers `-tag`/`-setTag:` and a control is a view, so a
 * second field here would shadow the one a caller's `-viewWithTag:` reads. What this class adds is the multi-click
 * flag, kept because Apple declares it and a caller can set it. */
@property BOOL ignoresMultiClick;

/* **AND THE THREE DOORS THAT MAKE IT A CONTROL RATHER THAN A VIEW WITH A CELL.** `-sendAction:to:` is the one place
 * the action goes out — a nil target means the responder chain, which is the application's walk — `-performClick:`
 * is the keyboard equivalent's door, and `-sizeToFit` asks the cell how big it wants to be. */
- (BOOL)sendAction:(nullable SEL)theAction to:(nullable id)theTarget;
- (void)performClick:(nullable id)sender;
- (void)sizeToFit;
/* THE MEASUREMENT AND THE DEPRECATED CACHE DOOR. `-calcSize` asks the cell to recalculate its drawing information for
 * the control's bounds; the cell computes its size on demand in this tier, so the door reaches `-calcDrawInfo:` and
 * `-sizeToFit` remains the door that sets the frame. */
- (void)calcSize;
/* THE ACTION MASK, which is the cell's `-sendActionOn:` — the events that make a held cell speak. */
- (NSInteger)sendActionOn:(NSInteger)mask;

/* **THE ONE-CELL SELECTION FAMILY.** A control has one cell, so "the selected cell" is that cell: `-selectCell:` puts
 * it in `NSOnState`, `-selectedCell` answers it, and `-selectedTag` answers its tag (or -1 when there is no cell). */
- (nullable id)selectedCell;
- (NSInteger)selectedTag;
- (void)selectCell:(nullable NSCell *)aCell;

/* **THE FOUR DRAWING AND INVALIDATION DOORS A SUBCLASS OVERRIDES.** `-drawCell:` paints the named cell if it is this
 * control's, `-drawCellInside:` paints only its interior, and the `-update…` pair marks the control for display. */
- (void)drawCell:(nullable NSCell *)aCell;
- (void)drawCellInside:(nullable NSCell *)aCell;
- (void)updateCell:(nullable NSCell *)aCell;
- (void)updateCellInside:(nullable NSCell *)aCell;
/* THE PRE-10.3 SPELLING OF `-setNeedsDisplay:` WITH NO ARGUMENT — it means YES. */
- (void)setNeedsDisplay;

/* **THE SENDER'S VALUE, TAKEN INTO THIS CONTROL'S CELL.** Each asks the sender for that shape and writes it through the
 * control's own setter, so the redisplay and the formatter are the same as a direct set. */
- (void)takeIntValueFrom:(nullable id)sender;
- (void)takeIntegerValueFrom:(nullable id)sender;
- (void)takeFloatValueFrom:(nullable id)sender;
- (void)takeDoubleValueFrom:(nullable id)sender;
- (void)takeStringValueFrom:(nullable id)sender;
- (void)takeObjectValueFrom:(nullable id)sender;

/* **AND THE TWO DOORS THAT ASK ABOUT AN EDIT SESSION, WHICH THE CELL ANSWERS BECAUSE THE CELL OWNS IT.** A control
 * whose cell can be typed into owes a caller a way to reach the editor that is running — `-currentEditor` — and a way
 * to throw the session away without committing it — `-abortEditing`. Neither is a fact a VIEW has: a view has no
 * editor, and the string being edited is the cell's. So both are forwards, and the cell's `cg_` pair (see
 * `NSCell.h`) is what they reach. */
- (nullable NSText *)currentEditor;
- (BOOL)abortEditing;
/* **VALIDATE THE RUNNING SESSION'S TEXT INTO THE CELL.** This tier's editor is an `NSText`; the string is copied into
 * the cell through its own setter, which is what a caller about to end a session needs. It does not end the session —
 * `-abortEditing` and the editor's own ending do that. */
- (void)validateEditing;

/* **AND THE TWO DOORS THE POINTER'S CROSSING ARRIVES BY.** Apple's `NSView` gets these from an `NSTrackingArea` — a
 * class this tier does not ship — so the WINDOW synthesises them out of the pointer's motion and the deepest view
 * under the pointer is the one that gets them. What this class does with them is TELL THE CELL, which is where the
 * answer lives: a control is a view that delegates its face to a cell, and "the pointer is over me" is a fact about
 * the face. Both forward up the responder chain, because that is what `NSResponder` says they do. */
- (void)mouseEntered:(nullable NSEvent *)event;
- (void)mouseExited:(nullable NSEvent *)event;

/* **AND WHETHER THE CONTROL REFUSES THE KEYBOARD, WHICH IS THE CELL'S FLAG.** A cell that refuses the first responder
 * is a label or a non-editable control; the forward is here because Apple declares the pair in `NSKeyboardUI`. */
- (void)setRefusesFirstResponder:(BOOL)flag;
- (BOOL)refusesFirstResponder;

@end

/* ============================================================================================ *
 * AND THE THREE THINGS A CONTROL THAT EDITS TEXT PUBLISHES: A CATEGORY TO LISTEN THROUGH, A     *
 * DELEGATE PROTOCOL TO CONFORM TO, AND THE NAMES THE NOTIFICATIONS ARRIVE UNDER.                 *
 * ============================================================================================ */

/* **THE LISTENER'S HALF IS A CATEGORY ON `NSOBJECT`, WHICH IS HOW APPLE SPELLS "ANY OBJECT MAY HEAR THIS".** A
 * delegate conforms to a protocol; an object that would rather REGISTER FOR THE NOTIFICATIONS conforms to nothing at
 * all and is simply sent these three. Declaring them on `NSObject` is what makes that a real, checkable interface
 * rather than a convention — and it is why they are not protocol methods: a listener need not be the control's
 * delegate, and the delegate need not listen.
 *
 * THE OBJECT OF EVERY ONE IS THE CONTROL, because the control is what a listener registered against and what owns the
 * value; the field editor travels in the `userInfo` under the key below, because it is a DIFFERENT object from the
 * control and a listener that wants to reach the editor (to ask its selection, or to read what is half-typed) has no
 * other way to it. */
@interface NSObject (NSControlSubclassNotifications)
- (void)controlTextDidBeginEditing:(NSNotification *)obj;
- (void)controlTextDidEndEditing:(NSNotification *)obj;
- (void)controlTextDidChange:(NSNotification *)obj;
@end

/* **AND THE DELEGATE IS THE SAME THREE QUESTIONS ASKED AS METHODS, PLUS THE TWO THAT CAN REFUSE AND THE TWO THAT
 * REACH THE EDITOR'S OWN MACHINERY.** The five names below split three ways and it is worth saying which is which:
 *
 *   * THE `Should` PAIR IS ASKED AND ANSWERED. `-control:textShouldBeginEditing:` and `-control:textShouldEndEditing:`
 *     return a BOOL, and NO is honoured — a session is not opened, or is not closed, which is how a form refuses a
 *     field it will not let be edited yet. These are the two this tier calls.
 *   * THE FORMATTER TRIO (`-control:didFailToFormatString:errorDescription:`,
 *     `-control:didFailToValidatePartialString:errorDescription:`, `-control:isValidObject:`) belongs to the
 *     formatter-driven validation a cell runs when a value is written through `-setObjectValue:`. THIS TIER HAS NO
 *     SUCH PATH — no cell calls them — so they are DECLARED AND NEVER ASKED, stated here rather than left for a
 *     conformer to discover by implementing one and watching nothing happen.
 *   * THE `textView:` PAIR (`-control:textView:doCommandBySelector:` and its `completions:…` sibling) is how a delegate
 *     intercepts a key BEFORE the text system handles it, and how it offers completions. Both take an `NSTextView`,
 *     which this tier has not written, and command interception is a seam `NSText` does not have — so these two are
 *     DECLARED AND NEVER ASKED for the same reason, and the class they name is forward declared above.
 *
 * EVERY METHOD IS `@optional`, which is what a delegate that only wants to know relies on: a conformer implements the
 * one door it cares about and the control asks `-respondsToSelector:` for the rest. */
@protocol NSControlTextEditingDelegate <NSObject>
@optional
- (BOOL)control:(NSControl *)control textShouldBeginEditing:(NSText *)fieldEditor;
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor;
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(nullable NSString *)error;
- (void)control:(NSControl *)control didFailToValidatePartialString:(NSString *)string errorDescription:(nullable NSString *)error;
- (BOOL)control:(NSControl *)control isValidObject:(nullable id)obj;
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
- (nullable NSArray *)control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray *)words
	forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(nullable NSInteger *)index;
@end

/* **AND THE THREE NAMES, WHICH ARE WHAT A LISTENER REGISTERS FOR.** The value of each is the era's own string, so a
 * listener keyed to Apple's literal still finds it. **AND THE FIELD-EDITOR KEY IS THE ONE FACT THE NOTIFICATION CARRIES
 * THAT THE NOTIFICATION ITSELF CANNOT**: Apple annotates these three names with the literal `@"NSFieldEditor"` and
 * never publishes a constant for it, so this tier gives it a name for the same reason `NSTextMovementUserInfoKey` has
 * one — a key spelled as a literal at every site is a key nobody can be told they got wrong. */
extern NSString *NSControlTextDidBeginEditingNotification;
extern NSString *NSControlTextDidEndEditingNotification;
extern NSString *NSControlTextDidChangeNotification;
extern NSString *NSFieldEditorUserInfoKey;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCONTROL_H */
