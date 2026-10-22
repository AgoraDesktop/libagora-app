/*
 * text_temporary_attributes — the table the layout sees and the store does not, and the rects a range occupies.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIM IS THAT A TEMPORARY ATTRIBUTE IS INK, NOT AN EDIT.** The probe sets a red foreground over one character,
 * draws the line into a bitmap and counts red pixels; then removes the attribute, draws again, and requires them gone.
 * That is the find-highlight round trip, and it fails if the table is stored and never read.
 *
 * **AND THE DELEGATE'S VETO IS THE SECOND HALF.** `-layoutManager:shouldUseTemporaryAttributes:forDrawingToScreen:
 * atCharacterIndex:effectiveRange:` may decline for a pass; a delegate that says NO must leave the pixels exactly as the
 * store paints them, even while the table still holds the attribute.
 *
 * The run table itself is checked as arithmetic: a set over a range SPLITS the runs it crosses and keeps their tails, an
 * add MERGES into what is there (splitting when it is in the middle), two abutting runs with one value are ONE range, and
 * `longestEffectiveRange:` clips to the caller's limit.
 *
 * The rect arrays are checked as geometry: a two-line range is two rects of the line's height, a caret is one rect of no
 * width, the character and glyph spellings agree, and the extra line a trailing newline opens is drawn only when the
 * selection covers it.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#define W 140
#define H 60

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

/* AN ATTACHMENT-STORAGE PAIR BUILT BY HAND, because the doors under test are the layout's and not the view's. */
static NSTextStorage *new_store(NSLayoutManager **managerOut, NSTextContainer **containerOut, NSString *text)
{
	NSLayoutManager *manager = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(320.0, 200.0)];
	NSTextStorage *store = [[NSTextStorage alloc] initWithString:text];

	[store addLayoutManager:manager];
	[manager addTextContainer:container];
	*managerOut = manager;		/* borrowed from here on; the test releases them at the end */
	*containerOut = container;
	return store;
}

static NSColor *colour_at(NSBitmapImageRep *rep, int x, int y)
{
	return [rep colorAtX:x y:y];
}

/* Red and green are the two inks the probe tells apart: the store paints green, the temporary attribute paints red. */
static int count_ink(NSBitmapImageRep *rep, BOOL wantRed)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = colour_at(rep, x, y);

			if (c == nil || [c alphaComponent] < 0.4) {
				continue;
			}
			if (wantRed && [c redComponent] > 0.6 && [c greenComponent] < 0.4 && [c blueComponent] < 0.4) {
				count++;
			}
			if (!wantRed && [c greenComponent] > 0.4 && [c redComponent] < 0.4 && [c blueComponent] < 0.4) {
				count++;
			}
		}
	}
	return count;
}

static NSBitmapImageRep *draw_line(NSLayoutManager *manager, NSUInteger glyphCount)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[manager drawGlyphsForGlyphRange:NSMakeRange(0, glyphCount) atPoint:NSMakePoint(0.0, 0.0)];
	return rep;
}

/* A DELEGATE THAT CAN VETO THE TEMPORARY TABLE, and counts how often it was asked — so a probe can tell "declined"
 * from "never consulted". */
@interface AGTemporaryAttributeDelegate : NSObject
{
@public
	BOOL allow;
	NSInteger asked;
}
@end

@implementation AGTemporaryAttributeDelegate
- (BOOL)layoutManager:(NSLayoutManager *)layoutManager
	shouldUseTemporaryAttributes:(NSDictionary *)attrs
	forDrawingToScreen:(BOOL)toScreen
	atCharacterIndex:(NSUInteger)charIndex
	effectiveRange:(NSRangePointer)effectiveCharRange
{
	(void)layoutManager;
	(void)attrs;
	(void)toScreen;
	(void)charIndex;
	(void)effectiveCharRange;
	asked++;
	return allow;
}
@end

int main(void)
{
	@autoreleasepool {
		/* ============================================================================================
		 * 1. THE RUN TABLE: SET SPLITS, ADD MERGES, REMOVE DELETES A KEY.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"abcdefgh");
			NSColor *red = [NSColor redColor];
			NSColor *blue = [NSColor blueColor];
			NSColor *green = [NSColor greenColor];
			NSRange effective = NSMakeRange(0, 0);

			[manager setTemporaryAttributes:
				[NSDictionary dictionaryWithObject:red forKey:NSForegroundColorAttributeName]
				forCharacterRange:NSMakeRange(2, 4)];
			check([manager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:4
						 effectiveRange:&effective] == red,
			      "a temporary attribute is answered at an index inside its run");
			check(effective.location == 2 && effective.length == 4,
			      "and the effective range is the RUN, not the query");

			/* AN ADD IN THE MIDDLE SPLITS THE RUN AND KEEPS BOTH TAILS. */
			[manager addTemporaryAttribute:NSBackgroundColorAttributeName value:blue
					 forCharacterRange:NSMakeRange(3, 4)];
			check([[manager temporaryAttributesAtCharacterIndex:2 effectiveRange:&effective]
				  objectForKey:NSBackgroundColorAttributeName] == nil,
			      "the part of the run before the add keeps only its first attribute");
			check([manager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:4
						 effectiveRange:&effective] == blue,
			      "the added attribute is present where it was added");
			check([manager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:6
						 effectiveRange:&effective] == nil
			      && [manager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:6
						      effectiveRange:&effective] == blue,
			      "and the tail past the first run kept the added one alone");

			/* REMOVE TAKES ONE KEY OUT AND LEAVES THE OTHER. */
			[manager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(3, 2)];
			check([manager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:4
						 effectiveRange:NULL] == nil,
			      "removing one attribute leaves the range without it");
			check([manager temporaryAttribute:NSBackgroundColorAttributeName atCharacterIndex:4
						 effectiveRange:NULL] == blue,
			      "and leaves the other one in place");

			/* TWO ABUTTING RUNS WITH THE SAME VALUE ARE ONE RANGE. */
			[manager setTemporaryAttributes:
				[NSDictionary dictionaryWithObject:green forKey:NSForegroundColorAttributeName]
				forCharacterRange:NSMakeRange(0, 8)];
			[manager setTemporaryAttributes:
				[NSDictionary dictionaryWithObject:green forKey:NSForegroundColorAttributeName]
				forCharacterRange:NSMakeRange(4, 4)];
			check([manager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:5
						 effectiveRange:&effective] == green
			      && effective.location == 0 && effective.length == 8,
			      "two abutting runs with one value answer as ONE range");
			check([manager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:1
						 effectiveRange:&effective] == green,
			      "and the colour that was already there is what the table answers");

			/* LONGEST-EFFECTIVE-RANGE CLIPS TO THE CALLER'S LIMIT. */
			[manager temporaryAttribute:NSForegroundColorAttributeName atCharacterIndex:5
				 longestEffectiveRange:&effective inRange:NSMakeRange(2, 4)];
			check(effective.location == 2 && effective.length == 4,
			      "the longest-effective-range door clips the run to the caller's limit");

			/* AN Attribute PAST THE TEXT IS NOT STORED. */
			[manager setTemporaryAttributes:
				[NSDictionary dictionaryWithObject:red forKey:NSForegroundColorAttributeName]
				forCharacterRange:NSMakeRange(20, 3)];
			check([manager temporaryAttributesAtCharacterIndex:20 effectiveRange:NULL] == nil,
			      "a range past the end of the text stores nothing");

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 2. THE TABLE IS INK: a temporary foreground reaches the pixels, and removing it clears them.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"abcd");
			NSRange all = NSMakeRange(0, 4);
			NSBitmapImageRep *rep;

			[store addAttribute:NSForegroundColorAttributeName value:[NSColor greenColor] range:all];
			rep = draw_line(manager, 4);
			check(count_ink(rep, NO) > 0, "the store's own colour paints green ink");
			check(count_ink(rep, YES) == 0, "and no red is there before the temporary attribute");
			[rep release];

			[manager setTemporaryAttributes:
				[NSDictionary dictionaryWithObject:[NSColor redColor] forKey:NSForegroundColorAttributeName]
				forCharacterRange:NSMakeRange(1, 1)];
			rep = draw_line(manager, 4);
			check(count_ink(rep, YES) > 0, "a temporary red foreground reaches the pixels");
			[rep release];

			[manager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(1, 1)];
			rep = draw_line(manager, 4);
			check(count_ink(rep, YES) == 0, "and removing it takes the ink away again");
			[rep release];

			/* THE DELEGATE'S VETO: the table still holds the attribute, and the ink does not. */
			{
				AGTemporaryAttributeDelegate *delegate = [[AGTemporaryAttributeDelegate alloc] init];

				[manager setTemporaryAttributes:
					[NSDictionary dictionaryWithObject:[NSColor redColor]
								    forKey:NSForegroundColorAttributeName]
					forCharacterRange:NSMakeRange(0, 4)];
				delegate->allow = NO;
				[manager setDelegate:delegate];
				rep = draw_line(manager, 4);
				check(count_ink(rep, YES) == 0, "a delegate that declines keeps the temporary table out of the ink");
				check(delegate->asked > 0, "and it was actually asked, rather than silently ignored");
				[rep release];

				delegate->allow = YES;
				rep = draw_line(manager, 4);
				check(count_ink(rep, YES) > 0, "a delegate that allows it paints the temporary colour");
				[rep release];

				[manager setDelegate:nil];
				[delegate release];
			}

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 3. THE RECT ARRAYS: one per line, the line's height, and the caret's zero width.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"one\ntwo");
			NSRect *rects;
			NSUInteger count = 0;
			CGFloat lineHeight;

			check([manager numberOfGlyphs] == 7, "the store lays out seven glyphs");
			lineHeight = [manager cg_lineHeight];

			rects = [manager rectArrayForGlyphRange:NSMakeRange(0, 7) withinSelectedGlyphRange:NSMakeRange(0, 7)
						inTextContainer:container rectCount:&count];
			check(rects != NULL && count == 2, "a two-line range is two rectangles");
			if (rects != NULL && count == 2) {
				check(close_enough(NSHeight(rects[0]), lineHeight) && close_enough(NSHeight(rects[1]), lineHeight),
				      "each one is a line's height");
				check(rects[1].origin.y > rects[0].origin.y, "and the second line's is below the first's");
				check(NSWidth(rects[0]) > 0.0 && NSWidth(rects[1]) > 0.0, "each has the width of the glyphs on it");
			}

			/* THE CHARACTER SPELLING IS THE SAME ANSWER. */
			{
				NSUInteger charCount = 0;
				NSRect *byChar = [manager rectArrayForCharacterRange:NSMakeRange(0, 7)
						    withinSelectedCharacterRange:NSMakeRange(0, 7)
								 inTextContainer:container rectCount:&charCount];

				check(byChar != NULL && charCount == 2 && NSEqualRects(byChar[0], rects[0])
					      && NSEqualRects(byChar[1], rects[1]),
				      "the character range spelling agrees with the glyph one");
			}

			/* A CARET IS ONE RECTANGLE OF NO WIDTH, on the line it sits in. */
			rects = [manager rectArrayForGlyphRange:NSMakeRange(2, 0) withinSelectedGlyphRange:NSMakeRange(2, 0)
						inTextContainer:container rectCount:&count];
			check(rects != NULL && count == 1 && close_enough(NSWidth(rects[0]), 0.0)
				      && close_enough(NSHeight(rects[0]), lineHeight),
			      "a caret is one rectangle of no width and a line's height");

			/* A CONTAINER THE MANAGER DOES NOT OWN HAS NO RECTS. */
			{
				NSTextContainer *stranger = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(10.0, 10.0)];
				NSUInteger strangerCount = 99;

				rects = [manager rectArrayForGlyphRange:NSMakeRange(0, 7)
						 withinSelectedGlyphRange:NSMakeRange(0, 7)
							  inTextContainer:stranger rectCount:&strangerCount];
				check(rects == NULL && strangerCount == 0,
				      "a container this manager does not own answers no rectangles");
				[stranger release];
			}

			[store release];
			[manager release];
			[container release];
		}

		/* ============================================================================================
		 * 4. THE EXTRA LINE, WHICH THIS TIER'S BREAKER DOES NOT PRODUCE — asserted as the state that is
		 *    true, and the empty document, whose single fragment IS the zero-glyph one.
		 * ========================================================================================== */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"one\n");
			NSRect *rects;
			NSUInteger count = 0;
			NSUInteger glyphs = [manager numberOfGlyphs];

			/* THE DOCUMENT SAYS TWO LINES AND THE LAYOUT HAS ONE FRAGMENT: the newline's glyph belongs to the line
			 * it ends, so a selection that reaches the end and one that stops short answer the same rects. That is
			 * the `withinSelected…` parameter with nothing to decide, and the header says so. */
			rects = [manager rectArrayForGlyphRange:NSMakeRange(0, glyphs) withinSelectedGlyphRange:NSMakeRange(0, 0)
						inTextContainer:container rectCount:&count];
			check(rects != NULL && count == 1, "a trailing newline leaves one line fragment, not two");
			rects = [manager rectArrayForGlyphRange:NSMakeRange(0, glyphs)
					withinSelectedGlyphRange:NSMakeRange(0, glyphs)
					    inTextContainer:container rectCount:&count];
			check(rects != NULL && count == 1,
			      "so a selection that covers the end answers the same rectangles as one that does not");

			[store release];
			[manager release];
			[container release];
		}

		/* AND THE EMPTY DOCUMENT IS THE ONE ZERO-GLYPH FRAGMENT: a caret at its origin, of no width. */
		{
			NSLayoutManager *manager = nil;
			NSTextContainer *container = nil;
			NSTextStorage *store = new_store(&manager, &container, @"");
			NSRect *rects;
			NSUInteger count = 0;

			rects = [manager rectArrayForGlyphRange:NSMakeRange(0, 0) withinSelectedGlyphRange:NSMakeRange(0, 0)
						inTextContainer:container rectCount:&count];
			check(rects != NULL && count == 1 && close_enough(NSWidth(rects[0]), 0.0),
			      "an empty document's caret is one rectangle of no width");

			[store release];
			[manager release];
			[container release];
		}

		if (failures == 0) {
			printf("text_temporary_attributes: all checks passed\n");
			return 0;
		}
		printf("text_temporary_attributes: FAILURES\n");
		return 1;
	}
}
