/*
 * NSDrawer.m — a child window at a parent's edge, the four states, and the size arithmetic between them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE WINDOW IS THE DRAWER, AND THE ARITHMETIC IS THE CLASS.** Everything a caller reads — the content view, the
 * frame, the panel's size — is the child window's; what this file adds is the relationship (a child of the parent), the
 * four-state transition, and the two-axis size rule that turns a content size and two offsets into a frame. Every door
 * below either stores a fact, lays the window out, or announces a transition; there is no second place a frame is
 * computed.
 *
 * **AND THE ANNOUNCEMENTS HAVE TWO FORMS BECAUSE APPLE GIVES THEM TWO.** A notification center observer hears the
 * posted name; a delegate hears the matching method, with the notification as its argument. Both are sent from the same
 * door so a listener cannot be told about a transition the other half missed.
 */
#import <AppKit/NSDrawer.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSString.h>

NSString *NSDrawerWillOpenNotification = @"NSDrawerWillOpenNotification";
NSString *NSDrawerDidOpenNotification = @"NSDrawerDidOpenNotification";
NSString *NSDrawerWillCloseNotification = @"NSDrawerWillCloseNotification";
NSString *NSDrawerDidCloseNotification = @"NSDrawerDidCloseNotification";

/* **THE DEFAULT MAXIMUM IS LARGE RATHER THAN INFINITE.** A clamp against `INFINITY` works, but a caller reading
 * `-maxContentSize` and doing arithmetic on it does not; ten million points is larger than any display this tier
 * targets and behaves like a number. */
static const CGFloat AGDrawerUnbounded = 10000000.0;

/* ============================================================================================
 * THE PARENT'S LIST IS THE WINDOW'S, NOT THIS CLASS'S.
 * ============================================================================================ */
/* **THE LIST OF DRAWERS BELONGS TO `NSWindow`, WHICH ALREADY DECLARES `-drawers`** ("this window's drawers" is the
 * window's answer, not the drawer's). This class therefore asks the parent to add and remove it through the window's
 * own `cg_` doors rather than keeping a second association keyed on the same window — two lists would be two answers
 * to one question. The ownership stays as Apple states it: the parent retains the drawer through that list, and this
 * class's `_parentWindow` is the borrowed half of the relationship.
 *
 * A CLAMP THAT ALSO HANDLES A LIMIT SET THE WRONG WAY ROUND: a maximum below the minimum is the minimum, because a
 * caller's mistaken pair must not produce a negative or reversed size. */
static CGFloat fn_clamp(CGFloat value, CGFloat low, CGFloat high)
{
	CGFloat lo = (high < low) ? high : low;

	if (value < lo) {
		return lo;
	}
	if (value > high) {
		return (high < lo) ? lo : high;
	}
	return value;
}

@implementation NSDrawer

/* ============================================================================================
 * INIT: A WINDOW FROM BIRTH, AND A ZERO-SIZE STANDBY FOR THE PLAIN INITIALISER.
 * ============================================================================================ */
/* **THE DRAWER'S WINDOW EXISTS FROM THE MOMENT THE DRAWER DOES.** Apple's does too, and it is what makes
 * `-setContentView:` meaningful before the first `-open`; the window is borderless and is not ordered in until there is
 * a visible parent to hang it on. */
- (instancetype)initWithContentSize:(NSSize)contentSize preferredEdge:(NSRectEdge)edge
{
	self = [super init];
	if (self != nil) {
		_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, contentSize.width, contentSize.height)
						      styleMask:NSBorderlessWindowMask
							backing:NSBackingStoreBuffered
							  defer:NO];
		_contentSize = contentSize;
		_minContentSize = NSMakeSize(0.0, 0.0);
		_maxContentSize = NSMakeSize(AGDrawerUnbounded, AGDrawerUnbounded);
		_edge = edge;
		_preferredEdge = edge;
		_state = NSDrawerClosedState;
		_leadingOffset = 0.0;
		_trailingOffset = 0.0;
	}
	return self;
}

/* **THE PLAIN INITIALISER IS A ZERO-SIZE DRAWER RATHER THAN A HALF-BUILT ONE.** `NSObject`'s `-init` is reachable, and a
 * drawer without a window would make every following door a nil test; this makes the same object the designated
 * initialiser makes, with no content. */
- (instancetype)init
{
	return [self initWithContentSize:NSZeroSize preferredEdge:NSMinYEdge];
}

- (void)dealloc
{
	/* **THE CHILD LINK IS BROKEN WITHOUT TOUCHING THE PARENT'S DRAWER LIST.** The list retains this drawer, so a drawer
	 * can only be here to be deallocated when the parent itself is going away (the association is released), and in that
	 * case the parent's own child list is already emptied. `-orderOut:` is the safe spelling: it detaches when there is
	 * a parent and hides when there is a server window. */
	[_window orderOut:nil];
	[_window release];
	[super dealloc];
}

/* ---- THE PARENT AND THE CONTENT ---------------------------------------------------------------- */

- (void)setParentWindow:(NSWindow *)parent
{
	NSWindow *old = _parentWindow;

	if (parent == old) {
		return;
	}
	/* **SELF IS RETAINED ACROSS THE MOVE.** Removing this drawer from the OLD parent's list may drop the last reference
	 * to it, and the rest of this method still has to run; the retain is balanced at the last statement, where a
	 * deallocation is harmless. */
	[self retain];
	if (_state == NSDrawerOpenState) {
		[self fn_detachWindow];
	}
	_parentWindow = parent;
	if (parent != nil) {
		[parent cg_addDrawer:self];
	}
	if (old != nil) {
		[old cg_removeDrawer:self];
	}
	if (parent != nil && _state == NSDrawerOpenState) {
		[self fn_attachWindow];
	}
	[self release];
}

- (NSWindow *)parentWindow
{
	return _parentWindow;
}

- (void)setContentView:(NSView *)aView
{
	/* THE WINDOW OWNS THE VIEW and frames it to the window's content rect; the extra layout is for the case where the
	 * drawer is OPEN and the new view must fill the already-computed panel. */
	[_window setContentView:aView];
	if (_state == NSDrawerOpenState) {
		[self fn_layout];
	}
}

- (NSView *)contentView
{
	return [_window contentView];
}

/* ---- THE EDGE AND THE FOUR STATE DOORS --------------------------------------------------------- */

- (void)setPreferredEdge:(NSRectEdge)edge
{
	if (edge == _preferredEdge) {
		return;
	}
	_preferredEdge = edge;
	/* **A CLOSED DRAWER HAS NO POSITION TO PRESERVE, SO ITS EDGE FOLLOWS THE PREFERENCE.** An open one keeps the edge it
	 * was opened on until `-openOnEdge:` moves it; that is the difference between "where it would like to be" and "where
	 * it is". */
	if (_state == NSDrawerClosedState) {
		_edge = edge;
	}
}

- (NSRectEdge)preferredEdge
{
	return _preferredEdge;
}

- (void)open
{
	[self openOnEdge:_preferredEdge];
}

- (void)openOnEdge:(NSRectEdge)edge
{
	/* **THE RE-ENTRANCY GUARD COMES FIRST, BECAUSE THE ANNOUNCEMENT IS THE MIDDLE OF THE TRANSITION.** A delegate's
	 * `-drawerWillOpen:` that called `-close` would otherwise run a close inside an open; while a transition is in
	 * flight both doors answer by doing nothing. */
	if (_cg_inTransition) {
		return;
	}
	if (_state == NSDrawerOpenState) {
		/* ALREADY OPEN: MOVING THE EDGE IS THE WHOLE REQUEST, AND NOTHING WAS OPENED A SECOND TIME. */
		if (_edge != edge) {
			_edge = edge;
			[self fn_layout];
		}
		return;
	}
	if (_state == NSDrawerOpeningState || _state == NSDrawerClosingState) {
		return;
	}
	if (_parentWindow == nil) {
		/* A DRAWER WITH NO PARENT HAS NO FRAME AND NO OWNER; opening it would put a window on the screen that nothing
		 * can move or release. */
		return;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(drawerShouldOpen:)] &&
	    ![_delegate drawerShouldOpen:self]) {
		return;
	}
	_edge = edge;
	_state = NSDrawerOpeningState;
	_cg_inTransition = YES;
	[self fn_announceWillOpen];
	[self fn_attachWindow];
	_state = NSDrawerOpenState;
	[self fn_announceDidOpen];
	_cg_inTransition = NO;
}

- (void)close
{
	if (_cg_inTransition) {
		return;
	}
	if (_state == NSDrawerClosedState || _state == NSDrawerClosingState) {
		return;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(drawerShouldClose:)] &&
	    ![_delegate drawerShouldClose:self]) {
		return;
	}
	_state = NSDrawerClosingState;
	_cg_inTransition = YES;
	[self fn_announceWillClose];
	[self fn_detachWindow];
	_state = NSDrawerClosedState;
	[self fn_announceDidClose];
	_cg_inTransition = NO;
}

- (void)open:(id)sender
{
	(void)sender;
	[self open];
}

- (void)close:(id)sender
{
	(void)sender;
	[self close];
}

- (void)toggle:(id)sender
{
	(void)sender;
	if (_state == NSDrawerClosedState) {
		[self open];
	} else if (_state == NSDrawerOpenState) {
		[self close];
	}
}

- (NSInteger)state
{
	return (NSInteger)_state;
}

- (NSRectEdge)edge
{
	return _edge;
}

/* ---- THE SIZE AND ITS LIMITS -------------------------------------------------------------------- */

- (void)setContentSize:(NSSize)size
{
	/* **PROGRAMMATIC, AND THEREFORE NOT LIMITED BY THE MINIMUM AND MAXIMUM** — Apple's own sentence. The parent clamp
	 * still applies where the frame is computed, because a drawer can never be larger than its parent. */
	_contentSize = size;
	if (_state == NSDrawerOpenState) {
		[self fn_layout];
	}
}

- (NSSize)contentSize
{
	return _contentSize;
}

- (void)setMinContentSize:(NSSize)size
{
	_minContentSize = size;
}

- (NSSize)minContentSize
{
	return _minContentSize;
}

- (void)setMaxContentSize:(NSSize)size
{
	_maxContentSize = size;
}

- (NSSize)maxContentSize
{
	return _maxContentSize;
}

- (void)setLeadingOffset:(CGFloat)offset
{
	_leadingOffset = offset;
	if (_state == NSDrawerOpenState) {
		[self fn_layout];
	}
}

- (CGFloat)leadingOffset
{
	return _leadingOffset;
}

- (void)setTrailingOffset:(CGFloat)offset
{
	_trailingOffset = offset;
	if (_state == NSDrawerOpenState) {
		[self fn_layout];
	}
}

- (CGFloat)trailingOffset
{
	return _trailingOffset;
}

/* **THE USER'S RESIZE: CLAMP, ASK, APPLY.** The order matters and is Apple's: the minimum and maximum are the limits a
 * PERSON may not cross, while the delegate is the review that may choose a different size inside or outside them — so
 * the proposed size is clamped first, and the delegate's answer is used as given. A negative answer is still not a
 * size, so the applied value is clamped at zero per axis; the parent clamp happens at layout, where it always does. */
- (void)cg_resizeContentByUserToSize:(NSSize)size
{
	NSSize proposed;

	proposed.width = fn_clamp(size.width, _minContentSize.width, _maxContentSize.width);
	proposed.height = fn_clamp(size.height, _minContentSize.height, _maxContentSize.height);
	if (_delegate != nil && [_delegate respondsToSelector:@selector(drawerWillResizeContents:toSize:)]) {
		proposed = [_delegate drawerWillResizeContents:self toSize:proposed];
	}
	proposed.width = (proposed.width > 0.0) ? proposed.width : 0.0;
	proposed.height = (proposed.height > 0.0) ? proposed.height : 0.0;
	_contentSize = proposed;
	if (_state == NSDrawerOpenState) {
		[self fn_layout];
	}
}

/* ---- THE DELEGATE ------------------------------------------------------------------------------- */

- (void)setDelegate:(id <NSDrawerDelegate>)anObject
{
	_delegate = anObject;	/* NOT RETAINED, this tree's rule for every delegate */
}

- (id <NSDrawerDelegate>)delegate
{
	return _delegate;
}

/* ============================================================================================
 * THE LAYOUT AND THE CHILD LINK.
 * ============================================================================================ */
/* **THE FRAME IS IN SCREEN COORDINATES, BECAUSE THE CHILD WINDOW'S PARENT IS ANOTHER WINDOW.** A left drawer sits
 * immediately to the LEFT of the parent's frame and a right one immediately to its right; a bottom drawer below it and
 * a top one above. The thickness comes from the content size (clamped to the parent), and the transverse extent is the
 * parent's minus both offsets (clamped to the parent and to zero). */
- (NSRect)fn_frameForEdge:(NSRectEdge)edge
{
	NSRect parentFrame = [_parentWindow frame];
	BOOL vertical = (edge == NSMinXEdge || edge == NSMaxXEdge);
	CGFloat thickness;
	CGFloat transverse;
	CGFloat x;
	CGFloat y;

	if (vertical) {
		thickness = fn_clamp(_contentSize.width, 0.0, NSWidth(parentFrame));
		transverse = fn_clamp(NSHeight(parentFrame) - _leadingOffset - _trailingOffset, 0.0, NSHeight(parentFrame));
		x = (edge == NSMinXEdge) ? (NSMinX(parentFrame) - thickness) : NSMaxX(parentFrame);
		y = NSMinY(parentFrame) + _leadingOffset;
		return NSMakeRect(x, y, thickness, transverse);
	}
	thickness = fn_clamp(_contentSize.height, 0.0, NSHeight(parentFrame));
	transverse = fn_clamp(NSWidth(parentFrame) - _leadingOffset - _trailingOffset, 0.0, NSWidth(parentFrame));
	x = NSMinX(parentFrame) + _leadingOffset;
	y = (edge == NSMinYEdge) ? (NSMinY(parentFrame) - thickness) : NSMaxY(parentFrame);
	return NSMakeRect(x, y, transverse, thickness);
}

/* **THE WINDOW'S FRAME AND ITS CONTENT VIEW'S FRAME ARE SET TOGETHER.** `NSWindow -setFrame:display:` updates the
 * window's geometry but does not resize the content view; a drawer whose content view kept its old frame would draw at
 * the wrong size the moment the panel changed, which is why the two assignments are one door. */
- (void)fn_layout
{
	NSRect frame;
	NSView *content;

	if (_parentWindow == nil) {
		return;
	}
	frame = [self fn_frameForEdge:_edge];
	[_window setFrame:frame display:YES];
	content = [_window contentView];
	if (content != nil) {
		[content setFrame:NSMakeRect(0.0, 0.0, frame.size.width, frame.size.height)];
	}
}

/* **THE LINK IS ATTACHED WITHOUT ORDERING WHEN THE PARENT IS OFF SCREEN.** Relative ordering is a request to a window
 * server; a drawer of a window nobody has shown has no server to ask and no reason to ask, so `NSWindowOut` records the
 * relationship and nothing else. When the parent IS on screen the child is ordered above it and shown. */
- (void)fn_attachWindow
{
	if (_parentWindow == nil) {
		return;
	}
	[self fn_layout];
	if ([_window parentWindow] != _parentWindow) {
		if ([_parentWindow isVisible]) {
			[_parentWindow addChildWindow:_window ordered:NSWindowAbove];
		} else {
			[_parentWindow addChildWindow:_window ordered:NSWindowOut];
		}
	}
	if ([_parentWindow isVisible]) {
		[_window orderFront:nil];
	}
}

/* **`-orderOut:` IS THE DETACH, BY APPLE'S OWN SENTENCE** ("Calling orderOut: on a child window causes the window to be
 * removed from its parent window before being removed"), and it is also the hide. One call therefore does both halves
 * of closing, and the child's back-pointer is cleared by the window class rather than by this one. */
- (void)fn_detachWindow
{
	[_window orderOut:nil];
}

/* ============================================================================================
 * THE FOUR ANNOUNCEMENTS: THE NOTIFICATION FIRST, THE DELEGATE METHOD SECOND, ONE OBJECT BETWEEN THEM.
 * ============================================================================================ */
- (void)fn_announceWillOpen
{
	NSNotification *note = [NSNotification notificationWithName:NSDrawerWillOpenNotification object:self];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(drawerWillOpen:)]) {
		[_delegate drawerWillOpen:note];
	}
}

- (void)fn_announceDidOpen
{
	NSNotification *note = [NSNotification notificationWithName:NSDrawerDidOpenNotification object:self];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(drawerDidOpen:)]) {
		[_delegate drawerDidOpen:note];
	}
}

- (void)fn_announceWillClose
{
	NSNotification *note = [NSNotification notificationWithName:NSDrawerWillCloseNotification object:self];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(drawerWillClose:)]) {
		[_delegate drawerWillClose:note];
	}
}

- (void)fn_announceDidClose
{
	NSNotification *note = [NSNotification notificationWithName:NSDrawerDidCloseNotification object:self];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(drawerDidClose:)]) {
		[_delegate drawerDidClose:note];
	}
}

@end
