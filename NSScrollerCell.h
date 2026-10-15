/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSScrollerCell.h — the cell that turns a fraction into a knob and a point into a part.
 *
 * **THE CELL OWNS THE TWO ARITHMETICS A SCROLLER IS.** The first is the VALUE pair — `-floatValue` in [0, 1] and
 * `-knobProportion`, the fraction of the track the knob fills — and the geometry that places the knob from them. The
 * second is the PARTS: `-testPart:` says which place a point is in and `-rectForPart:` says where a place is, and
 * the two must agree, because a press is routed by the first and a knob is drawn by the second.
 *
 * **AND ORIGIN IS A DECISION, NOT A DEFAULT.** Apple's scroller is a FLIPPED view: it counts y downward, so the
 * DECREMENT end — the smaller values — is the TOP of a vertical scroller and the LEFT of a horizontal one. This cell
 * is written in those coordinates directly, so the arrows point up and left for the decrement a reader expects, and
 * `NSScroller` overrides `-isFlipped` to say YES. A caller that draws this cell into an unflipped context gets the
 * geometry upside down, which is why that fact is stated here rather than left to be found.
 *
 * **THE KNOB HAS A MINIMUM LENGTH, AND IT IS A REAL DECISION.** `-knobProportion` can be any small fraction — one
 * row of a huge file — and a knob proportional to it would be too short to see, let alone grab. The cell therefore
 * never draws a knob shorter than the scroller is THICK (a square), which is the same floor Apple's own scroller
 * keeps and the reason a tiny document still has something to hold. When the slot is shorter than that floor the
 * knob simply fills the slot.
 */
#ifndef APPKIT_NSSCROLLERCELL_H
#define APPKIT_NSSCROLLERCELL_H

#import <AppKit/NSActionCell.h>
#import <AppKit/NSScroller.h>
#import <Foundation/NSDate.h>	/* NSTimeInterval, which the repeat's deadline is measured in */

NS_ASSUME_NONNULL_BEGIN

@interface NSScrollerCell : NSActionCell
{
	/* THE VALUE PAIR. Both live in [0, 1]; the clamp is at the setter below so nothing else has to repeat it. */
	CGFloat _floatValue;
	CGFloat _knobProportion;
	/* WHERE THE LAST TRACKING PASS LANDED, which is what an action reads through `-hitPart`. */
	NSScrollerPart _hitPart;
	/* **WHERE THE KNOB WAS GRABBED, SO A DRAG MOVES IT BY THE HAND'S OWN DELTA.** A scroller's knob does not jump so
	 * its centre lands under the pointer — a hand that has hold of a knob keeps hold of the same POINT on it — so the
	 * press remembers the point's offset from the knob's near edge and every later point subtracts it back out. */
	CGFloat _grabDelta;
	NSScrollArrowPosition _arrowsPosition;
	/* **THE FRAME THE GEOMETRY IS ANSWERED AGAINST WHEN NO VIEW IS SET.** `-rectForPart:` has no frame argument
	 * (Apple's signature), so it asks its control view for its bounds — and a cell with no view (a measurement, an
	 * offscreen probe) keeps the last frame it was drawn into instead. */
	NSRect _lastFrame;
	/* **WHEN A HELD PAGE OR LINE SPEAKS AGAIN.** Zero means "nothing is repeating"; a value is the reference-date
	 * time at which the next repeat is due. Armed by `-startTrackingAt:` for a part that STEPS and cleared by the
	 * release, so the loop's poll does nothing once the button is up. */
	NSTimeInterval _repeatDeadline;
}

- (void)setFloatValue:(CGFloat)value knobProportion:(CGFloat)proportion;
- (CGFloat)floatValue;
- (CGFloat)knobProportion;

- (NSScrollerPart)hitPart;
- (NSScrollerPart)testPart:(NSPoint)point;
- (NSRect)rectForPart:(NSScrollerPart)part;

- (NSScrollArrowPosition)arrowsPosition;
- (void)setArrowsPosition:(NSScrollArrowPosition)where;

/* **THE REPEAT, WHICH IS THE CELL'S CLOCK RATHER THAN THE LOOP'S.** `-cg_trackingShouldRepeat` is what
 * `NSControl -mouseDown:` polls when nothing has arrived: the cell answers YES when a held PAGE or LINE is due to
 * step again, and NO for everything else. The timing is the cell's own (a delay before the first repeat, an interval
 * after), and `-cg_trackingShouldRepeatAtTime:` is the same question with the clock SUPPLIED — which is how the
 * delay and the interval can be tested without waiting for them. */
- (BOOL)cg_trackingShouldRepeat;
- (BOOL)cg_trackingShouldRepeatAtTime:(NSTimeInterval)now;

- (void)drawArrow:(NSScrollerArrow)whichArrow highlight:(BOOL)flag;
- (void)drawKnob;
- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag;
- (void)drawWithFrame:(NSRect)cellFrame inView:(nullable NSView *)controlView;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSCROLLERCELL_H */
