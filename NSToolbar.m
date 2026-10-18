/*
 * NSToolbar — the strip between the title bar and the content.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE VIEW IS A SUBVIEW OF THE CONTENT VIEW, AND THAT IS NOT AN ACCIDENT OF DRAWING.** The toolbar band sits above
 * the content rect, so a view at `y = content.height` is outside its superview's bounds — and `NSView`'s live draw
 * path does not clip a child to its PARENT's bounds, it clips each child to its own frame. That is what lets the
 * toolbar be a real view at a negative-looking place: its items keep a real view tree, a custom item view keeps its
 * own responder chain, and pointer events reach it through the ordinary `-hitTest:` the window already performs. The
 * alternative — painting the items from `NSWindow` — would have made every custom view a bitmap and every control
 * inside a toolbar a second hit-test implementation.
 *
 * **THE HEIGHT IS THE SIZE MODE'S.** Regular is 52 points and small is 38, the numbers the era's toolbar used. The
 * width is the window's content width, and the layout is left-to-right with the three spacers: a fixed space is eight
 * points, a flexible space shares whatever is left after every other item, and a separator is a one-point rule with
 * eight points of air on either side. Items that do not fit are CLIPPED rather than moved into an overflow menu;
 * there is no toolbar overflow menu in this tier and `-visibleItems` is the honest answer to what is on screen.
 *
 * **THE BAND IS PART OF THE CHROME, SO IT WEARS THE CHROME'S COLOUR.** It fills with `+windowFrameColor`, the same
 * ground the title bar is drawn on, and the window's black hairline is at the CONTENT's top edge — below the band —
 * rather than between the title bar and it. That is what makes the toolbar read as the chrome continuing downward:
 * the title bar and the strip are one surface, and the document starts under the one black line. The control inks
 * (and the selected item's chip) are still the application's, because the items are the application's even when the
 * surface they sit on is the window's.
 */
#import "NSToolbar.h"
#import "NSToolbarItem.h"
#import "NSToolbar_internal.h"

#import "NSApplication.h"
#import "NSBezierPath.h"
#import "NSColor.h"
#import "NSFont.h"
#import "NSGraphicsContext.h"
#import "NSImage.h"
#import "NSMenuItem.h"
#import "NSStringDrawing.h"
#import "NSView.h"
#import "NSWindow.h"
#import "AppKitRefusal.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>

#include <math.h>

/* THE NAME AN ITEM TRAVELS UNDER IN THE TWO NOTIFICATIONS. Apple's prose says the userInfo key is `@"item"`; this
 * tree's convention is that a key is an exported constant, so the string is the same and the caller gets a name. */
NSString *NSToolbarItemKey = @"item";

NSString *NSToolbarWillAddItemNotification = @"NSToolbarWillAddItemNotification";
NSString *NSToolbarDidRemoveItemNotification = @"NSToolbarDidRemoveItemNotification";

NSString *NSToolbarItemIdentifiers = @"NSToolbarItemIdentifiers";
NSString *NSToolbarSelectedItemIdentifier = @"NSToolbarSelectedItemIdentifier";
NSString *NSToolbarDisplayModeKey = @"NSToolbarDisplayMode";
NSString *NSToolbarSizeModeKey = @"NSToolbarSizeMode";
NSString *NSToolbarShowsBaselineSeparatorKey = @"NSToolbarShowsBaselineSeparator";
NSString *NSToolbarAllowsUserCustomizationKey = @"NSToolbarAllowsUserCustomization";

/* THE TWO HEIGHTS, READ AS THE SIZE MODE'S ANSWER. `Default` is regular: an unset toolbar is the ordinary one. */
static const CGFloat fn_TOOLBAR_HEIGHT_REGULAR = 52.0;
static const CGFloat fn_TOOLBAR_HEIGHT_SMALL = 38.0;

/* THE LAYOUT'S FEW MEASURES, all in points: the strip's padding, the air around a separator, and the fixed width of
 * a plain space. A flexible space has no width of its own — it is the share that is left. */
static const CGFloat fn_TOOLBAR_EDGE = 8.0;
static const CGFloat fn_TOOLBAR_ITEM_AIR = 6.0;
static const CGFloat fn_TOOLBAR_SEPARATOR_AIR = 8.0;
static const CGFloat fn_TOOLBAR_SPACE = 8.0;

static BOOL fn_is_spacer(NSString *identifier)
{
	return [identifier isEqualToString:NSToolbarSeparatorItemIdentifier] ||
	       [identifier isEqualToString:NSToolbarSpaceItemIdentifier] ||
	       [identifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier];
}

static BOOL fn_is_flexible(NSString *identifier)
{
	return [identifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier];
}

/* THE ITEM UNDER AN INDEX, WITH THE SPACERS SKIPPED BY THE CALLERS THAT ACT. The layout keeps every visible item
 * (a separator is visible and draws), while a click only means something for the ones that are not spacers. */
static BOOL fn_item_acts(NSToolbarItem *item)
{
	return !fn_is_spacer([item itemIdentifier]);
}

static NSString *fn_identifier_at(NSArray *identifiers, NSUInteger index)
{
	id value = [identifiers objectAtIndex:index];

	return [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;
}

/* THE NOTIFICATION AND THE DELEGATE, IN THE ORDER APPLE DESCRIBES: the delegate hears about a change before the
 * item is in the toolbar (for an addition) and after it is out (for a removal), and the notification is posted for
 * everyone else. `NSWindow`'s own `fn_announce` does the same pair for window notifications. */
static void fn_announce(NSToolbar *toolbar, NSString *name, NSToolbarItem *item)
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:item forKey:NSToolbarItemKey];
	NSNotification *note = [NSNotification notificationWithName:name object:toolbar userInfo:info];
	id delegate = [toolbar delegate];
	SEL selector = [name isEqualToString:NSToolbarWillAddItemNotification]
			       ? @selector(toolbarWillAddItem:)
			       : @selector(toolbarDidRemoveItem:);

	if (delegate != nil && [delegate respondsToSelector:selector]) {
		[delegate performSelector:selector withObject:note];
	}
	[[NSNotificationCenter defaultCenter] postNotification:note];
}

/* ============================================================================================ *
 * THE VIEW.                                                                                     *
 * ============================================================================================ */

@interface NSToolbarView : NSView
{
	NSToolbar *_toolbar;			/* NOT RETAINED: the toolbar owns this view */
	NSMutableArray *_layoutItems;		/* RETAINED: the items that fit, in draw order */
	NSMutableArray *_itemRects;		/* RETAINED: NSValues, parallel to `_layoutItems` */
	NSMutableArray *_hostedViews;		/* RETAINED: the custom item views this view has adopted */
	NSInteger _pressedIndex;		/* index into `_layoutItems`, or -1 */
	NSInteger _hoverIndex;
}
- (instancetype)initWithToolbar:(NSToolbar *)toolbar;
- (void)cg_relayout;
- (NSArray *)cg_visibleItems;
- (NSToolbarItem *)itemForView:(NSView *)view;
@end

/* THE FONT AND INK AN ITEM IS DRAWN IN. The size mode chooses the face; enabledness chooses the ink, which is the
 * same pair `NSButtonCell -cg_inkColor` uses for the same reason. */
static NSFont *fn_item_font(NSToolbarSizeMode mode)
{
	CGFloat size = (mode == NSToolbarSizeModeSmall) ? [NSFont smallSystemFontSize] : [NSFont systemFontSize];

	return [NSFont systemFontOfSize:size];
}

static NSColor *fn_item_ink(BOOL enabled)
{
	return enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
}

/* HOW WIDE AN ITEM'S STANDARD FACE WANTS TO BE. The custom-view case is `-cg_item_width` below because it needs the
 * view itself; this is the label-and-picture arithmetic, and it is shared by layout and drawing so the two cannot
 * disagree about where the ink goes. */
static CGFloat fn_label_width(NSToolbarItem *item, NSToolbarSizeMode mode)
{
	NSString *label = [item label];
	NSDictionary *attrs;

	if (label == nil || [label length] == 0) {
		return 0.0;
	}
	attrs = [NSDictionary dictionaryWithObjectsAndKeys:fn_item_font(mode), NSFontAttributeName,
		 fn_item_ink([item isEnabled]), NSForegroundColorAttributeName, nil];
	return [label sizeWithAttributes:attrs].width;
}

static void fn_item_rects(NSToolbarItem *item, NSRect rect, NSToolbarDisplayMode display,
			  NSToolbarSizeMode mode, NSRect *imageRect, NSRect *labelRect)
{
	BOOL small = (mode == NSToolbarSizeModeSmall);
	BOOL hasImage = ([item image] != nil);
	BOOL hasLabel = ([item label] != nil && [[item label] length] > 0);
	CGFloat icon = small ? 16.0 : 24.0;
	CGFloat labelBand = small ? 12.0 : 15.0;
	CGFloat topPad = small ? 4.0 : 6.0;
	NSToolbarDisplayMode effective = display;

	/* **A MODE THAT HAS NOTHING TO SHOW FALLS BACK TO THE THING IT HAS.** An icon-only item with no image would be an
	 * empty cell, and a label-and-icon item with no icon is a label. The fallback is the same one the toolbar's own
	 * drawing has always needed and is stated here rather than repeated at the painter. */
	if (effective == NSToolbarDisplayModeDefault) {
		effective = NSToolbarDisplayModeIconAndLabel;
	}
	if (effective == NSToolbarDisplayModeIconOnly && !hasImage) {
		effective = hasLabel ? NSToolbarDisplayModeLabelOnly : NSToolbarDisplayModeIconOnly;
	}
	if ((effective == NSToolbarDisplayModeIconAndLabel || effective == NSToolbarDisplayModeLabelOnly) && !hasLabel) {
		effective = hasImage ? NSToolbarDisplayModeIconOnly : NSToolbarDisplayModeLabelOnly;
	}

	*imageRect = NSZeroRect;
	*labelRect = NSZeroRect;
	if (effective == NSToolbarDisplayModeIconAndLabel) {
		*imageRect = NSMakeRect(rect.origin.x + (rect.size.width - icon) / 2.0,
				        rect.origin.y + rect.size.height - topPad - icon, icon, icon);
		*labelRect = NSMakeRect(rect.origin.x + fn_TOOLBAR_ITEM_AIR,
				       rect.origin.y + 3.0, rect.size.width - 2.0 * fn_TOOLBAR_ITEM_AIR, labelBand);
	} else if (effective == NSToolbarDisplayModeIconOnly) {
		*imageRect = NSMakeRect(rect.origin.x + (rect.size.width - icon) / 2.0,
				        rect.origin.y + (rect.size.height - icon) / 2.0, icon, icon);
	} else {
		*labelRect = NSMakeRect(rect.origin.x + fn_TOOLBAR_ITEM_AIR, rect.origin.y + 2.0,
				       rect.size.width - 2.0 * fn_TOOLBAR_ITEM_AIR, rect.size.height - 4.0);
	}
}

@implementation NSToolbarView

- (instancetype)initWithToolbar:(NSToolbar *)toolbar
{
	self = [super initWithFrame:NSZeroRect];
	if (self != nil) {
		_toolbar = toolbar;
		_layoutItems = [[NSMutableArray alloc] init];
		_itemRects = [[NSMutableArray alloc] init];
		_hostedViews = [[NSMutableArray alloc] init];
		_pressedIndex = -1;
		_hoverIndex = -1;
	}
	return self;
}

- (void)dealloc
{
	[_layoutItems release];
	[_itemRects release];
	[_hostedViews release];
	[super dealloc];
}

/* THE CUSTOM VIEW'S WIDTH. A view with a frame size is the natural answer; the item's min/max range is the bound,
 * with zero meaning "no bound" exactly as `NSWindow`'s min and max sizes do. */
static CGFloat fn_custom_width(NSToolbarItem *item)
{
	NSView *view = [item view];
	NSSize min = [item minSize];
	NSSize max = [item maxSize];
	NSSize natural = (view != nil) ? [view frame].size : NSZeroSize;
	CGFloat width = min.width;

	if (width <= 0.0) {
		width = (natural.width > 0.0) ? natural.width : 32.0;
	}
	if (max.width > 0.0 && width > max.width) {
		width = max.width;
	}
	return width;
}

static CGFloat fn_custom_height(NSToolbarItem *item)
{
	NSView *view = [item view];
	NSSize min = [item minSize];
	NSSize max = [item maxSize];
	NSSize natural = (view != nil) ? [view frame].size : NSZeroSize;
	CGFloat height = min.height;

	if (height <= 0.0) {
		height = (natural.height > 0.0) ? natural.height : 24.0;
	}
	if (max.height > 0.0 && height > max.height) {
		height = max.height;
	}
	return height;
}

static CGFloat fn_standard_width(NSToolbarItem *item, NSToolbarDisplayMode display, NSToolbarSizeMode mode)
{
	NSString *identifier = [item itemIdentifier];
	CGFloat label = fn_label_width(item, mode);
	BOOL hasImage = ([item image] != nil);
	BOOL hasLabel = ([item label] != nil && [[item label] length] > 0);
	NSToolbarDisplayMode effective = display;
	CGFloat icon = (mode == NSToolbarSizeModeSmall) ? 16.0 : 24.0;

	if (fn_is_spacer(identifier)) {
		if ([identifier isEqualToString:NSToolbarSeparatorItemIdentifier]) {
			return 1.0 + 2.0 * fn_TOOLBAR_SEPARATOR_AIR;
		}
		return [identifier isEqualToString:NSToolbarSpaceItemIdentifier] ? fn_TOOLBAR_SPACE : 0.0;
	}
	if (effective == NSToolbarDisplayModeDefault) {
		effective = NSToolbarDisplayModeIconAndLabel;
	}
	if (effective == NSToolbarDisplayModeIconOnly && !hasImage) {
		effective = hasLabel ? NSToolbarDisplayModeLabelOnly : NSToolbarDisplayModeIconOnly;
	}
	if ((effective == NSToolbarDisplayModeIconAndLabel || effective == NSToolbarDisplayModeLabelOnly) && !hasLabel) {
		effective = hasImage ? NSToolbarDisplayModeIconOnly : NSToolbarDisplayModeLabelOnly;
	}
	if (effective == NSToolbarDisplayModeIconOnly) {
		return (hasImage ? icon : 0.0) + 2.0 * fn_TOOLBAR_ITEM_AIR;
	}
	if (effective == NSToolbarDisplayModeLabelOnly) {
		return label + 2.0 * fn_TOOLBAR_ITEM_AIR;
	}
	return ((hasImage ? icon : 0.0) > label ? (hasImage ? icon : 0.0) : label) + 2.0 * fn_TOOLBAR_ITEM_AIR;
}

- (void)cg_relayout
{
	NSArray *items = [_toolbar items];
	NSUInteger i, count;
	CGFloat width = [self bounds].size.width;
	CGFloat height = [self bounds].size.height;
	CGFloat fixed = 2.0 * fn_TOOLBAR_EDGE;
	CGFloat flexible = 0.0;
	NSInteger flexCount = 0;
	CGFloat x = fn_TOOLBAR_EDGE;
	NSMutableArray *wantedViews = [[NSMutableArray alloc] init];

	[_layoutItems removeAllObjects];
	[_itemRects removeAllObjects];
	/* A VIEW THAT HAS NOT BEEN GIVEN A WIDTH YET CANNOT DECIDE WHAT FITS. The window sets the frame before drawing;
	 * a toolbar asked for `-visibleItems` before attachment answers every item, which is the useful answer. */
	if (width <= 0.0) {
		[_layoutItems addObjectsFromArray:items];
		for (i = 0; i < [items count]; i++) {
			[_itemRects addObject:[NSValue valueWithRect:NSZeroRect]];
		}
		[wantedViews release];
		return;
	}
	count = [items count];

	/* THE FIRST PASS MEASURES. A flexible spacer is the only item whose width is not its own, so it contributes
	 * nothing here and the leftover is divided among the flexible ones below. */
	for (i = 0; i < count; i++) {
		NSToolbarItem *item = [items objectAtIndex:i];
		NSString *identifier = [item itemIdentifier];

		if (fn_is_flexible(identifier)) {
			flexCount++;
			continue;
		}
		if ([item view] != nil) {
			fixed += fn_custom_width(item);
		} else {
			fixed += fn_standard_width(item, [_toolbar displayMode], [_toolbar sizeMode]);
		}
	}
	if (flexCount > 0) {
		CGFloat left = width - fixed - 2.0 * fn_TOOLBAR_EDGE;

		flexible = (left > 0.0) ? left / (CGFloat)flexCount : 0.0;
	}

	/* THE SECOND PASS PLACES, AND STOPS AT THE FIRST ITEM THAT DOES NOT FIT. Stopping rather than skipping is what
	 * makes `-visibleItems` a prefix of `-items`: a toolbar that skipped a wide item to show a later narrow one would
	 * be reordering itself, which is not what a clip is. */
	for (i = 0; i < count; i++) {
		NSToolbarItem *item = [items objectAtIndex:i];
		NSString *identifier = [item itemIdentifier];
		CGFloat itemWidth;

		if (fn_is_flexible(identifier)) {
			itemWidth = flexible;
		} else if ([item view] != nil) {
			itemWidth = fn_custom_width(item);
		} else {
			itemWidth = fn_standard_width(item, [_toolbar displayMode], [_toolbar sizeMode]);
		}
		if (x + itemWidth > width - fn_TOOLBAR_EDGE + 0.001) {
			break;
		}
		if (itemWidth <= 0.0 && !fn_is_spacer(identifier)) {
			/* A ZERO-WIDTH NON-SPACER WOULD BE INVISIBLE AND UNCLICKABLE, which is a size mode with nothing to say
			 * rather than an item on screen. It stays in `_items`; it is not in `_visibleItems`. */
			continue;
		}
		[_layoutItems addObject:item];
		{
			CGFloat itemHeight = height;
			CGFloat itemY = 0.0;

			/* A CUSTOM VIEW KEEPS ITS OWN HEIGHT, CENTRED IN THE BAND. A standard face fills the strip; a control a
			 * caller supplied is as tall as it said, which is the whole reason it has a min/max pair. */
			if ([item view] != nil) {
				itemHeight = fn_custom_height(item);
				if (itemHeight <= 0.0 || itemHeight > height) {
					itemHeight = height;
				}
				itemY = (height - itemHeight) / 2.0;
				[wantedViews addObject:[item view]];
			}
			[_itemRects addObject:[NSValue valueWithRect:NSMakeRect(x, itemY, itemWidth, itemHeight)]];
		}
		x += itemWidth;
	}

	/* THE CUSTOM VIEWS THAT FIT ARE ADOPTED AND THE REST ARE LET GO. `-addSubview:` moves a view out of its previous
	 * parent, so the same line adopts a view that arrived from an item inserted into another toolbar. */
	for (i = 0; i < [_hostedViews count]; ) {
		NSView *view = [_hostedViews objectAtIndex:i];

		if ([wantedViews indexOfObjectIdenticalTo:view] == NSNotFound) {
			[view removeFromSuperview];
			[_hostedViews removeObjectAtIndex:i];
		} else {
			i++;
		}
	}
	for (i = 0; i < [wantedViews count]; i++) {
		NSView *view = [wantedViews objectAtIndex:i];

		if ([view superview] != self) {
			[self addSubview:view];
		}
		if ([_hostedViews indexOfObjectIdenticalTo:view] == NSNotFound) {
			[_hostedViews addObject:view];
		}
		{
			NSToolbarItem *viewItem = [self itemForView:view];
			NSUInteger index = (viewItem != nil) ? [_layoutItems indexOfObjectIdenticalTo:viewItem] : NSNotFound;
			NSRect rect = NSZeroRect;

			if (index != NSNotFound) {
				rect = [[_itemRects objectAtIndex:index] rectValue];
			}
			[view setFrame:rect];
		}
	}
	[wantedViews release];
}

- (NSToolbarItem *)itemForView:(NSView *)view
{
	NSUInteger i;

	for (i = 0; i < [_layoutItems count]; i++) {
		NSToolbarItem *item = [_layoutItems objectAtIndex:i];

		if ([item view] == view) {
			return item;
		}
	}
	return nil;
}

- (NSArray *)cg_visibleItems
{
	return [NSArray arrayWithArray:_layoutItems];
}

- (BOOL)isFlipped
{
	return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
	(void)event;
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	CGContextRef c = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	NSRect bounds = [self bounds];
	NSToolbarDisplayMode display = [_toolbar displayMode];
	NSToolbarSizeMode mode = [_toolbar sizeMode];
	NSFont *font = fn_item_font(mode);
	NSUInteger i;

	(void)dirtyRect;
	if (c == NULL) {
		return;
	}
	/* **THE BAND IS THE CHROME'S GROUND.** `+windowFrameColor` is the colour the title bar is drawn on, so the strip
	 * reads as that surface continuing downward rather than as a control panel placed under it. The line that ends
	 * the chrome is `NSWindow`'s black hairline at the content's top edge, drawn by the chrome painter — not here,
	 * because it belongs to the whole chrome and not to this view. */
	CGContextSetFillColorWithColor(c, [[NSColor windowFrameColor] CGColor]);
	CGContextFillRect(c, CGRectMake(0.0, 0.0, bounds.size.width, bounds.size.height));

	for (i = 0; i < [_layoutItems count]; i++) {
		NSToolbarItem *item = [_layoutItems objectAtIndex:i];
		NSString *identifier = [item itemIdentifier];
		NSRect rect = [[_itemRects objectAtIndex:i] rectValue];
		BOOL selected = [[_toolbar selectedItemIdentifier] isEqualToString:identifier];
		BOOL active = ((NSInteger)i == _pressedIndex || (NSInteger)i == _hoverIndex);

		if (fn_is_spacer(identifier)) {
			if ([identifier isEqualToString:NSToolbarSeparatorItemIdentifier]) {
				CGFloat x = NSMidX(rect);

				CGContextSetFillColorWithColor(c, [[NSColor colorWithCalibratedWhite:0.55 alpha:1.0] CGColor]);
				CGContextFillRect(c, CGRectMake(x, 8.0, 1.0, bounds.size.height - 16.0));
			}
			continue;
		}
		if ([item view] != nil) {
			/* THE VIEW DRAWS ITSELF, as a real subview. The highlight is still the toolbar's, because it is the
			 * item that is selected or pressed rather than the control's own face. */
		}
		if (selected || active) {
			NSRect plate = NSInsetRect(rect, 3.0, 4.0);
			NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:plate xRadius:4.0 yRadius:4.0];

			if (active && (NSInteger)i == _pressedIndex) {
				[[NSColor selectedControlColor] setFill];
			} else if (selected) {
				[[[NSColor selectedControlColor] colorWithAlphaComponent:0.55] setFill];
			} else {
				[[NSColor controlHighlightColor] setFill];
			}
			[path fill];
		}
		if ([item view] != nil) {
			continue;
		}
		{
			NSRect imageRect, labelRect;
			NSImage *image = [item image];
			NSString *label = [item label];
			NSDictionary *attrs;

			fn_item_rects(item, rect, display, mode, &imageRect, &labelRect);
			if (image != nil && imageRect.size.width > 0.0 && imageRect.size.height > 0.0) {
				/* A DISABLED ITEM'S PICTURE DIMS WITH ITS LABEL, which is the same pairing `NSButtonCell` uses: a
				 * grey word beside a full-strength icon still looks pressable. */
				if (![item isEnabled]) {
					CGContextSetAlpha(c, 0.5);
				}
				[image drawInRect:imageRect];
				if (![item isEnabled]) {
					CGContextSetAlpha(c, 1.0);
				}
			}
			if (label == nil || [label length] == 0 || labelRect.size.width <= 0.0) {
				continue;
			}
			attrs = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
				 fn_item_ink([item isEnabled]), NSForegroundColorAttributeName, nil];
			{
				NSSize size = [label sizeWithAttributes:attrs];
				CGFloat ascender = [font ascender];
				CGFloat descent = (CGFloat)fabs((double)[font descender]);
				CGFloat baseline = labelRect.origin.y + (labelRect.size.height - (ascender + descent)) / 2.0 + descent;

				[label drawAtPoint:NSMakePoint(labelRect.origin.x + (labelRect.size.width - size.width) / 2.0,
							       baseline)
				    withAttributes:attrs];
			}
		}
	}

	/* **NO BASELINE HERE: THE WINDOW'S CHROME PAINTER OWNS THAT LINE.** It is the black hairline at the CONTENT's top
	 * edge, drawn with the rest of the chrome, and `-showsBaselineSeparator` is read there. Drawing a second line on
	 * this view's bottom row would put a two-point rule under the band and split the chrome from itself. */
}

/* ---- THE POINTER -------------------------------------------------------------------------------- */

- (NSInteger)indexAtPoint:(NSPoint)point
{
	NSUInteger i;

	for (i = 0; i < [_itemRects count]; i++) {
		NSRect rect = [[_itemRects objectAtIndex:i] rectValue];

		if (NSPointInRect(point, rect)) {
			return (NSInteger)i;
		}
	}
	return -1;
}

- (NSPoint)localPointForEvent:(NSEvent *)event
{
	NSPoint p = [event locationInWindow];
	NSPoint origin = [self frame].origin;

	return NSMakePoint(p.x - origin.x, p.y - origin.y);
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint p = [self localPointForEvent:event];
	NSInteger index = [self indexAtPoint:p];

	_pressedIndex = index;
	_hoverIndex = index;
	[self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event
{
	NSPoint p = [self localPointForEvent:event];
	NSInteger index = [self indexAtPoint:p];

	if (index != _hoverIndex) {
		_hoverIndex = index;
		[self setNeedsDisplay:YES];
	}
}

- (void)mouseUp:(NSEvent *)event
{
	NSPoint p = [self localPointForEvent:event];
	NSInteger index = [self indexAtPoint:p];
	NSInteger pressed = _pressedIndex;

	_pressedIndex = -1;
	_hoverIndex = index;
	[self setNeedsDisplay:YES];
	if (pressed >= 0 && pressed == index && (NSUInteger)pressed < [_layoutItems count]) {
		NSToolbarItem *item = [_layoutItems objectAtIndex:pressed];

		if (fn_item_acts(item) && [item isEnabled]) {
			SEL action = [item action];

			if (action != NULL) {
				[[NSApplication sharedApplication] sendAction:action to:[item target] from:item];
			}
			/* **A SELECTABLE ITEM TAKES THE SELECTION WHEN IT IS PRESSED.** The delegate's array is the rule; the
			 * item's target/action is the action. The two are independent, which is what lets a view switcher both
			 * do something and show which mode is current. */
			{
				id delegate = [_toolbar delegate];

				if (delegate != nil && [delegate respondsToSelector:@selector(toolbarSelectableItemIdentifiers:)]) {
					NSArray *selectable = [delegate toolbarSelectableItemIdentifiers:_toolbar];

					if (selectable != nil && [selectable containsObject:[item itemIdentifier]]) {
						[_toolbar setSelectedItemIdentifier:[item itemIdentifier]];
					}
				}
			}
		}
	}
}

- (void)mouseMoved:(NSEvent *)event
{
	NSPoint p = [self localPointForEvent:event];
	NSInteger index = [self indexAtPoint:p];

	if (index != _hoverIndex) {
		_hoverIndex = index;
		[self setNeedsDisplay:YES];
	}
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self cg_relayout];
}

@end

/* ============================================================================================ *
 * THE TOOLBAR.                                                                                  *
 * ============================================================================================ */

/* THE PRIVATE DOORS, DECLARED BEFORE THE IMPLEMENTATION SO A CALL ABOVE A DEFINITION IS STILL A KNOWN METHOD. */
@interface NSToolbar ()
- (NSToolbarItem *)fn_itemForIdentifier:(NSString *)identifier willBeInserted:(BOOL)flag;
- (NSToolbarItem *)fn_standardItemForIdentifier:(NSString *)identifier;
- (NSString *)fn_defaultsKey;
- (void)fn_loadItemsIfNeeded;
- (void)fn_insertItemIdentifier:(NSString *)identifier atIndex:(NSInteger)index announce:(BOOL)announce;
- (void)fn_saveConfiguration;
@end

@implementation NSToolbar

- (instancetype)initWithIdentifier:(NSString *)identifier
{
	self = [super init];
	if (self != nil) {
		_identifier = [(identifier != nil ? identifier : @"") copy];
		_items = [[NSMutableArray alloc] init];
		_itemIdentifiers = [[NSMutableArray alloc] init];
		_delegate = nil;
		_window = nil;
		_selectedItemIdentifier = nil;
		_displayMode = NSToolbarDisplayModeDefault;
		_sizeMode = NSToolbarSizeModeDefault;
		/* **VISIBLE UNTIL SOMEBODY SAYS OTHERWISE**, which is what makes `[window setToolbar:...]` show a toolbar
		 * rather than silently doing nothing. The flag means "wants to be shown"; attachment is what makes it a band
		 * on a window. */
		_visible = YES;
		_allowsUserCustomization = NO;
		_autosavesConfiguration = NO;
		_showsBaselineSeparator = YES;
		_didLoadItems = NO;
		_suppressAutosave = NO;
		_toolbarView = nil;
	}
	return self;
}

- (void)dealloc
{
	/* **NO NOTIFICATIONS FROM HERE.** An `NSNotification` retains its object, so posting "this toolbar is losing its
	 * items" from inside `-dealloc` would resurrect the toolbar mid-teardown — the defect `NSMenu.m` records in its
	 * own dealloc. The items are detached quietly instead. */
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		[[_items objectAtIndex:i] cg_setToolbar:nil];
	}
	[_items release];
	[_itemIdentifiers release];
	[_identifier release];
	[_selectedItemIdentifier release];
	[_toolbarView release];
	[super dealloc];
}

- (NSString *)identifier
{
	return _identifier;
}

/* ---- THE ITEMS --------------------------------------------------------------------------------- */

/* THE ONE PLACE AN IDENTIFIER BECOMES AN ITEM. The delegate has first refusal; the three spacers and the four
 * standard commands are the toolbar's own fallback, because a delegate should not have to make a separator. */
- (NSToolbarItem *)fn_itemForIdentifier:(NSString *)identifier willBeInserted:(BOOL)flag
{
	NSToolbarItem *item = nil;

	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:)]) {
		item = [_delegate toolbar:self itemForItemIdentifier:identifier willBeInsertedIntoToolbar:flag];
	}
	if (item == nil) {
		item = [self fn_standardItemForIdentifier:identifier];
	}
	if (item == nil) {
		return nil;
	}
	[item cg_setToolbar:self];
	return item;
}

- (NSToolbarItem *)fn_standardItemForIdentifier:(NSString *)identifier
{
	NSToolbarItem *item;

	if (identifier == nil) {
		return nil;
	}
	item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
	if ([identifier isEqualToString:NSToolbarSeparatorItemIdentifier]) {
		[item setLabel:@""];
		return item;
	}
	if ([identifier isEqualToString:NSToolbarSpaceItemIdentifier] ||
	    [identifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
		[item setLabel:@""];
		return item;
	}
	if ([identifier isEqualToString:NSToolbarCustomizeToolbarItemIdentifier]) {
		[item setLabel:@"Customize"];
		[item setPaletteLabel:@"Customize Toolbar"];
		[item setTarget:self];
		[item setAction:@selector(runCustomizationPalette:)];
		return item;
	}
	if ([identifier isEqualToString:NSToolbarShowColorsItemIdentifier]) {
		[item setLabel:@"Colors"];
		[item setAction:@selector(orderFrontColorPanel:)];
		return item;
	}
	if ([identifier isEqualToString:NSToolbarShowFontsItemIdentifier]) {
		[item setLabel:@"Fonts"];
		[item setAction:@selector(orderFrontFontPanel:)];
		return item;
	}
	if ([identifier isEqualToString:NSToolbarPrintItemIdentifier]) {
		[item setLabel:@"Print"];
		[item setAction:@selector(print:)];
		return item;
	}
	/* AN IDENTIFIER WITH NO DELEGATE ITEM AND NO STANDARD MEANING IS NOT AN ITEM. A blank placeholder would be a
	 * toolbar slot that looks pressable and does nothing; nil is the honest answer and the insertion skips it. */
	return nil;
}

- (NSString *)fn_defaultsKey
{
	return [@"NSToolbar Configuration " stringByAppendingString:_identifier];
}

- (void)fn_loadItemsIfNeeded
{
	NSArray *identifiers = nil;
	NSDictionary *saved;
	NSUInteger i;

	if (_didLoadItems) {
		return;
	}
	_didLoadItems = YES;
	if (_autosavesConfiguration) {
		id value = [[NSUserDefaults standardUserDefaults] objectForKey:[self fn_defaultsKey]];

		if ([value isKindOfClass:[NSDictionary class]]) {
			[self setConfigurationFromDictionary:(NSDictionary *)value];
			return;
		}
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(toolbarDefaultItemIdentifiers:)]) {
		identifiers = [_delegate toolbarDefaultItemIdentifiers:self];
	}
	if (identifiers == nil) {
		return;
	}
	for (i = 0; i < [identifiers count]; i++) {
		NSString *identifier = fn_identifier_at(identifiers, i);

		if (identifier != nil) {
			[self fn_insertItemIdentifier:identifier atIndex:(NSInteger)i announce:YES];
		}
	}
}

- (void)fn_insertItemIdentifier:(NSString *)identifier atIndex:(NSInteger)index announce:(BOOL)announce
{
	NSToolbarItem *item;

	if (identifier == nil) {
		return;
	}
	item = [self fn_itemForIdentifier:identifier willBeInserted:YES];
	if (item == nil) {
		return;
	}
	if (index < 0) {
		index = 0;
	}
	if ((NSUInteger)index > [_items count]) {
		index = (NSInteger)[_items count];
	}
	if (announce) {
		fn_announce(self, NSToolbarWillAddItemNotification, item);
	}
	[_items insertObject:item atIndex:(NSUInteger)index];
	[_itemIdentifiers insertObject:identifier atIndex:(NSUInteger)index];
	[self cg_layoutChanged];
}

- (void)insertItemWithItemIdentifier:(NSString *)itemIdentifier atIndex:(NSInteger)index
{
	if (_window != nil) {
		[self fn_loadItemsIfNeeded];
	}
	[self fn_insertItemIdentifier:itemIdentifier atIndex:index announce:YES];
}

- (void)removeItemAtIndex:(NSInteger)index
{
	NSToolbarItem *item;

	if (index < 0 || (NSUInteger)index >= [_items count]) {
		return;
	}
	item = [[_items objectAtIndex:(NSUInteger)index] retain];
	[_items removeObjectAtIndex:(NSUInteger)index];
	[_itemIdentifiers removeObjectAtIndex:(NSUInteger)index];
	[item cg_setToolbar:nil];
	fn_announce(self, NSToolbarDidRemoveItemNotification, item);
	[item release];
	[self cg_layoutChanged];
}

- (NSArray *)items
{
	if (_window != nil) {
		[self fn_loadItemsIfNeeded];
	}
	return [NSArray arrayWithArray:_items];
}

- (NSArray *)visibleItems
{
	if (_window != nil) {
		[self fn_loadItemsIfNeeded];
	}
	if (_toolbarView != nil) {
		return [(NSToolbarView *)_toolbarView cg_visibleItems];
	}
	return [NSArray arrayWithArray:_items];
}

- (void)setDelegate:(id <NSToolbarDelegate>)delegate
{
	_delegate = delegate;	/* NOT RETAINED */
	if (_window != nil && !_didLoadItems) {
		[self fn_loadItemsIfNeeded];
	}
}

- (id <NSToolbarDelegate>)delegate
{
	return _delegate;
}

- (void)setDisplayMode:(NSToolbarDisplayMode)displayMode
{
	_displayMode = displayMode;
	[self cg_layoutChanged];
}

- (NSToolbarDisplayMode)displayMode
{
	return _displayMode;
}

- (void)setSizeMode:(NSToolbarSizeMode)sizeMode
{
	NSWindow *window;
	NSRect content;

	if (_sizeMode == sizeMode) {
		return;
	}
	window = _window;
	/* **A SIZE CHANGE PRESERVES THE CONTENT, LIKE A VISIBILITY CHANGE.** The toolbar's height is part of the frame
	 * arithmetic, so changing it without resizing the frame would make the document jump; the content's size is the
	 * constant and the frame follows the band. */
	if (window != nil) {
		content = [window contentRectForFrameRect:[window frame]];
		_sizeMode = sizeMode;
		[window setFrame:[window frameRectForContentRect:content] display:YES];
		[window cg_toolbarLayoutChanged];
	} else {
		_sizeMode = sizeMode;
	}
	[self cg_layoutChanged];
}

- (NSToolbarSizeMode)sizeMode
{
	return _sizeMode;
}

- (void)setVisible:(BOOL)shown
{
	NSWindow *window = _window;
	NSRect content;

	if (_visible == shown) {
		return;
	}
	if (window == nil) {
		_visible = shown;
		return;
	}
	/* THE CONTENT'S SIZE IS THE CONSTANT; THE FRAME GROWS OR SHRINKS BY THE BAND. The rect is taken BEFORE the flag
	 * changes, so it is the content the window has now — toolbar excluded when it was visible, which is exactly the
	 * size that must survive the toggle. */
	content = [window contentRectForFrameRect:[window frame]];
	_visible = shown;
	[window setFrame:[window frameRectForContentRect:content] display:YES];
	[window cg_toolbarLayoutChanged];
	[self cg_layoutChanged];
}

- (BOOL)isVisible
{
	return _visible;
}

- (void)setSelectedItemIdentifier:(NSString *)itemIdentifier
{
	NSString *copy = [itemIdentifier copy];

	[_selectedItemIdentifier release];
	_selectedItemIdentifier = copy;
	[self cg_layoutChanged];
}

- (NSString *)selectedItemIdentifier
{
	return _selectedItemIdentifier;
}

- (void)setShowsBaselineSeparator:(BOOL)flag
{
	/* THE WINDOW'S CHROME PAINTER IS THE READER: the line is at the content's top edge, below this band, and this
	 * flag decides whether it is drawn. The layout call is what makes the window repaint when the flag moves. */
	_showsBaselineSeparator = flag ? YES : NO;
	[self cg_layoutChanged];
}

- (BOOL)showsBaselineSeparator
{
	return _showsBaselineSeparator;
}

- (void)setAllowsUserCustomization:(BOOL)allowCustomization
{
	_allowsUserCustomization = allowCustomization ? YES : NO;
}

- (BOOL)allowsUserCustomization
{
	return _allowsUserCustomization;
}

- (void)runCustomizationPalette:(id)sender
{
	(void)sender;
	fn_refuse_window("-runCustomizationPalette:", "the toolbar customization palette (a panel and a drag session)");
}

- (BOOL)customizationPaletteIsRunning
{
	return NO;
}

/* ---- AUTOSAVE AND THE CONFIGURATION DICTIONARY -------------------------------------------------- */

- (void)setAutosavesConfiguration:(BOOL)flag
{
	/* **SETTING THE FLAG DOES NOT WRITE.** It says "changes from now on are saved"; writing the CURRENT configuration
	 * here would overwrite a saved one before the toolbar had a chance to read it — and a caller that sets the flag
	 * before attaching (the ordinary order) would save an empty list and then restore it. */
	_autosavesConfiguration = flag ? YES : NO;
}

- (BOOL)autosavesConfiguration
{
	return _autosavesConfiguration;
}

- (void)fn_saveConfiguration
{
	if (!_autosavesConfiguration || _suppressAutosave || [_identifier length] == 0) {
		return;
	}
	[[NSUserDefaults standardUserDefaults] setObject:[self configurationDictionary]
						  forKey:[self fn_defaultsKey]];
}

- (void)setConfigurationFromDictionary:(NSDictionary *)configDict
{
	NSArray *identifiers;
	id value;
	NSUInteger i;

	if (![configDict isKindOfClass:[NSDictionary class]]) {
		return;
	}
	/* THE ITEM LIST IS THE REQUIRED KEY, because it is the only thing that cannot be defaulted: a dictionary without
	 * one would either clear the toolbar or leave it unchanged, and neither is what "set the configuration" means. */
	identifiers = [configDict objectForKey:NSToolbarItemIdentifiers];
	if (![identifiers isKindOfClass:[NSArray class]]) {
		return;
	}
	_suppressAutosave = YES;
	_didLoadItems = YES;

	/* THE OLD ITEMS GO THROUGH THE SAME DOOR A CALLER USES, so the delegate and any observers see what happened.
	 * They are removed from the end rather than from zero so each announcement's item is the one being taken out. */
	while ([_items count] > 0) {
		[self removeItemAtIndex:(NSInteger)[_items count] - 1];
	}
	for (i = 0; i < [identifiers count]; i++) {
		NSString *identifier = fn_identifier_at(identifiers, i);

		if (identifier != nil) {
			[self fn_insertItemIdentifier:identifier atIndex:(NSInteger)[_items count] announce:YES];
		}
	}
	value = [configDict objectForKey:NSToolbarSelectedItemIdentifier];
	if ([value isKindOfClass:[NSString class]]) {
		[self setSelectedItemIdentifier:(NSString *)value];
	} else {
		[self setSelectedItemIdentifier:nil];
	}
	value = [configDict objectForKey:NSToolbarDisplayModeKey];
	if ([value isKindOfClass:[NSNumber class]]) {
		[self setDisplayMode:[value unsignedIntegerValue]];
	}
	value = [configDict objectForKey:NSToolbarSizeModeKey];
	if ([value isKindOfClass:[NSNumber class]]) {
		[self setSizeMode:[value unsignedIntegerValue]];
	}
	value = [configDict objectForKey:NSToolbarShowsBaselineSeparatorKey];
	if ([value isKindOfClass:[NSNumber class]]) {
		[self setShowsBaselineSeparator:[value boolValue]];
	}
	value = [configDict objectForKey:NSToolbarAllowsUserCustomizationKey];
	if ([value isKindOfClass:[NSNumber class]]) {
		[self setAllowsUserCustomization:[value boolValue]];
	}
	_suppressAutosave = NO;
	[self fn_saveConfiguration];
	[self cg_layoutChanged];
}

- (NSDictionary *)configurationDictionary
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

	[dictionary setObject:[NSArray arrayWithArray:_itemIdentifiers] forKey:NSToolbarItemIdentifiers];
	if (_selectedItemIdentifier != nil) {
		[dictionary setObject:_selectedItemIdentifier forKey:NSToolbarSelectedItemIdentifier];
	}
	[dictionary setObject:[NSNumber numberWithUnsignedInteger:_displayMode] forKey:NSToolbarDisplayModeKey];
	[dictionary setObject:[NSNumber numberWithUnsignedInteger:_sizeMode] forKey:NSToolbarSizeModeKey];
	[dictionary setObject:[NSNumber numberWithBool:_showsBaselineSeparator]
		       forKey:NSToolbarShowsBaselineSeparatorKey];
	[dictionary setObject:[NSNumber numberWithBool:_allowsUserCustomization]
		       forKey:NSToolbarAllowsUserCustomizationKey];
	return dictionary;
}

/* ---- VALIDATION --------------------------------------------------------------------------------- */

- (void)validateVisibleItems
{
	NSArray *visible = [self visibleItems];
	NSUInteger i;

	for (i = 0; i < [visible count]; i++) {
		NSToolbarItem *item = [visible objectAtIndex:i];

		if ([item autovalidates]) {
			[item validate];
		}
	}
}

/* ---- THE WINDOW'S SEAM -------------------------------------------------------------------------- */

- (CGFloat)cg_toolbarHeight
{
	return (_sizeMode == NSToolbarSizeModeSmall) ? fn_TOOLBAR_HEIGHT_SMALL : fn_TOOLBAR_HEIGHT_REGULAR;
}

- (NSView *)cg_view
{
	if (_toolbarView == nil) {
		_toolbarView = [[NSToolbarView alloc] initWithToolbar:self];
		[_toolbarView cg_setWindow:_window];
	}
	return _toolbarView;
}

- (void)cg_setWindow:(NSWindow *)window
{
	_window = window;	/* NOT RETAINED: the window owns the toolbar */
	if (_toolbarView != nil) {
		if (window == nil) {
			/* **DETACHING LEAVES THE TREE.** The content view retains a subview, so a toolbar that was merely set to
			 * nil would keep a stale strip drawn over the next window's content. Taking its view out here is the
			 * other half of `-setToolbar:`'s adoption. */
			[(NSView *)_toolbarView removeFromSuperview];
		}
		[(NSView *)_toolbarView cg_setWindow:window];
	}
	if (window != nil) {
		[self fn_loadItemsIfNeeded];
	}
}

- (void)cg_layoutChanged
{
	if (_toolbarView != nil) {
		[(NSToolbarView *)_toolbarView cg_relayout];
		[(NSView *)_toolbarView setNeedsDisplay:YES];
	}
	[_window cg_toolbarLayoutChanged];
	[self fn_saveConfiguration];
}

@end
