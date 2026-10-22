/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPanel.m — three answers that differ from a window's, and one initialiser that sets the panel's own default.
 *
 * **THE CLICK-TO-KEY DOOR IS A SEAM BETWEEN THIS CLASS AND `NSApplication`.** The application owns the click that
 * makes a window key (it is the one place a press becomes key/main), and the PANEL owns the "only when needed" rule.
 * Neither can answer the question alone, so the question travels on `NSWindow`'s private `-cg_shouldBecomeKey…`
 * door — declared in `NSWindow.h` beside the other click-to-key state, answered YES by a window, and answered by
 * this class with the view rule below. The door is prefixed `cg_` because it is this tree's seam and not Apple's API.
 */
#import <AppKit/NSPanel.h>

#import <AppKit/NSView.h>

@implementation NSPanel

- (instancetype)initWithContentRect:(NSRect)contentRect
			  styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType
			      defer:(BOOL)flag
{
	self = [super initWithContentRect:contentRect styleMask:styleMask backing:bufferingType defer:flag];
	if (self == nil) {
		return nil;
	}
	/* **THE ONE DEFAULT A PANEL DOES NOT SHARE WITH A WINDOW.** Apple's documentation: `hidesOnDeactivate` is "YES
	 * for panels and NO for other windows", because a panel is an assistant to a window and has nothing to say when
	 * the application is in the background. `NSWindow`'s ivar default is NO, so the difference has to be written
	 * here; a caller that disagrees sets it back through the inherited door. */
	[self setHidesOnDeactivate:YES];
	return self;
}

- (BOOL)becomesKeyOnlyIfNeeded
{
	return _becomesKeyOnlyIfNeeded;
}

- (void)setBecomesKeyOnlyIfNeeded:(BOOL)flag
{
	/* RECORDED, AND READ WHERE A CLICK IS ROUTED — see `-cg_shouldBecomeKeyForClickAtPoint:` below and
	 * `NSApplication -sendEvent:`. The name says "only if needed"; the need is the view's answer, which is why the
	 * flag alone is not the whole implementation. */
	_becomesKeyOnlyIfNeeded = flag ? YES : NO;
}

- (BOOL)canBecomeMainWindow
{
	/* **ALWAYS NO, AND APPLE SAYS SO IN THE WINDOW'S OWN RULE.** Its `canBecomeMainWindow` documentation is "true
	 * when the window is visible, is not an NSPanel object, and has a title bar or a resize mechanism" — the panel
	 * clause is absolute, so visibility and the style mask do not enter into it. A panel takes the KEY, which is how
	 * a utility palette receives typing; it never takes the MAIN slot, which is the document the person is working
	 * in. */
	return NO;
}

/* ---- THE SEAM WITH THE APPLICATION'S CLICK ROUTING ------------------------------------------ */

- (BOOL)cg_shouldBecomeKeyForClickAtPoint:(NSPoint)point
{
	NSView *hit;

	/* A PANEL THAT DID NOT ASK FOR THE RESTRICTION BEHAVES LIKE A WINDOW, which is Apple's default and the common
	 * case: a click anywhere in the panel makes it key. */
	if (!_becomesKeyOnlyIfNeeded) {
		return YES;
	}
	/* **THE VIEW UNDER THE POINTER IS ASKED, THEN ITS ANCESTORS.** `-hitTest:` answers the deepest view, and the
	 * question Apple's own door asks is `-needsPanelToBecomeKey`; walking up the superview chain answers for a view
	 * that is inside a container which needs the key (an editable field's label, a scroller inside a text view) while
	 * leaving a plain background NO. The walk stops at the content view because there is no view above it — the
	 * window is not a view and its own answer is `canBecomeKeyWindow`. */
	hit = [[self contentView] hitTest:point];
	while (hit != nil) {
		if ([hit needsPanelToBecomeKey]) {
			return YES;
		}
		hit = [hit superview];
	}
	return NO;
}

@end
