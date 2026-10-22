/*
 * NSBox.h — A FRAME AROUND OTHER VIEWS, WITH AN OPTIONAL TITLE.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A BOX IS A BORDER, A TITLE AND A CONTENT VIEW, AND THAT IS ALL IT IS.** It groups controls on a form: the border is
 * drawn from the border type and width, the title sits at one of the seven positions the era names, and the CONTENT VIEW
 * — an ordinary `NSView` the box owns — holds whatever the caller puts in it. The box's frame is the border; the content's
 * frame is what is inside, which is the arithmetic `-contentViewMargins`, `-titleRect` and `-borderRect` all speak.
 *
 * **WHAT IS DRAWN AND WHAT IS NOT, STATED.** The five box types are Apple's vocabulary: a primary or secondary box is a
 * rounded bezel in the platform's control colour, a separator is one line, the old-style box is a square line, and a CUSTOM
 * box takes the fill, border colour, width and corner radius a caller set. The drawing uses the same platform helpers a
 * field and a table header use (`NSDrawGrayBezel`, `NSDrawGroove`, `NSFrameRect`), so a box looks like the boxes beside it.
 *
 * **THE TITLE IS A CELL, WHICH IS APPLE'S SHAPE**: `-titleCell` answers an `NSCell` the box draws in `-titleRect`, so a
 * caller can change the title's face and alignment through the cell exactly as it would through a button's. The
 * `-titleFont` pair is the convenience over that cell.
 */
#ifndef APPKIT_NSBOX_H
#define APPKIT_NSBOX_H

#import <AppKit/NSView.h>
#import <AppKit/NSGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class NSCell;
@class NSColor;
@class NSFont;

/* **THE FIVE KINDS OF BOX, IN APPLE'S ORDER.** The custom one is the only kind whose look a caller composes. */
typedef NSUInteger NSBoxType;
enum {
	NSBoxPrimary = 0,
	NSBoxSecondary = 1,
	NSBoxSeparator = 2,
	NSBoxOldStyle = 3,
	NSBoxCustom = 4
};

/* **AND WHERE THE TITLE SITS.** The bottom three exist because a box's title can be under the border as well as over it;
 * `NSAtTop` and `NSAboveTop` are the two a form uses. */
typedef NSUInteger NSTitlePosition;
enum {
	NSNoTitle = 0,
	NSAboveTop = 1,
	NSAtTop = 2,
	NSBelowTop = 3,
	NSAboveBottom = 4,
	NSAtBottom = 5,
	NSBelowBottom = 6
};

@interface NSBox : NSView
{
	NSBoxType _boxType;
	NSBorderType _borderType;
	CGFloat _borderWidth;
	CGFloat _cornerRadius;
	NSTitlePosition _titlePosition;
	/* THE TITLE LIVES IN A CELL, which is what draws it and what a caller reaches to change its face. */
	NSCell *_titleCell;		/* RETAINED */
	NSFont *_titleFont;		/* RETAINED */
	NSSize _contentViewMargins;
	BOOL _transparent;
	NSColor *_fillColor;		/* RETAINED */
	NSColor *_borderColor;		/* RETAINED */
	/* **THE CONTENT VIEW IS A SUBVIEW**, which is how a box holds views without a second hierarchy: the box's own subviews
	 * are its content view, and everything the caller adds is added to that. */
	NSView *_contentView;		/* RETAINED: the box owns it */
}

/* THE KIND AND THE FOUR NUMBERS A CUSTOM BOX DRAWS WITH. */
- (NSBoxType)boxType;
- (void)setBoxType:(NSBoxType)boxType;
- (NSBorderType)borderType;
- (void)setBorderType:(NSBorderType)borderType;
- (CGFloat)borderWidth;
- (void)setBorderWidth:(CGFloat)borderWidth;
- (CGFloat)cornerRadius;
- (void)setCornerRadius:(CGFloat)radius;

/* THE TWO COLOURS A CUSTOM BOX FILLS AND OUTLINES WITH. */
- (nullable NSColor *)fillColor;
- (void)setFillColor:(nullable NSColor *)color;
- (nullable NSColor *)borderColor;
- (void)setBorderColor:(nullable NSColor *)color;

/* WHETHER THE FILL IS DRAWN AT ALL — a transparent box is its border and its title. */
- (BOOL)isTransparent;
- (void)setTransparent:(BOOL)flag;

/* THE TITLE: the string, the position, the cell that draws it, and the font that cell uses. */
- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)title;
/* The era's marker rule: `&&` is one literal `&`, a single `&` introduces a mnemonic and is removed. */
- (void)setTitleWithMnemonic:(nullable NSString *)title;
- (NSTitlePosition)titlePosition;
- (void)setTitlePosition:(NSTitlePosition)position;
- (NSCell *)titleCell;
- (nullable NSFont *)titleFont;
- (void)setTitleFont:(nullable NSFont *)font;

/* THE CONTENT VIEW AND THE MARGINS AROUND IT. Setting the content view ADOPTS it as a subview; the old one is removed. */
- (void)setContentView:(nullable NSView *)view;
- (nullable NSView *)contentView;
- (NSSize)contentViewMargins;
- (void)setContentViewMargins:(NSSize)offsetSize;

/* THE THREE RECTANGLES THE BOX DRAWS AND LAYS OUT WITH: the border's, the title's, and (through `-setFrameFromContentFrame:`)
 * the frame that makes the CONTENT a given size. */
- (NSRect)borderRect;
- (NSRect)titleRect;
- (void)setFrameFromContentFrame:(NSRect)contentFrame;

/* Fit the box to its content view's size plus the margins and the title. */
- (void)sizeToFit;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSBOX_H */
