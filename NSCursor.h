/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSCursor.h — the pointer's image and hot spot, and the stack of cursors a view pushes (stage B).
 *
 * WHAT THIS CLASS OWNS IS THE STATE, NOT THE PIXELS. A cursor is an image plus the point in it that is the
 * pointer's tip, and everything else here — the stack, the push/pop pair, the two flags that make a cursor
 * apply itself when the mouse crosses a view — is bookkeeping this class can do completely on its own. The
 * PIXELS ON THE SCREEN are the window server's, so nothing here draws: the window's own resolution hands the top of
 * this stack to the display seam as a NAME (see `-name` below, and `AGWindowSetCursor`), and the compositor draws it.
 *
 * AND THAT IS WHY THE SYSTEM CURSORS HAVE NO IMAGE, WHICH IS THE DEVIATION WORTH READING. `+arrowCursor`
 * and its siblings answer a SHARED INSTANCE — one per class, created on first ask, which is what Apple's do —
 * and their `-image` answers nil, because the arrow's pixels are the server's to supply and there is no server yet.
 * Apple's contract for these is the shared OBJECT, and a caller that wants to compare, push or set one gets
 * exactly what it asked for; a caller that wants the bitmap gets the truth instead of a fabricated rectangle.
 * `-image` is therefore annotated NULLABLE, which is the standing rule for these headers: the annotation says what
 * the implementation answers.
 *
 * **AND AN IMAGE THAT IS NIL IS WHY THE NAME HAD TO BE ADDED.** Twenty-one shared objects with no image are
 * indistinguishable to a display, so until recently installing the right one for a link changed nothing anywhere —
 * the answer died in this class. `-name` is what crosses: the Xcursor vocabulary the desktop's theme is written in,
 * resolved by the compositor into artwork at its own scale. That is a shape and not a bitmap, and it is the whole of
 * what a system cursor carries to the glass; its pixels stay the theme's business, which is the point.
 *
 * AND THE THREE DOORS THAT HIDE THE POINTER ARE DELIBERATELY ABSENT — `+hide`, `+unhide` and
 * `+setHiddenUntilMouseMoves:`. They take no argument and return nothing, so without a server they are
 * UNOBSERVABLE: a probe could call them and assert nothing, which is the "a check that cannot fail" trap
 * this tree warns about. They land with the seam, where they can be seen.
 */
#ifndef APPKIT_NSCURSOR_H
#define APPKIT_NSCURSOR_H

#import <Foundation/Foundation.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>

NS_ASSUME_NONNULL_BEGIN


/* THE ONE VERSION NUMBER, WHICH IS A `#define` WITH ITS VALUE IN THE ERA HEADER (`682.0`) — the second of
 * the two such constants this stage has met, and transcribed for the same reason NSAppKitVersionNumberWith-
 * PatternColorLeakFix was: a version constant's value IS published here. */
#define NSAppKitVersionNumberWithCursorSizeSupport 682.0

@interface NSCursor : NSObject
{
	NSImage *_image;		/* RETAINED; nil for a system cursor, whose pixels are the server's */
	NSPoint _hotSpot;
	/* RETAINED; the Xcursor name the compositor resolves into artwork, or nil for a cursor no theme can supply. */
	NSString *_name;
	BOOL _onMouseEntered;
	BOOL _onMouseExited;
}

/* THE TWO WAYS TO MAKE ONE. The hint variant's two colours are ADVISORY — Apple documents them as hints to
 * the window server for a cursor drawn over an unknown background — so they are accepted and not stored,
 * which is stated here rather than discovered. */
- (instancetype)initWithImage:(NSImage *)newImage hotSpot:(NSPoint)point;
- (instancetype)initWithImage:(NSImage *)newImage
	   foregroundColorHint:(nullable NSColor *)fg
	   backgroundColorHint:(nullable NSColor *)bg
		      hotSpot:(NSPoint)point;

@property (readonly, nullable) NSImage *image;
@property (readonly) NSPoint hotSpot;

/* THE STACK. `-set` puts this cursor up without remembering what was there; `-push` remembers first, and
 * `+pop` takes the last remembered one back — which is how a view shows a resize cursor while it drags and
 * puts the caller's cursor back when it is done. */

/* ============================================================================================ *
 * THE HIDE COUNTER. Apple's pair is a COUNT, not a flag: `+hide` increments and `+unhide`          *
 * decrements, so two nested hides need two unhides and a caller that unhides more than it hid      *
 * does not make the pointer appear twice over. That is why this is a counter with a FLOOR at        *
 * zero rather than a boolean.                                                                      *
 *                                                                                                 *
 * **AND THE "UNTIL THE MOUSE MOVES" HALF CANNOT BE HONOURED HERE, WHICH IS A STATED DEVIATION.**    *
 * Apple clears that hide when the pointer MOVES, and this layer has no event source — the display  *
 * and event seam is stage C. So the flag persists until a caller clears it, and the header says    *
 * so rather than implying a timer that does not exist.                                             *
 *                                                                                                 *
 * `+cg_isHidden` IS A PRIVATE SEAM AND IT IS HERE FOR A REASON WORTH NAMING: the era index has NO  *
 * public door for the hidden state, so without it the three doors above would be UNASSERTABLE —   *
 * the tree's rule is that a probe asserts behaviour rather than a symbol, and behaviour nobody    *
 * can observe cannot be asserted. It is also what stage C's seam will read.                        *
 * ============================================================================================ */

+ (void)hide;
+ (void)unhide;
+ (void)setHiddenUntilMouseMoves:(BOOL)flag;

- (void)push;
- (void)pop;
- (void)set;
+ (void)pop;
+ (nullable NSCursor *)currentCursor;
+ (nullable NSCursor *)currentSystemCursor;

/* AND THE FLAGS THAT MAKE A CURSOR APPLY ITSELF, AND THEY PAIR: with `-setOnMouseEntered:` the cursor
 * PUSHES itself when the mouse enters a view that has it installed, and with `-setOnMouseExited:` it POPS
 * when the mouse leaves — so a view that only sets the two flags gets a balanced push and pop without
 * touching the stack itself. */
- (void)setOnMouseEntered:(BOOL)flag;
- (void)setOnMouseExited:(BOOL)flag;
@property (readonly) BOOL isSetOnMouseEntered;
@property (readonly) BOOL isSetOnMouseExited;
- (void)mouseEntered:(NSEvent *)theEvent;
- (void)mouseExited:(NSEvent *)theEvent;

/* THE SHARED SYSTEM CURSORS, one instance each, created on first ask. Their `-image` is nil: see above. */
+ (NSCursor *)arrowCursor;
+ (NSCursor *)IBeamCursor;
+ (NSCursor *)pointingHandCursor;
+ (NSCursor *)closedHandCursor;
+ (NSCursor *)openHandCursor;
+ (NSCursor *)resizeLeftCursor;
+ (NSCursor *)resizeRightCursor;
+ (NSCursor *)resizeLeftRightCursor;
+ (NSCursor *)resizeUpCursor;
+ (NSCursor *)resizeDownCursor;
+ (NSCursor *)resizeUpDownCursor;
+ (NSCursor *)crosshairCursor;
+ (NSCursor *)disappearingItemCursor;
+ (NSCursor *)operationNotAllowedCursor;
+ (NSCursor *)dragLinkCursor;
+ (NSCursor *)dragCopyCursor;
+ (NSCursor *)contextualMenuCursor;

/* ============================================================================================ *
 * THE TWO DIAGONAL RESIZE CURSORS, WHICH APPLE HAS AND DOES NOT PUBLISH.                        *
 *                                                                                                 *
 * **A WINDOW'S CORNER IS A RESIZE HANDLE AND ITS CURSOR IS NOT ONE OF THE ERA'S PUBLIC ONES.**    *
 * `+resizeLeftRightCursor` and `+resizeUpDownCursor` are the only resize shapes 10.6 declares,   *
 * so a window that resolves its own edges has nothing diagonal to answer at a corner — Apple      *
 * keeps those in private CGS cursors, which is why the public surface looks complete and is not.  *
 * MEASURED here before this pair existed: the pointer over a resizable window's corner was the    *
 * ARROW, while a press there started a resize — the one place in the tier where the pointer was   *
 * deliberately wrong about what a click would do.                                                *
 *                                                                                                 *
 * THEY ARE `cg_` DOORS FOR THE SAME REASON `+cg_isHidden` IS: not Apple's API, this tier's, and   *
 * named so a reader cannot mistake them for a selector of the era. The names are the theme's own — *
 * `nwse-resize` and `nesw-resize` — so the compositor draws them out of the same Vimix artwork    *
 * every other pointer here comes from, and their pixels are the server's like every shared         *
 * cursor's. `NWSE` runs from the top-left corner to the bottom-right; `NESW` the other way.       *
 * ============================================================================================ */
+ (NSCursor *)cg_resizeNorthWestSouthEastCursor;
+ (NSCursor *)cg_resizeNorthEastSouthWestCursor;

/* **THE NAME THE COMPOSITOR KNOWS THIS POINTER BY, WHICH IS WHAT MAKES A CURSOR VISIBLE AT ALL.** `_image` is nil for
 * every system cursor — the pixels are the window server's — so before the name existed an `NSCursor` carried NOTHING a
 * display could act on: twenty-one distinct objects that were indistinguishable on the wire, which is why installing the
 * right one for a link changed nothing on the glass. The name is the Xcursor vocabulary the desktop's theme is written
 * in (`left_ptr`, `text`, `pointer`, `crosshair`, `not-allowed`, `nwse-resize` …), so it is a SHAPE and not a bitmap:
 * the compositor picks the artwork and the size for its own dots per inch (`AGWindowSetCursor` in
 * `platform/AGWindowServer.h`).
 *
 * **NIL IS A REAL ANSWER.** A cursor made from an image — `-initWithImage:hotSpot:`, which is what a custom pointer will
 * be when the compositor can carry pixels — has no name in any theme, and neither does a system cursor this tier does
 * not know. The window then asks for the compositor's DEFAULT rather than inventing a shape, so a custom image cursor
 * shows the theme's arrow for now: its pixels cannot cross yet, and an arrow is the honest "nothing special" rather
 * than a pointer that vanishes. The table lives in `NSCursor.m` beside the class methods it maps. */
@property (readonly, nullable) NSString *name;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCURSOR_H */
