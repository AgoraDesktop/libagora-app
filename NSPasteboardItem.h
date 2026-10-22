/*
 * NSPasteboardItem.h — ONE ITEM ON A PASTEBOARD: several types, each with its own value.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **A BOARD USED TO BE TYPES AND VALUES; AN ITEM IS THE SAME THING GROUPED.** `NSPasteboard`'s first API puts one value per
 * type on the whole board, so a drag carrying a file and a preview and a URL has to be three types that all mean "the same
 * thing". An item is the era's answer — ONE object carrying several types — and a board of items is a LIST of them, which is
 * what makes a multi-file drag expressible.
 *
 * **AND IT IS A WRITER THE EXISTING BOARD ALREADY KNOWS HOW TO TAKE.** `NSPasteboard -writeObjects:` asks each object for
 * `-writableTypesForPasteboard:` and `-pasteboardPropertyListForType:`, by `-respondsToSelector:` rather than by declaring
 * `NSPasteboardWriting` (that protocol is a row this tier still owes). This class implements those two methods, so
 * `[board writeObjects:[NSArray arrayWithObject:item]]` works — the same contract, one class that answers it.
 *
 * **THE DATA IS LAZY WHEN IT IS GIVEN A PROVIDER.** `-setDataProvider:forTypes:` names an object that will be asked for a
 * type's bytes only if somebody reads that type; the answer is cached, because a provider that is asked twice is a provider
 * doing its work twice. The provider's door is reached by `-respondsToSelector:` for the same reason the board's writer
 * contract is.
 */
#ifndef APPKIT_NSPASTEBOARDITEM_H
#define APPKIT_NSPASTEBOARDITEM_H

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSPasteboardItem : NSObject
{
	/* THE TYPES IN THE ORDER THEY WERE SET, and the value each one has: data as it was given, and a marker for a type whose
	 * data is still the provider's. */
	NSMutableArray *_types;		/* RETAINED; NSStrings, in order */
	NSMutableDictionary *_data;	/* RETAINED; type -> NSData */
	id _provider;			/* NOT RETAINED: the item's rule for a provider is the board's for an owner */
	NSArray *_providerTypes;	/* RETAINED; the types the provider answers for */
}

/* THE TYPES THIS ITEM CARRIES, in the order they were set. */
- (NSArray *)types;

/* THE FIRST OF THE NAMED TYPES THE ITEM HAS, which is how a reader asks "can you give me one of these". */
- (nullable NSString *)availableTypeFromArray:(NSArray *)types;

/* THE FOUR VALUE PAIRS: bytes, a string, and a property list, each with its reader. A string is stored as its UTF-8 bytes
 * (which is what `-stringForType:` reads back), and a property list is serialized on the way in, so a reader gets the object
 * it put in rather than a copy of the archive. */
- (void)setData:(nullable NSData *)data forType:(NSString *)type;
- (nullable NSData *)dataForType:(NSString *)type;
- (void)setString:(NSString *)string forType:(NSString *)type;
- (nullable NSString *)stringForType:(NSString *)type;
- (void)setPropertyList:(id)propertyList forType:(NSString *)type;
- (nullable id)propertyListForType:(NSString *)type;

/* **A PROVIDER, FOR THE TYPES NAMED.** The object is asked for a type's data only when that type is read; the answer is
 * cached. See the header's note. */
- (void)setDataProvider:(id)itemDataProvider forTypes:(NSArray *)types;

/* ---- THE WRITER CONTRACT `NSPasteboard -writeObjects:` SENDS, BY `-respondsToSelector:` ------------------------- */

- (NSArray *)writableTypesForPasteboard:(id)pasteboard;
- (nullable id)pasteboardPropertyListForType:(NSString *)type;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSPASTEBOARDITEM_H */
