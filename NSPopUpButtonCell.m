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
#import <AppKit/NSFont.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSGeometry.h>

/* **A POP-UP BUTTON IS A FIELD WITH A CHIP IN IT, AND THAT IS THE WHOLE OF WHAT THE SAMPLE DRAWS.** Not a raised
 * bezel with an arrow beside the words: `Argentum Mockup.png` draws its `NSPopUpButton` as a WHITE RECTANGLE with a
 * one-point border — which is what makes it read as a text field — holding an ACCENT-FILLED CHIP at its right end, and
 * inside that chip TWO TRIANGLES, one pointing up and one down, knocked out of it in white.
 *
 * **AND THE PAIR BESIDE IT IS WHAT MAKES THE SECOND TRIANGLE MEAN SOMETHING.** The sample's `NSComboBox` is the same
 * field with ONE triangle, down; so a doubled arrow is this control's own sign rather than decoration — a combo box
 * opens one way and a pop-up chooses both. The label on each row of that gallery names the control drawn there, which
 * is what settles it.
 *
 * THE SAMPLE'S NUMBERS: its field is 26 points tall, its chip 20 x 20 inset five points from the field's right border,
 * each triangle 10 points across and 5 tall, and 2 points between them. Said as fractions of the FIELD's height,
 * because a pop-up's chip belongs to the field it is drawn in and a small control's field is shorter: */
#define NS_POPUP_CHIP_FRACTION		0.769	/* 20/26 of the field's height, and square */
#define NS_POPUP_CHIP_INSET_FRACTION	0.192	/* 5/26, from the field's right border to the chip's */
#define NS_POPUP_CHEVRON_WIDTH_FRACTION	0.500	/* of the chip, across */
#define NS_POPUP_CHEVRON_HEIGHT_FRACTION 0.250	/* of the chip, apex to base */
#define NS_POPUP_CHEVRON_GAP_FRACTION	0.100	/* of the chip, between the two triangles */
/* **AND THE TITLE'S INSET IS THE FIELD'S, WHICH IS WHY IT IS TWO POINTS RATHER THAN EIGHT.** A pop-up wears a field's
 * face, so its words have to BEGIN where a text field's words begin — the same argument `NSText` makes about the
 * border, and the sample agrees with both: its label starts two points inside the border. `NSText`'s own inset is
 * private to that file, so this is the number restated rather than shared, and the pair has to be kept in step. */
#define NS_POPUP_TITLE_INSET		2.0

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
		/* **AND THE DEFAULT IS THE SAMPLE'S ARRANGEMENT, WHICH IS A DIVERGENCE FROM APPLE'S.** Apple documents
		 * `NSPopUpArrowAtBottom` as the default and that is the corner arrangement; `Argentum Mockup.png` draws
		 * the other one — the arrow on the contents' centre line — and the design is what this tier draws. A
		 * caller who wants Apple's corner asks for it, which is what the property is for. */
		_arrowPosition = NSPopUpArrowAtCenter;
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

/* **AND THE CHIP'S ROOM IS PART OF WHAT THIS CELL MEASURES.** `NSButtonCell` sizes itself to its title and knows
 * nothing about a pop-up's chip, so `-sizeToFit` handed back a frame exactly wide enough for the words and the chip
 * was drawn ON the last letter. The sample's field is 151 points wide for a 125-point label: it hugs its contents at
 * the left and the chip's zone at the right. That zone — the chip and the inset between it and the border — is added
 * here in the SAME fractions the drawing uses, so the measurement and the ink cannot drift apart. */
- (NSSize)cellSizeForBounds:(NSRect)aRect
{
	NSSize size = [super cellSizeForBounds:aRect];

	size.width += size.height * (NS_POPUP_CHIP_FRACTION + NS_POPUP_CHIP_INSET_FRACTION);
	return size;
}

/* ---- THE INK ------------------------------------------------------------------------------------- */

/* **A POP-UP WEARS A FIELD'S FACE, AND DRAWING IT IS WHAT THIS OVERRIDE IS FOR.** `NSButtonCell` draws a raised bezel
 * — `+controlColor`, a thing you press — and the sample draws this control as a TEXT FIELD: white, one point, radius
 * four. `NSText` draws that face already, and its comment is the reason to take the SAME constants rather than
 * look-alikes: a field and the control beside it are noticed when their borders are a shade apart. So the face is the
 * field's, `NSButtonCell`'s bezel is not drawn at all, and the path is inset by half the stroke for the reason both
 * of them do it — a stroke is centred on its path and the drawing layer clips a view to its bounds.
 *
 * **AND A FIELD DOES NOT CHANGE ITS FACE WHEN IT IS PRESSED, WHICH IS A CHOICE THE SAMPLE LEAVES OPEN.** It draws no
 * pressed pop-up, so this tier's reading is the text field's: a field's face is its face whatever is happening to it,
 * and the session this control raises is its own and sufficient feedback. A DISABLED one is white too, for the same
 * reason — nothing else in this tier greys a field out, and a pop-up that did would be the only one that does. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSRect faceRect = NSInsetRect(cellFrame, NS_CELL_BEZEL_WIDTH / 2.0, NS_CELL_BEZEL_WIDTH / 2.0);
	NSBezierPath *bezel = [NSBezierPath bezierPathWithRoundedRect:faceRect
							      xRadius:NS_CELL_BEZEL_RADIUS
							      yRadius:NS_CELL_BEZEL_RADIUS];

	[[NSColor controlBackgroundColor] setFill];
	[bezel fill];
	[[NSColor controlDarkShadowColor] setStroke];
	[bezel setLineWidth:NS_CELL_BEZEL_WIDTH];
	[bezel stroke];
	[self drawInteriorWithFrame:cellFrame inView:controlView];
}

/* **THE CHIP'S RECT, WHICH IS WHERE THE DRAWING AND THE TITLE'S ROOM ARE BOTH MEASURED FROM.** At the sample's
 * position it is a square at the field's right end on the field's centre line; at Apple's other one —
 * `NSPopUpArrowAtBottom` — it sits in the bottom-right corner instead, which is the whole of the difference between
 * the two positions. Its corner radius is `NS_CELL_BEZEL_RADIUS`, the same four points the field's own corners take,
 * because one control with two radii is the sort of thing a person sees without being able to name. */
- (NSRect)cg_chipRectInFrame:(NSRect)cellFrame
{
	CGFloat h = NSHeight(cellFrame);
	CGFloat side = h * NS_POPUP_CHIP_FRACTION;
	CGFloat inset = h * NS_POPUP_CHIP_INSET_FRACTION;
	CGFloat x = NSMaxX(cellFrame) - inset - side;
	CGFloat y = (_arrowPosition == NSPopUpArrowAtCenter)
			    ? NSMidY(cellFrame) - side / 2.0
			    : NSMinY(cellFrame) + inset;

	return NSMakeRect(x, y, side, side);
}

/* **AND THE TITLE IS LEFT-ALIGNED, WHICH IS THE ONE THING `NSButtonCell` CANNOT DO FOR THIS CONTROL.** Its
 * `-drawInteriorWithFrame:` CENTRES what it draws — a button's title and picture sit in the middle of its face — and
 * the sample's label begins at the field's inset instead, because that is where a field's text begins. So the title
 * is drawn here rather than forwarded: the rect is the string's OWN height, placed at the inset and centred on the
 * field, and the drawing is CLIPPED to the room between the inset and the chip, so a title longer than its frame
 * stops at the chip rather than running under it — which is what a field does at its far end.
 *
 * AN ATTRIBUTED TITLE WINS OVER THE PLAIN ONE, which is the cell's own documented answer, and the font and the colour
 * come from the two doors the button's own drawing uses — `-font` and `-cg_inkColor` — so a pop-up's words and a
 * button's cannot come out differently. */
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(id)controlView
{
	NSAttributedString *attributed = [self attributedTitle];
	NSString *title = [self title];
	NSFont *font = (NSFont *)[self font];
	NSDictionary *attributes;
	CGFloat x = NSMinX(cellFrame) + NS_POPUP_TITLE_INSET;
	CGFloat limit = NSMinX([self cg_chipRectInFrame:cellFrame]);
	NSSize tsize = NSZeroSize;
	NSRect room;

	(void)controlView;
	if (font == nil) {
		font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	}
	attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
		      [self cg_inkColor], NSForegroundColorAttributeName, nil];
	if (attributed != nil) {
		tsize = [attributed size];
	} else if (title != nil && [title length] > 0) {
		tsize = [title sizeWithAttributes:attributes];
	}
	/* NOTHING TO SAY: a pop-up whose title is empty is its field and its chip, which is a real state and the one a
	 * caller who sets a menu and no title gets. */
	if (tsize.width > 0.0 && tsize.height > 0.0 && (limit - x) > 0.0) {
		room = NSMakeRect(x, NSMidY(cellFrame) - tsize.height / 2.0, limit - x, tsize.height);
		[NSGraphicsContext saveGraphicsState];
		[[NSBezierPath bezierPathWithRect:room] setClip];
		if (attributed != nil) {
			[attributed drawInRect:room];
		} else {
			[title drawInRect:room withAttributes:attributes];
		}
		[NSGraphicsContext restoreGraphicsState];
	}
	[self cg_drawChipInFrame:cellFrame];
}

/* **THE CHIP, AND THE TWO CHEVRONS KNOCKED OUT OF IT.** A filled rounded square in the platform's accent with the
 * triangles drawn IN THE FIELD'S WHITE — that is the sample's construction, and it is why the arrows are white rather
 * than dark: they are not marks ON the chip, they are holes in it. The accent is `+cg_accentColor`, the same value
 * the menu's selection chip and a pressed button wear, because a highlight is one statement wherever it is made.
 *
 * THE TRIANGLES ARE FILLED WITH ANTIALIASING OFF, like every other triangle this tier draws and for the reason the
 * scroller's carries: a shape this small is almost entirely edge, and a blended fill reads as grey rather than as
 * white. THE CHIP ITSELF IS NOT — it is a curve, and a curve wants the antialiasing this does not. */
- (void)cg_drawChipInFrame:(NSRect)cellFrame
{
	NSRect chip = [self cg_chipRectInFrame:cellFrame];
	NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:chip xRadius:NS_CELL_BEZEL_RADIUS
							     yRadius:NS_CELL_BEZEL_RADIUS];
	CGFloat w = NSWidth(chip) * NS_POPUP_CHEVRON_WIDTH_FRACTION;
	CGFloat h = NSHeight(chip) * NS_POPUP_CHEVRON_HEIGHT_FRACTION;
	CGFloat gap = NSHeight(chip) * NS_POPUP_CHEVRON_GAP_FRACTION;
	CGFloat cx = floor(NSMidX(chip)) + 0.5;
	CGFloat cy = floor(NSMidY(chip)) + 0.5;
	CGContextRef c = [[NSGraphicsContext currentContext] CGContext];
	int i;

	[[NSColor cg_accentColor] setFill];
	[face fill];
	if (c == NULL) {
		return;
	}
	CGContextSaveGState(c);
	CGContextSetShouldAntialias(c, false);
	[[NSColor controlBackgroundColor] setFill];
	/* TWO TRIANGLES, THE UPPER POINTING UP AND THE LOWER DOWN, with the gap the sample leaves between them. Each is
	 * placed off the chip's own centre line so the PAIR is what ends up centred, which is what keeps them from
	 * drifting when the chip is not the sample's twenty points. */
	for (i = 0; i < 2; i++) {
		BOOL up = (i == 0);
		CGFloat lo = up ? (cy + gap / 2.0) : (cy - gap / 2.0 - h);
		CGFloat hi = lo + h;
		NSBezierPath *p = [NSBezierPath bezierPath];

		if (up) {
			[p moveToPoint:NSMakePoint(cx, hi)];
			[p lineToPoint:NSMakePoint(cx + w / 2.0, lo)];
			[p lineToPoint:NSMakePoint(cx - w / 2.0, lo)];
		} else {
			[p moveToPoint:NSMakePoint(cx, lo)];
			[p lineToPoint:NSMakePoint(cx + w / 2.0, hi)];
			[p lineToPoint:NSMakePoint(cx - w / 2.0, hi)];
		}
		[p closePath];
		[p fill];
	}
	CGContextRestoreGState(c);
}

@end
