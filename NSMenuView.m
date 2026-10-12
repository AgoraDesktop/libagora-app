/*
 * NSMenuView.m — laying out rows and calling the cells that draw them.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 */

#import "NSMenuView.h"
#import "NSMenu.h"
#import "NSMenuItem.h"
#import "NSMenuItemCell.h"
#import "NSColor.h"
#import "NSBezierPath.h"

#import <Foundation/NSArray.h>

const CGFloat NSMenuRowHeight = 22.0;

/* THE HIGHLIGHT, IN THE COLOUR `NSMenu`'s own hand-drawn pass used — so that the day this view replaces that pass,
 * the menu does not change colour. */
#define APPKIT_MENU_HIGHLIGHT_RED   0.16
#define APPKIT_MENU_HIGHLIGHT_GREEN 0.35
#define APPKIT_MENU_HIGHLIGHT_BLUE  0.72

@implementation NSMenuView

- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_cells = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_cells release];
	[super dealloc];
}

- (void)setMenu:(NSMenu *)menu
{
	/* A MENU THAT CHANGED IS A LAYOUT THAT CHANGED, so the cells go with it: keeping them would keep the widths
	 * measured from the OLD items and lay the new ones out in the old item's columns. */
	_shownMenu = menu;
	[_cells removeAllObjects];
	[self setNeedsDisplay:YES];
}

- (NSMenu *)menu
{
	return _shownMenu;
}

- (NSMenuItemCell *)cellForItemAtIndex:(NSInteger)index
{
	NSMenuItem *item = [_shownMenu itemAtIndex:index];
	NSMenuItemCell *cell;

	if (item == nil) {
		return nil;
	}
	while ((NSInteger)[_cells count] <= index) {
		[_cells addObject:[NSNull null]];
	}
	cell = [_cells objectAtIndex:(NSUInteger)index];
	if ((id)cell == [NSNull null]) {
		cell = [[NSMenuItemCell alloc] initTextCell:@""];
		[cell setMenuItem:item];
		/* **MEASURED ONCE, HERE.** `-calcSize` reads `-needsSizing`, so this is the flag that makes the
		 * measurement happen rather than a call that happens to work the first time. */
		[cell setNeedsSizing:YES];
		[cell calcSize];
		[_cells replaceObjectAtIndex:(NSUInteger)index withObject:cell];
		[cell release];
	}
	return cell;
}

- (NSRect)rectForRowAtIndex:(NSInteger)index
{
	NSRect bounds = [self bounds];

	/* **THE FIRST ITEM IS THE TOP ROW, WHICH IS THE CONVERSION WORTH WRITING DOWN.** A menu's item 0 is the row
	 * the reader sees first, at the TOP; a view's coordinates are Cocoa's and run UP from the bottom. So the row
	 * index counts down while the y counts up, and `-rowHeight` is the whole of the relationship. */
	return NSMakeRect(0.0, bounds.size.height - (CGFloat)(index + 1) * NSMenuRowHeight, bounds.size.width,
			  NSMenuRowHeight);
}

- (void)setHighlightedItem:(NSMenuItem *)item
{
	_highlightedItem = item;
	[self setNeedsDisplay:YES];
}

- (NSMenuItem *)highlightedItem
{
	return _highlightedItem;
}

- (BOOL)isHorizontal
{
	return _horizontal;
}

- (void)setHorizontal:(BOOL)flag
{
	_horizontal = flag;
	[self setNeedsDisplay:YES];
}

- (CGFloat)requiredHeight
{
	NSInteger count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;
	CGFloat height = (CGFloat)count * NSMenuRowHeight;

	return (height < NSMenuRowHeight) ? NSMenuRowHeight : height;
}

/* **THE ROW'S OWN BACKGROUND, DRAWN BY THE VIEW RATHER THAN BY THE CELL — WHICH IS THE RULE, NOT A SHORTCUT.**
 * `NSMenuItemCell -drawBorderAndBackgroundWithFrame:inView:` refuses on exactly this ground: the highlight and the
 * background are THE MENU VIEW'S, because a bar's rows and a dropdown's rows are different objects. The cell draws
 * its own parts; the view draws what the parts sit on. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;
	NSRect bounds = [self bounds];

	(void)dirtyRect;
	[[NSColor colorWithCalibratedRed:0.94 green:0.94 blue:0.94 alpha:1.0] setFill];
	[[NSBezierPath bezierPathWithRect:bounds] fill];

	for (i = 0; i < count; i++) {
		NSMenuItem *item = [_shownMenu itemAtIndex:i];
		NSMenuItemCell *cell = [self cellForItemAtIndex:i];
		NSRect row = [self rectForRowAtIndex:i];

		if (item == nil || cell == nil) {
			continue;
		}
		if (item == _highlightedItem) {
			[[NSColor colorWithCalibratedRed:APPKIT_MENU_HIGHLIGHT_RED green:APPKIT_MENU_HIGHLIGHT_GREEN
						   blue:APPKIT_MENU_HIGHLIGHT_BLUE alpha:1.0] setFill];
			[[NSBezierPath bezierPathWithRect:row] fill];
		}
		if ([item isSeparatorItem]) {
			[cell drawSeparatorItemWithFrame:row inView:self];
			continue;
		}
		/* **AND THE TWO IMAGE DOORS ARE ASKED ONLY WHEN THERE IS AN IMAGE**, so that a menu of plain titles does
		 * not make a door that has no work print a refusal once per row per frame. A door that refuses is doing
		 * its job; a row with no image is not its caller. */
		if ([cell stateImageWidth] > 0.0) {
			[cell drawStateImageWithFrame:row inView:self];
		}
		if ([cell imageWidth] > 0.0) {
			[cell drawImageWithFrame:row inView:self];
		}
		[cell drawTitleWithFrame:row inView:self];
		[cell drawKeyEquivalentWithFrame:row inView:self];
	}
}

@end
