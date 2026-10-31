/*
 * tooltips — the region, the walk, and the plate: a tip is found by the pointer's position, and it is EARNED by waiting.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **WHAT THIS MEASURES, AND WHY IT IS TWO HALVES.** The first half is "which string is under this point?" — a walk of a
 * live view tree, which is where tool tips were a stored string nobody read. The second half is "does a plate appear?" —
 * the delay, the one tip at a time, and the three ways one goes away. Neither half is a drawing test: the plate's pixels
 * are the window's own, and what a test can honestly assert is that the ENGINE decided to show it, for which window, and
 * where.
 */
#import <AppKit/AppKit.h>
#import <AppKit/AGToolTipWindow.h>

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

/* **THE WINDOW'S DOOR, DECLARED HERE AS IT IS DECLARED IN `NSWindow.m`** — a `cg_` seam is the tier's own passage and
 * this probe is the tier. It is the door the pointer's motion actually calls, so it is the one worth measuring: the
 * engine's own `-showTip:…` is reachable too, but a test that started there would be asserting a decision nobody asked
 * for. */
@interface NSWindow (APPKITToolTips)
- (void)cg_updateToolTipAtPoint:(NSPoint)windowPoint;
- (NSString *)cg_toolTipStringAtWindowPoint:(NSPoint)windowPoint;
@end

@interface NSView (APPKITToolTips)
- (NSString *)cg_toolTipStringAtWindowPoint:(NSPoint)windowPoint;
@end

/* **AN OWNER THAT ANSWERS FOR A REGION, AND REMEMBERS WHAT IT WAS ASKED.** The point arrives in the VIEW's coordinates
 * and the caller's `-userData` comes back, so both are recorded: a door that handed over the window's point or dropped
 * the caller's pointer would answer a string and still be wrong. */
@interface TipOwner : NSObject
{
	NSString *_tip;
	NSPoint _point;
	void *_data;
	int _asks;
	BOOL _answers;
}
- (void)setTip:(NSString *)tip;
- (void)setAnswers:(BOOL)flag;
- (int)asks;
- (NSPoint)point;
- (void *)data;
@end

@implementation TipOwner

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_answers = YES;		/* an owner exists to answer; a test that wants a refusal says so */
	}
	return self;
}

- (void)setTip:(NSString *)tip
{
	NSString *copy = [tip copy];

	[_tip release];
	_tip = copy;
}

- (void)setAnswers:(BOOL)flag
{
	_answers = flag;
}

- (int)asks
{
	return _asks;
}

- (NSPoint)point
{
	return _point;
}

- (void *)data
{
	return _data;
}

- (void)dealloc
{
	[_tip release];
	[super dealloc];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data
{
	(void)view; (void)tag;
	_asks++;
	_point = point;
	_data = data;
	return _answers ? _tip : nil;
}

@end

/* **DRAW A VIEW INTO A BITMAP AND MEASURE WHERE ITS INK IS.** The plate's centring is a question about PIXELS — where
 * the words sit inside the box — and the only honest instrument for it is the ink they leave. Row 0 is the bitmap's
 * top here, so "the top margin" and "the bottom margin" are named from that end and compared with each other rather
 * than with a number somebody guessed. */
static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static void ink_rows(NSView *view, int width, int height, int *top, int *bottom)
{
	NSBitmapImageRep *rep = new_rep(width, height);
	NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	unsigned char *data;
	int x, y;

	*top = -1;
	*bottom = -1;
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:context];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)width, (CGFloat)height)] fill];
	[view displayRect:[view bounds]];
	[NSGraphicsContext restoreGraphicsState];
	data = [rep bitmapData];
	/* **THE PLATE'S OWN HAIRLINE IS INK TOO, SO IT IS OUTSIDE THE MEASUREMENT** — two points in from each edge is past
	 * the border and its rounding, and inside is the field the words are centred in. */
	for (y = 2; y < height - 2; y++) {
		for (x = 2; x < width - 2; x++) {
			unsigned char *p = data + ((size_t)y * (size_t)width + (size_t)x) * 4u;

			if (p[0] < 128) {
				if (*top < 0) {
					*top = y;
				}
				*bottom = y;
			}
		}
	}
	[rep release];
}

/* A POINT WELL OUTSIDE ANYTHING, for the "nothing here" cases. */
static const CGFloat kOutside = 100000.0;

/* **EVERY POINT BELOW IS NAMED IN THE VIEW IT IS INSIDE AND CONVERTED ON THE WAY OUT.** The window's doors take WINDOW
 * coordinates, and where the content view sits inside the window is the window's business — a title bar's worth of it,
 * in this tier — so a test that wrote window coordinates by hand would be asserting the chrome's height. */
static NSPoint in_window(NSView *view, CGFloat x, CGFloat y)
{
	return [view convertPoint:NSMakePoint(x, y) toView:nil];
}

int main(void)
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 400.0, 300.0)
						       styleMask:NSTitledWindowMask
							 backing:NSBackingStoreBuffered
							   defer:NO];
	/* **THE CONTENT VIEW IS MADE AND ADOPTED, NOT ASKED FOR**: this tier's `-contentView` answers the one the window
	 * has, and a window nobody has given one has none — which is the test's business to provide, since the offsets
	 * below are measured through it. */
	NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)] autorelease];
	NSView *left = [[[NSView alloc] initWithFrame:NSMakeRect(10.0, 10.0, 80.0, 60.0)] autorelease];
	NSView *right = [[[NSView alloc] initWithFrame:NSMakeRect(100.0, 10.0, 80.0, 60.0)] autorelease];
	NSView *inner = [[[NSView alloc] initWithFrame:NSMakeRect(5.0, 5.0, 30.0, 20.0)] autorelease];
	AGToolTipController *engine = [AGToolTipController sharedController];
	TipOwner *owner = [[[TipOwner alloc] init] autorelease];
	NSPoint plate;

	printf("tooltips: the region, the walk and the plate\n");

	[window setContentView:content];
	[content addSubview:left];
	[content addSubview:right];
	[left addSubview:inner];

	/* 1. **A VIEW'S OWN TIP IS ITS WHOLE BOUNDS.** `-setToolTip:` is the simple door, and a pointer inside the view is
	 * inside the tip: that is the meaning of the door, and it is the one Forge's segmented control relies on. */
	[left setToolTip:@"the left view"];
	check([[content cg_toolTipStringAtWindowPoint:in_window(left, 10.0, 10.0)] isEqualToString:@"the left view"] ||
	      [[left cg_toolTipStringAtWindowPoint:in_window(left, 10.0, 10.0)] isEqualToString:@"the left view"],
	      "a view's toolTip answers for a point inside it");
	{
		NSString *found = [left cg_toolTipStringAtWindowPoint:in_window(left, 10.0, 10.0)];

		check([found isEqualToString:@"the left view"], "and the view is the one that answers");
	}
	check([window cg_toolTipStringAtWindowPoint:NSMakePoint(kOutside, kOutside)] == nil,
	      "a point outside every view answers nothing");
	check([window cg_toolTipStringAtWindowPoint:in_window(right, 20.0, 10.0)] == nil,
	      "a NEIGHBOUR with no tip of its own does not inherit one");

	/* 2. **AND THE DEEPEST VIEW WITH A TIP WINS.** A control inside a box: the box's tip must not answer for the
	 * control, because the smaller thing is the more specific answer — this is the same rule a hit test follows. */
	[inner setToolTip:@"the inner view"];
	check([[window cg_toolTipStringAtWindowPoint:in_window(inner, 10.0, 10.0)] isEqualToString:@"the inner view"],
	      "the deepest view with a tip answers first");
	check([[window cg_toolTipStringAtWindowPoint:in_window(left, 50.0, 10.0)] isEqualToString:@"the left view"],
	      "and the ancestor answers where the child is not");
	[inner setToolTip:nil];
	check([[window cg_toolTipStringAtWindowPoint:in_window(inner, 10.0, 10.0)] isEqualToString:@"the left view"],
	      "a view that lets its tip go hands the question back to its ancestor");
	[left setToolTip:nil];

	/* 3. **A REGION IS A SMALLER THING THAN A VIEW, SO ITS OWNER IS THE MORE SPECIFIC ANSWER.** The region is half of
	 * the view; the point arrives in the VIEW's coordinates and the caller's own pointer comes back, which is what makes
	 * one owner able to serve several regions. */
	[owner setTip:@"the region"];
	{
		NSToolTipTag tag = [left addToolTipRect:NSMakeRect(0.0, 0.0, 40.0, 60.0) owner:owner userData:(void *)0x1234];

		check(tag > 0, "addToolTipRect: answers a tag");
		check([[window cg_toolTipStringAtWindowPoint:in_window(left, 5.0, 5.0)] isEqualToString:@"the region"],
		      "a region's owner answers for a point inside the region");
		check([owner asks] == 1, "and it was asked once");
		{
			/* THE POINT CROSSES TO THE VIEW'S OWN COORDINATES, which is the one conversion this door promises. */
			NSPoint p = [owner point];
			NSPoint expect = [left convertPoint:in_window(left, 5.0, 5.0) fromView:nil];

			check(fabs(p.x - expect.x) < 0.01 && fabs(p.y - expect.y) < 0.01,
			      "with the point in the VIEW's coordinates, not the window's");
		}
		check([owner data] == (void *)0x1234, "and the caller's userData came back");

		/* AND THE OTHER HALF OF THE VIEW IS THE VIEW'S OWN, WHICH IS WHERE THE TWO DOORS PART. */
		{
			int asks = [owner asks];

			(void)[window cg_toolTipStringAtWindowPoint:in_window(left, 60.0, 5.0)];
			check([owner asks] == asks, "outside the region the owner is not asked");
		}

		/* 4. **AN OWNER THAT DOES NOT IMPLEMENT THE DOOR DECLINES ITS REGION RATHER THAN CRASHING THE WALK** — or, in
		 * this case, one that implements it and answers nothing. A region with no answer is not a region with a tip. */
		[owner setAnswers:NO];
		check([window cg_toolTipStringAtWindowPoint:in_window(left, 5.0, 5.0)] == nil,
		      "an owner that answers nothing leaves the view with no tip");
		[owner setAnswers:YES];
		[left setToolTip:@"the left view"];
		check([[window cg_toolTipStringAtWindowPoint:in_window(left, 60.0, 5.0)] isEqualToString:@"the left view"],
		      "and the view's own toolTip answers outside the region");
		[left setToolTip:nil];

		/* 5. **AND THE REGION GOES WITH ITS TAG.** `-removeAllToolTips` is the blunt door; a stale region answering
		 * after a layout change is the bug it exists to prevent, and the toolbar re-registers through it. */
		[left removeAllToolTips];
		check([window cg_toolTipStringAtWindowPoint:in_window(left, 5.0, 5.0)] == nil,
		      "removeAllToolTips: takes the region with it");
	}

	/* 6. **THE ENGINE WAITS, AND THEN IT SHOWS THE TIP THE POINTER IS ON.** Before the delay nothing is on the screen —
	 * a plate that appeared on every crossing would flash across a band on the way somewhere else — and the answer
	 * after it is the same string the walk found. */
	[left setToolTip:@"the left view"];
	[window cg_updateToolTipAtPoint:in_window(left, 10.0, 10.0)];
	check(![engine isShowingTip], "a tip is NOT shown the instant the pointer arrives");
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
	check([engine isShowingTip], "and it is shown once the pointer has rested");

	/* 7. **A DIFFERENT TIP REPLACES THE OLD ONE, WAIT INCLUDED.** A plate showing one thing while the pointer rests on
	 * another is worse than no plate, so the old one goes at once and the new one is earned by its own wait. */
	[right setToolTip:@"the right view"];
	[window cg_updateToolTipAtPoint:in_window(right, 20.0, 10.0)];
	check(![engine isShowingTip], "moving to another control drops the old plate and starts the wait again");
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
	check([engine isShowingTip], "and the new one appears in its turn");

	/* 8. **AND A POINT WITH NOTHING UNDER IT TAKES THE PLATE AWAY, which is this engine's whole "exit" event: there is
	 * no exit message in the tier, and "the answer is now nothing" is the same fact. */
	[window cg_updateToolTipAtPoint:NSMakePoint(kOutside, kOutside)];
	check(![engine isShowingTip], "a pointer over nothing drops the plate");
	[window cg_updateToolTipAtPoint:in_window(right, 20.0, 10.0)];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
	check([engine isShowingTip], "and it comes back over the control");

	/* 9. **A TIP BELONGS TO ONE WINDOW, SO ONLY THAT WINDOW CAN TAKE IT AWAY.** A click in another window must not drop
	 * a plate that is still true, and a window that goes away must not leave its plate behind. */
	[engine hideTipForWindow:nil];	/* a nil window is "whatever is up": the blunt door */
	check(![engine isShowingTip], "hideTipForWindow:nil drops whatever is up");
	[window cg_updateToolTipAtPoint:in_window(right, 20.0, 10.0)];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
	check([engine isShowingTip], "the plate is back");
	[engine showTip:@"the left view" fromWindow:nil atScreenPoint:NSMakePoint(10.0, 10.0)];
	check(![engine isShowingTip], "a tip asked for with no window is not shown at all");

	/* 10. **THE SAME TIP ASKED TWICE IS THE SAME ANSWER, WHICH IS WHAT KEEPS THE DELAY MEANINGFUL.** A pointer resting
	 * on a control still moves a pixel at a time; a door that restarted its timer on every motion would never fire. */
	[engine hideTip];
	[window cg_updateToolTipAtPoint:in_window(right, 20.0, 10.0)];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
	[window cg_updateToolTipAtPoint:in_window(right, 21.0, 11.0)];	/* still the same control */
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
	check([engine isShowingTip], "a small move inside the same control does not restart the wait");

	/* 11. **AND THE PLATE HANGS BELOW-RIGHT OF THE POINTER, NOT OVER IT.** The offset is what keeps the tip from
	 * covering the thing it describes; the engine's own placement is the only place it is decided. */
	[engine hideTip];
	[window cg_updateToolTipAtPoint:in_window(right, 20.0, 10.0)];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
	{
		NSPoint at = [window convertBaseToScreen:in_window(right, 20.0, 10.0)];
		AGToolTipWindow *plateWindow = [engine cg_plateWindow];

		check(plateWindow != nil, "the plate is a window of its own");
		if (plateWindow != nil) {
			plate = [plateWindow frame].origin;
			check([[plateWindow tip] isEqualToString:@"the right view"], "and it carries the tip the pointer is on");
			check(plate.y + [plateWindow frame].size.height <= at.y,
			      "the plate's TOP is below the pointer, so it never covers what it describes");
		}
	}
	/* 12. **AND THE WORDS ARE CENTRED IN THE PLATE, WHICH IS WHAT "A BIT TOO LOW IN THE BOX" WAS.** `-drawAtPoint:` takes
	 * a BASELINE, so a plate whose text was placed by the bottom of its line box put the glyphs on the floor: MEASURED,
	 * the ink sat low by half a descent plus the leading. The ink's two margins are compared with each other, because the
	 * question is whether the words are centred, not what number a padding constant happens to be. */
	{
		AGToolTipWindow *probe = [[[AGToolTipWindow alloc] init] autorelease];
		NSSize plateSize;
		int top = -1, bottom = -1;

		[probe setTip:@"Export"];
		plateSize = [probe cg_plateSize];
		ink_rows([probe contentView], (int)plateSize.width, (int)plateSize.height, &top, &bottom);
		check(top >= 0 && bottom >= top, "the plate draws something");
		if (top >= 0 && bottom >= top) {
			int above = top - 2;
			int below = (int)plateSize.height - 3 - bottom;

			printf("  [diag] plate %gx%g, ink rows %d..%d, above %d below %d\n", (double)plateSize.width,
			       (double)plateSize.height, top, bottom, above, below);
			check(abs(above - below) <= 2, "and its ink is CENTRED between the plate's edges");
		}
	}

	[engine hideTip];
	check(![engine isShowingTip], "hideTip: drops the plate");

	[window close];
	printf(s_failed == 0 ? "tooltips: all checks passed\n" : "tooltips: FAILURES\n");
	return (s_failed == 0) ? 0 : 1;
}
