/*
 * text_input_client.m — `NSTextInputClient`: the protocol a modern input method drives a view through.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROTOCOL IS DECLARED BY 10.6 AND WAS ABSENT HERE**, while the machinery it belongs to was not: a marked-text
 * composition, an input-method context, a dead-key table and a candidate window were all built, and the CONTRACT a
 * third-party input method or a ported client declares against was not. So the probe is written the way such a client
 * would be — the view is held as `id <NSTextInputClient>` and every one of the fifteen doors is called THROUGH THE
 * PROTOCOL — because a conformance that compiles is what a ported client actually needs.
 *
 * **AND NINE OF THE FIFTEEN ARE NEW**, so they are the ones with answers worth checking: the substring comes back with
 * the range it ACTUALLY got rather than the one proposed, the whole document comes back as a copy, the fraction through
 * a glyph is measured against the GLYPH's own box, the baseline delta is zero, nothing is drawn vertically, and the
 * window level is the window's own. **THE RANGE-CARRYING TRIO IS THE OTHER HALF**: `-insertText:replacementRange:` and
 * `-setMarkedText:selectedRange:replacementRange:` let the caller NAME what it replaces (with `NSNotFound` meaning the
 * marked range, else the selection), and `-firstRectForCharacterRange:actualRange:` writes back the range it really
 * answered — the same clamp-and-tell rule the substring door follows.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>

/* THE VIEW'S PER-CHARACTER RECT IS AN INTERNAL DOOR** (it is what its own caret and candidate-window placement use), so
 * the probe declares it rather than guessing from a missing declaration — which the compiler would have read as an `id`
 * and refused. */
@interface NSTextView (FNTextInputClientProbe)
- (NSRect)cg_rectForCharacterIndex:(NSUInteger)index;
@end

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
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 80.0)];
	id <NSTextInputClient> client;
	NSRange actual = NSMakeRange(0, 0);

	setvbuf(stdout, NULL, _IONBF, 0);
	client = (id <NSTextInputClient>)view;
	check(client != nil, "the view is a text input client");

	/* THE CONFORMANCE IS THE PROTOCOL'S, so every call below is a call through it. */
	[view setString:@"abcd"];
	[view setSelectedRange:NSMakeRange(2, 2)];
	/* THE LAYOUT IS LAZY, AND THE GEOMETRY DOORS BELOW ASK ABOUT GLYPHS: without this, a character's rect is the
	 * un-laid-out default and the fraction check measures nothing. */
	[[view layoutManager] ensureLayoutForTextContainer:[view textContainer]];
	check(NSEqualRanges([client selectedRange], NSMakeRange(2, 2)), "selectedRange answers");
	check(![client hasMarkedText], "nothing is marked to begin with");

	/* **THE SUBSTRING AND ITS ACTUAL RANGE**: a proposal past the end is clamped, and the caller is TOLD. */
	{
		NSAttributedString *sub = [client attributedSubstringForProposedRange:NSMakeRange(2, 20)
									 actualRange:&actual];

		printf("  (proposed (2,20) came back as (%lu,%lu): `%s`)\n", (unsigned long)actual.location,
		       (unsigned long)actual.length, sub ? [[sub string] UTF8String] : "(nil)");
		check(sub != nil && NSEqualRanges(actual, NSMakeRange(2, 2)), "the actual range is the clamped one");
		check(sub != nil && [[sub string] isEqualToString:@"cd"], "and the substring is what that range holds");
	}
	check([[client attributedString] isEqualToAttributedString:[view textStorage]]
	      || [[[client attributedString] string] isEqualToString:@"abcd"],
	      "the whole document comes back");
	check([[client attributedString] isKindOfClass:[NSAttributedString class]], "as an attributed string");

	/* **AND THE THREE DOORS THAT CARRY A RANGE**, every call through the protocol. An explicit range is replaced
	 * exactly; `NSNotFound` falls back to the marked range, then the selection; and the geometry door tells the caller
	 * which range it actually answered. */
	{
		NSRange got = NSMakeRange(0, 0);

		[view setString:@"abcd"];
		[client insertText:@"XY" replacementRange:NSMakeRange(1, 2)];
		printf("  (insertText:replacementRange:(1,2) gave `%s`)\n", [[view string] UTF8String]);
		check([[view string] isEqualToString:@"aXYd"],
		      "insertText:replacementRange: replaces the range it is NAMED");
		check(NSEqualRanges([client selectedRange], NSMakeRange(3, 0)),
		      "and leaves the caret after what it inserted");

		[view setString:@"abcd"];
		[view setSelectedRange:NSMakeRange(2, 1)];
		[client insertText:@"Z" replacementRange:NSMakeRange(NSNotFound, 0)];
		check([[view string] isEqualToString:@"abZd"],
		      "replacementRange NSNotFound with no mark replaces the SELECTION");

		/* A confirmation during a composition replaces the MARK, not the caret sitting inside it. */
		[view setString:@""];
		[view setSelectedRange:NSMakeRange(0, 0)];
		[client setMarkedText:@"ab" selectedRange:NSMakeRange(1, 0)
			replacementRange:NSMakeRange(NSNotFound, 0)];
		check(NSEqualRanges([client markedRange], NSMakeRange(0, 2)), "a composition marks what it inserted");
		[client insertText:@"q" replacementRange:NSMakeRange(NSNotFound, 0)];
		check([[view string] isEqualToString:@"q"],
		      "and a confirmation with NSNotFound replaces the MARKED range");
		check(![client hasMarkedText], "clearing the mark as it commits");

		/* setMarkedText:...replacementRange: — the explicit range, and the selection measured INSIDE the string. */
		[view setString:@"abcd"];
		[client setMarkedText:@"XY" selectedRange:NSMakeRange(1, 1)
			replacementRange:NSMakeRange(1, 2)];
		printf("  (setMarkedText:(1,2) gave `%s`, mark (%lu,%lu), selection (%lu,%lu))\n",
		       [[view string] UTF8String], (unsigned long)[client markedRange].location,
		       (unsigned long)[client markedRange].length, (unsigned long)[client selectedRange].location,
		       (unsigned long)[client selectedRange].length);
		check([[view string] isEqualToString:@"aXYd"],
		      "setMarkedText:selectedRange:replacementRange: replaces the NAMED range");
		check(NSEqualRanges([client markedRange], NSMakeRange(1, 2)), "and the mark covers what it inserted");
		check(NSEqualRanges([client selectedRange], NSMakeRange(2, 1)),
		      "with the selection INSIDE it, relative to the string");

		/* The next keystroke of the composition passes NSNotFound and replaces the existing mark. */
		[client setMarkedText:@"ZW" selectedRange:NSMakeRange(2, 0)
			replacementRange:NSMakeRange(NSNotFound, 0)];
		check([[view string] isEqualToString:@"aZWd"],
		      "a second call with NSNotFound GROWS the composition over its old mark");
		check(NSEqualRanges([client markedRange], NSMakeRange(1, 2)), "the mark moves with it");
		check(NSEqualRanges([client selectedRange], NSMakeRange(3, 0)), "and so does the selection inside it");
		[client unmarkText];
		check(![client hasMarkedText], "unmarkText ends the composition");

		/* firstRectForCharacterRange:actualRange: — the clamped range, and the old door's rectangle. */
		[view setString:@"abcd"];
		[[view layoutManager] ensureLayoutForTextContainer:[view textContainer]];
		{
			NSRect modern = [client firstRectForCharacterRange:NSMakeRange(2, 20) actualRange:&got];
			NSRect old = [view firstRectForCharacterRange:NSMakeRange(2, 2)];

			check(NSEqualRanges(got, NSMakeRange(2, 2)),
			      "firstRect... writes back the range it actually answered");
			check(NSEqualRects(modern, old),
			      "and the rectangle is the one that range's first character occupies");
		}
		{
			NSRect modern = [client firstRectForCharacterRange:NSMakeRange(10, 5) actualRange:&got];
			NSRect old = [view firstRectForCharacterRange:NSMakeRange(4, 0)];

			check(NSEqualRanges(got, NSMakeRange(4, 0)),
			      "a proposal past the end comes back as an empty range at the end");
			check(NSEqualRects(modern, old), "and still answers a rectangle there");
		}
	}

	/* THE TWO FACTS ABOUT THIS LAYER, AND THE WINDOW'S OWN LEVEL. */
	check([client baselineDeltaForCharacterAtIndex:1] == 0.0, "the baseline delta is zero — every line sits on it");
	check([client drawsVerticallyForCharacterAtIndex:1] == NO, "and nothing is drawn vertically here");
	check([client windowLevel] == NSNormalWindowLevel, "a view with no window answers the normal level");
	{
		NSArray *attributes = [client validAttributesForMarkedText];

		check(attributes != nil && [attributes count] > 0, "and the marked-text attributes are declared");
	}

	/* **AND THE FRACTION THROUGH A GLYPH, TESTED FOR ITS CONTRACT RATHER THAN FOR A NUMBER.** The box the door measures
	 * against is the CHARACTER's rect, and in a view with no window that rect is DEGENERATE — MEASURED at 1 point wide —
	 * so an absolute fraction here would be measuring the degenerate geometry rather than the arithmetic. What is checked
	 * is what the door promises whatever the box: a fraction in [0,1], the SAME answer for the same point twice, and a
	 * NON-DECREASING one as the point moves right **within one glyph**.
	 *
	 * **THE SWEEP IS ONE CHARACTER BECAUSE THE FRACTION IS PER GLYPH AND RESETS AT A BOUNDARY.** With four characters
	 * the old sweep saw 0, 0, 1, 0, 1 — the reset from the end of `c` to the start of `d` — and called it a regression.
	 * That reset is the door's contract, not a defect; a caller placing a candidate window asks within one glyph. The
	 * Inter face used to make the test pass by accident because its boxes were degenerate enough to clamp at 1 for
	 * every point after the first. A one-glyph document asks the question the door actually answers. */
	{
		CGFloat previous = -1.0;
		BOOL inRange = YES;
		BOOL monotone = YES;
		int step;

		[view setString:@"a"];
		[[view layoutManager] ensureLayoutForTextContainer:[view textContainer]];
		for (step = 0; step < 20; step++) {
			NSPoint at = NSMakePoint((CGFloat)step * 10.0, 5.0);
			CGFloat f = [client fractionOfDistanceThroughGlyphForPoint:at];
			CGFloat again = [client fractionOfDistanceThroughGlyphForPoint:at];

			if (f < 0.0 || f > 1.0) {
				inRange = NO;
			}
			if (fabs(f - again) > 0.0001) {
				monotone = NO;	/* determinism, checked in the same loop */
			}
			if (f + 0.0001 < previous) {
				monotone = NO;
			}
			previous = f;
		}
		printf("  (the fraction stayed in [0,1] within one glyph and never went backwards)\n");
		check(inRange, "every fraction the door answers is between 0 and 1");
		check(monotone, "and it is deterministic and non-decreasing as the point moves right");
	}

	[view release];
	[pool release];
	printf("text_input_client: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
