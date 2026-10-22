/*
 * NSPICTImageRep — declared and refused. See the header: PICT needs QuickDraw's player, which this tier has not got.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
#import "NSPICTImageRep.h"
#import "AppKitRefusal.h"

#import <AppKit/NSPasteboard.h>
#import <Foundation/NSData.h>

@implementation NSPICTImageRep

+ (BOOL)canInitWithData:(NSData *)data
{
	/* NO SNIFF, because a positive answer would promise a decode that cannot happen. */
	(void)data;
	return NO;
}

+ (NSArray *)imageUnfilteredFileTypes
{
	return [NSArray arrayWithObjects:@"pict", @"pct", @"pic", nil];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	return [NSArray arrayWithObjects:NSPICTPboardType, nil];
}

+ (instancetype)imageRepWithData:(NSData *)pictData
{
	(void)pictData;
	fn_refuse_window("+NSPICTImageRep imageRepWithData:",
			 "a PICT decoder — QuickDraw's picture player, which this tier has not got");
	return nil;
}

- (instancetype)initWithData:(NSData *)pictData
{
	(void)pictData;
	fn_refuse_window("-NSPICTImageRep -initWithData:",
			 "a PICT decoder — QuickDraw's picture player, which this tier has not got");
	[self release];
	return nil;
}

- (NSData *)PICTRepresentation
{
	return nil;
}

- (NSRect)boundingBox
{
	return NSZeroRect;
}

@end
