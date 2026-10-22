/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSPrinter.h — ONE PRINT QUEUE, AS THE APPLICATION SEES IT.
 *
 * **THIS CLASS IS A FACE OVER `platform/AGPrintService.h`.** The seam knows the queues and answers their facts as C
 * strings; this class gives those facts Apple's names — `-name`, `-type`, `-deviceDescription`, `-pageSizeForPaper:` —
 * and is what `NSPrintInfo -printer` and `NSPrintPanel`'s popup carry. A machine with no queue (or a build with no
 * print service) simply has no `NSPrinter` objects, which is a state every door here answers rather than a failure.
 *
 * **THE PAPER TABLE LIVES HERE, ONCE.** A queue reports its media as IPP KEYWORDS (`na_letter_8.5x11in`,
 * `iso_a4_210x297mm`), and a keyword is not a size: this class maps the keywords it knows to points, and answers the
 * same sizes for the friendly names a caller is more likely to write ("A4", "Letter"). `NSPrintInfo
 * -sizeForPaperName:` asks this class, so a page size cannot mean one thing to the panel and another to the ticket.
 *
 * **THE PER-TABLE KEY DOORS ARE ANSWERED FROM ONE TABLE, AND THE TABLE NAME IS IGNORED.** Apple's model is a PPD's
 * several tables ("General", "PageSize", …); this tier's seam reports one flat set of queue facts, so the name is taken
 * and unused rather than pretending to select a table that does not exist. The facts are the device description's keys:
 * `printer-info`, `printer-make-and-model`, `printer-location`, `printer-is-default`, `color-supported`.
 *
 * Written from `NSPrinter.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSPRINTER_H
#define APPKIT_NSPRINTER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSArray;
@class NSDictionary;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

@interface NSPrinter : NSObject <NSCopying, NSSecureCoding>
{
	NSString *_name;		/* RETAINED */
	NSDictionary *_deviceDescription;	/* RETAINED, built from the seam on first ask */
}

/* THE QUEUES. `+printerNames` is the seam's list; a name that is not in it answers nil. The `domain:` form is
 * answered for a nil or empty domain and nil otherwise, because this tier's queues are all local. */
+ (NSArray *)printerNames;
+ (nullable NSPrinter *)printerWithName:(NSString *)name;
+ (nullable NSPrinter *)printerWithName:(NSString *)name domain:(nullable NSString *)domain
		       includeUnavailable:(BOOL)flag;
+ (nullable NSPrinter *)printerWithType:(NSString *)type;

/* THE FACTS. `-type` is the make-and-model, which is Apple's reading; a queue that reports none answers its name. */
- (NSString *)name;
- (NSString *)type;
- (NSInteger)languageLevel;
- (NSArray *)printerTypes;
- (NSDictionary *)deviceDescription;
- (NSString *)domain;
- (NSString *)host;
- (NSString *)note;
- (BOOL)isColor;
- (BOOL)acceptsBinary;
- (BOOL)isOutputStackInReverseOrder;

/* THE PAPER. `-pageSizeForPaper:` answers NSZeroSize for a name this tier does not know, which is the empty value a
 * caller can test rather than a guess. `-imageRectForPaper:` is the whole sheet: the margins are `NSPrintInfo`'s. */
- (NSSize)pageSizeForPaper:(NSString *)paperName;
- (NSRect)imageRectForPaper:(NSString *)paperName;

/* THE FLAT TABLE, with the table name taken and unused. */
- (NSDictionary *)statusForTable:(NSString *)tableName;
- (BOOL)booleanForKey:(NSString *)key inTable:(NSString *)tableName;
- (float)floatForKey:(NSString *)key inTable:(NSString *)tableName;
- (int)intForKey:(NSString *)key inTable:(NSString *)tableName;
- (NSRect)rectForKey:(NSString *)key inTable:(NSString *)tableName;
- (NSSize)sizeForKey:(NSString *)key inTable:(NSString *)tableName;
- (nullable NSString *)stringForKey:(NSString *)key inTable:(NSString *)tableName;
- (nullable NSArray *)stringListForKey:(NSString *)key inTable:(NSString *)tableName;
- (BOOL)isKey:(NSString *)key inTable:(NSString *)tableName;
- (BOOL)isFontAvailable:(NSString *)faceName;

/* ============================================================================================ *
 * THE PAPER TABLE, WHICH IS THE INSTRUMENT'S AS WELL AS THE CLASS'S: `NSPrintInfo` asks these   *
 * so a size means one thing everywhere, and a probe can ask them without a queue.               *
 * ============================================================================================ */
+ (NSSize)cg_paperSizeForName:(nullable NSString *)name;
+ (nullable NSString *)cg_paperNameForKeyword:(nullable NSString *)keyword;
+ (NSArray *)cg_standardPaperNames;
- (NSArray *)cg_mediaKeywords;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPRINTER_H */
