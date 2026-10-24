/*
 * NSTextView.h — A TEXT VIEW: THE MODEL, AND THE LAYOUT THAT WRAPS IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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

@class NSParagraphStyle;
@class NSTextStorage;
@class NSLayoutManager;
@class NSTextContainer;
@class NSRulerView;
@class NSRulerMarker;
@class NSEvent;
@class NSColor;

NS_ASSUME_NONNULL_BEGIN

/* **THE ERA'S TWO SELECTION ENUMS.** Apple declares them in this header and not in Foundation, and their values are
 * the header's own: an affinity is which end of a selection the caret is at (upstream is the start), and a granularity
 * is the unit a selection prefers — the character, the word, the paragraph or the whole document. */
/* **THE LINK ATTRIBUTE IS FOUNDATION'S HERE** (`NSLinkAttributeName`, in `Foundation/NSAttributedString.h`), so this
 * header does not declare it a second time: the value is an `NSURL` (or a string this tier can make one from),
 * `-linkTextAttributes` is the ink such a run is drawn in, and `-clickedOnLink:atIndex:` is what a press on it sends. */

typedef NSInteger NSTextSelectionAffinity;
enum {
	NSTextSelectionAffinityUpstream = 0,
	NSTextSelectionAffinityDownstream = 1
};

typedef NSInteger NSTextSelectionGranularity;
enum {
	NSTextSelectionGranularityCharacter = 0,
	NSTextSelectionGranularityWord = 1,
	NSTextSelectionGranularityParagraph = 2,
	NSTextSelectionGranularityDocument = 3
};

@interface NSTextView : NSText <NSTextInput, NSTextInputClient>
{
	/* **THE TRIO, AND THE VIEW OWNS THE FIRST TWO.** The store is RETAINED here and it retains the MANAGER (its own
	 * list does); the manager retains the CONTAINER (its array does) and the container holds a BORROWED pointer back
	 * to this view — one `-setTextStorage:` and one `-addTextContainer:` build that web in `-initWithFrame:`, and the
	 * view's `_string` is a mirror the store's edits refresh. */
	NSTextStorage *_cg_textStorage;		/* RETAINED */
	NSLayoutManager *_cg_layoutManager;	/* RETAINED (the store also retains it) */
	NSTextContainer *_cg_textContainer;	/* RETAINED (the manager also retains it) */
	/* **THE MARGIN AROUND THE CONTAINER, AND WHERE THE CONTAINER'S ORIGIN THEREFORE SITS.** These are two facts and one
	 * of them is derived: the inset is the caller's and the origin is the point the container's (0,0) occupies in this
	 * VIEW's coordinates, which in a flipped view is the inset itself. The origin is CACHED rather than recomputed so
	 * that `-invalidateTextContainerOrigin` has something to invalidate — see that door's note. */
	NSSize _cg_textContainerInset;		/* the view's margin around the container, in points */
	NSPoint _cg_textContainerOrigin;		/* CACHED: the container's origin in this view's coordinates */
	BOOL _cg_originValid;
	/* **AND THE COLOUR THE CARET IS DRAWN IN.** `nil` answers the control text colour, which is Apple's default for a
	 * programmatically made view; a caller that sets one gets it read where the caret is filled. */
	NSColor *_cg_insertionPointColor;	/* RETAINED, or nil for the control text colour */
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
	/* **AND WHETHER THIS VIEW WANTS A RULER AT ALL.** Apple's default is YES for a text view — the line is there for
	 * the asking — and NO here would mean the view has none to show, which is a different fact from `-isRulerVisible`
	 * (whether the scroll view is showing the one it has). */
	BOOL _usesRuler;

	/* ============================================================================================
	 * THE FIND STATE. The panel is absent, so what a view owns is the SEARCH STRING and the indicator —
	 * the two things the era's `performFindPanelAction:` actually needed once the panel had handed it over.
	 * ========================================================================================== */
	BOOL _usesFindPanel;
	NSString *_cg_findString;	/* RETAINED: the last string searched for, set by action 7 or by a caller */
	NSRange _cg_findIndicatorRange;	/* where the find indicator was asked to show */
	BOOL _cg_findIndicatorActive;	/* YES until the next draw, which is how long the era's flash lasts */

	/* ============================================================================================
	 * THE SELECTION'S SHAPE AND THE ATTRIBUTES THE VIEW CARRIES.
	 *
	 * **THE RANGES ARE AN ARRAY ONLY WHEN THERE IS MORE THAN ONE.** `NSText`'s `_selectedRange` is the authority for a
	 * single selection — every inherited door reads it — so a multi-range selection is the array, and the FIRST range
	 * is also mirrored into `_selectedRange` so that "the selection" and "the ranges" cannot disagree about where the
	 * caret's document position is. Clearing the array returns the view to the single-selection shape.
	 * ========================================================================================== */
	NSMutableArray *_cg_selectedRanges;	/* RETAINED: NSValue ranges, or nil for "the one in _selectedRange" */
	NSTextSelectionAffinity _cg_selectionAffinity;
	NSTextSelectionGranularity _cg_selectionGranularity;
	/* THE ATTRIBUTES THE VIEW CARRIES RATHER THAN THE STORE: what new text gets, and what the three decorative runs
	 * wear. Each is RETAINED (a copy) and each has a reader — `-typingAttributes` falls back to the default paragraph
	 * style, `-insertText:` applies the typing attributes to the run it inserts, the marked run wears the marked
	 * attributes, and the selection's own ink comes from the selected attributes. */
	NSDictionary *_cg_typingAttributes;		/* RETAINED (a copy), or nil for "the insertion point's" */
	NSParagraphStyle *_cg_defaultParagraphStyle;	/* RETAINED, or nil for the class's default */
	NSDictionary *_cg_selectedTextAttributes;	/* RETAINED (a copy), or nil for the accent */
	NSDictionary *_cg_markedTextAttributes;		/* RETAINED (a copy), or nil for a single underline */
	/* AND THE TWO FLAGS THE ATTRIBUTE COMMANDS READ: whether `-changeAttributes:` may open the font panel, and whether
	 * `-updateFontPanel` has one to talk to. Apple's defaults are both YES. */
	BOOL _cg_usesFontPanel;
	/* **THE FONT PANEL AND COLOUR PANEL TARGETS.** `-changeAttributes:` and `-changeColor:` install this view as the
	 * panel's target with these actions, so a person's next choice lands on the selection rather than nowhere. */
	BOOL _cg_panelTargetInstalled;

	/* **AND WHETHER A PASTE MAY CARRY A PICTURE.** Apple's default is NO: an RTFD paste with attachments is accepted only
	 * by a view that allows editing images, and this flag is read where the paste is decoded rather than stored for a
	 * later slice. */
	BOOL _cg_allowsImageEditing;
	/* **AND THE STATE THE LAST THIRTY-NINE DOORS NEED** — the document-background permission a colour panel asks, the ink
	 * a link run is drawn in, and the locale list (stored, with a setter that says nothing reads it). */
	BOOL _cg_documentBackgroundChange;
	NSDictionary *_cg_linkTextAttributes;	/* RETAINED (a copy), or nil for the platform's link ink */
	NSArray *_cg_allowedInputLocales;	/* RETAINED (a copy), or nil */
	/* ============================================================================================
	 * WHAT TYPING DOES AROUND IT: THE SMART-INSERT FLAG, THE UNDO FLAG, AND WHERE THE LAST EDIT ENDED.
	 *
	 * **BOTH FLAGS DEFAULT TO NO, WHICH IS APPLE'S DEFAULT FOR A PROGRAMMATICALLY MADE VIEW** (a text view in a
	 * document gets YES from the document, and one in a nib from the nib). Stated because this tree has been here
	 * before: a flag whose default silently differs from the era is a difference a bookmark has to find.
	 *
	 * **`_cg_lastEditEnd` IS HOW COALESCING IS DECIDED.** Apple's text view relies on the undo manager's event-driven
	 * grouping to know where a typing run ends; this Foundation's manager has no event grouping, so the view keeps the
	 * one fact that answers the same question — WHERE THE PREVIOUS EDIT FINISHED — and an edit that is not adjacent to it
	 * closes the open group. `NSNotFound` means "no run in progress".
	 * ========================================================================================== */
	BOOL _cg_smartInsertDelete;
	BOOL _cg_allowsUndo;
	NSUInteger _cg_lastEditEnd;
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

/* ==================================================================================================================
 * THE CONTAINER, ITS INSET, ITS ORIGIN AND THE INSERTION POINT.
 *
 * **A TEXT VIEW'S CONTAINER IS ITS WIDTH.** That is the class's whole layout contract in one sentence: `-setFrameSize:`
 * carries the frame's width into the container (less the two sides of the inset), the manager wraps to it, and the
 * view's height is then the layout's answer. So the four doors below are not decoration — they are the way a view is
 * put together with a container a caller built, moved to another one, or given margins.
 *
 * **`-setTextContainer:` SIZES THE CONTAINER AND `-replaceTextContainer:` DOES NOT**, which is the one difference
 * between the two doors and Apple's own: the first is the view adopting a container as ITS container (so the view's
 * width reaches it at once), the second is the text system being re-pointed at a different container WITHOUT the
 * view's geometry following — a measurement a caller does before it settles on a width. Both set the container's
 * `-textView:` to this view, and both leave the previous container detached from the manager's list.
 *
 * **`-textContainerInset` IS A MARGIN AND THE CONTAINER'S `-lineFragmentPadding` IS AIR.** Apple keeps them apart and
 * so does this tier: the inset moves the container's ORIGIN inside the view, the padding moves the first glyph inside
 * the container. **THE DEFAULT HERE IS (0, `NS_TEXT_INSET`) AND THAT IS A STATED DEVIATION FROM APPLE'S (0, 0)** —
 * this tier's text view has always measured its first line down from the field's own four-point inset, every drawing,
 * hit-test and caret in the class is written in those coordinates, and a default of zero would move every pixel of
 * every document up by four points. The width defaults to zero because the left air is the padding's, which is where
 * it has always come from; a caller that wants a margin on both sides sets both numbers.
 *
 * **THE CARET IS DRAWN THROUGH A DOOR, NOT IN `-drawRect:`.** `-shouldDrawInsertionPoint` decides, the view's own
 * `-drawRect:` asks it, and `-drawInsertionPointInRect:color:turnedOn:` does the filling — which is why a caller that
 * changes `-insertionPointColor` sees the change: the drawing reads it.
 * ================================================================================================================ */

/* Apple's designated initialiser, and the one that takes a container built somewhere else. `nil` builds the trio's own
 * — the same one `-initWithFrame:` builds — so a subclass overriding this door alone still gets a working view. */
- (instancetype)initWithFrame:(NSRect)frameRect textContainer:(nullable NSTextContainer *)container;
- (void)setTextContainer:(nullable NSTextContainer *)container;
- (void)replaceTextContainer:(nullable NSTextContainer *)newContainer;
- (NSSize)textContainerInset;
- (void)setTextContainerInset:(NSSize)inset;

/* Where the container's origin sits in this view, and the door that says "recompute it". */
- (NSPoint)textContainerOrigin;
- (void)invalidateTextContainerOrigin;

/* **THE FRAME A WRAPPING VIEW WILL ACCEPT.** The width is the caller's; the HEIGHT may not be smaller than the layout
 * needs, which is the constraint — so a caller asking for a frame too short for its text gets the taller frame back. */
- (void)setConstrainedFrameSize:(NSSize)desiredSize;

/* The backdrop, drawn from `-drawRect:` before the selection and the glyphs. */
- (void)drawViewBackgroundInRect:(NSRect)rect;

/* The caret: whether it is wanted, how it is filled, and the two doors a drawing pass and a state change go through. */
- (BOOL)shouldDrawInsertionPoint;
- (void)drawInsertionPointInRect:(NSRect)rect color:(NSColor *)color turnedOn:(BOOL)turnedOn;
- (nullable NSColor *)insertionPointColor;
- (void)setInsertionPointColor:(nullable NSColor *)color;
- (void)updateInsertionPointStateAndRestartTimer:(BOOL)flag;

/* **A REDRAW THAT MUST NOT RE-LAY-OUT.** A caller marking a small rect dirty can say so here; this tier's drawing pass
 * does not lay out at all (edits and width changes do), so the flag has nothing to suppress and the door says why. */
- (void)setNeedsDisplayInRect:(NSRect)invalidRect avoidAdditionalLayout:(BOOL)flag;

/* **THE DROP'S ARITHMETIC, AND THE INVERSE OF THE CARET'S RECT** — which character an insertion at a point in THIS
 * view's coordinates would land before. `NSNotFound` only when there is no layout to ask. */
- (NSUInteger)characterIndexForInsertionAtPoint:(NSPoint)point;

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


/* ==================================================================================================================
 * THE RULER — the view's half of it, and the nine questions the ruler asks it back.
 *
 * **`-usesRuler` IS A LINE THE VIEW DRAWS AND `-isRulerVisible` IS WHERE IT IS.** Apple separates the two: a view that
 * uses a ruler wants one it can SHOW, and showing it is the scroll view's visibility flag. So `-setUsesRuler:NO` means
 * "this view has no ruler at all" — `-setRulerVisible:YES` then creates nothing — while hiding one leaves it built and
 * its markers intact.
 *
 * `-updateRuler` IS THE ONE PLACE THE RULER AND THE PARAGRAPH ARE RECONCILED, and it is public because Apple's is: it
 * reads the paragraph style at the insertion point, asks the layout manager for a marker per tab stop, installs them, and
 * reserves the ruler's marker band from the tallest one. The view calls it when the ruler is shown and when the
 * selection moves.
 *
 * **AND THE NINE DELEGATE-LOOKING DOORS ARE THE CLIENT VIEW'S SIDE OF THE INFORMAL PROTOCOL.** They are not a
 * `NSRulerViewDelegate` (10.6 has no such protocol) — they are the messages a ruler sends its CLIENT VIEW, and this is
 * the client. The three `should` questions answer YES; the two `will` questions answer the location they were given, and
 * are where a view would clamp one; and the three `did` questions are the real behaviour: THE PARAGRAPH'S TAB STOPS ARE
 * REBUILT FROM THE MARKERS, so dragging a marker in the ruler moves the tab stop in the document, and adding or
 * removing one adds or removes a tab. That is the whole reason a `representedObject` carries the `NSTextTab`.
 *
 * `-rulerView:handleMouseDown:` moves the insertion point to the place on the current line that the click names — the
 * other half of the gesture, so a click that misses a marker is not swallowed.
 * ================================================================================================================ */

- (BOOL)isRulerVisible;
- (void)setRulerVisible:(BOOL)flag;
- (BOOL)usesRuler;
- (void)setUsesRuler:(BOOL)flag;
- (void)updateRuler;

- (BOOL)rulerView:(NSRulerView *)aRulerView shouldAddMarker:(NSRulerMarker *)marker;
- (CGFloat)rulerView:(NSRulerView *)aRulerView willAddMarker:(NSRulerMarker *)marker atLocation:(CGFloat)location;
- (void)rulerView:(NSRulerView *)aRulerView didAddMarker:(NSRulerMarker *)marker;
- (BOOL)rulerView:(NSRulerView *)aRulerView shouldMoveMarker:(NSRulerMarker *)marker;
- (CGFloat)rulerView:(NSRulerView *)aRulerView willMoveMarker:(NSRulerMarker *)marker toLocation:(CGFloat)location;
- (void)rulerView:(NSRulerView *)aRulerView didMoveMarker:(NSRulerMarker *)marker;
- (BOOL)rulerView:(NSRulerView *)aRulerView shouldRemoveMarker:(NSRulerMarker *)marker;
- (void)rulerView:(NSRulerView *)aRulerView didRemoveMarker:(NSRulerMarker *)marker;
- (void)rulerView:(NSRulerView *)aRulerView handleMouseDown:(NSEvent *)event;

/* ==================================================================================================================
 * FINDING — `NSFindPanelAction` and the four doors that reach it.
 *
 * **THE PANEL DOES NOT EXIST AND THE ACTIONS STILL DO, WHICH IS THE SPLIT APPLE'S OWN API MAKES.** `-performFindPanelAction:`
 * takes a sender whose TAG is an `NSFindPanelAction`; a panel is only one of the ten things that tag can mean. The three
 * that need a panel — show it, replace, replace-all — refuse by name here, and the rest are real: next, previous, select
 * all, select-all-in-selection, and "set the find string from the selection", which is what a Find menu's first item
 * does before any panel exists.
 *
 * THE VOCABULARY IS DECLARED IN THIS HEADER BECAUSE APPLE DECLARES IT HERE, in `NSTextView.h` — the artefact has no
 * `NSFindPanel.h` at these pins, which is why a reader looking for one will not find it.
 * ================================================================================================================ */

enum {
	NSFindPanelActionShowFindPanel = 1,
	NSFindPanelActionNext = 2,
	NSFindPanelActionPrevious = 3,
	NSFindPanelActionReplaceAll = 4,
	NSFindPanelActionReplace = 5,
	NSFindPanelActionReplaceAndFind = 6,
	NSFindPanelActionSetFindString = 7,
	NSFindPanelActionReplaceAllInSelection = 8,
	NSFindPanelActionSelectAll = 9,
	NSFindPanelActionSelectAllInSelection = 10
};

- (void)performFindPanelAction:(nullable id)sender;

/* Whether the view prefers a find bar to a find panel. Stored and answered; the BAR is the application's to build. */
- (BOOL)usesFindPanel;
- (void)setUsesFindPanel:(BOOL)flag;

/* **THE FLASH IS STATIC HERE AND THAT IS STATED.** Apple's indicator is an animated capsule; this tier draws a yellow
 * ring for one drawing pass and clears it, so a caller sees the feedback it asked for without an animation engine. */
- (void)showFindIndicatorForRange:(NSRange)charRange;

/* ==================================================================================================================
 * THE SELECTION'S RANGES, ITS AFFINITY AND ITS GRANULARITY.
 *
 * **`-selectedRanges` IS THE ARRAY AND `-selectedRange` IS ITS FIRST MEMBER**, which is how Apple's own text system
 * keeps one caret position while allowing several disjoint selections. A view that never had more than one selection
 * answers a one-element array, so a caller that only ever asks this door sees the same thing it always did.
 * ================================================================================================================ */

- (NSArray *)selectedRanges;
- (void)setSelectedRanges:(NSArray *)ranges;
- (void)setSelectedRanges:(NSArray *)ranges affinity:(NSTextSelectionAffinity)affinity stillSelecting:(BOOL)stillSelecting;
- (void)setSelectedRange:(NSRange)range affinity:(NSTextSelectionAffinity)affinity stillSelecting:(BOOL)stillSelecting;
- (NSTextSelectionAffinity)selectionAffinity;
- (NSTextSelectionGranularity)selectionGranularity;
- (void)setSelectionGranularity:(NSTextSelectionGranularity)granularity;

/* **AND THE EXPANSION, WHICH IS THE UNIT THE SELECTION COMMANDS USE.** Character answers the range it was given; word
 * grows over letters, digits and underscore; paragraph grows to the newline boundaries; document is the whole text. A
 * proposed range is CLAMPED first, so a range that runs past the end answers the end rather than overflowing it. */
- (NSRange)selectionRangeForProposedRange:(NSRange)proposedRange
			      granularity:(NSTextSelectionGranularity)granularity;

/* ==================================================================================================================
 * THE ATTRIBUTES THE VIEW CARRIES.
 *
 * **`-typingAttributes` IS WHAT NEW TEXT GETS, AND `-insertText:` APPLIES IT.** Apple's view takes the attributes at
 * the insertion point when a caller set none; this tier answers the caller's dictionary when there is one, else the
 * insertion point's run, else the default paragraph style plus the view's font — and the snippet the view inserts wears
 * whatever it answers, which is what makes a "bold" toggle visible on the next keystroke rather than the next paste.
 * ================================================================================================================ */

- (NSDictionary *)typingAttributes;
- (void)setTypingAttributes:(NSDictionary *)attrs;
- (NSParagraphStyle *)defaultParagraphStyle;
- (void)setDefaultParagraphStyle:(NSParagraphStyle *)style;

/* **THE SELECTED AND MARKED RUNS' INK.** The selected pair's BACKGROUND colour is what the selection is filled with
 * (the accent when nothing is set), and the marked pair's underline is applied to a composition as it arrives. Both are
 * read where they are drawn rather than stored for a later slice. */
- (NSDictionary *)selectedTextAttributes;
- (void)setSelectedTextAttributes:(NSDictionary *)attributes;
- (NSDictionary *)markedTextAttributes;
- (void)setMarkedTextAttributes:(NSDictionary *)attributes;

/* ==================================================================================================================
 * WHAT A COMMAND MAY CHANGE, WHICH IS THE EDITING CONTRACT THE ATTRIBUTE COMMANDS ASK.
 *
 * `-shouldChangeTextInRange:replacementString:` is asked before every text edit and every attribute command, and a
 * subclass answers NO to refuse one; the plural form asks about each range in turn. The four `rangeForUser…` pairs are
 * the ranges a command SHOULD act on: the selection, the character a caret would affect, or the paragraphs it touches.
 * ================================================================================================================ */

- (BOOL)shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(nullable NSString *)replacementString;
- (BOOL)shouldChangeTextInRanges:(NSArray *)affectedRanges
	     replacementStrings:(nullable NSArray *)replacementStrings;

- (NSRange)rangeForUserTextChange;
- (NSArray *)rangesForUserTextChange;
- (NSRange)rangeForUserCharacterAttributeChange;
- (NSArray *)rangesForUserCharacterAttributeChange;
- (NSRange)rangeForUserParagraphAttributeChange;
- (NSArray *)rangesForUserParagraphAttributeChange;

/* ==================================================================================================================
 * THE ATTRIBUTE COMMANDS.
 *
 * **EACH ONE EDITS THE STORE OVER `-rangeForUserCharacterAttributeChange`** (or the paragraph range for the two
 * paragraph commands), and each asks `-shouldChangeTextInRange:replacementString:` first — so a subclass that refuses
 * an edit refuses the ATTRIBUTE change with it. Kerning and baseline are INCREMENTAL (Apple's commands add or subtract
 * a point); the two "standard" spellings REMOVE the attribute, which is what "standard" means when the default is the
 * font's own.
 * ================================================================================================================ */

- (void)loosenKerning:(nullable id)sender;
- (void)tightenKerning:(nullable id)sender;
- (void)turnOffKerning:(nullable id)sender;
- (void)useStandardKerning:(nullable id)sender;
- (void)lowerBaseline:(nullable id)sender;
- (void)raiseBaseline:(nullable id)sender;
- (void)turnOffLigatures:(nullable id)sender;
- (void)useAllLigatures:(nullable id)sender;
- (void)useStandardLigatures:(nullable id)sender;

/* AND THE TWO THAT MOVE A PARAGRAPH RATHER THAN A RUN. `-setAlignment:range:` sets the alignment on every paragraph the
 * range touches (each paragraph keeps its other style properties); the writing-direction pair does the same for the
 * base direction, and `-toggleBaseWritingDirection:` flips it. */
- (void)setAlignment:(NSTextAlignment)alignment range:(NSRange)range;
- (void)setBaseWritingDirection:(NSWritingDirection)direction range:(NSRange)range;
- (void)toggleBaseWritingDirection:(nullable id)sender;

/* ==================================================================================================================
 * WHAT TYPING DOES AROUND IT — SMART INSERT AND DELETE, AND THE UNDO GROUP.
 *
 * **SMART INSERT ADDS THE SPACE THAT TWO WORDS WOULD OTHERWISE LOSE.** A string inserted next to a word — by typing, by a
 * paste, by a drop — is surrounded by a space where the neighbouring character and the inserted edge are both
 * *word* characters (a letter, a digit or an underscore), because that is the case where the text would otherwise
 * fuse into one word. Whitespace at either edge needs nothing, and so does the start or the end of the document. The
 * three doors are Apple's: the pair answers the two halves, and the whole one answers both, so a caller that only
 * wants to know whether anything would happen can ask either half.
 *
 * **SMART DELETE TAKES THE WHITESPACE THE DELETION WOULD OTHERWISE LEAVE DOUBLED.** `-smartDeleteRangeForProposedRange:`
 * grows a non-empty range over the whitespace that separates it from the next word — the TRAILING run when there is one,
 * else the LEADING run — so deleting a word between two spaces leaves one space rather than two. That is the whole
 * rule, it is applied by `-delete:` (the command a Delete menu item sends), and it does not touch `-deleteBackward:`:
 * one character at a time there is no doubled space to avoid, and the base class's arithmetic for that key stays its
 * own.
 *
 * **UNDO IS A GROUP OF EDITS, NOT A STACK OF KEYSTROKES.** With `-allowsUndo` on and an undo manager in the responder
 * chain (`-undoManager`, which this view inherits and a document's window supplies), every edit through the view's
 * primitive registers the edit that reverses it, so the manager replays the view's own door and the text, the layout
 * and the selection all follow. A run of ADJACENT edits — typing, or a run of backspaces — stays in ONE group, which is
 * what makes one `-undo` take back a typed word rather than a letter; an edit somewhere else closes the group and
 * starts another, and `-breakUndoCoalescing` closes it on demand.
 *
 * **AND `-didChangeText` IS THE DOOR THE EDIT PATH CALLS**, rather than the notification being posted from three
 * places: it announces the change to the delegate and the centre, and it is what an override hooks to see an edit.
 * ================================================================================================================ */

- (BOOL)smartInsertDeleteEnabled;
- (void)setSmartInsertDeleteEnabled:(BOOL)flag;
- (void)toggleSmartInsertDelete:(nullable id)sender;
- (void)smartInsertForString:(NSString *)pasteString
	      replacingRange:(NSRange)charRange
		 beforeString:(NSString * _Nullable * _Nullable)beforeString
		  afterString:(NSString * _Nullable * _Nullable)afterString;
- (nullable NSString *)smartInsertBeforeStringForString:(NSString *)pasteString replacingRange:(NSRange)charRange;
- (nullable NSString *)smartInsertAfterStringForString:(NSString *)pasteString replacingRange:(NSRange)charRange;
- (NSRange)smartDeleteRangeForProposedRange:(NSRange)proposedCharRange;

- (BOOL)allowsUndo;
- (void)setAllowsUndo:(BOOL)flag;
- (void)breakUndoCoalescing;
- (BOOL)isCoalescingUndo;
- (void)didChangeText;

/* ==================================================================================================================
 * THE TWO PANELS A COMMAND OPENS.
 *
 * `-changeAttributes:` opens the font panel and tells it what the selection is set in; `-changeColor:` opens the colour
 * panel and makes this view its target, so the colour a person picks is applied to the selection. `-updateFontPanel`
 * is the report back — it is what a caller with the font panel open calls after moving the caret.
 * ================================================================================================================ */

- (void)changeAttributes:(nullable id)sender;
- (void)changeColor:(nullable id)sender;
- (BOOL)usesFontPanel;
- (void)setUsesFontPanel:(BOOL)flag;
- (void)updateFontPanel;

/* ==================================================================================================================
 * THE CLIPBOARD AND THE DRAG.
 *
 * **THE VIEW WRITES RICH TEXT AND READS IT BACK.** A copy puts the selection on a pasteboard as RTF (the AppKit-aware
 * writer `-RTFRepresentation`), as RTFD (which can carry an attachment), and as a plain string; a paste asks for the
 * RICHEST type the board has and falls back to the string. The two type lists are the view's declaration of what it can
 * read and write, and `-acceptableDragTypes` is the same list for a drop.
 *
 * **AND A DROP LANDS WHERE IT WAS DROPPED.** `-characterIndexForInsertionAtPoint:` is the mapping the earlier slice
 * said was missing: the manager's point-to-glyph door exists, the view converts the drop's point into the container's
 * coordinates through `-textContainerOrigin`, and the drop sets the selection there before it reads the pasteboard —
 * so a drop and a paste differ in exactly one thing, which is where the text goes.
 * ================================================================================================================ */

- (NSArray *)readablePasteboardTypes;
- (NSArray *)writablePasteboardTypes;
- (NSArray *)acceptableDragTypes;
- (nullable NSString *)preferredPasteboardTypeFromArray:(NSArray *)availableTypes
			       restrictedToTypesFromArray:(NSArray *)allowedTypes;

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard type:(NSString *)type;
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types;
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard;
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard type:(NSString *)type;

/* THE FIVE COMMANDS, WHICH ARE `NSResponder`'S NAMES IMPLEMENTED HERE.** `-copy:` writes, `-cut:` writes and deletes,
 * `-paste:` reads, and each does nothing when the pasteboard has nothing the view can use. */
- (void)copy:(nullable id)sender;
- (void)cut:(nullable id)sender;
- (void)paste:(nullable id)sender;
- (void)delete:(nullable id)sender;
- (void)pasteAsPlainText:(nullable id)sender;
- (void)pasteAsRichText:(nullable id)sender;

/* THE DRAG SOURCE. The image is the selection's ink, drawn into an image the drag can carry; `-dragOperationForDraggingInfo:type:`
 * is the operation a drop from this view offers, and `-updateDragTypeRegistration` registers `-acceptableDragTypes` with
 * the view's own destination list. */
- (nullable NSImage *)dragImageForSelectionWithEvent:(NSEvent *)event origin:(NSPointPointer)origin;
- (BOOL)dragSelectionWithEvent:(nullable NSEvent *)event offset:(NSSize)mouseOffset slideBack:(BOOL)slideBack;
- (NSDragOperation)dragOperationForDraggingInfo:(id <NSDraggingInfo>)dragInfo type:(nullable NSString *)type;
- (void)updateDragTypeRegistration;
- (void)cleanUpAfterDragOperation;

/* AND WHETHER A PASTE MAY CARRY A PICTURE — see the ivar's note. */
- (BOOL)allowsImageEditing;
- (void)setAllowsImageEditing:(BOOL)flag;

/* ==================================================================================================================
 * THE REMAINING THIRTY-NINE — nine real, thirty refused by name.
 *
 * **THE REAL ONES ARE THE DOCUMENT BACKGROUND, THE LINKS AND THE COMPLETION.** `-allowsDocumentBackgroundColorChange`
 * gates `-changeDocumentBackgroundColor:`, which is what a colour panel's target does; `-linkTextAttributes` is the ink a
 * link is DRAWN in (the attribute itself is `NSLinkAttributeName`, declared in this header because Apple declares it in an
 * AppKit category) and `-clickedOnLink:atIndex:` asks the delegate first and opens a URL second; and the completion trio
 * is the era's word completion — the partial word at the caret, the document's words that start with it, and the insert
 * that replaces the range.
 *
 * **THE THIRTY REFUSE, EACH NAMING THE PIECE THAT IS ABSENT, AND THE FAMILIES ARE WORTH NAMING ONCE HERE:**
 *
 *   - the TEXT-CHECKING family (fifteen doors: `-checkTextIn…`, `-enabledTextCheckingTypes`, `-handleTextCheckingResults:…`,
 *     and the three `-isAutomatic…Enabled`/`-setAutomatic…`/`-toggleAutomatic…` triples) is BLOCKED on
 *     `NSTextCheckingResult` and `NSOrthography`, which Foundation in this tier has not got — the asynchronous spell door
 *     already refuses for exactly that reason, so these answer with it;
 *   - the four `-orderFront…Panel:` doors need the link, list, spacing and table panels, which this tier has not built;
 *   - `-startSpeaking:`/`-stopSpeaking:` need a speech service;
 *   - `-registerForServices` needs the services transport (the same gap `-performService` refuses for);
 *   - `-acceptsGlyphInfo`/`-setAcceptsGlyphInfo:` would be a flag NOBODY READS: the manager in this tier never hands glyph
 *     info to a view;
 *   - `-allowedInputSourceLocales`/`-setAllowedInputSourceLocales:` would be a second flag nobody reads: the input context
 *     here does not filter its sources by locale;
 *   - `-displaysLinkToolTips`/`-setDisplaysLinkToolTips:` need the tool-tip machinery `NSView` has not got;
 *   - `-outline:` needs an outline panel, and `-toggleTraditionalCharacterShape:` is a 10.0-era CJK shape switch that no
 *     modern face has.
 * ================================================================================================================ */

- (BOOL)allowsDocumentBackgroundColorChange;
- (void)setAllowsDocumentBackgroundColorChange:(BOOL)flag;
- (void)changeDocumentBackgroundColor:(nullable id)sender;

- (nullable NSDictionary *)linkTextAttributes;
- (void)setLinkTextAttributes:(nullable NSDictionary *)attributes;
- (BOOL)clickedOnLink:(id)link atIndex:(NSUInteger)charIndex;
- (BOOL)displaysLinkToolTips;
- (void)setDisplaysLinkToolTips:(BOOL)flag;

- (NSRange)rangeForUserCompletion;
- (nullable NSArray *)completionsForPartialWordRange:(NSRange)charRange indexOfSelectedItem:(nullable NSInteger *)index;
- (void)insertCompletion:(NSString *)word
    forPartialWordRange:(NSRange)charRange
		 movement:(NSInteger)movement
		  isFinal:(BOOL)flag;

- (nullable NSArray *)allowedInputSourceLocales;
- (void)setAllowedInputSourceLocales:(nullable NSArray *)localeIdentifiers;
- (BOOL)acceptsGlyphInfo;
- (void)setAcceptsGlyphInfo:(BOOL)flag;
- (void)outline:(nullable id)sender;
- (void)toggleTraditionalCharacterShape:(nullable id)sender;
- (void)startSpeaking:(nullable id)sender;
- (void)stopSpeaking:(nullable id)sender;
- (void)registerForServices;
- (void)orderFrontLinkPanel:(nullable id)sender;
- (void)orderFrontListPanel:(nullable id)sender;
- (void)orderFrontSpacingPanel:(nullable id)sender;
- (void)orderFrontTablePanel:(nullable id)sender;

- (void)checkTextInDocument:(nullable id)sender;
- (void)checkTextInSelection:(nullable id)sender;
- (void)checkTextInRange:(NSRange)range types:(NSUInteger)types options:(nullable NSDictionary *)options;
- (void)handleTextCheckingResults:(NSArray *)results
			 forRange:(NSRange)range
			    types:(NSUInteger)types
			  options:(nullable NSDictionary *)options
		      orthography:(nullable id)orthography
			wordCount:(NSInteger)wordCount;
- (NSUInteger)enabledTextCheckingTypes;
- (void)setEnabledTextCheckingTypes:(NSUInteger)types;
- (BOOL)isAutomaticDataDetectionEnabled;
- (void)setAutomaticDataDetectionEnabled:(BOOL)flag;
- (void)toggleAutomaticDataDetection:(nullable id)sender;
- (BOOL)isAutomaticLinkDetectionEnabled;
- (void)setAutomaticLinkDetectionEnabled:(BOOL)flag;
- (void)toggleAutomaticLinkDetection:(nullable id)sender;
- (BOOL)isAutomaticTextReplacementEnabled;
- (void)setAutomaticTextReplacementEnabled:(BOOL)flag;
- (void)toggleAutomaticTextReplacement:(nullable id)sender;

@end
/* **`NSTextViewDelegate`, THE ERA'S PROTOCOL FOR THE TEXT VIEW'S QUESTIONS.** It is `NSTextDelegate`'s successor, and the
 * members below are the ten the 10.6 header names often enough to matter: the edit veto, the command hook, the link
 * click, the selection and completion pairs, the tooltip, the tooltip's cell, and the dragging hook.
 *
 * **NOTHING SENDS THEM YET, AND THAT IS STATED RATHER THAN IMPLIED.** `NSText` owns the delegate slot and this tier sends
 * it no message; the view's own edit path announces the change to the notification centre instead (see `NSTextView.m`).
 * The protocol is declared here because a PORTED subclass conforms to it, and a conformance has to name a protocol that
 * exists. When the view starts asking — the natural place is `-setString:` and `-keyDown:` — the doors are already
 * named, and the header at that site says which ones it asks.
 */
@protocol NSTextAttachmentCell;

@protocol NSTextViewDelegate <NSTextDelegate>
@optional
- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange
						  replacementString:(nullable NSString *)replacementString;
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector;
- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex;
- (NSRange)textView:(NSTextView *)textView willChangeSelectionFromCharacterRange:(NSRange)oldSelectedCharRange
						    toCharacterRange:(NSRange)newSelectedCharRange;
- (void)textViewDidChangeSelection:(NSNotification *)notification;
- (nullable NSString *)textView:(NSTextView *)textView willDisplayToolTip:(NSString *)tooltip
							  forCharacterAtIndex:(NSUInteger)characterIndex;
- (NSArray *)textView:(NSTextView *)textView completions:(NSArray *)words
						    forPartialWordRange:(NSRange)charRange
						    indexOfSelectedItem:(NSInteger *)index;
- (NSArray *)textView:(NSTextView *)textView willChangeSelectionFromCharacterRanges:(NSArray *)oldSelectedCharRanges
						     toCharacterRanges:(NSArray *)newSelectedCharRanges;
- (void)textView:(NSTextView *)view draggedCell:(id <NSTextAttachmentCell>)cell
						 inRect:(NSRect)rect event:(NSEvent *)event
						atIndex:(NSUInteger)charIndex;
- (BOOL)textView:(NSTextView *)textView shouldSetSpellingState:(NSInteger)value
							range:(NSRange)affectedCharRange;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTVIEW_H */
