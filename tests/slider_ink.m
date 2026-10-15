/*
 * slider_ink — does a SLIDER's cell turn a value into a knob, and a point back into a value?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **A SLIDER IS A CONTROL WHOSE VALUE IS A POSITION, AND THE ONLY INTERESTING CLAIMS ARE THE TWO GEOMETRIC ONES.**
 * Everything else here — the range, the clamps, the forwards — is the same "the cell owns it and the control forwards
 * it" shape `control_ink` already measures for a button, so this probe spends its cases on the pair that makes a
 * slider a slider: `-knobRect:flipped:` and `-cg_valueAtPoint:inRect:flipped:`.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. A slider makes a SLIDER CELL, and its range is the 0…1 the era documents.
 *   2. Every value setter CLAMPS to the range, in all four numeric shapes.
 *   3. Moving a RANGE END re-clamps a standing value, rather than leaving a knob outside its track.
 *   4. A slider is CONTINUOUS by default and a button is not: the one flag that decides whether a drag speaks.
 *   5. `-knobRect:flipped:` places the minimum at the left, the maximum at the right, and the middle in between.
 *   6. `-cg_valueAtPoint:inRect:flipped:` is its EXACT INVERSE at the knob's centre — a press on the knob moves
 *      nothing — and CLAMPS for a point past either end.
 *   7. A slider DRAWS a track and a knob, and a vertical slider puts its maximum at the TOP.
 *   8. The tracking hooks (`-startTrackingAt:inView:`) are where a point becomes a value.
 */
#import <AppKit/NSSlider.h>
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

#include <math.h>
#include <stdlib.h>
#include <stdio.h>

#define W 160
#define H 20

/* **THE GRABBER'S OWN SHAPE NUMBERS, WRITTEN HERE AS WELL AS IN THE CELL** — the rule `control_metrics` holds the
 * bezel height to, and for the same reason: a probe that read them back from the thing under test could not notice
 * them moving. `TIP_ANGLE` is the one that decides the shape's character (see the cell): the narrow cap is an ARC of
 * that angle rather than a semicircle, which is what lets the sides leave it at an angle and bow OUTWARD instead of
 * pinching in. */
#define WANT_TIP_RADIUS 0.22
#define WANT_TIP_ANGLE  55.0

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
	return fabs(a - b) < 0.01;
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* INK ANYWHERE IN A BOX: a pixel that is not the white the probe filled with. */
static int ink_in(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.72) {
				n++;
			}
		}
	}
	return n;
}

/* THE INK'S HORIZONTAL EXTENT IN ONE ROW — how a SILHOUETTE is read, row by row. A check that only asked "is there
 * ink" could not tell a teardrop from a box, which is the whole of what changed here. The scan is bounded so the
 * track's own ink (a dark bar across the whole cell) can never be mistaken for the knob's.
 *
 * **THE THRESHOLD IS LOOSER THAN `ink_in`'s ON PURPOSE.** A knob's FACE is `controlColor` (0.90), which `ink_in`'s
 * 0.72 is tuned to call background — the silhouette is the whole SHAPE rather than its dark parts, so anything that
 * is not the white the bitmap was filled with counts. The knob is drawn alone here (no track underneath), which is
 * what makes that a safe question to ask.
 *
 * AND THE ROW INDEX IS CONVERTED RATHER THAN PASSED: the bitmap's rows count from the TOP (AppKit's
 * `-colorAtX:y:`) and the drawing's from the BOTTOM, which is the off-by-a-flip that made the first version of this
 * check measure the shape upside down and report it as narrow at the top. */
static int row_of_drawing_y(int drawing_y)
{
	return H - 1 - drawing_y;
}

/* THE SAME MAPPING FOR A BITMAP OF ANY SIZE — the shape's checks are made at a MAGNIFIED scale, because a convex
 * bow of half a point is real geometry and fewer than one pixel of ink. */
static int row_of_drawing_y_in(int drawing_y, int bitmapHigh)
{
	return bitmapHigh - 1 - drawing_y;
}

static NSBitmapImageRep *new_rep_sized(int wide, int high)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:wide pixelsHigh:high
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:wide * 4 bitsPerPixel:32];
}

static void row_extent(NSBitmapImageRep *rep, int y, int x0, int x1, int *lo, int *hi)
{
	int x;

	*lo = -1;
	*hi = -1;
	for (x = x0; x < x1; x++) {
		NSColor *c = [rep colorAtX:x y:y];

		if (c != nil && [c redComponent] < 0.97) {
			if (*lo < 0) {
				*lo = x;
			}
			*hi = x;
		}
	}
}

/* **THE KNOB ALONE, WITH ITS INK'S BOUNDING BOX MEASURED** — which is how "is it round" can be answered at all: a
 * circle is as tall as it is wide, and the teardrop is that circle plus a taper below it. The scan is clamped to the
 * bitmap, because the box the probe asks about may reach past the surface it is drawn on. */
static void knob_ink_box(NSBitmapImageRep *rep, NSRect k, int *wide, int *high)
{
	int t, lo, hi, first = -1, last = -1, loX = 1 << 20, hiX = -1;

	for (t = (int)NSMinY(k) - 3; t <= (int)NSMaxY(k) + 3; t++) {
		if (t < 0 || t >= H) {
			continue;
		}
		row_extent(rep, row_of_drawing_y_in(t, H), (int)NSMinX(k) - 3, (int)NSMaxX(k) + 4, &lo, &hi);
		if (lo < 0) {
			continue;
		}
		if (first < 0) {
			first = t;
		}
		last = t;
		if (lo < loX) {
			loX = lo;
		}
		if (hi > hiX) {
			hiX = hi;
		}
	}
	*wide = (hiX >= loX) ? (hiX - loX + 1) : 0;
	*high = (first >= 0) ? (last - first + 1) : 0;
}

/* IS THE PIXEL THIS COLOUR? The fill's whole claim is a COLOUR, so the check has to read one rather than count ink —
 * and the tolerance is the one a bitmap rep's colour-space round trip needs. */
static int pixel_is(NSBitmapImageRep *rep, int x, int y, NSColor *want)
{
	NSColor *c = [rep colorAtX:x y:y];

	return c != nil && want != nil
		&& fabs([c redComponent] - [want redComponent]) < 0.06
		&& fabs([c greenComponent] - [want greenComponent]) < 0.06
		&& fabs([c blueComponent] - [want blueComponent]) < 0.06;
}

/* A FLIPPED VIEW, which exists only so the knob's ORIENTATION can be pinned: the shape is asymmetric, and "which way
 * is up" comes from the control view rather than from `-drawKnob:`'s rectangle (see the cell for why). */
@interface AGFlippedView : NSView
@end

@implementation AGFlippedView
- (BOOL)isFlipped { return YES; }
@end

int main(void)
{
	@autoreleasepool {
		NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		NSSliderCell *cell = (NSSliderCell *)[slider cell];
		NSRect bounds = NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H);

		/* 1. THE CELL AND THE RANGE. */
		check([cell isKindOfClass:[NSSliderCell class]], "a slider makes a SLIDER CELL");
		check(near([slider minValue], 0.0) && near([slider maxValue], 1.0),
		      "and its range is the 0…1 the era documents");

		/* 2. THE CLAMPS, IN EVERY SHAPE THE VALUE IS ASKED FOR IN. */
		[slider setMinValue:0.0];
		[slider setMaxValue:100.0];
		[slider setDoubleValue:42.5];
		check(near([slider doubleValue], 42.5), "`-setDoubleValue:` sets the value");
		check(near([slider floatValue], 42.5) && [slider intValue] == 42 && [slider integerValue] == 42,
		      "and `-floatValue`, `-intValue`, `-integerValue` are the same number in other shapes");
		[slider setDoubleValue:5000.0];
		check(near([slider doubleValue], 100.0), "a value past the MAXIMUM is clamped to it");
		[slider setIntValue:-9];
		check(near([slider doubleValue], 0.0), "and one below the MINIMUM is clamped to it");

		/* 3. MOVING AN END RE-CLAMPS. The value is at 0 after the line above; raise it, then drop the maximum under
		 * it — the knob must not be left past the end of its own track. */
		[slider setDoubleValue:90.0];
		[slider setMaxValue:40.0];
		check(near([slider doubleValue], 40.0), "moving the maximum BELOW the value re-clamps the value");

		/* 4. THE CONTINUOUS FLAG, pinned on BOTH classes so the default is a measured fact rather than a comment. */
		{
			NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 20.0)];

			check([slider isContinuous], "a SLIDER is continuous by default, so a drag speaks as it moves");
			check(![button isContinuous], "and a BUTTON is not, so a drag off it cancels");
			[button release];
		}

		/* 5. THE KNOB'S PLACEMENT. The travel is the width less the knob, so the ends are the frame's ends and the
		 * middle is halfway between them. */
		[slider setMinValue:0.0];
		[slider setMaxValue:100.0];
		[slider setDoubleValue:0.0];
		check(near(NSMinX([cell knobRect:bounds flipped:NO]), 0.0),
		      "`-knobRect:flipped:` puts the MINIMUM at the left of the track");
		[slider setDoubleValue:100.0];
		{
			NSRect r = [cell knobRect:bounds flipped:NO];

			check(near(NSMaxX(r), (double)W), "and the MAXIMUM at the right, with the knob inside the frame");
		}
		[slider setDoubleValue:50.0];
		{
			NSRect r = [cell knobRect:bounds flipped:NO];
			CGFloat middle = NSMinX(r) + NSWidth(r) / 2.0;

			check(near(middle, (double)W / 2.0), "and the MIDDLE value at the middle of the frame");
			/* 6. THE INVERSE. The point a value places the knob's centre at must answer that value back — which is
			 * the property that makes a press ON the knob move nothing. */
			check(near([cell cg_valueAtPoint:NSMakePoint(middle, NSMidY(bounds)) inRect:bounds flipped:NO], 50.0),
			      "and `-cg_valueAtPoint:inRect:flipped:` is its EXACT INVERSE at the knob's centre");
		}
		check(near([cell cg_valueAtPoint:NSMakePoint(-500.0, 10.0) inRect:bounds flipped:NO], 0.0),
		      "a point past the LEFT end clamps to the minimum");
		check(near([cell cg_valueAtPoint:NSMakePoint(5000.0, 10.0) inRect:bounds flipped:NO], 100.0),
		      "and one past the RIGHT end clamps to the maximum");

		/* 7. THE INK, AND THE OTHER ORIENTATION. */
		{
			NSBitmapImageRep *rep = new_rep();

			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[slider drawRect:bounds];
			check(ink_in(rep, 0, 0, W, H) > 0, "a slider DRAWS a track and a knob");
			[rep release];
		}
		{
			/* A VERTICAL SLIDER IS A TALL FRAME, and its maximum is at the TOP: in an unflipped view that is the
			 * LARGER y, which is the one orientation claim the two geometry doors can be wrong about. */
			NSRect tall = NSMakeRect(0.0, 0.0, 20.0, 160.0);

			[slider setVertical:YES];
			[slider setDoubleValue:100.0];
			check(near(NSMaxY([cell knobRect:tall flipped:NO]), 160.0),
			      "a VERTICAL slider puts its maximum at the TOP");
			[slider setDoubleValue:0.0];
			check(near(NSMinY([cell knobRect:tall flipped:NO]), 0.0),
			      "and its minimum at the bottom");
			check(near([cell cg_valueAtPoint:NSMakePoint(10.0, 80.0) inRect:tall flipped:NO], 50.0),
			      "and the geometry still round-trips upright");
			[slider setVertical:NO];
		}

		/* 8. THE TRACKING HOOK: the cell's half of the control's loop, where a point becomes a value. */
		[slider setDoubleValue:0.0];
		{
			BOOL answered = [cell startTrackingAt:NSMakePoint((CGFloat)W / 2.0, NSMidY(bounds))
						       inView:slider];

			check(answered, "`-startTrackingAt:inView:` answers YES, so the control's loop keeps tracking");
			check(near([slider doubleValue], 50.0), "and a press at the middle TAKES the middle value");
		}

		/* AND THE TWO REMAINING PROPERTIES OF THE FACE, which are stored and answered where the ink is not: the tick
		 * marks, and the circular style this tier declares without drawing. */
		[slider setNumberOfTickMarks:5];
		[slider setTickMarkPosition:NSTickMarkAbove];
		check([slider numberOfTickMarks] == 5 && [slider tickMarkPosition] == NSTickMarkAbove,
		      "the ticks round-trip through the control");
		check([slider sliderType] == NSLinearSlider, "a slider's type is linear by default");
		[slider setSliderType:NSCircularSlider];
		check([slider sliderType] == NSCircularSlider,
		      "and a circular style is STORED and ANSWERED, even though the ink here is linear");
		[slider setSliderType:NSLinearSlider];

		check([slider acceptsFirstMouse:nil], "a slider takes a press in a window that is not yet active");

		/* 9. **THE KNOB'S SILHOUETTE, WHICH IS THE ONE THING A TEARDROP HAS TO GET RIGHT.** The shape is drawn on its
		 * own (no track underneath, so every row is clean) and read back a ROW AT A TIME, because "round at the top and
		 * narrow at the bottom" is a statement about how the width changes with height and nothing else can check it.
		 *
		 * THE ROWS ARE SCANNED RATHER THAN NAMED, WHICH IS THE CORRECTION THAT MATTERED. The first version of this
		 * check assumed the WIDEST row was the middle — true of a square knob, and FALSE of a taller one: a teardrop's
		 * widest point is where its round cap meets its taper, which is `height - radius` up from the bottom, so a
		 * taller grabber puts the widest row HIGHER. Measuring it keeps the check about the SHAPE rather than about a
		 * number that the shape was allowed to move. */
		{
			NSRect k = [cell knobRect:bounds flipped:NO];
			int kw = (int)NSWidth(k);
			int kh = (int)NSHeight(k);
			int ky0 = (int)NSMinY(k);
			int x0 = (int)NSMinX(k) - 3;
			int x1 = (int)NSMaxX(k) + 3;
			int lo, hi, t, tmax = -1, wmax = 0, wbot = 0, wtop = 0;
			int cbot = 0, ctop = 0, cmax = 0;
			NSBitmapImageRep *rep = new_rep();

			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[cell drawKnob:k];

			for (t = 0; t < kh; t++) {
				row_extent(rep, row_of_drawing_y(ky0 + t), x0, x1, &lo, &hi);
				if (lo < 0) {
					continue;
				}
				/* **THE LAST ROW AT THE MAXIMUM, NOT THE FIRST.** The sides are tangent to the wide cap AT the
				 * widest point, so the width stops growing exactly there and a run of rows measures the same —
				 * the geometric widest point is the TOP of that run, and the bottom of it is only wherever the
				 * pixel grid first reached the number. */
				if (hi - lo >= wmax) {
					wmax = hi - lo;
					tmax = t;
					cmax = (lo + hi) / 2;
				}
				if (t == 1) {
					wbot = hi - lo;
					cbot = (lo + hi) / 2;
				}
				if (t == kh - 2) {
					wtop = hi - lo;
					ctop = (lo + hi) / 2;
				}
			}
			printf("  (note: the grabber is %d wide by %d TALL; widest row is %d of %d up from the bottom; "
			       "widths: %d bottom, %d widest, %d top)\n", kw, kh, tmax, kh, wbot, wmax, wtop);

			/* **AND THE SHAPE ITSELF, DRAWN, WHEN SOMEONE ASKS TO SEE IT.** A silhouette is the one thing a number
			 * cannot describe to a person, and this probe is where the shape is decided — so the ASCII rendering is
			 * gated behind `APPKIT_SLIDER_DIAG` (the convention `APPKIT_MENU_DIAG` and `APPKIT_LOOP_DIAG` set) rather
			 * than printed on every run. `#` is the outline, `.` the face. */
			if (getenv("APPKIT_SLIDER_DIAG") != NULL) {
				int yy;

				printf("  (the grabber's silhouette, top row first)\n");
				for (yy = ky0 - 1; yy <= ky0 + kh + 1; yy++) {
					int xx;
					printf("  |");
					for (xx = x0; xx < x1; xx++) {
						NSColor *c2 = [rep colorAtX:xx y:yy];
						double v = (c2 != nil) ? [c2 redComponent] : 1.0;
						putchar(v < 0.72 ? '#' : (v < 0.97 ? '.' : ' '));
					}
					printf("|\n");
				}
			}

			/* **THE REQUEST ITSELF, PINNED FIRST: THE GRABBER IS TALLER THAN IT IS WIDE.** Everything else here is
			 * about the silhouette; this is about the one dimension the face was asked to grow, and it is the check
			 * that would have failed before the knob's box stopped being square. */
			check(kh > kw, "the grabber is TALLER than it is WIDE — the extent across the track is the bigger side");
			check(wbot > 0 && wtop > 0 && wmax > 0, "and it draws at every height it occupies");
			check(wbot < wmax && wtop < wmax, "with both ends narrower than the widest row");
			check(wbot < wtop, "and the NARROW end is the BOTTOM one");
			check(tmax > kh / 2,
			      "and the widest point is ABOVE the middle — a short round cap over a long taper, which is what "
			      "makes it a teardrop rather than a lozenge");
			/* **A RATIO AND NOT A HALF, BECAUSE THE ROW THIS MEASURES IS ALIGNMENT-SENSITIVE.** It read
			 * `wbot <= wmax / 2`, and `wbot` is the SECOND row up from the box's bottom, where the teardrop's
			 * narrow cap is only a few points across — so a fraction of a point of the cap's circumference is
			 * most of the ANSWER. MEASURED: the same path at a whole-point origin gives 4 there, and the knob's
			 * own fractional origin gives 5 or 7. It moved 5 -> 7 when the fill's trapezoids started taking
			 * their top x at the band's top rather than at its middle, which is a fix in libagora-drawing's
			 * `cg_sweep` and not a change to this shape: that defect made every shape's top edge as wide as its
			 * middle, and it is why a triangle drew with its apex missing.
			 *
			 * WHAT IS WORTH HOLDING IS THAT THE END IS CLEARLY NARROWER THAN THE WIDEST ROW — a lozenge would
			 * sit at half or above — so the ratio is what is asserted, and the shape itself is what the
			 * silhouette above is for. */
			check(wbot * 5 <= wmax * 3,
			      "and the narrow end is narrow: at most three fifths of the widest row");
			check(cbot - cmax <= 1 && cmax - cbot <= 1 && cmax - ctop <= 1 && ctop - cmax <= 1,
			      "and the taper and the cap are both SYMMETRIC about the knob's axis, so the shape leans neither way");
			[rep release];

			/* **AND THE SIDES ARE CONVEX, WHICH IS A PROPERTY OF THE WHOLE OUTLINE AND NOT OF ANY ONE ROW.** A convex
			 * boundary lies ENTIRELY ON ONE SIDE OF EVERY CHORD between two of its own points — so the right edge is
			 * read off row by row, and then EVERY WINDOW of it is joined by a straight line and checked for a stretch
			 * that strays INWARD. A pinch anywhere shows up in some window; ONE long chord can miss it, because a short
			 * concave stretch is invisible against the whole side, which is exactly how the grabber used to look fine
			 * in a screenshot and wrong on a desk.
			 *
			 * THE SHAPE IS DRAWN AT FIVE TIMES ITS SIZE FOR THIS. The difference between a bow and a pinch is real
			 * geometry worth about half a point — fewer than one pixel at the size a slider actually draws, and nothing
			 * anybody could measure there. */
			{
				int bigW = kw * 5, bigH = kh * 5;
				int pad = 8;
				int bmW = bigW + 2 * pad, bmH = bigH + 2 * pad;
				int edge[256];
				int lo2, hi2, t, tLow = -1, tHigh = -1, worstAt = -1;
				int shoulder = 0, widest = 0;
				double theta = 0.0, bigTip = 0.0;
				double worst = 0.0, bulge = 0.0;
				NSBitmapImageRep *big = new_rep_sized(bmW, bmH);
				NSRect bigRect = NSMakeRect((CGFloat)pad, (CGFloat)pad, (CGFloat)bigW, (CGFloat)bigH);
				int i;

				for (i = 0; i < 256; i++) {
					edge[i] = -1;
				}
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:big]];
				[[NSColor whiteColor] setFill];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)bmW, (CGFloat)bmH)] fill];
				[cell drawKnob:bigRect];
				for (t = 0; t < bigH && t < 256; t++) {
					row_extent(big, row_of_drawing_y_in(pad + t, bmH), pad + 1, pad + bigW + 3, &lo2, &hi2);
					if (lo2 < 0) {
						continue;
					}
					edge[t] = hi2;
					if (tLow < 0) {
						tLow = t;
					}
					tHigh = t;
				}

				/* **THE SIDE'S OWN CHORD, WHICH IS THE ONLY ONE THAT CAN SHOW A PINCH.** A single chord over the
				 * whole right edge is passed by a side that bows out at BOTH ends and dips in the middle — which is
				 * exactly what an S-shaped side does — because the two caps dominate it. So the chord is taken
				 * between the side's OWN two ends: where the narrow cap stops and where the wide cap starts.
				 *
				 * THOSE TWO ROWS ARE THE CELL'S NUMBERS, NOT THE INK'S, which is why the constants are repeated at
				 * the top of this file: the narrow cap reaches `tip·(1 - cos θ)` up from the bottom and the wide cap's
				 * centre is `height - radius` up, and neither is something the outline can be asked about. */
				theta = WANT_TIP_ANGLE * 3.14159265358979323846 / 180.0;
				bigTip = (double)((bigW < bigH) ? bigW : bigH) * WANT_TIP_RADIUS;
				shoulder = (int)(bigTip * (1.0 - cos(theta)));
				widest = (int)((double)bigH - (double)((bigW < bigH) ? bigW : bigH) / 2.0);
				if (shoulder < tLow) {
					shoulder = tLow;
				}
				if (widest > tHigh) {
					widest = tHigh;
				}
				for (t = shoulder; t <= widest; t++) {
					double chord, dev;

					if (edge[t] < 0 || edge[shoulder] < 0 || edge[widest] < 0 || widest <= shoulder) {
						continue;
					}
					chord = (double)edge[shoulder] + ((double)(edge[widest] - edge[shoulder]) *
									  (double)(t - shoulder)) / (double)(widest - shoulder);
					dev = (double)edge[t] - chord;
					if (dev < worst) {
						worst = dev;
						worstAt = t;
					}
					if (dev > bulge) {
						bulge = dev;
					}
				}
				printf("  (note: at 5x the SIDE bows OUT by %.1f px and strays INWARD by at most %.1f px, "
				       "over a chord of %d px — a pinch would show up as a large inward number here)\n",
				       bulge, -worst, widest - shoulder);
				check(tLow >= 0 && tHigh > tLow, "the right edge was read off the whole outline");
				check(worst > -1.0,
				      "and the SIDE stays outside the chord joining its own two ends — convex, not pinched in");
				check(bulge > 1.0, "and there IS a bow: the side is convex, not straight and not concave");
				[big release];
			}

			/* **AND THE ORIENTATION, WHICH THE RECTANGLE CANNOT CARRY.** The same knob, drawn through a FLIPPED control
			 * view, has to come out the other way up — the narrow end at the top — because a view that counts y
			 * downward is the case that would otherwise draw every teardrop upside down. */
			{
				AGFlippedView *fv = [[AGFlippedView alloc] initWithFrame:bounds];
				int f_top, f_bot;

				[cell setControlView:fv];
				rep = new_rep();
				[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
				[[NSColor whiteColor] setFill];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
				[cell drawKnob:k];
				row_extent(rep, row_of_drawing_y(ky0 + 1), x0, x1, &lo, &hi);
				f_bot = (lo < 0) ? 0 : hi - lo;
				row_extent(rep, row_of_drawing_y(ky0 + kh - 2), x0, x1, &lo, &hi);
				f_top = (lo < 0) ? 0 : hi - lo;
				printf("  (note: through a flipped view the same rows are %d at the bottom and %d at the top)\n",
				       f_bot, f_top);
				check(f_top > 0 && f_bot > 0 && f_top < f_bot,
				      "in a FLIPPED view the narrow end is at the TOP, so the shape follows the view's y direction");
				[rep release];
				[cell setControlView:slider];
				[fv release];
			}
		}

		/* 10. **THE TICK MARKS PEEK OUT FROM UNDER THE GRABBER, WHICH IS THE ONLY REASON TO HAVE THEM.** A scale
		 * that stops inside the grabber's outline is a scale that vanishes wherever the grabber is standing — so what
		 * this measures is ink BELOW the grabber's own bottom edge, at the column a tick sits at, with the grabber
		 * parked ON that tick. Nothing else can put ink there: the track is above and the grabber's stroke ends at
		 * its own edge, which is why a row two points below it is a clean test of the tick alone.
		 *
		 * THE FRAME IS TALLER THAN THE SLIDER'S USUAL ONE, because the reach the ticks are drawn with is clamped to
		 * the cell's own rectangle (a cell only owns the rectangle it is given) — a 20-point frame would clip the
		 * peek, and this check would then be measuring the clamp instead of the ticks. */
		{
			NSRect frame = NSMakeRect(0.0, 0.0, 320.0, 48.0);
			NSBitmapImageRep *rep = new_rep_sized(320, 48);
			NSRect k;
			int tx, kb, y, found = 0;

			[slider setNumberOfTickMarks:5];
			[slider setTickMarkPosition:NSTickMarkBelow];
			[slider setDoubleValue:[slider minValue]];
			k = [cell knobRect:frame flipped:NO];
			tx = (int)NSMidX(k);
			kb = (int)NSMinY(k);
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:frame] fill];
			[cell drawWithFrame:frame inView:slider];
			for (y = kb - 2; y >= kb - 4 && !found; y--) {
				int x;

				for (x = tx - 2; x <= tx + 2; x++) {
					NSColor *c = [rep colorAtX:x y:row_of_drawing_y_in(y, 48)];

					/* **THE THRESHOLD IS ABOVE THE TICK'S OWN COLOUR, WHICH IS DRAWN AS A ONE-PIXEL COLUMN THAT
					 * STRADDLES TWO OF THEM.** The ticks are `+controlDarkShadowColor` — 0.55 since it was
					 * lightened — and a 0.55 line at a half-pixel x blends to about 0.78 against the white it is
					 * drawn on, so "is there ink here" has to be above that and below the background. It was 0.72,
					 * which read the OLD 0.40's blend (about 0.70) and stopped reading the new one. */
					if (c != nil && [c redComponent] < 0.85) {
						found = 1;
						break;
					}
				}
			}
			printf("  (note: the grabber's bottom edge is at y=%d, and the tick%s found below it)\n",
			       kb, found ? " IS" : " is NOT");
			check(found, "a tick mark reaches BELOW the grabber's own edge, so the scale reads while it covers one");
			[rep release];
			[slider setNumberOfTickMarks:0];
			[slider setDoubleValue:50.0];
		}

		/* 11. **AND THE STRETCH THE VALUE HAS COVERED IS THE ACCENT.** The claim is a COLOUR at a PLACE, so it is read
		 * as one: the track to the LEFT of the grabber must be the accent and the track to the RIGHT of it must not,
		 * which together pin where the fill stops — the only part of it a person can see, since its far end is drawn
		 * under the grabber. And the two ends of the range are checked as well, because those are where a fill that is
		 * off by the grabber's own half-length goes wrong: at the MINIMUM the accent must be hidden under the grabber
		 * (it runs from the track's start to the grabber's centre, and the grabber is standing on that), and at the
		 * MAXIMUM it must have reached everything the grabber is not covering. */
		{
			NSBitmapImageRep *rep;
			NSRect k;
			int track = row_of_drawing_y_in((int)NSMidY(bounds), H);

			[slider setNumberOfTickMarks:0];

			/* the middle of the range: accent on the left, bare track on the right */
			[slider setDoubleValue:50.0];
			k = [cell knobRect:bounds flipped:NO];
			rep = new_rep();
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[cell drawWithFrame:bounds inView:slider];
			check(pixel_is(rep, (int)NSMinX(k) - 3, track, [NSColor cg_accentColor]),
			      "the track to the LEFT of the grabber is the ACCENT colour — the filled portion");
			check(!pixel_is(rep, (int)NSMaxX(k) + 3, track, [NSColor cg_accentColor]),
			      "and the track to the RIGHT of it is NOT, so the fill stops at the grabber");
			[rep release];

			/* the minimum: nothing of the accent is left showing */
			[slider setDoubleValue:[slider minValue]];
			rep = new_rep();
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[cell drawWithFrame:bounds inView:slider];
			check(!pixel_is(rep, 40, track, [NSColor cg_accentColor]),
			      "at the MINIMUM the accent is hidden under the grabber, so the track reads as empty");
			[rep release];

			/* the maximum: the accent has reached as far as the grabber allows */
			[slider setDoubleValue:[slider maxValue]];
			rep = new_rep();
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[cell drawWithFrame:bounds inView:slider];
			check(pixel_is(rep, 40, track, [NSColor cg_accentColor]),
			      "and at the MAXIMUM it has reached the whole track the grabber is not covering");
			[rep release];

			[slider setDoubleValue:50.0];
		}

		/* 12. **AND THE GRABBER'S SHAPE FOLLOWS THE TICK MARKS — IN ITS OUTLINE AND IN ITS SIZE.** A teardrop's point
		 * exists to say WHICH MARK the value is on, so a slider with no tick marks has nothing for it to point at and a
		 * circle is the honest shape. WHAT IS MEASURED IS THE INK'S OWN BOUNDING BOX, because "round" is a statement
		 * about two dimensions and nothing else — and the RECTANGLE is measured too, because the box IS the shape's
		 * bounding box and the two must not drift apart.
		 *
		 * THE BOX IS MEASURED AGAIN AFTER EACH TICK COUNT rather than once for both, which is not a detail: the box
		 * now FOLLOWS the shape, so a rectangle taken while one shape was in force is the wrong box for the other. The
		 * first version of this check did exactly that and reported a teardrop twenty pixels wide. */
		{
			NSBitmapImageRep *rep;
			NSRect k;
			int circleWide = 0, circleHigh = 0, dropWide = 0, dropHigh = 0;

			/* the circle: no tick marks at all */
			[slider setNumberOfTickMarks:0];
			k = [cell knobRect:bounds flipped:NO];
			check(NSWidth(k) == NSHeight(k),
			      "with no tick marks the grabber's BOX is SQUARE, because its shape is");
			rep = new_rep();
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[cell drawKnob:k];
			knob_ink_box(rep, k, &circleWide, &circleHigh);
			[rep release];
			check(circleWide > 0 && circleHigh > 0 && circleWide - circleHigh <= 1 && circleHigh - circleWide <= 1,
			      "with no tick marks the grabber is CIRCULAR — as tall as it is wide");

			/* the teardrop: tick marks to point at */
			[slider setNumberOfTickMarks:5];
			k = [cell knobRect:bounds flipped:NO];
			check(NSHeight(k) > NSWidth(k), "with tick marks its BOX is TALLER than wide, to hold the point");
			rep = new_rep();
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[cell drawKnob:k];
			knob_ink_box(rep, k, &dropWide, &dropHigh);
			[rep release];
			check(dropHigh > dropWide + 2,
			      "and with tick marks it is the TEARDROP: taller than it is wide, so its point can sit on a mark");

			/* and the circle is the bigger of the two: the same height, half again as wide */
			printf("  (note: the circle is %dx%d and the teardrop %dx%d)\n",
			       circleWide, circleHigh, dropWide, dropHigh);
			check(circleHigh == dropHigh,
			      "the circular grabber is the SAME HEIGHT as the teardrop — both fill the track's breadth");
			check(circleWide > dropWide + 4,
			      "and it is the BIGGER of the two, by about half its radius again");
			[slider setNumberOfTickMarks:0];
		}

		printf("slider_ink: %d case(s) failed\n", s_failed);
		[slider release];
	}
	return s_failed != 0;
}
