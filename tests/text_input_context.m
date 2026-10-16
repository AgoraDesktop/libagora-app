/*
 * text_input_context.m — THE INPUT CONTEXT: WHERE A KEY GOES BEFORE THE TEXT VIEW, AND WHERE A COMPOSITION LIVES.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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

	/* 4. **AND THE SOURCE DOORS NAME THE ONE KEYBOARD THIS TIER HAS.** */
	{
		NSText *text = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 24.0)];
		NSTextInputContext *context = (NSTextInputContext *)[text inputContext];

		check([[context textInputSources] count] == 1, "one input source is listed — the stock keyboard");
		check([context selectedInputSource] != nil, "and it is the selected one");
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

	[pool release];
	printf("text_input_context: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
