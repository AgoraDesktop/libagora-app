/*
 * NSColorPicker — the palette picker, and the view it puts in the colour panel.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE GRID IS THE PICKER, AND EVERY OTHER DOOR IS ABOUT BEING HOSTED.** `-provideNewView:` makes the view,
 * `-setColor:` tells it what the panel's colour is (so it can ring the matching cell), `-attachColorList:` adds a
 * list's colours to the front of the grid, `-minContentSize` tells the panel how big to be, and the two button-image
 * doors are the chip that selects this picker. The GRID itself is the only interesting arithmetic: a colour list's
 * entries first, in the list's order, then a generated hue/brightness ramp to fill the remaining cells, so a panel with
 * no lists attached still has a full palette and a panel with one gets that list's colours where a person looks first.
 *
 * **THE VIEW IS ITS OWN CLASS BECAUSE IT IS THE THING THAT TRACKS.** `NSView -mouseDown:` is where a click becomes a
 * colour; a picker that handled it would need the view's geometry twice. The view carries an ASSIGN back-pointer to its
 * picker (the picker owns the view) and calls one private door on it.
 */
#import <AppKit/NSColorPicker.h>

#import <AppKit/NSColorPanel.h>
#import <AppKit/NSColorList.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSView.h>

#include <math.h>

/* THE GRID'S SHAPE, AND THE NUMBER OF GENERATED COLOURS THAT FILL WHAT THE LISTS LEAVE. Eight across is the width a
 * 160-point palette divides into twenty-point cells, and five rows is forty colours — enough to see a ramp in. */
#define AG_PICKER_COLUMNS 8
#define AG_PICKER_ROWS    5
#define AG_PICKER_CELL    20.0

@class AGColorPickerView;

@interface NSColorPicker ()
- (nullable NSColor *)fn_color;
- (NSColor *)fn_paletteColorAtIndex:(NSInteger)index;
- (NSInteger)fn_paletteCount;
- (void)fn_chooseColor:(NSColor *)color;
@end

/* ============================================================================================ *
 * THE GRID VIEW.                                                                                *
 * ============================================================================================ */

@interface AGColorPickerView : NSView
{
	NSColorPicker *_picker;		/* ASSIGN: the picker owns this view */
}
- (instancetype)initWithFrame:(NSRect)frameRect picker:(NSColorPicker *)picker;
@end

@implementation AGColorPickerView

- (instancetype)initWithFrame:(NSRect)frameRect picker:(NSColorPicker *)picker
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_picker = picker;
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	(void)theEvent;
	return YES;
}

/* **THE CELL IS ONE OF FORTY AND THE INDEX IS THE ARITHMETIC.** A click outside the grid is no click at all — the
 * answer is -1 rather than a clamped index, because a clamped one would pick the corner cell for a press in the margin
 * and a person clicking beside the grid would change their colour. */
- (NSInteger)fn_indexAtPoint:(NSPoint)point
{
	NSInteger column, row;

	if (point.x < 0.0 || point.y < 0.0) {
		return -1;
	}
	column = (NSInteger)floor(point.x / AG_PICKER_CELL);
	row = (NSInteger)floor(point.y / AG_PICKER_CELL);
	if (column < 0 || column >= AG_PICKER_COLUMNS || row < 0 || row >= AG_PICKER_ROWS) {
		return -1;
	}
	return row * AG_PICKER_COLUMNS + column;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger i;
	NSColor *current = [_picker fn_color];

	(void)dirtyRect;
	for (i = 0; i < AG_PICKER_COLUMNS * AG_PICKER_ROWS; i++) {
		NSInteger column = i % AG_PICKER_COLUMNS;
		NSInteger row = i / AG_PICKER_COLUMNS;
		NSRect cell = NSMakeRect((CGFloat)column * AG_PICKER_CELL, (CGFloat)row * AG_PICKER_CELL,
					 AG_PICKER_CELL, AG_PICKER_CELL);
		NSColor *colour = [_picker fn_paletteColorAtIndex:i];

		if (colour == nil) {
			continue;
		}
		[colour setFill];
		[[NSBezierPath bezierPathWithRect:NSInsetRect(cell, 1.0, 1.0)] fill];
		/* AND THE CELL THE PANEL'S COLOUR IS IN WEARS A RING, so a caller can see which swatch is current. A colour
		 * that matches no cell — one from a slider, or a system colour — leaves every cell unringed, which is the
		 * truth rather than a nearest-match guess. */
		if (current != nil
		    && fabs([current redComponent] - [colour redComponent]) < 0.01
		    && fabs([current greenComponent] - [colour greenComponent]) < 0.01
		    && fabs([current blueComponent] - [colour blueComponent]) < 0.01) {
			NSBezierPath *ring = [NSBezierPath bezierPathWithRect:NSInsetRect(cell, 2.0, 2.0)];

			[[NSColor cg_accentColor] setStroke];
			[ring setLineWidth:2.0];
			[ring stroke];
		}
	}
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSInteger index = [self fn_indexAtPoint:point];
	NSColor *colour;

	if (index < 0) {
		return;
	}
	colour = [_picker fn_paletteColorAtIndex:index];
	if (colour != nil) {
		[_picker fn_chooseColor:colour];
	}
}

@end

/* ============================================================================================ *
 * THE PICKER.                                                                                   *
 * ============================================================================================ */

@implementation NSColorPicker

- (id)initWithPickerMask:(NSUInteger)mask colorPanel:(NSColorPanel *)owningColorPanel
{
	self = [super init];
	if (self != nil) {
		_pickerMask = mask;
		_colorPanel = owningColorPanel;	/* ASSIGN */
		_colorLists = [[NSMutableArray alloc] init];
		_mode = NSHSBModeColorPanel;
	}
	return self;
}

- (void)dealloc
{
	[_colorLists release];
	[_color release];
	[_view release];
	[super dealloc];
}

- (NSColorPanel *)colorPanel
{
	return _colorPanel;
}

/* **THE TOOLTIP IS THE MODE'S NAME, AND IT IS THE ONE PLACE A PERSON CAN TELL THE CHIPS APART** — the chips are
 * letters, and a letter is a mnemonic rather than a word. */
- (NSString *)buttonToolTip
{
	switch (_mode) {
	case NSGrayModeColorPanel:
		return @"Gray";
	case NSRGBModeColorPanel:
		return @"RGB";
	case NSCMYKModeColorPanel:
		return @"CMYK";
	case NSHSBModeColorPanel:
		return @"HSB";
	case NSCustomPaletteModeColorPanel:
		return @"Palette";
	case NSColorListModeColorPanel:
		return @"Color list";
	case NSWheelModeColorPanel:
		return @"Wheel";
	case NSCrayonModeColorPanel:
		return @"Crayon";
	}
	return @"Colors";
}

/* A CHIP'S IMAGE: A ROUNDED SQUARE, THE MODE'S INITIAL, AND THE BORDER A BUTTON WEARS. It is drawn rather than shipped
 * for the same reason every mark in this tier is — no artwork, no resource, and a shape that is arithmetic. */
- (NSImage *)provideNewButtonImage
{
	NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(18.0, 18.0)] autorelease];
	NSString *initial;
	NSDictionary *attributes;

	switch (_mode) {
	case NSGrayModeColorPanel: initial = @"G"; break;
	case NSRGBModeColorPanel: initial = @"R"; break;
	case NSCMYKModeColorPanel: initial = @"C"; break;
	case NSHSBModeColorPanel: initial = @"H"; break;
	case NSCustomPaletteModeColorPanel: initial = @"P"; break;
	case NSColorListModeColorPanel: initial = @"L"; break;
	case NSWheelModeColorPanel: initial = @"W"; break;
	case NSCrayonModeColorPanel: initial = @"Y"; break;
	default: initial = @"?"; break;
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont boldSystemFontOfSize:10.0], NSFontAttributeName,
		[NSColor controlTextColor], NSForegroundColorAttributeName, nil];
	[image lockFocus];
	{
		NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.5, 0.5, 17.0, 17.0)
								     xRadius:3.0 yRadius:3.0];
		NSSize size = [initial sizeWithAttributes:attributes];

		[[NSColor controlColor] setFill];
		[face fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:1.0];
		[face stroke];
		[initial drawAtPoint:NSMakePoint((18.0 - size.width) / 2.0, (18.0 - size.height) / 2.0)
		      withAttributes:attributes];
	}
	[image unlockFocus];
	return image;
}

- (void)insertNewButtonImage:(NSImage *)newButtonImage in:(NSButtonCell *)buttonCell
{
	/* THE CELL IS THE CALLER'S — the panel's mode chip — so this door sets the image and nothing else; the button type,
	 * the bezel and the target belong to whoever made the cell. */
	if (buttonCell != nil) {
		[buttonCell setImage:newButtonImage];
	}
}

- (NSSize)minContentSize
{
	return NSMakeSize(AG_PICKER_COLUMNS * AG_PICKER_CELL, AG_PICKER_ROWS * AG_PICKER_CELL);
}

- (void)viewSizeChanged:(id)sender
{
	(void)sender;
	if (_view != nil) {
		[_view setFrameSize:[self minContentSize]];
		[_view setNeedsDisplay:YES];
	}
}

- (void)setMode:(NSColorPanelMode)mode
{
	_mode = mode;
}

- (NSColorPanelMode)currentMode
{
	return _mode;
}

- (BOOL)supportsMode:(NSColorPanelMode)mode
{
	/* **THE PALETTE CAN SHOW EVERY MODE**, because its face is a grid of colours and a grid does not depend on the mode
	 * — the mode moves the CHIP and the panel's label. A subclass with a real wheel answers NO to the modes it cannot
	 * draw, and the panel then keeps this picker for them. */
	(void)mode;
	return YES;
}

- (void)attachColorList:(NSColorList *)colorList
{
	if (colorList != nil && ![_colorLists containsObject:colorList]) {
		[_colorLists addObject:colorList];
		[_view setNeedsDisplay:YES];
	}
}

- (void)detachColorList:(NSColorList *)colorList
{
	if (colorList != nil) {
		[_colorLists removeObject:colorList];
		[_view setNeedsDisplay:YES];
	}
}

- (NSView *)provideNewView:(BOOL)initialRequest
{
	(void)initialRequest;
	if (_view == nil) {
		_view = [[AGColorPickerView alloc] initWithFrame:NSMakeRect(0.0, 0.0,
									AG_PICKER_COLUMNS * AG_PICKER_CELL,
									AG_PICKER_ROWS * AG_PICKER_CELL)
							     picker:self];
	}
	return _view;
}

- (void)setColor:(NSColor *)newColor
{
	NSColor *old = _color;

	_color = [newColor retain];
	[old release];
	[_view setNeedsDisplay:YES];
}

- (NSColor *)fn_color
{
	return _color;
}

/* **THE PALETTE IS THE ATTACHED LISTS FIRST AND A GENERATED RAMP AFTER THEM.** The lists are flattened in the order
 * they were attached — a list's own key order, which `NSColorList` keeps — so a caller's palette occupies the first
 * cells of the grid and does not reorder itself between draws. */
- (NSInteger)fn_paletteCount
{
	return AG_PICKER_COLUMNS * AG_PICKER_ROWS;
}

- (NSColor *)fn_paletteColorAtIndex:(NSInteger)index
{
	NSInteger listed = 0;
	NSUInteger i;

	if (index < 0) {
		return nil;
	}
	for (i = 0; i < [_colorLists count]; i++) {
		NSColorList *list = [_colorLists objectAtIndex:i];
		NSArray *keys = [list allKeys];
		NSUInteger k;

		for (k = 0; k < [keys count]; k++) {
			if (listed == index) {
				return [list colorWithKey:[keys objectAtIndex:k]];
			}
			listed++;
		}
	}
	index -= listed;
	if (index < 0 || index >= [self fn_paletteCount] - listed) {
		return nil;
	}
	{
		/* THE GENERATED RAMP: eight hues across, five brightness steps down, and the SAME pair of numbers the colour
		 * class's own HSV constructor takes. Saturation is fixed below 1 so the top row is not a set of primaries. */
		CGFloat hue = (CGFloat)(index % AG_PICKER_COLUMNS) / (CGFloat)AG_PICKER_COLUMNS;
		CGFloat brightness = 1.0 - (CGFloat)(index / AG_PICKER_COLUMNS) * 0.18;

		return [NSColor colorWithCalibratedHue:hue saturation:0.80 brightness:brightness alpha:1.0];
	}
}

- (NSColor *)cg_paletteColorAtIndex:(NSInteger)index
{
	return [self fn_paletteColorAtIndex:index];
}

- (void)fn_chooseColor:(NSColor *)color
{
	/* **THE PANEL OWNS THE COLOUR, SO THE PICKER ASKS IT TO CHANGE** — which is what sends the action to the target
	 * and what redraws every panel that shares the colour. A picker that stored the colour itself would be a second
	 * owner of one fact. */
	if (color != nil && _colorPanel != nil) {
		[_colorPanel setColor:color];
	}
}

@end
