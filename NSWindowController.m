/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

/* NSWindowController.m — a controller for a window.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 */
#import <AppKit/NSWindowController.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

#include <stdio.h>

/* **THE CASCADE POINT IS REMEMBERED ACROSS CONTROLLERS**, because that is what a cascade IS: the second window
 * opened goes below and right of the first, and a controller that started at the same corner every time would
 * stack every window in one place and call it a cascade. Apple's controller owns this state too. */
static NSPoint s_cascadePoint;
static BOOL s_hasCascadePoint;

/* THE ARCHIVE KEYS ARE OURS, for the reason `NSViewController`'s are: Apple archives a controller beside a NIB and
 * those keys are that format's business. */
static NSString * const FNWindowKey = @"NSWindowControllerWindow";
static NSString * const FNNibNameKey = @"NSWindowControllerNibName";
static NSString * const FNNibPathKey = @"NSWindowControllerNibPath";
static NSString * const FNAutosaveKey = @"NSWindowControllerFrameAutosaveName";

@implementation NSWindowController

- (instancetype)initWithWindow:(NSWindow *)window
{
	self = [super init];
	if (self != nil) {
		[self setWindow:window];
	}
	return self;
}

- (instancetype)initWithWindowNibName:(NSString *)windowNibName
{
	return [self initWithWindowNibName:windowNibName owner:nil];
}

- (instancetype)initWithWindowNibName:(NSString *)windowNibName owner:(id)owner
{
	self = [super init];
	if (self != nil) {
		_windowNibName = [windowNibName copy];
		_owner = owner;	/* BORROWED — see the header */
	}
	return self;
}

- (instancetype)initWithWindowNibPath:(NSString *)windowNibPath owner:(id)owner
{
	self = [super init];
	if (self != nil) {
		_windowNibPath = [windowNibPath copy];
		_owner = owner;
	}
	return self;
}

- (void)dealloc
{
	[_window release];
	[_windowNibName release];
	[_windowNibPath release];
	[_frameAutosaveName release];
	[super dealloc];
}

/* ---- THE TWO METHODS `NSCoding` REQUIRES ------------------------------------------------------ */

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	/* **THE WINDOW IS ENCODED NOW, AND THE GUARD THAT STOOD HERE IS GONE BECAUSE ITS REASON IS GONE.** `NSWindow` is
	 * archivable in this tier (see its coding methods), so a controller's window travels with it — and the archive
	 * carries the window's whole design subtree, which is what makes a window controller a thing a nib can hold. The nil
	 * case still WRITES THE KEY, which is a semantic choice rather than a workaround. */
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_window forKey:FNWindowKey];
	[aCoder encodeObject:_windowNibName forKey:FNNibNameKey];
	[aCoder encodeObject:_windowNibPath forKey:FNNibPathKey];
	[aCoder encodeObject:_frameAutosaveName forKey:FNAutosaveKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self != nil) {
		[self setWindow:[aDecoder decodeObjectForKey:FNWindowKey]];
		_windowNibName = [[aDecoder decodeObjectForKey:FNNibNameKey] retain];
		_windowNibPath = [[aDecoder decodeObjectForKey:FNNibPathKey] retain];
		[self setWindowFrameAutosaveName:[aDecoder decodeObjectForKey:FNAutosaveKey]];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* ---- THE NAMES, THE WINDOW, AND THE LOAD ------------------------------------------------------ */

- (NSString *)windowNibName
{
	return _windowNibName;
}

- (NSString *)windowNibPath
{
	return _windowNibPath;
}

- (id)owner
{
	return _owner;
}

- (void)setWindow:(NSWindow *)window
{
	if (_window == window) {
		return;
	}
	[window retain];
	[_window release];
	_window = window;
	/* **THE AUTOSAVE NAME IS HANDED OVER HERE, WHICH IS THE ONE PIECE OF ORDERING APPLE'S OWN COMMENT NAMES**: a
	 * name set before the window arrived is applied when it does, so a caller does not have to remember to set it
	 * twice. */
	if (_window != nil && _frameAutosaveName != nil) {
		[_window setFrameAutosaveName:_frameAutosaveName];
	}

	/* **AND THE WINDOW IS TOLD WHO ITS CONTROLLER IS, WHICH IS THIS SIDE OF THE LINK.** Apple's `-windowController`
	 * is the controller's business — the controller drives, the window records — and this tier had the window half
	 * missing until now: `-setWindow:` retained the window and stopped there. Both directions are asserted. */
	[_window setWindowController:self];
}

- (NSWindow *)window
{
	/* LOADED ON DEMAND, which is Apple's behaviour: a controller built with a nib name has no window until one is
	 * asked for. */
	if (_window == nil) {
		[self loadWindow];
	}
	return _window;
}

- (BOOL)isWindowLoaded
{
	return _window != nil;
}

- (void)loadWindow
{
	[self windowWillLoad];
	if (_window != nil) {
		[self windowDidLoad];
		return;	/* already loaded: Apple's implementation survives a redundant invocation too */
	}
	/* **A NIB IS REFUSED BY NAME, EXACTLY AS `NSViewController` REFUSES ONE.** Loading it needs `NSNib`, a class
	 * this tier has not got, and a controller that answered with NO window instead would look like one whose nib
	 * held nothing. `-windowDidLoad` is NOT called: nothing was loaded. */
	if (_windowNibName != nil || _windowNibPath != nil) {
		[NSException raise:NSInternalInconsistencyException
			    format:@"-loadWindow: loading `%@` needs NSNib, which this tier does not ship yet — set the "
				   "window with -setWindow: or override -loadWindow",
				   (_windowNibPath != nil) ? _windowNibPath : _windowNibName];
	}
	[NSException raise:NSInternalInconsistencyException
		    format:@"-loadWindow: no window and no nib: set a window with -setWindow: or override -loadWindow"];
}

- (void)windowWillLoad
{
	/* THE OVERRIDE POINT BEFORE THE LOAD, and it does nothing here — Apple's default does nothing either. */
}

- (void)windowDidLoad
{
	/* AND THE ONE AFTER IT. */
}

/* ---- SHOWING AND CLOSING --------------------------------------------------------------------- */

- (void)showWindow:(id)sender
{
	NSWindow *w = [self window];

	if (w == nil) {
		return;
	}
	if (_shouldCascadeWindows) {
		/* THE CASCADE STARTS AT THE WINDOW'S OWN TOP-LEFT AND MOVES DOWN AND RIGHT FROM THERE, remembering where it
		 * got to so the NEXT controller continues the run rather than starting again on top of this one. */
		NSPoint topLeft;

		topLeft = NSMakePoint([w frame].origin.x, [w frame].origin.y + [w frame].size.height);
		if (s_hasCascadePoint) {
			topLeft = s_cascadePoint;
		}
		s_cascadePoint = [w cascadeTopLeftFromPoint:topLeft];
		s_hasCascadePoint = YES;
	}
	[w makeKeyAndOrderFront:sender];
}

- (void)close
{
	/* THE DOCUMENT FIRST, IF THE CONTROLLER OWNS THE CLOSING OF IT — and asked BY SELECTOR, because the document is
	 * an `id` here (see the header) and this tier has no `NSDocument` to declare. */
	if (_shouldCloseDocument && _document != nil && [_document respondsToSelector:@selector(close)]) {
		[_document performSelector:@selector(close)];
	}
	if (_window != nil) {
		[_window close];
	}
}

/* ---- THE AUTOSAVE NAME AND THE CASCADE FLAG --------------------------------------------------- */

- (void)setWindowFrameAutosaveName:(NSString *)name
{
	NSString *old = _frameAutosaveName;

	_frameAutosaveName = [name copy];
	[old release];
	if (_window != nil && _frameAutosaveName != nil) {
		[_window setFrameAutosaveName:_frameAutosaveName];
	}
}

- (NSString *)windowFrameAutosaveName
{
	return _frameAutosaveName;
}

- (void)setShouldCascadeWindows:(BOOL)flag
{
	_shouldCascadeWindows = flag ? YES : NO;
}

- (BOOL)shouldCascadeWindows
{
	return _shouldCascadeWindows;
}

/* ---- THE DOCUMENT RELATIONSHIP ---------------------------------------------------------------- */

- (id)document
{
	return _document;
}

- (void)setDocument:(id)document
{
	/* BORROWED, like the owner: a document owns its window controllers, so a controller that retained its document
	 * would be half of a retain cycle. */
	_document = document;
}

- (void)setDocumentEdited:(BOOL)dirtyFlag
{
	/* **THE WINDOW'S, NOT THE CONTROLLER'S** — the controller is what Apple puts this door on, and what it does is
	 * tell the window, which is where the state lives (and where the ledger keeps the row). */
	[_window setDocumentEdited:dirtyFlag];
}

- (void)setShouldCloseDocument:(BOOL)flag
{
	_shouldCloseDocument = flag ? YES : NO;
}

- (BOOL)shouldCloseDocument
{
	return _shouldCloseDocument;
}

- (void)synchronizeWindowTitleWithDocumentName
{
	/* THE DOCUMENT'S NAME, ASKED BY SELECTOR for the reason `-close` is: the document is an `id` and a document
	 * that has no name is one whose title is left alone rather than blanked. */
	if (_document != nil && [_document respondsToSelector:@selector(displayName)]) {
		id name = [_document performSelector:@selector(displayName)];

		if ([name isKindOfClass:[NSString class]]) {
			[_window setTitle:[self windowTitleForDocumentDisplayName:(NSString *)name]];
		}
	}
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
	/* APPLE'S DEFAULT IS THE NAME ITSELF, which is the whole of this method and the reason it exists: a subclass
	 * adds the application's name, or a suffix, or nothing. */
	return displayName;
}

@end
