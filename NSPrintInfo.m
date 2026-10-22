/*
 * NSPrintInfo — a print job's ticket.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **EVERY PROPERTY IS ONE DICTIONARY KEY, AND THE DEFAULTS ARE IN ONE PLACE.** `-setUpPrintOperationDefaultValues`
 * fills the ticket with this tier's starting values — A4 unless the default queue names a paper, one-inch margins, no
 * scaling, portrait, automatic pagination and both centres on — and every setter below writes its key over that. A
 * caller that builds the ticket by hand and a caller that sets ten properties therefore end up with the same object,
 * which is the property `-dictionary` exists to make true.
 *
 * **THE DISPOSITION DEFAULTS TO SPOOL AND THE OPERATION FALLS BACK.** A build with no print service still answers
 * `NSPrintSpoolJob`, because the disposition is the caller's INTENT rather than a fact about the machine; the operation
 * is where "there is no queue" turns into a save or a preview, and it says so there.
 *
 * **THE CARBON HANDLES ARE NULL AND THE REASON IS PRINTED.** There is no Print Manager on this system, so
 * `-PMPageFormat` and its two siblings answer NULL and their two `-updateFrom…` doors refuse by name — a handle to
 * something that does not exist would be worse than a documented absence.
 */
#import <AppKit/NSPrintInfo.h>

#import <AppKit/NSPrinter.h>
#import <AppKit/AppKitRefusal.h>

#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include "../platform/AGPrintService.h"

NSString *NSPrintPaperName = @"NSPrintPaperName";
NSString *NSPrintPaperSize = @"NSPrintPaperSize";
NSString *NSPrintOrientation = @"NSPrintOrientation";
NSString *NSPrintScalingFactor = @"NSPrintScalingFactor";
NSString *NSPrintHorizontalPagination = @"NSPrintHorizontalPagination";
NSString *NSPrintVerticalPagination = @"NSPrintVerticalPagination";
NSString *NSPrintHorizontallyCentered = @"NSPrintHorizontallyCentered";
NSString *NSPrintVerticallyCentered = @"NSPrintVerticallyCentered";
NSString *NSPrintTopMargin = @"NSPrintTopMargin";
NSString *NSPrintBottomMargin = @"NSPrintBottomMargin";
NSString *NSPrintLeftMargin = @"NSPrintLeftMargin";
NSString *NSPrintRightMargin = @"NSPrintRightMargin";
NSString *NSPrintJobDisposition = @"NSPrintJobDisposition";
NSString *NSPrintSavePath = @"NSPrintSavePath";
NSString *NSPrintJobSavingURL = @"NSPrintJobSavingURL";
NSString *NSPrintCopies = @"NSPrintCopies";
NSString *NSPrintSelectionOnly = @"NSPrintSelectionOnly";
NSString *NSPrintDetailedErrorReporting = @"NSPrintDetailedErrorReporting";

NSString *NSPrintSpoolJob = @"NSPrintSpoolJob";
NSString *NSPrintPreviewJob = @"NSPrintPreviewJob";
NSString *NSPrintSaveJob = @"NSPrintSaveJob";
NSString *NSPrintCancelJob = @"NSPrintCancelJob";

static NSPrintInfo *s_sharedPrintInfo = nil;
static NSPrinter *s_defaultPrinter = nil;

/* THE DEFAULT'S FOUR MARGINS: one inch, which is the era's starting value and the one every printed page in this tier's
 * own documentation assumes. */
#define AG_PRINT_DEFAULT_MARGIN 72.0

@implementation NSPrintInfo

/* ============================================================================================ *
 * THE SHARED TICKET AND THE DEFAULT PRINTER.                                                    *
 * ============================================================================================ */

+ (NSPrintInfo *)sharedPrintInfo
{
	if (s_sharedPrintInfo == nil) {
		s_sharedPrintInfo = [[NSPrintInfo alloc] init];
	}
	return s_sharedPrintInfo;
}

+ (void)setSharedPrintInfo:(NSPrintInfo *)printInfo
{
	NSPrintInfo *old = s_sharedPrintInfo;

	s_sharedPrintInfo = [printInfo retain];
	[old release];
}

+ (NSPrinter *)defaultPrinter
{
	if (s_defaultPrinter == nil) {
		int index = AGPrintServiceDefaultPrinterIndex();

		if (index >= 0) {
			const char *name = AGPrintServicePrinterName(index);

			if (name != NULL) {
				s_defaultPrinter = [[NSPrinter printerWithName:[NSString stringWithUTF8String:name]] retain];
			}
		}
	}
	return s_defaultPrinter;
}

+ (void)setDefaultPrinter:(NSPrinter *)printer
{
	NSPrinter *old = s_defaultPrinter;

	s_defaultPrinter = [printer retain];
	[old release];
}

/* ============================================================================================ *
 * LIFETIME AND DEFAULTS.                                                                        *
 * ============================================================================================ */

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_dictionary = [[NSMutableDictionary alloc] init];
		[self setUpPrintOperationDefaultValues];
	}
	return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)attributes
{
	self = [self init];
	if (self != nil && attributes != nil) {
		[_dictionary addEntriesFromDictionary:attributes];
		/* **THE SHORTCUT KEYS ARE HONOURED AS WELL AS THE LONG ONES.** A ticket may carry the size directly or only a
		 * paper NAME; when it carries a name the size is recomputed from it, so the two cannot disagree. */
		if ([attributes objectForKey:NSPrintPaperName] != nil
		    && [attributes objectForKey:NSPrintPaperSize] == nil) {
			[self setPaperName:[attributes objectForKey:NSPrintPaperName]];
		}
	}
	return self;
}

- (void)dealloc
{
	[_dictionary release];
	[_printer release];
	[super dealloc];
}

/* A TICKET COPIES AS A TICKET: the dictionary is copied and the queue is the same object (a printer is a value here). */
- (id)copy
{
	NSPrintInfo *copy = [[NSPrintInfo alloc] init];

	[copy->_dictionary setDictionary:_dictionary];
	[copy setPrinter:_printer];
	return copy;
}

- (void)setUpPrintOperationDefaultValues
{
	NSPrinter *printer = [[self class] defaultPrinter];
	NSString *paperName = @"A4";
	NSSize size;

	if (printer != nil) {
		NSArray *keywords = [printer cg_mediaKeywords];

		if ([keywords count] > 0) {
			NSString *friendly = [NSPrinter cg_paperNameForKeyword:[keywords objectAtIndex:0]];

			if ([NSPrinter cg_paperSizeForName:friendly].width > 0.0) {
				paperName = friendly;
			}
		}
	}
	size = [NSPrinter cg_paperSizeForName:paperName];
	[_dictionary setObject:paperName forKey:NSPrintPaperName];
	[_dictionary setObject:[NSValue valueWithSize:size] forKey:NSPrintPaperSize];
	[_dictionary setObject:[NSNumber numberWithInteger:NSPortraitOrientation] forKey:NSPrintOrientation];
	[_dictionary setObject:[NSNumber numberWithDouble:1.0] forKey:NSPrintScalingFactor];
	[_dictionary setObject:[NSNumber numberWithInteger:NSAutoPagination] forKey:NSPrintHorizontalPagination];
	[_dictionary setObject:[NSNumber numberWithInteger:NSAutoPagination] forKey:NSPrintVerticalPagination];
	[_dictionary setObject:[NSNumber numberWithBool:YES] forKey:NSPrintHorizontallyCentered];
	[_dictionary setObject:[NSNumber numberWithBool:YES] forKey:NSPrintVerticallyCentered];
	[_dictionary setObject:[NSNumber numberWithDouble:AG_PRINT_DEFAULT_MARGIN] forKey:NSPrintTopMargin];
	[_dictionary setObject:[NSNumber numberWithDouble:AG_PRINT_DEFAULT_MARGIN] forKey:NSPrintBottomMargin];
	[_dictionary setObject:[NSNumber numberWithDouble:AG_PRINT_DEFAULT_MARGIN] forKey:NSPrintLeftMargin];
	[_dictionary setObject:[NSNumber numberWithDouble:AG_PRINT_DEFAULT_MARGIN] forKey:NSPrintRightMargin];
	[_dictionary setObject:NSPrintSpoolJob forKey:NSPrintJobDisposition];
	[_dictionary setObject:[NSNumber numberWithInteger:1] forKey:NSPrintCopies];
	[_dictionary setObject:[NSNumber numberWithBool:NO] forKey:NSPrintSelectionOnly];
	if (printer != nil) {
		[self setPrinter:printer];
	}
}

- (NSMutableDictionary *)dictionary
{
	return _dictionary;
}

/* ============================================================================================ *
 * THE SHEET AND THE MARGINS.                                                                    *
 * ============================================================================================ */

- (NSSize)paperSize
{
	NSValue *value = [_dictionary objectForKey:NSPrintPaperSize];

	return (value != nil) ? [value sizeValue] : NSZeroSize;
}

- (void)setPaperSize:(NSSize)size
{
	[_dictionary setObject:[NSValue valueWithSize:size] forKey:NSPrintPaperSize];
	/* AND THE NAME IS DROPPED, because a size a caller set by hand need not be a paper with a name. */
	[_dictionary removeObjectForKey:NSPrintPaperName];
}

- (NSString *)paperName
{
	return [_dictionary objectForKey:NSPrintPaperName];
}

- (void)setPaperName:(NSString *)name
{
	NSSize size;

	if (name == nil) {
		return;
	}
	[_dictionary setObject:name forKey:NSPrintPaperName];
	size = [self sizeForPaperName:name];
	if (size.width > 0.0 && size.height > 0.0) {
		[_dictionary setObject:[NSValue valueWithSize:size] forKey:NSPrintPaperSize];
	}
}

- (NSString *)localizedPaperName
{
	NSString *name = [self paperName];

	return (name != nil) ? name : @"";
}

- (NSSize)sizeForPaperName:(NSString *)name
{
	NSSize fromPrinter = (_printer != nil) ? [_printer pageSizeForPaper:name] : NSZeroSize;

	if (fromPrinter.width > 0.0 && fromPrinter.height > 0.0) {
		return fromPrinter;
	}
	return [NSPrinter cg_paperSizeForName:name];
}

- (CGFloat)fn_marginForKey:(NSString *)key
{
	NSNumber *value = [_dictionary objectForKey:key];

	return (value != nil) ? (CGFloat)[value doubleValue] : 0.0;
}

- (void)fn_setMargin:(CGFloat)margin forKey:(NSString *)key
{
	[_dictionary setObject:[NSNumber numberWithDouble:(double)margin] forKey:key];
}

- (CGFloat)topMargin
{
	return [self fn_marginForKey:NSPrintTopMargin];
}

- (void)setTopMargin:(CGFloat)margin
{
	[self fn_setMargin:margin forKey:NSPrintTopMargin];
}

- (CGFloat)bottomMargin
{
	return [self fn_marginForKey:NSPrintBottomMargin];
}

- (void)setBottomMargin:(CGFloat)margin
{
	[self fn_setMargin:margin forKey:NSPrintBottomMargin];
}

- (CGFloat)leftMargin
{
	return [self fn_marginForKey:NSPrintLeftMargin];
}

- (void)setLeftMargin:(CGFloat)margin
{
	[self fn_setMargin:margin forKey:NSPrintLeftMargin];
}

- (CGFloat)rightMargin
{
	return [self fn_marginForKey:NSPrintRightMargin];
}

- (void)setRightMargin:(CGFloat)margin
{
	[self fn_setMargin:margin forKey:NSPrintRightMargin];
}

/* **THE PAGE'S SHAPE FIRST, THEN THE MARGINS TAKEN OFF IT.** A landscape ticket swaps the SHEET's axes and then
 * subtracts the same physical margins, which is what the era's panel does: the margins belong to the page edge, not to
 * the text's width. The rect's origin is the imageable area's lower-left in the page's own (y-up) coordinates. */
- (NSRect)imageablePageBounds
{
	NSSize sheet = [self paperSize];
	CGFloat width = sheet.width;
	CGFloat height = sheet.height;

	if ([self orientation] == NSLandscapeOrientation) {
		width = sheet.height;
		height = sheet.width;
	}
	width -= [self leftMargin] + [self rightMargin];
	height -= [self topMargin] + [self bottomMargin];
	if (width < 0.0) {
		width = 0.0;
	}
	if (height < 0.0) {
		height = 0.0;
	}
	return NSMakeRect([self leftMargin], [self bottomMargin], width, height);
}

/* ============================================================================================ *
 * THE PAGE AND THE JOB.                                                                         *
 * ============================================================================================ */

- (NSPrintingOrientation)orientation
{
	NSNumber *value = [_dictionary objectForKey:NSPrintOrientation];

	return (NSPrintingOrientation)((value != nil) ? [value integerValue] : NSPortraitOrientation);
}

- (void)setOrientation:(NSPrintingOrientation)orientation
{
	[_dictionary setObject:[NSNumber numberWithInteger:(NSInteger)orientation] forKey:NSPrintOrientation];
}

- (CGFloat)scalingFactor
{
	NSNumber *value = [_dictionary objectForKey:NSPrintScalingFactor];

	return (value != nil) ? (CGFloat)[value doubleValue] : 1.0;
}

- (void)setScalingFactor:(CGFloat)factor
{
	[_dictionary setObject:[NSNumber numberWithDouble:(double)factor] forKey:NSPrintScalingFactor];
}

- (NSPrintingPaginationMode)horizontalPagination
{
	NSNumber *value = [_dictionary objectForKey:NSPrintHorizontalPagination];

	return (NSPrintingPaginationMode)((value != nil) ? [value integerValue] : NSAutoPagination);
}

- (void)setHorizontalPagination:(NSPrintingPaginationMode)mode
{
	[_dictionary setObject:[NSNumber numberWithInteger:(NSInteger)mode] forKey:NSPrintHorizontalPagination];
}

- (NSPrintingPaginationMode)verticalPagination
{
	NSNumber *value = [_dictionary objectForKey:NSPrintVerticalPagination];

	return (NSPrintingPaginationMode)((value != nil) ? [value integerValue] : NSAutoPagination);
}

- (void)setVerticalPagination:(NSPrintingPaginationMode)mode
{
	[_dictionary setObject:[NSNumber numberWithInteger:(NSInteger)mode] forKey:NSPrintVerticalPagination];
}

- (BOOL)isHorizontallyCentered
{
	NSNumber *value = [_dictionary objectForKey:NSPrintHorizontallyCentered];

	return (value != nil) ? [value boolValue] : YES;
}

- (void)setHorizontallyCentered:(BOOL)flag
{
	[_dictionary setObject:[NSNumber numberWithBool:flag ? YES : NO] forKey:NSPrintHorizontallyCentered];
}

- (BOOL)isVerticallyCentered
{
	NSNumber *value = [_dictionary objectForKey:NSPrintVerticallyCentered];

	return (value != nil) ? [value boolValue] : YES;
}

- (void)setVerticallyCentered:(BOOL)flag
{
	[_dictionary setObject:[NSNumber numberWithBool:flag ? YES : NO] forKey:NSPrintVerticallyCentered];
}

- (NSString *)jobDisposition
{
	NSString *value = [_dictionary objectForKey:NSPrintJobDisposition];

	return (value != nil) ? value : NSPrintSpoolJob;
}

- (void)setJobDisposition:(NSString *)disposition
{
	if (disposition != nil) {
		[_dictionary setObject:disposition forKey:NSPrintJobDisposition];
	}
}

- (BOOL)isSelectionOnly
{
	NSNumber *value = [_dictionary objectForKey:NSPrintSelectionOnly];

	return (value != nil) ? [value boolValue] : NO;
}

- (void)setSelectionOnly:(BOOL)flag
{
	[_dictionary setObject:[NSNumber numberWithBool:flag ? YES : NO] forKey:NSPrintSelectionOnly];
}

- (NSPrinter *)printer
{
	return _printer;
}

- (void)setPrinter:(NSPrinter *)printer
{
	NSPrinter *old = _printer;

	_printer = [printer retain];
	[old release];
}

/* ============================================================================================ *
 * THE CARBON HANDLES: NULL, NAMED.                                                              *
 * ============================================================================================ */

- (void *)PMPrintSession
{
	fn_refuse_window("-PMPrintSession", "the Carbon Print Manager, which this system does not have; the ticket is "
			 "`-dictionary` and the job is a PDF");
	return NULL;
}

- (void *)PMPageFormat
{
	fn_refuse_window("-PMPageFormat", "the Carbon Print Manager, which this system does not have");
	return NULL;
}

- (void *)PMPrintSettings
{
	fn_refuse_window("-PMPrintSettings", "the Carbon Print Manager, which this system does not have");
	return NULL;
}

- (void)updateFromPMPageFormat
{
	fn_refuse_window("-updateFromPMPageFormat", "the Carbon Print Manager, which this system does not have");
}

- (void)updateFromPMPrintSettings
{
	fn_refuse_window("-updateFromPMPrintSettings", "the Carbon Print Manager, which this system does not have");
}

- (id)printSettings
{
	fn_refuse_window("-printSettings", "the Carbon Print Manager's settings object, which this system does not have");
	return nil;
}

/* ============================================================================================ *
 * ARCHIVING: THE TICKET AND THE QUEUE'S NAME.                                                    *
 * ============================================================================================ */

static NSString * const AGCoderPrintInfoDictionaryKey = @"NSPrintInfoDictionary";
static NSString * const AGCoderPrintInfoPrinterKey = @"NSPrintInfoPrinter";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:_dictionary forKey:AGCoderPrintInfoDictionaryKey];
	[aCoder encodeObject:[_printer name] forKey:AGCoderPrintInfoPrinterKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [self init];
	if (self != nil) {
		NSDictionary *ticket = [aDecoder decodeObjectForKey:AGCoderPrintInfoDictionaryKey];

		if (ticket != nil) {
			[_dictionary setDictionary:ticket];
		}
		{
			NSString *name = [aDecoder decodeObjectForKey:AGCoderPrintInfoPrinterKey];

			if (name != nil) {
				[self setPrinter:[NSPrinter printerWithName:name]];
			}
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

@end
