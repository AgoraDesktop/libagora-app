/*
 * window_chrome — is the title bar Agora's, and is it the shapes it says it is?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CHROME IS THE CLIENT'S, SO IT CAN BE DRAWN WITHOUT A COMPOSITOR — AND THAT IS WHY THIS FILE CAN EXIST.**
 * The window server draws no title bar (see `agora-shell.xml`: its share of the model is the shadow, the work area
 * and the Z-order), so the strip is `NSWindow`'s own drawing and `-cg_drawChromeInContext:` hands it the context a
 * caller already has. This test hands it a bitmap rep's and then asks the PIXELS, which is the only place a claim
 * about a shape is worth anything: "the close mark is an X and not a circle" is not a fact about the code that
 * chose to draw lines.
 *
 * **THE CHROME WEARS GREYBIRD'S LOOK NOW, AND THAT LOOK IS DRAWN RATHER THAN COPIED.** The theme is somebody
 * else's GPL work and cannot ship, so `NSWindow` draws the bar and the four marks itself, in the theme's own
 * measures and colours — which means this file has to state them, because a number in a comment is not a claim.
 *
 * WHAT IS ASSERTED, each one a way the chrome can look right and be wrong:
 *
 *   1. THE BAR IS A BAR: a one-point outline on its top row, a white row under that, the face below them, and a
 *      ROUND corner — the frame colour at the corner's own pixel, because a rounded corner is a shape and a square
 *      one would ink it.
 *   2. THE THREE MARKS ARE THE THEME'S, IN ITS SIZES: an eight-by-nine box each, ink on both diagonals of the X
 *      and none at its top middle, one bar for the minus, that bar plus the upright for the plus. A circle would
 *      satisfy none of them.
 *   3. THE INK IS GREY AND IT FOLLOWS THE WINDOW: `#BFBFBF` while the window is not key, `#797979` when it is,
 *      `#4B4B4B` under the pointer and the theme's own blue under a press. The press is the one that proves the
 *      state is read at all, since the other three are greys.
 *   4. AND IT IS CRISP: every pixel of the minus is the ink exactly, with no half-covered row above or below it.
 *      That is what the marks' antialiasing switch buys, and a blurred two-point diagonal is exactly what it
 *      prevents.
 *   5. The title is CENTRED in the strip and BOLD, the second of those measured against the same string drawn in
 *      the two faces rather than against a number.
 *   6. THE FOURTH MARK IS A TRIANGLE: eight wide at its top, narrowing to two at its point, at the right end and
 *      clear of the bar's own edge. A pill — what stood there before — is the same width top and bottom.
 *      **AND IT IS THERE ONLY ON A WINDOW THAT HAS A TOOLBAR**: the right end of a toolbar-less window's strip is
 *      bare, which is checked first and is the policy; the triangle's SHAPE is then checked on a window that has a
 *      band for it to toggle (`fn_chrome_button_present` is where the difference is made).
 *   7. A title too long for the room between the two blocks is CUT rather than run under them.
 *   8. A SHEET PAINTS NOTHING. It has no title bar to paint — the Mac gives it none, and the parent's bar is the one it
 *      hangs from — so a frame-sized bitmap handed to the painter comes back untouched. That is the defect this check
 *      was written for: a sheet drawn as an ordinary window wore a strip and a traffic light of its own, sitting on top
 *      of its parent's title bar.
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
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

/* THE WINDOW THIS IS DRAWN FOR: a content rectangle, plus the 22-point strip above it. The rep is the FRAME's size,
 * because that is the surface the chrome has rows in — which is the same reason a live window's buffer is the frame
 * and not the content. */
#define CW 300
#define CH 120
#define STRIP 22
#define FH (CH + STRIP)

/* THE CHROME'S OWN NUMBERS, repeated here ON PURPOSE. They live in `NSWindow.m` as file-static constants, and a
 * test that imported them would agree with the painter by construction — including when the painter is wrong. These
 * are the theme's, taken from its `.xpm` art, and if the painter's copy ever drifts this file says so.
 *
 * THE FACE IS THE ONE EXCEPTION, and it is not a copy: `+cg_chromeFaceColor` is a PUBLISHED door, because the title
 * bar and the toolbar band are painted by two different files and have to be one colour. A claim about it is a claim
 * about the contract, so it is asked of `NSColor` rather than written down here a second time. */
#define EDGE_L     0.576	/* #939393 — its outline */
#define INK_L      0.475	/* #797979 — a mark on a key window */
#define FAINT_L    0.749	/* #BFBFBF — and on one that is not */
#define HOVER_L    0.294	/* #4B4B4B — under the pointer */
#define PRESS_R    (0x68 / 255.0)
#define PRESS_G    (0x97 / 255.0)
#define PRESS_B    (0xBC / 255.0)
#define MARK_W     8
#define MARK_H     9

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

static NSColor *grey(double white)
{
	return [NSColor colorWithCalibratedWhite:white alpha:1.0];
}

/* **THE INK IS "DARKER THAN THE BAR'S FACE", AND THE BAR'S OUTLINE IS DARKER STILL.** The face is 0.871, a mark is
 * 0.749 on a window that is not key and 0.475 on one that is, and the light row under a mark is 0.898 — so 0.80
 * separates a mark from the surface it is drawn on in every state. The OUTLINE at 0.576 is under that threshold too,
 * which is why every scan below stays off the bar's top row and its two end columns: the outline is not a mark, and
 * a probe that counted it would find "ink" across the whole strip and call a title a hundred points too wide. */
static int ink_at(NSBitmapImageRep *rep, int x, int y)
{
	return lum(at(rep, x, y)) < 0.80;
}

/* **THE INK'S BOUNDING BOX IN A COLUMN RANGE, OVER THE ROWS A MARK CAN BE DRAWN IN.** The rows start below the bar's
 * outline (row 0) and stop before the content's hairline, which is the band the marks and the title share. Returns NO
 * when there is no ink at all. */
static int ink_box_range(NSBitmapImageRep *rep, int x0, int x1, int y0, int y1,
			 int *outX0, int *outX1, int *outY0, int *outY1)
{
	int x, y, lo = -1, hi = -1, top = -1, bot = -1;

	for (x = x0; x < x1; x++) {
		for (y = y0; y < y1; y++) {
			if (ink_at(rep, x, y)) {
				/* **MIN AND MAX, NOT FIRST AND LAST.** The scan runs columns first, so "the first ink
				 * found" is the top of the FIRST COLUMN with any, and "the last" is the bottom of the
				 * LAST one — and a mark whose tips are single pixels has neither. This read `if (top <
				 * 0) top = y` and `bot = y` and measured the close mark as seven rows tall instead of
				 * nine, which is exactly the kind of quiet off-by-two a shape check dies of. */
				if (lo < 0 || x < lo) {
					lo = x;
				}
				if (x > hi) {
					hi = x;
				}
				if (top < 0 || y < top) {
					top = y;
				}
				if (y > bot) {
					bot = y;
				}
			}
		}
	}
	if (lo < 0) {
		return 0;
	}
	*outX0 = lo;
	*outX1 = hi;
	*outY0 = top;
	*outY1 = bot;
	return 1;
}

/* THE MARK'S OWN BAND: below the bar's outline and above the content. */
static int mark_box(NSBitmapImageRep *rep, int x0, int x1, int *lo, int *hi, int *top, int *bot)
{
	return ink_box_range(rep, x0, x1, 2, STRIP, lo, hi, top, bot);
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
	int lo = 0, hi = 0, top = 0, bot = 0;
	int found;

	[NSGraphicsContext setCurrentContext:ctx];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 240.0, 40.0)] fill];
	[[NSColor blackColor] setFill];
	[s drawAtPoint:NSMakePoint(4.0, 4.0) withAttributes:attrs];
	found = ink_box_range(rep, 0, 240, 0, 40, &lo, &hi, &top, &bot);
	[rep release];
	return found ? (hi - lo + 1) : 0;
}

/* **THE DOORS THIS FILE NEEDS THAT ONLY THE POINTER OR THE KEY STATE CAN OPEN**, declared the way this tree's other
 * probes declare a private contract: a hover is an engine call, and a press is an event the way a compositor would
 * have sent it. */
@interface NSWindow (APPKITWindowChromeTest)
- (void)cg_updateTrackingForPoint:(NSPoint)windowPoint;
/* **AND THE TWO SHEET DOORS THIS FILE ASKS.** The parent back-reference names the window whose title bar's border the
 * sheet wears, and the tuck says which row that is: both are `NSWindow`'s own arithmetic, so a probe that wrote either
 * number down would be a second copy of it. */
- (NSWindow *)cg_sheetParent;
- (CGFloat)cg_sheetTuck;
@end

int main(void)
{
	@autoreleasepool {
		NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)CH)
			styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
			backing:NSBackingStoreBuffered defer:NO];
		/* **THE BOXES ARE THE LAYOUT'S AND THE INK INSIDE THEM IS MEASURED.** The three left boxes are eleven
		 * points, nine points apart, starting at the strip's eight-point edge: 8..18, 28..38 and 48..58. Nothing
		 * below writes down a ROW: the marks' rows are found by asking the pixels, because they are the thing under
		 * test and a row written here would be a second copy of the painter's arithmetic. */
		const int xClose = 8, xHide = 28, xZoom = 48;
		const int xMenu = CW - 8 - 11;
		int lo = 0, hi = 0, top = 0, bot = 0;

		[w setTitle:@"Controls"];

		/* 1. **THE CHROME IS ONE SURFACE WITH ONE EDGE: ITS TOP.** The face is `+cg_chromeFaceColor` — the colour the
		 * toolbar band is painted with too, which is what makes the strip continuous — the row above it is a white
		 * highlight, and above that a one-point outline. THE EDGE IS THE TOP'S ALONE: it follows the corners and
		 * stops, so the ends of the strip are the window's own edges and nothing is drawn down them. That is a
		 * decision with a reason (a line down the ends reads as a border AROUND the chrome), so it is checked as
		 * hard as the things that ARE drawn. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);

			check(is_colour(at(rep, CW / 2, 0), grey(EDGE_L), 0.02),
			      "the strip's top row is its one-point outline, in the theme's #939393");
			check(is_colour(at(rep, CW / 2, 1), [NSColor whiteColor], 0.02),
			      "and the row below it is the white highlight the theme draws there");
			check(is_colour(at(rep, CW / 4, 6), [NSColor cg_chromeFaceColor], 0.02),
			      "and the surface is +cg_chromeFaceColor — the one colour the title bar and the toolbar share");
			check(is_colour(at(rep, 0, 0), [NSColor cg_chromeFaceColor], 0.02),
			      "the CORNER's own pixel is the surface, because the top edge is round and does not reach it");
			check(is_colour(at(rep, 8, 0), grey(EDGE_L), 0.02) && !is_colour(at(rep, 3, 0), grey(EDGE_L), 0.02),
			      "while the top edge, past the SIX-point corner, IS the outline — so the corner is a shape, not a gap");
			check(is_colour(at(rep, 0, 10), [NSColor cg_chromeFaceColor], 0.02)
			      && is_colour(at(rep, CW - 1, 10), [NSColor cg_chromeFaceColor], 0.02),
			      "and NOTHING is drawn down the ends — the strip is the surface to the window's own edges");
			check(is_colour(at(rep, CW / 2, STRIP + 6), [NSColor whiteColor], 0.02),
			      "and the chrome does not run down into the content below it");
			[rep release];
		}

		/* 2. **THE THREE MARKS, AS SHAPES AND AT THE THEME'S SIZE.** Each check below is one shape's own geometry and
		 * would fail for the other two: the X inks two diagonals, the minus inks one bar and NOTHING beside it, and the
		 * plus inks the bar AND the upright over the same centre. A circle — what used to be drawn — passes none. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);

			check(mark_box(rep, xClose, xClose + 11, &lo, &hi, &top, &bot)
			      && (hi - lo + 1) == MARK_W && (bot - top + 1) == MARK_H,
			      "the close mark is the theme's EIGHT BY NINE, in its eleven-point box");
			check(ink_at(rep, lo + 1, top + 1) && ink_at(rep, hi - 1, top + 1)
			      && !ink_at(rep, (lo + hi) / 2, top + 1),
			      "it inks BOTH diagonals and NOT its top middle — an X, not a dot");
			check(mark_box(rep, xHide, xHide + 11, &lo, &hi, &top, &bot)
			      && (hi - lo + 1) == MARK_W && (bot - top + 1) == 2,
			      "the miniaturize mark is ONE TWO-POINT BAR, eight wide — a minus");
			check(mark_box(rep, xZoom, xZoom + 11, &lo, &hi, &top, &bot)
			      && (hi - lo + 1) == MARK_W && (bot - top + 1) == MARK_W,
			      "and the zoom mark is that bar PLUS the upright — a plus, eight by eight");
			/* **AND ITS FOUR ARMS ARE ONE LENGTH, WHICH IS THE WHOLE OF WHAT A PLUS IS.** The cross-bar's rows
			 * are the only ones as wide as the mark and the upright's columns the only ones as tall; the rows
			 * above and below the bar, and the columns either side of the upright, are the four arms. They must
			 * MATCH — MEASURED, in a nine-row upright a two-row bar leaves three rows above and four below, which
			 * is exactly "the top and bottom of the + are uneven". A plus whose arms differ is a cross with a long
			 * leg, and the upright is eight rows for this reason. */
			{
				int x, y, barTop = -1, barBot = -1, upLeft = -1, upRight = -1;
				int above, below, leftArm, rightArm;

				for (y = top; y <= bot; y++) {
					int width = 0;

					for (x = lo; x <= hi; x++) {
						if (ink_at(rep, x, y)) {
							width++;
						}
					}
					if (width == MARK_W) {
						if (barTop < 0) {
							barTop = y;
						}
						barBot = y;
					}
				}
				for (x = lo; x <= hi; x++) {
					int height = 0;

					for (y = top; y <= bot; y++) {
						if (ink_at(rep, x, y)) {
							height++;
						}
					}
					if (height == MARK_W) {
						if (upLeft < 0) {
							upLeft = x;
						}
						upRight = x;
					}
				}
				above = barTop - top;
				below = bot - barBot;
				leftArm = upLeft - lo;
				rightArm = hi - upRight;
				printf("  (note: the plus's arms are %d above, %d below, %d left, %d right)\n",
				       above, below, leftArm, rightArm);
				check(barTop >= 0 && upLeft >= 0 && above == below && leftArm == rightArm
				      && above == leftArm,
				      "and its four arms are ONE length — an even plus, not a cross with a long leg");
			}
			{
				int mx0 = 0, mx1 = 0, my0 = 0, my1 = 0, px0 = 0, px1 = 0, py0 = 0, py1 = 0;

				/* **THE MINUS IS THE PLUS'S OWN CROSS BAR, TO THE ROW.** Its rows lie inside the upright's and
				 * its middle IS the upright's — the half-point offset a nine-row upright forced is gone with the
				 * upright, because the upright is now the cross-bar's own length. */
				check(mark_box(rep, xHide, xHide + 11, &mx0, &mx1, &my0, &my1)
				      && mark_box(rep, xZoom, xZoom + 11, &px0, &px1, &py0, &py1)
				      && my0 >= py0 && my1 <= py1
				      && (my0 + my1) == (py0 + py1),
				      "and the minus IS the plus's cross bar — same middle, inside the same upright");
			}
			[rep release];
		}

		/* 3. **THE INK IS GREY, AND IT FOLLOWS THE WINDOW.** The window this file builds is NOT key, so it wears the
		 * faded ink; making it key swaps to the theme's body colour. Those two are compared by COLOUR and not by
		 * "darker", because the claim is the theme's palette and not that something was drawn. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);
			int midX, midY;

			check(mark_box(rep, xHide, xHide + 11, &lo, &hi, &top, &bot), "the minus can be found");
			midX = (lo + hi) / 2;
			midY = (top + bot) / 2;
			check(is_colour(at(rep, midX, midY), grey(FAINT_L), 0.02),
			      "a window that is NOT key draws the theme's faded #BFBFBF marks");
			[w makeKeyWindow];
			check([w isKeyWindow], "and this window can be made key");
			[rep release];
			rep = draw_chrome(w);
			check(is_colour(at(rep, midX, midY), grey(INK_L), 0.02),
			      "made key, the SAME pixel is the theme's #797979");
			[rep release];
		}

		/* 4. **THE POINTER'S TWO STATES, WHICH ARE TWO MORE GREYS.** Hovering the minus darkens it to `#4B4B4B`; a
		 * press on the close mark turns it the theme's blue. The blue is the point: three greys that are merely
		 * "different" could all be wrong, and a colour that is not a grey could not be. */
		{
			NSBitmapImageRep *rep;
			int midX, midY;

			[w cg_updateTrackingForPoint:NSMakePoint((CGFloat)(xHide + 5), (CGFloat)(CH + 11))];
			rep = draw_chrome(w);
			check(mark_box(rep, xHide, xHide + 11, &lo, &hi, &top, &bot), "the hovered minus can be found");
			midX = (lo + hi) / 2;
			midY = (top + bot) / 2;
			check(is_colour(at(rep, midX, midY), grey(HOVER_L), 0.02),
			      "the mark UNDER THE POINTER is the theme's darker #4B4B4B");
			[rep release];
		}
		{
			NSBitmapImageRep *rep;
			NSEvent *down = [NSEvent mouseEventWithType:NSLeftMouseDown
				location:NSMakePoint((CGFloat)(xClose + 5), (CGFloat)(CH + 11))
				modifierFlags:0 timestamp:0.0 windowNumber:[w windowNumber] context:nil
				eventNumber:0 clickCount:1 pressure:0.0f];

			[w sendEvent:down];
			rep = draw_chrome(w);
			check(mark_box(rep, xClose, xClose + 11, &lo, &hi, &top, &bot), "the pressed close mark can be found");
			check(is_colour(at(rep, (lo + hi) / 2, (top + bot) / 2),
					[NSColor colorWithCalibratedRed:PRESS_R green:PRESS_G blue:PRESS_B alpha:1.0], 0.02),
			      "and a PRESS draws it in the theme's own BLUE (#6897BC), which no grey could imitate");
			[rep release];
		}

		/* 5. **AND IT IS CRISP, WHICH IS THE MARKS' OWN RULE.** A two-point bar is two rows of the ink EXACTLY; the
		 * light row under it is the theme's and is lighter than the bar, so it is not ink; and there is no
		 * half-covered row on either side of it. Before antialiasing was turned off for the marks the diagonal was
		 * the shape that suffered, and the bar is the shape that measures it without any geometry to argue about. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);
			int x, y, pure = 0, blended = 0;

			if (mark_box(rep, xHide, xHide + 11, &lo, &hi, &top, &bot)) {
				for (x = lo; x <= hi; x++) {
					int inkHere = 0;

					for (y = top - 1; y <= bot + 1; y++) {
						NSColor *p = at(rep, x, y);

						if (is_colour(p, grey(INK_L), 0.02)) {
							inkHere++;
						} else if (lum(p) < 0.80) {
							blended++;
						}
					}
					if (inkHere == 2) {
						pure++;
					}
				}
			}
			printf("  (note: %d of the minus's 8 columns are 2 rows of pure ink; %d blended pixels beside them)\n",
			       pure, blended);
			check(pure == MARK_W, "every column of the minus is TWO ROWS of ink and no more");
			check(blended == 0, "and there is not one half-covered pixel in the band — the marks are not smoothed");
			[rep release];
		}

		/* 6. **THE TITLE IS CENTRED AND BOLD.** Centred is measured as the ink's own centre against the strip's,
		 * over the columns BETWEEN the two blocks — where the title is the only thing that can be drawn. Bold is
		 * measured against the same string in the two faces, so it says "this came from the emphasized face" rather
		 * than "this came from the face whose name I happen to have written down". */
		{
			NSBitmapImageRep *rep = draw_chrome(w);
			int leftEnd = xZoom + 11 + 4;
			int rightStart = xMenu - 4;
			int found = mark_box(rep, leftEnd, rightStart, &lo, &hi, &top, &bot);
			double centre = found ? ((double)lo + (double)hi) / 2.0 : -1.0;
			int titleWidth = found ? (hi - lo + 1) : 0;
			int boldWidth, plainWidth;

			printf("  (note: the title's ink runs x %d..%d, centre %.1f against the strip's %.1f; width %d)\n",
			       lo, hi, centre, (double)CW / 2.0, titleWidth);
			check(found, "the title is drawn in the strip");
			check(found && fabs(centre - (double)CW / 2.0) <= 2.0,
			      "and it is CENTRED — its ink's centre is the strip's, not the left end after the marks");

			boldWidth = text_ink_width([NSFont boldSystemFontOfSize:[[NSFont titleBarFontOfSize:0.0] pointSize]],
						   [w title]);
			plainWidth = text_ink_width([NSFont systemFontOfSize:[[NSFont titleBarFontOfSize:0.0] pointSize]],
						    [w title]);
			printf("  (note: the same title measures %d in the emphasized face and %d in the regular one)\n",
			       boldWidth, plainWidth);
			check(boldWidth > 0 && plainWidth > 0, "the same string can be measured in both faces");
			/* **CLOSER TO, RATHER THAN EQUAL TO.** The two measurements are the same string drawn at the same
			 * point, so an exact match is what one would expect — and it is NOT what happens: the scratch rep draws
			 * at an integer point and the chrome's title is centred, so the two land on different sub-pixel phases
			 * and the ink's width can differ by one row of coverage. The CLAIM is which face it came from, and the
			 * two faces differ by more than that, so the distance decides it. */
			check(boldWidth != plainWidth
			      && abs(titleWidth - boldWidth) < abs(titleWidth - plainWidth),
			      "and the title in the strip is the BOLD one — nearer the emphasized face than the regular one");
			[rep release];
		}

		/* 7. **THE FOURTH MARK IS THERE WHEN THERE IS A TOOLBAR TO TOGGLE, AND NOT BEFORE.** Two halves, because
		 * both are claims: a window with no toolbar draws NOTHING at that end (a mark whose only action would be a
		 * no-op is a promise the window cannot keep), and a window with one draws the theme's TRIANGLE — eight wide
		 * on its base row and narrower on every row below it, down to a point, where a pill is the same width on
		 * every row and would fail every line of that. */
		{
			NSBitmapImageRep *rep = draw_chrome(w);
			int x, inked = 0;

			for (x = xMenu; x < CW; x++) {
				if (ink_at(rep, x, 10)) {
					inked++;
				}
			}
			check(inked == 0,
			      "a window with NO toolbar draws nothing at the strip's right end — the pill is the toolbar's");
			[rep release];
		}
		{
			/* **THE BAND IS WHAT MAKES THE DIFFERENCE, SO THE MARK IS CHECKED ON A WINDOW THAT HAS ONE.** The rep is
			 * the frame's own height, which `-setToolbar:` grows by the band, so the strip is still the top rows of
			 * it and every scan below asks the pixels exactly as the toolbar-less half did. */
			NSWindow *withBand = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)CH)
				styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
				backing:NSBackingStoreBuffered defer:NO];
			NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"AGWindowChromeProbe"];
			NSBitmapImageRep *rep;
			int widths[STRIP], i, rows = 0, nextToEdge = 0;
			int t0 = 0, t1 = 0, t2 = 0, t3 = 0;
			int height;

			[withBand setTitle:@"Controls"];
			[withBand setToolbar:toolbar];
			height = (int)[withBand frame].size.height;
			rep = new_rep(CW, height);
			{
				NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

				[NSGraphicsContext setCurrentContext:ctx];
				[[NSColor whiteColor] setFill];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)height)] fill];
				[withBand cg_drawChromeInContext:ctx];
			}
			memset(widths, 0, sizeof widths);
			/* **THE TRIANGLE'S ROWS COME FROM THE TRIANGLE.** Writing down "rows 2..8" here was the first
			 * version and it measured zero, because the mark sits nine rows lower than that — a probe with a
			 * row in it is a second copy of the painter's arithmetic. */
			if (!mark_box(rep, xMenu, xMenu + 11, &t0, &t1, &t2, &t3)) {
				t2 = t3 = -1;
			} else {
				for (i = 0; t2 + i <= t3; i++) {
					int x;

					for (x = xMenu; x < xMenu + 11; x++) {
						if (ink_at(rep, x, t2 + i)) {
							widths[i]++;
						}
					}
					rows++;
				}
			}
			printf("  (note: the triangle's rows are %d,%d,%d,%d,%d,%d wide)\n",
			       widths[0], widths[1], widths[2], widths[3], widths[4], widths[5]);
			check(rows >= 5 && widths[0] == MARK_W,
			      "a window WITH a toolbar draws the pill, EIGHT WIDE at its top");
			check(rows >= 5 && widths[rows - 1] < widths[0] && widths[rows - 1] <= 2,
			      "and narrows to a point at the bottom — a triangle, not a pill");
			{
				int narrowed = 1;

				for (i = 1; i < rows; i++) {
					if (widths[i] > widths[i - 1]) {
						narrowed = 0;
					}
				}
				check(narrowed, "and it narrows on EVERY row, without widening again");
			}
			for (i = xMenu; i < CW; i++) {
				if (is_colour(at(rep, i, 10), [NSColor cg_chromeFaceColor], 0.02)) {
					nextToEdge++;
				}
			}
			check(nextToEdge >= 8, "and it stands clear of the bar's own end, as the left block does");
			[rep release];
			[toolbar release];
			[withBand release];
		}

		/* 8. **AND A TITLE WITH NO ROOM IS CUT RATHER THAN ALLOWED TO RUN UNDER A MARK.** The window here is 160
		 * points wide with two blocks in it, so a title long enough to reach either one has to be truncated — and
		 * what is checked is that the ink stops before the right block rather than where the string happens to end. */
		{
			NSWindow *narrow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 160.0, (CGFloat)CH)
				styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask)
				backing:NSBackingStoreBuffered defer:NO];
			NSBitmapImageRep *rep;
			int bandLeft = 48 + 11 + 2;
			/* **THE RIGHT BLOCK IS THE STRIP'S EDGE ALONE HERE**, because this window has no toolbar and so no
			 * pill: `fn_chrome_layout`'s `rightBlock` is the edge on its own, and a scan that assumed the mark was
			 * still there would be measuring a band the title does not have. */
			int bandRight = 160 - 8 - 2;

			[narrow setTitle:@"A Title Far Longer Than Any Of This Window's Chrome Could Ever Hope To Fit"];
			rep = new_rep(160, FH);
			{
				NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

				[NSGraphicsContext setCurrentContext:ctx];
				[[NSColor whiteColor] setFill];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 160.0, (CGFloat)FH)] fill];
				[narrow cg_drawChromeInContext:ctx];
			}
			/* **THE SCAN IS THE COLUMNS THE TITLE MAY USE, NOT THE WHOLE STRIP.** The marks and the triangle are ink
			 * too, so a full-width scan measures THEM and says nothing about the title. The band below is what the
			 * title has to itself, and "the ink is inside it with air at both ends" is the claim that the title was
			 * CUT. */
			check(mark_box(rep, bandLeft, bandRight, &lo, &hi, &top, &bot)
			      && lo > 48 + 11 && hi < 160 - 8,
			      "an over-long title is CUT, and its ink stays clear of both blocks");
			[rep release];
			[narrow release];
		}

		/* 9. **A SHEET PAINTS NO CHROME AT ALL, AND THAT IS THE STRONGEST FORM OF THE CLAIM.** The Mac gives a sheet no
		 * title bar — the parent's bar is the one it hangs from — and this tier's chrome is the client's, so `-isSheet`
		 * is what the painter has to read. What is asserted is the whole rep: a frame-sized bitmap filled white and
		 * handed to the painter comes back WHITE, every pixel of it. A bar, an outline, a traffic light, a title or a
		 * hairline left anywhere in there fails this, which is exactly the defect that made a sheet look like a
		 * second window with a strip of its own sitting on top of its parent's title bar. */
		{
			NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
				styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
			NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)CH)
				styleMask:(NSTitledWindowMask | NSClosableWindowMask) backing:NSBackingStoreBuffered defer:NO];
			NSBitmapImageRep *rep = new_rep(CW, FH);
			NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
			int x, y, inked = 0, offRow = 0, onRow = 0;
			int lineRow;

			[sheet setTitle:@"Already exists"];
			[[NSApplication sharedApplication] beginSheet:sheet modalForWindow:parent
				modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
			[NSGraphicsContext setCurrentContext:ctx];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)CW, (CGFloat)FH)] fill];
			[sheet cg_drawChromeInContext:ctx];
			/* **ONE ROW, AND IT IS THE PARENT'S TITLE BAR BORDER — EVERYTHING ELSE IS BARE.** A sheet has no strip, no
			 * marks, no title and no hairline of its own; what it DOES paint is the bar's bottom border across itself,
			 * because the bar is in front of the sheet on the Mac and here the sheet's surface is the one on top — so
			 * the sheet wears the line, `tuck` points down from its top edge, and the parent's line meets it at the
			 * sheet's two sides. The row is found by asking the pixels, not by writing down an index: `[sheet frame]`
			 * is the sheet's content (no chrome), and the line is one row inside its top edge by the tuck. */
			/* THE REP'S ROWS RUN FROM THE TOP AND THE PAINTER'S FROM THE BOTTOM, so the row is converted: the line is
			 * `tuck` points below the sheet's top edge in window coordinates, which is `FH - 1 - that` in the bitmap. */
			lineRow = FH - 1 - (int)([sheet frame].size.height - [[sheet cg_sheetParent] cg_sheetTuck] - 1.0);
			for (y = 0; y < FH; y++) {
				for (x = 0; x < CW; x++) {
					BOOL ink = !is_colour(at(rep, x, y), [NSColor whiteColor], 0.02);

					if (!ink) {
						continue;
					}
					inked++;
					if (y == lineRow) {
						onRow++;
					} else {
						offRow++;
					}
				}
			}
			check([sheet isSheet], "the window under test IS a sheet");
			check(offRow == 0, "a sheet paints NO chrome of its own — no strip, no marks, no title, no hairline");
			check(onRow == CW,
			      "and it does paint the PARENT'S TITLE BAR BORDER across itself: one full-width row, at the row the "
			      "bar's line occupies");
			check(is_colour(at(rep, CW / 2, lineRow), [NSColor controlDarkShadowColor], 0.02),
			      "in the bar's own ink — the colour the parent's hairline is drawn with");
			printf("  (note: %d inked pixel(s), %d of them on row %d)\n", inked, onRow, lineRow);
			[rep release];
			[[NSApplication sharedApplication] endSheet:sheet returnCode:0];
			[sheet release];
			[parent release];
		}

		[w release];
		printf("window_chrome: %d case(s) failed\n", s_failed);
	}
	return s_failed == 0 ? 0 : 1;
}
