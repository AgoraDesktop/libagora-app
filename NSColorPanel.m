/*
 * NSColorPanel — the shared colour panel.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE PANEL IS A SINGLETON, A CONTENT VIEW, AND A PICKER.** The singleton is the two class doors and the two class
 * configurations; the content view is the chips, the swatch and the alpha ramp; the picker is `NSColorPicker`'s view,
 * hosted in a subview so it can be an ordinary view with its own `-mouseDown:`. Everything else here is forwarding to
 * one of those three, which is why the file is mostly small methods.
 *
 * **THE LAYOUT IS ONE SET OF CONSTANTS AND ONE METHOD.** The content view is flipped, so the chips are at the top, the
 * picker's grid below them, then the swatch, then the optional alpha ramp, then the caller's accessory view. A mode
 * change re-makes the picker's view and re-lays out; a size change does not, because the panel's content size is this
 * class's and not a caller's.
 */
#import <AppKit/NSColorPanel.h>

#import <AppKit/NSColorList.h>
#import <AppKit/NSColorPicker.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSDragging.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSView.h>

#include <math.h>

/* THE CONTENT'S SHAPE. The chip row is one cell high, the grid is the picker's minimum, and the swatch and ramp are
 * bands under it; the accessory view's band is the last one, and it is always reserved so that adding one does not
 * resize the panel. */
#define AG_COLOR_PANEL_WIDTH      220.0
#define AG_COLOR_PANEL_HEIGHT     236.0
#define AG_COLOR_PANEL_MARGIN       8.0
#define AG_COLOR_CHIP_SIZE         18.0
#define AG_COLOR_CHIP_GAP           4.0
#define AG_COLOR_CHIP_TOP           8.0
#define AG_COLOR_PICKER_TOP        40.0
#define AG_COLOR_SWATCH_TOP       148.0
#define AG_COLOR_SWATCH_HEIGHT     40.0
#define AG_COLOR_ALPHA_TOP        194.0
#define AG_COLOR_ALPHA_HEIGHT      14.0
#define AG_COLOR_ACCESSORY_TOP    214.0
#define AG_COLOR_ACCESSORY_HEIGHT  18.0
#define AG_COLOR_ALPHA_STEPS       32

@class NSColorPanel;

/* ============================================================================================ *
 * THE PRIVATE DOORS THE CONTENT VIEW AND THE PANEL SHARE.                                        *
 * ============================================================================================ */

@interface NSColorPanel ()
- (void)fn_buildChips;
- (NSColorPicker *)fn_makePickerForMode:(NSColorPanelMode)mode;
- (NSUInteger)fn_chipCount;
- (NSButtonCell *)fn_chipCellAtIndex:(NSUInteger)index;
- (NSColorPanelMode)fn_chipModeAtIndex:(NSUInteger)index;
- (void)fn_chooseChipAtIndex:(NSUInteger)index;
- (void)fn_showPickerForMode:(NSColorPanelMode)mode;
- (void)fn_layout;
- (void)fn_setAlpha:(CGFloat)alpha;
- (void)fn_sendAction;
- (NSImage *)fn_swatchImageForColor:(NSColor *)color;
@end

static NSUInteger s_pickerMask = NSColorPanelAllModesMask;
static NSColorPanelMode s_pickerMode = NSHSBModeColorPanel;

/* **THE MODE'S BIT, IN THE ORDER THE HEADER DECLARES THE MODES.** The enum's value IS the index, so the table and the
 * loop below are the same order as `NSColorPanelMode`'s cases. */
static NSUInteger AGColorPanelMaskForMode(NSColorPanelMode mode)
{
	switch (mode) {
	case NSGrayModeColorPanel:		return NSColorPanelGrayModeMask;
	case NSRGBModeColorPanel:		return NSColorPanelRGBModeMask;
	case NSCMYKModeColorPanel:		return NSColorPanelCMYKModeMask;
	case NSHSBModeColorPanel:		return NSColorPanelHSBModeMask;
	case NSCustomPaletteModeColorPanel:	return NSColorPanelCustomPaletteModeMask;
	case NSColorListModeColorPanel:		return NSColorPanelColorListModeMask;
	case NSWheelModeColorPanel:		return NSColorPanelWheelModeMask;
	case NSCrayonModeColorPanel:		return NSColorPanelCrayonModeMask;
	}
	return 0;
}

/* ============================================================================================ *
 * THE CONTENT VIEW: THE CHIPS, THE SWATCH AND THE RAMP.                                         *
 * ============================================================================================ */

@interface AGColorPanelView : NSView
{
	NSColorPanel *_panel;		/* ASSIGN: the panel owns this view */
}
- (instancetype)initWithFrame:(NSRect)frameRect panel:(NSColorPanel *)panel;
@end

@implementation AGColorPanelView

- (instancetype)initWithFrame:(NSRect)frameRect panel:(NSColorPanel *)panel
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_panel = panel;
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

/* **THE FOUR BANDS, IN ONE PLACE, BECAUSE THE DRAWING AND THE HITTING BOTH NEED THEM.** A second copy of this
 * arithmetic is how a swatch and its click get out of step; the content view is the only thing that lays them out. */
- (NSRect)fn_chipRectAtIndex:(NSUInteger)index
{
	CGFloat total = (CGFloat)[_panel fn_chipCount] * AG_COLOR_CHIP_SIZE
		      + (CGFloat)([_panel fn_chipCount] > 0 ? [_panel fn_chipCount] - 1 : 0) * AG_COLOR_CHIP_GAP;
	CGFloat x = (AG_COLOR_PANEL_WIDTH - total) / 2.0 + (CGFloat)index * (AG_COLOR_CHIP_SIZE + AG_COLOR_CHIP_GAP);

	return NSMakeRect(x, AG_COLOR_CHIP_TOP, AG_COLOR_CHIP_SIZE, AG_COLOR_CHIP_SIZE);
}

- (NSRect)fn_pickerRect
{
	return NSMakeRect((AG_COLOR_PANEL_WIDTH - 160.0) / 2.0, AG_COLOR_PICKER_TOP, 160.0, 100.0);
}

- (NSRect)fn_swatchRect
{
	return NSMakeRect(AG_COLOR_PANEL_MARGIN, AG_COLOR_SWATCH_TOP,
			  AG_COLOR_PANEL_WIDTH - 2.0 * AG_COLOR_PANEL_MARGIN, AG_COLOR_SWATCH_HEIGHT);
}

- (NSRect)fn_alphaRect
{
	return NSMakeRect(AG_COLOR_PANEL_MARGIN, AG_COLOR_ALPHA_TOP,
			  AG_COLOR_PANEL_WIDTH - 2.0 * AG_COLOR_PANEL_MARGIN, AG_COLOR_ALPHA_HEIGHT);
}

- (NSRect)fn_accessoryRect
{
	return NSMakeRect(AG_COLOR_PANEL_MARGIN, AG_COLOR_ACCESSORY_TOP,
			  AG_COLOR_PANEL_WIDTH - 2.0 * AG_COLOR_PANEL_MARGIN, AG_COLOR_ACCESSORY_HEIGHT);
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSColor *colour;
	NSUInteger i;

	(void)dirtyRect;
	[[NSColor windowBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:[self bounds]] fill];

	/* THE CHIPS, EACH ITS OWN CELL, WITH THE ACTIVE MODE RINGED. */
	for (i = 0; i < [_panel fn_chipCount]; i++) {
		NSRect rect = [self fn_chipRectAtIndex:i];
		NSButtonCell *cell = [_panel fn_chipCellAtIndex:i];

		[cell drawWithFrame:rect inView:self];
		if ([_panel fn_chipModeAtIndex:i] == [_panel mode]) {
			NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, -1.0, -1.0)
									    xRadius:4.0 yRadius:4.0];

			[[NSColor cg_accentColor] setStroke];
			[ring setLineWidth:2.0];
			[ring stroke];
		}
	}

	/* THE SWATCH: A BORDER AND THE COLOUR, DRAWN OPAQUE. A transparent colour's swatch is the alpha ramp below rather
	 * than a checkerboard here, and the header says so. */
	{
		NSRect swatch = [self fn_swatchRect];
		NSBezierPath *edge = [NSBezierPath bezierPathWithRect:swatch];

		colour = [_panel color];
		[(colour != nil ? [colour colorWithAlphaComponent:1.0] : [NSColor clearColor]) setFill];
		[edge fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[edge setLineWidth:1.0];
		[edge stroke];
	}

	/* AND THE RAMP WHEN IT IS SHOWN: thirty-two steps from transparent to opaque, over white, with a marker at the
	 * current alpha — the value the panel's colour actually has. */
	if ([_panel showsAlpha] && colour != nil) {
		NSRect ramp = [self fn_alphaRect];
		CGFloat step = NSWidth(ramp) / (CGFloat)AG_COLOR_ALPHA_STEPS;
		NSInteger i2;

		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:ramp] fill];
		for (i2 = 0; i2 < AG_COLOR_ALPHA_STEPS; i2++) {
			NSRect band = NSMakeRect(NSMinX(ramp) + (CGFloat)i2 * step, NSMinY(ramp), step + 0.5,
						 NSHeight(ramp));

			[[colour colorWithAlphaComponent:(CGFloat)i2 / (CGFloat)(AG_COLOR_ALPHA_STEPS - 1)] setFill];
			[[NSBezierPath bezierPathWithRect:band] fill];
		}
		[[NSColor blackColor] setStroke];
		{
			NSBezierPath *marker = [NSBezierPath bezierPath];
			CGFloat x = NSMinX(ramp) + [colour alphaComponent] * NSWidth(ramp);

			[marker moveToPoint:NSMakePoint(x, NSMinY(ramp) - 1.0)];
			[marker lineToPoint:NSMakePoint(x, NSMaxY(ramp) + 1.0)];
			[marker setLineWidth:1.0];
			[marker stroke];
		}
	}
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSUInteger i;

	for (i = 0; i < [_panel fn_chipCount]; i++) {
		if (NSPointInRect(point, [self fn_chipRectAtIndex:i])) {
			[_panel fn_chooseChipAtIndex:i];
			return;
		}
	}
	if ([_panel showsAlpha] && NSPointInRect(point, [self fn_alphaRect])) {
		NSRect ramp = [self fn_alphaRect];
		CGFloat alpha = (point.x - NSMinX(ramp)) / NSWidth(ramp);

		if (alpha < 0.0) {
			alpha = 0.0;
		}
		if (alpha > 1.0) {
			alpha = 1.0;
		}
		[_panel fn_setAlpha:alpha];
	}
}

@end

/* ============================================================================================ *
 * THE PANEL.                                                                                    *
 * ============================================================================================ */

static NSColorPanel *s_sharedColorPanel = nil;

@implementation NSColorPanel

/* ============================================================================================ *
 * THE SINGLETON AND THE TWO CLASS CONFIGURATIONS.                                               *
 * ============================================================================================ */

+ (NSColorPanel *)sharedColorPanel
{
	if (s_sharedColorPanel == nil) {
		NSColorPanel *panel = [[NSColorPanel alloc] initWithContentRect:NSMakeRect(0.0, 0.0, AG_COLOR_PANEL_WIDTH,
											  AG_COLOR_PANEL_HEIGHT)
								      styleMask:(NSTitledWindowMask | NSClosableWindowMask)
									backing:NSBackingStoreBuffered
									  defer:NO];

		[panel setTitle:@"Colors"];
		[panel setReleasedWhenClosed:NO];
		[panel setFloatingPanel:YES];
		[panel setLevel:NSFloatingWindowLevel];
		[panel setColor:[NSColor whiteColor]];
		s_sharedColorPanel = panel;	/* KEPT FOREVER: it is the shared panel */
	}
	return s_sharedColorPanel;
}

+ (BOOL)sharedColorPanelExists
{
	return s_sharedColorPanel != nil;
}

+ (void)setPickerMask:(NSUInteger)mask
{
	/* **THE CLASS DOOR APPLIES TO THE SHARED PANEL IF THERE IS ONE.** Apple's is a class method because the panel is a
	 * singleton; a caller may say this BEFORE the panel exists, which is why the value is kept in a static as well as
	 * pushed into a live panel. */
	s_pickerMask = mask;
	if (s_sharedColorPanel != nil) {
		s_sharedColorPanel->_pickerMask = mask;
		[s_sharedColorPanel fn_buildChips];
		[s_sharedColorPanel fn_layout];
	}
}

+ (void)setPickerMode:(NSColorPanelMode)mode
{
	s_pickerMode = mode;
	if (s_sharedColorPanel != nil) {
		[s_sharedColorPanel setMode:mode];
	}
}

/* ============================================================================================ *
 * LIFETIME AND THE CONTENT.                                                                     *
 * ============================================================================================ */

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{
	self = [super initWithContentRect:contentRect styleMask:styleMask backing:bufferingType defer:flag];
	if (self != nil) {
		_pickerMask = s_pickerMask;
		_mode = s_pickerMode;
		_colorLists = [[NSMutableArray alloc] init];
		_pickers = [[NSMutableDictionary alloc] init];
		_chipCells = [[NSMutableArray alloc] init];
		_chipModes = [[NSMutableArray alloc] init];
		_panelView = [[AGColorPanelView alloc] initWithFrame:NSMakeRect(0.0, 0.0, AG_COLOR_PANEL_WIDTH,
									      AG_COLOR_PANEL_HEIGHT)
							       panel:self];
		[self setContentView:(NSView *)_panelView];
		[self fn_buildChips];
		[self fn_showPickerForMode:_mode];
	}
	return self;
}

- (void)dealloc
{
	[_color release];
	[_accessoryView release];
	[_colorLists release];
	[_pickers release];
	[_chipCells release];
	[_chipModes release];
	[_panelView release];
	[super dealloc];
}

- (void)fn_layout
{
	NSView *pickerView = nil;
	NSRect pickerRect = NSMakeRect((AG_COLOR_PANEL_WIDTH - 160.0) / 2.0, AG_COLOR_PICKER_TOP, 160.0, 100.0);

	if (_picker != nil && [_picker respondsToSelector:@selector(provideNewView:)]) {
		pickerView = [_picker provideNewView:NO];
	}
	if (pickerView != nil) {
		[pickerView setFrame:pickerRect];
		if ([pickerView superview] != (NSView *)_panelView) {
			[(NSView *)_panelView addSubview:pickerView];
		}
	}
	if (_accessoryView != nil) {
		[_accessoryView setFrame:NSMakeRect(AG_COLOR_PANEL_MARGIN, AG_COLOR_ACCESSORY_TOP,
						    AG_COLOR_PANEL_WIDTH - 2.0 * AG_COLOR_PANEL_MARGIN,
						    AG_COLOR_ACCESSORY_HEIGHT)];
	}
	[(NSView *)_panelView setNeedsDisplay:YES];
}

/* THE CHIPS: ONE CELL PER MODE THE MASK OFFERS, IN THE ENUM'S ORDER, EACH WITH ITS PICKER'S IMAGE. */
- (void)fn_buildChips
{
	NSInteger mode;

	[_chipCells removeAllObjects];
	[_chipModes removeAllObjects];
	for (mode = NSGrayModeColorPanel; mode <= NSCrayonModeColorPanel; mode++) {
		NSColorPicker *picker;
		NSButtonCell *cell;
		NSImage *image;

		if ((_pickerMask & AGColorPanelMaskForMode((NSColorPanelMode)mode)) == 0) {
			continue;
		}
		picker = [self fn_makePickerForMode:(NSColorPanelMode)mode];
		cell = [[NSButtonCell alloc] init];
		[cell setBordered:NO];
		image = [picker provideNewButtonImage];
		[picker insertNewButtonImage:image in:cell];
		[_chipCells addObject:cell];
		[_chipModes addObject:[NSNumber numberWithInteger:mode]];
		[cell release];
	}
}

- (NSUInteger)fn_chipCount
{
	return [_chipCells count];
}

- (NSButtonCell *)fn_chipCellAtIndex:(NSUInteger)index
{
	return (index < [_chipCells count]) ? [_chipCells objectAtIndex:index] : nil;
}

- (NSColorPanelMode)fn_chipModeAtIndex:(NSUInteger)index
{
	return (NSColorPanelMode)[(NSNumber *)[_chipModes objectAtIndex:index] integerValue];
}

- (void)fn_chooseChipAtIndex:(NSUInteger)index
{
	NSInteger count = (NSInteger)[_chipModes count];

	if ((NSInteger)index >= 0 && (NSInteger)index < count) {
		[self setMode:[self fn_chipModeAtIndex:index]];
	}
}

/* ============================================================================================ *
 * THE PICKERS.                                                                                  *
 * ============================================================================================ */

- (NSColorPicker *)fn_makePickerForMode:(NSColorPanelMode)mode
{
	NSNumber *key = [NSNumber numberWithInteger:(NSInteger)mode];
	NSColorPicker *picker = [_pickers objectForKey:key];
	NSUInteger i;

	if (picker != nil) {
		return picker;
	}
	picker = [[NSColorPicker alloc] initWithPickerMask:_pickerMask colorPanel:self];
	[picker setMode:mode];
	for (i = 0; i < [_colorLists count]; i++) {
		[picker attachColorList:[_colorLists objectAtIndex:i]];
	}
	[picker setColor:_color];
	[_pickers setObject:picker forKey:key];
	[picker release];
	return picker;
}

- (void)fn_showPickerForMode:(NSColorPanelMode)mode
{
	NSColorPicker *next = [self fn_makePickerForMode:mode];
	NSView *oldView = (_picker != nil && [_picker respondsToSelector:@selector(provideNewView:)])
		? [_picker provideNewView:NO] : nil;
	NSView *newView = [next provideNewView:NO];

	if (oldView != nil && oldView != newView) {
		[oldView removeFromSuperview];
	}
	_picker = next;
	[_picker setMode:mode];
	[_picker setColor:_color];
	[self fn_layout];
}

/* ============================================================================================ *
 * THE COLOUR, THE MODE AND THE ACTION.                                                          *
 * ============================================================================================ */

- (void)setColor:(NSColor *)color
{
	NSColor *old = _color;

	if (color == nil) {
		return;
	}
	_color = [color retain];
	[old release];
	[_picker setColor:_color];
	[(NSView *)_panelView setNeedsDisplay:YES];
	/* **A NON-CONTINUOUS PANEL SPEAKS ONLY WHEN THE SESSION ENDS**, which for a panel is `-setColor:` from a picker
	 * that has finished a drag inside itself; a continuous one speaks on every change. Both send the same action. */
	if (_continuous) {
		[self fn_sendAction];
	}
}

- (NSColor *)color
{
	return (_color != nil) ? _color : [NSColor whiteColor];
}

- (CGFloat)alpha
{
	return (_color != nil) ? [_color alphaComponent] : 0.0;
}

- (void)fn_setAlpha:(CGFloat)alpha
{
	NSColor *base = [self color];

	[self setColor:[base colorWithAlphaComponent:alpha]];
}

- (void)setMode:(NSColorPanelMode)mode
{
	_mode = mode;
	s_pickerMode = mode;
	[self fn_showPickerForMode:mode];
	[(NSView *)_panelView setNeedsDisplay:YES];
}

- (NSColorPanelMode)mode
{
	return _mode;
}

- (void)setShowsAlpha:(BOOL)flag
{
	_showsAlpha = flag ? YES : NO;
	[self fn_layout];
	[(NSView *)_panelView setNeedsDisplay:YES];
}

- (BOOL)showsAlpha
{
	return _showsAlpha;
}

- (void)setContinuous:(BOOL)flag
{
	_continuous = flag ? YES : NO;
}

- (BOOL)isContinuous
{
	return _continuous;
}

- (void)setTarget:(id)target
{
	_target = target;	/* ASSIGN, as every target in this tree */
}

- (id)target
{
	return _target;
}

- (void)setAction:(SEL)action
{
	_action = action;
}

- (SEL)action
{
	return _action;
}

- (void)fn_sendAction
{
	if (_action == NULL) {
		return;
	}
	[[NSApplication sharedApplication] sendAction:_action to:_target from:self];
}

/* ============================================================================================ *
 * THE ACCESSORY VIEW AND THE COLOUR LISTS.                                                      *
 * ============================================================================================ */

- (void)setAccessoryView:(NSView *)aView
{
	NSView *old = _accessoryView;

	if (old != nil) {
		[old removeFromSuperview];
	}
	_accessoryView = [aView retain];
	[old release];
	if (_accessoryView != nil) {
		[_accessoryView setFrame:NSMakeRect(AG_COLOR_PANEL_MARGIN, AG_COLOR_ACCESSORY_TOP,
						    AG_COLOR_PANEL_WIDTH - 2.0 * AG_COLOR_PANEL_MARGIN,
						    AG_COLOR_ACCESSORY_HEIGHT)];
		[(NSView *)_panelView addSubview:_accessoryView];
	}
	[self fn_layout];
}

- (NSView *)accessoryView
{
	return _accessoryView;
}

- (void)attachColorList:(NSColorList *)colorList
{
	if (colorList == nil || [_colorLists containsObject:colorList]) {
		return;
	}
	[_colorLists addObject:colorList];
	if ([_picker respondsToSelector:@selector(attachColorList:)]) {
		[_picker attachColorList:colorList];
	}
	[(NSView *)_panelView setNeedsDisplay:YES];
}

- (void)detachColorList:(NSColorList *)colorList
{
	if (colorList == nil) {
		return;
	}
	if ([_picker respondsToSelector:@selector(detachColorList:)]) {
		[_picker detachColorList:colorList];
	}
	[_colorLists removeObject:colorList];
	[(NSView *)_panelView setNeedsDisplay:YES];
}

/* ============================================================================================ *
 * THE DRAG.                                                                                     *
 * ============================================================================================ */

- (NSImage *)fn_swatchImageForColor:(NSColor *)color
{
	NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(32.0, 32.0)] autorelease];

	[image lockFocus];
	{
		NSBezierPath *face = [NSBezierPath bezierPathWithRect:NSMakeRect(0.5, 0.5, 31.0, 31.0)];

		[[color colorWithAlphaComponent:1.0] setFill];
		[face fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:1.0];
		[face stroke];
	}
	[image unlockFocus];
	return image;
}

- (BOOL)dragColor:(NSColor *)color withEvent:(NSEvent *)event fromView:(NSView *)view
{
	NSPasteboard *board;
	NSPoint origin;

	if (color == nil || event == nil || view == nil) {
		return NO;
	}
	board = [NSPasteboard pasteboardWithName:NSDragPboard];
	if (board == nil) {
		return NO;
	}
	[color writeToPasteboard:board];
	origin = [view convertPoint:[event locationInWindow] fromView:nil];
	/* **THE LEGACY DRAG DOOR IS THE ONE THAT TAKES A PASTEBOARD**, and this method has just filled one; the modern
	 * `-beginDraggingSessionWithItems:…` would make the session fill its own board from a writer, and `NSColor` is not
	 * an `NSPasteboardWriting` in this tree. */
	[view dragImage:[self fn_swatchImageForColor:color] at:origin offset:NSZeroSize event:event
	     pasteboard:board source:self slideBack:YES];
	return [NSDraggingSession cg_activeSession] != nil;
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
	(void)isLocal;
	return NSDragOperationCopy | NSDragOperationGeneric;
}

/* ============================================================================================ *
 * AND THE INSTRUMENT'S FOUR, WHICH READ WHAT THE FACE DRAWS.                                    *
 * ============================================================================================ */

- (NSUInteger)cg_chipCount
{
	return [self fn_chipCount];
}

- (NSRect)cg_chipRectAtIndex:(NSUInteger)index
{
	AGColorPanelView *view = (AGColorPanelView *)_panelView;

	return [view fn_chipRectAtIndex:index];
}

- (NSColorPicker *)cg_picker
{
	return _picker;
}

- (NSView *)cg_pickerView
{
	return ([_picker respondsToSelector:@selector(provideNewView:)]) ? [_picker provideNewView:NO] : nil;
}

@end
