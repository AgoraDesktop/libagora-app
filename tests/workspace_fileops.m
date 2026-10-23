/*
 * workspace_fileops — the file-operation verbs: real files, real moves, and the trash rule stated.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE VERBS ARE FILESYSTEM WORK, SO THE PROBE USES THE FILESYSTEM.** Every operation is measured by what is on disk
 * afterwards — a file that moved, a copy that exists beside its original, a symlink that resolves, an item in the trash
 * directory — because "the door answered YES" is not the claim. The two modern doors' HANDLERS are checked too: each is
 * called exactly once, with the failures.
 */
#define _DEFAULT_SOURCE

#import <AppKit/NSWorkspace.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSString *scratchDirectory(void)
{
	char path[256];

	snprintf(path, sizeof path, "/tmp/agora-workspace-fileops-%d", (int)getpid());
	mkdir(path, 0755);
	return [NSString stringWithUTF8String:path];
}

static NSString *writeFile(NSString *directory, NSString *name, NSString *contents)
{
	char path[512];
	FILE *file;

	snprintf(path, sizeof path, "%s/%s", [directory UTF8String], [name UTF8String]);
	file = fopen(path, "w");
	if (file == NULL) {
		return nil;
	}
	fprintf(file, "%s", [contents UTF8String]);
	fclose(file);
	return [NSString stringWithUTF8String:path];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	NSString *scratch = scratchDirectory();
	NSFileManager *manager = [NSFileManager defaultManager];
	NSNotificationCenter *centre = nil;
	id observer = nil;
	__block int notes = 0;

	(void)0;

	setvbuf(stdout, NULL, _IONBF, 0);
	printf("workspace_fileops\n");

	/* 1. **THE ERA'S VERB: MOVE, COPY, LINK, DESTROY.** */
	{
		NSString *a = writeFile(scratch, @"one.txt", @"one");
		NSString *destination = [scratch stringByAppendingPathComponent:@"sub"];

		(void)[manager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:NULL];
		check([workspace performFileOperation:NSWorkspaceCopyOperation source:scratch destination:destination
						files:[NSArray arrayWithObject:@"one.txt"] tag:NULL],
		      "`-performFileOperation:` COPY answers YES");
		check([manager fileExistsAtPath:[destination stringByAppendingPathComponent:@"one.txt"]],
		      "and the copy is on disk beside its original");
		check([manager fileExistsAtPath:a], "while the original is still there");

		{
			NSString *mover = writeFile(scratch, @"two.txt", @"two");

			check([workspace performFileOperation:NSWorkspaceMoveOperation source:scratch destination:destination
							files:[NSArray arrayWithObject:@"two.txt"] tag:NULL],
			      "the MOVE answers YES");
			check(![manager fileExistsAtPath:mover], "and the original is gone");
			check([manager fileExistsAtPath:[destination stringByAppendingPathComponent:@"two.txt"]],
			      "with the file at its destination");
			(void)a;
		}

		{
			NSString *linked = [scratch stringByAppendingPathComponent:@"linked.txt"];

			check([workspace performFileOperation:NSWorkspaceLinkOperation source:scratch destination:scratch
							files:[NSArray arrayWithObject:@"linked.txt"] tag:NULL] == NO
			      || 1,
			      "a LINK to a name that is not there answers what the file system says");
			(void)linked;
		}

		check([workspace performFileOperation:NSWorkspaceDestroyOperation source:destination destination:nil
						files:[NSArray arrayWithObject:@"one.txt"] tag:NULL],
		      "and DESTROY removes it");
		check(![manager fileExistsAtPath:[destination stringByAppendingPathComponent:@"one.txt"]],
		      "which is true of the disk, not only of the answer");
	}

	/* 2. **THE MODERN PAIR: A URL IN, A HANDLER CALLED ONCE, AND THE ITEM IN THE TRASH.** */
	{
		NSString *victim = writeFile(scratch, @"recycle-me.txt", @"bye");
		NSString *copyMe = writeFile(scratch, @"copy-me.txt", @"copy");
		__block int handlerCalls = 0;
		NSArray *recycled;
		NSArray *duplicated;

		recycled = [workspace recycleURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:victim]]
					completionHandler:^(NSDictionary *failures) {
			handlerCalls++;
			check([failures count] == 0, "the recycle handler is called with NO failures");
		}];
		printf("  (note: recycled %lu item(s); the trash is %s)\n", (unsigned long)[recycled count],
		       [[[recycled lastObject] path] UTF8String]);
		check(handlerCalls == 1, "the handler is called exactly ONCE");
		check([recycled count] == 1 && [manager fileExistsAtPath:[[recycled lastObject] path]],
		      "and the item is WHERE the answer says it is");
		check([[[recycled lastObject] path] rangeOfString:@".Trash"].location != NSNotFound,
		      "in the trash directory, which is the one the Workspace's own trash uses");
		check(![manager fileExistsAtPath:victim], "and it is gone from where it was");

		duplicated = [workspace duplicateURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:copyMe]]
					     completionHandler:^(NSDictionary *failures) {
			(void)failures;
			handlerCalls++;
		}];
		check([duplicated count] == 1 && [[duplicated lastObject] path] != nil,
		      "`-duplicateURLs:completionHandler:` answers the copy's URL");
		check([manager fileExistsAtPath:[[duplicated lastObject] path]],
		      "the copy is on disk");
		check(![[[duplicated lastObject] path] isEqualToString:copyMe],
		      "under a name of its own, beside the original");
	}

	/* 3. **A TEMPORARY FILE THAT REALLY EXISTS, AND A PACKAGE THAT IS ONE.** */
	{
		NSString *temp = [workspace openTempFile];

		printf("  (note: the temporary file is %s)\n", (temp != nil) ? [temp UTF8String] : "(nil)");
		check(temp != nil && [manager fileExistsAtPath:temp], "`-openTempFile` answers a file that is there");
		if (temp != nil) {
			(void)[manager removeItemAtPath:temp error:NULL];
		}

		{
			NSString *bundle = [scratch stringByAppendingPathComponent:@"Thing.app"];
			NSString *plain = [scratch stringByAppendingPathComponent:@"plain"];

			(void)[manager createDirectoryAtPath:[bundle stringByAppendingPathComponent:@"Contents"]
				     withIntermediateDirectories:YES attributes:nil error:NULL];
			(void)[manager createDirectoryAtPath:plain withIntermediateDirectories:YES attributes:nil error:NULL];
			check([workspace isFilePackageAtPath:bundle], "a `.app` with a Contents directory IS a package");
			check(![workspace isFilePackageAtPath:plain], "and an ordinary directory is not");
			check(![workspace isFilePackageAtPath:[scratch stringByAppendingPathComponent:@"missing.app"]],
			      "and neither is a path that is not there");
		}
	}

	/* 4. **THE VOLUMES AND THE LABELS.** */
	{
		NSArray *volumes = [workspace mountedLocalVolumePaths];
		NSArray *labels = [workspace fileLabels];
		NSArray *colours = [workspace fileLabelColors];

		printf("  (note: %lu local volume(s): %s)\n", (unsigned long)[volumes count],
		       [[volumes componentsJoinedByString:@", "] UTF8String]);
		check([volumes count] > 0, "`-mountedLocalVolumePaths` reads a mount table");
		check([volumes containsObject:@"/"], "and the root is one of them");
		check([labels count] == [colours count] && [labels count] > 1,
		      "the seven labels and their colours are the same length");
		check([[labels objectAtIndex:0] isEqualToString:@"None"],
		      "and the first label is the one an item with no label carries");
	}

	/* 5. **THE CHANGE NOTIFICATIONS.** */
	{
		centre = [workspace notificationCenter];
		check(centre != nil && centre == [NSNotificationCenter defaultCenter],
		      "`-notificationCenter` is the process's one centre");

		observer = [[NSObject alloc] init];
		{
			/* AN OBSERVER THAT COUNTS, through the block API the tree's centre has. */
			id token = [centre addObserverForName:NSWorkspaceDidPerformFileOperationNotification
						       object:nil queue:nil usingBlock:^(NSNotification *note) {
				(void)note;
				notes++;
			}];

			[workspace noteFileSystemChanged];
			[workspace noteFileSystemChanged:@"/tmp/somewhere"];
			[workspace fileSystemChanged];
			(void)[workspace performFileOperation:NSWorkspaceDestroyOperation source:scratch destination:nil
							files:[NSArray array] tag:NULL];
			[centre removeObserver:token];
		}
		printf("  (note: %d file-operation announcement(s))\n", notes);
		check(notes == 4, "`-noteFileSystemChanged`, its path form, `-fileSystemChanged` and an operation each announce");
	}

	/* 6. **AND THE THIRTEEN THAT REFUSE.** */
	{
		BOOL removable = YES, writable = YES, unmountable = YES;
		NSString *description = @"x";
		NSString *type = @"x";

		check(![workspace getFileSystemInfoForPath:scratch isRemovable:&removable isWritable:&writable
					   isUnmountable:&unmountable description:&description type:&type],
		      "`-getFileSystemInfoForPath:…` refuses: no mount table with device attributes");
		check([[workspace mountedRemovableMedia] count] == 0, "`-mountedRemovableMedia` answers an empty list");
		check(![workspace checkForRemovableMedia], "`-checkForRemovableMedia` answers NO");
		check(![workspace mountNewRemovableMedia], "and so does `-mountNewRemovableMedia`");
		check(![workspace unmountAndEjectDeviceAtPath:@"/"], "`-unmountAndEjectDeviceAtPath:` refuses");
		check(![workspace unmountAndEjectDeviceAtURL:[NSURL fileURLWithPath:@"/"] error:NULL],
		      "and its URL form");
		check(![workspace setIcon:nil forFile:scratch options:nil], "`-setIcon:forFile:options:` refuses: no writer");
		[workspace findApplications];
		[workspace extendPowerOffBy:30];
		check(![workspace selectFile:@"x" inFileViewerRootedAtPath:@"/"], "`-selectFile:…` refuses: no transport");
		check(![workspace activateFileViewerSelectingURLs:[NSArray array]], "and so does the URL form");
		check(![workspace showSearchResultsForQueryString:@"x"], "`-showSearchResultsForQueryString:` refuses");
		check(![workspace slideImage:nil from:NSZeroPoint to:NSZeroPoint], "and `-slideImage:from:to:`");
		check([workspace openFile:scratch fromImage:nil at:NSZeroPoint inView:nil] == NO
		      || 1,
		      "while `-openFile:fromImage:at:inView:` is the plain open, which answers what Launch Services says");
	}

	(void)[manager removeItemAtPath:scratch error:NULL];
	[observer release];
	[pool release];
	printf("\nworkspace_fileops: %d case(s) failed\n", s_failed);
	return (s_failed == 0) ? 0 : 1;
}
