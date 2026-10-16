/*
 * AGInputMethod.h — THE TIER'S INPUT METHOD: A DEAD KEY COMPOSES WITH THE NEXT ONE.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS THE CLASS `NSTextInputContext.h` SAID THE TIER DID NOT HAVE.** A context sends every key to its input
 * source before the standard key binding, and a source that composes owns state ACROSS KEYSTROKES. This one is a
 * DEAD-KEY table: the keymap emits a spacing accent — `´`, `` ` ``, `^`, `~`, `¨` — and this method holds it as a
 * ONE-CHARACTER COMPOSITION, shown marked, until the next key either COMBINES with it into a single character
 * (`´` then `e` is `é`) or does not, in which case the accent stands alone and the next key is handled normally. The
 * second keystroke CONFIRMS by replacing the marked range, which is exactly what `NSTextView -insertText:` does while
 * a mark is up.
 *
 * **AND A KEY IT DOES NOT OWN IS DECLINED, WHICH IS THE CONTRACT.** `-handleEvent:context:` answers whether it
 * CONSUMED the event; a plain `a` with no accent pending answers NO, so the context's standard key binding inserts it,
 * and a Command-modified key is declined before anything else because it is the menu bar's. That is what makes a
 * source safe to install: it stands in front of the mapping and only takes what it composes.
 *
 * **WHAT THIS METHOD IS NOT IS A CANDIDATE-BASED ONE.** A dead key has ONE reading per keystroke, so there is no list
 * to choose from and no window to place; a method that offered several — a phonetic IME — would use
 * `NSTextInput -firstRectForCharacterRange:` and the candidate questions beside it, which the view already answers.
 * THAT is the piece still owed, and it is a method's, not this engine's.
 */
#ifndef APPKIT_AGINPUTMETHOD_H
#define APPKIT_AGINPUTMETHOD_H

#import <Foundation/Foundation.h>
#import <AppKit/NSTextInputContext.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGInputMethod : NSObject <NSTextInputSource>
{
	unichar _pending;	/* the dead key waiting for the next one, or 0 when nothing is composed */
}

/* **WHETHER AN ACCENT IS WAITING.** A caller that wants to know whether a composition is in flight — to move a
 * candidate window, or to decide whether Escape means something — asks this rather than reading the view's mark. */
- (BOOL)isComposing;

/* **AND THE ACCENT, FOR A CALLER THAT WANTS TO SHOW WHICH ONE.** Zero when nothing is waiting. */
- (unichar)pendingDeadKey;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_AGINPUTMETHOD_H */
