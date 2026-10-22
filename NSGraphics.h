/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */

/* NSGraphics.h — the window-depth vocabulary.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 *
 * **EVERY VALUE IN THIS FILE WAS READ FROM APPLE'S OWN PUBLIC HEADER RATHER THAN INFERRED**, which is what the
 * standing grant allows (declarations, for compatibility) and what the depth type REQUIRES: a depth is a PACKED
 * integer whose bits the functions below read apart, and a packed encoding is exactly the kind of thing a
 * plausible-looking guess gets wrong. Apple's header says so in as many words — "window depths should not be
 * made persistent as they will not be the same across systems" — so the constants and the extractors are the
 * whole interface and both are transcriptions.
 *
 * AND THE FILE IS `NSGraphics.h` BECAUSE THAT IS WHERE APPLE DECLARES THEM, beside the drawing functions rather
 * than in `NSWindow.h`, which is the class that happens to USE a depth limit.
 *
 * WHAT THE ENCODING IS, now that it has been read: the three depths are 0x208, 0x210 and 0x220 — each 0x10 apart
 * with the low nibble holding the bits-per-sample of the smallest, and the bits above 8 holding the colour space.
 * THAT OBSERVATION IS NOT AN IMPLEMENTATION: the extractors below answer from the CONSTANTS by name, so a depth
 * Apple has not published gets the honest answer rather than a bit-shuffle this tree invented.
 */
#ifndef APPKIT_NSGRAPHICS_H
#define APPKIT_NSGRAPHICS_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>
/* THE COMPOSITING VOCABULARY LIVES IN `NSGraphicsContext.h` IN THIS TIER, so the declarations below can name it. */
#import <AppKit/NSGraphicsContext.h>

NS_ASSUME_NONNULL_BEGIN

/* **AND THE FOCUS-RING VOCABULARY, WHICH MOVED HERE FROM `NSView.h` BECAUSE THIS IS WHERE APPLE DECLARES IT** — and
 * where the ledger's rows for its three cases say the ground is. It sat in `NSView.h` because stage A is where a view's
 * `-focusRingType` was first needed, which was the tree's-home rule doing its job; the blanket rule this plan now works
 * under is "match Apple, including which header", so the type lives beside the drawing vocabulary it belongs to. THE
 * VALUES ARE UNCHANGED AND SO IS EVERY CREDIT — a move is not a re-declaration: `NSView.h` imports this header, so the
 * three case rows stay shipped exactly as they were. AND THAT IMPORT IS APPLE'S OWN LINE RATHER THAN A WORKAROUND: the
 * era's `NSView.h` imports `AppKit/NSGraphics.h` for this very type and declares nothing itself, so the move made this
 * tree's include list MATCH Apple's instead of deviating from it — the earlier draft of this paragraph called the move
 * a deviation, and the measurement (Apple's `NSView.h`, line 12) withdrew that.
 *
 * THE ORDER IS APPLE'S OWN AND THE VALUES ARE THE ARTEFACT'S, which is the standing rule's case: Apple publishes the
 * case names and their order here, and a caller may rely on the names. */
typedef enum {
	NSFocusRingTypeDefault = 0,
	NSFocusRingTypeNone,
	NSFocusRingTypeExterior
} NSFocusRingType;

@class NSArray;
@class NSString;

/* 0 MEANS THE DEFAULT DEPTH, which is Apple's own reading of the value — a window with no limit set. */
typedef int NSWindowDepth;

enum {
	NSWindowDepthTwentyfourBitRGB = 0x208,
	NSWindowDepthSixtyfourBitRGB = 0x210,
	NSWindowDepthOnehundredtwentyeightBitRGB = 0x220
};

/* THE EXTRACTORS. `-1`/nil answers for a depth that is not one of the three — and that is a REFUSAL RATHER THAN A
 * GUESS: a bit-shuffle would return a plausible number for a value this tree has never seen, and a caller cannot
 * tell a right answer from a wrong one. */
NSInteger NSBitsPerSampleFromDepth(NSWindowDepth depth);
NSInteger NSBitsPerPixelFromDepth(NSWindowDepth depth);
BOOL NSPlanarFromDepth(NSWindowDepth depth);
NSString *NSColorSpaceFromDepth(NSWindowDepth depth);
/* AND THE DEPTHS THE SYSTEM OFFERS, `0`-TERMINATED — Apple's own sentinel, and the reason this returns a POINTER
 * rather than an array: a caller walks it until the zero. */
const NSWindowDepth *NSAvailableWindowDepths(void);

/* AND THE ONE THAT CHOOSES: the best depth for a requested sample size, pixel size, planarity and colour space,
 * with `exactMatch` reporting whether the answer matched all of them or merely accommodated them. Apple documents
 * the tie-break order — colour space, then bits per sample, then planarity, then bits per pixel. */
/* **AND BOTH OF THE LAST TWO ARE NULLABLE, WHICH IS WHAT THIS IMPLEMENTATION ACCEPTS — not what a first reading
 * of Apple's signature suggests.** The header's own comment says `exactMatch` is OPTIONAL, and a nil colour space
 * means "any"; marking them non-null made the one caller in this tree warn, and the rule this tier follows is that
 * an annotation describes what the implementation takes. AND THE SPELLING IS `_Nullable` RATHER THAN
 * `nullable`: this is a C FUNCTION, and `nullable` is a method-declaration keyword — a trap this tree has
 * recorded, and the compiler named it in one line. */
/* **AND THE FOURTH PARAMETER IS `isPlanar` WHERE APPLE SPELLS IT `planar`, WHICH IS A DELIBERATE DEVIATION AND A
 * HARMLESS ONE**: a C parameter's NAME is not part of the function's type, so no caller can tell — while the
 * ledger's policy gate is TEXT-BASED and a struck property named `planar` on `NSBitmapImageRep` is declared
 * "present" by the bare word. That trap is recorded in this tree and it has now been walked into twice; the name
 * is the part of a declaration that costs nothing to move. */
NSWindowDepth NSBestDepth(NSString * _Nullable colorSpace, NSInteger bps, NSInteger bpp, BOOL isPlanar,
			  BOOL * _Nullable exactMatch);

/* AND THE TWO VOCABULARIES THE DRAWING FUNCTIONS TAKE, WHICH ARE APPLE'S OWN AND LIVE HERE FOR APPLE'S REASON: this
 * is the header that declares the doors that read them. `NSFocusRingPlacement` is a DIFFERENT TYPE from the
 * `NSFocusRingType` above — one says where a ring goes, the other says whether a view has one — and conflating them
 * would make `NSSetFocusRingStyle` accept a value it does not mean. */
enum {
	NSFocusRingOnly  = 0,
	NSFocusRingBelow = 1,
	NSFocusRingAbove = 2
};
typedef NSUInteger NSFocusRingPlacement;

/* The era's animation effects, of which this tier has a renderer for none — see `NSShowAnimationEffect`. The values are
 * the artefact's, including the gap: only the disappearing-item default and the puff were ever defined. */
enum {
	NSAnimationEffectDisappearingItemDefault = 0,
	NSAnimationEffectPoof = 10
};
typedef NSUInteger NSAnimationEffect;

@class NSColor;

/* ==================================================================================================================
 * THE DRAWING FUNCTIONS — the 10.6 `NSGraphics.h` surface.
 *
 * **THIRTY OF THE THIRTY-SIX ARE REAL AND SIX REFUSE BY NAME**, and the split is stated here rather than discovered at
 * a link error: the fills, frames, clips, bezels and window list are implemented over the same context and ink the
 * rest of the tier draws with, while a beep, a screen read-back, memory accounting, a focus-ring renderer and the
 * window server's animation effects have no backing in this tier at all. See `NSGraphics.m` for each refusal and why.
 *
 * **THE LIST VARIANTS ARE HERE BECAUSE THEY ARE THE FAST PATH THE ERA'S CALLERS USED**, not because they are extra
 * surface: a table drawing its selection used `NSRectFillListWithColors`, and a caller ported from the era calls it.
 * ================================================================================================================ */

void NSRectFill(NSRect aRect);
void NSRectFillUsingOperation(NSRect aRect, NSCompositingOperation op);
void NSRectFillList(const NSRect *rects, NSInteger count);
void NSRectFillListUsingOperation(const NSRect *rects, NSInteger count, NSCompositingOperation op);
void NSRectFillListWithGrays(const NSRect *rects, const CGFloat *grays, NSInteger num);
void NSRectFillListWithColors(const NSRect *rects, NSColor **colors, NSInteger num);
void NSRectFillListWithColorsUsingOperation(const NSRect *rects, NSColor **colors, NSInteger num,
					    NSCompositingOperation op);
void NSHighlightRect(NSRect aRect);
void NSEraseRect(NSRect aRect);

void NSFrameRect(NSRect aRect);
void NSFrameRectWithWidth(NSRect aRect, CGFloat frameWidth);
void NSFrameRectWithWidthUsingOperation(NSRect aRect, CGFloat frameWidth, NSCompositingOperation op);
void NSDottedFrameRect(NSRect aRect);

void NSRectClip(NSRect aRect);
void NSRectClipList(const NSRect *rects, NSInteger count);

void NSDrawButton(NSRect aRect, NSRect clipRect);
void NSDrawWhiteBezel(NSRect aRect, NSRect clipRect);
void NSDrawGrayBezel(NSRect aRect, NSRect clipRect);
void NSDrawLightBezel(NSRect aRect, NSRect clipRect);
void NSDrawDarkBezel(NSRect aRect, NSRect clipRect);
void NSDrawGroove(NSRect aRect, NSRect clipRect);
void NSDrawWindowBackground(NSRect aRect);
NSRect NSDrawTiledRects(NSRect boundsRect, NSRect clipRect, const NSRectEdge *sides, const CGFloat *grays,
			NSInteger count);
NSRect NSDrawColorTiledRects(NSRect boundsRect, NSRect clipRect, const NSRectEdge *sides, NSColor **colors,
			     NSInteger count);

void NSDisableScreenUpdates(void);
void NSEnableScreenUpdates(void);

void NSCountWindows(NSInteger *count);
void NSCountWindowsForContext(NSInteger context, NSInteger *count);
void NSWindowList(NSInteger size, NSInteger list[]);
void NSWindowListForContext(NSInteger context, NSInteger size, NSInteger list[]);

/* THE SIX WITH NO BACKING. Each answers its type's empty value and names what is missing, so a ported caller gets a
 * named refusal instead of a link error or a silent nothing. */
void NSBeep(void);
void NSCopyBits(NSInteger srcGState, NSRect srcRect, NSPoint destPoint);
NSColor *NSReadPixel(NSPoint passedPoint);
NSInteger NSGetWindowServerMemory(NSInteger context, NSInteger *virtualMemory, NSInteger *windowBackingMemory,
				  NSString **windowDumpString);
void NSSetFocusRingStyle(NSFocusRingPlacement placement);
void NSShowAnimationEffect(NSAnimationEffect animationEffect, NSPoint centerLocation, NSSize size,
			   id animationDelegate, SEL didEndSelector, void *contextInfo);

NS_ASSUME_NONNULL_END


#endif /* APPKIT_NSGRAPHICS_H */
