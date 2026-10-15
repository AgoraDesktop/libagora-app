/*
 * text_field_cell.m — A FIELD'S STRING, ITS FACE, AND ONE EDIT SESSION FROM BEGINNING TO END.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * **AN EDIT IS THREE DOORS AND A ROUND TRIP, SO THAT IS WHAT THIS PROBE DRIVES.** A window lends an editor, a cell is
 * told to begin a session with it, and the cell takes the string back when the session ends — and the claim worth
 * making is that the value a person types is the value the cell holds afterwards, with the editor gone from the view
 * it was lent to. Nothing here needs an event loop or a display: every step is a call the probe makes itself, which is
 * what makes a text field testable offscreen.
 *
 * **AND THE SESSION IS DRIVEN THROUGH THE REAL PRIMITIVE.** The string is not assigned — it is EDITED, with
 * `-replaceCharactersInRange:withString:`, because that is the operation every keystroke is spelled in and a probe
 * that set the string directly would pass on a cell that could not be typed into.
 */
#import <AppKit/NSTextFieldCell.h>
#import <AppKit/NSComboBoxCell.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSAutoreleasePool.h>
#include <math.h>
#include <stdio.h>

static int failures = 0;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* A DELEGATE THAT ONLY WANTS TO KNOW, which is the half of the protocol a control uses. */
@interface Watcher : NSObject
{
@public
	int ended;
}
@end

@implementation Watcher
- (void)textDidEndEditing:(NSNotification *)note
{
	(void)note;
	ended++;
}
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 100.0)
						       styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
	NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 100.0)];
	NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@"hello"];
	NSComboBoxCell *combo = [[NSComboBoxCell alloc] initTextCell:@"a value"];
	NSText *editor;
	NSText *again;
	Watcher *watcher = [[Watcher alloc] init];
	NSRect frame = NSMakeRect(10.0, 40.0, 120.0, 23.0);

	[window setContentView:content];
	[cell setBordered:YES];
	[cell setBezeled:YES];

	/* 1. **THE WINDOW LENDS ONE EDITOR, AND ONLY MAKES ONE.** */
	editor = (NSText *)[window fieldEditor:YES forObject:cell];
	again = (NSText *)[window fieldEditor:YES forObject:combo];
	check(editor != nil, "the window lends an editor, which it did not before this slice");
	check(editor == again, "and lends the SAME one to a second field — one editor per window, Apple's own rule");
	check([window fieldEditor:NO forObject:cell] == editor, "and answers it without making one when asked not to");

	/* 2. **BEGINNING A SESSION PUTS IT IN THE VIEW, AT THE FIELD'S OWN TEXT RECT.** */
	[cell selectWithFrame:frame inView:content editor:editor delegate:watcher start:0 length:5];
	check([editor superview] == content, "a session puts the editor in the view being edited");
	check([editor string] != nil && [[editor string] isEqualToString:@"hello"],
	      "with the cell's string in it, so the field shows what it holds the moment it is clicked into");
	check([editor delegate] == (id)cell,
	      "and the CELL is the editor's delegate — it owns the string, so reading it back is its job");
	check(fabs(NSMinX([editor frame]) - NSMinX([cell drawingRectForBounds:frame])) < 0.01
	      && fabs(NSWidth([editor frame]) - NSWidth([cell drawingRectForBounds:frame])) < 0.01,
	      "and its frame IS the cell's text rect, so an editor and a drawn string agree about where the words live");
	check([editor isFieldEditor], "and the editor knows it is one, which is what a window's own editor is");
	/* **AND IT DRAWS NO BACKGROUND OF ITS OWN, WHICH IS THE GREY BOX THAT WAS SEEN IN THE DEMONSTRATION.** An editor
	 * that paints a fill paints a rectangle the size of this text rect — inset from the border, stopping at a chip — and
	 * the colour it was handed DEPENDED ON THE POINTER, so clicking into a white field produced a grey box inside it.
	 * The cell draws the face and the editor draws the words; nothing draws both. */
	check(![editor drawsBackground],
	      "the editor paints NO fill — the cell's face is the only fill, so an editor cannot box it in");

	/* 3. **TYPING EDITS THE STRING THROUGH THE ONE PRIMITIVE EVERY KEYSTROKE USES.** */
	[editor setSelectedRange:NSMakeRange(0, 5)];
	[editor replaceCharactersInRange:[editor selectedRange] withString:@"typed"];
	check([[editor string] isEqualToString:@"typed"], "the edit lands in the editor's string");

	/* 4. **AND ENDING THE SESSION TAKES IT BACK INTO THE CELL.** */
	[cell endEditing:editor];
	printf("  (note: the cell holds \"%s\" and the watcher heard %d end)\n",
	       [[cell stringValue] UTF8String], watcher->ended);
	check([[cell stringValue] isEqualToString:@"typed"],
	      "ending the session puts what was typed into the CELL — the round trip, which is the whole point");
	check([editor superview] == nil, "and the editor leaves the view, because it is the window's and goes back");
	check([editor delegate] == nil, "and stops being the cell's delegate, so a stale editor cannot report to it");
	check(watcher->ended == 1, "and the caller's own delegate is told the session ended, once");

	/* 5. **AND A COMBO BOX'S TEXT STOPS AT ITS CHIP, WHICH IS THE ONE RECT THAT IS ITS OWN.** The same override is what
	 * an edit session is handed, so a typed string cannot be drawn — or typed — under the chip. */
	{
		NSRect r = [combo drawingRectForBounds:frame];
		NSRect plain = [cell drawingRectForBounds:frame];
		/* THE CHIP'S RECT IS COMPUTED FROM THE SHARED MEASURES rather than asked for: it is
		 * `NSCell.h`'s five numbers that place it, and a probe that asked the cell would be checking the cell's
		 * arithmetic against itself. This is the same expression `-cg_chipRectInFrame:` is. */
		CGFloat side = NSHeight(frame) * NS_CELL_CHIP_FRACTION;
		CGFloat inset = NSHeight(frame) * NS_CELL_CHIP_INSET_FRACTION;
		NSRect chip = NSMakeRect(NSMaxX(frame) - inset - side, NSMidY(frame) - side / 2.0, side, side);

		printf("  (note: a field's text runs to x=%.1f; a combo box's stops at %.1f, with its chip at %.1f)\n",
		       (double)NSMaxX(plain), (double)NSMaxX(r), (double)NSMinX(chip));
		check(fabs(NSMinX(r) - NSMinX(plain)) < 0.01,
		      "a combo box begins its words at the same margin the field beside it does");
		check(NSMaxX(r) <= NSMinX(chip) + 0.01,
		      "and stops them where its chip begins, so the chip is never under them");
	}

	/* 6. **AND A FIELD'S STRING LIVES WHERE A FORMATTER CAN SEE IT.** `NSCell` keeps a `-_title` and an `-_objectValue`
	 * — two doors onto what a caller thinks is one thing — and this class puts the string it was made with in the second
	 * one, because that is the one `-stringValue` reads and the one a formatter is handed. MEASURED: without that, a
	 * cell made with `-initTextCell:@"hello"` drew nothing at all. */
	{
		NSTextFieldCell *fresh = [[NSTextFieldCell alloc] initTextCell:@"made with a string"];

		check([[fresh stringValue] isEqualToString:@"made with a string"],
		      "a cell made with a string answers it from the door a formatter reads");
		[fresh release];
	}

	[watcher release];
	[combo release];
	[cell release];
	[content release];
	[window release];
	[pool release];
	printf("text_field_cell: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
