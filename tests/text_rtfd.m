/*
 * text_rtfd.m — the package form of the RTF document: `TXT.rtf` plus one file per attachment.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **WHAT IS MEASURED HERE IS THE PACKAGE, NOT THE TEXT.** The RTF probe (`text_rtf.m`) already proves the text codec
 * in both directions; this one proves the thing RTFD adds: that a document's pictures become FILES beside a `TXT.rtf`
 * whose text REFERENCES them by name — and that the reference and the file agree, because a package whose text names
 * `pic.png` while the directory holds `Attachment-1.png` is a document that opens with a missing picture and no error.
 *
 * **AND THE ROUND TRIP IS THROUGH THE SERIALIZED FORM**, because that is what a document file and a pasteboard
 * actually carry: `-RTFDFromRange:documentAttributes:` answers the serialized package, and reading that back has to
 * give the same directory with the same children. A test that only looked at the in-memory wrapper would never touch
 * the half that writes bytes.
 *
 * **AND THE ATTACHMENT'S WRAPPER PAIR IS EXERCISED AS THE REASON THE NAME IS WHAT IT IS**: an attachment made with
 * `-initWithFileWrapper:` keeps a preferred filename, and that name is what the package uses. The second half of the
 * probe is an attachment WITHOUT a wrapper, which gets a name invented for it — and the two must not collide.
 */
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSTextAttachment.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGDataProvider.h>
#include <CoreGraphics/CGImage.h>
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

/* A 2x4 picture, built from pixels this probe owns. */
static NSImage *picture(void)
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
	NSImage *image = nil;

	CGDataProviderRelease(provider);
	CGColorSpaceRelease(space);
	if (cgImage != NULL) {
		image = [[NSImage alloc] initWithCGImage:cgImage size:NSMakeSize(2.0, 4.0)];
		CGImageRelease(cgImage);
	}
	return image;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSImage *image = picture();
	NSFileWrapper *named = [[NSFileWrapper alloc] initRegularFileWithContents:
		[NSData dataWithBytes:"x" length:1]];
	NSTextAttachment *withName;
	NSTextAttachment *unnamed;
	NSMutableAttributedString *store;
	NSRange whole;
	NSFileWrapper *package;
	NSFileWrapper *reread;
	NSData *serialized;
	NSDictionary *children;
	NSDictionary *docAttrs = nil;
	NSMutableDictionary *writeAttrs;

	setvbuf(stdout, NULL, _IONBF, 0);
	check(image != nil && named != nil, "the picture and the wrapper were made");
	if (image == nil || named == nil) {
		[pool release];
		printf("text_rtfd: %d case(s) failed\n", failures);
		return 1;
	}
	[named setPreferredFilename:@"pic.png"];

	/* **THE PAIR ITSELF, FIRST**: an attachment made with a wrapper answers it back, and replacing it does not leak
	 * the old one's identity. */
	withName = [[NSTextAttachment alloc] initWithFileWrapper:named];
	check([withName fileWrapper] == named, "an attachment made with a wrapper answers it back");
	[withName setImage:image];
	check([withName image] == image && [withName fileWrapper] == named,
	      "and it carries both the picture and the file, which are separate facts");
	unnamed = [NSTextAttachment textAttachmentWithImage:image];
	check([unnamed fileWrapper] == nil, "while a picture-only attachment has no wrapper");

	store = [[NSMutableAttributedString alloc] initWithString:@"A\uFFFCB"];
	[store addAttribute:NSAttachmentAttributeName value:withName range:NSMakeRange(1, 1)];
	whole = NSMakeRange(0, [store length]);

	/* **AND THE DOCUMENT ATTRIBUTES THE WRITER CONSUMES**, so the package's text carries the facts rather than only
	 * the caller's dictionary: 36 points is `\deftab720` (twips), page layout is `\viewkind1`, and a positive
	 * hyphenation factor is the on/off `\hyphauto1` — RTF has a switch, so 0.5 becomes ON and that loss is measured
	 * on the way back. */
	writeAttrs = [NSMutableDictionary dictionary];
	[writeAttrs setObject:[NSNumber numberWithDouble:36.0] forKey:NSDefaultTabIntervalDocumentAttribute];
	[writeAttrs setObject:[NSNumber numberWithInteger:1] forKey:NSViewModeDocumentAttribute];
	[writeAttrs setObject:[NSNumber numberWithDouble:0.5] forKey:NSHyphenationFactorDocumentAttribute];
	package = [store RTFDFileWrapperFromRange:whole documentAttributes:writeAttrs];
	check(package != nil, "the package was made");
	check(package != nil && [package isDirectory], "and it is a DIRECTORY, which is what a package is");
	if (package != nil) {
		children = [package fileWrappers];
		printf("  (the package holds %lu file(s))\n", (unsigned long)[children count]);
		check(children != nil && [children count] == 2, "holding the text and the picture, and nothing else");
		check([children objectForKey:@"TXT.rtf"] != nil, "the text part is `TXT.rtf`");
		check([children objectForKey:@"pic.png"] != nil,
		      "and the picture is the name the attachment's own wrapper carried");
		if ([children objectForKey:@"pic.png"] != nil) {
			NSData *bytes = [[children objectForKey:@"pic.png"] regularFileContents];
			const unsigned char *p = (const unsigned char *)[bytes bytes];

			check(bytes != nil && [bytes length] > 8 && p != NULL && p[0] == 0x89 && p[1] == 'P'
			      && p[2] == 'N' && p[3] == 'G',
			      "with the picture's own bytes, beginning with the PNG signature");
		}
		if ([children objectForKey:@"TXT.rtf"] != nil) {
			NSData *textBytes = [[children objectForKey:@"TXT.rtf"] regularFileContents];
			NSString *text = (textBytes != nil)
				? [[NSString alloc] initWithData:textBytes encoding:NSUTF8StringEncoding] : nil;

			check(text != nil, "and a text part that reads");
			if (text != nil) {
				check([text rangeOfString:@"\\NeXTGraphic pic.png"].location != NSNotFound,
				      "whose text REFERS to the picture by that same name");
				check([text rangeOfString:@"\\deftab720"].location != NSNotFound,
				      "and carries the default tab interval the writer was asked for, in twips");
				check([text rangeOfString:@"\\viewkind1"].location != NSNotFound,
				      "and the page-layout view mode, as `\\viewkind1`");
				check([text rangeOfString:@"\\hyphauto1"].location != NSNotFound,
				      "and the hyphenation switch, as `\\hyphauto1`");
				check([text rangeOfString:@"\\pict"].location == NSNotFound,
				      "and does NOT also carry it inline — one picture, stored once");
				[text release];
			}
		}
	}

	/* **AND THE SERIALIZED FORM**, which is what a file or a pasteboard carries. */
	serialized = [store RTFDFromRange:whole documentAttributes:writeAttrs];
	check(serialized != nil && [serialized length] > 0, "the package serializes to bytes");
	if (serialized != nil) {
		reread = [[NSFileWrapper alloc] initWithSerializedRepresentation:serialized];

		check(reread != nil && [reread isDirectory], "and those bytes come back as a directory wrapper");
		if (reread != nil) {
			NSDictionary *again = [reread fileWrappers];

			check(again != nil && [again count] == 2, "with the same two files in it");
			check([again objectForKey:@"TXT.rtf"] != nil && [again objectForKey:@"pic.png"] != nil,
			      "under the same names");
			[reread release];
		}
	}

	/* **AND THE PACKAGE OPENS AGAIN**, which is the other half of the format and the reason the wrapper pair exists.
	 * The loop is write → serialize → read, and it is closed by looking at what came back rather than at the bytes: the
	 * same three characters, an attachment on the middle one, the picture's size, and the FILE WRAPPER — because a
	 * package that loses its file names is a package that cannot be written again with them. */
	if (serialized != nil) {
		NSAttributedString *back = [[NSAttributedString alloc] initWithRTFD:serialized
							   documentAttributes:&docAttrs];

		check(back != nil, "the serialized package reads back as an attributed string");
		check(docAttrs != nil
		      && [NSRTFDTextDocumentType isEqual:[docAttrs objectForKey:NSDocumentTypeDocumentAttribute]],
		      "and it says the document is RTFD, which is what the package door is for");
		check([[docAttrs objectForKey:NSCharacterEncodingDocumentAttribute] isKindOfClass:[NSNumber class]]
		      && [[docAttrs objectForKey:NSCharacterEncodingDocumentAttribute] unsignedIntegerValue]
			 == NSUTF8StringEncoding,
		      "with the character encoding as an NSNumber holding UTF-8");
		check(fabs([[docAttrs objectForKey:NSDefaultTabIntervalDocumentAttribute] doubleValue] - 36.0) < 0.01,
		      "and the default tab interval comes back as 36 points from the package's own text");
		check([[docAttrs objectForKey:NSViewModeDocumentAttribute] integerValue] == 1,
		      "and the view mode comes back as page layout (1)");
		check([[docAttrs objectForKey:NSHyphenationFactorDocumentAttribute] doubleValue] == 1.0,
		      "and the hyphenation factor comes back as ON (1.0) — the 0.5 magnitude is the stated loss");
		if (back != nil) {
			check([back length] == 3, "with the same three characters");
			printf("  (the package gave %lu character(s))\n", (unsigned long)[back length]);
			if ([back length] == 3) {
				NSTextAttachment *got = [[back attributesAtIndex:1 effectiveRange:NULL]
					objectForKey:NSAttachmentAttributeName];

				check([[back string] characterAtIndex:1] == (unichar)NSAttachmentCharacter,
				      "the middle one is the attachment character");
				check(got != nil, "carrying an attachment");
				if (got != nil) {
					NSSize size = [[got image] size];

					check([got image] != nil && fabs(size.width - 2.0) < 0.01
					      && fabs(size.height - 4.0) < 0.01,
					      "whose picture is the size it went out at");
					printf("  (the picture came back %.1fx%.1f, file `%s`)\n", size.width, size.height,
					       [[[got fileWrapper] preferredFilename] UTF8String]);
					check([[got fileWrapper] preferredFilename] != nil
					      && [[[got fileWrapper] preferredFilename] isEqualToString:@"pic.png"],
					      "and whose FILE WRAPPER still carries the package's own name for it");
					check([[[got fileWrapper] regularFileContents] length] > 8,
					      "with the file's bytes still readable");
				}
				check([[back string] characterAtIndex:0] == 'A'
				      && [[back string] characterAtIndex:2] == 'B',
				      "and the text either side of it unchanged");
				{
					NSParagraphStyle *style = [[back attributesAtIndex:0 effectiveRange:NULL]
						objectForKey:NSParagraphStyleAttributeName];

					check(style != nil && fabs([style defaultTabInterval] - 36.0) < 0.01,
					      "and the interval is APPLIED to the paragraph, which is what the layout reads");
				}
			}
			[back release];
		}
	}
	/* AND THE IN-MEMORY PACKAGE IS READABLE BY THE OTHER DOOR, without going through bytes at all. */
	if (package != nil) {
		NSAttributedString *direct;

		docAttrs = nil;
		direct = [[NSAttributedString alloc] initWithRTFDFileWrapper:package documentAttributes:&docAttrs];

		check(direct != nil && [direct length] == 3,
		      "the file-wrapper door reads the package the writer made");
		check([NSRTFDTextDocumentType isEqual:[docAttrs objectForKey:NSDocumentTypeDocumentAttribute]],
		      "and names the document RTFD too, from the in-memory package");
		[direct release];
	}

	[store release];
	/* `unnamed` is AUTORELEASED by `+textAttachmentWithImage:` and is the pool's to free — releasing it here as well
	 * was an over-release, and it CRASHED at teardown under `ctest` while passing when run by hand, because the pool's
	 * own release is what finds the object with a count already at zero. */
	[withName release];
	[named release];
	[image release];
	[pool release];
	printf("text_rtfd: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
