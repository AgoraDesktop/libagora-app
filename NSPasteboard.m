/*
 * NSPasteboard — the pasteboard's types and the store behind them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * THE STORE IS TWO CONTAINERS AND A COUNTER, and the counter is the part with a contract: Apple's
 * `-changeCount` is how a client knows whether the pasteboard moved under it, so EVERY mutation advances it
 * — clearing, declaring, adding and writing all do — and no mutation leaves it still. A pasteboard whose
 * count stood still would have a client painting stale contents from a cache it believed was fresh, and
 * that is the one failure mode this class has.
 *
 * AND THE LAST WRITER WINS, WHICH IS APPLE'S RULE TOO: `-setData:forType:` replaces what was there for that
 * type rather than accumulating, because a pasteboard holds ONE value per type. `-declareTypes:owner:`
 * clears everything first, which is why it is a declare-and-clear rather than an append — `-addTypes:owner:`
 * is the append.
 *
 * THE OWNER IS A WEAK REFERENCE AND `-releaseGlobally` IS A NO-OP ON A SHARED BOARD, both on purpose: the
 * owner is a view or a controller that outlives the declaration, and a shared pasteboard is shared, so an
 * instance releasing itself out from under another client would be the bug, not the feature.
 *
 * THE MRC OWNERSHIP IS THREE RETAINED FIELDS (`_name`, `_types`, `_data`) that `-dealloc` releases, except
 * for the five shared boards, which are never released at all — the one immortal kind of object in this
 * file, which is what "shared" means.
 */
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSPropertyListSerialization.h>
#import <Foundation/NSFileWrapper.h>
#import <Foundation/NSKeyedArchiver.h>

#include <stdio.h>

NSString *NSGeneralPboard = @"NSGeneralPboard";
NSString *NSFontPboard = @"NSFontPboard";
NSString *NSRulerPboard = @"NSRulerPboard";
NSString *NSFindPboard = @"NSFindPboard";
NSString *NSDragPboard = @"NSDragPboard";

NSString *NSStringPboardType = @"NSStringPboardType";
NSString *NSFilenamesPboardType = @"NSFilenamesPboardType";
NSString *NSTIFFPboardType = @"NSTIFFPboardType";
NSString *NSRTFPboardType = @"NSRTFPboardType";
NSString *NSRTFDPboardType = @"NSRTFDPboardType";
NSString *NSHTMLPboardType = @"NSHTMLPboardType";
NSString *NSPDFPboardType = @"NSPDFPboardType";
NSString *NSPostScriptPboardType = @"NSPostScriptPboardType";
NSString *NSTabularTextPboardType = @"NSTabularTextPboardType";
NSString *NSFontPboardType = @"NSFontPboardType";
NSString *NSRulerPboardType = @"NSRulerPboardType";
NSString *NSColorPboardType = @"NSColorPboardType";
NSString *NSSoundPboardType = @"NSSoundPboardType";
NSString *NSFileContentsPboardType = @"NSFileContentsPboardType";
NSString *NSMultipleTextSelectionPboardType = @"NSMultipleTextSelectionPboardType";
NSString *NSFindPanelSearchOptionsPboardType = @"NSFindPanelSearchOptionsPboardType";
NSString *NSVCardPboardType = @"NSVCardPboardType";
NSString *NSInkTextPboardType = @"NSInkTextPboardType";

/* THE MODERN TYPE NAMES AND THEIR VALUES, TRANSCRIBED FROM APPLE'S OWN DOCUMENTATION — the one place this
 * tier transcribes a value it did not invent, because a UTI is an external identifier rather than a name
 * Apple chose for a symbol. See the header for why the legacy block above carries its own names instead. */
NSString *NSPasteboardTypeString = @"public.utf8-plain-text";
NSString *NSPasteboardTypePDF = @"com.adobe.pdf";
NSString *NSPasteboardTypeTIFF = @"public.tiff";
NSString *NSPasteboardTypePNG = @"public.png";
NSString *NSPasteboardTypeRTF = @"public.rtf";
NSString *NSPasteboardTypeRTFD = @"com.apple.flat-rtfd";
NSString *NSPasteboardTypeHTML = @"public.html";
NSString *NSPasteboardTypeTabularText = @"public.utf8-tab-separated-values-text";
NSString *NSPasteboardTypeFont = @"com.apple.cocoa.pasteboard.character-formatting";
NSString *NSPasteboardTypeColor = @"com.apple.cocoa.pasteboard.color";
NSString *NSPasteboardTypeSound = @"com.apple.cocoa.pasteboard.sound";

/* ---- THE NINE THAT SHIPPED ON UNEQUAL SUPPORT, AND EACH LINE CARRIES ITS SOURCE --------------- *
 * See the header for why this block exists at all: the era ground declares all nine and values none, and
 * the user's decision (2026-10-08) was to ship them rather than leave them owed. THE COMMENT ON EACH LINE IS
 * THE EVIDENCE, because a pasteboard type that matches nothing fails SILENTLY — a later reader must be able
 * to see which of these is a quotation and which is a convention. appkit-plan.md §A10j has the searches. */
NSString *NSFilesPromisePboardType = @"Apple files promise pasteboard type";	/* Apple's archived docs */
NSString *NSURLPboardType = @"Apple URL pasteboard type";			/* Apple's archived docs */
NSString *NSPICTPboardType = @"Apple PICT pasteboard type";			/* Apple's archived docs */
NSString *NSPasteboardTypeRuler = @"com.apple.cocoa.pasteboard.paragraph-formatting";
NSString *NSPasteboardTypeMultipleTextSelection = @"com.apple.cocoa.pasteboard.multiple-text-selection";
NSString *NSPasteboardTypeFindPanelSearchOptions = @"com.apple.cocoa.pasteboard.find-panel-search-options";
/* AND THE FOUR WITH NO LITERAL ANY SOURCE THIS TREE COULD REACH PRINTS — UNVERIFIED, AND SAID SO HERE. */
NSString *NSFindPanelCaseInsensitiveSearch = @"CaseInsensitiveSearch";
NSString *NSFindPanelSubstringMatch = @"SubstringMatch";
NSString *NSPasteboardURLReadingFileURLsOnlyKey = @"NSPasteboardURLReadingFileURLsOnlyKey";
NSString *NSPasteboardURLReadingContentsConformToTypesKey = @"NSPasteboardURLReadingContentsConformToTypesKey";

/* THE BOARDS, BY NAME. A name maps to ONE board for the life of the process, which is what makes
 * `+pasteboardWithName:` a lookup rather than a construction. */
static NSMutableDictionary *s_boards;
static unsigned s_uniqueSerial;

/* THE TWO PRIVATE DOORS, IN A CLASS EXTENSION RATHER THAN THE PUBLIC HEADER: a board is created through
 * one of them and a caller has no business naming either. */
@interface NSPasteboard ()
+ (NSPasteboard *)cg_boardNamed:(NSString *)name;
- (instancetype)cg_initWithName:(NSString *)name;
@end

/* THE INFORMAL CONTRACT, DECLARED AS A CATEGORY ON NSObject — WHICH IS APPLE'S OWN IDIOM HERE, not a
 * shortcut: its pasteboard header spells the older informal protocol exactly this way, as
 * `@interface NSObject(NSPasteboardOwner)`. Declaring the reading and writing messages the same way is
 * what makes the calls below known to the compiler rather than guessed at, so a caller's class works the
 * moment it implements them, and a method this file misspelled is a warning instead of a silent no-op. */
@interface NSObject (APPKITPasteboardCoding)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard;
- (NSPasteboardWritingOptions)writingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard;
- (id)pasteboardPropertyListForType:(NSString *)type;
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard;
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSString *)type pasteboard:(NSPasteboard *)pasteboard;
- (id)initWithPasteboardPropertyList:(id)propertyList ofType:(NSString *)type;
@end

@implementation NSPasteboard

+ (NSPasteboard *)cg_boardNamed:(NSString *)name
{
	NSPasteboard *board;

	if (s_boards == nil) {
		s_boards = [[NSMutableDictionary alloc] init];
	}
	board = [s_boards objectForKey:name];
	if (board == nil) {
		board = [[NSPasteboard alloc] cg_initWithName:name];
		[s_boards setObject:board forKey:name];
	}
	return board;
}

+ (NSPasteboard *)generalPasteboard
{
	return [self cg_boardNamed:NSGeneralPboard];
}

+ (NSPasteboard *)pasteboardWithName:(NSString *)name
{
	if (name == nil) {
		return nil;
	}
	return [self cg_boardNamed:name];
}

+ (NSPasteboard *)pasteboardWithUniqueName
{
	return [self cg_boardNamed:[NSString stringWithFormat:@"NSUniquePboard%u", s_uniqueSerial++]];
}

- (instancetype)cg_initWithName:(NSString *)name
{
	if ((self = [super init]) != nil) {
		_name = [name copy];
		_types = [[NSMutableArray alloc] init];
		_data = [[NSMutableDictionary alloc] init];
		_changeCount = 0;
		_owner = nil;
	}
	return self;
}

- (instancetype)init
{
	return [self cg_initWithName:[NSString stringWithFormat:@"NSUniquePboard%u", s_uniqueSerial++]];
}

- (void)dealloc
{
	[_name release];
	[_types release];
	[_data release];
	[super dealloc];
}

- (NSString *)name
{
	return _name;
}

- (void)releaseGlobally
{
	/* A SHARED BOARD IS SHARED: another client may be holding the same object, so this cannot free it. The
	 * five named boards live as long as the process, which is the same lifetime Apple's have. */
}

- (NSInteger)changeCount
{
	return _changeCount;
}

- (NSInteger)clearContents
{
	[_types removeAllObjects];
	[_data removeAllObjects];
	_owner = nil;
	return ++_changeCount;
}

- (NSInteger)declareTypes:(NSArray *)newTypes owner:(id)newOwner
{
	/* DECLARE REPLACES: the contents are cleared first, because the types a pasteboard holds and the
	 * contents it holds have to be the same generation. */
	[self clearContents];
	return [self addTypes:newTypes owner:newOwner];
}

- (NSInteger)addTypes:(NSArray *)newTypes owner:(id)newOwner
{
	NSUInteger i;

	if (newOwner != nil) {
		_owner = newOwner;
	}
	for (i = 0; i < [newTypes count]; i++) {
		NSString *t = [newTypes objectAtIndex:i];

		if (t != nil && ![_types containsObject:t]) {
			[_types addObject:t];
		}
	}
	return ++_changeCount;
}

- (NSArray *)types
{
	/* A COPY, so that a client holding the answer is not holding the pasteboard's own array. */
	return [[_types copy] autorelease];
}

- (NSString *)availableTypeFromArray:(NSArray *)candidates
{
	NSUInteger i;

	for (i = 0; i < [candidates count]; i++) {
		NSString *t = [candidates objectAtIndex:i];

		if (t != nil && [_types containsObject:t]) {
			return t;
		}
	}
	return nil;
}

/* THE TYPE IS DECLARED BY WRITING IT if it was not declared before, which is Apple's convenience and the
 * reason `-setString:forType:` works on a fresh board. */
- (BOOL)setData:(NSData *)data forType:(NSString *)dataType
{
	if (dataType == nil || data == nil) {
		return NO;
	}
	if (![_types containsObject:dataType]) {
		[self addTypes:[NSArray arrayWithObject:dataType] owner:_owner];
	}
	[_data setObject:data forKey:dataType];
	_changeCount++;
	return YES;
}

- (NSData *)dataForType:(NSString *)dataType
{
	return (dataType == nil) ? nil : [_data objectForKey:dataType];
}

- (BOOL)setString:(NSString *)string forType:(NSString *)dataType
{
	NSData *d;

	if (string == nil) {
		return NO;
	}
	d = [string dataUsingEncoding:NSUTF8StringEncoding];
	if (d == nil) {
		return NO;
	}
	return [self setData:d forType:dataType];
}

/* THE PROPERTY-LIST PAIR, ON THE FOUNDATION'S OWN SERIALISER rather than a second one written here: a
 * pasteboard's plist types (colour, font, ruler, the find panel's options) are exactly what
 * NSPropertyListSerialization writes and reads, and this tree already has it. A caller handing over
 * something the format cannot hold gets NO, which is the honest answer and the one Apple's BOOL return
 * carries. */
- (BOOL)setPropertyList:(id)plist forType:(NSString *)dataType
{
	NSData *d;

	if (plist == nil || dataType == nil) {
		return NO;
	}
	d = [NSPropertyListSerialization dataFromPropertyList:plist
						       format:NSPropertyListXMLFormat_v1_0
					     errorDescription:NULL];
	if (d == nil) {
		return NO;
	}
	return [self setData:d forType:dataType];
}

- (id)propertyListForType:(NSString *)dataType
{
	NSData *d = [self dataForType:dataType];

	if (d == nil) {
		return nil;
	}
	return [NSPropertyListSerialization propertyListFromData:d
					       mutabilityOption:NSPropertyListImmutable
							 format:NULL
					       errorDescription:NULL];
}

- (NSString *)stringForType:(NSString *)dataType
{
	NSData *d = [self dataForType:dataType];

	if (d == nil) {
		return nil;
	}
	/* A STRING THAT IS NOT UTF-8 IS NOT A STRING, and answering nil is the honest half of that: the bytes
	 * are still in `-dataForType:` for a caller that knows what they are. */
	return [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
}

/* ============================================================================================ *
 * THE ERA'S REMAINING DOORS.                                                                     *
 * ============================================================================================ */

/* ONE MESSAGE, TWO PROTOCOLS, SENT ONLY IF IT IS ANSWERED. Apple's contract for the object doors is
 * `NSPasteboardWriting` and `NSPasteboardReading`; reaching them through `-respondsToSelector:` is that
 * same contract without declaring protocols nothing in this tree conforms to yet, and it makes the doors
 * work for a caller's class the moment it implements the two methods. */
static BOOL fn_answers(id obj, SEL sel)
{
	return obj != nil && [obj respondsToSelector:sel];
}

- (BOOL)writeObjects:(NSArray *)objects
{
	NSMutableArray *all;
	NSUInteger i, j;

	if (objects == nil || [objects count] == 0) {
		return NO;
	}
	/* THE TYPES FIRST, AS A UNION IN ORDER: the board's type list is what a reader consults, and it has to
	 * be complete before any value is written — `-declareTypes:owner:` CLEARS, so writing as we go would
	 * drop the earlier objects' types. */
	all = [NSMutableArray array];
	for (i = 0; i < [objects count]; i++) {
		id o = [objects objectAtIndex:i];
		NSArray *t;

		if (!fn_answers(o, @selector(writableTypesForPasteboard:))) {
			continue;
		}
		t = [o writableTypesForPasteboard:self];
		for (j = 0; j < [t count]; j++) {
			NSString *ty = [t objectAtIndex:j];

			if (ty != nil && ![all containsObject:ty]) {
				[all addObject:ty];
			}
		}
	}
	if ([all count] == 0) {
		fprintf(stderr, "APPKIT-REFUSE: -writeObjects: found no object answering "
				"-writableTypesForPasteboard:, so there is nothing to write — that method is the "
				"contract this door sends\n");
		return NO;
	}
	[self declareTypes:all owner:nil];
	for (i = 0; i < [objects count]; i++) {
		id o = [objects objectAtIndex:i];
		NSArray *t;

		if (!fn_answers(o, @selector(writableTypesForPasteboard:))) {
			continue;
		}
		t = [o writableTypesForPasteboard:self];
		for (j = 0; j < [t count]; j++) {
			NSString *ty = [t objectAtIndex:j];
			id plist;

			if (ty == nil || !fn_answers(o, @selector(pasteboardPropertyListForType:))) {
				continue;
			}
			plist = [o pasteboardPropertyListForType:ty];
			if (plist == nil) {
				continue;
			}
			/* A CALLER MAY HAND BACK EITHER, which is Apple's own sentence: data goes on as data, and any
			 * property-list object is serialized on the way in. */
			if ([plist isKindOfClass:[NSData class]]) {
				[self setData:plist forType:ty];
			} else {
				[self setPropertyList:plist forType:ty];
			}
		}
	}
	return YES;
}

- (BOOL)canReadObjectForClasses:(NSArray *)classArray options:(NSDictionary *)options
{
	NSUInteger i, j;

	(void)options;
	if (classArray == nil) {
		return NO;
	}
	/* NO OBJECT IS CONSTRUCTED HERE — the question is "could one be", and building one to find out would
	 * make an answer into a side effect. */
	for (i = 0; i < [classArray count]; i++) {
		Class cls = (Class)[classArray objectAtIndex:i];
		NSArray *want;

		if (!fn_answers((id)cls, @selector(readableTypesForPasteboard:))) {
			continue;
		}
		want = [(id)cls readableTypesForPasteboard:self];
		for (j = 0; j < [want count]; j++) {
			if ([self availableTypeFromArray:[NSArray arrayWithObject:[want objectAtIndex:j]]] != nil) {
				return YES;
			}
		}
	}
	return NO;
}

- (NSArray *)readObjectsForClasses:(NSArray *)classArray options:(NSDictionary *)options
{
	NSMutableArray *out;
	NSUInteger i, j;

	(void)options;
	if (classArray == nil) {
		return nil;
	}
	out = [NSMutableArray array];
	for (i = 0; i < [classArray count]; i++) {
		Class cls = (Class)[classArray objectAtIndex:i];
		NSArray *want;

		if (!fn_answers((id)cls, @selector(readableTypesForPasteboard:))) {
			continue;
		}
		want = [(id)cls readableTypesForPasteboard:self];
		for (j = 0; j < [want count]; j++) {
			NSString *ty = [want objectAtIndex:j];
			NSPasteboardReadingOptions opt = NSPasteboardReadingAsData;
			id payload = nil;
			id obj = nil;

			if (ty == nil || [self availableTypeFromArray:[NSArray arrayWithObject:ty]] == nil) {
				continue;
			}
			if (fn_answers((id)cls, @selector(readingOptionsForType:pasteboard:))) {
				opt = [(id)cls readingOptionsForType:ty pasteboard:self];
			}
			/* THE FOUR OPTIONS ARE THE FOUR SHAPES THE CLASS ASKED FOR, and none is inferred from what
			 * happens to be on the board: AsData, AsString and AsPropertyList differ only in what is
			 * handed over, and AsKeyedArchive runs the unarchiver. */
			switch (opt) {
			case NSPasteboardReadingAsString:
				payload = [self stringForType:ty];
				break;
			case NSPasteboardReadingAsPropertyList:
				payload = [self propertyListForType:ty];
				break;
			case NSPasteboardReadingAsKeyedArchive:
				obj = [NSKeyedUnarchiver unarchiveObjectWithData:[self dataForType:ty]];
				break;
			default:
				payload = [self dataForType:ty];
				break;
			}
			/* THE INSTANCE METHOD IS ASKED OF THE INSTANCES. `fn_answers` asks an OBJECT whether it
			 * answers, which is right for the three instance messages above and WRONG here: a class
			 * does not respond to its instances' initialiser, so asking it answered NO for every
			 * candidate and the door returned an empty array. MEASURED by the probe, which is what
			 * the four failures at the first run of this door were. */
			if (obj == nil && payload != nil &&
			    [cls instancesRespondToSelector:@selector(initWithPasteboardPropertyList:ofType:)]) {
				obj = [[(id)[cls alloc] initWithPasteboardPropertyList:payload ofType:ty] autorelease];
			}
			if (obj != nil) {
				[out addObject:obj];
			}
		}
	}
	return out;
}

- (BOOL)canReadItemWithDataConformingToTypes:(NSArray *)types
{
	/* IDENTITY, NOT CONFORMANCE — see the header. A NO here is a real NO for a caller asking for a type
	 * the board does not carry BY NAME, and on the real system a SUPERTYPE would have answered YES, which
	 * is the narrowing this door states rather than hides. */
	if (types == nil) {
		return NO;
	}
	return [self availableTypeFromArray:types] != nil;
}

/* ---- THE FILE DOORS ------------------------------------------------------------------------ */

- (BOOL)writeFileContents:(NSString *)filename
{
	NSData *d;

	if (filename == nil) {
		return NO;
	}
	d = [NSData dataWithContentsOfFile:filename];
	if (d == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -writeFileContents: could not read the file it was given\n");
		return NO;
	}
	/* `NSFileContentsPboardType` IS THE ERA'S CARRIER for a file's bytes: the board holds the CONTENTS
	 * under it, which is what makes `-readFileContentsType:toFile:` able to write them back out. */
	[self declareTypes:[NSArray arrayWithObject:NSFileContentsPboardType] owner:nil];
	return [self setData:d forType:NSFileContentsPboardType];
}

- (NSString *)readFileContentsType:(NSString *)type toFile:(NSString *)filename
{
	NSData *d = [self dataForType:NSFileContentsPboardType];

	(void)type;
	if (d == nil || filename == nil) {
		return nil;
	}
	if (![d writeToFile:filename atomically:YES]) {
		fprintf(stderr, "APPKIT-REFUSE: -readFileContentsType:toFile: could not write the file it "
				"was given\n");
		return nil;
	}
	/* THE FILE THAT WAS WRITTEN, which is what Apple's return value names. The `type` argument is the
	 * caller's REQUEST for a flavour and this board stores one value, so there is nothing to convert and
	 * the argument is taken and unused rather than silently reinterpreted. */
	return filename;
}

- (BOOL)writeFileWrapper:(NSFileWrapper *)wrapper
{
	NSData *d;

	if (wrapper == nil) {
		return NO;
	}
	d = [wrapper regularFileContents];
	if (d == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -writeFileWrapper: needs a REGULAR-file wrapper to carry across; "
				"a directory or a symbolic link has no single byte stream and this board stores one "
				"value per type\n");
		return NO;
	}
	[self declareTypes:[NSArray arrayWithObject:NSFileContentsPboardType] owner:nil];
	return [self setData:d forType:NSFileContentsPboardType];
}

- (NSFileWrapper *)readFileWrapper
{
	NSData *d = [self dataForType:NSFileContentsPboardType];

	if (d == nil) {
		return nil;
	}
	return [[[NSFileWrapper alloc] initRegularFileWithContents:d] autorelease];
}

/* ---- THE FILTERING FAMILY, WHICH REFUSES BY NAME ------------------------------------------- */

/* ONE MESSAGE IN ONE PLACE, because four doors say the same measured thing and four copies of a reason is
 * four chances for them to disagree about it. */
static void fn_refuseFiltering(const char *which)
{
	fprintf(stderr, "APPKIT-REFUSE: %s needs the pasteboard FILTER SERVICES — a registry that converts "
			"data of one type into the types a class can read — and this tree has none, nor a UTI "
			"graph to register one with\n", which);
}

+ (NSArray *)typesFilterableTo:(NSString *)type
{
	(void)type;
	/* THE HONEST ANSWER, and it is the fact the three doors below refuse on: nothing here can be filtered
	 * to anything, so the list is empty rather than a guess at what the system would say. */
	return [NSArray array];
}

+ (NSPasteboard *)pasteboardByFilteringFile:(NSString *)filename
{
	(void)filename;
	fn_refuseFiltering("+pasteboardByFilteringFile:");
	return nil;
}

+ (NSPasteboard *)pasteboardByFilteringData:(NSData *)data ofType:(NSString *)type
{
	(void)data;
	(void)type;
	fn_refuseFiltering("+pasteboardByFilteringData:ofType:");
	return nil;
}

+ (NSPasteboard *)pasteboardByFilteringTypesInPasteboard:(NSPasteboard *)pboard
{
	(void)pboard;
	fn_refuseFiltering("+pasteboardByFilteringTypesInPasteboard:");
	return nil;
}

/* ---- THE TWO OBJECT DOORS, WHOSE ANSWERS ARE EXACT RATHER THAN A REFUSAL ----------------------- *
 * BOTH ARE ABOUT `NSPasteboardItem`, a class this tier does not ship, and the fact that makes a refusal
 * unnecessary is about the BOARD: `-writeObjects:` puts TYPES and a value per type on it (see that door) and
 * keeps no item objects, so there is nothing for `-pasteboardItems` to hand back and nothing for
 * `-indexOfPasteboardItem:` to find. An EMPTY ARRAY and NSNotFound are Apple's own answers for a board in
 * that state — nil would be the wrong one for the first, and an invented index for the second. */
- (NSArray *)pasteboardItems
{
	return [NSArray array];
}

- (NSInteger)indexOfPasteboardItem:(id)item
{
	(void)item;
	return NSNotFound;
}

@end


/* ==================================================================================================================
 * THE FOUR FILE-TYPE PHRASES.
 *
 * **THE SPELLINGS ARE STATED HERE BECAUSE THEY ARE THE WHOLE CONTRACT.** A "file contents" pboard type wraps the file
 * type in words — `Apple <type> pasteboard type` — and a "filename" type appends one: `<type> filename`. The creators
 * and the parsers below are exact inverses, and `tests/functions_target2.m` round-trips each one, because a pair that
 * disagrees would publish a file under a type nobody can read back.
 */

NSString *NSCreateFileContentsPboardType(NSString *fileType)
{
	if (fileType == nil) {
		return nil;
	}
	return [NSString stringWithFormat:@"Apple %@ pasteboard type", fileType];
}

NSString *NSCreateFilenamePboardType(NSString *fileType)
{
	if (fileType == nil) {
		return nil;
	}
	return [NSString stringWithFormat:@"%@ filename", fileType];
}

static NSString *const kFileContentsPrefix = @"Apple ";
static NSString *const kFileContentsSuffix = @" pasteboard type";
static NSString *const kFilenameSuffix = @" filename";

NSString *NSGetFileType(NSString *pboardType)
{
	NSUInteger prefixLength, suffixLength, total;

	if (pboardType == nil) {
		return nil;
	}
	total = [pboardType length];
	prefixLength = [kFileContentsPrefix length];
	suffixLength = [kFileContentsSuffix length];
	if (total > prefixLength + suffixLength
	    && [pboardType hasPrefix:kFileContentsPrefix] && [pboardType hasSuffix:kFileContentsSuffix]) {
		return [pboardType substringWithRange:NSMakeRange(prefixLength, total - prefixLength - suffixLength)];
	}
	suffixLength = [kFilenameSuffix length];
	if (total > suffixLength && [pboardType hasSuffix:kFilenameSuffix]) {
		return [pboardType substringToIndex:total - suffixLength];
	}
	return nil;
}

NSArray *NSGetFileTypes(NSArray *pboardTypes)
{
	NSMutableArray *out = [NSMutableArray array];
	NSUInteger i, count = [pboardTypes count];

	for (i = 0; i < count; i++) {
		NSString *fileType = NSGetFileType([pboardTypes objectAtIndex:i]);

		if (fileType != nil) {
			[out addObject:fileType];
		}
	}
	return out;
}
