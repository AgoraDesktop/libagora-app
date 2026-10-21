/*
 * NSRunningApplication.m — an application, as far as the window server can tell.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * THE ORDER EVERY LAZY DOOR TAKES: the identifier is all this object is GIVEN, so the bundle is resolved from it
 * once (Launch Services), and the name, the executable and the icon are read from the bundle once. An application
 * whose bundle is not in the registry still answers: it has an identifier and windows, which is what a Dock tiles
 * it by, and it has no name or icon to show — `localizedName` falls back to the identifier's last component and
 * `icon` is nil, so the tile is anonymous rather than absent.
 */

#import "NSRunningApplication.h"

#import "NSImage.h"
#import "NSWorkspace.h"

#import "AGWindowServer.h"

#import <Foundation/NSBundle.h>
#import <Foundation/NSNumber.h>

#import <LaunchServices/LSInfo.h>

#include <stdio.h>

/* One URL out of a Launch Services array, or nil. The array is +1 from the Copy door and released here.
 *
 * **THE CFURL IS CONVERTED THROUGH ITS STRING**, not cast: Agora's `NSURL` is not Core Foundation's object, and
 * `-[NSURL _cfurl]` — the door Core Foundation would call — aborts on a signature mismatch in this tree. See the
 * note on the same two bridges in `NSWorkspace.m`. */
static NSURL *URLForBundleIdentifier(NSString *identifier)
{
	CFArrayRef urls;
	NSURL *url = nil;

	if (identifier == nil) {
		return nil;
	}
	urls = LSCopyApplicationURLsForBundleIdentifier((CFStringRef)identifier, NULL);
	if (urls != NULL) {
		if (CFArrayGetCount(urls) > 0) {
			CFStringRef string = CFURLGetString((CFURLRef)CFArrayGetValueAtIndex(urls, 0));

			if (string != NULL) {
				url = [(NSURL *)[NSURL URLWithString:(NSString *)string] retain];
			}
		}
		CFRelease(urls);
	}
	return [url autorelease];
}

@implementation NSRunningApplication

- (id)cg_initWithBundleIdentifier:(NSString *)identifier
{
	if ((self = [super init]) != nil) {
		_bundleIdentifier = [identifier copy];
		_windowIDs = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_bundleIdentifier release];
	[_windowIDs release];
	[_bundleURL release];
	[_localizedName release];
	[_icon release];
	[super dealloc];
}

/* **TWO APPLICATIONS ARE THE SAME APPLICATION WHEN THEIR IDENTIFIERS ARE.** Apple compares running applications by
 * process, which is the stronger identity a pid gives it; here the identifier is the only one there is, and it is
 * the one a Dock groups by. A terminated object and a live one with the same identifier are NOT equal, so a
 * notification about "the old instance" cannot be mistaken for the new one. */
- (BOOL)isEqual:(id)other
{
	if (other == self) {
		return YES;
	}
	if (![other isKindOfClass:[NSRunningApplication class]]) {
		return NO;
	}
	if (_terminated != [(NSRunningApplication *)other cg_terminatedFlag]) {
		return NO;
	}
	return [_bundleIdentifier isEqualToString:[(NSRunningApplication *)other bundleIdentifier]];
}

- (NSUInteger)hash
{
	return [_bundleIdentifier hash];
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<NSRunningApplication %@%@>", _bundleIdentifier,
		_terminated ? @" (terminated)" : (_active ? @" (active)" : @"")];
}

- (NSString *)bundleIdentifier
{
	return _bundleIdentifier;
}

- (NSURL *)bundleURL
{
	if (_bundleURL == nil) {
		_bundleURL = [URLForBundleIdentifier(_bundleIdentifier) retain];
	}
	return _bundleURL;
}

- (NSString *)localizedName
{
	if (_localizedName == nil) {
		NSURL *url = [self bundleURL];
		NSString *name = nil;

		if (url != nil) {
			NSBundle *bundle = [NSBundle bundleWithPath:[url path]];

			name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
			if (name != nil) {
				[name retain];
			}
		}
		if (name == nil && _bundleIdentifier != nil) {
			/* NO BUNDLE, SO THE IDENTIFIER IS THE NAME: its last component, which is the convention's own name
			 * (`io.github.agoradesktop.workspace` → "workspace"). Anonymous beats invisible. */
			name = [[_bundleIdentifier lastPathComponent] retain];
		}
		_localizedName = name;
	}
	return _localizedName;
}

- (NSURL *)executableURL
{
	NSURL *url = [self bundleURL];
	NSBundle *bundle;
	NSString *path;

	if (url == nil) {
		return nil;
	}
	bundle = [NSBundle bundleWithPath:[url path]];
	path = [bundle executablePath];
	return path != nil ? [NSURL fileURLWithPath:path] : nil;
}

- (NSImage *)icon
{
	if (_icon == nil) {
		NSURL *url = [self bundleURL];

		if (url != nil) {
			_icon = [[[NSWorkspace sharedWorkspace] iconForFile:[url path]] retain];
		}
	}
	return _icon;
}

- (pid_t)processIdentifier
{
	return 0;	/* not published: see the header */
}

- (BOOL)isActive
{
	return _active;
}

- (void)cg_setActive:(BOOL)active
{
	_active = active;
}

- (BOOL)isHidden
{
	return NO;	/* there is no application-level hide in the protocol */
}

- (BOOL)ownsMenuBar
{
	return _active;
}

- (NSApplicationActivationPolicy)activationPolicy
{
	return NSApplicationActivationPolicyRegular;
}

- (BOOL)isTerminated
{
	return _terminated;
}

- (BOOL)cg_terminatedFlag
{
	return _terminated;
}

- (void)cg_setTerminated:(BOOL)terminated
{
	_terminated = terminated;
}

- (BOOL)isFinishedLaunching
{
	return YES;	/* it has at least one window, or it would not be in the list */
}

- (NSDate *)launchDate
{
	return nil;	/* OWED: nothing records when a client connected */
}

- (void)cg_setWindowIDs:(NSArray *)windowIDs
{
	NSMutableArray *copy = [windowIDs mutableCopy];

	[_windowIDs release];
	_windowIDs = copy;
}

- (NSArray *)cg_windowIDs
{
	return _windowIDs;
}

- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options
{
	NSNumber *frontmost;
	unsigned int windowID;

	(void)options;
	if (_terminated || [_windowIDs count] == 0) {
		return NO;
	}
	/* THE LAST WINDOW THE LIST NAMED IS THE FRONTMOST ONE the application owns: the list runs back to front, and
	 * it is rebuilt on every change, so its order is the stacking order the click will act on. */
	frontmost = [_windowIDs lastObject];
	windowID = [frontmost unsignedIntValue];
	if (windowID == 0) {
		return NO;
	}
	AGWindowActivate(AGWindowServerShared(), windowID);
	return YES;
}

- (BOOL)hide
{
	return NO;	/* see the header: hiding is the application's own, and local */
}

- (BOOL)unhide
{
	return NO;
}

- (BOOL)terminate
{
	AGWindowServer *server;
	BOOL asked = NO;

	if (_terminated) {
		return NO;
	}
	server = AGWindowServerShared();
	if (server == NULL) {
		return NO;
	}
	/* **EVERY WINDOW, WHICH IS THE MAC'S ANSWER FOR AN APPLICATION WITHOUT DOCUMENT SEMANTICS.** The application
	 * hears `close` on each and decides; a client that refuses stays open, which is why Force Quit is separate and
	 * why it needs the session. */
	{
		NSUInteger i;

		for (i = 0; i < [_windowIDs count]; i++) {
			AGWindowRequestClose(server, [[_windowIDs objectAtIndex:i] unsignedIntValue]);
			asked = YES;
		}
	}
	return asked;
}

- (BOOL)forceTerminate
{
	return NO;	/* OWED: needs a pid and a process table — the session component's */
}

@end
