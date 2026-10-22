/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */
/*
 * NSColorList.h — A NAMED, ORDERED COLLECTION OF COLOURS, AND THE FILE IT LIVES IN.
 *
 * **THE CLASS IS TWO MAPS AND A NAME, WHICH IS WHY IT UNLOCKS TWO OTHER CLASSES.** A list is an ORDERED set of keys
 * (`-allKeys` answers them in the order they were inserted, not sorted) each with a colour, plus a name; the colour
 * panel attaches lists as palettes, and `NSColor +colorWithCatalogName:colorName:` — which has refused by name since
 * this tier's colour slice because the class it needed did not exist — asks one. That class method is now a real
 * door, and this header is the reason.
 *
 * **THE FILE IS A PROPERTY LIST OF THIS TREE'S OWN SHAPE, STATED RATHER THAN IMPLIED.** Apple's `.clr` format is not
 * documented and is not reproduced here; what this class writes is a plist dictionary with the list's name, its keys
 * in order, and each colour as the four components `NSColor`'s own archive records. A file written by this class
 * reads back into the same list; an Apple `.clr` does NOT read (it fails the shape test and the initialiser answers
 * nil), which is a stated deviation in the DATA rather than in the API — the same trade `NSPasteboard`'s colour
 * format records.
 *
 * **THE STANDARD DIRECTORY IS `~/Library/Colors`, AND `+availableColorLists` SCANS IT EVERY TIME.** Apple caches the
 * set and publishes no reload door, so a list file that appears while the process runs is invisible until relaunch.
 * This tree re-scans, because a colour list is a small text file and the alternative is a cache with no invalidation.
 * A list loaded from a SYSTEM directory is NOT EDITABLE; one created here or loaded from the user's directory is.
 *
 * Written from `NSColorList.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSCOLORLIST_H
#define APPKIT_NSCOLORLIST_H

#import <Foundation/NSObject.h>
#import <Foundation/NSGeometry.h>

@class NSArray;
@class NSColor;
@class NSMutableArray;
@class NSMutableDictionary;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

@interface NSColorList : NSObject <NSSecureCoding>
{
	NSString *_name;			/* RETAINED */
	NSMutableArray *_order;			/* RETAINED: the keys, in insertion order */
	NSMutableDictionary *_colors;		/* RETAINED: key -> NSColor */
	NSString *_fileName;			/* RETAINED: the file it came from, or nil */
	BOOL _editable;
}

/* **THE TWO CLASS DOORS, WHICH ARE A SCAN AND A LOOKUP.** `+availableColorLists` answers a fresh array every call;
 * `+colorListNamed:` answers the list with that name from the same scan, or nil. Neither is cached (see the header). */
+ (NSArray *)availableColorLists;
+ (nullable NSColorList *)colorListNamed:(NSString *)name;

/* A LIST IS BORN EMPTY AND EDITABLE, OR FROM A FILE. The file form answers nil when the file is not a list this
 * class wrote — a missing file, an Apple `.clr`, or a plist of another shape — which is this tree's empty value for
 * the type rather than an empty list with the caller's name on it. */
- (instancetype)initWithName:(NSString *)name;
- (nullable instancetype)initWithName:(NSString *)name fromFile:(NSString *)path;

- (NSString *)name;

/* **NOT EVERY LIST MAY BE CHANGED.** A list loaded from a system directory answers NO and its three mutators refuse
 * by name; one created by `-initWithName:` or loaded from the user's directory answers YES. */
- (BOOL)isEditable;

/* THE COLOURS, BY KEY, IN THE ORDER THEY WERE INSERTED. */
- (NSArray *)allKeys;
- (nullable NSColor *)colorWithKey:(NSString *)key;
- (void)setColor:(NSColor *)color forKey:(NSString *)key;
- (void)insertColor:(NSColor *)color key:(NSString *)key atIndex:(NSUInteger)index;
- (void)removeColorWithKey:(NSString *)key;

/* **AND THE FILE'S TWO DOORS.** `-writeToFile:` with nil writes to the standard path for the list's name
 * (`~/Library/Colors/<name>.clr`), which is Apple's rule; a path writes exactly there. The answer says whether the
 * bytes were written, and the list keeps the path so a second write needs no argument. `-removeFile` deletes it and
 * answers nothing, which is Apple's signature. */
- (BOOL)writeToFile:(nullable NSString *)path;
- (void)removeFile;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSCOLORLIST_H */
