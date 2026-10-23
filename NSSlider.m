/*
 * NSSlider — a control whose value is a position.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE WHOLE FILE IS THE CELL, THE FORWARDS, AND ONE VIEW DOOR.** That is not a small class making excuses: a
 * control's design is that the CELL owns what is drawn and what the value is, and a slider is the control where that
 * split is most visible — the range, the value, the geometry and the ink are all questions about a NUMBER and a
 * RECTANGLE, and both of those are the cell's. What is left for the view is its frame, its window, and whether a
 * click that is not the first responder's should still land.
 */
#import <AppKit/NSSlider.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSImage.h>

/* THE FRAME A FRESHLY MADE SLIDER GETS, named rather than repeated: Apple's slider is a long thin control, and a
 * caller who wants another size sets it — this is the DEFAULT and not a constraint. The height is the knob's plus two
 * points of breathing room, which is what keeps `-knobRect:flipped:` from being clipped by its own frame. */
#define NS_SLIDER_DEFAULT_WIDTH		96.0
#define NS_SLIDER_DEFAULT_HEIGHT	20.0

@implementation NSSlider

/* ============================================================================================
 * ARCHIVING: NOTHING OF ITS OWN: ITS RANGE, VALUE AND TICKS ARE ITS CELL'S, SO THE CONTROL ITSELF HAS NOTHING TO ADD.
 * ============================================================================================ */
/* Its range, value and ticks are its CELL's, so the control itself has nothing to add. A class with no instance storage can inherit both coding methods — `class_getInstanceSize` is what
 * says so, and `NSNib`'s census accepts exactly that case. The conformance is declared so the allow-list's
 * `-conformsToProtocol:` question answers YES. */
+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* **THE CELL IS MADE HERE AND NOWHERE ELSE**, so that a slider always has one: `NSControl` treats a nil cell
		 * as "a control that draws nothing and does nothing", which is a real state for a control a caller built
		 * bare, but a slider whose cell a caller could forget to set would be a slider with no value at all. */
		NSSliderCell *cell = [[NSSliderCell alloc] init];

		[cell setEnabled:YES];
		[self setCell:cell];
		[cell release];
		/* A ZERO FRAME IS FILLED IN WITH THE DEFAULT, which is what makes `[[NSSlider alloc] initWithFrame:NSZeroRect]`
		 * a slider rather than a point: the same reading `NSButton` takes for its own default size. */
		if (frameRect.size.width <= 0.0 || frameRect.size.height <= 0.0) {
			[self setFrameSize:NSMakeSize(NS_SLIDER_DEFAULT_WIDTH, NS_SLIDER_DEFAULT_HEIGHT)];
		}
	}
	return self;
}

/* ---- THE RANGE, AND THE FACE'S FOUR PROPERTIES: FOURTEEN FORWARDS AND NO STATE OF THEIR OWN -------------------- */

- (double)minValue
{
	return [(NSSliderCell *)[self cell] minValue];
}

- (void)setMinValue:(double)aDouble
{
	[(NSSliderCell *)[self cell] setMinValue:aDouble];
	[self setNeedsDisplay:YES];
}

- (double)maxValue
{
	return [(NSSliderCell *)[self cell] maxValue];
}

- (void)setMaxValue:(double)aDouble
{
	[(NSSliderCell *)[self cell] setMaxValue:aDouble];
	[self setNeedsDisplay:YES];
}

- (double)altIncrementValue
{
	return [(NSSliderCell *)[self cell] altIncrementValue];
}

- (void)setAltIncrementValue:(double)increment
{
	[(NSSliderCell *)[self cell] setAltIncrementValue:increment];
}

- (BOOL)isVertical
{
	return [(NSSliderCell *)[self cell] isVertical];
}

- (void)setVertical:(BOOL)flag
{
	[(NSSliderCell *)[self cell] setVertical:flag];
	[self setNeedsDisplay:YES];
}

- (NSSliderType)sliderType
{
	return [(NSSliderCell *)[self cell] sliderType];
}

- (void)setSliderType:(NSSliderType)aType
{
	[(NSSliderCell *)[self cell] setSliderType:aType];
	[self setNeedsDisplay:YES];
}

- (NSInteger)numberOfTickMarks
{
	return [(NSSliderCell *)[self cell] numberOfTickMarks];
}

- (void)setNumberOfTickMarks:(NSInteger)count
{
	[(NSSliderCell *)[self cell] setNumberOfTickMarks:count];
	[self setNeedsDisplay:YES];
}

- (NSTickMarkPosition)tickMarkPosition
{
	return [(NSSliderCell *)[self cell] tickMarkPosition];
}

- (void)setTickMarkPosition:(NSTickMarkPosition)position
{
	[(NSSliderCell *)[self cell] setTickMarkPosition:position];
	[self setNeedsDisplay:YES];
}

/* ---- THE TICKS AS VALUES, THE KNOB'S THICKNESS, THE TITLE AND THE IMAGE: FORWARDS AND ONE NAMED REFUSAL -------- */

- (BOOL)allowsTickMarkValuesOnly
{
	return [(NSSliderCell *)[self cell] allowsTickMarkValuesOnly];
}

- (void)setAllowsTickMarkValuesOnly:(BOOL)flag
{
	[(NSSliderCell *)[self cell] setAllowsTickMarkValuesOnly:flag];
	[self setNeedsDisplay:YES];
}

- (double)tickMarkValueAtIndex:(NSInteger)index
{
	return [(NSSliderCell *)[self cell] tickMarkValueAtIndex:index];
}

- (double)closestTickMarkValueToValue:(double)aValue
{
	return [(NSSliderCell *)[self cell] closestTickMarkValueToValue:aValue];
}

- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index
{
	return [(NSSliderCell *)[self cell] rectOfTickMarkAtIndex:index];
}

- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point
{
	return [(NSSliderCell *)[self cell] indexOfTickMarkAtPoint:point];
}

- (double)knobThickness
{
	return [(NSSliderCell *)[self cell] knobThickness];
}

- (void)setKnobThickness:(double)thickness
{
	[(NSSliderCell *)[self cell] setKnobThickness:thickness];
	[self setNeedsDisplay:YES];
}

- (NSString *)title
{
	return [(NSSliderCell *)[self cell] title];
}

- (void)setTitle:(NSString *)aString
{
	[(NSSliderCell *)[self cell] setTitle:aString];
	[self setNeedsDisplay:YES];
}

- (NSCell *)titleCell
{
	return [(NSSliderCell *)[self cell] titleCell];
}

- (void)setTitleCell:(NSCell *)aCell
{
	[(NSSliderCell *)[self cell] setTitleCell:aCell];
	[self setNeedsDisplay:YES];
}

- (NSFont *)titleFont
{
	return [(NSSliderCell *)[self cell] titleFont];
}

- (void)setTitleFont:(NSFont *)font
{
	[(NSSliderCell *)[self cell] setTitleFont:font];
	[self setNeedsDisplay:YES];
}

- (NSColor *)titleColor
{
	return [(NSSliderCell *)[self cell] titleColor];
}

- (void)setTitleColor:(NSColor *)color
{
	[(NSSliderCell *)[self cell] setTitleColor:color];
	[self setNeedsDisplay:YES];
}

- (NSImage *)image
{
	return [(NSCell *)[self cell] image];
}

- (void)setImage:(NSImage *)theImage
{
	/* **A BACKGROUND IMAGE, WHICH IS APPLE'S OWN PARAMETER NAME AND THE CELL'S DRAWING.** The image lives on the cell
	 * (Apple's storage), and `NSSliderCell -drawWithFrame:inView:` draws it UNDER the track, the knob and the title —
	 * so the door is not merely stored. Redisplay is asked for because the face changed. */
	[(NSCell *)[self cell] setImage:theImage];
	[self setNeedsDisplay:YES];
}

/* ---- AND THE ONE VIEW DOOR A SLIDER ANSWERS DIFFERENTLY -------------------------------------------------------- */

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	/* **A SLIDER TAKES A PRESS IN A WINDOW THAT IS NOT YET ACTIVE**, because the press is a DRAG rather than a
	 * selection: the event is not read, and the answer does not depend on which button or where — the same reading
	 * `NSButtonCell`'s `-acceptsFirstMouse:` takes for a button. */
	(void)theEvent;
	return YES;
}

@end
