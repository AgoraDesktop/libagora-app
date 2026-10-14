/*
 * AGChromeTheme.h — the window chrome's control graphics, read from an XFWM theme when one resolves.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * WHAT THIS IS, AND WHY IT IS NOT IN THE LIBRARY'S RESOURCES. Agora draws its window chrome itself — the window
 * server draws no title bar — and the marks it draws are procedural. This class is the other source for them: an
 * XFWM THEME, whose `.xpm` buttons are named by the button and the STATE (`close-active.xpm`, `hide-prelight.xpm`,
 * …). The theme is a set of FILES ON DISK and never part of this library, because a theme is somebody else's work
 * under somebody else's licence — the one this was built against is GPL — and linking or bundling it would put that
 * licence on Agora. Read at runtime it is data, and Agora's MIT is untouched; the theme's own provenance travels
 * with the theme.
 *
 * IT IS A SINGLETON BECAUSE THE THEME IS A PROCESS-WIDE FACT. The frame-to-content arithmetic is a CLASS method
 * (`+contentRectForFrameRect:styleMask:`) with no window to ask, so the title bar's height has to be answerable
 * without an instance — and the height comes from the theme. Resolved once, on first use; a program that sets
 * `AGORA_CHROME_THEME` after the first window is asking for something the process has already decided.
 *
 * WHERE A THEME IS FOUND. `$AGORA_CHROME_THEME`, which may be the directory the `.xpm` files are in OR a theme
 * root with an `xfwm4/` inside it; then `$XDG_DATA_HOME/agora/chrome/xfwm4` (or `~/.local/share/agora/chrome/
 * xfwm4`). No theme resolving is not an error: the chrome falls back to the marks `NSWindow` draws.
 */
#ifndef AGORA_AGCHROMETHEME_H
#define AGORA_AGCHROMETHEME_H

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGImage.h>

NS_ASSUME_NONNULL_BEGIN

/* THE FOUR BUTTONS, IN THE ORDER THE CHROME LAYS THEM OUT AT THE LEFT, EXCEPT `Menu`, WHICH IS THE ONE AT THE
 * RIGHT. XFWM calls them close / hide / maximize / menu; Agora's third mark is a plus (zoom) and its right-hand
 * control is the toolbar pill, and both are drawn from the matching XFWM file — `menu` is what the pill is. */
typedef NS_ENUM(NSInteger, AGChromeButton) {
	AGChromeButtonClose = 0,
	AGChromeButtonHide = 1,
	AGChromeButtonMaximize = 2,
	AGChromeButtonMenu = 3,
	AGChromeButtonCount = 4
};

/* THE FOUR STATES XFWM SHIPS, WHICH ARE ALSO THE FOUR THE CHROME HAS: a window that is key and one that is not,
 * and the two the pointer makes while it is over a button. */
typedef NS_ENUM(NSInteger, AGChromeButtonState) {
	AGChromeButtonStateActive = 0,
	AGChromeButtonStateInactive = 1,
	AGChromeButtonStatePrelight = 2,
	AGChromeButtonStatePressed = 3,
	AGChromeButtonStateCount = 4
};

/* **THE PIECES A THEME DRAWS THE TITLE BAR ITSELF FROM, WHICH ARE THE PART THAT IS NOT A BUTTON.** XFWM composes
 * the bar from a CORNER at each end, a strip of TITLE pieces between them (`title-1` … `title-5`, cycled), and
 * the buttons on top — so reading only the button files leaves the theme's own bar background unread and the
 * buttons sit on this tier's flat grey instead of on the surface they were drawn for. There is no POINTER state
 * here: a bar does not prelight, so a piece is active or inactive and nothing else. */
typedef NS_ENUM(NSInteger, AGChromeFramePiece) {
	AGChromeFrameTopLeft = 0,
	AGChromeFrameTopRight = 1,
	AGChromeFrameTitle1 = 2,
	AGChromeFrameTitle2 = 3,
	AGChromeFrameTitle3 = 4,
	AGChromeFrameTitle4 = 5,
	AGChromeFrameTitle5 = 6,
	AGChromeFramePieceCount = 7
};

@interface AGChromeTheme : NSObject
{
	NSString *_directory;			/* RETAINED: the directory the `.xpm` files are read from */
	CGFloat _titleBarHeight;
	CGFloat _buttonOffset;
	CGFloat _buttonSpacing;
	NSSize _buttonSize;
	/* ONE CACHED IMAGE PER BUTTON AND STATE, or NULL where the theme has none. Each is RETAINED here and
	 * RETURNED BORROWED — a caller draws it and must not release it. */
	CGImageRef _images[AGChromeButtonCount][AGChromeButtonStateCount];
	BOOL _probed[AGChromeButtonCount][AGChromeButtonStateCount];
	/* THE TITLE BAR'S OWN PIECES, cached the same way: one image per piece and per ACTIVE/INACTIVE. */
	CGImageRef _frameImages[AGChromeFramePieceCount][2];
	BOOL _frameProbed[AGChromeFramePieceCount][2];
}

/* NIL WHEN NO THEME RESOLVES, which is the ordinary case and not a failure. */
+ (nullable instancetype)sharedTheme;

@property (readonly, copy) NSString *directory;
@property (readonly) CGFloat titleBarHeight;	/* the whole strip, from the theme's own images */
@property (readonly) CGFloat buttonOffset;		/* the strip's padding, from themerc's `button_offset` */
@property (readonly) CGFloat buttonSpacing;		/* between buttons, from themerc's `button_spacing` */
@property (readonly) NSSize buttonSize;		/* the close button's own size, when the theme has one */

/* BORROWED, AND CACHED. A state the theme does not ship falls back within its own family — `pressed` to
 * `prelight`, either to `active`/`inactive` — so a theme with two graphics per button still draws four states.
 * NULL when the button has no image at all, which is the caller's cue to draw its own mark. */
- (nullable CGImageRef)imageForButton:(AGChromeButton)button state:(AGChromeButtonState)state;

/* BORROWED, AND CACHED, like the buttons. NULL when the theme has no such piece, which is the caller's cue to
 * leave that part of the bar in the frame colour it would otherwise have. */
- (nullable CGImageRef)framePiece:(AGChromeFramePiece)piece active:(BOOL)active;

@end

/* THE CLASS-METHOD FORM OF THE STRIP'S HEIGHT, for `+contentRectForFrameRect:styleMask:`, which has no window to
 * ask. Zero when no theme resolves, which is the caller's cue to use its own constant. */
CGFloat AGChromeThemeTitleBarHeight(void);

NS_ASSUME_NONNULL_END

#endif /* AGORA_AGCHROMETHEME_H */
