/*
 * app_terminate_once — an application that is stopping does not stop twice.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A QUIT CAN ARRIVE FROM SEVERAL PLACES AT ONCE.** The menu has a Quit row, a Dock's tile has one, and a shell that
 * groups windows by bundle identifier can ask EVERY window of an application at once — which is what a tile's Quit
 * does now, because one identifier can be two processes (`NSRunningApplication -terminate`). The first request
 * terminates the application; the rest must not make it announce `-applicationWillTerminate:` again, which is an
 * application saving its state once per press.
 *
 * The claim is read from the notification, which is the only place the difference is visible: `-isRunning` answers NO
 * either way, and the process is gone either way.
 */
#import <AppKit/NSApplication.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

@interface AGTerminateCounter : NSObject
{
@public
	int willTerminate;
}
@end

@implementation AGTerminateCounter

- (void)willTerminate:(NSNotification *)note
{
	(void)note;
	willTerminate++;
}

@end

int main(void)
{
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		AGTerminateCounter *counter = [[AGTerminateCounter alloc] init];

		(void)[app finishLaunching];
		[[NSNotificationCenter defaultCenter] addObserver:counter
							 selector:@selector(willTerminate:)
							     name:NSApplicationWillTerminateNotification
							   object:app];
		[app terminate:nil];
		check(counter->willTerminate == 1, "a quit announces that the application is about to terminate");
		check(![app isRunning], "and the application is no longer running");

		/* **THE SECOND ONE IS THE CASE THIS EXISTS FOR.** It arrives from a window of the same application when a
		 * shell asks every window, and it must change nothing. */
		[app terminate:nil];
		[app terminate:nil];
		check(counter->willTerminate == 1,
		      "and a second and third quit announce NOTHING — the application is already stopping");

		[[NSNotificationCenter defaultCenter] removeObserver:counter];
		[app setDelegate:nil];
		[counter release];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
