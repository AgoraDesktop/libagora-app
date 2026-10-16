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
 *   II.  WRAPPING (THIS SLICE). The model gains a WIDTH: a line too wide for the view becomes several VISUAL LINES,
 *        and the caret, the hit test, the selection and every movement walk those instead. `NSResponder.h`'s word
 *        correction already said a WORD is not a layout question; a VISUAL LINE is one, and this is where it is
 *        decided.
 *   III. SCROLLING (THIS SLICE). The two `NSView` doors that move an enclosing clip view, the text view settling its
 *        own height so a clip view has something to scroll, and `-scrollRangeToVisible:` turning a caret into a
 *        rectangle. **WHAT IS OWED IS THE DOCUMENT'S ORIENTATION**: Apple's text view is FLIPPED so its FIRST line
 *        sits at the clip view's origin, and this class still measures y UP (the base's convention) — so the DOORS
 *        are right either way and the orientation is the next slice.
 *   IV.  RICH TEXT, ATTACHMENTS AND PARAGRAPHS, which need the attributed store and the attribute vocabulary the
 *        `NSTextFieldAttributedStringMethods` note already names as travelling without being obeyed.
 *
 * **THE TWO UNITS ARE NOT THE SAME THING AND BOTH KEEP THEIR OWN NAME.** A MODEL LINE — a paragraph, in Apple's
 * vocabulary — is a `\n`-terminated run, and the three `cg_…OfLine:` doors below are that model: they are facts about
 * the STRING and do not change when the view is resized. A VISUAL LINE is one line as LAID OUT at the view's width,
 * and there can be several per model line; the two `cg_visualLine…` doors are that layout, and they change every time
 * the text or the width does. A caller that wants "how many lines" has to say which.
 *
 * **WHAT THE SLICES ABOVE STILL HAVE NOT GOT, NAMED RATHER THAN STUBBED:** scrolling and the clip view, the
 * `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` trio and the door names that come with it, attachments, tables,
 * the paragraph commands, the marked-text family and the input-method half.
 */
#ifndef APPKIT_NSTEXTVIEW_H
#define APPKIT_NSTEXTVIEW_H

#import <AppKit/NSText.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSTextView : NSText
{
	/* **THE VISUAL LAYOUT, WHICH IS THE MODEL LAID OUT AT A WIDTH AND IS REBUILT WHENEVER EITHER CHANGES.** A flat
	 * array of character ranges in reading order, which is all a line IS: the y is the index times the line height and
	 * the x is Core Text's offset within the line, so a second array of positions would be a second thing to keep in
	 * step. `malloc`'d rather than an `NSArray` because a layout is a run of PODs a draw reads in a loop, and
	 * `_cg_layoutValid` is the dirty flag `-replaceCharactersInRange:`, `-setString:` and `-setFrameSize:` clear. */
	NSRange *_cg_visual;		/* malloc'd; the first `_cg_visualCount` are live */
	NSUInteger _cg_visualCount;
	NSUInteger _cg_visualCapacity;
	BOOL _cg_layoutValid;
	CGFloat _cg_layoutWidth;
	/* **AND WHETHER THIS VIEW IS TALL ENOUGH FOR ITS OWN LAYOUT.** Apple's default for a text view is YES — one inside
	 * a scroll view grows and shrinks with its text — and a caller that gave the view a frame on purpose says NO. */
	BOOL _cg_verticallyResizable;
}

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
