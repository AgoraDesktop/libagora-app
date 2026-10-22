/*
 * NSNib — the first-party interface format: the root's shape, the writer, and the reader with its allow-list.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * See the header for the format and the four rules the reader keeps. What is worth repeating here is the ORDER of
 * the checks in `-instantiateNibWithOwner:topLevelObjects:`, because the order is the security story:
 *
 *   1. The source is read. No source, no decode.
 *   2. The archive's OWN OBJECT TABLE is parsed as a property list and every class name in it is checked against
 *      `+supportedClasses` and against the census of rule 3 BEFORE a single object is instantiated. This is the
 *      check that runs first, and it is the reason a file naming a class this tree did not agree to build never
 *      reaches `-initWithCoder:`.
 *   3. The archive is decoded with secure decoding ON and the same set as the allowed classes, so the unarchiver's
 *      own gate refuses a class the walk somehow missed.
 *   4. The root's shape is checked, then the objects are built, then the connections are applied.
 *
 * A failure at any step answers NO and leaves the caller's out-parameter alone.
 */
#import <AppKit/NSNib.h>
#import <AppKit/NSView.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSActionCell.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSBrowserCell.h>
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSMenuItemCell.h>
#import <AppKit/NSPathCell.h>
#import <AppKit/NSPathComponentCell.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSScrollerCell.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSSegmentedCell.h>
#import <AppKit/NSSliderCell.h>
#import <AppKit/NSTableHeaderCell.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSSegmentedControl.h>
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSSearchField.h>
#import <AppKit/NSComboBox.h>
#import <AppKit/NSPathControl.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSBrowser.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSOutlineView.h>
#import <AppKit/NSSplitView.h>
#import <AppKit/NSToolbar.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSImage.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSKeyedArchiver.h>
/* **NSMutableArray, NSMutableDictionary AND NSMutableSet HAVE NO HEADERS OF THEIR OWN.** They are declared in
 * `NSArray.h`, `NSDictionary.h` and `NSSet.h` — all imported above — and this file imported headers that do not
 * exist, which only compiled while a stale object file hid it. Found by a rebuild after `libagora-base`
 * consolidated them. */
#import <Foundation/NSNumber.h>
#import <Foundation/NSPropertyListSerialization.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#import <objc/runtime.h>

#include <stdio.h>

/* THE ROOT'S THREE KEYS, whose values are their own names. */
NSString * const NSNibFormatVersionKey    = @"AGNibVersion";
NSString * const NSNibTopLevelObjectsKey  = @"AGNibTopLevelObjects";
NSString * const NSNibConnectionsKey      = @"AGNibConnections";

/* AND A CONNECTION'S FOUR. */
NSString * const NSNibConnectionSourceKey      = @"AGNibConnectionSource";
NSString * const NSNibConnectionKeyPathKey     = @"AGNibConnectionKeyPath";
NSString * const NSNibConnectionActionKey      = @"AGNibConnectionAction";
NSString * const NSNibConnectionDestinationKey = @"AGNibConnectionDestination";

/* THE OWNER'S PLACEHOLDER, and the two name-table keys Apple has always had. */
NSString * const NSNibFileOwner = @"NSNibFileOwner";
NSString *NSNibOwner = @"NSNibOwner";
NSString *NSNibTopLevelObjects = @"NSNibTopLevelObjects";

/* THE ONE VERSION THIS TREE WRITES, and the ceiling it reads: a file from the future is refused, because reading
 * half of it and reporting success is worse than saying the file is newer. */
static const NSInteger AGCodingFormatVersion = 1;

/* **THE ALLOW-LIST'S CACHE AND THE REGISTRY'S DOOR, DECLARED BEFORE THE C FUNCTIONS THAT READ THEM.** The cache is
 * file-scope rather than a static inside `+supportedClasses` so that `+registerDesignClass:` can INVALIDATE it: a class
 * registered after the first read must be visible to the next read, or registration would work only in the order a
 * program happens to call it. */
static NSSet *g_supported_cache = nil;

@interface NSNib (AGNibRegistry)
+ (NSMutableSet *)registeredClassNames;
@end

/* ============================================================================================
 * THE CENSUS: does a class implement its own coding, or does it inherit one?
 * ============================================================================================ */

/* **AN INHERITED `-initWithCoder:` IS SILENT DATA LOSS, WHICH IS WHY THIS EXISTS.** `NSButtonCell` responds to
 * `-initWithCoder:` whether or not `NSButtonCell` implements it, because `NSCell` does — so a subclass that forgets
 * decodes into an object whose own ivars are at their defaults and whose archive said otherwise. Comparing the IMP
 * the class answers with the IMP its SUPERCLASS answers with is the only check that separates "implements" from
 * "inherits", and it is exactly the trap this format has to survive as the hierarchy grows. */
static BOOL fn_class_implements_coding_method(Class cls, SEL sel)
{
	Method own;
	Method inherited;
	Class superclass;

	own = class_getInstanceMethod(cls, sel);
	if (own == NULL) {
		return NO;
	}
	superclass = class_getSuperclass(cls);
	if (superclass == NULL) {
		return YES;	/* a root class has nothing to inherit from */
	}
	inherited = class_getInstanceMethod(superclass, sel);
	if (inherited == NULL) {
		return YES;
	}
	return method_getImplementation(own) != method_getImplementation(inherited);
}

/* **AND INHERITING IS ONLY A DEFECT WHEN THERE IS SOMETHING TO LOSE.** A subclass that adds no instance storage has no
 * state of its own for an inherited `-initWithCoder:` to drop, so a plain `NSView` subclass with no ivars is a
 * legitimate design class — and refusing it would make the honest case (a view that exists to be one thing on screen)
 * impossible. `class_getInstanceSize` is the measurement: equal to the superclass's means no new ivars, and therefore
 * nothing the inherited method can fail to carry. A class that DOES add storage and inherits its coding is the drift
 * trap and is refused. */
static BOOL fn_class_coding_is_complete(Class cls)
{
	Class superclass;

	if (fn_class_implements_coding_method(cls, @selector(encodeWithCoder:)) &&
	    fn_class_implements_coding_method(cls, @selector(initWithCoder:))) {
		return YES;
	}
	superclass = class_getSuperclass(cls);
	if (superclass == Nil) {
		return NO;
	}
	return class_getInstanceSize(cls) == class_getInstanceSize(superclass);
}

/* ============================================================================================
 * THE ALLOW-LIST
 * ============================================================================================ */

/* **THE DESIGN LIST IS WRITTEN ONCE, AND THE CENSUS AND THE ALLOW-LIST BOTH READ IT.** Every class here must conform
 * to `NSSecureCoding` and implement both coding methods; the round-trip test asserts the census is empty, and the
 * reader refuses an archive naming a class that fails it. The order is the hierarchy's, which is the order a reader
 * chasing a refusal wants. */
/* THE LIST IS A FUNCTION'S LOCAL ARRAY so the class references resolve at FIRST USE rather than at load time — a
 * static initialiser that messages `+class` is a load-order dependency this tree has been bitten by before. */
static Class const *fn_design_classes(NSUInteger *countOut)
{
	static Class classes[64];
	static NSUInteger count = 0;

	if (count == 0) {
		classes[count++] = [NSResponder class];
		classes[count++] = [NSView class];
		classes[count++] = [NSControl class];
		/* THE CELLS, IN HIERARCHY ORDER: the base, the pass-through, and then every subclass whose face a design file
		 * can state. Each one implements its own coding — the census asserts it, and `class_getInstanceSize` is what
		 * separates a subclass with nothing to lose (NSActionCell, NSTableHeaderCell) from one that would silently drop
		 * its state. */
		classes[count++] = [NSCell class];
		classes[count++] = [NSActionCell class];
		classes[count++] = [NSTextFieldCell class];
		classes[count++] = [NSButtonCell class];
		classes[count++] = [NSBrowserCell class];
		classes[count++] = [NSComboBoxCell class];
		classes[count++] = [NSMenuItemCell class];
		classes[count++] = [NSPathCell class];
		classes[count++] = [NSPathComponentCell class];
		classes[count++] = [NSPopUpButtonCell class];
		classes[count++] = [NSScrollerCell class];
		classes[count++] = [NSSearchFieldCell class];
		classes[count++] = [NSSegmentedCell class];
		classes[count++] = [NSSliderCell class];
		classes[count++] = [NSTableHeaderCell class];
		/* AND THE CONTROLS THAT PLACE THEM, each of which adds little of its own because its face is its cell's. */
		classes[count++] = [NSButton class];
		classes[count++] = [NSTextField class];
		classes[count++] = [NSSlider class];
		classes[count++] = [NSSegmentedControl class];
		classes[count++] = [NSPopUpButton class];
		classes[count++] = [NSSearchField class];
		classes[count++] = [NSComboBox class];
		classes[count++] = [NSPathControl class];
		classes[count++] = [NSProgressIndicator class];
		classes[count++] = [NSBrowser class];
		/* AND THE CONTAINERS: a table's columns, an outline over it, the scroll view that clips one, a split's two
		 * panes, and a window's toolbar. */
		classes[count++] = [NSScrollView class];
		classes[count++] = [NSTableView class];
		classes[count++] = [NSOutlineView class];
		classes[count++] = [NSSplitView class];
		classes[count++] = [NSToolbar class];
		/* AND THE EQUATIONS, without which a nib could state a frame but never a relationship. */
		classes[count++] = [NSLayoutConstraint class];
		classes[count++] = [NSWindow class];
		classes[count++] = [NSMenu class];
		classes[count++] = [NSMenuItem class];
		classes[count++] = [NSTableColumn class];
		classes[count++] = [NSFont class];
		classes[count++] = [NSColor class];
		classes[count++] = [NSImage class];
	}
	if (countOut != NULL) {
		*countOut = count;
	}
	return classes;
}

/* **AND THE FOUNDATION VALUE CLASSES ARE ON THE ALLOW-LIST WITHOUT BEING IN THE CENSUS.** A nib's root is a
 * dictionary of arrays, strings and numbers, and a control's value is a string; those entries are in the archive's
 * table like any other, so the unarchiver must be allowed to build them. They are Apple's own archivable value types,
 * they are not design classes, and the census of rule 3 does not apply to them — it applies to the classes a design
 * file INSTRUCTS this tree to build. */
static Class const *fn_value_classes(NSUInteger *countOut)
{
	static Class classes[32];
	static NSUInteger count = 0;

	if (count == 0) {
		classes[count++] = [NSString class];
		classes[count++] = [NSMutableString class];
		classes[count++] = [NSNumber class];
		classes[count++] = [NSArray class];
		classes[count++] = [NSMutableArray class];
		classes[count++] = [NSDictionary class];
		classes[count++] = [NSMutableDictionary class];
		classes[count++] = [NSSet class];
		classes[count++] = [NSData class];
		classes[count++] = [NSDate class];
		classes[count++] = [NSValue class];
		classes[count++] = [NSNull class];
	}
	if (countOut != NULL) {
		*countOut = count;
	}
	return classes;
}

static BOOL fn_class_in_list(Class cls, Class const *classes, NSUInteger count)
{
	NSUInteger i;

	for (i = 0; i < count; i++) {
		if (classes[i] == cls) {
			return YES;
		}
	}
	return NO;
}

static BOOL fn_class_is_design_class(Class cls)
{
	NSUInteger count = 0;
	Class const *classes = fn_design_classes(&count);

	return fn_class_in_list(cls, classes, count);
}

static BOOL fn_class_is_supported(Class cls)
{
	NSUInteger dcount = 0, vcount = 0;
	Class const *design = fn_design_classes(&dcount);
	Class const *values = fn_value_classes(&vcount);

	if (fn_class_in_list(cls, design, dcount) || fn_class_in_list(cls, values, vcount)) {
		return YES;
	}
	return [[NSNib registeredClassNames] containsObject:NSStringFromClass(cls)];
}

/* **THE PRE-FLIGHT WALK, AND IT IS THE CHECK THAT RUNS BEFORE ANY OBJECT EXISTS.** The archive is a property list,
 * so its own `$objects` table can be read without instantiating anything: an object entry names its class through
 * `$class` -> `$ref` -> that entry's `$classes` chain. A name that this tree has no class for, or whose class is not
 * on the allow-list, or whose class only INHERITS its coding, is reported by name and the decode is not attempted.
 * Answer nil when the file is clean. */
static NSString *fn_first_refused_class_name(id plist)
{
	id objects;
	NSUInteger i;

	if (![plist isKindOfClass:[NSDictionary class]]) {
		return @"<the archive's root is not a dictionary>";
	}
	objects = [(NSDictionary *)plist objectForKey:@"$objects"];
	if (![objects isKindOfClass:[NSArray class]]) {
		return @"<the archive has no $objects table>";
	}
	for (i = 1; i < [(NSArray *)objects count]; i++) {
		id entry = [(NSArray *)objects objectAtIndex:i];
		id classRef;
		id classEntry;
		id names;
		id name;
		Class cls;

		if (![entry isKindOfClass:[NSDictionary class]]) {
			continue;	/* a plain plist value: a string, number, date or data */
		}
		classRef = [(NSDictionary *)entry objectForKey:@"$class"];
		if (![classRef isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		classRef = [(NSDictionary *)classRef objectForKey:@"$ref"];
		if (![classRef isKindOfClass:[NSNumber class]]) {
			continue;
		}
		if ([(NSNumber *)classRef unsignedIntegerValue] >= [(NSArray *)objects count]) {
			return @"<an object names a class entry outside the table>";
		}
		classEntry = [(NSArray *)objects objectAtIndex:[(NSNumber *)classRef unsignedIntegerValue]];
		if (![classEntry isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		/* THE `$classes` CHAIN NAMES THE CLASS FIRST AND ITS ANCESTORS AFTER IT; the FIRST name is the class the
		 * entry was written as, and it is the one that must implement its own coding. */
		names = [(NSDictionary *)classEntry objectForKey:@"$classes"];
		if (![names isKindOfClass:[NSArray class]] || [(NSArray *)names count] == 0) {
			continue;
		}
		name = [(NSArray *)names objectAtIndex:0];
		if (![name isKindOfClass:[NSString class]]) {
			continue;
		}
		cls = NSClassFromString((NSString *)name);
		if (cls == Nil) {
			return (NSString *)name;
		}
		if (!fn_class_is_supported(cls)) {
			return (NSString *)name;
		}
		/* THE CENSUS APPLIES TO THE CLASSES A DESIGN FILE NAMES, and to nothing else: a Foundation value class is
		 * Apple's archivable type and is not this tree's to audit. */
		if (fn_class_is_design_class(cls) && !fn_class_coding_is_complete(cls)) {
			return (NSString *)name;
		}
	}
	return nil;
}

@implementation NSNib

/* **THE APPLICATION'S OWN DESIGN CLASSES, BY NAME.** A `Class` is a pointer rather than an `NSObject`, and this tree's
 * collections are not asked to retain one, so the registry holds class NAMES and turns them back with
 * `NSClassFromString`. It is a class-level set because a nib's format is a class-level fact: an application registers
 * once and every `NSNib` in the process honours it. */
static NSMutableSet *g_registered_class_names = nil;

+ (NSMutableSet *)registeredClassNames
{
	if (g_registered_class_names == nil) {
		g_registered_class_names = [[NSMutableSet alloc] init];
	}
	return g_registered_class_names;
}

+ (BOOL)registerDesignClass:(Class)cls
{
	NSString *name;

	if (cls == Nil) {
		return NO;
	}
	/* **REGISTRATION IS WHERE RULE 3 IS ENFORCED, which is why this is not just an insert.** A class that would decode
	 * into a half-empty object is refused HERE, once, rather than producing a nib that loads wrongly later. */
	if (![cls conformsToProtocol:@protocol(NSSecureCoding)] || !fn_class_coding_is_complete(cls)) {
		fprintf(stderr, "NSNib: %s cannot be a design class — it must conform to NSSecureCoding and implement BOTH "
			"coding methods itself, or add no instance storage of its own if it inherits them\n",
			[NSStringFromClass(cls) UTF8String]);
		return NO;
	}
	name = NSStringFromClass(cls);
	[[self registeredClassNames] addObject:name];
	/* THE CACHE IS DROPPED SO THE NEXT READ SEES THE NEW CLASS. */
	[g_supported_cache release];
	g_supported_cache = nil;
	return YES;
}

+ (BOOL)isSupportedClass:(Class)cls
{
	return (cls != Nil) && fn_class_is_supported(cls);
}

+ (NSInteger)formatVersion
{
	return AGCodingFormatVersion;
}

+ (NSSet *)supportedClasses
{
	NSSet *set = g_supported_cache;

	if (set == nil) {
		NSUInteger dcount = 0, vcount = 0;
		Class const *design = fn_design_classes(&dcount);
		Class const *values = fn_value_classes(&vcount);
		NSMutableArray *array = [[NSMutableArray alloc] init];
		NSUInteger i;

		for (i = 0; i < dcount; i++) {
			[array addObject:design[i]];
		}
		for (i = 0; i < vcount; i++) {
			[array addObject:values[i]];
		}
		/* AND THE APPLICATION'S OWN, which are already validated by `+registerDesignClass:`. */
		{
			NSEnumerator *e = [[NSNib registeredClassNames] objectEnumerator];
			NSString *name;

			while ((name = [e nextObject]) != nil) {
				Class cls = NSClassFromString(name);

				if (cls != Nil) {
					[array addObject:cls];
				}
			}
		}
		set = [[NSSet alloc] initWithArray:array];
		g_supported_cache = set;
		[array release];
	}
	return set;
}

+ (NSSet *)classesInheritingCoding
{
	NSMutableSet *bad = [[[NSMutableSet alloc] init] autorelease];
	NSUInteger count = 0;
	Class const *classes = fn_design_classes(&count);
	NSUInteger i;

	for (i = 0; i < count; i++) {
		/* **THE ANSWER IS NAMED, NOT AN OBJECT.** A `Class` is a pointer, not an `NSObject`, and a set of them would be
		 * a set this tree's collections are not asked to hold — so the answer holds class NAMES, which are printable and
		 * which `NSClassFromString` can turn back into a class at the call site that needs one. */
		if (!fn_class_coding_is_complete(classes[i]) ||
		    ![classes[i] conformsToProtocol:@protocol(NSSecureCoding)]) {
			[bad addObject:NSStringFromClass(classes[i])];
		}
	}
	return bad;
}

/* ---- THE VALIDATOR'S DOOR ------------------------------------------------------------------- */

+ (NSString *)refusalReasonForArchiveData:(NSData *)data
{
	id plist;
	id root;
	id version;
	id objects;
	NSString *refused;
	NSError *error = nil;

	if (data == nil) {
		return @"the file could not be read";
	}
	plist = [NSPropertyListSerialization propertyListWithData:data
							  options:NSPropertyListImmutable
							   format:NULL
							    error:&error];
	if (![plist isKindOfClass:[NSDictionary class]]) {
		return [NSString stringWithFormat:@"not a property list%@%@",
			(error != nil) ? @": " : @"",
			(error != nil) ? [error localizedDescription] : @""];
	}
	refused = fn_first_refused_class_name(plist);
	if (refused != nil) {
		return [NSString stringWithFormat:@"it names %@, which this reader may not build "
				   "(see +supportedClasses and +classesInheritingCoding)", refused];
	}
	/* AND THE ROOT'S SHAPE, WHICH IS THE SAME CHECK THE READER MAKES — a file can be class-clean and still not be a nib. */
	root = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSNib supportedClasses] fromData:data error:&error];
	if (![root isKindOfClass:[NSDictionary class]]) {
		return [NSString stringWithFormat:@"it does not decode into a nib root%@%@",
			(error != nil) ? @": " : @"",
			(error != nil) ? [error localizedDescription] : @""];
	}
	version = [(NSDictionary *)root objectForKey:NSNibFormatVersionKey];
	if (![version isKindOfClass:[NSNumber class]]) {
		return [NSString stringWithFormat:@"the root has no %@", NSNibFormatVersionKey];
	}
	if ([(NSNumber *)version integerValue] > AGCodingFormatVersion) {
		return [NSString stringWithFormat:@"it is version %ld and this tree reads %ld",
			(long)[(NSNumber *)version integerValue], (long)AGCodingFormatVersion];
	}
	objects = [(NSDictionary *)root objectForKey:NSNibTopLevelObjectsKey];
	if (![objects isKindOfClass:[NSArray class]]) {
		return [NSString stringWithFormat:@"the root has no %@ array", NSNibTopLevelObjectsKey];
	}
	if ([(NSArray *)objects count] == 0) {
		return @"it owns no top-level objects, so it is not a nib";
	}
	return nil;
}

/* ---- THE TWO WAYS IN ------------------------------------------------------------------------- */

- (instancetype)initWithContentsOfURL:(NSURL *)nibFileURL
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (nibFileURL == nil) {
		[self release];
		return nil;
	}
	_url = [nibFileURL retain];
	return self;
}

- (instancetype)initWithNibNamed:(NSString *)nibName bundle:(NSBundle *)bundle
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	if (nibName == nil) {
		[self release];
		return nil;
	}
	_name = [nibName copy];
	_bundle = [bundle retain];
	return self;
}

- (void)dealloc
{
	[_url release];
	[_name release];
	[_bundle release];
	[super dealloc];
}

/* THE SOURCE'S BYTES, resolved at INSTANTIATION rather than at init — Apple's contract, and the reason a nib can be
 * named before the bundle it lives in is loaded. */
- (NSData *)cg_archiveData
{
	if (_url != nil) {
		return [NSData dataWithContentsOfURL:_url];
	}
	if (_name != nil) {
		NSBundle *bundle = (_bundle != nil) ? _bundle : [NSBundle mainBundle];
		NSString *path = [bundle pathForResource:_name ofType:@"nib"];

		if (path == nil) {
			path = [bundle pathForResource:_name ofType:nil];
		}
		if (path == nil) {
			return nil;
		}
		return [NSData dataWithContentsOfFile:path];
	}
	return nil;
}

/* ---- READING -------------------------------------------------------------------------------- */

/* **THE CONNECTIONS, APPLIED IN FILE ORDER, AND A FAILURE IS A FAILURE.** An outlet goes through
 * `-setValue:forKeyPath:`, which is the same door a design-time inspector uses, so a key that the class does not have
 * raises `NSUndefinedKeyException` — caught here and reported as a refusal, because a nib whose outlet no longer
 * exists in the code is a broken file and not a partially loaded one. An action is the target/action pair, which is
 * NOT KVC-reachable (a selector is not an object) and is therefore applied through its own two setters. */
- (BOOL)cg_applyConnections:(NSArray *)connections owner:(id)owner
{
	NSUInteger i;

	if (connections == nil) {
		return YES;
	}
	if (![connections isKindOfClass:[NSArray class]]) {
		return NO;
	}
	for (i = 0; i < [(NSArray *)connections count]; i++) {
		id record = [(NSArray *)connections objectAtIndex:i];
		id source;
		id destination;
		NSString *keyPath;
		NSString *actionName;

		if (![record isKindOfClass:[NSDictionary class]]) {
			fprintf(stderr, "NSNib: connection %lu is not a dictionary\n", (unsigned long)i);
			return NO;
		}
		source = [(NSDictionary *)record objectForKey:NSNibConnectionSourceKey];
		destination = [(NSDictionary *)record objectForKey:NSNibConnectionDestinationKey];
		keyPath = [(NSDictionary *)record objectForKey:NSNibConnectionKeyPathKey];
		actionName = [(NSDictionary *)record objectForKey:NSNibConnectionActionKey];

		/* **THE PLACEHOLDER IS SUBSTITUTED ON EITHER SIDE, BECAUSE THE FILE'S OWNER IS BOTH KINDS OF ENDPOINT.** An OUTLET
		 * has the owner as its SOURCE ("the owner's `titleField` is this view") and an ACTION has it as the DESTINATION
		 * ("this control's target is the owner"), so a reader that only resolved one side would be unable to express the
		 * common case in the other direction. */
		if ([destination isKindOfClass:[NSString class]] &&
		    [(NSString *)destination isEqualToString:NSNibFileOwner]) {
			destination = owner;
		}
		if ([source isKindOfClass:[NSString class]] &&
		    [(NSString *)source isEqualToString:NSNibFileOwner]) {
			source = owner;
		}
		if (source == nil || destination == nil) {
			fprintf(stderr, "NSNib: connection %lu is missing its source or destination%s\n",
				(unsigned long)i,
				(owner == nil) ? " (the file's owner is nil)" : "");
			return NO;
		}
		if (keyPath != nil) {
			@try {
				[source setValue:destination forKeyPath:keyPath];
			} @catch (NSException *exception) {
				fprintf(stderr, "NSNib: outlet %s on %s could not be set: %s\n",
					[keyPath UTF8String], [NSStringFromClass([source class]) UTF8String],
					[[exception reason] UTF8String]);
				return NO;
			}
		} else if (actionName != nil) {
			if (![source respondsToSelector:@selector(setTarget:)] ||
			    ![source respondsToSelector:@selector(setAction:)]) {
				fprintf(stderr, "NSNib: connection %lu sends an action to %s, which has no "
					"target/action pair\n", (unsigned long)i,
					[NSStringFromClass([source class]) UTF8String]);
				return NO;
			}
			[source setTarget:destination];
			[source setAction:NSSelectorFromString(actionName)];
		} else {
			fprintf(stderr, "NSNib: connection %lu is neither an outlet nor an action\n",
				(unsigned long)i);
			return NO;
		}
	}
	return YES;
}

- (BOOL)instantiateNibWithOwner:(id)owner topLevelObjects:(NSArray **)topLevelObjects
{
	NSData *data;
	id plist;
	id root;
	id version;
	id objects;
	id connections;
	NSString *refused;
	NSError *error = nil;

	data = [self cg_archiveData];
	if (data == nil) {
		fprintf(stderr, "NSNib: no source to read (url %s, name %s)\n",
			(_url != nil) ? [[_url absoluteString] UTF8String] : "(nil)",
			(_name != nil) ? [_name UTF8String] : "(nil)");
		return NO;
	}

	/* STEP 2: THE WALK, BEFORE ANY INSTANTIATION. */
	plist = [NSPropertyListSerialization propertyListWithData:data
							  options:NSPropertyListImmutable
							   format:NULL
							    error:&error];
	refused = fn_first_refused_class_name(plist);
	if (refused != nil) {
		fprintf(stderr, "NSNib: refusing this archive — it names %s, which is not a class this reader "
			"may build (see +supportedClasses and +classesInheritingCoding)\n", [refused UTF8String]);
		return NO;
	}

	/* STEP 3: THE DECODE, with the unarchiver's own gate set to the same list. */
	root = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSNib supportedClasses]
						     fromData:data
							error:&error];
	if (![root isKindOfClass:[NSDictionary class]]) {
		fprintf(stderr, "NSNib: the archive did not decode into a nib root%s%s\n",
			(error != nil) ? ": " : "", (error != nil) ? [[error localizedDescription] UTF8String] : "");
		return NO;
	}

	/* STEP 4: THE SHAPE, THEN THE OBJECTS, THEN THE CONNECTIONS. */
	version = [(NSDictionary *)root objectForKey:NSNibFormatVersionKey];
	if (![version isKindOfClass:[NSNumber class]]) {
		fprintf(stderr, "NSNib: the root has no %s\n", [NSNibFormatVersionKey UTF8String]);
		return NO;
	}
	if ([(NSNumber *)version integerValue] > AGCodingFormatVersion) {
		fprintf(stderr, "NSNib: this file is version %ld and this tree reads %ld\n",
			(long)[(NSNumber *)version integerValue], (long)AGCodingFormatVersion);
		return NO;
	}
	objects = [(NSDictionary *)root objectForKey:NSNibTopLevelObjectsKey];
	if (![objects isKindOfClass:[NSArray class]]) {
		fprintf(stderr, "NSNib: the root has no %s array\n", [NSNibTopLevelObjectsKey UTF8String]);
		return NO;
	}
	connections = [(NSDictionary *)root objectForKey:NSNibConnectionsKey];
	if (![self cg_applyConnections:connections owner:owner]) {
		return NO;
	}
	if (topLevelObjects != NULL) {
		*topLevelObjects = objects;
	}
	return YES;
}

- (BOOL)instantiateNibWithExternalNameTable:(NSDictionary *)nameTable
{
	id owner;
	id slot;

	if (![nameTable isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	owner = [(NSDictionary *)nameTable objectForKey:NSNibOwner];
	slot = [(NSDictionary *)nameTable objectForKey:NSNibTopLevelObjects];
	if (![slot isKindOfClass:[NSMutableArray class]]) {
		fprintf(stderr, "NSNib: -instantiateNibWithExternalNameTable: needs an NSMutableArray under %s\n",
			[NSNibTopLevelObjects UTF8String]);
		return NO;
	}
	{
		NSArray *objects = nil;

		if (![self instantiateNibWithOwner:owner topLevelObjects:&objects]) {
			return NO;
		}
		[(NSMutableArray *)slot addObjectsFromArray:objects];
	}
	return YES;
}

/* ---- WRITING -------------------------------------------------------------------------------- */

+ (NSData *)archivedDataWithTopLevelObjects:(NSArray *)objects connections:(NSArray *)connections
{
	NSMutableDictionary *root;

	if (objects == nil || [objects count] == 0) {
		return nil;
	}
	root = [[NSMutableDictionary alloc] init];
	[root setObject:[NSNumber numberWithInteger:AGCodingFormatVersion] forKey:NSNibFormatVersionKey];
	[root setObject:objects forKey:NSNibTopLevelObjectsKey];
	if (connections != nil) {
		[root setObject:connections forKey:NSNibConnectionsKey];
	}
	{
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:root];

		[root release];
		return data;
	}
}

+ (NSDictionary *)outletConnectionFrom:(id)source to:(id)destination keyPath:(NSString *)keyPath
{
	NSMutableDictionary *record = [[NSMutableDictionary alloc] init];

	if (source != nil) {
		[record setObject:source forKey:NSNibConnectionSourceKey];
	}
	if (destination != nil) {
		[record setObject:destination forKey:NSNibConnectionDestinationKey];
	}
	if (keyPath != nil) {
		[record setObject:keyPath forKey:NSNibConnectionKeyPathKey];
	}
	return [record autorelease];
}

+ (NSDictionary *)actionConnectionFrom:(id)source to:(id)destination action:(NSString *)selectorName
{
	NSMutableDictionary *record = [[NSMutableDictionary alloc] init];

	if (source != nil) {
		[record setObject:source forKey:NSNibConnectionSourceKey];
	}
	if (destination != nil) {
		[record setObject:destination forKey:NSNibConnectionDestinationKey];
	}
	if (selectorName != nil) {
		[record setObject:selectorName forKey:NSNibConnectionActionKey];
	}
	return [record autorelease];
}

@end
