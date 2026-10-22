/*
 * NSImage_internal.h — the two doors a template image needs, and they are not public because only the
 * platform itself makes one.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * APPLE'S `-isTemplate` IS A PROPERTY OF THE ARTWORK, NOT A DRAWING INSTRUCTION. A template image is allowed to
 * be drawn in any ink, and on the Mac it is the CONTROL that decides which: a button's ink is the label's ink, a
 * disabled control's is a grey, a menu highlight's is white. The public door here (`-drawInRect:`) cannot say
 * that, and giving it a tinted variant would be inventing API Apple does not have — so the ink travels through
 * an INTERNAL door that `NSCell`'s subclasses use, and a caller outside the framework keeps drawing the image in
 * its own black, which is what a plain `-drawInRect:` means.
 */
#ifndef APPKIT_NSIMAGE_INTERNAL_H
#define APPKIT_NSIMAGE_INTERNAL_H

#import <AppKit/NSImage.h>

@class NSColor;

@interface NSImage (AGTemplateMask)
/* Mark this image a template and give it one stencil for one size, in points. Called once per size by
 * `AGSystemImageNamed` while it builds a named image from the generated coverage table; the image RETAINS the
 * mask and picks the stencil closest to the rectangle it is asked to draw. */
- (void)cg_setTemplateMask:(CGImageRef)mask forSize:(NSInteger)points;

/* Draw the image's glyph in `ink`, clipped to the stencil closest to `rect`. Answers NO when this is not a
 * template with a stencil — in which case the caller's ordinary `-drawInRect:` is the right next thing. */
- (BOOL)cg_drawInRect:(NSRect)rect ink:(NSColor *)ink;
@end

#endif /* APPKIT_NSIMAGE_INTERNAL_H */
