/*
 * NSTextInput.h — THE PROTOCOL AN INPUT METHOD DRIVES A TEXT VIEW THROUGH.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS THE DOOR BETWEEN A TEXT VIEW AND SOMETHING THAT COMPOSES TEXT, AND IT IS A PROTOCOL RATHER THAN A CLASS
 * BECAUSE THE OTHER SIDE IS NOT THIS TIER'S.** Apple's own header declares it in the AppKit and describes it as "the
 * interface... that text views must implement in order to work with the text input system": the input system calls
 * these eleven methods, and a view that answers them can be composed into by ANY input method — a dead-key table, an
 * IME, a handwriting pad — without knowing which. The view answers what text it has, where the caret is, what a
 * screen rectangle looks like, and it is TOLD what to insert and what is currently MARKED (the unconfirmed text a
 * composition is building, which the person can still see and edit before it is committed).
 *
 * **AND THE CALLER IS THE TIER'S OWN INPUT METHOD NOW.** `NSResponder -interpretKeyEvents:` hands each key to the
 * view's INPUT CONTEXT, and the context sends it to its input source FIRST — so the doors below are CALLED: the marked
 * text by `AGInputMethod`'s dead-key table, the candidate questions by `AGVariantsInputMethod`, which shows what it
 * offers in an `AGCandidateWindow` placed at `-firstRectForCharacterRange:`. The protocol is still what an
 * application's own method would implement.
 */
#ifndef APPKIT_NSTEXTINPUT_H
#define APPKIT_NSTEXTINPUT_H

#import <Foundation/Foundation.h>

@class NSAttributedString;

NS_ASSUME_NONNULL_BEGIN

@protocol NSTextInput <NSObject>

/* WHAT THE PERSON IS COMPOSING, AND WHERE THE CARET IS INSIDE IT. `-setMarkedText:` is called on every keystroke of a
 * composition; the string is the WHOLE marked text so far (not a delta), and `selectedRange` is measured WITHIN it.
 * A NIL OR EMPTY STRING CLEARS the marked text, which is how a composition that was abandoned is taken back. */
- (void)setMarkedText:(nullable id)string selectedRange:(NSRange)selectedRange;
- (void)unmarkText;
- (BOOL)hasMarkedText;
- (NSRange)markedRange;

/* THE CARET, WHICH EVERY TEXT VIEW ALREADY ANSWERS. */
- (NSRange)selectedRange;

/* WHAT THE INPUT METHOD MAY SET ON THE TEXT IT INSERTS. A view that supports nothing beyond plain text answers an empty
 * array; one that can show an underline answers the attribute names it understands. */
- (NSArray *)validAttributesForMarkedText;

/* THE TEXT, AND WHERE IT IS ON SCREEN — the two questions a candidate window asks: what am I composing over, and
 * where should the window go. `-firstRectForCharacterRange:` answers in SCREEN coordinates, and the rectangle is the
 * caret's own, which is why a view that can place a caret can answer it. */
- (nullable NSAttributedString *)attributedSubstringFromRange:(NSRange)range;
- (NSRect)firstRectForCharacterRange:(NSRange)range;
- (NSUInteger)characterIndexForPoint:(NSPoint)point;

/* AND THE TWO THE VIEW ALREADY ANSWERS THROUGH `NSResponder` AND ITS OWN EDIT DOOR, named here because the input
 * system calls them BY THIS PROTOCOL: confirmed text goes in through `-insertText:`, and a command the input system
 * does not handle goes back through `-doCommandBySelector:`. */
- (void)insertText:(id)string;
- (void)doCommandBySelector:(SEL)selector;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTINPUT_H */
