/*
 * AGWindowServer-Wayland.c — the seam's first implementation: an `xdg-shell` client.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed.
 * SPDX-License-Identifier: MIT
 *
 * THE PIPELINE, ONCE, FOR ONE WINDOW OR MANY:
 *
 *   wl_display --- wl_registry ---+-- wl_compositor ----> wl_surface
 *                                 |                        |
 *                                 |                        +--> xdg_surface --> xdg_toplevel
 *                                 +-- xdg_wm_base ---------+       (configure / ack: the frame size)
 *                                 +-- wl_shm -------------> wl_shm_pool --> wl_buffer   (the pixels)
 *                                 +-- wl_seat ------------> wl_keyboard / wl_pointer    (AGEvent)
 *
 * and one present loop per window: draw into the shared buffer, attach, damage, commit, wait for the frame
 * callback.
 *
 * THE THREE RULES THIS FILE EXISTS TO KEEP, each a protocol error or an artefact when broken:
 *
 *   1. xdg_surface.configure MUST BE ACKNOWLEDGED with its serial before anything is committed on that
 *      surface. Committing first is a protocol error, not a cosmetic problem.
 *   2. A toplevel configure may name 0x0, which means "you choose" — the client owns the size then.
 *   3. The shared buffer belongs to the COMPOSITOR between attach and wl_buffer.release. `busy` is that
 *      ownership, and the frame handler is only called when `frame_done` AND the release have BOTH
 *      happened — calling it on either one alone stalls the loop, because the other is what frees the
 *      buffer.
 *
 * `xdg-shell` IS THE BOOTSTRAP PROTOCOL, NOT THE DESTINATION. It is what a stock compositor speaks today;
 * Agora's own window server will want more (layers for the menu bar and dock, client-side chrome, sheets),
 * and it is behind this interface precisely so that can change without NSWindow noticing.
 */

#include "AGWindowServer.h"
#include "AGKeyboard.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <wayland-client.h>

#include "xdg-shell-client-protocol.h"
#include "agora-shell-client-protocol.h"

/* ---------------------------------------------------------------------------------------------------
 * the shm buffer
 * --------------------------------------------------------------------------------------------------- */

struct AGBuffer {
	struct wl_buffer *buffer;
	uint32_t *pixels;
	int width;
	int height;
	int stride;			/* bytes per row */
	size_t size;
	int busy;			/* the compositor holds it until wl_buffer.release */
};

struct AGWindow {
	AGWindowServer *server;
	struct wl_surface *surface;
	struct xdg_surface *xdg_surface;
	struct xdg_toplevel *toplevel;
	/* THE ROLE, WHEN THE COMPOSITOR SPEAKS AGORA'S OWN PROTOCOL — and then `xdg_surface`/`toplevel` are NULL,
	 * because a surface has ONE role and the two disagree about who decides the size. */
	struct agora_window *agora;
	int frame_x;			/* the application's frame, which this layer remembers whether or not it can
					 * send it: a compositor that cannot be told still gets a window somewhere */
	int frame_y;
	int frame_width;
	int frame_height;
	int has_frame;
	int level;
	/* Non-zero when this window is a STATUS ITEM: the width the server places it in, and the reason a later
	 * `AGWindowSetFrame` is remembered but not allowed to move it. */
	int status_length;

	struct AGBuffer buffer;
	struct wl_callback *frame_cb;

	int asked_width;		/* what the compositor last asked for; 0 means "you choose" */
	int asked_height;
	int width;			/* the real, configured size */
	int height;
	int configured;
	int begun;			/* between BeginFrame and EndFrame */

	/* The frame handler runs only when frame_done AND release have both happened. `frame_ready` is the
	 * first half, `buffer.busy == 0` the second. */
	int frame_ready;
	uint32_t last_frame_time;

	AGEventFunction event_fn;
	void *event_context;
	AGFrameFunction frame_fn;
	void *frame_context;

	struct AGWindow *next;
};

struct AGWindowServer {
	struct wl_display *display;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct xdg_wm_base *wm_base;
	struct wl_seat *seat;
	struct wl_keyboard *keyboard;
	struct wl_pointer *pointer;
	struct wl_output *output;
	struct agora_shell *shell;	/* present only when the compositor speaks it */
	struct agora_output *agora_output;
	int work_x;			/* NSScreen's -visibleFrame, as the server said it */
	int work_y;
	int work_width;
	int work_height;
	int have_work_area;
	/* **AND THE BAR'S USABLE REGION, WHICH IS NOT THE WORK AREA.** The work area is the screen minus the bar and
	 * the Dock — a VERTICAL reserve for windows. This is the strip to the right of the System menu's square — a
	 * HORIZONTAL reserve for an application's own menus, which only the server can name. */
	int menu_x;
	int menu_y;
	int menu_width;
	int menu_height;
	int have_menu_bar_area;
	unsigned int menu_colour;	/* the strip's colour, 0xRRGGBB, as the server said it */

	/* THE FIRST OUTPUT'S CURRENT MODE, which is all a client is told without asking for more. `have_screen`
	 * separates "no output has described itself yet" from "the output is zero-sized", which are different. */
	int screen_width;
	int screen_height;
	int have_screen;
	char screen_name[128];

	AGKeyboard *keyboard_state;
	int keymap_seen;

	AGWindow *windows;
	AGWindow *keyboard_focus;
	AGWindow *pointer_focus;
	int pointer_x;
	int pointer_y;

	char error[256];
};

/* ---------------------------------------------------------------------------------------------------
 * helpers
 * --------------------------------------------------------------------------------------------------- */

static uint32_t ag_now_ms(void)
{
	struct timespec now;

	clock_gettime(CLOCK_MONOTONIC, &now);
	return (uint32_t)((uint64_t)now.tv_sec * 1000u + (uint64_t)now.tv_nsec / 1000000u);
}

static void ag_server_error(AGWindowServer *server, const char *what)
{
	snprintf(server->error, sizeof server->error, "%s: %s", what, strerror(errno));
}

static void ag_window_deliver(AGWindow *window, const AGEvent *event)
{
	if (window != NULL && window->event_fn != NULL) {
		window->event_fn(window->event_context, event);
	}
}

/* Call the frame handler if — and only if — the compositor has taken the last frame AND given the buffer
 * back. Either one alone would draw into a buffer the compositor still owns, or wait for a callback that
 * already arrived. */
static void ag_window_maybe_frame(AGWindow *window)
{
	if (window == NULL || !window->frame_ready || window->buffer.busy || window->begun) {
		return;
	}
	window->frame_ready = 0;
	if (window->frame_fn != NULL) {
		window->frame_fn(window->frame_context, window->last_frame_time);
	}
}

static void ag_window_unlink(AGWindow *window)
{
	AGWindowServer *server = window->server;
	AGWindow **link = &server->windows;

	while (*link != NULL) {
		if (*link == window) {
			*link = window->next;
			break;
		}
		link = &(*link)->next;
	}
	if (server->keyboard_focus == window) {
		server->keyboard_focus = NULL;
	}
	if (server->pointer_focus == window) {
		server->pointer_focus = NULL;
	}
}

/* ---------------------------------------------------------------------------------------------------
 * the buffer
 * --------------------------------------------------------------------------------------------------- */

static int ag_create_shm_file(size_t size)
{
	char name[64];
	int fd;
	static int counter;

	/* POSIX shm AND NOT memfd_create: Agora targets Linux AND BSD, and memfd_create is Linux-only. The name
	 * is unique per process and unlinked at once, so no other process ever sees it. */
	snprintf(name, sizeof name, "/agora-app-%d-%d", (int)getpid(), counter++);
	fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
	if (fd < 0) {
		return -1;
	}
	shm_unlink(name);
	if (ftruncate(fd, (off_t)size) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static void buffer_release(void *data, struct wl_buffer *wl_buffer)
{
	AGWindow *window = data;

	(void)wl_buffer;
	window->buffer.busy = 0;
	ag_window_maybe_frame(window);
}

static const struct wl_buffer_listener buffer_listener = {
	buffer_release,
};

static void ag_window_resize(AGWindow *window, int width, int height)
{
	int stride = width * 4;
	size_t size = (size_t)stride * (size_t)height;
	struct wl_shm_pool *pool;
	int fd;
	void *data;

	if (window->buffer.buffer != NULL) {
		wl_buffer_destroy(window->buffer.buffer);
		munmap(window->buffer.pixels, window->buffer.size);
		window->buffer.buffer = NULL;
		window->buffer.pixels = NULL;
	}
	fd = ag_create_shm_file(size);
	if (fd < 0) {
		ag_server_error(window->server, "shm_open");
		return;
	}
	data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		ag_server_error(window->server, "mmap");
		close(fd);
		return;
	}
	pool = wl_shm_create_pool(window->server->shm, fd, (int32_t)size);
	window->buffer.buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
							  WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);

	window->buffer.pixels = data;
	window->buffer.width = width;
	window->buffer.height = height;
	window->buffer.stride = stride;
	window->buffer.size = size;
	window->buffer.busy = 0;
	wl_buffer_add_listener(window->buffer.buffer, &buffer_listener, window);
}

/* ---------------------------------------------------------------------------------------------------
 * presenting
 * --------------------------------------------------------------------------------------------------- */

static void frame_done(void *data, struct wl_callback *callback, uint32_t callback_time)
{
	AGWindow *window = data;

	wl_callback_destroy(callback);
	window->frame_cb = NULL;
	window->last_frame_time = callback_time;
	window->frame_ready = 1;
	ag_window_maybe_frame(window);
}

static const struct wl_callback_listener frame_listener = {
	frame_done,
};

uint32_t *AGWindowBeginFrame(AGWindow *window, int *stride)
{
	if (window == NULL || !window->configured || window->buffer.buffer == NULL) {
		/* **AND THE REASON IS NAMED, BECAUSE A DIAGNOSTIC THAT GUESSES IS WORSE THAN NONE.** The window's draw
		 * used to report every refusal as "the compositor still holds its buffer" — WHICH WAS MY INTERPRETATION AND
		 * NOT THE CONDITION: this door refuses for three different reasons, and on a protocol with no configure the
		 * `configured` one is the one that fires. MEASURED, chasing the wrong two for two rounds. */
		if (getenv("APPKIT_DRAW_DIAG") != NULL) {
			fprintf(stderr, "  DIAG begin: refused — %s\n",
				window == NULL ? "no window"
				: !window->configured ? "NOT CONFIGURED (and this protocol sends no configure)"
				: "the buffer has not been created");
		}
		return NULL;
	}
	if (window->buffer.busy) {
		if (getenv("APPKIT_DRAW_DIAG") != NULL) {
			fprintf(stderr, "  DIAG begin: refused — the compositor still holds the buffer\n");
		}
		return NULL;		/* the compositor still owns it */
	}
	if (window->begun) {
		return window->buffer.pixels;
	}
	window->begun = 1;
	if (stride != NULL) {
		*stride = window->buffer.stride;
	}
	return window->buffer.pixels;
}

void AGWindowEndFrame(AGWindow *window)
{
	if (window == NULL || !window->begun) {
		return;
	}
	window->begun = 0;
	if (window->frame_cb == NULL) {
		/* REQUESTED BEFORE THE COMMIT IT IS MEANT TO FOLLOW, which is what the protocol requires. */
		window->frame_cb = wl_surface_frame(window->surface);
		wl_callback_add_listener(window->frame_cb, &frame_listener, window);
	}
	window->buffer.busy = 1;
	wl_surface_attach(window->surface, window->buffer.buffer, 0, 0);
	wl_surface_damage_buffer(window->surface, 0, 0, window->buffer.width, window->buffer.height);
	wl_surface_commit(window->surface);
	/* WHEN THE CALLER CAME HERE FROM `AGWindowShow`, THE FLUSH ALREADY HAPPENED — before the frame was asked
	 * for and therefore before this commit. Flushing here means the frame just handed over does not wait for
	 * something else to push it out. */
	wl_display_flush(window->server->display);
}

/* ---------------------------------------------------------------------------------------------------
 * xdg-shell
 * --------------------------------------------------------------------------------------------------- */

static void wm_base_ping(void *data, struct xdg_wm_base *wm_base, uint32_t serial)
{
	(void)data;
	xdg_wm_base_pong(wm_base, serial);
}

static const struct xdg_wm_base_listener wm_base_listener = {
	wm_base_ping,
};

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width, int32_t height,
			       struct wl_array *states)
{
	AGWindow *window = data;

	(void)toplevel;
	(void)states;
	/* 0x0 means "you choose"; the client's own size stands then. */
	window->asked_width = width;
	window->asked_height = height;
}

static void toplevel_close(void *data, struct xdg_toplevel *toplevel)
{
	AGWindow *window = data;
	AGEvent event;

	(void)toplevel;
	memset(&event, 0, sizeof event);
	event.type = AGEventClose;
	ag_window_deliver(window, &event);
}

static void toplevel_configure_bounds(void *data, struct xdg_toplevel *toplevel, int32_t width, int32_t height)
{
	(void)data; (void)toplevel; (void)width; (void)height;
}

static void toplevel_wm_capabilities(void *data, struct xdg_toplevel *toplevel, struct wl_array *capabilities)
{
	(void)data; (void)toplevel; (void)capabilities;
}

static const struct xdg_toplevel_listener toplevel_listener = {
	toplevel_configure,
	toplevel_close,
	toplevel_configure_bounds,
	toplevel_wm_capabilities,
};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial)
{
	AGWindow *window = data;
	AGEvent event;
	int width = window->asked_width;
	int height = window->asked_height;

	/* THE ACK COMES FIRST — everything below is committed on this surface. */
	xdg_surface_ack_configure(xdg_surface, serial);

	if (width <= 0) {
		width = window->width;
	}
	if (height <= 0) {
		height = window->height;
	}
	if (window->buffer.buffer == NULL || width != window->buffer.width || height != window->buffer.height) {
		ag_window_resize(window, width, height);
	}
	window->width = width;
	window->height = height;
	window->configured = 1;

	memset(&event, 0, sizeof event);
	event.type = AGEventConfigure;
	event.x = width;
	event.y = height;
	ag_window_deliver(window, &event);

	/* The first frame: there is no earlier callback, so the frame handler is asked for directly. */
	window->frame_ready = 1;
	ag_window_maybe_frame(window);
}

static const struct xdg_surface_listener xdg_surface_listener = {
	xdg_surface_configure,
};

/* ---------------------------------------------------------------------------------------------------
 * input
 * --------------------------------------------------------------------------------------------------- */

static void keyboard_keymap(void *data, struct wl_keyboard *keyboard, uint32_t format, int32_t fd,
			    uint32_t size)
{
	AGWindowServer *server = data;

	(void)keyboard;
	if (format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 && size > 0 && server->keyboard_state != NULL) {
		void *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);

		if (map != MAP_FAILED) {
			if (AGKeyboardUseKeymapText(server->keyboard_state, map, size) == 0) {
				server->keymap_seen = 1;
			}
			munmap(map, size);
		}
	}
	close(fd);
}

static void keyboard_enter(void *data, struct wl_keyboard *keyboard, uint32_t serial,
			   struct wl_surface *surface, struct wl_array *keys)
{
	AGWindowServer *server = data;
	AGWindow *window = server->windows;

	(void)keyboard; (void)serial; (void)keys;
	/* The compositor names the SURFACE; find the window that owns it. */
	for (; window != NULL; window = window->next) {
		if (window->surface == surface) {
			server->keyboard_focus = window;
			break;
		}
	}
}

static void keyboard_leave(void *data, struct wl_keyboard *keyboard, uint32_t serial,
			   struct wl_surface *surface)
{
	AGWindowServer *server = data;

	(void)keyboard; (void)serial; (void)surface;
	server->keyboard_focus = NULL;
}

static void keyboard_key(void *data, struct wl_keyboard *keyboard, uint32_t serial, uint32_t time,
			 uint32_t key, uint32_t state)
{
	AGWindowServer *server = data;
	AGWindow *window = server->keyboard_focus != NULL ? server->keyboard_focus : server->windows;
	AGEvent event;

	(void)keyboard; (void)serial;
	memset(&event, 0, sizeof event);
	event.type = AGEventKey;
	event.time_ms = time != 0 ? time : ag_now_ms();
	event.keycode = key;
	event.pressed = state == WL_KEYBOARD_KEY_STATE_PRESSED;
	/* THE TRANSLATION IS UNCONDITIONAL, even on release: the caller may want the text of the key that went
	 * up, and the modifier mask is wanted either way. */
	if (server->keyboard_state != NULL) {
		AGKeyboardTranslate(server->keyboard_state, key, event.text, sizeof event.text,
				    &event.modifiers);
		event.modifier = AGKeyboardKeyIsModifier(server->keyboard_state, key);
	}
	ag_window_deliver(window, &event);
}

static void keyboard_modifiers(void *data, struct wl_keyboard *keyboard, uint32_t serial,
			       uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group)
{
	AGWindowServer *server = data;

	(void)keyboard; (void)serial;
	if (server->keyboard_state != NULL) {
		AGKeyboardSetModifiers(server->keyboard_state, depressed, latched, locked, group);
	}
}

static void keyboard_repeat_info(void *data, struct wl_keyboard *keyboard, int32_t rate, int32_t delay)
{
	(void)data; (void)keyboard; (void)rate; (void)delay;
}

static const struct wl_keyboard_listener keyboard_listener = {
	keyboard_keymap,
	keyboard_enter,
	keyboard_leave,
	keyboard_key,
	keyboard_modifiers,
	keyboard_repeat_info,
};

static void pointer_enter(void *data, struct wl_pointer *pointer, uint32_t serial,
			  struct wl_surface *surface, wl_fixed_t sx, wl_fixed_t sy)
{
	AGWindowServer *server = data;
	AGWindow *window = server->windows;
	AGEvent event;

	(void)pointer; (void)serial;
	for (; window != NULL; window = window->next) {
		if (window->surface == surface) {
			server->pointer_focus = window;
			break;
		}
	}
	server->pointer_x = wl_fixed_to_int(sx);
	server->pointer_y = wl_fixed_to_int(sy);
	memset(&event, 0, sizeof event);
	event.type = AGEventPointerEnter;
	event.pressed = 1;
	event.x = server->pointer_x;
	event.y = server->pointer_y;
	ag_window_deliver(server->pointer_focus, &event);
}

static void pointer_leave(void *data, struct wl_pointer *pointer, uint32_t serial,
			  struct wl_surface *surface)
{
	AGWindowServer *server = data;
	AGEvent event;

	(void)pointer; (void)serial; (void)surface;
	memset(&event, 0, sizeof event);
	event.type = AGEventPointerEnter;
	event.pressed = 0;
	event.x = server->pointer_x;
	event.y = server->pointer_y;
	ag_window_deliver(server->pointer_focus, &event);
	server->pointer_focus = NULL;
}

static void pointer_motion(void *data, struct wl_pointer *pointer, uint32_t time, wl_fixed_t sx, wl_fixed_t sy)
{
	AGWindowServer *server = data;
	AGEvent event;

	(void)pointer;
	server->pointer_x = wl_fixed_to_int(sx);
	server->pointer_y = wl_fixed_to_int(sy);
	memset(&event, 0, sizeof event);
	event.type = AGEventPointerMotion;
	event.time_ms = time != 0 ? time : ag_now_ms();
	event.x = server->pointer_x;
	event.y = server->pointer_y;
	ag_window_deliver(server->pointer_focus, &event);
}

static void pointer_button(void *data, struct wl_pointer *pointer, uint32_t serial, uint32_t time,
			   uint32_t button, uint32_t state)
{
	AGWindowServer *server = data;
	AGEvent event;

	(void)pointer; (void)serial;
	memset(&event, 0, sizeof event);
	event.type = AGEventPointerButton;
	event.time_ms = time != 0 ? time : ag_now_ms();
	event.button = button;
	event.pressed = state == WL_POINTER_BUTTON_STATE_PRESSED;
	event.x = server->pointer_x;
	event.y = server->pointer_y;
	ag_window_deliver(server->pointer_focus, &event);
}

static void pointer_axis(void *data, struct wl_pointer *pointer, uint32_t time, uint32_t axis, wl_fixed_t value)
{
	(void)data; (void)pointer; (void)time; (void)axis; (void)value;
}

static void pointer_frame(void *data, struct wl_pointer *pointer)
{
	(void)data; (void)pointer;
}

static void pointer_axis_source(void *data, struct wl_pointer *pointer, uint32_t source)
{
	(void)data; (void)pointer; (void)source;
}

static void pointer_axis_stop(void *data, struct wl_pointer *pointer, uint32_t time, uint32_t axis)
{
	(void)data; (void)pointer; (void)time; (void)axis;
}

static void pointer_axis_discrete(void *data, struct wl_pointer *pointer, uint32_t axis, int32_t discrete)
{
	(void)data; (void)pointer; (void)axis; (void)discrete;
}

static void pointer_axis_value120(void *data, struct wl_pointer *pointer, uint32_t axis, int32_t value120)
{
	(void)data; (void)pointer; (void)axis; (void)value120;
}

static void pointer_axis_relative_direction(void *data, struct wl_pointer *pointer, uint32_t axis,
					    uint32_t direction)
{
	(void)data; (void)pointer; (void)axis; (void)direction;
}

static const struct wl_pointer_listener pointer_listener = {
	pointer_enter,
	pointer_leave,
	pointer_motion,
	pointer_button,
	pointer_axis,
	pointer_frame,
	pointer_axis_source,
	pointer_axis_stop,
	pointer_axis_discrete,
	pointer_axis_value120,
	pointer_axis_relative_direction,
};

/* ---------------------------------------------------------------------------------------------------
 * the registry
 * --------------------------------------------------------------------------------------------------- */

static void seat_capabilities(void *data, struct wl_seat *seat, uint32_t capabilities)
{
	AGWindowServer *server = data;

	if ((capabilities & WL_SEAT_CAPABILITY_KEYBOARD) && server->keyboard == NULL) {
		server->keyboard = wl_seat_get_keyboard(seat);
		wl_keyboard_add_listener(server->keyboard, &keyboard_listener, server);
	} else if (!(capabilities & WL_SEAT_CAPABILITY_KEYBOARD) && server->keyboard != NULL) {
		wl_keyboard_release(server->keyboard);
		server->keyboard = NULL;
	}
	if ((capabilities & WL_SEAT_CAPABILITY_POINTER) && server->pointer == NULL) {
		server->pointer = wl_seat_get_pointer(seat);
		wl_pointer_add_listener(server->pointer, &pointer_listener, server);
	} else if (!(capabilities & WL_SEAT_CAPABILITY_POINTER) && server->pointer != NULL) {
		wl_pointer_release(server->pointer);
		server->pointer = NULL;
	}
}

static void seat_name(void *data, struct wl_seat *seat, const char *name)
{
	(void)data; (void)seat; (void)name;
}

static const struct wl_seat_listener seat_listener = {
	seat_capabilities,
	seat_name,
};

/* ---- THE OUTPUT, WHICH IS HOW A CLIENT LEARNS HOW BIG THE SCREEN IS ---------------------------------- */

static void output_geometry(void *data, struct wl_output *output, int32_t x, int32_t y, int32_t physical_width,
			    int32_t physical_height, int32_t subpixel, const char *make, const char *model,
			    int32_t transform)
{
	AGWindowServer *server = data;

	(void)output; (void)x; (void)y; (void)physical_width; (void)physical_height; (void)subpixel;
	(void)transform;
	/* THE MODEL IS THE ONLY NAME A WAYLAND CLIENT IS GIVEN for a screen. Apple's is whatever the display's
	 * preferences carry; this is the closest honest answer, and it is empty on a compositor that reports
	 * none — which NSScreen turns into its own fallback. */
	snprintf(server->screen_name, sizeof server->screen_name, "%s", model != NULL ? model : "");
}

static void output_mode(void *data, struct wl_output *output, uint32_t flags, int32_t width, int32_t height,
			int32_t refresh)
{
	AGWindowServer *server = data;

	(void)output; (void)refresh;
	/* ONLY THE CURRENT MODE IS THE SCREEN'S SIZE; a compositor advertises every mode it can drive. */
	if (flags & WL_OUTPUT_MODE_CURRENT) {
		server->screen_width = width;
		server->screen_height = height;
		server->have_screen = 1;
	}
}

static void output_done(void *data, struct wl_output *output)
{
	(void)data; (void)output;
}

static void output_scale(void *data, struct wl_output *output, int32_t factor)
{
	(void)data; (void)output; (void)factor;
}

static const struct wl_output_listener output_listener = {
	output_geometry,
	output_mode,
	output_done,
	output_scale,
};

/* THE WORK AREA, WHICH IS THE SERVER'S TO SAY BECAUSE THE FURNITURE IS THE SERVER'S. */
static void agora_output_menu_bar_area(void *data, struct agora_output *output, int32_t x, int32_t y, int32_t width,
				       int32_t height, uint32_t colour)
{
	AGWindowServer *server = data;

	(void)output;
	server->menu_colour = (unsigned int)(colour & 0xFFFFFFu);
	server->menu_x = (int)x;
	server->menu_y = (int)y;
	server->menu_width = (int)width;
	server->menu_height = (int)height;
	server->have_menu_bar_area = 1;
}

static void agora_output_work_area(void *data, struct agora_output *output, int32_t x, int32_t y, int32_t width,
				   int32_t height)
{
	AGWindowServer *server = data;

	(void)output;
	server->work_x = (int)x;
	server->work_y = (int)y;
	server->work_width = (int)width;
	server->work_height = (int)height;
	server->have_work_area = 1;
}

static const struct agora_output_listener agora_output_listener = {
	/* **IN THE PROTOCOL'S OWN ORDER, WHICH IS WHAT A POSITIONAL INITIALISER MEANS.** `work_area` is declared
	 * before `menu_bar_area` in `agora-shell.xml`, so these two lines cannot be swapped — MEASURED: swapped, a
	 * client reads the bar's region as the work area and vice versa, and every consequence of that looks like the
	 * SERVER lying rather than like a struct in the wrong order. */
	agora_output_work_area,
	agora_output_menu_bar_area,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
			    uint32_t version)
{
	AGWindowServer *server = data;

	/* Ask for the SMALLEST version this backend can use, capped by what the compositor offers: asking for
	 * more than it has is a protocol error. wl_compositor v4 is what damage_buffer needs. */
	if (strcmp(interface, wl_compositor_interface.name) == 0) {
		server->compositor = wl_registry_bind(registry, name, &wl_compositor_interface,
						      version < 4 ? version : 4);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		server->shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	} else if (strcmp(interface, xdg_wm_base_interface.name) == 0) {
		server->wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface,
						   version < 2 ? version : 2);
		xdg_wm_base_add_listener(server->wm_base, &wm_base_listener, server);
	} else if (strcmp(interface, wl_seat_interface.name) == 0) {
		server->seat = wl_registry_bind(registry, name, &wl_seat_interface, version < 5 ? version : 5);
		wl_seat_add_listener(server->seat, &seat_listener, server);
	} else if (strcmp(interface, wl_output_interface.name) == 0 && server->output == NULL) {
		/* THE FIRST OUTPUT ONLY, and that is a decision rather than a simplification: Agora's window server is
		 * one screen at a time for now, and a second output would need a screens ARRAY on the AppKit side —
		 * NSScreen's own row. The listener is what tells this client the size. */
		server->output = wl_registry_bind(registry, name, &wl_output_interface, version < 2 ? version : 2);
		wl_output_add_listener(server->output, &output_listener, server);
		/* **THE COMPANION OBJECT IS ASKED FOR LATER, AND THE REGISTRY ORDER IS WHY.** `wl_output` says what a
		 * screen IS and `agora_output` says what is LEFT of it — but the globals arrive in the order the
		 * COMPOSITOR registered them, and this server registers `wl_output` BEFORE `agora_shell`. Asking here
		 * would find `server->shell` still NULL and quietly get no work area at all: MEASURED as a `-visibleFrame`
		 * that reserved nothing, which is exactly what `visibleFrame` returning `frame` looks like. So it is
		 * asked once the globals are all in — see `AGWindowServerConnect`. */
	} else if (strcmp(interface, agora_shell_interface.name) == 0) {
		/* **AGORA'S OWN PROTOCOL, IF IT IS THERE.** It is what can carry the frame, the level and the work
		 * area; a stock compositor will not offer it, and then this seam falls back to `xdg-shell` and the
		 * window is placed by whoever is in charge — a difference a caller can see through
		 * `AGWindowServerWorkArea` and through its frame being recorded rather than obeyed. */
		server->shell = wl_registry_bind(registry, name, &agora_shell_interface, 1);
	}
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
	(void)data; (void)registry; (void)name;
}

static const struct wl_registry_listener registry_listener = {
	registry_global,
	registry_global_remove,
};

/* ---------------------------------------------------------------------------------------------------
 * the public surface
 * --------------------------------------------------------------------------------------------------- */

AGWindowServer *AGWindowServerConnect(void)
{
	AGWindowServer *server = calloc(1, sizeof *server);

	if (server == NULL) {
		return NULL;
	}
	server->display = wl_display_connect(NULL);
	if (server->display == NULL) {
		ag_server_error(server, "wl_display_connect");
		free(server);
		return NULL;
	}
	server->keyboard_state = AGKeyboardCreate();
	server->registry = wl_display_get_registry(server->display);
	wl_registry_add_listener(server->registry, &registry_listener, server);

	/* TWO ROUNDTRIPS: the first gets the globals, and the second is needed because the seat's capabilities
	 * arrive only after the listener has been added to it. */
	if (wl_display_roundtrip(server->display) < 0 || wl_display_roundtrip(server->display) < 0) {
		ag_server_error(server, "wl_display_roundtrip");
		AGWindowServerDisconnect(server);
		return NULL;
	}
	/* **AND NOW BOTH ARE KNOWN, WHEREVER THEY WERE IN THE REGISTRY.** The work area is the one thing this seam
	 * needs that arrives as an EVENT, so it takes another roundtrip to have it in hand before the caller is told
	 * the connection is ready — a `-visibleFrame` that answers zero because the answer is still in flight would
	 * be a door that works only sometimes. */
	if (server->shell != NULL && server->output != NULL && server->agora_output == NULL) {
		server->agora_output = agora_shell_get_output(server->shell, server->output);
		agora_output_add_listener(server->agora_output, &agora_output_listener, server);
		if (wl_display_roundtrip(server->display) < 0) {
			ag_server_error(server, "wl_display_roundtrip");
			AGWindowServerDisconnect(server);
			return NULL;
		}
	}
	if (server->compositor == NULL || server->shm == NULL || server->wm_base == NULL) {
		snprintf(server->error, sizeof server->error,
			 "the compositor is missing a required global (wl_compositor=%s wl_shm=%s xdg_wm_base=%s)",
			 server->compositor ? "yes" : "no", server->shm ? "yes" : "no",
			 server->wm_base ? "yes" : "no");
		AGWindowServerDisconnect(server);
		return NULL;
	}
	/* A headless seat sends no keymap; without one nothing can be translated, so take the system's. */
	if (server->keyboard_state != NULL && !server->keymap_seen) {
		AGKeyboardUseDefaultKeymap(server->keyboard_state);
	}
	return server;
}

void AGWindowServerDisconnect(AGWindowServer *server)
{
	if (server == NULL) {
		return;
	}
	while (server->windows != NULL) {
		AGWindowDestroy(server->windows);
	}
	if (server->pointer != NULL) {
		wl_pointer_destroy(server->pointer);
	}
	if (server->keyboard != NULL) {
		wl_keyboard_destroy(server->keyboard);
	}
	if (server->output != NULL) {
		wl_output_destroy(server->output);
	}
	if (server->seat != NULL) {
		wl_seat_destroy(server->seat);
	}
	if (server->wm_base != NULL) {
		xdg_wm_base_destroy(server->wm_base);
	}
	if (server->shm != NULL) {
		wl_shm_destroy(server->shm);
	}
	if (server->compositor != NULL) {
		wl_compositor_destroy(server->compositor);
	}
	if (server->registry != NULL) {
		wl_registry_destroy(server->registry);
	}
	if (server->display != NULL) {
		wl_display_disconnect(server->display);
	}
	AGKeyboardDestroy(server->keyboard_state);
	free(server);
}

int AGWindowServerDispatchPending(AGWindowServer *server)
{
	struct pollfd pfd;

	if (server == NULL) {
		return -1;
	}
	/* The prepare_read dance is what makes "read whatever is there, without blocking" safe: a plain
	 * wl_display_dispatch would block, and a second reader on the same display is a protocol error. */
	if (wl_display_prepare_read(server->display) != 0) {
		return wl_display_dispatch_pending(server->display) < 0 ? -1 : 1;
	}
	wl_display_flush(server->display);
	pfd.fd = wl_display_get_fd(server->display);
	pfd.events = POLLIN;
	if (poll(&pfd, 1, 0) > 0 && (pfd.revents & POLLIN)) {
		if (wl_display_read_events(server->display) < 0) {
			ag_server_error(server, "wl_display_read_events");
			return -1;
		}
	} else {
		wl_display_cancel_read(server->display);
	}
	return wl_display_dispatch_pending(server->display) < 0 ? -1 : 1;
}

int AGWindowServerDispatch(AGWindowServer *server)
{
	if (server == NULL) {
		return -1;
	}
	if (wl_display_dispatch(server->display) < 0) {
		ag_server_error(server, "wl_display_dispatch");
		return -1;
	}
	return 1;
}

int AGWindowServerDispatchTimeout(AGWindowServer *server, int timeout_ms)
{
	struct pollfd pfd;
	int ready;

	if (server == NULL) {
		return -1;
	}
	/* DRAIN WHAT IS ALREADY QUEUED FIRST: a caller asking for a poll must not block on a socket that has
	 * nothing to say while events are sitting in the queue behind it. */
	if (wl_display_dispatch_pending(server->display) < 0) {
		ag_server_error(server, "wl_display_dispatch_pending");
		return -1;
	}
	if (wl_display_prepare_read(server->display) != 0) {
		/* Events arrived in between, or another reader holds the display: take what is there rather than
		 * blocking, because a timeout of zero must not. */
		return wl_display_dispatch_pending(server->display) < 0 ? -1 : 1;
	}
	wl_display_flush(server->display);
	pfd.fd = wl_display_get_fd(server->display);
	pfd.events = POLLIN;
	ready = poll(&pfd, 1, timeout_ms);
	if (ready > 0 && (pfd.revents & POLLIN)) {
		if (wl_display_read_events(server->display) < 0) {
			ag_server_error(server, "wl_display_read_events");
			return -1;
		}
	} else {
		wl_display_cancel_read(server->display);
	}
	if (wl_display_dispatch_pending(server->display) < 0) {
		ag_server_error(server, "wl_display_dispatch_pending");
		return -1;
	}
	return 1;
}

void AGWindowServerFlush(AGWindowServer *server)
{
	if (server != NULL) {
		wl_display_flush(server->display);
	}
}

const char *AGWindowServerLastError(AGWindowServer *server)
{
	return server != NULL ? server->error : "no connection";
}

void AGWindowServerScreenSize(AGWindowServer *server, int *width, int *height, const char **name)
{
	if (width != NULL) {
		*width = server != NULL ? server->screen_width : 0;
	}
	if (height != NULL) {
		*height = server != NULL ? server->screen_height : 0;
	}
	if (name != NULL) {
		*name = (server != NULL && server->screen_name[0] != '\0') ? server->screen_name : NULL;
	}
}

AGWindow *AGWindowCreate(AGWindowServer *server, int width, int height, const char *title)
{
	AGWindow *window;

	if (server == NULL || server->compositor == NULL || server->wm_base == NULL) {
		return NULL;
	}
	window = calloc(1, sizeof *window);
	if (window == NULL) {
		return NULL;
	}
	window->server = server;
	window->width = width > 0 ? width : 640;
	window->height = height > 0 ? height : 400;

	window->surface = wl_compositor_create_surface(server->compositor);
	window->next = server->windows;
	server->windows = window;

	/* **AGORA'S OWN PROTOCOL WHEN IT IS THERE, `xdg-shell` WHEN IT IS NOT.** This is the path that can carry
	 * the Mac's model — a frame the server honours, an integer level, a work area — and the other is the
	 * bootstrap for a compositor that cannot. A stock compositor offers no `agora_shell`, so a caller can tell
	 * which it got by whether its frame was obeyed and by what `AGWindowServerWorkArea` answers. */
	if (server->shell != NULL) {
		/* **THE AGORA ROLE, AND THERE IS NO CONFIGURE TO WAIT FOR.** xdg-shell makes a client ask to be
		 * configured and take the size it is given; this protocol is the Mac's, where the application states a
		 * frame and the server honours it — so the window is usable the moment it is made, at the size asked
		 * for, and the frame it will be shown at is whatever `AGWindowSetFrame` last said. */
		window->agora = agora_shell_get_window(server->shell, window->surface);
		if (title != NULL) {
			agora_window_set_title(window->agora, title);
		}
		agora_window_set_app_id(window->agora, "org.agora.AppKit");
		agora_window_set_frame(window->agora, window->has_frame ? window->frame_x : 0,
				       window->has_frame ? window->frame_y : 0, window->width, window->height);
		ag_window_resize(window, window->width, window->height);
		window->configured = 1;
	} else {
		window->xdg_surface = xdg_wm_base_get_xdg_surface(server->wm_base, window->surface);
		xdg_surface_add_listener(window->xdg_surface, &xdg_surface_listener, window);
		window->toplevel = xdg_surface_get_toplevel(window->xdg_surface);
		xdg_toplevel_add_listener(window->toplevel, &toplevel_listener, window);
		if (title != NULL) {
			xdg_toplevel_set_title(window->toplevel, title);
		}
		xdg_toplevel_set_app_id(window->toplevel, "org.agora.AppKit");
		/* AN EMPTY COMMIT GIVES THE SURFACE ITS ROLE and is what asks for the first configure. The window has
		 * no size until that arrives. */
		wl_surface_commit(window->surface);
	}
	wl_display_flush(server->display);
	return window;
}

void AGWindowDestroy(AGWindow *window)
{
	if (window == NULL) {
		return;
	}
	ag_window_unlink(window);
	if (window->frame_cb != NULL) {
		wl_callback_destroy(window->frame_cb);
	}
	if (window->buffer.buffer != NULL) {
		wl_buffer_destroy(window->buffer.buffer);
	}
	if (window->buffer.pixels != NULL) {
		munmap(window->buffer.pixels, window->buffer.size);
	}
	if (window->agora != NULL) {
		agora_window_destroy(window->agora);
	}
	if (window->toplevel != NULL) {
		xdg_toplevel_destroy(window->toplevel);
	}
	if (window->xdg_surface != NULL) {
		xdg_surface_destroy(window->xdg_surface);
	}
	if (window->surface != NULL) {
		wl_surface_destroy(window->surface);
	}
	free(window);
}

void AGWindowShow(AGWindow *window)
{
	if (window == NULL) {
		return;
	}
	/* WAYLAND HAS NO SEPARATE "MAP": a surface with a role and a committed buffer is shown. The commit
	 * exists for the case where the caller shows a window that has not been committed yet. */
	wl_surface_commit(window->surface);
	wl_display_flush(window->server->display);
	if (window->agora != NULL) {
		/* **AND THE FIRST FRAME STARTS HERE.** With `xdg-shell` the compositor's configure is what starts the
		 * drawing; with this protocol there is no configure, so the door that means "show it" is the one that
		 * says the first frame may be drawn. */
		window->frame_ready = 1;
		ag_window_maybe_frame(window);
	}
}

/* ---------------------------------------------------------------------------------------------------
 * the frame, the level, and the work area
 * --------------------------------------------------------------------------------------------------- */

void AGWindowSetFrame(AGWindow *window, int x, int y, int width, int height)
{
	if (window == NULL) {
		return;
	}
	window->frame_x = x;
	window->frame_y = y;
	window->has_frame = 1;
	/* A RESIZE MAKES THE BACKING STORE AGAIN, and only when the compositor is not holding it: the buffer that
	 * is on screen is not this process's to free. */
	if (width > 0 && height > 0 && (width != window->width || height != window->height)) {
		window->width = width;
		window->height = height;
		if (window->configured && !window->buffer.busy) {
			ag_window_resize(window, width, height);
		}
	}
	if (window->agora != NULL) {
		agora_window_set_frame(window->agora, x, y, width, height);
	}
	wl_display_flush(window->server->display);
}

void AGWindowSetLevel(AGWindow *window, int level)
{
	if (window == NULL) {
		return;
	}
	window->level = level;
	if (window->agora != NULL) {
		agora_window_set_level(window->agora, level);
		wl_display_flush(window->server->display);
	}
}

/* **THE ONE KIND OF WINDOW THE SERVER PLACES, AND THE DOOR IS A KIND RATHER THAN A FRAME.** `NSStatusItem` says
 * how long its item is and nothing about where it goes, because an application cannot know what else is in the
 * status bar. So the width is what is sent — and the frame this layer remembers is left alone, so that a client
 * that asks to be somewhere anyway does not get to move one. */
void AGWindowSetStatusItem(AGWindow *window, int length)
{
	if (window == NULL) {
		return;
	}
	window->status_length = length > 0 ? length : 0;
	if (window->agora != NULL) {
		agora_window_set_status_item(window->agora, window->status_length);
		wl_display_flush(window->server->display);
	}
}

/* **AND THE ONE WAY TO HIDE A SURFACE THE PROTOCOL HAS.** A `wl_surface` is not "on" or "off" — it is a picture
 * that may or may not be attached — so the compositor is TOLD, and an Agora server takes it off the glass. A client
 * of a stock compositor gets the state change and nothing else, which is why `-orderOut:`'s comment could say the
 * screen never changed: it was true of `xdg-shell` and is not true of this. */
void AGWindowHide(AGWindow *window)
{
	if (window == NULL) {
		return;
	}
	if (window->agora != NULL) {
		agora_window_set_visible(window->agora, 0);
		wl_display_flush(window->server->display);
	}
}

void AGWindowRaise(AGWindow *window)
{
	if (window != NULL && window->agora != NULL) {
		agora_window_raise(window->agora);
		wl_display_flush(window->server->display);
	}
}

void AGWindowServerMenuBarArea(AGWindowServer *server, int *x, int *y, int *width, int *height)
{
	if (x != NULL) {
		*x = (server != NULL && server->have_menu_bar_area) ? server->menu_x : 0;
	}
	if (y != NULL) {
		*y = (server != NULL && server->have_menu_bar_area) ? server->menu_y : 0;
	}
	if (width != NULL) {
		*width = (server != NULL && server->have_menu_bar_area) ? server->menu_width : 0;
	}
	if (height != NULL) {
		*height = (server != NULL && server->have_menu_bar_area) ? server->menu_height : 0;
	}
}

void AGWindowServerMenuBarColour(AGWindowServer *server, unsigned int *rgb)
{
	if (rgb != NULL) {
		*rgb = (server != NULL && server->have_menu_bar_area) ? server->menu_colour : 0u;
	}
}

void AGWindowServerWorkArea(AGWindowServer *server, int *x, int *y, int *width, int *height)
{
	if (x != NULL) {
		*x = (server != NULL && server->have_work_area) ? server->work_x : 0;
	}
	if (y != NULL) {
		*y = (server != NULL && server->have_work_area) ? server->work_y : 0;
	}
	if (width != NULL) {
		*width = (server != NULL && server->have_work_area) ? server->work_width : 0;
	}
	if (height != NULL) {
		*height = (server != NULL && server->have_work_area) ? server->work_height : 0;
	}
}

void AGWindowSetTitle(AGWindow *window, const char *title)
{
	if (window != NULL && window->toplevel != NULL && title != NULL) {
		xdg_toplevel_set_title(window->toplevel, title);
		wl_display_flush(window->server->display);
	}
}

int AGWindowWidth(const AGWindow *window)
{
	return window != NULL ? window->width : 0;
}

int AGWindowHeight(const AGWindow *window)
{
	return window != NULL ? window->height : 0;
}

int AGWindowIsConfigured(const AGWindow *window)
{
	return window != NULL && window->configured;
}

void AGWindowSetEventHandler(AGWindow *window, AGEventFunction function, void *context)
{
	if (window != NULL) {
		window->event_fn = function;
		window->event_context = context;
	}
}

void AGWindowSetFrameHandler(AGWindow *window, AGFrameFunction function, void *context)
{
	if (window != NULL) {
		window->frame_fn = function;
		window->frame_context = context;
	}
}
