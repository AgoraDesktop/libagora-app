/*
 * scroller — a fraction into a knob, a point into a part, and a drag back into a fraction.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **A SCROLLER IS TWO INVERSE ARITHMETICS, AND THIS PROBE IS BOTH.** The first turns the value pair into geometry:
 * `-rectForPart:` places the knob from `-floatValue` and `-knobProportion`. The second turns a point back into a
 * part: `-testPart:` says which place a press landed on, and `-hitPart` is what the action then reads. If the two
 * disagree about where the knob is, a press and a painting mean different things — which is the failure a scroller
 * is uniquely good at hiding, because the two are read at different moments.
 *
 * WHAT IS ASSERTED, each one a behaviour of the new slice:
 *
 *   1. The class metric — a scroller's width is 15 points regular and 11 small or mini.
 *   2. A scroller makes a SCROLLER CELL and is FLIPPED, because the whole geometry counts y downward.
 *   3. The value pair ROUND-TRIPS and CLAMPS, in both numbers, NAN included.
 *   4. `-rectForPart:` places the knob, splits the slot into the two pages, and puts a line button at each end.
 *   5. `-testPart:` is the same rectangles read backwards — and the DEcrement end is the TOP, which is the one claim
 *      the flip is responsible for.
 *   6. A DRAG moves the knob by the hand's own delta — the point that was grabbed stays under the pointer — and the
 *      two ends CLAMP.
 *   7. The knob has a FLOOR: a proportion too small to see still draws a grabbable square.
 *   8. `-NSScrollerArrowsNone` changes the GEOMETRY, not just the ink: the line parts vanish and the slot is the
 *      whole frame.
 *   9. The face puts INK in the arrow buttons and in the knob.
 *
 * Everything is offscreen: a scroller is a view with a cell, and this is its arithmetic and its ink with no scroll
 * view, no document and no compositor anywhere near it.
 */
#import <AppKit/NSScroller.h>
#import <AppKit/NSScrollerCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int near(double a, double b)
{
	return fabs(a - b) < 0.001;
}

static int eqr(NSRect a, NSRect b)
{
	return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) &&
	       near(a.size.width, b.size.width) && near(a.size.height, b.size.height);
}

static void note_rect(const char *what, NSRect r)
{
	printf("  (note: %s = (%.1f, %.1f) %.1f x %.1f)\n", what,
	       (double)r.origin.x, (double)r.origin.y, (double)r.size.width, (double)r.size.height);
}

/* INK IN A BOX, over a bitmap the probe has filled with white. The row index is converted because a bitmap's rows
 * count from the TOP and the drawing's from the bottom — the off-by-a-flip the slider probe also records. */
static int ink_in(NSBitmapImageRep *rep, int high, int x0, int y0, int x1, int y1, double under)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:(high - 1 - y)];

			if (c != nil && [c redComponent] < under) {
				n++;
			}
		}
	}
	return n;
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		/* A VERTICAL SCROLLER: 15 wide by 100 tall, which is the metric width by a track. */
		NSRect vframe = NSMakeRect(0.0, 0.0, 15.0, 100.0);
		NSScroller *s = [[NSScroller alloc] initWithFrame:vframe];
		NSScrollerCell *cell = (NSScrollerCell *)[s cell];

		/* 1. THE CLASS METRIC. */
		check(near([NSScroller scrollerWidth], 15.0), "a scroller is 15 points wide at the regular size");
		check(near([NSScroller scrollerWidthForControlSize:NSSmallControlSize], 11.0),
		      "11 at the small size");
		check(near([NSScroller scrollerWidthForControlSize:NSMiniControlSize], 11.0),
		      "and 11 at mini, which is the era's other width");

		/* 2. THE CELL AND THE FLIP. */
		check([cell isKindOfClass:[NSScrollerCell class]], "a scroller makes a SCROLLER CELL");
		check([s isFlipped], "and it is FLIPPED, which is what puts the decrement end at the top");

		/* 3. THE VALUE PAIR: round trip, then every clamp. */
		[s setFloatValue:0.25 knobProportion:0.5];
		check(near([s floatValue], 0.25) && near([s knobProportion], 0.5),
		      "`-setFloatValue:knobProportion:` round-trips through the control");
		[s setFloatValue:2.0 knobProportion:5.0];
		check(near([s floatValue], 1.0) && near([s knobProportion], 1.0),
		      "a value and a proportion past 1 clamp to 1");
		[s setFloatValue:-3.0 knobProportion:-3.0];
		check(near([s floatValue], 0.0) && near([s knobProportion], 0.0),
		      "and ones below 0 clamp to 0");
		{
			double nan_value = NAN;

			[s setFloatValue:(CGFloat)nan_value knobProportion:(CGFloat)nan_value];
			check(near([s floatValue], 0.0) && near([s knobProportion], 0.0),
			      "and a NAN is caught rather than slipping through the comparisons unclamped");
		}

		/* 4. **THE GEOMETRY.** The slot is the frame less a 15-point arrow at each end — y=15 to y=85 — and with the
		 * knob at the top of a 35-point travel the knob is (0, 15) by 15x35. */
		[s setFloatValue:0.0 knobProportion:0.5];
		note_rect("slot", [s rectForPart:NSScrollerKnobSlot]);
		note_rect("knob at 0", [s rectForPart:NSScrollerKnob]);
		check(eqr([s rectForPart:NSScrollerKnobSlot], NSMakeRect(0.0, 15.0, 15.0, 70.0)),
		      "the slot is the frame less an arrow at each end");
		check(eqr([s rectForPart:NSScrollerKnob], NSMakeRect(0.0, 15.0, 15.0, 35.0)),
		      "half a track of proportion puts a 35-point knob at the top of the slot");
		check(eqr([s rectForPart:NSScrollerDecrementLine], NSMakeRect(0.0, 0.0, 15.0, 15.0)),
		      "the DECREMENT line button is the TOP of a vertical scroller");
		check(eqr([s rectForPart:NSScrollerIncrementLine], NSMakeRect(0.0, 85.0, 15.0, 15.0)),
		      "and the INCREMENT one is the bottom");
		check(eqr([s rectForPart:NSScrollerDecrementPage], NSMakeRect(0.0, 15.0, 15.0, 0.0)),
		      "with the knob at the top there is no page above it");
		check(eqr([s rectForPart:NSScrollerIncrementPage], NSMakeRect(0.0, 50.0, 15.0, 35.0)),
		      "and the whole rest of the slot is the increment page");

		[s setFloatValue:1.0 knobProportion:0.5];
		check(eqr([s rectForPart:NSScrollerKnob], NSMakeRect(0.0, 50.0, 15.0, 35.0)),
		      "at 1 the knob sits at the far end of its own travel, with the slot's edge exactly where it ends");
		check(eqr([s rectForPart:NSScrollerDecrementPage], NSMakeRect(0.0, 15.0, 15.0, 35.0)),
		      "and the page above it is everything the knob has left behind");

		/* 5. **THE PART A POINT IS IN, WHICH IS THE SAME RECTANGLES READ BACKWARDS.** */
		[s setFloatValue:0.5 knobProportion:0.5];
		check([s testPart:NSMakePoint(7.0, 7.0)] == NSScrollerDecrementLine,
		      "a point near the top is the decrement LINE");
		check([s testPart:NSMakePoint(7.0, 92.0)] == NSScrollerIncrementLine,
		      "a point near the bottom is the increment LINE");
		check([s testPart:NSMakePoint(7.0, 40.0)] == NSScrollerKnob,
		      "a point on the knob is the KNOB");
		check([s testPart:NSMakePoint(7.0, 20.0)] == NSScrollerDecrementPage,
		      "a point between the top arrow and the knob is the decrement PAGE");
		check([s testPart:NSMakePoint(7.0, 80.0)] == NSScrollerIncrementPage,
		      "and one below the knob is the increment PAGE");
		check([s testPart:NSMakePoint(200.0, 200.0)] == NSScrollerNoPart,
		      "and a point off the scroller is no part at all");

		/* 6. **THE DRAG, WHICH KEEPS THE GRABBED POINT UNDER THE HAND.** The press is at y=40 with the knob at y=32.5,
		 * so the grab is 7.5 points into it. Moving the pointer to y=50 moves the knob's near edge to 42.5, which is
		 * (42.5 - 15) / 35 of the travel — and the two ends clamp. */
		[s setFloatValue:0.5 knobProportion:0.5];
		{
			BOOL answered = [cell startTrackingAt:NSMakePoint(7.0, 40.0) inView:s];

			check(answered && [s hitPart] == NSScrollerKnob,
			      "`-startTrackingAt:inView:` answers YES and the press is remembered as the KNOB");
			[cell continueTracking:NSMakePoint(7.0, 40.0) at:NSMakePoint(7.0, 50.0) inView:s];
			printf("  (note: dragging the grab from y=40 to y=50 took floatValue to %.4f)\n",
			       (double)[s floatValue]);
			check(near([s floatValue], 27.5 / 35.0),
			      "and dragging it 10 points moves the value by 10/35 of the travel, not to the pointer");
			[cell continueTracking:NSMakePoint(7.0, 50.0) at:NSMakePoint(7.0, 5.0) inView:s];
			check(near([s floatValue], 0.0), "a drag past the top clamps to 0");
			[cell continueTracking:NSMakePoint(7.0, 5.0) at:NSMakePoint(7.0, 400.0) inView:s];
			check(near([s floatValue], 1.0), "and one past the bottom clamps to 1");
		}
		{
			/* AND A PRESS THAT IS NOT THE KNOB REPORTS ITS PART AND MOVES NOTHING — the scroll view is what scrolls. */
			[s setFloatValue:0.5 knobProportion:0.5];
			[cell startTrackingAt:NSMakePoint(7.0, 80.0) inView:s];
			check([s hitPart] == NSScrollerIncrementPage && near([s floatValue], 0.5),
			      "a press on a page reports the PAGE and does not move the knob itself");
		}

		/* 7. **THE KNOB'S FLOOR.** A proportion of one percent of a 70-point slot is 0.7 points; the floor makes it a
		 * square instead, so there is something to hold. */
		{
			NSRect k;

			[s setFloatValue:0.0 knobProportion:0.01];
			k = [s rectForPart:NSScrollerKnob];
			printf("  (note: a 1%% proportion drew a %.1f-point knob, against a 15-point scroller)\n",
			       (double)NSHeight(k));
			check(near(NSHeight(k), 15.0),
			      "a proportion too small to see still draws a knob as long as the scroller is THICK");
		}

		/* 8. **NO ARROWS IS A GEOMETRY CHANGE, NOT AN INK ONE.** */
		[s setArrowsPosition:NSScrollerArrowsNone];
		check([s arrowsPosition] == NSScrollerArrowsNone, "`-setArrowsPosition:` round-trips");
		[s setFloatValue:0.5 knobProportion:0.5];
		check(eqr([s rectForPart:NSScrollerDecrementLine], NSZeroRect),
		      "with no arrows the line parts have no rectangle");
		check(eqr([s rectForPart:NSScrollerKnobSlot], NSMakeRect(0.0, 0.0, 15.0, 100.0)),
		      "and the slot is the WHOLE frame rather than the middle of it");
		check([s testPart:NSMakePoint(7.0, 7.0)] == NSScrollerDecrementPage,
		      "so a point that was a line button is now a page above the knob");
		[s setArrowsPosition:NSScrollerArrowsDefaultSetting];

		/* 9. **THE OTHER ORIENTATION.** A horizontal scroller is a wide, short frame; the decrement end is now the
		 * LEFT, which is the same flip read the other way. */
		{
			NSScroller *h = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 15.0)];

			[h setFloatValue:0.5 knobProportion:0.5];
			check(eqr([h rectForPart:NSScrollerKnobSlot], NSMakeRect(15.0, 0.0, 70.0, 15.0)),
			      "a horizontal scroller's slot runs between its two arrow buttons");
			check(eqr([h rectForPart:NSScrollerKnob], NSMakeRect(32.5, 0.0, 35.0, 15.0)),
			      "with the knob placed along x");
			check(eqr([h rectForPart:NSScrollerDecrementLine], NSMakeRect(0.0, 0.0, 15.0, 15.0)),
			      "the decrement line is the LEFT button");
			check([h testPart:NSMakePoint(50.0, 7.0)] == NSScrollerKnob, "and a point on the knob is the knob");
			check([h testPart:NSMakePoint(20.0, 7.0)] == NSScrollerDecrementPage,
			      "a point left of the knob is the decrement page");
			check([h testPart:NSMakePoint(80.0, 7.0)] == NSScrollerIncrementPage,
			      "and one right of it the increment page");
			[h release];
		}

		/* 10. **AND THE INK.** The face has to put marks in the two arrow buttons and in the knob; a face that drew
		 * only the slot would pass every geometry check above. */
		{
			NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:15
				pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:15 * 4 bitsPerPixel:32];
			NSRect k;

			[s setArrowsPosition:NSScrollerArrowsDefaultSetting];
			[s setFloatValue:0.0 knobProportion:0.5];
			k = [s rectForPart:NSScrollerKnob];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:vframe] fill];
			[s drawRect:vframe];
			printf("  (note: ink — %d in the decrement button, %d in the knob, %d in the increment button)\n",
			       ink_in(rep, 100, 0, 0, 15, 15, 0.85),
			       ink_in(rep, 100, (int)NSMinX(k), (int)NSMinY(k), (int)NSMaxX(k), (int)NSMaxY(k), 0.97),
			       ink_in(rep, 100, 0, 85, 15, 100, 0.85));
			check(ink_in(rep, 100, 0, 0, 15, 15, 0.85) > 0, "the decrement arrow is DRAWN");
			check(ink_in(rep, 100, 0, 85, 15, 100, 0.85) > 0, "and so is the increment arrow");
			check(ink_in(rep, 100, (int)NSMinX(k), (int)NSMinY(k), (int)NSMaxX(k), (int)NSMaxY(k), 0.97) > 0,
			      "and the knob is drawn where the value says it is");
			[rep release];
		}

		/* 10b. **AND THE ARROW IS CRISP *AND* THE TWO ARE EXACT MIRRORS, WHICH A PATH CAN BE WHEN IT IS FILLED HARD.**
		 * The glyph is a PATH — a triangle six points across and four tall, which is the sample's proportion and is WIDER
		 * THAN IT IS TALL — and it is filled with ANTIALIASING OFF. That is the pair of things being held here.
		 *
		 * IT WAS RASTERIZED A POINT AT A TIME FOR AS LONG AS THE FILL COULD NOT DRAW A TRIANGLE AT ALL: MEASURED then, a
		 * 60x40 triangle came out 30 points across its base and a 6x4 one came out a 3x2 bar, differently wrong at each
		 * end of one bar. That is fixed in libagora-drawing (`cg_sweep` filled every trapezoid's top edge at the width of
		 * its band's MIDDLE), so the shape is back, and the two claims below are the ones a person can still see: the
		 * arrows cover the SAME number of points, and there is NO half-covered point anywhere in either — which is what
		 * turning antialiasing off buys, and what a blended triangle this small cannot give, since it is almost all edge.
		 *
		 * THE MEASUREMENT IS THE GLYPH'S OWN BOX, not the whole button: the button is a rounded rectangle whose corners
		 * are curves and the knob's 1-point stroke antialiases into y=14, so neither is the arrow — counting them in would
		 * make the two windows differ by the button's corners rather than by the glyph. */
		{
			NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:15
				pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:15 * 4 bitsPerPixel:32];
			int top_ink = 0;
			int bottom_ink = 0;
			int partial = 0;
			int x, y;

			[s setArrowsPosition:NSScrollerArrowsDefaultSetting];
			[s setFloatValue:0.0 knobProportion:0.5];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 15.0, 100.0)] fill];
			[s drawRect:NSMakeRect(0.0, 0.0, 15.0, 100.0)];
			/* **THE ARROW'S OWN ROWS, AND NOT THE KNOB'S.** The knob's top edge is at y=15 and its 1-point STROKE is
			 * anti-aliased into y=14 — which is correct for a curve and is not the arrow. The arrow's box is centred in
			 * its 15-point button, so the rows below are its own: 5..9 at the top, 90..94 at the bottom. THE GROOVE IS
			 * EXCLUDED FOR A SECOND REASON — at 0.85 it falls inside the "half-covered" band below, so a groove row
			 * inside these windows would be counted as an anti-aliased arrow edge. */
			for (y = 0; y < 100; y++) {
				int drawing_y = 99 - y;	/* the bitmap counts rows from the top, the drawing from its own origin */
				/* THE GLYPH'S OWN ROWS, AND THEY ARE EACH OTHER'S MIRROR: 100 - 1 - 10 = 89, 100 - 1 - 4 = 95. */
				BOOL in_top = (drawing_y >= 4 && drawing_y <= 10);
				BOOL in_bottom = (drawing_y >= 89 && drawing_y <= 95);

				if (!in_top && !in_bottom) {
					continue;
				}
				for (x = 3; x <= 11; x++) {
					double v = [[rep colorAtX:x y:y] redComponent];

					if (v < 0.8) {		/* the arrow's own ink */
						if (in_top) {
							top_ink++;
						} else {
							bottom_ink++;
						}
					} else if (v < 0.97) {	/* neither ink nor ground: a half-covered point */
						partial++;
					}
				}
			}
			printf("  (note: the two arrows cover %d and %d points; %d half-covered inside the glyph)\n",
			       top_ink, bottom_ink, partial);
			check(top_ink > 0 && top_ink == bottom_ink,
			      "the decrement and increment arrows are each other's MIRROR — the same points, turned over");
			check(partial == 0,
			      "and there is no half-covered point in either: the arrow is CRISP, not an anti-aliased smudge");
			[rep release];
		}

		/* 11. AND THE FLAG ITS OWN DOOR SETS, read back through the control. */
		[s highlight:YES];
		check([s isHighlighted], "`-highlight:YES` reads back as highlighted");
		[s highlight:NO];
		check(![s isHighlighted], "and `-highlight:NO` clears it");

		/* 12. **AND A HELD PAGE REPEATS, WHICH THE TRACKING LOOP POLLS AND THE CELL TIMES.** A press that STEPS goes
		 * on stepping while the button is held, and the loop is the only thing that knows time is passing — but the
		 * NUMBERS are the cell's. The clock is SUPPLIED here (`-cg_trackingShouldRepeatAtTime:`), which is what pins
		 * the delay and the spacing without a test that sleeps through them. */
		{
			NSTimeInterval soon;

			[s setFloatValue:0.0 knobProportion:0.5];
			[cell startTrackingAt:NSMakePoint(7.0, 80.0) inView:s];	/* a press on the increment page (the slot below the knob) */
			check(![cell cg_trackingShouldRepeat],
			      "a page does not repeat the instant it is pressed — there is a delay for a hand that meant ONE page");
			soon = [NSDate timeIntervalSinceReferenceDate] + 30.0;	/* comfortably past the press's own delay */
			check([cell cg_trackingShouldRepeatAtTime:soon], "but a HELD page repeats once its delay has passed");
			check(![cell cg_trackingShouldRepeatAtTime:soon],
			      "and the repeats are SPACED: the next instant is not another step");
			check([cell cg_trackingShouldRepeatAtTime:(soon + 1.0)], "while a later one is");

			/* THE KNOB NEVER REPEATS — a drag is already a value per point — and the RELEASE disarms a page. */
			[cell startTrackingAt:NSMakePoint(7.0, 40.0) inView:s];
			check(![cell cg_trackingShouldRepeatAtTime:soon], "a KNOB never repeats");
			[cell startTrackingAt:NSMakePoint(7.0, 80.0) inView:s];
			[cell continueTracking:NSMakePoint(7.0, 80.0) at:NSMakePoint(7.0, 80.0) inView:s];	/* the release */
			check(![cell cg_trackingShouldRepeatAtTime:soon], "and the release stops a page that was repeating");
		}

		/* 13. **WHICH PARTS FIT, AND THE GEOMETRY FOLLOWING THE ANSWER.** The era's four members are a reduction: a bar too
		 * short for two buttons is buttons only, one whose slot cannot hold a square knob is a knob only, and the ordinary
		 * 15x100 bar has all three. THE PART THAT MATTERS IS THAT THE ANSWER IS NOT ADVICE — `-rectForPart:` reads it, so a
		 * part the bar has no room for has NO RECTANGLE and can be neither drawn nor hit. */
		{
			NSScroller *ordinary = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, 15.0, 100.0)];
			NSScroller *snug = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, 15.0, 40.0)];
			NSScroller *tiny = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, 15.0, 20.0)];
			NSScroller *bare = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, 15.0, 100.0)];

			check([ordinary usableParts] == NSScrollerAllParts,
			      "a 15x100 bar has room for both buttons and the track, which is the ordinary answer");
			check([snug usableParts] == NSScrollerKnobOnly,
			      "a 15x40 bar's slot cannot hold a square knob, so it keeps the KNOB and drops the buttons");
			check([tiny usableParts] == NSScrollerArrowsOnly,
			      "and a 15x20 bar has no slot at all — two 15-point buttons fill it, so only they are left");
			[bare setArrowsPosition:NSScrollerArrowsNone];
			check([bare usableParts] == NSScrollerKnobSlotOnly,
			      "with the arrows off by position, the knob and its slot are the whole bar");

			/* THE GEOMETRY, READ BACK: a dropped part is a part with no rectangle. */
			check(eqr([snug rectForPart:NSScrollerDecrementLine], NSZeroRect),
			      "in the knob-only bar neither line button HAS a rectangle");
			check(eqr([snug rectForPart:NSScrollerKnobSlot], NSMakeRect(0.0, 0.0, 15.0, 40.0)),
			      "and the slot is the whole frame, so the knob fills it");
			check(eqr([tiny rectForPart:NSScrollerKnobSlot], NSMakeRect(0.0, 15.0, 15.0, 0.0)),
			      "in the buttons-only bar the slot is EMPTY, and the two buttons meet in the middle");
			check(eqr([tiny rectForPart:NSScrollerDecrementLine], NSMakeRect(0.0, 0.0, 15.0, 15.0)) &&
			      eqr([tiny rectForPart:NSScrollerIncrementLine], NSMakeRect(0.0, 5.0, 15.0, 15.0)),
			      "and each button has its own end");
			check([tiny testPart:NSMakePoint(7.0, 2.0)] == NSScrollerDecrementLine,
			      "so a press at the top is the decrement button there");
			check([tiny testPart:NSMakePoint(7.0, 17.0)] == NSScrollerIncrementLine,
			      "and a press at the bottom is the increment button");

			/* AND THE DOOR THAT RE-ASKS: `-checkSpaceForParts` is a redisplay here (the answer is computed), so the
			 * claim is that the answer survives it and that a RESIZED bar re-answers from the new frame. */
			[ordinary setFrameSize:NSMakeSize(15.0, 40.0)];
			[ordinary checkSpaceForParts];
			check([ordinary usableParts] == NSScrollerKnobOnly,
			      "`-checkSpaceForParts` after a resize answers from the frame the bar NOW has");
			[ordinary setFrameSize:NSMakeSize(15.0, 100.0)];
			check([ordinary usableParts] == NSScrollerAllParts, "and back again when it is tall enough");
			[ordinary release];
			[snug release];
			[tiny release];
			[bare release];
		}

		/* 14. **THE PROPORTION WITHOUT THE VALUE.** The pair door is one fact and the single door is the other half of
		 * it: a caller that has measured a new visible fraction writes it and leaves the reader where it was. */
		[s setFloatValue:0.4 knobProportion:0.5];
		[s setKnobProportion:0.25];
		check(near([s knobProportion], 0.25) && near([s floatValue], 0.4),
		      "`-setKnobProportion:` writes the proportion and KEEPS the value");
		[s setKnobProportion:9.0];
		check(near([s knobProportion], 1.0), "and it clamps like the pair door does");

		/* 15. **THE TINT IS THE KNOB'S, WHICH IS THE ONE PIECE OF THE BAR WITH A SURFACE OF ITS OWN.** The default leaves
		 * the sample's white knob; asking for graphite asks the knob to wear the platform's graphite, which is a grey
		 * MEASURED on the knob's own pixels rather than read back from the flag. */
		{
			NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:15
				pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:15 * 4 bitsPerPixel:32];
			NSRect k;
			double white_knob;
			double grey_knob;

			[s setArrowsPosition:NSScrollerArrowsDefaultSetting];
			[s setFloatValue:0.5 knobProportion:0.5];
			k = [s rectForPart:NSScrollerKnob];
			[s setControlTint:NSDefaultControlTint];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:vframe] fill];
			[s drawRect:vframe];
			white_knob = [[rep colorAtX:11 y:(int)(100 - 1 - NSMidY(k))] redComponent];
			[s setControlTint:NSGraphiteControlTint];
			check([s controlTint] == NSGraphiteControlTint, "`-setControlTint:` round-trips through the control");
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:vframe] fill];
			[s drawRect:vframe];
			grey_knob = [[rep colorAtX:11 y:(int)(100 - 1 - NSMidY(k))] redComponent];
			printf("  (note: the knob's red is %.3f at the default tint and %.3f at graphite)\n",
			       white_knob, grey_knob);
			check(white_knob > 0.9, "the default tint leaves the knob WHITE, which is the sample's picture");
			check(grey_knob < white_knob - 0.2, "and graphite paints it a grey, which is what the door asks for");
			[s setControlTint:NSDefaultControlTint];
			[rep release];
		}

		/* 16. **THE TWO TRACKING ENTRY POINTS ARE GATES ON THE ONE LOOP.** Each refuses a press that did not land on the
		 * part it names — `-hitPart` is the witness — and each runs the loop for one that did. There is no run loop here,
		 * so the loop's own early return leaves exactly the state a press writes, which is what is being read. */
		{
			NSEvent *on_knob = [NSEvent mouseEventWithType:NSLeftMouseDown
							      location:NSMakePoint(7.0, 40.0)
							 modifierFlags:0
							     timestamp:0.0
							  windowNumber:0
							       context:nil
							   eventNumber:1
							    clickCount:1
							      pressure:1.0];
			NSEvent *on_line = [NSEvent mouseEventWithType:NSLeftMouseDown
							      location:NSMakePoint(7.0, 92.0)
							 modifierFlags:0
							     timestamp:0.0
							  windowNumber:0
							       context:nil
							   eventNumber:2
							    clickCount:1
							      pressure:1.0];

			[s setArrowsPosition:NSScrollerArrowsDefaultSetting];
			[s setFloatValue:0.5 knobProportion:0.5];
			check(on_knob != nil && on_line != nil, "the probe can build mouse-down events");

			/* A PRESS OFF THE BAR ENTIRELY CLEARS THE PART, which is how "nothing happened" is measured. */
			[cell startTrackingAt:NSMakePoint(200.0, 200.0) inView:s];
			check([s hitPart] == NSScrollerNoPart, "a press outside the bar reports no part");

			[s trackKnob:on_line];
			check([s hitPart] == NSScrollerNoPart,
			      "`-trackKnob:` REFUSES a press on a line button — it is not a knob drag");
			[s trackKnob:on_knob];
			check([s hitPart] == NSScrollerKnob, "and runs the loop for a press on the knob");

			[cell startTrackingAt:NSMakePoint(200.0, 200.0) inView:s];
			[s trackScrollButtons:on_knob];
			check([s hitPart] == NSScrollerNoPart,
			      "`-trackScrollButtons:` refuses a press on the knob for the same reason");
			[s trackScrollButtons:on_line];
			check([s hitPart] == NSScrollerIncrementLine, "and runs it for a press on a line button");
		}

		/* 17. **AND ALL OF THE INK AT ONCE.** `-drawParts` is the whole bar in one call, which is checked by comparing
		 * the ink it lays down with the ink `-drawWithFrame:` lays down for the same frame. */
		{
			NSBitmapImageRep *by_parts = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:15
				pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:15 * 4 bitsPerPixel:32];
			NSBitmapImageRep *by_frame = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:15
				pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:15 * 4 bitsPerPixel:32];
			int parts_ink;
			int frame_ink;

			[s setArrowsPosition:NSScrollerArrowsDefaultSetting];
			[s setFloatValue:0.5 knobProportion:0.5];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:by_parts]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:vframe] fill];
			[s drawParts];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:by_frame]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:vframe] fill];
			[s drawRect:vframe];
			parts_ink = ink_in(by_parts, 100, 0, 0, 15, 100, 0.97);
			frame_ink = ink_in(by_frame, 100, 0, 0, 15, 100, 0.97);
			printf("  (note: -drawParts lays %d inked points; -drawRect: lays %d)\n", parts_ink, frame_ink);
			check(parts_ink > 0 && parts_ink == frame_ink,
			      "`-drawParts` IS the frame's own painting — the same ink, point for point");
			[by_parts release];
			[by_frame release];
		}

		[s release];
		printf("scroller: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
