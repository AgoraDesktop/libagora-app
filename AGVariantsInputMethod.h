/*
 * AGVariantsInputMethod.h — A LETTER'S VARIANT READINGS, OFFERED AND PICKED.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS IS A CANDIDATE-BASED METHOD, WHICH IS WHAT THE DEAD-KEY ONE IS NOT.** A letter has several precomposed
 * readings — `a` is also `à á â ã ä å` — and only the person knows which one is meant, so the method HOLDS the letter
 * as marked text, offers the readings in a CANDIDATE WINDOW under the caret, and lets the arrows and Return pick. That
 * is the shape a phonetic IME has, with a letter's own variants for its table rather than a dictionary this tier
 * cannot ship: the data is the Unicode precomposed set, not an invention.
 *
 * **AND A LETTER THE METHOD DOES NOT PICK FROM IS DECLINED.** A consonant with one form, a command, a movement — all
 * fall through to the context's standard key binding, which is what makes the method safe to install. The PLAIN
 * letter is the FIRST candidate, so a person who wants no variant commits by typing the next key.
 */
#ifndef AG_VARIANTS_INPUT_METHOD_H
#define AG_VARIANTS_INPUT_METHOD_H

#import <Foundation/Foundation.h>
#import <AppKit/NSTextInputContext.h>

@class AGCandidateWindow;

NS_ASSUME_NONNULL_BEGIN

@interface AGVariantsInputMethod : NSObject <NSTextInputSource>
{
@private
	unichar _pending;		/* the base letter being picked from, or 0 */
	NSArray *_candidates;		/* RETAINED: the plain letter first, then the variants */
	NSInteger _selected;
	AGCandidateWindow *_window;	/* RETAINED; made on the first composition and reused */
}

- (BOOL)isComposing;
- (NSArray *)candidates;
- (NSInteger)selectedCandidateIndex;

/* THE WINDOW THE READINGS ARE SHOWN IN, so a caller (or a probe) can ask where it went. */
- (nullable AGCandidateWindow *)candidateWindow;

@end

NS_ASSUME_NONNULL_END

#endif /* AG_VARIANTS_INPUT_METHOD_H */
