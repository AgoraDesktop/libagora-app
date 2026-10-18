/*
 * text_list.m — `NSTextList`: the marker for an item number, and the paragraph style that carries lists.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLASS IS FIVE DOORS AND ONE OPTION (10.6's whole header), AND ITS ONLY BEHAVIOUR IS ARITHMETIC**: the marker
 * for an item number in a named format. So that is what is measured — every family the implementation claims, with the
 * numbers chosen to be the ones an off-by-one breaks: the Roman subtractive pairs (4, 9, 40, 90), the alphabetic
 * ROLLOVER (26, 27, 52, 53, which is where bijective base 26 stops being base 26), the radix formats, and one bullet
 * per glyph, because a bullet that returned the format string would pass any check that only asked for a non-empty
 * answer.
 *
 * **AND THE PARAGRAPH STYLE IS MEASURED WITH IT**, because a list nobody can attach to a paragraph is a calculator:
 * 10.6 declares `-textLists` beside `-textBlocks`, "nested from outermost to innermost", and a copy of a style must own
 * its own copy of that array — the same value semantics `-textBlocks` already has.
 */
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSTextList.h>
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

static NSTextList *listWith(const char *format)
{
	return [[[NSTextList alloc] initWithMarkerFormat:[NSString stringWithUTF8String:format] options:0] autorelease];
}

static void expect(const char *format, NSInteger item, const char *want)
{
	NSTextList *list = listWith(format);
	NSString *got = [list markerForItemNumber:item];

	printf("  %-20s %4ld -> `%s`\n", format, (long)item, got ? [got UTF8String] : "(nil)");
	check(got != nil && [got isEqualToString:[NSString stringWithUTF8String:want]],
	      "the marker is what the format says");
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* THE POSITIONAL FAMILY. */
	expect("{decimal}", 1, "1");
	expect("{decimal}", 42, "42");
	expect("{lower-hexadecimal}", 255, "ff");
	expect("{upper-hexadecimal}", 255, "FF");
	expect("{octal}", 64, "100");

	/* ROMAN, WHERE THE SUBTRACTIVE PAIRS ARE THE WHOLE RISK. */
	expect("{lower-roman}", 1, "i");
	expect("{lower-roman}", 4, "iv");
	expect("{lower-roman}", 9, "ix");
	expect("{lower-roman}", 40, "xl");
	expect("{lower-roman}", 90, "xc");
	expect("{lower-roman}", 1990, "mcmxc");
	expect("{upper-roman}", 4, "IV");

	/* ALPHABETIC, WHICH IS BIJECTIVE BASE 26: z then aa, not z then ba. */
	expect("{lower-alpha}", 1, "a");
	expect("{lower-alpha}", 26, "z");
	expect("{lower-alpha}", 27, "aa");
	expect("{lower-alpha}", 52, "az");
	expect("{lower-alpha}", 53, "ba");
	expect("{upper-latin}", 27, "AA");

	/* AND THE BULLETS, BY CODE POINT — a format that returned itself would pass a non-empty check. */
	{
		static const struct { const char *format; unsigned code; } bullets[] = {
			{ "{disc}", 0x2022 }, { "{circle}", 0x25E6 }, { "{square}", 0x25AA }, { "{box}", 0x2610 },
			{ "{check}", 0x2713 }, { "{diamond}", 0x25C6 }, { "{hyphen}", '-' }
		};
		size_t i;

		for (i = 0; i < sizeof bullets / sizeof bullets[0]; i++) {
			NSTextList *list = listWith(bullets[i].format);
			NSString *marker = [list markerForItemNumber:7];

			printf("  %-20s    7 -> U+%04X\n", bullets[i].format,
			       (unsigned)(marker != nil && [marker length] > 0 ? [marker characterAtIndex:0] : 0));
			check(marker != nil && [marker length] == 1
			      && (unsigned)[marker characterAtIndex:0] == bullets[i].code,
			      "a bullet is its glyph, and the item number does not change it");
		}
	}

	/* THE DOORS AROUND THE FORMAT: the options as given, the starting number, and a copy that owns them. */
	{
		NSTextList *list = [[NSTextList alloc] initWithMarkerFormat:@"{decimal}"
							    options:NSTextListPrependEnclosingMarker];
		NSTextList *copy;

		[list setStartingItemNumber:5];
		check([list listOptions] == NSTextListPrependEnclosingMarker, "the option is recorded as given");
		check([list startingItemNumber] == 5, "and the starting number with it");
		check([[list markerFormat] isEqualToString:@"{decimal}"], "the format comes back as given");
		copy = [list copy];
		check(copy != nil && copy != list && [copy startingItemNumber] == 5
		      && [copy listOptions] == [list listOptions]
		      && [[copy markerFormat] isEqualToString:[list markerFormat]],
		      "a copy is a separate list carrying the same format, options and starting number");
		[copy release];
		[list release];
	}

	/* AND THE TWO REFUSALS. */
	check(listWith("") != nil ? NO : YES, "a list with no format is refused rather than made");
	{
		NSTextList *unknown = listWith("{ordinal}");

		check([[unknown markerForItemNumber:3] isEqualToString:@"3"],
		      "a format this tier does not know is answered in decimal");
	}

	/* THE PARAGRAPH STYLE, WHICH IS WHERE A LIST LIVES: nested from outermost to innermost, and copied with the style. */
	{
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		NSTextList *outer = listWith("{decimal}");
		NSTextList *inner = listWith("{disc}");
		NSParagraphStyle *copied;

		check([[style textLists] count] == 0, "a style with no lists answers an empty array, not nil");
		[style setTextLists:[NSArray arrayWithObjects:outer, inner, nil]];
		check([[style textLists] count] == 2, "two lists are carried");
		check([[style textLists] objectAtIndex:0] == outer && [[style textLists] objectAtIndex:1] == inner,
		      "outermost first, in the order they were given");
		copied = [style copy];
		check([[copied textLists] count] == 2 && [[copied textLists] objectAtIndex:0] != outer,
		      "and a copy of the style owns its own copies of them");
		check([[[[copied textLists] objectAtIndex:0] markerFormat] isEqualToString:@"{decimal}"]
		      && [[[[copied textLists] objectAtIndex:1] markerFormat] isEqualToString:@"{disc}"],
		      "which still say what the originals said");
		[copied release];
		[style release];
	}

	[pool release];
	printf("text_list: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
