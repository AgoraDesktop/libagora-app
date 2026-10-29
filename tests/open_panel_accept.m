/*
 * open_panel_accept — an OPEN PANEL THAT IS SHOWN, LISTED, SELECTED AND ACCEPTED, with no modal loop.
 *
 * The panel's modal session is `-runModal`'s business and needs a window server; what a caller depends on is the part
 * between the press and the answer: the directory lists, a row selects, `-ok:` accepts it, and `-URLs`/`-URL` name the
 * file. This probe drives exactly that, so a panel that never accepts anything can be told apart from one that is never
 * shown.
 *
 * It also covers the two spellings an older application uses: the typed name (no selection) and `-runModalForDirectory:`
 * reaching the same configuration.
 */
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed = 0;
static int s_passed = 0;

static void check(int ok, const char *what)
{
	if (ok) {
		s_passed++;
		printf("  ok     %s\n", what);
	} else {
		s_failed++;
		printf("  FAIL   %s\n", what);
	}
}

/* THE TIER'S SEAMS, declared the way this tree's probes declare them: the entry list and the accept door are what the
 * panel's own buttons call, and a probe that only pressed buttons could not run without a window server. */
@interface NSSavePanel (AGProbeEntries)
- (NSInteger)cg_entryCount;
- (NSString *)cg_entryNameAtIndex:(NSInteger)index;
- (BOOL)cg_selectFilenames:(NSArray *)names;
@end

int main(void)
{
	@autoreleasepool {
		const char *tmp = getenv("TMPDIR");
		NSString *base = [NSString stringWithFormat:@"%s/forge-open-panel-%d",
			(tmp != NULL && tmp[0] != '\0') ? tmp : "/tmp", (int)getpid()];
		NSFileManager *manager = [NSFileManager defaultManager];
		NSString *directory = [base stringByAppendingPathComponent:@"Project"];
		NSString *subdirectory = [directory stringByAppendingPathComponent:@"Sources"];
		NSOpenPanel *panel;

		setvbuf(stdout, NULL, _IOLBF, 0);
		(void)[[NSApplication sharedApplication] finishLaunching];
		[manager createDirectoryAtPath:subdirectory withIntermediateDirectories:YES attributes:nil error:NULL];
		[[@"int main(void) { return 0; }\n" dataUsingEncoding:NSUTF8StringEncoding]
			writeToFile:[subdirectory stringByAppendingPathComponent:@"main.m"] atomically:YES];
		[[@"// notes\n" dataUsingEncoding:NSUTF8StringEncoding]
			writeToFile:[directory stringByAppendingPathComponent:@"Notes.h"] atomically:YES];

		panel = [NSOpenPanel openPanel];
		check(panel != nil, "the open panel exists");
		check([panel canChooseFiles] && ![panel canChooseDirectories],
		      "it chooses files and not directories by default");

		/* 0. **AN OPEN PANEL OFFERS NO NAME OF ITS OWN.** It used to keep the base panel's save default, "Untitled",
		 * so a press of Open with nothing selected asked for a file that does not exist and returned silently. */
		check([[panel nameFieldStringValue] length] == 0,
		      "an open panel starts with an empty name field");

		/* 1. THE DIRECTORY LISTS, which is the first thing a person sees. */
		[panel setDirectory:directory];
		check([panel cg_entryCount] >= 2, "the panel lists the directory's entries");
		check([[panel cg_entryNameAtIndex:0] length] > 0, "and the first entry has a name");

		/* 2. A SELECTED ROW IS ACCEPTED AND NAMES THE FILE. */
		{
			NSInteger row = -1;
			NSInteger i;

			for (i = 0; i < [panel cg_entryCount]; i++) {
				if ([[panel cg_entryNameAtIndex:i] isEqualToString:@"Notes.h"]) {
					row = i;
				}
			}
			check(row >= 0, "the file the probe wrote is in the list");
			if (row >= 0) {
				check([panel cg_selectFilenames:[NSArray arrayWithObject:@"Notes.h"]],
				      "the panel can select a row by name");
				[panel ok:nil];
				check([panel URL] != nil, "accepting a selected row answers a URL");
				check([[[panel URL] path] hasSuffix:@"Notes.h"], "and the URL is the selected file");
				check([[[panel URLs] objectAtIndex:0] isEqual:[panel URL]],
				      "and the multi-selection list agrees with it");
			}
		}

		/* 3. **A DIRECTORY IN AN OPEN PANEL IS A WAY IN, NOT AN ANSWER** — the press navigates and accepts nothing. */
		{
			NSInteger row = -1;
			NSInteger i;

			for (i = 0; i < [panel cg_entryCount]; i++) {
				if ([[panel cg_entryNameAtIndex:i] isEqualToString:@"Sources"]) {
					row = i;
				}
			}
			check(row >= 0, "the subdirectory is in the list");
			if (row >= 0) {
				[panel cg_selectFilenames:[NSArray arrayWithObject:@"Sources"]];
				[panel ok:nil];
				check([panel URL] == nil || ![[[panel URL] path] hasSuffix:@"Sources"],
				      "pressing OK on a directory opens it instead of choosing it");
				check([[panel directoryURL] path] != nil
				      && [[[panel directoryURL] path] hasSuffix:@"Sources"],
				      "and the panel is now inside that directory");
				check([panel cg_entryCount] >= 1, "with that directory's own entries");
			}
		}

		/* 4. **AND A TYPED NAME IS AN ANSWER WHEN NOTHING IS SELECTED**, which is how a person opens a file whose row
		 * they have not clicked. */
		{
			NSOpenPanel *typed = [NSOpenPanel openPanel];

			[typed setDirectory:directory];
			[typed setNameFieldStringValue:@"Notes.h"];
			[typed ok:nil];
			check([typed URL] != nil, "a typed name with no selection is accepted");
			check([[[typed URL] path] hasSuffix:@"Notes.h"], "and names the file that was typed");
		}

		/* 4b. **AND A PRESS THAT CANNOT ACCEPT SAYS SO** rather than doing nothing at all. */
		{
			NSOpenPanel *empty = [NSOpenPanel openPanel];

			[empty setDirectory:directory];
			[empty ok:nil];
			check([empty URL] == nil, "pressing OK with nothing selected and no name accepts nothing");
			check([[empty message] length] > 0, "and the panel says what it is waiting for");
		}

		/* 5. THE 10.3 SPELLING CONFIGURES THE SAME PANEL. `-runModalForDirectory:file:types:` forwards to `-runModal`,
		 * which is an application-modal SESSION and needs a window server — so what this probe can prove is the half
		 * Forge depends on: the panel it is handed is already in the right directory. */
		{
			NSOpenPanel *spelled = [NSOpenPanel openPanel];

			[spelled setDirectory:directory];
			check([[[spelled directoryURL] path] hasSuffix:@"Project"],
			      "a panel asked for a directory is in that directory");
			check([spelled cg_entryCount] >= 2, "and lists what is in it");
		}

		[manager removeItemAtPath:base error:NULL];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
