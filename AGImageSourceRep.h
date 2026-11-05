/*
 * AGImageSourceRep.h — every image format this tree's CoreGraphics can decode, as a representation the AppKit can use.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **`NSBitmapImageRep` IS PNG AND JPEG BECAUSE THOSE ARE THE TWO FORMATS IT IMPLEMENTS**, and that is the right shape for it:
 * a bitmap rep owns a pixel chart and decodes into it. Every other format in this tree is decoded by `CGImageSource`, which
 * is one registry over `CGImagePNG.c`, `CGImageGIF.c`, `CGImageTIFF.c` and their siblings — so the AppKit's face over that
 * registry is a rep that holds a `CGImage` and a source, not a second decoder per format.
 *
 * **IT CLAIMS WHAT THE REGISTRY CLAIMS.** `+canInitWithData:` asks `CGImageSourceCreateWithData` and nothing else, so a
 * format added to the drawing library becomes a format this rep opens without a line changing here — which is the point of
 * having one registry rather than one `canInitWithData:` per format.
 *
 * **AND IT CARRIES THE FRAMES.** A GIF or a WebP animation is several images in one file, so the rep answers `-frameCount`
 * and `-setFrame:`, and a viewer animates by advancing the frame on a timer. A still image is a one-frame source and does not
 * know the difference.
 */
#import <AppKit/NSImageRep.h>

#import <CoreGraphics/CGImage.h>
#import <CoreGraphics/CGImageSource.h>

NS_ASSUME_NONNULL_BEGIN

@interface AGImageSourceRep : NSImageRep
{
	CGImageSourceRef _source;	/* RETAINED: the file's bytes, and the decoder the registry chose for them */
	CGImageRef _image;		/* RETAINED: the decoded frame */
	NSSize _cgFrameSize;		/* the frame's pixels, which `-size` and `-pixelsWide` answer from */
	NSUInteger _frame;
	NSUInteger _frameCount;
	CGFloat _delay;			/* seconds this frame is shown for; 0 when the format does not say */
}

/* THE FRAME DOORS. `-setFrame:` decodes on demand and answers NO for an index past the end. */
@property (readonly) NSUInteger frameCount;
@property (readonly) CGFloat frameDelay;
- (BOOL)setFrame:(NSUInteger)frame;

@end

NS_ASSUME_NONNULL_END
