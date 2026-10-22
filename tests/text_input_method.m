/*
 * text_input_method.m — THE INPUT METHOD: A KEYSTROKE COMPOSED WITH THE ONE AFTER IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A DEAD KEY IS A COMPOSITION THAT SPANS TWO KEYSTROKES, AND THE PROBE DRIVES IT THROUGH THE CONTEXT.** The context
 * is handed a source; the source is handed each key before the standard binding. The accent goes into the store MARKED
 * — the person sees it waiting — and the next letter either REPLACES the mark with one composed character or, when
 * nothing composes, leaves the accent literal and lets the standard binding have the key. So the probe reads the
 * view's string, its marked range, and the source's own idea of whether it is composing.
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

	[pool release];
	printf("text_input_method: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
