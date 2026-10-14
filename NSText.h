/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSText.h — THE ALIGNMENT AND WRITING-DIRECTION VOCABULARIES, IN THE FILE APPLE PUTS THEM IN.
 *
 * **THIS FILE EXISTS BECAUSE OF WHERE APPLE DECLARES THE TWO TYPES, NOT BECAUSE THIS LIBRARY WANTED A NEW HEADER.**
 * `NSTextAlignment` and `NSWritingDirection` are the types behind `NSCell`'s `-alignment` and `-baseWritingDirection`,
 * and Apple declares them HERE — in `AppKit/NSText.h` — which is also the file every one of their ledger rows names as
 * the ground. THE BLANKET RULE THIS UNIT WORKS UNDER IS "MATCH APPLE, INCLUDING WHICH HEADER", so a header named
 * `NSText.h` is the answer rather than an extra block of types inside `NSCell.h`: the alternative would have declared
 * fifteen ledger rows in a file the ledger does not hold them against.
 *
 * THE VALUES ARE THE 10.6 HEADER'S, TRANSCRIBED. `NSTextAlignment` is `NSUInteger` and its five cases run 0 to 4 in
 * Apple's own order; `NSWritingDirection` is `NSInteger` — SIGNED — because its first case is `-1`, which is the whole
 * reason the two types cannot share a spelling.
 *
 * WHAT IS NOT HERE, AND ITS ROWS STAY OPEN: the text-movement codes of `NSTextDidEndEditing`, the notification keys,
 * the RTF/RTFD reading and writing, the spelling and substitution services, and the two
 * `NSTextWritingDirection*` values that modify a direction "when used with `NSWritingDirectionAttributeName`" — that
 * pair is a vocabulary whose user (an attributed-string attribute key) this tier does not have, so it is named here
 * and left for the unit that brings its user.
 */
#ifndef APPKIT_NSTEXT_H
#define APPKIT_NSTEXT_H

#import <Foundation/Foundation.h>
/* **AND ONE APPKIT HEADER, WHICH IS THE SUPERCLASS AND NOTHING ELSE.** The vocabulary above is Foundation's business
 * and was all this header held; a class deriving from `NSView` needs that class to be REAL rather than forward
 * declared, so it is imported — and `NSColor` is only ever a POINTER here, so it is forward declared instead.
 *
 * THAT ASYMMETRY IS NOT FUSSINESS: `NSCell.h` imports THIS header for `NSTextAlignment`, and `NSColor.h` needs a type
 * `NSCell.h` declares — so importing `NSColor.h` from here would close a cycle that has nothing to do with colours.
 * (The two errors it produced pointed at `NSColor.h`'s own declaration of `-colorForControlTint:`, which is a good
 * description of the problem and a poor one of the cause.) */
#import <AppKit/NSView.h>

@class NSColor;

NS_ASSUME_NONNULL_BEGIN

/* **THE ALIGNMENT, IN APPLE'S ORDER — AND THE ORDER IS WHAT MAKES THE VALUES MEANINGFUL**, which is why the era's
 * own trailing comments are kept: the last case is not a position on the line at all, it is "the default alignment for
 * script", and a reader who assumed it was the fifth position would get the RTL case wrong. */
enum {
	NSLeftTextAlignment = 0,	/* Visually left aligned */
	NSRightTextAlignment = 1,	/* Visually right aligned */
	NSCenterTextAlignment = 2,	/* Visually centered */
	NSJustifiedTextAlignment = 3,	/* Fully justified; the last line is natural-aligned */
	NSNaturalTextAlignment = 4	/* The default alignment for script */
};
typedef NSUInteger NSTextAlignment;

/* **AND THE WRITING DIRECTION, WHOSE FIRST CASE IS WHY THE TYPE IS SIGNED.** The era's comment gives the rule that
 * makes `-1` the right spelling rather than a sentinel this library invented: the natural direction is determined by
 * the Unicode Bidi Algorithm, not by a caller. */
enum {
	NSWritingDirectionNatural = -1,		/* Determined by the Unicode Bidi Algorithm, rules P2 and P3 */
	NSWritingDirectionLeftToRight = 0,
	NSWritingDirectionRightToLeft = 1
};
typedef NSInteger NSWritingDirection;

/* ============================================================================================ *
 * AND THE CLASS ITSELF, WHICH IS THE BIGGEST THING THIS HEADER HOLDS IN APPLE'S TREE.            *
 *                                                                                                *
 * **AN `NSText` IS A VIEW THAT HOLDS A STRING AND LETS A PERSON TYPE INTO IT.** It is the base   *
 * every editable text surface in AppKit is built on — a field's editor, a document's text view,  *
 * a table cell's editor — and what makes it a BASE rather than a partial `NSTextView` is what it  *
 * deliberately does not have: ONE RUN of text, ONE line, and no layout beyond that.               *
 * ============================================================================================ */

@class NSText;

/* **THE DELEGATE, IN THE 10.6 SHAPE — a real `@protocol`**, the same era decision `NSWindowDelegate` and
 * `NSImageDelegate` record. Every method is optional, which is what `@optional` says and what an informal protocol
 * used to have to say in prose. THE TWO `Should` QUESTIONS ARE ASKED AND ANSWERED as booleans rather than announced,
 * because a delegate that wants to REFUSE an edit session has to be able to: a form that will not let a field be
 * edited says so here, and the notification trio is what a delegate listens for when it only wants to know. */
@protocol NSTextDelegate <NSObject>
@optional
- (BOOL)textShouldBeginEditing:(NSText *)textObject;
- (void)textDidBeginEditing:(NSNotification *)notification;
- (BOOL)textShouldEndEditing:(NSText *)textObject;
- (void)textDidEndEditing:(NSNotification *)notification;
- (void)textDidChange:(NSNotification *)notification;
@end

@interface NSText : NSView
{
	/* **THE STRING IS MUTABLE AND HELD, rather than an immutable value swapped on every keystroke**: an edit is a
	 * RANGE REPLACEMENT — that is the one primitive every other edit is written in terms of — and a class that
	 * rebuilt its storage per character would copy the whole document to insert one letter. It is the only thing here
	 * that grows with the text; everything else is a flag or a number. */
	NSMutableString *_string;	/* RETAINED */
	/* AND WHERE THE EDITING HAPPENS: the selection, which is a CARET when its length is zero. One field rather than
	 * two, because a caret IS an empty selection and a class with both would have two answers to keep in step. */
	NSRange _selectedRange;
	id _font;			/* RETAINED — an NSFont */
	NSColor *_backgroundColor;	/* RETAINED */
	NSTextAlignment _alignment;
	id _delegate;			/* NOT RETAINED: this tree's rule for every delegate */
	BOOL _editable;
	BOOL _selectable;
	BOOL _drawsBackground;
	BOOL _fieldEditor;
	BOOL _richText;
	BOOL _importsGraphics;
	BOOL _editing;
	BOOL _dragging;		/* a selection drag is in flight, which is a fact about the POINTER */
	/* **AND THE END OF THE DRAG THAT DOES NOT MOVE.** A selection has two ends and one of them is fixed by the press,
	 * so it is REMEMBERED here rather than recomputed from the selection — see `-mouseDown:` for what recomputing
	 * it costs, which is a drag that works in one direction only. */
	NSUInteger _dragAnchor;
	/* **AND HOW FAR THE FIELD HAS SCROLLED ITSELF, BECAUSE NOTHING ELSE CAN.** A field whose text outruns its frame
	 * has to move that text so the caret stays in view, and this tier has no scroll view to do it — the drawing layer
	 * REFUSES a non-zero BOUNDS ORIGIN by name ("that is a scroll offset, and this layer does not model one"), so the
	 * offset is kept here and subtracted from the three things this class draws. ZERO WHENEVER THE TEXT FITS, because
	 * `-scrollRangeToVisible:` clamps it there. */
	CGFloat _originX;
}

/* THE STRING, WHICH IS WHAT THIS CLASS IS FOR. `-setString:` REPLACES the whole of it and puts the insertion point at
 * the end, which is what "the text is now this" means — a setter that left a selection pointing into text that is no
 * longer there would be a caret past the end of its own document. */
- (NSString *)string;
- (void)setString:(NSString *)string;

/* **AND THE ONE EDITING PRIMITIVE, WHICH EVERY OTHER EDIT IS SPELLED IN.** A range and its replacement; the
 * insertion point ends up after what was inserted, which is the rule the typing path depends on. A range outside the
 * string is CLAMPED rather than refused, because the alternative is a caller's arithmetic bug becoming a crash in a
 * view that is only trying to show some text. */
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string;

/* THE SELECTION, AND THE ONE CONVENIENCE THAT IS ALWAYS WANTED. A range outside the string is clamped the same way
 * `-replaceCharactersInRange:withString:` clamps one. */
- (NSRange)selectedRange;
- (void)setSelectedRange:(NSRange)range;
- (void)selectAll:(nullable id)sender;

/* **AND THE DOOR THAT KEEPS THE CARET IN VIEW.** Apple scrolls the ENCLOSING SCROLL VIEW, which this tier does not
 * have, so what moves here is the field's own text — the implementation says exactly what that is and is not the same
 * as, and what becomes of this arithmetic when the scrolling slice lands. It is called by every edit and every caret
 * move rather than by a caller alone, which is what makes typing past the right edge scroll without anybody asking. */
- (void)scrollRangeToVisible:(NSRange)range;

/* THE FACE. `-font` and `-alignment` are the two a plain-text view has; the ink is the window's text colour, which is
 * why there is no `-textColor` here — that door belongs to `NSTextView`, whose runs carry their own. */
- (nullable id)font;
- (void)setFont:(nullable id)font;
- (NSTextAlignment)alignment;
- (void)setAlignment:(NSTextAlignment)alignment;
- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)flag;
- (nullable NSColor *)backgroundColor;
- (void)setBackgroundColor:(nullable NSColor *)color;

/* **AND THE FOUR FLAGS, OF WHICH THIS SLICE HONOURS TWO.** `-isEditable` and `-isSelectable` decide whether keystrokes
 * change the text and whether the pointer can select it, and both are obeyed. `-isRichText` and `-isImportsGraphics`
 * are STORED AND ANSWERED AND HAVE NOTHING TO OBEY YET — this tier has no RTF reader and no paragraph model — which is
 * stated here rather than left for a caller to find out by setting one. `-isFieldEditor` is the role a window's field
 * editor plays, and the machinery that reads it is the next slice's. */
- (BOOL)isEditable;
- (void)setEditable:(BOOL)flag;
- (BOOL)isSelectable;
- (void)setSelectable:(BOOL)flag;
- (BOOL)isRichText;
- (void)setRichText:(BOOL)flag;
- (BOOL)importsGraphics;
- (void)setImportsGraphics:(BOOL)flag;
- (BOOL)isFieldEditor;
- (void)setFieldEditor:(BOOL)flag;

/* THE DELEGATE, AND THE MEASUREMENT. `-sizeToFit` asks the TEXT how big the view wants to be — the line plus this
 * class's own air — which is the same shape `NSControl -sizeToFit` takes one class over. */
- (nullable id)delegate;
- (void)setDelegate:(nullable id)delegate;
- (void)sizeToFit;

@end

/* **AND THE THREE NOTIFICATIONS A DELEGATE CAN WATCH INSTEAD.** They are the OTHER half of the delegate protocol — a
 * delegate that only wants to know registers for these and leaves the `Should` questions unanswered — and `userInfo`
 * is empty in all three: the OBJECT is the text view, which is the whole of what a listener needs. */
extern NSString *NSTextDidBeginEditingNotification;
extern NSString *NSTextDidEndEditingNotification;
extern NSString *NSTextDidChangeNotification;

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXT_H */
