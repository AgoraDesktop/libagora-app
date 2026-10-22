/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAlert.h — a question with buttons: a message, the text under it, an icon, and an answer.
 *
 * **AN ALERT IS A PANEL, AND THAT IS THE WHOLE OF ITS WINDOW MODEL.** Apple's alert is not a new kind of window: it
 * is an `NSPanel` at `NSModalPanelWindowLevel` whose content is text, an icon and buttons, and which runs either as an
 * application-modal loop (`-runModal`) or as a sheet (`-beginSheetModalForWindow:…`). This tier already had both
 * halves underneath — `NSApplication -runModalForWindow:` and `-beginSheet:modalForWindow:…` — and the panel class
 * arrived with this file, so what is left here is the CONTENT and the two ways of running it.
 *
 * **THE CONTENT IS REAL CONTROLS, NOT A PAINTED PICTURE.** The message and the informative text are `NSTextField`s
 * (a LINE each, because a field is one line in this tier, so the wrapping is done by measuring the string and making
 * as many fields as it needs); the buttons are `NSButton`s whose target is the alert; and the icon is a view that
 * draws an `NSImage`. That is why a probe can read the buttons' titles and the fields' strings rather than counting
 * pixels, and why the alert's Return/Escape handling can be a panel key handler rather than a secret.
 *
 * **THE THREE RETURN VALUES ARE APPLE'S PUBLISHED NUMBERS, AND THEY BELONG IN THIS HEADER.** They were declared in
 * `NSApplication.h` while this class did not exist; Apple's own header places them beside `NSAlert`, which is where
 * they are now. A caller compares `-runModal`'s answer against them, so the values may not be chosen.
 *
 * Written from `NSAlert.h` in the MacOSX10.6 SDK.
 */
#ifndef APPKIT_NSALERT_H
#define APPKIT_NSALERT_H

#import <AppKit/NSPanel.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

@class NSButton;
@class NSImage;
@class NSView;

/* AND THE THREE ANSWERS, IN THEIR APPLE'S-OWN PLACE. The first button's answer is 1000, the second's 1001, the third's
 * 1002, and any button after the third is `1000 + its index` — Apple's rule, stated where the click is turned into a
 * code. */
enum {
	NSAlertFirstButtonReturn = 1000,
	NSAlertSecondButtonReturn = 1001,
	NSAlertThirdButtonReturn = 1002
};

/* **THE THREE STYLES, RECORDED AND NOT READ.** Apple's 10.6 header gives them 0, 1 and 2; a WARNING is the default, an
 * INFORMATIONAL alert is the quiet one, and a CRITICAL alert is the one that asks for attention. This tier paints one
 * panel shape and has no system icon art to choose between, so the value round-trips because a caller reads it back
 * and because Apple's door exists — it selects no picture and no geometry, which is stated here rather than implied. */
typedef NSInteger NSAlertStyle;
enum {
	NSWarningAlertStyle = 0,
	NSInformationalAlertStyle = 1,
	NSCriticalAlertStyle = 2
};

/* **THE DELEGATE HAS ONE QUESTION, AND IT IS ABOUT HELP.** Apple declares `NSAlertDelegate` with a single optional
 * member — `-alertShowHelp:` — and the answer is whether the delegate handled the request itself: YES means "I opened my
 * own help", NO (or no delegate) means "show the alert's help anchor", which this tier has no Help Viewer for and says so
 * by name. The alert SENDS it, from the help button `-setShowsHelp:YES` puts in the button row — a delegate declared with
 * no sender is a contract nobody honours, so the button is part of this slice rather than a later one. */
@class NSAlert;
@protocol NSAlertDelegate <NSObject>
@optional
- (BOOL)alertShowHelp:(NSAlert *)alert;
@end

@interface NSAlert : NSObject
{
	/* THE FOUR PIECES OF TEXT THE ALERT OWNS. `_title` is the WINDOW's title (the factory's `title:` argument);
	 * `_messageText` is the bold line; `_informativeText` is what explains it; `_helpAnchor` is what the Help system
	 * would open, and is recorded for the door pair below. All four are retained copies. */
	NSString *_title;
	NSString *_messageText;
	NSString *_informativeText;
	NSString *_helpAnchor;
	/* THE ICON IS RETAINED WHEN A CALLER GIVES ONE, and nil means "ask the application for its icon" — the default
	 * Apple documents. Nil is therefore not the absence of an answer but the absence of an OVERRIDE. */
	NSImage *_icon;
	/* THE BUTTONS, IN THE ORDER THEY WERE ADDED. The array is retained and owns them; index 0 is the default. */
	NSMutableArray *_buttons;
	/* AND THE VIEWS THE LAYOUT MAKES: one field per wrapped line, one icon view, and the optional accessory. The
	 * line arrays are rebuilt by `-layout`, because a line break is a consequence of the width and the font and not a
	 * property of the text. */
	NSMutableArray *_messageLines;
	NSMutableArray *_informativeLines;
	NSView *_iconView;
	/* THE ACCESSORY IS RETAINED, because Apple's `-setAccessoryView:` is an owning property: a caller may build one,
	 * hand it over and release its own reference. */
	NSView *_accessoryView;
	/* THE PANEL, made on first use and retained. There is no stored "last answer": a modal alert returns its code
	 * from `-runModal`, and a sheet's answer is delivered to the caller's did-end method — Apple's two contracts,
	 * and a third ivar would be an answer nobody could ask for. */
	NSPanel *_window;
	NSAlertStyle _alertStyle;
	BOOL _showsHelp;
	/* **AND THE THREE THE SWEEP ADDS.** `_suppressionButton` is the "do not show this again" checkbox, made when
	 * `-setShowsSuppressionButton:YES` and RETAINED; `_helpButton` is the "?" the `-setShowsHelp:` flag puts in the
	 * button row, the caller of `-alertShowHelp:`; and `_delegate` is NOT retained — a delegate owned by the alert it
	 * is told about would be a cycle, which is this tree's rule for every delegate. */
	NSButton *_suppressionButton;
	NSButton *_helpButton;
	id _delegate;
}

/* **THE ERA'S CONVENIENCE CONSTRUCTOR.** `messageText` is the bold line, `title` is the window's title, and the three
 * button strings are the default, alternate and other titles — a NIL button string is simply not added, which is how
 * an alert with one or two buttons is built. Apple's header has `defaultButtonLabel` as a required argument; this
 * implementation accepts nil there too and then has no buttons at all. */
+ (NSAlert *)alertWithMessageText:(nullable NSString *)message
			    title:(nullable NSString *)title
		    defaultButton:(nullable NSString *)defaultButtonLabel
		  alternateButton:(nullable NSString *)alternateButtonLabel
		      otherButton:(nullable NSString *)otherButtonLabel;

/* **AND THE TWO CONSTRUCTORS THE 10.5 SURFACE ADDED.** The FORMAT one is the era's factory without a window title and
 * with the informative text built from a printf-style format — the shape a caller with a number in the message needs.
 * The ERROR one builds an alert out of an `NSError`: the message is its localized description, the informative text its
 * localized failure reason, and the buttons come from its `localizedRecoveryOptions` (or a single OK). */
+ (NSAlert *)alertWithMessageText:(nullable NSString *)message
		    defaultButton:(nullable NSString *)defaultButtonLabel
		  alternateButton:(nullable NSString *)alternateButtonLabel
		      otherButton:(nullable NSString *)otherButtonLabel
	informativeTextWithFormat:(nullable NSString *)format, ... NS_FORMAT_FUNCTION(5, 6);
+ (NSAlert *)alertWithError:(NSError *)error;

/* **THE SUPPRESSION BUTTON IS CREATED ON DEMAND, WHICH IS APPLE'S CONTRACT RATHER THAN AN OPTIMISATION.** A fresh alert
 * answers nil for it; `-setShowsSuppressionButton:YES` makes one (an `NSSwitchButton` with an empty title, so the caller
 * writes "Do not show this again" on it) and puts it at the LEFT of the button row; the caller reads its state back to
 * know whether the person asked not to be asked again. The flag is separate from the button so that turning it off
 * hides the box without destroying the answer it holds. */
- (BOOL)showsSuppressionButton;
- (void)setShowsSuppressionButton:(BOOL)flag;
- (nullable NSButton *)suppressionButton;

/* **AND THE DELEGATE, WHOSE ONE MESSAGE THE HELP BUTTON SENDS.** See the protocol above: a NO answer (or no delegate)
 * leaves the help anchor with nowhere to go, and that is refused by name rather than pretending. */
- (nullable id <NSAlertDelegate>)delegate;
- (void)setDelegate:(nullable id <NSAlertDelegate>)anObject;

/* **AND THE HELP BUTTON'S ACTION, WHICH IS PUBLIC BECAUSE A PROBE HAS TO SEND WHAT A PERSON WOULD.** Apple's alert shows
 * a "?" in its title bar and routes it through a door this header does not declare; this tier puts the button in the
 * button row, and this is the factory's action. It sends `-alertShowHelp:` and refuses by name when the delegate does not
 * handle it — see the protocol above. It is named `cg_` because Apple has no such door at this pin. */
- (void)cg_helpButtonClicked:(nullable id)sender;

/* THE TWO PIECES OF TEXT AND THE ICON, each a copy (the strings) or a retained object (the icon). A nil icon means
 * "the application's icon", which is Apple's default. */
- (nullable NSString *)messageText;
- (void)setMessageText:(nullable NSString *)string;
- (nullable NSString *)informativeText;
- (void)setInformativeText:(nullable NSString *)string;
- (nullable NSImage *)icon;
- (void)setIcon:(nullable NSImage *)image;

/* **THE BUTTONS, AND THE ORDER IS THE API.** `-addButtonWithTitle:` appends and answers the button it made; the first
 * one added is the default, the second is the cancel button, and any after them are ordinary answers. `-buttons`
 * answers a COPY, so a caller cannot add a button by mutating the array it was handed. */
- (NSButton *)addButtonWithTitle:(NSString *)title;
- (NSArray *)buttons;

/* THE STYLE AND THE ACCESSORY VIEW. The accessory is laid out between the text and the buttons; `-layout` is public
 * because Apple's is (a caller that changes a view's frame after handing it over has to ask for the arithmetic again),
 * and the setters that change the layout ask for it themselves. */
- (NSAlertStyle)alertStyle;
- (void)setAlertStyle:(NSAlertStyle)style;
- (nullable NSView *)accessoryView;
- (void)setAccessoryView:(nullable NSView *)view;

/* **THE HELP PAIR, RECORDED RATHER THAN SHOWN.** Apple's alert grows a help button when `-setShowsHelp:YES` and there
 * is a `-helpAnchor`. This tier has no Help system — `NSApplication -showHelp:` refuses by name — so the two values
 * round-trip and no button is made; the absence is said here, at the door, rather than discovered by a caller
 * wondering why the button is missing. */
- (BOOL)showsHelp;
- (void)setShowsHelp:(BOOL)flag;
- (nullable NSString *)helpAnchor;
- (void)setHelpAnchor:(nullable NSString *)anchor;

/* THE WINDOW, MADE ON FIRST ASK. It is an `NSPanel` at `NSModalPanelWindowLevel`, created once and reused (closing it
 * does not release it), and built from the message, the informative text and the buttons. */
- (NSWindow *)window;

/* **THE TWO WAYS TO RUN IT.** `-runModal` runs an application-modal loop and returns the clicked button's code,
 * ordering the panel out first. `-beginSheetModalForWindow:…` attaches the panel to `window` and returns immediately;
 * the button's action ends the sheet, and APPLE'S CALLBACK — not this class — is what orders the panel out, which is
 * the same contract `NSApplication -endSheet:` documents. */
- (NSInteger)runModal;
- (void)beginSheetModalForWindow:(NSWindow *)window
		  modalDelegate:(nullable id)modalDelegate
		 didEndSelector:(nullable SEL)didEndSelector
		    contextInfo:(nullable void *)contextInfo;

/* THE ARITHMETIC, PUBLIC AS APPLE'S IS: the panel's content size is computed from the wrapped text, the icon, the
 * accessory and the buttons, and each piece is placed in it. The setters that change the CONTENT call it when the window
 * already exists; the style and help pair do not, because neither changes a frame. */
- (void)layout;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSALERT_H */
