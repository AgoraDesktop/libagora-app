/*
 * NSWindow — a window on Agora's window server, and the geometry between two coordinate systems.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * **WHAT IS NOT HERE, AND WHY — CORRECTED, BECAUSE FOUR OF THESE ARRIVED AFTER THE LIST WAS WRITTEN.** The SHEETS
 * (their state is this file's; `-beginSheet:modalForWindow:...` and `-endSheet:returnCode:` are `NSApplication`'s),
 * the FRAME-AUTOSAVE strings, the CURSOR-RECT invalidation and the CHILD-WINDOW list are all implemented now, and
 * the screen is `NSScreen`'s own row and is measured with it. THE TOOLBAR IS HERE: `-setToolbar:` attaches one,
 * the frame-to-content arithmetic reserves its band, and the chrome's fourth mark toggles it. What remains absent: the
 * DRAWER (the class) and the SCRIPT-COMMAND handling, which refuses by name. The minimisable/closable BUTTONS are
 * a window manager's (Kestrel is parked). Each of those is absent rather than stubbed.
 */
#include "AGWindowServer.h"
#import "NSWindow_internal.h"
#import "AGChromeTheme.h"	/* the chrome's control graphics, when an XFWM theme resolves */
#import "NSToolbar.h"
#import "NSToolbar_internal.h"	/* the band's height and view, and the toolbar's own seam */

#include <math.h>	/* sqrt — how far a two-point diagonal reaches past its centreline */

#import "AppKitRefusal.h"
#import "NSDockMenu.h"	/* the dock menu's description, which this window carries out for the application */
#import "NSDocument.h"
#import "NSMenu.h"
#import <CoreGraphics/CGBitmapContext.h>

#include <objc/runtime.h>	/* the drawer list's association */

#import <AppKit/NSWindow.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSTrackingArea.h>

/* **THE DRAWER SYNC IS DECLARED HERE RATHER THAN IN THE PUBLIC HEADER.** It is the window's half of a relationship
 * `NSDrawer` owns — the layout rule and the list live in `NSDrawer.m` — and the doors below are the only callers. A
 * `cg_` selector in the header would be a third party's business with a class it does not own, and it would move the
 * 10.6 census for an internal seam. */
@interface NSWindow (AGDrawerUpdates)
- (void)cg_updateDrawers;
- (void)cg_raiseForDrawer;
- (BOOL)cg_isDrawerWindow;
@end
#import <AppKit/NSColor.h>
#import <AppKit/NSColorSpace.h>
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
#import <AppKit/NSCell.h>	/* NS_CELL_BEZEL_WIDTH — the one border width every control in this tier wears */
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

/* **THE SEAM'S STAMP ON AN EVENT: WHERE ITS TIMESTAMP CAME FROM, AND WHOSE KEYBOARD TENURE IT BELONGS TO.** A
 * category rather than three public setters — the values are the compositor's, and this file is the one that has them. */
@interface NSEvent (AGSeamStamp)
- (void)cg_setSourceTimestamp:(unsigned int)source_time hasSourceTimestamp:(BOOL)has focusSerial:(unsigned int)serial;
@end

@interface NSWindow ()
/* **AND THE PLACEMENT RULE, WHICH IS `NSApplication`'S BECAUSE THE SESSION IS.** A sheet hangs from the bottom edge of
 * its parent's title bar, centred on the parent's content — a rule about two windows, so it lives beside the doors
 * that make the pair rather than in this file. Declared here because the door that has to re-apply it on every move
 * and resize is `-setFrame:display:`, three thousand lines below the sheet's state. */
- (void)cg_updateSheet;
- (NSInteger)cg_clickCountFor:(NSPoint)p at:(NSTimeInterval)now;
- (NSInteger)currentClickCount;
/* THE SEAM'S DOORS AND THE STATE THEY KEEP, declared here for the same reason. */
- (void)cg_handleSeamEvent:(const AGEvent *)event;
- (void)cg_drawFrame;
- (void)cg_drawFrameDirty:(const NSRect *)damage count:(NSUInteger)count;
- (void)cg_drawDragGuideInContext:(CGContextRef)c;
/* **WHAT THE COMPOSITOR'S FRAME CALLBACK ASKS FOR — AND WHY IT IS NOT JUST `-cg_drawFrame`.** The callback says
 * the last frame was taken; it is an INVITATION to draw again, not an instruction. A window with nothing new to
 * show must DECLINE, or the client draws, commits, is asked again, and drives the whole desktop in a busy loop:
 * MEASURED at 517 composites a second, which is lag a person feels. This door declines when the window is not
 * stale. */
- (void)cg_frameCallback;
- (BOOL)cg_mouseButtonDown;
- (BOOL)cg_ensureWindow;
/* **THE DOOR A STATUS ITEM COMES IN BY, and it is here rather than in `NSStatusItem.m` because the seam is this
 * file's business: a status item needs the window's `AGWindow` and nothing else does. */
- (void)cg_setStatusItemLength:(CGFloat)length;
- (NSEvent *)cg_nextEventWaiting:(BOOL)wait milliseconds:(long)ms mask:(NSUInteger)mask
				dequeue:(BOOL)dequeue;
/* THE CURSOR DOORS THIS FILE ADDS, declared here because this is the file that defines them. */
- (void)cg_setPointerGrab:(BOOL)flag;
/* **AND THE ONE A DRAG USES, WHICH IS A REAL GRAB — see `-cg_setPointerCapture` for why the two differ.** */
- (void)cg_setPointerCapture:(BOOL)flag;
- (void)cg_setDocumentCloseApproved:(BOOL)flag;
/* AND WHETHER THERE IS A COMPOSITOR TO MAKE A WINDOW ON AT ALL, which is the question a drag image's floating
 * window has to ask before ordering itself in: with none, the session runs without an image rather than printing a
 * refusal for a window that could never be shown. */
+ (BOOL)cg_hasWindowServer;
/* **AND THE THREE THAT MAKE THE CONNECTION ONE OF THE RUN LOOP'S SOURCES.** Declared here because the source's target
 * lives in this file (see `AGConnectionSource`) and because the application's loop reads the seam's deadline; the
 * first two answer WITHOUT CONNECTING, so a loop asking about a descriptor cannot open one. */
+ (int)cg_connectionFd;
+ (long)cg_nextDeadlineMs;
+ (BOOL)cg_dispatchPending;
/* **AND THE SEAM'S OWN WINDOW, FOR THE ONE QUESTION ONLY A DIAGNOSTIC ASKS**: what did the last commit tell the
 * compositor it changed (`AGWindowLastDamage`)? The handle is this class's private business, so the door that hands
 * it out is too. */
- (AGWindow *)cg_seamWindow;
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
- (void)cg_updateTrackingIfMovedToPoint:(NSPoint)windowPoint;
- (void)cg_clearTracking;
/* **AND THE DRAG'S MOVE, MADE ONCE PER PASS AT THE LATEST POINTER RATHER THAN PER EVENT.** The window is moved to
 * the pointer, so applying every motion inside a frame would walk it along the sampled PATH — a fast flick's
 * intermediate points — instead of straight to where the hand is. */
- (void)cg_applyPendingDrag;
/* **AND THE RESIZE'S OWN, MADE ONCE PER PASS FOR THE SAME REASON.** A drag that resizes is a drag like any other:
 * the hand's intermediate points are not frames, and the pass applies the latest one. */
- (void)cg_applyPendingResize;
/* AND THE FRAME A RESIZE IS AIMING AT, FROM THE POINTER'S OWN POSITION — which is where the delegate is asked. */
- (NSRect)cg_frameForResizeToPoint:(NSPoint)globalPoint;
/* **AND THE BOOKKEEPING FOR A SEAM THAT ALTERNATES TWO BUFFERS.** Which buffer a frame is about to be drawn into,
 * which slot that buffer owns, and what it is missing — see the note on `_cg_paintMissing` in `NSWindow.h`. */
- (NSInteger)cg_paintSlotForPixels:(void *)pixels;
- (NSInteger)cg_claimPaintSlotForPixels:(void *)pixels;
- (void)cg_recordPaintInSlot:(NSInteger)slot rect:(NSRect)painted;
- (void)cg_addPaintRect:(NSRect)rect to:(NSRect *)out count:(NSUInteger *)count;
- (NSRect)cg_deviceOutward:(NSRect)rect;
- (NSRect)cg_wholeFrameRect;
- (NSRect)cg_chromeRect;
- (NSRect)cg_titleBarRect;
/* **AND THE ONE THING THAT MARKS THE CHROME'S INK STALE.** `-setNeedsDisplay:` is the general door (the window itself
 * changed); the setters that change a title or an edited dot call this one because they used to change the state and
 * mark NOTHING, which left the old title on the bar until an unrelated repaint. */
- (void)cg_invalidateChrome;
/* **AND THE ONE COPY THE TWO-BUFFER SEAM MAKES WORTH TAKING.** The frame on the glass holds the pixels for everything a
 * scroll did not change, so a scrolled region is moved rather than drawn: see `-cg_scrollContentInRect:inView:by:` in
 * `NSWindow.m` for what is recorded and `AGWindowPreviousFrameSized` for the read. */
- (BOOL)cg_copyRect:(NSRect)rect from:(const uint32_t *)previous stride:(int)previousStride delta:(NSSize)delta;
/* **AND WHERE A CHROME BUTTON IS, in WINDOW coordinates.** The painter and the pointer ask the one function, so
 * a hovered button cannot be a different rectangle from a drawn one. */
- (NSInteger)cg_chromeButtonAtPoint:(NSPoint)windowPoint;
/* **AND WHAT A BUTTON DOES, WHICH IS THE THIRD PART OF THAT ONE ANSWER.** The rectangles are `fn_chrome_layout`'s and
 * the pressed state is the pointer's; this is the ACTION, and it goes through the `-perform…` doors rather than the
 * bare ones so that a DELEGATE's refusal reaches a click on the chrome exactly as it reaches the menu item beside
 * it — a window whose document has unsaved changes must not close because a hand found the X. */
- (void)cg_performChromeButton:(NSInteger)index;
@end

/* The engine's doors into an area and into the event it builds: declared in every file that uses them and DEFINED by
 * the class that owns the storage — this tree's shape for a `cg_` door that is the tier's own business rather than
 * anybody's API. */
@interface NSView (AGDirtyUnion)
- (NSRect)cg_dirtyUnion;
- (void)cg_clearDirtyRegionRecursive;
/* **AND THE SAME DAMAGE AS A LIST, WHICH IS WHAT THE PAINT CONSUMES.** The union above is the bounding box and is still
 * what the ledger and the machinery's "is anything dirty" questions use; the list is what gets DRAWN, so a strip at one
 * edge and a knob beside it are two small pieces rather than the area between them. */
- (void)cg_dirtyRegionRecursive:(NSRect *)out max:(NSUInteger)max count:(NSUInteger *)outCount;
@end

@interface NSTrackingArea (APPKITTrackingEngine)
- (BOOL)cg_isInside;
- (void)cg_setInside:(BOOL)flag;
@end

@interface NSEvent (APPKITTrackingEngine)
- (void)cg_setTrackingArea:(NSTrackingArea *)area;
@end

/* **AND THE POINTER'S ABSOLUTE POSITION, WHICH A TITLE-BAR DRAG MEASURES AGAINST.** The same shape as the door
 * above: a private pair on `NSEvent`, declared wherever it is used and defined by the class that owns the storage. */
@interface NSEvent (APPKITGlobalPoint)
- (void)cg_setGlobalPoint:(NSPoint)point;
- (NSPoint)cg_globalPoint;
- (BOOL)cg_hasGlobalPoint;
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
/* THE APPLICATION'S TWO ANSWERS, kept in step with this window's own `_key`/`_main` flags by the doors below. */
- (void)cg_setKeyWindow:(NSWindow *)aWindow;
- (void)cg_setMainWindow:(NSWindow *)aWindow;
/* **AND THE ONE THAT IS NOT ABOUT THIS WINDOW AT ALL.** A shell's reopen ask arrives at a window because window ids
 * are the only names the two sides share, but the answer belongs to the application. */
- (BOOL)cg_handleReopen;
/* **AND THE TWO A DOCK TILE'S MENU ARRIVES THROUGH, which cross the same way and for the same reason.** The menu is
 * the delegate's answer to `-applicationDockMenu:`, so the APPLICATION is what holds it — a window is only the address
 * the question arrived at and the thing that has a connection to answer on. */
- (nullable id)cg_dockMenu;
- (void)cg_performDockMenuItem:(NSInteger)identifier;
@end

/* **A FRAME'S POINT IS PLACED AT THE POINT IT IS NEAREST, WHICH IS ROUNDING AND NOT TRUNCATION.** A Cocoa frame is
 * arithmetic and its origin is very often fractional — an alert's computed height is 109.6 points, so a sheet whose
 * top is the parent's title-bar bottom lands on a fraction — and `(int)` truncates it, which moves the window UP by up
 * to a point and, worse, does it by a DIFFERENT amount for the two windows of a pair. MEASURED on a sheet: the sheet's
 * top edge came out one row above the parent's content, so the border the sheet wears across itself (see
 * `fn_draw_chrome`) met the parent's own border one row apart — a one-pixel jog in the one line the tuck exists to make
 * continuous. Rounding is the honest reading of "where is this edge on the device": the nearest row, for the sheet and
 * its parent alike.
 *
 * THE Y IS FLIPPED AND THEN ROUNDED, not rounded and then flipped, because the two are not the same: the display
 * measures down from the top and Cocoa measures up from the bottom, so the flip is where the fraction enters, and the
 * nearest row of the FLIPPED coordinate is what the compositor places. */
static int fn_device_point(CGFloat value)
{
	return (int)floor((double)value + 0.5);
}

/* THE TITLE BAR'S HEIGHT, AND IT IS OURS. A titled window's FRAME is its content plus its chrome, and this
 * tree draws no title bar yet (Kestrel, which will, is parked) — so the number is this file's, stated here
 * rather than discovered: it is where the chrome and this arithmetic will have to agree. A borderless window
 * has no chrome and adds nothing. */
static const CGFloat fn_TITLE_BAR = 22.0;
/* **AND THE CHROME'S OWN MEASURES, WHICH ARE FOUR NUMBERS AND A SET OF MARKS.** What the strip's height leaves is
 * the size of a SYMBOL BOX and how far apart the boxes sit, the strip's own edge padding, and the marks themselves —
 * which are GREYBIRD'S, at GREYBIRD'S sizes, because that is the look this chrome is. Everything else about the
 * chrome — where the symbols start, how much room a title has, what `+minFrameWidthWithTitle:styleMask:` owes them —
 * is DERIVED from these rather than written a third and fourth time, which is what this file used to do. */
static const CGFloat fn_SYMBOL = 11.0;		/* the box ONE drawn mark lives in */
static const CGFloat fn_SYMBOL_GAP = 9.0;	/* between one symbol's box and the next */
static const CGFloat fn_CHROME_EDGE = 8.0;	/* the strip's own padding, at either end */

/* **THE MARK'S OWN BOX, INSIDE THE ELEVEN-POINT ONE.** These are the theme's measures and not this file's taste:
 * every one of its four button pictures is twenty by twenty-four with the mark in columns 6..13 and rows 9..17 — a
 * mark EIGHT POINTS WIDE and NINE TALL, whose strokes are TWO points thick — so those are the numbers here. The
 * four boxes are all one size now: the toolbar toggle wears the theme's own MENU mark, a filled triangle eight by
 * six, where this chrome used to draw a pill of its own invention at the far end. A mark that is not one of the
 * theme's is a mark that does not belong on its bar.
 *
 * **AND THE FOURTH BOX IS ONLY DRAWN WHEN THE WINDOW HAS A TOOLBAR** — `fn_chrome_button_present` decides, and the
 * size below is the size for the windows that get it. */
static const CGFloat fn_MARK_WIDTH = 8.0;	/* the mark, across */
static const CGFloat fn_MARK_HEIGHT = 9.0;	/* the X's and the minus's; the plus is eight and the triangle six */
static const CGFloat fn_MARK_CHEVRON = 6.0;
static const CGFloat fn_MARK_STROKE = 2.0;	/* the theme's two points, where this file used to draw three */

/* **THE CHROME'S OWN GEOMETRY: SIX-POINT TOP CORNERS AND A ONE-POINT OUTLINE.** Six is the window's SHAPE and not
 * only its decoration: the compositor clips every window to a rounded rectangle and draws its shadow around the same
 * one, and `AWS_SHADOW_RADIUS` in `window-server/src/output.c` is this number's copy — the protocol does not carry a
 * radius, so the two components each state it and they have to be changed together. A decoration whose corners are
 * one radius and a window whose shape is another is a window that looks drawn on rather than cut out.
 *
 * AND IT IS NOT THE CONTROL BEZEL'S RADIUS. `NS_CELL_BEZEL_RADIUS` is four: a push button is a small thing and a
 * window is not, and the two agreed at five and at four only because they happened to.
 *
 * THERE IS NO OUTLINE ALONG THE BOTTOM, because the content's hairline is already the boundary there and a second
 * line a point above it would be two boundaries where the window has one. */
static const CGFloat fn_BAR_RADIUS = 6.0;
static const CGFloat fn_BAR_BORDER = 1.0;

/* **AND THE TUCK: HOW FAR A SHEET'S TOP EDGE SITS INSIDE ITS PARENT'S TITLE BAR.** A sheet placed FLUSH with the bar's
 * bottom edge meets it along a line that two independently rounded frames can disagree about by a device row — at a
 * fractional scale the bar's own bottom line can show through as a one-pixel seam across the sheet, which is exactly the
 * ledge the tuck exists to remove. Two points is the hairline's one plus a point of slack; it is INVISIBLE because the
 * sheet's body is painted in the chrome's own colour (`-cg_bodyColor`), and it is what makes the sheet read as coming
 * out from under the bar: the bar's bottom hairline stops at the sheet's two sides instead of running across it.
 *
 * A PARENT WITH NO TITLE BAR HAS NOTHING TO TUCK UNDER, so the answer is zero there — overlapping a borderless
 * window's CONTENT with a strip of chrome-coloured body would be a band across its document.
 *
 * It is a door rather than a file-static because the placement rule (`NSApplication -cg_updateSheet`) and the compositor's
 * shadow clip (which must not paint on the bar the tuck covers) both need the same number, and two copies of it could
 * disagree about the row a shadow stops at. */
static const CGFloat fn_SHEET_TUCK = 2.0;

/* **AND ITS PALETTE, SAMPLED FROM THE THEME'S ART RATHER THAN CHOSEN.** Each value is the colour that fills the most
 * pixels of the matching `.xpm`: `#939393` the outline along the top and down the ends, `#797979` the body of a mark on
 * a key window, `#BFBFBF` the faded one on a window that is not, `#4B4B4B` the darker one under the pointer, and
 * `#6897BC` the BLUE one under a press — which is the theme's own answer to "this is happening now" and is the one
 * mark colour here that is not a grey. The two light values are the one-point row that sits UNDER every mark and is
 * what makes a mark read as pressed into the bar rather than printed on it; it is the reason every mark is drawn
 * twice, once a point low in this ink and once in its own.
 *
 * THE BAR'S FACE IS NOT HERE, because it is not this file's alone: `+cg_chromeFaceColor` is the one surface the title
 * bar and the toolbar band share. */
static const CGFloat fn_BAR_EDGE = 0.576;	/* #939393 */

/* TEMPORARY: a wall-clock millisecond, so a click and the paint it caused can be put on one timeline. */
static const CGFloat fn_MARK_INK = 0.475;	/* #797979 */
static const CGFloat fn_MARK_FAINT = 0.749;	/* #BFBFBF */
static const CGFloat fn_MARK_HOVER = 0.294;	/* #4B4B4B */
static const CGFloat fn_MARK_LIGHT = 0.898;	/* #E5E5E5 */
static const CGFloat fn_MARK_LIGHT_FAINT = 0.925; /* #ECECEC */
static const CGFloat fn_MARK_PRESS_RED = 0x68 / 255.0;	/* #6897BC */
static const CGFloat fn_MARK_PRESS_GREEN = 0x97 / 255.0;
static const CGFloat fn_MARK_PRESS_BLUE = 0xBC / 255.0;

/* **AND THE HAIRLINE BETWEEN THE CHROME AND THE CONTENT WEARS THE CONTROL BEZEL'S GREY** — `+controlDarkShadowColor`,
 * the same 0.737 that strokes a push button's bezel, a checkbox's box, a field's edge and a slider's track. It sits at
 * the CONTENT'S TOP EDGE, which is below the toolbar band when a window has one: the chrome includes the toolbar, so
 * the boundary is below everything the window owns and not between the title bar and the band.
 *
 * IT WAS BLACK, AND BLACK WAS THE WRONG KIND OF LINE. Every other edge on this desktop is that one grey — a control's
 * border, a field's, a groove's — and a hard black rule between two light surfaces read as a shadow the window does
 * not otherwise have. The hairline is the BOTTOM OF THE CHROME, not a division between two colours: after the chrome
 * and the toolbar became one surface it is the only line left there, so it is drawn in the ink the tier uses for
 * exactly that. IT IS STILL DRAWN LAST, so a theme's buttons cannot paint over it. */

/* ============================================================================================ *
 * THE CHROME'S THEME, AND WHY THE HEIGHT IS A FUNCTION NOW.                                     *
 *                                                                                                *
 * **A WINDOW'S CHROME IS EITHER THE THEME'S OR THIS FILE'S, AND THE HEIGHT DECIDES WHICH.** When   *
 * an XFWM theme resolves (see `AGChromeTheme`) the strip takes the THEME'S height and its buttons  *
 * are the theme's bitmaps at their own size — 1:1, no scaling — and when none does, everything     *
 * below is the bar and the marks THIS FILE DRAWS at `fn_TITLE_BAR`, in Greybird's own measures.     *
 * is a CLASS method with no window to ask, which is why the theme is a process-wide singleton: one  *
 * answer for every window in the process, which is what a theme is.                                *
 *                                                                                                *
 * WHERE EACH BUTTON IS lives in ONE place, `fn_chrome_layout`, because the painter and the pointer  *
 * must not be able to disagree about where a button is — a hovered button that is not the drawn one *
 * is exactly the defect two copies of this arithmetic produces.                                     *
 * ============================================================================================ */
static CGFloat fn_title_bar_height(void)
{
	CGFloat themed = AGChromeThemeTitleBarHeight();

	return (themed > 0.0) ? themed : fn_TITLE_BAR;
}

/* **AND A SHEET HAS NO CHROME AT ALL, WHICH IS THE ONE THING A STYLE MASK CANNOT SAY.** On the Mac a sheet's title bar
 * is not drawn because the WINDOW SERVER does not give a sheet one — it is the parent's title bar the sheet hangs
 * from, and the sheet's own top edge is that title bar's bottom edge. Here the chrome is the client's (the window
 * server draws no title bar at all: see `agora-shell.xml`), so the same rule has to be stated on this side: a sheet's
 * frame IS its content, so its content fills the surface and `-cg_drawChromeInContext:` has no strip to paint.
 *
 * THE STYLE MASK STAYS WHAT THE CALLER MADE, which is Apple's behaviour too: an `NSAlert`'s panel is built titled and
 * closable and reports that afterwards, and the sheet is a MODE the window is in rather than a change to what it was
 * built as. That is why this is an instance question and the class pair below cannot answer it. */
static CGFloat fn_chrome_height(NSWindow *w)
{
	if ([w isSheet]) {
		return 0.0;
	}
	return ([w styleMask] & NSTitledWindowMask) ? fn_title_bar_height() : 0.0;
}

/* **THE BAND THE TOOLBAR TAKES, ASKED OF THE TOOLBAR.** This is the one function that relates the window's frame
 * arithmetic to `NSToolbar`, and it answers zero for no toolbar and for a hidden one — so every caller below can add
 * it unconditionally and a window without a toolbar keeps the geometry it always had. */
static CGFloat fn_toolbar_height(NSWindow *w)
{
	NSToolbar *toolbar = [w toolbar];

	if (toolbar == nil || ![toolbar isVisible]) {
		return 0.0;
	}
	return [toolbar cg_toolbarHeight];
}

typedef struct {
	NSRect rects[AGChromeButtonCount];	/* window coordinates: origin at the window's bottom-left */
	BOOL present[AGChromeButtonCount];
	CGFloat height;
	CGFloat leftBlock;			/* how much width the left buttons take, from x = 0 */
	CGFloat rightBlock;			/* and the menu's, from the right edge */
} fn_chrome_layout_t;

/* WHICH ABILITIES THE STYLE MASK ASKS FOR, which is Apple's rule and not the theme's: a titled-but-not-closable
 * window has no close to offer, so it gets no X — or no bitmap either. */
static BOOL fn_chrome_button_present(NSWindow *w, AGChromeButton button)
{
	NSUInteger mask = [w styleMask];

	/* **AND A SHEET WEARS NO BUTTONS AT ALL**, which follows from having no strip to put them on: the traffic light of
	 * an alert belongs to the window the alert is ON, and a sheet with an X of its own is a sheet that looks like a
	 * second window stuck to the first. Asked first so the style-mask rule below never has to know about sheets. */
	if ([w isSheet]) {
		return NO;
	}

	switch (button) {
	case AGChromeButtonClose:    return (mask & NSClosableWindowMask) != 0;
	case AGChromeButtonHide:     return (mask & NSMiniaturizableWindowMask) != 0;
	case AGChromeButtonMaximize: return (mask & NSResizableWindowMask) != 0;
	/* **AND THE PILL IS THERE ONLY WHEN THERE IS A TOOLBAR FOR IT TO TOGGLE.** It is the toolbar's button — the one
	 * mark in the strip that is not about the window — so a window with no toolbar was drawing a control whose only
	 * action was a no-op (`-toggleToolbarShown:` with nothing attached), which is a mark that promises something the
	 * window cannot do. A WINDOW THAT HAS ONE KEEPS IT WHETHER THE BAND IS SHOWING OR NOT, because hiding a toolbar
	 * is not the same as not having one: the pill is how the band comes back.
	 *
	 * `-showsToolbarButton` is the second half of the same question and Apple's own property — a window that sets it
	 * NO wants the pill gone with the toolbar still attached, which is a caller choosing to reach the band from a
	 * menu instead. It defaults to YES in `-initWithContentRect:…`, which is Apple's default too. */
	case AGChromeButtonMenu:
		return (mask & NSTitledWindowMask) != 0 && [w toolbar] != nil && [w showsToolbarButton];
	default:                     return NO;
	}
}

static void fn_chrome_layout(NSWindow *w, fn_chrome_layout_t *layout)
{
	NSRect content = [w contentRectForFrameRect:[w frame]];
	AGChromeTheme *theme = [AGChromeTheme sharedTheme];
	CGFloat width = content.size.width;
	/* THE STRIP'S BOTTOM IS THE TOOLBAR'S TOP WHEN THERE IS ONE, so the title bar never paints over the band. The
	 * content rect no longer contains the toolbar (see `-contentRectForFrameRect:`), which is why the height is added
	 * back here rather than assumed to be zero. */
	CGFloat top = content.size.height + fn_toolbar_height(w);
	int i;

	memset(layout, 0, sizeof *layout);
	/* **AND A BORDERLESS WINDOW HAS NO CHROME AND SO NO HEIGHT** — which is the same rule `+fn_chromeForStyleMask:`
	 * applies to the frame arithmetic, and the two MUST agree, because this height is what the painter fills and
	 * what the hairline's guard reads. It was `fn_title_bar_height()` unconditionally, which is 22 (or the theme's
	 * height) for a BORDERLESS window too: the strip fill landed above the window and was clipped away, so nothing
	 * showed — but the hairline did not, and drew a dark row across the top of a MENU'S own window. **AND A SHEET IS
	 * THE SECOND KIND OF WINDOW WITH NO STRIP**, for the reason `fn_chrome_height` gives. */
	layout->height = fn_chrome_height(w);
	for (i = 0; i < AGChromeButtonCount; i++) {
		layout->present[i] = fn_chrome_button_present(w, (AGChromeButton)i);
	}

	if (theme != NULL) {
		NSSize button = [theme buttonSize];
		CGFloat offset = [theme buttonOffset];
		CGFloat spacing = [theme buttonSpacing];
		CGFloat x = offset;
		CGFloat y = floor(top + (layout->height - button.height) / 2.0);

		layout->leftBlock = offset;
		for (i = 0; i < AGChromeButtonCount - 1; i++) {	/* close, hide, maximize: the left block */
			if (!layout->present[i]) {
				continue;
			}
			layout->rects[i] = NSMakeRect(x, y, button.width, button.height);
			x += button.width + spacing;
			layout->leftBlock = x - spacing;
		}
		if (layout->present[AGChromeButtonMenu]) {
			layout->rects[AGChromeButtonMenu] = NSMakeRect(width - offset - button.width, y,
								       button.width, button.height);
			layout->rightBlock = offset + button.width;
		} else {
			layout->rightBlock = offset;
		}
	} else {
		CGFloat x = fn_CHROME_EDGE;
		CGFloat y = floor(top + (layout->height - fn_SYMBOL) / 2.0);

		layout->leftBlock = fn_CHROME_EDGE;
		for (i = 0; i < AGChromeButtonCount - 1; i++) {
			if (!layout->present[i]) {
				continue;
			}
			layout->rects[i] = NSMakeRect(x, y, fn_SYMBOL, fn_SYMBOL);
			x += fn_SYMBOL + fn_SYMBOL_GAP;
			layout->leftBlock = x - fn_SYMBOL_GAP;
		}
		if (layout->present[AGChromeButtonMenu]) {
			layout->rects[AGChromeButtonMenu] = NSMakeRect(width - fn_CHROME_EDGE - fn_SYMBOL, y,
								       fn_SYMBOL, fn_SYMBOL);
			layout->rightBlock = fn_CHROME_EDGE + fn_SYMBOL;
		} else {
			layout->rightBlock = fn_CHROME_EDGE;
		}
	}
}

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

/* **THE COMPOSITOR'S `/`YOU HAVE THE KEYBOARD`/` IS THE APPLICATION'S ACTIVE STATE**, and this is the one place it
 * is turned into the application's own pair. The seam says which CLIENT has the keyboard (per client, so a second
 * window of this application taking focus is not a change), and \"active\" is exactly that — the application in
 * front, whose menu bar is the one on the screen. The handler is registered when the connection is made because
 * the application cannot be told before it can be talked to. */
static void fn_activation(void *context, int active)
{
	NSApplication *app = [NSApplication sharedApplication];

	(void)context;
	if (active) {
		[app activate];
	} else {
		[app deactivate];
	}
}

/* **THE PASSIVE DOOR: THE CONNECTION IF THERE IS ONE, AND NOTHING IF THERE IS NOT.** Anything reachable from a
 * zero-time poll or a nonblocking query has to answer WITHOUT connecting, because discovery does round trips and a
 * query that blocks is not a query. */
static AGWindowServer *fn_server_if_connected(void)
{
	return s_server;
}

/* **THE CONNECTION'S RUN-LOOP TARGET, AND IT IS ONE OBJECT FOR THE PROCESS.** A run loop holds a source's target
 * WEAKLY (see `-addSourceForFileDescriptor:`), and the connection outlives every window, so the target cannot be a
 * window or the application: it is this singleton, and its whole body is "take what the compositor said".
 *
 * THE SOURCE IS INSTALLED WHERE THE CONNECTION IS MADE, not where an application's loop starts. That is the point of
 * the change: ANY wait on this thread's run loop now services the compositor — an application's frame, a library
 * caller's `-runUntilDate:`, a modal session, a `-performSelector:afterDelay:` — instead of only the one door that
 * used to poll the descriptor. A reconnect is a different descriptor, so it is re-registered rather than watched
 * twice (which would deliver every event twice). */
@interface AGConnectionSource : NSObject
- (void)connectionReadable;
@end

@implementation AGConnectionSource

- (void)connectionReadable
{
	(void)[NSWindow cg_dispatchPending];
}

@end

static AGConnectionSource *s_connection_source;
static int s_connection_source_fd = -1;

static void fn_install_connection_source(void)
{
	NSRunLoop *loop;
	int fd;

	if (s_server == NULL) {
		return;
	}
	/* **THE LOOP THAT MATTERS IS THE MAIN THREAD'S.** A source is registered on the calling thread's loop and the
	 * loop's own arrays are not locked, so a connection made on a worker thread cannot register one safely — and
	 * would not be serviced anyway, because the loop an application runs is the main thread's. The connection is
	 * still usable; it is served by whichever wait the program actually runs. */
	if (![NSThread isMainThread]) {
		return;
	}
	fd = AGWindowServerGetFd(s_server);
	if (fd < 0 || fd == s_connection_source_fd) {
		return;		/* nothing to watch, or the same descriptor already watched */
	}
	loop = [NSRunLoop currentRunLoop];
	if (s_connection_source == nil) {
		s_connection_source = [[AGConnectionSource alloc] init];
	}
	if (s_connection_source_fd >= 0) {
		[loop removeSourceForTarget:s_connection_source];
	}
	[loop addSourceForFileDescriptor:fd
				    mode:NSDefaultRunLoopMode
				readable:YES
				  target:s_connection_source
				selector:@selector(connectionReadable)];
	s_connection_source_fd = fd;
}

static AGWindowServer *fn_server(void)
{
	if (s_server == NULL) {
		s_server = AGWindowServerShared();
		if (s_server != NULL) {
			AGWindowServerSetActivationHandler(s_server, fn_activation, NULL);
			fn_install_connection_source();
		}
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

/* **THE POINTER'S ABSOLUTE POSITION RIDES WITH THE EVENT, NOT ON THE WINDOW.** A single "latest" value is read
 * after the seam has already advanced past the press — MEASURED: the grab was recorded at the FINAL pointer, so the
 * window jumped to the origin on the first motion — and attaching it to the event is what pairs the two. The output
 * measures DOWN and Cocoa UP, so the y is flipped here, once. */
static NSEvent *fn_with_global(NSEvent *ev, const AGEvent *e)
{
	if (ev != nil && e->has_global) {
		CGFloat screen_height = [[NSScreen mainScreen] frame].size.height;

		if (screen_height > 0.0) {
			[ev cg_setGlobalPoint:NSMakePoint((CGFloat)e->global_x,
							  screen_height - (CGFloat)e->global_y)];
		}
	}
	return ev;
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
		return fn_with_global([NSEvent mouseEventWithType:t location:where modifierFlags:flags
					 timestamp:now windowNumber:win context:nil
					 eventNumber:(NSInteger)e->time_ms
					  clickCount:count pressure:1.0f], e);
	}
	case AGEventPointerMotion: {
		BOOL dragging = [w cg_mouseButtonDown];

		/* **THE CURSOR IS RESOLVED HERE, BEFORE THE EARLY RETURN BELOW** — because it is the USER's information
		 * rather than the application's: Apple updates it on a move the application never sees, and a window that
		 * only changed its cursor when it also wanted `-mouseMoved:` would leave the wrong one showing for every
		 * window that did not ask for that message. The arrow is the answer when no view has an opinion. */
		/* **A DRAG OWNS THE CURSOR.** Resolving it through the view tree on every motion is both wrong while a
		 * divider or a split view is dragging (that owner has already pushed its resize cursor) and ruinously
		 * expensive in a browser with hundreds of columns; the hover answer is only for a move with no button. */
		if (!dragging) {
			NSCursor *c = [w cg_cursorForContentPoint:where];

			[(c != nil ? c : [NSCursor arrowCursor]) set];
		}
		/* **AND THE TRACKING ENGINE RUNS HERE, ABOVE THE EARLY RETURN, WHICH IS THE WHOLE POINT OF PUTTING IT FIRST.**
		 * `-acceptsMouseMovedEvents` decides whether a bare move becomes an `NSEvent` for the responder chain, and an
		 * area's enter and exit are NOT gated on it — an AppKit button prelights in a window that never asked for
		 * `-mouseMoved:`. The engine is handed the position and the event is not built until the return below lets it
		 * through. MEASURED, when this lived under that line: a pointer resting on a button in an ordinary window
		 * changed nothing at all. */
		[w cg_updateTrackingIfMovedToPoint:where];
		/* A MOVE WITH NO BUTTON IS DELIVERED ONLY IF THE WINDOW ASKED FOR IT — see the header. */
		if (!dragging && ![w acceptsMouseMovedEvents]) {
			return nil;
		}
		return fn_with_global([NSEvent mouseEventWithType:(dragging ? NSLeftMouseDragged : NSMouseMoved)
					  location:where modifierFlags:flags
					 timestamp:now windowNumber:win context:nil
					 eventNumber:(NSInteger)e->time_ms
					  clickCount:0 pressure:1.0f], e);
	}
	case AGEventPointerAxis: {
		/* **ONE NOTCH IS FIFTEEN UNITS IN THE COMPOSITOR'S SCALE, AND ONE LINE HERE.** The seam hands over the
		 * compositor's distance — where a wheel notch is 15.0 and a finger's movement is a fraction of one — and
		 * Cocoa's `-deltaX`/`-deltaY` count in wheel LINES, one per notch. Dividing by the same constant the server
		 * multiplies by is what makes the two ends agree; doing it anywhere else would be a second answer to "how
		 * big is a notch".
		 *
		 * **AND THE SIGNS ARE OPPOSITE, SO THEY ARE TURNED ROUND ONCE, HERE.** The protocol's positive vertical
		 * distance is DOWN and its positive horizontal is RIGHT; Cocoa's positive `-deltaY` is UP and its positive
		 * `-deltaX` is LEFT. A client that had to know this would have it wrong in half its handlers. */
		CGFloat lines = (CGFloat)(e->delta / 15.0);

		return [NSEvent cg_scrollEventWithDeltaX:(e->axis == AGAxisHorizontal ? -lines : 0.0)
						  deltaY:(e->axis == AGAxisVertical ? -lines : 0.0)
						location:where
				   modifierFlags:flags
				       timestamp:now
				    windowNumber:win];
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
		/* **AND WHETHER THIS IS A REPEAT IS THE SEAM'S ANSWER, NOT A CONSTANT.** A held key produces more presses
		 * than the hardware sent — the client generates them, honouring the compositor's `repeat_info` — and this
		 * line used to hard-code NO, which made every generated repeat look like a fresh press: `-isARepeat` would
		 * answer NO for all of them, which is the difference between a key being held and a key being typed twice,
		 * and is what a find panel or a nudge-with-arrows control checks. */
		{
			NSEvent *key = [NSEvent keyEventWithType:(e->modifier ? NSFlagsChanged
									 : (e->pressed ? NSKeyDown : NSKeyUp))
						 location:where modifierFlags:flags
						timestamp:now windowNumber:win context:nil
					       characters:chars
				  charactersIgnoringModifiers:chars
					      isARepeat:(e->repeat ? YES : NO)
						keyCode:(unsigned short)e->keycode];

			/* **AND THE TWO FACTS `-timestamp` CANNOT CARRY.** The translation time above is this process's; the
			 * source time and the keyboard tenure are the compositor's, and they are what a nonblocking
			 * confirmation asks about — "was this queued before my dialog appeared?", "was this pair interrupted by
			 * the keyboard leaving?". */
			[key cg_setSourceTimestamp:e->source_time_ms hasSourceTimestamp:(e->has_source_time ? YES : NO)
				       focusSerial:e->focus_serial];
			return key;
		}
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
	/* NOT `-cg_drawFrame`: a frame callback is an invitation, and a window with nothing new to draw must
	 * decline it or the desktop becomes a busy loop. See `-cg_frameCallback`. */
	[w cg_frameCallback];
}

/* ---- AND A DOCK TILE'S MENU, WHICH ARRIVES AT A WINDOW AND IS ANSWERED BY THE APPLICATION ------------- */

/* **A SHELL IS ASKING FOR THIS APPLICATION'S DOCK MENU, AND A WINDOW IS ONLY THE ADDRESS.** The menu is the
 * delegate's answer to `-applicationDockMenu:`, so the application builds it and keeps it — the ids that come back
 * name rows in THAT tree — and this window's only part is carrying the description out on the connection it owns.
 *
 * **AN APPLICATION ALWAYS ANSWERS, EVEN WITH NOTHING TO SAY.** The Dock is holding a panel open for this answer, so
 * no menu is the empty description and not silence; a client that never answered would leave the Dock waiting out its
 * timeout for a right-click that could have been drawn immediately. */
static void fn_dock_menu_request(void *context, AGWindow *window)
{
	NSMenu *menu = [[NSApplication sharedApplication] cg_dockMenu];
	NSString *description = [NSDockMenu cg_descriptionForMenu:menu];

	(void)context;
	AGWindowSetDockMenu(window, description != nil ? [description UTF8String] : "");
}

/* **AND THE PERSON CHOSE ONE OF THE ROWS THIS APPLICATION PUBLISHED.** The id is the one the description gave it, so
 * the application is what turns it back into an `NSMenuItem` and sends its action — which is why the seam says
 * nothing about what a menu means. */
static void fn_dock_menu_action(void *context, AGWindow *window, int item)
{
	(void)context;
	(void)window;
	[[NSApplication sharedApplication] cg_performDockMenuItem:(NSInteger)item];
}

/* **THE WINDOW'S HALF OF THE DOCUMENT'S CLOSE REVIEW.** The window asks its controller's document before it closes;
 * the answer arrives through this object, and a YES sets the approved flag and starts a second `-performClose:` pass
 * that goes on to the window delegate. The window is retained so a sheet that outlives the first pass still has one
 * to close. */
@interface AGWindowCloseReview : NSObject
{
@public
	NSWindow *_window;	/* RETAINED */
}
- (instancetype)initWithWindow:(NSWindow *)window;
- (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo;
@end

@implementation AGWindowCloseReview

- (instancetype)initWithWindow:(NSWindow *)window
{
	self = [super init];
	if (self != nil) {
		_window = [window retain];
	}
	return self;
}

- (void)dealloc
{
	[_window release];
	[super dealloc];
}

- (void)document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
{
	(void)document;
	(void)contextInfo;
	if (shouldClose) {
		[_window cg_setDocumentCloseApproved:YES];
		[_window performClose:nil];
	}
}

@end

@implementation NSWindow

/* ============================================================================================
 * ARCHIVING: THE DESIGN SUBSET OF A WINDOW, AND THE LONGER LIST OF THINGS THAT ARE NOT IN IT.
 * ============================================================================================ */

/* **A WINDOW HAS 116 IVARS AND ABOUT THIRTY OF THEM ARE A DESIGN.** The rest are the surface, the pixel buffer, the
 * compositor handle, the chrome drag and resize state, the event queue, the sheet linkage and the two cached click
 * samples — all state of a window that is RUNNING, none of it a property a design file can state. They are absent by
 * construction rather than by omission, and that is why a decoded window opens its OWN surface instead of pointing at
 * the archiver's address space.
 *
 * **WHAT IS NOT ARCHIVED AND HAS A NAME:** `_delegate` (an object with behaviour, not a design), `_windowController`
 * (the controller owns the window, not the other way round), `_firstResponder` and `_initialFirstResponder` (a focus
 * RING is a runtime walk and a first responder is who has the keyboard NOW), `_toolbar` (a toolbar's items are a
 * delegate's answers), `_fieldEditor` (owned by the window and re-made on demand), and `_documentEdited` (a fact about a
 * document's saved state, which a freshly decoded window has not got). `_delegate` in particular is the one a nib
 * normally DOES wire — and it is wired as a CONNECTION, which is the vocabulary `NSNib.h` publishes. */
static NSString * const AGCoderWindowFrameKey = @"frame";
static NSString * const AGCoderWindowStyleMaskKey = @"styleMask";
static NSString * const AGCoderWindowBackingKey = @"backingType";
static NSString * const AGCoderWindowTitleKey = @"title";
static NSString * const AGCoderWindowMinSizeKey = @"minSize";
static NSString * const AGCoderWindowMaxSizeKey = @"maxSize";
static NSString * const AGCoderWindowContentMinSizeKey = @"contentMinSize";
static NSString * const AGCoderWindowContentMaxSizeKey = @"contentMaxSize";
static NSString * const AGCoderWindowLevelKey = @"level";
static NSString * const AGCoderWindowHasShadowKey = @"hasShadow";
static NSString * const AGCoderWindowOpaqueKey = @"opaque";
static NSString * const AGCoderWindowAlphaKey = @"alphaValue";
static NSString * const AGCoderWindowShowsResizeKey = @"showsResizeIndicator";
static NSString * const AGCoderWindowResizeIncrementsKey = @"resizeIncrements";
static NSString * const AGCoderWindowAspectRatioKey = @"aspectRatio";
static NSString * const AGCoderWindowContentIncrementsKey = @"contentResizeIncrements";
static NSString * const AGCoderWindowContentAspectKey = @"contentAspectRatio";
static NSString * const AGCoderWindowReleasedWhenClosedKey = @"releasedWhenClosed";
static NSString * const AGCoderWindowHidesOnDeactivateKey = @"hidesOnDeactivate";
static NSString * const AGCoderWindowExcludedFromWindowsMenuKey = @"excludedFromWindowsMenu";
static NSString * const AGCoderWindowFrameAutosaveKey = @"frameAutosaveName";
static NSString * const AGCoderWindowRepresentedURLKey = @"representedURL";
static NSString * const AGCoderWindowRepresentedFilenameKey = @"representedFilename";
static NSString * const AGCoderWindowCollectionBehaviorKey = @"collectionBehavior";
static NSString * const AGCoderWindowAcceptsMouseMovedKey = @"acceptsMouseMovedEvents";
static NSString * const AGCoderWindowAutodisplayKey = @"autodisplay";
static NSString * const AGCoderWindowIgnoresMouseKey = @"ignoresMouseEvents";
static NSString * const AGCoderWindowMovableKey = @"movable";
static NSString * const AGCoderWindowMovableByBackgroundKey = @"movableByWindowBackground";
static NSString * const AGCoderWindowWorksWhenModalKey = @"worksWhenModal";
static NSString * const AGCoderWindowFloatingPanelKey = @"floatingPanel";
static NSString * const AGCoderWindowOneShotKey = @"oneShot";
static NSString * const AGCoderWindowShowsToolbarButtonKey = @"showsToolbarButton";
static NSString * const AGCoderWindowPreservesContentKey = @"preservesContentDuringLiveResize";
static NSString * const AGCoderWindowBackgroundColorKey = @"backgroundColor";
static NSString * const AGCoderWindowContentViewKey = @"contentView";
static NSString * const AGCoderWindowToolbarKey = @"toolbar";

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[super encodeWithCoder:aCoder];

	[aCoder encodeRect:_frame forKey:AGCoderWindowFrameKey];
	[aCoder encodeInteger:(NSInteger)_styleMask forKey:AGCoderWindowStyleMaskKey];
	[aCoder encodeInteger:(NSInteger)_backing forKey:AGCoderWindowBackingKey];
	[aCoder encodeObject:_title forKey:AGCoderWindowTitleKey];
	[aCoder encodeSize:_minSize forKey:AGCoderWindowMinSizeKey];
	[aCoder encodeSize:_maxSize forKey:AGCoderWindowMaxSizeKey];
	[aCoder encodeSize:_contentMinSize forKey:AGCoderWindowContentMinSizeKey];
	[aCoder encodeSize:_contentMaxSize forKey:AGCoderWindowContentMaxSizeKey];
	[aCoder encodeInteger:_level forKey:AGCoderWindowLevelKey];
	[aCoder encodeBool:_hasShadow forKey:AGCoderWindowHasShadowKey];
	[aCoder encodeBool:_opaque forKey:AGCoderWindowOpaqueKey];
	[aCoder encodeDouble:(double)_alphaValue forKey:AGCoderWindowAlphaKey];
	[aCoder encodeBool:_showsResizeIndicator forKey:AGCoderWindowShowsResizeKey];
	[aCoder encodeSize:_resizeIncrements forKey:AGCoderWindowResizeIncrementsKey];
	[aCoder encodeSize:_aspectRatio forKey:AGCoderWindowAspectRatioKey];
	[aCoder encodeSize:_contentResizeIncrements forKey:AGCoderWindowContentIncrementsKey];
	[aCoder encodeSize:_contentAspectRatio forKey:AGCoderWindowContentAspectKey];
	[aCoder encodeBool:_releasedWhenClosed forKey:AGCoderWindowReleasedWhenClosedKey];
	[aCoder encodeBool:_hidesOnDeactivate forKey:AGCoderWindowHidesOnDeactivateKey];
	[aCoder encodeBool:_excludedFromWindowsMenu forKey:AGCoderWindowExcludedFromWindowsMenuKey];
	[aCoder encodeObject:_frameAutosaveName forKey:AGCoderWindowFrameAutosaveKey];
	[aCoder encodeObject:_representedURL forKey:AGCoderWindowRepresentedURLKey];
	[aCoder encodeObject:_representedFilename forKey:AGCoderWindowRepresentedFilenameKey];
	[aCoder encodeInteger:(NSInteger)_cg_collectionBehavior forKey:AGCoderWindowCollectionBehaviorKey];
	[aCoder encodeBool:_acceptsMouseMoved forKey:AGCoderWindowAcceptsMouseMovedKey];
	[aCoder encodeBool:_autodisplay forKey:AGCoderWindowAutodisplayKey];
	[aCoder encodeBool:_ignoresMouseEvents forKey:AGCoderWindowIgnoresMouseKey];
	[aCoder encodeBool:_cg_movableByBackground forKey:AGCoderWindowMovableByBackgroundKey];
	[aCoder encodeBool:_worksWhenModal forKey:AGCoderWindowWorksWhenModalKey];
	[aCoder encodeBool:_floatingPanel forKey:AGCoderWindowFloatingPanelKey];
	[aCoder encodeBool:_oneShot forKey:AGCoderWindowOneShotKey];
	[aCoder encodeBool:_showsToolbarButton forKey:AGCoderWindowShowsToolbarButtonKey];
	[aCoder encodeBool:_preservesContentDuringLiveResize forKey:AGCoderWindowPreservesContentKey];
	[aCoder encodeObject:_backgroundColor forKey:AGCoderWindowBackgroundColorKey];
	[aCoder encodeObject:_contentView forKey:AGCoderWindowContentViewKey];
	[aCoder encodeObject:_toolbar forKey:AGCoderWindowToolbarKey];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	NSRect frame;
	NSUInteger mask = 0;
	NSBackingStoreType backing = NSBackingStoreBuffered;

	/* **THE DESIGNATED INITIALISER RUNS FIRST, AND THAT IS DELIBERATE.** `-initWithContentRect:styleMask:backing:defer:`
	 * is where a window's defaults, its surface and its content view are made — decode-time must not re-implement that,
	 * because a second copy is a second place for the two to disagree. The archived properties are applied ON TOP, which
	 * is also why the frame is set twice: once as the content rect the initialiser needs, once as the frame the file
	 * actually said. */
	frame = [aDecoder decodeRectForKey:AGCoderWindowFrameKey];
	if ([aDecoder containsValueForKey:AGCoderWindowStyleMaskKey]) {
		mask = (NSUInteger)[aDecoder decodeIntegerForKey:AGCoderWindowStyleMaskKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowBackingKey]) {
		backing = (NSBackingStoreType)[aDecoder decodeIntegerForKey:AGCoderWindowBackingKey];
	}
	self = [self initWithContentRect:frame styleMask:mask backing:backing defer:NO];
	if (self == nil) {
		return nil;
	}
	/* THE RESPONDER HALF. `-initWithContentRect:…` chains to `NSResponder -init`, which does not run a decode, so the
	 * archived interface style and context menu are applied here rather than being silently defaulted. */
	{
		NSResponder *responder = [[NSResponder alloc] initWithCoder:aDecoder];

		if (responder != nil) {
			[self setInterfaceStyle:[responder interfaceStyle]];
			[self setMenu:[responder menu]];
			[responder release];
		}
	}
	[self setFrame:frame display:NO];

	if ([aDecoder containsValueForKey:AGCoderWindowTitleKey]) {
		[self setTitle:[aDecoder decodeObjectForKey:AGCoderWindowTitleKey]];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowMinSizeKey]) {
		_minSize = [aDecoder decodeSizeForKey:AGCoderWindowMinSizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowMaxSizeKey]) {
		_maxSize = [aDecoder decodeSizeForKey:AGCoderWindowMaxSizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowContentMinSizeKey]) {
		_contentMinSize = [aDecoder decodeSizeForKey:AGCoderWindowContentMinSizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowContentMaxSizeKey]) {
		_contentMaxSize = [aDecoder decodeSizeForKey:AGCoderWindowContentMaxSizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowLevelKey]) {
		_level = [aDecoder decodeIntegerForKey:AGCoderWindowLevelKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowHasShadowKey]) {
		_hasShadow = [aDecoder decodeBoolForKey:AGCoderWindowHasShadowKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowOpaqueKey]) {
		_opaque = [aDecoder decodeBoolForKey:AGCoderWindowOpaqueKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowAlphaKey]) {
		_alphaValue = (CGFloat)[aDecoder decodeDoubleForKey:AGCoderWindowAlphaKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowShowsResizeKey]) {
		_showsResizeIndicator = [aDecoder decodeBoolForKey:AGCoderWindowShowsResizeKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowResizeIncrementsKey]) {
		_resizeIncrements = [aDecoder decodeSizeForKey:AGCoderWindowResizeIncrementsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowAspectRatioKey]) {
		_aspectRatio = [aDecoder decodeSizeForKey:AGCoderWindowAspectRatioKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowContentIncrementsKey]) {
		_contentResizeIncrements = [aDecoder decodeSizeForKey:AGCoderWindowContentIncrementsKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowContentAspectKey]) {
		_contentAspectRatio = [aDecoder decodeSizeForKey:AGCoderWindowContentAspectKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowReleasedWhenClosedKey]) {
		_releasedWhenClosed = [aDecoder decodeBoolForKey:AGCoderWindowReleasedWhenClosedKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowHidesOnDeactivateKey]) {
		_hidesOnDeactivate = [aDecoder decodeBoolForKey:AGCoderWindowHidesOnDeactivateKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowExcludedFromWindowsMenuKey]) {
		_excludedFromWindowsMenu = [aDecoder decodeBoolForKey:AGCoderWindowExcludedFromWindowsMenuKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowFrameAutosaveKey]) {
		_frameAutosaveName = [[aDecoder decodeObjectForKey:AGCoderWindowFrameAutosaveKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowRepresentedURLKey]) {
		_representedURL = [[aDecoder decodeObjectForKey:AGCoderWindowRepresentedURLKey] retain];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowRepresentedFilenameKey]) {
		_representedFilename = [[aDecoder decodeObjectForKey:AGCoderWindowRepresentedFilenameKey] copy];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowCollectionBehaviorKey]) {
		_cg_collectionBehavior = (NSUInteger)[aDecoder decodeIntegerForKey:AGCoderWindowCollectionBehaviorKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowAcceptsMouseMovedKey]) {
		_acceptsMouseMoved = [aDecoder decodeBoolForKey:AGCoderWindowAcceptsMouseMovedKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowAutodisplayKey]) {
		_autodisplay = [aDecoder decodeBoolForKey:AGCoderWindowAutodisplayKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowIgnoresMouseKey]) {
		_ignoresMouseEvents = [aDecoder decodeBoolForKey:AGCoderWindowIgnoresMouseKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowMovableByBackgroundKey]) {
		_cg_movableByBackground = [aDecoder decodeBoolForKey:AGCoderWindowMovableByBackgroundKey];
		_cg_movableByBackgroundSet = YES;
	}
	if ([aDecoder containsValueForKey:AGCoderWindowWorksWhenModalKey]) {
		_worksWhenModal = [aDecoder decodeBoolForKey:AGCoderWindowWorksWhenModalKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowFloatingPanelKey]) {
		_floatingPanel = [aDecoder decodeBoolForKey:AGCoderWindowFloatingPanelKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowOneShotKey]) {
		_oneShot = [aDecoder decodeBoolForKey:AGCoderWindowOneShotKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowShowsToolbarButtonKey]) {
		_showsToolbarButton = [aDecoder decodeBoolForKey:AGCoderWindowShowsToolbarButtonKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowPreservesContentKey]) {
		_preservesContentDuringLiveResize = [aDecoder decodeBoolForKey:AGCoderWindowPreservesContentKey];
	}
	if ([aDecoder containsValueForKey:AGCoderWindowBackgroundColorKey]) {
		_backgroundColor = [[aDecoder decodeObjectForKey:AGCoderWindowBackgroundColorKey] retain];
	}
	/* AND THE CONTENT VIEW LAST, THROUGH `-setContentView:`, because that door is what puts it on screen and hands it the
	 * window — the same reason a view's children go through `-addSubview:`. */
	if ([aDecoder containsValueForKey:AGCoderWindowContentViewKey]) {
		id view = [aDecoder decodeObjectForKey:AGCoderWindowContentViewKey];

		if ([view isKindOfClass:[NSView class]]) {
			[self setContentView:view];
		}
	}
	/* THE TOOLBAR LAST, THROUGH `-setToolbar:`, which is the door that makes the band and tells the toolbar its
	 * window; a toolbar decoded into an ivar would be attached to nothing. */
	if ([aDecoder containsValueForKey:AGCoderWindowToolbarKey]) {
		id toolbar = [aDecoder decodeObjectForKey:AGCoderWindowToolbarKey];

		if ([toolbar isKindOfClass:[NSToolbar class]]) {
			[self setToolbar:toolbar];
		}
	}
	return self;
}

+ (BOOL)supportsSecureCoding
{
	return YES;
}

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

/* **AND THE MENU BAR'S COLOUR, AS A COLOUR RATHER THAN AS THREE BYTES.** The server owns the strip and says what
 * colour it is; this turns that into the `NSColor` both the bar window's background and a dropdown's panel are
 * filled with, so the two cannot drift — MEASURED, they had: the strip was 235 and the panel a 251-to-236 ramp, so a
 * menu was lighter than the bar it hung from. THE FALLBACK IS THE BAR'S SAMPLED FACE (235,235,235), for a process
 * with no compositor to ask. */
+ (NSColor *)cg_menuBarColor
{
	AGWindowServer *server = [NSWindow cg_sharedServer];
	unsigned int rgb = 0;

	if (server != NULL) {
		AGWindowServerMenuBarColour(server, &rgb);
	}
	if (rgb == 0u) {
		return [NSColor colorWithCalibratedRed:0.9215686 green:0.9215686 blue:0.9215686 alpha:1.0];
	}
	return [NSColor colorWithCalibratedRed:(CGFloat)((rgb >> 16) & 0xFFu) / 255.0
					green:(CGFloat)((rgb >> 8) & 0xFFu) / 255.0
					 blue:(CGFloat)(rgb & 0xFFu) / 255.0
					alpha:1.0];
}

/* **AND THE FLAG, WHICH IS ALL THIS DOOR DOES.** `-display` paints now and returns early if the compositor still
 * holds the previous buffer — leaving the flag set, so the run loop's `-displayIfNeeded` tries again next pass.
 * A CALLER THAT WANTS THE PAINT TO HAPPEN NOW calls `-displayIfNeeded` after this, which is the pair the menu's
 * repaint uses. */
- (void)setNeedsDisplay:(BOOL)flag
{
	_viewsNeedDisplay = flag ? YES : NO;
	/* **AND IT DELIBERATELY DOES NOT TOUCH THE CHROME'S FLAG.** This door is "the whole window may be stale" — a
	 * background colour, a theme, anything a caller cannot name more precisely — and it must keep meaning that: with no
	 * view damage it lands on the whole-frame path, which paints the chrome too. The chrome-specific cases are the ones
	 * that call `-cg_invalidateChrome`, so the strip is repainted when its ink changed and NOT on every content pass,
	 * which is the whole point of owning the flag. */
}

- (void)cg_invalidateChrome
{
	_cg_chromeDirty = YES;
	_viewsNeedDisplay = YES;
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

/* **AND WHAT THE PAINTER ACTUALLY FILLS WITH, WHICH IS A DIFFERENT QUESTION FOR ONE KIND OF WINDOW.** See the header:
 * a sheet's body is the chrome's face, so that its top edge and the title bar it hangs from are one colour and the sheet
 * reads as emerging from under the bar. Every other window answers exactly what `-backgroundColor` says, which is why
 * this is a door of its own rather than a change to that one: `-backgroundColor` is the CALLER's answer, and a sheet is
 * not being asked to keep a colour it was given — it is being painted as part of a bar. */
- (NSColor *)cg_bodyColor
{
	if ([self isSheet]) {
		return [NSColor cg_chromeFaceColor];
	}
	return [self backgroundColor];
}

/* See `fn_SHEET_TUCK`: how far a sheet on THIS window is tucked into its title bar. */
- (CGFloat)cg_sheetTuck
{
	return [self hasTitleBar] ? fn_SHEET_TUCK : 0.0;
}

/* THE STYLE MASK'S CHROME, which is the frame-to-content arithmetic and its inverse. Both directions exist
 * because both are asked for, and they are written as one pair so a change to the title-bar height cannot
 * make them disagree. */
/* **AND THE HEIGHT IS THE THEME'S WHEN ONE RESOLVES**, because 1:1 means the strip is as tall as the theme's own
 * art; with no theme it is this file's constant, which is where it always was. */
+ (CGFloat)fn_chromeForStyleMask:(NSUInteger)styleMask
{
	return (styleMask & NSTitledWindowMask) ? fn_title_bar_height() : 0.0;
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

/* **THE INSTANCE PAIR OWNS THE TOOLBAR'S BAND; THE CLASS PAIR CANNOT.** A class method has no toolbar to ask, and
 * Apple's own pair has the same limitation. The instance pair is what every geometry door in this file uses, so the
 * content view, the min/max constraint conversion and the title bar all see one answer: the content rect excludes
 * the chrome AND the toolbar while the toolbar is visible.
 *
 * **AND IT IS THE INSTANCE PAIR THAT KNOWS ABOUT SHEETS**, for the same reason it is the instance pair that knows about
 * toolbars: being somebody's sheet is not a property of the style mask. A sheet's content is its whole frame, and a
 * sheet with a toolbar band would be a sheet with a strip of chrome above its content that the window server does not
 * give it — so the band is dropped too. */
- (NSRect)contentRectForFrameRect:(NSRect)frameRect
{
	CGFloat chrome = fn_chrome_height(self);
	CGFloat toolbar = [self isSheet] ? 0.0 : fn_toolbar_height(self);
	NSRect content = NSMakeRect(frameRect.origin.x, frameRect.origin.y,
				    frameRect.size.width, frameRect.size.height - chrome);

	content.size.height -= toolbar;
	if (content.size.height < 0.0) {
		content.size.height = 0.0;
	}
	return content;
}

- (NSRect)frameRectForContentRect:(NSRect)contentRect
{
	NSRect frame = NSMakeRect(contentRect.origin.x, contentRect.origin.y,
				  contentRect.size.width, contentRect.size.height + fn_chrome_height(self));

	frame.size.height += [self isSheet] ? 0.0 : fn_toolbar_height(self);
	return frame;
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
	/* AND THE PILL IS THE TOOLBAR'S, SO IT IS ON UNTIL SOMEBODY SAYS OTHERWISE — Apple's own default for
	 * `-showsToolbarButton`. It only has anything to show on a window that HAS a toolbar: see
	 * `fn_chrome_button_present`. */
	_showsToolbarButton = YES;
	/* NO BUTTON IS UNDER THE POINTER AND NONE IS PRESSED, which -1 says: index 0 is a real button. */
	_cg_hoverChrome = -1;
	_cg_pressedChrome = -1;
	_cg_resizeEdges = 0;
	_cg_resizePending = NO;
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
	_defaultButtonCell = nil;
	_colorSpace = nil;
	_preferredBackingLocation = NSWindowBackingLocationMainMemory;
	_orderedIndex = 0;
	_canBeVisibleOnAllSpaces = NO;
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

/* **THE SCREEN FORM.** This tier has one screen, so the content rect is already in the space that screen lives in;
 * the initialiser accepts the screen (a caller porting a multi-screen layout gets a real signature), places the
 * window where the rect says, and does not invent a second placement rule for a screen it cannot choose between. */
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
			     screen:(NSScreen *)screen
{
	(void)screen;
	return [self initWithContentRect:contentRect styleMask:styleMask backing:bufferingType defer:flag];
}

- (void)dealloc
{
	/* **THE RELATIONSHIPS END BEFORE THE WINDOW DOES, AND TWO OF THEM WERE LEAKING.** `_cg_childWindows` was never
	 * released at all, and a child that survived its parent kept a pointer to a window that no longer existed — the
	 * next `-orderOut:` on it would reach freed memory. The drawers come first because detaching one takes its child
	 * window out of `_cg_childWindows`, so the list is stable by the time the remaining children are walked. */
	{
		/* A COPY: `-setParentWindow:nil` removes the drawer from this window's list as it goes. */
		NSArray *drawers = [self drawers];
		NSUInteger i;

		for (i = 0; i < [drawers count]; i++) {
			[[drawers objectAtIndex:i] setParentWindow:nil];
		}
	}
	{
		NSUInteger i;

		for (i = 0; i < [_cg_childWindows count]; i++) {
			[[_cg_childWindows objectAtIndex:i] cg_setParentWindow:nil];
		}
		[_cg_childWindows release];
		_cg_childWindows = nil;
	}
	/* **AND THE SHEET LINKAGE ENDS WITH EITHER SIDE, WHICH IS THE ONE INVARIANT THE PAIR CANNOT BE LEFT WITHOUT.** Neither
	 * reference is retained (see `NSWindow.h`: the application's registry owns every window, and an attachment that
	 * retained would be a cycle), so a window that is freed while the other end still names it leaves a pointer into
	 * freed memory — and the walks that reach it are the ordinary ones: a `displayIfNeeded`, a pointer motion resolving a
	 * cursor. MEASURED, as a `SIGSEGV` inside `-[NSView cg_dirtyRegionRecursive:…]` and inside
	 * `-[NSView cg_rebuildStaleCursorRects]` when a sheet's owner died a run-loop pass after the sheet was attached.
	 * Breaking it from BOTH ends here is what makes "a sheet whose parent is gone is an ordinary window" and "a parent
	 * whose sheet is gone has no sheet" true even when the caller got the two lifetimes wrong. */
	if (_cg_sheetParent != nil) {
		NSWindow *parent = _cg_sheetParent;

		_cg_sheetParent = nil;
		[parent cg_setAttachedSheet:nil];
	}
	if (_cg_attachedSheet != nil) {
		NSWindow *sheet = _cg_attachedSheet;

		_cg_attachedSheet = nil;
		[sheet cg_setSheetParent:nil];
	}
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
	[_defaultButtonCell release];
	[_colorSpace release];
	[_representedURL release];
	[_miniwindowTitle release];
	[_miniwindowImage release];
	[_cg_registeredDraggedTypes release];
	[_keyViewLoop release];
	[_fieldEditor release];
	/* AND THE CONTENT VIEW, WHICH THE WINDOW RETAINED WHEN IT WAS SET. It was leaked here while the window owned it:
	 * a window is the content view's only owner, so nothing else can release it. */
	[_contentView release];
	/* AND THE TOOLBAR, WHICH THE WINDOW OWNS. Its own `-cg_setWindow:nil` is what takes its view out of the content
	 * tree; releasing it here is safe because nothing else retains it after this window goes. */
	[_toolbar release];
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
		/* **THE TITLE IS BOLD, AND THE DOOR THAT SAYS BOLD IS THE ONE READ FOR IT.** `+titleBarFontOfSize:` is answered
		 * with Core Text's `kCTFontWindowTitleFontType`, which names WHERE a font is used and says nothing about how
		 * heavy it is; a design that asks for a bold title is asking about WEIGHT, and the door whose own name is the
		 * weight is `+boldSystemFontOfSize:` — answered here with `kCTFontEmphasizedSystemFontType`, EMPHASIZED being
		 * what bold is called in this vocabulary. The SIZE still comes from the title-bar door, so each door is read
		 * for the one thing it knows. A title-bar font that will not answer leaves the emphasized default size. */
		NSFont *titleBarFont = [NSFont titleBarFontOfSize:(CGFloat)0.0];
		NSFont *font = [NSFont boldSystemFontOfSize:(titleBarFont != nil) ? [titleBarFont pointSize] : (CGFloat)0.0];
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
static CGFloat fn_title_baseline(CGFloat top, CGFloat ascent, CGFloat descent)
{
	return top + (fn_title_bar_height() - (ascent - descent)) / 2.0 - descent;
}

/* ============================================================================================ *
 * THE BAR AND ITS MARKS ARE GREYBIRD'S, DRAWN AS VECTORS RATHER THAN COPIED AS ART.              *
 *                                                                                                *
 * **THE THEME THIS LOOK COMES FROM CANNOT SHIP, SO THE LOOK IS DRAWN HERE INSTEAD.** Greybird's  *
 * button pictures are somebody else's work under a GPL, and a theme is readable at runtime but    *
 * not part of this library (`AGChromeTheme` carries that argument in full) — which leaves two    *
 * honest ways to wear it: depend on a file the person using the window supplies, or draw it.     *
 * This draws it. Every number below is the theme's own, taken from its `.xpm` art rather than    *
 * invented: the bar's face, its one-point outline and five-point corners, the mark's eight-by-   *
 * nine box and two-point strokes, and the four inks a mark wears.                               *
 *                                                                                                *
 * AND IT IS A DRAWING AND NOT A GLYPH. A glyph would be a character the font has to have — the   *
 * same argument the System menu's hamburger is drawn on — and it would also be a WEIGHT the font *
 * has to have, where two points here is a stroke width and nothing else. The shapes are          *
 * arithmetic on a box, so they are drawn from a box, and they are crisp at any size because      *
 * there is no bitmap to resample.                                                               *
 * ============================================================================================ */

/* **THE FOUR INKS, ONE PER STATE, AND THE LIGHT ROW THAT SITS UNDER EACH.** `outShade` is that row's colour, and a
 * state that has none — the pressed blue, which the theme draws flat — answers nil so the caller makes one pass
 * instead of two. The states are the same four the theme ships, so these answers are the theme's: `active` is the
 * body colour, `inactive` the faded one a window that is not key wears, `prelight` the darker one under the pointer,
 * and `pressed` the blue one that says this is happening now. */
static NSColor *fn_mark_ink(AGChromeButtonState state, NSColor **outShade)
{
	*outShade = nil;
	switch (state) {
	case AGChromeButtonStateInactive:
		*outShade = [NSColor colorWithCalibratedWhite:fn_MARK_LIGHT_FAINT alpha:1.0];
		return [NSColor colorWithCalibratedWhite:fn_MARK_FAINT alpha:1.0];
	case AGChromeButtonStatePrelight:
		*outShade = [NSColor colorWithCalibratedWhite:fn_MARK_LIGHT alpha:1.0];
		return [NSColor colorWithCalibratedWhite:fn_MARK_HOVER alpha:1.0];
	case AGChromeButtonStatePressed:
		return [NSColor colorWithCalibratedRed:fn_MARK_PRESS_RED green:fn_MARK_PRESS_GREEN
						 blue:fn_MARK_PRESS_BLUE alpha:1.0];
	case AGChromeButtonStateActive:
	default:
		*outShade = [NSColor colorWithCalibratedWhite:fn_MARK_LIGHT alpha:1.0];
		return [NSColor colorWithCalibratedWhite:fn_MARK_INK alpha:1.0];
	}
}

/* **ONE MARK'S PATH, IN ITS OWN BOX, BUILT FROM THE SYMBOL BOX IT SITS IN.** The mark is eight by nine — except the
 * plus, which is eight by eight because only an even upright can have four equal arms — and the box is eleven by
 * eleven, so its origin is snapped to a whole point and lands half a point to the left of centre —
 * which is deliberate: every edge of a minus, a plus or the chevron's base then falls ON a pixel boundary, and an
 * edge on a boundary is a crisp edge rather than two rows of half-covered ones. The X is the exception by nature,
 * and the snap costs it nothing.
 *
 * THE SHAPES ARE THE THEME'S, MEASURED FROM ITS PIXELS: the X crosses its box corner to corner, the minus is one
 * two-point bar, the plus is that bar plus the same one turned a quarter turn, and the chevron is a FILLED triangle
 * eight wide and six tall with its base at the top. Each is drawn with the call that draws it exactly — filled
 * rectangles go through `CGContextFillRect` and the triangle through `CGContextFillPath`, the pair of lessons
 * `tests/window_chrome.m` records — and the X alone is STROKED, because it is the one shape whose edges are not on
 * the axes. */
static void fn_mark_path(CGContextRef c, CGRect box, AGChromeButton button)
{
	CGFloat w = fn_MARK_WIDTH;
	CGFloat h = (button == AGChromeButtonMenu) ? fn_MARK_CHEVRON : fn_MARK_HEIGHT;
	CGFloat t = fn_MARK_STROKE;
	CGFloat x = CGRectGetMinX(box) + floor((fn_SYMBOL - w) / 2.0);
	CGFloat y = CGRectGetMinY(box) + floor((fn_SYMBOL - fn_MARK_HEIGHT) / 2.0);

	if (button == AGChromeButtonMenu) {
		/* THE CHEVRON IS CENTRED ON THE MARKS BESIDE IT, not on its own shorter box: it hangs from the same middle
		 * row as the minus and the plus, which is why it is placed from `fn_MARK_HEIGHT` and not from its own six. */
		y += (fn_MARK_HEIGHT - h) / 2.0;
		CGContextMoveToPoint(c, x, y + h);
		CGContextAddLineToPoint(c, x + w, y + h);
		CGContextAddLineToPoint(c, x + w / 2.0, y);
		CGContextClosePath(c);
		CGContextFillPath(c);
		return;
	}
	if (button == AGChromeButtonClose) {
		/* **THE X IS STROKED WITH BUTT CAPS, AND `e` IS WHY IT FILLS ITS BOX.** A two-point stroke is centred on
		 * its path, so the ink of a diagonal reaches half the stroke's width SIDEWAYS from the centreline — which at
		 * forty-five degrees is `t/2 · sin 45`, or 0.707, in each axis. Pulling the endpoints back by exactly that
		 * puts the stroke's outer corners ON the box's corners, so the mark inks the whole eight by nine the theme's
		 * does; pulling them back by `t/2 · √2` instead — which is what this said first — left it a six-by-eight
		 * inside an eight-by-nine box, MEASURED, and a mark smaller than its neighbours'. The caps are BUTT and not
		 * round because the theme's are: a round cap would put a semicircle where its author put a squared end. */
		CGFloat e = t / 2.0 / (CGFloat)sqrt(2.0);

		CGContextSetLineWidth(c, t);
		CGContextSetLineCap(c, kCGLineCapButt);
		CGContextMoveToPoint(c, x + e, y + h - e);
		CGContextAddLineToPoint(c, x + w - e, y + e);
		CGContextMoveToPoint(c, x + e, y + e);
		CGContextAddLineToPoint(c, x + w - e, y + h - e);
		CGContextStrokePath(c);
		return;
	}
	/* **THE MINUS, AND THE PLUS AS FOUR EQUAL ARMS FROM ONE CENTRE.** Both are snapped to a whole row so their edges
	 * are crisp and both are the theme's two points thick; what the plus must ALSO be is EVEN, and that is the one
	 * thing the mark's nine-row box cannot give it.
	 *
	 * A two-point bar inside a nine-row upright leaves three rows above it and four below — MEASURED, "the top and
	 * bottom of the + are uneven" — and no choice of row fixes it: nine and two are odd and even, so the arms cannot
	 * match. The upright is therefore EIGHT rows — the cross-bar's own length — centred on the bar's centre, which
	 * leaves three above, three below, and three at each end of the bar: four arms of one length from one centre, a
	 * plus rather than a cross with a long leg. It is one row shorter than the X, and that is the price of the
	 * symmetry: an odd upright cannot have it.
	 *
	 * THE CENTRE IS SHARED. The cross-bar's rows are what the MINUS uses too, and all three marks are centre on the
	 * same row as a result — so the set reads as one, which is the thing the eye checks first.
	 */
	{
		CGFloat bar = y + floor((h - t) / 2.0);		/* the cross-bar's bottom row: the centre all three share */
		CGFloat arms = w;				/* the upright is as long as the cross-bar */

		CGContextFillRect(c, CGRectMake(x, bar, w, t));
		if (button == AGChromeButtonMaximize) {
			CGContextFillRect(c, CGRectMake(x + floor((w - t) / 2.0), bar + t / 2.0 - arms / 2.0, t, arms));
		}
	}
}

/* **AND ONE MARK DRAWN IN ONE STATE, WHICH IS TWO PASSES AND NOT ONE.** The light row comes first, a point BELOW the
 * ink in window coordinates, and the ink is laid over it: what survives is a one-point light edge under each stroke,
 * which is the whole of the theme's engraved look — the mark reads as cut into the bar rather than printed on it.
 * The blue pressed state is flat because its art is, and `fn_mark_ink` says so by answering no shade at all. */
static void fn_draw_mark(CGContextRef c, CGRect box, AGChromeButton button, AGChromeButtonState state)
{
	NSColor *shade = nil;
	NSColor *ink = fn_mark_ink(state, &shade);

	/* **AND THE MARKS ARE NOT ANTIALIASED, WHICH IS HOW THE THEME'S OWN ART IS DRAWN.** A two-point diagonal is the
	 * one shape here that a soft edge ruins: the theme's X is a hard two-pixel stair and reads as an X at its own
	 * size, while the same stroke smoothed blends its arms into a blob at the crossing. Turning it off for the marks
	 * says "these are marks and not photographs", and the bar's arcs keep theirs, where a curve needs it. */
	CGContextSaveGState(c);
	CGContextSetShouldAntialias(c, false);
	if (shade != nil) {
		CGContextSaveGState(c);
		CGContextTranslateCTM(c, 0.0, -1.0);
		CGContextSetFillColorWithColor(c, [shade CGColor]);
		CGContextSetStrokeColorWithColor(c, [shade CGColor]);
		fn_mark_path(c, box, button);
		CGContextRestoreGState(c);
	}
	CGContextSetFillColorWithColor(c, [ink CGColor]);
	CGContextSetStrokeColorWithColor(c, [ink CGColor]);
	fn_mark_path(c, box, button);
	CGContextRestoreGState(c);
}

/* **THE CHROME IS ONE SURFACE WITH ONE EDGE: ITS TOP.** The title bar and the toolbar band are the same rectangle and
 * the same colour (`+cg_chromeFaceColor`) — the window paints the strip above the band, `NSToolbar` paints the band,
 * and there is no seam between them because there is no second colour to make one. What this function adds is the top:
 * a one-point outline in the theme's `#939393` and a one-point white row under it, following the top's six-point
 * corners and then STOPPING at the tangent on each side.
 *
 * **AND NOTHING DOWN THE SIDES.** A one-point line down the left and right ends of the strip reads as a border drawn
 * around the chrome rather than as the top of it: the ends of a window's decoration are the window's own edges, and
 * the shadow the compositor draws outside them is what says where they are. MEASURED, that line was the first thing
 * the eye found on the right-hand end, where the strip has nothing else in it.
 *
 * **THE HALF-POINT INSETS ARE THE WHOLE OF WHY THIS IS CRISP.** A one-point stroke is centred on its path, so a path
 * on the shape's own edge covers half a pixel inside and half outside and renders as two grey rows. The outline is
 * therefore drawn on a path inset by HALF its width, with its radius brought down to match so the corner stays
 * concentric, and the highlight on a path inset by one and a half. */
static void fn_chrome_edge_path(CGContextRef c, CGFloat width, CGFloat top, CGFloat radius, CGFloat inset)
{
	CGFloat left = inset;
	CGFloat right = width - inset;
	CGFloat y = top - inset;
	CGFloat r = radius - inset;

	if (r < 0.0) {
		r = 0.0;
	}
	/* FROM THE LEFT TANGENT, ROUND THE CORNER, ACROSS, AND ROUND THE OTHER — and no further: the path BEGINS at the
	 * point where the arc leaves the left edge, which is what makes the ends of the stroke the corners' own. */
	CGContextMoveToPoint(c, left, y - r);
	CGContextAddArcToPoint(c, left, y, left + r, y, r);
	CGContextAddLineToPoint(c, right - r, y);
	CGContextAddArcToPoint(c, right, y, right, y - r, r);
}

/* `top` IS THE WINDOW'S OWN TOP EDGE and `width` its width; the strip's height does not enter, because the edge does
 * not run down it. */
static void fn_draw_chrome_edges(CGContextRef c, CGFloat width, CGFloat top)
{
	CGFloat radius = fn_BAR_RADIUS;
	CGFloat w = fn_BAR_BORDER;

	if (width < 2.0 * radius) {
		radius = width / 2.0;	/* a window narrower than its own corners gets an edge, not a folded path */
	}
	CGContextSaveGState(c);
	CGContextSetShouldAntialias(c, true);

	/* 1. THE OUTLINE, inset by half of itself so its one point lands ON the pixel instead of across two of them. */
	CGContextBeginPath(c);
	fn_chrome_edge_path(c, width, top, radius, w / 2.0);
	CGContextSetLineWidth(c, w);
	CGContextSetStrokeColorWithColor(c, [[NSColor colorWithCalibratedWhite:fn_BAR_EDGE alpha:1.0] CGColor]);
	CGContextStrokePath(c);

	/* 2. AND THE LIGHT ROW UNDER IT, one point further in. */
	CGContextBeginPath(c);
	fn_chrome_edge_path(c, width, top, radius, w * 1.5);
	CGContextSetLineWidth(c, w);
	CGContextSetStrokeColorWithColor(c, [[NSColor whiteColor] CGColor]);
	CGContextStrokePath(c);

	CGContextRestoreGState(c);
}

/* ONE IMAGE INTO ONE RECTANGLE. **NO FLIP IS NEEDED AND THAT IS THIS TREE'S OWN CONVENTION, MEASURED RATHER THAN
 * ASSUMED**: `CGContextDrawImage`'s sampler reads the source row `(1 - v) * height` for a point at user-space `v`,
 * so the TOP of the rectangle is the image's FIRST row — which is exactly the row a `CGImage`'s bytes start with,
 * and exactly what an XPM's first pixel row is. The first version translated and scaled the CTM by hand, on the
 * assumption every bottom-left context needs it, and drew every button upside down; `tests/chrome_theme.m` asks the
 * top and the bottom corners precisely so that mistake cannot return. ANTIALIASING IS OFF because a theme's button
 * is drawn at its OWN size (1:1) and resampling it would soften the pixels the theme's author placed. */
/* **WHETHER A POINT IS IN THE TITLE BAR — THE WINDOW'S HANDLE, AS OPPOSED TO ITS CONTENT.** It is the same
 * `fn_chrome_layout` the painter and the button hit test use, so "in the chrome" cannot mean one rectangle here and
 * another there. A borderless window has no chrome and so has no handle: it answers NO. */
static BOOL fn_pointInChrome(NSWindow *w, NSPoint p)
{
	NSRect content = [w contentRectForFrameRect:[w frame]];
	fn_chrome_layout_t layout;

	fn_chrome_layout(w, &layout);
	if (layout.height <= 0.0) {
		return NO;
	}
	{
		CGFloat top = content.size.height + fn_toolbar_height(w);

		return p.x >= 0.0 && p.x < content.size.width
			&& p.y >= top && p.y < top + layout.height;
	}
}

/* **AND THE TOOLBAR BAND IS THE WINDOW'S TOO, EXCEPT WHERE AN ITEM SITS.** A press between the items used to go
 * nowhere: it is outside the title bar's rectangle and outside the content's, and the band itself has no control.
 * On the Mac that press moves the window, which is what makes a toolbar a place to take hold of rather than a strip
 * of dead pixels. The items are asked FIRST — through the toolbar's own hit test, so this cannot disagree with what
 * the toolbar would do with the same press — and only the space between and around them becomes a handle.
 *
 * A BORDERLESS WINDOW KEEPS NO HANDLE, which is `fn_pointInChrome`'s rule applied to the band as well: a window
 * with no chrome is a window the application placed itself. */
static BOOL fn_pointInToolbarBand(NSWindow *w, NSPoint p)
{
	NSRect content = [w contentRectForFrameRect:[w frame]];
	CGFloat height = fn_toolbar_height(w);

	if (height <= 0.0 || ![w hasTitleBar]) {
		return NO;
	}
	if (!(p.x >= 0.0 && p.x < content.size.width
	      && p.y >= content.size.height && p.y < content.size.height + height)) {
		return NO;
	}
	return ![[w toolbar] cg_pointIsOverControl:p];
}

/* ============================================================================================ *
 * THE FRAME'S OWN EDGES, WHICH ARE THE WINDOW'S OTHER HANDLE.                                   *
 *                                                                                                *
 * **A WINDOW THAT CAN BE MOVED BY ITS CHROME AND NOT RESIZED IS HALF A WINDOW**, and this is      *
 * the half that has to say WHERE the edges are rather than what to do with them. Four bands      *
 * inside the frame, five points wide, and the CORNERS get a square each: a hand aiming at a       *
 * diagonal should not have to be inside a five-point sliver on two axes at once.                  *
 *                                                                                                *
 * **TWO CONFLICTS WITH THE CHROME, AND BOTH WERE FOUND BY A TEST RATHER THAN REASONED ABOUT.**      *
 *                                                                                                *
 * A BUTTON ON THE EDGE KEEPS ITS PIXELS. A theme may put its buttons anywhere — the fixture's     *
 * are 6x8 in an 8-point strip, so the top band would lie over ALL of them — and a close button    *
 * that becomes a resize handle is worse than a top edge that is a few points shorter. So the      *
 * buttons are asked first, and the band is the window's everywhere they are not.                   *
 *                                                                                                *
 * AND THE TOP BAND NEVER TAKES MORE THAN A THIRD OF THE CHROME. A bar's height is the THEME's,    *
 * and a five-point band is a fifth of a 26-point bar and two thirds of an 8-point one — MEASURED,  *
 * the fixture's title bar became un-draggable in its middle, which is the window's oldest         *
 * gesture. Capping the band at a third leaves the majority of any bar as the handle it has        *
 * always been.                                                                                     *
 * ============================================================================================ */
#define FN_RESIZE_BAND 5.0	/* the band along each edge */
#define FN_RESIZE_CORNER 12.0	/* the square at each corner, where two bands would have to meet */

enum {
	FN_RESIZE_LEFT = 1,
	FN_RESIZE_RIGHT = 2,
	FN_RESIZE_BOTTOM = 4,
	FN_RESIZE_TOP = 8
};

static int fn_resizeEdges(NSWindow *w, NSPoint p)
{
	NSRect content = [w contentRectForFrameRect:[w frame]];
	fn_chrome_layout_t layout;
	CGFloat width, height, topBand;
	BOOL left, right, bottom, top;
	int edges = 0;

	/* A WINDOW THAT MAY NOT BE RESIZED HAS NO EDGE TO TAKE, which is the STYLE MASK's question and not the
	 * theme's — the same rule `fn_chrome_button_present` follows for the buttons. */
	if (([w styleMask] & NSResizableWindowMask) == 0) {
		return 0;
	}
	/* AND A BUTTON KEEPS ITS PIXELS, so the band is the window's only where no control is drawn on it. */
	if ([w cg_chromeButtonAtPoint:p] >= 0) {
		return 0;
	}
	fn_chrome_layout(w, &layout);
	width = content.size.width;
	height = content.size.height + fn_toolbar_height(w) + layout.height;	/* the FRAME's own height */
	if (p.x < 0.0 || p.y < 0.0 || p.x >= width || p.y >= height) {
		return 0;
	}
	/* THE TOP BAND IS CAPPED AT A THIRD OF THE CHROME, because that strip's height is the theme's and a bar must
	 * keep most of itself as the handle it is. */
	topBand = FN_RESIZE_BAND;
	if (layout.height > 0.0 && topBand > layout.height / 3.0) {
		topBand = layout.height / 3.0;
	}
	left = (p.x < FN_RESIZE_BAND);
	right = (p.x >= width - FN_RESIZE_BAND);
	bottom = (p.y < FN_RESIZE_BAND);
	top = (p.y >= height - topBand);
	if (p.x < FN_RESIZE_CORNER && p.y < FN_RESIZE_CORNER) {
		left = bottom = YES;
	} else if (p.x < FN_RESIZE_CORNER && p.y >= height - FN_RESIZE_CORNER) {
		left = top = YES;
	} else if (p.x >= width - FN_RESIZE_CORNER && p.y < FN_RESIZE_CORNER) {
		right = bottom = YES;
	} else if (p.x >= width - FN_RESIZE_CORNER && p.y >= height - FN_RESIZE_CORNER) {
		right = top = YES;
	}
	if (left) {
		edges |= FN_RESIZE_LEFT;
	}
	if (right) {
		edges |= FN_RESIZE_RIGHT;
	}
	if (bottom) {
		edges |= FN_RESIZE_BOTTOM;
	}
	if (top) {
		edges |= FN_RESIZE_TOP;
	}
	return edges;
}

/* THE CURSOR THAT SAYS WHICH WAY AN EDGE GOES, or nil where there is no edge. A CORNER ANSWERS NIL, and that is
 * the era's own limit rather than this file's: the cursor set has a left-right and an up-down arrow and NOTHING
 * diagonal, and a corner shown as one of the two would be claiming a direction it does not have. */
static NSCursor *fn_resizeCursor(NSWindow *w, NSPoint p)
{
	int edges = fn_resizeEdges(w, p);
	BOOL horizontal = (edges & (FN_RESIZE_LEFT | FN_RESIZE_RIGHT)) != 0;
	BOOL vertical = (edges & (FN_RESIZE_TOP | FN_RESIZE_BOTTOM)) != 0;

	if (horizontal && !vertical) {
		return [NSCursor resizeLeftRightCursor];
	}
	if (vertical && !horizontal) {
		return [NSCursor resizeUpDownCursor];
	}
	return nil;
}

static void fn_draw_image(CGContextRef c, NSRect rect, CGImageRef image)
{
	CGContextSaveGState(c);
	CGContextSetShouldAntialias(c, false);
	CGContextDrawImage(c, CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height), image);
	CGContextRestoreGState(c);
}

/* **THE STATE A BUTTON IS DRAWN IN, AND ITS PRECEDENCE IS THE POINTER'S.** A press outranks a hover, and both
 * outrank the window's key state: the pointer's answer is the newer one, and a theme's pressed art exists to say
 * "this is happening now". A window that is neither key nor under the pointer is the inactive state — the ADJUST
 * half of the four every XFWM theme ships.
 *
 * **AND A PRESS COUNTS ONLY WHILE THE POINTER IS STILL ON THE BUTTON.** `_cg_pressedChrome` is "the press began
 * here", kept for the whole press so that the RELEASE can ask whether it should count; the INK is the POINTER's
 * answer, so a hand that slid off the X turns it back to a hover and a hand that slid back turns it pressed
 * again. Reading the two together is what makes sliding off a way to change your mind — a button drawn pressed
 * while the pointer is nowhere near it is a button claiming something that is not true. */
static AGChromeButtonState fn_chrome_state(NSWindow *w, NSInteger index)
{
	if (w->_cg_pressedChrome == index && w->_cg_hoverChrome == index) {
		return AGChromeButtonStatePressed;
	}
	if (w->_cg_hoverChrome == index) {
		return AGChromeButtonStatePrelight;
	}
	return [w isKeyWindow] ? AGChromeButtonStateActive : AGChromeButtonStateInactive;
}

/* **THE TITLE BAR AS THE THEME DRAWS IT: A CORNER AT EACH END, TITLE PIECES BETWEEN, THE BUTTONS ON TOP.** XFWM
 * composes a bar this way, and those piece files are the ground a theme's buttons were drawn against — so a chrome
 * that read only the buttons would put them on this tier's flat grey and leave the rest of the bar plain. The
 * pieces are tiled in XFWM's order (1…5, cycled) and the corners are drawn LAST so they cover the tiling's ends; a
 * theme with only SOME of them keeps the frame colour as the ground, which is what the fill underneath is for. */
static void fn_draw_themed_title_bar(CGContextRef c, AGChromeTheme *theme, NSRect content, CGFloat top,
				     BOOL active, CGFloat height)
{
	CGFloat width = content.size.width;
	CGFloat x;
	int i;

	CGContextSetFillColorWithColor(c, [[NSColor windowFrameColor] CGColor]);
	CGContextFillRect(c, CGRectMake(0.0, top, width, height));

	for (x = 0.0, i = 0; x < width && i < 4096; i++) {
		AGChromeFramePiece which = (AGChromeFramePiece)(AGChromeFrameTitle1 + (i % 5));
		CGImageRef piece = [theme framePiece:which active:active];
		CGFloat pw;

		if (piece == NULL) {
			piece = [theme framePiece:AGChromeFrameTitle1 active:active];
			if (piece == NULL) {
				break;
			}
		}
		pw = (CGFloat)CGImageGetWidth(piece);
		if (pw <= 0.0) {
			break;
		}
		fn_draw_image(c, NSMakeRect(x, top, pw, height), piece);
		x += pw;
	}
	{
		CGImageRef tl = [theme framePiece:AGChromeFrameTopLeft active:active];
		CGImageRef tr = [theme framePiece:AGChromeFrameTopRight active:active];

		if (tl != NULL) {
			CGFloat w = (CGFloat)CGImageGetWidth(tl);

			fn_draw_image(c, NSMakeRect(0.0, top, w, height), tl);
		}
		if (tr != NULL) {
			CGFloat w = (CGFloat)CGImageGetWidth(tr);

			fn_draw_image(c, NSMakeRect(width - w, top, w, height), tr);
		}
	}
}

static void fn_draw_chrome(CGContextRef c, NSWindow *w, NSRect content)
{
	fn_chrome_layout_t layout;
	AGChromeTheme *theme = [AGChromeTheme sharedTheme];
	CGFloat top = content.size.height + fn_toolbar_height(w);
	int i;

	fn_chrome_layout(w, &layout);

	if (theme != NULL) {
		/* **THE THEME'S OWN TITLE BAR FIRST, THEN ITS BUTTONS ON TOP.** A bar is a corner at each end and a strip of
		 * title pieces between them; the buttons and the title text sit on THAT, not on a flat fill. Only a window
		 * with chrome has a bar to draw. */
		if (layout.height > 0.0) {
			fn_draw_themed_title_bar(c, theme, content, top, [w isKeyWindow], layout.height);
		}
		/* **THE THEME'S BUTTONS, AT THEIR OWN SIZE.** Each is asked for the state the pointer and the window make,
		 * and a theme that is missing one file falls back to the drawn mark for THAT button rather than for the
		 * whole bar — a half-themed window is still a window. */
		for (i = 0; i < AGChromeButtonCount; i++) {
			CGImageRef image;

			if (!layout.present[i]) {
				continue;
			}
			image = [theme imageForButton:(AGChromeButton)i state:fn_chrome_state(w, i)];
			if (image != NULL) {
				fn_draw_image(c, layout.rects[i], image);
			} else {
				fn_draw_mark(c, layout.rects[i], (AGChromeButton)i, fn_chrome_state(w, i));
			}
		}
	} else {
		/* **THE CHROME THIS FILE DRAWS ITSELF, WHICH IS WHAT A PROCESS WITH NO THEME GETS — THE ORDINARY CASE,
		 * because no theme ships with this library.** ONE SURFACE in ONE colour: the title bar's share of the strip is
		 * filled here, the toolbar band's share is filled by `NSToolbar` with the same `+cg_chromeFaceColor`, and the
		 * edge — outline and white row — is then drawn over BOTH of them, from the window's top to the content's
		 * hairline. The marks go last, on top of their surface, each in the state the window and the pointer make.
		 *
		 * AND IT IS ALL VECTORS: a fill, one stroked path for the outline, one for the highlight, and the marks'
		 * own paths. No image, no texture, no resampling. */
		CGContextSetFillColorWithColor(c, [[NSColor cg_chromeFaceColor] CGColor]);
		CGContextFillRect(c, CGRectMake(0.0, top, content.size.width, layout.height));
		if (layout.height > 0.0) {
			fn_draw_chrome_edges(c, content.size.width, top + layout.height);
		}
		for (i = 0; i < AGChromeButtonCount; i++) {
			if (layout.present[i]) {
				fn_draw_mark(c, layout.rects[i], (AGChromeButton)i, fn_chrome_state(w, i));
			}
		}
	}

	/* **AND THE EDITED MARK IN THE CLOSE BUTTON**, centred on whatever the close control is: a dot in the middle of
	 * a drawn X, and a dot in the middle of the theme's close button, which is where the convention puts it and the
	 * one thing a theme's art cannot supply. */
	if ([w isDocumentEdited] && layout.present[AGChromeButtonClose]) {
		NSRect r = layout.rects[AGChromeButtonClose];
		CGFloat dot = r.size.width / 4.0;

		CGContextSetFillColorWithColor(c, [[NSColor cg_chromeInkColor] CGColor]);
		CGContextFillEllipseInRect(c, CGRectMake(NSMidX(r) - dot / 2.0, NSMidY(r) - dot / 2.0, dot, dot));
	}

	/* THE TITLE, CENTRED BETWEEN THE TWO BLOCKS — whatever those blocks are, the drawn marks or the theme's
	 * buttons, which is why their widths come from the layout and not from the constants. **AND ONLY A WINDOW WITH A
	 * STRIP HAS A TITLE TO PUT IN IT**: the mask says the window was built titled, and a sheet is not drawn one
	 * (see `fn_chrome_height`), so the height is what decides here rather than the mask. */
	if (layout.height > 0.0 && ([w styleMask] & NSTitledWindowMask) != 0) {
		NSDictionary *attributes = fn_title_attributes();
		NSFont *font = attributes == nil ? nil : [attributes objectForKey:NSFontAttributeName];
		CGFloat bandLeft = layout.leftBlock;
		CGFloat bandRight = content.size.width - layout.rightBlock;
		CGFloat available = bandRight - bandLeft;
		NSString *title;

		if (available < 0.0) {
			available = 0.0;
		}
		title = fn_title_that_fits([w title], attributes, available);
		if (title != nil) {
			CGFloat width = [title sizeWithAttributes:attributes].width;
			CGFloat centre = content.size.width / 2.0;
			NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:c flipped:NO];
			NSGraphicsContext *prev = [[NSGraphicsContext currentContext] retain];

			[NSGraphicsContext setCurrentContext:g];
			[title drawAtPoint:NSMakePoint(centre - width / 2.0,
						       fn_title_baseline(top, [font ascender], [font descender]))
			     withAttributes:attributes];
			[NSGraphicsContext setCurrentContext:prev];
			[prev release];
		}
	}

	/* **AND THE HAIRLINE, LAST SO NOTHING IN THE CHROME CAN COVER IT.** It is the TOP ROW OF THE CONTENT, which is
	 * BELOW the toolbar when there is one — the band belongs to the chrome, and this is the line where the chrome
	 * ends. `-showsBaselineSeparator` is the toolbar's switch for it, because Apple gives the toolbar that control;
	 * a window with no toolbar keeps the line it always had. A borderless window has no chrome and gets no line. */
	if (layout.height > 0.0 && content.size.height >= 1.0) {
		NSToolbar *toolbar = [w toolbar];

		if (toolbar == nil || ![toolbar isVisible] || [toolbar showsBaselineSeparator]) {
			CGContextSetFillColorWithColor(c, [[NSColor controlDarkShadowColor] CGColor]);
			CGContextFillRect(c, CGRectMake(0.0, content.size.height - 1.0, content.size.width, 1.0));
		}
	}

	/* **AND A SHEET DRAWS ITS PARENT'S TITLE BAR BORDER OVER ITSELF, BECAUSE THE BAR IS IN FRONT OF IT.** A sheet's top
	 * edge is tucked under its parent's title bar (`-cg_sheetTuck`), which means the bar's bottom border runs ACROSS the
	 * sheet on the Mac — the sheet is behind the bar, so the line is the bar's and it is drawn over whatever is under it.
	 * Here the two windows are separate surfaces and the SHEET's is the one on top, so the parent's line can only be
	 * stopped at the sheet's two sides: the sheet has to wear the line itself, in the bar's own ink and at the row the
	 * bar's line occupies, which is `tuck` points down from the sheet's top edge and therefore the row the parent's
	 * hairline covers on both sides of it. ONE ROW OF ONE COLOUR IS THE WHOLE OF IT; the seek is that a sheet with its
	 * body in the chrome's face colour and no line across it reads as a slab pasted under a bar rather than as a window
	 * sliding out from behind one.
	 *
	 * THE PARENT IS ASKED RATHER THAN A CONSTANT READ, because the tuck is zero for a parent with no title bar — a sheet
	 * on a borderless window hangs from the top of its content and has no bar's border to wear. */
	if ([w isSheet]) {
		NSWindow *parent = [w cg_sheetParent];
		CGFloat tuck = (parent != nil) ? [parent cg_sheetTuck] : 0.0;

		if (tuck >= 1.0 && content.size.height >= tuck + 1.0) {
			/* **AND IT IS ANTIALIASED, LIKE THE PARENT'S HALF OF IT.** A one-point row at a fractional output scale covers
			 * 1.33 device rows and is therefore a blend of two of them — that is what the parent's hairline is, and a
			 * sheet whose half of the line was snapped to a whole row would change the line's THICKNESS at its own two
			 * sides, which reads as two different lines meeting. MEASURED both ways at 1.332: snapped, the bar's line is
			 * two rows at 188 and the sheet's one row at 188. */
			CGContextSetFillColorWithColor(c, [[NSColor controlDarkShadowColor] CGColor]);
			/* THE ROW IS THE PARENT'S, NOT THE SHEET'S: the bar's border is the last row OF THE PARENT'S CONTENT — the
			 * row just below its content top — and the sheet's top edge is `tuck` above that top, so the border sits
			 * `tuck + 1` points below the sheet's own top edge. */
			CGContextFillRect(c, CGRectMake(0.0, content.size.height - tuck - 1.0, content.size.width, 1.0));
		}
	}
}

/* **AND THE CHROME REACHED THROUGH A CONTEXT, WHICH IS HOW ANY OF IT GETS CHECKED WITHOUT A COMPOSITOR.** The
 * painter above takes a `CGContextRef` because that is what drawing into a window's own pixels is; this door takes
 * the `NSGraphicsContext` an AppKit caller has, so `-cg_drawFrame:` and `tests/window_chrome.m` reach the same code.
 * A nil context draws nothing, which is what this file's other drawing doors do for the same reason — a draw with
 * nowhere to put it is not a crash. */
- (void)cg_drawChromeInContext:(NSGraphicsContext *)context
{
	CGContextRef c = (context != nil) ? (CGContextRef)[context graphicsPort] : NULL;

	if (c == NULL) {
		return;
	}
	fn_draw_chrome(c, self, [self contentRectForFrameRect:_frame]);
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

/* **AND WHETHER A CLICK ON IT MAY MAKE THE APPLICATION ACTIVE.** The Dock's own answer is NO; everything else says
 * nothing and keeps the ordinary click-to-focus. The window is still clickable — this is the keyboard and the menu
 * bar, not the pointer. */
- (void)cg_setActivatable:(BOOL)flag
{
	if (![self cg_ensureWindow]) {
		return;
	}
	AGWindowSetActivatable(_agwindow, flag ? 1 : 0);
}

/* **AND THE OTHER THING A WINDOW CAN SAY ABOUT THE SCREEN ITSELF: HOW MUCH OF IT IS THIS WINDOW'S.** The Dock is
 * the client this exists for, and the Mac's answer to the same question is not a public API — its window server
 * derives `-visibleFrame` from the Dock's window frame privately. Agora's protocol carries the number instead, so
 * the translation here is only the vocabulary: `NSRectEdge` is Cocoa's, and the seam's edges are the SCREEN's
 * (top, bottom, left, right), which is why this is a switch rather than a cast.
 *
 * `NSMinYEdge` is the BOTTOM because Cocoa's y grows upward — the one mapping in here that a reader will want to
 * check twice, and the one a Dock at the bottom of the screen uses. */
- (void)cg_setReservedEdge:(NSRectEdge)edge amount:(CGFloat)amount
{
	int platform_edge;

	if (![self cg_ensureWindow]) {
		return;
	}
	switch (edge) {
	case NSMinXEdge: platform_edge = AGWindowEdgeLeft; break;
	case NSMaxXEdge: platform_edge = AGWindowEdgeRight; break;
	case NSMaxYEdge: platform_edge = AGWindowEdgeTop; break;
	case NSMinYEdge:
	default:         platform_edge = AGWindowEdgeBottom; break;
	}
	AGWindowSetReserved(_agwindow, platform_edge, (int)(amount > 0.0 ? amount : 0.0));
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
	/* **AND WHICH APPLICATION IT IS, FROM THE BUNDLE RATHER THAN A CONSTANT.** The seam used to write
	 * "org.agora.AppKit" into every window, so a shell component grouping windows by application saw one
	 * application; `NSBundle` already answers this and the app does not have to know it asked. A process with no
	 * bundle (a test binary) has no identifier, which is empty and reads as "not an application". */
	if (_agwindow != NULL) {
		NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];

		AGWindowSetAppID(_agwindow, identifier != nil ? [identifier UTF8String] : "");
	}
	/* **THE SEAM IS TOLD BEFORE THE FIRST FRAME**, because a transparent window's shm buffer must be ARGB8888 and
	 * the format is decided when the buffer is made. An opaque window says so too, so the two states are always
	 * stated rather than defaulted into. */
	AGWindowSetTransparent(_agwindow, _opaque ? 0 : 1);
	if (_agwindow == NULL) {
		fprintf(stderr, "APPKIT-REFUSE: NSWindow could not create a window: %s\n",
			AGWindowServerLastError(server));
		return NO;
	}
	_cg_windowNumber = s_nextNumberOfWindow++;
	AGWindowSetEventHandler(_agwindow, fn_ag_event, self);
	AGWindowSetFrameHandler(_agwindow, fn_ag_frame, self);
	/* **AND THE TWO DOORS OF A TILE'S MENU**, which are not events because one has no argument (a question) and the
	 * other's is an ITEM rather than a position. */
	AGWindowSetDockMenuHandlers(_agwindow, fn_dock_menu_request, fn_dock_menu_action, self);
	/* **AND THE SERVER IS TOLD THE FRAME IT WAS MADE WITH.** `-initWithContentRect:` sets `_frame` DIRECTLY
	 * rather than through `-setFrame:`, so a window that is never moved afterwards would never have told the
	 * server where it is — MEASURED as a window at the origin however far from it the application had asked.
	 * Telling it here is what makes the frame honoured from the first pixel. */
	{
		CGFloat screen_height = [[NSScreen mainScreen] frame].size.height;

		if (screen_height > 0.0) {
			AGWindowSetFrame(_agwindow, fn_device_point(_frame.origin.x),
					 fn_device_point(screen_height - (_frame.origin.y + _frame.size.height)),
					 fn_device_point(_frame.size.width), fn_device_point(_frame.size.height));
		}
		/* AND THE LEVEL IT WAS GIVEN BEFORE IT EXISTED, for the same reason the frame is told here. */
		AGWindowSetLevel(_agwindow, (int)_level);
	}
	/* **AND WHETHER IT IS SOMEBODY'S SHEET, WHICH IS THE THIRD THING A WINDOW CAN KNOW BEFORE ITS SURFACE EXISTS.**
	 * An alert attaches itself to its parent and is shown afterwards, so the attachment is older than the surface the
	 * server has to be told about — this is where that statement finally finds a listener. See
	 * `-cg_setSheetParent:`, which makes the same call for a window that already had one. */
	if (_cg_sheetParent != nil) {
		AGWindowSetSheetParent(_agwindow, _cg_sheetParent->_agwindow, (int)[_cg_sheetParent cg_sheetTuck]);
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

/* THE OTHER SIDE OF THAT QUESTION, and the one a drag asks: a connection that was never made is not a connection
 * that has gone away. `fn_server` is this file's lazy connect, so asking here is what makes the answer true rather
 * than an environment-variable guess. */
+ (BOOL)cg_hasWindowServer
{
	/* THE QUESTION IS "HAS THIS PROCESS A CONNECTION", NOT "COULD ONE BE MADE": `fn_server` would CONNECT on a
	 * machine whose environment names a compositor, and a probe that never ordered a window would then be talking to
	 * a live server for no reason. A real drag begins in a window that was ordered in, so a real application has
	 * already connected by the time it asks. */
	return s_server != NULL;
}

/* **THE CONNECTION AS A RUN-LOOP SOURCE.** These three answer about a connection that EXISTS: `fn_server_if_connected`
 * instead of `fn_server`, so a loop that asks for a descriptor cannot open one (the same rule the zero-time poll
 * below states, and for the same reason — discovery does round trips, and a query that blocks is not a query). */
+ (int)cg_connectionFd
{
	AGWindowServer *server = fn_server_if_connected();

	return (server != NULL) ? AGWindowServerGetFd(server) : -1;
}

- (AGWindow *)cg_seamWindow
{
	return _agwindow;
}

+ (long)cg_nextDeadlineMs
{
	AGWindowServer *server = fn_server_if_connected();

	return (server != NULL) ? (long)AGWindowServerNextDeadlineMs(server) : -1;
}

/* THE TAKE: whatever the compositor has said, read and dispatched without blocking, which turns the source's
 * readiness into the NSEvents the drain that follows this pass will hand to `-sendEvent:`. */
+ (BOOL)cg_dispatchPending
{
	AGWindowServer *server = fn_server_if_connected();

	if (server == NULL) {
		return NO;
	}
	if (AGWindowServerDispatchTimeout(server, 0) < 0) {
		s_connection_gone = 1;
		return NO;
	}
	return s_queued_events > 0;
}

+ (BOOL)cg_waitForEventInMilliseconds:(long)ms
{
	/* **A POLL DOES NOT MAKE A CONNECTION, AND A CALLER THAT ALREADY HAS ONE KEEPS GETTING IT.** `fn_server` is this
	 * file's laziest door — it CONNECTS — and reaching it from a zero-time poll meant a "is anything waiting?" query
	 * could open a connection to the compositor, and block doing the round trips discovery needs, on a process that
	 * had never ordered a window. A poll asks about a connection that exists; only a real WAIT is allowed to make
	 * one. */
	AGWindowServer *server = (ms > 0) ? fn_server() : s_server;

	if (server == NULL) {
		return NO;
	}
	/* **QUEUED INPUT DOES NOT STARVE THE CONNECTION.** This used to return YES the moment anything was queued, so
	 * under continuous input the native connection was never serviced again: buffer-release callbacks and frame
	 * callbacks that arrive on it stayed undelivered, and presentation stopped advancing while the application's own
	 * loop reported event after event. A turn here is NONBLOCKING whatever the caller asked for, so it cannot delay
	 * the event the caller is about to collect, and it is what keeps the two halves of one connection in step. */
	if (s_queued_events > 0) {
		if (AGWindowServerDispatchTimeout(server, 0) < 0) {
			s_connection_gone = 1;
			return NO;
		}
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
	/* **A RESIZE OWES A REPAINT AND A MOVE DOES NOT, WHICH IS AN ASYMMETRY THIS DOOR DID NOT HAVE TO KNOW
	 * ABOUT UNTIL A WINDOW COULD BE DRAGGED BY ITS EDGE.** A move changes no surface: `cg_ensureSurface` sees
	 * the same size, keeps the same backing store, and the compositor re-places a buffer that is still valid —
	 * so the pass has nothing to draw and the window follows the pointer by itself. A RESIZE remakes the
	 * backing store from scratch (it is allocated per size), so the pixels the compositor last saw now belong
	 * to a store that no longer exists, and there is no buffer at the new size until one is attached.
	 * MEASURED: a window dragged by its edge DISAPPEARED for the whole drag — the desktop showed through where
	 * it had been, and the mid-drag capture had no window in it at all — and came back on the release, because
	 * the release is what marked it stale. A RESIZE MARKS ITSELF STALE. */
	if (resized) {
		[self setNeedsDisplay:YES];
	}
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
			AGWindowSetFrame(_agwindow, fn_device_point(_frame.origin.x),
					 fn_device_point(screen_height - (_frame.origin.y + _frame.size.height)),
					 fn_device_point(_frame.size.width), fn_device_point(_frame.size.height));
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
	/* **A RESIZE RE-LAYS THE CONTENT VIEW, WITH OR WITHOUT A TOOLBAR; A MOVE DOES NOT NEED TO.** A window's content
	 * view is the view the frame describes, so a resize that leaves it at its old size is a window whose document is
	 * the wrong shape — MEASURED on a scroll view and again on a table, where the clip view changed and the view
	 * inside it did not. A move changes no content rectangle, and marking the window stale for one would repaint a
	 * surface that did not move. */
	if (resized) {
		/* **THE LAYOUT IS APPLIED BEFORE THE NOTIFICATION, AND THAT ORDER IS THE WHOLE POINT OF IT.** This tail ran
		 * the other way round: `-windowDidResize:` was announced first and the content view re-laid afterwards, so
		 * a resize observer — which is exactly what a scroll view, a table or a document registers — read the NEW
		 * frame and the OLD content bounds in the same callback and computed a layout for a size the window no
		 * longer had. MEASURED on a scroll view, where the clip view moved and the view inside it did not. */
		[self cg_layoutForResize];
		fn_announce(self, NSWindowDidResizeNotification, @selector(windowDidResize:));
	}
	/* **A MOVE OR A RESIZE RE-PINS EVERY DRAWER.** A child window is moved by the child loop above, but its own frame
	 * is computed from the parent's, so a drawer that is vertically centred has to be re-centred when the parent's
	 * height changes — and a tucked side drawer has to keep its tuck when the parent moves. The copy the drawer list
	 * answers is stable across a drawer hiding itself and re-making its child link. */
	[self cg_updateDrawers];
	/* **AND A SHEET IS THE OTHER WINDOW WHOSE FRAME IS DERIVED FROM THIS ONE'S.** It is not a child window (on the Mac
	 * a sheet's `-parentWindow` is nil and its `-sheetParent` is separate), so the child loop above does not move it,
	 * and a sheet left behind by a dragged parent is exactly the "separate window" a sheet must not be. The rule is
	 * `-cg_updateSheet`'s — it hangs from the bottom of this window's title bar, centred — and it is re-applied for
	 * a move AND for a resize: a wider parent re-centres its sheet. */
	if (moved || resized) {
		[self cg_updateSheet];
	}
	(void)flag;
}

/* **THE LAYOUT HALF OF A RESIZE, IN ONE PLACE BECAUSE THERE ARE NOW TWO DOORS THAT RESIZE.** A frame the
 * application sets and a frame the compositor configures used to take different paths through this file: the
 * application's re-laid the content and the compositor's did not. One window has one content geometry. */
- (void)cg_layoutForResize
{
	[self cg_toolbarLayoutChanged];
	_viewsNeedDisplay = YES;
}

/* **AND THE COMPOSITOR'S OWN RESIZE, LANDED.** The size was taken in the listener (see
 * `cg_handleSeamEvent:`); this is the tail that could not run there — layout first, then a repaint from the NEW
 * geometry, then the delegate's notification, once for the size the batch settled on. The origin does not move: a
 * compositor configures a size, and this tier places nothing. */
- (void)cg_configureDidLand
{
	NSSize previous = _cg_configuredSize;

	_cg_configuredSize = _frame.size;
	[self cg_layoutForResize];
	[self cg_drawFrame];
	/* THE NOTIFICATION IS A TRANSITION, NOT A COUNT, exactly as activation's is: a batch of configures that ends
	 * where it started is not a resize, and one the delegate has already been told about at this size is not told
	 * again. */
	if (previous.width != _frame.size.width || previous.height != _frame.size.height) {
		fn_announce(self, NSWindowDidResizeNotification, @selector(windowDidResize:));
	}
	[self cg_updateDrawers];
}

/* **THE ANIMATED SPELLING HAS NO FRAMES IN BETWEEN.** The geometry is the direct set's and the redraw is the direct
 * set's; `animate:` is accepted and does not schedule an animation, which is stated here rather than pretended by a
 * second placement path that would drift from the one every other door uses. */
- (void)setFrame:(NSRect)frameRect display:(BOOL)flag animate:(BOOL)animate
{
	(void)animate;
	[self setFrame:frameRect display:flag];
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

/* **CHANGING THE MASK PRESERVES THE CONTENT RECT.** The old content geometry is measured under the old mask, the
 * mask changes, and the frame that holds that content under the new one is set — so a caller that adds a title bar
 * grows the frame rather than shrinking its document. The redraw is what makes the chrome follow the new bits. */
- (void)setStyleMask:(NSUInteger)styleMask
{
	NSRect content;
	NSRect frame;

	if (styleMask == _styleMask) {
		return;
	}
	content = [self contentRectForFrameRect:_frame];
	_styleMask = styleMask;
	frame = [self frameRectForContentRect:content];
	[self setFrame:frame display:YES];
	[self setNeedsDisplay:YES];
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
	/* **AND THE BAR REPAINTS, WHICH IT DID NOT BEFORE**: a title is chrome ink and nothing here marked anything, so a
	 * renamed window kept its old title until an unrelated repaint — a focus change, a resize — happened to cover it. */
	[self cg_invalidateChrome];
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

/* ==================================================================================================================
 * THE UNDO MANAGER — THE ANSWER THE WHOLE RESPONDER CHAIN WAS WAITING FOR.
 *
 * **`-windowWillReturnUndoManager:` WAS DECLARED AND NEVER SENT, WHICH IS THE SHAPE THIS TREE KEEPS FINDING.**
 * `NSWindowDelegate` publishes the door, `NSResponder -undoManager` documents its walk in as many words ("a window's own
 * answer is the delegate's"), and neither half had a caller: `-undoManager` was `NSResponder`'s, which walks to the next
 * responder, and a window's next responder is the application. MEASURED: a text view in a window with an `NSDocument`
 * behind it found NO manager, so `-allowsUndo` could register nothing, and the only thing that kept this from showing was
 * that nothing in the tier had asked yet. The chain now has a source: view → window → delegate → the document's manager.
 *
 * **AND THAT IS APPLE'S ORDER, NOT AN INVENTION.** The window is the one object that knows which document it belongs to,
 * and the delegate is the only thing that can say; a document that does not want undo returns nil from its own answer and
 * the walk then ends where it would have ended anyway.
 * ================================================================================================================ */
- (NSUndoManager *)undoManager
{
	id delegate = [self delegate];

	if (delegate != nil && [delegate respondsToSelector:@selector(windowWillReturnUndoManager:)]) {
		return [delegate windowWillReturnUndoManager:self];
	}
	return [super undoManager];
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
	/* **MARKED STALE BEFORE IT IS SHOWN — AND ONLY WHEN IT IS NOT ALREADY ON THE SCREEN.** Showing is what asks
	 * for the first frame, and the compositor's frame callback now DECLINES to draw a window that is not stale — so
	 * the show path has to say there IS something to draw, or a freshly ordered-in window would never be painted at
	 * all. But `-orderFront:` is ALSO what a click calls, through `-[NSApplication activateIgnoringOtherApps:]`,
	 * and marking a window that is already visible stale there is a full repaint of every view and every string for
	 * a click that changed one cell. MEASURED: every click in a file window repainted 900x634 of content AND its
	 * toolbar, because the activation the application already had re-showed the window it already had. A visible
	 * window has its pixels; the mark belongs to the transition from hidden to shown, and the raise below is what
	 * the click actually wanted. */
	if (!_visible) {
		[self setNeedsDisplay:YES];
	}
	AGWindowShow(_agwindow);
	/* **`-orderFront:` RAISES, WHICH IS APPLE'S OWN SENTENCE ABOUT IT** — and until now this door only showed the
	 * window, while `-orderBack:` sent `raise` and therefore did the opposite of its name. A click in another window
	 * calls this door, so the raise is what makes "clicking brings it frontmost" true. */
	AGWindowRaise(_agwindow);
	/* **A DRAWER NEVER STAYS OVER ITS PARENT, EVEN FOR ONE FRAME.** A click on a control INSIDE the drawer is a
	 * `-orderFront:` on the drawer's own window; raising it alone would put it over the parent until the button's action
	 * ran. The drawer is marked, and the parent is raised again in the same call, so the compositor never sees the pair
	 * in that order. */
	if ([self cg_isDrawerWindow] && _cg_parentWindow != nil) {
		[_cg_parentWindow cg_raiseForDrawer];
	}
	/* **AND A SHEET COMES BACK WITH THE WINDOW IT HANGS FROM.** On the Mac the pair is one thing on the glass: a sheet
	 * cannot be on the screen without its parent. `-orderOut:` hides both (see there), so showing the parent has to
	 * bring the sheet back or a hidden-and-shown document would lose its question. It is ordered AFTER the parent, so
	 * the sheet is never briefly under it. */
	if (_cg_attachedSheet != nil) {
		[_cg_attachedSheet orderFront:nil];
	}
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
	/* **AND THE DRAWERS FOLLOW THE PIXELS, NOT A NOTIFICATION.** Ordering is the moment a window becomes "frontmost",
	 * and there is no ordering notification in this tier's surface; the list this window owns is the direct half. */
	[self cg_updateDrawers];
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
	/* **AND A SHEET GOES WITH IT.** A sheet is a part of the window it hangs from — the pair is one thing on the glass —
	 * so a parent ordered out with its sheet still showing leaves a question floating over the desktop with nothing to
	 * be a question about. The SESSION is not ended: the attachment, the reply and the sheet's own frame are all left
	 * alone, and `-orderFront:` brings the pair back together. ORDERED OUT AFTER THE PARENT, mirroring the order-in, so
	 * neither door ever leaves the sheet on the screen alone. */
	if (_cg_attachedSheet != nil) {
		[_cg_attachedSheet orderOut:nil];
	}
	/* A HIDDEN WINDOW IS NOT FRONTMOST, whatever its key flag still says. The drawers ask the same question the
	 * visibility rule does, through the same door. */
	[self cg_updateDrawers];
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

- (BOOL)cg_shouldBecomeKeyForClickAtPoint:(NSPoint)point
{
	/* **A CLICK MAY MAKE AN ORDINARY WINDOW KEY, WHEREVER IT LANDS.** The question exists for `NSPanel`, whose
	 * `-becomesKeyOnlyIfNeeded` narrows it to clicks on views that want the keyboard; a window has no such rule, so
	 * the base answer is YES and the point is not consulted. See `NSPanel.m` for the other half and
	 * `NSApplication -sendEvent:` for the one caller. */
	(void)point;
	return YES;
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
	[[NSApplication sharedApplication] cg_setKeyWindow:nil];
	[self setNeedsDisplay:YES];
	/* **AND THE TRACKING IS RE-EVALUATED, WHICH IS THE WHOLE REASON THE SCOPE BITS ARE WORTH HAVING.** Every area
	 * whose scope is `NSTrackingActiveInKeyWindow` — which is the default, and what every control in this tree installs
	 * — has just stopped being live, so a control the pointer is resting on gives up its prelight the moment its window
	 * stops being the key one. NO MOTION EVENT IS COMING to say so: the pointer has not moved, and the fact that
	 * changed is the WINDOW's. Re-running the engine at the pointer's last known position is what turns that into the
	 * exits the owners are owed. */
	[self cg_updateTrackingForPoint:[self mouseLocationOutsideOfEventStream]];
	fn_announce(self, NSWindowDidResignKeyNotification, @selector(windowDidResignKey:));
	[self cg_updateDrawers];
}

- (void)close
{
	/* **A WINDOW THAT CLOSES MID-DRAG ENDS THE DRAG.** The session retains the source window, so the window is
	 * still a safe message send here; letting it go without one would leave a session holding a captured pointer
	 * that no surface can release. `-cg_finish` sends the source and destination callbacks with no operation, which
	 * is the same ending an Escape gives. */
	if ([NSDraggingSession cg_activeSession] != nil
	    && [[NSDraggingSession cg_activeSession] cg_sourceWindow] == self) {
		[[NSDraggingSession cg_activeSession] cg_finish];
	}
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
	NSView *previousContent = _contentView;

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
	/* THE CONTENT VIEW — AND THE TOOLBAR'S VIEW WITH IT — IS LAID OUT HERE. `-addSubview:` takes the toolbar out of
	 * the previous content view, and this call is the one place both the content rect and that adoption are computed. */
	[self cg_toolbarLayoutChanged];
	/* **AND THE FIRST RESPONDER MOVES THROUGH THE REAL DOOR RATHER THAN BY ASSIGNMENT.** This used to write
	 * `_firstResponder` straight, which made the new content view the first responder WITHOUT EVER ASKING IT —
	 * neither `-acceptsFirstResponder` nor `-becomeFirstResponder` — and without telling the one it displaced.
	 * MEASURED, that is the SAME defect as the door that never called `-becomeFirstResponder` at all, reached by a
	 * second route: a text view that IS the first responder, and whose editing session therefore never opened, so
	 * its caret was missing. AND A CONTENT VIEW THAT DOES NOT WANT THE KEYBOARD IS A REAL CASE — the window then has
	 * no first responder, which is why `-sendEvent:` falls back to the content view for key events. */
	if (_firstResponder == nil || _firstResponder == previousContent) {
		[self makeFirstResponder:_contentView];
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
	/* **AND THE THREE QUESTIONS APPLE ASKS, WHICH THIS DOOR DID NOT ASK AT ALL.** A responder is not made the first
	 * responder by being NAMED — it is made one by AGREEING, and by the one it displaces agreeing to go. MEASURED,
	 * the absence was a text view with NO CARET: `-becomeFirstResponder` is where an editor opens its session, and
	 * nothing in this tier ever called it, so every field was permanently "not editing" and a delegate's
	 * `-textShouldBeginEditing:` was never consulted either. */
	NSResponder *previous = _firstResponder;

	/* THE ORDER IS THE CONTRACT. The newcomer is asked whether it wants the keyboard FIRST, so a view that declines
	 * is never asked to become anything; the incumbent is asked to let go SECOND, and a refusal ABANDONS the whole
	 * change — a field that will not give up its editing keeps it; and only then does the newcomer become it, with a
	 * refusal there UNDOING the change rather than leaving the window with a first responder that said no. */
	if (aResponder == previous) {
		return YES;
	}
	if (aResponder != nil && ![aResponder acceptsFirstResponder]) {
		return NO;
	}
	if (previous != nil && ![previous resignFirstResponder]) {
		return NO;
	}
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
	if (aResponder != nil && ![aResponder becomeFirstResponder]) {
		/* IT CHANGED ITS MIND ON THE WAY IN, so the change is undone and the one it displaced is put back — the only
		 * answer that leaves the window with a first responder rather than with none. */
		_firstResponder = previous;
		if (previous != nil) {
			[previous becomeFirstResponder];
		}
		return NO;
	}
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
	/* **PASSIVE, BECAUSE THE APPLICATION PUMPS EVERY WINDOW ON EVERY PASS.** The lazy door would CONNECT here — for
	 * a window that has no native window and therefore nothing to wait for — and the application's own drain calls
	 * this with an already-past date, so a "poll" could open a connection and block in discovery. A window with an
	 * `AGWindow` implies the connection exists, so the passive answer is the same one whenever it matters. */
	AGWindowServer *server = fn_server_if_connected();
	NSTimeInterval deadline = -1.0;
	BOOL noServer = (server == NULL || _agwindow == NULL);

	/* **A WINDOW WITH NO SERVER WINDOW CAN STILL HAVE A LOCAL QUEUE.** `-postEvent:atStart:` is a public door and
	 * works before a window is ordered in; the drain below is the same queue, so it serves those events first and
	 * returns nil only when there is nothing queued and nothing to wait on. Before this, a deferred window's
	 * posted events were unreachable. */
	if (noServer && [_cg_events count] == 0) {
		return nil;
	}
	/* A CLOSE THE COMPOSITOR ASKED FOR IS ACTED ON HERE rather than inside the dispatch that heard it, and this
	 * is outside the dispatch: `-close` destroys the window, and destroying it while libwayland is still walking
	 * that window's own listeners is a use-after-free.
	 *
	 * **AND IT GOES THROUGH `-performClose:`, WHICH IS THE DOOR WITH THE VETO ON IT.** This used to call `-close`
	 * directly, so a compositor's close (the shell's `close_window`, a Dock tile's Close) skipped
	 * `-windowShouldClose:` entirely and a window with unsaved changes went away without being asked — while the
	 * SAME window's chrome button asked. One window has one close policy; which door the request came through is
	 * not the application's business. `-performClose:` can refuse, in which case nothing happens here and the
	 * window stays. */
	/* **A CONFIGURE DECIDED OUTSIDE THE DISPATCH.** The size is already applied; what is left is the work that
	 * cannot run inside a native callback — re-lay the content and toolbar, mark the window stale, and tell the
	 * delegate ONCE for the size the batch settled on. */
	if (_cg_configurePending) {
		_cg_configurePending = NO;
		[self cg_configureDidLand];
	}
	if (_cg_closeRequested) {
		_cg_closeRequested = NO;
		/* **HELD ACROSS THE DECISION, BECAUSE THE DECISION MAY RELEASE THIS WINDOW.** `-performClose:` ends in
		 * `-close`, and a window that was created with `-setReleasedWhenClosed:YES` is deallocated by it — so the
		 * frame that asked gets a released receiver back and its next use is a use-after-free. Retaining here costs
		 * one pair of messages on a path that runs once per close. */
		[[self retain] autorelease];
		[self performClose:nil];
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

			/* **`mask & t` IS THE WHOLE TEST, AND IT ALREADY COVERS "ANY".** `NSAnyEventMask` is every bit
			 * set, so a selective mask that contains this event's type answers nonzero and the all-events mask
			 * answers nonzero for every event. Asking `mask & NSAnyEventMask` as well — which this did, before an
			 * event was even looked at — is nonzero for ANY nonzero mask, so the `continue` could never fire and
			 * a mouse-only peek returned the first key event in the queue. */
			if ((mask & t) == 0) {
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
		if (!wait || noServer) {
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
/* **THE LOCAL QUEUE'S TWO WRITERS.** `-postEvent:atStart:` is the seam a caller uses to feed an event into this
 * window ahead of or behind the ones already there; the queue is the same one `-nextEventMatchingMask:` drains, so
 * the static count is adjusted with it. `-discardEventsMatchingMask:beforeEvent:` removes the matching events that
 * are EARLIER than a named event (identity, not equality), or all matching events when the event is nil; a named
 * event that is not in this queue has no effect, which is Apple's reading of "before an event it does not have". */
- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag
{
	if (event == nil) {
		return;
	}
	if (flag) {
		[_cg_events insertObject:event atIndex:0];
	} else {
		[_cg_events addObject:event];
	}
	s_queued_events++;
}

- (void)discardEventsMatchingMask:(NSUInteger)mask beforeEvent:(NSEvent *)lastEvent
{
	NSMutableIndexSet *doomed;
	NSUInteger limit;
	NSUInteger i;

	if ([_cg_events count] == 0) {
		return;
	}
	if (lastEvent == nil) {
		limit = [_cg_events count];
	} else {
		limit = [_cg_events indexOfObjectIdenticalTo:lastEvent];
		if (limit == NSNotFound) {
			return;
		}
	}
	doomed = [NSMutableIndexSet indexSet];
	for (i = 0; i < limit; i++) {
		NSEvent *event = [_cg_events objectAtIndex:i];
		NSUInteger type = (NSUInteger)1 << [event type];

		if (mask == NSAnyEventMask || (mask & type) != 0) {
			[doomed addIndex:i];
		}
	}
	if ([doomed count] == 0) {
		return;
	}
	[_cg_events removeObjectsAtIndexes:doomed];
	s_queued_events -= (NSInteger)[doomed count];
}

- (void)sendEvent:(NSEvent *)theEvent
{
	SEL sel = NULL;
	id target;
	BOOL mouse = NO;

	/* **A DRAG IN FLIGHT TAKES THE POINTER'S EVENTS BEFORE ANY VIEW DOES.** The session captured the pointer on the
	 * source window, so every motion and the release arrive here — and the source view must not also see them, or
	 * a table would track a second, private drop while the session tracked the real one. The session answers YES
	 * only for the events it owns; a key it does not want, or anything outside a drag, falls through to the ordinary
	 * dispatch below. */
	if ([NSDraggingSession cg_activeSession] != nil
	    && [[NSDraggingSession cg_activeSession] cg_handleEvent:theEvent]) {
		return;
	}

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
	/* **A WHEEL GOES WHERE THE POINTER IS, LIKE A CLICK AND UNLIKE A KEY.** It is a mouse-family event for the hit
	 * test's purposes — the view under the pointer is the one that scrolls, which is what makes scrolling a list
	 * work without the list being key — but `mouse` here only decides the HIT TEST: the activation and
	 * become-key block below is gated on the mouse-DOWN types, so a wheel never makes a window key or raises it. */
	case NSScrollWheel:        sel = @selector(scrollWheel:); mouse = YES; break;
	case NSKeyDown:            sel = @selector(keyDown:); break;
	case NSKeyUp:              sel = @selector(keyUp:); break;
	case NSFlagsChanged:       sel = @selector(flagsChanged:); break;
	default:                   break;
	}
	if (sel == NULL) {
		return;
	}
	if (mouse) {
		/* **A PRESS THAT LANDS ON THE CHROME IS THE WINDOW'S, NOT A VIEW'S.** There is no view in the title bar, so
		 * the hit test below would hand the click to the content view — which is where a title-bar click used to go.
		 * A chrome button consumes the whole press instead: the press is REMEMBERED here, its ink follows the pointer
		 * for as long as the hand is down (see `fn_chrome_state`), and THE RELEASE IS WHAT PERFORMS IT — through
		 * `-cg_performChromeButton:`, and only if the pointer is still on the button that was pressed. */
		if ([theEvent type] == NSLeftMouseDown) {
			NSPoint p = [theEvent locationInWindow];
			NSInteger hit = [self cg_chromeButtonAtPoint:p];
			int edges = fn_resizeEdges(self, p);

			/* **A NEW PRESS FORGETS WHAT THE LAST ONE WAS DOING.** One press means one thing, and it is decided
			 * entirely below — so a release that never arrived (a compositor that lost it, a hand that left the
			 * surface) cannot leave a button pressed for good, with every later drag of the window swallowed as that
			 * button's. */
			_cg_pressedChrome = -1;
			_cg_draggingChrome = NO;
			_cg_resizeEdges = 0;
			_cg_resizePending = NO;
			/* **AN EDGE IS THE FIRST THING ASKED, BECAUSE IT IS THE WINDOW'S OWN BORDER** — see the note on
			 * `fn_resizeEdges` for why the band outranks the buttons it overlaps. */
			if (edges != 0) {
				_cg_resizeEdges = edges;
				_cg_resizeStartFrame = _frame;
				/* **THE GRAB IS KEPT IN THE FRAME'S OWN SPACE, WHICH IS NOT THE EVENT'S.** An event's point is
				 * relative to the window; the frame a resize is computed from is absolute; and the two must not be
				 * mixed, because every offset below is a distance from an EDGE — MEASURED, adding a relative grab
				 * point to an absolute right edge gave a 62-point inset for a two-point one and a 40-point drag
				 * grew the window by 100. */
				_cg_resizeGrab = NSMakePoint(_frame.origin.x + p.x, _frame.origin.y + p.y);
				/* THE POINTER IS TAKEN FOR THE DURATION, OUTRIGHT rather than as a fallback: a resize moves the
				 * window out from under the hand — the edge follows the pointer and the compositor's copy of the
				 * surface is a frame behind — so the pointer leaves the window and lands on the desktop or on a
				 * neighbour, and a fallback would lose every motion that crossed onto one. See
				 * `-cg_setPointerCapture:`. */
				[self cg_setPointerCapture:YES];
				return;
			}
			if (hit >= 0) {
				_cg_pressedChrome = hit;
				/* **AND THE POINTER IS ON THE BUTTON BY DEFINITION — `hit` IS the hit test's answer for where the
				 * hand is.** So the press sets the HOVER with it, and `fn_chrome_state`'s pair is satisfied by a CLICK:
				 * press and release with no motion between them, which is the common case and which arrives with no
				 * hover of its own. A press that drew no pressed art because the pointer had not been seen to move
				 * first would be a button that only answers a hand that wobbles. */
				_cg_hoverChrome = hit;
				[self setNeedsDisplay:YES];
				return;
			}
			/* **A PRESS ON THE CHROME, OR ON THE TOOLBAR BETWEEN ITS ITEMS, IS A MOVE.** The title bar is the window's
			 * handle, the band below it is the same strip with controls in it, and `-isMovable` is the flag Apple's own
			 * header says decides it — so a window that refuses to be moved keeps its chrome to itself. The grab point is
			 * remembered; see the drag case below for the arithmetic. */
			if ([self isMovable] && (fn_pointInChrome(self, p) || fn_pointInToolbarBand(self, p))) {
				_cg_draggingChrome = YES;
				_cg_dragGrab = p;
				/* **AND WHICH POINTER THE DRAG WILL USE: the compositor's absolute one if the PRESS carried it, the
				 * window-relative one otherwise.** What is kept is the GRAB OFFSET — where in the window the hand took
				 * hold — because the window that follows is `pointer - offset` in absolute terms. It comes off the EVENT,
				 * not the window, because the window's "latest" has already moved on by the time the press is processed. */
				_cg_dragUsesGlobal = [theEvent cg_hasGlobalPoint];
				if (_cg_dragUsesGlobal) {
					NSPoint g = [theEvent cg_globalPoint];

					_cg_dragGlobalOffset = NSMakePoint(g.x - _frame.origin.x, g.y - _frame.origin.y);
				}
				/* **AND THE POINTER IS TAKEN OUTRIGHT FOR THE DURATION OF THE DRAG.** The compositor delivers pointer
				 * events to the surface UNDER the pointer: a hand that outruns the window puts the pointer on the
				 * desktop, or on the window BEHIND the one being moved, and the motion and the release stop arriving
				 * — MEASURED, a fast drag moved the window zero pixels and left it still believing a drag was in
				 * progress. The fallback grab the menus use is not enough for that second case: it only catches
				 * events over NO surface, so a pointer over a neighbour still starves the drag. `set_pointer_capture`
				 * is the real grab — nothing else hears the pointer until it is given back on the release. */
				[self cg_setPointerCapture:YES];
				return;
			}
		} else if ([theEvent type] == NSLeftMouseDragged && _cg_resizeEdges != 0) {
			/* **THE POINTER'S ABSOLUTE POSITION, WHICH IS WHAT A RESIZE IS MEASURED AGAINST.** The relative
			 * fallback reconstructs it from this window's own frame and the pointer's place in it — the same pair
			 * the move's fallback uses, and for the same reason: an edge is where the POINTER is, and a window that
			 * followed a delta instead would drift from the hand by every motion the compositor batched.
			 *
			 * **AND IT IS TAKEN FROM EVERY EVENT THAT CARRIES ONE, NOT ONLY FROM A PRESS THAT DID.** A resize has
			 * no grab OFFSET to derive — `_cg_resizeGrab` is an absolute point already — so a motion's own absolute
			 * position is usable the moment one arrives, and the drag does not care whether the press happened to
			 * come with one. That matters while the pointer is captured: the motions that cross onto a neighbour are
			 * exactly the ones whose absolute position is worth having, and they are the ones a press-time flag
			 * would have discarded. */
			NSPoint g;

			if ([theEvent cg_hasGlobalPoint]) {
				g = [theEvent cg_globalPoint];
			} else {
				NSPoint p = [theEvent locationInWindow];

				g.x = _frame.origin.x + p.x;
				g.y = _frame.origin.y + p.y;
			}
			/* THE RESIZE IS REMEMBERED, NOT MADE — one `set_frame` and one repaint per pass rather than per
			 * motion, which is the rule the move already follows. */
			_cg_resizePendingFrame = [self cg_frameForResizeToPoint:g];
			_cg_resizePending = YES;
			return;
		} else if ([theEvent type] == NSLeftMouseDragged && _cg_draggingChrome) {
			/* **THE ABSOLUTE POSITION WHEN THE COMPOSITOR SENT ONE, AND THE RELATIVE ONE ONLY AS A FALLBACK.** The
			 * relative arithmetic is correct while this client's frame and the compositor's surface agree, and WRONG
			 * the moment they do not — which a fast drag makes happen, because the compositor processes a batch of
			 * motions before it processes the `set_frame`s they produce, and the error COMPOUNDS. MEASURED: a fast
			 * drag moved the window hundreds of pixels past the pointer, while the slow one was exact. The absolute
			 * position has no such coupling — the window goes where the pointer is, whatever the round trip is doing. */
			NSPoint origin;

			if (_cg_dragUsesGlobal && [theEvent cg_hasGlobalPoint]) {
				NSPoint g = [theEvent cg_globalPoint];

				origin.x = g.x - _cg_dragGlobalOffset.x;
				origin.y = g.y - _cg_dragGlobalOffset.y;
			} else {
				NSPoint p = [theEvent locationInWindow];

				origin = _frame.origin;
				origin.x += p.x - _cg_dragGrab.x;
				origin.y += p.y - _cg_dragGrab.y;
			}
			/* **THE MOVE IS REMEMBERED, NOT MADE.** A pass is a frame, and applying every motion inside one sends the
			 * window along the SAMPLED PATH — every intermediate point a fast flick produced — instead of straight to
			 * where the pointer is now. The pass applies the LATEST one; see `-cg_applyPendingDrag`. */
			_cg_dragPendingOrigin = origin;
			_cg_dragPending = YES;
			return;
		} else if ([theEvent type] == NSLeftMouseDragged && _cg_pressedChrome >= 0) {
			/* **A HAND HOLDING A BUTTON DOWN IS THE BUTTON'S, NOT A VIEW'S.** The press never reached a view, so the
			 * drag that follows it must not either. What the drag IS for is the ink: the engine re-answers which button
			 * the pointer is over, `fn_chrome_state` reads that with the press, and the bar repaints only when the
			 * answer CHANGES — which is the same rule the hover already followed. It also settles the release below:
			 * `_cg_hoverChrome` says whether the pointer came back. */
			[self cg_updateTrackingForPoint:[theEvent locationInWindow]];
			return;
		} else if ([theEvent type] == NSLeftMouseUp &&
			   (_cg_pressedChrome >= 0 || _cg_draggingChrome || _cg_resizeEdges != 0)) {
			NSInteger pressed = _cg_pressedChrome;
			BOOL releaseIsOnIt = NO;

			if (_cg_draggingChrome) {
				[self cg_applyPendingDrag];	/* the drag's LAST move is not lost to a pass boundary */
				[self cg_setPointerCapture:NO];	/* the drag is over; the pointer is the compositor's again */
			} else if (_cg_resizeEdges != 0) {
				[self cg_applyPendingResize];	/* and a resize's last aim is not lost either */
				[self cg_setPointerCapture:NO];
			} else if (pressed >= 0) {
				NSPoint p = [theEvent locationInWindow];

				/* **AND ONLY A RELEASE THAT IS STILL ON THE BUTTON COUNTS.** The press said "this button"; the release
				 * says whether the hand is still of that mind. It is asked of the release's OWN point rather than of
				 * `_cg_hoverChrome`, because a release is not always preceded by a drag — a click that never moved has
				 * only these two events, and the hover would still be describing wherever the pointer was before. */
				releaseIsOnIt = ([self cg_chromeButtonAtPoint:p] == pressed);
				/* AND THE INK AFTER THE RELEASE IS THE POINTER'S ANSWER TOO, from that same point: a release just
				 * outside the X would otherwise leave it prelighted until the next motion came along to say otherwise. */
				[self cg_updateTrackingForPoint:p];
			}
			_cg_pressedChrome = -1;
			_cg_draggingChrome = NO;
			_cg_dragUsesGlobal = NO;
			_cg_resizeEdges = 0;
			[self setNeedsDisplay:YES];
			/* **AND THE ACTION GOES LAST, BECAUSE ONE OF THEM DESTROYS THE WINDOW.** `-performClose:` ends in
			 * `-close`, which destroys the surface and takes this window off the application's list — so every line
			 * above has to have run before it does. */
			if (releaseIsOnIt) {
				[self cg_performChromeButton:pressed];
			}
			return;
		}
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

/* **WHERE A CHROME BUTTON IS, WHICH IS THE SAME ANSWER THE PAINTER USES.** The layout is recomputed rather than
 * cached so that a button's rectangle follows its window's frame without anybody remembering to invalidate it —
 * a title bar that resized and kept a stale hit rect is the defect two copies of this arithmetic would produce. */
- (NSInteger)cg_chromeButtonAtPoint:(NSPoint)windowPoint
{
	fn_chrome_layout_t layout;
	int i;

	fn_chrome_layout(self, &layout);
	for (i = 0; i < AGChromeButtonCount; i++) {
		if (layout.present[i] && NSPointInRect(windowPoint, layout.rects[i])) {
			return i;
		}
	}
	return -1;
}

/* **WHAT A CHROME BUTTON DOES, IN THE ONE PLACE THAT SAYS SO.** Three things have to agree for a title bar to be
 * true — where a button IS (`fn_chrome_layout`), what state it is DRAWN in (`fn_chrome_state`), and what it DOES
 * (here) — and the third was missing: the rects and the ink were wired and the action was not, so a press lit the
 * theme's pressed art and a release did nothing at all.
 *
 * **EACH GOES THROUGH THE `-perform…` DOOR, WHICH IS THE ONE THE MENU ITEM ALSO SENDS.** Their whole reason for
 * existing is that a click on a piece of chrome and the same command from a menu must be the SAME act — a delegate
 * that refuses `-windowShouldClose:` refuses it in both places, and a subclass that overrides `-zoom:` gets the
 * button's behaviour too. Sending `-close`, `-miniaturize:` and `-zoom:` from here instead would be a second road
 * to each that skips every question the first one asks.
 *
 * **AND THE PILL IS THE TOOLBAR TOGGLE, WHICH IS WHY A WINDOW WITHOUT A TOOLBAR DOES NOT SHOW ONE AT ALL.** It
 * sends `-toggleToolbarShown:`, the same door a menu item sends and the same door the toolbar's own visibility uses.
 * The mark is laid out only when there is a toolbar to toggle (`fn_chrome_button_present`), so this case is reached
 * by a window that has one; a quiet door here is the belt to that braces rather than the mechanism. */
- (void)cg_performChromeButton:(NSInteger)index
{
	switch ((AGChromeButton)index) {
	case AGChromeButtonClose:
		[self performClose:self];
		break;
	case AGChromeButtonHide:
		/* **THE MINUS MARKS THE STATE AND ANNOUNCES IT; IT DOES NOT TAKE THE WINDOW OFF THE SCREEN**, and that is
		 * `-miniaturize:`'s own recorded state rather than this button's shortfall: there is no Dock to put a
		 * miniaturized window in and no door in the protocol to ask for one. Wiring the button to the door that
		 * EXISTS beats inventing a behaviour here that the tier cannot honour. */
		[self performMiniaturize:self];
		break;
	case AGChromeButtonMaximize:
		[self performZoom:self];
		break;
	case AGChromeButtonMenu:
		/* **THE PILL IS THE TOOLBAR TOGGLE, AND NOW THERE IS A TOOLBAR TO TOGGLE.** With none attached the door is a
		 * no-op, which is the same answer it gave when `NSToolbar` was absent — but the mark is wired, so a window with
		 * a toolbar behaves like one. */
		[self toggleToolbarShown:self];
		break;
	default:
		break;
	}
}

- (void)cg_setDragGuideRect:(NSRect)rect
{
	if (_cg_dragGuideActive && !NSEqualRects(_cg_dragGuideRect, rect)) {
		[_contentView setNeedsDisplayInRect:_cg_dragGuideRect];
	}
	_cg_dragGuideRect = rect;
	_cg_dragGuideActive = YES;
	[_contentView setNeedsDisplayInRect:rect];
}

- (void)cg_clearDragGuide
{
	if (_cg_dragGuideActive) {
		[_contentView setNeedsDisplayInRect:_cg_dragGuideRect];
	}
	_cg_dragGuideActive = NO;
}

- (void)cg_drawDragGuideInContext:(CGContextRef)c
{
	if (!_cg_dragGuideActive || c == NULL) {
		return;
	}
	CGColorRef colour = [[NSColor controlDarkShadowColor] CGColor];
	CGFloat width = _cg_dragGuideRect.size.width;

	if (width < 1.0) {
		width = 1.0;
	}
	CGContextSetFillColorWithColor(c, colour);
	CGContextFillRect(c, CGRectMake(_cg_dragGuideRect.origin.x, _cg_dragGuideRect.origin.y,
					width, _cg_dragGuideRect.size.height));
}

- (void)cg_suspendTrackingUpdates
{
	_cg_trackingSuspensions++;
}

- (void)cg_resumeTrackingUpdates
{
	if (_cg_trackingSuspensions > 0) {
		_cg_trackingSuspensions--;
	}
	if (_cg_trackingSuspensions == 0) {
		/* One fresh evaluation at the pointer's last position, because the drag may have ended somewhere the
		 * frozen bits do not describe. */
		[self cg_updateTrackingForPoint:[self mouseLocationOutsideOfEventStream]];
	}
}

- (void)cg_updateTrackingIfMovedToPoint:(NSPoint)windowPoint
{
	if (_cg_hasTrackingPoint && windowPoint.x == _cg_trackingPoint.x && windowPoint.y == _cg_trackingPoint.y) {
		return;
	}
	[self cg_updateTrackingForPoint:windowPoint];
}

- (void)cg_updateTrackingForPoint:(NSPoint)windowPoint
{
	NSMutableArray *hits;

	if (_cg_trackingSuspensions > 0) {
		return;
	}
	hits = [[NSMutableArray alloc] init];
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
	/* **AND THE CHROME'S OWN BUTTONS, WHICH ARE NOT VIEWS AND SO HAVE NO TRACKING AREA.** The pointer's position
	 * is all this needs: which button contains it decides the prelight, and a CHANGE of answer is the only thing
	 * that asks for a redraw — a re-evaluation that answers the same button must not repaint the bar. */
	{
		NSInteger hover = [self cg_chromeButtonAtPoint:windowPoint];

		if (hover != _cg_hoverChrome) {
			_cg_hoverChrome = hover;
			/* **AND ONLY THE STRIP REPAINTS.** A prelight is chrome ink and nothing else: asking for a whole-window
			 * repaint here is what a pointer crossing a stoplight used to cost, and a change of hovered BUTTON does not
			 * change a single content pixel. */
			[self cg_invalidateChrome];
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
- (BOOL)cg_ensureSurfaceWithPixels:(unsigned char *)pixels stride:(int)stride width:(int)bufferWidth
			   height:(int)bufferHeight
{
	NSInteger w, h;
	CGColorSpaceRef cs;

	if (![self cg_ensureWindow] || pixels == NULL || stride <= 0) {
		return NO;
	}
	/* **THE SURFACE IS THE FRAME, NOT THE CONTENT** — client-side decoration (appkit-plan §6 D6). The window owns
	 * every pixel it was given, its title bar included, so the surface spans the FRAME and `-display` blits it at
	 * (0,0) rather than skipping the chrome rows. THE CONTENT IS UNMOVED inside it: Cocoa's frame puts the chrome at
	 * the TOP, so the content still begins at the surface's origin and every view coordinate in this tree is what it
	 * was. */
	/* **THE BUFFER IS THE FRAME TIMES THE OUTPUT SCALE, AND THE CONTEXT IS TOLD SO.** A HiDPI client renders at the
	 * resolution the screen has and asks the compositor to place the buffer at the logical size; the frame stays in
	 * POINTS, so every view in this tree keeps drawing in points and the scale is applied exactly once — to the
	 * context's transform. That is the whole of the drawing half of HiDPI: Core Text rasterises at whatever the CTM
	 * says, so text comes out sharp with no change to a single view. */
	/* **THE BUFFER IS THE FRAME TIMES THE OUTPUT SCALE, AND THE CONTEXT IS TOLD SO.** A HiDPI client renders at the
	 * resolution the screen has and asks the compositor to place the buffer at the logical size; the frame stays in
	 * POINTS, so every view in this tree keeps drawing in points and the scale is applied exactly once — to the
	 * context's transform. That is the whole of the drawing half of HiDPI: Core Text rasterises at whatever the CTM
	 * says, so text comes out sharp with no change to a single view. */
	{
		double scale = AGWindowBufferScale(_agwindow);

		if (!(scale > 0.0)) {
			scale = 1.0;
		}
		_deviceScale = (CGFloat)scale;
	}
	/* **THE BITMAP IS THE BUFFER THE SEAM ACTUALLY MADE, NOT THIS WINDOW'S ARITHMETIC ABOUT IT.** The platform sizes
	 * it at `round(frame x scale)`, and a frame with a fractional edge would round differently here; the refused
	 * context that produced — "a row shorter than its width" — is exactly a 159-column bitmap in a 158-pixel stride.
	 * The dimensions therefore come back from `AGWindowBeginFrameSized` and are used as they are. */
	w = (NSInteger)bufferWidth;
	h = (NSInteger)bufferHeight;
	if (w <= 0 || h <= 0) {
		return NO;
	}
	if (_surface != NULL) {
		if ((NSInteger)CGBitmapContextGetWidth(_surface) == w &&
		    (NSInteger)CGBitmapContextGetHeight(_surface) == h &&
		    (int)CGBitmapContextGetBytesPerRow(_surface) == stride &&
		    _pixels == pixels) {
			return YES;
		}
		CGContextRelease(_surface);
		_surface = NULL;
		if (_ownsPixels) {
			free(_pixels);
		}
		_pixels = NULL;
	}
	/* THE FORMAT IS THE SEAM'S OWN, AND IT IS THE SAME PATTERN FOR THE SAME REASON: the seam's frame buffer is
	 * `XRGB8888`, which on a little-endian machine stores a pixel as B, G, R, X in memory. So the copy in
	 * `-display` is a memcpy and not a conversion, and getting the pattern wrong would be a red/blue swap, which
	 * is why the probe checks a colour rather than a byte.
	 *
	 * **AND IT IS THE `X` SPELLING RATHER THAN THE ALPHA ONE, BECAUSE A WINDOW IS OPAQUE.** `NoneSkipFirst` is
	 * the same word with the fourth byte NOT WRITTEN — which is what the seam already says that byte is — and
	 * the difference is not cosmetic: an alpha channel is exactly what STOPS a context from rendering smoothed
	 * text (`cg_font_smoothing` in CoreGraphics), so a window surface that carried one would draw every label on
	 * the desktop in grey coverage while the renderer underneath could have done better. A window's frame has no
	 * transparency to represent — its shadow is the SERVER's, around the frame and not in it — so this is the
	 * honest format for it as well as the one that makes the text look right. */
	/* **THE PIXELS ARE THE SEAM'S, AND THAT IS THE POINT.** The backing store used to be `calloc`'d here and then
	 * copied into the wire buffer every frame; now the wire buffer IS the surface, so the copy is not made cheaper,
	 * it does not exist. `_ownsPixels` stays because a caller with no seam could still supply its own memory, and
	 * freeing the seam's would be a free of a GPU mapping. */
	if (_ownsPixels) {
		free(_pixels);
	}
	_pixels = pixels;
	_ownsPixels = NO;
	cs = CGColorSpaceCreateDeviceRGB();
	/* **A TRANSPARENT WINDOW'S SURFACE CARRIES ALPHA AND AN OPAQUE ONE'S DOES NOT**, and the two are the same word
	 * with the fourth byte treated differently. `NoneSkipFirst` is what lets CoreGraphics smooth text — an alpha
	 * channel switches sub-pixel coverage off — so an opaque window keeps it; `PremultipliedFirst` is what a
	 * transparent window's pixels must be, because the compositor BLENDS them (source-over) and premultiplied BGRA
	 * is exactly what ARGB8888 little-endian holds. */
	_surface = CGBitmapContextCreate(_pixels, (size_t)w, (size_t)h, 8, (size_t)stride, cs,
					 _opaque ? (uint32_t)(kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little)
						 : (uint32_t)(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little));
	CGColorSpaceRelease(cs);
	if (_surface == NULL) {
		_pixels = NULL;
		return NO;
	}
	_surfaceWidth = (int)w;
	_surfaceHeight = (int)h;
	/* **AND EVERYTHING FROM HERE DOWN DRAWS IN POINTS.** The bitmap is `w x h` DEVICE pixels; scaling the CTM by the
	 * same factor means a view that says `NSMakeRect(0, 0, 100, 40)` still covers a hundred points — a hundred device
	 * pixels at 1x and two hundred at 2x — and no drawing code anywhere has to know which screen it is on. */
	if (_deviceScale != 1.0) {
		CGContextScaleCTM(_surface, _deviceScale, _deviceScale);
	}
	if (getenv("AG_SCALE_DIAG") != NULL) {
		CGAffineTransform t = CGContextGetCTM(_surface);

		fprintf(stderr, "  DIAG scale: frame %gx%g deviceScale %g -> bitmap %ldx%ld stride %d, "
				"ctm a=%g d=%g tx=%g ty=%g\n", (double)_frame.size.width, (double)_frame.size.height,
			(double)_deviceScale, (long)CGBitmapContextGetWidth(_surface),
			(long)CGBitmapContextGetHeight(_surface), stride, (double)t.a, (double)t.d, (double)t.tx,
			(double)t.ty);
	}
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
		/* **THE SIZE IS TAKEN NOW AND EVERYTHING ELSE IS TAKEN LATER.** This runs INSIDE libwayland's listener
		 * dispatch, and it used to assign the size, mark the window dirty and DRAW — from inside a native
		 * callback. Three things were wrong with that. The draw happened with the content view still at its old
		 * frame, because the layout tail had not run, so the frame painted was stale geometry. A delegate reached
		 * from that draw could close the window while the surface's own callbacks were still on the stack. And
		 * the resize was never ANNOUNCED at all, so the compositor's resize and the application's took two
		 * different paths.
		 *
		 * So the SIZE is assigned here — it must be, because the input events that follow in this same native
		 * batch are converted through this frame — and the layout, repaint and notification are deferred to the
		 * pump, one pass per batch. See `_cg_configurePending`. */
		_frame.size.width = (CGFloat)event->x;
		_frame.size.height = (CGFloat)event->y;
		_cg_configurePending = YES;
		break;
	case AGEventClose:
		_cg_closeRequested = YES;
		break;
	case AGEventReopen:
		/* **A DOCK CLICK WITH NOTHING TO RAISE, ASKED OF THIS WINDOW BECAUSE A WINDOW IS THE ADDRESS.** The answer
		 * is the application's — its delegate's, and ultimately its own — so the window hands it straight on and
		 * does nothing else: this window may not even be the one that opens. */
		[[NSApplication sharedApplication] cg_handleReopen];
		break;
	case AGEventKey:
	case AGEventPointerButton:
	case AGEventPointerMotion:
	case AGEventPointerEnter:
	case AGEventPointerAxis: {
		NSEvent *ev;
		NSPoint p = fn_window_point(self, event->x, event->y);

		/* A SCROLL IS A POINTER EVENT FOR THE SAME REASON A CLICK IS: it goes to whatever is under the pointer, so
		 * the pointer's remembered position is where the wheel happened. It does NOT change the button state and it
		 * does not make the window key — a wheel is not a press. */
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

/* **TAKE THE POINTER'S FALLBACK WHILE A POPUP TRACKS.** A menu's window asks for this when its session begins and
 * gives it back when the session ends, so a click that lands on the DESKTOP — where a Wayland compositor would
 * otherwise have nobody to deliver it to — arrives at the menu and dismisses it. See `AGWindowSetPointerGrab`. */
- (void)cg_setPointerGrab:(BOOL)flag
{
	if (_agwindow != NULL) {
		AGWindowSetPointerGrab(_agwindow, flag ? 1 : 0);
	}
}

/* **THE DRAG'S, WHICH IS A DIFFERENT DOOR BECAUSE IT MEANS SOMETHING DIFFERENT.** The grab above is a FALLBACK: it
 * catches pointer events that would go to NO surface, and a surface under the pointer still takes them — which is
 * exactly what a menu bar needs, because the bar is a separate window from the menu it opened and the pointer must
 * be able to cross back to it. A window being dragged or resized needs the opposite: it MOVES OUT FROM UNDER THE
 * HAND, so "what is under the pointer" stops being a useful question the moment the drag starts. MEASURED, with
 * the fallback: resizing a window out over its neighbour stopped following the pointer the instant the hand crossed
 * onto the neighbour, and the press and release had gone there too, so the window went on believing it was still
 * being resized. The capture is a REAL grab — motion and buttons go to this window wherever the pointer is, until
 * the last button comes up. */
- (void)cg_setPointerCapture:(BOOL)flag
{
	if (_agwindow != NULL) {
		AGWindowSetPointerCapture(_agwindow, flag ? 1 : 0);
	}
}

/* **THE DRAG'S MOVE, MADE ONCE PER PASS AND ONLY EVER AT THE LATEST POINTER.** Every motion inside a frame updates
 * the target and only the LAST one is applied, so a fast flick puts the window WHERE THE POINTER IS rather than
 * walking it through the points the hand passed over — MEASURED, that walk is what "it crawls towards the target,
 * following the path of the mouse" is. One call per pass also means one `set_frame` and one flush per frame instead
 * of one per motion. `NSApplication -updateWindows` is what calls this, at the end of every pass. */
- (void)cg_applyPendingDrag
{
	if (_cg_dragPending) {
		NSPoint origin = _cg_dragPendingOrigin;

		_cg_dragPending = NO;
		[self setFrameOrigin:origin];
	}
}

/* **AND THE RESIZE'S AIM, MADE ONCE PER PASS LIKE THE MOVE'S.** The hand's intermediate positions are not frames
 * either, and one `set_frame` per pass is what keeps a fast diagonal drag from sending the compositor a stream of
 * sizes nobody sees. */
- (void)cg_applyPendingResize
{
	if (_cg_resizePending) {
		NSRect want = _cg_resizePendingFrame;
		NSRect start = _cg_resizeStartFrame;
		BOOL left = (_cg_resizeEdges & FN_RESIZE_LEFT) != 0;
		BOOL bottom = (_cg_resizeEdges & FN_RESIZE_BOTTOM) != 0;

		_cg_resizePending = NO;
		[self setFrame:want display:YES];
		/* **AND THE EDGE THE HAND DID NOT TAKE IS PUT BACK WHERE IT WAS.** `-setFrame:` clamps the size to the
		 * minimum and maximum sizes, and a clamp that bites on a drag of the LEFT or the BOTTOM edge would move the
		 * RIGHT or the TOP one — the edge the hand never touched. The origin is corrected from the size that was
		 * actually achieved, which is the only place the clamped answer exists. */
		if (left || bottom) {
			NSRect got = _frame;

			if (left) {
				got.origin.x = NSMaxX(start) - got.size.width;
			}
			if (bottom) {
				got.origin.y = NSMaxY(start) - got.size.height;
			}
			if (got.origin.x != _frame.origin.x || got.origin.y != _frame.origin.y) {
				[self setFrameOrigin:got.origin];
			}
		}
	}
}

/* **WHERE A RESIZE IS AIMING, FROM THE POINTER'S OWN POSITION — AND THIS IS WHERE THE DELEGATE IS ASKED.**
 * `-setFrame:` deliberately does NOT send `-windowWillResize:toSize:` (its own comment says why: a programmatic
 * frame set is not a drag), so the drag is the door that must, and Apple's contract is that the answer is the size
 * to USE rather than a permission — a delegate that wants to refuse returns the size the window already has.
 *
 * EACH EDGE THE HAND TOOK MOVES AND THE ONE OPPOSITE IT DOES NOT, which is why the two origin terms are computed
 * from the STARTING frame's far edge rather than from the frame as it goes: an edge that is not being dragged must
 * be a CONSTANT, not a value that drifts with each motion. */
- (NSRect)cg_frameForResizeToPoint:(NSPoint)p
{
	NSRect start = _cg_resizeStartFrame;
	NSRect frame = start;
	CGFloat right = NSMaxX(start);
	CGFloat top = NSMaxY(start);
	CGFloat fromLeft = _cg_resizeGrab.x - start.origin.x;
	CGFloat fromRight = right - _cg_resizeGrab.x;
	CGFloat fromBottom = _cg_resizeGrab.y - start.origin.y;
	CGFloat fromTop = top - _cg_resizeGrab.y;
	NSSize proposed;

	if (_cg_resizeEdges & FN_RESIZE_LEFT) {
		frame.origin.x = p.x - fromLeft;	/* the hand keeps the hold it took, so the edge does not jump */
		frame.size.width = right - frame.origin.x;
	}
	if (_cg_resizeEdges & FN_RESIZE_RIGHT) {
		frame.size.width = (p.x + fromRight) - frame.origin.x;
	}
	if (_cg_resizeEdges & FN_RESIZE_BOTTOM) {
		frame.origin.y = p.y - fromBottom;
		frame.size.height = top - frame.origin.y;
	}
	if (_cg_resizeEdges & FN_RESIZE_TOP) {
		frame.size.height = (p.y + fromTop) - frame.origin.y;
	}
	/* A WINDOW WHOSE EDGE IS DRAGGED PAST ITS OPPOSITE ONE HAS NO SIZE, and a frame of zero is not a window: the
	 * backing store would be empty and the compositor would be handed a surface with no area. One point is the
	 * floor here and `-setFrame:`'s own minimum may raise it; this is the geometry that must never be degenerate. */
	if (frame.size.width < 1.0) {
		frame.size.width = 1.0;
	}
	if (frame.size.height < 1.0) {
		frame.size.height = 1.0;
	}
	proposed = frame.size;
	if (_delegate != nil && [_delegate respondsToSelector:@selector(windowWillResize:toSize:)]) {
		proposed = [(id <NSWindowDelegate>)_delegate windowWillResize:self toSize:proposed];
	}
	if (proposed.width < 1.0) {
		proposed.width = 1.0;
	}
	if (proposed.height < 1.0) {
		proposed.height = 1.0;
	}
	if (_cg_resizeEdges & FN_RESIZE_LEFT) {
		frame.origin.x = right - proposed.width;
	}
	if (_cg_resizeEdges & FN_RESIZE_BOTTOM) {
		frame.origin.y = top - proposed.height;
	}
	frame.size = proposed;
	return frame;
}

/* DRAW AND PRESENT. The content view draws through an `NSGraphicsContext` over the pixels the seam handed over, so
 * there is no copy — the buffer CoreGraphics writes IS the buffer the compositor samples. */
/* **DRAW ONLY WHAT CHANGED.** A full `-cg_drawFrame` fills the whole content surface and walks the whole view tree;
 * a divider drag changes a few strips of one window many times a second, and that full pass was the difference
 * between a smooth gutter and a crawling one. The dirty rectangle is the union of every invalidated view below the
 * content view, converted into content coordinates; only the named rectangle is painted and cleared.
 *
 * **AND THE RECTANGLE IS WIDENED TO WHAT THE BUFFER IS MISSING, BECAUSE THE SEAM HAS TWO OF THEM.** A partial paint
 * leans on the pixels outside its damage still being right, which was true while a window had one buffer and is not
 * any more: the seam alternates two (one on the glass, one being drawn — see `AGWindowServer-Wayland.c`), so the
 * buffer this pass lands in last held the frame BEFORE the one a person is looking at. The region that changed since
 * is the other buffer's damage, and it is added here — the pair of records in `NSWindow.h` is that ledger. A buffer
 * with no record at all (the first frame, a resize, a reallocation) is painted whole, which is the only honest
 * answer about pixels nobody has described. */
/* SEE `NSWindow_internal.h`: y-up rectangle into top-down rows, clamped to the surface. */
+ (NSRange)cg_bufferRowsForDirtyRect:(NSRect)dirty surfaceHeight:(NSInteger)surfaceHeight
{
	NSInteger y0 = (NSInteger)floor((double)dirty.origin.y);
	NSInteger y1 = (NSInteger)ceil((double)(dirty.origin.y + dirty.size.height));

	if (y0 < 0) {
		y0 = 0;
	}
	if (y1 > surfaceHeight) {
		y1 = surfaceHeight;
	}
	if (y1 <= y0) {
		return NSMakeRange(0, 0);
	}
	return NSMakeRange((NSUInteger)(surfaceHeight - y1), (NSUInteger)(y1 - y0));
}

/* **WHICH OF THE SEAM'S TWO BUFFERS THIS IS, BY ITS PIXELS.** -1 means neither of the two on record, which is what a
 * buffer that has just been made looks like. The pointer is the identity because it is the one thing about a buffer
 * that survives a reallocation without this class having to be told. */
- (NSInteger)cg_paintSlotForPixels:(void *)pixels
{
	NSInteger i;

	for (i = 0; i < 2; i++) {
		if (_cg_paintPixels[i] == pixels) {
			return i;
		}
	}
	return -1;
}

/* THE SLOT A NEW POINTER IS RECORDED IN: one nothing holds, or the older of the two. A THIRD BUFFER MEANS ONE OF
 * THE TWO RECORDS DESCRIBES SOMETHING GONE, and then neither can be trusted to describe the live ones either — both
 * start again from "unknown", which is a whole-frame paint and not a wrong partial one. */
- (NSInteger)cg_claimPaintSlotForPixels:(void *)pixels
{
	NSInteger slot = (_cg_paintPixels[0] == NULL) ? 0 : ((_cg_paintPixels[1] == NULL) ? 1 : 0);

	if (_cg_paintPixels[slot] != NULL) {
		_cg_paintPixels[1 - slot] = NULL;
		_cg_paintMissing[1 - slot] = NSZeroRect;
	}
	_cg_paintPixels[slot] = pixels;
	_cg_paintMissing[slot] = NSZeroRect;
	return slot;
}

/* **WHAT WAS PAINTED IS CURRENT IN THIS BUFFER AND MISSING FROM THE OTHER ONE.** That single sentence is the whole of
 * the ledger: a buffer is current where it was last painted, so every later paint into the other buffer is a
 * difference this one does not have. Union rather than replace, because a run of paints into one buffer accumulates
 * damage the other has not seen. */
- (void)cg_recordPaintInSlot:(NSInteger)slot rect:(NSRect)painted
{
	NSInteger other = slot ^ 1;

	_cg_paintMissing[slot] = NSZeroRect;
	_cg_paintMissing[other] = NSUnionRect(_cg_paintMissing[other], painted);
}

/* **A PIECE ROUNDED OUT TO WHOLE DEVICE PIXELS, AT THE MOMENT IT IS PAINTED.** A view's damage lands on point
 * boundaries and at a fractional scale those are not pixel boundaries: painting a band whose edge falls between two
 * pixels makes CoreGraphics CLIP it with partial coverage, so the last row is composited at 30-70% over the old content
 * instead of being replaced — MEASURED as the faint washed line a person saw through the demo's buttons and captions,
 * which was each scroll strip's own edge. Rounding OUTWARD paints at most one extra pixel per edge, and that pixel is
 * drawn with the content that belongs there, so over-paint is the only cost. IT IS DONE HERE AND NOT WHEN THE PIECES
 * ARE COLLECTED, because two pieces that are merely ADJACENT (a strip and the scroller beside it) would then intersect
 * and the merge rule would union them into the bounding box — the whole visible area, which is the cost this region
 * exists to avoid. */
- (NSRect)cg_deviceOutward:(NSRect)rect
{
	CGFloat scale = [self userSpaceScaleFactor];
	CGFloat x0, y0, x1, y1;

	if (!(scale > 0.0) || scale == 1.0) {
		return rect;
	}
	x0 = (CGFloat)(floor((double)(rect.origin.x * scale)) / (double)scale);
	y0 = (CGFloat)(floor((double)(rect.origin.y * scale)) / (double)scale);
	x1 = (CGFloat)(ceil((double)((rect.origin.x + rect.size.width) * scale)) / (double)scale);
	y1 = (CGFloat)(ceil((double)((rect.origin.y + rect.size.height) * scale)) / (double)scale);
	return NSMakeRect(x0, y0, x1 - x0, y1 - y0);
}

/* **ONE MORE PIECE TO DRAW, WITH THE MERGE RULE THE VIEW TREE USES.** Overlapping pieces are unioned, separate ones are
 * kept apart, and a full budget collapses to the bounding box — over-paint and never a miss, for the same reason as
 * `-cg_addToDirtyRegion:` (which cannot be reused: this list is the window's and that one is a view's). */
- (void)cg_addPaintRect:(NSRect)rect to:(NSRect *)out count:(NSUInteger *)count
{
	NSUInteger i;

	if (NSIsEmptyRect(rect)) {
		return;
	}
	for (i = 0; i < *count; i++) {
		if (NSIntersectsRect(out[i], rect)) {
			out[i] = NSUnionRect(out[i], rect);
			return;
		}
	}
	if (*count < APPKIT_DAMAGE_RECTS) {
		out[*count] = rect;
		(*count)++;
		return;
	}
	for (i = 1; i < *count; i++) {
		out[0] = NSUnionRect(out[0], out[i]);
	}
	out[0] = NSUnionRect(out[0], rect);
	*count = 1;
}

/* THE WHOLE FRAME, in the space these rectangles live in (see `+cg_bufferRowsForDirtyRect:` for the mirroring). */
- (NSRect)cg_wholeFrameRect
{
	return NSMakeRect(0.0, 0.0, _frame.size.width, _frame.size.height);
}

/* **MOVE PIXELS INSTEAD OF DRAWING THEM.** `rect` is in this window's drawing space (content points, y UP, the space
 * `-cg_drawFrameDirty:` fills); `delta` is how far the content moved in those points. Every destination pixel asks for
 * the source pixel at `destination - delta` — which is the same sentence as "the picture slid by delta" — and the rows
 * are mirrored once on the way in, because the surface is top down and the rectangle is not.
 *
 * PIXELS THAT HAVE NO SOURCE ARE LEFT ALONE, and that is the contract rather than an omission: they are the strip
 * that scrolled into view, and the caller has already marked it for drawing. Rows or columns whose source falls
 * outside the buffer are skipped by the same rule, so a scroll to the end of a document copies what overlaps and draws
 * the rest. */
- (BOOL)cg_copyRect:(NSRect)rect from:(const uint32_t *)previous stride:(int)previousStride delta:(NSSize)delta
{
	NSInteger surfaceHeight;
	NSInteger surfaceWidth;
	NSInteger left, right;
	NSInteger dy, dx;
	NSInteger row;
	NSInteger rowEnd;
	NSInteger destinationStride;
	NSInteger columnLow, columnHigh;
	unsigned char *destination;
	const unsigned char *source;
	NSRange rows;
	CGFloat scale;

	if (_surface == NULL || _pixels == NULL || previous == NULL || previousStride <= 0) {
		return NO;
	}
	destinationStride = (NSInteger)CGBitmapContextGetBytesPerRow(_surface);
	if (destinationStride != (NSInteger)previousStride) {
		return NO;
	}
	surfaceWidth = (NSInteger)CGBitmapContextGetWidth(_surface);
	surfaceHeight = (NSInteger)CGBitmapContextGetHeight(_surface);
	/* **THE RECTANGLE IS IN POINTS, THE BUFFER IS IN DEVICE PIXELS, AND THE EDGES ARE ROUNDED TO THE NEAREST PIXEL.**
	 * Every rectangle that reaches this door is on the device grid already — `-scrollToPoint:` snaps the position and
	 * `-tile` puts the clip view itself on whole pixels — so nearest is the exact answer, and rounding OUTWARD was
	 * MEASURED wrong: a point divided by the scale and multiplied back does not always land on the integer it started
	 * from (11.261 x 1.33203 = 14.999...), so `floor` copied one row too many and left a one-pixel line along the clip
	 * view's top edge — content where a repaint draws the border. */
	scale = [self userSpaceScaleFactor];
	/* **INWARD, SO A COPY NEVER TOUCHES A PIXEL ITS RECTANGLE DOES NOT OWN.** The rectangle handed here is a clip view's
	 * visible area, and it need not sit on the device grid (this tier lays views out in points at a fractional scale,
	 * deliberately: snapping the layout to whole pixels is what MEASURED a one-pixel seam through the demo's controls).
	 * Rounding OUTWARD escapes by a fraction of a pixel into the enclosing view's border, where a copy is a smear;
	 * rounding inward leaves that sliver to the repaint, which the caller has already marked. The cost is a sub-pixel
	 * edge row/column that is one scroll step behind — invisible at a fractional scale, and never a wrong region. */
	{
		NSInteger deviceLeft = (NSInteger)ceil((double)(rect.origin.x * scale));
		NSInteger deviceRight = (NSInteger)floor((double)((rect.origin.x + rect.size.width) * scale));
		NSInteger deviceTop = (NSInteger)ceil((double)(rect.origin.y * scale));
		NSInteger deviceBottom = (NSInteger)floor((double)((rect.origin.y + rect.size.height) * scale));

		if (deviceLeft < 0) {
			deviceLeft = 0;
		}
		if (deviceRight > surfaceWidth) {
			deviceRight = surfaceWidth;
		}
		if (deviceRight <= deviceLeft || deviceBottom <= deviceTop) {
			return NO;
		}
		left = deviceLeft;
		right = deviceRight;
		rows = [[self class] cg_bufferRowsForDirtyRect:
				NSMakeRect((CGFloat)deviceLeft, (CGFloat)deviceTop,
					   (CGFloat)(deviceRight - deviceLeft), (CGFloat)(deviceBottom - deviceTop))
						     surfaceHeight:surfaceHeight];
	}
	if (rows.length == 0 || right <= left) {
		return NO;
	}
	dy = (NSInteger)llround((double)(delta.height * scale));
	dx = (NSInteger)llround((double)(delta.width * scale));
	/* DESTINATION row r takes SOURCE row r + dy, because a row's index grows DOWNWARD while the delta is stated
	 * upward: content that moved up the window has its pixels at a HIGHER row number than it did. */
	row = (NSInteger)rows.location;
	rowEnd = (NSInteger)(rows.location + rows.length);
	/* AND THE COLUMNS ARE THE SAME ARITHMETIC UNMIRRORED: destination column c takes source column c - dx. */
	columnLow = (dx > left) ? dx : left;
	columnHigh = (surfaceWidth + dx < right) ? (surfaceWidth + dx) : right;
	if (columnHigh <= columnLow) {
		return NO;
	}
	destination = (unsigned char *)_pixels;
	source = (const unsigned char *)previous;
	for (; row < rowEnd; row++) {
		NSInteger sourceRow = row + dy;

		if (sourceRow < 0 || sourceRow >= surfaceHeight) {
			continue;	/* the strip: drawn, not copied */
		}
		memcpy(destination + (size_t)row * (size_t)destinationStride + (size_t)columnLow * 4u,
		       source + (size_t)sourceRow * (size_t)previousStride + (size_t)(columnLow - dx) * 4u,
		       (size_t)(columnHigh - columnLow) * 4u);
	}
	return YES;
}

/* **WHAT A SCROLL REQUESTS, AND WHEN IT HAS TO GIVE UP.** Recorded rather than copied, because the frame to copy from
 * is the compositor's and the paint is what owns the begin/end pair. Two rules make it safe:
 *
 *   1. A SECOND MOVE BEFORE THE PAINT COULD NOT BE ONE TRANSFORM unless it is the same rectangle moving the same way
 *      again — which is a scroller being dragged — and then the deltas add. Anything else drops the copy and marks
 *      both buffers for a repaint of the two rectangles, which is what the caller would have got without this door.
 *   2. IT IS CLEARED BY THE PAINT THAT APPLIES IT, because a committed frame already has the translation in its
 *      pixels; a paint that is REFUSED leaves it, which is right — no frame was committed, so the same delta still
 *      describes the move from the frame on the glass.
 *
 * The answer is whether the fast path was taken: NO means "leave your whole bounds dirty", which is a repaint and
 * never a wrong picture. */
- (BOOL)cg_scrollContentInRect:(NSRect)rect inView:(NSView *)view by:(NSSize)delta
{
	NSRect inWindow;


	if (_agwindow == NULL || view == nil || _contentView == nil) {
		return NO;
	}
	if (delta.width == 0.0 && delta.height == 0.0) {
		return NO;
	}
	/* **A COPY MOVES WHOLE PIXELS, SO A FRACTIONAL MOVEMENT IS NOT ONE.** `-scrollToPoint:` snaps a scroll position to
	 * the device grid, which is what makes this true for every scroll the tier performs; a caller that moved the origin
	 * off the grid by hand gets a repaint, and a repaint is only slower. */
	{
		CGFloat scale = [self userSpaceScaleFactor];
		double dx = (double)(delta.width * scale);
		double dy = (double)(delta.height * scale);

		if (fabs(dx - floor(dx + 0.5)) > 0.01 || fabs(dy - floor(dy + 0.5)) > 0.01) {
			return NO;
		}
	}
	/* **AND THERE HAS TO BE A FRAME TO READ BEFORE THE REQUEST IS WORTH RECORDING.** The seam refuses when nothing has
	 * been committed yet (the first paint) or when the buffer is a GPU one; the paint path asks again, because the size
	 * has to match too and only it knows the geometry being drawn. */
	if (AGWindowPreviousFrameSized(_agwindow, NULL, NULL, NULL) == NULL) {
		return NO;
	}
	/* THE RECTANGLE IS TAKEN INTO THE WINDOW'S OWN DRAWING SPACE — the space `dirty` rects are in — by converting
	 * rather than by arithmetic on frames, because a clip view inside a flipped document is not a translation of its
	 * superview. */
	inWindow = [view convertRect:rect toView:nil];
	if (NSIsEmptyRect(inWindow)) {
		return NO;
	}
	if (_cg_scrollPending) {
		if (NSEqualRects(_cg_scrollRect, inWindow)) {
			_cg_scrollDelta.width += delta.width;
			_cg_scrollDelta.height += delta.height;
			[self setViewsNeedDisplay:YES];
			return YES;
		}
		/* A DIFFERENT REGION MOVED: two translations are not one. Both regions are repainted by the next pass. */
		_cg_paintMissing[0] = NSUnionRect(_cg_paintMissing[0], _cg_scrollRect);
		_cg_paintMissing[1] = NSUnionRect(_cg_paintMissing[1], _cg_scrollRect);
		_cg_paintMissing[0] = NSUnionRect(_cg_paintMissing[0], inWindow);
		_cg_paintMissing[1] = NSUnionRect(_cg_paintMissing[1], inWindow);
		_cg_scrollPending = NO;
		_cg_scrollRect = NSZeroRect;
		_cg_scrollDelta = NSZeroSize;
		return NO;
	}
	_cg_scrollRect = inWindow;
	_cg_scrollDelta = delta;
	_cg_scrollPending = YES;
	[self setViewsNeedDisplay:YES];
	return YES;
}

/* **THE STRIP THE CHROME PAINTER FILLS, WHICH IS THE TITLE BAR AND NOT THE TOOLBAR BAND UNDER IT.** The toolbar is a
 * VIEW in the band above the content, and it fills that band with the same face colour itself (`fn_draw_chrome` says so
 * where it draws); a face fill over the whole strip erases the view's items and, on a chrome-only pass, nothing puts them
 * back — MEASURED as a toolbar whose icons blinked with the pointer, because a hover repainted the chrome and wiped
 * them. So the fill covers what the painter draws and stops where the toolbar's own author starts. */
- (NSRect)cg_titleBarRect
{
	NSRect whole = [self cg_wholeFrameRect];
	NSRect content = [self contentRectForFrameRect:_frame];
	CGFloat bottom = content.size.height + fn_toolbar_height(self);
	CGFloat top = whole.size.height;

	if (bottom < 0.0) {
		bottom = 0.0;
	}
	if (bottom > top) {
		bottom = top;
	}
	return NSMakeRect(0.0, bottom, whole.size.width, top - bottom);
}

/* AND THE STRIP THE DIRTY PATH PAINTS WHATEVER THE CONTENT'S DAMAGE WAS, because the chrome is above the content and
 * is not part of that union. THIS IS THE WHOLE STRIP, TOOLBAR BAND INCLUDED, because it is what the other buffer's
 * record needs: the band's ink is part of the chrome's frame even though the band's author is a view. */
- (NSRect)cg_chromeRect
{
	NSRect whole = [self cg_wholeFrameRect];
	NSRect content = [self contentRectForFrameRect:_frame];
	CGFloat bottom = content.size.height;

	if (bottom < 0.0) {
		bottom = 0.0;
	}
	if (bottom > whole.size.height) {
		bottom = whole.size.height;
	}
	return NSMakeRect(0.0, bottom, whole.size.width, whole.size.height - bottom);
}

- (void)cg_drawFrameDirty:(const NSRect *)damage count:(NSUInteger)count
{
	CGContextRef c;
	uint32_t *frame;
	uint32_t *previous = NULL;
	int stride = 0;
	int buffer_w = 0, buffer_h = 0;
	int previousStrideForCopy = 0;
	BOOL canCopy = NO;
	BOOL scrolled = NO;
	NSInteger slot;
	NSRect changed;
	NSRect dirty = NSZeroRect;
	NSRect paint[APPKIT_DAMAGE_RECTS];
	NSUInteger paintCount = 0;
	/* **WHAT THIS PASS TELLS THE COMPOSITOR IT CHANGED**, in the window's own drawing space: the pieces it painted,
	 * plus a scroll's translated block — because that copy moves content to coordinates where the screen has something
	 * else. A copy made INTO this buffer from the frame on the glass (the missing-pixel ledger) is deliberately not
	 * here: it writes the pixels the screen already shows, and the compositor keeps the screen now. See the note at the
	 * reporting block. */
	NSRect reported[APPKIT_DAMAGE_RECTS];
	NSUInteger reportedCount = 0;
	NSUInteger i;
	NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];

	if (_agwindow == NULL || (count == 0 && !_cg_chromeDirty)) {
		return;
	}
	/* **A SHEET'S CHROME IS REPAINTED ON EVERY PASS THAT PAINTS ANYTHING, AND THE REASON IS WHERE IT LIVES.** A sheet has
	 * no strip; what it paints is its PARENT'S TITLE BAR BORDER across itself, one row inside its own body (see
	 * `fn_draw_chrome`) — inside the CONTENT's rectangle, which is the whole frame. The content walk below repaints that
	 * row whenever the content's top edge is damaged, and the chrome painter is the only thing that puts the line back,
	 * so gating it on `_cg_chromeDirty` alone leaves the border missing after any content repaint there — a sheet with
	 * the bar's line over half of it. It is one fill, and this is the flag that says to make it. */
	BOOL repaintChrome = (_cg_chromeDirty || [self isSheet]) ? YES : NO;
	/* **THE BOX IS KEPT BESIDE THE PIECES, FOR THE THREE QUESTIONS THAT WANT ONE RECTANGLE**: what the buffer ledger
	 * records, what the diagnostic prints, and what the fallback paints when a copy has no source. The PIECES are what
	 * the background and the view walk use, which is the whole point of the list — see `NSView.h`. */
	for (i = 0; i < count; i++) {
		dirty = NSIsEmptyRect(dirty) ? damage[i] : NSUnionRect(dirty, damage[i]);
	}
	/* **AND A DAMAGE THAT REACHES THE BOTTOM ROW OF THE CHROME PAYS FOR THE CHROME, BECAUSE THE HAIRLINE LIVES THERE.** The
	 * one-point rule between the chrome and the content is the CONTENT'S TOP ROW (see `fn_draw_chrome`) — drawn by the
	 * chrome painter, over pixels the content view also owns — so any content repaint that touches that row erases it
	 * and nothing puts it back while `_cg_chromeDirty` is clear. MEASURED at a fractional scale: a window that had
	 * repainted its content once had no line under its title bar at all, which is also the line a sheet wears across
	 * itself — a sheet's half of it present and the parent's half gone. The line is one row, so the repaint it costs is
	 * the strip's own; the flag is what makes every other part of this pass (the face fill, the walk's order, the
	 * buffer ledger) treat it as a chrome pass rather than one more thing to remember. */
	if ([self hasTitleBar]) {
		CGFloat contentHeight = [self contentRectForFrameRect:_frame].size.height;

		if (NSIntersectsRect(dirty, NSMakeRect(0.0, contentHeight - 1.0, _frame.size.width, 1.0))) {
			_cg_chromeDirty = YES;
			repaintChrome = YES;
		}
	}
	if (!AGWindowServerCanWrite(fn_server())) {
		return;
	}
	/* **THE FRAME IS ASKED FOR BEFORE THE SURFACE IS CHOSEN, BECAUSE THE FRAME IS THE SURFACE.** Drawing used to
	 * happen first and be copied after; now the buffer the compositor will sample is the context's pixels, so a
	 * refused frame is refused before a single pixel is drawn. */
	frame = AGWindowBeginFrameSized(_agwindow, &stride, &buffer_w, &buffer_h);
	if (frame == NULL) {
		return;
	}
	if (![self cg_ensureSurfaceWithPixels:(unsigned char *)frame stride:stride width:buffer_w
					       height:buffer_h]) {
		return;
	}
	/* **AND THE DAMAGE BECOMES WHAT THIS BUFFER IS MISSING, NOT ONLY WHAT THE VIEWS CHANGED.** A partial paint
	 * keeps every pixel outside its rectangle, which is right for the buffer that was on the glass and wrong for
	 * this one: see the note above this method. A buffer nobody has described is painted whole.
	 *
	 * **AND WHAT THE VIEWS CHANGED IS KEPT SEPARATELY, BECAUSE IT IS THE ONLY PART THE OTHER BUFFER LACKS.** The
	 * rectangle below grows to include `_cg_paintMissing[slot]` — the pixels THIS buffer was behind on — and those
	 * are pixels the other buffer already has, by definition. Recording the widened rectangle as the other buffer's
	 * damage therefore claims it is stale exactly where it is current, and the pair then ping-pongs: each paint
	 * tells the other it is missing everything it just caught up on. MEASURED before this line existed: 243 of 245
	 * paints in one scroller drag were the whole 700x522 frame at 110-215 ms each, so the knob crawled behind the
	 * pointer. With the views' own damage recorded, the third paint onwards is that damage and nothing else. */
	changed = dirty;
	/* **AND WHAT THIS BUFFER IS MISSING IS COPIED RATHER THAN DRAWN, WHICH IS THE OTHER HALF OF THE SAME IDEA.** The
	 * frame on the glass is this process's own mapping (`AGWindowPreviousFrameSized`), so the region a partial paint
	 * would have to repaint is already in front of the eye: copying it costs a memcpy and, unlike drawing it, needs no
	 * knowledge of what is in it. A fast window's typing, a dragged slider, a selection wash — none of them drawn
	 * twice. When the seam refuses the read (no committed frame, a GPU buffer, a resize in flight) the old answer
	 * stands: the missing region joins the damage and is drawn. */
	{
		int previousStride = 0, previousWidth = 0, previousHeight = 0;

		previous = AGWindowPreviousFrameSized(_agwindow, &previousStride, &previousWidth, &previousHeight);
		if (previous != NULL && previousStride == stride && previousWidth == buffer_w &&
		    previousHeight == buffer_h) {
			canCopy = YES;
			previousStrideForCopy = previousStride;
		} else {
			previous = NULL;
		}
	}
	/* **THE DAMAGE THE PASS WILL PAINT, AS PIECES: the caller's, plus whatever could not be copied.** It starts as the
	 * caller's list and a failed copy appends or merges (the merge rule is `NSView`'s, borrowed through the same helper,
	 * so a full budget collapses to the box rather than dropping anything).
	 *
	 * **AND EVERY PIECE IS ROUNDED OUT TO WHOLE DEVICE PIXELS BEFORE IT IS PAINTED.** A view's damage lands on point
	 * boundaries, and at a fractional scale those are not pixel boundaries: painting a band whose edge falls between two
	 * pixels makes CoreGraphics CLIP it with partial coverage, so the last row is composited at 30-70% over whatever was
	 * there — the old content — instead of being replaced. MEASURED as the faint washed line a person saw through the
	 * demo's buttons and captions: the row was each scroll strip's own edge. Rounding outward paints at most one extra
	 * pixel per edge, and that pixel is drawn with the content that actually belongs there, so over-paint is the only
	 * cost. The copy in `-cg_copyRect:...` rounds INWARD for the opposite reason: it must never write a pixel the
	 * rectangle does not own. */
	{
		NSUInteger j;

		for (j = 0; j < count && j < APPKIT_DAMAGE_RECTS; j++) {
			[self cg_addPaintRect:damage[j] to:paint count:&paintCount];
		}
	}
	slot = [self cg_paintSlotForPixels:frame];
	if (slot < 0) {
		slot = [self cg_claimPaintSlotForPixels:frame];
		paint[0] = [self cg_wholeFrameRect];
		paintCount = 1;
		dirty = [self cg_wholeFrameRect];
		/* **AND A BUFFER NOBODY HAS DESCRIBED HAS A CHROME NOBODY HAS PAINTED EITHER.** The whole-frame branch below
		 * fills and walks the CONTENT over this buffer; the strip above it is this window's own ink, and it is only
		 * drawn when `_cg_chromeDirty` says so. A resize hands out fresh buffers (`ag_window_resize`), so without this
		 * line each step painted the content over undescribed pixels and left the title bar — and the toolbar band's
		 * face — as whatever the new allocation held: MEASURED as a title bar that glitched and blinked while a window
		 * was dragged or resized, because the flag had been consumed by the last ordinary paint. */
		_cg_chromeDirty = YES;
	} else if (!NSIsEmptyRect(_cg_paintMissing[slot])) {
		if (!canCopy || ![self cg_copyRect:_cg_paintMissing[slot] from:previous stride:previousStrideForCopy
					    delta:NSZeroSize]) {
			[self cg_addPaintRect:_cg_paintMissing[slot] to:paint count:&paintCount];
			dirty = NSUnionRect(dirty, _cg_paintMissing[slot]);
		}
	}
	/* **AND THE SCROLL'S TRANSLATION IS THE ONE COPY THAT IS NOT A DAMAGE RECT.** The content moved, so the buffer's
	 * pixels for the whole scrolled region are stale — but they are stale in a way that is already known, and the
	 * frame on the glass has the answer one offset away. Copying it leaves only the strip that came into view to be
	 * drawn, which the scrolled view has already marked dirty. */
	if (_cg_scrollPending) {
		if (canCopy && [self cg_copyRect:_cg_scrollRect from:previous stride:previousStrideForCopy
					   delta:_cg_scrollDelta]) {
			scrolled = YES;
		} else {
			/* no source, or nothing of the region overlapped it: draw the lot */
			[self cg_addPaintRect:_cg_scrollRect to:paint count:&paintCount];
			dirty = NSUnionRect(dirty, _cg_scrollRect);
		}
	}
	c = (CGContextRef)_surface;
	if (_opaque) {
		/* **THE BACKGROUND IS AN AREA, NOT A SHAPE, SO IT MUST NOT BE ANTIALIASED.** A window's background covers
		 * its surface edge to edge, but at a fractional scale `content.width x scale` lands mid-pixel — 400 points at
		 * 1.332 is 532.8 — and an antialiased fill blends the last column with whatever was in the buffer, which is
		 * black. MEASURED: a 194,194,194 column down the right edge of the menu bar window, exactly the 82% of 235
		 * the fill covered. Turning antialiasing off snaps the area's edges to whole device pixels, which is what an
		 * area fill wants and what makes a client surface meet the server's strip with no seam. */
		CGContextSetShouldAntialias(c, 0);
		CGContextSetFillColorWithColor(c, [[self cg_bodyColor] CGColor]);
		/* **ONE FILL AND ONE WALK PER PIECE, WHICH IS WHAT KEEPS AN UNRELATED SECOND DAMAGE FROM COSTING THE GAP.** The
		 * fill is per piece for the same reason the walk is: a background over the bounding box would erase pixels this
		 * pass has no intention of drawing. */
		for (i = 0; i < paintCount; i++) {
			NSRect piece = [self cg_deviceOutward:paint[i]];

			CGContextFillRect(c, CGRectMake(piece.origin.x, piece.origin.y,
							piece.size.width, piece.size.height));
		}
		/* **THE CHROME'S FACE GOES DOWN BEFORE THE CONTENT, BECAUSE THE TOOLBAR IS PART OF THE CONTENT'S WALK.** A
		 * window with a toolbar has a view in the band above its content, and that view draws the items; filling the
		 * strip afterwards erases them. MEASURED as the intermittent toolbar the moment this fill moved below the walk:
		 * the bar repainted on a hover, wiped the items, and the next full repaint brought them back — a toolbar that
		 * blinked with the pointer. The whole-frame path has always drawn in this order (face, content, chrome). */
		if (_cg_chromeDirty) {
			NSRect bar = [self cg_titleBarRect];

			CGContextSetFillColorWithColor(c, [[NSColor cg_chromeFaceColor] CGColor]);
			CGContextFillRect(c, CGRectMake(bar.origin.x, bar.origin.y,
							bar.size.width, bar.size.height));
		}
		CGContextSetShouldAntialias(c, 1);
	} else {
		for (i = 0; i < paintCount; i++) {
			NSRect piece = [self cg_deviceOutward:paint[i]];

			CGContextClearRect(c, CGRectMake(piece.origin.x, piece.origin.y,
							 piece.size.width, piece.size.height));
		}
		if (_cg_chromeDirty) {
			NSRect bar = [self cg_titleBarRect];

			CGContextClearRect(c, CGRectMake(bar.origin.x, bar.origin.y,
							 bar.size.width, bar.size.height));
		}
	}
	if (_contentView != nil) {
		NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithCGContext:_surface flipped:NO];
		NSGraphicsContext *previous = [[NSGraphicsContext currentContext] retain];

		[NSGraphicsContext setCurrentContext:g];
		for (i = 0; i < paintCount; i++) {
			[_contentView displayRect:[self cg_deviceOutward:paint[i]]];
		}
		[self cg_drawDragGuideInContext:c];
		[NSGraphicsContext setCurrentContext:previous];
		[previous release];
	}
	/* **AND THE CHROME PAINTER GOES ON TOP OF WHATEVER THE CONTENT WALK PUT IN THE STRIP.** That walk includes the
	 * TOOLBAR VIEW, which draws its items into the band above the content, so the bar's edges and marks must not be
	 * painted before it — and the FACE under them must be, which is why the fill is with the background above. See
	 * `-cg_chromeRect`'s note for the order: face, content, chrome. */
	if (repaintChrome) {
		NSRect chrome = [self cg_chromeRect];

		[self cg_drawChromeInContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:NO]];
		dirty = NSIsEmptyRect(dirty) ? chrome : NSUnionRect(dirty, chrome);
	}
	/* **AND THERE IS NO COPY ANY MORE, WHICH IS THE WHOLE OF THIS CHANGE.** The cells above drew straight into the
	 * seam's buffer, so the pixels the compositor samples are the pixels CoreGraphics just wrote. The old block
	 * here mirrored y-up rectangles into top-down rows and ORed in an opaque alpha — both jobs that were needed
	 * only because a private backing store sat between the drawing and the wire. With one buffer there is nothing
	 * to mirror: `_surface` has held the buffer's rows all along. The alpha fix-up is not needed either, and for
	 * the reason its own note gave — an opaque window's format is XRGB8888, whose fourth byte the compositor does
	 * not read — while a transparent one is ARGB8888 and CoreGraphics filled its alpha. */
	/* **AND THE COMPOSITOR IS TOLD WHAT CHANGED, IN ITS OWN SPACE.** Until this door existed every frame damaged the
	 * whole buffer, so a terminal repainting one row made the server blend 1280x720; the rectangles below are the
	 * pieces this pass painted and the region a scroll moved, and `+cg_bufferRowsForDirtyRect:` is the same
	 * y-up-to-top-down mirror the scroll copy uses. A pass that painted nothing it can name (which cannot happen — the
	 * whole-frame branch names the frame) leaves the seam's default, which is the full buffer.
	 *
	 * **AND WHAT THIS BUFFER WAS MISSING IS NO LONGER PART OF THAT, WHEN IT WAS COPIED.** `_cg_paintMissing[slot]` is
	 * pixels THIS buffer was behind on; the copy takes them from the frame already on the glass, at the same
	 * coordinates, so the screen is already right there and naming them asked the compositor to draw pixels that had
	 * not changed. That was the right answer while the compositor recomposited the whole window from the committed
	 * buffer — every stale byte in this buffer would have reached the screen — and it is a cost with no payer now that
	 * the compositor keeps the screen: the pixels it is not told about are the pixels it leaves alone. When the copy is
	 * REFUSED the region is painted instead, and then it is in `paint` and reported with everything else, because then
	 * it really did change. The reason is the same one `_cg_paintMissing` exists at all: a partial paint keeps every
	 * pixel outside its rectangle, which is right for the buffer on the glass and must be made right for this one by
	 * COPYING rather than by drawing — copying does not mean the screen changed. */
	{
		CGContextRef surface = (CGContextRef)_surface;
		NSInteger surfaceHeight = (NSInteger)CGBitmapContextGetHeight(surface);
		NSInteger surfaceWidth = (NSInteger)CGBitmapContextGetWidth(surface);
		CGFloat scale = [self userSpaceScaleFactor];
		NSUInteger j;

		for (j = 0; j < paintCount; j++) {
			[self cg_addPaintRect:[self cg_deviceOutward:paint[j]] to:reported count:&reportedCount];
		}
		if (scrolled) {
			[self cg_addPaintRect:[self cg_deviceOutward:_cg_scrollRect] to:reported count:&reportedCount];
		}
		if (repaintChrome) {
			[self cg_addPaintRect:[self cg_deviceOutward:[self cg_chromeRect]] to:reported
					count:&reportedCount];
		}
		for (j = 0; j < reportedCount; j++) {
			NSRange rows = [[self class] cg_bufferRowsForDirtyRect:reported[j] surfaceHeight:surfaceHeight];
			NSInteger left = (NSInteger)floor((double)(reported[j].origin.x * scale));
			NSInteger right = (NSInteger)ceil((double)((reported[j].origin.x + reported[j].size.width) * scale));

			if (rows.length == 0 || right <= left) {
				continue;
			}
			if (left < 0) {
				left = 0;
			}
			if (right > surfaceWidth) {
				right = surfaceWidth;
			}
			AGWindowDamage(_agwindow, (int)left, (int)rows.location, (int)(right - left),
				       (int)rows.length);
		}
	}
	AGWindowEndFrame(_agwindow);
	/* **WHAT A PARTIAL PAINT ACTUALLY COSTS, WHICH IS THE NUMBER "DRAW ONLY WHAT CHANGED" IS JUDGED BY.** The
	 * rectangle, the milliseconds and the frames per second it implies, because a damage rectangle that is right
	 * and a paint that is still slow is a different bug from a damage rectangle that is the whole window — and the
	 * two are indistinguishable from the outside. THE VIEWS' OWN DAMAGE IS PRINTED BESIDE THE PAINTED RECTANGLE for
	 * the same reason: a paint that is wider than the damage is the buffer ledger's doing, and one that is exactly
	 * as wide is a view asking for that much. See APPKIT_LOOP_DIAG for the other half (the pass rate). */
	if (getenv("APPKIT_DRAW_DIAG") != NULL) {
		static int s_paints;
		static NSTimeInterval s_last;

		s_paints++;
		if (s_last == 0.0) {
			s_last = started;
		}
		fprintf(stderr, "  DIAG paint: window %ld damage %ldx%ld at (%ld,%ld) in %lu piece(s)",
			(long)[self windowNumber], (long)dirty.size.width, (long)dirty.size.height,
			(long)dirty.origin.x, (long)dirty.origin.y, (unsigned long)paintCount);
		for (i = 0; i < paintCount; i++) {
			fprintf(stderr, " %ldx%ld", (long)paint[i].size.width, (long)paint[i].size.height);
		}
		fprintf(stderr, ", view damage %ldx%ld, %.1f ms\n",
			(long)changed.size.width, (long)changed.size.height,
			([NSDate timeIntervalSinceReferenceDate] - started) * 1000.0);
		if ([NSDate timeIntervalSinceReferenceDate] - s_last >= 1.0) {
			s_last = [NSDate timeIntervalSinceReferenceDate];
			s_paints = 0;
		}
	}
	/* **AND THE LEDGER RECORDS WHAT THE OTHER BUFFER IS NOW MISSING, WHICH IS WHAT CHANGED — NOT WHAT WAS PAINTED.**
	 * The view damage is what changed; a scrolled region the copy moved is changed too, because the other buffer's
	 * pixels for it are at the OLD offset. The region copied from the missing ledger is deliberately not in here: the
	 * other buffer is exactly the source of that copy, so it already had those pixels. Choosing this rectangle wrongly
	 * is the difference between a knob that tracks the hand and one that crawls (see the note above). */
	{
		NSRect recorded = scrolled ? NSUnionRect(changed, _cg_scrollRect) : changed;

		/* and the strip only if this pass painted it, because otherwise the other buffer's copy of it is still true */
		[self cg_recordPaintInSlot:slot rect:(_cg_chromeDirty ? NSUnionRect(recorded, [self cg_chromeRect])
								      : recorded)];
		if (_cg_chromeDirty) {
			_cg_chromeDirty = NO;
		}
	}
	/* THE TRANSLATION IS IN THE PIXELS NOW, whichever way it got there: copied, or drawn when the copy was refused. */
	_cg_scrollPending = NO;
	_cg_scrollRect = NSZeroRect;
	_cg_scrollDelta = NSZeroSize;
	_viewsNeedDisplay = NO;
	if (_contentView != nil) {
		[_contentView cg_clearDirtyRegionRecursive];
	}
}

- (void)cg_drawFrame
{
	NSRect content;
	CGContextRef c;
	uint32_t *frame;
	int stride = 0;
	int buffer_w = 0, buffer_h = 0;
	NSInteger slot;

	if (_agwindow == NULL) {
		return;
	}
	/* **AND NOBODY DRAWS INTO A CONNECTION THAT CANNOT TAKE IT.** A window drawn faster than the output can absorb
	 * fills libwayland's fixed 4 KB request buffer, and the request after that CLOSES THE CONNECTION — MEASURED:
	 * "Data too big for buffer (4096 + 8 > 4096), error in client communication", in the middle of a menu, after
	 * which the whole desktop was gone. A frame is expensive to make, so the question is asked BEFORE it is
	 * begun; refusing here leaves `_viewsNeedDisplay` set, and the next pass that CAN write draws it. */
	if (!AGWindowServerCanWrite(fn_server())) {
		return;
	}
	/* **AND THE COMPOSITOR IS ASKED FOR THE FRAME BEFORE A SINGLE PIXEL IS DRAWN.** `AGWindowBeginFrame` answers
	 * NULL while the compositor still owns the previous frame — THE ORDINARY CASE FOR A WINDOW BEING DRAWN FASTER
	 * THAN THE OUTPUT CAN TAKE IT, which is exactly when a frame is most expensive to waste. Asking AFTER the drawing
	 * threw the whole frame away: the background fill, the view tree, the chrome and the copy, all for a commit that
	 * was never going to happen — and then the next turn drew and threw away the same again. IT IS NOT A FAILURE
	 * EITHER WAY: the seam calls the frame handler again when the buffer comes back, and there is no Expose to wait
	 * for because the client owns the pixels. LEAVING THE WINDOW STALE is what makes that retry happen. */
	frame = AGWindowBeginFrameSized(_agwindow, &stride, &buffer_w, &buffer_h);
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
	if (![self cg_ensureSurfaceWithPixels:(unsigned char *)frame stride:stride width:buffer_w
					       height:buffer_h]) {
		return;
	}
	/* **AND THE BUFFER THIS FRAME LANDS IN IS NOW CURRENT EVERYWHERE**, which is what the ledger is told at the end:
	 * the whole frame is painted here, so the other buffer's next partial paint is allowed to leave pixels alone. */
	slot = [self cg_paintSlotForPixels:frame];
	if (slot < 0) {
		slot = [self cg_claimPaintSlotForPixels:frame];
	}
	c = (CGContextRef)_surface;
	content = [self contentRectForFrameRect:_frame];
	/* **THE TWO HALVES OF A CLIENT-SIDE-DECORATED FRAME, IN THE ORDER THEY STACK.** The surface is the FRAME (see
	 * `cg_ensureSurface`), so everything here paints into the window's own pixels: the CONTENT is the lower
	 * `content.size.height` rows, where the view tree draws at the origin it has always drawn at, and the CHROME is
	 * the strip above them — which this method paints because nothing else will (appkit-plan §6 D6). There are no
	 * rows without an author, which is what the white stripe this file once carried was. */
	if (_opaque) {
		/* **THE CHROME IS ONE SURFACE, SO IT IS FILLED AS ONE BEFORE ANYBODY DRAWS ON IT.** The toolbar band and the
		 * title bar are painted by two different authors — `NSToolbar` and the chrome painter — each filling only its
		 * own rectangle. At a fractional output scale those rectangles meet between two device rows: each fill covers
		 * part of the row, and because both are antialiased and the row underneath a FRESH buffer is black, the two
		 * partial coverages compose to a DARK LINE — MEASURED at 187 where the face is 222. It was visible only on a
		 * window's first paint, because every later paint blended the same two fills over an existing face and the
		 * row came out at 222. One aliased prefill of the whole strip makes both edges blend with the face instead of
		 * with nothing, and a move (which repaints the whole buffer) is no longer what makes it go away. */
		NSRect chrome = [self cg_chromeRect];

		CGContextSetShouldAntialias(c, 0);
		CGContextSetFillColorWithColor(c, [[NSColor cg_chromeFaceColor] CGColor]);
		CGContextFillRect(c, CGRectMake(chrome.origin.x, chrome.origin.y, chrome.size.width, chrome.size.height));
		/* THE CONTENT'S AREA FILL, WITH THE SAME REASON TO BE ALIASED — see `-cg_drawFrameDirty:`. */
		CGContextSetFillColorWithColor(c, [[self cg_bodyColor] CGColor]);
		CGContextFillRect(c, CGRectMake(0.0, 0.0, content.size.width, content.size.height));
		CGContextSetShouldAntialias(c, 1);
	} else {
		/* **A TRANSPARENT WINDOW'S PIXELS START AT ALPHA ZERO.** Filling them with the background colour would paint
		 * OVER what is behind the window, which is the one thing a transparent window must not do. */
		memset(_pixels, 0, (size_t)_surfaceWidth * (size_t)_surfaceHeight * 4u);
	}
	if (_contentView != nil) {
		[self cg_drawContentInContext:[NSGraphicsContext graphicsContextWithCGContext:_surface flipped:NO]];
	}
	/* THE CHROME, THROUGH THE SAME DOOR A TEST USES — see `-cg_drawChromeInContext:` for why it is a method. */
	[self cg_drawChromeInContext:[NSGraphicsContext graphicsContextWithCGContext:c flipped:NO]];
	/* **AND THE WHOLE-FRAME PATH LOST ITS COPY TOO, FOR THE SAME REASON AS THE DIRTY ONE.** The context's pixels
	 * are the seam's buffer, so `_pixels` and the attached buffer are one allocation; the per-row pass that used
	 * to mirror, copy and OR an opaque alpha here was the price of two buffers, and there is now one. An opaque
	 * window's buffer is XRGB8888 (the fourth byte is not read) and a transparent one's is ARGB8888 (CoreGraphics
	 * wrote the alpha), so neither needs the fix-up the block above used to perform. */
	AGWindowEndFrame(_agwindow);
	/* **A WHOLE-FRAME PAINT ANSWERS EVERY TRANSLATION THERE WAS.** The content is drawn at its current offset into
	 * every pixel, so a scroll the dirty path never got to apply would be applied twice if it were kept. */
	_cg_chromeDirty = NO;
	_cg_scrollPending = NO;
	_cg_scrollRect = NSZeroRect;
	_cg_scrollDelta = NSZeroSize;
	[self cg_recordPaintInSlot:slot rect:[self cg_wholeFrameRect]];
	if (getenv("APPKIT_DRAW_DIAG") != NULL) {
		fprintf(stderr, "  DIAG paint: window %ld WHOLE FRAME %ldx%ld\n", (long)[self windowNumber],
			(long)_surfaceWidth, (long)_surfaceHeight);
	}
	_viewsNeedDisplay = NO;
	if (_contentView != nil) {
		[_contentView cg_clearDirtyRegionRecursive];
	}
}

/* **THE FRAME CALLBACK, WHICH DRAWS ONLY WHEN THERE IS SOMETHING TO DRAW.** The compositor saying "the last frame
 * is taken" is an invitation, and this tier used to treat it as an instruction: every window redrew and committed
 * on every callback, every commit asked for the next callback, and the whole desktop ran as fast as the output
 * could be copied — MEASURED at 517 composites a second, which is the lag a person feels as a click that lands
 * late. A window that is NOT stale has nothing to say, so it says nothing and the loop stops; it starts again the
 * moment anything marks it stale and a draw is due. */
- (void)cg_frameCallback
{
	if (_viewsNeedDisplay) {
		/* **THE INVITATION IS ANSWERED WITH THE PARTIAL PAINT, NOT THE WHOLE FRAME.** This used to call
		 * `-cg_drawFrame`, so the compositor's "your buffer is free" was answered with a full repaint of every
		 * view and a full copy of the surface — and because it arrives DURING the event dispatch, it beat the run
		 * loop's `-displayIfNeeded` to the dirty region and cleared it, so the damage-aware path below never ran.
		 * MEASURED: every click in a file window painted 900x634 whole, whichever view had actually changed.
		 * `-displayIfNeeded` is the same one door the run loop uses: it asks the content view for its dirty union
		 * and paints that, falling back to the whole frame only when nothing was invalidated (a window-level
		 * change like becoming key), which is exactly the case a full paint is for. */
		[self displayIfNeeded];
	}
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
		NSRect damage[APPKIT_DAMAGE_RECTS];
		NSUInteger count = 0;

		if (_contentView != nil) {
			[_contentView cg_dirtyRegionRecursive:damage max:APPKIT_DAMAGE_RECTS count:&count];
		}
		/* **A CHROME-ONLY PASS IS STILL A PARTIAL ONE.** A title change, a key change, a hovered button: 700x22 of ink,
		 * and it used to fall through to `-display` — a whole-frame repaint of every view for a new title. */
		if (count > 0 || _cg_chromeDirty) {
			[self cg_drawFrameDirty:damage count:count];
		} else {
			[self display];
		}
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
	/* **THE CHROME'S ALLOWANCE IS DERIVED FROM THE CHROME, NOT CHOSEN.** It is the block of three symbols and the air
	 * between them at one end, the fourth mark at the other, and the strip's own padding around all of it — the SAME
	 * numbers the painter lays out with, so a window cannot be too narrow for what it paints. It used to be
	 * `3.0 * fn_BUTTON`, which was this sentence with the old circles' diameter in it.
	 *
	 * THE MASK'S CONTRIBUTION HERE IS STILL ONLY WHETHER THERE IS ANY CHROME AT ALL, because this tree has no named
	 * style-mask bits yet — the style mask is a plain integer (see the header) — so a decorated window pays for the
	 * symbols and a borderless one pays for nothing. **AND IT ALWAYS PAYS FOR THE PILL, WHICH A WINDOW MAY NOT HAVE**:
	 * a class method has no instance to ask whether a toolbar is attached, and a minimum width is a promise about
	 * the title rather than an exact sum — so this stays deliberately roomy rather than narrow for the windows that
	 * never show the mark (`fn_chrome_button_present` is where that is decided). Apple's answer also depends on WHICH symbols, through bits this
	 * tree has not named; that is the owed part, stated. It is deliberately conservative in the meantime: a window
	 * whose mask draws no close button still gets the whole block's worth of room, which is room it does not need
	 * rather than a title it cannot read. */
	AGChromeTheme *theme = [AGChromeTheme sharedTheme];
	CGFloat chrome;

	if (aStyle == 0) {
		chrome = 0.0;
	} else if (theme != NULL) {
		/* **THE THEME'S OWN WIDTH, so a window cannot be narrower than four of its buttons plus the edges and the
		 * air between them — the same numbers `fn_chrome_layout` places them with, read here as a total.** The left
		 * block is the other three; the right is the menu button. */
		NSSize button = [theme buttonSize];

		chrome = 2.0 * [theme buttonOffset] + 4.0 * button.width + 3.0 * [theme buttonSpacing];
	} else {
		CGFloat block = 3.0 * fn_SYMBOL + 2.0 * fn_SYMBOL_GAP;

		chrome = 2.0 * fn_CHROME_EDGE + block + fn_SYMBOL;
	}
	CGFloat title = 0.0;

	/* **THE MEASUREMENT IS REAL NOW, AND IT WAS AN ESTIMATE**: this used to multiply the title's LENGTH by seven
	 * points, which is a guess at a rendered width and wrong for every face and every string — "Wi" and "il" are
	 * two characters and very different widths. The attributes are the painter's own (`fn_title_attributes`), so a
	 * window cannot be sized for a title that will be laid out in a different font from the one it was measured
	 * in, and `windowFrameTextColor`'s own ledger rows are untouched by this: they were already shipped. */
	if (aTitle != nil && fn_title_attributes() != nil) {
		title = [aTitle sizeWithAttributes:fn_title_attributes()].width;
	}
	return chrome + fn_CHROME_EDGE + title;
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
	[self setNeedsDisplay:YES];
	AGWindowShow(_agwindow);
	AGWindowLower(_agwindow);
	_visible = YES;
	[[NSApplication sharedApplication] cg_addWindow:self];
}

- (void)orderFrontRegardless
{
	if (![self cg_ensureWindow]) {
		return;
	}
	/* NO RAISE: the stacking is the compositor's (see `-orderBack:`). */
	[self setNeedsDisplay:YES];
	AGWindowShow(_agwindow);
	_visible = YES;
	[[NSApplication sharedApplication] cg_addWindow:self];
	/* **AND NOTHING ELSE HAPPENS.** "Regardless" means the window comes forward WITHOUT the application's key
	 * or main state changing — a caller that wanted those sent `-makeKeyAndOrderFront:`. The drawers still hear
	 * that a window became visible. */
	[self cg_updateDrawers];
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
	/* **AND THE SERVER IS TOLD, BECAUSE THE SEAT IS ITS.** Until this door existed the key flag was local: a click
	 * focused the window through the pointer path, and a programmatic `-makeKeyWindow` — `-makeKeyAndOrderFront:`,
	 * a `-showWindow:` — left the keyboard wherever it was. MEASURED as a reopened Workspace window that was
	 * frontmost in the window list while typing still went to the desktop behind it. Only a window that is ON THE
	 * GLASS may take it: a key window is a window a person can type into. */
	if (_visible && _agwindow != NULL) {
		AGWindowTakeFocus((AGWindow *)_agwindow);
	}
	/* **THE APPLICATION'S `-keyWindow` MOVES WITH THE WINDOW'S OWN FLAG**, whichever door caused the change: a
	 * click, `-makeKeyWindow`, or a previous key window resigning. Keeping the two in one place is what stops
	 * `-isKeyWindow` and `-keyWindow` from disagreeing. */
	[[NSApplication sharedApplication] cg_setKeyWindow:self];
	/* **AND THE CHROME IS STALE THE MOMENT THE KEY STATE CHANGES.** `fn_chrome_state` draws a stoplight's ACTIVE
	 * art from `-isKeyWindow`, so the whole title bar has to repaint when this flag moves — otherwise the buttons
	 * keep the old state until a pointer motion happens to invalidate the hover, which is the bug a person sees as
	 * "the lights only change when the mouse moves over them". */
	[self setNeedsDisplay:YES];
	/* AND THE SAME RE-EVALUATION ON THE WAY IN: the areas that were dead a moment ago are live again, so a control the
	 * pointer is already resting on lights up without waiting for the hand to move. */
	[self cg_updateTrackingForPoint:[self mouseLocationOutsideOfEventStream]];
	fn_announce(self, NSWindowDidBecomeKeyNotification, @selector(windowDidBecomeKey:));
	[self cg_updateDrawers];
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
	[[NSApplication sharedApplication] cg_setMainWindow:self];
	[self setNeedsDisplay:YES];
	fn_announce(self, NSWindowDidBecomeMainNotification, @selector(windowDidBecomeMain:));
}

- (void)resignMainWindow
{
	if (!_main) {
		return;
	}
	_main = NO;
	[[NSApplication sharedApplication] cg_setMainWindow:nil];
	[self setNeedsDisplay:YES];
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

/* **AND WHETHER THE WINDOW IS WAITING TO BE PAINTED.** The flag a pass consumes, unobservable from outside for the
 * same reason the flush count is: a caller cannot see the state that decides whether the next frame is DRAWN, and a
 * test that wants to ask "did this mark the window stale" has nothing else to read. MEASURED, the answer matters:
 * a resize that did not set this flag left the window with no buffer at its new size, and the window DISAPPEARED
 * for the whole drag — the desktop showed through where it had been. */
- (BOOL)cg_needsDisplay
{
	return _viewsNeedDisplay;
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

/* **THE REPRESENTED FILE WITHOUT THE TITLE CHANGE.** Apple's two doors differ: `-setTitleWithRepresentedFilename:`
 * makes the file's name the title, and this one only remembers the path. The proxy icon those titles stand for is
 * not drawn in this tier's chrome, so the store is the whole effect — and it is a separate store from
 * `-representedURL`, as Apple's header says. */
- (void)setRepresentedFilename:(NSString *)aString
{
	NSString *copy = [aString copy];

	[_representedFilename release];
	_representedFilename = copy;
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

/* THE ERA'S `is`-PREFIXED SPELLINGS, aliases of the three questions above. */
- (BOOL)isResizable { return [self resizable]; }
- (BOOL)isMiniaturizable { return [self miniaturizable]; }
- (BOOL)isZoomable { return [self zoomable]; }

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
	NSView *content = [self contentView];

	if (content == nil) {
		fn_refuse_window("-dataWithEPSInsideRect:", "a content view to draw");
		return nil;
	}
	return [content dataWithEPSInsideRect:[content convertRect:rect fromView:nil]];
}

- (nullable NSData *)dataWithPDFInsideRect:(NSRect)rect
{
	NSView *content = [self contentView];

	if (content == nil) {
		fn_refuse_window("-dataWithPDFInsideRect:", "a content view to draw");
		return nil;
	}
	/* THE RECT IS IN THE WINDOW'S BASE COORDINATES, which is what `-convertRect:fromView:nil` converts
	 * from; the content view then draws itself into a page of that size. */
	return [content dataWithPDFInsideRect:[content convertRect:rect fromView:nil]];
}

- (void)print:(id)sender
{
	/* **A WINDOW PRINTS ITS CONTENT VIEW**, which is where its document's drawing lives; `NSDocument` builds its own
	 * operation over the same view, so the two paths cannot disagree about what a page is. */
	(void)sender;
	[[NSPrintOperation printOperationWithView:[self contentView]] runOperation];
}

- (void)dragImage:(NSImage *)anImage at:(NSPoint)baseLocation offset:(NSSize)initialOffset event:(NSEvent *)event
       pasteboard:(NSPasteboard *)pboard source:(id)sourceObj slideBack:(BOOL)slideFlag
{
	/* **THE WINDOW'S VERSION IS THE CONTENT VIEW'S, IN THE CONTENT VIEW'S COORDINATES.** Apple's `baseLocation` is
	 * in the window's base system; the content view is the root, so the conversion is the root's own (which ignores
	 * its frame origin). The session is the view's now, so this door is a forward rather than a refusal. */
	if (_contentView == nil) {
		fn_refuse_window("-dragImage:at:offset:event:pasteboard:source:slideBack:",
				 "a content view; the drag belongs to the view it starts in, and this window has none");
		return;
	}
	[_contentView dragImage:anImage at:[_contentView convertPoint:baseLocation fromView:nil]
			  offset:initialOffset event:event pasteboard:pboard source:sourceObj slideBack:slideFlag];
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
	/* **THE PILL'S ACTION AND THE MENU ITEM'S, THE SAME ACT.** With no toolbar there is nothing to toggle and the
	 * door is quiet; with one, `-setVisible:` owns the frame arithmetic so both roads end in the same place. */
	if (_toolbar != nil) {
		[_toolbar setVisible:![_toolbar isVisible]];
	}
}

- (void)runToolbarCustomizationPalette:(id)sender
{
	/* **THE WINDOW OWNS NO PALETTE: THE TOOLBAR DOES, AND IT REFUSES BY NAME.** A window with no toolbar has nothing
	 * to ask; a window with one gets the toolbar's own answer, which is the one place that knows why. */
	if (_toolbar != nil) {
		[_toolbar runCustomizationPalette:sender];
	}
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

/* **AND IT IS ONE EDITOR PER WINDOW, MADE ON DEMAND AND LENT OUT.** Apple's rule, and the reason a cell asks the
 * window rather than making its own: a form with twenty fields has ONE editor that moves between them, so the memory a
 * text-editing surface needs is paid once rather than twenty times. `createFlag` is what makes the door usable for
 * asking without making — a caller that only wants to know whether a session is running passes NO and gets nil until
 * one is.
 *
 * THE EDITOR IS NOT IN THE VIEW TREE YET, and it must not be: a field editor that sat in a window would be a text view
 * showing at some position nobody chose. `-selectWithFrame:inView:editor:delegate:start:length:` puts it in the view it
 * is editing, at the field's own rect, and takes it out again when the session ends. */
- (id)fieldEditor:(BOOL)createFlag forObject:(id)anObject
{
	if (_fieldEditor == nil && createFlag) {
		NSText *editor = [[NSText alloc] initWithFrame:NSMakeRect(0.0, 0.0, 0.0, 0.0)];

		[editor setFieldEditor:YES];
		[editor setEditable:YES];
		[editor setSelectable:YES];
		_fieldEditor = editor;
	}
	/* **ONE EDITOR, ONE SESSION.** The window owns a single field editor and lends it to whichever field is being
	 * typed into. A second field asking for it while the first still has it used to get the editor back with the first
	 * session STILL LIVE: `-makeFirstResponder:` sees the editor is already the first responder and returns without
	 * resigning it, so the first cell keeps `_cg_editor` — and its next `-setStringValue:`, which is what a combo box's
	 * list pick does, writes into the editor that now stands in the SECOND field. Ending the old session first is the
	 * handoff Apple's door performs and the reason `-fieldEditor:forObject:` names the object at all. */
	if (createFlag && anObject != nil) {
		if (_fieldEditorOwner != nil && _fieldEditorOwner != anObject) {
			[self endEditingFor:_fieldEditorOwner];
		}
		_fieldEditorOwner = anObject;
	}
	return _fieldEditor;
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
	(void)anObject;
	/* **THE GROUND THIS DOOR STOOD ON EXPIRED, AND THIS IS WHAT IT DOES NOW.** It used to be a no-op "because this
	 * tier has no field editor"; a window lends one now, so the honest answer is the ending a click into another view
	 * performs — the editor resigns, the cell takes the string back, and the control decides whether its action fires.
	 * The reason it is NOT a refusal: the machinery is all here, and the door is the window's own `-makeFirstResponder:`
	 * rather than a second teardown. `anObject` is not consulted because the window owns exactly ONE field editor, so
	 * there is one session to end whichever object a caller names. */
	if (_fieldEditor != nil && _firstResponder == (NSResponder *)_fieldEditor) {
		[self makeFirstResponder:nil];
	}
	_fieldEditorOwner = nil;
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
	/* **THE WINDOW FORWARDS TO ITS CONTENT VIEW, WHICH IS APPLE'S OWN CONTRACT.** "Registers the window's content
	 * view" is the documentation's sentence, and it is also the only shape that works with the destination search:
	 * the search hit-tests the content view and climbs, so the registration has to live there. A window with no
	 * content view has nothing to register. */
	[_contentView registerForDraggedTypes:newTypes];
}

- (void)unregisterDraggedTypes
{
	[_contentView unregisterDraggedTypes];
}

- (nullable NSArray *)cg_registeredDraggedTypes
{
	return [_contentView cg_registeredDraggedTypes];
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
	if (_opaque == opaque) {
		return;
	}
	_opaque = opaque;
	/* THE SEAM IS TOLD: an ARGB buffer for a transparent window, an XRGB one for an opaque. */
	AGWindowSetTransparent(_agwindow, _opaque ? 0 : 1);
	/* AND THE BACKING STORE'S FORMAT FOLLOWS OPACITY, so a live surface of the other kind is dropped and the next
	 * draw remakes it — the same path a resize takes. */
	if (_surface != NULL) {
		CGContextRelease(_surface);
		_surface = NULL;
		/* **THE PIXELS ARE THE SEAM'S NOW, SO THEY ARE NOT FREED HERE.** Dropping the context is enough to make the
		 * next draw remake it against whatever buffer the window has then. */
		if (_ownsPixels) {
			free(_pixels);
		}
		_pixels = NULL;
	}
	[self setNeedsDisplay:YES];
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

/* **AND THE PILL APPEARS OR GOES WITH IT, WHICH IS THE WHOLE OF WHAT THE PROPERTY IS FOR.** A flag that only a
 * painter reads and nothing invalidates is a flag that takes effect at the next unrelated repaint — here the title
 * bar is marked stale on the transition, because the mark's presence is part of the strip's layout and not only its
 * ink. */
- (void)setShowsToolbarButton:(BOOL)show
{
	if (_showsToolbarButton == show) {
		return;
	}
	_showsToolbarButton = show;
	[self setNeedsDisplay:YES];
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

- (nullable NSToolbar *)toolbar
{
	return _toolbar;
}

/* **ATTACHING A TOOLBAR PRESERVES THE CONTENT AND GROWS THE FRAME.** The content rect is taken with whatever toolbar
 * the window has now, the new toolbar is attached, and the frame is rebuilt from that same content — so a window
 * whose content is 400x300 keeps a 400x300 document and gains the band. Detaching is the same arithmetic in reverse.
 * The toolbar's back-pointer is not retained; this side of the pair is. */
- (void)setToolbar:(nullable NSToolbar *)aToolbar
{
	NSRect content;
	NSToolbar *old;

	if (_toolbar == aToolbar) {
		return;
	}
	content = [self contentRectForFrameRect:_frame];
	old = _toolbar;
	_toolbar = [aToolbar retain];
	[old cg_setWindow:nil];
	[old release];
	[aToolbar cg_setWindow:self];
	[self setFrame:[self frameRectForContentRect:content] display:YES];
	[self cg_toolbarLayoutChanged];
	/* **AND THE CHROME IS STALE BECAUSE THE PILL IS THE TOOLBAR'S.** Attaching one gives the title bar a fourth mark
	 * and detaching one takes it away, and a strip whose ink was decided before the toolbar arrived would draw the
	 * wrong set until something else repainted it. */
	[self setNeedsDisplay:YES];
}

/* **THE ONE PLACE THE BAND'S GEOMETRY IS WRITTEN.** `NSToolbar` asks for it when it is shown, hidden or resized; this
 * file asks for it when the frame or the content view moves. The content view gets the content rect and the toolbar
 * view sits at that rect's top edge, which is where the chrome's title bar begins. A hidden toolbar's view stays in
 * the tree but is hidden, so it neither draws nor takes a click. */
- (void)cg_toolbarLayoutChanged
{
	NSRect content = [self contentRectForFrameRect:_frame];

	if (_contentView != nil) {
		[_contentView setFrame:content];
	}
	if (_toolbar != nil) {
		NSView *view = [_toolbar cg_view];
		NSRect band = NSMakeRect(0.0, content.size.height, content.size.width,
					 [_toolbar cg_toolbarHeight]);

		if (_contentView != nil && [view superview] != _contentView) {
			[_contentView addSubview:view];
		}
		[view setFrame:band];
		[view setHidden:![_toolbar isVisible]];
		[view setNeedsDisplay:YES];
	}
	[self setNeedsDisplay:YES];
}

/* **THE CONTENT TREE, WHICH IS THE LIVE WINDOW'S WALK AND THE DOOR A TEST CAN DRIVE.** `-displayRect:` draws the
 * receiver AND its subviews, so this is the whole content surface. **THE RECT INCLUDES THE TOOLBAR'S BAND, WHICH IS
 * OUTSIDE THE CONTENT VIEW'S FRAME.** `-displayRect:` converts the RECEIVER's rect into each child's coordinates, so
 * passing only the content rect converts to a zero-height rect at the toolbar's edge and its `-drawRect:` is never
 * called — MEASURED: the toolbar painted correctly in an offscreen draw of its own view and was invisible on a live
 * window, which is exactly the difference this rect closes. */
- (void)cg_drawContentInContext:(nullable NSGraphicsContext *)context
{
	NSGraphicsContext *previous;
	NSRect visible;

	if (_contentView == nil || context == nil) {
		return;
	}
	previous = [[NSGraphicsContext currentContext] retain];
	[NSGraphicsContext setCurrentContext:context];
	visible = [_contentView bounds];
	visible.size.height += fn_toolbar_height(self);
	[_contentView displayRect:visible];
	[self cg_drawDragGuideInContext:(CGContextRef)_surface];
	[NSGraphicsContext setCurrentContext:previous];
	[previous release];
}

/* **THE BAND ALONE, FOR A TEST THAT WANTS THE STRIP WITHOUT THE CONTENT.** A nil context, or a toolbar that is
 * absent or hidden, draws nothing. */
- (void)cg_drawToolbarInContext:(nullable NSGraphicsContext *)context
{
	CGContextRef c;
	NSRect content;
	NSRect band;
	NSView *view;
	NSGraphicsContext *previous;

	if (_toolbar == nil || ![_toolbar isVisible] || context == nil) {
		return;
	}
	c = (CGContextRef)[context graphicsPort];
	if (c == NULL) {
		return;
	}
	content = [self contentRectForFrameRect:_frame];
	band = NSMakeRect(0.0, content.size.height, content.size.width, [_toolbar cg_toolbarHeight]);
	view = [_toolbar cg_view];
	[view setFrame:band];
	previous = [[NSGraphicsContext currentContext] retain];
	[NSGraphicsContext setCurrentContext:context];
	CGContextSaveGState(c);
	CGContextTranslateCTM(c, band.origin.x, band.origin.y);
	[view displayRect:[view bounds]];
	CGContextRestoreGState(c);
	[NSGraphicsContext setCurrentContext:previous];
	[previous release];
}

/* ============================================================================================
 * THE DRAWERS THIS WINDOW OWNS.
 * ============================================================================================ */
/* **THE LIST LIVES ON THE WINDOW AS AN ASSOCIATED OBJECT, WHICH IS THE ONLY WAY A CLASS CAN ADD STATE WITHOUT AN
 * IVAR.** `NSDrawer` is a separate class and this file must not grow a drawer-shaped ivar for it; the association
 * retains the array, and the array retains the drawers, which is Apple's ownership rule ("the parent window retains
 * its drawers") and the reason a drawer's `-parentWindow` is a borrowed pointer. The key is the address of a file-static
 * char, unique for the process's lifetime. */
static char AGWindowDrawerListKey;

static NSMutableArray *fn_window_drawers(NSWindow *window, BOOL create)
{
	NSMutableArray *list;

	if (window == nil) {
		return nil;
	}
	list = objc_getAssociatedObject(window, &AGWindowDrawerListKey);
	if (list == nil && create) {
		list = [[NSMutableArray alloc] init];
		objc_setAssociatedObject(window, &AGWindowDrawerListKey, list, OBJC_ASSOCIATION_RETAIN);
		[list release];		/* the association owns it now */
	}
	return list;
}

- (nullable NSArray *)drawers
{
	NSMutableArray *list = fn_window_drawers(self, NO);

	/* **A COPY, AND AN EMPTY ARRAY RATHER THAN nil** — Apple's own contract for a window with no drawers, and a caller
	 * may enumerate without a test. The copy keeps a caller from reordering this window's drawers by mutating the
	 * answer. */
	return (list != nil) ? [NSArray arrayWithArray:list] : [NSArray array];
}

- (void)cg_addDrawer:(NSDrawer *)drawer
{
	NSMutableArray *list;

	if (drawer == nil) {
		return;
	}
	list = fn_window_drawers(self, YES);
	if (![list containsObject:drawer]) {
		[list addObject:drawer];
	}
}

- (void)cg_removeDrawer:(NSDrawer *)drawer
{
	NSMutableArray *list = fn_window_drawers(self, NO);

	if (list != nil) {
		[list removeObjectIdenticalTo:drawer];
	}
}

/* **THE PARENT'S HALF OF "ONE LAYER UNDER IT".** A drawer is put on the level's tail and the parent then raised over it;
 * this is that raise without the public ordering door, which would call back into every drawer's sync while the sync is
 * what asked. The parent must be on the glass for a raise to mean anything; a window with no seam has no stack. */
- (void)cg_raiseForDrawer
{
	if (_visible && _agwindow != NULL) {
		AGWindowRaise(_agwindow);
	}
}

- (nullable id)defaultButtonCell
{
	return _defaultButtonCell;
}

- (void)setDefaultButtonCell:(id)aCell
{
	[aCell retain];
	[_defaultButtonCell release];
	_defaultButtonCell = aCell;
	[self setNeedsDisplay:YES];
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
	return _preferredBackingLocation;
}

- (void)setPreferredBackingLocation:(NSWindowBackingLocation)location
{
	_preferredBackingLocation = location;
}

- (NSInteger)orderedIndex
{
	return _orderedIndex;
}

- (void)setOrderedIndex:(NSInteger)index
{
	/* **RECORDED, NOT REORDERED.** The application's ordered list is the manager's (D5); a window that stored an
	 * index it could not apply would be lying about a place it does not have, so the store is the answer and
	 * `-orderedIndex` reports what was asked for. */
	_orderedIndex = index;
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
	/* **LEVEL IS THE DRAWER'S PIN, SO A PARENT THAT MOVES IN THE STACK MOVES ITS DRAWERS WITH IT.** One below the
	 * parent is the rule; this is where a caller's `-setLevel:` reaches it. */
	[self cg_updateDrawers];
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
	/* **THE DOCUMENT'S REVIEW COMES FIRST, THEN THE WINDOW'S.** Apple asks the controller's document for a window
	 * whose controller has one; a YES comes back through `AGWindowCloseReview`, sets the approved flag and starts a
	 * second pass that skips the document and asks the window delegate. The flag is cleared on that pass so a later
	 * close asks again. */
	if (!_cg_documentCloseApproved && _cg_windowController != nil
	    && [_cg_windowController respondsToSelector:@selector(document)]) {
		id document = [_cg_windowController document];

		if (document != nil
		    && [document respondsToSelector:@selector(shouldCloseWindowController:delegate:shouldCloseSelector:contextInfo:)]) {
			AGWindowCloseReview *review = [[AGWindowCloseReview alloc] initWithWindow:self];

			[document shouldCloseWindowController:_cg_windowController
						     delegate:review
						  shouldCloseSelector:@selector(document:shouldClose:contextInfo:)
							contextInfo:NULL];
			[review release];
			return;
		}
	}
	_cg_documentCloseApproved = NO;
	/* **THE WINDOW IS ASKED BEFORE IT CLOSES, WHICH IS THE WHOLE OF THIS DOOR.** Apple sends
	 * `-windowShouldClose:` to the DELEGATE and closes only if it answers YES — so a caller that wires an
	 * unsaved-changes prompt to that message gets it from the button AND from the menu item, which is why both
	 * go through here. */
	if (_delegate != nil && [_delegate respondsToSelector:@selector(windowShouldClose:)]) {
		if (![(id <NSWindowDelegate>)_delegate windowShouldClose:self]) {
			return;	/* REFUSED — and nothing was announced and nothing changed, because a refusal is not an event */
		}
	}
	[self close];
}

- (void)cg_setDocumentCloseApproved:(BOOL)flag
{
	_cg_documentCloseApproved = flag;
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
		[self setNeedsDisplay:YES];
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
	NSPoint next = NSMakePoint(topLeft.x + fn_title_bar_height(), topLeft.y - fn_title_bar_height());

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
	NSCursor *edge;

	if (!_cursorRectsEnabled || _contentView == nil) {
		return nil;
	}
	/* **AND THE FRAME'S OWN EDGES ARE ASKED FIRST, BECAUSE THEY ARE THE WINDOW'S AND NOT A VIEW'S.** A view
	 * answers for the ground it covers; an edge is the window's own border, and a control that happens to reach it
	 * does not get to claim it — the same precedence the press takes one door over. */
	edge = fn_resizeCursor(self, p);
	if (edge != nil) {
		return edge;
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

/* **THE DEVICE AND COLOUR FACTS ARE THE SCREEN'S, WITH THE WINDOW'S OWN COLOUR SPACE IN FRONT.** The description's
 * keys live in `NSScreen.h`; the colour space is a caller's choice when one was made and the screen's otherwise; and
 * the deprecated scale factor is 1.0 because this tier has no backing scale. */
- (NSDictionary *)deviceDescription
{
	NSScreen *s = [self screen];

	if (s == nil) {
		s = [NSScreen mainScreen];
	}
	return [s deviceDescription];
}

- (NSColorSpace *)colorSpace
{
	NSScreen *s;

	if (_colorSpace != nil) {
		return _colorSpace;
	}
	s = [self screen];
	if (s != nil && [s colorSpace] != nil) {
		return [s colorSpace];
	}
	return [NSColorSpace genericRGBColorSpace];
}

- (void)setColorSpace:(NSColorSpace *)colorSpace
{
	[colorSpace retain];
	[_colorSpace release];
	_colorSpace = colorSpace;
	[self setNeedsDisplay:YES];
}

- (CGFloat)userSpaceScaleFactor
{
	/* **THE FACTOR BETWEEN A POINT AND A DEVICE PIXEL ON THIS WINDOW'S SURFACE.** It used to answer 1.0 with the note
	 * that "a backing scale is a screen fact it has not got" — the screen has one now, the compositor sends it, and a
	 * caller that asks before drawing gets the number the context was made with. 10.6's name for it; a 10.7 caller
	 * would ask `-backingScaleFactor`, which this tier does not declare. */
	return _deviceScale > 0.0 ? _deviceScale : 1.0;
}

/* **THE SPACES FLAG IS STORED AND ANSWERED.** This tier has one space, so a window is always on the active one and
 * the flag cannot change what a caller observes; the doors exist so a setting round-trips instead of crashing. */
- (BOOL)canBeVisibleOnAllSpaces
{
	return _canBeVisibleOnAllSpaces;
}

- (void)setCanBeVisibleOnAllSpaces:(BOOL)flag
{
	_canBeVisibleOnAllSpaces = flag;
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
	if (_documentEdited == (flag ? YES : NO)) {
		return;
	}
	_documentEdited = flag ? YES : NO;
	/* the edited dot is chrome ink, and it was the same silent change a title was */
	[self cg_invalidateChrome];
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

/* **THE ATTACHMENT IS ALSO A STATEMENT TO THE WINDOW SERVER, AND IT IS MADE WHERE THE STATE IS.** Two things follow
 * from being attached, and neither can be derived on the server's side: the sheet's TOP CORNERS are its parent's title
 * bar's seam rather than its own edge (so they are square, like a menu's top corners against the menu bar), and the
 * sheet is drawn and hit-tested immediately in front of its parent whoever was raised. The frames cannot say it: two
 * rounded rectangles whose edges touch look exactly like two that belong to each other.
 *
 * **AND THE FRAME CHANGES HERE, FOR THE SAME REASON `-setStyleMask:` CHANGES IT THERE: THE CONTENT KEEPS ITS SIZE.**
 * A sheet has no chrome (`fn_chrome_height`), so the strip the caller's window was built with has to come off its
 * frame instead of turning into twenty-two points of content nobody asked for — and putting it BACK when the session
 * ends is the same subtraction in reverse, so an alert dismissed as a sheet leaves a titled window with the content
 * it was built with rather than one with a twenty-two-point bite out of it. The content's size and place are measured
 * UNDER THE OLD MODE and the frame is re-derived under the NEW one, which is the whole of the arithmetic.
 *
 * A WINDOW THAT HAS NO SERVER-SIDE SURFACE YET says nothing — the seam's window is made lazily, by `-orderFront:`, and
 * `-cg_ensureWindow` makes this same statement when it does. So the order a caller happens to attach and order in is
 * not something this pair has to be careful about. */
- (void)cg_setSheetParent:(NSWindow *)parent
{
	BOOL changes = ((_cg_sheetParent != nil) != (parent != nil));
	NSRect content = [self contentRectForFrameRect:_frame];	/* under the mode this window is in NOW */

	_cg_sheetParent = parent;
	if (changes) {
		NSRect frame = [self frameRectForContentRect:content];

		/* **AND THE FRAME IS PUT ON THE POINT GRID, WHICH IS THE GRID THE SERVER PLACES ON.** A sheet's frame IS its
		 * content, and a caller's content need not be a whole number of points — an alert's layout computes 109.6 — but
		 * the protocol's frame is integral, so a fractional one is rasterised by the client at a fraction while the
		 * server places the buffer at a whole point. MEASURED, as the sheet's half of the title bar's border sitting a
		 * fraction of a row away from the parent's half: two antialiased rows inside the sheet where the bar has one
		 * crisp row outside it. Rounding the frame is what makes the two halves ONE line, which is the whole point of
		 * the tuck and of the border the sheet wears. */
		frame.size.width = fn_device_point(frame.size.width);
		frame.size.height = fn_device_point(frame.size.height);
		[self setFrame:frame display:YES];
	}
	if (_agwindow != NULL) {
		AGWindowSetSheetParent(_agwindow, parent != NULL ? parent->_agwindow : NULL,
				       parent != NULL ? (int)[parent cg_sheetTuck] : 0);
	}
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
