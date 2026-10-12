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
 * COLOUR. Pixels are 0x00RRGGBB. The alpha byte is ignored by the format this first implementation uses,
 * which is what AppKit's own drawing hands over (`libagora-drawing` produces an opaque 32-bit buffer).
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
	uint32_t button;		/* evdev button code */
	int pressed;
	uint32_t keycode;		/* evdev key code */
	int modifier;			/* nonzero when `keycode` is a MODIFIER key rather than one that types */
	uint32_t modifiers;		/* AGModifier... */
	char text[8];			/* UTF-8; empty when the key produces no text */
} AGEvent;

typedef void (*AGEventFunction)(void *context, const AGEvent *event);
typedef void (*AGFrameFunction)(void *context, uint32_t time_ms);

/* ---------------------------------------------------------------------------------------------------
 * the connection
 * --------------------------------------------------------------------------------------------------- */

typedef struct AGWindowServer AGWindowServer;

/* Connect to the display named by $WAYLAND_DISPLAY, or the default one. NULL if there is none. */
AGWindowServer *AGWindowServerConnect(void);
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

/* A human-readable description of why the connection failed, for the caller's log. */
const char *AGWindowServerLastError(AGWindowServer *server);

/* **THE PART OF THE OUTPUT AN APPLICATION MAY USE**: the frame minus the menu bar and the Dock, which is
 * `NSScreen`'s `-visibleFrame` and a question only the window server can answer, because the furniture is its.
 * Zeroes when the compositor does not say; the caller decides what to do about that. */
void AGWindowServerWorkArea(AGWindowServer *server, int *x, int *y, int *width, int *height);

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
void AGWindowSetTitle(AGWindow *window, const char *title);

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

int AGWindowWidth(const AGWindow *window);
int AGWindowHeight(const AGWindow *window);
/* Nonzero once the compositor has configured the window: only then is the size real. */
int AGWindowIsConfigured(const AGWindow *window);

void AGWindowSetEventHandler(AGWindow *window, AGEventFunction function, void *context);
void AGWindowSetFrameHandler(AGWindow *window, AGFrameFunction function, void *context);

/* The pixel buffer to draw into, or NULL when the compositor still holds the previous one — in which case
 * the caller must NOT draw and should wait for the frame handler. `*stride` receives the row pitch in
 * BYTES. Pixels are 0x00RRGGBB. */
uint32_t *AGWindowBeginFrame(AGWindow *window, int *stride);

/* Hand the frame to the compositor and ask for the next one. Does nothing when no frame is begun. */
void AGWindowEndFrame(AGWindow *window);

#ifdef __cplusplus
}
#endif

#endif /* AG_WINDOW_SERVER_H */
