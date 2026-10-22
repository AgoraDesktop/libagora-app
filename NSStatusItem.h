/*
 * NSStatusItem.h — one item in the status area, placed by the server.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **WHAT AN ITEM IS, AND WHY THERE IS NO POSITION ANYWHERE IN THIS FILE.** An item has a LENGTH — how wide it is —
 * and a view, a title, an image, a menu, a target and an action. It has NO frame, and that is not an omission: an
 * application does not know what else is in the status bar, so it cannot know where its own item goes. The server
 * packs them from the right edge leftwards, which is why the one number an application gives is a width.
 *
 * Written from `NSStatusItem.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSStatusBar;
@class NSView;
@class NSWindow;
@class NSImage;
@class NSMenu;
@class NSString;
@class NSAttributedString;
#include <AppKit/NSEvent.h>

/* THE TWO LENGTHS THAT ARE NOT LENGTHS, and this layer's job is to resolve them: only AppKit knows how wide a
 * view wants to be, so the server is never told a sentinel — it is told a width in output coordinates. */
#define NSVariableStatusItemLength	(-1.0)
#define NSSquareStatusItemLength	(-2.0)

@interface NSStatusItem : NSObject
{
@private
	NSStatusBar *_fStatusBar;
	NSWindow *_fWindow;		/* the item's own window, which is what the server places */
	NSView *_fView;
	CGFloat _fLength;
	SEL _fAction;
	SEL _fDoubleAction;
	id _fTarget;
	NSString *_fTitle;
	NSAttributedString *_fAttributedTitle;
	NSImage *_fImage;
	NSImage *_fAlternateImage;
	NSMenu *_fMenu;
	BOOL _fHighlightMode;
	/* **AND THE VIEW THE ITEM MAKES FOR ITSELF.** A status item with no view of the application's is not blank: it draws
	 * its title or image and it takes the press, which is what `-isEnabled`, `-sendActionOn:`, the tooltip and the action
	 * pair are ABOUT. This is that view, kept so that `-setView:nil` restores it rather than leaving a window with no
	 * content at all. */
	NSView *_fInternalView;
	/* **AND THE THREE THE SWEEP ADDS.** `_fEnabled` gates the action rather than the drawing; `_fActionMask` is the
	 * event that sends it (Apple's `-sendActionOn:`, with `NSLeftMouseUpMask` as the default); and `_fToolTip` is the
	 * string the item's own view shows. THE VIEW IS WHERE ALL THREE ARE OBEYED — see the note on the internal view in
	 * the implementation — because a status item is a window and its view is what receives the press. */
	BOOL _fEnabled;
	NSEventMask _fActionMask;
	NSString *_fToolTip;
}

- (NSStatusBar *)statusBar;

- (CGFloat)length;
- (void)setLength:(CGFloat)length;

- (SEL)action;
- (void)setAction:(SEL)aSelector;
- (SEL)doubleAction;
- (void)setDoubleAction:(SEL)aSelector;

- (id)target;
- (void)setTarget:(id)anObject;

- (NSString *)title;
- (void)setTitle:(NSString *)aString;

- (NSAttributedString *)attributedTitle;
- (void)setAttributedTitle:(NSAttributedString *)aString;

- (NSImage *)image;
- (void)setImage:(NSImage *)anImage;

- (NSImage *)alternateImage;
- (void)setAlternateImage:(NSImage *)anImage;

- (BOOL)highlightMode;
- (void)setHighlightMode:(BOOL)flag;

/* **AND THE THREE DOORS THAT GATE THE ACTION AND NAME THE ITEM.** `-isEnabled`/`-setEnabled:` decide whether a press
 * sends anything (a disabled item still draws, DIMMED, because its position is still worth showing); `-sendActionOn:`
 * says WHICH event sends the action, with `NSLeftMouseUpMask` as the default and any mask the app's event loop can
 * deliver accepted; and the tooltip pair is the string the item's view shows under the pointer. All three are obeyed by
 * the view the item makes for itself — see `-setView:` — so none of them is state without a reader. */
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;
- (NSInteger)sendActionOn:(NSEventMask)mask;
- (nullable NSString *)toolTip;
- (void)setToolTip:(nullable NSString *)toolTip;

- (NSMenu *)menu;
- (void)setMenu:(NSMenu *)aMenu;

/* The item's view, which the APPLICATION draws. The server places the item; it does not draw one. */
- (NSView *)view;
- (void)setView:(NSView *)aView;

- (void)popUpStatusItemMenu:(NSMenu *)aMenu;
- (void)drawStatusBarBackgroundInRect:(NSRect)rect withHighlight:(BOOL)highlight;

@end

/* The private door `NSStatusBar` uses to make one. Not part of the class the SDK describes, and here rather than in
 * a .m because the bar is a different file and the two are one object's halves. */
@interface NSStatusItem (AGORAStatusItemPrivate)
- (id)cg_initWithStatusBar:(NSStatusBar *)bar length:(CGFloat)length;
/* AND THE EVENT THE ACTION GOES OUT ON, which has no public getter in Apple's header — `-sendActionOn:` answers the
 * PREVIOUS mask, so the current one is this seam's. The item's own view reads it. */
- (NSEventMask)cg_actionMask;
@end
