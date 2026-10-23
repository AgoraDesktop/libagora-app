/*
 * NSWorkspace.h — the application-wide services: what is running, what opens a file, and an item's icon.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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

/* ==================================================================================================================
 * THE LAUNCH OPTIONS — Apple's bits, with Apple's values, and only the ones this tier can act on.
 *
 * **THE ONES THAT NAME A SESSION BEHAVIOUR ARE HERE AND NOT INTERPRETED**, which is `LSOpen.h`'s own position: the
 * launch flags are PASSED THROUGH to the seam, and what the seam cannot do (bring an application to the front, route a
 * document to a running instance, add a login item) is the session's, which this tier has not got. A caller that sets
 * one gets the seam's behaviour rather than a promise.
 * ================================================================================================================ */
typedef NSUInteger NSWorkspaceLaunchOptions;
enum {
	NSWorkspaceLaunchDefault = 0,
	NSWorkspaceLaunchAndPrint = 0x00000002,
	NSWorkspaceLaunchAndDisplayErrors = 0x00000040,
	NSWorkspaceLaunchInhibitingBackgroundOnly = 0x00000080,
	NSWorkspaceLaunchWithoutAddingToRecents = 0x00000100,
	NSWorkspaceLaunchWithoutActivation = 0x00000200,
	NSWorkspaceLaunchAsync = 0x00010000,
	NSWorkspaceLaunchNewInstance = 0x00080000,
	NSWorkspaceLaunchAndHide = 0x00100000,
	NSWorkspaceLaunchAndHideOthers = 0x00200000
};

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

/* **THE MODERN SPELLING OF THE SAME QUESTION, AND THE ONE APPLE KEPT.** `-absolutePathForAppBundleWithIdentifier:`
 * answers a PATH and is deprecated on the Mac; this answers the bundle's `NSURL`, which is what a caller that wants to
 * launch it needs. Both are here because a port uses whichever one it was written against. */
- (nullable NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)identifier;

/* **AN APPLICATION'S FULL PATH, FROM ANY OF THE THREE WAYS A PERSON NAMES ONE**: a bundle identifier (`com.x.y`), a
 * path to a `.app`, or a plain NAME searched for as `<name>.app` in `~/Applications`, `/Applications`,
 * `/Applications/Utilities` and the install prefix's share directory. nil when nothing matches — which for a plain
 * name means the search list has no such bundle, and the header says what that list IS rather than leaving a caller to
 * guess. */
- (nullable NSString *)fullPathForApplication:(NSString *)appName;

/* **THE 10.6 SPELLING OF `-launchApplication:`, AND THE TWO FLAGS IT CARRIES.** `showIcon` and `autolaunch` name Dock
 * and login-item behaviour, neither of which exists in this tier; the call is a launch, and the flags are accepted and
 * ignored, which is stated rather than silently dropped. */
- (nullable NSRunningApplication *)launchApplication:(NSString *)name showIcon:(BOOL)showIcon autolaunch:(BOOL)autolaunch;

/* **THE DOOR APPLE SAYS EVERY LAUNCH FUNNELS THROUGH.** The URL is an application (launched) or an item (opened in its
 * default handler); `options` are the launch flags above, passed to the seam; and `configuration` — Apple's dictionary
 * of launch parameters — has NO COUNTERPART here, so it is accepted and not read, which this header says instead of
 * pretending. `outError` receives a domain-local error when Launch Services refuses. The answer is the running
 * application when this tier can identify one (see `-launchApplication:`: a spawned process is not tracked), else nil.
 */
- (nullable NSRunningApplication *)launchApplicationAtURL:(NSURL *)url
						 options:(NSWorkspaceLaunchOptions)options
					   configuration:(nullable NSDictionary *)configuration
						   error:(NSError * _Nullable * _Nullable)outError;

/* **THE TWO DEPRECATED DICTIONARY DOORS, ANSWERED FROM THE LIVE LIST.** `-launchedApplications` is an array of
 * dictionaries, one per running application, keyed by Apple's own keys (`NSApplicationName`,
 * `NSApplicationPath`, `NSApplicationBundleIdentifier`, `NSApplicationProcessIdentifier`); `-activeApplication` is the
 * same dictionary for the one in front, or an empty one. They are the 10.0 spellings of `-runningApplications` and
 * `-frontmostApplication`, and a port that still asks them gets the same facts rather than a refusal.
 */
- (NSArray *)launchedApplications;
- (NSDictionary *)activeApplication;

/* **AN ITEM'S ICON**, through Icon Services: the raster at the icon's best size, as an `NSImage`. nil when the
 * item cannot be made into a URL at all; an item with no icon of its own still gets its type's generic. */
- (NSImage *)iconForFile:(NSString *)fullPath;
/* The same, for a TYPE (`public.folder`, `public.png`) rather than a file. */
- (NSImage *)iconForFileType:(NSString *)fileType;

/* **AN ICON FOR SEVERAL ITEMS AT ONCE.** Apple composes a stack; this tier answers the FIRST path's icon, because an
 * icon is one image and a stack is a drawing this tier has no composition for. Stated at the door rather than left to
 * be discovered: a caller with three files gets the picture of the first.
 */
- (NSImage *)iconForFiles:(NSArray *)fullPaths;

/* **THE DEPRECATED PAIR ANSWERED FROM THE SAME SEAM.** For an existing file this answers YES and writes the DEFAULT
 * HANDLER's path into `outApp` and the item's type — this tier's type for an item is its path EXTENSION, because there
 * is no UTI database behind it (see the type questions below). For a path that is not there, NO.
 */
- (BOOL)getInfoForFile:(NSString *)fullPath
	   application:(NSString * _Nullable * _Nullable)outApp
		  type:(NSString * _Nullable * _Nullable)outType;

/* ==================================================================================================================
 * WHAT IS REFUSED, AND WHY EACH — the dispositions this slice did not implement.
 *
 * **THE TYPE QUESTIONS NEED A UNIFORM TYPE IDENTIFIER DATABASE**, and this tier has none: Launch Services here maps
 * bundles to the types they claim, and the closest thing it has to a type is a kind string
 * (`LSCopyKindStringForURL`). Answering `-typeOfFile:error:` with an extension dressed as a UTI would be a wrong
 * answer that looks right, so the five doors below REFUSE BY NAME and answer their types' empty values.
 *
 * **AND THE TWO "OPEN WITH" DOORS NEED A LAUNCH SPECIFICATION THE SEAM HAS NOT GOT.** `LSOpenCFURLRef` opens an
 * application or opens an item in its DEFAULT handler; there is no argument that says "this application, this file",
 * and spawning a process from AppKit to fake one would put a second launcher in the tree. `-openURLs:withAppBundleIdentifier:…`
 * is the same gap from the other side — it names the application for a list of URLs.
 *
 * **`-hideOtherApplications:` NEEDS A HIDE VERB THE WINDOW SERVER HAS NOT GOT** — activation and focus are per-surface
 * there, and `NSRunningApplication -hide` already answers NO for the same reason.
 * ================================================================================================================ */
- (nullable NSString *)typeOfFile:(NSString *)absoluteFilePath error:(NSError * _Nullable * _Nullable)outError;
- (BOOL)type:(NSString *)firstTypeName conformsToType:(NSString *)secondTypeName;
- (nullable NSString *)localizedDescriptionForType:(NSString *)typeName;
- (nullable NSString *)preferredFilenameExtensionForType:(NSString *)typeName;
- (BOOL)filenameExtension:(NSString *)filenameExtension isValidForType:(NSString *)typeName;
- (BOOL)openFile:(NSString *)fullPath withApplication:(nullable NSString *)applicationName;
- (BOOL)openFile:(NSString *)fullPath withApplication:(nullable NSString *)applicationName andDeactivate:(BOOL)flag;
- (BOOL)openURLs:(NSArray *)urls
    withAppBundleIdentifier:(nullable NSString *)bundleIdentifier
	       options:(NSWorkspaceLaunchOptions)options
 additionalEventParamDescriptor:(nullable id)descriptor
	  launchIdentifiers:(NSArray * _Nullable * _Nullable)identifiers;
- (void)hideOtherApplications;

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
