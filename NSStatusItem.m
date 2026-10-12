/*
 * NSStatusItem.m — one item in the status area, and the width is the whole of what its application says.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 */

#import "NSStatusItem.h"
#import "NSStatusBar.h"
#import "NSWindow.h"
#import "NSView.h"

#import <Foundation/NSGeometry.h>

/* The seam door, declared here because this file is where it is CALLED — the same shape `NSWindow.m` uses for the
 * registry door. It is `NSWindow`'s business and not this file's which `AGWindow` an item ends up on. */
@interface NSWindow (AGORAStatusItemPrivate)
- (void)cg_setStatusItemLength:(CGFloat)length;
@end


@implementation NSStatusItem

/* **THE TWO SENTINELS ARE RESOLVED HERE, AND THIS IS THE ONLY PLACE THEY ARE.** The server is never told a
 * sentinel, because only AppKit knows how wide a view wants to be: `NSVariableStatusItemLength` is the view's own
 * width and `NSSquareStatusItemLength` is the bar's thickness. An item with neither a length nor a view has
 * nothing to be wide, so it falls back to a square — visible and honest rather than silently absent. */
- (CGFloat)cg_resolvedLength
{
	CGFloat thickness = [[NSStatusBar systemStatusBar] thickness];

	if (_fLength == NSSquareStatusItemLength) {
		return thickness;
	}
	if (_fLength == NSVariableStatusItemLength) {
		if (_fView != nil) {
			NSRect bounds = [_fView frame];

			if (bounds.size.width > 0.0) {
				return bounds.size.width;
			}
		}
		return thickness;
	}
	return _fLength;
}

/* THE WINDOW, MADE WHEN THERE IS SOMETHING TO PUT IT ON. A status item IS a window — the server places one — and
 * an application draws into it through the item's view. Nothing is made when the bar has no thickness, because
 * that means there is no screen to put an item on and a zero-height window would be a lie about where it is. */
- (BOOL)cg_ensureStatusWindow
{
	CGFloat length, thickness;

	if (_fWindow != nil) {
		return YES;
	}
	thickness = [[NSStatusBar systemStatusBar] thickness];
	if (thickness <= 0.0) {
		return NO;
	}
	length = [self cg_resolvedLength];
	_fWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, length, thickness)
					      styleMask:NSBorderlessWindowMask
						backing:NSBackingStoreBuffered
						  defer:NO];
	if (_fWindow == nil) {
		return NO;
	}
	/* **THE LEVEL IS STILL THE APPLICATION'S.** The server decides WHERE in the strip the item goes and the
	 * application decides how it is ordered against everything else — which is why the two are separate doors and
	 * why the item asks for the status level rather than being given it. */
	[_fWindow setLevel:NSStatusWindowLevel];
	[_fWindow cg_setStatusItemLength:length];
	return YES;
}

- (id)cg_initWithStatusBar:(NSStatusBar *)bar length:(CGFloat)length
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_fStatusBar = bar;
	_fLength = length;
	_fHighlightMode = YES;
	[self cg_ensureStatusWindow];
	return self;
}

- (void)dealloc
{
	[_fWindow release];
	[_fTitle release];
	[_fAttributedTitle release];
	[_fImage release];
	[_fAlternateImage release];
	[_fMenu release];
	[super dealloc];
}

- (NSStatusBar *)statusBar
{
	return _fStatusBar;
}

- (CGFloat)length
{
	return _fLength;
}

/* A LENGTH THE APPLICATION MAY CHANGE AT ANY TIME, sent again when it does: the server packs from the right edge
 * and a width that changed without telling it would leave the items after this one where they no longer belong. */
- (void)setLength:(CGFloat)length
{
	_fLength = length;
	if (_fWindow != nil) {
		[_fWindow cg_setStatusItemLength:(int)[self cg_resolvedLength]];
	}
}

- (SEL)action
{
	return _fAction;
}

- (void)setAction:(SEL)aSelector
{
	_fAction = aSelector;
}

- (SEL)doubleAction
{
	return _fDoubleAction;
}

- (void)setDoubleAction:(SEL)aSelector
{
	_fDoubleAction = aSelector;
}

- (id)target
{
	return _fTarget;
}

- (void)setTarget:(id)anObject
{
	_fTarget = anObject;
}

- (NSString *)title
{
	return _fTitle;
}

- (void)setTitle:(NSString *)aString
{
	NSString *copy = [aString copy];

	[_fTitle release];
	_fTitle = copy;
}

- (NSAttributedString *)attributedTitle
{
	return _fAttributedTitle;
}

- (void)setAttributedTitle:(NSAttributedString *)aString
{
	NSAttributedString *copy = [aString copy];

	[_fAttributedTitle release];
	_fAttributedTitle = copy;
}

- (NSImage *)image
{
	return _fImage;
}

- (void)setImage:(NSImage *)anImage
{
	[anImage retain];
	[_fImage release];
	_fImage = anImage;
}

- (NSImage *)alternateImage
{
	return _fAlternateImage;
}

- (void)setAlternateImage:(NSImage *)anImage
{
	[anImage retain];
	[_fAlternateImage release];
	_fAlternateImage = anImage;
}

- (BOOL)highlightMode
{
	return _fHighlightMode;
}

- (void)setHighlightMode:(BOOL)flag
{
	_fHighlightMode = flag;
}

- (NSMenu *)menu
{
	return _fMenu;
}

- (void)setMenu:(NSMenu *)aMenu
{
	[aMenu retain];
	[_fMenu release];
	_fMenu = aMenu;
}

- (NSView *)view
{
	return _fView;
}

/* **THE VIEW IS THE APPLICATION'S, WHICH IS THE WHOLE POINT OF AN ITEM BEING A CLIENT.** The server owns the strip
 * and places the item; what is DRAWN in it belongs to whoever made it, and setting a view is how that happens. */
- (void)setView:(NSView *)aView
{
	if (![self cg_ensureStatusWindow]) {
		return;
	}
	[aView retain];
	[_fView release];
	_fView = aView;
	if (_fView != nil) {
		[_fWindow setContentView:_fView];
	}
}

- (void)popUpStatusItemMenu:(NSMenu *)aMenu
{
	/* OWED, AND DECLARED RATHER THAN ABSENT: this needs the menu tracking session, which is the same machinery
	 * `NSMenu -popUpContextMenu:` needs and which does not exist here yet. The Mac's answer is that the menu is
	 * tracked by the APPLICATION and not drawn by the server — the same rule as the status area itself. */
	(void)aMenu;
}

- (void)drawStatusBarBackgroundInRect:(NSRect)rect withHighlight:(BOOL)highlight
{
	/* The item's view draws this; it is a call for a view that wants the bar's own background behind it. */
	(void)rect;
	(void)highlight;
}

@end
