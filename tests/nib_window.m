/*
 * nib_window — a WINDOW out of a nib, on a real compositor, drawing.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * **THIS IS THE LAST CODING PATH IN THE FORMAT THAT HAD NEVER RUN.** Every other nib test builds views; a window's
 * `-initWithCoder:` is a different animal — it derives the frame, the style mask and the backing store, calls the
 * DESIGNATED INITIALISER (which is what makes a window's defaults, its surface and its content view), applies the
 * archived properties on top, and puts the archived content view back through `-setContentView:`. None of that had ever
 * executed, because a window needs a compositor and the other nib tests deliberately need none.
 *
 * SO THE CHAIN HERE IS THE WHOLE ONE, from text to pixels:
 *
 *   SOURCE  ->  compile  ->  archive  ->  DECODE (a real NSWindow)  ->  order front  ->  the view DRAWS
 *
 * The content view's class is the test's OWN subclass, registered as a design class, because that is what a nib for an
 * application actually names — and its `-drawRect:` count is what proves the decoded window has a working surface rather
 * than merely correct fields.
 */
#import "NSNibSource.h"

#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSView.h>
#import <AppKit/NSNib.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSColor.h>

#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

static int s_failed;
static int s_draws;

static void check(int ok, const char *name)
{
	printf("%s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* THE APPLICATION'S OWN VIEW, named by the nib and counted as it draws. */
@interface WNibView : NSView
@end

@implementation WNibView
- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;
	s_draws++;
	/* **THE COUNT IS THE ASSERTION, NOT THE INK.** What has to be true is that the compositor configured the decoded
	 * window and the AppKit asked a view to draw; `NSRectFill` is not a door this tier has, and a test of the nib path
	 * should not depend on one the drawing tier owes. */
}
@end

/* THE RUN ENDS ON THIS TIMER, and a plain object with a selector is what `NSTimer` wants. */
@interface WNibStopper : NSObject
- (void)stop:(NSTimer *)timer;
@end

@implementation WNibStopper
- (void)stop:(NSTimer *)timer
{
	(void)timer;
	[NSApp terminate:nil];
}
@end

/* **THE SOURCE, AS AN APPLICATION WOULD WRITE IT.** A window whose content view is the app's own class, with one
 * constrained child, so the archive carries a content view, a subtree AND an equation. */
static const char *kWindowSource =
	"{\n"
	"  version = 1;\n"
	"  objects = (\n"
	"    {\n"
	"      id = \"window\";\n"
	"      class = NSWindow;\n"
	"      properties = { frame = \"0 0 320 200\"; title = \"From a nib\"; };\n"
	"      contentView = {\n"
	"        id = \"content\";\n"
	"        class = WNibView;\n"
	"        properties = { frame = \"0 0 320 200\"; tag = 71; };\n"
	"        subviews = (\n"
	"          { id = \"strip\"; class = WNibView;\n"
	"            properties = { frame = \"0 0 0 0\"; tag = 72;\n"
	"                           translatesAutoresizingMaskIntoConstraints = NO; }; }\n"
	"        );\n"
	"        constraints = (\n"
	"          { first = \"strip\"; firstAttribute = width; constant = 120; }\n"
	"          { first = \"strip\"; firstAttribute = height; constant = 40; }\n"
	"          { first = \"strip\"; firstAttribute = left; second = \"content\";\n"
	"            secondAttribute = left; constant = 16; }\n"
	"          { first = \"strip\"; firstAttribute = top; second = \"content\";\n"
	"            secondAttribute = top; constant = 12; }\n"
	"        );\n"
	"      };\n"
	"    }\n"
	"  );\n"
	"}\n";

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSApplication *app;
	NSString *error = nil;
	NSData *archive;
	NSWindow *window = nil;

	check([NSNib registerDesignClass:[WNibView class]],
	      "the application's own view class registered as a design class");

	/* ---- 1. THE COMPILE, WHICH ALSO PROVES A WINDOW IS EXPRESSIBLE ---------------------------------- */
	archive = [NSNibSource archiveFromSourceData:[NSData dataWithBytes:kWindowSource
								    length:strlen(kWindowSource)]
					       error:&error];
	if (archive == nil) {
		fprintf(stderr, "compile refused: %s\n", [(error != nil ? error : @"?") UTF8String]);
	}
	check(archive != nil, "a source that contains a WINDOW compiles");
	check(archive != nil && [NSNib refusalReasonForArchiveData:archive] == nil,
	      "and the reader accepts what was compiled");

	/* ---- 2. THE DECODE, WHICH IS THE PATH THAT HAD NEVER RUN ---------------------------------------- */
	if (archive != nil) {
		[archive writeToFile:@"/tmp/agora-nib-window.nib" atomically:YES];
		{
			NSNib *nib = [[NSNib alloc] initWithContentsOfURL:
				[NSURL fileURLWithPath:@"/tmp/agora-nib-window.nib"]];
			NSArray *top = nil;

			check([nib instantiateNibWithOwner:nil topLevelObjects:&top],
			      "the window DECODED through -initWithCoder:");
			if ([top count] == 1 && [[top objectAtIndex:0] isKindOfClass:[NSWindow class]]) {
				window = [[top objectAtIndex:0] retain];
			}
			check(window != nil, "one NSWindow came back");
			[nib release];
		}
	}

	if (window != nil) {
		NSView *content = [window contentView];
		NSArray *subviews;

		check([[window title] isEqualToString:@"From a nib"], "the window's title round-tripped");
		check(NSEqualRects([window frame], NSMakeRect(0.0, 0.0, 320.0, 200.0)),
		      "the window's frame round-tripped through the designated initialiser");
		check(content != nil, "the window has a content view");
		check([content isKindOfClass:[WNibView class]],
		      "and it is the APPLICATION'S class, by name, from the file");
		check([content tag] == 71, "with its tag");
		subviews = [content subviews];
		check([subviews count] == 1, "and its subtree");
		if ([subviews count] == 1) {
			NSView *strip = [subviews objectAtIndex:0];

			check([strip tag] == 72, "the child came through");
			check([strip superview] == content, "and is wired to its parent");
			check([strip window] == window, "and to the WINDOW it was decoded into");
			check([[content constraints] count] == 4, "all four equations came back");

			/* AND THE EQUATIONS ACTUALLY LAY THE DECODED TREE OUT — 400x300 would be a different answer. */
			[content layoutSubtreeIfNeeded];
			check(fabs([strip frame].size.width - 120.0) < 1e-6,
			      "the decoded width equation produced a width");
			check(fabs([strip frame].origin.x - 16.0) < 1e-6,
			      "and the decoded left equation produced an origin");
			check(fabs([strip frame].origin.y - (200.0 - 12.0 - 40.0)) < 1e-6,
			      "and the top equation measured from the window's top");
		}

		/* ---- 3. AND IT DRAWS, WHICH IS THE PROOF THE SURFACE EXISTS ---------------------------------- */
		app = [NSApplication sharedApplication];
		[window makeKeyAndOrderFront:nil];
		/* **THE PUMP IS THE APPLICATION'S AND IT IS BOUNDED BY A DEADLINE, not by `-run` and a terminating timer.** A
		 * timer that calls `-terminate:` leaves the run loop waiting for the compositor to tear down (the suite's other
		 * window test learned this: it takes ninety seconds that way and seven this way), so the loop asks the
		 * application for its next event until the deadline, which is also what makes the compositor's configure and the
		 * view's draw actually happen. */
		{
			NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];

			while ([deadline timeIntervalSinceNow] > 0.0) {
				NSEvent *event = [app nextEventMatchingMask:NSAnyEventMask
								 untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
								    inMode:nil
								   dequeue:YES];

				if (event != nil) {
					[app sendEvent:event];
				}
			}
		}

		check(s_draws > 0, "the decoded window's view was asked to DRAW (the surface exists)");
		printf("  (drew %d frame(s) out of a nib)\n", s_draws);
	}

	[window release];
	[pool release];
	if (s_failed != 0) {
		fprintf(stderr, "%d failure(s)\n", s_failed);
		return 1;
	}
	printf("all nib-window assertions passed\n");
	return 0;
}
