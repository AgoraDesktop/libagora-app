/*
 * text_container.m — A REGION, THE FOUR FACTS ABOUT IT, AND THE ONE COMPUTATION THAT READS THEM.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CONTAINER'S WHOLE CLAIM IS GEOMETRY, SO THE PROBE IS EXACT RECTANGLES.** A proposed fragment inside the
 * region answers itself; one that runs over an edge answers the part that fits; one that misses entirely answers
 * nothing unless the caller said the rectangle may be CARRIED, and then it answers the nearest place it could go. The
 * DEFAULTS are checked separately — a ten-point fragment padding, both tracking flags off, and the promise that this
 * is a plain rectangle — because those are what a layout manager would read before it asks for anything.
 */
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSTextView.h>
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

static int rect_is(NSRect r, CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
	return r.origin.x == x && r.origin.y == y && r.size.width == w && r.size.height == h;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(300.0, 200.0)];
	NSRect remaining;

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE REGION IS WHAT IT WAS MADE WITH, AND THE DEFAULTS ARE APPLE'S OWN.** */
	check([container containerSize].width == 300.0 && [container containerSize].height == 200.0,
	      "the container's size is the one it was made with");
	check([container lineFragmentPadding] == 10.0, "its line-fragment padding is ten points");
	check(![container widthTracksTextView] && ![container heightTracksTextView],
	      "and it tracks neither dimension of a view until it is told to");
	check([container isSimpleRectangularTextContainer],
	      "and it says it is a SIMPLE RECTANGLE, which is the promise the geometry is written against");
	check([container textView] == nil, "a container with no view answers nil rather than a stale pointer");

	/* 2. **AND THE FOUR FACTS ROUND-TRIP.** */
	[container setContainerSize:NSMakeSize(400.0, 100.0)];
	check([container containerSize].width == 400.0, "setting the container size answers it back");
	[container setLineFragmentPadding:4.0];
	check([container lineFragmentPadding] == 4.0, "so does the padding");
	[container setWidthTracksTextView:YES];
	[container setHeightTracksTextView:YES];
	check([container widthTracksTextView] && [container heightTracksTextView], "and so do the two tracking flags");
	{
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 100.0)];

		[container setTextView:view];
		check([container textView] == view, "and the view it is drawn in");
		[view release];
	}

	/* 3. **THE HIT TEST IS THE REGION.** */
	check([container containsPoint:NSMakePoint(10.0, 10.0)], "a point inside the region is contained");
	check(![container containsPoint:NSMakePoint(500.0, 10.0)], "and one past its right edge is not");
	check(![container containsPoint:NSMakePoint(-1.0, 10.0)], "nor one before it");

	/* **AND BACK TO A REGION THE FRAGMENTS CAN BE REASONED ABOUT.** */
	[container setContainerSize:NSMakeSize(300.0, 200.0)];

	/* 4. **A FRAGMENT INSIDE THE REGION IS ITSELF, AND NOTHING IS LEFT OVER.** A rectangle has no holes, so the
	 * `remainingRect` a typesetter is handed is empty — which is a statement about a SIMPLE container rather than an
	 * oversight. */
	remaining = NSMakeRect(1.0, 2.0, 3.0, 4.0);
	{
		NSRect fragment = [container lineFragmentRectForProposedRect:NSMakeRect(10.0, 10.0, 100.0, 20.0)
			sweepDirection:NSLineSweepLeft movementDirection:NSLineDoesntMove remainingRect:&remaining];

		check(rect_is(fragment, 10.0, 10.0, 100.0, 20.0), "a proposed fragment inside the region answers itself");
		check(rect_is(remaining, 0.0, 0.0, 0.0, 0.0), "with an EMPTY remaining rect — a rectangle has no holes");
	}

	/* 5. **AND ONE THAT RUNS OVER AN EDGE IS CLIPPED TO THE REGION.** The returned fragment is the part that FITS, and
	 * the sweep direction changes none of it, because a rectangle has no edges to start from. */
	{
		NSRect fragment = [container lineFragmentRectForProposedRect:NSMakeRect(250.0, 10.0, 100.0, 20.0)
			sweepDirection:NSLineSweepRight movementDirection:NSLineDoesntMove remainingRect:&remaining];

		printf("  (note: a fragment running 50 points past the right edge came back %g wide)\n",
		       (double)fragment.size.width);
		check(rect_is(fragment, 250.0, 10.0, 50.0, 20.0), "a fragment over the right edge is clipped to the region");
	}

	/* 6. **AND ONE THAT MISSES ENTIRELY ANSWERS NOTHING UNLESS IT MAY BE CARRIED.** `NSLineDoesntMove` is the refusal
	 * to try, and the four directions are the nearest edge on that side — which is the difference between "there is no
	 * room" and "there is room there". */
	{
		NSRect miss = NSMakeRect(400.0, 10.0, 100.0, 20.0);
		NSRect nothing = [container lineFragmentRectForProposedRect:miss
			sweepDirection:NSLineSweepLeft movementDirection:NSLineDoesntMove remainingRect:NULL];
		NSRect carried = [container lineFragmentRectForProposedRect:miss
			sweepDirection:NSLineSweepLeft movementDirection:NSLineMovesLeft remainingRect:NULL];

		printf("  (note: a fragment entirely past the region gave (%g,%g %gx%g) unmoved and (%g,%g %gx%g) carried)\n",
		       (double)nothing.origin.x, (double)nothing.origin.y, (double)nothing.size.width, (double)nothing.size.height,
		       (double)carried.origin.x, (double)carried.origin.y, (double)carried.size.width, (double)carried.size.height);
		check(NSIsEmptyRect(nothing), "a fragment entirely outside the region is EMPTY when the line may not move");
		check(rect_is(carried, 200.0, 10.0, 100.0, 20.0),
		      "and is CARRIED to the region's near edge when it may move left");
	}

	/* 7. **AND THE VERTICAL DIRECTIONS USE THE COORDINATES THE VIEW USES, WHICH ARE FLIPPED.** A text view's y grows
	 * DOWNWARD, so a fragment ABOVE the region is at a NEGATIVE y and `NSLineMovesDown` is what carries it back. */
	{
		NSRect carried = [container lineFragmentRectForProposedRect:NSMakeRect(10.0, -50.0, 100.0, 20.0)
			sweepDirection:NSLineSweepDown movementDirection:NSLineMovesDown remainingRect:NULL];

		check(rect_is(carried, 10.0, 0.0, 100.0, 20.0),
		      "a fragment above the region is carried DOWN to its top edge — y grows downward in a text view");
	}

	/* 8. **A SUBCLASS THAT IS NOT A RECTANGLE SAYS SO, AND THAT IS THE SEAM.** The answer is a promise a layout
	 * manager reads before it takes the cheap route, so the probe checks that the CLASS makes it — an override is what
	 * changes it, and this class does not pretend to a shape it has not got. */
	check([container isSimpleRectangularTextContainer],
	      "the class itself always answers YES; a shape is a SUBCLASS's declaration");

	[container release];
	[pool release];
	printf("text_container: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
