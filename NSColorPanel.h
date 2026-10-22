/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSColorPanel.h — THE SHARED COLOUR PANEL: ONE WINDOW, MANY WELLS.
 *
 * **THE PANEL IS A SINGLETON BECAUSE A COLOUR IS ONE VALUE.** Every colour well in an application opens the SAME panel;
 * the well that is active sets the panel's target and action to itself, so moving the panel's colour tells the active
 * well and nothing else. That is why `+sharedColorPanel` and `+sharedColorPanelExists` are class doors, and why the
 * target/action pair below is the PANEL's rather than any one well's.
 *
 * **THE FACE IS BUILT FROM THREE PIECES, AND EACH ONE IS A DOOR ABOVE.** A row of mode chips selects a PICKER (the
 * eight 10.6 modes; see `NSColorPicker.h` for what this tier's one picker draws), the picker's own view is hosted
 * below them, and the current colour is drawn as a swatch with an optional alpha ramp. `-setAccessoryView:` adds a
 * caller's view under all of it — Apple's contract for the door — and `-attachColorList:`/`-detachColorList:` hand a
 * palette to the picker.
 *
 * **AND TWO DOORS ARE APPLE'S CLASS METHODS RATHER THAN INSTANCE ONES.** `+setPickerMask:` and `+setPickerMode:` are
 * declared on the CLASS in 10.6, because they configure the shared panel before (or after) it exists; this tree keeps
 * that shape and applies a late call to the shared panel if it already exists. `-setMode:` is the instance door.
 *
 * WHAT THE PANEL DOES NOT DO, named at the door rather than left to be discovered: there is no wheel, slider, crayon or
 * CMYK picker behind any of the eight modes — the one picker is a palette, and the mode changes the chip — and the
 * panel does not implement `NSColorPanel`'s era `-setPickerMode:` as an instance method because 10.6 does not declare
 * one. `-dragColor:withEvent:fromView:` builds a real drag session whose pasteboard carries the colour under
 * `NSColorPboardType`; a drop target for it is the caller's.
 *
 * Written from `NSColorPanel.h` in the MacOSX10.6 SDK. The mode enum and the mask values are the header's own, declared
 * in `NSColorPicker.h` because both picker protocols take a mode.
 */
#ifndef APPKIT_NSCOLORPANEL_H
#define APPKIT_NSCOLORPANEL_H

#import <AppKit/NSPanel.h>
#import <AppKit/NSColorPicker.h>

@class NSEvent;
@class NSView;

NS_ASSUME_NONNULL_BEGIN

/* **THE EIGHT MODES' BITS, IN THE HEADER'S ORDER AND WITH ITS VALUES.** `NSColorPanelAllModesMask` is the era's
 * "everything" word rather than a sum of the eight above it, which is why it is spelled out. */
enum {
	NSColorPanelGrayModeMask = 0x00000001,
	NSColorPanelRGBModeMask = 0x00000002,
	NSColorPanelCMYKModeMask = 0x00000004,
	NSColorPanelHSBModeMask = 0x00000008,
	NSColorPanelCustomPaletteModeMask = 0x00000010,
	NSColorPanelColorListModeMask = 0x00000020,
	NSColorPanelWheelModeMask = 0x00000040,
	NSColorPanelCrayonModeMask = 0x00000080,
	NSColorPanelAllModesMask = 0x0000ffff
};
typedef NSUInteger NSColorPanelModeMask;

@interface NSColorPanel : NSPanel <NSDraggingSource>
{
	NSColor *_color;			/* RETAINED */
	NSColorPanelMode _mode;
	NSUInteger _pickerMask;
	BOOL _showsAlpha;
	BOOL _continuous;
	id _target;				/* ASSIGN */
	SEL _action;
	NSView *_accessoryView;			/* RETAINED */
	NSMutableArray *_colorLists;		/* RETAINED: attached NSColorList objects */
	NSMutableDictionary *_pickers;		/* RETAINED: mode number -> NSColorPicker */
	NSColorPicker *_picker;			/* ASSIGN: the one in the window */
	NSMutableArray *_chipCells;		/* RETAINED: NSButtonCell, one per offered mode */
	NSMutableArray *_chipModes;		/* RETAINED: NSNumber, the mode each chip selects */
	id _panelView;				/* RETAINED: the private content view */
}

/* THE SINGLETON AND THE TWO CLASS CONFIGURATIONS. `+sharedColorPanelExists` answers without creating one, which is what
 * a caller that only wants to know whether to close it needs. */
+ (NSColorPanel *)sharedColorPanel;
+ (BOOL)sharedColorPanelExists;
+ (void)setPickerMask:(NSUInteger)mask;
+ (void)setPickerMode:(NSColorPanelMode)mode;

/* THE COLOUR AND ITS ALPHA. `-alpha` is the colour's own alpha component rather than a second field, because a panel
 * whose alpha could disagree with its colour would put two numbers behind one swatch. */
- (void)setColor:(NSColor *)color;
- (NSColor *)color;
- (CGFloat)alpha;

/* WHETHER THE ALPHA RAMP IS SHOWN, AND WHETHER A CHANGE SPEAKS CONTINUOUSLY. */
- (void)setShowsAlpha:(BOOL)flag;
- (BOOL)showsAlpha;
- (void)setContinuous:(BOOL)flag;
- (BOOL)isContinuous;

/* THE TARGET AND THE ACTION THE PANEL SENDS WHEN ITS COLOUR CHANGES. The ACTIVE WELL sets these to itself. */
- (void)setTarget:(nullable id)target;
- (nullable id)target;
- (void)setAction:(nullable SEL)action;
- (nullable SEL)action;

/* THE MODE THE PANEL IS SHOWING, AND THE PICKER IT SHOWS FOR IT. */
- (void)setMode:(NSColorPanelMode)mode;
- (NSColorPanelMode)mode;

/* A CALLER'S VIEW UNDER THE PICKER, AND THE PALETTES THE PICKER OFFERS. */
- (void)setAccessoryView:(nullable NSView *)aView;
- (nullable NSView *)accessoryView;
- (void)attachColorList:(NSColorList *)colorList;
- (void)detachColorList:(NSColorList *)colorList;

/* **AND THE DRAG.** The colour goes onto `NSDragPboard` under `NSColorPboardType`, a swatch image is made for the
 * pointer, and the session begins from `fromView` — the legacy `-dragImage:…pasteboard:…` door, because the pasteboard
 * has to be the one this method filled. The answer is whether a session began, which is NO when there is no window to
 * drag from or another drag is already running. */
- (BOOL)dragColor:(NSColor *)color withEvent:(NSEvent *)event fromView:(NSView *)view;

/* ============================================================================================ *
 * THE INSTRUMENT'S DOORS, NOT APPLE'S — the `cg_` prefix this tier uses for a door that exists   *
 * because a probe has to DRIVE or READ what a session merely performs. The chip row is drawn by   *
 * the panel's private content view and hit-tested there, so a probe that wants to click a chip    *
 * needs its rectangle; and the picker's view is a subview a probe needs to reach to click a cell. *
 * ============================================================================================ */
- (NSUInteger)cg_chipCount;
- (NSRect)cg_chipRectAtIndex:(NSUInteger)index;
- (nullable NSColorPicker *)cg_picker;
- (nullable NSView *)cg_pickerView;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLORPANEL_H */
