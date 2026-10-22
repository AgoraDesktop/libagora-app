/*
 * NSOpenPanel — the save panel with the open panel's flags and the deprecated opening forms.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The base class owns the browser, the listing and the accept path; this file is the flags, the two results (`-URLs` and
 * the deprecated `-filenames`) and the 10.3 begin/run forms. The flags are read by the base's accept path, so there is
 * one place a directory is navigated versus chosen.
 */
#import "NSOpenPanel.h"
#import "NSSavePanel_internal.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <stdio.h>

typedef void (*AGOpenPanelDidEndIMP)(id, SEL, id, NSInteger, void *);

@interface NSOpenPanel (AGPrivate)
- (void)cg_configureOpenPanel;
@end

@implementation NSOpenPanel

+ (NSOpenPanel *)openPanel
{
	return [[[NSOpenPanel alloc] init] autorelease];
}

- (void)cg_configureOpenPanel
{
	_isOpenPanel = YES;
	_canChooseFiles = YES;
	_canChooseDirectories = NO;
	_allowsMultipleSelection = NO;
	_resolvesAliases = YES;
	[self setPrompt:@"Open"];
	[self setTitle:@"Open"];
	[self setNameFieldLabel:@"Name:"];
	[_table setAllowsMultipleSelection:NO];
	[self cg_reloadEntries];
}

/* BOTH WAYS IN END IN THE SAME CONFIGURATION: `-init` reaches the designated initialiser through the base, and a caller
 * that uses the designated initialiser directly gets the same open-panel defaults. */
- (instancetype)initWithContentRect:(NSRect)contentRect
			  styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType
			      defer:(BOOL)flag
{
	self = [super initWithContentRect:contentRect styleMask:styleMask backing:bufferingType defer:flag];
	if (self != nil) {
		[self cg_configureOpenPanel];
	}
	return self;
}

- (NSArray *)URLs
{
	if (_urls != nil) {
		return [NSArray arrayWithArray:_urls];
	}
	if (_url != nil) {
		return [NSArray arrayWithObject:_url];
	}
	return [NSArray array];
}

- (NSArray *)filenames
{
	NSArray *urls = [self URLs];
	NSMutableArray *paths = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [urls count]; i++) {
		NSString *path = [[urls objectAtIndex:i] path];

		if (path != nil) {
			[paths addObject:path];
		}
	}
	return paths;
}

- (BOOL)resolvesAliases { return _resolvesAliases; }
- (void)setResolvesAliases:(BOOL)flag { _resolvesAliases = flag; }

- (BOOL)canChooseDirectories { return _canChooseDirectories; }
- (void)setCanChooseDirectories:(BOOL)flag { _canChooseDirectories = flag; }

- (BOOL)allowsMultipleSelection { return _allowsMultipleSelection; }
- (void)setAllowsMultipleSelection:(BOOL)flag
{
	_allowsMultipleSelection = flag;
	[_table setAllowsMultipleSelection:flag];
}

- (BOOL)canChooseFiles { return _canChooseFiles; }
- (void)setCanChooseFiles:(BOOL)flag { _canChooseFiles = flag; }

/* ---- THE 10.3 SPELLINGS --------------------------------------------------------------------------- */

- (void)beginSheetForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)fileTypes
		modalForWindow:(NSWindow *)docWindow modalDelegate:(id)delegate
	       didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	if (fileTypes != nil) {
		[self setAllowedFileTypes:fileTypes];
	}
	[super beginSheetForDirectory:path file:name modalForWindow:docWindow modalDelegate:delegate
		      didEndSelector:didEndSelector contextInfo:contextInfo];
}

- (void)beginForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)fileTypes
	 modelessDelegate:(id)delegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	if (path != nil) {
		[self setDirectory:path];
	}
	if (name != nil) {
		[self setNameFieldStringValue:name];
	}
	if (fileTypes != nil) {
		[self setAllowedFileTypes:fileTypes];
	}
	[self beginWithCompletionHandler:^(NSInteger result) {
		if (delegate != nil && didEndSelector != NULL && [delegate respondsToSelector:didEndSelector]) {
			AGOpenPanelDidEndIMP imp = (AGOpenPanelDidEndIMP)[delegate methodForSelector:didEndSelector];

			imp(delegate, didEndSelector, self, result, contextInfo);
		}
	}];
}

- (NSInteger)runModalForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)fileTypes
{
	if (path != nil) {
		[self setDirectory:path];
	}
	if (name != nil) {
		[self setNameFieldStringValue:name];
	}
	if (fileTypes != nil) {
		[self setAllowedFileTypes:fileTypes];
	}
	return [self runModal];
}

- (NSInteger)runModalForTypes:(NSArray *)fileTypes
{
	if (fileTypes != nil) {
		[self setAllowedFileTypes:fileTypes];
	}
	return [self runModal];
}

@end
