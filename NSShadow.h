/*
 * NSShadow.h — A SHADOW: an offset, a blur and a colour, and the door that puts it on the context.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A SHADOW IS A VALUE UNTIL `-set` MAKES IT A STATE.** The object holds three numbers and a colour; everything that
 * draws reads them from the GRAPHICS CONTEXT, which is why `-set` is the only door with an effect: it hands the offset,
 * the blur and the colour to `CGContextSetShadowWithColor` and every fill or stroke after it is shadowed until the
 * caller's state is restored. That split — a value object plus one state-setting door — is Apple's, and it is the reason
 * this class is eight selectors rather than a drawing pass of its own.
 *
 * **THE DEFAULTS ARE APPLE'S AND THE TEST PINS THEM**, because a shadow whose blur silently defaulted to zero would look
 * like a shadow that did not work. A nil colour means "black, with the engine's own default alpha" and is not the same as
 * an alpha-zero colour: the first shadows, the second is invisible.
 *
 * **AND `-set` REFUSES WHEN THERE IS NO CONTEXT**, by name, rather than drawing into nothing: the same rule `NSColor
 * -setFill` follows.
 */
#ifndef APPKIT_NSSHADOW_H
#define APPKIT_NSSHADOW_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSColor;

@interface NSShadow : NSObject <NSCopying>
{
	NSSize _shadowOffset;
	CGFloat _shadowBlurRadius;
	NSColor *_shadowColor;	/* RETAINED; nil means black at the engine's default alpha */
}

/* THE DEFAULTS: an offset of (0, -3), a blur radius of 3.0 and no colour. */
- (instancetype)init;

/* **THE ONE DOOR WITH AN EFFECT.** It sets the shadow in the current graphics context; the caller's own save/restore is
 * what removes it, which is why this class does not offer an `-unset`. */
- (void)set;

/* WHERE THE SHADOW FALLS, how soft it is, and what colour it is. A nil colour means black. */
@property NSSize shadowOffset;
@property CGFloat shadowBlurRadius;
@property (nullable, copy) NSColor *shadowColor;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSHADOW_H */
