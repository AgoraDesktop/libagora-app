/*
 * combo_box.m — THE COMBO BOX'S INK, AND THE ONE MARK THAT TELLS IT FROM THE POP-UP BESIDE IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
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
#import <AppKit/NSComboBox.h>
#import <AppKit/AGComboListView.h>
#import <AppKit/AGComboListCell.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSText.h>
#import <Foundation/NSNotification.h>
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

/* **A WATCHER, BECAUSE A PICK IS TWO THINGS AND ONLY ONE OF THEM IS INSIDE THE CELL.** The selection moves in the
 * control; the ACTION goes to the control's target, and a probe that only read the cell's index would pass on a
 * control whose action never fired. */
@interface Watcher : NSObject
{
@public
	int fired;
}
@end

@implementation Watcher
- (void)picked:(id)sender
{
	(void)sender;
	fired++;
}
@end

/* **A SOURCE FOR THE VIEW'S PROTOCOL, WITH A LIST THE PROBE CAN CHANGE UNDER THE BOX.** All four members are
 * implemented, because the two optional ones are the ones the routing has to ask for by name — an index for a typed
 * string and a completion for a prefix — and a stub that answered neither would leave those two paths untested. */
@interface AGViewSource : NSObject <NSComboBoxDataSource>
{
@public
	NSMutableArray *rows;
}
@end

@implementation AGViewSource
- (id)init
{
	if ((self = [super init]) != nil) {
		rows = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[rows release];
	[super dealloc];
}
- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox
{
	(void)aComboBox;
	return (NSInteger)[rows count];
}
- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
	(void)aComboBox;
	return (index >= 0 && index < (NSInteger)[rows count]) ? [rows objectAtIndex:(NSUInteger)index] : nil;
}
- (NSUInteger)comboBox:(NSComboBox *)aComboBox indexOfItemWithStringValue:(NSString *)string
{
	NSUInteger i;

	(void)aComboBox;
	for (i = 0; i < [rows count]; i++) {
		if ([[[rows objectAtIndex:i] description] isEqual:string]) {
			return i;
		}
	}
	return NSNotFound;
}
- (NSString *)comboBox:(NSComboBox *)aComboBox completedString:(NSString *)string
{
	(void)aComboBox;
	if ([rows count] > 0) {
		NSString *first = [[rows objectAtIndex:0] description];

		if ([first length] > [string length] &&
		    [first compare:string options:NSCaseInsensitiveSearch
			     range:NSMakeRange(0, [string length])] == NSOrderedSame) {
			return first;
		}
	}
	return nil;
}
@end

/* AND THE CELL'S PROTOCOL, WHICH IS A DIFFERENT SET OF NAMES — the point the two headers make. */
@interface AGCellSource : NSObject <NSComboBoxCellDataSource>
{
@public
	NSMutableArray *rows;
}
@end

@implementation AGCellSource
- (id)init
{
	if ((self = [super init]) != nil) {
		rows = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[rows release];
	[super dealloc];
}
- (NSInteger)numberOfItemsInComboBoxCell:(NSComboBoxCell *)cell
{
	(void)cell;
	return (NSInteger)[rows count];
}
- (id)comboBoxCell:(NSComboBoxCell *)cell objectValueForItemAtIndex:(NSInteger)index
{
	(void)cell;
	return (index >= 0 && index < (NSInteger)[rows count]) ? [rows objectAtIndex:(NSUInteger)index] : nil;
}
- (NSUInteger)comboBoxCell:(NSComboBoxCell *)cell indexOfItemWithStringValue:(NSString *)string
{
	NSUInteger i;

	(void)cell;
	for (i = 0; i < [rows count]; i++) {
		if ([[[rows objectAtIndex:i] description] isEqual:string]) {
			return i;
		}
	}
	return NSNotFound;
}
@end

/* AND A DELEGATE THAT COUNTS THE FOUR TIDINGS. */
@interface ComboWatcher : NSObject <NSComboBoxDelegate>
{
@public
	int popUps;
	int dismisses;
	int didChanges;
	int isChangings;
}
@end

@implementation ComboWatcher
- (void)comboBoxWillPopUp:(NSNotification *)note { (void)note; popUps++; }
- (void)comboBoxWillDismiss:(NSNotification *)note { (void)note; dismisses++; }
- (void)comboBoxSelectionDidChange:(NSNotification *)note { (void)note; didChanges++; }
- (void)comboBoxSelectionIsChanging:(NSNotification *)note { (void)note; isChangings++; }
@end

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
	/* **AND ITS FACE IS THE FIELD'S WHITE RATHER THAN A CONTROL'S GREY.** The sample draws this control's field
	 * `#FFFFFF`, the tier's own text field is white, and a value is TYPED into a combo box — so its surface is the one
	 * a value is written on. The POP-UP is the one that departed from the sample and took a button's grey, and the pair
	 * differing here is the pair behaving as the two different things they are. */
	check(fabs([[rep colorAtX:W / 2 y:H - 1 - (H - 2)] redComponent] - [[NSColor controlBackgroundColor] redComponent]) < 0.01,
	      "the field's face is WHITE — the surface a value is typed on, like the text field beside it");
	/* **AND IT IS STILL WHITE UNDER THE POINTER AND WHILE A SESSION IS RUNNING.** This is the claim the grey box in the
	 * demonstration came from: the face used to answer the prelight grey when the pointer was inside — which, when a
	 * person CLICKS INTO THE FIELD, is always — and the edit session painted that same answer as its own background. A
	 * field does not change colour because somebody is near it or typing in it. */
	[combo cg_setMouseInside:YES];
	[rep release];
	rep = draw_cell(combo, W, H, view);
	check(fabs([[rep colorAtX:W / 2 y:H - 1 - (H - 2)] redComponent] - [[NSColor controlBackgroundColor] redComponent]) < 0.01,
	      "and STILL white with the pointer inside it — a field does not change colour under a person");
	[combo setHighlighted:YES];
	[rep release];
	rep = draw_cell(combo, W, H, view);
	check(fabs([[rep colorAtX:W / 2 y:H - 1 - (H - 2)] redComponent] - [[NSColor controlBackgroundColor] redComponent]) < 0.01,
	      "and still white while it is being used — the accent belongs to the list, not to the field");
	[combo setHighlighted:NO];
	[combo cg_setMouseInside:NO];
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
		/* **AND THE COUNT IS TAKEN INSIDE THE CHIP, WHICH IS NOT A REFINEMENT BUT A REQUIREMENT.** A combo box's field
		 * is WHITE — it is the surface a value is typed on — so "white" no longer means "the mark knocked out of the
		 * accent": the field around the chip is white too, and a counter that walked the whole zone found the field
		 * instead of the arrow and reported a 21-point run. The mark is knocked out OF THE CHIP, so the chip's own box
		 * is the only place the question has an answer. */
		{
			CGFloat side = (CGFloat)H * NS_CELL_CHIP_FRACTION;
			int chipL = W - (int)ceil((CGFloat)H * NS_CELL_CHIP_INSET_FRACTION) - (int)ceil(side);
			int chipR = chipL + (int)ceil(side) - 1;

			/* AND THE SAME BOUND APPLIES TO THE COLUMN: a centre line drawn down the whole field runs through the
			 * white ABOVE and BELOW the chip as well, which is two more runs that are the field rather than the mark.
			 * The chip's own box is the only place either question has an answer. */
			{
				int chipT = (int)ceil((H - (int)ceil(side)) / 2.0);
				int chipB = chipT + (int)ceil(side) - 1;

				for (y = chipT; y <= chipB; y++) {
					NSColor *c = [rep colorAtX:chipMidX y:y];
					int w = whiteish(c);

					if (w && first < 0) first = y;
					if (w) last = y;
					if (w && !whiteish([rep colorAtX:chipMidX y:y - 1])) runs++;
				}
			}
			/* **AND THE WIDEST ROW IS LOOKED FOR ONLY WHERE THE MARK IS.** A chip is a ROUNDED square, so its top and
			 * bottom rows show the FIELD's white in their corners — MEASURED, a scan over the chip's whole box reported
			 * the widest white row as 18 points at y=1, which is the corner and not the arrow, and the direction check
			 * below then passed for a reason that had nothing to do with the triangle. The mark's own rows are
			 * `first`..`last`, and among those a DOWN triangle is widest at its FIRST row and an up one at its last. */
			for (y = first; first >= 0 && y <= last; y++) {
				int n = 0;

				for (x = chipL; x <= chipR; x++) {
					if (whiteish([rep colorAtX:x y:y])) n++;
				}
				if (n > widest) { widest = n; widestY = y; }
			}
		}
		printf("  (note: chip x=%d..%d, centre column %d, white runs %d, widest %d px at y=%d, run y=%d..%d)\n",
		       comboLeft, comboRight, chipMidX, runs, widest, widestY, first, last);
		check(runs == 1, "ONE white run down the chip's centre column — the single arrow, where the pop-up has two");
		check(widest >= 8 && widest <= 12,
		      "and the triangle is a triangle: its base is 10 points across the 20-point chip, no more and no less");
		check(widestY == first,
		      "with that base at the FIRST row of the mark — a DOWN triangle, base up and apex down");
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
		/* THE PADDING IS `NS_TEXT_INSET` NOW — a FIELD's padding, named once in `NSText.h` — and not
		 * `NS_CELL_CONTENT_GAP`, which is the margin between a control's MARK and its words and happens to be four as
		 * well. The value is the same, so this check was passing while naming the wrong door; the name matters because
		 * the next change to one of them must not move the other. */
		check(leftmostInk >= (int)NS_TEXT_INSET && leftmostInk <= (int)NS_TEXT_INSET + 3,
		      "and the title begins at `NS_TEXT_INSET` — a FIELD's padding, the same air on all four sides");
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
		NSComboBoxCell *early = [[NSComboBoxCell alloc] initTextCell:@"NSComboBox"];
		NSSize before;
		NSSize after;
		NSSize direct;

		[late setBordered:YES];
		[late setBezeled:YES];
		[early setBordered:YES];
		[early setBezeled:YES];
		before = [late cellSizeForBounds:probe];
		[late setStringValue:@"NSComboBox"];
		after = [late cellSizeForBounds:probe];
		direct = [early cellSizeForBounds:probe];
		printf("  (note: a cell made empty measures %.2f, %.2f once the string arrives, and %.2f when made "
		       "with it)\n", (double)before.width, (double)after.width, (double)direct.width);
		check(after.width > before.width + 50.0,
		      "a string that arrives AFTER the cell is made is measured too — the control-built path");
		/* **THE COMPARISON IS AGAINST THE OTHER CELL, NOT A LITERAL.** The literal that used to be here (117.78)
		 * was the width in ONE face; the claim is that the two construction paths agree, so the second cell IS
		 * the expectation. MEASURED with Figtree: the late path answered 114.87 and the literal failed by three
		 * points while the two paths agreed exactly. */
		check(fabs(after.width - direct.width) < 0.01,
		      "and it measures the same as a cell that was made with that string, so the two paths agree");
		[early release];
		[late release];
	}

	/* 7. **AND A ROW CHOSEN FROM THE LIST COMES BACK AS THE SELECTION AND AS THE ACTION.** The list is built from the
	 * cell's own objects and every row is pointed at the cell with its index as the tag — so sending what a row sends
	 * is the whole of what a pick does, which is what makes it testable without a session or a display. */
	{
		Watcher *watcher = [[Watcher alloc] init];
		NSMenuItem *row = [[NSMenuItem alloc] initWithTitle:@"and its list" action:NULL keyEquivalent:@""];

		/* THE LIST HAS TO EXIST FOR A ROW TO BE PICKED FROM IT. The first draft of this check sent a tag of 1 to a cell
		 * whose list was EMPTY — the cell had only ever been given a string — so the pick correctly cleared the
		 * selection and the probe reported the code as broken. Two rows, as a combo box would have. */
		[combo addItemWithObjectValue:@"NSComboBox"];
		[combo addItemWithObjectValue:@"and its list"];
		[combo setTarget:watcher];
		[combo setAction:@selector(picked:)];
		[combo selectItemAtIndex:0];
		[combo cg_setMouseInside:NO];

		[row setTarget:combo];
		[row setAction:@selector(itemSelected:)];
		[row setTag:1];
		[combo itemSelected:row];
		printf("  (note: after picking row 1 the box holds \"%s\" at index %ld, and the action fired %d time(s))\n",
		       [[combo stringValue] UTF8String], (long)[combo indexOfSelectedItem], watcher->fired);
		check([[combo stringValue] isEqualToString:@"and its list"],
		      "a picked row becomes the box's string, which is what the field shows");
		check([combo indexOfSelectedItem] == 1, "and its index becomes the selection");
		check(watcher->fired == 1, "and the control's own action fires, ONCE, with the control as the sender");
		[row release];
		[watcher release];
	}

	/* 8. **AND THE CHIP IS A PLACE THE PRESS CAN BE TOLD FROM THE TEXT.** The press is split by this rect, so a chip
	 * that could not be located would be a press that could not be routed — which is what "clicking the arrow does
	 * nothing" was. */
	{
		NSRect chip = [combo cg_chipRectInFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		NSRect field = NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H);

		printf("  (note: the chip is x=%.1f..%.1f of a %d-point field)\n",
		       (double)NSMinX(chip), (double)NSMaxX(chip), W);
		check(NSMinX(chip) > 0.0 && NSMaxX(chip) <= NSMaxX(field),
		      "the chip is INSIDE the field and at its right end, where a press can find it");
		check(!NSPointInRect(NSMakePoint(NSMinX(field) + 5.0, NSMidY(field)), chip),
		      "and a press near the left edge is NOT in it, so it begins an edit instead");
		check(NSPointInRect(NSMakePoint(NSMidX(chip), NSMidY(chip)), chip),
		      "while a press on the chip is, so it opens the list");
	}

	/* 9. **AND BOTH CONTROLS ANCHOR THEIR RAISED WINDOW AT THE SAME PLACE: THE CONTROL'S OWN LEFT EDGE.** This is the
	 * claim "line the menu up with the control" makes, and it is ONE NUMBER, because `NSMenu` places its window at
	 * `location.x` — MEASURED in its own placement (`_trackingFrame = NSMakeRect(location.x, …)`). The two controls
	 * used to do this arithmetic separately and the combo box anchored at its CHIP, so its list hung under the arrow
	 * while the pop-up's hung under the button; a probe that checked either control ALONE would have passed on both. */
	{
		NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 200.0)
							  styleMask:NSBorderlessWindowMask
							    backing:NSBackingStoreBuffered defer:NO];
		NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 200.0)];
		NSView *holder = [[NSView alloc] initWithFrame:NSMakeRect(60.0, 80.0, (CGFloat)W, (CGFloat)H)];
		NSRect inner = NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H);
		NSPoint comboAnchor;
		NSPoint popupAnchor;
		CGFloat want;

		[w setContentView:content];
		[content addSubview:holder];
		comboAnchor = [combo cg_popUpAnchorForFrame:inner inView:holder];
		popupAnchor = [popup cg_popUpAnchorForFrame:inner inView:holder];
		want = [w frame].origin.x + 60.0;
		printf("  (note: the combo box anchors at x=%.1f and the pop-up at x=%.1f; the control's left edge is %.1f)\n",
		       (double)comboAnchor.x, (double)popupAnchor.x, (double)want);
		check(fabs(comboAnchor.x - popupAnchor.x) < 0.01,
		      "both controls anchor at the SAME x — one rule, so the pair cannot disagree");
		check(fabs(comboAnchor.x - want) < 0.01,
		      "and that x IS the control's own left edge, carried into the space a window frame lives in");
		check(fabs(comboAnchor.y - popupAnchor.y) < 0.01,
		      "and at the same y, which is the control's bottom edge");
		/* AND THE CHIP IS NOT IT, which is the specific defect this was: a control 140 points wide whose chip starts
		 * at 118 cannot have its list anchored at 118 and be lined up with anything. */
		check(fabs(comboAnchor.x - 118.0) > 50.0,
		      "which is NOT the chip's left edge — that is what the combo box's list used to hang under");
		[content release];
		[w release];
	}

	/* 10. **AND A COMMITTED EDIT SENDS THE CONTROL'S ACTION, WHILE A CANCELLED ONE DOES NOT.** The cell tells whoever
	 * lent the editor WHY a session ended; the CONTROL is what a caller set a target on, and `NSControl
	 * -textDidEndEditing:` is where Return and Tab become the action. The prohibited half is the point: an action sent
	 * on Escape would tell a caller that a value the model never accepted had been entered. */
	{
		/* **AND IT IS A CONTROL THAT HEARS THIS, NOT A CELL — which the first draft of this check got wrong.** The
		 * rest of this probe works with CELLS, so it called the control's door on a cell; the cell's own
		 * `-textDidEndEditing:` ran instead and treated the cell as the EDITOR, asking it for `-string`. A control is
		 * what a caller sets a target on, so a control is what this needs. */
		NSComboBox *box = [[NSComboBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		Watcher *watcher = [[Watcher alloc] init];
		NSDictionary *ret = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:NSTextMovementReturn]
							       forKey:NSTextMovementUserInfoKey];
		NSDictionary *esc = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:NSTextMovementCancel]
							       forKey:NSTextMovementUserInfoKey];
		NSDictionary *tab = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:NSTextMovementTab]
							       forKey:NSTextMovementUserInfoKey];

		[box setTarget:watcher];
		[box setAction:@selector(picked:)];
		/* **AND THE BOX IS EDITABLE, WHICH IS THE FLAG ITS BASE NOW READS.** A combo box's press opens a session
		 * through `NSTextField -mouseDown:`, and that door is gated on `-isEditable`. Before the cell said YES the
		 * flag answered NO while the control opened a session anyway — the flag and the behaviour disagreed, and the
		 * rebase onto `NSTextField` is what forced them to agree. */
		check([box isEditable], "a combo box is editable by default, which is the flag its field base's press reads");
		[box textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification
								     object:box userInfo:ret]];
		check(watcher->fired == 1, "a session ended by RETURN sends the control's action");
		[box textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification
								     object:box userInfo:esc]];
		check(watcher->fired == 1, "and one ended by ESCAPE does NOT — the value was never accepted");
		[box textDidEndEditing:[NSNotification notificationWithName:NSTextDidEndEditingNotification
								     object:box userInfo:tab]];
		check(watcher->fired == 2, "and TAB does too, because tabbing out of a field accepts what is in it");
		[watcher release];
		[box release];
	}

	/* 11. **AND THE LIST'S ROWS MARK THE ONE THIS BOX HOLDS.** The session needs a display — a borderless window, a
	 * traversal loop, a dismissal — and the LIST does not: how many rows it has, what they say, which one is marked and
	 * what each one is wired to are facts about a menu that has been built and never shown. So they are checked here,
	 * where a failure says WHICH fact is wrong rather than "the list looked odd on screen".
	 *
	 * MEASURED before this: every row looked alike, so the one question a combo box's list exists to answer — which row
	 * am I on — had to be answered by reading the whole list and comparing it with the field. */
	{
		NSMenu *list = [combo cg_buildListMenu];
		NSMenuItem *held;
		NSMenuItem *other;
		AGComboListView *listView;
		NSMenuView *plainView;

		check(list != nil && [list numberOfItems] == 2, "the list has a row per object, built without a display");
		held = [list itemAtIndex:[combo indexOfSelectedItem]];
		other = [list itemAtIndex:0];
		printf("  (note: the box holds index %ld; row 0 is \"%s\" and the held row is \"%s\")\n",
		       (long)[combo indexOfSelectedItem], [[other title] UTF8String], [[held title] UTF8String]);
		check([[held title] isEqualToString:@"and its list"], "the held row is the held OBJECT's own description");
		check([held state] == NSOnState && [other state] == NSOffState,
		      "and it is TURNED ON, which is a menu's way of saying \"this is the current choice\"");
		check([held target] == (id)combo && sel_isEqual([held action], @selector(itemSelected:)),
		      "every row is still wired to the cell, so the mark costs the pick nothing");

		listView = [[AGComboListView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 44.0)];
		plainView = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 44.0)];
		[listView setMenu:list];
		[plainView setMenu:list];
		check([listView cg_isItemMarked:held] && ![listView cg_isItemMarked:other],
		      "the combo box's view marks the ON row and only it");
		check(![plainView cg_isItemMarked:held] && ![plainView cg_isItemMarked:other],
		      "while a plain menu view marks NOTHING — the door's default, so no menu in the tier changed");
		check([list cg_menuViewClass] == [NSMenuView class] &&
		      [[NSMenu alloc] init] != nil,
		      "and a menu that was never told uses the default view, which is what every menu is");
		[listView release];
		[plainView release];
	}

	/* 12. **AND A LIST'S ROW HAS NO GUTTER, NO SHORTCUT COLUMN, AND A MARK THAT FILLS IT.** A menu's row is laid out in
	 * four strips and a list's in one, and both facts are ARITHMETIC — which column the title gets and how far the mark
	 * reaches — so neither needs a display to check. MEASURED before this: a list's rows were laid out as though the two
	 * columns it does not draw were there, so a list of short words was as wide as a menu of shortcut-bearing items, and
	 * the row it held wore a chip inset inside it rather than being filled. */
	{
		NSMenu *list = [combo cg_buildListMenu];
		AGComboListView *listView = [[AGComboListView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 44.0)];
		NSMenuView *plainView = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 120.0, 44.0)];
		NSMenuItemCell *listCell;
		NSMenuItemCell *menuCell;
		NSRect row = NSMakeRect(0.0, 0.0, 120.0, 22.0);

		[listView setMenu:list];
		[plainView setMenu:list];
		listCell = [listView cellForItemAtIndex:0];
		menuCell = [plainView cellForItemAtIndex:0];
		/* **AND THE CONTRAST WITH A MENU CANNOT BE SHOWN HERE, WHICH IS WORTH WRITING DOWN RATHER THAN FAKING.** A menu's
		 * column widths come from measuring TEXT, and this build has no font registry offscreen — MEASURED twice: with a
		 * shortcut set on the row the menu cell still answered 120 of 120, because the width it would have subtracted was
		 * zero. So the check below is the LIST's claim, which is unconditional because the override returns the row rather
		 * than computing one — and the menu's half of the comparison waits for a display. */
		[[list itemAtIndex:0] setKeyEquivalent:@"k"];
		[listCell calcSize];
		printf("  (note: with a shortcut on row 0, a list row's title column is %.0f of a %.0f row; the menu's is %.0f, "
		       "which is zero-column arithmetic for want of a font offscreen)\n",
		       (double)NSWidth([listCell titleRectForBounds:row]), (double)NSWidth(row),
		       (double)NSWidth([menuCell titleRectForBounds:row]));
		check([listCell isKindOfClass:[AGComboListCell class]],
		      "the combo box's list makes a LIST's cell, asked for rather than named");
		check(![menuCell isKindOfClass:[AGComboListCell class]],
		      "and a plain menu view still makes the menu's, so no menu in the tier changed its rows");
		check(NSEqualRects([listCell titleRectForBounds:row], row),
		      "a list row's title column IS the whole row, shortcut or no shortcut — the columns it has not got are "
		      "not measured, because the door returns the row rather than computing one");
		check(NSEqualRects([listView cg_markRectForRow:row], row),
		      "and its mark is the whole row, which is what a full-width fill is");
		check(!NSEqualRects([plainView cg_markRectForRow:row], row),
		      "while a menu's mark stays the chip inset inside its row");
		/* AND THE CELL DOOR IS A +1 DOOR, so a probe that called it and dropped the result would leak one — the two
		 * class checks above already say which cell each view makes, and they go through `-cellForItemAtIndex:`,
		 * which is the door that owns the cell. */
		[listView release];
		[plainView release];
	}

	/* 10. **THE DATA SOURCE: THE ROWS ARE THE SOURCE'S, AND EVERY ROW DOOR KNOWS IT.** The view's protocol names the
	 * VIEW and the cell's names the CELL, so this section sets the VIEW's source and the box adapts — which is the
	 * claim: one source, every door. */
	{
		NSComboBox *box = [[NSComboBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		AGViewSource *source = [[AGViewSource alloc] init];

		[source->rows addObject:@"one"];
		[source->rows addObject:@"two"];
		[source->rows addObject:@"three"];
		[box setDataSource:source];
		[box setUsesDataSource:YES];
		check([box dataSource] == source, "the data source round-trips through the control");
		check([box numberOfItems] == 3, "and the box counts the SOURCE's rows, not its own empty array");
		check([[box itemObjectValueAtIndex:1] isEqual:@"two"], "a row comes from the source, at the index asked");
		check([[box objectValues] count] == 3,
		      "`-objectValues` GATHERS them, so a caller is not handed an empty array for a box with rows");
		check([box indexOfItemWithObjectValue:@"three"] == 2,
		      "and a typed string's index is the source's own door rather than a scan");
		[box selectItemAtIndex:2];
		check([[box stringValue] isEqual:@"three"], "a selection writes the source's row into the field");

		/* THE SOURCE CHANGES UNDER THE BOX, WHICH IS WHAT THE TWO ``RELOAD'' DOORS ARE FOR. */
		[source->rows removeAllObjects];
		[source->rows addObject:@"alpha"];
		[box reloadData];
		check([box numberOfItems] == 1, "`-reloadData` re-reads a source that changed its count");
		check([box indexOfSelectedItem] == 0, "and the selection is CLAMPED into the new count");
		check([[box stringValue] isEqual:@"alpha"], "with the shown value re-read from it");

		[source->rows addObject:@"beta"];
		[box noteNumberOfItemsChanged];
		check([box numberOfItems] == 2, "`-noteNumberOfItemsChanged` re-reads it too");

		/* AND THE ARRAY DOORS REFUSE, BECAUSE THEY WOULD WRITE STORAGE NOTHING READS. */
		[box addItemWithObjectValue:@"ignored"];
		check([box numberOfItems] == 2, "`-addItemWithObjectValue:` is refused while the source is in use");
		[box setUsesDataSource:NO];
		check([box numberOfItems] == 0,
		      "and with the flag off the box shows its OWN rows, which are still empty — the flag is the switch");
		[box release];
		[source release];
	}

	/* 11. **THE CELL'S OWN PROTOCOL, WHICH IS THE ONE WITH A COMPLETION.** */
	{
		NSComboBoxCell *cell = [[NSComboBoxCell alloc] initTextCell:@""];
		AGCellSource *source = [[AGCellSource alloc] init];

		[source->rows addObject:@"apples"];
		[source->rows addObject:@"bananas"];
		[cell setDataSource:source];
		[cell setUsesDataSource:YES];
		check([cell dataSource] == source, "the CELL protocol's source round-trips through the cell");
		check([cell numberOfItems] == 2, "and the cell counts its rows");
		check([[cell completedString:@"ap"] isEqual:@"apples"],
		      "`-completedString:` finds the row that begins with the prefix");
		check([[cell completedString:@"BAN"] isEqual:@"bananas"],
		      "the comparison is CASE-INSENSITIVE, so a person typing lowercase is completed too");
		check([cell completedString:@"x"] == nil, "a prefix no row begins with answers nil");
		check([cell completedString:@""] == nil, "and so does an empty prefix — completion is not a default choice");
		check([cell completedString:@"apples"] == nil,
		      "a prefix that IS a whole row completes nothing: the answer has to be LONGER to be a completion");
		check([cell indexOfItemWithObjectValue:@"bananas"] == 1, "the index door scans the source's rows by equality");
		[cell release];
		[source release];
	}

	/* 12. **AND THE TYPING PATH, WHICH IS WHERE `-completes` STOPS BEING A STORED BIT.** The editor's change
	 * notification reaches the cell because the cell is the editor's delegate, so sending that notification by hand is
	 * the same path a keystroke takes. The completed suffix must be SELECTED, so the next character replaces the offer. */
	{
		NSComboBoxCell *cell = [[NSComboBoxCell alloc] initTextCell:@""];
		NSText *editor = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];
		NSNotification *note;

		[cell addItemWithObjectValue:@"Apples"];
		[cell addItemWithObjectValue:@"Apricots"];
		[cell addItemWithObjectValue:@"Bananas"];
		check([cell completes], "a combo cell completes by default");
		[editor setString:@"Ap"];
		note = [NSNotification notificationWithName:NSTextDidChangeNotification object:editor];
		[cell textDidChange:note];
		printf("  (note: typing \"Ap\" left the editor at \"%s\", selection %lu..%lu)\n",
		       [[editor string] UTF8String], (unsigned long)[editor selectedRange].location,
		       (unsigned long)([editor selectedRange].location + [editor selectedRange].length));
		check([[editor string] isEqual:@"Apples"], "typing a prefix COMPLETES it from the rows");
		check([editor selectedRange].location == 2 && [editor selectedRange].length == 4,
		      "and the completed suffix is SELECTED, so the next key replaces it");

		[cell setCompletes:NO];
		[editor setString:@"Ba"];
		[cell textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:editor]];
		check([[editor string] isEqual:@"Ba"], "with `-completes` off the editor is left exactly as typed");
		[editor release];
		[cell release];
	}

	/* 13. **THE LIST'S SHAPE, WHICH THE SESSION NOW OBEYS.** The rows of this tier's list are a menu's, so the cell
	 * hands its two numbers to the menu it builds and the menu's own arithmetic is what answers — which is the claim:
	 * not that the cell stores a height, but that the rows ARE that tall. */
	{
		NSComboBoxCell *cell = [[NSComboBoxCell alloc] initTextCell:@""];
		NSMenu *list;
		NSMenu *plain = [[NSMenu alloc] initWithTitle:@"plain"];
		NSRect frame = NSMakeRect(0.0, 0.0, 100.0, 200.0);
		NSRect row0, row1;

		[cell addItemWithObjectValue:@"a"];
		[cell addItemWithObjectValue:@"b"];
		[cell addItemWithObjectValue:@"c"];
		check([cell itemHeight] == 0.0 && [cell intercellSpacing].height == 0.0,
		      "an unshaped box asks for the session's OWN row shape, which is zero on both axes");
		[cell setItemHeight:30.0];
		[cell setIntercellSpacing:NSMakeSize(4.0, 6.0)];
		check([cell itemHeight] == 30.0 && [cell intercellSpacing].width == 4.0 &&
		      [cell intercellSpacing].height == 6.0, "the two shape doors round-trip through the cell");

		list = [cell cg_buildListMenu];
		check([list cg_rowHeight] == 30.0, "the list the cell builds is 30 points a row");
		check([list cg_rowPitch] == 36.0, "and its rows are PITCHED by the height plus the air between them");
		row0 = [list cg_rowRectAtIndex:0 inFrame:frame];
		row1 = [list cg_rowRectAtIndex:1 inFrame:frame];
		printf("  (note: row 0 is (%.1f, %.1f) %.0fx%.0f and row 1 is (%.1f, %.1f))\n",
		       (double)row0.origin.x, (double)row0.origin.y, (double)row0.size.width, (double)row0.size.height,
		       (double)row1.origin.x, (double)row1.origin.y);
		check(row0.size.height == 30.0 && row1.size.height == 30.0, "each row IS the height asked for");
		check(fabs((row0.origin.y - row1.origin.y) - 36.0) < 0.01, "and the gap between two rows is the pitch");
		check(row0.origin.x == NSMenuPanelPadding + 4.0,
		      "the spacing's WIDTH insets the rows from the panel, which is what a list's rows do");

		/* AND A MENU THAT NOBODY SHAPED IS UNCHANGED — the defaults are the session's own, not zero-sized rows. */
		check([plain cg_rowHeight] == NSMenuRowHeight && [plain cg_rowPitch] == NSMenuRowHeight,
		      "a menu nobody shaped keeps the shared row height and no gap");
		[plain release];
		[cell release];
	}

	/* 14. **`-setButtonBordered:NO` IS THE TRIANGLE WITHOUT ITS PLATE.** Measured in the chip's own rect: the bordered
	 * chip is accent there, and the unbordered one has no accent at all but still carries a mark — in the field's ink,
	 * because a white triangle on a white field would be the borderless button that is merely invisible. */
	{
		NSComboBoxCell *bordered = [[NSComboBoxCell alloc] initTextCell:@""];
		NSComboBoxCell *bare = [[NSComboBoxCell alloc] initTextCell:@""];
		NSBitmapImageRep *a;
		NSBitmapImageRep *b;
		NSRect chip;
		int accentA = 0, accentB = 0, inkB = 0;
		int x, y, i;

		check([bordered isButtonBordered], "a chip is bordered by default");
		[bare setButtonBordered:NO];
		check(![bare isButtonBordered], "and `-setButtonBordered:NO` round-trips");
		chip = [bordered cg_chipRectInFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		a = draw_cell(bordered, W, H, nil);
		b = draw_cell(bare, W, H, nil);
		for (y = 0; y < H; y++) {
			int drawing_y = H - 1 - y;

			if (drawing_y < (int)NSMinY(chip) || drawing_y >= (int)NSMaxY(chip)) {
				continue;
			}
			for (x = (int)NSMinX(chip); x < (int)NSMaxX(chip); x++) {
				NSColor *ca = [a colorAtX:x y:y];
				NSColor *cb = [b colorAtX:x y:y];

				accentA += is_accent(ca) ? 1 : 0;
				accentB += is_accent(cb) ? 1 : 0;
				inkB += (cb != nil && [cb redComponent] < 0.6) ? 1 : 0;
			}
		}
		printf("  (note: accent in the chip — %d bordered, %d unbordered; and %d dark points where the mark is)\n",
		       accentA, accentB, inkB);
		check(accentA > 50, "a bordered chip is the accent plate it always was");
		check(accentB == 0, "and an unbordered one has NO plate at all");
		check(inkB > 5, "while its triangle is still drawn, in the field's ink");
		[a release];
		[b release];
		[bordered release];
		[bare release];
	}

	/* 15. **`-deselectItemAtIndex:` UN-CHOOSES, AND ONLY THE ROW IT NAMES.** */
	{
		NSComboBox *box = [[NSComboBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

		[box addItemWithObjectValue:@"zero"];
		[box addItemWithObjectValue:@"one"];
		[box selectItemAtIndex:1];
		[box deselectItemAtIndex:0];
		check([box indexOfSelectedItem] == 1, "deselecting a row that is NOT the held one changes nothing");
		[box deselectItemAtIndex:1];
		check([box indexOfSelectedItem] == -1 && [[box stringValue] isEqual:@""],
		      "and deselecting the HELD row clears the selection and the field with it");
		[box release];
	}

	/* 16. **AND THE THREE LIST DOORS THIS SESSION HAS NO MECHANISM FOR REFUSE BY NAME.** A scroller in a list window
	 * would need a scroll offset the menu session has not got, so the flag answers NO however it is set and the two
	 * scroll doors say what they would need. */
	{
		NSComboBox *box = [[NSComboBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

		check(![box hasVerticalScroller], "a box has no vertical scroller");
		[box setHasVerticalScroller:YES];
		check(![box hasVerticalScroller], "and setting the flag does not invent one");
		[box scrollItemAtIndexToTop:0];
		[box scrollItemAtIndexToVisible:0];
		check(1, "the two scroll doors are refusals rather than crashes");
		[box release];
	}

	/* 17. **THE DELEGATE'S THREE TIDINGS, TWO OF THEM THROUGH THE PATH A PERSON TAKES.** `-cg_didSelectItemAtIndex:`
	 * is what the CELL sends when a row is picked; the two list messages are sent around the session a press on the
	 * chip begins. */
	{
		NSComboBox *box = [[NSComboBox alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		ComboWatcher *watcher = [[ComboWatcher alloc] init];
		NSMenuItem *row = [[NSMenuItem alloc] initWithTitle:@"one" action:NULL keyEquivalent:@""];

		[box addItemWithObjectValue:@"zero"];
		[box addItemWithObjectValue:@"one"];
		[box setDelegate:(id <NSComboBoxDelegate>)watcher];
		check([box delegate] == (id)watcher, "the combo box answers its delegate through its own typed door");

		[row setTarget:box];
		[row setAction:@selector(itemSelected:)];
		[row setTag:1];
		[(NSComboBoxCell *)[box cell] itemSelected:row];
		printf("  (note: a pick sent %d selection-changed message(s))\n", watcher->didChanges);
		check(watcher->didChanges == 1,
		      "a picked row tells the delegate the selection changed — the CELL asks the CONTROL to send it");
		/* **AND THE FOURTH MESSAGE IS SENT NOW, THROUGH THE SEAM THAT WAS MISSING.** The list is a menu, the CELL is its
		 * delegate, and the menu's session reports every highlight change — so `-menu:willHighlightItem:` on the cell
		 * becomes `-comboBoxSelectionIsChanging:` on the control's delegate. The probe sends what the session sends. */
		{
			NSMenu *list = [(NSComboBoxCell *)[box cell] cg_buildListMenu];
			NSMenuItem *second = (NSMenuItem *)[list itemAtIndex:1];

			check([list delegate] == (id)[box cell],
			      "the list's menu DELEGATE is the cell, which is what carries the highlight back");
			[(NSComboBoxCell *)[box cell] menu:list willHighlightItem:second];
			printf("  (note: moving the highlight over row 1 sent %d selection-is-changing message(s))\n",
			       watcher->isChangings);
			check(watcher->isChangings == 1,
			      "and a highlight change on a row reaches the delegate as `-comboBoxSelectionIsChanging:`");
			[(NSComboBoxCell *)[box cell] menu:list willHighlightItem:nil];
			check(watcher->isChangings == 2,
			      "including the move OFF the menu, which the cell reports as no row");
		}

		/* AND THE TWO LIST TIDINGS COME FROM THE CHIP'S PRESS, WHICH IS THE ONLY THING THAT OPENS A LIST. The session
		 * needs a display to be seen but not to be ENTERED: it is begun and dismissed around the press, so a probe with
		 * no compositor still hears the two messages — which is the claim, and the reason they are sent by the VIEW
		 * rather than built inside the session. */
		{
			/* THE CHIP'S RECT COMES FROM THE CELL: it is a cell-only door, and a view has none — the control's own
			 * press asks its cell the same question. */
			NSRect chip = [(NSComboBoxCell *)[box cell] cg_chipRectInFrame:[box bounds]];
			NSEvent *press = [NSEvent mouseEventWithType:NSLeftMouseDown
							    location:NSMakePoint(NSMidX(chip), NSMidY(chip))
						       modifierFlags:0
							   timestamp:0.0
							windowNumber:0
							     context:nil
							 eventNumber:1
							  clickCount:1
							    pressure:1.0];

			check(press != nil, "the probe can build a press on the chip");
			[box mouseDown:press];
			printf("  (note: a chip press sent %d pop-up and %d dismiss message(s))\n",
			       watcher->popUps, watcher->dismisses);
			check(watcher->popUps == 1 && watcher->dismisses == 1,
			      "and a press on the CHIP tells the delegate the list is opening, then that it is gone");
		}
		[box release];
		[watcher release];
		[row release];
	}

	[combo release];
	[popup release];
	[view release];
	[pool release];
	printf("combo_box: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
