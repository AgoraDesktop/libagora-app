/*
 * segmented_control — a row of segments: geometry, selection, tracking, forwarding and ink.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CONTROL IS A FORWARDER, SO THE PROBE ASKS BOTH HALVES.** The public NSSegmentedControl doors are checked for
 * their answers and their storage, and the cell's private geometry door is used to pin the segment arithmetic: fixed
 * widths first, then an auto-sized segment taking the surplus, then proportional scaling when the frame is narrower
 * than the row. The three tracking modes are driven through the cell's own hooks — the same hooks NSControl's loop
 * calls — because the selection is committed in `-stopTracking:...`, and the action that follows must see it.
 *
 * The ink is read from a bitmap: the selected plate is cg_accentColor, the ordinary face is controlColor, the
 * separators and border are controlDarkShadowColor, and the labels are present on both kinds of plate.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSSegmentedControl.h>
#import <AppKit/NSSegmentedCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

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
	return fabs(a - b) < 0.05;
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static int same_colour(NSColor *a, NSColor *b, double tol)
{
	return a != nil && b != nil
		&& fabs([a redComponent] - [b redComponent]) < tol
		&& fabs([a greenComponent] - [b greenComponent]) < tol
		&& fabs([a blueComponent] - [b blueComponent]) < tol;
}

@interface AGSegmentTarget : NSObject
{
@public
	int actions;
}
- (void)perform:(id)sender;
@end

@implementation AGSegmentTarget
- (void)perform:(id)sender
{
	(void)sender;
	actions++;
}
@end

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSSegmentedControl *control;
	NSSegmentedCell *cell;
	AGSegmentTarget *target;
	NSMenu *menu;
	NSImage *image;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];

	control = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 150.0, 24.0)];
	cell = (NSSegmentedCell *)[control cell];

	/* 1. THE EMPTY CONTROL, AND THE SEGMENTS A CALLER ADDS. */
	check([control segmentCount] == 0 && [control selectedSegment] == -1,
	      "a new segmented control has no segments and no selection");
	check(near([control frame].size.height, 24.0), "and the default face is twenty-four points tall");
	[control setSegmentCount:3];
	[control setLabel:@"One" forSegment:0];
	[control setLabel:@"Two" forSegment:1];
	[control setLabel:@"Three" forSegment:2];
	check([control segmentCount] == 3 && [[control labelForSegment:1] isEqual:@"Two"],
	      "three labelled segments, and each label is stored");
	[cell setTag:11 forSegment:0];
	[cell setTag:22 forSegment:1];
	[cell setTag:33 forSegment:2];
	check([cell tagForSegment:2] == 33, "and each tag is stored");

	/* 2. FIXED WIDTHS, AN AUTO-SIZED SEGMENT, AND A NARROWER FRAME. */
	[control setWidth:40.0 forSegment:0];
	[control setWidth:50.0 forSegment:1];
	[control setWidth:0.0 forSegment:2];
	{
		NSRect a = [cell cg_rectForSegment:0 inFrame:[control bounds]];
		NSRect b = [cell cg_rectForSegment:1 inFrame:[control bounds]];
		NSRect c = [cell cg_rectForSegment:2 inFrame:[control bounds]];

		check(near(NSMinX(a), 0.0) && near(NSWidth(a), 40.0),
		      "segment 0 takes its fixed forty points");
		check(near(NSMinX(b), 40.0) && near(NSWidth(b), 50.0),
		      "segment 1 begins after it and takes its fifty");
		check(near(NSMinX(c), 90.0) && near(NSMaxX(c), 150.0),
		      "the auto-sized segment takes the surplus and ends at the frame");
	}
	[control setWidth:60.0 forSegment:2];
	check(near(NSWidth([cell cg_rectForSegment:0 inFrame:NSMakeRect(0.0, 0.0, 150.0, 24.0)]), 40.0)
	      && near(NSWidth([cell cg_rectForSegment:2 inFrame:NSMakeRect(0.0, 0.0, 150.0, 24.0)]), 60.0),
	      "an exact set of fixed widths is left alone");
	check(near(NSMaxX([cell cg_rectForSegment:2 inFrame:NSMakeRect(0.0, 0.0, 75.0, 24.0)]), 75.0),
	      "and a narrower frame scales the row to fit it");

	/* 3. SELECT ONE, PER-SEGMENT STATE, AND THE TAG DOOR. */
	[control setWidth:50.0 forSegment:0];
	[control setWidth:50.0 forSegment:1];
	[control setWidth:50.0 forSegment:2];
	[control setSelectedSegment:1];
	check([control selectedSegment] == 1 && ![control isSelectedForSegment:0]
	      && [control isSelectedForSegment:1] && ![control isSelectedForSegment:2],
	      "setSelectedSegment: selects exactly one segment");
	check([control selectSegmentWithTag:33] && [control selectedSegment] == 2,
	      "selectSegmentWithTag: finds the segment by its tag");
	[control setSelected:NO forSegment:2];
	check([control selectedSegment] == -1, "and clearing the selected segment leaves none selected");

	/* 4. SELECT ANY TOGGLES SEGMENTS INDEPENDENTLY. */
	[cell setTrackingMode:NSSegmentSwitchTrackingSelectAny];
	[control setSelected:YES forSegment:0];
	[control setSelected:YES forSegment:2];
	check([control isSelectedForSegment:0] && [control isSelectedForSegment:2]
	      && ![control isSelectedForSegment:1],
	      "SelectAny keeps two segments selected at once");
	[control setSelected:NO forSegment:0];
	check(![control isSelectedForSegment:0] && [control isSelectedForSegment:2],
	      "and toggling one leaves the other alone");

	/* 5. A DISABLED SEGMENT DOES NOT TAKE A PRESS. */
	[cell setTrackingMode:NSSegmentSwitchTrackingSelectOne];
	[control setSelectedSegment:0];
	[control setEnabled:NO forSegment:2];
	[cell startTrackingAt:NSMakePoint(125.0, 12.0) inView:control];
	[cell stopTracking:NSMakePoint(125.0, 12.0) at:NSMakePoint(125.0, 12.0) inView:control mouseIsUp:YES];
	check([control selectedSegment] == 0, "a press on a disabled segment selects nothing");

	/* 6. TRACKING COMMITS ON THE RELEASE, AND THE ACTION SEES THE NEW STATE. */
	[control setEnabled:YES forSegment:2];
	[cell setTrackingMode:NSSegmentSwitchTrackingSelectOne];
	[control setSelectedSegment:0];
	[cell startTrackingAt:NSMakePoint(75.0, 12.0) inView:control];
	[cell continueTracking:NSMakePoint(75.0, 12.0) at:NSMakePoint(75.0, 12.0) inView:control];
	[cell stopTracking:NSMakePoint(75.0, 12.0) at:NSMakePoint(75.0, 12.0) inView:control mouseIsUp:YES];
	check([control selectedSegment] == 1, "a press and release commits the segment under the pointer");
	target = [[AGSegmentTarget alloc] init];
	[control setTarget:target];
	[control setAction:@selector(perform:)];
	[cell startTrackingAt:NSMakePoint(125.0, 12.0) inView:control];
	[cell stopTracking:NSMakePoint(125.0, 12.0) at:NSMakePoint(125.0, 12.0) inView:control mouseIsUp:YES];
	[control sendAction:[control action] to:[control target]];
	check(control != nil && [control selectedSegment] == 2 && target->actions == 1,
	      "the action is sent with the newly selected segment in place");

	/* 7. MOMENTARY SELECTS ONLY WHILE PRESSED. */
	[cell setTrackingMode:NSSegmentSwitchTrackingMomentary];
	[cell startTrackingAt:NSMakePoint(75.0, 12.0) inView:control];
	check([control isSelectedForSegment:1], "Momentary shows the pressed segment as selected");
	[cell stopTracking:NSMakePoint(75.0, 12.0) at:NSMakePoint(75.0, 12.0) inView:control mouseIsUp:YES];
	check(![control isSelectedForSegment:1] && [control selectedSegment] == 1,
	      "and releases the visual selection while the action still sees the segment");

	/* 8. THE PICTURE, MENU, TOOL TIP AND STYLE DOORS. */
	image = [[NSImage alloc] initWithSize:NSMakeSize(12.0, 12.0)];
	menu = [[NSMenu alloc] initWithTitle:@"Segment"];
	[control setImage:image forSegment:0];
	[control setImageScaling:NSImageScaleNone forSegment:0];
	[control setMenu:menu forSegment:1];
	[cell setToolTip:@"tip" forSegment:2];
	check([control imageForSegment:0] == image && [control imageScalingForSegment:0] == NSImageScaleNone,
	      "a segment keeps its picture and its scaling rule");
	check([control menuForSegment:1] == menu && [[cell toolTipForSegment:2] isEqual:@"tip"],
	      "and its menu and tool tip");
	[control setSegmentStyle:NSSegmentStyleCapsule];
	check([control segmentStyle] == NSSegmentStyleCapsule, "the segment style is stored");

	/* 9. THE INK. */
	[control setSegmentCount:3];
	[control setLabel:@"A" forSegment:0];
	[control setLabel:@"B" forSegment:1];
	[control setLabel:@"C" forSegment:2];
	[control setSegmentStyle:NSSegmentStyleRounded];
	[control setFrameSize:NSMakeSize(150.0, 24.0)];
	[cell setTrackingMode:NSSegmentSwitchTrackingSelectOne];
	[control setSelectedSegment:1];
	{
		int w = (int)[control frame].size.width;
		int h = (int)[control frame].size.height;
		NSBitmapImageRep *rep = new_rep(w, h);
		int x, y;
		int lightInk = 0;
		int darkInk = 0;
		int platePixels = 0;
		int eraBluePixels = 0;

		[control cacheDisplayInRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h) toBitmapImageRep:rep];
		check(same_colour([rep colorAtX:25 y:12], [NSColor controlColor], 0.04),
		      "an unselected segment is the control face");
		/* **AND THE PLATE IS MEASURED OVER THE SEGMENT RATHER THAN SAMPLED AT ITS CENTRE, WHICH IS WHERE THE LABEL
		 * IS.** This assertion used to read the single pixel at (75, 12) — the middle of the selected segment — and
		 * that pixel lies INSIDE the `B` glyph, on its crossbar, so the test was asking the LABEL whether the PLATE
		 * was the accent and could only pass for as long as the label happened to miss it. It stopped missing it: the
		 * reading was dark ink on a correct plate, and the failure named the accent while the accent was never in
		 * question. MEASURED: the crossbar sits on y = 12 and covers x = 73..77, and of the 768 pixels in the
		 * segment's interior 693 are the accent and 32 are ink. Counting asks what the prose asks. */
		check(same_colour([rep colorAtX:50 y:12], [NSColor controlDarkShadowColor], 0.08)
		      || same_colour([rep colorAtX:49 y:12], [NSColor controlDarkShadowColor], 0.08),
		      "the separator between segments is the border grey");
		for (y = 4; y < 20; y++) {
			for (x = 1; x < 49; x++) {
				if ([rep colorAtX:x y:y] != nil && [[rep colorAtX:x y:y] redComponent] < 0.35) {
					darkInk++;
				}
			}
			for (x = 51; x < 99; x++) {
				NSColor *pixel = [rep colorAtX:x y:y];

				if (pixel != nil && [pixel redComponent] > 0.90 && [pixel greenComponent] > 0.90
				    && [pixel blueComponent] > 0.90) {
					lightInk++;
				}
				if (same_colour(pixel, [NSColor cg_accentColor], 0.04)) {
					platePixels++;
				}
				/* **AND THE ERA'S BLUE IS COUNTED SO ITS ABSENCE IS A MEASUREMENT RATHER THAN AN IMPLICATION.**
				 * The claim in the assertion's name is "not the era's other blue", and a count of ZERO says that
				 * directly instead of leaving it to be inferred from the accent being present. */
				if (same_colour(pixel, [NSColor selectedControlColor], 0.04)) {
					eraBluePixels++;
				}
			}
		}
		check(darkInk > 0, "the ordinary segment draws its label in dark ink");
		check(platePixels > (48 * 16) / 2,
		      "the selected segment's plate is the platform's ACCENT, not the era's other blue");
		check(eraBluePixels == 0, "and none of the plate is the era's +selectedControlColor");
		/* **AND SO DOES THE SELECTED ONE, WHICH IS THE CHANGE THE ACCENT BROUGHT.** The plate used to be the era's
		 * blue with white ink on it; the platform's accent is a LIGHT periwinkle, and white on that is a wash. A
		 * selected segment is a chip that stays selected rather than a button caught mid-press, so it takes the
		 * menu's chip answer — dark ink — and the PLATE is what says "this one". MEASURED, the light group went to
		 * zero when the ink did. */
		check(lightInk == 0, "and the selected one does NOT invert to white — the accent is too light for it");
		[rep release];
	}

	/* 10. THE SIZE-TO-FIT DOOR AND THE SEGMENT COUNT SHRINKING. */
	[control setWidth:0.0 forSegment:0];
	[control setWidth:0.0 forSegment:1];
	[control setWidth:0.0 forSegment:2];
	[control sizeToFit];
	check([control frame].size.width > 0.0 && near([control frame].size.height, 24.0),
	      "sizeToFit asks the cell for the natural row and the face's height");
	[control setSegmentCount:1];
	check([control segmentCount] == 1 && [control selectedSegment] <= 0,
	      "shrinking the row drops the extra segments and clamps the selection");

	[control release];
	[target release];
	[image release];
	[menu release];
	printf("segmented_control: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
