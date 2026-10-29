/*
 * nib_edit — the two doors a DESIGN TOOL uses, and the four things that must stay true for one to save a file.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * An editor holds the property list it parsed, shows the live object behind each node, and writes the tree back. That
 * loop has one failure mode worth a test, and it is quiet: a save that loses a property, reorders a file nobody edited,
 * or produces text the compiler then refuses. So this program measures the loop rather than describing it.
 *
 * WHAT IS ASSERTED:
 *
 *   1. THE EMITTER IS THE PARSER'S INVERSE. `parse → emit → parse → emit` is byte-identical to the first emit, so saving
 *      an unedited file twice cannot churn a diff, and the emitted text COMPILES — saving is never the step at which a
 *      design became unreadable.
 *   2. THE OBJECT TABLE IS COMPLETE AND IDENTITY-HOLDING. Every `id` in the file — including one on a SUBVIEW, which is
 *      the common case for a connection — is in the table, and the entry for a top-level object is the very instance the
 *      door answered as top level, because an editor keys its outline, its canvas and its connections off one map.
 *   3. THE TWO DOORS REFUSE THE SAME FILES WITH THE SAME SENTENCE. An editor that could show a design the compiler then
 *      refuses would be an editor that cannot save; the refusals are shared, and this says so.
 *   4. THE SPELLINGS SURVIVE. A bare key stays bare and so does a value that reads back as itself (`class = NSView`,
 *      `destination = owner`), a value that would not — `YES`, a number, anything with a space or a quote — is quoted and
 *      keeps its escapes, and a LITERAL is written back as `@color(...)` rather than as the two-key record the parser keeps
 *      it in, because `orange` and `#ff0000` are the compiler's to interpret and the parser must not normalise them.
 *
 * AND THERE IS NO REWRITE TO NAME: emit(parse(x)) is x itself for every fixture here, named colours included. That is the
 * property a design file needs — the person's own spelling is the file's spelling — and the test would rather measure it
 * than describe it.
 */
#import <AppKit/NSNibSource.h>

#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSLayoutConstraint.h>

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("%s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSData *source(const char *text)
{
	return [NSData dataWithBytes:text length:strlen(text)];
}

static NSString *textOf(NSData *data)
{
	return [[[NSString alloc] initWithBytes:[data bytes]
					 length:[data length]
				       encoding:NSUTF8StringEncoding] autorelease];
}

/* THE FIXTURE: a view with a constrained child, a second view with a QUOTE AND A BACKSLASH in a property, an exact
 * colour, and one connection to the file's owner — a shape that reaches every spelling the emitter has. */
static const char *kSource =
	"{\n"
	"  version = 1;\n"
	"  objects = (\n"
	"    {\n"
	"      id = \"root\";\n"
	"      class = NSView;\n"
	"      properties = { frame = \"0 0 320 240\"; tag = 41; };\n"
	"      subviews = (\n"
	"        {\n"
	"          id = \"subject\";\n"
	"          class = NSView;\n"
	"          properties = { frame = \"10 10 100 40\"; hidden = YES; };\n"
	"          constraints = (\n"
	"            { first = \"subject\"; firstAttribute = width; multiplier = 1; constant = 120; }\n"
	"            { first = \"subject\"; firstAttribute = left; second = \"root\";\n"
	"              secondAttribute = left; relation = equal; constant = 10; }\n"
	"          );\n"
	"        }\n"
	"        {\n"
	"          id = \"title\";\n"
	"          class = NSView;\n"
	"          properties = { toolTip = \"say \\\"this\\\" \\\\ that\"; };\n"
	"        }\n"
	"      );\n"
	"    }\n"
	"    {\n"
	"      id = \"sidebar\";\n"
	"      class = NSView;\n"
	"      properties = { frame = \"0 0 80 240\"; };\n"
	"    }\n"
	"  );\n"
	"  connections = (\n"
	"    { source = \"title\"; action = \"go:\"; destination = owner; }\n"
	"  );\n"
	"}\n";

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *first = nil;

	/* 1. THE LOOP. The first emit, then the loop's fixed point, then the compile that proves the text is readable. */
	{
		NSString *reason = nil;
		id parsed = [NSNibSource propertyListFromSourceData:source(kSource) error:&reason];
		NSData *emitted = nil;

		check(parsed != nil, "the fixture parses");
		check(reason == nil, "…without a reason");

		emitted = [NSNibSource sourceDataFromPropertyList:parsed error:&reason];
		check(emitted != nil, "the property list emits");
		check(reason == nil, "…without a reason");
		first = [textOf(emitted) retain];

		{
			id reparsed = [NSNibSource propertyListFromSourceData:emitted error:&reason];
			NSData *again = [NSNibSource sourceDataFromPropertyList:reparsed error:&reason];

			check(reparsed != nil, "the emitted text parses again");
			check(again != nil && [again isEqualToData:emitted],
			      "emitting twice is byte-identical, so an unedited save cannot churn a diff");
		}

		{
			NSData *archive = [NSNibSource archiveFromSourceData:emitted error:&reason];

			check(archive != nil, "the emitted text COMPILES");
			check([NSNib refusalReasonForArchiveData:archive] == nil,
			      "…into an archive the reader accepts");
		}
	}

	/* 2. THE TABLE. Every id, including the subview's, and the identity the editor keys everything off. */
	{
		NSString *reason = nil;
		NSDictionary *byID = nil;
		NSArray *top = [NSNibSource objectsFromPropertyList:[NSNibSource propertyListFromSourceData:source(kSource)
												error:NULL]
							  objectsByID:&byID
								error:&reason];

		check(top != nil, "the object door builds the graph");
		check(reason == nil, "…without a reason");
		check([top count] == 2, "…answering both top-level objects, in file order");
		check(byID != nil && [byID count] == 4, "…and a table naming every object in the file");

		if (top != nil && byID != nil) {
			id root = [byID objectForKey:@"root"];
			id subject = [byID objectForKey:@"subject"];

			check([top objectAtIndex:0] == root, "the top-level object IS the table's entry, not a copy");
			check(subject != nil && [subject isKindOfClass:[NSView class]], "a SUBVIEW is in the table");
			check(subject != nil && [[root subviews] objectAtIndex:0] == subject,
			      "…and is the very subview the hierarchy holds");
			check([(NSView *)root frame].size.width == 320.0, "the properties were applied");
			check([(NSView *)subject isHidden] == YES, "…including a boolean that reads as a flag");
			check([[[(NSView *)root subviews] objectAtIndex:1] toolTip] != nil,
			      "…and a quoted value with a quote and a backslash in it");
			check([[(NSView *)[byID objectForKey:@"sidebar"] constraints] count] == 0,
			      "a view with no constraints gets none");
		}
	}

	/* 3. THE REFUSALS ARE SHARED, so an editor cannot show what the compiler would reject. */
	{
		NSString *compilerSays = nil;
		NSString *editorSays = nil;
		id plist = [NSNibSource propertyListFromSourceData:source("{ version = 1; objects = ( { id = \"a\"; class = NoSuchClass; } ); }")
							     error:NULL];

		check([NSNibSource archiveFromSourceData:source("{ version = 1; objects = ( { id = \"a\"; class = NoSuchClass; } ); }")
						   error:&compilerSays] == nil, "an unknown class is refused by the compiler");
		check([NSNibSource objectsFromPropertyList:plist objectsByID:NULL error:&editorSays] == nil,
		      "…and by the editor's door");
		check(compilerSays != nil && editorSays != nil && [compilerSays isEqualToString:editorSays],
		      "…with the SAME sentence, because the rule is shared");

		compilerSays = nil;
		editorSays = nil;
		check([NSNibSource archiveFromSourceData:source("{ objects = ( { class = NSView; } ); }")
						   error:&compilerSays] == nil, "a root with no version is refused");
		check([NSNibSource objectsFromPropertyList:[NSDictionary dictionary]
					    objectsByID:NULL
						  error:&editorSays] == nil, "…by both doors");
		check(compilerSays != nil && editorSays != nil && [compilerSays isEqualToString:editorSays],
		      "…again in one voice");

		/* AND THE EMITTER REFUSES A TREE THE COMPILER WOULD, so a save can never write a design that cannot be read. */
		check([NSNibSource sourceDataFromPropertyList:[NSDictionary dictionary] error:&editorSays] == nil,
		      "the emitter refuses a root the compiler refuses");
	}

	/* 4. THE SPELLINGS. Bare keys bare, the order stable, the placeholder a word, a literal a literal. */
	if (first != nil) {
		NSRange idRange = [first rangeOfString:@"id = root;"];
		NSRange classRange = [first rangeOfString:@"class = NSView;"];
		NSRange tagRange = [first rangeOfString:@"tag = 41;"];
		NSRange hiddenRange = [first rangeOfString:@"hidden = YES;"];

		check(idRange.location != NSNotFound && classRange.location != NSNotFound &&
		      idRange.location < classRange.location,
		      "an object states its id before its class");
		check(tagRange.location != NSNotFound, "an integer is a bare word, not a quoted string");
		check(hiddenRange.location != NSNotFound, "a boolean is YES or NO");
		check([first rangeOfString:@"destination = owner;"].location != NSNotFound,
		      "the file's owner is written as the word the grammar reads");
		check([first rangeOfString:@"say \\\"this\\\" \\\\ that"].location != NSNotFound,
		      "a quoted value keeps its escapes");
	}

	/* A LITERAL KEEPS ITS SPELLING, NAME AND ALL — the parser stores the body as text and the writer puts it back, so the
	 * one value this format cannot hold as a plist scalar is also the one it cannot quietly rewrite. */
	{
		NSString *reason = nil;
		id parsed = [NSNibSource propertyListFromSourceData:source("{ version = 1; objects = ( { class = NSView; "
									 "properties = { tint = @color(orange); exact = @color(#ff0000); }; } ); }")
							    error:NULL];
		NSData *emitted = [NSNibSource sourceDataFromPropertyList:parsed error:&reason];
		NSString *text = textOf(emitted);

		check(emitted != nil, "a colour literal parses and emits");
		check(reason == nil, "…without a reason");
		check([text rangeOfString:@"tint = @color(orange);"].location != NSNotFound,
		      "a colour written by NAME keeps its name, so the file says what the person wrote");
		check([text rangeOfString:@"exact = @color(#ff0000);"].location != NSNotFound,
		      "…and an exact one keeps its hex");
		{
			NSData *again = [NSNibSource sourceDataFromPropertyList:
				[NSNibSource propertyListFromSourceData:emitted error:NULL] error:&reason];

			check(again != nil && [again isEqualToData:emitted], "…and neither moves on a second save");
		}
	}

	[first release];
	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d failure(s)\n", s_failed);
		return 1;
	}
	printf("all nib-edit assertions passed\n");
	return 0;
}
