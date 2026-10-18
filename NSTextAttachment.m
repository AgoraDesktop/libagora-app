/*
 * NSTextAttachment.m — the attachment, its picture, and the cell that draws it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CELL IS THE ONLY THING HERE WITH ARITHMETIC, AND IT IS THE IMAGE'S OWN SIZE.** `NSTextAttachment` is two
 * retained pointers and the convenience that gives a picture an attachment cell when it has none; the cell answers
 * its size from its image, draws that image into the frame it is handed, and TRACKS THE MOUSE — one event at a time,
 * because `NSTextView` owns the event stream and this tier does not run the modal loop `NSCell` refuses. A drag that
 * leaves the cell's frame clears the highlight and one that comes back restores it, which is the behaviour a pressed
 * picture needs; the up event answers whether the button came up inside the frame, Apple's own return for the end of
 * a tracking session.
 */
#import <AppKit/NSTextAttachment.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <Foundation/NSFileWrapper.h>

/* **WHERE AN EVENT IS, IN THE CELL'S OWN FRAME.** The view handed to the cell is the text view, so converting the
 * event's window location through it is what makes the comparison possible; a NIL VIEW is the quiet case and answers
 * YES, because a caller driving a cell with no view in front of it has no coordinates to disagree in. */
static BOOL ag_eventIsInsideCell(NSEvent *event, NSRect cellFrame, NSView *controlView)
{
	NSPoint point;

	if (controlView == nil) {
		return YES;
	}
	point = [controlView convertPoint:[event locationInWindow] fromView:nil];
	return NSPointInRect(point, cellFrame);
}

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
	/* **AND A PRESSED PICTURE IS DIMMED WITH THE PLATFORM'S SELECTION COLOUR.** The overlay lives HERE, in the drawing,
	 * rather than in `-highlight:`: that door sets the flag and marks the frame, and this one paints the state it set —
	 * the division `NSCell` states, and the reason a redraw after a drag comes out right. The alpha leaves the picture
	 * readable underneath, which is what makes this a highlight rather than a replacement. */
	if ([self isHighlighted]) {
		[[[NSColor selectedControlColor] colorWithAlphaComponent:0.35] setFill];
		[[NSBezierPath bezierPathWithRect:cellFrame] fill];
	}
}

/* **THE HIGHLIGHT'S STATE IS THE BASE'S, AND IT IS SET HERE EXPLICITLY BECAUSE THIS CLASS'S INK READS IT.** `NSCell`
 * stores the flag and asks the control view to redraw; the attachment's face is drawn by `-drawWithFrame:inView:`, so
 * the override exists to make that pairing visible rather than to change it. */
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	[super highlight:flag withFrame:cellFrame inView:controlView];
}

/* **THE DEFAULT CELL TRACKS, WHICH IS WHAT ITS CLICK AND DRAG BEHAVIOUR IS FOR.** A base cell with no image measures
 * zero and is never hit-tested (see the view's frame arithmetic), so answering YES here cannot make an empty cell
 * clickable; a subclass that draws content of its own inherits the useful answer. */
- (BOOL)wantsToTrackMouse
{
	return YES;
}

- (BOOL)wantsToTrackMouseForEvent:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView
		 atCharacterIndex:(NSUInteger)charIndex
{
	(void)theEvent;
	(void)cellFrame;
	(void)controlView;
	(void)charIndex;
	return [self wantsToTrackMouse];
}

/* **ONE EVENT, ONE CALL — THE WHOLE OF THIS TIER'S TRACKING CONTRACT IS IN THIS METHOD'S SHAPE.** `NSTextView` sends
 * the DOWN, every DRAG and the UP through this door, so the default cell highlights on the press, follows the pointer
 * in and out of its frame while the button is held, and clears the highlight on the release. The down and drag
 * answers mean "keep tracking"; the UP answer is Apple's own — whether the button came up inside `cellFrame`. */
- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag
{
	NSEventType type = [theEvent type];

	(void)flag;	/* the view tracks until the button is up, so there is no early-exit decision to make here */

	if (type == NSLeftMouseUp) {
		BOOL inside = ag_eventIsInsideCell(theEvent, cellFrame, controlView);

		[self highlight:NO withFrame:cellFrame inView:controlView];
		return inside;
	}
	if (type == NSLeftMouseDragged) {
		[self highlight:ag_eventIsInsideCell(theEvent, cellFrame, controlView)
			withFrame:cellFrame inView:controlView];
		return YES;
	}
	/* THE PRESS, and anything else the view chooses to forward. */
	[self highlight:YES withFrame:cellFrame inView:controlView];
	return YES;
}

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView
  atCharacterIndex:(NSUInteger)charIndex untilMouseUp:(BOOL)flag
{
	(void)charIndex;
	return [self trackMouse:theEvent inRect:cellFrame ofView:controlView untilMouseUp:flag];
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

/* **THE WRAPPER IS THE DESIGNATED INITIALISER'S ARGUMENT, which is Apple's own arrangement**: `-initWithFileWrapper:`
 * is what a package document calls with the file it found, and `-init` is that with nothing. */
- (instancetype)init
{
	return [self initWithFileWrapper:nil];
}

- (instancetype)initWithFileWrapper:(NSFileWrapper *)fileWrapper
{
	self = [super init];
	if (self != nil) {
		_fileWrapper = [fileWrapper retain];
	}
	return self;
}

- (void)dealloc
{
	[_image release];
	[_fileWrapper release];
	[_attachmentCell release];
	[super dealloc];
}

- (NSFileWrapper *)fileWrapper
{
	return _fileWrapper;
}

- (void)setFileWrapper:(NSFileWrapper *)fileWrapper
{
	if (fileWrapper != _fileWrapper) {
		id held = [fileWrapper retain];

		[_fileWrapper release];
		_fileWrapper = held;
	}
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
