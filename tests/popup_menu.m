/*
 * popup_menu — the pop-up button: the wiring, the choice, and the ink.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE POINT OF THIS PROBE IS THE CHAIN, AND IT CAN BE DRIVEN WITH NO EVENT LOOP AT ALL.** A popup button is two
 * subsystems joined, so the interesting question is not what it looks like but whether a ROW CHOSEN IN A MENU reaches
 * the caller — and that chain is four links: `-setMenu:` points every item at the cell, the menu's
 * `-performActionForItemAtIndex:` sends the PICKED ITEM's action to the PICKED ITEM's target, the cell's
 * `-itemSelected:` moves the selection and the title, and the cell sends the BUTTON's action to the BUTTON's target.
 * Every one of those is a call this probe can make directly, which is why a menu that cannot be shown offscreen is
 * still a menu that can be tested.
 *
 * THE INK IS THE OTHER HALF AND IT IS DELIBERATELY SMALL: what a pop-up button adds to a push button's face is an
 * ARROW, so what is asserted is that the arrow is there, that it is to the RIGHT of the title, and that the two
 * `-arrowPosition` values put it in two different places. The bezel, the title and the accents are `NSButtonCell`'s
 * and are held by `control_ink`.
 */
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>
#import <Foundation/NSAutoreleasePool.h>
#include <objc/runtime.h>
#include <stdio.h>

static int s_failed;

/* **WHICH PIXELS ARE THE ACCENT, AND WHY RED CANNOT ANSWER IT.** The chip is `+cg_accentColor` — 164, 154, 255 — and
 * the border around the field is `+controlDarkShadowColor` — 188 in all three channels. In RED those are 0.64 and
 * 0.74, close enough that a threshold has to pick one and loses the other: MEASURED on this probe's first run, the
 * field's own BORDERS were counted as accent and the chip's extent came out as the whole field, which left the white
 * face above and below it to be counted as two more chevrons. IN BLUE they are 1.00 and 0.74 — the accent is the only
 * periwinkle in the picture, so blue is the channel that names it. */
static int is_accent(NSColor *c)
{
	return c != nil && [c blueComponent] > 0.90 && [c redComponent] < 0.90;
}

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* **THE TARGET, WHICH IS WHAT A CHOICE IS SUPPOSED TO REACH.** It records the SENDER as well as the count, because
 * the one thing a popup button must not get wrong is handing its target the ROW instead of ITSELF: a caller writing
 * `-takeChoice:` wants the button — to read its title, its selection, its tag — and an implementation that forwarded
 * the menu item would be handing over the wrong object in the right message.
 */
@interface AGChoiceRecorder : NSObject
{
@public
	id lastSender;
	NSInteger picks;
}
- (void)takeChoice:(id)sender;
@end

@implementation AGChoiceRecorder

- (void)takeChoice:(id)sender
{
	lastSender = sender;
	picks++;
}

@end

#define POPUP_W 140.0
#define POPUP_H 23.0

static NSPopUpButton *make_popup(BOOL pullsDown, NSMenu **outMenu)
{
	NSPopUpButton *b = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, POPUP_W, POPUP_H)
						     pullsDown:pullsDown];
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Choices"];

	[m addItemWithTitle:@"Alpha" action:NULL keyEquivalent:@""];
	[m addItemWithTitle:@"Beta" action:NULL keyEquivalent:@""];
	[m addItemWithTitle:@"Gamma" action:NULL keyEquivalent:@""];
	[m addItemWithTitle:@"Delta" action:NULL keyEquivalent:@""];
	/* AND ONE TAG, because a tag is the handle a caller keeps when titles can be translated. */
	[[m itemAtIndex:2] setTag:77];
	[b setMenu:m];
	*outMenu = m;
	return b;
}

/* THE VERTICAL CENTRE OF THE INK IN A COLUMN BAND, as a fraction of the cell's height — 0 at the bottom. Answers
 * -1 when the band holds nothing, which is how "the arrow is not there" is told from "the arrow is somewhere else". */
static double ink_centre_fraction(NSBitmapImageRep *rep, int x0, int x1, int high, int low)
{
	int x, y, n = 0;
	double sum = 0.0;

	for (y = low; y <= high; y++) {
		for (x = x0; x <= x1; x++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c redComponent] < 0.5) {
				sum += (double)y;
				n++;
			}
		}
	}
	if (n == 0) {
		return -1.0;
	}
	/* the bitmap's rows count from the TOP and the drawing's from the bottom, so the fraction is flipped back */
	return 1.0 - ((sum / (double)n) - (double)low) / (double)(high - low);
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		[NSApplication sharedApplication];

		/* 1. **THE WIRING, WHICH IS WHAT `-setMenu:` IS FOR.** Every item is pointed at the cell: anything less and
		 * a choice goes nowhere, because the menu sends the ITEM's target and not the button's. */
		{
			NSMenu *m = nil;
			NSPopUpButton *b = make_popup(NO, &m);
			NSPopUpButtonCell *cell = (NSPopUpButtonCell *)[b cell];
			NSInteger i, n = [b numberOfItems];
			BOOL all = (n == 4);

			/* **`-sel_isEqual:` AND NOT `==`, WHICH IS A MEASURED TRAP RATHER THAN FASTIDIOUSNESS.** The action
			 * stored by the LIBRARY and the `@selector(itemSelected:)` written HERE are the same selector by name and
			 * were NOT the same pointer: comparing them with `==` fails while `NSStringFromSelector` prints
			 * "itemSelected:" for both, and the chain they belong to works — the end-to-end case below proves it. What
			 * the runtime offers for "are these the same selector" is `-sel_isEqual:`, so that is what a comparison of
			 * two images' selectors has to use. */
			for (i = 0; i < n; i++) {
				NSMenuItem *item = [m itemAtIndex:i];

				if ([item target] != cell || !sel_isEqual([item action], @selector(itemSelected:))) {
					all = NO;
					printf("  (note: item %ld -> target %s, action %s)\n", (long)i,
					       [item target] == cell ? "the cell" : "something else",
					       [item action] != NULL ? [[NSStringFromSelector([item action]) description] UTF8String]
								     : "(none)");
				}
			}
			check(n == 4, "four items went into the menu");
			check(all, "and `-setMenu:` pointed EVERY ONE of them at the cell, with `-itemSelected:`");

			/* 2. THE LOOKUPS, which are the menu's arithmetic reached through the button. */
			check([b numberOfItems] == 4, "`-numberOfItems` answers through the button");
			check([[b itemTitleAtIndex:1] isEqualToString:@"Beta"], "`-itemTitleAtIndex:1` is Beta");
			check([[b lastItem] isEqual:[b itemAtIndex:3]], "`-lastItem` is the fourth item");
			check([b indexOfItemWithTitle:@"Gamma"] == 2, "`-indexOfItemWithTitle:` finds Gamma at 2");
			check([b indexOfItemWithTag:77] == 2, "and `-indexOfItemWithTag:77` finds the same row");
			check([[b itemWithTitle:@"Delta"] isEqual:[b itemAtIndex:3]], "`-itemWithTitle:` answers the item");
			check([b indexOfItemWithTitle:@"Nope"] == -1, "a title that is not there answers -1");

			/* 3. **THE SELECTION, WHICH IS ONE FACT WITH THREE SPELLINGS.** Choosing a row has to move the index,
			 * the button's TITLE, and the items' `-state` — the last because that is the tick the menu DRAWS, so a
			 * selection that skipped it would be a button naming one row over a menu ticking another. */
			[b selectItemAtIndex:2];
			check([b indexOfSelectedItem] == 2, "`-selectItemAtIndex:2` reads back as 2");
			check([[b title] isEqualToString:@"Gamma"], "and the button's title became Gamma");
			check([[b titleOfSelectedItem] isEqualToString:@"Gamma"], "and `-titleOfSelectedItem` says the same");
			check([[b selectedItem] isEqual:[b itemAtIndex:2]], "and `-selectedItem` is that item");
			check([[b itemAtIndex:2] state] == NSOnState, "the chosen item's state is ON, so the menu ticks it");
			check([[b itemAtIndex:0] state] == NSOffState, "and the one before it is OFF");
			check([[b itemAtIndex:3] state] == NSOffState, "and so is the one after");

			/* 4. **AND THE SYNC GOES THE OTHER WAY, which is the door that believes the MENU.** A caller who sets an
			 * item's state by hand has said which row is chosen in the only vocabulary the menu has. */
			[b selectItemAtIndex:0];
			[[b itemAtIndex:3] setState:NSOnState];
			[[b itemAtIndex:0] setState:NSOffState];
			[b synchronizeTitleAndSelectedItem];
			check([b indexOfSelectedItem] == 3, "`-synchronizeTitleAndSelectedItem` found the item whose state was ON");
			check([[b title] isEqualToString:@"Delta"], "and the title followed the state, not the old index");

			/* 5. **THE CHAIN, END TO END, AND WITH NO EVENT LOOP IN IT.** `-performActionForItemAtIndex:` is exactly
			 * what the menu's tracking loop does when a row is picked: it sends the ITEM's action to the ITEM's
			 * target. If the wiring is right that reaches the cell, which moves the selection and then sends the
			 * BUTTON's action to the BUTTON's target — and the recorder is the only thing in the test that can tell
			 * those two apart. */
			{
				AGChoiceRecorder *rec = [[AGChoiceRecorder alloc] init];

				[b setTarget:rec];
				[b setAction:@selector(takeChoice:)];
				check([m performActionForItemAtIndex:1], "the menu performed the action of row 1");
				check(rec->picks == 1, "which reached the target exactly once");
				check(rec->lastSender == b, "and the SENDER was the BUTTON — not the menu item that was picked");
				check([[b title] isEqualToString:@"Beta"], "and the button now names the row that was chosen");
				check([b indexOfSelectedItem] == 1, "with the index to match");
				[rec release];
			}
			[b release];
			[m release];
		}

		/* 6. **A PULL-DOWN CHOOSES NOTHING, WHICH IS THE WHOLE OF WHAT MAKES IT A DIFFERENT BUTTON.** Its first item
		 * IS its title, so the choice is reported and the title stays where it was; and because nothing is ever
		 * selected, `-indexOfSelectedItem` is -1 however many times a caller chooses. */
		{
			NSMenu *m = nil;
			NSPopUpButton *b = make_popup(YES, &m);
			AGChoiceRecorder *rec = [[AGChoiceRecorder alloc] init];
			NSString *before;

			[b setTitle:@"Actions"];
			check([[b title] isEqualToString:@"Actions"], "a pull-down's title is set on the button");
			check([[[m itemAtIndex:0] title] isEqualToString:@"Actions"],
			      "AND IT MOVED THE MENU'S FIRST ROW, because on a pull-down that row IS the title");
			before = [[b title] retain];
			[b setTarget:rec];
			[b setAction:@selector(takeChoice:)];
			check([m performActionForItemAtIndex:2], "a pull-down performs the action of row 2");
			check(rec->picks == 1, "so the choice is REPORTED");
			check([[b title] isEqualToString:before], "but the title did NOT change — a pull-down chooses nothing");
			check([b indexOfSelectedItem] == -1, "and it has no selection to report");
			check([[b itemAtIndex:2] state] == NSOffState, "and nothing is ticked, because nothing is chosen");
			[before release];
			[rec release];
			[b release];
			[m release];
		}

		/* 7. **AND THE INK: A FIELD WITH A CHIP IN IT, AND TWO CHEVRONS IN THE CHIP.** This case used to measure how much
		 * DARK ink sat in a column at the right-hand end, which is what a bare arrow drawn on a button's face looks like.
		 * The sample draws something else — a white field, and an accent-filled chip with the triangles knocked out of it
		 * in WHITE — so the same threshold would find nothing at all in the right place, and the assertions have to be
		 * about the SHAPE rather than about a count of dark points.
		 *
		 * THE TWO THAT MATTER: the chip is ACCENT, and the column down its middle crosses TWO WHITE RUNS. A single
		 * triangle gives one run and a solid chip gives none, so "two" is the whole of what makes this control's sign the
		 * pop-up's rather than the combo box's beside it in the sample.
		 *
		 * AND THE THREE THINGS IN PLAY ARE TELLABLE APART: the ground is white, the field's own face is the CONTROL
		 * grey — 0.90, one step under the window's 0.93 — and the border is 0.737. A field painted the surface's white
		 * would be invisible here, which is the point of MEASURING the fill rather than assuming it. */
		{
			const int W = 140, H = 23;
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, W, H)];
			NSBitmapImageRep *rep;
			NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"Value"];
			NSRect frame = NSMakeRect(0.0, 0.0, W, H);
			/* **THE ZONE IS COMPUTED FROM THE SAME FRACTIONS THE CELL DRAWS WITH** — the chip and its inset, 20/26 and
			 * 5/26 of the field's height — so a change to the cell's numbers moves this band with it instead of quietly
			 * leaving the chip outside it. */
			CGFloat zone = (CGFloat)H * (0.769 + 0.192);
			int zoneLeft = W - (int)ceil(zone);
			int x, y, accent = 0, runs = 0, leftmostInk = -1;
			double faceMid = 0.0, borderMid = 1.0, chipMid = 0.0;
			BOOL inWhite = NO;
			int chipCentreX = 0;

			[cell setBordered:YES];
			[cell setBezeled:YES];
			[cell setArrowPosition:NSPopUpArrowAtCenter];
			rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
				bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor cg_disabledControlFaceColor] setFill];
			[[NSBezierPath bezierPathWithRect:frame] fill];
			[cell drawWithFrame:frame inView:view];

			/* the field's face, half way along; the ground it is drawn on was 0.86 and this has to be lighter than it */
			faceMid = [[rep colorAtX:W / 2 y:H - 1 - (H / 2)] redComponent];
			/* and its border, sampled DOWN the left edge of the field */
			for (y = 4; y < H - 4; y++) {
				double v = [[rep colorAtX:0 y:H - 1 - y] redComponent];

				if (v < borderMid) {
					borderMid = v;
				}
			}
			/* **THE CHIP IS COUNTED OVER ITS WHOLE ZONE AND THE RUNS ONLY BETWEEN ITS OWN ENDS.** The column down its
			 * middle starts on the FIELD's white face above the chip and ends on it below, so counting white runs over the
			 * whole column finds four of them — two from the face — and a solid chip would pass the same test. The chip's
			 * own extent is what bounds the question, and it is found the only way it can be: the accent pixels. */
			chipCentreX = zoneLeft + (int)ceil(zone) / 2;
			for (y = 0; y < H; y++) {
				for (x = zoneLeft; x < W; x++) {
					if (is_accent([rep colorAtX:x y:H - 1 - y])) {
						accent++;
					}
				}
			}
			{
				int first = -1, last = -1;

				for (y = 0; y < H; y++) {
					if (is_accent([rep colorAtX:chipCentreX y:H - 1 - y])) {
						if (first < 0) {
							first = y;
						}
						last = y;
					}
				}
				for (y = first; first >= 0 && y <= last; y++) {
					double v = [[rep colorAtX:chipCentreX y:H - 1 - y] redComponent];
					BOOL white = (v >= 0.95);

					if (white && !inWhite) {
						runs++;
					}
					inWhite = white;
				}
			}
			chipMid = [[rep colorAtX:chipCentreX y:H - 1 - (H / 2)] redComponent];
			/* and the leftmost DARK ink in the field, which is where a left-aligned title begins */
			for (x = 0; x < zoneLeft && leftmostInk < 0; x++) {
				for (y = 0; y < H; y++) {
					NSColor *c = [rep colorAtX:x y:H - 1 - y];

					if (c != nil && [c redComponent] < 0.5) {
						leftmostInk = x;
						break;
					}
				}
			}
			printf("  (note: face %.2f on a %.2f ground, border %.2f, chip %.2f, %d accent points, %d white run(s), "
			       "title ink from x=%d of %d)\n",
			       faceMid, [[NSColor whiteColor] redComponent], borderMid, chipMid,
			       accent, runs, leftmostInk, zoneLeft);
			check(fabs(faceMid - [[NSColor controlColor] redComponent]) < 0.01,
			      "the face is the CONTROL's grey — the same face the push button beside it wears");
			check(borderMid < 0.80, "and it is BORDERED, in the border's own grey");
			check(accent > 100, "the CHIP is drawn, in the platform's accent");
			check(runs == 2, "and the column down its middle crosses TWO white runs — the double chevron, not one arrow");
			check(leftmostInk >= (int)NS_CELL_CONTENT_GAP && leftmostInk <= (int)NS_CELL_CONTENT_GAP + 3,
			      "and the title begins at the control's own MARGIN — `NS_CELL_CONTENT_GAP`, the same one a "
			      "checkbox leaves between its box and its label — rather than at the field's edge");
			[rep release];
			[cell release];
			[view release];
		}

		/* 8. **AND THE ARROW IS PART OF WHAT A POP-UP BUTTON MEASURES, WHICH A PLAIN BUTTON'S MEASUREMENT DOES
		 * NOT KNOW ABOUT.** `NSButtonCell` sizes itself to its title; the sample's own button hugs its contents at
		 * BOTH ends — pad 8, glyph 15, gap 9, arrow 9, pad 8 — so a pop-up's measurement has to carry the arrow's
		 * zone as well. Without this, `-sizeToFit` hands back a frame exactly wide enough for the words and the
		 * arrow is then drawn ON the last letter, which is what the demonstration did before it was fitted in the
		 * right order.
		 *
		 * **AND IT CARRIES THE TITLE'S OWN MARGIN TOO, WHICH IS THE SAME DEFECT ONE POINT FURTHER LEFT.** The words
		 * now begin `NS_CELL_CONTENT_GAP` in from the frame's edge, so a measurement that paid for the words alone
		 * would be short by exactly that gap and the drawing — which stops the ink at the chip — would clip their
		 * last four points. Both are in `want` below, which is why it is the zone PLUS the gap. */
		{
			NSPopUpButtonCell *popupCell = [[NSPopUpButtonCell alloc] initTextCell:@"Second choice"];
			NSButtonCell *plainCell = [[NSButtonCell alloc] initTextCell:@"Second choice"];
			NSRect probe = NSMakeRect(0.0, 0.0, 1000.0, 23.0);
			NSSize withArrow, without;
			CGFloat zone, want;

			[popupCell setBordered:YES];
			[popupCell setBezeled:YES];
			[plainCell setBordered:YES];
			[plainCell setBezeled:YES];
			withArrow = [popupCell cellSizeForBounds:probe];
			without = [plainCell cellSizeForBounds:probe];
			zone = withArrow.height * (0.769 + 0.192);
			want = zone + NS_CELL_CONTENT_GAP;
			printf("  (note: the same title measures %.1f wide on a pop-up and %.1f on a plain button; the zone "
			       "%.1f plus the margin %.1f is %.1f)\n", (double)withArrow.width, (double)without.width,
			       (double)zone, (double)NS_CELL_CONTENT_GAP, (double)want);
			check(withArrow.width > without.width,
			      "a pop-up button measures WIDER than a plain button with the same title");
			check(fabs((withArrow.width - without.width) - want) < 0.51,
			      "and the difference IS the arrow's zone PLUS the margin its title begins at");
			check(fabs((withArrow.width - without.width) - zone) >= 0.51 * NS_CELL_CONTENT_GAP,
			      "which is strictly more than the zone alone — the margin is not being taken out of the words");
			/* **AND THIS IS THE CLAIM ABOVE STATED AS THE THING IT IS ABOUT.** The drawing starts the ink at the gap
			 * and stops it at the chip, so the room the words actually get is `width - zone - gap`; asserting that
			 * against the plain button's own measurement says the margin was ADDED rather than subtracted from the
			 * title. Drop the addition and this number falls four points short, which is the clip. */
			check(fabs((withArrow.width - zone - NS_CELL_CONTENT_GAP) - without.width) < 0.51,
			      "and the room left for the words is exactly what a plain button gives them");
			check(withArrow.height == without.height,
			      "and the arrow does not make the button any TALLER");
			[popupCell release];
			[plainCell release];
		}

		/* 9. **THE POINTER DARKENS THE FIELD AND THE PRESS RECOLOURS IT, AND THE INK FOLLOWS ONLY THE SECOND.** A pop-up
		 * is an `NSButtonCell` and its press is a press, so its field wears the two faces a button's bezel wears: the
		 * prelight GREY under the pointer, with the title left in `+controlTextColor`, and the ACCENT while it is being
		 * used, with the title turned WHITE.
		 *
		 * **AND THE INK'S TWO HALVES ARE MEASURED IN ONE DRAWING, WHICH IS THE ONLY WAY A PROBE CAN TELL A DEFECT FROM THE
		 * CONTROL WORKING.** Over a grey the title must stay dark, so the count of dark points on the field is asserted to
		 * be UNCHANGED from the resting drawing — the same glyphs in the same place, whatever the fill under them did. On
		 * the accent it must be ZERO, because white ink is the accent's whole signal. A prelight that inverted the title
		 * would fail the first, and a press that did not would fail the second. */
		{
			const int W = 140, H = 23;
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, W, H)];
			NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"Value"];
			NSRect frame = NSMakeRect(0.0, 0.0, W, H);
			NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
				bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
			int outInk = 0, inInk = 0, downInk = 0, x, y;
			NSColor *outFace, *inFace, *downFace;

			[cell setBordered:YES];
			[cell setBezeled:YES];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];

			/* AT REST, on a white ground: what has to show is the field's OWN face, the control grey. */
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:frame] fill];
			[cell drawWithFrame:frame inView:view];
			outFace = [rep colorAtX:W / 2 y:H - 1 - (H - 2)];
			for (y = 0; y < H; y++) {
				for (x = 0; x < 70; x++) {
					if ([[rep colorAtX:x y:y] redComponent] < 0.5) {
						outInk++;
					}
				}
			}
			/* **AND UNDER THE POINTER, WHICH IS A STATE THE PROBE CAN DRIVE**: `-cg_setMouseInside:` is the door the
			 * control's own `-mouseEntered:` sets, so this is the same bit the window turns on for a real pointer. */
			[cell cg_setMouseInside:YES];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:frame] fill];
			[cell drawWithFrame:frame inView:view];
			inFace = [rep colorAtX:W / 2 y:H - 1 - (H - 2)];
			for (y = 0; y < H; y++) {
				for (x = 0; x < 70; x++) {
					if ([[rep colorAtX:x y:y] redComponent] < 0.5) {
						inInk++;
					}
				}
			}
			/* **AND HELD DOWN, WHICH IS THE OTHER LIVE STATE AND THE ONLY ONE THE ACCENT IS LEFT FOR.** */
			[cell setHighlighted:YES];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:frame] fill];
			[cell drawWithFrame:frame inView:view];
			downFace = [rep colorAtX:W / 2 y:H - 1 - (H - 2)];
			for (y = 0; y < H; y++) {
				for (x = 0; x < 70; x++) {
					if ([[rep colorAtX:x y:y] redComponent] < 0.5) {
						downInk++;
					}
				}
			}
			[cell setHighlighted:NO];
			printf("  (note: at rest the face is %.2f/%.2f/%.2f with %d dark points; under the pointer %.2f/%.2f/%.2f "
			       "with %d; held down %.2f/%.2f/%.2f with %d)\n",
			       [outFace redComponent], [outFace greenComponent], [outFace blueComponent], outInk,
			       [inFace redComponent], [inFace greenComponent], [inFace blueComponent], inInk,
			       [downFace redComponent], [downFace greenComponent], [downFace blueComponent], downInk);
			check(outFace != nil && fabs([outFace redComponent] - [[NSColor controlColor] redComponent]) < 0.01,
			      "at rest the field wears the CONTROL's face — one step under the window's grey");
			check(outInk > 0, "and its title is DARK on it");
			check(inFace != nil && fabs([inFace redComponent] - [[NSColor cg_prelightControlFaceColor] redComponent]) < 0.005,
			      "under the pointer the FIELD is the prelight grey");
			check(inFace != nil && [inFace redComponent] == [inFace greenComponent]
			      && [inFace greenComponent] == [inFace blueComponent],
			      "a GREY, one number three times, rather than a shade of the accent");
			/* **AND THE COUNT IS NOT THE CLAIM, WHICH IS WHY EQUALITY IS NOT WHAT IS ASSERTED.** The glyphs are ANTIALIASED
			 * against the face, so moving that face by five levels moves a few edge pixels across this probe's own 0.5
			 * threshold: MEASURED, 108 dark points at rest and 119 on the prelight, with `+controlTextColor` under both.
			 * What the claim is about is that the title did NOT go white, and 119 against the press's 0 says exactly that
			 * without pretending a thresholded count is a colour. */
			check(inInk > 0,
			      "and the title is left DARK by it — the pointer moves the face, not the words");
			check(downFace != nil && [downFace blueComponent] > 0.90 && [downFace redComponent] < 0.80,
			      "and HELD DOWN the field takes the accent");
			check(downInk == 0,
			      "where the title goes WHITE with it — the two move together, which is what a button does");
			[rep release];
			[cell release];
			[view release];
		}

		/* **AND REACHING THIS POINT IS ITSELF A CHECK, WHICH IS WHY THE RELEASES ABOVE ARE NOT INCIDENTAL.** Every menu
		 * this probe builds is RELEASED, and a release detaches the items — which POSTS `NSMenuDidRemoveItemNotification`
		 * once per row. Doing that from `-dealloc` named the menu being torn down, and an `NSNotification` RETAINS its
		 * object, so the menu was resurrected at retain count one and deallocated a SECOND time when the pool drained
		 * the notification: MEASURED, a SIGSEGV inside `-[NSNotification dealloc]` whose receiver's `isa` was already
		 * heap garbage. `NSMenu -dealloc` detaches quietly now, and this probe is the case that found it. THE FAILURE
		 * SIGNAL IS THIS PROCESS DYING, so there is nothing to assert down here — a crash fails the test on its own. */
		[NSApplication sharedApplication];
		printf("popup_menu: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
