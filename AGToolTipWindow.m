/*
 * AGToolTipWindow.m — the plate, one line of text on it, and the delay that decides when it is earned.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import "AGToolTipWindow.h"
#import <AppKit/AGChromeTheme.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/NSTimer.h>

/* **THE AIR INSIDE THE PLATE, AND THE ONE NUMBER THE WAIT IS.** Five points either side and three above and below is what
 * makes one line of 11-point text read as a plate rather than a crop of itself. The delay is the era's own
 * `NSInitialToolTipDelay`, and it is a SECOND rather than a few hundred milliseconds because a tip is an answer to
 * "what is this?" — the question a person asks with their hand still. */
static const CGFloat AGToolTipPaddingX = 5.0;
static const CGFloat AGToolTipPaddingY = 3.0;
static const CGFloat AGToolTipCornerRadius = 4.0;
static const NSTimeInterval AGToolTipDelay = 1.0;

/* **AND WHERE IT HANGS FROM THE POINTER: DOWN AND TO THE RIGHT, BY THE AMOUNT A CURSOR IS TALL.** A plate under the
 * pointer's own hotspot would cover the control it describes; this clears the arrow with room to spare. */
static const CGFloat AGToolTipGap = 8.0;

static NSFont *fn_tip_font(void)
{
	return [NSFont toolTipsFontOfSize:[NSFont smallSystemFontSize]];
}

static NSDictionary *fn_tip_attributes(void)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:fn_tip_font(), NSFontAttributeName,
						  [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
}

/* ============================================================================================ *
 * THE PLATE'S VIEW.  A plate is a ground, a hairline and a line of text, which is all the candidate
 * window's panel is too — the same two colours, so the two small panels on this desktop match.
 * ============================================================================================ */

@interface AGToolTipView : NSView
{
	NSString *_tip;			/* RETAINED (a copy) */
}
- (void)setTip:(NSString *)tip;
- (NSString *)tip;
@end

@implementation AGToolTipView

- (void)dealloc
{
	[_tip release];
	[super dealloc];
}

- (void)setTip:(NSString *)tip
{
	NSString *copy = [tip copy];

	[_tip release];
	_tip = copy;
	[self setNeedsDisplay:YES];
}

- (NSString *)tip
{
	return _tip;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 0.5, 0.5)
							      xRadius:AGToolTipCornerRadius
							       yRadius:AGToolTipCornerRadius];
	NSDictionary *attrs = fn_tip_attributes();
	NSSize size = [(_tip != nil ? _tip : @"") sizeWithAttributes:attrs];

	(void)dirtyRect;
	[[NSColor windowBackgroundColor] setFill];
	[shape fill];
	[[NSColor darkGrayColor] setStroke];
	[shape stroke];
	if (_tip != nil && [_tip length] > 0) {
		/* **THE GLYPHS ARE CENTRED IN THE PLATE, WHICH IS NOT THE SAME AS CENTRING THE LINE BOX.** `-drawAtPoint:`
		 * takes a BASELINE (Core Text's `CGContextSetTextPosition`), so a box centred by its own height leaves the
		 * words sitting on the plate's floor — MEASURED, "a bit too low in the box". The box to centre is the
		 * ascender-to-descender one, and the baseline is that box's bottom: the same arithmetic the toolbar's own label
		 * painter does, for the same reason a shared rule is worth having twice. */
		NSFont *font = fn_tip_font();
		CGFloat ascent = [font ascender];
		CGFloat descent = (CGFloat)fabs((double)[font descender]);
		CGFloat baseline = (bounds.size.height - (ascent + descent)) / 2.0 + descent;

		[_tip drawAtPoint:NSMakePoint((bounds.size.width - size.width) / 2.0, baseline) withAttributes:attrs];
	}
}

@end

/* ============================================================================================ *
 * THE WINDOW.  Borderless, floating, not activatable — a tip is furniture, not a place to type.
 * ============================================================================================ */

@implementation AGToolTipWindow

- (instancetype)init
{
	AGToolTipView *view = [[AGToolTipView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

	self = [super initWithContentRect:NSMakeRect(0.0, 0.0, 10.0, 10.0) styleMask:NSBorderlessWindowMask
				  backing:NSBackingStoreBuffered defer:NO];
	if (self != nil) {
		[self setContentView:view];
		/* **ABOVE EVERY ORDINARY WINDOW, AND BELOW THE MENUS**, which is where a tip belongs: a menu that opens over a
		 * tip hides it, and a tip over an ordinary window is still readable. The two flags below are what the menu
		 * panel and the candidate window both say — the keyboard is not this window's, and nothing here is clicked. */
		[self setLevel:NSStatusWindowLevel];
		[self cg_setActivatable:NO];
	}
	[view release];		/* the window's content view is retained by it */
	return self;
}

- (void)setTip:(NSString *)tip
{
	[(AGToolTipView *)[self contentView] setTip:tip];
	[self setContentSize:[self cg_plateSize]];
}

- (NSString *)tip
{
	return [(AGToolTipView *)[self contentView] tip];
}

/* **THE PLATE'S SIZE IS THE TEXT'S PLUS THE AIR, AND IT IS THE ONLY MEASUREMENT IN THIS FILE.** A tip is one line, so
 * there is no wrapping and no maximum: the string is the caller's, and a long one makes a long plate rather than a
 * clipped sentence. */
- (NSSize)cg_plateSize
{
	NSString *tip = [self tip];
	NSSize size = [(tip != nil ? tip : @"") sizeWithAttributes:fn_tip_attributes()];

	return NSMakeSize(ceil(size.width) + 2.0 * AGToolTipPaddingX, ceil(size.height) + 2.0 * AGToolTipPaddingY);
}

@end

/* ============================================================================================ *
 * THE ENGINE.                                                                                    *
 *                                                                                                *
 * **THE STATE IS THE TIP AND WHOSE IT IS, AND THAT IS WHAT MAKES `-showTip:…` IDEMPOTENT.** Every
 * motion over the same control calls the same door with the same string; a door that restarted its
 * timer on each call would never fire while the pointer was moving a little, and a door that opened
 * a new plate would flash. So the same (window, string) is a no-op, and the point is merely kept up
 * to date — the plate then appears where the pointer came to REST, not where it first arrived.
 * ============================================================================================ */

@interface AGToolTipController ()
- (void)fn_show:(NSTimer *)timer;
@end

@implementation AGToolTipController
{
	AGToolTipWindow *_plate;	/* RETAINED, made on first use */
	NSTimer *_timer;		/* RETAINED by the run loop while pending */
	NSWindow *_owner;		/* NOT RETAINED: a back-reference to the window the tip belongs to */
	NSString *_tip;			/* RETAINED (a copy): the tip the engine is holding, shown or pending */
	NSPoint _point;			/* where the pointer was when it was last asked, in SCREEN coordinates */
	BOOL _showing;
}

+ (AGToolTipController *)sharedController
{
	static AGToolTipController *shared = nil;

	if (shared == nil) {
		shared = [[AGToolTipController alloc] init];
	}
	return shared;
}

- (void)dealloc
{
	[_timer invalidate];
	[_plate release];
	[_tip release];
	[super dealloc];
}

- (void)showTip:(NSString *)tip fromWindow:(NSWindow *)window atScreenPoint:(NSPoint)point
{
	_point = point;
	if (tip == nil || [tip length] == 0) {
		[self hideTip];
		return;
	}
	/* **THE SAME TIP IN THE SAME WINDOW IS THE SAME ANSWER**, whether it is already up or still waiting: keep the timer
	 * that is running and only remember where the pointer is now. */
	if (_owner == window && _tip != nil && [_tip isEqualToString:tip]) {
		if (_showing && _plate != nil) {
			[self fn_placePlate];
		}
		return;
	}
	/* A DIFFERENT TIP REPLACES THE OLD ONE AT ONCE — a plate showing one thing while the pointer rests on another is
	 * worse than no plate at all — and the new one is earned by its own wait. */
	[self hideTip];
	_owner = window;
	_tip = [tip copy];
	_timer = [NSTimer scheduledTimerWithTimeInterval:AGToolTipDelay target:self selector:@selector(fn_show:)
					       userInfo:nil repeats:NO];
}

- (void)hideTip
{
	[_timer invalidate];
	_timer = nil;
	[_tip release];
	_tip = nil;
	_owner = nil;
	if (_showing) {
		[_plate orderOut:nil];
		_showing = NO;
	}
}

- (void)hideTipForWindow:(NSWindow *)window
{
	if (window == nil || window == _owner) {
		[self hideTip];
	}
}

- (BOOL)isShowingTip
{
	return _showing;
}

- (AGToolTipWindow *)cg_plateWindow
{
	return _plate;
}

/* **THE WAIT IS OVER, SO THE PLATE IS BUILT (once) AND PLACED (every time).** A tip is shown whether or not the window
 * it belongs to is key — a control in a background window still wants explaining — but it is NOT shown for a window
 * that has gone away, which is the one case where the plate would hang over nothing. */
- (void)fn_show:(NSTimer *)timer
{
	(void)timer;
	_timer = nil;
	if (_tip == nil || _owner == nil) {
		[self hideTip];
		return;
	}
	if (_plate == nil) {
		_plate = [[AGToolTipWindow alloc] init];
	}
	[_plate setTip:_tip];
	[self fn_placePlate];
	if (!_showing) {
		[_plate orderFrontRegardless];
		_showing = YES;
	}
}

/* **THE PLACEMENT, CLAMPED TO THE SCREEN THE POINTER IS ON.** The plate hangs below and to the right of the pointer; at
 * the edge of a screen that would put it off the glass, so it flips to the other side of the pointer rather than being
 * drawn half of it. `-visibleFrame` is the screen minus the bar and the Dock, which is where a tip may be. */
- (void)fn_placePlate
{
	NSSize size;
	NSRect visible;
	NSPoint origin;

	if (_plate == nil) {
		return;
	}
	size = [_plate cg_plateSize];
	visible = [[NSScreen mainScreen] visibleFrame];
	origin = NSMakePoint(_point.x + AGToolTipGap, _point.y - size.height - AGToolTipGap);
	if (visible.size.width > 0.0 && origin.x + size.width > NSMaxX(visible)) {
		origin.x = _point.x - size.width - AGToolTipGap;
	}
	if (visible.size.height > 0.0 && origin.y < NSMinY(visible)) {
		origin.y = _point.y + AGToolTipGap;
	}
	if (visible.size.width > 0.0 && origin.x < NSMinX(visible)) {
		origin.x = NSMinX(visible);
	}
	[_plate setContentSize:size];
	[_plate setFrameOrigin:origin];
}

@end
