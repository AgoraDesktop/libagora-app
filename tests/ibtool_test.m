/*
 * ibtool_test — the format's command line, driven the way a shell would drive it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * The tool is a real executable and the only honest way to test it is to RUN it: this program builds a nib, writes it,
 * spawns `ibtool` for each verb and checks the exit status and the output. The fixture is built here rather than checked
 * in so the two cannot drift — there is no committed binary in this repository, and a format's test fixture should not be
 * the exception.
 *
 * WHAT EACH VERB HAS TO PROVE:
 *
 *   dump       names the version, both top-level objects, the connections in file order and the classes it decoded
 *   validate   says ok for a good file, and REFUSES a file naming a class outside the allow-list with a non-zero status
 *   roundtrip  is IDENTICAL for a tree of views and control cells, which is the format's closure
 */
#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>

#include <string.h>

#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("%s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* RUNS THE TOOL AND HANDS BACK ITS COMBINED OUTPUT, so a caller can assert on what a person would read.
 *
 * **THE OUTPUT GOES THROUGH A FILE RATHER THAN A PIPE, AND THAT IS A DELIBERATE RETREAT.** Driving a pipe from `NSTask`
 * here deadlocked twice for two different reasons — the parent's write end kept the pipe open so the read never saw EOF,
 * and the read has to happen before the wait or a chatty child blocks in `write`. A shell redirection has neither
 * problem, is one line, and is how a person would run the tool anyway; the test is about the tool's OUTPUT, not about
 * `NSPipe`. */
static NSString *run_ibtool(NSString *tool, NSArray *arguments, int *statusOut)
{
	NSString *outPath = @"/tmp/agora-ibtool-output.txt";
	NSMutableString *command = [NSMutableString string];
	NSTask *task = [[NSTask alloc] init];
	NSUInteger i;
	int status = -1;
	NSString *text = nil;

	[command appendFormat:@"'%@'", tool];
	for (i = 0; i < [arguments count]; i++) {
		[command appendFormat:@" '%@'", [arguments objectAtIndex:i]];
	}
	[command appendFormat:@" > '%@' 2>&1", outPath];

	[task setLaunchPath:@"/bin/sh"];
	[task setArguments:[NSArray arrayWithObjects:@"-c", command, nil]];
	@try {
		[task launch];
		[task waitUntilExit];
		status = [task terminationStatus];
	} @catch (NSException *exception) {
		printf("  (could not run %s: %s)\n", [[tool description] UTF8String],
		       [[exception reason] UTF8String]);
	}
	[task release];
	if (statusOut != NULL) {
		*statusOut = status;
	}
	text = [NSString stringWithContentsOfFile:outPath];
	return (text != nil) ? text : @"";
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *tool;
	NSString *goodPath = @"/tmp/agora-ibtool-good.nib";
	NSString *badPath = @"/tmp/agora-ibtool-bad.nib";
	NSView *root;
	NSButton *button;
	NSData *archive;
	NSString *output;
	int status = 0;

	if (argc < 2) {
		fprintf(stderr, "usage: ibtool_test <path-to-ibtool>\n");
		[pool release];
		return 2;
	}
	tool = [NSString stringWithUTF8String:argv[1]];

	/* ---- THE FIXTURE: a view with a tagged child and a real button, plus one connection. ---------- */
	root = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 240.0)];
	[root setTag:41];
	{
		NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(8.0, 9.0, 100.0, 20.0)];

		[child setTag:42];
		[root addSubview:child];
		[child release];
	}
	button = [[NSButton alloc] initWithFrame:NSMakeRect(10.0, 40.0, 90.0, 24.0)];
	[button setTitle:@"Go"];
	[root addSubview:button];
	[button release];

	archive = [NSNib archivedDataWithTopLevelObjects:[NSArray arrayWithObject:root]
					     connections:[NSArray arrayWithObject:
		[NSNib actionConnectionFrom:button to:NSNibFileOwner action:@"go:"]]];
	check(archive != nil, "the fixture archives");
	check([archive writeToFile:goodPath atomically:YES], "the fixture was written");

	/* A FILE THE READER MAY NOT BUILD, written the same way the round-trip test writes one. */
	{
		NSData *hostile = [NSNib archivedDataWithTopLevelObjects:
			[NSArray arrayWithObject:[NSIndexPath indexPathWithIndex:3]] connections:nil];

		check(hostile != nil && [hostile writeToFile:badPath atomically:YES],
		      "a file naming a class outside the allow-list was written");
	}

	/* ---- dump ------------------------------------------------------------------------------------ */
	output = run_ibtool(tool, [NSArray arrayWithObjects:@"dump", goodPath, nil], &status);
	check(status == 0, "dump exits 0 for a good file");
	check([output rangeOfString:@"version: 1"].location != NSNotFound, "dump names the format version");
	check([output rangeOfString:@"top-level objects: 1"].location != NSNotFound,
	      "dump counts the top-level objects");
	check([output rangeOfString:@"NSView frame=0,0,320,240"].location != NSNotFound,
	      "dump describes the root's frame");
	check([output rangeOfString:@"tag=41"].location != NSNotFound, "dump reports a tag");
	check([output rangeOfString:@"subviews=2"].location != NSNotFound, "dump counts the subviews");
	check([output rangeOfString:@"cell=NSButtonCell"].location != NSNotFound,
	      "dump names the button's cell class");
	check([output rangeOfString:@"action NSButton -> NSNibFileOwner @go:"].location != NSNotFound,
	      "dump reports the action connection and its selector");

	/* ---- validate -------------------------------------------------------------------------------- */
	output = run_ibtool(tool, [NSArray arrayWithObjects:@"validate", goodPath, nil], &status);
	check(status == 0, "validate accepts a good file");
	check([output rangeOfString:@"ok"].location != NSNotFound, "validate says ok");

	output = run_ibtool(tool, [NSArray arrayWithObjects:@"validate", badPath, nil], &status);
	check(status == 1, "validate REFUSES a file naming a class outside the allow-list");
	check([output rangeOfString:@"NSIndexPath"].location != NSNotFound,
	      "the refusal names the class it refused");

	/* ---- roundtrip ------------------------------------------------------------------------------- */
	output = run_ibtool(tool, [NSArray arrayWithObjects:@"roundtrip", goodPath, nil], &status);
	check(status == 0, "roundtrip exits 0");
	check([output rangeOfString:@"roundtrip: identical"].location != NSNotFound,
	      "the archive survives decode and re-encode unchanged");

	/* ---- compile --------------------------------------------------------------------------------- */
	/* **THE SOURCE HALF OF THE TOOL, DRIVEN THE SAME WAY.** A text source goes in, a nib comes out, and the file it wrote
	 * is then VALIDATED by the same tool — the compiler and the reader agreeing about what a nib is. */
	{
		const char *sourceText =
			"{ version = 1; objects = ( { class = NSView;"
			" properties = { frame = \"0 0 200 100\"; tag = 5; }; } ); }\n";
		NSString *sourcePath = @"/tmp/agora-ibtool-source.nibsource";
		NSString *outPath = @"/tmp/agora-ibtool-compiled.nib";

		check([[NSData dataWithBytes:sourceText length:strlen(sourceText)] writeToFile:sourcePath
										      atomically:YES],
		      "a text source was written");
		output = run_ibtool(tool, [NSArray arrayWithObjects:@"compile", sourcePath, outPath, nil],
				    &status);
		check(status == 0, "compile exits 0 for a good source");
		check([output rangeOfString:@"compiled"].location != NSNotFound, "compile says what it did");

		output = run_ibtool(tool, [NSArray arrayWithObjects:@"validate", outPath, nil], &status);
		check(status == 0, "what compile wrote is a nib the reader accepts");

		output = run_ibtool(tool, [NSArray arrayWithObjects:@"dump", outPath, nil], &status);
		check([output rangeOfString:@"tag=5"].location != NSNotFound,
		      "the compiled file carries the property from the SOURCE");

		/* AND A SOURCE THAT MUST NOT COMPILE: the refusal names the key. */
		{
			const char *bad = "{ version = 1; objects = ( { class = NSView; freckles = 1; } ); }\n";

			[[NSData dataWithBytes:bad length:strlen(bad)] writeToFile:sourcePath atomically:YES];
			output = run_ibtool(tool, [NSArray arrayWithObjects:@"compile", sourcePath, outPath, nil],
					    &status);
			check(status == 1, "compile exits 1 for a source it refuses");
			check([output rangeOfString:@"freckles"].location != NSNotFound,
			      "and the refusal names the key");
		}
	}

	/* AND A VERB THAT DOES NOT EXIST IS A USAGE ERROR RATHER THAN A SILENT SUCCESS. */
	output = run_ibtool(tool, [NSArray arrayWithObjects:@"frobnicate", goodPath, nil], &status);
	check(status == 2, "an unknown verb exits 2");

	[root release];
	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d failure(s)\n", s_failed);
		return 1;
	}
	printf("all ibtool assertions passed\n");
	return 0;
}
