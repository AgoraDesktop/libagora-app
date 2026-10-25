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
#import <AppKit/NSApplication.h>
#import <AppKit/NSDrawer.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSString.h>

#include <objc/runtime.h>

NSString *NSDrawerWillOpenNotification = @"NSDrawerWillOpenNotification";
NSString *NSDrawerDidOpenNotification = @"NSDrawerDidOpenNotification";
NSString *NSDrawerWillCloseNotification = @"NSDrawerWillCloseNotification";
NSString *NSDrawerDidCloseNotification = @"NSDrawerDidCloseNotification";

/* **THE DEFAULT MAXIMUM IS LARGE RATHER THAN INFINITE.** A clamp against `INFINITY` works, but a caller reading
 * `-maxContentSize` and doing arithmetic on it does not; ten million points is larger than any display this tier
 * targets and behaves like a number. */
static const CGFloat AGDrawerUnbounded = 10000000.0;

/* **THE TUCK, AND THE MARGIN, ARE ONE NUMBER.** A side drawer slides out from UNDER its parent: the edge against the
 * parent is hidden behind it, which is what makes the panel read as part of the window rather than a second window in
 * the same place. The same inset is the least air a drawer leaves above and below itself, so "less than the parent"
 * is a margin a person can see rather than a single clipped point. Apple publishes no such number — its drawers abut
 * — so this is this tier's, stated here and checked by `tests/drawer.m`. */
static const CGFloat AGDrawerInset = 20.0;

/* **AND A DRAWER IS ABOUT FOUR-FIFTHS OF ITS PARENT'S HEIGHT.** The content size's WIDTH is the panel's thickness; the
 * height is this fraction of the parent, centred, because a drawer is a panel beside a window rather than a second
 * window at the same height. The remaining tenth is the air above and below that makes it read as a drawer. */
static const CGFloat AGDrawerHeightFraction = 0.9;

@interface NSWindow (AGDrawerUpdates)
- (void)cg_setDrawerWindow:(BOOL)flag;
- (BOOL)cg_isDrawerWindow;
@end

@interface NSDrawer (AGDrawerParentUpdates)
- (void)cg_parentStateChanged;
- (void)cg_applicationActivityChanged:(NSNotification *)notification;
- (void)fn_layout;
- (void)fn_syncLevel;
- (void)fn_updateVisibility;
- (void)fn_hidePreservingAttachment;
- (BOOL)fn_parentWantsVisibility;
@end

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

/* **THE STRIP OF A SIDE DRAWER THAT SITS UNDER THE PARENT IS EXTRA WIDTH, NOT LOST CONTENT.** The content size names
 * the VISIBLE panel; the window grows by this much on the hidden side, and the content view is inset by the same amount
 * on that side. A tucked edge therefore costs the drawer an empty strip the parent covers, not the first twenty points
 * of whatever it is showing. */
static CGFloat fn_drawer_tuck(CGFloat thickness)
{
	return (thickness < AGDrawerInset) ? thickness : AGDrawerInset;
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
		/* **AND THE WINDOW KNOWS IT IS A DRAWER.** `-orderFront:` is reached by a click inside the drawer too, and a
		 * drawer that raised itself there would be above its parent for the length of the click — the brief flash a
		 * close button produced. The marker lets the window put the parent back on top in the same ordering call. */
		[_window cg_setDrawerWindow:YES];
		_contentSize = contentSize;
		_minContentSize = NSMakeSize(0.0, 0.0);
		_maxContentSize = NSMakeSize(AGDrawerUnbounded, AGDrawerUnbounded);
		_edge = edge;
		_preferredEdge = edge;
		_state = NSDrawerClosedState;
		_leadingOffset = 0.0;
		_trailingOffset = 0.0;
		/* **THE APPLICATION'S ACTIVE STATE IS PART OF "FRONTMOST", AND IT IS NOT A WINDOW NOTIFICATION.** A
		 * deactivated application keeps its key window in this tier (a window owns the keyboard even when the
		 * application is not the frontmost one), so the parent's key flag alone would keep a drawer on the glass over
		 * another application. The two application notifications are what close that gap. */
		[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(cg_applicationActivityChanged:)
			name:NSApplicationDidBecomeActiveNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
			selector:@selector(cg_applicationActivityChanged:)
			name:NSApplicationWillResignActiveNotification object:nil];
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
	[[NSNotificationCenter defaultCenter] removeObserver:self];
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
	} else {
		/* **A CLOSED DRAWER STILL OWNS A WINDOW, AND ITS LEVEL MUST FOLLOW THE PARENT'S.** The panel is not on the
		 * glass, so this changes nothing a person can see; it is what makes the first `-open` land on the right level
		 * even when the parent was raised or lowered while the drawer was shut. */
		[self fn_syncLevel];
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
	/* **THE ATTACH RAN WHILE THE STATE WAS STILL OPENING, AND THE VISIBILITY RULE ASKS FOR OPEN.** Showing the panel
	 * here is the other half of the transition: a parent that is already frontmost, key and active must have its
	 * drawer on the glass the moment `-open` returns, not at the next unrelated notification. */
	[self fn_updateVisibility];
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
/* **THE FRAME IS IN SCREEN COORDINATES, BECAUSE THE CHILD WINDOW'S PARENT IS ANOTHER WINDOW.**
 *
 * A SIDE DRAWER IS A PANEL, NOT A SECOND COPY OF THE WINDOW'S HEIGHT. Its width is the content size's, its height is
 * the content size's height — capped so at least `AGDrawerInset` of the parent shows above and below it — and it is
 * CENTRED on the parent's vertical axis (inside the caller's leading/trailing offsets, which are the inset area the two
 * doors name). THE EDGE AGAINST THE PARENT IS TUCKED UNDER IT by the same inset: a right drawer's left edge begins 20
 * points before the parent's right edge, so the parent's level, one above the drawer's, hides that strip. The result is
 * a panel that reads as sliding out from under the window rather than a separate window butted against it.
 *
 * A TOP OR BOTTOM DRAWER KEEPS THE OLD SPAN: its thickness is the content height (also capped to leave the inset), and
 * its width is the parent's less the two offsets, because a bottom drawer that did not span would not be a bottom
 * drawer. It hangs immediately above or below the parent, as before.
 *
 * THE PARENT CLAMP IS STILL ABSOLUTE, and the inset cap makes "less than the parent" true rather than a clamp that can
 * land exactly on the parent's height. */
- (NSRect)fn_frameForEdge:(NSRectEdge)edge
{
	NSRect parentFrame = [_parentWindow frame];
	BOOL vertical = (edge == NSMinXEdge || edge == NSMaxXEdge);
	CGFloat parentWidth = NSWidth(parentFrame);
	CGFloat parentHeight = NSHeight(parentFrame);
	CGFloat maxPanelHeight = parentHeight - 2.0 * AGDrawerInset;
	CGFloat thickness;
	CGFloat transverse;
	CGFloat x;
	CGFloat y;

	if (maxPanelHeight < 0.0) {
		maxPanelHeight = 0.0;
	}
	if (vertical) {
		CGFloat availableHeight = fn_clamp(parentHeight - _leadingOffset - _trailingOffset, 0.0, parentHeight);
		CGFloat height = parentHeight * AGDrawerHeightFraction;
		CGFloat tuck;

		if (height > availableHeight) {
			height = availableHeight;
		}
		if (height < 0.0) {
			height = 0.0;
		}
		thickness = fn_clamp(_contentSize.width, 0.0, parentWidth);
		tuck = fn_drawer_tuck(thickness);
		/* THE WINDOW IS THE VISIBLE WIDTH PLUS THE TUCK. A right drawer starts one tuck before the parent's right edge
		 * and runs its visible width past it; a left drawer ends one tuck under the parent's left edge. */
		x = (edge == NSMinXEdge) ? (NSMinX(parentFrame) - thickness) : (NSMaxX(parentFrame) - tuck);
		y = NSMinY(parentFrame) + _leadingOffset + (availableHeight - height) / 2.0;
		return NSMakeRect(x, y, thickness + tuck, height);
	}
	thickness = fn_clamp(_contentSize.height, 0.0, parentHeight);
	if (thickness > maxPanelHeight) {
		thickness = maxPanelHeight;
	}
	transverse = fn_clamp(parentWidth - _leadingOffset - _trailingOffset, 0.0, parentWidth);
	x = NSMinX(parentFrame) + _leadingOffset;
	y = (edge == NSMinYEdge) ? (NSMinY(parentFrame) - thickness) : NSMaxY(parentFrame);
	return NSMakeRect(x, y, transverse, thickness);
}

/* **THE DRAWER SHARES ITS PARENT'S LEVEL AND IS THE NEXT LAYER UNDER IT.** A numeric level one lower would be below
 * EVERY window at the parent's level — which is the bug the gallery showed, with the drawer under the Controls window
 * behind the parent. Levels are coarse; the ordering within a level is the layer stack, and this is where the drawer is
 * put under the parent and above the window below it: both windows share a level, the drawer is raised, and the parent
 * is then raised over it. `-cg_raiseForDrawer` is the raise without the ordering path that would re-enter the drawer
 * sync. */
- (void)fn_syncLevel
{
	if (_parentWindow != nil) {
		[_window setLevel:[_parentWindow level]];
	}
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
	[self fn_syncLevel];
	frame = [self fn_frameForEdge:_edge];
	[_window setFrame:frame display:YES];
	content = [_window contentView];
	if (content != nil) {
		CGFloat contentX = 0.0;
		CGFloat contentWidth = frame.size.width;

		/* **THE TUCK IS EMPTY DRAWER BEHIND THE PARENT, NOT A CLIPPED LEFT MARGIN OF THE CONTENT.** A side drawer's
		 * window is wider than the visible panel by the tuck; the content view is placed after that strip on the
		 * parent's side so the visible content is exactly the content size the caller asked for. */
		if (_edge == NSMinXEdge || _edge == NSMaxXEdge) {
			CGFloat thickness = fn_clamp(_contentSize.width, 0.0, NSWidth([_parentWindow frame]));
			CGFloat tuck = fn_drawer_tuck(thickness);

			contentWidth = thickness;
			contentX = (_edge == NSMaxXEdge) ? tuck : 0.0;
		}
		[content setFrame:NSMakeRect(contentX, 0.0, contentWidth, frame.size.height)];
	}
}

/* **THE LINK IS ATTACHED WITHOUT ORDERING, AND THE VISIBILITY RULE IS WHAT SHOWS IT.** `NSWindowOut` records the child
 * relationship and nothing else; the drawer is put on the glass only while its parent is frontmost, key and on screen —
 * see `-fn_parentWantsVisibility`. This replaces the old "attach above and order front whenever the parent is visible",
 * which left a drawer floating over another application's window. */
- (void)fn_attachWindow
{
	if (_parentWindow == nil) {
		return;
	}
	[self fn_layout];
	if ([_window parentWindow] != _parentWindow) {
		[_parentWindow addChildWindow:_window ordered:NSWindowOut];
	}
	[self fn_updateVisibility];
}

/* **`-orderOut:` IS THE DETACH, BY APPLE'S OWN SENTENCE** ("Calling orderOut: on a child window causes the window to be
 * removed from its parent window before being removed"), and it is also the hide. One call therefore does both halves
 * of closing, and the child's back-pointer is cleared by the window class rather than by this one. */
- (void)fn_detachWindow
{
	[_window orderOut:nil];
}

/* **A HIDDEN DRAWER KEEPS ITS CHILD LINK.** `-orderOut:` on a child detaches it (Apple's sentence above), so a drawer
 * that must disappear because its parent lost focus is taken off the glass and then re-attached with `NSWindowOut`:
 * the relationship survives, the pixels do not. Re-adding is the only way to have both with this window class's
 * ordering contract. */
- (void)fn_hidePreservingAttachment
{
	BOOL attached = ([_window parentWindow] == _parentWindow);

	if ([_window isVisible]) {
		[_window orderOut:nil];
	}
	if (attached && _parentWindow != nil) {
		[_parentWindow addChildWindow:_window ordered:NSWindowOut];
	}
}

/* **FRONTMOST, KEY AND ON THE GLASS.** A key window can be a deactivated application's (this tier keeps the key flag
 * across `-deactivate`), and a key window can be ordered out; neither is "frontmost". The composite is therefore the
 * application's active flag, the parent's key flag and the parent's visibility — and all three are re-asked whenever any
 * of them can have changed. */
- (BOOL)fn_parentWantsVisibility
{
	if (_state != NSDrawerOpenState || _parentWindow == nil) {
		return NO;
	}
	if (![_parentWindow isVisible] || ![_parentWindow isKeyWindow]) {
		return NO;
	}
	return [[NSApplication sharedApplication] isActive];
}

- (void)fn_updateVisibility
{
	if (![self fn_parentWantsVisibility]) {
		[self fn_hidePreservingAttachment];
		return;
	}
	if ([_window parentWindow] != _parentWindow) {
		[_parentWindow addChildWindow:_window ordered:NSWindowOut];
	}
	/* **RAISE THE DRAWER, AND LET THE WINDOW PUT THE PARENT BACK OVER IT.** `-orderFront:` on a marked drawer raises it
	 * and then raises the parent in the same call, so the same-level layer is always drawer-under-parent and above every
	 * window below the parent. This runs on EVERY sync, not only on the show, so the pair cannot be left out of order. */
	[_window orderFront:nil];
}

/* **THE ONE ENTRY A PARENT'S CHANGE COMES THROUGH.** `NSWindow` calls its drawers on every ordering, key, level and
 * frame change (see `cg_updateDrawers`); this re-syncs the level first, then the frame, then the pixels. A closed drawer
 * only needs the level, because it has no panel to place or show. */
- (void)cg_parentStateChanged
{
	if (_parentWindow == nil) {
		return;
	}
	[self fn_syncLevel];
	if (_state == NSDrawerOpenState) {
		[self fn_layout];
	}
	[self fn_updateVisibility];
}

- (void)cg_applicationActivityChanged:(NSNotification *)notification
{
	(void)notification;
	[self cg_parentStateChanged];
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

/* ============================================================================================
 * THE PARENT'S SIDE OF THE SYNC: ONE DOOR, CALLED BY THE DOORS THAT CHANGE WHAT A DRAWER IS PINNED TO.
 * ============================================================================================ */
/* **THE WINDOW SIDE IS A CATEGORY HERE BECAUSE THE STORAGE IS THE DRAWER'S.** `NSWindow` owns the list but not the
 * layout rule; `-cg_updateDrawers` is the seam the ordering, key, level and frame doors call, and its body is a walk of
 * the list this class already understands. The copy `-drawers` answers is what keeps the walk stable while a drawer
 * hides itself and its child link is re-made. */
@implementation NSWindow (AGDrawerUpdates)

static char AGWindowDrawerMarkerKey;

/* **A DRAWER WINDOW'S ONE MARKER.** An associated object rather than a fourth ivar: the flag is `NSDrawer`'s business,
 * the class it marks is `NSWindow`, and the public interface should not grow a field for a private relationship. */
- (void)cg_setDrawerWindow:(BOOL)flag
{
	objc_setAssociatedObject(self, &AGWindowDrawerMarkerKey, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)cg_isDrawerWindow
{
	return [objc_getAssociatedObject(self, &AGWindowDrawerMarkerKey) boolValue];
}

- (void)cg_updateDrawers
{
	NSArray *drawers = [self drawers];
	NSUInteger i;

	for (i = 0; i < [drawers count]; i++) {
		[(NSDrawer *)[drawers objectAtIndex:i] cg_parentStateChanged];
	}
}

@end
