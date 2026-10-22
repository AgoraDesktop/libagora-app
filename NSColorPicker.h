/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSColorPicker.h — ONE PICKER INSIDE THE COLOUR PANEL, AND THE TWO PROTOCOLS A PICKER SPEAKS.
 *
 * **A PICKER IS THE PART OF THE COLOUR PANEL THAT IS A *CHOOSER*.** The panel owns the colour, the target and the
 * action; a picker supplies a BUTTON IMAGE for the mode chip that selects it, a VIEW that shows and changes the colour,
 * and a minimum size the panel sizes itself against. That division is why the two protocols in this header have no
 * overlap: `NSColorPickingDefault` is what EVERY picker answers (identity, its chip, its view's size, the lists the
 * panel attaches), and `NSColorPickingCustom` is what a picker that has its own view and own colour-setter answers.
 *
 * **THIS TREE SHIPS ONE PICKER, AND IT IS A PALETTE.** `NSColorPicker` itself conforms to both protocols: it draws a
 * grid of colours — the panel's attached colour lists first, then a generated hue/brightness ramp — and a click in the
 * grid sets the panel's colour. The eight 10.6 picker modes all select this one picker, which changes the CHIP and the
 * panel's label but not the grid; a caller with a real swatch/wheel picker subclasses this class, answers
 * `-provideNewView:` with its own view and `-setColor:` with its own setter, and the panel hosts it with no change to
 * the panel. READ THAT AS A STATED LIMIT: there is no built-in wheel, slider or crayon picker in this tier.
 *
 * Written from `NSColorPicker.h`, `NSColorPickingDefault.h` and `NSColorPickingCustom.h` in the MacOSX10.6 SDK. The
 * protocol members are the ones those headers declare; `NSColorPicker`'s own ten selectors are the class's.
 */
#ifndef APPKIT_NSCOLORPICKER_H
#define APPKIT_NSCOLORPICKER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSButtonCell;
@class NSColor;
@class NSColorList;
@class NSColorPanel;
@class NSImage;
@class NSMutableArray;
@class NSString;
@class NSView;

/* THE PANEL'S MODES, DECLARED WITH THE PANEL AND NAMED HERE BECAUSE BOTH PROTOCOLS TAKE ONE. The values are the
 * 10.6 header's own, and the order is its order. */
typedef enum {
	NSGrayModeColorPanel = 0,
	NSRGBModeColorPanel = 1,
	NSCMYKModeColorPanel = 2,
	NSHSBModeColorPanel = 3,
	NSCustomPaletteModeColorPanel = 4,
	NSColorListModeColorPanel = 5,
	NSWheelModeColorPanel = 6,
	NSCrayonModeColorPanel = 7
} NSColorPanelMode;

NS_ASSUME_NONNULL_BEGIN

@protocol NSColorPickingDefault <NSObject>
/* THE DOORS EVERY PICKER ANSWERS. `-initWithPickerMask:colorPanel:` is how the panel makes one; the mask is the modes
 * the panel was told to offer, so a picker can answer NO by never appearing for a mode it does not implement. */
- (nullable id)initWithPickerMask:(NSUInteger)mask colorPanel:(NSColorPanel *)owningColorPanel;
- (nullable NSImage *)provideNewButtonImage;
- (void)insertNewButtonImage:(NSImage *)newButtonImage in:(NSButtonCell *)buttonCell;
- (void)viewSizeChanged:(nullable id)sender;
- (NSSize)minContentSize;
- (nullable NSString *)buttonToolTip;
- (void)setMode:(NSColorPanelMode)mode;
- (void)attachColorList:(NSColorList *)colorList;
- (void)detachColorList:(NSColorList *)colorList;
@end

/* **AND WHAT A PICKER WITH A VIEW OF ITS OWN ANSWERS.** A picker that conforms to this protocol is hosted by the panel
 * in place of the panel's own swatch: `-provideNewView:` is asked once and the view is added to the panel's content,
 * `-setColor:` is the panel telling the picker what the current colour is, and `-supportsMode:` is how the panel
 * decides whether a mode can select this picker at all. */
@protocol NSColorPickingCustom <NSObject>
- (BOOL)supportsMode:(NSColorPanelMode)mode;
- (NSColorPanelMode)currentMode;
- (NSView *)provideNewView:(BOOL)initialRequest;
- (void)setColor:(NSColor *)newColor;
@end

@interface NSColorPicker : NSObject <NSColorPickingDefault, NSColorPickingCustom>
{
	NSColorPanel *_colorPanel;		/* ASSIGN: the panel owns its pickers */
	NSUInteger _pickerMask;
	NSColorPanelMode _mode;
	NSMutableArray *_colorLists;		/* RETAINED: the lists the panel attached */
	NSColor *_color;			/* RETAINED: the colour the panel last set */
	NSView *_view;				/* RETAINED: the grid, made on first request */
}

- (nullable id)initWithPickerMask:(NSUInteger)mask colorPanel:(NSColorPanel *)owningColorPanel;
- (nullable NSColorPanel *)colorPanel;
- (nullable NSString *)buttonToolTip;
- (nullable NSImage *)provideNewButtonImage;
- (void)insertNewButtonImage:(NSImage *)newButtonImage in:(NSButtonCell *)buttonCell;
- (NSSize)minContentSize;
- (void)viewSizeChanged:(nullable id)sender;
- (void)setMode:(NSColorPanelMode)mode;
- (void)attachColorList:(NSColorList *)colorList;
- (void)detachColorList:(NSColorList *)colorList;

/* AND THE FOUR CUSTOM DOORS, ON THIS CLASS RATHER THAN ON A SUBCLASS — the palette is this tier's only picker. */
- (BOOL)supportsMode:(NSColorPanelMode)mode;
- (NSColorPanelMode)currentMode;
- (NSView *)provideNewView:(BOOL)initialRequest;
- (void)setColor:(NSColor *)newColor;

/* **AND THE INSTRUMENT'S DOOR**: what the grid holds at an index. A probe that clicks a cell has to know which colour
 * the cell stands for, and the palette is generated — so the question is answered rather than re-derived by the test. */
- (nullable NSColor *)cg_paletteColorAtIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLORPICKER_H */
