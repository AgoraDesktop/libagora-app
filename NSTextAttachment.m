/*
 * NSTextAttachment.m — the attachment, its picture, and the cell that draws it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CELL IS THE ONLY THING HERE WITH ARITHMETIC, AND IT IS THE IMAGE'S OWN SIZE.** `NSTextAttachment` is two
 * retained pointers and the convenience that gives a picture an attachment cell when it has none; the cell answers
 * its size from its image and draws that image into the frame it is handed. Everything else a cell can do — tracking,
 * highlighting, a baseline offset other than zero — is named as owed in the header.
 */
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSView.h>

@implementation NSTextAttachmentCell

/* **THE SIZE IS THE IMAGE'S, WHICH IS WHY THIS OVERRIDES THE BASE'S TYPE-BASED MEASUREMENT.** A cell with no image
 * answers zero rather than the base's "no opinion" sentinel, because an attachment with nothing to draw occupies
 * nothing. */
- (NSSize)cellSize
{
	NSImage *image = [self image];

	return (image != nil) ? [image size] : NSZeroSize;
}

/* A PICTURE SITS ON THE BASELINE, so the offset from the cell's origin to the baseline is zero in this tier's reading
 * — the manager places the frame ABOVE the baseline itself. Apple's own value for an image cell is derived from the
 * image; this is the simpler rule this tier draws by, stated here. */
- (NSPoint)cellBaselineOffset
{
	return NSZeroPoint;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	(void)controlView;
	[[self image] drawInRect:cellFrame];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView characterIndex:(NSUInteger)charIndex
{
	(void)charIndex;
	[self drawWithFrame:cellFrame inView:controlView];
}

@end

@implementation NSTextAttachment

+ (NSTextAttachment *)textAttachmentWithImage:(NSImage *)image
{
	NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];

	[attachment setImage:image];
	return attachment;
}

- (void)dealloc
{
	[_image release];
	[_attachmentCell release];
	[super dealloc];
}

- (NSImage *)image
{
	return _image;
}

/* **AND SETTING THE PICTURE GIVES THE ATTACHMENT A CELL TO DRAW IT WITH, IF IT HAS NONE.** That is the convenience
 * Apple's own `-setImage:` is: a caller with a picture should not have to make a cell to see it, and a caller who
 * WANTS a cell of their own sets the image first and then replaces the cell. */
- (void)setImage:(NSImage *)image
{
	if (image != _image) {
		id held = [image retain];

		[_image release];
		_image = held;
	}
	if (_attachmentCell == nil && image != nil) {
		NSTextAttachmentCell *cell = [[NSTextAttachmentCell alloc] init];

		[cell setImage:image];
		[self setAttachmentCell:cell];
		[cell release];
	}
}

- (NSCell<NSTextAttachmentCell> *)attachmentCell
{
	return _attachmentCell;
}

- (void)setAttachmentCell:(NSCell<NSTextAttachmentCell> *)cell
{
	if (cell != _attachmentCell) {
		id held = [cell retain];

		[_attachmentCell release];
		_attachmentCell = held;
	}
}

@end
