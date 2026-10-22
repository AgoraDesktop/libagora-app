/*
 * NSCachedImageRep.h — A REP THAT HOLDS PIXELS SOMEBODY ELSE DREW.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE REP FOR A REGION ALREADY RENDERED.** Two shapes: a WINDOW and a rectangle of it (the era's way to keep a piece of
 * a window as an image), or a blank CANVAS of a given size and depth that a caller fills in. This tier can honour both for
 * real, because the pieces exist: `-cacheDisplayInRect:toBitmapImageRep:` renders a view region into a bitmap, and a bitmap
 * rep draws through the base class's `-CGImage` blit.
 *
 * **THE WINDOW IS BORROWED AND THE PIXELS ARE NOT.** The rep captures the rectangle ONCE, at construction — the era's
 * class was a cache, not a live view — so a window that repaints afterwards does not change the rep. That is stated because
 * the alternative reading ("this tracks the window") is what a caller would assume from the name.
 *
 * **THE CANVAS FORM IS TRANSPARENT UNTIL SOMETHING DRAWS INTO IT**, and nothing can: this tier's reps are read-only. The
 * initialiser exists so a caller's compile line works and so a subclass can use the buffer; a caller expecting to paint
 * into it should draw into a bitmap rep, which is the class this one wraps.
 */
#ifndef APPKIT_NSCACHEDIMAGEREP_H
#define APPKIT_NSCACHEDIMAGEREP_H

#import <AppKit/NSImageRep.h>
#import <AppKit/NSGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class NSWindow;
@class NSBitmapImageRep;

@interface NSCachedImageRep : NSImageRep
{
	NSBitmapImageRep *_bitmap;	/* RETAINED: the captured (or blank) pixels */
	NSWindow *_window;		/* NOT RETAINED: the window it was captured from, for `-window` */
	NSRect _rect;			/* where in the window the capture came from */
}

/* **A BLANK CANVAS.** The size, the depth (an `NSWindowDepth`), whether the buffer is separate from a window's, and whether
 * it has alpha; the last three decide the bitmap's format and the pixels start transparent. */
- (nullable instancetype)initWithSize:(NSSize)size depth:(NSWindowDepth)depth separate:(BOOL)separate
			      alpha:(BOOL)alpha;

/* **A CAPTURE OF A WINDOW'S RECTANGLE**, taken now. The window is borrowed and the rectangle is in the window's BASE
 * coordinates, which is what the era's door means. */
- (nullable instancetype)initWithWindow:(NSWindow *)window rect:(NSRect)rect;

- (nullable NSWindow *)window;
- (NSRect)rect;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCACHEDIMAGEREP_H */
