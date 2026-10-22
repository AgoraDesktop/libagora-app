/*
 * text_input_context.m — THE INPUT CONTEXT: WHERE A KEY GOES BEFORE THE TEXT VIEW, AND WHERE A COMPOSITION LIVES.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE MAPPING MOVED OUT OF THE RESPONDER, AND THE PROBE PROVES IT BY DRIVING THE CONTEXT DIRECTLY.** A text view's
 * `-inputContext` answers a context whose client is the view; `-handleEvent:` is the door a key comes in through, and
 * what comes out is the SAME standard key binding the responder used to do — a left arrow moves the caret, a printable
 * character is inserted — only now with an input method's place in front of it. A view that is not a text input client
 * has NO context, which is the truth for every view that is not a text surface.
 *
 * **AND THE COMPOSITION'S OWNER IS CHECKED.** `-discardMarkedText` takes a marked composition back through its client,
 * and `+currentInputContext` is the one `-activate`/`-deactivate` set and clear. The two input-source doors answer the
 * one stock keyboard this tier has rather than an empty array pretending there is none.
 */
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

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **A TEXT VIEW HAS A CONTEXT AND ITS CLIENT IS THE VIEW; A PLAIN VIEW HAS NONE.** */
	{
		NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
		NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];
		NSTextInputContext *context = (NSTextInputContext *)[text inputContext];

		check(context != nil, "a text input client answers an input context");
		check([context client] == text, "and the context's client IS the view it was made for");
		check([plain inputContext] == nil, "a view that is not a text input client answers NO context");
		[plain release];
		[text release];
	}

	/* 2. **AND THE KEY BINDING IS THE CONTEXT'S NOW.** Driving `-handleEvent:` directly — not through the responder —
	 * moves the caret and inserts text, which is the mapping that used to live in `NSResponder`. */
	{
		NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
		NSTextInputContext *context = (NSTextInputContext *)[text inputContext];
		NSString *leftArrow = [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey];

		[text setString:@"abc"];
		[context handleEvent:key(leftArrow, 0)];
		check([text selectedRange].location == 2, "`-handleEvent:` maps a LEFT ARROW to a movement command");
		[context handleEvent:key(@"x", 0)];
		check([[text string] isEqualToString:@"abxc"], "and a printable character to an insertion");
		[context handleEvent:key(@"c", NSCommandKeyMask)];
		check([[text string] isEqualToString:@"abxc"], "while a COMMAND-modified key is left to the menu bar");
		[text release];
	}

	/* 3. **AND THE ACTIVE CONTEXT IS THE ONE `-activate` SET.** */
	{
		NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
		NSTextInputContext *context = (NSTextInputContext *)[text inputContext];

		check([NSTextInputContext currentInputContext] == nil, "a fresh process has no active input context");
		[context activate];
		check([NSTextInputContext currentInputContext] == context, "`-activate` makes it the current one");
		[context deactivate];
		check([NSTextInputContext currentInputContext] == nil, "and `-deactivate` clears it");
		check([context isActive] == NO, "with `-isActive` answering the same fact");
		[text release];
	}

	/* 4. **AND THE SOURCE DOORS NAME THE KEYBOARD'S LAYOUTS, WHICH ARE THIS TIER'S INPUT SOURCES.** This used to assert
	 * ONE source — a placeholder string for "there is a keyboard" — and the sweep replaced it with the registry: the
	 * layouts the machine can build, with the SELECTED one first. See section 6 for the registry's own claims. */
	{
		NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
		NSTextInputContext *context = (NSTextInputContext *)[text inputContext];
		NSArray *listed = [context textInputSources];

		check([listed count] > 0, "the input sources are the keyboard layouts the machine can build");
		check([[context selectedInputSource] isKindOfClass:[NSString class]] &&
		      [listed containsObject:[context selectedInputSource]],
		      "and the selected source is one of them");
		[text release];
	}

	/* 5. **AND THE CONTEXT OWNS THE COMPOSITION: `-discardMarkedText` TAKES IT BACK THROUGH THE CLIENT.** */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)];
		NSTextInputContext *context = (NSTextInputContext *)[view inputContext];

		[view setString:@""];
		[view setMarkedText:@"ab" selectedRange:NSMakeRange(0, 2)];
		check([view hasMarkedText], "the view is composing");
		[context discardMarkedText];
		check(![view hasMarkedText], "and `-discardMarkedText` ends the composition through its client");
		check([[view string] isEqualToString:@"ab"], "leaving the characters that were composed");
		[view release];
	}

	/* ============================================================================================
	 * 6. AND THE EIGHT THE SWEEP ADDS: THE LAYOUTS THIS MACHINE CAN BUILD, AND THE CONTEXT'S LIMITS.
	 * ============================================================================================ */
	{
		NSArray *sources = [NSTextInputContext keyboardInputSources];
		NSString *selected;
		NSTextInputContext *context;
		NSTextView *view;

		printf("        (layouts this machine can build: %lu)\n", (unsigned long)[sources count]);
		check(sources != nil && [sources count] > 0,
		      "`+keyboardInputSources` answers the layouts this machine can build, not an empty list");
		check([sources containsObject:@"us"],
		      "which includes the U.S. layout, because a machine with no US keymap could not be a desktop");
		{
			NSUInteger i;
			BOOL allStrings = YES;

			for (i = 0; i < [sources count]; i++) {
				if (![[sources objectAtIndex:i] isKindOfClass:[NSString class]]) {
					allStrings = NO;
				}
			}
			check(allStrings, "each source is an identifier string");
		}

		/* THE SELECTION IS VALIDATED AND ITS READER IS THE ORDER: the chosen layout comes FIRST. */
		selected = [NSTextInputContext selectedKeyboardInputSource];
		check(selected != nil, "`+selectedKeyboardInputSource` answers an identifier");
		check([[sources objectAtIndex:0] isEqualToString:selected],
		      "and the selected layout is FIRST in the list, which is what makes the selection visible");
		if ([sources containsObject:@"de"]) {
			[NSTextInputContext setSelectedKeyboardInputSource:@"de"];
			check([[NSTextInputContext selectedKeyboardInputSource] isEqualToString:@"de"],
			      "selecting the German layout takes");
			check([[[NSTextInputContext keyboardInputSources] objectAtIndex:0] isEqualToString:@"de"],
			      "and moves it to the front of the list");
		}
		[NSTextInputContext setSelectedKeyboardInputSource:@"zz-nonsense"];
		check(![[NSTextInputContext selectedKeyboardInputSource] isEqualToString:@"zz-nonsense"],
		      "a layout this machine cannot build is REFUSED rather than selected");
		[NSTextInputContext setSelectedKeyboardInputSource:@"us"];

		/* AND THE NAME A MENU SHOWS: a known layout's name, and an unknown identifier back rather than a guess. */
		check([[NSTextInputContext localizedNameForInputSource:@"us"] isEqualToString:@"U.S."],
		      "`+localizedNameForInputSource:` names a layout the table knows");
		check([[NSTextInputContext localizedNameForInputSource:@"de_CH"] isEqualToString:@"de_CH"],
		      "and answers an identifier it does not know rather than inventing a name");

		/* THE CONTEXT'S TWO LIMITS. The locale list narrows `-textInputSources`, and its default allows anything. */
		view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 60.0)];
		context = (NSTextInputContext *)[view inputContext];
		check([[context allowedInputSourceLocales] containsObject:NSAllowsAnyInputSource],
		      "a fresh context allows any input source, which is Apple's default");
		check([[context textInputSources] count] == [sources count],
		      "so it offers every layout the machine can build");
		[context setAllowedInputSourceLocales:[NSArray arrayWithObject:@"de_DE"]];
		check([[context allowedInputSourceLocales] isEqual:[NSArray arrayWithObject:@"de_DE"]],
		      "`-setAllowedInputSourceLocales:` round-trips");
		{
			NSArray *narrowed = [context textInputSources];

			printf("        (restricted to de_DE: %lu source(s))\n", (unsigned long)[narrowed count]);
			check([narrowed count] <= 1, "a context restricted to de_DE offers at most the German layout");
			if ([sources containsObject:@"de"]) {
				check([narrowed isEqual:[NSArray arrayWithObject:@"de"]],
				      "and offers exactly it — the restriction is BEHAVIOUR, not storage");
			}
		}
		[context setAllowedInputSourceLocales:[NSArray arrayWithObject:NSAllowsAnyInputSource]];
		check([[context textInputSources] count] == [sources count], "and the sentinel widens it back to every layout");

		/* THE GLYPH-INFO FLAG IS RECORDED, AND THE HEADER SAYS NOTHING HERE READS IT. */
		check(![context acceptsGlyphInfo], "a fresh context does not accept glyph info, which is the era's default");
		[context setAcceptsGlyphInfo:YES];
		check([context acceptsGlyphInfo], "and `-setAcceptsGlyphInfo:` round-trips");
		[view release];
	}

	[pool release];
	printf("text_input_context: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
