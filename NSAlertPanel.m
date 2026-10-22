/*
 * NSAlertPanel.m — the era's thirteen alert-panel functions, over `NSAlert`.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE WHOLE FILE IS A TRANSLATION LAYER AND THAT IS ITS CORRECT SHAPE.** The 10.6 caller passes a title, a printf
 * format and up to three button names, and gets 1000/1001/1002 back. `NSAlert` already owns the panel, the layout, the
 * wrapped text and that exact arithmetic — `NSAlert.h` states the return values in its own words — so a second dialog
 * implementation would be a second set of bugs in the same pixels.
 *
 * **AND THE FORMAT IS EXPANDED BY FOUNDATION, BECAUSE `vsnprintf` CANNOT DO IT.** The first draft of this file used
 * `vsnprintf` on the reasoning that a bounded C write is safer than a hand-rolled expansion — and it was WRONG in a way
 * the test caught immediately: the era's formats carry `%@`, which is not a C conversion at all, so `vsnprintf` emitted
 * the literal `%@` and the message reached the panel unexpanded. `+stringWithFormat:arguments:` is the door that knows
 * the Cocoa conversions, and it is what the era's callers were actually getting.
 *
 * **`title` BECOMES THE PANEL'S WINDOW TITLE AND `msgFormat` BECOMES ITS MESSAGE**, which is the era's arrangement: the
 * title belonged to the frame, the sentence to the body.
 */
#import <AppKit/NSPanel.h>
#import <AppKit/NSAlert.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSButton.h>
#import <Foundation/Foundation.h>

#include <stdarg.h>
#include <stdio.h>

/* One expansion of the era's format, with the Cocoa conversions (`%@` above all) that a C library does not have. */
static NSString *fn_panel_message(NSString *format, va_list args)
{
	if (format == nil) {
		return @"";
	}
	return [NSString stringWithFormat:format arguments:args];
}

static NSAlert *fn_panel_alert(NSString *title, NSString *format, va_list args, NSAlertStyle style,
			       NSString *defaultButton, NSString *alternateButton, NSString *otherButton)
{
	NSString *message = fn_panel_message(format, args);
	NSAlert *alert = [[NSAlert alloc] init];

	[alert setAlertStyle:style];
	[alert setMessageText:message];
	if (title != nil) {
		[[alert window] setTitle:title];
	}
	/* **A NIL BUTTON NAME MEANS "NO SUCH BUTTON", NOT "A BUTTON WITH NO NAME"** — that is what the era's callers
	 * relied on when they passed NULL for the third button of a two-button question. */
	if (defaultButton != nil) {
		[alert addButtonWithTitle:defaultButton];
	}
	if (alternateButton != nil) {
		[alert addButtonWithTitle:alternateButton];
	}
	if (otherButton != nil) {
		[alert addButtonWithTitle:otherButton];
	}
	return alert;
}

/* ------------------------------------------------------------------------------------------------------------------
 * The GET family: a `+1` alert, released by `NSReleaseAlertPanel`.
 * ---------------------------------------------------------------------------------------------------------------- */

id NSGetAlertPanel(NSString *title, NSString *msgFormat, NSString *defaultButton, NSString *alternateButton,
		   NSString *otherButton, ...)
{
	va_list args;
	NSAlert *alert;

	va_start(args, otherButton);
	alert = fn_panel_alert(title, msgFormat, args, NSWarningAlertStyle, defaultButton, alternateButton, otherButton);
	va_end(args);
	return alert;
}

id NSGetCriticalAlertPanel(NSString *title, NSString *msgFormat, NSString *defaultButton, NSString *alternateButton,
			   NSString *otherButton, ...)
{
	va_list args;
	NSAlert *alert;

	va_start(args, otherButton);
	alert = fn_panel_alert(title, msgFormat, args, NSCriticalAlertStyle, defaultButton, alternateButton, otherButton);
	va_end(args);
	return alert;
}

id NSGetInformationalAlertPanel(NSString *title, NSString *msgFormat, NSString *defaultButton,
				NSString *alternateButton, NSString *otherButton, ...)
{
	va_list args;
	NSAlert *alert;

	va_start(args, otherButton);
	alert = fn_panel_alert(title, msgFormat, args, NSInformationalAlertStyle, defaultButton, alternateButton,
			       otherButton);
	va_end(args);
	return alert;
}

void NSReleaseAlertPanel(id panel)
{
	[(id)panel release];
}

/* ------------------------------------------------------------------------------------------------------------------
 * The RUN family: the same alert, run modally, answering 1000/1001/1002.
 * ---------------------------------------------------------------------------------------------------------------- */

static NSInteger fn_panel_run(NSString *title, NSString *format, va_list args, NSAlertStyle style,
			      NSString *defaultButton, NSString *alternateButton, NSString *otherButton)
{
	NSAlert *alert = fn_panel_alert(title, format, args, style, defaultButton, alternateButton, otherButton);
	NSInteger answer = [alert runModal];

	[alert release];
	return answer;
}

NSInteger NSRunAlertPanel(NSString *title, NSString *msgFormat, NSString *defaultButton, NSString *alternateButton,
			  NSString *otherButton, ...)
{
	va_list args;
	NSInteger answer;

	va_start(args, otherButton);
	answer = fn_panel_run(title, msgFormat, args, NSWarningAlertStyle, defaultButton, alternateButton, otherButton);
	va_end(args);
	return answer;
}

NSInteger NSRunCriticalAlertPanel(NSString *title, NSString *msgFormat, NSString *defaultButton,
				  NSString *alternateButton, NSString *otherButton, ...)
{
	va_list args;
	NSInteger answer;

	va_start(args, otherButton);
	answer = fn_panel_run(title, msgFormat, args, NSCriticalAlertStyle, defaultButton, alternateButton, otherButton);
	va_end(args);
	return answer;
}

NSInteger NSRunInformationalAlertPanel(NSString *title, NSString *msgFormat, NSString *defaultButton,
				       NSString *alternateButton, NSString *otherButton, ...)
{
	va_list args;
	NSInteger answer;

	va_start(args, otherButton);
	answer = fn_panel_run(title, msgFormat, args, NSInformationalAlertStyle, defaultButton, alternateButton,
			      otherButton);
	va_end(args);
	return answer;
}

/* **THE DOCUMENT WINDOW IS TAKEN AND NOT USED BY A MODAL RUN**, which is Apple's own reading of these doors: the
 * window is the sheet's parent, and a modal panel has no parent. It is named in the signature because a ported caller
 * passes it. */
NSInteger NSRunAlertPanelRelativeToWindow(NSString *title, NSString *msgFormat, NSString *defaultButton,
					  NSString *alternateButton, NSString *otherButton, NSWindow *docWindow, ...)
{
	va_list args;
	NSInteger answer;

	(void)docWindow;
	va_start(args, docWindow);
	answer = fn_panel_run(title, msgFormat, args, NSWarningAlertStyle, defaultButton, alternateButton, otherButton);
	va_end(args);
	return answer;
}

NSInteger NSRunCriticalAlertPanelRelativeToWindow(NSString *title, NSString *msgFormat, NSString *defaultButton,
						  NSString *alternateButton, NSString *otherButton, NSWindow *docWindow, ...)
{
	va_list args;
	NSInteger answer;

	(void)docWindow;
	va_start(args, docWindow);
	answer = fn_panel_run(title, msgFormat, args, NSCriticalAlertStyle, defaultButton, alternateButton, otherButton);
	va_end(args);
	return answer;
}

NSInteger NSRunInformationalAlertPanelRelativeToWindow(NSString *title, NSString *msgFormat,
						       NSString *defaultButton, NSString *alternateButton,
						       NSString *otherButton, NSWindow *docWindow, ...)
{
	va_list args;
	NSInteger answer;

	(void)docWindow;
	va_start(args, docWindow);
	answer = fn_panel_run(title, msgFormat, args, NSInformationalAlertStyle, defaultButton, alternateButton,
			      otherButton);
	va_end(args);
	return answer;
}

/* ------------------------------------------------------------------------------------------------------------------
 * The SHEET family: asynchronous, and the alert outlives this call.
 * ---------------------------------------------------------------------------------------------------------------- */

/* **THE ALERT IS AUTORELEASED RATHER THAN RELEASED, BECAUSE A SHEET OUTLIVES THE FUNCTION THAT BEGAN IT.** The panel it
 * owns is retained by the application for the duration of the sheet, and the era's `didDismissSelector` has no
 * counterpart on `-beginSheetModalForWindow:…` — the dismiss callback is a 10.6 addition the class does not carry, so
 * the parameter is accepted and named as unhonoured rather than silently dropped. */
static void fn_panel_sheet(NSString *title, NSString *format, va_list args, NSAlertStyle style,
			   NSString *defaultButton, NSString *alternateButton, NSString *otherButton,
			   NSWindow *docWindow, id modalDelegate, SEL didEndSelector, SEL didDismissSelector,
			   void *contextInfo)
{
	NSAlert *alert = fn_panel_alert(title, format, args, style, defaultButton, alternateButton, otherButton);

	(void)didDismissSelector;
	[alert beginSheetModalForWindow:docWindow
			  modalDelegate:modalDelegate
			 didEndSelector:didEndSelector
			    contextInfo:contextInfo];
	[alert autorelease];
}

void NSBeginAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton, NSString *otherButton,
		       NSWindow *docWindow, id modalDelegate, SEL didEndSelector, SEL didDismissSelector,
		       void *contextInfo, NSString *msgFormat, ...)
{
	va_list args;

	va_start(args, msgFormat);
	fn_panel_sheet(title, msgFormat, args, NSWarningAlertStyle, defaultButton, alternateButton, otherButton,
		       docWindow, modalDelegate, didEndSelector, didDismissSelector, contextInfo);
	va_end(args);
}

void NSBeginCriticalAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton,
			       NSString *otherButton, NSWindow *docWindow, id modalDelegate, SEL didEndSelector,
			       SEL didDismissSelector, void *contextInfo, NSString *msgFormat, ...)
{
	va_list args;

	va_start(args, msgFormat);
	fn_panel_sheet(title, msgFormat, args, NSCriticalAlertStyle, defaultButton, alternateButton, otherButton,
		       docWindow, modalDelegate, didEndSelector, didDismissSelector, contextInfo);
	va_end(args);
}

void NSBeginInformationalAlertSheet(NSString *title, NSString *defaultButton, NSString *alternateButton,
				    NSString *otherButton, NSWindow *docWindow, id modalDelegate, SEL didEndSelector,
				    SEL didDismissSelector, void *contextInfo, NSString *msgFormat, ...)
{
	va_list args;

	va_start(args, msgFormat);
	fn_panel_sheet(title, msgFormat, args, NSInformationalAlertStyle, defaultButton, alternateButton, otherButton,
		       docWindow, modalDelegate, didEndSelector, didDismissSelector, contextInfo);
	va_end(args);
}
