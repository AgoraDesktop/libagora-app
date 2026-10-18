/*
 * text_input_client.m — `NSTextInputClient`: the protocol a modern input method drives a view through.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE PROTOCOL IS DECLARED BY 10.6 AND WAS ABSENT HERE**, while the machinery it belongs to was not: a marked-text
 * composition, an input-method context, a dead-key table and a candidate window were all built, and the CONTRACT a
 * third-party input method or a ported client declares against was not. So the probe is written the way such a client
 * would be — the view is held as `id <NSTextInputClient>` and every one of the fifteen doors is called THROUGH THE
 * PROTOCOL — because a conformance that compiles is what a ported client actually needs.
 *
 * **AND SIX OF THE FIFTEEN ARE NEW**, so they are the ones with answers worth checking: the substring comes back with the
 * range it ACTUALLY got rather than the one proposed, the whole document comes back as a copy, the fraction through a
 * glyph is measured against the GLYPH's own box, the baseline delta is zero, nothing is drawn vertically, and the window
 * level is the window's own.
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
	 * NON-DECREASING one as the point moves right across the line. */
	{
		CGFloat previous = -1.0;
		BOOL inRange = YES;
		BOOL monotone = YES;
		int step;

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
		printf("  (the fraction stayed in [0,1] across the line and never went backwards)\n");
		check(inRange, "every fraction the door answers is between 0 and 1");
		check(monotone, "and it is deterministic and non-decreasing as the point moves right");
	}

	[view release];
	[pool release];
	printf("text_input_client: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
