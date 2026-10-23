/*
 * slider_title_ticks — the slider's tick marks as VALUES, its title as a CELL, and the two no-argument ink doors.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE TICKS WERE INK BEFORE THIS SLICE AND ARE VALUES NOW, WHICH IS THE WHOLE CLAIM.** A scale a caller can only
 * see is a decoration; `-tickMarkValueAtIndex:`, `-closestTickMarkValueToValue:` and `-allowsTickMarkValuesOnly` make
 * it part of the control's contract, and the probe measures the arithmetic in both directions: the nth mark's value,
 * the nearest mark to a value, and the snap every value setter then performs.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. The marks are EVENLY SPACED WITH BOTH ENDS INCLUDED: n marks make the first the minimum and the last the
 *      maximum, one mark is the minimum, and no marks is a value with no snap.
 *   2. `-allowsTickMarkValuesOnly` snaps a standing value when it is turned on AND every value afterwards; turning it
 *      off frees the value again.
 *   3. `-rectOfTickMarkAtIndex:` places each mark on the same travel the knob uses — measured, not assumed — in BOTH
 *      orientations and in a FLIPPED view, where the old inline ink drew the scale upside down.
 *   4. `-indexOfTickMarkAtPoint:` names the mark at a point and answers `NSNotFound` between marks.
 *   5. `-knobThickness` is the effective length along the track; setting it moves the travel and the two geometric
 *      doors still round-trip.
 *   6. The title is a CELL, its font and colour round-trip, and the TITLE'S BAND IS TAKEN OFF THE TOP of the frame —
 *      the knob's centre moves down by exactly that band, and the words draw where the knob used to be.
 *   7. `-drawKnob` (no argument) and `-knobRectFlipped:` take their rectangle from the control view; with no view they
 *      answer their type's empty value rather than inventing a frame.
 *   8. `-image` is the slider's BACKGROUND: it stores and answers, and the drawing puts it UNDER the track, the
 *      knob and the title — proved by a pixel the track cannot cover, and by the same pixel going white when the
 *      image is removed.
 */
#import <AppKit/NSSlider.h>
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSAttributedString.h>

#include <objc/runtime.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>

#define W 200
#define H 40

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

static int near_point(double a, double b)
{
	return fabs(a - b) < 0.51;
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

static void clear_rep(NSBitmapImageRep *rep)
{
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
}

/* INK ANYWHERE IN A BOX: a pixel that is not the white the probe filled with. The box is in BITMAP ROWS, which count
 * from the top; `ink_in_drawing` is the version a drawing coordinate can be handed without a silent vertical flip —
 * the mistake an earlier version of this probe made, and the reason both spellings are here. */
static int ink_in(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			/* **"NOT THE WHITE THE PROBE FILLED WITH" RATHER THAN "DARK"**, because the title's colour is a
			 * caller's choice and this probe sets it RED to prove the colour door has a reader. A threshold on
			 * `redComponent` alone would call red text invisible — which is exactly what an earlier version did. */
			if (c != nil && !([c redComponent] > 0.97 && [c greenComponent] > 0.97
					  && [c blueComponent] > 0.97)) {
				n++;
			}
		}
	}
	return n;
}

static int ink_in_drawing(NSBitmapImageRep *rep, int x0, double y0, int x1, double y1)
{
	int row0 = H - (int)ceil(y1);
	int row1 = H - (int)floor(y0);

	if (row0 < 0) {
		row0 = 0;
	}
	if (row1 > H) {
		row1 = H;
	}
	if (row0 >= row1) {
		return 0;
	}
	return ink_in(rep, x0, row0, x1, row1);
}

/* IS THE PIXEL THE BACKGROUND IMAGE'S RED? A solid image is the only way to separate "the background was drawn"
 * from "the track was drawn over it", and the corner chosen is above the track and away from the knob. */
static int pixel_is_red(NSBitmapImageRep *rep, int x, int y)
{
	NSColor *c = [rep colorAtX:x y:y];

	return c != nil && [c redComponent] > 0.85 && [c greenComponent] < 0.25 && [c blueComponent] < 0.25;
}

/* A FLIPPED SLIDER, so the mark that used to be drawn upside down can be pinned. The override is the whole point:
 * `-rectOfTickMarkAtIndex:` asks the control view which way it counts. */
@interface AGFlippedSlider : NSSlider
@end

@implementation AGFlippedSlider
- (BOOL)isFlipped { return YES; }
@end

int main(void)
{
	@autoreleasepool {
		NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, 20.0)];
		NSSliderCell *cell = (NSSliderCell *)[slider cell];
		NSRect bounds = NSMakeRect(0.0, 0.0, (CGFloat)W, 20.0);

		/* 1. THE MARKS AS VALUES. */
		[slider setMinValue:0.0];
		[slider setMaxValue:100.0];
		[slider setNumberOfTickMarks:5];
		check(near([cell tickMarkValueAtIndex:0], 0.0), "the first of five marks is the MINIMUM");
		check(near([cell tickMarkValueAtIndex:2], 50.0), "the middle mark is halfway between the ends");
		check(near([cell tickMarkValueAtIndex:4], 100.0), "and the last mark is the MAXIMUM");
		check(near([cell tickMarkValueAtIndex:5], 0.0),
		      "an index past the marks answers the minimum — the type's empty value, not a value off the range");
		check(near([cell closestTickMarkValueToValue:26.0], 25.0), "26 is nearest the 25 mark");
		check(near([cell closestTickMarkValueToValue:74.0], 75.0), "74 is nearest the 75 mark");
		check(near([cell closestTickMarkValueToValue:1000.0], 100.0), "a value past the end clamps before it snaps");
		[slider setNumberOfTickMarks:1];
		check(near([cell tickMarkValueAtIndex:0], 0.0) && near([cell closestTickMarkValueToValue:80.0], 0.0),
		      "ONE mark is the minimum, and every value is nearest it");
		[slider setNumberOfTickMarks:0];
		check(near([cell closestTickMarkValueToValue:43.0], 43.0),
		      "with NO marks there is nothing to snap to, so the value is itself");

		/* 2. THE FLAG AND ITS SNAP — ON, AT THE MOMENT IT IS TURNED ON, AND OFF AGAIN. */
		[slider setNumberOfTickMarks:5];
		[slider setDoubleValue:26.0];
		[slider setAllowsTickMarkValuesOnly:YES];
		check([slider allowsTickMarkValuesOnly], "the flag round-trips through the control");
		check(near([slider doubleValue], 25.0), "turning it ON snaps the standing value to the nearest mark");
		[slider setDoubleValue:74.0];
		check(near([slider doubleValue], 75.0), "and every value set afterwards is snapped");
		[slider setDoubleValue:1000.0];
		check(near([slider doubleValue], 100.0), "including one clamped at the end");
		[slider setMaxValue:90.0];
		check(near([slider doubleValue], 90.0), "moving an end re-clamps and re-snaps through the same door");
		[slider setAllowsTickMarkValuesOnly:NO];
		[slider setDoubleValue:26.0];
		check(near([slider doubleValue], 26.0), "turning it OFF frees the value again");

		/* 3. WHERE THE MARKS ARE, AND THE PROPERTY THAT MAKES THEM THE KNOB'S OWN SCALE: each mark's centre along the
		 * track is the centre of the knob at that mark's value — in both orientations and both flips. That is the
		 * check the old inline ink could not pass in a flipped vertical slider. */
		[slider setMinValue:0.0];
		[slider setMaxValue:100.0];
		[slider setNumberOfTickMarks:5];
		[slider setTickMarkPosition:NSTickMarkBelow];
		{
			NSRect r0 = [cell rectOfTickMarkAtIndex:0];
			NSRect r4 = [cell rectOfTickMarkAtIndex:4];

			printf("  (note: horizontal marks: first centre %.2f, last centre %.2f)\n",
			       NSMidX(r0), NSMidX(r4));
			check(r0.size.width > 0.0 && r0.size.height > 0.0 && r4.size.width > 0.0,
			      "a mark has a rectangle in a horizontal slider");
			check(near_point(NSMidX(r0), 6.0) && near_point(NSMidX(r4), (double)W - 6.0),
			      "the first mark is half a grabber in from the left and the last half in from the right");
			check(near_point(NSMinY(r0), 0.0),
			      "a BELOW mark begins at the frame's bottom edge");
			[slider setTickMarkPosition:NSTickMarkAbove];
			r0 = [cell rectOfTickMarkAtIndex:0];
			check(near_point(NSMaxY(r0), 20.0),
			      "and an ABOVE mark ends at the frame's top edge");
			[slider setTickMarkPosition:NSTickMarkBelow];
		}
		{
			NSInteger i;
			int all_match = 1;

			for (i = 0; i < 5; i++) {
				NSRect tick = [cell rectOfTickMarkAtIndex:i];
				double value = [cell tickMarkValueAtIndex:i];
				double save = [slider doubleValue];
				NSRect knob;

				[slider setDoubleValue:value];
				knob = [cell knobRect:bounds flipped:NO];
				if (!near_point(NSMidX(tick), NSMidX(knob))) {
					all_match = 0;
				}
				[slider setDoubleValue:save];
			}
			check(all_match, "every horizontal mark is centred on the knob's centre at that mark's value");
		}
		{
			/* THE VERTICAL, FLIPPED CASE, WHICH IS THE ONE THE OLD INK GOT WRONG. */
			AGFlippedSlider *flipped = [[AGFlippedSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, (CGFloat)W)];
			NSSliderCell *fcell = (NSSliderCell *)[flipped cell];
			NSRect fbounds = NSMakeRect(0.0, 0.0, 20.0, (CGFloat)W);
			NSInteger i;
			int all_match = 1;

			[flipped setMinValue:0.0];
			[flipped setMaxValue:100.0];
			[flipped setNumberOfTickMarks:5];
			[flipped setVertical:YES];
			for (i = 0; i < 5; i++) {
				NSRect tick = [fcell rectOfTickMarkAtIndex:i];
				double value = [fcell tickMarkValueAtIndex:i];
				double save = [flipped doubleValue];
				NSRect knob;

				[flipped setDoubleValue:value];
				knob = [fcell knobRect:fbounds flipped:YES];
				if (!near_point(NSMidY(tick), NSMidY(knob))) {
					all_match = 0;
				}
				[flipped setDoubleValue:save];
			}
			check(all_match, "and every VERTICAL mark in a FLIPPED view is centred on its knob — the scale is not "
			      "upside down");
			[flipped setDoubleValue:0.0];
			check(NSMidY([fcell rectOfTickMarkAtIndex:0]) > NSMidY([fcell rectOfTickMarkAtIndex:4]),
			      "with the minimum's mark BELOW the maximum's in a flipped view, as its knob is");
			[flipped release];
		}

		/* 4. THE POINT THAT NAMES A MARK. */
		{
			NSRect r2 = [cell rectOfTickMarkAtIndex:2];
			NSPoint on = NSMakePoint(NSMidX(r2), NSMidY(r2));
			NSPoint between = NSMakePoint((NSMidX([cell rectOfTickMarkAtIndex:0]) +
						       NSMidX([cell rectOfTickMarkAtIndex:1])) / 2.0, 10.0);

			check([cell indexOfTickMarkAtPoint:on] == 2, "a point on the middle mark names index 2");
			check([cell indexOfTickMarkAtPoint:between] == NSNotFound,
			      "a point between two marks names NO mark, which is what 'at point' means");
			check([cell indexOfTickMarkAtPoint:NSMakePoint(1000.0, 10.0)] == NSNotFound,
			      "and a point outside the control names none either");
		}

		/* 5. THE KNOB'S THICKNESS IS THE EFFECTIVE LENGTH ALONG THE TRACK. */
		{
			NSSlider *thick = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, 20.0)];
			NSSliderCell *tcell = (NSSliderCell *)[thick cell];
			NSRect r;

			[thick setMinValue:0.0];
			[thick setMaxValue:100.0];
			[thick setNumberOfTickMarks:0];
			check(near([tcell knobThickness], 18.0),
			      "a circle's thickness is its own default — the extent across the track");
			[tcell setKnobThickness:30.0];
			check(near([tcell knobThickness], 30.0), "setting it answers the new effective thickness");
			[thick setDoubleValue:50.0];
			r = [tcell knobRect:NSMakeRect(0.0, 0.0, (CGFloat)W, 20.0) flipped:NO];
			check(near(NSWidth(r), 30.0), "and the knob is that long along the track");
			check(near(NSMidX(r), (double)W / 2.0), "while the middle value is still in the middle of the frame");
			check(near([tcell cg_valueAtPoint:NSMakePoint(NSMidX(r), 10.0)
						   inRect:NSMakeRect(0.0, 0.0, (CGFloat)W, 20.0)
						  flipped:NO], 50.0),
			      "and the two geometric doors still round-trip with a thicker knob");
			[tcell setNumberOfTickMarks:4];
			check(near([tcell knobThickness], 30.0), "a caller's thickness survives a change of shape");
			[thick release];
		}

		/* 6. THE TITLE: A CELL, TWO CONVENIENCES, AND A BAND TAKEN OFF THE TOP. */
		{
			NSSlider *titled = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSSlider *plain = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSSliderCell *titledCell = (NSSliderCell *)[titled cell];
			NSSliderCell *plainCell = (NSSliderCell *)[plain cell];
			NSRect frame = NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H);
			NSFont *font = [NSFont systemFontOfSize:14.0];
			NSColor *colour = [NSColor redColor];
			NSBitmapImageRep *rep;

			[titled setTitle:@"Speed"];
			[plain setTitle:@""];
			check([[titled title] isEqualToString:@"Speed"], "the title round-trips through the control");
			check([[titledCell title] isEqualToString:@"Speed"], "and is the cell's own label");
			check([[titled titleCell] isKindOfClass:[NSCell class]], "the title cell is an NSCell");
			[titled setTitleFont:font];
			[titled setTitleColor:colour];
			check([titled titleFont] == font && near([[titled titleFont] pointSize], 14.0),
			      "the title's font is the one a caller set");
			check([[titled titleColor] isEqual:colour], "and so is its colour");

			[titled setDoubleValue:50.0];
			[plain setDoubleValue:50.0];
			printf("  (note: the titled knob's centre is %.2f; the untitled one is %.2f)\n",
			       NSMidY([titledCell knobRect:frame flipped:NO]),
			       NSMidY([plainCell knobRect:frame flipped:NO]));
			check(NSMidY([titledCell knobRect:frame flipped:NO]) <
			      NSMidY([plainCell knobRect:frame flipped:NO]) - 4.0,
			      "a title takes its band off the TOP, so the titled knob sits lower than an untitled one");

			rep = new_rep();
			clear_rep(rep);
			[titled drawRect:frame];
			/* **THE FACE ITSELF, ROW BY ROW, WHEN SOMEONE ASKS TO SEE IT** — the convention `APPKIT_SLIDER_DIAG`
			 * sets in the sibling probe, and the way a band claim is checked by eye rather than by one number. */
			if (getenv("APPKIT_SLIDER_TITLE_DIAG") != NULL) {
				int row;

				printf("  (the titled face, one drawing row per line, top first: title '%s', cell %s)\n",
				       [[titledCell title] UTF8String],
				       class_getName([[[titledCell titleCell] class] self]));
				for (row = 0; row < H; row++) {
					printf("    row %2d (drawing y %2d): %d\n", row, H - 1 - row,
					       ink_in(rep, 0, row, W, row + 1));
				}
			}
			check(ink_in_drawing(rep, 0, 22.0, W, (double)H) > 0,
			      "and the words are DRAWN in that band, above where the knob would be without one");
			[rep release];

			rep = new_rep();
			clear_rep(rep);
			[plain drawRect:frame];
			check(ink_in_drawing(rep, 0, 31.0, W, (double)H) == 0,
			      "an UNTITLED slider draws nothing above its knob — the band is the title's, not the frame's");
			[rep release];

			/* AND A TITLE REMOVED GIVES THE FRAME BACK. */
			[titled setTitle:@""];
			check(NSMidY([titledCell knobRect:frame flipped:NO]) > 18.0,
			      "removing the title returns the knob to the middle of the whole frame");

			/* THE CELL ITSELF IS REPLACEABLE, WHICH IS WHAT MAKES IT A DOOR AND NOT A FIELD. */
			{
				NSCell *custom = [[NSCell alloc] initTextCell:@""];

				[titled setTitle:@"Again"];
				[titled setTitleCell:custom];
				check([titled titleCell] == custom, "a caller's title cell is the one the slider answers");
				check([[custom title] isEqualToString:@"Again"],
				      "and it is given the slider's standing title, so the label and the face cannot disagree");
				[custom release];
			}
			[titled release];
			[plain release];
		}

		/* 7. THE TWO NO-ARGUMENT INK DOORS. */
		{
			NSSlider *one = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, 20.0)];
			NSSliderCell *oneCell = (NSSliderCell *)[one cell];
			NSRect want;
			NSBitmapImageRep *rep;

			[one setMinValue:0.0];
			[one setMaxValue:100.0];
			[one setDoubleValue:50.0];
			want = [oneCell knobRect:[one bounds] flipped:NO];
			check(NSEqualRects(want, [oneCell knobRectFlipped:NO]),
			      "`-knobRectFlipped:` answers the control view's own knob rectangle");
			rep = new_rep();
			clear_rep(rep);
			[oneCell drawKnob];
			check(ink_in_drawing(rep, (int)NSMinX(want), (double)NSMinY(want),
					     (int)NSMaxX(want), (double)NSMaxY(want)) > 0,
			      "`-drawKnob` draws the knob where the control view's rectangle puts it");
			[rep release];
			[one release];
		}
		{
			NSSliderCell *orphan = [[NSSliderCell alloc] init];

			check(NSEqualRects([orphan trackRect], NSZeroRect),
			      "`-trackRect` with NO control view answers the empty rectangle");
			check(NSEqualRects([orphan knobRectFlipped:NO], NSZeroRect),
			      "and so does `-knobRectFlipped:`");
			check(NSEqualRects([orphan rectOfTickMarkAtIndex:0], NSZeroRect),
			      "and `-rectOfTickMarkAtIndex:`");
			check([orphan indexOfTickMarkAtPoint:NSMakePoint(0.0, 0.0)] == NSNotFound,
			      "and `-indexOfTickMarkAtPoint:` names no mark");
			[orphan drawKnob];	/* the refusal, not a crash */
			check(1, "`-drawKnob` with no control view refuses rather than inventing a frame");
			[orphan release];
		}

		/* 8. THE IMAGE IS THE BACKGROUND, WHICH IS A CLAIM ABOUT PIXELS AND NOT ONLY STORAGE. */
		{
			NSSlider *painted = [[NSSlider alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
				pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
			NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize((CGFloat)W, (CGFloat)H)];
			NSBitmapImageRep *face;

			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor redColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[image addRepresentation:rep];
			[rep release];

			[painted setImage:image];
			check([painted image] == image, "`-image` stores and answers the image a caller set");

			face = new_rep();
			clear_rep(face);
			[painted drawRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			check(pixel_is_red(face, W - 3, 3),
			      "and the cell DRAWS it as the background, in a corner the track and knob cannot cover");

			[painted setImage:nil];
			clear_rep(face);
			[painted drawRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			check(!pixel_is_red(face, W - 3, 3),
			      "and removing it puts the ground back, so the reader is the image and not the face");
			[face release];
			[image release];
			[painted release];
		}

		printf("slider_title_ticks: %d case(s) failed\n", s_failed);
		[slider release];
	}
	return s_failed != 0;
}
