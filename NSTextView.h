/*
 * NSTextView.h — A TEXT VIEW: THE MODEL, AND THE LAYOUT THAT WRAPS IT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **APPLE'S `NSTextView` IS THE TOP OF A STACK THIS TIER HAS NOT GOT** — an `NSTextStorage`, an `NSLayoutManager` and
 * an `NSTextContainer`, with attachments and rich text on top — so this class is built in slices, each one a thing a
 * person can see:
 *
 *   I.   THE LINE MODEL (shipped). The string is broken at its EXPLICIT newlines; a line is drawn per line; a click
 *        lands on the line it is over; the caret sits on its own line; and the movement a one-line field had no
 *        answer for (`-moveUp:`, `-moveDown:`, the document ends) is real.
 *   II.  WRAPPING (shipped). The model gains a WIDTH: a line too wide for the view becomes several VISUAL LINES,
 *        and the caret, the hit test, the selection and every movement walk those instead.
 *   III. SCROLLING AND THE DOCUMENT'S ORIENTATION (shipped). The view is FLIPPED, so its FIRST line sits at the clip
 *        view's origin and the origin grows as a reader moves DOWN; the view settles its own height so there is
 *        something to scroll.
 *   IV.  RICH TEXT, ATTACHMENTS AND PARAGRAPHS (IN PROGRESS). The store, the region and the manager are here, and
 *        **THE VIEW NOW READS THE STORE THROUGH THE MANAGER**: the view owns an `NSTextStorage`, an `NSLayoutManager`
 *        and an `NSTextContainer`, `-string` is the STORE's string, every edit goes through the store, and the layout
 *        the view asks for — a visual line's range, a caret's x, a point's index, the ink — is the MANAGER's. THIS IS
 *        WHAT RETIRED THE VIEW'S OWN LAYOUT: the `malloc`'d visual array, the typesetter walk and the per-line
 *        `CTLine` are GONE from this class, and the one copy of that arithmetic is in `NSLayoutManager`. It also
 *        means the view DRAWS RUNS rather than one style — a foreground colour, a background colour and an underline
 *        are the manager's to paint. What is left is attachments, tables, the paragraph model, the marked-text family
 *        and the input-method half.
 *
 * **AND THE MIRROR IS HOW THE BASE CLASS STILL WORKS.** `NSText` holds a `NSMutableString` and its movement and word
 * commands read it directly; so the view keeps that string as a MIRROR of the store, refreshed by the store's own
 * `NSTextStorageDidProcessEditingNotification`, and the base's arithmetic keeps working while the STORE is what a
 * caller reads and writes. THE TWO CANNOT DISAGREE for longer than one synchronous notification, which is what makes
 * the mirror safe rather than a second source of truth.
 *
 * **AND THE FLIP IS WHY THE LAYOUT BELOW IS y-DOWN.** A flipped view measures y from the TOP — that is what flipping
 * MEANS — so a band is drawn ABOVE its baseline. THE ONE PLACE IT SHOWS is the text: Core Text's own coordinates run
 * UP from the baseline, and the MANAGER is what applies the translate-and-mirror now. The base, `NSText`, is a y-up
 * single-line field and is left one.
 *
 * **THE TWO UNITS ARE NOT THE SAME THING AND BOTH KEEP THEIR OWN NAME.** A MODEL LINE — a paragraph, in Apple's
 * vocabulary — is a `\n`-terminated run, and the three `cg_…OfLine:` doors below are that model: they are facts about
 * the STRING and do not change when the view is resized. A VISUAL LINE is one line as LAID OUT at the view's width,
 * and there can be several per model line; the `cg_visualLine…` doors read the MANAGER, and they change every time
 * the text or the width does. A caller that wants "how many lines" has to say which.
 *
 * **WHAT IS STILL NOT HERE, NAMED RATHER THAN STUBBED:** attachments, tables, the paragraph commands (the
 * `-alignLeft:` family, as opposed to the `-setAlignment:` that moves the glyphs), and the INPUT CONTEXT — the class
 * that owns a composition across keystrokes and arranges a candidate window. The `NSTextInput` PROTOCOL is here and
 * this view ANSWERS it (`NSTextInput.h`), so a caller can drive a composition by hand; what no class in this tier does
 * yet is call those doors itself. The view's own `NSText`-inherited `_string` is a mirror (see above) rather than the
 * authority.
 */
#ifndef APPKIT_NSTEXTVIEW_H
#define APPKIT_NSTEXTVIEW_H

#import <AppKit/NSText.h>
#import <AppKit/NSTextInput.h>

@class NSTextStorage;
@class NSLayoutManager;
@class NSTextContainer;

NS_ASSUME_NONNULL_BEGIN

@interface NSTextView : NSText <NSTextInput>
{
	/* **THE TRIO, AND THE VIEW OWNS THE FIRST TWO.** The store is RETAINED here and it retains the MANAGER (its own
	 * list does); the manager retains the CONTAINER (its array does) and the container holds a BORROWED pointer back
	 * to this view — one `-setTextStorage:` and one `-addTextContainer:` build that web in `-initWithFrame:`, and the
	 * view's `_string` is a mirror the store's edits refresh. */
	NSTextStorage *_cg_textStorage;		/* RETAINED */
	NSLayoutManager *_cg_layoutManager;	/* RETAINED (the store also retains it) */
	NSTextContainer *_cg_textContainer;	/* RETAINED (the manager also retains it) */
	/* **AND WHETHER THIS VIEW IS TALL ENOUGH FOR ITS OWN LAYOUT.** Apple's default for a text view is YES — one inside
	 * a scroll view grows and shrinks with its text — and a caller that gave the view a frame on purpose says NO. */
	BOOL _cg_verticallyResizable;
	/* **AND THE MARKED TEXT, WHICH IS THE UNCONFIRMED HALF OF A COMPOSITION.** It is a RANGE IN THE STORE — the marked
	 * characters are really there, so the caret, the layout and an edit all work as usual — and it is remembered here
	 * because the STORE cannot say which of its runs are still being composed. `NSNotFound` means nothing is marked,
	 * which is the state of every view no input method has touched. */
	NSRange _cg_markedRange;
}

/* ---- THE TRIO, WHICH A CALLER REACHES TO PUT RUNS IN ------------------------------------------------ */

/* **THE STORE IS WHERE A CALLER PUTS ATTRIBUTES, AND THIS IS HOW THEY REACH IT.** The manager and the container are
 * named too, because Apple's `NSTextView` names them and because a caller that wants a second container has to be
 * able to reach the manager. */
- (NSTextStorage *)textStorage;
- (void)setTextStorage:(NSTextStorage *)storage;
- (nullable NSLayoutManager *)layoutManager;
- (nullable NSTextContainer *)textContainer;

/* ---- THE MODEL: A LINE IS A `\n`-TERMINATED RUN, AND NONE OF THIS DEPENDS ON THE VIEW'S WIDTH ---------------- */

- (NSUInteger)cg_lineCount;
- (NSUInteger)cg_lineIndexForCharacterIndex:(NSUInteger)index;
- (NSRange)cg_characterRangeOfLine:(NSUInteger)line;

/* ---- THE LAYOUT: THE SAME MODEL AT THE VIEW'S WIDTH, WRAPPED ------------------------------------------------- */

/* **AND A VISUAL LINE'S RANGE INCLUDES THE SPACE OR NEWLINE IT ENDED ON**, which is the engine's own convention (a
 * line's trailing whitespace is part of it) — so the range a caller gets back is the range the BREAKER decided on,
 * not one this class trimmed. A caller drawing an index within a line asks Core Text, and the caret at the END of a
 * line is at the end of that range. */
- (NSUInteger)cg_visualLineCount;
- (NSRange)cg_visualLineRangeAtIndex:(NSUInteger)line;
- (NSUInteger)cg_visualLineIndexForCharacterIndex:(NSUInteger)index;

/* ---- AND WHO OWNS THE HEIGHT --------------------------------------------------------------------------------- */

/* **A VERTICALLY RESIZABLE TEXT VIEW IS AS TALL AS ITS LAYOUT.** That is the default, because a document inside a
 * scroll view has to be as tall as its text for the scroll view to have anything to scroll; a caller that gave the
 * view a frame — a field, a label laid out by hand — sets NO and keeps the frame it chose. The height is settled
 * after every edit and after a width change, because both RE-WRAP; `-sizeToFit` fits regardless, being an explicit
 * request rather than an automatic one. */
- (BOOL)isVerticallyResizable;
- (void)setVerticallyResizable:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTVIEW_H */
