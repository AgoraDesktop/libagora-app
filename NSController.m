/*
 * NSController.m — the editing registration and the commit doors.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **ONE ARRAY, BOXED ADDRESSES, AND NO OWNERSHIP OF THE EDITORS.** `NSValue`'s non-retained box is exactly the
 * primitive this needs: the array can be searched, copied and walked without the controller keeping any editor alive.
 * The alternative — an `NSHashTable` of weak objects — would answer the same question with an unordered walk, and the
 * ORDER of a commit is part of what a user sees.
 */
#import <AppKit/NSController.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#import <objc/message.h>

@implementation NSController

- (id)init
{
	self = [super init];
	if (self != nil) {
		_editors = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_editors release];
	[super dealloc];
}

/* WHO IS REGISTERED, BY IDENTITY. Two `NSValue` boxes over the same address are equal, but the question here is
 * object identity in the Cocoa sense, so the comparison is on the address the boxes carry. */
static NSUInteger fn_index_of_editor(NSArray *editors, id editor)
{
	NSUInteger i;

	for (i = 0; i < [editors count]; i++) {
		if ([[editors objectAtIndex:i] nonretainedObjectValue] == editor) {
			return i;
		}
	}
	return NSNotFound;
}

- (BOOL)isEditing
{
	return [_editors count] != 0;
}

- (void)objectDidBeginEditing:(id)editor
{
	if (editor == nil) {
		return;
	}
	if (fn_index_of_editor(_editors, editor) != NSNotFound) {
		return;		/* one registration per editor, however many times a view says it began */
	}
	[_editors addObject:[NSValue valueWithNonretainedObject:editor]];
}

- (void)objectDidEndEditing:(id)editor
{
	NSUInteger index;

	if (editor == nil) {
		return;
	}
	index = fn_index_of_editor(_editors, editor);
	if (index != NSNotFound) {
		[_editors removeObjectAtIndex:index];
	}
}

/* **THE SNAPSHOT IS WHY THIS IS A COPY.** An editor's `-commitEditing` may call back `-objectDidEndEditing:`, which
 * mutates `_editors` DURING the walk. Iterating the live array would then skip the next editor or walk off its end. */
- (BOOL)commitEditing
{
	NSArray *snapshot = [[_editors copy] autorelease];
	BOOL committed = YES;
	NSUInteger i;

	for (i = 0; i < [snapshot count]; i++) {
		id editor = [[snapshot objectAtIndex:i] nonretainedObjectValue];

		if (fn_index_of_editor(_editors, editor) == NSNotFound) {
			continue;	/* the previous editor's commit ended this one: it is already done */
		}
		if (![editor respondsToSelector:@selector(commitEditing)]) {
			continue;	/* registered as an editor but not one: nothing to ask */
		}
		if (![editor commitEditing]) {
			committed = NO;	/* keep walking: every editor is asked, and one refusal is the answer */
		}
	}
	return committed;
}

- (void)discardEditing
{
	NSArray *snapshot = [[_editors copy] autorelease];
	NSUInteger i;

	for (i = 0; i < [snapshot count]; i++) {
		id editor = [[snapshot objectAtIndex:i] nonretainedObjectValue];

		if (fn_index_of_editor(_editors, editor) == NSNotFound) {
			continue;
		}
		if ([editor respondsToSelector:@selector(discardEditing)]) {
			[editor discardEditing];
		}
	}
}

- (void)commitEditingWithDelegate:(id)delegate
	       didCommitSelector:(SEL)didCommitSelector
		     contextInfo:(void *)contextInfo
{
	BOOL committed = [self commitEditing];

	if (delegate != nil && didCommitSelector != NULL) {
		/* THE THREE-ARGUMENT SEND, DECLARED RATHER THAN GUESSED: (editor, didCommit, contextInfo). The same cast
		 * `NSKeyValueBinding`'s no-editor default uses, so the two cannot disagree about the arity. */
		((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, didCommitSelector, self, committed,
								   contextInfo);
	}
}

@end
