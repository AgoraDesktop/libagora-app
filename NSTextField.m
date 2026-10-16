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

/* **AND THE BORDER'S SHAPE IS A FORWARD LIKE THE REST, WITH THE REDISPLAY A VIEW OWES.** The cell stores the style and
 * the DRAWING reads it, so the control's half is exactly what `-setBordered:`'s is: tell the cell, then mark this view
 * for redisplay. A cell has no view to ask, which is why the redisplay cannot live in its setter. */
- (NSTextFieldBezelStyle)bezelStyle
{
	return [(NSTextFieldCell *)[self cell] bezelStyle];
}

- (void)setBezelStyle:(NSTextFieldBezelStyle)style
{
	[(NSTextFieldCell *)[self cell] setBezelStyle:style];
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

/* ============================================================================================ *
 * THE DELEGATE: THE CELL'S REPORTS, RE-HOMED TO THE CONTROL AND PASSED ON                        *
 * ============================================================================================ */

- (id <NSTextFieldDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(id <NSTextFieldDelegate>)anObject
{
	/* NOT RETAINED, and not released on the way out: this tree's rule for every delegate. A field that retained its
	 * delegate would own whatever owned it. */
	_delegate = anObject;
}

/* **THE TWO QUESTIONS ARE ASKED AND ANSWERED, AND NO IS HONOURED.** `-textShouldBeginEditing:` is reached from the
 * editor's `-becomeFirstResponder` (through the cell, which is the editor's delegate), so a NO leaves the session
 * UNOPENED — and the cell's session door tears the half-built session down rather than leaving an editor nobody is
 * typing into. `-textShouldEndEditing:` is reached from `-resignFirstResponder`, so a NO keeps the editor exactly
 * where it is: the caret stays and the value is not committed. A delegate that does not implement them says YES by not
 * answering, which is what `@optional` on the protocol and the `-respondsToSelector:` below are for. */
- (BOOL)textShouldBeginEditing:(NSText *)textObject
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(control:textShouldBeginEditing:)]) {
		return [_delegate control:self textShouldBeginEditing:textObject];
	}
	return YES;
}

- (BOOL)textShouldEndEditing:(NSText *)textObject
{
	if (_delegate != nil && [_delegate respondsToSelector:@selector(control:textShouldEndEditing:)]) {
		return [_delegate control:self textShouldEndEditing:textObject];
	}
	return YES;
}

/* **AND EVERY ANNOUNCEMENT GOES OUT TWICE, WHICH IS APPLE'S DESIGN AND NOT A DUPLICATION.** A delegate that CONFORMS
 * is told as a method; an object that would rather not conform registers for the NOTIFICATION and is told by the
 * center. Both carry the same facts — the notification's OBJECT is the CONTROL, never the editor, and its `userInfo`
 * names the field editor under `NSFieldEditorUserInfoKey` — so a listener gets the editor without conforming, and a
 * delegate gets it as an argument rather than through a dictionary. A conformer that does BOTH is told twice, which is
 * Apple's behaviour and the caller's own business. */
- (void)textDidBeginEditing:(NSNotification *)notification
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:[notification object] forKey:NSFieldEditorUserInfoKey];
	NSNotification *note = [NSNotification notificationWithName:NSControlTextDidBeginEditingNotification
							     object:self userInfo:info];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(controlTextDidBeginEditing:)]) {
		[_delegate controlTextDidBeginEditing:note];
	}
}

- (void)textDidChange:(NSNotification *)notification
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:[notification object] forKey:NSFieldEditorUserInfoKey];
	NSNotification *note = [NSNotification notificationWithName:NSControlTextDidChangeNotification
							     object:self userInfo:info];

	/* **AND THE CONTROL REDRAWS ITSELF ON EVERY EDIT, WHICH IS THE PLACEHOLDER'S REQUIREMENT RATHER THAN THE TEXT'S.**
	 * During a session the words are the EDITOR's and the editor redraws itself; what the CELL still draws is the
	 * PLACEHOLDER, and whether that belongs on screen depends on whether the editor is EMPTY — a fact that changes with
	 * the first character typed and the last one deleted. Without this line the placeholder would appear and disappear
	 * only when something else happened to ask the window to repaint. */
	[self setNeedsDisplay:YES];
	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(controlTextDidChange:)]) {
		[_delegate controlTextDidChange:note];
	}
}

/* **AND THE END OF AN EDIT IS TWO PIECES OF WORK AT ONE DOOR: THE DELEGATE IS TOLD, AND A COMMITTED VALUE SENDS THIS
 * CONTROL'S ACTION.** The rule about the action moved HERE from `NSControl` with the class that made it meaningful — a
 * control with no field editor has no session to end — and it is unchanged: a field's value is committed by ending its
 * session, and the control that owns the value is what a caller set a target on. So Return and Tab send; ESCAPE DOES
 * NOT, because `NSTextMovementCancel` means the session was thrown away, and a control that sent its action there
 * would tell a caller that a value the model never accepted had been entered. MEASURED, before the movement existed:
 * Escape committed, because nothing distinguished it from a click away.
 *
 * THE SENDER IS THE CONTROL rather than the editor, because a caller's handler is written against the CONTROL — the
 * thing with a value and a cell — and an editor is a view the window happens to be lending. The movement travels on to
 * the delegate in the notification's `userInfo`, so a listener can tell a commit from a cancel without asking
 * anything. */
- (void)textDidEndEditing:(NSNotification *)notification
{
	id editor = [notification object];
	id raw = [[notification userInfo] objectForKey:NSTextMovementUserInfoKey];
	NSTextMovement movement = (raw != nil) ? (NSTextMovement)[raw integerValue] : NSTextMovementOther;
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
		editor, NSFieldEditorUserInfoKey,
		[NSNumber numberWithInteger:(NSInteger)movement], NSTextMovementUserInfoKey, nil];
	NSNotification *note = [NSNotification notificationWithName:NSControlTextDidEndEditingNotification
							     object:self userInfo:info];

	[[NSNotificationCenter defaultCenter] postNotification:note];
	if (_delegate != nil && [_delegate respondsToSelector:@selector(controlTextDidEndEditing:)]) {
		[_delegate controlTextDidEndEditing:note];
	}
	if (movement == NSTextMovementReturn || movement == NSTextMovementTab || movement == NSTextMovementBacktab) {
		[[NSApplication sharedApplication] sendAction:[self action] to:[self target] from:self];
	}
}

@end
