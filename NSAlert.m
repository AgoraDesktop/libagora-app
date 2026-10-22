/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSAlert.m — the content of an alert, the panel that holds it, and the two loops it can run in.
 *
 * **THE LAYOUT IS ARITHMETIC, AND IT IS DONE IN ONE PLACE.** `-layout` wraps the two strings at the text column's
 * width, makes one `NSTextField` per line (this tier's field is one line tall), and places the icon, the text, the
 * accessory and the buttons in a content rect whose height it computes. Nothing is `autoresizingMask`-driven: an
 * alert is a fixed question, and a second copy of the arithmetic in a resize callback would only be a second thing to
 * keep true.
 *
 * **THE BUTTON IS THE ANSWER, AND THE WINDOW IS THE SESSION.** A button's action turns its INDEX into Apple's return
 * code and then ends whichever session is running: `-stopModalWithCode:` for `-runModal`, `-endSheet:returnCode:` for
 * `-beginSheetModalForWindow:…`, and nothing at all for an alert that was only built and never run. That is why the
 * same button works in both modes without the alert knowing which one a caller chose.
 *
 * **RETURN AND ESCAPE ARE THE PANEL'S, BECAUSE THE PUMP HAS NO KEY-EQUIVALENT PASS.** `NSApplication -sendEvent:`
 * gives a key event to the first responder and, when there is none, to the content view; this tier's windows do not
 * offer key equivalents to their buttons the way the Mac's do (the menu bar is the one client of
 * `-performKeyEquivalent:`). So the alert's panel owns a `-keyDown:` that turns Return into the default button and
 * Escape into the cancel button. That is a real behaviour of this class rather than a promise the pump does not keep,
 * and `tests/panel_alert.m` drives it through `-sendEvent:`.
 */
#import <AppKit/NSAlert.h>
#import "AppKitRefusal.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSGeometry.h>

/* THE PANEL'S PROPORTIONS, IN ONE PLACE. Apple's alert is a fixed-width panel with a 64-point icon at the top left,
 * the text to its right, and the buttons along the bottom right; these are the numbers this tier uses for that shape,
 * and they are constants rather than a table because there is one layout. */
#define AG_ALERT_WIDTH		420.0
#define AG_ALERT_MARGIN		 20.0
#define AG_ALERT_ICON_SIZE	 64.0
#define AG_ALERT_ICON_GAP	 16.0
#define AG_ALERT_TEXT_GAP	  6.0
#define AG_ALERT_SECTION_GAP	 16.0
#define AG_ALERT_BUTTON_HEIGHT	 32.0
#define AG_ALERT_BUTTON_GAP	 12.0
#define AG_ALERT_BUTTON_MIN_WIDTH 84.0

/* THE PRIVATE HALF, DECLARED BEFORE THE CLASSES THAT CALL IT: the panel's key handler asks the alert to click a
 * button, and the button's action is the alert's. */
@interface NSAlert (AGPrivate)
- (void)cg_alertButtonClicked:(id)sender;
- (void)cg_clickDefaultButton;
- (void)cg_clickCancelButton;
@end

/* ============================================================================================ *
 * THE ICON, WHICH IS A VIEW BECAUSE AN IMAGE IS NOT ONE.                                        *
 * ============================================================================================ */

/* **A SMALL VIEW THAT DRAWS ONE IMAGE AND NOTHING ELSE.** This tier has no `NSImageView`, and the alert needs exactly
 * what that class's simplest form does: a rectangle whose ink is an image, centred at its native size when the two
 * differ. Making it a view means the icon is a subview with a frame like everything else, so the layout arithmetic and
 * a probe both see it. */
@interface AGAlertIconView : NSView
{
	NSImage *_image;	/* RETAINED */
}
- (void)setImage:(nullable NSImage *)image;
@end

@implementation AGAlertIconView

- (void)setImage:(NSImage *)image
{
	if (_image == image) {
		return;
	}
	[_image release];
	_image = [image retain];
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSSize size;

	(void)dirtyRect;
	if (_image == nil) {
		return;
	}
	size = [_image size];
	if (size.width <= 0.0 || size.height <= 0.0) {
		return;
	}
	/* **AN IMAGE SMALLER THAN THE WELL IS CENTRED; ONE LARGER THAN IT IS SCALED INTO IT.** Apple's alert icon is
	 * 64 points and an application's icon may be 32 (centred, at its own size) or 128 (drawn into the well rather
	 * than overflowing it). `-compositeToPoint:` draws with the point as the image's BOTTOM-LEFT corner, which is the
	 * same origin convention every drawing door in this tree uses; `-drawInRect:` is the scaled path. */
	if (size.width > [self bounds].size.width || size.height > [self bounds].size.height) {
		[_image drawInRect:[self bounds]];
	} else {
		[_image compositeToPoint:NSMakePoint(NSMidX([self bounds]) - size.width / 2.0,
						     NSMidY([self bounds]) - size.height / 2.0)
			       operation:NSCompositingOperationSourceOver];
	}
}

- (void)dealloc
{
	[_image release];
	[super dealloc];
}

@end

/* ============================================================================================ *
 * THE PANEL, WHICH OWNS RETURN AND ESCAPE.                                                      *
 * ============================================================================================ */

/* **THE ALERT'S WINDOW IS A PANEL WITH ONE MORE BEHAVIOUR: TWO KEYS.** The reference back to the alert is NOT
 * retained — the alert retains the panel, and a retained pair would be a cycle — and it is cleared by the alert's
 * `-dealloc` before the panel is released. */
@interface AGAlertPanel : NSPanel
{
	NSAlert *_alert;	/* NOT retained — the alert owns this panel */
}
- (void)cg_setAlert:(nullable NSAlert *)alert;
@end

@implementation AGAlertPanel

- (void)cg_setAlert:(NSAlert *)alert
{
	_alert = alert;
}

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event characters];
	BOOL defaultButton;
	BOOL cancelButton;

	if (_alert == nil) {
		[super keyDown:event];
		return;
	}
	/* RETURN (AND A NEWLINE, WHICH A COMPOSITOR MAY SEND FOR THE SAME KEY) IS THE DEFAULT BUTTON; ESCAPE IS THE
	 * CANCEL BUTTON. Both are decided here rather than by `-performKeyEquivalent:`, because this tier's pump does
	 * not offer key equivalents to windows — see the file's header. */
	defaultButton = ([characters isEqualToString:@"\r"] || [characters isEqualToString:@"\n"]);
	cancelButton = [characters isEqualToString:@"\033"];
	if (!defaultButton && !cancelButton) {
		[super keyDown:event];
		return;
	}
	/* **THE PANEL HOLDS ITSELF ACROSS THE CLICK, BECAUSE THE CLICK MAY RELEASE IT.** A sheet's reply can release
	 * the alert, and the alert owns this panel; without the retain, the button's action could free the object whose
	 * `-keyDown:` is still on the stack. The same rule `NSWindow`'s chrome buttons follow, applied to the one
	 * action a panel runs. */
	[self retain];
	if (defaultButton) {
		[_alert cg_clickDefaultButton];
	} else {
		[_alert cg_clickCancelButton];
	}
	[self release];
}

@end

/* ============================================================================================ *
 * THE TEXT, MEASURED AND WRAPPED.                                                               *
 * ============================================================================================ */

/* **ONE LINE PER WORD RUN THAT FITS, AND A NEW LINE FOR EVERY HARD BREAK.** `-sizeWithAttributes:` is this tier's
 * single-line measurement (there is no `-boundingRectWithSize:` at this pin), so the wrap is a greedy walk with that
 * measurement as its test. A word WIDER than the column goes on its own line and overflows rather than being split:
 * breaking inside a word is hyphenation's job and this tier's hyphenation zone is a different slice. An empty
 * paragraph is one empty line, because a blank line in an alert is a line. */
static NSArray *fn_wrap_text(NSString *text, NSFont *font, CGFloat width)
{
	NSMutableArray *lines;
	NSArray *paragraphs;
	NSDictionary *attributes;
	NSUInteger p;

	lines = [NSMutableArray array];
	if (text == nil || [text length] == 0) {
		return lines;
	}
	attributes = [NSDictionary dictionaryWithObject:(id)font forKey:NSFontAttributeName];
	paragraphs = [text componentsSeparatedByString:@"\n"];
	for (p = 0; p < [paragraphs count]; p++) {
		NSString *paragraph = [paragraphs objectAtIndex:p];
		NSArray *words = [paragraph componentsSeparatedByString:@" "];
		NSString *line = @"";
		NSUInteger w;

		if ([paragraph length] == 0) {
			[lines addObject:@""];
			continue;
		}
		for (w = 0; w < [words count]; w++) {
			NSString *word = [words objectAtIndex:w];
			NSString *candidate;

			if ([line length] == 0) {
				candidate = word;
			} else {
				candidate = [line stringByAppendingFormat:@" %@", word];
			}
			if ([candidate sizeWithAttributes:attributes].width <= width || [line length] == 0) {
				line = candidate;
			} else {
				[lines addObject:line];
				line = word;
			}
		}
		[lines addObject:line];
	}
	return lines;
}

/* **A LABEL IS A FIELD THAT DOES NOT EDIT.** The flag set below is the same one every label in this tree sets, and it
 * is what keeps a line of alert text from growing a bezel, a background or a caret. */
static NSTextField *fn_make_label(NSString *line, NSFont *font, NSColor *color)
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

	[field setEditable:NO];
	[field setSelectable:YES];
	[field setBordered:NO];
	[field setBezeled:NO];
	[field setDrawsBackground:NO];
	[field setFont:font];
	if (color != nil) {
		[field setTextColor:color];
	}
	[field setStringValue:line];
	return [field autorelease];
}

static CGFloat fn_label_height(NSTextField *field, CGFloat width)
{
	NSSize size = [[field cell] cellSizeForBounds:NSMakeRect(0.0, 0.0, width, 1000.0)];

	return size.height;
}

/* THE BOLD MESSAGE FONT AND THE SMALLER INFORMATIVE ONE, asked from the font system rather than written as sizes: the
 * alert's hierarchy is a font WEIGHT, and a size of its own would not follow the system's. */
static NSFont *fn_message_font(void)
{
	return [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
}

static NSFont *fn_informative_font(void)
{
	return [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
}

/* ============================================================================================ *
 * THE ALERT.                                                                                    *
 * ============================================================================================ */

@implementation NSAlert

+ (NSAlert *)alertWithMessageText:(NSString *)message
			    title:(NSString *)title
		    defaultButton:(NSString *)defaultButtonLabel
		  alternateButton:(NSString *)alternateButtonLabel
		      otherButton:(NSString *)otherButtonLabel
{
	NSAlert *alert = [[[self alloc] init] autorelease];

	[alert setMessageText:message];
	alert->_title = [title copy];
	if (defaultButtonLabel != nil) {
		[alert addButtonWithTitle:defaultButtonLabel];
	}
	if (alternateButtonLabel != nil) {
		[alert addButtonWithTitle:alternateButtonLabel];
	}
	if (otherButtonLabel != nil) {
		[alert addButtonWithTitle:otherButtonLabel];
	}
	return alert;
}

+ (NSAlert *)alertWithMessageText:(NSString *)message
		    defaultButton:(NSString *)defaultButtonLabel
		  alternateButton:(NSString *)alternateButtonLabel
		      otherButton:(NSString *)otherButtonLabel
	informativeTextWithFormat:(NSString *)format, ...
{
	NSAlert *alert = [self alertWithMessageText:message title:nil defaultButton:defaultButtonLabel
				    alternateButton:alternateButtonLabel otherButton:otherButtonLabel];

	if (format != nil) {
		va_list args;
		NSString *informative;

		va_start(args, format);
		informative = [[NSString alloc] initWithFormat:format arguments:args];
		va_end(args);
		[alert setInformativeText:informative];
		[informative release];
	}
	return alert;
}

/* **AN ALERT OUT OF AN ERROR IS A TRANSLATION AND NOTHING MORE.** The message is the error's localized description; the
 * informative run is its localized failure reason (nil when it has none, and nil text is simply no line); the buttons are
 * its recovery options in the order it gives them, and an error offering no options gets the one button every alert needs
 * — OK. THE DOMAIN AND CODE ARE NOT PRINTED: an alert is what a person reads, and the technical detail belongs in a log. */
+ (NSAlert *)alertWithError:(NSError *)error
{
	NSAlert *alert;
	NSArray *options;
	NSString *reason;

	if (error == nil) {
		return nil;
	}
	alert = [[[self alloc] init] autorelease];
	[alert setMessageText:[error localizedDescription]];
	reason = [error localizedFailureReason];
	if (reason != nil) {
		[alert setInformativeText:reason];
	}
	options = [error localizedRecoveryOptions];
	if ([options count] == 0) {
		[alert addButtonWithTitle:@"OK"];
	} else {
		NSUInteger i;

		for (i = 0; i < [options count]; i++) {
			[alert addButtonWithTitle:[[options objectAtIndex:i] description]];
		}
	}
	return alert;
}

- (instancetype)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* **THE DEFAULTS AN IVAR CANNOT GIVE.** A warning is Apple's default style, and the three pieces of state are
	 * the arrays the buttons and the wrapped lines live in — a window made from a bare `-init` alert still has a
	 * frame to compute, and `-layout` is what computes it. */
	_alertStyle = NSWarningAlertStyle;
	_buttons = [[NSMutableArray alloc] init];
	_messageLines = [[NSMutableArray alloc] init];
	_informativeLines = [[NSMutableArray alloc] init];
	return self;
}

- (void)dealloc
{
	/* THE PANEL'S BACK-REFERENCE IS CLEARED FIRST: it is not retained, so releasing the panel while it still named
	 * this object would leave a dangling pointer if anything kept the window alive. */
	if (_window != nil) {
		[(AGAlertPanel *)_window cg_setAlert:nil];
	}
	[_window release];
	/* THE ICON VIEW IS HELD TWICE: the content view retains it as a subview and this object retains the ALLOC that
	 * made it. Releasing the window releases the first; this releases the second. */
	[_iconView release];
	[_title release];
	[_messageText release];
	[_informativeText release];
	[_helpAnchor release];
	[_icon release];
	[_buttons release];
	[_messageLines release];
	[_informativeLines release];
	[_accessoryView release];
	[_suppressionButton release];
	[_helpButton release];
	[super dealloc];
}

/* ---- THE TEXT AND THE ICON ------------------------------------------------------------------ */

- (NSString *)messageText
{
	return _messageText;
}

- (void)setMessageText:(NSString *)string
{
	NSString *copy = [string copy];

	[_messageText release];
	_messageText = copy;
	[self layout];
}

- (NSString *)informativeText
{
	return _informativeText;
}

- (void)setInformativeText:(NSString *)string
{
	NSString *copy = [string copy];

	[_informativeText release];
	_informativeText = copy;
	[self layout];
}

- (NSImage *)icon
{
	/* **THE DEFAULT IS THE APPLICATION'S ICON, WHICH IS APPLE'S ANSWER.** The style does not change it: an
	 * application that wants a caution or info picture sets one, and this tier has no system art to substitute. */
	if (_icon != nil) {
		return _icon;
	}
	return [[NSApplication sharedApplication] applicationIconImage];
}

- (void)setIcon:(NSImage *)image
{
	if (_icon == image) {
		return;
	}
	[_icon release];
	_icon = [image retain];
	[self layout];
}

/* ---- THE BUTTONS ---------------------------------------------------------------------------- */

- (NSButton *)addButtonWithTitle:(NSString *)title
{
	NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, AG_ALERT_BUTTON_MIN_WIDTH,
								     AG_ALERT_BUTTON_HEIGHT)];

	[button setTitle:title];
	[button setButtonType:NSMomentaryPushInButton];
	[button setBezelStyle:NSRoundedBezelStyle];
	[button setTarget:self];
	[button setAction:@selector(cg_alertButtonClicked:)];
	/* **THE KEYS ARE ASSIGNED BY POSITION, AS APPLE ASSIGNS THEM.** The first button answers Return, the second
	 * answers Escape, and a third has no key of its own. A caller that wants a different key sets it after this
	 * returns; that is why the assignment happens here and not in `-layout`, which runs again. */
	if ([_buttons count] == 0) {
		[button setKeyEquivalent:@"\r"];
	} else if ([_buttons count] == 1) {
		[button setKeyEquivalent:@"\033"];
	}
	[_buttons addObject:button];
	[button release];
	[self layout];
	return button;
}

- (NSArray *)buttons
{
	return [NSArray arrayWithArray:_buttons];
}

/* ---- THE STYLE, THE ACCESSORY AND THE HELP PAIR --------------------------------------------- */

- (NSAlertStyle)alertStyle
{
	return _alertStyle;
}

- (void)setAlertStyle:(NSAlertStyle)style
{
	/* **RECORDED AND NOT READ.** This tier paints one panel shape and has no system icon art to choose between, so the
	 * value cannot change the frame or the picture. It still round-trips because a caller reads it back and because
	 * Apple's own door exists; the honesty is here rather than in a comment a caller never sees. */
	_alertStyle = style;
}

- (NSView *)accessoryView
{
	return _accessoryView;
}

- (void)setAccessoryView:(NSView *)view
{
	if (_accessoryView == view) {
		return;
	}
	if (_accessoryView != nil) {
		[_accessoryView removeFromSuperview];
	}
	[_accessoryView release];
	_accessoryView = [view retain];
	[self layout];
}

- (BOOL)showsHelp
{
	return _showsHelp;
}

- (void)setShowsHelp:(BOOL)flag
{
	_showsHelp = flag ? YES : NO;
	if (_showsHelp) {
		[self cg_ensureHelpButton];
		if (_window != nil && [_helpButton superview] != [_window contentView]) {
			[[_window contentView] addSubview:_helpButton];
		}
	} else if (_helpButton != nil) {
		[_helpButton removeFromSuperview];
	}
	[self layout];
}

- (NSString *)helpAnchor
{
	return _helpAnchor;
}

- (void)setHelpAnchor:(NSString *)anchor
{
	NSString *copy = [anchor copy];

	[_helpAnchor release];
	_helpAnchor = copy;
}

/* ---- THE SUPPRESSION BUTTON, THE DELEGATE, AND THE HELP BUTTON --------------------------------- */

- (BOOL)showsSuppressionButton
{
	return _suppressionButton != nil && ![_suppressionButton isHidden];
}

- (void)setShowsSuppressionButton:(BOOL)flag
{
	if (flag) {
		/* **THE BUTTON IS MADE THE FIRST TIME THE FLAG IS SET, WITH AN EMPTY TITLE.** Apple's alert's suppression
		 * button starts as a bare checkbox and the caller writes the words on it — which is why the title is not part
		 * of this door: "do not show this again" is the CALLER's sentence, and an alert cannot know what it suppresses. */
		if (_suppressionButton == nil) {
			_suppressionButton = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 18.0)];
			[_suppressionButton setButtonType:NSSwitchButton];
			[_suppressionButton setTitle:@""];
		}
		[_suppressionButton setHidden:NO];
		if (_window != nil && [_suppressionButton superview] != [_window contentView]) {
			[[_window contentView] addSubview:_suppressionButton];
		}
	} else if (_suppressionButton != nil) {
		[_suppressionButton setHidden:YES];
	}
	[self layout];
}

- (NSButton *)suppressionButton
{
	return _suppressionButton;
}

- (id <NSAlertDelegate>)delegate
{
	return (id <NSAlertDelegate>)_delegate;
}

- (void)setDelegate:(id <NSAlertDelegate>)anObject
{
	_delegate = anObject;	/* NOT RETAINED */
}

/* **THE HELP BUTTON IS THE CALLER OF `-alertShowHelp:`, AND ITS ANSWER IS WHAT MAKES THE DELEGATE DOOR REAL.** A YES
 * from the delegate means it handled the request (opened its own window, say); anything else means "show the alert's help
 * anchor", and this tier has no Help Viewer — so that branch is REFUSED BY NAME rather than silently doing nothing, and
 * the message says which anchor it would have opened. */
- (void)cg_helpButtonClicked:(id)sender
{
	BOOL handled = NO;

	(void)sender;
	if (_delegate != nil && [_delegate respondsToSelector:@selector(alertShowHelp:)]) {
		handled = [_delegate alertShowHelp:self];
	}
	if (!handled) {
		fn_refuse_window("-[NSAlert help]", "a Help Viewer to open the alert's help anchor (the delegate did not "
				 "handle `-alertShowHelp:`, and this tier has no Help Viewer)");
	}
}

/* THE "?" IS MADE WHEN THE FLAG IS SET, the same way the suppression button is: Apple's alert shows it in the title bar
 * and this tier has no title-bar accessory, so it joins the BUTTON ROW at its left end — where a Help button sits on the
 * alerts that have one. */
- (void)cg_ensureHelpButton
{
	if (_helpButton != nil) {
		return;
	}
	_helpButton = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 24.0, AG_ALERT_BUTTON_HEIGHT)];
	[_helpButton setTitle:@"?"];
	[_helpButton setTarget:self];
	[_helpButton setAction:@selector(cg_helpButtonClicked:)];
}

/* ---- THE WINDOW ----------------------------------------------------------------------------- */

- (NSWindow *)window
{
	if (_window != nil) {
		return _window;
	}
	/* **THE PANEL IS MADE ONCE AND REUSED.** Apple's alert owns one window for its lifetime, so a second `-runModal`
	 * reuses the same panel rather than building a second one; `-layout` is what makes the reuse safe. */
	_window = [[AGAlertPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, AG_ALERT_WIDTH, 120.0)
						 styleMask:NSTitledWindowMask
						   backing:NSBackingStoreBuffered
						     defer:NO];
	[(AGAlertPanel *)_window cg_setAlert:self];
	[_window setLevel:NSModalPanelWindowLevel];
	[_window setFloatingPanel:YES];
	[_window setReleasedWhenClosed:NO];
	/* **AN ALERT STAYS ON THE SCREEN WHEN THE APPLICATION DOES NOT.** `NSPanel`'s default is the opposite
	 * (`hidesOnDeactivate` YES, because a palette belongs to an active application), and an alert that vanished while
	 * an application-modal loop kept running would leave a modal session with no visible question to answer. Apple's
	 * alert panel is the panel-shaped exception, and this is where it is made. */
	[_window setHidesOnDeactivate:NO];
	[_window setTitle:(_title != nil ? _title : @"")];
	{
		NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, AG_ALERT_WIDTH, 120.0)];

		[_window setContentView:content];
		[content release];
	}
	_iconView = [[AGAlertIconView alloc] initWithFrame:NSMakeRect(AG_ALERT_MARGIN,
								     AG_ALERT_MARGIN,
								     AG_ALERT_ICON_SIZE,
								     AG_ALERT_ICON_SIZE)];
	[[_window contentView] addSubview:_iconView];
	[self layout];
	return _window;
}

/* ---- THE ARITHMETIC ------------------------------------------------------------------------- */

- (void)layout
{
	NSView *content;
	NSFont *messageFont;
	NSFont *informativeFont;
	NSArray *messageLines;
	NSArray *informativeLines;
	CGFloat contentWidth = AG_ALERT_WIDTH;
	CGFloat iconWidth;
	CGFloat textWidth;
	CGFloat textHeight = 0.0;
	CGFloat messageHeight = 0.0;
	CGFloat informativeHeight = 0.0;
	CGFloat textTop;
	CGFloat contentHeight;
	CGFloat accessoryHeight;
	CGFloat buttonRow = 0.0;
	CGFloat x;
	CGFloat y;
	BOOL hasIcon;
	NSUInteger i;

	/* **WITHOUT A WINDOW THERE IS NOTHING TO LAY OUT, AND THAT IS NOT A FAILURE.** Every setter calls this door so a
	 * caller never has to remember the order; the first `-window` is what builds the views, and its own call is the
	 * one that matters. */
	if (_window == nil) {
		return;
	}
	content = [_window contentView];
	messageFont = fn_message_font();
	informativeFont = fn_informative_font();
	hasIcon = ([self icon] != nil);
	iconWidth = hasIcon ? (AG_ALERT_ICON_SIZE + AG_ALERT_ICON_GAP) : 0.0;
	textWidth = contentWidth - 2.0 * AG_ALERT_MARGIN - iconWidth;
	if (textWidth < 40.0) {
		textWidth = 40.0;	/* a width this narrow is a caller's window, not an alert's; keep a column */
	}

	/* THE OLD LINES ARE TAKEN DOWN BEFORE THE NEW ONES GO UP, and the arrays are emptied rather than replaced so
	 * the two ivars keep their identity. */
	for (i = 0; i < [_messageLines count]; i++) {
		[[_messageLines objectAtIndex:i] removeFromSuperview];
	}
	[_messageLines removeAllObjects];
	for (i = 0; i < [_informativeLines count]; i++) {
		[[_informativeLines objectAtIndex:i] removeFromSuperview];
	}
	[_informativeLines removeAllObjects];

	messageLines = fn_wrap_text(_messageText, messageFont, textWidth);
	for (i = 0; i < [messageLines count]; i++) {
		NSTextField *field = fn_make_label([messageLines objectAtIndex:i], messageFont,
						   [NSColor controlTextColor]);

		[content addSubview:field];
		[_messageLines addObject:field];
		messageHeight += fn_label_height(field, textWidth);
	}
	informativeLines = fn_wrap_text(_informativeText, informativeFont, textWidth);
	for (i = 0; i < [informativeLines count]; i++) {
		NSTextField *field = fn_make_label([informativeLines objectAtIndex:i], informativeFont,
						   [NSColor darkGrayColor]);

		[content addSubview:field];
		[_informativeLines addObject:field];
		informativeHeight += fn_label_height(field, textWidth);
	}
	textHeight = messageHeight;
	if (messageHeight > 0.0 && informativeHeight > 0.0) {
		textHeight += AG_ALERT_TEXT_GAP;
	}
	textHeight += informativeHeight;

	accessoryHeight = (_accessoryView != nil) ? [_accessoryView frame].size.height : 0.0;
	if ([_buttons count] > 0) {
		buttonRow = AG_ALERT_BUTTON_HEIGHT;
	}
	{
		CGFloat topBlock = hasIcon ? (textHeight > AG_ALERT_ICON_SIZE ? textHeight : AG_ALERT_ICON_SIZE) : textHeight;

		contentHeight = AG_ALERT_MARGIN
			+ topBlock
			+ (accessoryHeight > 0.0 ? AG_ALERT_SECTION_GAP + accessoryHeight : 0.0)
			+ (buttonRow > 0.0 ? AG_ALERT_SECTION_GAP + buttonRow : 0.0)
			+ AG_ALERT_MARGIN;
	}
	/* A MINIMUM, BECAUSE A ONE-LINE ALERT IS STILL A PANEL RATHER THAN A STRIP: the two margins and the button row
	 * are the floor Apple's own alerts keep. */
	if (contentHeight < 100.0) {
		contentHeight = 100.0;
	}

	/* THE WINDOW'S SIZE IS THE CONTENT'S, AND IT IS SET BEFORE THE SUBVIEWS ARE PLACED so the content view's own
	 * frame is already the one the arithmetic uses. */
	[_window setContentSize:NSMakeSize(contentWidth, contentHeight)];
	[content setFrame:NSMakeRect(0.0, 0.0, contentWidth, contentHeight)];

	/* THE ICON SITS AT THE TOP LEFT. */
	[(AGAlertIconView *)_iconView setImage:[self icon]];
	[_iconView setFrame:NSMakeRect(AG_ALERT_MARGIN,
				       contentHeight - AG_ALERT_MARGIN - AG_ALERT_ICON_SIZE,
				       AG_ALERT_ICON_SIZE,
				       AG_ALERT_ICON_SIZE)];
	[_iconView setHidden:!hasIcon];

	/* THE TEXT DESCENDS FROM THE TOP, FIRST THE BOLD MESSAGE AND THEN THE INFORMATIVE RUN. */
	textTop = contentHeight - AG_ALERT_MARGIN;
	x = AG_ALERT_MARGIN + iconWidth;
	for (i = 0; i < [_messageLines count]; i++) {
		NSTextField *field = [_messageLines objectAtIndex:i];
		CGFloat height = fn_label_height(field, textWidth);

		[field setFrame:NSMakeRect(x, textTop - height, textWidth, height)];
		textTop -= height;
	}
	if ([_messageLines count] > 0 && [_informativeLines count] > 0) {
		textTop -= AG_ALERT_TEXT_GAP;
	}
	for (i = 0; i < [_informativeLines count]; i++) {
		NSTextField *field = [_informativeLines objectAtIndex:i];
		CGFloat height = fn_label_height(field, textWidth);

		[field setFrame:NSMakeRect(x, textTop - height, textWidth, height)];
		textTop -= height;
	}

	/* THE ACCESSORY SPANS THE WIDTH BETWEEN THE MARGINS, ABOVE THE BUTTONS. */
	if (_accessoryView != nil) {
		if ([_accessoryView superview] != content) {
			[content addSubview:_accessoryView];
		}
		[_accessoryView setFrame:NSMakeRect(AG_ALERT_MARGIN,
						    AG_ALERT_MARGIN + buttonRow + AG_ALERT_SECTION_GAP,
						    contentWidth - 2.0 * AG_ALERT_MARGIN,
						    accessoryHeight)];
	}

	/* **AND THE TWO BOXES THE SWEEP ADDS SHARE THE BUTTON ROW.** The HELP button sits at the far LEFT — the end a Help
	 * button occupies on the alerts that have one — and the SUPPRESSION box beside it, which is where Apple puts "do not
	 * show this again": opposite the answers, under the text it suppresses, so it reads as a remark about the question
	 * rather than as another answer to it. Both are sized to fit and both are skipped when hidden. */
	y = AG_ALERT_MARGIN;
	if (_helpButton != nil && ![_helpButton isHidden]) {
		[_helpButton setFrame:NSMakeRect(AG_ALERT_MARGIN, y, 24.0, AG_ALERT_BUTTON_HEIGHT)];
		if ([_helpButton superview] != content) {
			[content addSubview:_helpButton];
		}
	}
	if (_suppressionButton != nil && ![_suppressionButton isHidden]) {
		[_suppressionButton sizeToFit];
		[_suppressionButton setFrame:NSMakeRect(AG_ALERT_MARGIN + ((_helpButton != nil && ![_helpButton isHidden]) ? 32.0 : 0.0),
						       y + floor((AG_ALERT_BUTTON_HEIGHT - [_suppressionButton frame].size.height) / 2.0),
						       [_suppressionButton frame].size.width,
						       [_suppressionButton frame].size.height)];
		if ([_suppressionButton superview] != content) {
			[content addSubview:_suppressionButton];
		}
	}

	/* **THE BUTTONS RUN RIGHT TO LEFT, FIRST BUTTON RIGHTMOST**, which is Apple's order and the reason the default
	 * answer is the one under the Return key at the right edge. */
	x = contentWidth - AG_ALERT_MARGIN;
	for (i = 0; i < [_buttons count]; i++) {
		NSButton *button = [_buttons objectAtIndex:i];
		CGFloat width;

		[button sizeToFit];
		width = [button frame].size.width;
		if (width < AG_ALERT_BUTTON_MIN_WIDTH) {
			width = AG_ALERT_BUTTON_MIN_WIDTH;
		}
		x -= width;
		[button setFrame:NSMakeRect(x, y, width, AG_ALERT_BUTTON_HEIGHT)];
		if ([button superview] != content) {
			[content addSubview:button];
		}
		x -= AG_ALERT_BUTTON_GAP;
	}
}

/* ---- THE ANSWER ----------------------------------------------------------------------------- */

/* THE INDEX TO APPLE'S CODE: the first three buttons have their own names, and a fourth or later is `1000 + index`.
 * That is Apple's own arithmetic, stated where it is performed. */
- (NSInteger)cg_codeForButtonAtIndex:(NSUInteger)index
{
	/* THE FIRST THREE HAVE THEIR OWN NAMES IN `NSAlert.h`; a fourth or later is `1000 + index`. Both spellings are
	 * the same arithmetic, which is why this is one expression rather than a switch. */
	return 1000 + (NSInteger)index;
}

- (void)cg_alertButtonClicked:(id)sender
{
	NSUInteger index = [_buttons indexOfObject:sender];
	NSInteger code;

	if (index == NSNotFound) {
		return;
	}
	code = [self cg_codeForButtonAtIndex:index];
	/* **WHICH SESSION, IF ANY, IS THE WINDOW'S OWN ANSWER.** A sheet has a parent (`-isSheet`), a modal session is
	 * the application's current one, and an alert that was built and never run has neither — in that last case the
	 * click does nothing. NOTHING IS TOUCHED AFTER EITHER CALL, which is a use-after-free rule rather than tidiness:
	 * a sheet's did-end callback is free to release the alert (Apple's contract, and `NSApplication -endSheet:` says
	 * so where it runs the reply), so `code` is taken into a local first and `self` is not read again. */
	if ([_window isSheet]) {
		[[NSApplication sharedApplication] endSheet:_window returnCode:code];
		return;
	}
	if ([[NSApplication sharedApplication] modalWindow] == _window) {
		[[NSApplication sharedApplication] stopModalWithCode:code];
	}
}

- (void)cg_clickDefaultButton
{
	if ([_buttons count] > 0) {
		[(NSButton *)[_buttons objectAtIndex:0] performClick:nil];
	}
}

- (void)cg_clickCancelButton
{
	/* **THE CANCEL BUTTON IS THE SECOND, AND AN ALERT WITH ONE BUTTON HAS NONE.** Apple's Escape equivalent is the
	 * second button; a one-button alert is dismissed by its one button and by Return, and Escape does nothing, which
	 * is what the 10.6 alert does. */
	if ([_buttons count] > 1) {
		[(NSButton *)[_buttons objectAtIndex:1] performClick:nil];
	}
}

- (NSInteger)runModal
{
	NSInteger code;

	(void)[self window];
	[self layout];
	[_window center];
	code = [[NSApplication sharedApplication] runModalForWindow:_window];
	/* **THE PANEL GOES AWAY, BECAUSE THE CALL HAS RETURNED.** Apple's `-runModal` orders the alert out before it
	 * answers; the sheet form does not, because its caller's callback is the one that dismisses a sheet. */
	[_window orderOut:nil];
	return code;
}

- (void)beginSheetModalForWindow:(NSWindow *)window
		  modalDelegate:(id)modalDelegate
		 didEndSelector:(SEL)didEndSelector
		    contextInfo:(void *)contextInfo
{
	(void)[self window];
	[self layout];
	[[NSApplication sharedApplication] beginSheet:_window
				       modalForWindow:window
					modalDelegate:modalDelegate
				       didEndSelector:didEndSelector
					  contextInfo:contextInfo];
}

@end
