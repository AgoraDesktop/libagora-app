/*
 * AGCandidateListView.m — a row of titles, the selected one filled, sized from the strings.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE MEASUREMENT IS THE STRING'S OWN.** `NSString -sizeWithAttributes:` is this tree's one text measurer (see
 * `NSStringDrawing.h`), so the list needs no font arithmetic of its own: a title's box is its measured width plus the
 * air either side, and the list's width is those boxes summed. The draw then centers each title in its box, which is
 * the same walk in the other direction.
 */
#import "AGCandidateListView.h"
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSStringDrawing.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

const CGFloat AGCandidateRowHeight = 22.0;
const CGFloat AGCandidatePanelPadding = 4.0;
const CGFloat AGCandidateTitlePadding = 8.0;

/* THE FONT IS ASKED ONCE PER CALL rather than cached, because a candidate list is shown briefly and a cache would be
 * a second thing to keep in step with a system font the process can change under it. */
static NSFont *fn_candidate_font(void)
{
	return [NSFont systemFontOfSize:12.0];
}

/* **THE ATTRIBUTES A CANDIDATE IS MEASURED AND DRAWN WITH.** The colour matters only to the draw; the measurement
 * would be the same either way, but passing the same dictionary to both is how the box and the title cannot disagree.
 * `NSFontAttributeName` is set only when a font came back, so a font-less process still measures and draws. */
static NSDictionary *fn_candidate_attributes(NSColor *colour)
{
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	NSFont *font = fn_candidate_font();

	if (font != nil) {
		[attrs setObject:font forKey:NSFontAttributeName];
	}
	[attrs setObject:((colour != nil) ? colour : [NSColor controlTextColor]) forKey:NSForegroundColorAttributeName];
	return attrs;
}

@implementation AGCandidateListView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_candidates = [[NSArray alloc] init];
		_selectedIndex = 0;
	}
	return self;
}

- (void)dealloc
{
	[_candidates release];
	[super dealloc];
}

- (NSArray *)candidates
{
	return _candidates;
}

- (void)setCandidates:(NSArray *)candidates
{
	NSArray *held = (candidates != nil) ? [[NSArray alloc] initWithArray:candidates] : [[NSArray alloc] init];

	[_candidates release];
	_candidates = held;
	if (_selectedIndex >= (NSInteger)[_candidates count]) {
		_selectedIndex = ([_candidates count] > 0) ? (NSInteger)[_candidates count] - 1 : 0;
	}
	[self setNeedsDisplay:YES];
}

- (NSInteger)selectedIndex
{
	return _selectedIndex;
}

- (void)setSelectedIndex:(NSInteger)index
{
	NSInteger count = (NSInteger)[_candidates count];

	if (index < 0) {
		index = (count > 0) ? count - 1 : 0;	/* a step back from the first wraps to the last */
	}
	if (index >= count) {
		index = 0;				/* and a step past the last wraps to the first */
	}
	_selectedIndex = index;
	[self setNeedsDisplay:YES];
}

/* THE WIDTH OF ONE TITLE, which every other measurement here is built from. */
- (CGFloat)cg_widthOfCandidateAtIndex:(NSInteger)index
{
	NSString *title = [_candidates objectAtIndex:(NSUInteger)index];

	return [title sizeWithAttributes:fn_candidate_attributes(nil)].width;
}

- (NSSize)cg_sizeForCandidates
{
	CGFloat width = 2.0 * AGCandidatePanelPadding;
	NSUInteger i;

	for (i = 0; i < [_candidates count]; i++) {
		width += [self cg_widthOfCandidateAtIndex:(NSInteger)i] + 2.0 * AGCandidateTitlePadding;
	}
	return NSMakeSize(width, 2.0 * AGCandidatePanelPadding + AGCandidateRowHeight);
}

- (NSRect)cg_rectForCandidateAtIndex:(NSInteger)index
{
	CGFloat x = AGCandidatePanelPadding;
	NSInteger i;

	if (index < 0 || index >= (NSInteger)[_candidates count]) {
		return NSZeroRect;
	}
	for (i = 0; i < index; i++) {
		x += [self cg_widthOfCandidateAtIndex:i] + 2.0 * AGCandidateTitlePadding;
	}
	return NSMakeRect(x, AGCandidatePanelPadding,
			  [self cg_widthOfCandidateAtIndex:index] + 2.0 * AGCandidateTitlePadding, AGCandidateRowHeight);
}

- (NSInteger)cg_indexAtPoint:(NSPoint)point
{
	NSUInteger i;

	for (i = 0; i < [_candidates count]; i++) {
		if (NSMouseInRect(point, [self cg_rectForCandidateAtIndex:(NSInteger)i], [self isFlipped])) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (BOOL)isFlipped
{
	/* THE ROW RUNS LEFT TO RIGHT AND ITS y IS THE SAME EITHER WAY, so this view takes the container's own y-down
	 * space rather than mirroring: a title drawn at the top of its box is the whole of the question. */
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	NSFont *font = fn_candidate_font();
	CGFloat fontHeight = (font != nil) ? ([font ascender] - [font descender]) : 12.0;
	NSUInteger i;

	(void)dirtyRect;
	/* THE PANEL, THEN ITS EDGE. A candidate list sits over a document, so it needs a ground of its own and a line
	 * around it, or a reading would be drawn straight onto the text it is composing. */
	[[NSColor windowBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:bounds] fill];
	[[NSColor darkGrayColor] setStroke];
	[[NSBezierPath bezierPathWithRect:NSInsetRect(bounds, 0.5, 0.5)] stroke];

	for (i = 0; i < [_candidates count]; i++) {
		NSString *title = [_candidates objectAtIndex:i];
		NSRect box = [self cg_rectForCandidateAtIndex:(NSInteger)i];
		BOOL selected = ((NSInteger)i == _selectedIndex);
		NSDictionary *attrs = fn_candidate_attributes(selected ? [NSColor whiteColor] : [NSColor controlTextColor]);
		NSSize size = [title sizeWithAttributes:attrs];
		NSPoint at;

		if (selected) {
			[[NSColor cg_accentColor] setFill];
			[[NSBezierPath bezierPathWithRect:box] fill];
		}
		/* THE BASELINE IS CENTERED BY THE FONT'S OWN METRICS: the text's box is the ascender-to-descender band, and
		 * `-drawAtPoint:` sets the BASELINE there, so the descender has to be added back. */
		at = NSMakePoint(box.origin.x + (box.size.width - size.width) / 2.0,
				 box.origin.y + (AGCandidateRowHeight - fontHeight) / 2.0 - [font descender]);
		[title drawAtPoint:at withAttributes:attrs];
	}
}

@end
