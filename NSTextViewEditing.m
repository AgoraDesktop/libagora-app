/*
 * NSTextViewEditing.m — what typing does around it: the smart space, the smart delete, and the undo group.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THIS IS A CATEGORY OF ITS OWN BECAUSE `NSTextView.m` IS OVER TWO THOUSAND LINES**, which is the rule `HANDOFF-4.md`
 * §5 states: a deep class lands in a category file of its own, the way `NSTextViewAttributes.m` and
 * `NSTextViewPasteboard.m` did. The private doors this file asks of the main file are declared in a `(Private)`
 * category below, and the two doors IT offers the main file — the smart insertion and the undo registration — are
 * declared the same way, once here and once at the top of `NSTextView.m`, so the two files cannot disagree about them.
 *
 * **THE SPLIT IS BY SUBJECT RATHER THAN BY SIZE.** Smart insert (the space two words would otherwise lose), smart
 * delete (the whitespace a deletion would otherwise leave doubled) and the undo group (what one `-undo` takes back) are
 * one subject: they are all answers to "what does an edit do BESIDES replace a range", and every one of them is a
 * decision the edit path asks this file for. The edit path itself — the primitive, `-insertText:` and `-didChangeText` —
 * stays in `NSTextView.m` where the store is written.
 *
 * **WHAT THE ERA DOES AND WHAT THIS TIER DOES DIFFER IN ONE PLACE, SAID PLAINLY.** Apple's text view leans on
 * `NSUndoManager`'s EVENT-DRIVEN grouping to decide where a typing run ends; this Foundation's manager has no event
 * grouping (its own header says so: groups are opened by a registration and closed by an explicit `-endUndoGrouping`, or
 * by `-undo` itself). So the view keeps the one fact that answers the same question — WHERE THE PREVIOUS EDIT FINISHED,
 * in `_cg_lastEditEnd` — and an edit that is not adjacent to it closes the open group. The observable behaviour is the
 * era's: a typed word is one undo, a run of backspaces is one undo, and a keystroke somewhere else starts a new one.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/NSUndoManager.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>

/* THE MAIN FILE'S PRIVATE DOORS, ASKED OF IT BY NAME — see the file comment. */
@interface NSTextView (AGEditingPrivate)
- (BOOL)cg_isWordCharacter:(unichar)character;
- (NSString *)cg_textWithSmartInsertionForString:(NSString *)text range:(NSRange)range;
- (void)cg_noteEditInRange:(NSRange)range
	      insertedText:(NSString *)inserted
	      replacedText:(NSString *)replaced;
@end

/* THE TWO KEYS THE UNDO ACTION CARRIES. A dictionary rather than a private class: the action is a range and a string,
 * and an object with two fields would be a class whose only method is its own encoding. */
static NSString * const AGUndoRangeKey = @"AGUndoRange";
static NSString * const AGUndoStringKey = @"AGUndoString";

/* ==================================================================================================================
 * THE WORD EDGE, WHICH IS ASCII AND SAYS SO.
 *
 * **THE PREDICATE IS LETTER, DIGIT OR UNDERSCORE — the same set `NSText`'s word movement uses**, and the same deviation
 * `HANDOFF-2.md` §4 records for this tree's strings: a NON-ASCII letter is not a word character here, because the word
 * arithmetic this class inherits is byte-oriented. A smart space around an accented word is therefore the one place a
 * reader would notice, and it is stated rather than discovered.
 * ================================================================================================================ */
static BOOL fn_is_word(unichar c)
{
	return (c == '_')
		|| (c >= '0' && c <= '9')
		|| (c >= 'a' && c <= 'z')
		|| (c >= 'A' && c <= 'Z');
}

/* SPACES AND TABS ARE WHAT A DELETION LEAVES DOUBLED. A NEWLINE IS NOT: it is a paragraph break, and absorbing one
 * would join two paragraphs into one, which is a bigger change than the deletion asked for. */
static BOOL fn_is_gap(unichar c)
{
	return (c == ' ') || (c == '\t');
}

@implementation NSTextView (AGEditing)

/* ============================================================================================ *
 * SMART INSERT: THE SPACE THAT TWO WORDS WOULD OTHERWISE LOSE                                   *
 * ============================================================================================ */

- (BOOL)smartInsertDeleteEnabled
{
	return _cg_smartInsertDelete;
}

/* **TURNING IT OFF MID-RUN ENDS THE RUN**, for the same reason `-setAllowsUndo:NO` ends an undo group: the state that
 * the next edit would have joined no longer exists, and leaving the boundary behind would make the next placement
 * decide against a fact the caller has just withdrawn. */
- (void)setSmartInsertDeleteEnabled:(BOOL)flag
{
	if (flag == _cg_smartInsertDelete) {
		return;
	}
	_cg_smartInsertDelete = flag;
	if (!flag) {
		_cg_lastEditEnd = NSNotFound;
	}
}

- (void)toggleSmartInsertDelete:(id)sender
{
	(void)sender;
	[self setSmartInsertDeleteEnabled:![self smartInsertDeleteEnabled]];
}

/* **THE WHOLE DOOR ANSWERS BOTH HALVES AT ONCE, AND IT IS THE ONE `-insertText:` ASKS.** A caller that only wants to
 * know whether a space would be added asks either half; a caller that is about to insert asks this and gets both, which
 * is why this one exists rather than the halves being enough. */
- (void)smartInsertForString:(NSString *)pasteString
	      replacingRange:(NSRange)charRange
		beforeString:(NSString **)beforeString
		 afterString:(NSString **)afterString
{
	if (beforeString != NULL) {
		*beforeString = [self smartInsertBeforeStringForString:pasteString replacingRange:charRange];
	}
	if (afterString != NULL) {
		*afterString = [self smartInsertAfterStringForString:pasteString replacingRange:charRange];
	}
}

/* **BEFORE: THE CHARACTER BEFORE THE RANGE AND THE FIRST CHARACTER OF THE STRING ARE BOTH WORD CHARACTERS.** Nothing
 * else fuses: a space, a punctuation mark, the start of the document and an empty string all answer nil, which is what
 * "no space needed" means. `NSNotFound` in the range means "the caller did not say" and is answered as the selection,
 * because that is what the edit path would replace. */
- (NSString *)smartInsertBeforeStringForString:(NSString *)pasteString replacingRange:(NSRange)charRange
{
	NSUInteger length = [_cg_textStorage length];
	NSUInteger location;

	if (!_cg_smartInsertDelete || pasteString == nil || [pasteString length] == 0) {
		return nil;
	}
	if (charRange.location == NSNotFound) {
		charRange = _selectedRange;
	}
	location = (charRange.location > length) ? length : charRange.location;
	if (location == 0) {
		return nil;
	}
	if (fn_is_word([[self string] characterAtIndex:location - 1])
	    && fn_is_word([pasteString characterAtIndex:0])) {
		return @" ";
	}
	return nil;
}

/* AND AFTER, THE MIRROR: THE LAST CHARACTER OF THE STRING AND THE CHARACTER AT THE END OF THE RANGE. An insertion at
 * the end of the document answers nil, because there is nothing to fuse with. */
- (NSString *)smartInsertAfterStringForString:(NSString *)pasteString replacingRange:(NSRange)charRange
{
	NSUInteger length = [_cg_textStorage length];
	NSUInteger location, end;

	if (!_cg_smartInsertDelete || pasteString == nil || [pasteString length] == 0) {
		return nil;
	}
	if (charRange.location == NSNotFound) {
		charRange = _selectedRange;
	}
	location = (charRange.location > length) ? length : charRange.location;
	end = location + ((charRange.length > length - location) ? (length - location) : charRange.length);
	if (end >= length) {
		return nil;
	}
	if (fn_is_word([pasteString characterAtIndex:[pasteString length] - 1])
	    && fn_is_word([[self string] characterAtIndex:end])) {
		return @" ";
	}
	return nil;
}

/* **THE EXPANSION, FOR THE EDIT PATH.** The before-string goes at the START of the range and the after-string at its
 * END, so the caller replaces one range with one string and the two spaces land where the words meet. A nil half adds
 * nothing; both nil answers the string itself, unchanged and not copied. */
- (NSString *)cg_textWithSmartInsertionForString:(NSString *)text range:(NSRange)range
{
	NSString *before = nil;
	NSString *after = nil;

	[self smartInsertForString:text replacingRange:range beforeString:&before afterString:&after];
	if (before == nil && after == nil) {
		return text;
	}
	{
		NSMutableString *expanded = [NSMutableString string];

		if (before != nil) {
			[expanded appendString:before];
		}
		[expanded appendString:text];
		if (after != nil) {
			[expanded appendString:after];
		}
		return expanded;
	}
}

/* ============================================================================================ *
 * SMART DELETE: THE WHITESPACE A DELETION WOULD HAVE LEFT DOUBLED                               *
 * ============================================================================================ */

/* **ONE RULE, AND IT IS THE ONE THAT MAKES A DELETED WORD LEAVE ONE SPACE RATHER THAN TWO.** A non-empty range grows
 * over the run of spaces and tabs that follows it — that is the gap the deletion would leave at its END. Only when
 * there is no such gap does it grow backwards over the gap BEFORE it, which is the same problem at the other edge.
 * Both directions at once is deliberately not offered: growing both would swallow the gap on each side and join the
 * two remaining words with no space at all.
 *
 * A ZERO-LENGTH RANGE IS ANSWERED UNCHANGED, because a caret has no gap to leave, and so is a range that does not
 * touch a gap. The flag is read HERE rather than at the caller, so a caller that has already decided to delete asks
 * one door and gets the era's answer either way. */
- (NSRange)smartDeleteRangeForProposedRange:(NSRange)proposedCharRange
{
	NSUInteger length = [_cg_textStorage length];
	NSRange range = proposedCharRange;
	NSString *string;
	NSUInteger end;

	if (!_cg_smartInsertDelete || range.length == 0) {
		return range;
	}
	if (range.location > length) {
		range.location = length;
	}
	if (range.location + range.length > length) {
		range.length = length - range.location;
	}
	string = [self string];
	end = range.location + range.length;
	/* THE TRAILING GAP FIRST: it is the one a delete key leaves when the word is not at the end of a line. */
	{
		NSUInteger after = end;

		while (after < length && fn_is_gap([string characterAtIndex:after])) {
			after++;
		}
		if (after > end) {
			return NSMakeRange(range.location, after - range.location);
		}
	}
	/* ELSE THE LEADING GAP, so the word at the end of a line still takes one space with it rather than leaving two. */
	{
		NSUInteger before = range.location;

		while (before > 0 && fn_is_gap([string characterAtIndex:before - 1])) {
			before--;
		}
		if (before < range.location) {
			return NSMakeRange(before, end - before);
		}
	}
	return range;
}

/* ============================================================================================ *
 * THE UNDO GROUP                                                                               *
 * ============================================================================================ */

- (BOOL)allowsUndo
{
	return _cg_allowsUndo;
}

/* **A VIEW THAT STOPS RECORDING DOES NOT LEAVE A GROUP OPEN.** The group belongs to the manager, and one left open by a
 * view that has just been told not to record is a group the NEXT edit — by anybody — would join. */
- (void)setAllowsUndo:(BOOL)flag
{
	if (flag == _cg_allowsUndo) {
		return;
	}
	_cg_allowsUndo = flag;
	if (!flag) {
		[self breakUndoCoalescing];
	}
}

/* **THE EXPLICIT BOUNDARY, AND ALSO WHAT A NON-ADJACENT EDIT DOES FOR ITSELF.** Only a TOP-LEVEL group is closed:
 * `groupingLevel` 2 is a caller's own nesting (a document wrapping several edits in one undoable action), and closing
 * that would be this view reaching into somebody else's group. */
- (void)breakUndoCoalescing
{
	NSUndoManager *manager = [self undoManager];

	if (manager != nil && [manager groupingLevel] == 1) {
		[manager endUndoGrouping];
	}
	_cg_lastEditEnd = NSNotFound;
}

/* WHETHER THE NEXT EDIT WOULD JOIN AN OPEN GROUP — which is exactly what "coalescing" means, and why this is the
 * manager's grouping level rather than a flag of the view's that could disagree with it. */
- (BOOL)isCoalescingUndo
{
	NSUndoManager *manager = [self undoManager];

	return (manager != nil && [manager groupingLevel] > 0);
}

/* ============================================================================================ *
 * THE REGISTRATION THE EDIT PATH ASKS FOR                                                       *
 * ============================================================================================ */

/* **ONE UNDO ACTION PER EDIT, AND THE VIEW IS ITS OWN TARGET.** The action carries the range the edit INSERTED over and
 * the text it REPLACED, so replaying it is one `-replaceCharactersInRange:withString:` — the view's own primitive, which
 * means the store, the mirror, the layout, the selection and the notification all follow from an undo exactly as they
 * follow from a keystroke. There is no second edit path here for the same reason there is no second one in the pasteboard
 * code.
 *
 * **AND THE MANAGER'S OWN STACK DECIDES WHAT A REPLAY IS.** While an undo or a redo runs, the edit path still registers
 * — that registration IS the other stack — so this door records in both directions and only the GROUPING is skipped
 * during a replay. That is the one thing that would otherwise nest a group inside the manager's own operation.
 *
 * **AN EDIT THAT CHANGES NOTHING IS NOT RECORDED**, so a no-op replacement cannot put an empty action on the stack and
 * make `-undo` look like it did nothing. */
- (void)cg_noteEditInRange:(NSRange)range
	      insertedText:(NSString *)inserted
	      replacedText:(NSString *)replaced
{
	NSUndoManager *manager = [self undoManager];
	NSString *fresh = (inserted != nil) ? inserted : @"";
	NSString *old = (replaced != nil) ? replaced : @"";
	NSUInteger length = [fresh length];
	BOOL replaying;

	if (!_cg_allowsUndo || manager == nil) {
		return;
	}
	if ([fresh isEqual:old]) {
		return;
	}
	replaying = ([manager isUndoing] || [manager isRedoing]);
	if (replaying) {
		_cg_lastEditEnd = NSNotFound;
	} else {
		BOOL continues = (_cg_lastEditEnd != NSNotFound)
			&& (range.location == _cg_lastEditEnd || range.location + range.length == _cg_lastEditEnd);

		if (!continues && [manager groupingLevel] == 1) {
			[manager endUndoGrouping];
		}
		_cg_lastEditEnd = range.location + length;
	}
	[manager registerUndoWithTarget:self
			      selector:@selector(cg_undoReplaceRange:)
				object:[NSDictionary dictionaryWithObjectsAndKeys:
						[NSValue valueWithRange:NSMakeRange(range.location, length)],
						AGUndoRangeKey, old, AGUndoStringKey, nil]];
}

/* **THE REPLAY ITSELF, AND IT IS THE PUBLIC DOOR.** A dictionary arrives because a target/selector/object registration
 * carries exactly one argument; the range it names is the range the original edit INSERTED, and the string is what was
 * there before it. Both are clamped by the primitive, so an undo after an unrelated edit cannot run off the end. */
- (void)cg_undoReplaceRange:(NSDictionary *)action
{
	NSRange range = [[action objectForKey:AGUndoRangeKey] rangeValue];
	NSString *text = [action objectForKey:AGUndoStringKey];

	[self replaceCharactersInRange:range withString:(text != nil) ? text : @""];
}

@end
