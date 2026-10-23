/*
 * NSTokenField.h — THE CONTROL THAT OWNS A TOKEN CELL AND IS ITS DELEGATE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS CLASS IS ALMOST ALL FORWARDS, AND THE ONE THING IT ADDS IS A RELAY.** Apple's `NSTokenField` is an
 * `NSTextField` whose cell is an `NSTokenFieldCell`: the ten selectors the era declares are the style, the separator,
 * the completion delay and the delegate, and every one of them is the CELL's state — the view contributes a redisplay
 * and nothing else. The same shape `NSImageView` took over `NSImageCell`.
 *
 * **AND THE RELAY IS WHY THE VIEW EXISTS AT ALL.** `NSTokenFieldCell`'s delegate speaks `tokenFieldCell:`; the caller's
 * delegate speaks `tokenField:`. This class INSTALLS ITSELF as the cell's delegate and forwards each question with
 * itself as the token field argument, which is exactly how `NSComboBox` stands between its caller's data source and its
 * cell. The forwarding is not a pass-through: where the caller has no opinion the FIELD supplies the protocol's default
 * (the identity conversion, accept-the-addition, no menu, the cell's own style), so the cell never mistakes "the field
 * answered" for "the caller cares".
 *
 * **THE TWO DELEGATE TYPES OCCUPY ONE SLOT, WHICH IS APPLE'S ARRANGEMENT.** `NSTokenFieldDelegate` EXTENDS
 * `NSTextFieldDelegate`, so the session events (`control:textShouldBeginEditing:` and the four notifications) arrive at
 * the same object through the field's inherited doors; the token questions arrive through the relay above. ONE `-delegate`
 * property, two families of message.
 *
 * WHAT IS DELIBERATELY NOT HERE, EACH NAMED RATHER THAN GUESSED:
 *
 *   * NO TOKEN SELECTION AND NO TOKEN DRAG. The cell has no selected-token concept in this tier, so the standard
 *     copy/cut/paste commands move the WHOLE list (see the cell's header) and dragging a chip is not implemented.
 *   * NO COMPLETION POP-UP. The delay is the switch and the unique-completion insert is the effect; a list of offers is
 *     the cell's named missing half.
 *   * NO AFTER-10.6 SURFACE. The block-based completions, the token-field search field and the `NSTokenField` pasteboard
 *     types postdate the era and are absent for the same reason the other late constructors are.
 */
#ifndef APPKIT_NSTOKENFIELD_H
#define APPKIT_NSTOKENFIELD_H

#import <AppKit/NSTextField.h>
/* **AND THE CELL'S HEADER, BECAUSE `NSTokenStyle` LIVES THERE AND APPLE IMPORTS IT THE SAME WAY.** The import is
 * one-directional: `NSTokenFieldCell.h` imports `NSTextFieldCell.h` and never this file. */
#import <AppKit/NSTokenFieldCell.h>

@protocol NSTokenFieldDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface NSTokenField : NSTextField
{
}

/* **THE DESIGNATED INITIALISER MAKES A TOKEN CELL AND MAKES THIS FIELD ITS DELEGATE.** A token field built from
 * `NSControl -initWithFrame:` would own a plain cell and answer none of the ten selectors below; this one makes the cell
 * that owns the list, gives it the field-editing defaults a field needs (editable, selectable, bordered, bezeled), and
 * installs itself as that cell's delegate so the `tokenFieldCell:` questions become `tokenField:` questions. The frame is
 * re-measured only when the caller gave a degenerate one, the same contract `NSTextField` records. */
- (instancetype)initWithFrame:(NSRect)frameRect;

/* THE CELL CLASS THE FACTORY ANSWERS. `NSControl`'s `+cellClass` is a process-wide default; a subclass that makes a
 * specific cell names it here, which is the door a nib decoder and `+setCellClass:` consult. */
+ (Class)cellClass;

/* ---- THE DELEGATE, WHICH IS THE CALLER'S ------------------------------------------------------------ */

/* **THE TOKEN DELEGATE IS TYPED NARROWER THAN THE FIELD'S AND OCCUPIES THE SAME SLOT.** `NSTokenFieldDelegate` extends
 * `NSTextFieldDelegate`, so the session doors declared on `NSTextField` still reach the same object; setting this to nil
 * leaves the CELL its own delegate (it asks the field, the field answers every default), which is why a token field with
 * no caller delegate still tokenizes, draws and pastes. */
- (nullable id <NSTokenFieldDelegate>)delegate;
- (void)setDelegate:(nullable id <NSTokenFieldDelegate>)anObject;

/* ---- THE CELL'S FOUR PIECES OF STATE, FORWARDED ------------------------------------------------------ */

/* The style each new token gets when the delegate has no per-token opinion. Stored on the cell; the forward marks this
 * view for redisplay because a chip's shape is pixels. */
- (void)setTokenStyle:(NSTokenStyle)style;
- (NSTokenStyle)tokenStyle;

/* The separator a typed string is split on. Copied by the cell; the forward is plain storage because the set changes no
 * pixel until the next string is committed. */
- (void)setTokenizingCharacterSet:(nullable NSCharacterSet *)characterSet;
- (nullable NSCharacterSet *)tokenizingCharacterSet;
+ (NSCharacterSet *)defaultTokenizingCharacterSet;

/* The completion delay, and the switch it doubles as: negative disables the completion question, zero or positive
 * enables it. Stored and answered; no timer is made in this tier, and the cell's own header says where the question is
 * asked instead. */
- (void)setCompletionDelay:(NSTimeInterval)delay;
- (NSTimeInterval)completionDelay;
+ (NSTimeInterval)defaultCompletionDelay;

@end

/* **AND THE FIELD'S PROTOCOL, WHICH IS THE CELL'S WITH THE VIEW AS THE ARGUMENT.** Ten optional methods: the completion
 * question, the addition review, the three conversions, the pasteboard pair, the per-token menu pair and the per-token
 * style. Each one has a sender in the cell (and therefore here) — none is published prose. Apple's defaults are stated
 * per method; where a nil answer means "no opinion" the identity behaviour follows, and where it means Apple's error
 * case (`-shouldAddObjects:atIndex:`) this tier refuses the addition. */
@protocol NSTokenFieldDelegate <NSTextFieldDelegate>

@optional

/* Each element of the answer is an `NSString` or an array of `NSString`s. `substring` is the partial token and
 * `tokenIndex` its index in the list. A UNIQUE offer longer than the substring is inserted and its appended letters are
 * selected; several offers insert nothing because this tier has no list UI. */
- (nullable NSArray *)tokenField:(NSTokenField *)tokenField
	 completionsForSubstring:(NSString *)substring
		    indexOfToken:(NSInteger)tokenIndex
	     indexOfSelectedItem:(nullable NSInteger *)selectedIndex;

/* The review of an addition: the objects to add, an EMPTY array to reject them all, or nil for Apple's error case,
 * which this tier refuses. */
- (nullable NSArray *)tokenField:(NSTokenField *)tokenField
	       shouldAddObjects:(NSArray *)tokens
		       atIndex:(NSUInteger)index;

/* The three conversions; nil means "the object's own text", which is the no-delegate behaviour. */
- (nullable NSString *)tokenField:(NSTokenField *)tokenField
     displayStringForRepresentedObject:(id)representedObject;
- (nullable NSString *)tokenField:(NSTokenField *)tokenField
     editingStringForRepresentedObject:(id)representedObject;
- (nullable id)tokenField:(NSTokenField *)tokenField
     representedObjectForEditingString:(NSString *)editingString;

/* The pasteboard pair: the write door runs after the default string write (YES keeps both, NO clears the board), and the
 * read door's nil falls back to the pasteboard's string. */
- (BOOL)tokenField:(NSTokenField *)tokenField
     writeRepresentedObjects:(NSArray *)objects
	       toPasteboard:(NSPasteboard *)pboard;
- (nullable NSArray *)tokenField:(NSTokenField *)tokenField
	       readFromPasteboard:(NSPasteboard *)pboard;

/* The per-token menu: the `has` door is asked first and NO means no menu. */
- (nullable NSMenu *)tokenField:(NSTokenField *)tokenField
     menuForRepresentedObject:(id)representedObject;
- (BOOL)tokenField:(NSTokenField *)tokenField
     hasMenuForRepresentedObject:(id)representedObject;

/* The per-token style, which wins over the field's `-tokenStyle`. */
- (NSTokenStyle)tokenField:(NSTokenField *)tokenField
     styleForRepresentedObject:(id)representedObject;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTOKENFIELD_H */
