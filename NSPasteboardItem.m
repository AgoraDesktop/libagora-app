/*
 * NSPasteboardItem — several types, one object.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * A dictionary of types to bytes with an ordered type list, plus two conveniences that are the reason the class exists at
 * all: a string is bytes in one encoding, and a property list is a serialized object. The provider is asked lazily and its
 * answer cached.
 */
#import "NSPasteboardItem.h"
#import "AppKitRefusal.h"

#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSPropertyListSerialization.h>

@implementation NSPasteboardItem

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_types = [[NSMutableArray alloc] init];
		_data = [[NSMutableDictionary alloc] init];
		_provider = nil;
		_providerTypes = nil;
	}
	return self;
}

- (void)dealloc
{
	[_types release];
	[_data release];
	[_providerTypes release];
	[super dealloc];
}

/* **A VALUE IS `-dataForType:`'s ANSWER, AND A NEW TYPE JOINS THE LIST ONCE.** Setting a type twice replaces its data and
 * keeps its place, which is what makes the ORDER stable for a reader that takes the first type it understands. */
- (void)cg_setData:(NSData *)data forType:(NSString *)type
{
	if (type == nil) {
		return;
	}
	if (![_types containsObject:type]) {
		[_types addObject:type];
	}
	if (data != nil) {
		[_data setObject:data forKey:type];
	} else {
		[_data removeObjectForKey:type];
	}
}

- (NSArray *)types
{
	return [_types copy];
}

- (NSString *)availableTypeFromArray:(NSArray *)types
{
	NSUInteger i;

	for (i = 0; i < [types count]; i++) {
		NSString *type = [types objectAtIndex:i];

		if ([_types containsObject:type]) {
			return type;
		}
	}
	return nil;
}

/* ---- THE BYTES ------------------------------------------------------------------------------------ */

- (void)setData:(NSData *)data forType:(NSString *)type
{
	[self cg_setData:data forType:type];
}

/* **THE PROVIDER IS ASKED HERE, AND ONLY HERE.** A type whose data has not arrived and whose provider answers the era's
 * door is asked once; an answer is cached, so a second read is free. A provider that cannot be reached answers nothing, which
 * makes an item with a dead provider an item with fewer types rather than a crash. */
- (NSData *)dataForType:(NSString *)type
{
	NSData *data;

	if (type == nil) {
		return nil;
	}
	data = [_data objectForKey:type];
	if (data != nil) {
		return data;
	}
	if (_provider != nil && [_providerTypes containsObject:type]
	    && [(id<NSPasteboardItemDataProvider>)_provider respondsToSelector:
									  @selector(pasteboard:item:provideDataForType:)]) {
		[(id<NSPasteboardItemDataProvider>)_provider pasteboard:nil item:self provideDataForType:type];
		data = [_data objectForKey:type];
	}
	return data;
}

/* ---- THE TWO CONVENIENCES ------------------------------------------------------------------------- */

- (void)setString:(NSString *)string forType:(NSString *)type
{
	[self cg_setData:[string dataUsingEncoding:NSUTF8StringEncoding] forType:type];
}

- (NSString *)stringForType:(NSString *)type
{
	NSData *data = [self dataForType:type];

	return (data != nil) ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
}

/* **A PROPERTY LIST IS SERIALIZED ON THE WAY IN, because a pasteboard carries BYTES.** The format is the XML one, which is
 * what the rest of this tree writes; a reader that put in a dictionary gets a dictionary back, which is the only thing that
 * matters about the bytes in between. */
- (void)setPropertyList:(id)propertyList forType:(NSString *)type
{
	if (propertyList == nil) {
		[self cg_setData:nil forType:type];
		return;
	}
	[self cg_setData:[NSPropertyListSerialization dataWithPropertyList:propertyList
								  format:NSPropertyListXMLFormat_v1_0
								 options:0 error:NULL]
		 forType:type];
}

- (id)propertyListForType:(NSString *)type
{
	NSData *data = [self dataForType:type];

	if (data == nil) {
		return nil;
	}
	return [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
}

- (void)setDataProvider:(id)itemDataProvider forTypes:(NSArray *)types
{
	NSArray *held = [types copy];

	_provider = itemDataProvider;	/* NOT RETAINED: see the header */
	[_providerTypes release];
	_providerTypes = held;
}

/* ---- THE WRITER CONTRACT ------------------------------------------------------------------------- */

- (NSArray *)writableTypesForPasteboard:(id)pasteboard
{
	(void)pasteboard;
	return _types;
}

/* **THE VALUE THE BOARD TAKES IS THE TYPE'S BYTES, WHICH THE BOARD WRITES AS DATA.** A provider's type is resolved here, so
 * the laziness survives only as far as the write — which is where a board stops being able to ask. */
- (id)pasteboardPropertyListForType:(NSString *)type
{
	return [self dataForType:type];
}

/* AND THE READING HALF OF THE SAME CONTRACT, so a board can build an item back. The class answers an empty type list, which
 * is Apple's own answer for an item (the BOARD has the types, not the class), so `-readObjectsForClasses:` skips it rather
 * than inventing an item with no types. */
+ (NSArray *)readableTypesForPasteboard:(id)pasteboard
{
	(void)pasteboard;
	return [NSArray array];
}

@end
