/*
 * text_attachment_tracking.m — A PICTURE IN THE TEXT IS PRESSED, TRACKED AND RELEASED BY THE VIEW.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE TRACKING FAMILY IS DRIVEN BY THE TEXT VIEW'S OWN EVENT STREAM, NOT BY A MODAL LOOP.** `NSCell` refuses
 * `-trackMouse:inRect:ofView:untilMouseUp:` because a loop built from guessed coordination can hang the guest. This
 * slice does not re-introduce one: `NSTextView` hit-tests the attachment under the pointer, asks the cell whether it
 * wants the mouse, and then sends the DOWN, every DRAG and the UP through the cell's tracking door — one event per
 * call. So the probe drives the view's real `-mouseDown:`/`-mouseDragged:`/`-mouseUp:` and watches the cell, which is
 * the half a pixel test alone cannot see.
 *
 * WHAT IS MEASURED:
 *
 *   1. A cell ANSWERS the simple and sophisticated tracking doors, and `-highlight:` puts ink on the picture: a
 *      highlighted red image gains accent pixels, and clearing the flag takes them away again.
 *   2. A press on the picture is the VIEW's: the attachment character is selected, the cell is highlighted, and the
 *      accent is visible in the rendered view.
 *   3. A drag out of the cell's frame clears the highlight and a drag back in restores it — the cell's own frame, not
 *      the attachment character, is what the pointer is compared against.
 *   4. A recording cell sees EXACTLY ONE call per event — down, two drags, up — with the attachment's character
 *      index, and the up event's answer is Apple's: YES when the button came up inside the frame, NO when it did not.
 *   5. A cell that says it does NOT want the mouse leaves an ordinary click: no tracking call, and a caret rather
 *      than an attachment selection.
 *   6. And a cell that wants the mouse but DECLINES the press itself leaves the same ordinary click, because a refusal
 *      is a refusal and not a swallowed event.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSText.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>
#import <Foundation/Foundation.h>
#include <CoreGraphics/CGContext.h>
#include <stdio.h>

#define W 200
#define H 60

#define BOX_W 30.0
#define BOX_H 12.0
#define ATTACH_INDEX 1		/* the string is `a`, U+FFFC, `b` */

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSImage *red_image(CGFloat w, CGFloat h)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		pixelsWide:(NSInteger)w pixelsHigh:(NSInteger)h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:(NSInteger)w * 4 bitsPerPixel:32];
	NSImage *image;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, w, h)] fill];
	image = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
	[image addRepresentation:rep];
	[rep release];
	return image;
}

/* **THE ACCENT OVER A RED PICTURE, COUNTED BY ITS COLOUR RATHER THAN BY "NOT WHITE".** The overlay is the platform's
 * selection colour at 35%, so a covered pixel is (0.72, 0.15, 0.28) — still mostly red, with a blue the plain picture
 * does not have. The bounds keep the SELECTION BAND behind the picture out of the count (that is a much bluer blue),
 * so a positive answer is the overlay and not the text view's own selection ink. */
static int accent_pixels(NSBitmapImageRep *rep)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			NSColor *c = [rep colorAtX:x y:y];
			CGFloat r, g, b;

			if (c == nil) {
				continue;
			}
			r = [c redComponent];
			g = [c greenComponent];
			b = [c blueComponent];
			if (r > 0.5 && r < 0.85 && g < 0.35 && b > 0.2 && b < 0.5) {
				count++;
			}
		}
	}
	return count;
}

static NSBitmapImageRep *draw_view(NSTextView *view)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
	NSGraphicsContext *ctx;
	CGContextRef cg;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	cg = (CGContextRef)[ctx graphicsPort];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	/* THE VIEW IS FLIPPED AND THIS REP IS NOT, so the same mirror a superview applies is applied here. */
	CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[view drawRect:[view bounds]];
	return rep;
}

static NSBitmapImageRep *draw_cell(NSCell<NSTextAttachmentCell> *cell)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[cell drawWithFrame:NSMakeRect(5.0, 5.0, BOX_W, BOX_H) inView:nil];
	return rep;
}

/* **WHERE THE MANAGER PUTS THE BOX, READ BACK FROM THE MANAGER ITSELF.** The x is the character's own offset (the
 * container's padding is already in it); the y is the view's inset plus the fragment's baseline, less the box's
 * height, which is the arithmetic `-drawGlyphsForGlyphRange:atPoint:` uses. */
static NSRect attachment_frame(NSTextView *view)
{
	NSLayoutManager *manager = [view layoutManager];
	CGFloat x = [manager cg_offsetForGlyphAtIndex:ATTACH_INDEX];
	CGFloat baseline = [manager cg_baselineForGlyphAtIndex:ATTACH_INDEX];

	return NSMakeRect(x, NS_TEXT_INSET + baseline - BOX_H, BOX_W, BOX_H);
}

static NSEvent *mouse(NSEventType type, NSPoint point, NSWindow *window)
{
	return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0.0
			      windowNumber:[window windowNumber] context:nil eventNumber:0
				clickCount:1 pressure:1.0f];
}

/* **A CELL THAT RECORDS THE TRACKING CONTRACT RATHER THAN PAINTING IT.** It is the real `NSTextAttachmentCell` with
 * three answers changed: whether it wants the mouse, how many events of each kind it was sent, and what it says about
 * the release. The index and the frame it was handed are recorded too, so the probe can check WHICH attachment and
 * WHERE rather than only that something was called. */
@interface AGRecordingAttachmentCell : NSTextAttachmentCell
{
@public
	BOOL trackWanted;
	BOOL declinePress;
	int downs;
	int drags;
	int ups;
	BOOL lastUpInside;
	NSUInteger lastIndex;
	NSRect lastFrame;
}
@end

@implementation AGRecordingAttachmentCell

- (BOOL)wantsToTrackMouse
{
	return trackWanted;
}

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView
  atCharacterIndex:(NSUInteger)charIndex untilMouseUp:(BOOL)flag
{
	NSEventType type = [theEvent type];

	(void)flag;
	lastIndex = charIndex;
	lastFrame = cellFrame;
	if (type == NSLeftMouseDown) {
		downs++;
		return !declinePress;
	}
	if (type == NSLeftMouseDragged) {
		drags++;
		return YES;
	}
	if (type == NSLeftMouseUp) {
		NSPoint point = [controlView convertPoint:[theEvent locationInWindow] fromView:nil];

		ups++;
		lastUpInside = NSPointInRect(point, cellFrame);
		return lastUpInside;
	}
	return YES;
}

@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
	NSImage *image = red_image(BOX_W, BOX_H);
	NSTextAttachment *attachment = [[NSTextAttachment textAttachmentWithImage:image] retain];
	NSCell<NSTextAttachmentCell> *cell = [attachment attachmentCell];
	unichar chars[3];
	NSRect frame;
	NSPoint inside;
	NSPoint outside;

	setvbuf(stdout, NULL, _IONBF, 0);
	[window setContentView:view];
	[view setVerticallyResizable:NO];
	[view setFrameSize:NSMakeSize((CGFloat)W, (CGFloat)H)];

	chars[0] = 'a';
	chars[1] = (unichar)NSAttachmentCharacter;
	chars[2] = 'b';
	[view setString:[NSString stringWithCharacters:chars length:3]];
	[[view textStorage] addAttribute:NSAttachmentAttributeName value:attachment
				    range:NSMakeRange(ATTACH_INDEX, 1)];
	frame = attachment_frame(view);
	inside = NSMakePoint(frame.origin.x + frame.size.width / 2.0, frame.origin.y + frame.size.height / 2.0);
	outside = NSMakePoint(frame.origin.x + frame.size.width + 40.0, inside.y);
	printf("  (note: the attachment's box is x=%.2f y=%.2f w=%.2f h=%.2f)\n",
	       (double)frame.origin.x, (double)frame.origin.y, (double)frame.size.width, (double)frame.size.height);

	/* 1. **THE CELL ANSWERS THE TRACKING DOORS, AND THE HIGHLIGHT IS INK.** */
	check([cell wantsToTrackMouse], "an attachment cell wants the mouse");
	check([cell wantsToTrackMouseForEvent:mouse(NSLeftMouseDown, inside, window)
				      inRect:frame ofView:view atCharacterIndex:ATTACH_INDEX],
	      "and the event-and-index door forwards that answer");
	{
		NSBitmapImageRep *plain = draw_cell(cell);

		check(accent_pixels(plain) == 0, "an unhighlighted picture carries no accent ink");
		[plain release];
	}
	[cell highlight:YES withFrame:frame inView:nil];
	{
		NSBitmapImageRep *lit = draw_cell(cell);
		int litCount = accent_pixels(lit);

		printf("  (note: highlighting the cell put %d accent pixel(s) on it)\n", litCount);
		check(litCount > 0, "`-highlight:YES` puts accent ink on the picture");
		[lit release];
	}
	[cell highlight:NO withFrame:frame inView:nil];
	{
		NSBitmapImageRep *dark = draw_cell(cell);

		check(accent_pixels(dark) == 0, "and `-highlight:NO` takes it away");
		[dark release];
	}

	/* 2. **A PRESS ON THE PICTURE BELONGS TO THE VIEW AND THE CELL.** */
	[view mouseDown:mouse(NSLeftMouseDown, inside, window)];
	printf("  (note: the press selected (%lu,%lu) and the cell is %s)\n",
	       (unsigned long)[view selectedRange].location, (unsigned long)[view selectedRange].length,
	       [cell isHighlighted] ? "highlighted" : "plain");
	check([view selectedRange].location == ATTACH_INDEX && [view selectedRange].length == 1,
	      "a press on the picture selects the attachment CHARACTER");
	check([cell isHighlighted], "and the cell records the press");
	{
		NSBitmapImageRep *pressed = draw_view(view);
		int pressedCount = accent_pixels(pressed);

		printf("  (note: the rendered view carries %d accent pixel(s) over the picture)\n", pressedCount);
		check(pressedCount > 0, "the pressed picture is highlighted IN THE VIEW'S OWN INK");
		[pressed release];
	}

	/* 3. **THE DRAG IS COMPARED AGAINST THE CELL'S FRAME, NOT THE CHARACTER.** */
	[view mouseDragged:mouse(NSLeftMouseDragged, outside, window)];
	check(![cell isHighlighted], "a drag OUT of the cell's frame clears the highlight");
	[view mouseDragged:mouse(NSLeftMouseDragged, inside, window)];
	check([cell isHighlighted], "and a drag back IN restores it");
	[view mouseUp:mouse(NSLeftMouseUp, inside, window)];
	check(![cell isHighlighted], "the release clears it");

	/* 4. **AND ONE EVENT IS ONE CALL, WITH THE ATTACHMENT'S OWN CHARACTER INDEX.** */
	{
		AGRecordingAttachmentCell *recorder = [[AGRecordingAttachmentCell alloc] init];

		[recorder setImage:image];
		recorder->trackWanted = YES;
		[attachment setAttachmentCell:recorder];
		[view mouseDown:mouse(NSLeftMouseDown, inside, window)];
		[view mouseDragged:mouse(NSLeftMouseDragged, inside, window)];
		[view mouseDragged:mouse(NSLeftMouseDragged, outside, window)];
		[view mouseUp:mouse(NSLeftMouseUp, inside, window)];
		printf("  (note: recorder saw %d down(s), %d drag(s), %d up(s); index %lu; up inside %s)\n",
		       recorder->downs, recorder->drags, recorder->ups,
		       (unsigned long)recorder->lastIndex, recorder->lastUpInside ? "yes" : "no");
		check(recorder->downs == 1 && recorder->drags == 2 && recorder->ups == 1,
		      "the cell is sent EXACTLY one call per event of the gesture");
		check(recorder->lastIndex == ATTACH_INDEX, "and every call carries the attachment's character index");
		check(recorder->lastUpInside, "the release reports Apple's answer: the button came up INSIDE the frame");

		/* A release OUTSIDE answers NO, and is still the last event of the session. */
		[view mouseDown:mouse(NSLeftMouseDown, inside, window)];
		[view mouseUp:mouse(NSLeftMouseUp, outside, window)];
		check(recorder->ups == 2 && !recorder->lastUpInside,
		      "a release outside the frame answers NO");
		[view mouseDragged:mouse(NSLeftMouseDragged, inside, window)];
		[view mouseUp:mouse(NSLeftMouseUp, inside, window)];
		check(recorder->drags == 2 && recorder->ups == 2,
		      "and events AFTER the release do not reach the cell again");

		/* 5. **A CELL THAT DOES NOT WANT THE MOUSE LEAVES AN ORDINARY CLICK.** */
		recorder->trackWanted = NO;
		recorder->downs = recorder->drags = recorder->ups = 0;
		[view mouseDown:mouse(NSLeftMouseDown, inside, window)];
		[view mouseUp:mouse(NSLeftMouseUp, inside, window)];
		check(recorder->downs == 0 && recorder->drags == 0 && recorder->ups == 0,
		      "a cell that declines tracking is never called");
		check([view selectedRange].length == 0,
		      "and the press is a caret rather than an attachment selection");

		/* 6. **AND A CELL THAT WANTS THE MOUSE BUT DECLINES THE PRESS IS THE SAME ORDINARY CLICK.** */
		recorder->trackWanted = YES;
		recorder->declinePress = YES;
		recorder->downs = recorder->drags = recorder->ups = 0;
		[view mouseDown:mouse(NSLeftMouseDown, inside, window)];
		check(recorder->downs == 1 && recorder->drags == 0 && recorder->ups == 0,
		      "a declined press ends the session at once — no drag or release follows");
		check([view selectedRange].length == 0,
		      "and the declined press falls back to the ordinary caret");
		[view mouseUp:mouse(NSLeftMouseUp, inside, window)];
		[recorder release];
	}

	[attachment release];
	[image release];
	[view release];
	[window release];
	[pool release];
	printf("text_attachment_tracking: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
