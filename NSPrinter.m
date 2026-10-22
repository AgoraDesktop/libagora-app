/*
 * NSPrinter — one print queue, as the application sees it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE PAPER TABLE IS THE ONE PIECE OF REAL DATA HERE, AND IT IS SMALL ON PURPOSE.** A queue names its media in IPP
 * keywords; a caller names paper in words. The table below is the intersection the era's panels offer, in points at
 * 72/inch, with each row carrying BOTH spellings so a keyword and a friendly name resolve to the same size. A paper
 * this table does not know answers NSZeroSize, which is the empty value `NSPrintInfo` and the panels test for.
 *
 * The rest of the class is a projection of the seam's facts: names, description, make-and-model, location, colour and
 * the queue's media keywords.
 */
#import <AppKit/NSPrinter.h>

#import <AppKit/NSFont.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include "../platform/AGPrintService.h"

#include <string.h>

/* ONE ROW PER PAPER: the IPP keyword, the friendly name, and the sheet in points. */
typedef struct AGPaperRow {
	const char *keyword;
	const char *name;
	double width;
	double height;
} AGPaperRow;

static const AGPaperRow s_papers[] = {
	{ "na_letter_8.5x11in", "Letter", 612.0, 792.0 },
	{ "na_legal_8.5x14in", "Legal", 612.0, 1008.0 },
	{ "na_ledger_11x17in", "Ledger", 792.0, 1224.0 },
	{ "na_index-4x6_4x6in", "4x6", 288.0, 432.0 },
	{ "na_index-3x5_3x5in", "3x5", 216.0, 360.0 },
	{ "na_number-10_4.125x9.5in", "Envelope #10", 297.0, 684.0 },
	{ "iso_a3_297x420mm", "A3", 842.0, 1191.0 },
	{ "iso_a4_210x297mm", "A4", 595.0, 842.0 },
	{ "iso_a5_148x210mm", "A5", 420.0, 595.0 },
	{ "iso_a6_105x148mm", "A6", 298.0, 420.0 },
	{ "jis_b5_182x257mm", "B5", 516.0, 729.0 },
};
static const size_t s_paperCount = sizeof s_papers / sizeof s_papers[0];

/* **COMPARISON FOLDS THE THREE SPELLINGS A CALLER MAY USE**: the keyword (`na_letter_8.5x11in`), the friendly name
 * (`Letter`), and the name with the keyword's separators turned into spaces. Case is folded, and so are '_' and '-',
 * because "na-letter" and "na_letter" are the same paper in two notations. */
static int fn_same_paper(const char *a, const char *b)
{
	if (a == NULL || b == NULL) {
		return 0;
	}
	while (*a != '\0' && *b != '\0') {
		unsigned char ca = (unsigned char)*a;
		unsigned char cb = (unsigned char)*b;

		if (ca == '_' || ca == '-' || ca == ' ') {
			while (*a == '_' || *a == '-' || *a == ' ') {
				a++;
			}
			continue;
		}
		if (cb == '_' || cb == '-' || cb == ' ') {
			while (*b == '_' || *b == '-' || *b == ' ') {
				b++;
			}
			continue;
		}
		if (ca >= 'A' && ca <= 'Z') {
			ca = (unsigned char)(ca - 'A' + 'a');
		}
		if (cb >= 'A' && cb <= 'Z') {
			cb = (unsigned char)(cb - 'A' + 'a');
		}
		if (ca != cb) {
			return 0;
		}
		a++;
		b++;
	}
	return *a == '\0' && *b == '\0';
}

static const AGPaperRow *fn_paper_for_name(const char *name)
{
	size_t i;

	if (name == NULL) {
		return NULL;
	}
	for (i = 0; i < s_paperCount; i++) {
		if (fn_same_paper(name, s_papers[i].keyword) || fn_same_paper(name, s_papers[i].name)) {
			return &s_papers[i];
		}
	}
	/* AND ONE ALIAS THE ERA USES FOR THE SAME SHEET, which is a different WORD rather than a different paper. */
	if (fn_same_paper(name, "Tabloid")) {
		return &s_papers[2];
	}
	if (fn_same_paper(name, "US Letter")) {
		return &s_papers[0];
	}
	if (fn_same_paper(name, "Envelope #10")) {
		return &s_papers[5];
	}
	return NULL;
}

@interface NSPrinter ()
- (instancetype)fn_initWithName:(NSString *)name;
- (int)fn_index;
@end

@implementation NSPrinter

+ (NSSize)cg_paperSizeForName:(NSString *)name
{
	const AGPaperRow *row = (name != nil) ? fn_paper_for_name([name UTF8String]) : NULL;

	return (row != NULL) ? NSMakeSize((CGFloat)row->width, (CGFloat)row->height) : NSZeroSize;
}

+ (NSString *)cg_paperNameForKeyword:(NSString *)keyword
{
	const AGPaperRow *row = (keyword != nil) ? fn_paper_for_name([keyword UTF8String]) : NULL;

	if (row != NULL) {
		return [NSString stringWithUTF8String:row->name];
	}
	return keyword;
}

+ (NSArray *)cg_standardPaperNames
{
	NSMutableArray *names = [NSMutableArray array];
	size_t i;

	for (i = 0; i < s_paperCount; i++) {
		[names addObject:[NSString stringWithUTF8String:s_papers[i].name]];
	}
	return names;
}

/* ============================================================================================ *
 * THE QUEUES.                                                                                   *
 * ============================================================================================ */

+ (NSArray *)printerNames
{
	NSMutableArray *names = [NSMutableArray array];
	int i, count = AGPrintServicePrinterCount();

	for (i = 0; i < count; i++) {
		const char *name = AGPrintServicePrinterName(i);

		if (name != NULL) {
			[names addObject:[NSString stringWithUTF8String:name]];
		}
	}
	return names;
}

+ (NSPrinter *)printerWithName:(NSString *)name
{
	NSArray *names;
	NSUInteger i;

	if (name == nil) {
		return nil;
	}
	names = [self printerNames];
	for (i = 0; i < [names count]; i++) {
		if ([[names objectAtIndex:i] isEqual:name]) {
			return [[[self alloc] fn_initWithName:name] autorelease];
		}
	}
	return nil;
}

+ (NSPrinter *)printerWithName:(NSString *)name domain:(NSString *)domain includeUnavailable:(BOOL)flag
{
	(void)domain;
	(void)flag;
	/* **THE DOMAIN IS TAKEN AND UNUSED, AND THE HEADER SAYS WHY**: every queue this tier can see is local, so a
	 * caller asking for a domain gets the local answer for an empty one and nil for a name that is not there. */
	return [self printerWithName:name];
}

+ (NSPrinter *)printerWithType:(NSString *)type
{
	NSArray *names = [self printerNames];
	NSUInteger i;

	if (type == nil) {
		return nil;
	}
	for (i = 0; i < [names count]; i++) {
		NSPrinter *printer = [self printerWithName:[names objectAtIndex:i]];

		if (printer != nil && [[printer type] isEqual:type]) {
			return printer;
		}
	}
	return nil;
}

/* THE ONE INITIALISER, PRIVATE BECAUSE APPLE'S `NSPrinter` HAS NO PUBLIC ONE: a printer is made BY NAME through
 * `+printerWithName:`, and a caller that already has the object asks it for its facts. */
- (instancetype)fn_initWithName:(NSString *)name
{
	self = [super init];
	if (self != nil) {
		_name = [name copy];
	}
	return self;
}

- (void)dealloc
{
	[_name release];
	[_deviceDescription release];
	[super dealloc];
}

/* A PRINTER IS A VALUE, so its copy is itself with one more owner — which is what `-copy` answering `-retain` means. */
- (id)copy
{
	return [self retain];
}

/* ============================================================================================ *
 * THE FACTS.                                                                                    *
 * ============================================================================================ */

/* THE SEAM INDEX FOR THIS QUEUE, looked up by name each time so a printer object made before a queue list refresh
 * still answers about a queue that exists. -1 when the queue has gone. */
- (int)fn_index
{
	int i, count = AGPrintServicePrinterCount();
	const char *wanted = (_name != nil) ? [_name UTF8String] : NULL;

	if (wanted == NULL) {
		return -1;
	}
	for (i = 0; i < count; i++) {
		const char *name = AGPrintServicePrinterName(i);

		if (name != NULL && strcmp(name, wanted) == 0) {
			return i;
		}
	}
	return -1;
}

- (NSString *)name
{
	return _name;
}

- (NSString *)type
{
	int index = [self fn_index];
	const char *make = (index >= 0) ? AGPrintServicePrinterMake(index) : NULL;

	if (make != NULL && make[0] != '\0') {
		return [NSString stringWithUTF8String:make];
	}
	return (_name != nil) ? _name : @"";
}

- (NSInteger)languageLevel
{
	/* A PDF/PostScript queue is level 3; an IPP Everywhere queue is not described in these terms at all, and 3 is the
	 * era's last value rather than a claim about the device. */
	return 3;
}

- (NSArray *)printerTypes
{
	NSString *type = [self type];

	return ([type length] > 0) ? [NSArray arrayWithObject:type] : [NSArray array];
}

- (NSDictionary *)deviceDescription
{
	int index;
	NSMutableDictionary *description;

	if (_deviceDescription != nil) {
		return _deviceDescription;
	}
	description = [NSMutableDictionary dictionary];
	index = [self fn_index];
	if (index >= 0) {
		const char *info = AGPrintServicePrinterInfo(index);
		const char *make = AGPrintServicePrinterMake(index);
		const char *where = AGPrintServicePrinterLocation(index);

		if (info != NULL) {
			[description setObject:[NSString stringWithUTF8String:info] forKey:@"printer-info"];
		}
		if (make != NULL) {
			[description setObject:[NSString stringWithUTF8String:make] forKey:@"printer-make-and-model"];
		}
		if (where != NULL) {
			[description setObject:[NSString stringWithUTF8String:where] forKey:@"printer-location"];
		}
		[description setObject:[NSNumber numberWithBool:AGPrintServicePrinterIsDefault(index) != 0]
				forKey:@"printer-is-default"];
		[description setObject:[NSNumber numberWithBool:AGPrintServicePrinterIsColor(index) != 0]
				forKey:@"color-supported"];
	}
	_deviceDescription = [description copy];
	return _deviceDescription;
}

- (NSString *)domain
{
	return @"";
}

- (NSString *)host
{
	return @"";
}

- (NSString *)note
{
	int index = [self fn_index];
	const char *info = (index >= 0) ? AGPrintServicePrinterInfo(index) : NULL;

	return (info != NULL) ? [NSString stringWithUTF8String:info] : @"";
}

- (BOOL)isColor
{
	int index = [self fn_index];

	return index >= 0 && AGPrintServicePrinterIsColor(index) != 0;
}

- (BOOL)acceptsBinary
{
	return NO;
}

- (BOOL)isOutputStackInReverseOrder
{
	return NO;
}

- (NSArray *)cg_mediaKeywords
{
	int index = [self fn_index];
	const char *keywords = (index >= 0) ? AGPrintServicePrinterMediaKeywords(index) : NULL;
	NSMutableArray *list = [NSMutableArray array];

	if (keywords == NULL || keywords[0] == '\0') {
		return list;
	}
	{
		NSString *text = [NSString stringWithUTF8String:keywords];
		NSArray *parts = [text componentsSeparatedByString:@" "];
		NSUInteger i;

		for (i = 0; i < [parts count]; i++) {
			NSString *part = [parts objectAtIndex:i];

			if ([part length] > 0) {
				[list addObject:part];
			}
		}
	}
	return list;
}

/* ============================================================================================ *
 * THE PAPER.                                                                                    *
 * ============================================================================================ */

- (NSSize)pageSizeForPaper:(NSString *)paperName
{
	return [NSPrinter cg_paperSizeForName:paperName];
}

- (NSRect)imageRectForPaper:(NSString *)paperName
{
	NSSize size = [self pageSizeForPaper:paperName];

	return NSMakeRect(0.0, 0.0, size.width, size.height);
}

/* ============================================================================================ *
 * THE FLAT TABLE.                                                                               *
 * ============================================================================================ */

- (NSDictionary *)statusForTable:(NSString *)tableName
{
	(void)tableName;
	return [NSDictionary dictionary];
}

- (BOOL)booleanForKey:(NSString *)key inTable:(NSString *)tableName
{
	id value = [[self deviceDescription] objectForKey:key];

	(void)tableName;
	return (value != nil) ? [value boolValue] : NO;
}

- (float)floatForKey:(NSString *)key inTable:(NSString *)tableName
{
	id value = [[self deviceDescription] objectForKey:key];

	(void)tableName;
	return (value != nil) ? (float)[value doubleValue] : 0.0f;
}

- (int)intForKey:(NSString *)key inTable:(NSString *)tableName
{
	id value = [[self deviceDescription] objectForKey:key];

	(void)tableName;
	return (value != nil) ? (int)[value integerValue] : 0;
}

- (NSRect)rectForKey:(NSString *)key inTable:(NSString *)tableName
{
	id value = [[self deviceDescription] objectForKey:key];

	(void)tableName;
	return [value isKindOfClass:[NSValue class]] ? [value rectValue] : NSZeroRect;
}

- (NSSize)sizeForKey:(NSString *)key inTable:(NSString *)tableName
{
	id value = [[self deviceDescription] objectForKey:key];

	(void)tableName;
	return [value isKindOfClass:[NSValue class]] ? [value sizeValue] : NSZeroSize;
}

- (NSString *)stringForKey:(NSString *)key inTable:(NSString *)tableName
{
	id value = [[self deviceDescription] objectForKey:key];

	(void)tableName;
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSArray *)stringListForKey:(NSString *)key inTable:(NSString *)tableName
{
	id value = [[self deviceDescription] objectForKey:key];

	(void)tableName;
	if ([value isKindOfClass:[NSArray class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSString class]]) {
		return [(NSString *)value componentsSeparatedByString:@" "];
	}
	return nil;
}

- (BOOL)isKey:(NSString *)key inTable:(NSString *)tableName
{
	(void)tableName;
	return key != nil && [[self deviceDescription] objectForKey:key] != nil;
}

- (BOOL)isFontAvailable:(NSString *)faceName
{
	return faceName != nil && [NSFont fontWithName:faceName size:12.0] != nil;
}

@end
