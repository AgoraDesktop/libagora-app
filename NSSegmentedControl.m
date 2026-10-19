/*
 * NSSegmentedControl — a row of segments that acts as one control.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **EVERY DOOR IS A FORWARD, AND THAT IS THE CLASS.** The segments, their contents, the selection and the tracking
 * are the cell's; the view supplies a frame and a cell and asks its cell to draw. The one decision here is the
 * default height: a segmented control made with a zero-height frame gets the face's twenty-four points, because a
 * zero-height control has nothing to click.
 */
#import <AppKit/NSSegmentedControl.h>
#import <AppKit/NSSegmentedCell.h>

@implementation NSSegmentedControl

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSSegmentedCell *cell = [[NSSegmentedCell alloc] init];

		[cell setEnabled:YES];
		[self setCell:cell];
		[cell release];
		if (frameRect.size.height <= 0.0) {
			[self setFrameSize:NSMakeSize(frameRect.size.width, 24.0)];
		}
	}
	return self;
}

- (NSSegmentedCell *)fn_cell
{
	return (NSSegmentedCell *)[self cell];
}

- (void)setSegmentCount:(NSInteger)count
{
	[[self fn_cell] setSegmentCount:count];
	[self setNeedsDisplay:YES];
}

- (NSInteger)segmentCount
{
	return [[self fn_cell] segmentCount];
}

- (void)setSelectedSegment:(NSInteger)selectedSegment
{
	[[self fn_cell] setSelectedSegment:selectedSegment];
	[self setNeedsDisplay:YES];
}

- (NSInteger)selectedSegment
{
	return [[self fn_cell] selectedSegment];
}

- (BOOL)selectSegmentWithTag:(NSInteger)tag
{
	BOOL selected = [[self fn_cell] selectSegmentWithTag:tag];

	if (selected) {
		[self setNeedsDisplay:YES];
	}
	return selected;
}

- (void)setWidth:(CGFloat)width forSegment:(NSInteger)segment
{
	[[self fn_cell] setWidth:width forSegment:segment];
	[self setNeedsDisplay:YES];
}

- (CGFloat)widthForSegment:(NSInteger)segment
{
	return [[self fn_cell] widthForSegment:segment];
}

- (void)setImage:(NSImage *)image forSegment:(NSInteger)segment
{
	[[self fn_cell] setImage:image forSegment:segment];
	[self setNeedsDisplay:YES];
}

- (NSImage *)imageForSegment:(NSInteger)segment
{
	return [[self fn_cell] imageForSegment:segment];
}

- (void)setImageScaling:(NSImageScaling)scaling forSegment:(NSInteger)segment
{
	[[self fn_cell] setImageScaling:scaling forSegment:segment];
	[self setNeedsDisplay:YES];
}

- (NSImageScaling)imageScalingForSegment:(NSInteger)segment
{
	return [[self fn_cell] imageScalingForSegment:segment];
}

- (void)setLabel:(NSString *)label forSegment:(NSInteger)segment
{
	[[self fn_cell] setLabel:label forSegment:segment];
	[self setNeedsDisplay:YES];
}

- (NSString *)labelForSegment:(NSInteger)segment
{
	return [[self fn_cell] labelForSegment:segment];
}

- (void)setMenu:(NSMenu *)menu forSegment:(NSInteger)segment
{
	[[self fn_cell] setMenu:menu forSegment:segment];
	[self setNeedsDisplay:YES];
}

- (NSMenu *)menuForSegment:(NSInteger)segment
{
	return [[self fn_cell] menuForSegment:segment];
}

- (void)setSelected:(BOOL)selected forSegment:(NSInteger)segment
{
	[[self fn_cell] setSelected:selected forSegment:segment];
	[self setNeedsDisplay:YES];
}

- (BOOL)isSelectedForSegment:(NSInteger)segment
{
	return [[self fn_cell] isSelectedForSegment:segment];
}

- (void)setEnabled:(BOOL)enabled forSegment:(NSInteger)segment
{
	[[self fn_cell] setEnabled:enabled forSegment:segment];
	[self setNeedsDisplay:YES];
}

- (BOOL)isEnabledForSegment:(NSInteger)segment
{
	return [[self fn_cell] isEnabledForSegment:segment];
}

- (void)setSegmentStyle:(NSSegmentStyle)segmentStyle
{
	[[self fn_cell] setSegmentStyle:segmentStyle];
	[self setNeedsDisplay:YES];
}

- (NSSegmentStyle)segmentStyle
{
	return [[self fn_cell] segmentStyle];
}

@end
