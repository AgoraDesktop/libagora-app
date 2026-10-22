/*
 * AGCandidateWindow.m — the borderless panel, its list, and the caret it follows.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE PLACEMENT IS ONE SUBTRACTION.** The client answers the caret's rectangle in screen coordinates; the window's
 * content is as tall as the list, so its origin is the caret's x and the caret's y LESS its own height — a panel that
 * hangs under the line rather than over the word. That is the whole of this class's geometry, and it is what the four
 * candidate questions are FOR.
 */
#import "AGCandidateWindow.h"
#import "AGCandidateListView.h"
#import <AppKit/NSTextInput.h>

/* THE AIR BETWEEN THE CARET AND THE PANEL, so the panel is not drawn touching the line. */
static const CGFloat AGCandidateGap = 2.0;

@implementation AGCandidateWindow

- (instancetype)initWithClient:(id <NSTextInput>)client
{
	self = [super initWithContentRect:NSMakeRect(0.0, 0.0, 10.0, 10.0) styleMask:NSBorderlessWindowMask
				  backing:NSBackingStoreBuffered defer:NO];
	if (self != nil) {
		_client = client;	/* borrowed */
		_listView = [[AGCandidateListView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
		[self setContentView:_listView];
	}
	return self;
}

- (void)dealloc
{
	[_listView release];
	[super dealloc];
}

- (id <NSTextInput>)client
{
	return _client;
}

- (AGCandidateListView *)candidateListView
{
	return _listView;
}

/* **WHERE THE PANEL GOES, WHICH IS THE ONE PLACE THE CLIENT'S ANSWER IS READ.** A client that answers nothing (or a
 * window with no client) places the panel at the origin the caller's own coordinates are in, which is the honest
 * answer for a window with nothing to hang under. */
- (NSPoint)cg_placementForSize:(NSSize)size
{
	NSRect caret = NSZeroRect;

	if (_client != nil) {
		caret = [_client firstRectForCharacterRange:[_client markedRange]];
	}
	return NSMakePoint(caret.origin.x, caret.origin.y - size.height - AGCandidateGap);
}

- (void)showCandidates:(NSArray *)candidates selected:(NSInteger)index
{
	NSSize size;

	[_listView setCandidates:candidates];
	[_listView setSelectedIndex:index];
	size = [_listView cg_sizeForCandidates];
	[self setContentSize:size];
	[self setFrameOrigin:[self cg_placementForSize:size]];
	[self orderFrontRegardless];
}

- (void)hideCandidates
{
	[self orderOut:nil];
}

- (NSInteger)selectedIndex
{
	return [_listView selectedIndex];
}

- (void)setSelectedIndex:(NSInteger)index
{
	[_listView setSelectedIndex:index];
}

- (void)invalidatePlacement
{
	NSSize size = [_listView cg_sizeForCandidates];

	[self setFrameOrigin:[self cg_placementForSize:size]];
}

@end
