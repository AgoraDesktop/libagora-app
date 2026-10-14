/*
 * NSApplication — the application object, its window registry and its run loop.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * THE LOOP IS DELIBERATELY BOUNDED AND THAT IS A STATED DEVIATION. Apple's run loop waits in the run loop
 * until an event or a timer wakes it; this tree has no timer service wired into the loop yet, so each pass
 * waits on the CONNECTION for at most a slice. The consequence is the honest one: `-stop:` takes effect
 * within a slice, which an unbounded wait could not offer — a loop that only woke on an event could only be
 * stopped BY an event, and a caller stopping it from a delegate would wait forever.
 *
 * AND THE DRAIN IS THE POINT OF THIS CLASS: an event is not delivered to a window until the APPLICATION asks
 * for it. `-nextEventMatchingMask:` drains the posted queue, then asks every window in the registry, and only
 * waits when none has anything — which is what makes a window's pump part of a program rather than a probe.
 */
#import "AppKitRefusal.h"

/* THE PIECES THE BAR IS MADE OF, named here because this file is where they are used: the seam (for the region the
 * server owns), the window (which owns the connection), and the view that lays a bar out. */
#include "AGWindowServer.h"
#import "NSWindow.h"
#import "NSMenuView.h"
/* **THE MENU'S OWN HEADER, NOT JUST ITS ITEMS'.** `NSMenu` was forward-declared here — enough to write
 * `NSMenu *menu` and not enough to ask it anything: without this the compiler answers `id` for
 * `-numberOfItems` and then refuses to subtract from a pointer. MEASURED as two errors that read like mistakes in
 * the arithmetic rather than like a missing import. */
#import "NSMenu.h"
#import "NSMenuItem.h"
#import "NSColor.h"

#import <Foundation/NSThread.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>
/* NSScreen IS WHAT `-arrangeInFront:` ASKS FOR THE CASCADE'S SEED — the same object NSWindow's own
 * `-cascadeTopLeftFromPoint:` reads its visible frame from. */
#import <AppKit/NSScreen.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNotification.h>
/* NSMutableArray IS DECLARED IN NSArray.h — there is no NSMutableArray.h, which has now cost this
 * session three builds (here, NSPasteboard.m and NSImageRep.m). */
#import <Foundation/NSString.h>

/* THE DELEGATE'S INFORMAL CONTRACT, DECLARED AS A CATEGORY ON NSObject — Apple's own idiom for a delegate
 * that predates the formal protocol, and the shape NSPasteboard's reading/writing contract uses in this
 * library. THE FULL `NSApplicationDelegate` PROTOCOL IS A LATER SLICE AND ITS ROWS STAY OPEN: it carries a
 * long list of members (open-file, print, dock, termination), and declaring the two the launch sends needs is
 * what this slice can honestly assert — a protocol declared with members nothing implements would be the
 * half-measure this tree refuses. */

/* AND THE WINDOW SEAM THIS FILE CALLS, declared here because this is where it is called — the mirror of the
 * registry category below, and the reason the application can wait on the connection it does not own. */
@interface NSWindow (APPKITApplicationSeam)
+ (BOOL)cg_waitForEventInMilliseconds:(long)ms;
@end

/* AND THE EVENT SEAM, WHICH IS THE SAME SHAPE FOR THE SAME REASON: NSEvent owns a monitor registry and a
 * periodic source, and THIS pump is what reads them — `+cg_monitorLocalEvent:` before the dispatch below,
 * `+cg_periodicEventIfDueMatchingMask:` at the top of `-nextEventMatchingMask:…`. That is what makes the
 * registry a store a program can observe rather than a store nothing consults. */
@interface NSEvent (APPKITApplicationEventSeam)
+ (nullable NSEvent *)cg_monitorLocalEvent:(NSEvent *)event;
+ (nullable NSEvent *)cg_periodicEventIfDueMatchingMask:(NSUInteger)mask;
@end

#include <stdio.h>
/* THE SESSION IS HEAP-ALLOCATED AND OPAQUE, so the two names that make it so are C's. */
#include <stdlib.h>

/* THE SEAM A WINDOW REGISTERS ITSELF THROUGH — declared HERE, in the file that uses it, which is this tree's
 * pattern for a private contract crossing a file boundary (the same shape the probes use for the pasteboard's
 * informal protocols). A window cannot appear in the run loop without being in this list, so the list is
 * maintained where windows are made rather than polled for. */
@interface NSApplication (APPKITWindowRegistry)
- (void)cg_addWindow:(NSWindow *)aWindow;
- (void)cg_removeWindow:(NSWindow *)aWindow;
- (void)cg_windowClosed:(NSWindow *)aWindow;
@end

/* AND THE ONE PIECE OF PRIVATE STATE THAT CROSSES A FILE BOUNDARY: `-preventWindowOrdering` records a request and
 * `-cg_preventsWindowOrdering` is how the code that would otherwise order a window — and this class's own probe —
 * asks whether it is standing. A door with no public observation point gets a named seam, which is this tree's
 * pattern rather than exporting the ivar. */
@interface NSApplication (APPKITWindowOrdering)
- (BOOL)cg_preventsWindowOrdering;
@end

/* AND THE SHEET SEAM, WHICH CROSSES THE OTHER WAY: the doors that begin and end a session are this class's, the
 * attachment they operate on is `NSWindow`'s, and this is the contract between them. Four inert accessors and one
 * door that TAKES the reply — named here, implemented in NSWindow.m, and deliberately without a verb that begins
 * or ends anything: the ordering the sheet contract turns on (nothing touches the sheet after the reply runs,
 * because the reply may release it) is then an ordering in ONE method, below, rather than two files agreeing. */
@interface NSWindow (APPKITSheetState)
- (void)cg_setSheetParent:(NSWindow *)parent;
- (NSWindow *)cg_sheetParent;
- (void)cg_setAttachedSheet:(NSWindow *)sheet;
- (void)cg_setSheetReplyDelegate:(id)delegate selector:(SEL)selector contextInfo:(void *)contextInfo;
- (BOOL)cg_takeSheetReplyDelegate:(id *)delegate selector:(SEL *)selector contextInfo:(void **)contextInfo;
@end


/* ============================================================================================ *
 * TELLING THE DELEGATE.                                                                         *
 * ============================================================================================ */

NSString *NSApplicationWillFinishLaunchingNotification = @"NSApplicationWillFinishLaunchingNotification";
/* NOTHING POSTS THIS ONE YET, which is stated rather than left to be found: a screen change is a thing this
 * tier does not notice — the screens come from one X connection and nothing watches it for a change. */
NSString *NSApplicationDidChangeScreenParametersNotification = @"NSApplicationDidChangeScreenParametersNotification";
NSString *NSApplicationDidFinishLaunchingNotification = @"NSApplicationDidFinishLaunchingNotification";
NSString *NSApplicationWillBecomeActiveNotification = @"NSApplicationWillBecomeActiveNotification";
NSString *NSApplicationDidBecomeActiveNotification = @"NSApplicationDidBecomeActiveNotification";
NSString *NSApplicationWillResignActiveNotification = @"NSApplicationWillResignActiveNotification";
NSString *NSApplicationDidResignActiveNotification = @"NSApplicationDidResignActiveNotification";
NSString *NSApplicationWillHideNotification = @"NSApplicationWillHideNotification";
NSString *NSApplicationDidHideNotification = @"NSApplicationDidHideNotification";
NSString *NSApplicationWillUnhideNotification = @"NSApplicationWillUnhideNotification";
NSString *NSApplicationDidUnhideNotification = @"NSApplicationDidUnhideNotification";
NSString *NSApplicationWillUpdateNotification = @"NSApplicationWillUpdateNotification";
NSString *NSApplicationDidUpdateNotification = @"NSApplicationDidUpdateNotification";
NSString *NSApplicationWillTerminateNotification = @"NSApplicationWillTerminateNotification";

/* **ONE RELAY, AS IN THE WINDOW**: every announcement has the same shape, the protocol marks every method
 * optional, and writing the guard out thirteen times would be thirteen chances to forget it. The selector is
 * CHECKED first, which is what makes `-performSelector:withObject:` the right call rather than a cast. */
static void fn_tell_delegate(NSApplication *app, SEL sel, id argument)
{
	id d = [app delegate];

	if (d != nil && [d respondsToSelector:sel]) {
		[d performSelector:sel withObject:argument];
	}
}

/* AND THE DELEGATE IS TOLD BEFORE THE OBSERVERS ARE, so a delegate that acts on a change has done so by the time
 * anything watching for it runs. */
/* THE GLOBAL, defined here because this class is what makes one. */
id NSApp = nil;

static void fn_announce(NSApplication *app, NSString *name, SEL delegateSelector)
{
	fn_tell_delegate(app, delegateSelector, [NSNotification notificationWithName:name object:app]);
	[[NSNotificationCenter defaultCenter] postNotificationName:name object:app];
}

/* AND THE SAME TWO HALVES FOR AN ANNOUNCEMENT ABOUT A WINDOW — with the difference that makes it a function of its
 * own: the notification's OBJECT IS THE WINDOW, not the application. Apple's wording for the sheet pair is explicit
 * ("the NSWindow object that's about to open the sheet"), and this tree's window announcements already post to both
 * the centre and the delegate (`fn_announce` in NSWindow.m), so a sheet that told only one of them would be a gap
 * of this file's own making. */
static void fn_announce_window(NSWindow *w, NSString *name, SEL delegateSelector)
{
	id delegate = [w delegate];
	NSNotification *note = [NSNotification notificationWithName:name object:w];

	if ([delegate respondsToSelector:delegateSelector]) {
		typedef void (*fn_note_t)(id, SEL, NSNotification *);

		((fn_note_t)(void *)[delegate methodForSelector:delegateSelector])(delegate, delegateSelector, note);
	}
	[[NSNotificationCenter defaultCenter] postNotification:note];
}

/* THE PARTS OF THE REPLY STATE NO CALLER HAS BUSINESS WITH: the flag a deferred termination waits on, the last
 * open/print reply, and the ONE tail both termination paths run. */
@interface NSApplication (FNReplySeams)
- (void)cg_finishTermination;
- (BOOL)cg_waitingForTerminateReply;
- (NSApplicationDelegateReply)cg_lastOpenOrPrintReply;
@end

@implementation NSApplication

+ (NSApplication *)sharedApplication
{
	static NSApplication *s_shared;

	if (s_shared == nil) {
		s_shared = [[NSApplication alloc] init];
		/* **AND THE GLOBAL BECOMES THAT OBJECT**, which is the whole of what `NSApp` is: this class makes one
		 * application, so a name for it is a name and not a second variable somebody has to keep in step. */
		NSApp = s_shared;
	}
	return s_shared;
}

/* AND THE ONE C FUNCTION, OUTSIDE THE CLASS'S OWN BLOCK BECAUSE IT IS NOT A MESSAGE. */
BOOL NSApplicationLoad(void)
{
	/* **THE ONE THING THIS CAN HONESTLY DO.** Apple's contract is for a Cocoa bundle loaded into a Carbon
	 * application: it initializes AppKit and other Cocoa objects, and REDUNDANT CALLS ARE IGNORED. This tier has no
	 * Carbon, no bundle loading and no AppKit-wide state to initialize — so the door makes the application object
	 * exist and answers that it is ready, and the redundancy rule falls out of `+sharedApplication` being
	 * idempotent rather than being a second flag to keep. */
	(void)[NSApplication sharedApplication];
	return YES;
}

- (instancetype)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_windows = [[NSMutableArray alloc] init];
	_eventQueue = [[NSMutableArray alloc] init];
	_activationPolicy = NSApplicationActivationPolicyRegular;
	return self;
}

- (void)dealloc
{
	[_windows release];
	[_eventQueue release];
	[super dealloc];
}

- (id)delegate
{
	return _delegate;
}

- (void)setDelegate:(id)anObject
{
	_delegate = anObject;
}

- (NSArray *)windows
{
	/* A COPY, so a caller walking the registry cannot change it behind the loop's back. */
	return [NSArray arrayWithArray:_windows];
}

- (NSWindow *)keyWindow
{
	return _keyWindow;
}

- (NSWindow *)mainWindow
{
	return _mainWindow;
}

- (NSWindow *)windowWithWindowNumber:(NSInteger)windowNum
{
	NSUInteger i;

	for (i = 0; i < [_windows count]; i++) {
		NSWindow *w = [_windows objectAtIndex:i];

		if ([w windowNumber] == windowNum) {
			return w;
		}
	}
	return nil;
}

/* A WINDOW ARRIVES AT THE FRONT (the most recently ordered front is the first the loop drains) and the first
 * one to arrive becomes KEY and MAIN, because an application with a window and no key window has nowhere for
 * a key event to go. */
- (void)cg_addWindow:(NSWindow *)aWindow
{
	if (aWindow == nil || [_windows containsObject:aWindow]) {
		return;
	}
	[_windows insertObject:aWindow atIndex:0];
	if (_keyWindow == nil) {
		_keyWindow = aWindow;
	}
	if (_mainWindow == nil) {
		_mainWindow = aWindow;
	}
}

- (void)cg_removeWindow:(NSWindow *)aWindow
{
	NSUInteger i;

	if (aWindow == nil) {
		return;
	}
	for (i = 0; i < [_windows count]; i++) {
		if ([_windows objectAtIndex:i] == aWindow) {
			[_windows removeObjectAtIndex:i];
			break;
		}
	}
	if (_keyWindow == aWindow) {
		_keyWindow = [_windows count] > 0 ? [_windows objectAtIndex:0] : nil;
	}
	if (_mainWindow == aWindow) {
		_mainWindow = [_windows count] > 0 ? [_windows objectAtIndex:0] : nil;
	}
}

/* THE WINDOW-MENU PAIR, which is bookkeeping rather than a menu: it records which windows the application's
 * window list would show. The menu itself is stage D's. */
- (void)addWindowsItem:(NSWindow *)aWindow title:(NSString *)aString filename:(BOOL)isFilename
{
	(void)aString;
	(void)isFilename;
	[self cg_addWindow:aWindow];
}

- (void)removeWindowsItem:(NSWindow *)aWindow
{
	[self cg_removeWindow:aWindow];
}

- (void)makeWindowsPerform:(SEL)aSelector inOrder:(BOOL)flag
{
	NSUInteger i;

	(void)flag;
	for (i = 0; i < [_windows count]; i++) {
		id w = [_windows objectAtIndex:i];

		if (aSelector != NULL && [w respondsToSelector:aSelector]) {
			[w performSelector:aSelector];
		}
	}
}

/* ---- THE ACTION DOORS ---------------------------------------------------------------------- */

/* `to:nil` MEANS THE RESPONDER CHAIN, and the FIRST responder is where a walk starts: the key window's, then
 * the window itself, then this application — which is the last link, so an action with no target reaches here
 * having walked the whole chain. A nil selector is refused rather than sent. */
- (BOOL)sendAction:(SEL)anAction to:(id)theTarget from:(id)sender
{
	id target = theTarget;

	if (anAction == NULL) {
		return NO;
	}
	if (target == nil) {
		target = [self targetForAction:anAction];
	}
	if (target == nil || ![target respondsToSelector:anAction]) {
		return NO;
	}
	[target performSelector:anAction withObject:sender];
	return YES;
}

- (id)targetForAction:(SEL)anAction
{
	NSResponder *r;

	if (anAction == NULL) {
		return nil;
	}
	/* THE CHAIN, STARTED AT THE KEY WINDOW'S FIRST RESPONDER — which walks view → superview → … → window →
	 * application, because the window's `-nextResponder` is this object. */
	r = [_keyWindow firstResponder];
	if (r == nil) {
		r = _keyWindow;
	}
	while (r != nil) {
		if ([r respondsToSelector:anAction]) {
			return r;
		}
		if (r == self) {
			break;
		}
		r = [r nextResponder];
	}
	return [self respondsToSelector:anAction] ? self : nil;
}

/* ---- LAUNCHING AND RUNNING ------------------------------------------------------------------ */

- (void)finishLaunching
{
	if (_launched) {
		return;
	}
	_launched = YES;
	/* THE DELEGATE'S PAIR, SENT IF IT ANSWERS — the same `-respondsToSelector:` shape every informal contract
	 * in this library uses, so a delegate implements what it cares about. */
	fn_announce(self, NSApplicationWillFinishLaunchingNotification, @selector(applicationWillFinishLaunching:));
	fn_announce(self, NSApplicationDidFinishLaunchingNotification, @selector(applicationDidFinishLaunching:));
}

- (BOOL)isRunning
{
	return _running;
}

/* THE LOOP'S OWN COUNTERS, for the diagnostic above: a static rather than an ivar because they are instrumentation
 * and not state the application has. */
static int s_passes;
static double s_last_report;

- (void)run
{
	[self finishLaunching];
	/* **AGAIN HERE, BECAUSE A MAIN MENU SET BEFORE THE CONNECTION EXISTED HAS NOWHERE TO GO.** An application that
	 * sets its menu and then runs is the ordinary shape, and at `-setMainMenu:` time there may be no server to ask.
	 * This is the second chance, and the door is idempotent: a bar that already exists is merely re-measured. */
	[self cg_updateMenuBarWindow];
	_running = YES;
	_stopped = NO;
	while (!_stopped) {
		/* A POOL PER PASS, because a loop that runs for the life of a process and never drains its own
		 * autoreleased objects grows without bound — the reason a run loop owns a pool at all. */
		id pool = [[NSClassFromString(@"NSAutoreleasePool") alloc] init];
		/* **A SLICE IS A FRAME, NOT A TENTH OF A SECOND.** Every window is updated once per pass, so this number
		 * IS the rate the desktop draws at: MEASURED, 0.1 s gave TEN passes per second — the whole interface
		 * repainting ten times a second and every click waiting up to a tenth of one. A display's frame is the
		 * honest deadline for a loop whose job is to keep windows drawn, and a loop with nothing to do now BLOCKS
		 * on the compositor for the rest of the slice rather than waking to ask. BOTH LOOPS GET IT: this one and
		 * the modal one below draw the same windows and were slow in the same way. */
		NSDate *slice = [NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0];
		NSEvent *e;

		/* THE UPDATE PAIR, ONCE PER PASS: Apple sends these when the loop is about to update the windows and
		 * again when it has, which is what gives a delegate a place to change what is shown BETWEEN passes
		 * rather than in response to an event. */
		fn_announce(self, NSApplicationWillUpdateNotification, @selector(applicationWillUpdate:));
		e = [self nextEventMatchingMask:NSAnyEventMask untilDate:slice inMode:nil dequeue:YES];

		/* **AND AN APPLICATION WHOSE WINDOW SERVER HAS GONE STOPS.** There is nothing left to draw on and no events
		 * will ever come: a loop that keeps turning is a process nobody can tell is dead, and this one kept turning
		 * in front of a person for a minute and a half. Saying so and stopping is the difference between a session
		 * that ended and a session that looks broken. */
		if ([NSWindow cg_connectionIsGone]) {
			fprintf(stderr, "APPKIT-NOTE: the window server has gone — stopping the run loop\n");
			_stopped = YES;
			break;
		}

		/* **HOW FAST THIS LOOP ACTUALLY TURNS, WHICH IS WHAT "SLOW" IS.** Every window is updated once per pass,
		 * so the pass rate IS the frame rate the whole desktop draws at — and the wait below is where that rate is
		 * decided, not here. MEASURED rather than reasoned about, because "the interface feels slow" is a
		 * measurement and this is the instrument for it. */
		if (getenv("APPKIT_LOOP_DIAG") != NULL) {
			double now = [NSDate timeIntervalSinceReferenceDate];

			s_passes++;
			if (s_last_report == 0.0) {
				s_last_report = now;
			}
			if (now - s_last_report >= 1.0) {
				fprintf(stderr, "  DIAG loop: %.1f pass(es) per second\n",
					(double)s_passes / (now - s_last_report));
				s_passes = 0;
				s_last_report = now;
			}
		}
		if (e != nil) {
			[self sendEvent:e];
		}
		/* **AND THE STALE WINDOWS ARE PAINTED, WHICH THE FRAME CALLBACK NO LONGER DOES FOR FREE.** A window's
		 * frame callback now declines to draw unless the window is stale, so SOMETHING has to act on "stale" —
		 * and this is the pass the AppKit gives it. Without this line a window marked for display outside a menu
		 * session would wait for a frame callback that is no longer coming. */
		[self updateWindows];
		fn_announce(self, NSApplicationDidUpdateNotification, @selector(applicationDidUpdate:));
		[pool release];
	}
	_running = NO;
}

- (void)stop:(id)sender
{
	/* THE FLAG THE LOOP READS, set from any thread or any delegate — and the bounded slice above is what
	 * makes it take effect without an event arriving. */
	(void)sender;
	_stopped = YES;
}

- (void)terminate:(id)sender
{
	(void)sender;
	/* **THE APPLICATION IS ASKED BEFORE IT STOPS, AND THE ANSWER CAN STOP IT.** This is why the delegate's
	 * termination callback returns a VALUE: an application with unsaved work refuses here, and a door that asked
	 * and ignored the answer would be worse than one that never asked. */
	if (_delegate != nil && [_delegate respondsToSelector:@selector(applicationShouldTerminate:)]) {
		NSApplicationTerminateReply reply =
			[(id <NSApplicationDelegate>)_delegate applicationShouldTerminate:self];

		if (reply == NSTerminateCancel) {
			return;	/* REFUSED — nothing was announced and nothing stopped */
		}
		if (reply == NSTerminateLater) {
			/* **"MAYBE" IS NOT "YES", AND NOW THE ANSWER HAS SOMEWHERE TO COME FROM.** Apple's header says that
			 * after a `NSTerminateLater` the delegate "must call -replyToApplicationShouldTerminate: with YES or NO
			 * once the application decides if it can terminate" — so this still DOES NOT STOP, and remembers that
			 * the question is open. `-replyToApplicationShouldTerminate:` is what resolves it. */
			_cg_waitingForTerminateReply = YES;
			return;
		}
	}
	[self cg_finishTermination];
}

/* ---- THE TWO REPLIES, AND THE TAIL THEY SHARE -------------------------------------------------------- */

/* **ONE TAIL, SO A LATE YES CANNOT STOP DIFFERENTLY FROM AN IMMEDIATE ONE.** Apple's prose says the reply "must be
 * called with YES or NO once the application decides if it can terminate", and the answer being late is the whole
 * point: by then the application has done whatever it was waiting on, and an immediate yes is no longer the only
 * thing that ends it. */
- (void)cg_finishTermination
{
	fn_announce(self, NSApplicationWillTerminateNotification, @selector(applicationWillTerminate:));
	_stopped = YES;
	_running = NO;
}

- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate
{
	if (!shouldTerminate) {
		/* NO IS AN ANSWER LIKE ANY OTHER: the application keeps running, nothing is announced, and the question is
		 * closed. Apple's prose calls this the case where "the application decides it cannot terminate". */
		_cg_waitingForTerminateReply = NO;
		return;
	}
	_cg_waitingForTerminateReply = NO;
	[self cg_finishTermination];
}

- (void)replyToOpenOrPrint:(NSApplicationDelegateReply)reply
{
	/* RECORDED AND READ BY NOBODY — see the header: nothing in this tier makes an open/print request, so this door
	 * exists for a delegate that calls it unconditionally, and the last reply is KEPT rather than dropped. */
	_cg_lastOpenOrPrintReply = reply;
}

- (NSApplicationDelegateReply)cg_lastOpenOrPrintReply
{
	return _cg_lastOpenOrPrintReply;
}

- (BOOL)cg_waitingForTerminateReply
{
	return _cg_waitingForTerminateReply;
}

/* AND THE ONE QUESTION THAT IS ABOUT THE LAST WINDOW: `NSWindow`'s close tells the application, which asks its
 * delegate whether closing the last one should end the application too. */
- (void)cg_windowClosed:(NSWindow *)aWindow
{
	(void)aWindow;
	if ([[self windows] count] > 0) {
		return;	/* there are windows left, so the question does not arise */
	}
	if (_delegate != nil && [_delegate respondsToSelector:@selector(applicationShouldTerminateAfterLastWindowClosed:)]) {
		if ([(id <NSApplicationDelegate>)_delegate applicationShouldTerminateAfterLastWindowClosed:self]) {
			[self terminate:nil];
		}
	}
}

/* ---- THE PUMP ------------------------------------------------------------------------------- */

- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag
{
	if (event == nil) {
		return;
	}
	if (flag) {
		[_eventQueue insertObject:event atIndex:0];
	} else {
		[_eventQueue addObject:event];
	}
}

- (void)discardEventsMatchingMask:(NSUInteger)mask beforeEvent:(NSEvent *)lastEvent
{
	NSUInteger i = 0;

	(void)lastEvent;
	/* THE MASK IS THE WHOLE TEST; the `beforeEvent:` bound is not expressible over this queue, because a
	 * posted event carries no ordering token to compare — and saying so is better than an approximation that
	 * discarded the wrong ones. */
	while (i < [_eventQueue count]) {
		NSEvent *e = [_eventQueue objectAtIndex:i];

		if ((mask & NSAnyEventMask) || (mask & ((NSUInteger)1 << [e type]))) {
			[_eventQueue removeObjectAtIndex:i];
		} else {
			i++;
		}
	}
}

- (NSEvent *)nextEventMatchingMask:(NSUInteger)mask
			 untilDate:(NSDate *)expiration
			    inMode:(NSString *)mode
			   dequeue:(BOOL)deqFlag
{
	(void)mode;
	for (;;) {
		NSUInteger i;

		/* THE POSTED QUEUE FIRST: an event a caller made did not come from the server and must not wait
		 * behind one that has not arrived. */
		for (i = 0; i < [_eventQueue count]; i++) {
			NSEvent *e = [_eventQueue objectAtIndex:i];

			if ((mask & NSAnyEventMask) || (mask & ((NSUInteger)1 << [e type]))) {
				if (deqFlag) {
					[e retain];
					[_eventQueue removeObjectAtIndex:i];
					return [e autorelease];
				}
				return e;
			}
		}
		/* AND A DUE PERIODIC TICK, once the posted queue is empty: the application armed it by TIME
		 * (`+[NSEvent startPeriodicEventsAfterDelay:withPeriod:]`) and this door is the only one that can
		 * notice, so a tracking loop waits on exactly this method. */
		{
			NSEvent *tick = [NSEvent cg_periodicEventIfDueMatchingMask:mask];

			if (tick != nil) {
				return tick;
			}
		}
		/* THEN EVERY WINDOW, asked with a deadline that has already passed — which is the window's own POLL
		 * form, so no window can block the others out. */
		for (i = 0; i < [_windows count]; i++) {
			NSWindow *w = [_windows objectAtIndex:i];
			NSEvent *e;

			if ([w windowNumber] == -1) {
				continue;
			}
			e = [w nextEventMatchingMask:mask untilDate:[NSDate date] inMode:nil dequeue:deqFlag];
			if (e != nil) {
				return e;
			}
		}
		if (expiration != nil && [expiration timeIntervalSinceNow] <= 0.0) {
			return nil;
		}
		/* AND ONLY THEN THE WAIT, ON THE SERVER'S OWN CONNECTION. A slice rather than the whole remaining
		 * time, so a window that appears mid-wait is drained rather than missed. */
		/* **AND THE WAIT IS THE TIME LEFT, NOT A CONSTANT THAT OVERSHOOTS IT.** A fixed 50 ms under a 16 ms slice
		 * would cap the loop at twenty passes a second however short the slice was — THE WAIT, NOT THE SLICE, IS
		 * WHAT DECIDES. Waiting the remaining time means a pass ends when its deadline does. */
		{
			int wait_ms = 50;

			if (expiration != nil) {
				double left = [expiration timeIntervalSinceNow] * 1000.0;

				wait_ms = (left < 1.0) ? 1 : ((left < 50.0) ? (int)left : 50);
			}
			if (![NSWindow cg_waitForEventInMilliseconds:wait_ms]) {
				if (expiration == nil) {
					continue;
				}
				if ([expiration timeIntervalSinceNow] <= 0.0) {
					return nil;
				}
			}
		}
	}
}

/* THE DISPATCH IS BY WINDOW NUMBER, which is what every event this tree delivers carries and what
 * `-windowWithWindowNumber:`
 * asks for: an event that happened in a window goes to THAT window — and a mouse-down makes it key, because
 * clicking a window is how one becomes key in every system this one resembles. */
/* ---- THE CURRENT EVENT, AND THE DOCK TILE THIS TIER HAS NOT GOT ---------------------------------------- */

/* ---- THE APPLICATION'S LAST ROWS ---------------------------------------------------------------------- */

/* THE ACTIVATION FLAG IS SET BY THE DOORS THAT CHANGE IT, not invented here: `-isActive` reports what
 * `-activateIgnoringOtherApps:` and `-deactivate` already do. */
- (BOOL)isActive
{
	return _active;
}

- (nullable NSArray *)orderedWindows
{
	/* THE SAME LIST `-windows` ANSWERS WITH. Apple orders its own from front to back; this tier does not reorder by
	 * depth because the ordering is the window manager's (D5), which is stated rather than approximated. */
	return [self windows];
}

- (nullable NSArray *)orderedDocuments
{
	/* AN EMPTY ARRAY IS APPLE'S CONTRACT for an application with no open documents, so this is an answer. */
	return [NSArray array];
}

- (void)setApplicationIconImage:(NSImage *)image
{
	[image retain];
	[_applicationIconImage release];
	_applicationIconImage = image;
}

- (nullable NSImage *)applicationIconImage
{
	return _applicationIconImage;
}

- (void)setServicesProvider:(id)provider
{
	_servicesProvider = provider;	/* NOT RETAINED: Apple's own does not own it either */
}

- (nullable id)servicesProvider
{
	return _servicesProvider;
}

- (void)registerServicesMenuSendTypes:(NSArray *)sendTypes returnTypes:(NSArray *)returnTypes
{
	/* RECORDED, AND THE MENU THAT WOULD READ IT DOES NOT EXIST IN THIS TIER — stated rather than implied, because a
	 * caller registering types is entitled to know that nothing consumes them yet. */
	[sendTypes retain];
	[_servicesSendTypes release];
	_servicesSendTypes = sendTypes;
	[returnTypes retain];
	[_servicesReturnTypes release];
	_servicesReturnTypes = returnTypes;
}

- (void)registerUserInterfaceItemSearchHandler:(id)handler
{
	if (_searchHandlers == nil) {
		_searchHandlers = [[NSMutableArray alloc] init];
	}
	if (![_searchHandlers containsObject:handler]) {
		[_searchHandlers addObject:handler];
	}
}

- (void)unregisterUserInterfaceItemSearchHandler:(id)handler
{
	[_searchHandlers removeObject:handler];
}

- (nullable NSString *)searchString
{
	return _searchString;
}

/* THE TWO SEAMS THE PROBE READS THE STORED STATE THROUGH: nothing consumes the search handlers or the registered
 * send types in this tier, so without these the doors would be accepted-but-unobservable — and the probe would have
 * to assert that a call did not crash, which is not a check. The same shape `-cg_flushCount` uses in NSWindow. */
- (NSUInteger)cg_searchHandlerCount
{
	return (_searchHandlers != nil) ? [_searchHandlers count] : 0;
}

- (nullable NSArray *)cg_registeredServicesSendTypes
{
	return _servicesSendTypes;
}

/* ---- THE FOUR MENUS: RECORDED AND RETURNED, WITH THE EFFECT NAMED ------------------------------------- */

/* APPLE'S DOORS RETURN THE MENUS THE APPLICATION OWNS. This tier has no `NSMenu`, so what a setter can honestly do
 * is KEEP WHAT IT WAS GIVEN and what a getter can honestly do is return it: a ported program that sets a main menu
 * and reads it back gets the same object, and the part that cannot be honoured — anything DRAWING that menu — is
 * named in the header instead of silently dropped. */
- (void)setMainMenu:(id)menu
{
	_mainMenu = menu;
	[self cg_arrangeMenuBar];
	/* **AND THE MENUS GO IN THE BAR, WHICH IS WHAT THIS DOOR COULD NOT DO BEFORE.** The header used to say that the
	 * part which cannot be honoured — "anything DRAWING that menu" — was named there rather than silently dropped.
	 * It is honoured now: the server says where the bar's free space begins, `NSMenuView` lays the titles out, and a
	 * window of the application's own holds them. */
	[self cg_updateMenuBarWindow];
}

/* **THE APPLICATION'S OWN MENUS, BESIDE THE SYSTEM MENU.** Three numbers come from the server and one from the
 * menus: where the bar's free space begins, how tall it is, and how wide these menus happen to be.
 *
 * **AND THE WINDOW IS ONLY AS WIDE AS THE MENUS**, not as wide as the region. A bar stretched across the whole free
 * space would swallow clicks meant for the STATUS ITEMS — other CLIENTS at `NSStatusWindowLevel`, one level above
 * this one, which would find themselves under a window that has no business being there. */
- (void)cg_updateMenuBarWindow
{
	AGWindowServer *server = [NSWindow cg_sharedServer];
	int x = 0, y = 0, width = 0, height = 0;
	int screen_width = 0, screen_height = 0;
	CGFloat cocoa_y;
	CGFloat needed;

	if (_mainMenu == nil || server == NULL) {
		return;
	}
	unsigned int rgb = 0;

	AGWindowServerMenuBarArea(server, &x, &y, &width, &height);
	AGWindowServerMenuBarColour(server, &rgb);
	if (width <= 0 || height <= 0) {
		return;		/* a compositor that does not say where the bar's free space begins */
	}
	/* **AND THE ROW IS CONVERTED, BECAUSE THE TWO SIDES COUNT FROM OPPOSITE ENDS.** The server's region is in
	 * OUTPUT coordinates — y downwards, from the TOP, as a display has them — and this class's frames are Cocoa's,
	 * which run UP from the bottom. MEASURED, with the server's y passed straight through: the bar appeared at the
	 * BOTTOM of the screen (its panel pixels reached y = 479 of a 480-row output), which looks like the server
	 * naming the wrong row rather than like an arithmetic mistake here.
	 *
	 * The conversion needs the screen, and the seam already answers that: `AGWindowServerScreenSize`. */
	AGWindowServerScreenSize(server, &screen_width, &screen_height, NULL);
	if (screen_height <= 0) {
		return;		/* no screen described yet, so there is no row to convert into */
	}
	cocoa_y = (CGFloat)(screen_height - (y + height));
	if (_menuBarWindow == nil) {
		NSMenuView *view = [[NSMenuView alloc] initWithFrame:NSMakeRect(0.0, 0.0, (CGFloat)width,
									       (CGFloat)height)];

		[view setHorizontal:YES];
		_menuBarView = view;
		_menuBarWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect((CGFloat)x, cocoa_y, (CGFloat)width,
										 (CGFloat)height)
							     styleMask:NSBorderlessWindowMask
							       backing:NSBackingStoreBuffered
								 defer:NO];
		[_menuBarWindow setLevel:NSMainMenuWindowLevel];
		[_menuBarWindow setContentView:view];
		/* **AND IT IS THE STRIP'S COLOUR, SO THERE IS NO SEAM.** The window's background is what shows between the
		 * titles, and the server's strip is what shows either side of this window — two surfaces a person reads as
		 * ONE BAR, so they had better be the same colour. It is the SERVER's colour because the strip is the
		 * server's: a client that picked one which looked close is how they come to differ. */
		if (rgb != 0u) {
			[_menuBarWindow setBackgroundColor:[NSColor colorWithCalibratedRed:(CGFloat)((rgb >> 16) & 0xFFu) / 255.0
										     green:(CGFloat)((rgb >> 8) & 0xFFu) / 255.0
										      blue:(CGFloat)(rgb & 0xFFu) / 255.0
										     alpha:1.0]];
		}
	}
	[(NSMenuView *)_menuBarView setMenu:(NSMenu *)_mainMenu];
	needed = [(NSMenuView *)_menuBarView requiredWidth];
	if (needed > (CGFloat)width) {
		needed = (CGFloat)width;
	}
	/* **`-setFrame:display:` AND NOT `-setFrame:`.** This tier implements the one Apple's own frame sets all pass
	 * through — `-setFrameOrigin:`, `-setContentSize:` and `-zoom:` go through it too — and the bare `-setFrame:`
	 * is NOT implemented: MEASURED, it raises `-[NSWindow setFrame:] is not implemented` and takes the process with
	 * it, which is how this line was found rather than assumed. */
	if (getenv("APPKIT_MENUBAR_DIAG") != NULL) {
		fprintf(stderr, "  DIAG menubar: region x=%d y=%d %dx%d -> cocoa y=%g, the menus need %g\n", x, y, width,
			height, (double)cocoa_y, (double)needed);
	}
	[_menuBarWindow setFrame:NSMakeRect((CGFloat)x, cocoa_y, needed, (CGFloat)height) display:NO];
	/* **ONLY THE ACTIVE APPLICATION'S MENUS SHOW.** A window that is not in front leaves the bar empty for whoever
	 * is; the `-activate`/`-deactivate` pair is what puts this on the glass and takes it away, and this door only
	 * creates or re-measures. An application that has not been told it is active yet — the compositor says so
	 * asynchronously — will be told, and the bar comes out then. */
	if (_active) {
		[_menuBarWindow orderFront:nil];
	}
}

- (nullable id)mainMenu
{
	return _mainMenu;
}

- (void)setWindowsMenu:(id)menu
{
	_windowsMenu = menu;
}

- (nullable id)windowsMenu
{
	return _windowsMenu;
}

- (void)setServicesMenu:(id)menu
{
	_servicesMenu = menu;
}

- (nullable id)servicesMenu
{
	return _servicesMenu;
}

/* **THE MENU BAR'S SHAPE, WHICH IS THE HIG'S AND NOT EACH APPLICATION'S TO GET RIGHT.** Two rules, and both are
 * about a menu the application did not write:
 *
 *   1. THE FIRST MENU IS THE APPLICATION'S OWN, AND IT IS NAMED AFTER THE APPLICATION. It is put here rather than
 *      asked for, because an application that had to remember would eventually not — and the name is the one thing
 *      on the bar that says WHICH program you are looking at.
 *   2. HELP IS LAST. Wherever the application put it.
 *
 * THIS MUTATES THE MENU IT WAS GIVEN, which is the Mac's own arrangement: `[NSApp mainMenu]` IS the menu bar, its
 * item 0 IS the application menu, and there is no second copy to keep in step. Doing it here rather than deriving a
 * menu also avoids handing an `NSMenuItem` two parents, which nothing in this tree would enjoy.
 *
 * AND IT IS IDEMPOTENT, so setting a main menu twice — or setting one, then setting a help menu — does not stack
 * up application menus. An item already at the front with the application's name IS the application menu. */
- (void)cg_arrangeMenuBar
{
	NSString *appName = [[NSProcessInfo processInfo] processName];
	NSMenu *menu;
	NSArray *items;
	NSMenuItem *first;
	NSMenuItem *help;
	NSInteger i, count;

	if (_mainMenu == nil) {
		return;
	}
	if (appName == nil || [appName length] == 0) {
		appName = @"Application";
	}
	/* **`_mainMenu` IS `id`** — Apple's own type for it, because a main menu may be a nib-loaded object this tier
	 * does not model — SO EVERY DOOR ON IT IS ASKED THROUGH A LOCAL THAT SAYS WHAT IT IS. Without one the compiler
	 * answers `id` for `-numberOfItems` and then does arithmetic on a pointer: MEASURED, two errors, one of them
	 * "arithmetic on pointer to interface 'id'". */
	menu = (NSMenu *)_mainMenu;
	items = [menu itemArray];
	first = ([items count] > 0) ? [items objectAtIndex:0] : nil;
	if (first == nil || ![[first title] isEqualToString:appName]) {
		NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:appName action:NULL keyEquivalent:@""];

		[appItem setSubmenu:[[[NSMenu alloc] initWithTitle:appName] autorelease]];
		[menu insertItem:appItem atIndex:0];
		[appItem release];
	}

	/* AND HELP LAST. `-setHelpMenu:` is the door that says which one it is; a menu merely TITLED "Help" is taken
	 * as the same claim, because an application that has one and never called that door has still written a help
	 * menu and the HIG still puts it last. */
	count = [menu numberOfItems];
	help = (NSMenuItem *)_helpMenu;
	if (help == nil) {
		for (i = 1; i < count; i++) {
			NSMenuItem *item = [menu itemAtIndex:i];

			if ([[item title] isEqualToString:@"Help"]) {
				help = item;
				break;
			}
		}
	}
	if (help != nil && [menu indexOfItem:help] != [menu numberOfItems] - 1) {
		[help retain];
		[menu removeItem:help];
		[menu addItem:help];
		[help release];
	}
}

- (void)setHelpMenu:(id)menu
{
	_helpMenu = menu;
	[self cg_arrangeMenuBar];
}

- (nullable id)helpMenu
{
	return _helpMenu;
}

- (BOOL)isFullKeyboardAccessEnabled
{
	/* A SYSTEM PREFERENCE WITH NO DOOR IN THIS TIER, so the answer is NO rather than a guess at the host's. */
	return NO;
}

- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection
{
	/* LEFT TO RIGHT, which is what this tier lays out — see the enum in the header for why its values are ours. */
	return NSUserInterfaceLayoutDirectionLeftToRight;
}

/* ---- THE EIGHT THAT REFUSE ---------------------------------------------------------------------------- */

- (void)activateContextHelpMode:(id)sender
{
	(void)sender;
	fn_refuse_window("-activateContextHelpMode:", "the Help system");
}

- (void)showHelp:(id)sender
{
	(void)sender;
	fn_refuse_window("-showHelp:", "the Help system, and a Help book to show");
}

- (void)changeWindowsItem:(id)win title:(NSString *)aString filename:(BOOL)isFilename
{
	(void)win; (void)aString; (void)isFilename;
	fn_refuse_window("-changeWindowsItem:title:filename:", "the Windows menu, which this tier has not got");
}

- (void)orderFrontCharacterPalette:(id)sender
{
	(void)sender;
	fn_refuse_window("-orderFrontCharacterPalette:", "the character palette");
}

- (void)orderFrontColorPanel:(id)sender
{
	(void)sender;
	fn_refuse_window("-orderFrontColorPanel:", "NSColorPanel");
}

- (void)orderFrontStandardAboutPanel:(id)sender
{
	(void)sender;
	fn_refuse_window("-orderFrontStandardAboutPanel:", "a panel AND text drawing, neither of which this tier has");
}

- (void)orderFrontStandardAboutPanelWithOptions:(NSDictionary *)optionsDictionary
{
	(void)optionsDictionary;
	fn_refuse_window("-orderFrontStandardAboutPanelWithOptions:", "a panel AND text drawing, neither of which this tier has");
}

- (void)runPageLayout:(id)sender
{
	(void)sender;
	fn_refuse_window("-runPageLayout:", "the page layout panel (NSPageLayout)");
}

/* AND THE ONE THAT IS REAL: Foundation has threads, and this is the pre-10.0 spelling of a door that still works. */
+ (void)detachDrawingThread:(SEL)selector toTarget:(id)target withObject:(id)argument
{
	[NSThread detachNewThreadSelector:selector toTarget:target withObject:argument];
}

- (nullable NSEvent *)currentEvent
{
	/* **THE MOST RECENT EVENT THIS APPLICATION DISPATCHED**, which is what Apple's door reports: the event being
	 * processed while one is, and the last one outside processing. It is recorded in `-sendEvent:` as the dispatch
	 * happens, so the door answers something real instead of nil. NOT RETAINED, as Apple's own is not. */
	return _cg_currentEvent;
}

- (nullable id)dockTile
{
	/* NO `NSDockTile` IN THIS TIER AND NO DOCK TO OWN ONE, so nil is the whole answer. */
	return nil;
}

- (void)sendEvent:(NSEvent *)theEvent
{
	/* THE LOCAL MONITORS RUN BEFORE THE DISPATCH, and they may REPLACE the event — what is dispatched is what
	 * they returned — or DROP it by answering nil, which is Apple's own contract for
	 * `+addLocalMonitorForEventsMatchingMask:handler:` and the reason NSEvent's registry is read from here
	 * rather than from the pump. A DROPPED EVENT IS NOT RECORDED: `-currentEvent` answers the last event that
	 * reached the dispatch machinery, and a dropped one never did. */
	if (theEvent != nil) {
		theEvent = [NSEvent cg_monitorLocalEvent:theEvent];
		if (theEvent == nil) {
			return;
		}
	}
	/* THE RECORD `-currentEvent` ANSWERS FROM, written as the dispatch happens. */
	_cg_currentEvent = theEvent;
	NSWindow *w;

	if (theEvent == nil) {
		return;
	}
	w = [self windowWithWindowNumber:[theEvent windowNumber]];
	if (w == nil) {
		if (getenv("APPKIT_MENU_DIAG") != NULL) {
			fprintf(stderr, "  DIAG dispatch: a type-%ld event for window %ld has NO window and is being "
					"dropped\n", (long)[theEvent type], (long)[theEvent windowNumber]);
		}
		w = _keyWindow;
	}
	if (w == nil) {
		return;
	}
	/* **A WINDOW WITH AN ATTACHED SHEET TAKES NO INPUT** — that is what window-modal MEANS observably, and this is
	 * the one place this tier routes events, so it is where the gate belongs. The event is DROPPED rather than
	 * delivered, and it is dropped BEFORE the mouse-down below could make the parent key: a click that is refused
	 * must not move the key window it was refused for. Apple disables the parent and beeps; the drop is the tier's
	 * version, and the header says so where the doors are declared. The sheet itself carries no attachment of its
	 * own, so events aimed at it are untouched. */
	if ([w attachedSheet] != nil) {
		return;
	}
	/* **A WINDOW THAT IGNORES MOUSE EVENTS PASSES THE EVENT DOWN.** Apple's word for it is transparent: "a Boolean
	 * value that indicates whether the window is transparent to mouse events". So a MOUSE event aimed at such a
	 * window is re-aimed at whatever is beneath it at that point — through the door this class just gained,
	 * `+windowNumberAtPoint:belowWindowWithWindowNumber:`, which asks the same question of the whole application —
	 * and a click that hits nothing of ours is DROPPED rather than delivered to the transparent window (which is
	 * where the cross-application half of that door's answer would have been; its header says so).
	 *
	 * ONLY THE MOUSE-DOWN TYPES THIS PUMP ACTS ON ARE PASSED — the same three the flag's own prose is about, a
	 * click. KEYBOARD EVENTS ARE NOT: a transparent window that is key still takes typing. */
	switch ([theEvent type]) {
	case NSLeftMouseDown:
	case NSRightMouseDown:
	case NSOtherMouseDown: {
		NSUInteger guard = 0;

		while (w != nil && [w ignoresMouseEvents] && guard++ < 64) {
			NSPoint p = [theEvent locationInWindow];
			NSRect f = [w frame];
			NSInteger below = [NSWindow windowNumberAtPoint:NSMakePoint(f.origin.x + p.x, f.origin.y + p.y)
					       belowWindowWithWindowNumber:(NSInteger)[w windowNumber]];
			NSWindow *next = (below != 0) ? [self windowWithWindowNumber:below] : nil;

			if (next == w) {
				break;	/* the door answered the same window, which it should not — a loop is no place to trust that */
			}
			w = next;
		}
		if (w == nil) {
			return;	/* nothing of this application is there: the click is dropped, and the header says why */
		}
		break;
	}
	default:
		break;
	}
	switch ([theEvent type]) {
	case NSLeftMouseDown:
	case NSRightMouseDown:
	case NSOtherMouseDown:
		_keyWindow = w;
		_mainWindow = w;
		break;
	default:
		break;
	}
	[w sendEvent:theEvent];
}

/* ---- ACTIVATION AND HIDING ------------------------------------------------------------------ */

/* WITH NO WINDOW MANAGER OF THIS TREE'S OWN, activation is the APPLICATION's state and the window verbs it
 * implies — stated rather than pretending to negotiate with a manager that is parked. What it really does is
 * keep `-isActive` honest and bring the windows back when the application is unhidden. */
- (void)activateIgnoringOtherApps:(BOOL)flag
{
	/* `-isActive` REPORTS THIS, so the flag is set where the state changes. */
	_active = YES;
	NSUInteger i;

	(void)flag;
	fn_announce(self, NSApplicationWillBecomeActiveNotification, @selector(applicationWillBecomeActive:));
	_hidden = NO;
	for (i = 0; i < [_windows count]; i++) {
		if (!_preventsOrdering && _keyWindow == [_windows objectAtIndex:i]) {
			[[_windows objectAtIndex:i] orderFront:nil];
		}
	}
	/* **AND THE MENU BAR COMES BACK, BECAUSE IT IS THE ACTIVE APPLICATION'S THAT SHOWS.** Only this application's
	 * own menus are in this window — the bar's strip and its System menu belong to the server — so showing it is
	 * exactly "show the active application's menus". */
	if (_menuBarWindow != nil) {
		[_menuBarWindow orderFront:nil];
	}
}

- (void)activate
{
	[self activateIgnoringOtherApps:NO];
	/* THE OTHER HALF OF THE PAIR, so the two doors are not the same door with two names: this is the one that says
	 * the application HAS the focus, and the one above says it is about to get it. */
	fn_announce(self, NSApplicationDidBecomeActiveNotification, @selector(applicationDidBecomeActive:));
}

- (void)deactivate
{
	/* `-isActive` REPORTS THIS, so the flag is set where the state changes. */
	_active = NO;
	/* **AND THE MENU BAR GOES WITH IT, so only the application in front shows menus.** The window is not DESTROYED —
	 * `-orderOut:` is the door that takes it off the glass and leaves it to be shown again, which is what an
	 * application being activated and deactivated repeatedly needs. */
	if (_menuBarWindow != nil) {
		[_menuBarWindow orderOut:nil];
	}
	/* NOTHING TO GIVE UP: there is no manager to give the focus to. The state that matters — which window is
	 * key — is left where it is, because a deactivated application still owns its key window. */
	fn_announce(self, NSApplicationWillResignActiveNotification, @selector(applicationWillResignActive:));
	/* **AND THE WINDOWS THAT ASKED TO BE HIDDEN WHEN THIS HAPPENS ARE HIDDEN, AND REMEMBERED.** Only a window that
	 * is VISIBLE is taken and remembered: a window the caller had already ordered out must not be ours to bring
	 * back, and remembering it would do exactly that. */
	{
		NSUInteger i;

		for (i = 0; i < [_windows count]; i++) {
			NSWindow *w = [_windows objectAtIndex:i];

			if ([w hidesOnDeactivate] && [w isVisible]) {
				if (_cg_deactivatedWindows == nil) {
					_cg_deactivatedWindows = [[NSMutableArray alloc] init];
				}
				[_cg_deactivatedWindows addObject:w];
				[w orderOut:nil];
			}
		}
	}
	fn_announce(self, NSApplicationDidResignActiveNotification, @selector(applicationDidResignActive:));
}

- (void)hide:(id)sender
{
	NSUInteger i;

	(void)sender;
	fn_announce(self, NSApplicationWillHideNotification, @selector(applicationWillHide:));
	_hidden = YES;
	for (i = 0; i < [_windows count]; i++) {
		NSWindow *w = [_windows objectAtIndex:i];

		/* **AND A WINDOW THAT REFUSES IS SKIPPED** — Apple's own comment on `-canHide` says what this door is for:
		 * "indicate whether a window can be hidden during -[NSApplication hide:]". */
		if ([w canHide]) {
			[w orderOut:nil];
		}
	}
	fn_announce(self, NSApplicationDidHideNotification, @selector(applicationDidHide:));
}

- (void)unhide:(id)sender
{
	(void)sender;
	fn_announce(self, NSApplicationWillUnhideNotification, @selector(applicationWillUnhide:));
	[self activate];
	fn_announce(self, NSApplicationDidUnhideNotification, @selector(applicationDidUnhide:));
}

- (void)unhideWithoutActivation
{
	NSUInteger i;

	fn_announce(self, NSApplicationWillUnhideNotification, @selector(applicationWillUnhide:));
	_hidden = NO;
	/* WHILE ORDERING IS PREVENTED NOTHING COMES FORWARD — see `-preventWindowOrdering`. */
	if (_preventsOrdering) {
		return;
	}
	for (i = 0; i < [_windows count]; i++) {
		[[_windows objectAtIndex:i] orderFront:nil];
	}
}

- (void)hideOtherApplications:(id)sender
{
	(void)sender;
	fprintf(stderr, "APPKIT-REFUSE: -hideOtherApplications: needs a window manager to hide the OTHER "
			"applications with, and this tree has none (Kestrel is parked)\n");
}

- (void)unhideAllApplications:(id)sender
{
	(void)sender;
	fprintf(stderr, "APPKIT-REFUSE: -unhideAllApplications: needs a window manager, as its hide peer does\n");
}

/* ---- THE PRESENTATION OPTIONS ----------------------------------------------------------------- */

/* SEE THE HEADER FOR THE VALUES, FOR THE ONE RULE APPLE'S PROSE STATES, AND FOR WHAT THESE DO NOT DO. The check
 * below is the contradictory pair and nothing more, because the rest of Apple's table lives in documentation this
 * tree does not hold — a tier that guessed at the legal combinations would refuse requests Apple accepts, which is
 * worse than recording a request it cannot act on. */
static const struct {
	NSUInteger appears;
	NSUInteger unavailable;
	const char *what;
} fn_presentation_pairs[] = {
	{ NSApplicationPresentationAutoHideDock, NSApplicationPresentationHideDock, "the Dock" },
	{ NSApplicationPresentationAutoHideMenuBar, NSApplicationPresentationHideMenuBar, "the menu bar" }
};

- (NSApplicationPresentationOptions)presentationOptions
{
	return _presentationOptions;
}

- (void)setPresentationOptions:(NSApplicationPresentationOptions)newOptions
{
	NSUInteger i;

	for (i = 0; i < sizeof(fn_presentation_pairs) / sizeof(fn_presentation_pairs[0]); i++) {
		if ((newOptions & fn_presentation_pairs[i].appears) && (newOptions & fn_presentation_pairs[i].unavailable)) {
			/* APPLE'S OWN INSTRUCTION IS AN EXCEPTION, and the pair is named so the message says which two
			 * flags cannot stand together — the same shape the length checks on the arrow below use. The
			 * PREVIOUS OPTIONS STAND: a request that was refused did not happen. */
			[NSException raise:NSInvalidArgumentException
				    format:@"-setPresentationOptions: cannot ask for %s to appear when moused to AND to be "
					   @"unavailable: those two flags contradict each other",
				    fn_presentation_pairs[i].what];
		}
	}
	_presentationOptions = newOptions;
}

- (NSApplicationPresentationOptions)currentSystemPresentationOptions
{
	return _presentationOptions;
}

- (NSInteger)activationPolicy
{
	return _activationPolicy;
}

- (BOOL)setActivationPolicy:(NSInteger)activationPolicy
{
	_activationPolicy = activationPolicy;
	return YES;
}

- (void)reportException:(NSException *)theException
{
	/* THE LOOP REPORTS AND CARRIES ON, which is Apple's contract: an exception that escaped a delegate is a
	 * fact about that call, not a reason to end the process. */
	fprintf(stderr, "APPKIT-EXCEPTION: %s: %s\n",
		[[theException name] UTF8String] != NULL ? [[theException name] UTF8String] : "(unnamed)",
		[[theException reason] UTF8String] != NULL ? [[theException reason] UTF8String] : "(no reason)");
}


/* ---- THE DOORS THAT DRIVE THE WINDOWS' DRAWING ----------------------------------------------- */

- (void)setWindowsNeedUpdate:(BOOL)flag
{
	NSUInteger i;

	for (i = 0; i < [_windows count]; i++) {
		[[_windows objectAtIndex:i] setViewsNeedDisplay:flag];
	}
}

- (void)updateWindows
{
	NSUInteger i;

	for (i = 0; i < [_windows count]; i++) {
		[[_windows objectAtIndex:i] displayIfNeeded];
	}
}

- (void)updateWindowsItem:(NSWindow *)aWindow
{
	(void)aWindow;
	fprintf(stderr, "APPKIT-REFUSE: -updateWindowsItem: updates the WINDOW MENU's row for a window, and the "
			"menu bar is stage D\n");
}

/* ============================================================================================ *
 * THE MODAL SESSION.                                                                            *
 *                                                                                                *
 * A MODAL WINDOW IS NOT A FLAG — it is a NESTED LOOP, and what makes it nested here is that it  *
 * runs the SAME `-nextEventMatchingMask:` the run loop runs, ONE PASS AT A TIME. That is why    *
 * `-runModalForWindow:` is a loop over `-runModalSession:` rather than a second event system:   *
 * there is one pump in this class, and a session is a different way out of it.                  *
 * ============================================================================================ */

NSString *NSModalPanelRunLoopMode = @"NSModalPanelRunLoopMode";
/* AND ITS SIBLING, declared after the same fashion and honoured to the same degree: see the header's note. */
NSString *NSEventTrackingRunLoopMode = @"NSEventTrackingRunLoopMode";

- (void)beginSheet:(NSWindow *)sheet
    modalForWindow:(NSWindow *)docWindow
     modalDelegate:(id)modalDelegate
    didEndSelector:(SEL)didEndSelector
       contextInfo:(void *)contextInfo
{
	NSRect parentFrame, sheetFrame;

	if (sheet == nil || docWindow == nil) {
		/* Apple's door takes two windows. With either missing there is nothing to attach, so a nil gets nothing
		 * rather than a half-attachment in which one window believes it is a sheet. */
		return;
	}
	if ([docWindow attachedSheet] != nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-beginSheet:modalForWindow: — %@ already has a sheet attached, and Apple's model "
				   @"attaches one at a time: end that session before beginning this one",
			    docWindow];
	}
	/* AND THE WINDOW IS TOLD IT IS ABOUT TO OPEN A SHEET, before anything about it changes: "about to open" is
	 * the moment, so an observer asking `-attachedSheet` here is told nil and is being told the truth. */
	fn_announce_window(docWindow, NSWindowWillBeginSheetNotification, @selector(windowWillBeginSheet:));

	/* THE ATTACHMENT, AND THEN THE PLACEMENT — which is OURS, because this tier places its own windows: the sheet
	 * is centred horizontally on its parent with its TOP EDGE at the parent's top, that being what makes it read
	 * as hanging from the window it belongs to. A frame's origin is its BOTTOM-left, so the y is the parent's top
	 * minus the sheet's height. ONLY THE ORIGIN IS MOVED, which is also why `-setFrameOrigin:` is the door: a
	 * sheet's SIZE is the sheet's own — it is a whole window the caller made — and a caller that wants a smaller
	 * one makes a smaller window rather than asking this door to resize it. */
	parentFrame = [docWindow frame];
	sheetFrame = [sheet frame];
	[sheet setFrameOrigin:NSMakePoint(
		parentFrame.origin.x + (parentFrame.size.width - sheetFrame.size.width) / 2.0,
		parentFrame.origin.y + parentFrame.size.height - sheetFrame.size.height)];
	[sheet cg_setSheetParent:docWindow];
	[docWindow cg_setAttachedSheet:sheet];
	[docWindow cg_setSheetReplyDelegate:modalDelegate selector:didEndSelector contextInfo:contextInfo];
	[sheet orderFront:nil];
	/* AND THE SHEET HAS THE KEY, which is the other half of window-modal: the application's own idea of where input
	 * goes. There is no `-makeKeyWindow` call here because this class's key window IS that idea — the same state
	 * `-sendEvent:` sets on a click — and the X focus is a separate negotiation nothing in this tier asks for. */
	_keyWindow = sheet;
	_mainWindow = sheet;
}

- (void)endSheet:(NSWindow *)sheet
{
	/* THE CODE IS OURS AND IT IS ZERO, for the reason the header gives where the door is declared. */
	[self endSheet:sheet returnCode:0];
}

- (void)endSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode
{
	NSWindow *docWindow;
	id delegate = nil;
	SEL selector = NULL;
	void *contextInfo = NULL;
	BOOL owesReply;
	typedef void (*fn_sheet_did_end_t)(id, SEL, NSWindow *, NSInteger, void *);

	if (sheet == nil) {
		return;
	}
	docWindow = [sheet cg_sheetParent];
	if (docWindow == nil) {
		/* ENDING A SESSION THAT IS NOT RUNNING IS NOT AN ERROR, for the reason `-stopModal` with none is not
		 * either: a caller unwinding from a failure ends sessions it is not sure it began. */
		return;
	}
	/* KEY GOES BACK TO THE PARENT FIRST, so that a reply which asks who has the key is told the truth. */
	if (_keyWindow == sheet) {
		_keyWindow = docWindow;
	}
	if (_mainWindow == sheet) {
		_mainWindow = docWindow;
	}
	/* THE REPLY IS TAKEN BEFORE ANYTHING ELSE IS UNDONE, and the record is cleared as it is read. */
	owesReply = [docWindow cg_takeSheetReplyDelegate:&delegate selector:&selector contextInfo:&contextInfo];
	/* AND THE SESSION ENDS WITH THE ATTACHMENT — Apple's prose makes the ORDER-OUT the caller's job, so what has
	 * ended here is the modal session, not the window. Both references go, including the sheet's back-reference,
	 * and BOTH GO BEFORE THE CALLBACK: after it, the reply is free to have released the sheet, and the one rule
	 * this method turns on is that nothing here touches the sheet again. */
	[sheet cg_setSheetParent:nil];
	[docWindow cg_setAttachedSheet:nil];
	/* AND THE SESSION IS ANNOUNCED AS ENDED — before the reply runs, because a reply may release the sheet and the
	 * announcement's object is the PARENT (which the caller still owns). Apple posts this one when the sheet has
	 * finished animating offscreen; nothing here animates, so the end of the session is that moment, which the
	 * header states. */
	fn_announce_window(docWindow, NSWindowDidEndSheetNotification, @selector(windowDidEndSheet:));
	if (!owesReply) {
		return;
	}
	{
		/* THE REPLY IS A BARE SELECTOR, so it is called through a function pointer of the shape Apple's own header
		 * declares for it. The cast goes through `void *` because the runtime's `IMP` is VARIADIC while this
		 * signature is fixed, and a direct function-to-function cast is the one shape clang calls incompatible. */
		fn_sheet_did_end_t fn_end = (fn_sheet_did_end_t)(void *)[delegate methodForSelector:selector];

		if (fn_end != NULL) {
			fn_end(delegate, selector, sheet, returnCode, contextInfo);
		}
	}
}

/* **THE SESSION ITSELF, PRIVATE AND HEAP-ALLOCATED.** Apple's `NSModalSession` is an opaque pointer, so nothing
 * outside this file knows this shape — and what a session has to carry is exactly three things: the window the
 * loop is spending its passes on (BORROWED — the caller owns it), the code it will end with, and whether it has
 * ended. */
struct _NSModalSession {
	NSWindow *window;
	NSInteger code;
	BOOL ended;
};

- (NSModalSession)beginModalSessionForWindow:(NSWindow *)theWindow
{
	struct _NSModalSession *s;

	if (theWindow == nil) {
		/* A SESSION WITH NO WINDOW IS NOT A SESSION, and answering NULL is how a caller learns that rather than
		 * getting a session whose every pass does nothing. */
		return NULL;
	}
	s = (struct _NSModalSession *)calloc(1, sizeof(*s));
	if (s == NULL) {
		return NULL;    /* an allocation failure is not a modal session either, and the caller checks this one */
	}
	s->window = theWindow;
	s->code = NSRunContinuesResponse;
	_modalSession = s;
	_modalWindow = theWindow;
	/* THE WINDOW IS BROUGHT FORWARD AND MADE KEY, which is what makes a modal window behave like one: the
	 * application's input goes to it. WITH NO SERVER that is the window's own refusal rather than a failure. */
	[theWindow makeKeyAndOrderFront:nil];
	return (NSModalSession)s;
}

- (NSInteger)runModalSession:(NSModalSession)session
{
	struct _NSModalSession *s = (struct _NSModalSession *)session;

	if (s == NULL) {
		return NSRunAbortedResponse;
	}
	if (s->ended) {
		return s->code; /* ASKING AN ENDED SESSION AGAIN ANSWERS THE SAME CODE, not a fresh one */
	}
	/* **ONE PASS OF THE PUMP THIS CLASS ALREADY HAS.** The mode is NAMED rather than dropped — it is the value
	 * `NSModalPanelRunLoopMode` carries — but `-nextEventMatchingMask:` says of itself that it does not route by
	 * one yet: a caller relying on the distinction would be relying on nothing, and this is where that is said. */
	{
		/* **A SLICE IS A FRAME, NOT A TENTH OF A SECOND.** Every window is updated once per pass, so this number
		 * IS the rate the desktop draws at: MEASURED, 0.1 s gave TEN passes per second — the whole interface
		 * repainting ten times a second and every click waiting up to a tenth of one. A display's frame is the
		 * honest deadline for a loop whose job is to keep windows drawn, and a loop with nothing to do now BLOCKS
		 * on the compositor for the rest of the slice rather than waking to ask. BOTH LOOPS GET IT: this one and
		 * the modal one below draw the same windows and were slow in the same way. */
		NSDate *slice = [NSDate dateWithTimeIntervalSinceNow:1.0 / 60.0];
		NSEvent *e = [self nextEventMatchingMask:NSAnyEventMask
					   untilDate:slice
						  inMode:NSModalPanelRunLoopMode
						 dequeue:YES];

		if (e != nil) {
			[self sendEvent:e];
		}
	}
	/* AND THE APPLICATION BEING STOPPED ENDS THE SESSION TOO — otherwise `-stop:` while a modal loop is running
	 * would leave it spinning with nothing to stop it. */
	if (_stopped) {
		s->ended = YES;
		s->code = NSRunAbortedResponse;
	}
	return s->ended ? s->code : NSRunContinuesResponse;
}

- (void)endModalSession:(NSModalSession)session
{
	struct _NSModalSession *s = (struct _NSModalSession *)session;

	if (s == NULL) {
		return; /* ending no session is not an error, for the reason `-stopModal` with none is not either */
	}
	if (_modalSession == s) {
		_modalSession = NULL;
		_modalWindow = nil;
	}
	free(s);
}

- (NSInteger)runModalForWindow:(NSWindow *)theWindow
{
	NSModalSession s = [self beginModalSessionForWindow:theWindow];
	NSInteger code;

	if (s == NULL) {
		return NSRunAbortedResponse;
	}
	/* **UNBOUNDED, WHICH IS APPLE'S CONTRACT AND A REAL HAZARD FOR A CALLER.** The ways out are `-stopModal`,
	 * `-abortModal`, the application being stopped — and nothing else. A test therefore drives the SESSION doors
	 * above and leaves this one to code that can be stopped from a callback; this class's own probe never calls
	 * it, because a probe that did would hang rather than fail. */
	for (;;) {
		code = [self runModalSession:s];
		if (code != NSRunContinuesResponse) {
			break;
		}
	}
	[self endModalSession:s];
	return code;
}

- (void)stopModal
{
	[self stopModalWithCode:NSRunStoppedResponse];
}

- (void)stopModalWithCode:(NSInteger)returnCode
{
	struct _NSModalSession *s = (struct _NSModalSession *)_modalSession;

	/* WITH NO SESSION IN FLIGHT THERE IS NOTHING TO STOP and nothing is announced: `-stopModal` is a message to a
	 * loop, and a loop that is not running has no reason to hear it. */
	if (s == NULL) {
		return;
	}
	s->ended = YES;
	s->code = returnCode;
}

- (void)abortModal
{
	[self stopModalWithCode:NSRunAbortedResponse];
}

- (NSWindow *)modalWindow
{
	return _modalWindow;
}

/* ---- THE DOORS THAT ACT ON EVERY WINDOW AT ONCE --------------------------------------------- */

/* `-arrangeInFront:` REUSES THE CASCADE THE PLACEMENT WORK ALREADY BUILT: `-cascadeTopLeftFromPoint:` places a
 * window AND answers where the next one goes, which is exactly what arranging every window needs, and a second
 * copy of that arithmetic would be a second thing to keep true.
 *
 * THE SEED IS THE SCREEN'S TOP-LEFT CORNER, asked through `NSScreen` rather than by opening the seam here: this file
 * does not own the connection, and a second one would be a second thing to close. WITH NO SCREEN the seed is the
 * origin and the cascade still walks. */
- (void)arrangeInFront:(id)sender
{
	NSPoint next = NSMakePoint(0.0, 0.0);
	NSScreen *screen = [NSScreen mainScreen];
	NSUInteger i;

	(void)sender;
	if (screen != nil) {
		NSRect visible = [screen visibleFrame];

		next = NSMakePoint(visible.origin.x, visible.origin.y + visible.size.height);
	}
	/* THE REGISTRY IS FRONT-FIRST, so the window that was already in front keeps the seed and the rest cascade
	 * behind it — which is what "arrange in front" means. */
	for (i = 0; i < [_windows count]; i++) {
		next = [[_windows objectAtIndex:i] cascadeTopLeftFromPoint:next];
	}
}

- (void)miniaturizeAll:(id)sender
{
	NSUInteger i;

	(void)sender;
	/* THE SAME DOOR THE TITLE BAR'S BUTTON SENDS, applied to each window — so a window that miniaturizes itself one
	 * way does not miniaturize itself another way here, and a window already down gets no second will/did pair
	 * (NSWindow's own guard). */
	for (i = 0; i < [_windows count]; i++) {
		[[_windows objectAtIndex:i] miniaturize:nil];
	}
}

- (void)preventWindowOrdering
{
	/* **WHAT THIS SUPPRESSES IN THIS TIER, SAID RATHER THAN IMPLIED.** Apple's door stops the APPLICATION from
	 * ordering windows in response to a user action — a window being dragged, typically — and there is no drag in
	 * this tier. What IS here is the ordering the application does on its own behalf: activating and unhiding
	 * bring the key window forward, and both consult this flag (see `-activateIgnoringOtherApps:`). There is no
	 * public counterpart that LIFTS it, in Apple's era header or here, so the request is one-way by construction.
	 */
	_preventsOrdering = YES;
}

/* AND THE SEAM THAT REPORTS IT — see the category above, where it is declared and why. */
- (BOOL)cg_preventsWindowOrdering
{
	return _preventsOrdering;
}

/* ---- AND THE USER'S ATTENTION ---------------------------------------------------------------- */

- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)requestType
{
	/* **THE REQUEST IS RECORDED, NOT DISPLAYED, AND THAT IS SAID RATHER THAN FAKED.** Apple's version bounces the
	 * dock icon; there is no dock in this tier, so what is real here is the BOOKKEEPING — a request answers an ID
	 * of its own (a counter, because nothing else in this tree identifies one), and a second request while one is
	 * outstanding is a SECOND ID. The KIND is accepted and not stored: nothing in this tier would read it, and
	 * carrying a value nobody reads is the half-measure this tree refuses. */
	(void)requestType;
	_attentionCounter++;
	return _attentionCounter;
}

- (void)cancelUserAttentionRequest:(NSInteger)request
{
	/* AND CANCELLING IS BY ID, so a caller cancelling a request it does not hold is asking about a request that is
	 * not there — which is not an error and is not announced. There is nothing to stop either: no bounce is
	 * running. */
	(void)request;
}

@end


/* THE ONE IMPORT THIS SLICE ADDS, and it is here rather than at the top because it is this slice's alone: a second
 * sheet on the same window is a CALLER ERROR, and this tree reports one by name rather than by silence. */
#import <Foundation/NSException.h>


/* **AND WHY THE DOORS ARE NOT DECLARED HERE WITH THE SEAM.** The seam crosses a file boundary, so it is declared
 * where it is called; the doors are this class's own API and belong in its own implementation block — clang
 * refuses an incomplete implementation (a method declared in the class and defined in a category is exactly that)
 * and warns about a category that re-implements its primary class. The slice still reads as one thing: the doors
 * sit beside the modal sessions they are built on. */
