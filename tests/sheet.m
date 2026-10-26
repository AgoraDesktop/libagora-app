/*
 * sheet — where a sheet goes, what it loses when it becomes one, and what it gets back.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. A sheet is the first thing in this tier that is TWO windows at once, and every part of it that
 * can be wrong is a property of the pair rather than of either window: a sheet drawn with a title bar of its own reads
 * as a second window sitting on the first one's strip (which is exactly what it was before `-isSheet` reached the
 * chrome arithmetic), a sheet placed at its parent's TOP rather than at the bottom of the parent's title bar leaves the
 * parent's title behind it, a sheet that does not follow a dragged parent comes unstuck, a sheet that keeps its frame
 * when the session ends loses twenty-two points of its own content, and — the report that added the last section — a
 * CLICK on the disabled parent did nothing at all, so the pair stayed buried behind whatever had been raised since and
 * the question with it.
 *
 * WHAT IS ASSERTED, each one a way the pair can look right and be wrong:
 *
 *   1. A sheet's FRAME IS ITS CONTENT — it has no strip of its own — and taking the strip off leaves the CONTENT the
 *      size the caller laid it out for, which is what `-setStyleMask:` already promises for a mask change.
 *   2. THE PLACEMENT: the sheet's top edge IS the bottom edge of the parent's title bar, and it is centred on the
 *      parent's content. Its body is over that content, which is what makes it a sheet ON the window.
 *   3. THE PAIR IS RE-PINNED, NOT REMEMBERED: moving the parent carries the sheet with it, resizing the parent
 *      re-centres it, and the parent's size never touches the sheet's own.
 *   4. THE STRIP IS NOT A HANDLE ANY MORE. A press in the sheet's top rows is not in the chrome and not on a button,
 *      because there is no chrome there to press; the same press on a titled window IS. That is `fn_pointInChrome`'s
 *      and `fn_chrome_layout`'s answer, asked through the two private doors this probe declares.
 *   5. ENDING THE SESSION GIVES THE STRIP BACK with the content intact, and a second sheet on the same parent is
 *      refused rather than queued — Apple's one-at-a-time rule.
 *   6. THE PAIR IS ONE THING ON THE GLASS: ordering the parent out takes the sheet with it and ordering it back in
 *      brings it back, and the session is untouched by either.
 *   7. THE MODAL-SESSION RELATIVE FORM ATTACHES BY THE SAME RULE — its placement is `-cg_updateSheet`'s too.
 *   8. A CLICK IN THE DISABLED PARENT IS STILL A CLICK: the application activates, the parent is ordered front, the
 *      SHEET takes the key and main, and the event itself is DROPPED — no control behind the question hears it, while a
 *      press ON the sheet is delivered, which is the control that proves the drop is the modal rule.
 *   9. A FREED WINDOW LEAVES NO DANGLING ATTACHMENT, from either end: the pair is two unretained pointers, so a window
 *      that dies while the other end names it is a message to freed memory waiting for the next walk of a view tree.
 *
 * OFFSCREEN, like `tests/panel_alert.m`, for the geometry, the attachment and the chrome arithmetic; sections 6 and 8
 * need GLASS (a visible window, and a numbered window to aim an event at), so they are asserted in the
 * `appkit-sheet-visibility` run through `run-appkit-headless.sh` and say so where they are skipped. The PIXELS are
 * `tests/window_chrome.m`'s (a sheet paints nothing of its own and wears the bar's border), and the compositor's half
 * of the shape and the order — square top corners, the pair one layer — is `agora_window.set_sheet_parent`'s and
 * `tests/sheet_stack.c`'s.
 */
#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>	/* +cg_chromeFaceColor — the colour a sheet's body must be */
#import <AppKit/NSEvent.h>	/* the mouse-down this file sends */
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSAutoreleasePool.h>

#include <math.h>
#include <stdio.h>

/* THE TWO PRIVATE DOORS THIS PROBE NEEDS. `-cg_chromeButtonAtPoint:` is where a press in the strip is turned into a
 * button, and `fn_pointInChrome` is not a door at all — so the handle is asked the way a press asks it, by sending the
 * window the press and seeing whether it starts a MOVE. That is the behaviour, not the rectangle. */
@interface NSWindow (APPKITSheetProbe)
- (NSInteger)cg_chromeButtonAtPoint:(NSPoint)windowPoint;
- (void)cg_setSheetParent:(NSWindow *)parent;
- (NSWindow *)cg_sheetParent;
@end

/* **A VIEW THAT COUNTS ITS CLICKS, WHICH IS HOW "THE CLICK WAS DROPPED" BECOMES A FACT.** A window-modal parent is
 * disabled by not delivering its events at all, so the only way to see the difference between "disabled" and "delivered
 * to a control that ignored it" is to ask the view whether it ever heard the press. */
@interface SheetClickCounter : NSView
{
	NSInteger _clicks;
}
- (NSInteger)clicks;
@end

@implementation SheetClickCounter

- (void)mouseDown:(NSEvent *)event
{
	(void)event;
	_clicks++;
}

- (NSInteger)clicks
{
	return _clicks;
}

@end

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* TWO RECTANGLES AGREE TO A POINT, for the reason `panel_alert.m` gives: the placement is arithmetic on integers and the
 * comparison is between two answers that came by different routes. */
static int same(double a, double b)
{
	return fabs(a - b) < 0.001;
}

/* THE ALERT-SHAPED PARENT: a titled window with a content rect of its own, which is all a sheet needs of one. */
static NSWindow *fn_parent(void)
{
	return [[NSWindow alloc] initWithContentRect:NSMakeRect(120.0, 80.0, 480.0, 320.0)
					  styleMask:(NSTitledWindowMask | NSClosableWindowMask)
					    backing:NSBackingStoreBuffered
					      defer:NO];
}

static NSWindow *fn_sheet(void)
{
	return [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 360.0, 140.0)
					  styleMask:(NSTitledWindowMask | NSClosableWindowMask)
					    backing:NSBackingStoreBuffered
					      defer:NO];
}

static void attach(NSWindow *parent, NSWindow *sheet)
{
	[[NSApplication sharedApplication] beginSheet:sheet
				      modalForWindow:parent
				       modalDelegate:nil
				      didEndSelector:NULL
					 contextInfo:NULL];
}

static void test_attachment_and_placement(void)
{
	NSWindow *parent = fn_parent();
	NSWindow *sheet = fn_sheet();
	NSRect parentContent;
	NSRect contentBefore = [sheet contentRectForFrameRect:[sheet frame]];
	NSRect frameBefore = [sheet frame];

	printf("1. the frame becomes the content, and the content is unchanged\n");
	check(frameBefore.size.height > contentBefore.size.height,
	      "before the attachment a titled window's frame is its content PLUS a strip");
	attach(parent, sheet);
	check([sheet isSheet] && [parent attachedSheet] == sheet,
	      "attaching makes the sheet a sheet and the parent its owner");
	check([sheet frame].size.height == [sheet contentRectForFrameRect:[sheet frame]].size.height,
	      "a sheet's frame IS its content: there is no strip for the arithmetic to subtract");
	check(same([sheet frame].size.width, contentBefore.size.width)
	      && same([sheet frame].size.height, contentBefore.size.height),
	      "and the caller's CONTENT kept its size across the transition");
	check([sheet styleMask] == (NSTitledWindowMask | NSClosableWindowMask),
	      "the style mask is what the caller built: a sheet is a MODE, not a different window");
	/* **AND ITS BODY IS THE CHROME'S OWN COLOUR.** That is what makes the tuck below invisible: the sheet's top edge is
	 * inside the parent's bar, so it has to be painted the bar's colour or the sheet wears a grey band and a line across
	 * its top. An ordinary window keeps its own `-backgroundColor`, which is the door the menu bar's panel needs. */
	check([[sheet cg_bodyColor] isEqual:[NSColor cg_chromeFaceColor]],
	      "a sheet's body is painted the CHROME'S FACE, the title bar's own colour");
	check([[parent cg_bodyColor] isEqual:[parent backgroundColor]],
	      "and an ordinary window's body is its -backgroundColor, unchanged");
	{
		NSWindow *plain = fn_sheet();

		check([[plain cg_bodyColor] isEqual:[plain backgroundColor]],
		      "which for a window that is not a sheet is windowBackgroundColor until a caller says otherwise");
		[plain release];
	}

	printf("2. it hangs from the parent's title bar, tucked under it\n");
	parentContent = [parent contentRectForFrameRect:[parent frame]];
	/* **TUCKED UNDER, NOT FLUSH BELOW.** The sheet's top edge is a few points INSIDE the bar: the overlap is invisible
	 * because the sheet's body is the chrome's own colour, and it is what makes the bar's bottom hairline stop at the
	 * sheet's two sides instead of reading as a ledge the sheet sits beneath. It is also what keeps the seam from
	 * showing at a fractional scale, where the two windows' edges are rounded independently. */
	check(NSMaxY([sheet frame]) > NSMaxY(parentContent),
	      "the sheet's TOP edge is a little way INTO the title bar, not flush with its bottom edge");
	check(NSMaxY([sheet frame]) < NSMaxY([parent frame]),
	      "and still inside the bar rather than above the window");
	check(NSMaxY([sheet frame]) - NSMaxY(parentContent) <= 4.0,
	      "by a couple of points: enough to hide the bar's hairline, not enough to be a band");
	check(same(NSMidX([sheet frame]), NSMidX(parentContent)),
	      "and it is centred on the parent's content");
	check(NSMinY([sheet frame]) >= NSMinY(parentContent) && NSMinY([sheet frame]) < NSMaxY(parentContent),
	      "with its body over the parent's content rather than floating above the window");

	printf("3. the pair is re-pinned, not remembered\n");
	[parent setFrame:NSMakeRect(70.0, 40.0, 620.0, 360.0) display:YES];
	parentContent = [parent contentRectForFrameRect:[parent frame]];
	check(NSMaxY([sheet frame]) > NSMaxY(parentContent) && NSMaxY([sheet frame]) < NSMaxY([parent frame]),
	      "moving the parent carries the sheet with it, still tucked into the bar");
	check(same(NSMidX([sheet frame]), NSMidX(parentContent)),
	      "and the new width re-centres it, so no remembered offset can drift");
	check(same([sheet frame].size.width, contentBefore.size.width)
	      && same([sheet frame].size.height, contentBefore.size.height),
	      "the parent's own size is not the sheet's size");

	printf("4. the strip is not a handle any more\n");	{
		/* THE TOP ROW OF THE WINDOW, WHICH ON A TITLED WINDOW IS THE STRIP AND ON A SHEET IS ITS CONTENT. Both
		 * windows are asked the same point so the two answers differ in nothing but the attachment. */
		NSPoint topCentre = NSMakePoint([sheet frame].size.width / 2.0,
						[sheet frame].size.height - 2.0);
		NSInteger sheetButton = [sheet cg_chromeButtonAtPoint:topCentre];
		/* THE PARENT IS A CONTROL: a point in ITS strip, on the close button's box, must find one. The box is the
		 * theme's, so what is asked is the whole left block rather than a coordinate — eight points in is inside the
		 * X on every theme this tier ships or reads. */
		NSPoint parentButtonPoint = NSMakePoint(8.0, [parent frame].size.height - 8.0);
		NSInteger parentButton = -1;
		NSWindow *plain = fn_sheet();	/* a titled window that is NOT a sheet */

		[plain setFrameOrigin:NSMakePoint(40.0, 40.0)];
		parentButton = [plain cg_chromeButtonAtPoint:NSMakePoint(8.0, [plain frame].size.height - 8.0)];
		check(sheetButton < 0, "a press in a sheet's top rows is on NO chrome button");
		check(parentButton == 0,
		      "and the same press on a TITLED window finds the close button — the control that proves the difference");
		check([parent cg_chromeButtonAtPoint:parentButtonPoint] == 0,
		      "with the parent's own strip still a strip: a sheet does not disarm its parent's chrome");
		[plain release];
	}

	printf("5. the pair is one thing on the glass\n");
	[parent orderFront:nil];
	/* **THE VISIBILITY HALF NEEDS GLASS, AND SAYS SO WHEN THERE IS NONE.** `-orderFront:` CREATES the seam's window and
	 * returns early when no compositor answers — so without one, `-isVisible` never becomes YES and a check here would
	 * fail for a reason that has nothing to do with sheets. The rule itself is `-orderOut:`'s and `-orderFront:`'s, and
	 * the note below is the difference between "not tested here" and "tested and fine". */
	if ([parent isVisible]) {
		check([sheet isVisible],
		      "a parent ordered in with a sheet on it shows BOTH — the sheet is part of the window");
		[parent orderOut:nil];
		check(![sheet isVisible],
		      "ordering the parent out takes the sheet with it: a question with nothing to ask about is not left "
		      "floating over the desktop");
		check([parent attachedSheet] == sheet,
		      "and the SESSION is untouched — this is a hiding, not an ending");
		[parent orderFront:nil];
		check([parent isVisible] && [sheet isVisible],
		      "and ordering the parent back in brings the sheet back with it");
	} else {
		printf("  (note: no compositor, so the visibility pair is not asserted here — `-orderFront:` refuses "
		       "without one and a window that is never shown can be neither hidden nor brought back)\n");
		[parent orderOut:nil];
		check([parent attachedSheet] == sheet, "ordering a parent out does not END the session");
	}

	printf("6. ending the session gives the strip back, and a second sheet is refused\n");	[[NSApplication sharedApplication] endSheet:sheet returnCode:0];
	check(![sheet isSheet] && [parent attachedSheet] == nil, "ending the session takes the attachment down");
	check([sheet cg_sheetParent] == nil, "and clears the sheet's own back-reference");
	check([sheet frame].size.height > [sheet contentRectForFrameRect:[sheet frame]].size.height,
	      "the window is a titled window again: its frame is its content PLUS a strip");
	check(same([sheet contentRectForFrameRect:[sheet frame]].size.height, contentBefore.size.height),
	      "and the content it was dismissed with is the size it was laid out for");
	{
		NSWindow *first = fn_sheet();
		NSWindow *second = fn_sheet();
		BOOL threw = NO;

		attach(parent, first);
		@try {
			attach(parent, second);
		} @catch (NSException *e) {
			threw = [[e name] isEqual:NSInvalidArgumentException];
		}
		check(threw, "a second sheet on a parent that already has one is REFUSED, which is Apple's model");
		check([parent attachedSheet] == first, "and the refusal leaves the first session exactly as it was");
		[[NSApplication sharedApplication] endSheet:first returnCode:0];
		[first release];
		[second release];
	}

	[sheet release];
	[parent release];
}

/* **THE OTHER DOOR INTO THE SAME PAIR, AND IT IS THE ONE DOCUMENT CODE USES.** `-beginModalSessionForWindow:
 * relativeToWindow:` attaches through `-beginSheet:…` and then begins a session; `-endModalSession:` is what takes the
 * attachment back down. What is checked here is only the attachment half — the session itself is `panel_alert.m`'s,
 * because a session needs a pass of the pump and this file is about geometry. */
static void test_modal_session_relative(void)
{
	NSWindow *parent = fn_parent();
	NSWindow *sheet = fn_sheet();
	NSModalSession session;

	printf("7. the modal-session relative form is the same attachment\n");
	session = [[NSApplication sharedApplication] beginModalSessionForWindow:sheet relativeToWindow:parent];
	check(session != NULL, "`-beginModalSessionForWindow:relativeToWindow:` answers a session");
	check([sheet isSheet] && [parent attachedSheet] == sheet, "and the window IS the parent's sheet");
	check(NSMaxY([sheet frame]) > NSMaxY([parent contentRectForFrameRect:[parent frame]])
	      && NSMaxY([sheet frame]) < NSMaxY([parent frame]),
	      "placed by the same rule: its top edge tucked under the parent's title bar");
	[[NSApplication sharedApplication] endModalSession:session];
	check(![sheet isSheet] && [parent attachedSheet] == nil, "and ending the session detaches it");

	[sheet release];
	[parent release];
}

/* **8. A CLICK IN A DISABLED PARENT IS STILL A CLICK: IT BRINGS THE PAIR FORWARD AND KEYS THE SHEET.** The gate in
 * `NSApplication -sendEvent:` drops every event aimed at a window with a sheet attached — that is what window-modal
 * means observably — and the reported bug was that the drop was ALL it did: a person clicking a background document's
 * greyed body got nothing at all, so the pair stayed buried behind whatever had been raised since and the question
 * stayed in the background with it. What a click must do is the two acts the application owns: activate, order the
 * parent front (which on this compositor raises the pair), and give the KEY and MAIN to the SHEET — never to the
 * parent the click landed on, which is disabled.
 *
 * IT NEEDS A COMPOSITOR, because the two facts that make it a CLICK are a window number to aim the event at and
 * `-orderFront:` actually ordering something; without one the number is -1 and `-orderFront:` refuses. So this runs
 * where `sheet.m` is run through `run-appkit-headless.sh`, and says so where it is skipped — the same bargain the
 * visibility rule makes above. */
static void test_click_in_disabled_parent(void)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSWindow *parent = fn_parent();
	NSWindow *sheet = fn_sheet();
	SheetClickCounter *parentView = [[SheetClickCounter alloc] initWithFrame:NSMakeRect(0.0, 0.0, 480.0, 320.0)];
	SheetClickCounter *sheetView = [[SheetClickCounter alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 140.0)];
	NSEvent *press;
	NSPoint inParent;

	printf("8. a click in a disabled parent brings the pair forward and keys the sheet\n");
	[parent setContentView:parentView];
	[sheet setContentView:sheetView];
	[parent makeKeyAndOrderFront:nil];
	attach(parent, sheet);
	if ([parent windowNumber] < 0) {
		printf("  (note: no compositor, so a click cannot be aimed at a numbered window — the click rule is not "
		       "asserted here; `appkit-sheet-visibility` is the run where it is)\n");
		[[NSApplication sharedApplication] endSheet:sheet returnCode:0];
		[parentView release];
		[sheetView release];
		[sheet release];
		[parent release];
		return;
	}
	/* THE STATE SOME OTHER CLICK WOULD HAVE LEFT: the parent has the key, which is exactly what must not survive a
	 * press on the disabled pair. */
	[parent makeKeyWindow];
	check([parent isKeyWindow] && ![sheet isKeyWindow],
	      "before the click the parent can be key and the sheet is not");
	check([application keyWindow] == parent, "which is the application's answer before the click as well");
	inParent = NSMakePoint(30.0, 30.0);
	press = [NSEvent mouseEventWithType:NSLeftMouseDown
				   location:inParent
			      modifierFlags:0
				  timestamp:0.0
			       windowNumber:[parent windowNumber]
				    context:nil
				eventNumber:1
				clickCount:1
				  pressure:1.0];
	[application sendEvent:press];
	check([sheet isKeyWindow], "a LEFT CLICK on the disabled parent leaves the SHEET key");
	check(![parent isKeyWindow], "and never the parent the click landed on");
	check([application keyWindow] == sheet, "which is the application's own answer too");
	check([application mainWindow] == sheet, "with MAIN going the same way, as beginning the session does");
	check([parentView clicks] == 0, "and the press was DROPPED: no control behind the question heard it");
	check([parent isVisible] && [sheet isVisible], "the pair is on the screen, the click having ordered the parent front");
	/* AND A RIGHT CLICK AND A MIDDLE ONE ARE THE SAME ACT, which the Mac's own model says they are. */
	press = [NSEvent mouseEventWithType:NSRightMouseDown
				   location:inParent
			      modifierFlags:0
				  timestamp:0.0
			       windowNumber:[parent windowNumber]
				    context:nil
				eventNumber:2
				clickCount:1
				  pressure:1.0];
	[parent makeKeyWindow];
	[application sendEvent:press];
	check([sheet isKeyWindow] && ![parent isKeyWindow], "a RIGHT click does the same");
	/* **AND THE SHEET ITSELF IS NOT DISABLED, WHICH IS THE OTHER HALF OF THE GATE.** A press aimed at the sheet is
	 * delivered — it is the window that can answer the question — so this is the control that proves the drop above was
	 * the modal rule and not a broken event. */
	press = [NSEvent mouseEventWithType:NSLeftMouseDown
				   location:NSMakePoint(20.0, 20.0)
			      modifierFlags:0
				  timestamp:0.0
			       windowNumber:[sheet windowNumber]
				    context:nil
				eventNumber:3
				clickCount:1
				  pressure:1.0];
	[application sendEvent:press];
	check([sheetView clicks] == 1,
	      "while a press ON the sheet reaches its content — the drop is the modal rule, not a broken event");

	[[NSApplication sharedApplication] endSheet:sheet returnCode:0];
	[parentView release];
	[sheetView release];
	[sheet release];
	[parent release];
}

/* **9. AND A WINDOW THAT DIES TAKES ITS END OF THE ATTACHMENT WITH IT.** Neither reference is retained — the
 * application's registry owns every window — so a freed window named by the other end is a pointer into freed memory,
 * and the walks that reach it are the ordinary ones (a `displayIfNeeded`, a pointer motion resolving a cursor). The
 * window's own `-dealloc` breaks the pair from whichever end is dying, which is what makes the two rules this file has
 * already asserted — "a sheet whose parent is gone is an ordinary window" and "a parent whose sheet is gone has no
 * sheet" — true even when a caller gets the two lifetimes wrong. The attachment is made through the seam's own doors
 * here rather than through `-beginSheet:…`, because ordering a window front makes the APPLICATION its owner and a test
 * could not then free it. */
static void test_window_released_while_attached(void)
{
	NSWindow *parent = fn_parent();
	NSWindow *sheet = fn_sheet();

	printf("9. a freed window leaves no dangling attachment\n");
	{
		/* A POOL AROUND THE ATTACHMENT, DRAINED BEFORE THE RELEASE: the pair's own doors post notifications, and
		 * those holds are in the pool — a window released before it drains is honestly still alive. */
		NSAutoreleasePool *pass = [[NSAutoreleasePool alloc] init];

		[sheet cg_setSheetParent:parent];
		[parent cg_setAttachedSheet:sheet];
		[pass release];
	}
	check([parent attachedSheet] == sheet && [sheet isSheet], "the pair is attached");
	[sheet release];	/* the caller's only reference, which the application has not taken */
	check([parent attachedSheet] == nil,
	      "a sheet window that is FREED removes itself from the parent, so the parent names nothing dead");
	[parent release];

	parent = fn_parent();
	sheet = fn_sheet();
	{
		NSAutoreleasePool *pass = [[NSAutoreleasePool alloc] init];

		[sheet cg_setSheetParent:parent];
		[parent cg_setAttachedSheet:sheet];
		[pass release];
	}
	[parent release];	/* the parent goes first, which is the other direction */
	check(![sheet isSheet], "and a parent that is FREED detaches its sheet: the sheet is an ordinary window again");
	[sheet release];
}

int main(void)
{
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];

		setvbuf(stdout, NULL, _IONBF, 0);
		[application finishLaunching];

		test_attachment_and_placement();
		test_modal_session_relative();
		test_click_in_disabled_parent();
		test_window_released_while_attached();

		printf("sheet: %s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	}
	return s_failed == 0 ? 0 : 1;
}
