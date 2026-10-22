/*
 * NSRunningApplication.h — an application the window server can see is running.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **WHAT THIS CAN HONESTLY BE IN THIS TREE, AND WHAT IT CANNOT.** On the Mac an `NSRunningApplication` is a live
 * Process Manager record: a pid, a launch date, a hidden flag, and a `terminate` that can be escalated to a
 * `SIGKILL`. Agora has no session component yet, so the only liveness there is IS THE WINDOW SERVER'S CONNECTION:
 * a client that is connected has an application, and the windows it owns say which one. That gives a bundle
 * identifier, a bundle on disk, a name, an icon, and "is this the application in front" — honestly — and it does
 * NOT give a pid, a launch date, or a way to kill anything. Each of those doors says so where it stands rather
 * than answering a plausible zero.
 *
 * `NSApplicationActivationOptions` LIVES HERE BECAUSE APPLE PUTS IT HERE. It used to be declared in
 * `NSApplication.h`, with a note that the class that owns it on the Mac had not been declared in this tree. That
 * is now false, so the declaration moved to its owner and `NSApplication.h` points at it.
 *
 * Written from `NSRunningApplication.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#import <AppKit/NSApplication.h>	/* NSApplicationActivationPolicy */

#include <sys/types.h>

@class NSImage;

/* **THE ARCHITECTURE CODES ARE FOUNDATION'S, AND THIS HEADER DOES NOT DECLARE THEM AGAIN.** Apple files them in
 * `NSRunningApplication.h`; in THIS layer they already exist in `NSBundle.h` — where the door that reads the executable's
 * header lives — with THIS LIBRARY'S values (1..5, not Mach-O's cputype words). Declaring a second set here would be two
 * answers to one question, so `-executableArchitecture` below answers one of `NSBundleExecutableArchitecture` and a caller
 * that includes AppKit gets them through Foundation's umbrella, which is how every other cross-framework type works here.
 * (The first version of this header DID declare them, with Mach-O's numbers, and the compiler refused the redefinition —
 * the measurement that found the existing set.) */

/* THE OPTIONS A DOCK'S CLICK PASSES. Apple's bits; this tree can honour the first one and ignores the second,
 * because "ignore other applications" is advice to a window manager that does not arbitrate focus that way. */
enum {
	NSApplicationActivateAllWindows = 1 << 0,
	NSApplicationActivateIgnoringOtherApps = 1 << 1
};
typedef NSUInteger NSApplicationActivationOptions;

@interface NSRunningApplication : NSObject
{
@private
	NSString *_bundleIdentifier;
	NSMutableArray *_windowIDs;	/* NSNumber(unsigned int), the windows this application owns */
	NSMutableArray *_ordinaryWindowIDs;	/* the subset a person can work in — not the desktop, not a bar */
	BOOL _active;
	BOOL _terminated;
	/* Resolved LAZILY and kept, because each of these is a Launch Services query or an icon raster. */
	NSURL *_bundleURL;
	NSString *_localizedName;
	NSImage *_icon;
	/* **AND THE ONE PID THIS TIER CAN TRULY KNOW.** Zero means "not published" — the state every application built from
	 * the window server's list is in, because the server publishes `app_id` and not a process — while the CURRENT
	 * application's object carries `getpid()` from the moment it is made. See the class door on why the lookup by pid
	 * therefore answers for one process. */
	pid_t _pid;
}

/* **THE IDENTIFIER IS THE APPLICATION'S NAME HERE**, because it is the only name the window server publishes: the
 * `app_id` a window declares, which is its bundle identifier (`io.github.agoradesktop.workspace`). Everything else
 * in this class is read from the bundle that identifier resolves to. */
@property (readonly, copy) NSString *bundleIdentifier;
@property (readonly, copy) NSString *localizedName;

/* The bundle on disk, when Launch Services knows one for the identifier; nil when it does not. */
@property (readonly, copy) NSURL *bundleURL;
/* `<bundle>/Contents/MacOS/<CFBundleExecutable>`, from the bundle's own `Info.plist`. */
@property (readonly, copy) NSURL *executableURL;
/* The application's icon, through `NSWorkspace -iconForFile:` — one raster at the icon's best size. */
@property (readonly, copy) NSImage *icon;

/* **ZERO MEANS "NOT PUBLISHED", AND THAT IS A DEVIATION.** The window server knows a client, not a pid, so there is
 * no number to give. A caller that needs one (to signal, to `waitpid`) has the wrong tool until the session
 * component exists — see the header note. */
@property (readonly) pid_t processIdentifier;

/* **AND THE FOUR DOORS THE SWEEP ADDS — THREE THAT ASK, AND ONE THAT ANSWERS nil.** `+currentApplication` is the running
 * application for THIS process (and the pid it carries is the one that is actually known); `+runningApplicationsWithBundleIdentifier:`
 * is a filter over the workspace's list; `+runningApplicationWithProcessIdentifier:` is a lookup BY pid, and THIS TIER
 * PUBLISHES A PID ONLY FOR THE CURRENT PROCESS — a window server says which application owns a window, not which process
 * it is — so a query for any other pid answers nil, which is the true answer to "is there an application with that pid I
 * know of". `-executableArchitecture` asks the BUNDLE, whose `-executableArchitectures` is the door that reads the
 * header. */
+ (nullable NSRunningApplication *)currentApplication;
+ (nullable NSRunningApplication *)runningApplicationWithProcessIdentifier:(pid_t)pid;
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)bundleIdentifier;
- (NSInteger)executableArchitecture;

/* **"IN FRONT" IS "HAS THE KEYBOARD"**, which is the only notion of frontmost this tree has: the window server
 * gives the keyboard to one window, and the application that owns it is the active one. */
@property (readonly, getter=isActive) BOOL active;
/* No application-level hiding exists in the protocol, so nothing is ever hidden — stated rather than guessed. */
@property (readonly, getter=isHidden) BOOL hidden;
/* The application whose window has the menu bar, which here IS the active one: the bar follows the keyboard. */
@property (readonly) BOOL ownsMenuBar;
/* Every Agora application is Regular until Info.plist's `LSUIElement`/`LSBackgroundOnly` is read, which it is not
 * yet; a Dock tile that should not appear is a future distinction, not a guessed one. */
@property (readonly) NSApplicationActivationPolicy activationPolicy;
/* `+items`/`-isTerminated` is YES once the application's last window is gone and the object has been retired. */
@property (readonly, getter=isTerminated) BOOL terminated;
/* An application with a window has finished launching; there is no earlier state to report. */
@property (readonly, getter=isFinishedLaunching) BOOL finishedLaunching;
/* OWED, and nil rather than now: nothing records when a client connected. */
@property (readonly, copy) NSDate *launchDate;

/* **A CLICK ON A DOCK TILE, WHICH IS ONE OF TWO THINGS.** With windows a person can work in, every one of them is
 * raised in its level — BACK TO FRONT, the order the window list already holds, so the click brings the application
 * forward without shuffling its windows. The frontmost also takes the keyboard, which is what makes the application's
 * menu bar follow. With nothing to raise — an application showing only its furniture, which is Workspace whenever its
 * desktop is on the screen and no file window is — the application is ASKED to reopen and decides for itself what
 * that means (`-applicationShouldHandleReopen:hasVisibleWindows:`); Workspace opens a file window. YES when the click
 * did something, NO when the application has no window at all to address the ask to (it has gone away, or never had
 * one). `NSApplicationActivateAllWindows` raises all of them; without it only the frontmost is raised. */
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options;

/* **NO HIDE/UNHIDE, AND THESE ANSWER NO RATHER THAN PRETENDING.** Hiding is `-[NSApplication hide:]` — local to
 * the application, and no part of the protocol lets another client ask for it. */
- (BOOL)hide;
- (BOOL)unhide;

/* **QUIT, WHICH IS A REQUEST AND NOT A KILL.** Every window the application owns is sent `agora_window.close` — the
 * same event its own close button produces — and the application decides. YES when at least one window was asked,
 * NO when there was nothing to ask. */
- (BOOL)terminate;
/* **OWED, BECAUSE IT NEEDS THE SESSION.** A `SIGKILL` needs a pid and a process table; the window server has
 * neither. Answers NO, and the Dock's Force Quit waits for the session component. */
- (BOOL)forceTerminate;

@end

/* ============================================================================================ *
 * THE SEAM `NSWorkspace` USES. NOT APPLE'S, AND NOT FOR CALLERS.                                  *
 *                                                                                                *
 * `NSWorkspace` owns the one live instance per identifier and updates it from the window list;   *
 * these doors are how it does that, and a test's way in. They are declared in the public header  *
 * because this tree's headers are installed as they are (the same shape `NSStatusItem`'s private *
 * category has), not because an application should call them.                                    *
 * ============================================================================================ */
@interface NSRunningApplication (AGORAPrivate)
- (id)cg_initWithBundleIdentifier:(NSString *)identifier;
- (void)cg_setActive:(BOOL)active;
- (void)cg_setWindowIDs:(NSArray *)windowIDs;
- (NSArray *)cg_windowIDs;
/* **AND THE SUBSET A PERSON CAN WORK IN**, which is what a click raises and what "has no window" is measured
 * against. `NSWorkspace` decides which rows are in it, by level; see `cg_applyWindowList:`. */
- (void)cg_setOrdinaryWindowIDs:(NSArray *)windowIDs;
- (NSArray *)cg_ordinaryWindowIDs;
- (BOOL)cg_terminatedFlag;
- (void)cg_setTerminated:(BOOL)terminated;
@end
