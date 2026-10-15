/*
 * NSMenuView.m — laying out rows and calling the cells that draw them.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 */

#include <stdlib.h>
#import "NSMenuView.h"
#import "NSWindow.h"
#import "NSMenu.h"
#import "NSMenuItem.h"
#import "NSMenuItemCell.h"
#import "NSColor.h"
#import "NSBezierPath.h"
#import "NSGraphicsContext.h"

#import <Foundation/NSArray.h>

const CGFloat NSMenuRowHeight = 22.0;

/* **THE PANEL'S OWN PADDING, WHICH IS THE AIR BETWEEN THE EDGE AND THE FIRST ROW.** The rows used to run EDGE TO
 * EDGE, so the only air inside the panel was the highlight chip's own 2-point inset — which left the chip almost
 * touching the panel's rounded edge. Two points on every side gives the panel a margin — the chip's own inset again,
 * on the panel's behalf — and it is a SHARED number (`NSMenuView.h`) because `NSMenu` sizes the window with it and
 * this view insets the rows by it. */
const CGFloat NSMenuPanelPadding = 2.0;

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
	[super dealloc];
}

- (void)setMenu:(NSMenu *)menu
{
	/* A MENU THAT CHANGED IS A LAYOUT THAT CHANGED, so the cells go with it: keeping them would keep the widths
	 * measured from the OLD items and lay the new ones out in the old item's columns. */
	_shownMenu = menu;
	[_cells removeAllObjects];
	[self setNeedsDisplay:YES];
}

- (NSMenu *)menu
{
	return _shownMenu;
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
		cell = [[NSMenuItemCell alloc] initTextCell:@""];
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
		 * the rows sit inside the panel rather than against it. */
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

/* **THE CLICK, AND THE ONE ARITHMETIC THAT IS NOT OBVIOUS: WHERE THE MENU GOES.** `-popUpMenuPositioningItem:`
 * takes a point in the space a WINDOW FRAME lives in — the space the popped-up menu's own window is placed in —
 * and hangs the menu BELOW that point. So the point to give it is the clicked item's BOTTOM-LEFT CORNER carried
 * from this view's coordinates into the window's, which is this window's frame origin plus the corner. Handing it
 * the view's own point instead would put every menu at the screen's top-left, which is what a coordinate-space
 * mistake always looks like.
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
				BOOL consume_release = YES;	/* the release of the press that opened this menu */
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

							if (type == NSLeftMouseUp) {
								if (consume_release) {
									consume_release = NO;	/* the press that opened it, coming up */
									continue;
								}
								if (getenv("APPKIT_MENU_DIAG") != NULL) {
									fprintf(stderr, "  DIAG bar: ENDING the session here (event type %ld)\n",
										(long)type);
								}
								[open cancelTracking];
								ended = YES;
								continue;
							}
							if (hit >= 0 && hit != current) {
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
	CGFloat height = (CGFloat)count * NSMenuRowHeight;

	/* **THE DROPDOWN KEEPS AIR ABOVE AND BELOW ITS ROWS; THE BAR DOES NOT.** A bar's height IS the strip the server
	 * draws, so padding it would lift its titles off the surface they are part of. */
	if (!_horizontal) {
		height += 2.0 * NSMenuPanelPadding;
	}
	return (height < NSMenuRowHeight) ? NSMenuRowHeight : height;
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
			NSRect chip = _horizontal ? NSInsetRect(row, 1.0, 2.0)
						  : NSInsetRect(row, APPKIT_MENU_HIGHLIGHT_INSET,
								APPKIT_MENU_HIGHLIGHT_INSET);

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

@end
