/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSApplication.h — the application object, and the RUN LOOP (stage C; appkit-plan D1).
 *
 * **THE RUN LOOP IS THE THING STAGE A BUILT THE RESPONDER CHAIN FOR.** An `NSApplication` owns the windows,
 * knows which is key and which is main, drains THEIR event pumps and hands what it drains to `-sendEvent:`,
 * which is where a key event reaches the key window and a click reaches the window it happened in. Until
 * this class existed a window could deliver an event and nothing could ask it to.
 *
 * AND IT TAKES THE FIRST RESPONDER'S PLACE AT THE END OF THE CHAIN, which is what `NSResponder`'s
 * `-nextResponder` was waiting for: `NSView` → its superview → … → the window → the application. The
 * `-tryToPerform:with:` this class inherits therefore reaches the APPLICATION last, and that is what an
 * action sent to `nil` means.
 *
 * AND THE MODAL SESSIONS *ARE* HERE — one slice after this note said they were not. `-runModalSession:` runs the
 * SAME pump the run loop runs, one pass at a time, so a modal loop is not a second event system with a different
 * way out but the same one with a different exit. What is MISSING from them is said where they are implemented:
 * the mode is passed and not routed by, and there is no dock for a request for the user's attention to bounce.
 *
 * **THE SHEETS ARE HERE NOW, AND THE SENTENCE THAT SAID THEY WERE NOT IS CORRECTED RATHER THAN DELETED** — the note
 * above about the modal sessions is the same correction a slice earlier. `-beginSheet:modalForWindow:...` and
 * `-endSheet:returnCode:` attach a window to a parent, announce the session (Will and Did) and run the reply dance,
 * which is exactly what this list used to defer. WHAT IS STILL NOT HERE: the standard panel CLASSES (about, colour,
 * font, page layout) — `NSPanel`, the window a panel is made of, is `NSPanel.h` and is not one of these — the SERVICES
 * menu and the HELP/Toolbar/StatusBar plumbing, which need the frameworks of stages E through I; and the scripting
 * doors, which need an OSA this tree does not have. Each is a later stage's.
 */

#ifndef APPKIT_NSAPPLICATION_H
#define APPKIT_NSAPPLICATION_H

#import <AppKit/NSResponder.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

@class NSEvent;
@class NSException;
@class NSWindow;

/* THE MODE A MODAL LOOP RUNS IN. Apple's value IS its own name, and this class's probe asserts that rather than
 * trusting it: a constant carrying a different string would be a wrong value in the one place a caller hands it to
 * a pump.
 *
 * AND `NSEventTrackingRunLoopMode` IS HERE TOO, WHICH REVERSES A NOTE THIS HEADER USED TO CARRY. It said the
 * second name would promise a distinction that does not exist — and the distinction still does not exist, because
 * this tier's pump takes a mode and does not route by one. What changed is that the name is APPLE'S OWN API at
 * the era pin, so it is OWED rather than owed-against: both constants are declared, neither is honoured, and that
 * is stated here and where the pump is called. */
extern NSString *NSModalPanelRunLoopMode;
extern NSString *NSEventTrackingRunLoopMode;

/* THE ACTIVATION POLICY, whose values are the era header's (a plain `NSInteger` at this pin, so the cases are
 * an anonymous enum). And the three modal-session replies, which `-runModalForWindow:` and its family return —
 * declared because a caller's `switch` needs them, and the modal doors below are what return them. */
enum {
	NSApplicationActivationPolicyRegular = 0,
	NSApplicationActivationPolicyAccessory = 1,
	NSApplicationActivationPolicyProhibited = 2
};
/* AND THE TYPE THAT NAMES THAT ENUM, which the anonymous form left unnamed: a caller stores a policy in it and a
 * door takes one, so the name is API rather than decoration. */
typedef NSInteger NSApplicationActivationPolicy;

/* THE ACTIVATION OPTIONS, WHICH USED TO BE DECLARED HERE. They are Apple's `NSRunningApplication.h` declarations,
 * and this header used to carry the copy with a note that the class that owns them on the Mac had not been declared
 * in this tree. `NSRunningApplication` exists now, so they live there, where Apple has them — include
 * `<AppKit/NSRunningApplication.h>` to use them. Nothing in this class took one, which is why moving them broke
 * nothing.
 *
 * `NSUserInterfaceLayoutDirection` is this header's own and stays. */
enum {
	NSUserInterfaceLayoutDirectionLeftToRight = 0,
	NSUserInterfaceLayoutDirectionRightToLeft = 1
};
typedef NSInteger NSUserInterfaceLayoutDirection;

/* AND THE TWO GLOBALS THAT MAKE AN APPLICATION REACHABLE BY NAME. `NSApp` is `id` in Apple's own header — not
 * `NSApplication *` — and it is set where the one object is made, so a caller never has to keep it in step. */
extern id NSApp;

/* THE ONE C FUNCTION THIS CLASS OWNS. Apple's contract is for a Cocoa BUNDLE loaded into a CARBON application:
 * it initializes AppKit, and redundant calls are ignored. See the implementation for what of that is real here. */
BOOL NSApplicationLoad(void);

/* AND THE ONE NOTIFICATION A SCREEN CHANGE WOULD POST, whose name is its own string like every other. Nothing
 * posts it yet — this tier notices no screen change — and that is said rather than left to be discovered. */
extern NSString *NSApplicationDidChangeScreenParametersNotification;

enum {
	NSRunStoppedResponse = -1000,
	NSRunAbortedResponse = -1001,
	NSRunContinuesResponse = -1002
};

/* THE ORDERING CONSTANTS `-setWindowsNeedUpdate:`'s machinery uses, from the era header. */
enum {
	NSUpdateWindowsRunLoopOrdering = 500000,
	NSDisplayWindowRunLoopOrdering = 200000,
	NSResetCursorRectsRunLoopOrdering = 100000
};

/* ============================================================================================ *
 * THE MODAL SESSION: A WINDOW THAT OWNS ITS OWN EVENT LOOP.                                     *
 *                                                                                                *
 * A MODAL WINDOW IS NOT A FLAG — it is a NESTED LOOP, and what makes it nested here is that it  *
 * runs the SAME `-nextEventMatchingMask:` the run loop runs, ONE PASS AT A TIME. That is why    *
 * `-runModalForWindow:` can be a loop over `-runModalSession:` rather than a second event       *
 * system: there is one pump in this class, and a session is a different way out of it.          *
 *                                                                                                *
 * `NSModalSession` IS AN OPAQUE POINTER TO AN INCOMPLETE STRUCT, which is Apple's own shape: a  *
 * caller can hold one and hand it back, and cannot see what is behind it — which is what lets   *
 * the whole implementation live in the `.m`.                                                    *
 * ============================================================================================ */
typedef struct _NSModalSession *NSModalSession;

/* NAMED BECAUSE THE DOORS BELOW NAME IT. A forward declaration only flips a `class` row the ledger still holds
 * OPEN, and NSImage's is shipped — the same reasoning NSView.h records for its own. */
@class NSImage;

/* **THE REPLIES A DELEGATE SENDS BACK, WITH APPLE'S OWN PROSE FOR EACH.** Its 10.6 header gives the three values
 * and then says what they answer:
 *
 *   "-replyToApplicationShouldTerminate: — If an application delegate returns NSTerminateLater from
 *    -applicationShouldTerminate:, -replyToApplicationShouldTerminate: must be called with YES or NO once the
 *    application decides if it can terminate."
 *
 *   "If an application delegate encounters an error while handling -application:openFiles: or
 *    -application:printFiles:, -replyToOpenOrPrint: should be called with NSApplicationDelegateReplyFailure. If the
 *    user cancels the operation, NSApplicationDelegateReplyCancel should be used, and if the operation succeeds,
 *    NSApplicationDelegateReplySuccess."
 *
 * THE VALUES ARE APPLE'S (0, 1, 2) and the reply is a plain `NSUInteger`. */
enum {
	NSApplicationDelegateReplySuccess = 0,
	NSApplicationDelegateReplyCancel = 1,
	NSApplicationDelegateReplyFailure = 2
};
typedef NSUInteger NSApplicationDelegateReply;


/* AND WHAT A REQUEST FOR THE USER'S ATTENTION IS, in Apple's two kinds; the values are the era header's. */
typedef NSUInteger NSRequestUserAttentionType;

enum {
	NSCriticalRequest = 0,
	NSInformationalRequest = 10
};

/* ============================================================================================ *
 * THE PRESENTATION OPTIONS.                                                                     *
 * ============================================================================================ */

/* Apple's 10.6 header carries EVERY value AND a comment saying what each one does, so both are quoted rather than
 * paraphrased — and the pairing is visible in the comments themselves: `AutoHideDock` is "Dock appears when moused
 * to" while `HideDock` is "Dock is entirely unavailable". */
enum {
	NSApplicationPresentationDefault = 0,
	NSApplicationPresentationAutoHideDock = (1 << 0),		/* Dock appears when moused to */
	NSApplicationPresentationHideDock = (1 << 1),			/* Dock is entirely unavailable */
	NSApplicationPresentationAutoHideMenuBar = (1 << 2),		/* Menu Bar appears when moused to */
	NSApplicationPresentationHideMenuBar = (1 << 3),		/* Menu Bar is entirely unavailable */
	NSApplicationPresentationDisableAppleMenu = (1 << 4),		/* all Apple menu items are disabled */
	NSApplicationPresentationDisableProcessSwitching = (1 << 5),	/* Cmd+Tab UI is disabled */
	NSApplicationPresentationDisableForceQuit = (1 << 6),		/* Cmd+Opt+Esc panel is disabled */
	NSApplicationPresentationDisableSessionTermination = (1 << 7),	/* the power key panel is disabled */
	NSApplicationPresentationDisableHideApplication = (1 << 8),	/* the "Hide" menu item is disabled */
	NSApplicationPresentationDisableMenuBarTransparency = (1 << 9)	/* the Menu Bar is never transparent */
};
typedef NSUInteger NSApplicationPresentationOptions;

@interface NSApplication : NSResponder
{
	/* THE WINDOWS, FRONT FIRST, which is also the order a run-loop pass drains them in. */
	id _windows;
	NSWindow *_keyWindow;
	NSWindow *_mainWindow;
	/* POSTED EVENTS. A posted event is not a server event: it was made by a caller and it is kept here until
	 * the pump takes it, which is what `-postEvent:atStart:` means. */
	id _eventQueue;
	id _delegate;               /* NOT retained — Apple's contract for a delegate, as for a window's */
	BOOL _running;
	BOOL _stopped;
	BOOL _launched;
	BOOL _hidden;
	BOOL _windowsNeedUpdate;
	NSInteger _activationPolicy;
	/* THE MODAL SESSION IN FLIGHT, if any. `NSModalSession` is opaque, so a caller never sees what is behind it:
	 * this holds the one the application is running, and `_modalWindow` is that window BORROWED — the caller owns
	 * the window it handed in. */
	void *_modalSession;
	NSWindow *_modalWindow;
	/* AND WHAT THE APPLICATION RECORDS ABOUT THE USER'S ATTENTION — see the two doors. */
	NSInteger _attentionCounter;
	/* WHETHER THE APPLICATION HAS BEEN ASKED TO STOP ORDERING WINDOWS: `-preventWindowOrdering` sets it, the seam
	 * `-cg_preventsWindowOrdering` reports it, and activation and unhiding consult it. */
	BOOL _preventsOrdering;
	/* **WHAT THIS APPLICATION HAS ASKED THE SYSTEM TO PRESENT** — the options `-setPresentationOptions:` accepted,
	 * which is also what `-currentSystemPresentationOptions` reports, because nothing else in this tier changes
	 * the system's presentation (see the doors). Zero is `NSApplicationPresentationDefault`. */
	NSUInteger _presentationOptions;
	/* **THE WINDOWS THIS APPLICATION ITSELF HID WHEN IT DEACTIVATED**, so that activating brings back exactly those
	 * and not a window a caller had already ordered out. The application owns this list because the application is
	 * what performed the act — the same reason the window registry lives here. */
	NSMutableArray *_cg_deactivatedWindows;
	/* **WHETHER A TERMINATION IS WAITING ON THE DELEGATE.** `-applicationShouldTerminate:` answering `NSTerminateLater`
	 * means "ask me again", and this is what remembers that the question is open. */
	BOOL _cg_waitingForTerminateReply;
	/* AND THE LAST OPEN/PRINT REPLY, which nothing reads — see the door. */
	NSApplicationDelegateReply _cg_lastOpenOrPrintReply;
	/* WHAT THE DOORS ABOVE STORE OR TRACK. */
	BOOL _active;
	NSImage *_applicationIconImage;
	id _servicesProvider;
	NSArray *_servicesSendTypes;
	NSArray *_servicesReturnTypes;
	NSMutableArray *_searchHandlers;
	NSString *_searchString;
	id _mainMenu;
	/* **AND THE BAR ITSELF, WHICH IS A WINDOW THE APPLICATION OWNS.** The Window Server owns the strip and the
	 * SYSTEM menu at its left; these menus are the application's and so is the window they are drawn in — which is
	 * why it sits at `NSMainMenuWindowLevel`: above the server's strip, and BELOW the status items, which are other
	 * CLIENTS. Both start nil and are made the first time a main menu is set on a connection that can say where the
	 * bar's free space begins. */
	id _menuBarWindow;
	id _menuBarView;
	id _windowsMenu;
	id _servicesMenu;
	id _helpMenu;
	/* NOT RETAINED, as Apple's is not: the door reports the event being processed. */
	NSEvent *_cg_currentEvent;
	/* **AND THE MENU THIS APPLICATION GAVE THE DOCK.** A tile's menu crosses to another process as a DESCRIPTION and
	 * only its ids come back — so the tree those ids name has to be kept here, and it is RETAINED because the Dock
	 * may take its time and the menu must outlive the answer that described it. Replaced on every ask; see
	 * `-cg_dockMenu`. */
	id _cg_dockMenu;
}

/* THE ONE APPLICATION OBJECT. Apple's is made on first ask and lives for the process; `-run` refuses to do
 * anything on anything else, which is the contract a caller cannot break by construction. */
/* **THE TWO DOORS.** `-replyToApplicationShouldTerminate:` is the one this class's `-terminate:` has pointed at
 * since it was written — that method's own comment said a MAYBE "is not YES" and that a reply door it had not got
 * was the reason a later answer could not stop the application. It has one now, and it runs the SAME tail an
 * immediate yes runs (see the implementation), so the two cannot drift apart.
 *
 * `-replyToOpenOrPrint:` IS RECORDED AND NOTHING ASKS: there is no `-application:openFiles:` or
 * `-application:printFiles:` request in this tier — both need an Apple Event this tree does not receive — so a
 * delegate that calls this unconditionally is answered by a door that keeps the last reply rather than dropping it. */

/* ============================================================================================ *
 * THE APPLICATION'S LAST ROWS: THREE THAT ANSWER, FOUR THAT STORE, AND EIGHT THAT REFUSE.        *
 * ============================================================================================ */

/* **THE THREE THAT ARE REAL ANSWERS.** `-isActive` reports the activation state this class ALREADY tracks — the
 * doors that change it are `-activateIgnoringOtherApps:` and `-deactivate` — so the flag is set there rather than
 * invented here. `-orderedWindows` is the same list `-windows` answers with, and this tier does not reorder it by
 * depth because the ordering is the manager's (D5); `-orderedDocuments` is an EMPTY ARRAY, which is Apple's own
 * contract for an application with no open documents rather than a refusal. */
- (BOOL)isActive;
- (nullable NSArray *)orderedWindows;
- (nullable NSArray *)orderedDocuments;

/* AND THE FOUR THAT ARE STORED, with the effect named: an application icon is the Dock's or the manager's to draw, a
 * services provider and a Services menu's send types are read by a Services menu this tier has not got, and the
 * interface-item search handlers are read by a Help search field this tier has not got either. */
- (void)setApplicationIconImage:(nullable NSImage *)image;
- (nullable NSImage *)applicationIconImage;
- (void)setServicesProvider:(nullable id)provider;
- (nullable id)servicesProvider;
- (void)registerServicesMenuSendTypes:(nullable NSArray *)sendTypes returnTypes:(nullable NSArray *)returnTypes;
- (void)registerUserInterfaceItemSearchHandler:(id)handler;
- (void)unregisterUserInterfaceItemSearchHandler:(id)handler;

/* **AND THE MENUS ANSWER NIL, WITH THEIR SETTERS RECORDING WHAT THEY WERE GIVEN.** Apple's doors return the
 * application's menus. THIS USED TO SAY "this tier has no `NSMenu`" AND THAT IS NO LONGER TRUE — menus shipped at stage
 * D and are what the bar is made of — so the reason is now the real one: the menu bar belongs to the WINDOW SERVER,
 * which owns the strip and tells a client where it is, and this class carries no menu of its own to hand back. A
 * setter that kept the object would only be something else to leak — WHAT IT RECORDS IS THAT IT WAS CALLED, which is
 * the state `-servicesProvider` and the search handlers also keep, and the reason the setters exist at all is that a
 * ported program calls them. */
- (void)setMainMenu:(nullable id)menu;
- (nullable id)mainMenu;

/* **THE APPLICATION'S WINDOWS.** Apple's own door, and it is here because the MENU BAR is one of them: a caller
 * that wants to know which window the bar is — a test, or an application arranging its own furniture — has no
 * other way to ask. The ORDER is the registry's, which is the order windows were ordered in. */
@property (readonly) NSArray *windows;
- (void)setWindowsMenu:(nullable id)menu;
- (nullable id)windowsMenu;
- (void)setServicesMenu:(nullable id)menu;
- (nullable id)servicesMenu;
- (void)setHelpMenu:(nullable id)menu;
- (nullable id)helpMenu;

/* AND TWO SYSTEM-FACING QUESTIONS THIS TIER ANSWERS FROM WHAT IT KNOWS RATHER THAN FROM A SETTING: full keyboard
 * access is a SYSTEM preference there is no door to here, and the interface layout direction is this tree's own
 * enum, whose values nobody publishes — the standing rule, so the order is the artefact's. */
- (BOOL)isFullKeyboardAccessEnabled;
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection;

/* ============================================================================================ *
 * THE EIGHT THAT REFUSE, EACH NAMING WHAT IT NEEDS.                                             *
 * ============================================================================================ */
- (void)activateContextHelpMode:(nullable id)sender;	/* needs the Help system */
- (void)showHelp:(nullable id)sender;			/* the same, and a Help book to show */
- (void)changeWindowsItem:(nullable id)win title:(nullable NSString *)aString filename:(BOOL)isFilename;	/* the Windows menu */
- (void)orderFrontCharacterPalette:(nullable id)sender;	/* the character palette */
- (void)orderFrontColorPanel:(nullable id)sender;	/* NSColorPanel */
- (void)orderFrontStandardAboutPanel:(nullable id)sender;/* a panel AND text drawing, neither of which this tier has */
- (void)orderFrontStandardAboutPanelWithOptions:(nullable NSDictionary *)optionsDictionary;
- (void)runPageLayout:(nullable id)sender;		/* the page layout panel (NSPageLayout) */

/* AND ONE THAT IS REAL RATHER THAN A REFUSAL, because Foundation has the thread: `+detachDrawingThread:toTarget:`
 * is the pre-10.0 spelling of `+[NSThread detachNewThreadSelector:toTarget:withObject:]` and it still works. */
+ (void)detachDrawingThread:(SEL)selector toTarget:(nullable id)target withObject:(nullable id)argument;

/* AND `-searchString`, the Help search text, which is nil until a search happens — a NICER answer here than the
 * Help doors above can give, because the state it reports is one this class owns. */
- (nullable NSString *)searchString;

/* ============================================================================================ *
 * AND THE THREE ALERT RETURN VALUES HAVE MOVED TO `NSAlert.h`, WHERE APPLE PUTS THEM.             *
 * ============================================================================================ */

/* They were declared here while this tree had no `NSAlert` — the numbers are what a caller's `switch` needs, so they
 * could not wait for the class. Now the class exists, and the constants live beside it: Apple's own `NSAlert.h`
 * declares `NSAlertFirstButtonReturn`, `NSAlertSecondButtonReturn` and `NSAlertThirdButtonReturn`, and a caller that
 * includes `<AppKit/NSAlert.h>` gets them. `NSApplication -runModalForWindow:` still returns whatever code it was
 * stopped with, so a door in this file can answer 1000 without knowing the name. */

/* AND `-userInterfaceLayoutDirection` ANSWERS THE ENUM THIS TIER ALREADY DECLARES — the first draft of this block
 * declared its own and the compiler said `redefinition of enumerator`, which is the tree telling me the type was
 * already here rather than that the values were wrong. */

- (void)replyToApplicationShouldTerminate:(BOOL)shouldTerminate;
- (void)replyToOpenOrPrint:(NSApplicationDelegateReply)reply;

+ (NSApplication *)sharedApplication;

/* **WHICH CLASS THE ONE APPLICATION IS.** `+sharedApplication` used to construct `[[NSApplication alloc] init]`
 * whatever the receiving class was, so an application that subclassed this class to customize event dispatch, own
 * background work or extend the lifecycle had no supported way to be the object `NSApp` names. It now chooses, in
 * this order: the class set here; `NSPrincipalClass` from the main bundle's `Info.plist`, which is Apple's own key;
 * and otherwise the receiving class, so `[MyApplication sharedApplication]` answers a `MyApplication`.
 *
 * The class must be a subclass of `NSApplication`, and it must be chosen BEFORE the application exists — the
 * instance is one, so changing it afterwards would leave `NSApp` naming an object of a class nobody asked for.
 * Both refusals are printed rather than raised, for the reason this tree's other refusals are: a bootstrap
 * mistake should say what it was and let the program continue with the default. This is an Agora extension; it is
 * not in Apple's 10.6 surface. */
+ (void)setSharedApplicationClass:(Class)aClass;

- (nullable id)delegate;
- (void)setDelegate:(nullable id)anObject;

/* LAUNCHING AND RUNNING. `-finishLaunching` posts the delegate's will/did-finish pair; `-run` launches and
 * then loops until `-stop:` — and it never returns until it stops, which is Apple's contract. */
- (void)finishLaunching;
- (void)run;
- (BOOL)isRunning;
- (void)stop:(nullable id)sender;
- (void)terminate:(nullable id)sender;

/* THE PUMP AT THE APPLICATION LEVEL, which is the door that MAKES the loop work: it drains the posted queue
 * first, then asks every window for an event, and only waits on the connection when none has one. */
- (nullable NSEvent *)nextEventMatchingMask:(NSUInteger)mask
				  untilDate:(nullable NSDate *)expiration
				     inMode:(nullable NSString *)mode
				    dequeue:(BOOL)deqFlag;
- (void)sendEvent:(NSEvent *)theEvent;
- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag;
- (void)discardEventsMatchingMask:(NSUInteger)mask beforeEvent:(nullable NSEvent *)lastEvent;

/* THE WINDOW REGISTRY. A window added here is one the run loop drains; the KEY window is where a key event
 * goes and the MAIN window is the one a menu belongs to. */
- (nullable NSArray *)windows;
- (nullable NSWindow *)keyWindow;
- (nullable NSWindow *)mainWindow;
- (nullable NSWindow *)windowWithWindowNumber:(NSInteger)windowNum;
- (void)addWindowsItem:(NSWindow *)aWindow title:(NSString *)aString filename:(BOOL)isFilename;
- (void)removeWindowsItem:(NSWindow *)aWindow;
- (void)makeWindowsPerform:(nullable SEL)aSelector inOrder:(BOOL)flag;

/* THE TWO DOORS THAT DRIVE THE WINDOWS' DRAWING FROM THE LOOP: marking them all, and displaying the ones
 * that asked. `-updateWindowsItem:` is the WINDOW MENU's and needs a menu, which is stage D's. */
- (void)setWindowsNeedUpdate:(BOOL)flag;
- (void)updateWindows;
- (void)updateWindowsItem:(NSWindow *)aWindow;



/* THE ACTION DOORS, which are how a target/action pair reaches an object that may not be the sender: `to:nil`
 * walks the responder chain, and THIS class is its last link. */
- (BOOL)sendAction:(nullable SEL)anAction to:(nullable id)theTarget from:(nullable id)sender;
- (nullable id)targetForAction:(nullable SEL)anAction;

/* **AND THE THREE-ARGUMENT FORM, WHICH IS WHERE THE SENDER DECIDES WHERE THE SEARCH STARTS.** Apple's `-targetForAction:`
 * is this door with no sender; with a sender that IS a responder, the walk starts at the SENDER (its own chain) rather
 * than at the key window's first responder — which is what makes a menu item's action find the view the click came from.
 * `-sendAction:to:from:` is what a caller usually does; this is the question behind it, asked aloud. */
- (nullable id)targetForAction:(nullable SEL)anAction to:(nullable id)aTarget from:(nullable id)sender;

/* **AND THE HELP SEARCH, WHICH IS A STRING SEARCH AND NOT A UI INDEX.** Apple's Help menu filters its items by what a
 * person has typed; the door takes the typed string, the item's string, a range to search in, and answers the MATCHED
 * SUBSTRING (and writes its range) or nil. A leading `&` in an item's title marks a keyboard mnemonic and is not part of
 * what a person sees, so the search SKIPS it when comparing — see the implementation for the one-pass rule. */
- (nullable NSString *)searchString:(nullable NSString *)searchString
	  inUserInterfaceItemString:(nullable NSString *)stringToSearch
		       searchRange:(NSRange)searchRange
			foundRange:(nullable NSRangePointer)foundRange;

/* ACTIVATION AND HIDING. With no window manager of this tree's own (Kestrel is parked) these are the
 * application's own state plus the window verbs they imply — stated rather than pretending to talk to one. */
- (void)activateIgnoringOtherApps:(BOOL)flag;
- (void)activate;
- (void)deactivate;
- (void)hide:(nullable id)sender;
- (void)unhide:(nullable id)sender;
- (void)unhideWithoutActivation;
- (void)hideOtherApplications:(nullable id)sender;
- (void)unhideAllApplications:(nullable id)sender;

- (NSInteger)activationPolicy;


/* **AND THE DOOR THAT TAKES THEM, WHOSE OWN PROSE STATES THE RULE THIS TIER ENFORCES.** Apple's header says:
 *
 *   "Gets or sets the presentationOptions that should be in effect for the system when this application is the
 *    active application. Only certain combinations of NSApplicationPresentationOptions flags are allowed, as
 *    detailed in the AppKit Release Notes and the reference documentation for -setPresentationOptions:. When given
 *    an invalid combination of option flags, -setPresentationOptions: raises an exception."
 *
 * SO AN INVALID COMBINATION IS AN EXCEPTION RATHER THAN A SILENT CLAMP, and the one rule that CAN be read off the
 * header rather than the release notes it points at is the CONTRADICTORY PAIR: a flag saying a thing appears when
 * moused to and a flag saying the same thing is unavailable cannot both be asked for. Two such pairs exist — the
 * Dock's and the menu bar's — and asking for both members of either raises `NSInvalidArgumentException` naming the
 * pair. The rest of Apple's table (which combinations are legal beyond that) lives in documentation this tree does
 * not hold, so what is not enforced is not claimed: the other flags are recorded as asked.
 *
 * AND WHAT THE OPTIONS DO NOT DO IS NAMED HERE RATHER THAN IMPLIED. They describe a DOCK, a MENU BAR, a Cmd+Tab
 * switcher and a power-key panel — none of which is this process's to present. The dock and the menu bar belong to
 * the guest's window manager (D5/D6), and the session's panels belong to the session. So the request is RECORDED,
 * exactly as `NSWindow`'s collection behaviour is, and a manager that honours Cocoa's presentation reaches it
 * through this door. */
- (NSApplicationPresentationOptions)presentationOptions;
- (void)setPresentationOptions:(NSApplicationPresentationOptions)newOptions;

/* `-currentSystemPresentationOptions` IS READ-ONLY IN APPLE'S HEADER, and in this tier it answers the SAME value:
 * the system's presentation here is what this application asked for, because nothing else changes it — there is no
 * second process negotiating, and the session does not have a presentation of its own to report. */
- (NSApplicationPresentationOptions)currentSystemPresentationOptions;
- (BOOL)setActivationPolicy:(NSInteger)activationPolicy;

/* AND THE ONE EXCEPTION DOOR: a run loop that lets an exception escape kills the application, so Apple's
 * contract is that the loop reports it and carries on. */
- (void)reportException:(nullable NSException *)theException;

/* ---- MODAL SESSIONS ------------------------------------------------------------------------- */

/* THE TWO WAYS IN. `-runModalForWindow:` returns the code the session ended with, and it CANNOT be interrupted
 * except by `-stopModal`/`-abortModal` or by the application being stopped — Apple's own contract, and a real
 * hazard for a caller: one that has work to do between passes wants the SESSION doors below, not this one. */
/* ============================================================================================ *
 * THE SHEETS.                                                                                   *
 * ============================================================================================ */

/* **A SHEET IS A WINDOW-ATTACHED MODAL SESSION, AND APPLE'S OWN HEADER SAYS WHAT THE CALLBACK IS.** Quoted
 * verbatim from the 10.6 SDK, because the contract is not ours to invent:
 *
 *   "Present a sheet on the given window.  When the modal session is ended, the didEndSelector will be invoked in
 *    the modalDelegate.  The didEndSelector should have the following signature, and will be invoked when the
 *    modal session ends.  This method should dismiss the sheet using orderOut:
 *    - (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;"
 *
 * THREE THINGS FOLLOW FROM THAT PROSE, AND EACH ONE IS A DECISION THIS TIER COULD OTHERWISE GET WRONG:
 *
 *   1. THE CALLBACK DISMISSES THE SHEET, NOT `-endSheet:`. So ending a session does NOT order the sheet out — the
 *      sheet may still be on the screen when `-endSheet:returnCode:` returns, and the caller's own did-end method
 *      is what takes it off. That is Apple's sentence above, not a shortcut.
 *   2. THE REPLY IS A BARE SELECTOR, so this tier reaches it through `-methodForSelector:` and calls it with the
 *      three arguments above. A nil modalDelegate, or one that does not answer the selector, is NO CALLBACK rather
 *      than an error: Apple's signature allows a caller that only wants the attachment.
 *   3. ONE SHEET PER WINDOW. Apple's model attaches one at a time, so beginning a second on the same window is
 *      refused BY NAME (an `NSInvalidArgumentException`) rather than silently losing the first session's reply.
 *
 * AND WHAT IS NOT ENFORCED IS STATED RATHER THAN IMPLIED. A window with an attached sheet takes no input — that is
 * what window-modal means observably — and this tier enforces it in the ONE place it routes events,
 * `-sendEvent:`, by DROPPING an event aimed at the parent rather than delivering it (Apple disables the parent and
 * beeps; there is no beep here). It is not a grab the compositor knows about: nothing here negotiates with the
 * window manager, so a caller's key window is this application's own state and no more. */
- (void)beginSheet:(NSWindow *)sheet
    modalForWindow:(NSWindow *)docWindow
     modalDelegate:(nullable id)modalDelegate
    didEndSelector:(nullable SEL)didEndSelector
       contextInfo:(nullable void *)contextInfo;

/* `-endSheet:` CARRIES NO RETURN CODE OF ITS OWN. Apple's header publishes one only for the three-argument form
 * below, so a session ended through this door reads as 0 in the tier — which is NOT one of Apple's three run
 * responses (they are -1000/-1001/-1002, declared above), so it reads as "no code given" rather than as a response
 * in disguise. A caller that has a code uses the door that takes one. */
- (void)endSheet:(NSWindow *)sheet;
- (void)endSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode;

- (NSInteger)runModalForWindow:(NSWindow *)theWindow;

/* **AND THE TWO RELATIVES, WHICH RUN THE WINDOW AS A SHEET OF ANOTHER.** `-beginModalSessionForWindow:relativeToWindow:`
 * attaches the window to `docWindow` as a sheet and then begins a session for it — the pair a document's "are you sure?"
 * question uses — and the run form is the loop over that session. THE SESSION REMEMBERS ITS PARENT, so
 * `-endModalSession:` takes the sheet back down; that is the one piece of state these two doors need beyond the session
 * the class already keeps. */
- (nullable NSModalSession)beginModalSessionForWindow:(nullable NSWindow *)theWindow
				     relativeToWindow:(nullable NSWindow *)docWindow;
- (NSInteger)runModalForWindow:(nullable NSWindow *)theWindow relativeToWindow:(nullable NSWindow *)docWindow;

/* **AND THREE ONE-LINE DOORS THAT WERE SIMPLY ABSENT.** `-isHidden` is the flag `-hide:`/`-unhide:` already keep;
 * `-context` is Apple's own "does nothing and returns nil" (its 10.6 page says so in as many words), kept because a
 * ported caller sends it; and `-application:printFiles:` is a NAMED REFUSAL, because printing needs the print system
 * this tier has not got — the delegate door above already tells a delegate to reply FAILURE to it. */
- (BOOL)isHidden;
- (nullable NSGraphicsContext *)context;
- (void)application:(nullable id)sender printFiles:(nullable NSArray *)filenames;
/* AND THE WINDOW ARGUMENT IS `nullable` HERE, WHILE APPLE'S HEADER SPELLS IT NONNULL: this tree annotates
 * from what the IMPLEMENTATION accepts (the standing practice), and the implementation below answers NULL for
 * a nil window rather than making one. */
- (nullable NSModalSession)beginModalSessionForWindow:(nullable NSWindow *)theWindow;
/* ONE PASS. `NSRunContinuesResponse` means "call again"; anything else is the code the session ended with. */
- (NSInteger)runModalSession:(nullable NSModalSession)session;
- (void)endModalSession:(nullable NSModalSession)session;

/* AND THE THREE WAYS TO END ONE. `-stopModal` is `-stopModalWithCode:` with the STOPPED response and `-abortModal`
 * is the ABORTED one — the difference a caller reads to tell "the user answered" from "something cancelled it". */
- (void)stopModal;
- (void)stopModalWithCode:(NSInteger)returnCode;
- (void)abortModal;

/* THE WINDOW THE CURRENT SESSION IS FOR, nil when none is in flight. A getter rather than a `@property`, which is
 * the shape BOTH era headers use and the shape this ledger credits either way. */
- (nullable NSWindow *)modalWindow;

/* ---- THE DOORS THAT ACT ON EVERY WINDOW AT ONCE --------------------------------------------- */

/* `-arrangeInFront:` REUSES THE CASCADE the placement work already built — `-cascadeTopLeftFromPoint:` places a
 * window AND answers where the next one goes, which is exactly what arranging every window needs — and
 * `-miniaturizeAll:` is the same door the title bar's button sends, applied to each window. A second copy of
 * either arithmetic would be a second thing to keep true. */
- (void)arrangeInFront:(nullable id)sender;
- (void)miniaturizeAll:(nullable id)sender;
/* NOTHING ELSE MAY ORDER A WINDOW WHILE THIS IS SET, which is what a caller rearranging windows asks for. */
- (void)preventWindowOrdering;

/* ---- AND THE USER'S ATTENTION ---------------------------------------------------------------- */

/* RECORDED, NOT DISPLAYED, AND THAT IS STATED RATHER THAN FAKED. Apple's version bounces a dock icon; there is no
 * dock in this tier, so what is real here is the BOOKKEEPING — a request answers an ID of its own (a counter,
 * because nothing else in this tree identifies one) and cancelling is by that ID. The KIND is accepted and not
 * stored: nothing in this tier would read it. */
- (NSInteger)requestUserAttention:(NSRequestUserAttentionType)requestType;
- (void)cancelUserAttentionRequest:(NSInteger)request;


/* **THE LAST EVENT THIS APPLICATION DISPATCHED, AND THE DOCK TILE THIS TIER HAS NOT GOT.** Apple's `-currentEvent`
 * is "the event currently being processed" — the most recent one, outside processing — so `-sendEvent:` records it
 * as it dispatches, which makes the door a real answer rather than a nil. `-dockTile` answers nil because there is
 * no `NSDockTile` in this tier and no Dock to own one. */
- (nullable NSEvent *)currentEvent;
- (nullable id)dockTile;

@end

/* ============================================================================================ *
 * THE APPLICATION'S DELEGATE — AND, LIKE THE WINDOW'S, EVERY METHOD IS OPTIONAL.               *
 *                                                                                                *
 * THIS REPLACES AN INFORMAL `NSObject` CATEGORY that declared exactly two messages and said     *
 * "some object might answer these". A protocol says WHICH messages, WITH WHAT SIGNATURES — and  *
 * the two VALUE-RETURNING ones are why that matters here: `-applicationShouldTerminate:` can   *
 * STOP A TERMINATION, and a guessed signature would ask the question and ignore the answer.    *
 *                                                                                                *
 * THE VALUES BELOW WERE READ FROM APPLE'S OWN PUBLIC HEADER rather than invented: three         *
 * termination replies, four printing replies, and the two unsigned typedefs. They are NOT the   *
 * "values are ours" case Foundation's enums are — Apple publishes these in the header itself.   *
 *                                                                                                *
 * AND THE POST-10.6 CALLBACKS ARE STRUCK IN THE LEDGER WITH THIS CLASS: occlusion, protected    *
 * data, automatic key-equivalent localisation and secure restorable state are rows newer than   *
 * the era pins, and a protocol declaring them would promise a feature this tier has not got.    *
 * ============================================================================================ */
typedef NSUInteger NSApplicationTerminateReply;
typedef NSUInteger NSApplicationPrintReply;

enum {
	NSTerminateCancel = 0,	/* the application should NOT be terminated */
	NSTerminateNow = 1,	/* it is all right to proceed */
	NSTerminateLater = 2	/* MAYBE later — see the note in `-terminate:` about the reply door */
};

enum {
	NSPrintingCancelled = 0,
	NSPrintingSuccess = 1,
	NSPrintingFailure = 3,
	NSPrintingReplyLater = 2
};

/* THE NAMES THE DELEGATE'S CALLBACKS ARRIVE UNDER, whose values are their own identifiers. */
extern NSString *NSApplicationWillFinishLaunchingNotification;
extern NSString *NSApplicationDidFinishLaunchingNotification;
extern NSString *NSApplicationWillBecomeActiveNotification;
extern NSString *NSApplicationDidBecomeActiveNotification;
extern NSString *NSApplicationWillResignActiveNotification;
extern NSString *NSApplicationDidResignActiveNotification;
extern NSString *NSApplicationWillHideNotification;
extern NSString *NSApplicationDidHideNotification;
extern NSString *NSApplicationWillUnhideNotification;
extern NSString *NSApplicationDidUnhideNotification;
extern NSString *NSApplicationWillUpdateNotification;
extern NSString *NSApplicationDidUpdateNotification;
extern NSString *NSApplicationWillTerminateNotification;

@protocol NSApplicationDelegate <NSObject>
@optional
/* THE LAUNCH PAIR, then the lifecycle, each announced before and after. */
- (void)applicationWillFinishLaunching:(NSNotification *)notification;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (void)applicationWillBecomeActive:(NSNotification *)notification;
- (void)applicationDidBecomeActive:(NSNotification *)notification;
- (void)applicationWillResignActive:(NSNotification *)notification;
- (void)applicationDidResignActive:(NSNotification *)notification;
- (void)applicationWillHide:(NSNotification *)notification;
- (void)applicationDidHide:(NSNotification *)notification;
- (void)applicationWillUnhide:(NSNotification *)notification;
- (void)applicationDidUnhide:(NSNotification *)notification;
- (void)applicationWillUpdate:(NSNotification *)notification;
- (void)applicationDidUpdate:(NSNotification *)notification;
- (void)applicationWillTerminate:(NSNotification *)notification;
- (void)applicationDidChangeScreenParameters:(NSNotification *)notification;

/* AND THE ONES THAT ANSWER A QUESTION — which is where a delegate changes what happens. */
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender;
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag;
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender;
- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender;
/* THE PRINTING ONE, WHOSE SIGNATURE IS ALSO A TRANSCRIPTION — and whose name is the ledger's bare `-application`,
 * which is how a five-part selector is recorded. It is DECLARED AND NOT ASKED, because the printing half of this
 * framework is a subsystem this tier has not reached: a delegate may implement it, and nothing calls it yet. */
- (NSApplicationPrintReply)application:(NSApplication *)application
			    printFiles:(NSArray *)fileNames
			  withSettings:(NSDictionary *)printSettings
		      showPrintPanels:(BOOL)showPrintPanels;
/* AND THE DOCK MENU, WHOSE RETURN TYPE IS `id` HERE AND `NSMenu` IN APPLE'S HEADER. Menus are stage D, and a
 * `@class NSMenu` forward would FLIP the `class NSMenu` LEDGER ROW to shipped — a name-based ledger cannot tell
 * a forward declaration from a class, which is a trap this tree has already walked into once. So the type is
 * `id` and the reason is stated with it.
 *
 * **AND IT IS ASKED NOW.** It used to be declared and not asked, because "the dock" was an absence in this tier —
 * and the Dock is still a separate program, not a part of the framework. What changed is that there is a way for the
 * question to reach it across a connection: a shell component asks the application for the items of a tile's menu
 * (`agora_window.dock_menu_requested`), this class puts the question to its delegate and KEEPS the answer, and
 * `NSDockMenu` carries a description of it to the Dock and a chosen item's id back. See `NSDockMenu.h` for the two
 * halves and the format, and `-cg_dockMenu` in the implementation for the question itself.
 *
 * WHAT THE DOCK DOES WITH IT IS THE DOCK'S: Apple's composes the application's items with its own above them, and
 * Agora's Dock does the same — the answer here is the application's items ALONE. */
- (nullable id)applicationDockMenu:(NSApplication *)sender;
@end




/* ==================================================================================================================
 * THE ENTRY POINT AND THE SERVICES DOORS.
 *
 * **`NSApplicationMain` IS THE FUNCTION EVERY COCOA `main()` CALLS, AND ITS ABSENCE WAS VISIBLE IN THIS TREE'S OWN
 * SOURCE**: `workspace/src/main.m` hand-rolls "shared application, finish launching, run" because there was nothing to
 * call. That workaround is now optional rather than necessary.
 *
 * **THE APPLICATION-DEFINED MAIN NIB IS NOT LOADED HERE, AND THAT IS A DOCUMENTED DEVIATION.** Apple's
 * `NSApplicationMain` reads `NSMainNibFile` out of the main bundle's Info.plist and loads it before launching. This
 * tier's applications load their own interface, so the function does the three things it can do honestly and says so
 * at the definition rather than appearing to read a key it does not.
 *
 * THE SERVICES DOORS REACH THE STATE `-servicesProvider` AND `-servicesMenu` ALREADY KEEP, which is why they are
 * wrappers: a second registry inside AppKit would be the "second source of truth" the plan forbids.
 * ================================================================================================================ */

@class NSPasteboard;

int NSApplicationMain(int argc, const char *argv[]);
BOOL NSPerformService(NSString *itemName, NSPasteboard *pboard);
void NSRegisterServicesProvider(id provider, NSString *name);
void NSUnregisterServicesProvider(NSString *name);
NSInteger NSSetShowsServicesMenuItem(NSString *itemName, BOOL enabled);
BOOL NSShowsServicesMenuItem(NSString *itemName);
void NSUpdateDynamicServices(void);

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSAPPLICATION_H */
