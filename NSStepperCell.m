/*
 * NSStepperCell — the arrows, the step, and the pressed ink.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The press is the step; the release only clears the ink. The bezel and the two triangles are drawn here because a stepper
 * is one of the controls with no cell of a family beside it to inherit a face from — the button's bezel and the slider's
 * arrows are the two halves, and this file takes both from the platform's own colours.
 */
#import "NSStepperCell.h"
#import "NSColor.h"
#import "NSBezierPath.h"
#import "NSGraphicsContext.h"
#import "NSView.h"
#import "NSControl.h"

/* THE TWO ARROW HEIGHTS AS A FRACTION OF THE CELL, so a stepper drawn small still has two arrows and one drawn large does
 * not grow arrowheads the size of the box. */
#define AG_STEPPER_ARROW_INSET 3.0
#define AG_STEPPER_ARROW_WIDTH 5.0

@implementation NSStepperCell

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		/* **APPLE'S DOCUMENTED DEFAULTS.** A stepper that started at 0…0 with a step of 0 would be a control that cannot
		 * move, which is not what "make me a stepper" means. */
		_minValue = 0.0;
		_maxValue = 59.0;
		_increment = 1.0;
		_valueWraps = YES;
		_autorepeat = YES;
		_pressedSide = 0;
		_value = 0.0;
	}
	return self;
}

/* A CELL IS COPIED AS A VALUE, so the copy carries the four facts and the value; the pressed ink is a gesture's state and
 * is not copied. */
- (id)copy
{
	NSStepperCell *copy = [super copy];

	copy->_minValue = _minValue;
	copy->_maxValue = _maxValue;
	copy->_increment = _increment;
	copy->_valueWraps = _valueWraps;
	copy->_autorepeat = _autorepeat;
	copy->_value = _value;
	copy->_pressedSide = 0;
	return copy;
}

- (double)minValue
{
	return _minValue;
}

- (void)setMinValue:(double)aDouble
{
	_minValue = aDouble;
	if (_maxValue < _minValue) {
		_maxValue = _minValue;
	}
	[self setDoubleValue:[self doubleValue]];	/* re-clamped */
}

- (double)maxValue
{
	return _maxValue;
}

- (void)setMaxValue:(double)aDouble
{
	_maxValue = aDouble;
	if (_minValue > _maxValue) {
		_minValue = _maxValue;
	}
	[self setDoubleValue:[self doubleValue]];
}

- (double)increment
{
	return _increment;
}

- (void)setIncrement:(double)increment
{
	if (increment <= 0.0) {
		return;	/* a stepper with a zero step cannot move; see the header */
	}
	_increment = increment;
}

- (BOOL)valueWraps
{
	return _valueWraps;
}

- (void)setValueWraps:(BOOL)flag
{
	_valueWraps = flag ? YES : NO;
}

- (BOOL)autorepeat
{
	return _autorepeat;
}

- (void)setAutorepeat:(BOOL)flag
{
	_autorepeat = flag ? YES : NO;
}

/* **THE VALUE PAIR, OVERRIDDEN BECAUSE `NSCell`'s IS A TEXT CELL'S.** `NSCell -setDoubleValue:` answers only for an
 * `NSTextCellType` cell (see the ivar's note), so a stepper that inherited it would have arrows that change nothing. This
 * pair reads and writes the cell's own number, and the CLAMP lives in the setter — one place, which is what makes every
 * path into the value (the setters above and the step below) obey the range and the wrap. */
- (double)doubleValue
{
	return _value;
}

- (void)setDoubleValue:(double)aDouble
{
	if (aDouble > _maxValue) {
		aDouble = _valueWraps ? _minValue : _maxValue;
	} else if (aDouble < _minValue) {
		aDouble = _valueWraps ? _maxValue : _minValue;
	}
	_value = aDouble;
}

/* **THE STEP, WHICH IS THE PRESS.** The direction comes from the half the point landed in; the new value goes through the
 * clamp above; and if it actually moved, the action is sent. A stepper at its end that does not wrap sends nothing, which
 * is what a target should see — an action with no change is a click that did nothing. */
- (void)cg_stepBy:(double)direction inView:(NSView *)controlView
{
	double before = [self doubleValue];
	double after = before + direction * _increment;

	[self setDoubleValue:after];
	if ([self doubleValue] != before) {
		NSControl *control = (NSControl *)controlView;

		if ([control isKindOfClass:[NSControl class]]) {
			[control sendAction:[self action] to:[self target]];
		}
	}
}

- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	CGFloat midY = NSMidY([controlView bounds]);	/* the point arrives in the CONTROL's coordinates */
	BOOL flipped = [controlView isFlipped];
	NSInteger side;

	/* **"UP" IS A DIRECTION AND A FLIP REVERSES IT**, the trap the slider's ticks record: in a flipped view the upper
	 * arrow is the SMALLER y, and in an unflipped one it is the larger. */
	if (flipped) {
		side = (startPoint.y < midY) ? 1 : -1;
	} else {
		side = (startPoint.y > midY) ? 1 : -1;
	}
	_pressedSide = side;
	[self cg_stepBy:(double)side inView:controlView];
	[controlView setNeedsDisplay:YES];
	return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
	(void)lastPoint;
	(void)currentPoint;
	(void)controlView;
	/* A DRAG ACROSS A STEPPER DOES NOT STEP AGAIN: the value moved on the press, and repeating it on every point would
	 * turn one gesture into a dozen increments. The pressed ink is what a drag changes, and it keeps it. */
	return YES;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
	(void)lastPoint;
	(void)stopPoint;
	(void)flag;
	_pressedSide = 0;
	[controlView setNeedsDisplay:YES];
}

/* ---- THE INK ------------------------------------------------------------------------------------ */

/* A TRIANGLE, POINTING UP OR DOWN, inside the arrow's band. **"UP" IS A DIRECTION ON THE SCREEN, NOT A SIGN OF Y**: in a
 * flipped view the up arrow's apex is the band's SMALLER y, and in an unflipped one it is the larger. The first version
 * put the apex at `NSMaxY` in both and drew the two arrows INWARD — a stepper whose top arrow pointed down and whose bottom
 * arrow pointed up, which every press test passed because a press only reads the band, not the triangle. */
- (void)cg_drawArrowInRect:(NSRect)rect up:(BOOL)up pressed:(BOOL)pressed flipped:(BOOL)flipped
{
	CGFloat mid = NSMidX(rect);
	BOOL apexAtMax = up ? !flipped : flipped;
	CGFloat apex = apexAtMax ? NSMaxY(rect) : NSMinY(rect);
	CGFloat base = apexAtMax ? NSMinY(rect) : NSMaxY(rect);
	NSBezierPath *path = [NSBezierPath bezierPath];

	[path moveToPoint:NSMakePoint(mid, apex)];
	[path lineToPoint:NSMakePoint(mid - AG_STEPPER_ARROW_WIDTH / 2.0, base)];
	[path lineToPoint:NSMakePoint(mid + AG_STEPPER_ARROW_WIDTH / 2.0, base)];
	[path closePath];
	[(pressed ? [NSColor controlDarkShadowColor] : [NSColor controlTextColor]) setFill];
	[path fill];
}

/* **THE FACE IS THE PLATFORM'S CONTROL GREY WITH ONE THIN BORDER, and the two arrows sit in its halves.** A stepper is not
 * a button — it does not depress — so the pressed state is the ARROW's colour rather than the face's, which is what makes
 * a held stepper readable. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSRect faceRect = NSInsetRect(cellFrame, 0.5, 0.5);
	NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:faceRect xRadius:2.0 yRadius:2.0];
	NSRect upper = NSMakeRect(NSMinX(cellFrame), NSMidY(cellFrame), NSWidth(cellFrame), NSHeight(cellFrame) / 2.0);
	NSRect lower = NSMakeRect(NSMinX(cellFrame), NSMinY(cellFrame), NSWidth(cellFrame), NSHeight(cellFrame) / 2.0);
	BOOL flipped = (controlView != nil) ? [controlView isFlipped] : NO;
	/* THE UP ARROW IS THE ONE AT THE TOP OF THE SCREEN — the larger y unflipped, the smaller y flipped — and the tracking
	 * door above uses the same test, so the arrow a press steps is the arrow it hit. */
	NSRect upBand = NSInsetRect(flipped ? lower : upper, AG_STEPPER_ARROW_INSET, AG_STEPPER_ARROW_INSET);
	NSRect downBand = NSInsetRect(flipped ? upper : lower, AG_STEPPER_ARROW_INSET, AG_STEPPER_ARROW_INSET);

	[[NSColor controlColor] setFill];
	[face fill];
	[[NSColor controlShadowColor] setStroke];
	[face setLineWidth:1.0];
	[face stroke];
	/* THE DIVIDER BETWEEN THE ARROWS, so two triangles in one box read as two controls. */
	[[NSColor controlShadowColor] setFill];
	NSRectFill(NSMakeRect(NSMinX(cellFrame) + 1.0, NSMidY(cellFrame), NSWidth(cellFrame) - 2.0, 1.0));

	[self cg_drawArrowInRect:upBand up:YES pressed:(_pressedSide == 1) flipped:flipped];
	[self cg_drawArrowInRect:downBand up:NO pressed:(_pressedSide == -1) flipped:flipped];
}

@end
