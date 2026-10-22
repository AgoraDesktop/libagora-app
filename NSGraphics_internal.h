/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

/* NSGraphics_internal.h — the one piece of state the drawing functions share with the context.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 *
 * **`NSDisableScreenUpdates` NEEDS SOMEWHERE TO BE TRUE.** The pair is a counter over "do not push pixels to the
 * compositor yet", and the only door in this tier that pushes pixels is `-[NSGraphicsContext flushGraphics]`, which
 * calls `CGContextFlush`. So the counter lives in `NSGraphics.m` beside its two owners and the flush asks it — rather
 * than a function that returns `void` and stores a boolean nothing reads, which is the shape a stub takes when it is
 * written to satisfy a linker instead of a caller.
 */
#ifndef APPKIT_NSGRAPHICS_INTERNAL_H
#define APPKIT_NSGRAPHICS_INTERNAL_H

#import <Foundation/NSObjCRuntime.h>

/* YES while a `NSDisableScreenUpdates` is outstanding. Balanced: each disable is a +1 and each enable a -1. */
BOOL cg_screenUpdatesDisabled(void);

#endif /* APPKIT_NSGRAPHICS_INTERNAL_H */
