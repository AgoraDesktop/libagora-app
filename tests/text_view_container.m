/*
 * text_view_container — the container, its margin, its origin, and the point that maps to a character.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CLAIM THIS SLICE MAKES IS THAT A TEXT VIEW'S MARGIN AND ITS HIT TEST ARE ONE COORDINATE SPACE**, and that is
 * not a thing a header can say: the inset moves the glyphs, the origin is where the container says they start, and the
 * point-to-character door has to agree with both or a click lands next to the letter it was over. So the assertions here
 * are PIXELS and ROUND TRIPS rather than property reads — the ink moves by exactly the margin that was set, and a point
 * inside a character's box answers that character's index (and its neighbour's at the far end of the box, which is the
 * negative half of the same claim).
 *
 * WHAT IS ASSERTED, in order:
 *
 *   1. THE DEFAULTS, including the one deviation this tier states: the inset is (0, `NS_TEXT_INSET`), not Apple's
 *      (0, 0), because every pixel of this class was measured down from the field's own four-point air.
 *   2. THE MARGIN IS REAL: moving the inset moves the ink by the same number of points, in both directions.
 *   3. THE HIT TEST AGREES WITH THE DRAWING: a point a quarter of the way into a character answers that character, three
 *      quarters of the way answers the next — and the same arithmetic holds with a margin set, which is what makes the
 *      two coordinate spaces one.
 *   4. THE EDGES: a point below the last line answers the end of the text, and one left of a wrapped line answers that
 *      line's first character.
 *   5. THE CARET GOES THROUGH ITS DOOR: no caret without an editing session, a caret with one, and the caret's ink is
 *      the colour `-insertionPointColor` answers — the reader that makes the setter worth having.
 *   6. `-drawViewBackgroundInRect:` IS A DOOR A SUBCLASS SEES, and `-setNeedsDisplayInRect:avoidAdditionalLayout:` and
 *      `-updateInsertionPointStateAndRestartTimer:` mark the rects they are supposed to mark (a recording subclass is the
 *      witness, because "it marked something dirty" is not a claim a flag can settle).
 *   7. THE CONTAINER DOORS: the designated initialiser adopts a container, `-setTextContainer:` sizes it to the frame,
 *      `-replaceTextContainer:` re-points WITHOUT sizing it, and `nil` leaves the view with no container rather than
 *      with a dead one — and putting one back draws the text again.
 *   8. `-setConstrainedFrameSize:` IS A FLOOR UNDER THE HEIGHT and the width still decides the wrap.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSTextStorage.h>
#import <AppKit/NSTextContainer.h>
#import <AppKit/NSLayoutManager.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

#define W 320
#define H 160

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int near_enough(CGFloat a, CGFloat b)
{
	return fabs((double)(a - b)) < 0.01;
}

/* ============================================================================================ *
 * THE SURFACE, DRAWN THE WAY A SUPERVIEW WOULD DRAW IT.                                        *
 *                                                                                              *
 * `NSTextView` IS FLIPPED and a bitmap rep's context is not, so the transform below is the      *
 * mirror `NSView -displayRect:` applies to a child that differs from it: in the REP, a row index *
 * therefore runs OPPOSITE to the view's y, which is why the row assertions below compare        *
 * deltas and say which way round they are.                                                     *
 * ============================================================================================ */
static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static NSBitmapImageRep *draw_view(NSView *view)
{
	NSBitmapImageRep *rep = new_rep(W, H);
	NSGraphicsContext *ctx;
	CGContextRef cg;

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	ctx = [NSGraphicsContext currentContext];
	cg = (CGContextRef)[ctx graphicsPort];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	CGContextTranslateCTM(cg, 0.0, (CGFloat)H);
	CGContextScaleCTM(cg, 1.0, -1.0);
	[view drawRect:[view bounds]];
	[NSGraphicsContext setCurrentContext:nil];
	return rep;
}

static int is_dark(NSColor *c)
{
	return (c != nil && [c alphaComponent] > 0.3 && [c redComponent] < 0.4 && [c greenComponent] < 0.4
		&& [c blueComponent] < 0.4);
}

static int is_green(NSColor *c)
{
	return (c != nil && [c alphaComponent] > 0.3 && [c greenComponent] > 0.45
		&& [c greenComponent] > [c redComponent] + 0.15 && [c greenComponent] > [c blueComponent] + 0.15);
}

/* The leftmost column holding dark ink, or -1 when the surface has none. */
static int leftmost_ink(NSBitmapImageRep *rep, int y0, int y1)
{
	int x, y;

	for (x = 0; x < W; x++) {
		for (y = y0; y < y1; y++) {
			if (is_dark([rep colorAtX:x y:y])) {
				return x;
			}
		}
	}
	return -1;
}

/* The smallest REP row index holding dark ink — which is the view's LARGEST y, because of the mirror. */
static int topmost_ink_row(NSBitmapImageRep *rep)
{
	int x, y;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			if (is_dark([rep colorAtX:x y:y])) {
				return y;
			}
		}
	}
	return -1;
}

static int count_green(NSBitmapImageRep *rep)
{
	int x, y, count = 0;

	for (y = 0; y < H; y++) {
		for (x = 0; x < W; x++) {
			if (is_green([rep colorAtX:x y:y])) {
				count++;
			}
		}
	}
	return count;
}

static int count_dark_in_column(NSBitmapImageRep *rep, int column)
{
	int y, count = 0;

	for (y = 0; y < H; y++) {
		if (is_dark([rep colorAtX:column y:y])) {
			count++;
		}
	}
	return count;
}

/* **ANY INK AT ALL, WHICH IS WHAT A ONE-POINT BAR AT A FRACTIONAL x LOOKS LIKE.** A caret is drawn at the layout's own
 * x (19.344 in the probe's own note), so it straddles two pixel columns and NEITHER is the pure pen colour — asserting
 * "dark" of one column would be asserting that the layout happened to land on a whole number. */
static int count_ink_in_columns(NSBitmapImageRep *rep, int column)
{
	int x, y, count = 0;

	for (x = column; x <= column + 1; x++) {
		if (x < 0 || x >= W) {
			continue;
		}
		for (y = 0; y < H; y++) {
			NSColor *c = [rep colorAtX:x y:y];

			if (c != nil && [c alphaComponent] > 0.3
			    && ([c redComponent] < 0.85 || [c greenComponent] < 0.85 || [c blueComponent] < 0.85)) {
				count++;
			}
		}
	}
	return count;
}

/* **SCREEN TO VIEW, WHICH IS THE CONVERSION `-firstRectForCharacterRange:` MAKES IN THE OTHER DIRECTION.** The rect
 * doors answer in SCREEN coordinates (Apple's contract) and the insertion door takes the VIEW's, so a probe that wants
 * to drive one with the other has to undo exactly this much — the same two lines `-characterIndexForPoint:` uses. */
static NSPoint point_in_view(NSTextView *view, NSPoint screenPoint)
{
	NSRect frame = [[view window] frame];
	NSPoint inWindow = NSMakePoint(screenPoint.x - frame.origin.x, screenPoint.y - frame.origin.y);

	return [view convertPoint:inWindow fromView:nil];
}

static NSTextView *make_view(NSWindow *window, NSString *text)
{
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

	[view setFont:[NSFont systemFontOfSize:14.0]];
	[view setEditable:YES];
	[view setSelectable:YES];
	[view setDrawsBackground:NO];
	[view setString:text];
	/* THE TYPED REFERENCE IS THE OWNING ONE; `-contentView` answers NSView *, which is the wrong class here. */
	[window setContentView:view];
	return view;
}

/* ============================================================================================ *
 * THE RECORDING VIEW, WHICH IS THE WITNESS FOR THE TWO DOORS NO PIXEL CAN SHOW.                *
 * ============================================================================================ */
@interface AGRecordingView : NSTextView
{
@public
	int marks;
	NSRect lastMark;
	int backdrops;
	BOOL paintsBackdrop;
}
@end

@implementation AGRecordingView
- (void)setNeedsDisplayInRect:(NSRect)invalidRect
{
	marks++;
	lastMark = invalidRect;
	[super setNeedsDisplayInRect:invalidRect];
}

- (void)drawViewBackgroundInRect:(NSRect)rect
{
	backdrops++;
	if (paintsBackdrop) {
		/* A COLOUR NOTHING ELSE IN THIS TEST USES, so "the subclass's ink is on the surface" is unambiguous. */
		[[NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.9 alpha:1.0] setFill];
		[[NSBezierPath bezierPathWithRect:rect] fill];
	} else {
		[super drawViewBackgroundInRect:rect];
	}
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	/* THE WINDOW OUTLIVES EVERY CASE: a view's `-window` is borrowed and the window clears it when it goes. */
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)
		styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
	BOOL ok;

	setvbuf(stdout, NULL, _IONBF, 0);

	/* 1. **THE DEFAULTS, INCLUDING THE DEVIATION.** */
	{
		NSTextView *view = make_view(window, @"Hg");
		NSSize inset = [view textContainerInset];
		NSPoint origin = [view textContainerOrigin];
		NSTextContainer *container = [view textContainer];

		check(near_enough(inset.width, 0.0) && near_enough(inset.height, 4.0),
		      "the default inset is (0, NS_TEXT_INSET) — the stated deviation from Apple's (0, 0)");
		check(near_enough(origin.x, inset.width) && near_enough(origin.y, inset.height),
		      "and the container's origin IS that inset, in a flipped view");
		check(container != nil && [container textView] == view,
		      "the view's container names the view back");
		check([container lineFragmentPadding] > 0.0,
		      "and the container's own padding is the air the left of the text has");
		check([view insertionPointColor] == nil, "no insertion-point colour is set, which answers the control colour");
		/* **THE CARET FOLLOWS THE EDITING SESSION, AND THE SESSION IS THE WINDOW'S.** A content view becomes its
		 * window's first responder when it is installed, so the honest default to assert here is the RELATIONSHIP;
		 * the two negatives below it are what pin the two halves down. */
		printf("  (note: first responder is %s the view)\n",
		       ([[view window] firstResponder] == view) ? "" : "NOT");
		check([view shouldDrawInsertionPoint] == ([[view window] firstResponder] == view),
		      "a caret is wanted exactly while the view is the window's first responder");
		[view setEditable:NO];
		check(![view shouldDrawInsertionPoint], "and never for a view that cannot be edited");
		[view setEditable:YES];
	}

	/* 2. **THE MARGIN MOVES THE INK.** */
	{
		NSTextView *view = make_view(window, @"Hg");
		NSBitmapImageRep *before = draw_view(view);
		int left0 = leftmost_ink(before, 0, H);
		int row0 = topmost_ink_row(before);

		[view setTextContainerInset:NSMakeSize(12.0, 20.0)];
		{
			NSBitmapImageRep *after = draw_view(view);
			int left1 = leftmost_ink(after, 0, H);
			int row1 = topmost_ink_row(after);
			NSPoint origin = [view textContainerOrigin];

			printf("  (note: ink at x=%d,row=%d with no margin; x=%d,row=%d with (12, 20))\n",
			       left0, row0, left1, row1);
			check(left0 >= 4 && left0 <= 6,
			      "with no margin the first ink begins at the container's four-point padding (plus its antialias)");
			check(left1 - left0 == 12, "and a twelve-point margin moves it twelve points right");
			check(row1 - row0 == 16,
			      "a twenty-point margin moves it sixteen points down — the default four was already there");
			check(near_enough(origin.x, 12.0) && near_enough(origin.y, 20.0),
			      "the origin followed the inset, which is the cache being invalidated rather than left stale");
			[after release];
		}
		[before release];
	}

	/* 3. **THE HIT TEST AND THE DRAWING ARE ONE SPACE**, with the default margin and with one set. */
	{
		NSArray *insets = [NSArray arrayWithObjects:[NSValue valueWithSize:NSMakeSize(0.0, 4.0)],
						   [NSValue valueWithSize:NSMakeSize(17.0, 9.0)], nil];
		NSUInteger k;

		for (k = 0; k < [insets count]; k++) {
			NSSize inset = [[insets objectAtIndex:k] sizeValue];
			NSTextView *view = make_view(window, @"Hamburgefonstiv");
			NSUInteger i, checked = 0, wrong = 0;
			NSString *text = [view string];

			[view setTextContainerInset:inset];
			for (i = 0; i + 1 < [text length]; i++) {
				NSRect a = [view firstRectForCharacterRange:NSMakeRange(i, 0)];
				NSRect b = [view firstRectForCharacterRange:NSMakeRange(i + 1, 0)];
				NSPoint p25, p75;

				/* A pair on different lines is a wrap boundary; the box arithmetic below is only about one line. */
				if (!near_enough(a.origin.y, b.origin.y) || b.origin.x <= a.origin.x) {
					continue;
				}
				p25 = NSMakePoint(a.origin.x + (b.origin.x - a.origin.x) * 0.25, a.origin.y + a.size.height / 2.0);
				p75 = NSMakePoint(a.origin.x + (b.origin.x - a.origin.x) * 0.75, a.origin.y + a.size.height / 2.0);
				checked++;
				if ([view characterIndexForInsertionAtPoint:point_in_view(view, p25)] != i) {
					wrong++;
				}
				if ([view characterIndexForInsertionAtPoint:point_in_view(view, p75)] != i + 1) {
					wrong++;
				}
			}
			printf("  (note: inset (%g, %g): %lu boxes checked, %lu answers wrong)\n",
			       (double)inset.width, (double)inset.height, (unsigned long)checked, (unsigned long)wrong);
			check(checked > 10, "the round trip had boxes to check");
			check(wrong == 0,
			      "a quarter into a character answers it and three quarters answers the next — in both margins");
		}
	}

	/* 4. **THE TWO EDGES**: below the last line, and left of a wrapped line. */
	{
		NSTextView *view = make_view(window, @"abcdef");
		NSUInteger length = [[view string] length];

		check([view characterIndexForInsertionAtPoint:NSMakePoint(5.0, (CGFloat)H - 1.0)] == 0,
		      "a point below the last line lands on that line at the character nearest its x, which is its start");
		check([view characterIndexForInsertionAtPoint:NSMakePoint((CGFloat)W - 5.0, (CGFloat)H - 1.0)] == length,
		      "and past that line's end it answers the end of the text, where a drop there belongs");
		check([view characterIndexForInsertionAtPoint:NSMakePoint(-40.0, 0.5)] == 0,
		      "and one left of the first line answers the beginning");

		/* THE WRAP: the same sentence at a width that breaks it in two, and the second line's start. */
		[view setString:@"aaaa bbbb cccc dddd"];
		[view setConstrainedFrameSize:NSMakeSize(70.0, (CGFloat)H)];
		{
			NSUInteger lines = [view cg_visualLineCount];
			NSRange second = [view cg_visualLineRangeAtIndex:(lines > 1) ? 1 : 0];

			check(lines > 1, "a narrow frame wraps the sentence");
			{
				NSTextView *probe = make_view(window, @"aaaa bbbb cccc dddd");

				[probe setConstrainedFrameSize:NSMakeSize(70.0, (CGFloat)H)];
				{
					NSRect start = [probe firstRectForCharacterRange:NSMakeRange(second.location, 0)];
					NSPoint left = NSMakePoint(start.origin.x - 6.0, start.origin.y + start.size.height / 2.0);

					check([probe characterIndexForInsertionAtPoint:point_in_view(probe, left)] == second.location,
					      "and a point just left of the second line answers THAT line's first character");
				}
			}
		}
	}

	/* 5. **THE CARET IS DRAWN THROUGH ITS DOOR, IN ITS COLOUR.** */
	{
		/* **THE STRING ENDS IN A SPACE AND THE CARET SITS AFTER IT**, so the caret's own columns carry no glyph ink at
		 * all — otherwise "there is no caret here" would be a claim about a column the letter `c` also occupies. */
		NSTextView *view = make_view(window, @"abc ");
		NSBitmapImageRep *none;
		NSRect caret;
		int column;

		[view setSelectedRange:NSMakeRange(4, 0)];
		caret = [view firstRectForCharacterRange:NSMakeRange(4, 0)];
		column = (int)floor((double)caret.origin.x);
		/* **THE NEGATIVE CONTROL NEEDS THE SESSION ENDED FIRST**, because installing a content view makes it the
		 * window's first responder — so "no caret" has to be asked of a view that has none, not assumed of a new one. */
		[view resignFirstResponder];
		none = draw_view(view);
		check(count_ink_in_columns(none, column) == 0,
		      "with no editing session there is no caret at the insertion point");
		[none release];

		ok = [view becomeFirstResponder];
		check(ok && [view shouldDrawInsertionPoint], "a view that became first responder wants a caret");
		{
			NSBitmapImageRep *plain = draw_view(view);
			NSBitmapImageRep *green;
			int ink;

			ink = count_ink_in_columns(plain, column);
			check(ink > 5, "and the caret is ink at the insertion point's own x");
			check(count_green(plain) == 0, "in the control text colour, not green");
			[plain release];

			[view setInsertionPointColor:[NSColor colorWithCalibratedRed:0.0 green:0.9 blue:0.0 alpha:1.0]];
			green = draw_view(view);
			check(count_green(green) > 5,
			      "`-setInsertionPointColor:` reaches the pixels — the caret is drawn in the colour the door answers");
			check(count_dark_in_column(green, column) == 0, "and the dark caret is gone, so the pen really changed");
			[green release];
		}
		[view resignFirstResponder];
		check(![view shouldDrawInsertionPoint],
		      "a view that resigned first responder wants none — the condition is the session, not the editability");
	}

	/* 6. **THE TWO DOORS A PIXEL CANNOT SHOW, WITH A RECORDING WITNESS.** */
	{
		AGRecordingView *view = [[AGRecordingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];
		NSRect asked = NSMakeRect(3.0, 5.0, 7.0, 9.0);
		NSBitmapImageRep *rep;

		[window setContentView:view];
		[view setFont:[NSFont systemFontOfSize:14.0]];
		[view setString:@"abc"];
		[view setSelectedRange:NSMakeRange(2, 0)];

		[view setNeedsDisplayInRect:asked avoidAdditionalLayout:YES];
		check(view->marks > 0 && NSEqualRects(view->lastMark, asked),
		      "`-setNeedsDisplayInRect:avoidAdditionalLayout:` marks the rect it was given");

		view->marks = 0;
		[view updateInsertionPointStateAndRestartTimer:YES];
		{
			NSRect caret = [view firstRectForCharacterRange:NSMakeRange(2, 0)];
			NSPoint corner = point_in_view(view, NSMakePoint(caret.origin.x, caret.origin.y));

			printf("  (note: the timer door marked %g,%g %gx%g; the caret is at %g,%g)\n",
			       (double)view->lastMark.origin.x, (double)view->lastMark.origin.y,
			       (double)view->lastMark.size.width, (double)view->lastMark.size.height,
			       (double)corner.x, (double)corner.y);
			check(view->marks > 0 && near_enough(view->lastMark.origin.x, corner.x)
			      && near_enough(view->lastMark.size.width, 1.0),
			      "and the insertion-point door dirties the CARET's own rect, which is what a blink would redraw");
		}

		/* THE BACKDROP: the subclass paints, and its ink is on the surface with the view's own fill OFF. */
		view->paintsBackdrop = YES;
		view->backdrops = 0;
		rep = draw_view(view);
		check(view->backdrops > 0, "`-drawRect:` asks `-drawViewBackgroundInRect:` before it draws anything else");
		{
			NSColor *corner = [rep colorAtX:W - 1 y:H - 1];

			check(corner != nil && [corner blueComponent] > 0.6 && [corner greenComponent] > 0.6,
			      "and the subclass's fill is the backdrop the surface got");
		}
		[rep release];
		[view release];
	}

	/* 7. **THE CONTAINER DOORS, FROM BOTH SIDES.** */
	{
		NSTextContainer *mine = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(40.0, 30.0)];
		NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 100.0)
						       textContainer:mine];
		NSTextContainer *other = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(100.0, 50.0)];
		NSArray *held;

		[window setContentView:view];
		[view setFont:[NSFont systemFontOfSize:14.0]];
		[view setDrawsBackground:NO];
		/* **AND THIS VIEW IS NOT EDITABLE, SO THE CARET IS NOT IN THE PICTURES BELOW** — it is a caret drawn from a
		 * container-less layout's zeroed x otherwise, which would read as "the text is still there". */
		[view setEditable:NO];
		[view setString:@"one two"];
		check([view textContainer] == mine, "the designated initialiser adopts the container it was handed");
		check([mine textView] == view, "and that container names the view back");
		held = [[view layoutManager] textContainers];
		check([held count] == 1 && [held objectAtIndex:0] == mine, "the manager lays out that one container, once");
		printf("  (note: the view is %g wide and its container %g)\n",
		       (double)[view frame].size.width, (double)[mine containerSize].width);
		check(near_enough([mine containerSize].width, [view frame].size.width),
		      "and the view's width reached it, because a wrapping view's container IS its width");

		[view setTextContainer:other];
		held = [[view layoutManager] textContainers];
		check([view textContainer] == other && [other textView] == view,
		      "`-setTextContainer:` moves the trio to the new container");
		check([mine textView] == nil, "the old container no longer names a view");
		check([held count] == 1 && [held objectAtIndex:0] == other, "and the manager lists the new one and not the old");
		check(near_enough([other containerSize].width, [view frame].size.width)
		      && near_enough([other containerSize].height, 0.0),
		      "and the adoption carried the frame's width into it, with an unbounded height");

		{
			NSTextContainer *third = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(60.0, 25.0)];

			[view replaceTextContainer:third];
			check([view textContainer] == third, "`-replaceTextContainer:` re-points the text system");
			check(near_enough([third containerSize].width, 60.0) && near_enough([third containerSize].height, 25.0),
			      "and does NOT size the container to the frame — that is the whole difference between the two doors");
			[third release];
		}

		/* AND `nil`: no container, no layout to ask, and a drawing pass that survives it. */
		[view setTextContainer:nil];
		check([view textContainer] == nil, "`-setTextContainer:nil` leaves the view with no container");
		check([view layoutManager] != nil, "and the manager is still there, with nothing to lay out");
		check([view characterIndexForInsertionAtPoint:NSMakePoint(5.0, 5.0)] == NSNotFound,
		      "which is the one case the insertion door answers NSNotFound rather than an index");
		{
			NSBitmapImageRep *rep = draw_view(view);

			check(leftmost_ink(rep, 0, H) < 0, "and a view with no container draws no text rather than crashing");
			[rep release];
		}
		{
			NSTextContainer *back = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200.0, 100.0)];

			[view setTextContainer:back];
			check([view textContainer] == back && [[view layoutManager] textContainers] != nil,
			      "and a container put back is laid out again");
			{
				NSBitmapImageRep *rep = draw_view(view);

				check(leftmost_ink(rep, 0, H) >= 0, "so the text comes back");
				[rep release];
			}
			[back release];
		}
		[mine release];
		[other release];
		[view release];
	}

	/* 8. **`-setConstrainedFrameSize:` IS A FLOOR, AND THE WIDTH STILL WRAPS.** */
	{
		NSTextView *view = make_view(window, @"one\ntwo\nthree");

		[view setVerticallyResizable:YES];
		[view setConstrainedFrameSize:NSMakeSize(300.0, 10.0)];
		printf("  (note: asked for 300x10 with three lines, got %gx%g)\n",
		       (double)[view frame].size.width, (double)[view frame].size.height);
		check([view frame].size.height > 10.0,
		      "a frame too short for its text is raised to the height the layout needs");
		[view setConstrainedFrameSize:NSMakeSize(300.0, 500.0)];
		check(near_enough([view frame].size.height, 500.0), "and a frame with room to spare is left alone");

		[view setVerticallyResizable:NO];
		[view setConstrainedFrameSize:NSMakeSize(300.0, 12.0)];
		check(near_enough([view frame].size.height, 12.0),
		      "a view that is NOT vertically resizable keeps the frame it was given — it was given one on purpose");

		/* THE WIDTH: the same text at 300 points and at 60. */
		[view setVerticallyResizable:YES];
		[view setString:@"aaaa bbbb cccc dddd eeee"];
		[view setConstrainedFrameSize:NSMakeSize(300.0, 400.0)];
		{
			NSUInteger wide = [view cg_visualLineCount];

			[view setConstrainedFrameSize:NSMakeSize(60.0, 400.0)];
			printf("  (note: 300 points is %lu line(s), 60 points is %lu)\n",
			       (unsigned long)wide, (unsigned long)[view cg_visualLineCount]);
			check(wide == 1 && [view cg_visualLineCount] > wide,
			      "and the width it was given decides the wrap");
		}
	}

	[window release];
	[pool release];
	printf("\n%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return (s_failed == 0) ? 0 : 1;
}
