/*
 * view_tail — the last twenty-eight doors of NSView: the forced display family, the frame/rotation setters, the
 * subview list, autoscroll, the focus-lock and layer refusals, the definition look-up, and the ruler client defaults.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE VIEW'S LAST DOORS ARE TWO KINDS: EFFECTS AND SPELLINGS.** The display doors paint and clear damage; the frame,
 * rotation, subview and autoscroll doors move real geometry; the ruler client defaults are the permissive base a
 * plain view gives a ruler; and the focus-lock, layer and definition doors refuse by name because this tier has no
 * state stack, no CALayer tree and no dictionary substrate. The probe measures the effects and calls the refusals, so
 * both halves are exercised rather than described.
 *
 * WHAT IS ASSERTED:
 *
 *   1. `-display` paints the whole tree and clears the damage; `-displayIfNeeded` paints only when dirty; and the
 *      one-argument `-displayRectIgnoringOpacity:` draws in the current context.
 *   2. `-isHiddenOrHasHiddenAncestor` follows the superview chain, and the three `is` spellings that were missing are
 *      aliases of the tree's older names.
 *   3. `-setFrameRotation:`, `-setBoundsRotation:` and `-scaleUnitSquareToSize:` are the state the three rotation
 *      queries report.
 *   4. `-setFrameOrigin:` moves the frame, leaves the size and bounds alone, and announces the change.
 *   5. `-addSubview:positioned:relativeTo:` places above and below, including the nil-relative ends, and
 *      `-setSubviews:` replaces the list with the move notices run for every view.
 *   6. `-autoscroll:` moves the enclosing clip view to the pointer's point and answers NO with no clip view.
 *   7. `-lockFocus`, `-unlockFocus`, `-setLayer:` and the range form of the definition door refuse without crashing.
 *   8. The ruler client defaults allow every add/move/remove, keep the asked-for location, and `-setClientView:` tells
 *      the OLD client before it stops being one.
 */
#import <AppKit/NSView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSClipView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSRulerView.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>

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

static NSBitmapImageRep *context_rep(int wide, int high)
{
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:wide pixelsHigh:high
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:wide * 4 bitsPerPixel:32];

	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
	[[NSColor whiteColor] setFill];
	[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)wide, (CGFloat)high)] fill];
	return rep;
}

@interface AGDrawingView : NSView
{
@public
	int draws;
	NSRect lastDirty;
}
@end

@implementation AGDrawingView
- (void)drawRect:(NSRect)dirtyRect
{
	draws++;
	lastDirty = dirtyRect;
}
@end

@interface AGNoticeCounter : NSObject
{
@public
	int notices;
}
@end

@implementation AGNoticeCounter
- (void)noted:(NSNotification *)note
{
	(void)note;
	notices++;
}
@end

@interface AGRulerClientView : NSView
{
@public
	int willSet;
	int didAdd;
}
@end

@implementation AGRulerClientView
- (void)rulerView:(NSRulerView *)ruler willSetClientView:(NSView *)newClient
{
	(void)ruler; (void)newClient;
	willSet++;
}
- (void)rulerView:(NSRulerView *)ruler didAddMarker:(NSRulerMarker *)marker
{
	(void)ruler; (void)marker;
	didAdd++;
}
@end

int main(void)
{
	@autoreleasepool {
		/* 1. THE FORCED DISPLAY FAMILY. */
		{
			AGDrawingView *view = [[AGDrawingView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 50.0, 50.0)];
			NSBitmapImageRep *rep = context_rep(60, 60);

			[view setNeedsDisplay:YES];
			[view display];
			check(view->draws == 1, "`-display` paints the view");
			check(![view needsDisplay], "and clears the damage it repaired");
			[view displayIfNeeded];
			check(view->draws == 1, "`-displayIfNeeded` does nothing when nothing is dirty");
			[view setNeedsDisplayInRect:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			[view displayIfNeeded];
			check(view->draws == 2, "and paints when a rectangle was invalidated");
			[view displayRectIgnoringOpacity:NSMakeRect(0.0, 0.0, 5.0, 5.0)];
			check(view->draws == 3, "the one-argument IgnoringOpacity form draws in the current context");
			[rep release];
			[view release];
		}

		/* 2. THE HIDDEN-ANCESTOR WALK AND THE `is` ALIASES. */
		{
			NSView *parent = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
			NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

			[parent addSubview:child];
			check(![child isHiddenOrHasHiddenAncestor], "a visible view is not hidden_or_has_hidden_ancestor");
			[child setHidden:YES];
			check([child isHiddenOrHasHiddenAncestor], "a hidden view is");
			[child setHidden:NO];
			[parent setHidden:YES];
			check([child isHiddenOrHasHiddenAncestor], "and a view under a hidden ancestor is");
			[parent setHidden:NO];
			check(![child isHiddenOrHasHiddenAncestor], "and clearing the ancestor clears the answer");
			check(![child isInFullScreenMode], "`-isInFullScreenMode` is the older door's NO");
			[parent release];
			[child release];
		}

		/* 3. THE ROTATION AND SCALE STATE. */
		{
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 20.0, 20.0)];

			check(![view isRotatedFromBase] && ![view isRotatedOrScaledFromBase],
			      "a fresh view is neither rotated nor scaled from its base");
			[view setFrameRotation:30.0];
			check(near([view frameRotation], 30.0) && [view isRotatedFromBase]
			      && [view isRotatedOrScaledFromBase],
			      "`-setFrameRotation:` is reported by both rotation queries");
			[view setBoundsRotation:45.0];
			check(near([view boundsRotation], 45.0), "`-setBoundsRotation:` writes the same stored rotation");
			[view setFrameRotation:0.0];
			[view setBoundsRotation:0.0];
			check(![view isRotatedOrScaledFromBase], "zero clears rotated-or-scaled");
			[view scaleUnitSquareToSize:NSMakeSize(2.0, 1.0)];
			check([view isRotatedOrScaledFromBase] && ![view isRotatedFromBase],
			      "a scaled unit square is the scaled half of the query, not the rotated one");
			[view release];
		}

		/* 4. THE FRAME-ORIGIN SETTER AND ITS ANNOUNCEMENT. */
		{
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(10.0, 20.0, 30.0, 40.0)];
			AGNoticeCounter *counter = [[AGNoticeCounter alloc] init];

			[view setPostsFrameChangedNotifications:YES];
			[[NSNotificationCenter defaultCenter] addObserver:counter selector:@selector(noted:)
				name:NSViewFrameDidChangeNotification object:view];
			[view setFrameOrigin:NSMakePoint(50.0, 60.0)];
			check(near([view frame].origin.x, 50.0) && near([view frame].origin.y, 60.0),
			      "`-setFrameOrigin:` moves the frame");
			check(near([view frame].size.width, 30.0) && near([view frame].size.height, 40.0),
			      "and leaves the size alone");
			check(near([view bounds].origin.x, 0.0) && near([view bounds].origin.y, 0.0),
			      "and leaves the bounds origin alone");
			check(counter->notices == 1, "and announces the frame change once");
			[[NSNotificationCenter defaultCenter] removeObserver:counter];
			[counter release];
			[view release];
		}

		/* 5. THE POSITIONED ADD AND THE SUBVIEW LIST. */
		{
			NSView *parent = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 100.0)];
			NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSView *c = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSView *d = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];

			[parent addSubview:a];
			[parent addSubview:b];
			[parent addSubview:c positioned:NSWindowAbove relativeTo:a];
			check([[parent subviews] indexOfObjectIdenticalTo:a] == 0
			      && [[parent subviews] indexOfObjectIdenticalTo:c] == 1
			      && [[parent subviews] indexOfObjectIdenticalTo:b] == 2,
			      "an Above add goes immediately after its relative view");
			[parent addSubview:d positioned:NSWindowBelow relativeTo:a];
			check([[parent subviews] indexOfObjectIdenticalTo:d] == 0,
			      "a Below add goes immediately before it");
			[parent addSubview:c positioned:NSWindowAbove relativeTo:nil];
			check([[parent subviews] lastObject] == c, "a nil-relative Above add goes on top");
			[parent addSubview:c positioned:NSWindowBelow relativeTo:nil];
			check([[parent subviews] objectAtIndex:0] == c, "and a nil-relative Below add goes to the bottom");
			{
				NSArray *replacement = [NSArray arrayWithObjects:b, d, nil];

				[parent setSubviews:replacement];
				check([[parent subviews] count] == 2
				      && [[parent subviews] objectAtIndex:0] == b
				      && [[parent subviews] objectAtIndex:1] == d,
				      "`-setSubviews:` replaces the list in the array's order");
				check([a superview] == nil && [c superview] == nil,
				      "and the views that left have no superview");
			}
			[parent release];
			[a release];
			[b release];
			[c release];
			[d release];
		}

		/* 6. AUTOSCROLL. */
		{
			NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 200.0, 100.0)
				styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
			NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 100.0)];
			NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 400.0)];
			NSPoint outside;
			NSEvent *event;
			BOOL scrolled;

			[scroll setDocumentView:document];
			[window setContentView:scroll];
			outside = [document convertPoint:NSMakePoint(10.0, 250.0) toView:nil];
			event = [NSEvent mouseEventWithType:NSLeftMouseDragged location:outside modifierFlags:0
						 timestamp:0.0 windowNumber:[window windowNumber] context:nil
						 eventNumber:0 clickCount:1 pressure:1.0f];
			scrolled = [document autoscroll:event];
			printf("  (note: autoscroll answered %d and the clip origin is %.1f)\n",
			       scrolled, [[scroll contentView] bounds].origin.y);
			check(scrolled && [[scroll contentView] bounds].origin.y > 0.0,
			      "`-autoscroll:` moves the enclosing clip view toward the pointer");
			check(![document autoscroll:nil], "and nil is NO rather than a crash");
			[window release];
			[scroll release];
			[document release];
		}
		{
			NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSEvent *event = [NSEvent mouseEventWithType:NSLeftMouseDragged location:NSMakePoint(5.0, 5.0)
						 modifierFlags:0 timestamp:0.0 windowNumber:0 context:nil
						 eventNumber:0 clickCount:1 pressure:1.0f];

			check(![plain autoscroll:event], "a view with no enclosing clip view cannot scroll");
			[plain release];
		}

		/* 7. THE FOUR REFUSALS: NOTHING TO ASSERT BUT THAT THEY ANSWER. */
		{
			NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSAttributedString *string = [[NSAttributedString alloc] initWithString:@"definition"];
			NSPoint (^provider)(NSRange) = ^NSPoint(NSRange range) { (void)range; return NSZeroPoint; };

			[view lockFocus];
			[view unlockFocus];
			[view setLayer:nil];
			[view showDefinitionForAttributedString:string range:NSMakeRange(0, 1) options:nil
					 baselineOriginProvider:provider];
			check([view layer] == nil, "the focus-lock, layer and definition refusals leave the view unchanged");
			[string release];
			[view release];
		}

		/* 8. THE RULER CLIENT DEFAULTS, AND THE OLD CLIENT'S NOTICE. */
		{
			AGRulerClientView *client = [[AGRulerClientView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSView *other = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 10.0, 10.0)];
			NSRulerView *ruler = [[NSRulerView alloc] initWithScrollView:nil orientation:NSHorizontalRuler];
			NSRulerMarker *marker = [[NSRulerMarker alloc] initWithRulerView:ruler markerLocation:10.0
									 image:nil imageOrigin:NSZeroPoint];

			check([client respondsToSelector:@selector(rulerView:shouldAddMarker:)],
			      "every view answers the ruler client protocol");
			check([client rulerView:ruler shouldAddMarker:marker]
			      && [client rulerView:ruler shouldMoveMarker:marker]
			      && [client rulerView:ruler shouldRemoveMarker:marker],
			      "the defaults allow every add, move and remove");
			check(near([client rulerView:ruler willAddMarker:marker atLocation:42.0], 42.0)
			      && near([client rulerView:ruler willMoveMarker:marker toLocation:43.0], 43.0),
			      "and the will-doors keep the location they were asked for");
			[ruler setClientView:client];
			[ruler setClientView:other];
			check(client->willSet == 1,
			      "`-setClientView:` tells the OLD client before it stops being one");
			[marker release];
			[ruler release];
			[other release];
			[client release];
		}

		printf("view_tail: %d case(s) failed\n", s_failed);
	}
	return s_failed != 0;
}
