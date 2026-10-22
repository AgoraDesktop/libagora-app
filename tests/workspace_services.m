/*
 * workspace_services — NSWorkspace and NSRunningApplication, measured.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE WINDOW LIST IS FED IN DIRECTLY, WHICH IS WHY THIS TEST NEEDS NO COMPOSITOR.** `NSWorkspace`'s whole model is
 * one diff over two snapshots, and the snapshot is a plain array of rows — so the interesting half (launch,
 * terminate, activate, and the application objects the three of them carry) is a sequence here rather than a race
 * against another process. The other half, that the compositor's snapshot actually reaches this door, is the
 * window-list probe's and the Dock's.
 *
 * WHAT ELSE IS MEASURED, AND WHY EACH: a bundle identifier resolves to the bundle on disk (the door Launch Services
 * gained for exactly this), an application's name and icon come out of that bundle, an item's icon comes out of Icon
 * Services as an NSImage, and every door that cannot be honoured says NO instead of inventing an answer.
 */
#define _DEFAULT_SOURCE

#import <AppKit/NSWorkspace.h>
#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSImage.h>

#import "AGWindowServer.h"

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSNotification.h>

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

/* ---------------------------------------------------------------------------------------------------
 * an observer, because the three transitions are the part a Dock reacts to
 * --------------------------------------------------------------------------------------------------- */
@interface AGRecorder : NSObject
{
@public
	int launches;
	int terminations;
	int activations;
	NSRunningApplication *lastLaunched;
	NSRunningApplication *lastTerminated;
	NSRunningApplication *lastActivated;
}
@end

@implementation AGRecorder
- (void)launched:(NSNotification *)note
{
	launches++;
	lastLaunched = [[note userInfo] objectForKey:NSWorkspaceApplicationKey];
}
- (void)terminated:(NSNotification *)note
{
	terminations++;
	lastTerminated = [[note userInfo] objectForKey:NSWorkspaceApplicationKey];
}
- (void)activated:(NSNotification *)note
{
	activations++;
	lastActivated = [[note userInfo] objectForKey:NSWorkspaceApplicationKey];
}
@end

/* ONE FIXTURE BUNDLE ON DISK, so the identifier → bundle → name → icon chain has something to resolve. It is not
 * run; nothing here launches anything. */
static NSString *makeFixtureBundle(void)
{
	char root[256];
	char path[512];
	NSString *bundlePath;
	FILE *file;

	snprintf(root, sizeof root, "/tmp/agora-workspace-services-%d.app", (int)getpid());
	bundlePath = [NSString stringWithUTF8String:root];
	snprintf(path, sizeof path, "%s/Contents/MacOS", root);
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
		"<key>CFBundleIdentifier</key><string>io.github.agoradesktop.fixture</string>\n"
		"<key>CFBundleName</key><string>Fixture App</string>\n"
		"<key>CFBundleExecutable</key><string>Fixture</string>\n"
		"<key>CFBundlePackageType</key><string>APPL</string>\n"
		"</dict></plist>\n");
	fclose(file);

	snprintf(path, sizeof path, "%s/Contents/MacOS/Fixture", root);
	file = fopen(path, "w");
	if (file != NULL) {
		fprintf(file, "#!/bin/sh\nexit 0\n");
		fclose(file);
		chmod(path, 0755);
	}
	return bundlePath;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
	AGRecorder *recorder = [[AGRecorder alloc] init];
	AGWindowInfo rows[3];
	NSString *fixture;
	NSArray *running;
	NSRunningApplication *one;
	NSImage *icon;

	printf("workspace_services\n");

	check(workspace != nil, "there is a shared workspace");
	check([NSWorkspace sharedWorkspace] == workspace, "and asking twice is the same object");

	/* **NO COMPOSITOR MEANS NO APPLICATIONS, NOT A CRASH AND NOT AN INVENTED ONE.** This suite runs without a
	 * server, so the list is empty until a snapshot is fed in below. */
	check([[workspace runningApplications] isKindOfClass:[NSArray class]], "runningApplications is an array");
	check([[workspace runningApplications] count] == 0, "and it is empty with nothing connected");
	check([workspace frontmostApplication] == nil, "and nothing is frontmost");

	/* ---- the snapshot diff --------------------------------------------------------------- */
	[[NSNotificationCenter defaultCenter] addObserver:recorder selector:@selector(launched:)
						     name:NSWorkspaceDidLaunchApplicationNotification object:workspace];
	[[NSNotificationCenter defaultCenter] addObserver:recorder selector:@selector(terminated:)
						     name:NSWorkspaceDidTerminateApplicationNotification object:workspace];
	[[NSNotificationCenter defaultCenter] addObserver:recorder selector:@selector(activated:)
						     name:NSWorkspaceDidActivateApplicationNotification object:workspace];

	memset(rows, 0, sizeof rows);
	snprintf(rows[0].app_id, sizeof rows[0].app_id, "io.github.agoradesktop.one");
	snprintf(rows[0].title, sizeof rows[0].title, "One");
	rows[0].id = 11;
	rows[0].visible = 1;
	rows[0].active = 1;
	snprintf(rows[1].app_id, sizeof rows[1].app_id, "io.github.agoradesktop.two");
	snprintf(rows[1].title, sizeof rows[1].title, "Two");
	rows[1].id = 22;
	rows[1].visible = 1;
	rows[1].active = 0;

	[workspace cg_applyWindowList:rows count:2];
	running = [workspace runningApplications];
	check([running count] == 2, "two applications are running, one per identifier");
	check(recorder->launches == 2, "and both launches were announced");
	check([[workspace frontmostApplication] isEqual:recorder->lastActivated]
	      && [[[workspace frontmostApplication] bundleIdentifier] isEqualToString:@"io.github.agoradesktop.one"],
	      "the active window's application is frontmost, and that was announced");
	one = [running objectAtIndex:0];
	check([one isActive], "the frontmost application says it is active");
	check(![[running objectAtIndex:1] isActive], "and the other one does not");
	check([one ownsMenuBar], "the frontmost application owns the menu bar");

	/* THE SAME SNAPSHOT AGAIN IS NOT A CHANGE: a client that pumps must not get a launch storm. */
	[workspace cg_applyWindowList:rows count:2];
	check(recorder->launches == 2 && recorder->terminations == 0 && recorder->activations == 1,
	      "an unchanged snapshot announces nothing");

	/* ONE GOES AWAY, THE OTHER TAKES THE KEYBOARD. */
	snprintf(rows[0].app_id, sizeof rows[0].app_id, "io.github.agoradesktop.two");
	rows[0].id = 22;
	rows[0].active = 1;
	[workspace cg_applyWindowList:rows count:1];
	running = [workspace runningApplications];
	check([running count] == 1, "one application is left");
	check(recorder->terminations == 1 && recorder->lastTerminated != nil
	      && [[recorder->lastTerminated bundleIdentifier] isEqualToString:@"io.github.agoradesktop.one"],
	      "the one that went away was announced, by identifier");
	check([recorder->lastTerminated isTerminated], "and it is marked terminated, so it is not the live one");
	check([[[workspace frontmostApplication] bundleIdentifier] isEqualToString:@"io.github.agoradesktop.two"],
	      "and the survivor is frontmost");

	/* **THE ORDINARY BAND, WHICH IS THE DIFFERENCE BETWEEN A WINDOW AND FURNITURE.** A row's LEVEL is what tells a
	 * desktop from a file window, and it is the whole of what decides whether a Dock click raises something or asks
	 * the application for a window. Workspace is the case that made this necessary: its desktop is a window, at a
	 * level below every ordinary one, so a Workspace with no file window is "running with nothing to raise" — and
	 * that click has to open a window rather than raise the desktop nobody can see. */
	{
		AGWindowInfo furniture[2];
		NSRunningApplication *app;

		memset(furniture, 0, sizeof furniture);
		snprintf(furniture[0].app_id, sizeof furniture[0].app_id, "io.github.agoradesktop.three");
		furniture[0].id = 41;
		furniture[0].level = -2147483627;	/* a desktop: below every ordinary window */
		furniture[0].visible = 1;
		[workspace cg_applyWindowList:furniture count:1];
		app = [[workspace runningApplications] lastObject];
		check([[app bundleIdentifier] isEqualToString:@"io.github.agoradesktop.three"],
		      "an application showing only furniture is still a running application");
		check([[app cg_ordinaryWindowIDs] count] == 0, "and it has no window a click could raise");
		check([app activateWithOptions:NSApplicationActivateAllWindows],
		      "so a click asks it to reopen, and that is a click that did something");

		furniture[1] = furniture[0];
		furniture[1].id = 42;
		furniture[1].level = 0;	/* a file window */
		[workspace cg_applyWindowList:furniture count:2];
		check([[app cg_ordinaryWindowIDs] count] == 1,
		      "adding an ordinary window gives the click something to raise instead");
	}

	/* A ROW WITH NO APPLICATION IS NOT AN APPLICATION. */
	memset(&rows[0], 0, sizeof rows[0]);
	rows[0].id = 33;
	[workspace cg_applyWindowList:rows count:1];
	check([[workspace runningApplications] count] == 0, "an anonymous window is not an application");
	check([[workspace frontmostApplication] bundleIdentifier] != nil
	      || [workspace frontmostApplication] == nil, "and nothing frontmost is fine");

	[[NSNotificationCenter defaultCenter] removeObserver:recorder];

	/* ---- identifier → bundle → name and icon ---------------------------------------------- */
	fixture = makeFixtureBundle();
	check(fixture != nil, "a fixture bundle was written");
	if (fixture != nil) {
		/* **THE CFURL IS BUILT FROM THE STRING, NOT CAST.** See the note in `NSWorkspace.m`: passing an `NSURL`
		 * into a CF URL door aborts in this tree, because `-[NSURL _cfurl]` was compiled with a different signature
		 * from the one Core Foundation calls it with. */
		CFURLRef url = CFURLCreateWithString(NULL, (CFStringRef)[[NSURL fileURLWithPath:fixture] absoluteString],
						     NULL);

		check(url != NULL && LSRegisterURL(url, true) == 0, "and registered with Launch Services");
		if (url != NULL) {
			CFRelease(url);
		}
		check([[workspace absolutePathForAppBundleWithIdentifier:@"io.github.agoradesktop.fixture"]
		       isEqualToString:fixture], "the identifier resolves to the bundle on disk");
		check([workspace absolutePathForAppBundleWithIdentifier:@"io.github.agoradesktop.nothing"] == nil,
		      "and an unknown identifier resolves to nil");

		icon = [workspace iconForFile:fixture];
		check(icon != nil && [icon size].width > 0.0 && [icon size].height > 0.0,
		      "an icon comes back for the bundle, with a size");
		check([workspace iconForFileType:@"public.folder"] != nil,
		      "and for a type, through Icon Services");

		{
			NSRunningApplication *application =
				[[NSRunningApplication alloc] cg_initWithBundleIdentifier:@"io.github.agoradesktop.fixture"];

			check([[application bundleURL] isEqual:[NSURL fileURLWithPath:fixture]],
			      "a running application resolves its own bundle");
			check([[application localizedName] isEqualToString:@"Fixture App"],
			      "its name comes from CFBundleName");
			check([application icon] != nil, "and it has an icon");
			check([[application executableURL] path] != nil, "and an executable path");
			check(![application isActive] && ![application isHidden] && ![application isTerminated],
			      "a fresh application is not active, not hidden and not terminated");
			check([application processIdentifier] == 0, "there is no pid to publish, and it says zero");
			check([application activationPolicy] == NSApplicationActivationPolicyRegular,
			      "every Agora application is Regular for now");
			check(![application activateWithOptions:NSApplicationActivateAllWindows],
			      "activating an application with no windows answers NO");
			check(![application terminate], "and there is nothing to ask to quit");
			check(![application forceTerminate], "Force Quit is owed to the session, so it answers NO");
			check(![application hide] && ![application unhide], "and hide/unhide are the same honest NO");
			[application release];
		}

		check(![workspace openURL:[NSURL fileURLWithPath:@"/tmp/agora-nothing-here"]],
		      "opening a path that does not exist, or that nothing claims, answers NO");
	}

	/* **AND THE FOUR APPLICATION DOORS THE SWEEP ADDS.** The current application is the one process this tier publishes
	 * a pid for; the lookup by pid therefore answers for it and for nothing else — which is the true answer rather than a
	 * refusal, because "no application I know of has that pid" is a fact. */
	{
		NSRunningApplication *current = [NSRunningApplication currentApplication];
		NSRunningApplication *samePid;
		NSRunningApplication *stranger;
		NSArray *byIdentifier;
		NSInteger architecture;
		NSString *mainIdentifier = [[NSBundle mainBundle] bundleIdentifier];

		check(current != nil, "`+currentApplication` answers an application for this process");
		check([NSRunningApplication currentApplication] == current,
		      "and the SAME object every time, which is what a caller comparing with `==` expects");
		check(current != nil && [current processIdentifier] == getpid(),
		      "its pid is this process's, which is the one pid this tier can publish");
		check(current != nil && [[current bundleIdentifier] length] > 0,
		      "and it carries an identifier");
		check(mainIdentifier == nil || [[current bundleIdentifier] isEqualToString:mainIdentifier],
		      "which is the main bundle's when this process HAS a bundle");

		samePid = [NSRunningApplication runningApplicationWithProcessIdentifier:getpid()];
		check(samePid == current, "the lookup BY PID finds it");
		stranger = [NSRunningApplication runningApplicationWithProcessIdentifier:getpid() + 1];
		check(stranger == nil,
		      "and a pid nobody published answers nil — an ordinary nil, because a window server does not publish pids");

		byIdentifier = [NSRunningApplication runningApplicationsWithBundleIdentifier:mainIdentifier];
		check(byIdentifier != nil, "the filter by identifier answers an array even when nothing matches");
		{
			NSUInteger i;
			BOOL allMatch = YES;

			for (i = 0; i < [byIdentifier count]; i++) {
				if (![[[byIdentifier objectAtIndex:i] bundleIdentifier] isEqualToString:mainIdentifier]) {
					allMatch = NO;
				}
			}
			check(allMatch, "and every element it answers carries the identifier that was asked for");
		}
		check([[NSRunningApplication runningApplicationsWithBundleIdentifier:nil] count] == 0,
		      "a nil identifier matches nothing rather than everything");

		/* THE ARCHITECTURE IS READ FROM THE EXECUTABLE'S OWN HEADER, through the bundle's door. This host is x86-64,
		 * and the test asserts the SHAPE (a code from Foundation's enum) rather than a constant that would pin the
		 * machine — plus the one equality that is checkable here: the answer for this process is the answer the bundle
		 * itself gives. */
		architecture = [current executableArchitecture];
		printf("  (note: this process's executable architecture reads %ld)\n", (long)architecture);
		check(architecture != 0, "`-executableArchitecture` reads a code from the executable's ELF header");
		{
			NSArray *codes = [[NSBundle mainBundle] executableArchitectures];

			check([codes count] == 0 || architecture == (NSInteger)[[codes objectAtIndex:0] integerValue],
			      "and it is the SAME code the bundle's own door reports for this executable");
		}
	}

	[recorder release];
	[pool release];
	printf("workspace_services: %d case(s) failed\n", s_failures);
	return s_failures == 0 ? 0 : 1;
}
