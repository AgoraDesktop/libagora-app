/*
 * NSImageView.h — a control that shows one image, placed and framed like an image cell.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE VIEW IS THE CELL'S FACE AND THE TWO EDIT FLAGS.** `NSImageView` is the `NSControl` Apple makes it: the image,
 * its alignment, its scaling and its frame are `NSImageCell`'s, and the view forwards each door and redisplays. What
 * the view adds is the interaction: `-allowsCutCopyPaste` and `-isEditable` gate the standard cut/copy/paste/delete
 * commands, and `-animates` records whether a caller wants an animated image played.
 *
 * WHAT IS NOT DRAWN HERE, STATED: `-animates` is STORED AND ANSWERED but this tier's `NSImage` has no animation clock,
 * so no timer is made and each representation is not cycled. A caller's setting round-trips; nothing pretends the
 * image moved. `-copy:`/`-cut:` refuse by name because this tree's CoreGraphics has no `CGImageDestination` to encode
 * a TIFF (the same reason `NSImage -TIFFRepresentation` refuses), while `-paste:`/`-delete:` are real: the pasteboard
 * reader and the image field are both here.
 */
#ifndef APPKIT_NSIMAGEVIEW_H
#define APPKIT_NSIMAGEVIEW_H

#import <AppKit/NSControl.h>
#import <AppKit/NSImageCell.h>

NS_ASSUME_NONNULL_BEGIN

@class NSImage;

@interface NSImageView : NSControl
{
	BOOL _animates;
	BOOL _allowsCutCopyPaste;
}

/* THE CELL CLASS A FRESH IMAGE VIEW MAKES. */
+ (Class)cellClass;

/* THE IMAGE AND ITS THREE PLACEMENT FACTS — all forwards to the image cell, each with the redisplay a view owes. */
- (nullable NSImage *)image;
- (void)setImage:(nullable NSImage *)newImage;
- (NSImageAlignment)imageAlignment;
- (void)setImageAlignment:(NSImageAlignment)newAlignment;
- (NSImageScaling)imageScaling;
- (void)setImageScaling:(NSImageScaling)newScaling;
- (NSImageFrameStyle)imageFrameStyle;
- (void)setImageFrameStyle:(NSImageFrameStyle)newStyle;

/* THE TWO EDIT FLAGS. `-isEditable` is the CELL's editable flag; `-allowsCutCopyPaste` is the view's gate on the
 * standard commands. Both are needed for a paste or a delete to change the image. */
- (BOOL)isEditable;
- (void)setEditable:(BOOL)flag;
- (BOOL)allowsCutCopyPaste;
- (void)setAllowsCutCopyPaste:(BOOL)allow;

/* **THE ANIMATION FLAG, RECORDED RATHER THAN RUN.** See the header's note: this tier has no image animation clock. */
- (BOOL)animates;
- (void)setAnimates:(BOOL)flag;

/* THE STANDARD IMAGE COMMANDS. Copy and cut refuse by name through `NSImage -TIFFRepresentation` (no encoder);
 * paste reads the pasteboard's image types and delete clears the field. */
- (void)copy:(nullable id)sender;
- (void)cut:(nullable id)sender;
- (void)paste:(nullable id)sender;
- (void)delete:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSIMAGEVIEW_H */
