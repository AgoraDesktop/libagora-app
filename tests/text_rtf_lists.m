/*
 * text_rtf_lists.m — lists in the RTF writer: the `{\listtable}` and the paragraph's `\ls`/`\ilvl`.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **WHAT THIS MEASURES IS THE SHAPE THE FORMAT REQUIRES, NOT THAT SOMETHING CALLED A LIST WAS WRITTEN.** Three things
 * have to be true together to be a list a reader can reconstruct: the definitions are in the HEADER as a `{\listtable}`
 * with one `{\list}` per distinct stack; each definition says its NUMBER FORMAT with `\levelnfc` (0 decimal, 23 bullet),
 * which is the only thing that survives a round trip into `NSTextList`; and each paragraph says which list it is in with
 * `\ls` and how deep with `\ilvl`. A writer that emitted the table and no `\ls`, or the `\ls` and no table, would pass
 * any check that only looked for one of them.
 *
 * **AND THE TEXT IS CHECKED FOR WHAT IT MUST NOT CONTAIN**: no marker text. The list lives in the paragraph style and the
 * marker is drawn from it, so a writer that also wrote `1.` into the string would double the marker in every reader that
 * honours the style — and would look correct in this one, which is why it is asserted rather than assumed.
 */
#import <AppKit/NSAttributedString.h>
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

static BOOL mentions(NSString *text, const char *needle)
{
	return [text rangeOfString:[NSString stringWithUTF8String:needle]].location != NSNotFound;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableAttributedString *store;
	NSTextList *decimal;
	NSTextList *disc;
	NSMutableParagraphStyle *outer;
	NSMutableParagraphStyle *nested;
	NSMutableParagraphStyle *plain;
	NSData *data;
	NSString *rtf;

	setvbuf(stdout, NULL, _IONBF, 0);
	decimal = [[NSTextList alloc] initWithMarkerFormat:@"{decimal}" options:0];
	disc = [[NSTextList alloc] initWithMarkerFormat:@"{disc}" options:0];
	[decimal setStartingItemNumber:5];

	store = [[NSMutableAttributedString alloc] initWithString:@"first\nsecond\nthird\n"];
	outer = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[outer setTextLists:[NSArray arrayWithObject:decimal]];
	nested = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[nested setTextLists:[NSArray arrayWithObjects:decimal, disc, nil]];
	plain = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	/* The first paragraph is in ONE list, the second in TWO (decimal outside, disc inside), the third in none. */
	[store addAttribute:NSParagraphStyleAttributeName value:outer range:NSMakeRange(0, 6)];
	[store addAttribute:NSParagraphStyleAttributeName value:nested range:NSMakeRange(6, 7)];

	data = [store RTFRepresentation];
	rtf = (data != nil) ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
	check(rtf != nil, "the store writes as RTF");
	if (rtf != nil) {
		printf("  (the RTF is %lu bytes)\n", (unsigned long)[rtf length]);
		check(mentions(rtf, "{\\listtable"), "the definitions are a `{\\listtable}` group in the header");
		check(mentions(rtf, "\\listid1") && mentions(rtf, "\\listid2"),
		      "one `{\\list}` per distinct stack — two here");
		check(mentions(rtf, "\\levelnfc0"), "the numbered list says decimal (0)");
		check(mentions(rtf, "\\levelnfc23"), "and the nested one says bullet (23) for its inner level");
		check(mentions(rtf, "\\levelstartat5"), "and the starting number the list was given (5)");
		check(mentions(rtf, "\\ls1\\ilvl0"), "the first paragraph names its list and depth 0");
		check(mentions(rtf, "\\ls2\\ilvl1"), "the nested paragraph names the OTHER stack and depth 1");
		/* TWO PARAGRAPHS, TWO `\ls` — the third has none, so counting them is the check that the plain paragraph
		 * stayed plain rather than the check that the writer can emit one. */
		{
			unsigned long count = 0;
			NSRange search = NSMakeRange(0, [rtf length]);

			while (YES) {
				NSRange found = [rtf rangeOfString:@"\\ls" options:0 range:search];

				if (found.location == NSNotFound) {
					break;
				}
				count++;
				search = NSMakeRange(NSMaxRange(found), [rtf length] - NSMaxRange(found));
			}
			printf("  (the document names a list %lu time(s) for 3 paragraphs)\n", count);
			check(count == 2, "and only the two listed paragraphs name one");
		}
		/* AND NOTHING WAS INJECTED INTO THE TEXT: the string's own characters are all there, and no `1.` was added. */
		check(mentions(rtf, "first") && mentions(rtf, "second") && mentions(rtf, "third"),
		      "the paragraphs' own text is in the document");
		check(!mentions(rtf, "5.\\tab") && !mentions(rtf, "5. "),
		      "and no marker text was written into it — the marker is drawn from the style");
		[rtf release];
	}
	[store release];
	[plain release];
	[nested release];
	[outer release];
	[disc release];
	[decimal release];
	[pool release];
	printf("text_rtf_lists: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
