/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSPanel.h — a window that is a helper rather than a document: it floats, it can be made to work while a modal session
 * runs, and it takes the keyboard only when the thing under the pointer needs it.
 *
 * **A PANEL IS A WINDOW, AND THIS TREE'S `NSWindow` ALREADY CARRIES THREE OF ITS FOUR FLAGS.** `-isFloatingPanel`,
 * `-worksWhenModal` and `-setModalPanel:` are `NSWindow` doors with Apple's own values (the panel's answer is the
 * window's, not a second copy of it), so what is left for this subclass is the part that is genuinely about being a
 * panel:
 *
 *   * `-becomesKeyOnlyIfNeeded` — the flag a utility panel sets so that clicking its background does not steal the
 *     document window's keyboard, while clicking a FIELD inside it does. The decision is made where a click becomes
 *     key (`NSApplication -sendEvent:`), and the per-view half is `NSView -needsPanelToBecomeKey`; before this class
 *     the view door answered NO for everything and its comment said there was no panel to need.
 *   * `-canBecomeMainWindow` — Apple's rule for a window's main-hood names a panel as NEVER main ("true when the
 *     window is visible, is not an NSPanel object, and has a title bar or a resize mechanism"). `NSWindow`'s
 *     implementation could not test that clause because there was no `NSPanel`; the clause is this override.
 *   * `hidesOnDeactivate` — YES for a panel and NO for a document, which is why the designated initialiser says so.
 *
 * **AND WHAT A PANEL DOES NOT GET IS ANOTHER IMPLEMENTATION OF THE WINDOW.** The style mask, the chrome, the content
 * view, the sheet attachment and the modal session are all `NSWindow`'s (and `NSApplication`'s); a panel changes
 * three answers and nothing else. That is also why `NSAlert` can be built on this class without a second window
 * model.
 *
 * Written from `NSPanel.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSPANEL_H
#define APPKIT_NSPANEL_H

#import <AppKit/NSWindow.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSPanel : NSWindow
{
	/* **THE ONE FLAG THE CLASS ADDS.** It is stored as the value it was given rather than as a deviation, because
	 * Apple's default is NO and an ivar's default is NO — the same trade `NSWindow`'s positive flags make. */
	BOOL _becomesKeyOnlyIfNeeded;
}

/* THE DESIGNATED INITIALISER IS THE WINDOW'S, with one panel default applied: `hidesOnDeactivate` YES. Apple's
 * `NSPanel` documentation gives that default and explains it — a panel belongs to the window it assists, so it goes
 * away when the application does — and this is the only place the difference can be made. */
- (instancetype)initWithContentRect:(NSRect)contentRect
			  styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType
			      defer:(BOOL)flag;

/* **WHEN THE PANEL TAKES THE KEYBOARD, WHICH IS NOT ON EVERY CLICK.** Apple's prose for this door is exactly the rule
 * the implementation follows: "A Boolean value that indicates whether the panel becomes the key window only when
 * needed." A panel with this NO (Apple's default) becomes key on any click, like a window; a panel with it YES is
 * asked, at the view under the pointer, whether that view needs the panel to be key — a text field says yes, a
 * button says no. */
- (BOOL)becomesKeyOnlyIfNeeded;
- (void)setBecomesKeyOnlyIfNeeded:(BOOL)flag;

/* AND THE TWO WINDOW ANSWER A PANEL CHANGES. `-canBecomeKeyWindow` is inherited (a titled or resizable panel can take
 * the keyboard, a borderless one cannot); `-canBecomeMainWindow` is ALWAYS NO, which is Apple's documented answer for
 * every panel, and the reason a panel does not appear in the application's main-window slot. */
- (BOOL)canBecomeMainWindow;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPANEL_H */
