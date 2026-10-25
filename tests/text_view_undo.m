/*
 * text_view_undo — what typing does around it: the smart space, the smart delete, and the undo group.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIMS HERE ARE ABOUT THE TEXT AFTERWARDS, NOT ABOUT FLAGS.** A smart insert is a space in the store, a smart
 * delete is a space that is NOT in the store, and an undo is the string that comes back — so every assertion below
 * compares `-string` before and after, and the flag assertions are only there to pin the two defaults.
 *
 * WHAT IS ASSERTED, in order:
 *
 *   1. THE DEFAULTS: `-smartInsertDeleteEnabled` and `-allowsUndo` are both NO, which is Apple's default for a view made
 *      in code, and `-isCoalescingUndo` is NO because no group is open.
 *   2. THE SMART-INSERT HALVES, one at a time: the space appears where two word characters would otherwise fuse, and
 *      nowhere else — not at the start of the document, not at its end, not when either edge is whitespace.
 *   3. THE SAME THING THROUGH THE EDIT: `-insertText:` next to a word puts the space in the store, and with the flag off
 *      it does not. The paste path is the same door, so it is checked through `-insertText:` too.
 *   4. THE SMART DELETE: the trailing gap goes with the word, the leading gap goes when there is no trailing one, a
 *      NEWLINE is never absorbed, a caret deletes nothing, and `-delete:` is what applies it.
 *   5. THE UNDO GROUP, through a real `NSUndoManager` supplied by the window's delegate — which is also the assertion
 *      that `-windowWillReturnUndoManager:` is SENT at last. One typed run is one undo; a break starts a new one; an
 *      edit somewhere else starts a new one; a run of backspaces is one undo; a redo puts it all back; and a smart
 *      delete's undo restores the space it took.
 *   6. `-didChangeText` IS THE EDIT PATH'S DOOR: one notification and one delegate message per edit, not two.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSResponder.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static void check_string(NSTextView *view, NSString *expected, const char *name)
{
	NSString *actual = [view string];
	int ok = [actual isEqualToString:expected];

	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		printf("        expected `%s`, got `%s`\n", [expected UTF8String], [actual UTF8String]);
		s_failed++;
	}
}

static void check_range(NSRange range, NSUInteger location, NSUInteger length, const char *name)
{
	int ok = (range.location == location && range.length == length);

	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		printf("        expected (%lu, %lu), got (%lu, %lu)\n", (unsigned long)location, (unsigned long)length,
		       (unsigned long)range.location, (unsigned long)range.length);
	}
	if (!ok) {
		s_failed++;
	}
}

/* **THE WINDOW'S DELEGATE IS THE ONLY THING THAT CAN NAME A DOCUMENT'S MANAGER**, which is what
 * `-windowWillReturnUndoManager:` is for; this one holds a manager and counts the text changes it is told about. */
@interface AGUndoDelegate : NSObject
{
@public
	NSUndoManager *manager;
	int changes;
	int undoManagerAsks;
}
@end

@implementation AGUndoDelegate
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
	(void)window;
	undoManagerAsks++;
	return manager;
}

- (void)textDidChange:(NSNotification *)note
{
	(void)note;
	changes++;
}
@end

/* THE OBSERVER THAT MAKES "ONE NOTIFICATION PER EDIT" A NUMBER. */
@interface AGChangeCounter : NSObject
{
@public
	int notifications;
}
@end

@implementation AGChangeCounter
- (void)noteChange:(NSNotification *)note
{
	(void)note;
	notifications++;
}
@end

static NSTextView *make_view(NSWindow *window, NSString *text)
{
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 200.0)];

	[view setFont:[NSFont systemFontOfSize:14.0]];
	[view setEditable:YES];
	[view setString:text];
	/* THE TYPED REFERENCE IS THE OWNING ONE; `-contentView` answers NSView *, which is the wrong class here. */
	[window setContentView:view];
	return view;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 200.0)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
	AGUndoDelegate *delegate = [[AGUndoDelegate alloc] init];
	NSUndoManager *manager = [[NSUndoManager alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);
	delegate->manager = manager;

	/* 1. **THE DEFAULTS.** */
	{
		NSTextView *view = make_view(window, @"one two");

		check(![view smartInsertDeleteEnabled], "smart insert/delete is OFF by default, which is Apple's code-made default");
		check(![view allowsUndo], "and so is undo");
		check(![view isCoalescingUndo], "with no group open, nothing is coalescing");
		[view release];
	}

	/* 2. **THE TWO HALVES, ONE AT A TIME.** */
	{
		NSTextView *view = make_view(window, @"one two");

		[view setSmartInsertDeleteEnabled:YES];
		check([[view smartInsertBeforeStringForString:@"three" replacingRange:NSMakeRange(3, 0)] isEqual:@" "],
		      "a word typed against a word gets a space before it");
		check([view smartInsertBeforeStringForString:@"three" replacingRange:NSMakeRange(0, 0)] == nil,
		      "at the start of the document there is nothing to fuse with");
		check([view smartInsertBeforeStringForString:@" " replacingRange:NSMakeRange(3, 0)] == nil,
		      "and an inserted space needs no space in front of it");
		check([view smartInsertBeforeStringForString:@"." replacingRange:NSMakeRange(3, 0)] == nil,
		      "nor does punctuation, which does not fuse");
		check([view smartInsertAfterStringForString:@"three" replacingRange:NSMakeRange(3, 0)] == nil,
		      "the character after the range is a space, so no space goes there");
		check([[view smartInsertAfterStringForString:@"X" replacingRange:NSMakeRange(4, 0)] isEqual:@" "],
		      "but a word inserted just before a word gets one after it");
		check([view smartInsertAfterStringForString:@"X" replacingRange:NSMakeRange(7, 0)] == nil,
		      "and at the end of the document there is nothing after it");
		{
			NSString *before = @"untouched";
			NSString *after = @"untouched";

			[view smartInsertForString:@"X" replacingRange:NSMakeRange(4, 0) beforeString:&before afterString:&after];
			check(before == nil && [after isEqual:@" "], "the whole door answers both halves at once");
		}
		[view setSmartInsertDeleteEnabled:NO];
		check([view smartInsertBeforeStringForString:@"three" replacingRange:NSMakeRange(3, 0)] == nil,
		      "and with the flag off neither half answers anything");
		[view release];
	}

	/* 3. **THE PLACE THE SPACE ACTUALLY HAS TO APPEAR: THE STORE.** */
	{
		NSTextView *view = make_view(window, @"one two");

		[view setSelectedRange:NSMakeRange(3, 0)];
		[view insertText:@"three"];
		check_string(view, @"onethree two", "with the flag off, typing against a word fuses them");

		[view setString:@"one two"];
		[view setSmartInsertDeleteEnabled:YES];
		[view setSelectedRange:NSMakeRange(3, 0)];
		[view insertText:@"three"];
		check_string(view, @"one three two", "with it on, the same keystrokes leave the words apart");
		check([view selectedRange].location == 9, "and the caret sits after what was typed, spaces included");

		/* AND THE PASTE PATH IS THE SAME DOOR, so it gets the same space. */
		[view setString:@"one two"];
		[view setSelectedRange:NSMakeRange(3, 0)];
		[view insertText:@"four"];
		check_string(view, @"one four two", "a paste next to a word is spaced the same way, because it is the same edit");
		[view release];
	}

	/* 4. **THE SMART DELETE AND THE COMMAND THAT APPLIES IT.** */
	{
		NSTextView *view = make_view(window, @"one two three");

		[view setSmartInsertDeleteEnabled:YES];
		check_range([view smartDeleteRangeForProposedRange:NSMakeRange(4, 3)], 4, 4,
			    "deleting `two` takes the space AFTER it, so the gap is not left doubled");
		check_range([view smartDeleteRangeForProposedRange:NSMakeRange(8, 5)], 7, 6,
			    "deleting the last word takes the space BEFORE it, there being no space after");
		check_range([view smartDeleteRangeForProposedRange:NSMakeRange(4, 0)], 4, 0,
			    "a caret proposes nothing and gets nothing");
		[view setSmartInsertDeleteEnabled:NO];
		check_range([view smartDeleteRangeForProposedRange:NSMakeRange(4, 3)], 4, 3,
			    "and with the flag off the range is the caller's own");

		/* A NEWLINE IS A PARAGRAPH BREAK, NOT A GAP: absorbing one would join two paragraphs. */
		[view setString:@"one\ntwo"];
		[view setSmartInsertDeleteEnabled:YES];
		check_range([view smartDeleteRangeForProposedRange:NSMakeRange(0, 3)], 0, 3,
			    "deleting a line's word does not swallow the newline after it");

		/* AND THE COMMAND: the text after a delete is what proves the range was applied. */
		[view setString:@"one two three"];
		[view setSelectedRange:NSMakeRange(4, 3)];
		[view delete:nil];
		check_string(view, @"one three", "`-delete:` on a word leaves ONE space between the survivors");
		[view setSelectedRange:NSMakeRange(4, 0)];
		[view delete:nil];
		check_string(view, @"one three", "and a delete with a caret removes nothing");
		[view release];
	}

	/* 5. **THE UNDO GROUP, WITH A REAL MANAGER FROM THE WINDOW'S DELEGATE.** */
	{
		NSTextView *view;

		[window setDelegate:nil];
		view = make_view(window, @"");
		check([view undoManager] == nil, "a window with no delegate has no manager for the chain to find");
		[view release];

		[window setDelegate:delegate];
		view = make_view(window, @"");
		check([view undoManager] == manager,
		      "and with one, `-undoManager` walks view -> window -> delegate: `-windowWillReturnUndoManager:` is SENT");

		/* THE NEGATIVE CONTROL FIRST: with the flag off nothing is recorded. */
		[view insertText:@"a"];
		check(![manager canUndo], "a view that does not allow undo records nothing");

		[view setAllowsUndo:YES];
		[view setString:@""];
		[manager removeAllActions];
		[view insertText:@"a"];
		[view insertText:@"b"];
		[view insertText:@"c"];
		check_string(view, @"abc", "three keystrokes make a word");
		check([manager canUndo], "and one undo action");
		check([view isCoalescingUndo], "the run is coalescing, which is what one undo means");

		[manager undo];
		check_string(view, @"", "one undo takes back the whole typed run, not one letter");
		check([manager canRedo], "and the redo stack holds it");
		[manager redo];
		check_string(view, @"abc", "the redo puts the word back through the view's own edit door");

		/* A BREAK STARTS A NEW GROUP. */
		[view setString:@""];
		[manager removeAllActions];
		[view insertText:@"a"];
		[view breakUndoCoalescing];
		check(![view isCoalescingUndo], "a break closes the group, so nothing is coalescing");
		[view insertText:@"b"];
		[manager undo];
		check_string(view, @"a", "so the undo takes back the second run only");
		[manager undo];
		check_string(view, @"", "and a second undo takes back the first");

		/* AN EDIT SOMEWHERE ELSE STARTS A NEW GROUP BY ITSELF. */
		[view setString:@""];
		[manager removeAllActions];
		[view setSelectedRange:NSMakeRange(0, 0)];
		[view insertText:@"a"];
		[view insertText:@"b"];
		[view setSelectedRange:NSMakeRange(0, 0)];
		[view insertText:@"X"];
		check_string(view, @"Xab", "an insertion at the start lands before the run");
		[manager undo];
		check_string(view, @"ab", "the non-adjacent edit was its own group, so one undo takes back the X only");
		[manager undo];
		check_string(view, @"", "and the next undo takes back the run");

		/* A RUN OF BACKSPACES IS ONE GROUP TOO. */
		[view setString:@""];
		[manager removeAllActions];
		[view setSelectedRange:NSMakeRange(0, 0)];
		[view insertText:@"abc"];
		[view breakUndoCoalescing];
		[view deleteBackward:nil];
		[view deleteBackward:nil];
		[view deleteBackward:nil];
		check_string(view, @"", "three backspaces empty the view");
		[manager undo];
		check_string(view, @"abc", "and one undo restores all three, because the deletions coalesced");

		/* AND A SMART DELETE'S UNDO PUTS THE SPACE BACK. */
		[view setString:@"one two three"];
		[manager removeAllActions];
		[view setSmartInsertDeleteEnabled:YES];
		[view setSelectedRange:NSMakeRange(4, 3)];
		[view delete:nil];
		check_string(view, @"one three", "the word and its trailing space are gone");
		[manager undo];
		check_string(view, @"one two three", "and the undo restores the space the smart delete took as well");
		[view release];
	}

	/* 6. **ONE ANNOUNCEMENT PER EDIT, AND IT IS THE DOOR'S.** */
	{
		AGChangeCounter *counter = [[AGChangeCounter alloc] init];
		NSTextView *view = make_view(window, @"");

		[view setDelegate:delegate];
		[view setAllowsUndo:YES];
		delegate->changes = 0;
		[[NSNotificationCenter defaultCenter] addObserver:counter selector:@selector(noteChange:)
			name:NSTextDidChangeNotification object:view];
		[view insertText:@"a"];
		[[NSNotificationCenter defaultCenter] removeObserver:counter name:NSTextDidChangeNotification object:view];
		printf("  (note: one insertText: posted %d notification(s) and %d delegate message(s))\n",
		       counter->notifications, delegate->changes);
		check(counter->notifications == 1, "one edit posts ONE change notification, through `-didChangeText`");
		check(delegate->changes == 1, "and tells the delegate once");
		[view setDelegate:nil];
		[view release];
		[counter release];
	}

	[manager release];
	[delegate release];
	[window release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
