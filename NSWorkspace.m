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
#import "AppKitRefusal.h"	/* the shared refusal helper — the refused doors say what they need. */

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

@end
