/*
 * NSTextList.h — a list a paragraph belongs to: a marker format, an option, and the marker for an item number.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE SURFACE BELOW IS A TRANSCRIPTION OF THE 10.6 SDK's `NSTextList.h`, WHICH IS THIRTY-FOUR LINES AND DECLARES
 * NOTHING ELSE.** That is worth saying because the obvious assumption is wrong: **Apple's 10.6 header declares NO
 * marker-format constants** — no `NSTextListMarkerDecimal`, no `{decimal}`, none of that family — and this file does not
 * invent them. What 10.6 declares is one option, five doors, and conformance to `NSCoding` and `NSCopying`, and those
 * are what are here.
 *
 * **AND `NSParagraphStyle` DECLARES THE ARRAY THAT USES IT**, at the same era and in the same breath as `textBlocks`:
 * "Array to specify the text lists containing the paragraph, nested from outermost to innermost." So the list lives in
 * the paragraph style's `-textLists`, which this tree's `NSParagraphStyle` carries beside `-textBlocks` (10.6 declares
 * the two adjacently, and `libagora-app/NSParagraphStyle.h` has had the other one all along).
 *
 * **AND THE MARKER FORMAT IS A STRING WHOSE VOCABULARY IS APPLE'S DOCUMENTATION RATHER THAN ITS HEADER**, which is a
 * distinction this file keeps rather than blurs: `-markerForItemNumber:` understands the documented `{decimal}` family
 * (listed where the implementation reads them) and refuses anything else BY NAME, returning the decimal marker, because
 * a caller with a format this tier does not know should get a numbered marker and a message rather than an empty string.
 * A reader can therefore tell which half of this class is transcribed and which is a reading of the documentation.
 *
 * **AND `NSTextListPrependEnclosingMarker` IS APPLIED NOW**, which needed the one fact no public API carries: which list
 * ENCLOSES this one. 10.6's own header declares the private `_listSecondary` slot for exactly that, and
 * `NSParagraphStyle`'s `-setTextLists:` is what fills it — the array IS the nesting ("nested from outermost to
 * innermost"), so the style links each list to the one outside it and `-markerForItemNumber:` walks outwards as far as
 * the options ask. The tie is NOT carried by RTF, which has no such option: a round trip through a document loses it,
 * and that boundary is stated rather than discovered.
 *
 * **AND `NSCoding` IS IMPLEMENTED NOW**, which corrected a claim in this very comment: it said no class in this layer
 * archives, and the truth is the opposite — `libagora-base` carries the whole family (`NSCoder`, `NSArchiver`,
 * `NSKeyedArchiver`, `NSUnarchiver`) and `NSArray`, `NSAttributedString`, `NSTrackingArea` and `NSFontDescriptor` all
 * implement the pair. A list was simply one of the ones that had not.
 */
#ifndef APPKIT_NSTEXTLIST_H
#define APPKIT_NSTEXTLIST_H

#import <Foundation/Foundation.h>

/* THE ONE OPTION 10.6 DECLARES. `-listOptions` answers exactly what `-initWithMarkerFormat:options:` was given. */
enum {
	NSTextListPrependEnclosingMarker = (1 << 0)
};

@interface NSTextList : NSObject <NSCoding, NSCopying>
{
	NSString *_markerFormat;	/* RETAINED */
	NSUInteger _listOptions;
	NSInteger _startingItemNumber;
	void *_listSecondary;		/* RETAINED — APPLE'S OWN PRIVATE SLOT, holding the ENCLOSING list; see
					 * NSTextList_internal.h for who fills it and why no public door does */
}

/* The designated initialiser. A nil or empty format is refused by name: a list with no format has no marker, and this
 * tier will not answer one it cannot justify. */
- (id)initWithMarkerFormat:(NSString *)format options:(NSUInteger)mask;

/* THE FORMAT AS GIVEN, and the options as given. */
- (NSString *)markerFormat;
- (NSUInteger)listOptions;

/* **THE MARKER FOR ONE ITEM**, which is the whole behaviour of this class: for `{decimal}` the item's own number, for
 * the roman, alphabetic, hexadecimal and octal formats the number in that form, and for the bullet formats the glyph.
 * The numbering starts at `-startingItemNumber` (10.6's own addition, and the reason `-markerForItemNumber:` takes the
 * item rather than the count). An unknown format is refused by name and answered in decimal, which is what a caller
 * with a format from a newer era can still act on. */
- (NSString *)markerForItemNumber:(NSInteger)itemNum;

/* **THE ARCHIVE DOORS, WHICH 10.6 DECLARES BY CONFORMANCE** — `NSTextList : NSObject <NSCoding, NSCopying>` in the SDK's
 * own header. What an archive carries is the three facts a list IS: its marker format, its options and its starting
 * number. **AND IT DOES NOT CARRY THE ENCLOSING LIST**, which is not a fact about this list at all — it is a fact about
 * the paragraph style's STACK (`NSTextList_internal.h`), so a decoded list is a level of a stack rather than a stack,
 * and the style that receives it links it again. */
- (void)encodeWithCoder:(NSCoder *)coder;
- (nullable instancetype)initWithCoder:(NSCoder *)coder;

/* 10.6 AND LATER, which is this tier's era for this class. Default 1. */
- (void)setStartingItemNumber:(NSInteger)itemNum;
- (NSInteger)startingItemNumber;

@end

#endif /* APPKIT_NSTEXTLIST_H */
