/*
 * NSFontPanel — the shared font panel.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE FACE IS A SCROLLING FAMILY LIST, A SIZE ROW AND THE CALLER'S BAND.** The list is a real `NSScrollView` around
 * a document view that draws one row per family — 115 families on this machine, so a list that could not scroll would
 * be a list that showed a third of the fonts — the size row is eight chips drawn by the panel's own content view, and
 * the accessory view has a reserved band at the foot. Both of the first two are HIT-TESTED where they are drawn, so a
 * click needs no synthetic button: the list view's `-mouseDown:` answers a row, and the content view's answers a chip.
 *
 * **A CLICK CHANGES THE PANEL AND THEN ASKS THE MANAGER TO SPEAK.** The panel's font becomes the clicked family at the
 * panel's current size (or the current family at the clicked size); the same font is installed as the manager's
 * selection; and `-modifyFontViaPanel:` sends `-changeFont:` to the manager's target. That order is Apple's and it is
 * why the panel owns no conversion code of its own beyond `-panelConvertFont:`'s pure form.
 */
#import <AppKit/NSFontPanel.h>

#import <AppKit/NSFontManager.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSFontDescriptor.h>
#import <AppKit/NSView.h>

#include <math.h>

#define AG_FONT_PANEL_WIDTH    220.0
#define AG_FONT_PANEL_HEIGHT   300.0
#define AG_FONT_PANEL_MARGIN     8.0
#define AG_FONT_LIST_TOP         8.0
#define AG_FONT_LIST_HEIGHT    206.0
#define AG_FONT_ROW_HEIGHT      15.0
#define AG_FONT_CHIP_TOP       220.0
#define AG_FONT_CHIP_WIDTH      18.0
#define AG_FONT_CHIP_GAP         4.0
#define AG_FONT_CHIP_HEIGHT     18.0
#define AG_FONT_ACCESSORY_TOP  244.0
#define AG_FONT_ACCESSORY_HEIGHT 48.0

static NSFontPanel *s_sharedFontPanel = nil;
static Class s_panelFactory = Nil;

/* THE SIZES A CHIP OFFERS, and the reason they are a table: a size list is a set of choices rather than an arithmetic
 * progression, and these are the era's eight. */
static const CGFloat AGFontPanelSizes[8] = {9.0, 10.0, 11.0, 12.0, 14.0, 18.0, 24.0, 36.0};

@class NSFontPanel;

/* **ONE EXTENSION, BEFORE EITHER VIEW CLASS**, because both of them call into the panel: the list view asks which row,
 * the content view asks which chip, and neither can wait for a declaration further down the file. */
@interface NSFontPanel ()
- (void)fn_layout;
- (void)fn_chooseFamilyAtIndex:(NSUInteger)index;
- (void)fn_chooseSize:(CGFloat)size;
- (NSString *)cg_familyAtIndex:(NSUInteger)index;
@end

/* ============================================================================================ *
 * THE FAMILY LIST: A SCROLLING DOCUMENT VIEW OF ROWS.                                           *
 * ============================================================================================ */

@interface AGFontFamilyListView : NSView
{
	NSFontPanel *_panel;		/* ASSIGN */
}
- (instancetype)initWithFrame:(NSRect)frameRect panel:(NSFontPanel *)panel;
- (NSRect)fn_rectForRow:(NSUInteger)row;
- (NSInteger)fn_rowAtPoint:(NSPoint)point;
@end

@implementation AGFontFamilyListView

- (instancetype)initWithFrame:(NSRect)frameRect panel:(NSFontPanel *)panel
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_panel = panel;
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	(void)theEvent;
	return YES;
}

- (NSRect)fn_rectForRow:(NSUInteger)row
{
	return NSMakeRect(0.0, (CGFloat)row * AG_FONT_ROW_HEIGHT, NSWidth([self bounds]), AG_FONT_ROW_HEIGHT);
}

- (NSInteger)fn_rowAtPoint:(NSPoint)point
{
	NSInteger row;

	if (point.y < 0.0 || point.x < 0.0) {
		return -1;
	}
	row = (NSInteger)floor(point.y / AG_FONT_ROW_HEIGHT);
	return ((NSUInteger)row < [_panel cg_familyCount]) ? row : -1;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger selected = [_panel cg_selectedFamilyIndex];
	NSDictionary *attributes;
	NSDictionary *selectedAttributes;
	NSUInteger i;

	(void)dirtyRect;
	[[NSColor controlBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont systemFontOfSize:11.0], NSFontAttributeName,
		([_panel isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]),
		NSForegroundColorAttributeName, nil];
	selectedAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont boldSystemFontOfSize:11.0], NSFontAttributeName,
		[NSColor whiteColor], NSForegroundColorAttributeName, nil];
	for (i = 0; i < [_panel cg_familyCount]; i++) {
		NSRect row = [self fn_rectForRow:i];
		NSString *family = [_panel cg_familyAtIndex:i];

		if (family == nil || !NSIntersectsRect(row, dirtyRect)) {
			continue;
		}
		if ((NSInteger)i == selected) {
			[[NSColor cg_accentColor] setFill];
			[[NSBezierPath bezierPathWithRect:row] fill];
			[family drawAtPoint:NSMakePoint(NSMinX(row) + 4.0, NSMinY(row) + 2.0)
			     withAttributes:selectedAttributes];
		} else {
			[family drawAtPoint:NSMakePoint(NSMinX(row) + 4.0, NSMinY(row) + 2.0)
			     withAttributes:attributes];
		}
	}
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point;
	NSInteger row;

	if (![_panel isEnabled]) {
		return;
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	row = [self fn_rowAtPoint:point];
	if (row >= 0) {
		[_panel fn_chooseFamilyAtIndex:(NSUInteger)row];
	}
}

@end

/* ============================================================================================ *
 * THE PANEL'S CONTENT VIEW: THE SIZE ROW AND THE ACCESSORY BAND.                                *
 * ============================================================================================ */

@interface AGFontPanelView : NSView
{
	NSFontPanel *_panel;		/* ASSIGN */
}
- (instancetype)initWithFrame:(NSRect)frameRect panel:(NSFontPanel *)panel;
@end

@implementation AGFontPanelView

- (instancetype)initWithFrame:(NSRect)frameRect panel:(NSFontPanel *)panel
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_panel = panel;
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSColor *ink = [_panel isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
	NSUInteger i;

	(void)dirtyRect;
	[[NSColor windowBackgroundColor] setFill];
	[[NSBezierPath bezierPathWithRect:[self bounds]] fill];
	for (i = 0; i < [_panel cg_sizeChipCount]; i++) {
		NSRect chip = [_panel cg_sizeChipRectAtIndex:i];
		NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:chip xRadius:3.0 yRadius:3.0];
		NSNumber *size = [NSNumber numberWithDouble:(double)[_panel cg_sizeChipValueAtIndex:i]];
		NSString *label = [NSString stringWithFormat:@"%d", (int)[size doubleValue]];
		NSSize text = [label sizeWithAttributes:
			[NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:10.0] forKey:NSFontAttributeName]];

		[[NSColor controlColor] setFill];
		[face fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:1.0];
		[face stroke];
		[label drawAtPoint:NSMakePoint(NSMidX(chip) - text.width / 2.0, NSMidY(chip) - text.height / 2.0)
		    withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSFont systemFontOfSize:10.0], NSFontAttributeName, ink, NSForegroundColorAttributeName, nil]];
	}
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint point;
	NSUInteger i;

	if (![_panel isEnabled]) {
		return;
	}
	point = [self convertPoint:[event locationInWindow] fromView:nil];
	for (i = 0; i < [_panel cg_sizeChipCount]; i++) {
		if (NSPointInRect(point, [_panel cg_sizeChipRectAtIndex:i])) {
			[_panel fn_chooseSize:[_panel cg_sizeChipValueAtIndex:i]];
			return;
		}
	}
}

@end

/* ============================================================================================ *
 * THE PANEL.                                                                                    *
 * ============================================================================================ */

@implementation NSFontPanel

/* ============================================================================================ *
 * THE SINGLETON.                                                                                *
 * ============================================================================================ */

+ (NSFontPanel *)sharedFontPanel
{
	if (s_sharedFontPanel == nil) {
		Class factory = (s_panelFactory != Nil) ? s_panelFactory : [NSFontPanel class];
		NSFontPanel *panel = [[factory alloc] initWithContentRect:NSMakeRect(0.0, 0.0, AG_FONT_PANEL_WIDTH,
										     AG_FONT_PANEL_HEIGHT)
								styleMask:(NSTitledWindowMask | NSClosableWindowMask)
								  backing:NSBackingStoreBuffered
								    defer:NO];

		[panel setTitle:@"Fonts"];
		[panel setReleasedWhenClosed:NO];
		[panel setFloatingPanel:YES];
		[panel setLevel:NSFloatingWindowLevel];
		[panel setPanelFont:[NSFont systemFontOfSize:[NSFont systemFontSize]] isMultiple:NO];
		s_sharedFontPanel = panel;	/* KEPT FOREVER: it is the shared panel */
	}
	return s_sharedFontPanel;
}

+ (BOOL)sharedFontPanelExists
{
	return s_sharedFontPanel != nil;
}

+ (void)setSharedPanelFactory:(Class)factory
{
	/* **THE FACTORY APPLIES ONLY BEFORE THE SHARED PANEL EXISTS**, which is `NSFontManager +setFontPanelFactory:`'s
	 * rule by consequence: the live panel is what every target is already holding. */
	s_panelFactory = factory;
}

/* ============================================================================================ *
 * LIFETIME AND THE FACE.                                                                        *
 * ============================================================================================ */

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{
	self = [super initWithContentRect:contentRect styleMask:styleMask backing:bufferingType defer:flag];
	if (self != nil) {
		_enabled = YES;
		_selectedFamily = -1;
		_panelView = [[AGFontPanelView alloc] initWithFrame:NSMakeRect(0.0, 0.0, AG_FONT_PANEL_WIDTH,
									      AG_FONT_PANEL_HEIGHT)
							       panel:self];
		[self setContentView:(NSView *)_panelView];
		[self reloadDefaultFontFamilies];
	}
	return self;
}

- (void)dealloc
{
	[_panelFont release];
	[_accessoryView release];
	[_families release];
	[_panelView release];
	[_listScrollView release];
	[_listView release];
	[super dealloc];
}

- (void)reloadDefaultFontFamilies
{
	NSArray *families = [[NSFontManager sharedFontManager] availableFontFamilies];
	NSArray *old = _families;

	_families = [families copy];
	[old release];
	_selectedFamily = -1;
	if (_panelFont != nil) {
		NSUInteger i;

		for (i = 0; i < [_families count]; i++) {
			if ([[_families objectAtIndex:i] isEqual:[_panelFont familyName]]) {
				_selectedFamily = (NSInteger)i;
				break;
			}
		}
	}
	if (_selectedFamily < 0 && [_families count] > 0) {
		_selectedFamily = 0;
	}
	[self fn_layout];
}

/* **THE LIST AND THE CHIPS ARE MADE ONCE AND FRAMED HERE**, so a reload only resizes the document. */
- (void)fn_layout
{
	NSScrollView *scroll = (NSScrollView *)_listScrollView;
	NSRect listFrame = NSMakeRect(AG_FONT_PANEL_MARGIN, AG_FONT_LIST_TOP,
				      AG_FONT_PANEL_WIDTH - 2.0 * AG_FONT_PANEL_MARGIN, AG_FONT_LIST_HEIGHT);
	CGFloat documentWidth = NSWidth(listFrame) - 16.0;
	AGFontFamilyListView *list;

	if (scroll == nil) {
		scroll = [[NSScrollView alloc] initWithFrame:listFrame];
		[scroll setHasVerticalScroller:YES];
		[scroll setBorderType:NSBezelBorder];
		[(NSView *)_panelView addSubview:scroll];
		_listScrollView = scroll;
	}
	[scroll setFrame:listFrame];
	list = [[AGFontFamilyListView alloc] initWithFrame:NSMakeRect(0.0, 0.0, documentWidth,
								      (CGFloat)[_families count] * AG_FONT_ROW_HEIGHT)
						    panel:self];
	[_listView release];
	_listView = list;
	[scroll setDocumentView:list];
	if (_accessoryView != nil) {
		[_accessoryView setFrame:NSMakeRect(AG_FONT_PANEL_MARGIN, AG_FONT_ACCESSORY_TOP,
						    AG_FONT_PANEL_WIDTH - 2.0 * AG_FONT_PANEL_MARGIN,
						    AG_FONT_ACCESSORY_HEIGHT)];
	}
	[(NSView *)_panelView setNeedsDisplay:YES];
}

/* ============================================================================================ *
 * THE SELECTION.                                                                                *
 * ============================================================================================ */

- (void)setPanelFont:(NSFont *)fontObj isMultiple:(BOOL)flag
{
	NSFont *old = _panelFont;
	NSUInteger i;

	_panelFont = [fontObj retain];
	[old release];
	_multiple = flag ? YES : NO;
	if (_panelFont != nil) {
		for (i = 0; i < [_families count]; i++) {
			if ([[_families objectAtIndex:i] isEqual:[_panelFont familyName]]) {
				_selectedFamily = (NSInteger)i;
				break;
			}
		}
	}
	[(NSView *)_panelView setNeedsDisplay:YES];
}

- (NSFont *)panelFont
{
	return (_panelFont != nil) ? _panelFont : [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

- (BOOL)isMultiple
{
	return _multiple;
}

- (NSFont *)panelConvertFont:(NSFont *)fontObj
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSFont *inFamily;
	NSFont *sized;

	if (fontObj == nil || _panelFont == nil) {
		return fontObj;
	}
	inFamily = [manager convertFont:fontObj toFamily:[_panelFont familyName]];
	sized = [manager convertFont:inFamily toSize:[_panelFont pointSize]];
	return (sized != nil) ? sized : fontObj;
}

/* ============================================================================================ *
 * THE TWO CLICKS.                                                                               *
 * ============================================================================================ */

- (void)fn_chooseFamilyAtIndex:(NSUInteger)index
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSString *family = [self cg_familyAtIndex:index];
	NSFont *font;

	if (family == nil) {
		return;
	}
	font = [manager fontWithFamily:family traits:0 weight:5 size:[[self panelFont] pointSize]];
	if (font == nil) {
		return;
	}
	[self setPanelFont:font isMultiple:NO];
	[manager setSelectedFont:font isMultiple:NO];
	[manager modifyFontViaPanel:self];
}

- (void)fn_chooseSize:(CGFloat)size
{
	NSFontManager *manager = [NSFontManager sharedFontManager];
	NSFont *font = [[self panelFont] fontWithSize:size];

	if (font == nil) {
		return;
	}
	[self setPanelFont:font isMultiple:NO];
	[manager setSelectedFont:font isMultiple:NO];
	[manager modifyFontViaPanel:self];
}

/* ============================================================================================ *
 * THE ACCESSORY VIEW, ENABLE, AND MODALITY.                                                     *
 * ============================================================================================ */

- (void)setAccessoryView:(NSView *)aView
{
	NSView *old = _accessoryView;

	if (old != nil) {
		[old removeFromSuperview];
	}
	_accessoryView = [aView retain];
	[old release];
	if (_accessoryView != nil) {
		[_accessoryView setFrame:NSMakeRect(AG_FONT_PANEL_MARGIN, AG_FONT_ACCESSORY_TOP,
						    AG_FONT_PANEL_WIDTH - 2.0 * AG_FONT_PANEL_MARGIN,
						    AG_FONT_ACCESSORY_HEIGHT)];
		[(NSView *)_panelView addSubview:_accessoryView];
	}
	[(NSView *)_panelView setNeedsDisplay:YES];
}

- (NSView *)accessoryView
{
	return _accessoryView;
}

- (void)setEnabled:(BOOL)flag
{
	_enabled = flag ? YES : NO;
	[(NSView *)_panelView setNeedsDisplay:YES];
	{
		NSArray *subviews = [(NSView *)_panelView subviews];
		NSUInteger i;

		for (i = 0; i < [subviews count]; i++) {
			[[subviews objectAtIndex:i] setNeedsDisplay:YES];
		}
	}
}

- (BOOL)isEnabled
{
	return _enabled;
}

- (BOOL)worksWhenModal
{
	return YES;
}

/* ============================================================================================ *
 * AND THE INSTRUMENT'S SIX.                                                                     *
 * ============================================================================================ */

- (NSUInteger)cg_familyCount
{
	return [_families count];
}

- (NSString *)cg_familyAtIndex:(NSUInteger)index
{
	return (index < [_families count]) ? [_families objectAtIndex:index] : nil;
}

- (NSUInteger)cg_sizeChipCount
{
	return 8;
}

- (NSRect)cg_familyRectAtIndex:(NSUInteger)index
{
	/* **THE RECT IS IN THE LIST'S COORDINATES**, which is where a click lands and where the document view draws. */
	return NSMakeRect(0.0, (CGFloat)index * AG_FONT_ROW_HEIGHT, AG_FONT_PANEL_WIDTH - 2.0 * AG_FONT_PANEL_MARGIN,
			  AG_FONT_ROW_HEIGHT);
}

- (NSInteger)cg_selectedFamilyIndex
{
	return _selectedFamily;
}

- (NSRect)cg_sizeChipRectAtIndex:(NSUInteger)index
{
	CGFloat total = 8.0 * AG_FONT_CHIP_WIDTH + 7.0 * AG_FONT_CHIP_GAP;
	CGFloat x = (AG_FONT_PANEL_WIDTH - total) / 2.0 + (CGFloat)index * (AG_FONT_CHIP_WIDTH + AG_FONT_CHIP_GAP);

	return NSMakeRect(x, AG_FONT_CHIP_TOP, AG_FONT_CHIP_WIDTH, AG_FONT_CHIP_HEIGHT);
}

- (CGFloat)cg_sizeChipValueAtIndex:(NSUInteger)index
{
	return (index < 8) ? AGFontPanelSizes[index] : 0.0;
}

@end
