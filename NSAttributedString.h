/*
 * NSAttributedString.h (AppKit) — the attribute NAMES, which are the AppKit's and not Foundation's.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **APPLE SPLITS THE ATTRIBUTED STRING BETWEEN TWO FRAMEWORKS, AND THIS FILE IS THE SPLIT.** Foundation owns the
 * CLASS (`NSAttributedString` and its range API, which this tree already ships); the AppKit owns the KEYS that
 * say what a run of text MEANS — and the era's own `NSStringDrawing.h` imports this header for exactly that
 * reason (10.6 line 11). So the keys live here, in an AppKit header Apple also names `NSAttributedString.h`.
 *
 * **AND WHAT THIS SLICE CARRIES IS THE TWO THE DRAWING DOORS NEED, DELIBERATELY.** Apple's era header declares
 * twenty of these (`NSParagraphStyleAttributeName`, `NSUnderlineStyleAttributeName`, `NSAttachmentAttributeName`,
 * …) and each one is a claim about a VALUE TYPE this tier may not have yet — a paragraph style, an attachment —
 * so declaring them here would be writing twenty promises to satisfy one unit. The two below are the ones a
 * `-drawAtPoint:withAttributes:` caller must be able to name, and the rest arrive with the classes they name.
 *
 * **THE LITERALS ARE OURS, AND THE REASON IS MEASURED RATHER THAN ASSUMED**: the era header annotates each name
 * with the VALUE'S TYPE and default (`// NSFont, default Helvetica 12`) and publishes no literal, so no era
 * artifact fixes the strings. These two are Apple's long-standing spellings; what the probe CAN prove is the
 * behaviour that matters — that a dictionary keyed by them reaches the text layer and changes what is drawn.
 */
#ifndef APP_KIT_NSATTRIBUTEDSTRING_H
#define APP_KIT_NSATTRIBUTEDSTRING_H

#import <Foundation/Foundation.h>

/* THE FONT OF A RUN OF TEXT. Apple's era annotation: "NSFont, default Helvetica 12" — and THE DEFAULT IS A
 * DIVERGENCE IN THIS TIER, because there is no Helvetica here: a string drawn with no font attribute is drawn in
 * this tier's own system font at 12 points, which is `+[NSFont systemFontOfSize:12.0]`'s answer. */
extern NSString *NSFontAttributeName;

/* THE COLOUR OF A RUN OF TEXT. Apple's era annotation: "NSColor, default blackColor" — and black is what this
 * tier draws with when the key is absent, so the default needs no divergence note. */
extern NSString *NSForegroundColorAttributeName;

#endif /* APP_KIT_NSATTRIBUTEDSTRING_H */
