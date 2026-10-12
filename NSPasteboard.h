/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSPasteboard.h — the pasteboard's types, and the class that holds them (stage B).
 *
 * THIS IS THE ONE CLASS NSColor AND NSImage BOTH REFERENCE, which is why stage B's order puts it first: a
 * colour writes itself out as `NSColorPboardType` and an image as `NSTIFFPboardType`, so a drawing class
 * cannot finish its surface without the pasteboard existing.
 *
 * AND IT IS AN IN-PROCESS PASTEBOARD, WHICH IS A STAGING DECISION WORTH STATING. The clipboard in this tree
 * is designed as a session-scoped SERVICE (docs/design/clipboard-plan.md) and that plan parks the question
 * of non-UIKit programs, so an Objective-C pasteboard is a NEW case rather than a covered one. What ships
 * here is the API with real behaviour inside one process: declare, add, write, read, and a change count that
 * moves when the contents do. WHAT DOES NOT CROSS PROCESSES YET IS THE CONTENTS — binding this to the
 * session service is stage C's work, with the display and event seam, because that is where a session
 * begins to exist.
 *
 * THE TYPE NAMES ARE THE ERA'S, AND THE TWO FAMILIES CARRY DIFFERENT STRINGS *BECAUSE THAT IS WHAT 10.6 DID*.
 * The legacy spellings (`NSStringPboardType`) have their own names as values — Apple's classic pasteboard
 * types are exactly that, so a reader inspecting one sees the text a 10.2 application wrote. The modern
 * spellings (`NSPasteboardTypeString`) arrive at 10.6 carrying UTI strings instead, and the block below
 * carries those values TRANSCRIBED AND CITED: Apple publishes them in its documentation rather than in the
 * header, and a UTI is an external identifier like the TIFF compression codes, which is the one case this
 * tier transcribes a value it did not invent.
 *
 * SO THE TWO FAMILIES ARE NOT INTERCHANGEABLE, and that asymmetry is the pin's rather than ours:
 * `NSPasteboardTypeString` is "public.utf8-plain-text" while `NSStringPboardType` is "NSStringPboardType",
 * so a board written under one spelling is not found under the other. A migration that changes the spelling
 * changes the string — which is what happened on the real system too. The probe asserts the asymmetry
 * rather than assuming it, because a later "tidy-up" that made them equal would be a silent fidelity change.
 */
#ifndef APPKIT_NSPASTEBOARD_H
#define APPKIT_NSPASTEBOARD_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* THE PASTEBOARD NAMES. `NSGeneralPboard` is the one `+generalPasteboard` answers. */
extern NSString *NSGeneralPboard;
extern NSString *NSFontPboard;
extern NSString *NSRulerPboard;
extern NSString *NSFindPboard;
extern NSString *NSDragPboard;

/* AND THE TYPES. A pasteboard stores BY TYPE, so these are the vocabulary a caller declares and reads. */
extern NSString *NSStringPboardType;
extern NSString *NSFilenamesPboardType;
extern NSString *NSTIFFPboardType;
extern NSString *NSRTFPboardType;
extern NSString *NSRTFDPboardType;
extern NSString *NSHTMLPboardType;
extern NSString *NSPDFPboardType;
extern NSString *NSPostScriptPboardType;
extern NSString *NSTabularTextPboardType;
extern NSString *NSFontPboardType;
extern NSString *NSRulerPboardType;
extern NSString *NSColorPboardType;
extern NSString *NSSoundPboardType;
extern NSString *NSFileContentsPboardType;
extern NSString *NSMultipleTextSelectionPboardType;
extern NSString *NSFindPanelSearchOptionsPboardType;
extern NSString *NSVCardPboardType;
extern NSString *NSInkTextPboardType;

@interface NSPasteboard : NSObject
{
	NSString *_name;		/* RETAINED */
	NSMutableArray *_types;		/* the declared types, in declaration order */
	NSMutableDictionary *_data;	/* type -> the value that was written for it */
	NSInteger _changeCount;
	/* THE OWNER IS NOT RETAINED, which is Apple's contract: `-declareTypes:owner:` takes an object that is
	 * told when the pasteboard changes, and a pasteboard that owned it would keep it alive forever. */
	id _owner;
}

/* THE FIVE SHARED BOARDS BY NAME, and one unique to this process. */
+ (NSPasteboard *)generalPasteboard;
+ (nullable NSPasteboard *)pasteboardWithName:(NSString *)name;
+ (NSPasteboard *)pasteboardWithUniqueName;
- (NSString *)name;
- (void)releaseGlobally;

/* THE CONTENT DOORS, and the change count is what tells a client whether anything moved. */
- (NSInteger)changeCount;
- (NSInteger)clearContents;
- (NSInteger)declareTypes:(nullable NSArray *)newTypes owner:(nullable id)newOwner;
- (NSInteger)addTypes:(nullable NSArray *)newTypes owner:(nullable id)newOwner;
- (nullable NSArray *)types;
- (nullable NSString *)availableTypeFromArray:(NSArray *)types;

- (BOOL)setData:(nullable NSData *)data forType:(NSString *)dataType;
- (nullable NSData *)dataForType:(NSString *)dataType;
- (BOOL)setString:(nullable NSString *)string forType:(NSString *)dataType;
- (nullable NSString *)stringForType:(NSString *)dataType;
- (BOOL)setPropertyList:(nullable id)plist forType:(NSString *)dataType;
- (nullable id)propertyListForType:(NSString *)dataType;

/* ============================================================================================ *
 * THE ERA'S REMAINING DOORS (10.6's additions, plus the 10.2 file doors).                       *
 * ============================================================================================ */

/* THE READING AND WRITING OPTIONS. Both are flag sets with PUBLISHED values, so both are transcribed
 * rather than numbered: the reading options are `1 << n` with `AsData` at ZERO — an absent option means
 * "as data", which is why zero is a real value here and not a placeholder. */
typedef enum {
	NSPasteboardReadingAsData = 0,
	NSPasteboardReadingAsString = 1 << 0,
	NSPasteboardReadingAsPropertyList = 1 << 1,
	NSPasteboardReadingAsKeyedArchive = 1 << 2
} NSPasteboardReadingOptions;

typedef enum {
	NSPasteboardWritingPromised = 1 << 9
} NSPasteboardWritingOptions;

/* THE MODERN TYPE NAMES, WITH APPLE'S PUBLISHED UTI VALUES — see the note above for why these carry real
 * strings while the legacy block carries its own names. */
extern NSString *NSPasteboardTypeString;      /* public.utf8-plain-text */
extern NSString *NSPasteboardTypePDF;         /* com.adobe.pdf */
extern NSString *NSPasteboardTypeTIFF;        /* public.tiff */
extern NSString *NSPasteboardTypePNG;         /* public.png */
extern NSString *NSPasteboardTypeRTF;         /* public.rtf */
extern NSString *NSPasteboardTypeRTFD;        /* com.apple.flat-rtfd */
extern NSString *NSPasteboardTypeHTML;        /* public.html */
extern NSString *NSPasteboardTypeTabularText; /* public.utf8-tab-separated-values-text */
extern NSString *NSPasteboardTypeFont;        /* com.apple.cocoa.pasteboard.character-formatting */
extern NSString *NSPasteboardTypeColor;       /* com.apple.cocoa.pasteboard.color */
extern NSString *NSPasteboardTypeSound;       /* com.apple.cocoa.pasteboard.sound */

/* ============================================================================================ *
 * THE NINE THE FIRST UNIT LEFT OPEN, AND THEY SHIP NOW ON SUPPORT THAT IS NOT ALL EQUAL.        *
 * ============================================================================================ *
 *
 * THE FIRST PASS REFUSED ALL NINE because the ERA GROUND declares them and does not value them: every one is
 * an `APPKIT_EXTERN NSString *` in the 10.6 headers with no string beside it, and the SDK carries no
 * resources that hold one (its only non-header artefact is a Mach-O BridgeSupport stub). THE USER'S DECISION
 * (2026-10-08) WAS TO SHIP THEM ON THE WEAKEST AVAILABLE SUPPORT RATHER THAN LEAVE THEM OWED, and the
 * comment on each line carries ITS OWN SOURCE, because a pasteboard type that matches nothing fails
 * silently and the strength of the evidence is the only thing a later reader can check.
 *
 *   CORROBORATED BY APPLE'S OWN ARCHIVED DOCUMENTATION: `NSFilesPromisePboardType`, `NSURLPboardType` and
 *     `NSPICTPboardType` — "Pasteboard Programming Topics for Cocoa" prints all three strings verbatim, and
 *     independent listings agree.
 *   CORROBORATED BY THE FAMILY THIS HEADER ALREADY SHIPS: `NSPasteboardTypeRuler` and
 *     `NSPasteboardTypeMultipleTextSelection`, whose `com.apple.cocoa.pasteboard.*` values come from the same
 *     sources as the three members of that family already above.
 *   CONVENTION RATHER THAN A QUOTE: `NSPasteboardTypeFindPanelSearchOptions`, whose UTI follows the same
 *     family and is documented "as string" under exactly that spelling by the Monkeybread plugin.
 *   AND FOUR WITH NO LITERAL IN ANY SOURCE THIS TREE COULD REACH — marked UNVERIFIED at the line. The two
 *     find-panel KEYS take the spelling their bindings' enums use; the two URL-reading KEYS take THEIR OWN
 *     NAMES, which is the convention this tree already uses for a key (NSNib's `owner`/`topLevelObjects`,
 *     NSInterfaceStyleDefault). appkit-plan.md §A10j records the searches that failed and what would settle
 *     each one.
 */
extern NSString *NSFilesPromisePboardType;		/* "Apple files promise pasteboard type" — Apple's archived docs */
extern NSString *NSURLPboardType;			/* "Apple URL pasteboard type" — Apple's archived docs */
extern NSString *NSPICTPboardType;			/* "Apple PICT pasteboard type" — Apple's archived docs */
extern NSString *NSPasteboardTypeRuler;			/* com.apple.cocoa.pasteboard.paragraph-formatting */
extern NSString *NSPasteboardTypeMultipleTextSelection;	/* com.apple.cocoa.pasteboard.multiple-text-selection */
extern NSString *NSPasteboardTypeFindPanelSearchOptions;	/* com.apple.cocoa.pasteboard.find-panel-search-options — by convention */
extern NSString *NSFindPanelCaseInsensitiveSearch;	/* "CaseInsensitiveSearch" — UNVERIFIED: a binding's enum member name */
extern NSString *NSFindPanelSubstringMatch;		/* "SubstringMatch" — UNVERIFIED: a binding's enum member name */
extern NSString *NSPasteboardURLReadingFileURLsOnlyKey;	/* its own name — UNVERIFIED: the key convention */
extern NSString *NSPasteboardURLReadingContentsConformToTypesKey;	/* its own name — UNVERIFIED: the key convention */

/* THE OBJECT DOORS, OVER THE TWO PROTOCOLS' INFORMAL SHAPE — Apple's own idiom for this class, spelled the
 * way its pasteboard header spells the older informal protocol (`@interface NSObject(NSPasteboardOwner)`):
 * the six messages are declared as a category on `NSObject` in the implementation, and every candidate is
 * asked before anything is sent. So the doors work for a caller's class the moment it implements them, and
 * a misspelled selector is a compile warning rather than a silent no-op.
 *
 * THE SIGNS ARE APPLE'S AND THEY MATTER: `+readableTypesForPasteboard:` and
 * `+readingOptionsForType:pasteboard:` are CLASS methods, while `-writableTypesForPasteboard:`,
 * `-pasteboardPropertyListForType:` and `-initWithPasteboardPropertyList:ofType:` are instance ones. The
 * one question that follows from that is asked of the INSTANCES — a class does not respond to its
 * instances' initialiser — and getting it wrong makes `-readObjectsForClasses:options:` return an empty
 * array for every input, which is what the probe caught. */
- (BOOL)writeObjects:(NSArray *)objects;
- (nullable NSArray *)readObjectsForClasses:(NSArray *)classArray options:(nullable NSDictionary *)options;
- (BOOL)canReadObjectForClasses:(NSArray *)classArray options:(nullable NSDictionary *)options;

/* AND THE TWO OBJECT DOORS, WHICH ARE ABOUT `NSPasteboardItem` — A CLASS THIS TIER DOES NOT SHIP. The item
 * parameter and the elements are spelled `id` for the rule this header states elsewhere: naming the class
 * would credit its own class row. WHAT THEY ANSWER IS EXACT RATHER THAN A REFUSAL, and the reason is a fact
 * about the board: `-writeObjects:` puts TYPES and VALUES on it and keeps NO item objects, so a board has
 * no items — which is what an empty array and NSNotFound mean, and both are Apple's own answers for that
 * state (nil is not: a board with no items has an EMPTY array, not a missing one). */
- (nullable NSArray *)pasteboardItems;
- (NSInteger)indexOfPasteboardItem:(id)item;

/* AND THE CONFORMANCE QUESTION, WHICH IS ANSWERED BY IDENTITY HERE. Real conformance needs the UTI graph —
 * something that resolves `public.png` as a kind of `public.image` — and this tree has none, so a board
 * satisfies the request when it carries one of the requested types BY NAME. THAT IS A NARROWING and it is
 * stated rather than implied: a caller asking for a supertype gets NO here and would get YES on the real
 * system. */
- (BOOL)canReadItemWithDataConformingToTypes:(nullable NSArray *)types;

/* THE FILE DOORS, WHICH ARE REAL: they read and write FILES through Foundation, so a caller can put a
 * file's contents on the board and take them back off again. */
- (BOOL)writeFileContents:(NSString *)filename;
- (nullable NSString *)readFileContentsType:(nullable NSString *)type toFile:(NSString *)filename;
- (BOOL)writeFileWrapper:(NSFileWrapper *)wrapper;
- (nullable NSFileWrapper *)readFileWrapper;

/* AND THE FILTERING FAMILY, WHICH REFUSES BY NAME. "Filtering" is a pasteboard SERVICE that converts data
 * of one type into the types a class can read; this tree has no filter services and no UTI graph to
 * register them with, so there is nothing to filter WITH. `+typesFilterableTo:` answers an EMPTY ARRAY for
 * the same reason — the honest answer to "what can this be filtered to" here is "nothing". */
+ (nullable NSArray *)typesFilterableTo:(NSString *)type;
+ (nullable NSPasteboard *)pasteboardByFilteringFile:(NSString *)filename;
+ (nullable NSPasteboard *)pasteboardByFilteringData:(NSData *)data ofType:(NSString *)type;
+ (nullable NSPasteboard *)pasteboardByFilteringTypesInPasteboard:(NSPasteboard *)pboard;

/* THE FILE-TYPE HELPERS, WHICH REFUSE BY NAME. They map between a file type name and a pasteboard type
 * built from it ("Apple TIFF pasteboard type" and its siblings), and that CONVENTION is not in Apple's
 * header where this tier's ground lives — so a string built to a remembered pattern could be one word
 * wrong, and a pasteboard type that matches nothing is exactly the silent failure this tier refuses. */
NSString * _Nullable NSCreateFileContentsPboardType(NSString *fileType);
NSString * _Nullable NSCreateFilenamePboardType(NSString *fileType);
NSString * _Nullable NSGetFileType(NSString *pboardType);
NSArray * _Nullable NSGetFileTypes(NSArray *pboardTypes);

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPASTEBOARD_H */
