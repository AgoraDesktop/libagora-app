/*
 * NSColorList — a named, ordered collection of colours, and the file it lives in.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLASS IS TWO MAPS AND A NAME**, and the file is a property list of this tree's own shape (see the header). The
 * two decisions worth naming are both about EDITABILITY: a list loaded from a system directory refuses its three
 * mutators by name rather than quietly changing in memory and losing the change on the next launch, and a list loaded
 * from the user's directory is writable because `~/Library/Colors` is where a colour list belongs.
 *
 * AND THE ONE SHAPE THIS FILE MUST NOT GET WRONG: **THE KEYS ARE ORDERED BY THE LIST, NOT BY THE DICTIONARY.** A naive
 * implementation that answered `-allKeys` from the dictionary would return hash order, so a palette's swatches would
 * reorder themselves between launches; `_order` is that fact kept explicitly.
 */
#import <AppKit/NSColorList.h>

#import <AppKit/NSColor.h>
#import <AppKit/AppKitRefusal.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPropertyListSerialization.h>
#import <Foundation/NSString.h>

/* **THE FILE'S KEYS, NAMED ONCE.** A plist of this shape is what `-writeToFile:` writes and `-initWithName:fromFile:`
 * requires; a file that does not carry them is not a colour list, and the initialiser answers nil rather than a list
 * with no colours in it. */
static NSString * const AGColorListNameKey = @"name";
static NSString * const AGColorListKeysKey = @"keys";
static NSString * const AGColorListColorsKey = @"colors";
static NSString * const AGColorListRedKey = @"red";
static NSString * const AGColorListGreenKey = @"green";
static NSString * const AGColorListBlueKey = @"blue";
static NSString * const AGColorListAlphaKey = @"alpha";

/* AND THE DIRECTORY'S TWO, in the order a scan wants them: the user's first, so a user list wins a name collision. */
static NSString *AGColorListUserDirectory(void)
{
	return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Colors"];
}

static NSArray *AGColorListDirectories(void)
{
	return [NSArray arrayWithObjects:AGColorListUserDirectory(), @"/Library/Colors", nil];
}

static NSDictionary *AGColorListComponents(NSColor *color)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithDouble:(double)[color redComponent]], AGColorListRedKey,
		[NSNumber numberWithDouble:(double)[color greenComponent]], AGColorListGreenKey,
		[NSNumber numberWithDouble:(double)[color blueComponent]], AGColorListBlueKey,
		[NSNumber numberWithDouble:(double)[color alphaComponent]], AGColorListAlphaKey, nil];
}

static NSColor *AGColorListColor(NSDictionary *components)
{
	NSNumber *red, *green, *blue, *alpha;

	if (![components isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	red = [components objectForKey:AGColorListRedKey];
	green = [components objectForKey:AGColorListGreenKey];
	blue = [components objectForKey:AGColorListBlueKey];
	alpha = [components objectForKey:AGColorListAlphaKey];
	if (red == nil || green == nil || blue == nil || alpha == nil) {
		return nil;
	}
	return [NSColor colorWithCalibratedRed:(CGFloat)[red doubleValue] green:(CGFloat)[green doubleValue]
					 blue:(CGFloat)[blue doubleValue] alpha:(CGFloat)[alpha doubleValue]];
}

@interface NSColorList ()
- (NSString *)fn_standardPath;
@end

@implementation NSColorList

/* ============================================================================================ *
 * THE CLASS DOORS: A SCAN AND A LOOKUP.                                                         *
 * ============================================================================================ */

+ (NSArray *)availableColorLists
{
	NSMutableArray *lists = [NSMutableArray array];
	NSFileManager *manager = [NSFileManager defaultManager];
	NSArray *directories = AGColorListDirectories();
	NSUInteger d;

	for (d = 0; d < [directories count]; d++) {
		NSString *directory = [directories objectAtIndex:d];
		NSArray *names = [manager contentsOfDirectoryAtPath:directory error:NULL];
		NSUInteger i;

		for (i = 0; i < [names count]; i++) {
			NSString *file = [names objectAtIndex:i];
			NSString *path;
			NSColorList *list;

			if (![[file pathExtension] isEqual:@"clr"]) {
				continue;
			}
			path = [directory stringByAppendingPathComponent:file];
			list = [[[NSColorList alloc] initWithName:[file stringByDeletingPathExtension] fromFile:path] autorelease];
			if (list != nil) {
				/* **THE FIRST LIST WITH A NAME WINS**, which is what scanning the user's directory first buys: a
				 * user's "Favourites" shadows a system one of the same name rather than appearing twice. */
				BOOL shadowed = NO;
				NSUInteger j;

				for (j = 0; j < [lists count]; j++) {
					if ([[[lists objectAtIndex:j] name] isEqual:[list name]]) {
						shadowed = YES;
						break;
					}
				}
				if (!shadowed) {
					[lists addObject:list];
				}
			}
		}
	}
	return lists;
}

+ (NSColorList *)colorListNamed:(NSString *)name
{
	NSArray *lists = [NSColorList availableColorLists];
	NSUInteger i;

	if (name == nil) {
		return nil;
	}
	for (i = 0; i < [lists count]; i++) {
		if ([[[lists objectAtIndex:i] name] isEqual:name]) {
			return [lists objectAtIndex:i];
		}
	}
	return nil;
}

/* ============================================================================================ *
 * LIFETIME.                                                                                     *
 * ============================================================================================ */

- (instancetype)initWithName:(NSString *)name
{
	self = [super init];
	if (self != nil) {
		_name = [name copy];
		_order = [[NSMutableArray alloc] init];
		_colors = [[NSMutableDictionary alloc] init];
		_fileName = nil;
		/* **A LIST MADE HERE IS EDITABLE**, because it has no file to be protected and the caller made it to edit. */
		_editable = YES;
	}
	return self;
}

- (instancetype)initWithName:(NSString *)name fromFile:(NSString *)path
{
	NSData *data;
	id plist;
	NSArray *keys;
	NSDictionary *colors;
	NSUInteger i;

	self = [super init];
	if (self == nil) {
		return nil;
	}
	_name = [name copy];
	_order = [[NSMutableArray alloc] init];
	_colors = [[NSMutableDictionary alloc] init];
	if (path == nil) {
		[self release];
		return nil;
	}
	data = [NSData dataWithContentsOfFile:path];
	plist = (data != nil)
		? [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable
						 format:NULL errorDescription:NULL]
		: nil;
	if (![plist isKindOfClass:[NSDictionary class]]) {
		[self release];
		return nil;
	}
	keys = [(NSDictionary *)plist objectForKey:AGColorListKeysKey];
	colors = [(NSDictionary *)plist objectForKey:AGColorListColorsKey];
	if (![keys isKindOfClass:[NSArray class]] || ![colors isKindOfClass:[NSDictionary class]]) {
		[self release];
		return nil;
	}
	if (_name == nil) {
		_name = [(NSString *)[(NSDictionary *)plist objectForKey:AGColorListNameKey] copy];
	}
	for (i = 0; i < [keys count]; i++) {
		NSString *key = [keys objectAtIndex:i];
		NSColor *color = AGColorListColor([colors objectForKey:key]);

		if (key != nil && color != nil) {
			[_order addObject:key];
			[_colors setObject:color forKey:key];
		}
	}
	_fileName = [path copy];
	/* **A LIST FROM THE USER'S DIRECTORY IS WRITABLE; ONE FROM THE SYSTEM'S IS NOT.** The test is the path's prefix
	 * rather than the file's permissions, because a system list may well be writable by root and still must not be
	 * changed by an application running as one. */
	_editable = [path hasPrefix:AGColorListUserDirectory()];
	return self;
}

- (void)dealloc
{
	[_name release];
	[_order release];
	[_colors release];
	[_fileName release];
	[super dealloc];
}

/* ============================================================================================ *
 * THE COLOURS.                                                                                  *
 * ============================================================================================ */

- (NSString *)name
{
	return _name;
}

- (BOOL)isEditable
{
	return _editable;
}

- (NSArray *)allKeys
{
	return [NSArray arrayWithArray:_order];
}

- (NSColor *)colorWithKey:(NSString *)key
{
	return (key != nil) ? [_colors objectForKey:key] : nil;
}

/* **THE THREE MUTATORS ASK `-isEditable` FIRST AND REFUSE BY NAME WHEN IT SAYS NO.** That is a refusal with a reader
 * rather than a stored bit: the branch below is the only place the flag is consulted, and a caller can tell a
 * protected list from a full one because the door says so on stderr. */
- (void)setColor:(NSColor *)color forKey:(NSString *)key
{
	if (key == nil) {
		return;
	}
	if (!_editable) {
		fn_refuse_window("-setColor:forKey:", "an editable list — this one came from a system directory");
		return;
	}
	if (color == nil) {
		[self removeColorWithKey:key];
		return;
	}
	if ([_colors objectForKey:key] == nil) {
		[_order addObject:key];
	}
	[_colors setObject:color forKey:key];
}

- (void)insertColor:(NSColor *)color key:(NSString *)key atIndex:(NSUInteger)index
{
	NSUInteger existing;

	if (key == nil || color == nil) {
		return;
	}
	if (!_editable) {
		fn_refuse_window("-insertColor:key:atIndex:", "an editable list — this one came from a system directory");
		return;
	}
	existing = [_order indexOfObject:key];
	if (existing != NSNotFound) {
		[_order removeObjectAtIndex:existing];
		if (existing < index) {
			index--;
		}
	}
	if (index > [_order count]) {
		index = [_order count];
	}
	[_order insertObject:key atIndex:index];
	[_colors setObject:color forKey:key];
}

- (void)removeColorWithKey:(NSString *)key
{
	NSUInteger existing;

	if (key == nil) {
		return;
	}
	if (!_editable) {
		fn_refuse_window("-removeColorWithKey:", "an editable list — this one came from a system directory");
		return;
	}
	existing = [_order indexOfObject:key];
	if (existing != NSNotFound) {
		[_order removeObjectAtIndex:existing];
	}
	[_colors removeObjectForKey:key];
}

/* ============================================================================================ *
 * THE FILE.                                                                                     *
 * ============================================================================================ */

- (NSString *)fn_standardPath
{
	return [AGColorListUserDirectory() stringByAppendingPathComponent:
		[_name stringByAppendingPathExtension:@"clr"]];
}

- (BOOL)writeToFile:(NSString *)path
{
	NSString *destination = (path != nil) ? path : [self fn_standardPath];
	NSMutableDictionary *colors = [NSMutableDictionary dictionary];
	NSDictionary *plist;
	NSData *data;
	NSUInteger i;

	if (!_editable && path == nil) {
		fn_refuse_window("-writeToFile:", "an editable list with no destination — this one came from a system directory");
		return NO;
	}
	for (i = 0; i < [_order count]; i++) {
		NSString *key = [_order objectAtIndex:i];

		[colors setObject:AGColorListComponents([_colors objectForKey:key]) forKey:key];
	}
	plist = [NSDictionary dictionaryWithObjectsAndKeys:
		 _name, AGColorListNameKey,
		 [NSArray arrayWithArray:_order], AGColorListKeysKey,
		 colors, AGColorListColorsKey, nil];
	data = [NSPropertyListSerialization dataFromPropertyList:plist format:NSPropertyListXMLFormat_v1_0
							errorDescription:NULL];
	if (data == nil) {
		return NO;
	}
	/* **THE DIRECTORY IS MADE IF IT IS NOT THERE**, because the standard path is under `~/Library`, which a fresh
	 * account may not have: a write that failed for want of a directory would look like a colour-list bug. */
	if (path == nil) {
		/* **THE INTERMEDIATE DIRECTORIES ARE CREATED, NOT JUST THE LAST ONE.** On this system `~/Library` need not
		 * exist at all, and the one-directory door would fail with "no such file or directory" for a colour list —
		 * MEASURED by the probe's first run, where every standard-path write failed and the list looked uneditable. */
		[[NSFileManager defaultManager] createDirectoryAtPath:AGColorListUserDirectory()
					  withIntermediateDirectories:YES attributes:nil error:NULL];
	}
	if (![data writeToFile:destination atomically:YES]) {
		return NO;
	}
	[_fileName release];
	_fileName = [destination copy];
	return YES;
}

- (void)removeFile
{
	if (_fileName != nil) {
		[[NSFileManager defaultManager] removeItemAtPath:_fileName error:NULL];
		[_fileName release];
		_fileName = nil;
	}
}

/* ============================================================================================ *
 * ARCHIVING: THE NAME, THE ORDER AND THE COLOURS.                                               *
 * ============================================================================================ */

static NSString * const AGCoderColorListNameKey = @"NSColorListName";
static NSString * const AGCoderColorListOrderKey = @"NSColorListOrder";
static NSString * const AGCoderColorListColorsKey = @"NSColorListColors";
static NSString * const AGCoderColorListEditableKey = @"NSColorListEditable";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject:_name forKey:AGCoderColorListNameKey];
	[aCoder encodeObject:_order forKey:AGCoderColorListOrderKey];
	[aCoder encodeObject:_colors forKey:AGCoderColorListColorsKey];
	[aCoder encodeBool:_editable forKey:AGCoderColorListEditableKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super init];
	if (self != nil) {
		_name = [[aDecoder decodeObjectForKey:AGCoderColorListNameKey] copy];
		_order = [[NSMutableArray alloc] initWithArray:[aDecoder decodeObjectForKey:AGCoderColorListOrderKey]];
		_colors = [[NSMutableDictionary alloc] initWithDictionary:
			[aDecoder decodeObjectForKey:AGCoderColorListColorsKey]];
		_editable = [aDecoder decodeBoolForKey:AGCoderColorListEditableKey];
		_fileName = nil;
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

@end
