/*
 * NSTextInputClient.h — the protocol a client of the input-method system conforms to.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE SURFACE BELOW IS TRANSCRIBED FROM THE 10.6 SDK's `NSTextInputClient.h`**, which declares fifteen doors and nothing
 * else — no classes, no constants — and it is the protocol a text view conforms to when an INPUT METHOD drives it. Two
 * protocols in this tree look alike and are not: `NSTextInput` (`NSTextInput.h`) is the older, smaller one this tier's
 * view has answered all along, and `NSTextInputClient` is the one that adds the doors an input method needs to place its
 * candidate window, to ask what the composition looks like around a point, and to be told the view's window level.
 *
 * **AND THE VIEW ANSWERS IT NOW**, which is the reason this file exists: the machinery was here — a marked-text
 * composition, an input-method context, a dead-key table, a candidate window — and the CONTRACT a third-party input
 * method or a ported client declares against was not. A client that conformed to `NSTextInput` alone could not be handed
 * to a modern input method; one that conforms to this can.
 *
 * **AND TWO OF THE FIFTEEN ARE ANSWERED HONESTLY RATHER THAN FAKED**: `-drawsVerticallyForCharacterAtIndex:` is NO
 * because this layer has no vertical text at all, and `-baselineDeltaForCharacterAtIndex:` is 0 because every line here
 * sits on its baseline. Both are what a caller in this tier should be told, and both are stated where they are
 * implemented as well as here.
 */
#ifndef APPKIT_NSTEXTINPUTCLIENT_H
#define APPKIT_NSTEXTINPUTCLIENT_H

#import <Foundation/Foundation.h>

@protocol NSTextInputClient

/* THE COMPOSITION ITSELF: insert, mark, unmark, and what the client is currently holding. `-setMarkedText:` is given the
 * WHOLE composition rather than a delta, with the selection measured INSIDE it, and `replacementRange` says what of the
 * document the composition replaces (NSNotFound when it replaces nothing). */
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange;
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange;
- (void)unmarkText;
- (NSRange)selectedRange;
- (NSRange)markedRange;
- (BOOL)hasMarkedText;

/* WHAT THE DOCUMENT LOOKS LIKE, for a method that wants context: a substring for a proposed range with the range it
 * actually got, the options for marked text, and the client's whole attributed string. */
- (nullable NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range
							actualRange:(nullable NSRangePointer)actualRange;
- (NSArray *)validAttributesForMarkedText;
- (nullable NSAttributedString *)attributedString;

/* **WHERE THINGS ARE**, which is what places a candidate window: the screen rect of a character range, the character
 * under a point, how far through that character's glyph the point falls, and how far the baseline is offset. */
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(nullable NSRangePointer)actualRange;
- (NSUInteger)characterIndexForPoint:(NSPoint)point;
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point;
- (CGFloat)baselineDeltaForCharacterAtIndex:(NSUInteger)anIndex;

/* AND THE WINDOW: its level, so a candidate window can be ordered against it, and whether the text at an index is drawn
 * vertically — NO here, because this layer has no vertical text. */
- (NSInteger)windowLevel;
- (BOOL)drawsVerticallyForCharacterAtIndex:(NSUInteger)charIndex;

@end

#endif /* APPKIT_NSTEXTINPUTCLIENT_H */
