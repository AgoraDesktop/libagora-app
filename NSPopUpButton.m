/*
 * NSPopUpButton — a button whose press raises a menu.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * EVERY DOOR HERE IS A FORWARD except two, and the two are the same act: `-mouseDown:` and `-performClick:` both hand
 * the cell this button's bounds and this button, which is everything the cell needs to put a menu under it. That is
 * the whole of what the view contributes — a cell can decide and draw, but only a view has a coordinate space and a
 * window in it.
 */
#import <AppKit/NSPopUpButton.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSView.h>

@implementation NSPopUpButton

/* ============================================================================================
 * ARCHIVING: NOTHING OF ITS OWN: ITS PULL-DOWN FLAG AND SELECTION ARE ITS CELL'S.
 * ============================================================================================ */
/* Its pull-down flag and selection are its CELL's. A class with no instance storage can inherit both coding methods — `class_getInstanceSize` is what
 * says so, and `NSNib`'s census accepts exactly that case. The conformance is declared so the allow-list's
 * `-conformsToProtocol:` question answers YES. */
+ (BOOL)supportsSecureCoding
{
	return YES;
}


- (instancetype)initWithFrame:(NSRect)frameRect pullsDown:(BOOL)pullDown
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		/* **THE CELL IS REPLACED, WHICH IS THE ONE THING THIS INITIALISER IS FOR.** `NSButton`'s own `-initWithFrame:`
		 * has already made a plain button cell and sized the frame for it; a pop-up wants ITS cell — the one that knows
		 * what a menu is — and the sizing follows the cell, so it is done again below rather than trusted from the
		 * superclass's pass. THE BEZEL IS THE SAME ONE A PUSH BUTTON WEARS, because a popup IS a push button: Apple's
		 * own control is a rounded bezel with a title and an arrow, and that is what this draws. */
		NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:pullDown];

		[cell setBordered:YES];
		[cell setBezeled:YES];
		[self setCell:cell];
		[cell release];
		if (frameRect.size.width <= 0.0 || frameRect.size.height <= 0.0) {
			[self sizeToFit];
		}
	}
	return self;
}

/* ---- THE MENU AND ITS SHAPE ----------------------------------------------------------------------- */

- (id)menu
{
	return [(NSPopUpButtonCell *)[self cell] menu];
}

- (void)setMenu:(id)aMenu
{
	[(NSPopUpButtonCell *)[self cell] setMenu:aMenu];
	[self setNeedsDisplay:YES];
}

- (BOOL)pullsDown
{
	return [(NSPopUpButtonCell *)[self cell] pullsDown];
}

- (void)setPullsDown:(BOOL)flag
{
	[(NSPopUpButtonCell *)[self cell] setPullsDown:flag];
	[self setNeedsDisplay:YES];
}

- (NSRectEdge)preferredEdge
{
	return [(NSPopUpButtonCell *)[self cell] preferredEdge];
}

- (void)setPreferredEdge:(NSRectEdge)edge
{
	[(NSPopUpButtonCell *)[self cell] setPreferredEdge:edge];
}

- (NSPopUpArrowPosition)arrowPosition
{
	return [(NSPopUpButtonCell *)[self cell] arrowPosition];
}

- (void)setArrowPosition:(NSPopUpArrowPosition)position
{
	[(NSPopUpButtonCell *)[self cell] setArrowPosition:position];
	[self setNeedsDisplay:YES];
}

/* ---- WHAT IS IN THE MENU -------------------------------------------------------------------------- */

- (void)addItemWithTitle:(NSString *)title
{
	[(NSPopUpButtonCell *)[self cell] addItemWithTitle:title];
	[self setNeedsDisplay:YES];
}

- (void)removeItemAtIndex:(NSInteger)index
{
	[(NSPopUpButtonCell *)[self cell] removeItemAtIndex:index];
	[self setNeedsDisplay:YES];
}

- (void)removeAllItems
{
	[(NSPopUpButtonCell *)[self cell] removeAllItems];
	[self setNeedsDisplay:YES];
}

- (NSInteger)numberOfItems
{
	return [(NSPopUpButtonCell *)[self cell] numberOfItems];
}

- (id)itemAtIndex:(NSInteger)index
{
	return [(NSPopUpButtonCell *)[self cell] itemAtIndex:index];
}

- (NSArray *)itemArray
{
	return [(NSPopUpButtonCell *)[self cell] itemArray];
}

- (id)lastItem
{
	return [(NSPopUpButtonCell *)[self cell] lastItem];
}

- (NSString *)itemTitleAtIndex:(NSInteger)index
{
	return [(NSPopUpButtonCell *)[self cell] itemTitleAtIndex:index];
}

- (NSInteger)indexOfItem:(id)item
{
	return [(NSPopUpButtonCell *)[self cell] indexOfItem:item];
}

- (NSInteger)indexOfItemWithTitle:(NSString *)title
{
	return [(NSPopUpButtonCell *)[self cell] indexOfItemWithTitle:title];
}

- (NSInteger)indexOfItemWithTag:(NSInteger)tag
{
	return [(NSPopUpButtonCell *)[self cell] indexOfItemWithTag:tag];
}

- (id)itemWithTitle:(NSString *)title
{
	return [(NSPopUpButtonCell *)[self cell] itemWithTitle:title];
}

- (id)itemWithTag:(NSInteger)tag
{
	return [(NSPopUpButtonCell *)[self cell] itemWithTag:tag];
}

- (void)addItemsWithTitles:(NSArray *)itemTitles
{
	[(NSPopUpButtonCell *)[self cell] addItemsWithTitles:itemTitles];
}

- (void)insertItemWithTitle:(NSString *)title atIndex:(NSInteger)index
{
	[(NSPopUpButtonCell *)[self cell] insertItemWithTitle:title atIndex:index];
}

- (void)removeItemWithTitle:(NSString *)title
{
	[(NSPopUpButtonCell *)[self cell] removeItemWithTitle:title];
}

- (NSArray *)itemTitles
{
	return [(NSPopUpButtonCell *)[self cell] itemTitles];
}

- (NSInteger)indexOfItemWithRepresentedObject:(id)object
{
	return [(NSPopUpButtonCell *)[self cell] indexOfItemWithRepresentedObject:object];
}

- (NSInteger)indexOfItemWithTarget:(id)target andAction:(SEL)actionSelector
{
	return [(NSPopUpButtonCell *)[self cell] indexOfItemWithTarget:target andAction:actionSelector];
}

- (void)selectItem:(id)item
{
	[(NSPopUpButtonCell *)[self cell] selectItem:item];
}

- (BOOL)autoenablesItems
{
	return [(NSPopUpButtonCell *)[self cell] autoenablesItems];
}

- (void)setAutoenablesItems:(BOOL)flag
{
	[(NSPopUpButtonCell *)[self cell] setAutoenablesItems:flag];
}

/* ---- WHAT IS CHOSEN ------------------------------------------------------------------------------- */

- (id)selectedItem
{
	return [(NSPopUpButtonCell *)[self cell] selectedItem];
}

- (void)setSelectedItem:(id)item
{
	[(NSPopUpButtonCell *)[self cell] setSelectedItem:item];
	[self setNeedsDisplay:YES];
}

- (NSInteger)indexOfSelectedItem
{
	return [(NSPopUpButtonCell *)[self cell] indexOfSelectedItem];
}

- (void)selectItemAtIndex:(NSInteger)index
{
	[(NSPopUpButtonCell *)[self cell] selectItemAtIndex:index];
	[self setNeedsDisplay:YES];
}

- (void)selectItemWithTitle:(NSString *)title
{
	[(NSPopUpButtonCell *)[self cell] selectItemWithTitle:title];
	[self setNeedsDisplay:YES];
}

- (void)selectItemWithTag:(NSInteger)tag
{
	[(NSPopUpButtonCell *)[self cell] selectItemWithTag:tag];
	[self setNeedsDisplay:YES];
}

- (NSString *)titleOfSelectedItem
{
	return [(NSPopUpButtonCell *)[self cell] titleOfSelectedItem];
}

- (void)synchronizeTitleAndSelectedItem
{
	[(NSPopUpButtonCell *)[self cell] synchronizeTitleAndSelectedItem];
	[self setNeedsDisplay:YES];
}

/* **AND THE TITLE, WHICH IS THE CELL'S — INCLUDING THE PULL-DOWN'S ONE WRINKLE.** `NSPopUpButtonCell`'s
 * `-setTitle:` moves the menu's first row when the button is a pull-down, because on a pull-down that row IS the
 * title. Forwarding rather than re-deriving is what keeps one copy of that rule. */
- (NSString *)title
{
	return [[self cell] title];
}

- (void)setTitle:(NSString *)aTitle
{
	[(NSPopUpButtonCell *)[self cell] setTitle:aTitle];
	[self setNeedsDisplay:YES];
}

/* ---- THE PRESS ------------------------------------------------------------------------------------ */

/* **THE PRESS IS THE VIEW'S ONE CONTRIBUTION.** The cell knows what to do — begin the session, take the pick, put the
 * highlight up and down — and what it cannot know is WHERE, because a cell has no space of its own. So this hands it
 * the bounds and the view and nothing else, which is exactly Apple's `-attachPopUpWithFrame:inView:` split.
 *
 * **AND IT DOES NOT CALL `-super`.** `NSControl`'s tracking loop highlights the cell, follows the pointer and sends
 * the action on the RELEASE — which is a push button's gesture. A popup's gesture is a press that raises a menu and a
 * session that ends wherever the hand says, so running both would open the menu from inside a tracking loop that is
 * still waiting for a release it will never see as its own. */
- (void)mouseDown:(NSEvent *)event
{
	(void)event;
	[(NSPopUpButtonCell *)[self cell] attachPopUpWithFrame:[self bounds] inView:self];
}

/* **AND `-performClick:` RAISES THE MENU, WHICH IS WHAT MAKES THIS DOOR USEFUL RATHER THAN MISLEADING.** Apple's
 * `NSControl -performClick:` sends the action, and for a push button that is what a click means — but a POPUP has no
 * action of its own until something is CHOSEN, so sending it here would fire a caller's handler with no selection and
 * no menu ever shown. `NSButton`'s own version highlights and performs; this one opens the menu, which is the act a
 * person means by clicking a popup. */
- (void)performClick:(id)sender
{
	(void)sender;
	[(NSPopUpButtonCell *)[self cell] attachPopUpWithFrame:[self bounds] inView:self];
}

@end
