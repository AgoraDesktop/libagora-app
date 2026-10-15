/*
 * combo_box.m — THE COMBO BOX'S INK, AND THE ONE MARK THAT TELLS IT FROM THE POP-UP BESIDE IT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLAIM THIS FILE EXISTS FOR IS A COUNT.** A pop-up's chip carries two triangles knocked out of it and a combo
 * box's carries one, and "one" is a number a probe can measure: draw the chip, walk the column down its middle, and
 * count the runs of white. Two means the doubled arrow is back; zero means the chip drew and its mark did not.
 *
 * AND THE SECOND CLAIM IS THE DIRECTION, because one triangle could point either way. A down triangle has its widest
 * row at its TOP and an up triangle has it at its bottom, so the widest white row's position within the run is what
 * separates them — a property rather than a remembered number, which is what this tier's probes are for.
 *
 * A DRAWING IS THE UNIT HERE because the ink is what the sample specifies. Every claim below is taken from
 * `Argentum Mockup.png`'s own gallery, where the two controls are drawn on adjacent rows: the field is a one-point
 * bordered rectangle at radius four, the chip is 20 x 20 inset five points from the field's right border, and the
 * triangle is 10 points across and 5 tall. THE FIELD'S FILL IS THE ONE VALUE TAKEN FROM THIS TIER RATHER THAN THE
 * SAMPLE — every control here is slightly darker than the surface under it — and the check says so by name.
 */
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSActionCell.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>
#import <Foundation/NSAutoreleasePool.h>
#include <math.h>
#include <stdio.h>

static int failures = 0;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static int is_accent(NSColor *c)
{
	return c != nil
		&& fabs([c redComponent] - 0.643) < 0.02
		&& fabs([c greenComponent] - 0.604) < 0.02
		&& fabs([c blueComponent] - 1.0) < 0.02;
}

/* **AND "WHITE" MEANS WHITE HERE, NOT "LIGHT".** The first draft of this helper asked for anything above 0.87, which
 * the field's OWN FACE passes — it is the control grey, 0.90 — so the run counter was walking a column of face and
 * reporting one enormous run instead of the chip's mark. THE KNOCKED-OUT TRIANGLES ARE THE FIELD'S WHITE, `1.0`, and
 * the accent they sit on is 0.64, so the threshold belongs between those two and nowhere else. */
static int whiteish(NSColor *c)
{
	return c != nil && [c redComponent] > 0.95 && [c greenComponent] > 0.95 && [c blueComponent] > 0.95;
}

/* ---- THE TWO CONTROLS, DRAWN THE SAME WAY, SO THEY CAN BE COMPARED ---------------------------------- */

static NSBitmapImageRep *draw_cell(NSObject *cell, int W, int H, NSView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	/* **THE CONTEXT COMES FIRST, WHICH IS NOT A STYLE CHOICE: A COLOUR CANNOT BE SET AS THE FILL WITHOUT ONE.** An
	 * earlier draft of this helper filled the ground before it had a destination and the layer said so — `-setFill`
	 * needs a current graphics context and a colour — which is worth keeping in mind as the shape every offscreen
	 * probe in this tree has to take.
	 *
	 * AND THE GROUND IS WHITE, deliberately: the field's own face is the control grey, so a field measured against the
	 * surface it sits on would be two things three levels apart. */
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[(id)cell drawWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H) inView:view];
	return rep;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	const int W = 140, H = 23;
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
	NSComboBoxCell *combo = [[NSComboBoxCell alloc] initTextCell:@"NSComboBox"];
	NSPopUpButtonCell *popup = [[NSPopUpButtonCell alloc] initTextCell:@"NSPopUpButton" pullsDown:NO];
	NSBitmapImageRep *rep;
	CGFloat zone = (CGFloat)H * (NS_CELL_CHIP_FRACTION + NS_CELL_CHIP_INSET_FRACTION);
	int zoneLeft = W - (int)ceil(zone);
	int chipMidX = zoneLeft + (int)ceil((CGFloat)H * NS_CELL_CHIP_FRACTION) / 2;
	int y, runs = 0, widest = 0, widestY = -1, first = -1, last = -1;
	int comboLeft = -1, comboRight = -1, popupLeft = -1, popupRight = -1;
	int x;

	[combo setBordered:YES];
	[combo setBezeled:YES];
	[popup setBordered:YES];
	[popup setBezeled:YES];

	/* 1. **THE FIELD IS A FIELD, AND IT IS THIS TIER'S GREY RATHER THAN THE SAMPLE'S WHITE.** */
	rep = draw_cell(combo, W, H, view);
	check(fabs([[rep colorAtX:W / 2 y:H - 1 - (H - 2)] redComponent] - [[NSColor controlColor] redComponent]) < 0.01,
	      "the field's face is the CONTROL's grey — the same face the pop-up and the push button wear");
	/* **AND THE BORDER IS THE FIRST THING UNDER THE WHITE GROUND AT THE FIELD'S TOP EDGE.** Sampling a remembered row
	 * would be a claim about the FRAME rather than about the ink; walking down the column until the ground stops is a
	 * claim about where the border actually is, which is what the check is for. */
	{
		int borderY = -1;

		for (y = 0; y < H; y++) {
			if (fabs([[rep colorAtX:W / 2 y:y] redComponent] - 1.0) > 0.01) {
				borderY = y;
				break;
			}
		}
		printf("  (note: the field's top edge is at y=%d)\n", borderY);
		check(borderY >= 0 && borderY <= 2
		      && fabs([[rep colorAtX:W / 2 y:borderY] redComponent]
			      - [[NSColor controlDarkShadowColor] redComponent]) < 0.10,
		      "and its border is the border's own grey, drawn at the field's own top edge");
	}
	[rep release];

	/* 2. **THE CHIP'S ZONE, AND THE MARK INSIDE IT.** */
	rep = draw_cell(combo, W, H, view);
	{
		int accent = 0;

		for (y = 0; y < H; y++) {
			for (x = zoneLeft; x < W; x++) {
				if (is_accent([rep colorAtX:x y:y])) {
					accent++;
					if (comboLeft < 0 || x < comboLeft) comboLeft = x;
					if (x > comboRight) comboRight = x;
				}
			}
		}
		check(accent > 100, "the CHIP is drawn, in the platform's accent");
		/* AND THE CHIP'S OWN ROW IS ITS MIDDLE, which is where a triangle's centre column is measured from. */
		for (y = 0; y < H; y++) {
			NSColor *c = [rep colorAtX:chipMidX y:y];
			int w = whiteish(c);

			if (w && first < 0) first = y;
			if (w) last = y;
			if (w && !whiteish([rep colorAtX:chipMidX y:y - 1])) runs++;
		}
		for (y = 0; y < H; y++) {
			int n = 0;
			NSColor *c;

			for (x = zoneLeft; x < W; x++) {
				if (whiteish([rep colorAtX:x y:y])) n++;
			}
			if (n > widest) { widest = n; widestY = y; }
		}
		printf("  (note: chip x=%d..%d, centre column %d, white runs %d, widest %d px at y=%d, run y=%d..%d)\n",
		       comboLeft, comboRight, chipMidX, runs, widest, widestY, first, last);
		check(runs == 1, "ONE white run down the chip's centre column — the single arrow, where the pop-up has two");
		check(widest >= 8, "and the triangle is a triangle: its widest row is 10 points across the 20-point chip");
		check(widestY < (first + last) / 2,
		      "with that widest row in the UPPER half of the run — a DOWN triangle, base up and apex down");
		check((last - first + 1) <= 6, "and it is 5 points tall, apex to base, as the sample's is");
	}
	[rep release];

	/* 3. **AND THE CHIP LANDS WHERE THE POP-UP'S DOES, WHICH IS WHAT SHARING THE MEASURES MEANS.** */
	rep = draw_cell(popup, W, H, view);
	for (y = 0; y < H; y++) {
		for (x = zoneLeft; x < W; x++) {
			if (is_accent([rep colorAtX:x y:y])) {
				if (popupLeft < 0 || x < popupLeft) popupLeft = x;
				if (x > popupRight) popupRight = x;
			}
		}
	}
	[rep release];
	check(comboLeft == popupLeft && comboRight == popupRight,
	      "the two chips occupy the SAME points — one field, one chip, two controls");

	/* 4. **THE TITLE'S MARGIN, WHICH IS THE CHECKBOX'S RATHER THAN THE FIELD'S EDGE.** */
	rep = draw_cell(combo, W, H, view);
	{
		int leftmostInk = -1;

		for (x = 0; x < zoneLeft && leftmostInk < 0; x++) {
			for (y = 0; y < H; y++) {
				if ([[rep colorAtX:x y:y] redComponent] < 0.5) {
					leftmostInk = x;
					break;
				}
			}
		}
		printf("  (note: title ink from x=%d of %d)\n", leftmostInk, zoneLeft);
		check(leftmostInk >= (int)NS_CELL_CONTENT_GAP && leftmostInk <= (int)NS_CELL_CONTENT_GAP + 3,
		      "and the title begins at NS_CELL_CONTENT_GAP — the margin a checkbox leaves its label");
	}
	[rep release];

	/* 5. **AND THE MEASUREMENT CARRIES THE CHIP, BUT NOT THE MARGIN — THE BASE PAYS THAT ONE.** The claim is not that
	 * the frame is wide; it is that the DIFFERENCE between this cell and a BORDERED bare one with the same title is
	 * exactly the chip's zone. BOTH SIDES ARE BORDERED ON PURPOSE: `NSCell`'s own measurement pays
	 * `NS_CELL_CONTENT_GAP` for a bordered cell — MEASURED, 91.67 points bare against 95.67 bordered — so comparing
	 * against an unbordered one would fold that margin into the difference and quietly assert a double count. It is
	 * the defect the pop-up's version of this door shipped once and corrects, and this probe's shape is what caught
	 * it. */
	{
		NSRect probe = NSMakeRect(0.0, 0.0, 1000.0, (CGFloat)H);
		NSActionCell *plain = [[NSActionCell alloc] initTextCell:@"NSComboBox"];
		NSSize measured;
		NSSize bare;
		CGFloat zoneOnly = (CGFloat)H * (NS_CELL_CHIP_FRACTION + NS_CELL_CHIP_INSET_FRACTION);

		[plain setBordered:YES];
		measured = [combo cellSizeForBounds:probe];
		bare = [plain cellSizeForBounds:probe];
		printf("  (note: 'NSComboBox' measures %.2f wide and %.2f on a bordered bare cell; the chip's zone is "
		       "%.2f)\n", (double)measured.width, (double)bare.width, (double)zoneOnly);
		check(fabs((measured.width - bare.width) - zoneOnly) < 0.51,
		      "the frame is wider than a bordered cell's by the chip's ZONE and nothing else");
		check((measured.width - zoneOnly) >= bare.width - 0.51,
		      "so the margin the title begins at is IN the base's answer rather than taken out of the words");
		[plain release];
	}

	/* 6. **AND A STRING THAT ARRIVES AFTER THE CELL IS MADE IS MEASURED TOO, WHICH IS THE BUG THIS PROBE EXISTS FOR.**
	 * A control makes its cell with an EMPTY string and sets the text later — that is what `-selectItemAtIndex:` and
	 * every keystroke do — and `NSCell` keeps a cell's text in two places, of which `-cellSizeForBounds:` reads one and
	 * `-stringValue` the other. MEASURED before the fix: this cell measured 19.61 points with a two-word string in it,
	 * drew a clipped "N", and the demo's combo box was a stub 20 points wide. A probe that only ever made cells WITH
	 * their strings — which is how the four checks above are written, and how a careless test would stop — could not
	 * have seen it. */
	{
		NSRect probe = NSMakeRect(0.0, 0.0, 1000.0, (CGFloat)H);
		NSComboBoxCell *late = [[NSComboBoxCell alloc] initTextCell:@""];
		NSSize before;
		NSSize after;

		[late setBordered:YES];
		[late setBezeled:YES];
		before = [late cellSizeForBounds:probe];
		[late setStringValue:@"NSComboBox"];
		after = [late cellSizeForBounds:probe];
		printf("  (note: a cell made empty measures %.2f, and %.2f once the string arrives)\n",
		       (double)before.width, (double)after.width);
		check(after.width > before.width + 50.0,
		      "a string that arrives AFTER the cell is made is measured too — the control-built path");
		check(fabs(after.width - 117.78) < 1.0,
		      "and it measures the same as a cell that was made with that string, so the two paths agree");
		[late release];
	}

	[combo release];
	[popup release];
	[view release];
	[pool release];
	printf("combo_box: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
