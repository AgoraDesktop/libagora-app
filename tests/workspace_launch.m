/*
 * workspace_launch — the launch verbs, the deprecated dictionary doors, and the refusals beside them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **WHAT THIS MEASURES IS WHERE A NAME BECOMES A PATH, A PATH BECOMES A URL, AND A URL BECOMES A LAUNCH** — the chain a
 * file manager walks when a person double-clicks something. A fixture bundle is written and registered with Launch
 * Services (the same fixture shape `workspace_services.m` uses), so the identifier → URL → path chain has something real
 * to resolve; nothing here launches it, because a spawned process is not what a headless probe should leave behind.
 *
 * WHAT IS ASSERTED:
 *
 *   1. THE TWO IDENTIFIER DOORS AGREE: `-URLForApplicationWithBundleIdentifier:` and the deprecated
 *      `-absolutePathForAppBundleWithIdentifier:` answer the same bundle, and both answer nil for an identifier nobody
 *      registered.
 *   2. `-fullPathForApplication:` TAKES ALL THREE NAMES a person can give — an absolute `.app` path, a bundle
 *      identifier, and a plain name — and answers nil for a path that is not there rather than a path nobody can launch.
 *   3. THE DEPRECATED DICTIONARY PAIR is derived from the live list: `-launchedApplications` has one dictionary per
 *      running application with Apple's keys, and `-activeApplication` is the frontmost one's — or an EMPTY dictionary
 *      when nothing is in front.
 *   4. THE ICON AND FILE QUESTIONS: `-iconForFiles:` answers the first path's picture (and nil for an empty array), and
 *      `-getInfoForFile:application:type:` answers YES with a handler and the extension for a file that exists, NO for
 *      one that does not.
 *   5. A FAILED LAUNCH ANSWERS NIL AND AN ERROR, rather than a made-up application.
 *   6. AND EVERY REFUSED DOOR ANSWERS ITS TYPE'S EMPTY VALUE: the five type questions (no UTI database), the two
 *      "open with" doors and the multiple-URL funnel (no launch specification in the seam), and the hide. They are
 *      checked BOTH ways — the empty answer AND that the door did not crash or invent something.
 */
#define _DEFAULT_SOURCE

#import <AppKit/NSWorkspace.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSWindow.h>

#import "AGWindowServer.h"

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSError.h>

#include <LaunchServices/LSInfo.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int s_failures;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failures++;
	}
}

/* ONE FIXTURE BUNDLE ON DISK, registered with Launch Services, so the identifier resolves to it and to nothing else.
 * It is never run: the probe checks where the chain POINTS, not what a spawn would do. */
static NSString *makeFixtureBundle(void)
{
	char root[256];
	char path[512];
	NSString *bundlePath;
	FILE *file;

	snprintf(root, sizeof root, "/tmp/agora-workspace-launch-%d.app", (int)getpid());
	bundlePath = [NSString stringWithUTF8String:root];
	mkdir(root, 0755);
	snprintf(path, sizeof path, "%s/Contents", root);
	mkdir(path, 0755);
	snprintf(path, sizeof path, "%s/Contents/MacOS", root);
	mkdir(path, 0755);
	snprintf(path, sizeof path, "%s/Contents/Info.plist", root);
	file = fopen(path, "w");
	if (file == NULL) {
		return nil;
	}
	fprintf(file,
		"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		"<plist version=\"1.0\"><dict>\n"
		"<key>CFBundleIdentifier</key><string>io.github.agoradesktop.launch</string>\n"
		"<key>CFBundleName</key><string>Launch Fixture</string>\n"
		"<key>CFBundleExecutable</key><string>LaunchFixture</string>\n"
		"<key>CFBundlePackageType</key><string>APPL</string>\n"
		"</dict></plist>\n");
	fclose(file);
	snprintf(path, sizeof path, "%s/Contents/MacOS/LaunchFixture", root);
	file = fopen(path, "w");
	if (file != NULL) {
		fprintf(file, "#!/bin/sh\nexit 0\n");
		fclose(file);
		chmod(path, 0755);
	}
	return bundlePath;
}

/* A FILE THAT EXISTS, so the file questions have one; and a path that does not, for the negative. */
static NSString *makeFixtureFile(void)
{
	char path[256];
	FILE *file;

	snprintf(path, sizeof path, "/tmp/agora-workspace-launch-%d.txt", (int)getpid());
	file = fopen(path, "w");
	if (file == NULL) {
		return nil;
	}
	fprintf(file, "hello\n");
	fclose(file);
	return [NSString stringWithUTF8String:path];
}

/* THE WINDOW LIST IS FED IN DIRECTLY, as `workspace_services.m` does: no compositor, no race, and the deprecated
 * dictionaries are measured against a list the probe controls. */
static void feed(NSWorkspace *workspace, AGWindowInfo *rows, int count)
{
	[workspace cg_applyWindowList:rows count:count];
}

static void fill(AGWindowInfo *row, const char *identifier, unsigned int handle, const char *title, int active)
{
	memset(row, 0, sizeof *row);
	snprintf(row->app_id, sizeof row->app_id, "%s", identifier);
	snprintf(row->title, sizeof row->title, "%s", title);
	row->id = handle;
	row->visible = 1;
	row->active = active;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	AGWindowInfo rows[2];
	NSString *fixture;
	NSString *file;
	NSURL *bundleURL;
	CFURLRef registered;

	printf("workspace_launch\n");
	setvbuf(stdout, NULL, _IONBF, 0);

	/* ---- 1. the identifier doors agree -------------------------------------------------------- */
	fixture = makeFixtureBundle();
	check(fixture != nil, "a fixture bundle was written");
	if (fixture == nil) {
		printf("workspace_launch: 1 case(s) failed\n");
		[pool release];
		return 1;
	}
	/* **THE CFURL IS BUILT FROM THE STRING, NOT CAST** — `NSWorkspace.m` and `workspace_services.m` both record why:
	 * passing an `NSURL` into a CF URL door aborts in this tree. And the URL is the NSURL's `absoluteString` rather
	 * than a file-system path, so the registry sees the same spelling the resolution doors ask with. */
	registered = CFURLCreateWithString(NULL, (CFStringRef)[[NSURL fileURLWithPath:fixture] absoluteString], NULL);
	check(registered != NULL && LSRegisterURL(registered, true) == 0, "and registered with Launch Services");
	if (registered != NULL) {
		CFRelease(registered);
	}
	{
		NSString *path = [workspace absolutePathForAppBundleWithIdentifier:@"io.github.agoradesktop.launch"];
		NSURL *url = [workspace URLForApplicationWithBundleIdentifier:@"io.github.agoradesktop.launch"];

		check([path isEqualToString:fixture], "the deprecated path door answers the fixture's bundle");
		check(url != nil && [[url path] isEqualToString:fixture],
		      "and `-URLForApplicationWithBundleIdentifier:` answers the SAME bundle as a URL");
		check([workspace URLForApplicationWithBundleIdentifier:@"io.github.agoradesktop.nobody"] == nil,
		      "an identifier nobody registered answers nil");
		check([workspace URLForApplicationWithBundleIdentifier:nil] == nil, "and so does a nil identifier");
	}
	bundleURL = [workspace URLForApplicationWithBundleIdentifier:@"io.github.agoradesktop.launch"];

	/* ---- 2. one door, three names ------------------------------------------------------------- */
	check([[workspace fullPathForApplication:fixture] isEqualToString:fixture],
	      "`-fullPathForApplication:` takes an absolute bundle path");
	check([[workspace fullPathForApplication:@"io.github.agoradesktop.launch"] isEqualToString:fixture],
	      "and a bundle identifier");
	{
		char name[128];
		NSString *plain;

		snprintf(name, sizeof name, "agora-workspace-launch-%d", (int)getpid());
		plain = [NSString stringWithUTF8String:name];
		/* THE PLAIN NAME IS SEARCHED FOR, not resolved through the registry — and `/tmp` is deliberately not on the
		 * search list, so a name that only exists there is NOT found, which is the honest answer. */
		check([workspace fullPathForApplication:plain] == nil,
		      "a plain name is searched in the application folders, so one outside them is not found");
	}
	check([workspace fullPathForApplication:@"/tmp/definitely-not-a-bundle.app"] == nil,
	      "a path that is not there answers nil rather than a path nobody can launch");
	check([workspace fullPathForApplication:nil] == nil, "and so does nil");

	/* ---- 3. the deprecated dictionary pair, from the live list --------------------------------- */
	{
		NSDictionary *active;
		NSArray *launched;
		NSDictionary *first;

		feed(workspace, rows, 0);
		check([workspace launchedApplications] != nil && [[workspace launchedApplications] count] == 0,
		      "with nothing running `-launchedApplications` is an empty array");
		check([[workspace activeApplication] isKindOfClass:[NSDictionary class]]
		      && [[workspace activeApplication] count] == 0,
		      "and `-activeApplication` is an EMPTY dictionary rather than nil");

		/* THE FIRST ROW IS THE REGISTERED FIXTURE, so its bundle — and therefore its name and path — resolve; the
		 * second is an identifier nothing declares, which is the negative for the same keys. */
		fill(&rows[0], "io.github.agoradesktop.launch", 11, "Launch Fixture", 1);
		fill(&rows[1], "io.github.agoradesktop.unregistered", 22, "Nobody", 0);
		feed(workspace, rows, 2);
		launched = [workspace launchedApplications];
		check([launched count] == 2, "two applications are running, and the array has two dictionaries");
		first = [launched objectAtIndex:0];
		check([[first objectForKey:@"NSApplicationBundleIdentifier"]
		       isEqualToString:@"io.github.agoradesktop.launch"],
		      "and the first dictionary carries Apple's bundle-identifier key");
		check([[first objectForKey:@"NSApplicationName"] isEqualToString:@"Launch Fixture"],
		      "its name comes from the bundle on disk");
		check([[NSURL fileURLWithPath:[first objectForKey:@"NSApplicationPath"]]
		       isEqual:[NSURL fileURLWithPath:fixture]],
		      "and its path is that bundle's");
		check([[first objectForKey:@"NSApplicationProcessIdentifier"] integerValue] == 0,
		      "while the process identifier is ZERO: the window list carries no pid, which is stated at the door");

		active = [workspace activeApplication];
		check([[active objectForKey:@"NSApplicationBundleIdentifier"]
		       isEqualToString:@"io.github.agoradesktop.launch"],
		      "`-activeApplication` is the application in front");
	}

	/* ---- 4. the icon and the file question ---------------------------------------------------- */
	file = makeFixtureFile();
	check(file != nil, "a fixture file was written");
	{
		NSArray *five = [NSArray arrayWithObjects:file, @"/tmp/other", nil];
		NSImage *first = [workspace iconForFile:file];
		NSImage *many = [workspace iconForFiles:five];

		check(many != nil, "`-iconForFiles:` answers a picture for a list of paths");
		check(many != nil && first != nil && NSEqualSizes([many size], [first size]),
		      "and it is the FIRST path's icon — the header says a stack is not built");
		check([workspace iconForFiles:[NSArray array]] == nil, "an empty list has no icon at all");
	}
	{
		NSString *app = nil;
		NSString *type = nil;

		check([workspace getInfoForFile:file application:&app type:&type],
		      "`-getInfoForFile:application:type:` answers YES for a file that exists");
		check(type != nil && [type isEqualToString:@"txt"], "and the type is the path's extension");
		printf("  (note: the file's default handler is %s)\n", (app != nil) ? [app UTF8String] : "(none)");
		check([workspace getInfoForFile:@"/tmp/not-here-at-all.txt" application:&app type:&type] == NO,
		      "and NO for one that does not");
	}

	/* ---- 5. a launch that cannot happen answers nil AND an error ------------------------------ */
	{
		NSError *error = nil;
		NSRunningApplication *app;

		app = [workspace launchApplicationAtURL:[NSURL fileURLWithPath:@"/tmp/definitely-not-a-bundle.app"]
					       options:NSWorkspaceLaunchDefault
					 configuration:nil
						 error:&error];
		printf("  (note: launching a missing bundle answered %s, error %s)\n",
		       (app != nil) ? "an application" : "nil",
		       (error != nil) ? [[error localizedDescription] UTF8String] : "(none)");
		check(app == nil, "launching a URL that is not there answers nil rather than an invented application");
		check(error != nil, "and an error, because the caller passed an outError");
	}
	{
		NSRunningApplication *app = [workspace launchApplication:@"io.github.agoradesktop.launch"
							       showIcon:YES
							      autolaunch:NO];

		/* THE FIXTURE IS NOT RUNNING, and this tier does not track a spawned process, so nil is the documented answer
		 * for a fresh launch — the header says so at both launch doors. */
		check(app == nil, "the 10.6 launch spelling accepts its two flags and answers like `-launchApplication:`");
	}

	/* ---- 6. the refusals, both ways ----------------------------------------------------------- */
	{
		NSError *error = nil;
		NSArray *identifiers = (NSArray *)@"untouched";

		check([workspace typeOfFile:file error:&error] == nil, "`-typeOfFile:error:` refuses: there is no UTI database");
		check(![workspace type:@"public.png" conformsToType:@"public.image"], "`-type:conformsToType:` refuses");
		check([workspace localizedDescriptionForType:@"public.png"] == nil,
		      "`-localizedDescriptionForType:` refuses");
		check([workspace preferredFilenameExtensionForType:@"public.png"] == nil,
		      "`-preferredFilenameExtensionForType:` refuses");
		check(![workspace filenameExtension:@"png" isValidForType:@"public.png"],
		      "`-filenameExtension:isValidForType:` refuses");
		check(![workspace openFile:file withApplication:@"Launch Fixture"],
		      "`-openFile:withApplication:` refuses: the seam has no launch specification");
		check(![workspace openFile:file withApplication:@"Launch Fixture" andDeactivate:YES],
		      "and so does its andDeactivate: sibling");
		check(![workspace openURLs:[NSArray arrayWithObject:[NSURL fileURLWithPath:file]]
		       withAppBundleIdentifier:@"io.github.agoradesktop.launch"
				   options:NSWorkspaceLaunchDefault
	     additionalEventParamDescriptor:nil
			  launchIdentifiers:&identifiers],
		      "`-openURLs:withAppBundleIdentifier:…` refuses");
		check(identifiers == (NSArray *)@"untouched" || identifiers == nil,
		      "and it does not write a launch identifier it never obtained");
		[workspace hideOtherApplications];
		check(1, "`-hideOtherApplications` answers nothing and does not crash");
	}

	remove([file UTF8String]);
	[pool release];
	printf("\nworkspace_launch: %d case(s) failed\n", s_failures);
	return (s_failures == 0) ? 0 : 1;
}
