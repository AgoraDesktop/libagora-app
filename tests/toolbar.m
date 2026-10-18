/*
 * toolbar — does the strip have items, a band of its own, a click and a selection?
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **THE TOOLBAR IS FOUR CONTRACTS AT ONCE, SO THIS ASKS ALL FOUR.** It is a DELEGATE-driven list (the default
 * identifiers become items, in order), a FRAME's band (showing it preserves the content and grows the window),
 * a VIEW (the strip draws a ground, a baseline and a label, and a custom item view is a real subview), and a
 * CONTROL (a press and release perform the item and take the selection). A test that only counted items would
 * pass with a toolbar that painted nothing; a test that only read pixels would pass with one whose click did
 * nothing. This file asks each question where it lives.
 *
 * EVERYTHING HERE IS OFFSCREEN. `NSWindow`'s toolbar geometry and the toolbar's own drawing need no compositor —
 * the same reason `tests/window_chrome.m` can exist — so the test runs anywhere the library loads.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSToolbar.h>
#import <AppKit/NSToolbarItem.h>
#import <AppKit/NSToolbar_internal.h>
#import <AppKit/AGChromeTheme.h>

#include <stdio.h>
#include <math.h>

/* THE CHROME-BUTTON DOOR IS PRIVATE TO NSWindow.m; the test redeclares it, the tree's pattern for a second caller. */
@interface NSWindow (AGToolbarTestDoor)
- (void)cg_performChromeButton:(NSInteger)index;
@end

#define TW 400
#define TH 300

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static double lum(NSColor *c)
{
	return c == nil ? 2.0 : ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3.0;
}

static int same_colour(NSColor *a, NSColor *b, double tol)
{
	return a != nil && b != nil
		&& fabs([a redComponent] - [b redComponent]) < tol
		&& fabs([a greenComponent] - [b greenComponent]) < tol
		&& fabs([a blueComponent] - [b blueComponent]) < tol;
}

/* THE TARGET THAT VALIDATES. It counts the questions, answers what it was told, and MAY CHANGE THE ITEM WHILE IT
 * ANSWERS — the second half of the protocol and the reason the walk has to call it rather than guess. */
@interface AGToolbarTarget : NSObject
{
@public
	int validates;
	int actions;
	BOOL answer;
	BOOL changesTag;
}
- (void)perform:(id)sender;
@end

@implementation AGToolbarTarget
- (void)perform:(id)sender
{
	(void)sender;
	actions++;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
	validates++;
	if (changesTag) {
		[theItem setTag:77];
	}
	return answer;
}
@end

/* THE DELEGATE. Every non-spacer identifier gets a labelled item with the validation target; the three spacers are
 * left to the toolbar's own fallback, which is the half a delegate should not have to provide. */
@interface AGToolbarDelegate : NSObject <NSToolbarDelegate>
{
@public
	int willAdd;
	int didRemove;
	int itemRequests;
	AGToolbarTarget *target;
	NSToolbarItem *customItem;	/* NOT RETAINED: the test owns it */
	BOOL selectable;
}
@end

@implementation AGToolbarDelegate
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
	NSToolbarItem *item;

	(void)toolbar;
	(void)flag;
	itemRequests++;
	if ([itemIdentifier isEqualToString:@"custom"] && customItem != nil) {
		return customItem;
	}
	if ([itemIdentifier isEqualToString:NSToolbarSeparatorItemIdentifier] ||
	    [itemIdentifier isEqualToString:NSToolbarSpaceItemIdentifier] ||
	    [itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]) {
		return nil;
	}
	item = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
	[item setLabel:itemIdentifier];
	[item setTarget:target];
	[item setAction:@selector(perform:)];
	return item;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	(void)toolbar;
	return [NSArray arrayWithObjects:@"one", @"two", NSToolbarSeparatorItemIdentifier,
					 @"three", NSToolbarFlexibleSpaceItemIdentifier, @"four", nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	(void)toolbar;
	return [NSArray arrayWithObjects:@"one", @"two", @"three", @"four",
					 NSToolbarSeparatorItemIdentifier, NSToolbarSpaceItemIdentifier,
					 NSToolbarFlexibleSpaceItemIdentifier, nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
	(void)toolbar;
	return selectable ? [NSArray arrayWithObjects:@"one", @"two", nil] : nil;
}

- (void)toolbarWillAddItem:(NSNotification *)notification
{
	(void)notification;
	willAdd++;
}

- (void)toolbarDidRemoveItem:(NSNotification *)notification
{
	(void)notification;
	didRemove++;
}
@end

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	AGToolbarDelegate *delegate = [[AGToolbarDelegate alloc] init];
	AGToolbarTarget *target = [[AGToolbarTarget alloc] init];
	NSToolbar *toolbar;
	NSWindow *window;
	NSView *content;
	NSView *toolbarView;
	NSBitmapImageRep *rep;
	NSGraphicsContext *ctx;
	NSDictionary *configuration;
	NSArray *items;
	NSRect frame;
	NSRect before;
	NSRect contentBefore;
	NSUInteger count;
	int i;
	int ink = 0;

	setvbuf(stdout, NULL, _IONBF, 0);
	[application finishLaunching];

	delegate->target = target;
	delegate->selectable = YES;
	target->answer = YES;

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, TW, TH)
					     styleMask:(NSTitledWindowMask | NSClosableWindowMask |
							NSMiniaturizableWindowMask | NSResizableWindowMask)
					       backing:NSBackingStoreBuffered defer:NO];
	content = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, TW, TH)] autorelease];
	[window setContentView:content];

	before = [window frame];
	toolbar = [[NSToolbar alloc] initWithIdentifier:@"AGToolbarProbe"];
	[toolbar setDelegate:delegate];
	[window setToolbar:toolbar];

	/* 1. ATTACHING GROWS THE FRAME BY THE BAND AND KEEPS THE CONTENT. */
	check([window toolbar] == toolbar, "the window answers the toolbar it was given");
	check([window frame].size.height == before.size.height + [toolbar cg_toolbarHeight],
	      "attaching a toolbar grows the frame by exactly the band's height");
	check([window contentRectForFrameRect:[window frame]].size.height == TH,
	      "and the content keeps the size it had");
	contentBefore = [content frame];
	check(contentBefore.size.height == TH && contentBefore.size.width == TW,
	      "the content view is laid out in the content rect, not in the band");

	/* 2. THE DELEGATE'S DEFAULT LIST BECOMES THE ITEM ORDER. */
	items = [toolbar items];
	check([items count] == 6, "the six default identifiers became six items");
	check([[[items objectAtIndex:0] itemIdentifier] isEqualToString:@"one"]
	      && [[[items objectAtIndex:1] itemIdentifier] isEqualToString:@"two"]
	      && [[[items objectAtIndex:2] itemIdentifier] isEqualToString:NSToolbarSeparatorItemIdentifier]
	      && [[[items objectAtIndex:3] itemIdentifier] isEqualToString:@"three"]
	      && [[[items objectAtIndex:4] itemIdentifier] isEqualToString:NSToolbarFlexibleSpaceItemIdentifier]
	      && [[[items objectAtIndex:5] itemIdentifier] isEqualToString:@"four"],
	      "in the order the delegate gave them, spacers included");
	check(delegate->willAdd == 6, "each addition was announced to the delegate");
	check([[toolbar visibleItems] count] == 6, "every item fits the 400-point band");
	toolbarView = [toolbar cg_view];
	check([toolbarView superview] == content, "the toolbar's view is a real subview of the content view");
	check([toolbarView frame].origin.y == TH, "and it sits at the content's top edge");

	/* 3. INSERT AND REMOVE, WITH THE NOTIFICATIONS BOTH WAYS. */
	[toolbar insertItemWithItemIdentifier:@"five" atIndex:1];
	items = [toolbar items];
	check([items count] == 7 && [[[items objectAtIndex:1] itemIdentifier] isEqualToString:@"five"],
	      "an explicit insertion lands at its index");
	check(delegate->willAdd == 7, "and it is announced");
	[toolbar removeItemAtIndex:1];
	check([[toolbar items] count] == 6 && delegate->didRemove == 1,
	      "removing one shortens the list and announces the removal");

	/* 4. A CUSTOM VIEW IS ADOPTED, PLACED AT ITS ITEM, AND LET GO. */
	{
		NSView *custom = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 24.0)] autorelease];
		NSToolbarItem *customItem = [[[NSToolbarItem alloc] initWithItemIdentifier:@"custom"] autorelease];

		[customItem setLabel:@"custom"];
		[customItem setView:custom];
		[customItem setMinSize:NSMakeSize(40.0, 24.0)];
		[customItem setMaxSize:NSMakeSize(40.0, 24.0)];
		delegate->customItem = customItem;
		[toolbar insertItemWithItemIdentifier:@"custom" atIndex:0];
		check([[toolbar items] count] == 7, "a custom item is inserted through the delegate");
		check([custom superview] == toolbarView, "its view is adopted by the toolbar's view");
		check([custom frame].size.width == 40.0 && [custom frame].size.height == 24.0,
		      "and it is placed at the size the item asked for");
		[toolbar removeItemAtIndex:0];
		delegate->customItem = nil;
		check([custom superview] == nil, "removing the item takes its view out of the tree");
	}

	/* 5. VALIDATION IS THE TARGET'S TO DECIDE, AND MAY CHANGE THE ITEM. */
	{
		NSToolbarItem *item = [[toolbar items] objectAtIndex:0];

		target->answer = NO;
		target->validates = 0;
		[item validate];
		check(![item isEnabled] && target->validates == 1, "a validator that says no disables the item");
		target->answer = YES;
		target->changesTag = YES;
		[item validate];
		check([item isEnabled] && [item tag] == 77, "and a validator may change the item while it answers");
		target->changesTag = NO;
		target->validates = 0;
		[toolbar validateVisibleItems];
		check(target->validates > 0, "the toolbar validates its visible items");
	}

	/* 6. A PRESS AND A RELEASE PERFORM THE ITEM AND TAKE THE SELECTION. */
	{
		NSRect f = [toolbarView frame];
		NSPoint at = NSMakePoint(18.0, f.origin.y + f.size.height / 2.0);
		NSEvent *down = mouse(NSLeftMouseDown, at, [window windowNumber]);
		NSEvent *up = mouse(NSLeftMouseUp, at, [window windowNumber]);
		int actions = target->actions;

		[toolbarView mouseDown:down];
		[toolbarView mouseUp:up];
		check(target->actions == actions + 1, "a click on an item sends its action");
		check([[[toolbar selectedItemIdentifier] description] isEqualToString:@"one"],
		      "an identifier in the delegate's selectable list becomes the selection");
	}

	/* 7. THE SIZE MODE AND THE CONFIGURATION DICTIONARY. */
	frame = [window frame];
	[toolbar setSizeMode:NSToolbarSizeModeSmall];
	check([window frame].size.height == frame.size.height - 14.0 &&
	      [window contentRectForFrameRect:[window frame]].size.height == TH,
	      "small mode shrinks the band and preserves the content");
	[toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[toolbar setSelectedItemIdentifier:@"two"];
	configuration = [toolbar configurationDictionary];
	[toolbar setSelectedItemIdentifier:nil];
	[toolbar setDisplayMode:NSToolbarDisplayModeDefault];
	[toolbar setSizeMode:NSToolbarSizeModeRegular];
	[toolbar setConfigurationFromDictionary:configuration];
	check([toolbar sizeMode] == NSToolbarSizeModeSmall &&
	      [toolbar displayMode] == NSToolbarDisplayModeIconOnly &&
	      [[[toolbar selectedItemIdentifier] description] isEqualToString:@"two"],
	      "the configuration dictionary round-trips the item list, modes and selection");
	check([[toolbar items] count] == 6, "and the item list survives the round trip");
	[toolbar setSizeMode:NSToolbarSizeModeRegular];
	[toolbar setDisplayMode:NSToolbarDisplayModeDefault];
	[toolbar setSelectedItemIdentifier:@"one"];

	/* 8. THE INK: A GROUND, A BASELINE, A LABEL, AND THE CHROME ABOVE IT.
	 *
	 * **THE REP IS READ TOP-DOWN, WHICH IS THE ONE COORDINATE FACT THIS FILE HAS TO REMEMBER.** `-colorAtX:y:` counts
	 * rows from the TOP of the bitmap, while the window draws from the BOTTOM; the band's window rows `300..351` are
	 * therefore rep rows `22..73` in a `374`-row rep. The first version of this test asked for the window's rows and
	 * found white — the content below the band — which is exactly the mistake the chrome's own test documents. */
	{
		const int fh = (int)(TH + 22.0 + [toolbar cg_toolbarHeight]);
		const int bandTop = fh - (int)(TH + [toolbar cg_toolbarHeight]);	/* 22: the chrome's height */
		const int bandBottom = fh - (int)TH - 1;				/* 73: the band's bottom row */

		rep = new_rep(TW, fh);
		ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
		[NSGraphicsContext setCurrentContext:ctx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)TW, (CGFloat)fh)] fill];
		/* THE BAND ALONE, THEN THE LIVE WINDOW'S CONTENT WALK. The second is the one that found the invisible-toolbar
		 * defect: the band drew correctly when asked for its own rect, and the content tree's walk never reached it. */
		[window cg_drawToolbarInContext:ctx];
		[window cg_drawChromeInContext:ctx];
		check(same_colour([rep colorAtX:2 y:bandTop + 8], [NSColor windowFrameColor], 0.02),
		      "the toolbar band is filled with the chrome's own windowFrameColor");
		/* THE HAIRLINE IS THE CONTENT'S TOP ROW, one row BELOW the band — the chrome painter draws it, not the
		 * toolbar's own view, because the band is part of the chrome. */
		check(lum([rep colorAtX:2 y:bandBottom + 1]) < lum([rep colorAtX:2 y:bandTop + 8]),
		      "the black hairline is at the content's top edge, below the band");
		for (i = 0; i < TW; i++) {
			int y;

			for (y = bandTop; y <= bandBottom; y++) {
				NSColor *pixel = [rep colorAtX:i y:y];

				if (pixel != nil && lum(pixel) < 0.55) {
					ink++;
				}
			}
		}
		check(ink > 0, "an item's label is drawn as ink inside the band");
		check(same_colour([rep colorAtX:2 y:6], [NSColor windowFrameColor], 0.02)
		      && same_colour([rep colorAtX:2 y:6], [rep colorAtX:2 y:bandTop + 8], 0.02),
		      "the title bar above it is the SAME chrome ground, so the band is part of the chrome");
	}

	/* **AND THE SAME BAND THROUGH THE WINDOW'S OWN CONTENT WALK.** This is the path a live window uses, and it is
	 * the one that was blank while the band-only draw above was correct. */
	{
		const int fh = (int)(TH + 22.0 + [toolbar cg_toolbarHeight]);
		const int bandTop = fh - (int)(TH + [toolbar cg_toolbarHeight]);
		const int bandBottom = fh - (int)TH - 1;
		NSBitmapImageRep *contentRep = new_rep(TW, fh);
		NSGraphicsContext *contentCtx = [NSGraphicsContext graphicsContextWithBitmapImageRep:contentRep];
		int contentInk = 0;

		[NSGraphicsContext setCurrentContext:contentCtx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)TW, (CGFloat)fh)] fill];
		[window cg_drawContentInContext:contentCtx];
		for (i = 0; i < TW; i++) {
			int y;

			for (y = bandTop; y <= bandBottom; y++) {
				NSColor *pixel = [contentRep colorAtX:i y:y];

				if (pixel != nil && lum(pixel) < 0.55) {
					contentInk++;
				}
			}
		}
		check(contentInk > 0, "the content view's own walk reaches the toolbar band and draws its items");
		[contentRep release];
	}

	/* 9. THE TOGGLE DOORS, INCLUDING THE CHROME'S PILL. */
	[window toggleToolbarShown:nil];
	check(![toolbar isVisible], "-toggleToolbarShown: hides the toolbar");
	check([window frame].size.height == before.size.height, "and the frame shrinks back to the chrome and content");
	[window toggleToolbarShown:nil];
	check([toolbar isVisible], "and a second call shows it again");
	[window cg_performChromeButton:AGChromeButtonMenu];
	check(![toolbar isVisible], "the chrome's pill performs the same toggle");
	[window cg_performChromeButton:AGChromeButtonMenu];
	check([toolbar isVisible], "and toggles it back");

	/* 10. REMOVING THE TOOLBAR GIVES THE BAND BACK. */
	frame = [window frame];
	[window setToolbar:nil];
	check([window toolbar] == nil, "a window can lose its toolbar");
	check([window frame].size.height == frame.size.height - [toolbar cg_toolbarHeight],
	      "and the frame gives the band back");
	check([window contentRectForFrameRect:[window frame]].size.height == TH,
	      "while the content keeps its size");

	[toolbar release];
	[window release];
	printf("toolbar: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
