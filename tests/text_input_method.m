/*
 * text_input_method.m — THE INPUT METHOD: A KEYSTROKE COMPOSED WITH THE ONE AFTER IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A DEAD KEY IS A COMPOSITION THAT SPANS TWO KEYSTROKES, AND THE PROBE DRIVES IT THROUGH THE CONTEXT.** The context
 * is handed a source; the source is handed each key before the standard binding. The accent goes into the store MARKED
 * — the person sees it waiting — and the next letter either REPLACES the mark with one composed character or, when
 * nothing composes, leaves the accent literal and lets the standard binding have the key. So the probe reads the
 * view's string, its marked range, and the source's own idea of whether it is composing.
 *
 * **AND THE KEY IT COMPOSES WITH IS IDENTIFIED BY ITS KEYSYM, BECAUSE TEXT CANNOT IDENTIFY IT.** A dead key types
 * nothing at all — the keymap has no text for `XKB_KEY_dead_acute` — so the first three cases below feed events that
 * carry a symbol and an empty string, which is exactly what real hardware delivers. The fourth case is the other half
 * of that claim: a US keyboard's `` ` `` is an ORDINARY key (`XKB_KEY_grave`), types a character, and must NOT begin a
 * composition — a rule a characters-only table cannot express, because `` ` `` is also the spacing clone of the dead
 * grave accent. The fifth and sixth cases cover a dead key arriving while one waits, and the composer the context
 * supplies when nobody installed a source.
 *
 * **AND A KEY THE METHOD DOES NOT OWN IS DECLINED.** A plain letter with nothing pending, a Command key, and a
 * movement key all fall through to the context's standard key binding — which is what makes a source safe to install,
 * and is checked here by the caret moving on a left arrow with the method in place.
 */
#import <AppKit/AGInputMethod.h>
#import <AppKit/NSTextInputContext.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSText.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <xkbcommon/xkbcommon-keysyms.h>	/* XKB_KEY_dead_… and XKB_KEY_grave */

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSEvent *key(NSString *characters, NSUInteger flags)
{
	return [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint modifierFlags:flags
			       timestamp:0.0 windowNumber:0 context:nil
			      characters:characters charactersIgnoringModifiers:characters
			       isARepeat:NO keyCode:0];
}

/* **A KEY AS THE SEAM DELIVERS IT: WHAT IT TYPED (OFTEN NOTHING) AND WHAT THE KEYMAP CALLED IT.** A dead key types
 * nothing — xkbcommon writes no bytes for `XKB_KEY_dead_acute` — so this is the only shape in which a real dead key can
 * arrive, and a table that only reads `-characters` cannot see one. */
static NSEvent *keyWithKeysym(NSString *characters, NSUInteger flags, unsigned int keysym)
{
	NSEvent *event = key(characters, flags);

	[event cg_setKeysym:keysym];
	return event;
}

static NSString *one(unichar c)
{
	return [NSString stringWithFormat:@"%C", c];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE SOURCE IS INSTALLED, NAMED, AND TAKEN BACK OFF.** With none the context lists the stock keyboard;
	 * one installed, the method is what it lists and names as selected. */
	{
		NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
		NSTextInputContext *context = (NSTextInputContext *)[text inputContext];
		AGInputMethod *method = [[AGInputMethod alloc] init];

		/* **THE PLACEHOLDER BECAME THE REGISTRY.** This used to assert ONE source — "AgoraKeyboard", the stand-in for
		 * "there is a keyboard" — and the sweep replaced it with the layout registry: with no method installed the
		 * sources are the keyboard layouts this machine can build, and the selected one is among them (see
		 * `tests/text_input_context.m` for the registry's own claims). */
		check([[context textInputSources] count] > 0
		      && [[context textInputSources] containsObject:[context selectedInputSource]],
		      "with nothing installed the sources are the keyboard's layouts");
		check([context inputSource] == nil, "and there is no method behind it");
		[context setInputSource:method];
		check([context inputSource] == method, "`-setInputSource:` installs the method");
		check([[context textInputSources] count] == 1
		      && [[[context textInputSources] objectAtIndex:0] isEqualToString:@"AgoraInputMethod"],
		      "and it is the source a caller now sees listed");
		check([[context selectedInputSource] isEqualToString:@"AgoraInputMethod"], "named as the selected one");
		[context setInputSource:nil];
		check([context inputSource] == nil
		      && [[context textInputSources] containsObject:[context selectedInputSource]],
		      "and uninstalling it restores the keyboard's layouts");
		[method release];
		[text release];
	}

	/* 2. **A DEAD KEY IS MARKED, THE NEXT KEY COMPOSES, AND A KEY THAT DOES NOT IS INSERTED NORMALLY.** */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 60.0)];
		NSTextInputContext *context = (NSTextInputContext *)[view inputContext];
		AGInputMethod *method = [[AGInputMethod alloc] init];
		NSString *acute = one(0x00B4);

		[view setEditable:YES];
		[context setInputSource:method];

		/* THE DEAD KEY BEGINS A COMPOSITION. */
		[view setString:@""];
		[context handleEvent:key(acute, 0)];
		printf("  (note: after the dead key the store is `%s`, marked=%d)\n",
		       [[view string] UTF8String], (int)[view hasMarkedText]);
		check([view hasMarkedText] && [method isComposing], "a dead key begins a composition");
		check([[view string] isEqualToString:acute], "and the accent is in the store, MARKED");
		check([method pendingDeadKey] == 0x00B4, "and the method names which accent is waiting");

		/* THE NEXT LETTER COMPOSES AND REPLACES THE MARK. */
		[context handleEvent:key(@"e", 0)];
		check(![view hasMarkedText] && ![method isComposing], "the next key ENDS the composition");
		check([[view string] isEqualToString:one(0x00E9)],
		      "and `acute + e` is the composed character, over the mark");

		/* UPPERCASE COMPOSES TOO. */
		[view setString:@""];
		[context handleEvent:key(acute, 0)];
		[context handleEvent:key(@"E", 0)];
		check([[view string] isEqualToString:one(0x00C9)], "an uppercase letter composes to the uppercase letter");

		/* A LETTER THAT DOES NOT COMPOSE LEAVES THE ACCENT LITERAL. */
		[view setString:@""];
		[context handleEvent:key(acute, 0)];
		[context handleEvent:key(@"q", 0)];
		printf("  (note: `acute` then `q` gave `%s`)\n", [[view string] UTF8String]);
		check(![view hasMarkedText], "a key that does NOT compose ends the composition too");
		check([[view string] isEqualToString:[acute stringByAppendingString:@"q"]],
		      "the accent stands alone and the key is inserted normally");

		/* ESCAPE TAKES AN UN-COMPOSED DEAD KEY BACK. */
		[view setString:@""];
		[context handleEvent:key(acute, 0)];
		[context handleEvent:key(one(0x1B), 0)];
		check(![view hasMarkedText] && ![method isComposing] && [[view string] isEqualToString:@""],
		      "ESCAPE takes an un-composed dead key back");

		/* AND A KEY WITH NOTHING PENDING IS THE STANDARD BINDING'S. */
		[view setString:@""];
		[context handleEvent:key(@"a", 0)];
		check([[view string] isEqualToString:@"a"],
		      "with nothing pending the source is DECLINED and the key binding inserts the character");

		/* A KEY THE METHOD DOES NOT COMPOSE IS STILL THE CONTEXT'S MAPPING — here, a movement. */
		[view setString:@"ab"];
		[context handleEvent:key(one((unichar)NSLeftArrowFunctionKey), 0)];
		check([view selectedRange].location == 1, "a movement key still reaches the standard binding");

		/* `-discardMarkedText` CLEARS THE SOURCE'S HALF OF THE COMPOSITION. */
		[view setString:@""];
		[context handleEvent:key(acute, 0)];
		[context discardMarkedText];
		check(![method isComposing], "`-discardMarkedText` clears the source's composition state");
		[context handleEvent:key(@"e", 0)];
		check([[view string] isEqualToString:[acute stringByAppendingString:@"e"]],
		      "so the next letter is inserted as itself rather than composed");

		[context setInputSource:nil];
		[method release];
		[view release];
	}

	/* 3. **A DEAD KEY FROM A REAL KEYMAP.** The event types NOTHING and is identified only by its keysym — the shape
	 * every key on a French, German or international layout arrives in, and the shape this probe could not produce
	 * before the keysym reached `NSEvent`. */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 60.0)];
		NSTextInputContext *context = (NSTextInputContext *)[view inputContext];
		AGInputMethod *method = [[AGInputMethod alloc] init];

		[view setEditable:YES];
		[context setInputSource:method];

		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_acute)];
		check([view hasMarkedText] && [method isComposing], "a dead key that TYPES NOTHING still begins a composition");
		check([[view string] isEqualToString:one(0x00B4)], "and the accent it stands for is in the store, MARKED");
		[context handleEvent:key(@"e", 0)];
		check([[view string] isEqualToString:one(0x00E9)], "and the next letter composes with it — `é`");

		/* THE OTHER DIRECTION: GERMAN, WHERE `^` IS A DEAD KEY AND `a` COMPOSES TO `â`. */
		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_circumflex)];
		[context handleEvent:key(@"a", 0)];
		check([[view string] isEqualToString:one(0x00E2)], "`circumflex` then `a` is `â`");

		/* AND THE CEDILLA, WHICH xkbcommon ALSO NAMES AS A DEAD KEY. */
		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_cedilla)];
		[context handleEvent:key(@"c", 0)];
		check([[view string] isEqualToString:one(0x00E7)], "`cedilla` then `c` is `ç`");

		[context setInputSource:nil];
		[method release];
		[view release];
	}

	/* 4. **AND A KEY THAT TYPES ONE OF THOSE CHARACTERS WITHOUT BEING DEAD IS NOT ONE.** This is the half the keysym
	 * buys and a characters-only table cannot: on a US keyboard `` ` `` and `^` are ORDINARY keys whose symbol is
	 * `XKB_KEY_grave`/`XKB_KEY_asciicircum`, and typing "`e" there must produce "`e". Before the keysym existed this
	 * probe would have composed `è` — a character the person did not type, from a keystroke they did. */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 60.0)];
		NSTextInputContext *context = (NSTextInputContext *)[view inputContext];
		AGInputMethod *method = [[AGInputMethod alloc] init];

		[view setEditable:YES];
		[context setInputSource:method];

		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"`", 0, XKB_KEY_grave)];
		check(![method isComposing], "a US `grave` key does NOT begin a composition");
		[context handleEvent:key(@"e", 0)];
		check([[view string] isEqualToString:@"`e"], "so ` then e is `e, not the composed `è`");

		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"^", 0, XKB_KEY_asciicircum)];
		[context handleEvent:key(@"a", 0)];
		check([[view string] isEqualToString:@"^a"], "and the same for `^`, which is `â` only where the map says `dead`");

		[context setInputSource:nil];
		[method release];
		[view release];
	}

	/* 5. **A DEAD KEY WHILE ONE IS WAITING CONFIRMS THE FIRST AND BEGINS THE SECOND.** Two accents have nothing to
	 * compose with each other, so the first stands alone as a literal and the person's second accent is what waits. The
	 * readings this rules out both lose a keystroke: dropping the first loses an accent they typed, and dropping the
	 * second makes their next letter compose with the accent they had already abandoned. */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 60.0)];
		NSTextInputContext *context = (NSTextInputContext *)[view inputContext];
		AGInputMethod *method = [[AGInputMethod alloc] init];

		[view setEditable:YES];
		[context setInputSource:method];

		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_acute)];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_grave)];
		check([method isComposing] && [method pendingDeadKey] == 0x0060,
		      "a second dead key replaces the accent that was waiting");
		[context handleEvent:key(@"e", 0)];
		check([[view string] isEqualToString:[one(0x00B4) stringByAppendingString:one(0x00E8)]],
		      "and the first stands alone: `´è`");

		[context setInputSource:nil];
		[method release];
		[view release];
	}

	/* 6. **AND IT COMPOSES WITH NOTHING INSTALLED.** The seam does not compose dead keys for anybody — `AGKeyboard`
	 * answers what a key types, and a dead key types nothing — so a context that composes only when somebody installed a
	 * source would leave every text view in the system unable to type `é`. The default is a COMPOSER, not a selection:
	 * `-inputSource` still answers nil and the layouts are still what the context lists. */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 60.0)];
		NSTextInputContext *context = (NSTextInputContext *)[view inputContext];

		[view setEditable:YES];
		check([context inputSource] == nil, "nothing is installed, so no method is named");
		check([[context textInputSources] count] > 0, "and the keyboard's layouts are still the sources");
		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_acute)];
		check([view hasMarkedText], "with nothing installed a dead key STILL begins a composition");
		[context handleEvent:key(@"e", 0)];
		check([[view string] isEqualToString:one(0x00E9)], "and it completes with the default composer");

		/* AN INSTALLED SOURCE REPLACES THE DEFAULT RATHER THAN STACKING ON IT: the accent the default was holding is
		 * discarded when the installed one takes over, so the next letter is inserted as itself. */
		AGInputMethod *method = [[AGInputMethod alloc] init];

		[view setString:@""];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_acute)];
		[context setInputSource:method];
		check(![view hasMarkedText], "installing a source takes the default composer's mark down");
		[context handleEvent:key(@"e", 0)];
		/* THE ACCENT STAYS AS A LITERAL, WHICH IS `-discardMarkedText`'s OWN RULE: a discarded composition keeps the
		 * text it had already put in the store and forgets only that it was a composition. What must NOT happen is
		 * composition through a source that never saw the accent. */
		check([[view string] isEqualToString:[one(0x00B4) stringByAppendingString:@"e"]],
		      "an installed source does not compose the default composer's abandoned accent");

		/* **AND THE ACCENT DOES NOT COME BACK WHEN THE SOURCE IS TAKEN OFF AGAIN.** An accent waiting in a source the
		 * person has moved away from is state for a keyboard they are no longer using; left alone it would surface on
		 * the next letter typed, composing `é` out of two keystrokes with a layout change between them. */
		[view setString:@""];
		[context setInputSource:method];
		[context handleEvent:keyWithKeysym(@"", 0, XKB_KEY_dead_acute)];
		[context setInputSource:nil];
		[context handleEvent:key(@"e", 0)];
		check([[view string] isEqualToString:[one(0x00B4) stringByAppendingString:@"e"]],
		      "and un-installing a source does not compose the accent it was holding into the next letter");

		[context setInputSource:nil];
		[method release];
		[view release];
	}

	[pool release];
	printf("text_input_method: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
