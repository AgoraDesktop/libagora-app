/*
 * control_metrics — is a push button's height a METRIC, and is a line of text a plausible height?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE TWO HALVES ARE ONE BUG, WHICH IS WHY THEY ARE ONE PROBE.** A push button came out 35.2 points tall — a
 * property of the FONT rather than of the control — and the font half of that was wrong too: a 13-point line measured
 * 25.2 points, or 1.94 em, because the seam answered `CGFontGetLeading` with FreeType's `face->height` (the LINE
 * height, which its callers then ADD to ascent and descent) and `CGFontGetDescent` with a negative number (which
 * those callers then SUBTRACT).
 *
 * SO THE ASSERTIONS COME IN THE ORDER THE DEFECT CHAIN RUNS:
 *
 *   1. The font's own numbers have the signs a caller can add up: ascent positive, descent negative (that door's
 *      contract), and the band they make is about one em.
 *   2. A MEASURED line of text is a plausible line height rather than twice one. This is the case that fails on the
 *      double count, and it is measured through `-sizeWithAttributes:` — the AppKit door a control actually uses —
 *      rather than through the engine door underneath it.
 *   3. A push button's height is the BEZEL's metric and does not move with the title.
 *   4. And a button nobody sized at all lands on the same number.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSAttributedString.h>
#include <math.h>
#include <stdio.h>

/* THE STANDARD PUSH-BUTTON HEIGHT, WRITTEN HERE AS WELL AS IN THE CELL SO THE PROBE FAILS IF THE CELL MOVES IT. */
#define WANT_BEZEL_HEIGHT 23.0
#define WANT_BEZEL_AIR    3.0

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSButtonCell *push(NSString *title)
{
	NSButtonCell *c = [[NSButtonCell alloc] initTextCell:title];

	[c setBordered:YES];
	[c setBezeled:YES];
	return c;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
		CGFloat size = [NSFont systemFontSize];
		CGFloat band;
		NSSize measured;

		/* 1. THE FONT'S OWN SIGNS AND BAND. */
		check(size > 0.0, "the system font has a size");
		check([font ascender] > 0.0, "`-ascender` is POSITIVE, so a line's band adds it");
		check([font descender] < 0.0,
		      "and `-descender` is NEGATIVE, which is that door's own contract and why callers use fabs");
		band = [font ascender] + (CGFloat)fabs((double)[font descender]);
		printf("  (note: %.1f pt font — ascent %.1f, descent %.1f, band %.1f = %.2f em)\n",
		       size, [font ascender], [font descender], band, band / size);
		check(band > 0.9 * size && band < 1.6 * size,
		      "and the band they make is about one em, not two and not three quarters of one");

		/* 2. **THE MEASUREMENT, WHICH IS THE REGRESSION TEST FOR THE DOUBLE COUNT.** Before the fix this answered
		 * 25.2 points for a 13-point font — 1.94 em — and a line that tall is what made every control fat. */
		measured = [@"OK" sizeWithAttributes:
				[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];
		printf("  (note: a measured line of \"OK\" is %.1f x %.1f)\n", measured.width, measured.height);
		check(measured.height > 1.0 * size && measured.height < 1.5 * size,
		      "a MEASURED line of text is a plausible line height — not twice one, and not less than the glyphs");

		/* **AND THE ONE THAT WAS A CRASH RATHER THAN AN ANSWER.** A zero-length title is not exotic — it is what a button
		 * is BORN with (`initTextCell:@""`), and it is why this case exists at all: measuring one used to segfault
		 * inside `CFBasicHashFindBucket`, because `CFRunArrayGetValueAtIndex` read the uninitialised first slot of an
		 * empty run array and the garbage looked enough like a dictionary to be used as one. A string with no
		 * characters measures nothing, which is the answer the engine's own `CTLineCreateWithAttributedString` already
		 * documents for a zero-length string. */
		{
			NSSize empty = [@"" sizeWithAttributes:
					[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]];

			check(empty.width == 0.0 && empty.height == 0.0,
			      "and an EMPTY string measures nothing at all, rather than reaching into an empty run array");
		}

		/* 3. **THE BEZEL'S METRIC.** Two titles of very different lengths, one height. */
		{
			NSButtonCell *shortTitle = push(@"OK");
			NSButtonCell *longTitle = push(@"A Considerably Longer Title");
			NSSize a = [shortTitle cellSize];
			NSSize b = [longTitle cellSize];

			printf("  (note: push cells measure %.1f x %.1f and %.1f x %.1f)\n",
			       a.width, a.height, b.width, b.height);
			check(a.height == WANT_BEZEL_HEIGHT && b.height == WANT_BEZEL_HEIGHT,
			      "a push button's height is the STANDARD ONE (23 points), whatever its title");
			check(b.width > a.width, "while its WIDTH still grows with the title, which a bezel does");
			check(band + 2.0 * WANT_BEZEL_AIR <= WANT_BEZEL_HEIGHT,
			      "and the font's band fits inside that height with the bezel's air to spare");
		}

		/* 4. **AND A BUTTON NOBODY SIZED.** A degenerate frame is filled in by `-sizeToFit` in this tier, so a
		 * button made with `NSZeroRect` is a real button at the standard height rather than a point. */
		{
			NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
			NSButton *fitted = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

			[button setTitle:@"OK"];
			[fitted setTitle:@"OK"];
			[fitted sizeToFit];
			printf("  (note: zero-frame button %.1f x %.1f; sizeToFit frame %.1f x %.1f bounds %.1f x %.1f)\n",
			       [button frame].size.width, [button frame].size.height,
			       [fitted frame].size.width, [fitted frame].size.height,
			       [fitted bounds].size.width, [fitted bounds].size.height);
			check([button frame].size.height == WANT_BEZEL_HEIGHT,
			      "a button made with a ZERO frame lands on the standard height");
			check([fitted frame].size.height == WANT_BEZEL_HEIGHT,
			      "and so does `-sizeToFit` on a button that was given a frame");
			/* **AND THE BOUNDS ARE THE HALF THIS CASE DID NOT ASK ABOUT, WHICH IS HOW THE BUG GOT THROUGH IT.**
			 * `-sizeToFit` goes through `NSView -setFrameSize:`, and that door changed the FRAME alone: `-setFrame:`
			 * states the rule where it does the same work — "the size is shared and the origins are not" — and this
			 * one left `_bounds` at whatever size the view was born with. The frame above was therefore RIGHT while
			 * the view was 0x0 to everything that reads its bounds, and `-visibleRect` intersects those: MEASURED on
			 * a live window, a pop-up button fitted this way reported frame 118x23, BOUNDS 0x0, visibleRect 0x0, and
			 * was never drawn — while a button given the same frame in `-initWithFrame:` drew normally. */
			check([fitted bounds].size.height == WANT_BEZEL_HEIGHT &&
			      [fitted bounds].size.width == [fitted frame].size.width,
			      "and the BOUNDS moved with the frame");
			check([fitted visibleRect].size.width > 0.0 && [fitted visibleRect].size.height > 0.0,
			      "so the view is not INVISIBLE to the display path");
			[button release];
			[fitted release];
		}

		/* 5. **AND THE METRIC IS THE BEZEL'S, NOT EVERY BUTTON'S.** A checkbox has no bezel, so it measures its own
		 * row instead: the case that would otherwise make an indicator TALLER than the push button beside it. */
		{
			NSButtonCell *box = [[NSButtonCell alloc] initTextCell:@"A Checkbox"];

			[box setButtonType:NSSwitchButton];
			printf("  (note: a checkbox cell measures %.1f x %.1f)\n", [box cellSize].width, [box cellSize].height);
			check([box cellSize].height < WANT_BEZEL_HEIGHT && [box cellSize].height >= 14.0,
			      "a checkbox takes its own row height — the metric belongs to the BEZEL, so no bezel means no 23");
			[box release];
		}

		/* 6. **AND THE SIZES WITH NO PUBLISHED METRIC KEEP THE ONE THAT IS PUBLISHED.** The refusal is printed at
		 * `-setControlSize:` (see the cell), so what this pins is that the height does NOT quietly become one of two
		 * invented numbers — which is the failure mode a table with three guessed rows would have. */
		{
			NSButtonCell *small = push(@"OK");
			NSButtonCell *mini = push(@"OK");

			[small setControlSize:NSSmallControlSize];
			[mini setControlSize:NSMiniControlSize];
			check([small cellSize].height == WANT_BEZEL_HEIGHT && [mini cellSize].height == WANT_BEZEL_HEIGHT,
			      "a small or mini bezelled button keeps the REGULAR metric rather than an invented one");
			[small release];
			[mini release];
		}

		printf("control_metrics: %d case(s) failed\n", s_failed);
	}
	return s_failed == 0 ? 0 : 1;
}
