/*
 * NSMenu — a menu as a list of items, and the class that keeps the tree's links in step.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE WHOLE CLASS IS ONE INVARIANT, KEPT IN ONE PLACE: AN ITEM IN THIS LIST KNOWS WHICH MENU HOLDS IT, AND A
 * MENU ATTACHED TO AN ITEM KNOWS WHICH ITEM HOLDS IT. Both directions are maintained by the four doors that
 * change the list — the two inserts, the two removes — and by `-setSubmenu:forItem:` for the vertical link, so
 * there is no path into this object that leaves the tree describing something other than what it holds. That is
 * what makes `NSMenuItem`'s `-menu`/`-parentItem` doors READWRITE rather than readonly there: this class is
 * their only caller, and it is the caller because it is the only thing that knows.
 *
 * AND THE LINKS POINT DIFFERENT WAYS ON PURPOSE. A menu RETAINS its items — they are its contents, and a menu
 * whose items were deallocated out from under it would be a list of dangling rows. An item does NOT retain its
 * menu or its parent, because that would be the same object graph holding itself up by its own bootstraps: the
 * tree would never be freed. Said out loud because the asymmetry is the kind of thing a later reader "tidies".
 *
 * THE NOTIFICATIONS ARE POSTED THROUGH THE FOUNDATION NOTIFICATION CENTRE, which this tree has — and the one
 * this unit posts is the CHANGE one, because that is the door a caller drives. The tracking notifications
 * belong to the tracking half (the header says which rows are owed and why), and posting one from nowhere
 * would announce a tracking session that never began.
 */
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSMenuItemCell.h>
/* THE HEADERS THIS FILE'S BODIES NEED, AND THEY ARE HERE RATHER THAN BESIDE THE CODE THAT USES THEM: a mid-file
 * import inside an `@implementation` splices the imported header's `@interface` blocks INTO the implementation (see
 * the note in the tracking section, which is where that was learned). The event header serves the key-equivalent
 * door, the window and graphics headers the tracking session, and the application header the popup's own loop —
 * which is the application's `-run` loop, and the reason a popped-up menu tracks until it is dismissed. */
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSApplication.h>

#include <stdio.h>

NSString *NSMenuDidAddItemNotification = @"NSMenuDidAddItemNotification";
NSString *NSMenuDidChangeItemNotification = @"NSMenuDidChangeItemNotification";
NSString *NSMenuDidRemoveItemNotification = @"NSMenuDidRemoveItemNotification";
NSString *NSMenuDidSendActionNotification = @"NSMenuDidSendActionNotification";
NSString *NSMenuWillSendActionNotification = @"NSMenuWillSendActionNotification";
NSString *NSMenuDidBeginTrackingNotification = @"NSMenuDidBeginTrackingNotification";
NSString *NSMenuDidEndTrackingNotification = @"NSMenuDidEndTrackingNotification";

@implementation NSMenu

- (instancetype)init
{
	return [self initWithTitle:@""];
}

- (instancetype)initWithTitle:(NSString *)aTitle
{
	if ((self = [super init]) != nil) {
		_title = [aTitle copy];
		_items = [[NSMutableArray alloc] init];
		/* **AND THE ONE FIELD WHOSE DEFAULT IS NOT ZERO, WHICH THE PROBE FOUND BY FAILING.** Objective-C zeroes an
		 * object's storage, so a flag added to this class is OFF unless the initialiser says otherwise — and this
		 * one has to start ON, because a menu that announced nothing by default would be a menu nobody could
		 * observe. The switch itself worked on the first run and its DEFAULT did not: the probe's
		 * "announces-by-default" check is what caught the difference, which is the case for asserting defaults
		 * rather than only transitions. */
		_menuChangedMessagesEnabled = YES;
	}
	return self;
}

- (void)dealloc
{
	/* THE ITEMS ARE RELEASED ONE AT A TIME, DETACHED FIRST, which is the same work `-removeAllItems` does and
	 * has to happen here too: an item that outlives its menu (a caller kept a reference) must not go on
	 * believing it is in one. */
	[self removeAllItems];
	[_items release];
	[_title release];
	[super dealloc];
}

/* ---- THE TITLE AND THE UPWARD LINK -------------------------------------------------------------- */

- (NSString *)title
{
	return _title;
}

- (void)setTitle:(NSString *)string
{
	if (string != _title) {
		NSString *copy = [string copy];

		[_title release];
		_title = copy;
	}
}

- (id)supermenu
{
	return _supermenu;
}

- (void)setSupermenu:(id)supermenu
{
	/* NULLABLE ASYMMETRY, and both halves are deliberate: an item's submenu is TOLD which item holds it (the
	 * argument), while an item's submenu is also told when it is DETACHED (nil). The memory policy is
	 * NSMenuItem's — the link up is not retained — so this is a plain assignment. */
	_supermenu = supermenu;
}

/* ---- THE LIST, AND THE ONE PLACE THE LINKS ARE KEPT IN STEP ------------------------------------ */

- (void)insertItem:(NSMenuItem *)newItem atIndex:(NSInteger)index
{
	if (newItem == nil) {
		return;			/* Apple's `addItem:` does not document nil, and a list cannot hold one */
	}
	if (index < 0) {
		index = 0;
	}
	if (index > (NSInteger)[_items count]) {
		index = (NSInteger)[_items count];
	}
	/* BOTH BOOKKEEPING ACTS BEFORE THE INSERT, so an item is never briefly in a list that does not know it. */
	[newItem setMenu:self];
	[newItem retain];
	[_items insertObject:newItem atIndex:(NSUInteger)index];
	[newItem release];
	/* AND THE VERTICAL LINK IS RESTORED IF THE ITEM ALREADY HAD A SUBMENU, which is what makes re-inserting an
	 * item that was removed (and detached) work without the caller telling it again. */
	if ([newItem submenu] != nil) {
		[[newItem submenu] setSupermenu:newItem];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidAddItemNotification object:self];
}

- (void)addItem:(NSMenuItem *)newItem
{
	[self insertItem:newItem atIndex:(NSInteger)[_items count]];
}

- (NSMenuItem *)insertItemWithTitle:(NSString *)aString
			     action:(SEL)aSelector
		      keyEquivalent:(NSString *)charCode
			    atIndex:(NSInteger)index
{
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:aString
						     action:aSelector
					      keyEquivalent:charCode];

	[self insertItem:item atIndex:index];
	return [item autorelease];
}

- (NSMenuItem *)addItemWithTitle:(NSString *)aString
			  action:(SEL)aSelector
		  keyEquivalent:(NSString *)charCode
{
	return [self insertItemWithTitle:aString
				  action:aSelector
			   keyEquivalent:charCode
				 atIndex:(NSInteger)[_items count]];
}

- (void)removeItemAtIndex:(NSInteger)index
{
	NSMenuItem *item;

	if (index < 0 || index >= (NSInteger)[_items count]) {
		return;
	}
	item = [[_items objectAtIndex:(NSUInteger)index] retain];
	/* DETACHED BEFORE IT LEAVES, so a caller holding the item cannot ask it about a menu that no longer holds
	 * it — and so its own submenu, if it has one, stops pointing at a tree it is no longer in. */
	[item setMenu:nil];
	[item setParentItem:nil];
	if ([item submenu] != nil) {
		[[item submenu] setSupermenu:nil];
	}
	[_items removeObjectAtIndex:(NSUInteger)index];
	[item release];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidRemoveItemNotification object:self];
}

- (void)removeItem:(NSMenuItem *)item
{
	NSInteger i = [self indexOfItem:item];

	if (i != NSNotFound) {
		[self removeItemAtIndex:i];
	}
}

- (void)removeAllItems
{
	while ([_items count] > 0) {
		[self removeItemAtIndex:0];
	}
}

- (NSArray *)itemArray
{
	/* A COPY, which is Apple's contract for this door and this tree's rule for any array it hands out: a caller
	 * that could mutate the answer could change the menu's contents without going through the doors that keep
	 * the links in step. */
	return [[_items copy] autorelease];
}

- (NSInteger)numberOfItems
{
	return (NSInteger)[_items count];
}

- (NSMenuItem *)itemAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)[_items count]) {
		return nil;
	}
	return [_items objectAtIndex:(NSUInteger)index];
}

/* ---- THE FINDS, EACH ANSWERING NSNotFound RATHER THAN RAISING ---------------------------------- */

- (NSInteger)indexOfItem:(NSMenuItem *)index
{
	if (index == nil) {
		return NSNotFound;
	}
	return (NSInteger)[_items indexOfObjectIdenticalTo:index];
}

- (NSInteger)indexOfItemWithTitle:(NSString *)aTitle
{
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		NSMenuItem *item = [_items objectAtIndex:i];

		if ([[item title] isEqualToString:aTitle]) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (NSInteger)indexOfItemWithTag:(NSInteger)aTag
{
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		if ([[_items objectAtIndex:i] tag] == aTag) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (NSInteger)indexOfItemWithRepresentedObject:(id)object
{
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		id rep = [[_items objectAtIndex:i] representedObject];

		/* IDENTITY, NOT `-isEqual:`, because a represented object is a thing a caller put there and two
		 * different objects that happen to compare equal are not the same item's payload. */
		if (rep == object) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (NSInteger)indexOfItemWithSubmenu:(id)submenu
{
	NSUInteger i;

	if (submenu == nil) {
		return NSNotFound;
	}
	for (i = 0; i < [_items count]; i++) {
		if ([[_items objectAtIndex:i] submenu] == submenu) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)actionSelector
{
	NSUInteger i;

	for (i = 0; i < [_items count]; i++) {
		NSMenuItem *item = [_items objectAtIndex:i];

		if ([item target] == target && [item action] == actionSelector) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (NSMenuItem *)itemWithTitle:(NSString *)aTitle
{
	NSInteger i = [self indexOfItemWithTitle:aTitle];

	return i == NSNotFound ? nil : [_items objectAtIndex:(NSUInteger)i];
}

- (NSMenuItem *)itemWithTag:(NSInteger)tag
{
	NSInteger i = [self indexOfItemWithTag:tag];

	return i == NSNotFound ? nil : [_items objectAtIndex:(NSUInteger)i];
}

/* ---- AND THE VERTICAL LINK --------------------------------------------------------------------- */

- (void)setSubmenu:(id)aMenu forItem:(NSMenuItem *)anItem
{
	if (anItem == nil) {
		fprintf(stderr, "APPKIT-REFUSE: -setSubmenu:forItem: needs an item — Apple's own comment says the "
				"item may not be nil, and attaching a menu to nothing would leave the menu pointing at "
				"an item that does not exist\n");
		return;
	}
	[anItem setSubmenu:aMenu];
	/* BOTH DIRECTIONS, IN ONE CALL — which is the whole reason this door exists rather than the caller writing
	 * the two lines: the item now holds the menu, and the menu now knows which item holds IT. */
	[aMenu setSupermenu:anItem];
}

/* ---- AN ITEM CHANGED, AND SENDING AN ITEM'S ACTION --------------------------------------------- */

/* THE SWITCH THAT MAKES A BATCH OF EDITS QUIET, AND ITS READER IS THE DOOR BELOW. `-menuChangedMessagesEnabled`
 * exists because announcing every change of every item is expensive while a caller is rebuilding a menu: a caller
 * turns it OFF, edits, and turns it on again. So it is shipped rather than owed — this class asks it — and it
 * starts ON, because a menu that announced nothing by default would be a menu nobody could observe. */
- (BOOL)menuChangedMessagesEnabled
{
	return _menuChangedMessagesEnabled;
}

- (void)setMenuChangedMessagesEnabled:(BOOL)flag
{
	_menuChangedMessagesEnabled = flag;
}

- (void)itemChanged:(NSMenuItem *)item
{
	(void)item;
	/* THE CLASS ANNOUNCES IT, and the object is the MENU rather than the item: a delegate registers for a
	 * menu's changes, not for the seven hundred conceivable objects that could be an item.
	 *
	 * **AND IT ASKS THE SWITCH FIRST, WHICH IS THE WHOLE OF WHY THAT ROW IS SHIPPED**: the flag is consulted HERE,
	 * by the door that would announce, so it is not a field stored and consulted nowhere — the ground the previous
	 * units left it open on. A silenced menu still does its other work; it simply says nothing. */
	if (!_menuChangedMessagesEnabled) {
		return;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidChangeItemNotification object:self];
}

- (BOOL)performActionForItemAtIndex:(NSInteger)index
{
	NSMenuItem *item = [self itemAtIndex:index];

	if (item == nil) {
		return NO;
	}
	/* THE WILL-SEND NOTICE GOES OUT BEFORE THE SEND, which is what makes it useful for a caller that wants to
	 * know an action is about to happen, and the DID-SEND one after — Apple's pair, in Apple's order. */
	[[NSNotificationCenter defaultCenter] postNotificationName:NSMenuWillSendActionNotification object:item];
	/* TARGET/ACTION, AND ONLY ONE OF THE TWO SHAPES IS THIS CLASS'S. A NAMED TARGET is dispatched right here,
	 * through the item's own action and with the item as the argument. A NIL TARGET MEANS "whoever implements
	 * it" — the RESPONDER CHAIN — and that needs the APPLICATION'S dispatch: a key window, its first responder
	 * and the walk up from there, which is the wiring the tracking half of this class owns. So the door REFUSES
	 * BY NAME rather than reaching for a walk this class cannot make, because a wrong dispatch is worse than a
	 * named refusal: this object is a menu, and the first thing a guessed walk would do is send an action to it.
	 *
	 * (THE FIRST VERSION OF THIS DOOR CALLED `-tryToPerform:with:` ON ITSELF — a method NSMenu does not
	 * implement — and THIS TREE RAISES on that rather than returning nil, so it ABORTED THE PROBE instead of
	 * failing a check. That is the loudest way a wrong guess can present, and the reason the check is now
	 * asserted through a named refusal rather than through a walk that does not exist.) */
	if ([item target] != nil) {
		if (![[item target] respondsToSelector:[item action]]) {
			return NO;
		}
		[[item target] performSelector:[item action] withObject:item];
	} else {
		fprintf(stderr, "APPKIT-REFUSE: -performActionForItemAtIndex: cannot dispatch an item whose target "
				"is NIL — that means the responder chain, and the walk belongs to the application's "
				"dispatch (the tracking half of this class). Give the item a target\n");
		return NO;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidSendActionNotification object:item];
	return YES;
}

/* ---- THE GEOMETRY, AND THE WALK THAT IS WHAT READS THE SWITCHES -------------------------------- */

/* THE STATE COLUMN'S WIDTH, AND THE NUMBER IS THIS TIER'S: Apple's own is not published, and the drawing half
 * (the plan's own note) is what will own the real measurement — ONE NUMBER IN ONE PLACE keeps that a change here
 * rather than a hunt. It is a constant rather than a field because nothing sets it: the only question a caller
 * asks is whether the column is RESERVED, which is what `-showsStateColumn` answers. */
static const CGFloat NSMenuStateColumnWidth = 20.0;

- (NSSize)size
{
	NSSize s = _size;
	CGFloat floorWidth = _minimumWidth + (_showsStateColumn ? NSMenuStateColumnWidth : 0.0);

	/* **AND THIS IS WHERE `-showsStateColumn` GETS ITS READER**, which is the rule this class's slice was drawn
	 * by: the switch is not a fact stored and consulted nowhere, it WIDENS THE FLOOR the menu answers with. A
	 * stated deviation, and the reason is the same gap `-sizeToFit` refuses over: Apple computes a menu's width
	 * from its items' titles, key equivalents and images; this tier has no text metrics on this side, so the
	 * width is the caller's or the floor, and the height is always the caller's. */
	if (s.width < floorWidth) {
		s.width = floorWidth;
	}
	return s;
}

- (void)setSize:(NSSize)aSize
{
	_size = aSize;
}

- (CGFloat)minimumWidth
{
	return _minimumWidth;
}

- (void)setMinimumWidth:(CGFloat)width
{
	_minimumWidth = width;
}

- (BOOL)showsStateColumn
{
	return _showsStateColumn;
}

- (void)setShowsStateColumn:(BOOL)flag
{
	_showsStateColumn = flag;
}

- (id)font
{
	return _font;
}

- (void)setFont:(id)font
{
	if (font != _font) {
		id held = [font retain];

		[_font release];
		_font = held;
	}
}

- (void)sizeToFit
{
	fprintf(stderr, "APPKIT-REFUSE: -sizeToFit needs TEXT METRICS — a menu's width is its widest item's title "
			"plus its key equivalents and its images — and this tier has no font stack on this side of the "
			"library, so a size computed here would be a guess wearing a measurement's clothes\n");
}

+ (CGFloat)menuBarHeight
{
	/* ZERO, AND THAT IS APPLE'S OWN ANSWER FOR A MENU THAT IS NOT IN A MENU BAR — which is every menu in this
	 * tier, because the bar belongs to the DESKTOP and the desktop draws its own chrome (the plan's D6: the
	 * guest's window manager paints none). A number here would be a height nothing has measured; when the
	 * desktop publishes its bar geometry, this becomes the reader of it. */
	return 0.0;
}

- (id)delegate
{
	return _delegate;
}

- (void)setDelegate:(id)delegate
{
	/* NOT RETAINED, and the assignment is the whole difference from `-setFont:` above: an owner that retained its
	 * delegate could not be freed while that delegate were alive. */
	_delegate = delegate;
}

- (BOOL)autoenablesItems
{
	return _autoenablesItems;
}

- (void)setAutoenablesItems:(BOOL)flag
{
	_autoenablesItems = flag;
}

- (NSMenuProperties)propertiesToUpdate
{
	return _propertiesToUpdate;
}

- (void)update
{
	NSInteger i;
	id delegate = _delegate;

	/* THE DELEGATE GOES FIRST, and only when it ANSWERS the selector: `NSMenuDelegate` is a protocol this tier has
	 * not got, so the property is an `id` and the optional method is asked about BY SELECTOR — which is also why
	 * the call goes through `-performSelector:`: a direct message to an `id` whose selector no header declares is
	 * exactly what `-Wobjc-method-access` exists to warn about, and this is the one place where the honest fix is
	 * the indirection rather than a declaration of a protocol that does not exist. */
	if ([delegate respondsToSelector:@selector(menuNeedsUpdate:)]) {
		[delegate performSelector:@selector(menuNeedsUpdate:) withObject:self];
	}
	/* AND EVERY PROPERTY IS OFFERED, which is what `-propertiesToUpdate` is FOR: Apple's door exists to be called
	 * from inside a delegate callback to find out which parts of the menu need rebuilding, so a menu that never
	 * set it would be a door with no writer. OFFERING EVERYTHING IS ALWAYS CORRECT — Apple's own documentation
	 * says "it is always acceptable to fully update the menu" — so this tier takes that option rather than
	 * guessing which parts a caller will touch. */
	_propertiesToUpdate = NSMenuPropertyItemTitle | NSMenuPropertyItemAttributedTitle |
			      NSMenuPropertyItemKeyEquivalent | NSMenuPropertyItemImage |
			      NSMenuPropertyItemEnabled | NSMenuPropertyItemAccessibilityDescription;
	for (i = 0; i < (NSInteger)[_items count]; i++) {
		NSMenuItem *item = [_items objectAtIndex:(NSUInteger)i];
		id target;

		if ([item submenu] != nil) {
			[[item submenu] update];	/* a submenu updates with its parent, all the way down */
			continue;
		}
		if (!_autoenablesItems || [item isSeparatorItem]) {
			continue;
		}
		target = [item target];
		/* THE AUTO-ENABLING RULE, AND ONLY THE HALF THIS CLASS CAN ANSWER: an item that NAMES a target is enabled
		 * exactly when that target answers the action. AN ITEM WITH NO TARGET MEANS THE RESPONDER CHAIN, and this
		 * class cannot walk it — the same ground `-performActionForItemAtIndex:` refuses on — so the item is LEFT
		 * ALONE rather than enabled or disabled on a guess. A guessed enablement is a menu offering an action
		 * that then does nothing, which is worse than a menu that declines to say. */
		if (target != nil) {
			[item setEnabled:([item action] != NULL && [target respondsToSelector:[item action]])];
		}
	}
}

/* ---- AND THE SETTERS THE LEDGER ASKS FOR BY NAME ------------------------------------------------ */

/* THE SIX DOORS THIS UNIT EXISTS FOR ARE DECLARED IN THE HEADER AND **ALREADY IMPLEMENTED ABOVE** — that is what
 * made them invisible, not their absence. THE FIRST VERSION OF THIS SECTION REPEATED ALL SIX BODIES and clang
 * refused the file with six "duplicate declaration of method" errors, which is the loudest possible form of the
 * lesson: a door that is implemented and UNDECLARED looks exactly like a door that is not implemented, from every
 * side except the compiler's. The declarations are the fix; the bodies were already here. */

/* ---- THE TRACKING SESSION, AND THE DOORS AROUND IT THAT ARE STILL REFUSALS ---------------------- */

/* THE TWO HEADERS THIS SECTION NEEDS, AND THEY ARE IMPORTED HERE RATHER THAN AT THE TOP because the session is
 * the only thing in the file that needs them.
 *
 * **AND THEY LIVE AT THE TOP OF THE FILE RATHER THAN HERE, WHICH IS A COMPILER FACT AND NOT A STYLE PREFERENCE: a
 * mid-file `#import` INSIDE an `@implementation` splices the imported header's `@interface` blocks INTO the
 * implementation, and clang's answer to that is "missing '@end'" on the imported header, followed by "missing
 * context for method declaration" on every method in this file after it — twenty errors that all point at the
 * wrong place. The first version of this section imported them right here and the build said exactly that.**
 *
 * AND THE LESSON IS ALREADY IN THIS FILE, ONE UNIT OLD AND INVISIBLY: the key-equivalent door imports the EVENT
 * header mid-file too, and it compiled only because that header was ALREADY included by the time the directive was
 * reached — a no-op rather than a splice. An import that works by accident is a trap for whoever reorders the
 * includes above it, which is why these two did not repeat the trick. */

/* A ROW'S HEIGHT, AND THE NUMBER IS THIS TIER'S for the same reason the state column's width is: Apple's comes from
 * the font, this tier has no metrics on this side, and ONE NUMBER IN ONE PLACE keeps that a change here rather
 * than a hunt. It is also what the session's hit-testing and its painting agree about, which is the property that
 * matters — the two must use the SAME arithmetic or the menu highlights a row it does not draw. */
/* **THE ROW HEIGHT MOVED TO `NSMenuView.h` WHEN A SECOND FILE NEEDED IT.** A dropdown's window is measured with it
 * and the view that fills that window lays its rows out with it, so the two must agree; it is declared once and
 * defined by the view. */

/* THE PAINT, AND IT IS GEOMETRY RATHER THAN INK: the panel's background, a separator between each pair of rows,
 * and the highlighted row filled — all of which this tier HAS (NSColor, CoreGraphics, a window's context) while
 * text does not. **AND THAT IS NO LONGER TRUE — THE LABELS LANDED**: the font stack was looking in
 * `/System/Library/Fonts`, so every label was owed to a registry that found no fonts at all. With that fixed, this
 * pass draws each row's TITLE and KEY EQUIVALENT through an `NSMenuItemCell`, which is the class that owns a row's
 * parts. What is still hand-drawn here is the panel, the highlight and the separators. */
- (void)cg_repaintSession
{
	/* **THE REPAINT IS THE VIEW'S NOW, AND IT HAD TO BECOME SO.** This method used to paint the panel, the
	 * highlight and the separators into a context taken over the tracking window with
	 * `+graphicsContextWithWindow:` — WHICH REFUSES IN THIS TIER, because the only destination `NSGraphicsContext`
	 * honours is a bitmap rep. So a popped-up menu drew NOTHING AT ALL: not the panel, not the rows, not the
	 * labels. The note here claimed a menu "you can see and use but not read" and THAT WAS TOO GENEROUS — there
	 * was nothing to see.
	 *
	 * MEASURED, on a nested run against this project's own window server: a menu with four items was up for 200
	 * event passes and the composited output held FOUR colours — the background, the bar, the System menu's glyph
	 * and the application's window. The menu was not among them.
	 *
	 * The reason is the PRESENT. A window's pixels reach the compositor only in `NSWindow -cg_drawFrame`, which
	 * paints its background, its content view's tree, its chrome, and then hands the buffer over. A menu that
	 * paints into the window's context behind that path writes pixels nobody presents. SO THE MENU'S CONTENT IS
	 * AN `NSMenuView`, and displaying the window is what draws the menu. */
	[(NSMenuView *)_menuView setMenu:self];
	[(NSMenuView *)_menuView setHighlightedItem:_highlightedItem];
	[(NSMenuView *)_menuView setNeedsDisplay:YES];
	/* **MARKED STALE AND THEN TRIED — AND BOTH HALVES ARE THE FIX.** `-display` alone PAINTS NOW and gives up if
	 * the compositor still holds the previous buffer: MEASURED, a menu opened by a click did not appear until the
	 * pointer moved again, because the one paint it asked for was dropped and NOTHING RETRIED IT. The flag is what
	 * makes the run loop's per-pass `-displayIfNeeded` try again; the `-displayIfNeeded` here is what paints at
	 * once when the buffer is free, so a session with no run loop still draws. */
	[_trackingWindow setNeedsDisplay:YES];
	[_trackingWindow displayIfNeeded];
}

/* THE ROW UNDER A POINT — the arithmetic the paint above shares, which is why the row height is one constant: THE
 * TOP ROW IS THE FIRST ITEM (a frame's origin is its bottom-left), so the row index counts DOWN from the top.
 *
 * **AND THE POINT ARRIVES IN THE WINDOW'S COORDINATES AND IS CONVERTED HERE, WHICH IS A DEFECT THE PROBE COULD NOT
 * SEE.** An event's `-locationInWindow` is measured from the WINDOW's bottom-left; this session hit-tests in the
 * FRAME's coordinates — and because a popped-up menu's window is BORDERLESS, its frame IS its content, so the
 * conversion is the frame's origin added to the point and nothing else. The first version compared the raw window
 * point against the frame, WHICH IS ONLY EVER RIGHT WHEN THE MENU OPENS AT THE SCREEN'S ORIGIN — and the probe
 * passed anyway, because a stand-in hands back whatever space the session is reading, so a right space and a wrong
 * one are indistinguishable to a test that supplies both sides of the comparison. THAT IS THE SHAPE OF BUG A
 * STAND-IN CANNOT CATCH, which is why the check that pins it is written against a KNOWN frame origin rather than
 * against the session's own answer: the window's origin corner must be the LAST row. */
- (NSMenuItem *)cg_itemAtPoint:(NSPoint)point
{
	NSInteger count = (NSInteger)[_items count];
	NSPoint screen;
	CGFloat y;
	NSInteger row;

	if (count == 0 || _trackingFrame.size.height <= 0.0) {
		return nil;
	}
	screen = NSMakePoint(_trackingFrame.origin.x + point.x, _trackingFrame.origin.y + point.y);
	if (screen.x < _trackingFrame.origin.x || screen.x > NSMaxX(_trackingFrame) ||
	    screen.y < _trackingFrame.origin.y || screen.y > NSMaxY(_trackingFrame)) {
		return nil;
	}
	y = screen.y - _trackingFrame.origin.y;
	row = count - 1 - (NSInteger)(y / NSMenuRowHeight);
	if (row < 0 || row >= count) {
		return nil;
	}
	return [_items objectAtIndex:(NSUInteger)row];
}

/* THE ROW THE POINTER IS OVER, written by the step below and READ BY THE PAINT above — which is the reader this
 * row was owed while the session did not exist. Setting it repaints when a session is up, because the highlight IS
 * what the paint draws. */
- (NSMenuItem *)highlightedItem
{
	return _highlightedItem;
}

- (void)setHighlightedItem:(NSMenuItem *)item
{
	if (item != _highlightedItem) {
		_highlightedItem = item;
		if (_tracking) {
			[self cg_repaintSession];
		}
	}
}

/* THE TEAR-OFF FLAG'S TWO DOORS, WHICH SIT HERE BECAUSE THEY ARE THE SESSION'S STATE RATHER THAN THE CLASS'S
 * CONTENT: a menu is torn off or it is not, and the only thing that reads it is the step below. APPLE'S SETTER IS
 * INTERNAL, so this tier's is a seam spelled `cg_` like the rest of this class's private plumbing — and the header
 * says why: a menu bar tears a menu off itself to set it, and this tier has no bar, so the door is a seam rather
 * than a gesture. */
- (BOOL)tornOff
{
	return _tornOff;
}

- (void)cg_setTornOff:(BOOL)flag
{
	_tornOff = flag;
}

/* THE LOOP'S BODY. It takes ONE event and answers whether the session is still up — so a caller with a run loop
 * writes `while ([menu cg_trackOneEvent:[app nextEventMatchingMask:...]]) { }` and nothing else. */
- (BOOL)cg_trackOneEvent:(id)event
{
	NSUInteger type;

	if (!_tracking) {
		return NO;
	}
	if (event == nil) {
		return YES;			/* nothing happened this turn; the session is still up */
	}
	type = (NSUInteger)[event type];
	/* **AN EVENT THAT CAME IN THE SUBMENU'S WINDOW IS THE SUBMENU'S OWN, AND THAT IS THE WHOLE OF THE ROUTING.**
	 * Each menu hit-tests in ITS OWN frame with its own arithmetic, so the two never have to agree about a
	 * coordinate space — the parent only has to recognise that the event is not its. (The child's window is read
	 * straight off the child because these fields are PROTECTED: another instance of the same class may read them,
	 * which is exactly the case here and the reason no accessor is owed.) AN EVENT THAT NAMES NO WINDOW IS THE
	 * PARENT'S — a stand-in, or a host with no display — since the parent is the only space it could be in. */
	if (_openSubmenu != nil && ((NSMenu *)_openSubmenu)->_trackingWindow != nil &&
	    [event respondsToSelector:@selector(window)] &&
	    [event window] == ((NSMenu *)_openSubmenu)->_trackingWindow) {
		if (![_openSubmenu cg_trackOneEvent:event]) {
			/* THE CHILD ENDED ITSELF — a pick in it, or a dismissal — AND THAT TAKES THE PARENT WITH IT: choosing
			 * from a submenu closes the whole menu, which is what a menu is. */
			_openSubmenu = nil;	/* only the SESSION is forgotten; the item still owns the menu */
			[self cancelTracking];
			return NO;
		}
		return YES;
	}
	/* **AND A PRESS OUTSIDE THE MENU ENDS IT AT ONCE, REMEMBERING WHERE — AND IT GOES FIRST.** The branch below
	 * handles `NSLeftMouseDown` too ("a press is deliberately not a pick"), so a check placed after it is DEAD CODE
	 * that never runs: MEASURED, the second click was still eaten and the open menu never moved. Waiting for the
	 * release would swallow the whole click, and the click is how a menu bar is told to switch: the loop that owns
	 * the events must hand the point back rather than keep it. A press INSIDE is the menu's own, and nothing changes
	 * for it. */
	if (type == NSLeftMouseDown) {
		NSPoint at = [event locationInWindow];

		if ([self cg_itemAtPoint:at] == nil) {
			_dismissedAt = at;
			_hasDismissedAt = YES;
			[self cancelTracking];
			return NO;
		}
	}
	if (type == NSLeftMouseDown || type == NSLeftMouseDragged || type == NSMouseMoved ||
	    type == NSRightMouseDown) {
		/* **AND A DRAG THAT LEAVES THE MENU ENDS THE SESSION, which is how a menu bar switches menus.** On the Mac
		 * you press a title, drag sideways and the menus change under the pointer without releasing. The bar cannot
		 * do that from outside this loop — the loop owns the events — so the loop ends itself and the bar re-opens
		 * whatever title the pointer is over. A drag WITHIN the menu is untouched. */
		if (type == NSLeftMouseDragged && [self cg_itemAtPoint:[event locationInWindow]] == nil) {
			/* **AND NOT WHEN THE DRAG IS STILL INSIDE THIS MENU'S PARENT, WHICH IS THE CASE THE FIRST VERSION GOT
			 * WRONG.** A menu opened from the MENU BAR is held down while the pointer sits OVER THE BAR — that is
			 * where a person's hand is — and the bar is outside the menu's frame by definition, so every small
			 * movement ended the session: MEASURED, "the highlight chip shows for one frame, and sometimes the menu
			 * is visible for that frame, and then nothing". The rule is about a pointer that has LEFT THE THING THE
			 * MENU BELONGS TO, not one that has left the menu's own rectangle. */
			/* **AND THE QUESTION IS THE SAME ONE THAT DECIDED WHETHER THIS MENU TRACKS AT ALL: IS ITS PARENT
			 * RUNNING A SESSION?** A submenu opened by hovering inside its parent is the parent's to drive, so a
			 * drag off it means "leave the submenu" and the child ends. A menu opened from the BAR has a parent
			 * that is NOT tracking — the bar is not a session, it is a window with a view — and the pointer is
			 * legitimately over that bar the whole time the button is held. MEASURED, the first version asked
			 * whether the drag was outside the PARENT'S TRACKING WINDOW, and the bar has none, so it answered
			 * "yes, it left" for every movement and the menu closed on the first one. */
			if (_supermenu != nil && ((NSMenu *)_supermenu)->_tracking) {
				[self cancelTracking];
				return NO;
			}
		}
		/* MOVEMENT SETS THE HIGHLIGHT AND NOTHING ELSE. A press is deliberately not a pick: Apple sends the action
		 * on the RELEASE, which is what makes a drag off a row cancel it. */
		[self setHighlightedItem:[self cg_itemAtPoint:[event locationInWindow]]];
		/* **AND THE SUBMENU FOLLOWS THE HIGHLIGHT, WHICH IS THE WHOLE OF THE SUBMENU'S RULE**: an item that HAS one
		 * opens it beside itself; an item that has not closes whatever is open. The child is opened as A SESSION OF
		 * ITS OWN through the ordinary popup door — at the place `-locationForSubmenu:` computes, which makes that
		 * door the READER of the geometry rather than a factory for a number nothing consumes. */
		if (_highlightedItem != nil && [_highlightedItem submenu] != nil) {
			if (_openSubmenu != [_highlightedItem submenu]) {
				[self cg_closeSubmenu];
				_openSubmenu = [_highlightedItem submenu];
				[_openSubmenu popUpMenuPositioningItem:nil
							    atLocation:[self locationForSubmenu:_openSubmenu]
							       inView:nil];
			}
		} else {
			[self cg_closeSubmenu];
		}
		return YES;
	}
	if (type == NSLeftMouseUp && _openedByPress) {
		_openedByPress = NO;
		return YES;		/* the press that opened the menu, coming up: the menu stays */
	}
	if (type == NSLeftMouseUp) {
		/* **THE PICK IS THE RELEASE, AND RELEASING OVER NOTHING IS A DISMISSAL RATHER THAN A PICK** — which is what
		 * makes a click outside the menu close it without sending anything. */
		NSMenuItem *picked = [self cg_itemAtPoint:[event locationInWindow]];

		if (picked != nil && [picked isEnabled] && ![picked isSeparatorItem]) {
			[self performActionForItemAtIndex:[self indexOfItem:picked]];
		}
		/* **AND A MENU THAT HAS BEEN TORN OFF STAYS UP THROUGH BOTH HALVES OF THAT**, which is the whole of what
		 * the flag means: a pick from a torn-off menu SENDS ITS ACTION AND LEAVES THE MENU WHERE IT IS, and a click
		 * outside neither picks nor dismisses, because a torn-off menu is a palette rather than a popup. ONE LINE
		 * OF BEHAVIOUR IN ONE PLACE, and the check beside it asserts both halves rather than one. ESCAPE STILL
		 * CLOSES IT — the key branch below is deliberately untouched — so a torn-off menu is not a trap. */
		if (_tornOff) {
			return YES;
		}
		[self cancelTracking];
		return NO;
	}
	if (type == NSKeyDown) {
		NSString *characters = [event charactersIgnoringModifiers];

		/* ESCAPE, which is a dismissal and not a pick. */
		if (characters != nil && [characters isEqualToString:@"\033"]) {
			[self cancelTracking];
			return NO;
		}
		/* AND ANY OTHER KEY IS OFFERED TO THE MENU ITSELF, which is `-performKeyEquivalent:` getting the caller it
		 * never had: a menu bar is handed keystrokes for every menu below it, and this is the door that decides. */
		if ([self performKeyEquivalent:event]) {
			[self cancelTracking];
			return NO;
		}
	}
	return YES;
}

/* CLOSING WHATEVER SUBMENU IS OPEN, in one place because three doors need it: the highlight moving off a holder,
 * the parent's own session ending, and a switch to a different holder. THE CHILD IS ASKED TO CANCEL ITS OWN
 * SESSION rather than being torn down from here, so all of a menu's state comes down its own door. */
- (void)cg_closeSubmenu
{
	if (_openSubmenu != nil) {
		[_openSubmenu cancelTracking];
		_openSubmenu = nil;	/* NOT RELEASED: the item that holds the submenu owns it */
	}
}

/* BEGINNING A SESSION: a borderless window sized from the menu's own geometry, painted, and announced. THE MENU
 * IS NOT BLOCKED ON — see the header: this tier has no run loop to block in. */
- (void)popUpMenuPositioningItem:(NSMenuItem *)item atLocation:(NSPoint)location inView:(id)view
{
	double t0 = [NSDate timeIntervalSinceReferenceDate];
#define DIAG(...) do { if (getenv("APPKIT_MENU_DIAG") != NULL) { fprintf(stderr, __VA_ARGS__); } } while (0)
	NSSize size;

	(void)item;
	(void)view;
	if (_tracking) {
		fprintf(stderr, "APPKIT-REFUSE: -popUpMenuPositioningItem:atLocation:inView: cannot begin a session "
				"while one is already up — one menu at a time is the shape of this tier's tracking\n");
		return;
	}
	if ([_items count] == 0) {
		fprintf(stderr, "APPKIT-REFUSE: -popUpMenuPositioningItem:atLocation:inView: needs a menu with items — "
				"there is nothing to show\n");
		return;
	}
	size = [self size];
	DIAG("  DIAG open: -size took %.1f ms\n", ([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
	if (size.width <= 0.0) {
		size.width = 120.0;	/* a floor, because a menu narrower than this is not usable */
	}
	size.height = (CGFloat)[_items count] * NSMenuRowHeight;
	if (size.height < NSMenuRowHeight) {
		size.height = NSMenuRowHeight;
	}
	/* THE FRAME HANGS BELOW-LEFT OF THE POINT, which is where a menu opens from a click. */
	_trackingFrame = NSMakeRect(location.x, location.y - size.height, size.width, size.height);
	/* **AND THE VIEW THAT FILLS IT, MADE BEFORE THE WINDOW IS SHOWN** so that the first display has something to
	 * draw: a window whose content is set after it is on the screen has been on the screen empty. */
	_menuView = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, _trackingFrame.size.width,
								 _trackingFrame.size.height)];
	[(NSMenuView *)_menuView setMenu:self];
	_trackingWindow = [[NSWindow alloc] initWithContentRect:_trackingFrame
						      styleMask:NSBorderlessWindowMask
							backing:NSBackingStoreBuffered
							  defer:NO];
	if (_trackingWindow == nil) {
		/* **A SESSION WITH NO WINDOW IS NOTED RATHER THAN REFUSED, AND THE DIFFERENCE MATTERS.** A host with no
		 * reachable display cannot show a menu, but the session's own state — its frame, its rows, its highlight,
		 * its picks and its dismissal — is exactly the same either way, SO TRACKING GOES AHEAD AND THE MENU IS
		 * SIMPLY NOT PAINTED. Refusing here would make every one of those behaviours untestable off the guest, and
		 * a caller that genuinely needs a window can ask whether it got one. */
		fprintf(stderr, "APPKIT-NOTE: no reachable display — this menu is tracking WITHOUT a window, so it is "
				"invisible but its state is real\n");
	}
	DIAG("  DIAG open: the tracking WINDOW (with its socket and buffer) took %.1f ms\n",
	     ([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
	[_trackingWindow setContentView:_menuView];
	[_trackingWindow orderFrontRegardless];
	_tracking = YES;
	_openedByPress = YES;
	/* AND THE MENU UPDATES ITSELF FIRST, so that what it shows is what its targets can actually answer — this is
	 * `-update` getting its caller, one unit after it was given its reader. */
	[self update];
	[self cg_repaintSession];
	DIAG("  DIAG open: the first repaint took %.1f ms — the menu is on screen now\n",
	     ([NSDate timeIntervalSinceReferenceDate] - t0) * 1000.0);
	[[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidBeginTrackingNotification object:self];
	/* **AND INSIDE A RUNNING APPLICATION IT TRACKS UNTIL IT IS DISMISSED, WHICH IS WHAT A MENU DOES.** This tier
	 * HAS a run loop — `NSApplication`'s `-run`, which the first version of this class's plan note claimed it had
	 * not — so a popup can behave the way Apple's does, and the loop is a few lines because `-cg_trackOneEvent:` is
	 * the loop's BODY and its only copy.
	 *
	 * **AND A MENU THAT IS SOMEBODY'S SUBMENU NEVER BLOCKS, WHICH IS NOT A DETAIL**: its parent is already running
	 * a loop that drives the pointer over BOTH windows, so a child that blocked would be a loop inside a loop. The
	 * question therefore has two halves — `-isRunning` for the application, `-supermenu` for the child — AND BOTH
	 * ARE ASKED RATHER THAN ASSUMED, so a popup from a script, a probe or a host with no loop returns at once and
	 * lets its caller step the session itself. */
	/* **A MENU TRACKS UNLESS IT WAS OPENED FROM INSIDE A SESSION THAT IS ALREADY RUNNING.** The old test was
	 * `_supermenu == nil`, and it was wrong in the one case that matters most: AN ITEM IN THE MENU BAR'S MENU HAS A
	 * SUPERMENU — the bar itself — so a menu opened by CLICKING A TITLE never tracked at all. Nothing dismissed it,
	 * the title's highlight was taken down the instant the call returned, and every click after it was refused with
	 * "cannot begin a session while one is already up" — WHICH IS EXACTLY "SLOW, NO HIGHLIGHT, NEVER CLOSES".
	 *
	 * The question is not whether this menu HAS a parent but WHETHER ITS PARENT IS TRACKING: a submenu opened by
	 * hovering inside its parent's session is the parent's to drive, and one opened from a bar — where the parent is
	 * just sitting there — is the root of a session and drives itself. Reading the parent's own `_tracking` is the
	 * idiom this file already uses two screens up, where the child's window is read straight off the child because
	 * these fields are protected. */
	/* **AND A CALLER THAT ASKED TO DRIVE GETS THE SESSION AND NO LOOP.** It has the window, the view, the first
	 * paint and the notification — everything a beginning is — and it will hand events back through
	 * `-cg_trackOneEvent:` until it calls `-cancelTracking`. */
	if (_callerDrives) {
		_callerDrives = NO;
		return;
	}
	if ((_supermenu == nil || !((NSMenu *)_supermenu)->_tracking) &&
	    [[NSApplication sharedApplication] isRunning]) {
		NSApplication *app = [NSApplication sharedApplication];

		if (getenv("APPKIT_MENU_DIAG") != NULL) {
			fprintf(stderr, "  DIAG menu: tracking \"%s\" (%ld item(s))\n",
				[[self title] UTF8String] ?: "?", (long)[_items count]);
		}
		for (;;) {
			/* ONE POOL PER PASS, the discipline the application's own loop keeps: a menu that ran for the life of
			 * a gesture and never drained its own autoreleased objects would grow while the hand is still moving. */
			id pool = [[NSClassFromString(@"NSAutoreleasePool") alloc] init];
			NSEvent *next = [app nextEventMatchingMask:NSAnyEventMask
							 untilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]
							    inMode:nil
							   dequeue:YES];
			BOOL more;

			/* **AND THE WINDOWS ARE PAINTED, WHICH IS WHAT A TRACKING LOOP OWES THEM.** This loop BLOCKS the
			 * application's own run loop for as long as a menu is up — and the update pass that paints stale
			 * windows lives in that loop, not in `-nextEventMatchingMask:`. So without this line NOTHING IS DRAWN
			 * WHILE A MENU IS OPEN: not the menu itself if the compositor happened to hold its buffer at the one
			 * moment it asked, and not the bar's highlighted title, which the click set a flag for and nothing ever
			 * painted. A tracking loop that stops the world is not what a menu does on the Mac — there the loop
			 * keeps updating, which is why a menu bar can repaint its title while the menu is down. */
			[app updateWindows];
			more = [self cg_trackOneEvent:next];

			if (getenv("APPKIT_MENU_DIAG") != NULL) {
				fprintf(stderr, "  DIAG menu: event type %ld -> %s\n", (long)(next != nil ? [next type] : -1),
					more ? "still up" : "ended");
			}

			[pool release];
			if (!more) {
				break;
			}
		}
	}
}

- (BOOL)cg_takeDismissedAt:(NSPoint *)where
{
	if (!_hasDismissedAt) {
		return NO;
	}
	if (where != NULL) {
		*where = _dismissedAt;
	}
	_hasDismissedAt = NO;
	return YES;
}

- (void)cg_beginSessionAt:(NSPoint)location
{
	_callerDrives = YES;
	[self popUpMenuPositioningItem:nil atLocation:location inView:nil];
	/* the call above returns as soon as the session is up: `_callerDrives` is what tells it to */
}

- (BOOL)cg_ownsEvent:(id)event
{
	if (event == nil || ![event respondsToSelector:@selector(window)]) {
		return NO;
	}
	if (_trackingWindow != nil && [event window] == _trackingWindow) {
		return YES;
	}
	if (_openSubmenu != nil) {
		return [(NSMenu *)_openSubmenu cg_ownsEvent:event];
	}
	return NO;
}

- (void)cancelTracking
{
	/* CANCELLING WITH NO SESSION IS A NO-OP AND NOT A REFUSAL: there is nothing to decline. */
	if (!_tracking) {
		return;
	}
	/* AND A SUBMENU GOES WITH ITS PARENT, which is the rule the other way round from the pick: a session that ends
	 * ends everything it opened. */
	[self cg_closeSubmenu];
	DIAG("  DIAG close: the session ended\n");
	_tracking = NO;
	/* NOT RELEASED — the items belong to this menu, and the highlight is a POINTER to one of them rather than a
	 * thing of its own. */
	_highlightedItem = nil;
	[_trackingWindow orderOut:nil];
	[_trackingWindow release];
	_trackingWindow = nil;
	[[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidEndTrackingNotification object:self];
}

- (void)cancelTrackingWithoutAnimation
{
	/* THE SAME SESSION, AND THE WHOLE DIFFERENCE IS THE ANIMATION THIS TIER HAS NOT GOT: a menu that closed with a
	 * fade would take a different path here; one that closes at once is this door, which is why it forwards rather
	 * than duplicating. */
	[self cancelTracking];
}

+ (void)popUpContextMenu:(NSMenu *)menu withEvent:(id)event forView:(id)view
{
	NSPoint where = NSMakePoint(0.0, 0.0);

	/* THE CLASS DOOR IS THE INSTANCE ONE PLUS A PLACE, which is exactly how Apple describes it: a context menu is
	 * positioned at the event and nothing else distinguishes it. A NIL EVENT HAS NO PLACE, so it is refused here
	 * rather than guessed at. */
	if (event == nil) {
		fprintf(stderr, "APPKIT-REFUSE: +popUpContextMenu:withEvent:forView: needs an EVENT to position the "
				"menu at — a context menu with no place to open is not a context menu\n");
		return;
	}
	where = [event locationInWindow];
	[menu popUpMenuPositioningItem:nil atLocation:where inView:view];
}

- (BOOL)isAttached
{
	/* NO, AND IT IS THE TRUE ANSWER rather than a refusal dance: a menu can be POPPED UP here now, but nothing
	 * can be PINNED to a screen edge, because that is the desktop's bar and not this class's. */
	return NO;
}

- (id)attachedMenu
{
	fprintf(stderr, "APPKIT-REFUSE: -attachedMenu needs the ATTACHED-MENU SUBSTRATE (a menu pinned to a screen "
			"edge, kept open and repositioned by the tracking loop)\n");
	return nil;
}

- (NSPoint)locationForSubmenu:(id)aSubmenu
{
	NSInteger index;
	NSRect row;

	/* **WHERE A SUBMENU OPENS, WHICH IS REAL GEOMETRY RATHER THAN A REFUSAL NOW**: BESIDE THE ROW THAT HOLDS IT, at
	 * that row's TOP-RIGHT corner — what "beside" means in a menu and where Apple puts one. THE ROW IS FOUND
	 * THROUGH THE SAME ARITHMETIC THE HIT-TESTING AND THE PAINT USE, from the frame the session is tracking in, so
	 * all three agree BY CONSTRUCTION rather than by being checked against each other — which is the property that
	 * matters, since a submenu that opens beside a row the menu does not draw is the same class of bug as a
	 * highlight on a row that is not there. */
	if (!_tracking) {
		fprintf(stderr, "APPKIT-REFUSE: -locationForSubmenu: needs A MENU THAT IS UP — where a submenu goes is a "
				"question about a menu being tracked, and no session is running\n");
		return NSMakePoint(0.0, 0.0);
	}
	index = (aSubmenu != nil) ? [self indexOfItemWithSubmenu:aSubmenu] : NSNotFound;
	if (index == NSNotFound) {
		/* A SUBMENU THIS MENU DOES NOT HOLD has no row to open beside, so the frame's own top-right is the honest
		 * answer: it is where a menu with no such row would put one. */
		return NSMakePoint(NSMaxX(_trackingFrame), NSMaxY(_trackingFrame));
	}
	row = NSMakeRect(_trackingFrame.origin.x,
			 _trackingFrame.origin.y + (CGFloat)([_items count] - 1 - index) * NSMenuRowHeight,
			 _trackingFrame.size.width, NSMenuRowHeight);
	return NSMakePoint(NSMaxX(row), NSMaxY(row));
}

- (void)helpRequested:(id)event
{
	(void)event;
	fprintf(stderr, "APPKIT-REFUSE: -helpRequested: needs the HELP SUBSTRATE (the Help menu, its context "
			"tracking and the tooltip machinery), which this tier has not got\n");
}

- (void)submenuAction:(id)sender
{
	/* **APPLE'S ACTION FOR AN ITEM THAT HAS A SUBMENU, AND THIS TIER CAN ANSWER IT NOW** — which is why the
	 * refusal that stood here is gone rather than reworded: it named SUBMENU TRACKING as the missing thing, and
	 * that is exactly what the session now has. THE SENDER IS THE ITEM and opening ITS submenu beside itself is
	 * the whole of the door. The tracking step opens a child directly (this tier's holders carry no action), so
	 * what makes this REAL rather than dead is that a CALLER can drive the same opening — and it goes through the
	 * same two doors the step does, `-locationForSubmenu:` for the place and `-popUpMenuPositioningItem:…` for the
	 * session, so there is one implementation of "open a submenu" reached from two directions. */
	NSMenuItem *item = (sender != nil) ? (NSMenuItem *)sender : (NSMenuItem *)_highlightedItem;

	if (!_tracking || item == nil || [item submenu] == nil) {
		/* NOTHING TO OPEN IS NOT A REFUSAL: Apple's door is an ACTION, and an action with nothing to act on does
		 * nothing — which is the difference between a door a caller drove wrongly and a door that cannot work. */
		return;
	}
	[self cg_closeSubmenu];
	_openSubmenu = [item submenu];
	[_openSubmenu popUpMenuPositioningItem:nil
				    atLocation:[self locationForSubmenu:_openSubmenu]
				       inView:nil];
}

+ (BOOL)menuBarVisible
{
	/* NO, AND IT IS TRUE: THE BAR BELONGS TO THE DESKTOP and the desktop draws its own chrome (the plan's D6 —
	 * the guest's window manager paints none), so there is no bar here to be visible. */
	return NO;
}

+ (void)setMenuBarVisible:(BOOL)visible
{
	(void)visible;
	fprintf(stderr, "APPKIT-REFUSE: +setMenuBarVisible: needs A MENU BAR TO SHOW — the bar is the desktop's "
			"(D6), and this tier has no desktop-side bar service to ask\n");
}

+ (void *)menuZone
{
	fprintf(stderr, "APPKIT-REFUSE: +menuZone needs ZONE-BASED ALLOCATION, and this tier allocates through the "
			"runtime's default zone: a zone answer here would name a zone nothing is allocated from\n");
	return NULL;
}

+ (void)setMenuZone:(void *)zone
{
	(void)zone;
	fprintf(stderr, "APPKIT-REFUSE: +setMenuZone: needs ZONE-BASED ALLOCATION — the same ground +menuZone "
			"refuses on\n");
}

- (id)menuRepresentation
{
	fprintf(stderr, "APPKIT-REFUSE: -menuRepresentation needs the REPRESENTATION CLASSES (NSMenuView and its "
			"siblings), which are the drawing half of this class and are not in this tree\n");
	return nil;
}

- (void)setMenuRepresentation:(id)menuRepresentation
{
	(void)menuRepresentation;
	fprintf(stderr, "APPKIT-REFUSE: -setMenuRepresentation: needs the REPRESENTATION CLASSES — the same ground "
			"-menuRepresentation refuses on\n");
}

- (id)contextMenuRepresentation
{
	fprintf(stderr, "APPKIT-REFUSE: -contextMenuRepresentation needs the REPRESENTATION CLASSES, the same ground "
			"-menuRepresentation refuses on\n");
	return nil;
}

- (void)setContextMenuRepresentation:(id)contextMenuRepresentation
{
	(void)contextMenuRepresentation;
	fprintf(stderr, "APPKIT-REFUSE: -setContextMenuRepresentation: needs the REPRESENTATION CLASSES — the same "
			"ground -menuRepresentation refuses on\n");
}

- (id)tearOffMenuRepresentation
{
	fprintf(stderr, "APPKIT-REFUSE: -tearOffMenuRepresentation needs the REPRESENTATION CLASSES together with the "
			"TEAR-OFF SUBSTRATE — the same ground -menuRepresentation refuses on\n");
	return nil;
}

- (void)setTearOffMenuRepresentation:(id)tearOffMenuRepresentation
{
	(void)tearOffMenuRepresentation;
	fprintf(stderr, "APPKIT-REFUSE: -setTearOffMenuRepresentation: needs the REPRESENTATION CLASSES — the same "
			"ground -menuRepresentation refuses on\n");
}

/* ---- AND THE ONE DOOR OF THE TRACKING HALF THIS CLASS CAN ANSWER -------------------------------- */

/* THE FOUR MODIFIER MASKS ARE THAT HEADER'S, and this file imports it HERE rather than at the top because this
 * door is the only thing in the file that needs it: a mid-file import is legal, it sits with the only code that
 * uses it, and the alternative — pulling this file's import block into a diff that changes no behaviour — would be
 * a change nobody asked for. (This is the other half of the same decision the header states: its event parameter
 * is typed `id` so that the header need not import anything at all.) */
#import <AppKit/NSEvent.h>

/* THE SPEC DECODER, AND IT IS THE PLACE A SPEC BECOMES FOUR BITS AND A KEY. Apple's letters are `@` for command,
 * `^` for control, `~` for option and `$` for shift, and they come BEFORE the key: `@~f` is command-option-f. A spec
 * with no modifier letter has no modifiers, which is the honest reading of a bare character rather than a special
 * case — and the loop stops at the first letter that is not one, so the key may itself begin with a character this
 * decoder knows. */
- (BOOL)cg_matchesUserSpec:(NSString *)spec characters:(NSString *)characters flags:(NSUInteger)flags
{
	NSUInteger mask = 0;
	NSUInteger i = 0;

	for (i = 0; i < [spec length]; i++) {
		unichar c = [spec characterAtIndex:i];

		if (c == '@') {
			mask |= NSCommandKeyMask;
		} else if (c == '^') {
			mask |= NSControlKeyMask;
		} else if (c == '~') {
			mask |= NSAlternateKeyMask;
		} else if (c == '$') {
			mask |= NSShiftKeyMask;
		} else {
			break;
		}
	}
	return [[spec substringFromIndex:i] isEqualToString:characters] && mask == flags;
}

- (BOOL)performKeyEquivalent:(id)event
{
	NSString *characters;
	NSUInteger wanted;
	NSInteger i;

	/* THE GUARD COMES FIRST AND IS NOT A FORMALITY: this project's runtime RAISES on a selector an object does not
	 * implement, so a door that messaged its argument blind would ABORT rather than answer — which is exactly how
	 * the first version of `-performActionForItemAtIndex:` presented its mistake. */
	if (event == nil || ![event respondsToSelector:@selector(charactersIgnoringModifiers)] ||
	    ![event respondsToSelector:@selector(modifierFlags)]) {
		fprintf(stderr, "APPKIT-REFUSE: -performKeyEquivalent: needs an EVENT — an object answering "
				"-charactersIgnoringModifiers and -modifierFlags — and this argument answers neither\n");
		return NO;
	}
	characters = [(NSEvent *)event charactersIgnoringModifiers];
	if (characters == nil || [characters length] == 0) {
		return NO;
	}
	/* THE FOUR BITS A KEY EQUIVALENT IS MADE OF, AND THE REST OF THE EVENT'S FLAGS ARE MASKED OFF RATHER THAN
	 * COMPARED: an event carries device-dependent bits (its own header documents them), and comparing the whole
	 * mask would make the same keystroke fail on a different keyboard. */
	wanted = [(NSEvent *)event modifierFlags] &
		 (NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask | NSCommandKeyMask);
	for (i = 0; i < (NSInteger)[_items count]; i++) {
		NSMenuItem *item = [_items objectAtIndex:(NSUInteger)i];

		/* A SUBMENU IS ASKED TOO, and that is what lets ONE menu answer for a whole tree: a key equivalent belongs
		 * to the menu its item is in, and a menu bar's door is handed the keystrokes for every menu below it. */
		if ([item submenu] != nil && [[item submenu] performKeyEquivalent:event]) {
			return YES;
		}
		/* AND THE THREE THINGS THAT STOP AN ITEM ANSWERING: it is hidden, it is a separator (which has no action by
		 * construction), or it is disabled. Apple disables an item's key equivalent along with the item, so a menu
		 * that ignored the flag would send commands its own rows decline to offer. */
		if ([item isHidden] || [item isSeparatorItem] || ![item isEnabled]) {
			continue;
		}
		/* **AND THE ITEM'S OWN KEY EQUIVALENT IS NOT THE ONLY ONE IT MAY ANSWER.** When menu items consult the
		 * user's overrides (`+[NSMenuItem usesUserKeyEquivalents]`), the SPEC the user assigned is matched instead —
		 * and a spec carries its OWN modifiers, so it is DECODED here rather than compared as a character. This is
		 * the difference between ANSWERING an override and USING it, which is why the check that pins it uses an
		 * item whose own key equivalent could not match the event at all: its own is a bare `o` with no mask, and
		 * the event is command-o. */
		if ([NSMenuItem usesUserKeyEquivalents]) {
			NSString *spec = [item userKeyEquivalent];

			if (spec != nil && [self cg_matchesUserSpec:spec characters:characters flags:wanted]) {
				[self performActionForItemAtIndex:i];
				return YES;
			}
		}
		if ([[item keyEquivalent] isEqualToString:characters] &&
		    ([item keyEquivalentModifierMask] & (NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask |
							 NSCommandKeyMask)) == wanted) {
			[self performActionForItemAtIndex:i];
			return YES;
		}
	}
	return NO;
}

/* ---- AND THE DECODER DOOR ---------------------------------------------------------------------- */

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
	(void)coder;
	/* SAME GROUND AS NSMenuItem's: Apple's key set for an archived menu is not published, and a guessed one is
	 * a WRONG MENU rather than an unfinished door — a menu is a tree, so a guess is wrong in every row at once. */
	fprintf(stderr, "APPKIT-REFUSE: -initWithCoder: needs Apple's published key set for an archived menu, and "
			"this duplication has not got one. Build the menu in code instead\n");
	return nil;
}

@end
