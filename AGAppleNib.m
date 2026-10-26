/*
 * AGAppleNib.m — Apple's compiled nib, translated into this tree's coding keys.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE THREE PIECES, IN THE ORDER THEY RUN:
 *
 *   1. THE TABLE. A nib's `$objects` table is walked once. Every object whose `$class` names a class this
 *      translator maps gets a RECORD: a dictionary of THIS tree's coding keys (`frame`, `subviews`, `cell`, …)
 *      and their translated values. A record never holds a live object; a reference is an `AGAppleNibRef`
 *      carrying the object's INDEX in Apple's table, so identity and cycles survive the rewrite unchanged.
 *   2. THE CALIBRATION. Before anything is built, every record is walked and every reference is checked: it must
 *      name another translated record, or (for a connection only) the file's owner. A reference to an object this
 *      translator did not map is refused BY NAME here, which is why a nib cannot half-load.
 *   3. THE BUILD. Each record is instantiated through `-initWithCoder:` with `AGAppleNibCoder` answering the
 *      translated keys. That is the whole reason the keys are translated into this tree's spelling: the classes'
 *      own `-initWithCoder:` runs, with its defaults, its designated initialisers and its own validation.
 *
 * APPLE'S KEY LAYOUT IS TAKEN FROM THE FIXTURES AND FROM THE ONE REFERENCE IMPLEMENTATION THIS FEDERATION HAS —
 * GNUstep's `NSView`/`NSCell`/`NSButtonCell` decoders in `audit/corpus/libs-gui` — not from a guess. The flag
 * masks below are quoted beside the door that states them. Keys not named in a class's table are DROPPED and
 * reported by `+unmappedKeysForAppleNibArchive:`; a value that cannot be translated (an attributed string, a
 * formatter, a font) is left at the class's default for the same reason.
 */

#import "AGAppleNib.h"

#import <AppKit/NSActionCell.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/ForFoundationOnly.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The record's class, and the key Apple's root uses for `NSIBObjectData`. */
static NSString * const AGAppleClassKey = @"AGAppleNibClass";
static NSString * const AGAppleObjectDataKey = @"IB.objectdata";
static NSString * const AGAppleObjectDataClassName = @"NSIBObjectData";

/* ==================================================================================================
 * THE SMALL VALUE TYPES
 * ================================================================================================ */

/* **A REFERENCE IS AN INDEX, NOT AN OBJECT.** The table is Apple's, so keeping indexes keeps identity (two
 * properties that named one object still name one object) and makes a cycle detectable instead of silently
 * duplicated. */
@interface AGAppleNibRef : NSObject
{
	NSUInteger _index;
}
+ (AGAppleNibRef *)refWithIndex:(NSUInteger)index;
- (NSUInteger)index;
@end

@implementation AGAppleNibRef

+ (AGAppleNibRef *)refWithIndex:(NSUInteger)index
{
	AGAppleNibRef *ref = [[self alloc] init];

	ref->_index = index;
	return [ref autorelease];
}

- (NSUInteger)index
{
	return _index;
}

@end

/* ==================================================================================================
 * THE CODER THE TRANSLATED RECORD ANSWERS THROUGH
 * ================================================================================================ */

@class AGAppleNibImporter;

/* **A READ-ONLY CODER OVER ONE RECORD.** Every keyed door this tree's `-initWithCoder:` implementations use is
 * answered from the record, so the object's own decode path runs unchanged. A key the record does not carry
 * answers NO from `-containsValueForKey:`, which is exactly the "missing key leaves the class's default" rule
 * `NSNib.h` states for AGNib. */
@interface AGAppleNibCoder : NSCoder
{
	AGAppleNibImporter *_importer;	/* NOT retained: the importer outlives every coder it makes */
	NSDictionary *_record;		/* NOT retained: the record outlives the build */
}
- (instancetype)initWithImporter:(AGAppleNibImporter *)importer record:(NSDictionary *)record;
@end

/* ==================================================================================================
 * THE IMPORTER
 * ================================================================================================ */

@interface AGAppleNibImporter : NSObject
{
	id _plist;				/* the decoded property list, retained */
	NSArray *_objects;			/* Apple's $objects table, retained */
	NSUInteger _objectDataIndex;		/* the NSIBObjectData object's index */
	NSUInteger _rootIndex;			/* NSRoot's index: the file's owner placeholder */
	NSMutableDictionary *_records;		/* NSNumber index -> translated record */
	NSMutableArray *_topLevelRefs;		/* AGAppleNibRef, in Apple's object-key order */
	NSMutableArray *_connectorIndexes;	/* NSNumber indexes of NSNib*Connector objects */
	NSMutableSet *_proxies;			/* NSNumber indexes of skipped proxies (NSApplication, FirstResponder) */
	NSMutableSet *_building;		/* NSNumber indexes being decoded, for cycle detection */
	NSMutableDictionary *_built;		/* NSNumber index -> live object */
	NSMutableSet *_unmapped;		/* "Class.key" strings, for the ledger */
	NSString *_reason;			/* the first refusal, retained */
}

- (instancetype)initWithArchive:(id)plist;
- (BOOL)buildRecords;
- (BOOL)instantiateTopLevelObjects:(NSArray **)outObjects connections:(NSArray **)outConnections;
- (NSArray *)unmappedKeys;
- (NSString *)reason;

/* Used by the coder and by the connection builder. */
- (id)fnDecodedValue:(id)value;
- (id)fnDecodeObjectAtIndex:(NSUInteger)index;
@end

/* ==================================================================================================
 * HELPERS
 * ================================================================================================ */

/* IS THIS VALUE ONE OF CORE FOUNDATION'S KEYED-ARCHIVER UID SLOTS? The binary reader hands them out as CF
 * objects (type id 41), which is why every reference in Apple's archive is recognised here and nowhere else. */
static BOOL fn_uid_index(id value, NSUInteger *outIndex)
{
	if (value == nil || CFGetTypeID((CFTypeRef)value) != _CFKeyedArchiverUIDGetTypeID()) {
		return NO;
	}
	if (outIndex != NULL) {
		*outIndex = (NSUInteger)_CFKeyedArchiverUIDGetValue((CFKeyedArchiverUIDRef)(void *)value);
	}
	return YES;
}

/* THE CLASSES THAT ARE NOT STRUCTURAL: collections, value leaves, and the resources a translated key may name.
 * They are skipped when the table is walked, and a kept property that names one is refused by the reference
 * calibration with the class's own name (a cell's FONT is fine to ignore; a view's CONTENT is not). */
static BOOL fn_is_auxiliary_class(NSString *name)
{
	static NSSet *auxiliary = nil;

	if (auxiliary == nil) {
		auxiliary = [[NSSet alloc] initWithObjects:
			@"NSArray", @"NSMutableArray", @"NSSet", @"NSMutableSet",
			@"NSDictionary", @"NSMutableDictionary", @"NSNull",
			@"NSString", @"NSMutableString", @"NSNumber", @"NSDate", @"NSData", @"NSValue",
			@"NSFontManager", @"NSImage", @"NSCustomResource",
			@"NSAttributedString", @"NSMutableAttributedString", @"NSParagraphStyle",
			nil];
	}
	return [auxiliary containsObject:name];
}

/* THE VIEW CLASSES THIS SLICE MAPS, and the cell classes. A view subclass outside this list (NSBox,
 * NSScrollView, NSMatrix, NSClipView, NSTextView, …) is refused rather than loaded without its state. */
static BOOL fn_is_translated_view_class(NSString *name)
{
	return [name isEqualToString:@"NSView"]
	    || [name isEqualToString:@"NSControl"]
	    || [name isEqualToString:@"NSButton"]
	    || [name isEqualToString:@"NSTextField"]
	    || [name isEqualToString:@"NSSplitView"]
	    || [name isEqualToString:@"NSCustomView"]
	    || [name isEqualToString:@"NSBox"]
	    || [name isEqualToString:@"NSScrollView"]
	    || [name isEqualToString:@"NSClipView"]
	    || [name isEqualToString:@"NSMatrix"]
	    || [name isEqualToString:@"NSSlider"];
}

static BOOL fn_is_translated_cell_class(NSString *name)
{
	return [name isEqualToString:@"NSCell"]
	    || [name isEqualToString:@"NSActionCell"]
	    || [name isEqualToString:@"NSButtonCell"]
	    || [name isEqualToString:@"NSTextFieldCell"]
	    || [name isEqualToString:@"NSSliderCell"];
}

/* ==================================================================================================
 * THE CODER
 * ================================================================================================ */

@implementation AGAppleNibCoder

- (instancetype)initWithImporter:(AGAppleNibImporter *)importer record:(NSDictionary *)record
{
	self = [super init];
	if (self != nil) {
		_importer = importer;
		_record = record;
	}
	return self;
}

- (BOOL)allowsKeyedCoding
{
	return YES;
}

- (BOOL)containsValueForKey:(NSString *)key
{
	return [_record objectForKey:key] != nil;
}

- (id)decodeObjectForKey:(NSString *)key
{
	return [_importer fnDecodedValue:[_record objectForKey:key]];
}

- (id)decodeObjectOfClass:(Class)cls forKey:(NSString *)key
{
	id value = [self decodeObjectForKey:key];

	return (value != nil && [value isKindOfClass:cls]) ? value : nil;
}

- (id)decodeObjectOfClasses:(NSSet *)classes forKey:(NSString *)key
{
	id value = [self decodeObjectForKey:key];
	NSEnumerator *e;
	id cls;

	if (value == nil) {
		return nil;
	}
	e = [classes objectEnumerator];
	while ((cls = [e nextObject]) != nil) {
		if ([value isKindOfClass:(Class)cls]) {
			return value;
		}
	}
	return nil;
}

- (BOOL)decodeBoolForKey:(NSString *)key
{
	return [[_record objectForKey:key] boolValue];
}

- (int)decodeIntForKey:(NSString *)key
{
	return [[_record objectForKey:key] intValue];
}

- (NSInteger)decodeIntegerForKey:(NSString *)key
{
	return [[_record objectForKey:key] integerValue];
}

- (int32_t)decodeInt32ForKey:(NSString *)key
{
	return (int32_t)[[_record objectForKey:key] longValue];
}

- (int64_t)decodeInt64ForKey:(NSString *)key
{
	return (int64_t)[[_record objectForKey:key] longLongValue];
}

- (float)decodeFloatForKey:(NSString *)key
{
	return [[_record objectForKey:key] floatValue];
}

- (double)decodeDoubleForKey:(NSString *)key
{
	return [[_record objectForKey:key] doubleValue];
}

- (NSRect)decodeRectForKey:(NSString *)key
{
	id value = [_record objectForKey:key];

	return [value isKindOfClass:[NSValue class]] ? [(NSValue *)value rectValue] : NSZeroRect;
}

- (NSSize)decodeSizeForKey:(NSString *)key
{
	id value = [_record objectForKey:key];

	return [value isKindOfClass:[NSValue class]] ? [(NSValue *)value sizeValue] : NSZeroSize;
}

- (NSPoint)decodePointForKey:(NSString *)key
{
	id value = [_record objectForKey:key];

	return [value isKindOfClass:[NSValue class]] ? [(NSValue *)value pointValue] : NSZeroPoint;
}

- (const void *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)lengthp
{
	id value = [_record objectForKey:key];

	if (![value isKindOfClass:[NSData class]]) {
		if (lengthp != NULL) {
			*lengthp = 0;
		}
		return NULL;
	}
	if (lengthp != NULL) {
		*lengthp = [(NSData *)value length];
	}
	return [(NSData *)value bytes];
}

- (NSInteger)versionForClassName:(NSString *)className
{
	(void)className;
	return 0;
}

@end

/* ==================================================================================================
 * THE IMPORTER
 * ================================================================================================ */

@implementation AGAppleNibImporter

- (instancetype)initWithArchive:(id)plist
{
	self = [super init];
	if (self != nil) {
		_plist = [plist retain];
		_records = [[NSMutableDictionary alloc] init];
		_topLevelRefs = [[NSMutableArray alloc] init];
		_connectorIndexes = [[NSMutableArray alloc] init];
		_proxies = [[NSMutableSet alloc] init];
		_building = [[NSMutableSet alloc] init];
		_built = [[NSMutableDictionary alloc] init];
		_unmapped = [[NSMutableSet alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_plist release];
	[_objects release];
	[_records release];
	[_topLevelRefs release];
	[_connectorIndexes release];
	[_proxies release];
	[_building release];
	[_built release];
	[_unmapped release];
	[_reason release];
	[super dealloc];
}

- (NSString *)reason
{
	return _reason;
}

- (NSArray *)unmappedKeys
{
	return [_unmapped allObjects];
}

- (BOOL)fnFail:(NSString *)reason
{
	if (_reason == nil) {
		_reason = [reason copy];
	}
	return NO;
}

- (id)fnFailValue:(NSString *)reason
{
	[self fnFail:reason];
	return nil;
}

/* ---- resolving Apple's slots --------------------------------------------------------------- */

- (id)fnResolvedValue:(id)value
{
	NSUInteger index;

	if (fn_uid_index(value, &index) && index < [_objects count]) {
		return [_objects objectAtIndex:index];
	}
	return value;
}

- (NSString *)fnStringValue:(id)value
{
	id resolved = [self fnResolvedValue:value];

	return [resolved isKindOfClass:[NSString class]] ? (NSString *)resolved : nil;
}

- (NSNumber *)fnNumberValue:(id)value
{
	id resolved = [self fnResolvedValue:value];

	return [resolved isKindOfClass:[NSNumber class]] ? (NSNumber *)resolved : nil;
}

/* THE ITEMS OF A COLLECTION VALUE: Apple stores `{ "$class": <NSArray>, "NS.objects": [ <uid>, … ] }`, and the
 * contents are an INLINE property-list array (not another slot). Both spellings are accepted. */
- (NSArray *)fnArrayValue:(id)value
{
	id resolved = [self fnResolvedValue:value];

	if ([resolved isKindOfClass:[NSArray class]]) {
		return (NSArray *)resolved;
	}
	if ([resolved isKindOfClass:[NSDictionary class]]) {
		id items = [(NSDictionary *)resolved objectForKey:@"NS.objects"];
		NSArray *array;

		if (items == nil) {
			items = [(NSDictionary *)resolved objectForKey:@"NS.keys"];
		}
		array = [self fnResolvedValue:items];
		if ([array isKindOfClass:[NSArray class]]) {
			return array;
		}
	}
	return nil;
}

- (NSString *)fnClassNameAt:(NSUInteger)index
{
	id entry;
	NSUInteger classIndex;
	id classEntry;
	id name;

	if (index >= [_objects count]) {
		return nil;
	}
	entry = [_objects objectAtIndex:index];
	if (![entry isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	if (!fn_uid_index([(NSDictionary *)entry objectForKey:@"$class"], &classIndex) ||
	    classIndex >= [_objects count]) {
		return nil;
	}
	classEntry = [_objects objectAtIndex:classIndex];
	if (![classEntry isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	name = [(NSDictionary *)classEntry objectForKey:@"$classname"];
	if (fn_uid_index(name, &classIndex)) {
		name = (classIndex < [_objects count]) ? [_objects objectAtIndex:classIndex] : nil;
	}
	return [name isKindOfClass:[NSString class]] ? (NSString *)name : nil;
}

/* THE LEDGER: every key of this entry that the translation did not consume is named `Class.key`. `$class` and
 * the class entry's own keys are not part of the object's state. */
- (void)fnNoteUnmappedForEntry:(NSDictionary *)entry className:(NSString *)className consumed:(NSSet *)consumed
{
	NSEnumerator *e = [[entry allKeys] objectEnumerator];
	NSString *key;

	while ((key = [e nextObject]) != nil) {
		if ([key isEqualToString:@"$class"] || [consumed containsObject:key]) {
			continue;
		}
		[_unmapped addObject:[NSString stringWithFormat:@"%@.%@", className, key]];
	}
}

/* ---- the table walk ------------------------------------------------------------------------ */


/* ---- class-specific children and properties ------------------------------------------------- */

/* ONE REFERENCE, PUT UNDER THIS TREE'S KEY. Geometry and scalars are translated where they are read; every object
 * child goes through here, so "is this slot a UID" is answered once. */
- (BOOL)fnSetRefFrom:(id)value key:(NSString *)key inRecord:(NSMutableDictionary *)record as:(NSString *)agnibKey
{
	NSUInteger index;

	if (value == nil) {
		return YES;
	}
	if (!fn_uid_index(value, &index)) {
		return [self fnFail:[NSString stringWithFormat:@"%@ is not an object reference", key]];
	}
	[record setObject:[AGAppleNibRef refWithIndex:index] forKey:agnibKey];
	return YES;
}

/* **NSBOX: ITS CHILD IS `NSContentView`, NOT `NSSubviews`.** Apple lists the content view in both; taking the
 * `NSSubviews` array as well would add it twice (the box's own door re-parents it). `NSTitleCell` is the cell that
 * draws the title, and `NSOffsets` is this tree's `contentViewMargins`. */
- (BOOL)fnBuildBoxExtrasForEntry:(NSDictionary *)entry record:(NSMutableDictionary *)record
{
	NSNumber *number;
	NSString *value;

	if (![self fnSetRefFrom:[entry objectForKey:@"NSContentView"] key:@"NSContentView"
		       inRecord:record as:@"contentView"]) {
		return NO;
	}
	if (![self fnSetRefFrom:[entry objectForKey:@"NSTitleCell"] key:@"NSTitleCell"
		       inRecord:record as:@"titleCell"]) {
		return NO;
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSOffsets"]]) != nil) {
		[record setObject:[NSValue valueWithSize:NSSizeFromString(value)] forKey:@"contentViewMargins"];
	}
	number = [self fnNumberValue:[entry objectForKey:@"NSBoxType"]];
	if (number != nil) {
		[record setObject:number forKey:@"boxType"];
	}
	number = [self fnNumberValue:[entry objectForKey:@"NSBorderType"]];
	if (number != nil) {
		[record setObject:number forKey:@"borderType"];
	}
	number = [self fnNumberValue:[entry objectForKey:@"NSTitlePosition"]];
	if (number != nil) {
		[record setObject:number forKey:@"titlePosition"];
	}
	number = [self fnNumberValue:[entry objectForKey:@"NSTransparent"]];
	if (number != nil) {
		[record setObject:number forKey:@"transparent"];
	}
	return YES;
}

/* **NSScrollView: APPLE'S `NSsFlags` IS THE DESIGN, AND THE SCROLLER OBJECTS ARE ITS RENDERED FORM.** The low two bits
 * are the border type, 16 and 32 say a bar exists, and 512 is autohide (GNUstep's `NSScrollView -initWithCoder:`
 * reads exactly these). This tree creates its own bars from those flags, so the archived `NSScroller`s are dropped
 * rather than translated; that is why they are in the consumed list below. */
- (BOOL)fnBuildScrollViewExtrasForEntry:(NSDictionary *)entry record:(NSMutableDictionary *)record
{
	NSNumber *number;
	unsigned int flags;

	if (![self fnSetRefFrom:[entry objectForKey:@"NSContentView"] key:@"NSContentView"
		       inRecord:record as:@"contentView"]) {
		return NO;
	}
	number = [self fnNumberValue:[entry objectForKey:@"NSsFlags"]];
	if (number != nil) {
		flags = [number unsignedIntValue];
		[record setObject:[NSNumber numberWithUnsignedInteger:(flags & 3u)] forKey:@"borderType"];
		[record setObject:[NSNumber numberWithBool:((flags & 16u) != 0)]
			   forKey:@"hasVerticalScroller"];
		[record setObject:[NSNumber numberWithBool:((flags & 32u) != 0)]
			   forKey:@"hasHorizontalScroller"];
		[record setObject:[NSNumber numberWithBool:((flags & 512u) != 0)]
			   forKey:@"autohidesScrollers"];
	}
	[self fnSetColorRef:[entry objectForKey:@"NSBackgroundColor"] key:@"NSBackgroundColor"
		   inRecord:record as:@"backgroundColor" translated:NULL];
	[self fnSetColorRef:[entry objectForKey:@"NSBGColor"] key:@"NSBGColor"
		   inRecord:record as:@"backgroundColor" translated:NULL];
	return YES;
}

/* **NSClipView: THE DOCUMENT IS `NSDocView` AND IS BORROWED.** It is put back through `-setDocumentView:`, which is
 * what re-registers the frame/bounds notifications and clamps the origin. `NScvFlags` bits 4 and 2 are
 * drawsBackground and no-copy-on-scroll. */
- (BOOL)fnBuildClipViewExtrasForEntry:(NSDictionary *)entry record:(NSMutableDictionary *)record
{
	id document = [entry objectForKey:@"NSDocView"];
	NSNumber *number;
	NSArray *subviews;

	if (document == nil) {
		subviews = [self fnArrayValue:[entry objectForKey:@"NSSubviews"]];
		if ([subviews count] > 0) {
			document = [subviews objectAtIndex:0];
		}
	}
	if (![self fnSetRefFrom:document key:@"NSDocView" inRecord:record as:@"documentView"]) {
		return NO;
	}
	number = [self fnNumberValue:[entry objectForKey:@"NScvFlags"]];
	if (number != nil) {
		unsigned int flags = [number unsignedIntValue];

		[record setObject:[NSNumber numberWithBool:((flags & 4u) != 0)] forKey:@"drawsBackground"];
		[record setObject:[NSNumber numberWithBool:((flags & 2u) == 0)] forKey:@"copiesOnScroll"];
	}
	[self fnSetColorRef:[entry objectForKey:@"NSBGColor"] key:@"NSBGColor" inRecord:record
			 as:@"backgroundColor" translated:NULL];
	return YES;
}

/* **NSMatrix: APPLE'S `NSCells` IS FLAT AND THIS TREE'S `NSMatrixCells` IS AN ARRAY OF ROWS.** The rows and columns
 * come from `NSNumRows`/`NSNumCols`, the sizes are strings, and the selected cell is a REFERENCE into the flat array
 * that becomes the per-slot boolean array this tree archives. `NSMatrixFlags` is intentionally not translated: its
 * bitfield's byte order differs between the PowerPC-era writers these archives come from, and a guessed mode is
 * worse than the list mode this tree defaults to (the ledger names it). */
- (BOOL)fnBuildMatrixExtrasForEntry:(NSDictionary *)entry record:(NSMutableDictionary *)record
{
	NSArray *flat = [self fnArrayValue:[entry objectForKey:@"NSCells"]];
	NSNumber *rowsValue = [self fnNumberValue:[entry objectForKey:@"NSNumRows"]];
	NSNumber *colsValue = [self fnNumberValue:[entry objectForKey:@"NSNumCols"]];
	NSInteger rows = (rowsValue != nil) ? [rowsValue integerValue] : 0;
	NSInteger cols = (colsValue != nil) ? [colsValue integerValue] : 0;
	NSMutableArray *rowArrays;
	NSMutableArray *selectedFlags;
	NSUInteger selectedIndex = NSNotFound;
	NSUInteger selectedValue = 0;
	BOOL haveSelected = NO;
	NSString *value;
	NSInteger r, c;

	if (flat == nil || rows <= 0 || cols <= 0 || (NSUInteger)(rows * cols) != [flat count]) {
		return [self fnFail:[NSString stringWithFormat:
			@"its NSMatrix cells (%lu) do not match %ld rows by %ld columns",
			(unsigned long)[flat count], (long)rows, (long)cols]];
	}
	if ([entry objectForKey:@"NSSelectedCell"] != nil) {
		haveSelected = fn_uid_index([entry objectForKey:@"NSSelectedCell"], &selectedValue);
	}
	for (r = 0; r < rows * cols; r++) {
		NSUInteger cellIndex;

		if (!fn_uid_index([flat objectAtIndex:(NSUInteger)r], &cellIndex)) {
			return [self fnFail:@"an NSMatrix cell is not an object reference"];
		}
		if (haveSelected && cellIndex == selectedValue) {
			selectedIndex = (NSUInteger)r;
		}
	}
	rowArrays = [NSMutableArray arrayWithCapacity:(NSUInteger)rows];
	selectedFlags = [NSMutableArray arrayWithCapacity:(NSUInteger)(rows * cols)];
	for (r = 0; r < rows; r++) {
		NSMutableArray *row = [NSMutableArray arrayWithCapacity:(NSUInteger)cols];

		for (c = 0; c < cols; c++) {
			NSUInteger cellIndex;
			NSUInteger slot = (NSUInteger)(r * cols + c);

			fn_uid_index([flat objectAtIndex:slot], &cellIndex);
			[row addObject:[AGAppleNibRef refWithIndex:cellIndex]];
			[selectedFlags addObject:[NSNumber numberWithBool:(slot == selectedIndex)]];
		}
		[rowArrays addObject:row];
	}
	[record setObject:rowArrays forKey:@"NSMatrixCells"];
	[record setObject:selectedFlags forKey:@"NSMatrixSelected"];
	[record setObject:[NSNumber numberWithInteger:rows] forKey:@"NSMatrixRows"];
	[record setObject:[NSNumber numberWithInteger:cols] forKey:@"NSMatrixColumns"];
	if ((value = [self fnStringValue:[entry objectForKey:@"NSCellSize"]]) != nil) {
		[record setObject:[NSValue valueWithSize:NSSizeFromString(value)] forKey:@"NSMatrixCellSize"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSIntercellSpacing"]]) != nil) {
		[record setObject:[NSValue valueWithSize:NSSizeFromString(value)]
			   forKey:@"NSMatrixIntercellSpacing"];
	}
	[self fnSetColorRef:[entry objectForKey:@"NSBackgroundColor"] key:@"NSBackgroundColor"
		   inRecord:record as:@"NSMatrixBackgroundColor" translated:NULL];
	[self fnSetColorRef:[entry objectForKey:@"NSCellBackgroundColor"] key:@"NSCellBackgroundColor"
		   inRecord:record as:@"NSMatrixCellBackgroundColor" translated:NULL];
	return YES;
}


/* **A FONT IS A DESIGN VALUE, NOT A STRUCTURAL OBJECT.** Apple's `NSFont` archive is three keys: the name, the size
 * and a traits bitfield. This tree's `NSFont -initWithCoder:` asks for `fontName` and `pointSize` and substitutes a
 * system font when the name is missing (a design written on another machine), so the translation states the two
 * keys that matter and leaves `NSfFlags` to the ledger — the face's name already carries the family, and guessing a
 * trait mask is the wrong value `NSNib.h` refuses. */

/* **A COLOUR IS A LEAF, AND APPLE'S THREE SPELLINGS ARE ALL COMPONENT TEXT.** `NSWhite` is "w" or "w a", `NSRGB` is
 * "r g b" or "r g b a" in an NSData whose bytes are an ASCII C string (MEASURED across the corpus: `b'1\0'`,
 * `b'0 0.80000001\0'`, `b'0 0 1\0'`), and a catalog colour (`NSColorSpace` 6) carries a FALLBACK NSColor that resolves
 * the same way. This tree's NSColor codes calibrated RGBA, so all three become those four numbers; a space with none
 * of them (a pattern or CMYK colour) is refused by name rather than guessed. */
static BOOL fn_parse_color_components(NSData *data, CGFloat *values, NSUInteger maximum, NSUInteger *count)
{
	char buffer[128];
	NSUInteger length;
	char *cursor;
	NSUInteger n = 0;

	if (![data isKindOfClass:[NSData class]]) {
		return NO;
	}
	length = [data length];
	if (length >= sizeof(buffer)) {
		length = sizeof(buffer) - 1;
	}
	memcpy(buffer, [data bytes], length);
	buffer[length] = '\0';
	cursor = buffer;
	while (n < maximum) {
		char *end = NULL;
		double number;

		while (*cursor == ' ' || *cursor == '\t' || *cursor == '\n') {
			cursor++;
		}
		if (*cursor == '\0') {
			break;
		}
		number = strtod(cursor, &end);
		if (end == cursor) {
			break;
		}
		values[n++] = (CGFloat)number;
		cursor = end;
	}
	if (count != NULL) {
		*count = n;
	}
	return n > 0;
}

- (BOOL)fnColorComponentsFromEntry:(NSDictionary *)entry
			       red:(CGFloat *)red
			     green:(CGFloat *)green
			      blue:(CGFloat *)blue
			     alpha:(CGFloat *)alpha
			     depth:(NSUInteger)depth
{
	CGFloat values[4] = { 0.0, 0.0, 0.0, 1.0 };
	NSUInteger count = 0;
	id value;

	if (depth > 4) {
		return [self fnFail:@"a catalog colour's fallback chain does not end"];
	}
	value = [entry objectForKey:@"NSWhite"];
	if (value != nil) {
		if (!fn_parse_color_components([self fnResolvedValue:value], values, 2, &count)) {
			return [self fnFail:@"an NSWhite colour carries no values"];
		}
		values[1] = (count > 1) ? values[1] : 1.0;
		*red = *green = *blue = values[0];
		*alpha = values[1];
		return YES;
	}
	value = [entry objectForKey:@"NSRGB"];
	if (value != nil) {
		if (!fn_parse_color_components([self fnResolvedValue:value], values, 4, &count) || count < 3) {
			return [self fnFail:@"an NSRGB colour carries fewer than three values"];
		}
		*red = values[0];
		*green = values[1];
		*blue = values[2];
		*alpha = (count > 3) ? values[3] : 1.0;
		return YES;
	}
	/* THE CATALOG COLOUR: `NSColor` is the resolved fallback. */
	value = [entry objectForKey:@"NSColor"];
	if (value != nil) {
		id fallback = [self fnResolvedValue:value];

		if ([fallback isKindOfClass:[NSDictionary class]]) {
			return [self fnColorComponentsFromEntry:fallback red:red green:green blue:blue
							alpha:alpha depth:depth + 1];
		}
	}
	{
		NSNumber *space = [self fnNumberValue:[entry objectForKey:@"NSColorSpace"]];

		return [self fnFail:[NSString stringWithFormat:
			@"an NSColor in space %ld has no white, RGB or catalog fallback this translator can read",
			(space != nil) ? (long)[space integerValue] : -1L]];
	}
}

- (BOOL)fnBuildColorRecordAtIndex:(NSUInteger)index record:(NSMutableDictionary *)record
{
	NSDictionary *entry = [_objects objectAtIndex:index];
	CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0;

	if (![self fnColorComponentsFromEntry:entry red:&red green:&green blue:&blue alpha:&alpha depth:0]) {
		return NO;
	}
	[record setObject:@"NSColor" forKey:AGAppleClassKey];
	[record setObject:[NSNumber numberWithDouble:(double)red] forKey:@"redComponent"];
	[record setObject:[NSNumber numberWithDouble:(double)green] forKey:@"greenComponent"];
	[record setObject:[NSNumber numberWithDouble:(double)blue] forKey:@"blueComponent"];
	[record setObject:[NSNumber numberWithDouble:(double)alpha] forKey:@"alphaComponent"];
	[self fnNoteUnmappedForEntry:entry className:@"NSColor"
			    consumed:[NSSet setWithObjects:
				@"NSWhite", @"NSRGB", @"NSColorSpace", @"NSCatalogName",
				@"NSColorName", @"NSColor", nil]];
	return YES;
}


/* A COLOUR REFERENCE, WHEN THE VALUE NAMES A TRANSLATED NSColor. Anything else (an image, or no value) is left alone
 * so the ledger can name the key; `translated` says whether the caller may mark it consumed. */
- (BOOL)fnSetColorRef:(id)value key:(NSString *)key inRecord:(NSMutableDictionary *)record
		   as:(NSString *)agnibKey translated:(BOOL *)translated
{
	NSUInteger index;

	if (translated != NULL) {
		*translated = NO;
	}
	if (value == nil || !fn_uid_index(value, &index)) {
		return YES;
	}
	if (![[self fnClassNameAt:index] isEqualToString:@"NSColor"]) {
		return YES;
	}
	[record setObject:[AGAppleNibRef refWithIndex:index] forKey:agnibKey];
	if (translated != NULL) {
		*translated = YES;
	}
	return YES;
}

- (BOOL)fnBuildFontRecordAtIndex:(NSUInteger)index record:(NSMutableDictionary *)record
{
	NSDictionary *entry = [_objects objectAtIndex:index];
	NSString *name = [self fnStringValue:[entry objectForKey:@"NSName"]];
	NSNumber *size = [self fnNumberValue:[entry objectForKey:@"NSSize"]];

	if (name == nil) {
		return [self fnFail:@"a font in the archive has no NSName"];
	}
	if (size == nil) {
		return [self fnFail:[NSString stringWithFormat:@"the font %@ has no NSSize", name]];
	}
	[record setObject:@"NSFont" forKey:AGAppleClassKey];
	[record setObject:name forKey:@"fontName"];
	[record setObject:size forKey:@"pointSize"];
	[self fnNoteUnmappedForEntry:entry className:@"NSFont"
			    consumed:[NSSet setWithObjects:@"NSName", @"NSSize", nil]];
	return YES;
}

- (BOOL)fnBuildViewRecordAtIndex:(NSUInteger)index
			  appleClass:(NSString *)appleClass
			      record:(NSMutableDictionary *)record
{
	NSDictionary *entry = [_objects objectAtIndex:index];
	NSString *targetName = appleClass;
	Class cls;
	NSString *value;
	NSNumber *number;
	NSArray *items;
	NSMutableArray *refs;
	NSUInteger i;

	if ([appleClass isEqualToString:@"NSCustomView"]) {
		targetName = [self fnStringValue:[entry objectForKey:@"NSClassName"]];
		if (targetName == nil) {
			return [self fnFail:@"an NSCustomView in the archive names no class"];
		}
	}
	cls = NSClassFromString(targetName);
	if (cls == Nil) {
		return [self fnFail:[NSString stringWithFormat:
			@"it names the view class %@, which is not in this process", targetName]];
	}
	if (![cls isSubclassOfClass:[NSView class]]) {
		return [self fnFail:[NSString stringWithFormat:
			@"%@ is not an NSView subclass", targetName]];
	}
	if (![NSNib isSupportedClass:cls]) {
		return [self fnFail:[NSString stringWithFormat:
			@"the view class %@ is not on NSNib's allow-list; register it with +[NSNib registerDesignClass:]",
			targetName]];
	}
	[record setObject:targetName forKey:AGAppleClassKey];

	value = [self fnStringValue:[entry objectForKey:@"NSFrame"]];
	if (value != nil) {
		[record setObject:[NSValue valueWithRect:NSRectFromString(value)] forKey:@"frame"];
	} else if ((value = [self fnStringValue:[entry objectForKey:@"NSFrameSize"]]) != nil) {
		NSSize size = NSSizeFromString(value);

		[record setObject:[NSValue valueWithRect:NSMakeRect(0.0, 0.0, size.width, size.height)]
			   forKey:@"frame"];
	}

	/* **THE VIEW FLAGS, AND THE MASKS ARE GNUSTEP'S `NSView -initWithCoder:` (audit/corpus): the lower six bits
	 * are the autoresizing mask ("Apple use the same constants in the lower bits"), 0x100 is autoresizesSubviews
	 * and 0x80000000 is hidden.** */
	number = [self fnNumberValue:[entry objectForKey:@"NSvFlags"]];
	if (number != nil) {
		unsigned int flags = [number unsignedIntValue];

		[record setObject:[NSNumber numberWithBool:((flags & 0x80000000u) != 0)] forKey:@"hidden"];
		[record setObject:[NSNumber numberWithUnsignedInteger:(flags & 0x3Fu)] forKey:@"autoresizingMask"];
		[record setObject:[NSNumber numberWithBool:((flags & 0x100u) != 0)] forKey:@"autoresizesSubviews"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSToolTip"]]) != nil) {
		[record setObject:value forKey:@"toolTip"];
	}
	if ([entry objectForKey:@"NSConstraints"] != nil) {
		return [self fnFail:[NSString stringWithFormat:
			@"%@ carries autolayout constraints, which this translator does not map yet", appleClass]];
	}
	/* **THE CLASSES WHOSE CHILD IS NOT `NSSubviews`.** Each of these owns its children through a typed door (a box's
	 * content view, a scroll view's clip view, a clip view's document, a matrix's cells), so taking the generic array
	 * as well would add the same object twice. The extras functions above state each one's own spelling. */
	if ([appleClass isEqualToString:@"NSBox"]) {
		if (![self fnBuildBoxExtrasForEntry:entry record:record]) {
			return NO;
		}
	} else if ([appleClass isEqualToString:@"NSScrollView"]) {
		if (![self fnBuildScrollViewExtrasForEntry:entry record:record]) {
			return NO;
		}
	} else if ([appleClass isEqualToString:@"NSClipView"]) {
		if (![self fnBuildClipViewExtrasForEntry:entry record:record]) {
			return NO;
		}
	} else if ([appleClass isEqualToString:@"NSMatrix"]) {
		if (![self fnBuildMatrixExtrasForEntry:entry record:record]) {
			return NO;
		}
	} else if ([entry objectForKey:@"NSSubviews"] != nil) {
		items = [self fnArrayValue:[entry objectForKey:@"NSSubviews"]];
		if (items == nil) {
			return [self fnFail:[NSString stringWithFormat:@"%@'s NSSubviews is not a collection", appleClass]];
		}
		refs = [NSMutableArray arrayWithCapacity:[items count]];
		for (i = 0; i < [items count]; i++) {
			NSUInteger subview;

			if (!fn_uid_index([items objectAtIndex:i], &subview)) {
				return [self fnFail:[NSString stringWithFormat:
					@"%@'s NSSubviews holds an entry that is not an object", appleClass]];
			}
			[refs addObject:[AGAppleNibRef refWithIndex:subview]];
		}
		[record setObject:refs forKey:@"subviews"];
	}
	if ([cls isSubclassOfClass:[NSControl class]] && [entry objectForKey:@"NSCell"] != nil) {
		NSUInteger cellIndex;

		if (!fn_uid_index([entry objectForKey:@"NSCell"], &cellIndex)) {
			return [self fnFail:[NSString stringWithFormat:@"%@'s NSCell is not an object", appleClass]];
		}
		[record setObject:[AGAppleNibRef refWithIndex:cellIndex] forKey:@"cell"];
	}

	{
		NSMutableSet *consumed = [NSMutableSet setWithObjects:
			@"NSFrame", @"NSFrameSize", @"NSvFlags", @"NSToolTip", @"NSSubviews",
			@"NSCell", @"NSAllowsLogicalLayoutDirection", @"NSNextKeyView",
			@"NSPreviousKeyView", nil];

		if ([appleClass isEqualToString:@"NSBox"]) {
			[consumed addObjectsFromArray:[NSArray arrayWithObjects:
				@"NSContentView", @"NSTitleCell", @"NSOffsets", @"NSBoxType",
				@"NSBorderType", @"NSTitlePosition", @"NSTransparent", nil]];
		} else if ([appleClass isEqualToString:@"NSScrollView"]) {
			[consumed addObjectsFromArray:[NSArray arrayWithObjects:
				@"NSContentView", @"NSsFlags", @"NSVScroller", @"NSHScroller",
				@"NSBackgroundColor", @"NSBGColor", nil]];
		} else if ([appleClass isEqualToString:@"NSClipView"]) {
			[consumed addObjectsFromArray:[NSArray arrayWithObjects:
				@"NSDocView", @"NScvFlags", @"NSBGColor", nil]];
		} else if ([appleClass isEqualToString:@"NSMatrix"]) {
			[consumed addObjectsFromArray:[NSArray arrayWithObjects:
				@"NSCells", @"NSNumRows", @"NSNumCols", @"NSCellSize",
				@"NSIntercellSpacing", @"NSSelectedCell", @"NSMatrixFlags",
				@"NSCellClass", @"NSProtoCell", @"NSEnabled",
				@"NSBackgroundColor", @"NSCellBackgroundColor", nil]];
		}
		[self fnNoteUnmappedForEntry:entry className:appleClass consumed:consumed];
	}
	return YES;
}

- (BOOL)fnBuildCellRecordAtIndex:(NSUInteger)index
		      appleClass:(NSString *)appleClass
			  record:(NSMutableDictionary *)record
{
	NSDictionary *entry = [_objects objectAtIndex:index];
	Class cls = NSClassFromString(appleClass);
	NSNumber *number;
	NSString *value;
	BOOL textColorTranslated = NO;
	BOOL backgroundColorTranslated = NO;
	BOOL drawsBackgroundTranslated = NO;

	if (cls == Nil) {
		return [self fnFail:[NSString stringWithFormat:@"it names the cell class %@, which is not in this process",
			appleClass]];
	}
	if (![cls isSubclassOfClass:[NSCell class]]) {
		return [self fnFail:[NSString stringWithFormat:@"%@ is not an NSCell subclass", appleClass]];
	}
	if (![NSNib isSupportedClass:cls]) {
		return [self fnFail:[NSString stringWithFormat:
			@"the cell class %@ is not on NSNib's allow-list", appleClass]];
	}
	[record setObject:appleClass forKey:AGAppleClassKey];

	/* **THE CELL FLAGS, AGAIN FROM GNUSTEP'S DECODER (`NSCell -initWithCoder:`), WHICH QUOTES THE MASKS.** */
	number = [self fnNumberValue:[entry objectForKey:@"NSCellFlags"]];
	if (number != nil) {
		unsigned int f = [number unsignedIntValue];

		[record setObject:[NSNumber numberWithUnsignedInteger:(f & 0x3u)] forKey:@"focusRingType"];
		[record setObject:[NSNumber numberWithBool:((f & 0x4u) != 0)] forKey:@"showsFirstResponder"];
		[record setObject:[NSNumber numberWithBool:((f & 0x40u) == 0)] forKey:@"wraps"];
		[record setObject:[NSNumber numberWithBool:((f & 0x100000u) != 0)] forKey:@"scrollable"];
		[record setObject:[NSNumber numberWithBool:((f & 0x200000u) != 0)] forKey:@"selectable"];
		[record setObject:[NSNumber numberWithBool:((f & 0x400000u) != 0)] forKey:@"bezeled"];
		[record setObject:[NSNumber numberWithBool:((f & 0x800000u) != 0)] forKey:@"bordered"];
		[record setObject:[NSNumber numberWithUnsignedInteger:((f & 0x0C000000u) >> 26)] forKey:@"cellType"];
		[record setObject:[NSNumber numberWithBool:((f & 0x10000000u) != 0)] forKey:@"editable"];
		[record setObject:[NSNumber numberWithBool:((f & 0x20000000u) == 0)] forKey:@"enabled"];
		[record setObject:[NSNumber numberWithInteger:((f & 0x80000000u) != 0) ? NSOnState : NSOffState]
			   forKey:@"state"];
	}
	number = [self fnNumberValue:[entry objectForKey:@"NSCellFlags2"]];
	if (number != nil) {
		unsigned int f = [number unsignedIntValue];

		[record setObject:[NSNumber numberWithBool:((f & 0x40u) != 0)] forKey:@"usesSingleLineMode"];
		[record setObject:[NSNumber numberWithUnsignedInteger:((f & 0xE0u) >> 5)] forKey:@"controlTint"];
		[record setObject:[NSNumber numberWithUnsignedInteger:((f & 0xE00u) >> 9)] forKey:@"lineBreakMode"];
		[record setObject:[NSNumber numberWithUnsignedInteger:((f & 0xE0000u) >> 17)] forKey:@"controlSize"];
		[record setObject:[NSNumber numberWithBool:((f & 0x400000u) != 0)] forKey:@"sendsActionOnEndEditing"];
		[record setObject:[NSNumber numberWithBool:((f & 0x1000000u) != 0)] forKey:@"allowsMixedState"];
		[record setObject:[NSNumber numberWithBool:((f & 0x2000000u) != 0)] forKey:@"refusesFirstResponder"];
		[record setObject:[NSNumber numberWithUnsignedInteger:((f & 0x1C000000u) >> 26)] forKey:@"alignment"];
		[record setObject:[NSNumber numberWithBool:((f & 0x20000000u) != 0)] forKey:@"importsGraphics"];
		[record setObject:[NSNumber numberWithBool:((f & 0x40000000u) != 0)]
			   forKey:@"allowsEditingTextAttributes"];
	}

	value = [self fnStringValue:[entry objectForKey:@"NSContents"]];
	if (value != nil) {
		/* **THE CONTENTS ARE THE VALUE EVERY CELL CARRIES; A BUTTON'S TITLE IS THE SAME STRING UNDER APPLE'S
		 * MODEL, and this tree keeps the two in separate ivars.** A text field reads `objectValue`; a button
		 * reads `title`, so both are stated for the button. */
		[record setObject:value forKey:@"objectValue"];
		/* **AND THE TITLE, FOR EVERY CELL.** A button draws `-title`; a box's `-title` is its TITLE
		 * CELL's title; a field reads `-objectValue`. Apple's `NSContents` is the one string all three
		 * stand on, so it is written under both names rather than guessed per class. */
		[record setObject:value forKey:@"title"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSKeyEquivalent"]]) != nil) {
		[record setObject:value forKey:@"keyEquivalent"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSAlternateContents"]]) != nil) {
		[record setObject:value forKey:@"alternateTitle"];
	}
	/* **`NSSupport` IS A FONT IN THE COMMON CASE AND AN IMAGE IN THE RARE ONE.** Only the font is translated, so the
	 * cell gets this tree's `font` key; an image stays at the cell's default and the ledger names the key. */
	{
		id support = [entry objectForKey:@"NSSupport"];
		NSUInteger supportIndex;

		if (support != nil && fn_uid_index(support, &supportIndex) &&
		    [[self fnClassNameAt:supportIndex] isEqualToString:@"NSFont"]) {
			[record setObject:[AGAppleNibRef refWithIndex:supportIndex] forKey:@"font"];
		}
	}
	[self fnSetColorRef:[entry objectForKey:@"NSTextColor"] key:@"NSTextColor" inRecord:record
			 as:@"textColor" translated:&textColorTranslated];
	[self fnSetColorRef:[entry objectForKey:@"NSBackgroundColor"] key:@"NSBackgroundColor"
		   inRecord:record as:@"backgroundColor" translated:&backgroundColorTranslated];
	number = [self fnNumberValue:[entry objectForKey:@"NSDrawsBackground"]];
	if (number != nil) {
		[record setObject:number forKey:@"drawsBackground"];
		drawsBackgroundTranslated = YES;
	}

	/* **THE SLIDER'S OWN NUMBERS.** `NSVertical` is deliberately not one of them: this tree derives the orientation
	 * from the frame (and says so at `-_vertical`), so the flag is a rendering fact rather than a property. */
	if ([appleClass isEqualToString:@"NSSliderCell"]) {
		/* AGORA KEY -> APPLE KEY, so the enumeration below reads as "for each key this tree knows". */
		NSDictionary *sliderKeys = [NSDictionary dictionaryWithObjectsAndKeys:
			@"NSMinValue", @"minValue",
			@"NSMaxValue", @"maxValue",
			@"NSValue", @"sliderValue",
			@"NSNumberOfTickMarks", @"numberOfTickMarks",
			@"NSTickMarkPosition", @"tickMarkPosition",
			@"NSAltIncValue", @"altIncrementValue",
			@"NSAllowsTickMarkValuesOnly", @"allowsTickMarkValuesOnly",
			@"NSKnobThickness", @"knobThickness",
			@"NSSliderType", @"sliderType",
			nil];
		NSEnumerator *e = [sliderKeys keyEnumerator];
		NSString *agnibKey;

		while ((agnibKey = [e nextObject]) != nil) {
			NSNumber *sliderNumber = [self fnNumberValue:
				[entry objectForKey:[sliderKeys objectForKey:agnibKey]]];

			if (sliderNumber != nil) {
				[record setObject:sliderNumber forKey:agnibKey];
			}
		}
	}

	/* **THE BUTTON'S SECOND FLAG WORD: the masks are GNUstep's `NSButtonCell -initWithCoder:` (same file), which
	 * composes bezelStyle from the low bits and the modifier mask from bits 8 and up.** */
	if ([appleClass isEqualToString:@"NSButtonCell"]) {
		number = [self fnNumberValue:[entry objectForKey:@"NSButtonFlags2"]];
		if (number != nil) {
			unsigned int f = [number unsignedIntValue];

			[record setObject:[NSNumber numberWithUnsignedInteger:((f & 0x7u) | ((f & 0x20u) >> 2))]
				   forKey:@"bezelStyle"];
			[record setObject:[NSNumber numberWithUnsignedInteger:((f >> 8) & 0xFFFF0000u)]
				   forKey:@"keyEquivalentModifierMask"];
		}
	}

	{
		NSMutableSet *consumed = [NSMutableSet setWithObjects:
			@"NSCellFlags", @"NSCellFlags2", @"NSContents", @"NSKeyEquivalent",
			@"NSAlternateContents", @"NSButtonFlags2", @"NSControlView",
			@"NSMenu", @"NSFormatter", nil];
		id support = [entry objectForKey:@"NSSupport"];
		NSUInteger supportIndex;

		if (support == nil ||
		    (fn_uid_index(support, &supportIndex) &&
		     [[self fnClassNameAt:supportIndex] isEqualToString:@"NSFont"])) {
			[consumed addObject:@"NSSupport"];
		}
		if ([appleClass isEqualToString:@"NSSliderCell"]) {
			[consumed addObjectsFromArray:[NSArray arrayWithObjects:
				@"NSMinValue", @"NSMaxValue", @"NSValue", @"NSNumberOfTickMarks",
				@"NSTickMarkPosition", @"NSAltIncValue", @"NSAllowsTickMarkValuesOnly",
				@"NSKnobThickness", @"NSSliderType", @"NSVertical", nil]];
		}
		if (textColorTranslated) {
			[consumed addObject:@"NSTextColor"];
		}
		if (backgroundColorTranslated) {
			[consumed addObject:@"NSBackgroundColor"];
		}
		if (drawsBackgroundTranslated) {
			[consumed addObject:@"NSDrawsBackground"];
		}
		[self fnNoteUnmappedForEntry:entry className:appleClass consumed:consumed];
	}
	return YES;
}

- (BOOL)fnBuildWindowTemplateRecordAtIndex:(NSUInteger)index record:(NSMutableDictionary *)record
{
	NSDictionary *entry = [_objects objectAtIndex:index];
	NSString *windowClass = [self fnStringValue:[entry objectForKey:@"NSWindowClass"]];
	Class cls;
	NSNumber *number;
	NSString *value;
	NSRect content = NSZeroRect;
	NSUInteger style = 0;
	NSSize size;
	NSUInteger subview;

	if (windowClass == nil) {
		windowClass = @"NSWindow";
	}
	cls = NSClassFromString(windowClass);
	if (cls == Nil) {
		return [self fnFail:[NSString stringWithFormat:
			@"it names the window class %@, which is not in this process", windowClass]];
	}
	if (![cls isSubclassOfClass:[NSWindow class]]) {
		return [self fnFail:[NSString stringWithFormat:@"%@ is not an NSWindow subclass", windowClass]];
	}
	if (![NSNib isSupportedClass:cls]) {
		return [self fnFail:[NSString stringWithFormat:
			@"the window class %@ is not on NSNib's allow-list; register it with +[NSNib registerDesignClass:]",
			windowClass]];
	}
	[record setObject:windowClass forKey:AGAppleClassKey];

	number = [self fnNumberValue:[entry objectForKey:@"NSWindowStyleMask"]];
	style = (number != nil) ? [number unsignedIntegerValue] : 0;
	value = [self fnStringValue:[entry objectForKey:@"NSWindowRect"]];
	if (value != nil) {
		content = NSRectFromString(value);
	}
	/* **APPLE STORES THE CONTENT RECT; THIS TREE'S "frame" IS THE WINDOW FRAME.** GNUstep's encoder makes the
	 * same conversion in the other direction through `+contentRectForFrameRect:styleMask:`. */
	[record setObject:[NSValue valueWithRect:[NSWindow frameRectForContentRect:content styleMask:style]]
		   forKey:@"frame"];
	[record setObject:[NSNumber numberWithUnsignedInteger:style] forKey:@"styleMask"];

	number = [self fnNumberValue:[entry objectForKey:@"NSWindowBacking"]];
	if (number != nil) {
		[record setObject:number forKey:@"backingType"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSWindowTitle"]]) != nil) {
		[record setObject:value forKey:@"title"];
	}
	/* THE FOUR SIZE KEYS: Apple's `NSMinSize`/`NSMaxSize` are FRAME sizes and its `…ContentMinSize` are CONTENT
	 * sizes, which is exactly this tree's split. */
	if ((value = [self fnStringValue:[entry objectForKey:@"NSMinSize"]]) != nil) {
		size = NSSizeFromString(value);
		[record setObject:[NSValue valueWithSize:size] forKey:@"minSize"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSMaxSize"]]) != nil) {
		size = NSSizeFromString(value);
		[record setObject:[NSValue valueWithSize:size] forKey:@"maxSize"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSWindowContentMinSize"]]) != nil) {
		size = NSSizeFromString(value);
		[record setObject:[NSValue valueWithSize:size] forKey:@"contentMinSize"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSWindowContentMaxSize"]]) != nil) {
		size = NSSizeFromString(value);
		[record setObject:[NSValue valueWithSize:size] forKey:@"contentMaxSize"];
	}
	if ((value = [self fnStringValue:[entry objectForKey:@"NSFrameAutosaveName"]]) != nil) {
		[record setObject:value forKey:@"frameAutosaveName"];
	}
	if ([entry objectForKey:@"NSWindowView"] != nil) {
		if (!fn_uid_index([entry objectForKey:@"NSWindowView"], &subview)) {
			return [self fnFail:@"the window template's NSWindowView is not an object"];
		}
		[record setObject:[AGAppleNibRef refWithIndex:subview] forKey:@"contentView"];
	}
	if ([entry objectForKey:@"NSToolbar"] != nil) {
		return [self fnFail:@"the window template carries a toolbar, which this translator does not map yet"];
	}

	[self fnNoteUnmappedForEntry:entry className:@"NSWindowTemplate"
			    consumed:[NSSet setWithObjects:
				@"NSWindowClass", @"NSWindowStyleMask", @"NSWindowRect", @"NSWindowBacking",
				@"NSWindowTitle", @"NSMinSize", @"NSMaxSize", @"NSWindowContentMinSize",
				@"NSWindowContentMaxSize", @"NSFrameAutosaveName", @"NSWindowView", @"NSToolbar",
				nil]];
	return YES;
}

- (BOOL)fnBuildCustomObjectRecordAtIndex:(NSUInteger)index
{
	NSDictionary *entry = [_objects objectAtIndex:index];
	NSString *name = [self fnStringValue:[entry objectForKey:@"NSClassName"]];
	Class cls;
	NSMutableDictionary *record;

	if (index == _rootIndex) {
		/* THE FILE'S OWNER IS NOT AN OBJECT THE NIB OWNS: it is the caller's, substituted by `NSNib`. */
		return YES;
	}
	if (name == nil) {
		return [self fnFail:[NSString stringWithFormat:@"the custom object at index %lu names no class",
			(unsigned long)index]];
	}
	/* **THE TWO PROXIES APPLE ARCHIVES WITHOUT A CLASS OF ITS OWN.** Neither is instantiated; a reference to one
	 * is refused by name by the calibration, because this tree has no equivalent proxy. */
	if ([name isEqualToString:@"NSApplication"] || [name isEqualToString:@"FirstResponder"]) {
		[_proxies addObject:[NSNumber numberWithUnsignedInteger:index]];
		[self fnNoteUnmappedForEntry:entry className:name
				    consumed:[NSSet setWithObject:@"NSClassName"]];
		return YES;
	}
	cls = NSClassFromString(name);
	if (cls == Nil) {
		return [self fnFail:[NSString stringWithFormat:
			@"it names the custom object class %@, which is not in this process", name]];
	}
	if (![NSNib isSupportedClass:cls]) {
		return [self fnFail:[NSString stringWithFormat:
			@"the custom object class %@ is not on NSNib's allow-list; register it with "
			@"+[NSNib registerDesignClass:]", name]];
	}
	record = [NSMutableDictionary dictionary];
	[record setObject:name forKey:AGAppleClassKey];
	[_records setObject:record forKey:[NSNumber numberWithUnsignedInteger:index]];
	[self fnNoteUnmappedForEntry:entry className:name
			    consumed:[NSSet setWithObject:@"NSClassName"]];
	return YES;
}

- (BOOL)buildRecords
{
	id objectsValue;
	id topValue;
	id rootValue;
	id rootData;
	NSString *rootClassName;
	NSUInteger rootDataIndex;
	NSUInteger i;

	if (![_plist isKindOfClass:[NSDictionary class]]) {
		return [self fnFail:@"its root is not a property list dictionary"];
	}
	objectsValue = [(NSDictionary *)_plist objectForKey:@"$objects"];
	topValue = [(NSDictionary *)_plist objectForKey:@"$top"];
	if (![objectsValue isKindOfClass:[NSArray class]]) {
		return [self fnFail:@"it has no $objects table"];
	}
	if (![topValue isKindOfClass:[NSDictionary class]]) {
		return [self fnFail:@"it has no $top dictionary"];
	}
	_objects = [(NSArray *)objectsValue retain];
	if (!fn_uid_index([(NSDictionary *)topValue objectForKey:AGAppleObjectDataKey], &rootDataIndex) ||
	    rootDataIndex >= [_objects count]) {
		return [self fnFail:@"its $top does not name an IB.objectdata object"];
	}
	rootData = [_objects objectAtIndex:rootDataIndex];
	rootClassName = [self fnClassNameAt:rootDataIndex];
	if (![rootData isKindOfClass:[NSDictionary class]] ||
	    ![rootClassName isEqualToString:AGAppleObjectDataClassName]) {
		return [self fnFail:@"its IB.objectdata object is not an NSIBObjectData"];
	}
	_objectDataIndex = rootDataIndex;
	if (!fn_uid_index([(NSDictionary *)rootData objectForKey:@"NSRoot"], &_rootIndex) ||
	    _rootIndex >= [_objects count]) {
		return [self fnFail:@"its IBObjectData has no NSRoot"];
	}

	/* WALK THE WHOLE TABLE. Class entries and value/collection leaves are skipped; every structural object is
	 * either translated into a record, or named in a refusal. */
	for (i = 0; i < [_objects count]; i++) {
		id entry = [_objects objectAtIndex:i];
		NSString *name;
		NSMutableDictionary *record;

		if (![entry isKindOfClass:[NSDictionary class]] ||
		    [(NSDictionary *)entry objectForKey:@"$classname"] != nil) {
			continue;
		}
		if ([(NSDictionary *)entry objectForKey:@"$class"] == nil) {
			continue;
		}
		name = [self fnClassNameAt:i];
		if (name == nil) {
			continue;
		}
		record = [NSMutableDictionary dictionary];
		if ([name isEqualToString:AGAppleObjectDataClassName]) {
			continue;
		}
		if ([name hasSuffix:@"Connector"]) {
			[_connectorIndexes addObject:[NSNumber numberWithUnsignedInteger:i]];
			continue;
		}
		if ([name isEqualToString:@"NSFont"]) {
			if (![self fnBuildFontRecordAtIndex:i record:record]) {
				return NO;
			}
			[_records setObject:record forKey:[NSNumber numberWithUnsignedInteger:i]];
			continue;
		}
		if ([name isEqualToString:@"NSColor"]) {
			if (![self fnBuildColorRecordAtIndex:i record:record]) {
				return NO;
			}
			[_records setObject:record forKey:[NSNumber numberWithUnsignedInteger:i]];
			continue;
		}
		if (fn_is_auxiliary_class(name)) {
			continue;
		}
		if ([name isEqualToString:@"NSCustomObject"]) {
			if (![self fnBuildCustomObjectRecordAtIndex:i]) {
				return NO;
			}
			continue;
		}
		if ([name isEqualToString:@"NSWindowTemplate"]) {
			if (![self fnBuildWindowTemplateRecordAtIndex:i record:record]) {
				return NO;
			}
		} else if (fn_is_translated_view_class(name)) {
			if (![self fnBuildViewRecordAtIndex:i appleClass:name record:record]) {
				return NO;
			}
		} else if (fn_is_translated_cell_class(name)) {
			if (![self fnBuildCellRecordAtIndex:i appleClass:name record:record]) {
				return NO;
			}
		} else {
			return [self fnFail:[NSString stringWithFormat:
				@"it names %@, which this translator does not map", name]];
		}
		if ([record objectForKey:AGAppleClassKey] != nil) {
			[_records setObject:record forKey:[NSNumber numberWithUnsignedInteger:i]];
		}
	}

	if (![self fnCalibrateRecords]) {
		return NO;
	}
	if (![self fnBuildTopLevel]) {
		return NO;
	}
	return [self fnValidateConnections];
}

/* ---- the calibration ------------------------------------------------------------------------ */

- (BOOL)fnCalibrateValue:(id)value className:(NSString *)className key:(NSString *)key
{
	if ([value isKindOfClass:[AGAppleNibRef class]]) {
		NSUInteger index = [(AGAppleNibRef *)value index];

		if (index == _rootIndex) {
			return [self fnFail:[NSString stringWithFormat:
				@"%@'s %@ names the file's owner, which is only a connection endpoint",
				className, key]];
		}
		if ([_records objectForKey:[NSNumber numberWithUnsignedInteger:index]] == nil) {
			NSString *targetClass = [self fnClassNameAt:index];

			return [self fnFail:[NSString stringWithFormat:
				@"%@'s %@ names %@, which this translator does not map",
				className, key, (targetClass != nil) ? targetClass : @"an object"]];
		}
		return YES;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		NSUInteger i;

		for (i = 0; i < [(NSArray *)value count]; i++) {
			if (![self fnCalibrateValue:[(NSArray *)value objectAtIndex:i]
					  className:className key:key]) {
				return NO;
			}
		}
	}
	return YES;
}

- (BOOL)fnCalibrateRecords
{
	NSEnumerator *e = [_records keyEnumerator];
	NSNumber *index;
	NSDictionary *record;

	while ((index = [e nextObject]) != nil) {
		NSString *className;
		NSEnumerator *keys;
		NSString *key;

		record = [_records objectForKey:index];
		className = [record objectForKey:AGAppleClassKey];
		keys = [[record allKeys] objectEnumerator];
		while ((key = [keys nextObject]) != nil) {
			if ([key isEqualToString:AGAppleClassKey]) {
				continue;
			}
			if (![self fnCalibrateValue:[record objectForKey:key] className:className key:key]) {
				return NO;
			}
		}
	}
	return YES;
}

- (BOOL)fnBuildTopLevel
{
	NSDictionary *rootData;
	NSArray *keys;
	NSArray *owners;
	NSUInteger i;

	rootData = [_objects objectAtIndex:_objectDataIndex];
	keys = [self fnArrayValue:[rootData objectForKey:@"NSObjectsKeys"]];
	owners = [self fnArrayValue:[rootData objectForKey:@"NSObjectsValues"]];
	if (keys == nil || owners == nil || [keys count] != [owners count]) {
		return [self fnFail:@"its NSObjectsKeys and NSObjectsValues are not parallel arrays"];
	}
	for (i = 0; i < [keys count]; i++) {
		NSUInteger keyIndex;
		NSUInteger ownerIndex;

		if (!fn_uid_index([keys objectAtIndex:i], &keyIndex) ||
		    !fn_uid_index([owners objectAtIndex:i], &ownerIndex)) {
			return [self fnFail:@"its object map holds an entry that is not an object reference"];
		}
		if (keyIndex == _rootIndex || ownerIndex != _rootIndex) {
			continue;
		}
		if ([_proxies containsObject:[NSNumber numberWithUnsignedInteger:keyIndex]]) {
			continue;		/* the NSApplication/FirstResponder proxy is not an object to own */
		}
		if ([_records objectForKey:[NSNumber numberWithUnsignedInteger:keyIndex]] == nil) {
			continue;		/* an auxiliary leaf owned by the root is not a top-level object */
		}
		[_topLevelRefs addObject:[AGAppleNibRef refWithIndex:keyIndex]];
	}
	if ([_topLevelRefs count] == 0) {
		return [self fnFail:@"it owns no top-level object this translator can build"];
	}
	return YES;
}

/* ---- the connections ------------------------------------------------------------------------ */

- (BOOL)fnValidateConnectionEndpoint:(id)value what:(NSString *)what
{
	NSUInteger index;
	NSString *name;

	if (!fn_uid_index(value, &index)) {
		return [self fnFail:[NSString stringWithFormat:@"a connection's %@ is not an object reference", what]];
	}
	if (index == _rootIndex) {
		return YES;
	}
	if ([_proxies containsObject:[NSNumber numberWithUnsignedInteger:index]]) {
		name = [self fnClassNameAt:index];
		return [self fnFail:[NSString stringWithFormat:
			@"a connection's %@ names the %@ proxy, which this translator does not expose",
			what, (name != nil) ? name : @"Interface Builder"]];
	}
	if ([_records objectForKey:[NSNumber numberWithUnsignedInteger:index]] == nil) {
		name = [self fnClassNameAt:index];
		return [self fnFail:[NSString stringWithFormat:
			@"a connection's %@ names %@, which this translator does not map",
			what, (name != nil) ? name : @"an object"]];
	}
	return YES;
}

- (BOOL)fnValidateConnections
{
	NSUInteger i;

	for (i = 0; i < [_connectorIndexes count]; i++) {
		NSUInteger connectorIndex = [[_connectorIndexes objectAtIndex:i] unsignedIntegerValue];
		NSDictionary *entry = [_objects objectAtIndex:connectorIndex];
		NSString *name = [self fnClassNameAt:connectorIndex];
		NSString *label = [self fnStringValue:[entry objectForKey:@"NSLabel"]];

		if (![name isEqualToString:@"NSNibOutletConnector"] &&
		    ![name isEqualToString:@"NSNibControlConnector"]) {
			return [self fnFail:[NSString stringWithFormat:
				@"it carries an %@, which this translator does not map", name]];
		}
		if (label == nil) {
			return [self fnFail:[NSString stringWithFormat:@"an %@ has no label", name]];
		}
		if (![self fnValidateConnectionEndpoint:[entry objectForKey:@"NSSource"] what:@"source"] ||
		    ![self fnValidateConnectionEndpoint:[entry objectForKey:@"NSDestination"] what:@"destination"]) {
			return NO;
		}
	}
	return YES;
}

/* ---- the build ------------------------------------------------------------------------------ */

- (id)fnConnectionEndpoint:(id)value
{
	NSUInteger index;

	if (!fn_uid_index(value, &index)) {
		return [self fnFailValue:@"a connection's endpoint is not an object reference"];
	}
	if (index == _rootIndex) {
		return NSNibFileOwner;
	}
	return [self fnDecodeObjectAtIndex:index];
}

- (BOOL)fnBuildConnections:(NSMutableArray *)connections
{
	NSUInteger i;

	for (i = 0; i < [_connectorIndexes count]; i++) {
		NSUInteger connectorIndex = [[_connectorIndexes objectAtIndex:i] unsignedIntegerValue];
		NSDictionary *entry = [_objects objectAtIndex:connectorIndex];
		NSString *name = [self fnClassNameAt:connectorIndex];
		NSString *label = [self fnStringValue:[entry objectForKey:@"NSLabel"]];
		id source = [self fnConnectionEndpoint:[entry objectForKey:@"NSSource"]];
		id destination = [self fnConnectionEndpoint:[entry objectForKey:@"NSDestination"]];
		NSDictionary *record;

		if (source == nil || destination == nil) {
			return NO;
		}
		if ([name isEqualToString:@"NSNibOutletConnector"]) {
			record = [NSNib outletConnectionFrom:source to:destination keyPath:label];
		} else {
			record = [NSNib actionConnectionFrom:source to:destination action:label];
		}
		[connections addObject:record];
	}
	return YES;
}

- (BOOL)instantiateTopLevelObjects:(NSArray **)outObjects connections:(NSArray **)outConnections
{
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[_topLevelRefs count]];
	NSMutableArray *connections = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [_topLevelRefs count]; i++) {
		id object = [self fnDecodeObjectAtIndex:[[_topLevelRefs objectAtIndex:i] index]];

		if (object == nil) {
			return NO;
		}
		[objects addObject:object];
	}
	if (![self fnBuildConnections:connections]) {
		return NO;
	}
	if (outObjects != NULL) {
		*outObjects = objects;
	}
	if (outConnections != NULL) {
		*outConnections = connections;
	}
	return YES;
}

- (id)fnDecodedValue:(id)value
{
	if (value == nil) {
		return nil;
	}
	if ([value isKindOfClass:[AGAppleNibRef class]]) {
		return [self fnDecodeObjectAtIndex:[(AGAppleNibRef *)value index]];
	}
	if ([value isKindOfClass:[NSArray class]]) {
		NSMutableArray *array = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
		NSUInteger i;

		for (i = 0; i < [(NSArray *)value count]; i++) {
			id item = [self fnDecodedValue:[(NSArray *)value objectAtIndex:i]];

			if (item == nil) {
				return nil;
			}
			[array addObject:item];
		}
		return array;
	}
	return value;
}

- (id)fnDecodeObjectAtIndex:(NSUInteger)index
{
	NSNumber *key = [NSNumber numberWithUnsignedInteger:index];
	NSDictionary *record;
	NSString *className;
	Class cls;
	AGAppleNibCoder *coder;
	id object = nil;

	object = [_built objectForKey:key];
	if (object != nil) {
		return object;
	}
	record = [_records objectForKey:key];
	if (record == nil) {
		NSString *name = [self fnClassNameAt:index];

		return [self fnFailValue:[NSString stringWithFormat:
			@"the archive names %@, which this translator does not map",
			(name != nil) ? name : @"an object"]];
	}
	if ([_building containsObject:key]) {
		return [self fnFailValue:[NSString stringWithFormat:
			@"%@ refers to itself while it is being built", [record objectForKey:AGAppleClassKey]]];
	}
	className = [record objectForKey:AGAppleClassKey];
	cls = NSClassFromString(className);
	if (cls == Nil) {
		return [self fnFailValue:[NSString stringWithFormat:@"the class %@ is not in this process", className]];
	}
	coder = [[AGAppleNibCoder alloc] initWithImporter:self record:record];
	[_building addObject:key];
	@try {
		object = [[cls alloc] initWithCoder:coder];
	} @catch (NSException *exception) {
		[self fnFail:[NSString stringWithFormat:@"%@ refused its translated keys: %@",
			className, [exception reason]]];
		object = nil;
	}
	[_building removeObject:key];
	[coder release];
	if (object == nil) {
		return nil;
	}
	[_built setObject:object forKey:key];
	[object release];		/* _built owns it now */
	return object;
}

@end

/* ==================================================================================================
 * THE PUBLIC DOOR
 * ================================================================================================ */

@implementation AGAppleNib

+ (BOOL)isAppleNibArchive:(id)plist
{
	id top;
	id objects;
	NSUInteger index;

	if (![plist isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	top = [(NSDictionary *)plist objectForKey:@"$top"];
	objects = [(NSDictionary *)plist objectForKey:@"$objects"];
	if (![top isKindOfClass:[NSDictionary class]] || ![objects isKindOfClass:[NSArray class]]) {
		return NO;
	}
	return fn_uid_index([(NSDictionary *)top objectForKey:AGAppleObjectDataKey], &index);
}

+ (BOOL)validateAppleNibArchive:(id)plist reason:(NSString **)reason
{
	AGAppleNibImporter *importer = [[AGAppleNibImporter alloc] initWithArchive:plist];
	BOOL valid = [importer buildRecords];

	if (!valid && reason != NULL) {
		*reason = [[[importer reason] copy] autorelease];
	}
	[importer release];
	return valid;
}

+ (BOOL)instantiateAppleNibArchive:(id)plist
		   topLevelObjects:(NSArray **)topLevelObjects
		       connections:(NSArray **)connections
			    reason:(NSString **)reason
{
	AGAppleNibImporter *importer = [[AGAppleNibImporter alloc] initWithArchive:plist];
	BOOL valid;

	valid = [importer buildRecords] &&
		[importer instantiateTopLevelObjects:topLevelObjects connections:connections];
	if (!valid && reason != NULL) {
		*reason = [[[importer reason] copy] autorelease];
	}
	[importer release];
	return valid;
}

+ (NSArray *)unmappedKeysForAppleNibArchive:(id)plist
{
	AGAppleNibImporter *importer = [[AGAppleNibImporter alloc] initWithArchive:plist];
	NSArray *keys;

	[importer buildRecords];
	keys = [[importer unmappedKeys] sortedArrayUsingSelector:@selector(compare:)];
	[importer release];
	return keys;
}

@end
