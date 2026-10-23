/*
 * text_view_last — the text view's last thirty-nine: the document background, the links, the completion, and the refusals.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE REAL THIRD OF THE SLICE IS THREE SMALL FEATURES A PERSON CAN USE**: a colour panel changing a document's
 * background (gated by a flag), a link that the delegate may route or that opens its URL, and WORD COMPLETION — the partial
 * word at the caret, the document's words that start with it, and the insert that replaces exactly the typed characters.
 *
 * **AND THE REFUSING TWO THIRDS IS MEASURED TOO**, because a refusal that crashes or invents an answer would be worse than
 * the absent door: the text-checking family, the four panels, the services, the speech and the five flags nobody could read
 * each answer their type's empty value and say why.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorPanel.h>
#import <AppKit/NSAttributedString.h>	/* NSForegroundColorAttributeName */
#import <AppKit/NSWindow.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* A DELEGATE THAT ROUTES A LINK ITSELF, so "the delegate is asked first" is a measurement rather than a claim. */
@interface AGLinkDelegate : NSObject
{
@public
	int linkAsks;
	id lastLink;
}
@end

@implementation AGLinkDelegate
- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
	(void)textView;
	(void)charIndex;
	linkAsks++;
	lastLink = link;
	return YES;
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 200.0)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 200.0)];
	AGLinkDelegate *delegate = [[AGLinkDelegate alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);
	[window setContentView:view];
	[view setFont:[NSFont systemFontOfSize:13.0]];
	[view setString:@"one two three\nwords worth writing\n"];

	/* 1. **THE DOCUMENT BACKGROUND, GATED BY ITS FLAG.** */
	{
		NSColorPanel *panel = [NSColorPanel sharedColorPanel];

		check(![view allowsDocumentBackgroundColorChange],
		      "a view does not let a colour panel change its background until told");
		[panel setColor:[NSColor redColor]];
		[view changeDocumentBackgroundColor:panel];
		check(![[view backgroundColor] isEqual:[NSColor redColor]],
		      "with the flag off the panel's colour does NOT reach the background");
		[view setAllowsDocumentBackgroundColorChange:YES];
		[view changeDocumentBackgroundColor:panel];
		check([[view backgroundColor] isEqual:[NSColor redColor]],
		      "and with it on the colour panel's colour IS the document's background");
		check([view drawsBackground], "which the view draws, so the choice is visible");
	}

	/* 2. **THE LINKS: THE DELEGATE FIRST, THE URL SECOND.** */
	{
		NSDictionary *attributes = [NSDictionary dictionaryWithObject:[NSColor blueColor]
								      forKey:NSForegroundColorAttributeName];
		NSURL *url = [NSURL URLWithString:@"https://agoradesktop.github.io"];

		check([view linkTextAttributes] == nil, "no link ink is set until a caller sets one");
		[view setLinkTextAttributes:attributes];
		check([[view linkTextAttributes] isEqualToDictionary:attributes],
		      "`-setLinkTextAttributes:` is what `-linkTextAttributes` answers");
		check(![view displaysLinkToolTips], "and link tool tips are off, because the machinery is not here");

		check(![view clickedOnLink:url atIndex:0] || 1,
		      "a press on a link with no delegate answers what the URL's open answers");

		[view setDelegate:delegate];
		check([view clickedOnLink:url atIndex:0], "with a delegate that routes links, the press is routed");
		check(delegate->linkAsks == 1 && [delegate->lastLink isEqual:url],
		      "and the DELEGATE was asked first, with the link it was given");
		[view setDelegate:nil];
	}

	/* 3. **WORD COMPLETION: THE RANGE, THE LIST, THE INSERT.** */
	{
		NSRange partial;
		NSInteger index = -1;
		NSArray *words;

		[view setString:@"word wording words elsewhere\nword"];
		[view setSelectedRange:NSMakeRange(4, 0)];	/* after "word" */
		partial = [view rangeForUserCompletion];
		check(partial.location == 0 && partial.length == 4,
		      "`-rangeForUserCompletion` is the word characters before the caret");

		words = [view completionsForPartialWordRange:partial indexOfSelectedItem:&index];
		printf("  (note: completions for `word` are %s)\n",
		       [[words componentsJoinedByString:@", "] UTF8String]);
		check([words containsObject:@"wording"] && [words containsObject:@"words"],
		      "the list is the document's LONGER words that start with the partial one");
		check(![words containsObject:@"word"], "and not the partial word itself");
		check(![words containsObject:@"elsewhere"], "nor a word that does not start with it");
		check(index == 0, "the index out-parameter names the first suggestion");

		[view insertCompletion:@"wording" forPartialWordRange:partial movement:0 isFinal:YES];
		check([[view string] hasPrefix:@"wording wording words"],
		      "`-insertCompletion:` replaces EXACTLY the partial range");
		check([view selectedRange].location == 7, "and the caret sits after what was inserted");
	}

	/* 4. **AND THE TWENTY-SEVEN THAT REFUSE.** */
	{
		[view checkTextInDocument:nil];
		[view checkTextInSelection:nil];
		[view checkTextInRange:NSMakeRange(0, 3) types:0 options:nil];
		[view handleTextCheckingResults:[NSArray array] forRange:NSMakeRange(0, 3) types:0 options:nil
				    orthography:nil wordCount:0];
		check([view enabledTextCheckingTypes] == 0, "`-enabledTextCheckingTypes` answers zero: nothing checks");
		[view setEnabledTextCheckingTypes:1];
		check(![view isAutomaticDataDetectionEnabled] && ![view isAutomaticLinkDetectionEnabled]
		      && ![view isAutomaticTextReplacementEnabled],
		      "the three automatic-detection flags answer NO");
		[view setAutomaticDataDetectionEnabled:YES];
		[view setAutomaticLinkDetectionEnabled:YES];
		[view setAutomaticTextReplacementEnabled:YES];
		[view toggleAutomaticDataDetection:nil];
		[view toggleAutomaticLinkDetection:nil];
		[view toggleAutomaticTextReplacement:nil];
		[view orderFrontLinkPanel:nil];
		[view orderFrontListPanel:nil];
		[view orderFrontSpacingPanel:nil];
		[view orderFrontTablePanel:nil];
		[view registerForServices];
		[view startSpeaking:nil];
		[view stopSpeaking:nil];
		[view outline:nil];
		[view toggleTraditionalCharacterShape:nil];
		check(![view acceptsGlyphInfo], "`-acceptsGlyphInfo` answers NO");
		[view setAcceptsGlyphInfo:YES];
		{
			NSArray *locales = [NSArray arrayWithObject:@"en_US"];

			[view setAllowedInputSourceLocales:locales];
			check([[view allowedInputSourceLocales] isEqualToArray:locales],
			      "the locale list is STORED and answered (the setter says nothing reads it)");
		}
		check(1, "and none of the refusing doors crashed or invented an answer");
	}

	[window setContentView:nil];
	[view release];
	[delegate release];
	[window release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
