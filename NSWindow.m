/*
 * NSWindow — a window on Agora's window server, and the geometry between two coordinate systems.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 *
 * THE DISPLAY SEAM IS `AGWindowServer`'s, AND IT USED TO BE XLIB'S. This file opened an X display, made an
 * `XCreateSimpleWindow` on it, pumped it with `XNextEvent`, translated keys with `XLookupString` and put its
 * pixels on it with `XPutImage`. Agora's display target is Wayland with no X11-native target, so all of that
 * is gone: the window is an `AGWindow`, the events arrive already translated as `AGEvent`s, the pixels are
 * copied into the frame the compositor hands over, and this file includes neither <X11/Xlib.h> nor
 * <X11/Xutil.h>.
 *
 * WHAT A WINDOW SERVER DOES NOT GIVE A CLIENT, RECORDED RATHER THAN DISCOVERED, because Wayland is not X:
 *   - a client does NOT choose where its window is, so `-setFrameOrigin:` moves the COCOA frame and not the
 *     window; the compositor places it;
 *   - there is no unmap, no iconify and no raise/lower in `xdg-shell`, so `-orderOut:`, `-miniaturize:`,
 *     `-orderFront:` and `-orderBack:` change THIS OBJECT's state and not the screen's;
 *   - and there is no Expose, because the client owns the pixels: a repaint is asked for by the frame
 *     callback the compositor sends when it wants a new frame.
 * Each is a deviation with its reason written at the door that carries it.
 *
 * THE COORDINATE CONVERSION IS STILL THE WHOLE OF THE DIFFICULTY. Cocoa puts a window's origin at its
 * BOTTOM-left with y growing UP; the seam reports a pointer measured DOWN from the window's TOP-left. Every
 * point that crosses is converted ONCE, in one place (`fn_window_point`), so there is no second copy of the
 * arithmetic to drift.
 *
 * AND `defer:` IS HONOURED RATHER THAN IGNORED. Apple's flag means "do not create the window until it is
 * ordered front", which is a real saving for a window that may never appear; the `AGWindow` is therefore
 * made on demand, at the first door that needs one, and `-windowNumber` answers -1 until then — which is
 * Apple's own answer for a window with no window number.
 *
 * WHAT IS NOT HERE, AND WHY, so the open rows are a decision rather than an omission: the SHEETS, the
 * TOOLBAR, the DRAWER, the frame-autosave strings, the script-command handling, the cursor-rect
 * invalidation and the child-window list all need subsystems this stage has not reached; the
 * minimisable/closable BUTTONS are a window manager's (Kestrel is parked); and the real screen/zone
 * placement needs `NSScreen`, which is its own row. Each is absent rather than stubbed.
 */
#include "AGWindowServer.h"

#include <math.h>	/* M_PI — the arcs a pill's caps are made of */

#import "AppKitRefusal.h"
#import <CoreGraphics/CGBitmapContext.h>

#import <AppKit/NSWindow.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSNotification.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSStringDrawing.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSResponder.h>
#import <AppKit/NSView.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSString.h>

/* THE TWO PRIVATE DOORS THIS FILE'S TRANSLATION CALLS BEFORE THEY ARE DEFINED, declared here for the reason
 * the rest of this tree declares a private seam in a class extension: the click count is this class's own
 * derivation of a number X does not send, and it is not public API. */
/* **THE VIEW'S CURSOR DOORS, DECLARED HERE BECAUSE THE WINDOW IS THE ONE THAT ASKS THEM.** They belong to
 * `NSView` and are defined in its file; a window that resolved the cursors itself would be a second copy of the
 * front-to-back rule, and the rule is the view's because only the view knows its own subviews. The redeclaration
 * is the same pattern this tree uses for a private door a second file has to call. */
@interface NSView (FNCursorRects)
- (NSCursor *)cg_cursorAtPoint:(NSPoint)point;
- (void)cg_markCursorRectsStale;
- (void)cg_rebuildStaleCursorRects;
- (NSUInteger)cg_cursorRectCount;
@end

@interface NSWindow ()
- (NSInteger)cg_clickCountFor:(NSPoint)p at:(NSTimeInterval)now;
- (NSInteger)currentClickCount;
/* THE SEAM'S DOORS AND THE STATE THEY KEEP, declared here for the same reason. */
- (void)cg_handleSeamEvent:(const AGEvent *)event;
- (void)cg_drawFrame;
- (BOOL)cg_mouseButtonDown;
- (BOOL)cg_ensureWindow;
/* **THE DOOR A STATUS ITEM COMES IN BY, and it is here rather than in `NSStatusItem.m` because the seam is this
 * file's business: a status item needs the window's `AGWindow` and nothing else does. */
- (void)cg_setStatusItemLength:(CGFloat)length;
- (NSEvent *)cg_nextEventWaiting:(BOOL)wait milliseconds:(long)ms mask:(NSUInteger)mask
				dequeue:(BOOL)dequeue;
/* THE CURSOR DOORS THIS FILE ADDS, declared here because this is the file that defines them. */
- (NSScreen *)cg_screenFor:(NSScreen *)screen;
- (void)cg_rebuildCursorRectsIfNeeded;
- (NSCursor *)cg_cursorForContentPoint:(NSPoint)p;
/* THE KEY-VIEW LOOP'S PRIVATE DOORS, declared here because this is the file that defines them. */
- (void)cg_ensureKeyViewLoop;
- (NSView *)cg_keyViewLoopEntry:(NSInteger)index;
- (NSInteger)cg_keyViewLoopIndexOf:(NSView *)view;
- (void)cg_selectKeyViewAt:(NSInteger)index;
/* AND THE CHILD WINDOWS' BACK-REFERENCE, private for the same reason the key-view loop's doors are: it is the half
 * of the relationship that must NOT go through the public door, because that door takes the child's side and would
 * recurse back into the parent's. */
- (void)cg_setParentWindow:(NSWindow *)parent;
/* **AND THE TRACKING ENGINE, WHICH IS THIS FILE'S BECAUSE AN `NSTrackingArea` HAS NO WINDOW OF ITS OWN.** An area is
 * installed on a VIEW and names an OWNER; turning a rectangle in a view's coordinates into "the pointer is inside
 * region R of view V, whose owner wants to hear about it" takes a walk of the tree AND the window's own state (is it
 * key? is a button held?), so the window is the only object that can do it. Called from three places: the pointer's
 * motion, a mouse event, and the pointer leaving the window. */
- (void)cg_updateTrackingForPoint:(NSPoint)windowPoint;
- (void)cg_clearTracking;
@end

/* The engine's doors into an area and into the event it builds: declared in every file that uses them and DEFINED by
 * the class that owns the storage — this tree's shape for a `cg_` door that is the tier's own business rather than
 * anybody's API. */
@interface NSTrackingArea (APPKITTrackingEngine)
- (BOOL)cg_isInside;
- (void)cg_setInside:(BOOL)flag;
@end

@interface NSEvent (APPKITTrackingEngine)
- (void)cg_setTrackingArea:(NSTrackingArea *)area;
@end


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <time.h>


/* THE APPLICATION SEAM, declared here because this file is where it is CALLED — the same shape
 * NSApplication.m uses for the registry door itself. A window that is ordered front joins the run loop's
 * registry, and a window that is closed leaves it: the loop drains what is in the list and nothing else. */
@interface NSApplication (APPKITWindowRegistry)
- (void)cg_addWindow:(NSWindow *)aWindow;
- (void)cg_windowClosed:(NSWindow *)aWindow;
- (void)cg_removeWindow:(NSWindow *)aWindow;
@end

/* THE TITLE BAR'S HEIGHT, AND IT IS OURS. A titled window's FRAME is its content plus its chrome, and this
 * tree draws no title bar yet (Kestrel, which will, is parked) — so the number is this file's, stated here
 * rather than discovered: it is where the chrome and this arithmetic will have to agree. A borderless window
 * has no chrome and adds nothing. */
static const CGFloat fn_TITLE_BAR = 22.0;
/* AND A TITLE-BAR BUTTON'S DIAMETER, which is the second of the TWO numbers the chrome needs: the strip's height
 * above, and the size of the three buttons the window draws in it. Everything else about the chrome — where the
 * buttons sit, how much room `-minFrameWidthWithTitle:` owes them — is derived from these two rather than written
 * a third and fourth time, which is what this file used to do. */
static const CGFloat fn_BUTTON = 16.0;

/* ONE CONNECTION FOR THE PROCESS, made on first use and never dropped: a connection to the window server is a
 * resource a window does not own, and one per window would give two windows two event queues and two
 * registries. A process with no reachable compositor gets NULL, and every door that needs a window then
 * REFUSES BY NAME rather than faulting — which is what makes this library probeable on a machine with no
 * display at all. */
static AGWindowServer *s_server;

/* HOW MANY NSEvents are waiting in every window's queue together. `+cg_waitForEventInMilliseconds:` is a
 * CLASS door and has to answer "is there anything to read" for the PROCESS, and the events land in
 * PER-WINDOW queues — so the count is the one piece of state that spans them. */
static NSInteger s_queued_events;

static AGWindowServer *fn_server(void)
{
	if (s_server == NULL) {
		s_server = AGWindowServerConnect();
	}
	return s_server;
}


/* ---- THE X EVENT, TURNED INTO AN NSEvent ------------------------------------------------ */

/* THE MODIFIER FLAGS, from the seam's mask to the AppKit bits. The seam names them the way this tree's
 * keymaps do — Alt is `Mod1` and Super is `Mod4`, which is what xkbcommon resolves in AGKeyboard — so this is
 * a rename rather than a decision. */
static NSUInteger fn_flags(uint32_t modifiers)
{
	NSUInteger f = 0;

	if (modifiers & AGModifierShift)    f |= NSShiftKeyMask;
	if (modifiers & AGModifierCapsLock) f |= NSAlphaShiftKeyMask;
	if (modifiers & AGModifierControl)  f |= NSControlKeyMask;
	if (modifiers & AGModifierAlt)      f |= NSAlternateKeyMask;
	if (modifiers & AGModifierSuper)    f |= NSCommandKeyMask;
	return f;
}

/* THE CLICK COUNT, WHICH X DOES NOT CARRY. A press that lands within Apple's double-click interval and
 * close to the previous one continues the series; anything else starts a new one. The interval is OURS
 * because there is no settings service here yet, and it is stated where it is used. */
#define APPKIT_DOUBLE_CLICK_SECONDS 0.5
#define APPKIT_CLICK_SLOP 4.0

static NSPoint fn_window_point(NSWindow *w, int x, int y)
{
	NSRect frame = [w frame];

	/* THE Y IS THE WHOLE OF IT: X reports a point measured DOWN from the window's top, AppKit wants it
	 * measured UP from the window's bottom. */
	return NSMakePoint((CGFloat)x, frame.size.height - (CGFloat)y);
}

/* THE TRANSLATION ITSELF, and it is one function for the same reason the point conversion is: the pump, the
 * mouse-location door and any future monitor all have to agree about what a seam event means. A NULL answer
 * is "this is not an event this class delivers" — a configure, a close — and the pump handles those itself
 * rather than inventing an NSEvent for them. */
static NSEvent *fn_translate(NSWindow *w, const AGEvent *e, NSTimeInterval now)
{
	NSPoint where = fn_window_point(w, e->x, e->y);
	NSUInteger flags = fn_flags(e->modifiers);
	NSInteger win = [w windowNumber];

	switch (e->type) {
	case AGEventPointerButton: {
		NSEventType t;
		NSInteger count;

		/* THE BUTTONS ARE EVDEV CODES, not X's numbering: BTN_LEFT is 0x110, BTN_RIGHT 0x111 and BTN_MIDDLE
		 * 0x112. Anything else is an "other" button, which is Apple's own bucket for the rest. */
		switch (e->button) {
		case 0x110: t = e->pressed ? NSLeftMouseDown : NSLeftMouseUp; break;
		case 0x111: t = e->pressed ? NSRightMouseDown : NSRightMouseUp; break;
		default:    t = e->pressed ? NSOtherMouseDown : NSOtherMouseUp; break;
		}
		if (e->pressed) {
			count = [w cg_clickCountFor:where at:now];
		} else {
			count = [w currentClickCount];
		}
		return [NSEvent mouseEventWithType:t location:where modifierFlags:flags
					 timestamp:now windowNumber:win context:nil
					 eventNumber:(NSInteger)e->time_ms
					  clickCount:count pressure:1.0f];
	}
	case AGEventPointerMotion: {
		BOOL dragging = [w cg_mouseButtonDown];

		/* **THE CURSOR IS RESOLVED HERE, BEFORE THE EARLY RETURN BELOW** — because it is the USER's information
		 * rather than the application's: Apple updates it on a move the application never sees, and a window that
		 * only changed its cursor when it also wanted `-mouseMoved:` would leave the wrong one showing for every
		 * window that did not ask for that message. The arrow is the answer when no view has an opinion. */
		{
			NSCursor *c = [w cg_cursorForContentPoint:where];

			[(c != nil ? c : [NSCursor arrowCursor]) set];
		}
		/* **AND THE TRACKING ENGINE RUNS HERE, ABOVE THE EARLY RETURN, WHICH IS THE WHOLE POINT OF PUTTING IT FIRST.**
		 * `-acceptsMouseMovedEvents` decides whether a bare move becomes an `NSEvent` for the responder chain, and an
		 * area's enter and exit are NOT gated on it — an AppKit button prelights in a window that never asked for
		 * `-mouseMoved:`. The engine is handed the position and the event is not built until the return below lets it
		 * through. MEASURED, when this lived under that line: a pointer resting on a button in an ordinary window
		 * changed nothing at all. */
		[w cg_updateTrackingForPoint:where];
		/* A MOVE WITH NO BUTTON IS DELIVERED ONLY IF THE WINDOW ASKED FOR IT — see the header. */
		if (!dragging && ![w acceptsMouseMovedEvents]) {
			return nil;
		}
		return [NSEvent mouseEventWithType:(dragging ? NSLeftMouseDragged : NSMouseMoved)
					  location:where modifierFlags:flags
					 timestamp:now windowNumber:win context:nil
					 eventNumber:(NSInteger)e->time_ms
					  clickCount:0 pressure:1.0f];
	}
	case AGEventKey: {
		/* **THE TEXT ARRIVES ALREADY TRANSLATED**, which is the seam's job and xkbcommon's: `AGKeyboard` turned
		 * the evdev code into UTF-8 through the keymap the COMPOSITOR sent, so there is no keymap in this file
		 * and no `XLookupString` behind it. The keycode is carried too, because a caller that wants the PHYSICAL
		 * key asks for it. */
		NSString *chars = [NSString stringWithUTF8String:e->text];

		if (chars == nil) {
			chars = @"";
		}
		/* **A MODIFIER IS NOT A KEYSTROKE**, and this is where that shows: AppKit delivers one as
		 * `-flagsChanged:` and everything else as `-keyDown:`/`-keyUp:`, so the type is chosen from the seam's
		 * own answer rather than guessed here. The characters travel either way — a modifier's are empty. */
		return [NSEvent keyEventWithType:(e->modifier ? NSFlagsChanged : (e->pressed ? NSKeyDown : NSKeyUp))
					location:where modifierFlags:flags
				       timestamp:now windowNumber:win context:nil
				      characters:chars
			 charactersIgnoringModifiers:chars
				     isARepeat:NO
				       keyCode:(unsigned short)e->keycode];
	}
	default:
		return nil;
	}
}

/* ---- THE SEAM'S TWO HANDLERS, WHICH ARE THE WHOLE OF THIS CLASS'S CONNECTION TO THE SERVER ---------- */

/* AN EVENT FROM THE SERVER. It is converted and QUEUED rather than delivered, because the pump is pulled by
 * `-nextEventMatchingMask:` and a push would have no place to wait. The two kinds that are not NSEvents are
 * handled here instead: a CONFIGURE is the window's new size (and the compositor's answer to a resize this
 * client asked for), and a CLOSE is the window going away. */
static void fn_ag_event(void *context, const AGEvent *e)
{
	NSWindow *w = context;

	[w cg_handleSeamEvent:e];
}

/* A FRAME. This is the compositor saying it has taken the last frame and the buffer is free again, which is
 * the ONLY moment a new frame may be drawn — so this is where a window repaints, and there is no Expose to
 * wait for because the client owns the pixels. */
static void fn_ag_frame(void *context, uint32_t time_ms)
{
	NSWindow *w = context;

	(void)time_ms;
	[w cg_drawFrame];
}

@implementation NSWindow

/* **THE CONNECTION THIS PROCESS USES, ASKED FOR RATHER THAN MADE AGAIN.** A Wayland client has ONE connection to
 * its compositor and this file is where it is made. Anything else that needs to ASK THE SERVER A QUESTION — the
 * application asking where its OWN menus may begin — has to use the same one: a second `AGWindowServerConnect`
 * would be a second connection, carrying a second registry, a second output and a second set of proxies, and two
 * connections that each believe they know the screen is a class of bug this tree does not need to have.
 *
 * AND IT IS A METHOD ON `NSWindow` RATHER THAN A FREE FUNCTION because the connection is this class's to own: the
 * static above is where it is made and cached, and a door that handed it out from anywhere else would be a second
 * place that knows how a client connects. */
+ (AGWindowServer *)cg_sharedServer
{
	return fn_server();
}

/* **AND THE FLAG, WHICH IS ALL THIS DOOR DOES.** `-display` paints now and returns early if the compositor still
 * holds the previous buffer — leaving the flag set, so the run loop's `-displayIfNeeded` tries again next pass.
 * A CALLER THAT WANTS THE PAINT TO HAPPEN NOW calls `-displayIfNeeded` after this, which is the pair the menu's
 * repaint uses. */
- (void)setNeedsDisplay:(BOOL)flag
{
	_viewsNeedDisplay = flag ? YES : NO;
}

/* **THE WINDOW'S BACKGROUND COLOUR.** Apple's door, and the reason it is needed here is the menu bar: an
 * application's menus are drawn IN the bar, and a panel of the window's own default colour is a SEAM across it. Nil
 * is the default and means `+[NSColor windowBackgroundColor]`, so every window that says nothing is unchanged. */
- (NSColor *)backgroundColor
{
	return (_backgroundColor != nil) ? _backgroundColor : [NSColor windowBackgroundColor];
}

- (void)setBackgroundColor:(NSColor *)colour
{
	if (colour == _backgroundColor) {
		return;
	}
	[colour retain];
	[_backgroundColor release];
	_backgroundColor = colour;
	/* THE WINDOW IS A DIFFERENT COLOUR NOW, so what is on the screen is stale until it draws again. **THE DOOR IS
	 * WHAT SETS THE FLAG** — when this line was first written `-setNeedsDisplay:` did not exist here and the ivar
	 * was set by hand, with a comment saying why. It exists now, and the hand-write is gone with it. */
	[self setNeedsDisplay:YES];
}

/* THE STYLE MASK'S CHROME, which is the frame-to-content arithmetic and its inverse. Both directions exist
 * because both are asked for, and they are written as one pair so a change to the title-bar height cannot
 * make them disagree. */
+ (CGFloat)fn_chromeForStyleMask:(NSUInteger)styleMask
{
	return (styleMask & NSTitledWindowMask) ? fn_TITLE_BAR : 0.0;
}

+ (NSRect)contentRectForFrameRect:(NSRect)frameRect styleMask:(NSUInteger)styleMask
{
	CGFloat chrome = [self fn_chromeForStyleMask:styleMask];

	/* THE CONTENT IS THE FRAME MINUS THE CHROME AT THE TOP, because the title bar sits above the content in
	 * a bottom-left system. */
	return NSMakeRect(frameRect.origin.x, frameRect.origin.y,
			  frameRect.size.width, frameRect.size.height - chrome);
}

+ (NSRect)frameRectForContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask
{
	CGFloat chrome = [self fn_chromeForStyleMask:styleMask];

	return NSMakeRect(contentRect.origin.x, contentRect.origin.y,
			  contentRect.size.width, contentRect.size.height + chrome);
}

- (NSRect)contentRectForFrameRect:(NSRect)frameRect
{
	return [[self class] contentRectForFrameRect:frameRect styleMask:_styleMask];
}

- (NSRect)frameRectForContentRect:(NSRect)contentRect
{
	return [[self class] frameRectForContentRect:contentRect styleMask:_styleMask];
}

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{
	/* **THE DEFAULTS AN IVAR CANNOT GIVE.** `(1, 1)` is "no increments" and `(0, 0)` is "no ratio", so a fresh
	 * window carries both pairs neutral; a window is opaque and fully opaque-valued until a caller says otherwise.
	 * `hasShadow` and `showsResizeIndicator` start NO, and THAT IS A STATED DEVIATION rather than a claim about
	 * Apple's defaults: both are the manager's to draw here (D5/D6), so a YES this tier could not honour would be
	 * the wrong kind of answer. */
	_resizeIncrements = NSMakeSize(1.0, 1.0);
	_contentResizeIncrements = NSMakeSize(1.0, 1.0);
	_aspectRatio = NSMakeSize(0.0, 0.0);
	_contentAspectRatio = NSMakeSize(0.0, 0.0);
	_alphaValue = 1.0;
	_opaque = YES;
	/* THE BACKING TYPE IS KEPT, because Apple's `-backingType` reports what the window was MADE with — which
	 * is the only thing that makes that door checkable rather than a constant. */
	_backing = bufferingType;
	self = [super init];
	if (self == nil) {
		return nil;
	}
	/* THE FRAME IS DERIVED FROM THE CONTENT RECT, which is Apple's contract: the initialiser takes the
	 * CONTENT and the chrome is added by the style mask. */
	_frame = [[self class] frameRectForContentRect:contentRect styleMask:styleMask];
	_styleMask = styleMask;
	_title = nil;
	_cursorRectsEnabled = YES;
	_cursorRectsDirty = YES;
	_delegate = nil;
	_deferred = flag;
	_visible = NO;
	_key = NO;
	_main = NO;
	_agwindow = NULL;
	_cg_events = [[NSMutableArray alloc] init];
	(void)bufferingType;
	return self;
}

- (void)dealloc
{
	/* THE WINDOW GOES, THE QUEUE GOES, AND THE CONNECTION DOES NOT: the connection is the process's (see
	 * `fn_server`), and a window that dropped it would take every other window's events with it. */
	if (_agwindow != NULL) {
		AGWindowDestroy(_agwindow);
		_agwindow = NULL;
	}
	[_cg_events release];
	[_title release];
	[_frameAutosaveName release];
	[_representedFilename release];
	[_representedURL release];
	[_miniwindowTitle release];
	[_miniwindowImage release];
	[_cg_registeredDraggedTypes release];
	[_keyViewLoop release];
	[super dealloc];
}

/* THE WINDOW IS MADE ON DEMAND — see the header's `defer:` note. Every door that needs an X window asks for
 * one here, so the lazy path is one place and the eager callers cannot forget it. */

/* ============================================================================================ *
 * THE CHROME, WHICH THE WINDOW PAINTS ITSELF.                                                    *
 *                                                                                                *
 * CLIENT-SIDE DECORATION (appkit-plan §6 D6): the guest's window manager draws no chrome, so the  *
 * strip above the content is THIS WINDOW's pixels and something has to paint it. Before this it   *
 * was the X window's background — measured on the guest as a white stripe — because the surface   *
 * held the content only and the blit skipped the rows above it.                                   *
 *                                                                                                *
 * **THE TITLE'S TEXT IS STILL NOT DRAWN, AND THE REASON HAS MOVED TWICE.** The original refusal *
 * said this tier "has no font until the text system (stage F)" — true then, and half of it was      *
 * already STALE (it claimed `+windowFrameTextColor` was owed; both ledgers have said `shipped`     *
 * all along). The font arrived (§A10bv/A10bw) and the ink layer with it (§A10bx), so the refusal   *
 * now rests on a MEASURED engine fact instead: this tier's `CTLineDraw` does not honour the         *
 * context's text position, so a title would land at the surface's origin rather than in the        *
 * strip. The site, the measurement and the fix belong to Core Text — see below.                    *
 * ============================================================================================ */
/* **THE TITLE'S APPEARANCE, IN ONE PLACE, FOR THE PAINTER AND THE MEASUREMENT ALIKE.** Apple's title bar font
 * is `+titleBarFontOfSize:0` — zero asking for the standard size — and the text colour is
 * `+windowFrameTextColor`, which THIS TREE ALREADY SHIPPED (`NSColor.h`; both ledgers say `shipped`). The refusal
 * this function's caller used to carry said that colour "stays on the ledger's work list", and that sentence was
 * simply STALE: the colour was done and the font was not. Two callers now read this one dictionary so a window
 * cannot measure a title in one face and paint it in another. */
static NSDictionary *fn_title_attributes(void)
{
	static NSDictionary *attributes = nil;

	if (attributes == nil) {
		NSFont *font = [NSFont titleBarFontOfSize:(CGFloat)0.0];
		NSColor *colour = [NSColor windowFrameTextColor];
		NSMutableDictionary *built;

		/* **A TITLE WITH NO FONT IS NOT DRAWN AT ALL, AND THE COLOUR IS OPTIONAL ON THE SAME GROUND.** The first
		 * version put both objects straight into a varargs constructor, and this tree's dictionary RAISES when a
		 * value is nil ("value must not be nil - use -removeObjectForKey:") — so a host with no font registry made
		 * the whole window probe ABORT rather than draw no title. A missing font means there is nothing to lay out;
		 * a missing colour means the title is drawn in whatever the context's fill colour is. */
		if (font == nil) {
			return nil;
		}
		built = [NSMutableDictionary dictionary];
		[built setObject:font forKey:NSFontAttributeName];
		if (colour != nil) {
			[built setObject:colour forKey:NSForegroundColorAttributeName];
		}
		attributes = [built copy];
	}
	return attributes;
}

/* A TITLE THAT FITS, MEASURED RATHER THAN GUESSED (longest prefix, marked with three periods). */
static NSString *fn_title_that_fits(NSString *title, NSDictionary *attributes, CGFloat available)
{
	NSUInteger i;

	if (attributes == nil || available <= 0.0) {
		return nil;
	}
	if ([title sizeWithAttributes:attributes].width <= available) {
		return title;
	}
	for (i = [title length]; i > 0; i--) {
		NSString *cut = [[title substringToIndex:i] stringByAppendingString:@"..."];

		if ([cut sizeWithAttributes:attributes].width <= available) {
			return cut;
		}
	}
	return nil;
}

/* WHERE A TITLE'S BASELINE GOES: the box is `ascent` above the baseline and `|descent|` below, so centring it in
 * the strip puts the baseline at the strip's bottom plus half the leftover, MINUS the descent. */
static CGFloat fn_title_baseline(NSRect content, CGFloat ascent, CGFloat descent)
{
	return content.size.height + (fn_TITLE_BAR - (ascent - descent)) / 2.0 - descent;
}

static void fn_draw_chrome(CGContextRef c, NSWindow *w, NSRect content)
{
	const CGFloat d = fn_BUTTON;
	CGFloat y = content.size.height + (fn_TITLE_BAR - d) / 2.0;
	CGFloat x = 8.0;
	int i;

	/* THE STRIP FIRST, in the frame colour — the fill that had no author before. */
	CGContextSetFillColorWithColor(c, [[NSColor windowFrameColor] CGColor]);
	CGContextFillRect(c, CGRectMake(0.0, content.size.height, content.size.width, fn_TITLE_BAR));

	/* **AND THE THREE BUTTONS, EACH DRAWN ONLY IF THE STYLE MASK ASKS FOR IT** — close for the closable bit,
	 * miniaturize for the miniaturizable one and zoom for the resizable one, in the order every window manager puts
	 * them and in the colours that order is read by. THE COLOURS ARE OURS, on the same ground the colour's own
	 * header states; the MASK RULE is Apple's, whose scripting reference defines the abilities as the buttons:
	 * "returns YES if the receiver can be miniaturized (has a minimize button)", "is zoomable (has a zoom button)".
	 *
	 * THIS IS A FIX RATHER THAN A NEW BEHAVIOUR: the three dots used to be painted for EVERY window, so a
	 * titled-but-not-closable window showed a close box it did not have. The x advances only for a button that is
	 * actually drawn, so a window with one bit gets one dot at the left edge. */
	for (i = 0; i < 3; i++) {
		static const NSUInteger bits[3] = { NSClosableWindowMask, NSMiniaturizableWindowMask, NSResizableWindowMask };
		CGFloat r, g, b;

		if (([w styleMask] & bits[i]) == 0) {
			continue;
		}
		switch (i) {
		case 0: r = 0.85; g = 0.25; b = 0.20; break;	/* close */
		case 1: r = 0.90; g = 0.75; b = 0.25; break;	/* miniaturize */
		default: r = 0.30; g = 0.80; b = 0.35; break;	/* zoom */
		}
		CGContextSetRGBFillColor(c, r, g, b, 1.0);
		CGContextFillEllipseInRect(c, CGRectMake(x, y, d, d));
		x += d + 8.0;
	}

	/* AND THE EDITED DOT INSIDE THE CLOSE BUTTON — which exists only when there IS a close button. `-isDocumentEdited`'s
	 * own note used to say "a window manager draws this as the dot in the close button" — and under D6 the window IS
	 * the window manager here, so this is where that sentence stops being a promise about somebody else and becomes a
	 * thing this code does. */
	if ([w isDocumentEdited] && ([w styleMask] & NSClosableWindowMask) != 0) {
		CGContextSetRGBFillColor(c, 0.15, 0.15, 0.15, 1.0);
		CGContextFillEllipseInRect(c, CGRectMake(8.0 + d / 4.0, y + d / 4.0, d / 2.0, d / 2.0));
	}

	if (([w styleMask] & NSTitledWindowMask) != 0) {
		NSDictionary *attributes = fn_title_attributes();
		NSFont *font = attributes == nil ? nil : [attributes objectForKey:NSFontAttributeName];
		NSString *title = fn_title_that_fits([w title], attributes, content.size.width - x - 8.0);

		if (title != nil) {
			NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:c flipped:NO];
			NSGraphicsContext *prev = [[NSGraphicsContext currentContext] retain];

			[NSGraphicsContext setCurrentContext:g];
			[title drawAtPoint:NSMakePoint(x, fn_title_baseline(content, [font ascender], [font descender]))
			     withAttributes:attributes];
			[NSGraphicsContext setCurrentContext:prev];
			[prev release];
		}
	}

}

/* **A STATUS ITEM IS A WINDOW WHOSE PLACEMENT IS NOT ITS APPLICATION'S.** Everything else this file does with a
 * frame is "the application said so"; this is the single exception, and it is a KIND of window rather than a
 * frame, because the server is the only thing that can know what else is in the status bar. */
- (void)cg_setStatusItemLength:(CGFloat)length
{
	if (![self cg_ensureWindow]) {
		return;
	}
	AGWindowSetStatusItem(_agwindow, (int)length);
}

- (BOOL)cg_ensureWindow
{
	AGWindowServer *server = fn_server();
	static NSInteger s_nextNumberOfWindow = 1;
	int w, h;

	if (_agwindow != NULL) {
		return YES;
	}
	if (server == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: NSWindow needs a reachable window server; AGWindowServerConnect "
				"answered NULL, so there is no window to make (WAYLAND_DISPLAY is unset or the "
				"compositor is not listening)\n");
		return NO;
	}
	/* **THE POSITION IS NOT THIS CLIENT'S, AND THAT IS THE PROTOCOL RATHER THAN A GAP.** A Wayland client
	 * does not choose where its toplevel goes — the compositor places it — so only the SIZE crosses, and
	 * `-setFrameOrigin:` moves the Cocoa frame without moving the window (the header says so where the
	 * deviation is recorded). */
	w = (int)(_frame.size.width > 0.0 ? _frame.size.width : 0.0);
	h = (int)(_frame.size.height > 0.0 ? _frame.size.height : 0.0);
	if (w == 0 || h == 0) {
		fprintf(stderr, "APPKIT-REFUSE: NSWindow refuses a frame with no area (%gx%g)\n",
			(double)_frame.size.width, (double)_frame.size.height);
		return NO;
	}
	_agwindow = AGWindowCreate(server, w, h, _title != nil ? [_title UTF8String] : NULL);
	if (_agwindow == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: NSWindow could not create a window: %s\n",
			AGWindowServerLastError(server));
		return NO;
	}
	_cg_windowNumber = s_nextNumberOfWindow++;
	AGWindowSetEventHandler(_agwindow, fn_ag_event, self);
	AGWindowSetFrameHandler(_agwindow, fn_ag_frame, self);
	/* **AND THE SERVER IS TOLD THE FRAME IT WAS MADE WITH.** `-initWithContentRect:` sets `_frame` DIRECTLY
	 * rather than through `-setFrame:`, so a window that is never moved afterwards would never have told the
	 * server where it is — MEASURED as a window at the origin however far from it the application had asked.
	 * Telling it here is what makes the frame honoured from the first pixel. */
	{
		CGFloat screen_height = [[NSScreen mainScreen] frame].size.height;

		if (screen_height > 0.0) {
			AGWindowSetFrame(_agwindow, (int)_frame.origin.x,
					 (int)(screen_height - (_frame.origin.y + _frame.size.height)),
					 (int)_frame.size.width, (int)_frame.size.height);
		}
		/* AND THE LEVEL IT WAS GIVEN BEFORE IT EXISTED, for the same reason the frame is told here. */
		AGWindowSetLevel(_agwindow, (int)_level);
	}
	/* **AND IT IS NOT SHOWN HERE.** `-cg_ensureWindow` CREATES and `-orderFront:` SHOWS, and this used to do
	 * both — so a window was shown twice, which is a second commit for no reason and, on a protocol where a
	 * commit carries state, a chance to say the wrong thing twice. */
	return YES;
}


/* THE WAIT THE APPLICATION'S PUMP USES. The connection is this file's — one per process, made on first use —
 * so the application cannot wait on it without asking here, and asking here is what keeps ONE connection
 * rather than two event queues. A millisecond count of 0 is a poll.
 *
 * THE EVENTS LAND IN THE WINDOWS' OWN QUEUES, so what this door answers is "did anything arrive", and the
 * count `s_queued_events` is that answer. */
/* **WHETHER THE COMPOSITOR HAS GONE AWAY, WHICH IS NOT THE SAME THING AS NOTHING HAPPENING.** The seam answers a
 * NEGATIVE from its dispatch when the connection is dead, and this door used to fold that into "no event" — so an
 * application whose window server died SPUN FOR EVER, repainting nothing, refusing every buffer, looking exactly
 * like an application that was merely slow. MEASURED: a live session ran a minute and a half against a compositor
 * that had been killed, and the only clue was a frame counter that had stopped. */
static int s_connection_gone;

+ (BOOL)cg_connectionIsGone
{
	return s_connection_gone ? YES : NO;
}

+ (BOOL)cg_waitForEventInMilliseconds:(long)ms
{
	AGWindowServer *server = fn_server();

	if (server == NULL) {
		return NO;
	}
	if (s_queued_events > 0) {
		return YES;
	}
	if (AGWindowServerDispatchTimeout(server, (int)ms) < 0) {
		s_connection_gone = 1;
		return NO;
	}
	return s_queued_events > 0;
}

- (NSRect)frame
{
	return _frame;
}

/* ---- THE SIZE CONSTRAINTS ------------------------------------------------------------------- */

/* ZERO IS THE ABSENCE OF A BOUND — the derivation is in the header — so the tighter of two lower bounds is the
 * LARGER of them and the tighter of two upper bounds is the SMALLER, with a zero contributing nothing either way.
 * All three are per axis, because a caller may constrain one and not the other. */
static CGFloat fn_lower_bound(CGFloat a, CGFloat b)
{
	if (a <= 0.0) {
		return b;
	}
	if (b <= 0.0) {
		return a;
	}
	return (a > b) ? a : b;
}

static CGFloat fn_upper_bound(CGFloat a, CGFloat b)
{
	if (a <= 0.0) {
		return b;
	}
	if (b <= 0.0) {
		return a;
	}
	return (a < b) ? a : b;
}

static CGFloat fn_clamp_axis(CGFloat v, CGFloat lo, CGFloat hi)
{
	if (lo > 0.0 && v < lo) {
		v = lo;
	}
	if (hi > 0.0 && v > hi) {
		v = hi;
	}
	return v;
}

- (NSSize)minSize
{
	return _minSize;
}

- (void)setMinSize:(NSSize)size
{
	_minSize = size;
}

- (NSSize)maxSize
{
	return _maxSize;
}

- (void)setMaxSize:(NSSize)size
{
	_maxSize = size;
}

- (NSSize)contentMinSize
{
	return _contentMinSize;
}

- (void)setContentMinSize:(NSSize)size
{
	_contentMinSize = size;
}

- (NSSize)contentMaxSize
{
	return _contentMaxSize;
}

- (void)setContentMaxSize:(NSSize)size
{
	_contentMaxSize = size;
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag
{
	/* **THE CONSTRAINTS, APPLIED WHERE EVERY FRAME SET ENDS UP.** A content constraint is converted through this
	 * window's own chrome arithmetic — which is the only thing that relates the two questions — and an axis whose
	 * content bound is zero contributes NOTHING, because converting a zero content size still yields the chrome's
	 * own thickness and would otherwise impose a minimum nobody asked for. The conversion happens once, below,
	 * rather than per axis, because the two axes of one rect come from one call. */
	{
		NSRect contentMinFrame = [self frameRectForContentRect:NSMakeRect(0.0, 0.0, _contentMinSize.width, _contentMinSize.height)];
		NSRect contentMaxFrame = [self frameRectForContentRect:NSMakeRect(0.0, 0.0, _contentMaxSize.width, _contentMaxSize.height)];
		CGFloat loW = fn_lower_bound(_minSize.width, (_contentMinSize.width > 0.0) ? contentMinFrame.size.width : 0.0);
		CGFloat loH = fn_lower_bound(_minSize.height, (_contentMinSize.height > 0.0) ? contentMinFrame.size.height : 0.0);
		CGFloat hiW = fn_upper_bound(_maxSize.width, (_contentMaxSize.width > 0.0) ? contentMaxFrame.size.width : 0.0);
		CGFloat hiH = fn_upper_bound(_maxSize.height, (_contentMaxSize.height > 0.0) ? contentMaxFrame.size.height : 0.0);

		frameRect.size.width = fn_clamp_axis(frameRect.size.width, loW, hiW);
		frameRect.size.height = fn_clamp_axis(frameRect.size.height, loH, hiH);
	}
	/* **THE TWO ANNOUNCEMENTS ARE DECIDED BY WHAT ACTUALLY CHANGED, NOT BY THE DOOR THAT WAS USED.** A frame set
	 * that moves a window without resizing it is a MOVE, and one that resizes without moving is a RESIZE — and a
	 * delegate that acts on either would be told the wrong thing by a door that announced both unconditionally.
	 * `-windowWillResize:toSize:` is NOT sent here: it is the question the user's drag asks, and a programmatic
	 * frame set is not a drag. */
	BOOL moved = (frameRect.origin.x != _frame.origin.x || frameRect.origin.y != _frame.origin.y);
	BOOL resized = (frameRect.size.width != _frame.size.width || frameRect.size.height != _frame.size.height);
	/* The children move by the DELTA this set applied, so the old origin is kept before `_frame` below takes
	 * the new one. */
	NSPoint previousOrigin = _frame.origin;

	if (moved) {
		fn_announce(self, NSWindowWillMoveNotification, @selector(windowWillMove:));
	}
	_frame = frameRect;
	/* **THERE IS NO `XMoveResizeWindow` BEHIND THIS DOOR ANY MORE.** A Wayland client neither places nor
	 * moves its toplevel; what a client CAN do is attach a frame of the new size, and the next `-display`
	 * does exactly that, because `cg_ensureSurface` remakes the backing store when the frame's size has
	 * changed. The Cocoa frame is updated either way — it is this object's own geometry, and the chrome
	 * arithmetic above is written in its terms. */
	(void)flag;
	/* **AND THE SERVER IS TOLD, WHICH IS WHAT `-setFrame:` MEANS ON A COMPOSITOR THAT CAN BE TOLD.** The Mac's
	 * model is that the application states a frame and the window server honours it; a stock compositor speaking
	 * only `xdg-shell` cannot be told where a window goes, and the seam records the frame and places nothing —
	 * which is a property of the compositor and not of this door. The y is flipped because a display measures
	 * down from the top and Cocoa measures up from the bottom. */
	if (_agwindow != NULL) {
		CGFloat screen_height = [[NSScreen mainScreen] frame].size.height;

		if (screen_height > 0.0) {
			AGWindowSetFrame(_agwindow, (int)_frame.origin.x,
					 (int)(screen_height - (_frame.origin.y + _frame.size.height)),
					 (int)_frame.size.width, (int)_frame.size.height);
		}
	}
	if (moved) {
		/* **AND THE CHILDREN FOLLOW** — Apple's sentence: "moving the window will cause childWin to move". The same
		 * DELTA, so the attachment keeps its relative position without this file storing one; and a child with
		 * children of its own propagates it through this same door, which TERMINATES because the attachment
		 * refuses a cycle where it is made. The converse — "moving childWin will not cause the window to move" —
		 * is why nothing of the sort appears in a child's own frame set. */
		NSUInteger i;

		for (i = 0; i < [_cg_childWindows count]; i++) {
			NSWindow *child = [_cg_childWindows objectAtIndex:i];
			NSRect childFrame = [child frame];

			childFrame.origin.x += frameRect.origin.x - previousOrigin.x;
			childFrame.origin.y += frameRect.origin.y - previousOrigin.y;
			[child setFrame:childFrame display:YES];
		}
		fn_announce(self, NSWindowDidMoveNotification, @selector(windowDidMove:));
	}
	if (resized) {
		fn_announce(self, NSWindowDidResizeNotification, @selector(windowDidResize:));
	}
	(void)flag;
}

- (void)setFrameOrigin:(NSPoint)aPoint
{
	[self setFrame:NSMakeRect(aPoint.x, aPoint.y, _frame.size.width, _frame.size.height) display:YES];
}

- (void)setContentSize:(NSSize)aSize
{
	NSRect content = [self contentRectForFrameRect:_frame];
	NSRect frame;

	content.size = aSize;
	frame = [self frameRectForContentRect:content];
	/* THE CONTENT'S ORIGIN IS WHAT STAYS PUT, which is Apple's contract: resizing a window grows it from its
	 * bottom-left corner rather than moving that corner. */
	[self setFrame:frame display:YES];
}

- (NSUInteger)styleMask
{
	return _styleMask;
}

- (NSString *)title
{
	return _title;
}

- (void)setTitle:(NSString *)aString
{
	NSString *copy = [aString copy];

	[_title release];
	_title = copy;
	if (_agwindow != NULL && _title != nil) {
		AGWindowSetTitle(_agwindow, [_title UTF8String]);
	}
}

- (id)delegate
{
	return _delegate;
}

- (void)setDelegate:(id)anObject
{
	/* NOT RETAINED, which is Apple's contract for a delegate and the same choice this tree's NSPasteboard
	 * makes for its owner: a window that retained its delegate would keep a controller alive forever. */
	_delegate = anObject;
}

/* THE WINDOW'S NUMBER IS ASSIGNED WHEN ITS WINDOW IS MADE, and -1 before that — which is Apple's own answer
 * for a window that has no number. It is a small per-process ordinal rather than the server's handle now:
 * a Wayland client is given no window id, and the number only has to be stable and unique within the process
 * for `-windowWithWindowNumber:` to dispatch by it. */
- (NSInteger)windowNumber
{
	return _agwindow == NULL ? -1 : _cg_windowNumber;
}

- (BOOL)isVisible
{
	return _visible;
}

- (BOOL)isKeyWindow
{
	return _key;
}

- (BOOL)isMainWindow
{
	return _main;
}

/* ---- THE CHILD WINDOWS ---------------------------------------------------------------------- */

/* SEE THE HEADER FOR THE TWO SENTENCES THIS IMPLEMENTS AND FOR WHAT IS DELIBERATELY NOT HERE. What this file needs
 * of the foundation is one array and one unretained back-reference, both declared with the window's other state. */

/* ---- THE WINDOW-NUMBER DOORS ------------------------------------------------------------------ */

/* SEE THE HEADER FOR APPLE'S PROSE AND FOR THE ONE HALF THIS TIER DOES NOT DO (the cross-application answers both
 * doors' documentation allows). What is here is the half that is THIS application's, and it is built on the same
 * two facts the registry itself rests on: a window number IS the X window id (so the numbers these doors answer are
 * the ones `-windowNumber` answers), and the registry is FRONT-FIRST. */

+ (NSArray *)windowNumbersWithOptions:(NSWindowNumberListOptions)options
{
	NSApplication *app = [NSApplication sharedApplication];
	NSArray *windows = [app windows];
	NSMutableArray *out = [NSMutableArray array];
	NSUInteger i;

	(void)options;	/* accepted and not honoured — see the header for why it cannot widen here */
	for (i = 0; i < [windows count]; i++) {
		NSWindow *w = [windows objectAtIndex:i];

		/* VISIBLE IS THE ONE WORD APPLE'S PROSE USES FOR THE DEFAULT, and in this tier a window is visible when it
		 * has been ordered in: an ordered-out window keeps its number (that is what ordering out means here) but it
		 * is not something a caller looking for "the windows on the screen" wants back. */
		if ([w isVisible]) {
			[out addObject:[NSNumber numberWithInteger:(NSInteger)[w windowNumber]]];
		}
	}
	return out;
}

+ (NSInteger)windowNumberAtPoint:(NSPoint)point belowWindowWithWindowNumber:(NSInteger)windowNumber
{
	NSApplication *app = [NSApplication sharedApplication];
	NSArray *windows = [app windows];
	NSUInteger i;
	BOOL below = (windowNumber == 0);	/* 0 excludes nothing, which is Apple's own instruction */

	for (i = 0; i < [windows count]; i++) {
		NSWindow *w = [windows objectAtIndex:i];
		NSRect f;

		if (!below) {
			/* THE EXCLUSION IS THE WINDOW ITSELF AND EVERYTHING ABOVE IT, and the registry's front-first order
			 * is what makes "everything above it" mean "everything already passed". */
			if ((NSInteger)[w windowNumber] == windowNumber) {
				below = YES;
			}
			continue;
		}
		/* AND A WINDOW THAT IGNORES MOUSE EVENTS IS NOT HIT, which is Apple's own sentence about this door: "windows
		 * with transparency at the given point, and windows that ignore mouse events, will not be returned." */
		if (![w isVisible] || [w ignoresMouseEvents]) {
			continue;
		}
		f = [w frame];
		if (point.x >= f.origin.x && point.x < (f.origin.x + f.size.width) &&
		    point.y >= f.origin.y && point.y < (f.origin.y + f.size.height)) {
			return (NSInteger)[w windowNumber];
		}
	}
	return 0;	/* NOTHING WAS HIT — 0, with the reason the header states. */
}

- (void)cg_setParentWindow:(NSWindow *)parent
{
	/* THE PRIVATE HALF: it records and nothing else. The public `-setParentWindow:` takes the child's side of the
	 * relationship and would call back into `-addChildWindow:ordered:` on the other window — which is right for a
	 * caller and wrong for the parent's own bookkeeping. */
	_cg_parentWindow = parent;
}

- (void)addChildWindow:(NSWindow *)childWin ordered:(NSWindowOrderingMode)place
{
	NSWindow *up;

	if (childWin == nil || childWin == self) {
		/* Nothing to attach, and a window attached to ITSELF is the shortest cycle there is. */
		return;
	}
	/* THE CYCLE CHECK: this window's ancestors are walked, because a cycle of ANY length is endless here — every
	 * later move would propagate through it forever. Apple's own page warns about the two-window case; the walk
	 * catches the long one too. */
	for (up = self; up != nil; up = [up parentWindow]) {
		if (up == childWin) {
			[NSException raise:NSInvalidArgumentException
				    format:@"-addChildWindow:ordered: — %@ is already an ancestor of %@, and a child "
					   @"relationship between them would make every later move endless",
				    childWin, self];
		}
	}
	/* A WINDOW HAS ONE PARENT: one coming from somewhere else leaves that parent first, which is also what makes
	 * this door the way a child is MOVED rather than duplicated. */
	if ([childWin parentWindow] != nil) {
		[[childWin parentWindow] removeChildWindow:childWin];
	}
	if (_cg_childWindows == nil) {
		_cg_childWindows = [[NSMutableArray alloc] init];
	}
	if (![_cg_childWindows containsObject:childWin]) {
		[_cg_childWindows addObject:childWin];
	}
	[childWin cg_setParentWindow:self];
	/* AND THE CHILD IS ORDERED RELATIVE TO THE WINDOW IT WAS GIVEN TO, which is what `place` names. `NSWindowOut`
	 * is not an ordering relative to anything, so a caller that passes it gets the attachment without the
	 * ordering — stated rather than mapped to a guess about what they meant. */
	if (place != NSWindowOut) {
		[childWin orderWindow:place relativeTo:(NSInteger)[self windowNumber]];
	}
}

- (void)removeChildWindow:(NSWindow *)childWin
{
	if (childWin == nil || _cg_childWindows == nil) {
		/* REMOVING A WINDOW THAT IS NOT A CHILD IS NOT AN ERROR, for the reason ending a modal session that is
		 * not running is not one: a caller unwinding from a failure detaches things it is not sure it attached. */
		return;
	}
	if ([_cg_childWindows containsObject:childWin]) {
		[childWin cg_setParentWindow:nil];
		[_cg_childWindows removeObject:childWin];
	}
}

- (NSArray *)childWindows
{
	/* A COPY, so a caller cannot mutate the relationship by holding onto the answer — and nil when there are none,
	 * which reads as empty to anyone iterating it. */
	return [[_cg_childWindows copy] autorelease];
}

- (NSWindow *)parentWindow
{
	return _cg_parentWindow;
}

- (void)setParentWindow:(NSWindow *)window
{
	if (window == nil) {
		/* THE DETACHING HALF: expressed from the child's side, it is still the parent that owns the list. */
		[_cg_parentWindow removeChildWindow:self];
		return;
	}
	[window addChildWindow:self ordered:NSWindowAbove];
}

/* ORDERING. `-orderFront:` makes the window visible and `-orderOut:` takes it off the screen WITHOUT
 * destroying it — the distinction that makes a window reusable, and the reason `-close` is a separate door. */
- (void)orderFront:(id)sender
{
	(void)sender;
	if (![self cg_ensureWindow]) {
		return;
	}
	AGWindowShow(_agwindow);
	_visible = YES;
	/* A WINDOW THAT IS ON THE SCREEN IS ONE THE RUN LOOP MUST DRAIN, so it joins the registry here
	 * rather than being polled for: the loop has no way to ask a server which windows are ours. */
	[[NSApplication sharedApplication] cg_addWindow:self];

	/* **AND THE INITIAL FIRST RESPONDER IS MADE THE FIRST RESPONDER HERE, ONCE.** Apple's door promises "the first
	 * time the window is placed onscreen", so this happens on the first order-front and never again: a caller that
	 * has since focused something else must not have that undone by re-ordering the window in. */
	if (!_cg_placedOnscreen) {
		_cg_placedOnscreen = YES;
		if (_initialFirstResponder != nil) {
			[self makeFirstResponder:_initialFirstResponder];
		}
	}
}

- (void)orderOut:(id)sender
{
	/* **ORDERING A CHILD OUT DETACHES IT** — Apple's own sentence about this door, quoted in the header: "Calling
	 * orderOut: on a child window causes the window to be removed from its parent window before being removed."
	 * The detach comes FIRST, because the parent's list must not keep a window that is no longer on the screen as
	 * its child: the next move of the parent would drag a window the caller has just hidden. */
	if (_cg_parentWindow != nil) {
		[_cg_parentWindow removeChildWindow:self];
	}
	(void)sender;
	/* **AND THE SCREEN CHANGES TOO, WHICH IT DID NOT BEFORE.** The comment here used to say that `xdg-shell` has no
	 * unmap — a toplevel is on the screen or it is destroyed — and that was true and is no longer the whole story:
	 * AGORA'S OWN PROTOCOL HAS THE DOOR, so a window that is ordered out is TAKEN OFF THE GLASS. MEASURED, before
	 * this: closing a menu left its panel painted, every menu ever opened was still there, and the run loop was
	 * repainting the whole stack every pass — which is what "the menus never close" and "it gets slower and slower"
	 * both were. */
	_visible = NO;
	if (_agwindow != NULL) {
		AGWindowHide(_agwindow);
	}
}

/* THE ORDERING MODE IS THE RELATIVE ONE, and X has no `relativeTo` for a bare map: this tree runs one
 * window per application today (a window manager is Kestrel's, and it is parked), so `-orderWindow:` is
 * honoured as a make-visible-or-not and the ARGUMENT is recorded rather than silently dropped. */
- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin
{
	if (place == NSWindowOut) {
		[self orderOut:nil];
		return;
	}
	[self orderFront:nil];
	(void)otherWin;
}

- (void)makeKeyAndOrderFront:(id)sender
{
	[self orderFront:sender];
	[self makeKeyWindow];
}

/* **WHY A WINDOW MAY BECOME KEY OR MAIN, and the defaults are Appel's documentation — see the header, where the
 * two rules are quoted and where the one condition this tree cannot test is named. The test for both is the same
 * pair of style mask bits: a TITLE BAR or a RESIZE MECHANISM. */
- (BOOL)canBecomeKeyWindow
{
	return ((_styleMask & NSTitledWindowMask) != 0 || (_styleMask & NSResizableWindowMask) != 0);
}

- (NSWindowCollectionBehavior)collectionBehavior
{
	return _cg_collectionBehavior;
}

- (void)setCollectionBehavior:(NSWindowCollectionBehavior)behavior
{
	/* RECORDED, NOT ACTED — see the header. The request is kept because the window manager that honours Cocoa's
	 * frames (D5's) is what would read it, and dropping a caller's request on the floor would leave a ported
	 * application with no way to state it at all. */
	_cg_collectionBehavior = behavior;
}

- (NSWindowSharingType)sharingType
{
	/* THE TRUTH ABOUT THIS WINDOW, not a stored preference: the content sits in an X window, so any client that
	 * can reach the display can read it — which is Apple's `NSWindowSharingReadOnly`. */
	return NSWindowSharingReadOnly;
}

- (void)setSharingType:(NSWindowSharingType)type
{
	if (type == NSWindowSharingReadOnly) {
		/* ALREADY THE STATE: asking for what is true is not an error. */
		_cg_sharingType = type;
		return;
	}
	/* THE OTHER TWO ARE REFUSED BY NAME, because recording them would record a control this tier does not have:
	 * X has no per-window sharing attribute, so neither "nobody may capture this" nor "others may draw in it" can
	 * be granted or denied from here. */
	[NSException raise:NSInvalidArgumentException
		    format:@"-setSharingType: cannot make a window %@: window content in this tier lives in an X "
			   @"window, and X has no per-window sharing attribute — so NSWindowSharingNone would be a privacy "
			   @"control that does not exist, and NSWindowSharingReadWrite a grant this tier cannot issue",
		    (type == NSWindowSharingNone) ? @"NSWindowSharingNone" : @"NSWindowSharingReadWrite"];
}

- (BOOL)canBecomeMainWindow
{
	/* THE VISIBILITY CLAUSE IS THE MAIN RULE'S OWN, and it is the difference between the two doors: a window that
	 * is not on the screen can still be asked to take the key (making it key is how it gets there), but it cannot
	 * become the MAIN window, which is a state about what the user is looking at. */
	return ([self isVisible] && ((_styleMask & NSTitledWindowMask) != 0 || (_styleMask & NSResizableWindowMask) != 0));
}

- (void)makeKeyWindow
{
	/* **APPLE'S SENTENCE, AND THE ONE BEHAVIOUR THIS UNIT CHANGES**: "Attempts to make the window the key window
	 * are abandoned if the value of this property is false." A borderless window therefore does NOT become key here
	 * — the request is dropped, silently, which is what Apple's own implementation does (it logs a warning this
	 * tree has no channel for). */
	if (![self canBecomeKeyWindow]) {
		return;
	}
	/* AND APPLE'S OWN ROUTE: making a window key IS it becoming key, so this calls the door that announces it
	 * rather than setting the same ivar a second way. */
	[self becomeKeyWindow];
}

- (void)makeMainWindow
{
	if (![self canBecomeMainWindow]) {
		return;
	}
	[self becomeMainWindow];
}

- (void)resignKeyWindow
{
	/* A WINDOW THAT WAS NOT KEY DOES NOT RESIGN, and so does not announce: a notification for a change that
	 * did not happen is worse than none, because a callback acts on it. */
	if (!_key) {
		return;
	}
	_key = NO;
	/* **AND THE TRACKING IS RE-EVALUATED, WHICH IS THE WHOLE REASON THE SCOPE BITS ARE WORTH HAVING.** Every area
	 * whose scope is `NSTrackingActiveInKeyWindow` — which is the default, and what every control in this tree installs
	 * — has just stopped being live, so a control the pointer is resting on gives up its prelight the moment its window
	 * stops being the key one. NO MOTION EVENT IS COMING to say so: the pointer has not moved, and the fact that
	 * changed is the WINDOW's. Re-running the engine at the pointer's last known position is what turns that into the
	 * exits the owners are owed. */
	[self cg_updateTrackingForPoint:[self mouseLocationOutsideOfEventStream]];
	fn_announce(self, NSWindowDidResignKeyNotification, @selector(windowDidResignKey:));
}

- (void)close
{
	/* THE DELEGATE IS TOLD BEFORE THE WINDOW GOES**, which is the whole point of a `will` callback: after it, the
	 * window is gone and the numbers are meaningless. */
	fn_announce(self, NSWindowWillCloseNotification, @selector(windowWillClose:));
	/* THE FRAME IS SAVED ON THE WAY OUT when the window has an autosave name — Apple's behaviour, and the only
	 * moment a window's place is remembered without the caller asking. It happens BEFORE the X window goes, so
	 * the frame saved is the one the window had while it was still a window. */
	if (_frameAutosaveName != nil) {
		[self saveFrameUsingName:_frameAutosaveName];
	}
	/* **CLOSING DESTROYS THE WINDOW, WHICH IS THE ONE THING `xdg-shell` DOES OFFER.** A later `-orderFront:`
	 * makes a NEW one — which is what a closed window being re-shown means here. The queued events go with it:
	 * they name a window that no longer exists. */
	if (_agwindow != NULL) {
		AGWindowDestroy(_agwindow);
		_agwindow = NULL;
	}
	s_queued_events -= (NSInteger)[_cg_events count];
	[_cg_events removeAllObjects];
	/* AND A CLOSED WINDOW LEAVES IT, so the loop stops asking a window with no window for events. */
	[[NSApplication sharedApplication] cg_removeWindow:self];
	/* AND THE APPLICATION IS TOLD, because ONE question is about the LAST window: a delegate may say that closing
	 * it should end the application too, and only the application knows how many are left. */
	[[NSApplication sharedApplication] cg_windowClosed:self];
	_cg_windowNumber = -1;
	_visible = NO;
	_key = NO;
	_main = NO;
}

/* CENTRED ON THE SCREEN, in COCOA's coordinates: the frame's own size is kept and its lower-left corner is
 * placed so that the frame is centred in the screen's rectangle. */
- (void)center
{
	AGWindowServer *server = fn_server();
	int sh = 0, sw = 0;

	if (server == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: -center needs a reachable window server to measure the screen with\n");
		return;
	}
	AGWindowServerScreenSize(server, &sw, &sh, NULL);
	if (sw <= 0 || sh <= 0) {
		/* NO OUTPUT HAS DESCRIBED ITSELF YET: there is nothing to centre in, and inventing a size would place
		 * the frame somewhere plausible and wrong. */
		fprintf(stderr, "APPKIT-REFUSE: -center has no screen size from the compositor yet\n");
		return;
	}
	[self setFrame:NSMakeRect((sw - _frame.size.width) / 2.0,
				  (sh - _frame.size.height) / 2.0,
				  _frame.size.width, _frame.size.height)
	       display:YES];
}


/* ---- THE CONTENT VIEW AND THE RESPONDER ---------------------------------------------------- */

- (NSView *)contentView
{
	return _contentView;
}

- (void)setContentView:(NSView *)aView
{
	if (aView == _contentView) {
		return;
	}
	[aView retain];
	[_contentView release];
	_contentView = aView;
	/* THE VIEW IS LAID OUT IN THE CONTENT RECT, which is what makes a titled window's content view sit
	 * BELOW the title bar rather than behind it. */
	if (_contentView != nil) {
		[_contentView setFrame:[self contentRectForFrameRect:_frame]];
		/* **AND THE VIEW LEARNS WHICH WINDOW IT IS IN.** `-addSubview:` gives a subtree its window, and a window
		 * adopting a content view is the other way a view arrives in one — WITHOUT THIS, a content view's whole
		 * subtree answered `-window` with nil, which is a gap the key-view walk found: `-previousKeyView` starts at
		 * the window's content view and had nothing to start from. */
		[_contentView cg_setWindow:self];
	}
	/* AND A WINDOW WITH A CONTENT VIEW ALWAYS HAS SOMEWHERE FOR A KEY TO GO, which is why installing one
	 * makes it the first responder unless something else already is. */
	if (_firstResponder == nil && _contentView != nil) {
		_firstResponder = _contentView;
	}
}

- (NSResponder *)firstResponder
{
	return _firstResponder;
}

/* **THE WINDOW'S SUCCESSOR IS THE APPLICATION**, which is where Apple's chain ends and where
 * `-targetForAction:`'s walk expects to arrive (NSApplication.m's own comment says so). A caller that has put
 * something in between — a window controller, say — keeps it, because an explicit link wins. */
- (NSResponder *)nextResponder
{
	NSResponder *explicit = [super nextResponder];

	return explicit != nil ? explicit : (NSResponder *)[NSApplication sharedApplication];
}

- (BOOL)makeFirstResponder:(NSResponder *)aResponder
{
	/* A NIL RESPONDER IS ACCEPTED AND MEANS "NOBODY", which is Apple's contract (a window whose field
	 * editor is going away clears it) — so this answers YES for nil rather than refusing it.
	 *
	 * **AND THE RESPONDER IS LINKED INTO THE CHAIN, WHICH IS NOT BOOKKEEPING.** `NSResponder` IMPLEMENTS
	 * `-mouseDown:` and friends — its implementation FORWARDS to `-nextResponder` (that is what stage A's
	 * class is for) — so a responder whose `-nextResponder` is nil SWALLOWS every event it is sent: the
	 * forward goes nowhere and the content view below it never hears about the click. MEASURED: this is
	 * exactly what happened, and the diagnostic was a click the app pumped, dispatched and then lost —
	 * `sendEvent returned; stopped=0`. Linking the first responder to the CONTENT VIEW is what makes the
	 * chain reach the view, and through it the window and the application. */
	_firstResponder = aResponder;
	/* A DIRECT SELECTION IS NOT A TRAVERSAL: Apple's `NSDirectSelection` means the window is not using the key view
	 * loop, which is exactly what a caller naming the responder has done. The four traversal doors set this back to
	 * the direction they moved in AFTER the selection, so a `-becomeFirstResponder` reached through Tab is told
	 * which way it arrived. */
	_keyViewSelectionDirection = NSDirectSelection;
	/* **AND NOTHING IS LINKED HERE ANY MORE, BECAUSE THE CHAIN IS REAL NOW.** This door used to set the
	 * responder's successor to the CONTENT VIEW, which was a workaround for `NSView` never wiring
	 * `-nextResponder` at all (see that method): with the successor unset, NSResponder's forwarding methods
	 * had nowhere to go and the click was lost. Linking straight to the content view made the click arrive,
	 * but SKIPPED EVERY ANCESTOR between the responder and the content view — so an intermediate view could
	 * never hear an event its descendant did not handle. `-nextResponder` is computed now, so the walk is the
	 * real one and there is nothing to patch up. */
	return YES;
}

- (void)setAcceptsMouseMovedEvents:(BOOL)flag
{
	_acceptsMouseMoved = flag;
}

- (BOOL)acceptsMouseMovedEvents
{
	return _acceptsMouseMoved;
}

/* THE CLICK COUNT'S TWO HALVES, private because they are this file's derivation of a number X does not
 * send. `cg_clickCountFor:at:` is called on a press and answers the count that press belongs to. */
- (NSInteger)cg_clickCountFor:(NSPoint)p at:(NSTimeInterval)now
{
	CGFloat dx = p.x - _lastClick.x;
	CGFloat dy = p.y - _lastClick.y;

	if (now - _lastClickTime <= APPKIT_DOUBLE_CLICK_SECONDS &&
	    dx * dx + dy * dy <= APPKIT_CLICK_SLOP * APPKIT_CLICK_SLOP) {
		_clickCount++;
	} else {
		_clickCount = 1;
	}
	_lastClick = p;
	_lastClickTime = now;
	return _clickCount;
}

- (NSInteger)currentClickCount
{
	return _clickCount;
}

/* ---- THE EVENT PUMP ------------------------------------------------------------------------ */

/* THE FIRST QUEUED EVENT THIS WINDOW'S MASK WANTS, or NULL when there is none to be had. THE QUEUE IS FILLED
 * BY THE SEAM'S HANDLER, so this door is a POP rather than a read from a socket — and the ordering the old
 * `XPeekEvent`/`XNextEvent` pair existed to preserve is now just "index into an array".
 *
 * THE MASK DECIDES WHAT MAY BE TAKEN, and an event it did not ask for STAYS for the next call, which is
 * Apple's contract. `wait` decides whether to block for one: the timed form passes the milliseconds left, so a
 * deadline is kept and this door can return with nothing to show. There is no Expose to handle, because the
 * client owns the pixels and the compositor asks for a frame through the frame handler instead. */
- (NSEvent *)cg_nextEventWaiting:(BOOL)wait milliseconds:(long)ms mask:(NSUInteger)mask
				dequeue:(BOOL)dequeue
{
	AGWindowServer *server = fn_server();
	NSTimeInterval deadline = -1.0;

	if (server == NULL || _agwindow == NULL) {
		return nil;
	}
	/* A CLOSE THE COMPOSITOR ASKED FOR IS ACTED ON HERE rather than inside the dispatch that heard it, and this
	 * is outside the dispatch: `-close` destroys the window, and destroying it while libwayland is still walking
	 * that window's own listeners is a use-after-free. */
	if (_cg_closeRequested) {
		_cg_closeRequested = NO;
		[self close];
		return nil;
	}
	if (ms >= 0) {
		deadline = [NSDate timeIntervalSinceReferenceDate] + (NSTimeInterval)ms / 1000.0;
	}
	for (;;) {
		NSUInteger i, count = [_cg_events count];

		for (i = 0; i < count; i++) {
			NSEvent *ev = [_cg_events objectAtIndex:i];
			NSUInteger t = (NSUInteger)1 << [ev type];

			if (!(mask & NSAnyEventMask) && !(mask & t)) {
				continue;
			}
			/* NOT DEQUEUING MEANS NOT TAKING: the caller is LOOKING, and the app-level drain polls every
			 * window this way — taking the event would eat the very one it is testing for. */
			if (!dequeue) {
				return ev;
			}
			[ev retain];
			[_cg_events removeObjectAtIndex:i];
			s_queued_events--;
			return [ev autorelease];
		}
		if (!wait) {
			return nil;
		}
		{
			int timeout = -1;

			if (deadline >= 0.0) {
				timeout = (int)((deadline - [NSDate timeIntervalSinceReferenceDate]) * 1000.0);
				if (timeout < 0) {
					return nil;	/* THE DATE PASSED with nothing matching, which the timed form reports as none. */
				}
			}
			if (AGWindowServerDispatchTimeout(server, timeout) < 0) {
				return nil;
			}
		}
	}
}

- (NSEvent *)nextEventMatchingMask:(NSUInteger)mask
{
	/* THE BLOCKING FORM: no deadline, so the wait has none either. */
	return [self cg_nextEventWaiting:YES milliseconds:-1 mask:mask dequeue:YES];
}

- (NSEvent *)nextEventMatchingMask:(NSUInteger)mask
			 untilDate:(NSDate *)expiration
			    inMode:(NSString *)mode
			   dequeue:(BOOL)deqFlag
{
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	long ms = -1;

	(void)mode;
	if (expiration != nil) {
		double left = [expiration timeIntervalSinceReferenceDate] - now;

		if (left <= 0.0) {
			/* A DATE ALREADY PAST IS A POLL, which is what makes this form usable inside a run loop. */
			return [self cg_nextEventWaiting:NO milliseconds:0 mask:mask dequeue:deqFlag];
		}
		ms = (long)(left * 1000.0);
	}
	/* `dequeue:` IS HONOURED IN BOTH DIRECTIONS: NO means "look without taking", which is the peer the pump
	 * leaves for the next call. */
	if (!deqFlag) {
		return [self cg_nextEventWaiting:NO milliseconds:ms >= 0 ? ms : 0 mask:mask dequeue:NO];
	}
	return [self cg_nextEventWaiting:YES milliseconds:ms mask:mask dequeue:deqFlag];
}

/* THE DISPATCH, AND IT IS THE RESPONDER CHAIN'S FIRST LINK: the event goes to the FIRST RESPONDER when that
 * responder handles this kind of event, and to the CONTENT VIEW otherwise. The selector is chosen by TYPE
 * because that is what a responder implements — `mouseDown:`, `keyDown:`, `flagsChanged:` — and a responder
 * that does not implement one is skipped rather than sent a message it cannot answer. */
- (void)sendEvent:(NSEvent *)theEvent
{
	SEL sel = NULL;
	id target;
	BOOL mouse = NO;

	switch ([theEvent type]) {
	case NSLeftMouseDown:      sel = @selector(mouseDown:); mouse = YES; break;
	case NSLeftMouseUp:        sel = @selector(mouseUp:); mouse = YES; break;
	case NSLeftMouseDragged:   sel = @selector(mouseDragged:); mouse = YES; break;
	case NSRightMouseDown:     sel = @selector(rightMouseDown:); mouse = YES; break;
	case NSRightMouseUp:       sel = @selector(rightMouseUp:); mouse = YES; break;
	case NSRightMouseDragged:  sel = @selector(rightMouseDragged:); mouse = YES; break;
	case NSOtherMouseDown:     sel = @selector(otherMouseDown:); mouse = YES; break;
	case NSOtherMouseUp:       sel = @selector(otherMouseUp:); mouse = YES; break;
	case NSOtherMouseDragged:  sel = @selector(otherMouseDragged:); mouse = YES; break;
	case NSMouseMoved:         sel = @selector(mouseMoved:); mouse = YES; break;
	case NSKeyDown:            sel = @selector(keyDown:); break;
	case NSKeyUp:              sel = @selector(keyUp:); break;
	case NSFlagsChanged:       sel = @selector(flagsChanged:); break;
	default:                   break;
	}
	if (sel == NULL) {
		return;
	}
	if (mouse) {
		/* **THE VIEW UNDER THE POINTER, WHICH IS WHAT `-hitTest:` IS FOR, AND WHAT THIS DOOR DID NOT DO.**
		 * Every mouse event went to the FIRST RESPONDER, so a click on a control inside a subview never
		 * reached the subview unless the subview happened to be the first responder — a control you could
		 * see and not press. Apple's rule is the deepest view containing the point, which is exactly
		 * `NSView`'s own `-hitTest:`; and a view that does not implement the selector still gets it, because
		 * `NSResponder` implements every one of them as a FORWARD to the next responder — which is how a
		 * click on a plain subview walks up to the content view and the window by itself. */
		target = [_contentView hitTest:[theEvent locationInWindow]];
		if (target == nil) {
			/* A point outside the content — the window's own chrome — is this window's business. */
			target = _contentView;
		}
		/* **AND THE TRACKING ENGINE RUNS FROM THE SAME ANSWER, which is why it is here and not in a second walk.** Every
		 * mouse event already names the deepest view containing the point, so a re-evaluation here keeps an enter/exit
		 * correct for a press that arrived without a motion — a click after the window appeared under the pointer. The
		 * engine does its OWN walk (an area belongs to a region and an owner, not to the deepest view), so this is a
		 * second traversal for the same event; it is idempotent and the alternative is a press that reports a pointer
		 * position the tracking state disagrees with. */
		[self cg_updateTrackingForPoint:[theEvent locationInWindow]];
	} else {
		/* A KEY GOES TO THE FIRST RESPONDER, and nowhere else: that is what the first responder means. */
		target = _firstResponder;
		if (target == nil) {
			target = _contentView;
		}
	}
	if (target != nil && [target respondsToSelector:sel]) {
		[target performSelector:sel withObject:theEvent];
	}
}

/* ============================================================================================ *
 * THE TRACKING ENGINE.                                                                          *
 *                                                                                                *
 * **IT IS A WALK, AND THE WALK IS THE DESIGN.** An `NSTrackingArea` names a rectangle in a         *
 * VIEW's coordinates and an OWNER who wants to hear about it, and the window is what knows where   *
 * that view currently sits, whether the window is key, and whether a button is held — so the       *
 * engine RE-DERIVES the whole picture on every motion instead of keeping a registry of live       *
 * regions that would go stale the moment anything moved. The only state it keeps is ONE BIT PER    *
 * AREA (is the pointer inside it right now, and that bit lives on the area); the rectangle, the     *
 * owner and the options are the area's, and the pointer's path is not remembered at all.           *
 * ============================================================================================ */

/* **THE WALK, TOPMOST FIRST.** The last subview is drawn on top (the subview order IS the z order, which `-hitTest:`
 * already relies on), so the subviews are visited in REVERSE and a view's own areas come AFTER its children's — which
 * puts the deepest, topmost region at the FRONT of `hits`. That is what `NSTrackingCursorUpdate` needs (the topmost
 * owner who asked is the one who sets the cursor) and it costs the other two callbacks nothing, because they fire for
 * every area that changed regardless of where it sits. */
- (void)cg_walkTrackingInView:(NSView *)view point:(NSPoint)p moved:(BOOL)moved hits:(NSMutableArray *)hits
{
	NSArray *subs = [view subviews];
	NSArray *areas;
	NSInteger i;
	NSUInteger j;

	for (i = (NSInteger)[subs count] - 1; i >= 0; i--) {
		[self cg_walkTrackingInView:[subs objectAtIndex:(NSUInteger)i] point:p moved:moved hits:hits];
	}
	areas = [view trackingAreas];
	for (j = 0; j < [areas count]; j++) {
		NSTrackingArea *area = [areas objectAtIndex:j];
		NSTrackingAreaOptions o = [area options];
		BOOL want;

		/* **FROZEN DURING A DRAG, WHICH IS NOT THE SAME AS "OUTSIDE".** An area that did not ask for
		 * `NSTrackingEnabledDuringMouseDrag` is SKIPPED ENTIRELY while a button is held, leaving its bit exactly as it
		 * was — because a drag belongs to whoever began it, and firing an exit here would unlight a button halfway
		 * through its own press. The flag is what a caller sets to say "keep telling me while the pointer sweeps me
		 * with a button down". */
		if ([self cg_mouseButtonDown] && (o & NSTrackingEnabledDuringMouseDrag) == 0) {
			continue;
		}
		want = [self cg_areaIsActive:area] && [self cg_area:area ofView:view containsPoint:p];
		if (want) {
			[hits addObject:area];
			if (![area cg_isInside]) {
				[area cg_setInside:YES];
				[self cg_trackArea:area type:NSMouseEntered];
			} else if (moved && (o & NSTrackingMouseMoved) != 0) {
				[self cg_trackArea:area type:NSMouseMoved];
			}
		} else if ([area cg_isInside]) {
			[area cg_setInside:NO];
			[self cg_trackArea:area type:NSMouseExited];
		}
	}
}

/* **WHEN AN AREA IS LIVE, WHICH IS THE QUESTION THE WHOLE CLASS EXISTS TO ANSWER.** The four `Active…` bits are
 * mutually exclusive, and **NONE OF THEM SET MEANS `NSTrackingActiveInKeyWindow`** — Apple's documented default, and
 * the reason a background window's controls stay unlit. The tier used to decide this by looking at whichever window
 * the pointer happened to be over, so a button in a window that was not key prelighted anyway; the option word is
 * what makes the scope a property of the REGION rather than of the pointer's luck. */
- (BOOL)cg_areaIsActive:(NSTrackingArea *)area
{
	NSTrackingAreaOptions o = [area options];

	if ((o & NSTrackingActiveAlways) != 0) {
		return YES;
	}
	if ((o & NSTrackingActiveInActiveApp) != 0) {
		return [[NSApplication sharedApplication] isActive];
	}
	if ((o & NSTrackingActiveWhenFirstResponder) != 0) {
		/* THE OWNER IS THE RESPONDER THIS ASKS ABOUT, because the owner is who the callbacks go to. Apple's sentence
		 * names "the view"; a view-only reading would make the bit unusable for the one thing an area is FOR — an
		 * owner that is not the view — so the owner is what is asked, and the reading is stated rather than assumed. */
		return [self firstResponder] == [area owner];
	}
	return [self isKeyWindow];
}

- (BOOL)cg_area:(NSTrackingArea *)area ofView:(NSView *)view containsPoint:(NSPoint)p
{
	/* **`NSTrackingInVisibleRect` REPLACES THE RECTANGLE RATHER THAN ADJUSTING IT**, which is Apple's own rule ("the
	 * rect is ignored") and the reason the door can follow a scrolled view for free: `-visibleRect` is COMPUTED from
	 * the ancestors' bounds every time it is asked, so a clip view scrolling under a view moves the region with no
	 * `-updateTrackingAreas` pass at all. */
	NSRect r = (([area options] & NSTrackingInVisibleRect) != 0) ? [view visibleRect] : [area rect];

	return NSPointInRect(p, [view convertRect:r toView:nil]);
}

/* **ONE MESSAGE, AND THE OWNER IS ASKED FIRST.** An area's owner is any object a caller named, so a door it does not
 * implement is a callback it declined — quieter than a crash, and the same shape `-sendEvent:` uses for a responder. */
- (void)cg_trackArea:(NSTrackingArea *)area type:(NSEventType)type
{
	id owner = [area owner];
	SEL sel = (type == NSMouseEntered) ? @selector(mouseEntered:)
		: (type == NSMouseExited) ? @selector(mouseExited:)
		: @selector(mouseMoved:);

	if ([owner respondsToSelector:sel]) {
		[owner performSelector:sel withObject:[self cg_eventForArea:area type:type]];
	}
}

/* **AND THE EVENT, WHICH IS WHERE THE AREA REACHES THE OWNER.** Apple hands `-mouseEntered:` an `NSEvent` carrying the
 * `NSTrackingArea` that fired it, and that is the ONLY channel by which one owner serving several areas can tell them
 * apart — so the area is attached, and `[[event trackingArea] userInfo]` is the dictionary the caller installed.
 *
 * THE TWO TYPES USE THE TWO CONSTRUCTORS APPLE GIVES THEM: `+enterExitEventWithType:…` is the one that carries a
 * tracking number and user data (which is what a tracking RECT's event needs, and its `-trackingArea` is nil), and a
 * `-mouseMoved:` is an ordinary mouse event. The TIMESTAMP is read here rather than carried from the motion that
 * caused the call, because the engine fires from three different places and only one of them has an event. */
- (NSEvent *)cg_eventForArea:(NSTrackingArea *)area type:(NSEventType)type
{
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	NSEvent *e;

	if (type == NSMouseMoved) {
		e = [NSEvent mouseEventWithType:type location:_cg_trackingPoint modifierFlags:0
				      timestamp:now windowNumber:[self windowNumber] context:nil
				    eventNumber:0 clickCount:0 pressure:0.0f];
	} else {
		e = [NSEvent enterExitEventWithType:type location:_cg_trackingPoint modifierFlags:0
					  timestamp:now windowNumber:[self windowNumber] context:nil
					  eventNumber:0 trackingNumber:0 userData:NULL];
	}
	[e cg_setTrackingArea:area];
	return e;
}

- (void)cg_updateTrackingForPoint:(NSPoint)windowPoint
{
	NSMutableArray *hits = [[NSMutableArray alloc] init];
	BOOL moved = !_cg_hasTrackingPoint ||
		     windowPoint.x != _cg_trackingPoint.x || windowPoint.y != _cg_trackingPoint.y;
	NSUInteger i;

	_cg_trackingPoint = windowPoint;
	_cg_hasTrackingPoint = YES;
	if (_contentView != nil) {
		[self cg_walkTrackingInView:_contentView point:windowPoint moved:moved hits:hits];
	}
	/* **AND THE CURSOR GOES TO THE TOPMOST AREA THAT ASKED — one message, not one per area.** A cursor is a single
	 * global thing, so a second `-cursorUpdate:` would be a second opinion the first owner cannot see; the deepest
	 * region is the one the pointer is "in" for cursor purposes, which is the rule `-hitTest:` already follows. THE
	 * EVENT'S TYPE IS `NSMouseEntered` AND THAT IS THIS TIER'S CHOICE: the constructor is the enter/exit one, an
	 * arrival in a region is what the message reports, and Apple names no type for this door. */
	for (i = 0; i < [hits count]; i++) {
		NSTrackingArea *area = [hits objectAtIndex:i];

		if (([area options] & NSTrackingCursorUpdate) != 0) {
			id owner = [area owner];

			if ([owner respondsToSelector:@selector(cursorUpdate:)]) {
				[owner cursorUpdate:[self cg_eventForArea:area type:NSMouseEntered]];
			}
			break;
		}
	}
	[hits release];
}

/* **THE POINTER LEAVING THE WINDOW, WHICH THE SEAM REPORTS WITHOUT A POSITION.** Fed a point that cannot be inside any
 * view, the engine does exactly the right thing with no second code path: every area that was inside takes its exit
 * and every area that was not is left alone. A pointer that left a button and never moved again would otherwise leave
 * it prelighted for good. */
- (void)cg_clearTracking
{
	[self cg_updateTrackingForPoint:NSMakePoint(-1000000.0, -1000000.0)];
	_cg_hasTrackingPoint = NO;
}

- (NSPoint)mouseLocationOutsideOfEventStream
{
	/* **THE POINTER'S POSITION COMES FROM THE SEAM, NOT FROM A QUERY.** There is no `XQueryPointer` in
	 * `xdg-shell`: a client learns where the pointer is from `wl_pointer.motion`, so this door answers the LAST
	 * position the compositor reported — converted through this window's frame by `fn_window_point` when it
	 * arrived. Before anything has been reported it answers the origin, which is the honest "no information"
	 * for a coordinate rather than an invented one.
	 *
	 * AND THE ANSWER IS WINDOW-RELATIVE, WHICH IS WHAT A CALLER ASKED FOR. The X form read the pointer in ROOT
	 * coordinates and subtracted this frame's origin, which is the same number only while the manager honoured
	 * the frame. A Wayland client is TOLD the position in the surface the pointer is over, so there is no root
	 * coordinate that can disagree with the frame and the question does not arise. */
	if (!_cg_hasPointer) {
		return NSMakePoint(0.0, 0.0);
	}
	return _cg_pointer;
}


/* ---- THE DRAWING SURFACE ------------------------------------------------------------------- */

/* THE SURFACE IS THE CONTENT RECT'S, MADE ON DEMAND AND REMADE WHEN THAT RECT CHANGES SIZE — the size is
 * read back off the context rather than kept in a second ivar, so the two cannot disagree about it. */
- (BOOL)cg_ensureSurface
{
	NSInteger w, h;
	CGColorSpaceRef cs;

	if (![self cg_ensureWindow]) {
		return NO;
	}
	/* **THE SURFACE IS THE FRAME, NOT THE CONTENT** — client-side decoration (appkit-plan §6 D6). The window owns
	 * every pixel it was given, its title bar included, so the surface spans the FRAME and `-display` blits it at
	 * (0,0) rather than skipping the chrome rows. THE CONTENT IS UNMOVED inside it: Cocoa's frame puts the chrome at
	 * the TOP, so the content still begins at the surface's origin and every view coordinate in this tree is what it
	 * was. */
	w = (NSInteger)_frame.size.width;
	h = (NSInteger)_frame.size.height;
	if (w <= 0 || h <= 0) {
		return NO;
	}
	if (_surface != NULL) {
		if ((NSInteger)CGBitmapContextGetWidth(_surface) == w &&
		    (NSInteger)CGBitmapContextGetHeight(_surface) == h) {
			return YES;
		}
		CGContextRelease(_surface);
		_surface = NULL;
		free(_pixels);
		_pixels = NULL;
	}
	/* THE FORMAT IS THE SEAM'S OWN, AND IT IS THE SAME PATTERN FOR THE SAME REASON: the seam's frame buffer is
	 * `XRGB8888`, which on a little-endian machine stores a pixel as B, G, R, X in memory — exactly
	 * `PremultipliedFirst | 32Little`, the pair the drawing-handler canvas in NSImage uses too. So the copy in
	 * `-display` is a memcpy and not a conversion, and getting the pattern wrong would be a red/blue swap, which
	 * is why the probe checks a colour rather than a byte. */
	_pixels = calloc((size_t)w * (size_t)h * 4u, 1);
	if (_pixels == NULL) {
		return NO;
	}
	cs = CGColorSpaceCreateDeviceRGB();
	_surface = CGBitmapContextCreate(_pixels, (size_t)w, (size_t)h, 8, (size_t)w * 4u, cs,
					 (uint32_t)(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little));
	CGColorSpaceRelease(cs);
	if (_surface == NULL) {
		free(_pixels);
		_pixels = NULL;
		return NO;
	}
	_surfaceWidth = (int)w;
	_surfaceHeight = (int)h;
	return YES;
}

/* DRAW AND BLIT. The content view is drawn through an `NSGraphicsContext` over the surface, and the surface
 * is then put on the window with `XPutImage` — a copy from CLIENT memory, which is what makes the backing
 * store the authority on what the window shows. */
/* AN EVENT FROM THE COMPOSITOR, TURNED INTO THIS CLASS'S STATE AND ITS QUEUE. The two kinds that are not
 * NSEvents are handled here: a CONFIGURE is the window's real size — a window is not its requested size until
 * the compositor has configured it — and a CLOSE is the compositor asking for the window to go away.
 *
 * THE CLOSE IS DEFERRED, AND THAT IS NOT FASTIDIOUSNESS: this runs INSIDE libwayland's dispatch, and destroying
 * the `AGWindow` here would free the very surface whose listeners are still on the stack. The flag is acted on
 * by the pump, which runs outside the dispatch. */
- (void)cg_handleSeamEvent:(const AGEvent *)event
{
	switch (event->type) {
	case AGEventConfigure:
		/* THE SIZE IS THE COMPOSITOR'S TO DECIDE, and this is the only place the real one comes from. The Cocoa
		 * frame keeps its origin and takes the new size; the backing store is remade by `cg_ensureSurface` on the
		 * next draw, because its size no longer matches. */
		_frame.size.width = (CGFloat)event->x;
		_frame.size.height = (CGFloat)event->y;
		_viewsNeedDisplay = YES;
		[self cg_drawFrame];
		break;
	case AGEventClose:
		_cg_closeRequested = YES;
		break;
	case AGEventKey:
	case AGEventPointerButton:
	case AGEventPointerMotion:
	case AGEventPointerEnter: {
		NSEvent *ev;
		NSPoint p = fn_window_point(self, event->x, event->y);

		if (event->type != AGEventKey) {
			_cg_pointer = p;
			_cg_hasPointer = YES;
		}
		if (event->type == AGEventPointerButton) {
			_cg_mouseButtonDown = event->pressed;
		}
		if (event->type == AGEventPointerEnter && !event->pressed) {
			/* THE POINTER LEFT THE WINDOW: there is no motion and no button in it — AND THE AREAS IT WAS INSIDE ARE TOLD,
			 * because the crossing has to be synthesised from SOMETHING and no motion event is coming to carry it. A
			 * pointer that leaves a button and never moves again would otherwise leave the button prelighted for good. */
			[self cg_clearTracking];
			return;
		}
		ev = fn_translate(self, event, [NSDate timeIntervalSinceReferenceDate]);
		if (ev != nil) {
			[_cg_events addObject:ev];
			s_queued_events++;
		}
		break;
	}
	default:
		break;
	}
}

- (BOOL)cg_mouseButtonDown
{
	return _cg_mouseButtonDown;
}

/* DRAW AND PRESENT. The content view is drawn through an `NSGraphicsContext` over this window's own backing
 * store, and the backing store is then COPIED into the frame the compositor handed over. One copy per frame is
 * the price of a client-side backing store on a protocol whose buffers come and go, and it is what keeps this
 * class's drawing model — and every view coordinate in this tree — what it was. */
- (void)cg_drawFrame
{
	NSRect content;
	NSGraphicsContext *g;
	NSGraphicsContext *prev;
	CGContextRef c;
	uint32_t *frame;
	int stride = 0;
	int y;

	if (_agwindow == NULL || ![self cg_ensureSurface]) {
		return;
	}
	c = (CGContextRef)_surface;
	content = [self contentRectForFrameRect:_frame];
	/* **THE TWO HALVES OF A CLIENT-SIDE-DECORATED FRAME, IN THE ORDER THEY STACK.** The surface is the FRAME (see
	 * `cg_ensureSurface`), so everything here paints into the window's own pixels: the CONTENT is the lower
	 * `content.size.height` rows, where the view tree draws at the origin it has always drawn at, and the CHROME is
	 * the strip above them — which this method paints because nothing else will (appkit-plan §6 D6). There are no
	 * rows without an author, which is what the white stripe this file once carried was. */
	CGContextSetFillColorWithColor(c, [[self backgroundColor] CGColor]);
	CGContextFillRect(c, CGRectMake(0.0, 0.0, content.size.width, content.size.height));
	if (_contentView != nil) {
		g = [NSGraphicsContext graphicsContextWithCGContext:_surface flipped:NO];
		prev = [[NSGraphicsContext currentContext] retain];
		[NSGraphicsContext setCurrentContext:g];
		/* THE TREE WALK IS THE VIEW'S: `-displayRect:` draws the receiver AND its subviews, which is what the
		 * WINDOW used to do by hand — and could only do for one view. */
		[_contentView displayRect:[_contentView bounds]];
		[NSGraphicsContext setCurrentContext:prev];
		[prev release];
	}
	fn_draw_chrome(c, self, content);

	/* **THE PRESENT.** `AGWindowBeginFrame` answers NULL while the compositor still owns the previous frame, and
	 * that is not a failure: the seam calls the frame handler again when the buffer comes back, and there is no
	 * Expose to wait for because the client owns the pixels. */
	frame = AGWindowBeginFrame(_agwindow, &stride);
	if (frame == NULL) {
		/* **A REFUSED PAINT, NAMED.** The compositor still holds this window's previous buffer, so this pass draws
		 * nothing — and the retry is the run loop's `-displayIfNeeded`, which only happens if the flag is still set.
		 * It is, and this line is what makes a paint that never happens visible instead of invisible. */
		if (getenv("APPKIT_DRAW_DIAG") != NULL) {
			/* **AND IT DOES NOT GUESS AT THE REASON.** This line used to say "the compositor still holds its
			 * buffer" for every refusal, and the door refuses for four different reasons — MEASURED, that sentence
			 * sent two rounds into buffer lifetime for a fault that was never there. The seam names its own
			 * condition (see `AGWindowBeginFrame`), so this only says WHICH WINDOW could not paint. */
			fprintf(stderr, "  DIAG draw: window %ld could not paint (the reason is named by the seam)\n",
				(long)[self windowNumber]);
		}
		return;
	}
	for (y = 0; y < _surfaceHeight; y++) {
		memcpy((char *)frame + (size_t)y * (size_t)stride,
		       _pixels + (size_t)y * (size_t)_surfaceWidth * 4u,
		       (size_t)_surfaceWidth * 4u);
	}
	AGWindowEndFrame(_agwindow);
	_viewsNeedDisplay = NO;
}

/* `-display` IS THE COCOA DOOR and the frame handler is the compositor's, but both end in the same draw: a
 * caller asking a window to display and a compositor asking for a frame want the same pixels. */
- (void)display
{
	[self cg_drawFrame];
}

- (void)displayIfNeeded
{
	if (_viewsNeedDisplay) {
		[self display];
	}
}

/* `-update` IS ABOUT THE VIEWS, which is Apple's own split: it marks the content view as needing display and
 * then does the display pass the flag decides. */
- (void)update
{
	/* THE ANNOUNCEMENT COMES FIRST, because its whole purpose is to give a delegate the chance to change what the
	 * window SHOWS before the pass that shows it runs. */
	fn_announce(self, NSWindowDidUpdateNotification, @selector(windowDidUpdate:));
	if (_contentView != nil) {
		[_contentView setNeedsDisplay:YES];
	}
	_viewsNeedDisplay = YES;
	[self displayIfNeeded];
}

- (BOOL)viewsNeedDisplay
{
	return _viewsNeedDisplay;
}

- (void)setViewsNeedDisplay:(BOOL)flag
{
	_viewsNeedDisplay = flag;
}

- (void)setIsVisible:(BOOL)flag
{
	if (flag) {
		[self orderFront:nil];
	} else {
		[self orderOut:nil];
	}
}

- (BOOL)canStoreColor
{
	/* 24-BIT ON EVERY DISPLAY THIS TREE RUNS ON, which follows from the seam's own 32-bit `XRGB8888` frame rather than
	 * a query — and the honest answer to "can this device store colour" for them is YES. */
	return YES;
}

/* ---- THE FOUR THAT REFUSE BY NAME ----------------------------------------------------------- */

- (void)invalidateShadow
{
	fprintf(stderr, "APPKIT-REFUSE: -invalidateShadow drops a CACHED shadow so the server recomputes it, and "
			"this tree's shadows belong to a window manager — Kestrel, which is parked — so there is "
			"no cached shadow to drop\n");
}

- (void)cacheImageInRect:(NSRect)aRect
{
	(void)aRect;
	/* THE CACHE IS WHAT THIS WINDOW ALREADY IS. Apple's trio exists to remember a screen rect so it can be
	 * put back without redrawing; a backing store does that for EVERY frame, which is why the trio has
	 * nothing to add here rather than being unimplemented. */
	fprintf(stderr, "APPKIT-REFUSE: -cacheImageInRect: remembers a rect to redraw later, and this window "
			"already keeps its whole content in a BACKING STORE that every display blits\n");
}

- (void)discardCachedImage
{
	fprintf(stderr, "APPKIT-REFUSE: -discardCachedImage has nothing to discard — see -cacheImageInRect:\n");
}

- (void)restoreCachedImage
{
	fprintf(stderr, "APPKIT-REFUSE: -restoreCachedImage has nothing to restore — see -cacheImageInRect:\n");
}

- (void)disableScreenUpdatesUntilFlush
{
	/* THERE IS NO DEFERRED DRAW QUEUE TO SUSPEND: the drawing goes into the backing store and the blit
	 * happens with the frame, so a caller asking to hold updates back until a flush would be holding back a
	 * copy rather than a draw. Deprecated by Apple in any case. */
	fprintf(stderr, "APPKIT-REFUSE: -disableScreenUpdatesUntilFlush suspends a deferred draw queue, and this "
			"window draws into a backing store and blits with the frame — there is nothing deferred\n");
}


/* ============================================================================================ *
 * WHERE THE WINDOW IS, AND WHERE IT WAS.                                                        *
 * ============================================================================================ */

/* APPLE PUBLISHES THIS SYMBOL AND NO NUMBER, so the value is ours. A window level is a band, and 1000 is the
 * level this symbol is used at — above the normal level and below the shielding one. */
const CGFloat NSScreenSaverWindowLevel = 1000.0;

/* THE TOP-LEFT SETTER, AND THE SUBTRACTION IS THE WHOLE OF IT: Cocoa's frame origin is the BOTTOM-left corner,
 * so a caller who has the top-left (a title-bar drag, a cascade) needs this and nothing else. */
- (void)setFrameTopLeftPoint:(NSPoint)point
{
	[self setFrameOrigin:NSMakePoint(point.x, point.y - _frame.size.height)];
}

- (NSPoint)convertBaseToScreen:(NSPoint)aPoint
{
	/* THE BASE POINT PLUS THE FRAME'S ORIGIN, with no bezel term: this window's coordinate system starts at its
	 * own bottom-left corner, which the class note states as the deviation. */
	return NSMakePoint(_frame.origin.x + aPoint.x, _frame.origin.y + aPoint.y);
}

- (NSPoint)convertScreenToBase:(NSPoint)aPoint
{
	return NSMakePoint(aPoint.x - _frame.origin.x, aPoint.y - _frame.origin.y);
}

- (NSTimeInterval)animationResizeTime:(NSRect)newFrame
{
	/* ZERO, AND IT IS AN ANSWER RATHER THAN A SHRUG: an animated resize is a sequence of frames over time, and
	 * this window's frame change is ONE X request — there is nothing to time. Apple's own method returns 0.0
	 * for a window that cannot animate, which is this one. */
	/* THE DOOR TAKES THE FRAME IT WOULD RESIZE TO, and this window cannot use it — see above. */
	(void)newFrame;
	return 0.0;
}


/* ONE PLACE THAT DECIDES WHAT "THE SCREEN" MEANS, so no door repeats the rule: the argument when there is one,
 * because a caller that names a screen means it, and the main screen when there is not — which is Apple's own
 * contract for a nil argument. */
- (NSScreen *)cg_screenFor:(NSScreen *)screen
{
	return (screen != nil) ? screen : [NSScreen mainScreen];
}

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
	/* **THE ARGUMENT IS ACCEPTED AND NOT CONSULTED.** `NSScreen` is a class this tree does not ship, so the
	 * screen here is the X root — and a caller that passed a real `NSScreen` gets the same answer as one that
	 * passed nil, which the header states. Silently using half of a passed object's meaning would be worse. */
	NSRect r = frameRect;
	NSRect visible = [[self cg_screenFor:screen] visibleFrame];
	CGFloat sw, sh;

	/* **AND THE ARGUMENT IS CONSULTED NOW, WHICH IS THE DEVIATION THIS CLASS ENDS.** It used to be accepted and
	 * ignored, because a screen was the X root and there was no object to ask. A caller that passes a screen gets
	 * THAT screen's visible frame — and a window at a screen whose origin is not (0,0) is constrained against it
	 * rather than against the whole coordinate space, which the old arithmetic could not express at all. */
	if (visible.size.width <= 0.0 || visible.size.height <= 0.0) {
		return r;   /* no server, no screen — and no constraint is better than a constraint against nothing */
	}
	sw = visible.origin.x + visible.size.width;
	sh = visible.origin.y + visible.size.height;
	/* THE TITLE BAR STAYS REACHABLE, which is the rule: a window may hang off the bottom and either side, but
	 * its top edge never goes above the screen's top, and a part of it wide enough to grab stays visible.
	 * THE MINIMUM VISIBLE WIDTH IS OURS — Apple does not publish a number. */
	{
		const CGFloat minVisible = 100.0;

		if (r.origin.y + r.size.height > sh) {
			r.origin.y = sh - r.size.height;
		}
		if (r.origin.y < visible.origin.y) {
			r.origin.y = visible.origin.y;
		}
		if (r.origin.x + r.size.width < minVisible) {
			r.origin.x = minVisible - r.size.width;
		}
		if (r.origin.x > sw - minVisible) {
			r.origin.x = sw - minVisible;
		}
		if (r.origin.x + r.size.width < visible.origin.x + minVisible) {
			r.origin.x = visible.origin.x + minVisible - r.size.width;
		}
	}
	return r;
}

+ (CGFloat)minFrameWidthWithTitle:(NSString *)aTitle styleMask:(NSUInteger)aStyle
{
	/* THE MASK'S WHOLE CONTRIBUTION HERE IS WHETHER THERE IS ANY CHROME AT ALL, because this tree has no named
	 * style-mask bits yet — the style mask is a plain integer (see the header), so a decorated window pays for
	 * its buttons and a borderless one does not. Apple's answer also depends on WHICH buttons, through bits
	 * this tree has not named; that is the owed part, stated. The per-character term is an ESTIMATE: Apple
	 * measures the rendered title and this window owns no font metrics. */
	/* THE BUTTONS' ALLOWANCE IS DERIVED, not chosen: three buttons of `fn_BUTTON` plus the leading inset —
	 * the same constant the chrome is DRAWN with, so a window cannot be too narrow for what it paints. */
	CGFloat chrome = (aStyle == 0) ? 0.0 : 3.0 * fn_BUTTON;
	CGFloat title = 0.0;

	/* **THE MEASUREMENT IS REAL NOW, AND IT WAS AN ESTIMATE**: this used to multiply the title's LENGTH by seven
	 * points, which is a guess at a rendered width and wrong for every face and every string — "Wi" and "il" are
	 * two characters and very different widths. The attributes are the painter's own (`fn_title_attributes`), so a
	 * window cannot be sized for a title that will be laid out in a different font from the one it was measured
	 * in, and `windowFrameTextColor`'s own ledger rows are untouched by this: they were already shipped. */
	if (aTitle != nil && fn_title_attributes() != nil) {
		title = [aTitle sizeWithAttributes:fn_title_attributes()].width;
	}
	return chrome + 16.0 + title;
}

/* ---- THE ZOOM, WHICH ALTERNATES -------------------------------------------------------------- */

- (void)zoom:(id)sender
{
	(void)sender;
	if (_zoomed && _hasPreZoomFrame) {
		NSRect back = _preZoomFrame;

		/* THE CHANGED STATE COMES FIRST, so a caller that reads `-frame` from inside its own notification sees
		 * a window that is already unzoomed — and so a re-entrant `-zoom:` alternates instead of recursing. */
		_zoomed = NO;
		_hasPreZoomFrame = NO;
		[self setFrame:back display:YES];
	} else {
		NSRect standard = [[NSScreen mainScreen] visibleFrame];

		if (standard.size.width <= 0.0 || standard.size.height <= 0.0) {
			fprintf(stderr, "APPKIT-REFUSE: -zoom: needs a screen: the standard frame IS the screen in this "
					"tree, and there is none to measure (DISPLAY unset or no server listening)\n");
			return;
		}
		/* **THE ZOOM ASKS THE DELEGATE, TWICE, AND BOTH QUESTIONS ARE THIS PROTOCOL'S.** The first is for the
		 * frame the window should take — the delegate may answer something other than the screen, which is how an
		 * application zooms to a frame that suits its content — and the second is permission to zoom at all. They
		 * are asked in Apple's order: the frame first, then whether to use it. */
		if (_delegate != nil && [_delegate respondsToSelector:@selector(windowWillUseStandardFrame:defaultFrame:)]) {
			standard = [(id <NSWindowDelegate>)_delegate windowWillUseStandardFrame:self
									  defaultFrame:standard];
		}
		if (_delegate != nil && [_delegate respondsToSelector:@selector(windowShouldZoom:toFrame:)]) {
			if (![(id <NSWindowDelegate>)_delegate windowShouldZoom:self toFrame:standard]) {
				return;	/* REFUSED, and the window is left EXACTLY as it was — not zoomed and not remembered */
			}
		}
		_preZoomFrame = _frame;
		_hasPreZoomFrame = YES;
		_zoomed = YES;
		[self setFrame:standard display:YES];
	}
}

- (void)performZoom:(id)sender
{
	/* THE DOOR THE ZOOM BUTTON SENDS. Apple's default implementation is `-zoom:`, and this one calls it rather
	 * than repeating it, so a subclass that overrides either gets the other's behaviour — which is the only
	 * reason the pair exists at all. */
	[self zoom:sender];
}

- (BOOL)isZoomed
{
	return _zoomed;
}

- (void)setIsZoomed:(BOOL)flag
{
	if (flag != _zoomed) {
		[self zoom:nil];
	}
}

/* ---- AND WHERE IT WAS: THE SAVED FRAME ------------------------------------------------------- */

- (NSString *)stringWithSavedFrame
{
	/* `x y w h` WITH THE TRAILING SPACE, which is the form Apple's writes — so a string this window produced can
	 * be handed to Apple's `-setFrameFromString:` and vice versa. `%g` rather than `%f`, because a frame string
	 * is meant to be short and the format has no fixed precision in it. */
	return [NSString stringWithFormat:@"%g %g %g %g ",
			(double)_frame.origin.x, (double)_frame.origin.y,
			(double)_frame.size.width, (double)_frame.size.height];
}

- (void)setFrameFromString:(NSString *)string
{
	double x = 0.0, y = 0.0, w = 0.0, h = 0.0;

	/* THE PARSE IS PERMISSIVE ABOUT WHITESPACE AND STRICT ABOUT THE COUNT: a string that is not four numbers is
	 * REFUSED BY NAME rather than placing the window at whatever origin a partial read left behind. */
	if (string == nil || sscanf([string UTF8String], "%lf %lf %lf %lf", &x, &y, &w, &h) != 4) {
		fprintf(stderr, "APPKIT-REFUSE: -setFrameFromString: needs four numbers, `x y w h`; the frame is "
				"left where it was rather than placed from a partial read\n");
		return;
	}
	[self setFrame:NSMakeRect((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h) display:YES];
}

- (BOOL)setFrameUsingName:(NSString *)name
{
	return [self setFrameUsingName:name force:NO];
}

- (BOOL)setFrameUsingName:(NSString *)name force:(BOOL)force
{
	id saved = [[NSUserDefaults standardUserDefaults] objectForKey:name];

	/* IT ANSWERS NO WHEN NOTHING WAS SAVED, rather than placing the window at an origin of zero: "there was no
	 * saved frame" is a fact a caller acts on, and a frame at (0,0) is a placement it cannot tell from a real
	 * one. `force:` is about a user drag in progress, which this window does not track — stated, not pretended. */
	(void)force;
	if (![saved isKindOfClass:[NSString class]]) {
		return NO;
	}
	[self setFrameFromString:(NSString *)saved];
	return YES;
}

- (void)saveFrameUsingName:(NSString *)name
{
	if (name == nil) {
		return;
	}
	[[NSUserDefaults standardUserDefaults] setObject:[self stringWithSavedFrame] forKey:name];
}

+ (void)removeFrameUsingName:(NSString *)name
{
	if (name == nil) {
		return;
	}
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:name];
}

- (void)setFrameAutosaveName:(NSString *)name
{
	/* SETTING THE NAME RESTORES A SAVED FRAME IF THERE IS ONE — that is what makes the name useful — and the
	 * window then SAVES ITSELF WHEN IT CLOSES, wired in `-close`. */
	NSString *old = _frameAutosaveName;

	_frameAutosaveName = [name retain];
	[old release];
	if (name != nil) {
		(void)[self setFrameUsingName:name];
	}
}

- (NSString *)frameAutosaveName
{
	return _frameAutosaveName;
}


/* ============================================================================================ *
 * ORDERING, THE KEY/MAIN STATE, THE FLUSH PAIR AND THE TITLE THAT STANDS FOR A FILE.            *
 * ============================================================================================ */

NSString *NSWindowDidBecomeKeyNotification = @"NSWindowDidBecomeKeyNotification";
NSString *NSWindowDidBecomeMainNotification = @"NSWindowDidBecomeMainNotification";
NSString *NSWindowDidResignKeyNotification = @"NSWindowDidResignKeyNotification";
NSString *NSWindowDidResignMainNotification = @"NSWindowDidResignMainNotification";

/* THE WINDOW THE APPLICATION CURRENTLY HAS AS ITS KEY OR MAIN ONE, asked of the REGISTRY rather than kept in a
 * second place: a window that has been closed is gone from it, and a cache of "the key window" would be one
 * more thing to keep true. */
static NSWindow *fn_key_window(NSWindow *except)
{
	NSArray *windows = [[NSApplication sharedApplication] windows];
	NSUInteger i;

	for (i = 0; windows != nil && i < [windows count]; i++) {
		NSWindow *w = [windows objectAtIndex:i];

		if (w != except && [w isKeyWindow]) {
			return w;
		}
	}
	return nil;
}

static NSWindow *fn_main_window(NSWindow *except)
{
	NSArray *windows = [[NSApplication sharedApplication] windows];
	NSUInteger i;

	for (i = 0; windows != nil && i < [windows count]; i++) {
		NSWindow *w = [windows objectAtIndex:i];

		if (w != except && [w isMainWindow]) {
			return w;
		}
	}
	return nil;
}

/* ---- THE ORDERING --------------------------------------------------------------------------- */

- (void)orderBack:(id)sender
{
	(void)sender;
	if (![self cg_ensureWindow]) {
		return;
	}
	/* **ORDERING IS THE APPLICATION'S ON THE MAC** — `-orderFront:` raises its own window — so on a compositor
	 * that can be told, it is told. Where it cannot, this door shows the window and changes THIS OBJECT's state,
	 * which is the deviation the header records. */
	AGWindowShow(_agwindow);
	AGWindowRaise(_agwindow);
	_visible = YES;
	[[NSApplication sharedApplication] cg_addWindow:self];
}

- (void)orderFrontRegardless
{
	if (![self cg_ensureWindow]) {
		return;
	}
	/* NO RAISE: the stacking is the compositor's (see `-orderBack:`). */
	AGWindowShow(_agwindow);
	_visible = YES;
	[[NSApplication sharedApplication] cg_addWindow:self];
	/* **AND NOTHING ELSE HAPPENS.** "Regardless" means the window comes forward WITHOUT the application's key
	 * or main state changing — a caller that wanted those sent `-makeKeyAndOrderFront:`. */
}

/* ---- BECOMING AND RESIGNING ---------------------------------------------------------------- */

- (void)becomeKeyWindow
{
	NSWindow *previous;

	if (_key) {
		return;
	}
	/* THE PREVIOUS ONE RESIGNS FIRST, and it resigns through its own door so ITS notification is posted: a
	 * callback that fires from this one sees a single key window, not two. */
	previous = fn_key_window(self);
	if (previous != nil) {
		[previous resignKeyWindow];
	}
	_key = YES;
	/* AND THE SAME RE-EVALUATION ON THE WAY IN: the areas that were dead a moment ago are live again, so a control the
	 * pointer is already resting on lights up without waiting for the hand to move. */
	[self cg_updateTrackingForPoint:[self mouseLocationOutsideOfEventStream]];
	fn_announce(self, NSWindowDidBecomeKeyNotification, @selector(windowDidBecomeKey:));
}

- (void)becomeMainWindow
{
	NSWindow *previous;

	if (_main) {
		return;
	}
	previous = fn_main_window(self);
	if (previous != nil) {
		[previous resignMainWindow];
	}
	_main = YES;
	fn_announce(self, NSWindowDidBecomeMainNotification, @selector(windowDidBecomeMain:));
}

- (void)resignMainWindow
{
	if (!_main) {
		return;
	}
	_main = NO;
	fn_announce(self, NSWindowDidResignMainNotification, @selector(windowDidResignMain:));
}

/* ---- THE FLUSH PAIR ------------------------------------------------------------------------- */

- (void)flushWindow
{
	AGWindowServer *server = fn_server();

	/* THE COUNT MOVES WHETHER OR NOT FLUSHING IS ENABLED — it counts the CALLS — and the PUSH is what the flag
	 * gates. That split is what makes the flag observable at all: the seam flushes the CONNECTION as a whole, so
	 * there is no partial buffer for a disabled window to hold back either. */
	_flushCount++;
	if (_flushing && server != NULL) {
		AGWindowServerFlush(server);
		_flushPushCount++;
	}
}

- (void)flushWindowIfNeeded
{
	/* The "if needed" half lives in the caller's dirty state and not here, because X has no per-window buffer
	 * to be dirty — see the note above. */
	[self flushWindow];
}

- (void)enableFlushWindow
{
	_flushing = YES;
}

- (void)disableFlushWindow
{
	_flushing = NO;
}

/* THE SEAM THE PROBE READS: the private count, and the flag as this object holds it. A public door for it
 * would be a door Apple does not have; an unobservable flag would make `-disableFlushWindow` untestable. */
- (NSInteger)cg_flushCount
{
	return _flushCount;
}

- (NSInteger)cg_flushPushCount
{
	return _flushPushCount;
}

- (BOOL)cg_flushingEnabled
{
	return _flushing;
}

/* ---- THE TITLE THAT STANDS FOR A FILE -------------------------------------------------------- */

- (void)setTitleWithRepresentedFilename:(NSString *)aString
{
	const char *s = (aString != nil) ? [aString UTF8String] : NULL;
	const char *slash = NULL, *p;
	NSString *old;

	if (s == NULL) {
		return;
	}
	/* THE NAME IS THE LAST PATH COMPONENT, found by scanning rather than by asking for a path API: the title
	 * is the whole of what this window does with it, and a helper that does not exist would be a dependency
	 * for one `for` loop. */
	for (p = s; *p != '\0'; p++) {
		if (*p == '/') {
			slash = p;
		}
	}
	old = _representedFilename;
	_representedFilename = [aString copy];
	[old release];
	[self setTitle:[NSString stringWithUTF8String:(slash != NULL ? slash + 1 : s)]];
}

- (NSString *)representedFilename
{
	return _representedFilename;
}


/* ============================================================================================ *
 * THE KEY-VIEW LOOP.                                                                            *
 * ============================================================================================ */

/* THE ROW TOLERANCE, WHICH IS OURS: two views whose top edges differ by less than this are IN THE SAME ROW, and
 * a reading order that compared them exactly would sort a hand-laid-out grid by fractions of a point. Apple's
 * algorithm groups rows too and does not publish its threshold. */
#define FN_KEY_VIEW_ROW_TOLERANCE 4.0

/* EVERY VIEW UNDER `v` THAT ACCEPTS FIRST RESPONDER, depth first. A plain `NSView` answers NO — the default is
 * on `NSResponder` — so a view is in the loop only because it said so. */
static void fn_collect_focusable(NSView *v, NSMutableArray *into)
{
	NSArray *subs;
	NSUInteger i;

	if (v == nil) {
		return;
	}
	if ([v acceptsFirstResponder]) {
		[into addObject:v];
	}
	subs = [v subviews];
	for (i = 0; subs != nil && i < [subs count]; i++) {
		fn_collect_focusable([subs objectAtIndex:i], into);
	}
}

/* **THE READING ORDER, WHICH IS THE WHOLE CONTRACT OF THIS DOOR.** Apple's loop runs left to right and top to
 * bottom — NOT in the order the views were added — so a grid built bottom-up still tabs in reading order. Both
 * edges are measured in the CONTENT VIEW's coordinates, because two focusable views are usually in different
 * superviews and their own frames are not comparable. Descending y for a NON-flipped content view (Cocoa's y
 * grows upward) and ascending for a flipped one; ties broken by the leading edge. */
static int fn_reading_order(NSView *content, NSView *a, NSView *b)
{
	NSRect ra = [a convertRect:[a bounds] toView:content];
	NSRect rb = [b convertRect:[b bounds] toView:content];
	BOOL flipped = [content isFlipped];
	CGFloat atop = flipped ? NSMinY(ra) : -NSMaxY(ra);
	CGFloat btop = flipped ? NSMinY(rb) : -NSMaxY(rb);

	if (atop < btop - FN_KEY_VIEW_ROW_TOLERANCE) {
		return -1;
	}
	if (atop > btop + FN_KEY_VIEW_ROW_TOLERANCE) {
		return 1;
	}
	if (NSMinX(ra) < NSMinX(rb)) {
		return -1;
	}
	if (NSMinX(ra) > NSMinX(rb)) {
		return 1;
	}
	return 0;
}

/* AN INSERTION SORT, because the comparator needs the content view as context and this Foundation's
 * `NSMutableArray` should not be depended on for a function sort it may not carry. It is STABLE, which matters:
 * two views in the same cell keep the order they were collected in rather than swapping on every
 * recalculation. */
static void fn_sort_focusable(NSMutableArray *list, NSView *content)
{
	NSUInteger i, j, n = [list count];

	for (i = 1; i < n; i++) {
		id key = [[list objectAtIndex:i] retain];

		j = i;
		while (j > 0 && fn_reading_order(content, [list objectAtIndex:j - 1], key) > 0) {
			[list replaceObjectAtIndex:j withObject:[list objectAtIndex:j - 1]];
			j--;
		}
		[list replaceObjectAtIndex:j withObject:key];
		[key release];
	}
}

- (void)recalculateKeyViewLoop
{
	NSMutableArray *list = [NSMutableArray array];
	NSMutableArray *old;
	NSUInteger i, n;

	/* THE CONTENT VIEW'S SUBTREE IS THE UNIVERSE: a view outside it is not in this window, and a view in a CHILD
	 * WINDOW belongs to that window's loop. */
	fn_collect_focusable(_contentView, list);
	fn_sort_focusable(list, _contentView);
	n = [list count];
	/* THE CHAIN IS WHAT TAB FOLLOWS; the array is kept beside it so a PRECEDING selection can be answered
	 * without walking the tree backwards looking for whoever points here. */
	for (i = 0; i < n; i++) {
		[[list objectAtIndex:i] setNextKeyView:[list objectAtIndex:(i + 1) % n]];
	}
	old = _keyViewLoop;
	_keyViewLoop = [list retain];
	[old release];
}

/* THE LOOP IS BUILT ON DEMAND, which is what makes a caller that never asks for it pay nothing — and what makes
 * a caller that edits the view tree need nothing but the next selection. */
/* ---- THE THREE KEY-VIEW DOORS THAT WERE OWED ------------------------------------------------- */

/* SEE THE HEADER FOR APPLE'S WORDING AND FOR WHAT EACH ANSWERS. The direction recording lives in the four
 * traversal doors below; this is the state and the one-time placement. */

- (NSView *)initialFirstResponder
{
	return _initialFirstResponder;
}

- (void)setInitialFirstResponder:(NSView *)view
{
	_initialFirstResponder = view;	/* unretained, as Apple declares it */
}

- (NSSelectionDirection)keyViewSelectionDirection
{
	return _keyViewSelectionDirection;
}

- (BOOL)autorecalculatesKeyViewLoop
{
	/* NO IS THE TRUE ANSWER — see the header. The loop is built on demand and rebuilt only when a caller marks it
	 * with `-recalculateKeyViewLoop`; nothing here recalculates it because a view was added. */
	return NO;
}

/* ---- THE THREE VISIBILITY FLAGS ------------------------------------------------------------------ */

/* SEE THE HEADER FOR APPLE'S OWN COMMENT ON `canHide`, FOR THE TWO STATED BOUNDARIES, AND FOR WHY ONE OF THESE IS
 * STORED AS ITS DEVIATION (an ivar defaults to NO and `canHide`'s default is YES). */

/* ---- THE CONTENT BORDER -------------------------------------------------------------------------- */

/* SEE THE HEADER FOR THE TWO DOCUMENTED RULES AND FOR WHAT THESE DO NOT DO (the border is DRAWN on the real thing
 * and this tier paints nothing for it). `NSRectEdge` is a small enum — MinX, MinY, MaxX, MaxY — and an index
 * outside it cannot arrive from a caller using the constants; a value outside it is still clamped rather than used
 * as an index, because an array bound is not a place to trust a parameter. */

static NSUInteger fn_edge_index(NSRectEdge edge)
{
	NSUInteger i = (NSUInteger)edge;

	return (i < 4) ? i : 0;
}

/* THE ONE REFUSAL, in one place because BOTH setters are subject to it: a TOP edge on a window that is not
 * textured, which is Apple's own documented exception. It answers nothing — it raises or it returns. */
/* ---- WHAT THE USER MAY DO WITH THE WINDOW -------------------------------------------------------- */

/* SEE THE HEADER FOR THE THREE ABILITIES' DEFINITIONS AND FOR APPLE'S OWN PROSE ON THE TWO DRAGGING FLAGS. */

- (BOOL)resizable
{
	return (_styleMask & NSResizableWindowMask) != 0;
}

- (BOOL)miniaturizable
{
	return (_styleMask & NSMiniaturizableWindowMask) != 0;
}

- (BOOL)hasTitleBar
{
	return (_styleMask & NSTitledWindowMask) != 0;
}

- (BOOL)hasCloseBox
{
	return (_styleMask & NSClosableWindowMask) != 0;
}

- (BOOL)zoomable
{
	/* THE ZOOM BUTTON IS THE RESIZABLE BIT — see the header. */
	return (_styleMask & NSResizableWindowMask) != 0;
}

- (BOOL)isMovable
{
	return !_cg_refusesMove;
}

- (void)setMovable:(BOOL)flag
{
	_cg_refusesMove = flag ? NO : YES;
}

- (BOOL)isMovableByWindowBackground
{
	if (_cg_movableByBackgroundSet) {
		return _cg_movableByBackground;
	}
	/* **THE CONDITIONAL DEFAULT**: Apple's documentation gives a TEXTURED window YES here and every other window
	 * NO, which is the default the mask shipped a unit ago was for. */
	return (_styleMask & NSTexturedBackgroundWindowMask) != 0;
}

- (void)setMovableByWindowBackground:(BOOL)flag
{
	if (flag) {
		/* TWO DOCUMENTED IGNORES, both stated in the header: a window that refuses to be MOVED ignores this flag
		 * entirely, and a sheet cannot be movable by its background. Asking for what is ignored CHANGES NOTHING
		 * rather than raising, because both are Apple's own sentences about the flag rather than about an error. */
		if (![self isMovable] || [self isSheet]) {
			return;
		}
	}
	_cg_movableByBackground = flag ? YES : NO;
	_cg_movableByBackgroundSet = YES;
}

/* ---- THE WINDOW'S OWNER, WHAT IT REPRESENTS, AND HOW IT SHRINKS -------------------------------- */

/* SEE THE HEADER FOR WHY THE CONTROLLER LINK IS THE CONTROLLER'S TO MAKE, AND FOR WHAT THE OTHER THREE DO NOT DO. */

- (id)windowController
{
	return _cg_windowController;
}

- (void)setWindowController:(NSWindowController *)windowController
{
	/* RECORDED, NOT CALLED BACK: this door does NOT set the controller's own window, because that is what would
	 * make the pair recurse. See the header. */
	_cg_windowController = windowController;
}

/* ---- THE WINDOW'S LEVEL -------------------------------------------------------------------------- */

/* SEE THE HEADER FOR WHY THE CONSTANTS' VALUES ARE OURS AND FOR WHAT A CALLER MAY RELY ON (the ORDER). The door
 * itself is a RECORD: where a window sits in the stack is the window manager's arrangement (D5), the same ground
 * `-orderWindow:relativeTo:` states for its own argument. */

/* ---- THE DOORS THIS TIER CANNOT MEET, AND THE FOUR THAT ANSWER WITHOUT APPROXIMATING --------------------------------- */

- (nullable NSData *)dataWithEPSInsideRect:(NSRect)rect
{
	(void)rect;
	fn_refuse_window("-dataWithEPSInsideRect:", "a PDF/EPS producer, which this tree's CoreGraphics has not got");
	return nil;
}

- (nullable NSData *)dataWithPDFInsideRect:(NSRect)rect
{
	(void)rect;
	fn_refuse_window("-dataWithPDFInsideRect:", "the PDF substrate, which this tree parked");
	return nil;
}

- (void)print:(id)sender
{
	(void)sender;
	fn_refuse_window("-print:", "the printing system (NSPrintOperation)");
}

- (void)dragImage:(NSImage *)anImage at:(NSPoint)baseLocation offset:(NSSize)initialOffset event:(NSEvent *)event
       pasteboard:(NSPasteboard *)pboard source:(id)sourceObj slideBack:(BOOL)slideFlag
{
	(void)anImage; (void)baseLocation; (void)initialOffset; (void)event; (void)pboard; (void)sourceObj; (void)slideFlag;
	fn_refuse_window("-dragImage:at:offset:event:pasteboard:source:slideBack:", "a drag session (the window server's drag loop)");
}

- (void)disableKeyEquivalentForDefaultButtonCell
{
	fn_refuse_window("-disableKeyEquivalentForDefaultButtonCell", "the default button cell: no NSCell in this tier");
}

- (void)enableKeyEquivalentForDefaultButtonCell
{
	fn_refuse_window("-enableKeyEquivalentForDefaultButtonCell", "the default button cell: no NSCell in this tier");
}

- (void)toggleToolbarShown:(id)sender
{
	(void)sender;
	fn_refuse_window("-toggleToolbarShown:", "NSToolbar");
}

- (void)runToolbarCustomizationPalette:(id)sender
{
	(void)sender;
	fn_refuse_window("-runToolbarCustomizationPalette:", "NSToolbar");
}

+ (void)menuChanged:(id)menu
{
	(void)menu;
	fn_refuse_window("+menuChanged:", "the application's menu system (NSMenu)");
}

- (nullable NSWindow *)initWithWindowRef:(void *)windowRef
{
	(void)windowRef;
	fn_refuse_window("-initWithWindowRef:", "CARBON, which this tree is not");
	return nil;
}

- (nullable id)handleCloseScriptCommand:(id)command
{
	(void)command;
	fn_refuse_window("-handleCloseScriptCommand:", "the scripting suite: this tree has no NSScriptCommand");
	return nil;
}

- (nullable id)handleSaveScriptCommand:(id)command
{
	(void)command;
	fn_refuse_window("-handleSaveScriptCommand:", "the scripting suite: this tree has no NSScriptCommand");
	return nil;
}

- (nullable id)handlePrintScriptCommand:(id)command
{
	(void)command;
	fn_refuse_window("-handlePrintScriptCommand:", "the scripting suite: this tree has no NSScriptCommand");
	return nil;
}

- (nullable id)fieldEditor:(BOOL)createFlag forObject:(id)anObject
{
	(void)createFlag; (void)anObject;
	fn_refuse_window("-fieldEditor:forObject:", "the text system: this tier has no NSText");
	return nil;
}

/* ---- AND THE FOUR THAT ARE NOT REFUSALS ------------------------------------------------------------------ */

- (NSInteger)gState
{
	/* A VALUE RATHER THAN A MISSING ONE: this tier draws through a `CGContext`, not a graphics-state stack, so
	 * there is no state ID to give and 0 is the truth about that. */
	return 0;
}

- (void)endEditingFor:(id)anObject
{
	/* THE CONTRACT IS ALREADY MET: there is no field editor in this tier for anything to be editing in. */
	(void)anObject;
}

- (void)useOptimizedDrawing:(BOOL)flag
{
	/* RECORDED, WITH THE EFFECT NAMED: this tier's drawing does not consult the promise, and Apple's surface has no
	 * getter for it either — so the flag is kept and read back only through the seam the probe uses. */
	_cg_useOptimizedDrawing = flag;
}

- (BOOL)cg_useOptimizedDrawing
{
	return _cg_useOptimizedDrawing;
}

- (void)registerForDraggedTypes:(NSArray *)newTypes
{
	/* RECORDED THE SAME WAY: what would consume this set is the content view's drag acceptance, in a tier with no
	 * drag session — so the set is kept and the pair reports what it was given. */
	if (_cg_registeredDraggedTypes == nil) {
		_cg_registeredDraggedTypes = [[NSMutableArray alloc] init];
	}
	[_cg_registeredDraggedTypes removeAllObjects];
	if (newTypes != nil) {
		[_cg_registeredDraggedTypes addObjectsFromArray:newTypes];
	}
}

- (void)unregisterDraggedTypes
{
	[_cg_registeredDraggedTypes removeAllObjects];
}

- (nullable NSArray *)cg_registeredDraggedTypes
{
	return _cg_registeredDraggedTypes;
}

/* ---- THE FRAME'S CONSTRAINTS: TWO PAIRS, MUTUALLY EXCLUSIVE WITHIN EACH --------------------------------- */

/* APPLE'S RULE, QUOTED IN THE HEADER AND IMPLEMENTED HERE: the aspect ratio and the resize increments are mutually
 * exclusive, and setting one CANCELS the other — the documented way to clear a ratio is to set the increments to
 * (1, 1), which is exactly the neutral increment. Nothing here constrains `-setFrame:`, because Apple's own words
 * are that a window's size can be set to any ratio programmatically. */

- (void)setResizeIncrements:(NSSize)increments
{
	_resizeIncrements = increments;
	_aspectRatio = NSMakeSize(0.0, 0.0);	/* SETTING ONE CANCELS THE OTHER */
}

- (NSSize)resizeIncrements
{
	return _resizeIncrements;
}

- (void)setAspectRatio:(NSSize)ratio
{
	_aspectRatio = ratio;
	_resizeIncrements = NSMakeSize(1.0, 1.0);	/* the neutral increment is how a ratio is cancelled */
}

- (NSSize)aspectRatio
{
	return _aspectRatio;
}

- (void)setContentResizeIncrements:(NSSize)increments
{
	_contentResizeIncrements = increments;
	_contentAspectRatio = NSMakeSize(0.0, 0.0);
}

- (NSSize)contentResizeIncrements
{
	return _contentResizeIncrements;
}

- (void)setContentAspectRatio:(NSSize)ratio
{
	_contentAspectRatio = ratio;
	_contentResizeIncrements = NSMakeSize(1.0, 1.0);
}

- (NSSize)contentAspectRatio
{
	return _contentAspectRatio;
}

/* ---- THE APPEARANCE FLAGS: RECORDED, BECAUSE THE EFFECT IS THE MANAGER'S --------------------------------- */

- (void)setAlphaValue:(CGFloat)alphaValue
{
	_alphaValue = alphaValue;
}

- (CGFloat)alphaValue
{
	return _alphaValue;
}

- (void)setOpaque:(BOOL)opaque
{
	_opaque = opaque;
}

- (BOOL)isOpaque
{
	return _opaque;
}

- (void)setHasShadow:(BOOL)hasShadow
{
	_hasShadow = hasShadow;
}

- (BOOL)hasShadow
{
	return _hasShadow;
}

- (void)setShowsResizeIndicator:(BOOL)show
{
	_showsResizeIndicator = show;
}

- (BOOL)showsResizeIndicator
{
	return _showsResizeIndicator;
}

- (void)setShowsToolbarButton:(BOOL)show
{
	_showsToolbarButton = show;
}

- (BOOL)showsToolbarButton
{
	return _showsToolbarButton;
}

/* ---- AND THE ONES THAT ANSWER RATHER THAN STORE ------------------------------------------------------- */

- (BOOL)inLiveResize
{
	/* NOTHING RESIZES THIS WINDOW LIVE: the user's drag is the window manager's in this design (D5). */
	return NO;
}

- (BOOL)isOnActiveSpace
{
	/* THE SINGLE-SPACE MODEL: there is one space, so the window is on the active one. */
	return YES;
}

- (void *)windowRef
{
	/* NULL RATHER THAN A PRETENDED REF, on the same ground `-initWithWindowRef:` refuses on. */
	return NULL;
}

- (nullable id)toolbar
{
	return nil;
}

- (nullable NSArray *)drawers
{
	/* AN EMPTY ARRAY IS APPLE'S OWN CONTRACT for a window that has no drawers, so this is an answer. */
	return [NSArray array];
}

- (nullable id)defaultButtonCell
{
	return nil;
}

- (nullable id)dockTile
{
	return nil;
}

- (nullable NSGraphicsContext *)graphicsContext
{
	/* THIS WINDOW DRAWS THROUGH A `CGContext`, not through a window graphics context — the substrate choice
	 * `NSView` records for the whole layer. */
	return nil;
}

- (nullable NSEvent *)currentEvent
{
	return nil;
}

/* ---- AND THE TWO PUBLISHED VERSION NUMBERS ------------------------------------------------------------ */

double NSAppKitVersionNumberWithCustomSheetPosition = 686.0;
double NSAppKitVersionNumberWithDeferredWindowDisplaySupport = 1019.0;


/* ---- THE REST OF THE FLAGS: RECORDED, AND THE THREE THAT ANSWER --------------------------------------- */

/* ONE PAIR PER DOOR, and a shared note rather than fourteen: the effect is the manager's or the compositor's (D5/D6),
 * so each accessor keeps its value and says nothing it cannot honour. Apple's accessor spellings are the declared
 * ones — `-isAutodisplay`, `-isFlushWindowDisabled`, `-isExcludedFromWindowsMenu`, `-isOneShot`,
 * `-isFloatingPanel`, `-isModalPanel` — because the ledger's row is answered by a declaration. */
#define FN_FLAG_PAIR(setter, getter, ivar)                       \
	- (void)setter:(BOOL)flag { ivar = flag; }               \
	- (BOOL)getter { return ivar; }

FN_FLAG_PAIR(setAllowsConcurrentViewDrawing, allowsConcurrentViewDrawing, _allowsConcurrentViewDrawing)
FN_FLAG_PAIR(setAllowsToolTipsWhenApplicationIsInactive, allowsToolTipsWhenApplicationIsInactive, _allowsToolTipsWhenApplicationIsInactive)
FN_FLAG_PAIR(setAutodisplay, isAutodisplay, _autodisplay)
FN_FLAG_PAIR(setExcludedFromWindowsMenu, isExcludedFromWindowsMenu, _excludedFromWindowsMenu)
FN_FLAG_PAIR(setOneShot, isOneShot, _oneShot)
FN_FLAG_PAIR(setReleasedWhenClosed, isReleasedWhenClosed, _releasedWhenClosed)
FN_FLAG_PAIR(setFloatingPanel, isFloatingPanel, _floatingPanel)
FN_FLAG_PAIR(setModalPanel, isModalPanel, _modalPanel)
FN_FLAG_PAIR(setWorksWhenModal, worksWhenModal, _worksWhenModal)
FN_FLAG_PAIR(setPreventsApplicationTerminationWhenModal, preventsApplicationTerminationWhenModal, _preventsApplicationTerminationWhenModal)
FN_FLAG_PAIR(setCanBecomeVisibleWithoutLogin, canBecomeVisibleWithoutLogin, _canBecomeVisibleWithoutLogin)
FN_FLAG_PAIR(setDisplaysWhenScreenProfileChanges, displaysWhenScreenProfileChanges, _displaysWhenScreenProfileChanges)
FN_FLAG_PAIR(setPreservesContentDuringLiveResize, preservesContentDuringLiveResize, _preservesContentDuringLiveResize)

/* **AND FLUSHING IS ONE STATE ACROSS TWO DOORS, WHICH IS WHY THIS ONE READS RATHER THAN STORES.** Apple spells the
 * transitions as `-disableFlushWindow` / `-enableFlushWindow` (method rows of this ledger, implemented above) and
 * the state as this getter. Implementing it with a flag of its own would give the window two answers to one
 * question the moment the pair moved — so it reports the flag the pair actually sets. The first draft of this block
 * DID carry a second flag and a duplicate implementation; the compiler caught the duplicate, which is the argument
 * for one state written in the build's own voice. */
- (BOOL)isFlushWindowDisabled
{
	return !_flushing;
}

/* ---- THE THREE THAT ARE ANSWERS ----------------------------------------------------------------------- */

- (void)setBackingType:(NSBackingStoreType)bufferingType
{
	/* APPLE'S DOOR IS READ-ONLY IN PRACTICE BUT DECLARED SETTABLE, and setting it changes what was ASKED FOR rather
	 * than what the surface already is, so the store is the request. */
	_backing = bufferingType;
}

- (NSBackingStoreType)backingType
{
	return _backing;
}

- (NSWindowBackingLocation)backingLocation
{
	/* WHERE THE STORE ACTUALLY IS, AND IT IS NOT THE SERVER'S VRAM: this tier draws the surface through a
	 * `CGContext` into an X window, so the store is in main memory. */
	return NSWindowBackingLocationMainMemory;
}

- (NSWindowBackingLocation)preferredBackingLocation
{
	return NSWindowBackingLocationMainMemory;	/* what it would use, for the same reason */
}

- (NSInteger)orderedIndex
{
	/* A PLACE IN A LIST THIS TIER DOES NOT KEEP: the manager owns the ordering (D5), so the honest answer is the
	 * position of a window in a list of one. */
	return 0;
}

- (NSUInteger)resizeFlags
{
	/* ONLY MEANINGFUL DURING A LIVE RESIZE, AND THERE IS NONE — see `-inLiveResize`. */
	return 0;
}

- (NSInteger)level
{
	return _level;
}

- (void)setLevel:(NSInteger)level
{
	_level = level;
	/* **AND THE SERVER IS TOLD, WHICH IS WHAT AN INTEGER LEVEL IS FOR.** `NSWindow`'s level is what a menu
	 * window, a status item and the Dock are ordered by, and it is an INTEGER rather than a member of a fixed
	 * set precisely so that this layer need not know which number is which — so it is passed through and never
	 * interpreted. A compositor that cannot be told keeps `_level` for itself and orders as it likes. */
	if (_agwindow != NULL) {
		AGWindowSetLevel(_agwindow, (int)level);
	}
}

- (NSURL *)representedURL
{
	return _representedURL;
}

- (void)setRepresentedURL:(NSURL *)url
{
	[url retain];
	[_representedURL release];
	_representedURL = url;
}

- (NSString *)miniwindowTitle
{
	return _miniwindowTitle;
}

- (void)setMiniwindowTitle:(NSString *)title
{
	[title retain];
	[_miniwindowTitle release];
	_miniwindowTitle = title;
}

- (NSImage *)miniwindowImage
{
	return _miniwindowImage;
}

- (void)setMiniwindowImage:(NSImage *)image
{
	[image retain];
	[_miniwindowImage release];
	_miniwindowImage = image;
}

- (void)cg_checkContentBorderEdge:(NSRectEdge)edge
{
	if (edge == NSRectEdgeMaxY && (_styleMask & NSTexturedBackgroundWindowMask) == 0) {
		[NSException raise:NSInvalidArgumentException
			    format:@"NSRectEdgeMaxY needs a TEXTURED window: Apple's rule is that a non-textured window may "
				   @"only set the content border of the BOTTOM edge, and that asking for the top one raises"];
	}
}

- (void)setContentBorderThickness:(CGFloat)thickness forEdge:(NSRectEdge)edge
{
	[self cg_checkContentBorderEdge:edge];
	_contentBorderThickness[fn_edge_index(edge)] = thickness;
}

- (CGFloat)contentBorderThicknessForEdge:(NSRectEdge)edge
{
	return _contentBorderThickness[fn_edge_index(edge)];
}

- (void)setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge
{
	[self cg_checkContentBorderEdge:edge];
	_autorecalculatesContentBorder[fn_edge_index(edge)] = flag ? YES : NO;
	if (!flag) {
		/* **THE DOCUMENTED SIDE EFFECT**: turning auto-recalculation OFF sets that edge's thickness to 0.0, which
		 * is why this door is in the same unit as the thickness pair rather than a separate one. */
		_contentBorderThickness[fn_edge_index(edge)] = 0.0;
	}
}

- (BOOL)autorecalculatesContentBorderThicknessForEdge:(NSRectEdge)edge
{
	return _autorecalculatesContentBorder[fn_edge_index(edge)];
}

- (BOOL)canHide
{
	return !_cg_refusesHide;
}

- (void)setCanHide:(BOOL)flag
{
	_cg_refusesHide = flag ? NO : YES;
}

- (BOOL)hidesOnDeactivate
{
	return _hidesOnDeactivate;
}

- (void)setHidesOnDeactivate:(BOOL)flag
{
	_hidesOnDeactivate = flag ? YES : NO;
}

- (BOOL)ignoresMouseEvents
{
	return _ignoresMouseEvents;
}

- (void)setIgnoresMouseEvents:(BOOL)flag
{
	_ignoresMouseEvents = flag ? YES : NO;
}

- (void)setAutorecalculatesKeyViewLoop:(BOOL)flag
{
	if (flag) {
		[NSException raise:NSInvalidArgumentException
			    format:@"-setAutorecalculatesKeyViewLoop: cannot promise YES: this tier's key view loop is built "
				   @"when it is first asked for and marked for a rebuild only by -recalculateKeyViewLoop, and "
				   @"nothing rebuilds it when a view is ADDED — which is what YES means"];
	}
	/* ACCEPTING NO CHANGES NOTHING, which is the honest answer to asking for what is already so. */
}

- (void)cg_ensureKeyViewLoop
{
	if (_keyViewLoop == nil) {
		[self recalculateKeyViewLoop];
	}
}

- (NSView *)cg_keyViewLoopEntry:(NSInteger)index
{
	NSInteger n;

	[self cg_ensureKeyViewLoop];
	n = (NSInteger)[_keyViewLoop count];
	if (n == 0) {
		return nil;
	}
	return [_keyViewLoop objectAtIndex:(NSUInteger)(((index % n) + n) % n)];
}

/* WHERE A VIEW IS IN THE LOOP, or NSNotFound when it is not in it at all — the case a caller gets by making
 * something else the first responder, which is why the walk starts over rather than giving up. */
- (NSInteger)cg_keyViewLoopIndexOf:(NSView *)view
{
	NSUInteger i;

	if (view == nil) {
		return NSNotFound;
	}
	[self cg_ensureKeyViewLoop];
	for (i = 0; i < [_keyViewLoop count]; i++) {
		if ([_keyViewLoop objectAtIndex:i] == view) {
			return (NSInteger)i;
		}
	}
	return NSNotFound;
}

- (void)cg_selectKeyViewAt:(NSInteger)index
{
	NSView *v = [self cg_keyViewLoopEntry:index];

	if (v != nil) {
		[self makeFirstResponder:v];
	}
}

- (void)selectNextKeyView:(id)sender
{
	NSResponder *current = [self firstResponder];
	NSInteger index;

	(void)sender;
	/* A FIRST RESPONDER THAT IS NOT A VIEW IS NOT IN THE LOOP, and neither is a view that has been removed from
	 * the tree — so both fall to the HEAD. The alternative is a Tab that silently does nothing. */
	index = [current isKindOfClass:[NSView class]] ? [self cg_keyViewLoopIndexOf:(NSView *)current] : NSNotFound;
	[self cg_selectKeyViewAt:(index == NSNotFound) ? 0 : index + 1];
	_keyViewSelectionDirection = NSSelectingNext;
}

- (void)selectPreviousKeyView:(id)sender
{
	NSResponder *current = [self firstResponder];
	NSInteger index;

	(void)sender;
	index = [current isKindOfClass:[NSView class]] ? [self cg_keyViewLoopIndexOf:(NSView *)current] : NSNotFound;
	/* BACKWARDS FROM THE HEAD WRAPS TO THE LAST, which is what makes the loop a LOOP. */
	[self cg_selectKeyViewAt:(index == NSNotFound) ? -1 : index - 1];
	_keyViewSelectionDirection = NSSelectingPrevious;
}

- (void)selectKeyViewFollowingView:(NSView *)aView
{
	/* THE SAME DOOR RELATIVE TO A GIVEN VIEW, which is what a caller that has just built a view needs: it can
	 * select the one after it without making it the first responder first. */
	[self cg_selectKeyViewAt:[self cg_keyViewLoopIndexOf:aView] + 1];
}

- (void)selectKeyViewPrecedingView:(NSView *)aView
{
	NSInteger index = [self cg_keyViewLoopIndexOf:aView];

	/* AN ABSENT VIEW GOES TO THE HEAD, as it does above — and the arithmetic is written out because NSNotFound
	 * is NSIntegerMax, whose +1 wraps to the head and whose -1 does NOT. */
	[self cg_selectKeyViewAt:(index == NSNotFound) ? -1 : index - 1];
	_keyViewSelectionDirection = NSSelectingPrevious;
}


/* ============================================================================================ *
 * WHAT THE TITLE BAR'S BUTTONS DO.                                                              *
 * ============================================================================================ */

NSString *NSWindowWillMiniaturizeNotification = @"NSWindowWillMiniaturizeNotification";
NSString *NSWindowDidMiniaturizeNotification = @"NSWindowDidMiniaturizeNotification";
NSString *NSWindowDidDeminiaturizeNotification = @"NSWindowDidDeminiaturizeNotification";

/* THE CASCADE'S OFFSET, WHICH IS OURS: Apple's cascade steps by the title bar's height, and this tree's windows
 * have no title bar of their own to measure (a window manager draws those). 22 points is the offset every
 * implementation this tree knows about uses, and stating it beats deriving it from a bar that is not here. */
/* AND THE CASCADE'S STEP IS THE TITLE BAR'S HEIGHT, READ FROM THAT ONE CONSTANT rather than written a second
 * time: Apple ties the step to the title bar (the note above says so), and two 22.0s are one number too many.
 * The use below reads `fn_TITLE_BAR` directly. */

- (void)performClose:(id)sender
{
	(void)sender;
	/* **THE WINDOW IS ASKED BEFORE IT CLOSES, WHICH IS THE WHOLE OF THIS DOOR.** Apple sends
	 * `-windowShouldClose:` to the DELEGATE and closes only if it answers YES — so a caller that wires an
	 * unsaved-changes prompt to that message gets it from the button AND from the menu item, which is why both
	 * go through here. `NSWindowDelegate` is not a protocol this tier ships, so the message is asked for BY
	 * SELECTOR rather than declared — the informal-protocol pattern used elsewhere in this tree. */
	/* **THE ASKING IS NOW A REAL PROTOCOL SEND.** `NSWindowDelegate` declares this message with its signature, so
	 * this is an ordinary checked send — the informal `NSObject` category it used to go through is gone. */
	if (_delegate != nil && [_delegate respondsToSelector:@selector(windowShouldClose:)]) {
		if (![(id <NSWindowDelegate>)_delegate windowShouldClose:self]) {
			return;	/* REFUSED — and nothing was announced and nothing changed, because a refusal is not an event */
		}
	}
	[self close];
}

- (void)miniaturize:(id)sender
{
	(void)sender;
	if (_miniaturized) {
		return;	/* already miniaturized: a second request is not an event either */
	}
	fn_announce(self, NSWindowWillMiniaturizeNotification, @selector(windowWillMiniaturize:));
	/* **THERE IS NO ICONIFY IN `xdg-shell`, AND THE STATE WAS ALREADY THIS OBJECT'S OWN.** The request used to go
	 * to a window manager; now there is nowhere to send it, and nothing is lost, because the code never read the
	 * state back from the server in the first place. */
	_miniaturized = YES;
	/* AND THE DID IS POSTED HERE rather than when a window manager finishes: there is a round trip through a WM
	 * on a desktop and none on a bare server, and a notification that arrived only on a desktop would make the
	 * door behave differently in the two places a caller cannot tell apart. */
	fn_announce(self, NSWindowDidMiniaturizeNotification, @selector(windowDidMiniaturize:));
}

- (void)deminiaturize:(id)sender
{
	(void)sender;
	if (!_miniaturized) {
		return;
	}
	if (_agwindow != NULL) {
		AGWindowShow(_agwindow);
	}
	_miniaturized = NO;
	fn_announce(self, NSWindowDidDeminiaturizeNotification, @selector(windowDidDeminiaturize:));
}

- (void)setIsMiniaturized:(BOOL)flag
{
	if (flag) {
		[self miniaturize:nil];
	} else {
		[self deminiaturize:nil];
	}
}

- (BOOL)isMiniaturized
{
	return _miniaturized;
}

- (void)performMiniaturize:(id)sender
{
	/* THE DOOR THE MINIATURIZE BUTTON AND THE MENU ITEM SEND. Apple's default implementation is `-miniaturize:`,
	 * and this calls it rather than repeating it, so a window that overrides one gets the other's behaviour. */
	[self miniaturize:sender];
}

- (NSPoint)cascadeTopLeftFromPoint:(NSPoint)topLeft
{
	NSRect visible = [[NSScreen mainScreen] visibleFrame];
	NSPoint next = NSMakePoint(topLeft.x + fn_TITLE_BAR, topLeft.y - fn_TITLE_BAR);

	[self setFrameTopLeftPoint:topLeft];
	/* THE ANSWER IS WHERE THE NEXT WINDOW GOES, and the caller feeds it straight back in. IT WRAPS AT THE BOTTOM
	 * OF THE SCREEN, which is Apple's behaviour and not a nicety: a cascade that walked off the screen would put
	 * a window where the user cannot reach it and would never come back. */
	if (visible.size.height > 0.0) {
		/* the wrap is vertical only: a cascade walks down and right, so x needs no bound here */
		if (next.y < visible.origin.y) {
			next = NSMakePoint(visible.origin.x, visible.origin.y + visible.size.height);
		}
	}
	return next;
}


/* ============================================================================================ *
 * THE CURSOR RECTS, FROM THE WINDOW'S SIDE.                                                      *
 * ============================================================================================ */

/* EVERY VIEW UNDER `v`, asked to give up its rects — the window's `-discardCursorRects` is about the whole window
 * and there is no per-view door that could say so. */
static void fn_discard_cursor_rects(NSView *v)
{
	NSArray *subs = [v subviews];
	NSUInteger i;

	if (v == nil) {
		return;
	}
	[v discardCursorRects];
	for (i = 0; i < [subs count]; i++) {
		fn_discard_cursor_rects([subs objectAtIndex:i]);
	}
}

- (void)cg_rebuildCursorRectsIfNeeded
{
	if (_cursorRectsDirty && _contentView != nil) {
		[_contentView cg_rebuildStaleCursorRects];
		_cursorRectsDirty = NO;
	}
}

/* **THE RESOLUTION, WHICH IS THE ONE THING THE POINTER'S APPEARANCE DEPENDS ON.** Nil when the rects are
 * disabled — the caller decides what that means, and the pump below shows the arrow, which is Apple's answer for
 * a window that has no opinion at the point. */
- (NSCursor *)cg_cursorForContentPoint:(NSPoint)p
{
	if (!_cursorRectsEnabled || _contentView == nil) {
		return nil;
	}
	[self cg_rebuildCursorRectsIfNeeded];
	return [_contentView cg_cursorAtPoint:p];
}

- (void)resetCursorRects
{
	/* EVERYTHING STALE, THEN THE PASS: this door says "the rects are no longer right", which is what a caller
	 * means after changing what its views show. */
	if (_contentView != nil) {
		[_contentView cg_markCursorRectsStale];
	}
	_cursorRectsDirty = YES;
	[self cg_rebuildCursorRectsIfNeeded];
}

- (void)invalidateCursorRectsForView:(NSView *)aView
{
	if (aView == nil) {
		return;
	}
	/* THE VIEW AND EVERYTHING UNDER IT, because a view that moved has moved its subviews' rects too. */
	[aView cg_markCursorRectsStale];
	_cursorRectsDirty = YES;
}

- (void)discardCursorRects
{
	fn_discard_cursor_rects(_contentView);
	_cursorRectsDirty = NO;	/* there is nothing to rebuild: every view has just said it wants nothing */
}

- (void)disableCursorRects
{
	_cursorRectsEnabled = NO;
}

/* THE SAME STATE AS THE PAIR ABOVE, reported rather than stored again. */
- (BOOL)areCursorRectsEnabled
{
	return _cursorRectsEnabled;
}

- (void)enableCursorRects
{
	_cursorRectsEnabled = YES;
	/* THE RECTS WERE NOT MAINTAINED WHILE IT WAS OFF, so the first resolution after this rebuilds them — which is
	 * the whole reason the flag can be turned off without losing them. */
	_cursorRectsDirty = YES;
}


/* ============================================================================================ *
 * TELLING THE DELEGATE.                                                                         *
 * ============================================================================================ */

NSString *NSWindowWillCloseNotification = @"NSWindowWillCloseNotification";
NSString *NSWindowWillMoveNotification = @"NSWindowWillMoveNotification";
NSString *NSWindowDidMoveNotification = @"NSWindowDidMoveNotification";
NSString *NSWindowDidResizeNotification = @"NSWindowDidResizeNotification";
NSString *NSWindowDidExposeNotification = @"NSWindowDidExposeNotification";
NSString *NSWindowDidUpdateNotification = @"NSWindowDidUpdateNotification";

/* AND THE SIX OF THIS CLASS'S ANNOUNCEMENTS THAT HAD NAMES IN THE DELEGATE PROTOCOL AND NONE HERE — see the header
 * for which two fire and why the other four cannot. Each is its own name, like every other string in this file. */
NSString *NSWindowWillBeginSheetNotification = @"NSWindowWillBeginSheetNotification";
NSString *NSWindowDidEndSheetNotification = @"NSWindowDidEndSheetNotification";
NSString *NSWindowWillStartLiveResizeNotification = @"NSWindowWillStartLiveResizeNotification";
NSString *NSWindowDidEndLiveResizeNotification = @"NSWindowDidEndLiveResizeNotification";
NSString *NSWindowDidChangeScreenNotification = @"NSWindowDidChangeScreenNotification";
NSString *NSWindowDidChangeScreenProfileNotification = @"NSWindowDidChangeScreenProfileNotification";

/* **THE RELAY, AND WHY IT IS ONE FUNCTION RATHER THAN A SEND AT EVERY SITE.** Every announcement below has the
 * same shape — `-respondsToSelector:`, then one message taking the notification — and the protocol marks them all
 * `@optional`, because a delegate that implements four of them must not be asked for the rest. Writing that guard
 * out sixteen times is sixteen chances to forget it. `-performSelector:withObject:` is used because the selector is
 * CHECKED first and every one of these takes exactly one object argument; a cast to each signature would be the
 * `-methodForSelector:` guess again, which is what declaring the protocol was meant to end. */
static void fn_tell_delegate(NSWindow *w, SEL sel, id argument)
{
	id d = [w delegate];

	if (d != nil && [d respondsToSelector:sel]) {
		[d performSelector:sel withObject:argument];
	}
}

/* AND THE ANNOUNCEMENT: **THE DELEGATE IS TOLD FIRST, THEN THE NOTIFICATION IS POSTED.** Both see the change
 * exactly once and in a fixed order, rather than depending on which registry happened to run first — and a
 * delegate that acts on the change (which several of these exist for) has done so before any observer is
 * called. */
static void fn_announce(NSWindow *w, NSString *name, SEL delegateSelector)
{
	fn_tell_delegate(w, delegateSelector, [NSNotification notificationWithName:name object:w]);
	[[NSNotificationCenter defaultCenter] postNotificationName:name object:w];
}


/* ============================================================================================ *
 * THE DEPTH LIMIT.                                                                              *
 * ============================================================================================ */

+ (NSWindowDepth)defaultDepthLimit
{
	/* APPLE STATES THIS IN ITS OWN HEADER — "NSWindowDepthTwentyfourBitRGB is the default" — and it is also the
	 * depth of the surface this window makes, so the class's answer and the window's behaviour agree by
	 * construction rather than by two people remembering the same number. */
	return NSWindowDepthTwentyfourBitRGB;
}

- (NSWindowDepth)depthLimit
{
	return _depthLimit;	/* ZERO MEANS "the default", which is the vocabulary's own reading of the value */
}

/* ---- WHICH SCREEN, AND WHICH ONE IS DEEPEST -------------------------------------------------- */

/* THE TWO SELECTIONS SHARE EVERYTHING BUT THE BASIS — AREA for `-screen`, DEPTH for `-deepestScreen` — and both
 * rules are Apple's, quoted where the doors are declared. The overlap is worked out here rather than through a rect
 * helper: three comparisons that cannot be wrong beat a guess about whether this tree's geometry has an intersection
 * function, and the same code answers the offscreen question — no overlap anywhere means no screen at all. */
- (NSScreen *)cg_dominantScreenForArea:(BOOL)byArea
{
	NSArray *screens = [NSScreen screens];
	NSScreen *best = nil;
	CGFloat bestArea = 0.0;
	NSInteger bestBits = -1;
	NSUInteger i;

	for (i = 0; i < [screens count]; i++) {
		NSScreen *s = [screens objectAtIndex:i];
		NSRect f = [s frame];
		CGFloat frameRight = _frame.origin.x + _frame.size.width;
		CGFloat frameTop = _frame.origin.y + _frame.size.height;
		CGFloat screenRight = f.origin.x + f.size.width;
		CGFloat screenTop = f.origin.y + f.size.height;
		CGFloat left = (_frame.origin.x > f.origin.x) ? _frame.origin.x : f.origin.x;
		CGFloat bottom = (_frame.origin.y > f.origin.y) ? _frame.origin.y : f.origin.y;
		CGFloat right = (frameRight < screenRight) ? frameRight : screenRight;
		CGFloat top = (frameTop < screenTop) ? frameTop : screenTop;
		CGFloat w = (right > left) ? (right - left) : 0.0;
		CGFloat h = (top > bottom) ? (top - bottom) : 0.0;
		CGFloat area = w * h;

		if (area <= 0.0) {
			continue;	/* a screen this window does not overlap is not one it is on */
		}
		if (byArea) {
			if (area > bestArea) {
				bestArea = area;
				best = s;
			}
		} else {
			NSInteger bits = NSBitsPerPixelFromDepth([s depth]);

			if (bits > bestBits) {
				bestBits = bits;
				best = s;
			}
		}
	}
	return best;
}

- (NSScreen *)screen
{
	return [self cg_dominantScreenForArea:YES];
}

- (NSScreen *)deepestScreen
{
	return [self cg_dominantScreenForArea:NO];
}

- (void)setDepthLimit:(NSWindowDepth)limit
{
	NSInteger wanted = NSBitsPerPixelFromDepth(limit);

	/* THE SURFACE IS 32 BITS PER PIXEL. A deeper limit would ask for a backing store this window cannot make, and
	 * RECORDING IT would leave a caller believing its window had the depth it asked for — so the request is
	 * refused by name and the previous limit stands. */
	if (limit != 0 && (wanted < 0 || wanted > 32)) {
		fprintf(stderr, "APPKIT-REFUSE: -setDepthLimit: asked for %d bits per pixel; this window's surface is "
				"32 and a deeper backing store is not made yet — the limit is unchanged\n", (int)wanted);
		return;
	}
	_depthLimit = limit;
}

- (void)setDynamicDepthLimit:(BOOL)flag
{
	_dynamicDepthLimit = flag ? YES : NO;
}

- (BOOL)hasDynamicDepthLimit
{
	return _dynamicDepthLimit;
}

- (void)setDocumentEdited:(BOOL)flag
{
	_documentEdited = flag ? YES : NO;
}

- (BOOL)isDocumentEdited
{
	return _documentEdited;
}

- (BOOL)isSheet
{
	return _cg_sheetParent != nil;
}

- (NSWindow *)attachedSheet
{
	return _cg_attachedSheet;
}

/* AND THE STANDARD BUTTONS, WHICH THIS TIER HAS NO OBJECTS FOR — see the header for why the answer is nil rather
 * than a refusal, and why the type is `id` rather than a forward-declared `NSButton`. What is NOT here is any
 * attempt to hand back the ellipses this file paints: they are DRAWING, not views, and a caller that got one could
 * not set an image on it anyway. */
+ (id)standardWindowButton:(NSWindowButton)b forStyleMask:(NSUInteger)styleMask
{
	(void)b;
	(void)styleMask;
	return nil;
}

- (id)standardWindowButton:(NSWindowButton)b
{
	(void)b;
	return nil;
}

@end


/* ============================================================================================ *
 * THE SHEETS — THE STATE, AND THE SEAM THE APPLICATION REACHES IT THROUGH.                      *
 * ============================================================================================ */

/* WHY THE STATE IS THIS FILE'S AND THE DOORS ARE NOT. `-isSheet` and `-attachedSheet` are questions about the
 * attachment, so they are answered where the attachment is kept; `-beginSheet:...` and `-endSheet:` are
 * NSApplication's (Apple's too) and reach this state through the seam declared in NSApplication.m — this tree's
 * pattern for a private contract crossing a file boundary, and the same shape the window registry uses.
 *
 * THE SEAM IS DELIBERATELY FOUR INERT ACCESSORS AND NOT A VERB. Nothing here begins, ends or answers anything: a
 * getter that reads, a pair of setters that record, and one door that TAKES the reply (reads it and clears it) so
 * the application can call the delegate without this file knowing that a delegate exists. What that buys is that
 * the one rule the sheet contract turns on — nothing touches the sheet after the reply runs, because the reply may
 * release it — is enforced by an ordering in ONE file, the application's, rather than by two files agreeing. */
@implementation NSWindow (APPKITSheetState)

- (void)cg_setSheetParent:(NSWindow *)parent
{
	_cg_sheetParent = parent;
}

- (NSWindow *)cg_sheetParent
{
	return _cg_sheetParent;
}

- (void)cg_setAttachedSheet:(NSWindow *)sheet
{
	_cg_attachedSheet = sheet;
}

- (void)cg_setSheetReplyDelegate:(id)delegate selector:(SEL)selector contextInfo:(void *)contextInfo
{
	_cg_sheetReplyDelegate = delegate;
	_cg_sheetReplySelector = selector;
	_cg_sheetContextInfo = contextInfo;
}

/* ANSWERS NO WHEN THERE IS NOBODY TO TELL — a session begun with a nil delegate or no selector — which is what
 * makes `-beginSheet:...` with a nil delegate legal rather than a crash at the end of it. */
- (BOOL)cg_takeSheetReplyDelegate:(id *)delegate selector:(SEL *)selector contextInfo:(void **)contextInfo
{
	if (_cg_sheetReplyDelegate == nil || _cg_sheetReplySelector == NULL) {
		return NO;
	}
	*delegate = _cg_sheetReplyDelegate;
	*selector = _cg_sheetReplySelector;
	*contextInfo = _cg_sheetContextInfo;
	_cg_sheetReplyDelegate = nil;
	_cg_sheetReplySelector = NULL;
	_cg_sheetContextInfo = NULL;
	return YES;
}

@end
