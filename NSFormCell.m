/*
 * NSFormCell — a form's entry: a label, and a field beside it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **ONE STRING IS THE VALUE AND THE OTHER IS THE TITLE, AND THE BOUNDARY BETWEEN THEM IS ONE NUMBER.** Everything in
 * this file is that sentence: `-drawingRectForBounds:` is "the value band, inset", `-titleWidth:` is the measurement
 * that decides where it starts, and the drawing is two strings placed in the two bands. The editing session needs no
 * code at all, because `NSCell -selectWithFrame:…` already puts the field editor in `-drawingRectForBounds:` — so the
 * editor lands in the value band by construction rather than by a second placement path that could disagree.
 *
 * THE TWO STRINGS' INK IS `NSTextFieldCell`'S ARITHMETIC, REUSED RATHER THAN REINVENTED: a line is drawn at a baseline
 * computed from the font's ascent and descent, centred on the band, with the sign of the correction taken from the
 * graphics context's own transform so a flipped context puts the line in the same place as an unflipped one. That is
 * the same measurement `NSTextFieldCell -cg_centredBaselineInFrame:font:` documents; it is repeated here because this
 * cell is not a text-field cell and inheriting the door would mean inheriting the class.
 */
#import <AppKit/NSFormCell.h>

#import <AppKit/NSAttributedString.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>

#include <math.h>

@interface NSFormCell ()
- (NSAttributedString *)fn_titleText;
- (NSAttributedString *)fn_placeholderText;
- (CGFloat)fn_titleBandWidthForBounds:(NSRect)bounds;
- (NSRect)fn_fieldRectForBounds:(NSRect)bounds;
- (NSRect)fn_titleRectForBounds:(NSRect)bounds;
- (NSColor *)fn_inkColor;
- (void)fn_drawString:(NSString *)string attributed:(NSAttributedString *)attributed
	     inRect:(NSRect)rect ink:(NSColor *)ink font:(NSFont *)font alignment:(NSTextAlignment)alignment;
@end

@implementation NSFormCell

/* ============================================================================================ *
 * LIFETIME AND THE DEFAULTS THE HEADER NAMES.                                                   *
 * ============================================================================================ */

- (instancetype)initTextCell:(NSString *)aString
{
	self = [super initTextCell:aString];
	if (self != nil) {
		/* **THE THREE DEFAULTS THAT ARE NOT ZERO ARE WRITTEN OUT** — see the header: the title is right-aligned, the
		 * title font is bold, and the width is zero MEANING measured. The direction is the natural one, which is 1 in
		 * this era rather than 0, the same trap `NSCell -init` records for `-baseWritingDirection`. */
		_titleFont = [[NSFont boldSystemFontOfSize:[NSFont systemFontSize]] retain];
		_titleWidth = 0.0;
		_titleAlignment = NSRightTextAlignment;
		_titleBaseWritingDirection = NSWritingDirectionNatural;
	}
	return self;
}

- (void)dealloc
{
	[_titleFont release];
	[_placeholderString release];
	[_placeholderAttributedString release];
	[_attributedTitle release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE LABEL.                                                                                    *
 * ============================================================================================ */

- (NSFont *)titleFont
{
	return _titleFont;
}

- (void)setTitleFont:(NSFont *)font
{
	NSFont *old = _titleFont;

	_titleFont = [font retain];
	[old release];
}

- (void)setTitle:(NSString *)aString
{
	/* SETTING THE PLAIN TITLE DROPS AN ATTRIBUTED ONE, because the two are two spellings of one label and keeping both
	 * would leave which one is drawn to a caller who cannot see the rule. */
	[super setTitle:aString];
	[_attributedTitle release];
	_attributedTitle = nil;
}

- (NSAttributedString *)attributedTitle
{
	return [self fn_titleText];
}

- (void)setAttributedTitle:(NSAttributedString *)obj
{
	NSAttributedString *old = _attributedTitle;

	_attributedTitle = [obj retain];
	[old release];
	/* AND THE PLAIN TITLE FOLLOWS IT, so a caller that reads `-title` after setting an attributed one gets the same
	 * characters the label is drawn with rather than the label it replaced. */
	if (obj != nil) {
		[super setTitle:[obj string]];
	}
}

- (void)setTitleWithMnemonic:(NSString *)stringWithAmpersand
{
	[_attributedTitle release];
	_attributedTitle = nil;
	[super setTitleWithMnemonic:stringWithAmpersand];
}

- (CGFloat)titleWidth
{
	return _titleWidth;
}

- (void)setTitleWidth:(CGFloat)width
{
	_titleWidth = (width > 0.0) ? width : 0.0;
}

/* **THE MEASUREMENT THE BAND USES, INCLUDING THE GAP THE FIELD STARTS AFTER.** A title wider than the cell is clamped
 * to the cell, because a band wider than the cell is a negative field — which is the one arithmetic mistake that makes
 * `-drawingRectForBounds:` answer a rectangle that draws backwards. */
- (CGFloat)titleWidth:(NSSize)aSize
{
	NSAttributedString *title = [self fn_titleText];
	CGFloat measured;

	if (title == nil || [title length] == 0) {
		return 0.0;
	}
	measured = [title size].width + NS_CELL_CONTENT_GAP;
	if (measured > aSize.width) {
		measured = aSize.width;
	}
	return measured;
}

- (NSTextAlignment)titleAlignment
{
	return _titleAlignment;
}

- (void)setTitleAlignment:(NSTextAlignment)mode
{
	_titleAlignment = mode;
}

- (NSWritingDirection)titleBaseWritingDirection
{
	return _titleBaseWritingDirection;
}

- (void)setTitleBaseWritingDirection:(NSWritingDirection)mode
{
	_titleBaseWritingDirection = mode;
}

- (NSString *)placeholderString
{
	return _placeholderString;
}

- (void)setPlaceholderString:(NSString *)string
{
	NSString *old = _placeholderString;

	_placeholderString = [string copy];
	[old release];
}

- (NSAttributedString *)placeholderAttributedString
{
	return _placeholderAttributedString;
}

- (void)setPlaceholderAttributedString:(NSAttributedString *)string
{
	NSAttributedString *old = _placeholderAttributedString;

	_placeholderAttributedString = [string retain];
	[old release];
}

- (BOOL)isOpaque
{
	/* A FORM CELL PAINTS ITS LABEL AND ITS FIELD AND LEAVES THE REST ALONE — see the header. */
	return NO;
}

/* ============================================================================================ *
 * THE TWO BANDS.                                                                                *
 * ============================================================================================ */

- (CGFloat)fn_titleBandWidthForBounds:(NSRect)bounds
{
	if (_titleWidth > 0.0) {
		return (_titleWidth < NSWidth(bounds)) ? _titleWidth : NSWidth(bounds);
	}
	return [self titleWidth:bounds.size];
}

- (NSRect)fn_fieldRectForBounds:(NSRect)bounds
{
	CGFloat band = [self fn_titleBandWidthForBounds:bounds];

	return NSMakeRect(NSMinX(bounds) + band, NSMinY(bounds), NSWidth(bounds) - band, NSHeight(bounds));
}

- (NSRect)fn_titleRectForBounds:(NSRect)bounds
{
	CGFloat band = [self fn_titleBandWidthForBounds:bounds];
	CGFloat air = (band > NS_CELL_CONTENT_GAP) ? NS_CELL_CONTENT_GAP : 0.0;

	return NSMakeRect(NSMinX(bounds), NSMinY(bounds), band - air, NSHeight(bounds));
}

/* **THE VALUE BAND, INSET** — which is the field editor's frame as well, because `NSCell` asks this door for both. */
- (NSRect)drawingRectForBounds:(NSRect)theRect
{
	return NSInsetRect([self fn_fieldRectForBounds:theRect], NS_TEXT_INSET, NS_TEXT_INSET);
}

/* ============================================================================================ *
 * THE INK.                                                                                      *
 * ============================================================================================ */

- (NSColor *)fn_inkColor
{
	return [self isEnabled] ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];
}

- (NSAttributedString *)fn_titleText
{
	if (_attributedTitle != nil) {
		return _attributedTitle;
	}
	if ([self title] == nil) {
		return nil;
	}
	{
		NSFont *font = (_titleFont != nil) ? _titleFont : [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];

		return [[[NSAttributedString alloc] initWithString:[self title]
						       attributes:[NSDictionary dictionaryWithObjectsAndKeys:
								font, NSFontAttributeName,
								[self fn_inkColor], NSForegroundColorAttributeName,
								nil]] autorelease];
	}
}

- (NSAttributedString *)fn_placeholderText
{
	if (_placeholderAttributedString != nil) {
		return _placeholderAttributedString;
	}
	if (_placeholderString == nil) {
		return nil;
	}
	return [[[NSAttributedString alloc] initWithString:_placeholderString
					       attributes:[NSDictionary dictionaryWithObjectsAndKeys:
							[self font], NSFontAttributeName,
							[NSColor disabledControlTextColor], NSForegroundColorAttributeName,
							nil]] autorelease];
}

/* **THE BASELINE THAT PUTS A LINE'S MIDDLE ON THE BAND'S MIDDLE, IN EITHER Y DIRECTION** — the same arithmetic, and
 * the same reason, `NSTextFieldCell -cg_centredBaselineInFrame:font:` records: the context's transform is read rather
 * than assumed, because a bitmap a flipped view draws into is not flipped itself. */
- (void)fn_drawString:(NSString *)string attributed:(NSAttributedString *)attributed
	       inRect:(NSRect)rect ink:(NSColor *)ink font:(NSFont *)font alignment:(NSTextAlignment)alignment
{
	NSDictionary *attributes;
	NSSize size;
	CGFloat x, baseline;
	CGContextRef cg = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	CGAffineTransform transform = (cg != NULL) ? CGContextGetCTM(cg) : CGAffineTransformIdentity;

	if (font == nil) {
		font = (_titleFont != nil) ? _titleFont : [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	if (attributed != nil) {
		size = [attributed size];
	} else {
		attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, ink,
			      NSForegroundColorAttributeName, nil];
		size = [string sizeWithAttributes:attributes];
	}
	if (size.width <= 0.0 || NSWidth(rect) <= 0.0) {
		return;
	}
	x = NSMinX(rect);
	if (alignment == NSCenterTextAlignment) {
		x = NSMinX(rect) + (NSWidth(rect) - size.width) / 2.0;
	} else if (alignment == NSRightTextAlignment) {
		x = NSMaxX(rect) - size.width;
	}
	if (x < NSMinX(rect)) {
		x = NSMinX(rect);
	}
	{
		CGFloat ascent = [font ascender];
		CGFloat descent = (CGFloat)fabs((double)[font descender]);
		CGFloat band = ceil(ascent + descent);

		baseline = NSMinY(rect) + (NSHeight(rect) - band) / 2.0
			   + ((transform.d >= 0.0) ? descent : (band - descent));
	}
	[NSGraphicsContext saveGraphicsState];
	/* THE CLIP IS THE BAND, INTERSECTED WITH THE CALLER'S — the same rule `NSTextFieldCell` records: a cell inside a
	 * table's clip must not replace it. */
	[[NSBezierPath bezierPathWithRect:rect] addClip];
	if (attributed != nil) {
		[attributed drawAtPoint:NSMakePoint(x, baseline)];
	} else {
		[string drawAtPoint:NSMakePoint(x, baseline) withAttributes:attributes];
	}
	[NSGraphicsContext restoreGraphicsState];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSRect field = [self fn_fieldRectForBounds:cellFrame];
	NSRect titleRect = [self fn_titleRectForBounds:cellFrame];
	NSAttributedString *title = [self fn_titleText];

	/* THE FIELD FIRST: its face, then its border, then the two strings. A cell that is neither bordered nor bezeled is
	 * a value band with no box, which is what an unbordered form entry is. */
	if ([self isBezeled] || [self isBordered]) {
		NSRect faceRect = NSInsetRect(field, NS_CELL_BEZEL_WIDTH / 2.0, NS_CELL_BEZEL_WIDTH / 2.0);
		NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:faceRect
								     xRadius:NS_CELL_BEZEL_RADIUS
								     yRadius:NS_CELL_BEZEL_RADIUS];

		[[NSColor controlBackgroundColor] setFill];
		[face fill];
		[[NSColor controlDarkShadowColor] setStroke];
		[face setLineWidth:NS_CELL_BEZEL_WIDTH];
		[face stroke];
	}
	if (title != nil && [title length] > 0) {
		[self fn_drawString:[title string] attributed:title inRect:titleRect
				ink:[self fn_inkColor] font:_titleFont alignment:_titleAlignment];
	}
	[self drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	/* **THE VALUE, OR THE HINT WHEN THERE IS NONE.** An editor that is up owns the words (the editor draws them), so
	 * the cell draws nothing where it would otherwise double the line — the same rule, and the same measurement,
	 * `NSTextFieldCell -drawInteriorWithFrame:` records. */
	NSString *value = [self stringValue];
	NSAttributedString *hint = [self fn_placeholderText];
	NSRect room = [self drawingRectForBounds:cellFrame];

	(void)controlView;
	if ([self cg_currentEditor] != nil) {
		return;
	}
	if (value == nil || [value length] == 0) {
		if (hint != nil) {
			[self fn_drawString:[hint string] attributed:hint inRect:room
					ink:[NSColor disabledControlTextColor] font:[self font] alignment:[self alignment]];
		}
		return;
	}
	[self fn_drawString:value attributed:nil inRect:room ink:[self fn_inkColor] font:[self font]
		    alignment:[self alignment]];
}

/* ============================================================================================ *
 * THE SESSION.                                                                                  *
 * ============================================================================================ */

/* **THE MATRIX IS ASKED FIRST, AND IT ASKS ITS DELEGATE.** A cell's editor delegates to the CELL (see
 * `NSCell -selectWithFrame:…`), so the cell is where a form's refusal has to be asked from — and the matrix above it is
 * the object that knows whether a delegate declared one. That is why these two doors exist on a form cell at all. */
- (BOOL)textShouldBeginEditing:(NSText *)textObject
{
	id control = [self controlView];

	if (control != nil && [control respondsToSelector:@selector(textShouldBeginEditing:)]) {
		return (BOOL)[control textShouldBeginEditing:textObject];
	}
	return [super textShouldBeginEditing:textObject];
}

- (BOOL)textShouldEndEditing:(NSText *)textObject
{
	id control = [self controlView];

	if (control != nil && [control respondsToSelector:@selector(textShouldEndEditing:)]) {
		return (BOOL)[control textShouldEndEditing:textObject];
	}
	return [super textShouldEndEditing:textObject];
}

/* ============================================================================================ *
 * ARCHIVING: THE LABEL AND ITS HINT.                                                            *
 * ============================================================================================ */

static NSString * const AGCoderFormTitleFontKey = @"NSFormCellTitleFont";
static NSString * const AGCoderFormTitleWidthKey = @"NSFormCellTitleWidth";
static NSString * const AGCoderFormTitleAlignmentKey = @"NSFormCellTitleAlignment";
static NSString * const AGCoderFormTitleDirectionKey = @"NSFormCellTitleBaseWritingDirection";
static NSString * const AGCoderFormPlaceholderKey = @"NSFormCellPlaceholder";
static NSString * const AGCoderFormAttributedPlaceholderKey = @"NSFormCellAttributedPlaceholder";
static NSString * const AGCoderFormAttributedTitleKey = @"NSFormCellAttributedTitle";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeObject:_titleFont forKey:AGCoderFormTitleFontKey];
	[aCoder encodeDouble:(double)_titleWidth forKey:AGCoderFormTitleWidthKey];
	[aCoder encodeInteger:(NSInteger)_titleAlignment forKey:AGCoderFormTitleAlignmentKey];
	[aCoder encodeInteger:(NSInteger)_titleBaseWritingDirection forKey:AGCoderFormTitleDirectionKey];
	[aCoder encodeObject:_placeholderString forKey:AGCoderFormPlaceholderKey];
	[aCoder encodeObject:_placeholderAttributedString forKey:AGCoderFormAttributedPlaceholderKey];
	[aCoder encodeObject:_attributedTitle forKey:AGCoderFormAttributedTitleKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderFormTitleFontKey]) {
		_titleFont = [[aDecoder decodeObjectForKey:AGCoderFormTitleFontKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderFormTitleWidthKey]) {
		_titleWidth = (CGFloat)[aDecoder decodeDoubleForKey:AGCoderFormTitleWidthKey];
	}
	if ([aDecoder containsValueForKey:AGCoderFormTitleAlignmentKey]) {
		_titleAlignment = (NSTextAlignment)[aDecoder decodeIntegerForKey:AGCoderFormTitleAlignmentKey];
	}
	if ([aDecoder containsValueForKey:AGCoderFormTitleDirectionKey]) {
		_titleBaseWritingDirection =
			(NSWritingDirection)[aDecoder decodeIntegerForKey:AGCoderFormTitleDirectionKey];
	}
	if ([aDecoder containsValueForKey:AGCoderFormPlaceholderKey]) {
		_placeholderString = [[aDecoder decodeObjectForKey:AGCoderFormPlaceholderKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderFormAttributedPlaceholderKey]) {
		_placeholderAttributedString =
			[[aDecoder decodeObjectForKey:AGCoderFormAttributedPlaceholderKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderFormAttributedTitleKey]) {
		_attributedTitle = [[aDecoder decodeObjectForKey:AGCoderFormAttributedTitleKey] retain];
	}
	/* **THE DEFAULTS ARE APPLIED ONLY WHEN THE ARCHIVE DOES NOT CARRY THEM**, so a nib whose author never touched the
	 * label still gets a bold, right-aligned title — the same "a zero in the storage is not the default" rule the
	 * initialiser states. */
	if (_titleFont == nil) {
		_titleFont = [[NSFont boldSystemFontOfSize:[NSFont systemFontSize]] retain];
	}
	if (![aDecoder containsValueForKey:AGCoderFormTitleAlignmentKey]) {
		_titleAlignment = NSRightTextAlignment;
	}
	if (![aDecoder containsValueForKey:AGCoderFormTitleDirectionKey]) {
		_titleBaseWritingDirection = NSWritingDirectionNatural;
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

@end
