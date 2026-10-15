/*
 * NSPopUpButtonCell — a button whose press raises a menu.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CELL'S WORK IS FOUR THINGS, AND THREE OF THEM ARE SMALL.** It points every item in its menu at itself, so a
 * pick comes back; it keeps an index and the items' `-state` saying the same thing; it draws an arrow; and it hands
 * the menu a place to open at. Everything else here is a forward to the menu, because a menu is what knows what is
 * in a menu.
 *
 * **AND THE ONE THING THAT IS NOT SMALL IS WHERE IT OPENS.** `NSMenuView`'s note on the click records the rule and
 * this is its second reader: `-popUpMenuPositioningItem:` takes a point in the space a WINDOW FRAME lives in and
 * hangs the menu BELOW it, so the anchor is the button's BOTTOM-LEFT CORNER carried from the view's coordinates
 * into the window's and then into that space — which is the window's frame origin plus the corner. Handing it the
 * view's own point puts the menu at the screen's top-left, which is what a coordinate-space mistake always looks
 * like.
 */
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSGeometry.h>

/* **THE ARROW'S THREE NUMBERS, AND THEY ARE THE SCRATCH ONE'S, NOT THE SAMPLE'S.** `Argentum Mockup.png` draws its
 * gear button with a `▼` about as wide as the glyph beside it, on a button the same height as any other; these are
 * what that comes to at this tier's 23-point bezel, and the MARGIN is the room between the arrow and the bezel's
 * right edge — which is also the room the title gives up when the arrow is at the centre. */
#define NS_POPUP_ARROW_WIDTH	7.0
#define NS_POPUP_ARROW_HEIGHT	4.0
#define NS_POPUP_ARROW_MARGIN	6.0
/* AND HOW FAR THE ARROW SITS OFF THE BOTTOM when it is a BOTTOM arrow, which is the same air the bezel keeps. */
#define NS_POPUP_ARROW_LIFT	4.0

@implementation NSPopUpButtonCell

- (instancetype)initTextCell:(NSString *)stringValue pullsDown:(BOOL)pullDown
{
	self = [super initTextCell:stringValue];
	if (self != nil) {
		_menu = nil;
		_pullsDown = pullDown;
		_selectedIndex = -1;
		/* APPLE'S DEFAULTS, AND ONE OF THEM IS A REAL CHOICE: `NSMaxYEdge` is the edge a popup opens TOWARD when
		 * the geometry it was given does not fit it, and the top of the button is where a menu that hangs below
		 * would flip to. Nothing here acts on it yet — `NSMenu` places the session itself — and it is declared,
		 * stored and answered because a caller that reads it back expects what it set. */
		_preferredEdge = NSMaxYEdge;
		_arrowPosition = NSPopUpArrowAtBottom;
	}
	return self;
}

- (void)dealloc
{
	[_menu release];
	[super dealloc];
}

/* ---- THE MENU, AND THE WIRING THAT MAKES A PICK COME BACK ------------------------------------------ */

/* **EVERY ITEM IS POINTED AT THIS CELL, AND THAT IS THE ONE PIECE OF WIRING IN THIS CLASS.** A menu's tracking loop
 * ends a session by sending the PICKED ITEM's action to the PICKED ITEM's target with the item as the argument (see
 * `-performActionForItemAtIndex:`), so a popup button that wants to know which row was chosen has to BE that
 * target. This is called from `-setMenu:` and again from every door that ADDS an item, because an item added to a
 * live button is wired the moment it exists rather than the next time the menu is set — which is the bug that pair
 * exists to not have. */
- (void)cg_pointItemsAtSelf
{
	NSArray *items = (_menu != nil) ? [(NSMenu *)_menu itemArray] : nil;
	NSUInteger i, n = [items count];

	for (i = 0; i < n; i++) {
		NSMenuItem *item = [items objectAtIndex:i];

		[item setTarget:self];
		[item setAction:@selector(itemSelected:)];
	}
}

- (id)menu
{
	return _menu;
}

- (void)setMenu:(id)aMenu
{
	if (aMenu == _menu) {
		return;
	}
	[aMenu retain];
	[_menu release];
	_menu = aMenu;
	[self cg_pointItemsAtSelf];
	/* **AND THE TITLE IS RE-DERIVED, BECAUSE THE OLD INDEX POINTED INTO THE OLD MENU.** A selection is an index, so
	 * a new menu of a different length makes the stored one either wrong or out of range; asking for the item whose
	 * `-state` is on is the only answer that survives the swap, and it is the same question
	 * `-synchronizeTitleAndSelectedItem` asks. */
	[self synchronizeTitleAndSelectedItem];
	[[self controlView] setNeedsDisplay:YES];
}

- (BOOL)pullsDown
{
	return _pullsDown;
}

- (void)setPullsDown:(BOOL)flag
{
	_pullsDown = flag;
	[self synchronizeTitleAndSelectedItem];
	[[self controlView] setNeedsDisplay:YES];
}

- (NSRectEdge)preferredEdge
{
	return _preferredEdge;
}

- (void)setPreferredEdge:(NSRectEdge)edge
{
	_preferredEdge = edge;
}

- (NSPopUpArrowPosition)arrowPosition
{
	return _arrowPosition;
}

- (void)setArrowPosition:(NSPopUpArrowPosition)position
{
	_arrowPosition = position;
	[[self controlView] setNeedsDisplay:YES];
}

/* ---- WHAT IS IN THE MENU, WHICH IS ALL THE MENU'S OWN ARITHMETIC --------------------------------- */

/* **A MENU ANSWERS `NSNotFound` AND A POP-UP BUTTON ANSWERS -1, AND THAT IS APPLE'S SPLIT RATHER THAN A TIDINESS.**
 * `NSMenu -indexOfItemWithTitle:` is documented to answer NSNotFound — a huge POSITIVE sentinel, `NSIntegerMax` in
 * this tree and in Apple's Foundation — while `NSPopUpButton`'s three `-indexOf…` doors are documented to answer "-1
 * if the item is not in the menu". A forward that passed the menu's sentinel straight through would hand a caller a
 * number that is neither a valid index nor the -1 the documentation promised, and a caller testing `< 0` would take
 * the huge value for a legitimate row. MEASURED: that is exactly what the first version of this file did, and the
 * probe's "a title that is not there answers -1" is the check that caught it. */
static NSInteger fn_popup_index(NSInteger menu_index)
{
	return (menu_index == NSNotFound) ? -1 : menu_index;
}

- (NSInteger)numberOfItems
{
	return (_menu != nil) ? [(NSMenu *)_menu numberOfItems] : 0;
}

- (id)itemAtIndex:(NSInteger)index
{
	if (_menu == nil || index < 0 || index >= [(NSMenu *)_menu numberOfItems]) {
		return nil;
	}
	return [(NSMenu *)_menu itemAtIndex:index];
}

- (NSArray *)itemArray
{
	return (_menu != nil) ? [(NSMenu *)_menu itemArray] : nil;
}

- (id)lastItem
{
	return [self itemAtIndex:[self numberOfItems] - 1];
}

- (NSString *)itemTitleAtIndex:(NSInteger)index
{
	id item = [self itemAtIndex:index];

	return (item != nil) ? [item title] : nil;
}

- (NSInteger)indexOfItem:(id)item
{
	return (_menu != nil && item != nil) ? fn_popup_index([(NSMenu *)_menu indexOfItem:item]) : -1;
}

- (NSInteger)indexOfItemWithTitle:(NSString *)title
{
	return (_menu != nil && title != nil) ? fn_popup_index([(NSMenu *)_menu indexOfItemWithTitle:title]) : -1;
}

- (NSInteger)indexOfItemWithTag:(NSInteger)tag
{
	return (_menu != nil) ? fn_popup_index([(NSMenu *)_menu indexOfItemWithTag:tag]) : -1;
}

- (id)itemWithTitle:(NSString *)title
{
	return (_menu != nil && title != nil) ? [(NSMenu *)_menu itemWithTitle:title] : nil;
}

- (id)itemWithTag:(NSInteger)tag
{
	return (_menu != nil) ? [(NSMenu *)_menu itemWithTag:tag] : nil;
}

- (void)addItemWithTitle:(NSString *)title
{
	if (_menu == nil || title == nil) {
		return;
	}
	[(NSMenu *)_menu addItemWithTitle:title action:NULL keyEquivalent:@""];
	[self cg_pointItemsAtSelf];
	[[self controlView] setNeedsDisplay:YES];
}

- (void)removeItemAtIndex:(NSInteger)index
{
	if (_menu == nil || index < 0 || index >= [(NSMenu *)_menu numberOfItems]) {
		return;
	}
	[(NSMenu *)_menu removeItemAtIndex:index];
	/* THE INDEX MOVES WITH THE ROW IT NAMED: removing a row ABOVE the selection slides the selection down with the
	 * items it was counting, and removing the selected row leaves nothing chosen. Getting this wrong is a button
	 * whose title is a row that is no longer in its menu. */
	if (index < _selectedIndex) {
		_selectedIndex--;
	} else if (index == _selectedIndex) {
		_selectedIndex = -1;
	}
	[self synchronizeTitleAndSelectedItem];
	[[self controlView] setNeedsDisplay:YES];
}

- (void)removeAllItems
{
	if (_menu == nil) {
		return;
	}
	[(NSMenu *)_menu removeAllItems];
	_selectedIndex = -1;
	[self synchronizeTitleAndSelectedItem];
	[[self controlView] setNeedsDisplay:YES];
}

/* ---- WHAT IS CHOSEN, WHICH IS WHERE THE TITLE COMES FROM ------------------------------------------ */

- (NSInteger)indexOfSelectedItem
{
	/* **A PULL-DOWN HAS NO SELECTION, WHICH IS A FACT AND NOT AN OVERSIGHT.** Its first item is the button's TITLE
	 * and is never a choice, so there is nothing for an index to name however many times a caller chooses; Apple
	 * answers -1 here for exactly that reason and this does too. */
	return _pullsDown ? -1 : _selectedIndex;
}

- (void)selectItemAtIndex:(NSInteger)index
{
	NSInteger count = [self numberOfItems];
	NSInteger i;

	/* A PULL-DOWN'S `-selectItemAtIndex:0` NAMES THE TITLE rather than a choice, which is Apple's reading and the
	 * only one that makes the door mean something on a button that can choose nothing. */
	if (_pullsDown && index == 0 && count > 0) {
		[self setTitle:[self itemTitleAtIndex:0]];
		return;
	}
	if (index < 0 || index >= count) {
		index = -1;	/* nothing chosen, which is a real answer and the one a fresh button gives */
	}
	_selectedIndex = index;
	/* **AND THE ITEMS' `-state` FOLLOWS, because that is the menu's own way of saying which row is chosen** — a
	 * button wearing one title over a menu showing its tick on another row is the two halves of one fact disagreeing
	 * in public. `NSMenuItem -state` draws the tick, so this is not bookkeeping: it is the ink. */
	for (i = 0; i < count; i++) {
		[[self itemAtIndex:i] setState:(i == index) ? NSOnState : NSOffState];
	}
	if (!_pullsDown && _selectedIndex >= 0) {
		NSString *title = [self itemTitleAtIndex:_selectedIndex];

		if (title != nil) {
			[super setTitle:title];
		}
	}
	[[self controlView] setNeedsDisplay:YES];
}

- (void)selectItemWithTitle:(NSString *)title
{
	NSInteger index = [self indexOfItemWithTitle:title];

	if (index >= 0) {
		[self selectItemAtIndex:index];
	}
}

- (void)selectItemWithTag:(NSInteger)tag
{
	NSInteger index = [self indexOfItemWithTag:tag];

	if (index >= 0) {
		[self selectItemAtIndex:index];
	}
}

- (id)selectedItem
{
	return (_selectedIndex >= 0) ? [self itemAtIndex:_selectedIndex] : nil;
}

- (void)setSelectedItem:(id)item
{
	NSInteger index = [self indexOfItem:item];

	if (index >= 0) {
		[self selectItemAtIndex:index];
	}
}

- (NSString *)titleOfSelectedItem
{
	id item = [self selectedItem];

	return (item != nil) ? [item title] : nil;
}

/* **THE ODD ONE OUT: THIS ONE READS THE MENU RATHER THAN WRITING IT.** A caller who sets an item's `-state` by hand
 * has said which row is chosen in the only vocabulary the MENU has, and this is the door that believes it — it finds
 * the item whose state is on and moves the index there. `-setMenu:` calls it for a different reason (a new menu of a
 * different length makes a stored index meaningless) and both wants are the same question. */
- (void)synchronizeTitleAndSelectedItem
{
	NSInteger count = [self numberOfItems];
	NSInteger i;

	if (_pullsDown) {
		/* the pull-down's title is its FIRST ITEM — see `-setTitle:` — so what has to be in step is that row. */
		if (count > 0) {
			id item = [self itemAtIndex:0];
			NSString *title = [item title];

			if (title != nil && ![title isEqual:[self title]]) {
				[super setTitle:title];
			}
		}
		return;
	}
	_selectedIndex = -1;
	for (i = 0; i < count; i++) {
		if ([[self itemAtIndex:i] state] == NSOnState) {
			_selectedIndex = i;
			break;
		}
	}
	if (_selectedIndex >= 0) {
		NSString *title = [self itemTitleAtIndex:_selectedIndex];

		if (title != nil) {
			[super setTitle:title];
		}
	}
}

/* **A PULL-DOWN'S TITLE IS ITS FIRST ITEM, SO SETTING THE BUTTON'S TITLE MOVES THAT ROW TOO.** The button says one
 * thing and the menu it opens says another if this is left out, and the row is the one that is wrong: the title on
 * the bezel is what a person typed. */
- (void)setTitle:(NSString *)aString
{
	[super setTitle:aString];
	if (_pullsDown && [self numberOfItems] > 0) {
		[[self itemAtIndex:0] setTitle:(aString != nil) ? aString : @""];
	}
}

/* ---- RAISING IT, WHICH IS THE ONE DOOR THAT IS NOT A FORWARD ------------------------------------- */

- (void)attachPopUpWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSWindow *window = [controlView respondsToSelector:@selector(window)] ? [controlView window] : nil;
	NSPoint where;

	if (_menu == nil || [(NSMenu *)_menu numberOfItems] == 0) {
		fprintf(stderr, "APPKIT-REFUSE: -attachPopUpWithFrame:inView: needs a menu with items — a popup with "
				"nothing to pop up is not a popup\n");
		return;
	}
	/* **THE ANCHOR IS THE BOTTOM-LEFT CORNER CARRIED INTO THE SPACE A WINDOW FRAME LIVES IN.** Three spaces are in
	 * play and only one arithmetic gets them in the right order: the CELL's frame is in the view's coordinates, the
	 * view's `-convertPoint:toView:` with a nil view reaches the WINDOW's, and the window's own frame origin is where
	 * that window sits in the space the popped-up menu's window will be placed in. A button at the window's own
	 * origin hides the middle step, which is exactly the bug this comment exists to stop. */
	if (window != nil) {
		NSRect frame = [window frame];
		NSPoint corner = [controlView convertPoint:NSMakePoint(NSMinX(cellFrame), NSMinY(cellFrame)) toView:nil];

		where = NSMakePoint(frame.origin.x + corner.x, frame.origin.y + corner.y);
	} else {
		/* NO WINDOW, AND THE SESSION GOES AHEAD ANYWAY: `NSMenu`'s own note says a menu with no reachable display
		 * still HAS a session — its state is real and only its ink is missing — so refusing here would make every
		 * behaviour below untestable offscreen. The point is then the frame's corner in its own space. */
		where = NSMakePoint(NSMinX(cellFrame), NSMinY(cellFrame));
	}
	/* **THE HIGHLIGHT IS THIS DOOR'S TO PUT UP AND TAKE DOWN.** Nothing else knows the press and the session are one
	 * gesture, and the call below does not return until the session is over — so the two lines around it are the whole
	 * of "the button is down while its menu is up". */
	[self highlight:YES withFrame:cellFrame inView:controlView];
	if ([controlView respondsToSelector:@selector(setNeedsDisplay:)]) {
		[controlView setNeedsDisplay:YES];
	}
	[(NSMenu *)_menu popUpMenuPositioningItem:nil atLocation:where inView:controlView];
	[self highlight:NO withFrame:cellFrame inView:controlView];
	if ([controlView respondsToSelector:@selector(setNeedsDisplay:)]) {
		[controlView setNeedsDisplay:YES];
	}
}

- (void)dismissPopUp
{
	if (_menu != nil && [(NSMenu *)_menu respondsToSelector:@selector(cancelTracking)]) {
		[(NSMenu *)_menu cancelTracking];
	}
}

/* **THE PICK, WHICH IS WHAT EVERY ITEM IN THE MENU IS POINTED AT.** The menu sends it with the item as the argument.
 * What it does is the whole of this class's behaviour: move the selection (unless this is a pull-down, which chooses
 * nothing), and then FORWARD THE CELL'S OWN ACTION — with the CONTROL as the sender, which is Apple's convention and
 * the one a target expects, since a caller writing `-takeChoice:` wants to be handed the button and not the row. */
- (void)itemSelected:(id)sender
{
	NSInteger index = [self indexOfItem:sender];

	if (index >= 0 && !_pullsDown) {
		[self selectItemAtIndex:index];
	}
	[[NSApplication sharedApplication] sendAction:[self action] to:[self target] from:[self controlView]];
	if ([self controlView] != nil) {
		[[self controlView] setNeedsDisplay:YES];
	}
}

/* ---- THE INK ------------------------------------------------------------------------------------- */

/* **THE TWO ARROW POSITIONS DIFFER IN EXACTLY ONE THING: WHAT THE TITLE GIVES UP.** An arrow AT THE CENTRE is a
 * column on the right that the contents have to keep out of, so the interior is drawn into a frame narrowed by the
 * arrow's own zone. An arrow AT THE BOTTOM is in the corner the contents were never going to reach, so the interior
 * is drawn into the WHOLE frame and its title stays centred on the button — which is the difference the mockup's two
 * popups show, and the only one there is. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSRect content = cellFrame;

	if (_arrowPosition == NSPopUpArrowAtCenter) {
		CGFloat zone = NS_POPUP_ARROW_MARGIN + NS_POPUP_ARROW_WIDTH;

		content.size.width -= zone;
		if (content.size.width < 0.0) {
			content.size.width = 0.0;
		}
	}
	[super drawInteriorWithFrame:content inView:controlView];
	[self cg_drawArrowInFrame:cellFrame];
}

- (void)cg_drawArrowInFrame:(NSRect)cellFrame
{
	CGFloat w = NS_POPUP_ARROW_WIDTH;
	CGFloat h = NS_POPUP_ARROW_HEIGHT;
	CGFloat cx = NSMaxX(cellFrame) - NS_POPUP_ARROW_MARGIN - w / 2.0;
	CGFloat cy = (_arrowPosition == NSPopUpArrowAtCenter)
			     ? NSMidY(cellFrame)
			     : NSMinY(cellFrame) + NS_POPUP_ARROW_LIFT + h / 2.0;
	NSBezierPath *p;
	CGContextRef c;

	/* HALF-POINT CENTRES, so the apex is ONE point rather than a two-point flat — the scroller's own rule, for the
	 * same reason and at the same size. */
	cx = floor(cx) + 0.5;
	cy = floor(cy) + 0.5;
	p = [NSBezierPath bezierPath];
	[p moveToPoint:NSMakePoint(cx - w / 2.0, cy + h / 2.0)];
	[p lineToPoint:NSMakePoint(cx + w / 2.0, cy + h / 2.0)];
	[p lineToPoint:NSMakePoint(cx, cy - h / 2.0)];
	[p closePath];
	/* **AND IT IS FILLED WITH ANTIALIASING OFF, LIKE THE SCROLLER'S ARROWS AND FOR THE SAME REASON.** A triangle this
	 * small is almost entirely edge, so a blended fill reads as GREY rather than as ink. The ink itself is the CELL's
	 * answer — `-cg_inkColor`, which is the same door the title and the image are drawn through — so an arrow cannot
	 * disagree with the words beside it about what colour this button's contents are. */
	c = [[NSGraphicsContext currentContext] CGContext];
	if (c != NULL) {
		CGContextSaveGState(c);
		CGContextSetShouldAntialias(c, false);
		[[self cg_inkColor] setFill];
		[p fill];
		CGContextRestoreGState(c);
	} else {
		[[self cg_inkColor] setFill];
		[p fill];
	}
}

@end
