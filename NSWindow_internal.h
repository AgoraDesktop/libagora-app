/*
 * NSWindow_internal.h — the window's drag seam for the tracking engine.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * NOT INSTALLED AND NOT PUBLIC. A view that runs a modal drag loop (a divider, a split view) owns the pointer for
 * the length of the drag; re-walking the tracking tree for every motion event is both pointless and, in a browser
 * with hundreds of columns, ruinously expensive. These two doors are the tier's own and are used by the classes
 * that implement a drag, not by callers.
 */
#ifndef APPKIT_NSWINDOW_INTERNAL_H
#define APPKIT_NSWINDOW_INTERNAL_H

#import <AppKit/NSWindow.h>

/* **A RECTANGLE IN THIS WINDOW'S CORE GRAPHICS SPACE, AS ROWS OF ITS BUFFER.** The two spaces are mirrored: a
 * rectangle is y-UP (the space `-cg_drawFrameDirty:` fills and the tree draws in) and both the backing store and the
 * `wl_shm` buffer are TOP DOWN, so memory row 0 is the top of the window. This is that conversion, by itself,
 * because it is the arithmetic a partial copy is wrong without — `tests/display_damage.m` holds it. */
@interface NSWindow (AGDamageRows)
+ (NSRange)cg_bufferRowsForDirtyRect:(NSRect)dirty surfaceHeight:(NSInteger)surfaceHeight;
@end

@interface NSWindow (AGDragGuide)
- (void)cg_setDragGuideRect:(NSRect)rect;
- (void)cg_clearDragGuide;
@end

@interface NSWindow (AGTrackingSuspension)
- (void)cg_suspendTrackingUpdates;
- (void)cg_resumeTrackingUpdates;
@end

#endif /* APPKIT_NSWINDOW_INTERNAL_H */
