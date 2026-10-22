/*
 * NSEPSImageRep — the bytes, the bounding box from the header, and a stated refusal to render.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * The parser is two scans: `%!PS` near the start for the sniff, and the `%%BoundingBox:` comment for the size. Nothing here
 * interprets PostScript, and `-drawInRect:` says so.
 */
#import "NSEPSImageRep.h"
#import "AppKitRefusal.h"

#import <AppKit/NSPasteboard.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* **THE BOUNDING BOX, READ FROM THE HEADER'S OWN COMMENT.** EPS requires it within the first few kilobytes, and the form is
 * `%%BoundingBox: llx lly urx ury`; a file may also carry `%%HiResBoundingBox:` with reals. This reads the plain one (the
 * integer form every EPS producer writes, including this tier's own writer) and answers NSZeroRect when it is absent,
 * because a guessed box would place a drawing nobody measured. */
static NSRect fn_parse_bounding_box(const char *bytes, size_t length)
{
	const char *cursor = bytes;
	const char *end = bytes + length;
	const char *marker = "%%BoundingBox:";
	size_t markerLength = strlen(marker);
	NSRect box = NSZeroRect;

	while (cursor != NULL && cursor < end) {
		const char *line = memchr(cursor, '%', (size_t)(end - cursor));

		if (line == NULL) {
			break;
		}
		if ((size_t)(end - line) > markerLength && memcmp(line, marker, markerLength) == 0) {
			int llx = 0, lly = 0, urx = 0, ury = 0;

			if (sscanf(line + markerLength, "%d %d %d %d", &llx, &lly, &urx, &ury) == 4) {
				box = NSMakeRect((CGFloat)llx, (CGFloat)lly, (CGFloat)(urx - llx), (CGFloat)(ury - lly));
				if (box.size.width < 0.0) {
					box.size.width = 0.0;
				}
				if (box.size.height < 0.0) {
					box.size.height = 0.0;
				}
				return box;
			}
			return NSZeroRect;	/* a malformed box is no box */
		}
		cursor = line + 1;
	}
	return box;
}

@implementation NSEPSImageRep

/* **THE REGISTRATION IS THE CLASS'S OWN, which is Apple's contract for a rep that can sniff bytes.** NSImage's file and
 * pasteboard loading dispatch through the registry, so without this line an `.eps` file would answer nil from
 * `+imageRepClassForData:` no matter how good the sniff is. */
+ (void)initialize
{
	if (self == [NSEPSImageRep class]) {
		[NSImageRep registerImageRepClass:self];
	}
}

/* **THE SNIFF IS `%!PS` NEAR THE START.** An EPS begins with `%!PS-Adobe-…`; a plain PostScript file does too, and this
 * class takes both (Apple's does), so the test is the magic rather than the `EPSF` version comment. */
+ (BOOL)canInitWithData:(NSData *)data
{
	const char *bytes = (data != nil) ? (const char *)[data bytes] : NULL;

	if (bytes == NULL || [data length] < 4) {
		return NO;
	}
	return (bytes[0] == '%' && bytes[1] == '!' && bytes[2] == 'P' && bytes[3] == 'S') ? YES : NO;
}

+ (NSArray *)imageUnfilteredFileTypes
{
	return [NSArray arrayWithObjects:@"eps", @"ps", nil];
}

+ (NSArray *)imageUnfilteredPasteboardTypes
{
	/* THE ERA'S NAMES, which are the strings the pasteboard carries — `NSPostScriptPboardType` is one of them and is
	 * declared in `NSPasteboard.h`. */
	return [NSArray arrayWithObjects:NSPostScriptPboardType, @"EPS", nil];
}

+ (instancetype)imageRepWithData:(NSData *)epsData
{
	return [[[self alloc] initWithData:epsData] autorelease];
}

- (instancetype)initWithData:(NSData *)epsData
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (![[self class] canInitWithData:epsData]) {
		fn_refuse_window("-NSEPSImageRep -initWithData:",
				 "PostScript bytes (a `%!PS` header); these are some other format");
		[self release];
		return nil;
	}
	_data = [epsData copy];
	_boundingBox = fn_parse_bounding_box((const char *)[_data bytes], (size_t)[_data length]);
	[self setSize:_boundingBox.size];
	[self setPixelsWide:(NSInteger)_boundingBox.size.width];
	[self setPixelsHigh:(NSInteger)_boundingBox.size.height];
	[self setColorSpaceName:NSDeviceRGBColorSpace];
	return self;
}

- (void)dealloc
{
	[_data release];
	[super dealloc];
}

- (NSData *)EPSRepresentation
{
	return _data;
}

- (NSRect)boundingBox
{
	return _boundingBox;
}

- (void)prepareGState
{
	/* NOTHING TO PREPARE. See the header: the door belongs to the Display PostScript era, and there is no such state. */
}

/* **THE ONE THING THIS CLASS CANNOT DO, SAID AT THE DOOR.** Rendering PostScript needs an interpreter and Apple's converter
 * is not here; answering NO is a refusal a caller can see, where a silent success would paint nothing and read as a
 * corrupt file. */
- (BOOL)drawInRect:(NSRect)rect
{
	(void)rect;
	fn_refuse_window("-NSEPSImageRep -drawInRect:",
			 "a PostScript interpreter (Apple's route is CGPSConverter), which this tier has not got; the rep "
			 "answers the bytes and the bounding box, and rendering the file is the caller's");
	return NO;
}

- (BOOL)draw
{
	return [self drawInRect:NSMakeRect(0.0, 0.0, [self size].width, [self size].height)];
}

@end
