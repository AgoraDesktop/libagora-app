/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSSegmentedControl.h — a row of buttons that act as one control.
 *
 * **THE CONTROL IS A FORWARDER; THE CELL OWNS THE SEGMENTS.** Every door below asks the cell, for the same reason a
 * slider's do: the labels, pictures, widths, enabled flags, selection and tracking state are the FACE's business, and
 * the view is only the rectangle the face is drawn in. The one thing the control does itself is create its cell.
 *
 * **THE ERA'S SEVEN SEGMENT STYLES ARE TRANSCRIBED FROM THE 10.6 HEADER**, values included. `Automatic` is the
 * default and this tier resolves it to the rounded look; the two square styles draw square ends, and `Capsule`
 * rounds to half the height. The style changes the BEZEL, never the segment arithmetic.
 *
 * WHAT THIS SLICE DOES NOT DO: a segment's `menu` is stored and read back, but clicking a segment with a menu does
 * not yet pop that menu up — that needs a menu-tracking session per segment, and it is named here rather than left
 * to be discovered. Segment tool tips are likewise stored and not yet surfaced as window tool tips. Images, labels,
 * widths, tags, enabled flags, per-segment selection, all three tracking modes and keyboard segment movement are
 * implemented.
 *
 * Written from `NSSegmentedControl.h` and `NSSegmentedCell.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSSEGMENTEDCONTROL_H
#define APPKIT_NSSEGMENTEDCONTROL_H

#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>
#import <Foundation/NSGeometry.h>

NS_ASSUME_NONNULL_BEGIN

@class NSImage;
@class NSMenu;
@class NSString;

/* THE ERA'S SEVEN STYLES. Apple publishes the case names and their order; the values are the header's own. */
enum {
	NSSegmentStyleAutomatic = 0,
	NSSegmentStyleRounded = 1,
	NSSegmentStyleTexturedRounded = 2,
	NSSegmentStyleRoundRect = 3,
	NSSegmentStyleTexturedSquare = 4,
	NSSegmentStyleCapsule = 5,
	NSSegmentStyleSmallSquare = 6
};
typedef NSInteger NSSegmentStyle;

@interface NSSegmentedControl : NSControl <NSSecureCoding>

/* THE SEGMENTS. A count of zero is a control with no face and no track. */
- (void)setSegmentCount:(NSInteger)count;
- (NSInteger)segmentCount;

/* THE SELECTION. In `SelectOne` and `Momentary` this is the one active segment; in `SelectAny` it is the segment
 * most recently selected, while the per-segment flags carry the whole answer. -1 means none. */
- (void)setSelectedSegment:(NSInteger)selectedSegment;
- (NSInteger)selectedSegment;
- (BOOL)selectSegmentWithTag:(NSInteger)tag;

/* THE PER-SEGMENT FACE. A width of zero means "as wide as the segment's own content needs", which is Apple's rule. */
- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment;
- (CGFloat)widthForSegment:(NSInteger)segment;
- (void)setImage:(nullable NSImage *)image forSegment:(NSInteger)segment;
- (nullable NSImage *)imageForSegment:(NSInteger)segment;
- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment;
- (NSImageScaling)imageScalingForSegment:(NSInteger)segment;
- (void)setLabel:(nullable NSString *)label forSegment:(NSInteger)segment;
- (nullable NSString *)labelForSegment:(NSInteger)segment;
- (void)setMenu:(nullable NSMenu *)menu forSegment:(NSInteger)segment;
- (nullable NSMenu *)menuForSegment:(NSInteger)segment;
- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment;
- (BOOL)isSelectedForSegment:(NSInteger)segment;
- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment;
- (BOOL)isEnabledForSegment:(NSInteger)segment;

/* THE BEZEL'S SHAPE. */
- (void)setSegmentStyle:(NSSegmentStyle)segmentStyle;
- (NSSegmentStyle)segmentStyle;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSSEGMENTEDCONTROL_H */
