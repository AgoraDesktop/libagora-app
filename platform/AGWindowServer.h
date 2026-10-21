/*
 * AGWindowServer.h — the seam between AppKit's windows and whatever is displaying them.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * WHAT THIS IS FOR. `NSWindow` has to put pixels on a screen and get events back, and it must not know
 * HOW. The Fiwix import it came from knows: it opens an X11 display and calls XCreateSimpleWindow,
 * XMapWindow, XPutImage and XNextEvent in `NSWindow.m` and `NSScreen.m`. Agora's target is Wayland with no
 * X11-native target, so those calls go — and they are replaced by THIS, an interface, with the Wayland
 * client as its first implementation rather than as a hard dependency.
 *
 * WHY AN INTERFACE AND NOT `#include <wayland-client.h>` IN NSWindow. Two reasons, both already true:
 *
 *   1. Agora's own window server (`window-server`, the Wayland compositor) does not exist yet. While it is
 *      being written the seam's implementation is a client of a stock compositor, and afterwards it has to
 *      speak to Agora's own. `xdg-shell` is the BOOTSTRAP protocol, not the destination: a Mac-like window
 *      server with client-side chrome, a system menu bar, a dock, sheets and the drag session needs more
 *      than `xdg-shell` carries, so the protocol must be able to change without NSWindow noticing.
 *   2. The same seam is what a nested or headless test drives. `tests/window.c` is an NSWindow-shaped
 *      program that uses nothing but these declarations.
 *
 * THE SHAPE OF A FRAME, WHICH IS THE ONE THING THAT IS NOT OBVIOUS. A Wayland surface does not own its
 * pixels: a buffer is handed to the compositor, the compositor says when it is done with it, and only then
 * may it be written again. So drawing is bracketed:
 *
 *     uint32_t *pixels = AGBeginFrame(window, &stride);   // NULL if the compositor still holds the buffer
 *     ... write pixels[stride/4 * y + x] = 0x00RRGGBB ...
 *     AGEndFrame(window);                                 // attach, damage, commit, ask for the next frame
 *
 * and `AGWindowSetFrameHandler` says when the next frame may begin — which is what makes an animation
 * loop rather than a single paint.
 *
 * COLOUR. Pixels are 0x00RRGGBB for an OPAQUE window and 0xAARRGGBB (PREMULTIPLIED) for a TRANSPARENT one — see
 * `AGWindowSetTransparent`. An opaque window's alpha byte is ignored; a transparent window's IS the window's
 * transparency, and the compositor blends on it.
 *
 * EVENTS. Nothing here is an `NSEvent`. This layer reports what the compositor said — an evdev key code, a
 * pointer position, a UTF-8 string already translated through the compositor's own keymap — and NSEvent
 * will be built from it one layer up. That split is deliberate: the keymap translation is xkbcommon's and
 * is tested on its own (`AGKeyboard.h`), and the Cocoa-shaped event is AppKit's business.
 */

#ifndef AG_WINDOW_SERVER_H
#define AG_WINDOW_SERVER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------------------------------------------------------------------------------------------
 * events
 * --------------------------------------------------------------------------------------------------- */

typedef enum {
	/* No event. */
	AGEventNone = 0,
	/* The window's size changed. x and y are the new client size. */
	AGEventConfigure,
	/* The compositor asked the window to close (the titlebar's X, or a session shutdown). */
	AGEventClose,
	/* **THE SHELL ASKED THIS APPLICATION TO SHOW A WINDOW.** A Dock tile was clicked and the application had no
	 * window a person could work in, so the question "what does that click mean" is the application's. It arrives
	 * at the window the ask named, and the answer need not be that window. */
	AGEventReopen,
	/* A key changed state. `keycode` is the evdev code, `text` the UTF-8 it produces (empty when none). */
	AGEventKey,
	/* The pointer moved inside the window. */
	AGEventPointerMotion,
	/* A pointer button changed state. `button` is the evdev code. */
	AGEventPointerButton,
	/* The pointer entered or left the window. `pressed` is 1 for entered. */
	AGEventPointerEnter,
} AGEventType;

enum {
	AGModifierShift    = 1u << 0,
	AGModifierControl  = 1u << 1,
	AGModifierAlt      = 1u << 2,
	AGModifierSuper    = 1u << 3,	/* Command on a Mac keyboard */
	AGModifierCapsLock = 1u << 4,
	AGModifierNumLock  = 1u << 5,
};

typedef struct AGEvent {
	AGEventType type;
	uint32_t time_ms;
	int x;				/* pointer or new size, window coordinates */
	int y;
	/* **AND WHERE THE POINTER IS IN THE OUTPUT, WHEN THE COMPOSITOR SAID.** `x`/`y` above are relative to THIS
	 * window, and a title-bar drag MOVES the window — which turns the relative pair into a moving target that a
	 * fast hand outruns. These are the absolute position the relative one was computed from. `has_global` is zero
	 * for a compositor that does not send them (a stock `xdg-shell` one), where a drag falls back to the relative
	 * arithmetic. */
	int global_x;
	int global_y;
	int has_global;
	uint32_t button;		/* evdev button code */
	int pressed;
	uint32_t keycode;		/* evdev key code */
	int modifier;			/* nonzero when `keycode` is a MODIFIER key rather than one that types */
	uint32_t modifiers;		/* AGModifier... */
	char text[8];			/* UTF-8; empty when the key produces no text */
} AGEvent;

typedef void (*AGEventFunction)(void *context, const AGEvent *event);
typedef void (*AGFrameFunction)(void *context, uint32_t time_ms);

/* **WHETHER THIS APPLICATION HAS THE KEYBOARD — WHICH IS WHAT "ACTIVE" MEANS, AND WHY ONLY THE ACTIVE APP'S MENUS
 * SHOW.** The compositor already says which CLIENT has the keyboard: it sends `wl_keyboard.enter` to the client
 * whose surface is focused and `wl_keyboard.leave` when that client gives the keyboard up — so a client can answer
 * this without asking anyone, and a window manager never has to be told who is in front. The handler below is
 * called when the answer CHANGES, which is the moment an application shows or hides its menu bar. */
typedef void (*AGActivationFunction)(void *context, int active);

/* ---------------------------------------------------------------------------------------------------
 * the connection
 * --------------------------------------------------------------------------------------------------- */

typedef struct AGWindowServer AGWindowServer;

/* Connect to the display named by $WAYLAND_DISPLAY, or the default one. NULL if there is none. **THIS MAKES A NEW,
 * INDEPENDENT CONNECTION** and the caller owns it — which is what a test or a probe wants. An application wants
 * the one below. */
AGWindowServer *AGWindowServerConnect(void);

/* **THE PROCESS'S ONE CONNECTION, MADE ON FIRST USE.** AppKit has a single window server, and every part of it —
 * a window that places itself, a screen that is asked for `-visibleFrame`, the menu bar, the window list — has to
 * be looking at the SAME event queue. Two connections is two caches: an event that arrives on one is invisible to
 * the other, so a work area announced to the windows would never reach the screen that reports it.
 *
 * MEASURED, which is why this exists: `NSScreen` used to call `AGWindowServerConnect` on every ask, so a view
 * reading `-visibleFrame` once a frame opened 902 connections in five seconds — and each of them got the work area
 * at bind and never again. This is the one accessor `NSWindow` and `NSScreen` both use; it is never disconnected,
 * because the application lives as long as it does. */
AGWindowServer *AGWindowServerShared(void);
void AGWindowServerDisconnect(AGWindowServer *server);

/* Read and dispatch everything already queued; returns the number dispatched, or -1 if the connection is
 * gone. This is what an event loop's "is there anything to do" step calls. */
int AGWindowServerDispatchPending(AGWindowServer *server);

/* Block until something happens, then dispatch it. Returns -1 if the connection is gone. */
int AGWindowServerDispatch(AGWindowServer *server);

/* Block until something happens or `timeout_ms` passes, dispatching whatever arrives. `timeout_ms` < 0 waits
 * with no timeout and 0 is a poll — which is the pair an event loop is built from: poll each window, then
 * wait once, so a window that appears mid-wait is drained rather than missed. Returns -1 if the connection is
 * gone, 1 otherwise. */
int AGWindowServerDispatchTimeout(AGWindowServer *server, int timeout_ms);

/* Send anything buffered. */
void AGWindowServerFlush(AGWindowServer *server);

/* **WHETHER ANOTHER REQUEST WOULD FIT, WHICH IS HOW A CLIENT AVOIDS KILLING ITSELF.** A `wl_display_flush` that
 * cannot push everything answers `EAGAIN` and KEEPS the remainder in a fixed 4 KB buffer; a client that goes on
 * making requests then overflows it and libwayland closes the connection — "Data too big for buffer (4096 + 8 >
 * 4096), error in client communication", MEASURED, and it took a whole session down with it. 1 when there is
 * room, so a caller that has something expensive to say can wait for the output instead of dying. */
int AGWindowServerCanWrite(AGWindowServer *server);

/* A human-readable description of why the connection failed, for the caller's log. */
const char *AGWindowServerLastError(AGWindowServer *server);

/* **THE PART OF THE OUTPUT AN APPLICATION MAY USE**: the frame minus the menu bar and the Dock, which is
 * `NSScreen`'s `-visibleFrame` and a question only the window server can answer, because the furniture is its.
 * Zeroes when the compositor does not say; the caller decides what to do about that. */
void AGWindowServerWorkArea(AGWindowServer *server, int *x, int *y, int *width, int *height);

/* **WHERE AN APPLICATION'S OWN MENUS MAY BEGIN, WHICH IS A DIFFERENT QUESTION FROM THE WORK AREA.** The server owns
 * the menu bar's strip and the System menu at its left; this is the strip to the RIGHT of that square, where an
 * application's own menus go. THE APPLICATION DRAWS THEM — it always did — and this says where they may start and
 * nothing else.
 *
 * IT CANNOT BE DERIVED, WHICH IS WHY IT IS A DOOR: the System menu's width is the server's number, and an
 * application that guessed would put its first menu UNDER the System menu the first time that width changed. And
 * the work area cannot carry it: that is a VERTICAL reserve for windows, and the Mac's `-visibleFrame` begins at
 * x = 0 because the bar spans the whole screen. Zeroes when the compositor does not say. */
void AGWindowServerMenuBarArea(AGWindowServer *server, int *x, int *y, int *width, int *height);

/* **AND THE STRIP'S COLOUR, BECAUSE AN APPLICATION'S MENUS SIT IN IT.** A menu drawn on a panel of its own colour is
 * a visible SEAM across a surface that is meant to be one thing — MEASURED: the server's strip at 216,216,216 and
 * `NSMenuView`'s own panel at 240,240,240. The colour is the server's, so the server is what says it; a client that
 * picked a colour which looked close is how two greys come to differ by four counts and nobody can say which one is
 * right. 0xRRGGBB, and 0 when the compositor did not say. */
void AGWindowServerMenuBarColour(AGWindowServer *server, unsigned int *rgb);

/* The compositor's first output, as far as a client can know it. `*width` and `*height` receive the output's
 * current mode, and `*name` the model the compositor reported — the closest thing to a screen name a Wayland
 * client is given. Any of the three may be NULL. Width and height are left at 0 when no output has been
 * described yet, which is a state and not an error. */
void AGWindowServerScreenSize(AGWindowServer *server, int *width, int *height, const char **name);

/* ---------------------------------------------------------------------------------------------------
 * windows
 * --------------------------------------------------------------------------------------------------- */

typedef struct AGWindow AGWindow;

/* Ask for a window of this size. The compositor may choose another, in which case AGEventConfigure says
 * so — a window is not its requested size until it is configured. */
AGWindow *AGWindowCreate(AGWindowServer *server, int width, int height, const char *title);
void AGWindowDestroy(AGWindow *window);

void AGWindowShow(AGWindow *window);

/* **TAKE THE WINDOW OFF THE SCREEN, AND PUT IT BACK.** `NSWindow`'s `-orderOut:`, and the door `xdg-shell` does not
 * have: a toplevel there is mapped or destroyed, so hiding a window means destroying it and building another to
 * show it again — which is not what a menu does when it closes. On a compositor that speaks Agora's own protocol
 * this is a request; on one that speaks only `xdg-shell` it is recorded here and the window stays where it is,
 * which is a property of the compositor and not of this call. */
void AGWindowHide(AGWindow *window);
void AGWindowSetTitle(AGWindow *window, const char *title);

/* **WHICH APPLICATION THIS WINDOW BELONGS TO, IN THE MAC'S VOCABULARY: THE BUNDLE IDENTIFIER.** The server records it
 * for its own use — a shell component groups windows by it — and AppKit supplies `[[NSBundle mainBundle]
 * bundleIdentifier]` without asking. It used to be a constant in this file, which is why every Agora application
 * was the same application to anything that asked. */
void AGWindowSetAppID(AGWindow *window, const char *app_id);

/* **THE APPLICATION'S FRAME, AND ON A COMPOSITOR THAT CAN BE TOLD, IT IS HONOURED.** Where the window goes and
 * how big it is, in the output's coordinates (y downwards, as the display has them). This is the Mac's
 * `-setFrame:display:`: the application states a frame and the server writes it down — the only thing that
 * adjusts one is the APPLICATION's `-constrainFrameRect:toScreen:`, against the work area below.
 *
 * It is a door on the SEAM rather than on the protocol because a compositor need not be able to express it: a
 * stock one speaking only `xdg-shell` has no way to be told where a window goes, and this then records the frame
 * and places nothing. That is a property of the compositor and not of this call. */
void AGWindowSetFrame(AGWindow *window, int x, int y, int width, int height);

/* WHERE THE WINDOW SITS IN THE STACK — `NSWindow`'s `-level`, AN INTEGER rather than a member of a fixed set, so
 * that a menu window and a status item and the Dock can be ordered against each other without this layer having
 * anticipated any of them. */
void AGWindowSetLevel(AGWindow *window, int level);

/* **AND HOW MUCH OF THE SCREEN IT TAKES FOR ITSELF — the one thing a Dock has to be able to say.** Apple's window
 * server learns this from the Dock's own window frame through a private CGS call Agora has no answer for, so here
 * the owner SAYS: `amount` pixels along `edge` leave the work area, and every application's `NSScreen.visibleFrame`
 * shrinks by them from that moment on. The seam reads the result through `AGWindowServerWorkArea`, which is what
 * `-constrainFrameRect:toScreen:` is checked against.
 *
 * Nothing here moves the window — `AGWindowSetFrame` is unaffected, and the two are separate answers to separate
 * questions. A window has ONE reservation, so asking again MOVES it (a Dock dragged from the bottom to the side);
 * `amount` 0 releases it, which is what an autohiding Dock says before it hides. The reservation dies with the
 * window, so a client that crashes does not leave a strip missing for ever. A compositor that speaks only
 * `xdg-shell` has no door for this and records nothing. */
enum {
	AGWindowEdgeTop = 0,
	AGWindowEdgeBottom = 1,
	AGWindowEdgeLeft = 2,
	AGWindowEdgeRight = 3
};
void AGWindowSetReserved(AGWindow *window, int edge, int amount);

/* **AND WHETHER A CLICK ON THE WINDOW MAY GIVE ITS APPLICATION THE KEYBOARD.** True for every ordinary window and
 * what a Dock switches off: clicking one of its tiles activates the application the tile names, and a Dock that took
 * the keyboard would take the menu bar with it. The window still receives every pointer event; it just never becomes
 * the application in front. A compositor that does not speak Agora's protocol has no door for it. */
void AGWindowSetActivatable(AGWindow *window, int activatable);

/* **WHETHER THIS WINDOW'S PIXELS CARRY ALPHA.** A transparent window's shm buffer is ARGB8888 and the compositor
 * blends it over what is behind (source-over, in `window-server/src/output.c`); an opaque window's is XRGB8888 and
 * is copied. Set it BEFORE the first frame, because the buffer's FORMAT is decided when the buffer is made; a
 * window that changes afterwards keeps its old buffer until the next one is made. */
void AGWindowSetTransparent(AGWindow *window, int transparent);

/* **TAKE THE POINTER WHEN IT IS OVER NO SURFACE AT ALL.** A Wayland compositor sends pointer events to the surface
 * under the pointer and to nobody when the pointer is over the desktop, so a popup could not hear the click that
 * lands outside it — and "click anywhere to dismiss" was not expressible. While this is set, events that would go
 * to NO surface are delivered to THIS one, with coordinates relative to it, which may fall outside its frame. A
 * surface under the pointer is untouched, ON PURPOSE: a menu bar is a separate window from the menu it opened and
 * the pointer has to be able to cross back to it. A compositor that does not speak `agora_shell` has no door for
 * this and simply delivers nothing, which is the behaviour every popup had before it. */
void AGWindowSetPointerGrab(AGWindow *window, int grab);

/* **AND TAKE IT WHEREVER IT IS, FOR THE DURATION OF A DRAG.** The grab above is a fallback and stops at the first
 * surface under the pointer, which is what a menu bar needs; a window being MOVED or RESIZED needs the opposite,
 * because it goes out from under the hand — the edge follows the pointer and the compositor's copy of the surface
 * is a frame behind, so the pointer ends up over the desktop or over a neighbour. While this is set, motion and
 * buttons are delivered to THIS window whatever is under them, which is the only way a drag hears its own hand.
 * The server gives it back when the last button comes up; zero gives it back early. */
void AGWindowSetPointerCapture(AGWindow *window, int capture);

/* **MAKE THIS WINDOW AN ITEM THE SERVER PLACES, OF THIS WIDTH.** The one place the frame rule does not reach:
 * `NSStatusItem` has a length and no position, because an application does not know what else is in the status bar
 * and so cannot know where its own item goes. After this, `AGWindowSetFrame` no longer moves the window — a status
 * item is in the menu bar by definition. A length of zero or less puts it back among the ordinary windows.
 *
 * `length` is a width in output coordinates and never a sentinel: resolving `NSVariableStatusItemLength` and
 * `NSSquareStatusItemLength` is AppKit's, since only it knows how wide its view wants to be. */
void AGWindowSetStatusItem(AGWindow *window, int length);

/* BRING THE WINDOW TO THE FRONT OF ITS LEVEL — the Mac's `-orderFront:`. It is not a level change and not a
 * claim on the keyboard: who has FOCUS is the user's click together with `-makeKeyAndOrderFront:`. */
void AGWindowRaise(AGWindow *window);
/* SEND IT TO THE BACK OF ITS LEVEL — the Mac's `-orderBack:`. The same level, the other end of it. */
void AGWindowLower(AGWindow *window);

int AGWindowWidth(const AGWindow *window);
int AGWindowHeight(const AGWindow *window);
/* Nonzero once the compositor has configured the window: only then is the size real. */
int AGWindowIsConfigured(const AGWindow *window);

void AGWindowSetEventHandler(AGWindow *window, AGEventFunction function, void *context);
void AGWindowSetFrameHandler(AGWindow *window, AGFrameFunction function, void *context);

/* ============================================================================================ *
 * WHAT A SHELL COMPONENT IS TOLD: THE WINDOW LIST.                                                      *
 *                                                                                                *
 * **THE DOCK'S DATA SOURCE, AND AN APPLICATION'S ONE EXCEPTION TO "MY OWN WINDOWS ONLY".** An  *
 * ordinary client knows its own windows and has no business knowing anyone else's. A shell       *
 * component's job is the opposite — it shows what is running — and it cannot learn that from its *
 * own process. So it asks, and the server re-sends the whole snapshot whenever the set changes: *
 * a title, a map or unmap, a level, a visibility, or the keyboard moving.                        *
 *                                                                                                *
 * It is a SNAPSHOT and not a delta, because a desktop has thirty windows and a person is what     *
 * changes them: a client that missed one is corrected by the next. The callback is handed the     *
 * finished list, never a half-built one, and it must not keep the pointer.                        *
 * ============================================================================================ */

/* MORE WINDOWS THAN THIS AND THE LIST IS TRUNCATED, which is stated rather than discovered: a desktop with sixty-
 * four windows has stopped being a desktop a Dock can usefully show, and the alternative is an allocation in an
 * event callback. */
#define AG_WINDOW_LIST_MAX 64

typedef struct AGWindowInfo {
	unsigned int id;		/* the handle AGWindowActivate and AGWindowRequestClose take */
	char app_id[128];		/* the bundle identifier the application declared */
	char title[256];
	int level;			/* the integer level; a shell ignores menus and the bar by it */
	int visible;
	int active;			/* this window has the keyboard — the only "frontmost" there is */
} AGWindowInfo;

typedef void (*AGWindowListFunction)(void *context, const AGWindowInfo *windows, int count);

/* Ask to be told. Idempotent: the LAST handler wins, and a NULL handler stops the snapshots. A compositor that does
 * not speak `agora_shell` version 3 never calls it, which is the same silence every other Agora-only door has. */
void AGWindowListSetHandler(AGWindowServer *server, AGWindowListFunction function, void *context);

/* **AND THE TWO THINGS A SHELL DOES TO SOMEBODY ELSE'S WINDOW.** `AGWindowActivate` is a click on a Dock tile: the
 * window is raised in its level AND takes the keyboard, which is what makes the application's own menu bar follow.
 * `AGWindowRequestClose` is Quit: the application is ASKED through its own close path and decides — a client that
 * refuses stays open, exactly as it does when its close button is pressed. An id nothing answers is ignored. */
void AGWindowActivate(AGWindowServer *server, unsigned int id);
void AGWindowRequestClose(AGWindowServer *server, unsigned int id);
/* **AND THE ONE THAT ASKS AN APPLICATION TO SHOW SOMETHING.** `AGWindowActivate` moves a window; this asks the
 * application behind one to reopen, which is what a tile click means when there is nothing to raise. The id is an
 * ADDRESS rather than a subject — the application decides what opens — and a compositor that does not speak
 * `agora_shell` version 5 never answers, which is the silence every older door has. */
void AGWindowReopen(AGWindowServer *server, unsigned int id);

/* WHETHER THIS APPLICATION HAS THE KEYBOARD, and a door to be told when that changes. Zero when the connection is
 * NULL, which is the honest answer for "no server, no focus". */
int AGWindowServerIsActive(AGWindowServer *server);
void AGWindowServerSetActivationHandler(AGWindowServer *server, AGActivationFunction function, void *context);

/* The pixel buffer to draw into, or NULL when the compositor still holds the one a frame would go in — in which
 * case the caller must NOT draw and should wait for the frame handler. `*stride` receives the row pitch in BYTES.
 * Pixels are 0x00RRGGBB.
 *
 * **AND THE BUFFER HANDED BACK IS NOT THE ONE ON THE SCREEN, WHICH IS THE ONLY REASON THIS IS SAFE TO DRAW ON.**
 * A window keeps two of them: one the compositor is showing and one this process owns, swapped at `AGWindowEndFrame`
 * and given back by the compositor when the commit that replaces it arrives. So the pixels a caller gets are one
 * frame behind what a person is looking at, and a caller that paints only part of the surface must repaint whatever
 * changed since that buffer was last painted — see `_cg_paintMissing` in `NSWindow.h` for the ledger AppKit keeps,
 * and the note at the top of `AGWindowServer-Wayland.c` for why one buffer is a blink a person can see. A pointer
 * that stays the same from one frame to the next is not promised, and a caller that caches it across frames is
 * caching something the seam may have replaced. */
uint32_t *AGWindowBeginFrame(AGWindow *window, int *stride);

/* **THE SAME DOOR, WITH THE BUFFER'S OWN SIZE AS WELL AS ITS PITCH.** The drawing surface IS the frame now — the
 * seam hands back the memory the compositor will sample — so a caller that sizes its own bitmap has to ask the
 * buffer rather than the window: a resize the compositor is still holding leaves the two momentarily different, and
 * the window's number would be the wrong one. */
uint32_t *AGWindowBeginFrameSized(AGWindow *window, int *stride, int *width, int *height);

/* Hand the frame to the compositor and ask for the next one. Does nothing when no frame is begun. */
void AGWindowEndFrame(AGWindow *window);

#ifdef __cplusplus
}
#endif

#endif /* AG_WINDOW_SERVER_H */
