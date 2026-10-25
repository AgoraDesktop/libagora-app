/*
 * NSMenuView.m — laying out rows and calling the cells that draw them.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

#include <stdlib.h>
#include <time.h>
#import "NSMenuView.h"
#import "NSWindow.h"
#import "NSMenu.h"
#import "NSMenuItem.h"
#import "NSMenuItemCell.h"
#import "NSColor.h"
#import "NSBezierPath.h"
#import "NSGraphicsContext.h"
#import "AppKitRefusal.h"	/* the refused doors say what they need. */

#import <Foundation/NSArray.h>

const CGFloat NSMenuRowHeight = 22.0;

/* **THE PANEL'S OWN PADDING, WHICH IS THE AIR BETWEEN THE EDGE AND THE FIRST ROW.** The rows used to run EDGE TO
 * EDGE, so the only air inside the panel was the highlight chip's own 2-point inset — which left the chip almost
 * touching the panel's rounded edge. Two points on every side gives the panel a margin — the chip's own inset again,
 * on the panel's behalf — and it is a SHARED number (`NSMenuView.h`) because `NSMenu` sizes the window with it and
 * this view insets the rows by it. */
const CGFloat NSMenuPanelPadding = 2.0;

/* **A WALL-CLOCK MILLISECOND, SO THIS LOG CAN BE LINED UP WITH THE COMPOSITOR'S.** Two logs that each say a click
 * happened cannot be compared without a clock in both, and the question — how long did the press wait before this
 * view saw it — is exactly the difference between the two. MEASURED because a person reported the menu taking five
 * seconds while this file's own timings said 3 ms + 63 ms: something between the two is where that time goes. */
static long long ag_menu_diag_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_REALTIME, &ts);
	return (long long)ts.tv_sec * 1000LL + (long long)(ts.tv_nsec / 1000000L);
}

/* A BAR'S ITEM IS ITS TITLE PLUS THE AIR EITHER SIDE OF IT, and a floor so that a one-letter title is still a
 * target a person can hit. Both are the bar's own measures, so they live beside the bar's drawing. */
#define APPKIT_MENUBAR_TITLE_PADDING  12.0
#define APPKIT_MENUBAR_MIN_ITEM_WIDTH 40.0

/* ============================================================================================ *
 * THE DROPDOWN'S PANEL AND ITS SELECTION, WHICH ARE SNOW LEOPARD'S.                             *
 *                                                                                                *
 * A MENU IS A ROUNDED PANEL WITH NO BORDER — ITS COLOUR IS THE MENU BAR'S — and the row under the  *
 * rounded chip INSET inside that panel — not a full-width bar of colour — with its title and its  *
 * shortcut inked to sit on it. What this replaces filled the entire row with a flat colour and   *
 * left the ink dark, which is none of those three things.                                       *
 *                                                                                                *
 * THE SELECTION IS ARGENTUM'S PERIWINKLE, AND THE INK ON IT IS BLACK. The chip was Snow Leopard's blue with    *
 * white ink for one pass; the desktop's own sampled accent is the periwinkle (164,154,255), and a chip LIGHT     *
 * enough to carry dark ink is exactly what that accent is. So the STRUCTURE stays Snow Leopard's — a rounded     *
 * chip inset inside the panel, with the title and its shortcut inked to match — and the COLOUR is the design's.  *
 * ============================================================================================ */
#define APPKIT_MENU_PANEL_RADIUS     4.0
#define APPKIT_MENU_HIGHLIGHT_INSET  2.0
#define APPKIT_MENU_HIGHLIGHT_RADIUS 3.0
/* **THE ACCENT IS `NSColor`'S, NOT THIS VIEW'S.** These six numbers used to be `#define`s here — the platform's
 * sampled periwinkle, copied into the one file that drew a selection chip — and the moment a CONTROL wanted the same
 * colour there were two of it. `[NSColor cg_accentColor]` is now the single definition and the menu asks for it; the
 * gradient stays (both stops are the accent today, and the shape is what a later two-tone selection uses). */
#define APPKIT_MENU_HIGHLIGHT_RADIUS 3.0

/* **A TWO-STOP VERTICAL GRADIENT IN A ROUNDED RECTANGLE, CLIPPED TO IT.** CoreGraphics owns the ramp and
 * `NSBezierPath` owns the clip; the fallback is the FLAT BOTTOM COLOUR rather than nothing, because a menu chip
 * that vanished when there was no `CGContext` would be a worse bug than one without its gradient. */
static void apk_fill_vertical_gradient(NSRect rect, CGFloat radius,
				       CGFloat tr, CGFloat tg, CGFloat tb,
				       CGFloat br, CGFloat bg, CGFloat bb)
{
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
	CGContextRef c = [[NSGraphicsContext currentContext] CGContext];
	CGFloat components[8];
	CGColorSpaceRef space;
	CGGradientRef gradient;

	if (c == NULL) {
		[[NSColor colorWithCalibratedRed:br green:bg blue:bb alpha:1.0] setFill];
		[path fill];
		return;
	}
	components[0] = tr; components[1] = tg; components[2] = tb; components[3] = 1.0;
	components[4] = br; components[5] = bg; components[6] = bb; components[7] = 1.0;
	space = CGColorSpaceCreateDeviceRGB();
	gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
	if (gradient == NULL) {
		[[NSColor colorWithCalibratedRed:br green:bg blue:bb alpha:1.0] setFill];
		[path fill];
		CGColorSpaceRelease(space);
		return;
	}
	CGContextSaveGState(c);
	[path addClip];
	/* USER SPACE RUNS UP, so the top stop is the rect's MAX y — which is what makes this a gradient from the
	 * top down and not, as the first version of any gradient always is, upside down. */
	CGContextDrawLinearGradient(c, gradient, CGPointMake(NSMidX(rect), NSMaxY(rect)),
				    CGPointMake(NSMidX(rect), NSMinY(rect)), 0);
	CGContextRestoreGState(c);
	CGGradientRelease(gradient);
	CGColorSpaceRelease(space);
}

@implementation NSMenuView

- (id)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		_cells = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_cells release];
	{
		NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];

		[centre removeObserver:self name:NSMenuDidAddItemNotification object:nil];
		[centre removeObserver:self name:NSMenuDidChangeItemNotification object:nil];
		[centre removeObserver:self name:NSMenuDidRemoveItemNotification object:nil];
	}
	[_font release];
	[super dealloc];
}

- (void)setMenu:(NSMenu *)menu
{
	/* A MENU THAT CHANGED IS A LAYOUT THAT CHANGED, so the cells go with it: keeping them would keep the widths
	 * measured from the OLD items and lay the new ones out in the old item's columns. */
	_shownMenu = menu;
	[_cells removeAllObjects];
	[self setNeedsDisplay:YES];

	/* **THE VIEW LISTENS TO THE MENU IT SHOWS**, which is what makes `-itemAdded:`/`-itemChanged:`/`-itemRemoved:` the ONE
	 * path into the cell cache: the menu announces every change and this is the listener, so nothing can edit a menu and
	 * leave a stale cell behind it. */
	{
		NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];

		[centre removeObserver:self name:NSMenuDidAddItemNotification object:nil];
		[centre removeObserver:self name:NSMenuDidChangeItemNotification object:nil];
		[centre removeObserver:self name:NSMenuDidRemoveItemNotification object:nil];
		if (menu != nil) {
			[centre addObserver:self selector:@selector(cg_menuItemsChanged:)
				       name:NSMenuDidAddItemNotification object:menu];
			[centre addObserver:self selector:@selector(cg_menuItemsChanged:)
				       name:NSMenuDidChangeItemNotification object:menu];
			[centre addObserver:self selector:@selector(cg_menuItemsChanged:)
				       name:NSMenuDidRemoveItemNotification object:menu];
		}
	}
}

- (NSMenu *)menu
{
	return _shownMenu;
}

- (NSMenuItemCell *)cg_newItemCell
{
	/* +1: the caller retains it in the row cache and then releases it. See the header. */
	return [[NSMenuItemCell alloc] initTextCell:@""];
}

- (NSRect)cg_markRectForRow:(NSRect)row
{
	/* THE MENU'S OWN CHIP, WHICH IS WHAT THIS VIEW HAS ALWAYS DRAWN: inset inside the row, so that the row still reads
	 * as a row and the chip as a chip. A list answers the row itself. */
	return _horizontal ? NSInsetRect(row, 1.0, 2.0)
			   : NSInsetRect(row, APPKIT_MENU_HIGHLIGHT_INSET, APPKIT_MENU_HIGHLIGHT_INSET);
}

- (NSMenuItemCell *)cellForItemAtIndex:(NSInteger)index
{
	NSMenuItem *item = [_shownMenu itemAtIndex:index];
	NSMenuItemCell *cell;

	if (item == nil) {
		return nil;
	}
	while ((NSInteger)[_cells count] <= index) {
		[_cells addObject:[NSNull null]];
	}
	cell = [_cells objectAtIndex:(NSUInteger)index];
	if ((id)cell == [NSNull null]) {
		cell = [self cg_newItemCell];
		[cell setMenuItem:item];
		/* **A BAR'S FIRST ITEM IS THE APPLICATION MENU, AND THE HIG SETS IT IN BOLD.** That is the whole of why
		 * this view is the one that decides: the first item of a HORIZONTAL menu is the application's own — put
		 * there by `NSApplication`, which is the only thing that knows the application's name — and a DROPDOWN's
		 * first row is just its first row. */
		[cell setBold:(_horizontal && index == 0)];
		/* **MEASURED ONCE, HERE.** `-calcSize` reads `-needsSizing`, so this is the flag that makes the
		 * measurement happen rather than a call that happens to work the first time. */
		[cell setNeedsSizing:YES];
		[cell calcSize];
		[_cells replaceObjectAtIndex:(NSUInteger)index withObject:cell];
		[cell release];
	}
	return cell;
}

- (CGFloat)widthForItemAtIndex:(NSInteger)index
{
	NSMenuItemCell *cell = [self cellForItemAtIndex:index];

	/* **THE TWO ORIENTATIONS MEASURE DIFFERENT THINGS, WHICH IS WHY THIS DOOR ASKS WHICH ONE IT IS.** A DROPDOWN
	 * row is as wide as its own CONTENT — the gutter, the title, the least gap, the shortcut, the right padding —
	 * and the menu is as wide as its widest row. A BAR column is just its title and its air, and the bar is the
	 * SUM of them. */
	if (!_horizontal) {
		CGFloat width = APPKIT_MENU_LEFT_GUTTER + [cell titleWidth] + APPKIT_MENU_RIGHT_PADDING;

		if ([cell keyEquivalentWidth] > 0.0) {
			width += APPKIT_MENU_ITEM_GAP + [cell keyEquivalentWidth];
		}
		return width;
	}
	{
		CGFloat width = [cell titleWidth] + 2.0 * APPKIT_MENUBAR_TITLE_PADDING;

		/* **A BAR'S ITEMS ARE AS WIDE AS THEIR TITLES, WHICH IS WHY A BAR'S LAYOUT HAS TO ASK A CELL.** A
		 * dropdown's rows are all the menu's width and their geometry is arithmetic; a bar's columns are the
		 * ITEM's, and only the cell that measured the title knows how wide that is. */
		return (width < APPKIT_MENUBAR_MIN_ITEM_WIDTH) ? APPKIT_MENUBAR_MIN_ITEM_WIDTH : width;
	}
}

- (NSRect)rectForItemAtIndex:(NSInteger)index
{
	NSRect bounds = [self bounds];
	CGFloat offset = 0.0;
	NSInteger i;

	if (!_horizontal) {
		/* **THE FIRST ITEM IS THE TOP ROW, WHICH IS THE CONVERSION WORTH WRITING DOWN.** A menu's item 0 is the
		 * row the reader sees first, at the TOP; a view's coordinates are Cocoa's and run UP from the bottom. So
		 * the row index counts down while the y counts up — and the panel's own padding is taken off BOTH ends, so
		 * the rows sit inside the panel rather than against it.
		 *
		 * **AND THE ARITHMETIC IS THE MENU'S NOW, BECAUSE A LIST'S ROWS ARE NOT THE MENU'S HEIGHT.** A combo box can say
		 * how tall its rows are and how much air it wants between them, and BOTH the paint and the hit test have to agree
		 * about that or a click would land on a row the menu did not draw. So the rect comes from
		 * `-cg_rowRectAtIndex:inFrame:` — one door, three callers — and the fallback below is the constant for a view that
		 * was handed no menu at all. */
		if (_shownMenu != nil) {
			return [_shownMenu cg_rowRectAtIndex:index inFrame:bounds];
		}
		return NSMakeRect(NSMenuPanelPadding,
				  bounds.size.height - NSMenuPanelPadding - (CGFloat)(index + 1) * NSMenuRowHeight,
				  bounds.size.width - 2.0 * NSMenuPanelPadding,
				  NSMenuRowHeight);
	}
	/* **AND IN A BAR THE FIRST ITEM IS THE LEFTMOST COLUMN**, running right from the left edge, each as wide as
	 * its own title. The sum is walked rather than cached because a bar has a handful of items and a cache of
	 * offsets is a second thing to keep in step with the titles that produced them. */
	for (i = 0; i < index; i++) {
		offset += [self widthForItemAtIndex:i];
	}
	/* **AND A BAR'S ITEMS ARE AS TALL AS THE BAR**, not as tall as a dropdown's row: the bar is 24 pixels and a
	 * row is 22, so an item that took a row's height would sit 2 pixels below the top of the surface it is part of
	 * — half of why the titles read as too high. */
	return NSMakeRect(offset, 0.0, [self widthForItemAtIndex:index], bounds.size.height);
}

/* **THE CLICK, AND THE ONE ARITHMETIC THIS VIEW DOES ITSELF: WHERE THE MENU GOES.** The bar starts its session with
 * `-cg_beginSessionAt:`, which has no view parameter — so the point it is handed is already in SCREEN coordinates,
 * and the clicked item's BOTTOM-LEFT CORNER is carried there ONCE, as this window's frame origin plus the item's box.
 * (A pop-up or a combo box hands `-popUpMenuPositioningItem:…` a point in its CONTROL's coordinates and lets the menu
 * do that carrying; doing it in both places is the second conversion `popup_anchor.m` measures.)
 *
 * AND IT IS THE ITEM'S BOTTOM, NOT ITS TOP: a bar's items run the height of the bar, so their bottom edge IS the
 * bar's bottom edge, and a menu hung below that hangs below the bar rather than over it. */
/* **WHICH TITLE A POINT IS OVER, WHICH IS THE BAR'S OWN ARITHMETIC** — the same boxes the click was matched
 * against, asked as a question rather than searched in a loop. -1 for none. */
- (NSInteger)cg_indexOfItemAtPoint:(NSPoint)point
{
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;

	for (i = 0; i < count; i++) {
		NSRect box = [self rectForItemAtIndex:i];

		if (point.x >= box.origin.x && point.x <= box.origin.x + box.size.width && point.y >= box.origin.y &&
		    point.y <= box.origin.y + box.size.height) {
			return i;
		}
	}
	return -1;
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint p;
	NSInteger i, count;
	NSInteger current;

	/* **WHETHER THE CLICK REACHED THIS VIEW AT ALL**, printed BEFORE the guards below so that a bar that
	 * declines the press and a bar that never heard of it read differently in the log. */
	if (getenv("APPKIT_MENU_DIAG") != NULL) {
		fprintf(stderr, "  DIAG bar %lld: mouseDown in the view at (%.0f,%.0f), horizontal %d, menu %s\n",
			ag_menu_diag_ms(), (double)[event locationInWindow].x, (double)[event locationInWindow].y,
			(int)_horizontal, (_shownMenu != nil) ? "set" : "nil");
	}

	if (!_horizontal || _shownMenu == nil) {
		[super mouseDown:event];	/* a dropdown is tracked by NSMenu, not by clicking its rows */
		return;
	}
	/* **AND THE POINT IS CONVERTED, WHICH IS A DOOR AND NOT A COINCIDENCE.** `-locationInWindow` is the WINDOW's
	 * coordinates and the item boxes are THIS VIEW's; for a borderless window whose content fills it the two
	 * happen to agree, and a bar whose content is inset by a single pixel would then open the wrong menu — or none.
	 * `-convertPoint:fromView:` with a nil view means "from the window's", which is what this is. */
	p = [self convertPoint:[event locationInWindow] fromView:nil];
	count = [_shownMenu numberOfItems];
	/* **`current` AND NOT `index`.** `index` is a FUNCTION in POSIX's `<strings.h>` — the same family as `rindex` —
	 * so a variable of that name is a redeclaration the compiler reads as assigning to the function: MEASURED,
	 * "non-object type 'char *(const char *, int)' is not assignable". The name is `current` because that is what it
	 * is: the title whose menu is open right now. */
	current = -1;
	for (i = 0; i < count; i++) {
		NSRect box = [self rectForItemAtIndex:i];
		NSMenuItem *item = [_shownMenu itemAtIndex:i];
		id submenu;

		if (p.x < box.origin.x || p.x > box.origin.x + box.size.width || p.y < box.origin.y ||
		    p.y > box.origin.y + box.size.height) {
			continue;
		}
		current = i;	/* WHICH TITLE, which is the session's whole state: the loop below moves it */
		submenu = [item submenu];
		if (submenu != nil) {
			NSRect frame = [[self window] frame];

			/* **AND THE TITLE IS HIGHLIGHTED FOR AS LONG AS ITS MENU IS OPEN**, which is how a menu bar says
			 * WHICH menu you are looking at — the row that is down stays down until it is dismissed. The menu is
			 * opened from here and returns when it ends, so the highlight is this door's to put up and take down;
			 * nothing else knows the two are the same gesture. */
			/* **THE BAR OWNS THIS SESSION, AND THAT IS THE WHOLE OF WHY DRAGGING CAN WORK.** A menu that runs
			 * its own tracking loop EATS the events a menu bar has to act on — a drag across the bar, a press on
			 * another title — because that loop is inside this call and this view never sees them. So the menu is
			 * BEGUN here (`-cg_beginSessionAt:`, which is the beginning of a session and not its loop) and driven
			 * from here: the loop below fetches the events, asks the menu whether each one is its
			 * (`-cg_ownsEvent:`), hands over the ones that are, and acts on the ones that are the BAR's — moving the
			 * session to whatever title the pointer is over, and ending it when the press was somewhere that has no
			 * menu of its own. */
			{
				NSApplication *app = [NSApplication sharedApplication];
				BOOL ended = NO;

				while (!ended) {
					NSMenu *open = (NSMenu *)[[_shownMenu itemAtIndex:current] submenu];
					NSRect box;

					if (open == nil) {
						break;
					}
					box = [self rectForItemAtIndex:current];
					{
						NSRect frame = [[self window] frame];

						[self setHighlightedItem:[_shownMenu itemAtIndex:current]];
						/* AND THE MENU'S DELEGATE HEARS IT, through the menu's own notify door — the bar's loop
						 * raises a highlight the same way the session's step does, and a delegate must not be able to
						 * tell which path it came from. */
						[_shownMenu cg_willHighlightItem:[_shownMenu itemAtIndex:current]];
						[[self window] setNeedsDisplay:YES];
						[[self window] displayIfNeeded];
						[open cg_beginSessionAt:NSMakePoint(frame.origin.x + box.origin.x,
										    frame.origin.y + box.origin.y)];
					}
					/* **AND THE EVENTS ARE ONLY FETCHED WHEN THERE IS A RUN LOOP TO FETCH THEM FROM.** An application
					 * that has not called `-run` has no event source: this loop would wait forever for a click that
					 * cannot come, and MEASURED, that is exactly what happened — the display-path test hung for its
					 * whole sixty-second budget. A program without a run loop gets the menu BEGIN and no loop, which
					 * is what it had before this commit and what a demonstration wants. */
					while (!ended && [app isRunning] && ![NSWindow cg_connectionIsGone]) {
						NSEvent *next = [app nextEventMatchingMask:NSAnyEventMask
										 untilDate:[NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0]
										    inMode:nil dequeue:YES];

						/* **AND THE WINDOWS ARE PAINTED, WHICH IS WHAT A TRACKING LOOP OWES THEM.** */
						[app updateWindows];
						if (next == nil) {
							continue;
						}
						if (getenv("APPKIT_MENU_DIAG") != NULL) {
							fprintf(stderr, "  DIAG bar: event type %ld, the menu owns it: %s\n",
								(long)[next type], [open cg_ownsEvent:next] ? "yes" : "no");
						}
						if ([open cg_ownsEvent:next]) {
							if (![open cg_trackOneEvent:next]) {
								ended = YES;	/* a pick, a dismissal, or Escape */
							}
							continue;
						}
						{
							NSUInteger type = [next type];
							NSPoint at = [self convertPoint:[next locationInWindow] fromView:nil];
							NSInteger hit = [self cg_indexOfItemAtPoint:at];

						/* **WHICH EVENT, WHERE, AND WHAT IT HIT** — added because "the session ended on a move" says
						 * nothing about WHY, and the two numbers that decide it are the point in this view's space and
						 * the item it landed on. */
						if (getenv("APPKIT_MENU_DIAG") != NULL) {
							fprintf(stderr, "  DIAG bar: type %lu win %ld at (%.0f,%.0f) -> item %ld, current %ld\n",
								(unsigned long)type, (long)[next windowNumber], (double)at.x,
								(double)at.y, (long)hit, (long)current);
						}

							/* **A RELEASE NEVER ENDS A MENU BAR'S SESSION, AND THAT IS THE FIX.** The rule that every release
							 * after the opening one dismissed the menu was written for a menu that owns its own tracking loop,
							 * where the next thing the loop sees after the press IS its release. A BAR does not own one: the
							 * loop here drains EVERY window's queue, so it sees the DOWN, the DRAG and the UP of the opening
							 * gesture, and then whatever the compositor sends next — and MEASURED, with the AppKit's own
							 * `APPKIT_MENU_DIAG` on and one click on the application menu: the session ended on a `type 2`
							 * three times running, so the menu was up for a frame and gone. On the Mac a release is inert —
							 * what dismisses a menu bar's menu is a PRESS somewhere else, which is the next branch down, and
							 * what moves it to another title is a MOVE. */
							if (type == NSLeftMouseUp) {
								continue;
							}
							/* **ONLY A DELIBERATE GESTURE MOVES THE SESSION: A DRAG, OR A PRESS ON ANOTHER TITLE.** It used to
							 * move on a bare MOVE as well, and MEASURED, with the AppKit's own diagnostic on and a person
							 * clicking the application menu: the hand drifting from (63,18) to (101,6) crossed a title
							 * boundary and the session was CANCELLED AND REBUILT — a new tracking window, whose own cost was
							 * measured at 3 ms once and at 8052 ms another time — and then the next jitter did it again. The
							 * menu never appeared; "I click File and nothing happens" is what that looks like from outside.
							 *
							 * The Mac does follow a hover across the bar, but it moves ONE session; this tier rebuilds one, so
							 * a hover that costs a window per boundary is a menu that cannot be used. Correctness first: a
							 * press on another title still moves (and a drag still moves), which is the deliberate version of
							 * the same gesture. */
							if ((type == NSLeftMouseDragged || type == NSLeftMouseDown) && hit >= 0 &&
							    hit != current) {
								/* **THE POINTER MOVED TO ANOTHER TITLE AND THE SESSION FOLLOWS IT** — the
								 * gesture that could not work while the menu owned its own loop. */
								if (getenv("APPKIT_MENU_DIAG") != NULL) {
									fprintf(stderr, "  DIAG bar: ENDING the session here (event type %ld)\n",
										(long)type);
								}
								[open cancelTracking];
								current = hit;
								break;
							}
							if (type == NSLeftMouseDown && hit < 0) {
								if (getenv("APPKIT_MENU_DIAG") != NULL) {
									fprintf(stderr, "  DIAG bar: ENDING the session here (event type %ld)\n",
										(long)type);
								}
								[open cancelTracking];
								ended = YES;
							}
						}
					}
					/* **AND WITH NO RUN LOOP THE OUTER LOOP MUST STOP TOO.** The inner one is skipped
					 * entirely when the application is not running — there is no event source — so without
					 * this the OUTER one re-begins the same menu for ever. MEASURED: the display-path test
					 * hung for its whole budget with the inner guard already in place and this one missing. */
					/* **AND A COMPOSITOR THAT HAS GONE ENDS THIS LOOP TOO, WHICH IS WHERE IT MATTERS MOST.** The
					 * check for a dead connection lives in the run loop — and a session loop NESTS INSIDE the run
					 * loop, so while one is up the run loop's check never runs. MEASURED: the client sat for two
					 * minutes with its server dead and its own log silent, turning in here. A loop that has events
					 * to fetch is a loop that has to ask whether there is anything left to fetch them from. */
					if (![app isRunning] || [NSWindow cg_connectionIsGone]) {
						if ([NSWindow cg_connectionIsGone]) {
							fprintf(stderr, "APPKIT-NOTE: the window server has gone — ending the menu session\n");
						}
						break;
					}
				}
				[self setHighlightedItem:nil];
				[_shownMenu cg_willHighlightItem:nil];
				[[self window] setNeedsDisplay:YES];
				[[self window] displayIfNeeded];
			}
		}
		return;
	}
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
	(void)event;
	return YES;
}

- (void)setHighlightedItem:(NSMenuItem *)item
{
	_highlightedItem = item;
	[self setNeedsDisplay:YES];
}

- (BOOL)cg_isItemMarked:(NSMenuItem *)item
{
	(void)item;
	return NO;
}

- (NSMenuItem *)highlightedItem
{
	return _highlightedItem;
}

- (BOOL)isHorizontal
{
	return _horizontal;
}

- (void)setHorizontal:(BOOL)flag
{
	if (flag == _horizontal) {
		return;
	}
	_horizontal = flag;
	/* **AND THE CELLS GO WITH IT, because which item is bold is a fact about the ORIENTATION.** A cell that was
	 * made for a dropdown carried no bold row; the same items in a bar have one. */
	[_cells removeAllObjects];
	[self setNeedsDisplay:YES];
}

- (CGFloat)requiredHeight
{
	NSInteger count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;
	CGFloat pitch = (_shownMenu != nil) ? [_shownMenu cg_rowPitch] : NSMenuRowHeight;
	CGFloat gap = (_shownMenu != nil) ? (pitch - [_shownMenu cg_rowHeight]) : 0.0;
	CGFloat height = (CGFloat)count * pitch - gap;
	CGFloat rowHeight = (_shownMenu != nil) ? [_shownMenu cg_rowHeight] : NSMenuRowHeight;

	/* **THE DROPDOWN KEEPS AIR ABOVE AND BELOW ITS ROWS; THE BAR DOES NOT.** A bar's height IS the strip the server
	 * draws, so padding it would lift its titles off the surface they are part of.
	 *
	 * **AND THE LAST ROW KEEPS ITS HEIGHT RATHER THAN A GAP:** a list's rows are pitched by the height PLUS the air
	 * between them, so a panel sized `count * pitch` would end with one gap's worth of nothing under the last row. */
	if (!_horizontal) {
		height += 2.0 * NSMenuPanelPadding;
	}
	return (height < rowHeight) ? rowHeight : height;
}

- (CGFloat)requiredWidth
{
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;
	CGFloat width = 0.0;

	/* **A BAR IS THE SUM OF ITS COLUMNS AND A DROPDOWN IS THE WIDEST OF ITS ROWS.** One door, because both answer
	 * "how wide does this menu need to be", and the orientation is what decides how. */
	for (i = 0; i < count; i++) {
		CGFloat item = [self widthForItemAtIndex:i];

		if (_horizontal) {
			width += item;
		} else if (item > width) {
			width = item;
		}
	}
	/* THE SAME PADDING AS THE HEIGHT, for the same reason: a dropdown's rows do not touch its left or right edge
	 * either, and the bar's columns run the whole width of the strip. */
	return _horizontal ? width : (width + 2.0 * NSMenuPanelPadding);
}

/* **THE ROW'S OWN BACKGROUND, DRAWN BY THE VIEW RATHER THAN BY THE CELL — WHICH IS THE RULE, NOT A SHORTCUT.**
 * `NSMenuItemCell -drawBorderAndBackgroundWithFrame:inView:` refuses on exactly this ground: the highlight and the
 * background are THE MENU VIEW'S, because a bar's rows and a dropdown's rows are different objects. The cell draws
 * its own parts; the view draws what the parts sit on. */
- (void)drawRect:(NSRect)dirtyRect
{
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;
	NSRect bounds = [self bounds];

	(void)dirtyRect;
	/* **A BAR PAINTS NO PANEL OF ITS OWN, WHICH IS WHAT MAKES IT SEAMLESS.** The strip belongs to the Window Server
	 * and the WINDOW's background colour is the strip's — told to the client as part of the bar's own description —
	 * so a view that filled its own panel here would put a rectangle of a slightly different grey across a surface
	 * meant to be one thing. MEASURED before this: the server's strip at 216,216,216 and this panel at 240,240,240.
	 * A DROPDOWN still paints its own, because a dropdown is a panel with nothing behind it.
	 *
	 * **AND IT IS AGORA'S PANEL: ROUNDED, ONE FLAT COLOUR, AND WITH NO BORDER AT ALL.** A menu is a flat sheet of the
	 * panel's own colour; a hairline around it is a frame, and the panel's own rounded shade is already doing that
	 * job without one.
	 *
	 * THE HALF-PIXEL INSET WENT WITH THE BORDER, because the border was the whole of its reason — "inset half a
	 * pixel so the one-pixel border falls INSIDE the surface rather than half off it" was the sentence, and a panel
	 * with nothing to keep inside it is the surface itself. */
	if (!_horizontal) {
		/* **THE PANEL IS THE MENU BAR'S OWN COLOUR, WHICH IS THE SERVER'S — see `+[NSWindow cg_menuBarColor]`.**
		 * It used to be a Snow-Leopard ramp of this file's own (0.985 down to 0.925), which made a menu LIGHTER
		 * at its top than the bar it hung from: MEASURED, the strip at 235 and the panel's first row at 251. A
		 * menu is part of the bar it comes out of, so it is the same colour as it — by CONSTRUCTION rather than
		 * by a second guess. */
		NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:bounds
								     xRadius:APPKIT_MENU_PANEL_RADIUS
								      yRadius:APPKIT_MENU_PANEL_RADIUS];

		[[NSWindow cg_menuBarColor] setFill];
		[shape fill];
	}

	for (i = 0; i < count; i++) {
		NSMenuItem *item = [_shownMenu itemAtIndex:i];
		NSMenuItemCell *cell = [self cellForItemAtIndex:i];
		NSRect row = [self rectForItemAtIndex:i];

		if (item == nil || cell == nil) {
			continue;
		}
		/* **AND A SUBCLASS MAY MARK A ROW THE POINTER IS NOT ON.** A list holds a row of its own; a menu holds nothing,
		 * so its answer is NO and this reads exactly as it did. See the header for why the question is the VIEW's. */
		if (item == _highlightedItem || [self cg_isItemMarked:item]) {
			/* **A CHIP INSET INSIDE THE ROW, NOT THE WHOLE ROW.** That inset-and-round is most of what makes a
			 * Mac menu read as a menu; a full-width band of colour is what a Windows menu does. The bar's chip is
			 * inset the same way, a little more vertically, so it does not touch the strip's edges. */
			NSRect chip = [self cg_markRectForRow:row];

			NSColor *accent = [NSColor cg_accentColor];

			apk_fill_vertical_gradient(chip, APPKIT_MENU_HIGHLIGHT_RADIUS,
						   [accent redComponent], [accent greenComponent], [accent blueComponent],
						   [accent redComponent], [accent greenComponent], [accent blueComponent]);
		}
		if ([item isSeparatorItem]) {
			[cell drawSeparatorItemWithFrame:row inView:self];
			continue;
		}
		/* **AND THE TWO IMAGE DOORS ARE ASKED ONLY WHEN THERE IS AN IMAGE**, so that a menu of plain titles does
		 * not make a door that has no work print a refusal once per row per frame. A door that refuses is doing
		 * its job; a row with no image is not its caller. */
		/* **AND THE STATE DOOR IS ASKED WHEN THERE IS ANYTHING TO SHOW: a state image the item named, OR the
		 * default checkmark its own state asks for.** An item that is ON with no picture of its own used to draw
		 * nothing at all, so a menu could not say which of its items was chosen. */
		if ([cell stateImageWidth] > 0.0 || [item state] != NSOffState) {
			[cell drawStateImageWithFrame:row inView:self];
		}
		if ([cell imageWidth] > 0.0) {
			[cell drawImageWithFrame:row inView:self];
		}
		[cell drawTitleWithFrame:row inView:self];
		/* **AND A BAR SHOWS NO KEY EQUIVALENTS, WHICH IS THE MAC'S ANSWER AND NOT AN OMISSION.** A key equivalent
		 * belongs to the MENU a title opens, so drawing it in the title would say that Command-S opens the File
		 * menu. */
		if (!_horizontal) {
			[cell drawKeyEquivalentWithFrame:row inView:self];
		}
	}
}

/* ============================================================================================ *
 * THE ERA'S SURFACE: GEOMETRY, METRICS, THE LIFECYCLE AND THE ACTION                           *
 * ============================================================================================ */

/* THE PUBLIC NAMES OF THE VIEW'S OWN ARITHMETIC. `-rectForItemAtIndex:` and `-cellForItemAtIndex:` are what the drawing
 * and the hit test use; these are the era's spellings of the same two answers, plus the padding the item's rect keeps. */
- (NSRect)rectOfItemAtIndex:(NSInteger)index
{
	NSRect rect = [self rectForItemAtIndex:index];

	if (_horizontal || NSEqualRects(rect, NSZeroRect)) {
		return rect;
	}
	{
		CGFloat width = NSWidth(rect) - 2.0 * _horizontalEdgePadding;

		if (width < 0.0) {
			width = 0.0;
		}
		return NSMakeRect(NSMinX(rect) + _horizontalEdgePadding, NSMinY(rect), width, NSHeight(rect));
	}
}

- (NSMenuItemCell *)menuItemCellForItemAtIndex:(NSInteger)index
{
	if (_shownMenu == nil || index < 0 || index >= [_shownMenu numberOfItems]) {
		return nil;
	}
	return [self cellForItemAtIndex:index];
}

/* **A CALLER'S CELL REPLACES THE ONE THE VIEW MADE**, and the view keeps the replacement rather than copying it: the
 * cache is per row and a caller that supplies a cell has said it wants that one drawn. */
- (void)setMenuItemCell:(NSMenuItemCell *)cell forItemAtIndex:(NSInteger)index
{
	if (_shownMenu == nil || index < 0 || index >= [_shownMenu numberOfItems]) {
		return;
	}
	while ((NSInteger)[_cells count] <= index) {
		[_cells addObject:[NSNull null]];
	}
	[_cells replaceObjectAtIndex:(NSUInteger)index
			  withObject:(cell != nil) ? (id)cell : (id)[NSNull null]];
	if (cell != nil) {
		[cell setMenuView:self];
		[cell setMenuItem:[_shownMenu itemAtIndex:index]];
		[cell setNeedsSizing:YES];
	}
	[self setNeedsDisplayForItemAtIndex:index];
}

- (NSInteger)indexOfItemAtPoint:(NSPoint)point
{
	return [self cg_indexOfItemAtPoint:point];
}

/* **THE PANEL LESS ITS PADDING**, which is the rect a row lives inside. A bar has no padding — its height is the
 * server's strip — so a horizontal view answers its bounds. */
- (NSRect)innerRect
{
	return _horizontal ? [self bounds] : NSInsetRect([self bounds], 0.0, NSMenuPanelPadding);
}

- (void)sizeToFit
{
	[self setFrameSize:NSMakeSize([self requiredWidth], [self requiredHeight])];
	_needsSizing = NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)needsSizing
{
	return _needsSizing;
}

- (void)setNeedsSizing:(BOOL)flag
{
	_needsSizing = flag ? YES : NO;
	if (_needsSizing) {
		[self setNeedsDisplay:YES];
	}
}

/* **THE SEVEN METRICS, EACH THE WIDEST ACROSS THE ROWS.** A menu's gutters are ONE set of columns for every row — that is
 * what makes the titles line up — so the width any of them gets is the widest any row needs. The two offsets are then
 * where those columns START: the state image at the content inset, the image-and-title after it, and the key equivalent
 * at the far end, measured from the right edge because that is the edge its width is subtracted from. */
- (CGFloat)cg_widestStateImage
{
	CGFloat widest = 0.0;
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;

	for (i = 0; i < count; i++) {
		NSMenuItemCell *cell = [self cellForItemAtIndex:i];

		if ([cell stateImageWidth] > widest) {
			widest = [cell stateImageWidth];
		}
	}
	return widest;
}

- (CGFloat)cg_widestImageAndTitle
{
	CGFloat widest = 0.0;
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;

	for (i = 0; i < count; i++) {
		NSMenuItemCell *cell = [self cellForItemAtIndex:i];
		CGFloat width = [cell imageWidth] + [cell titleWidth];

		if (width > widest) {
			widest = width;
		}
	}
	return widest;
}

- (CGFloat)cg_widestKeyEquivalent
{
	CGFloat widest = 0.0;
	NSInteger i, count = (_shownMenu != nil) ? [_shownMenu numberOfItems] : 0;

	for (i = 0; i < count; i++) {
		NSMenuItemCell *cell = [self cellForItemAtIndex:i];

		if ([cell keyEquivalentWidth] > widest) {
			widest = [cell keyEquivalentWidth];
		}
	}
	return widest;
}

- (CGFloat)stateImageOffset
{
	return APPKIT_MENU_LEFT_GUTTER;
}

- (CGFloat)stateImageWidth
{
	return [self cg_widestStateImage];
}

- (CGFloat)imageAndTitleOffset
{
	return [self stateImageOffset] + [self stateImageWidth];
}

- (CGFloat)imageAndTitleWidth
{
	return [self cg_widestImageAndTitle];
}

/* THE SHORTCUT COLUMN IS MEASURED FROM ITS OWN WIDTH AND THE ROW'S RIGHT EDGE, because that is how a menu draws it: the
 * key equivalents share one right-aligned column. */
- (CGFloat)keyEquivalentOffset
{
	CGFloat width = [self cg_widestKeyEquivalent];

	if (width <= 0.0) {
		return NSWidth([self bounds]);
	}
	return NSWidth([self bounds]) - APPKIT_MENU_RIGHT_PADDING - width;
}

- (CGFloat)keyEquivalentWidth
{
	return [self cg_widestKeyEquivalent];
}

- (CGFloat)horizontalEdgePadding
{
	return _horizontalEdgePadding;
}

/* **READ WHERE THE ROWS ARE PLACED**: `-rectOfItemAtIndex:` insets every row by it, so a caller that wants a menu's rows
 * away from the panel's sides sets it and the rects (and the highlight, which is drawn from them) follow. */
- (void)setHorizontalEdgePadding:(CGFloat)padding
{
	_horizontalEdgePadding = (padding > 0.0) ? padding : 0.0;
	[self setNeedsDisplay:YES];
}

/* ---- THE HIGHLIGHT BY INDEX -------------------------------------------------------------------- */

- (NSInteger)highlightedItemIndex
{
	if (_highlightedItem == nil || _shownMenu == nil) {
		return -1;
	}
	return [_shownMenu indexOfItem:_highlightedItem];
}

- (void)setHighlightedItemIndex:(NSInteger)index
{
	if (_shownMenu == nil || index < 0 || index >= [_shownMenu numberOfItems]) {
		[self setHighlightedItem:nil];
		return;
	}
	[self setHighlightedItem:[_shownMenu itemAtIndex:index]];
}

/* ---- THE ITEM LIFECYCLE -------------------------------------------------------------------------- */

/* **A CHANGED MENU DROPS THE CELL THE VIEW CACHED FOR THAT ROW.** The cells are made on demand and hold a measured copy of
 * the item's widths; an item whose title or key equivalent changed would otherwise be drawn at the old size, which is the
 * kind of stale cache that looks like a layout bug. The three doors are the public hooks; the view calls them from the
 * menu's own notifications, so there is one path into the cache. */
- (void)cg_dropCachedCellForItem:(NSMenuItem *)item
{
	NSInteger index;

	if (_shownMenu == nil || item == nil) {
		return;
	}
	index = [_shownMenu indexOfItem:item];
	if (index < 0 || index >= (NSInteger)[_cells count]) {
		return;
	}
	[_cells replaceObjectAtIndex:(NSUInteger)index withObject:[NSNull null]];
	[self setNeedsSizing:YES];
}

- (void)itemAdded:(NSMenuItem *)item
{
	(void)item;
	[self setNeedsSizing:YES];
	[self setNeedsDisplay:YES];
}

- (void)itemChanged:(NSMenuItem *)item
{
	/* **A CHANGE WITH NO ITEM NAMED DROPS EVERYTHING**, which is what the menu's notification actually carries: it does not
	 * name the item, so the honest answer is "the cache is stale" rather than "nothing changed". A caller that knows which
	 * item changed passes it and only that row is dropped. */
	if (item == nil) {
		[_cells removeAllObjects];
		[self setNeedsSizing:YES];
	} else {
		[self cg_dropCachedCellForItem:item];
	}
	[self setNeedsDisplay:YES];
}

- (void)itemRemoved:(NSMenuItem *)item
{
	(void)item;
	/* THE ROWS AFTER THE REMOVED ONE SHIFT, so the whole cell cache is stale rather than one entry. */
	[_cells removeAllObjects];
	[self setNeedsSizing:YES];
	[self setNeedsDisplay:YES];
}

/* AND THE THREE OBSERVERS THAT REACH THOSE DOORS. The menu announces each change; the view is a listener on the menu it
 * shows, which is why `-setMenu:` re-subscribes. */
- (void)cg_menuItemsChanged:(NSNotification *)note
{
	NSString *name = [note name];

	if ([name isEqualToString:NSMenuDidAddItemNotification]) {
		[self itemAdded:nil];
	} else if ([name isEqualToString:NSMenuDidChangeItemNotification]) {
		[self itemChanged:nil];
	} else {
		[self itemRemoved:nil];
	}
}

/* **THE MENU'S OWN VALIDATION, THEN THE REPAINT** — `-update` is Apple's door for "re-read the menu", and the validity of
 * every item is the menu's to decide (`-update` walks the items and asks their targets). */
- (void)update
{
	if (_shownMenu != nil) {
		[_shownMenu update];
	}
	[self setNeedsSizing:YES];
	[self setNeedsDisplay:YES];
}

- (void)setNeedsDisplayForItemAtIndex:(NSInteger)index
{
	if (_shownMenu == nil || index < 0 || index >= [_shownMenu numberOfItems]) {
		return;
	}
	[self setNeedsDisplayInRect:[self rectOfItemAtIndex:index]];
}

/* **THE FLASH AND THE SEND.** The row is highlighted, the view is drawn once so the highlight is visible, the item's
 * action is sent exactly as a click sends it, and the highlight comes back off — which is what "highlighting" means for a
 * caller that is performing a row without a pointer. */
- (void)performActionWithHighlightingForItemAtIndex:(NSInteger)index
{
	NSMenuItem *item;

	if (_shownMenu == nil || index < 0 || index >= [_shownMenu numberOfItems]) {
		return;
	}
	item = [_shownMenu itemAtIndex:index];
	if (![item isEnabled]) {
		return;
	}
	[self setHighlightedItem:item];
	/* **THE FLASH IS A DIRTY RECT, NOT `-display`.** `-display` and `-displayIfNeeded` are absent in this tier on purpose
	 * (they mean "draw me where I live", NSView.h says so); the highlighted row is marked and the action sent, which is the
	 * half a caller can observe without a window. */
	[self setNeedsDisplayForItemAtIndex:index];
	/* **THE SHARED APPLICATION, NOT THE `NSApp` GLOBAL.** `NSApp` is set by `-sharedApplication` and is NULL in a process
	 * that never made one — which a probe, a test and a command-line tool all are. The rest of this tree asks the class for
	 * the instance, and this door does the same. */
	[[NSApplication sharedApplication] sendAction:[item action] to:[item target] from:item];
	[self setHighlightedItem:nil];
	[self setNeedsDisplay:YES];
}

/* ---- THE FACE AND THE BAR'S HEIGHT ---------------------------------------------------------------- */

- (NSFont *)font
{
	if (_font != nil) {
		return _font;
	}
	if (_shownMenu != nil && [_shownMenu numberOfItems] > 0) {
		return [[self cellForItemAtIndex:0] font];
	}
	return nil;
}

/* **A FACE FOR EVERY ROW.** A caller that sets one gets it on the cells the view made; a row whose cell the CALLER
 * supplied is left alone, because its face is the caller's. */
- (void)setFont:(NSFont *)font
{
	[font retain];
	[_font release];
	_font = font;
	if (_font != nil && _shownMenu != nil) {
		NSInteger i, count = [_shownMenu numberOfItems];

		for (i = 0; i < count; i++) {
			[[self cellForItemAtIndex:i] setFont:_font];
		}
	}
	[self setNeedsSizing:YES];
	[self setNeedsDisplay:YES];
}

/* THE STRIP'S HEIGHT WHEN THIS VIEW IS A BAR, and zero for a dropdown — a dropdown has no bar to be tall. */
- (CGFloat)menuBarHeight
{
	return _horizontal ? NSHeight([self bounds]) : 0.0;
}

/* ---- AND THE ONES THAT REFUSE ---------------------------------------------------------------------- */

/* **THE POPUP ATTACHMENT IS `NSMenu`'S IN THIS TIER.** Apple's view owned it; here `NSMenu` owns the tracking window, the
 * open submenu and the event loop, and two owners of one window is the arrangement that cannot work. Each door says so
 * rather than pretending. */

- (void)attachSubmenuForItemAtIndex:(NSInteger)index
{
	(void)index;
	fn_refuse_workspace("NSMenuView -attachSubmenuForItemAtIndex:",
			    "an attachment owned by the view - NSMenu owns the tracking window and the open submenu "
			    "in this tier (see -cg_trackOneEvent:)");
}

- (NSMenu *)attachedMenu
{
	fn_refuse_workspace("NSMenuView -attachedMenu",
			    "an attachment owned by the view - NSMenu owns the tracking window and the open submenu");
	return nil;
}

- (NSMenuView *)attachedMenuView
{
	fn_refuse_workspace("NSMenuView -attachedMenuView",
			    "an attachment owned by the view - NSMenu owns the tracking window and the open submenu");
	return nil;
}

- (void)detachSubmenu
{
	fn_refuse_workspace("NSMenuView -detachSubmenu",
			    "an attachment owned by the view - NSMenu owns the tracking window and the open submenu");
}

- (NSPoint)locationForSubmenu:(NSMenu *)submenu
{
	(void)submenu;
	fn_refuse_workspace("NSMenuView -locationForSubmenu:",
			    "an attachment owned by the view - NSMenu computes where a submenu's window goes");
	return NSZeroPoint;
}

- (BOOL)isAttached
{
	fn_refuse_workspace("NSMenuView -isAttached",
			    "an attachment owned by the view - NSMenu owns the tracking window and the open submenu");
	return NO;
}

- (void)setWindowFrameForAttachingToRect:(NSRect)cellFrame
			       onScreen:(NSScreen *)screen
			  preferredEdge:(NSRectEdge)preferredEdge
			 popUpSelectedItem:(NSInteger)selectedItemIndex
{
	(void)cellFrame;
	(void)screen;
	(void)preferredEdge;
	(void)selectedItemIndex;
	fn_refuse_workspace("NSMenuView -setWindowFrameForAttachingToRect:onScreen:preferredEdge:popUpSelectedItem:",
			    "an attachment owned by the view - NSMenu sizes and places the tracking window");
}

- (void)trackWithEvent:(NSEvent *)event
{
	(void)event;
	fn_refuse_workspace("NSMenuView -trackWithEvent:",
			    "a tracking loop owned by the view - NSMenu runs it, one event at a time "
			    "(-cg_trackOneEvent:)");
}

/* AND THE TEAR-OFF PAIR, which is a 10.0-era feature Apple deprecated. */
- (id)initAsTearOff
{
	fn_refuse_workspace("NSMenuView -initAsTearOff",
			    "tear-off menus, a 10.0-era feature this tier has not got");
	return [self initWithFrame:NSZeroRect];
}

- (BOOL)isTornOff
{
	fn_refuse_workspace("NSMenuView -isTornOff",
			    "tear-off menus, a 10.0-era feature this tier has not got");
	return NO;
}

@end
