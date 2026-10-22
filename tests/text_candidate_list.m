/*
 * text_candidate_list.m — THE READINGS AN INPUT METHOD OFFERS, THE WINDOW THAT SHOWS THEM, AND THE PICK.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A CANDIDATE LIST IS THREE THINGS: A LIST, A WINDOW, AND A METHOD.** The list holds the readings and the selected
 * one and draws them (checked as ink and as the accent fill, which MOVES when the selection does); the window sizes
 * itself from the list and places itself UNDER THE CARET the client reports (checked against
 * `-firstRectForCharacterRange:`, and it FOLLOWS the caret when the window moves); and the method holds a letter's
 * readings open across keystrokes — arrows to move, Return to pick, Escape to take back — and DECLINES a key it does
 * not pick from.
 */
#import <AppKit/AGCandidateListView.h>
#import <AppKit/AGCandidateWindow.h>
#import <AppKit/AGVariantsInputMethod.h>
#import <AppKit/NSTextInputContext.h>
#import <AppKit/NSTextInput.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
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

static NSArray *readings(NSString *a, NSString *b, NSString *c)
{
	return [NSArray arrayWithObjects:a, b, c, nil];
}

static int is_accent(NSColor *colour)
{
	NSColor *accent = [NSColor cg_accentColor];

	return colour != nil
		&& fabs([colour redComponent] - [accent redComponent]) < 0.1
		&& fabs([colour greenComponent] - [accent greenComponent]) < 0.1
		&& fabs([colour blueComponent] - [accent blueComponent]) < 0.1;
}

/* THE ACCENT'S LEFTMOST PIXEL, which moves RIGHT when the selection moves to a later candidate — the whole of the
 * "which one is marked" question, read as ink rather than trusted to an index. */
static int leftmost_accent(NSBitmapImageRep *rep, int width, int height)
{
	int x, y;

	for (x = 0; x < width; x++) {
		for (y = 0; y < height; y++) {
			if (is_accent([rep colorAtX:x y:y])) {
				return x;
			}
		}
	}
	return -1;
}

static int count_dark(NSBitmapImageRep *rep, int width, int height)
{
	int x, y, count = 0;

	for (y = 0; y < height; y++) {
		for (x = 0; x < width; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.3 && [c greenComponent] < 0.3 && [c blueComponent] < 0.3) {
				count++;
			}
		}
	}
	return count;
}

static NSBitmapImageRep *draw_list(AGCandidateListView *view, int width, int height)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height)] fill];
	[view drawRect:[view bounds]];
	return rep;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE LIST: ITS SIZE COMES FROM THE STRINGS, AND THE MARK MOVES.** */
	{
		AGCandidateListView *list = [[AGCandidateListView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
		NSSize size;

		[list setCandidates:readings(@"a", @"\u00e0", @"\u00e1")];
		size = [list cg_sizeForCandidates];
		printf("  (note: three readings measure %g x %g)\n", (double)size.width, (double)size.height);
		check([list selectedIndex] == 0, "a fresh list marks the first reading");
		check(size.width > 0.0 && fabs(size.height - (AGCandidateRowHeight + 2.0 * AGCandidatePanelPadding)) < 0.01,
		      "its size is the row's height plus the panel's padding");
		check([list cg_rectForCandidateAtIndex:0].origin.x < [list cg_rectForCandidateAtIndex:1].origin.x
		      && [list cg_rectForCandidateAtIndex:1].origin.x < [list cg_rectForCandidateAtIndex:2].origin.x,
		      "the readings run left to right");
		check([list cg_indexAtPoint:NSMakePoint([list cg_rectForCandidateAtIndex:2].origin.x + 2.0,
							AGCandidatePanelPadding + 2.0)] == 2,
		      "and a point in a reading's box is that reading");

		/* THE MARK IS THE ACCENT FILL, AND IT MOVES. */
		[list setFrame:NSMakeRect(0.0, 0.0, size.width, size.height)];
		{
			int w = (int)ceil(size.width), h = (int)ceil(size.height);
			NSBitmapImageRep *first = draw_list(list, w, h);
			int leftAtFirst = leftmost_accent(first, w, h);
			int ink = count_dark(first, w, h);
			NSBitmapImageRep *second;
			int leftAtSecond;

			[list setSelectedIndex:1];
			second = draw_list(list, w, h);
			leftAtSecond = leftmost_accent(second, w, h);
			printf("  (note: the accent starts at x=%d with the first marked and x=%d with the second)\n",
			       leftAtFirst, leftAtSecond);
			check(ink > 0, "the readings are drawn as ink");
			check(leftAtFirst >= 0 && leftAtSecond > leftAtFirst,
			      "and the accent fill MOVES right when a later reading is marked");
			check([list selectedIndex] == 1, "the selection is the one that was set");
			[list setSelectedIndex:-1];
			check([list selectedIndex] == 2, "a step back from the first wraps to the last");
			[second release];
			[first release];
		}
		[list release];
	}

	/* 2. **THE WINDOW: SIZED FROM THE LIST, PLACED UNDER THE CARET, AND FOLLOWING IT.** */
	{
		NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(100.0, 150.0, 240.0, 60.0)
				   styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 240.0, 60.0)];
		NSTextInputContext *context;
		AGVariantsInputMethod *method = [[AGVariantsInputMethod alloc] init];
		AGCandidateWindow *window;
		NSRect caret, frameBefore, frameAfter;

		[host setContentView:view];
		context = (NSTextInputContext *)[view inputContext];
		[context setInputSource:method];
		[view setEditable:YES];
		[view setString:@""];
		[context handleEvent:key(@"a", 0)];	/* begins a composition, which shows the window */

		window = [method candidateWindow];
		check(window != nil, "an 'a' opens a candidate window");
		if (window != nil) {
			caret = [view firstRectForCharacterRange:[view markedRange]];
			frameBefore = [window frame];
			printf("  (note: the caret is at %g,%g and the window at %g,%g %gx%g)\n",
			       (double)caret.origin.x, (double)caret.origin.y,
			       (double)frameBefore.origin.x, (double)frameBefore.origin.y,
			       (double)frameBefore.size.width, (double)frameBefore.size.height);
			check(fabs(frameBefore.origin.x - caret.origin.x) < 0.01,
			      "the window is placed at the caret's x");
			check(fabs(frameBefore.origin.y - (caret.origin.y - frameBefore.size.height - 2.0)) < 0.01,
			      "and hangs UNDER it");
			check(frameBefore.size.width > 0.0 && frameBefore.size.height > 0.0, "with the list's own size");

			/* THE CARET MOVES, THE WINDOW FOLLOWS. */
			[host setFrameOrigin:NSMakePoint(140.0, 150.0)];
			[context invalidateCharacterCoordinates];
			frameAfter = [window frame];
			check(fabs(frameAfter.origin.x - (frameBefore.origin.x + 40.0)) < 0.01,
			      "`-invalidateCharacterCoordinates` moves the window when the caret's window moves");
		}
		[context setInputSource:nil];
		[method release];
		[view release];
		[host release];
	}

	/* 3. **THE METHOD: A LETTER'S READINGS, PICKED.** */
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 60.0)];
		NSTextInputContext *context = (NSTextInputContext *)[view inputContext];
		AGVariantsInputMethod *method = [[AGVariantsInputMethod alloc] init];
		NSString *rightArrow = one((unichar)NSRightArrowFunctionKey);
		NSString *leftArrow = one((unichar)NSLeftArrowFunctionKey);
		NSString *firstVariant;

		[context setInputSource:method];
		[view setEditable:YES];

		[view setString:@""];
		[context handleEvent:key(@"a", 0)];
		check([method isComposing] && [view hasMarkedText], "a letter with variants begins a composition");
		check([[method candidates] count] == 7, "and `a` offers the plain letter and six variants");
		check([[[method candidates] objectAtIndex:0] isEqualToString:@"a"],
		      "the PLAIN letter is first, so typing on commits it");
		check([method selectedCandidateIndex] == 0, "and it is the one marked");

		[context handleEvent:key(rightArrow, 0)];
		check([method selectedCandidateIndex] == 1, "an arrow moves the mark");
		firstVariant = [[method candidates] objectAtIndex:1];
		[context handleEvent:key(@"\r", 0)];
		check(![method isComposing] && ![view hasMarkedText], "Return commits and ends the composition");
		check([[view string] isEqualToString:firstVariant], "and the store holds the reading that was marked");

		/* ESCAPE TAKES IT BACK. */
		[view setString:@""];
		[context handleEvent:key(@"a", 0)];
		[context handleEvent:key(one(0x1B), 0)];
		check(![method isComposing] && [[view string] isEqualToString:@""],
		      "Escape takes the whole composition back");

		/* A LETTER WITH ONE FORM IS DECLINED. */
		[view setString:@""];
		[context handleEvent:key(@"q", 0)];
		check(![method isComposing] && [[view string] isEqualToString:@"q"],
		      "a letter with one form is DECLINED and the standard binding inserts it");

		/* A RUN OF LETTERS COMMITS THE PICK AND BEGINS THE NEXT. */
		[view setString:@""];
		[context handleEvent:key(@"a", 0)];
		[context handleEvent:key(@"e", 0)];
		check([[view string] isEqualToString:@"ae"], "committing `a` and beginning `e` leaves both in the store");
		check([method isComposing] && [[[method candidates] objectAtIndex:0] isEqualToString:@"e"],
		      "and the second letter's readings are the ones offered");

		/* THE STEP BACK WRAPS, and the list is where the wrap is decided. */
		[view setString:@""];
		[context handleEvent:key(@"a", 0)];
		[context handleEvent:key(leftArrow, 0)];
		check([method selectedCandidateIndex] == (NSInteger)[[method candidates] count] - 1,
		      "a step back from the first reading wraps to the last");

		[context setInputSource:nil];
		[method release];
		[view release];
	}

	[pool release];
	printf("text_candidate_list: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
