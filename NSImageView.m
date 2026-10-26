/*
 * NSImageView — the image cell's face, plus the edit commands its flags gate.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **THE VIEW IS MOSTLY FORWARDS, WHICH IS THE CONTROL DESIGN.** The image, its alignment, scaling and frame live in
 * the `NSImageCell` because that is the class that draws them; the view only makes the cell, forwards each door and
 * marks itself for display. The interaction is the view's: cut/copy/paste/delete are the commands a menu sends, and
 * the two flags decide whether they do anything.
 */
#import "NSImageView.h"
#import "NSImage.h"
#import "NSPasteboard.h"

#import <Foundation/NSData.h>

@implementation NSImageView

+ (Class)cellClass
{
	return [NSImageCell class];
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSImageCell *cell = [[NSImageCell alloc] init];

		[cell setEnabled:YES];
		[self setCell:cell];
		[cell release];
		_animates = NO;
		_allowsCutCopyPaste = NO;
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self != nil) {
		if ([self cell] == nil) {
			NSImageCell *cell = [[NSImageCell alloc] init];

			[cell setEnabled:YES];
			[self setCell:cell];
			[cell release];
		}
		_animates = [aDecoder decodeBoolForKey:@"animates"];
		_allowsCutCopyPaste = [aDecoder decodeBoolForKey:@"allowsCutCopyPaste"];
		/* THE CELL'S EDIT FLAG, which the view forwards: it is design state and has no other home in this archive. */
		if ([aDecoder containsValueForKey:@"editable"]) {
			[self setEditable:[aDecoder decodeBoolForKey:@"editable"]];
		}
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeBool:_animates forKey:@"animates"];
	[aCoder encodeBool:_allowsCutCopyPaste forKey:@"allowsCutCopyPaste"];
	[aCoder encodeBool:[self isEditable] forKey:@"editable"];
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

/* ---- THE IMAGE AND ITS PLACEMENT ------------------------------------------------------------------ */

- (NSImage *)image
{
	return [(NSCell *)[self cell] image];
}

- (void)setImage:(NSImage *)newImage
{
	[(NSCell *)[self cell] setImage:newImage];
	[self setNeedsDisplay:YES];
}

- (NSImageAlignment)imageAlignment
{
	return [(NSImageCell *)[self cell] imageAlignment];
}

- (void)setImageAlignment:(NSImageAlignment)newAlignment
{
	[(NSImageCell *)[self cell] setImageAlignment:newAlignment];
	[self setNeedsDisplay:YES];
}

- (NSImageScaling)imageScaling
{
	return [(NSImageCell *)[self cell] imageScaling];
}

- (void)setImageScaling:(NSImageScaling)newScaling
{
	[(NSImageCell *)[self cell] setImageScaling:newScaling];
	[self setNeedsDisplay:YES];
}

- (NSImageFrameStyle)imageFrameStyle
{
	return [(NSImageCell *)[self cell] imageFrameStyle];
}

- (void)setImageFrameStyle:(NSImageFrameStyle)newStyle
{
	[(NSImageCell *)[self cell] setImageFrameStyle:newStyle];
	[self setNeedsDisplay:YES];
}

/* ---- THE TWO EDIT FLAGS AND THE ANIMATION FLAG ----------------------------------------------------- */

- (BOOL)isEditable
{
	return [[self cell] isEditable];
}

- (void)setEditable:(BOOL)flag
{
	[[self cell] setEditable:flag];
	[self setNeedsDisplay:YES];
}

- (BOOL)allowsCutCopyPaste
{
	return _allowsCutCopyPaste;
}

- (void)setAllowsCutCopyPaste:(BOOL)allow
{
	_allowsCutCopyPaste = allow ? YES : NO;
}

- (BOOL)animates
{
	return _animates;
}

- (void)setAnimates:(BOOL)flag
{
	/* **STORED AND ANSWERED, NOT RUN.** `NSImage` in this tier has no animation clock, so no timer is made and no
	 * representation is cycled; a caller's setting round-trips and nothing claims the image moved. */
	_animates = flag ? YES : NO;
}

/* ---- THE STANDARD IMAGE COMMANDS ------------------------------------------------------------------ */

/* **COPY AND CUT REFUSE BY NAME.** `NSImage -TIFFRepresentation` needs a `CGImageDestination`, which this tree's
 * CoreGraphics does not have; the refusal is the image class's own, so this door only reaches it when the flags and
 * the image make the attempt meaningful. */
/* THE WRITE HALF, WHICH IS THE ONE THE ENCODER DECIDES. `NSImage -TIFFRepresentation` refuses by name when this
 * tree cannot encode; a nil answer leaves the pasteboard untouched and the caller learns why from that refusal. */
- (BOOL)cg_writeImageToPasteboard
{
	NSData *data = [[self image] TIFFRepresentation];

	if (data == nil) {
		return NO;
	}
	{
		NSPasteboard *board = [NSPasteboard generalPasteboard];

		[board declareTypes:[NSArray arrayWithObject:NSTIFFPboardType] owner:nil];
		return [board setData:data forType:NSTIFFPboardType];
	}
}

- (void)copy:(id)sender
{
	(void)sender;
	if (!_allowsCutCopyPaste || [self image] == nil) {
		return;
	}
	(void)[self cg_writeImageToPasteboard];
}

- (void)cut:(id)sender
{
	(void)sender;
	if (!_allowsCutCopyPaste || ![self isEditable] || [self image] == nil) {
		return;
	}
	if ([self cg_writeImageToPasteboard]) {
		[self setImage:nil];
		[self sendAction:[self action] to:[self target]];
	}
}

/* **PASTE IS REAL: THE BOARD'S READER AND THE CELL'S IMAGE FIELD ARE BOTH HERE.** `NSImage -initWithPasteboard:`
 * asks the board for the first type it can decode, so a PNG or JPEG pasted by any application lands in the view. */
- (void)paste:(id)sender
{
	NSImage *pasted = nil;

	(void)sender;
	if (!_allowsCutCopyPaste || ![self isEditable]) {
		return;
	}
	pasted = [[NSImage alloc] initWithPasteboard:[NSPasteboard generalPasteboard]];
	if (pasted != nil) {
		[self setImage:pasted];
		[self sendAction:[self action] to:[self target]];
		[pasted release];
	}
}

- (void)delete:(id)sender
{
	(void)sender;
	if (!_allowsCutCopyPaste || ![self isEditable]) {
		return;
	}
	[self setImage:nil];
	[self sendAction:[self action] to:[self target]];
}

@end
