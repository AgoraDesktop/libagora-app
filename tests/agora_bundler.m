/*
 * agora-bundler — the Project Builder role's first executable piece: an application bundle, for MORE THAN ONE MACHINE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE PRODUCT OF A PROJECT IS A `.app`, AND ON AGORA THAT MEANS SEVERAL BINARIES, NOT ONE FAT ONE.** Apple's universal
 * binary is a Mach-O container with several architectures inside; the ELF loaders on Linux and the BSDs have no such
 * container and would not `exec` one. So a universal Agora bundle is the honest thing instead: one complete binary per
 * platform, side by side, and a manifest that NAMES them — `AGBundleExecutables`, documented in `NSBundle.h` and resolved
 * there against the machine the process is running on.
 *
 * This tool is the writer half of that pair, and it is deliberately the smallest useful one: it lays out a bundle
 * (`Contents/Info.plist`, `Contents/MacOS/`, `Contents/Resources/`), copies each variant's binary in, records the table,
 * and copies resources. What it does NOT do is decide what to build — that is the manifest's job and the Project
 * Builder's, and pretending to have it here would be inventing a project file before the manifest is designed.
 *
 *   agora-bundler --identifier org.agora.App --name App [--version 1.0] [--executable App]
 *                 --variant <platform>=<path> ...        (repeatable; platform is `uname -sm` lowercased)
 *                 [--resource <source>:<Destination>] ... (repeatable)
 *                 <out.app>
 *
 * IT LIVES IN `tests/` FOR NOW, the way `ibtool` does: the eventual home of a packager is its own repository (the
 * one-component-one-repository rule), and moving it later should be a move rather than a rewrite.
 */
#import <Foundation/Foundation.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void usage(void)
{
	printf("usage: agora-bundler --identifier ID --name NAME [--version V] [--executable NAME]\n"
	       "                     --variant <platform>=<path> ...\n"
	       "                     [--resource <source>:<Destination>] ...\n"
	       "                     <out.app>\n"
	       "\n"
	       "  --variant  a complete binary for one machine; the platform is `uname -sm` lowercased and\n"
	       "             hyphenated, which is the spelling NSBundle resolves by (e.g. linux-x86_64).\n"
	       "  --resource copies a file into Contents/Resources under the name after the colon.\n");
}

/* A DIRECTORY THE WAY `mkdir -p` MEANS IT. */
static int make_directory(const char *path)
{
	char buffer[4096];
	size_t length;
	size_t i;

	length = strlen(path);
	if (length == 0 || length + 1 > sizeof(buffer)) {
		return -1;
	}
	memcpy(buffer, path, length + 1);
	for (i = 1; i <= length; i++) {
		if (buffer[i] == '/' || buffer[i] == '\0') {
			char saved = buffer[i];

			buffer[i] = '\0';
			if (mkdir(buffer, 0755) != 0 && errno != EEXIST) {
				return -1;
			}
			buffer[i] = saved;
		}
	}
	return 0;
}

static int copy_file(const char *from, const char *to, mode_t mode)
{
	FILE *in = fopen(from, "rb");
	FILE *out;
	char buffer[65536];
	size_t got;

	if (in == NULL) {
		fprintf(stderr, "agora-bundler: cannot read %s: %s\n", from, strerror(errno));
		return -1;
	}
	out = fopen(to, "wb");
	if (out == NULL) {
		fprintf(stderr, "agora-bundler: cannot write %s: %s\n", to, strerror(errno));
		fclose(in);
		return -1;
	}
	while ((got = fread(buffer, 1, sizeof(buffer), in)) > 0) {
		if (fwrite(buffer, 1, got, out) != got) {
			fprintf(stderr, "agora-bundler: short write to %s\n", to);
			fclose(in);
			fclose(out);
			return -1;
		}
	}
	fclose(in);
	fclose(out);
	if (chmod(to, mode) != 0) {
		fprintf(stderr, "agora-bundler: cannot set the mode on %s: %s\n", to, strerror(errno));
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSMutableDictionary *manifest = [[NSMutableDictionary alloc] init];
	NSMutableDictionary *variants = [[NSMutableDictionary alloc] init];
	NSMutableArray *resources = [[NSMutableArray alloc] init];
	NSString *identifier = nil;
	NSString *name = nil;
	NSString *version = nil;
	NSString *executableName = nil;
	NSString *outPath = nil;
	NSUInteger i;

	for (i = 1; i < (NSUInteger)argc; i++) {
		const char *argument = argv[i];
		const char *value = (i + 1 < (NSUInteger)argc) ? argv[i + 1] : NULL;

		if (strcmp(argument, "help") == 0 || strcmp(argument, "--help") == 0) {
			usage();
			[pool release];
			return 0;
		}
		if (strcmp(argument, "--identifier") == 0 && value != NULL) {
			identifier = [[NSString alloc] initWithUTF8String:value];
			i++;
		} else if (strcmp(argument, "--name") == 0 && value != NULL) {
			name = [[NSString alloc] initWithUTF8String:value];
			i++;
		} else if (strcmp(argument, "--version") == 0 && value != NULL) {
			version = [[NSString alloc] initWithUTF8String:value];
			i++;
		} else if (strcmp(argument, "--executable") == 0 && value != NULL) {
			executableName = [[NSString alloc] initWithUTF8String:value];
			i++;
		} else if (strcmp(argument, "--variant") == 0 && value != NULL) {
			/* `<platform>=<path>`: split on the FIRST `=`, because a path may contain one. */
			const char *equals = strchr(value, '=');

			if (equals == NULL || equals == value || equals[1] == '\0') {
				fprintf(stderr, "agora-bundler: --variant wants <platform>=<path>, got %s\n", value);
				[pool release];
				return 2;
			}
			/* THE PLATFORM IS THE KEY AND THE PATH IS THE VALUE — in that order, which is the opposite of how the
			 * command line reads, and getting it backwards made the bundler try to open a file named after a machine. */
			[variants setObject:[[[NSString alloc] initWithUTF8String:equals + 1] autorelease]
				     forKey:[[[NSString alloc] initWithBytes:value
								      length:(NSUInteger)(equals - value)
								    encoding:NSUTF8StringEncoding] autorelease]];
			i++;
		} else if (strcmp(argument, "--resource") == 0 && value != NULL) {
			[resources addObject:[NSString stringWithUTF8String:value]];
			i++;
		} else if (argument[0] == '-') {
			fprintf(stderr, "agora-bundler: unknown option %s\n", argument);
			usage();
			[pool release];
			return 2;
		} else {
			outPath = [[NSString alloc] initWithUTF8String:argument];
		}
	}

	if (identifier == nil || name == nil || outPath == nil || [variants count] == 0) {
		fprintf(stderr, "agora-bundler: --identifier, --name, at least one --variant and an output path "
			"are required\n");
		[pool release];
		return 2;
	}
	if (executableName == nil) {
		executableName = name;
	}

	/* ---- THE LAYOUT ------------------------------------------------------------------------------ */
	{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSString *contents = [outPath stringByAppendingPathComponent:@"Contents"];
		NSString *macos = [contents stringByAppendingPathComponent:@"MacOS"];
		NSString *resourcesPath = [contents stringByAppendingPathComponent:@"Resources"];
		NSString *plistPath = [contents stringByAppendingPathComponent:@"Info.plist"];
		NSMutableDictionary *table = [[NSMutableDictionary alloc] init];
		NSEnumerator *keys;
		NSString *platform;
		NSData *plist;

		if (make_directory([macos fileSystemRepresentation]) != 0 ||
		    make_directory([resourcesPath fileSystemRepresentation]) != 0) {
			fprintf(stderr, "agora-bundler: cannot create %s: %s\n", [contents UTF8String], strerror(errno));
			[pool release];
			return 2;
		}
		(void)fm;

		/* **THE NAME OF A VARIANT'S FILE CARRIES ITS PLATFORM**, because `Contents/MacOS` is one directory and two
		 * binaries called `App` cannot both live in it. The manifest maps the platform to that name, which is the table
		 * `NSBundle -executablePath` reads. */
		keys = [variants keyEnumerator];
		while ((platform = [keys nextObject]) != nil) {
			NSString *source = [variants objectForKey:platform];
			NSString *file = [NSString stringWithFormat:@"%@-%@", executableName, platform];
			NSString *destination = [macos stringByAppendingPathComponent:file];

			[table setObject:file forKey:platform];
			if (copy_file([source fileSystemRepresentation], [destination fileSystemRepresentation],
				      0755) != 0) {
				[pool release];
				return 2;
			}
		}

		for (i = 0; i < [resources count]; i++) {
			NSString *spec = [resources objectAtIndex:i];
			NSRange colon = [spec rangeOfString:@":" options:NSBackwardsSearch];
			NSString *source = (colon.location == NSNotFound) ? spec : [spec substringToIndex:colon.location];
			NSString *leaf = (colon.location == NSNotFound) ? [spec lastPathComponent]
				: [spec substringFromIndex:colon.location + 1];
			NSString *destination = [resourcesPath stringByAppendingPathComponent:leaf];

			if (copy_file([source fileSystemRepresentation], [destination fileSystemRepresentation],
				      0644) != 0) {
				[pool release];
				return 2;
			}
		}

		/* ---- THE MANIFEST ---------------------------------------------------------------------- */
		[manifest setObject:identifier forKey:@"CFBundleIdentifier"];
		[manifest setObject:name forKey:@"CFBundleName"];
		[manifest setObject:executableName forKey:@"CFBundleExecutable"];
		[manifest setObject:@"APPL" forKey:@"CFBundlePackageType"];
		[manifest setObject:((version != nil) ? version : @"1.0") forKey:@"CFBundleShortVersionString"];
		[manifest setObject:table forKey:@"AGBundleExecutables"];
		[table release];

		plist = [NSPropertyListSerialization dataWithPropertyList:manifest
								 format:NSPropertyListXMLFormat_v1_0
								options:0
								  error:NULL];
		if (plist == nil || ![plist writeToFile:plistPath atomically:YES]) {
			fprintf(stderr, "agora-bundler: cannot write %s\n", [plistPath UTF8String]);
			[pool release];
			return 2;
		}
		printf("%s: %lu variant(s) written for %s\n", [outPath UTF8String],
		       (unsigned long)[variants count], [identifier UTF8String]);
	}
	{
		NSEnumerator *keys = [variants keyEnumerator];
		NSString *platform;

		while ((platform = [keys nextObject]) != nil) {
			printf("  %s -> %s-%s\n", [platform UTF8String], [executableName UTF8String],
			       [platform UTF8String]);
		}
	}

	[pool release];
	return 0;
}
