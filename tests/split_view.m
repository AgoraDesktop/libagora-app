/*
 * split_view — panes, dividers, the collapse, the constraints and the ink.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * **A SPLIT VIEW IS GEOMETRY, A GESTURE AND A DELEGATE AT ONCE, SO THIS FILE ASKS ALL THREE.** The geometry half is
 * the pane frames, the divider positions and the possible ranges; the gesture half is a press inside a divider's
 * effective rectangle, the drag that follows and the double-click that collapses; the delegate half is the minimum
 * and maximum constraints, the resize hook, the fixed-size pane and the collapse permission. The ink is read back
 * from a bitmap, because "the divider is drawn" is not a fact about the code that asked for it.
 *
 * The window is a coordinate root for the synthetic events and nothing else. No compositor is involved, and a press
 * is delivered by calling the view's mouse methods directly — the split view's own tracking loop is skipped when the
 * application is not running, which is the same door `NSControl` takes in this tier's other probes.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSSplitView.h>
#import <AppKit/NSScrollView.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSBezierPath.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

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
	return fabs(a - b) < 0.05;
}

static int eqr(NSRect a, NSRect b)
{
	return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y)
		&& near(a.size.width, b.size.width) && near(a.size.height, b.size.height);
}

static NSBitmapImageRep *new_rep(int w, int h)
{
	return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
}

static double lum(NSColor *c)
{
	return c == nil ? 1.0 : ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3.0;
}

static int same_colour(NSColor *a, NSColor *b, double tol)
{
	return a != nil && b != nil
		&& fabs([a redComponent] - [b redComponent]) < tol
		&& fabs([a greenComponent] - [b greenComponent]) < tol
		&& fabs([a blueComponent] - [b blueComponent]) < tol;
}

static NSEvent *mouse(int type, NSPoint where, NSInteger windowNumber, NSInteger clickCount)
{
	return [NSEvent mouseEventWithType:(NSEventType)type location:where modifierFlags:0
				 timestamp:0.0 windowNumber:windowNumber context:nil
				 eventNumber:0 clickCount:clickCount pressure:1.0f];
}

static NSSplitView *make_split(NSWindow **outWindow, CGFloat width, CGFloat height, BOOL vertical,
			       CGFloat a, CGFloat b, CGFloat c)
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, width, height)
						      styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, height)];
	NSView *one = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, vertical ? a : width, vertical ? height : a)];
	NSView *two = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, vertical ? b : width, vertical ? height : b)];
	NSView *three = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, vertical ? c : width, vertical ? height : c)];

	[split setDividerStyle:NSSplitViewDividerStyleThin];
	[split setVertical:vertical];
	[split addSubview:one];
	[split addSubview:two];
	[split addSubview:three];
	[window setContentView:split];
	[split adjustSubviews];
	[one release];
	[two release];
	[three release];
	if (outWindow != NULL) {
		*outWindow = window;
	}
	return split;
}

/* A TABLE'S ONLY JOB IN THE CLIP PROBE IS TO HAVE TEXT WIDER THAN ITS PANE. */
@interface AGTextClipSource : NSObject <NSTableViewDataSource>
@end

@implementation AGTextClipSource
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return 4;
}
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn
	     row:(NSInteger)row
{
	(void)tableView;
	(void)tableColumn;
	(void)row;
	return @"text wider than the pane must stop at its edge";
}
@end

/* ---- THE DELEGATES, EACH ONE ONLY THE DOORS ITS QUESTION NEEDS ---------------------------------- */

@interface AGCollapseDelegate : NSObject <NSSplitViewDelegate>
{
@public
	NSView *collapsible;
	BOOL doubleClick;
}
@end

@implementation AGCollapseDelegate
- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
	(void)splitView;
	return subview == collapsible;
}
- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview
    forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex
{
	(void)splitView;
	(void)dividerIndex;
	return doubleClick && subview == collapsible;
}
@end

@interface AGConstraintDelegate : NSObject <NSSplitViewDelegate>
{
@public
	CGFloat minimum;
	CGFloat maximum;
	CGFloat splitPosition;
	BOOL overrideSplitPosition;
}
@end

@implementation AGConstraintDelegate
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition
	 ofSubviewAt:(NSInteger)dividerIndex
{
	(void)splitView;
	(void)dividerIndex;
	(void)proposedMinimumPosition;
	return minimum;
}
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition
	 ofSubviewAt:(NSInteger)dividerIndex
{
	(void)splitView;
	(void)dividerIndex;
	(void)proposedMaximumPosition;
	return maximum;
}
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)proposedPosition
	 ofSubviewAt:(NSInteger)dividerIndex
{
	(void)splitView;
	(void)dividerIndex;
	return overrideSplitPosition ? splitPosition : proposedPosition;
}
@end

@interface AGFixedPaneDelegate : NSObject <NSSplitViewDelegate>
{
@public
	NSView *fixedView;
}
@end

@implementation AGFixedPaneDelegate
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view
{
	(void)splitView;
	return view != fixedView;
}
@end

@interface AGResizeDelegate : NSObject <NSSplitViewDelegate>
{
@public
	NSView *first;
	int calls;
}
@end

@implementation AGResizeDelegate
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
	(void)oldSize;
	calls++;
	if (first != nil) {
		NSRect frame = [first frame];

		frame.size.width = 42.0;
		[first setFrame:frame];
	}
	(void)splitView;
}
@end

@interface AGSplitObserver : NSObject
{
@public
	int willResize;
	int didResize;
	NSInteger lastDivider;
	BOOL sawIndex;
}
@end

@implementation AGSplitObserver
- (void)willResize:(NSNotification *)notification
{
	NSNumber *number = [[notification userInfo] objectForKey:@"NSSplitViewDividerIndex"];

	willResize++;
	sawIndex = (number != nil);
	lastDivider = number != nil ? [number integerValue] : -1;
}
- (void)didResize:(NSNotification *)notification
{
	NSNumber *number = [[notification userInfo] objectForKey:@"NSSplitViewDividerIndex"];

	didResize++;
	sawIndex = (number != nil);
	lastDivider = number != nil ? [number integerValue] : -1;
}
@end

int main(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *window;
	NSSplitView *split;
	NSArray *subviews;

	setvbuf(stdout, NULL, _IONBF, 0);
	/* NSUserDefaults resolves a config root from this environment variable; without it the Foundation defaults to a
	 * path that is not writable here. The autosave check needs a real defaults store, so it gets a temporary one. */
	setenv("FNX_CONFIG_ROOT", "/tmp/agora-split-view-defaults", 1);
	[application finishLaunching];

	/* 1. THE DEFAULT ORIENTATION, THE FLIPPED COORDINATES AND THE THREE THICKNESSES. */
	split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
	check(![split isVertical], "a split view is horizontal until told otherwise");
	check([split isFlipped], "and its coordinates are flipped, so subview 0 is the top or left pane");
	check(near([split dividerThickness], 6.0), "the default thick divider is six points here");
	[split setDividerStyle:NSSplitViewDividerStyleThin];
	check(near([split dividerThickness], 1.0), "the thin style is a one-point hairline");
	[split setDividerStyle:NSSplitViewDividerStylePaneSplitter];
	check(near([split dividerThickness], 18.0), "and the pane splitter is an 18-point gutter");
	[split setDividerStyle:NSSplitViewDividerStyleThick];
	[split setIsPaneSplitter:YES];
	check([split isPaneSplitter] && near([split dividerThickness], 18.0),
	      "the deprecated pane-splitter pair is the same style");
	[split release];

	/* 2. A VERTICAL LAYOUT: THREE PANES, TWO DIVIDERS, EXACT GEOMETRY. */
	split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
	subviews = [split subviews];
	check(eqr([[subviews objectAtIndex:0] frame], NSMakeRect(0.0, 0.0, 100.0, 300.0)),
	      "pane 0 starts at the left edge and is 100 wide");
	check(eqr([[subviews objectAtIndex:1] frame], NSMakeRect(101.0, 0.0, 150.0, 300.0)),
	      "pane 1 begins after the first divider");
	check(eqr([[subviews objectAtIndex:2] frame], NSMakeRect(252.0, 0.0, 148.0, 300.0)),
	      "pane 2 begins after the second and fills the remainder");
	check(near([split minPossiblePositionOfDividerAtIndex:0], 0.0)
	      && near([split maxPossiblePositionOfDividerAtIndex:0], 250.0),
	      "divider 0 may run from the left edge to the next divider less one thickness");
	check(near([split minPossiblePositionOfDividerAtIndex:1], 101.0)
	      && near([split maxPossiblePositionOfDividerAtIndex:1], 399.0),
	      "divider 1 may run from the first divider to the right edge");

	/* 3. A PROGRAMMATIC MOVE RESIZES ONLY THE TWO PANES BESIDE IT. */
	[split setPosition:150.0 ofDividerAtIndex:0];
	check(near([[subviews objectAtIndex:0] frame].size.width, 150.0)
	      && near([[subviews objectAtIndex:1] frame].origin.x, 151.0)
	      && near([[subviews objectAtIndex:1] frame].size.width, 100.0),
	      "moving divider 0 to 150 gives pane 0 the room and takes it from pane 1");
	check(near([[subviews objectAtIndex:2] frame].origin.x, 252.0),
	      "and divider 1 does not move");
	[split setPosition:1000.0 ofDividerAtIndex:0];
	check(near([[subviews objectAtIndex:0] frame].size.width, 250.0)
	      && near([[subviews objectAtIndex:1] frame].size.width, 0.0),
	      "a position past the maximum is clamped, leaving the next pane at zero");
	[split setPosition:-50.0 ofDividerAtIndex:0];
	check(near([[subviews objectAtIndex:0] frame].size.width, 0.0)
	      && near([[subviews objectAtIndex:1] frame].size.width, 250.0),
	      "and a position before the minimum is clamped to zero");
	[split release];
	[window release];

	/* 4. A HORIZONTAL LAYOUT RUNS TOP TO BOTTOM, BECAUSE THE VIEW IS FLIPPED. */
	split = make_split(&window, 400.0, 300.0, NO, 100.0, 100.0, 98.0);
	subviews = [split subviews];
	check(eqr([[subviews objectAtIndex:0] frame], NSMakeRect(0.0, 0.0, 400.0, 100.0)),
	      "pane 0 is the top pane at y=0");
	check(eqr([[subviews objectAtIndex:1] frame], NSMakeRect(0.0, 101.0, 400.0, 100.0)),
	      "pane 1 follows it down the flipped y axis");
	check(eqr([[subviews objectAtIndex:2] frame], NSMakeRect(0.0, 202.0, 400.0, 98.0)),
	      "and pane 2 reaches the bottom edge");
	[split release];
	[window release];

	/* 5. A FRAME CHANGE RE-STATES THE PROPORTIONS, DIVIDERS INCLUDED. */
	split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
	subviews = [split subviews];
	[split setFrame:NSMakeRect(0.0, 0.0, 600.0, 300.0)];
	check(near([[subviews objectAtIndex:0] frame].size.width / 600.0, 100.0 / 400.0),
	      "a wider split view keeps the first pane's share of the width");
	check(near([[subviews objectAtIndex:1] frame].size.width / 600.0, 150.0 / 398.0),
	      "and the second pane's share of the pane area");
	check(near([[subviews objectAtIndex:2] frame].origin.x + [[subviews objectAtIndex:2] frame].size.width,
		   600.0),
	      "and the last pane still ends at the trailing edge");
	[split release];
	[window release];

	/* 6. THE DELEGATE'S CONSTRAINTS NARROW BOTH ENDS. */
	{
		AGConstraintDelegate *delegate = [[AGConstraintDelegate alloc] init];

		delegate->minimum = 50.0;
		delegate->maximum = 200.0;
		delegate->splitPosition = 0.0;
		delegate->overrideSplitPosition = NO;
		split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
		[split setDelegate:delegate];
		[split setPosition:10.0 ofDividerAtIndex:0];
		check(near([[[split subviews] objectAtIndex:0] frame].size.width, 50.0),
		      "a delegate's minimum coordinate stops the divider at 50");
		[split setPosition:300.0 ofDividerAtIndex:0];
		check(near([[[split subviews] objectAtIndex:0] frame].size.width, 200.0),
		      "and its maximum stops the other direction at 200");
		/* THE SPLIT-POSITION DOOR IS ASKED FIRST, and this delegate answers a position rather than the proposal. */
		delegate->splitPosition = 123.0;
		delegate->overrideSplitPosition = YES;
		[split setPosition:200.0 ofDividerAtIndex:0];
		check(near([[[split subviews] objectAtIndex:0] frame].size.width, 123.0),
		      "constrainSplitPosition replaces the proposal before the range is applied");
		[split release];
		[window release];
		[delegate release];
	}

	/* 7. SHOULD-ADJUST KEEPS A PANE'S SIZE AND GIVES THE REST TO THE OTHERS. */
	{
		AGFixedPaneDelegate *delegate = [[AGFixedPaneDelegate alloc] init];
		NSArray *views;

		split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
		views = [split subviews];
		delegate->fixedView = [views objectAtIndex:0];
		[split setDelegate:delegate];
		[split setFrame:NSMakeRect(0.0, 0.0, 600.0, 300.0)];
		check(near([[views objectAtIndex:0] frame].size.width, 100.0),
		      "a pane the delegate refuses to resize keeps its 100 points");
		check(near([[views objectAtIndex:1] frame].size.width + [[views objectAtIndex:2] frame].size.width,
			  498.0),
		      "and the other two share the 498 points left after it and the dividers");
		[split release];
		[window release];
		[delegate release];
	}

	/* 8. THE RESIZE HOOK TAKES THE LAYOUT AWAY FROM THE SPLIT VIEW. */
	{
		AGResizeDelegate *delegate = [[AGResizeDelegate alloc] init];

		split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
		delegate->first = [[split subviews] objectAtIndex:0];
		[split setDelegate:delegate];
		[split setFrame:NSMakeRect(0.0, 0.0, 500.0, 300.0)];
		check(delegate->calls == 1 && near([[[split subviews] objectAtIndex:0] frame].size.width, 42.0),
		      "the delegate's resize hook runs and its own frame is the one that stands");
		[split release];
		[window release];
		[delegate release];
	}

	/* 9. A DRAG FROM THE PRESS DELTA, INCLUDING THE THIN STYLE'S WIDER GRAB AREA. */
	split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
	subviews = [split subviews];
	{
		NSInteger number = [window windowNumber];
		NSPoint grab = [split convertPoint:NSMakePoint(99.0, 100.0) toView:nil];
		NSPoint moved = [split convertPoint:NSMakePoint(129.0, 100.0) toView:nil];

		[split mouseDown:mouse(NSLeftMouseDown, grab, number, 1)];
		[split mouseDragged:mouse(NSLeftMouseDragged, moved, number, 1)];
		[split mouseUp:mouse(NSLeftMouseUp, moved, number, 1)];
		check(near([[subviews objectAtIndex:0] frame].size.width, 130.0),
		      "a press two points outside the hairline still grabs it, and the drag is a 30-point delta");
		check(near([[subviews objectAtIndex:1] frame].origin.x, 131.0),
		      "the next pane follows the divider");
	}
	[split release];
	[window release];

	/* 10. A THICK DIVIDER'S HIT AREA IS ITS DRAWN RECTANGLE. */
	split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 138.0);
	[split setDividerStyle:NSSplitViewDividerStyleThick];
	[split adjustSubviews];
	subviews = [split subviews];
	{
		NSInteger number = [window windowNumber];
		NSPoint outside = [split convertPoint:NSMakePoint(98.0, 100.0) toView:nil];
		NSPoint moved = [split convertPoint:NSMakePoint(130.0, 100.0) toView:nil];

		[split mouseDown:mouse(NSLeftMouseDown, outside, number, 1)];
		[split mouseDragged:mouse(NSLeftMouseDragged, moved, number, 1)];
		[split mouseUp:mouse(NSLeftMouseUp, moved, number, 1)];
		check(near([[subviews objectAtIndex:0] frame].size.width, 100.0),
		      "a click two points outside a thick divider lands in the pane and moves nothing");
	}
	[split release];
	[window release];

	/* 11. A DOUBLE-CLICK COLLAPSES AND OPENS AGAIN, AND A COLLAPSED PANE IS HIDDEN AND ZERO-SIZED. */
	split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
	{
		AGCollapseDelegate *delegate = [[AGCollapseDelegate alloc] init];
		NSInteger number = [window windowNumber];
		NSPoint at = [split convertPoint:NSMakePoint(100.5, 100.0) toView:nil];
		NSPoint collapsedAt = [split convertPoint:NSMakePoint(0.5, 100.0) toView:nil];
		NSView *first = [[split subviews] objectAtIndex:0];

		delegate->collapsible = first;
		delegate->doubleClick = YES;
		[split setDelegate:delegate];
		[split mouseDown:mouse(NSLeftMouseDown, at, number, 2)];
		check([split isSubviewCollapsed:first] && [first isHidden]
		      && near([first frame].size.width, 0.0),
		      "a double-click collapses the pane the delegate names");
		check(near([[[split subviews] objectAtIndex:1] frame].size.width, 250.0),
		      "and the pane after it takes the empty room");
		[split mouseDown:mouse(NSLeftMouseDown, collapsedAt, number, 2)];
		check(![split isSubviewCollapsed:first] && ![first isHidden]
		      && near([first frame].size.width, 100.0),
		      "a second double-click opens it at its remembered width");
		[split release];
		[window release];
		[delegate release];
	}

	/* 12. A DRAG THROUGH ZERO COLLAPSES, AND A DRAG BACK OPENS. */
	split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
	{
		AGCollapseDelegate *delegate = [[AGCollapseDelegate alloc] init];
		NSView *first = [[split subviews] objectAtIndex:0];

		delegate->collapsible = first;
		delegate->doubleClick = NO;
		[split setDelegate:delegate];
		[split setPosition:0.0 ofDividerAtIndex:0];
		check([split isSubviewCollapsed:first] && [first isHidden],
		      "dragging a collapsible pane to zero collapses it");
		[split setPosition:50.0 ofDividerAtIndex:0];
		check(![split isSubviewCollapsed:first] && near([first frame].size.width, 50.0),
		      "and dragging the divider back opens it to the delta");
		[split release];
		[window release];
		[delegate release];
	}

	/* 13. THE ANNOUNCEMENTS CARRY THE DIVIDER INDEX FOR A MOVE, AND NONE FOR A LAYOUT. */
	{
		AGSplitObserver *observer = [[AGSplitObserver alloc] init];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

		split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
		[center addObserver:observer selector:@selector(willResize:)
			       name:NSSplitViewWillResizeSubviewsNotification object:split];
		[center addObserver:observer selector:@selector(didResize:)
			       name:NSSplitViewDidResizeSubviewsNotification object:split];
		[split setPosition:130.0 ofDividerAtIndex:0];
		check(observer->willResize == 1 && observer->didResize == 1
		      && observer->sawIndex && observer->lastDivider == 0,
		      "a programmatic move announces once at each end, with divider 0 in the user info");
		observer->willResize = observer->didResize = 0;
		observer->sawIndex = NO;
		[split adjustSubviews];
		check(observer->willResize >= 1 && observer->didResize >= 1 && !observer->sawIndex,
		      "a layout announces the same pair with no divider index");
		[center removeObserver:observer name:nil object:split];
		[split release];
		[window release];
		[observer release];
	}

	/* 14. THE AUTOSAVE NAME ROUND-TRIPS THE PANE PROPORTIONS AND THE COLLAPSED SET. */
	{
		NSString *key = @"AgoraSplitView SplitProbe";
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSSplitView *second;
		NSWindow *secondWindow;

		[defaults removeObjectForKey:key];
		split = make_split(&window, 400.0, 300.0, YES, 100.0, 150.0, 148.0);
		[split setAutosaveName:@"SplitProbe"];
		[split setPosition:150.0 ofDividerAtIndex:0];
		check(near([[[split subviews] objectAtIndex:0] frame].size.width, 150.0),
		      "the first split view is saved at a 150-point first pane");
		[split release];
		[window release];

		second = make_split(&secondWindow, 400.0, 300.0, YES, 50.0, 50.0, 298.0);
		[second setAutosaveName:@"SplitProbe"];
		check(near([[[second subviews] objectAtIndex:0] frame].size.width, 150.0)
		      && near([[[second subviews] objectAtIndex:1] frame].size.width, 100.0),
		      "a second split view under the same name restores those proportions");
		[second release];
		[secondWindow release];
		[defaults removeObjectForKey:key];
	}

	/* 15. THE INK: THE DIVIDER IS THE CONTROL SHADOW, IN BOTH ORIENTATIONS. */
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 200.0, 100.0)
					     styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 100.0)];
	[split setDividerStyle:NSSplitViewDividerStyleThin];
	[split setVertical:YES];
	[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 100.0)] autorelease]];
	[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 119.0, 100.0)] autorelease]];
	[window setContentView:split];
	[split adjustSubviews];
	{
		int w = (int)[split frame].size.width;
		int h = (int)[split frame].size.height;
		NSBitmapImageRep *rep = new_rep(w, h);
		NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

		[NSGraphicsContext setCurrentContext:ctx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
		{
			CGContextRef cg = (CGContextRef)[ctx graphicsPort];

			CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
			CGContextScaleCTM(cg, 1.0, -1.0);
		}
		[split displayRect:[split bounds]];
		check(same_colour([rep colorAtX:80 y:50], [NSColor controlDarkShadowColor], 0.03),
		      "a vertical split's divider is drawn at its leading edge");
		check(!same_colour([rep colorAtX:10 y:50], [NSColor controlDarkShadowColor], 0.03),
		      "and the pane beside it is not painted by the split view");
		[rep release];
	}
	[split release];
	[window release];

	/* A TWO-PANE HORIZONTAL SPLIT, SO THE HORIZONTAL DIVIDER'S INK HAS A RECT OF ITS OWN. */
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 200.0, 100.0)
					     styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 100.0)];
	[split setDividerStyle:NSSplitViewDividerStyleThin];
	[split setVertical:NO];
	[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 40.0)] autorelease]];
	[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 59.0)] autorelease]];
	[window setContentView:split];
	[split adjustSubviews];
	{
		int w = (int)[split frame].size.width;
		int h = (int)[split frame].size.height;
		NSBitmapImageRep *rep = new_rep(w, h);
		NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];

		[NSGraphicsContext setCurrentContext:ctx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
		{
			CGContextRef cg = (CGContextRef)[ctx graphicsPort];

			CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
			CGContextScaleCTM(cg, 1.0, -1.0);
		}
		[split displayRect:[split bounds]];
		check(same_colour([rep colorAtX:100 y:40], [NSColor controlDarkShadowColor], 0.03),
		      "a horizontal split's divider is drawn down the flipped y axis");
		[rep release];
	}
	[split release];
	[window release];

	/* 16. THE PANE SPLITTER'S WIDE GUTTER AND ITS THREE RINGS, READ AS PIXELS. */
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 200.0, 120.0)
					     styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 200.0, 120.0)];
	[split setDividerStyle:NSSplitViewDividerStylePaneSplitter];
	[split setVertical:YES];
	[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 80.0, 120.0)] autorelease]];
	[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 102.0, 120.0)] autorelease]];
	[window setContentView:split];
	[split adjustSubviews];
	check(same_colour([split dividerColor], [NSColor controlDarkShadowColor], 0.01),
	      "the divider colour is the tier's border grey");
	{
		int w = (int)[split frame].size.width;
		int h = (int)[split frame].size.height;
		NSBitmapImageRep *rep = new_rep(w, h);
		NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
		int x, y, i;
		int bandStarts[8];
		int bandEnds[8];
		int bandCount = 0;
		BOOL inBand = NO;

		[NSGraphicsContext setCurrentContext:ctx];
		[[NSColor whiteColor] setFill];
		[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
		{
			CGContextRef cg = (CGContextRef)[ctx graphicsPort];

			CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
			CGContextScaleCTM(cg, 1.0, -1.0);
		}
		[split displayRect:[split bounds]];
		check(same_colour([rep colorAtX:90 y:10], [NSColor windowBackgroundColor], 0.03),
		      "the 18-point gutter is the window's face, not ink");
		/* THE RINGS ARE THE ONLY DARK INK IN THE GUTTER, so each contiguous band of rows containing a
		 * darker-than-gutter pixel is one ring. Scanning every x in the gutter makes a ring's whole outline
		 * one band rather than the two crossings a single column would show. */
		for (y = 0; y < h; y++) {
			BOOL dark = NO;

			for (x = 80; x < 98; x++) {
				if (lum([rep colorAtX:x y:y]) < 0.85) {
					dark = YES;
					break;
				}
			}
			if (dark && !inBand) {
				inBand = YES;
				if (bandCount < 8) {
					bandStarts[bandCount] = y;
				}
			} else if (!dark && inBand) {
				inBand = NO;
				if (bandCount < 8) {
					bandEnds[bandCount] = y - 1;
				}
				bandCount++;
			}
		}
		if (inBand && bandCount < 8) {
			bandEnds[bandCount] = h - 1;
			bandCount++;
		}
		check(bandCount == 3, "the pane splitter draws exactly three rings");
		for (i = 0; i < bandCount && i < 3; i++) {
			int center = (bandStarts[i] + bandEnds[i]) / 2;
			int want = 52 + i * 8;

			check(fabs((double)(center - want)) <= 2.5,
			      i == 0 ? "the top ring is eight points above the centre"
				     : (i == 1 ? "the middle ring sits on the centre"
					: "the bottom ring is eight points below it"));
		}
		[rep release];
	}
	[split release];
	[window release];

	/* 17. A PANE CLIPS THE TABLE'S TEXT, NOT ONLY ITS BACKGROUND. A cell's text used to REPLACE the
	 * enclosing clip with its own cell rectangle, so a wide column in a narrow pane drew its words across
	 * the neighbour. The right pane here is blank: any dark pixel in it came from the table. */
	window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 300.0, 160.0)
					     styleMask:0 backing:NSBackingStoreBuffered defer:NO];
	split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 160.0)];
	[split setDividerStyle:NSSplitViewDividerStyleThin];
	[split setVertical:YES];
	{
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, 160.0)];
		NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 250.0, 160.0)];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"wide"];
		AGTextClipSource *source = [[AGTextClipSource alloc] init];
		NSView *blank = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 199.0, 160.0)];

		[scroll setBorderType:NSNoBorder];
		[scroll setHasVerticalScroller:NO];
		[scroll setHasHorizontalScroller:NO];
		[table setHeaderView:nil];
		[table setRowHeight:20.0];
		[column setWidth:250.0];
		[table addTableColumn:column];
		[table setDataSource:source];
		[scroll setDocumentView:table];
		[table reloadData];
		[split addSubview:scroll];
		[split addSubview:blank];
		[window setContentView:split];
		[split adjustSubviews];
		{
			int w = (int)[split frame].size.width;
			int h = (int)[split frame].size.height;
			NSBitmapImageRep *rep = new_rep(w, h);
			NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
			int x, y, inside = 0, outside = 0;

			[NSGraphicsContext setCurrentContext:ctx];
			[[NSColor whiteColor] setFill];
			[[NSBezierPath bezierPathWithRect:NSMakeRect(0.0, 0.0, (CGFloat)w, (CGFloat)h)] fill];
			{
				CGContextRef cg = (CGContextRef)[ctx graphicsPort];

				CGContextTranslateCTM(cg, 0.0, (CGFloat)h);
				CGContextScaleCTM(cg, 1.0, -1.0);
			}
			[split displayRect:[split bounds]];
			for (y = 0; y < h; y++) {
				for (x = 0; x < w; x++) {
					if (lum([rep colorAtX:x y:y]) < 0.35) {
						if (x < 100) {
							inside++;
						} else if (x > 102) {
							outside++;
						}
					}
				}
			}
			check(inside > 0, "the narrow pane draws the table's text");
			check(outside == 0, "and none of it escapes past the pane's edge");
			[rep release];
		}
		[scroll release];
		[table release];
		[column release];
		[source release];
		[blank release];
	}
	[split release];
	[window release];

	printf("split_view: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
