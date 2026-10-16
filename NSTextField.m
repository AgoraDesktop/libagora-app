/*
 * NSTextField.m — a field cell in a view, and the three doors a click needs to become an edit.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CLASS IS A CELL IT MAKES, A WALL OF FORWARDS, AND TWO DOORS THE CELL COULD NOT REACH.** The forwards are the
 * face and the two flags, each ending at the cell because the cell is what shows the string and what would be typed
 * into. The two doors with behaviour are `-mouseDown:` and `-selectText:`, and they are the same act — open a session
 * over this cell's text with the editor the WINDOW lends — reached from the pointer and from a caller. Everything a
 * session then does belongs to `NSTextFieldCell`; everything a committed session MEANS (an action to the target)
 * belongs to `NSControl`. This class is the place those two meet.
 */
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSText.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSApplication.h>

@implementation NSTextField

/* **THE INITIALISER IS THE ONE DOOR WITH A DECISION IN IT, AND THE DECISION IS THE CELL.** `NSControl`'s
 * `-initWithFrame:` makes no cell at all; a field wants the one that owns a face, a string and a session. The frame is
 * re-measured only when the caller gave a degenerate one, which is the same contract `NSComboBox` and `NSPopUpButton`
 * record: a field asked to size itself does so from its cell's own measurement. */
- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	if (self != nil) {
		NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];

		/* **A DEFAULT FIELD IS A FIELD AND NOT A LABEL.** Editable and selectable are what make a press an edit;
		 * bordered and bezeled are the surface a value is written on rather than a bare run of text. Apple's default
		 * field is all four, and a class whose default was a label would make every caller opt into being a field. */
		[cell setEditable:YES];
		[cell setSelectable:YES];
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

/* ---- WHAT MAY BE DONE TO IT ------------------------------------------------------------------------- */

- (BOOL)isEditable
{
	return [(NSTextFieldCell *)[self cell] isEditable];
}

- (void)setEditable:(BOOL)flag
{
	[(NSTextFieldCell *)[self cell] setEditable:flag];
	[self setNeedsDisplay:YES];
}

- (BOOL)isSelectable
{
	return [(NSTextFieldCell *)[self cell] isSelectable];
}

- (void)setSelectable:(BOOL)flag
{
	[(NSTextFieldCell *)[self cell] setSelectable:flag];
	[self setNeedsDisplay:YES];
}

/* ---- THE FACE, WHICH IS THE CELL'S ------------------------------------------------------------------ */

- (BOOL)drawsBackground
{
	return [(NSTextFieldCell *)[self cell] drawsBackground];
}

- (void)setDrawsBackground:(BOOL)flag
{
	[(NSTextFieldCell *)[self cell] setDrawsBackground:flag];
	[self setNeedsDisplay:YES];
}

- (NSColor *)backgroundColor
{
	return [(NSTextFieldCell *)[self cell] backgroundColor];
}

- (void)setBackgroundColor:(NSColor *)color
{
	[(NSTextFieldCell *)[self cell] setBackgroundColor:color];
	[self setNeedsDisplay:YES];
}

- (NSColor *)textColor
{
	return [(NSTextFieldCell *)[self cell] textColor];
}

- (void)setTextColor:(NSColor *)color
{
	[(NSTextFieldCell *)[self cell] setTextColor:color];
	[self setNeedsDisplay:YES];
}

- (BOOL)isBezeled
{
	return [(NSTextFieldCell *)[self cell] isBezeled];
}

- (void)setBezeled:(BOOL)flag
{
	[(NSTextFieldCell *)[self cell] setBezeled:flag];
	[self setNeedsDisplay:YES];
}

- (BOOL)isBordered
{
	return [(NSTextFieldCell *)[self cell] isBordered];
}

- (void)setBordered:(BOOL)flag
{
	[(NSTextFieldCell *)[self cell] setBordered:flag];
	[self setNeedsDisplay:YES];
}

/* ---- THE KEYBOARD, WHICH A FIELD SURRENDERS TO ITS EDITOR ------------------------------------------- */

/* **A FIELD WANTS THE KEYBOARD ONLY WHEN IT HAS SOMEWHERE TO PUT A CARET.** An editable, enabled field says yes; a
 * label says no, which is what keeps `-makeFirstResponder:` from parking the keyboard on something that cannot use it. */
- (BOOL)acceptsFirstResponder
{
	return [self isEditable] && [self isEnabled];
}

/* **AND BECOMING THE FIRST RESPONDER IS OPENING THE SESSION, NOT TAKING THE KEYBOARD.** The responder the window
 * should end up with is the EDITOR — it is the view the caret is in and the view keystrokes reach — so this door puts
 * one up and answers whether it did. A caller who asked a field to focus it has, in effect, asked it to start being
 * typed into, which is exactly Apple's behavior.
 *
 * THE GUARD IS REAL EVEN THOUGH NOTHING HERE REFUSES YET. `NSWindow -makeFirstResponder:` restores a displaced
 * responder by calling `-becomeFirstResponder` on it again, so if a session ever failed to open — the field-delegate
 * slice the header names — this method would be re-entered from inside its own `-selectText:`, with the cell's editor
 * already set, and would try to open a second session over the first. A field already showing a session is already
 * the responder that matters, so the door answers yes and does nothing. */
- (BOOL)becomeFirstResponder
{
	if ([self currentEditor] != nil) {
		return YES;
	}
	[self selectText:nil];
	return [self currentEditor] != nil;
}

/* ---- THE POINTER AND THE CALLER, WHICH ARE THE TWO WAYS INTO AN EDIT --------------------------------- */

/* **THE PRESS OPENS A SESSION, AND `-super` IS DELIBERATELY NOT CALLED.** `NSControl`'s press is a BUTTON's gesture:
 * highlight the cell, follow the pointer, send the action on the release. A field does none of that — its press is the
 * beginning of an edit that OUTLIVES the press — so the superclass loop is exactly the wrong behaviour and running it
 * would send a caller's action for a click that was meant to start typing.
 *
 * A FIELD THAT IS NOT EDITABLE IS A LABEL: a press on a label opens nothing and does nothing. A press on a field that
 * is ALREADY being edited is ignored too, because the editor is a subview covering the text and the click that landed
 * here is on the padding around it — the caret arithmetic for that click belongs to the editor, and restarting the
 * session would throw away what is already typed. */
- (void)mouseDown:(NSEvent *)event
{
	NSTextFieldCell *cell = (NSTextFieldCell *)[self cell];
	NSText *editor;

	if (![self isEditable] || ![self isEnabled] || [self currentEditor] != nil) {
		return;
	}
	editor = (NSText *)[[self window] fieldEditor:YES forObject:self];
	if (editor == nil) {
		return;
	}
	/* **THE CONTROL IS THE CALLER THE CELL REPORTS TO, WHICH IS HOW A COMMITTED EDIT REACHES A TARGET.** The cell
	 * hands its caller's delegate the movement when the session ends, and `NSControl -textDidEndEditing:` is what
	 * turns Return and Tab into this control's action — so the field and the handler are one gesture rather than two.
	 * The rect handed over is this view's BOUNDS, because that is the space the cell and the editor share. */
	[cell editWithFrame:[self bounds] inView:self editor:editor delegate:self event:event];
	[self setNeedsDisplay:YES];
}

/* **AND SELECTING IS THE SAME SESSION WITHOUT A POINTER.** A caller that focuses a field, or a form that opens with a
 * value ready to replace, wants the whole string taken — which is exactly what a first click into an unselected field
 * does, so it is the same starting selection and not a second rule. A field already in a session is asked to select
 * its editor's string rather than have a second editor put up. */
- (void)selectText:(id)sender
{
	NSTextFieldCell *cell = (NSTextFieldCell *)[self cell];
	NSText *editor;
	NSUInteger length;

	(void)sender;
	if (![self isEditable]) {
		return;
	}
	length = [[self stringValue] length];
	editor = [self currentEditor];
	if (editor != nil) {
		[editor setSelectedRange:NSMakeRange(0, length)];
		return;
	}
	editor = (NSText *)[[self window] fieldEditor:YES forObject:self];
	if (editor == nil) {
		return;
	}
	[cell selectWithFrame:[self bounds] inView:self editor:editor delegate:self start:0 length:(NSInteger)length];
	[self setNeedsDisplay:YES];
}

@end
