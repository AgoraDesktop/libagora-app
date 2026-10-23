/*
 * NSWorkspace.m — the running applications, what opens a file, and an icon.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE WINDOW LIST IS A SNAPSHOT, SO THIS IS A DIFF.** Every change the compositor sees sends the whole list —
 * `begin`, a row per window, `done` — and `-cg_applyWindowList:count:` is the one place that turns two consecutive
 * snapshots into the three things a caller can react to: an application appeared, an application went away, and
 * the application in front changed. It is deliberately the whole of the model: no window count is published, no
 * per-window object, and no state that a snapshot cannot rebuild.
 *
 * **NOTHING IS ASKED FOR UNTIL SOMEBODY ASKS.** `+sharedWorkspace` only allocates; the window list is requested on
 * the first read of `-runningApplications` (or `-frontmostApplication`), because the snapshot is re-sent on every
 * window change and an application that never asks must not pay for a Dock's bookkeeping.
 */

#import "NSWorkspace.h"

#import "NSImage.h"
#import "NSRunningApplication.h"

#import "AGWindowServer.h"
#import "AppKitRefusal.h"
#import "NSColor.h"
#import <Foundation/NSFileManager.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSNotification.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>	/* the shared refusal helper — the refused doors say what they need. */

#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNumber.h>

/* **AND `NSWindow.h` FOR THE TWO LEVELS THAT TELL AN APPLICATION'S FURNITURE FROM ITS WINDOWS.** A row in the
 * snapshot carries a level, and the difference between Workspace's desktop and a Workspace file window is exactly
 * that number — see `cg_applyWindowList:`'s note on the ordinary band. */
#import <AppKit/NSWindow.h>

#import <LaunchServices/LaunchServices.h>
#import <IconServices/IconServices.h>

#import <CoreGraphics/CGImage.h>

/* ============================================================================================ *
 * THE TWO BRIDGES, AND WHY THEY GO THROUGH THE STRING.                                                    *
 *                                                                                                *
 * Agora's `NSURL` is an Objective-C object with its own storage, and `CFURLRef` is Core           *
 * Foundation's — the tree bridges STRINGS (a `CFStringRef` can be messaged as an `NSString`, which *
 * `WSItemKind` relies on) but a URL is bridged, on paper, by `-[NSURL _cfurl]`. MEASURED: calling  *
 * that door ABORTS with "Calling [NSURL -_cfurl] with incorrect signature" — the method was         *
 * compiled with an opaque `struct __CFURL` and Core Foundation's call site with a complete one — so *
 * passing an `NSURL` straight into a CF URL API is a segfault in this tree today, not a bridge.    *
 *                                                                                                *
 * These two go the long way round, through the absolute string, which is a real bridge and the one *
 * the two runtimes agree on. THEY ARE A WORKAROUND WITH A NAMED CAUSE: the fix belongs in           *
 * `-[NSURL _cfurl]`'s declaration (libagora-base), and until then every caller that has to cross    *
 * this line writes these two lines rather than casting.                                            *
 * ============================================================================================ */
static CFURLRef CFCreateWithNSURL(NSURL *url)
{
	NSString *string;

	if (url == nil) {
		return NULL;
	}
	string = [url absoluteString];
	return string != nil ? CFURLCreateWithString(NULL, (CFStringRef)string, NULL) : NULL;
}

static NSURL *NSURLFromCFURL(CFURLRef url)
{
	CFStringRef string;

	if (url == NULL) {
		return nil;
	}
	string = CFURLGetString(url);
	return string != NULL ? [NSURL URLWithString:(NSString *)string] : nil;
}

NSString *NSWorkspaceApplicationKey = @"NSWorkspaceApplicationKey";

NSString *NSWorkspaceDidLaunchApplicationNotification = @"NSWorkspaceDidLaunchApplicationNotification";
NSString *NSWorkspaceDidTerminateApplicationNotification = @"NSWorkspaceDidTerminateApplicationNotification";
NSString *NSWorkspaceDidActivateApplicationNotification = @"NSWorkspaceDidActivateApplicationNotification";

/* THE ICON SIZE `-iconForFile:` WHATEVER THE CALLER INTENDS, out of Icon Services' best representation: an NSImage
 * with one raster is what this tree can make (there is no `CGImageDestination` to build a multi-rep `.icns`), and
 * the best size is the one that scales down cleanly in a tile or a list. */
#define WORKSPACE_ICON_POINT_SIZE 128.0

@implementation NSWorkspace

static NSWorkspace *s_shared;

+ (NSWorkspace *)sharedWorkspace
{
	if (s_shared == nil) {
		s_shared = [[NSWorkspace alloc] init];
	}
	return s_shared;
}

- (id)init
{
	if ((self = [super init]) != nil) {
		_runningApplications = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_runningApplications release];
	[_frontmost release];
	[super dealloc];
}

/* ---------------------------------------------------------------------------------------------------
 * the window list
 * --------------------------------------------------------------------------------------------------- */

/* THE C CALLBACK THE SEAM TAKES, forwarding into the object. It runs during the application's dispatch, which is
 * the main thread — the same place a delegate and a notification are called. */
static void fn_window_list(void *context, const AGWindowInfo *rows, int count)
{
	[(NSWorkspace *)context cg_applyWindowList:rows count:count];
}

- (void)cg_startListening
{
	AGWindowServer *server;

	if (_listening) {
		return;
	}
	server = AGWindowServerShared();
	if (server == NULL) {
		return;	/* no compositor: an empty list is the honest answer, and a retry happens on the next ask */
	}
	AGWindowListSetHandler(server, fn_window_list, self);
	_listening = YES;
}

/* **THE DIFF, AND THE ONE ORDER THAT MATTERS: TERMINATIONS BEFORE LAUNCHES.** An application that quits and
 * relaunches can be two snapshots apart, but a snapshot that contains the replacement and not the original would
 * otherwise be read as "still running" and the termination would never be announced. Removing what is gone first
 * gives each identifier a begin and an end. */
- (void)cg_applyWindowList:(const AGWindowInfo *)rows count:(int)count
{
	NSMutableDictionary *byIdentifier = [NSMutableDictionary dictionary];
	NSMutableDictionary *windowsByIdentifier = [NSMutableDictionary dictionary];
	/* **AND THE ONES A PERSON CAN WORK IN, WHICH IS NOT THE SAME SET.** An application's furniture — a desktop, a
	 * menu bar — are its windows too, and the snapshot says which is which by LEVEL rather than by a flag. The
	 * ordinary band is `NSNormalWindowLevel` up to (not including) `NSDockWindowLevel`: everything from a plain
	 * window through panels and floating palettes, and nothing that is a backdrop below them or a bar above them.
	 * That split is what lets a Dock click raise a file window instead of a desktop, and tells it when there is
	 * nothing to raise at all. */
	NSMutableDictionary *ordinaryByIdentifier = [NSMutableDictionary dictionary];
	NSString *active = nil;	/* the IDENTIFIER of the frontmost row, not the object: it is matched as a name */
	BOOL activeSeen = NO;
	int i;
	NSUInteger j;

	for (i = 0; i < count; i++) {
		NSString *identifier = [NSString stringWithUTF8String:rows[i].app_id];
		NSMutableArray *windows;
		BOOL ordinary = (rows[i].level >= NSNormalWindowLevel && rows[i].level < NSDockWindowLevel);

		if ([identifier length] == 0) {
			continue;	/* a window whose application declared no identifier: nothing to group it under */
		}
		windows = [windowsByIdentifier objectForKey:identifier];
		if (windows == nil) {
			windows = [NSMutableArray array];
			[windowsByIdentifier setObject:windows forKey:identifier];
			[byIdentifier setObject:identifier forKey:identifier];
		}
		[windows addObject:[NSNumber numberWithUnsignedInt:rows[i].id]];
		if (ordinary) {
			NSMutableArray *raised = [ordinaryByIdentifier objectForKey:identifier];

			if (raised == nil) {
				raised = [NSMutableArray array];
				[ordinaryByIdentifier setObject:raised forKey:identifier];
			}
			[raised addObject:[NSNumber numberWithUnsignedInt:rows[i].id]];
		}
		/* THE LIST RUNS BACK TO FRONT, so the LAST active row is the frontmost window. */
		if (rows[i].active) {
			activeSeen = YES;
			active = identifier;
		}
	}

	/* ---- 1. what is gone ---------------------------------------------------------------- */
	for (j = 0; j < [_runningApplications count]; ) {
		NSRunningApplication *application = [_runningApplications objectAtIndex:j];
		NSString *identifier = [application bundleIdentifier];

		if ([windowsByIdentifier objectForKey:identifier] == nil) {
			NSDictionary *userInfo;

			[application retain];
			[application cg_setTerminated:YES];
			userInfo = [NSDictionary dictionaryWithObject:application forKey:NSWorkspaceApplicationKey];
			[[NSNotificationCenter defaultCenter] postNotificationName:NSWorkspaceDidTerminateApplicationNotification
									    object:self
									  userInfo:userInfo];
			[_runningApplications removeObjectAtIndex:j];
			[application release];
			continue;
		}
		j++;
	}

	/* ---- 2. what is new, and what is still here ------------------------------------------ */
	for (i = 0; i < count; i++) {
		NSString *identifier = [NSString stringWithUTF8String:rows[i].app_id];
		NSRunningApplication *application = nil;
		NSArray *windows;
		BOOL isActive;

		if ([identifier length] == 0) {
			continue;
		}
		for (j = 0; j < [_runningApplications count]; j++) {
			NSRunningApplication *candidate = [_runningApplications objectAtIndex:j];

			if ([[candidate bundleIdentifier] isEqualToString:identifier]) {
				application = candidate;
				break;
			}
		}
		if (application == nil) {
			NSDictionary *userInfo;

			application = [[NSRunningApplication alloc] cg_initWithBundleIdentifier:identifier];
			[_runningApplications addObject:application];
			[application release];
			userInfo = [NSDictionary dictionaryWithObject:application forKey:NSWorkspaceApplicationKey];
			[[NSNotificationCenter defaultCenter] postNotificationName:NSWorkspaceDidLaunchApplicationNotification
									    object:self
									  userInfo:userInfo];
		}
		/* The FIRST time this identifier is met in this snapshot sets its windows and active flag; a second row
		 * for the same application joins the same array. */
		windows = [windowsByIdentifier objectForKey:identifier];
		if (![[application cg_windowIDs] isEqualToArray:windows]) {
			[application cg_setWindowIDs:windows];
		}
		{
			NSArray *ordinary = [ordinaryByIdentifier objectForKey:identifier];

			if (ordinary == nil) {
				ordinary = [NSArray array];
			}
			if (![[application cg_ordinaryWindowIDs] isEqualToArray:ordinary]) {
				[application cg_setOrdinaryWindowIDs:ordinary];
			}
		}
		isActive = (activeSeen && [active isEqualToString:identifier]);
		[application cg_setActive:isActive];
	}

	/* ---- 3. the application in front, and the notification when it changed ---------------- */
	{
		NSRunningApplication *frontmost = nil;

		if (activeSeen) {
			for (j = 0; j < [_runningApplications count]; j++) {
				NSRunningApplication *candidate = [_runningApplications objectAtIndex:j];

				if ([candidate isActive]) {
					frontmost = candidate;
					break;
				}
			}
		}
		if (frontmost != _frontmost) {
			NSDictionary *userInfo = nil;

			[frontmost retain];
			[_frontmost release];
			_frontmost = frontmost;
			if (frontmost != nil) {
				userInfo = [NSDictionary dictionaryWithObject:frontmost forKey:NSWorkspaceApplicationKey];
			}
			[[NSNotificationCenter defaultCenter] postNotificationName:NSWorkspaceDidActivateApplicationNotification
									    object:self
									  userInfo:userInfo];
		}
	}
}

/* ---------------------------------------------------------------------------------------------------
 * what is running
 * --------------------------------------------------------------------------------------------------- */

- (NSArray *)runningApplications
{
	[self cg_startListening];
	return [[_runningApplications copy] autorelease];
}

- (NSRunningApplication *)frontmostApplication
{
	[self cg_startListening];
	return _frontmost;
}

- (NSRunningApplication *)menuBarOwningApplication
{
	return [self frontmostApplication];
}

/* ---------------------------------------------------------------------------------------------------
 * what opens a file
 * --------------------------------------------------------------------------------------------------- */

- (NSURL *)URLForApplicationToOpenURL:(NSURL *)url
{
	CFURLRef item = CFCreateWithNSURL(url);
	CFURLRef application = NULL;
	NSURL *answer = nil;

	if (item == NULL) {
		return nil;
	}
	if (LSGetApplicationForURL(item, kLSRolesAll, &application) == 0 && application != NULL) {
		answer = NSURLFromCFURL(application);
	}
	if (application != NULL) {
		CFRelease(application);
	}
	CFRelease(item);
	return answer;
}

- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)identifier
{
	CFArrayRef urls;
	NSString *path = nil;

	if (identifier == nil) {
		return nil;
	}
	urls = LSCopyApplicationURLsForBundleIdentifier((CFStringRef)identifier, NULL);
	if (urls != NULL) {
		if (CFArrayGetCount(urls) > 0) {
			path = [NSURLFromCFURL((CFURLRef)CFArrayGetValueAtIndex(urls, 0)) path];
		}
		CFRelease(urls);
	}
	return path;
}

- (BOOL)openURL:(NSURL *)url
{
	CFURLRef item = CFCreateWithNSURL(url);
	OSStatus status;

	if (item == NULL) {
		return NO;
	}
	status = LSOpenCFURLRef(item, NULL);
	CFRelease(item);
	return status == 0;
}

- (BOOL)openFile:(NSString *)fullPath
{
	NSURL *url;

	if (fullPath == nil) {
		return NO;
	}
	url = [NSURL fileURLWithPath:fullPath];
	return url != nil ? [self openURL:url] : NO;
}

- (NSRunningApplication *)launchApplication:(NSString *)name
{
	NSString *path = nil;
	NSURL *url = nil;
	NSUInteger i;

	if (name == nil) {
		return nil;
	}
	/* WHICH NAME IS IT? An identifier when it looks like one, a path when it ends in `.app`, and a plain name is
	 * searched for as an identifier's last component — the Mac's own three readings, in the order that costs the
	 * least to be wrong about. */
	if ([name hasSuffix:@".app"]) {
		path = name;
	} else if ([name rangeOfString:@"."].location != NSNotFound && [name characterAtIndex:0] != '/') {
		path = [self absolutePathForAppBundleWithIdentifier:name];
	}
	if (path == nil) {
		/* A PLAIN NAME, MATCHED AGAINST THE APPLICATIONS THAT ARE RUNNING — which is the only set this tree can
		 * enumerate without an Applications-folder scan. */
		for (i = 0; i < [_runningApplications count]; i++) {
			NSRunningApplication *application = [_runningApplications objectAtIndex:i];

			if ([[application localizedName] isEqualToString:name]
			    || [[[application bundleIdentifier] lastPathComponent] isEqualToString:name]) {
				return application;
			}
		}
		return nil;
	}
	url = [NSURL fileURLWithPath:path];
	if (url == nil || ![self openURL:url]) {
		return nil;
	}
	/* **THE APPLICATION IS SPAWNED, AND THIS DOES NOT PRETEND TO HAVE ITS PROCESS.** It appears in
	 * `-runningApplications` when it maps a window; a caller that wants it then can look it up by identifier. */
	return nil;
}

/* ---------------------------------------------------------------------------------------------------
 * icons
 * --------------------------------------------------------------------------------------------------- */

- (NSImage *)iconForFile:(NSString *)fullPath
{
	NSURL *url;

	if (fullPath == nil) {
		return nil;
	}
	url = [NSURL fileURLWithPath:fullPath];
	if (url == nil) {
		return nil;
	}
	{
		CFURLRef cf = CFCreateWithNSURL(url);
		NSImage *image;

		if (cf == NULL) {
			return nil;
		}
		image = [self cg_imageForIcon:AGIconCreateWithURL(cf)];
		CFRelease(cf);
		return image;
	}
}

- (NSImage *)iconForFileType:(NSString *)fileType
{
	if (fileType == nil) {
		return nil;
	}
	return [self cg_imageForIcon:AGIconCreateWithType((CFStringRef)fileType)];
}

/* ---------------------------------------------------------------------------------------------------
 * the launch verbs
 * --------------------------------------------------------------------------------------------------- */

/* **THE MODERN SPELLING, AND THE PATH DOOR ABOVE IS ITS DEPRECATED TWIN** — Apple deprecated the path answer in this
 * class's favour. Both go through the same Launch Services door, so the two can never disagree about which bundle
 * declares an identifier. */
- (NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)identifier
{
	CFArrayRef urls;
	NSURL *answer = nil;

	if (identifier == nil) {
		return nil;
	}
	urls = LSCopyApplicationURLsForBundleIdentifier((CFStringRef)identifier, NULL);
	if (urls != NULL) {
		if (CFArrayGetCount(urls) > 0) {
			answer = NSURLFromCFURL((CFURLRef)CFArrayGetValueAtIndex(urls, 0));
		}
		CFRelease(urls);
	}
	return answer;
}

/* **THE FOUR PLACES A PLAIN NAME IS LOOKED FOR, IN THIS ORDER, AND THEY ARE WRITTEN DOWN BECAUSE THE LIST IS THE
 * ANSWER.** The first two are Apple's user and local application folders; `Utilities` is inside the second on the Mac
 * and is searched separately so a bundle there is found; and the last is where THIS system installs its own
 * application bundles, which is the only way a freshly built Agora application is findable at all before a package
 * puts it in `/Applications`. */
static NSArray *fn_applicationSearchDirectories(void)
{
	NSString *home = NSHomeDirectory();
	NSString *prefix = [[[NSProcessInfo processInfo] environment] objectForKey:@"AGORA_PREFIX"];
	NSMutableArray *directories = [NSMutableArray array];
	NSString *share;

	if (home != nil) {
		[directories addObject:[home stringByAppendingPathComponent:@"Applications"]];
	}
	[directories addObject:@"/Applications"];
	[directories addObject:@"/Applications/Utilities"];
	share = (prefix != nil) ? prefix : @"/usr/local";
	[directories addObject:[share stringByAppendingPathComponent:@"share/agora/applications"]];
	return directories;
}

- (NSString *)fullPathForApplication:(NSString *)appName
{
	NSString *path = nil;

	if (appName == nil || [appName length] == 0) {
		return nil;
	}
	/* A PATH IS A PATH, and it is answered only when the bundle is really there — a caller passing a stale path gets
	 * nil rather than a path nobody can launch. */
	if ([appName characterAtIndex:0] == '/') {
		return [[NSFileManager defaultManager] fileExistsAtPath:appName] ? appName : nil;
	}
	/* AN IDENTIFIER IS THE SEAM'S QUESTION. A name with a dot and no slash looks like one; the seam decides whether it
	 * is, and a plain NAME with a dot in it is still searched below, so a bundle called `Foo.app` is not lost. */
	if ([appName rangeOfString:@"."].location != NSNotFound) {
		path = [self absolutePathForAppBundleWithIdentifier:appName];
		if (path != nil) {
			return path;
		}
	}
	{
		NSString *bundleName = [appName hasSuffix:@".app"] ? appName : [appName stringByAppendingPathExtension:@"app"];
		NSArray *directories = fn_applicationSearchDirectories();
		NSFileManager *manager = [NSFileManager defaultManager];
		NSUInteger i;

		for (i = 0; i < [directories count]; i++) {
			NSString *candidate = [[directories objectAtIndex:i] stringByAppendingPathComponent:bundleName];

			if ([manager fileExistsAtPath:candidate]) {
				return candidate;
			}
		}
	}
	return nil;
}

/* **THE 10.6 SPELLING, WITH THE TWO FLAGS NAMED AND NOT READ.** `showIcon` is Dock behaviour and `autolaunch` is a
 * login item; neither exists here, and the header says so rather than pretending the launch honoured them. */
- (NSRunningApplication *)launchApplication:(NSString *)name showIcon:(BOOL)showIcon autolaunch:(BOOL)autolaunch
{
	(void)showIcon;
	(void)autolaunch;
	return [self launchApplication:name];
}

/* **THE FUNNEL EVERY LAUNCH GOES THROUGH ON THE MAC, AND THE ONE DOOR THAT TAKES OPTIONS.** The options are the launch
 * flags, passed to the seam, which accepts them and interprets none of the session's half (`LSOpen.h` says so). The
 * configuration dictionary has no counterpart here and is not read. A refusal from Launch Services becomes an NSError
 * in this class's domain, because a caller with an `outError` is entitled to know that the launch did not happen. */
- (NSRunningApplication *)launchApplicationAtURL:(NSURL *)url
					 options:(NSWorkspaceLaunchOptions)options
				   configuration:(NSDictionary *)configuration
					   error:(NSError * _Nullable * _Nullable)outError
{
	CFURLRef item;
	CFArrayRef urls;
	CFArrayRef launched = NULL;
	OSStatus status;
	NSRunningApplication *answer = nil;

	(void)configuration;
	if (outError != NULL) {
		*outError = nil;
	}
	if (url == nil) {
		return nil;
	}
	item = CFCreateWithNSURL(url);
	if (item == NULL) {
		return nil;
	}
	urls = CFArrayCreate(NULL, (const void **)&item, 1, &kCFTypeArrayCallBacks);
	if (urls == NULL) {
		CFRelease(item);
		return nil;
	}
	status = LSOpenURLsWithRole(urls, kLSRolesAll, (LSLaunchFlags)options, &launched);
	CFRelease(urls);
	CFRelease(item);
	if (status != 0) {
		if (outError != NULL) {
			*outError = [NSError errorWithDomain:@"NSWorkspaceErrorDomain" code:(NSInteger)status
						    userInfo:[NSDictionary dictionaryWithObject:
								@"Launch Services could not launch or open this URL"
										      forKey:NSLocalizedDescriptionKey]];
		}
		return nil;
	}
	/* AND THE APPLICATION, WHEN THIS TIER CAN NAME IT: the URL was a bundle that is already running, in which case the
	 * answer is that object. A fresh spawn is not tracked (see `-launchApplication:`), so nil is the honest answer. */
	if ([[url path] hasSuffix:@".app"]) {
		NSString *identifier = [[NSBundle bundleWithPath:[url path]] bundleIdentifier];
		NSUInteger i;

		if (identifier != nil) {
			for (i = 0; i < [_runningApplications count]; i++) {
				NSRunningApplication *candidate = [_runningApplications objectAtIndex:i];

				if ([[candidate bundleIdentifier] isEqualToString:identifier]) {
					answer = candidate;
					break;
				}
			}
		}
	}
	if (launched != NULL) {
		CFRelease(launched);
	}
	return answer;
}

/* ---------------------------------------------------------------------------------------------------
 * the two deprecated dictionary doors
 * --------------------------------------------------------------------------------------------------- */

/* **ONE DICTIONARY PER APPLICATION, KEYED AS APPLE KEYS THEM.** The keys are string literals rather than extern
 * constants because the whole pair is deprecated: a caller that wants these facts asks `-runningApplications`, and the
 * dictionaries exist only so a port that predates that door keeps working. */
static NSDictionary *fn_dictionaryForApplication(NSRunningApplication *application)
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	NSString *value;

	if (application == nil) {
		return dictionary;
	}
	value = [application localizedName];
	if (value != nil) {
		[dictionary setObject:value forKey:@"NSApplicationName"];
	}
	value = [[application bundleURL] path];
	if (value != nil) {
		[dictionary setObject:value forKey:@"NSApplicationPath"];
	}
	value = [application bundleIdentifier];
	if (value != nil) {
		[dictionary setObject:value forKey:@"NSApplicationBundleIdentifier"];
	}
	[dictionary setObject:[NSNumber numberWithInteger:[application processIdentifier]]
		       forKey:@"NSApplicationProcessIdentifier"];
	return dictionary;
}

- (NSArray *)launchedApplications
{
	NSMutableArray *answer = [NSMutableArray array];
	NSUInteger i;

	[self cg_startListening];
	for (i = 0; i < [_runningApplications count]; i++) {
		[answer addObject:fn_dictionaryForApplication([_runningApplications objectAtIndex:i])];
	}
	return answer;
}

- (NSDictionary *)activeApplication
{
	NSRunningApplication *frontmost = [self frontmostApplication];

	return (frontmost != nil) ? fn_dictionaryForApplication(frontmost) : [NSDictionary dictionary];
}

/* ---------------------------------------------------------------------------------------------------
 * an icon for several items, and the deprecated file question
 * --------------------------------------------------------------------------------------------------- */

- (NSImage *)iconForFiles:(NSArray *)fullPaths
{
	/* **THE FIRST PATH'S ICON.** Apple composes a stack of the items' icons; this tier has no composition for one, and a
	 * single picture of the first item is a thinner answer than a stack but a TRUE one — the header states it. */
	if (fullPaths == nil || [fullPaths count] == 0) {
		return nil;
	}
	return [self iconForFile:[fullPaths objectAtIndex:0]];
}

- (BOOL)getInfoForFile:(NSString *)fullPath application:(NSString * _Nullable * _Nullable)outApp type:(NSString * _Nullable * _Nullable)outType
{
	NSURL *url;

	if (fullPath == nil || ![[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
		return NO;
	}
	if (outApp != NULL) {
		NSString *application = nil;

		url = [NSURL fileURLWithPath:fullPath];
		if (url != nil) {
			NSURL *handler = [self URLForApplicationToOpenURL:url];

			application = [handler path];
		}
		*outApp = application;
	}
	if (outType != NULL) {
		/* THE TYPE IS THE EXTENSION, and the header says why: there is no UTI database behind this tier. */
		*outType = [fullPath pathExtension];
	}
	return YES;
}

/* ONE RASTER OUT OF AN `IconRef`, at the size the icon calls its best. The raster is +1 from Icon Services and the
 * `IconRef` is released here — this is the only place either happens, which is why both icon doors share it. */
- (NSImage *)cg_imageForIcon:(IconRef)icon
{
	CGImageRef raster;
	CGSize best;
	NSImage *image;

	if (icon == NULL) {
		return nil;
	}
	best = AGIconGetBestSize(icon);
	if (best.width <= 0.0 || best.height <= 0.0) {
		best = CGSizeMake(WORKSPACE_ICON_POINT_SIZE, WORKSPACE_ICON_POINT_SIZE);
	}
	raster = AGIconCopyImage(icon, best);
	AGIconRelease(icon);
	if (raster == NULL) {
		return nil;
	}
	image = [[NSImage alloc] initWithCGImage:raster size:NSMakeSize(best.width, best.height)];
	CGImageRelease(raster);
	return [image autorelease];
}

/* ==================================================================================================================
 * THE REFUSED DOORS — each answers its type's empty value and says which piece is missing.
 *
 * The header carries the reasons in full; the point of repeating the NAME of the missing piece here is that a caller
 * reading stderr learns it from the door that was called, and a reader of this file sees the disposition next to the
 * body rather than three hundred lines away.
 * ================================================================================================================ */

- (NSString *)typeOfFile:(NSString *)absoluteFilePath error:(NSError * _Nullable * _Nullable)outError
{
	(void)absoluteFilePath;
	if (outError != NULL) {
		*outError = nil;
	}
	fn_refuse_workspace("NSWorkspace -typeOfFile:error:", "a uniform type identifier database");
	return nil;
}

- (BOOL)type:(NSString *)firstTypeName conformsToType:(NSString *)secondTypeName
{
	(void)firstTypeName;
	(void)secondTypeName;
	fn_refuse_workspace("NSWorkspace -type:conformsToType:", "a uniform type identifier database");
	return NO;
}

- (NSString *)localizedDescriptionForType:(NSString *)typeName
{
	(void)typeName;
	fn_refuse_workspace("NSWorkspace -localizedDescriptionForType:", "a uniform type identifier database");
	return nil;
}

- (NSString *)preferredFilenameExtensionForType:(NSString *)typeName
{
	(void)typeName;
	fn_refuse_workspace("NSWorkspace -preferredFilenameExtensionForType:", "a uniform type identifier database");
	return nil;
}

- (BOOL)filenameExtension:(NSString *)filenameExtension isValidForType:(NSString *)typeName
{
	(void)filenameExtension;
	(void)typeName;
	fn_refuse_workspace("NSWorkspace -filenameExtension:isValidForType:", "a uniform type identifier database");
	return NO;
}

- (BOOL)openFile:(NSString *)fullPath withApplication:(NSString *)applicationName
{
	(void)fullPath;
	(void)applicationName;
	fn_refuse_workspace("NSWorkspace -openFile:withApplication:",
			    "a launch specification in LSOpen - the seam opens an application, or an item in its DEFAULT handler");
	return NO;
}

- (BOOL)openFile:(NSString *)fullPath withApplication:(NSString *)applicationName andDeactivate:(BOOL)flag
{
	(void)fullPath;
	(void)applicationName;
	(void)flag;
	fn_refuse_workspace("NSWorkspace -openFile:withApplication:andDeactivate:",
			    "a launch specification in LSOpen - the seam opens an application, or an item in its DEFAULT handler");
	return NO;
}

- (BOOL)openURLs:(NSArray *)urls
    withAppBundleIdentifier:(NSString *)bundleIdentifier
	       options:(NSWorkspaceLaunchOptions)options
 additionalEventParamDescriptor:(id)descriptor
	  launchIdentifiers:(NSArray * _Nullable * _Nullable)identifiers
{
	(void)urls;
	(void)bundleIdentifier;
	(void)options;
	(void)descriptor;
	if (identifiers != NULL) {
		*identifiers = nil;
	}
	fn_refuse_workspace("NSWorkspace -openURLs:withAppBundleIdentifier:options:additionalEventParamDescriptor:launchIdentifiers:",
			    "a launch specification in LSOpen - the seam launches the DEFAULT handler for each URL");
	return NO;
}

- (void)hideOtherApplications
{
	fn_refuse_workspace("NSWorkspace -hideOtherApplications:", "a hide verb in the window server (activation is per-surface)");
}

/* ============================================================================================ *
 * THE FILE OPERATIONS, THE VOLUMES, THE LABELS AND THE CHANGE NOTIFICATIONS                     *
 * ============================================================================================ */

NSString *NSWorkspaceDidPerformFileOperationNotification = @"NSWorkspaceDidPerformFileOperationNotification";

/* THE TRASH DIRECTORY, WHICH THE WORKSPACE'S `WSTrash` USES TOO: the home trash. The Workspace additionally keeps a Put
 * Back record beside the item; this class only moves it, which is the difference stated in the header. */
static NSString *fn_workspace_trash_directory(void)
{
	return [NSHomeDirectory() stringByAppendingPathComponent:@".Trash"];
}

/* **AND THE PER-VOLUME RULE, BECAUSE A RENAME CANNOT CROSS A DEVICE.** MEASURED: recycling from `/tmp` to a home trash on
 * another filesystem failed with `EXDEV`, which is the same fact the Workspace's `WSTrash` documents ("the home volume gets
 * `~/.Trash`; another volume gets `.Trash-<uid>` at its root"). So the item's device picks the trash, and when even that
 * rename fails the item is COPIED and then removed — the same outcome by two syscalls. */
static NSString *fn_trash_directory_for_path(NSString *path)
{
	NSString *home = fn_workspace_trash_directory();
	struct stat item;
	struct stat homeStat;

	if (path == nil || stat([path fileSystemRepresentation], &item) != 0) {
		return home;
	}
	if (stat([NSHomeDirectory() fileSystemRepresentation], &homeStat) == 0 && item.st_dev == homeStat.st_dev) {
		return home;
	}
	{
		/* WALK UP TO THE MOUNT POINT: the first ancestor whose device differs is the root of this one. */
		NSString *directory = [path stringByDeletingLastPathComponent];

		while ([directory length] > 1) {
			NSString *parent = [directory stringByDeletingLastPathComponent];
			struct stat directoryStat;
			struct stat parentStat;

			if (stat([directory fileSystemRepresentation], &directoryStat) != 0
			    || stat([parent fileSystemRepresentation], &parentStat) != 0
			    || directoryStat.st_dev != parentStat.st_dev) {
				return [directory stringByAppendingPathComponent:
					[NSString stringWithFormat:@".Trash-%d", (int)getuid()]];
			}
			directory = parent;
		}
		return [directory stringByAppendingPathComponent:
			[NSString stringWithFormat:@".Trash-%d", (int)getuid()]];
	}
}

/* A NAME THAT IS NOT TAKEN, by appending " copy", " copy 2", … — the rule the file managers here use. */
static NSString *fn_unique_destination(NSString *directory, NSString *name, NSFileManager *manager, BOOL copies)
{
	NSString *candidate;
	NSString *base = [name stringByDeletingPathExtension];
	NSString *extension = [name pathExtension];
	NSUInteger index = 1;

	if (!copies) {
		candidate = [directory stringByAppendingPathComponent:name];
		while ([manager fileExistsAtPath:candidate]) {
			candidate = [directory stringByAppendingPathComponent:
				[NSString stringWithFormat:@"%@ %lu.%@", base, (unsigned long)++index, extension]];
		}
		return candidate;
	}
	candidate = [directory stringByAppendingPathComponent:name];
	while ([manager fileExistsAtPath:candidate]) {
		NSString *suffixed = [NSString stringWithFormat:@"%@ copy", base];

		if (index > 1) {
			suffixed = [NSString stringWithFormat:@"%@ copy %lu", base, (unsigned long)index];
		}
		if ([extension length] > 0) {
			suffixed = [suffixed stringByAppendingPathExtension:extension];
		}
		candidate = [directory stringByAppendingPathComponent:suffixed];
		index++;
	}
	return candidate;
}

- (NSString *)cg_trashDirectory
{
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *trash = fn_workspace_trash_directory();

	(void)manager;
	return trash;
}

/* ONE FILE, ONE OPERATION — the primitive the array doors and the era's verb both go through. */
- (BOOL)cg_performOperation:(NSWorkspaceFileOperation)operation
		      onPath:(NSString *)path
	       destination:(NSString *)destination
		     result:(NSString **)outPath
{
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *target = nil;

	if (path == nil) {
		return NO;
	}
	switch (operation) {
	case NSWorkspaceMoveOperation:
	case NSWorkspaceRecycleOperation:
		{
			NSString *trash = [self cg_trashDirectory];

			if (operation == NSWorkspaceRecycleOperation) {
				trash = fn_trash_directory_for_path(path);
				target = fn_unique_destination(trash, [path lastPathComponent], manager, NO);
				if (![manager fileExistsAtPath:trash]) {
					(void)[manager createDirectoryAtPath:trash withIntermediateDirectories:YES
								 attributes:nil error:NULL];
				}
			} else {
				target = [destination stringByAppendingPathComponent:[path lastPathComponent]];
			}
		}
		if (![manager moveItemAtPath:path toPath:target error:NULL]) {
			/* **A MOVE THAT THE FILE SYSTEM REFUSES IS A COPY AND A REMOVAL** — the one fallback that keeps the door's
			 * promise (the item ends up at the target and is gone from where it was) when a rename cannot cross a
			 * device. */
			if (![manager copyItemAtPath:path toPath:target error:NULL]
			    || ![manager removeItemAtPath:path error:NULL]) {
				return NO;
			}
		}
		break;
	case NSWorkspaceCopyOperation:
	case NSWorkspaceDuplicateOperation:
		target = (operation == NSWorkspaceDuplicateOperation)
			? fn_unique_destination([path stringByDeletingLastPathComponent], [path lastPathComponent],
						manager, YES)
			: [destination stringByAppendingPathComponent:[path lastPathComponent]];
		if (![manager copyItemAtPath:path toPath:target error:NULL]) {
			return NO;
		}
		break;
	case NSWorkspaceLinkOperation:
		target = [destination stringByAppendingPathComponent:[path lastPathComponent]];
		if (symlink([path fileSystemRepresentation], [target fileSystemRepresentation]) != 0) {
			return NO;
		}
		break;
	case NSWorkspaceDestroyOperation:
		if (![manager removeItemAtPath:path error:NULL]) {
			return NO;
		}
		target = path;
		break;
	default:
		fn_refuse_workspace("NSWorkspace -performFileOperation:source:destination:files:tag:",
				    "a compressor, an archiver or an encryptor - compress, decompress, encrypt and decrypt "
				    "need a tool this tier has not got");
		return NO;
	}
	if (outPath != NULL) {
		*outPath = target;
	}
	return YES;
}

/* **THE ERA'S VERB.** `files` are names relative to `source` (or absolute paths); the tag is written for a completion
 * target this tier has not got. The announcement is posted whatever the outcome, because that is what the era's door
 * does — a caller that registered for it learns that an operation happened. */
- (BOOL)performFileOperation:(NSWorkspaceFileOperation)operation
		      source:(NSString *)source
		 destination:(NSString *)destination
		       files:(NSArray *)files
			 tag:(NSInteger *)outTag
{
	BOOL allSucceeded = YES;
	NSUInteger i;

	if (outTag != NULL) {
		*outTag = 0;
	}
	for (i = 0; i < [files count]; i++) {
		NSString *name = [files objectAtIndex:i];
		NSString *path = [name isAbsolutePath] ? name
			: [source stringByAppendingPathComponent:name];

		if (![self cg_performOperation:operation onPath:path destination:destination result:NULL]) {
			allSucceeded = NO;
		}
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:NSWorkspaceDidPerformFileOperationNotification
							    object:self];
	return allSucceeded;
}

/* **THE MODERN PAIR: URLS IN, ONE HANDLER CALL WITH WHAT FAILED.** The handler's dictionary is keyed by the URL that
 * failed and carries its error — Apple's shape — and the answer is the new URLs, in order. A nil handler is legal. */
- (NSArray *)recycleURLs:(NSArray *)URLs completionHandler:(void (^)(NSDictionary *))handler
{
	NSMutableArray *results = [NSMutableArray array];
	NSMutableDictionary *failures = [NSMutableDictionary dictionary];
	NSUInteger i;

	for (i = 0; i < [URLs count]; i++) {
		NSURL *url = [URLs objectAtIndex:i];
		NSString *resultPath = nil;

		if ([self cg_performOperation:NSWorkspaceRecycleOperation onPath:[url path] destination:nil
				       result:&resultPath]) {
			[results addObject:[NSURL fileURLWithPath:resultPath]];
		} else {
			[failures setObject:[NSError errorWithDomain:@"NSWorkspaceErrorDomain" code:1
							   userInfo:[NSDictionary dictionaryWithObject:
									@"the item could not be recycled"
												    forKey:NSLocalizedDescriptionKey]]
				     forKey:url];
		}
	}
	if (handler != nil) {
		handler(failures);
	}
	return results;
}

- (NSArray *)duplicateURLs:(NSArray *)URLs completionHandler:(void (^)(NSDictionary *))handler
{
	NSMutableArray *results = [NSMutableArray array];
	NSMutableDictionary *failures = [NSMutableDictionary dictionary];
	NSUInteger i;

	for (i = 0; i < [URLs count]; i++) {
		NSURL *url = [URLs objectAtIndex:i];
		NSString *resultPath = nil;

		if ([self cg_performOperation:NSWorkspaceDuplicateOperation onPath:[url path] destination:nil
				       result:&resultPath]) {
			[results addObject:[NSURL fileURLWithPath:resultPath]];
		} else {
			[failures setObject:[NSError errorWithDomain:@"NSWorkspaceErrorDomain" code:2
							   userInfo:[NSDictionary dictionaryWithObject:
									@"the item could not be duplicated"
												    forKey:NSLocalizedDescriptionKey]]
				     forKey:url];
		}
	}
	if (handler != nil) {
		handler(failures);
	}
	return results;
}

/* **A TEMPORARY FILE THAT IS REALLY THERE**, with a unique name in the system's temporary directory — what a caller that
 * says "open a scratch file" needs to be able to write into. */
- (NSString *)openTempFile
{
	/* **THE TEMPORARY DIRECTORY MAY NOT EXIST, SO THE DOOR TRIES THE STANDARD ONES IN ORDER.** `NSTemporaryDirectory()`
	 * answers a platform path this tree chooses (`/System/Temporary Files/`, which need not be mounted), so `$TMPDIR`
	 * comes first and `/tmp` last — the first candidate that `mkstemp` accepts is the answer, and the loop is what makes
	 * a missing directory a fallback rather than a nil. */
	NSString *candidates[3];
	NSFileManager *manager = [NSFileManager defaultManager];
	NSUInteger i;
	const char *environment = getenv("TMPDIR");

	candidates[0] = (environment != NULL && environment[0] != '\0')
		? [NSString stringWithUTF8String:environment] : nil;
	candidates[1] = NSTemporaryDirectory();
	candidates[2] = @"/tmp";
	for (i = 0; i < 3; i++) {
		BOOL isDirectory = NO;
		NSString *candidate = candidates[i];
		NSString *template;
		char *buffer;
		int descriptor;

		if ([candidate length] == 0
		    || ![manager fileExistsAtPath:candidate isDirectory:&isDirectory] || !isDirectory) {
			continue;
		}
		template = [candidate stringByAppendingPathComponent:@"agora-XXXXXX"];
		buffer = strdup([template fileSystemRepresentation]);
		if (buffer == NULL) {
			continue;
		}
		descriptor = mkstemp(buffer);
		if (descriptor >= 0) {
			NSString *path;

			close(descriptor);
			path = [NSString stringWithUTF8String:buffer];
			free(buffer);
			return path;
		}
		free(buffer);
	}
	return nil;
}

/* ---- THE VOLUMES, FROM THE ONLY MOUNT TABLE THIS TIER CAN READ --------------------------------- */

/* **`/proc/mounts`, FILTERED TO THE MOUNTS THAT ARE NOT PSEUDO-FILESYSTEMS.** The local volume paths are the mount points
 * whose filesystem is not one of the kernel's synthetic ones, which is what a caller listing "disks" means. */
- (NSArray *)mountedLocalVolumePaths
{
	NSMutableArray *paths = [NSMutableArray array];
	/* **READ WITH STDIO, NOT WITH THE STRING DOOR.** MEASURED: `/proc/mounts` is a symlink to a file whose `stat` size is
	 * zero, so a reader that sizes its buffer from the stat answers an EMPTY string — the door returns 0 bytes and the
	 * volume list comes back empty. A plain read loop has no such assumption, which is what a `/proc` file needs. */
	NSString *table = nil;
	NSArray *lines;
	NSUInteger i;
	{
		FILE *file = fopen("/proc/mounts", "r");
		NSMutableData *data;

		if (file == NULL) {
			return paths;
		}
		data = [NSMutableData data];
		{
			char buffer[4096];
			size_t got;

			while ((got = fread(buffer, 1, sizeof buffer, file)) > 0) {
				[data appendBytes:buffer length:got];
			}
		}
		fclose(file);
		table = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	}
	if (table == nil) {
		return paths;
	}
	lines = [table componentsSeparatedByString:@"\n"];
	for (i = 0; i < [lines count]; i++) {
		NSArray *fields = [[lines objectAtIndex:i] componentsSeparatedByString:@" "];
		NSString *type;

		if ([fields count] < 3) {
			continue;
		}
		type = [fields objectAtIndex:2];
		if ([type isEqualToString:@"proc"] || [type isEqualToString:@"sysfs"] ||
		    [type isEqualToString:@"devtmpfs"] || [type isEqualToString:@"devpts"] ||
		    [type isEqualToString:@"tmpfs"] || [type isEqualToString:@"cgroup"] ||
		    [type isEqualToString:@"cgroup2"] || [type isEqualToString:@"debugfs"] ||
		    [type isEqualToString:@"tracefs"] || [type isEqualToString:@"securityfs"] ||
		    [type isEqualToString:@"pstore"] || [type isEqualToString:@"bpf"] ||
		    [type isEqualToString:@"autofs"] || [type isEqualToString:@"mqueue"] ||
		    [type isEqualToString:@"hugetlbfs"] || [type isEqualToString:@"configfs"] ||
		    [type isEqualToString:@"fusectl"] || [type isEqualToString:@"ramfs"]) {
			continue;
		}
		[paths addObject:[fields objectAtIndex:1]];
	}
	return paths;
}

/* **THE SEVEN LABELS ARE A FIXED, DOCUMENTED SET** — Apple's own colours and names, which are data rather than platform
 * services, so the two doors are real: the ask is "what are the labels", not "what does the Finder show". */
- (NSArray *)fileLabels
{
	return [NSArray arrayWithObjects:@"None", @"Gray", @"Green", @"Purple", @"Blue", @"Yellow", @"Red", @"Orange",
					 nil];
}

- (NSArray *)fileLabelColors
{
	return [NSArray arrayWithObjects:
		[NSColor clearColor],
		[NSColor colorWithCalibratedWhite:0.5 alpha:1.0],
		[NSColor colorWithCalibratedRed:0.0 green:0.7 blue:0.2 alpha:1.0],
		[NSColor colorWithCalibratedRed:0.5 green:0.2 blue:0.7 alpha:1.0],
		[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.9 alpha:1.0],
		[NSColor colorWithCalibratedRed:0.95 green:0.85 blue:0.1 alpha:1.0],
		[NSColor colorWithCalibratedRed:0.9 green:0.2 blue:0.2 alpha:1.0],
		[NSColor colorWithCalibratedRed:0.95 green:0.55 blue:0.1 alpha:1.0],
		nil];
}

/* ---- THE DESKTOP PICTURE: STORED, AND SAID SO --------------------------------------------------- */

- (NSString *)cg_desktopKeyForScreen:(id)screen suffix:(NSString *)suffix
{
	NSInteger number = (screen != nil && [screen respondsToSelector:@selector(cg_screenNumber)])
		? (NSInteger)[screen performSelector:@selector(cg_screenNumber)] : 0;

	return [NSString stringWithFormat:@"NSWorkspaceDesktop%ld%@", (long)number, suffix];
}

- (NSURL *)desktopImageURLForScreen:(id)screen
{
	NSString *path = [[NSUserDefaults standardUserDefaults]
			  objectForKey:[self cg_desktopKeyForScreen:screen suffix:@"URL"]];

	return ([path length] > 0) ? [NSURL fileURLWithPath:path] : nil;
}

- (BOOL)setDesktopImageURL:(NSURL *)url forScreen:(id)screen options:(NSDictionary *)options error:(NSError **)outError
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if (outError != NULL) {
		*outError = nil;
	}
	if (url == nil || ![[url path] length]) {
		return NO;
	}
	[defaults setObject:[url path] forKey:[self cg_desktopKeyForScreen:screen suffix:@"URL"]];
	if (options != nil) {
		[defaults setObject:options forKey:[self cg_desktopKeyForScreen:screen suffix:@"Options"]];
	}
	return YES;
}

- (NSDictionary *)desktopImageOptionsForScreen:(id)screen
{
	return [[NSUserDefaults standardUserDefaults]
		objectForKey:[self cg_desktopKeyForScreen:screen suffix:@"Options"]];
}

/* ---- THE CHANGE NOTIFICATIONS ------------------------------------------------------------------ */

- (NSNotificationCenter *)notificationCenter
{
	return [NSNotificationCenter defaultCenter];
}

/* **A CHANGE IS ANNOUNCED, WHICH IS THE WHOLE OF THE FIVE DOORS.** Apple's pair are the file-operation announcement (with
 * and without a path) and the defaults one is Foundation's own name; the two without the `note` prefix are the older
 * spellings of the same two sends. */
- (void)noteFileSystemChanged
{
	[[NSNotificationCenter defaultCenter] postNotificationName:NSWorkspaceDidPerformFileOperationNotification
							    object:self];
}

- (void)noteFileSystemChanged:(NSString *)path
{
	NSDictionary *userInfo = ([path length] > 0)
		? [NSDictionary dictionaryWithObject:path forKey:@"NSWorkspaceFileOperationPath"] : nil;

	[[NSNotificationCenter defaultCenter] postNotificationName:NSWorkspaceDidPerformFileOperationNotification
							    object:self userInfo:userInfo];
}

- (void)fileSystemChanged
{
	[self noteFileSystemChanged];
}

- (void)noteUserDefaultsChanged
{
	[[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
}

- (void)userDefaultsChanged
{
	[self noteUserDefaultsChanged];
}

/* ---- THE LAUNCH BY IDENTIFIER, AND THE PACKAGE QUESTION ----------------------------------------- */

/* **THE IDENTIFIER BECOMES A BUNDLE, AND THE BUNDLE IS OPENED** — the same path `-launchApplication:` takes once it has
 * resolved a name. There is no launch IDENTIFIER to report (that is a session's handle, and this tier has no session), so
 * the out-parameter is written as 0 and the header says so. */
- (BOOL)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier
			      options:(NSWorkspaceLaunchOptions)options
       additionalEventParamDescriptor:(id)descriptor
		   launchIdentifier:(NSInteger *)launchIdentifier
{
	NSString *path = [self fullPathForApplication:bundleIdentifier];
	NSURL *url;

	(void)options;
	(void)descriptor;
	if (launchIdentifier != NULL) {
		*launchIdentifier = 0;
	}
	if (path == nil) {
		return NO;
	}
	url = [NSURL fileURLWithPath:path];
	return (url != nil) ? [self openURL:url] : NO;
}

/* **A PACKAGE IS A DIRECTORY WITH A `.app`-shaped NAME**, which is this tier's whole notion of one: the extension is what
 * a person sees and what `-getInfoForFile:` reports, so a bundle with a `Contents` directory inside is a package and a
 * plain directory is not. */
- (BOOL)isFilePackageAtPath:(NSString *)fullPath
{
	BOOL isDirectory = NO;
	NSString *extension;

	if (fullPath == nil || ![[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
		return NO;
	}
	if (!isDirectory) {
		return NO;
	}
	extension = [fullPath pathExtension];
	if (![extension isEqualToString:@"app"] && ![extension isEqualToString:@"bundle"] &&
	    ![extension isEqualToString:@"framework"] && ![extension isEqualToString:@"plugin"] &&
	    ![extension isEqualToString:@"kext"]) {
		return NO;
	}
	return [[NSFileManager defaultManager] fileExistsAtPath:
		[fullPath stringByAppendingPathComponent:@"Contents"]];
}

/* ---- AND THE THIRTEEN THAT REFUSE ------------------------------------------------------------------ */

- (BOOL)getFileSystemInfoForPath:(NSString *)fullPath
		     isRemovable:(BOOL *)removableFlag
		      isWritable:(BOOL *)writableFlag
		    isUnmountable:(BOOL *)unmountableFlag
		      description:(NSString **)description
			     type:(NSString **)fileType
{
	(void)fullPath;
	if (removableFlag != NULL) {
		*removableFlag = NO;
	}
	if (writableFlag != NULL) {
		*writableFlag = NO;
	}
	if (unmountableFlag != NULL) {
		*unmountableFlag = NO;
	}
	if (description != NULL) {
		*description = nil;
	}
	if (fileType != NULL) {
		*fileType = nil;
	}
	fn_refuse_workspace("NSWorkspace -getFileSystemInfoForPath:isRemovable:isWritable:isUnmountable:description:type:",
			    "a mount table with device attributes - DiskArbitration");
	return NO;
}

- (NSArray *)mountedRemovableMedia
{
	fn_refuse_workspace("NSWorkspace -mountedRemovableMedia", "a mount table with device attributes - DiskArbitration");
	return [NSArray array];
}

- (BOOL)checkForRemovableMedia
{
	fn_refuse_workspace("NSWorkspace -checkForRemovableMedia", "device discovery - DiskArbitration");
	return NO;
}

- (BOOL)mountNewRemovableMedia
{
	fn_refuse_workspace("NSWorkspace -mountNewRemovableMedia", "device discovery and mounting - DiskArbitration");
	return NO;
}

- (BOOL)unmountAndEjectDeviceAtPath:(NSString *)path
{
	(void)path;
	fn_refuse_workspace("NSWorkspace -unmountAndEjectDeviceAtPath:", "unmounting a device - DiskArbitration");
	return NO;
}

- (BOOL)unmountAndEjectDeviceAtURL:(NSURL *)url error:(NSError **)outError
{
	(void)url;
	if (outError != NULL) {
		*outError = nil;
	}
	fn_refuse_workspace("NSWorkspace -unmountAndEjectDeviceAtURL:error:", "unmounting a device - DiskArbitration");
	return NO;
}

- (BOOL)setIcon:(NSImage *)image forFile:(NSString *)fullPath options:(NSDictionary *)options
{
	(void)image;
	(void)fullPath;
	(void)options;
	fn_refuse_workspace("NSWorkspace -setIcon:forFile:options:", "an icon WRITER - Icon Services here only reads");
	return NO;
}

- (void)findApplications
{
	fn_refuse_workspace("NSWorkspace -findApplications",
			    "an incremental registry rescan - the seam seeds its registry at start (AGLaunchServicesReset "
			    "is the whole of it)");
}

- (void)extendPowerOffBy:(NSInteger)requested
{
	(void)requested;
	fn_refuse_workspace("NSWorkspace -extendPowerOffBy:", "a power manager");
}

- (BOOL)selectFile:(NSString *)fullPath inFileViewerRootedAtPath:(NSString *)rootFullpath
{
	(void)fullPath;
	(void)rootFullpath;
	fn_refuse_workspace("NSWorkspace -selectFile:inFileViewerRootedAtPath:",
			    "a file manager to TELL across processes - the Workspace is this stack's, and there is no "
			    "transport from AppKit to another process yet");
	return NO;
}

- (BOOL)activateFileViewerSelectingURLs:(NSArray *)urls
{
	(void)urls;
	fn_refuse_workspace("NSWorkspace -activateFileViewerSelectingURLs:",
			    "a file manager to TELL across processes - the Workspace is this stack's, and there is no "
			    "transport from AppKit to another process yet");
	return NO;
}

- (BOOL)showSearchResultsForQueryString:(NSString *)queryString
{
	(void)queryString;
	fn_refuse_workspace("NSWorkspace -showSearchResultsForQueryString:",
			    "a file manager's search window, which another process owns");
	return NO;
}

- (BOOL)slideImage:(NSImage *)image from:(NSPoint)fromPoint to:(NSPoint)toPoint
{
	(void)image;
	(void)fromPoint;
	(void)toPoint;
	fn_refuse_workspace("NSWorkspace -slideImage:from:to:", "a compositor animation the window server has not got");
	return NO;
}

- (BOOL)openFile:(NSString *)fullPath fromImage:(NSImage *)anImage at:(NSPoint)point inView:(NSView *)aView
{
	(void)anImage;
	(void)point;
	(void)aView;
	return [self openFile:fullPath];
}

@end
