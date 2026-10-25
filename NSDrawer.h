/*
 * NSDrawer.h — A PANEL THAT SLIDES OUT OF A WINDOW'S EDGE, AND THE FOUR STATES IT MOVES THROUGH.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A DRAWER IS A CHILD WINDOW, AND THAT IS APPLE'S MODEL RATHER THAN A CONVENIENCE.** `NSDrawer` is an
 * `NSResponder`, not a view: it owns a WINDOW (borderless, the size of the drawer), that window is attached to the
 * parent as a CHILD WINDOW, and `-contentView` is that window's content view. The drawer's geometry is therefore in
 * SCREEN coordinates, computed from the parent's frame, and "sliding out" means the child window sits at the parent's
 * edge — left, right, bottom or top — with the edge that touches the parent TUCKED UNDER IT. This tier already has
 * child windows (`-addChildWindow:ordered:` and the move propagation that goes with them), so the class is built on
 * that machinery instead of inventing a second one.
 *
 * **A DRAWER IS PINNED TO ITS PARENT, IN THREE WAYS.** Its window SHARES THE PARENT'S LEVEL and is ordered as the
 * LAYER IMMEDIATELY BELOW it — the drawer is raised, then the parent over it, so the tucked edge disappears under the
 * window it belongs to while the panel stays above every window below the parent. (A numeric level one lower would sit
 * under every window at the parent's level, which is the bug the gallery showed.) A click INSIDE the drawer is an
 * ordering of the drawer's own window; the drawer's marker makes that ordering re-raise the parent in the same call, so
 * the panel cannot be above it even for one frame — the flash a close button used to produce. It is on the glass only
 * while the parent is VISIBLE, KEY and in an ACTIVE application; focusing another window or another application takes it down,
 * and bringing the parent back brings it up. And its frame follows every move, resize and level change of the parent,
 * so the centring and the tuck are properties of the pair rather than a position captured once at `-open`. A hidden
 * drawer keeps its child link (the window is un-ordered and re-attached behind the parent), so the relationship is
 * stable across the hides.
 *
 * **THE TRANSITION IS SYNCHRONOUS, AND THAT IS THE ONE STATED DEVIATION.** Apple's drawer slides: `-open` sets
 * `NSDrawerOpeningState`, animates over some frames, then `NSDrawerOpenState`. This tier has no drawer animation clock,
 * so `-open` performs the whole transition in one call: it sets the OPENING state, announces `WillOpen` (where a
 * handler can read the state), lays the window out, sets the OPEN state, and announces `DidOpen`. `-close` does the
 * same in reverse with CLOSING/CLOSED. **THE INTERMEDIATE STATES ARE THEREFORE REAL BUT FLEETING** — observable from a
 * notification handler or the delegate, never from a caller that is merely waiting for `-open` to return. A slice that
 * adds a slide animation replaces the two middle assignments and nothing else.
 *
 * **THE PARENT WINDOW RETAINS THE DRAWER, WHICH IS APPLE'S OWN OWNERSHIP RULE.** `-setParentWindow:` registers the
 * receiver in the parent's `-drawers` list (declared in the `NSWindow (Drawers)` category below), and that list retains
 * it; `-parentWindow` is a BORROWED back-pointer, which is what keeps the pair from retaining each other. Releasing a
 * drawer that is still attached therefore does not destroy it: detach it with `-setParentWindow:nil` first.
 *
 * **THE SIZE HAS TWO AXES AND THEY ARE NOT SYMMETRIC.** In the direction of the drawer's motion the VISIBLE size is its
 * CONTENT SIZE; a side drawer's WINDOW is that width PLUS the tucked strip on the parent's side, and its content view is
 * inset by the strip so the tuck costs empty panel rather than the first 20 points of the content. A SIDE DRAWER'S
 * HEIGHT IS 90% OF THE PARENT'S, CENTRED on the parent's vertical axis inside the `-leadingOffset`/`-trailingOffset`
 * inset: the remaining tenth is the air above and below that makes the panel read as a drawer rather than a second
 * window. A top or bottom drawer keeps the older span across the parent, because a bottom drawer that did not span is
 * not a bottom drawer; its thickness is the content height capped by the same 20-point inset.
 *
 * **AND THE MINIMUM AND MAXIMUM CONTENT SIZES LIMIT THE USER'S RESIZE, NOT THE PROGRAMMER'S.** Apple says so in as
 * many words ("programmatic changes are not so limited"), and it is why `-setContentSize:` is plain storage while the
 * user path below is a separate door. THIS TIER HAS NO DRAWER-EDGE DRAG GESTURE: `-cg_resizeContentByUserToSize:` is
 * the user path, so a caller that wires a gesture to it — or a probe — gets the documented clamp and the delegate's
 * `-drawerWillResizeContents:toSize:` review, and nothing pretends a mouse is tracking an edge nobody drew.
 */
#ifndef APPKIT_NSDRAWER_H
#define APPKIT_NSDRAWER_H

#import <AppKit/NSResponder.h>
#import <AppKit/NSWindow.h>

@class NSNotification;
@class NSView;
@class NSWindow;
@protocol NSDrawerDelegate;

NS_ASSUME_NONNULL_BEGIN

/* **THE FOUR STATES, AND ZERO IS "CLOSED" BECAUSE A FRESH DRAWER IS NOT ON SCREEN.** `NSDrawerState` is the type a
 * caller compares against; the two middle values are the ones a synchronous transition passes through (see the header
 * note above), which is what makes a `WillOpen` handler see OPENING rather than OPEN. */
enum {
	NSDrawerClosedState = 0,
	NSDrawerOpeningState = 1,
	NSDrawerOpenState = 2,
	NSDrawerClosingState = 3
};
typedef NSUInteger NSDrawerState;

@interface NSDrawer : NSResponder
{
	/* **THE CHILD WINDOW, MADE AT INIT AND NEVER REPLACED.** A drawer always has a window (Apple's does too), which is
	 * what makes `-setContentView:` meaningful before the drawer is ever opened; it is created borderless and is not
	 * ordered in until the parent is on screen and the drawer opens. */
	NSWindow *_window;		/* RETAINED */
	/* **THE PARENT IS BORROWED, BECAUSE THE PARENT OWNS THIS DRAWER.** The `-drawers` list retains the drawer; a
	 * retained back-pointer would close the cycle, so this one is not retained. */
	NSWindow *_parentWindow;	/* NOT RETAINED */
	/* THE DELEGATE, NOT RETAINED, like every delegate in this tree. */
	id <NSDrawerDelegate> _delegate;	/* NOT RETAINED */

	NSDrawerState _state;
	/* **TWO EDGES, BECAUSE A DRAWER HAS A PREFERENCE AND A POSITION.** `-preferredEdge` is where it WOULD like to be;
	 * `-edge` is where it IS (or was last). They differ while the drawer is open on an edge chosen by
	 * `-openOnEdge:`/`-open:`, and while it is closed a preference change moves both. */
	NSRectEdge _edge;
	NSRectEdge _preferredEdge;
	/* THE CONTENT SIZE: the thickness in the motion direction and the panel's own extent across it. */
	NSSize _contentSize;
	NSSize _minContentSize;
	NSSize _maxContentSize;
	CGFloat _leadingOffset;
	CGFloat _trailingOffset;
	/* **AND THE RE-ENTRANCY GUARD.** The transition announces its own middle, so a delegate or observer that calls
	 * `-open`/`-close` from inside a `Will…` handler would otherwise run a second transition inside the first. While
	 * this is set, both doors answer by doing nothing, which is the documented rule rather than an accident. */
	BOOL _cg_inTransition;
}

/* **THE DESIGNATED INITIALISER: A SIZE AND AN EDGE, BECAUSE A DRAWER WITHOUT EITHER HAS NO GEOMETRY.** The size is the
 * CONTENT size (the panel's thickness in the motion direction, its other extent before offsets), and the edge is where
 * the drawer prefers to sit. The drawer starts CLOSED; `-open` is what puts it on screen. */
- (instancetype)initWithContentSize:(NSSize)contentSize preferredEdge:(NSRectEdge)edge;

/* ---- THE PARENT AND THE CONTENT ---------------------------------------------------------------- */

/* **ATTACHING AND DETACHING ARE THE SAME DOOR, AND IT IS WHERE THE OWNERSHIP LIVES.** Setting a parent registers the
 * receiver in that window's `-drawers` list (which retains it) and, if the drawer is open, moves its child window to the
 * new parent. Setting nil unregisters it — the step that makes a `release` destroy the drawer. A drawer with no parent
 * cannot open: there is no frame to hang off and no owner to retain it. */
- (void)setParentWindow:(nullable NSWindow *)parent;
- (nullable NSWindow *)parentWindow;

/* **THE VIEW THE DRAWER SHOWS IS ITS CHILD WINDOW'S CONTENT VIEW, IN THOSE WORDS.** Setting one retains it through the
 * window; while the drawer is open the view's frame is the drawer's content rect, so a content view that resizes itself
 * with its window (`NSView`'s default) fills the panel. */
- (void)setContentView:(nullable NSView *)aView;
- (nullable NSView *)contentView;

/* ---- THE EDGE AND THE FOUR STATE DOORS --------------------------------------------------------- */

/* The preferred edge is a wish; `-openOnEdge:` and `-open:` are what act. While CLOSED a preference change moves
 * `-edge` too (a closed drawer has no position to preserve); while OPEN it does not move the window. */
- (void)setPreferredEdge:(NSRectEdge)edge;
- (NSRectEdge)preferredEdge;

/* **`-open` OPENS ON THE PREFERRED EDGE; `-openOnEdge:` OPENS ON THE NAMED ONE.** Both are refused by a delegate's
 * `-drawerShouldOpen:` answering NO, by a nil parent, and (silently) by a re-entrant call from inside a transition.
 * Opening a drawer that is already open moves it to the named edge and lays it out again — no second pair of
 * notifications, because nothing was opened. `-open:` is the action-sender spelling of the same door. */
- (void)open;
- (void)openOnEdge:(NSRectEdge)edge;
- (void)close;
- (void)open:(nullable id)sender;
- (void)close:(nullable id)sender;
/* AND TOGGLE IS THE ONE DECISION A TOOLBAR ITEM WANTS: closed opens, open closes, a transition ignores it. */
- (void)toggle:(nullable id)sender;

/* THE STATE AND THE EDGE THE DRAWER IS ACTUALLY ON. `-state` answers one of the four `NSDrawerState` values, and
 * `-edge` answers the last edge opened on (or the preference, while closed). */
- (NSInteger)state;
- (NSRectEdge)edge;

/* ---- THE SIZE, AND THE LIMITS THAT APPLY TO THE USER -------------------------------------------- */

/* **`-setContentSize:` IS PROGRAMMATIC AND THEREFORE NOT LIMITED BY THE MINIMUM AND MAXIMUM** (Apple's sentence). The
 * parent clamp still applies at layout, because a drawer cannot be larger than its parent. `-contentSize` answers the
 * STORED request rather than the clamped layout, so a caller can read back what it asked for. */
- (void)setContentSize:(NSSize)size;
- (NSSize)contentSize;
- (void)setMinContentSize:(NSSize)size;
- (NSSize)minContentSize;
- (void)setMaxContentSize:(NSSize)size;
- (NSSize)maxContentSize;

/* **THE OFFSETS ARE THE GAP AT EACH END OF THE TRANSVERSE AXIS.** For a left or right drawer they inset the top and
 * bottom (leading is the top); for a bottom or top drawer they inset the left and right (leading is the left). The
 * transverse size is the parent's minus both, never less than zero and never more than the parent. */
- (void)setLeadingOffset:(CGFloat)offset;
- (CGFloat)leadingOffset;
- (void)setTrailingOffset:(CGFloat)offset;
- (CGFloat)trailingOffset;

/* ---- THE USER'S RESIZE, WHICH IS A DOOR BECAUSE THIS TIER HAS NO EDGE TRACKER --------------------- */

/* **THE USER PATH: CLAMP TO THE MINIMUM AND MAXIMUM, ASK THE DELEGATE, THEN LAY OUT.** Apple's rule is that a user may
 * resize the drawer within its limits, and the delegate may choose the final size; this door is that rule without the
 * gesture. The proposed size is clamped to `-minContentSize`/`-maxContentSize` BEFORE the delegate is asked, the
 * delegate's answer is used as given (only the parent clamp remains, because that one is absolute), and the drawer
 * lays out again if it is open. A caller wiring a drag to this door gets the documented behaviour; nothing here
 * pretends a mouse is tracking an edge. */
- (void)cg_resizeContentByUserToSize:(NSSize)size;

/* ---- THE DELEGATE -------------------------------------------------------------------------------- */

- (void)setDelegate:(nullable id <NSDrawerDelegate>)anObject;
- (nullable id <NSDrawerDelegate>)delegate;

@end

/* **THE FOUR ANNOUNCEMENTS, AND THE DELEGATE'S NOTIFICATION-SHAPED DOORS CARRY THE SAME OBJECTS.** Each notification's
 * object is the DRAWER; the protocol's four `drawerWillOpen:`-style methods are sent with that notification AFTER it is
 * posted, which is the arrangement `NSSplitView` and `NSMenu` already use. */
extern NSString *NSDrawerWillOpenNotification;
extern NSString *NSDrawerDidOpenNotification;
extern NSString *NSDrawerWillCloseNotification;
extern NSString *NSDrawerDidCloseNotification;

/* **THE DRAWERS OF A WINDOW, WHICH IS HOW A CALLER FINDS THEM RATHER THAN KEEPING ITS OWN LIST.** The array is the
 * window's private order (the order drawers were attached); it is a COPY the caller may not mutate, and it is empty
 * rather than nil when the window has none. */
@interface NSWindow (Drawers)
- (NSArray *)drawers;
@end

/* **AND THE DELEGATE'S SEVEN OPTIONAL DOORS, EACH WITH A SENDER.** The first two are the permission questions, the
 * third is the user-resize review, and the last four are the notification-shaped twins of the four announcements. */
@protocol NSDrawerDelegate <NSObject>

@optional

/* NO leaves the drawer where it is: a refused open sends no notification and changes no state, and a refused close
 * leaves an open drawer open. */
- (BOOL)drawerShouldOpen:(NSDrawer *)sender;
- (BOOL)drawerShouldClose:(NSDrawer *)sender;

/* THE USER'S RESIZE, REVIEWED. `contentSize` has already been clamped to the drawer's minimum and maximum; the answer
 * is the size the drawer takes (the parent clamp still applies at layout). */
- (NSSize)drawerWillResizeContents:(NSDrawer *)sender toSize:(NSSize)contentSize;

/* THE FOUR ANNOUNCEMENTS, AS METHODS. Each is sent after the notification of the same name is posted, with the
 * notification as its argument, so a conforming delegate can read `[notification object]` and the drawer's state. */
- (void)drawerWillOpen:(NSNotification *)notification;
- (void)drawerDidOpen:(NSNotification *)notification;
- (void)drawerWillClose:(NSNotification *)notification;
- (void)drawerDidClose:(NSNotification *)notification;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSDRAWER_H */
