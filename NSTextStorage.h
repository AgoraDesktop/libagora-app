/*
 * NSTextStorage.h — THE EDITABLE STORE: AN ATTRIBUTED STRING THAT ANNOUNCES ITS OWN EDITS.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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
 * that, and every other mutator the base class offers (`-insertAttributedString:atIndex:`, `-deleteCharactersInRange:`,
 * `-appendAttributedString:`) reaches them by DISPATCH — it does not need to be overridden, because it was written to
 * call a primitive and this class IS the primitive's implementation.
 *
 * **WHAT IS NOT HERE, NAMED RATHER THAN STUBBED: THE LAYOUT MANAGERS.** `-addLayoutManager:`, `-removeLayoutManager:`
 * and `-layoutManagers` are the other half of Apple's class and they need `NSLayoutManager`, which this tier has not
 * built — and a door that took a class that does not exist would be a declaration with nothing behind it. The
 * `NSTextStorageScripting` category is likewise out (it needs the whole key-value-coding scripting surface), and so is
 * LAZY ATTRIBUTE FIXING: `-fixesAttributesLazily` answers NO and `-invalidateAttributesInRange:` fixes at once,
 * because there is no substitution or attachment machinery here whose attributes would ever need fixing.
 */
#ifndef APPKIT_NSTEXTSTORAGE_H
#define APPKIT_NSTEXTSTORAGE_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSTextStorage;

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

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTEXTSTORAGE_H */
