/*
 * AGToolTipWindow.h — the little plate that says what a control is for, and the engine that decides when to show one.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **A TOOL TIP IS TWO THINGS THAT MUST NOT BE CONFUSED: A REGION THAT HAS ONE, AND A PLATE THAT SHOWS IT.** The region is
 * `NSView`'s (`-setToolTip:`, `-addToolTipRect:owner:userData:`); the plate is this file. Which means the plate knows
 * nothing about views, windows or pointers — it is handed a string and a point on the screen and it appears there — and
 * the engine knows nothing about drawing: it is told "the pointer is over this string at this point" on every motion, it
 * waits, and it either shows the plate or drops it.
 *
 * WHY THE WAIT IS THE ENGINE'S AT ALL. A tip that appeared the instant the pointer crossed a control would flash across
 * every one on the way to where the user was going; a tip that appeared when the pointer came to rest is the behaviour
 * every desktop has and the reason this class is a delay and a plate rather than a drawing routine. See `fn_show:`.
 *
 * THE PLACEMENT IS ONE SUBTRACTION, like the candidate window's: the plate's TOP-LEFT corner sits at the pointer, so it
 * hangs below and to the right of the thing it describes and never covers the words under the pointer.
 */
#ifndef APPKIT_AGTOOLTIPWINDOW_H
#define APPKIT_AGTOOLTIPWINDOW_H

#import <AppKit/NSWindow.h>

NS_ASSUME_NONNULL_BEGIN

/* **THE PLATE ITSELF: A BORDERLESS WINDOW AS TALL AS ITS ONE LINE OF TEXT.** It is not activatable and it floats, because
 * a tool tip belongs to whatever window the pointer is over and must never take the keyboard from it — the same two
 * sentences the candidate window and a menu panel say, for the same reason. */
@interface AGToolTipWindow : NSWindow

/* Sizes the window to the words: one line, the tool tip font, plus the plate's own air. */
- (void)setTip:(nullable NSString *)tip;
- (nullable NSString *)tip;
- (NSSize)cg_plateSize;

@end

/* **AND THE ENGINE, WHICH IS THE DELAY, THE ONE PLATE, AND THE ONE TIP IT IS SHOWING.** One per application: two tips up
 * at once would be two answers to the same question, and a `-hideTip` that had to find "the right one" is the bug this
 * shape prevents. The window it was asked on behalf of is remembered only so that a window going away takes its own tip
 * with it and nobody else's. */
@interface AGToolTipController : NSObject

+ (AGToolTipController *)sharedController;

/* **THE POINTER'S NEWS, ON EVERY MOTION: the string under it, and where the plate should hang from.** A nil or empty
 * string means "nothing here", which is the same door a caller uses to make the tip go away — the arrow moving off a
 * control is not an event the engine could tell apart from the pointer resting on one, so it is exactly this call with
 * nothing in it. */
- (void)showTip:(nullable NSString *)tip fromWindow:(nullable NSWindow *)window atScreenPoint:(NSPoint)point;

/* Drops the plate and any pending one. */
- (void)hideTip;

/* **AND ONLY THE TIP THIS WINDOW ASKED FOR** — a window that resigns key or goes away calls this, and a tip belonging to
 * a different window is left alone: a click in one window must not drop another's tip that is still true. */
- (void)hideTipForWindow:(nullable NSWindow *)window;

/* Whether a plate is ON THE SCREEN right now (a pending one is not). The tests read this to tell the delay from the show. */
- (BOOL)isShowingTip;

/* **AND THE PLATE ITSELF, WHICH IS THE ENGINE'S OWN STATE RATHER THAN A PUBLIC DOOR.** Nothing in the tier needs it — the
 * engine places and drops its own window — but a test with no display cannot find the plate in the application's window
 * list, because a window that was never registered is not in it, and "where did it appear" is a question worth asking. */
- (nullable AGToolTipWindow *)cg_plateWindow;

@end

NS_ASSUME_NONNULL_END
#endif /* APPKIT_AGTOOLTIPWINDOW_H */
