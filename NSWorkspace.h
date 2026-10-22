/*
 * NSWorkspace.h — the application-wide services: what is running, what opens a file, and an item's icon.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THIS IS APPKIT'S FACE OVER THREE COMPONENTS, NOT A FOURTH ONE.** Launch Services answers what opens a file and
 * what a bundle is; Icon Services draws the icon; the window server says what is running. `NSWorkspace` is where an
 * application asks all three, and it adds only the things those layers cannot know together: the one live object
 * per running application, and the notifications when that set changes. `WORKSPACE-PLAN.md` says the same thing in
 * one line — *"`NSWorkspace` is adapted, not reimplemented"* — and `COCOA-10.11-SURFACE-PLAN.md` §A6 schedules it
 * as AppKit's, which is why it lives here and not in the file manager.
 *
 * **WHAT "RUNNING" MEANS HERE, STATED AT THE DOOR.** There is no session component and no `launchd`, so the window
 * server's connections are what liveness is: an application with at least one window is running. An application
 * that has closed every window but has not quit is therefore NOT listed, which the Mac would list — a deviation,
 * and the one place a Dock will look wrong until the session lands. `NSRunningApplication.h` carries the rest of
 * the same list.
 *
 * Written from `NSWorkspace.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

@class NSImage;
@class NSRunningApplication;

/* THE ONE KEY IN EVERY NOTIFICATION'S USERINFO: the application the notification is about. */
extern NSString *NSWorkspaceApplicationKey;

/* The three transitions the window list can honestly report. Apple has more (`didMount`, `didWake`, …); those
 * need DiskArbitration and a power source, and neither is here. */
extern NSString *NSWorkspaceDidLaunchApplicationNotification;
extern NSString *NSWorkspaceDidTerminateApplicationNotification;
extern NSString *NSWorkspaceDidActivateApplicationNotification;

@interface NSWorkspace : NSObject
{
@private
	NSMutableArray *_runningApplications;	/* NSRunningApplication, in the order the window list gave them */
	NSRunningApplication *_frontmost;
	BOOL _listening;			/* the window-list handler is installed on the shared connection */
}

+ (NSWorkspace *)sharedWorkspace;

/* **THE APPLICATIONS WITH WINDOWS, ONE OBJECT PER BUNDLE IDENTIFIER**, in stacking order. The list is refreshed
 * when the compositor dispatches — so it is as current as the application's event loop, which is the honest answer
 * for a client of a window server. */
@property (readonly, copy) NSArray *runningApplications;
/* The application whose window has the keyboard; nil when nothing does. */
@property (readonly) NSRunningApplication *frontmostApplication;
/* The same application here, because the menu bar follows the keyboard — one focus, two doors. */
@property (readonly) NSRunningApplication *menuBarOwningApplication;

/* **WHAT OPENS THIS**, through Launch Services: the default handler, or nil when no Agora bundle claims the type. */
- (NSURL *)URLForApplicationToOpenURL:(NSURL *)url;

/* The bundle on disk that declares this identifier, or nil. The path `launchApplication:` accepts. */
- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)identifier;

/* **OPEN, WHICH IS LAUNCH FOR AN APPLICATION AND "OPEN WITH" FOR EVERYTHING ELSE.** YES when a launch happened; NO
 * when Launch Services had no answer — which for a document means no Agora bundle claims its type, and never a
 * foreign application (the registry is Agora's bundles only). */
- (BOOL)openURL:(NSURL *)url;
- (BOOL)openFile:(NSString *)fullPath;

/* **LAUNCH AN APPLICATION BY PATH OR BY IDENTIFIER.** Apple returns the launched `NSRunningApplication`; this
 * returns the one that is ALREADY running when there is one, and nil for a fresh launch — because a spawned
 * process is not tracked here (the session's job) and returning a made-up object would be worse than nil. The
 * application appears in `runningApplications` when it maps its first window. */
- (NSRunningApplication *)launchApplication:(NSString *)name;

/* **AN ITEM'S ICON**, through Icon Services: the raster at the icon's best size, as an `NSImage`. nil when the
 * item cannot be made into a URL at all; an item with no icon of its own still gets its type's generic. */
- (NSImage *)iconForFile:(NSString *)fullPath;
/* The same, for a TYPE (`public.folder`, `public.png`) rather than a file. */
- (NSImage *)iconForFileType:(NSString *)fileType;

@end

/* ============================================================================================ *
 * THE SEAM THE WINDOW LIST COMES IN THROUGH — and a test's way in, which is why it is named     *
 * rather than hidden. `NSWorkspace` installs the handler on the process's shared connection and *
 * hands each snapshot here; a caller never does.                                                *
 * ============================================================================================ */
struct AGWindowInfo;

@interface NSWorkspace (AGORAPrivate)
- (void)cg_applyWindowList:(const struct AGWindowInfo *)rows count:(int)count;
@end
