/*
 * clip_view — the CLIP VIEW's arithmetic, in exact points, and the wire that re-runs it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THIS IS THE INSIDE OF A SCROLL VIEW, AND IT IS THE HALF THAT CAN BE CHECKED WITHOUT ONE.** `NSClipView.h` says
 * the arithmetic "is the whole of it" and that a clip view without an `NSScrollView` is "still useful and still
 * testable" — and this is that test. Every claim here is a NUMBER: where a SHORT document sits (centred, not
 * pinned), where a LONG one stops (the far edge, and never blank space), what `-documentVisibleRect` answers in the
 * DOCUMENT's coordinates, and what a scroll request becomes once `-constrainScrollPoint:` has had it.
 *
 * **AND THE SECOND HALF IS A WIRE, WHICH IS WHY THIS PROBE EXISTS AT ALL.** The header says the two change handlers
 * "re-constrain the scroll so a document that SHRANK pulls the visible area back with it" — a promise about the
 * DEFAULT notification centre, because it is `NSView -setFrame:` and `-setBoundsOrigin:` that ANNOUNCE the change
 * while the clip view is the one that must be LISTENING. So this drives a document's frame and asks whether the
 * visible area moved with it. IT DID NOT when this test was written: `-viewFrameChanged:` and `-viewBoundsChanged:`
 * were doors nothing ever knocked on, since no one had registered the clip view for the document's own
 * notifications. Registering in `-setDocumentView:` is the fix, and these cases are what hold it — including that a
 * REPLACED document stops being watched.
 *
 * The file also pins the four defaults a caller reads before touching anything: flipped, drawing its background,
 * copying on scroll, and holding no document at all.
 *
 * Everything is offscreen. No window, no compositor and no run loop: a clip view is a view, and its scrolling is
 * arithmetic over `bounds` and the document's frame — which is exactly the point `NSClipView.h` makes.
 */
#import <AppKit/NSClipView.h>
#import <AppKit/NSView.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>
#import <Foundation/NSArray.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int eqp(NSPoint a, NSPoint b)
{
	return a.x == b.x && a.y == b.y;
}

static int eqr(NSRect a, NSRect b)
{
	return a.origin.x == b.origin.x && a.origin.y == b.origin.y &&
	       a.size.width == b.size.width && a.size.height == b.size.height;
}

static void note_pt(const char *what, NSPoint p)
{
	printf("  (note: %s = (%.1f, %.1f))\n", what, (double)p.x, (double)p.y);
}

static void note_rect(const char *what, NSRect r)
{
	printf("  (note: %s = (%.1f, %.1f) %.1f x %.1f)\n", what,
	       (double)r.origin.x, (double)r.origin.y, (double)r.size.width, (double)r.size.height);
}

/* **THE SUPERVIEW THAT REMEMBERS BEING TOLD.** `-scrollToPoint:` ends by announcing the scroll to whatever holds the
 * clip view — that is Apple's contract and what lets a scroller redraw its knob — so the only way to see the
 * announcement is to be the holder. It counts the calls and keeps the origin a scroller would draw from. */
@interface AGClipRecorder : NSView
{
@public
	int reflects;
	NSPoint lastPoint;
}
@end

@implementation AGClipRecorder
- (void)reflectScrolledClipView:(NSClipView *)aClipView
{
	reflects++;
	lastPoint = [aClipView bounds].origin;
}
@end

static NSClipView *clip100(void)
{
	return [[NSClipView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {

	/* 1. THE DEFAULTS, READ BEFORE ANYTHING IS DONE. */
	{
		NSClipView *c = clip100();

		check([c isFlipped],
		      "a clip view is FLIPPED, so a scroll origin reads as \"how far down\"");
		check([c drawsBackground], "and it draws its background unless told not to");
		check([c copiesOnScroll], "and it copies on scroll, which is the flag's default");
		check([c documentView] == nil, "a clip view with no document answers no document");
		check(eqr([c documentRect], NSZeroRect), "and its document rect is EMPTY rather than invented");
		check(eqr([c documentVisibleRect], NSZeroRect), "and so is its visible rect");
		[c release];
	}

	/* 2. **THE DOCUMENT RECT, WHICH IS WHERE THE FLIP IS VISIBLE.** A flipped clip view works in the document's
	 * own frame; a non-flipped one has to include the region BELOW a short document, because that is what a scroll
	 * there would show. One document, two answers, and the flip is the only difference. */
	{
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(10.0, 10.0, 40.0, 40.0)];
		NSClipView *c = clip100();

		[c setDocumentView:doc];
		note_rect("flipped documentRect", [c documentRect]);
		check(eqr([c documentRect], NSMakeRect(10.0, 10.0, 40.0, 40.0)),
		      "a FLIPPED clip view's document rect is the document's own frame");
		[c setFlipped:NO];
		note_rect("non-flipped documentRect", [c documentRect]);
		check(eqr([c documentRect], NSMakeRect(0.0, 0.0, 100.0, 100.0)),
		      "and a NON-flipped one unions it with its own bounds — the area below a short document");
		[c release];
		[doc release];
	}

	/* 3. **THE CONSTRAINT, WHICH IS THREE CASES AND NOT ONE.** Long: clamped to both ends. Short: centred. Exactly
	 * equal: centred too, which is the `<=` in the class and the case a `<` would get wrong. */
	{
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSClipView *c = clip100();

		[c setDocumentView:doc];
		check(eqp([c constrainScrollPoint:NSMakePoint(50.0, 60.0)], NSMakePoint(50.0, 60.0)),
		      "a scroll inside a LONG document is left where it was asked for");
		check(eqp([c constrainScrollPoint:NSMakePoint(-50.0, -50.0)], NSMakePoint(0.0, 0.0)),
		      "a scroll before the start is pulled back to it");
		check(eqp([c constrainScrollPoint:NSMakePoint(1000.0, 1000.0)], NSMakePoint(200.0, 100.0)),
		      "and a scroll past the end stops at the far edge — 300-100 by 200-100");
		[c release];
		[doc release];
	}
	{
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0)];
		NSClipView *c = clip100();

		[c setDocumentView:doc];
		note_pt("short document, asked for (0,0)", [c constrainScrollPoint:NSMakePoint(0.0, 0.0)]);
		check(eqp([c constrainScrollPoint:NSMakePoint(0.0, 0.0)], NSMakePoint(-30.0, -30.0)),
		      "a document SHORTER than the clip view is CENTRED: -30 is half of 100-40, left and above");
		check(eqp([c constrainScrollPoint:NSMakePoint(500.0, 500.0)], NSMakePoint(-30.0, -30.0)),
		      "and asking to scroll it does not move it off the centre");
		[c release];
		[doc release];
	}
	{
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
		NSClipView *c = clip100();

		[c setDocumentView:doc];
		check(eqp([c constrainScrollPoint:NSMakePoint(50.0, 50.0)], NSMakePoint(0.0, 0.0)),
		      "a document EXACTLY the clip view's size is centred too — the test is `<=`, not `<`");
		[c release];
		[doc release];
	}

	/* 4. **THE DOOR A CALLER USES.** `-scrollToPoint:` constrains FIRST — which is why a scroll past the end is not
	 * a way to see blank space — and `-documentVisibleRect` is the same fact asked in the DOCUMENT's coordinates. */
	{
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSClipView *c = clip100();

		[c setDocumentView:doc];
		[c scrollToPoint:NSMakePoint(1000.0, 1000.0)];
		note_pt("after scrollToPoint(1000,1000)", [c bounds].origin);
		check(eqp([c bounds].origin, NSMakePoint(200.0, 100.0)),
		      "`-scrollToPoint:` CONSTRAINS FIRST, so a scroll past the end lands on the far edge");
		check(eqr([c documentVisibleRect], NSMakeRect(200.0, 100.0, 100.0, 100.0)),
		      "and the visible rect is the bounds shifted by the document's origin, in the DOCUMENT's coordinates");
		[c scrollToPoint:NSMakePoint(-5.0, -5.0)];
		check(eqp([c bounds].origin, NSMakePoint(0.0, 0.0)),
		      "and a scroll before the start lands on it");
		[c release];
		[doc release];
	}

	/* 5. **AND THE ANNOUNCEMENT.** A scroll is not private: the enclosing view is told, which is the half a
	 * scroller's knob is drawn from. The default `NSView` answer does nothing, so the holder here is what makes the
	 * call observable. */
	{
		AGClipRecorder *holder = [[AGClipRecorder alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSClipView *c = clip100();

		[holder addSubview:c];
		[c setDocumentView:doc];
		[c scrollToPoint:NSMakePoint(40.0, 30.0)];
		check(holder->reflects > 0 && eqp(holder->lastPoint, NSMakePoint(40.0, 30.0)),
		      "a scroll TELLS THE ENCLOSING VIEW, with the origin it landed on");
		[c release];
		[doc release];
		[holder release];
	}

	/* 6. **THE WIRE: A DOCUMENT THAT SHRANK PULLS THE VISIBLE AREA BACK WITH IT.** This is the case that failed
	 * before `-setDocumentView:` registered for the document's own notifications. `-setFrame:` is what announces the
	 * change, and nothing in the clip view is called by hand. */
	{
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSClipView *c = clip100();

		[c setDocumentView:doc];
		[c scrollToPoint:NSMakePoint(200.0, 100.0)];
		check(eqp([c bounds].origin, NSMakePoint(200.0, 100.0)),
		      "a long document scrolls to its far edge");
		[doc setFrame:NSMakeRect(0.0, 0.0, 40.0, 40.0)];	/* the document SHRANK */
		note_pt("after the document shrank", [c bounds].origin);
		check(eqp([c bounds].origin, NSMakePoint(-30.0, -30.0)),
		      "and a document that SHRANK pulls the visible area back to CENTRE it — the frame-changed wire");
		[c release];
		[doc release];
	}

	/* 7. **AND THE OTHER ANNOUNCEMENT, WHICH IS THE SAME PROBLEM FROM THE DOCUMENT'S SIDE.** A bounds change on the
	 * document must re-ask the visible origin; the origin here does not move, so the OBSERVABLE is the announcement
	 * the clip view makes onward. */
	{
		AGClipRecorder *holder = [[AGClipRecorder alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSClipView *c = clip100();

		[holder addSubview:c];
		[c setDocumentView:doc];
		holder->reflects = 0;
		[doc setBoundsOrigin:NSMakePoint(5.0, 5.0)];	/* the document's own bounds moved */
		check(holder->reflects > 0,
		      "a BOUNDS change on the document re-constrains too — the bound edge visible in this state");
		[c release];
		[doc release];
		[holder release];
	}

	/* 8. **THE EDGE, WHICH IS WHAT AUTOSCROLL IS FOR.** A drag inside the visible rect is not a reason to scroll at
	 * all; a drag past an edge steps 16 points toward it and SAYS it did. */
	{
		NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSClipView *c = clip100();

		[c setDocumentView:doc];
		{
			NSEvent *inside = [NSEvent mouseEventWithType:NSLeftMouseDragged
					location:NSMakePoint(50.0, 50.0) modifierFlags:0 timestamp:0 windowNumber:0
					context:nil eventNumber:0 clickCount:1 pressure:1.0];
			check(![c autoscroll:inside], "a drag INSIDE the visible rect does not scroll");
		}
		{
			NSEvent *past = [NSEvent mouseEventWithType:NSLeftMouseDragged
					location:NSMakePoint(150.0, 50.0) modifierFlags:0 timestamp:0 windowNumber:0
					context:nil eventNumber:0 clickCount:1 pressure:1.0];
			BOOL moved = [c autoscroll:past];

			note_pt("after autoscroll past the right edge", [c bounds].origin);
			check(moved && eqp([c bounds].origin, NSMakePoint(16.0, 0.0)),
			      "but a drag past an edge steps 16 points toward it, and says it moved");
		}
		[c release];
		[doc release];
	}
	{
		NSClipView *c = clip100();
		NSEvent *e = [NSEvent mouseEventWithType:NSLeftMouseDragged
				location:NSMakePoint(150.0, 50.0) modifierFlags:0 timestamp:0 windowNumber:0
				context:nil eventNumber:0 clickCount:1 pressure:1.0];

		check(![c autoscroll:e], "and a clip view with NO document does not autoscroll at all");
		[c release];
	}

	/* 9. **AND REPLACING THE DOCUMENT REPLACES THE WATCH.** A new document is added and the old one leaves the tree
	 * — and, with the wire above, the old one must stop moving the clip view when its frame changes. */
	{
		NSView *first = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
		NSView *second = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];
		NSClipView *c = clip100();

		[c setDocumentView:first];
		[c setDocumentView:second];
		check([c documentView] == second, "setting a new document view takes effect");
		check([first superview] == nil, "and the replaced view leaves the tree");
		check([[c subviews] count] == 1 && [[c subviews] objectAtIndex:0] == second,
		      "so the clip view holds exactly the document it names");
		[c scrollToPoint:NSMakePoint(200.0, 100.0)];
		[first setFrame:NSMakeRect(0.0, 0.0, 5.0, 5.0)];
		check(eqp([c bounds].origin, NSMakePoint(200.0, 100.0)),
		      "and the REPLACED document is no longer watched — its frame change moves nothing");

		[c setDocumentView:nil];
		check([c documentView] == nil, "and setting nil is a document view of none");
		check(eqr([c documentRect], NSZeroRect), "with an empty document rect");
		[c release];
		[first release];
		[second release];
	}

	/* 10. **A CLIP VIEW WITH NO DOCUMENT IS NOT "A DOCUMENT THAT FITS".** The centring rule is about a document
	 * SMALLER than the clip view, and with no document at all there is no such comparison to make: the extent is
	 * empty, and `-(100 - 0)/2` is a real number that means nothing. MEASURED as a bug one class up: a scroll view
	 * given its bars before its document was left with an origin of (-30, -30) in a 100-point clip, so the first line
	 * scroll clamped to 0 instead of stepping — a scroll that visibly did nothing. The two claims below are the pair
	 * that closes it: the constraint leaves a document-less origin ALONE, and a document arriving is measured against
	 * the origin the clip already has rather than adopting a number computed for nothing. */
	{
		NSClipView *c = clip100();

		check(eqp([c constrainScrollPoint:NSMakePoint(0.0, 0.0)], NSMakePoint(0.0, 0.0)),
		      "a clip view with NO document leaves (0, 0) at (0, 0) rather than centring an empty extent");
		check(eqp([c constrainScrollPoint:NSMakePoint(20.0, 20.0)], NSMakePoint(20.0, 20.0)),
		      "and leaves any other asked-for origin alone too — there is nothing to constrain against");
		{
			NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 200.0)];

			[c setDocumentView:doc];
			check(eqp([c bounds].origin, NSMakePoint(0.0, 0.0)),
			      "and a long document arriving leaves the origin at the start, where the scroll belongs");
			[doc release];
		}
		[c release];
	}

		printf("clip_view: %d case(s) failed\n", s_failed);
	}
	return s_failed == 0 ? 0 : 1;
}
