/*
 * NSStringDrawing.h — drawing a string where a caller says, which is the ink layer §A10bt found missing.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **§A10bt RETRACTED "a font is ink in this tier" AND NAMED THE GAP AS A LAYER.** The font arrived (§A10bv,
 * §A10bw); this file is the other half — the six doors that put a string on a surface — and it is the layer
 * `NSWindow`'s title refusal has been waiting on since it was recorded.
 *
 * **THE SHAPE IS THE ERA'S, INCLUDING THE FACT THAT IT IS CATEGORIES.** Apple declares these on `NSString` and
 * `NSAttributedString` rather than on a drawer object, and 10.6's `NSStringDrawing.h` is two categories plus an
 * extended half (the options-taking pair, which needs `NSStringDrawingOptions` and is its own slice). A category
 * is why the declarations live in an AppKit header while the classes are Foundation's — that IS Apple's split,
 * and the era file imports the key header (`<AppKit/NSAttributedString.h>`) to say so.
 *
 * **ONE POINT OF CONTRACT IS OURS AND IS STATED**: the era header carries no comment on what the point means, so
 * `-drawAtPoint:` draws with the point as the BASELINE origin — which is Core Text's own meaning for its text
 * position, so this tier's door is its engine's door rather than a convention invented above it.
 */
#ifndef APP_KIT_NSSTRINGDRAWING_H
#define APP_KIT_NSSTRINGDRAWING_H

#import <Foundation/Foundation.h>
#import <AppKit/NSAttributedString.h>

/* **ANNOTATED WHILE WRITTEN (F6), AND THE ANNOTATION SAYS WHAT THE IMPLEMENTATION ACCEPTS** — which is the standing
 * practice for this family, learned the hard way: a header that claims a parameter is non-null while the code
 * tolerates nil is a lie the compiler then propagates to every caller. **`attrs` IS NULLABLE HERE**: every door
 * below falls back to this tier's default font when it is nil, and that fallback is a behaviour the probe checks
 * (`...and-an-EMPTY-attributes-dictionary-still-draws`), so the annotation records it. */
NS_ASSUME_NONNULL_BEGIN

@interface NSString (NSStringDrawing)

- (NSSize)sizeWithAttributes:(nullable NSDictionary<NSString *, id> *)attrs;
- (void)drawAtPoint:(NSPoint)point withAttributes:(nullable NSDictionary<NSString *, id> *)attrs;
- (void)drawInRect:(NSRect)rect withAttributes:(nullable NSDictionary<NSString *, id> *)attrs;

@end

@interface NSAttributedString (NSStringDrawing)

- (NSSize)size;
- (void)drawAtPoint:(NSPoint)point;
- (void)drawInRect:(NSRect)rect;

@end

NS_ASSUME_NONNULL_END

#endif /* APP_KIT_NSSTRINGDRAWING_H */
