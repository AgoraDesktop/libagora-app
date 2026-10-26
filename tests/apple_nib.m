/*
 * apple_nib — Apple's compiled nib, translated into this tree's keys.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE ARCHIVE HERE IS BUILT THE WAY APPLE BUILDS ONE, and it is a real binary property list.** The UIDs are
 * `_CFKeyedArchiverUID`s, the objects live in `NSObjectsKeys`/`NSObjectsValues`, the classes are `$classes` chains,
 * and every object carries APPLE'S keys (`NSFrame`, `NSvFlags`, `NSCellFlags`, `NSContents`, `NSCustomObject`,
 * `NSWindowTemplate`). The file is written with the binary writer that now goes through Core Foundation, so the test
 * covers the whole door: binary UIDs → the translator → this tree's `-initWithCoder:` → a working view tree.
 *
 * THE ASSERTIONS ARE THE TWO THINGS THAT COULD BE WRONG: the OBJECTS (a view with two children, a button with its
 * title, a field with its value) and the CONNECTIONS (the owner's outlet and the button's action), because a
 * translator can get either half right and still not load a nib.
 */
#import <AppKit/AGAppleNib.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>

#import <Foundation/Foundation.h>

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/ForFoundationOnly.h>

#include <stdio.h>

static int g_fail;

static void
check(int condition, const char *what)
{
	printf("%s   %s\n", condition ? "ok  " : "FAIL", what);
	if (!condition) {
		g_fail++;
	}
}

/* ============================== THE ARCHIVE BUILDER ============================================== */

static id
uid(NSUInteger index)
{
	return (__bridge id)_CFKeyedArchiverUIDCreate(kCFAllocatorDefault, (uint32_t)index);
}

static NSUInteger
add_class(NSMutableArray *objects, NSString *name)
{
	NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSArray arrayWithObjects:name, @"NSObject", nil], @"$classes",
		name, @"$classname",
		nil];

	[objects addObject:entry];
	return [objects count] - 1;
}

static NSUInteger
add_object(NSMutableArray *objects, NSUInteger classIndex, NSDictionary *properties)
{
	NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:properties];

	[entry setObject:uid(classIndex) forKey:@"$class"];
	[objects addObject:entry];
	return [objects count] - 1;
}

static NSUInteger
add_array(NSMutableArray *objects, NSUInteger arrayClass, NSArray *items)
{
	return add_object(objects, arrayClass,
			  [NSDictionary dictionaryWithObject:items forKey:@"NS.objects"]);
}

/* **THE OWNER THE NIB TALKS TO.** KVC is what `NSNib`'s connection pass uses for an outlet, so this class states
 * `content` as a real accessor pair rather than a bare ivar. */
@interface AppleNibOwner : NSObject
{
	id _content;
	BOOL _fired;
}
- (id)content;
- (void)setContent:(id)value;
- (void)fire:(id)sender;
- (BOOL)fired;
@end

@implementation AppleNibOwner

- (id)content
{
	return _content;
}

- (void)setContent:(id)value
{
	_content = value;
}

- (void)fire:(id)sender
{
	(void)sender;
	_fired = YES;
}

- (BOOL)fired
{
	return _fired;
}

@end

/* ============================== THE FIXTURE ===================================================== */

/* A view with a button and a text field, both with cells, an outlet from the owner to the view, and the button's
 * action wired back to the owner. `viewClassName` lets a refusal test swap NSView for NSBox without a second
 * builder; `extraViewKey` exercises the unmapped-key ledger; `withWindow` moves the view into a window template and
 * makes the window the top-level object. */
static NSDictionary *
build_archive(NSString *viewClassName, NSString *extraViewKey, BOOL withWindow)
{
	NSMutableArray *objects = [NSMutableArray arrayWithObject:@"$null"];
	NSUInteger cObjectData = add_class(objects, @"NSIBObjectData");
	NSUInteger cArray = add_class(objects, @"NSArray");
	NSUInteger cCustom = add_class(objects, @"NSCustomObject");
	NSUInteger cView = add_class(objects, viewClassName);
	NSUInteger cButton = add_class(objects, @"NSButton");
	NSUInteger cButtonCell = add_class(objects, @"NSButtonCell");
	NSUInteger cField = add_class(objects, @"NSTextField");
	NSUInteger cFieldCell = add_class(objects, @"NSTextFieldCell");
	NSUInteger cOutlet = add_class(objects, @"NSNibOutletConnector");
	NSUInteger cAction = add_class(objects, @"NSNibControlConnector");
	NSUInteger root;
	NSUInteger buttonCell;
	NSUInteger button;
	NSUInteger fieldCell;
	NSUInteger field;
	NSUInteger subviewsArray;
	NSUInteger view;
	NSUInteger outlet;
	NSUInteger action;
	NSUInteger connectionsArray;
	NSUInteger keysArray;
	NSUInteger valuesArray;
	NSUInteger objectData;
	NSMutableDictionary *viewProperties;
	NSMutableArray *keys;
	NSMutableArray *owners;
	NSMutableDictionary *properties;

	root = add_object(objects, cCustom,
			  [NSDictionary dictionaryWithObject:@"Owner" forKey:@"NSClassName"]);

	/* THE BUTTON: NSCellFlags 0x04C00000 is type 1 (text), bordered, bezeled, enabled. */
	buttonCell = add_object(objects, cButtonCell,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInt:0x04C00000u], @"NSCellFlags",
			@"Press", @"NSContents",
			nil]);
	button = add_object(objects, cButton,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{10, 10}, {90, 24}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
			uid(buttonCell), @"NSCell",
			nil]);

	/* THE FIELD: editable, selectable, bordered, bezeled, text type. */
	fieldCell = add_object(objects, cFieldCell,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInt:0x14E00000u], @"NSCellFlags",
			@"hello", @"NSContents",
			nil]);
	field = add_object(objects, cField,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{110, 10}, {180, 24}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
			uid(fieldCell), @"NSCell",
			nil]);

	subviewsArray = add_array(objects, cArray,
		[NSArray arrayWithObjects:uid(button), uid(field), nil]);
	viewProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		@"{{0, 0}, {300, 200}}", @"NSFrame",
		[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
		uid(subviewsArray), @"NSSubviews",
		nil];
	if (extraViewKey != nil) {
		[viewProperties setObject:@"unmapped" forKey:extraViewKey];
	}
	view = add_object(objects, cView, viewProperties);

	outlet = add_object(objects, cOutlet,
		[NSDictionary dictionaryWithObjectsAndKeys:
			uid(root), @"NSSource",
			uid(view), @"NSDestination",
			@"content", @"NSLabel",
			nil]);
	action = add_object(objects, cAction,
		[NSDictionary dictionaryWithObjectsAndKeys:
			uid(button), @"NSSource",
			uid(root), @"NSDestination",
			@"fire:", @"NSLabel",
			nil]);
	connectionsArray = add_array(objects, cArray,
		[NSArray arrayWithObjects:uid(outlet), uid(action), nil]);

	keys = [NSMutableArray arrayWithObjects:
		uid(root), uid(view), uid(button), uid(buttonCell), uid(field), uid(fieldCell), nil];
	owners = [NSMutableArray arrayWithObjects:
		uid(root), uid(root), uid(view), uid(button), uid(view), uid(field), nil];

	if (withWindow) {
		NSUInteger window = add_object(objects, add_class(objects, @"NSWindowTemplate"),
			[NSDictionary dictionaryWithObjectsAndKeys:
				@"NSWindow", @"NSWindowClass",
				[NSNumber numberWithUnsignedInt:15u], @"NSWindowStyleMask",
				@"{{0, 0}, {300, 200}}", @"NSWindowRect",
				[NSNumber numberWithUnsignedInt:2u], @"NSWindowBacking",
				@"Test Window", @"NSWindowTitle",
				uid(view), @"NSWindowView",
				nil]);

		/* The window is the top-level object and the view is its content view. */
		[keys addObject:uid(window)];
		[owners addObject:uid(root)];
		[owners replaceObjectAtIndex:1 withObject:uid(window)];	/* the view's owner becomes the window */
	}

	keysArray = add_array(objects, cArray, keys);
	valuesArray = add_array(objects, cArray, owners);
	objectData = add_object(objects, cObjectData,
		[NSDictionary dictionaryWithObjectsAndKeys:
			uid(keysArray), @"NSObjectsKeys",
			uid(valuesArray), @"NSObjectsValues",
			uid(connectionsArray), @"NSConnections",
			uid(root), @"NSRoot",
			nil]);
	properties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:100000], @"$version",
		@"NSKeyedArchiver", @"$archiver",
		objects, @"$objects",
		[NSDictionary dictionaryWithObject:uid(objectData) forKey:@"IB.objectdata"], @"$top",
		nil];
	return properties;
}

static NSData *
archive_data(NSDictionary *plist)
{
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
								  format:NSPropertyListBinaryFormat_v1_0
								 options:0
								   error:&error];

	if (data == nil) {
		printf("FAIL: the fixture did not write as a binary property list: %s\n",
		       error != nil ? [[error localizedDescription] UTF8String] : "unknown");
		g_fail++;
	}
	return data;
}

/* ============================== THE TESTS ======================================================= */

static void
test_instantiation(void)
{
	NSDictionary *plist = build_archive(@"NSView", nil, NO);
	NSData *data = archive_data(plist);
	NSString *path;
	NSNib *nib;
	AppleNibOwner *owner = [[AppleNibOwner alloc] init];
	NSArray *top = nil;
	NSView *view;
	NSArray *subviews;
	NSButton *button;
	NSTextField *field;

	check([AGAppleNib isAppleNibArchive:plist], "the fixture is recognised as Apple's archive");
	check([NSNib refusalReasonForArchiveData:data] == nil, "the fixture validates");

	path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"agora-apple-nib-test.nib"];
	[data writeToFile:path atomically:YES];
	nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
	check([nib instantiateNibWithOwner:owner topLevelObjects:&top],
	      "an Apple nib instantiates through NSNib");
	check([top count] == 1, "it owns one top-level object");
	view = [top count] == 1 ? [top objectAtIndex:0] : nil;
	check([view isKindOfClass:[NSView class]], "the top-level object is a view");
	check(NSEqualRects([view frame], NSMakeRect(0, 0, 300, 200)),
	      "NSFrame becomes the view's frame");

	subviews = [view subviews];
	check([subviews count] == 2, "NSSubviews becomes two subviews");
	button = [subviews count] == 2 ? [subviews objectAtIndex:0] : nil;
	field = [subviews count] == 2 ? [subviews objectAtIndex:1] : nil;
	check([button isKindOfClass:[NSButton class]], "the first child is a button");
	check(NSEqualRects([button frame], NSMakeRect(10, 10, 90, 24)),
	      "the button's frame is translated");
	check([[[button cell] title] isEqualToString:@"Press"],
	      "NSContents becomes the button cell's title");
	check([[button cell] isEnabled], "the cell's enabled flag is translated");
	check([field isKindOfClass:[NSTextField class]], "the second child is a text field");
	check([[field stringValue] isEqualToString:@"hello"],
	      "NSContents becomes the field's value");
	check([[[field cell] class] isSubclassOfClass:[NSTextFieldCell class]],
	      "the field's archived cell class is used");

	check([owner content] == view, "the owner's outlet names the top-level view");
	check([button target] == owner, "the button's action target is the owner");
	check([NSStringFromSelector([button action]) isEqualToString:@"fire:"],
	      "the action selector is translated");
	check([view superview] == nil, "no NSSuperview back-reference was obeyed");

	[nib release];
	[owner release];
}

static void
test_unmapped_ledger(void)
{
	NSDictionary *plist = build_archive(@"NSView", @"NSAlpha", NO);
	NSArray *unmapped = [AGAppleNib unmappedKeysForAppleNibArchive:plist];

	check([unmapped containsObject:@"NSView.NSAlpha"],
	      "an Apple key this translator does not map is reported");
}

static void
test_refusal_of_unsupported_class(void)
{
	NSDictionary *plist = build_archive(@"NSBox", nil, NO);
	NSData *data = archive_data(plist);
	NSString *reason = [NSNib refusalReasonForArchiveData:data];

	check(reason != nil && [reason rangeOfString:@"NSBox"].location != NSNotFound,
	      "an unsupported Apple class is refused by name");
}

static void
test_window_template_validation(void)
{
	NSDictionary *plist = build_archive(@"NSView", nil, YES);
	NSString *reason = nil;

	check([AGAppleNib validateAppleNibArchive:plist reason:&reason],
	      "a window template with a content view validates");
	check([AGAppleNib unmappedKeysForAppleNibArchive:plist] != nil,
	      "the ledger answers for a window nib");
}

static void
test_window_class_refusal(void)
{
	NSMutableArray *objects;
	NSDictionary *plist;
	NSString *reason = nil;

	plist = build_archive(@"NSView", nil, YES);
	objects = [[plist objectForKey:@"$objects"] mutableCopy];
	/* Rename the window class to an AppKit class this tree does not have. */
	{
		NSUInteger i;

		for (i = 0; i < [objects count]; i++) {
			id entry = [objects objectAtIndex:i];
			id name;

			if (![entry isKindOfClass:[NSDictionary class]]) {
				continue;
			}
			name = [entry objectForKey:@"NSWindowClass"];
			if ([name isEqualToString:@"NSWindow"]) {
				[entry setObject:@"NSFontPanel" forKey:@"NSWindowClass"];
				break;
			}
		}
	}
	{
		NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:plist];

		[copy setObject:objects forKey:@"$objects"];
		plist = copy;
	}
	check(![AGAppleNib validateAppleNibArchive:plist reason:&reason] &&
	      [reason rangeOfString:@"NSFontPanel"].location != NSNotFound,
	      "an unavailable NSWindowClass is refused by name");
	[objects release];
}

int
main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	test_instantiation();
	test_unmapped_ledger();
	test_refusal_of_unsupported_class();
	test_window_template_validation();
	test_window_class_refusal();

	[pool drain];
	printf(g_fail ? "apple_nib: FAIL\n" : "apple_nib: all checks passed\n");
	return g_fail ? 1 : 0;
}
