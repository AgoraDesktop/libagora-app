/*
 * NSToolbar_internal.h — the doors NSWindow and NSToolbarItem use on each other.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE TOOLBAR'S VIEW IS PRIVATE, BUT THE WINDOW HAS TO HOST IT.** `NSToolbarView` is an implementation class: it
 * owns the layout, the item rectangles and the custom item views, and no caller outside `NSToolbar.m` should name it.
 * `NSWindow` still has to place it in the frame, ask its height, draw it in the content's context and send it a
 * pointer event — so those four doors are declared here rather than on the public class, and the view itself stays
 * private.
 *
 * **WHY A VIEW AT ALL.** The toolbar band is not inside the content view: `NSView -displayRect:` clips every view to
 * its bounds, so a toolbar made a subview of the content view would be clipped away the moment it sat above the
 * content's top edge. A root view with no superview is drawn by the window at an explicit origin instead, which is
 * the same shape the chrome's painter uses and the only one that lets a custom item view keep a real view tree.
 */
#ifndef AGORA_APPKIT_NSTOOLBAR_INTERNAL_H
#define AGORA_APPKIT_NSTOOLBAR_INTERNAL_H

#import <AppKit/NSToolbar.h>
#import <AppKit/NSToolbarItem.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSView;
@class NSWindow;
@class NSToolbarItem;

@interface NSToolbar (AGWindowSeam)
/* THE HEIGHT THE BAND WANTS, which is the size mode's answer and the number `NSWindow` subtracts from its content
 * rect. Zero is not an answer here: `-isVisible` is the switch, and this is what a visible toolbar needs. */
- (CGFloat)cg_toolbarHeight;
/* THE VIEW, MADE ON FIRST ASK. The window owns nothing; the toolbar owns its view and lends it. */
- (NSView *)cg_view;
/* THE WINDOW THE TOOLBAR IS ATTACHED TO, or nil. The view is told the same window so a custom item view can reach
 * its own `-window` and responder chain. */
- (void)cg_setWindow:(nullable NSWindow *)window;
/* "SOMETHING THE VIEW DRAWS CHANGED" — an item was added or removed, a label or image moved, a mode switched. */
- (void)cg_layoutChanged;
/* **"IS THIS POINT ON SOMETHING THE POINTER CAN USE?", IN WINDOW COORDINATES — the question `NSWindow` asks before
 * it decides the band is a drag handle.** A control is the item's; the band between controls — and over a separator
 * or either space, which are drawn but do nothing — is the window's, the way the title bar is. Asking the toolbar
 * rather than re-deriving the item rectangles in `NSWindow.m` is what keeps the drag handle and the item's own click
 * from disagreeing about which is which. */
- (BOOL)cg_pointIsOverControl:(NSPoint)pointInWindow;
@end

@interface NSToolbarItem (AGToolbarSeam)
/* THE OWNER LINK, SET BY THE TOOLBAR AS IT INSERTS OR REMOVES. Not retained: a toolbar owns its items, and an item
 * that retained its toolbar would make a cycle with no owner outside it. */
- (void)cg_setToolbar:(nullable NSToolbar *)toolbar;
/* An attribute changed, so the toolbar's layout and ink are stale. */
- (void)cg_changed;
@end

NS_ASSUME_NONNULL_END

#endif /* AGORA_APPKIT_NSTOOLBAR_INTERNAL_H */
