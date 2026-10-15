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

		/* 7. **AND THE INK: THE ARROW, AND WHERE THE TWO POSITIONS PUT IT.** The title is centred in the room left
		 * over, so an arrow at the CENTRE takes a column the contents keep out of and an arrow at the BOTTOM sits in
		 * the corner they never reach — which is the only difference between the two, and is measurable. */
		{
			const int W = 140, H = 23;
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, W, H)];
			NSBitmapImageRep *rep;
			NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"Value"];
			NSRect frame = NSMakeRect(0.0, 0.0, W, H);
			double centreAtBottom, centreAtCentre;
			int x, y, arrowInk = 0, titleInk = 0;
			/* **THE ARROW'S ZONE AT THE RIGHT, IN THE SAME FRACTIONS THE CELL DRAWS IT IN** — so this band is
			 * computed rather than written down, and a change to the cell's numbers moves the band with it
			 * instead of quietly leaving the arrow outside it. See the constants in `NSPopUpButtonCell.m`: the
			 * sample's margin is 8/24 of the button's height and its arrow is 9/24 across. */
			CGFloat zone = (CGFloat)H * (0.333 + 0.375);
			int zoneLeft = W - (int)ceil(zone) - 1;

			[cell setBordered:YES];
			[cell setBezeled:YES];
			[cell setArrowPosition:NSPopUpArrowAtBottom];
			rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
				bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
				colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:frame] fill];
			[cell drawWithFrame:frame inView:view];
			for (y = 0; y < H; y++) {
				for (x = 0; x < W; x++) {
					NSColor *c = [rep colorAtX:x y:y];

					if (c != nil && [c redComponent] < 0.5) {
						if (x >= zoneLeft) {
							arrowInk++;
						} else {
							titleInk++;
						}
					}
				}
			}
			printf("  (note: %d dark points right of x=%d — the arrow's zone, %.1f wide — and %d to its left)\n",
			       arrowInk, zoneLeft, (double)zone, titleInk);
			check(arrowInk > 0, "the ARROW is drawn, in the right-hand zone");
			check(titleInk > 0, "and the title is drawn to its left");

			centreAtBottom = ink_centre_fraction(rep, zoneLeft, W - 1, H - 1, 0);

			[cell setArrowPosition:NSPopUpArrowAtCenter];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:frame] fill];
			[cell drawWithFrame:frame inView:view];
			centreAtCentre = ink_centre_fraction(rep, zoneLeft, W - 1, H - 1, 0);
			printf("  (note: the arrow's ink sits at %.2f of the height when AtBottom and %.2f when AtCenter)\n",
			       centreAtBottom, centreAtCentre);
			check(centreAtBottom >= 0.0 && centreAtCentre >= 0.0, "the arrow is in the zone at both positions");
			check(centreAtCentre > centreAtBottom + 0.1,
			      "and AtCenter puts it HIGHER than AtBottom — which is the whole difference between them");
			[rep release];
			[cell release];
			[view release];
		}

		/* 8. **AND THE ARROW IS PART OF WHAT A POP-UP BUTTON MEASURES, WHICH A PLAIN BUTTON'S MEASUREMENT DOES
		 * NOT KNOW ABOUT.** `NSButtonCell` sizes itself to its title; the sample's own button hugs its contents at
		 * BOTH ends — pad 8, glyph 15, gap 9, arrow 9, pad 8 — so a pop-up's measurement has to carry the arrow's
		 * zone as well. Without this, `-sizeToFit` hands back a frame exactly wide enough for the words and the
		 * arrow is then drawn ON the last letter, which is what the demonstration did before it was fitted in the
		 * right order. */
		{
			NSPopUpButtonCell *popupCell = [[NSPopUpButtonCell alloc] initTextCell:@"Second choice"];
			NSButtonCell *plainCell = [[NSButtonCell alloc] initTextCell:@"Second choice"];
			NSRect probe = NSMakeRect(0.0, 0.0, 1000.0, 23.0);
			NSSize withArrow, without;
			CGFloat want;

			[popupCell setBordered:YES];
			[popupCell setBezeled:YES];
			[plainCell setBordered:YES];
			[plainCell setBezeled:YES];
			withArrow = [popupCell cellSizeForBounds:probe];
			without = [plainCell cellSizeForBounds:probe];
			want = withArrow.height * (0.333 + 0.375);
			printf("  (note: the same title measures %.1f wide on a pop-up and %.1f on a plain button; the zone "
			       "is %.1f)\n", (double)withArrow.width, (double)without.width, (double)want);
			check(withArrow.width > without.width,
			      "a pop-up button measures WIDER than a plain button with the same title");
			check(fabs((withArrow.width - without.width) - want) < 0.51,
			      "and the difference IS the arrow's zone, to within half a point");
			check(withArrow.height == without.height,
			      "and the arrow does not make the button any TALLER");
			[popupCell release];
			[plainCell release];
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
