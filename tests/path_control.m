/*
 * path_control — a path as components: URL decomposition, geometry, styles, tracking and ink.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PATH IS THE MODEL AND THE COMPONENT CELLS ARE THE ROWS.** Setting a file URL decomposes it into one
 * NSPathComponentCell per path component, each with its own prefix URL; the geometry places them with separators,
 * hides the middle when the frame is too narrow and keeps the first and last; the three styles change the surface and
 * the separators. A single click commits the component under the release through NSPathCell's tracking hooks, and a
 * double-click goes through NSPathControl's own gesture.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSPathControl.h>
#import <AppKit/NSPathCell.h>
#import <AppKit/NSPathComponentCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSEvent.h>
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

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber, NSInteger clickCount)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:clickCount pressure:1.0f];
}

@interface AGPathTarget : NSObject
{
@public
	int actions;
}
- (void)perform:(id)sender;
@end

@implementation AGPathTarget
- (void)perform:(id)sender
{
	(void)sender;
	actions++;
}
@end

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	NSPathControl *control;
	NSPathCell *cell;
	AGPathTarget *target;
	NSURL *url;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 24.0)
					     styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	control = [[NSPathControl alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 24.0)];
	[window setContentView:control];
	cell = (NSPathCell *)[control cell];
	target = [[AGPathTarget alloc] init];

	/* 1. A FILE URL BECOMES ONE COMPONENT PER PATH ELEMENT, EACH WITH ITS PREFIX URL. */
	url = [NSURL fileURLWithPath:@"/Users/kyle/Documents"];
	[control setURL:url];
	check([[control URL] isEqual:url], "the control answers the URL it was given");
	check([[control pathComponentCells] count] == 4,
	      "a four-element file path becomes four component cells (root, Users, kyle, Documents)");
	if ([[control pathComponentCells] count] == 4) {
		NSArray *cells = [control pathComponentCells];
		NSPathComponentCell *root = [cells objectAtIndex:0];
		NSPathComponentCell *users = [cells objectAtIndex:1];
		NSPathComponentCell *last = [cells objectAtIndex:3];

		check([[root stringValue] isEqual:@"/"], "the first component is the root");
		check([[users stringValue] isEqual:@"Users"] && [[last stringValue] isEqual:@"Documents"],
		      "and the rest name their path elements");
		check([[root URL] isEqual:[NSURL fileURLWithPath:@"/"]]
		      && [[last URL] isEqual:url],
		      "each component carries its own prefix URL");
	}

	/* 2. THE OBJECT VALUE DOORS. */
	check([[cell objectValue] isEqual:url], "the cell's objectValue is the URL");
	[cell setObjectValue:@"/System/Library"];
	check([[control URL].path isEqual:@"/System/Library"],
	      "setting a path string updates the URL and the components");
	[control setURL:url];

	/* 3. THE GEOMETRY: NATURAL ROW, HIT TEST, AND MIDDLE TRUNCATION. */
	check([[control pathComponentCells] count] == 4, "the URL is restored for the geometry checks");
	{
		NSArray *cells = [control pathComponentCells];
		NSRect first = [cell rectOfPathComponentCell:[cells objectAtIndex:0]
						  withFrame:[control bounds] inView:control];
		NSRect second = [cell rectOfPathComponentCell:[cells objectAtIndex:1]
						   withFrame:[control bounds] inView:control];
		NSRect last = [cell rectOfPathComponentCell:[cells objectAtIndex:3]
						 withFrame:[control bounds] inView:control];
		NSPathComponentCell *hit = [cell pathComponentCellAtPoint:NSMakePoint(NSMidX(second), NSMidY(second))
								   withFrame:[control bounds] inView:control];

		check(NSWidth(first) > 0.0 && NSWidth(second) > 0.0 && NSWidth(last) > 0.0,
		      "each component has a rectangle in a 300-point bar");
		check(hit == [cells objectAtIndex:1], "the point in the second rectangle finds the second cell");
		check(NSMinX(first) < NSMinX(second) && NSMinX(second) < NSMinX(last),
		      "and the components run left to right");
	}
	{
		NSArray *cells = [control pathComponentCells];
		NSRect first;
		NSRect middle;
		NSRect last;

		[control setFrameSize:NSMakeSize(110.0, 24.0)];
		first = [cell rectOfPathComponentCell:[cells objectAtIndex:0]
					  withFrame:[control bounds] inView:control];
		middle = [cell rectOfPathComponentCell:[cells objectAtIndex:2]
					   withFrame:[control bounds] inView:control];
		last = [cell rectOfPathComponentCell:[cells objectAtIndex:3]
					 withFrame:[control bounds] inView:control];
		check(NSWidth(first) > 0.0 && NSWidth(last) > 0.0,
		      "a narrow bar keeps the first and last components");
		check(NSIsEmptyRect(middle), "and hides the middle one that does not fit");
		[control setFrameSize:NSMakeSize(300.0, 24.0)];
	}

	/* 4. THE THREE STYLES, THEIR SIZES AND THEIR FACES. */
	check([cell pathStyle] == NSPathStyleStandard, "the path style starts as Standard");
	check([cell backgroundColor] != nil && [cell isOpaque], "the Standard bar has an opaque background");
	[control setPathStyle:NSPathStyleNavigationBar];
	check([cell controlSize] == NSSmallControlSize, "the navigation bar forces the small control size");
	check(same_colour([cell backgroundColor], [NSColor controlColor], 0.03),
	      "and wears the control face");
	[control setPathStyle:NSPathStylePopUp];
	{
		NSArray *cells = [control pathComponentCells];
		NSRect first = [cell rectOfPathComponentCell:[cells objectAtIndex:0]
						  withFrame:[control bounds] inView:control];
		NSRect last = [cell rectOfPathComponentCell:[cells objectAtIndex:3]
						 withFrame:[control bounds] inView:control];

		check(NSIsEmptyRect(first) && NSWidth(last) > 0.0,
		      "the PopUp style shows only the last component");
	}
	[control setPathStyle:NSPathStyleStandard];

	/* 5. A CLICK COMMITS THE COMPONENT UNDER THE RELEASE, AND THE ACTION SEES IT. */
	[control setTarget:target];
	[control setAction:@selector(perform:)];
	{
		NSArray *cells = [control pathComponentCells];
		NSRect second = [cell rectOfPathComponentCell:[cells objectAtIndex:1]
						   withFrame:[control bounds] inView:control];
		NSPoint at = NSMakePoint(NSMidX(second), NSMidY(second));

		[cell startTrackingAt:at inView:control];
		[cell stopTracking:at at:at inView:control mouseIsUp:YES];
		[control sendAction:[control action] to:[control target]];
		check([control clickedPathComponentCell] == [cells objectAtIndex:1],
		      "the clicked component is the one under the release");
		check(target->actions == 1, "and the control's action is sent");
	}

	/* 6. A DOUBLE-CLICK USES THE DOUBLE ACTION, NOT THE SINGLE ONE. */
	[control setDoubleAction:@selector(perform:)];
	{
		NSArray *cells = [control pathComponentCells];
		NSRect second = [cell rectOfPathComponentCell:[cells objectAtIndex:1]
						   withFrame:[control bounds] inView:control];
		NSPoint at = NSMakePoint(NSMidX(second), NSMidY(second));
		NSEvent *down = mouse(NSLeftMouseDown, at, [window windowNumber], 2);

		target->actions = 0;
		[control mouseDown:down];
		check(target->actions == 1 && [control clickedPathComponentCell] == [cells objectAtIndex:1],
		      "a double-click sends the double action for the clicked component");
	}

	/* 7. MANUAL COMPONENT CELLS AND THE PLACEHOLDER. */
	{
		NSPathComponentCell *one = [[[NSPathComponentCell alloc] init] autorelease];
		NSPathComponentCell *two = [[[NSPathComponentCell alloc] init] autorelease];

		[one setStringValue:@"one"];
		[one setURL:[NSURL fileURLWithPath:@"/one"]];
		[two setStringValue:@"two"];
		[two setURL:[NSURL fileURLWithPath:@"/two"]];
		[control setPathComponentCells:[NSArray arrayWithObjects:one, two, nil]];
		check([[control pathComponentCells] count] == 2
		      && [[control pathComponentCells] objectAtIndex:0] == one,
		      "a caller's component array is adopted");
		[cell setPlaceholderString:@"No path"];
		check([[cell placeholderString] isEqual:@"No path"], "and the placeholder is stored");
	}

	/* 8. THE INK: THE STANDARD BACKGROUND AND THE COMPONENT TEXT. */
	[control setURL:url];
	[control setPathStyle:NSPathStyleStandard];
	[control setFrameSize:NSMakeSize(300.0, 24.0)];
	{
		int w = (int)[control frame].size.width;
		int h = (int)[control frame].size.height;
		NSBitmapImageRep *rep = new_rep(w, h);
		int x, y, ink = 0;

		[control cacheDisplayInRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h) toBitmapImageRep:rep];
		check(same_colour([rep colorAtX:5 y:5], [cell backgroundColor], 0.04),
		      "the Standard bar's corner is the background it reports");
		for (y = 3; y < h - 3; y++) {
			for (x = 4; x < w - 4; x++) {
				NSColor *pixel = [rep colorAtX:x y:y];

				if (pixel != nil && [pixel redComponent] < 0.35 && [pixel greenComponent] < 0.35
				    && [pixel blueComponent] < 0.35) {
					ink++;
				}
			}
		}
		check(ink > 0, "the component titles draw ink on the bar");
		[rep release];
	}

	[control release];
	[window release];
	[target release];
	printf("path_control: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
