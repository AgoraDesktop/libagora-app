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
 * `-defaultTabInterval` of 40. And the tab draws no ink, which is what a box in the line means. A fourth case reads
 * the COLUMN TERMINATORS: `+[NSTextTab columnTerminatorsForLocale:]` is the locale's decimal separator, which ICU
 * answers, and `NSTabColumnTerminatorsAttributeName` is the options key that names them. A fifth puts a DECIMAL stop
 * to work: the number's point lands AT the stop whatever the integer part's length, which a left stop cannot do.
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

/* THE x OF THE COMMA IN `x\t12,5` FOR A GIVEN DECIMAL STOP, which is where the stop's own terminators show: a stop
 * that treats the comma as the point lands it ON the stop, and one that does not carries the whole number instead. */
static CGFloat comma_offset_with_tab(NSTextTab *tab)
{
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"x\t12,5"];
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 100.0)];
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	CGFloat offset;

	[style addTabStop:tab];
	[container setLineFragmentPadding:0.0];
	[store addLayoutManager:manager];
	[manager addTextContainer:container];
	[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [store length])];
	offset = [manager cg_offsetForGlyphAtIndex:4];
	[style release];
	[container release];
	[manager release];
	[store release];
	return offset;
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

	/* 4. **AND THE COLUMN'S TERMINATORS COME FROM THE LOCALE.** `+columnTerminatorsForLocale:` answers the locale's
	 * decimal separator — ICU's data, read through `NSLocale -decimalSeparator` — and the options key names them. A
	 * decimal STOP still carries its type and has no alignment to be, which is the half that remains owed. */
	{
		NSArray *us = [NSTextTab columnTerminatorsForLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
		NSArray *de = [NSTextTab columnTerminatorsForLocale:[NSLocale localeWithLocaleIdentifier:@"de_DE"]];
		NSArray *none = [NSTextTab columnTerminatorsForLocale:nil];
		NSTextTab *decimal;

		printf("  (note: en_US terminators %s, de_DE %s)\n",
		       ([us count] > 0) ? [[us objectAtIndex:0] UTF8String] : "(none)",
		       ([de count] > 0) ? [[de objectAtIndex:0] UTF8String] : "(none)");
		check([us count] == 1 && [[us objectAtIndex:0] isEqualToString:@"."],
		      "an English locale's decimal column is ended by a period");
		check([de count] == 1 && [[de objectAtIndex:0] isEqualToString:@","],
		      "a German one's by a comma — the separator is the LOCALE's, not a constant here");
		check([none count] == 1, "and a nil locale falls back to the current one rather than answering nothing");
		check([NSTabColumnTerminatorsAttributeName isEqualToString:@"NSTabColumnTerminators"],
		      "the options key this tier names has its own spelling");
		decimal = [[[NSTextTab alloc] initWithType:NSDecimalTabStopType location:120.0] autorelease];
		check([decimal tabStopType] == NSDecimalTabStopType && [decimal alignment] == NSNaturalTextAlignment,
		      "and a decimal stop keeps its type, with no alignment to be (it aligns on a point, not an edge)");
	}

	/* 5. **AND A DECIMAL TAB ALIGNS THE NUMBER ON ITS POINT.** Core Text has no decimal edge, so the manager lays the
	 * line out with the stop as a LEFT one and REBUILDS it with the stop moved left by the integer part's width — the
	 * point then sits AT the stop whatever the integer part's length, which is the thing a left stop cannot do. */
	{
		NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"x\t12.5\ny\t123.5"];
		NSLayoutManager *manager = [[NSLayoutManager alloc] init];
		NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 100.0)];
		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		NSTextTab *decimal = [[NSTextTab alloc] initWithType:NSDecimalTabStopType location:100.0];
		CGFloat shortDot, longDot;

		[style addTabStop:decimal];
		[decimal release];
		[container setLineFragmentPadding:0.0];
		[store addLayoutManager:manager];
		[manager addTextContainer:container];
		[store addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [store length])];
		shortDot = [manager cg_offsetForGlyphAtIndex:4];
		longDot = [manager cg_offsetForGlyphAtIndex:12];
		printf("  (note: a decimal stop at 100 put `12.5`'s point at %g and `123.5`'s at %g)\n",
		       (double)shortDot, (double)longDot);
		check(fabs(shortDot - 100.0) < 0.01, "a decimal tab puts the point of `12.5` AT the stop");
		check(fabs(longDot - 100.0) < 0.01,
		      "and `123.5`'s at the SAME stop — the integer part grew, the point did not move");
		[style release];
		[container release];
		[manager release];
		[store release];
	}

	/* 6. **AND A DECIMAL STOP'S OWN TERMINATORS, WHICH `-initWithType:location:options:` IS THE DOOR FOR.** The same
	 * stop at 100, twice: with the PERIOD as its terminator the comma in `12,5` is no point at all, so the number is
	 * carried whole and right-aligned at the stop; with the COMMA as its terminator the comma lands ON the stop. */
	{
		NSArray *periods = [NSArray arrayWithObject:@"."];
		NSArray *commas = [NSArray arrayWithObject:@","];
		NSTextTab *periodStop = [[NSTextTab alloc] initWithType:NSDecimalTabStopType location:100.0
			options:[NSDictionary dictionaryWithObject:periods forKey:NSTabColumnTerminatorsAttributeName]];
		NSTextTab *commaStop = [[NSTextTab alloc] initWithType:NSDecimalTabStopType location:100.0
			options:[NSDictionary dictionaryWithObject:commas forKey:NSTabColumnTerminatorsAttributeName]];
		CGFloat periodComma = comma_offset_with_tab(periodStop);
		CGFloat commaComma = comma_offset_with_tab(commaStop);

		printf("  (note: with a PERIOD terminator the comma is at %g; with a COMMA it is at %g)\n",
		       (double)periodComma, (double)commaComma);
		check(fabs(periodComma - 100.0) > 1.0,
		      "a stop whose terminator is the PERIOD finds no point in `12,5` and carries the number whole");
		check(fabs(commaComma - 100.0) < 0.01,
		      "and the stop's OWN comma terminator lands the comma ON the stop");
		[periodStop release];
		[commaStop release];
	}

	[pool release];
	printf("text_tab_stops: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
