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
 *        means the view DRAWS RUNS rather than one style — a foreground colour, a background colour, the two rules and
 *        an attachment's cell are the manager's — and the PARAGRAPH STYLE's alignment, line-break mode and geometry
 *        are the layout's. What is left is a table's flow across containers; an
 *        attachment's inline flow is HERE — the manager reserves a box of the cell's width and shifts the text after
 *        it.
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
 * **THE GRID IS WHOLE HERE, FLOW INCLUDED:** the manager measures the columns, lays each cell inside them and places
 * them side by side, `-collapsesBorders` draws an edge two cells share ONCE, and a table that does not fit a container
 * goes on in the NEXT one at a row boundary. The
 * `NSTextInput` PROTOCOL is here (`NSTextInput.h`),
 * this view ANSWERS it, and the INPUT CONTEXT that owns a composition is here too (`NSTextInputContext.h`) — AND SO IS
 * AN INPUT METHOD: `AGInputMethod` is a dead-key table the context sends each key to FIRST, which composes the accent
 * and the next letter through these very doors, and a key it does not own reaches the standard key binding. ATTACHMENTS are drawn (`NSTextAttachment.h`, and the manager's run walk
 * draws the cell), and their INLINE ADVANCE IS THE ENGINE'S NOW: a `CTRunDelegate` over the attachment character makes
 * Core Text reserve the box, so the text after an attachment flows PAST it rather than over it. A PRESSED ATTACHMENT
 * IS TRACKED HERE TOO: `-mouseDown:` hit-tests the box and hands the cell the DOWN, `-mouseDragged:` and `-mouseUp:`
 * hand it every remaining event, and the cell's `-trackMouse:…` is asked once per event — the view owns the stream, so
 * the modal loop `NSCell` refuses is never built. The view's own
 * `NSText`-inherited `_string` is a mirror (see above) rather than the authority.
 */
#ifndef APPKIT_NSTEXTVIEW_H
#define APPKIT_NSTEXTVIEW_H

#import <AppKit/NSText.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextInputClient.h>

@class NSTextStorage;
@class NSLayoutManager;
@class NSTextContainer;

NS_ASSUME_NONNULL_BEGIN

@interface NSTextView : NSText <NSTextInput, NSTextInputClient>
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
	/* **AND THE ATTACHMENT CELL THE POINTER IS TRACKING, IF ANY.** The view OWNS THE SESSION rather than borrowing a
	 * modal loop from the cell (see `NSTextAttachment.h`), so the cell, the character it stands for and the frame it
	 * occupied are remembered between the press and the release. THE CELL IS RETAINED FOR THE SESSION: an edit during
	 * the drag could take the attachment out of the store, and a borrowed pointer to ink that no longer exists is the
	 * one thing a drag must not keep. `nil` means no session, which is the state of every view between gestures. */
	id _cg_trackingCell;		/* RETAINED while a session is in flight, else nil */
	NSUInteger _cg_trackingIndex;
	NSRect _cg_trackingFrame;
	/* ============================================================================================
	 * THE SPELLING FLAGS. Five bits and two pieces of per-document state, which is all the view owns: the CHECKING is
	 * `NSSpellChecker`'s and the underlining is the layout manager's, so what lives here is what the user toggled.
	 *
	 * **ALL FIVE DEFAULT TO NO, WHICH IS A STATED DEVIATION FROM APPLE**, whose smart quotes and dashes start ON. This
	 * tier sets them in no initialiser because the view has none to set them in yet, and a default that depends on
	 * code that does not run is worse than one that is written down.
	 * ========================================================================================== */
	BOOL _continuousSpellChecking;
	BOOL _grammarChecking;
	BOOL _automaticSpellingCorrection;
	BOOL _automaticQuoteSubstitution;
	BOOL _automaticDashSubstitution;
	/* THE DOCUMENT TAG, allocated once and reused: a second tag would make the checker forget what the user ignored. */
	NSInteger _spellCheckerDocumentTag;
	/* WHERE THE VIEW WAS TOLD A RANGE IS MISSPELLED. Apple draws a squiggle from this; this tier RECORDS it, and the
	 * drawing is the layout manager's next slice — stated here rather than implied, because a setter that silently
	 * drops its argument is the shape a stub takes. */
	NSMutableDictionary *_spellingState;


}

/* ==================================================================================================================
 * SPELLING AND SUBSTITUTION — the eighteen doors that reach `NSSpellChecker`.
 *
 * **THE FLAGS ARE THE VIEW'S; THE WORK IS NOT.** Each pair stores a bit and the toggle flips it, which is exactly what
 * Apple's view does — the checking itself is the checker's and the underline is the layout manager's, so a view that
 * owned the algorithm would be a second implementation of it.
 *
 * `-setSpellingState:range:` IS RECORDED AND NOT DRAWN. Apple's names a range and a state and the view underlines it
 * in its own drawing pass; this tier records the pair in `_spellingState` so the call is not lost, and the drawing is
 * the slice that makes the layout manager paint it. Saying so here is the difference between a documented gap and a
 * stub that looks implemented.
 * ================================================================================================================ */

- (BOOL)isContinuousSpellCheckingEnabled;
- (void)setContinuousSpellCheckingEnabled:(BOOL)flag;
- (void)toggleContinuousSpellChecking:(nullable id)sender;

- (BOOL)isGrammarCheckingEnabled;
- (void)setGrammarCheckingEnabled:(BOOL)flag;
- (void)toggleGrammarChecking:(nullable id)sender;

- (BOOL)isAutomaticSpellingCorrectionEnabled;
- (void)setAutomaticSpellingCorrectionEnabled:(BOOL)flag;
- (void)toggleAutomaticSpellingCorrection:(nullable id)sender;

- (BOOL)isAutomaticQuoteSubstitutionEnabled;
- (void)setAutomaticQuoteSubstitutionEnabled:(BOOL)flag;
- (void)toggleAutomaticQuoteSubstitution:(nullable id)sender;

- (BOOL)isAutomaticDashSubstitutionEnabled;
- (void)setAutomaticDashSubstitutionEnabled:(BOOL)flag;
- (void)toggleAutomaticDashSubstitution:(nullable id)sender;

/* The state a caller marks a range with, and the tag this view's spell document carries. */
- (void)setSpellingState:(NSInteger)value range:(NSRange)charRange;
- (NSInteger)spellCheckerDocumentTag;

/* THE SUBSTITUTIONS PANEL IS A PANEL THIS TIER HAS NOT BUILT, so the door says so instead of doing nothing. */
- (void)orderFrontSubstitutionsPanel:(nullable id)sender;

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
