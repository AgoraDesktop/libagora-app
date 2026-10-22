/*
 * toolbar — does the strip have items, a band of its own, a click and a selection?
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
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
#import <AppKit/NSToolbarItemGroup.h>
#import <AppKit/NSToolbar_internal.h>
#import <AppKit/AGChromeTheme.h>

#include <stdio.h>
#include <math.h>

/* THE CHROME-BUTTON DOOR IS PRIVATE TO NSWindow.m; the test redeclares it, the tree's pattern for a second caller. */
@interface NSWindow (AGToolbarTestDoor)
- (void)cg_performChromeButton:(NSInteger)index;
@end

/* AND THE DRAG'S MOVE IS DEFERRED TO THE END OF A PASS, so a probe has to make that pass — the same door
 * `tests/chrome_theme.m` declares for the title bar. */
@interface NSWindow (AGToolbarDragTest)
- (void)cg_applyPendingDrag;
@end

#define TW 400
#define TH 300

static int s_failed;

static int near(double a, double b)
{
	return fabs(a - b) < 0.05;
}

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
	NSToolbarItemGroup *groupItem;	/* NOT RETAINED: the test owns it */
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
	if ([itemIdentifier isEqualToString:@"group"] && groupItem != nil) {
		return groupItem;
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

static NSEvent *mouse_at(int type, NSPoint where, NSInteger windowNumber, double when)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:when windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:1 pressure:1.0f];
}

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber)
{
	return mouse_at(type, where, windowNumber, 0.0);
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

	/* 2b. **THE PRELIGHT IS THE ACCENT, AND A DISABLED ITEM DOES NOT TAKE ONE.** A borderless toolbar item's
	 * background is the band's until the pointer answers it; the prelight this draws is the platform accent at a
	 * quarter, so it reads as the item responding rather than as a panel appearing under it — MEASURED, because the
	 * grey it used to be (`+controlHighlightColor`) was LIGHTER than the chrome face. And a disabled item is flat
	 * whatever the pointer does, which is the rule `NSButtonCell` follows for its own face.
	 *
	 * The probe renders the band twice — once with the pointer nowhere, once after a motion over an item's own
	 * rectangle — and compares the pixels inside that rectangle. Nothing here depends on where an item's rectangle
	 * IS: the first item starts at the band's left padding, and the check is "something in that box changed, and
	 * what changed leads in blue". */
	{
		NSBitmapImageRep *beforeRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
			pixelsWide:(NSInteger)TW pixelsHigh:(NSInteger)[toolbar cg_toolbarHeight] bitsPerSample:8
			samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
			bytesPerRow:(NSInteger)TW * 4 bitsPerPixel:32];
		NSBitmapImageRep *afterRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
			pixelsWide:(NSInteger)TW pixelsHigh:(NSInteger)[toolbar cg_toolbarHeight] bitsPerSample:8
			samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
			bytesPerRow:(NSInteger)TW * 4 bitsPerPixel:32];
		unsigned char *a;
		unsigned char *b;
		int x, y, changed = 0, bluest = -1;

		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:beforeRep]];
		[toolbarView displayRect:[toolbarView bounds]];
		a = [beforeRep bitmapData];

		/* THE FIRST ITEM'S OWN RECTANGLE, in the view's coordinates: the band's padding is 8 and its first item is
		 * a labelled one, so 40 points is inside it. The EVENT's location is in the WINDOW's content coordinates,
		 * which is where the view's frame origin has to be added back. */
		[toolbarView mouseMoved:mouse(NSMouseMoved,
					      NSMakePoint(8.0 + 20.0 + [toolbarView frame].origin.x,
							  [toolbarView frame].origin.y +
							  [toolbar cg_toolbarHeight] / 2.0),
					      [window windowNumber])];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:afterRep]];
		[toolbarView displayRect:[toolbarView bounds]];
		b = [afterRep bitmapData];

		for (y = 0; y < (int)[toolbar cg_toolbarHeight]; y++) {
			for (x = 8; x < 48; x++) {
				unsigned char *pa = a + ((size_t)y * (size_t)TW + (size_t)x) * 4u;
				unsigned char *pb = b + ((size_t)y * (size_t)TW + (size_t)x) * 4u;

				if (pa[0] != pb[0] || pa[1] != pb[1] || pa[2] != pb[2]) {
					changed++;
					if (pb[2] > pb[0] && (bluest < 0 || pb[2] - pb[0] > bluest)) {
						bluest = (int)pb[2] - (int)pb[0];
					}
				}
			}
		}
		check(changed > 20, "a pointer over an item paints a plate where the band was flat");
		check(bluest > 6, "and the plate is the ACCENT, not a grey: blue leads red");
		[beforeRep release];
		[afterRep release];
	}

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

	/* 4b. **A GROUP IS ONE ITEM ON SCREEN AND ITS SUBITEMS ARE ADJACENT.** Two tiny custom views prove the
	 * flattening without depending on the standard face's label metrics: the group stays the unit `-items` and
	 * `-visibleItems` report, while the two views are separate subviews laid side by side. */
	{
		NSView *firstView = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 12.0, 24.0)] autorelease];
		NSView *secondView = [[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 12.0, 24.0)] autorelease];
		NSToolbarItem *first = [[[NSToolbarItem alloc] initWithItemIdentifier:@"g1"] autorelease];
		NSToolbarItem *second = [[[NSToolbarItem alloc] initWithItemIdentifier:@"g2"] autorelease];
		NSToolbarItemGroup *group = [[NSToolbarItemGroup alloc] initWithItemIdentifier:@"group"];
		NSArray *visible;

		[first setLabel:@"g1"];
		[first setView:firstView];
		[first setMinSize:NSMakeSize(12.0, 24.0)];
		[first setMaxSize:NSMakeSize(12.0, 24.0)];
		[second setLabel:@"g2"];
		[second setView:secondView];
		[second setMinSize:NSMakeSize(12.0, 24.0)];
		[second setMaxSize:NSMakeSize(12.0, 24.0)];
		[group setSubitems:[NSArray arrayWithObjects:first, second, nil]];
		delegate->groupItem = group;
		[toolbar insertItemWithItemIdentifier:@"group" atIndex:0];
		visible = [toolbar visibleItems];
		check([[toolbar items] count] == 7
		      && [[[toolbar items] objectAtIndex:0] isKindOfClass:[NSToolbarItemGroup class]],
		      "the group is one item in -items");
		check([visible containsObject:group] && ![visible containsObject:first]
		      && ![visible containsObject:second],
		      "and the group, not its subitems, is what -visibleItems reports");
		check([firstView superview] == toolbarView && [secondView superview] == toolbarView,
		      "both subitem views are adopted by the toolbar's view");
		check(near([secondView frame].origin.x, [firstView frame].origin.x + [firstView frame].size.width),
		      "and they are laid out adjacent");
		[toolbar removeItemAtIndex:0];
		delegate->groupItem = nil;
		check([firstView superview] == nil && [secondView superview] == nil,
		      "removing the group takes both subitem views out of the tree");
		[group release];
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
		check(same_colour([rep colorAtX:2 y:bandTop + 8], [NSColor cg_chromeFaceColor], 0.02),
		      "the toolbar band is filled with the chrome's own face colour");
		/* **THE HAIRLINE IS THE CONTENT'S TOP ROW, ONE ROW BELOW THE BAND — AND IT WEARS THE CONTROL BEZEL'S GREY.**
		 * The chrome painter draws it, not the toolbar's own view, because the band is part of the chrome; and it is
		 * `+controlDarkShadowColor`, the same ink a push button's bezel, a field's edge and a checkbox's box are
		 * stroked with, because it is the BOTTOM OF THE CHROME and every other edge on this desktop is that one
		 * grey. It was black, which read as a shadow the window does not otherwise have. */
		check(same_colour([rep colorAtX:2 y:bandBottom + 1], [NSColor controlDarkShadowColor], 0.02),
		      "the chrome's hairline, at the content's top edge below the band, is the bezel's grey");
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
		/* **AND THE TITLE BAR ABOVE IT IS THE SAME COLOUR, WHICH IS THE WHOLE CLAIM.** The strip is ONE surface —
		 * the title bar and the toolbar band are one rectangle in one colour (`+cg_chromeFaceColor`), painted by two
		 * different objects — so what is checked is not that each is a plausible grey but that THE TWO PIXELS ARE THE
		 * SAME, one from above the boundary and one from below it. A chrome that painted them from two doors grew a
		 * seam the moment the numbers drifted, and a seam is exactly what this asks about. */
		check(same_colour([rep colorAtX:2 y:6], [NSColor cg_chromeFaceColor], 0.02),
		      "the title bar above the band is the chrome's face colour");
		check(same_colour([rep colorAtX:2 y:6], [rep colorAtX:2 y:bandTop + 8], 0.002),
		      "and the band below it is the SAME PIXEL — one continuous surface, not two that happen to match");
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

	/* 9. **THE BAND BETWEEN THE ITEMS IS A DRAG HANDLE; THE ITEMS ARE NOT.** A press on the strip that misses every
	 * item used to reach the toolbar's view, which answered "no item" and did nothing — a strip of dead pixels the
	 * width of the window. It now takes hold of the window, the way the title bar above it already did, and the two
	 * halves are in different files: `NSWindow` owns the gesture, `NSToolbar` owns the answer to "is this an item". */
	{
		NSRect dragBefore = [window frame];
		CGFloat bandY = TH + [toolbar cg_toolbarHeight] / 2.0;
		CGFloat itemX = -1.0, freeX = -1.0, x, run = 0.0, longest = 0.0;

		/* THE SCAN STARTS INSIDE THE RESIZE BANDS (five points at each end), so a sample is never an edge's. */
		for (x = 8.0; x < (CGFloat)TW - 8.0; x += 1.0) {
			if ([toolbar cg_pointIsOverControl:NSMakePoint(x, bandY)]) {
				if (itemX < 0.0) itemX = x;
				run = 0.0;
			} else {
				if (freeX < 0.0) freeX = x;
				run += 1.0;
				if (run > longest) longest = run;
			}
		}
		check(itemX >= 0.0 && freeX >= 0.0,
		      "the band has both a control and a point that is not one to take hold of");
		/* **AND THE FLEXIBLE SPACE IS THE WINDOW'S, NOT AN ITEM'S.** The delegate's list has one, so the run of
		 * non-control points between the last real item and the one after it is WIDE; a toolbar that called a
		 * flexible space a control would leave only the few points of air around each item, and this band would be
		 * un-draggable in exactly the place a hand aims for. */
		check(longest > 40.0, "the flexible space between items is part of the handle, not an item");

		if (freeX >= 0.0) {
			[window sendEvent:mouse_at(NSLeftMouseDown, NSMakePoint(freeX, bandY), [window windowNumber], 0.0)];
			[window sendEvent:mouse_at(NSLeftMouseDragged, NSMakePoint(freeX + 40.0, bandY), [window windowNumber], 0.01)];
			[window sendEvent:mouse_at(NSLeftMouseUp, NSMakePoint(freeX + 40.0, bandY), [window windowNumber], 0.02)];
			[window cg_applyPendingDrag];	/* the pass would do this; the probe makes the pass */
			check(near([window frame].origin.x, dragBefore.origin.x + 40.0)
			      && near([window frame].origin.y, dragBefore.origin.y),
			      "a drag on the TOOLBAR between its items moves the window by the pointer's own delta");
		}

		if (itemX >= 0.0) {
			NSRect itemBefore = [window frame];

			[window sendEvent:mouse_at(NSLeftMouseDown, NSMakePoint(itemX, bandY), [window windowNumber], 0.0)];
			[window sendEvent:mouse_at(NSLeftMouseDragged, NSMakePoint(itemX + 40.0, bandY), [window windowNumber], 0.01)];
			[window sendEvent:mouse_at(NSLeftMouseUp, NSMakePoint(itemX + 40.0, bandY), [window windowNumber], 0.02)];
			[window cg_applyPendingDrag];
			check(near([window frame].origin.x, itemBefore.origin.x)
			      && near([window frame].origin.y, itemBefore.origin.y),
			      "and a press on an ITEM does not: the item keeps its pixels");
		}

		/* A WINDOW THAT MAY NOT MOVE KEEPS ITS BAND. `-isMovable` is the switch Apple's header names. */
		[window setMovable:NO];
		if (freeX >= 0.0) {
			NSRect lockedBefore = [window frame];

			[window sendEvent:mouse_at(NSLeftMouseDown, NSMakePoint(freeX, bandY), [window windowNumber], 0.0)];
			[window sendEvent:mouse_at(NSLeftMouseDragged, NSMakePoint(freeX + 40.0, bandY), [window windowNumber], 0.01)];
			[window sendEvent:mouse_at(NSLeftMouseUp, NSMakePoint(freeX + 40.0, bandY), [window windowNumber], 0.02)];
			[window cg_applyPendingDrag];
			check(near([window frame].origin.x, lockedBefore.origin.x),
			      "and an immovable window does not move from the band either");
		}
		[window setMovable:YES];
	}

	/* 10. THE TOGGLE DOORS, INCLUDING THE CHROME'S PILL. */
	[window toggleToolbarShown:nil];
	check(![toolbar isVisible], "-toggleToolbarShown: hides the toolbar");
	check([window frame].size.height == before.size.height, "and the frame shrinks back to the chrome and content");
	[window toggleToolbarShown:nil];
	check([toolbar isVisible], "and a second call shows it again");
	[window cg_performChromeButton:AGChromeButtonMenu];
	check(![toolbar isVisible], "the chrome's pill performs the same toggle");
	[window cg_performChromeButton:AGChromeButtonMenu];
	check([toolbar isVisible], "and toggles it back");

	/* 11. REMOVING THE TOOLBAR GIVES THE BAND BACK. */
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
