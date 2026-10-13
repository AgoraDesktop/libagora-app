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
/* A BAR'S ITEM IS ITS TITLE PLUS THE AIR EITHER SIDE OF IT, and a floor so that a one-letter title is still a
 * target a person can hit. Both are the bar's own measures, so they live beside the bar's drawing. */
#define APPKIT_MENUBAR_TITLE_PADDING  12.0
#define APPKIT_MENUBAR_MIN_ITEM_WIDTH 40.0

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
		/* **A BAR'S FIRST ITEM IS THE APPLICATION MENU, AND THE HIG SETS IT IN BOLD.** That is the whole of why
		 * this view is the one that decides: the first item of a HORIZONTAL menu is the application's own — put
		 * there by `NSApplication`, which is the only thing that knows the application's name — and a DROPDOWN's
		 * first row is just its first row. */
		[cell setBold:(_horizontal && index == 0)];
		/* **MEASURED ONCE, HERE.** `-calcSize` reads `-needsSizing`, so this is the flag that makes the
		 * measurement happen rather than a call that happens to work the first time. */
		[cell setNeedsSizing:YES];
		[cell calcSize];
		[_cells replaceObjectAtIndex:(NSUInteger)index withObject:cell];
		[cell release];
	}
	return cell;
}

- (CGFloat)widthForItemAtIndex:(NSInteger)index
{
	NSMenuItemCell *cell = [self cellForItemAtIndex:index];
	CGFloat width = [cell titleWidth] + 2.0 * APPKIT_MENUBAR_TITLE_PADDING;

	/* **A BAR'S ITEMS ARE AS WIDE AS THEIR TITLES, WHICH IS WHY A BAR'S LAYOUT HAS TO ASK A CELL.** A dropdown's
	 * rows are all the menu's width and their geometry is arithmetic; a bar's columns are the ITEM's, and only
	 * the cell that measured the title knows how wide that is. */
	return (width < APPKIT_MENUBAR_MIN_ITEM_WIDTH) ? APPKIT_MENUBAR_MIN_ITEM_WIDTH : width;
}

- (NSRect)rectForItemAtIndex:(NSInteger)index
{
	NSRect bounds = [self bounds];
	CGFloat offset = 0.0;
	NSInteger i;

	if (!_horizontal) {
		/* **THE FIRST ITEM IS THE TOP ROW, WHICH IS THE CONVERSION WORTH WRITING DOWN.** A menu's item 0 is the
		 * row the reader sees first, at the TOP; a view's coordinates are Cocoa's and run UP from the bottom. So
		 * the row index counts down while the y counts up. */
		return NSMakeRect(0.0, bounds.size.height - (CGFloat)(index + 1) * NSMenuRowHeight, bounds.size.width,
				  NSMenuRowHeight);
	}
	/* **AND IN A BAR THE FIRST ITEM IS THE LEFTMOST COLUMN**, running right from the left edge, each as wide as
	 * its own title. The sum is walked rather than cached because a bar has a handful of items and a cache of
	 * offsets is a second thing to keep in step with the titles that produced them. */
	for (i = 0; i < index; i++) {
		offset += [self widthForItemAtIndex:i];
	}
	/* **AND A BAR'S ITEMS ARE AS TALL AS THE BAR**, not as tall as a dropdown's row: the bar is 24 pixels and a
	 * row is 22, so an item that took a row's height would sit 2 pixels below the top of the surface it is part of
	 * — half of why the titles read as too high. */
	return NSMakeRect(offset, 0.0, [self widthForItemAtIndex:index], bounds.size.height);
}

/* **THE CLICK, AND THE ONE ARITHMETIC THAT IS NOT OBVIOUS: WHERE THE MENU GOES.** `-popUpMenuPositioningItem:`
 * takes a point in the space a WINDOW FRAME lives in — the space the popped-up menu's own window is placed in —
 * and hangs the menu BELOW that point. So the point to give it is the clicked item's BOTTOM-LEFT CORNER carried
 * from this view's coordinates into the window's, which is this window's frame origin plus the corner. Handing it
 * the view's own point instead would put every menu at the screen's top-left, which is what a coordinate-space
 * mistake always looks like.
 *
 * AND IT IS THE ITEM'S BOTTOM, NOT ITS TOP: a bar's items run the height of the bar, so their bottom edge IS the
 * bar's bottom edge, and a menu hung below that hangs below the bar rather than over it. */
- (void)mouseDown:(NSEvent *)event
{
	NSPoint p;
	NSInteger i, count;

	if (!_horizontal || _shownMenu == nil) {
		[super mouseDown:event];	/* a dropdown is tracked by NSMenu, not by clicking its rows */
		return;
	}
	/* **AND THE POINT IS CONVERTED, WHICH IS A DOOR AND NOT A COINCIDENCE.** `-locationInWindow` is the WINDOW's
	 * coordinates and the item boxes are THIS VIEW's; for a borderless window whose content fills it the two
	 * happen to agree, and a bar whose content is inset by a single pixel would then open the wrong menu — or none.
	 * `-convertPoint:fromView:` with a nil view means "from the window's", which is what this is. */
	p = [self convertPoint:[event locationInWindow] fromView:nil];
	count = [_shownMenu numberOfItems];
	for (i = 0; i < count; i++) {
		NSRect box = [self rectForItemAtIndex:i];
		NSMenuItem *item = [_shownMenu itemAtIndex:i];
		id submenu;

		if (p.x < box.origin.x || p.x > box.origin.x + box.size.width || p.y < box.origin.y ||
		    p.y > box.origin.y + box.size.height) {
			continue;
		}
		submenu = [item submenu];
		if (submenu != nil) {
			NSRect frame = [[self window] frame];

			[submenu popUpMenuPositioningItem:nil
					       atLocation:NSMakePoint(frame.origin.x + box.origin.x,
								      frame.origin.y + box.origin.y)
						 inView:nil];
		}
		return;
	}
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
	(void)event;
	return YES;
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
	if (flag == _horizontal) {
		return;
	}
	_horizontal = flag;
	/* **AND THE CELLS GO WITH IT, because which item is bold is a fact about the ORIENTATION.** A cell that was
	 * made for a dropdown carried no bold row; the same items in a bar have one. */
	[_cells removeAllObjects];
	[self setNeedsDisplay:YES];
}

- (CGFloat)requiredHeight
{
	NSInteger count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;
	CGFloat height = (CGFloat)count * NSMenuRowHeight;

	return (height < NSMenuRowHeight) ? NSMenuRowHeight : height;
}

- (CGFloat)requiredWidth
{
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;
	CGFloat width = 0.0;

	for (i = 0; i < count; i++) {
		width += [self widthForItemAtIndex:i];
	}
	return width;
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
	/* **A BAR PAINTS NO PANEL OF ITS OWN, WHICH IS WHAT MAKES IT SEAMLESS.** The strip belongs to the Window Server
	 * and the WINDOW's background colour is the strip's — told to the client as part of the bar's own description —
	 * so a view that filled its own panel here would put a rectangle of a slightly different grey across a surface
	 * meant to be one thing. MEASURED before this: the server's strip at 216,216,216 and this panel at 240,240,240.
	 * A DROPDOWN still paints its own, because a dropdown is a panel with nothing behind it. */
	if (!_horizontal) {
		[[NSColor colorWithCalibratedRed:0.94 green:0.94 blue:0.94 alpha:1.0] setFill];
		[[NSBezierPath bezierPathWithRect:bounds] fill];
	}

	for (i = 0; i < count; i++) {
		NSMenuItem *item = [_shownMenu itemAtIndex:i];
		NSMenuItemCell *cell = [self cellForItemAtIndex:i];
		NSRect row = [self rectForItemAtIndex:i];

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
		/* **AND A BAR SHOWS NO KEY EQUIVALENTS, WHICH IS THE MAC'S ANSWER AND NOT AN OMISSION.** A key equivalent
		 * belongs to the MENU a title opens, so drawing it in the title would say that Command-S opens the File
		 * menu. */
		if (!_horizontal) {
			[cell drawKeyEquivalentWithFrame:row inView:self];
		}
	}
}

@end
