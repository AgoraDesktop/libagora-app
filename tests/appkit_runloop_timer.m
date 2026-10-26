/*
 * appkit_runloop_timer — the application's loop delivers what a run loop is for, and then stops when told.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHAT THIS HOLDS UP. `-[NSApplication run]` used to be a 60 Hz pump over the compositor's fd and nothing else: it
 * updated the windows, took the events, and never entered `NSRunLoop`, so `NSTimer` never fired inside an
 * application, `-performSelector:afterDelay:` never ran, a `-performSelectorOnMainThread:` from a worker was never
 * delivered, and the main dispatch queue was never serviced. The loop now gives one run-loop pass per frame
 * (`NSRunLoop` being `CFRunLoopRunInMode`), and this case is the application-level proof of that — the unit-level
 * one is `libagora-base`'s `runloop_cf`.
 *
 * HOW IT ASKS, AND WHY IT NEEDS NO COMPOSITOR. The application object is real and `-run` is the real loop; no window
 * is made, so no display is needed and this case runs everywhere rather than skipping with the window tests. The
 * loop is asked for four different kinds of work, each of which is a different path into the same wait:
 *
 *   * a REPEATING TIMER, which is `CFRunLoopTimer`'s callout and the frame pacing an animation would use;
 *   * a DELAYED PERFORM, which is a one-shot timer nobody calls a timer;
 *   * a PERFORMER FROM ANOTHER THREAD, which is the wake path (the loop is signalled and woken, not polled);
 *   * and `dispatch_async(dispatch_get_main_queue(), ^{…})`, which is the main dispatch queue's port — the thing
 *     that made leaving Core Foundation's loop unrun a correctness hole rather than a performance one.
 *
 * AND ONE NEGATIVE: a timer added for a mode the loop never runs must NOT fire, which is the half of the mode rule
 * that a single-mode implementation gets away with.
 *
 * THE SAFETY TIMER IS PART OF THE TEST. A loop that never delivers anything would otherwise hang the suite, so a
 * five-second one-shot stops the application and records that the real checks below never got their answers.
 */
#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>

#include <dispatch/dispatch.h>

#include <stdio.h>
#include <unistd.h>

static int g_checks;
static int g_failed;

static int g_ticks;
static int g_delayed;
static int g_performed;
static int g_dispatchRan;
static int g_wrongModeFired;
static int g_watchdog;

static void check(int ok, const char *what)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", what);
	} else {
		printf("  [ok]   %s\n", what);
	}
}

@interface Probe : NSObject
- (void)tick:(NSTimer *)timer;
- (void)delayed;
- (void)performed;
- (void)wrongMode:(NSTimer *)timer;
- (void)watchdog:(NSTimer *)timer;
@end

@implementation Probe

- (void)tick:(NSTimer *)timer
{
	(void)timer;
	g_ticks++;
	/* THREE FRAMES OF WORK IS ENOUGH TO PROVE THE PASS, and stopping from inside a timer is the ordinary way an
	 * application ends: the loop is bounded by its slice, so `-stop:` takes effect at the end of this pass. */
	if (g_ticks >= 3) {
		[timer invalidate];
		[NSApp stop:nil];
	}
}

- (void)delayed
{
	g_delayed++;
}

- (void)performed
{
	g_performed++;
}

- (void)wrongMode:(NSTimer *)timer
{
	(void)timer;
	g_wrongModeFired++;
}

- (void)watchdog:(NSTimer *)timer
{
	(void)timer;
	g_watchdog = 1;
	[NSApp stop:nil];
}

@end

/* THE WORKER: a thread that asks the main thread to run something, which is `-performSelectorOnMainThread:`'s real
 * use and the path that needed the loop to be woken rather than polled. */
@interface Worker : NSObject
{
@public
	Probe *probe;
}
@end

@implementation Worker
- (void)run:(id)ignored
{
	(void)ignored;
	usleep(20 * 1000);
	[probe performSelectorOnMainThread:@selector(performed) withObject:nil waitUntilDone:NO];
}
@end

int main(void)
{
	NSApplication *app = [NSApplication sharedApplication];
	Probe *probe = [[Probe alloc] init];
	Worker *worker = [[Worker alloc] init];

	(void)app;
	printf("the application's loop delivers timers, performers and the dispatch main queue\n");

	/* THE WORK, ALL OF IT SCHEDULED BEFORE THE LOOP STARTS, which is how an application's first frame looks. */
	[NSTimer scheduledTimerWithTimeInterval:0.01
					 target:probe
				       selector:@selector(tick:)
				       userInfo:nil
					repeats:YES];
	[probe performSelector:@selector(delayed) withObject:nil afterDelay:0.02];
	[[NSRunLoop currentRunLoop] addTimer:[NSTimer timerWithTimeInterval:0.01
								     target:probe
								   selector:@selector(wrongMode:)
								   userInfo:nil
								    repeats:YES]
				      forMode:@"AGRunLoopModeNeverRun"];
	dispatch_async(dispatch_get_main_queue(), ^{
		g_dispatchRan = 1;
	});
	worker->probe = probe;
	[NSThread detachNewThreadSelector:@selector(run:) toTarget:worker withObject:nil];
	[NSTimer scheduledTimerWithTimeInterval:5.0
					 target:probe
				       selector:@selector(watchdog:)
				       userInfo:nil
					repeats:NO];

	[app run];	/* the real loop: this returns when the application is stopped */

	check(g_watchdog == 0, "the loop did not have to be stopped by the watchdog");
	check(g_ticks >= 3, "a repeating timer fired three times inside -[NSApplication run]");
	check(g_delayed == 1, "-performSelector:withObject:afterDelay: ran");
	check(g_performed == 1, "-performSelectorOnMainThread: from a worker thread was delivered");
	check(g_dispatchRan == 1, "dispatch_async(dispatch_get_main_queue(), ^{...}) ran");
	check(g_wrongModeFired == 0, "a timer added for a mode the loop never ran did not fire");
	check(![app isRunning], "-run returned after -stop:");

	[probe release];
	[worker release];
	printf("%s (%d check%s)\n", g_failed ? "FAILURES" : "all checks passed", g_checks,
	       (g_checks == 1) ? "" : "s");
	return g_failed ? 1 : 0;
}
