/*
 * text_tab_stops.m — A TAB GOES TO ITS STOP, AND THE STOPS COME FROM THE PARAGRAPH STYLE.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A TAB IS A PLACE, NOT A WIDTH, SO THE CLAIM IS WHERE THE NEXT CHARACTER LANDS.** `NSTextTab` names a location and
 * a kind; the manager copies them into the `CTParagraphStyle` it builds; and `CTLine` advances a `\t` to the next stop
 * — so the character after the tab begins AT the stop. The probe reads the manager's own offsets: the two tabs of
 * `a\tb\tc` land at 50 and 100 when the style says so, and at 40 and 80 when the style has no stops but a
 * `-defaultTabInterval` of 40. And the tab draws no ink, which is what a box in the line means.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextTab.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSParagraphStyle.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE STYLE'S STOPS ARE THE LAYOUT's.** */
	{
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"a\tb\tc"];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 100.0)];
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		CGFloat bX, cX;

		check([[style tabStops] count] == 0, "a fresh style has no tab stops");
		[style addTabStop:[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:50.0] autorelease]];
		[style addTabStop:[[[NSTextTab alloc] initWithType:NSLeftTabStopType location:100.0] autorelease]];
		check([[style tabStops] count] == 2, "and `-addTabStop:` puts two in");
		check([[[style tabStops] objectAtIndex:0] location] == 50.0, "the first is at 50, which `-location` answers");
		check([[[style tabStops] objectAtIndex:0] tabStopType] == NSLeftTabStopType,
		      "and its kind is the one it was made with");

		[container setLineFragmentPadding:0.0];
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, 5)];
		bX = [manager cg_offsetForGlyphAtIndex:2];
		cX = [manager cg_offsetForGlyphAtIndex:4];
		printf("  (note: the stops at 50 and 100 put `b` at %g and `c` at %g)\n", (double)bX, (double)cX);
		check(fabs(bX - 50.0) < 0.01, "the character after the first tab begins AT its 50-point stop");
		check(fabs(cX - 100.0) < 0.01, "and the one after the second at its 100-point stop");

		[style release];
		[container release];
		[manager release];
		[store release];
	}

	/* 2. **AND WITH NO STOPS, `-defaultTabInterval` IS THE FALLBACK.** Two tabs at multiples of 40. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"a\tb\tc"];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 100.0)];
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		CGFloat bX, cX;

		[style setDefaultTabInterval:40.0];
		[container setLineFragmentPadding:0.0];
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, 5)];
		bX = [manager cg_offsetForGlyphAtIndex:2];
		cX = [manager cg_offsetForGlyphAtIndex:4];
		printf("  (note: a 40-point interval put `b` at %g and `c` at %g)\n", (double)bX, (double)cX);
		check(fabs(bX - 40.0) < 0.01, "the first tab falls on the 40-point interval");
		check(fabs(cX - 80.0) < 0.01, "and the second on the next multiple, 80");

		[style release];
		[container release];
		[manager release];
		[store release];
	}

	/* 3. **AND THE VIEW TYPES ONE, WHICH IS THE SAME CHARACTER THE LAYOUT WALKS.** */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 60.0)];

		[view setString:@"a"];
		[view insertTab:nil];
		check([[view string] isEqualToString:@"a\t"], "`-insertTab:` puts a tab in the store");
		[view release];
	}

	[pool release];
	printf("text_tab_stops: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
