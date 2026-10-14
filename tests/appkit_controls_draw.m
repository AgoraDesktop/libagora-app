/*
 * appkit_controls_draw — a window full of CONTROLS under a real MENU BAR, on a display.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE DEMONSTRATION FOR THE CONTROL LAYER, AND IT IS A DEMONSTRATION RATHER THAN A TEST.** The offscreen
 * `control_ink` test asserts the pixels; this puts the controls in a real window on Agora's window server so what the
 * slice draws can be LOOKED at — and it is what found the subview-placement defect in `NSView -displayRect:`, which
 * no offscreen draw of a single view could have shown.
 *
 * **AND IT SETS A MAIN MENU, WHICH THE FIRST VERSION DID NOT.** A window with controls and no `-setMainMenu:` leaves
 * the bar showing only the server's System menu — the application's own menus are put there BY the application, so a
 * demonstration that never sets one shows no application menus at all. It sets one now, and the two halves
 * demonstrate EACH OTHER: the View menu's "Show Grid" is a CHECKED item whose state is validated against the
 * checkbox below it, "Undo" is DISABLED by the same validator, and the push button TOGGLES the checkbox — so a click
 * on a control changes a menu item, and the menu reports what the control says.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSText.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/AGChromeTheme.h>	/* the chrome's theme, which this demonstration loads by DEFAULT */
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* **THE TARGET BOTH HALVES POINT AT.** A menu item's action, a button's action and a validator all end here, which
 * is what makes the checkbox and the View menu one piece of state rather than two that look alike. */
@interface AGControlsController : NSObject
{
@public
	NSButton *checkbox;
	/* **AND THE SLIDER PAIR: the control, and the button whose TITLE is used as a readout.** A slider's whole
	 * difference from a checkbox is that its value MOVES while it is dragged, so the demonstration needs something
	 * that shows a value and not a state — and a button with a changing title is the one such surface this tier has.
	 *
	 * AND THERE ARE TWO SLIDERS RATHER THAN ONE, because the grabber's SHAPE depends on the tick count: with tick
	 * marks to point at it is a teardrop, and without them it is a circle. A demonstration of a rule that shows only
	 * one side of it is a demonstration of half a rule. */
	NSButton *readout;
	NSSlider *slider;
	NSSlider *plain;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)toggleCheckbox:(id)sender;
- (void)sliderMoved:(id)sender;
- (void)noop:(id)sender;
@end

@implementation AGControlsController

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	NSString *title = [item title];

	/* THE CHECKED ITEM'S STATE COMES FROM THE CONTROL, so the menu and the checkbox cannot disagree: the menu is
	 * opened with `-update`, which asks this, and this reads the button. */
	if ([title isEqualToString:@"Show Grid"]) {
		[item setState:[checkbox state]];
		return YES;
	}
	/* AND ONE DISABLED ITEM TO LOOK AT: nothing here can undo, so the item greys out and refuses the highlight —
	 * the two halves of menu VALIDATION, shown rather than described. */
	if ([title isEqualToString:@"Undo"]) {
		return NO;
	}
	return YES;
}

- (void)toggleCheckbox:(id)sender
{
	(void)sender;
	[checkbox setState:([checkbox state] == NSOnState) ? NSOffState : NSOnState];
	[checkbox setNeedsDisplay:YES];
}

/* **THE SLIDER'S ACTION, WHICH IS WHERE CONTINUOUS TRACKING BECOMES VISIBLE.** A slider sends its action while it is
 * dragged rather than once when the button comes up, so this readout's title follows the knob — and if the flag were
 * off, the title would only change on release. That is the difference the probe pins one class over, shown here.
 *
 * **AND IT READS THE SENDER RATHER THAN A FIXED IVAR, BECAUSE THERE ARE TWO SLIDERS.** A handler that read one
 * slider's value would report the WRONG one the moment the other was dragged — which is the sort of thing a
 * demonstration with two of something exists to make impossible. */
- (void)sliderMoved:(id)sender
{
	NSSlider *moved = (NSSlider *)sender;

	[readout setTitle:[NSString stringWithFormat:@"Value: %.0f", [moved doubleValue]]];
	[readout setNeedsDisplay:YES];
	/* AND ONE LINE OUT, so that a live drag can be READ rather than only looked at: a continuous slider prints once
	 * per point, which is the behaviour the probe pins and this makes observable from outside the process. */
	fprintf(stderr, "controls: slider -> %.1f\n", [moved doubleValue]);
}

/* AN ITEM WITH NO WORK TO DO BUT SOMETHING TO BE: a menu item whose action is NULL is DISABLED by the auto-enabling
 * walk (nothing answers it), so the items that are here to be LOOKED at carry this instead — enabled, and honestly
 * doing nothing but saying so. */
- (void)noop:(id)sender
{
	fprintf(stderr, "controls: menu item chosen: %s\n", [[(NSMenuItem *)sender title] UTF8String]);
}

@end

/* ONE TITLE, ITS ITEMS, AND WHOSE ACTION THEY CARRY. Written as a helper because the bar below makes four of them and
 * the repetition is the shape of a menu rather than a decision. */
/* **A KEY EQUIVALENT, WITH THE MODIFIER MASK THE MATCHER WANTS.** `-performKeyEquivalent:` compares an event's
 * `-charactersIgnoringModifiers` — which the seam produces WITH Shift applied, so a shifted key arrives as an
 * UPPERCASE letter — against the item's key equivalent, and it compares the MASK EXACTLY. So an uppercase key takes
 * both bits and a lowercase one Command alone, which is what makes Cmd-Z undo and Shift-Cmd-Z redo rather than two
 * spellings of one shortcut. THE MASK IS SET EXPLICITLY rather than left to a default: a fresh item in this tier
 * carries NO modifier at all, and a shortcut nobody meant to type is not a shortcut. */
static void fn_set_key(NSMenuItem *item, NSString *key)
{
	NSUInteger mask = NSCommandKeyMask;

	if ([key length] == 1) {
		unichar c = [key characterAtIndex:0];

		if (c >= 'A' && c <= 'Z') {
			mask |= NSShiftKeyMask;
		}
	}
	[item setKeyEquivalent:key];
	[item setKeyEquivalentModifierMask:mask];
}

static NSMenuItem *add_menu(NSMenu *bar, NSString *title, NSArray *itemTitles, NSArray *keys, id target, SEL action)
{
	NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
	NSMenu *contents = [[NSMenu alloc] initWithTitle:title];
	NSUInteger i;

	for (i = 0; i < [itemTitles count]; i++) {
		NSString *name = [itemTitles objectAtIndex:i];
		NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:name action:action keyEquivalent:@""];

		/* THE KEYS ARE A PARALLEL ARRAY rather than part of the title, because a key equivalent is an ITEM's and
		 * not a menu's: two items in one menu may carry different modifiers (undo and redo), so the pair travels
		 * with the item. */
		if (i < [keys count]) {
			fn_set_key(entry, [keys objectAtIndex:i]);
		}
		[entry setTarget:target];
		[contents addItem:entry];
		[entry release];
	}
	[titleItem setSubmenu:contents];
	[contents release];
	[bar addItem:titleItem];
	return titleItem;
}

int main(int argc, char **argv)
{
	int seconds = 0;
	int i;

	/* **THE CHROME'S THEME IS THIS DEMONSTRATION'S DEFAULT, WHICH IS WHAT MAKES IT THE THING TO ITERATE ON.** The
	 * library reads a theme only when `AGORA_CHROME_THEME` names one — that is the whole of the mechanism, and it is
	 * the right default for a LIBRARY, which must not go looking for other people's art. A DEMONSTRATION is the other
	 * case: the chrome is the thing being looked at, so this points the variable at the tree's own `themes/` when a
	 * caller has not, and an explicit `AGORA_CHROME_THEME` still wins. A checkout with no theme there resolves none and
	 * falls back to the marks `NSWindow` draws, which is why the default can be unconditional. */
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
			seconds = atoi(argv[++i]);
		}
	}
#ifdef AGORA_CHROME_DEFAULT_THEME
	if (getenv("AGORA_CHROME_THEME") == NULL) {
		setenv("AGORA_CHROME_THEME", AGORA_CHROME_DEFAULT_THEME, 1);
	}
#endif
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		AGControlsController *controller = [[AGControlsController alloc] init];
		NSMenu *bar = [[NSMenu alloc] initWithTitle:@"MainMenu"];
		NSWindow *w;
		NSView *content;
		NSButton *push;
		NSButton *alt;
		NSButton *check;
		NSButton *radio;
		NSButton *off;
		NSButton *readout;
		NSSlider *slider;
		NSSlider *plain;
		/* **AND A TEXT VIEW, WHICH IS THE ONE CONTROL IN THIS WINDOW THAT TAKES THE KEYBOARD.** It is made the
		 * window's first responder below, so a keystroke goes to it rather than nowhere: the window sends KEY EVENTS to
		 * the first responder, and a window with none has nobody to type at. */
		NSText *field;

		[app finishLaunching];

		/* THE WINDOW AND ITS CONTROLS. The slider sits at the bottom with a readout button beside the checkbox, so a
		 * drag on the knob is visible without any other instrument.
		 *
		 * **AND EVERY PUSH BUTTON BELOW IS THE STANDARD 23 POINTS TALL**, which is what `-sizeToFit` and a degenerate frame
		 * now produce by themselves — the frames are explicit only because a demonstration says where its controls go. The
		 * two INDICATOR rows and the slider keep their own heights, which is the other half of the same rule: 23 is the
		 * BEZEL's metric, so a control with no bezel does not wear it. */
		/* **FOUR BITS, WHICH IS AGORA'S OWN CHROME RATHER THAN APPLE'S.** Agora's title bar is an X, a minus and a
		 * plus in one ink, so the closable, miniaturizable and resizable bits are three SYMBOLS and the window wants all
		 * three of them on screen. The previous revision left the resizable bit off on the ground that a zoom mark this
		 * tier cannot act on is worse than no mark at all; the chrome's redesign settles it the other way — an X, a minus
		 * and a plus are a SET, and a set with a hole in it reads as a window that is missing something. What the plus
		 * will do when this tier grows a resizable window is `NSResizableWindowMask`'s business and not this demo's.
		 *
		 * THE FRAME GROWS BY THE STRIP AND THE CONTENT DOES NOT MOVE, because the frame is bottom-left: the title bar is
		 * added ABOVE the 420x290 the controls are already laid out in. */
		w = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 120, 420, 290)
			styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
			backing:NSBackingStoreBuffered defer:NO];
		content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 290)];
		push = [[NSButton alloc] initWithFrame:NSMakeRect(30, 234, 140, 23)];
		alt = [[NSButton alloc] initWithFrame:NSMakeRect(200, 234, 180, 23)];
		check = [[NSButton alloc] initWithFrame:NSMakeRect(30, 190, 170, 22)];
		readout = [[NSButton alloc] initWithFrame:NSMakeRect(230, 189, 150, 23)];
		radio = [[NSButton alloc] initWithFrame:NSMakeRect(30, 160, 260, 22)];
		off = [[NSButton alloc] initWithFrame:NSMakeRect(30, 129, 260, 23)];
		slider = [[NSSlider alloc] initWithFrame:NSMakeRect(30, 60, 350, 24)];
		/* THE SECOND ONE, WITH NO TICK MARKS AT ALL — which is the whole of what makes its grabber a circle rather
		 * than a teardrop. Same range and same action, so the only difference on screen is the shape. */
		plain = [[NSSlider alloc] initWithFrame:NSMakeRect(30, 25, 350, 24)];
		field = [[NSText alloc] initWithFrame:NSMakeRect(30, 95, 350, 22)];

		[push setTitle:@"Toggle the Checkbox"];
		[push setTarget:controller];
		[push setAction:@selector(toggleCheckbox:)];
		[alt setTitle:@"Longer Title Here"];
		[check setTitle:@"A Checkbox, on"];
		[check setButtonType:NSSwitchButton];
		[check setState:NSOnState];
		[readout setTitle:@"Value: 50"];
		[readout setTarget:controller];
		[readout setAction:@selector(noop:)];
		[radio setTitle:@"A Radio, on"];
		[radio setButtonType:NSRadioButton];
		[radio setState:NSOnState];
		[off setTitle:@"A disabled button"];
		[off setEnabled:NO];
		/* **THE SLIDER'S OWN SETTINGS, ALL FOUR OF THEM A DOOR THIS SLICE ADDED**: a range that is not 0…1, a value
		 * to start at, five ticks to look at, and the controller as the target of a drag that speaks continuously. */
		[slider setMinValue:0.0];
		[slider setMaxValue:100.0];
		[slider setDoubleValue:50.0];
		[slider setNumberOfTickMarks:5];
		[slider setTarget:controller];
		[slider setAction:@selector(sliderMoved:)];
		/* **AND THE SECOND SLIDER, WHICH IS THE SAME CONTROL WITH THE TICKS TAKEN AWAY.** `-setNumberOfTickMarks:`
		 * is left at its default of none, and the grabber's shape follows from that rather than from anything the
		 * demonstration asks for — which is the point of showing them side by side. */
		[plain setMinValue:0.0];
		[plain setMaxValue:100.0];
		[plain setDoubleValue:25.0];
		[plain setTarget:controller];
		[plain setAction:@selector(sliderMoved:)];
		/* THE TEXT VIEW DRAWS ITS OWN BACKGROUND, because the window's surface is white already and a field that did
		 * not would be invisible until the first character arrived. `-setString:` also puts the caret at the END of
		 * what it was given, which is where a person expects to carry on typing. */
		[field setDrawsBackground:YES];
		[field setBackgroundColor:[NSColor whiteColor]];
		[field setString:@"Type here — the caret is already in this field"];
		[content addSubview:push];
		[content addSubview:alt];
		[content addSubview:check];
		[content addSubview:readout];
		[content addSubview:radio];
		[content addSubview:off];
		[content addSubview:slider];
		[content addSubview:plain];
		[content addSubview:field];
		[w setContentView:content];
		[w setTitle:@"Controls"];

		/* **AND THE MENUS, WHICH ARE THE APPLICATION'S AND GO IN THE SERVER'S BAR.** View has the checked item and
		 * Edit the disabled one; both are validated against this controller, and the push button toggles the same
		 * checkbox their state is read from. */
		controller->checkbox = check;
		controller->readout = readout;
		controller->slider = slider;
		/* **AND EVERY ITEM WORTH TYPING CARRIES ITS SHORTCUT**, the Mac's own spellings: Cmd-N/O/W to make, open and
		 * close, Cmd-Z and Shift-Cmd-Z to undo and redo, Cmd-G/R for the two View toggles. HELP HAS NONE — a Help
		 * menu's own shortcut is a search field this tier has not got, and a made-up key would be one nobody typed. */
		add_menu(bar, @"File", [NSArray arrayWithObjects:@"New", @"Open", @"Close", nil],
			 [NSArray arrayWithObjects:@"n", @"o", @"w", nil], controller, @selector(noop:));
		add_menu(bar, @"Edit", [NSArray arrayWithObjects:@"Undo", @"Redo", nil],
			 [NSArray arrayWithObjects:@"z", @"Z", nil], controller, @selector(noop:));
		add_menu(bar, @"View", [NSArray arrayWithObjects:@"Show Grid", @"Show Ruler", nil],
			 [NSArray arrayWithObjects:@"g", @"r", nil], controller, @selector(toggleCheckbox:));
		add_menu(bar, @"Help", [NSArray arrayWithObjects:@"Agora Help", nil],
			 [NSArray arrayWithObjects:@"", nil], controller, @selector(noop:));
		[app setMainMenu:bar];

		/* **AND IT IS MADE KEY, WHICH IS WHAT A FRONTMOST WINDOW IS.** A theme's four states are the point of
		 * looking at it, and `-orderFront:` alone leaves the window inactive — so the ACTIVE art a theme ships for a
		 * focused window would never be on screen, and the thing being iterated on would be the grey half of it. On
		 * a real desktop the compositor's keyboard enter makes the APPLICATION active; the WINDOW is made key here. */
		[w makeKeyAndOrderFront:nil];
		/* **AND THE TEXT VIEW TAKES THE KEYBOARD.** A window sends KEY events to its FIRST RESPONDER and nowhere
		 * else, so a field that is not the first responder is a field nobody can type into — which is what this line
		 * is for, rather than a decoration. */
		[w makeFirstResponder:field];
		/* ONE LINE OF GEOMETRY, so that a screenshot can be READ against the numbers the application believes rather
		 * than against a guess about where a window landed. */
		fprintf(stderr, "controls: window frame = %.0f,%.0f %.0fx%.0f; content = %.0fx%.0f; slider = %.0f,%.0f\n",
			[w frame].origin.x, [w frame].origin.y, [w frame].size.width, [w frame].size.height,
			[content frame].size.width, [content frame].size.height,
			[slider frame].origin.x, [slider frame].origin.y);
		/* AND WHO HAS THE KEYBOARD, which is what decides whether a keystroke reaches the text view at all: a window
		 * sends KEY events to its FIRST RESPONDER, so a field that is not the first responder is one nobody can type
		 * into — and printing this is cheaper than guessing when it is not. */
		fprintf(stderr, "controls: first responder = %s\n",
			([w firstResponder] == field) ? "the text field" : "NOT the text field");
		/* **AND WHICH CHROME THIS WINDOW WILL WEAR**, printed for the same reason the geometry is: iterating on a
		 * theme means knowing whether the one you pointed at is the one that resolved. */
		{
			AGChromeTheme *theme = [AGChromeTheme sharedTheme];

			if (theme != nil) {
				fprintf(stderr, "controls: chrome theme = %s (%g-point strip)\n",
					[[theme directory] UTF8String], (double)[theme titleBarHeight]);
			} else {
				fprintf(stderr, "controls: no chrome theme — drawing Agora's own marks\n");
			}
		}
		if (seconds > 0) {
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds];

			while ([deadline timeIntervalSinceNow] > 0.0) {
				NSEvent *e = [app nextEventMatchingMask:NSAnyEventMask
					untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
					inMode:nil dequeue:YES];

				if (e != nil) {
					[app sendEvent:e];
				}
				[app updateWindows];
			}
		} else {
			[app run];
		}
	}
	return 0;
}
