/*
 * NSBrowserCell.m — the picture and the title, and the leaf/loaded pair.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import <AppKit/NSBrowserCell.h>

#import <AppKit/NSImage.h>

#include <math.h>

@implementation NSBrowserCell

/* ============================================================================================
 * ARCHIVING: A BROWSER CELL IS A LEAF AND HAS LOADED OR NOT.
 * ============================================================================================ */
static NSString * const AGCoderBrowserLeafKey = @"leaf";
static NSString * const AGCoderBrowserLoadedKey = @"loaded";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	[aCoder encodeBool:_leaf forKey:AGCoderBrowserLeafKey];
	[aCoder encodeBool:_loaded forKey:AGCoderBrowserLoadedKey];
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

- (void)reset
{
	_leaf = NO;
	_loaded = NO;
	[self setImage:nil];
	[self setStringValue:@""];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	NSImage *image = [self image];

	if (image != nil) {
		NSRect box = NSMakeRect(cellFrame.origin.x + 2.0,
					cellFrame.origin.y + floor((cellFrame.size.height - 16.0) / 2.0),
					16.0, 16.0);

		[image drawInRect:box];
		cellFrame.origin.x += 20.0;
		cellFrame.size.width -= 20.0;
	}
	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

@end
