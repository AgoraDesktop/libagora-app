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
#import <AppKit/NSEvent.h>
#import <Foundation/NSNotification.h>

/* **THE VIEW IS THE CELL'S DATA SOURCE, WHICH IS THE ADAPTATION THAT KEEPS APPLE'S TWO PROTOCOLS APART.** A caller hands
 * over an `NSComboBoxDataSource` — the protocol whose methods name the VIEW — and the cell asks its own protocol, whose
 * methods name the CELL. This class conforms to the cell's protocol and translates the three calls, so neither header
 * has to pretend to be the other and a source written for a view is never asked a cell's question. The conformance is
 * declared here rather than in the header because it is an implementation detail of the hand-off. */
@interface NSComboBox () <NSComboBoxCellDataSource>
@end

@implementation NSComboBox

/* ============================================================================================
 * ARCHIVING: ITS ROWS ARE ITS CELL'S, AND ITS ONE IVAR IS NOT A DESIGN PROPERTY.
 * ============================================================================================ */
/* **THIS CLASS NOW HAS STORAGE, SO IT MUST DO ITS OWN CODING** — `NSNib`'s census accepts an inherited method only when
 * `class_getInstanceSize` says there is nothing to lose, and `_dataSource` is something to lose. What it holds is an
 * OBJECT the caller owns and feeds, not a design property: a data source has no coding protocol in this tier and a nib
 * carrying one would carry a live graph, so the pair below encodes and decodes NOTHING and says so. The CELL's coding
 * carries everything that is part of the design — its own rows, the selection, the list's shape. */
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];
	/* NOTHING OF THIS CLASS'S IS WRITTEN: the one ivar is a source, and a source is not a design property. */
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	self = [super initWithCoder:aDecoder];
	if (self == nil) {
		return nil;
	}
	/* THE SOURCE IS NOT ARCHIVED, so a decoded box shows its own rows until a caller sets one. */
	_dataSource = nil;
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}


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

/* **THE PRESS HAS TWO ANSWERS, AND WHICH ONE DEPENDS ON WHERE IT LANDED.** A combo box is two things in one frame: a
 * FIELD the value is typed into and a CHIP that opens the list of values. So a press on the chip opens the list and a
 * press anywhere else begins an edit — MEASURED, before this split, clicking the chip did nothing at all, because the
 * chip's ink was drawn and the list behind it had never been built.
 *
 * THE CHIP'S RECT COMES FROM THE CELL, because only the cell knows where it is: its side is a fraction of the field's
 * height, which is a measurement rather than a constant. The point is carried into the control's own space first —
 * `-convertPoint:fromView:nil` — because an event's location is in the WINDOW's.
 *
 * **AND A PRESS ANYWHERE ELSE IS A PRESS ON A FIELD, WHICH IS A DOOR THIS CLASS NOW INHERITS.** It used to open the
 * session here, in a copy of `NSTextField`'s command written before `NSTextField` existed. The base is that class
 * now, so the field half is `-super` and this method keeps only what a text field cannot do: the CHIP. (Calling
 * `-super` is not calling `NSControl`'s tracking loop any more — `NSTextField -mouseDown:` overrides it — so the
 * button gesture the earlier note warned about is not what is reached.) The one thing the base needs from this class
 * is that the box be EDITABLE, which a combo cell now says of itself. */
- (void)mouseDown:(NSEvent *)event
{
	NSComboBoxCell *cell = (NSComboBoxCell *)[self cell];
	NSRect bounds = [self bounds];
	NSPoint where = [self convertPoint:[event locationInWindow] fromView:nil];

	if (NSPointInRect(where, [cell cg_chipRectInFrame:bounds])) {
		/* **AND THE DELEGATE HEARS THE LIST OPEN AND CLOSE, WHICH IS WHAT THOSE TWO MESSAGES ARE FOR.** They are sent
		 * around the session — the cell's attach door RUNS it, so "after it returns" is "the list is gone" — and each
		 * carries a notification naming this control, which is the object Apple's messages carry. THE NOTIFICATION IS
		 * BUILT AND NOT POSTED: a delegate that also registered for the name would otherwise hear the same news twice,
		 * and this tier has one delegate to tell. */
		[self fn_notifyDelegate:@selector(comboBoxWillPopUp:)];
		[cell cg_attachListWithFrame:bounds inView:self];
		[self fn_notifyDelegate:@selector(comboBoxWillDismiss:)];
		return;
	}
	/* **THE CONTROL IS THE CALLER, WHICH IS HOW A COMMITTED EDIT REACHES A CALLER'S ACTION** — and that is still true
	 * through the base: `NSTextField` passes this control as the cell's caller, exactly as the copy above did. */
	[super mouseDown:event];
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


/* ---- THE DATA SOURCE ----------------------------------------------------------------------------- */

- (void)setDataSource:(id <NSComboBoxDataSource>)aSource
{
	/* **THE VIEW KEEPS THE SOURCE AND THE CELL IS TOLD THIS OBJECT IS ITS OWN.** A nil source clears both, which is how
	 * a caller falls back to the box's own rows; the box keeps `-usesDataSource` as its own switch, so a caller may hold
	 * a source while asking the box to show what it holds (Apple's split, and the cell's header says so). */
	_dataSource = aSource;
	[(NSComboBoxCell *)[self cell] setDataSource:((aSource != nil) ? (id <NSComboBoxCellDataSource>)self : nil)];
	[self setNeedsDisplay:YES];
}

- (id <NSComboBoxDataSource>)dataSource
{
	return (id <NSComboBoxDataSource>)_dataSource;
}

/* THE THREE ADAPTED CALLS. Each asks the view's protocol of the source the CALLER handed over; a required member the
 * source does not implement is treated as an empty list rather than sent a message it cannot answer. */
- (NSInteger)numberOfItemsInComboBoxCell:(NSComboBoxCell *)comboBoxCell
{
	(void)comboBoxCell;
	if (_dataSource == nil || ![(id)_dataSource respondsToSelector:@selector(numberOfItemsInComboBox:)]) {
		return 0;
	}
	return [(id)_dataSource numberOfItemsInComboBox:self];
}

- (id)comboBoxCell:(NSComboBoxCell *)comboBoxCell objectValueForItemAtIndex:(NSInteger)index
{
	(void)comboBoxCell;
	if (_dataSource == nil || ![(id)_dataSource respondsToSelector:@selector(comboBox:objectValueForItemAtIndex:)]) {
		return nil;
	}
	return [(id)_dataSource comboBox:self objectValueForItemAtIndex:index];
}

- (NSUInteger)comboBoxCell:(NSComboBoxCell *)comboBoxCell indexOfItemWithStringValue:(NSString *)string
{
	(void)comboBoxCell;
	if (_dataSource != nil && [(id)_dataSource respondsToSelector:@selector(comboBox:indexOfItemWithStringValue:)]) {
		return [(id)_dataSource comboBox:self indexOfItemWithStringValue:string];
	}
	return NSNotFound;
}

- (NSString *)comboBoxCell:(NSComboBoxCell *)comboBoxCell completedString:(NSString *)uncompletedString
{
	(void)comboBoxCell;
	if (_dataSource != nil && [(id)_dataSource respondsToSelector:@selector(comboBox:completedString:)]) {
		return [(id)_dataSource comboBox:self completedString:uncompletedString];
	}
	return nil;
}

- (void)reloadData
{
	[(NSComboBoxCell *)[self cell] reloadData];
}

- (void)noteNumberOfItemsChanged
{
	[(NSComboBoxCell *)[self cell] noteNumberOfItemsChanged];
}

/* ---- THE DELEGATE'S THREE TIDINGS ---------------------------------------------------------------- */

/* **ONE HELPER, THREE CALLERS, AND THE SAME SHAPE FOR EACH.** The delegate is asked whether it implements the message
 * before it is sent — a delegate is `id` and the four are `@optional` — and the notification names THIS control, because
 * that is the object a caller's handler will look at. */
- (void)fn_notifyDelegate:(SEL)message
{
	id delegate = [self delegate];
	NSNotification *note;

	if (delegate == nil || ![delegate respondsToSelector:message]) {
		return;
	}
	note = [NSNotification notificationWithName:NSStringFromSelector(message) object:self];
	(void)[(id)delegate performSelector:message withObject:note];
}

- (void)cg_didSelectItemAtIndex:(NSInteger)index
{
	(void)index;
	[self fn_notifyDelegate:@selector(comboBoxSelectionDidChange:)];
}

/* AND THE ROW THE POINTER MOVED TO, which is the fourth of the delegate's messages — see the header: this is the seam
 * `-comboBoxSelectionIsChanging:` was declared for. */
- (void)cg_willHighlightItemAtIndex:(NSInteger)index
{
	(void)index;
	[self fn_notifyDelegate:@selector(comboBoxSelectionIsChanging:)];
}

/* ---- THE LIST'S SHAPE, ALL OF IT THE CELL'S ------------------------------------------------------ */

- (CGFloat)itemHeight
{
	return [(NSComboBoxCell *)[self cell] itemHeight];
}

- (void)setItemHeight:(CGFloat)itemHeight
{
	[(NSComboBoxCell *)[self cell] setItemHeight:itemHeight];
}

- (NSSize)intercellSpacing
{
	return [(NSComboBoxCell *)[self cell] intercellSpacing];
}

- (void)setIntercellSpacing:(NSSize)aSize
{
	[(NSComboBoxCell *)[self cell] setIntercellSpacing:aSize];
}

- (BOOL)isButtonBordered
{
	return [(NSComboBoxCell *)[self cell] isButtonBordered];
}

- (void)setButtonBordered:(BOOL)flag
{
	[(NSComboBoxCell *)[self cell] setButtonBordered:flag];
}

- (BOOL)hasVerticalScroller
{
	return [(NSComboBoxCell *)[self cell] hasVerticalScroller];
}

- (void)setHasVerticalScroller:(BOOL)flag
{
	[(NSComboBoxCell *)[self cell] setHasVerticalScroller:flag];
}

- (void)scrollItemAtIndexToTop:(NSInteger)index
{
	[(NSComboBoxCell *)[self cell] scrollItemAtIndexToTop:index];
}

- (void)scrollItemAtIndexToVisible:(NSInteger)index
{
	[(NSComboBoxCell *)[self cell] scrollItemAtIndexToVisible:index];
}

- (void)deselectItemAtIndex:(NSInteger)index
{
	[(NSComboBoxCell *)[self cell] deselectItemAtIndex:index];
	[self setNeedsDisplay:YES];
}

@end
