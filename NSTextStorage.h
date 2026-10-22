/*
 * NSTextStorage.h — THE EDITABLE STORE: AN ATTRIBUTED STRING THAT ANNOUNCES ITS OWN EDITS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THIS IS THE FOUNDATION OF THE TEXT-VIEW SLICE THE `NSTextView` HEADER NAMES**, and it is a FOUNDATION rather than a
 * feature: a document's characters and attributes live here, every edit announces itself, and the things that DRAW it
 * hang off the announcement. Apple's `NSTextStorage` is an `NSMutableAttributedString` — the storage IS the string, so
 * `-length`, `-string` and every attributed-string door work on it unchanged — and what it adds is an EDITING MODEL:
 * a coalescing `-beginEditing`/`-endEditing` pair, a three-value record of what changed (`-editedMask`, `-editedRange`,
 * `-changeInLength`), and one `-processEditing` at the end that tells the world.
 *
 * **THE WHOLE DESIGN IS "THE PRIMITIVES OPEN THE DOOR AND EVERYTHING ELSE WALKS THROUGH IT".** Apple's own header
 * says it: "These primitives should perform the change then call `-edited:range:changeInLength:` to get everything else
 * to happen." So `-replaceCharactersInRange:withString:` and `-setAttributes:range:` are overridden here to do exactly
 * that, and the CHARACTER mutators the base class offers (`-insertAttributedString:atIndex:`, `-deleteCharactersInRange:`,
 * `-appendAttributedString:`) reach them by DISPATCH — they were written to call a primitive, so they need no override.
 * **THE TWO ATTRIBUTE MUTATORS ARE THE EXCEPTION, AND THEY ARE OVERRIDDEN FOR THAT REASON**: Foundation's
 * `-addAttributes:range:` and `-removeAttribute:range:` edit their runs DIRECTLY, so a caller using `-addAttribute:`
 * bypassed `-setAttributes:range:` and announced nothing — MEASURED, a paragraph style that never reached its manager.
 *
 * **AND THE LAYOUT MANAGERS ARRIVED WITH THE CLASS THEY NAME.** This header used to REFUSE `-addLayoutManager:`,
 * `-removeLayoutManager:` and `-layoutManagers` — the three would have taken a class that did not exist — and
 * `NSLayoutManager` does now, so the three are here: the storage RETAINS each manager it is given, sets its
 * `-textStorage:` on the way in and clears it on the way out, and calls
 * `-textStorage:edited:range:changeInLength:invalidatedRange:` on each of them from `-processEditing`. WHAT IS STILL
 * NOT HERE: the `NSTextStorageScripting` category (it needs the whole key-value-coding scripting surface), and LAZY
 * ATTRIBUTE FIXING — `-fixesAttributesLazily` answers NO and `-invalidateAttributesInRange:` fixes at once, because
 * there is no substitution or attachment machinery here whose attributes would ever need fixing.
 */
#ifndef APPKIT_NSTEXTSTORAGE_H
#define APPKIT_NSTEXTSTORAGE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTextStorage;
@class NSLayoutManager;

/* **WHAT KIND OF EDIT HAPPENED, AS A MASK.** The two values combine — an edit may change characters AND attributes —
 * and they are the era's numbers: 1 is the ATTRIBUTES and 2 is the CHARACTERS, in that order. */
enum {
	NSTextStorageEditedAttributes = 1,
	NSTextStorageEditedCharacters = 2
};
typedef NSUInteger NSTextStorageEditActions;

/* **AND THE TWO THINGS THAT WANT TO KNOW.** A delegate that conforms is told as a METHOD; an object that would rather
 * not conform registers for the NOTIFICATION and is told by the centre — the same pair of doors every other
 * notification family in this tier offers, and both carry the same object: the STORAGE. */
@protocol NSTextStorageDelegate <NSObject>
@optional
- (void)textStorageWillProcessEditing:(NSNotification *)notification;
- (void)textStorageDidProcessEditing:(NSNotification *)notification;
@end

extern NSString *NSTextStorageWillProcessEditingNotification;
extern NSString *NSTextStorageDidProcessEditingNotification;

@interface NSTextStorage : NSMutableAttributedString
{
	/* **THE THREE FACTS ABOUT THE EDIT IN FLIGHT, WHICH ARE THE WHOLE OF THE MODEL.** The mask says WHAT changed, the
	 * range WHERE in the original string, and the delta how much the length moved; `NSNotFound` as the range's
	 * location means NOTHING has been edited, which is the state a fresh store is in and the state `-processEditing`
	 * returns it to afterwards. The count is the `-beginEditing` nesting, and `-edited:` is what consults it. */
	NSRange _editedRange;
	NSInteger _editedDelta;
	NSUInteger _editedMask;
	NSUInteger _editingCount;
	id _delegate;			/* NOT RETAINED */
	/* **AND THE MANAGERS THIS STORE TELLS, WHICH IT RETAINS AND WHICH START AS NOTHING.** Apple's own comment on
	 * `-addLayoutManager:` is "Retains & calls setTextStorage: on the item", so the list is an owning one and the
	 * manager is handed the storage by the storage itself — the pointer is never written by the manager's caller.
	 * Lazily made, because a store with no layout is the common case. */
	NSMutableArray *_layoutManagers;	/* RETAINED; made on the first add */
}

/* **THE DOOR THE PRIMITIVES CALL, AND THE ONE A SUBCLASS OVERRIDES.** It ACCUMULATES: the mask is OR-ed in, the range
 * grows to hold both the old one and the new one, and the deltas add — so a nested group of edits becomes ONE
 * `-processEditing` over the whole of what changed. It processes only when the `-beginEditing` count is zero, which is
 * what makes the pair a coalescing device rather than a pair of no-ops. */
- (void)edited:(NSUInteger)editedMask range:(NSRange)range changeInLength:(NSInteger)delta;

/* AND THE ANNOUNCEMENT ITSELF: Will, then the attribute fix, then Did, then the record is cleared. Apple's order, and
 * the reason a delegate can read `-editedRange` while it is being told. */
- (void)processEditing;

/* THE RECORD, ASKED. `-editedRange` answers `NSNotFound` for its location when nothing has been edited. */
- (NSRange)editedRange;
- (NSInteger)changeInLength;
- (NSUInteger)editedMask;

/* THE DELEGATE, NOT RETAINED — this tree's rule for every delegate. */
- (nullable id <NSTextStorageDelegate>)delegate;
- (void)setDelegate:(nullable id <NSTextStorageDelegate>)anObject;

/* **AND THE ATTRIBUTE-FIXING TRIO, OF WHICH TWO ARE HONEST NO-OPS HERE.** There is no substitution or attachment
 * machinery in this tier, so nothing is ever deferred: `-fixesAttributesLazily` is NO, `-ensureAttributesAreFixedInRange:`
 * fixes at once, and `-invalidateAttributesInRange:` is the same call under the name a subclass of Apple's would use. */
- (BOOL)fixesAttributesLazily;
- (void)ensureAttributesAreFixedInRange:(NSRange)range;
- (void)invalidateAttributesInRange:(NSRange)range;

/* **AND THE COALESCING PAIR, OVERRIDDEN SO THAT THE COUNT IS THIS CLASS'S.** The base's `-beginEditing`/`-endEditing`
 * group the ATTRIBUTE WORK; what is needed here is to know when the OUTERMOST one ends, because that is when the
 * announcement happens — one per group rather than one per edit. */
- (void)beginEditing;
- (void)endEditing;

/* ---- AND THE LAYOUT MANAGERS, WHICH THIS STORE RETAINS AND TELLS -------------------------------- */

/* **THE OTHER HALF OF APPLE'S CLASS, AND THE HALF THAT MAKES THE STORE A SUBJECT RATHER THAN A VALUE.** A manager is
 * RETAINED for as long as it is on the list (Apple's comment says so), it is handed THIS store through
 * `-setTextStorage:` on the way in and nil on the way out, and every `-processEditing` reports the edit to each of
 * them. THAT LAST CALL IS THE WHOLE WEB: it is how a change to a character reaches the thing that lays the characters
 * out, and it is why the manager's own door for it takes the two ranges the storage's record already holds. */
- (void)addLayoutManager:(NSLayoutManager *)obj;
- (void)removeLayoutManager:(NSLayoutManager *)obj;
- (nullable NSArray *)layoutManagers;

/* ============================================================================================ *
 * AND THE 10.0 DOORS, WHICH THIS TIER HAD NO ANSWER FOR UNTIL THE SWEEP.                          *
 * ============================================================================================ */
/* **THESE ARE THE PRE-ATTRIBUTE-STRING API, AND THEY ARE REAL RATHER THAN DEPRECATED STUBS.** Before an attributed
 * string had runs, a text storage was a sequence of CHARACTERS, WORDS, PARAGRAPHS or ATTRIBUTE RUNS that a caller read
 * as arrays and wrote back wholesale — and Apple kept every one of those doors when the storage became an
 * `NSMutableAttributedString`. They are implemented here over the modern primitives, which is why each is a few lines
 * and why each ANNOUNCES its edit through `-edited:range:changeInLength:` like every other mutator: a caller who uses
 * the old API gets the same notifications as one who uses the new.
 *
 * THE DECOMPOSITIONS ARE STATED RATHER THAN GUESSED, because "words" and "paragraphs" are the era's rules and not a
 * modern word breaker: WORDS are the runs between whitespace (a run of spaces, tabs and newlines separates them, and
 * nothing else does); PARAGRAPHS are the runs between newlines; CHARACTERS are one string per UTF-16 unit, which is what
 * this layer's strings ARE (see the non-ASCII note in `HANDOFF-2.md` — a literal's `-length` is its bytes here, so a
 * "character" is one unit and the door is honest about it); and ATTRIBUTE RUNS are the maximal ranges of uniform
 * attributes, read by walking `-attributesAtIndex:effectiveRange:`.
 *
 * THE SETTERS REPLACE THE WHOLE CONTENTS and the FONT and COLOUR pairs are one attribute over the whole range — Apple's
 * documented reading of `-setFont:` and `-setForegroundColor:`. */
- (nullable NSArray *)characters;
- (void)setCharacters:(nullable NSArray *)aStringArray;
- (nullable NSArray *)words;
- (void)setWords:(nullable NSArray *)aStringArray;
- (nullable NSArray *)paragraphs;
- (void)setParagraphs:(nullable NSArray *)aStringArray;
- (nullable NSArray *)attributeRuns;
- (void)setAttributeRuns:(nullable NSArray *)attributedStringArray;
- (nullable id)font;
- (void)setFont:(nullable id)aFont;
- (nullable id)foregroundColor;
- (void)setForegroundColor:(nullable id)aColor;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTSTORAGE_H */
