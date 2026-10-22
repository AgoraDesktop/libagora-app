/*
 * text_field_bezel.m — A FIELD'S TWO BORDER SHAPES, WHICH ARE THE SAME FACE WITH ITS CORNERS CUT OR NOT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A BEZEL STYLE IS A CLAIM ABOUT PIXELS, SO THIS PROBE READS PIXELS.** `NSTextFieldBezelStyle` has two cases —
 * square and rounded — and the only thing that differs between them is whether the border's corners take
 * `NS_CELL_BEZEL_RADIUS`. That is not a fact a caller can read back from an ivar and believe; it is a fact about where
 * the INK falls. So the cell is drawn into a bitmap rep, offset into a FRESH WHITE SURFACE, and the four CORNER
 * pixels are the instrument: a square field's border runs through all four, and a rounded field's arc leaves all four
 * empty.
 *
 * **AND THE CLAIM IS DOUBLED, BECAUSE "SQUARE MINUS ROUNDED" COULD BE SATISFIED BY A FIELD THAT DREW NOTHING.** Every
 * corner check is paired with a check that the MIDDLE of an edge carries ink at BOTH settings — so a border that
 * stopped being drawn would fail the pair rather than pass the difference. And the two settings are then checked to
 * share every measure that is NOT the corner (the text rect and the cell's own size), which is what "the same face
 * with its corners not cut" means.
 *
 * Offscreen, into a bitmap rep: no display, no window, no run loop.
 */
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>

#define W 60
#define H 24

static int failures = 0;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* **THE BORDER'S INK, READ AGAINST THE SAME THRESHOLD `control_ink.m` USES.** The border is `+controlDarkShadowColor`
 * and the field's face is white, so "drawn in a colour this dark at this point" is what a border pixel is; nothing
 * else in this rep is below the threshold. */
static int is_ink(NSBitmapImageRep *rep, int x, int y)
{
	NSColor *c = [rep colorAtX:x y:y];

	return c != nil && [c redComponent] < 0.80;
}

/* **AND THE FOUR CORNERS, COUNTED, SO A `0` IS AS MUCH A RESULT AS A `4`.** The rep's rows count from the top and the
 * four corners are four corners whichever way round that is, so the count does not depend on the orientation. */
static int corner_ink(NSBitmapImageRep *rep)
{
	return is_ink(rep, 0, 0) + is_ink(rep, W - 1, 0) + is_ink(rep, 0, H - 1) + is_ink(rep, W - 1, H - 1);
}

/* A point on an EDGE and clear of any corner: the middle of the top row. Every shape this file draws has ink here. */
static int edge_ink(NSBitmapImageRep *rep)
{
	return is_ink(rep, W / 2, 0);
}

/* DRAW A CELL into a fresh rep over a white surface, the way `control_ink.m` draws a view — so every measurement
 * starts from the same ground and the corner reads are reads of the BORDER rather than of whatever was there first. */
static NSBitmapImageRep *draw_cell(NSTextFieldCell *cell)
{
	NSBitmapImageRep *rep = new_rep();
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[cell drawWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H) inView:view];
	[view release];
	return rep;
}

/* **AND THE SAME DRAW THROUGH THE CONTROL**, which is the half that proves the forward reaches the cell: `-drawRect:`
 * is the path a window uses, and it hands the cell the view's own bounds. */
static NSBitmapImageRep *draw_view(NSView *view)
{
	NSBitmapImageRep *rep = new_rep();

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[view drawRect:[view bounds]];
	return rep;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"Wg"];
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
	NSRect frame = NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H);
	NSBitmapImageRep *roundedRep;
	NSBitmapImageRep *squareRep;

	[cell setBordered:YES];
	[cell setBezeled:YES];

	/* 1. **A FRESH FIELD IS ROUNDED, WHICH IS THE DEFAULT THAT MATTERS BECAUSE ZERO IS SQUARE.** The two cases are
	 * the opposite way round from the button family's — `NSRoundedBezelStyle` is 1 there and zero is not a bezel at
	 * all — so a cell that trusted its zeroed ivar would come out square. */
	check([cell bezelStyle] == NSTextFieldRoundedBezel,
	      "a fresh field cell is ROUNDED, which zeroing an ivar would get backwards");

	/* 2. **ROUNDED: THE ARCS LEAVE ALL FOUR CORNERS EMPTY, AND THE BORDER IS STILL THERE.** */
	roundedRep = draw_cell(cell);
	printf("  (note: rounded — corner ink %d of 4, top-edge ink at the middle %d)\n",
	       corner_ink(roundedRep), edge_ink(roundedRep));
	check(corner_ink(roundedRep) == 0, "a ROUNDED field's border leaves all four corner pixels empty");
	check(edge_ink(roundedRep), "while its border is drawn — the middle of the top edge carries ink");

	/* 3. **SQUARE: THE SAME BORDER RUNS THROUGH ALL FOUR CORNERS.** */
	[cell setBezelStyle:NSTextFieldSquareBezel];
	check([cell bezelStyle] == NSTextFieldSquareBezel, "the cell answers the square style it was given");
	squareRep = draw_cell(cell);
	printf("  (note: square — corner ink %d of 4, top-edge ink at the middle %d)\n",
	       corner_ink(squareRep), edge_ink(squareRep));
	check(corner_ink(squareRep) == 4, "a SQUARE field's border passes through all four corner pixels");
	check(edge_ink(squareRep), "and draws the same edge the rounded one does");

	/* 4. **AND THE TWO ARE THE SAME FIELD: EVERY MEASURE THAT IS NOT THE CORNER AGREES.** A square field is not a
	 * second face — it is this one with its corners not cut — so the text rect and the cell's own size are the same
	 * at either setting. The text rect is the one a caller notices, because it is where the words live and what an
	 * edit session is handed. */
	{
		NSRect squareText;
		NSRect roundedText;
		NSSize squareSize;
		NSSize roundedSize;

		[cell setBezelStyle:NSTextFieldRoundedBezel];
		roundedText = [cell drawingRectForBounds:frame];
		roundedSize = [cell cellSizeForBounds:frame];
		[cell setBezelStyle:NSTextFieldSquareBezel];
		squareText = [cell drawingRectForBounds:frame];
		squareSize = [cell cellSizeForBounds:frame];
		check(NSEqualRects(squareText, roundedText),
		      "the TEXT RECT is the same at either style — a square field is not a second face");
		check(NSEqualSizes(squareSize, roundedSize),
		      "and so is the cell's own measurement, because a field's bezel changes no metric");
	}

	/* 5. **AND THE CONTROL FORWARDS IT, WHICH IS THE HALF A CALLER ACTUALLY TOUCHES.** A fresh field is rounded;
	 * setting the style on the CONTROL reaches the cell; and the control's own `-drawRect:` — the path a window uses —
	 * then draws square corners. */
	{
		NSBitmapImageRep *controlRep;

		check([field bezelStyle] == NSTextFieldRoundedBezel, "a fresh field CONTROL is rounded too");
		[field setBezelStyle:NSTextFieldSquareBezel];
		check([field bezelStyle] == NSTextFieldSquareBezel,
		      "setting the style on the control answers it back from the control");
		check([(NSTextFieldCell *)[field cell] bezelStyle] == NSTextFieldSquareBezel,
		      "and it reached the CELL, which is what draws");
		controlRep = draw_view(field);
		printf("  (note: square through the control — corner ink %d of 4)\n", corner_ink(controlRep));
		check(corner_ink(controlRep) == 4,
		      "and the control's OWN `-drawRect:` draws the square corners, so the forward is wired to the ink");
		[controlRep release];
	}

	[squareRep release];
	[roundedRep release];
	[field release];
	[cell release];
	[pool release];
	printf("text_field_bezel: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
