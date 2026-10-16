/*
 * text_word_movement.m — MOVING AND DELETING BY THE WORD, WHICH IS ARITHMETIC OVER THE STRING.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A WORD IS A RUN OF THE STRING'S OWN CHARACTERS, SO THIS NEEDS NO LAYOUT MODEL.** `NSResponder.h` used to name the
 * word commands among the family that needed a layout model — words, paragraphs, several lines — and that reason was
 * right for the PARAGRAPH and DOCUMENT commands and wrong for these: `-moveWordLeft:` asks where the run of
 * `+alphanumericCharacterSet` before the caret begins, which is a walk over the text a one-line field already holds.
 * The correction is in that header; what this probe holds is the arithmetic.
 *
 * **EVERY CASE IS DRIVEN THE WAY A PERSON DRIVES IT — AS A KEY.** The command doors are exercised directly only where
 * a key cannot reach them (an AndModifySelection variant with nothing to extend, say); everything else is an `NSEvent`
 * with the Option flag, so what is under test is the MAPPING as well as the walk. MEASURED here is where the caret
 * lands and what the string becomes, both read back from the view.
 */
#import <AppKit/NSText.h>
#import <AppKit/NSEvent.h>
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

static int range_is(NSRange r, NSUInteger where, NSUInteger length)
{
	return r.location == where && r.length == length;
}

/* A KEYSTROKE, BUILT FROM THE CHARACTER IT CARRIES AND THE FLAGS IT CARRIES — which is the whole of what the mapping
 * reads, so an Option-arrow is one string and one bit and is otherwise the same event as a plain arrow. */
static NSEvent *key(NSString *characters, NSUInteger flags)
{
	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags
			       timestamp:0.0 windowNumber:0 context:nil
			      characters:characters charactersIgnoringModifiers:characters
			       isARepeat:NO keyCode:0];
}

static NSString *arrow(unichar code)
{
	return [NSString stringWithFormat:@"%C", code];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	/* "one two three": the words begin at 0, 4 and 8, and end at 3, 7 and 13. */
	NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 24.0)];

	/* 1. **LEFT GOES TO THE START OF THE WORD BEFORE THE CARET, AND RIGHT TO THE END OF THE ONE AFTER.** From the end
	 * of the line, Option+Left crosses the whole of "three"; from the start, Option+Right crosses "one". */
	[text setString:@"one two three"];
	[text keyDown:key(arrow(NSLeftArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 8, 0), "Option+Left from the end lands at the start of the LAST word");
	[text keyDown:key(arrow(NSLeftArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 4, 0), "and again at the start of the one before it");

	[text setSelectedRange:NSMakeRange(0, 0)];
	[text keyDown:key(arrow(NSRightArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 3, 0), "Option+Right from the start lands at the END of the first word");
	[text keyDown:key(arrow(NSRightArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 7, 0), "and again at the end of the next one");

	/* 2. **THE SAME KEYS FROM THE MIDDLE OF A WORD GO TO THAT WORD'S OWN BOUNDARY.** The walk skips NON-word
	 * characters first and word characters second, so a caret inside a word has nothing to skip in the first pass and
	 * lands on the boundary of the word it is IN — which is what a person pressing Option+arrow inside a word means. */
	[text setSelectedRange:NSMakeRange(6, 0)];	/* inside "two" */
	[text keyDown:key(arrow(NSLeftArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 4, 0), "Option+Left from INSIDE a word goes to that word's start");
	[text setSelectedRange:NSMakeRange(5, 0)];
	[text keyDown:key(arrow(NSRightArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 7, 0), "and Option+Right to that word's end");

	/* 3. **AND THE ENDS DO NOTHING, WHICH IS WHERE A WALK OFF THE STRING IS CAUGHT.** */
	[text setSelectedRange:NSMakeRange(0, 0)];
	[text keyDown:key(arrow(NSLeftArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 0, 0), "Option+Left at the START stays put");
	[text setSelectedRange:NSMakeRange(13, 0)];
	[text keyDown:key(arrow(NSRightArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 13, 0), "and Option+Right at the END");

	/* 4. **A SELECTION COLLAPSES TO ITS NEAR END, THE SAME AS A CHARACTER MOVEMENT.** The word pair is a movement
	 * like the arrows, so what a movement does to a selection is not a second rule. */
	[text setSelectedRange:NSMakeRange(0, 5)];
	[text keyDown:key(arrow(NSLeftArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 0, 0), "a movement COLLAPSES a selection to the near end (left)");
	[text setSelectedRange:NSMakeRange(0, 5)];
	[text keyDown:key(arrow(NSRightArrowFunctionKey), NSAlternateKeyMask)];
	check(range_is([text selectedRange], 5, 0), "and to the far end (right)");

	/* 5. **AND SHIFT EXTENDS BY THE WORD RATHER THAN BY THE CHARACTER.** The left form rewrites the selection's
	 * LOCATION and the right form its LENGTH, which is "move the one end the drag is moving". */
	[text setSelectedRange:NSMakeRange(8, 0)];
	[text keyDown:key(arrow(NSLeftArrowFunctionKey), NSAlternateKeyMask | NSShiftKeyMask)];
	check(range_is([text selectedRange], 4, 4),
	      "Option+SHIFT+Left extends to the previous word's start — four characters, not one");
	[text setSelectedRange:NSMakeRange(4, 0)];
	[text keyDown:key(arrow(NSRightArrowFunctionKey), NSAlternateKeyMask | NSShiftKeyMask)];
	check(range_is([text selectedRange], 4, 3),
	      "and Option+SHIFT+Right to this word's end — the word itself, without the space after it");

	/* 6. **AND NOTHING TO EXTEND IS A NO-OP RATHER THAN A STRAY CHARACTER.** These are the cases a key cannot reach
	 * (Shift+Option+Left at the very start does reach the door and is a no-op, but the doors are asked directly here
	 * so a failure names the door rather than the mapping). */
	[text setSelectedRange:NSMakeRange(0, 0)];
	[text moveWordLeftAndModifySelection:nil];
	check(range_is([text selectedRange], 0, 0), "`-moveWordLeftAndModifySelection:` at the start does nothing");
	[text setSelectedRange:NSMakeRange(13, 0)];
	[text moveWordRightAndModifySelection:nil];
	check(range_is([text selectedRange], 13, 0), "`-moveWordRightAndModifySelection:` at the end does nothing");

	/* 7. **AND DELETING A WORD DELETES EXACTLY WHAT MOVING BY ONE CROSSES.** Option+Delete is backward, and the
	 * forward one is the Delete function key with Option — the same pairing the unmodified keys have. */
	[text setString:@"one two three"];
	[text setSelectedRange:NSMakeRange(8, 0)];
	[text keyDown:key(arrow(NSBackspaceCharacter), NSAlternateKeyMask)];
	check([[text string] isEqualToString:@"one three"],
	      "Option+Delete from the start of the last word removes the whole word AND the space before it");
	[text setString:@"one two three"];
	[text setSelectedRange:NSMakeRange(8, 0)];
	[text keyDown:key(arrow(NSDeleteCharacter), NSAlternateKeyMask)];
	check([[text string] isEqualToString:@"one three"], "and the other Backspace spelling does the same");

	[text setString:@"one two three"];
	[text setSelectedRange:NSMakeRange(4, 0)];
	[text keyDown:key(arrow(NSDeleteFunctionKey), NSAlternateKeyMask)];
	check([[text string] isEqualToString:@"one  three"],
	      "Option+ForwardDelete from a word's start removes the word, leaving the space on either side");

	/* 8. **AND A SELECTION IS DELETED WHOLE, WORD KEY OR NOT.** A person who has selected something and pressed a
	 * delete key means the selection; the word walk only applies to a collapsed caret. */
	[text setString:@"one two three"];
	[text setSelectedRange:NSMakeRange(4, 4)];
	[text keyDown:key(arrow(NSBackspaceCharacter), NSAlternateKeyMask)];
	check([[text string] isEqualToString:@"one three"], "Option+Delete deletes a SELECTION whole");

	/* 9. **AND A WORD IS ALPHANUMERIC RUNS, NOT LETTERS WITH SPACES AROUND THEM.** Punctuation between words is not a
	 * word, and neither is a digit — so `abc123` is ONE word and `a...b` is two with three non-word characters
	 * between them. This is the boundary rule stated as a case rather than trusted. */
	[text setString:@"abc123 def"];
	[text setSelectedRange:NSMakeRange(0, 0)];
	[text moveWordRight:nil];
	check(range_is([text selectedRange], 6, 0), "digits belong to the word they sit in — `abc123` is one word");

	[text setString:@"a...b"];
	[text setSelectedRange:NSMakeRange(0, 0)];
	[text moveWordRight:nil];
	check(range_is([text selectedRange], 1, 0), "punctuation is not a word, so Right stops before the dots");
	[text moveWordRight:nil];
	check(range_is([text selectedRange], 5, 0), "and the next Right crosses them to the end of the following word");
	[text moveWordLeft:nil];
	check(range_is([text selectedRange], 4, 0), "while Left from the end lands at that word's start");
	[text moveWordLeft:nil];
	check(range_is([text selectedRange], 0, 0), "and the next crosses the dots to the start of the first word");

	/* 10. **AND AN UNSHIFTED, UNMODIFIED ARROW IS STILL A CHARACTER MOVEMENT.** The Option branch is a branch and not
	 * a replacement: the whole point of the mapping is that the SAME key with one modifier is both. */
	[text setString:@"one two"];
	[text setSelectedRange:NSMakeRange(0, 0)];
	[text keyDown:key(arrow(NSRightArrowFunctionKey), 0)];
	check(range_is([text selectedRange], 1, 0), "a plain Right still moves ONE character");
	[text setSelectedRange:NSMakeRange(5, 0)];
	[text keyDown:key(arrow(NSBackspaceCharacter), 0)];
	check([[text string] isEqualToString:@"one wo"], "and a plain Delete still deletes one");

	[text release];
	[pool release];
	printf("text_word_movement: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
