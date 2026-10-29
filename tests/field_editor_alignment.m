/*
 * field_editor_alignment — the text being edited sits where the SAME cell draws that text when it is not being edited.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DEFECT WAS THE SAME PADDING PAID TWICE.** A field editor positions its text with `NS_TEXT_INSET` of its own
 * inside its frame (`NSText.m`: the baseline is `NSMaxY(bounds) - NS_TEXT_INSET - ascender`, and the pen's x is that
 * same inset from the edge), while the cell draws inside `-drawingRectForBounds:`, which adds the same air. The editor
 * was given the drawing rect — so editing text landed one inset (four points) lower than the text on either side of it,
 * and four points further in. MEASURED in Forge's info pane: the Version field's text dropped with its caret.
 *
 * The claim is an equality of two numbers the two drawing paths each compute for themselves: where the cell's text
 * starts inside the field, and where the editor's text starts inside the editor. A test that asserted the editor's
 * frame alone would be asserting the fix rather than the thing a person sees.
 */
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <math.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* THE TWO NUMBERS. `NSText` keeps its inset private, so the test measures it the way the class uses it: the first
 * glyph's baseline sits `NS_MAX_TEXT_INSET` below the editor's top, and this file names that constant once. */
static const CGFloat kTextInset = 4.0;

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		NSTextField *field;
		NSText *editor;
		id cell;

		(void)[application finishLaunching];
		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 320.0, 200.0)
						     styleMask:NSTitledWindowMask
						       backing:NSBackingStoreBuffered
							 defer:NO];
		/* A BEZELLED FIELD, which is the case a person types into: the border is what the padding is measured from. */
		field = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0, 20.0, 200.0, 24.0)];
		[field setBezeled:YES];
		[field setEditable:YES];
		[field setStringValue:@"1.2.2"];
		[[window contentView] addSubview:field];
		cell = [field cell];

		editor = (NSText *)[window fieldEditor:YES forObject:field];
		check(editor != nil, "the window lends a field editor");

		/* BEGIN A SESSION THE WAY A CLICK DOES — through the cell, at the field's own frame. */
		[(NSTextFieldCell *)cell selectWithFrame:[field bounds]
						  inView:field
						  editor:editor
						delegate:nil
						   start:0
						  length:[[field stringValue] length]];

		/* 1. THE EDITOR COVERS THE FIELD, because it supplies the padding the field's own drawing supplies. */
		check(NSEqualRects([editor frame], [field bounds]),
		      "the editor is placed over the field, not inside its padded rect");

		/* 2. AND THE TEXT LANDS WHERE THE CELL'S OWN TEXT LANDS, on both axes. */
		{
			NSRect room = [(NSTextFieldCell *)cell drawingRectForBounds:[field bounds]];
			CGFloat editorTextTop = NSMinY([editor frame]) + kTextInset;
			CGFloat editorTextLeft = NSMinX([editor frame]) + kTextInset;

			if (fabs((double)(editorTextTop - NSMinY(room))) > 0.5) {
				printf("       the editor's text starts %.1f pt from the cell's\n",
					(double)(editorTextTop - NSMinY(room)));
			}
			check(fabs((double)(editorTextTop - NSMinY(room))) <= 0.5,
			      "the edited text sits on the baseline row the cell draws it on");
			check(fabs((double)(editorTextLeft - NSMinX(room))) <= 0.5,
			      "and starts at the same distance from the border");
		}

		/* 3. THE EDITOR IS THE TEXT THAT SHOWS, so its string is the field's. */
		check([[editor string] isEqualToString:@"1.2.2"], "the editor holds the field's value");

		/* 4. AND ENDING THE SESSION LEAVES NOTHING BEHIND. */
		[(NSTextFieldCell *)cell endEditing:editor];
		check([editor superview] == nil, "the editor left the field when the session ended");

		[field release];
		[window release];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
