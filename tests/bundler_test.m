/*
 * bundler_test — a bundle for more than one machine, written and then READ BACK by NSBundle.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * The writer and the reader are two halves of one decision, so the test would be worth little if it checked only the
 * files: what matters is that `NSBundle -executablePath` picks the binary for THIS machine out of a bundle that carries
 * several, and falls back to Apple's key when the table does not name this one. So the tool is RUN (as a person would
 * run it), and then the result is opened.
 *
 * WHAT IS ASSERTED:
 *
 *   1. `+[NSBundle currentPlatformName]` is `sysname-machine` lowercased, which the test recomputes from `uname` itself
 *      rather than trusting the class under test.
 *   2. A bundle with TWO variants resolves to the one for this machine, and the file it names EXISTS and is executable.
 *   3. A bundle whose table names only OTHER machines falls back to `CFBundleExecutable`.
 *   4. A bundle with no table at all — every bundle that exists today — behaves exactly as before.
 *   5. Resources land in `Contents/Resources` and `-pathForResource:ofType:` finds them.
 *   6. The tool refuses what it cannot write: no variants, a malformed `--variant`, an unreadable binary.
 */
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("%s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* THE HOST'S PLATFORM, COMPUTED HERE SO THE TEST DOES NOT ASK THE THING IT IS TESTING. */
static NSString *host_platform(void)
{
	struct utsname info;
	char system[65];
	char machine[65];
	size_t i;

	if (uname(&info) != 0) {
		return @"unknown";
	}
	for (i = 0; i < 64 && info.sysname[i] != '\0'; i++) {
		system[i] = (char)((info.sysname[i] >= 'A' && info.sysname[i] <= 'Z')
			? info.sysname[i] - 'A' + 'a' : info.sysname[i]);
	}
	system[i] = '\0';
	for (i = 0; i < 64 && info.machine[i] != '\0'; i++) {
		machine[i] = (char)((info.machine[i] >= 'A' && info.machine[i] <= 'Z')
			? info.machine[i] - 'A' + 'a' : info.machine[i]);
	}
	machine[i] = '\0';
	return [NSString stringWithFormat:@"%s-%s", system, machine];
}

/* RUNS THE TOOL THROUGH A SHELL, with its output in a file — the same harness `ibtool_test` uses, and for the same
 * reason: a pipe here deadlocks on a write end the parent still holds. */
static NSString *run(NSString *tool, NSString *arguments, int *statusOut)
{
	NSString *outPath = @"/tmp/agora-bundler-output.txt";
	NSString *command = [NSString stringWithFormat:@"'%@' %@ > '%@' 2>&1", tool, arguments, outPath];
	FILE *pipe = popen([command UTF8String], "r");
	int status = -1;

	if (pipe != NULL) {
		while (fgetc(pipe) != EOF) {
			/* drain */
		}
		status = pclose(pipe);
		if (status != -1) {
			status = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
		}
	}
	if (statusOut != NULL) {
		*statusOut = status;
	}
	{
		NSString *text = [NSString stringWithContentsOfFile:outPath];

		return (text != nil) ? text : @"";
	}
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *tool;
	NSString *host = host_platform();
	NSString *fake = @"linux-aarch64";
	NSString *binary = @"/bin/true";
	NSString *resourcePath = @"/tmp/agora-bundler-resource.txt";
	NSString *multi = @"/tmp/agora-bundler/Universal.app";
	NSString *foreign = @"/tmp/agora-bundler/Foreign.app";
	NSString *plain = @"/tmp/agora-bundler/Plain.app";
	NSString *output;
	int status = 0;

	if (argc < 2) {
		fprintf(stderr, "usage: bundler_test <path-to-agora-bundler>\n");
		[pool release];
		return 2;
	}
	tool = [NSString stringWithUTF8String:argv[1]];

	/* ---- 1. THE PLATFORM NAME, MEASURED BOTH WAYS --------------------------------------------- */
	check([[NSBundle currentPlatformName] isEqualToString:host],
	      "+[NSBundle currentPlatformName] is sysname-machine, computed the same way here");
	printf("      (%s)\n", [host UTF8String]);

	[[NSFileManager defaultManager] createDirectoryAtPath:@"/tmp/agora-bundler"
						 withIntermediateDirectories:YES
								  attributes:nil
								       error:NULL];
	[@"" writeToFile:resourcePath atomically:YES];
	{
		NSData *sample = [NSData dataWithContentsOfFile:binary];

		check(sample != nil && [sample length] > 0, "there is a real binary to stand in for a variant");
	}

	/* ---- 2. TWO VARIANTS: THIS MACHINE AND ANOTHER -------------------------------------------- */
	output = run(tool, [NSString stringWithFormat:
		@"--identifier org.agora.Universal --name Universal --executable Universal "
		@"--variant %@=%@ --variant %@=%@ --resource %@:note.txt %@",
		host, binary, fake, binary, resourcePath, multi], &status);
	check(status == 0, "the bundler wrote a bundle with two variants");
	if (status != 0) {
		printf("      (%s)\n", [output UTF8String]);
	}
	{
		NSBundle *bundle = [NSBundle bundleWithPath:multi];
		NSString *executable;

		check(bundle != nil, "NSBundle opened it");
		executable = [bundle executablePath];
		check(executable != nil, "the bundle answers an executable path");
		check(executable != nil &&
		      [executable hasSuffix:[NSString stringWithFormat:@"Universal-%@", host]],
		      "and it is the variant for THIS machine");
		check(executable != nil && access([executable fileSystemRepresentation], X_OK) == 0,
		      "and that file exists and is executable");
		check([[bundle bundleIdentifier] isEqualToString:@"org.agora.Universal"],
		      "the identifier came through the manifest");
		check([bundle pathForResource:@"note" ofType:@"txt"] != nil,
		      "a resource landed in Contents/Resources");
		check([[bundle objectForInfoDictionaryKey:@"AGBundleExecutables"] count] == 2,
		      "the manifest records BOTH variants");
	}

	/* ---- 3. A BUNDLE FOR OTHER MACHINES ONLY: APPLE'S KEY IS THE ANSWER ------------------------ */
	output = run(tool, [NSString stringWithFormat:
		@"--identifier org.agora.Foreign --name Foreign --executable Foreign "
		@"--variant %@=%@ %@", fake, binary, foreign], &status);
	check(status == 0, "the bundler wrote a single-variant bundle for another machine");
	{
		NSBundle *bundle = [NSBundle bundleWithPath:foreign];
		NSString *executable = [bundle executablePath];

		check(executable != nil && [executable hasSuffix:@"Foreign"],
		      "a bundle that does not name this machine falls back to CFBundleExecutable");
	}

	/* ---- 4. NO TABLE AT ALL: TODAY'S BEHAVIOUR ----------------------------------------------- */
	{
		NSString *contents = [plain stringByAppendingPathComponent:@"Contents"];

		[[NSFileManager defaultManager] createDirectoryAtPath:[contents stringByAppendingPathComponent:@"MacOS"]
					 withIntermediateDirectories:YES
							  attributes:nil
							       error:NULL];
		/* **XML, BECAUSE THAT IS WHAT THIS TREE'S PLIST WRITER WRITES AND ITS READER READS** — the OpenStep text form is a
		 * declared format with no implementation, so a hand-written `{ … }` here would produce a bundle NSBundle could not
		 * read and a test that failed for the wrong reason. */
		{
			NSDictionary *manifest = [NSDictionary dictionaryWithObjectsAndKeys:
				@"org.agora.Plain", @"CFBundleIdentifier",
				@"Plain", @"CFBundleName",
				@"Plain", @"CFBundleExecutable",
				@"APPL", @"CFBundlePackageType", nil];
			NSData *plist = [NSPropertyListSerialization dataWithPropertyList:manifest
										  format:NSPropertyListXMLFormat_v1_0
										 options:0
										   error:NULL];

			[plist writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
		}
	}
	{
		NSBundle *bundle = [NSBundle bundleWithPath:plain];
		NSString *executable = [bundle executablePath];

		check(executable != nil && [executable hasSuffix:@"Plain"],
		      "a bundle with no variant table is unchanged (CFBundleExecutable)");
	}

	/* ---- 5. THE REFUSALS ---------------------------------------------------------------------- */
	output = run(tool, @"--identifier org.agora.None --name None /tmp/agora-bundler/None.app", &status);
	check(status == 2, "no variants is a usage error");

	output = run(tool, [NSString stringWithFormat:
		@"--identifier org.agora.Bad --name Bad --variant nonsense %@", @"/tmp/agora-bundler/Bad.app"],
		&status);
	check(status == 2, "a malformed --variant is a usage error");

	output = run(tool, [NSString stringWithFormat:
		@"--identifier org.agora.Missing --name Missing --variant %@=%@ %@",
		host, @"/tmp/agora-bundler/does-not-exist", @"/tmp/agora-bundler/Missing.app"], &status);
	check(status == 2, "an unreadable variant binary is refused");

	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d failure(s)\n", s_failed);
		return 1;
	}
	printf("all bundler assertions passed\n");
	return 0;
}
