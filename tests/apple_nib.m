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
#import <AppKit/NSBox.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSSlider.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>

#import <Foundation/Foundation.h>

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/ForFoundationOnly.h>

#include <stdio.h>
#include <math.h>

static int g_fail;

static void check(int condition, const char *what);

static void
check_color(NSColor *color, CGFloat red, CGFloat green, CGFloat blue, const char *what)
{
	check(color != nil &&
	      fabs((double)[color redComponent] - (double)red) < 0.01 &&
	      fabs((double)[color greenComponent] - (double)green) < 0.01 &&
	      fabs((double)[color blueComponent] - (double)blue) < 0.01,
	      what);
}

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


/* **THE SECOND FIXTURE: THE CONTAINERS.** A box with a content view and a title cell, a scroll view with a clip view
 * and a matrix document, and the matrix's flat cell array — the four classes the first slice refused. They are built
 * with the SAME Apple spelling as the first fixture (`NSContentView`, `NSDocView`, `NSsFlags`, `NScvFlags`,
 * `NSCells`, `NSSubviews`), so this is the translator's own table being exercised rather than a shortcut. */
static NSDictionary *
build_layout_archive(void)
{
	NSMutableArray *objects = [NSMutableArray arrayWithObject:@"$null"];
	NSUInteger cObjectData = add_class(objects, @"NSIBObjectData");
	NSUInteger cArray = add_class(objects, @"NSArray");
	NSUInteger cCustom = add_class(objects, @"NSCustomObject");
	NSUInteger cView = add_class(objects, @"NSView");
	NSUInteger cBox = add_class(objects, @"NSBox");
	NSUInteger cScroll = add_class(objects, @"NSScrollView");
	NSUInteger cClip = add_class(objects, @"NSClipView");
	NSUInteger cMatrix = add_class(objects, @"NSMatrix");
	NSUInteger cButtonCell = add_class(objects, @"NSButtonCell");
	NSUInteger cFieldCell = add_class(objects, @"NSTextFieldCell");
	NSUInteger cFont = add_class(objects, @"NSFont");
	NSUInteger cSlider = add_class(objects, @"NSSlider");
	NSUInteger cSliderCell = add_class(objects, @"NSSliderCell");
	NSUInteger cColor = add_class(objects, @"NSColor");
	NSUInteger root;
	NSUInteger font;
	NSUInteger textColor;
	NSUInteger fieldBackground;
	NSUInteger catalogBackground;
	NSUInteger matrixBackground;
	NSUInteger matrixCellBackground;
	NSUInteger cellA;
	NSUInteger cellB;
	NSUInteger cellsArray;
	NSUInteger matrix;
	NSUInteger clip;
	NSUInteger scroll;
	NSUInteger titleCell;
	NSUInteger sliderCell;
	NSUInteger slider;
	NSUInteger inner;
	NSUInteger box;
	NSUInteger view;
	NSUInteger subviewsArray;
	NSUInteger keysArray;
	NSUInteger valuesArray;
	NSUInteger objectData;
	NSMutableArray *keys = [NSMutableArray array];
	NSMutableArray *owners = [NSMutableArray array];
	NSDictionary *properties;

	root = add_object(objects, cCustom,
			  [NSDictionary dictionaryWithObject:@"Owner" forKey:@"NSClassName"]);
	font = add_object(objects, cFont,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"Helvetica", @"NSName",
			[NSNumber numberWithDouble:13.0], @"NSSize",
			[NSNumber numberWithUnsignedInt:16u], @"NSfFlags",
			nil]);
	textColor = add_object(objects, cColor,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:1], @"NSColorSpace",
			[NSData dataWithBytes:"0 0 1" length:5], @"NSRGB",
			nil]);
	fieldBackground = add_object(objects, cColor,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:3], @"NSColorSpace",
			[NSData dataWithBytes:"0.8" length:3], @"NSWhite",
			nil]);
	/* A CATALOG COLOUR WITH ITS RESOLVED FALLBACK, which is Apple's own shape for a system colour. */
	catalogBackground = add_object(objects, cColor,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"System", @"NSCatalogName",
			@"textBackgroundColor", @"NSColorName",
			[NSNumber numberWithInt:6], @"NSColorSpace",
			uid(fieldBackground), @"NSColor",
			nil]);
	matrixBackground = add_object(objects, cColor,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:1], @"NSColorSpace",
			[NSData dataWithBytes:"1 0 0" length:5], @"NSRGB",
			nil]);
	matrixCellBackground = add_object(objects, cColor,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:3], @"NSColorSpace",
			[NSData dataWithBytes:"0.25" length:4], @"NSWhite",
			nil]);

	cellA = add_object(objects, cButtonCell,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInt:0x04000000u], @"NSCellFlags",
			@"A", @"NSContents",
			nil]);
	cellB = add_object(objects, cButtonCell,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInt:0x04000000u], @"NSCellFlags",
			@"B", @"NSContents",
			nil]);
	cellsArray = add_array(objects, cArray,
		[NSArray arrayWithObjects:uid(cellA), uid(cellB), nil]);

	/* THE MATRIX: two rows by one column, the first cell selected, its cells flat in Apple's order. */
	matrix = add_object(objects, cMatrix,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{0, 0}, {100, 40}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0u], @"NSvFlags",
			uid(cellsArray), @"NSCells",
			[NSNumber numberWithInt:2], @"NSNumRows",
			[NSNumber numberWithInt:1], @"NSNumCols",
			@"{100, 20}", @"NSCellSize",
			@"{0, 0}", @"NSIntercellSpacing",
			uid(cellA), @"NSSelectedCell",
			uid(matrixBackground), @"NSBackgroundColor",
			uid(matrixCellBackground), @"NSCellBackgroundColor",
			nil]);

	titleCell = add_object(objects, cFieldCell,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInt:0u], @"NSCellFlags",
			@"Group", @"NSContents",
			uid(font), @"NSSupport",
			uid(textColor), @"NSTextColor",
			uid(fieldBackground), @"NSBackgroundColor",
			[NSNumber numberWithBool:YES], @"NSDrawsBackground",
			nil]);

	inner = add_object(objects, cView,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{4, 4}, {192, 80}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
			nil]);

	/* THE BOX: its content view is BOTH `NSContentView` and an entry in `NSSubviews`, which is Apple's own shape. */
	box = add_object(objects, cBox,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{0, 0}, {200, 100}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
			uid(inner), @"NSContentView",
			uid(titleCell), @"NSTitleCell",
			@"{3, 3}", @"NSOffsets",
			[NSNumber numberWithInt:0], @"NSBoxType",
			[NSNumber numberWithInt:0], @"NSBorderType",
			[NSNumber numberWithInt:0], @"NSTitlePosition",
			[NSNumber numberWithBool:NO], @"NSTransparent",
			uid(inner), @"NSSubviews",
			nil]);

	clip = add_object(objects, cClip,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{0, 0}, {190, 90}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0u], @"NSvFlags",
			uid(matrix), @"NSDocView",
			[NSNumber numberWithUnsignedInt:4u], @"NScvFlags",
			uid(matrix), @"NSSubviews",
			uid(catalogBackground), @"NSBGColor",
			nil]);

	/* NSsFlags: border 0, vertical 16, horizontal 32, autohide 512. */
	scroll = add_object(objects, cScroll,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{0, 110}, {200, 100}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
			uid(clip), @"NSContentView",
			[NSNumber numberWithUnsignedInt:560u], @"NSsFlags",
			nil]);

	sliderCell = add_object(objects, cSliderCell,
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInt:0x04000000u], @"NSCellFlags",
			[NSNumber numberWithDouble:0.0], @"NSMinValue",
			[NSNumber numberWithDouble:10.0], @"NSMaxValue",
			[NSNumber numberWithDouble:4.0], @"NSValue",
			[NSNumber numberWithInt:3], @"NSNumberOfTickMarks",
			[NSNumber numberWithInt:1], @"NSTickMarkPosition",
			[NSNumber numberWithBool:YES], @"NSAllowsTickMarkValuesOnly",
			[NSNumber numberWithBool:NO], @"NSVertical",
			nil]);
	slider = add_object(objects, cSlider,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{0, 220}, {200, 20}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
			uid(sliderCell), @"NSCell",
			nil]);

	subviewsArray = add_array(objects, cArray,
		[NSArray arrayWithObjects:uid(box), uid(scroll), uid(slider), nil]);
	view = add_object(objects, cView,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"{{0, 0}, {200, 240}}", @"NSFrame",
			[NSNumber numberWithUnsignedInt:0x100u], @"NSvFlags",
			uid(subviewsArray), @"NSSubviews",
			nil]);

	[keys addObjectsFromArray:[NSArray arrayWithObjects:
		uid(root), uid(view), uid(box), uid(inner), uid(titleCell), uid(font),
		uid(scroll), uid(clip), uid(matrix), uid(cellA), uid(cellB),
		uid(slider), uid(sliderCell), nil]];
	[owners addObjectsFromArray:[NSArray arrayWithObjects:
		uid(root), uid(root), uid(view), uid(box), uid(box), uid(titleCell),
		uid(view), uid(scroll), uid(clip), uid(matrix), uid(matrix),
		uid(view), uid(slider), nil]];

	keysArray = add_array(objects, cArray, keys);
	valuesArray = add_array(objects, cArray, owners);
	objectData = add_object(objects, cObjectData,
		[NSDictionary dictionaryWithObjectsAndKeys:
			uid(keysArray), @"NSObjectsKeys",
			uid(valuesArray), @"NSObjectsValues",
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

static void
test_layout_translation(void)
{
	NSDictionary *plist = build_layout_archive();
	NSData *data = archive_data(plist);
	NSString *path;
	NSNib *nib;
	NSArray *top = nil;
	NSView *view;
	NSArray *subviews;
	NSBox *box;
	NSScrollView *scroll;
	NSSlider *slider;
	NSMatrix *matrix;
	NSFont *titleFont;
	NSString *reason = nil;

	check([AGAppleNib validateAppleNibArchive:plist reason:&reason],
	      "the container fixture validates");
	check([NSNib refusalReasonForArchiveData:data] == nil, "the container fixture is accepted");

	path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"agora-apple-nib-layout.nib"];
	[data writeToFile:path atomically:YES];
	nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
	check([nib instantiateNibWithOwner:nil topLevelObjects:&top],
	      "the container nib instantiates");
	view = [top count] == 1 ? [top objectAtIndex:0] : nil;
	subviews = [view subviews];
	check([subviews count] == 3, "the container view keeps all three children");
	box = [subviews count] == 3 ? [subviews objectAtIndex:0] : nil;
	scroll = [subviews count] == 3 ? [subviews objectAtIndex:1] : nil;
	slider = [subviews count] == 3 ? [subviews objectAtIndex:2] : nil;

	check([box isKindOfClass:[NSBox class]], "NSBox becomes an NSBox");
	check([[box title] isEqualToString:@"Group"], "NSTitleCell becomes the box's title");
	check([box contentView] != nil && [box contentView] != (NSView *)box,
	      "NSContentView becomes the box's content view");
	check(NSEqualSizes([box contentViewMargins], NSMakeSize(3, 3)),
	      "NSOffsets becomes the content view margins");
	check([[box contentView] superview] == (NSView *)box && [[box subviews] count] == 1,
	      "the content view is not added twice");
	titleFont = [[box titleCell] font];
	check([titleFont isKindOfClass:[NSFont class]] && [titleFont pointSize] == 13.0,
	      "NSSupport becomes the title cell's font");
	check_color([[box titleCell] textColor], 0.0, 0.0, 1.0,
		    "NSTextColor becomes the cell's text colour");
	check_color([[box titleCell] backgroundColor], 0.8, 0.8, 0.8,
		    "NSBackgroundColor becomes the cell's background");
	check([[box titleCell] drawsBackground], "NSDrawsBackground is translated");

	check([scroll isKindOfClass:[NSScrollView class]], "NSScrollView becomes an NSScrollView");
	check([scroll hasVerticalScroller] && [scroll hasHorizontalScroller],
	      "NSsFlags creates both scrollers");
	check_color([(NSClipView *)[scroll contentView] backgroundColor], 0.8, 0.8, 0.8,
		    "a catalog NSBGColor resolves through its fallback");
	check([[scroll contentView] isKindOfClass:[NSClipView class]],
	      "NSContentView becomes the clip view");
	matrix = (NSMatrix *)[scroll documentView];
	check([matrix isKindOfClass:[NSMatrix class]], "NSDocView becomes the document view");
	check([matrix numberOfRows] == 2 && [matrix numberOfColumns] == 1,
	      "the flat NSCells regroup into two rows by one column");
	check([[[matrix cellAtRow:0 column:0] title] isEqualToString:@"A"] &&
	      [[[matrix cellAtRow:1 column:0] title] isEqualToString:@"B"],
	      "the matrix's cell titles travel");
	check([matrix selectedRow] == 0 && [matrix selectedColumn] == 0,
	      "NSSelectedCell becomes the selected slot");
	check_color([matrix backgroundColor], 1.0, 0.0, 0.0,
		    "NSMatrix NSBackgroundColor is translated");
	check_color([matrix cellBackgroundColor], 0.25, 0.25, 0.25,
		    "NSMatrix NSCellBackgroundColor is translated");

	check([slider isKindOfClass:[NSSlider class]], "NSSlider becomes an NSSlider");
	check([[[slider cell] class] isSubclassOfClass:[NSSliderCell class]],
	      "NSSliderCell becomes the slider's cell");
	check([slider minValue] == 0.0 && [slider maxValue] == 10.0 && [slider doubleValue] == 4.0,
	      "the slider's value range and value travel");
	check([slider numberOfTickMarks] == 3 && [slider tickMarkPosition] == 1 &&
	      [slider allowsTickMarkValuesOnly],
	      "the slider's tick marks travel");

	[nib release];
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
	NSDictionary *plist = build_archive(@"NSTextView", nil, NO);
	NSData *data = archive_data(plist);
	NSString *reason = [NSNib refusalReasonForArchiveData:data];

	check(reason != nil && [reason rangeOfString:@"NSTextView"].location != NSNotFound,
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
	test_layout_translation();

	[pool drain];
	printf(g_fail ? "apple_nib: FAIL\n" : "apple_nib: all checks passed\n");
	return g_fail ? 1 : 0;
}
