/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScroller.h — the bar that says where a scroll view is looking (stage E/F).
 *
 * **A SCROLLER IS A CONTROL WHOSE VALUE IS A FRACTION AND WHOSE PARTS ARE PLACES.** `-floatValue` is where the knob
 * sits in [0, 1] and `-knobProportion` is how much of the track it fills — the visible fraction of the document —
 * and the two are all `-setFloatValue:knobProportion:` takes. The PARTS are the other half: `-testPart:` turns a
 * point into `NSScrollerKnob`, a page, a line or the bare slot, and `-rectForPart:` turns a part back into its
 * rectangle. A caller that has those two does not need to know how the face is shaped; a caller that has the value
 * pair does not need to know where the knob was put.
 *
 * **WHAT TRACKS THE POINTER IS `NSControl`'S LOOP, AS IT IS FOR A SLIDER.** Apple's `NSScroller` has its own
 * `-trackKnob:` and `-trackScrollButtons:` because its cell has its own tracking; this tier's `NSControl -mouseDown:`
 * already runs the one tracking loop with the cell's three hooks, and `NSScrollerCell` answers them — so the knob
 * drags and a click on a page reports its part through the SAME loop every other control here uses. **THE TWO APPLE
 * DOORS ARE STILL HERE, AND THEY ARE THE ENTRY TO THAT LOOP**: `-trackKnob:` runs it for a press that landed on the
 * knob and `-trackScrollButtons:` for one that landed on a line button, each refusing a press that began anywhere else
 * — which is what the names mean and what makes them worth declaring rather than aliasing both to `-mouseDown:`.
 *
 * **AND A SCROLLER DOES NOT SCROLL ANYTHING BY ITSELF.** It is a control: it reports `-hitPart` and its value pair
 * and sends its action, and the `NSScrollView` that owns it reads those and moves the clip view. That split is what
 * lets this class be tested with no document anywhere near it.
 *
 * The enums and the doors are the 10.6 header read for the era's members. `NSScrollerStyle` and the overlay look are
 * 10.7 and are STRUCK: this tree pins the era, and an overlay scroller is a whole different face.
 */
#ifndef APPKIT_NSSCROLLER_H
#define APPKIT_NSSCROLLER_H

#import <AppKit/NSControl.h>

NS_ASSUME_NONNULL_BEGIN

/* WHERE A POINT IS ON A SCROLLER. `NSScrollerNoPart` is not a place and is why the first member is 0: a point off
 * the scroller answers none rather than being bumped into the nearest part. */
typedef enum {
	NSScrollerNoPart = 0,
	NSScrollerDecrementPage = 1,
	NSScrollerKnob = 2,
	NSScrollerIncrementPage = 3,
	NSScrollerDecrementLine = 4,
	NSScrollerIncrementLine = 5,
	NSScrollerKnobSlot = 6
} NSScrollerPart;

/* WHICH ARROW, FOR `-drawArrow:highlight:`. The increment arrow points the way the value grows — down or right. */
typedef enum {
	NSScrollerIncrementArrow = 0,
	NSScrollerDecrementArrow = 1
} NSScrollerArrow;

/* WHERE THE LINE-STEPPING ARROWS SIT. `-ArrowsNone` leaves the whole frame to the knob, which is the one value that
 * changes the geometry rather than the ink; `-ArrowsDefaultSetting` is Apple's own alias for `-ArrowsMaxEnd`. */
typedef enum {
	NSScrollerArrowsMaxEnd = 0,
	NSScrollerArrowsMinEnd = 1,
	NSScrollerArrowsNone = 2,
	NSScrollerArrowsDefaultSetting = NSScrollerArrowsMaxEnd
} NSScrollArrowPosition;

/* **WHICH OF THE BAR'S PARTS THERE IS ROOM TO DRAW, WHICH IS A QUESTION ABOUT THE FRAME RATHER THAN ABOUT THE INK.**
 * `NSScrollerUsableParts` is the era's enum and its four members are the four things a bar of shrinking length can be
 * reduced to: both buttons and the track, only the buttons, only the knob, or only the knob's slot. The two `…Only`
 * spellings are FORCED by `NSScrollerPart` above already owning `NSScrollerKnob` and `NSScrollerKnobSlot` — C
 * enumerators share one scope — and the numbers are the era's.
 *
 * **THE ANSWER IS COMPUTED FROM THE FRAME EVERY TIME IT IS ASKED**, which is why `-checkSpaceForParts` here is a
 * redisplay rather than a cache: a scroller that remembered a stale answer from a frame it no longer has would draw
 * parts that do not fit, and a caller resizing a window is exactly the case that would find it. Apple caches because a
 * scroller there is a cell with a fixed frame; this tier's geometry always reads the live bounds. */
typedef enum {
	NSScrollerArrowsOnly = 0,
	NSScrollerKnobOnly = 1,
	NSScrollerKnobSlotOnly = 2,
	NSScrollerAllParts = 3
} NSScrollerUsableParts;

@class NSEvent;

@interface NSScroller : NSControl

/* **THE TWO CLASS DOORS THAT ANSWER HOW THICK A SCROLLER IS.** The width is the metric a scroll view lays itself out
 * against, and it is a property of the CONTROL SIZE rather than of the instance — which is why it is a class door on
 * Apple's header and why the default frame a fresh scroller gets is taken from it. */
+ (CGFloat)scrollerWidth;
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)controlSize;

- (instancetype)initWithFrame:(NSRect)frameRect;

/* **THE VALUE PAIR, WHICH IS THE WHOLE OF A SCROLLER'S STATE.** `-setFloatValue:knobProportion:` is the only setter
 * because the two numbers are one fact — where the view is looking and how much of the document it can see — and
 * setting them apart is how a knob comes to disagree with the document it stands for. Both are clamped to [0, 1]. */
- (void)setFloatValue:(CGFloat)value knobProportion:(CGFloat)proportion;
- (CGFloat)floatValue;
- (CGFloat)knobProportion;
/* **AND THE PROPORTION ALONE, WHICH IS THE SETTER THE PAIR ABOVE HAS NEVER HAD.** It keeps the current `-floatValue`
 * rather than resetting it, because that is the only reading under which it is not the pair door under a shorter name:
 * a caller that has measured a new visible fraction writes the fraction and leaves the place where the reader is. */
- (void)setKnobProportion:(CGFloat)proportion;

/* **AND WHICH PARTS THE BAR HAS ROOM FOR.** `-usableParts` answers the enum, computed from the live frame and
 * `-arrowsPosition`; `-checkSpaceForParts` is the era's "look again" door, which here recomputes and redraws. Its
 * answer is a real reduction of the geometry: with only the arrows usable the line buttons occupy the frame and there
 * is no slot, and with only the knob usable the arrows are gone and the knob takes the whole track. */
- (NSScrollerUsableParts)usableParts;
- (void)checkSpaceForParts;

/* **AND THE PARTS.** `-hitPart` is what the LAST tracking pass landed on, which is what an action reads; `-testPart:`
 * is the same question about a point the caller supplies; and `-rectForPart:` is the geometry both are built on. */
- (NSScrollerPart)hitPart;
- (NSScrollerPart)testPart:(NSPoint)point;
- (NSRect)rectForPart:(NSScrollerPart)part;

/* WHERE THE ARROWS ARE, AND WHICH SIZE THIS SCROLLER WEARS. Both are the cell's, forwarded for the reason every
 * control here forwards: the face and its geometry are one object, and it is not the view. */
- (NSScrollArrowPosition)arrowsPosition;
- (void)setArrowsPosition:(NSScrollArrowPosition)where;
- (NSControlSize)controlSize;
- (void)setControlSize:(NSControlSize)size;
/* **AND THE TINT, WHICH IS THE CELL'S AND IS DRAWN.** The knob is the one piece of a scroller with a surface of its own,
 * so the tint is what colours it: the DEFAULT leaves the sample's white knob alone, and asking for blue or graphite asks
 * the knob to wear that colour instead. */
- (NSControlTint)controlTint;
- (void)setControlTint:(NSControlTint)tint;

/* **AND THE INK, ONE PIECE AT A TIME.** `-drawKnob` draws the knob where the value says it is, `-drawKnobSlotInRect:`
 * draws the groove and its arrows, and `-drawArrow:highlight:` draws one arrow — which is the split a subclass needs
 * to change one piece without redrawing the others. */
- (void)drawArrow:(NSScrollerArrow)whichArrow highlight:(BOOL)flag;
- (void)drawKnob;
- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag;
/* **AND ALL OF IT AT ONCE**, which is Apple's door for a caller that wants the bar redrawn without knowing which pieces
 * `-usableParts` has left it: the slot, its arrows and the knob, in that order. */
- (void)drawParts;

/* **AND THE TWO TRACKING ENTRY POINTS, WHICH ARE THIS CLASS'S SPELLING OF `NSControl`'S ONE LOOP.** Each takes the
 * mouse-down event that started the press, refuses it if it did not land on the part it names, and otherwise runs the
 * loop — so `-trackKnob:` with a press on the knob drags it, and with a press anywhere else does nothing at all. */
- (void)trackKnob:(NSEvent *)theEvent;
- (void)trackScrollButtons:(NSEvent *)theEvent;

/* AND WHETHER THE KNOB READS AS PRESSED. This is the control's flag; what it changes is the knob's ink. */
- (void)highlight:(BOOL)flag;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSCROLLER_H */
