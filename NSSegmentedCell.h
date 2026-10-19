/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSSegmentedCell.h — the face of a segmented control: its segments, their contents, and the tracking that selects.
 *
 * **THE CELL OWNS ONE RECORD PER SEGMENT.** A label, a picture, a picture-scaling rule, a width, a tag, an enabled
 * flag, a selected flag, a menu and a tool tip all belong to the segment rather than to the control, so they live in
 * an array of private segment records. The public doors are Apple's 10.6 set.
 *
 * **THE THREE TRACKING MODES ARE THREE DIFFERENT RULES, NOT THREE NAMES FOR ONE.** `SelectOne` moves the selection
 * to the segment pressed; `SelectAny` toggles that segment and leaves the others alone; `Momentary` selects only
 * while the button is held. The control's tracking loop calls the three `NSCell` hooks, and this cell commits the
 * selection in `-stopTracking:...` so the action that follows sees the new state.
 *
 * **DRAWING IS SPLIT THE WAY APPLE SPLITS IT.** `-drawWithFrame:inView:` paints the track, the selected/pressed
 * plates and the separators, then asks `-drawInteriorWithFrame:inView:` to paint each segment through
 * `-drawSegment:inFrame:withView:`. A subclass that wants custom segment content overrides that last door and keeps
 * the bezel arithmetic.
 *
 * Written from `NSSegmentedCell.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSSEGMENTEDCELL_H
#define APPKIT_NSSEGMENTEDCELL_H

#import <AppKit/NSActionCell.h>
#import <AppKit/NSSegmentedControl.h>

NS_ASSUME_NONNULL_BEGIN

/* THE THREE TRACKING MODES. `SelectOne` is zero, which is the default a zeroed cell gets. */
enum {
	NSSegmentSwitchTrackingSelectOne = 0,
	NSSegmentSwitchTrackingSelectAny = 1,
	NSSegmentSwitchTrackingMomentary = 2
};
typedef NSUInteger NSSegmentSwitchTracking;

@class NSImage;
@class NSMenu;
@class NSMutableArray;
@class NSString;

@interface NSSegmentedCell : NSActionCell
{
	NSMutableArray *_segmentItems;		/* RETAINED: one private record per segment */
	NSInteger _selectedSegment;		/* -1 means none */
	NSInteger _keySegment;			/* the segment keyboard movement is on */
	NSSegmentSwitchTracking _trackingMode;
	NSSegmentStyle _segmentStyle;
	/* THE SEGMENT THE POINTER IS PRESSING, or -1. It is what draws the pressed plate and what decides which
	 * segment a release commits. */
	NSInteger _pressedSegment;
}

- (void)setSegmentCount:(NSInteger)count;
- (NSInteger)segmentCount;

- (void)setSelectedSegment:(NSInteger)selectedSegment;
- (NSInteger)selectedSegment;
- (BOOL)selectSegmentWithTag:(NSInteger)tag;

/* KEYBOARD MOVEMENT. Both wrap; neither changes the selection by itself. */
- (void)makeNextSegmentKey;
- (void)makePreviousSegmentKey;

- (void)setTrackingMode:(NSSegmentSwitchTracking)trackingMode;
- (NSSegmentSwitchTracking)trackingMode;

- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment;
- (CGFloat)widthForSegment:(NSInteger)segment;
- (void)setImage:(nullable NSImage *)image forSegment:(NSInteger)segment;
- (nullable NSImage *)imageForSegment:(NSInteger)segment;
- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment;
- (NSImageScaling)imageScalingForSegment:(NSInteger)segment;
- (void)setLabel:(nullable NSString *)label forSegment:(NSInteger)segment;
- (nullable NSString *)labelForSegment:(NSInteger)segment;
- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment;
- (BOOL)isSelectedForSegment:(NSInteger)segment;
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment;
- (BOOL)isEnabledForSegment:(NSInteger)segment;
- (void)setMenu:(nullable NSMenu *)menu forSegment:(NSInteger)segment;
- (nullable NSMenu *)menuForSegment:(NSInteger)segment;
- (void)setToolTip:(nullable NSString *)toolTip forSegment:(NSInteger)segment;
- (nullable NSString *)toolTipForSegment:(NSInteger)segment;
- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment;
- (NSInteger)tagForSegment:(NSInteger)segment;

- (void)setSegmentStyle:(NSSegmentStyle)segmentStyle;
- (NSSegmentStyle)segmentStyle;

/* THE CONTENT HOOK. The frame is the segment's rectangle; a subclass overrides this to draw its own content. */
- (void)drawSegment:(NSInteger)segment inFrame:(NSRect)frame withView:(nullable NSView *)controlView;

/* THE BACKGROUND STYLE A CUSTOM `-drawSegment:` SHOULD USE. Dark means the segment is selected or pressed. */
- (NSBackgroundStyle)interiorBackgroundStyleForSegment:(NSInteger)segment;

/* **THE TIER'S GEOMETRY DOOR.** Apple keeps the segment rectangles private; the view and the probes need to ask
 * where a segment is, so this is the one `cg_` extension on the class. The rect is in the control's coordinates. */
- (NSRect)cg_rectForSegment:(NSInteger)segment inFrame:(NSRect)frame;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSEGMENTEDCELL_H */
