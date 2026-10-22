/*
 * text_field_attributes.m — WHAT A FIELD MAY HOLD, AND THE EDITOR IT TELLS ABOUT IT.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **TWO FLAGS AND THE DOOR THAT CARRIES THEM, WHICH IS THE PART THAT WAS NOT WIRED.** `NSCell` has carried
 * `-allowsEditingTextAttributes` and `-importsGraphics` since the cell family's first slice, and the field EDITOR has
 * carried `-isRichText` and `-isImportsGraphics` since the text view's — and nothing connected the two, so a caller
 * could set a field rich and get a plain editor. The claim here is that connection: a flag set on the CONTROL reaches
 * the CELL, and the NEXT session's editor is configured from it. That is a chain of three objects, so it is checked
 * at all three rather than at the one a caller happens to hold.
 *
 * **AND THE DOOR ITSELF IS EXERCISED DIRECTLY**, because `-setUpFieldEditorAttributes:` is what a subclass would
 * override and a probe that only ever reached it through a window could not tell whether it configured the editor or
 * whether the session did.
 */
#import <AppKit/NSTextField.h>
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSText.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSFont.h>
#import <Foundation/NSAutoreleasePool.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 120.0)
						       styleMask:NSBorderlessWindowMask
							 backing:NSBackingStoreBuffered defer:NO];
	NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 120.0)];
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(10.0, 50.0, 200.0, 23.0)];
	NSText *editor;

	[window setContentView:content];
	[content addSubview:field];

	/* 1. **A FRESH FIELD MAY HOLD NEITHER**, because `NSCell`'s defaults are NO and this class adds no default of its
	 * own — a field is plain unless a caller says otherwise. */
	check(![field allowsEditingTextAttributes], "a fresh field does not allow editing text attributes");
	check(![field importsGraphics], "and does not import graphics");

	/* 2. **AND SETTING THEM ON THE CONTROL REACHES THE CELL.** The control owns no flag of its own; the pair is a
	 * forward, so this is the whole of the chain's first hop. */
	[field setAllowsEditingTextAttributes:YES];
	[field setImportsGraphics:YES];
	check([field allowsEditingTextAttributes] && [[field cell] allowsEditingTextAttributes],
	      "setting allows-editing-text-attributes on the CONTROL reaches the CELL");
	check([field importsGraphics] && [[field cell] importsGraphics],
	      "and setting imports-graphics does too");

	/* 3. **AND THE CELL TELLS THE EDITOR, WHICH IS THE HOP THAT DID NOT EXIST.** A session is opened on the field and
	 * the editor the window lent is configured from the cell's flags — so the connection is from the flag a caller set
	 * to the object that would honour it. */
	[field selectText:nil];
	editor = (NSText *)[field currentEditor];
	check(editor != nil, "a session opens on the field");
	check([editor isRichText], "and the EDITOR is rich, because the cell's flag said so");
	check([editor importsGraphics], "and imports graphics, for the same reason");
	[field abortEditing];

	/* 4. **AND A FIELD THAT MAY HOLD NEITHER GETS A PLAIN EDITOR.** The other side of the same hop, so the check above
	 * cannot pass with an editor that is always rich. */
	[field setAllowsEditingTextAttributes:NO];
	[field setImportsGraphics:NO];
	[field selectText:nil];
	editor = (NSText *)[field currentEditor];
	check(editor != nil && ![editor isRichText], "a field with the flag OFF gets a plain editor");
	check(editor != nil && ![editor importsGraphics], "and one that imports nothing");
	[field abortEditing];

	/* 5. **AND THE FLAG IS READ AT EVERY SESSION, NOT ONCE AT CONSTRUCTION.** A field switched to rich between two
	 * sessions is rich the second time — which is what "the editor is configured from the cell" means rather than "the
	 * editor was configured once". */
	[field setAllowsEditingTextAttributes:YES];
	[field selectText:nil];
	editor = (NSText *)[field currentEditor];
	check(editor != nil && [editor isRichText], "and a flag set BETWEEN sessions is honoured by the next one");
	[field abortEditing];

	/* 6. **AND THE DOOR ITSELF, DRIVEN DIRECTLY, WHICH IS WHAT A SUBCLASS WOULD OVERRIDE.** A bare cell is handed a
	 * bare editor: the door returns it, marks it a field editor, and takes the cell's own font and alignment — so the
	 * configuration is the CELL's and not a side effect of the window's session. */
	{
		NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"x"];
		NSText *bare = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 20.0)];
		NSFont *font = [NSFont systemFontOfSize:13.0];
		NSText *returned;

		[cell setFont:font];
		[cell setAllowsEditingTextAttributes:YES];
		returned = [cell setUpFieldEditorAttributes:bare];
		check(returned == bare, "`-setUpFieldEditorAttributes:` answers the editor it was given");
		check([bare isFieldEditor], "with the field-editor role set");
		check(![bare drawsBackground], "and painting no background of its own");
		check([bare font] == font, "and carrying the CELL's font");
		check([bare isRichText] == [cell allowsEditingTextAttributes],
		      "and the cell's attributed-editing flag, so the door is the one that carries it");
		[bare release];
		[cell release];
	}

	[field release];
	[content release];
	[window release];
	[pool release];
	printf("text_field_attributes: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
