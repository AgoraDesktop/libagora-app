/*
 * NSCustomImageRep — a rep whose pixels are a message.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * The delegate draws, and this class does three things: check at construction that it can, send the message on every
 * draw, and answer the two facts back. There is no format, no bytes and no `-CGImage` — which is why it overrides
 * `-drawInRect:` rather than supplying pixels to the base's blit.
 */
#import "NSCustomImageRep.h"
#import "AppKitRefusal.h"

#import <Foundation/NSMethodSignature.h>

@implementation NSCustomImageRep

- (instancetype)initWithDrawSelector:(SEL)selector delegate:(id)delegate
{
	NSMethodSignature *signature;

	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (selector == NULL || delegate == nil) {
		fn_refuse_window("-NSCustomImageRep -initWithDrawSelector:delegate:",
				 "a selector and a delegate; one of them is missing, and a rep that cannot draw is not one");
		[self release];
		return nil;
	}
	/* **THE SIGNATURE IS CHECKED HERE RATHER THAN AT THE FIRST PAINT**, because a rep that exists and raises when drawn is
	 * worse than a constructor that says no. Apple's selector takes (id, NSRect, BOOL) after the two implicit arguments. */
	signature = [delegate methodSignatureForSelector:selector];
	if (signature == nil || [signature numberOfArguments] != 5) {
		fn_refuse_window("-NSCustomImageRep -initWithDrawSelector:delegate:",
				 "a draw selector taking (id, NSRect, BOOL); this one's signature does not match");
		[self release];
		return nil;
	}
	_drawSelector = selector;
	_delegate = delegate;	/* NOT RETAINED */
	return self;
}

- (SEL)drawSelector
{
	return _drawSelector;
}

- (id)delegate
{
	return _delegate;
}

/* **THE DRAW IS THE MESSAGE, SENT THROUGH THE METHOD'S OWN IMP.** `-performSelector:` cannot carry an `NSRect` or a BOOL,
 * and this tier's `NSInvocation` refuses a 32-byte argument ("marshals register arguments only", which its own header
 * states), so the call is the C one a message compiles to: the delegate's `-methodForSelector:` gives the function to call,
 * and the signature checked at construction is what makes the cast safe. The three arguments are the era's — the rep, the
 * rectangle BY VALUE, and YES for a screen draw. */
- (BOOL)drawInRect:(NSRect)rect
{
	IMP implementation;
	BOOL forScreen = YES;

	if (_delegate == nil || _drawSelector == NULL) {
		return NO;
	}
	implementation = [_delegate methodForSelector:_drawSelector];
	if (implementation == NULL) {
		return NO;
	}
	((void (*)(id, SEL, id, NSRect, BOOL))implementation)(_delegate, _drawSelector, self, rect, forScreen);
	return YES;
}

@end
