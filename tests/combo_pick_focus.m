/*
 * combo_pick_focus — a pick from a combo box's list writes THE BOX THAT OWNS THE LIST, not the field being edited.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE BUG THIS FILE EXISTS FOR WAS "selecting from a combo box's menu with the input caret in another box causes the
 * value of the combo box menu item to be written to the wrong box".** The pick itself is sound: every row is pointed at
 * the cell that built it, with the row's index as the tag. What is NOT sound is what the cell does with its own string
 * while a session is live. `NSTextFieldCell -setStringValue:` writes the cell's value AND, when the cell has an
 * editor, pushes the same string into that editor. A shared field editor is the window's, so a cell that has been
 * given the window's editor without being the first responder owns a pointer into somebody else's live text — and a
 * combo box's list selection then writes the picked row into the field the person is typing in.
 *
 * The probe puts the caret in one field, picks a row from a combo box that is NOT editing, and asserts that the
 * picked row lands in the combo box and the focused field keeps every character it had.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSComboBox.h>
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSText.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>

#import <Foundation/NSAutoreleasePool.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  [%s] %s\n", ok ? "ok" : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	NSView *content;
	NSComboBox *combo;
	NSTextField *focused;
	NSText *editor;
	NSMenu *list;

	(void)application;
	printf("combo_pick_focus\n");
	[application finishLaunching];

	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100.0, 100.0, 400.0, 220.0)
					     styleMask:NSTitledWindowMask
					       backing:NSBackingStoreBuffered
						 defer:NO];
	content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 220.0)];
	[window setContentView:content];

	combo = [[NSComboBox alloc] initWithFrame:NSMakeRect(20.0, 130.0, 200.0, 24.0)];
	[combo addItemWithObjectValue:@"First"];
	[combo addItemWithObjectValue:@"NSComboBox"];
	[content addSubview:combo];

	focused = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0, 70.0, 200.0, 24.0)];
	[focused setStringValue:@"typed text"];
	[content addSubview:focused];

	[window makeKeyAndOrderFront:nil];
	/* **THE HANDOFF IS THE BUG.** The window lends ONE editor. Begin a session in the combo, then focus the other
	 * field: the second `-selectText:` gets the SAME editor back, and the window's `-makeFirstResponder:` sees the
	 * editor is already the first responder and returns without ending the first session. The combo cell keeps a
	 * pointer to the editor that now belongs to the focused field. */
	[combo selectText:nil];
	printf("  combo's editor after its own session began: %s\n",
	       ([combo currentEditor] != nil) ? "present" : "ABSENT");
	[focused selectText:nil];
	editor = [focused currentEditor];
	printf("  focused field's editor: %s (text \"%s\"), combo's now %s\n",
	       (editor != nil) ? "present" : "ABSENT",
	       (editor != nil) ? [[editor string] UTF8String] : "",
	       ([combo currentEditor] != nil) ? "STILL PRESENT" : "ended");
	check([combo currentEditor] == nil,
	      "moving the caret to another field ENDED the combo box's session");

	list = [(NSComboBoxCell *)[combo cell] cg_buildListMenu];
	check(list != nil && [list numberOfItems] == 2, "the combo box built its two-row list");
	[list performActionForItemAtIndex:1];

	printf("  after the pick: combo \"%s\", focused field \"%s\", editor \"%s\"\n",
	       [[combo stringValue] UTF8String], [[focused stringValue] UTF8String],
	       (editor != nil) ? [[editor string] UTF8String] : "");
	check([[combo stringValue] isEqualToString:@"NSComboBox"], "the picked row landed in the combo box");
	check([[focused stringValue] isEqualToString:@"typed text"],
	      "and the field that had the caret kept its value");
	check(editor == nil || [[editor string] isEqualToString:@"typed text"],
	      "and the live editor kept the text the person had typed");

	[focused release];
	[combo release];
	[content release];
	[window release];
	[pool release];
	printf("combo_pick_focus: %d case(s) failed\n", s_failed);
	return s_failed == 0 ? 0 : 1;
}
