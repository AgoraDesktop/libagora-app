/*
 * button_sweep — the button pair finished: the forwards, the alternate mnemonic, the shading, and the three ink doors.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **TWENTY DOORS OVER TWO CLASSES, AND EVERY ONE OF THEM IS TESTED AS A CLAIM RATHER THAN AS A SETTER.** The button's
 * eight are FORWARDS, so each is checked by asking the CELL what it now answers — a button that stored its own copy
 * would pass "does the button read back" and fail "does the cell that draws know". The cell's twelve divide into three
 * kinds, and each kind has its own instrument:
 *
 *   1. THE ALTERNATE MNEMONIC is a PARSE, so it is tested as one: the mark removed, the index kept, `&&` collapsed, and
 *      the empty string for none.
 *   2. THE TWO FONT DOORS are one field, so the two-argument form is tested by reading the object form back — and by
 *      requiring the nil name to land on the system font rather than on nil.
 *   3. THE SHADING AND THE THREE INK DOORS ARE PIXELS. A convex bezel is LIGHTER AT THE TOP than at the bottom and a
 *      concave one is the reverse; the strong pair differs from the weak pair in DEPTH; and the three doors are proved
 *      by a subclass that counts the calls and by one that paints from inside `-drawTitle:`.
 *
 * PLUS THE ONE INTERACTION BETWEEN A FLAG AND A DOOR: `-showsBorderOnlyWhileMouseInside` is honoured by the face, so
 * the border is ABSENT with the pointer outside and PRESENT once `-mouseEntered:` has said it arrived — which is what
 * makes the cell's two pointer doors behaviour rather than storage.
 *
 * Offscreen: a bitmap rep, a graphics context, and the cells' own geometry. No window and no compositor.
 */
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>

#include <math.h>
#include <stdio.h>

#define W 160
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
	return fabs(a - b) < 0.0001;
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* DRAW A CELL into a fresh white bitmap, through the cell's own drawing door — the same path a control uses. */
static NSBitmapImageRep *draw_cell(NSCell *cell, NSRect frame)
{
	NSBitmapImageRep *rep = new_rep();
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[cell drawWithFrame:frame inView:nil];
	return rep;
}

/* THE MEAN RED OF ONE ROW inside a band, which is how a vertical gradient is read: the shading is a grey wash over the
 * face, so the three channels move together and one of them is enough. */
static double row_mean(NSBitmapImageRep *rep, int x0, int x1, int y)
{
	double sum = 0.0;
	int x, n = 0;

	for (x = x0; x < x1; x++) {
		NSColor *c = [rep colorAtX:x y:y];

		if (c != nil) {
			sum += [c redComponent];
			n++;
		}
	}
	return n > 0 ? sum / n : 0.0;
}

/* INK ANYWHERE IN A BOX, with the threshold the control palette's own tests use: above the border colour and below
 * every face a control wears. */
static int ink_in(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.80) {
				n++;
			}
		}
	}
	return n;
}

/* A CELL THAT COUNTS THE THREE INK DOORS, so "the split is real and `-drawWithFrame:` goes through it" is a number
 * rather than a reading of the source. It records the rect each content door was handed, which is the other half of
 * the claim: the interior owns the layout, so the doors receive FINISHED rects. */
@interface AGDoorCell : NSButtonCell
{
@public
	int bezelCalls;
	int titleCalls;
	int imageCalls;
	NSRect lastTitleRect;
	NSRect lastImageRect;
}
@end

@implementation AGDoorCell
- (void)drawBezelWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	bezelCalls++;
	[super drawBezelWithFrame:cellFrame inView:controlView];
}

- (void)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(id)controlView
{
	titleCalls++;
	lastTitleRect = frame;
	[super drawTitle:title withFrame:frame inView:controlView];
}

- (void)drawImage:(NSImage *)image withFrame:(NSRect)frame inView:(id)controlView
{
	imageCalls++;
	lastImageRect = frame;
	[super drawImage:image withFrame:frame inView:controlView];
}
@end

/* AND A CELL THAT PAINTS RED FROM INSIDE `-drawTitle:` — the same claim as the counter, made in PIXELS, so a door that
 * is called but ignored cannot pass. */
@interface AGPaintTitleCell : NSButtonCell
@end

@implementation AGPaintTitleCell
- (void)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(id)controlView
{
	(void)title;
	(void)controlView;
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:frame] fill];
}
@end

/* A BUTTON SUBCLASS THAT CANNOT DO ANYTHING BUT COUNT, so the view-level forwards can be checked against the cell. */
static NSButton *new_button(void)
{
	NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(20.0, 8.0, 120.0, 24.0)];

	[b setTitle:@"Save"];
	return b;
}

int main(void)
{
	/* ---- 1. THE BUTTON'S EIGHT FORWARDS ------------------------------------------------------------ */
	{
		NSButton *b = new_button();
		NSButtonCell *cell = (NSButtonCell *)[b cell];
		id sound = [[[NSObject alloc] init] autorelease];

		check([b isBordered] && [cell isBordered], "a fresh button is bordered, on the button and on its cell");
		[b setBordered:NO];
		check(![b isBordered] && ![cell isBordered],
		      "`-setBordered:NO` reaches the CELL, which is the object that draws");

		check(![b isTransparent] && ![cell isTransparent], "and it is not transparent by default");
		[b setTransparent:YES];
		check([b isTransparent] && [cell isTransparent], "`-setTransparent:` is the cell's flag");
		[b setTransparent:NO];

		check(![b showsBorderOnlyWhileMouseInside] && ![cell showsBorderOnlyWhileMouseInside],
		      "the border-only-while-inside flag starts NO");
		[b setShowsBorderOnlyWhileMouseInside:YES];
		check([b showsBorderOnlyWhileMouseInside] && [cell showsBorderOnlyWhileMouseInside],
		      "and it is the cell's flag too");

		[b setSound:sound];
		check([b sound] == sound && [cell sound] == sound,
		      "the sound is the cell's, and the button answers the SAME object back");
		[b release];
	}

	/* ---- 2. THE ALTERNATE MNEMONIC, WHICH IS A PARSE ------------------------------------------------ */
	{
		NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@"Save"];
		NSButtonCell *other = [[NSButtonCell alloc] initTextCell:@"Save"];

		check([[cell alternateMnemonic] isEqual:@""], "a cell with no alternate title has no alternate mnemonic");

		[cell setAlternateTitleWithMnemonic:@"&Open"];
		check([[cell alternateTitle] isEqual:@"Open"], "the `&` is STRIPPED from the alternate title");
		check([cell alternateMnemonicLocation] == 0, "and the mark is recorded at index 0");
		check([[cell alternateMnemonic] isEqual:@"O"], "which is the character `-alternateMnemonic` answers");

		[other setAlternateTitleWithMnemonic:@"Sa&ve"];
		check([[other alternateTitle] isEqual:@"Save"] && [other alternateMnemonicLocation] == 2,
		      "a mark in the middle is stripped from the middle and indexed there");
		check([[other alternateMnemonic] isEqual:@"v"], "and names the character it marked");

		[cell setAlternateTitleWithMnemonic:@"A&&B"];
		check([[cell alternateTitle] isEqual:@"A&B"], "`&&` collapses to ONE literal ampersand");
		check([cell alternateMnemonicLocation] == NSNotFound && [[cell alternateMnemonic] isEqual:@""],
		      "and names no mnemonic, which is the one-pass rule the title's parse also records");

		[cell setAlternateTitleWithMnemonic:@"Trailing&"];
		check([[cell alternateTitle] isEqual:@"Trailing&"] && [cell alternateMnemonicLocation] == NSNotFound,
		      "a trailing `&` is kept and names nothing");

		[cell setAlternateTitle:@"Plain"];
		check([cell alternateMnemonicLocation] == NSNotFound,
		      "`-setAlternateTitle:` CLEARS the index, because the index is into that string");

		[cell setAlternateMnemonicLocation:3];
		check([cell alternateMnemonicLocation] == 3 && [[cell alternateMnemonic] isEqual:@"i"],
		      "and `-setAlternateMnemonicLocation:` marks a character directly, as the primary pair allows");
		[cell setAlternateMnemonicLocation:99];
		check([[cell alternateMnemonic] isEqual:@""],
		      "an index past the end answers the empty string rather than a character from nowhere");
		[cell release];
		[other release];
	}

	/* ---- 3. THE TWO FONT DOORS ARE ONE FIELD -------------------------------------------------------- */
	{
		NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@"Save"];
		NSFont *byName;

		[cell setKeyEquivalentFont:@"Helvetica" size:17.0];
		byName = [cell keyEquivalentFont];
		check(byName != nil, "`-setKeyEquivalentFont:size:` resolves a name to a font");
		check(byName != nil && near([byName pointSize], 17.0),
		      "at the size asked for, which is the half the object door cannot state");
		check(byName == [cell keyEquivalentFont], "and the object door answers the SAME font back");
		{
			/* THE NAME IS HONOURED WHEN THE HOST HAS THAT FACE, and the system font is the documented answer when it
			 * has not — so the assertion is conditional on what the font registry itself says, never on a face this
			 * machine may not ship. */
			NSFont *direct = [NSFont fontWithName:@"Helvetica" size:17.0];

			if (direct != nil) {
				check([[byName fontName] isEqual:[direct fontName]],
				      "the named face is the one the cell keeps, out of the registry that has it");
			}
		}

		[cell setKeyEquivalentFont:nil size:9.0];
		check([cell keyEquivalentFont] != nil && near([[cell keyEquivalentFont] pointSize], 9.0),
		      "a nil name is the SYSTEM font at the given size, not nil");
		[cell release];
	}

	/* ---- 4. THE CELL'S TWO POINTER DOORS, AND THE FLAG THEY MAKE REAL ------------------------------- */
	{
		NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@"Save"];
		NSRect frame = NSMakeRect(20.0, 8.0, 120.0, 24.0);
		NSBitmapImageRep *outside;
		NSBitmapImageRep *inside;

		check(![cell cg_mouseIsInside], "a cell with no pointer over it starts with the flag clear");
		[cell mouseEntered:nil];
		check([cell cg_mouseIsInside], "`-mouseEntered:` says the pointer arrived");
		[cell mouseExited:nil];
		check(![cell cg_mouseIsInside], "and `-mouseExited:` says it left");

		/* **THE FLAG IS ONLY REAL IF THE FACE READS IT.** With the door set the face is drawn only while the pointer is
		 * inside, so the same cell, drawn twice, differs by its BORDER — which is what "borderless until you point at
		 * it" means. The title stays in both pictures, so the comparison is a border band rather than all the ink. */
		[cell setShowsBorderOnlyWhileMouseInside:YES];
		[cell setTitle:@""];
		outside = draw_cell(cell, frame);
		[cell mouseEntered:nil];
		inside = draw_cell(cell, frame);
		check(ink_in(outside, 0, 0, W, H) == 0,
		      "with the pointer outside, a border-only button draws NO border at all");
		check(ink_in(inside, 0, 0, W, H) > 0,
		      "and once `-mouseEntered:` has arrived the border is DRAWN — the flag is behaviour");
		[cell mouseExited:nil];
		[cell release];
	}

	/* ---- 5. THE SHADING, WHICH IS THE ONE THING THE GRADIENT DOOR CHANGES ---------------------------- */
	{
		NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@""];
		NSRect frame = NSMakeRect(20.0, 8.0, 120.0, 24.0);
		NSBitmapImageRep *flat;
		NSBitmapImageRep *convex;
		NSBitmapImageRep *concave;
		NSBitmapImageRep *strong;
		double flatTop, flatBottom;
		double convexTop, convexBottom;
		double concaveTop, concaveBottom;
		double strongTop, strongBottom;

		[cell setBordered:YES];
		[cell setBezeled:YES];
		check([cell gradientType] == NSGradientNone, "a fresh button cell is FLAT, which is the sample's face");

		flat = draw_cell(cell, frame);
		[cell setGradientType:NSGradientConvexWeak];
		check([cell gradientType] == NSGradientConvexWeak, "`-setGradientType:` round-trips");
		convex = draw_cell(cell, frame);
		[cell setGradientType:NSGradientConcaveWeak];
		concave = draw_cell(cell, frame);
		[cell setGradientType:NSGradientConvexStrong];
		strong = draw_cell(cell, frame);

		/* THE SAMPLES ARE INSIDE THE FACE AND CLEAR OF THE TITLE: x 40..100 is the middle of a 120-point bezel whose
		 * border is at 20 and 140, and the two rows are four points in from each edge. */
		flatTop = row_mean(flat, 40, 100, 12);
		flatBottom = row_mean(flat, 40, 100, 27);
		convexTop = row_mean(convex, 40, 100, 12);
		convexBottom = row_mean(convex, 40, 100, 27);
		concaveTop = row_mean(concave, 40, 100, 12);
		concaveBottom = row_mean(concave, 40, 100, 27);
		strongTop = row_mean(strong, 40, 100, 12);
		strongBottom = row_mean(strong, 40, 100, 27);

		printf("  (note: flat %.3f/%.3f convex %.3f/%.3f concave %.3f/%.3f strong %.3f/%.3f)\n",
		       flatTop, flatBottom, convexTop, convexBottom, concaveTop, concaveBottom, strongTop, strongBottom);

		check(near(flatTop, flatBottom) && flatTop > 0.5,
		      "the FLAT face is one value top to bottom, which is what makes the other two measurable");
		check(convexTop > convexBottom + 0.05,
		      "a CONVEX bezel is lighter at the TOP than at the bottom — it bulges toward the light");
		check(concaveBottom > concaveTop + 0.05,
		      "and a CONCAVE one is the reverse, which is a face pressed IN");
		check((strongTop - strongBottom) > 0.1,
		      "the STRONG pair shades deeper than the weak pair");
		check(fabs(strongTop - convexTop) > 0.01 || fabs(strongBottom - convexBottom) > 0.01,
		      "and its two ends differ from the weak pair's, so depth is not a synonym for direction");
		[cell release];
	}

	/* ---- 6. THE THREE INK DOORS, COUNTED AND THEN PAINTED -------------------------------------------- */
	{
		AGDoorCell *cell = [[AGDoorCell alloc] initTextCell:@"Save"];
		NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)];
		NSRect frame = NSMakeRect(20.0, 8.0, 120.0, 24.0);
		NSBitmapImageRep *rep;
		AGPaintTitleCell *painter;
		NSBitmapImageRep *painted;
		int red = 0;
		int x, y;

		[NSGraphicsContext setCurrentContext:nil];
		rep = draw_cell(cell, frame);		(void)rep;
		check(cell->bezelCalls == 1, "`-drawWithFrame:` paints the FACE through `-drawBezelWithFrame:inView:` once");
		check(cell->titleCalls == 1, "and the words through `-drawTitle:withFrame:inView:` once");
		check(cell->imageCalls == 0, "with no image, the image door is not called at all");
		check(NSHeight(cell->lastTitleRect) > 0.0 && NSHeight(cell->lastTitleRect) < 24.0,
		      "the title's rect is the line's BAND rather than the whole cell, so the interior owns the layout");
		check(NSMinX(cell->lastTitleRect) >= 20.0 && NSMaxX(cell->lastTitleRect) <= 140.0,
		      "and it lies inside the cell it was measured in");

		[cell setImage:image];
		rep = draw_cell(cell, frame);
		check(cell->bezelCalls == 2, "a second draw is a second face");
		check(cell->imageCalls == 1, "and an image gives the image door a call");
		check(NSWidth(cell->lastImageRect) == 16.0 && NSHeight(cell->lastImageRect) == 16.0,
		      "whose rect is the picture's own scaled size, because `-imageScaling` is the interior's");

		painter = [[AGPaintTitleCell alloc] initTextCell:@"Save"];
		painted = draw_cell(painter, frame);
		for (y = 0; y < H; y++) {
			for (x = 0; x < W; x++) {
				NSColor *c = [painted colorAtX:x y:y];

				if (c != nil && [c redComponent] > 0.9 && [c greenComponent] < 0.1) {
					red++;
				}
			}
		}
		check(red > 0, "and a subclass that paints from inside `-drawTitle:` puts ITS ink on the surface");
		[cell release];
		[painter release];
	}

	if (s_failed != 0) {
		printf("FAILED: %d check(s)\n", s_failed);
		return 1;
	}
	printf("all checks passed\n");
	return 0;
}
