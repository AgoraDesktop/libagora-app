/*
 * NSTextView.h — A TEXT VIEW: MANY LINES WHERE `NSText` HOLDS ONE.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THIS IS A RECONNAISSANCE AND ITS FIRST SLICE, AND THE TWO ARE ONE FILE BECAUSE THE FIRST THING A READER NEEDS IS
 * WHERE THIS CLASS IS GOING.** Apple's `NSTextView` is the top of the Cocoa text system: a DOCUMENT view over an
 * `NSTextStorage`, laid out by an `NSLayoutManager` through one or more `NSTextContainer`s, with attachments, tables
 * and rich text on top. NONE OF THAT STACK EXISTS HERE — this tier has no storage, no layout manager and no container
 * — so what this class is for now is the thing those three exist to make: MORE THAN ONE LINE.
 *
 * THE SLICES, IN THE ORDER THEY CAN BE BUILT, each one a thing a person can see:
 *
 *   I.   THE LINE MODEL, WHICH IS THIS SLICE. The string is broken at its EXPLICIT newlines, a line is drawn per
 *        line, a click lands on the line it is over, the caret sits on its own line, and the movement commands that
 *        were no-ops for a one-line field (`-moveUp:`, `-moveDown:`, the document ends) are real. A line WIDER than
 *        the view is CLIPPED — no wrapping yet, and no scrolling.
 *   II.  WRAPPING, which is a line model with a width: a logical line becomes several VISUAL lines, and the caret and
 *        the hit test have to walk a visual line rather than a logical one.
 *   III. SCROLLING, which is a clip view and a document height — and it is why slice I takes the horizontal origin
 *        away from its base rather than pretending a document scrolls sideways.
 *   IV.  RICH TEXT, ATTACHMENTS AND PARAGRAPHS, which need the attributed store and the attribute vocabulary the
 *        `NSTextFieldAttributedStringMethods` note already names as travelling without being obeyed.
 *
 * **WHAT SLICE I DOES NOT HAVE, NAMED RATHER THAN LEFT TO BE FOUND:** wrapping, any scroll view integration, the
 * `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` trio and the door names that come with it, attachments, tables,
 * the paragraph commands, the marked-text family and the input-method half. Each is a slice above; none is stubbed.
 *
 * **AND THE ONE THING THAT IS NOT A SLICE BUT A DESIGN DECISION: A LINE IS A `\n`-TERMINATED RUN, AND NOTHING ELSE.**
 * A trailing newline therefore ends with an EMPTY last line — "a\n" is two lines — which is what a document editor
 * means by "the caret is on an empty line at the end" and what a naive split on the newline would get wrong. The two
 * `cg_` doors below are this tier's own name for the model (Apple's line doors need the layout manager), and they are
 * public because a caller laying anything out beside a text view needs the count.
 */
#ifndef APPKIT_NSTEXTVIEW_H
#define APPKIT_NSTEXTVIEW_H

#import <AppKit/NSText.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTextView : NSText

/* ---- THE LINE MODEL, WHICH IS THIS TIER'S OWN NAME FOR IT -------------------------------------------- */

/* **A LINE IS A MAXIMAL RUN OF CHARACTERS NOT CONTAINING A NEWLINE**, and the line's range EXCLUDES the newline that
 * ends it — so an edit that replaces a whole line cannot eat the break between it and the next. Bytes and indices are
 * the string's own, which is what every other door in this family counts in. */
- (NSUInteger)cg_lineCount;
- (NSUInteger)cg_lineIndexForCharacterIndex:(NSUInteger)index;
- (NSRange)cg_characterRangeOfLine:(NSUInteger)line;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTVIEW_H */
