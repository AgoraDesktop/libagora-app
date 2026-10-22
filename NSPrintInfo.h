/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSPrintInfo.h — A PRINT JOB'S TICKET: THE PAPER, THE MARGINS, AND WHERE THE JOB GOES.
 *
 * **THIS CLASS IS A DICTIONARY WITH DOORS, AND THAT IS APPLE'S DESIGN RATHER THAN THIS TIER'S SHORTCUT.** Every property
 * below reads and writes one key of `-dictionary`, whose keys are the `NSPrint…` constants declared here — so a caller
 * that builds a ticket from a dictionary, or hands one to `-initWithDictionary:`, gets the same object a caller that
 * sets ten properties would have. The one fact that is NOT in the dictionary is the `NSPrinter`, because a printer is
 * an object rather than a value.
 *
 * **THE DISPOSITION DECIDES WHAT A JOB IS.** `NSPrintSpoolJob` sends the rendered PDF to a queue, `NSPrintSaveJob`
 * writes it to `NSPrintSavePath` (or `NSPrintJobSavingURL`), and `NSPrintPreviewJob` keeps the bytes for the caller to
 * look at. A build with no print service can still do the last two, which is why the disposition is a property of the
 * TICKET rather than of the operation.
 *
 * **THE PAPER'S SIZE AND THE IMAGEABLE RECT ARE TWO ANSWERS.** `-paperSize` is the sheet; `-imageablePageBounds` is
 * what a page can be drawn on — the sheet minus the four margins, with the AXES SWAPPED when the orientation is
 * landscape. Everything a paginating view is told comes from the second.
 *
 * WHAT REFUSES: the three Print Manager handles (`-PMPrintSession`, `-PMPageFormat`, `-PMPrintSettings`) and their two
 * `-updateFrom…` doors, because there is no Carbon Print Manager on this system and a NULL handle is the honest answer
 * rather than a stand-in.
 *
 * Written from `NSPrintInfo.h` in the MacOSX10.6 SDK. The constant names and the two enums are the header's own.
 */
#ifndef APPKIT_NSPRINTINFO_H
#define APPKIT_NSPRINTINFO_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSMutableDictionary;
@class NSPrinter;
@class NSString;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

/* THE TWO ENUMS THE TICKET CARRIES. */
typedef enum {
	NSPortraitOrientation = 0,
	NSLandscapeOrientation = 1
} NSPrintingOrientation;

typedef enum {
	NSFitPagination = 0,
	NSAutoPagination = 1,
	NSClipPagination = 2
} NSPrintingPaginationMode;

/* THE KEYS. A ticket is these names and their values, and a caller may build one by hand. */
extern NSString *NSPrintPaperName;
extern NSString *NSPrintPaperSize;
extern NSString *NSPrintOrientation;
extern NSString *NSPrintScalingFactor;
extern NSString *NSPrintHorizontalPagination;
extern NSString *NSPrintVerticalPagination;
extern NSString *NSPrintHorizontallyCentered;
extern NSString *NSPrintVerticallyCentered;
extern NSString *NSPrintTopMargin;
extern NSString *NSPrintBottomMargin;
extern NSString *NSPrintLeftMargin;
extern NSString *NSPrintRightMargin;
extern NSString *NSPrintJobDisposition;
extern NSString *NSPrintSavePath;
extern NSString *NSPrintJobSavingURL;
extern NSString *NSPrintCopies;
extern NSString *NSPrintSelectionOnly;
extern NSString *NSPrintDetailedErrorReporting;

/* AND THE FOUR DISPOSITIONS. `NSPrintCancelJob` is what a print panel's Cancel leaves on the ticket. */
extern NSString *NSPrintSpoolJob;
extern NSString *NSPrintPreviewJob;
extern NSString *NSPrintSaveJob;
extern NSString *NSPrintCancelJob;

@interface NSPrintInfo : NSObject <NSCopying, NSSecureCoding>
{
	NSMutableDictionary *_dictionary;	/* RETAINED: the ticket, keyed by the constants above */
	NSPrinter *_printer;			/* RETAINED */
}

/* **THE SHARED TICKET AND THE DEFAULT PRINTER.** `+sharedPrintInfo` is what `-print:` and the panels use when a caller
 * has no opinion; `+setSharedPrintInfo:` replaces it. The default printer is an `NSPrinter`, or nil when the machine
 * has no queues — which is a normal state, not an error. */
+ (NSPrintInfo *)sharedPrintInfo;
+ (void)setSharedPrintInfo:(NSPrintInfo *)printInfo;
+ (nullable NSPrinter *)defaultPrinter;
+ (void)setDefaultPrinter:(nullable NSPrinter *)printer;

- (instancetype)init;
- (instancetype)initWithDictionary:(nullable NSDictionary *)attributes;

/* THE WHOLE TICKET, and the door that fills in the values a fresh one starts with. */
- (NSMutableDictionary *)dictionary;
- (void)setUpPrintOperationDefaultValues;

/* THE SHEET AND ITS MARGINS, IN POINTS. */
- (NSSize)paperSize;
- (void)setPaperSize:(NSSize)size;
- (nullable NSString *)paperName;
- (void)setPaperName:(nullable NSString *)name;
- (nullable NSString *)localizedPaperName;
- (NSSize)sizeForPaperName:(NSString *)name;

- (CGFloat)topMargin;
- (void)setTopMargin:(CGFloat)margin;
- (CGFloat)bottomMargin;
- (void)setBottomMargin:(CGFloat)margin;
- (CGFloat)leftMargin;
- (void)setLeftMargin:(CGFloat)margin;
- (CGFloat)rightMargin;
- (void)setRightMargin:(CGFloat)margin;

/* **THE SHEET MINUS THE MARGINS, ORIENTATION APPLIED** — the rectangle every page is drawn into. */
- (NSRect)imageablePageBounds;

/* THE PAGE'S SHAPE AND THE JOB'S SHAPE. */
- (NSPrintingOrientation)orientation;
- (void)setOrientation:(NSPrintingOrientation)orientation;
- (CGFloat)scalingFactor;
- (void)setScalingFactor:(CGFloat)factor;
- (NSPrintingPaginationMode)horizontalPagination;
- (void)setHorizontalPagination:(NSPrintingPaginationMode)mode;
- (NSPrintingPaginationMode)verticalPagination;
- (void)setVerticalPagination:(NSPrintingPaginationMode)mode;
- (BOOL)isHorizontallyCentered;
- (void)setHorizontallyCentered:(BOOL)flag;
- (BOOL)isVerticallyCentered;
- (void)setVerticallyCentered:(BOOL)flag;

/* WHERE THE JOB GOES, AND WHETHER IT IS ONLY THE SELECTION. */
- (NSString *)jobDisposition;
- (void)setJobDisposition:(NSString *)disposition;
- (BOOL)isSelectionOnly;
- (void)setSelectionOnly:(BOOL)flag;

/* THE QUEUE, WHEN THERE IS ONE. Setting a printer also adopts its default paper size when the ticket has none. */
- (nullable NSPrinter *)printer;
- (void)setPrinter:(nullable NSPrinter *)printer;

/* THE CARBON HANDLES, WHICH THIS TIER ANSWERS NULL FOR — see the header's last paragraph. */
- (nullable void *)PMPrintSession;
- (nullable void *)PMPageFormat;
- (nullable void *)PMPrintSettings;
- (void)updateFromPMPageFormat;
- (void)updateFromPMPrintSettings;
- (nullable id)printSettings;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPRINTINFO_H */
