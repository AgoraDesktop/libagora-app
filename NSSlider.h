/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSSlider.h — a control whose value is a position (stage E).
 *
 * **THIS CLASS IS THE THINNEST IN THE CONTROL FAMILY AND THAT IS THE POINT OF IT.** Every value and face below is its
 * `NSSliderCell`'s; what `NSSlider` adds is the CELL, the default frame a freshly made slider wants, and
 * `-acceptsFirstMouse:`. The TRACKING is not here either — it is `NSControl`'s loop, which calls the cell's own
 * tracking hooks (§A10cc), so a slider needs no `-mouseDown:` of its own and the "what value is this point" question
 * stays in exactly one place.
 *
 * THE VALUE FAMILY IS INHERITED AND DELIBERATELY NOT REDECLARED: `-doubleValue`, `-floatValue`, `-intValue`,
 * `-integerValue` and their setters, plus `-isContinuous` and `-setContinuous:`, are `NSControl`'s and reach this
 * class's cell unchanged — `NSSliderCell` overrides the numeric family so that `NSCell`'s "does nothing if the
 * receiver isn't a text cell" rule never applies here, and the doors above the cell are the same forwards a button
 * uses. Re-declaring them would be a second signature to keep in step with the first.
 *
 * **THE TICK AND TITLE FAMILIES ARE FORWARDS TOO, AND THE SLIDER IS WHERE THEY ARE ASKED FOR.** A slider's ticks are
 * values as well as ink — `-tickMarkValueAtIndex:`, `-closestTickMarkValueToValue:` and
 * `-allowsTickMarkValuesOnly` are the cell's arithmetic — and its title is a cell's label drawn in a band above the
 * track. The one door that is not the cell's arithmetic is `-image`: Apple's parameter name calls it a BACKGROUND
 * image, and the cell draws it under the track, the knob and the title rather than inventing a second face.
 *
 * WHAT IS NOT HERE, ON THE SAME TERMS AS THE CELL: the circular face (`-sliderType` stores and answers
 * `NSCircularSlider`, and the ink is the linear one), and the class doors Apple added after this vintage
 * (`+sliderWithValue:minValue:maxValue:target:action:` is 10.12, and `-tickMarkPosition`'s newer spellings are the
 * same question) — this tree pins the era, so the newer doors are STRUCK rather than declared and stubbed.
 */
#ifndef APPKIT_NSSLIDER_H
#define APPKIT_NSSLIDER_H

#import <AppKit/NSControl.h>
#import <AppKit/NSSliderCell.h>

@class NSColor;
@class NSFont;
@class NSImage;

NS_ASSUME_NONNULL_BEGIN

@interface NSSlider : NSControl <NSSecureCoding>

/* THE CELL, MADE AND INSTALLED. `-value` IS NOT A DOOR HERE — a slider's value is `-doubleValue`, five doors up. */
- (instancetype)initWithFrame:(NSRect)frameRect;

/* **THE RANGE, AND THE FOUR PROPERTIES OF THE FACE.** Each is its cell's, exactly as a button's title is its
 * `NSButtonCell`'s, so each is a forward and nothing more. */
- (double)minValue;
- (void)setMinValue:(double)aDouble;
- (double)maxValue;
- (void)setMaxValue:(double)aDouble;
- (double)altIncrementValue;
- (void)setAltIncrementValue:(double)increment;
- (BOOL)isVertical;
- (void)setVertical:(BOOL)flag;
- (NSSliderType)sliderType;
- (void)setSliderType:(NSSliderType)aType;
- (NSInteger)numberOfTickMarks;
- (void)setNumberOfTickMarks:(NSInteger)count;
- (NSTickMarkPosition)tickMarkPosition;
- (void)setTickMarkPosition:(NSTickMarkPosition)position;

/* **THE TICKS AS VALUES, AND THE FLAG THAT MAKES THEM MANDATORY** — the cell's own arithmetic, forwarded unchanged.
 * The three questions are: what value is mark n, what mark is nearest a value, and which mark is at a point. */
- (BOOL)allowsTickMarkValuesOnly;
- (void)setAllowsTickMarkValuesOnly:(BOOL)flag;
- (double)tickMarkValueAtIndex:(NSInteger)index;
- (double)closestTickMarkValueToValue:(double)aValue;
- (NSRect)rectOfTickMarkAtIndex:(NSInteger)index;
- (NSInteger)indexOfTickMarkAtPoint:(NSPoint)point;

/* **THE KNOB, THE TITLE AND THE IMAGE.** The thickness is the grabber's length along the track; the title's four doors
 * are the cell that draws it and the font and colour conveniences over it; and the image is the BACKGROUND the cell
 * draws under the track, the knob and the title. */
- (double)knobThickness;
- (void)setKnobThickness:(double)thickness;
- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)aString;
- (NSCell *)titleCell;
- (void)setTitleCell:(nullable NSCell *)aCell;
- (nullable NSFont *)titleFont;
- (void)setTitleFont:(nullable NSFont *)font;
- (nullable NSColor *)titleColor;
- (void)setTitleColor:(nullable NSColor *)color;
- (nullable NSImage *)image;
- (void)setImage:(nullable NSImage *)theImage;

/* **AND THE ONE VIEW DOOR A SLIDER ANSWERS DIFFERENTLY FROM MOST CONTROLS.** Apple's slider takes a press even when
 * its window is not the active one — a slider is dragged, not typed into, so the first click should move the knob
 * rather than only raise the window. */
- (BOOL)acceptsFirstMouse:(nullable NSEvent *)theEvent;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSLIDER_H */
