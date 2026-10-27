/*
 * appkit_events — an event's journey: the seam's `AGEvent`, through `NSWindow`, to the view that should get it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHY THIS EXISTS. `tests/appkit_window.m` proves a window appears and paints. It does NOT prove anything
 * arrives at it: the headless compositor has no seat, so a run of that test sees zero events and says so. The
 * input path is the half of the port that was REWRITTEN — the key translation moved out of `XLookupString`
 * into xkbcommon, the event pump out of `XNextEvent` into the seam's callback, and the dispatch out of X's
 * window ids — and it had never been asked a single question.
 *
 * HOW IT ASKS THEM WITHOUT A SEAT. `AGEvent` is the seam's own public struct, so this test builds the events a
 * compositor would have sent and hands them to the window through the seam's private door, then pumps them
 * with the APPLICATION's own pump and dispatches them with `-sendEvent:`. The one link that is not exercised
 * is the compositor calling that door — and that link IS exercised elsewhere, because a headless run reaches
 * `640x422` only by way of a configure event arriving through it.
 *
 * WHAT IS ASSERTED, and each one was a bug or a dead branch before it passed:
 *
 *   1. A key goes to the FIRST RESPONDER and carries its characters — and, for every key and not only the ones
 *      that type nothing, THE KEYMAP'S NAME FOR THE KEY, which is the only thing that identifies a dead key.
 *   2. A MODIFIER arrives as `-flagsChanged:` rather than as a key down.
 *   3. A click goes to THE VIEW UNDER THE POINTER, not to the first responder.
 *   4. A view that does not implement the event method BUBBLES it up the responder chain, which is what
 *      `NSResponder`'s forwarding methods are for and what an unwired chain silently swallowed.
 *   5. A move is DELIVERED ONLY TO A WINDOW THAT ASKED FOR IT — the default drops it, and a window that says
 *      `-setAcceptsMouseMovedEvents:YES` (the menu bar and every menu window now do) receives it. Without the
 *      request every move over a menu was thrown away, so a row never highlighted under the pointer.
 *   6. The compositor's close request closes the window.
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>

#include "AGWindowServer.h"
#include "AGKeyboard.h"	/* the same door the seam's backend asks, so the two halves are joined by the test */

#include <xkbcommon/xkbcommon-keysyms.h>	/* keysym names on both sides of an assertion */

#include <stdio.h>
#include <string.h>

/* THE PRIVATE DOOR THE SEAM CALLS, redeclared here. That is this tree's own pattern for a private contract a
 * second file has to reach — NSWindow.m does it for NSView's cursor doors, for the same reason. */
@interface NSWindow (AGEventTestDoor)
- (void)cg_handleSeamEvent:(const AGEvent *)event;
@end

static int g_checks;
static int g_failed;

/* A FUNCTION KEY'S CHARACTER IS ITS NAME, so the check is that the string is exactly that one unit — not that it
 * merely contains it. */
static BOOL is_function_key(NSString *characters, unichar wanted)
{
	return characters != nil && [characters length] == 1 && [characters characterAtIndex:0] == wanted;
}

static void check(int ok, const char *what)
{
	g_checks++;
	if (!ok) {
		g_failed++;
		printf("  [FAIL] %s\n", what);
	} else {
		printf("  [ok]   %s\n", what);
	}
}

/* A VIEW THAT RECORDS WHAT IT IS SENT. Nothing here is a mock: these are the real callbacks AppKit delivers,
 * and the counters are how the test sees them. */
@interface AGRecordingView : NSView
{
@public
	int keyDowns;
	int keyUps;
	int flagsChangeds;
	int mouseDowns;
	int mouseUps;
	int mouseMoveds;
	NSString *lastCharacters;
	NSUInteger lastModifiers;
	BOOL lastWasRepeat;
	BOOL lastHadSourceTime;
	unsigned int lastSourceTime;
	unsigned int lastFocusSerial;
	unsigned int lastKeysym;	/* `-cg_keysym`, which the seam has always carried and AppKit used to drop */
	NSString *lastIgnoringModifiers;	/* and `-charactersIgnoringModifiers`, the key with the modifiers taken off */
	NSPoint lastPoint;
}
@end

@implementation AGRecordingView

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)keyDown:(NSEvent *)event
{
	keyDowns++;
	[lastCharacters release];
	lastCharacters = [[event characters] copy];
	lastModifiers = [event modifierFlags];
	lastWasRepeat = [event isARepeat];
	lastHadSourceTime = [event cg_hasSourceTimestamp];
	lastSourceTime = [event cg_sourceTimestamp];
	lastFocusSerial = [event cg_focusSerial];
	lastKeysym = [event cg_keysym];
	[lastIgnoringModifiers release];
	lastIgnoringModifiers = [[event charactersIgnoringModifiers] copy];
}

- (void)keyUp:(NSEvent *)event
{
	(void)event;
	keyUps++;
}

- (void)flagsChanged:(NSEvent *)event
{
	flagsChangeds++;
	lastModifiers = [event modifierFlags];
}

- (void)mouseDown:(NSEvent *)event
{
	mouseDowns++;
	lastPoint = [event locationInWindow];
}

- (void)mouseUp:(NSEvent *)event
{
	(void)event;
	mouseUps++;
}

- (void)mouseMoved:(NSEvent *)event
{
	(void)event;
	mouseMoveds++;
}

- (void)dealloc
{
	[lastCharacters release];
	[super dealloc];
}

@end

/* A VIEW THAT IMPLEMENTS NOTHING, so the event has to BUBBLE: NSResponder's own `-mouseDown:` forwards to
 * `-nextResponder`, and this class is what makes that path the one under test. */
@interface AGPassiveView : NSView
@end

@implementation AGPassiveView
@end

/* ---------------------------------------------------------------------------------------------------
 * the seam's own events, built here and delivered through the private door
 * --------------------------------------------------------------------------------------------------- */

static AGEvent evdev_key(uint32_t code, const char *text, int pressed, int modifier, uint32_t modifiers)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventKey;
	event.keycode = code;
	event.pressed = pressed;
	event.modifier = modifier;
	event.modifiers = modifiers;
	snprintf(event.text, sizeof event.text, "%s", text != NULL ? text : "");
	return event;
}

/* **AND THE SAME KEY WITH THE MODIFIERS OFF, WHICH IS A SECOND FIELD AND NOT A SECOND OPINION.** `AGKeyboard`
 * produces both — `-Translate` for what the person will see, `-TranslateIgnoringModifiers` for which key it was — so a
 * test that filled only one would be testing half the seam. */
static AGEvent evdev_key_plain(uint32_t code, const char *text, const char *plain, int pressed, uint32_t modifiers)
{
	AGEvent event = evdev_key(code, text, pressed, 0, modifiers);

	snprintf(event.text_plain, sizeof event.text_plain, "%s", plain != NULL ? plain : "");
	return event;
}

static AGEvent pointer_button(uint32_t button, int pressed, int x, int y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerButton;
	event.button = button;			/* BTN_LEFT */
	event.pressed = pressed;
	event.x = x;
	event.y = y;
	return event;
}

/* DELIVER ONE EVENT: hand it to the window the way the seam does, then run the APPLICATION's own pump and
 * dispatch, so what is being tested is the path a real event takes and not a shortcut into the view. */
static void deliver(NSApplication *application, NSWindow *window, const AGEvent *event)
{
	NSEvent *built;
	NSDate *deadline;

	[window cg_handleSeamEvent:event];
	deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
	while ((built = [application nextEventMatchingMask:NSAnyEventMask
						 untilDate:deadline
						    inMode:nil
						   dequeue:YES]) != nil) {
		[application sendEvent:built];
		/* ONE EVENT PER CALL: the loop is here to drain a configure if one is waiting, not to batch. */
		if ([built type] != NSFlagsChanged && [built windowNumber] != 0) {
			break;
		}
	}
}

/* THE SEAM'S `y` IS MEASURED DOWN FROM THE TOP OF THE WHOLE FRAME, and Cocoa's content view starts at the
 * BOTTOM — so a content point becomes a seam point through the frame's height. Written once, here, for the
 * same reason NSWindow writes it once. */
static AGEvent click_at_content_point(NSWindow *window, CGFloat x, CGFloat y)
{
	return pointer_button(0x110, 1, (int)x, (int)([window frame].size.height - y));
}

/* A MOVE, in the same space the click is built in. There is no button, so the seam sees a plain motion and not
 * a drag. */
static AGEvent motion_at_content_point(NSWindow *window, CGFloat x, CGFloat y)
{
	AGEvent event;

	memset(&event, 0, sizeof event);
	event.type = AGEventPointerMotion;
	event.x = (int)x;
	event.y = (int)([window frame].size.height - y);
	return event;
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		AGRecordingView *content;
		AGRecordingView *inner;
		AGPassiveView *passive;
		AGEvent event;
		int before;

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 640.0, 400.0)
						     styleMask:(NSTitledWindowMask | NSClosableWindowMask)
						       backing:NSBackingStoreBuffered
							 defer:NO];
		if (window == nil) {
			fprintf(stderr, "appkit_events: NO WINDOW WAS MADE\n");
			return 1;
		}
		content = [[AGRecordingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 400.0)];
		[window setContentView:content];
		/* ONE SUBVIEW THAT HANDLES THE EVENT, and one that does not, so bubbling is measurable and not assumed. */
		inner = [[AGRecordingView alloc] initWithFrame:NSMakeRect(10.0, 10.0, 100.0, 50.0)];
		passive = [[AGPassiveView alloc] initWithFrame:NSMakeRect(150.0, 10.0, 100.0, 50.0)];
		[content addSubview:inner];
		[content addSubview:passive];
		[window orderFront:nil];

		/* LET THE COMPOSITOR CONFIGURE IT, because the seam's coordinates are the frame's and the frame is not
		 * its requested size until it has been configured. */
		{
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];

			while ([deadline timeIntervalSinceNow] > 0.0) {
				NSEvent *e = [application nextEventMatchingMask:NSAnyEventMask
								      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
									 inMode:nil
									dequeue:YES];

				if (e != nil) {
					[application sendEvent:e];
				}
			}
		}
		printf("appkit_events: window %ld, frame %gx%g, content %gx%g\n", (long)[window windowNumber],
		       (double)[window frame].size.width, (double)[window frame].size.height,
		       (double)[content frame].size.width, (double)[content frame].size.height);

		/* **THE FIRST RESPONDER IS THE CONTENT VIEW AND NOT THE SUBVIEW THAT WILL BE CLICKED**, which is the
		 * whole point of separating these checks: with the subview as the first responder, a click would reach
		 * it whether or not the window hit-tests, and the check could not tell the two apart. MEASURED — the
		 * first version of this test made that mistake and the hit-test check passed with the hit test REMOVED. */
		[window makeFirstResponder:content];

		/* 1. A KEY GOES TO THE FIRST RESPONDER, with its characters. */
		event = evdev_key(30 /* KEY_A */, "a", 1, 0, 0);
		deliver(application, window, &event);
		check(content->keyDowns == 1, "a key reaches the FIRST RESPONDER");
		check(content->lastCharacters != nil && [content->lastCharacters isEqual:@"a"],
		      "and it carries the character xkbcommon produced");
		event = evdev_key(30, "a", 0, 0, 0);
		deliver(application, window, &event);
		check(content->keyUps == 1, "a key release reaches it too");

		/* **1b. A KEY THAT TYPES NOTHING ARRIVES AS ITS FUNCTION-KEY CHARACTER.** AppKit's whole vocabulary for a
		 * commanding key is the 0xF700 block in `-characters`, and this tier used to build `-characters` from the
		 * seam's UTF-8 alone — so an arrow arrived as an EMPTY string, an F key was indistinguishable from it, and
		 * every control whose arrow handling lives behind `NSUpArrowFunctionKey` was dead under a real keyboard. The
		 * seam now carries the keymap's keysym; this is the chain end to end inside the library: this test asks the
		 * SAME `AGKeyboard` the backend asks for the SAME evdev code, puts the answer in the seam's own field, and
		 * reads back what the view was sent. The one link still not exercised is the compositor calling the door,
		 * which is the same link every other check here leaves out.
		 *
		 * THE CODES ARE THE PHYSICAL KEYS and the keysyms come from the layout, so a failure names which half broke:
		 * "the code is not that key" would fail in `keyboard`, and what fails here is the Cocoa mapping. */
		{
			AGKeyboard *keyboard = AGKeyboardCreate();
			int beforeFunction = content->keyDowns;

			if (keyboard == NULL || AGKeyboardUseDefaultKeymap(keyboard) != 0) {
				fprintf(stderr, "appkit_events: NO KEYMAP — the function-key checks cannot run\n");
				return 1;
			}

			/* THE ARROWS, in the order Cocoa's own constants are defined, so a transposed table shows up. */
			event = evdev_key(103 /* KEY_UP */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 103);
			deliver(application, window, &event);
			check(content->keyDowns == beforeFunction + 1, "an arrow key reaches the first responder at all");
			check(is_function_key(content->lastCharacters, NSUpArrowFunctionKey),
			      "and its -characters is NSUpArrowFunctionKey, not an empty string");

			event = evdev_key(108 /* KEY_DOWN */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 108);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSDownArrowFunctionKey),
			      "evdev 108 is NSDownArrowFunctionKey");

			event = evdev_key(105 /* KEY_LEFT */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 105);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSLeftArrowFunctionKey),
			      "evdev 105 is NSLeftArrowFunctionKey");

			event = evdev_key(106 /* KEY_RIGHT */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 106);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSRightArrowFunctionKey),
			      "evdev 106 is NSRightArrowFunctionKey");

			/* **AND THE MODIFIER IS STILL A MODIFIER.** Shift-Up moves the selection rather than the caret, and the
			 * way a view knows is `-modifierFlags` — the character is the same one either way. */
			event = evdev_key(103 /* KEY_UP */, "", 1, 0, AGModifierShift);
			event.keysym = AGKeyboardKeysym(keyboard, 103);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSUpArrowFunctionKey) &&
			      (content->lastModifiers & NSShiftKeyMask) != 0,
			      "shift-up is the SAME character with the shift flag set");

			/* THE EDIT BLOCK: Home, End, and the two page keys. */
			event = evdev_key(102 /* KEY_HOME */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 102);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSHomeFunctionKey),
			      "evdev 102 is NSHomeFunctionKey");

			event = evdev_key(107 /* KEY_END */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 107);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSEndFunctionKey),
			      "evdev 107 is NSEndFunctionKey");

			event = evdev_key(104 /* KEY_PAGEUP */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 104);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSPageUpFunctionKey),
			      "evdev 104 is NSPageUpFunctionKey");

			event = evdev_key(109 /* KEY_PAGEDOWN */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 109);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSPageDownFunctionKey),
			      "evdev 109 is NSPageDownFunctionKey");

			/* **THE TWO DELETES ARE DIFFERENT KEYS AND THIS IS THE ONE THAT IS A FUNCTION KEY.** Backspace types
			 * 0x08 (a character, so it is untouched by this table); the FORWARD delete is `NSDeleteFunctionKey`, and a
			 * tier that mapped neither would give a view no way to tell them apart. */
			event = evdev_key(14 /* KEY_BACKSPACE */, "\b", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 14);
			deliver(application, window, &event);
			check(content->lastCharacters != nil && [content->lastCharacters isEqual:@"\b"],
			      "Backspace still arrives as the character it types");

			event = evdev_key(111 /* KEY_DELETE */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 111);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSDeleteFunctionKey),
			      "while forward delete (evdev 111) is NSDeleteFunctionKey");

			event = evdev_key(110 /* KEY_INSERT */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 110);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSInsertFunctionKey),
			      "evdev 110 is NSInsertFunctionKey");

			/* **THE F KEYS ARE ONE RUN ON BOTH SIDES, WHICH IS WHY THE TABLE IS ARITHMETIC.** The first and last of
			 * the 35 are checked: an off-by-one in the base shows at F1, and one in the count at F12 — which is also
			 * the last F key most keyboards have. */
			event = evdev_key(59 /* KEY_F1 */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 59);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSF1FunctionKey),
			      "evdev 59 is NSF1FunctionKey");

			event = evdev_key(88 /* KEY_F12 */, "", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 88);
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSF12FunctionKey),
			      "and evdev 88 is NSF12FunctionKey, eleven keys along the same run");

			/* **AND THE KEY'S NAME REACHES THE VIEW FOR A KEY THAT TYPES, WHICH IT DID NOT BEFORE.** The mapping
			 * above turns a keysym into a `0xF700` character and the translation path used to stop there: the symbol
			 * survived only for keys that typed nothing, so a dead key — which types nothing AND has no `0xF700`
			 * character — arrived as an empty string with no name at all. A typing key and a dead one are checked
			 * here, which is the whole of what `NSWindow` owes: identifying them is the input method's job. */
			event = evdev_key(30 /* KEY_A */, "a", 1, 0, 0);
			event.keysym = AGKeyboardKeysym(keyboard, 30);
			deliver(application, window, &event);
			check(content->lastKeysym == XKB_KEY_a,
			      "a key that types carries its keysym too — `XKB_KEY_a` for evdev 30");

			event = evdev_key(13 /* KEY_EQUAL, the `de` dead-accent key */, "", 1, 0, 0);
			event.keysym = XKB_KEY_dead_acute;
			deliver(application, window, &event);
			check(content->lastKeysym == XKB_KEY_dead_acute,
			      "and a DEAD KEY arrives named, which is the only way it can be identified at all");
			check(content->lastCharacters != nil && [content->lastCharacters length] == 0,
			      "typing nothing, as a dead key does: the name is the whole of what it says");

			/* **1c. AND THE KEY WITH ITS MODIFIERS OFF, WHICH IS THE ONLY THING THAT NAMES A CONTROL COMBINATION.**
			 * `Ctrl+Shift+C` and `Ctrl+C` both type `0x03`, so `-characters` cannot tell the copy shortcut from an
			 * interrupt — the menu's key equivalent and a terminal's modifier parameter both need the symbol the
			 * key carries, and `NSMenu -performKeyEquivalent:` has always matched on
			 * `-charactersIgnoringModifiers`. This is the chain: `AGKeyboard`'s unmasked answer into the seam's field,
			 * through `NSWindow`, out of the event the view is sent. */
			event = evdev_key_plain(30 /* KEY_A */, "\x01", "a", 1, AGModifierControl);
			deliver(application, window, &event);
			check(content->lastCharacters != nil && [content->lastCharacters length] == 1 &&
			      [content->lastCharacters characterAtIndex:0] == 0x01,
			      "Control makes the key type the control character");
			check(content->lastIgnoringModifiers != nil &&
			      [content->lastIgnoringModifiers isEqual:@"a"],
			      "and the very same event still says the key was `a`");

			event = evdev_key_plain(30, "\x01", "A", 1, AGModifierControl | AGModifierShift);
			deliver(application, window, &event);
			check([content->lastCharacters isEqual:content->lastIgnoringModifiers] == NO &&
			      [content->lastIgnoringModifiers isEqual:@"A"],
			      "Ctrl+Shift types the same byte as Ctrl and answers `A` when the modifiers are ignored");

			/* **AND A KEY THAT TYPES NOTHING ANSWERS THE SAME CHARACTER BOTH WAYS**, which is what AppKit does
			 * for the `0xF700` block: the name IS the character, so `-charactersIgnoringModifiers` has nothing
			 * better to say and must not fall back to the empty string. */
			event = evdev_key(103 /* KEY_UP */, "", 1, 0, 0);
			event.keysym = XKB_KEY_Up;
			deliver(application, window, &event);
			check(is_function_key(content->lastIgnoringModifiers, NSUpArrowFunctionKey),
			      "an arrow answers NSUpArrowFunctionKey with the modifiers ignored too");

			/* **AND SHIFT-TAB IS `NSBackTabCharacter`, NOT THE EMPTY STRING.** A shifted Tab is
			 * `XKB_KEY_ISO_Left_Tab`, it types nothing, and it is not in the `0xF700` block — so before the mapping
			 * had this case it was indistinguishable from a key the layout does not define, and a terminal had
			 * nothing to key `CSI Z` off. Apple's answer is the control character `0x19`. */
			event = evdev_key(15 /* KEY_TAB */, "", 1, 0, AGModifierShift);
			event.keysym = XKB_KEY_ISO_Left_Tab;
			deliver(application, window, &event);
			check(is_function_key(content->lastCharacters, NSBackTabCharacter),
			      "Shift-Tab is NSBackTabCharacter, not an empty string");

			/* AND AN EVENT WITH NO UNMASKED TEXT — one this tier fabricated, or a seam that did not fill it —
			 * falls back to `-characters` rather than to an empty string, so nothing that read that door before
			 * this field existed changes its answer. */
			event = evdev_key(30, "a", 1, 0, 0);
			deliver(application, window, &event);
			check([content->lastIgnoringModifiers isEqual:@"a"],
			      "with no unmasked text the door answers what the key typed");

			/* **A KEY WITH NO COCOA NAME IS STILL DELIVERED, WITH NO CHARACTER.** A layout can bind a key this
			 * tier does not map, and the alternative to an empty string is a refusal or a wrong guess; the empty
			 * string with its modifier flags is what the seam can honestly say. */
			event = evdev_key(0 /* no code in particular */, "", 1, 0, 0);
			event.keysym = XKB_KEY_Multi_key;
			deliver(application, window, &event);
			check(content->lastCharacters != nil && [content->lastCharacters length] == 0,
			      "a keysym with no Cocoa equivalent arrives with EMPTY characters, not a refused event");

			/* **AND TEXT WINS WHEN THERE IS ANY**, which is the branch the table is behind: a key that types keeps
			 * what it typed even if its keysym would map. Contrived here on purpose — no real key does both — so the
			 * precedence is asserted rather than left as an effect of the order the two fields are filled in. */
			event = evdev_key(30 /* KEY_A */, "a", 1, 0, 0);
			event.keysym = XKB_KEY_Up;
			deliver(application, window, &event);
			check(content->lastCharacters != nil && [content->lastCharacters isEqual:@"a"],
			      "a key that TYPES keeps its text even when its keysym would map");

			AGKeyboardDestroy(keyboard);
		}

		/* 2. A MODIFIER IS `-flagsChanged:`, NOT A KEYSTROKE. */
		before = content->keyDowns;
		event = evdev_key(42 /* KEY_LEFTSHIFT */, "", 1, 1, AGModifierShift);
		deliver(application, window, &event);
		check(content->flagsChangeds == 1, "a MODIFIER arrives as -flagsChanged:");
		check(content->keyDowns == before, "and NOT as a key down");
		check((content->lastModifiers & NSShiftKeyMask) != 0, "and the flag it carries is the shift bit");

		/* **2b. AND A REPEAT IS MARKED AS ONE.** A held key produces presses the hardware did not send: the seam's
		 * platform generates them, at the compositor's `repeat_info` rate, and marks them. The AppKit's whole
		 * vocabulary for that is `-isARepeat`, which this conversion used to hard-code to NO — so a held arrow key
		 * was indistinguishable from someone pressing it again, and a control that nudges with arrows would nudge
		 * twice per repeat. `event.repeat` is the seam's answer and it is carried straight through. */
		before = content->keyDowns;
		event = evdev_key(30 /* KEY_A */, "a", 1, 0, 0);
		event.repeat = 1;
		deliver(application, window, &event);
		check(content->keyDowns == before + 1, "a generated repeat is delivered as a key down");
		check(content->lastWasRepeat, "and says so: -isARepeat is YES");
		event = evdev_key(30, "a", 1, 0, 0);
		deliver(application, window, &event);
		check(!content->lastWasRepeat, "while an ordinary press still answers NO");

		/* **2c. THE SOURCE'S OWN CHRONOLOGY, AND WHOSE FOCUS IT ARRIVED UNDER.** `-timestamp` is a TRANSLATION time —
		 * when this process made the object — and a confirmation that has to say "this keystroke was queued before
		 * my dialog appeared" cannot use it. The compositor's millisecond and the keyboard tenure travel separately,
		 * and an event with no source time says so instead of quietly carrying the translation time. */
		event = evdev_key(30 /* KEY_A */, "a", 1, 0, 0);
		event.source_time_ms = 4242;
		event.has_source_time = 1;
		event.focus_serial = 7;
		deliver(application, window, &event);
		check(content->lastHadSourceTime, "a key event says whether it HAS a source timestamp");
		check(content->lastSourceTime == 4242, "and carries the compositor's millisecond, not this process's");
		check(content->lastFocusSerial == 7, "and the keyboard tenure it arrived under");

		/* A PRESS WITH NO SOURCE TIME — the shape a compositor that sends zero produces. (A RELEASE would record
		 * nothing here: the probe counts `-keyDown:`, which is exactly why the check above used a press.) */
		event = evdev_key(30, "a", 1, 0, 0);
		event.source_time_ms = 0;
		event.has_source_time = 0;
		event.focus_serial = 7;
		deliver(application, window, &event);
		check(!content->lastHadSourceTime,
		      "an event a compositor sent no time for says it has NONE, rather than passing a translation time "
		      "off as one");
		check(content->lastFocusSerial == 7, "and it still says which keyboard tenure it belongs to");

		event = evdev_key(30, "a", 1, 0, 0);
		event.focus_serial = 8;			/* the keyboard left and came back */
		deliver(application, window, &event);
		check(content->lastFocusSerial == 8,
		      "and a press after a focus return carries a HIGHER tenure, which is how a pair is known to be "
		      "uninterrupted");

		/* **3. A CLICK IS ALSO WINDOW MANAGEMENT: it activates the application, makes the clicked window key and
		 * main, and asks for it to be frontmost.** Deactivating first makes the activation half observable even in
		 * a headless run where the seat has already delivered a keyboard-enter. Before this door was fixed, the
		 * click wrote the application's two ivars and left `-isKeyWindow`/`-isMainWindow` NO. */
		[application deactivate];
		[window resignKeyWindow];
		[window resignMainWindow];
		check(![application isActive], "the application is INACTIVE before the click");
		check(![window isKeyWindow] && ![window isMainWindow], "and the window is neither key nor main");
		event = click_at_content_point(window, 60.0, 30.0);	/* inside `inner` */
		deliver(application, window, &event);
		check(inner->mouseDowns == 1, "a click lands on the SUBVIEW it is over");
		check(content->mouseDowns == 0, "and not on the content view behind it");
		check([application isActive], "and the click ACTIVATES the application");
		check([application keyWindow] == window && [window isKeyWindow],
		      "the clicked window becomes KEY, and the application agrees");
		check([application mainWindow] == window && [window isMainWindow],
		      "and MAIN, through the doors that announce it");

		/* 4. AND A VIEW THAT DOES NOT HANDLE IT BUBBLES UP THE CHAIN. */
		before = content->mouseDowns;
		event = click_at_content_point(window, 200.0, 30.0);	/* inside `passive` */
		deliver(application, window, &event);
		check(content->mouseDowns == before + 1,
		      "a click on a view that does not handle it BUBBLES to its superview");

		/* Release the button the check above left down, so the move below is a MOVE and not a drag. */
		event = pointer_button(0x110, 0, 200, 30);
		deliver(application, window, &event);

		/* 5. A PLAIN MOVE IS DROPPED UNLESS THE WINDOW ASKED FOR IT, and that request is what lets a menu row
		 * light up under the pointer: a window's default is NO, the menu bar and every menu window now say YES,
		 * and before they did, EVERY move over a menu was thrown away — the row never highlighted and a submenu
		 * never opened by hovering. Both halves are asserted, because only the pair catches a tier that dropped
		 * the event for a window that asked, or delivered it for one that did not. */
		before = inner->mouseMoveds;
		event = motion_at_content_point(window, 60.0, 30.0);	/* over `inner` */
		deliver(application, window, &event);
		check(inner->mouseMoveds == before, "a move the window did NOT ask for is dropped");
		[window setAcceptsMouseMovedEvents:YES];
		event = motion_at_content_point(window, 60.0, 30.0);
		deliver(application, window, &event);
		check(inner->mouseMoveds == before + 1, "and a move it DID ask for reaches the view under the pointer");

		/* 6. THE COMPOSITOR'S CLOSE REQUEST CLOSES THE WINDOW. The close is deferred by design — it is acted
		 * on by the pump, not inside the seam's dispatch — so it takes one more pass to be seen. */
		memset(&event, 0, sizeof event);
		event.type = AGEventClose;
		[window cg_handleSeamEvent:&event];
		{
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];

			while ([deadline timeIntervalSinceNow] > 0.0 && [window windowNumber] != -1) {
				NSEvent *e = [application nextEventMatchingMask:NSAnyEventMask
								      untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
									 inMode:nil
									dequeue:YES];

				if (e != nil) {
					[application sendEvent:e];
				}
			}
		}
		check([window windowNumber] == -1, "the compositor's close request closes the window");

		printf("appkit_events: %d checks, %d failed%s\n", g_checks, g_failed,
	       g_failed == 0 ? " -- all checks passed" : "");
		[inner release];
		[passive release];
		[content release];
		[window release];
	}
	return g_failed == 0 ? 0 : 1;
}
