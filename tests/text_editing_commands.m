/*
 * text_editing_commands.m — `-transpose:` AND THE INSERTIONS THAT IGNORE A FIELD'S ROLE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE COMMANDS THE RESPONDER NAMED AS OWED, IMPLEMENTED WHERE THEY BELONG.** `-transpose:` is pure string
 * arithmetic over a position — no layout, no width, no marked range — so it is the one command in that named list that
 * needed nothing this tier was missing. The probe drives it from every position (middle, a selection of two, either
 * end, and a string too short) because the edge cases ARE the behavior. And the `IgnoringFieldEditor` pair plus
 * `-insertParagraphSeparator:` are checked across the two surfaces: a text view inserts the break, a one-line field
 * refuses it at the door that decides whether it can hold one.
 */
#import <AppKit/NSText.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSView.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSText *field = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **`-transpose:` SWAPS THE CHARACTERS AROUND THE INSERTION POINT.** */
	[field setString:@"abcd"];
	[field setSelectedRange:NSMakeRange(2, 0)];
	[field transpose:nil];
	printf("  (note: transpose at 2 of `abcd` gave `%s`, caret %lu)\n",
	       [[field string] UTF8String], (unsigned long)[field selectedRange].location);
	check([[field string] isEqualToString:@"acbd"], "the two characters around the caret change places");
	check([field selectedRange].location == 3, "and the caret ends after the pair");

	/* 2. **AND A SELECTION OF TWO IS EXACTLY THAT PAIR.** */
	[field setString:@"abcd"];
	[field setSelectedRange:NSMakeRange(1, 2)];
	[field transpose:nil];
	check([[field string] isEqualToString:@"acbd"], "a selection of two swaps the two it covers");

	/* 3. **AND AT EITHER END THE LAST TWO ARE THE PAIR, because there are not two on the far side.** */
	[field setString:@"abcd"];
	[field setSelectedRange:NSMakeRange(0, 0)];
	[field transpose:nil];
	check([[field string] isEqualToString:@"bacd"], "at the START the first two swap");
	[field setString:@"abcd"];		/* -setString: leaves the caret at the end */
	[field transpose:nil];
	check([[field string] isEqualToString:@"abdc"], "at the END the last two swap");

	/* 4. **AND A STRING WITH NOTHING TO SWAP IS LEFT ALONE.** */
	[field setString:@"a"];
	[field transpose:nil];
	check([[field string] isEqualToString:@"a"], "one character has no pair to swap with");

	/* 5. **AND A PARAGRAPH SEPARATOR IS A BREAK IN A VIEW AND REFUSED BY A FIELD.** */
	[view setString:@"ab"];
	[view insertParagraphSeparator:nil];
	check([[view string] isEqualToString:@"ab\n"], "a text view's `-insertParagraphSeparator:` is a break it holds");
	[field setString:@"ab"];
	[field insertParagraphSeparator:nil];
	check([[field string] isEqualToString:@"ab"], "a one-line field refuses one at its insert door");

	/* 6. **AND THE IgnoringFieldEditor PAIR INSERTS THE CHARACTERS A VIEW CAN HOLD.** */
	[view setString:@"ab"];
	[view insertNewlineIgnoringFieldEditor:nil];
	[view insertTabIgnoringFieldEditor:nil];
	printf("  (note: the IgnoringFieldEditor pair gave a string %lu characters long)\n",
	       (unsigned long)[[view string] length]);
	check([[view string] isEqualToString:@"ab\n\t"], "the newline and tab are inserted rather than ending a session");

	[view release];
	[field release];
	[pool release];
	printf("text_editing_commands: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
