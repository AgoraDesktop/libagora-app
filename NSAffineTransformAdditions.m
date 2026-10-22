/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAffineTransformAdditions.m — the three AppKit doors' IMPLEMENTATION (§63.187). Their DECLARATIONS are
 * Foundation's, on the class, as Apple's are; what they need (a graphics context, an NSBezierPath) is here.
 */
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <CoreGraphics/CGContext.h>
#import <Foundation/NSAffineTransform.h>

static CGAffineTransform fn_cg_affine(NSAffineTransform *transform)
{
	NSAffineTransformStruct s = [transform transformStruct];

	return CGAffineTransformMake(s.m11, s.m12, s.m21, s.m22, s.tX, s.tY);
}

static CGContextRef fn_current_cg_context(void)
{
	NSGraphicsContext *context = [NSGraphicsContext currentContext];

	return context != nil ? context.CGContext : NULL;
}

/* AND THE THREE WARNINGS THIS FILE USED TO PRODUCE ARE SILENCED HERE, WITH THEIR REASON: clang warns when
 * a category implements a method its primary class DECLARES, on the assumption that the class implements it
 * too. Foundation's NSAffineTransform declares these three and does NOT implement them — this file is the
 * implementation, and it is here because they need an NSGraphicsContext and an NSBezierPath, which is
 * AppKit's half. That is the tree's deliberate split, stated in this file's own header comment (§63.187);
 * the warning is the compiler's inference and not a fact. THE SCOPE IS THREE METHOD DECLARATIONS, not the
 * file. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation NSAffineTransform (NSAffineTransformAppKitAdditions)

- (void)set
{
	CGContextRef cg = fn_current_cg_context();

	if (cg == NULL) {
		return;
	}
	CGContextConcatCTM(cg, CGAffineTransformInvert(CGContextGetCTM(cg)));
	CGContextConcatCTM(cg, fn_cg_affine(self));
}

- (void)concat
{
	CGContextRef cg = fn_current_cg_context();

	if (cg == NULL) {
		return;
	}
	CGContextConcatCTM(cg, fn_cg_affine(self));
}

- (NSBezierPath *)transformBezierPath:(NSBezierPath *)path
{
	NSBezierPath *copy = [path copy];

	[copy transformUsingAffineTransform:self];
	return [copy autorelease];
}

@end

#pragma clang diagnostic pop
