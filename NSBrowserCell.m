/*
 * NSBrowserCell.m — the picture and the title, and the leaf/loaded pair.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
#import <AppKit/NSBrowserCell.h>

#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSGraphicsContext.h>

#include <math.h>

@implementation NSBrowserCell

/* ============================================================================================
 * ARCHIVING: A BROWSER CELL IS A LEAF AND HAS LOADED OR NOT.
 * ============================================================================================ */
static NSString * const AGCoderBrowserLeafKey = @"leaf";
static NSString * const AGCoderBrowserLoadedKey = @"loaded";
static NSString * const AGCoderBrowserAlternateImageKey = @"alternateImage";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeBool:_leaf forKey:AGCoderBrowserLeafKey];
	[aCoder encodeBool:_loaded forKey:AGCoderBrowserLoadedKey];
	[aCoder encodeObject:_alternateImage forKey:AGCoderBrowserAlternateImageKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserLeafKey]) {
		_leaf = [aDecoder decodeBoolForKey:AGCoderBrowserLeafKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserLoadedKey]) {
		_loaded = [aDecoder decodeBoolForKey:AGCoderBrowserLoadedKey];
	}
	if ([aDecoder containsValueForKey:AGCoderBrowserAlternateImageKey]) {
		_alternateImage = [[aDecoder decodeObjectForKey:AGCoderBrowserAlternateImageKey] retain];
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (BOOL)isLeaf { return _leaf; }
- (void)setLeaf:(BOOL)flag { _leaf = flag ? YES : NO; }
- (BOOL)isLoaded { return _loaded; }
- (void)setLoaded:(BOOL)flag { _loaded = flag ? YES : NO; }

- (void)dealloc
{
	[_alternateImage release];
	[super dealloc];
}

- (void)reset
{
	_leaf = NO;
	_loaded = NO;
	[self setImage:nil];
	[self setStringValue:@""];
}

/* ---- THE PICTURE, THE BRANCH MARK AND THE HIGHLIGHT ------------------------------------------------ */

- (NSImage *)alternateImage
{
	return _alternateImage;
}

- (void)setAlternateImage:(NSImage *)anImage
{
	if (anImage != _alternateImage) {
		NSImage *held = [anImage retain];

		[_alternateImage release];
		_alternateImage = held;
	}
}

/* **THE MARK IS A TRIANGLE IN A TEN-POINT BOX, DRAWN ONCE PER PROCESS.** A branch's chevron points RIGHT because a
 * branch opens the column beside it; the highlighted one is the SAME PATH in white, because a selected row's chip is the
 * accent and a dark mark on it would be the illegal pairing the button family's ink door exists to prevent. The images
 * are built through `+imageWithSize:flipped:drawingHandler:` — this tier's one constructor for an image made of
 * arithmetic — and held in statics so a browser with a thousand rows does not build a thousand copies. NOT THREAD-SAFE
 * and does not need to be: a cell is drawn on the main thread. */
static NSImage *fn_branch_image(BOOL highlighted)
{
	static NSImage *sPlain = nil;
	static NSImage *sHighlighted = nil;
	NSImage **slot = highlighted ? &sHighlighted : &sPlain;

	if (*slot == nil) {
		*slot = [[NSImage imageWithSize:NSMakeSize(10.0, 10.0) flipped:NO
				       drawingHandler:^BOOL(NSRect dstRect) {
			NSBezierPath *mark = [NSBezierPath bezierPath];

			(void)dstRect;
			[(highlighted ? [NSColor whiteColor] : [NSColor controlTextColor]) setFill];
			[mark moveToPoint:NSMakePoint(3.0, 1.5)];
			[mark lineToPoint:NSMakePoint(7.0, 5.0)];
			[mark lineToPoint:NSMakePoint(3.0, 8.5)];
			[mark closePath];
			[mark fill];
			return YES;
		}] retain];
	}
	return *slot;
}

+ (NSImage *)branchImage
{
	return fn_branch_image(NO);
}

+ (NSImage *)highlightedBranchImage
{
	return fn_branch_image(YES);
}

/* **AND THE COLOUR A ROW IS HIGHLIGHTED WITH.** Apple's own is the selected-control colour, which this tier has; a cell
 * in a source list is a selected row, and the answer is the same colour the table's selection uses rather than a second
 * accent. */
- (NSColor *)highlightColorInView:(NSView *)controlView
{
	(void)controlView;
	return [NSColor selectedControlColor];
}

/* **`-set` IS TWO FACTS, AND BOTH OF THEM ARE THE CELL'S OWN.** See the header: the era declares the shorthand here
 * rather than on `NSCell`, and "selected" is the state a cell draws a chip for plus the highlight that makes it draw
 * one. */
- (void)set
{
	[self setState:NSOnState];
	[self setHighlighted:YES];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	/* **AND A SELECTED ROW SHOWS ITS ALTERNATE PICTURE**, which is the same swap `NSButtonCell` makes while it is held:
	 * a glyph drawn for the accent chip cannot be the glyph drawn for a white row. */
	NSImage *image = ([self isHighlighted] && _alternateImage != nil) ? _alternateImage : [self image];

	if (image != nil) {
		NSRect box = NSMakeRect(cellFrame.origin.x + 2.0,
					cellFrame.origin.y + floor((cellFrame.size.height - 16.0) / 2.0),
					16.0, 16.0);

		[image drawInRect:box];
		cellFrame.origin.x += 20.0;
		cellFrame.size.width -= 20.0;
	}
	/* **AND A BRANCH WEARS ITS CHEVRON AT THE TRAILING EDGE**, which is the one thing a browser's row draws that a text
	 * cell's does not: the mark that says a column opens to the right. A LEAF has none — that is what `-isLeaf:` is
	 * FOR — and the highlighted variant is chosen by the same predicate the alternate picture uses, so one state cannot
	 * come out in two vocabularies. */
	if (!_leaf && cellFrame.size.width > 14.0) {
		NSImage *mark = [self isHighlighted] ? [[self class] highlightedBranchImage] : [[self class] branchImage];

		[mark drawInRect:NSMakeRect(NSMaxX(cellFrame) - 12.0,
					    cellFrame.origin.y + floor((cellFrame.size.height - 10.0) / 2.0),
					    10.0, 10.0)];
		cellFrame.size.width -= 14.0;
	}
	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end
