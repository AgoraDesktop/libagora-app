/*
 * NSTextStorage.m — an attributed string that says what was edited, and coalesces until it is asked.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE TWO OVERRIDES UNDER "THE PRIMITIVES" ARE THE CLASS.** Apple's header states the contract in one sentence —
 * "These primitives should perform the change then call `-edited:range:changeInLength:` to get everything else to
 * happen" — and everything else in this file is the accumulation, the coalescing, and the announcement. NOTHING here
 * walks the string: the base class holds the characters and the attributes, this class holds THE RECORD of what
 * happened to them, and the two are one object because Apple's storage IS an `NSMutableAttributedString`.
 */
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSDictionary.h>

NSString *NSTextStorageWillProcessEditingNotification = @"NSTextStorageWillProcessEditingNotification";
NSString *NSTextStorageDidProcessEditingNotification = @"NSTextStorageDidProcessEditingNotification";

@implementation NSTextStorage

/* **EVERY WAY IN SETS THE RECORD TO "NOTHING HAS BEEN EDITED", WHICH IS `NSNotFound` AND NOT ZERO.** Zero is a real
 * location — the first character — so a store that started with `{0, 0}` would answer "an edit happened at the start"
 * before anybody had touched it. */
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_editedRange = NSMakeRange(NSNotFound, 0);
	}
	return self;
}

- (instancetype)initWithString:(NSString *)str
{
	self = [super initWithString:str];
	if (self != nil) {
		_editedRange = NSMakeRange(NSNotFound, 0);
	}
	return self;
}

- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary *)attrs
{
	self = [super initWithString:str attributes:attrs];
	if (self != nil) {
		_editedRange = NSMakeRange(NSNotFound, 0);
	}
	return self;
}

- (void)dealloc
{
	[_layoutManagers release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE LAYOUT MANAGERS, WHICH THIS STORE RETAINS AND TELLS                                     *
 * ============================================================================================ */

/* **THE STORE HANDS ITSELF TO THE MANAGER, WHICH IS THE DIRECTION APPLE'S COMMENT GIVES.** "Retains & calls
 * setTextStorage: on the item" — so the list owns the manager and the manager's pointer to the store is written BY the
 * store, never by a caller. That is what makes the two objects' holdings impossible to get out of step: a manager on a
 * list has that list's store, and one taken off has nil. */
- (void)addLayoutManager:(NSLayoutManager *)obj
{
	if (obj == nil) {
		return;
	}
	if (_layoutManagers == nil) {
		_layoutManagers = [[NSMutableArray alloc] init];
	}
	if (![_layoutManagers containsObject:obj]) {
		[_layoutManagers addObject:obj];
		[obj setTextStorage:self];
	}
}

- (void)removeLayoutManager:(NSLayoutManager *)obj
{
	if (obj == nil || _layoutManagers == nil) {
		return;
	}
	if ([_layoutManagers containsObject:obj]) {
		[obj setTextStorage:nil];
		[_layoutManagers removeObject:obj];
	}
}

/* AN EMPTY ARRAY WHEN THERE ARE NONE is Apple's answer for a store with no layout, and not nil: a caller that asks how
 * many managers there are can count it either way, and one that iterates it gets no iterations rather than a crash. */
- (NSArray *)layoutManagers
{
	return (_layoutManagers != nil) ? [[_layoutManagers copy] autorelease] : [NSArray array];
}

- (id <NSTextStorageDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSTextStorageDelegate>)anObject
{
	/* NOT RETAINED, and not released on the way out: this tree's rule for every delegate. */
	_delegate = anObject;
}

/* ============================================================================================ *
 * THE RECORD, ASKED                                                                             *
 * ============================================================================================ */

- (NSRange)editedRange
{
	return _editedRange;
}

- (NSInteger)changeInLength
{
	return _editedDelta;
}

- (NSUInteger)editedMask
{
	return _editedMask;
}

/* ============================================================================================ *
 * THE PRIMITIVES: DO THE EDIT, THEN SAY SO                                                       *
 * ============================================================================================ */

/* **AND THESE TWO ARE WHY THE REST OF THE BASE CLASS NEEDS NO OVERRIDES.** Every other mutator an attributed string
 * offers — `-insertAttributedString:atIndex:`, `-deleteCharactersInRange:`, `-appendAttributedString:` — was written to
 * change the storage through ONE of these, so a store that overrides them is announced to by all of them by DISPATCH
 * rather than by a copy of the bookkeeping per door. THE DELTA IS THE REPLACEMENT'S LENGTH LESS THE REPLACED RANGE's,
 * which is the only arithmetic here: the range is the one in the ORIGINAL string, because that is what Apple's own
 * contract says the record holds. */
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str
{
	[super replaceCharactersInRange:range withString:str];
	[self edited:NSTextStorageEditedCharacters range:range
	     changeInLength:(NSInteger)[str length] - (NSInteger)range.length];
}

- (void)replaceCharactersInRange:(NSRange)range withAttributedString:(NSAttributedString *)attrString
{
	[super replaceCharactersInRange:range withAttributedString:attrString];
	[self edited:NSTextStorageEditedCharacters range:range
	     changeInLength:(NSInteger)[attrString length] - (NSInteger)range.length];
}

/* AN ATTRIBUTE EDIT MOVES NO CHARACTERS, so the delta is zero and the mask says which kind of change it was — which is
 * the whole reason the mask exists: a layout manager redraws for either, but a character-count change is not one. */
- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range
{
	[super setAttributes:attrs range:range];
	[self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

/* ============================================================================================ *
 * THE ACCUMULATION, AND THE COALESCING                                                            *
 * ============================================================================================ */

/* **ONE EDIT IS A MASK, A RANGE AND A NUMBER, AND A GROUP OF THEM IS THE UNION OF ALL THREE.** The mask is OR-ed in,
 * because a group that changed characters and then attributes changed BOTH — the flag a listener reads is "what kinds
 * of change are in here", not "what happened last". The deltas add, because the length moved by the sum of them, and a
 * listener told about either end has to be told about everything between.
 *
 * **AND THE RANGES ARE BROUGHT BACK TO THE ORIGINAL STRING'S COORDINATES BEFORE THEY ARE UNIONED.** Apple's contract is
 * that the record holds "the range in the ORIGINAL string", and a SECOND edit's range was measured against a string the
 * FIRST one had already moved — so the running delta is taken back off its location. Without that, editing the top of a
 * document and then its middle would union two ranges from two different coordinate systems and report a span that
 * covers neither. A location pushed below zero is clamped, because a caller's range cannot be before the document. */
- (void)edited:(NSUInteger)editedMask range:(NSRange)range changeInLength:(NSInteger)delta
{
	NSInteger location = (NSInteger)range.location - _editedDelta;

	if (location < 0) {
		location = 0;
	}
	_editedMask |= editedMask;
	if (_editedRange.location == NSNotFound) {
		_editedRange = NSMakeRange((NSUInteger)location, range.length);
	} else {
		NSInteger lo = ((NSInteger)_editedRange.location < location) ? (NSInteger)_editedRange.location : location;
		NSInteger a = (NSInteger)_editedRange.location + (NSInteger)_editedRange.length;
		NSInteger b = location + (NSInteger)range.length;

		_editedRange = NSMakeRange((NSUInteger)lo, (NSUInteger)(((a > b) ? a : b) - lo));
	}
	_editedDelta += delta;
	/* **AND IT PROCESSES ONLY WHEN NOBODY IS STILL EDITING**, which is the whole of what `-beginEditing` buys: an
	 * editor that brackets a paragraph's worth of changes gets ONE announcement, and a listener never sees a document
	 * that is half-changed. */
	if (_editingCount == 0) {
		[self processEditing];
	}
}

- (void)beginEditing
{
	[super beginEditing];
	_editingCount++;
}

- (void)endEditing
{
	[super endEditing];
	if (_editingCount > 0) {
		_editingCount--;
	}
	if (_editingCount == 0) {
		[self processEditing];
	}
}

/* ============================================================================================ *
 * THE ANNOUNCEMENT, IN APPLE'S ORDER                                                             *
 * ============================================================================================ */

/* **WILL, THEN THE FIX, THEN DID, THEN THE RECORD IS CLEARED** — and the ORDER is what lets a delegate read
 * `-editedRange`, `-editedMask` and `-changeInLength` while it is being told: all four facts are still there when the
 * two callbacks run, and the store is back to "nothing edited" the moment the last listener has been told. The
 * notification goes to the centre FIRST and the delegate SECOND, which is the shape this tree's other announcement
 * doors use (`NSText`'s `fn_announce`), so an object that registers and an object that conforms cannot disagree about
 * whether something happened. */
- (void)processEditing
{
	NSNotification *note;

	if (_editingCount > 0) {
		return;		/* somebody is still editing; the outermost `-endEditing:` will call this */
	}
	note = [NSNotification notificationWithName:NSTextStorageWillProcessEditingNotification object:self];
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(textStorageWillProcessEditing:)]) {
		[_delegate textStorageWillProcessEditing:note];
	}
	[self fixAttributesInRange:_editedRange];
	note = [NSNotification notificationWithName:NSTextStorageDidProcessEditingNotification object:self];
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(textStorageDidProcessEditing:)]) {
		[_delegate textStorageDidProcessEditing:note];
	}
	/* **AND THE MANAGERS, WHICH IS THE WHOLE WEB AND THE REASON A STORE IS A SUBJECT RATHER THAN A VALUE.** Each is
	 * handed the two ranges Apple's header describes — the OLD one the storage's record holds, and the one that
	 * changed in the NEW string, which is the old one grown by the delta because with no attribute fixing nothing can
	 * have widened it — plus the MASK, so a manager that one day cares about attributes as well as characters is told
	 * which kind of change it is looking at. THE RECORD IS STILL STANDING here: a manager that reads the store's own
	 * `-editedRange` while it is being told gets the edit and not NSNotFound. */
	if (_layoutManagers != nil && _editedRange.location != NSNotFound) {
		NSInteger grown = (NSInteger)_editedRange.length + _editedDelta;
		NSRange newRange = NSMakeRange(_editedRange.location, (grown > 0) ? (NSUInteger)grown : 0);
		NSUInteger i;

		for (i = 0; i < [_layoutManagers count]; i++) {
			NSLayoutManager *manager = [_layoutManagers objectAtIndex:i];

			[manager textStorage:self edited:_editedMask range:_editedRange
			     changeInLength:_editedDelta invalidatedRange:newRange];
		}
	}
	_editedMask = 0;
	_editedDelta = 0;
	_editedRange = NSMakeRange(NSNotFound, 0);
}

/* ============================================================================================ *
 * AND THE ATTRIBUTE FIXING, WHICH HAS NOTHING TO DO HERE                                          *
 * ============================================================================================ */

/* **NOT LAZY, BECAUSE THERE IS NOTHING THAT WOULD BE DEFERRED.** Apple's laziness exists so a large document does not
 * re-scan for substitutions and attachments on every keystroke; this tier has neither, so `-fixAttributesInRange:` is
 * the base class's (which does the work it has) and the three doors below are one call under two names plus a NO. */
- (BOOL)fixesAttributesLazily
{
	return NO;
}

- (void)ensureAttributesAreFixedInRange:(NSRange)range
{
	[self fixAttributesInRange:range];
}

- (void)invalidateAttributesInRange:(NSRange)range
{
	[self fixAttributesInRange:range];
}

@end
