/*
 * NSStatusItem.h — one item in the status area, placed by the server.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
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
@end
