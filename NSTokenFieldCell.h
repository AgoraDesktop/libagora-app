/*
 * NSTokenFieldCell.h — A FIELD CELL WHOSE VALUE IS A LIST, AND WHOSE LIST IS DRAWN AS TOKENS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS IS THE FIRST ABSENT CELL TO ARRIVE, AND IT IS A FIELD CELL BEFORE IT IS ANYTHING ELSE.** Apple's
 * `NSTokenFieldCell` is an `NSTextFieldCell`: the face, the string, the edit session and the placeholder are all the
 * field cell's, and what a token cell adds is a MODEL — an array of represented objects — plus the three functions
 * that turn one representation into another (display, editing, object) and the drawing that shows the list as chips.
 * It is the same shape `NSImageView` took one slice ago: a thin subclass over a class that already owns the pixels.
 *
 * **THE MODEL IS AN ARRAY, AND THE BASE'S `-_objectValue` IS WHERE IT LIVES.** `NSCell` keeps one value per cell, and
 * for a token cell that value is the ordered list of represented objects: `-objectValue` answers it, `-setObjectValue:`
 * takes one, and `-stringValue` is the same list SPELLED AS TEXT — the display strings joined by ", ". There is no
 * second array. `NSTextFieldCell` already makes `-stringValue` a spelling of `-setObjectValue:`, and this class extends
 * that spelling rather than replacing it: a string handed to `-setObjectValue:` is TOKENIZED into the list, an array is
 * taken as the list, and a single object becomes a one-element list.
 *
 * **AND THE THREE STRINGS ARE THREE QUESTIONS, WHICH IS THE WHOLE POINT OF THE DELEGATE.** A represented object is what
 * the MODEL holds (an address book record, an `NSURL`, a document reference); the DISPLAY string is what a person reads
 * on the chip; the EDITING string is what an edit session puts in its text when the token is being changed. Without a
 * delegate all three are the same thing — the object's own text — which is why a token field over strings needs no
 * delegate at all. With one, each conversion is asked separately and the round trip (string in, object out) is the
 * delegate's to define.
 *
 * **THE DEFAULT SEPARATOR IS A COMMA AND A NEWLINE, NOT A SPACE, AND THAT IS A DELIBERATE CHOICE.** A space is part of
 * a token — "John Smith" is one address, not two — so a tokenizer that split on whitespace would make the era's own
 * address field impossible to type into. Commas and line breaks are what an address field separates on; the set is
 * named here because a caller that wants another rule supplies its own.
 *
 * WHAT THIS CLASS DELIBERATELY DOES NOT DO, NAMED AT THE DOOR RATHER THAN LEFT TO BE DISCOVERED:
 *
 *   * NO TOKEN SELECTION. There is no "selected token" in this tier, so `-copy:` on the control writes the WHOLE list
 *     and `-cut:` clears it; a person cannot copy one chip. The list is still the unit a pasteboard round trip carries.
 *   * NO COMPLETION LIST UI. When `-completionDelay` is non-negative the cell ASKS the delegate for completions on
 *     every change and inserts a UNIQUE one, selecting the appended letters; a menu of several offers is the missing
 *     half, and a delegate that answers more than one gets no insertion rather than a silent first choice. A NEGATIVE
 *     delay disables the question entirely, which is the flag's reader.
 *   * NO TOKEN DRAGGING OR PILL ANIMATION. Chips are drawn, not moved or animated; this tier has no token drag session.
 */
#ifndef APPKIT_NSTOKENFIELDCELL_H
#define APPKIT_NSTOKENFIELDCELL_H

#import <AppKit/NSTextFieldCell.h>

@class NSCharacterSet;
@class NSMenu;
@class NSPasteboard;

NS_ASSUME_NONNULL_BEGIN

/* **THE THREE WAYS A TOKEN IS DRAWN, WHICH IS APPLE'S OWN VOCABULARY AND NOT A CELL'S.** `NSDefaultTokenStyle` is the
 * style a token field uses unless told otherwise (a rounded chip in the era); `NSRoundedTokenStyle` is that chip named
 * explicitly; and `NSPlainTextTokenStyle` is a token drawn as words with NO background, for data that reads better as
 * running text than as a badge. The drawing is the only reader, and the delegate may choose a style PER TOKEN, which is
 * why the cell asks rather than reading its own field at every chip. */
enum {
	NSDefaultTokenStyle = 0,
	NSPlainTextTokenStyle = 1,
	NSRoundedTokenStyle = 2
};
typedef NSUInteger NSTokenStyle;

@protocol NSTokenFieldCellDelegate;

@interface NSTokenFieldCell : NSTextFieldCell
{
	/* **THE SEPARATOR, WHICH IS THE ONLY THING TOKENIZING NEEDS AND THE ONLY THING A CALLER MAY CHANGE.** Copied on the
	 * way in, because a caller that keeps a mutable set and edits it later must not change how this cell parses. nil
	 * means the class default, which is also what a decoded cell with no archived set answers. */
	NSCharacterSet *_tokenizingCharacterSet;	/* RETAINED (a copy) */
	/* **THE DELEGATE IS THE CONVERSIONS' DELEGATE, NOT THE SESSION'S.** `NSTextFieldCell` already has an
	 * `_editorDelegate` for the object a session reports to; this is the object that answers the token questions. For a
	 * cell inside an `NSTokenField`, this is THE FIELD, and the field forwards to the caller — the relay `NSComboBox`
	 * established, one class over. NOT RETAINED, this tree's rule for every delegate. */
	id _delegate;					/* NOT RETAINED */
	/* **AND THE COMPLETION DELAY, WHICH IS ALSO A SWITCH.** Zero or positive enables completion (the era's default is
	 * 0.0 — immediate); negative disables it. This tier has no timer, so a positive value is stored and answered and the
	 * question is asked on a change rather than after a pause — named here rather than implied. */
	NSTimeInterval _completionDelay;
	/* **AND THE STYLE A TOKEN GETS WHEN THE DELEGATE HAS NO OPINION.** The delegate's answer wins per token; this is the
	 * fallback, and it is what `-tokenStyle` names. */
	NSTokenStyle _tokenStyle;
	/* **AND WHETHER THE CELL ITSELF IS WRITING THE EDITOR, WHICH THE COMPLETION PATH HAS TO KNOW.** The ending writes
	 * the committed list back into the cell, and opening a session seeds the editor; both announce a change, so without
	 * this flag the completion pass could run on text the cell itself just wrote — or while the editor is being removed. */
	BOOL _cg_quiet;
}

/* ---- THE TOKEN STYLE AND THE SEPARATOR ------------------------------------------------------------- */

/* **THE STYLE IS THE PER-TOKEN DEFAULT, NOT A PROMISE ABOUT EVERY CHIP.** `-cg_styleForRepresentedObject:` asks the
 * delegate first (Apple's rule: `-tokenFieldCell:styleForRepresentedObject:` wins over `-tokenStyle`), so a list may mix
 * badges and plain words. This pair is stored, answered, and read by the drawing when the delegate says nothing. */
- (void)setTokenStyle:(NSTokenStyle)style;
- (NSTokenStyle)tokenStyle;

/* **THE SEPARATOR IS THE SET A TYPED STRING IS SPLIT ON, AND IT IS COPIED.** The class default is a comma and a newline;
 * a space is deliberately NOT in it (see the header's note), so "John Smith" survives as one token. A caller who wants
 * semicolons or pipes supplies the set and gets a tokenizer that honours it in both directions — `-setStringValue:` and
 * the commit of an edit session both split on this set. */
- (void)setTokenizingCharacterSet:(nullable NSCharacterSet *)characterSet;
- (nullable NSCharacterSet *)tokenizingCharacterSet;
+ (NSCharacterSet *)defaultTokenizingCharacterSet;

/* ---- THE COMPLETION DELAY, WHICH IS THE COMPLETION SWITCH ------------------------------------------ */

/* **A NEGATIVE DELAY IS THE OFF SWITCH AND A NON-NEGATIVE ONE IS A REAL QUESTION.** With completion enabled the cell asks
 * its delegate for completions on every change to a partial token and inserts a UNIQUE answer, selecting the appended
 * letters so the next keystroke replaces the offer. There is no pop-up list in this tier and no timer: a positive delay
 * round-trips and is what a timer would use, while the question is asked at the change. `+defaultCompletionDelay`
 * answers the era's 0.0. */
- (void)setCompletionDelay:(NSTimeInterval)delay;
- (NSTimeInterval)completionDelay;
+ (NSTimeInterval)defaultCompletionDelay;

/* ---- THE DELEGATE ----------------------------------------------------------------------------------- */

/* THE CONVERSIONS' DELEGATE: display, editing, represented object, the style, the add review, the pasteboard pair and
 * the per-token menu. `NSTokenField` installs itself here and forwards to its own delegate; a standalone cell may be
 * given a delegate directly, and then the `tokenFieldCell:` spellings are what it is sent. */
- (void)setDelegate:(nullable id <NSTokenFieldCellDelegate>)anObject;
- (nullable id <NSTokenFieldCellDelegate>)delegate;

/* ---- THE MODEL, SPELLED AS TEXT --------------------------------------------------------------------- */

/* **`-stringValue` IS THE DISPLAY LIST JOINED BY ", ", AND `-setStringValue:` IS THAT SPELLING READ BACK.** The base
 * class makes the latter a call to `-setObjectValue:`; so does this class, with a string TOKENIZED first. An EMPTY list
 * answers an empty string (not nil): a token field with no tokens is a field with nothing in it, and the placeholder is
 * what an empty field shows. */
- (void)setStringValue:(nullable NSString *)aString;
- (nullable NSString *)stringValue;

/* **AND THE SAME LIST AS THE EDITING STRINGS, WHICH IS WHAT AN OPEN SESSION SHOWS.** A session on a token field does not
 * edit the display text: it edits the EDITING text, so the delegate's `-tokenFieldCell:editingStringForRepresentedObject:`
 * has a reader. The session is opened by the base class, which seeds the editor from `-stringValue:`; this class replaces
 * that seed after the session opens and selects the whole run, because a token's range in the display text is not a
 * token's range in the editing text. */
- (nullable NSString *)cg_editingText;

/* ---- THE LIST, PROGRAMMATICALLY --------------------------------------------------------------------- */

/* **`-objectValue`/`-setObjectValue:` ARE THE LIST, AND THEY ACCEPT THREE SHAPES.** An array is the list of represented
 * objects; a string is tokenized (which is what makes `-setStringValue:` work); any other object becomes a one-token
 * list; nil empties it. A FRESH CELL ANSWERS AN EMPTY ARRAY rather than nil, so a caller may enumerate without a test. */
- (nullable id)objectValue;
- (void)setObjectValue:(nullable id)value;

/* ---- THE DRAWING'S TWO PRIVATE FACTS, EXPOSED FOR THE CONTROL --------------------------------------- */

/* **A CHIP'S RECTANGLE IS THE THING A POINT CAN BE TESTED AGAINST, AND IT IS THE SAME LAYOUT THE DRAWING USES.**
 * `-cg_tokenIndexAtPoint:inFrame:` answers the index of the token whose chip (or, for a plain token, whose text) contains
 * the point, or `NSNotFound`; the control's `-menuForEvent:` uses it to find which token a right-click named. It is a
 * door rather than arithmetic repeated in the control because the layout must be the drawing's own. */
- (NSInteger)cg_tokenIndexAtPoint:(NSPoint)point inFrame:(NSRect)frame;

/* **AND THE MENU IS THE DELEGATE'S, ASKED ONLY FOR A TOKEN THAT HAS ONE.** `-cg_menuForRepresentedObjectAtIndex:`
 * answers nil for an out-of-range index, for a delegate that does not implement the menu door, and for a token its
 * `-tokenFieldCell:hasMenuForRepresentedObject:` answers NO for. A nil answer is the whole instruction: no menu. */
- (nullable NSMenu *)cg_menuForRepresentedObjectAtIndex:(NSInteger)index;

/* ---- THE PASTEBOARD, WHICH IS HOW A WHOLE LIST MOVES ------------------------------------------------- */

/* **COPY WRITES THE EDITING STRINGS AND THEN GIVES THE DELEGATE THE CHANCE TO REPLACE THEM.** Apple's order, and the
 * reason it is that order: a delegate that knows a richer pasteboard type (a vCard, a file URL) can add it, while a
 * caller with no delegate still gets a useful string. A delegate that answers NO REMOVES the default write and the door
 * answers NO — an empty pasteboard rather than a misleading one. */
- (BOOL)cg_writeTokensToPasteboard:(NSPasteboard *)pboard;

/* **AND PASTE ASKS THE DELEGATE FIRST AND FALLS BACK TO THE STRING.** A delegate that implements
 * `-tokenFieldCell:readFromPasteboard:` supplies the objects; a nil answer, or no implementation, reads the pasteboard's
 * string and tokenizes it with this cell's set. Every added object passes the same `-shouldAddObjects:atIndex:` review a
 * typed token does, and the answer is whether anything was added. */
- (BOOL)cg_readTokensFromPasteboard:(NSPasteboard *)pboard;

/* **AND CUT'S SECOND HALF, WHICH IS THE ONLY WAY TO EMPTY THE LIST BY COMMAND.** */
- (void)cg_removeAllRepresentedObjects;

@end

/* **AND THE CELL'S PROTOCOL, WHOSE METHODS ARE ALL OPTIONAL AND WHOSE DEFAULTS ARE ALL "THE OBJECT ITSELF".** Apple's
 * contract, quoted in this class's own words: a delegate that returns nil for a conversion, or does not implement it,
 * gets the identity behaviour (editing string = display string = represented object). A conversion that answers nil is
 * therefore NOT an error; it is "no opinion". `-shouldAddObjects:atIndex:` is the exception: an EMPTY array rejects the
 * addition and nil is Apple's error case, which this tier treats as a rejection and names at the door.
 *
 * The cell SENDS each of these, and the senders are: the drawing (display string, style), the commit of a session and
 * `-setObjectValue:` with a string (represented object, editing string), a typed or pasted addition (shouldAdd, paste,
 * the menu pair), and the per-change completion pass (completions). */
@protocol NSTokenFieldCellDelegate <NSObject>

@optional

/* Each element of the answer is an `NSString` or an array of `NSString`s; `substring` is the partial token being
 * completed and `tokenIndex` is its index in the list. `selectedIndex` may be set to name the offer to select. This tier
 * has no list UI: a UNIQUE offer longer than the substring is inserted, and several offers insert nothing. */
- (nullable NSArray *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
	     completionsForSubstring:(NSString *)substring
			indexOfToken:(NSInteger)tokenIndex
	     indexOfSelectedItem:(nullable NSInteger *)selectedIndex;

/* The review of an addition. The answer is the objects to add; an EMPTY array rejects all of them. nil is Apple's error
 * case, and this tier refuses the addition rather than guessing. */
- (nullable NSArray *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
		     shouldAddObjects:(NSArray *)tokens
			     atIndex:(NSUInteger)index;

/* The three conversions. nil means "no opinion", and the fallback is the object's own text. */
- (nullable NSString *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     displayStringForRepresentedObject:(id)representedObject;
- (nullable NSString *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     editingStringForRepresentedObject:(id)representedObject;
- (nullable id)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     representedObjectForEditingString:(NSString *)editingString;

/* The pasteboard pair. The write door is called AFTER the default string write, so a YES answer keeps both; a NO answer
 * clears the board. The read door supplies the objects, and nil falls back to the string. */
- (BOOL)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     writeRepresentedObjects:(NSArray *)objects
	       toPasteboard:(NSPasteboard *)pboard;
- (nullable NSArray *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
	       readFromPasteboard:(NSPasteboard *)pboard;

/* The per-token menu. `-hasMenuForRepresentedObject:` is asked first and NO means no menu; an implementation of the menu
 * door alone is treated as YES. */
- (nullable NSMenu *)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     menuForRepresentedObject:(id)representedObject;
- (BOOL)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     hasMenuForRepresentedObject:(id)representedObject;

/* The per-token style, which wins over the cell's `-tokenStyle`. */
- (NSTokenStyle)tokenFieldCell:(NSTokenFieldCell *)tokenFieldCell
     styleForRepresentedObject:(id)representedObject;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTOKENFIELDCELL_H */
