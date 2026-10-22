/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSTrackingArea.h — a REGION of a view that wants the pointer's news, and the owner who wants it (stage E).
 *
 * **AN AREA ANSWERS THREE QUESTIONS THAT `-hitTest:` CANNOT.** A hit test says which VIEW the pointer is over. An
 * area says which REGION of which view, WHOSE callbacks it fires, and WHEN the region is live at all — and those are
 * three separate facts, which is why this class is those three plus a dictionary and nothing else:
 *
 *   * THE REGION is `-rect`, in the view's own coordinates — or, when `NSTrackingInVisibleRect` is set, THE VIEW'S
 *     VISIBLE RECT and the stored rect is not read at all (Apple's own rule: "the rect is ignored").
 *   * THE OWNER is `-owner`, and IT IS NOT THE VIEW. That is the point of the door: one object can own areas in
 *     several views, and `-userInfo` is how one owner tells its areas apart when the callbacks arrive. THE OWNER IS
 *     NOT RETAINED (Apple says so, and the same rule this tree applies to every target and back-reference).
 *   * WHEN IT IS LIVE is the four `Active…` bits below. **AND THE DEFAULT IS THE ONE THIS WHOLE CLASS WAS WORTH
 *     WRITING: an area with none of the four set behaves as `NSTrackingActiveInKeyWindow`**, so a button in a window
 *     that is not key does NOT prelight. Before this class, the tier synthesised the pointer's crossing for the
 *     deepest view of whatever window the pointer was over, and a BACKGROUND WINDOW'S BUTTONS LIT UP — measured on
 *     the desktop, and the reason the option word is not decoration here.
 *
 * WHAT AN AREA DOES NOT DO, STATED RATHER THAN IMPLIED. It does not DRAW: an owner that wants its face changed is
 * told the pointer arrived and repaints itself. And it does not follow the view's geometry by itself: `-rect` is in
 * the view's coordinates and the WINDOW resolves it against the view's current position on every motion, which is
 * why a moving view needs no bookkeeping and a RESIZING one only needs `-updateTrackingAreas` for the
 * `NSTrackingInVisibleRect` case (`-visibleRect` is computed, not stored, so even that is free here).
 *
 * THE OPTIONS ARE THE ERA'S, transcribed from the 10.6 header rather than recalled, and ALL TEN ARE HONOURED — there
 * is no refused bit in this class, which is worth saying because it is rare in this tier.
 */
#ifndef APPKIT_NSTRACKINGAREA_H
#define APPKIT_NSTRACKINGAREA_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* **THE OPTION WORD. FOUR GROUPS, AND EACH GROUP IS A DIFFERENT KIND OF QUESTION** — which callbacks, when the area
 * is live, and two flags about how it starts and what it follows. The values are bit positions in one word, so the
 * groups compose; the four `Active…` bits are MUTUALLY EXCLUSIVE and the last one set wins if a caller sets two. */
enum {
	/* WHICH CALLBACKS. `NSTrackingMouseEnteredAndExited` is the pair a prelight is made of; `NSTrackingMouseMoved`
	 * is every motion WITHIN the area, which is a much louder channel; `NSTrackingCursorUpdate` is the owner's
	 * chance to set a cursor for the region. */
	NSTrackingMouseEnteredAndExited		= 0x01,
	NSTrackingMouseMoved			= 0x02,
	NSTrackingCursorUpdate			= 0x04,

	/* **WHEN THE AREA IS LIVE — AND THIS GROUP IS WHY THE CLASS EXISTS.** Apple's scope is about the APP and the
	 * WINDOW rather than the pointer, so the same button behaves correctly in a background window without any view
	 * having to ask whether its window is key. NONE SET MEANS `NSTrackingActiveInKeyWindow`. */
	NSTrackingActiveWhenFirstResponder	= 0x10,
	NSTrackingActiveInKeyWindow		= 0x20,
	NSTrackingActiveInActiveApp		= 0x40,
	NSTrackingActiveAlways			= 0x80,

	/* AND THE TWO ODD BITS. `NSTrackingAssumeInside` makes the area START inside, so the owner's first message is a
	 * `-mouseExited:` as the pointer leaves a region it was never seen to enter — the idiom for refreshing a face
	 * whose state was already true when the area appeared. `NSTrackingInVisibleRect` REPLACES `-rect` with the view's
	 * `-visibleRect`, which is what a SCROLLED view needs (`-rect` is in the view's coordinates, and the visible part
	 * of a view inside a clip view moves under the view's feet). */
	NSTrackingAssumeInside			= 0x100,
	NSTrackingInVisibleRect			= 0x200,

	/* AND `NSTrackingEnabledDuringMouseDrag`, which is the one bit whose absence is a behaviour rather than an
	 * error: a DRAG usually belongs to whoever began it, so an area that would otherwise fire enter/exit as the
	 * pointer sweeps across it stays quiet unless it asked for this. */
	NSTrackingEnabledDuringMouseDrag	= 0x400
};

typedef NSUInteger NSTrackingAreaOptions;

@interface NSTrackingArea : NSObject <NSCopying, NSCoding>
{
	NSRect _rect;			/* in the VIEW's coordinates; not read at all when InVisibleRect is set */
	NSTrackingAreaOptions _options;
	id _owner;			/* NOT RETAINED: this tree's rule for every back-reference to a caller's object */
	id _userInfo;			/* RETAINED: the area owns the dictionary it was handed */
	/* AND WHETHER THE POINTER IS INSIDE IT RIGHT NOW, which is the one piece of LIVE state the area carries. It is
	 * kept HERE rather than in a set on the window for two reasons: it is per-area (so two areas in one view are
	 * independent), and it dies WITH the area, so a view that is removed from the hierarchy can never leave the
	 * window holding a stale "inside" verdict about a region that no longer exists. */
	BOOL _cg_inside;
}

/* **THE ONE CONSTRUCTOR, AND IT ANSWERS NIL FOR THE ONE THING THAT CANNOT BE DONE.** Apple's own sentence is that a
 * nil owner is not an area — there is nobody to tell — so the initialiser DECLINES rather than making an object whose
 * callbacks go nowhere. Everything else is stored: a rect of any size (a zero rect is a legitimate area that never
 * matches), any word of options (including a word with no bits, which is a live area that wants no callbacks). */
- (nullable instancetype)initWithRect:(NSRect)rect options:(NSTrackingAreaOptions)options
				owner:(nullable id)owner userInfo:(nullable NSDictionary *)userInfo;

/* THE FOUR READ-BACK DOORS, each answering what the constructor was told. `-rect` answers the STORED rect even when
 * the area follows the visible rect, because that is what Apple's door does: the flag is the caller's to read, and a
 * door that answered a different rectangle depending on an option bit would be answering two questions at once. */
- (NSRect)rect;
- (NSTrackingAreaOptions)options;
- (nullable id)owner;
- (nullable NSDictionary *)userInfo;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSTRACKINGAREA_H */
