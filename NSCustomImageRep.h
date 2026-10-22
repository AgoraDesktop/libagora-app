/*
 * NSCustomImageRep.h — A REP THAT DRAWS BY ASKING SOMEBODY ELSE.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE ONLY IMAGE REP WHOSE PIXELS ARE A MESSAGE.** Every other rep decodes a format; this one holds a DELEGATE and a
 * selector, and `-drawInRect:` sends that selector to that delegate so the delegate can draw whatever it likes into the
 * rectangle. It is how an application puts code-shaped art into an `NSImage` — a shape that recomputes itself at every
 * size rather than a bitmap that scales.
 *
 * **THE SELECTOR TAKES THREE ARGUMENTS**, which Apple's own example spells: the image rep, the destination rectangle, and
 * a flag that is YES when the drawing is for the screen. The delegate is BORROWED, and the selector is checked at
 * construction — a rep that cannot draw is worth refusing at the call rather than at the paint.
 */
#ifndef APPKIT_NSCUSTOMIMAGEREP_H
#define APPKIT_NSCUSTOMIMAGEREP_H

#import <AppKit/NSImageRep.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSCustomImageRep : NSImageRep
{
	SEL _drawSelector;
	id _delegate;		/* NOT RETAINED: this tree's rule for every delegate */
}

/* **THE SELECTOR MUST TAKE (id, NSRect, BOOL).** A nil delegate, a NULL selector or a selector whose signature does not
 * match answers nil and says which, because the alternative is a rep that exists and cannot draw. */
- (nullable instancetype)initWithDrawSelector:(SEL)selector delegate:(nullable id)delegate;

- (nullable SEL)drawSelector;
- (nullable id)delegate;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCUSTOMIMAGEREP_H */
