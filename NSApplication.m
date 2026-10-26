/*
 * NSApplication — the application object, its window registry and its run loop.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **EVERY PASS GIVES THE RUN LOOP A TURN AND THEN WAITS ON THE CONNECTION, AND THE FIRST HALF IS WHAT MAKES TIMERS
 * RUN.** `NSRunLoop` is CoreFoundation's loop (see `libagora-base/NSRunLoop.m`), so one `-runMode:` pass delivers
 * a due `NSTimer`, an fd source's readiness, a `-performSelectorOnMainThread:` from a worker and — on the main
 * thread, in a common mode — the main dispatch queue's port. That pass is taken once per frame, BEFORE the events
 * are read, which is the AppKit's own ordering: a timer fires, a view is marked dirty, and this frame paints it.
 *
 * **AND THE WAIT IS THE RUN LOOP'S, WITH THE COMPOSITOR'S DESCRIPTOR AS ONE OF ITS SOURCES.** `NSWindow` registers
 * the connection with the run loop where the connection is made (see its `fn_install_connection_source`), so the
 * frame's wait covers the compositor, the timers, the fd sources, a performer from another thread and the main
 * dispatch queue in ONE call — `-fnRunMode:forSeconds:returnAfterWork:`, which returns the moment anything was
 * delivered and otherwise at the frame's deadline (or the seam's own, when a held key's repeat is due sooner).
 * Nothing is polled: the compositor's events arrive because the loop was woken by its descriptor, not because a
 * pass asked the connection whether it had anything.
 *
 * **AND `-nextEventMatchingMask:untilDate:inMode:dequeue:` WAITS IN THE SAME PLACE**, so a hand-pumped loop is not a
 * second kind of loop: it reaches the timers, the sources and the main dispatch queue while it waits, and the
 * connection is one of the sources it is waiting on rather than a timeout around them.
 *
 * The consequence is still the honest one: the wait is BOUNDED, by the frame in the loop and by the caller's own
 * deadline (or the old fifty milliseconds) in the door, so `-stop:` takes effect within one of those even though a
 * wake on input would have returned at once — a loop that only woke on an event could only be stopped BY an event,
 * and a caller stopping it from a delegate would wait forever.
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
#import "NSDockMenu.h"
#import "NSDockTile.h"	/* the ids a tile's menu crosses by, and the tree they name */
#import "NSColor.h"
#import "NSPrintInfo.h"
#import "NSPageLayout.h"
#import "NSDocumentController.h"
#import "NSPrintOperation.h"

#import <Foundation/NSThread.h>
#import <Foundation/NSRunLoop.h>
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
/* ⚠⚠ AND THE CONNECTION ITSELF (2026-10-21), which `-cg_updateMenuBarWindow` below asks for. NSWindow.m declared
 * this door on the class body IN ITS OWN TRANSLATION UNIT, so every caller in another file was answered `id` for
 * it and `AGWindowServer *server = [NSWindow cg_sharedServer]` was diagnosed as initializing a pointer with `id`
 * — an error that reads as a mistake in this file. It is not: it is the missing declaration. The door belongs
 * HERE, beside the one above, for the same reason: this file is a caller, and this tree declares a private
 * contract crossing a file boundary where it is CALLED. NSWindow keeps the ownership, and the note over its
 * implementation is still the explanation of why the connection is its to hand out. */
+ (AGWindowServer *)cg_sharedServer;
/* **AND THE THREE DOORS THAT MAKE THE CONNECTION ONE OF THE LOOP'S OWN SOURCES** — the descriptor to watch, the
 * seam's own next deadline (a held key's repeat), and the non-blocking take that turns readiness into queued
 * NSEvents. The first two answer WITHOUT CONNECTING (`s_server`, not `fn_server()`): a loop asking about a
 * descriptor must not make one, which is the rule this file already states for the zero-time poll. */
+ (int)cg_connectionFd;
+ (long)cg_nextDeadlineMs;
+ (BOOL)cg_dispatchPending;
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
/* **THE TWO STATES A CLICK MOVES, KEPT IN ONE PLACE.** `NSWindow` owns the per-window key/main flags and posts
 * the notifications; the application owns `-keyWindow`/`-mainWindow`. These doors are how the window tells the
 * application which one is which, so a `-makeKeyWindow` from a caller and a click in `-sendEvent:` cannot leave
 * the two answers disagreeing. */
- (void)cg_setKeyWindow:(NSWindow *)aWindow;
- (void)cg_setMainWindow:(NSWindow *)aWindow;
@end

/* AND THE ONE PIECE OF PRIVATE STATE THAT CROSSES A FILE BOUNDARY: `-preventWindowOrdering` records a request and
 * `-cg_preventsWindowOrdering` is how the code that would otherwise order a window — and this class's own probe —
 * asks whether it is standing. A door with no public observation point gets a named seam, which is this tree's
 * pattern rather than exporting the ivar. */
@interface NSApplication (APPKITWindowOrdering)
- (BOOL)cg_preventsWindowOrdering;
@end

/* **THE ONE-WINDOW RULE, AS A PRIVATE DOOR.** An application that is active must have a key window, and an
 * application with one usable window must not leave that window looking inactive just because nobody clicked it
 * yet. This is what `-activateIgnoringOtherApps:`, `-cg_addWindow:` and `-cg_removeWindow:` consult. */
@interface NSApplication (APPKITKeyWindow)
- (void)cg_ensureKeyAndMainWindow;
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
/* **AND HOW FAR A SHEET ON THIS WINDOW IS TUCKED INTO ITS TITLE BAR**, asked here because the placement below needs it
 * and answered in `NSWindow.m` because the compositor's shadow clip needs the same number (see `fn_SHEET_TUCK`). */
- (CGFloat)cg_sheetTuck;
/* **AND THE PLACEMENT, WHICH IS THIS FILE'S EVEN THOUGH THE ATTACHMENT IS `NSWindow`'S.** A sheet's position is a rule
 * about TWO windows — the parent's title bar and the sheet's top edge — so it belongs beside the doors that make the
 * pair. `NSWindow -setFrame:display:` calls it too, which is why it is declared in that file's private seam as well;
 * see `@implementation NSWindow (APPKITSheetPlacement)` below. */
- (void)cg_updateSheet;
@end

/* **THE WINDOW'S PENDING DRAG MOVE, DECLARED HERE BECAUSE THIS IS WHAT APPLIES IT.** A pass ends by updating the
 * windows, and that is the one place a drag's move is made: every motion inside a frame updates a target and only
 * the last is applied, so the window goes to where the POINTER is instead of walking the points it passed over. */
@interface NSWindow (APPKITPendingDrag)
- (void)cg_applyPendingDrag;
/* AND THE RESIZE'S AIM, WHICH IS APPLIED IN THE SAME PASS FOR THE SAME REASON. */
- (void)cg_applyPendingResize;
@end

/* ============================================================================================ *
 * WHERE A SHEET GOES, IN ONE PLACE, BECAUSE THREE DOORS ASK.                                   *
 *                                                                                                *
 * **A SHEET HANGS FROM THE BOTTOM EDGE OF ITS PARENT'S TITLE BAR, CENTRED ON THE PARENT.**       *
 * That is the whole of the rule and it is the Mac's: the sheet reads as part of the window it  *
 * belongs to rather than as a panel that happens to be nearby, which is what "attached" means   *
 * when the window server gives a sheet no title bar of its own to hang by.                       *
 *                                                                                                *
 * IT IS RE-APPLIED, NOT REMEMBERED. A parent that moves drags its sheet with it and a parent    *
 * that resizes re-centres it — `NSWindow -setFrame:display:` is where that happens, through     *
 * this door — so nothing here stores an offset that could drift from the parent's frame. The   *
 * alternative, remembering a delta, is a second source of truth about a position the parent's  *
 * frame already states.
 *
 * **AND ITS TOP EDGE IS TUCKED UNDER THE BAR RATHER THAN FLUSH WITH ITS BOTTOM.** The sheet's top edge is placed
 * `NSWindow -cg_sheetTuck` points INTO the title bar, which is invisible — the sheet's body is painted in the chrome's own
 * colour (`-cg_bodyColor`), so what the overlap covers is the same colour it is painted — and it is what makes the
 * seam read as a tuck: the bar's bottom hairline is interrupted across the sheet's width instead of being a ledge the
 * sheet sits under. IT IS NOT ONLY A LOOK: the bar's edge and the sheet's are placed by two `set_frame` calls rounded
 * independently, so at a fractional scale a FLUSH sheet can leave a device row of the parent's line showing across the
 * top of it — a one-pixel seam that a tuck of more than one point cannot have.
 *
 * A PARENT WITH NO TITLE BAR HAS NOTHING TO TUCK UNDER, so the tuck is zero there and the sheet hangs from the top of
 * the window: overlapping a borderless parent's CONTENT with a strip of chrome-coloured body would be a band across its
 * document, which is the opposite of invisible.
 *
 * AND IT IS A CATEGORY HERE BECAUSE THE RULE IS ABOUT TWO WINDOWS: the state is `NSWindow`'s and
 * the session is this class's, which is the same split the sheet seam already makes.
 * ============================================================================================ */
@implementation NSWindow (APPKITSheetPlacement)

- (void)cg_updateSheet
{
	NSWindow *sheet = [self attachedSheet];
	NSRect parentContent;
	NSRect frame;
	CGFloat tuck;

	if (sheet == nil) {
		return;
	}
	/* THE PARENT'S CONTENT, NOT ITS FRAME: the bottom edge of the title bar is where the sheet's top goes, and the
	 * content rect is exactly the frame minus that bar. Asking the frame and subtracting the chrome by hand would be
	 * a second copy of the chrome arithmetic `-contentRectForFrameRect:` already owns. */
	parentContent = [self contentRectForFrameRect:[self frame]];
	/* THE TUCK IS `NSWindow`'s, because the compositor is told the same number — see `fn_SHEET_TUCK` there. */
	tuck = [self cg_sheetTuck];
	frame = [sheet frame];
	frame.origin.x = parentContent.origin.x + (parentContent.size.width - frame.size.width) / 2.0;
	frame.origin.y = NSMaxY(parentContent) + tuck - frame.size.height;
	[sheet setFrameOrigin:frame.origin];
}

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

/* **THE QUESTION A DOCK CLICK ASKS WHEN THERE IS NOTHING TO RAISE.** Declared here because the seam that receives
 * it is a window's event and the answer is the application's: a window is where the ask ARRIVES, not what it is
 * about. See the implementation's own note for what "visible" means in this tree. */
@interface NSApplication (APPKITReopen)
- (BOOL)cg_handleReopen;
@end

/* THE DOCUMENT CONTROLLER'S CRASH-TIME REOPEN IS A PRIVATE CONTRACT WITH THIS CLASS. */
@interface NSDocumentController (AGAutosaveReopen)
+ (BOOL)cg_hasAutosavedDocumentsToReopen;
- (void)cg_reopenAutosavedDocuments;
@end

@implementation NSApplication

/* **WHICH CLASS THE APPLICATION IS, AND WHO DECIDES.** The single instance used to be `[[NSApplication alloc]
 * init]`, hard-coded, so an application that subclassed this class to customize dispatch, own background work or
 * extend the lifecycle had no supported way to have ITS class be the one `NSApp` names — and `NSApplicationMain`
 * had no principal-class selection at all. Three doors, in the order Apple's model implies:
 *
 *   1. `+setSharedApplicationClass:` — an explicit choice, for a program that has no bundle to read;
 *   2. `NSPrincipalClass` in the main bundle's Info.plist — Apple's own key, and the reason a Carbon-era bundle
 *      could name its application class without a line of code;
 *   3. the RECEIVING class, so `[MyApplication sharedApplication]` answers a `MyApplication` rather than quietly
 *      substituting this class for it.
 *
 * A named class that is not a subclass of this one is REFUSED and the default is used, because `NSApp` is typed
 * `NSApplication *` throughout this tree and an object that is not one would fail at the first message rather than
 * here, a long way from the mistake. */
static Class s_sharedApplicationClass = Nil;

+ (void)setSharedApplicationClass:(Class)aClass
{
	if (aClass != Nil && ![aClass isSubclassOfClass:[NSApplication class]]) {
		fprintf(stderr, "APPKIT-REFUSE: +setSharedApplicationClass: needs a subclass of NSApplication; %s is "
				"not one, so the default is kept\n", class_getName(aClass));
		return;
	}
	/* THE INSTANCE IS ONE, so the class is chosen once: changing it after the application exists would leave
	 * `NSApp` naming an object of a class nobody asked for. */
	if (NSApp != nil) {
		fprintf(stderr, "APPKIT-REFUSE: +setSharedApplicationClass: the application already exists, so the "
				"class cannot change now\n");
		return;
	}
	s_sharedApplicationClass = aClass;
}

/* THE BUNDLE'S ANSWER, ASKED ONCE AND ONLY WHEN NOBODY HAS SAID OTHERWISE. `NSPrincipalClass` is a string, and a
 * name that does not resolve to a class is not an error worth stopping for — a bundle that ships a stale plist
 * should get the default application rather than no application at all. */
+ (Class)cg_principalApplicationClass
{
	Class named;

	if (s_sharedApplicationClass != Nil) {
		return s_sharedApplicationClass;
	}
	if (self != [NSApplication class]) {
		return self;	/* `[MyApplication sharedApplication]` means MyApplication */
	}
	{
		NSString *name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSPrincipalClass"];

		named = (name != nil) ? NSClassFromString(name) : Nil;
	}
	if (named != Nil && [named isSubclassOfClass:[NSApplication class]]) {
		return named;
	}
	return [NSApplication class];
}

+ (NSApplication *)sharedApplication
{
	static NSApplication *s_shared;

	if (s_shared == nil) {
		Class applicationClass = [self cg_principalApplicationClass];

		s_shared = [[applicationClass alloc] init];
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
	[_cg_dockMenu release];
	[_cgDockTile release];
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

- (void)cg_setKeyWindow:(NSWindow *)aWindow
{
	_keyWindow = aWindow;
}

- (void)cg_setMainWindow:(NSWindow *)aWindow
{
	_mainWindow = aWindow;
}

/* **AN ACTIVE APPLICATION ALWAYS HAS A KEY WINDOW, AND A SINGLE WINDOW IS ALWAYS THAT ONE.** `-cg_addWindow:`
 * used to record the application's two pointers and stop there, so a window that had never been clicked answered
 * `-isKeyWindow` NO and drew its chrome inactive even when it was the only window on the screen. The candidate is
 * the remembered window when it can still take the state, otherwise the first visible window that can. A window
 * that refuses (the desktop, a borderless panel) is skipped rather than forced. */
- (void)cg_ensureKeyAndMainWindow
{
	NSWindow *candidate;
	NSUInteger i;

	if (!_active) {
		return;
	}
	candidate = _keyWindow;
	if (candidate == nil || ![candidate isVisible] || ![candidate canBecomeKeyWindow]) {
		candidate = nil;
		for (i = 0; i < [_windows count]; i++) {
			NSWindow *w = [_windows objectAtIndex:i];

			if ([w isVisible] && [w canBecomeKeyWindow]) {
				candidate = w;
				break;
			}
		}
	}
	if (candidate != nil && ![candidate isKeyWindow]) {
		[candidate makeKeyWindow];
	}

	candidate = _mainWindow;
	if (candidate == nil || ![candidate canBecomeMainWindow]) {
		candidate = nil;
		for (i = 0; i < [_windows count]; i++) {
			NSWindow *w = [_windows objectAtIndex:i];

			if ([w canBecomeMainWindow]) {
				candidate = w;
				break;
			}
		}
	}
	if (candidate != nil && ![candidate isMainWindow]) {
		[candidate makeMainWindow];
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
	[self cg_ensureKeyAndMainWindow];
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
	return [self targetForAction:anAction to:nil from:nil];
}

/* **AND THE SENDER DECIDES WHERE THE WALK STARTS.** A sender that is a RESPONDER answers from its own chain — that is how
 * a menu item's action finds the view the click came from — and anything else (nil, a window, a control that is not a
 * responder) starts at the key window's first responder, which is what the one-argument door has always done. */
- (id)targetForAction:(SEL)anAction to:(id)aTarget from:(id)sender
{
	NSResponder *r;

	if (anAction == NULL) {
		return nil;
	}
	if (aTarget != nil) {
		/* A TARGET NAMED BY THE CALLER IS ANSWERED WHEN IT CAN TAKE THE ACTION, and nothing is walked: that is what
		 * "to:" MEANS in this door's name. */
		return ([aTarget respondsToSelector:anAction]) ? aTarget : nil;
	}
	if (sender != nil && [sender isKindOfClass:[NSResponder class]]) {
		r = (NSResponder *)sender;
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
	/* **A CRASHED SESSION'S AUTOSAVED DOCUMENTS COME BACK BEFORE THE DELEGATE'S LAUNCH PAIR.** The registry is the
	 * controller's; this class only asks whether one exists, so a non-document application pays one `stat`, and a
	 * document application reopens through the same `-reopenDocumentForURL:withContentsOfURL:` path the Finder uses. */
	if ([NSDocumentController cg_hasAutosavedDocumentsToReopen]) {
		[[NSDocumentController sharedDocumentController] cg_reopenAutosavedDocuments];
	}
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

/* **AND HOW LONG THE PASS MAY WAIT.** One frame, unless the SEAM has a deadline sooner — a held key's repeat — in
 * which case that is the deadline: the compositor asked for a repeat rate, and firing it at the frame's cadence
 * instead is a keyboard that stutters. A closed connection or an empty process with no server at all has no source
 * to wake it, so the frame's slice is also what keeps this loop from waiting forever on nothing. */
- (double)cg_passSeconds
{
	double seconds = 1.0 / 60.0;
	long deadline = [NSWindow cg_nextDeadlineMs];

	if (deadline >= 0) {
		double fromSeam = (double)deadline / 1000.0;

		if (fromSeam < seconds) {
			seconds = fromSeam;
		}
	}
	return seconds;
}

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
		NSEvent *e;

		/* THE UPDATE PAIR, ONCE PER PASS: Apple sends these when the loop is about to update the windows and
		 * again when it has, which is what gives a delegate a place to change what is shown BETWEEN passes
		 * rather than in response to an event. */
		fn_announce(self, NSApplicationWillUpdateNotification, @selector(applicationWillUpdate:));
		/* **THE WAIT IS THE RUN LOOP'S, AND THE CONNECTION IS ONE OF ITS SOURCES.** One frame's deadline (or the
		 * seam's own, if it is sooner) is spent inside CoreFoundation, which wakes on the compositor's descriptor,
		 * on a due timer, on a performer signalled by another thread and on the main dispatch queue's port — so a
		 * pass no longer has to choose between "watch the compositor" and "let the rest of the loop run". A
		 * handled source returns the pass at once; a timer does not make CoreFoundation return early on its own,
		 * which is what the door's work counter is for. */
		[[NSRunLoop currentRunLoop] fnRunMode:NSDefaultRunLoopMode
					   forSeconds:[self cg_passSeconds]
				      returnAfterWork:YES];
		e = [self nextEventMatchingMask:NSAnyEventMask
				       untilDate:[NSDate distantPast]
					  inMode:NSDefaultRunLoopMode
					 dequeue:YES];

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
		/* **AND THE WHOLE QUEUE IS DRAINED, NOT ONE EVENT PER PASS.** A pass is a FRAME — it ends by updating the
		 * windows once — and a loop that takes ONE event per frame can process at most sixty events a second. A
		 * mouse that reports faster than that (MEASURED: a hand at 125 Hz) then leaves a BACKLOG that grows for as
		 * long as the drag lasts, so the window trails further and further behind the pointer. "It is very laggy"
		 * is a QUEUE, not a slow frame: the compositor was measured compositing 3 ms a frame in step with every
		 * motion. Draining costs nothing when the queue is empty — the poll returns at once — and it means a pass
		 * ends with the windows drawn at the LATEST position whatever the input's rate. */
		while (e != nil) {
			[self sendEvent:e];
			e = [self nextEventMatchingMask:NSAnyEventMask
					       untilDate:[NSDate distantPast]
						  inMode:nil
						dequeue:YES];
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

		/* **THE EVENT'S OWN BIT, WHICH IS WHAT "ANY" MEANS ANYWAY.** `NSAnyEventMask` has every bit set, so it
		 * needs no separate case; asking whether the mask intersects `NSAnyEventMask` at all is true for every
		 * nonzero mask and would discard events the caller did not name. */
		if ((mask & ((NSUInteger)1 << [e type])) != 0) {
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
	/* **THE MENU BAR'S SECOND CHANCE, AT THE DOOR EVERY LOOP PASSES THROUGH.** `-setMainMenu:` measures its window
	 * from the MENU-BAR REGION the compositor sends, and an application that set its main menu BEFORE that region
	 * was read has a menu and no window to put it in. MEASURED: the region arrives asynchronously, so whether it is
	 * known at `-setMainMenu:` time is a RACE — the same program against the same compositor produced a bar window
	 * in one run and not in the next, which is exactly the shape of bug a `-run`-only fix cannot catch.
	 *
	 * `-run` re-measures once for the stated reason, but a loop of its own never goes through `-run` — W0's
	 * `-runForSeconds:` is one — so the re-measure belongs where EVERY loop passes: the first event read. The guard
	 * makes it a one-off: once the window exists this is a nil test per event. */
	if (_mainMenu != nil && _menuBarWindow == nil) {
		[self cg_updateMenuBarWindow];
	}
	/* **THE MODE, WHICH THIS DOOR USED TO DROP ON THE FLOOR.** It is `NSDefaultRunLoopMode` when the caller passed
	 * nil (Apple's own reading), and it is what the run-loop pass below this door belongs to: a tracking loop that
	 * asks for `NSEventTrackingRunLoopMode` gets that mode's timers and not the default ones. */
	NSString *runMode = (mode != nil) ? mode : NSDefaultRunLoopMode;

	/* **AND A QUEUED EVENT GIVES THE CONNECTION ITS TURN FIRST, ONCE PER PASS.** This door returns the durable queue
	 * and the windows' queues BEFORE it ever waits, so under continuous input it returned event after event and the
	 * native connection was never serviced: buffer-release and frame callbacks that arrive ON that connection stayed
	 * undelivered and presentation stopped advancing, while the loop looked perfectly busy. A nonblocking service
	 * turn costs one `poll` with a zero timeout, cannot delay the event about to be collected, and cannot extend the
	 * caller's deadline. Nothing is created either — a process with no connection is not made one by asking — which
	 * is the other half of the report: a zero-time poll must not bootstrap a connection. */
	if ([NSWindow cg_hasWindowServer]) {
		(void)[NSWindow cg_waitForEventInMilliseconds:0];
	}
	for (;;) {
		NSUInteger i;

		/* THE POSTED QUEUE FIRST: an event a caller made did not come from the server and must not wait
		 * behind one that has not arrived. */
		for (i = 0; i < [_eventQueue count]; i++) {
			NSEvent *e = [_eventQueue objectAtIndex:i];

			/* AND THE SAME TEST AT THE PEEK, so a mask that does not name this event leaves it in place and
			 * the search continues — rather than returning the first thing in the queue whatever was asked
			 * for. */
			if ((mask & ((NSUInteger)1 << [e type])) != 0) {
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
		/* **AND ONLY THEN THE WAIT — AND IT IS THE RUN LOOP'S, THE SAME ONE THE FRAME USES.** This door used to
		 * wait on the compositor's descriptor directly (`+cg_waitForEventInMilliseconds:`), which made a hand-pumped
		 * loop and an application's loop two mechanisms with two different ideas of what could happen while
		 * waiting: a timer did not fire in the first and a compositor event did not arrive in the second. Both wait
		 * in one place now, so a caller that pumps through this door gets the timers, the fd sources, a performer
		 * from another thread and the main dispatch queue for free — and the connection is one of those sources
		 * rather than a timeout around them.
		 *
		 * THE WAIT IS WHAT THE CALLER ASKED FOR, capped at the old fifty milliseconds. The cap is not about the
		 * descriptor: it is what bounds `-stop:` for a loop whose only work is this door, and it costs nothing when
		 * something is due — `-fnRunMode:` returns the moment a timer fires or a source is handled, not when the
		 * wait expires. A nil deadline means "until something happens", one cap at a time. */
		{
			double seconds = 0.05;

			if (expiration != nil) {
				seconds = [expiration timeIntervalSinceNow];
				if (seconds <= 0.0) {
					return nil;
				}
				if (seconds > 0.05) {
					seconds = 0.05;
				}
			}
			[[NSRunLoop currentRunLoop] fnRunMode:runMode
						   forSeconds:seconds
					      returnAfterWork:YES];
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
	AGWindowServerMenuBarArea(server, &x, &y, &width, &height);
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
		/* **THE BAR WANTS THE MOTION, AND NOT WANTING IT WAS HALF OF A BUG.** This tier drops a plain
		 * `NSMouseMoved` for a window that has not asked (`NSWindow -fn_translate`), and nothing had ever asked —
		 * so the bar's own tracking loop never heard the pointer cross from one title to another, and the menu a
		 * click had opened could not follow it. See `-setAcceptsMouseMovedEvents:`. */
		[_menuBarWindow setAcceptsMouseMovedEvents:YES];
		[_menuBarWindow setContentView:view];
		/* **AND IT IS THE STRIP'S COLOUR, SO THERE IS NO SEAM.** The window's background is what shows between the
		 * titles, and the server's strip is what shows either side of this window — two surfaces a person reads as
		 * ONE BAR, so they had better be the same colour. It comes through `+[NSWindow cg_menuBarColor]` NOW rather
		 * than being built here, because A DROPDOWN'S PANEL IS THE SAME QUESTION: the menus hang from the bar and a
		 * second copy of "the server's colour, as an NSColor" is how the panel came to be lighter than the strip. */
		[_menuBarWindow setBackgroundColor:[NSWindow cg_menuBarColor]];
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
	/* **PAGE SETUP IS THE SHARED TICKET'S PAGE, EDITED IN PLACE.** The panel writes paper, orientation and margins back
	 * through `-writePrintInfo`, so the next print job of any document inherits the change — which is what a page-setup
	 * command is for. */
	(void)sender;
	[[NSPageLayout pageLayout] runModalWithPrintInfo:[NSPrintInfo sharedPrintInfo]];
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
	/* **ONE TILE PER APPLICATION, MADE ON FIRST ASK.** Apple's contract: the tile belongs to the application and the
	 * Dock draws it. This tier's Dock is a separate program, so what the tile changes travels `agora-shell` 8 (see
	 * `NSDockTile.h`); the object itself is the application's, and `-owner` answers that. */
	if (_cgDockTile == nil) {
		_cgDockTile = [[NSDockTile alloc] init];
	}
	return _cgDockTile;
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
	/* **THE MAIN MENU IS OFFERED THE KEY BEFORE ANY WINDOW IS.** Apple's `-sendEvent:` does this for a key-down and
	 * returns when the menu takes it, and this pump did not: it went straight to `[w sendEvent:]`, so a Command-key
	 * equivalent never fired on the ORDINARY dispatch route and only worked while a menu was tracking. MEASURED on
	 * this tree: a main-menu item with an explicit Command modifier and a first responder recording `-keyDown:` —
	 * the responder won and the menu action never ran.
	 *
	 * IT COMES BEFORE THE WINDOW IS EVEN LOOKED UP, because a key equivalent belongs to the MENU BAR and not to a
	 * window: it must fire when the event's window number names nothing this application has (a menu bar window of
	 * its own, or the compositor's numbering) and it must fire while a sheet is up, which is exactly when the gate
	 * below drops input aimed at the sheet's parent. `-performKeyEquivalent:` matches only items that HAVE a key
	 * equivalent, so an ordinary keystroke falls straight through to the responder chain.
	 *
	 * AND A HANDLED EVENT IS CONSUMED, so the action fires once: returning here is what stops the responder seeing
	 * a keystroke the menu already acted on. */
	if ([theEvent type] == NSKeyDown && _mainMenu != nil) {
		if ([_mainMenu performKeyEquivalent:theEvent]) {
			if (getenv("APPKIT_MENU_DIAG") != NULL) {
				fprintf(stderr, "  DIAG dispatch: the main menu handled the key equivalent\n");
			}
			return;
		}
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
	 * delivered: a click in a disabled parent must not reach a control behind a question nobody has answered yet.
	 * The sheet itself carries no attachment of its own, so events aimed at it are untouched.
	 *
	 * **AND A CLICK IN IT IS NOT NOTHING.** Refusing the click is only half of what the Mac does with one: the other
	 * half is that a press anywhere in the pair brings the pair FORWARD and leaves the SHEET with the keyboard — a
	 * person who clicks a background document's dimmed body is saying "this one", and getting a document that comes
	 * to the front with the question still greyed out (or, worse, nothing at all) is how a modal session comes to look
	 * stuck. So the click does the two acts this class owns and then drops the event: the APPLICATION activates, the
	 * parent is ordered front — which is the raise, and on this compositor it brings the sheet with it, because a
	 * sheet is exactly one layer above its parent and has no place of its own — and the KEY AND MAIN go to the sheet,
	 * never to the parent the click landed on. Apple disables the parent and beeps; the beep is the one part this tier
	 * does not do, and the drop is what stands in for the disablement. */
	if ([w attachedSheet] != nil) {
		if ([theEvent type] == NSLeftMouseDown || [theEvent type] == NSRightMouseDown
		    || [theEvent type] == NSOtherMouseDown) {
			NSWindow *sheet = [w attachedSheet];

			[self activate];
			[w orderFront:nil];
			/* **AND THE SHEET TAKES THE KEY, WHICH IS ALSO WHAT KEEPS IT THERE.** A window that cannot become key
			 * (a borderless sheet) keeps whatever had it, which is this tier's answer to Apple's refusal-by-print. */
			if ([sheet canBecomeKeyWindow]) {
				[sheet makeKeyWindow];
			}
			if ([sheet canBecomeMainWindow]) {
				[sheet makeMainWindow];
			}
		}
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
	if ([theEvent type] == NSLeftMouseDown || [theEvent type] == NSRightMouseDown
	    || [theEvent type] == NSOtherMouseDown) {
		/* **A CLICK IS THREE ACTS, AND THE OLD CODE DID ONLY THE THIRD OF THE FIRST ONE.** It wrote the two
		 * application ivars and stopped: the window itself never became key (`-isKeyWindow` stayed NO), never
		 * became main, was never raised, and the application was never activated. A person clicked a background
		 * window and it stayed behind an inactive application's menu bar.
		 *
		 * `-orderFront:` comes first because `-canBecomeMainWindow` requires a VISIBLE window — and it is also
		 * the raise, now that `-orderFront:` sends the server's `raise`. `-makeKeyWindow`/`-makeMainWindow` are
		 * the public doors, so their notifications and their previous-window resignations run; a window that
		 * cannot become key or main (the desktop, a menu) keeps the previous one instead of stealing the state
		 * by assignment.
		 *
		 * AND THE APPLICATION ACTIVATES: a click in another process is what makes that process the active one.
		 * `-activate` is idempotent now, so the keyboard-enter half of the compositor's click-to-focus can arrive
		 * before or after this and announce once. */
		[self activate];
		[w orderFront:nil];
		/* **AND WHETHER THE CLICK SHOULD TAKE THE KEY IS THE WINDOW'S QUESTION, NOT THIS PUMP'S.** A window says yes
		 * to any click; a panel whose `-becomesKeyOnlyIfNeeded` is YES says yes only when the press lands on a view that
		 * needs the panel to be key — a text field rather than a button or the background. The rule lives on the
		 * window (`-cg_shouldBecomeKeyForClickAtPoint:`) because a panel's flag is its state and the view under the
		 * pointer is its content tree; this class owns only the moment. */
		if ([w canBecomeKeyWindow] && [w cg_shouldBecomeKeyForClickAtPoint:[theEvent locationInWindow]]) {
			[w makeKeyWindow];
		}
		if ([w canBecomeMainWindow]) {
			[w makeMainWindow];
		}
	}
	[w sendEvent:theEvent];
}

/* ---- ACTIVATION AND HIDING ------------------------------------------------------------------ */

/* WITH NO WINDOW MANAGER OF THIS TREE'S OWN, activation is the APPLICATION's state and the window verbs it
 * implies — stated rather than pretending to negotiate with a manager that is parked. What it really does is
 * keep `-isActive` honest and bring the windows back when the application is unhidden. */
- (void)activateIgnoringOtherApps:(BOOL)flag
{
	/* `-isActive` REPORTS THIS, so the flag is set where the state changes. THE ANNOUNCEMENT IS A TRANSITION,
	 * NOT A COUNT: the compositor's keyboard-enter and a click can both ask in the same pass, and an application
	 * that posted Will/Did twice for one activation would make a delegate act twice on one change. */
	BOOL wasActive = _active;
	NSUInteger i;

	_active = YES;
	(void)flag;
	if (!wasActive) {
		fn_announce(self, NSApplicationWillBecomeActiveNotification, @selector(applicationWillBecomeActive:));
	}
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
	/* **AND THE WINDOW THE APPLICATION SPEAKS THROUGH IS KEY AND MAIN.** On a first launch nobody has clicked yet;
	 * with one window there is no choice to make; with several the remembered one keeps the state. */
	[self cg_ensureKeyAndMainWindow];
}

- (void)activate
{
	BOOL wasActive = _active;

	[self activateIgnoringOtherApps:NO];
	/* THE OTHER HALF OF THE PAIR, so the two doors are not the same door with two names: this is the one that says
	 * the application HAS the focus, and the one above says it is about to get it. A second `-activate` on an
	 * already-active application still brings its key window and menu bar forward, but it announces nothing. */
	if (!wasActive) {
		fn_announce(self, NSApplicationDidBecomeActiveNotification, @selector(applicationDidBecomeActive:));
	}
}

- (void)deactivate
{
	if (!_active) {
		return;
	}
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

/* ============================================================================================
 * REOPEN: WHAT A DOCK CLICK MEANS WHEN THE APPLICATION HAS NOTHING TO RAISE.
 *
 * **THE MAC'S CONTRACT, AND THE ONE PIECE OF IT THAT IS A QUESTION RATHER THAN A VERB.** A click on a running
 * application's tile activates it; if it has no window a person can work in, the application is ASKED what that
 * click should do (`-applicationShouldHandleReopen:hasVisibleWindows:`) and decides for itself — Finder opens a
 * Finder window, a document application opens an untitled document, a paletted utility does nothing. This tree has
 * the same split: the window server forwards the ask to the window's client (see `agora_window.reopen`), the seam
 * turns it into `AGEventReopen`, and this is where the delegate hears it.
 *
 * **"VISIBLE" IS "A WINDOW A PERSON WORKS IN", NOT "ANY WINDOW ON THE GLASS", AND THAT IS A DEVIATION WITH A
 * CAUSE.** On the Mac the desktop is not a window, so a Finder showing nothing but its desktop honestly answers
 * NO. Here the desktop IS an `NSWindow` — at a level below every ordinary one — and so is the menu bar, above
 * them; counting either would answer YES for exactly the state this question exists to catch, and a Workspace with
 * no file window would never open one. The band is therefore the ordinary levels: from `NSNormalWindowLevel` up to
 * (not including) `NSDockWindowLevel`, which is where furniture starts.
 * ============================================================================================ */
- (BOOL)cg_handleReopen
{
	BOOL hasVisibleWindows = NO;
	NSUInteger i;

	for (i = 0; i < [_windows count]; i++) {
		NSWindow *w = [_windows objectAtIndex:i];
		NSInteger level = [w level];

		if ([w isVisible] && level >= NSNormalWindowLevel && level < NSDockWindowLevel) {
			hasVisibleWindows = YES;
			break;
		}
	}
	/* **AND A DELEGATE THAT DOES NOT ANSWER GETS THE MAC'S DEFAULT, WHICH IS NO: nothing opens.** The alternative —
	 * opening something on the application's behalf — would make this class decide what a window is for an
	 * application it knows nothing about. */
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(applicationShouldHandleReopen:hasVisibleWindows:)]) {
		return [(id <NSApplicationDelegate>)_delegate applicationShouldHandleReopen:self
								hasVisibleWindows:hasVisibleWindows];
	}
	return NO;
}

/* ============================================================================================
 * THE DOCK MENU: THE APPLICATION'S HALF OF A RIGHT-CLICK ON ITS TILE.
 *
 * **THE QUESTION IS APPLE'S, AND IT HAS BEEN DECLARED HERE FOR LONGER THAN THERE WAS A DOCK TO ASK IT.**
 * `-applicationDockMenu:` is a delegate method in the 10.6 surface this tree follows, and until now nothing asked
 * it: there was no Dock. There is one, so the question is put, and the answer is KEPT — because the menu has to
 * cross to another process as a description and only its ids can come back, and an id needs a tree to name.
 *
 * **THE MENU IS REPLACED ON EVERY ASK, WHICH IS THE POINT OF ASKING AT ALL.** A dock menu is a picture of what the
 * application can do at this moment, so asking again rebuilds it and the previous tree is released; a pick that
 * arrives after a rebuild is looked up in the numbering the new answer published, and an item's action is sent to
 * the target the application itself gave it.
 * ============================================================================================ */
- (NSMenu *)cg_dockMenu
{
	NSMenu *menu = nil;

	if (_delegate != nil && [_delegate respondsToSelector:@selector(applicationDockMenu:)]) {
		/* THE DELEGATE'S ANSWER IS TYPED `id` IN THE PROTOCOL — see the note there, which explains why a forward
		 * declaration of NSMenu could not be used instead — so what came back is checked rather than assumed: an
		 * answer that is not a menu is no menu. */
		menu = [(id <NSApplicationDelegate>)_delegate applicationDockMenu:self];
	}
	if (![menu isKindOfClass:[NSMenu class]]) {
		menu = nil;
	}
	/* **AND THE APPLICATION VALIDATES ITS OWN ITEMS, BECAUSE IT IS THE ONLY ONE THAT CAN.** A menu's enabling walk
	 * asks each item's target `-validateMenuItem:` — and those targets are this process's objects, so the answer has
	 * to be made HERE, before the menu is described. The Dock cannot re-run it: it will hold the same rows with a
	 * target of its own, and re-validating there would enable every row whose id the Dock can send. */
	[menu update];
	[menu retain];
	[_cg_dockMenu release];
	_cg_dockMenu = menu;
	return menu;
}

- (void)cg_performDockMenuItem:(NSInteger)identifier
{
	NSMenuItem *item = [NSDockMenu cg_itemForID:identifier inMenu:_cg_dockMenu];
	NSMenu *owner;
	NSInteger index;

	/* **THE ID NAMES A ROW IN THE MENU THIS APPLICATION GAVE THE DOCK, AND NOTHING ELSE.** A stale id — the tree was
	 * rebuilt between the answer and the pick — names no row, and doing nothing is the honest answer to a question
	 * about an item that is no longer there. */
	if (item == nil) {
		return;
	}
	/* **AND THE DISPATCH IS THE MENU'S OWN, ONE LAYER DOWN.** Sending the item's action here would be a second copy
	 * of the target/action pair — a named target or the responder chain, plus the two notifications — and the row may
	 * live in a SUBMENU, so the item's OWNING MENU is what is asked to do it. This is the same call the Dock's
	 * tracking loop would have made had the menu been drawn in this process. */
	owner = [item menu];
	index = (owner != nil) ? [owner indexOfItem:item] : NSNotFound;
	if (index != NSNotFound) {
		[owner performActionForItemAtIndex:index];
	}
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
		NSWindow *w = [_windows objectAtIndex:i];

		/* **THE DRAG'S PENDING MOVE FIRST, THEN THE PAINT.** A drag's move is applied once per pass at the LATEST
		 * pointer (see `NSWindow -cg_applyPendingDrag`), and the window is then painted at its new place by the
		 * display pass below. One move and one `set_frame` per frame, never one per motion event. */
		[w cg_applyPendingDrag];
		/* AND A RESIZE'S AIM, WHICH IS THE SAME KIND OF DEFERRAL: one `set_frame` per pass, at the latest
		 * position the hand reached, with the size the delegate last agreed to. */
		[w cg_applyPendingResize];
		[w displayIfNeeded];
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

	/* **THE ATTACHMENT, WHICH IS ALSO WHERE THE SHEET LOSES ITS CHROME.** A sheet is a window whose frame IS its
	 * content — the Mac gives it no title bar, and `fn_chrome_height` is where this tier states the same thing — so
	 * `-cg_setSheetParent:` takes the strip off the frame while keeping the CONTENT's size and place, the mirror of
	 * what `-setStyleMask:` does when a mask changes. Doing it in the state's own door rather than here is what
	 * makes ending the session put the strip back. */
	[sheet cg_setSheetParent:docWindow];
	[docWindow cg_setAttachedSheet:sheet];
	[docWindow cg_setSheetReplyDelegate:modalDelegate selector:didEndSelector contextInfo:contextInfo];
	/* **AND THE PLACEMENT, WHICH IS THIS TIER'S BECAUSE IT PLACES ITS OWN WINDOWS.** `-cg_updateSheet` is the one rule
	 * (see its comment above): the sheet's top edge at the bottom of the parent's title bar, centred on the parent's
	 * content. It is the same door the parent's own frame changes use, so a sheet cannot be placed one way here and
	 * another way after a drag. */
	[docWindow cg_updateSheet];
	[sheet orderFront:nil];
	/* **AND THE SHEET TAKES THE KEY AND MAIN THROUGH THE WINDOWS' OWN DOORS, NOT BY ASSIGNING THE IVARS.** Assigning
	 * them — which is what this did — moved the application's two pointers and NOTHING ELSE: the parent kept
	 * `-isKeyWindow` YES for the whole session (two windows claiming to be key at once), the sheet answered NO, and the
	 * `-windowDidBecomeKey:` an observer was waiting for never came. It also left the SEAT alone, so a sheet opened
	 * without a click left the keyboard where it was. The doors do all three, and they are the same pair a click runs:
	 * `-becomeKeyWindow` resigns the previous key window, `-becomeMainWindow` the previous main.
	 *
	 * (That also makes `-makeKeyWindow` on the parent AFTER a sheet is attached mean something: with the parent's flag
	 * never cleared it early-returned, and the two windows disagreed about who was key for as long as the sheet was
	 * up.) */
	if ([sheet canBecomeKeyWindow]) {
		[sheet makeKeyWindow];
	}
	if ([sheet canBecomeMainWindow]) {
		[sheet makeMainWindow];
	}
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
	/* **KEY GOES BACK TO THE PARENT FIRST, SO THAT A REPLY WHICH ASKS WHO HAS THE KEY IS TOLD THE TRUTH** — and it goes
	 * back through the windows' doors for the reason the attachment used them: the two flags, the application's two
	 * pointers and the seat's focus are one answer, and assigning an ivar moves one of the three. The sheet's own flags
	 * are cleared by the parent's `-becomeKeyWindow`/`-becomeMainWindow` resigning it, which is also what tells an
	 * observer the session is over as far as the keyboard is concerned. */
	if ([sheet isKeyWindow]) {
		[docWindow makeKeyWindow];
	}
	if ([sheet isMainWindow]) {
		[docWindow makeMainWindow];
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
 * ended.
 *
 * **AND THE TAG IS NOT `_NSModalSession`, WHICH IS A MATTER OF ABI RATHER THAN TASTE.** `NSApplication.h`
 * declares `typedef struct _NSModalSession *NSModalSession` with the struct INCOMPLETE, so every caller's method
 * signature encodes `^{_NSModalSession=}`; if this file DEFINED that tag, the compiler would encode the three
 * fields into these methods' signatures instead, and the runtime would print "incorrect signature" for every
 * external `-beginModalSessionForWindow:` (MEASURED with `tests/panel_alert.m`, the first client outside this
 * file to use the session doors). A private tag keeps the public one opaque in the encoding and the calls quiet. */
struct AGModalSession {
	NSWindow *window;
	NSInteger code;
	BOOL ended;
	/* **AND THE PARENT, WHICH IS WHAT MAKES A SESSION A SHEET'S.** Nil for a plain `-beginModalSessionForWindow:`, the
	 * document window for the `…relativeToWindow:` form — and `-endModalSession:` reads it to take the sheet back down. */
	NSWindow *sheetParent;
};

- (NSModalSession)beginModalSessionForWindow:(NSWindow *)theWindow
{
	struct AGModalSession *s;

	if (theWindow == nil) {
		/* A SESSION WITH NO WINDOW IS NOT A SESSION, and answering NULL is how a caller learns that rather than
		 * getting a session whose every pass does nothing. */
		return NULL;
	}
	s = (struct AGModalSession *)calloc(1, sizeof(*s));
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

/* **AND THE TWO RELATIVES ARE THE SHEET'S SESSION, NOT A SECOND KIND OF MODALITY.** `-beginModalSessionForWindow:relativeToWindow:`
 * attaches the window to its parent through the sheet door the class already has, then begins the SAME session; the
 * parent is remembered in the session so `-endModalSession:` can take the attachment back down. A nil parent is the plain
 * form rather than a refusal, because Apple's own documentation treats the parent as advice about PLACEMENT — a window with
 * no parent is still a modal session, just not a hanging one.
 *
 * ONE THING IS DELIBERATELY NOT DONE: the sheet is begun with NO modal delegate, because the session IS the caller's — the
 * code comes back from `-runModalSession:`, not from a did-end selector, which is the difference between the two shapes
 * Apple ships. */
- (NSModalSession)beginModalSessionForWindow:(NSWindow *)theWindow relativeToWindow:(NSWindow *)docWindow
{
	NSModalSession session;
	struct AGModalSession *s;

	session = [self beginModalSessionForWindow:theWindow];
	s = (struct AGModalSession *)(void *)session;
	if (s == NULL) {
		return NULL;
	}
	if (docWindow != nil) {
		[self beginSheet:theWindow modalForWindow:docWindow modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
		s->sheetParent = docWindow;
	}
	return session;
}

- (NSInteger)runModalForWindow:(NSWindow *)theWindow relativeToWindow:(NSWindow *)docWindow
{
	NSModalSession session = [self beginModalSessionForWindow:theWindow relativeToWindow:docWindow];
	NSInteger code;

	if (session == NULL) {
		return NSRunAbortedResponse;
	}
	for (;;) {
		code = [self runModalSession:session];
		if (code != NSRunContinuesResponse) {
			break;
		}
	}
	[self endModalSession:session];
	return code;
}

- (NSInteger)runModalSession:(NSModalSession)session
{
	struct AGModalSession *s = (struct AGModalSession *)(void *)session;

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
		/* A MODAL SESSION IS A FRAME TOO, in `NSModalPanelRunLoopMode` — so a timer or a performer scheduled for
		 * that mode is delivered here, and one scheduled ONLY for the default mode is not (the mode rule). The
		 * connection's source is in the common modes, so it is live in this one as well. */
		NSEvent *e;

		[[NSRunLoop currentRunLoop] fnRunMode:NSModalPanelRunLoopMode
					   forSeconds:[self cg_passSeconds]
				      returnAfterWork:YES];
		e = [self nextEventMatchingMask:NSAnyEventMask
				       untilDate:[NSDate distantPast]
					  inMode:NSModalPanelRunLoopMode
					 dequeue:YES];

		/* THE SAME DRAIN AS THE MAIN LOOP: a modal session is a frame too, and taking one event per frame would
		 * leave the same backlog behind a fast hand. */
		while (e != nil) {
			[self sendEvent:e];
			e = [self nextEventMatchingMask:NSAnyEventMask
					       untilDate:[NSDate distantPast]
						  inMode:NSModalPanelRunLoopMode
						dequeue:YES];
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
	struct AGModalSession *s = (struct AGModalSession *)(void *)session;

	if (s == NULL) {
		return; /* ending no session is not an error, for the reason `-stopModal` with none is not either */
	}
	if (_modalSession == s) {
		_modalSession = NULL;
		_modalWindow = nil;
	}
	/* **AND A SESSION THAT WAS A SHEET'S TAKES THE ATTACHMENT DOWN.** The code is the one the session ended with, so a
	 * sheet ended by `-stopModalWithCode:` reports that code to its parent's own bookkeeping. The parent is not retained:
	 * it outlives the sheet it is showing, which is the same rule every parent link in this class follows. */
	if (s->sheetParent != nil) {
		[self endSheet:s->window returnCode:s->code];
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

/* **THE HELP SEARCH, IN ONE PASS OVER THE ITEM'S STRING.** Apple's Help menu filters items by what a person has typed.
 * The comparison is CASE-INSENSITIVE and the item's `&` MNEMONIC MARK is skipped: a title of "Save &As…" is read as
 * "Save As…" for someone typing, so an ampersand in the search string is not expected and one in the title must not shift
 * the match. THE RANGE IS WHERE THE SEARCH IS LOOKED FOR, and the answer is the MATCHED SUBSTRING (not the whole title),
 * which is what makes a menu highlight the letters it found. */
- (NSString *)searchString:(NSString *)searchString
  inUserInterfaceItemString:(NSString *)stringToSearch
	       searchRange:(NSRange)searchRange
		foundRange:(NSRangePointer)foundRange
{
	NSString *haystack;
	NSRange found;

	if (foundRange != NULL) {
		*foundRange = NSMakeRange(NSNotFound, 0);
	}
	if ([searchString length] == 0 || stringToSearch == nil) {
		return nil;
	}
	haystack = [stringToSearch stringByReplacingOccurrencesOfString:@"&" withString:@""];
	if (searchRange.location == NSNotFound || NSMaxRange(searchRange) > [haystack length]) {
		searchRange = NSMakeRange(0, [haystack length]);
	}
	found = [haystack rangeOfString:searchString options:NSCaseInsensitiveSearch range:searchRange];
	if (found.location == NSNotFound) {
		return nil;
	}
	if (foundRange != NULL) {
		*foundRange = found;
	}
	return [haystack substringWithRange:found];
}

- (BOOL)isHidden
{
	return _hidden;
}

- (NSGraphicsContext *)context
{
	/* **APPLE'S OWN ANSWER IS nil, IN AS MANY WORDS**: "This method does nothing and returns nil." A ported caller sends
	 * it and expects nothing back; answering the current context would be a different (and wrong) door. */
	return nil;
}

/* **A PRINT REQUEST IS THE DELEGATE'S FIRST, AND THE DOCUMENT CONTROLLER'S SECOND.** Apple's delegate door
 * (`-application:printFiles:withSettings:showPrintPanels:`) is asked when a delegate implements it; otherwise each file is
 * opened as a document and printed through the document, which is the path a file manager's "Print" takes. The reply is
 * the launch's: success when at least one document printed, failure when none did, and cancel when there was nothing to
 * print at all. */
- (void)application:(id)sender printFiles:(NSArray *)filenames
{
	id delegate = [self delegate];

	(void)sender;
	if (filenames == nil || [filenames count] == 0) {
		[self replyToOpenOrPrint:NSApplicationDelegateReplyCancel];
		return;
	}
	if ([delegate respondsToSelector:@selector(application:printFiles:withSettings:showPrintPanels:)]) {
		NSApplicationPrintReply reply = (NSApplicationPrintReply)[delegate application:self printFiles:filenames
									      withSettings:nil showPrintPanels:YES];

		[self replyToOpenOrPrint:(reply == NSPrintingSuccess) ? NSApplicationDelegateReplySuccess
								     : NSApplicationDelegateReplyFailure];
		return;
	}
	{
		NSDocumentController *controller = [NSDocumentController sharedDocumentController];
		BOOL printed = NO;
		NSUInteger i;

		for (i = 0; i < [filenames count]; i++) {
			NSURL *url = [NSURL fileURLWithPath:[filenames objectAtIndex:i]];
			NSError *error = nil;
			id document = [controller openDocumentWithContentsOfURL:url display:NO error:&error];

			if (document != nil) {
				[document printDocument:self];
				printed = YES;
			}
		}
		[self replyToOpenOrPrint:printed ? NSApplicationDelegateReplySuccess : NSApplicationDelegateReplyFailure];
	}
}

- (void)stopModal
{
	[self stopModalWithCode:NSRunStoppedResponse];
}

- (void)stopModalWithCode:(NSInteger)returnCode
{
	struct AGModalSession *s = (struct AGModalSession *)_modalSession;

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


/* ==================================================================================================================
 * THE ENTRY POINT AND THE SERVICES DOORS.
 *
 * **`NSApplicationMain` IS DELIBERATELY THE SMALLEST THING THAT IS HONEST.** Apple's also reads `NSMainNibFile` from the
 * main bundle and loads it before launching; this tier's applications load their own interface (the Workspace builds
 * its menu and windows in code), so the function launches and runs and says here that it does not read that key —
 * rather than shipping a lookup for a plist convention nothing in this tree uses.
 *
 * THE SERVICES DOORS WRITE AND READ THE STATE `-servicesProvider` AND `-servicesMenu` ALREADY HOLD. A second registry
 * inside AppKit would be the second source of truth the plan forbids, so `NSRegisterServicesProvider` is the C form of
 * the setter that already exists.
 */

#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>

int NSApplicationMain(int argc, const char *argv[])
{
	/* **THE PRINCIPAL CLASS IS SELECTED BEFORE THE INSTANCE EXISTS**, which is the only order that can work: the
	 * class decides what the instance is. `+sharedApplication` performs the selection, so this door needs to say
	 * nothing — but it is worth stating here, because "NSApplicationMain has no principal-class selection" was
	 * a reported limitation and the answer is that the selection moved to the door both callers share. */
	NSApplication *application = [NSApplication sharedApplication];

	(void)argc;
	(void)argv;
	[application finishLaunching];
	[application run];
	return 0;
}

void NSRegisterServicesProvider(id provider, NSString *name)
{
	/* THE NAME IS THE ERA'S PROVIDER IDENTITY and there is no registry of them here, so the APPLICATION's single
	 * provider slot is what a registration fills. */
	(void)name;
	[[NSApplication sharedApplication] setServicesProvider:provider];
}

void NSUnregisterServicesProvider(NSString *name)
{
	(void)name;
	[[NSApplication sharedApplication] setServicesProvider:nil];
}

/* THE ERA'S "SHOULD THIS SERVICE APPEAR IN THE MENU" BIT, held as the set of names that are HIDDEN so the default for
 * an unmentioned service stays visible — which is the direction the era's callers depended on. */
static NSMutableSet *fn_hiddenServiceItems(void)
{
	static NSMutableSet *hidden = nil;

	if (hidden == nil) {
		hidden = [[NSMutableSet alloc] init];
	}
	return hidden;
}

NSInteger NSSetShowsServicesMenuItem(NSString *itemName, BOOL enabled)
{
	if (itemName == nil) {
		return 0;
	}
	if (enabled) {
		[fn_hiddenServiceItems() removeObject:itemName];
	} else {
		[fn_hiddenServiceItems() addObject:itemName];
	}
	return 1;
}

BOOL NSShowsServicesMenuItem(NSString *itemName)
{
	if (itemName == nil) {
		return NO;
	}
	return [fn_hiddenServiceItems() containsObject:itemName] ? NO : YES;
}

/* **A SERVICE IS FOUND BY ITS MENU TITLE, WHICH IS WHAT THE ERA'S `itemName` WAS.** The search is over the application's
 * services menu, top level only: a submenu is a group heading rather than a service, and descending into one would run
 * something the caller did not name. Not finding it is `NO` — the documented answer for "this service is not offered",
 * and the reason the return value exists at all.
 */
BOOL NSPerformService(NSString *itemName, NSPasteboard *pboard)
{
	NSApplication *application = [NSApplication sharedApplication];
	NSMenu *services = (NSMenu *)[application servicesMenu];
	NSInteger i, count;

	if (itemName == nil || services == nil) {
		return NO;
	}
	count = [services numberOfItems];
	for (i = 0; i < count; i++) {
		NSMenuItem *item = [services itemAtIndex:i];

		if (item == nil || ![itemName isEqualToString:[item title]]) {
			continue;
		}
		if ([item action] == NULL) {
			continue;
		}
		(void)pboard;	/* the pasteboard is the selection the application already published */
		return [application sendAction:[item action] to:[item target] from:item] ? YES : NO;
	}
	return NO;
}

void NSUpdateDynamicServices(void)
{
	/* **THERE IS NO DYNAMIC PROVIDER REGISTRY TO REFRESH.** Apple's collects services advertised by other applications;
	 * this tier's services come from the application's own menu, which needs no re-scan. A no-op with a reason is the
	 * honest shape; a refusal would be louder and less true, because nothing is missing — there is nothing to do. */
}
