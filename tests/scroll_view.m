/*
 * scroll_view — the frame that joins a document, a clip view and two scrollers.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed. SPDX-License-Identifier: MIT
 *
 * **THIS IS THE CLASS THAT MAKES THE OTHER TWO USEFUL, SO WHAT IT IS TESTED ON IS THE JOINING.** A clip view scrolls
 * and a scroller reports; neither knows about the other, and this class is the only thing that turns one into the
 * other. So the cases below are the LAYOUT (`-tile` and the two size conversions that must agree with it) and the
 * LOOP (a scroller's action moves the clip view; a moved clip view moves the scrollers), plus the one door on
 * `NSView` that could not be written while this class did not exist.
 *
 * WHAT IS ASSERTED:
 *
 *   1. A scroll view makes a CONTENT VIEW that is an `NSClipView`, and it is a subview.
 *   2. The two class conversions are EXACT INVERSES of each other and agree with `-tile`.
 *   3. `-tile` puts a 15-point scroller down the right and along the bottom and shrinks the content by exactly that.
 *   4. A document goes in through the scroll view and lands in the clip view.
 *   5. `-reflectScrolledClipView:` sets the knob's SIZE from the visible fraction and its PLACE from how far the
 *      clip view has scrolled — read from the clip view, not remembered.
 *   6. A scroller's action moves the clip view: a knob to the value's own place, a page by the visible extent, a line
 *      by `-lineScroll`.
 *   7. `NSView -enclosingScrollView` finds this class from inside it.
 *
 * Offscreen: no window and no compositor. A scroll view is a view with three subviews and an arithmetic between
 * them, which is exactly what a probe can hold.
 */
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSScrollerCell.h>
#import <AppKit/NSView.h>

#include <math.h>
#include <stdio.h>

/* THE SCROLLER'S ACTION IS PRIVATE, AND THE PROBE HAS TO BE ABLE TO SEND IT.** A scroller's action is what a real
 * click sends; without a run loop the probe cannot make the press and the message happen on their own, so it names
 * the selector the scroll view installed and calls it the way `-sendAction:` would. */
@interface NSScrollView (AGScrollProbe)
- (void)cg_scrollerAction:(id)sender;
@end

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static int near(double a, double b)
{
	return fabs(a - b) < 0.01;
}

static int eqr(NSRect a, NSRect b)
{
	return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) &&
	       near(a.size.width, b.size.width) && near(a.size.height, b.size.height);
}

static void note_rect(const char *what, NSRect r)
{
	printf("  (note: %s = (%.1f, %.1f) %.1f x %.1f)\n", what,
	       (double)r.origin.x, (double)r.origin.y, (double)r.size.width, (double)r.size.height);
}

/* PUT THE SCROLLER'S PART AND VALUE WHERE A DRAG WOULD HAVE LEFT THEM, without a run loop: the cell's own tracking
 * hook is what sets `-hitPart`, and `-setFloatValue:` is what a drag writes. */
static void aim_scroller(NSScroller *sc, NSPoint press, CGFloat value)
{
	NSScrollerCell *cell = (NSScrollerCell *)[sc cell];

	[cell startTrackingAt:press inView:sc];
	[sc setFloatValue:value knobProportion:[sc knobProportion]];
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	@autoreleasepool {
		NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
		NSClipView *clip = (NSClipView *)[sv contentView];

		/* 1. THE CONTENT VIEW. */
		check([clip isKindOfClass:[NSClipView class]], "a scroll view makes a CONTENT VIEW that is an NSClipView");
		check([clip superview] == sv, "and it is the scroll view's own subview");
		check(eqr([clip frame], NSMakeRect(0.0, 0.0, 200.0, 200.0)),
		      "with no scrollers and no border the content is the whole frame");

		/* 2. **THE TWO CONVERSIONS, WHICH MUST BE INVERSES AND MUST AGREE WITH `-tile`.** */
		{
			NSSize f = [NSScrollView frameSizeForContentSize:NSMakeSize(100.0, 100.0)
							  hasHorizontalScroller:YES
							    hasVerticalScroller:YES
								    borderType:NSNoBorder];
			NSSize c = [NSScrollView contentSizeForFrameSize:f
							  hasHorizontalScroller:YES
							    hasVerticalScroller:YES
								    borderType:NSNoBorder];

			printf("  (note: content 100x100 with both scrollers and no border is a frame of %.0fx%.0f)\n",
			       (double)f.width, (double)f.height);
			check(near(f.width, 115.0) && near(f.height, 115.0),
			      "a 100x100 content with two 15-point scrollers is a 115x115 frame");
			check(near(c.width, 100.0) && near(c.height, 100.0),
			      "and `-contentSizeForFrameSize:` is its exact inverse");
		}
		{
			NSSize f = [NSScrollView frameSizeForContentSize:NSMakeSize(100.0, 100.0)
							  hasHorizontalScroller:NO
							    hasVerticalScroller:YES
								    borderType:NSLineBorder];

			check(near(f.width, 117.0) && near(f.height, 102.0),
			      "a 1-point border adds two points to each side of the conversion");
		}

		/* 3. **THE LAYOUT.** Both scrollers on a 200x200 frame: 15 to the right, 15 along the bottom, and the
		 * content is what is left over. */
		[sv setHasVerticalScroller:YES];
		[sv setHasHorizontalScroller:YES];
		check([sv hasVerticalScroller] && [sv hasHorizontalScroller],
		      "`-setHasVerticalScroller:`/`-setHasHorizontalScroller:` report the bars they made");
		check([sv verticalScroller] != nil && [sv horizontalScroller] != nil, "and both scrollers exist");
		note_rect("content", [clip frame]);
		note_rect("vertical scroller", [[sv verticalScroller] frame]);
		note_rect("horizontal scroller", [[sv horizontalScroller] frame]);
		check(eqr([clip frame], NSMakeRect(0.0, 15.0, 185.0, 185.0)),
		      "the content is the frame less a scroller on the right and one along the bottom");
		check(eqr([[sv verticalScroller] frame], NSMakeRect(185.0, 15.0, 15.0, 185.0)),
		      "the vertical scroller runs down the right, above the horizontal one");
		check(eqr([[sv horizontalScroller] frame], NSMakeRect(0.0, 0.0, 185.0, 15.0)),
		      "and the horizontal one runs along the bottom, to the left of the vertical one");
		check(near([sv contentSize].width, 185.0) && near([sv contentSize].height, 185.0),
		      "and `-contentSize` reports the content view's own size");

		/* 4. **THE DOCUMENT, THROUGH THE SCROLL VIEW.** */
		{
			NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 185.0, 400.0)];

			[sv setDocumentView:doc];
			check([sv documentView] == doc, "a document set on the scroll view is answered back");
			check([doc superview] == clip, "and it lands in the CLIP VIEW, which is the content view");
			check(near([sv verticalScroller].knobProportion, 185.0 / 400.0),
			      "and the knob's size is the visible fraction of the document, set on arrival");

			/* 5. **THE SCROLLER CATCHES UP WHEN THE CLIP VIEW MOVES.** Scroll to the bottom and the value must be 1
			 * — read from the clip view rather than remembered by the scroller. */
			[clip scrollToPoint:NSMakePoint(0.0, 10000.0)];
			printf("  (note: scrolled to the bottom, the clip origin is %.1f and the knob value %.4f)\n",
			       (double)[clip bounds].origin.y, (double)[[sv verticalScroller] floatValue]);
			check(near([clip bounds].origin.y, 215.0),
			      "the clip view stops at the document's height less its own (400-185)");
			check(near([[sv verticalScroller] floatValue], 1.0),
			      "and `-reflectScrolledClipView:` has put the knob at 1, its far end");
			[clip scrollToPoint:NSMakePoint(0.0, 0.0)];
			check(near([[sv verticalScroller] floatValue], 0.0), "and back at the top the knob reads 0");

			/* 6. **AND THE OTHER DIRECTION: THE SCROLLER'S ACTION MOVES THE CLIP VIEW.** A knob at 1 goes to the far
			 * end; a page moves by the visible extent; a line by `-lineScroll`. */
			{
				NSScroller *v = [sv verticalScroller];

				aim_scroller(v, NSMakePoint(7.0, 40.0), 1.0);	/* a press on the knob, dragged to the end */
				[sv cg_scrollerAction:v];
				printf("  (note: the knob's action left the clip origin at %.1f)\n",
				       (double)[clip bounds].origin.y);
				check(near([clip bounds].origin.y, 215.0),
				      "a knob at 1 scrolls the clip view to the document's far end");
			}
			[clip scrollToPoint:NSMakePoint(0.0, 0.0)];
			{
				NSScroller *v = [sv verticalScroller];

				[sv setLineScroll:10.0];
				[sv setPageScroll:0.0];		/* 0 means "page by the visible extent" */
				aim_scroller(v, NSMakePoint(7.0, 120.0), 0.0);	/* a press BELOW the knob is the increment page */
				[sv cg_scrollerAction:v];
				printf("  (note: the page action left the clip origin at %.1f, against 185-10)\n",
				       (double)[clip bounds].origin.y);
				check(near([clip bounds].origin.y, 175.0),
				      "an increment page moves by the visible extent less one line (185-10)");

				[clip scrollToPoint:NSMakePoint(0.0, 100.0)];
				aim_scroller(v, NSMakePoint(7.0, 7.0), 0.0);	/* a press in the TOP button */
				[sv cg_scrollerAction:v];
				check(near([clip bounds].origin.y, 90.0), "a decrement line moves back by `-lineScroll`");
			}

			/* 7. **AND THE DOOR THAT COULD NOT EXIST BEFORE THIS CLASS.** */
			check([doc enclosingScrollView] == sv,
			      "`-enclosingScrollView` finds the scroll view from the document inside it");
			check([clip enclosingScrollView] == sv, "and from the clip view too");
			[doc release];
		}

		/* AND TAKING A SCROLLER AWAY GIVES THE CONTENT ITS ROOM BACK. */
		[sv setHasVerticalScroller:NO];
		[sv setHasHorizontalScroller:NO];
		check([sv verticalScroller] == nil && [sv horizontalScroller] == nil,
		      "taking the bars away answers no scroller");
		check(eqr([clip frame], NSMakeRect(0.0, 0.0, 200.0, 200.0)),
		      "and gives the content the whole frame again");

		[sv release];
		printf("scroll_view: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
