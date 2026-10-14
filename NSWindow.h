/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSWindow.h — the window, and it is a window on AGORA'S WINDOW SERVER.
 *
 * **THE SEAM IS THIS TREE'S OWN AND THIS HEADER IS WHERE IT SHOWS.** `NSWindow : NSResponder` — the responder
 * base stage A shipped — and its implementation makes an `AGWindow` through `AGWindowServer.h`, which on this
 * platform is an `xdg-shell` client. The seam was Xlib when this file was imported (an X window made through
 * `XCreateSimpleWindow` and drawn with `XPutImage`), and that is GONE: Agora's display target is Wayland with
 * no X11-native target. Two consequences are visible here rather than discovered later:
 *
 *   * THE HEADER DOES NOT INCLUDE THE SEAM'S HEADER, and the seam is not Xlib's either. The ivars that hold
 *     the connection and the window are `void *`, so a consumer of this header names neither Wayland nor Xlib
 *     and a change of protocol does not reach it.
 *   * THE FRAME IS COCOA's: origin at the BOTTOM-LEFT, y growing up. The seam reports a pointer measured DOWN
 *     from a window's top-left, and the conversion lives in one function in the implementation — so no caller
 *     of this header has to know.
 *
 * AND WHAT A WAYLAND CLIENT DOES NOT GET, because these are properties of the protocol and not gaps: a client
 * does not place or move its own toplevel, there is no unmap and no iconify, and there is no stacking. The
 * doors that used to ask the X server for those (`-setFrameOrigin:`, `-orderOut:`, `-miniaturize:`,
 * `-orderBack:`) change THIS OBJECT's state and not the screen's, each with its reason written at the door.
 *
 * WHAT IS NOT HERE, AND WHY, so the ledger's open rows are a decision rather than an omission: the sheets,
 * the toolbar, the drawer, the frame-autosave strings, the script-command doors, the cursor-rect
 * invalidation and the child-window list each need a subsystem this stage has not reached; the window's
 * BUTTONS are a window manager's business (Kestrel, which will draw them, is parked); and screen and zone
 * placement needs `NSScreen`, which is its own row. Each is absent rather than stubbed.
 */

#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSResponder.h>
#import <AppKit/NSView.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

NS_ASSUME_NONNULL_BEGIN

/* FORWARDED: it appears only as a pointer parameter here. See the note above the class for what this tree can
 * and cannot describe about a screen. */
@class NSCursor;
@class NSGraphicsContext;
@class NSScreen;
@class NSUndoManager;

/* THE STYLE MASK, WHICH AT THIS PIN IS A PLAIN `NSUInteger` AND NOT A NAMED ENUM — the era header declares
 * the cases in an anonymous enum and the parameter as `NSUInteger`, so a caller ORs them and the type is an
 * integer. The five the era declares are here with the era's own bits. */
enum {
	NSBorderlessWindowMask = 0,
	NSTitledWindowMask = 1 << 0,
	NSClosableWindowMask = 1 << 1,
	NSMiniaturizableWindowMask = 1 << 2,
	NSResizableWindowMask = 1 << 3,
	/* **AND THE TEXTURED BIT, WHICH IS THE ONE THE CONTENT BORDER'S RULE TURNS ON.** Apple's 10.6 header gives it
	 * the value `1 << 8` (the live ledger carries it as a `var` flagged `deprecated`, because the modern spelling of
	 * this bit is a later name — the value is Apple's and the NAME is the era's, which is the same trade the other
	 * legacy spellings in this tree make). Nothing here PAINTS a textured background; what it decides is which
	 * content border edge a window may set. */
	NSTexturedBackgroundWindowMask = 1 << 8,
	/* AND TWO MORE APPEARANCE BITS, with Apple's own values. NOTHING HERE HONOURS EITHER: an unscaled window and a
	 * unified title-and-toolbar window are appearances this tier does not paint (it draws a strip and three buttons,
	 * D6), so the bits travel in `-styleMask` and decide nothing — which is said here rather than left for a caller
	 * to discover. The ledger flags both `deprecated` because their live spelling is a later name, the same trade the
	 * textured bit above makes. */
	NSUnscaledWindowMask = 1 << 11,
	NSUnifiedTitleAndToolbarWindowMask = 1 << 12
};

@class NSEvent;
@class NSImage;
@class NSWindowController;
@class NSURL;
@class NSResponder;
@class NSView;

/* ============================================================================================ *
 * THE WINDOW-NUMBER DOORS.                                                                      *
 * ============================================================================================ */

/* Apple's 10.6 header gives these two doors, their option flags, AND the prose that says what each answers — so the
 * prose is quoted rather than paraphrased, because it is also what makes the tier's ONE deviation visible:
 *
 *   `windowNumbersWithOptions:` "returns an autoreleased array of NSNumbers containing windowNumbers for all visible
 *   windows satisfying options. ... If options include NSWindowNumberListAllApplications, visible windows belonging
 *   to all applications are included. If options include NSWindowNumberListAllSpaces, visible windows on all spaces
 *   are included."
 *
 *   `windowNumberAtPoint:belowWindowWithWindowNumber:` "returns the number of the frontmost window that would be hit
 *   by a mouseDown at the screen location point. windowNum can be specified to exclude a given window along with all
 *   windows above it, and may belong to any application. If no windows are to be excluded, specify 0 for windowNum.
 *   The windowNumber returned may correspond to a window in another application."
 */
enum {
	NSWindowNumberListAllApplications = 1 << 0,
	NSWindowNumberListAllSpaces = 1 << 4
};
typedef NSUInteger NSWindowNumberListOptions;


/* **AND THE DEVIATION IS THE CROSS-APPLICATION HALF, WHICH IS STATED RATHER THAN FAKED.** Both doors' prose says
 * their answers may include OTHER applications' windows, and this tier has no cross-application window registry: the
 * only windows it knows are the ones this application made. A compositor HAS a window tree, but its entries are not
 * NSWindows and a frame window's id is not a window number this class ever answers — so widening through it would
 * return numbers that no `+windowNumber`-bearing object corresponds to, which is a lie with a plausible shape rather
 * than a shorter answer. The flags are therefore ACCEPTED, RECORDED IN NO STATE, AND DO NOT WIDEN: both doors answer
 * for THIS application's visible windows, and `NSWindowNumberListAllSpaces` has nothing to widen because there is
 * one space here (the same fact that keeps `NSApplicationPresentation*` a request).
 *
 * AND A MISS ANSWERS 0, WHICH IS ALSO THE "NO EXCLUSION" SENTINEL: Apple's header documents the parameter but no
 * value for "nothing was hit", so the choice is ours and is stated. */
/* Every value below is READ OFF Apple's 10.6 header rather than remembered. `NSSelectionDirection` is the one the
 * header lists with NO values, so its own enumeration order is what its three cases are worth; the rest carry
 * explicit numbers, and `NSWindowSharingType`'s are parsed from the header rather than typed, because its third
 * case carries a trailing comment. */
enum {
	NSDirectSelection = 0,
	NSSelectingNext = 1,
	NSSelectingPrevious = 2
};
typedef NSUInteger NSSelectionDirection;

/* ============================================================================================ *
 * THE WINDOW LEVELS.                                                                            *
 * ============================================================================================ */

/* **AND WHAT THE VALUES ARE IS THE INTERESTING PART: APPLE DOES NOT DEFINE THEM.** Its 10.6 header writes each of
 * these as a macro over `CGWindowLevelForKey` — a CoreGraphics function this tree's CG does not have — and Apple's
 * own engineering discussion of the area says the Cocoa specification DOES NOT PIN THE NUMBERS and that code must
 * rely on the SYMBOLIC NAMES AND THEIR RELATIVE ORDER. Two published sources disagree with each other, even: the
 * older CGWindowLevel.h comments put the dock at 10, the main menu at 20 and the status level at 21, while the
 * modern mapped set has 20, 24 and 25.
 *
 * SO THE VALUES BELOW ARE **OURS, STATED** — the tree's rule for a value Apple publishes none of — and they are the
 * MODERN MAPPED SET rather than the older comments, because that is the one whose ORDER matches what these levels
 * mean. WHAT A CALLER MAY RELY ON IS THE ORDER, and the probe asserts the order rather than the numbers:
 *
 *     normal  <  floating = submenu = torn-off  <  modal panel  <  dock  <  main menu  <  status  <  pop-up menu
 *
 * (`NSSubmenuWindowLevel` and `NSTornOffMenuWindowLevel` are ALIASES of the floating level in Apple's own header —
 * that is why they share its value. `NSDockWindowLevel` is deprecated in the live ledger and is here for a porting
 * caller: the anchor's own `-setLevel:` does not care.) An enum rather than extern constants because Apple's are
 * MACROS: a caller's `switch` over a level needs a compile-time constant, and that is the same trade this file's
 * style masks make. */
enum {
	NSNormalWindowLevel = 0,
	NSFloatingWindowLevel = 3,
	NSSubmenuWindowLevel = 3,
	NSTornOffMenuWindowLevel = 3,
	NSModalPanelWindowLevel = 8,
	NSDockWindowLevel = 20,
	NSMainMenuWindowLevel = 24,
	NSStatusWindowLevel = 25,
	NSPopUpMenuWindowLevel = 101
};

enum {
	NSWindowCollectionBehaviorDefault = 0,
	NSWindowCollectionBehaviorCanJoinAllSpaces = 1 << 0,
	NSWindowCollectionBehaviorMoveToActiveSpace = 1 << 1,
	/* **AND THE FIVE THE 10.6 HEADER GUARDS BEHIND ITS VERSION CHECK, WHICH IS WHY THEY WERE INVISIBLE UNTIL THE ERA
	 * GROUND WAS REPAIRED — every value and every comment below is Apple's own.** The header states TWO CONSTRAINTS
	 * ON COMBINING THEM: at most one of Managed/Transient/Stationary, and at most one of
	 * ParticipatesInCycle/IgnoresCycle, with the default in each group determined by the window's level.
	 *
	 * AND THOSE CONSTRAINTS ARE STATED RATHER THAN ENFORCED, which is the difference between this header and the
	 * presentation options': THERE the prose promises that an invalid combination "raises an exception", and this
	 * one only says "you may specify at most one". So `-setCollectionBehavior:` records what it is given, and the
	 * probe asserts that a combination the constraint would forbid is ACCEPTED — a promise is enforced, a
	 * constraint is documented. */
	NSWindowCollectionBehaviorManaged = 1 << 2,		/* participates in spaces, exposé; the default at NSNormalWindowLevel */
	NSWindowCollectionBehaviorTransient = 1 << 3,		/* floats in spaces, hidden by exposé; the default otherwise */
	NSWindowCollectionBehaviorStationary = 1 << 4,		/* unaffected by exposé; stays visible and stationary */
	NSWindowCollectionBehaviorParticipatesInCycle = 1 << 5,	/* the default at NSNormalWindowLevel */
	NSWindowCollectionBehaviorIgnoresCycle = 1 << 6		/* the default otherwise */
};
typedef NSUInteger NSWindowCollectionBehavior;

enum {
	NSWindowBackingLocationDefault = 0,
	NSWindowBackingLocationVideoMemory = 1,
	NSWindowBackingLocationMainMemory = 2
};
typedef NSUInteger NSWindowBackingLocation;

enum {
	NSWindowSharingNone = 0,
	NSWindowSharingReadOnly = 1,
	NSWindowSharingReadWrite = 2
};
typedef NSUInteger NSWindowSharingType;

@interface NSWindow : NSResponder
{
	/* **THE SHEET'S STATE.** A SHEET IS AN ORDINARY WINDOW THAT ONE OTHER WINDOW HAS ATTACHED, and the attachment
	 * is the only thing that makes it one — so the state is two references and no more. `_cg_sheetParent` is the
	 * window this one is a sheet ON (nil when it is not a sheet) and `_cg_attachedSheet` is the sheet on THIS one.
	 * NOTHING HERE RETAINS THE OTHER WINDOW: the application's window registry already owns every window, and an
	 * attachment that retained would be a cycle between two of them. The reply a sheet's session owes — the
	 * delegate, the selector and the caller's context — lives with the ATTACHMENT, on the parent, because a sheet's
	 * session belongs to the parent window and a second sheet on it is refused rather than queued.
	 *
	 * The doors that BEGIN and END a session are `NSApplication`'s (Apple's too); they reach this state through the
	 * seam declared in NSApplication.m, which is this tree's pattern for a private contract crossing a file. */
	NSWindow *_cg_sheetParent;
	NSWindow *_cg_attachedSheet;
	id _cg_sheetReplyDelegate;
	SEL _cg_sheetReplySelector;
	void *_cg_sheetContextInfo;
	/* **THE FOUR SIZE CONSTRAINTS, AND WHY THE FRAME PAIR AND THE CONTENT PAIR ARE FOUR VALUES AND NOT TWO.** A
	 * frame constraint and a content constraint are DIFFERENT QUESTIONS — one is about the whole decorated window,
	 * the other about the part inside its chrome — and Apple keeps them separate, so setting one does NOT move the
	 * other's answer. Both are enforced, and the chrome is what relates them (this file already converts between
	 * the two rects, which is what makes the content pair cost nothing here). */
	NSSize _minSize;
	NSSize _maxSize;
	NSSize _contentMinSize;
	NSSize _contentMaxSize;
	/* **THE KEY-VIEW FAMILY'S STATE.** `_initialFirstResponder` is NOT RETAINED, as Apple declares it (a weak
	 * reference): it names a view the window's own content tree owns, and a window that retained it would keep a
	 * view alive after its superview had gone. `_keyViewSelectionDirection` is the CURRENT traversal direction —
	 * direct, next or previous — and `_cg_placedOnscreen` is what makes the initial first responder a ONE-TIME
	 * act, because the door promises the FIRST time the window is placed onscreen and nothing after that. */
	NSView *_initialFirstResponder;
	NSSelectionDirection _keyViewSelectionDirection;
	BOOL _cg_placedOnscreen;
	/* **THE THREE VISIBILITY FLAGS, AND ONE OF THEM IS STORED AS ITS DEVIATION.** `_cg_refusesHide` is the INVERSE
	 * of Apple's `canHide`, because Apple's default for that door is YES and an ivar's default is NO — so storing
	 * the deviation means the default is right without an initializer to remember. The other two default to NO,
	 * which is what an ivar gives for free and what Apple documents. */
	BOOL _hidesOnDeactivate;
	BOOL _cg_refusesHide;
	BOOL _ignoresMouseEvents;
	/* **THE CONTENT BORDER, ONE VALUE PER EDGE** — indexed by `NSRectEdge`, which this tree's geometry declares as
	 * NSRectEdgeMinX/MinY/MaxX/MaxY in that order. Apple's automatic thickness is computed from the toolbar and
	 * title-bar area; this window draws its own chrome with a constant strip and has no toolbar, so there is nothing
	 * for the automatic value to come from and it is 0 (stated where the doors are). */
	CGFloat _contentBorderThickness[4];
	BOOL _autorecalculatesContentBorder[4];
	/* **WHAT THE USER MAY DO WITH THE WINDOW, AND TWO FLAGS STORED AS THEIR DEVIATIONS.** `-isMovable`'s default is
	 * YES and `-isMovableByWindowBackground`'s is NO — EXCEPT on a textured window, where it is YES — so both are
	 * stored as the deviation from a default an ivar cannot give: `_cg_refusesMove` for the first, and an explicit
	 * "asked" flag for the second, because a ternary default needs to know whether it was ever set. (An `int`
	 * sentinel of -1 looks like it would do that and does not: AN IVAR'S DEFAULT IS ZERO.) */
	BOOL _cg_refusesMove;
	BOOL _cg_movableByBackground;
	BOOL _cg_movableByBackgroundSet;
	/* **THE WINDOW'S OWNER AND WHAT IT REPRESENTS.** `_cg_windowController` is NOT RETAINED — the controller retains
	 * the window, so the back-reference must not retain it back (a cycle between two objects, either of which a
	 * caller may release first). The other three ARE retained, and `-dealloc` releases them. */
	id _cg_windowController;
	NSURL *_representedURL;
	NSString *_miniwindowTitle;
	NSImage *_miniwindowImage;
	/* THE FLAG `-useOptimizedDrawing:` KEEPS, and the set the drag pair keeps: see the doors. */
	BOOL _cg_useOptimizedDrawing;
	/* THE FRAME'S CONSTRAINTS: two pairs, mutually exclusive within each — see the doors. */
	NSSize _resizeIncrements;
	NSSize _aspectRatio;
	NSSize _contentResizeIncrements;
	NSSize _contentAspectRatio;
	/* AND THE APPEARANCE FLAGS, RECORDED FOR THE WINDOW MANAGER RATHER THAN APPLIED HERE. */
	CGFloat _alphaValue;
	BOOL _opaque;
	BOOL _hasShadow;
	BOOL _showsResizeIndicator;
	BOOL _allowsConcurrentViewDrawing;
	BOOL _allowsToolTipsWhenApplicationIsInactive;
	BOOL _autodisplay;
	BOOL _excludedFromWindowsMenu;
	BOOL _oneShot;
	BOOL _releasedWhenClosed;
	BOOL _floatingPanel;
	BOOL _modalPanel;
	BOOL _worksWhenModal;
	BOOL _preventsApplicationTerminationWhenModal;
	BOOL _canBecomeVisibleWithoutLogin;
	BOOL _displaysWhenScreenProfileChanges;
	BOOL _preservesContentDuringLiveResize;
	NSBackingStoreType _backing;
	BOOL _showsToolbarButton;
	NSMutableArray *_cg_registeredDraggedTypes;
	BOOL _cg_registeredDraggedTypesSet;
	/* THE PLACE IN THE STACK THIS WINDOW ASKED FOR — `NSNormalWindowLevel` until a caller says otherwise. */
	NSInteger _level;
	/* **THE CHILD WINDOWS, AND THE ONE BACK-REFERENCE A CHILD KEEPS.** A window's children are its own business
	 * and they are RETAINED here (the list is the only thing holding a child that a caller has let go of); the
	 * parent reference is NOT retained, because a retained pair would be a cycle and a cycle here is not a leak but
	 * a HANG — every move propagates through this same pair. Apple's own documentation names the cycle as a thing
	 * not to build, and this file refuses to build one rather than relying on a caller's care. */
	NSMutableArray *_cg_childWindows;
	NSWindow *_cg_parentWindow;
	/* AND THE TWO REQUESTS THIS FILE RECORDS RATHER THAN ACTS ON: the collection behaviour (spaces, which is a
	 * window manager's business) and the sharing type (which the header says nothing can grant). See the doors. */
	NSUInteger _cg_collectionBehavior;
	NSUInteger _cg_sharingType;
	/* THE SEAM'S STATE, DELIBERATELY UNTYPED — see the header note: the window server's types belong to the
	 * files that include its header, and this header must not drag them in. */
	void *_agwindow;        /* the AGWindow this window draws into, or NULL before `defer:` is resolved */
	NSMutableArray *_cg_events; /* queued NSEvents, converted from the seam's events (private) */
	NSPoint _cg_pointer;    /* where the seam last saw the pointer, in COCOA coordinates */
	BOOL _cg_hasPointer;
	BOOL _cg_mouseButtonDown; /* a button is held, so a move is a DRAG rather than a move */
	/* **AND WHERE THE POINTER IS, FOR THE TRACKING ENGINE.** The engine's walk asks whether the point CHANGED, so that
	 * a re-evaluation which is not a motion — an area installed under a resting pointer, a window resigning key — does
	 * not fire `-mouseMoved:` at an owner who never moved. `_cg_hasTrackingPoint` is NO until the first report, which
	 * makes the first walk a movement by definition. */
	NSPoint _cg_trackingPoint;
	BOOL _cg_hasTrackingPoint;
	NSInteger _cg_windowNumber; /* Apple's window number, assigned when the AGWindow is made; -1 before */
	BOOL _cg_closeRequested; /* the compositor asked the window to close; acted on in the pump */
	NSRect _frame;          /* COCOA's coordinates: bottom-left origin */
	/* THE PLACE THE WINDOW HAD BEFORE IT ZOOMED, and whether it is zoomed — the pair is the whole state of
	 * `-zoom:`, because Apple's zoom ALTERNATES between the user's frame and the standard one. */
	NSRect _preZoomFrame;
	BOOL _hasPreZoomFrame;
	BOOL _zoomed;
	/* THE NAME IT REMEMBERS ITSELF UNDER, retained; nil until a caller gives one. */
	NSString *_frameAutosaveName;
	/* WHETHER A FLUSH PUSHES ANYTHING, and how many times it has. Apple's pair of doors is gated by the flag,
	 * and X flushes the whole display at once — so the flag is the only thing here with a meaning, and the
	 * count is the seam the probe reads (private: `-cg_flushCount`). */
	BOOL _flushing;
	NSInteger _flushCount;
	NSInteger _flushPushCount;
	/* THE FILE THE WINDOW STANDS FOR, retained; nil until a caller says. */
	NSString *_representedFilename;
	/* THE KEY-VIEW LOOP, IN THE ORDER IT IS WALKED, retained. It is kept rather than recomputed so that a
	 * caller's `-setNextKeyView:` LINKS survive: the loop is the default order and the chain is the truth. */
	NSMutableArray *_keyViewLoop;
	/* WHETHER THE WINDOW IS MINIATURIZED, which is a state this object keeps rather than asks the server for:
	 * with no window manager the iconify request is a no-op, and a window that could not say whether it had been
	 * asked to miniaturize would be unusable on a bare server. */
	BOOL _miniaturized;
	/* THE CURSOR RECTS' STATE: whether they are honoured at all, and whether the tree's rects need rebuilding
	 * before the next resolution. `-disableCursorRects` is for a caller that is rearranging views — rebuilding
	 * the rects under a live pointer would flash the wrong cursor at the user. */
	/* THE DEPTH LIMIT: zero means the default (Apple's own reading of the value), and the dynamic flag says
	 * whether the window may change its depth when it changes screens. */
	NSWindowDepth _depthLimit;
	BOOL _dynamicDepthLimit;
	/* WHETHER THE WINDOW'S DOCUMENT HAS UNSAVED CHANGES, which is a window's own state and not its controller's:
	 * the controller is where Apple puts the DOOR, and the window is where the ledger keeps the ROW. */
	BOOL _documentEdited;	BOOL _cursorRectsEnabled;
	BOOL _cursorRectsDirty;
	NSUInteger _styleMask;
	NSString *_title;
	id _delegate;           /* NOT retained, which is Apple's contract for a delegate */
	BOOL _deferred;
	BOOL _visible;
	BOOL _key;
	BOOL _main;
	/* THE CONTENT VIEW AND THE FIRST RESPONDER. The view is RETAINED (a window owns its content), the
	 * responder is NOT (it is a view inside the content, and a window that retained it would keep a whole
	 * subtree alive through one pointer). */
	NSView *_contentView;
	/* **THE WINDOW'S OWN BACKGROUND COLOUR, WHICH IS A DOOR APPLE HAS AND THIS TIER DID NOT.** The frame's fill has
	 * always been `+[NSColor windowBackgroundColor]`; a window that is part of a surface it does not own — an
	 * application's menus, sitting in the menu bar — has to BE that surface's colour instead, and the only way to
	 * say so is to let the window be told. Nil means the default, so every window that says nothing is unchanged. */
	id _backgroundColor;
	NSResponder *_firstResponder;
	/* WHETHER MOVEMENT WITHOUT A BUTTON IS DELIVERED. Apple's default is NO — a window that wants moves has
	 * to ask — and it is what makes the pump's MotionNotify branch conditional rather than unconditional. */
	BOOL _acceptsMouseMoved;
	/* THE CLICK COUNT IS DERIVED HERE, because X has none: a press within the double-click interval and
	 * close to the last one counts as the next in a series. */
	NSInteger _clickCount;
	NSPoint _lastClick;
	NSTimeInterval _lastClickTime;
	/* THE BACKING STORE. The window's content is drawn into this and then COPIED into the frame the window
	 * server hands over — one copy per frame, which is the price of a client-side backing store on a protocol
	 * whose buffers come and go. */
	void *_surface;         /* the CGContextRef the content draws into, or NULL */
	unsigned char *_pixels; /* the buffer behind it, which is also what is copied */
	int _surfaceWidth;      /* the size the two above were made for, so a resize can remake them */
	int _surfaceHeight;
	BOOL _viewsNeedDisplay;
}

/* THE GEOMETRY PAIR, IN BOTH SPELLINGS: the class forms take the style mask, the instance forms use the
 * receiver's, and the chrome they add is the title bar's — see the implementation for whose number it is. */
+ (NSRect)frameRectForContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask;
+ (NSRect)contentRectForFrameRect:(NSRect)frameRect styleMask:(NSUInteger)styleMask;
- (NSRect)frameRectForContentRect:(NSRect)contentRect;
- (NSRect)contentRectForFrameRect:(NSRect)frameRect;

/* THE DESIGNATED INITIALISER TAKES the CONTENT rect, the style, the backing and `defer:` — and `defer:` is
 * HONOURED: the X window is made on demand, so a window that is never ordered front never becomes one. The
 * `screen:` form Apple also declares needs `NSScreen`, which is its own row. */
- (instancetype)initWithContentRect:(NSRect)contentRect
			  styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType
			      defer:(BOOL)flag;

- (NSRect)frame;
- (void)setFrame:(NSRect)frameRect display:(BOOL)flag;

/* ============================================================================================ *
 * THE SIZE CONSTRAINTS.                                                                         *
 * ============================================================================================ */

/* `-minSize`/`-maxSize` CONSTRAIN THE FRAME; `-contentMinSize`/`-contentMaxSize` CONSTRAIN THE CONTENT, and both
 * pairs are enforced — a window must satisfy the four of them at once. They are four values rather than two because
 * that is what Apple's own door pair says: setting a content minimum does not change what `-minSize` answers.
 *
 * **WHY A ZERO IS THE ABSENCE OF A CONSTRAINT, AND WHY THAT IS A DERIVATION RATHER THAN A GUESS.** Apple's header
 * carries no prose for these four, and it declares no defaults — but a window is BORN with all four at (0,0), and
 * under any other reading of a zero maximum every window this tree has ever made would have been locked at no size
 * at all. So a zero in either bound is read as "this bound is not set", PER AXIS: a caller may constrain the width
 * and leave the height alone, which is the shape a (0,0) initial value forces on any honest implementation.
 *
 * AND THE CONSTRAINT IS APPLIED IN `-setFrame:display:` — the ONE place every frame set in this file passes
 * through (`-setFrameOrigin:`, `-setContentSize:`, `-zoom:`, `-setFrameUsingName:` and this class's own placement
 * arithmetic all end up there), which is why a clamped set announces the frame that actually resulted rather than
 * the one that was asked for. A MAXIMUM THAT IS TIGHTER THAN THE MINIMUM LANDS ON THE MAXIMUM: it is applied last,
 * and a window that cannot be as large as its minimum is a caller error this tier must still resolve to some size.
 *
 * WHAT IS NOT HERE IS `-liveResize`'s BEHAVIOUR: `-preservesContentDuringLiveResize` and `-inLiveResize` describe
 * a DRAG, and there is no drag in this tier — the window manager that would run one is the guest's. */
- (NSSize)minSize;
- (void)setMinSize:(NSSize)size;
- (NSSize)maxSize;
- (void)setMaxSize:(NSSize)size;
- (NSSize)contentMinSize;
- (void)setContentMinSize:(NSSize)size;
- (NSSize)contentMaxSize;
- (void)setContentMaxSize:(NSSize)size;
/* **THE WINDOW NEEDS DRAWING AGAIN — APPLE'S DOOR, AND THE ONE THIS TIER DID NOT HAVE.** Without it a caller had
 * no way to say "this is stale": `-display` PAINTS NOW and gives up if the compositor still owns the buffer, so a
 * paint can be lost with nothing to retry it. `-setNeedsDisplay:` only SETS A FLAG, and the run loop calls
 * `-displayIfNeeded` on every window each pass — so the paint happens when the buffer is free, however many passes
 * that takes. That is the difference between a menu that appears and one that waits for the mouse to move. */
- (void)setNeedsDisplay:(BOOL)flag;

- (void)setFrameOrigin:(NSPoint)aPoint;
- (void)setContentSize:(NSSize)aSize;
- (NSUInteger)styleMask;

- (nullable NSString *)title;
- (void)setTitle:(nullable NSString *)aString;

/* THE DELEGATE IS NOT RETAINED — see the ivar note. */
- (nullable id)delegate;
- (void)setDelegate:(nullable id)anObject;

/* THE WINDOW'S NUMBER IS ITS X WINDOW ID, and -1 BEFORE THERE IS ONE, which is Apple's own answer for a
 * window with no number. */
- (NSInteger)windowNumber;

- (BOOL)isVisible;
- (BOOL)isKeyWindow;
- (BOOL)isMainWindow;


/* ============================================================================================ *
 * THE CONTENT VIEW AND THE EVENT PUMP (stage C, second slice).                                   *
 *                                                                                                *
 * A WINDOW THAT CANNOT HOLD A VIEW AND CANNOT DELIVER AN EVENT IS NOT A WINDOW — it is a        *
 * rectangle. These doors are what make it the thing stage A's responder chain was built for:     *
 * the content view is the ROOT of the view tree, and the pump is what turns X's events into      *
 * `NSEvent`s and hands them to the chain.                                                        *
 *                                                                                                *
 * `-fieldEditor:forObject:` IS NOT HERE and its row stays open: a field editor IS an `NSText`    *
 * (in practice an `NSTextView`), and the text system is stage F. Writing a forward `@class         *
 * NSText;` to satisfy the signature would flip the ledger's `class NSText` row to shipped and      *
 * claim a class this tree does not have — the ground NSImage's `-initWithIconRef:` and NSColor's   *
 * two colour-space doors already stand on.                                                        *
 * ============================================================================================ */

/* THE CONTENT VIEW, WHICH IS THE VIEW TREE'S ROOT. Setting one RETAINS it and lays it out in the
 * window's CONTENT rect, which is the frame minus the chrome — so a titled window's content view is
 * where a caller draws and never where the title bar is. */
- (nullable NSView *)contentView;
- (void)setContentView:(nullable NSView *)aView;
- (nullable NSResponder *)firstResponder;

/* THE RESPONDER THAT GETS THE KEY EVENTS FIRST. It is set to the content view when one is installed, so a
 * window with a content view always has somewhere for a key to go. */
- (BOOL)makeFirstResponder:(nullable NSResponder *)aResponder;

/* THE PUMP. `-nextEventMatchingMask:` takes the first event the server has for this window whose type is in
 * the mask, waiting for one; the `untilDate:inMode:dequeue:` form waits no longer than the date, which is
 * what makes it usable inside a run loop (and the `mode` is taken and unused — this tree has one mode). A
 * mask of `NSEventMaskAny` matches everything.  */
- (nullable NSEvent *)nextEventMatchingMask:(NSUInteger)mask;
- (nullable NSEvent *)nextEventMatchingMask:(NSUInteger)mask
				  untilDate:(nullable NSDate *)expiration
				     inMode:(nullable NSString *)mode
				    dequeue:(BOOL)deqFlag;

/* AND THE DISPATCH, which is the responder chain: the event goes to the FIRST RESPONDER if it handles that
 * kind, and to the CONTENT VIEW otherwise — Apple's own routing, and the reason a window with a content
 * view and no first responder still delivers a click. */
- (void)sendEvent:(NSEvent *)theEvent;

/* WHETHER A MOVE WITH NO BUTTON HELD IS DELIVERED. Default NO, and it is Apple's default: a window that
 * wants `mouseMoved:` has to ask, which is what keeps the pump from generating an event for every pixel of
 * pointer travel. */
- (void)setAcceptsMouseMovedEvents:(BOOL)flag;
- (BOOL)acceptsMouseMovedEvents;

/* WHERE THE POINTER IS, without an event — READ FROM THE SERVER IN ROOT COORDINATES and then converted through
 * THIS WINDOW'S FRAME. It is deliberately NOT the pump's arithmetic: an event arrives from the server already
 * window-relative, so the pump only flips it, while this door has to subtract the frame's origin as well.
 *
 * AND THE DEVIATION IT LEAVES IS STATED RATHER THAN HIDDEN: `-frame` is a REQUEST. A reparenting window manager
 * places the window where it likes, so a pointer can be over the window a person can see while this answers a
 * point outside the requested frame — and reading the server's own geometry is how to know the difference.
 *
 * THAT DEVIATION IS EXPECTED TO END, NOT TO BE DESIGNED AROUND: the guest's window manager is to be one that
 * HONOURS Cocoa's frame API (appkit-plan §6 D5), so the request becomes the placement and this answers
 * relative to the window a person can see. Until then the probe's expectation is what pins the behaviour. */- (NSPoint)mouseLocationOutsideOfEventStream;


/* ============================================================================================ *
 * THE DRAWING SURFACE **IS THE WHOLE FRAME**, TITLE BAR INCLUDED — client-side decoration          *
 * (appkit-plan §6 D6): the window owns every pixel it was given, its own chrome too, and `-display`*
 * blits the frame at (0,0) once the content and then the strip above it are drawn. That is why an  *
 * Expose is a REPAINT rather than a question — nothing on the server to ask, nothing to lose.      *
 *                                                                                                *
 * `-invalidateShadow`, THE CACHED-IMAGE TRIO AND `-disableScreenUpdatesUntilFlush` REFUSE BY NAME: *
 * a shadow is a window manager's (Kestrel is parked), the cached image is exactly what the      *
 * backing store already is — caching a screen rect to redraw it later is what this window does *
 * on EVERY display — and there is no deferred draw queue to suspend, because the blit happens  *
 * with the frame. Each says so rather than doing nothing quietly.                               *
 * ============================================================================================ */

/* DRAW THE CONTENT VIEW INTO THE BACKING STORE AND PUT IT ON THE WINDOW. This is the door that makes a view's
 * drawing visible at all, and it is also what the PUMP calls when the server says the window was exposed. */
- (void)display;
- (void)displayIfNeeded;
- (void)update;

/* AND THE ONE PIECE OF STATE THAT DECIDES WHETHER `-displayIfNeeded` DOES ANYTHING. */
@property BOOL viewsNeedDisplay;

/* SHOWING AND HIDING BY FLAG, which is Apple's spelling of the same pair `-orderFront:`/`-orderOut:` are. */
- (void)setIsVisible:(BOOL)flag;

/* WHETHER THE WINDOW'S DEVICE CAN STORE COLOUR. This tree's windows are 24-bit on every display it runs on,
 * so the honest answer is YES rather than a query it cannot make. */
- (BOOL)canStoreColor;
- (nullable NSScreen *)screen;
- (nullable NSScreen *)deepestScreen;

/* ============================================================================================ *
 * THE KEY VIEW LOOP'S THREE REMAINING DOORS.                                                    *
 * ============================================================================================ */

/* Apple groups the loop's doors under "Managing the Key View Loop", and this tier already implements most of them
 * (`-selectNextKeyView:`, `-selectPreviousKeyView:`, `-selectKeyViewFollowingView:`,
 * `-selectKeyViewPrecedingView:` and `-recalculateKeyViewLoop`). What follows is what was owed, each against
 * Apple's own documented wording:
 *
 *   `initialFirstResponder` — "the view that's made first responder (also called the key view) THE FIRST TIME THE
 *   WINDOW IS PLACED ONSCREEN". So this tier makes it the first responder when the window is first ordered front,
 *   and ONLY then: a later order-front must not undo whatever the user or the caller has since focused. */
- (nullable NSView *)initialFirstResponder;
- (void)setInitialFirstResponder:(nullable NSView *)view;

/*   `keyViewSelectionDirection` — "the direction the window is CURRENTLY using to change the key view": the three
 *   values are this tree's `NSSelectionDirection`, and `NSDirectSelection` means the window is NOT traversing the
 *   loop — which is what a direct `-makeFirstResponder:` sets it back to. The four traversal doors set it to the
 *   direction they moved in, so a caller inside `-becomeFirstResponder` is told which way focus arrived. */
- (NSSelectionDirection)keyViewSelectionDirection;

/*   `autorecalculatesKeyViewLoop` — "whether the window AUTOMATICALLY RECALCULATES the key view loop when views are
 *   added". **IN THIS TIER THE ANSWER IS NO, AND THAT IS A FACT RATHER THAN A PREFERENCE**: the loop is built when
 *   it is first asked for and marked for a rebuild only by `-recalculateKeyViewLoop` — Apple's own lazy model —
 *   and nothing here rebuilds it because a view was ADDED. So the getter reports what is true, the setter accepts
 *   `NO` (which changes nothing), and asking for `YES` is REFUSED BY NAME: it would promise a recalculation this
 *   tier has no path to trigger, which is the shape of half-implementation this tree treats as worse than an open
 *   row. (`-recalculateKeyViewLoop` is the door a caller uses after editing the tree, and it works.) */
- (BOOL)autorecalculatesKeyViewLoop;
- (void)setAutorecalculatesKeyViewLoop:(BOOL)flag;

/* ============================================================================================ *
 * THE THREE VISIBILITY FLAGS.                                                                   *
 * ============================================================================================ */

/* `canHide` IS THE ONE APPLE'S OWN HEADER COMMENTS, verbatim: "indicate whether a window can be hidden during
 * -[NSApplication hide:]. Default is YES" — so the comment names BOTH the default and the hook that consults it,
 * and this tier does exactly that: `-hide:` skips a window that refuses. */
- (BOOL)canHide;
- (void)setCanHide:(BOOL)flag;

/* `hidesOnDeactivate` — "whether the window is removed from the screen when its application becomes inactive" —
 * default NO for a window. TWO THINGS ARE STATED RATHER THAN COPIED: Apple's default for an NSPanel is YES, and
 * there is no NSPanel in this tree (the class is an open ledger row), so that difference is not implemented; and
 * what this tier does is hide the windows that ARE VISIBLE when the application deactivates and bring them back
 * when it activates, so a window the caller had already ordered out is NOT brought back by us. */
- (BOOL)hidesOnDeactivate;
- (void)setHidesOnDeactivate:(BOOL)flag;

/* `ignoresMouseEvents` — "whether the window is transparent to mouse events" — default NO. The two behaviours it
 * has here are the documented ones: a mouse event aimed at such a window is passed DOWN to the window below it (or
 * dropped when there is none), and `+windowNumberAtPoint:belowWindowWithWindowNumber:` does NOT return one — which
 * is Apple's own sentence about that door ("windows that ignore mouse events will not be returned").
 *
 * WHAT IS NOT IMPLEMENTED IS THE THIRD, UNDOCUMENTED STATE: an untouched window on macOS passes clicks through its
 * TRANSPARENT regions while capturing them in opaque ones, and this tier has no per-pixel-transparent window to do
 * that with (an X window without a compositor is opaque). So the flag here is a plain two-state one — which is also
 * a deviation from the quirk that setting it once on macOS can never be undone: this tier's can be set back. */
- (BOOL)ignoresMouseEvents;
- (void)setIgnoresMouseEvents:(BOOL)flag;

/* ============================================================================================ *
 * THE CONTENT BORDER.                                                                           *
 * ============================================================================================ */

/* Apple's 10.6 header declares these four doors with NO prose, so the contract is its DOCUMENTATION, and two of its
 * rules are the interesting ones:
 *
 *   * THE EDGE A WINDOW MAY SET DEPENDS ON ITS STYLE: "In a non-textured window, passing NSMaxYEdge will raise an
 *     exception ... it's only valid to set the content border thickness of the bottom edge." So a top edge on a
 *     window without `NSTexturedBackgroundWindowMask` is REFUSED BY NAME here, and a textured window accepts it.
 *     (The mirror — a textured window's BOTTOM edge — is stated only in passing in the source this was read from,
 *     so it is ACCEPTED and stored rather than refused: a rule this tier cannot attest is not one it enforces.)
 *   * "TURNING OFF A BORDER'S AUTO-RECALCULATION SETS ITS BORDER THICKNESS TO 0.0" — a documented side effect, and
 *     the reason those two doors belong in one unit rather than two.
 *
 * AND WHAT THE THICKNESS DOES NOT DO IS STATED: the content border is a DRAWN region ("it only changes how the
 * background is drawn", and it is not part of the content view and does not resize it). This tier stores the
 * request and paints nothing for it — the appearance of that gradient is a visual decision this tree has not made,
 * and inventing one would be a wrong value in the one place a caller can see it. */
- (void)setContentBorderThickness:(CGFloat)thickness forEdge:(NSRectEdge)edge;
- (CGFloat)contentBorderThicknessForEdge:(NSRectEdge)edge;
- (void)setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
- (BOOL)autorecalculatesContentBorderThicknessForEdge:(NSRectEdge)edge;

/* ============================================================================================ *
 * WHAT THE USER MAY DO WITH THE WINDOW.                                                         *
 * ============================================================================================ */

/* APPLE'S ARCHIVED WINDOW-SCRIPTING REFERENCE DEFINES THE THREE ABILITIES IN TERMS OF THE BUTTONS, and its wording
 * is quoted because the modern pages are terser: `-isResizable` "returns YES if the receiver is resizable (has a
 * size control)", `-isMiniaturizable` "if the receiver can be miniaturized (has a minimize button)", `-isZoomable`
 * "if the receiver is zoomable (has a zoom button)". Each is a question about the STYLE MASK, and the ZOOM BUTTON IS
 * THE RESIZABLE BIT: a zoomable window is a resizable one — that is where the green button comes from, and it is
 * what the platform code that sets a window's zoom button consults.
 *
 * WHAT THAT DOES NOT MEAN IS STATED: this reports the ABILITY. `-zoom:` does not consult it yet, so asking a
 * non-zoomable window to zoom still zooms here — a caller that cares asks this door first. */
- (BOOL)resizable;
- (BOOL)miniaturizable;
- (BOOL)zoomable;

/* AND THE TWO DRAGGING FLAGS, whose ground is Apple's own header prose — WHICH NAMES THE SERVER, and is therefore
 * exactly the relationship this tier has with its window manager (D5):
 *
 *   "Calling -setMovable with a flag of NO will disable SERVER-SIDE DRAGGING of the window via titlebar or
 *    background.  -setMovableByWindowBackground:YES is ignored on a window that returns NO from -isMovable. ...
 *    Note that a resizable window may still be resized, and the window frame may be changed programmatically."
 *
 * So `-isMovable` defaults to YES and is RECORDED for the server to honour; `-isMovableByWindowBackground` defaults
 * to NO — EXCEPT ON A TEXTURED WINDOW, where Apple's documentation gives it YES — and asking for YES is IGNORED on
 * a window that answers NO to `-isMovable`, and on a SHEET, which Apple's documentation says "cannot be movable by
 * window background". */
- (BOOL)isMovable;
- (void)setMovable:(BOOL)flag;
- (BOOL)isMovableByWindowBackground;
- (void)setMovableByWindowBackground:(BOOL)flag;

/* ============================================================================================ *
 * THE WINDOW'S OWNER, WHAT IT REPRESENTS, AND HOW IT SHRINKS.                                   *
 * ============================================================================================ */

/* `-windowController` IS `id` IN APPLE'S OWN 10.6 HEADER — not `NSWindowController *`, even though the setter's
 * parameter IS typed — and the link it names is maintained by the CONTROLLER: `NSWindowController`'s `-setWindow:`
 * is what tells the window who its controller is, because the controller is the object that drives. This window
 * therefore RECORDS what it is told and does not call back, which is what keeps the two doors from recursing. */
- (nullable id)windowController;
- (void)setWindowController:(nullable NSWindowController *)windowController;

/* `-representedURL` — "the URL the window represents" — with Apple's own prose about what the window DOES with it
 * quoted for the reason it is only stored here:
 *
 *   "If a window has a representedURL, the window will by default show a path popup menu for a command-click on a
 *    rectangle containing the window document icon button and the window title."
 *
 * THERE IS NO DOCUMENT ICON BUTTON AND NO PATH POPUP IN THIS TIER — the chrome is a strip, three buttons and the
 * edited dot (D6) — so the URL round-trips and nothing is drawn from it. And it is INDEPENDENT of the older
 * `-representedFilename` this class already carries: Apple's header documents the two as separate doors and does not
 * derive one from the other, so neither does this. */
- (nullable NSURL *)representedURL;
- (void)setRepresentedURL:(nullable NSURL *)url;

/* `-miniwindowTitle` and `-miniwindowImage` are "what the miniaturized window shows". This tier MINIATURIZES (it
 * marks the state and announces it) but has nothing to draw a miniaturized window WITH — that view belongs to the
 * dock the guest's window manager owns — so both round-trip and are read by nobody here. */
- (nullable NSString *)miniwindowTitle;
- (void)setMiniwindowTitle:(nullable NSString *)title;
- (nullable NSImage *)miniwindowImage;
- (void)setMiniwindowImage:(nullable NSImage *)image;

/* **THE TWO CHROME FACTS, WHOSE GROUND IS APPLE'S ARCHIVED WINDOW-SCRIPTING REFERENCE** — they are the KVC-compliant
 * accessors for Cocoa's Standard Suite attributes, and its wording is "Returns YES if the receiver has a close box"
 * and "Returns YES if the receiver has a title bar". Each is therefore a question about the STYLE MASK, and the
 * mask is also what DECIDES WHAT THIS WINDOW DRAWS: the strip is drawn for a titled window and the close,
 * miniaturize and zoom buttons for the closable, miniaturizable and resizable bits — which is the same relation
 * Apple's scripting reference states for the buttons ("has a minimize button", "has a zoom button"). */
- (BOOL)hasTitleBar;
- (BOOL)hasCloseBox;

/* ============================================================================================ *
 * THE DOORS THIS TIER CANNOT MEET, EACH WITH ITS REASON.                                        *
 * ============================================================================================ */

/* THE SHAPE IS THE ONE `NSBitmapImageRep` ESTABLISHED FOR ITS ENCODER: the door exists, is DECLARED in Apple's
 * own signature, and answers by NAMING what it needs rather than approximating the work. A stub that answered a
 * plausible value would be worse than this — the caller would go on with something this tier cannot do — and a
 * door that is simply absent is worse still, because a ported program gets a link error instead of the reason.

 * THE COMMON GROUND, SAID ONCE: this tier has the display (an X client window), the drawing substrate
 * (CoreGraphics) and the event path. What it has not got is printing, PDF/EPS production, the scripting suite,
 * Carbon, toolbars, text views, cells, or a drag session — and each door below names the one it needs. */
- (nullable NSData *)dataWithEPSInsideRect:(NSRect)rect;	/* needs a PDF/EPS producer: this tree's CG has none */
- (nullable NSData *)dataWithPDFInsideRect:(NSRect)rect;	/* the same substrate, and the PDF half is parked */
- (void)print:(nullable id)sender;			/* needs the printing system (NSPrintOperation) */
- (void)dragImage:(nullable NSImage *)anImage		/* needs a drag SESSION: the window server's drag loop */
		   at:(NSPoint)baseLocation
	       offset:(NSSize)initialOffset
		event:(nullable NSEvent *)event
	   pasteboard:(nullable NSPasteboard *)pboard
	       source:(nullable id)sourceObj
	    slideBack:(BOOL)slideFlag;
- (void)disableKeyEquivalentForDefaultButtonCell;	/* needs the default button CELL: no NSCell in this tier */
- (void)enableKeyEquivalentForDefaultButtonCell;
- (void)toggleToolbarShown:(nullable id)sender;		/* needs NSToolbar */
- (void)runToolbarCustomizationPalette:(nullable id)sender;
+ (void)menuChanged:(nullable id)menu;			/* needs the application's menu system (NSMenu) */
- (nullable NSWindow *)initWithWindowRef:(nullable void *)windowRef;	/* needs CARBON, which this tree is not —
							 * and the ARGUMENT IS ANNOTATED NULLABLE BECAUSE THE IMPLEMENTATION ACCEPTS NULL: it
							 * refuses by name without looking at the ref, which is what the probe's nil case checks */
- (nullable id)handleCloseScriptCommand:(nullable id)command;	/* needs the SCRIPTING suite: no NSScriptCommand */
- (nullable id)handleSaveScriptCommand:(nullable id)command;
- (nullable id)handlePrintScriptCommand:(nullable id)command;
- (nullable id)fieldEditor:(BOOL)createFlag forObject:(nullable id)anObject;	/* needs the TEXT SYSTEM: no NSText */

/* **AND THE FOUR THAT ARE NOT REFUSALS, WHICH IS WHY THEY ARE SEPARATED FROM THE LIST ABOVE.**

 * `-gState` ANSWERS 0 AND THAT IS A VALUE RATHER THAN A MISSING ONE: Apple's door returns the graphics-state ID
 * of the window's content view, and this tier draws through a `CGContext` rather than a state stack, so there is
 * no ID to return. A caller comparing two windows' gStates gets 0 == 0, which is the truth here.

 * `-endEditingFor:` IS A NO-OP BECAUSE THE CONTRACT IS ALREADY MET: it ends editing in that view's field editor,
 * and this tier has no field editor to end anything in. Nothing is approximated — there is nothing to do.

 * `-useOptimizedDrawing:` IS RECORDED, with the effect named: it let a window promise that its views do not
 * overlap, and this tier's drawing does not consult such a promise, so the flag is kept for a caller that reads
 * it back through nothing — there is no getter in Apple's surface either, and the store is stated rather than
 * made to look effective.

 * `-registerForDraggedTypes:` AND `-unregisterDraggedTypes` ARE RECORDED THE SAME WAY: the set is kept, and what
 * would consume it is the content view's drag acceptance, in a tier with no drag session. */
- (NSInteger)gState;
- (void)endEditingFor:(nullable id)anObject;
- (void)useOptimizedDrawing:(BOOL)flag;
- (void)registerForDraggedTypes:(nullable NSArray *)newTypes;
- (void)unregisterDraggedTypes;
- (BOOL)cg_useOptimizedDrawing;
- (nullable NSArray *)cg_registeredDraggedTypes;


/* **AND THE LEVEL ITSELF, WHICH IS WHERE THOSE CONSTANTS ARE USED.** Apple's header says nothing about it beyond the
 * declaration, and what it means is a place in the stack ABOVE OR BELOW other windows — which in this tier is the
 * window manager's to arrange (D5), exactly as `-orderWindow:relativeTo:` says of its own argument. So the level is
 * RECORDED: a normal window starts at `NSNormalWindowLevel`, and a caller that raises its level is stating a
 * request the manager honours. */
- (NSInteger)level;
- (void)setLevel:(NSInteger)level;

/* ============================================================================================ *
 * THE FRAME'S CONSTRAINTS, AND THE DOCUMENTED RULE THAT MAKES THEM TWO PAIRS AND NOT FOUR KNOBS.  *
 * ============================================================================================ */

/* **APPLE'S OWN RULE, WHICH CHANGED HOW THIS WAS WRITTEN: THE ASPECT RATIO AND THE RESIZE INCREMENTS ARE MUTUALLY
 * EXCLUSIVE, AND SETTING ONE CANCELS THE OTHER.** Its documentation says so in those words — "An NSWindow object's
 * aspect ratio and its resize increments are mutually exclusive attributes. In fact, setting one attribute cancels
 * the setting of the other", and the worked example is the way to clear a ratio: set the increments to (1, 1). So
 * these are not four independent knobs to store; a setter clears its opposite, which is behaviour a probe can
 * check.

 * AND THE SAME DOCUMENTATION SAYS WHAT THEY DO NOT TOUCH: "You can set an NSWindow object's size to any ratio
 * programmatically" — so `-setFrame:` is NOT constrained by either. This tier's frame sets therefore apply the
 * min/max constraints they always did and nothing else here, and the half these values DO govern, the USER's
 * resize, is the window manager's in this design (D5).

 * THE TWO PAIRS, WITH THE PRECEDENCE APPLE GIVES THEM, ALSO QUOTED: "contentAspectRatio takes precedence over
 * aspectRatio" and "contentResizeIncrements takes precedence over resizeIncrements" — so the frame pair applies
 * only when the content pair says nothing, and the mutual exclusion holds WITHIN each pair.

 * `(0, 0)` is "no ratio" and `(1, 1)` is "no increment", which is why a freshly built window carries both. */
- (void)setResizeIncrements:(NSSize)increments;
- (NSSize)resizeIncrements;
- (void)setAspectRatio:(NSSize)ratio;
- (NSSize)aspectRatio;
- (void)setContentResizeIncrements:(NSSize)increments;
- (NSSize)contentResizeIncrements;
- (void)setContentAspectRatio:(NSSize)ratio;
- (NSSize)contentAspectRatio;

/* ============================================================================================ *
 * THE APPEARANCE FLAGS AND THE HONEST ABSENCES.                                                  *
 * ============================================================================================ */

/* **THE FLAGS ARE RECORDED, WITH THE EFFECT NAMED, BECAUSE THE EFFECT IS THE WINDOW MANAGER'S OR THE COMPOSITOR'S
 * IN THIS DESIGN** (D5/D6: the manager honours Cocoa's frame API and draws no chrome). A window's opacity, its
 * shadow, its resize indicator and its toolbar button are all things the guest's manager would draw or honour, and
 * none of them can be made true from inside an X client there. What this tier CAN do is keep the value and say so,
 * which is the same shape `-collectionBehavior` and the miniwindow doors already use. */
- (void)setAlphaValue:(CGFloat)alphaValue;
- (CGFloat)alphaValue;
- (void)setOpaque:(BOOL)opaque;
- (BOOL)isOpaque;
- (void)setHasShadow:(BOOL)hasShadow;
- (BOOL)hasShadow;
- (void)setShowsResizeIndicator:(BOOL)show;
- (BOOL)showsResizeIndicator;

/* ============================================================================================ *
 * THE REST OF THE WINDOW'S FLAGS, AND THE THREE THAT ARE ANSWERS RATHER THAN STORES.            *
 * ============================================================================================ */

/* **THE SAME SHAPE THE APPEARANCE FLAGS USE: RECORDED, WITH THE EFFECT NAMED.** Each of these describes something
 * the window manager or the compositor would honour in this design (D5/D6) — whether a panel floats, whether a
 * window joins the Windows menu, whether flushing is disabled, whether the cursor rects are live — and none of it
 * can be made true from inside an X client. Where Apple's accessor spelling differs from the ledger's property name
 * it is APPLE'S SPELLING that is declared here (`-isAutodisplay`, `-isFlushWindowDisabled`,
 * `-isExcludedFromWindowsMenu`), because the ledger's row is answered by a declaration, not the other way round. */
- (void)setAllowsConcurrentViewDrawing:(BOOL)flag;
- (BOOL)allowsConcurrentViewDrawing;
- (void)setAllowsToolTipsWhenApplicationIsInactive:(BOOL)flag;
- (BOOL)allowsToolTipsWhenApplicationIsInactive;
- (void)setAutodisplay:(BOOL)flag;
- (BOOL)isAutodisplay;
- (void)disableFlushWindow;
- (void)enableFlushWindow;
- (BOOL)isFlushWindowDisabled;
- (void)setExcludedFromWindowsMenu:(BOOL)flag;
- (BOOL)isExcludedFromWindowsMenu;
- (void)setOneShot:(BOOL)flag;
- (BOOL)isOneShot;
- (void)setReleasedWhenClosed:(BOOL)flag;
- (BOOL)isReleasedWhenClosed;
- (void)setFloatingPanel:(BOOL)flag;
- (BOOL)isFloatingPanel;
- (void)setModalPanel:(BOOL)flag;
- (BOOL)isModalPanel;
- (void)setWorksWhenModal:(BOOL)flag;
- (BOOL)worksWhenModal;
- (void)setPreventsApplicationTerminationWhenModal:(BOOL)flag;
- (BOOL)preventsApplicationTerminationWhenModal;
- (void)setCanBecomeVisibleWithoutLogin:(BOOL)flag;
- (BOOL)canBecomeVisibleWithoutLogin;
- (void)setDisplaysWhenScreenProfileChanges:(BOOL)flag;
- (BOOL)displaysWhenScreenProfileChanges;
- (void)setPreservesContentDuringLiveResize:(BOOL)flag;
- (BOOL)preservesContentDuringLiveResize;

/* **AND THE THREE THAT ARE ANSWERS.** `-backingType` is REAL AND READ FROM THE INITIALISER: Apple's door returns
 * the backing-store type the window was created with, so the initialiser keeps it. `-backingLocation` reports where
 * that store ACTUALLY is, and this tier's is not the window server's VRAM — the surface is an X window whose
 * contents this tier draws through a `CGContext` — so the honest answer is `NSWindowBackingLocationMainMemory`,
 * with the reason stated. `-preferredBackingLocation` is what the window WOULD use, which for the same reason is
 * the same value. */
- (void)setBackingType:(NSBackingStoreType)bufferingType;
- (NSBackingStoreType)backingType;
- (NSWindowBackingLocation)backingLocation;
- (NSWindowBackingLocation)preferredBackingLocation;

/* AND TWO THAT ARE THE TRUTH ABOUT THIS TIER RATHER THAN STORES: `-orderedIndex` is a place in the application's
 * ORDERED WINDOW LIST, which this tier does not keep (the manager does), so it answers 0 — the position of a window
 * in a list of one — and `-resizeFlags` is only meaningful DURING a live resize, of which there is none. */
- (NSInteger)orderedIndex;
- (NSUInteger)resizeFlags;

- (void)setShowsToolbarButton:(BOOL)show;
- (BOOL)showsToolbarButton;

/* AND THE ONES THAT ANSWER RATHER THAN STORE, EACH BECAUSE THE ANSWER IS THE TRUTH HERE: a window is never in a
 * live resize (nothing resizes it live), the single-space model means the one space IS the active one, and this
 * tier has no Carbon ref, no toolbar, no drawers, no cells, no Dock tile, and no graphics context of its own — it
 * draws through a `CGContext`. `-drawers` answering an EMPTY ARRAY is not a refusal: Apple's own contract for a
 * window without drawers is exactly that. */
- (BOOL)inLiveResize;
- (BOOL)isOnActiveSpace;
- (void *)windowRef;
- (nullable id)toolbar;
- (nullable NSArray *)drawers;
- (nullable id)defaultButtonCell;
- (nullable id)dockTile;
- (nullable NSGraphicsContext *)graphicsContext;
- (nullable NSEvent *)currentEvent;

/* ============================================================================================ *
 * AND TWO VERSION NUMBERS, WHICH ARE APPLE'S OWN PUBLISHED VALUES.                               *
 * ============================================================================================ */

/* These are not ours to choose: Apple's header gives them, as the AppKit version at which a feature arrived —
 * `NSAppKitVersionNumberWithCustomSheetPosition` is 686.0 and `...WithDeferredWindowDisplaySupport` is 1019.0 in
 * the 10.6 header. A caller compares them against `NSAppKitVersionNumber`, so a made-up number would answer every
 * such comparison wrongly. */
extern double NSAppKitVersionNumberWithCustomSheetPosition;
extern double NSAppKitVersionNumberWithDeferredWindowDisplaySupport;


/* **WHICH SCREEN THIS WINDOW IS ON, AND WHICH ONE IS DEEPEST — TWO QUESTIONS WITH TWO DIFFERENT ANSWERS.** The
 * 10.6 header declares both doors and no prose, so the selection bases are quoted from Apple's own documentation:
 *
 *   `-screen` is "the screen that (most of) the window is on" — the screen covering the LARGEST PORTION of the
 *   window's frame. That wording is the legacy AppKit/OpenStep reference (the modern page is terse), so the AREA
 *   basis is what is implemented here, stated rather than assumed.
 *
 *   `-deepestScreen` is "the deepest screen the window is on (it may be split over several screens)" — chosen by
 *   DEPTH rather than by area, which is exactly why a window spanning two screens may answer differently to the two
 *   doors.
 *
 * AND BOTH ANSWER nil WHEN THE WINDOW IS OFFSCREEN: Apple documents that for `-deepestScreen`, and it follows for
 * `-screen` — a window that overlaps no screen is on none. THE TIE-BREAKS ARE OURS AND ARE STATED: equal area, or
 * equal depth, keeps the FIRST screen `+screens` lists, because nothing in the documentation orders equals. */
/* AND THE FOUR THAT REFUSE, for the reasons above. */
- (void)invalidateShadow;
- (void)cacheImageInRect:(NSRect)aRect;
- (void)discardCachedImage;
- (void)restoreCachedImage;
- (void)disableScreenUpdatesUntilFlush;

- (void)orderFront:(nullable id)sender;
- (void)orderOut:(nullable id)sender;
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin;
- (void)makeKeyAndOrderFront:(nullable id)sender;
- (void)makeKeyWindow;
- (void)makeMainWindow;

/* ============================================================================================ *
 * WHETHER THE WINDOW MAY BE KEY OR MAIN.                                                        *
 * ============================================================================================ */

/* **BOTH ARE READ-ONLY, AND THAT IS WHAT MAKES THEM API RATHER THAN STATE.** Apple declares no setter for either:
 * a window that must be able to become key while borderless is a SUBCLASS that overrides the door, which is why the
 * defaults have to be somewhere and why this pair is a question rather than a flag. The defaults are Apple's
 * documentation, quoted because it is the only ground for them (the header carries the method and no prose):
 *
 *   "Attempts to make the window the key window are abandoned if the value of this property is false."
 *   `canBecomeKeyWindow` — default "true if the window has a title bar or a resize bar".
 *   `canBecomeMainWindow` — default "true when the window is visible, is not an NSPanel object, and has a title bar
 *   or a resize mechanism".
 *
 * SO A BORDERLESS WINDOW ANSWERS NO TO BOTH, and an attempt to make one key is abandoned rather than honoured —
 * which is what `-makeKeyWindow`/`-makeMainWindow` below now do, and the one place this tier's behaviour changes.
 *
 * THE THIRD CONDITION OF THE MAIN RULE IS NOT IMPLEMENTABLE HERE, AND IS STATED RATHER THAN DROPPED: "is not an
 * NSPanel object" cannot be tested because THIS TREE HAS NO NSPanel (the class is an open ledger row, not a
 * declaration — and a forward declaration would mark it shipped for a class that does not exist). A panel in a tree
 * that grows one overrides these doors, which is exactly the route Apple documents for a window whose answer must
 * differ. */
- (BOOL)canBecomeKeyWindow;
- (BOOL)canBecomeMainWindow;

/* ============================================================================================ *
 * FOUR VOCABULARIES, AND THE TWO DOORS THAT CARRY TWO OF THEM.                                   *
 * ============================================================================================ */


/* **`-collectionBehavior` IS A REQUEST THIS TIER RECORDS, AND WHAT IT DOES NOT DO IS NAMED.** Apple's behaviour
 * names are about SPACES and exposé — "can join all spaces", "move to the active space" — and there are no spaces
 * here: a window manager is the thing that would honour them (D5's), and it is the guest's. So the value
 * round-trips and nothing reads it, which is said here rather than left implied by a door that looks like work. */
- (NSWindowCollectionBehavior)collectionBehavior;
- (void)setCollectionBehavior:(NSWindowCollectionBehavior)behavior;

/* **AND THE SHARING TYPE IS THE ONE VOCABULARY THIS FILE REFUSES TO PRETEND ABOUT.** Apple's own prose, quoted
 * because it is the ground for the default:
 *
 *   "-setSharingType: specifies whether the window content can be read and/or written from another process. The
 *    default sharing type is NSWindowSharingReadOnly, which means other processes can read the window content (eg.
 *    for window capture) but cannot modify it. If you set your window sharing type to NSWindowSharingNone, so that
 *    the content cannot be captured, your window will also not be able to participate in a number of system
 *    services, so this setting should be used with caution. If you set your window sharing type to
 *    NSWindowSharingReadWrite, other processes can both read and modify the window content."
 *
 * SO THE GETTER ANSWERS `NSWindowSharingReadOnly`, AND THAT IS A FACT ABOUT THIS TIER RATHER THAN A DEFAULT COPIED
 * DOWN: the window's pixels live in an X window, and any X client that can reach the display can read them. What
 * the tier CANNOT do is the other two, and `-setSharingType:` REFUSES THEM BY NAME rather than recording them — X
 * has no per-window sharing attribute, so a recorded `NSWindowSharingNone` would be a PRIVACY CONTROL THAT DOES
 * NOT EXIST, which is the one shape of half-implementation this tree treats as worse than an open row. */
- (NSWindowSharingType)sharingType;
- (void)setSharingType:(NSWindowSharingType)type;
- (void)resignKeyWindow;
- (void)close;
- (void)center;


/* ============================================================================================ *
 * WHERE THE WINDOW IS, AND WHERE IT WAS.                                                        *
 *                                                                                                *
 * A WINDOW THAT CANNOT BE PLACED CANNOT BE MANAGED, and every door here answers one of two    *
 * questions: WHERE (the two screen conversions and the top-left setter) and WHERE IT WAS       *
 * (the zoom pair and the saved-frame family). The screen is the X ROOT — see the class note —  *
 * so `-constrainFrameRect:toScreen:` ignores its argument by design.                            *
 * ============================================================================================ */

/* THE TOP-LEFT SETTER, WHICH EXISTS BECAUSE COCOA'S FRAME ORIGIN IS THE BOTTOM-LEFT: the subtraction of the
 * height is the whole of the door, and a caller moving a window by its title bar needs it. */
- (void)setFrameTopLeftPoint:(NSPoint)point;

/* THE TWO SCREEN CONVERSIONS. The BASE coordinates are the window's own with the origin at its bottom-left,
 * so these are the frame's origin added and subtracted — no bezel, which is the deviation the class note
 * states rather than a rounding for a caller to discover. */
- (NSPoint)convertBaseToScreen:(NSPoint)aPoint;
- (NSPoint)convertScreenToBase:(NSPoint)aPoint;

/* THE ZOOM, WHICH ALTERNATES: Apple's `-zoom:` grows the window to the standard frame and a second `-zoom:`
 * puts it back where the user had it. `-performZoom:` is the door the ZOOM BUTTON and the menu item send, and
 * this class's implementation of it calls `-zoom:` — a subclass overrides one and gets the other's behaviour. */
- (void)zoom:(nullable id)sender;
- (void)performZoom:(nullable id)sender;
- (BOOL)isZoomed;
- (void)setIsZoomed:(BOOL)flag;

/* HOW LONG AN ANIMATED RESIZE WOULD TAKE — answered, not refused: this window's frame change is ONE X request
 * and there is no animation to time, which is Apple's own answer for a window that cannot animate. */
- (NSTimeInterval)animationResizeTime:(NSRect)newFrame;

/* AND THE CONSTRAINT: a window may hang off the screen, but NOT so far that its title bar is out of reach. */
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(nullable NSScreen *)screen;

/* THE MINIMUM WIDTH A FRAME WITH THIS TITLE CAN HAVE. The arithmetic is OURS and stated as an estimate:
 * Apple's measures the rendered title, and this window owns no font metrics — what the door promises is the
 * PROPERTY a caller relies on (a wider title gives a wider minimum, and never narrower than the buttons). */
+ (CGFloat)minFrameWidthWithTitle:(NSString *)aTitle styleMask:(NSUInteger)aStyle;

/* ---- AND WHERE IT WAS, WHICH IS WHAT A SAVED FRAME IS -------------------------------------- */

/* THE STRING IS `x y w h`, whitespace-separated — the form `-stringWithSavedFrame` writes and the form
 * `-setFrameFromString:` reads, with the trailing space Apple's writes. The parse is PERMISSIVE about runs of
 * whitespace and REFUSES a string that is not four numbers rather than placing the window somewhere invented. */
- (nullable NSString *)stringWithSavedFrame;
- (void)setFrameFromString:(NSString *)string;

/* THE NAMES LIVE IN THE STANDARD USER DEFAULTS, under the name given — that is where Apple keeps them, and it
 * is what makes a saved frame outlive the process. `-setFrameUsingName:` answers NO when nothing was saved
 * rather than placing the window at an origin of zero. */
- (BOOL)setFrameUsingName:(NSString *)name;
- (BOOL)setFrameUsingName:(NSString *)name force:(BOOL)force;
- (void)saveFrameUsingName:(NSString *)name;
+ (void)removeFrameUsingName:(NSString *)name;
- (void)setFrameAutosaveName:(NSString *)name;
- (nullable NSString *)frameAutosaveName;

/* THE WINDOW LEVEL, whose value is ours (Apple publishes the symbol and no number). THE SCREEN'S OWN CONSTANTS
 * ARE NOT HERE: they moved to `NSScreen.h`, which is where Apple declares them and where they are now defined —
 * the window was merely the first thing in this tree to need them. */
extern const CGFloat NSScreenSaverWindowLevel;


/* ============================================================================================ *
 * THE WINDOW COMES FORWARD, GOES BACK, AND KNOWS WHETHER IT IS THE KEY WINDOW.                  *
 *                                                                                                *
 * ALL FOUR ORDERING DOORS ARE `XRaiseWindow`/`XLowerWindow` UNDERNEATH, because on a server     *
 * the stacking order IS the z order — and it is READABLE (`XQueryTree`), which is what makes    *
 * the probe's checks facts about the server rather than about this object's memory.            *
 * ============================================================================================ */

/* `-orderBack:` puts the window BEHIND its siblings; `-orderFrontRegardless` brings it to the front WITHOUT
 * making it key — which is the whole difference between it and `-makeKeyAndOrderFront:` (shipped). */
- (void)orderBack:(nullable id)sender;
- (void)orderFrontRegardless;

/* **THE SHEET DOORS, AND WHAT THEY ARE NOT.** Apple's 10.6 header declares exactly these two: `-isSheet` answers
 * whether THIS window is a sheet, and `-attachedSheet` answers which sheet is attached to THIS window. Both are
 * questions about the attachment, so both live in the file that owns it.
 *
 * `-sheetParent` IS NOT DECLARED HERE — it is Apple's LATER spelling (the live ledger carries it as a property
 * this pin does not have), and the era ground is what this surface is measured against. A caller at this pin asks
 * the sheet `-isSheet` and the parent `-attachedSheet`, which is the whole of the pairing. */
- (BOOL)isSheet;
- (nullable NSWindow *)attachedSheet;

/* ============================================================================================ *
 * THE STANDARD BUTTONS' VOCABULARY.                                                             *
 * ============================================================================================ */

/* THE FIVE KINDS OF STANDARD BUTTON, and the values are APPLE'S OWN ENUMERATION ORDER: the header writes no
 * explicit numbers, so the order it lists them in IS the value (close, miniaturize, zoom, toolbar, document icon
 * — 0 through 4). Written out here rather than left implicit because a caller's `switch` reads them, and because
 * this file's own chrome draws the first three as ellipses in that same order. */
enum {
	NSWindowCloseButton = 0,
	NSWindowMiniaturizeButton = 1,
	NSWindowZoomButton = 2,
	NSWindowToolbarButton = 3,
	NSWindowDocumentIconButton = 4
};
typedef NSUInteger NSWindowButton;

/* **THE TWO DOORS, AND WHY THEY ANSWER `id` AND THEN nil.** Apple's door answers the standard BUTTON OBJECT of a
 * kind — an `NSButton` — and there is no `NSButton` in this tree's AppKit at all: a window's chrome here is
 * PAINTED (the strip, the three ellipses, the edited dot), not built from views with buttons inside them (D6, the
 * user's decision that the window draws its own chrome). So the doors are declared with `id` rather than a
 * forward-declared `NSButton` — a `@class` line would flip the ledger's `NSButton` row into "shipped" for a class
 * that does not exist — and they answer nil, which is a value Apple's own contract already carries for a window
 * with no button of that kind.
 *
 * WHY nil RATHER THAN A NAMED REFUSAL: nothing is WRONG with this call. Apple's own header shows the usage
 * `[[NSWindow standardWindowButton:NSWindowDocumentIconButton] setImage:customImage]`, and against nil that is a
 * NO-OP — the ported caller carries on with a window whose chrome it does not own. A refusal would turn an
 * ordinary call into an exception for a caller that has done nothing wrong. */
+ (nullable id)standardWindowButton:(NSWindowButton)b forStyleMask:(NSUInteger)styleMask;
+ (nullable NSArray *)windowNumbersWithOptions:(NSWindowNumberListOptions)options;
+ (NSInteger)windowNumberAtPoint:(NSPoint)point belowWindowWithWindowNumber:(NSInteger)windowNumber;

- (nullable id)standardWindowButton:(NSWindowButton)b;

/* ============================================================================================ *
 * THE CHILD WINDOWS.                                                                            *
 * ============================================================================================ */

/* **A CHILD WINDOW IS A WINDOW THAT MOVES WITH ANOTHER ONE, AND THE TWO HALVES OF THAT ARE BOTH APPLE'S OWN
 * SENTENCES.** Its header declares these five doors and no prose at all, so the contract is Apple's DOCUMENTATION,
 * quoted here because a behaviour implemented to a remembered shape is exactly what this tree refuses:
 *
 *   "After the childWin is added as a child of the window, it is maintained in relative position indicated by
 *    place for subsequent ordering operations involving either window. While this attachment is active, moving
 *    childWin will not cause the window to move (as in sliding a drawer in or out), but moving the window will
 *    cause childWin to move."
 *
 *   (of `-orderOut:`) "Calling orderOut: on a child window causes the window to be removed from its parent window
 *    before being removed."
 *
 * SO THE TIER DOES TWO THINGS BEYOND KEEPING THE LIST: a MOVE OF THE PARENT MOVES ITS CHILDREN BY THE SAME DELTA,
 * and ORDERING A CHILD OUT DETACHES IT. The asymmetry is not an oversight — it is the first sentence above, and it
 * is why the movement lives on the parent's side of the relationship and nowhere else: a child that dragged its
 * parent along would be sliding a drawer and moving the wall.
 *
 * WHAT IS NOT DONE IS STATED RATHER THAN IMPLIED. The `place` this door is given orders the child relative to its
 * parent through this tier's own `-orderWindow:relativeTo:`, which is a REQUEST: real stacking is the window
 * manager's, and the guest's manager is what honours Cocoa's frames (D5). Nor is a child ORDERED OUT when its
 * parent is: Apple's documentation does not say so, the frameworks that fought this API report it as a BUG rather
 * than a contract, and a tier that invented it would be inventing a behaviour to be debugged later.
 *
 * A CYCLE IS REFUSED BY NAME, not tolerated: Apple's own page warns against one, and here every later move would
 * walk it forever. */
- (void)addChildWindow:(NSWindow *)childWin ordered:(NSWindowOrderingMode)place;
- (void)removeChildWindow:(NSWindow *)childWin;
- (nullable NSArray *)childWindows;

/* `-parentWindow` IS NIL WHEN THE WINDOW HAS NONE, and `-childWindows` is nil rather than an empty array when there
 * are none — which reads identically to a caller iterating it, and avoids handing back a fresh object on every ask.
 * `-setParentWindow:` is the same relationship expressed from the child's side; the ordering it uses is
 * `NSWindowAbove`, because Apple documents no order for this door and a child that is not told otherwise is a
 * satellite in front of the window it belongs to. A caller that wants a specific order uses the door that takes
 * one. */
- (nullable NSWindow *)parentWindow;
- (void)setParentWindow:(nullable NSWindow *)window;

/* THE FOUR DOORS THE FRAMEWORK CALLS, AND THE RULE THAT A FRAMEWORK CALLS THEM: Apple documents that a window
 * should not call these on itself but OVERRIDE them, because becoming key is announced to the whole
 * application — so this implementation RESIGNS THE PREVIOUS WINDOW and POSTS the notification, which is what
 * the shipped `-makeKeyWindow`/`-resignKeyWindow` did not do. */
- (void)becomeKeyWindow;
- (void)becomeMainWindow;
- (void)resignMainWindow;

/* AND THE FLUSH PAIR. X flushes the whole display at once, so `-flushWindow` and `-flushWindowIfNeeded` differ
 * only in Apple's words here — what both honour is WHETHER FLUSHING IS ENABLED, which is the flag. */
- (void)flushWindow;
- (void)flushWindowIfNeeded;
- (void)enableFlushWindow;
- (void)disableFlushWindow;

/* AND THE TITLE THAT STANDS FOR A FILE: the title becomes the file's NAME and the path is remembered, which is
 * what the title bar's proxy icon is for. */
- (void)setTitleWithRepresentedFilename:(NSString *)aString;
- (nullable NSString *)representedFilename;

/* THE FOUR NOTIFICATIONS A KEY OR MAIN CHANGE POSTS. */
extern NSString *NSWindowDidBecomeKeyNotification;
extern NSString *NSWindowDidBecomeMainNotification;
extern NSString *NSWindowDidResignKeyNotification;
extern NSString *NSWindowDidResignMainNotification;


/* ============================================================================================ *
 * THE KEY-VIEW LOOP: WHAT TAB DOES.                                                              *
 *                                                                                                *
 * THE LOOP IS A CYCLE OF THE VIEWS THAT ACCEPT FIRST RESPONDER, and it is what makes Tab mean    *
 * anything. Computing it has an ORDER, and Apple's is a READING order rather than the order the  *
 * views were added in — so a grid of fields Tab follows left to right and top to bottom even if  *
 * it was built bottom-up. That is the contract this implementation keeps, and it is the one a   *
 * probe can tell apart from its alternative.                                                    *
 * ============================================================================================ */
- (void)recalculateKeyViewLoop;
- (void)selectNextKeyView:(nullable id)sender;
- (void)selectPreviousKeyView:(nullable id)sender;
- (void)selectKeyViewFollowingView:(NSView *)aView;
- (void)selectKeyViewPrecedingView:(NSView *)aView;


/* ============================================================================================ *
 * WHAT THE TITLE BAR'S BUTTONS DO.                                                              *
 *                                                                                                *
 * THE CLOSE IS ASKED BEFORE IT HAPPENS (a delegate may refuse it), THE MINIATURIZE IS A STATE  *
 * THIS WINDOW KEEPS as well as a request to the server, and THE CASCADE IS ARITHMETIC the      *
 * caller feeds back in.                                                                         *
 * ============================================================================================ */
- (void)performClose:(nullable id)sender;
- (void)miniaturize:(nullable id)sender;
- (void)deminiaturize:(nullable id)sender;
- (void)performMiniaturize:(nullable id)sender;
- (void)setIsMiniaturized:(BOOL)flag;
- (BOOL)isMiniaturized;
- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)topLeft;

/* AND THE THREE NOTIFICATIONS THE MINIATURIZE POSTS. */
extern NSString *NSWindowWillMiniaturizeNotification;
extern NSString *NSWindowDidMiniaturizeNotification;
extern NSString *NSWindowDidDeminiaturizeNotification;

/* AND THE SIX ANNOUNCEMENTS THE DELEGATE'S OTHER CALLBACKS ARRIVE WITH. The values are their own identifiers, the
 * rule this tier follows wherever Apple publishes a symbol and no string. */
extern NSString *NSWindowWillCloseNotification;
extern NSString *NSWindowWillMoveNotification;
extern NSString *NSWindowDidMoveNotification;
extern NSString *NSWindowDidResizeNotification;
extern NSString *NSWindowDidExposeNotification;
extern NSString *NSWindowDidUpdateNotification;

/* ============================================================================================ *
 * SIX ANNOUNCEMENTS, TWO OF WHICH NOW FIRES — AND THE DELEGATE DOORS THEY BELONG TO.              *
 * ============================================================================================ */

/* THIS CLASS'S DELEGATE PROTOCOL ALREADY DECLARED ALL SIX OF THESE DOORS AND NOTHING EVER CALLED THEM, so the
 * names below are not new surface so much as the other half of a promise this header was already making:
 * `-windowWillBeginSheet:`, `-windowDidEndSheet:`, `-windowWillStartLiveResize:`, `-windowDidEndLiveResize:`,
 * `-windowDidChangeScreen:` and `-windowDidChangeScreenProfile:`.
 *
 * THE SHEET PAIR IS POSTED, WITH THE PARENT AS THE OBJECT — and the object is Apple's own wording rather than a
 * guess: "the NSWindow object that's about to open the sheet" for the first and "the NSWindow object that contained
 * the sheet" for the second. So an observer registered on the SHEET is told nothing, which the probe asserts, and an
 * observer on the PARENT is told both times. WHAT IS OURS IS THE MOMENT: Apple posts the did-end notification when
 * the sheet finishes animating offscreen, and nothing here animates — the modal session's end is that moment.
 *
 * AND FOUR OF THE SIX CANNOT FIRE IN THIS TIER, EACH FOR A REASON THAT IS A PROPERTY OF THIS TREE RATHER THAN A
 * GAP:
 *
 *   * the LIVE-RESIZE pair describes a user's DRAG, and the drag belongs to the guest's window manager (D5) — the
 *     same reason `-inLiveResize`/`-preservesContentDuringLiveResize` are not declared either.
 *   * the SCREEN pair describes a window MOVING BETWEEN SCREENS, and there is ONE screen here — a single X
 *     connection's geometry is what `NSScreen` reports (the same reason
 *     `NSApplicationDidChangeScreenParametersNotification` is declared there and never posted).
 *
 * They are declared because a ported application REGISTERS an observer by name, and a name that does not exist is a
 * compile error rather than a notification that never arrives. */
extern NSString *NSWindowWillBeginSheetNotification;
extern NSString *NSWindowDidEndSheetNotification;
extern NSString *NSWindowWillStartLiveResizeNotification;
extern NSString *NSWindowDidEndLiveResizeNotification;
extern NSString *NSWindowDidChangeScreenNotification;
extern NSString *NSWindowDidChangeScreenProfileNotification;


/* ============================================================================================ *
 * AND THE HALF OF THE CURSOR RECTS THAT IS THE WINDOW'S.                                         *
 *                                                                                                *
 * THE WINDOW RESOLVES THE WINNER AS THE POINTER MOVES, and it is the only object that knows    *
 * when a pass is due — so the view declares and the window decides. `-disableCursorRects` is   *
 * what a caller uses while it is rearranging views, and it is a real door rather than a       *
 * convenience: rebuilding the rects under a live pointer would otherwise flash the wrong       *
 * cursor at the user.                                                                          *
 * ============================================================================================ */
- (void)resetCursorRects;
- (void)discardCursorRects;
- (void)disableCursorRects;
- (void)enableCursorRects;
/* **AND THE GETTER FOR THE SAME STATE**, which Apple declares beside them (`-areCursorRectsEnabled`, line 439 of its
 * 10.6 header). It READS the flag the pair sets rather than keeping one of its own — the lesson `-isFlushWindowDisabled`
 * taught in the same unit: two doors onto one question, one state. */
- (BOOL)areCursorRectsEnabled;
- (void)invalidateCursorRectsForView:(NSView *)aView;

/* ============================================================================================ *
 * THE DEPTH LIMIT.                                                                              *
 *                                                                                                *
 * A WINDOW'S BACKING STORE HAS A DEPTH AND A CALLER MAY ASK FOR ONE. THIS WINDOW'S SURFACE IS   *
 * THE 24-BIT ONE (Apple's own default) and NOTHING HERE MAKES A DEEPER ONE YET — so a limit    *
 * that asks for more is REFUSED BY NAME rather than recorded and quietly ignored, which is    *
 * the difference between a caller knowing and a caller guessing.                                *
 * ============================================================================================ */
- (void)setDepthLimit:(NSWindowDepth)limit;
- (NSWindowDepth)depthLimit;
+ (NSWindowDepth)defaultDepthLimit;
/* AND WHETHER THE WINDOW MAY CHANGE ITS DEPTH BY ITSELF, which is a real flag in the era's API rather than a
 * convenience: a window that follows the screen needs it, and one that must not move does not. */
- (void)setDynamicDepthLimit:(BOOL)flag;
@property (readonly) BOOL hasDynamicDepthLimit;
/* AND WHETHER THE WINDOW'S DOCUMENT HAS UNSAVED CHANGES — a window manager draws this as the dot in the close
 * button, and a caller reads it to decide whether to prompt. */
@property (getter=isDocumentEdited) BOOL documentEdited;

@end
/* ============================================================================================ *
 * THE DELEGATE'S PROTOCOL — AND EVERY METHOD IS OPTIONAL, WHICH IS WHY EVERY SEND IS GUARDED.  *
 *                                                                                                *
 * THIS IS THE PROTOCOL THE CALLBACKS BELONG TO, and until it existed the window's own close    *
 * asked its delegate through an INFORMAL category on `NSObject` — a declaration that says      *
 * "some object might answer this". A real protocol says WHICH messages and WITH WHAT           *
 * SIGNATURES, which is what lets the sends below be ordinary checked sends instead of         *
 * `-methodForSelector:` and a guessed calling convention.                                      *
 *                                                                                                *
 * WHAT IS DECLARED IS THE ERA'S SURFACE (10.2-10.6). THE POST-10.6 CALLBACKS — the full-screen *
 * and version-browser families, occlusion, backing properties, window sharing — ARE STRUCK IN *
 * THE LEDGER WITH THEIR CLASS rather than declared, which is this plan's own rule for a row    *
 * that is newer than the pins: a protocol that declared them would be promising a feature      *
 * this tier has not reached.                                                                   *
 *                                                                                                *
 * AND NOT ALL OF THESE ARE SENT YET, WHICH IS STATED RATHER THAN LEFT TO BE DISCOVERED: the     *
 * sheet, live-resize and screen callbacks arrive with the features that produce them. What is  *
 * wired is every callback this window can actually cause.                                      *
 * ============================================================================================ */
@protocol NSWindowDelegate <NSObject>
@optional
/* ASKING, BEFORE SOMETHING HAPPENS. These return a value, so they are not announcements. */
- (BOOL)windowShouldClose:(NSWindow *)sender;
- (BOOL)windowShouldZoom:(NSWindow *)window toFrame:(NSRect)newFrame;
- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame;
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize;
- (nullable NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window;
/* AND THE FIELD EDITOR: what a delegate answers when the window asks which editor a client should be given.
 *
 * IT IS DECLARED AND NOT ASKED YET, which is stated rather than left to be discovered: a field editor IS an
 * `NSText` — the note on `-fieldEditor:forObject:` in the window's own block says so — and the text system is
 * stage F, so the door exists for a delegate to implement and NOTHING IN THIS TIER CALLS IT. The probe calls it
 * through the protocol, which is what makes the declaration a checked shape rather than a comment. */
- (nullable id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(nullable id)client;

/* AND THE ANNOUNCEMENTS, which take the notification the window posts. */
- (void)windowWillMove:(NSNotification *)notification;
- (void)windowDidMove:(NSNotification *)notification;
- (void)windowDidResize:(NSNotification *)notification;
- (void)windowDidExpose:(NSNotification *)notification;
- (void)windowWillMiniaturize:(NSNotification *)notification;
- (void)windowDidMiniaturize:(NSNotification *)notification;
- (void)windowDidDeminiaturize:(NSNotification *)notification;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (void)windowDidResignKey:(NSNotification *)notification;
- (void)windowDidBecomeMain:(NSNotification *)notification;
- (void)windowDidResignMain:(NSNotification *)notification;
- (void)windowWillClose:(NSNotification *)notification;
- (void)windowDidUpdate:(NSNotification *)notification;
- (void)windowDidChangeScreen:(NSNotification *)notification;
- (void)windowDidChangeScreenProfile:(NSNotification *)notification;
- (void)windowWillBeginSheet:(NSNotification *)notification;
- (void)windowDidEndSheet:(NSNotification *)notification;
- (void)windowWillStartLiveResize:(NSNotification *)notification;
- (void)windowDidEndLiveResize:(NSNotification *)notification;

@end



NS_ASSUME_NONNULL_END
