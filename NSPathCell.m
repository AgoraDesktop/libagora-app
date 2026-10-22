/*
 * NSPathCell — a path as a row of component cells.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE LAYOUT IS THE PATH'S.** Components are measured from their own cells, separators are inserted between them,
 * and when the row is wider than the frame the middle components are hidden and an ellipsis takes their place. The
 * first and last components always stay, because they are the root and the item a person is looking at; a middle
 * component is kept only if it fits from the last one backwards.
 *
 * **THREE STYLES, ONE LAYOUT.** Standard fills a light-blue bar and draws small arrows; NavigationBar fills the
 * control face and draws chevrons at the small control size; PopUp shows only the last component with a down chevron
 * and raises a menu of the whole path on a press. The component cells draw only their interiors, so changing the
 * style changes the surface and the separators without changing a component's face.
 *
 * The editable/drop half is absent with the drag session, as the header says; `allowedTypes` is stored and the
 * delegate's PopUp hook is called, while the open-panel hook is declared and never reached.
 */
#import <AppKit/NSPathCell.h>

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSView.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <math.h>
#include <stdlib.h>

#define AG_PATH_PADDING		4.0
#define AG_PATH_ELLIPSIS_WIDTH	18.0
#define AG_PATH_SEPARATOR_STANDARD	10.0
#define AG_PATH_SEPARATOR_NAV	16.0
#define AG_PATH_HEIGHT		24.0
#define AG_PATH_SMALL_HEIGHT	18.0

static NSColor *fn_path_standard_background(void)
{
	return [NSColor colorWithCalibratedRed:0.85 green:0.91 blue:0.98 alpha:1.0];
}

static NSColor *fn_path_default_background(NSPathStyle style)
{
	switch (style) {
	case NSPathStyleNavigationBar:
	case NSPathStylePopUp:
		return [NSColor controlColor];
	case NSPathStyleStandard:
	default:
		return fn_path_standard_background();
	}
}

@interface NSPathCell ()
- (void)cg_setCellsFromURL;
- (void)cg_redraw;
- (CGFloat)cg_separatorWidth;
- (void)cg_layoutInFrame:(NSRect)frame rects:(NSRect *)rects visible:(BOOL *)visible
	    ellipsisRect:(NSRect *)ellipsisRect count:(NSUInteger)count;
- (void)cg_drawChevronAtX:(CGFloat)x y:(CGFloat)y height:(CGFloat)height;
- (void)cg_setClickedPathComponentCell:(NSPathComponentCell *)cell;
- (void)cg_popUpMenuWithEvent:(NSEvent *)event inView:(NSView *)view;
- (void)cg_pathMenuSelected:(id)sender;
@end

@implementation NSPathCell

/* ============================================================================================
 * ARCHIVING: A PATH'S COMPONENTS, ITS URL AND ITS STYLE.
 * ============================================================================================ */
/* **`_clickedCell` AND `_hoveredCell` ARE WHAT THE POINTER IS DOING** and are absent; `_delegate` is a CONNECTION. The
 * components themselves are `NSPathComponentCell`s — real archivable cells — so a path round-trips as a path. The double
 * action is a selector and is archived by name, the way every action in this format is. */
static NSString * const AGCoderPathCellsKey = @"cells";
static NSString * const AGCoderPathURLKey = @"url";
static NSString * const AGCoderPathBackgroundColorKey = @"backgroundColor";
static NSString * const AGCoderPathBackgroundUserSetKey = @"cgBackgroundUserSet";
static NSString * const AGCoderPathAllowedTypesKey = @"allowedTypes";
static NSString * const AGCoderPathDoubleActionKey = @"doubleAction";
static NSString * const AGCoderPathStyleKey = @"pathStyle";
static NSString * const AGCoderPathPlaceholderKey = @"placeholderString";
static NSString * const AGCoderPathPlaceholderAttributedKey = @"placeholderAttributedString";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_cells forKey:AGCoderPathCellsKey];
	[aCoder encodeObject:_url forKey:AGCoderPathURLKey];
	[aCoder encodeObject:_backgroundColor forKey:AGCoderPathBackgroundColorKey];
	[aCoder encodeBool:_cgBackgroundUserSet forKey:AGCoderPathBackgroundUserSetKey];
	[aCoder encodeObject:_allowedTypes forKey:AGCoderPathAllowedTypesKey];
	[aCoder encodeObject:(_doubleAction != NULL) ? NSStringFromSelector(_doubleAction) : nil
		      forKey:AGCoderPathDoubleActionKey];
	[aCoder encodeInteger:(NSInteger)_pathStyle forKey:AGCoderPathStyleKey];
	[aCoder encodeObject:_placeholderString forKey:AGCoderPathPlaceholderKey];
	[aCoder encodeObject:_placeholderAttributedString forKey:AGCoderPathPlaceholderAttributedKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderPathCellsKey]) {
		_cells = [[aDecoder decodeObjectForKey:AGCoderPathCellsKey] mutableCopy];
	}
	if ([aDecoder containsValueForKey:AGCoderPathURLKey]) {
		_url = [[aDecoder decodeObjectForKey:AGCoderPathURLKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderPathBackgroundColorKey]) {
		_backgroundColor = [[aDecoder decodeObjectForKey:AGCoderPathBackgroundColorKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderPathBackgroundUserSetKey]) {
		_cgBackgroundUserSet = [aDecoder decodeBoolForKey:AGCoderPathBackgroundUserSetKey];
	}
	if ([aDecoder containsValueForKey:AGCoderPathAllowedTypesKey]) {
		_allowedTypes = [[aDecoder decodeObjectForKey:AGCoderPathAllowedTypesKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderPathStyleKey]) {
		_pathStyle = [aDecoder decodeIntegerForKey:AGCoderPathStyleKey];
	}
	if ([aDecoder containsValueForKey:AGCoderPathPlaceholderKey]) {
		_placeholderString = [[aDecoder decodeObjectForKey:AGCoderPathPlaceholderKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderPathPlaceholderAttributedKey]) {
		_placeholderAttributedString = [[aDecoder decodeObjectForKey:AGCoderPathPlaceholderAttributedKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderPathDoubleActionKey]) {
		NSString *name = [aDecoder decodeObjectForKey:AGCoderPathDoubleActionKey];

		if ([name isKindOfClass:[NSString class]]) {
			_doubleAction = NSSelectorFromString(name);
		}
	}
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
		_cells = [[NSMutableArray alloc] init];
		_clickedCell = nil;
		_hoveredCell = nil;
		_url = nil;
		_pathStyle = NSPathStyleStandard;
		_backgroundColor = [fn_path_default_background(_pathStyle) retain];
		_cgBackgroundUserSet = NO;
		_allowedTypes = nil;
		_doubleAction = NULL;
		_delegate = nil;
		_placeholderString = nil;
		_placeholderAttributedString = nil;
	}
	return self;
}

- (void)dealloc
{
	[_cells release];
	[_url release];
	[_backgroundColor release];
	[_allowedTypes release];
	[_placeholderString release];
	[_placeholderAttributedString release];
	[super dealloc];
}

- (void)cg_redraw
{
	if (_controlView != nil && [_controlView respondsToSelector:@selector(setNeedsDisplay:)]) {
		[(NSView *)_controlView setNeedsDisplay:YES];
	}
}

/* ---- THE STYLE, THE BACKGROUND AND THE SIZE ------------------------------------------------------ */

- (NSPathStyle)pathStyle
{
	return _pathStyle;
}

- (void)setPathStyle:(NSPathStyle)style
{
	if (style == _pathStyle) {
		return;
	}
	_pathStyle = style;
	if (!_cgBackgroundUserSet) {
		NSColor *color = fn_path_default_background(style);

		[color retain];
		[_backgroundColor release];
		_backgroundColor = color;
	}
	if (style == NSPathStyleNavigationBar) {
		[self setControlSize:NSSmallControlSize];
	}
	[self cg_redraw];
}

- (void)setControlSize:(NSControlSize)size
{
	NSUInteger i;

	if (_pathStyle == NSPathStyleNavigationBar) {
		size = NSSmallControlSize;
	}
	[super setControlSize:size];
	for (i = 0; i < [_cells count]; i++) {
		[[_cells objectAtIndex:i] setControlSize:size];
	}
	[self cg_redraw];
}

- (void)setBackgroundColor:(NSColor *)color
{
	[color retain];
	[_backgroundColor release];
	_backgroundColor = color;
	_cgBackgroundUserSet = YES;
	[self cg_redraw];
}

- (NSColor *)backgroundColor
{
	return _backgroundColor;
}

- (BOOL)isOpaque
{
	return _backgroundColor != nil && [_backgroundColor alphaComponent] >= 1.0;
}

/* ---- THE URL AND THE COMPONENTS ------------------------------------------------------------------ */

- (void)cg_setCellsFromURL
{
	NSUInteger i;

	[_cells removeAllObjects];
	_clickedCell = nil;
	_hoveredCell = nil;
	if (_url == nil) {
		return;
	}
	if ([_url isFileURL]) {
		NSArray *parts = [_url pathComponents];
		NSURL *prefix = [NSURL fileURLWithPath:@"/"];
		NSPathComponentCell *root = [[[self class] pathComponentCellClass] new];

		[root setStringValue:@"/"];
		[root setURL:prefix];
		[root setControlSize:[self controlSize]];
		[_cells addObject:root];
		[root release];
		for (i = 1; parts != nil && i < [parts count]; i++) {
			NSString *name = [parts objectAtIndex:i];
			NSPathComponentCell *cell = [[[self class] pathComponentCellClass] new];

			prefix = [prefix URLByAppendingPathComponent:name];
			[cell setStringValue:name];
			[cell setURL:prefix];
			[cell setControlSize:[self controlSize]];
			[_cells addObject:cell];
			[cell release];
		}
	} else {
		NSPathComponentCell *cell = [[[self class] pathComponentCellClass] new];

		[cell setStringValue:[_url absoluteString]];
		[cell setURL:_url];
		[cell setControlSize:[self controlSize]];
		[_cells addObject:cell];
		[cell release];
	}
}

- (NSURL *)URL
{
	return _url;
}

- (void)setURL:(NSURL *)url
{
	[url retain];
	[_url release];
	_url = url;
	[super setObjectValue:url];
	[self cg_setCellsFromURL];
	[self cg_redraw];
}

- (void)setObjectValue:(id <NSCopying>)obj
{
	id value = (id)obj;

	if (value == nil) {
		[self setURL:nil];
		return;
	}
	if ([value isKindOfClass:[NSURL class]]) {
		[self setURL:(NSURL *)value];
		return;
	}
	if ([value isKindOfClass:[NSString class]]) {
		NSURL *url = [NSURL fileURLWithPath:(NSString *)value];

		if (url == nil) {
			url = [NSURL URLWithString:(NSString *)value];
		}
		[self setURL:url];
		return;
	}
	[NSException raise:NSInvalidArgumentException
		    format:@"NSPathCell -setObjectValue: takes an NSURL or a path string, not %@", [value class]];
}

- (NSArray *)allowedTypes
{
	return _allowedTypes;
}

- (void)setAllowedTypes:(NSArray *)allowedTypes
{
	NSArray *copy = [allowedTypes copy];

	[_allowedTypes release];
	_allowedTypes = copy;
}

- (id <NSPathCellDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSPathCellDelegate>)value
{
	_delegate = value;	/* NOT RETAINED */
}

+ (Class)pathComponentCellClass
{
	return [NSPathComponentCell class];
}

- (NSArray *)pathComponentCells
{
	return [NSArray arrayWithArray:_cells];
}

- (void)setPathComponentCells:(NSArray *)cells
{
	NSUInteger i;
	NSMutableArray *copy = [NSMutableArray array];

	if (cells == nil) {
		cells = [NSArray array];
	}
	for (i = 0; i < [cells count]; i++) {
		id cell = [cells objectAtIndex:i];

		if (![cell isKindOfClass:[NSPathComponentCell class]]) {
			[NSException raise:NSInvalidArgumentException
				    format:@"NSPathCell components must be NSPathComponentCells, not %@",
					   [cell class]];
		}
		[cell setControlSize:[self controlSize]];
		[copy addObject:cell];
	}
	[_cells removeAllObjects];
	[_cells addObjectsFromArray:copy];
	_clickedCell = nil;
	_hoveredCell = nil;
	[self cg_redraw];
}

- (NSPathComponentCell *)clickedPathComponentCell
{
	return _clickedCell;
}

- (void)cg_setClickedPathComponentCell:(NSPathComponentCell *)cell
{
	_clickedCell = cell;
	[self cg_redraw];
}

- (SEL)doubleAction
{
	return _doubleAction;
}

- (void)setDoubleAction:(SEL)action
{
	_doubleAction = action;
}

- (void)setPlaceholderString:(NSString *)string
{
	NSString *copy = [string copy];

	[_placeholderString release];
	_placeholderString = copy;
	[self cg_redraw];
}

- (NSString *)placeholderString
{
	return _placeholderString;
}

- (void)setPlaceholderAttributedString:(NSAttributedString *)string
{
	[string retain];
	[_placeholderAttributedString release];
	_placeholderAttributedString = string;
	[self cg_redraw];
}

- (NSAttributedString *)placeholderAttributedString
{
	return _placeholderAttributedString;
}

/* ---- THE GEOMETRY ------------------------------------------------------------------------------- */

/* **`-cellSize` IS OVERRIDDEN BECAUSE THE BASE ONE CHECKS THE CELL TYPE FIRST.** A path cell is not a text or image
 * cell, so `NSCell -cellSize` would answer its 10000x10000 "no opinion" sentinel before reaching
 * `-cellSizeForBounds:`. A path has an opinion: its components' natural widths plus the separators between them. */
- (NSSize)cellSize
{
	return [self cellSizeForBounds:NSMakeRect(0.0, 0.0, 10000.0, 10000.0)];
}

- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	CGFloat separator = [self cg_separatorWidth];
	CGFloat width = 4.0;
	CGFloat height = (_pathStyle == NSPathStyleNavigationBar) ? AG_PATH_SMALL_HEIGHT : AG_PATH_HEIGHT;
	NSUInteger i;

	for (i = 0; i < [_cells count]; i++) {
		NSSize size = [[_cells objectAtIndex:i] cellSizeForBounds:NSMakeRect(0.0, 0.0, aRect.size.width, height)];

		width += size.width + 2.0 * AG_PATH_PADDING;
		if (i + 1 < [_cells count]) {
			width += separator;
		}
	}
	if (aRect.size.width > 0.0 && width > aRect.size.width) {
		width = aRect.size.width;
	}
	if (aRect.size.height > 0.0 && height > aRect.size.height) {
		height = aRect.size.height;
	}
	return NSMakeSize(width, height);
}

- (CGFloat)cg_separatorWidth
{
	return (_pathStyle == NSPathStyleNavigationBar) ? AG_PATH_SEPARATOR_NAV : AG_PATH_SEPARATOR_STANDARD;
}

- (void)cg_layoutInFrame:(NSRect)frame rects:(NSRect *)rects visible:(BOOL *)visible
	    ellipsisRect:(NSRect *)ellipsisRect count:(NSUInteger)count
{
	CGFloat *widths;
	CGFloat separator = [self cg_separatorWidth];
	CGFloat height = frame.size.height - 4.0;
	CGFloat y = frame.origin.y + 2.0;
	CGFloat total = 0.0;
	NSUInteger i;

	for (i = 0; i < count; i++) {
		rects[i] = NSZeroRect;
		visible[i] = NO;
	}
	*ellipsisRect = NSZeroRect;
	if (count == 0) {
		return;
	}
	if (height < 0.0) {
		height = 0.0;
	}
	widths = (CGFloat *)malloc(sizeof(CGFloat) * count);
	for (i = 0; i < count; i++) {
		NSPathComponentCell *cell = [_cells objectAtIndex:i];
		NSSize size = [cell cellSizeForBounds:NSMakeRect(0.0, 0.0, frame.size.width, height)];

		widths[i] = size.width + 2.0 * AG_PATH_PADDING;
		if (widths[i] < 20.0) {
			widths[i] = 20.0;
		}
	}
	if (_pathStyle == NSPathStylePopUp) {
		rects[count - 1] = NSMakeRect(frame.origin.x + 4.0, y,
					      fmax(0.0, frame.size.width - 28.0), height);
		visible[count - 1] = YES;
		free(widths);
		return;
	}
	for (i = 0; i < count; i++) {
		total += widths[i];
		if (i + 1 < count) {
			total += separator;
		}
	}
	if (count == 1 || total <= frame.size.width - 4.0) {
		CGFloat x = frame.origin.x + 2.0;

		for (i = 0; i < count; i++) {
			rects[i] = NSMakeRect(x, y, widths[i], height);
			visible[i] = YES;
			x += widths[i] + separator;
		}
		free(widths);
		return;
	}

	/* THE MIDDLE TRUNCATES; THE TWO ENDS STAY. The last component is reserved first, then the ellipsis, then the
	 * middle components are taken from the end backwards for as long as they fit. */
	{
		CGFloat x = frame.origin.x + 2.0;
		CGFloat right = frame.origin.x + frame.size.width - 2.0;
		CGFloat firstWidth = fmin(widths[0], fmax(0.0, right - x));
		CGFloat lastWidth;
		CGFloat middleRoom;

		lastWidth = fmin(widths[count - 1], fmax(0.0, right - x - firstWidth - separator));
		middleRoom = right - x - firstWidth - separator - lastWidth - separator;
		if (middleRoom < 0.0) {
			middleRoom = 0.0;
		}
		if (count > 2) {
			if (middleRoom >= AG_PATH_ELLIPSIS_WIDTH + separator) {
				middleRoom -= AG_PATH_ELLIPSIS_WIDTH + separator;
				*ellipsisRect = NSMakeRect(x + firstWidth + separator, y,
							   AG_PATH_ELLIPSIS_WIDTH, height);
			} else {
				middleRoom = 0.0;
			}
		}
		for (i = count - 2; i > 0; i--) {
			if (widths[i] + (i > 1 ? separator : 0.0) <= middleRoom) {
				visible[i] = YES;
				middleRoom -= widths[i] + (i > 1 ? separator : 0.0);
			} else {
				break;
			}
		}
		rects[0] = NSMakeRect(x, y, firstWidth, height);
		visible[0] = YES;
		x += firstWidth + separator;
		if (!NSIsEmptyRect(*ellipsisRect)) {
			x += AG_PATH_ELLIPSIS_WIDTH + separator;
		}
		for (i = 1; i < count - 1; i++) {
			if (visible[i]) {
				rects[i] = NSMakeRect(x, y, widths[i], height);
				x += widths[i] + separator;
			}
		}
		lastWidth = fmax(0.0, right - x);
		if (lastWidth > widths[count - 1]) {
			lastWidth = widths[count - 1];
		}
		rects[count - 1] = NSMakeRect(x, y, lastWidth, height);
		visible[count - 1] = YES;
	}
	free(widths);
}

- (NSRect)rectOfPathComponentCell:(NSPathComponentCell *)cell
			withFrame:(NSRect)frame inView:(NSView *)view
{
	NSUInteger count = [_cells count];
	NSUInteger index = [_cells indexOfObjectIdenticalTo:cell];
	NSRect *rects;
	BOOL *visible;
	NSRect ellipsis;
	NSRect result = NSZeroRect;

	(void)view;
	if (index == NSNotFound || count == 0) {
		return NSZeroRect;
	}
	rects = (NSRect *)malloc(sizeof(NSRect) * count);
	visible = (BOOL *)malloc(sizeof(BOOL) * count);
	[self cg_layoutInFrame:frame rects:rects visible:visible ellipsisRect:&ellipsis count:count];
	if (visible[index]) {
		result = rects[index];
	}
	free(rects);
	free(visible);
	return result;
}

- (NSPathComponentCell *)pathComponentCellAtPoint:(NSPoint)point
					withFrame:(NSRect)frame inView:(NSView *)view
{
	NSUInteger count = [_cells count];
	NSRect *rects;
	BOOL *visible;
	NSRect ellipsis;
	NSUInteger i;
	NSPathComponentCell *found = nil;

	(void)view;
	if (count == 0) {
		return nil;
	}
	rects = (NSRect *)malloc(sizeof(NSRect) * count);
	visible = (BOOL *)malloc(sizeof(BOOL) * count);
	[self cg_layoutInFrame:frame rects:rects visible:visible ellipsisRect:&ellipsis count:count];
	for (i = 0; i < count; i++) {
		if (visible[i] && NSPointInRect(point, rects[i])) {
			found = [_cells objectAtIndex:i];
			break;
		}
	}
	free(rects);
	free(visible);
	return found;
}

/* ---- THE POINTER -------------------------------------------------------------------------------- */

- (void)mouseEntered:(NSEvent *)event withFrame:(NSRect)frame inView:(NSView *)view
{
	NSPoint point = (view != nil) ? [view convertPoint:[event locationInWindow] fromView:nil]
				      : [event locationInWindow];
	NSPathComponentCell *cell = [self pathComponentCellAtPoint:point withFrame:frame inView:view];

	if (cell != _hoveredCell) {
		_hoveredCell = cell;
		[self cg_redraw];
	}
}

- (void)mouseExited:(NSEvent *)event withFrame:(NSRect)frame inView:(NSView *)view
{
	(void)event;
	(void)frame;
	(void)view;
	if (_hoveredCell != nil) {
		_hoveredCell = nil;
		[self cg_redraw];
	}
}

/* ---- TRACKING ----------------------------------------------------------------------------------- */

- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
	NSRect frame = (controlView != nil) ? [controlView bounds] : NSZeroRect;

	_clickedCell = [self pathComponentCellAtPoint:startPoint withFrame:frame inView:controlView];
	[self cg_redraw];
	return YES;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint inView:(NSView *)controlView
{
	NSRect frame = (controlView != nil) ? [controlView bounds] : NSZeroRect;
	NSPathComponentCell *cell = [self pathComponentCellAtPoint:currentPoint withFrame:frame inView:controlView];

	if (cell != _clickedCell) {
		_clickedCell = cell;
		[self cg_redraw];
	}
	return YES;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
	NSRect frame = (controlView != nil) ? [controlView bounds] : NSZeroRect;
	NSPathComponentCell *cell = [self pathComponentCellAtPoint:stopPoint withFrame:frame inView:controlView];

	if (flag) {
		_clickedCell = cell;
	} else {
		_clickedCell = nil;
	}
	[self cg_redraw];
	(void)lastPoint;
}

/* ---- DRAWING ------------------------------------------------------------------------------------ */

- (void)cg_drawChevronAtX:(CGFloat)x y:(CGFloat)y height:(CGFloat)height
{
	NSBezierPath *chevron = [NSBezierPath bezierPath];
	CGFloat mid = y + height / 2.0;
	CGFloat width = (_pathStyle == NSPathStyleNavigationBar) ? 5.0 : 4.0;
	CGFloat half = (_pathStyle == NSPathStyleNavigationBar) ? 4.5 : 3.5;

	[[NSColor controlDarkShadowColor] setStroke];
	[chevron setLineWidth:(_pathStyle == NSPathStyleNavigationBar) ? 2.0 : 1.0];
	[chevron moveToPoint:NSMakePoint(x, mid - half)];
	[chevron lineToPoint:NSMakePoint(x + width, mid)];
	[chevron lineToPoint:NSMakePoint(x, mid + half)];
	[chevron stroke];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSUInteger count = [_cells count];
	NSRect *rects;
	BOOL *visible;
	NSRect ellipsis;
	NSUInteger i;

	if (_backgroundColor != nil) {
		[_backgroundColor setFill];
		if (_pathStyle == NSPathStyleStandard) {
			[[NSBezierPath bezierPathWithRect:cellFrame] fill];
		} else {
			[[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cellFrame, 0.5, 0.5)
							 xRadius:3.0 yRadius:3.0] fill];
			[[NSColor controlDarkShadowColor] setStroke];
			{
				NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(cellFrame, 0.5, 0.5)
										       xRadius:3.0 yRadius:3.0];

				[border setLineWidth:1.0];
				[border stroke];
			}
		}
	}
	if (count == 0) {
		NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			font, NSFontAttributeName, [NSColor disabledControlTextColor], NSForegroundColorAttributeName, nil];
		NSString *placeholder = _placeholderString;

		if (_placeholderAttributedString != nil) {
			NSSize size = [_placeholderAttributedString size];

			[_placeholderAttributedString drawAtPoint:NSMakePoint(cellFrame.origin.x + 6.0,
									     NSMidY(cellFrame) - size.height / 2.0)];
		} else if (placeholder != nil && [placeholder length] > 0) {
			NSSize size = [placeholder sizeWithAttributes:attributes];
			CGFloat ascender = [font ascender];
			CGFloat descent = (CGFloat)fabs((double)[font descender]);
			CGFloat baseline = NSMidY(cellFrame) - (ascender - descent) / 2.0;

			(void)size;
			[placeholder drawAtPoint:NSMakePoint(cellFrame.origin.x + 6.0, baseline)
				  withAttributes:attributes];
		}
		return;
	}

	rects = (NSRect *)malloc(sizeof(NSRect) * count);
	visible = (BOOL *)malloc(sizeof(BOOL) * count);
	[self cg_layoutInFrame:cellFrame rects:rects visible:visible ellipsisRect:&ellipsis count:count];

	for (i = 0; i < count; i++) {
		NSPathComponentCell *cell;

		if (!visible[i]) {
			continue;
		}
		cell = [_cells objectAtIndex:i];
		[cell setControlView:controlView];
		[cell setEnabled:[self isEnabled]];
		[cell setHighlighted:(cell == _clickedCell)];
		if (cell == _clickedCell || cell == _hoveredCell) {
			NSBezierPath *plate = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rects[i], 1.0, 1.0)
									   xRadius:3.0 yRadius:3.0];

			/* THE CLICKED CELL IS A HIGHLIGHT LIKE ANY OTHER, so it wears the platform's accent; the cell merely
			 * hovered keeps the grey, which is the pointer's answer rather than a selection. */
			[[cell == _clickedCell ? [NSColor cg_accentColor]
					       : [NSColor controlHighlightColor] colorWithAlphaComponent:0.65] setFill];
			[plate fill];
		}
		[cell drawInteriorWithFrame:rects[i] inView:controlView];
	}
	if (!NSIsEmptyRect(ellipsis)) {
		NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			font, NSFontAttributeName, [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
		NSSize size = [@"…" sizeWithAttributes:attributes];
		CGFloat ascender = [font ascender];
		CGFloat descent = (CGFloat)fabs((double)[font descender]);

		[@"…" drawAtPoint:NSMakePoint(NSMidX(ellipsis) - size.width / 2.0,
					       NSMidY(ellipsis) - (ascender - descent) / 2.0)
		 withAttributes:attributes];
	}
	/* SEPARATORS AFTER THE PLATES AND THE LABELS, so a selected plate cannot erase one. */
	for (i = 0; i < count; i++) {
		if (visible[i] && i + 1 < count) {
			[self cg_drawChevronAtX:NSMaxX(rects[i]) + 3.0
					     y:NSMinY(rects[i])
					height:NSHeight(rects[i])];
		}
		if (i == 0 && !NSIsEmptyRect(ellipsis)) {
			[self cg_drawChevronAtX:NSMaxX(ellipsis) + 3.0
					     y:NSMinY(ellipsis)
					height:NSHeight(ellipsis)];
		}
	}
	if (_pathStyle == NSPathStylePopUp) {
		/* THE POP-UP STYLE'S CHIP: a down chevron at the trailing edge. */
		NSBezierPath *down = [NSBezierPath bezierPath];
		CGFloat cx = NSMaxX(cellFrame) - 12.0;
		CGFloat cy = NSMidY(cellFrame);

		[[NSColor controlDarkShadowColor] setStroke];
		[down setLineWidth:1.5];
		[down moveToPoint:NSMakePoint(cx - 4.0, cy + 2.0)];
		[down lineToPoint:NSMakePoint(cx, cy - 2.0)];
		[down lineToPoint:NSMakePoint(cx + 4.0, cy + 2.0)];
		[down stroke];
	}
	free(rects);
	free(visible);
}

/* ---- THE PopUp MENU ----------------------------------------------------------------------------- */

- (void)cg_popUpMenuWithEvent:(NSEvent *)event inView:(NSView *)view
{
	NSMenu *menu = [self menu];
	BOOL owned = NO;
	NSUInteger i;
	NSPoint location;

	if (menu == nil) {
		menu = [[NSMenu alloc] initWithTitle:@"Path"];
		owned = YES;
		for (i = 0; i < [_cells count]; i++) {
			NSPathComponentCell *cell = [_cells objectAtIndex:i];
			NSString *title = [cell stringValue];
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:(title != nil ? title : @"")
								      action:@selector(cg_pathMenuSelected:)
							       keyEquivalent:@""];

			[item setTarget:self];
			[item setRepresentedObject:cell];
			[menu addItem:item];
			[item release];
		}
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(pathCell:willPopUpMenu:)]) {
		[_delegate pathCell:self willPopUpMenu:menu];
	}
	location = (view != nil) ? [view convertPoint:[event locationInWindow] fromView:nil]
				 : [event locationInWindow];
	[menu popUpMenuPositioningItem:nil atLocation:location inView:view];
	if (owned) {
		[menu release];
	}
}

- (void)cg_pathMenuSelected:(id)sender
{
	NSPathComponentCell *cell = [sender representedObject];

	if ([cell isKindOfClass:[NSPathComponentCell class]]) {
		_clickedCell = cell;
		[self cg_redraw];
		if (_controlView != nil && [_controlView respondsToSelector:@selector(sendAction:to:)]) {
			[(NSControl *)_controlView sendAction:[self action] to:[self target]];
		}
	}
}

@end
