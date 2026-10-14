/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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
 * WHAT IS NOT HERE: the cell-based editors (`-currentEditor`, `-selectText:`, `-abortEditing`), which need a field
 * editor and therefore the text-input session; the formatter-driven validation and its delegate family; and any
 * `-sizeToFit` arithmetic beyond the cell's own measurement. Each is absent rather than stubbed.
 */
#ifndef APPKIT_NSCONTROL_H
#define APPKIT_NSCONTROL_H

#import <AppKit/NSView.h>
#import <AppKit/NSCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSControl : NSView
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

/* **AND THE TWO DOORS THE POINTER'S CROSSING ARRIVES BY.** Apple's `NSView` gets these from an `NSTrackingArea` — a
 * class this tier does not ship — so the WINDOW synthesises them out of the pointer's motion and the deepest view
 * under the pointer is the one that gets them. What this class does with them is TELL THE CELL, which is where the
 * answer lives: a control is a view that delegates its face to a cell, and "the pointer is over me" is a fact about
 * the face. Both forward up the responder chain, because that is what `NSResponder` says they do. */
- (void)mouseEntered:(nullable NSEvent *)event;
- (void)mouseExited:(nullable NSEvent *)event;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCONTROL_H */
