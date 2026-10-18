/*
 * NSAttributedStringRTFD.m — RTFD: the same RTF document, wrapped in a package that carries its pictures as files.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **RTFD IS RTF PLUS A DIRECTORY, AND THAT IS THE WHOLE IDEA.** A standalone RTF file carries a picture INLINE, as
 * `{\pict\pngblip…}` hex — which is what this tier's RTF writer has always done — and a package document carries each
 * attachment as a FILE beside the text, with the text REFERRING to it by name. So the document is a directory holding
 * `TXT.rtf` and one file per attachment, and `{\NeXTGraphic <filename> \width<twips>\height<twips>}` is the reference
 * the format uses. The advantage is not cosmetic: a picture is stored once, byte-for-byte, instead of as hex inside a
 * text stream, and a package can carry any file at all rather than only the two image formats a blip can name.
 *
 * **AND THE TEXT PART IS THE RTF WRITER'S, NOT A SECOND ONE.** `fn_rtf_text` (`NSAttributedStringRTF_internal.h`) takes
 * a sink: with none it writes the inline picture it always wrote, and with one it writes the reference and hands back
 * the bytes. Two writers would be two chances for the package's `TXT.rtf` to disagree with what `-RTFRepresentation`
 * answers, and a reader would then have to guess which one wrote the file.
 *
 * **AND WHERE THIS LIVES IS THE APPKIT HALF, WHICH IS WHY `libagora-base` REFUSES THE SAME DOORS.** Base declares
 * `-RTFDFileWrapperFromRange:documentAttributes:` and refuses it, because "RTFD needs an attachment no class here
 * defines" — the attachment is `NSTextAttachment`, which is AppKit's. The declaration is base's and the implementation
 * is here, so a caller that links the AppKit gets the format and a caller that links only Foundation gets the named
 * refusal it always got.
 *
 * **WHAT IS NOT HERE, NAMED**: reading a package back (`-initWithRTFD:documentAttributes:` and
 * `-initWithRTFDFileWrapper:documentAttributes:`), which the RTF reader would need to learn `\NeXTGraphic` for and to
 * be handed the package's files; and document attributes, which neither writer produces yet.
 */
#import "NSAttributedStringRTF_internal.h"

#import <AppKit/NSAttributedString.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

/* THE PACKAGE'S TEXT FILE, which is the name every RTFD reader looks for. */
static NSString *const kRTFDPackageTextName = @"TXT.rtf";

/* **THE PACKAGE, BUILT FROM THE WRITER'S OWN OUTPUT.** The text goes in as `TXT.rtf`; every attachment the writer
 * referred to goes in as a regular file under the name the text uses, so the reference and the file cannot disagree —
 * they are the same string. The wrapper is a DIRECTORY wrapper because that is what a package is, and its children are
 * keyed by their preferred filenames, which is what makes the serialized form reproducible. */
static NSFileWrapper *fn_rtfd_package(NSAttributedString *self, NSRange range, NSDictionary *dict)
{
	NSAttributedString *piece;
	NSMutableDictionary *attachmentFiles;
	NSMutableDictionary *children;
	NSString *text;
	NSFileWrapper *package;
	NSEnumerator *names;
	NSString *name;

	(void)dict;	/* document attributes are not produced yet — see the note at the top of this file. */
	if (range.location + range.length > [self length]) {
		fprintf(stderr, "APPKIT-REFUSE: -RTFDFileWrapperFromRange:documentAttributes: was given a range "
				"past the end of the string\n");
		return nil;
	}
	piece = (range.length == [self length] && range.location == 0)
		? self : [self attributedSubstringFromRange:range];
	attachmentFiles = [NSMutableDictionary dictionary];
	text = fn_rtf_text(piece, attachmentFiles);
	if (text == nil) {
		return nil;
	}
	children = [NSMutableDictionary dictionary];
	{
		NSData *textBytes = [text dataUsingEncoding:NSUTF8StringEncoding];
		NSFileWrapper *textFile = [[NSFileWrapper alloc] initRegularFileWithContents:textBytes];

		[textFile setPreferredFilename:kRTFDPackageTextName];
		[children setObject:textFile forKey:kRTFDPackageTextName];
		[textFile release];
	}
	names = [attachmentFiles keyEnumerator];
	while ((name = [names nextObject]) != nil) {
		NSFileWrapper *file = [[NSFileWrapper alloc] initRegularFileWithContents:
			[attachmentFiles objectForKey:name]];

		[file setPreferredFilename:name];
		[children setObject:file forKey:name];
		[file release];
	}
	package = [[[NSFileWrapper alloc] initDirectoryWithFileWrappers:children] autorelease];
	if (package == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -RTFDFileWrapperFromRange:documentAttributes: could not make the "
				"package directory\n");
	}
	return package;
}

/* **AND THE SAME DOCUMENT AS DATA**, which is the serialized form of that package — the representation a pasteboard
 * and a document file both take. It is not the RTF bytes: a caller that wants the text alone asks `-RTFRepresentation`. */
/* **AND IT IS INSTALLED FROM A CONSTRUCTOR RATHER THAN A CATEGORY METHOD**, for the reason this tree has already
 * recorded once: a category's methods are not what a runtime necessarily prefers over the class's own, and this task's
 * first attempt — a category implementation of the same selectors — was MEASURED LOSING to `libagora-base`'s refusal,
 * which is what the probe printed. A constructor runs when this library loads, so the seam is filled before any caller
 * can ask, and the two doors in Foundation dispatch to this one function.
 *
 * A CONSTRUCTOR RATHER THAN `+load` IS ALSO THE TREE'S OWN CHOICE (see `FNCURLURLProtocol.m`), for the same ordering
 * reason: the dynamic loader runs a dependency's constructors before its dependents', so nothing here can run before
 * Foundation is ready to be told. */
__attribute__((constructor)) static void fn_install_rtfd_writer(void)
{
	_NSAttributedStringSetRTFDWriter(fn_rtfd_package);
}
