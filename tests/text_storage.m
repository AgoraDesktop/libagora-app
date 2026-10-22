/*
 * text_storage.m — THE STORE ANNOUNCES ITS OWN EDITS, AND THE RECORD IS WHAT IT ANNOUNCES.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLASS'S WHOLE CLAIM IS A RELATIONSHIP: the primitives change the string, and `-edited:range:changeInLength:`
 * records WHAT changed so that `-processEditing` can tell the world ONCE.** So what is measured here is not "the text
 * changed" — the base class already did that — but that the RECORD is right at the moment the announcement runs, that
 * a `-beginEditing`/`-endEditing` GROUP is one announcement and not several, and that the announcement reaches both a
 * delegate and a listener registered for the name.
 *
 * **AND THE ROUTING IS CHECKED RATHER THAN ASSUMED.** `-insertAttributedString:atIndex:` is NOT overridden by the
 * store; the claim is that the base class's version reaches the overridden PRIMITIVE by dispatch, so an edit made
 * through a door the store has never heard of is still announced. That is the sentence the header opens with, and it
 * is the one a copy of the header cannot prove.
 */
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSAttributedString.h>
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

/* **A DELEGATE THAT READS THE RECORD WHILE IT IS BEING TOLD.** That is the point of Apple's order — Will, the fix, Did
 * — and a delegate that recorded the range afterwards would be reading a store that had already cleared it. */
@interface StoreWatcher : NSObject <NSTextStorageDelegate>
{
@public
	int will;
	int did;
	NSRange lastRange;
	NSUInteger lastMask;
	NSInteger lastDelta;
	NSUInteger lastLength;
}
@end

@implementation StoreWatcher
- (void)textStorageWillProcessEditing:(NSNotification *)notification
{
	(void)notification;
	will++;
}

- (void)textStorageDidProcessEditing:(NSNotification *)notification
{
	NSTextStorage *store = [notification object];

	did++;
	lastRange = [store editedRange];
	lastMask = [store editedMask];
	lastDelta = [store changeInLength];
	lastLength = [store length];
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"hello"];
	StoreWatcher *watcher = [[StoreWatcher alloc] init];
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	NSDictionary *red = [NSDictionary dictionaryWithObject:@"red" forKey:@"Colour"];

	setvbuf(stdout, NULL, _IONBF, 0);
	[store setDelegate:watcher];

	/* 1. **A FRESH STORE HAS EDITED NOTHING, AND THE ANSWER IS `NSNotFound` RATHER THAN ZERO.** A location of zero is
	 * a real place in the string, so a store that started at `{0, 0}` would claim an edit at the first character. */
	check([store editedRange].location == NSNotFound, "a fresh store's edited range is NSNotFound");
	check([store editedMask] == 0 && [store changeInLength] == 0, "with no mask and no length change");
	check(![store fixesAttributesLazily], "and it does not fix attributes lazily — there is nothing to defer");
	check([store length] == 5 && [[store string] isEqualToString:@"hello"],
	      "and it IS an attributed string: `-length` and `-string` answer the base's own");

	/* 2. **AN INSERTION IS ANNOUNCED WITH ITS OWN RANGE AND DELTA, AND THE RECORD IS CLEARED AFTERWARDS.** */
	[store replaceCharactersInRange:NSMakeRange(5, 0) withString:@" world"];
	printf("  (note: after inserting six characters — will %d, did %d, range (%lu,%lu), mask %lu, delta %ld)\n",
	       watcher->will, watcher->did, (unsigned long)watcher->lastRange.location,
	       (unsigned long)watcher->lastRange.length, (unsigned long)watcher->lastMask, (long)watcher->lastDelta);
	check([store length] == 11 && [[store string] isEqualToString:@"hello world"],
	      "the primitive made the change, through the base class's own storage");
	check(watcher->will == 1 && watcher->did == 1, "and the delegate heard Will then Did, once each");
	check(watcher->lastMask == NSTextStorageEditedCharacters, "the mask says the CHARACTERS changed");
	check(range_is(watcher->lastRange, 5, 0), "the range is where the edit happened, in the ORIGINAL string");
	check(watcher->lastDelta == 6, "and the delta is the six characters that arrived");
	check(watcher->lastLength == 11, "with the store already the new length while the delegate is being told");
	check([store editedRange].location == NSNotFound,
	      "and the record is CLEARED by the time `-processEditing` returns");

	/* 3. **AN ATTRIBUTE EDIT IS A DIFFERENT MASK AND MOVES NO CHARACTERS.** The mask is what tells a listener which
	 * kind of change it is looking at, which is why it exists rather than a single boolean. */
	[store setAttributes:red range:NSMakeRange(0, 5)];
	check(watcher->lastMask == NSTextStorageEditedAttributes, "setting attributes reports the ATTRIBUTES mask");
	check(watcher->lastDelta == 0, "and a length change of zero");
	check([[store attributesAtIndex:0 effectiveRange:NULL] objectForKey:@"Colour"] != nil,
	      "with the attributes really in the store");

	/* 4. **AND A GROUP IS ONE ANNOUNCEMENT, WHICH IS WHAT `-beginEditing` BUYS.** Two edits inside the pair produce a
	 * single Will/Did, over the UNION of the two ranges — so a listener never sees a document that is half-changed. */
	{
		int before = watcher->did;

		[store beginEditing];
		[store replaceCharactersInRange:NSMakeRange(0, 5) withString:@"HELLO"];
		[store replaceCharactersInRange:NSMakeRange(6, 5) withString:@"WORLD"];
		check(watcher->did == before, "an edit inside `-beginEditing` does NOT announce itself yet");
		[store endEditing];
		printf("  (note: the group produced %d announcement(s), range (%lu,%lu), mask %lu, delta %ld)\n",
		       watcher->did - before, (unsigned long)watcher->lastRange.location,
		       (unsigned long)watcher->lastRange.length, (unsigned long)watcher->lastMask,
		       (long)watcher->lastDelta);
		check(watcher->did == before + 1, "and closing the group announces ONCE for the two of them");
		check(range_is(watcher->lastRange, 0, 11), "over the UNION of the two ranges");
		check(watcher->lastMask == NSTextStorageEditedCharacters, "with the mask they share");
		check([[store string] isEqualToString:@"HELLO WORLD"], "and both edits really happened");
	}

	/* 5. **AND A GROUP WHOSE EDITS MOVE THE LENGTH REPORTS THE SUM, WITH THE RANGES IN THE ORIGINAL'S COORDINATES.**
	 * The second edit's location was measured against a string the first had already SHORTENED, so the record has to
	 * put it back before the two can be unioned — which is the arithmetic a naive accumulator gets wrong. */
	{
		int before = watcher->did;

		[store beginEditing];
		[store replaceCharactersInRange:NSMakeRange(0, 2) withString:@"X"];	/* -1 */
		[store replaceCharactersInRange:NSMakeRange(0, 0) withString:@"YZ"];	/* +2 */
		[store endEditing];
		printf("  (note: a -1 then a +2 gave delta %ld over range (%lu,%lu), and the store is '%s')\n",
		       (long)watcher->lastDelta, (unsigned long)watcher->lastRange.location,
		       (unsigned long)watcher->lastRange.length, [[store string] UTF8String]);
		check(watcher->did == before + 1, "the second group is announced once too");
		check(watcher->lastDelta == 1, "and the deltas ADD — a one-character net growth");
		check(range_is(watcher->lastRange, 0, 2), "over the original coordinates both edits were measured in");
	}

	/* 6. **AND A DOOR THE STORE NEVER OVERRODE IS STILL ANNOUNCED.** `-insertAttributedString:atIndex:` is the base
	 * class's; the mask reaches the primitive by DISPATCH, which is the whole reason there is one primitive. */
	{
		int before = watcher->did;
		NSAttributedString *piece = [[NSAttributedString alloc] initWithString:@"!"];

		[store insertAttributedString:piece atIndex:0];
		[piece release];
		/* **AND IT MAY BE MORE THAN ONE, WHICH IS THE BASE CLASS'S BUSINESS RATHER THAN THIS CLASS'S.** An attributed
		 * insert sets the CHARACTERS and then the ATTRIBUTES, and each of those is a primitive — so an insert is two
		 * announcements (one per mask) and WOULD BE ONE inside a `-beginEditing`/`-endEditing` group. What is asserted is
		 * the routing: the store never overrode this door and was still told. */
		printf("  (note: inserting through the base class's door announced %d time(s))\n", watcher->did - before);
		check(watcher->did > before,
		      "an edit through a door the store did NOT override is announced — the routing, not a copy");
	}

	/* 7. **AND A LISTENER THAT CONFORMS TO NOTHING IS TOLD THE SAME TWO BY NAME.** */
	{
		__block int posts = 0;
		id token = [center addObserverForName:NSTextStorageDidProcessEditingNotification object:store
						 queue:nil usingBlock:^(NSNotification *n) {
			(void)n;
			posts++;
		}];

		[store replaceCharactersInRange:NSMakeRange(0, 0) withString:@"?"];
		check(posts == 1, "a listener registered for the DID notification is told without conforming to anything");
		[center removeObserver:token];
	}

	/* ============================================================================================
	 * AND THE 10.0 DOORS: CHARACTERS, WORDS, PARAGRAPHS, RUNS AND THE TWO WHOLE-RANGE ATTRIBUTES.
	 * ============================================================================================ */
	{
		NSTextStorage *old = [[NSTextStorage alloc] initWithString:@"one two\nthree"];

		/* 1. THE TWO DECOMPOSITIONS THAT ARE THE ERA'S RULES RATHER THAN A MODERN BREAKER. */
		check([[old words] count] == 3, "`-words` splits the runs between whitespace, and a newline is whitespace");
		check([[[old words] objectAtIndex:2] isEqual:@"three"], "in order, with the words themselves");
		check([[old paragraphs] count] == 2, "`-paragraphs` splits at the newlines");
		check([[[old paragraphs] objectAtIndex:1] isEqual:@"three"], "and answers the second line's text");
		check([[old characters] count] == [old length], "`-characters` answers one string per unit of the string");
		check([[[old characters] objectAtIndex:3] isEqual:@" "], "which is the character itself, spaces included");

		/* 2. THE SETTERS REPLACE THE WHOLE CONTENTS — AND ANNOUNCE IT LIKE ANY OTHER EDIT. */
		[old setWords:[NSArray arrayWithObjects:@"alpha", @"beta", nil]];
		check([[old string] isEqual:@"alpha beta"], "`-setWords:` joins with single spaces");
		[old setParagraphs:[NSArray arrayWithObjects:@"first", @"second", @"third", nil]];
		check([[old string] isEqual:@"first\nsecond\nthird"], "`-setParagraphs:` joins with newlines");
		[old setCharacters:[NSArray arrayWithObjects:@"a", @"b", @"c", nil]];
		check([[old string] isEqual:@"abc"], "`-setCharacters:` concatenates the array");

		/* 3. THE FONT AND THE COLOUR ARE ONE ATTRIBUTE OVER THE WHOLE RANGE, and a store with no characters answers
		 * nil rather than an attribute nobody set. */
		check([old font] == nil && [old foregroundColor] == nil,
		      "a store with no font or colour set answers nil for both");
		[old setFont:[NSFont systemFontOfSize:13.0]];
		[old setForegroundColor:[NSColor redColor]];
		check([old font] != nil && [[old font] pointSize] == 13.0,
		      "`-setFont:` applies the font to the whole text, and `-font` reads it back");
		check([[old foregroundColor] isEqual:[NSColor redColor]],
		      "and the same for the foreground colour");
		check([old attributeRuns] != nil && [[old attributeRuns] count] == 1,
		      "with one uniform run over the whole text");
		[old setForegroundColor:nil];
		check([old foregroundColor] == nil, "and a nil colour REMOVES the attribute rather than storing a nil");

		/* 4. THE RUNS ARE READ FROM THE ATTRIBUTES, so two runs are two objects with the ranges they came from. */
		{
			NSTextStorage *runs = [[NSTextStorage alloc] initWithString:@"abcdef"];
			NSArray *read;

			[runs addAttribute:@"Colour" value:@"red" range:NSMakeRange(0, 3)];
			[runs addAttribute:@"Colour" value:@"blue" range:NSMakeRange(3, 3)];
			read = [runs attributeRuns];
			check([read count] == 2, "two attribute ranges are two runs");
			check([read count] == 2 && [[(NSAttributedString *)[read objectAtIndex:0] string] isEqual:@"abc"],
			      "the first is the characters the first range covers");
			/* **THE ATTRIBUTES ARE READ AT AN INDEX, NOT IN BULK**: this layer's `NSAttributedString` has no
			 * `-attributes` (one run's worth of attributes is what an attributed string has), so a probe asks at 0. */
			check([read count] == 2 &&
			      [[[(NSAttributedString *)[read objectAtIndex:1] attributesAtIndex:0 effectiveRange:NULL]
				  objectForKey:@"Colour"] isEqual:@"blue"],
			      "and its attributes are the ones that were set");

			/* AND WRITING THEM BACK REPLACES THE CONTENTS, ATTRIBUTES AND ALL. */
			[runs setAttributeRuns:read];
			check([[runs string] isEqual:@"abcdef"], "`-setAttributeRuns:` puts back the same characters");
			check([[[runs attributesAtIndex:4 effectiveRange:NULL] objectForKey:@"Colour"] isEqual:@"blue"],
			      "and the same attributes, run for run");
			[runs release];
		}
		[old release];
	}

	[watcher release];
	[store release];
	[pool release];
	printf("text_storage: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
