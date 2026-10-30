/*
 * workspace_single_instance — a bundle that is already running is brought forward, not started again.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **TWO PROCESSES OF ONE BUNDLE ARE ONE APPLICATION, AND ONE APPLICATION IS THE WHOLE POINT.** Every row the
 * compositor lists is grouped by `CFBundleIdentifier`, so the Dock draws one tile, the menu bar has one owner and
 * `-runningApplications` has one entry — and a second launch is then not a second application but a second copy of one.
 * MEASURED before this existed: two Forge instances shared a tile, and one press of that tile's Quit ended one of them
 * and left the other, so the Quit looked like it had done nothing.
 *
 * `-[NSWorkspace openURL:]` is the door every launch the desktop performs goes through (a Dock tile with nothing
 * behind it, `-launchApplication:`, anything that resolves a document to an application), so the rule is stated there:
 * if the bundle's identifier is ALREADY in the window list, activate that application and start nothing.
 *
 * **THE PROOF IS A SIDE EFFECT, NOT A RETURN VALUE.** The bundle this test writes has an executable whose only job is
 * to `touch` a file, so "no second copy" is a file that does not appear — and then the same test makes the application
 * NOT running and launches again, so the spawn being forbidden is one the reader can see happen. A test that asserted
 * only the negative would pass for a launcher that never worked.
 */
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include "AGWindowServer.h"

#include <stdio.h>
#include <string.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* DRAIN THE QUEUE, so a request has been read by the compositor and its answer is in the seam's own storage. */
static void fn_pump(NSApplication *app, int passes)
{
	int i;

	for (i = 0; i < passes; i++) {
		NSEvent *e = [app nextEventMatchingMask:NSAnyEventMask
					      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
						 inMode:nil dequeue:YES];

		if (e != nil) {
			[app sendEvent:e];
		}
	}
}

/* nsstring -> C, for the two file names this test makes. */
static void fn_path(const char *pattern, char *buffer, size_t size)
{
	snprintf(buffer, size, pattern, (int)getpid());
}

/* A BUNDLE ON DISK WHOSE EXECUTABLE TOUCHES `markerPath`. The manifest is written by hand because what is under test
 * is the AppKit's READING of it: a plist writer would be a second thing that could be wrong. */
static void fn_write_bundle(const char *rootPath, const char *identifier, const char *markerPath)
{
	char path[512];
	char source[1024];
	FILE *file;

	fn_path("/tmp/agora-single-%d.app", path, sizeof path);
	mkdir(path, 0755);
	snprintf(source, sizeof source, "%s/Contents", path);
	mkdir(source, 0755);
	snprintf(source, sizeof source, "%s/Contents/MacOS", path);
	mkdir(source, 0755);

	snprintf(source, sizeof source, "%s/Contents/Info.plist", path);
	file = fopen(source, "w");
	if (file != NULL) {
		fprintf(file,
			"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
			"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
			"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
			"<plist version=\"1.0\"><dict>\n"
			"<key>CFBundleIdentifier</key><string>%s</string>\n"
			"<key>CFBundleExecutable</key><string>Single</string>\n"
			"<key>CFBundleName</key><string>Single</string>\n"
			"</dict></plist>\n", identifier);
		fclose(file);
	}

	snprintf(source, sizeof source, "%s/Contents/MacOS/Single", path);
	file = fopen(source, "w");
	if (file != NULL) {
		fprintf(file, "#!/bin/sh\ntouch '%s'\n", markerPath);
		fclose(file);
	}
	chmod(source, 0755);
	(void)rootPath;
}

static void fn_remove_bundle(void)
{
	char path[512];

	fn_path("/tmp/agora-single-%d.app/Contents/MacOS/Single", path, sizeof path);
	unlink(path);
	fn_path("/tmp/agora-single-%d.app/Contents/MacOS", path, sizeof path);
	rmdir(path);
	fn_path("/tmp/agora-single-%d.app/Contents/Info.plist", path, sizeof path);
	unlink(path);
	fn_path("/tmp/agora-single-%d.app/Contents", path, sizeof path);
	rmdir(path);
	fn_path("/tmp/agora-single-%d.app", path, sizeof path);
	rmdir(path);
}

/* THE RUNNING APPLICATION FOR AN IDENTIFIER, as the Dock's model sees it. */
static NSRunningApplication *fn_running(NSString *identifier)
{
	NSArray *all = [[NSWorkspace sharedWorkspace] runningApplications];
	NSUInteger i;

	for (i = 0; i < [all count]; i++) {
		NSRunningApplication *candidate = [all objectAtIndex:i];

		if ([[candidate bundleIdentifier] isEqualToString:identifier]) {
			return candidate;
		}
	}
	return nil;
}

int main(int argc, char **argv)
{
	/* **THE COLD LAUNCHER, WHICH IS THE CASE THAT BROKE.** A process that has just started has been sent no snapshot,
	 * so its model is EMPTY — and empty reads as "nothing is running" rather than "not told yet", which started a
	 * second copy of an application that was already on the glass. This mode is that process: it is spawned by the
	 * test below, opens the bundle and exits, and the parent reads the result from the marker file. */
	if (argc > 2 && strcmp(argv[1], "--open") == 0) {
		BOOL opened = [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:
			[NSString stringWithUTF8String:argv[2]]]];

		return opened ? 0 : 1;
	}
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		AGWindowServer *server = NULL;
		NSString *identifier = @"io.github.agoradesktop.singleinstance";
		char markerPath[512];
		char bundlePath[512];
		char rootPath[512];
		NSURL *bundleURL;
		AGWindow *fake = NULL;
		int pass;
		BOOL opened;

		[app finishLaunching];
		server = AGWindowServerShared();
		if (server == NULL) {
			printf("SKIP: no window server\n");
			return 77;
		}
		fn_path("/tmp/agora-single-%d.spawned", markerPath, sizeof markerPath);
		fn_path("/tmp/agora-single-%d.app", rootPath, sizeof rootPath);
		fn_path("/tmp/agora-single-%d.app", bundlePath, sizeof bundlePath);
		unlink(markerPath);
		fn_write_bundle(rootPath, [identifier UTF8String], markerPath);
		bundleURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:bundlePath]];

		/* A WINDOW THAT DECLARES THE BUNDLE'S IDENTIFIER, which is what "the application is running" MEANS here: the
		 * compositor groups rows by it and `-runningApplications` is built from those rows. */
		fake = AGWindowCreate(server, 200, 100, "single instance");
		AGWindowSetAppID(fake, [identifier UTF8String]);
		AGWindowShow(fake);
		for (pass = 0; pass < 120 && fn_running(identifier) == nil; pass++) {
			AGWindowServerDispatchPending(server);
			fn_pump(app, 1);
		}
		check(fn_running(identifier) != nil,
		      "the application that declares the bundle's identifier is RUNNING");

		/* 1. **A LAUNCH OF A RUNNING BUNDLE STARTS NOTHING.** Answered YES — the request was served by bringing the
		 * application forward — and the marker its executable would leave does not appear. */
		opened = [[NSWorkspace sharedWorkspace] openURL:bundleURL];
		check(opened, "opening a bundle that is already running is ANSWERED, not refused");
		usleep(400000);
		check(access(markerPath, F_OK) != 0,
		      "and its executable was NOT spawned — there is no second copy of that application");

		/* 1b. **AND A LAUNCHER THAT HAS JUST STARTED DOES THE SAME.** It has never been sent a snapshot, so the wait
		 * inside `-openURL:` is the whole of what makes this pass; without it the child's model is empty and it
		 * starts a second copy. */
		{
			pid_t child = 0;
			char *childArgv[4];
			int status = -1;

			childArgv[0] = argv[0];
			childArgv[1] = (char *)"--open";
			childArgv[2] = bundlePath;
			childArgv[3] = NULL;
			if (posix_spawn(&child, argv[0], NULL, NULL, childArgv, environ) == 0) {
				(void)waitpid(child, &status, 0);
			}
			check(status == 0, "a FRESH launcher process opened the bundle and said so");
			usleep(400000);
			check(access(markerPath, F_OK) != 0,
			      "and it did not spawn a second copy either, though its model started empty");
		}

		/* 2. **AND THE SAME LAUNCH SPAWNS WHEN NOTHING IS RUNNING**, which is what makes the claim above mean
		 * something. The window goes, the list is read until the application is gone, and the launch is repeated. */
		AGWindowDestroy(fake);
		fake = NULL;
		for (pass = 0; pass < 120 && fn_running(identifier) != nil; pass++) {
			AGWindowServerDispatchPending(server);
			fn_pump(app, 1);
		}
		check(fn_running(identifier) == nil, "with that window gone the application is no longer running");
		opened = [[NSWorkspace sharedWorkspace] openURL:bundleURL];
		check(opened, "opening it again with nothing running is answered too");
		for (pass = 0; pass < 200 && access(markerPath, F_OK) != 0; pass++) {
			fn_pump(app, 1);
			usleep(20000);
		}
		check(access(markerPath, F_OK) == 0,
		      "and NOW its executable ran, so the case above forbade a spawn that otherwise happens");

		unlink(markerPath);
		fn_remove_bundle();
	}
	printf("%s: %d failure(s)\n", s_failed == 0 ? "PASS" : "FAIL", s_failed);
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
