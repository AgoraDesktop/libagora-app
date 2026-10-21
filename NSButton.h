/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSButton.h — A CONTROL WHOSE CELL IS A BUTTON CELL (stage E).
 *
 * **THIS CLASS IS ALMOST ENTIRELY FORWARDING, AND THAT IS APPLE'S DESIGN RATHER THAN A THIN SLICE.** A button's
 * title, its state, its button type, its bezel, its key equivalent and its image all live on `NSButtonCell`; the
 * button is the VIEW that gives the cell a rectangle to be drawn in and a click to act on. So every door below is a
 * forward, and the two things this class decides are the CELL IT MAKES — a bordered, bezeled `NSButtonCell` — and
 * nothing else.
 *
 * THE ERA'S DESIGNATED INITIALISER IS `-initWithFrame:`, and a caller sets the title, the target and the action on
 * the button it just made. There is no `+buttonWithTitle:target:action:` here because that convenience is ten years
 * out of this tree's pinned vintage, and a constructor from a later era would be a door the era's own header does not
 * declare.
 */
#ifndef APPKIT_NSBUTTON_H
#define APPKIT_NSBUTTON_H

#import <AppKit/NSControl.h>
#import <AppKit/NSButtonCell.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSButton : NSControl <NSSecureCoding>
{
	/* THE ONE PIECE OF STATE THE COMPLETING SLICE ADDS, and the only one a BUTTON owns rather than its cell: whether
	 * the button SPRINGS OPEN its menu while the pointer rests on it, which is a property of the view's behaviour and
	 * not of the face the cell draws. */
	BOOL _springLoaded;
}

- (instancetype)initWithFrame:(NSRect)frameRect;

/* THE TITLE AND THE ALTERNATE TITLE, both the cell's: the second is what the button shows WHILE IT IS PRESSED, which
 * is how a button says "this is happening" without changing its face. */
- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)aTitle;
- (nullable NSString *)alternateTitle;
- (void)setAlternateTitle:(nullable NSString *)aTitle;

/* **THE STATE, WHICH IS WHAT A CHECKBOX AND A RADIO USE AND WHAT A PUSH BUTTON IGNORES.** `NSOnState`/`NSOffState`
 * (and `NSMixedState`) are declared with `NSCell`; a toggle button's face shows the state and a momentary button's
 * does not, which is a property of the button TYPE rather than of the state. */
- (NSInteger)state;
- (void)setState:(NSInteger)value;
- (void)setAllowsMixedState:(BOOL)flag;
- (BOOL)allowsMixedState;

/* WHAT KIND OF BUTTON IT IS AND HOW ITS FACE IS BUILT — the cell's two enums, forwarded. */
- (NSButtonType)buttonType;
- (void)setButtonType:(NSButtonType)aType;
- (NSBezelStyle)bezelStyle;
- (void)setBezelStyle:(NSBezelStyle)style;

/* THE KEY EQUIVALENT, which is a cell's, and the image, which is too. */
- (nullable NSString *)keyEquivalent;
- (void)setKeyEquivalent:(nullable NSString *)aKeyEquivalent;
- (nullable id)image;
- (void)setImage:(nullable id)anImage;
- (NSCellImagePosition)imagePosition;
- (void)setImagePosition:(NSCellImagePosition)aPosition;

/* **THE TWO ATTRIBUTED TITLES, WHICH WIN OVER THE PLAIN ONES, AND THE PICTURE THAT REPLACES THE OTHER ONE ON A
 * PRESS.** All four are the cell's; the button forwards them, and `imageScaling` is how a picture meets the rectangle
 * the cell gives it. */
- (nullable NSAttributedString *)attributedTitle;
- (void)setAttributedTitle:(nullable NSAttributedString *)aTitle;
- (nullable NSAttributedString *)attributedAlternateTitle;
- (void)setAttributedAlternateTitle:(nullable NSAttributedString *)aTitle;
- (nullable NSImage *)alternateImage;
- (void)setAlternateImage:(nullable NSImage *)anImage;
- (NSImageScaling)imageScaling;
- (void)setImageScaling:(NSImageScaling)scaling;

/* THE KEY EQUIVALENT'S MASK, AND THE PERIODIC PAIR A REPEATING BUTTON USES. */
- (NSUInteger)keyEquivalentModifierMask;
- (void)setKeyEquivalentModifierMask:(NSUInteger)mask;
- (void)setPeriodicDelay:(float)delay interval:(float)interval;
- (void)getPeriodicDelay:(nullable float *)delay interval:(nullable float *)interval;

/* **AND THE STATE WALK, WHICH IS THE CELL'S RULE FORWARDED** — off → on → (mixed if allowed) → off. */
- (void)setNextState;

/* **AND THE THREE DOORS THAT ARE THE BUTTON'S OWN RATHER THAN THE CELL'S.** A mnemonic is the CELL's rule (the index
 * is into the cell's title) and is forwarded; spring-loading is the VIEW's state, kept here; and the accelerator
 * level is stored on the cell because a multi-level accelerator button's face is what reads it. */
- (void)setTitleWithMnemonic:(nullable NSString *)titleWithMnemonic;
- (BOOL)isSpringLoaded;
- (void)setSpringLoaded:(BOOL)flag;
- (void)setMaxAcceleratorLevel:(NSInteger)level;

/* **AND THE PRESS, WHICH IS A VIEW'S STATE RATHER THAN THE CELL'S.** `-highlight:` is Apple's door on the BUTTON
 * (the same one the control's tracking uses), and it forwards to the cell and redraws — which is what makes a button
 * drawn under the pointer go dark for as long as it is held. */
- (void)highlight:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBUTTON_H */
