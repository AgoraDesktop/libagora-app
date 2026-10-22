/*
 * NSScroller — the bar that says where a scroll view is looking.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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

- (void)setKnobProportion:(CGFloat)proportion
{
	/* THE VALUE THE BAR IS AT IS KEPT, because the proportion is the OTHER half of the pair: this door writes how much
	 * of the document is visible and leaves where the reader is. */
	[(NSScrollerCell *)[self cell] setFloatValue:[self floatValue] knobProportion:proportion];
	[self setNeedsDisplay:YES];
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

- (NSControlTint)controlTint
{
	return [(NSScrollerCell *)[self cell] controlTint];
}

- (void)setControlTint:(NSControlTint)tint
{
	[(NSScrollerCell *)[self cell] setControlTint:tint];
	[self setNeedsDisplay:YES];
}

/* ---- WHICH PARTS FIT, AND ALL OF THE INK AT ONCE -------------------------------------------------------- */

- (NSScrollerUsableParts)usableParts
{
	return [(NSScrollerCell *)[self cell] cg_usableParts];
}

- (void)checkSpaceForParts
{
	/* **THE ANSWER IS COMPUTED, SO THIS DOOR'S JOB IS THE REDISPLAY APPLE'S CACHED VERSION NEEDS AFTER IT CHANGES.**
	 * A caller that resized the bar asks this and the bar is drawn again from the frame it now has; see the header on
	 * why nothing here is remembered. */
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

- (void)drawParts
{
	/* THE SLOT, ITS ARROWS AND THE KNOB, IN THAT ORDER — which is `NSScrollerCell -drawWithFrame:inView:`'s order, so
	 * this is the forward rather than a second painting. */
	[(NSScrollerCell *)[self cell] drawWithFrame:[self bounds] inView:self];
}

/* ---- AND THE TWO TRACKING ENTRY POINTS --------------------------------------------------------------- */

/* **EACH IS A GATE IN FRONT OF THE ONE LOOP, NOT A LOOP OF ITS OWN.** Apple's scroller has its own tracking because its
 * cell does; this tier's `NSControl -mouseDown:` already runs the loop with the cell's three hooks, so the honest version
 * of these doors is "check the part this door is named for, then enter it" — which is also what makes them testable
 * and what keeps a press on the knob from being handled twice by two different loops.
 *
 * A PRESS THAT LANDED SOMEWHERE ELSE IS REFUSED SILENTLY: `-trackKnob:` with the pointer on a page is not a knob drag,
 * and acting on it would scroll a document the caller did not mean to touch. There is nothing to report, so nothing is
 * reported. */
- (void)trackKnob:(NSEvent *)theEvent
{
	NSPoint where = [self convertPoint:[theEvent locationInWindow] fromView:nil];

	if ([(NSScrollerCell *)[self cell] testPart:where] != NSScrollerKnob) {
		return;
	}
	[self mouseDown:theEvent];
}

- (void)trackScrollButtons:(NSEvent *)theEvent
{
	NSPoint where = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	NSScrollerPart part = [(NSScrollerCell *)[self cell] testPart:where];

	if (part != NSScrollerDecrementLine && part != NSScrollerIncrementLine) {
		return;
	}
	[self mouseDown:theEvent];
}

@end
