/*
 * NSCIImageRep — declared and refused. See the header: there is no Core Image in this tier.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import "NSCIImageRep.h"
#import "AppKitRefusal.h"

@implementation NSCIImageRep

+ (BOOL)canInitWithData:(NSData *)data
{
	(void)data;
	return NO;	/* a rep that cannot be made never decodes anything */
}

+ (NSArray *)imageUnfilteredFileTypes
{
	return [NSArray array];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	return [NSArray array];
}

+ (instancetype)imageRepWithCIImage:(id)image
{
	(void)image;
	fn_refuse_window("+NSCIImageRep imageRepWithCIImage:", "Core Image, which this tree has not got");
	return nil;
}

- (instancetype)initWithCIImage:(id)image
{
	(void)image;
	fn_refuse_window("-NSCIImageRep -initWithCIImage:", "Core Image, which this tree has not got");
	[self release];
	return nil;
}

- (id)CIImage
{
	return nil;
}

@end
