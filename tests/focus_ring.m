/*
 * focus_ring — the highlight around the control the keyboard is in: where it goes, when it is earned, and what it is
 * made of.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE RING IS A WINDOW'S, AND THIS PROBE IS WHY.** Every subview is clipped to its own frame, so a control that drew
 * its own ring would have all of it thrown away — the ring is outside the frame by definition. So the ink is asserted
 * where it actually lands: outside the control's rectangle and inside the window's, in the accent colour, only while
 * that window is key.
 */
#import <AppKit/AppKit.h>

#include <math.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* THE WINDOW DOORS THIS PROBE DRIVES: the content walk, which control the ring belongs to, and the ring's own ink with
 * the clip a PARTIAL paint gives it. */
@interface NSWindow (APPKITFocusRing)
- (void)cg_drawContentInContext:(NSGraphicsContext *)context;
- (NSView *)cg_focusRingView;
- (void)cg_drawFocusRingInContext:(CGContextRef)c clip:(NSRect)clip;
@end

/* AND THE VIEW'S DIRTY REGION, WHICH IS HOW A PARTIAL PAINT DECIDES WHAT TO PAINT AT ALL. */
@interface NSView (APPKITDirtyRegion)
- (void)cg_dirtyRegionRecursive:(NSRect *)out max:(NSUInteger)max count:(NSUInteger *)outCount;
- (void)cg_clearDirtyRegionRecursive;
@end

@interface RingTarget : NSObject
{
@public
	int fired;
}
@end

@implementation RingTarget

- (void)fire:(id)sender
{
	(void)sender;
	fired++;
}

@end

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

/* **HOW MUCH OF THE ACCENT IS IN A RECTANGLE**, counted as pixels that are nearer the accent's hue than the window's
 * face: a ring is accent over grey, so "is this pixel blue-ish" is the honest question and one a flat face cannot
 * answer yes to.
 *
 * THE RECTANGLE ARRIVES IN THE CONTENT'S COORDINATES — the ones the view tree and the ring both work in, with y
 * growing upward — and the bitmap's rows grow downward, so the band is MIRRORED here rather than at every call site.
 * MEASURED, when this was not done: the "ring" and "inside the field" rectangles landed on top of each other and both
 * counted the same ink. */
static int accent_pixels(NSBitmapImageRep *rep, NSRect rect)
{
	unsigned char *data = [rep bitmapData];
	int width = (int)[rep pixelsWide];
	int height = (int)[rep pixelsHigh];
	int x1 = (int)rect.origin.x, y1 = height - (int)(rect.origin.y + rect.size.height);
	int x2 = (int)(rect.origin.x + rect.size.width), y2 = height - (int)rect.origin.y;
	int count = 0;
	int x, y;

	if (x1 < 0) x1 = 0;
	if (y1 < 0) y1 = 0;
	if (x2 > width) x2 = width;
	if (y2 > height) y2 = height;
	for (y = y1; y < y2; y++) {
		for (x = x1; x < x2; x++) {
			unsigned char *p = data + ((size_t)y * (size_t)width + (size_t)x) * 4u;

			/* **THE ACCENT'S SIGNATURE, WITHOUT ASSUMING A CHANNEL ORDER.** The face is grey (three equal
			 * channels) and the accent is not, so "one channel is clearly the greatest" is the question — with
			 * blue named as that channel rather than the byte at a particular offset. */
			{
				int r = p[0], g = p[1], b = p[2];

				if (b > r + 24 && b > g + 24) {
					count++;
					continue;
				}
			}
			if (0) {
				count++;
			}
		}
	}
	return count;
}

/* **THE TWO PASSES THE WINDOW MAKES, WRITTEN OUT SO THIS PROBE PAINTS WHAT A LIVE WINDOW PAINTS.** The whole-frame one
 * draws the tree and then the ring with no clip; the partial one fills the damaged pieces, walks the tree over each of
 * them, and draws the ring CLIPPED TO THE UNION — which is the order `-cg_drawFrameDirty:` uses, and the order that made
 * the old ring survive when the damage list did not name it. */
static NSBitmapImageRep *whole_pass(NSWindow *window, int width, int height)
{
	NSBitmapImageRep *rep = new_rep(width, height);
	NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:context];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height)] fill];
	[window cg_drawContentInContext:context];
	[NSGraphicsContext restoreGraphicsState];
	return rep;
}

/* THE RING'S BAND: a control's rectangle grown by the ring's reach, minus the rectangle itself. */
static NSRect band_outside(NSRect frame, CGFloat reach)
{
	(void)reach;
	return NSInsetRect(frame, -5.0, -5.0);
}

int main(void)
{
	NSApplication *app = [NSApplication sharedApplication];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 260.0)
						       styleMask:NSTitledWindowMask
							 backing:NSBackingStoreBuffered
							   defer:NO];
	NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 260.0)] autorelease];
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(40.0, 120.0, 180.0, 24.0)] autorelease];
	NSTextField *other = [[[NSTextField alloc] initWithFrame:NSMakeRect(40.0, 80.0, 180.0, 24.0)] autorelease];
	NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(40.0, 40.0, 90.0, 24.0)] autorelease];
	RingTarget *target = [[[RingTarget alloc] init] autorelease];
	NSBitmapImageRep *rep;
	NSGraphicsContext *context;
	NSRect frame;
	int ringBand, faceOnly;

	(void)app;
	printf("focus_ring: the highlight around the control the keyboard is in\n");

	[window setContentView:content];
	[content addSubview:field];
	[content addSubview:other];
	[content addSubview:button];
	[field setEditable:YES];
	[other setEditable:YES];
	[button setTitle:@"Go"];
	[button setTarget:target];
	[button setAction:@selector(fire:)];

	/* 1. **THE RING IS EARNED BY THE KEYBOARD AND BY THE KEY WINDOW.** A window that is not key shows none even when a
	 * field in it holds the keyboard — a tip in the wrong window explains a control nobody is typing into. */
	[window makeKeyWindow];
	check([window isKeyWindow], "the window can be the key window");
	check([window cg_focusRingView] == nil, "a window with no first responder has nothing to ring");

	rep = new_rep(400, 260);
	context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:context];
	[window cg_drawContentInContext:context];
	[NSGraphicsContext restoreGraphicsState];
	check(accent_pixels(rep, band_outside([field frame], 5.0)) == 0,
	      "and an unfocused field is not ringed");
	[rep release];

	/* 2. **A FOCUSED FIELD IS RINGED, AND THE RING IS OUTSIDE IT.** The band is the field's rectangle grown by the
	 * ring's reach, and the ink must be there rather than drawn inside the bezel: that is the whole difference between a
	 * highlight around a control and a second border on it. */
	check([window makeFirstResponder:field], "a field takes the keyboard");
	check([window cg_focusRingView] == field, "and the FIELD is what the ring goes around, not the editor inside it");
	rep = new_rep(400, 260);
	context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:context];
	[window cg_drawContentInContext:context];
	[NSGraphicsContext restoreGraphicsState];
	frame = [field frame];
	ringBand = accent_pixels(rep, band_outside(frame, 5.0)) -
		   accent_pixels(rep, NSInsetRect(frame, 1.0, 1.0));
	faceOnly = accent_pixels(rep, NSInsetRect(frame, 1.0, 1.0));
	check(ringBand > 40, "a focused field is RINGED in the accent colour");
	check(faceOnly == 0, "and the ink is OUTSIDE the field, not a second border inside it");
	[rep release];

	/* 3. **AND IT MOVES WITH THE KEYBOARD.** Two fields, two rings in turn — the one that lost the keyboard must be
	 * plain again, which is what makes the ring say "here" rather than "somewhere". */
	check([window makeFirstResponder:other], "the keyboard moves to the second field");
	check([window cg_focusRingView] == other, "and the ring follows it");
	rep = new_rep(400, 260);
	context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:context];
	[window cg_drawContentInContext:context];
	[NSGraphicsContext restoreGraphicsState];
	check(accent_pixels(rep, band_outside([other frame], 5.0)) > 40,
	      "the field that has the keyboard wears the ring");
	check(accent_pixels(rep, band_outside([field frame], 5.0)) == 0,
	      "and the one that lost it does not");
	[rep release];

	/* 4. **AND A PARTIAL PAINT CLEARS THE OLD RING, WHICH IS WHAT "NOT CLEARING ON THE OLD TARGET" WAS.** The window
	 * prefers a partial paint the moment any view is dirty, and a focus change always is: the field being left marks its
	 * own caret and selection. So the ring's two bands have to be IN THE DAMAGE LIST — the old one to erase it and the new
	 * one to draw it — or the pass paints the fields and leaves the ring around the field that no longer has the
	 * keyboard exactly where it was, until something unrelated repaints that corner. MEASURED, and this case is that
	 * measurement written down: the damage list is asked directly, and then a partial pass is painted over a bitmap that
	 * still holds the old ring. */
	{
		NSRect damage[APPKIT_DAMAGE_RECTS];
		NSUInteger count = 0, i;
		NSRect oldBand = NSInsetRect([field frame], -5.0, -5.0);
		NSRect newBand = NSInsetRect([other frame], -5.0, -5.0);
		BOOL oldNamed = NO, newNamed = NO;
		NSBitmapImageRep *before;
		NSGraphicsContext *context;
		NSRect clip = NSZeroRect;

		check([window makeFirstResponder:field], "the first field has the keyboard again");
		[content cg_clearDirtyRegionRecursive];
		check([window makeFirstResponder:other], "and the keyboard moves to the second one");
		[content cg_dirtyRegionRecursive:damage max:APPKIT_DAMAGE_RECTS count:&count];
		for (i = 0; i < count; i++) {
			/* **CONTAINMENT, NOT OVERLAP.** A field that is being edited marks its own rectangle dirty, and that
			 * rectangle is INSIDE the ring's band — so "some piece touches the band" is answered yes by the field's
			 * own damage even when the ring's band was never named. The band has to be there as a piece of its own,
			 * which is exactly what a partial paint needs to erase the glow. */
			if (NSContainsRect(damage[i], oldBand)) {
				oldNamed = YES;
			}
			if (NSContainsRect(damage[i], newBand)) {
				newNamed = YES;
			}
			clip = NSIsEmptyRect(clip) ? damage[i] : NSUnionRect(clip, damage[i]);
		}
		check(oldNamed, "the ring the keyboard LEFT is in the damage list");
		check(newNamed, "and so is the one it arrived at");

		/* AND THEN THE PASS ITSELF: a bitmap painted in full with the first field focused, then a partial pass after
		 * the move. The old band must be plain and the new one ringed. */
		[window makeFirstResponder:field];
		before = whole_pass(window, 400, 260);
		check(accent_pixels(before, oldBand) > 40, "the first field is ringed before the move");
		{
			/* the move happens on the LIVE window, so the damage above is the real one; the bitmap still shows the
			 * old ring, which is what a partial pass has to erase. */
			[content cg_clearDirtyRegionRecursive];
			[window makeFirstResponder:other];
			{
				NSRect pieces[APPKIT_DAMAGE_RECTS];
				NSUInteger n = 0;
				NSRect region = NSZeroRect;

				[content cg_dirtyRegionRecursive:pieces max:APPKIT_DAMAGE_RECTS count:&n];
				context = [NSGraphicsContext graphicsContextWithBitmapImageRep:before];
				[NSGraphicsContext saveGraphicsState];
				[NSGraphicsContext setCurrentContext:context];
				for (i = 0; i < n; i++) {
					[[NSColor whiteColor] setFill];
					[[NSBezierPath bezierPathWithRect:pieces[i]] fill];
					region = NSIsEmptyRect(region) ? pieces[i] : NSUnionRect(region, pieces[i]);
				}
				[content displayRect:region];
				[window cg_drawFocusRingInContext:(CGContextRef)[context graphicsPort] clip:region];
				[NSGraphicsContext restoreGraphicsState];
			}
		}
		check(accent_pixels(before, oldBand) == 0, "a partial paint CLEARS the ring the keyboard left");
		check(accent_pixels(before, newBand) > 40, "and draws the one it arrived at");
		[before release];
	}

	/* 4b. **AND THE LIVE WAY FROM ONE FIELD TO THE NEXT TAKES THREE STEPS, NOT ONE.** A click runs through
	 * `-fieldEditor:forObject:`, which hands the window's ONE editor to the new field — and that hands-over step CLEARS
	 * the responder (MEASURED: `NSText` before, nil after), then `-selectWithFrame:…` reinstalls the editor and asks for
	 * it. Which means the ring's old end has to be named at the moment the responder is cleared, when the ring's target
	 * still answers; a door that asked "which control wears the ring?" AFTER resigning was told nil, damaged nothing,
	 * and the old ring stayed on the glass: MEASURED on the live desktop as a click from one field to the next leaving
	 * BOTH ringed. */
	{
		NSRect damage[APPKIT_DAMAGE_RECTS];
		NSUInteger count = 0, i;
		NSRect oldBand = NSInsetRect([field frame], -5.0, -5.0);
		NSRect newBand = NSInsetRect([other frame], -5.0, -5.0);
		BOOL oldNamed = NO;
		NSText *editor;

		check([window makeFirstResponder:field], "the first field is being edited");
		editor = [field currentEditor];
		check(editor != nil, "and it has the window's editor standing in it");
		[content cg_clearDirtyRegionRecursive];
		/* THE CLICK, IN THE ORDER A CLICK MAKES IT: the editor is handed to the second field, moved into it, and then
		 * asked for as the responder it already is. */
		editor = (NSText *)[window fieldEditor:YES forObject:other];
		[[other cell] selectWithFrame:[other bounds] inView:other editor:editor delegate:other start:0
				       length:(NSInteger)[[other stringValue] length]];
		check([window firstResponder] == editor, "the editor is the first responder again, in the second field");
		check([window cg_focusRingView] == other, "and the ring's target is the second field");
		[content cg_dirtyRegionRecursive:damage max:APPKIT_DAMAGE_RECTS count:&count];
		for (i = 0; i < count; i++) {
			if (NSContainsRect(damage[i], oldBand)) {
				oldNamed = YES;	/* the band around the field that no longer has the keyboard */
			}
		}
		check(oldNamed, "so the ring around the FIRST field is damaged and will be cleared");
	}

	/* 5. **A BUTTON CAN HOLD THE KEYBOARD, AND IS RINGED TOO.** Full keyboard access is always on in this tier (it reads
	 * no system preferences), so a button accepts the first responder — otherwise the ring would exist for text fields
	 * and be unreachable for every other control. */
	check([button acceptsFirstResponder], "a button accepts the keyboard");
	check([window makeFirstResponder:button], "and can become the first responder");
	rep = new_rep(400, 260);
	context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:context];
	[window cg_drawContentInContext:context];
	[NSGraphicsContext restoreGraphicsState];
	check(accent_pixels(rep, band_outside([button frame], 5.0)) > 40, "a focused BUTTON wears the ring");
	[rep release];

	/* 6. **AND SPACE PRESSES IT, WHICH IS WHY TAKING THE KEYBOARD MEANS ANYTHING.** A control that can be Tabbed to and
	 * then ignores the keyboard is a ring around nothing. */
	{
		NSEvent *space = [NSEvent keyEventWithType:NSKeyDown location:NSZeroPoint
					    modifierFlags:0 timestamp:1.0 windowNumber:[window windowNumber]
					    context:nil characters:@" " charactersIgnoringModifiers:@" "
					    isARepeat:NO keyCode:49];

		[button keyDown:space];
		check(target->fired == 1, "Space presses the focused button");
	}

	/* 7. **A DISABLED CONTROL TAKES NOTHING AND WEARS NOTHING.** The ring is the keyboard's, and a disabled button cannot
	 * have either — an enabled-looking highlight would say the control is usable. */
	[button setEnabled:NO];
	check(![button acceptsFirstResponder], "a disabled button does not take the keyboard");

	/* 8. **AND A WINDOW THAT IS NOT KEY SHOWS NO RING, EVEN WITH THE KEYBOARD IN A FIELD.** The flag is the window's, so
	 * the ink is too: one repaint per focus change rather than a ring that keeps glowing behind whatever is in front. */
	[button setEnabled:YES];
	[window makeFirstResponder:field];
	check([window cg_focusRingView] == field, "the field has the keyboard again");
	[window resignKeyWindow];
	rep = new_rep(400, 260);
	context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:context];
	[window cg_drawContentInContext:context];
	[NSGraphicsContext restoreGraphicsState];
	check(accent_pixels(rep, band_outside([field frame], 5.0)) == 0,
	      "a window that is not key paints no ring");
	[rep release];

	[window close];
	printf(s_failed == 0 ? "focus_ring: all checks passed\n" : "focus_ring: FAILURES\n");
	return (s_failed == 0) ? 0 : 1;
}
