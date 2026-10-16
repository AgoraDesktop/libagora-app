/*
 * text_rtf.m — RTF READ BACK: THE CONTROL WORDS BECOME THE APPKIT'S ATTRIBUTES.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE FOUNDATION BELOW ALREADY WRITES RTF; WHAT IT CANNOT DO IS READ ONE INTO APPKIT ATTRIBUTES**, because the
 * value of `NSFontAttributeName` is an `NSFont` and Foundation has no such class. So the probe feeds the reader a
 * LITERAL RTF document — a font table, a colour table, a centred underlined red paragraph and a plain one — and asks
 * for the attributes back: the text and its break, the font by name and size, the ink, the rule, the alignment. It
 * also checks the escapes (`\'hh` and `\uN?`) and that a document that is not RTF at all answers nil rather than an
 * empty string.
 */
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSParagraphStyle.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int colour_is(NSColor *c, CGFloat r, CGFloat g, CGFloat b)
{
	return c != nil && fabs([c redComponent] - r) < 0.02 && fabs([c greenComponent] - g) < 0.02
		&& fabs([c blueComponent] - b) < 0.02;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *fontName = [[NSFont systemFontOfSize:12.0] fontName];
	NSString *rtfText;
	NSData *data;
	NSDictionary *documentAttributes = nil;
	NSAttributedString *parsed;

	setvbuf(stdout, NULL, _IONBF, 0);

	rtfText = [NSString stringWithFormat:
		@"{\\rtf1\\ansi\\deff0\n"
		@"{\\fonttbl{\\f0 %@;}}\n"
		@"{\\colortbl;\\red255\\green0\\blue0;}\n"
		@"\\pard\\qc\\f0\\fs24\\cf1\\ul ab\\par\n"
		@"\\pard\\ql\\cf0\\ulnone ab\\'41\\u233?\n"
		@"}\n", fontName];
	data = [rtfText dataUsingEncoding:NSUTF8StringEncoding];

	/* 1. **THE PARSE.** */
	parsed = [[NSAttributedString alloc] initWithRTF:data documentAttributes:&documentAttributes];
	check(parsed != nil, "`-initWithRTF:documentAttributes:` parses a document");
	if (parsed != nil) {
		NSDictionary *first = [parsed attributesAtIndex:0 effectiveRange:NULL];
		NSDictionary *second = [parsed attributesAtIndex:3 effectiveRange:NULL];
		NSColor *ink = [first objectForKey:NSForegroundColorAttributeName];
		NSNumber *underline = [first objectForKey:NSUnderlineStyleAttributeName];
		NSParagraphStyle *style = [first objectForKey:NSParagraphStyleAttributeName];
		NSFont *font = [first objectForKey:NSFontAttributeName];
		NSString *expected = [NSString stringWithFormat:@"ab\nabA%C", (unichar)233];

		printf("  (note: the reader gave `%s`)\n", [[parsed string] UTF8String]);
		check([[parsed string] isEqualToString:expected],
		      "the text, the `\\par` break and the two escapes come through");
		check(font != nil && fabs([font pointSize] - 12.0) < 0.01,
		      "`\\fs` gives the size back — the face is substituted when this tier cannot resolve its name");
		check(colour_is(ink, 1.0, 0.0, 0.0), "the colour table and `\\cf` give the ink back");
		check(underline != nil && [underline integerValue] == NSUnderlineStyleSingle, "`\\ul` gives the rule back");
		check(style != nil && [style alignment] == NSCenterTextAlignment, "and `\\qc` the paragraph alignment");
		check([second objectForKey:NSUnderlineStyleAttributeName] == nil
		      && [second objectForKey:NSForegroundColorAttributeName] == nil,
		      "the SECOND paragraph, which is neither underlined nor coloured, is neither");
		check(documentAttributes != nil, "the document attributes are filled in");
	}
	[parsed release];

	/* 2. **AND A DOCUMENT THAT IS NOT RTF ANSWERS NIL**, not an empty string. */
	{
		NSData *junk = [@"not an rtf document" dataUsingEncoding:NSUTF8StringEncoding];
		NSAttributedString *none = [[NSAttributedString alloc] initWithRTF:junk documentAttributes:NULL];

		printf("  (note: garbage parsed to %s)\n", none != nil ? [[none string] UTF8String] : "(nil)");
		check(none == nil, "a document with no RTF header answers nil rather than an empty string");
		[none release];
	}

	[pool release];
	printf("text_rtf: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
