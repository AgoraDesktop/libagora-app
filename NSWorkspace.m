/*
 * NSWorkspace.m — the running applications, what opens a file, and an icon.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
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

#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNumber.h>

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
	NSRunningApplication *active = nil;
	BOOL activeSeen = NO;
	int i;
	NSUInteger j;

	for (i = 0; i < count; i++) {
		NSString *identifier = [NSString stringWithUTF8String:rows[i].app_id];
		NSMutableArray *windows;

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

@end
