/*
 * NSTabView — a set of panes with tabs along one edge.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The pair is one object graph: the view owns the items, an item owns its pane, and exactly one pane is IN the view's
 * hierarchy. Selection is the whole behaviour — everything else is geometry (where the strip is and what is left for the
 * pane) or ink (the bezel, the tabs and their labels).
 */
#import "NSTabView.h"
#import "NSColor.h"
#import "NSFont.h"
#import "NSBezierPath.h"
#import "NSGraphics.h"
#import "NSGraphicsContext.h"
#import "NSStringDrawing.h"
#import "NSAttributedString.h"
#import "NSView.h"

/* THE THREE NUMBERS A TAB STRIP IS MADE OF: the padding either side of a label, the gap between tabs, and the least width a
 * tab may have. */
#define AG_TAB_PADDING 9.0
#define AG_TAB_MIN_WIDTH 42.0

@implementation NSTabViewItem

- (instancetype)initWithIdentifier:(id)identifier
{
	self = [super init];
	if (self != nil) {
		_identifier = [identifier retain];
		_label = [@"" retain];
		_tabState = NSBackgroundTab;
	}
	return self;
}

- (void)dealloc
{
	[_identifier release];
	[_label release];
	[_view release];
	[_color release];
	[_toolTip release];
	[super dealloc];
}

- (id)identifier { return _identifier; }
- (void)setIdentifier:(id)identifier
{
	id held = [identifier retain];

	[_identifier release];
	_identifier = held;
}

- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)label
{
	NSString *held = [(label != nil) ? label : @"" copy];

	[_label release];
	_label = held;
	[[self tabView] setNeedsDisplay:YES];
}

- (NSView *)view { return _view; }
- (void)setView:(NSView *)view
{
	NSView *held = [view retain];

	[_view release];
	_view = held;
}

- (NSColor *)color { return _color; }
- (void)setColor:(NSColor *)color
{
	NSColor *held = [color retain];

	[_color release];
	_color = held;
	[[self tabView] setNeedsDisplay:YES];
}

- (NSString *)toolTip { return _toolTip; }
- (void)setToolTip:(NSString *)toolTip
{
	NSString *held = [toolTip copy];

	[_toolTip release];
	_toolTip = held;
}

- (NSView *)initialFirstResponder { return _initialFirstResponder; }
- (void)setInitialFirstResponder:(NSView *)view { _initialFirstResponder = view; }

- (NSTabView *)tabView { return _tabView; }
- (NSTabState)tabState { return _tabState; }

/* **THE LABEL'S MEASURE IS THE LABEL'S OWN**, with the tab's padding added; the `shouldTruncateLabel` flag is taken and
 * answered the same way, because this tier never truncates (it grows the strip instead, which `-minimumSize` reports). */
- (NSSize)sizeOfLabel:(BOOL)shouldTruncateLabel
{
	NSFont *font = [[self tabView] font];
	NSSize size;

	(void)shouldTruncateLabel;
	size = [[self label] sizeWithAttributes:
		[NSDictionary dictionaryWithObject:(font != nil) ? font : [NSFont systemFontOfSize:12.0]
					   forKey:NSFontAttributeName]];
	size.width += 2.0 * AG_TAB_PADDING;
	if (size.width < AG_TAB_MIN_WIDTH) {
		size.width = AG_TAB_MIN_WIDTH;
	}
	size.height = ((font != nil) ? [font ascender] - [font descender] : 15.0) + 8.0;
	return size;
}

/* **A TAB'S INK: THE LABEL, CENTRED, IN THE COLOUR THE STATE DESERVES.** The selected tab is the window's text colour on the
 * lighter face the tab view draws under it; the others are the disabled control colour, which is what "not the one you are
 * looking at" looks like. */
- (void)drawLabel:(BOOL)shouldTruncateLabel inRect:(NSRect)tabRect
{
	NSFont *font = [[self tabView] font];
	NSDictionary *attributes;
	NSSize size;
	NSPoint where;

	(void)shouldTruncateLabel;
	font = (font != nil) ? font : [NSFont systemFontOfSize:12.0];
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:
		font, NSFontAttributeName,
		(_tabState == NSSelectedTab) ? [NSColor controlTextColor] : [NSColor disabledControlTextColor],
		NSForegroundColorAttributeName, nil];
	size = [[self label] sizeWithAttributes:attributes];
	where = NSMakePoint(NSMidX(tabRect) - size.width / 2.0,
			    NSMidY(tabRect) - (([font ascender] - [font descender]) / 2.0 - [font descender]));
	[[self label] drawAtPoint:where withAttributes:attributes];
}

@end

@implementation NSTabView

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_items = [[NSMutableArray alloc] init];
		_selectedItem = nil;
		_tabViewType = NSTopTabsBezelBorder;
		_font = [[NSFont systemFontOfSize:12.0] retain];
		_delegate = nil;
		_drawsBackground = YES;
		_allowsTruncatedLabels = YES;
		_minimumSize = NSZeroSize;
	}
	return self;
}

- (void)dealloc
{
	[_items release];
	[_font release];
	[super dealloc];
}

/* ---- THE ITEMS ------------------------------------------------------------------------------------ */

- (NSArray *)tabViewItems
{
	return [[_items copy] autorelease];
}

- (NSUInteger)numberOfTabViewItems
{
	return [_items count];
}

- (NSTabViewItem *)tabViewItemAtIndex:(NSInteger)index
{
	if (index < 0 || (NSUInteger)index >= [_items count]) {
		return nil;	/* an index past the end is an ordinary mistake, and this tree answers rather than raises */
	}
	return [_items objectAtIndex:(NSUInteger)index];
}

/* **ADDING AN ITEM ADOPTS IT**: the item's view becomes a child of this view only if the item is the selected one, and the
 * item learns which tab view it belongs to. An empty tab view selects its first item, which is what makes
 * `-addTabViewItem:` useful on its own. */
- (void)addTabViewItem:(NSTabViewItem *)tabViewItem
{
	[self insertTabViewItem:tabViewItem atIndex:(NSInteger)[_items count]];
}

- (void)insertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(NSInteger)index
{
	if (tabViewItem == nil) {
		return;
	}
	if (index < 0 || (NSUInteger)index > [_items count]) {
		index = (NSInteger)[_items count];
	}
	tabViewItem->_tabView = self;
	tabViewItem->_tabState = NSBackgroundTab;
	[_items insertObject:tabViewItem atIndex:(NSUInteger)index];
	if (_selectedItem == nil) {
		[self selectTabViewItem:tabViewItem];
	}
	[self setNeedsDisplay:YES];
}

/* **REMOVING THE SELECTED ITEM SELECTS ANOTHER**, because a tab view with items and no selection shows nothing at all. The
 * nearest remaining item takes the selection — the one after where the removed one was, or the last one if it was at the
 * end. */
- (void)removeTabViewItem:(NSTabViewItem *)tabViewItem
{
	NSUInteger index;

	if (tabViewItem == nil) {
		return;
	}
	index = [_items indexOfObjectIdenticalTo:tabViewItem];
	if (index == NSNotFound) {
		return;
	}
	{
		BOOL wasSelected = (tabViewItem == _selectedItem);

		[tabViewItem->_view removeFromSuperview];
		tabViewItem->_tabView = nil;
		tabViewItem->_tabState = NSBackgroundTab;
		[_items removeObjectAtIndex:index];
		if (wasSelected) {
			_selectedItem = nil;
			if ([_items count] > 0) {
				[self selectTabViewItemAtIndex:(NSInteger)((index < [_items count]) ? index : [_items count] - 1)];
			}
		}
	}
	[self setNeedsDisplay:YES];
}

- (NSInteger)indexOfTabViewItem:(NSTabViewItem *)tabViewItem
{
	NSUInteger index;

	if (tabViewItem == nil) {
		return NSNotFound;
	}
	index = [_items indexOfObjectIdenticalTo:tabViewItem];
	return (index == NSNotFound) ? NSNotFound : (NSInteger)index;
}

- (NSInteger)indexOfTabViewItemWithIdentifier:(id)identifier
{
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		if ([[[_items objectAtIndex:i] identifier] isEqual:identifier]) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

/* ---- THE SELECTION -------------------------------------------------------------------------------- */

- (NSTabViewItem *)selectedTabViewItem
{
	return _selectedItem;
}

/* **THE ONE PLACE THE SELECTION CHANGES, AND THE THREE DELEGATE QUESTIONS IT ASKS.** `shouldSelect` may refuse; `willSelect`
 * is the last moment before the panes swap; and after the swap `didSelect` is sent. The OLD item's view LEAVES the
 * hierarchy and the new one's arrives, which is the difference between a tab view and hidden views. */
- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem
{
	NSTabViewItem *previous = _selectedItem;

	if (tabViewItem == _selectedItem) {
		return;
	}
	if (tabViewItem != nil && [_items indexOfObjectIdenticalTo:tabViewItem] == NSNotFound) {
		return;	/* an item that is not in this view is not selectable in it */
	}
	if (tabViewItem != nil && _delegate != nil
	    && [_delegate respondsToSelector:@selector(tabView:shouldSelectTabViewItem:)]
	    && ![_delegate tabView:self shouldSelectTabViewItem:tabViewItem]) {
		return;
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tabView:willSelectTabViewItem:)]) {
		[_delegate tabView:self willSelectTabViewItem:tabViewItem];
	}
	if (previous != nil) {
		previous->_tabState = NSBackgroundTab;
		[previous->_view removeFromSuperview];
	}
	_selectedItem = tabViewItem;
	if (tabViewItem != nil) {
		tabViewItem->_tabState = NSSelectedTab;
		if (tabViewItem->_view != nil) {
			[tabViewItem->_view setFrame:[self contentRect]];
			[self addSubview:tabViewItem->_view];
		}
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(tabView:didSelectTabViewItem:)]) {
		[_delegate tabView:self didSelectTabViewItem:tabViewItem];
	}
	[self setNeedsDisplay:YES];
}

- (void)selectTabViewItemAtIndex:(NSInteger)index
{
	[self selectTabViewItem:[self tabViewItemAtIndex:index]];
}

- (void)selectTabViewItemWithIdentifier:(id)identifier
{
	NSInteger index = [self indexOfTabViewItemWithIdentifier:identifier];

	if (index != NSNotFound) {
		[self selectTabViewItemAtIndex:index];
	}
}

- (void)selectFirstTabViewItem:(id)sender
{
	(void)sender;
	[self selectTabViewItemAtIndex:0];
}

- (void)selectLastTabViewItem:(id)sender
{
	(void)sender;
	[self selectTabViewItemAtIndex:(NSInteger)[_items count] - 1];
}

/* **THE TWO THAT STEP WRAP**, because a strip is a ring: past the last tab is the first, and before the first is the last. */
- (void)selectNextTabViewItem:(id)sender
{
	NSInteger index;

	(void)sender;
	if ([_items count] == 0) {
		return;
	}
	index = [self indexOfTabViewItem:_selectedItem];
	index = (index == NSNotFound) ? 0 : index + 1;
	if (index >= (NSInteger)[_items count]) {
		index = 0;
	}
	[self selectTabViewItemAtIndex:index];
}

- (void)selectPreviousTabViewItem:(id)sender
{
	NSInteger index;

	(void)sender;
	if ([_items count] == 0) {
		return;
	}
	index = [self indexOfTabViewItem:_selectedItem];
	index = (index == NSNotFound) ? 0 : index - 1;
	if (index < 0) {
		index = (NSInteger)[_items count] - 1;
	}
	[self selectTabViewItemAtIndex:index];
}

- (void)takeSelectedTabViewItemFromSender:(id)sender
{
	NSInteger index = (sender != nil && [sender respondsToSelector:@selector(tag)]) ? [sender tag] : NSNotFound;

	if (index != NSNotFound) {
		[self selectTabViewItemAtIndex:index];
	}
}

/* ---- THE GEOMETRY --------------------------------------------------------------------------------- */

/* THE STRIP'S THICKNESS, in the axis the tabs run across: a tab's own height from `-sizeOfLabel:`. There is one number for
 * every kind because a tab's height does not depend on which edge it is on. */
- (CGFloat)cg_tabThickness
{
	NSTabViewItem *first = ([_items count] > 0) ? [_items objectAtIndex:0] : nil;

	return (first != nil) ? [first sizeOfLabel:NO].height : (([_font ascender] - [_font descender]) + 8.0);
}

- (BOOL)cg_tabsAtTop
{
	return (_tabViewType == NSTopTabsBezelBorder);
}

- (BOOL)cg_tabsAtBottom
{
	return (_tabViewType == NSBottomTabsBezelBorder);
}

- (BOOL)cg_tabsVertical
{
	return (_tabViewType == NSLeftTabsBezelBorder || _tabViewType == NSRightTabsBezelBorder);
}

/* **WHAT IS LEFT FOR THE PANE.** The border is one point on every side; the strip takes its thickness off the edge its type
 * names, and no strip at all for the three `NSNoTabs…` kinds. */
- (NSRect)contentRect
{
	NSRect bounds = [self bounds];
	CGFloat border = 1.0;
	CGFloat strip = 0.0;
	NSRect content;

	if (_tabViewType <= NSRightTabsBezelBorder) {
		strip = [self cg_tabThickness];
	}
	content = NSInsetRect(bounds, border, border);
	if (strip > 0.0) {
		if ([self cg_tabsAtTop]) {
			content.size.height -= strip;
		} else if ([self cg_tabsAtBottom]) {
			content.size.height -= strip;
			content.origin.y += strip;
		} else if (_tabViewType == NSLeftTabsBezelBorder) {
			content.size.width -= strip;
			content.origin.x += strip;
		} else {
			content.size.width -= strip;
		}
	}
	if (content.size.width < 0.0) {
		content.size.width = 0.0;
	}
	if (content.size.height < 0.0) {
		content.size.height = 0.0;
	}
	return content;
}

/* THE TAB'S RECTANGLE, laid along the strip from the top-left corner (or the left edge, for a vertical strip). */
- (NSRect)cg_rectForTabAtIndex:(NSUInteger)index
{
	NSRect bounds = [self bounds];
	CGFloat strip = [self cg_tabThickness];
	CGFloat along = 1.0;
	CGFloat thick = strip - 2.0;
	NSUInteger i;

	for (i = 0; i < index && i < [_items count]; i++) {
		along += [[_items objectAtIndex:i] sizeOfLabel:NO].width;
	}
	{
		CGFloat width = (index < [_items count]) ? [[_items objectAtIndex:index] sizeOfLabel:NO].width : AG_TAB_MIN_WIDTH;

		if ([self cg_tabsVertical]) {
			CGFloat y = [self cg_tabsAtTop] ? NSMaxY(bounds) - strip : NSMinY(bounds) + 1.0;

			if (_tabViewType == NSLeftTabsBezelBorder) {
				return NSMakeRect(NSMinX(bounds) + 1.0, NSMaxY(bounds) - along - strip + 2.0, thick, width);
			}
			return NSMakeRect(NSMaxX(bounds) - strip + 1.0, NSMaxY(bounds) - along - strip + 2.0, thick, width);
			(void)y;
		}
		if ([self cg_tabsAtBottom]) {
			return NSMakeRect(NSMinX(bounds) + along, NSMinY(bounds) + 1.0, width, thick);
		}
		return NSMakeRect(NSMinX(bounds) + along, NSMaxY(bounds) - strip + 1.0, width, thick);
	}
}

- (NSTabViewItem *)tabViewItemAtPoint:(NSPoint)point
{
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		if (NSPointInRect(point, [self cg_rectForTabAtIndex:i])) {
			return [_items objectAtIndex:i];
		}
	}
	return nil;
}

/* **THE LEAST SIZE**: every tab's width plus the borders, by the strip's thickness plus a pane's smallest sensible height. */
- (NSSize)minimumSize
{
	CGFloat along = 2.0;
	NSInteger i;

	if (_minimumSize.width > 0.0 || _minimumSize.height > 0.0) {
		return _minimumSize;
	}
	for (i = 0; i < (NSInteger)[_items count]; i++) {
		along += [[_items objectAtIndex:(NSUInteger)i] sizeOfLabel:NO].width;
	}
	if ([self cg_tabsVertical]) {
		return NSMakeSize([self cg_tabThickness] + 2.0, along);
	}
	return NSMakeSize(along, [self cg_tabThickness] + 40.0);
}

/* ---- THE FACE ------------------------------------------------------------------------------------- */

- (NSTabViewType)tabViewType { return _tabViewType; }
- (void)setTabViewType:(NSTabViewType)tabViewType
{
	_tabViewType = tabViewType;
	if (_selectedItem != nil && _selectedItem->_view != nil) {
		[_selectedItem->_view setFrame:[self contentRect]];
	}
	[self setNeedsDisplay:YES];
}

- (NSFont *)font { return _font; }
- (void)setFont:(NSFont *)font
{
	NSFont *held = [(font != nil) ? font : [NSFont systemFontOfSize:12.0] retain];

	[_font release];
	_font = held;
	[self setNeedsDisplay:YES];
}

- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)flag { _drawsBackground = flag ? YES : NO; [self setNeedsDisplay:YES]; }
- (BOOL)allowsTruncatedLabels { return _allowsTruncatedLabels; }
- (void)setAllowsTruncatedLabels:(BOOL)flag { _allowsTruncatedLabels = flag ? YES : NO; }

- (id <NSTabViewDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id <NSTabViewDelegate>)delegate { _delegate = delegate; }	/* NOT RETAINED */
- (NSControlSize)controlSize { return NSRegularControlSize; }
- (void)setControlSize:(NSControlSize)controlSize { (void)controlSize; }
- (NSControlTint)controlTint { return NSDefaultControlTint; }
- (void)setControlTint:(NSControlTint)controlTint { (void)controlTint; }

/* ---- THE INK ------------------------------------------------------------------------------------ */

/* **THE BEZEL, THEN THE TABS, THEN THE SELECTED TAB'S LABEL LAST.** The selected tab is drawn with the pane's own face so it
 * reads as one piece with the content; the others wear the control face. A tab whose item has a colour uses it, which is the
 * one per-tab choice the era gives a caller. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = [self bounds];
	NSRect content = [self contentRect];
	NSBezierPath *bezel;
	NSUInteger i;

	(void)dirtyRect;
	if (_drawsBackground) {
		[[NSColor windowBackgroundColor] setFill];
		NSRectFill(bounds);
	}
	/* THE PANE'S FACE, THEN ITS BORDER. */
	if (_drawsBackground) {
		[[NSColor controlBackgroundColor] setFill];
		NSRectFill(content);
	}
	if (_tabViewType != NSNoTabsNoBorder) {
		[[NSColor controlDarkShadowColor] setStroke];
		bezel = [NSBezierPath bezierPathWithRect:NSInsetRect(bounds, 0.5, 0.5)];
		[bezel stroke];
	}
	/* THE TABS, back to front so the selected one is drawn last and its label is on top. */
	for (i = 0; i < [_items count]; i++) {
		NSTabViewItem *item = [_items objectAtIndex:i];
		NSRect tab = [self cg_rectForTabAtIndex:i];
		NSRect face = NSInsetRect(tab, 0.0, 1.0);

		if (item != _selectedItem) {
			[( (item->_color != nil) ? item->_color : [NSColor controlColor]) setFill];
			NSRectFill(face);
		}
	}
	{
		NSInteger selectedIndex = [self indexOfTabViewItem:_selectedItem];

		if (selectedIndex != NSNotFound) {
			NSRect tab = [self cg_rectForTabAtIndex:(NSUInteger)selectedIndex];
			NSTabViewItem *item = _selectedItem;

			[( (item->_color != nil) ? item->_color : [NSColor controlBackgroundColor]) setFill];
			NSRectFill(tab);
			/* AND ITS OUTLINE, WHICH IS WHAT MAKES IT READ AS RAISED. */
			[[NSColor controlDarkShadowColor] setStroke];
			[[NSBezierPath bezierPathWithRect:NSInsetRect(tab, 0.5, 0.5)] stroke];
		}
	}
	for (i = 0; i < [_items count]; i++) {
		NSTabViewItem *item = [_items objectAtIndex:i];
		NSRect tab = [self cg_rectForTabAtIndex:i];

		[item drawLabel:YES inRect:tab];
	}
}

/* **A CLICK ON A TAB SELECTS IT; A CLICK ANYWHERE ELSE IS THE PANE'S.** Which is the whole gesture: the strip is the tab
 * view's, the content is its child's. */
- (void)mouseDown:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSTabViewItem *item = [self tabViewItemAtPoint:point];

	if (item != nil) {
		[self selectTabViewItem:item];
		return;
	}
	[super mouseDown:event];
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	if (_selectedItem != nil && _selectedItem->_view != nil) {
		[_selectedItem->_view setFrame:[self contentRect]];
	}
}

@end
