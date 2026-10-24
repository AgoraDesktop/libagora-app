/*
 * NSPasteboard — the pasteboard's types and the store behind them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
#include "AGWindowServer.h"
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

/* ==================================================================================================
 * THE OTHER APPLICATION'S HALF — see CLIPBOARD-PLAN.md in the window server.
 *
 * The compositor owns the claim and never the data: a request turns into a pipe whose ends go to the owner and to this
 * process, so what arrives here is a descriptor rather than a copy the server made.
 * ================================================================================================== */

/* **ONE BOARD HOLDS THE REMOTE STATE, AND IT IS THE GENERAL ONE.** A named or unique pasteboard is this process's own
 * namespace — the Mac has application groups behind those, and this tier has neither — so the cross-application half
 * belongs to `+generalPasteboard` and nothing else.
 *
 * The seam is a single connection with single callbacks, so the board that registered them is a static: there is one
 * general pasteboard per process, and a second one would be a second connection. */
static NSPasteboard *s_remote_board;

/* **THE CALLBACKS ARE C FUNCTIONS AND THE STATE IS AN OBJECT'S, SO THE STATE HAS PRIVATE DOORS.** An ivar is
 * `@protected` by default — visible to this class and its subclasses, not to a plain function — and making it `@public`
 * in the header would hand every client this pasteboard's innards to save five methods. */
@interface NSPasteboard (AGRemote)
- (NSData *)cg_remoteReadType:(NSString *)type;
- (void)cg_remoteOfferType:(NSString *)type;
- (void)cg_remoteLost;
- (NSData *)cg_remoteDataForType:(NSString *)type;
- (void)cg_remoteTakeFd:(int)fd;
- (void)cg_remoteTakeRefusal:(int)reason;
@end

static void fn_remote_offer(void *context, const char *mime_type)
{
	NSPasteboard *board = (NSPasteboard *)context;
	NSString *type;

	if (board == nil || mime_type == NULL) {
		return;
	}
	type = [NSString stringWithUTF8String:mime_type];
	if (type != nil) {
		[board cg_remoteOfferType:type];
	}
}

static void fn_remote_lost(void *context)
{
	NSPasteboard *board = (NSPasteboard *)context;

	if (board == nil) {
		return;
	}
	[board cg_remoteLost];
}

/* **THE OWNER'S SIDE: WRITE, AND CLOSE.** The descriptor is the write end of a pipe whose reader is already holding the
 * other end, so what is written here is what arrives there — no copy the seam could get wrong. */
static void fn_remote_requested(void *context, const char *mime_type, int fd)
{
	NSPasteboard *board = (NSPasteboard *)context;
	NSString *type;
	NSData *data = nil;

	if (fd < 0) {
		return;
	}
	if (board == nil || mime_type == NULL) {
		close(fd);
		return;
	}
	type = [NSString stringWithUTF8String:mime_type];
	if (type != nil) {
		data = [board cg_remoteDataForType:type];
	}
	if (data != nil) {
		const char *bytes = (const char *)[data bytes];
		size_t length = [data length];
		size_t written = 0;

		while (written < length) {
			ssize_t n = write(fd, bytes + written, length - written);

			if (n <= 0) {
				break;
			}
			written += (size_t)n;
		}
	}
	close(fd);
}

static void fn_remote_sent(void *context, const char *mime_type, int fd)
{
	NSPasteboard *board = (NSPasteboard *)context;

	(void)mime_type;
	if (board == nil) {
		close(fd);
		return;
	}
	[board cg_remoteTakeFd:fd];
}

static void fn_remote_refused(void *context, const char *mime_type, uint32_t reason)
{
	NSPasteboard *board = (NSPasteboard *)context;

	(void)mime_type;
	if (board == nil) {
		return;
	}
	[board cg_remoteTakeRefusal:(int)reason];
}

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
	NSPasteboard *board = [self cg_boardNamed:NSGeneralPboard];

	/* **THE GENERAL BOARD IS THE ONE THAT CROSSES PROCESSES**, so it is the one that registers the seam's five
	 * callbacks — once, because the seam is one connection with one set of them. A named or unique pasteboard stays
	 * this process's own namespace: the Mac has application groups behind those, and this tier has neither. */
	if (board != nil && s_remote_board == nil) {
		AGWindowServer *server = AGWindowServerShared();
		AGSelectionHandlers handlers;

		if (server != NULL) {
			memset(&handlers, 0, sizeof handlers);
			handlers.context = board;
			handlers.offer = fn_remote_offer;
			handlers.lost = fn_remote_lost;
			handlers.requested = fn_remote_requested;
			handlers.sent = fn_remote_sent;
			handlers.refused = fn_remote_refused;
			AGWindowServerSetSelectionHandlers(server, &handlers);
			s_remote_board = board;
		}
	}
	return board;
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
		_remoteTypes = [[NSMutableArray alloc] init];
		_remoteFd = -1;
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
	[_remoteTypes release];
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

/* ---- THE REMOTE STATE'S PRIVATE DOORS --------------------------------------------------------- */

- (void)cg_remoteOfferType:(NSString *)type
{
	if (type != nil && ![_remoteTypes containsObject:type]) {
		[_remoteTypes addObject:type];
	}
	/* **THE CHANGE COUNT MOVES**, because that is how a client here polls for a clipboard change — the same door it
	 * uses for this process's own contents, which is what keeps the in-process idiom working across applications. */
	_changeCount++;
}

- (void)cg_remoteLost
{
	[_remoteTypes removeAllObjects];
	_changeCount++;
}

/* **WHAT THE OWNER WOULD SEND FOR THIS TYPE**, asked of it if it has not written it yet: `-declareTypes:owner:` names
 * an object that is asked for a type it did not write up front, which is the older informal protocol and the one an
 * `NSTextView` uses. */
- (NSData *)cg_remoteDataForType:(NSString *)type
{
	NSData *data = (type != nil) ? [_data objectForKey:type] : nil;

	if (data == nil && _owner != nil &&
	    [_owner respondsToSelector:@selector(pasteboard:provideDataForType:)]) {
		[_owner pasteboard:self provideDataForType:type];
		data = [_data objectForKey:type];
	}
	return data;
}

- (void)cg_remoteTakeFd:(int)fd
{
	_remoteFd = fd;
	_remoteAnswered = YES;
}

- (void)cg_remoteTakeRefusal:(int)reason
{
	_remoteRefused = YES;
	_remoteReason = reason;
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
	/* **AND THE OTHER APPLICATIONS ARE TOLD**, because a selection this process gave up is one they may not paste. */
	if (self == s_remote_board) {
		AGWindowServerClearSelection(AGWindowServerShared());
	}
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
	/* **AND THE SELECTION IS CLAIMED WITH THEM.** The types are the offer; the data stays here and is produced when
	 * somebody asks (`-pasteboard:provideDataForType:` or a value written with `-setData:forType:`). */
	if (self == s_remote_board) {
		const char *names[32];
		int count = 0;
		NSUInteger j;

		for (j = 0; j < [_types count] && count < 32; j++) {
			names[count++] = [[_types objectAtIndex:j] UTF8String];
		}
		AGWindowServerSetSelection(AGWindowServerShared(), names, count);
	}
	return ++_changeCount;
}

- (NSArray *)types
{
	/* **WHAT THIS PROCESS DECLARED, OR — WHEN IT DECLARED NOTHING — WHAT ANOTHER APPLICATION IS OFFERING.** The
	 * remote list arrives unsolicited, so this answers without a round trip; only `-dataForType:` ever asks. A
	 * pasteboard that owns types is the owner, and an owner's list is its own. */
	if ([_types count] > 0 || _remoteTypes == nil) {
		/* A COPY, so that a client holding the answer is not holding the pasteboard's own array. */
		return [[_types copy] autorelease];
	}
	return [[_remoteTypes copy] autorelease];
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

/* **THE ONE DOOR THAT ASKS ANOTHER APPLICATION, AND IT IS BOUNDED RATHER THAN BLOCKING.** A pasteboard read on the Mac
 * can wait on a remote owner; this seam has no unbounded waits, so the wait here is a deadline: the request is sent, the
 * connection is dispatched until the answer arrives or 250 ms pass, and a reader slower than that is answered `nil`
 * rather than by hanging a UI. Callers that want the async shape take the descriptor through the private door and read
 * it with `O_NONBLOCK`; this is the shape `NSTextView` and every existing caller already uses. */
- (NSData *)cg_remoteReadType:(NSString *)dataType
{
	AGWindowServer *server = AGWindowServerShared();
	NSMutableData *data;
	long deadline_ms = 250;
	char buffer[4096];
	BOOL got;

	if (server == NULL || dataType == nil || AGWindowServerRequestSelection(server, [dataType UTF8String]) != 0) {
		return nil;
	}
	_remoteAnswered = NO;
	_remoteRefused = NO;
	_remoteFd = -1;
	_remoteReason = -1;
	/* DISPATCH UNTIL AN ANSWER OR THE DEADLINE. The answer is an event on the same connection every window uses, so
	 * this pumps it rather than waiting on the descriptor alone — and the deadline is what keeps it bounded. */
	while (!_remoteAnswered && !_remoteRefused && deadline_ms > 0) {
		if (AGWindowServerDispatchTimeout(server, 1) < 0) {
			break;
		}
		deadline_ms--;
	}
	got = _remoteAnswered;
	if (!got || _remoteFd < 0) {
		if (!_remoteAnswered && !_remoteRefused) {
			/* **A TIMEOUT IS NOT A REFUSAL AND IS NOT AN EMPTY CLIPBOARD.** Said out loud in the diagnostic, because
			 * "the paste came out empty" is the failure that is worst to debug by eye. */
			if (getenv("AG_PASTEBOARD_DIAG") != NULL) {
				fprintf(stderr, "  DIAG pasteboard: no answer for %s within the deadline\n",
					[dataType UTF8String]);
			}
		} else if (_remoteRefused && getenv("AG_PASTEBOARD_DIAG") != NULL) {
			fprintf(stderr, "  DIAG pasteboard: %s refused (reason %d)\n", [dataType UTF8String],
				_remoteReason);
		}
		return nil;
	}
	data = [NSMutableData data];
	for (;;) {
		ssize_t got_bytes = read(_remoteFd, buffer, sizeof buffer);

		if (got_bytes <= 0) {
			break;
		}
		[data appendBytes:buffer length:(NSUInteger)got_bytes];
	}
	close(_remoteFd);
	_remoteFd = -1;
	return (NSData *)data;
}

- (NSData *)dataForType:(NSString *)dataType
{
	NSData *local;

	if (dataType == nil) {
		return nil;
	}
	local = [_data objectForKey:dataType];
	if (local != nil) {
		return local;
	}
	/* **THIS PROCESS'S OWN CONTENTS FIRST, THEN THE OTHER APPLICATION'S.** A pasteboard that declared types is the owner
	 * and answers from its own store; one that declared nothing is a reader, and the only reader that has a
	 * compositor to ask. */
	if (self != s_remote_board || [_types count] > 0) {
		return nil;
	}
	return [self cg_remoteReadType:dataType];
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
