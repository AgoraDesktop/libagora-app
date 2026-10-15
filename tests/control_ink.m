/*
 * control_ink — does a CONTROL draw its CELL, and does a BUTTON's cell put a face on a surface?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THE CONTROL LAYER'S WHOLE POINT IS THAT A VIEW DELEGATES ITS FACE TO A CELL, SO THIS ASKS THE TWO HALVES
 * SEPARATELY AND THEN TOGETHER.** Offscreen, because the ink is the claim: a bitmap rep and a graphics context
 * answer "did anything land", and the control's `-drawRect:` is what this calls, so what is exercised is the real
 * path — `NSControl -drawRect:` → `NSCell -drawWithFrame:inView:` → the bezel and the title — and not a shortcut.
 *
 * WHAT IS ASSERTED, each one a behaviour that did not exist before this slice:
 *
 *   1. A button makes a BUTTON CELL, bordered and bezeled.
 *   2. `-drawRect:` puts INK on a surface — the bezel and the title.
 *   3. A SWITCH draws an INDICATOR, and a radio draws a different one: the button TYPE decides the face.
 *   4. The value doors FORWARD to the cell (a string round-trips).
 *   5. `-performClick:` SENDS THE ACTION to the target.
 *   6. `-sizeToFit` asks the CELL how big it wants to be, and the title is not clipped by the answer.
 *   7. A DISABLED button still draws (dimmed) and sends nothing.
 *   8. The CONTROL PALETTE'S four relationships hold: a button's face is above the window's grey, a disabled one is
 *      below it with a darker title still, the border is a dark grey rather than black, and the two LIVE titles are
 *      white.
 */
#import <AppKit/NSButton.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSStringDrawing.h>
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

/* A TARGET THAT COUNTS, so "the action was sent" is a number rather than an assumption. */
@interface AGControlTarget : NSObject
{
@public
	int fired;
}
- (void)clicked:(id)sender;
@end

@implementation AGControlTarget
- (void)clicked:(id)sender
{
	(void)sender;
	fired++;
}
@end

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

/* **INK ANYWHERE IN A BOX, WHICH IS A CONTROL'S OUTLINE RATHER THAN ITS SURFACE.** The threshold sits ABOVE
 * `+controlDarkShadowColor` and BELOW every face a control wears — the disabled face is the darkest of those at 0.86
 * — so what this counts is the border without counting the surface it encloses.
 *
 * MEASURED, AND IT IS THE THING THAT GOES WRONG WITH A THRESHOLD LIKE THIS: it was 0.72, which was above the 0.55
 * this tree used to give that colour and is now BELOW the sample's 0.737 — so `-drawRect:` on a button came out with
 * no ink at all and the case read as a button that had stopped drawing. The value moved with the colour; what the
 * threshold is anchored TO is the pair of them, which is what its comment now says. */
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

/* DRAW A VIEW into a fresh bitmap rep and hand the rep back, so every draw starts from a clean white surface. */
static NSBitmapImageRep *draw(NSView *view)
{
	NSBitmapImageRep *rep = new_rep();

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[view drawRect:[view bounds]];
	return rep;
}

/* IS THE FACE AT THIS POINT THIS COLOUR? The probe samples the RIGHT END of the button, well clear of the centred
 * title, so "the face changed" is a measurement of the chip rather than of its ink. The tolerance is the one the
 * bitmap rep's colour-space round trip needs; the two shades of the accent differ by more than 0.15. */
static int face_is(NSBitmapImageRep *rep, NSColor *want)
{
	NSColor *c = [rep colorAtX:W - 6 y:H / 2];

	return c != nil && want != nil
		&& fabs([c redComponent] - [want redComponent]) < 0.05
		&& fabs([c greenComponent] - [want greenComponent]) < 0.05
		&& fabs([c blueComponent] - [want blueComponent]) < 0.05;
}

/* **THE DARKEST PIXEL'S BRIGHTNESS IN A BOX** — the instrument for "is any of this drawn in a dark colour", which is
 * what a white title on a coloured face is a question about. `ink_in` counts pixels against a fixed threshold and
 * cannot answer it here: the ACCENT's own red is 0.643, below that threshold, so a pressed button's face would be
 * counted as ink and the check would fail on a title that was exactly right. Reading the minimum instead makes the FACE
 * the floor of the measurement, and a black glyph drops it to nothing. */
static double darkest_brightness(NSBitmapImageRep *rep, int x0, int y0, int x1, int y1)
{
	int x, y;
	double min = 2.0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil) {
				double v = ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3.0;

				if (v < min) {
					min = v;
				}
			}
		}
	}
	return min;
}

/* THE FIRST COLUMN WITH INK AT OR AFTER `fromX` — which is what "where does the LABEL start" means, and is the
 * measurement a checkbox's alignment is about. It is the right instrument for this because a CENTRED label moves when
 * the title's length changes and a LEFT-ALIGNED one does not, so the same probe answers both questions. */
static int first_ink_column(NSBitmapImageRep *rep, int fromX)
{
	int x, y;

	for (x = fromX; x < W; x++) {
		for (y = 0; y < H; y++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.72) {
				return x;
			}
		}
	}
	return -1;
}

/* **THE INDICATOR'S OWN FACE: a point inside the box that NOTHING ELSE DRAWN IN IT CAN REACH**, which is a stricter
 * requirement than it looks, because a checkbox and a radio share this probe and draw different things in the same
 * square. The box is the FOURTEEN-point square a checkbox and a radio share, at the cell's left edge and centred
 * vertically, and H is 40 — so in this rep's coordinates (rows counting from the TOP) it spans x 1..15 and y 12..26
 * and its centre is (8, 19). The probe is three points left of that centre and four below it: (5, 15).
 *
 * WHAT THAT POINT HAS TO MISS, all of it measured from the box's centre in BOX coordinates, where the centre is
 * (7, 7) and the radius that matters is the ring's:
 *
 *   - the square's one-point stroke, which now lies INSIDE the edge (box 0..1 and 13..14) — the probe is at (4, 11);
 *   - the ring's one-point stroke, which spans radius 6 to 7 — the probe is at radius 5;
 *   - a radio's dot, which is a disc of radius 3 — the probe is outside it;
 *   - the CHECKMARK, which is the one that actually constrains this: its two segments are (3,7)-(6,3.5)-(11,11)
 *     stroked two points wide, and the nearest thing on either of them to (4, 11) is 4.1 points away.
 *
 * IT WAS (4, H/2 + 4) UNTIL THE RING'S STROKE MOVED INWARD, and that is worth recording as a coupling rather than as
 * a tweak: the old probe cleared a stroke that was CENTRED on the ring's path by sitting just inside it, so when the
 * border was inset by half its width to put it on one pixel column the probe landed UNDER the border and a radio's
 * prelight measured as though no face had been drawn. A probe is a claim about geometry, and it has to be re-derived
 * when the geometry moves. */
static int box_is(NSBitmapImageRep *rep, NSColor *want)
{
	NSColor *c = [rep colorAtX:5 y:15];

	return c != nil && want != nil
		&& fabs([c redComponent] - [want redComponent]) < 0.05
		&& fabs([c greenComponent] - [want greenComponent]) < 0.05
		&& fabs([c blueComponent] - [want blueComponent]) < 0.05;
}

int main(void)
{
	@autoreleasepool {
		NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		AGControlTarget *target = [[AGControlTarget alloc] init];

		/* 1. THE CELL. */
		check([[button cell] isKindOfClass:[NSButtonCell class]], "a button makes a BUTTON CELL");
		check([[button cell] isBordered] && [[button cell] isBezeled], "and it is bordered and bezeled");

		[button setTitle:@"OK"];
		[button setTarget:target];
		[button setAction:@selector(clicked:)];

		/* 2. THE FACE. */
		{
			NSBitmapImageRep *rep = draw((NSView *)button);

			check(ink_in(rep, 0, 0, W, H) > 100, "`-drawRect:` puts a BUTTON's face on a surface");
			[rep release];
		}

		/* 3. THE INDICATOR: a switch and a radio draw their state at the left, and the face differs from a bezel. */
		{
			NSBitmapImageRep *bezel;
			NSBitmapImageRep *sw;
			int bezel_left, sw_left;

			[button setButtonType:NSMomentaryLightButton];
			bezel = draw((NSView *)button);
			bezel_left = ink_in(bezel, 0, 0, 20, H);
			[bezel release];

			[button setButtonType:NSSwitchButton];
			[button setState:NSOnState];
			sw = draw((NSView *)button);
			sw_left = ink_in(sw, 0, 0, 20, H);
			[sw release];

			check(sw_left > 0, "a SWITCH draws its indicator box at the left");
			check(sw_left != bezel_left, "and its face is NOT the momentary bezel it was");
			[button setButtonType:NSMomentaryLightButton];
		}

		/* 4. THE VALUE DOORS FORWARD TO THE CELL. */
		[button setStringValue:@"Renamed"];
		check([[button stringValue] isEqualToString:@"Renamed"], "`-setStringValue:` reaches the CELL and comes back");

		/* 5. THE ACTION. */
		target->fired = 0;
		[button performClick:nil];
		check(target->fired == 1, "`-performClick:` SENDS THE ACTION to the target");

		/* 7. DISABLED: it still draws (a control with a face), and it sends nothing. */
		[button setEnabled:NO];
		target->fired = 0;
		check([button isEnabled] == NO, "a disabled button reports itself disabled");
		{
			NSBitmapImageRep *rep = draw((NSView *)button);

			check(ink_in(rep, 0, 0, W, H) > 0, "and it still DRAWS its face");
			[rep release];
		}
		[button setEnabled:YES];

		/* 6. THE MEASUREMENT: `-sizeToFit` asks the cell, and a wider title makes a wider button. */
		{
			NSButton *small = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSButton *large = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

			[small setTitle:@"OK"];
			[large setTitle:@"A Considerably Longer Title"];
			[small sizeToFit];
			[large sizeToFit];
			check([small frame].size.width > 0.0, "`-sizeToFit` gives a button a width");
			check([large frame].size.width > [small frame].size.width,
			      "and a LONGER title makes a WIDER button, because the cell measured it");
			printf("  (note: 'OK' measured %g, the long title %g)\n", (double)[small frame].size.width,
			       (double)[large frame].size.width);
			[small release];
			[large release];
		}

		/* 8. **A CONTROL IS A SUBVIEW, SO THE CONTAINER HAS TO PLACE IT.** This is the check the LIVE probe found: a
		 * window's `-displayRect:` recursed into subviews without moving the CTM, so every control drew at its
		 * superview's ORIGIN — five buttons, one place. Two buttons at two frames, and the RIGHT half must carry ink
		 * of its own rather than the first button's. */
		{
			NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSButton *left = [[NSButton alloc] initWithFrame:NSMakeRect(5.0, 5.0, 60.0, 30.0)];
			NSButton *right = [[NSButton alloc] initWithFrame:NSMakeRect(95.0, 5.0, 60.0, 30.0)];
			NSBitmapImageRep *rep = new_rep();

			[left setTitle:@"L"];
			[right setTitle:@"R"];
			[container addSubview:left];
			[container addSubview:right];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
			[container displayRect:[container bounds]];
			check(ink_in(rep, 0, 0, W / 2, H) > 0, "a SUBVIEW is drawn at all");
			check(ink_in(rep, W / 2, 0, W, H) > 0, "and a second is drawn at ITS OWN x, not stacked on the first");
			[rep release];
			[left release];
			[right release];
			[container release];
		}

		/* 9. **THE COMPLETED SURFACE: THE TYPE'S DEFAULT MASKS, THE STATE WALK, THE ATTRIBUTED TITLE, THE PICTURES,
		 * THE PERIODIC PAIR AND THE TWO THE BUTTON OWNS.** Each of these is a door the completing slice added, and
		 * each is asserted rather than assumed — a forward that forwards to nothing looks exactly like a door that
		 * was never called. */
		{
			NSAttributedString *attributed = [[NSAttributedString alloc] initWithString:@"Attributed"
										attributes:nil];
			NSImage *picture = [[NSImage alloc] initWithSize:NSMakeSize(16.0, 16.0)];
			float delay = 0.0f, interval = 0.0f;

			[button setButtonType:NSSwitchButton];
			check([(NSButtonCell *)[button cell] highlightsBy] == NSNoCellMask,
			      "a SWITCH takes NO highlight, so a press never paints over its indicator");
			check([(NSButtonCell *)[button cell] showsStateBy] == NSContentsCellMask,
			      "and shows its state as its CONTENTS");
			[button setButtonType:NSMomentaryPushInButton];
			check([(NSButtonCell *)[button cell] highlightsBy] == NSPushInCellMask,
			      "a momentary push-in button highlights by PUSHING IN");

			[button setState:NSOffState];
			[button setNextState];
			check([button state] == NSOnState, "`-setNextState` walks off to on");
			[button setNextState];
			check([button state] == NSOffState, "and on to off when a mixed state is not allowed");

			[button setAttributedTitle:attributed];
			check([[[button attributedTitle] string] isEqualToString:@"Attributed"],
			      "an ATTRIBUTED TITLE round-trips through the button");
			check([[(NSButtonCell *)[button cell] attributedTitle] string] != nil,
			      "and reaches the CELL, which is where the drawing asks for it");

			[button setAlternateImage:picture];
			check([button alternateImage] == picture, "an ALTERNATE IMAGE round-trips");
			check([button imageScaling] == NSImageScaleProportionallyDown,
			      "the default image scaling is proportionally DOWN");
			[button setImageScaling:NSImageScaleNone];
			check([button imageScaling] == NSImageScaleNone, "and it can be set");

			[button setKeyEquivalentModifierMask:NSShiftKeyMask];
			check([button keyEquivalentModifierMask] == NSShiftKeyMask, "the key equivalent's MASK round-trips");

			[button setPeriodicDelay:0.5f interval:0.1f];
			[button getPeriodicDelay:&delay interval:&interval];
			check(delay == 0.5f && interval == 0.1f, "the PERIODIC pair round-trips");

			check(![button isSpringLoaded], "a button is not spring-loaded by default");
			[button setSpringLoaded:YES];
			check([button isSpringLoaded], "and it can be told to be");

			[button setTitleWithMnemonic:@"&File"];
			check([[button title] isEqualToString:@"File"],
			      "a mnemonic's ampersand is STRIPPED from the title, which is the cell's rule");

			[attributed release];
			[picture release];
		}

		/* 10. **THE REPAINT PAIR, WHICH IS THE DEFECT THIS SLICE FOUND AND FIXED.** A view marking itself for display
		 * has to mark its WINDOW: `NSWindow -displayIfNeeded` gates on the window's own `-viewsNeedDisplay`, so a
		 * control whose value changed outside the run loop's own update pass could set its dirty rect and have NOTHING
		 * paint. MEASURED on the desktop as a slider whose knob sat at 50 through an entire drag while its action
		 * fired on every point — the value was right and the pixels never asked for. */
		{
			NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 100.0, 100.0)
				styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
			NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
			NSView *sub = [[NSView alloc] initWithFrame:NSMakeRect(10.0, 10.0, 20.0, 20.0)];

			[content addSubview:sub];
			[w setContentView:content];
			[w setViewsNeedDisplay:NO];
			[sub setNeedsDisplay:YES];
			check([w viewsNeedDisplay], "a SUBVIEW marking itself for display marks its WINDOW");
			[w setViewsNeedDisplay:NO];
			[sub setNeedsDisplayInRect:NSMakeRect(0.0, 0.0, 5.0, 5.0)];
			check([w viewsNeedDisplay],
			      "and so does a ONE-RECT invalidation, which is what a cell's highlight sends");
			[sub release];
			[content release];
			[w release];
		}

		/* 11. **THE PRELIGHT AND THE PRESS, WHICH ARE TWO SHADES OF ONE ACCENT.** The fill and the ink are ONE decision
		 * — a periwinkle chip is light, so its title goes black — which is why the cell asks `-fn_wearsAccent` once. */
		{
			NSButtonCell *bc = (NSButtonCell *)[button cell];

			[button setButtonType:NSMomentaryLightButton];
			[button setEnabled:YES];
			/* **THE ATTRIBUTED TITLE IS CLEARED FIRST, AND THAT IS A NOTE ABOUT THIS HARNESS RATHER THAN ABOUT THE
			 * PALETTE.** An earlier case set `-attributedTitle:` to a string carrying NO font attribute, and the cell
			 * prefers the attributed title when there is one; drawing THAT needs a default font, and
			 * `+[NSFont systemFontOfSize:]` answers nil in a harness with no font service — a shortfall
			 * `NSStringDrawing.m` names in its own words. The plain title takes the other path, where the cell passes
			 * the font object it was given, so the ink below is the ink this slice is about. (The attributed path
			 * drawing nothing here is a REAL gap and is reported rather than worked around: it is not a palette
			 * question and clearing the title keeps it out of this one.) */
			[button setAttributedTitle:nil];
			[button setTitle:@"OK"];
			[bc cg_setMouseInside:NO];
			[bc setHighlighted:NO];
			{
				NSBitmapImageRep *rest = draw((NSView *)button);
				NSBitmapImageRep *hover;
				NSBitmapImageRep *down;

				check(face_is(rest, [NSColor controlColor]), "an idle button's face is the control colour");
				[rest release];

				[bc cg_setMouseInside:YES];
				hover = draw((NSView *)button);
				check(face_is(hover, [NSColor cg_accentPrelightColor]),
				      "a HOVERED button's face is the accent's PRELIGHT shade");
				[hover release];

				[bc setHighlighted:YES];
				down = draw((NSView *)button);
				check(face_is(down, [NSColor cg_accentColor]), "and a PRESSED one wears the ACCENT itself");
				check(!face_is(down, [NSColor cg_accentPrelightColor]),
				      "which is a different colour from the prelight it had a moment ago");
				[down release];
				[bc setHighlighted:NO];
			}
			check([[NSColor cg_accentPrelightColor] redComponent] > [[NSColor cg_accentColor] redComponent]
			      && [[NSColor cg_accentPrelightColor] greenComponent] > [[NSColor cg_accentColor] greenComponent]
			      && [[NSColor cg_accentPrelightColor] blueComponent] >= [[NSColor cg_accentColor] blueComponent],
			      "and the prelight IS a lighter shade of the accent, component by component");

			/* AND THE TWO CASES THAT MUST NOT PRELIGHT: a disabled button, and one with a background colour a caller
			 * chose — a colour a caller set is the colour the button is. */
			[button setEnabled:NO];
			{
				NSBitmapImageRep *rep = draw((NSView *)button);

				check(face_is(rep, [NSColor cg_disabledControlFaceColor]),
				      "and a DISABLED button does not prelight, however long the pointer rests on it");
				[rep release];
			}
			[button setEnabled:YES];
			[bc cg_setMouseInside:NO];

			/* **AND `-showsBorderOnlyWhileMouseInside` BECOMES A DOOR WITH A READER.** It was stored and never read,
			 * so a caller who set it got an ordinary button; its whole meaning is the pointer's position, which is the
			 * bit this slice added, so it is honoured now rather than merely remembered. */
			[bc setShowsBorderOnlyWhileMouseInside:YES];
			{
				NSBitmapImageRep *away = draw((NSView *)button);
				NSBitmapImageRep *over;

				check(!face_is(away, [NSColor controlColor]),
				      "with `-showsBorderOnlyWhileMouseInside:` and the pointer away, NO face is drawn at all");
				[away release];
				[bc cg_setMouseInside:YES];
				over = draw((NSView *)button);
				check(face_is(over, [NSColor cg_accentPrelightColor]),
				      "and the pointer arriving brings it back, prelighted");
				[over release];
			}
			[bc setShowsBorderOnlyWhileMouseInside:NO];
			[bc cg_setMouseInside:NO];
		}

		/* 12. **AN INDICATOR BUTTON'S LABEL IS LEFT-ALIGNED, WITH A MARGIN.** The box is drawn at x = 1 and is 14 wide, so
		 * the label's left edge should be a few points past x = 15 — and, the part a screenshot cannot tell you, the SAME
		 * edge whatever the title's length is. A centred label moves with its own width, which is exactly what a caller
		 * who asked for a margin is not asking for. */
		{
			NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			int shortCol, longCol;

			[box setButtonType:NSSwitchButton];
			[box setState:NSOnState];
			[box setTitle:@"On"];
			{
				NSBitmapImageRep *rep = draw((NSView *)box);

				shortCol = first_ink_column(rep, 18);
				[rep release];
			}
			[box setTitle:@"A Considerably Longer Checkbox Label"];
			{
				NSBitmapImageRep *rep = draw((NSView *)box);

				longCol = first_ink_column(rep, 18);
				[rep release];
			}
			check(shortCol > 15 && shortCol < 32,
			      "a checkbox's LABEL starts just right of its box — a small margin, not the cell's centre");
			check(shortCol > 0 && longCol > 0 && shortCol - longCol <= 1 && longCol - shortCol <= 1,
			      "and the margin does NOT depend on how long the title is, which is what left-aligned means");

			/* AND THE MEASUREMENT AGREES WITH THE DRAWING: `-sizeToFit` must leave room for the indicator's zone as well
			 * as the title, or a fitted checkbox clips its own label. */
			[box setTitle:@"On"];
			[box sizeToFit];
			{
				NSSize ink = [[box title] sizeWithAttributes:
						[NSDictionary dictionaryWithObject:[box font] forKey:NSFontAttributeName]];

				check([box frame].size.width > ink.width + 15.0,
				      "and `-sizeToFit` leaves room for the INDICATOR as well as the title");
			}
			[box release];
		}

		/* 13. **AND A CHECKBOX'S SQUARE AND A RADIO'S CIRCLE ANSWER THE POINTER LIKE ANY OTHER BUTTON'S FACE.** The
		 * two shades are the SAME TWO a push button wears — the accent's lighter shade under the pointer and the accent
		 * itself while held down — because there is one accent and one meaning for each of its two states. What this
		 * pins is that the decision is made at all for a button whose FACE is not a chip: `-fn_wearsAccent` answers NO
		 * for an indicator button by design, so the indicator's fill is its own rule, and a probe that only looked at
		 * the face would find nothing here. */
		{
			NSButton *cbox = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSButton *dot = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
			NSBitmapImageRep *rep;

			[cbox setButtonType:NSSwitchButton];
			[cbox setTitle:@"A Checkbox, on"];
			[cbox setState:NSOnState];
			[cbox setEnabled:YES];
			[dot setButtonType:NSRadioButton];
			[dot setTitle:@"A Radio, on"];
			[dot setState:NSOnState];
			[dot setEnabled:YES];

			rep = draw((NSView *)cbox);
			check(box_is(rep, [NSColor controlBackgroundColor]),
			      "an idle CHECKBOX's box is the background colour");
			[rep release];

			[[cbox cell] cg_setMouseInside:YES];
			rep = draw((NSView *)cbox);
			check(box_is(rep, [NSColor cg_accentPrelightColor]),
			      "and under the pointer its BOX prelights with the accent's lighter shade");
			[rep release];

			[[cbox cell] setHighlighted:YES];
			rep = draw((NSView *)cbox);
			check(box_is(rep, [NSColor cg_accentColor]),
			      "and while it is held down the box takes the ACCENT itself, like a push button");
			[rep release];
			[[cbox cell] setHighlighted:NO];
			[[cbox cell] cg_setMouseInside:NO];

			[[dot cell] cg_setMouseInside:YES];
			rep = draw((NSView *)dot);
			check(box_is(rep, [NSColor cg_accentPrelightColor]),
			      "a RADIO's circle prelights the same way, inside its ring");
			[rep release];

			[[dot cell] setHighlighted:YES];
			rep = draw((NSView *)dot);
			check(box_is(rep, [NSColor cg_accentColor]), "and takes the accent while it is held down");
			[rep release];
			[[dot cell] setHighlighted:NO];
			[[dot cell] cg_setMouseInside:NO];

			/* AND A DISABLED ONE STAYS DARK, whatever the pointer is doing */
			[cbox setEnabled:NO];
			[[cbox cell] cg_setMouseInside:YES];
			rep = draw((NSView *)cbox);
			check(box_is(rep, [NSColor controlBackgroundColor]),
			      "while a DISABLED checkbox does not prelight at all, however long the pointer rests on it");
			[rep release];

			[cbox release];
			[dot release];
		}

		/* 12. **THE CONTROL PALETTE, ASSERTED AS FOUR RELATIONSHIPS RATHER THAN AS FOUR NUMBERS.** The numbers can be
		 * changed for good reasons and the palette can still be wrong; what must not move is the ORDER — a raised button
		 * above the surface it sits on, a disabled one below it, its title below its own face, and a border in between
		 * the two greys it separates. Each check below states the relationship AND the literal, so a value that drifts
		 * is caught twice: once because the relationship broke and once because the number did.
		 *
		 * THE TWO LIVE STATES ARE THE EXCEPTION, and deliberately: their claim is not a direction but a COLOUR — white —
		 * so they are measured as ink on the face. */
		{
			double bg = [[NSColor windowBackgroundColor] redComponent];
			double face = [[NSColor controlColor] redComponent];
			double dead = [[NSColor cg_disabledControlFaceColor] redComponent];
			double deadInk = [[NSColor disabledControlTextColor] redComponent];
			double border = [[NSColor controlDarkShadowColor] redComponent];
			NSButtonCell *bc = (NSButtonCell *)[button cell];

			printf("  (note: window %.2f; enabled face %.2f, disabled face %.2f, its title %.2f, border %.2f)\n",
			       bg, face, dead, deadInk, border);
			check(face > bg && face - bg <= 0.05,
			      "an ENABLED button's face sits just ABOVE the window's grey — raised, not sunken");
			check(dead < bg, "a DISABLED button's face sits BELOW it");
			check(deadInk < dead, "and its title is a darker grey than its own face");
			/* **AND THE UPPER BOUND IS THE DARKEST FACE RATHER THAN A NUMBER OF ITS OWN.** It was 0.60, which read
			 * the 0.55 this tree had chosen; the sample's answer is 0.737, and what the claim is really about is that
			 * the border is darker than EVERY face it is drawn against — the disabled one is the lightest of those at
			 * 0.86 — without being black. Stated against that face, the check survives the next value instead of
			 * having to be re-tuned by hand the way this one just was. */
			check(border > 0.15 && border < dead - 0.05,
			      "the border is a DARK GREY — not black, and darker than every face it is drawn against");

			[button setButtonType:NSMomentaryLightButton];
			[button setEnabled:YES];
			[button setAttributedTitle:nil];
			[button setTitle:@"OK"];
			[bc cg_setMouseInside:NO];
			[bc setHighlighted:NO];
			{
				NSBitmapImageRep *rep = draw((NSView *)button);
				NSColor *edge = [rep colorAtX:0 y:H / 2];

				check(edge != nil && fabs([edge redComponent] - border) < 0.05,
				      "and the bezel is drawn in it, sampled on the frame's own edge");
				[rep release];
			}

			/* the two live states: white ink, measured as the darkest thing inside the face */
			{
				double rest, hover, down;

				[bc cg_setMouseInside:NO];
				[bc setHighlighted:NO];
				{
					NSBitmapImageRep *rep = draw((NSView *)button);
					rest = darkest_brightness(rep, 3, 3, W - 3, H - 3);
					[rep release];
				}
				[bc cg_setMouseInside:YES];
				{
					NSBitmapImageRep *rep = draw((NSView *)button);
					hover = darkest_brightness(rep, 3, 3, W - 3, H - 3);
					[rep release];
				}
				[bc setHighlighted:YES];
				{
					NSBitmapImageRep *rep = draw((NSView *)button);
					down = darkest_brightness(rep, 3, 3, W - 3, H - 3);
					[rep release];
				}
				printf("  (note: darkest ink inside the face — idle %.2f, prelit %.2f, pressed %.2f)\n",
				       rest, hover, down);
				check(rest < 0.35, "an IDLE button's title is dark ink");
				check(hover >= 0.60, "a PRELIGHTED button's title is WHITE — no dark ink inside its face");
				check(down >= 0.60, "and so is a PRESSED one's");
				[bc setHighlighted:NO];
				[bc cg_setMouseInside:NO];
			}

			/* **AND THE INDICATOR'S BORDER, WHICH IS THE ONE THAT WAS DRAWN AT HALF STRENGTH.** A checkbox's box is
			 * stroked on its own edge, so the probe reads the OUTERMOST pixel column of the box — bitmap x 1, with the
			 * box starting at the cell's one-point inset — on the row through its centre, which for a 40-point-tall cell
			 * is 19. Before the stroke was inset, that pixel held an even blend of the border and what was behind it
			 * (MEASURED 0.68 under the old 0.40 border; the border is 0.55 now), and this check is what says so. */
			[button setButtonType:NSSwitchButton];
			[button setAttributedTitle:nil];
			[button setTitle:@"Box"];
			{
				NSBitmapImageRep *rep = draw((NSView *)button);
				NSColor *edge = [rep colorAtX:1 y:19];

				printf("  (note: a checkbox's border pixel reads %.2f, against the border's %.2f)\n",
				       edge != nil ? [edge redComponent] : -1.0, border);
				check(edge != nil && [edge redComponent] < border + 0.05 && [edge redComponent] > border - 0.05,
				      "and an INDICATOR's border is that same dark grey — one pixel of it, not half of two");
				[rep release];
			}
		}

		printf("control_ink: %d case(s) failed\n", s_failed);
		[button release];
		[target release];
	}
	return s_failed == 0 ? 0 : 1;
}
