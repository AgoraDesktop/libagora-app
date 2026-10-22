/*
 * text_container_region.m — A SHAPED CONTAINER'S REGION IS WHAT THE LAYOUT USES.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **`-lineFragmentRectForProposedRect:…` IS THE CONTAINER'S WHOLE JOB**, and until this slice the manager never
 * asked it: every line was the container's width minus its padding, so a subclass that returned a narrower, offset
 * or split region changed nothing. Now a NON-SIMPLE container (`-isSimpleRectangularTextContainer` answers NO) is
 * asked for each line's band, and the answer's x and width are what the typesetter breaks to and what the fragment
 * records.
 *
 * WHAT IS MEASURED:
 *
 *   1. A PLAIN container is unchanged: the first fragment is the whole width at x=0.
 *   2. An INSET first line — x=40, width=120 — makes the first fragment start at 40, measure 120, and break EARLIER
 *      than the same text in the plain container.
 *   3. A SPLIT line — a region with a hole, where the container answers a left part and a REMAINING right part —
 *      makes TWO fragments at the SAME baseline whose ranges are contiguous, which is one logical line set in two
 *      places.
 *   4. And a point in the right part HIT-TESTS to the right part's characters, not to the end of the left one, which
 *      is why the hit test now compares x among fragments that share a band.
 */
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

#define W 300.0
#define PAD 10.0

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* **A CONTAINER WHOSE REGION HAS A SHAPE.** Mode 0 insets the first line; mode 1 puts a hole in it and hands the
 * right-hand part back as the remaining rect. Every other line is the full proposed band, so the probe can tell the
 * shaped line from its neighbours without guessing at the font's line height. */
@interface AGShapedContainer : NSTextContainer
{
@public
	int mode;
}
@end

@implementation AGShapedContainer

- (BOOL)isSimpleRectangularTextContainer
{
	return NO;
}

- (NSRect)lineFragmentRectForProposedRect:(NSRect)proposedRect
			   sweepDirection:(NSLineSweepDirection)sweepDirection
		       movementDirection:(NSLineMovementDirection)movementDirection
			    remainingRect:(NSRect *)remainingRect
{
	NSRect fragment = proposedRect;

	(void)sweepDirection;
	(void)movementDirection;
	if (remainingRect != NULL) {
		*remainingRect = NSZeroRect;
	}
	if (proposedRect.origin.y > 1.0 || proposedRect.origin.x > 1.0) {
		return fragment;	/* every line after the first, and a remaining part already right of the hole */
	}
	if (mode == 0) {
		fragment.origin.x += 40.0;
		fragment.size.width = 120.0;
	} else {
		fragment.size.width = 80.0;
		if (remainingRect != NULL) {
			*remainingRect = NSMakeRect(160.0, proposedRect.origin.y, 140.0, proposedRect.size.height);
		}
	}
	return fragment;
}

@end

static NSTextStorage *make_store(void)
{
	return [[NSTextStorage alloc] initWithString:
		@"alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron"];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextStorage *plainStore = make_store();
	NSTextStorage *stepStore = make_store();
	NSTextStorage *holeStore = make_store();
	NSLayoutManager *plainManager = [[NSLayoutManager alloc] init];
	NSLayoutManager *stepManager = [[NSLayoutManager alloc] init];
	NSLayoutManager *holeManager = [[NSLayoutManager alloc] init];
	NSTextContainer *plain = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(W, 0.0)];
	AGShapedContainer *step = [[AGShapedContainer alloc] initWithContainerSize:NSMakeSize(W, 0.0)];
	AGShapedContainer *hole = [[AGShapedContainer alloc] initWithContainerSize:NSMakeSize(W, 0.0)];
	NSRange plainFirst, stepFirst;

	setvbuf(stdout, NULL, _IONBF, 0);
	[plain setLineFragmentPadding:PAD];
	[step setLineFragmentPadding:PAD];
	[hole setLineFragmentPadding:PAD];
	step->mode = 0;
	hole->mode = 1;
	[plainStore addLayoutManager:plainManager];
	[plainManager addTextContainer:plain];
	[stepStore addLayoutManager:stepManager];
	[stepManager addTextContainer:step];
	[holeStore addLayoutManager:holeManager];
	[holeManager addTextContainer:hole];

	/* 1. **THE PLAIN CONTAINER IS THE REFERENCE, AND IT IS UNCHANGED.** */
	plainFirst = [plainManager cg_lineFragmentRangeAtIndex:0 inTextContainer:plain];
	{
		NSRect rect = [plainManager lineFragmentRectForGlyphAtIndex:plainFirst.location effectiveRange:NULL];
		NSRect used = [plainManager lineFragmentUsedRectForGlyphAtIndex:plainFirst.location effectiveRange:NULL];

		printf("  (plain: first line x=%.1f w=%.1f, %lu character(s), used x=%.1f)\n",
		       (double)rect.origin.x, (double)rect.size.width, (unsigned long)plainFirst.length,
		       (double)used.origin.x);
		check([plain isSimpleRectangularTextContainer], "the plain container says it is a rectangle");
		check(rect.origin.x == 0.0 && rect.size.width == W, "and its first fragment is the whole width at x=0");
		check(used.origin.x == PAD, "with its text inset by the fragment padding");
	}

	/* 2. **THE INSET FIRST LINE IS THE REGION'S, NOT THE CONTAINER'S WIDTH.** */
	stepFirst = [stepManager cg_lineFragmentRangeAtIndex:0 inTextContainer:step];
	{
		NSRect rect = [stepManager lineFragmentRectForGlyphAtIndex:stepFirst.location effectiveRange:NULL];
		NSRect used = [stepManager lineFragmentUsedRectForGlyphAtIndex:stepFirst.location effectiveRange:NULL];

		printf("  (step: first line x=%.1f w=%.1f, %lu character(s), used x=%.1f)\n",
		       (double)rect.origin.x, (double)rect.size.width, (unsigned long)stepFirst.length,
		       (double)used.origin.x);
		check(![step isSimpleRectangularTextContainer], "the shaped container says it is NOT a rectangle");
		check(rect.origin.x == 40.0 && rect.size.width == 120.0,
		      "the first fragment is the subrect the container answered");
		check(used.origin.x == 40.0 + PAD, "and its text starts at that x inset by the padding");
		check(stepFirst.length < plainFirst.length,
		      "so the line breaks EARLIER than the same text in the plain container");
	}
	{
		NSRange next = [stepManager cg_lineFragmentRangeAtIndex:1 inTextContainer:step];
		NSRect rect = [stepManager lineFragmentRectForGlyphAtIndex:next.location effectiveRange:NULL];

		check(next.location == stepFirst.location + stepFirst.length,
		      "the rest of the first line wraps contiguously");
		check(rect.origin.x == 0.0 && rect.size.width == W,
		      "and the SECOND line is the full band, because the shape only narrowed the first");
	}

	/* 3. **A LINE WITH A HOLE IS TWO FRAGMENTS AT ONE BASELINE.** */
	{
		NSRange left = [holeManager cg_lineFragmentRangeAtIndex:0 inTextContainer:hole];
		NSRange right = [holeManager cg_lineFragmentRangeAtIndex:1 inTextContainer:hole];
		NSRect leftRect = [holeManager lineFragmentRectForGlyphAtIndex:left.location effectiveRange:NULL];
		NSRect rightRect = [holeManager lineFragmentRectForGlyphAtIndex:right.location effectiveRange:NULL];
		NSRect leftUsed = [holeManager lineFragmentUsedRectForGlyphAtIndex:left.location effectiveRange:NULL];
		CGFloat leftBaseline = [holeManager cg_baselineForGlyphAtIndex:left.location];
		CGFloat rightBaseline = [holeManager cg_baselineForGlyphAtIndex:right.location];
		CGFloat rightOffset = [holeManager cg_offsetForGlyphAtIndex:right.location];

		printf("  (hole: left (%lu,%lu) at x=%.1f w=%.1f, right (%lu,%lu) at x=%.1f w=%.1f)\n",
		       (unsigned long)left.location, (unsigned long)left.length,
		       (double)leftRect.origin.x, (double)leftRect.size.width,
		       (unsigned long)right.location, (unsigned long)right.length,
		       (double)rightRect.origin.x, (double)rightRect.size.width);
		check(left.length > 0 && right.length > 0, "the line is set in TWO parts");
		check(right.location == left.location + left.length,
		      "and the right part continues the left one with no gap in the text");
		check(leftRect.origin.x == 0.0 && leftRect.size.width == 80.0,
		      "the left part is the container's left subrect");
		check(rightRect.origin.x == 160.0 && rightRect.size.width == 140.0,
		      "and the right part is the remaining rect the container handed back");
		check(leftBaseline == rightBaseline, "both parts sit on the SAME baseline — they are one line");
		check(leftUsed.origin.x == PAD && rightOffset == 160.0 + PAD,
		      "each part's text is inset from its own subrect");
	}

	/* 4. **AND THE HIT TEST CHOOSES BY X AMONG THE FRAGMENTS THAT SHARE THE BAND.** */
	{
		NSRange left = [holeManager cg_lineFragmentRangeAtIndex:0 inTextContainer:hole];
		NSRange right = [holeManager cg_lineFragmentRangeAtIndex:1 inTextContainer:hole];
		CGFloat baseline = [holeManager cg_baselineForGlyphAtIndex:left.location];
		CGFloat y = baseline - 4.0;
		NSUInteger inLeft = [holeManager cg_glyphIndexForPoint:NSMakePoint(30.0, y) inTextContainer:hole];
		NSUInteger inRight = [holeManager cg_glyphIndexForPoint:NSMakePoint(200.0, y) inTextContainer:hole];

		printf("  (hit test on the split line: x=30 -> %lu, x=200 -> %lu; right starts at %lu)\n",
		       (unsigned long)inLeft, (unsigned long)inRight, (unsigned long)right.location);
		check(inLeft >= left.location && inLeft <= left.location + left.length,
		      "a point in the LEFT part hit-tests into the left part");
		check(inRight >= right.location && inRight <= right.location + right.length,
		      "and a point in the RIGHT part hit-tests into the right part, not the left one's end");
	}

	[hole release];
	[step release];
	[plain release];
	[holeManager release];
	[stepManager release];
	[plainManager release];
	[holeStore release];
	[stepStore release];
	[plainStore release];
	[pool release];
	printf("text_container_region: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
