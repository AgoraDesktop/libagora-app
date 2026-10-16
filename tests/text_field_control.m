/*
 * text_field_control.m — THE VIEW ABOVE THE FIELD CELL: A CLICK THAT OPENS A SESSION, AND WHAT COMMITS IT.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **THE CELL'S OWN PROBE DRIVES THE CELL; THIS ONE DRIVES THE CONTROL.** `tests/text_field_cell.m` begins a session
 * by hand — a window lends an editor, a caller tells the cell to begin — which is the right instrument for the cell's
 * arithmetic. What it cannot show is the half a PERSON exercises: that a press on a field is what starts the edit,
 * that Return sends the action while Escape does not, and that the responder the window ends up holding is the editor
 * rather than the field. Those are the control's, and they are what this file drives.
 *
 * **AND IT IS DRIVEN WITHOUT AN EVENT LOOP OR A DISPLAY.** Every step is a call the probe makes itself: a press is an
 * `NSEvent` built by hand and handed to `-mouseDown:` (which reads no geometry — the field's press is the beginning of
 * a session, and the session's rectangle comes from the field's bounds, not the click's position), and Return and
 * Escape are the two command doors the editor implements. That is what makes a field's gesture testable offscreen.
 */
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSResponder.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>

static int failures = 0;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* A TARGET THAT COUNTS ITS ACTIONS, because "the action was sent once" is the claim a committed session makes and a
 * boolean would not tell "once" from "twice". */
@interface Counter : NSObject
{
@public
	int actions;
}
- (void)counted:(id)sender;
@end

@implementation Counter
- (void)counted:(id)sender
{
	(void)sender;
	actions++;
}
@end

/* **A PRESS, BUILT BY HAND, AT A POINT INSIDE THE FIELD.** The field's `-mouseDown:` reads no geometry — the editor's
 * rectangle is the field's bounds — so the point only has to be one a person could have clicked. */
static NSEvent *press(void)
{
	return [NSEvent mouseEventWithType:NSLeftMouseDown
				  location:NSMakePoint(20.0, 60.0)
			     modifierFlags:0
				 timestamp:0.0
			      windowNumber:0
				   context:nil
			       eventNumber:1
				clickCount:1
				  pressure:1.0f];
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 120.0)
						       styleMask:NSBorderlessWindowMask
							 backing:NSBackingStoreBuffered
							   defer:NO];
	NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 120.0)];
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(10.0, 50.0, 200.0, 23.0)];
	Counter *counter = [[Counter alloc] init];
	NSText *editor;

	[window setContentView:content];
	/* **THE FIELD HAS TO BE IN A WINDOW, BECAUSE THE EDITOR COMES FROM ONE.** A session is opened with the window's
	 * field editor, so a field that was built but never put anywhere has no window to borrow one from — which is a
	 * real state and not a test artefact: the same is true of a control that has been removed from its window. */
	[content addSubview:field];
	[field setStringValue:@"hello"];

	/* 1. **A FIELD MAKES A FIELD CELL, AND A DEFAULT FIELD IS A FIELD RATHER THAN A LABEL.** The four flags are what
	 * make a press an edit and what put a surface under the words; a class whose default was a label would make every
	 * caller opt into being a field. */
	check([[field cell] isKindOfClass:[NSTextFieldCell class]], "a field's cell is a field cell");
	check([field isEditable] && [field isSelectable],
	      "a default field is editable and selectable, which is what makes a press an edit");
	check([field isBordered] && [field isBezeled],
	      "and bordered and bezeled, which is what puts a surface under the words");
	check([[field stringValue] isEqualToString:@"hello"],
	      "and the string it was given is the string it answers, through the cell");

	/* 2. **THE KEYBOARD IS ACCEPTED ONLY WHEN THERE IS SOMEWHERE TO PUT A CARET.** */
	check([field acceptsFirstResponder], "an editable, enabled field accepts the keyboard");
	[field setEnabled:NO];
	check(![field acceptsFirstResponder], "a disabled field does not");
	[field setEnabled:YES];
	[field setEditable:NO];
	check(![field acceptsFirstResponder], "and neither does a label");
	[field setEditable:YES];

	/* 3. **AND A FIELD NOBODY HAS TOUCHED HAS NO EDITOR.** The door has to answer nil rather than a stale pointer,
	 * because a caller asks it before there is anything to ask about. */
	check([field currentEditor] == nil, "a field nobody has clicked has no editor");

	/* 4. **THE PRESS IS WHAT OPENS A SESSION.** A click on a field is not a button press: it starts an edit that
	 * outlives the press, which is why `NSControl`'s tracking loop is the wrong gesture and this class does not call
	 * it. The editor comes from the WINDOW and is put in the FIELD, so the words a person sees are the field's. */
	[field mouseDown:press()];
	editor = (NSText *)[field currentEditor];
	check(editor != nil, "a press on an editable field opens a session");
	check(editor == (NSText *)[window fieldEditor:NO forObject:field],
	      "with the window's own field editor, which is the one a window lends and keeps");
	check([editor superview] == field, "put in the field, so the words are where the field's words are");
	check([[editor string] isEqualToString:@"hello"],
	      "holding the field's string, so the field shows what it holds the moment it is clicked into");
	check([window firstResponder] == (NSResponder *)editor,
	      "and the EDITOR is the window's first responder, not the field — this is where the keyboard went");

	/* 5. **RETURN COMMITS AND SENDS THE ACTION.** A committed session is what a caller's handler waits for, and it is
	 * the control that turns the ending into the action — the cell reports the reason and `NSControl` sends. */
	[field setTarget:counter];
	[field setAction:@selector(counted:)];
	[editor replaceCharactersInRange:NSMakeRange(0, [[editor string] length]) withString:@"typed"];
	[editor insertNewline:nil];
	check([[field stringValue] isEqualToString:@"typed"],
	      "RETURN puts what was typed into the FIELD, through the cell that owns the string");
	check(counter->actions == 1, "and sends the field's action exactly once");
	check([field currentEditor] == nil, "and the session is over");
	check([editor superview] == nil, "because the editor has left the view it was lent to");
	check([window firstResponder] != (NSResponder *)editor,
	      "and the window is no longer holding a detached editor as its responder");

	/* 6. **ESCAPE THROWS THE EDIT AWAY AND SENDS NOTHING.** Both keys end the session; they differ in one answer, and
	 * the action is where a caller sees that difference. */
	{
		int before = counter->actions;

		[field setStringValue:@"original"];
		[field mouseDown:press()];
		editor = (NSText *)[field currentEditor];
		check(editor != nil, "a second press opens a second session");
		[editor replaceCharactersInRange:NSMakeRange(0, [[editor string] length]) withString:@"thrown away"];
		[editor cancelOperation:nil];
		check([[field stringValue] isEqualToString:@"original"],
		      "ESCAPE throws the edit away — the field keeps what it had");
		check(counter->actions == before, "and sends NO action, because no value was committed");
		check([field currentEditor] == nil, "and the session is over all the same");
	}

	/* 7. **AND `-selectText:` IS THE SAME SESSION WITHOUT A POINTER.** A caller that focuses a field, or a form that
	 * opens with a value ready to replace, wants the whole string taken — which is the same starting selection a first
	 * click into an unselected field uses. */
	{
		[field setStringValue:@"select me"];
		[field selectText:nil];
		editor = (NSText *)[field currentEditor];
		check(editor != nil, "-selectText: opens a session with no pointer involved");
		check([editor selectedRange].location == 0 && [editor selectedRange].length == 9,
		      "and takes the whole string, which is what clicking an unselected field does");
	}

	/* 8. **AND `-abortEditing` IS THE SAME ENDING AS ESCAPE, REACHED THROUGH A DOOR.** It is the half of a form's
	 * "cancel" that a caller cannot express with a key, and it must leave the window with no first responder rather
	 * than still holding the editor it took down. */
	{
		/* **WHAT THE ABORT THROWS AWAY IS THE EDITOR'S TEXT, NOT THE CELL'S VALUE** — which is why the edit is made in
		 * the EDITOR. Setting the field's value here would reach the editor too (`-setStringValue:` tells a running
		 * session, so the field SHOWS what it holds), and the two would agree again: the case would pass for the wrong
		 * reason. This is the session case 7 opened, still over "select me". */
		editor = (NSText *)[field currentEditor];
		[editor replaceCharactersInRange:NSMakeRange(0, [[editor string] length]) withString:@"discard me"];
		[field abortEditing];
		check([[field stringValue] isEqualToString:@"select me"],
		      "-abortEditing throws away what is in the editor — the field keeps the value it had");
		check([field currentEditor] == nil, "and the session is over");
		check([window firstResponder] != (NSResponder *)editor,
		      "and the window is not left holding the detached editor");
		check(![field abortEditing], "aborting a field with no session answers NO, which is Apple's reading of it");

		/* AND ONCE MORE FROM A CLEAN START: the value at the moment of the abort is the value that survives, which is
		 * the whole difference between abort and commit. */
		[field setStringValue:@"keep me"];
		[field selectText:nil];
		editor = (NSText *)[field currentEditor];
		[editor replaceCharactersInRange:NSMakeRange(0, [[editor string] length]) withString:@"discard me"];
		check([field abortEditing], "a live session answers YES to an abort");
		check([[field stringValue] isEqualToString:@"keep me"], "and the edit is discarded rather than committed");
	}

	/* 9. **A FIELD THAT IS NOT EDITABLE IS A LABEL, AND A PRESS ON IT DOES NOTHING.** There is no session to open, and
	 * the tracking loop is the wrong gesture for a field of any kind. */
	[field setEditable:NO];
	[field mouseDown:press()];
	check([field currentEditor] == nil, "a press on a field that is not editable opens nothing");
	check(counter->actions == 1, "and sends no action, because a label is not a control a press acts on");
	[field setEditable:YES];

	/* 10. **AND FOCUSING THE FIELD IS OPENING ITS SESSION.** Apple's rule is that a field's responder is its editor, so
	 * `-becomeFirstResponder` here does not take the keyboard — it puts up the session that does. This is the case that
	 * makes a form usable from the keyboard without a click. */
	{
		[field setStringValue:@"focus me"];
		check([window makeFirstResponder:field], "asking the window to focus the field succeeds");
		check([field currentEditor] != nil, "because focusing an editable field opens its session");
		check([window firstResponder] == (NSResponder *)[field currentEditor],
		      "and the window ends up holding the EDITOR, because that is where the keyboard belongs");
		[field abortEditing];
	}

	/* 11. **AND THE WINDOW'S OWN DOOR ENDS A SESSION, NOW THAT THERE IS ONE TO END.** `-endEditingFor:` was a no-op
	 * whose stated reason was that the tier had no field editor; the reason expired with the field editor, so the door
	 * now performs the ending a click into another view performs. This is the half a caller exercises when it takes
	 * the keyboard away programmatically. */
	{
		[field setStringValue:@"commit me"];
		[field selectText:nil];
		editor = (NSText *)[field currentEditor];
		check(editor != nil, "a session is open before the window's door is asked");
		[editor replaceCharactersInRange:NSMakeRange(0, [[editor string] length]) withString:@"ended by the window"];
		[window endEditingFor:field];
		check([field currentEditor] == nil, "-endEditingFor: ends the window's editing session");
		check([[field stringValue] isEqualToString:@"ended by the window"],
		      "and the edit is committed, because it is the ending a click elsewhere performs");
		check([editor superview] == nil, "and the editor leaves the view it was lent to");
	}

	[counter release];
	[field release];
	[content release];
	[window release];
	[pool release];
	printf("text_field_control: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
