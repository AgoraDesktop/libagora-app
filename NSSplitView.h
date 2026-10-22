/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSplitView.h — panes side by side or one above another, and the dividers that move between them.
 *
 * **THE VIEW IS FLIPPED, AND THAT IS THE FIRST THING TO KNOW ABOUT ITS GEOMETRY.** The era's own documentation says
 * a divider's rectangle is in coordinates "which are flipped": subview 0 is the LEFT pane of a vertical split view,
 * or the TOP pane of a horizontal one, and a horizontal split's y grows DOWN. That is the same choice `NSTableView`
 * makes, and it is why a divider's position needs no mirror arithmetic.
 *
 * **A DIVIDER POSITION IS ITS LEADING EDGE.** For a vertical split view that is the divider's x, and for a horizontal
 * one its y. `-setPosition:ofDividerAtIndex:` therefore names the boundary a pane ends at, not the middle of the
 * divider; the pane before the divider is exactly that many points wide (or tall). The trailing edge is the same
 * number plus `-dividerThickness`. This is stated because Apple's headers name the door but not the edge, and a
 * caller who assumes the centre is half a divider off.
 *
 * **THE COLLAPSED STATE IS A HIDDEN, ZERO-SIZED PANE.** A split view with a delegate may collapse a subview when
 * the user drags a divider through it or double-clicks the divider; `-isSubviewCollapsed:` is the question, and
 * the subview is retained (it is still in `-subviews`) rather than removed. A split view with NO delegate can
 * collapse nothing, which is Apple's rule and not a shortcut: `-splitView:canCollapseSubview:` is the permission.
 *
 * **WHAT THIS SLICE DOES NOT DO.** The later `NSSplitViewController` (10.10) and the holding-priority doors from
 * 10.8 are not here; this is the 10.6 class. Drag and drop of panes, an overlay scroller over a divider and the
 * live-resize snapshot optimisation are likewise absent. Autosave is implemented in THIS tier's format rather than
 * Apple's private one — the `autosaveName` is the contract, the dictionary under it is ours (see `-autosaveName`).
 *
 * Written from `NSSplitView.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSSPLITVIEW_H
#define APPKIT_NSSPLITVIEW_H

#import <AppKit/NSView.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSColor;
@class NSNotification;
@class NSSplitView;

/* THE ERA'S THREE VALUES. Apple publishes the case names and their order, not the numbers; the numbers here are the
 * header's own order. Thick is the default, as the SDK says. */
enum {
	NSSplitViewDividerStyleThick = 1,
	NSSplitViewDividerStyleThin = 2,
	NSSplitViewDividerStylePaneSplitter = 3
};
typedef NSInteger NSSplitViewDividerStyle;

/* **THE TWO ANNOUNCEMENTS, AND THE INDEX IN THE USER INFO.** A resize caused by dragging a divider carries the
 * divider's index under this key; a resize caused by the split view itself (a frame change, `-adjustSubviews`) has
 * no index and therefore no entry. Apple spells the key as a literal in the 10.6 header's prose rather than
 * declaring a constant, so this header does the same. */
extern NSString *NSSplitViewWillResizeSubviewsNotification;
extern NSString *NSSplitViewDidResizeSubviewsNotification;

@protocol NSSplitViewDelegate <NSObject>
@optional

/* COLLAPSING. With no delegate, or a delegate that does not answer the first door, no subview can collapse. The
 * second door is the double-click question; the drag path asks only the first (Apple's rule). */
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview;
- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview
    forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex;

/* THE DRAG'S LIMITS. The proposed positions are the geometric ones; a delegate may narrow them. */
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition
	 ofSubviewAt:(NSInteger)dividerIndex;
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition
	 ofSubviewAt:(NSInteger)dividerIndex;
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition
	 ofSubviewAt:(NSInteger)dividerIndex;

/* **THE RESIZE HOOK.** A delegate that answers this OWNS the layout for a frame change; the split view does not
 * also call `-adjustSubviews`. That is Apple's division, and it is why the delegate is handed the old size. */
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize;

/* The 10.6 question: may `-adjustSubviews` resize this pane? Its ORIGIN may still move regardless. */
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view;

/* The divider's appearance and hit area. The effective rectangle is where a press starts a drag; the additional
 * rectangle is a second, usually smaller, grab area (a splitter handle in the middle of a wide divider).
 *
 * **`shouldHideDividerAtIndex:` IS DECLARED BUT NOT CONSULTED, WHICH IS A DELIBERATE OMISSION RATHER THAN A STUB.**
 * Apple's door is about letting a divider be dragged or resized OFF THE EDGE of the split view so its handle is
 * invisible there. This implementation clamps every divider inside the bounds, so there is no off-edge state for the
 * answer to permit; the method is here because a 10.6 delegate might implement it, and ignoring an opinion a caller
 * was never given a chance to act on would be worse than naming the gap. */
- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex;
- (NSRect)splitView:(NSSplitView *)splitView effectiveRect:(NSRect)proposedEffectiveRect
       forDrawnRect:(NSRect)drawnRect ofDividerAtIndex:(NSInteger)dividerIndex;
- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex;

/* THE NOTIFICATION-SHAPED DOORS. Apple defines these so a delegate can answer without registering; the split view
 * sends both the notification and, when the delegate answers, this message. */
- (void)splitViewWillResizeSubviews:(NSNotification *)notification;
- (void)splitViewDidResizeSubviews:(NSNotification *)notification;

@end

@interface NSSplitView : NSView <NSSecureCoding>
{
	id <NSSplitViewDelegate> _delegate;		/* NOT RETAINED: a delegate is a client of its subject */
	BOOL _vertical;
	NSSplitViewDividerStyle _dividerStyle;
	NSString *_autosaveName;			/* COPIED; nil or empty means no autosave */
	/* THE COLLAPSED PANES, BY IDENTITY. An NSValue holds each subview's address; a subview that leaves the
	 * split view is swept out of this list before the next layout, because the pointer is borrowed. */
	NSMutableArray *_cg_collapsedSubviews;
	/* THE SIZE TO RETURN TO WHEN A COLLAPSED PANE IS OPENED AGAIN, keyed by the same identity. */
	NSMutableDictionary *_cg_collapsedSizes;
	/* THE DRAG'S BOOKKEEPING. A press records the divider and the point it began at, so a drag is a delta
	 * from that point rather than a jump to wherever the pointer was first seen. */
	NSInteger _cg_draggingDividerIndex;
	NSPoint _cg_dragStartPoint;
	CGFloat _cg_dragStartPosition;
	BOOL _cg_pushedCursor;
	CGFloat _cg_dragPreviewCenter;
	BOOL _cg_dragPreviewActive;
	/* LAYOUT'S REENTRANCY GATE. A delegate is allowed to set a divider's position while it is being resized,
	 * and a frame set on a subview may itself be a split view; the gate keeps one adjustment from nesting. */
	BOOL _cg_adjusting;
	BOOL _cg_hasLayout;
	BOOL _cg_loadingAutosave;
	BOOL _cg_autosavePending;
}

/* THE ORIENTATION. A vertical split view has vertical dividers and side-by-side panes; horizontal is the default,
 * as the SDK's `-setVertical:` says. */
- (void)setVertical:(BOOL)flag;
- (BOOL)isVertical;

/* THE DIVIDER'S STYLE AND ITS NAME FOR AUTOSAVING. */
- (void)setDividerStyle:(NSSplitViewDividerStyle)dividerStyle;
- (NSSplitViewDividerStyle)dividerStyle;
- (void)setAutosaveName:(nullable NSString *)autosaveName;
- (nullable NSString *)autosaveName;

/* THE DELEGATE. Not retained. */
- (void)setDelegate:(nullable id <NSSplitViewDelegate>)delegate;
- (nullable id <NSSplitViewDelegate>)delegate;

/* THE DIVIDER'S FACE. `-drawDividerInRect:` is the override point; a subclass changes the ink without touching the
 * geometry. `-dividerThickness` may also be overridden, in which case the split view relayouts on the next change.
 *
 * THE THREE STYLES IN THIS TIER: thick is a six-point filled bar, thin a one-point hairline, and PANE SPLITTER a
 * 18-point `windowBackgroundColor` gutter carrying three hollow `controlDarkShadowColor` rings — the scrollbar's
 * own grip: two-point radii, eight points apart. The pane splitter also snaps its non-final panes to whole points,
 * so a one-point pane border lands on the pixel grid and keeps the toolkit's `#BCBCBC` instead of being antialiased
 * into a lighter grey. Those numbers are this tier's (Apple says only that the default thickness depends on the
 * platform), and they are the ones the mockup the desktop is drawn from shows. */
- (void)drawDividerInRect:(NSRect)rect;
- (NSColor *)dividerColor;
- (CGFloat)dividerThickness;

/* THE LAYOUT. `-adjustSubviews` proportionally resizes the uncollapsed panes to fill the view and leaves room for
 * the dividers. The split view calls it itself when its frame changes unless its delegate took the resize hook. */
- (void)adjustSubviews;

/* THE COLLAPSED QUESTION. A collapsed pane is hidden and has a zero extent; it is still a subview. */
- (BOOL)isSubviewCollapsed:(NSView *)subview;

/* THE DIVIDER GEOMETRY. Indices are zero-based, with divider 0 the leftmost (vertical) or topmost (horizontal).
 * The "possible" range is dictated by the bounds and the OTHER dividers; a delegate's constraints narrow it further
 * and are applied by a drag or by `-setPosition:ofDividerAtIndex:`, not by these two questions. */
- (CGFloat)minPossiblePositionOfDividerAtIndex:(NSInteger)dividerIndex;
- (CGFloat)maxPossiblePositionOfDividerAtIndex:(NSInteger)dividerIndex;
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex;

@end

/* THE PRE-10.5 SPELLING, DEPRECATED BY APPLE IN 10.6 AND OWED HERE FOR OLDER APPLICATIONS. A pane splitter is the
 * wide divider style; a "grabber" is the ordinary one. */
@interface NSSplitView (NSDeprecated)
- (void)setIsPaneSplitter:(BOOL)flag;
- (BOOL)isPaneSplitter;
@end

/* AN AGORA-OWNED SEAM: whether a divider drag is in progress. A containing view that does expensive document
 * layout in `-splitViewDidResizeSubviews:` can defer it to the end of the drag, when the final notification is
 * posted with the dragging flag already cleared. */
@interface NSSplitView (AGDividerDragState)
- (BOOL)cg_isDraggingDivider;
@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSPLITVIEW_H */
