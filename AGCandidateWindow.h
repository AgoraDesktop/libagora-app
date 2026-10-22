/*
 * AGCandidateWindow.h — THE WINDOW A CANDIDATE LIST IS SHOWN IN, PLACED AT THE CARET.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A CANDIDATE LIST IS A WINDOW BECAUSE IT MUST SIT OVER THE DOCUMENT, NOT IN IT.** The four questions
 * `NSTextInput` makes a text view answer exist for this object: `-firstRectForCharacterRange:` is the caret's
 * rectangle IN SCREEN COORDINATES, so the window is placed under the caret without this class knowing anything about
 * the view's own geometry, and `-invalidateCharacterCoordinates` is the view saying the caret has moved — which is
 * this window's cue to move with it.
 *
 * **IT IS BORDERLESS AND NEVER KEY.** The person is typing into the TEXT VIEW, and a window that took the keyboard
 * would swallow the very keys the input method is composing with; the window is a picture of the readings and the
 * keys stay with the document. `-showCandidates:selected:` sizes the window from the list, places it under the caret
 * and orders it in; `-hideCandidates` takes it away.
 */
#ifndef AG_CANDIDATE_WINDOW_H
#define AG_CANDIDATE_WINDOW_H

#import <AppKit/NSWindow.h>

@class AGCandidateListView;
@protocol NSTextInput;

NS_ASSUME_NONNULL_BEGIN

@interface AGCandidateWindow : NSWindow
{
@private
	/* **THE CLIENT IS BORROWED**, like every back-pointer in this tree: the text view outlives the candidate window
	 * and owns the caret this window is placed at. */
	id <NSTextInput> _client;	/* NOT RETAINED */
	AGCandidateListView *_listView;	/* RETAINED; also the window's content view */
}

- (instancetype)initWithClient:(id <NSTextInput>)client;
- (nullable id <NSTextInput>)client;

/* THE VIEW THE READINGS ARE DRAWN IN, so a caller that wants to hit-test a click asks the list rather than the
 * window. */
- (AGCandidateListView *)candidateListView;

/* **THE TWO THINGS THE WINDOW IS FOR.** Show sizes itself from the readings, places itself under the caret and orders
 * in; hide takes it away. The selection is the caller's to move, and moving it repaints. */
- (void)showCandidates:(NSArray *)candidates selected:(NSInteger)index;
- (void)hideCandidates;
- (NSInteger)selectedIndex;
- (void)setSelectedIndex:(NSInteger)index;

/* **AND THE CARET MOVED, WHICH IS THE ONE THING A CANDIDATE WINDOW MUST FOLLOW.** It re-asks the client where the
 * caret is and moves there without rebuilding the list. */
- (void)invalidatePlacement;

@end

NS_ASSUME_NONNULL_END

#endif /* AG_CANDIDATE_WINDOW_H */
