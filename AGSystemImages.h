/*
 * AGSystemImages.h — the platform's own named images: what `+[NSImage imageNamed:]` answers for an
 * `NSImageName…` that this tier draws rather than reads from a bundle.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * APPLE'S NAMES EXISTED HERE BEFORE THE PICTURES DID. `NSImage.h` has declared all 57 `NSImageName…` constants
 * for as long as the tier has had an `NSImage`, and `+imageNamed:` answered every one of them with a BUNDLE
 * lookup — which found nothing, because a framework's images are not an application's resources. A caller
 * that asked for `NSImageNameGoLeftTemplate` got nil and drew a text label instead, which is why nothing in
 * this tree has ever had a Back arrow.
 *
 * SO THE PICTURES ARE THE PLATFORM'S, IN THE PLATFORM. `SystemImageMasks.c` is a generated table of coverage —
 * one byte per pixel, two sizes, one picture per glyph — and this unit turns a name into an `NSImage` that
 * carries it. Nothing is installed beside the library and there is no directory to find: the same reason the
 * window chrome's marks are numbers in `NSWindow.m` rather than XFWM's `.xpm` files.
 *
 * A SYSTEM IMAGE IS A TEMPLATE. It has one ink, chosen by whatever draws it (a button's `-cg_inkColor`, a
 * disabled control's grey), which is what makes the same glyph work on a grey button, in a menu and in a
 * toolbar. `NSImage -cg_drawInRect:ink:` is that door; a plain `-drawInRect:` falls back to the image's own
 * black, which is the honest answer for a caller that did not say what ink it wanted.
 *
 * NOT EVERY `NSImageName…` IS HERE YET. The twenty below are the BUTTON set — the images a toolbar, a menu
 * item or a view-mode switcher actually wears. The rest (`NSImageNameMobileMe`, `NSImageNameFlowViewTemplate`,
 * the icon-art ones) are still a bundle lookup that finds nothing, and `AGSystemImageNamed` answers nil for
 * them rather than inventing a picture.
 */
#ifndef AGORA_AGSYSTEMIMAGES_H
#define AGORA_AGSYSTEMIMAGES_H

#import <Foundation/NSString.h>

@class NSImage;

/* The image for one of the names this tier draws, or nil when the name is not one of them — in which case the
 * caller's ordinary bundle lookup is still the right next question. The answer is CACHED and not retained on
 * the caller's behalf beyond the cache, exactly as `+[NSImage imageNamed:]` behaves. */
NSImage *AGSystemImageNamed(NSString *name);

/* How many names this tier draws. The probe uses it to walk the whole set rather than a list of its own. */
unsigned AGSystemImageCount(void);

/* The name at an index, sorted the way `SystemImageMasks.c` is, so a probe can assert over all of them. */
NSString *AGSystemImageNameAtIndex(unsigned index);

#endif /* AGORA_AGSYSTEMIMAGES_H */
