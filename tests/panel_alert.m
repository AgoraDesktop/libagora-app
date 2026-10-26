/*
 * panel_alert — a helper window's three answers, and an alert's content, layout and return codes.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHY THIS EXISTS. `NSPanel` and `NSAlert` are the two classes the file manager's conflict question said it could not
 * have, and the four `NSWindow` flags a panel is built from (`floating`, `worksWhenModal`, `modalPanel`, `hidesOnDeactivate`)
 * had been state with no class to own them. This probe asks the questions that class ownership makes answerable:
 *
 *   1. A panel's defaults differ from a window's exactly where Apple says they do — `hidesOnDeactivate` YES,
 *      `canBecomeMainWindow` NO — and the flags it shares with `NSWindow` round-trip.
 *   2. `-becomesKeyOnlyIfNeeded` is a REAL rule: the click-to-key seam asks the view under the pointer, and an editable
 *      field says yes where a button and the background say no. That is the half `NSControl -needsPanelToBecomeKey`
 *      owns, and the reason the door is not just a stored BOOL.
 *   3. An alert is a PANEL at `NSModalPanelWindowLevel`, its factory arguments become text, title and buttons, and its
 *      layout puts the first button rightmost with every piece inside the content rect.
 *   4. The buttons return Apple's codes THROUGH A MODAL SESSION — 1000, 1001, 1002 — and Return and Escape, which this
 *      tier's pump has no key-equivalent pass for, reach the default and cancel buttons through the panel's own
 *      `-keyDown:`.
 *   5. The sheet form attaches the alert to a parent, ends the session on a click, and runs the caller's reply with
 *      the clicked code. `-runModal` is NOT called here, for the reason `NSApplication.m` gives about its own probe:
 *      it is an unbounded loop, and a test that called it would hang rather than fail.
 */
#import <AppKit/NSAlert.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* A KEY EVENT, built the way the seam builds one: the character is what the panel's handler reads. */
static NSEvent *fn_key(NSString *characters, NSWindow *window)
{
	return [NSEvent keyEventWithType:NSKeyDown
				location:NSZeroPoint
			   modifierFlags:0
			       timestamp:0.0
			    windowNumber:[window windowNumber]
				 context:nil
			      characters:characters
	     charactersIgnoringModifiers:characters
			     isARepeat:NO
			       keyCode:0];
}

/* THE FIELDS A LAYOUT MAKES, found the way a person finds them: by walking the content view's subtree. The alert's
 * text is real `NSTextField`s, so a probe can read it rather than infer it from ink. */
static void fn_collect_fields(NSView *view, NSMutableArray *fields)
{
	NSArray *subviews = [view subviews];
	NSUInteger i;

	for (i = 0; i < [subviews count]; i++) {
		NSView *child = [subviews objectAtIndex:i];

		if ([child isKindOfClass:[NSTextField class]]) {
			[fields addObject:child];
		}
		fn_collect_fields(child, fields);
	}
}

static NSArray *fn_fields(NSWindow *window)
{
	NSMutableArray *fields = [NSMutableArray array];

	fn_collect_fields([window contentView], fields);
	return fields;
}

static BOOL fn_has_field_text(NSWindow *window, NSString *text)
{
	NSArray *fields = fn_fields(window);
	NSUInteger i;

	for (i = 0; i < [fields count]; i++) {
		if ([[[fields objectAtIndex:i] stringValue] isEqualToString:text]) {
			return YES;
		}
	}
	return NO;
}

/* THE REPLY THE SHEET FORM OWES, with the signature Apple's `NSApplication.h` quotes. */
@interface SheetReception : NSObject
{
	NSInteger _code;
	BOOL _called;
}
- (NSInteger)code;
- (BOOL)wasCalled;
@end

@implementation SheetReception

- (NSInteger)code
{
	return _code;
}

- (BOOL)wasCalled
{
	return _called;
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	(void)sheet;
	(void)contextInfo;
	_code = returnCode;
	_called = YES;
}

@end

static void test_panel(void)
{
	NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 320.0, 200.0)
						   styleMask:NSTitledWindowMask
						     backing:NSBackingStoreBuffered
						       defer:NO];
	NSPanel *borderless;
	NSWindow *window;
	NSView *content;
	NSTextField *field;
	NSButton *button;

	check([panel isKindOfClass:[NSWindow class]], "a panel is a window");
	check([panel hidesOnDeactivate], "a panel hides when the application deactivates");
	check(![panel isFloatingPanel], "floating is NO until asked");
	check(![panel worksWhenModal], "worksWhenModal is NO until asked");
	check(![panel becomesKeyOnlyIfNeeded], "becomesKeyOnlyIfNeeded is NO until asked");
	[panel setFloatingPanel:YES];
	check([panel isFloatingPanel], "the floating flag round-trips");
	[panel setWorksWhenModal:YES];
	check([panel worksWhenModal], "the worksWhenModal flag round-trips");
	check([panel canBecomeKeyWindow], "a titled panel can take the keyboard");
	check(![panel canBecomeMainWindow], "and it is never the main window");
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 320.0, 200.0)
					     styleMask:NSTitledWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	check([window cg_shouldBecomeKeyForClickAtPoint:NSMakePoint(1.0, 1.0)],
	      "an ordinary window still takes the key from any click");
	[window release];

	borderless = [[NSPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 320.0, 200.0)
						styleMask:NSBorderlessWindowMask
						  backing:NSBackingStoreBuffered
						    defer:NO];
	check(![borderless canBecomeKeyWindow], "a borderless panel cannot take the keyboard either");

	/* **THE CLICK-TO-KEY RULE.** With the flag NO every click takes the key; with it YES the view under the point is
	 * asked, and a field's `-needsPanelToBecomeKey` is YES where a button's and the background's are NO. The panel is
	 * given a content view first, because this tier's `NSWindow` does not make one on a caller's behalf. */
	content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 200.0)];
	[panel setContentView:content];
	[content release];
	field = [[NSTextField alloc] initWithFrame:NSMakeRect(10.0, 10.0, 100.0, 24.0)];
	[content addSubview:field];
	button = [[NSButton alloc] initWithFrame:NSMakeRect(150.0, 10.0, 90.0, 28.0)];
	[content addSubview:button];
	check([panel cg_shouldBecomeKeyForClickAtPoint:NSMakePoint(20.0, 20.0)],
	      "without the flag a click anywhere takes the key");
	[panel setBecomesKeyOnlyIfNeeded:YES];
	check([panel cg_shouldBecomeKeyForClickAtPoint:NSMakePoint(20.0, 20.0)],
	      "an editable field still takes it when the rule is on");
	check(![panel cg_shouldBecomeKeyForClickAtPoint:NSMakePoint(160.0, 20.0)],
	      "a button does not");
	check(![panel cg_shouldBecomeKeyForClickAtPoint:NSMakePoint(250.0, 150.0)],
	      "and neither does the background");
	[field release];
	[button release];
	[borderless release];
	[panel release];
}

static void test_alert_content(void)
{
	NSAlert *alert = [NSAlert alertWithMessageText:@"Delete “notes.txt”?"
					  title:@"Confirm"
				  defaultButton:@"Delete"
				alternateButton:@"Cancel"
				    otherButton:nil];
	NSWindow *window = [alert window];
	NSArray *buttons = [alert buttons];
	NSRect first;
	NSRect second;
	NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(32.0, 32.0)];
	NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 40.0)];

	check(NSAlertFirstButtonReturn == 1000 && NSAlertSecondButtonReturn == 1001
	      && NSAlertThirdButtonReturn == 1002, "the three answer codes are Apple's numbers");
	check([[alert messageText] isEqualToString:@"Delete “notes.txt”?"], "the factory sets the message");
	check([buttons count] == 2, "and adds the two buttons it was given");
	check([[buttons objectAtIndex:0] isKindOfClass:[NSButton class]], "a button is an NSButton");
	check([[[buttons objectAtIndex:0] title] isEqualToString:@"Delete"], "the default button keeps its title");
	check([[[buttons objectAtIndex:1] title] isEqualToString:@"Cancel"], "the alternate button too");
	check([window isKindOfClass:[NSPanel class]], "the alert's window is a panel");
	check(window == [alert window], "and it is made once and reused");
	check([window level] == NSModalPanelWindowLevel, "at the modal panel level");
	check([[window title] isEqualToString:@"Confirm"], "the factory's title is the window's");
	check(![window hidesOnDeactivate], "the alert panel stays put while the application is inactive");
	check([alert alertStyle] == NSWarningAlertStyle, "a warning is the default style");
	[alert setAlertStyle:NSCriticalAlertStyle];
	check([alert alertStyle] == NSCriticalAlertStyle, "and the style round-trips");
	check(fn_has_field_text(window, @"Delete “notes.txt”?"), "the message is a field in the content");
	check([[buttons objectAtIndex:0] superview] == [window contentView], "the buttons are subviews of the content");
	first = [[buttons objectAtIndex:0] frame];
	second = [[buttons objectAtIndex:1] frame];
	check(NSMaxX(first) > NSMaxX(second), "the default button is rightmost");
	check(first.origin.y == second.origin.y, "the buttons share a row");
	check(NSContainsRect([[window contentView] bounds], first)
	      && NSContainsRect([[window contentView] bounds], second), "and both are inside the content rect");
	check([alert icon] == nil || [[alert icon] isKindOfClass:[NSImage class]],
	      "the default icon is an image or nothing");

	[alert setIcon:icon];
	check([alert icon] == icon, "a custom icon is the one the alert answers");
	[icon release];

	/* **A LONG INFORMATIVE TEXT WRAPS INTO MORE THAN ONE FIELD**, which is the only way a one-line field can hold a
	 * paragraph: the wrap is measured at the text column's width and each line is a field. The count is the check,
	 * because a single field would mean the text was silently clipped. */
	[alert setInformativeText:@"This item is used by another application. Deleting it may make that application "
				  @"unable to open its documents, and the change cannot be undone after the Trash is emptied."];
	[alert layout];
	check([fn_fields(window) count] > 2, "a long informative text becomes several line fields");
	[alert setMessageText:@"A different question"];
	[alert layout];
	check(fn_has_field_text(window, @"A different question"), "a changed message is laid out again");
	check(!fn_has_field_text(window, @"Delete “notes.txt”?"), "and the old one is gone");

	[alert setAccessoryView:accessory];
	[alert layout];
	check([accessory superview] == [window contentView], "the accessory is placed in the content");
	check(NSContainsRect([[window contentView] bounds], [accessory frame]), "and inside its bounds");
	[alert setAccessoryView:nil];
	check([accessory superview] == nil, "replacing the accessory takes it out");
	[accessory release];
}

static void test_alert_answers(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSAlert *alert = [NSAlert alertWithMessageText:@"Save changes?"
					  title:@"Unsaved"
				  defaultButton:@"Save"
				alternateButton:@"Don't Save"
				    otherButton:@"Cancel"];
	NSWindow *window = [alert window];
	NSArray *buttons = [alert buttons];
	NSModalSession session;
	NSEvent *event;

	check([buttons count] == 3, "three buttons were added");

	/* **THE THIRD BUTTON, THEN THE SECOND, THEN THE FIRST.** Each session is begun, a button is clicked through
	 * `-performClick:` (which sends the button's action exactly as a press does), and the session's answer is read
	 * through `-runModalSession:` rather than `-runModal`, which would loop forever. */
	session = [application beginModalSessionForWindow:window];
	check(session != NULL, "a modal session begins on the alert's panel");
	[[buttons objectAtIndex:2] performClick:nil];
	check([application runModalSession:session] == NSAlertThirdButtonReturn, "the third button answers 1002");
	[application endModalSession:session];

	session = [application beginModalSessionForWindow:window];
	[[buttons objectAtIndex:1] performClick:nil];
	check([application runModalSession:session] == NSAlertSecondButtonReturn, "the second answers 1001");
	[application endModalSession:session];

	session = [application beginModalSessionForWindow:window];
	[[buttons objectAtIndex:0] performClick:nil];
	check([application runModalSession:session] == NSAlertFirstButtonReturn, "the first answers 1000");
	[application endModalSession:session];

	/* **THE KEYS, WHICH THE PUMP DOES NOT ROUTE AS KEY EQUIVALENTS.** The event goes through the window's own
	 * dispatch so the panel's `-keyDown:` is the thing under test. */
	session = [application beginModalSessionForWindow:window];
	event = fn_key(@"\r", window);
	[window sendEvent:event];
	check([application runModalSession:session] == NSAlertFirstButtonReturn, "Return clicks the default button");
	[application endModalSession:session];

	session = [application beginModalSessionForWindow:window];
	event = fn_key(@"\033", window);
	[window sendEvent:event];
	check([application runModalSession:session] == NSAlertSecondButtonReturn, "Escape clicks the cancel button");
	[application endModalSession:session];

	/* AND AN ALERT THAT WAS NEVER RUN RECORDS A CLICK WITHOUT ENDING ANYTHING — the same action, with no session to
	 * stop, must not send `-stopModalWithCode:` into a loop that is not there. */
	[[buttons objectAtIndex:1] performClick:nil];
	check([application modalWindow] == nil, "a click with no session running ends nothing");
}

static void test_alert_sheet(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(100.0, 100.0, 400.0, 300.0)
						       styleMask:NSTitledWindowMask
							 backing:NSBackingStoreBuffered
							   defer:NO];
	NSAlert *alert = [NSAlert alertWithMessageText:@"Replace it?"
					  title:@"Already exists"
				  defaultButton:@"Replace"
				alternateButton:@"Cancel"
				    otherButton:nil];
	SheetReception *reception = [[SheetReception alloc] init];
	NSWindow *sheet = [alert window];
	/* **THE GEOMETRY IS MEASURED BEFORE THE ATTACHMENT, BECAUSE THE ATTACHMENT IS WHAT CHANGES IT.** The alert's panel
	 * is a titled window, so its frame is its content plus a strip; a sheet has no strip of its own, so what has to
	 * survive the transition is the CONTENT's size while the frame becomes exactly that. */
	NSRect contentBefore = [sheet contentRectForFrameRect:[sheet frame]];
	NSRect frameBefore = [sheet frame];

	sheet = [alert window];
	check(frameBefore.size.height > contentBefore.size.height,
	      "the alert's panel is built as a TITLED window, so its frame is its content plus a strip");

	[alert beginSheetModalForWindow:parent
			  modalDelegate:reception
			 didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
			    contextInfo:NULL];
	check([parent attachedSheet] == [alert window], "the alert is attached as the parent's sheet");
	check([[alert window] isSheet], "and the panel knows it is one");
	/* 5a. **A SHEET HAS NO CHROME, AND WHAT THAT MEANS HERE IS THAT ITS FRAME IS ITS CONTENT.** `-contentRectForFrameRect:`
	 * has to answer the frame itself while a window is a sheet — otherwise the content view is laid out into a strip's
	 * worth of pixels that are not on its surface — and the content has to be the size the alert laid itself out for. */
	check([sheet frame].size.height == [sheet contentRectForFrameRect:[sheet frame]].size.height,
	      "a sheet's frame IS its content: it has no title bar of its own");
	/* **TO WITHIN A POINT, AND THAT IS THE POINT GRID RATHER THAN TOLERANCE.** An alert's computed height is a
	 * fraction (109.6 here), and a sheet's frame is put on whole points because the row its title bar border sits on
	 * has to be the row the parent's own border is on — see `-cg_setSheetParent:`. So the content keeps its size to
	 * the nearest point, which is the only grid a frame has ever had on the wire. */
	check(fabs([sheet frame].size.width - contentBefore.size.width) <= 1.0
	      && fabs([sheet frame].size.height - contentBefore.size.height) <= 1.0,
	      "and taking the strip off the frame leaves the alert's content the size it was laid out for");
	/* 5b. **AND IT HANGS FROM THE PARENT'S TITLE BAR: TOP EDGE AT THE CONTENT'S TOP, CENTRED.** The Mac's rule, and
	 * the one that makes a sheet read as part of the window rather than as a panel near it. */
	{
		NSRect parentContent = [parent contentRectForFrameRect:[parent frame]];

		check(NSMaxY([sheet frame]) > NSMaxY(parentContent)
		      && NSMaxY([sheet frame]) < NSMaxY([parent frame]),
		      "the sheet's TOP edge is INSIDE the parent's title bar — it hangs from the bar, tucked under it");
		check([[sheet cg_bodyColor] isEqual:[NSColor cg_chromeFaceColor]],
		      "and the sheet's body is the chrome's own colour, so the seam is one surface");
		check(fabs(NSMidX([sheet frame]) - NSMidX(parentContent)) < 0.001,
		      "and it is centred on the parent's content");
		check(NSMinY([sheet frame]) >= NSMinY(parentContent)
		      && NSMinY([sheet frame]) < NSMaxY(parentContent),
		      "with its body over the parent's content, which is what makes it a sheet ON it");
	}
	/* 5c. **AND IT MOVES WITH ITS PARENT.** A sheet left behind by a dragged parent is a separate window again, so a
	 * move re-pins it and a resize re-centres it — both through the parent's own `-setFrame:display:`. */
	[parent setFrame:NSMakeRect(60.0, 40.0, 460.0, 300.0) display:YES];
	{
		NSRect parentContent = [parent contentRectForFrameRect:[parent frame]];

		check(NSMaxY([sheet frame]) > NSMaxY(parentContent) && NSMaxY([sheet frame]) < NSMaxY([parent frame]),
		      "moving and widening the parent takes the sheet with it, still tucked into the bar");
		check(fabs(NSMidX([sheet frame]) - NSMidX(parentContent)) < 0.001,
		      "and the new width re-centres it, because the placement is re-applied rather than remembered");
		check(fabs([sheet frame].size.height - contentBefore.size.height) <= 1.0,
		      "the parent's size does not touch the sheet's own size");
	}

	[[[alert buttons] objectAtIndex:1] performClick:nil];
	check([reception wasCalled], "the caller's did-end method ran");
	check([reception code] == NSAlertSecondButtonReturn, "with the clicked button's code");
	check([parent attachedSheet] == nil, "and the session is over");
	check(![[alert window] isSheet], "the panel is no longer a sheet");
	/* 5d. **AND THE STRIP COMES BACK WITH THE CONTENT INTACT.** A dismissed sheet is an ordinary titled window again —
	 * Apple's contract does not destroy it — so the frame has to be its content plus chrome, with the alert's content
	 * still the size it was built for. */
	check([sheet frame].size.height > contentBefore.size.height,
	      "ending the session gives the window its title bar back: its frame is its content plus a strip");
	check(fabs([sheet contentRectForFrameRect:[sheet frame]].size.height - contentBefore.size.height) <= 1.0,
	      "and the content it was dismissed with is the size the alert laid out for");

	[reception release];
	[parent release];
}

/* **AND THE TWO RELATIVES, WHICH RUN A WINDOW AS A SHEET'S MODAL SESSION.** The RUN form is a loop over the session and
 * is not called here — it is unbounded until something stops it, the same reason `-runModal` is left alone — so what is
 * asserted is the SESSION form: it attaches the sheet, one pass answers "continue", the stop code comes back, and ending
 * the session takes the attachment down. */
static void test_modal_relative(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
						       styleMask:NSTitledWindowMask
							 backing:NSBackingStoreBuffered
							   defer:NO];
	NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 120.0)
						      styleMask:NSTitledWindowMask
							backing:NSBackingStoreBuffered
							  defer:NO];
	NSModalSession session;

	session = [application beginModalSessionForWindow:sheet relativeToWindow:parent];
	check(session != NULL, "`-beginModalSessionForWindow:relativeToWindow:` answers a session");
	check([parent attachedSheet] == sheet, "and the window is attached to the parent as its sheet");
	check([application modalWindow] == sheet, "with the session naming it as the modal window");
	check([application runModalSession:session] == NSRunContinuesResponse,
	      "one pass of the session asks to be called again");
	[application stopModalWithCode:4242];
	check([application runModalSession:session] == 4242, "and the stop's code is what the session answers");
	[application endModalSession:session];
	check([parent attachedSheet] == nil, "ending the session takes the sheet back down");
	check([application modalWindow] == nil, "and there is no modal window any more");

	[sheet release];
	[parent release];
}

/* **AND THE ALERT'S FOUR NEW DOORS: TWO CONSTRUCTORS, THE SUPPRESSION BOX, AND THE DELEGATE'S ONE QUESTION.** The box and
 * the constructor are checked for what they BUILD, and the delegate for what it is TOLD — the help button's action is the
 * sender, so the probe sends what a press would. */
@interface AGAlertWatcher : NSObject <NSAlertDelegate>
{
@public
	int asked;
	BOOL answers;
}
@end

@implementation AGAlertWatcher
- (BOOL)alertShowHelp:(NSAlert *)alert
{
	(void)alert;
	asked++;
	return answers;
}
@end

static void test_alert_sweep(void)
{
	NSAlert *alert;
	NSAlert *fromFormat;
	NSAlert *fromError;
	NSButton *box;
	NSError *error;
	AGAlertWatcher *watcher;

	/* 1. THE FORMAT CONSTRUCTOR. */
	fromFormat = [NSAlert alertWithMessageText:@"Delete 3 items?"
				     defaultButton:@"Delete"
				   alternateButton:@"Cancel"
				       otherButton:nil
		     informativeTextWithFormat:@"%@ cannot be undone.", @"This"];
	check(fromFormat != nil, "+alertWithMessageText:...informativeTextWithFormat: builds an alert");
	check([[fromFormat messageText] isEqual:@"Delete 3 items?"], "with the message it was given");
	check([[fromFormat informativeText] isEqual:@"This cannot be undone."],
	      "and the informative run BUILT FROM THE FORMAT — the argument reached it");
	check([[fromFormat buttons] count] == 2, "with one button per non-nil title, and none for the nil one");

	/* 2. THE ERROR CONSTRUCTOR: the message, the reason and the recovery options. */
	error = [NSError errorWithDomain:@"io.github.agoradesktop.test" code:7
			       userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
					 @"The file could not be saved.", NSLocalizedDescriptionKey,
					 @"The volume is read-only.", NSLocalizedFailureReasonKey,
					 [NSArray arrayWithObjects:@"Save As…", @"Cancel", nil],
					 NSLocalizedRecoveryOptionsErrorKey,
					 nil]];
	fromError = [NSAlert alertWithError:error];
	check(fromError != nil, "+alertWithError: builds an alert from an error");
	check([[fromError messageText] isEqual:@"The file could not be saved."],
	      "whose message is the error's localized description");
	check([[fromError informativeText] isEqual:@"The volume is read-only."],
	      "and whose explanatory line is its localized failure reason");
	check([[fromError buttons] count] == 2 &&
	      [[(NSButton *)[[fromError buttons] objectAtIndex:0] title] isEqual:@"Save As…"],
	      "with a button per recovery option, in the error's own order");
	check([NSAlert alertWithError:nil] == nil, "and a nil error is nil rather than an empty alert");

	/* 3. THE SUPPRESSION BOX IS MADE ON DEMAND, WHICH IS APPLE'S CONTRACT. */
	alert = [[NSAlert alloc] init];
	check(![alert showsSuppressionButton] && [alert suppressionButton] == nil,
	      "a fresh alert has NO suppression box, and asking for one answers nil");
	[alert setShowsSuppressionButton:YES];
	box = [alert suppressionButton];
	check(box != nil && [alert showsSuppressionButton], "`-setShowsSuppressionButton:YES` makes one");
	check([box buttonType] == NSSwitchButton, "and it is a CHECKBOX, which is what a suppression box is");
	[box setTitle:@"Do not ask again"];
	[box setState:NSOnState];
	check([[alert suppressionButton] state] == NSOnState &&
	      [[[alert suppressionButton] title] isEqual:@"Do not ask again"],
	      "and the caller's title and the person's answer live on the BUTTON, which is the object the door hands back");
	[alert setShowsSuppressionButton:NO];
	check([alert suppressionButton] != nil && ![alert showsSuppressionButton],
	      "turning the flag off HIDES the box without destroying the answer it holds");
	[alert release];

	/* 4. THE DELEGATE'S ONE QUESTION, SENT BY THE HELP BUTTON'S ACTION. */
	watcher = [[AGAlertWatcher alloc] init];
	alert = [[NSAlert alloc] init];
	[alert setDelegate:watcher];
	check([alert delegate] == watcher, "the alert answers its delegate through its own typed door");
	watcher->answers = YES;
	[alert cg_helpButtonClicked:nil];
	check(watcher->asked == 1, "the help action ASKS the delegate, once");
	watcher->answers = NO;
	[alert cg_helpButtonClicked:nil];
	check(watcher->asked == 2,
	      "and a NO answer is a second ask: the delegate said it had not handled the request");
	[alert setDelegate:nil];
	[alert cg_helpButtonClicked:nil];
	check(watcher->asked == 2, "with no delegate nothing is asked and the refusal is printed instead");
	[alert release];
	[watcher release];
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];

	test_panel();
	test_alert_content();
	test_alert_answers();
	test_alert_sheet();
	test_modal_relative();
	test_alert_sweep();

	printf("panel_alert: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
