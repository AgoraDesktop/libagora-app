/*
 * NSScroller — the bar that says where a scroll view is looking.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE FILE IS THE CELL, THE FORWARDS, AND THE ONE VIEW FACT THAT MATTERS.** Every value, every part and every
 * stroke below belongs to the `NSScrollerCell` this control makes; what the VIEW adds is its frame, a default size
 * taken from the class metric, and `-isFlipped` — which is not a detail but the fact the whole geometry is written
 * against, since a scroller that counted y upward would put its decrement arrow, its pages and its knob all at the
 * wrong end.
 *
 * The tracking is `NSControl`'s loop with the cell's hooks, as it is for a slider, so there is no `-mouseDown:`
 * here and no second event loop: the cell's `-startTrackingAt:`/`-continueTracking:at:` do the knob arithmetic and
 * the control's loop pumps the events and sends the action.
 */
#import <AppKit/NSScroller.h>
#import <AppKit/NSScrollerCell.h>
#import <AppKit/NSEvent.h>

/* THE FRAME A FRESHLY MADE SCROLLER GETS, which is a VERTICAL one: 15 points of metric width by 100 of track. A
 * caller building a horizontal scroller gives it a wide, short frame, and the cell reads the orientation from that
 * frame rather than from a flag. */
#define NS_SCROLLER_DEFAULT_WIDTH	15.0
#define NS_SCROLLER_DEFAULT_HEIGHT	100.0

@implementation NSScroller

+ (CGFloat)scrollerWidth
{
	return [self scrollerWidthForControlSize:NSRegularControlSize];
}

/* **THE ONE METRIC A SCROLL VIEW LAYS ITSELF OUT AGAINST.** The regular width is 15 points and the smaller two are
 * 11 — the era's numbers, named here rather than guessed by whoever is doing the layout. */
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)controlSize
{
	switch (controlSize) {
	case NSSmallControlSize:
	case NSMiniControlSize:
		return 11.0;
	case NSRegularControlSize:
	default:
		return 15.0;
	}
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* THE CELL IS MADE HERE AND NOWHERE ELSE, so a scroller always has one — the same reason `NSSlider` makes
		 * its own. A scroller whose cell a caller forgot to set would have no value to report and no face to draw. */
		NSScrollerCell *cell = [[NSScrollerCell alloc] init];

		[cell setEnabled:YES];
		[self setCell:cell];
		[cell release];
		if (frameRect.size.width <= 0.0 || frameRect.size.height <= 0.0) {
			[self setFrameSize:NSMakeSize(NS_SCROLLER_DEFAULT_WIDTH, NS_SCROLLER_DEFAULT_HEIGHT)];
		}
	}
	return self;
}

/* **A SCROLLER IS FLIPPED, AND THE GEOMETRY DEPENDS ON IT.** Counting y downward puts the decrement end at the TOP of
 * a vertical scroller and the LEFT of a horizontal one — which is where a person expects the arrow that goes back to
 * the beginning. `NSScrollerCell` is written in these coordinates, so this is the one line that makes them true. */
- (BOOL)isFlipped
{
	return YES;
}

/* ---- THE VALUE PAIR, FORWARDED --------------------------------------------------------------------------- */

- (void)setFloatValue:(CGFloat)value knobProportion:(CGFloat)proportion
{
	[(NSScrollerCell *)[self cell] setFloatValue:value knobProportion:proportion];
	[self setNeedsDisplay:YES];
}

- (CGFloat)floatValue
{
	return [(NSScrollerCell *)[self cell] floatValue];
}

- (CGFloat)knobProportion
{
	return [(NSScrollerCell *)[self cell] knobProportion];
}

/* ---- THE PARTS, FORWARDED -------------------------------------------------------------------------------- */

- (NSScrollerPart)hitPart
{
	return [(NSScrollerCell *)[self cell] hitPart];
}

- (NSScrollerPart)testPart:(NSPoint)point
{
	return [(NSScrollerCell *)[self cell] testPart:point];
}

- (NSRect)rectForPart:(NSScrollerPart)part
{
	return [(NSScrollerCell *)[self cell] rectForPart:part];
}

/* ---- THE ARROWS, THE SIZE, AND THE INK ------------------------------------------------------------------- */

- (NSScrollArrowPosition)arrowsPosition
{
	return [(NSScrollerCell *)[self cell] arrowsPosition];
}

- (void)setArrowsPosition:(NSScrollArrowPosition)where
{
	[(NSScrollerCell *)[self cell] setArrowsPosition:where];
	[self setNeedsDisplay:YES];
}

- (NSControlSize)controlSize
{
	return [(NSScrollerCell *)[self cell] controlSize];
}

- (void)setControlSize:(NSControlSize)size
{
	[(NSScrollerCell *)[self cell] setControlSize:size];
	[self setNeedsDisplay:YES];
}

- (void)drawArrow:(NSScrollerArrow)whichArrow highlight:(BOOL)flag
{
	[(NSScrollerCell *)[self cell] drawArrow:whichArrow highlight:flag];
}

- (void)drawKnob
{
	[(NSScrollerCell *)[self cell] drawKnob];
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
	[(NSScrollerCell *)[self cell] drawKnobSlotInRect:slotRect highlight:flag];
}

- (void)highlight:(BOOL)flag
{
	[(NSScrollerCell *)[self cell] setHighlighted:flag];
	[self setNeedsDisplay:YES];
}

@end
