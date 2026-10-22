/*
 * NSSegmentedCell — the face and the tracking of a row of segments.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A SEGMENT IS A RECORD, NOT A VIEW.** Each one carries a label, an image, an image-scaling rule, a width, a tag,
 * an enabled flag, a selected flag, a menu and a tool tip. The cell keeps those records in one array and derives the
 * whole geometry from them: a width of zero means the segment measures its own content, a frame wider than the
 * natural total gives the surplus to the auto-sized segments, and a frame narrower than it scales the row to fit.
 *
 * **THE THREE TRACKING MODES COMMIT IN `-stopTracking:`.** The control's loop calls `-startTrackingAt:`,
 * `-continueTracking:` and `-stopTracking:`; this cell uses the first two to follow the pointer and the last to
 * commit, which is the point at which the control is about to send the action. `SelectOne` moves the selection,
 * `SelectAny` toggles one segment, and `Momentary` exposes the pressed segment to the action while drawing it only
 * for the duration of the press.
 *
 * **THE BEZEL AND THE CONTENT ARE TWO DOORS.** `-drawWithFrame:` paints the track, the selected/pressed plates and
 * the separators, then asks `-drawInteriorWithFrame:` to call `-drawSegment:inFrame:withView:` for each segment. A
 * subclass that wants custom segment content overrides the last door and keeps the arithmetic.
 */
#import <AppKit/NSSegmentedCell.h>

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSView.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <math.h>
#include <stdlib.h>

/* THE FACE'S OWN MEASURES, named rather than repeated. A segment's label gets eight points of air on each side; an
 * image gets a sixteen-point box; and the track is twenty-four points tall unless the caller's frame says otherwise.
 * A width of zero is Apple's "autosize to fit", and the natural measure is the one used for it. */
#define AG_SEGMENT_HEIGHT		24.0
#define AG_SEGMENT_PADDING		8.0
#define AG_SEGMENT_IMAGE_BOX		16.0
#define AG_SEGMENT_IMAGE_GAP		4.0
#define AG_SEGMENT_MIN_WIDTH		12.0
#define AG_SEGMENT_CONTENT_INSET	2.0

/* THE PRIVATE RECORD. It is a class rather than a dictionary so an image and a menu are retained by the segment that
 * owns them and released at the same moment, and so a typo in a dictionary key cannot turn into a silent nil. */
@interface AGSegmentItem : NSObject
{
@public
	NSString *label;		/* COPIED */
	NSImage *image;			/* RETAINED */
	NSMenu *menu;			/* RETAINED */
	NSString *toolTip;		/* COPIED */
	CGFloat width;			/* 0 means autosize */
	NSInteger tag;
	BOOL enabled;
	BOOL selected;
	NSImageScaling imageScaling;
}
@end

@implementation AGSegmentItem

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		label = nil;
		image = nil;
		menu = nil;
		toolTip = nil;
		width = 0.0;
		tag = 0;
		enabled = YES;
		selected = NO;
		imageScaling = NSImageScaleProportionallyDown;
	}
	return self;
}

- (void)dealloc
{
	[label release];
	[image release];
	[menu release];
	[toolTip release];
	[super dealloc];
}

@end

static NSFont *fn_segment_font(void)
{
	return [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

static CGFloat fn_segment_radius(NSSegmentStyle style, NSRect frame)
{
	switch (style) {
	case NSSegmentStyleSmallSquare:
	case NSSegmentStyleTexturedSquare:
		return 0.0;
	case NSSegmentStyleCapsule:
		return frame.size.height / 2.0;
	case NSSegmentStyleAutomatic:
	case NSSegmentStyleRounded:
	case NSSegmentStyleTexturedRounded:
	case NSSegmentStyleRoundRect:
	default:
		return NS_CELL_BEZEL_RADIUS;
	}
}

static NSRect fn_image_rect_in_box(NSImage *image, NSRect box, NSImageScaling scaling)
{
	NSSize natural;
	NSRect result;
	CGFloat scale;

	if (image == nil) {
		return NSZeroRect;
	}
	natural = [image size];
	if (natural.width <= 0.0 || natural.height <= 0.0) {
		return NSZeroRect;
	}
	if (scaling == NSImageScaleNone) {
		result.size = natural;
		result.origin.x = box.origin.x + (box.size.width - natural.width) / 2.0;
		result.origin.y = box.origin.y + (box.size.height - natural.height) / 2.0;
		return result;
	}
	if (scaling == NSImageScaleAxesIndependently) {
		return box;
	}
	scale = fmin(box.size.width / natural.width, box.size.height / natural.height);
	if (scaling == NSImageScaleProportionallyDown && scale > 1.0) {
		scale = 1.0;
	}
	result.size.width = natural.width * scale;
	result.size.height = natural.height * scale;
	result.origin.x = box.origin.x + (box.size.width - result.size.width) / 2.0;
	result.origin.y = box.origin.y + (box.size.height - result.size.height) / 2.0;
	return result;
}

@implementation NSSegmentedCell

/* ============================================================================================
 * ARCHIVING: THE SEGMENTS, AS PLIST VALUES RATHER THAN AS THE PRIVATE RECORD.
 * ============================================================================================ */
/* **THE PRIVATE `AGSegmentItem` IS DELIBERATELY NOT IN THE ARCHIVE.** It is this file's storage layout, and a format is
 * not a place to publish one: a design file that named it would break the day the record changed, and the reader would
 * have to allow a class nothing outside this file can construct. So each segment is written as a DICTIONARY of the eight
 * things a segment IS — the label, the image, the menu, the tool tip, the width, the tag, whether it is enabled and
 * whether it is selected, and how the image scales — and decoded back into the record. The archive names only classes
 * the format publishes. */
static NSString * const AGCoderSegmentsKey = @"segmentItems";
static NSString * const AGCoderSegmentSelectedKey = @"selectedSegment";
static NSString * const AGCoderSegmentKeySegmentKey = @"keySegment";
static NSString * const AGCoderSegmentTrackingKey = @"trackingMode";
static NSString * const AGCoderSegmentStyleKey = @"segmentStyle";

/* THE EIGHT KEYS OF A SEGMENT'S DICTIONARY, whose values are their own names. */
static NSString * const AGSegmentLabelKey = @"label";
static NSString * const AGSegmentImageKey = @"image";
static NSString * const AGSegmentMenuKey = @"menu";
static NSString * const AGSegmentToolTipKey = @"toolTip";
static NSString * const AGSegmentWidthKey = @"width";
static NSString * const AGSegmentTagKey = @"tag";
static NSString * const AGSegmentEnabledKey = @"enabled";
static NSString * const AGSegmentSelectedKey = @"selected";
static NSString * const AGSegmentScalingKey = @"imageScaling";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	NSMutableArray *records = [[NSMutableArray alloc] init];
	NSUInteger i;

	[super encodeWithCoder:aCoder];
	for (i = 0; i < [_segmentItems count]; i++) {
		AGSegmentItem *item = (AGSegmentItem *)[_segmentItems objectAtIndex:i];
		NSMutableDictionary *record = [[NSMutableDictionary alloc] init];

		if (item->label != nil) {
			[record setObject:item->label forKey:AGSegmentLabelKey];
		}
		if (item->image != nil) {
			[record setObject:item->image forKey:AGSegmentImageKey];
		}
		if (item->menu != nil) {
			[record setObject:item->menu forKey:AGSegmentMenuKey];
		}
		if (item->toolTip != nil) {
			[record setObject:item->toolTip forKey:AGSegmentToolTipKey];
		}
		[record setObject:[NSNumber numberWithDouble:(double)item->width] forKey:AGSegmentWidthKey];
		[record setObject:[NSNumber numberWithInteger:item->tag] forKey:AGSegmentTagKey];
		[record setObject:[NSNumber numberWithBool:item->enabled] forKey:AGSegmentEnabledKey];
		[record setObject:[NSNumber numberWithBool:item->selected] forKey:AGSegmentSelectedKey];
		[record setObject:[NSNumber numberWithInteger:(NSInteger)item->imageScaling]
			   forKey:AGSegmentScalingKey];
		[records addObject:record];
		[record release];
	}
	[aCoder encodeObject:records forKey:AGCoderSegmentsKey];
	[records release];
	[aCoder encodeInteger:_selectedSegment forKey:AGCoderSegmentSelectedKey];
	[aCoder encodeInteger:_keySegment forKey:AGCoderSegmentKeySegmentKey];
	[aCoder encodeInteger:(NSInteger)_trackingMode forKey:AGCoderSegmentTrackingKey];
	[aCoder encodeInteger:(NSInteger)_segmentStyle forKey:AGCoderSegmentStyleKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	_segmentItems = [[NSMutableArray alloc] init];
	if ([aDecoder containsValueForKey:AGCoderSegmentsKey]) {
		id records = [aDecoder decodeObjectForKey:AGCoderSegmentsKey];
		NSUInteger i;

		if ([records isKindOfClass:[NSArray class]]) {
			for (i = 0; i < [(NSArray *)records count]; i++) {
				id record = [(NSArray *)records objectAtIndex:i];
				AGSegmentItem *item;
				id value;

				if (![record isKindOfClass:[NSDictionary class]]) {
					continue;
				}
				item = [[AGSegmentItem alloc] init];
				value = [(NSDictionary *)record objectForKey:AGSegmentLabelKey];
				if ([value isKindOfClass:[NSString class]]) {
					item->label = [(NSString *)value copy];
				}
				item->image = [[(NSDictionary *)record objectForKey:AGSegmentImageKey] retain];
				item->menu = [[(NSDictionary *)record objectForKey:AGSegmentMenuKey] retain];
				value = [(NSDictionary *)record objectForKey:AGSegmentToolTipKey];
				if ([value isKindOfClass:[NSString class]]) {
					item->toolTip = [(NSString *)value copy];
				}
				value = [(NSDictionary *)record objectForKey:AGSegmentWidthKey];
				if ([value isKindOfClass:[NSNumber class]]) {
					item->width = (CGFloat)[(NSNumber *)value doubleValue];
				}
				value = [(NSDictionary *)record objectForKey:AGSegmentTagKey];
				if ([value isKindOfClass:[NSNumber class]]) {
					item->tag = [(NSNumber *)value integerValue];
				}
				value = [(NSDictionary *)record objectForKey:AGSegmentEnabledKey];
				item->enabled = [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value boolValue] : YES;
				value = [(NSDictionary *)record objectForKey:AGSegmentSelectedKey];
				if ([value isKindOfClass:[NSNumber class]]) {
					item->selected = [(NSNumber *)value boolValue];
				}
				value = [(NSDictionary *)record objectForKey:AGSegmentScalingKey];
				if ([value isKindOfClass:[NSNumber class]]) {
					item->imageScaling = (NSImageScaling)[(NSNumber *)value integerValue];
				}
				[_segmentItems addObject:item];
				[item release];
			}
		}
	}
	if ([aDecoder containsValueForKey:AGCoderSegmentSelectedKey]) {
		_selectedSegment = [aDecoder decodeIntegerForKey:AGCoderSegmentSelectedKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSegmentKeySegmentKey]) {
		_keySegment = [aDecoder decodeIntegerForKey:AGCoderSegmentKeySegmentKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSegmentTrackingKey]) {
		_trackingMode = (NSSegmentSwitchTracking)[aDecoder decodeIntegerForKey:AGCoderSegmentTrackingKey];
	}
	if ([aDecoder containsValueForKey:AGCoderSegmentStyleKey]) {
		_segmentStyle = (NSSegmentStyle)[aDecoder decodeIntegerForKey:AGCoderSegmentStyleKey];
	}
	/* THE PRESSED SEGMENT IS ABSENT, so a decoded cell has no press in progress. */
	_pressedSegment = -1;
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_segmentItems = [[NSMutableArray alloc] init];
		_selectedSegment = -1;
		_keySegment = 0;
		_trackingMode = NSSegmentSwitchTrackingSelectOne;
		_segmentStyle = NSSegmentStyleAutomatic;
		_pressedSegment = -1;
	}
	return self;
}

- (void)dealloc
{
	[_segmentItems release];
	[super dealloc];
}

/* ---- THE PRIVATE RECORD DOORS ------------------------------------------------------------------- */

- (AGSegmentItem *)cg_itemAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)[_segmentItems count]) {
		return nil;
	}
	return (AGSegmentItem *)[_segmentItems objectAtIndex:(NSUInteger)index];
}

- (void)cg_changed
{
	if (_controlView != nil && [_controlView respondsToSelector:@selector(setNeedsDisplay:)]) {
		[(NSView *)_controlView setNeedsDisplay:YES];
	}
}

- (NSSize)cg_contentSizeForItem:(AGSegmentItem *)item
{
	NSFont *font = fn_segment_font();
	CGFloat width = 0.0;
	CGFloat height = 0.0;

	if (item == nil) {
		return NSZeroSize;
	}
	if (item->image != nil) {
		NSSize is = [item->image size];

		width = (is.width > 0.0) ? is.width : AG_SEGMENT_IMAGE_BOX;
		height = (is.height > 0.0) ? is.height : AG_SEGMENT_IMAGE_BOX;
	}
	if (item->label != nil && [item->label length] > 0) {
		NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
		NSSize ls = [item->label sizeWithAttributes:attributes];

		if (width > 0.0) {
			width += AG_SEGMENT_IMAGE_GAP;
		}
		width += ls.width;
		if (ls.height > height) {
			height = ls.height;
		}
	}
	if (width <= 0.0) {
		width = AG_SEGMENT_HEIGHT;
	}
	if (height <= 0.0) {
		height = AG_SEGMENT_HEIGHT - 2.0 * AG_SEGMENT_CONTENT_INSET;
	}
	return NSMakeSize(width, height);
}

- (CGFloat)cg_naturalWidthForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];
	CGFloat content;

	if (item == nil) {
		return 0.0;
	}
	if (item->width > 0.0) {
		return item->width;
	}
	content = [self cg_contentSizeForItem:item].width + 2.0 * AG_SEGMENT_PADDING;
	return content > AG_SEGMENT_MIN_WIDTH ? content : AG_SEGMENT_MIN_WIDTH;
}

- (void)cg_widthsForFrame:(NSRect)frame widths:(CGFloat *)widths count:(NSUInteger)count
{
	NSUInteger i;
	NSUInteger automatic = 0;
	CGFloat total = 0.0;

	for (i = 0; i < count; i++) {
		AGSegmentItem *item = [self cg_itemAtIndex:(NSInteger)i];

		widths[i] = [self cg_naturalWidthForSegment:(NSInteger)i];
		total += widths[i];
		if (item == nil || item->width <= 0.0) {
			automatic++;
		}
	}
	if (count == 0 || frame.size.width <= 0.0) {
		return;
	}
	if (total <= 0.0) {
		for (i = 0; i < count; i++) {
			widths[i] = frame.size.width / (CGFloat)count;
		}
		return;
	}
	if (total < frame.size.width) {
		CGFloat surplus = frame.size.width - total;

		if (automatic > 0) {
			for (i = 0; i < count; i++) {
				AGSegmentItem *item = [self cg_itemAtIndex:(NSInteger)i];

				if (item == nil || item->width <= 0.0) {
					widths[i] += surplus / (CGFloat)automatic;
				}
			}
		} else {
			widths[count - 1] += surplus;
		}
	} else if (total > frame.size.width) {
		CGFloat scale = frame.size.width / total;

		for (i = 0; i < count; i++) {
			widths[i] *= scale;
		}
	}
}

- (NSRect)cg_rectForSegment:(NSInteger)segment inFrame:(NSRect)frame
{
	NSUInteger count = [_segmentItems count];
	CGFloat *widths;
	CGFloat x = frame.origin.x;
	NSInteger i;

	if (segment < 0 || segment >= (NSInteger)count || count == 0) {
		return NSZeroRect;
	}
	widths = (CGFloat *)malloc(sizeof(CGFloat) * count);
	[self cg_widthsForFrame:frame widths:widths count:count];
	for (i = 0; i < segment; i++) {
		x += widths[i];
	}
	{
		NSRect rect = NSMakeRect(x, frame.origin.y, widths[segment], frame.size.height);

		free(widths);
		return rect;
	}
}

- (NSInteger)cg_segmentAtPoint:(NSPoint)point inFrame:(NSRect)frame
{
	NSUInteger count = [_segmentItems count];
	CGFloat *widths;
	CGFloat x = frame.origin.x;
	NSUInteger i;
	NSInteger found = -1;

	if (count == 0 || !NSPointInRect(point, frame)) {
		return -1;
	}
	widths = (CGFloat *)malloc(sizeof(CGFloat) * count);
	[self cg_widthsForFrame:frame widths:widths count:count];
	for (i = 0; i < count; i++) {
		if (point.x >= x && (point.x < x + widths[i] || i + 1 == count)) {
			found = (NSInteger)i;
			break;
		}
		x += widths[i];
	}
	free(widths);
	return found;
}

/* ---- THE SEGMENT COUNT AND THE SELECTION --------------------------------------------------------- */

- (void)setSegmentCount:(NSInteger)count
{
	NSInteger i;

	if (count < 0) {
		count = 0;
	}
	while ((NSInteger)[_segmentItems count] < count) {
		[_segmentItems addObject:[[[AGSegmentItem alloc] init] autorelease]];
	}
	while ((NSInteger)[_segmentItems count] > count) {
		[_segmentItems removeObjectAtIndex:[_segmentItems count] - 1];
	}
	if (_selectedSegment >= count) {
		_selectedSegment = -1;
	}
	if (_keySegment >= count) {
		_keySegment = count > 0 ? count - 1 : 0;
	}
	[self cg_changed];
}

- (NSInteger)segmentCount
{
	return (NSInteger)[_segmentItems count];
}

- (void)setSelectedSegment:(NSInteger)selectedSegment
{
	NSUInteger i;

	if (selectedSegment < -1 || selectedSegment >= (NSInteger)[_segmentItems count]) {
		selectedSegment = -1;
	}
	_selectedSegment = selectedSegment;
	for (i = 0; i < [_segmentItems count]; i++) {
		AGSegmentItem *item = [_segmentItems objectAtIndex:i];

		if (_trackingMode == NSSegmentSwitchTrackingSelectOne) {
			item->selected = ((NSInteger)i == selectedSegment);
		} else if (_trackingMode == NSSegmentSwitchTrackingSelectAny && (NSInteger)i == selectedSegment) {
			item->selected = YES;
		} else if (_trackingMode == NSSegmentSwitchTrackingMomentary) {
			item->selected = NO;
		}
	}
	[self cg_changed];
}

- (NSInteger)selectedSegment
{
	if (_trackingMode == NSSegmentSwitchTrackingSelectAny) {
		NSUInteger i;

		if (_selectedSegment >= 0 && _selectedSegment < (NSInteger)[_segmentItems count]
		    && ((AGSegmentItem *)[_segmentItems objectAtIndex:(NSUInteger)_selectedSegment])->selected) {
			return _selectedSegment;
		}
		for (i = 0; i < [_segmentItems count]; i++) {
			if (((AGSegmentItem *)[_segmentItems objectAtIndex:i])->selected) {
				return (NSInteger)i;
			}
		}
		return -1;
	}
	if (_selectedSegment < 0 || _selectedSegment >= (NSInteger)[_segmentItems count]) {
		return -1;
	}
	return _selectedSegment;
}

- (BOOL)selectSegmentWithTag:(NSInteger)tag
{
	NSInteger i;

	for (i = 0; i < (NSInteger)[_segmentItems count]; i++) {
		AGSegmentItem *item = [self cg_itemAtIndex:i];

		if (item != nil && item->tag == tag && item->enabled) {
			if (_trackingMode == NSSegmentSwitchTrackingSelectAny) {
				[self setSelected:YES forSegment:i];
			} else {
				[self setSelectedSegment:i];
			}
			return YES;
		}
	}
	return NO;
}

- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item == nil) {
		return;
	}
	if (_trackingMode == NSSegmentSwitchTrackingSelectOne) {
		if (selected) {
			[self setSelectedSegment:segment];
		} else if (_selectedSegment == segment) {
			[self setSelectedSegment:-1];
		}
		return;
	}
	item->selected = selected ? YES : NO;
	if (selected) {
		_selectedSegment = segment;
	} else if (_selectedSegment == segment) {
		_selectedSegment = -1;
	}
	[self cg_changed];
}

- (BOOL)isSelectedForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item == nil) {
		return NO;
	}
	if (_trackingMode == NSSegmentSwitchTrackingMomentary) {
		return _pressedSegment == segment;
	}
	if (_trackingMode == NSSegmentSwitchTrackingSelectAny) {
		return item->selected;
	}
	return _selectedSegment == segment;
}

- (void)setTrackingMode:(NSSegmentSwitchTracking)trackingMode
{
	NSUInteger i;

	_trackingMode = trackingMode;
	if (trackingMode == NSSegmentSwitchTrackingMomentary) {
		_selectedSegment = -1;
		for (i = 0; i < [_segmentItems count]; i++) {
			((AGSegmentItem *)[_segmentItems objectAtIndex:i])->selected = NO;
		}
	} else if (trackingMode == NSSegmentSwitchTrackingSelectOne) {
		for (i = 0; i < [_segmentItems count]; i++) {
			AGSegmentItem *item = [_segmentItems objectAtIndex:i];

			item->selected = ((NSInteger)i == _selectedSegment);
		}
	}
	[self cg_changed];
}

- (NSSegmentSwitchTracking)trackingMode
{
	return _trackingMode;
}

- (void)makeNextSegmentKey
{
	NSInteger count = (NSInteger)[_segmentItems count];
	NSInteger i;

	if (count == 0) {
		return;
	}
	for (i = 1; i <= count; i++) {
		NSInteger next = (_keySegment + i) % count;
		AGSegmentItem *item = [self cg_itemAtIndex:next];

		if (item != nil && item->enabled) {
			_keySegment = next;
			[self cg_changed];
			return;
		}
	}
}

- (void)makePreviousSegmentKey
{
	NSInteger count = (NSInteger)[_segmentItems count];
	NSInteger i;

	if (count == 0) {
		return;
	}
	for (i = 1; i <= count; i++) {
		NSInteger next = (_keySegment - i) % count;
		AGSegmentItem *item;

		if (next < 0) {
			next += count;
		}
		item = [self cg_itemAtIndex:next];
		if (item != nil && item->enabled) {
			_keySegment = next;
			[self cg_changed];
			return;
		}
	}
}

/* ---- THE PER-SEGMENT FACE ----------------------------------------------------------------------- */

- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item == nil) {
		return;
	}
	item->width = width > 0.0 ? width : 0.0;
	[self cg_changed];
}

- (CGFloat)widthForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->width : 0.0;
}

- (void)setImage:(NSImage *)image forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item == nil) {
		return;
	}
	[image retain];
	[item->image release];
	item->image = image;
	[self cg_changed];
}

- (NSImage *)imageForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->image : nil;
}

- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item != nil) {
		item->imageScaling = scaling;
		[self cg_changed];
	}
}

- (NSImageScaling)imageScalingForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->imageScaling : NSImageScaleProportionallyDown;
}

- (void)setLabel:(NSString *)label forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];
	NSString *copy;

	if (item == nil) {
		return;
	}
	copy = [label copy];
	[item->label release];
	item->label = copy;
	[self cg_changed];
}

- (NSString *)labelForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->label : nil;
}

- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item != nil) {
		item->enabled = enabled ? YES : NO;
		[self cg_changed];
	}
}

- (BOOL)isEnabledForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->enabled : NO;
}

- (void)setMenu:(NSMenu *)menu forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item == nil) {
		return;
	}
	[menu retain];
	[item->menu release];
	item->menu = menu;
	[self cg_changed];
}

- (NSMenu *)menuForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->menu : nil;
}

- (void)setToolTip:(NSString *)toolTip forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];
	NSString *copy;

	if (item == nil) {
		return;
	}
	copy = [toolTip copy];
	[item->toolTip release];
	item->toolTip = copy;
}

- (NSString *)toolTipForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->toolTip : nil;
}

- (void)setTag:(NSInteger)tag forSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (item != nil) {
		item->tag = tag;
	}
}

- (NSInteger)tagForSegment:(NSInteger)segment
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	return item != nil ? item->tag : 0;
}

- (void)setSegmentStyle:(NSSegmentStyle)segmentStyle
{
	_segmentStyle = segmentStyle;
	[self cg_changed];
}

- (NSSegmentStyle)segmentStyle
{
	return _segmentStyle;
}

/* ---- MEASUREMENT -------------------------------------------------------------------------------- */

/* **`-cellSize` IS OVERRIDDEN BECAUSE THE BASE ONE ASKS THE CELL'S TYPE FIRST, AND A SEGMENTED CELL IS NOT A TEXT
 * CELL.** `NSCell -cellSize` answers its 10000x10000 "no opinion" sentinel for a null cell BEFORE it reaches
 * `-cellSizeForBounds:`, so relying on the inherited door made `-sizeToFit` set a control to 10000x10000. A segmented
 * cell has an opinion, so it asks its own measurement directly. */
- (NSSize)cellSize
{
	return [self cellSizeForBounds:NSMakeRect(0.0, 0.0, 10000.0, 10000.0)];
}

- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSUInteger count = [_segmentItems count];
	CGFloat width = 0.0;
	CGFloat height = AG_SEGMENT_HEIGHT;
	NSUInteger i;

	for (i = 0; i < count; i++) {
		width += [self cg_naturalWidthForSegment:(NSInteger)i];
	}
	if (count == 0) {
		return NSZeroSize;
	}
	if (aRect.size.height > 0.0 && aRect.size.height < height) {
		height = aRect.size.height;
	}
	if (aRect.size.width > 0.0 && width > aRect.size.width) {
		width = aRect.size.width;
	}
	return NSMakeSize(width, height);
}

/* ---- TRACKING ----------------------------------------------------------------------------------- */

- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	NSRect frame = (controlView != nil) ? [controlView bounds] : NSZeroRect;

	_pressedSegment = [self cg_segmentAtPoint:startPoint inFrame:frame];
	if (_trackingMode == NSSegmentSwitchTrackingMomentary) {
		_selectedSegment = _pressedSegment;
	}
	[self cg_changed];
	return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
	NSRect frame = (controlView != nil) ? [controlView bounds] : NSZeroRect;
	NSInteger segment = [self cg_segmentAtPoint:currentPoint inFrame:frame];

	if (segment != _pressedSegment) {
		_pressedSegment = segment;
		if (_trackingMode == NSSegmentSwitchTrackingMomentary) {
			_selectedSegment = segment;
		}
		[self cg_changed];
	}
	return YES;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
	NSRect frame = (controlView != nil) ? [controlView bounds] : NSZeroRect;
	NSInteger segment = [self cg_segmentAtPoint:stopPoint inFrame:frame];
	AGSegmentItem *item = [self cg_itemAtIndex:segment];

	if (flag && segment >= 0 && segment == _pressedSegment && item != nil && item->enabled) {
		if (_trackingMode == NSSegmentSwitchTrackingSelectOne) {
			[self setSelectedSegment:segment];
		} else if (_trackingMode == NSSegmentSwitchTrackingSelectAny) {
			item->selected = item->selected ? NO : YES;
			if (item->selected) {
				_selectedSegment = segment;
			} else if (_selectedSegment == segment) {
				_selectedSegment = -1;
			}
			[self cg_changed];
		} else {
			_selectedSegment = segment;
			[self cg_changed];
		}
	}
	_pressedSegment = -1;
	[self cg_changed];
	(void)lastPoint;
}

- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(id)controlView
{
	[super highlight:flag withFrame:cellFrame inView:controlView];
	if (!flag && _pressedSegment != -1) {
		_pressedSegment = -1;
		if (_trackingMode == NSSegmentSwitchTrackingMomentary) {
			_selectedSegment = -1;
		}
		[self cg_changed];
	}
}

/* ---- DRAWING ------------------------------------------------------------------------------------ */

- (NSBackgroundStyle)interiorBackgroundStyleForSegment:(NSInteger)segment
{
	return [self isSelectedForSegment:segment] ? NSBackgroundStyleDark : NSBackgroundStyleLight;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSUInteger count = [_segmentItems count];
	NSRect trackRect;
	NSBezierPath *track;
	CGFloat radius;
	NSUInteger i;

	if (count == 0) {
		return;
	}
	radius = fn_segment_radius(_segmentStyle, cellFrame);
	trackRect = NSInsetRect(cellFrame, 0.5, 0.5);
	track = [NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:radius yRadius:radius];

	{
		NSColor *trackFill = [self isEnabled] ? [NSColor controlColor] : [NSColor controlBackgroundColor];

		[trackFill setFill];
	}
	[track fill];

	/* THE PLATES ARE CLIPPED TO THE TRACK, so the first and last selected segments inherit the track's rounded ends
	 * instead of painting square corners over them. The current clip is intersected, not replaced. */
	[NSGraphicsContext saveGraphicsState];
	[track addClip];
	for (i = 0; i < count; i++) {
		AGSegmentItem *item = [_segmentItems objectAtIndex:i];
		BOOL active = ([self isSelectedForSegment:(NSInteger)i] || _pressedSegment == (NSInteger)i);

		if (active && item->enabled) {
			NSRect plate = [self cg_rectForSegment:(NSInteger)i inFrame:cellFrame];

			/* **THE PLATE IS THE PLATFORM'S ACCENT, NOT THE ERA'S `+selectedControlColor`.** The header's own note on
			 * `+cg_accentColor` says every control that highlights reads it — the menu's chip, a pressed button, a
			 * slider's fill, a switch's track, a text selection — and this control was one of four that still carried
			 * the era's BLUE instead, which put two different highlights in one window. The selected label's ink is
			 * `+selectedControlTextColor`, the white a pressed button wears on the same accent. */
			[[NSColor cg_accentColor] setFill];
			[[NSBezierPath bezierPathWithRect:plate] fill];
		}
	}
	/* THE SEPARATORS COME AFTER THE PLATES so a selected segment cannot erase the line to its neighbour. */
	{
		CGFloat x = cellFrame.origin.x;
		NSUInteger k;

		[[NSColor controlDarkShadowColor] setStroke];
		for (k = 0; k + 1 < count; k++) {
			x += [self cg_rectForSegment:(NSInteger)k inFrame:cellFrame].size.width;
			{
				NSBezierPath *line = [NSBezierPath bezierPath];

				[line setLineWidth:1.0];
				[line moveToPoint:NSMakePoint(x - 0.5, cellFrame.origin.y + 3.0)];
				[line lineToPoint:NSMakePoint(x - 0.5, NSMaxY(cellFrame) - 3.0)];
				[line stroke];
			}
		}
	}
	[self drawInteriorWithFrame:cellFrame inView:controlView];
	[NSGraphicsContext restoreGraphicsState];

	[[NSColor controlDarkShadowColor] setStroke];
	[track setLineWidth:1.0];
	[track stroke];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSUInteger i;

	for (i = 0; i < [_segmentItems count]; i++) {
		[self drawSegment:(NSInteger)i
			  inFrame:[self cg_rectForSegment:(NSInteger)i inFrame:cellFrame]
			 withView:(NSView *)controlView];
	}
}

- (void)drawSegment:(NSInteger)segment inFrame:(NSRect)frame withView:(NSView *)controlView
{
	AGSegmentItem *item = [self cg_itemAtIndex:segment];
	NSFont *font = fn_segment_font();
	NSColor *ink;
	NSRect content;
	NSAttributedString *labelText = nil;
	NSSize labelSize = NSZeroSize;
	NSRect imageRect = NSZeroRect;
	BOOL selected;

	(void)controlView;
	if (item == nil) {
		return;
	}
	selected = [self isSelectedForSegment:segment];
	/* **AND THE SELECTED LABEL IS DARK, ON THE ACCENT, BECAUSE THE ACCENT IS LIGHT.** The plate became
	 * `+cg_accentColor` — the sampled periwinkle (164,154,255) — and white on THAT is a wash: it is the ink a
	 * pressed button wears for the moment it is held, where the accent is a flash and nothing is read off it. A
	 * selected segment is not a flash: it is a chip that stays, and the platform's own answer for this accent is
	 * the one `NSMenuView` states — "a chip LIGHT enough to carry dark ink is exactly what that accent is". So the
	 * selected segment reads in the same ink as its neighbours and lets the plate do the saying.
	 *
	 * IT WAS `+selectedControlTextColor` (white) while the plate was the era's BLUE, and that pairing was right for
	 * a blue. A colour change is a whole pairing, not half of one. */
	if (!item->enabled) {
		ink = [NSColor disabledControlTextColor];
	} else {
		ink = [NSColor controlTextColor];
	}
	(void)selected;
	content = NSInsetRect(frame, AG_SEGMENT_PADDING, AG_SEGMENT_CONTENT_INSET);
	if (content.size.width < 0.0) {
		content.size.width = 0.0;
	}
	if (item->label != nil && [item->label length] > 0) {
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			font, NSFontAttributeName, ink, NSForegroundColorAttributeName, nil];

		labelText = [[[NSAttributedString alloc] initWithString:item->label attributes:attributes] autorelease];
		labelSize = [item->label sizeWithAttributes:attributes];
	}
	if (item->image != nil) {
		CGFloat boxWidth = AG_SEGMENT_IMAGE_BOX;

		if (labelText != nil) {
			boxWidth = fmin(AG_SEGMENT_IMAGE_BOX, content.size.width);
		}
		imageRect = fn_image_rect_in_box(item->image,
						 NSMakeRect(0.0, 0.0, boxWidth, content.size.height),
						 item->imageScaling);
	}
	{
		CGFloat total = 0.0;
		CGFloat x;

		if (item->image != nil) {
			total += imageRect.size.width;
		}
		if (labelText != nil) {
			if (total > 0.0) {
				total += AG_SEGMENT_IMAGE_GAP;
			}
			total += labelSize.width;
		}
		x = content.origin.x + (content.size.width - total) / 2.0;
		if (item->image != nil) {
			NSRect placed = imageRect;

			placed.origin.x = x;
			placed.origin.y = content.origin.y + (content.size.height - imageRect.size.height) / 2.0;
			[item->image drawInRect:placed];
			x += imageRect.size.width + (labelText != nil ? AG_SEGMENT_IMAGE_GAP : 0.0);
		}
		if (labelText != nil) {
			CGFloat ascender = [font ascender];
			CGFloat descent = (CGFloat)fabs((double)[font descender]);
			/* THE BAND'S MIDDLE IS THE CONTENT'S MIDDLE. The baseline is the middle less the half-difference
			 * between ascent and descent; MEASURED in the controls demonstration, where the y-up cell's labels
			 * sit centred in the track. */
			CGFloat baseline = NSMidY(content) - (ascender - descent) / 2.0;

			[labelText drawAtPoint:NSMakePoint(x, baseline)];
		}
	}
}

@end
