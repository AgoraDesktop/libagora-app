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
#import <AppKit/NSCursor.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>

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

/* A DOCUMENT THAT MARKS ONE PLACE IN ITS OWN COORDINATES, so a scroll can be read as the mark MOVING. It is flipped
 * to match the clip view it goes into, which keeps the mark's arithmetic out of the flip's way. */
@interface AGScrollMarker : NSView
@end

@implementation AGScrollMarker
- (BOOL)isFlipped
{
	return YES;
}
- (void)drawRect:(NSRect)r
{
	(void)r;
	[[NSColor redColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 100.0, 185.0, 20.0)] fill];
}
@end

static NSBitmapImageRep *new_185(void)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:185 pixelsHigh:185
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:185 * 4 bitsPerPixel:32];
}

/* A RED PIXEL at a DRAWING y: the bitmap counts rows from the top and the drawing from its own origin. */
static int red_at(NSBitmapImageRep *rep, int x, int drawing_y)
{
	NSColor *c = [rep colorAtX:x y:(184 - drawing_y)];

	return c != nil && [c redComponent] > 0.8 && [c greenComponent] < 0.25 && [c blueComponent] < 0.25;
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

			/* 6b. **AND A CLICK IS ONE STEP, NOT TWO.** `NSControl -mouseDown:` sends a continuous cell's action on
			 * the PRESS and AGAIN on the point the button came up at — which is right for a slider, whose value is
			 * ABSOLUTE and therefore the same question twice, and WRONG for a page, which is a STEP: the press scrolled
			 * a page and the release scrolled another, so one click moved two pages. MEASURED, by driving the cell's own
			 * hooks the way the control loop does: the origin went to 215 (the document's end) instead of 175. The cell
			 * reports the part ONCE now — on the press — and the click below is what holds it. */
			[clip scrollToPoint:NSMakePoint(0.0, 0.0)];
			{
				NSScroller *v = [sv verticalScroller];
				NSScrollerCell *vc = (NSScrollerCell *)[v cell];

				[vc startTrackingAt:NSMakePoint(7.0, 120.0) inView:v];	/* press on the increment page */
				[sv cg_scrollerAction:v];
				check(near([clip bounds].origin.y, 175.0), "a page click steps once, ON THE PRESS");
				[vc continueTracking:NSMakePoint(7.0, 120.0) at:NSMakePoint(7.0, 120.0) inView:v];	/* the release */
				[sv cg_scrollerAction:v];
				printf("  (note: after the release the clip origin is still %.1f)\n", (double)[clip bounds].origin.y);
				check(near([clip bounds].origin.y, 175.0),
				      "and the RELEASE is not a second step — the action speaks twice, the page moves once");
			}

			/* 7. **AND THE DOOR THAT COULD NOT EXIST BEFORE THIS CLASS.** */
			check([doc enclosingScrollView] == sv,
			      "`-enclosingScrollView` finds the scroll view from the document inside it");
			check([clip enclosingScrollView] == sv, "and from the clip view too");
			[doc release];
		}

		/* 8. **AND THE WHOLE SLICE TOGETHER: A SCROLLED DOCUMENT IS DRAWN OFFSET.** The mark is at the document's
		 * own y 100..120; with the clip view at the top it draws at 100, and after a scroll of 100 the SAME mark draws
		 * at 0 — which is the one thing the arithmetic alone could not prove. */
		{
			AGScrollMarker *mark = [[AGScrollMarker alloc] initWithFrame:NSMakeRect(0.0, 0.0, 185.0, 400.0)];
			NSBitmapImageRep *rep = new_185();

			[sv setDocumentView:mark];
			[clip scrollToPoint:NSMakePoint(0.0, 0.0)];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 185.0, 185.0)] fill];
			[clip displayRect:[clip bounds]];
			check(red_at(rep, 90, 110),
			      "with the clip view at the top the document's mark is drawn where the document put it");
			[rep release];

			rep = new_185();
			[clip scrollToPoint:NSMakePoint(0.0, 100.0)];
			[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, 185.0, 185.0)] fill];
			[clip displayRect:[clip bounds]];
			check(red_at(rep, 90, 10), "and after scrolling 100 the SAME mark is drawn 100 points further up");
			check(!red_at(rep, 90, 110), "and not where it was, which is the offset being drawn and not just computed");
			[rep release];
			[mark release];
		}

		/* AND TAKING A SCROLLER AWAY GIVES THE CONTENT ITS ROOM BACK. */
		[sv setHasVerticalScroller:NO];
		[sv setHasHorizontalScroller:NO];
		check([sv verticalScroller] == nil && [sv horizontalScroller] == nil,
		      "taking the bars away answers no scroller");
		check(eqr([clip frame], NSMakeRect(0.0, 0.0, 200.0, 200.0)),
		      "and gives the content the whole frame again");

		/* 9. **THE BARS HIDE WHEN THE DOCUMENT FITS.** Autohide is a caller's choice (the default is Apple's NO),
		 * and the same scroll view is driven through a small document, one that needs only the horizontal bar and
		 * one that needs both. The bars still EXIST throughout; they are hidden, not removed. */
		{
			NSScrollView *autoView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
			NSView *autoDoc = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];

			check(![sv autohidesScrollers], "autohide is OFF by default, which is Apple's default");
			[autoView setHasVerticalScroller:YES];
			[autoView setHasHorizontalScroller:YES];
			[autoView setAutohidesScrollers:YES];
			[autoView setDocumentView:autoDoc];
			check([autoView autohidesScrollers] && [autoView hasVerticalScroller]
			      && [autoView hasHorizontalScroller],
			      "autohide keeps both bars CONFIGURED");
			check([[autoView verticalScroller] isHidden] && [[autoView horizontalScroller] isHidden],
			      "a document that fits hides both bars");
			check(near([autoView contentSize].width, 200.0) && near([autoView contentSize].height, 200.0),
			      "and the content takes the space the bars would have used");

			[autoDoc setFrame:NSMakeRect(0.0, 0.0, 300.0, 100.0)];
			check(![[autoView horizontalScroller] isHidden] && [[autoView verticalScroller] isHidden],
			      "a wide document shows the horizontal bar and keeps the vertical one hidden");
			check(near([autoView contentSize].width, 200.0) && near([autoView contentSize].height, 185.0),
			      "and only the shown bar takes room");

			[autoDoc setFrame:NSMakeRect(0.0, 0.0, 300.0, 300.0)];
			check(![[autoView verticalScroller] isHidden] && ![[autoView horizontalScroller] isHidden],
			      "a document larger in both directions shows both bars");
			check(near([autoView contentSize].width, 185.0) && near([autoView contentSize].height, 185.0),
			      "and the content is what both of them leave");

			[autoView setAutohidesScrollers:NO];
			[autoDoc setFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
			check(![[autoView verticalScroller] isHidden] && ![[autoView horizontalScroller] isHidden],
			      "turning autohide off brings both bars back even for a document that fits");

			[autoDoc release];
			[autoView release];
		}

		/* 12. **THE TWO AXES, THE ALIASES BETWEEN THE 10.0 PAIR AND THEM, AND THE TWO DOORS THAT ARE NOT NUMBERS.** A
		 * second scroll view with a document that overflows BOTH ways, because one that only overflows downward cannot tell
		 * a vertical step from a horizontal one. */
		{
			NSScrollView *two = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 200.0)];
			NSClipView *c2 = (NSClipView *)[two contentView];
			NSView *d2 = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 500.0, 500.0)];
			NSScroller *h;

			[two setHasVerticalScroller:YES];
			[two setHasHorizontalScroller:YES];
			[two setDocumentView:d2];
			h = [two horizontalScroller];

			check(near([two horizontalLineScroll], 10.0) && near([two verticalLineScroll], 10.0),
			      "both axes start at the era's ten-point line step");
			check(near([two lineScroll], 10.0),
			      "and `-lineScroll` is the VERTICAL amount — the 10.0 door is the vertical axis by name");
			check(near([two horizontalPageScroll], 0.0) && near([two verticalPageScroll], 0.0),
			      "with a page of 0 on both axes, which means \"page by the visible extent\"");

			/* THE ALIAS IS ONE FIELD, NOT TWO ANSWERS THAT HAPPEN TO MATCH. */
			[two setLineScroll:7.0];
			check(near([two verticalLineScroll], 7.0) && near([two horizontalLineScroll], 10.0),
			      "`-setLineScroll:` writes the VERTICAL amount and leaves the horizontal one alone");
			[two setHorizontalLineScroll:30.0];
			check(near([two verticalLineScroll], 7.0) && near([two lineScroll], 7.0),
			      "and `-setHorizontalLineScroll:` cannot be read back through the vertical door");

			/* A LINE ON EACH AXIS, AND EACH STEPS ITS OWN WAY. The horizontal scroller is 185 wide, so its decrement
			 * line button is x 0..15; the vertical one's is y 0..15 in a flipped cell. */
			[two setVerticalLineScroll:10.0];
			aim_scroller(h, NSMakePoint(178.0, 7.0), 0.0);	/* the increment line button of a horizontal bar */
			[two cg_scrollerAction:h];
			printf("  (note: a horizontal line step left the clip origin at %.1f, %.1f)\n",
			       (double)[c2 bounds].origin.x, (double)[c2 bounds].origin.y);
			check(near([c2 bounds].origin.x, 30.0),
			      "an increment LINE on the horizontal bar moves x by the HORIZONTAL step (30)");
			check(near([c2 bounds].origin.y, 0.0), "and leaves y where it was");
			{
				NSScroller *v = [two verticalScroller];

				aim_scroller(v, NSMakePoint(7.0, 178.0), 0.0);	/* the increment line at the bottom */
				[two cg_scrollerAction:v];
				check(near([c2 bounds].origin.y, 10.0),
				      "and the vertical bar's line step is the VERTICAL amount (10)");
				check(near([c2 bounds].origin.x, 30.0), "which leaves x alone");
			}

			/* A PAGE OF ITS OWN IS HONOURED WHEN IT IS SET, AND THE VISIBLE EXTENT IS THE FALLBACK. */
			[two setHorizontalPageScroll:50.0];
			aim_scroller(h, NSMakePoint(160.0, 7.0), 0.0);	/* an increment PAGE, clear of the knob */
			[two cg_scrollerAction:h];
			check(near([c2 bounds].origin.x, 80.0),
			      "a horizontal page of 50 moves x by 50 rather than by the visible extent");
			[two setHorizontalPageScroll:0.0];
			[two setVerticalLineScroll:15.0];
			[two setVerticalPageScroll:0.0];
			/* BACK TO THE TOP FIRST, or the page would step from wherever the line step left the clip view — this is a
			 * page's ARITHMETIC being checked, not its accumulation. */
			[c2 scrollToPoint:NSMakePoint([c2 bounds].origin.x, 0.0)];
			aim_scroller([two verticalScroller], NSMakePoint(7.0, 120.0), 0.0);
			[two cg_scrollerAction:[two verticalScroller]];
			printf("  (note: the vertical page of 0 left y at %.1f, and the knob sits at value %.3f)\n",
			       (double)[c2 bounds].origin.y, (double)[[two verticalScroller] floatValue]);
			check(near([c2 bounds].origin.y, 185.0 - 15.0),
			      "and a page of 0 is the visible extent less the line step, on that axis's own numbers");

			/* THE DOCUMENT'S CURSOR IS THE CLIP VIEW'S, AND THIS IS THE FORWARD. */
			check([two documentCursor] == nil, "a scroll view has no document cursor by default");
			[two setDocumentCursor:[NSCursor openHandCursor]];
			check([two documentCursor] == [NSCursor openHandCursor],
			      "`-setDocumentCursor:` round-trips through the scroll view");
			check([c2 documentCursor] == [NSCursor openHandCursor],
			      "because the state is the CLIP VIEW's, which is the object that draws the document");

			/* AND THE ONE FLAG WITH ONE MODE. NO is refused by name and the bar keeps the mode it can honour — the
			 * claim is read back rather than assumed. */
			check([two scrollsDynamically], "a scroll view draws as it goes by default");
			[two setScrollsDynamically:NO];
			check([two scrollsDynamically],
			      "`-setScrollsDynamically:NO` is REFUSED and the flag stays YES, because there is no deferred mode here");

			[d2 release];
			[two release];
		}

		[sv release];
		printf("scroll_view: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
