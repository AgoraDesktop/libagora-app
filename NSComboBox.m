/*
 * NSComboBox.m — the control, which is one initialiser and a wall of forwards.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE INITIALISER IS THE ONLY DOOR WITH A DECISION IN IT, AND THE DECISION IS THE CELL.** `NSControl`'s
 * `-initWithFrame:` makes a plain cell and sizes the frame for it; this control wants the one that knows what a chip
 * is, so the cell is REPLACED and the sizing is done again rather than trusted from the superclass's pass — which is
 * exactly what `NSPopUpButton -initWithFrame:pullsDown:` does, and for the same reason: a field drawn by a plain cell
 * has no chip, and a frame measured before the chip existed is too narrow for the control it is holding.
 *
 * EVERY OTHER DOOR FORWARDS. That is not a placeholder for behaviour that is coming; it is what a control IS in this
 * tier — the cell decides and draws, and the control is the thing with a frame for the drawing to happen in.
 */
#import <AppKit/NSComboBox.h>
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSText.h>
#import <AppKit/NSEvent.h>

@implementation NSComboBox

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSComboBoxCell *cell = [[NSComboBoxCell alloc] initTextCell:@""];

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

/* **THE PRESS IS THE CONTROL'S ONE PIECE OF BEHAVIOUR, AND IT OPENS AN EDIT.** A cell can set an editor up but it has
 * no window to find one in and no view to put it in — those are the two things a view contributes — so the press is
 * where the control hands the cell what it cannot get itself. THE EDITOR IS THE WINDOW'S: one per window, lent to
 * whichever field is being typed into, which is what `NSWindow -fieldEditor:forObject:` is for and why this is three
 * lines rather than a text view of the control's own.
 *
 * AND IT DOES NOT CALL `-super`. `NSControl`'s tracking loop highlights the cell, follows the pointer and sends the
 * action on the release — which is a push button's gesture. A field's gesture is a session that outlives the press, so
 * running both would start an edit from inside a loop still waiting for a release it will never own. */
- (void)mouseDown:(NSEvent *)event
{
	NSComboBoxCell *cell = (NSComboBoxCell *)[self cell];
	NSText *editor = (NSText *)[[self window] fieldEditor:YES forObject:self];

	if (editor == nil) {
		return;
	}
	[cell editWithFrame:[self bounds] inView:self editor:editor delegate:nil event:event];
	[self setNeedsDisplay:YES];
}

/* ---- THE LIST ------------------------------------------------------------------------------------- */

- (NSInteger)numberOfItems
{
	return [(NSComboBoxCell *)[self cell] numberOfItems];
}

- (void)addItemWithObjectValue:(id)object
{
	[(NSComboBoxCell *)[self cell] addItemWithObjectValue:object];
	[self setNeedsDisplay:YES];
}

- (void)addItemsWithObjectValues:(NSArray *)objects
{
	[(NSComboBoxCell *)[self cell] addItemsWithObjectValues:objects];
	[self setNeedsDisplay:YES];
}

- (void)insertItemWithObjectValue:(id)object atIndex:(NSInteger)index
{
	[(NSComboBoxCell *)[self cell] insertItemWithObjectValue:object atIndex:index];
	[self setNeedsDisplay:YES];
}

- (void)removeAllItems
{
	[(NSComboBoxCell *)[self cell] removeAllItems];
	[self setNeedsDisplay:YES];
}

- (void)removeItemAtIndex:(NSInteger)index
{
	[(NSComboBoxCell *)[self cell] removeItemAtIndex:index];
	[self setNeedsDisplay:YES];
}

- (void)removeItemWithObjectValue:(id)object
{
	[(NSComboBoxCell *)[self cell] removeItemWithObjectValue:object];
	[self setNeedsDisplay:YES];
}

- (id)itemObjectValueAtIndex:(NSInteger)index
{
	return [(NSComboBoxCell *)[self cell] itemObjectValueAtIndex:index];
}

- (NSArray *)objectValues
{
	return [(NSComboBoxCell *)[self cell] objectValues];
}

- (NSInteger)indexOfItemWithObjectValue:(id)object
{
	return [(NSComboBoxCell *)[self cell] indexOfItemWithObjectValue:object];
}

/* ---- WHAT IS CHOSEN ------------------------------------------------------------------------------- */

- (NSInteger)indexOfSelectedItem
{
	return [(NSComboBoxCell *)[self cell] indexOfSelectedItem];
}

- (void)selectItemAtIndex:(NSInteger)index
{
	[(NSComboBoxCell *)[self cell] selectItemAtIndex:index];
	[self setNeedsDisplay:YES];
}

- (void)selectItemWithObjectValue:(id)object
{
	[(NSComboBoxCell *)[self cell] selectItemWithObjectValue:object];
	[self setNeedsDisplay:YES];
}

- (id)objectValueOfSelectedItem
{
	return [(NSComboBoxCell *)[self cell] objectValueOfSelectedItem];
}

/* **AND THE BOX'S "TITLE" IS ITS STRING, WHICH IS THE SAME DOOR UNDER THE NAME A CALLER EXPECTS.** Apple gives
 * `NSComboBox` a `-stringValue` because that is what a field has; this tier's header names `-title` as well because the
 * gallery and the tests speak of a control's title, and both end at the cell's own text so there is one value rather
 * than two. */
- (NSString *)title
{
	return [[self cell] stringValue];
}

- (void)setTitle:(NSString *)aTitle
{
	[(NSComboBoxCell *)[self cell] setStringValue:aTitle];
	[self setNeedsDisplay:YES];
}

/* ---- THE TWO SHAPE FLAGS -------------------------------------------------------------------------- */

- (NSInteger)numberOfVisibleItems
{
	return [(NSComboBoxCell *)[self cell] numberOfVisibleItems];
}

- (void)setNumberOfVisibleItems:(NSInteger)count
{
	[(NSComboBoxCell *)[self cell] setNumberOfVisibleItems:count];
}

- (BOOL)completes
{
	return [(NSComboBoxCell *)[self cell] completes];
}

- (void)setCompletes:(BOOL)flag
{
	[(NSComboBoxCell *)[self cell] setCompletes:flag];
}

- (BOOL)usesDataSource
{
	return [(NSComboBoxCell *)[self cell] usesDataSource];
}

- (void)setUsesDataSource:(BOOL)flag
{
	[(NSComboBoxCell *)[self cell] setUsesDataSource:flag];
}

- (BOOL)isEditable
{
	return [(NSComboBoxCell *)[self cell] isEditable];
}

- (void)setEditable:(BOOL)flag
{
	[(NSComboBoxCell *)[self cell] setEditable:flag];
}

@end
