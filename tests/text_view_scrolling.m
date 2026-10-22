/*
 * text_view_scrolling.m — A TEXT VIEW IN A SCROLL VIEW: THE DOORS, AND WHAT MOVES.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **SLICE III IS TWO DOORS ON `NSView` AND ONE ON THE TEXT VIEW, AND THIS CHECKS ALL THREE AGAINST A REAL CLIP VIEW.**
 * `-scrollRectToVisible:` finds the closest enclosing clip view, works in ITS coordinates and moves the origin just
 * far enough; `-scrollPoint:` puts the origin where a caller says; and `NSTextView -scrollRangeToVisible:` turns a
 * caret into the rectangle those two take. What is measured is the CLIP VIEW'S OWN `bounds` origin, which is the one
 * fact that says a scroll happened.
 *
 * **AND THE HEIGHT IS PART OF IT RATHER THAN A FOOTNOTE.** A clip view can only scroll a document that is TALLER than
 * it, so the text view settles its own height after every edit (`-isVerticallyResizable`, YES by default) — and a
 * view whose caller owns the frame says NO and keeps it.
 *
 * **AND THE DOCUMENT'S ORIENTATION IS PART OF IT RATHER THAN AN AFTERTHOUGHT.** A text view is FLIPPED, so its FIRST
 * line sits at the clip view's origin and the origin grows as a reader moves DOWN the document — which is what makes
 * a scroller's knob mean what it looks like it means. That is checked here, because it is the one claim the doors
 * cannot make on their own.
 */
#import <AppKit/NSTextView.h>
#import <AppKit/NSText.h>
#import <AppKit/NSView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static int failures;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok   " : "FAIL ", what);
	if (!ok) {
		failures++;
	}
}

/* **IS THE RECTANGLE INSIDE THE CLIP VIEW'S VISIBLE RECTANGLE, ASKED IN THE CLIP VIEW'S OWN COORDINATES** — which is
 * the same space `-bounds` is in, and so the same space the arithmetic under test works in. */
static int visible(NSView *view, NSClipView *clip, NSRect r)
{
	return NSContainsRect([clip bounds], [view convertRect:r toView:clip]);
}

/* A DOCUMENT OF `n` LINES, each short enough not to wrap at the width below. */
static NSString *lines(NSUInteger n)
{
	NSMutableString *s = [NSMutableString string];

	while (n-- > 0) {
		[s appendFormat:@"line %lu\n", (unsigned long)n];
	}
	return s;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 180.0, 60.0)];
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 180.0, 60.0)];
	NSClipView *clip;
	NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	CGFloat lineHeight = [font ascender] - [font descender];
	CGFloat height;

	setvbuf(stdout, NULL, _IONBF, 0);
	[scroll setDocumentView:view];
	clip = (NSClipView *)[scroll contentView];
	check(clip != nil, "a scroll view has a clip view to scroll with");

	/* 1. **AND THE TEXT VIEW SETTLES ITS OWN HEIGHT, WHICH IS WHAT GIVES THE CLIP VIEW SOMETHING TO SCROLL.** */
	[view setString:lines(20)];
	height = [view frame].size.height;
	printf("  (note: twenty lines measure %.1f points in a 60-point clip view)\n", (double)height);
	check(height > 60.0, "a twenty-line document is TALLER than the clip view holding it");
	check([view isVerticallyResizable], "which it got by being vertically resizable — the default");

	/* 2. **AND A CALLER THAT OWNS THE FRAME KEEPS IT.** The flag is what a field or a label laid out by hand says. */
	{
		NSTextView *fixed = [[NSTextView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 180.0, 60.0)];

		[fixed setVerticallyResizable:NO];
		[fixed setString:lines(20)];
		check([fixed frame].size.height == 60.0, "a view with the flag OFF keeps the frame its caller gave it");
		[fixed release];
	}

	/* 3. **AND THE DOCUMENT READS FROM THE TOP, WHICH IS WHAT THE FLIP IS FOR.** A text view is FLIPPED, so line 0 is
	 * at the clip view's origin: with the origin at 0 the FIRST line is on screen, and moving the caret to the END
	 * scrolls the origin DOWN the document. Before the flip, origin 0 showed the document's LAST lines — a document
	 * scrolled upside down. */
	check([view isFlipped], "a text view is FLIPPED — its first line sits at the clip view's origin");
	[view scrollPoint:NSMakePoint(0.0, 0.0)];
	check(visible(view, clip, NSMakeRect(NS_TEXT_INSET, NS_TEXT_INSET, 1.0, lineHeight)),
	      "with the origin at 0 the FIRST line is visible");

	/* 4. **AND BRINGING A RECTANGLE INTO VIEW IS THE CLIP VIEW MOVING.** A rectangle near the document's FAR end in
	 * this class's own (y-up) coordinates is outside the visible rectangle at the origin and inside it afterwards —
	 * which is what "scrolled into view" means, and it is read as `-bounds`, not as a redraw. */
	{
		NSRect far = NSMakeRect(2.0, height - NS_TEXT_INSET - lineHeight, 1.0, lineHeight);
		NSPoint before = [clip bounds].origin;
		BOOL moved = [view scrollRectToVisible:far];

		printf("  (note: scrollRectToVisible moved the origin from %.1f to %.1f)\n",
		       (double)before.y, (double)[clip bounds].origin.y);
		check(moved, "`-scrollRectToVisible:` answers YES when it had to move");
		check(visible(view, clip, far), "and the rectangle it was given is inside the visible rectangle afterwards");
		check([view scrollRectToVisible:far] == NO,
		      "asking again for the SAME rectangle answers NO — it is already visible");
	}

	/* 5. **AND THE CARET IS BROUGHT INTO VIEW BY THE SAME DOOR.** `-setSelectedRange:` ends in
	 * `-scrollRangeToVisible:`, which turns the caret into a rectangle; a caret at the document's far end must end up
	 * visible, and that is an assertion about the clip view rather than about the selection. */
	{
		NSTextView *t = view;
		NSUInteger n = [[t string] length];
		NSRect caret;

		[t scrollPoint:NSMakePoint(0.0, 0.0)];
		[t setSelectedRange:NSMakeRange(n - 1, 0)];
		printf("  (note: a caret at the end of the document left the origin at %.1f)\n",
		       (double)[clip bounds].origin.y);
		/* THE CARET'S OWN RECTANGLE, built the way `-scrollRangeToVisible:` builds it: a point wide, on the visual line
		 * the caret is on. */
		{
			NSUInteger line = [t cg_visualLineIndexForCharacterIndex:n - 1];
			/* THE CARET'S OWN RECTANGLE, built the way `-scrollRangeToVisible:` builds it: a point wide, on the visual
			 * line the caret is on, in a FLIPPED view's y-down coordinates. */
			CGFloat baseline = NS_TEXT_INSET + [font ascender] + (CGFloat)line * lineHeight;

			caret = NSMakeRect(NS_TEXT_INSET, baseline - [font ascender], 1.0, lineHeight);
		}
		check(visible(t, clip, caret), "a caret moved to the end of the document is SCROLLED into view");
	}

	/* 6. **AND `-scrollPoint:` PUTS THE ORIGIN WHERE IT IS TOLD, WITHIN WHAT THERE IS.** It constrains rather than
	 * refusing, so a point past the end is the far edge and not blank space. */
	{
		CGFloat maxOrigin = [view frame].size.height - 60.0;

		[view scrollPoint:NSMakePoint(0.0, 30.0)];
		check([clip bounds].origin.y == 30.0, "`-scrollPoint:` moves the origin to the point it is given");
		[view scrollPoint:NSMakePoint(0.0, 100000.0)];
		printf("  (note: scrollPoint past the end left the origin at %.1f of a %.1f maximum)\n",
		       (double)[clip bounds].origin.y, (double)maxOrigin);
		check([clip bounds].origin.y == maxOrigin, "and a point past the end is CONSTRAINED to the far edge");
		check([clip bounds].origin.x == 0.0,
		      "with no horizontal origin at all — a wrapped document has nothing to scroll sideways");
	}

	/* 7. **AND A GROWING DOCUMENT GROWS THE ORIGIN'S RANGE WITH IT**, which is the auto-fit and the clip view's
	 * re-constrain meeting: the view is taller after an edit and the clip view can therefore scroll further. */
	{
		CGFloat before = [view frame].size.height;

		[view insertText:@"\nlast"];
		printf("  (note: an edit took the document from %.1f to %.1f points)\n",
		       (double)before, (double)[view frame].size.height);
		check([view frame].size.height > before, "an edit that adds a line makes the document taller");
	}

	[scroll release];
	[view release];
	[pool release];
	printf("text_view_scrolling: %d case(s) failed\n", failures);
	return failures == 0 ? 0 : 1;
}
