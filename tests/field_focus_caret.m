/*
 * field_focus_caret — the field the focus LEFT is repainted, so its caret goes with the focus.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE DEFECT WAS A FIELD WHOSE PIXELS WERE THE EDITOR'S AND NOBODY ASKED IT TO PAINT AGAIN.** While a session is up a
 * cell draws no words of its own — the editor's text and caret are the ink — so when the session ends and the editor
 * moves to another field, the caret stays on the glass until something else marks the first field dirty. Something did:
 * the pointer passing over it. MEASURED as two carets, one of which disappeared only when the mouse arrived.
 *
 * The claim is the invalidation, which is the thing that was missing: after the focus moves, the OLD field must be
 * marked for display. `-needsDisplay` is public and is exactly that question, so the probe asks it rather than
 * rendering and looking for a caret's pixels.
 */
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* THE CELL'S OWN ANSWER TO "IS AN EDITOR MINE", declared here the way this tree declares a `cg_` seam it uses. */
@interface NSTextFieldCell (AGFocusProbe)
- (NSText *)cg_currentEditor;
@end

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		NSWindow *window;
		NSTextField *first;
		NSTextField *second;
		NSText *editor;

		(void)[application finishLaunching];
		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 360.0, 200.0)
						     styleMask:NSTitledWindowMask
						       backing:NSBackingStoreBuffered
							 defer:NO];
		first = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0, 120.0, 220.0, 24.0)];
		second = [[NSTextField alloc] initWithFrame:NSMakeRect(20.0, 80.0, 220.0, 24.0)];
		[first setBezeled:YES];
		[second setBezeled:YES];
		[first setStringValue:@"first"];
		[second setStringValue:@"second"];
		[[window contentView] addSubview:first];
		[[window contentView] addSubview:second];

		/* 1. A SESSION ON THE FIRST FIELD, begun the way a click begins one. */
		editor = (NSText *)[window fieldEditor:YES forObject:first];
		[[first cell] selectWithFrame:[first bounds] inView:first editor:editor delegate:nil
				start:0 length:[[first stringValue] length]];
		check([[(NSTextFieldCell *)[first cell] cg_currentEditor] isEqual:editor],
		      "the first field has the editor");
		check([editor superview] == first, "and the editor is in it");

		/* 2. THE POINTER'S NEXT CLICK TAKES THE EDITOR TO THE SECOND FIELD — the window's own handoff, which is what
		 * `-fieldEditor:forObject:` performs when the owner changes. */
		[first setNeedsDisplay:NO];
		/* THE WINDOW'S OWN HANDOFF — what `-fieldEditor:forObject:` performs when the owner changes, asked directly
		 * so the probe measures the door rather than a borrow. */
		[window endEditingFor:first];
		(void)[window fieldEditor:YES forObject:second];
		[[second cell] selectWithFrame:[second bounds] inView:second editor:editor delegate:nil
				start:0 length:[[second stringValue] length]];

		check([(NSTextFieldCell *)[first cell] cg_currentEditor] == nil,
		      "the first field's session has ended");
		check([[((NSTextFieldCell *)[second cell]) cg_currentEditor] isEqual:editor],
		      "and the second field has the editor");

		/* 3. **AND THE FIRST FIELD IS MARKED FOR DISPLAY, WHICH IS THE WHOLE OF THE FIX.** Without it the caret the
		 * editor drew there stays until something else invalidates the field. */
		check([first needsDisplay] == YES,
		      "the field the focus LEFT is marked dirty, so its caret is painted away");

		/* 4. AND THE SECOND FIELD DRAWS ITS OWN WORDS AGAIN — the editor is gone from it. */
		[[second cell] endEditing:editor];
		check([editor superview] == nil, "ending the session takes the editor out of the field");
		check([second needsDisplay] == YES, "and the field it left is marked dirty too");

		[first release];
		[second release];
		[window release];
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
