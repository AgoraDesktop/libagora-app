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

	/* 3. **AND THE WRITER, WHICH IS THE SAME CODEC THE OTHER WAY.** An AppKit-attributed string with a font, an ink, a
	 * ground, the two rules and a centred paragraph is written and read back, and the two agree — which is what "keyed
	 * on the APPKIT's attributes" has to mean. The bytes are checked for the tables and the control words too, so a
	 * writer that wrote nothing readable would fail even if a later reader invented the attributes. */
	{
		NSMutableAttributedString *rich;
		NSMutableParagraphStyle *centre = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		NSFont *font = [NSFont systemFontOfSize:12.0];
		NSData *written;
		NSAttributedString *back;
		NSString *bytes;
		NSUInteger len;

		[centre setAlignment:NSCenterTextAlignment];
		rich = [[NSMutableAttributedString alloc] initWithString:@"ab\tcd\n\u00e9w"];
		len = [rich length];
		[rich addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, len)];
		[rich addAttribute:NSParagraphStyleAttributeName value:centre range:NSMakeRange(0, len)];
		[rich addAttribute:NSForegroundColorAttributeName value:[NSColor redColor] range:NSMakeRange(0, 2)];
		[rich addAttribute:NSBackgroundColorAttributeName value:[NSColor greenColor] range:NSMakeRange(0, 2)];
		[rich addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
			    range:NSMakeRange(0, 2)];
		[rich addAttribute:NSStrikethroughStyleAttributeName value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
			    range:NSMakeRange(3, 2)];
		written = [rich RTFRepresentation];
		bytes = [[[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding] autorelease];
		printf("  (note: the writer produced %lu byte(s))\n", (unsigned long)[written length]);
		check(written != nil && [written length] > 0, "`-RTFRepresentation` writes bytes");
		check(bytes != nil && [bytes rangeOfString:@"\\rtf1"].location != NSNotFound
		      && [bytes rangeOfString:@"\\fonttbl"].location != NSNotFound
		      && [bytes rangeOfString:@"\\colortbl"].location != NSNotFound,
		      "with an RTF header, a font table and a colour table");
		check([bytes rangeOfString:@"\\ul "].location != NSNotFound
		      && [bytes rangeOfString:@"\\qc "].location != NSNotFound
		      && [bytes rangeOfString:@"\\tab "].location != NSNotFound,
		      "and the control words for the rule, the alignment and the tab");

		back = [[NSAttributedString alloc] initWithRTF:written documentAttributes:NULL];
		check(back != nil, "and the READER takes it back");
		if (back != nil) {
			NSDictionary *first = [back attributesAtIndex:0 effectiveRange:NULL];
			NSDictionary *struck = [back attributesAtIndex:3 effectiveRange:NULL];
			NSFont *fontBack = [first objectForKey:NSFontAttributeName];
			NSParagraphStyle *styleBack = [first objectForKey:NSParagraphStyleAttributeName];

			printf("  (note: the round trip gave `%s`)\n", [[back string] UTF8String]);
			check([[back string] isEqualToString:[rich string]],
			      "the text, the break, the tab and the non-ASCII character survive");
			check(fontBack != nil && fabs([fontBack pointSize] - 12.0) < 0.01, "`\\fs` gives the size back");
			check(colour_is([first objectForKey:NSForegroundColorAttributeName], 1.0, 0.0, 0.0)
			      && colour_is([first objectForKey:NSBackgroundColorAttributeName], 0.0, 1.0, 0.0),
			      "the ink and the ground come back");
			check([first objectForKey:NSUnderlineStyleAttributeName] != nil, "the underline comes back");
			check([struck objectForKey:NSStrikethroughStyleAttributeName] != nil, "and the strikethrough");
			check(styleBack != nil && [styleBack alignment] == NSCenterTextAlignment, "and the alignment");
		}
		[back release];
		[rich release];
		[centre release];
	}

	[pool release];
	printf("text_rtf: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
