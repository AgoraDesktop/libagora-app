/*
 * NSImageCell.h — A CELL WHOSE CONTENT IS AN IMAGE, PLACED THREE WAYS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE IMAGE IS THE BASE CELL'S; THE THREE FACTS ABOUT IT ARE THIS CLASS'S.** `NSCell` already holds an image and draws it
 * — a button's face uses the same field — so an image cell is that image plus the era's three choices: how it ALIGNS in the
 * box (`NSCellImageAlignment`), how it SCALES when the box is not its size (`NSImageScaling`), and what FRAME is drawn around
 * it (`NSImageFrameStyle`). All three are drawn here, in pixels, because a cell that stored them and ignored them would be a
 * control that looked the same whatever a caller asked for.
 *
 * **THE DEFAULTS ARE APPLE'S**: image aligned left, no scaling, no frame. The two enums are declared beside the class if
 * this tier does not already have them, because they exist for nothing else.
 */
#ifndef APPKIT_NSIMAGECELL_H
#define APPKIT_NSIMAGECELL_H

#import <AppKit/NSCell.h>

NS_ASSUME_NONNULL_BEGIN

/* **HOW THE IMAGE SITS IN ITS BOX.** Apple's five values; the names are the era's. */
typedef NSInteger NSCellImageAlignment;
enum {
	NSImageAlignCenter = 0,
	NSImageAlignTop = 1,
	NSImageAlignTopLeft = 2,
	NSImageAlignTopRight = 3,
	NSImageAlignLeft = 4,
	NSImageAlignBottom = 5,
	NSImageAlignBottomLeft = 6,
	NSImageAlignBottomRight = 7,
	NSImageAlignRight = 8
};

/* **AND THE FRAME AROUND IT.** None, a line, a bezel or a groove. */
typedef NSInteger NSImageFrameStyle;
enum {
	NSImageFrameNone = 0,
	NSImageFramePhoto = 1,
	NSImageFrameGrayBezel = 2,
	NSImageFrameGroove = 3,
	NSImageFrameButton = 4
};

@interface NSImageCell : NSCell
{
	NSCellImageAlignment _imageAlignment;
	NSImageScaling _imageScaling;
	NSImageFrameStyle _imageFrameStyle;
}

- (NSCellImageAlignment)imageAlignment;
- (void)setImageAlignment:(NSCellImageAlignment)alignment;

/* `NSImageScaling` IS `NSCell.h`'s TYPE (the four `NSImageScale…` values), which is why this pair is not one of the enums
 * above: scaling is a shared vocabulary, and alignment and framing are an image cell's own. */
- (NSImageScaling)imageScaling;
- (void)setImageScaling:(NSImageScaling)scaling;

- (NSImageFrameStyle)imageFrameStyle;
- (void)setImageFrameStyle:(NSImageFrameStyle)frameStyle;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSIMAGECELL_H */
