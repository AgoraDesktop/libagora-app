/*
 * umbrella — the AppKit's umbrella header, measured: it compiles, and it names every header this component installs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE HEADER'S JOB IS TWO THINGS AND THIS PROBE CHECKS BOTH.** First: `#import <AppKit/AppKit.h>` COMPILES — every
 * header it names is self-sufficient and the set does not fight itself, which is a claim no single header can make.
 * Second: the set is COMPLETE. `CMakeLists.txt` installs `*.h` with a glob, so a new class joins the installed
 * surface the moment its header exists; an umbrella that silently stopped naming them would be a public interface
 * that is a directory listing again. The census below fails with the header nobody classified.
 *
 * **THE INTERNAL ONES ARE NAMED HERE RATHER THAN IN THE UMBRELLA, AND THAT IS THE CLASSIFICATION.** A header that
 * carries a class's workings (`*_internal.h`) or this tier's own machinery (`AG*`, `SystemImage*`) is installed for
 * a sibling component's build, not for a consumer's `#import`.
 */
#import <AppKit/AppKit.h>

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* THE HEADERS THAT ARE INSTALLED AND DELIBERATELY NOT IN THE UMBRELLA. Adding a class means adding one line to
 * `AppKit.h` or one line here; there is no third state. */
static const char *s_internal[] = {
	/* A class's own workings: the archive's recorded keys, the layout solver's rows, the toolbar's item database. */
	"NSArrayController_internal", "NSAttributedStringRTF_internal", "NSGraphics_internal", "NSImage_internal",
	"NSLayoutAnchor_internal", "NSObjectController_internal", "NSSavePanel_internal", "NSScrollView_internal",
	"NSTextBlock_internal", "NSTextList_internal", "NSTextTable_internal", "NSToolbar_internal",
	"NSWindow_internal",
	/* This tier's own machinery, below the Cocoa names. */
	"AGAppleNib", "AGCandidateListView", "AGCandidateWindow", "AGChromeTheme", "AGComboListCell", "AGComboListView",
	"AGInputMethod", "AGStatusBarItemView", "AGSwitch", "AGSwitchCell", "AGSystemImages", "AGVariantsInputMethod",
	"AGXPM",
	/* The icon catalogue's naming tables, which `AGSystemImages` reads. */
	"SystemImageMasks", "SystemImageNames",
	NULL,
};

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

static int is_internal(const char *name)
{
	int i;

	for (i = 0; s_internal[i] != NULL; i++) {
		if (strcmp(s_internal[i], name) == 0) {
			return 1;
		}
	}
	return 0;
}

/* THE UMBRELLA'S OWN LIST, read as text: the includes are the specification, and a test that asked a parsed
 * structure would be testing a second parser rather than the file a consumer compiles. */
static NSArray *umbrella_names(void)
{
	NSString *text = [NSString stringWithContentsOfFile:@APPKIT_UMBRELLA
						   encoding:NSUTF8StringEncoding
						      error:NULL];
	NSMutableArray *names = [NSMutableArray array];
	NSArray *lines;
	NSUInteger i;

	if (text == nil) {
		return names;
	}
	lines = [text componentsSeparatedByString:@"\n"];
	for (i = 0; i < [lines count]; i++) {
		NSString *line = [lines[i] stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceCharacterSet]];

		if (![line hasPrefix:@"#import <AppKit/"] || ![line hasSuffix:@".h>"]) {
			continue;
		}
		{
			NSString *rest = [line substringFromIndex:[@"#import <AppKit/" length]];

			[names addObject:[rest substringToIndex:[rest length] - [@".h>" length]]];
		}
	}
	return names;
}

static NSArray *installed_names(void)
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@APPKIT_SOURCE_DIR error:NULL];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSString *entry = entries[i];

		/* THE UMBRELLA IS NOT ONE OF THE HEADERS IT HAS TO NAME. */
		if ([entry hasSuffix:@".h"] && ![entry isEqualToString:@"AppKit.h"]) {
			[names addObject:[entry substringToIndex:[entry length] - 2]];
		}
	}
	return names;
}

int main(void)
{
	@autoreleasepool {
		NSArray *umbrella, *installed;

		umbrella = umbrella_names();
		installed = installed_names();
		NSMutableArray *unclassified = [NSMutableArray array];
		NSUInteger i;

		printf("umbrella names %lu header(s); the source directory holds %lu\n",
			(unsigned long)[umbrella count], (unsigned long)[installed count]);

		check([umbrella count] > 100, "the umbrella names the surface rather than a sample of it");

		/* 1. EVERY INSTALLED HEADER IS CLASSIFIED. */
		for (i = 0; i < [installed count]; i++) {
			const char *name = [installed[i] UTF8String];

			if (![umbrella containsObject:installed[i]] && !is_internal(name)) {
				[unclassified addObject:installed[i]];
			}
		}
		if ([unclassified count] > 0) {
			printf("       unclassified: %s\n", [[unclassified componentsJoinedByString:@", "] UTF8String]);
		}
		check([unclassified count] == 0, "every installed header is in the umbrella or named as internal");

		/* 2. EVERY NAME IN THE UMBRELLA EXISTS — so a rename cannot leave a dangling include behind. */
		{
			NSMutableArray *dangling = [NSMutableArray array];

			for (i = 0; i < [umbrella count]; i++) {
				if (![installed containsObject:umbrella[i]]) {
					[dangling addObject:umbrella[i]];
				}
			}
			if ([dangling count] > 0) {
				printf("       dangling: %s\n", [[dangling componentsJoinedByString:@", "] UTF8String]);
			}
			check([dangling count] == 0, "every header the umbrella names exists");
		}

		/* 3. NO HEADER IS BOTH, which would mean the classification disagreed with itself. */
		{
			int both = 0;

			for (i = 0; i < [umbrella count]; i++) {
				if (is_internal([umbrella[i] UTF8String])) {
					printf("       both: %s\n", [umbrella[i] UTF8String]);
					both++;
				}
			}
			check(both == 0, "no header is both public and internal");
		}

		/* 4. THE UMBRELLA ACTUALLY PULLS THE CLASSES IN. The include above compiled; this says it was not an empty
		 * file: a class from each band of the AppKit answers its own name. */
		check(NSClassFromString(@"NSWindow") != Nil, "the window class is reachable through the umbrella");
		check(NSClassFromString(@"NSView") != Nil, "the view class is reachable");
		check(NSClassFromString(@"NSTextView") != Nil, "the text system is reachable");
		check(NSClassFromString(@"NSToolbar") != Nil, "the toolbar is reachable");
		check(NSClassFromString(@"NSDocument") != Nil, "the document model is reachable");
		check(NSClassFromString(@"NSOutlineView") != Nil, "the table and outline are reachable");
		check(NSClassFromString(@"NSAlert") != Nil, "the panels are reachable");
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
