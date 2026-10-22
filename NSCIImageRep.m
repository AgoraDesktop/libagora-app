/*
 * NSCIImageRep — declared and refused. See the header: there is no Core Image in this tier.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
