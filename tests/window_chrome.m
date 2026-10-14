/*
 * window_chrome — is the title bar Agora's, and is it the shapes it says it is?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE CHROME IS THE CLIENT'S, SO IT CAN BE DRAWN WITHOUT A COMPOSITOR — AND THAT IS WHY THIS FILE CAN EXIST.**
 * The window server draws no title bar (see `agora-shell.xml`: its share of the model is the shadow, the work area
 * and the Z-order), so the strip is `NSWindow`'s own drawing and `-cg_drawChromeInContext:` hands it the context a
 * caller already has. This test hands it a bitmap rep's and then asks the PIXELS, which is the only place a claim
 * about a shape is worth anything: "the close symbol is an X and not a circle" is not a fact about the code that
 * chose to draw lines.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. The strip is filled, from one end to the other, in the frame colour.
 *   2. The three symbols are DRAWN at the left, one ink for all of them, and each one only if its style-mask bit
 *      is set — and they are SHAPES: ink on both diagonals of the X, ink above the minus and none beside it, ink
 *      above the plus. A circle would satisfy none of the three.
 *   3. The stroke is THICK — three points, measured as the ink's extent across the minus.
 *   4. The title is CENTRED in the strip and BOLD, the second of those measured against the same string drawn in
 *      the two faces rather than against a number.
 *   5. The pill is at the right end, filled like a control and bordered like one, and ROUNDED — its corner is the
 *      strip, which is what a rounded rectangle's corner is and what a square one's is not.
 *   6. A title too long for the room between the two blocks is CUT rather than run under them.
 */
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>	/* NSFontAttributeName — what a face is called in an attributes dictionary */
#import <AppKit/NSColor.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSApplication.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

/* THE WINDOW THIS IS DRAWN FOR: a content rectangle, plus the 22-point strip above it. The rep is the FRAME's size,
 * because that is the surface the chrome has rows in — which is the same reason a live window's buffer is the frame
 * and not the content. */
#define CW 300
#define CH 120
#define STRIP 22
#define FH (CH + STRIP)

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static NSColor *at(NSBitmapImageRep *rep, int x, int y)
{
	return [rep colorAtX:x y:y];
}

static double lum(NSColor *c)
{
	return c == nil ? 2.0 : ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3.0;
}

static int is_colour(NSColor *c, NSColor *want, double tol)
{
	return c != nil && want != nil
		&& fabs([c redComponent] - [want redComponent]) < tol
		&& fabs([c greenComponent] - [want greenComponent]) < tol
		&& fabs([c blueComponent] - [want blueComponent]) < tol;
}

/* INK IS DARK. The strip is 0.82 and the frame text colour is black, so one threshold separates them and nothing
 * else in the strip is near it — the pill's face is LIGHTER than the strip, which is why the pill is asked about by
 * colour below rather than by darkness. */
/* **INK IS "DARKER THAN THE STRIP", WHICH IS A DIFFERENT THRESHOLD SINCE THE MARKS STOPPED BEING BLACK.**
 * The chrome's marks and its pill are `+cg_chromeInkColor` (0.70) and the strip is `+windowFrameColor` (0.82), so the
 * fixed 0.5 this asked for while the marks were `+windowFrameTextColor` stopped finding them altogether — MEASURED, a
 * minus that drew at 0.70 read as "0 rows thick". What the question really is, everywhere below, is "is this pixel
 * part of a mark that was DRAWN rather than the surface it was drawn on", and 0.78 answers it: the strip is 0.82, and
 * both inks — the chrome's 0.70 and the title's black — are under it. */
static int ink_at(NSBitmapImageRep *rep, int x, int y)
{
	return lum(at(rep, x, y)) < 0.78;
}

static int ink_in(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y, n = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			if (ink_at(rep, x, y)) {
				n++;
			}
		}
	}
	return n;
}

/* **THE INK'S BOUNDING BOX IN A COLUMN RANGE**, which is how a title's width and its centre are measured without
 * asking the font anything: what was drawn is what can be seen. Returns NO when there is no ink at all. */
static int ink_box_range(NSBitmapImageRep *rep, int x0, int x1, int y0, int y1, int *outX0, int *outX1)
{
	int x, y, lo = -1, hi = -1;

	for (x = x0; x < x1; x++) {
		for (y = y0; y < y1; y++) {
			if (ink_at(rep, x, y)) {
				if (lo < 0) {
					lo = x;
				}
				hi = x;
				break;
			}
		}
	}
	if (lo < 0) {
		return 0;
	}
	*outX0 = lo;
	*outX1 = hi;
	return 1;
}

/* THE STRIP'S OWN BAND, which is what almost every question here is about; the text scratch reps below are taller and
 * ask about their own rows instead. */
static int ink_box(NSBitmapImageRep *rep, int x0, int x1, int *outX0, int *outX1)
{
	return ink_box_range(rep, x0, x1, 0, STRIP, outX0, outX1);
}

/* DRAW THE CHROME into a fresh rep, which is the whole of how this file reaches it. */
static NSBitmapImageRep *draw_chrome(NSWindow *w)
{
	NSBitmapImageRep *rep = new_rep(CW, FH);
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)FH)] fill];
	[w cg_drawChromeInContext:ctx];
	return rep;
}

/* ONE STRING IN ONE FACE, in a rep of its own, so the SAME string can be measured in two fonts. This is what makes
 * the boldness claim a measurement instead of a number copied out of a header. */
static int text_ink_width(NSFont *font, NSString *s)
{
	NSBitmapImageRep *rep = new_rep(240, 40);
	NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	NSDictionary *attrs = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
	int lo = 0, hi = 0;
	int found;

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 240.0, 40.0)] fill];
	[[NSColor blackColor] setFill];
	[s drawAtPoint:NSMakePoint(4.0, 4.0) withAttributes:attrs];
	found = ink_box_range(rep, 0, 240, 0, 40, &lo, &hi);
	[rep release];
	return found ? (hi - lo + 1) : 0;
}

int main(void)
{
	@autoreleasepool {
		NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)CH)
			styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
			backing:NSBackingStoreBuffered defer:NO];
		/* THE SYMBOLS' BOXES, in the rep's own coordinates — rows count from the TOP here, so the strip is rows
		 * 0..21 and the eleven-point boxes are centred in it at rows 5..15. x is the same at both ends of the
		 * conversion, so the three boxes are 8..19, 28..39 and 48..59: the strip's edge padding, then the symbol,
		 * then the gap, three times. */
		/* **AND THE BOXES ARE ON WHOLE POINTS, WHICH IS WHY THESE ROWS ARE ODD-NUMBERED.** The painter snaps the
		 * strip's eleven-point boxes with `floor`, so a three-point stroke has its centre on a half point and covers
		 * exactly three rows; the box therefore occupies rows 6..16 of this rep and its centre is 11. These read 5 and
		 * 15 until that snap — and the probes still landed on ink, which is exactly how a probe goes quietly wrong. */
		const int boxY0 = 6, boxY1 = 16;
		const int xX = 8, xM = 28, xP = 48;
		const int midY = (boxY0 + boxY1) / 2;

		[w setTitle:@"Controls"];

		/* 1. THE STRIP, which is the surface everything else in this file is drawn on. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);

			check(is_colour(at(rep, 70, 1), [NSColor windowFrameColor], 0.02),
			      "the strip is filled in the frame colour, in the row above the content");
			check(is_colour(at(rep, 70, STRIP + 6), [NSColor whiteColor], 0.02),
			      "and it does not run down into the content below it");
			[rep release];
		}

		/* 2. **THE THREE SYMBOLS, AS SHAPES.** Each check below is one shape's own geometry and would fail for the
		 * other two: the X inks two diagonals, the minus inks one horizontal and NOTHING above it, and the plus inks
		 * the horizontal AND the upright over the same centre. A circle — what used to be drawn — passes none. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);

			check(ink_at(rep, xX + 2, boxY0 + 1) && ink_at(rep, xX + 10, boxY0 + 1) && ink_at(rep, xX + 5, midY)
			      && !ink_at(rep, xX + 5, boxY0),
			      "the CLOSE symbol inks BOTH diagonals of its box and NOT its top middle — an X, not a dot");
			check(ink_at(rep, xM + 5, midY) && !ink_at(rep, xM + 1, boxY0 + 1) && !ink_at(rep, xM + 10, boxY0 + 1),
			      "the MINIATURIZE symbol inks one horizontal line and nothing above it — a minus");
			check(ink_at(rep, xP + 5, midY) && ink_at(rep, xP + 5, boxY0 + 1)
			      && !ink_at(rep, xP + 1, boxY0 + 1),
			      "and the ZOOM symbol inks the same line PLUS the upright through it — a plus");
			/* **AND THE MINUS ENDS IN A FACE, WHICH IS WHAT MAKES IT A RECTANGLE RATHER THAN A STROKE.** This is the
			 * check the last two rounds were missing, and it is about SHAPE: the ink at a rectangle's end column is
			 * its full END FACE — three rows of it, because that is how thick the bar is — where a round cap covers
			 * about a tenth of that column and leaves two rows half covered. MEASURED: 3 here, and 2 with the round caps
			 * this chrome used to be drawn with. Nothing about antialiasing or crispness would have found that, which is
			 * exactly why two rounds of looking at those did not. */
			{
				int row, x, first = -1, face = 0;

				for (x = xM - 2; x <= xM + 13 && first < 0; x++) {
					for (row = boxY0; row <= boxY1; row++) {
						if (lum(at(rep, x, row)) < 0.72) {
							first = x;
							break;
						}
					}
				}
				for (row = boxY0; row <= boxY1; row++) {
					if (first >= 0 && lum(at(rep, first, row)) < 0.72) {
						face++;
					}
				}
				printf("  (note: the minus's end face at column %d is %d rows tall)\n", first, face);
				check(face == 3, "and its end is a FACE rather than a cap — 3 rows of rectangle, not 2 of semicircle");
			}
			/* **THE THICKNESS AND THE CRISPNESS, WHICH ARE TWO DIFFERENT CLAIMS.** "Darker than the strip" is the
			 * first — that is what "very thick" means, and a blurred edge passes it just as well. The second is rows
			 * of PURE ink, to within the rep's own round trip: before the boxes were snapped onto whole points the
			 * minus was four rows with two of them half covered, and it read 2 then and reads 3 now. */
			{
				int y, rows = 0, pure = 0;

				for (y = 0; y < STRIP; y++) {
					if (ink_at(rep, xM + 5, y)) {
						rows++;
					}
					if (is_colour(at(rep, xM + 5, y), [NSColor cg_chromeInkColor], 0.02)) {
						pure++;
					}
				}
				printf("  (note: the minus is %d rows thick, %d of them pure ink)\n", rows, pure);
				check(rows >= 3 && rows <= 5, "the symbols are drawn with a VERY THICK stroke, not a hairline");
				check(pure == 3, "and its edges are not blended — 3 rows of ink, not 4 with two half covered");
			}
			[rep release];
		}

		/* 4. **THE TITLE IS CENTRED AND BOLD.** Centred is measured as the ink's own centre against the strip's,
		 * over the columns BETWEEN the two blocks — where the title is the only thing that can be drawn. Bold is
		 * measured against the same string in the two faces, so it says "this came from the emphasized face" rather
		 * than "this came from the face whose name I happen to have written down". */
		{
			NSBitmapImageRep *rep = draw_chrome(w);
			int lo = 0, hi = 0, leftEnd = xP + 11 + 4;
			int rightStart = CW - 8 - 30 - 4;
			int found = ink_box(rep, leftEnd, rightStart, &lo, &hi);
			double centre = found ? ((double)lo + (double)hi) / 2.0 : -1.0;
			int chromeWidth = found ? (hi - lo + 1) : 0;
			int boldWidth, plainWidth;

			printf("  (note: the title's ink runs x %d..%d, centre %.1f against the strip's %.1f; width %d)\\n",
			       lo, hi, centre, (double)CW / 2.0, chromeWidth);
			check(found, "the title is drawn in the strip");
			check(found && fabs(centre - (double)CW / 2.0) <= 2.0,
			      "and it is CENTRED — its ink's centre is the strip's, not the left end after the symbols");

			boldWidth = text_ink_width([NSFont boldSystemFontOfSize:[[NSFont titleBarFontOfSize:0.0] pointSize]],
						   [w title]);
			plainWidth = text_ink_width([NSFont systemFontOfSize:[[NSFont titleBarFontOfSize:0.0] pointSize]],
						    [w title]);
			printf("  (note: the same title measures %d in the emphasized face and %d in the regular one)\\n",
			       boldWidth, plainWidth);
			check(boldWidth > 0 && plainWidth > 0, "the same string can be measured in both faces");
			/* **CLOSER TO, RATHER THAN EQUAL TO.** The two measurements are the same string drawn at the same
			 * point, so an exact match is what one would expect — and it is NOT what happens: the scratch rep draws
			 * at an integer point and the chrome's title is centred, so the two land on different sub-pixel phases
			 * and the ink's width can differ by one row of coverage. The CLAIM is which face it came from, and the
			 * two faces differ by more than that (46 against 49 for this title), so the distance decides it. */
			check(boldWidth != plainWidth
			      && abs(chromeWidth - boldWidth) < abs(chromeWidth - plainWidth),
			      "and the title in the strip is the BOLD one — nearer the emphasized face than the regular one");
			[rep release];
		}

		/* 5. **THE PILL AT THE FAR END, AND ROUNDED.** The face is the control colour, the border is the control
		 * border, and the CORNER is the strip — which is the whole difference between a rounded rectangle and a
		 * square one, and cannot be satisfied by a rectangle. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);
			/* **THE PILL'S OWN WIDTH, FROM THE ARITHMETIC THE PAINTER USES: the strip's edge padding, then the
			 * shape.** 19.5 points puts the box's left edge on a half pixel — CW - 8 - 19.5 is 272.5 — so a probe
			 * that wants an integer column starts at 273, the first one the shape covers whole. This read
			 * `CW - 8 - 30` until the width changed, and then it was no longer the pill's edge but a column ten
			 * points to its LEFT: every check below went on passing, because they all landed inside the shape
			 * anyway, while the corner probe quietly began sampling empty strip and proving nothing at all. A probe
			 * derived from a constant that has since moved is not a probe. */
			int left = CW - 8 - 19, midRow = STRIP / 2;

			/* **THE PILL IS A FILLED SHAPE IN THE MARKS' OWN INK, WITH NO BORDER AT ALL — AND ITS HEIGHT IS A
			 * METRIC RATHER THAN A ROW NUMBER.** Every claim below is made against the column of ink ITSELF rather
			 * than against rows written down here, which is what the first version did: it probed row 4 for the top
			 * edge, and the moment the pill was made shorter that row was the STRIP, so the check failed on a pill
			 * that was exactly right. A probe is a claim about geometry and has to be derived from the geometry —
			 * the same lesson `box_is` carries one screen down, learned the same way. */
			{
				int top = -1, bottom = -1, y, height;

				for (y = 0; y < STRIP; y++) {
					if (is_colour(at(rep, left + 9, y), [NSColor cg_chromeInkColor], 0.03)) {
						if (top < 0) {
							top = y;
						}
						bottom = y;
					}
				}
				height = (top < 0) ? 0 : (bottom - top + 1);
				printf("  (note: the pill runs rows %d..%d — %d points tall in a %d-point strip)\n",
				       top, bottom, height, STRIP);
				check(is_colour(at(rep, left + 9, midRow), [NSColor cg_chromeInkColor], 0.03),
				      "the toolbar pill is filled in the chrome's ink — the same grey as the three marks");
				check(height > 0, "and it is drawn at all");
				check(height == 7, "and it is HALF the 14 points it was — a mark rather than a bar");
				{
					int x, across = 0;

					/* **THE SCAN IS THE PILL'S OWN END OF THE STRIP, NOT THE WHOLE OF IT.** A full-width row finds the three
					 * SYMBOLS too — same ink, same row — and MEASURED that reads 41 columns, which is the marks plus the pill
					 * and not the pill. */
					for (x = CW - 40; x < CW; x++) {
						if (is_colour(at(rep, x, top + 3), [NSColor cg_chromeInkColor], 0.03)) {
							across++;
						}
					}
					printf("  (note: the pill is %d columns across, where 30 points used to be 30)\n", across);
					check(across >= 19 && across <= 20,
					      "and 35 PER CENT SHORTER across — 19.5 points where it was 30");
				}
				check(top > 0 && is_colour(at(rep, left + 9, top - 1), [NSColor windowFrameColor], 0.02),
				      "with STRIP directly above its top edge, so there is no border row there");
				check(!is_colour(at(rep, left + 9, top), [NSColor controlDarkShadowColor], 0.06)
				      && !is_colour(at(rep, left + 9, top), [NSColor controlColor], 0.06),
				      "and that edge is neither the border nor the face the pill used to be drawn with");
				/* **AND THE CORNER IS ASKED AS "NOT THE INK" RATHER THAN "IS THE STRIP".** The point below is inside the
				 * shape's bounding box but outside its rounded corner, so a SQUARE pill would ink it and a rounded one
				 * leaves the strip showing — which is the claim. Asking for an exact strip colour instead was the first
				 * version and it FAILED on a pill that was right: a 3.5-point radius means that pixel is part of the
				 * curve's own antialiasing, a blend of the two, and neither colour to within 0.02. */
				check(!is_colour(at(rep, left, top), [NSColor cg_chromeInkColor], 0.03),
				      "while its corner is NOT the ink — a rounded rectangle, not a square one");
			}
			[rep release];
		}

		/* 6. **AND A TITLE WITH NO ROOM IS CUT RATHER THAN ALLOWED TO RUN UNDER A SYMBOL.** The window here is 300
		 * points wide with two blocks in it, so a title long enough to reach either one has to be truncated — and
		 * what is checked is that the ink stops before the pill rather than where the string happens to end. */
		{
			NSWindow *narrow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 160.0, (CGFloat)CH)
				styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
				backing:NSBackingStoreBuffered defer:NO];
			NSBitmapImageRep *rep;
			int lo = 0, hi = 0;

			[narrow setTitle:@"A Title Far Longer Than Any Of This Window's Chrome Could Ever Hope To Fit"];
			rep = new_rep(160, FH);
			{
				NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

				[NSGraphicsContext setCurrentContext:ctx];
				[[NSColor whiteColor] setFill];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 160.0, (CGFloat)FH)] fill];
				[narrow cg_drawChromeInContext:ctx];
			}
			/* **THE SCAN IS THE COLUMNS THE TITLE MAY USE, NOT THE WHOLE STRIP.** The symbols and the pill are ink
			 * too, so a full-width scan measures THEM and says nothing about the title — which is exactly what the first
			 * version of this check did: it passed while the pill had no border (there was nothing to find at the right
			 * end) and broke the moment the border was drawn, reporting the pill's own ink as an over-long title. The
			 * band below is what the title has to itself, and "the ink is inside it with air at both ends" is the claim
			 * that the title was CUT. */
			if (ink_box_range(rep, 8 + 51 + 2, 160 - 8 - 30 - 2, 0, STRIP, &lo, &hi)) {
				printf("  (note: a title with no room runs x %d..%d, in the band it has)\n", lo, hi);
			}
			check(ink_box_range(rep, 8 + 51 + 2, 160 - 8 - 30 - 2, 0, STRIP, &lo, &hi)
			      && lo > 8 + 51 && hi < 160 - 8 - 30,
			      "an over-long title is CUT, and its ink stays clear of both blocks");
			[rep release];
			[narrow release];
		}

		[w release];
		printf("window_chrome: %d case(s) failed\n", s_failed);
	}
	return s_failed == 0 ? 0 : 1;
}
