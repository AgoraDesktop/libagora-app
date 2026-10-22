/*
 * NSShadow — an offset, a blur and a colour, and the door that puts it on the context.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * Three numbers and a colour; `-set` is what makes them a state. The engine does the rest, which is why this file is
 * accessors and one call.
 */
#import "NSShadow.h"
#import "NSColor.h"
#import "NSGraphicsContext.h"
#import "AppKitRefusal.h"

#import <CoreGraphics/CGContext.h>
#import <CoreGraphics/CGColor.h>

@implementation NSShadow

/* **THE DEFAULTS ARE DOCUMENTED ONES RATHER THAN ZEROS.** A shadow with no offset and no blur is invisible, and one that
 * defaults to that would make `[[NSShadow alloc] init]` plus `-set` a no-op that looks like a broken engine. Apple's own
 * defaults are the offset (0, -3) and the blur 3.0. */
- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_shadowOffset = NSMakeSize(0.0, -3.0);
		_shadowBlurRadius = 3.0;
		_shadowColor = nil;
	}
	return self;
}

- (void)dealloc
{
	[_shadowColor release];
	[super dealloc];
}

/* A SHADOW IS A VALUE, so its copy is a second object with the same three facts and a retained colour. */
- (id)copy
{
	NSShadow *copy = [[NSShadow alloc] init];

	copy->_shadowOffset = _shadowOffset;
	copy->_shadowBlurRadius = _shadowBlurRadius;
	copy->_shadowColor = [_shadowColor retain];
	return copy;
}

- (NSSize)shadowOffset
{
	return _shadowOffset;
}

- (void)setShadowOffset:(NSSize)shadowOffset
{
	_shadowOffset = shadowOffset;
}

- (CGFloat)shadowBlurRadius
{
	return _shadowBlurRadius;
}

- (void)setShadowBlurRadius:(CGFloat)shadowBlurRadius
{
	_shadowBlurRadius = shadowBlurRadius;
}

- (NSColor *)shadowColor
{
	return _shadowColor;
}

- (void)setShadowColor:(NSColor *)shadowColor
{
	NSColor *held = [shadowColor copy];

	[_shadowColor release];
	_shadowColor = held;
}

/* **THE STATE DOOR.** The engine's offset is y-UP while an AppKit shadow's offset is in the era's own drawing coordinates,
 * so the y is NEGATED: a shadow of (0, -3) in AppKit falls BELOW the ink, and `CGContextSetShadow`'s positive y is up. A
 * nil colour uses the engine's default shadow (black at one third alpha), which is what Apple's nil means. */
- (void)set
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGContextRef cg = (context != nil) ? (CGContextRef)[context CGContext] : NULL;

	if (cg == NULL) {
		fn_refuse_window("-NSShadow -set",
				 "a current graphics context; a shadow is a state on the context, and there is none to set it on");
		return;
	}
	if (_shadowColor != nil) {
		CGContextSetShadowWithColor(cg, CGSizeMake(_shadowOffset.width, -_shadowOffset.height),
					    _shadowBlurRadius, [_shadowColor CGColor]);
	} else {
		CGContextSetShadow(cg, CGSizeMake(_shadowOffset.width, -_shadowOffset.height), _shadowBlurRadius);
	}
}

@end
