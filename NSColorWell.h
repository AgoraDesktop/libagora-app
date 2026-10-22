/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSColorWell.h — A CONTROL THAT SHOWS A COLOUR AND OPENS THE COLOUR PANEL.
 *
 * **A WELL IS A SWATCH WITH A CLICK BEHAVIOUR, AND THAT IS ALL NINE OF ITS SELECTORS.** It draws the colour it holds,
 * it ACTIVATES — which means it makes itself the shared colour panel's target and brings the panel forward — and it
 * takes a colour back from the panel through `-takeColorFrom:`. `-drawWellInside:` is the public half of the drawing,
 * so a caller can paint the same swatch somewhere else (a palette row, a print-out) without a well instance.
 *
 * **ITS TARGET AND ACTION ARE ITS OWN, NOT A CELL'S**, for the same reason `NSMatrix`'s are: `NSControl` stores that
 * pair on its single cell and a well has no cell — the whole face is the swatch. The four inherited doors are therefore
 * overridden here, and the panel's action reaches this well through `-takeColorFrom:`.
 *
 * **A DRAG OUT OF THE WELL IS THE PANEL'S DRAG.** Apple's well begins a colour drag when the pointer leaves it; the
 * pasteboard and the rules for the drag live on `NSColorPanel`, so `-mouseDragged:` forwards there once per press — the
 * panel's `-dragColor:withEvent:fromView:` — rather than a second copy of the drag code in this class.
 *
 * Written from `NSColorWell.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSCOLORWELL_H
#define APPKIT_NSCOLORWELL_H

#import <AppKit/NSControl.h>

@class NSColor;

NS_ASSUME_NONNULL_BEGIN

@interface NSColorWell : NSControl <NSSecureCoding>
{
	NSColor *_color;		/* RETAINED */
	BOOL _active;
	BOOL _bordered;
	BOOL _draggedThisPress;
	/* THE WELL'S OWN TARGET/ACTION — see the header's second paragraph. */
	id _target;			/* ASSIGN */
	SEL _action;
}

- (instancetype)initWithFrame:(NSRect)frameRect;

/* THE COLOUR. A well with no colour set is white, which is the value a fresh well shows rather than an empty box. */
- (nullable NSColor *)color;
- (void)setColor:(nullable NSColor *)color;

/* **ACTIVATION IS THE PANEL'S.** `-activate:` makes this well the shared panel's target and action and orders the panel
 * front; `-deactivate` takes the panel's target back if it is still this well. A well that is deactivated while another
 * well has taken the panel leaves that other well alone, which is why the check is by identity. */
- (BOOL)isActive;
- (void)activate:(nullable id)sender;
- (void)deactivate;

/* THE FACE: WHETHER THE SWATCH WEARS A BORDER, AND THE DRAWING DOOR THAT PAINTS IT. */
- (void)setBordered:(BOOL)flag;
- (BOOL)isBordered;
- (void)drawWellInside:(NSRect)insideRect;

/* AND THE PANEL'S REPORT BACK. `-takeColorFrom:` asks the sender for its colour — the panel is the sender in the use
 * that matters — stores it, redisplays, and sends this well's own action. */
- (void)takeColorFrom:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLORWELL_H */
