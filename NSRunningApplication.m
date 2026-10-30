/*
 * NSRunningApplication.m — an application, as far as the window server can tell.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
#import <Foundation/NSProcessInfo.h>

#import <LaunchServices/LSInfo.h>

#include <stdio.h>
#include <unistd.h>	/* getpid: the one process fact this tier publishes */

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

/* **THE ELF HEADER'S ONE FACT, FOR A PROCESS WITH NO BUNDLE.** See `-executableArchitecture` for why this exists beside
 * `NSBundle -executableArchitectures` rather than instead of it: the codes are FOUNDATION's (this library's 1..5), the
 * machine word is `e_machine` at offset 18, and `e_ident[EI_DATA]` decides the byte order. A file that cannot be read, is
 * not an ELF, or names a machine this layer has no code for answers 0. */
static NSInteger fn_architecture_of_elf(const char *path)
{
	FILE *file;
	unsigned char header[20];
	size_t got;
	unsigned int machine;

	file = fopen(path, "rb");
	if (file == NULL) {
		return 0;
	}
	got = fread(header, 1, sizeof(header), file);
	fclose(file);
	if (got < sizeof(header) || header[0] != 0x7f || header[1] != 'E' || header[2] != 'L' || header[3] != 'F') {
		return 0;
	}
	if (header[5] == 2) {
		machine = ((unsigned int)header[18] << 8) | header[19];
	} else {
		machine = (unsigned int)header[18] | ((unsigned int)header[19] << 8);
	}
	switch (machine) {
	case 3:		return NSBundleExecutableArchitectureI386;	/* EM_386 */
	case 20:	return NSBundleExecutableArchitecturePPC;	/* EM_PPC */
	case 21:	return NSBundleExecutableArchitecturePPC64;	/* EM_PPC64 */
	case 62:	return NSBundleExecutableArchitectureX86_64;	/* EM_X86_64 */
	case 183:	return NSBundleExecutableArchitectureARM64;	/* EM_AARCH64, Foundation's fifth code */
	default:	return 0;
	}
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
	/* SEE THE IVAR: the window server publishes an application's IDENTIFIER and not its process, so an application
	 * discovered that way has no pid. The current application's object has one, because a process always knows its own. */
	return _pid;
}

- (void)cg_setProcessIdentifier:(pid_t)pid
{
	_pid = pid;
}

/* ---- THE CLASS DOORS, AND THE ONE LOOKUP WITH A REAL ANSWER ------------------------------------ */

/* **`+currentApplication` IS THE PROCESS'S OWN APPLICATION, AND IT IS THE SAME OBJECT EVERY TIME.** A caller compares
 * two of these with `==` (Apple's own answer is a singleton), so it is cached. When the workspace's list already holds
 * an entry for this bundle — the ordinary case for an application the compositor has seen — THAT object is answered,
 * so the current application and its Dock tile are one object rather than two that are `-isEqual:`.
 *
 * THE PID IS THE ONE FACT THIS CLASS ADDS OVER A DISCOVERED APPLICATION: `getpid()` is available in any process, so the
 * application that is asking always knows its own. */
+ (NSRunningApplication *)currentApplication
{
	static NSRunningApplication *sCurrent = nil;
	NSString *identifier;

	if (sCurrent != nil) {
		return sCurrent;
	}
	identifier = [[NSBundle mainBundle] bundleIdentifier];
	if (identifier == nil) {
		/* **A PROCESS WITH NO BUNDLE STILL HAS AN APPLICATION.** Apple's `+currentApplication` never answers nil; here a
		 * bare executable (a test, a tool) has no Info.plist to name it, so its PROCESS NAME is the identifier — which is
		 * what the window server would see on a window it declared, and the only name such a process has. */
		identifier = [[NSProcessInfo processInfo] processName];
	}
	if (identifier == nil) {
		return nil;
	}
	{
		NSArray *known = [[NSWorkspace sharedWorkspace] runningApplications];
		NSUInteger i;

		for (i = 0; i < [known count]; i++) {
			NSRunningApplication *candidate = [known objectAtIndex:i];

			if ([[candidate bundleIdentifier] isEqualToString:identifier]) {
				sCurrent = [candidate retain];
				[candidate cg_setProcessIdentifier:getpid()];
				return sCurrent;
			}
		}
	}
	sCurrent = [[NSRunningApplication alloc] cg_initWithBundleIdentifier:identifier];
	[sCurrent cg_setProcessIdentifier:getpid()];
	return sCurrent;
}

/* **AND THE LOOKUP BY PID ANSWERS FOR EVERY PID THIS TIER CAN SEE, WHICH IS ONE.** See the header: the window server
 * publishes identifiers, not processes, so only the current application carries a pid. A query for a pid nobody
 * published answers nil, which is the true answer to "which application has this pid" from a component that was never
 * told. NO REFUSAL IS PRINTED: a pid that matches nothing is an ordinary nil, not a missing mechanism. */
+ (NSRunningApplication *)runningApplicationWithProcessIdentifier:(pid_t)pid
{
	NSRunningApplication *current = [self currentApplication];

	if (current != nil && pid != 0 && [current processIdentifier] == pid) {
		return current;
	}
	return nil;
}

/* AND THE FILTER IS A FILTER: the workspace's own list, by identifier, in the order the workspace holds it. */
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)bundleIdentifier
{
	NSMutableArray *matching = [NSMutableArray array];
	NSArray *known;
	NSUInteger i;

	if (bundleIdentifier == nil) {
		return matching;
	}
	known = [[NSWorkspace sharedWorkspace] runningApplications];
	for (i = 0; i < [known count]; i++) {
		NSRunningApplication *candidate = [known objectAtIndex:i];

		if ([[candidate bundleIdentifier] isEqualToString:bundleIdentifier]) {
			[matching addObject:candidate];
		}
	}
	return matching;
}

/* **THE ARCHITECTURE IS THE BUNDLE'S OWN ANSWER, WHICH IS ALREADY THE HEADER READ.** `NSBundle -executableArchitectures`
 * opens the executable and maps the ELF's `e_machine` onto the library's five codes — written in `libagora-base`, where the
 * bundle's executable is. So this door is a translation of the APPLICATION into a BUNDLE and of the array's first code into
 * an `NSInteger`; a second ELF parser here would be the same reading twice, and the first version of this method was
 * exactly that (and would have answered Mach-O's numbers rather than this library's). */
- (NSInteger)executableArchitecture
{
	NSURL *url = [self executableURL];
	NSBundle *bundle;
	NSArray *codes;
	NSInteger code = 0;

	/* **AND A PROCESS WITH NO BUNDLE READS ITS OWN EXECUTABLE.** See `+currentApplication`: a bare tool has no bundle
	 * URL to resolve, and the only application this tier can identify that way is the running one, so `/proc/self/exe`
	 * is the file that answers. Any OTHER application without a resolvable bundle answers 0, because there is no path to
	 * read. */
	if (url != nil) {
		bundle = [NSBundle bundleWithPath:[url path]];
		codes = [bundle executableArchitectures];
		if ([codes count] > 0) {
			code = (NSInteger)[[codes objectAtIndex:0] integerValue];
		}
		return code;
	}
	if (self == [[self class] currentApplication]) {
		/* **A BARE PROCESS HAS NO BUNDLE OBJECT TO ASK, SO ITS OWN EXECUTABLE IS READ HERE.** `/proc/self/exe` is the
		 * one path a process always has, and the mapping from `e_machine` to the codes is the SAME mapping
		 * `NSBundle -executableArchitectures` performs — which is a second copy of ten lines, named rather than hidden,
		 * because that door is BUNDLE-shaped and a process without a bundle has no bundle to hand it. The day a
		 * path-based door exists in Foundation, this block is what it replaces. */
		return fn_architecture_of_elf("/proc/self/exe");
	}
	return 0;
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

- (void)cg_setOrdinaryWindowIDs:(NSArray *)windowIDs
{
	NSMutableArray *copy = [windowIDs mutableCopy];

	[_ordinaryWindowIDs release];
	_ordinaryWindowIDs = copy;
}

- (NSArray *)cg_ordinaryWindowIDs
{
	return _ordinaryWindowIDs;
}

- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options
{
	AGWindowServer *server = AGWindowServerShared();
	NSUInteger i;

	if (_terminated || [_windowIDs count] == 0) {
		return NO;
	}
	if ([_ordinaryWindowIDs count] > 0) {
		/* **BACK TO FRONT, WHICH IS THE ORDER THE LIST IS ALREADY IN.** Raising each window in turn puts it at the
		 * front of its level, so raising the BACKMOST first and the frontmost last leaves the application's own
		 * order exactly as it was and puts the whole of it above everybody else. Doing it the other way round is
		 * the same set of windows in reverse — the classic reopened-window-stack bug — and the frontmost is the
		 * one that keeps the keyboard, because it is the one activated last. */
		NSUInteger first = 0;

		if ((options & NSApplicationActivateAllWindows) == 0) {
			first = [_ordinaryWindowIDs count] - 1;	/* just the frontmost, which is the last one the list named */
		}
		for (i = first; i < [_ordinaryWindowIDs count]; i++) {
			AGWindowActivate(server, [[_ordinaryWindowIDs objectAtIndex:i] unsignedIntValue]);
		}
		return YES;
	}
	/* **AN APPLICATION WITH NOTHING TO RAISE IS STILL AN APPLICATION, AND A CLICK ON ITS TILE ACTIVATES IT.** Its only
	 * window may be its MENU BAR — a bar never takes the keyboard from a click, which is what keeps a click on
	 * furniture from moving the keyboard away from the application a person is working in — so the activation is asked
	 * for as a DECISION rather than as a click: `AGWindowServerActivateApplication` is `agora-shell` 13's
	 * `activate_application`, and what it buys is exactly the Mac's answer to this click, the application's menus in
	 * the strip. MEASURED before it existed: a tile click on a running application with no ordinary windows did nothing
	 * at all — no bar, no keyboard, no window.
	 *
	 * AND THE REOPEN ASK STILL FOLLOWS IT, which is the other half of the same click and the older half of this
	 * method: an application that HAS a window to offer (Workspace opening a file window, an editor its open panel)
	 * opens it, and the new window takes the keyboard from the bar it just gave it. An application that does not is
	 * left active with its menus up, which is what "at minimum" means. A compositor older than 13 answers 0 and gets
	 * this door's old behaviour — the reopen alone. */
	(void)AGWindowServerActivateApplication(server, [[_windowIDs lastObject] unsignedIntValue]);
	AGWindowReopen(server, [[_windowIDs lastObject] unsignedIntValue]);
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
	/* **THE APPLICATION IS ASKED, WHICH IS WHAT APPLE'S `-terminate` MEANS AND WHAT A SHELL CAN NOW SAY.** Apple:
	 * "Attempts to terminate the receiver" — the application, through its own termination path, refusing if it must.
	 * The older answer here asked every WINDOW to close and left the rest to the application, which is the same thing
	 * for an application that quits with its last window and nothing at all for one whose windows are furniture
	 * (Workspace's desktop): the desktop closed and the application went on drawing it, so a Dock's Restart could not
	 * work. `AGWindowRequestQuit` is `agora-shell` 12's `quit_window`, and a compositor older than that answers 0 — in
	 * which case the windows are asked instead, which is exactly the behaviour that existed before. */
	if (AGWindowRequestQuit(server, [[_windowIDs lastObject] unsignedIntValue])) {
		return YES;
	}
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
