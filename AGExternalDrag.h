/*
 * AGExternalDrag.h — a drag that arrives from ANOTHER application, answered with AppKit's own protocol.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE SEAM CARRIES THE GESTURE; THIS FILE IS THE HALF THAT SPEAKS APPKIT.** `AGWindowServer`'s drag events name a
 * window id and a point in that window's coordinates; a view expects `-draggingEntered:`, a `draggingLocation` in
 * window space, and a pasteboard it can read during `-performDragOperation:`. The two vocabularies are this file's
 * whole subject, and the translation is done in one place because both a destination (this file) and a source
 * (`NSDraggingSession`, which answers `dataRequested`) have to agree about it.
 *
 * **THE EVENTS ARE QUEUED, AND THAT IS NOT TIMIDITY.** They arrive inside a Wayland dispatch, and a drop's handler
 * reads its payload through the same connection — a pump inside a dispatch is a re-entrant dispatch. So the seam's
 * callbacks record what happened and the application drains them where an event loop has already returned
 * (`-nextEventMatchingMask:`, which is the door every loop passes through). The extra pass costs nothing and buys the
 * one thing a synchronous read needs: a dispatch that is not already running.
 */

#import <AppKit/AppKit.h>

@interface AGExternalDrag : NSObject

/* **IDEMPOTENT, AND CALLED FROM BOTH ENDS.** A destination wants `enter`/`drop`; a source wants `dataRequested`, because
 * the payload it offers lives in the session's pasteboard, not in the compositor. Whichever side asks first installs. */
+ (void)cg_install;

/* Drain the queue recorded by the seam's callbacks. Called by the application between an event and its delivery. */
+ (void)cg_processPendingEvents;

/* **THE WINDOW LOOKUP, THROUGH A DOOR A PROBE CAN ANSWER.** A window's number is assigned by the compositor, so a program
 * with no display has none — and a test that could not resolve a window id could not drive `enter` at all, which is the
 * one door worth measuring. Nil restores the real lookup. */
typedef NSWindow *(*AGExternalDragWindowLookup)(uint32_t windowId);
+ (void)cg_setWindowLookup:(AGExternalDragWindowLookup)lookup;

/* Is a drag from another application over one of this application's windows? */
+ (BOOL)cg_isDragging;

/* ==================================================================================================
 * THE EIGHT DOORS THE SEAM PLUMBS INTO, NAMED SO A TEST CAN DRIVE THEM WITHOUT A COMPOSITOR.
 * ================================================================================================== */
+ (void)cg_handleEnterWithWindow:(uint32_t)windowId
			       x:(int)x
			       y:(int)y
			       types:(NSArray *)types
			      mask:(uint32_t)mask;
+ (void)cg_handleMotionToX:(int)x y:(int)y;
+ (void)cg_handleLeave;
+ (void)cg_handleDropAtX:(int)x y:(int)y;
+ (void)cg_handleFinished;
+ (void)cg_handleDataRequestedForType:(NSString *)type fd:(int)fd;
+ (void)cg_handleDataForType:(NSString *)type fd:(int)fd;
+ (void)cg_handleRefusalForType:(NSString *)type reason:(uint32_t)reason;

@end
