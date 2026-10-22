/*
 * NSTextStorage.m — an attributed string that says what was edited, and coalesces until it is asked.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
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
#import <AppKit/NSAttributedString.h>	/* NSFontAttributeName and its foreground sibling */

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

/* **AND THE TWO ATTRIBUTE MUTATORS FOUNDATION DOES NOT ROUTE THROUGH `-setAttributes:range:`.** The override above
 * catches a caller that sets a whole dictionary, but Foundation's `-addAttributes:range:` and `-removeAttribute:range:`
 * edit their runs DIRECTLY — so an attribute edit made with `-addAttribute:value:range:` announced NOTHING, and a
 * paragraph style put into a store that way never reached its layout manager. MEASURED, which is how this was found:
 * a centred style left every line at the left margin because the manager was never told the layout was stale.
 * `-addAttribute:` itself is covered by the first override below, because Foundation's own implementation calls
 * `-addAttributes:range:` on SELF, which dispatches here. */
- (void)addAttributes:(NSDictionary *)attrs range:(NSRange)range
{
	[super addAttributes:attrs range:range];
	[self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

- (void)removeAttribute:(NSString *)name range:(NSRange)range
{
	[super removeAttribute:name range:range];
	[self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}

/* ============================================================================================ *
 * THE 10.0 DOORS: CHARACTERS, WORDS, PARAGRAPHS, RUNS, AND THE TWO WHOLE-RANGE ATTRIBUTES.        *
 * ============================================================================================ */

/* **ONE PRIVATE DOOR FOR "REPLACE EVERYTHING", BECAUSE FOUR SETTERS DO EXACTLY THAT.** Apple's old setters all replace
 * the receiver's contents wholesale, so the only difference between them is how the array becomes a string — and routing
 * all four through one `-replaceCharactersInRange:withString:` is what makes them announce like any other edit rather
 * than each doing its own bookkeeping. */
- (void)fn_replaceContentsWithString:(NSString *)replacement
{
	NSString *text = (replacement != nil) ? replacement : @"";

	[self replaceCharactersInRange:NSMakeRange(0, [self length]) withString:text];
	/* AND THE ATTRIBUTES GO WITH THE CHARACTERS, because a wholesale replacement is a new document: an old font left
	 * over the new string's first character would be a run nobody asked for. The setter's caller applies its own. */
	[self setAttributes:[NSDictionary dictionary] range:NSMakeRange(0, [self length])];
}

- (NSArray *)characters
{
	NSUInteger length = [self length];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:length];
	NSUInteger i;

	for (i = 0; i < length; i++) {
		[out addObject:[[self string] substringWithRange:NSMakeRange(i, 1)]];
	}
	return out;
}

- (void)setCharacters:(NSArray *)aStringArray
{
	NSMutableString *joined = [NSMutableString string];
	NSUInteger i;

	for (i = 0; i < [aStringArray count]; i++) {
		id piece = [aStringArray objectAtIndex:i];

		[joined appendString:([piece isKindOfClass:[NSString class]] ? (NSString *)piece : [piece description])];
	}
	[self fn_replaceContentsWithString:joined];
}

/* THE ERA'S WORD RULE, IN ONE PASS: a word ends at whitespace, and a RUN of whitespace is one separator rather than
 * several empty words. That is what a caller of `-words` expects — an empty string between two spaces is not a word. */
- (NSArray *)words
{
	NSString *text = [self string];
	NSMutableArray *out = [NSMutableArray array];
	NSUInteger length = [text length];
	NSUInteger start = 0;
	BOOL inWord = NO;
	NSUInteger i;

	for (i = 0; i <= length; i++) {
		BOOL space = (i == length);
		unichar c = 0;

		if (!space) {
			c = [text characterAtIndex:i];
			space = (c == ' ' || c == '\t' || c == '\n' || c == '\r');
		}
		if (!space && !inWord) {
			start = i;
			inWord = YES;
		} else if (space && inWord) {
			[out addObject:[text substringWithRange:NSMakeRange(start, i - start)]];
			inWord = NO;
		}
	}
	return out;
}

- (void)setWords:(NSArray *)aStringArray
{
	[self fn_replaceContentsWithString:[aStringArray componentsJoinedByString:@" "]];
}

- (NSArray *)paragraphs
{
	return [[self string] componentsSeparatedByString:@"\n"];
}

- (void)setParagraphs:(NSArray *)aStringArray
{
	[self fn_replaceContentsWithString:[aStringArray componentsJoinedByString:@"\n"]];
}

/* **AND THE RUNS ARE READ, NOT REMEMBERED.** A run is the maximal range whose attributes are uniform, which is exactly
 * what `-attributesAtIndex:effectiveRange:` answers — so this door is a walk over the store and cannot disagree with the
 * attributes a caller set, which a cached array would. */
- (NSArray *)attributeRuns
{
	NSMutableArray *out = [NSMutableArray array];
	NSUInteger length = [self length];
	NSUInteger location = 0;

	while (location < length) {
		NSRange run = NSMakeRange(0, 0);
		NSDictionary *attributes = [self attributesAtIndex:location effectiveRange:&run];

		if (run.length == 0) {
			break;	/* a store that answers no run would loop forever; one step and out */
		}
		[out addObject:[[[NSAttributedString alloc] initWithString:
				[[self string] substringWithRange:run] attributes:attributes] autorelease]];
		location = NSMaxRange(run);
	}
	return out;
}

- (void)setAttributeRuns:(NSArray *)attributedStringArray
{
	NSMutableAttributedString *assembled = [[NSMutableAttributedString alloc] init];
	NSUInteger i;

	for (i = 0; i < [attributedStringArray count]; i++) {
		id piece = [attributedStringArray objectAtIndex:i];

		if (![piece isKindOfClass:[NSAttributedString class]]) {
			continue;
		}
		[assembled appendAttributedString:piece];
	}
	[self setAttributedString:assembled];
	[assembled release];
}

/* THE TWO WHOLE-RANGE ATTRIBUTES. Apple's `-font` answers the font at the START of the text; a store with no characters
 * has none. The setter applies to every character, which is the era's reading of a storage-wide font. */
- (id)font
{
	if ([self length] == 0) {
		return nil;
	}
	return [[self attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSFontAttributeName];
}

- (void)setFont:(id)aFont
{
	NSRange all = NSMakeRange(0, [self length]);

	if (all.length == 0) {
		return;
	}
	if (aFont == nil) {
		[self removeAttribute:NSFontAttributeName range:all];
	} else {
		[self addAttribute:NSFontAttributeName value:aFont range:all];
	}
}

- (id)foregroundColor
{
	if ([self length] == 0) {
		return nil;
	}
	return [[self attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSForegroundColorAttributeName];
}

- (void)setForegroundColor:(id)aColor
{
	NSRange all = NSMakeRange(0, [self length]);

	if (all.length == 0) {
		return;
	}
	if (aColor == nil) {
		[self removeAttribute:NSForegroundColorAttributeName range:all];
	} else {
		[self addAttribute:NSForegroundColorAttributeName value:aColor range:all];
	}
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
