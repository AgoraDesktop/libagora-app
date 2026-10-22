/*
 * search_field.m — A FIELD WITH TWO ORNAMENTS: THE MAGNIFIER, THE CLEAR BUTTON, AND WHAT TYPING SENDS.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE CLAIMS ARE OF THREE KINDS, AND EACH IS READ WHERE IT LIVES.** The GEOMETRY is read from the published
 * rectangles (the text sits between the ornaments, and the editor lands on the same rect). The INK is read from a
 * bitmap — a magnifier in the left slot, a clear circle that is absent until there is text and present after. And the
 * BEHAVIOUR is driven through the same doors a person does: a press built by hand, a real field editor's string, the
 * Return key and a fired timer. No display and no run loop are needed for any of it.
 *
 * **THE TIMER IS FIRED BY HAND BECAUSE THIS PROBE DOES NOT RUN A LOOP.** That is the one piece of the delayed search
 * that a test can reach without waiting: the cell exposes its pending timer, and firing it is exactly what the run
 * loop would do. The firing is not a shortcut around the code — it is the code.
 */
#import <AppKit/NSSearchField.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSButtonCell.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSText.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSUserDefaults.h>
#include <stdio.h>
#include <stdlib.h>
#include <objc/runtime.h>

#define W 120
#define H 22

static int failures = 0;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

static NSBitmapImageRep *new_rep(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
}

static NSBitmapImageRep *draw_cell(NSSearchFieldCell *cell)
{
	NSBitmapImageRep *rep = new_rep();
	NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H)] fill];
	[cell drawWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H) inView:view];
	[view release];
	return rep;
}

/* **THE INK COUNT, AND THE THRESHOLD IS `control_ink.m`'S.** A glyph is `+controlDarkShadowColor` on a white face,
 * and nothing else in the ornament's slot is below 0.80 — so a count of zero is "nothing was drawn" and a count above
 * zero is "a mark is there", which is the whole of what the geometry cannot say. */
static int ink_in(NSBitmapImageRep *rep, NSRect rect)
{
	int x0 = (int)NSMinX(rect);
	int y0 = (int)NSMinY(rect);
	int x1 = (int)NSMaxX(rect);
	int y1 = (int)NSMaxY(rect);
	int x;
	int y;
	int count = 0;

	for (y = y0; y < y1; y++) {
		for (x = x0; x < x1; x++) {
			NSColor *c = (x >= 0 && y >= 0 && x < W && y < H) ? [rep colorAtX:x y:y] : nil;

			if (c != nil && [c redComponent] < 0.80) {
				count++;
			}
		}
	}
	return count;
}

/* A TARGET THAT COUNTS ITS ACTIONS, because "the search ran" and "it ran once" are different claims. */
@interface Counter : NSObject
{
@public
	int actions;
}
- (void)counted:(id)sender;
@end

@implementation Counter
- (void)counted:(id)sender
{
	(void)sender;
	actions++;
}
@end

/* **A PRESS AT A POINT IN THE FIELD'S OWN COORDINATES, converted to the window's** — which is the conversion the
 * control itself performs and the reason a point in a test can be written in the space the rects are in. */
static NSEvent *press_in_field(NSView *field, NSPoint local)
{
	NSPoint windowPoint = [field convertPoint:local toView:nil];

	return [NSEvent mouseEventWithType:NSLeftMouseDown
				  location:windowPoint
			     modifierFlags:0
				 timestamp:0.0
			      windowNumber:0
				   context:nil
			       eventNumber:1
				clickCount:1
				  pressure:1.0f];
}

/* **A TEMPLATE WITH ALL FOUR PLACEHOLDERS**, which is what a caller's menu looks like and what the built menu has to
 * honour: a title, the recents, a separator, the clear item and the "none" item. */
static NSMenu *make_template(void)
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"template"];
	NSMenuItem *title = [[NSMenuItem alloc] initWithTitle:@"Recent Searches" action:NULL keyEquivalent:@""];
	NSMenuItem *recents = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
	NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:@"Clear Recents" action:NULL keyEquivalent:@""];
	NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"No Recent Searches" action:NULL keyEquivalent:@""];

	[title setTag:NSSearchFieldRecentsTitleMenuItemTag];
	[recents setTag:NSSearchFieldRecentsMenuItemTag];
	[clear setTag:NSSearchFieldClearRecentsMenuItemTag];
	[none setTag:NSSearchFieldNoRecentsMenuItemTag];
	[menu addItem:title];
	[menu addItem:recents];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:clear];
	[menu addItem:none];
	[title release];
	[recents release];
	[clear release];
	[none release];
	return menu;
}

int main(void)
{
	NSAutoreleasePool *pool;

	/* **THE DEFAULTS ROOT IS A TEMP DIRECTORY, NOT THE TEST RUNNER'S `/Users/...`.** `NSUserDefaults` writes
	 * under `FNX_CONFIG_ROOT`, which is empty by default — the same environment the table's and split view's autosave
	 * probes set, and the reason this probe can exercise a real save and load without touching anything of the
	 * user's. */
	setenv("FNX_CONFIG_ROOT", "/tmp/agora-search-field-defaults", 1);
	pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 360.0, 160.0)
						       styleMask:NSBorderlessWindowMask
							 backing:NSBackingStoreBuffered
							   defer:NO];
	NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 160.0)];
	NSSearchField *field = [[NSSearchField alloc] initWithFrame:NSMakeRect(10.0, 100.0, (CGFloat)W, (CGFloat)H)];
	NSSearchFieldCell *cell = (NSSearchFieldCell *)[field cell];
	Counter *counter = [[Counter alloc] init];
	NSRect bounds = NSMakeRect(0.0, 0.0, (CGFloat)W, (CGFloat)H);
	NSRect searchRect;
	NSRect cancelRect;
	NSRect textRect;
	NSTextFieldCell *plain;
	NSSize plainSize;
	NSSize searchSize;
	NSBitmapImageRep *rep;
	NSMenu *template;
	NSMenu *menu;
	NSTimer *timer;
	NSString *autosave = @"appkit.searchfield.recents.test";

	[window setContentView:content];
	[content addSubview:field];
	[field setTarget:counter];
	[field setAction:@selector(counted:)];
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:autosave];

	/* 1. **THE CLASS AND ITS DEFAULTS.** A search field is a text field whose cell is the search cell; the four
	 * field flags are set, the face is the rounded one, and the two sending rules start off with the recents at
	 * Apple's default of ten. */
	check([cell isKindOfClass:[NSSearchFieldCell class]], "a search field's cell is an NSSearchFieldCell");
	check([field isEditable] && [field isSelectable], "and it is editable and selectable, like the field it is");
	check([field isBordered] && [field isBezeled], "bordered and bezeled, so it has a face to put ornaments on");
	check([cell bezelStyle] == NSTextFieldRoundedBezel, "with the rounded face, which is a search field's shape");
	check([[cell placeholderString] isEqualToString:@"Search"], "and it opens saying Search");
	check([cell maximumRecents] == 10, "ten recents is the default, which is what -1 asks for");
	check(![cell sendsWholeSearchString] && ![cell sendsSearchStringImmediately],
	      "and typing is delayed rather than sent on every key or only on Return");
	check([[cell recentSearches] count] == 0, "with an empty recents list");

	/* 2. **THE LAYOUT IS THREE RECTANGLES THAT DO NOT OVERLAP.** The magnifier is at the left edge, the clear button
	 * at the right, and the text lives strictly between them — which is what keeps a glyph from being drawn over a
	 * value, and what the editor inherits because it uses the same drawing rect. */
	searchRect = [cell searchButtonRectForBounds:bounds];
	cancelRect = [cell cancelButtonRectForBounds:bounds];
	textRect = [cell searchTextRectForBounds:bounds];
	check(NSMinX(searchRect) < NSMinX(textRect), "the magnifier is left of the text");
	check(NSMaxX(searchRect) + 1.0 < NSMinX(textRect), "with air between them, not an overlap");
	check(NSMaxX(textRect) < NSMinX(cancelRect), "and the text stops before the clear button");
	check(NSMaxX(cancelRect) < NSMaxX(bounds), "which is itself inside the field's right edge");
	check(NSMaxY(searchRect) <= NSMaxY(bounds) && NSMinY(searchRect) >= NSMinY(bounds),
	      "the magnifier is inside the field vertically");
	check(NSEqualRects(textRect, [cell drawingRectForBounds:bounds]),
	      "and -drawingRectForBounds: is that same text rect, which is how the drawn string and the editor agree");

	/* 3. **AND THE MEASUREMENT PAYS FOR BOTH SLOTS.** A search field is wider than the same text in a plain field by
	 * the two ornaments, and no taller. */
	[cell setStringValue:@"query"];
	plain = [[NSTextFieldCell alloc] initTextCell:@"query"];
	[plain setBordered:YES];
	[plain setBezeled:YES];
	plainSize = [plain cellSizeForBounds:NSMakeRect(0.0, 0.0, 1000.0, 22.0)];
	searchSize = [cell cellSizeForBounds:NSMakeRect(0.0, 0.0, 1000.0, 22.0)];
	check(searchSize.width >= plainSize.width + 40.0,
	      "the natural width includes the magnifier's and the clear button's slots");
	check(searchSize.height <= plainSize.height + 0.01 && searchSize.height >= plainSize.height - 0.01,
	      "and the ornaments add no height");
	[plain release];

	/* 4. **THE CLEAR BUTTON APPEARS WITH THE TEXT, IN EITHER SPELLING OF A VALUE.** It exists from birth, it is simply
	 * not drawn while there is nothing to clear; the slot is reserved either way, so the editor does not move when the
	 * first character reveals it. */
	[cell setStringValue:@""];
	check([cell cancelButtonCell] != nil, "the clear button cell exists even when the button is hidden");
	check([cell searchButtonCell] != nil, "and so does the magnifier cell");
	check(![cell cg_isCancelVisible], "an empty search field hides the clear button");
	[cell setStringValue:@"abc"];
	check([cell cg_isCancelVisible], "typing or setting a value reveals it");
	[cell setObjectValue:@"xyz"];
	check([cell cg_isCancelVisible], "and the object-value spelling reveals it too");
	[cell setStringValue:@""];
	check(![cell cg_isCancelVisible], "clearing hides it again");
	check(NSEqualRects([cell searchTextRectForBounds:bounds], textRect),
	      "and the text rect did not move while the button came and went");

	/* 5. **THE INK IS WHERE THE RECTANGLES SAY.** A drawn search field carries the magnifier's mark in its slot; the
	 * clear slot carries nothing while hidden and a disc once there is text. */
	[cell setStringValue:@""];
	rep = draw_cell(cell);
	check(ink_in(rep, searchRect) > 0, "the magnifier is DRAWN in its slot");
	check(ink_in(rep, cancelRect) == 0, "and the clear button is not drawn when there is nothing to clear");
	[rep release];
	[cell setStringValue:@"abc"];
	rep = draw_cell(cell);
	check(ink_in(rep, cancelRect) > 0, "with text in the field, the clear button is drawn in its slot");
	check(ink_in(rep, textRect) > 0, "and the value is drawn in the text rect");
	[rep release];

	/* 6. **A PRESS ON AN ORNAMENT DOES NOT BECOME AN EDIT.** The conversion and the hit test are the control's, so a
	 * window point lands on the right rectangle. The clear button clears AND sends (an empty search is a result), the
	 * magnifier sends when there is no recents menu, and a press between them opens the field's session as usual. */
	[field setStringValue:@"hello"];
	[cell cg_handleClickAtPoint:NSMakePoint(NSMidX([cell cancelButtonRectForBounds:[field bounds]]),
						NSMidY([cell cancelButtonRectForBounds:[field bounds]]))
			      inView:field];
	check([[field stringValue] length] == 0, "a press on the clear button empties the field");
	check(counter->actions == 1, "and sends the control's action once");
	[cell cg_handleClickAtPoint:NSMakePoint(NSMidX(searchRect), NSMidY(searchRect)) inView:field];
	check(counter->actions == 2, "a press on the magnifier sends the search when there is no template");
	check([cell cg_handleClickAtPoint:NSMakePoint(NSMidX(textRect), NSMidY(textRect)) inView:field] == NO,
	      "and a press in the text is the field's own press, not an ornament's");

	[field setStringValue:@"hello"];
	[field mouseDown:press_in_field(field, NSMakePoint(NSMidX([cell cancelButtonRectForBounds:[field bounds]]),
							   NSMidY([cell cancelButtonRectForBounds:[field bounds]])))];
	check([[field stringValue] length] == 0 && [field currentEditor] == nil,
	      "through -mouseDown:, a press on the clear button clears without opening an editor");
	[field mouseDown:press_in_field(field, NSMakePoint(NSMidX(textRect), NSMidY(textRect)))];
	check([field currentEditor] != nil, "and a press in the text opens a session");
	check(NSEqualRects([(NSText *)[field currentEditor] frame], [cell searchTextRectForBounds:[field bounds]]),
	      "the editor is put in the TEXT rect, between the ornaments, rather than over the whole field");
	[field abortEditing];

	/* 7. **TYPING IS A DELAYED SEND, AND THE TIMER IS THE DELAY.** A change arms one timer; firing it sends once. The
	 * immediate rule sends on the change and arms nothing; the whole-string rule sends only on Return. **AND THE
	 * RECENTS UI IS OPT-IN:** with no template there is no menu, and the cell does not remember a term behind a UI that
	 * cannot show it — so the template goes on here, before the Return that is checked below. */
	check([cell cg_searchMenu] == nil, "no template means no recents menu");
	template = make_template();
	[cell setSearchMenuTemplate:template];
	counter->actions = 0;
	[field setStringValue:@""];
	[field selectText:nil];
	{
		NSText *editor = (NSText *)[field currentEditor];
		NSEvent *returnKey;
		(void)returnKey;

		[editor replaceCharactersInRange:NSMakeRange(0, 0) withString:@"a"];
		check(counter->actions == 0, "an ordinary change does not send immediately");
		timer = [cell cg_partialStringTimer];
		check(timer != nil, "it arms the partial-string timer instead");
		if (timer != nil) {
			[timer fire];
		}
		check(counter->actions == 1, "and firing the timer sends the search once");
		check([cell cg_partialStringTimer] == nil, "the timer is gone after it fires");

		[cell setSendsSearchStringImmediately:YES];
		[editor replaceCharactersInRange:NSMakeRange([[editor string] length], 0) withString:@"b"];
		check(counter->actions == 2, "the immediate rule sends on the change itself");
		check([cell cg_partialStringTimer] == nil, "and arms no timer");

		[cell setSendsWholeSearchString:YES];
		[editor replaceCharactersInRange:NSMakeRange([[editor string] length], 0) withString:@"c"];
		check(counter->actions == 2, "the whole-string rule sends nothing while typing");
		check([cell cg_partialStringTimer] == nil, "and still arms no timer");
		[editor insertNewline:nil];
		check(counter->actions == 3, "Return sends the whole string");
		check([[[cell recentSearches] objectAtIndex:0] isEqualToString:@"abc"],
		      "and the committed term is remembered as the newest recent");
		check([field currentEditor] == nil, "the session is over");
	}
	/* **AND A VALUE THE CODE WRITES DOES NOT ALSO SEND.** Writing a string tells a live editor, which produces the
	 * same change notification a key does; the programmatic flag is what keeps one choice from becoming two searches.
	 * This is also what makes the clear button and a chosen recent send exactly once. */
	[cell setSendsWholeSearchString:NO];
	[cell setSendsSearchStringImmediately:YES];
	counter->actions = 0;
	[field selectText:nil];
	{
		NSText *editor = (NSText *)[field currentEditor];

		[editor replaceCharactersInRange:NSMakeRange([[editor string] length], 0) withString:@"x"];
		check(counter->actions == 1, "the immediate rule sends once for a keystroke");
		[cell setStringValue:@"written by code"];
		check(counter->actions == 1, "and a value written by code adds no second send");
		[field abortEditing];
	}
	[cell setSendsSearchStringImmediately:NO];

	/* 8. **THE RECENTS ARE A BOUNDED, DEDUPED LIST, AND THE AUTOSAVE NAME BOTH STORES AND LOADS.** A repeat moves to
	 * the front; the limit truncates from the end; -1 restores ten and 300 clamps at 254; and a second cell with the
	 * same name opens with what the first saved. */
	[cell setRecentSearches:[NSArray arrayWithObjects:@"one", @"two", @"three", nil]];
	check([[cell recentSearches] count] == 3, "setRecentSearches: replaces the list");
	check([[[cell recentSearches] objectAtIndex:0] isEqualToString:@"one"], "in the order it was given");
	[cell setMaximumRecents:2];
	check([[cell recentSearches] count] == 2, "a shorter limit truncates the list");
	check([[[cell recentSearches] objectAtIndex:1] isEqualToString:@"two"], "keeping the newest entries");
	[cell setMaximumRecents:300];
	check([cell maximumRecents] == 254, "the maximum clamps at 254");
	[cell setMaximumRecents:-1];
	check([cell maximumRecents] == 10, "and -1 restores the default of ten");

	[cell setRecentSearches:[NSArray arrayWithObjects:@"alpha", @"beta", nil]];
	[cell setRecentsAutosaveName:autosave];
	{
		NSSearchFieldCell *second = [[NSSearchFieldCell alloc] initTextCell:@""];

		[second setRecentsAutosaveName:autosave];
		check([[second recentSearches] count] == 2, "a cell with the same autosave name loads the saved list");
		check([[[second recentSearches] objectAtIndex:0] isEqualToString:@"alpha"], "with its order intact");
		[second release];
	}
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:autosave];

	/* 9. **THE TEMPLATE IS THE RECENTS UI, AND THE TAGS SAY WHERE THE PIECES GO.** With recents, the title and the
	 * items and the clear item appear and the "none" item does not; with no recents, the reverse. The template itself
	 * is untouched — the built menu is a copy. */
	check([cell searchMenuTemplate] == template, "the template is the object that was set");
	[cell setRecentSearches:[NSArray arrayWithObjects:@"one", @"two", nil]];
	menu = [cell cg_searchMenu];
	check([menu itemWithTitle:@"one"] != nil && [menu itemWithTitle:@"two"] != nil,
	      "the built menu contains the recents");
	check([menu itemWithTitle:@"Clear Recents"] != nil, "and a clear item, because there is something to clear");
	check([menu itemWithTitle:@"No Recent Searches"] == nil, "and no no-recents item");
	check([template numberOfItems] == 5, "the template itself is unchanged");

	{
		NSMenuItem *clear = [menu itemWithTitle:@"Clear Recents"];

		[[NSApplication sharedApplication] sendAction:[clear action] to:[clear target] from:clear];
		check([[cell recentSearches] count] == 0, "the clear item empties the list");
	}
	menu = [cell cg_searchMenu];
	check([menu itemWithTitle:@"Recent Searches"] == nil, "with no recents, the title item is gone");
	check([menu itemWithTitle:@"No Recent Searches"] != nil, "and the no-recents item takes its place");
	check([menu itemWithTitle:@"Clear Recents"] == nil, "and there is nothing to clear");

	[cell setRecentSearches:[NSArray arrayWithObjects:@"pick me", nil]];
	menu = [cell cg_searchMenu];
	{
		NSMenuItem *pick = [menu itemWithTitle:@"pick me"];

		check(pick != nil && [pick representedObject] != nil, "a recent item carries its term");
		counter->actions = 0;
		[[NSApplication sharedApplication] sendAction:[pick action] to:[pick target] from:pick];
		check([[field stringValue] isEqualToString:@"pick me"], "choosing a recent puts it in the field");
		check(counter->actions == 1, "and sends the search once");
	}
	[cell setSearchMenuTemplate:nil];
	check([cell cg_searchMenu] == nil, "clearing the template clears the menu");
	[template release];

	/* 10. **THE ORNAMENT CELLS ARE REPLACEABLE AND RESETTABLE.** A caller's cell takes the host's target and action;
	 * resetting builds a fresh default with no image, which is the state the drawn glyph needs. */
	{
		NSButtonCell *custom = [[NSButtonCell alloc] initTextCell:@"S"];

		[cell setSearchButtonCell:custom];
		check([cell searchButtonCell] == custom, "a caller's search button cell is the one the host keeps");
		check([custom target] == cell && sel_isEqual([custom action], @selector(search:)),
		      "and its target and action are the host's, so its click reaches -search:");
		[cell resetSearchButtonCell];
		check([cell searchButtonCell] != custom, "resetting replaces it with a fresh default");
		check([[cell searchButtonCell] image] == nil, "which has no image, because its mark is drawn");
		[cell setCancelButtonCell:custom];
		check(sel_isEqual([custom action], @selector(cancel:)), "the same pairing for the clear button");
		[cell resetCancelButtonCell];
		[custom release];
	}

	[field release];
	[content release];
	[window release];
	[counter release];
	[pool release];

	printf("search_field: %s\n", failures == 0 ? "all checks passed" : "FAILED");
	return failures == 0 ? 0 : 1;
}
