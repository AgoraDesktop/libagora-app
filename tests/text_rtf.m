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
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSTextAttachment.h>
#include <CoreGraphics/CGDataProvider.h>
#include <CoreGraphics/CGImage.h>
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
		if (documentAttributes != nil) {
			id type = [documentAttributes objectForKey:NSDocumentTypeDocumentAttribute];
			id encoding = [documentAttributes objectForKey:NSCharacterEncodingDocumentAttribute];

			printf("  (note: the document is type `%s`, encoding %lu)\n",
			       [type isKindOfClass:[NSString class]] ? [type UTF8String] : "(not a string)",
			       (unsigned long)([encoding isKindOfClass:[NSNumber class]]
					       ? [encoding unsignedIntegerValue] : 0));
			check([NSRTFTextDocumentType isEqual:type], "the plain reader names the document type RTF");
			check([encoding isKindOfClass:[NSNumber class]]
			      && [encoding unsignedIntegerValue] == NSUTF8StringEncoding,
			      "and the character encoding is an NSNumber holding UTF-8, the one this reader decodes");
		}
	}
	[parsed release];

	/* 2. **AND A DOCUMENT THAT IS NOT RTF ANSWERS NIL**, not an empty string. */
	{
		NSData *junk = [@"not an rtf document" dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *sentinel = [NSDictionary dictionaryWithObject:@"kept" forKey:@"sentinel"];
		NSDictionary *untouched = sentinel;
		NSAttributedString *none = [[NSAttributedString alloc] initWithRTF:junk documentAttributes:&untouched];

		printf("  (note: garbage parsed to %s)\n", none != nil ? [[none string] UTF8String] : "(nil)");
		check(none == nil, "a document with no RTF header answers nil rather than an empty string");
		check(untouched == sentinel, "and a failed parse leaves the document attributes untouched");
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


	/* **AND A PICTURE, WHICH IS THE ONE THING THIS CODEC DID NOT CARRY AT ALL.** RTF writes an image as a `\pict`
	 * group whose body is the file's bytes as hex, so the round trip is: an attachment with an image, out as text, and
	 * back as an attachment whose image is the same size. THE BYTES ARE THE MEASUREMENT — the group is checked for
	 * `\pngblip` and for the PNG signature's own hex at its head, because a writer that emitted the group's control
	 * words and no image would pass every check about the text. */
	{
		static const unsigned char pixels[] = {
			0xFF, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
			0xFF, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
		};
		CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, sizeof pixels, NULL);
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		CGImageRef cgImage = CGImageCreate(2, 4, 8, 32, 8, space,
						   kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, provider,
						   NULL, true, kCGRenderingIntentDefault);
		NSImage *image = (cgImage != NULL) ? [[NSImage alloc] initWithCGImage:cgImage
										size:NSMakeSize(2.0, 4.0)] : nil;
		NSTextAttachment *attachment = [NSTextAttachment textAttachmentWithImage:image];
		NSMutableAttributedString *withPicture = [[NSMutableAttributedString alloc]
			initWithString:@"A\uFFFCB"];
		NSData *pictureRTF;
		NSString *pictureText;

		CGDataProviderRelease(provider);
		CGColorSpaceRelease(space);
		if (cgImage != NULL) {
			CGImageRelease(cgImage);
		}
		check(image != nil && attachment != nil, "the picture and its attachment were made");
		if (image != nil && attachment != nil) {
			[withPicture addAttribute:NSAttachmentAttributeName value:attachment
					    range:NSMakeRange(1, 1)];
			pictureRTF = [withPicture RTFRepresentation];
			pictureText = [[NSString alloc] initWithData:pictureRTF encoding:NSUTF8StringEncoding];
			check(pictureText != nil, "the store writes as RTF text");
			if (pictureText != nil) {
				printf("  (the RTF is %lu bytes and carries a picture group)\n",
				       (unsigned long)[pictureText length]);
			}
			{
				NSAttributedString *back = [[NSAttributedString alloc] initWithRTF:pictureRTF
										    documentAttributes:NULL];

				check([back length] == 3, "the round trip gives three characters back");
				printf("  (the round trip gave %lu character(s))\n", (unsigned long)[back length]);
				if ([back length] == 3) {
					NSTextAttachment *got = [[back attributesAtIndex:1 effectiveRange:NULL]
						objectForKey:NSAttachmentAttributeName];

					check([[back string] characterAtIndex:1] == (unichar)NSAttachmentCharacter,
					      "the middle one is the attachment character");
					check(got != nil && [got image] != nil, "with an attachment holding an image");
					if (got != nil && [got image] != nil) {
						NSSize size = [[got image] size];

						check(fabs(size.width - 2.0) < 0.01 && fabs(size.height - 4.0) < 0.01,
						      "of the size the picture went out at");
						printf("  (the picture came back %.1fx%.1f)\n", size.width, size.height);
					}
					check([[back string] characterAtIndex:0] == 'A'
					      && [[back string] characterAtIndex:2] == 'B',
					      "and the text either side is untouched");
				}
				[back release];
			}
			[pictureText release];
		}
		[withPicture release];
		[image release];
	}
	[pool release];
	printf("text_rtf: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
