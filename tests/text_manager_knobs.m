/*
 * text_manager_knobs — the manager's stored settings, the one that changes the layout, the caret's places on a line, and
 * the three questions about the view a document is shown in.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **MOST OF THESE ARE STORED, AND THE TEST SAYS SO BY CHECKING THE ROUND TRIP RATHER THAN AN EFFECT.** A flag that has no
 * effect in this tier is still a real door — a caller sets it and reads it back — and the header names what each would
 * mean. The exception is `-usesFontLeading`, and it is asserted where it matters: turning it on makes the line height the
 * font's leading taller AND MOVES THE SECOND LINE'S BASELINE BY THAT MUCH, which is the claim that the knob reaches the
 * breaker rather than a field.
 *
 * **THE FONT MATTERS TO THAT TEST AND THE DEFAULT ONE HAS NO LEADING.** The system font's leading measures zero on this
 * machine, so a probe that used it would prove nothing; the store is set in Helvetica, whose leading the probe reads at
 * run time and compares against.
 *
 * The insertion points are checked as a count and an order: one per character of the line plus the line's end, indexes
 * ascending, positions ascending, and the last position past the last character.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSWindow.h>
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

static int close_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE STORED KNOBS COME BACK, AND THE ONE THAT CANNOT BE TRUE SAYS SO.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];

			check(![manager allowsNonContiguousLayout] && ![manager hasNonContiguousLayout],
			      "a manager starts with contiguous layout and never has a hole");
			[manager setAllowsNonContiguousLayout:YES];
			check([manager allowsNonContiguousLayout] && ![manager hasNonContiguousLayout],
			      "allowing it is stored, and having one is still NO because a layout here is complete");

			check(![manager backgroundLayoutEnabled], "background layout starts off");
			[manager setBackgroundLayoutEnabled:YES];
			check([manager backgroundLayoutEnabled], "and the flag comes back");

			[manager setShowsInvisibleCharacters:YES];
			[manager setShowsControlCharacters:YES];
			check([manager showsInvisibleCharacters] && [manager showsControlCharacters],
			      "the two character-visibility flags are stored and answered");
			[manager setShowsInvisibleCharacters:NO];
			check(![manager showsInvisibleCharacters] && [manager showsControlCharacters],
			      "and each one moves on its own");

			check(![manager usesScreenFonts], "screen fonts start off");
			[manager setUsesScreenFonts:YES];
			check([manager usesScreenFonts], "and the flag comes back");

			check([manager hyphenationFactor] == 0.0f, "the manager's own hyphenation factor starts at zero");
			[manager setHyphenationFactor:0.5f];
			check([manager hyphenationFactor] == 0.5f, "and stores what it is given");

			check([manager layoutOptions] == 0, "no layout option bits are defined here, so the answer is zero");
			[manager release];
		}

		/* ============================================================================================
		 * 2. THE LIVE KNOB: leading makes a line taller AND MOVES THE NEXT LINE'S BASELINE.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(320.0, 200.0)];
			NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"one\ntwo\n"];
			NSFont *font = [NSFont fontWithName:@"Helvetica" size:12.0];
			CGFloat leading;
			CGFloat heightBefore;
			CGFloat heightAfter;
			CGFloat baselineBefore;
			CGFloat baselineAfter;

			[store addLayoutManager:manager];
			[manager addTextContainer:container];
			if (font == nil) {
				font = [NSFont systemFontOfSize:12.0];
			}
			leading = [font leading];
			[store addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, [store length])];
			printf("  (note: the probe's font has %g points of leading)\n", (double)leading);

			heightBefore = [manager cg_lineHeight];
			baselineBefore = [manager cg_baselineForGlyphAtIndex:4];
			check(close_enough(heightBefore, [font ascender] - [font descender]),
			      "a line is the font's ascender minus its descender while leading is off");

			check(![manager usesFontLeading], "leading starts off, which is this tier's stated default");
			[manager setUsesFontLeading:YES];
			check([manager usesFontLeading], "turning it on is stored");

			heightAfter = [manager cg_lineHeight];
			baselineAfter = [manager cg_baselineForGlyphAtIndex:4];
			check(close_enough(heightAfter, heightBefore + leading),
			      "and the line height grows by the font's leading");
			check(close_enough(baselineAfter - baselineBefore, leading),
			      "so the SECOND line's baseline moved by exactly the leading — the knob reached the breaker");

			[manager setUsesFontLeading:NO];
			check(close_enough([manager cg_lineHeight], heightBefore) && [manager cg_invalidatedRange].location == 0,
			      "turning it off restores the height and marks the document stale");

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 3. THE CARET'S PLACES ON A LINE: one per character plus the end.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = [[NSLayoutManager alloc] init];
			NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(320.0, 200.0)];
			NSTextStorage *store = [[NSTextStorage alloc] initWithString:@"abcd"];
			CGFloat positions[16];
			NSUInteger indexes[16];
			NSUInteger count;

			[store addLayoutManager:manager];
			[manager addTextContainer:container];

			count = [manager getLineFragmentInsertionPointsForCharacterAtIndex:1 alternatePositions:NO
								     inDisplayOrder:YES positions:positions
								     characterIndexes:indexes];
			check(count == 5, "a four-character line has five places to put a caret");
			check(indexes[0] == 0 && indexes[4] == 4 && indexes[1] == 1 && indexes[3] == 3,
			      "and the character each place sits before runs from the line's first to its end");
			check(positions[0] < positions[1] && positions[1] < positions[2]
				      && positions[2] < positions[3] && positions[3] <= positions[4],
			      "in display order the positions ascend");

			/* THE ALTERNATE-POSITION FLAG HAS NOTHING TO ADD IN ONE DIRECTION, and the count says so. */
			{
				CGFloat alternates[16];
				NSUInteger altIndexes[16];
				NSUInteger altCount = [manager getLineFragmentInsertionPointsForCharacterAtIndex:1
								      alternatePositions:YES inDisplayOrder:NO
										 positions:alternates characterIndexes:altIndexes];

				check(altCount == count, "asking for bidi alternates adds no places, because this tier lays out one direction");
			}

			/* AN EMPTY DOCUMENT HAS ONE PLACE, AT ITS ORIGIN. */
			{
				NSLayoutManager *empty = [[NSLayoutManager alloc] init];
				NSTextContainer *emptyContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(80.0, 40.0)];
				NSTextStorage *emptyStore = [[NSTextStorage alloc] initWithString:@""];
				CGFloat emptyPositions[4];
				NSUInteger emptyIndexes[4];

				[emptyStore addLayoutManager:empty];
				[empty addTextContainer:emptyContainer];
				check([empty getLineFragmentInsertionPointsForCharacterAtIndex:0 alternatePositions:NO
									 inDisplayOrder:YES positions:emptyPositions
									 characterIndexes:emptyIndexes] == 1,
				      "an empty document's caret has one place");
				[emptyStore release];
				[empty release];
				[emptyContainer release];
			}

			/* AND A CHARACTER PAST THE TEXT ANSWERS NOTHING RATHER THAN A GUESSED PLACE. */
			check([manager getLineFragmentInsertionPointsForCharacterAtIndex:99 alternatePositions:NO
								    inDisplayOrder:YES positions:NULL characterIndexes:NULL] == 0,
			      "an index past the text has no place on any line");

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 4. THE THREE QUESTIONS ABOUT THE VIEW.
		 * ========================================================================================== */
		{
			/* **THE VIEW'S OWN TRIO, NOT A HAND-BUILT ONE.** `-layoutManagerOwnsFirstResponderInWindow:` compares the
			 * responder's manager with the receiver; a manager attached by hand to a container the view already has is a
			 * DIFFERENT manager, so the positive case would be false for the right reason and the wrong claim. */
			NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 120.0)];
			NSLayoutManager *manager;
			NSTextContainer *container;
			NSWindow *window;

			[view setString:@"a document"];
			manager = [view layoutManager];
			container = [view textContainer];

			check([manager firstTextView] == view, "the view the container names is the first one");
			check([manager textViewForBeginningOfSelection] == view,
			      "the beginning of the selection answers the same view, because the manager does not know a selection");

			/* A REAL WINDOW, because the question is about its responder chain rather than about a pointer comparison
			 * the manager could make up. */
			window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 320.0, 120.0)
							 styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
			if (window != nil) {
				NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 120.0)];
				NSTextField *other = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 24.0)];

				/* **THE FIRST CASE.** The text view is in the window and is its first responder. */
				[window setContentView:content];
				[content addSubview:view];
				[content addSubview:other];
				[window makeFirstResponder:view];
				check([manager layoutManagerOwnsFirstResponderInWindow:window],
				      "the manager owns the first responder when its view is the window's");

				/* **AND THE SECOND: A DIFFERENT VIEW TAKES IT.** A field is a responder, so this is a real handover
				 * rather than a `makeFirstResponder:` that quietly failed. */
				check([window makeFirstResponder:other], "another view can take the responder status");
				check(![manager layoutManagerOwnsFirstResponderInWindow:window],
				      "and then the manager does not own it");
				[other release];
				[content release];
				[window release];
			} else {
				printf("  SKIP  no window could be created for the responder question\n");
			}
			check(![manager layoutManagerOwnsFirstResponderInWindow:nil],
			      "a nil window answers NO rather than crashing");

			[view release];
			(void)container;
			(void)manager;
		}

		if (failures == 0) {
			printf("text_manager_knobs: all checks passed\n");
			return 0;
		}
		printf("text_manager_knobs: FAILURES\n");
		return 1;
	}
}
