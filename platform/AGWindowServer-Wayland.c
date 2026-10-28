/*
 * AGWindowServer-Wayland.c — the seam's first implementation: an `xdg-shell` client.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
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
 * **AND THERE ARE TWO BUFFERS PER WINDOW, BECAUSE ONE BUFFER IS A BLINK A PERSON CAN SEE.** With one, the buffer
 * the compositor is SHOWING is also the only place a frame can be drawn: the compositor releases it after a
 * composite and goes on treating it as the surface's content, so the whole repaint — the background fill, the view
 * tree, the chrome — happens inside pixels that are still on the glass. Any composite that lands in that window
 * (another window committing, which is what a focus change IS) puts a half-drawn window on the screen. MEASURED,
 * capturing the nested output at 60 Hz through a click from one window to another: 59% of one window's pixels
 * changed in a single captured frame, and the frame showed both windows part-painted, for about eight frames.
 *
 * So `buffer` is what the compositor has and `spare` is what a frame is drawn into; `AGWindowEndFrame` attaches the
 * spare and they swap. The compositor gives a buffer back when the commit that REPLACES it arrives (`surface.c`),
 * which is exactly the moment painting into it becomes safe — that pairing is the whole of the fix, and it is why
 * neither side alone is enough: double buffering under a release-per-frame compositor still paints a buffer the
 * compositor is sampling, because that release does not mean "I have moved on".
 *
 * `xdg-shell` IS THE BOOTSTRAP PROTOCOL, NOT THE DESTINATION. It is what a stock compositor speaks today;
 * Agora's own window server will want more (layers for the menu bar and dock, client-side chrome, sheets),
 * and it is behind this interface precisely so that can change without NSWindow noticing.
 */

#include "AGWindowServer.h"
#include "AGKeyboard.h"
#ifdef AG_HAVE_GL
#include "AGGL.h"
#endif

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

/* **AND THE GPU-BUFFER PATH, WHEN THE BUILD HAS IT.** `AG_HAVE_DMABUF` is the CMake option's decision, not a
 * runtime one: without it this file still allocates shared memory and every window works, which is why the
 * fallback is the ABSENCE of the code below rather than a flag someone has to remember to set. */
struct gbm_bo;

#ifdef AG_HAVE_DMABUF
#include <gbm.h>

#include "linux-dmabuf-v1-client-protocol.h"

#ifdef __linux__
#include <sys/ioctl.h>
#include <linux/dma-buf.h>
#endif

/* THE DRM VOCABULARY, SPELLED HERE RATHER THAN PULLED IN FROM libdrm. `gbm.h` does not need `<drm_fourcc.h>`, and
 * a fourcc is an integer — a header-only dependency on libdrm's include path for three constants is not one. */
#define AG_FOURCC(a, b, c, d) \
	((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | ((uint32_t)(d) << 24))
#define AG_DRM_FORMAT_XRGB8888 AG_FOURCC('X', 'R', '2', '4')
#define AG_DRM_FORMAT_ARGB8888 AG_FOURCC('A', 'R', '2', '4')
#define AG_DRM_FORMAT_MOD_LINEAR 0ULL
#endif /* AG_HAVE_DMABUF */

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
	/* **AND WHEN THE PIXELS ARE A GPU BUFFER RATHER THAN A MAPPING.** `bo` non-NULL means `pixels` is GBM's own
	 * mapping of GPU memory and `dmabuf_fd` is the descriptor kept for `DMA_BUF_IOCTL_SYNC`; the shared-memory path
	 * leaves all three zero and `pixels` is an `mmap` that `ag_buffer_dispose` unmaps. The two lifetimes are
	 * genuinely different — one is `munmap`, the other is unmap-the-bo then destroy-it — which is why the disposal
	 * has to ask which kind it has. */
	struct gbm_bo *bo;
	void *map_data;
	int dmabuf_fd;
	/* **AND WHEN THE BUFFER WAS MADE BY EGL RATHER THAN BY GBM.** A GPU buffer has two possible origins and they are not
	 * interchangeable: MEASURED on this machine, a `gbm_bo_create_with_modifiers` allocation is REFUSED by this same
	 * device's EGL (`glEGLImageTargetTexture2DOES` answers `GL_INVALID_OPERATION`, so nobody can render into it), while a
	 * texture exported with `EGL_MESA_image_dma_buf_export` imports and renders perfectly. `egl_texture` non-zero means
	 * this slot's memory IS that texture, and the texture must outlive every descriptor handed out from it, because an
	 * export aliases it rather than copying. */
	unsigned int egl_texture;
	/* **AND THE LAYOUT THE MEMORY WAS MADE WITH**, which a caller importing it needs and which only `gbm_bo` can answer
	 * after the fact — an EGL-exported buffer has no handle to ask, so both allocators record it here. */
	unsigned int fourcc;
	unsigned long long modifier;
};

/* HOW MANY RECTANGLES ONE FRAME MAY NAME. Sixteen covers a window's damage pieces (`APPKIT_DAMAGE_RECTS` is that
 * kind of budget on the AppKit side too); past it the last slot grows rather than anything being dropped. */
#define AG_WINDOW_DAMAGE_MAX 16

/* THE ONE RECTANGLE TYPE, NAMED, because an array of an anonymous struct and another array of a DIFFERENT anonymous
 * struct cannot be assigned to each other — which is exactly what recording the last frame's damage does. */
struct AGDamageRect {
	int x, y, w, h;
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
	/* **THE OUTPUT SCALE THIS WINDOW'S BUFFERS ARE MADE AT.** The frame is LOGICAL — the size the application asked
	 * for and the size the compositor places — and the buffer is `frame x scale`, rounded to whole device pixels.
	 * Copied rather than read through `server` so a buffer's dimensions are a fact about the window that owns it.
	 * A double, because a point is 1/72 inch and a 57.97-dpi panel's scale is 0.805. */
	double scale;
	/* **THE SELECTION'S FIVE CALLBACKS AND THEIR CONTEXT**, installed by whoever wants the clipboard. Held here rather
	 * than per-window because a selection belongs to the application, not to a surface. */
	AGSelectionHandlers selection;
	/* **ONE KEYBOARD TENURE AT A TIME, AND IT IS NUMBERED.** Raised on every `wl_keyboard.enter` and by nothing else,
	 * so two events with the same number were delivered without the keyboard leaving this application in between. */
	uint32_t focus_serial;
	int level;
	/* **WHICH APPLICATION THIS WINDOW BELONGS TO.** The bundle identifier, empty until the owner says otherwise —
	 * it used to be the constant "org.agora.AppKit" written into `AGWindowCreate`, which made every Agora
	 * application the same application to anything that asked. */
	char app_id[128];
	/* **WHETHER THIS WINDOW'S PIXELS CARRY ALPHA**, which decides the shm buffer's FORMAT: ARGB8888 when set,
	 * XRGB8888 when not. The compositor blends a transparent buffer over what is behind it. */
	int transparent;
	/* Non-zero when this window is a STATUS ITEM: the width the server places it in, and the reason a later
	 * `AGWindowSetFrame` is remembered but not allowed to move it. */
	int status_length;
	/* **AND WHERE THE POINTER IS IN THE OUTPUT, KEPT FROM THE COMPOSITOR'S `pointer_global`.** Absolute, so a
	 * drag that moves this window can follow the pointer without depending on where the window is. */
	int global_x;
	int global_y;
	int has_global;

	/* **TWO BUFFERS, AND THEY SWAP: `buffer` IS ON THE SCREEN AND `spare` IS WHAT A FRAME IS DRAWN INTO.**
	 * Painting the buffer the compositor is showing is what made a focus change blink — see the note at the top of
	 * this file — so a frame is drawn into the one the compositor does NOT have, and `AGWindowEndFrame` attaches it.
	 * `AGBuffer.busy` follows the compositor's release, one flag per buffer. */
	struct AGBuffer buffer;
	struct AGBuffer spare;
	struct wl_callback *frame_cb;

	int asked_width;		/* what the compositor last asked for; 0 means "you choose" */
	int asked_height;
	/* **AND A SIZE ASKED FOR WHILE A FRAME IS BEING DRAWN.** A resize cannot land under the frame that asked for
	 * it: the caller holds the old buffer's pointer and its stride, and `AGWindowWidth` would already be the new
	 * one — MEASURED, that is a write past the end of a 640x400 mapping with 680x430's dimensions, and it
	 * segfaulted. The request waits here and is made when the buffer comes back. */
	int pending_width;
	int pending_height;
	int width;			/* the real, configured size */
	int height;
	int configured;
	int begun;			/* between BeginFrame and EndFrame */
	/* **AND WHICH KIND OF FRAME IT IS.** A GPU frame's pixels were written by the GPU, so the CPU cache maintenance
	 * `ag_buffer_sync` performs at the commit is not just unnecessary — it is about a mapping that was never used. */
	int begun_gpu;
	int gpu_frame_pending;

	/* **THE DAMAGE THIS FRAME WILL ASK FOR, AND THE DAMAGE THE LAST ONE DID.** `damage` accumulates what the caller
	 * says it changed (buffer pixels, top-down rows) and is emptied by `AGWindowEndFrame`; `last_damage` is kept so a
	 * diagnostic — and a test — can ask what the last commit actually told the compositor, which is the only place
	 * that number exists. A frame with NO recorded damage damages the whole buffer, which is the safe default for a
	 * caller that does not track its own. */
	struct AGDamageRect damage[AG_WINDOW_DAMAGE_MAX];
	int damage_count;
	struct AGDamageRect last_damage[AG_WINDOW_DAMAGE_MAX];
	int last_damage_count;

	/* The frame handler runs only when `frame_done` has arrived AND the buffer a frame would be drawn into is this
	 * process's again. `frame_ready` is the first half, `spare.busy == 0` the second. */
	int frame_ready;
	uint32_t last_frame_time;

	AGEventFunction event_fn;
	void *event_context;
	AGFrameFunction frame_fn;
	void *frame_context;
	/* **AND THE TWO DOORS OF A DOCK TILE'S MENU, which are not `AGEvent`s**: one has no argument at all — it is a
	 * question — and the other's is an ITEM rather than a position, so folding either into the event struct would
	 * be a field every other window carried for one caller's sake. */
	AGDockMenuRequestFunction dock_menu_request_fn;
	AGDockMenuActionFunction dock_menu_action_fn;
	void *dock_menu_context;

	struct AGWindow *next;
};

struct AGWindowServer {
	struct wl_display *display;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	/* **AND THE GPU-BUFFER GLOBAL, WHEN THE COMPOSITOR OFFERS ONE.** NULL when it does not — a compositor running
	 * the CPU renderer advertises nothing to import — and then every window keeps the shared-memory path. The
	 * advertised (format, modifier) pairs are kept because the client may only allocate what the server said it can
	 * sample; allocating anything else is a `failed` event at `create` time with no diagnosis. */
#ifdef AG_HAVE_DMABUF
	struct zwp_linux_dmabuf_v1 *dmabuf;
	struct gbm_device *gbm;
	int gbm_fd;
	/* **THE GPU ALLOCATOR, LAZILY.** One EGL context per connection, on the same device the window's buffers come from,
	 * used only to make those buffers — the client's own rendering context is its own business. */
	AGGLContext *gl;
	struct {
		uint32_t format;
		uint64_t modifier;
	} dmabuf_formats[64];
	int dmabuf_format_count;
#endif
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
	/* **THE OUTPUT'S DEVICE PIXELS PER LOGICAL PIXEL, WHICH THIS CLIENT HAS TO RENDER AT.** `wl_output.scale` is how
	 * a compositor says "this screen is HiDPI"; a client that ignores it draws soft pixels that the compositor
	 * upscales, and one that honours it renders at that resolution and asks for the buffer to be placed at the
	 * logical size. It arrives with the output, before any window exists, so a window is created already knowing.
	 * **AND IT IS A DOUBLE, BECAUSE THE PROTOCOL'S INTEGER IS ONLY A CEILING**: `agora_output.preferred_scale`
	 * carries the display's real fraction (1.333, 0.805) and, when it arrives, replaces the integer — that is what
	 * lets the client rasterise on the device grid instead of at 2x and let the compositor resample. */
	double scale;
	int have_fractional_scale;	/* the preferred_scale event has arrived; the wl_output ceiling is ignored */
	/* **THE SELECTION'S FIVE CALLBACKS AND THEIR CONTEXT**, installed by whoever wants the clipboard. Held here rather
	 * than per-window because a selection belongs to the application, not to a surface. */
	AGSelectionHandlers selection;
	/* **ONE KEYBOARD TENURE AT A TIME, AND IT IS NUMBERED.** Raised on every `wl_keyboard.enter` and by nothing else,
	 * so two events with the same number were delivered without the keyboard leaving this application in between. */
	uint32_t focus_serial;
	int have_screen;
	char screen_name[128];

	AGKeyboard *keyboard_state;
	int keymap_seen;
	/* **THE REPEAT POLICY, WHICH THE COMPOSITOR SETS AND THIS CLIENT OWNS.** `wl_keyboard.repeat_info` names a rate
	 * in keys per second and a delay in milliseconds; a rate of ZERO means "do not repeat at all", which is a policy
	 * a client must honour rather than override. The held key is remembered with the event it produced, because a
	 * repeat is that same keystroke again — same characters, same modifiers — marked so the application can tell it
	 * apart. `repeat_active` is what every one of the cancel paths below clears. */
	int repeat_rate;		/* keys per second; 0 disables repeats entirely */
	int repeat_delay;		/* milliseconds before the first repeat */
	int repeat_active;
	uint32_t repeat_key;		/* the evdev code being held */
	uint32_t repeat_due_ms;		/* when the next repeat is due, on the monotonic clock */
	AGEvent repeat_event;		/* the press this repeats: text, modifiers, window */

	/* **THE WINDOW LIST, FOR A SHELL COMPONENT.** Asked for lazily (`AGWindowListSetHandler`) because the snapshot is
	 * re-sent on every window change and an ordinary application must not pay for a Dock's bookkeeping. The rows
	 * are built between `begin` and `done` and handed over whole: the callback sees a SNAPSHOT, never a half-built
	 * list. */
	struct agora_window_list *window_list;
	AGWindowListFunction list_fn;
	void *list_context;
	AGWindowInfo list_rows[AG_WINDOW_LIST_MAX];
	int list_count;
	int list_in_snapshot;
	/* **AND THE MENU A DOCK IS WAITING FOR.** One at a time, because a dock shows one menu at a time: the ask is
	 * abandoned and replaced by a second one, and the answer destroys it. The handler is the caller's, and it runs
	 * INSIDE the dispatch that delivered the answer, which is what lets a caller wait for it without a queue. */
	struct agora_dock_menu *dock_menu;
	AGDockMenuFunction dock_menu_fn;
	void *dock_menu_context;

	AGWindow *windows;
	AGWindow *keyboard_focus;
	AGWindow *pointer_focus;
	int pointer_x;
	int pointer_y;
	/* **ONE GESTURE'S AXES, ACCUMULATED UNTIL THE FRAME CLOSES.** `wl_pointer` sends `axis` per axis and then ONE
	 * `frame`, and this is the only moment the compositor says "those belong together". They are accumulated rather
	 * than delivered one at a time so that a two-axis gesture arrives as two events from ONE gesture — and so that
	 * the units are decided once, here, rather than by every reader of the seam. */
	struct {
		double vertical;
		double horizontal;
		int32_t vertical120;
		int32_t horizontal120;
		int32_t vertical_discrete;
		int32_t horizontal_discrete;
		int have_vertical;
		int have_horizontal;
		int have_discrete;
		uint32_t source;
	} axis;

	/* **WHETHER THIS APPLICATION HAS THE KEYBOARD, and who to tell when that changes.** It is derived from
	 * `keyboard_focus` and not stored twice: the handler fires on the transition and nothing else reads a
	 * separate flag. */
	AGActivationFunction activation_fn;
	void *activation_context;
	int active;

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

/* **THE ONE PLACE ACTIVATION CHANGES, so the handler fires exactly once per transition.** `keyboard_enter` and
 * `keyboard_leave` are per WINDOW; this application is active while ANY of its windows has the keyboard, so
 * entering a second window while already active is not a change and says nothing. */
static void ag_server_set_active(AGWindowServer *server, int active)
{
	active = active ? 1 : 0;
	if (server->active == active) {
		return;
	}
	server->active = active;
	if (server->activation_fn != NULL) {
		server->activation_fn(server->activation_context, active);
	}
}

static void ag_server_error(AGWindowServer *server, const char *what)
{
	snprintf(server->error, sizeof server->error, "%s: %s", what, strerror(errno));
}

/* Defined below, and used by the commit path above it. */
static int ag_flush_drain(AGWindowServer *server, int timeout_ms);

static void ag_window_deliver(AGWindow *window, const AGEvent *event)
{
	if (window != NULL && window->event_fn != NULL) {
		window->event_fn(window->event_context, event);
	}
}

/* Call the frame handler if — and only if — the compositor has taken the last frame AND given back the buffer a
 * frame would be drawn into. Either one alone would draw into a buffer the compositor still owns, or wait for a
 * callback that already arrived. */
static void ag_window_maybe_frame(AGWindow *window)
{
	if (window == NULL || !window->frame_ready || window->spare.busy || window->begun) {
		return;
	}
	window->frame_ready = 0;
	if (window->frame_fn != NULL) {
		window->frame_fn(window->frame_context, window->last_frame_time);
	}
}

/* DEFINED WITH THE KEYBOARD HANDLERS, DECLARED HERE BECAUSE THE WINDOW TEARDOWN NEEDS IT TOO — a window going away
 * is one of the six ways a held key stops being held. */
static void ag_repeat_cancel(AGWindowServer *server);
static void ag_repeat_fire_if_due(AGWindowServer *server);

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
		/* **A DESTROYED WINDOW TAKES THE HELD KEY WITH IT.** The key event would be delivered to this window and
		 * there is no longer one; leaving the repeat armed would fire it at whatever the focus became. */
		ag_repeat_cancel(server);
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

static int ag_buffer_make(AGWindow *window, struct AGBuffer *slot, int width, int height);
static void ag_window_resize(AGWindow *window, int width, int height);
static void ag_window_apply_pending_resize(AGWindow *window);

/* LET GO OF A BUFFER'S RESOURCES, whichever of the two it is. */
static void ag_buffer_dispose(struct AGBuffer *buffer)
{
	if (buffer->buffer != NULL) {
		wl_buffer_destroy(buffer->buffer);
	}
#ifdef AG_HAVE_DMABUF
	if (buffer->egl_texture != 0) {
		/* An EGL-allocated slot: the texture IS the memory, so it goes last, after the descriptor that aliases it. */
		if (buffer->dmabuf_fd >= 0) {
			close(buffer->dmabuf_fd);
		}
		buffer->egl_texture = 0;
		memset(buffer, 0, sizeof *buffer);
		return;
	}
	if (buffer->bo != NULL) {
		/* **THE GPU BUFFER IS UNMAPPED FIRST AND DESTROYED SECOND**, and the descriptor last: the mapping belongs
		 * to the bo, and the bo's destroy is what drops this process's reference to the memory. */
		if (buffer->map_data != NULL) {
			gbm_bo_unmap(buffer->bo, buffer->map_data);
		}
		gbm_bo_destroy(buffer->bo);
		if (buffer->dmabuf_fd >= 0) {
			close(buffer->dmabuf_fd);
		}
		memset(buffer, 0, sizeof *buffer);
		return;
	}
#endif
	if (buffer->pixels != NULL) {
		munmap(buffer->pixels, buffer->size);
	}
	memset(buffer, 0, sizeof *buffer);
}

static void buffer_release(void *data, struct wl_buffer *wl_buffer)
{
	AGWindow *window = data;
	struct AGBuffer *slot;

	/* **THE RELEASE NAMES ITS BUFFER, AND WITH TWO ALIVE AT ONCE THAT MATTERS: it says WHICH SLOT is this process's
	 * again.** `buffer` is the one that was on the glass; `spare` is the one the commit that replaced it gave
	 * back, and either can be the one a release names. */
	if (window->buffer.buffer == wl_buffer) {
		slot = &window->buffer;
	} else if (window->spare.buffer == wl_buffer) {
		slot = &window->spare;
	} else {
		return;
	}
	slot->busy = 0;
	/* **AND A SIZE THAT WAS ASKED FOR WHILE IT WAS HELD IS MADE NOW.** A resize cannot free a buffer the
	 * compositor is drawing (see `ag_window_resize`), so it leaves the request in the window's own size —
	 * exactly the comparison here: the buffer no longer matches the window, and THIS is the moment it becomes
	 * this process's again. Only the DRAWING slot is remade; the one on the glass keeps its pixels until it is
	 * replaced. */
	if (slot == &window->spare) {
		ag_window_apply_pending_resize(window);
	}
	ag_window_maybe_frame(window);
}

static const struct wl_buffer_listener buffer_listener = {
	buffer_release,
};

/* ---------------------------------------------------------------------------------------------------
 * the GPU buffer, when the compositor can import one
 * --------------------------------------------------------------------------------------------------- */

#ifdef AG_HAVE_DMABUF

/* **THE PAIRS THE SERVER SAYS IT CAN SAMPLE.** A v3 compositor sends `format` followed by one `modifier` per pair;
 * a v1/v2 one sends only `format`, and LINEAR is the layout the protocol assumes in that case. Recording both forms
 * the same way means the allocation code asks one question — "is this (format, modifier) advertised?" — and never
 * has to know which version answered. */
static void ag_dmabuf_record(AGWindowServer *server, uint32_t format, uint64_t modifier)
{
	int i;

	for (i = 0; i < server->dmabuf_format_count; i++) {
		if (server->dmabuf_formats[i].format == format &&
		    server->dmabuf_formats[i].modifier == modifier) {
			return;
		}
	}
	if (server->dmabuf_format_count >= (int)(sizeof server->dmabuf_formats /
						 sizeof server->dmabuf_formats[0])) {
		return;
	}
	server->dmabuf_formats[server->dmabuf_format_count].format = format;
	server->dmabuf_formats[server->dmabuf_format_count].modifier = modifier;
	server->dmabuf_format_count++;
}

static void ag_dmabuf_format(void *data, struct zwp_linux_dmabuf_v1 *dmabuf, uint32_t format)
{
	AGWindowServer *server = data;

	/* Only a v1/v2 server arrives here with nothing following: LINEAR is what the protocol assumes without a
	 * modifier event, and it is the one layout every driver can sample. */
	if (wl_proxy_get_version((struct wl_proxy *)dmabuf) < 3) {
		ag_dmabuf_record(server, format, AG_DRM_FORMAT_MOD_LINEAR);
	}
}

static void ag_dmabuf_modifier(void *data, struct zwp_linux_dmabuf_v1 *dmabuf, uint32_t format,
			       uint32_t modifier_hi, uint32_t modifier_lo)
{
	(void)dmabuf;
	ag_dmabuf_record(data, format, ((uint64_t)modifier_hi << 32) | (uint64_t)modifier_lo);
}

static const struct zwp_linux_dmabuf_v1_listener ag_dmabuf_listener = {
	ag_dmabuf_format,
	ag_dmabuf_modifier,
};

/* **LINEAR IF IT IS OFFERED, AND ONLY OTHERWISE THE FIRST PAIR.** A tiled modifier would be the faster allocation,
 * but LINEAR is the one this client can also map for CoreGraphics to draw into — the whole point of this path — and
 * choosing a tiled one would mean the CPU could no longer write the pixels it is about to hand over. */
static int ag_dmabuf_pick(AGWindowServer *server, uint32_t format, uint64_t *modifier)
{
	int i, found = 0;

	for (i = 0; i < server->dmabuf_format_count; i++) {
		if (server->dmabuf_formats[i].format != format) {
			continue;
		}
		if (!found || server->dmabuf_formats[i].modifier == AG_DRM_FORMAT_MOD_LINEAR) {
			*modifier = server->dmabuf_formats[i].modifier;
			found = 1;
		}
	}
	return found;
}

/* ONE DEVICE PER PROCESS, OPENED ON FIRST USE. The render node is the one a compositor samples from and the one
 * that does not need DRM master. */
static int ag_gbm_ready(AGWindowServer *server)
{
	static const char *const nodes[] = { "/dev/dri/renderD128", "/dev/dri/renderD129", "/dev/dri/card0" };
	size_t i;

	if (server->gbm != NULL) {
		return 1;
	}
	for (i = 0; i < sizeof nodes / sizeof nodes[0]; i++) {
		server->gbm_fd = open(nodes[i], O_RDWR | O_CLOEXEC);
		if (server->gbm_fd < 0) {
			continue;
		}
		server->gbm = gbm_create_device(server->gbm_fd);
		if (server->gbm != NULL) {
			return 1;
		}
		close(server->gbm_fd);
		server->gbm_fd = -1;
	}
	return 0;
}

/* **THE BUFFER THE WINDOW DRAWS INTO AND THE COMPOSITOR SAMPLES, AS ONE PIECE OF MEMORY.** This is the whole of the
 * client half: the mapping GBM hands back IS what `AGWindowBeginFrame` returns, so CoreGraphics rasterizes where the
 * GPU will read and the per-frame copy from a private backing store disappears. `-1` means "use shared memory", and
 * every failure below is that answer rather than an error — a client that refused to open a window because its GPU
 * path did not work would be worse than one that copies pixels. */
/* **CAN THE COMPOSITOR SAMPLE THIS PAIR?** The list came from `zwp_linux_dmabuf_v1`, and a buffer outside it is refused at
 * `create` time with no diagnosis — so an allocator that gets to choose the layout (the EGL one does) has to check. */
static int ag_dmabuf_pair_supported(AGWindowServer *server, uint32_t format, uint64_t modifier)
{
	int i;

	for (i = 0; i < server->dmabuf_format_count; i++) {
		if (server->dmabuf_formats[i].format == format &&
		    (server->dmabuf_formats[i].modifier == modifier || server->dmabuf_formats[i].modifier == 0)) {
			return 1;
		}
	}
	return 0;
}

static int ag_buffer_create_dmabuf(AGWindow *window, struct AGBuffer *slot, int width, int height)
{
	AGWindowServer *server = window->server;
	struct zwp_linux_buffer_params_v1 *params;
	struct gbm_bo *bo;
	uint32_t format = window->transparent ? AG_DRM_FORMAT_ARGB8888 : AG_DRM_FORMAT_XRGB8888;
	uint64_t modifier = AG_DRM_FORMAT_MOD_LINEAR;
	uint32_t stride = 0, offset;
	void *map, *map_data = NULL;
	int fd;

	if (server->dmabuf == NULL || server->dmabuf_format_count == 0) {
		return -1;
	}
	/* **A CLIENT THAT DRAWS WITH THE CPU BELONGS IN RAM, NOT IN DEVICE MEMORY, AND THAT IS NOW THE DEFAULT.** Every
	 * Agora client paints its frame with CoreGraphics into the pointer `AGWindowBeginFrame` hands back, and this
	 * mapping is the CPU's view of a GPU allocation: writing through it is ordinary speed, but READING IT BACK — which
	 * every blend, every antialiased edge and every glyph does — is an uncached round trip. MEASURED on this machine
	 * (nested x11, 1.332 scale), a destination read-modify-write through this mapping costs about 2.4 us a pixel
	 * against about 2 ns for the same access in shared memory, and the difference is the whole of one defect: the
	 * gallery window's 700x522 repaint took 150-215 ms with a GPU buffer and 21 ms with shm, at one repaint per
	 * scroller step. The compositor's GL renderer is the only half that gains from this path — it imports the buffer
	 * rather than uploading shm every frame — and an upload of one window is about a millisecond, so the trade is a
	 * hundredfold loss on the client for a millisecond gained on the server. The GPU buffer is therefore OPT-IN, for a
	 * client whose frames are UPLOADED rather than drawn: `AG_WINDOW_DMABUF=1` asks for it. This supersedes the old
	 * `AG_NO_DMABUF` escape hatch, which is what the default now says always. */
	{
		const char *want = getenv("AG_WINDOW_DMABUF");

		if (want == NULL || want[0] == '\0' || strcmp(want, "0") == 0) {
			return -1;
		}
	}
	if (getenv("AG_WINDOW_DIAG") != NULL) {
		fprintf(stderr, "  DIAG dmabuf: trying %dx%d, %d format(s) advertised\n",
			width, height, server->dmabuf_format_count);
	}
	/* **EGL FIRST, BECAUSE ITS BUFFERS ARE THE ONES THAT CAN BE RENDERED INTO.** See `AGBuffer.egl_texture`: this
	 * machine's GBM allocations are refused by the same device's EGL, so a window made of them cannot be drawn into with
	 * the GPU at all. The fallback is GBM, kept because a machine whose EGL cannot export still gets a GPU buffer the
	 * compositor can sample — it simply cannot be rendered into by EGL, which is what `AGWindowBeginFrameDMABUF`'s
	 * callers want and the ordinary CPU path does not need. */
#ifdef AG_HAVE_GL
	{
		/* **THE DEVICE HAS TO BE OPEN BEFORE THE CONTEXT CAN BE MADE ON IT**, and `ag_gbm_ready` is what opens it — the
		 * context uses the device as a device, not as an allocator, which is the whole distinction this path turns on. */
		(void)ag_gbm_ready(server);
		if (server->gl == NULL) {
			server->gl = AGGLContextCreateWithGBM(server->gbm != NULL ? (void *)server->gbm : NULL);
		}
		if (server->gl != NULL) {
			unsigned int texture = AGGLTextureAllocate(server->gl, width, height);
			int egl_fd = -1;
			int egl_stride = 0;
			unsigned int egl_fourcc = 0;
			unsigned long long egl_modifier = 0;

			if (texture == 0 && getenv("AG_WINDOW_DIAG") != NULL) {
				fprintf(stderr, "  DIAG dmabuf: the EGL texture could not be allocated\n");
			}
			if (texture != 0) {
				int exported = AGGLExportTextureDmabuf(server->gl, texture, width, height, &egl_fd,
								       &egl_stride, &egl_fourcc, &egl_modifier);

				if (getenv("AG_WINDOW_DIAG") != NULL) {
					fprintf(stderr, "  DIAG dmabuf: export=%d fourcc 0x%08x modifier 0x%016llx "
							"supported=%d\n", exported, egl_fourcc, (unsigned long long)egl_modifier,
						exported ? ag_dmabuf_pair_supported(server, egl_fourcc, egl_modifier) : -1);
				}
				if (exported && ag_dmabuf_pair_supported(server, egl_fourcc, egl_modifier)) {
					params = zwp_linux_dmabuf_v1_create_params(server->dmabuf);

					zwp_linux_buffer_params_v1_add(params, egl_fd, 0, 0, (uint32_t)egl_stride,
								       (uint32_t)(egl_modifier >> 32),
								       (uint32_t)egl_modifier);
					slot->buffer = zwp_linux_buffer_params_v1_create_immed(params, width, height,
											       egl_fourcc, 0);
					zwp_linux_buffer_params_v1_destroy(params);
					if (slot->buffer != NULL) {
						slot->egl_texture = texture;
						slot->fourcc = egl_fourcc;
						slot->modifier = egl_modifier;
						slot->dmabuf_fd = egl_fd;
						slot->width = width;
						slot->height = height;
						slot->stride = egl_stride;
						slot->size = (size_t)egl_stride * (size_t)height;
						/* `pixels` STAYS NULL, AND THAT IS THE POINT: this buffer's memory is not this
						 * process's to write through a pointer. A caller draws into it as a descriptor. */
						if (getenv("AG_WINDOW_DIAG") != NULL) {
							fprintf(stderr, "  DIAG dmabuf: egl %dx%d stride %d format 0x%08x "
									"modifier 0x%016llx\n", width, height, egl_stride,
								egl_fourcc, (unsigned long long)egl_modifier);
						}
						return 0;
					}
					close(egl_fd);
				}
				AGGLDeleteTexture(server->gl, texture);
			}
		}
		if (getenv("AG_WINDOW_DIAG") != NULL) {
			fprintf(stderr, "  DIAG dmabuf: the EGL allocation was not available (context %p), falling back to "
					"gbm\n", (void *)server->gl);
		}
	}
#endif

	if (!ag_dmabuf_pick(server, format, &modifier)) {
		return -1;
	}
	if (!ag_gbm_ready(server)) {
		return -1;
	}
	bo = gbm_bo_create_with_modifiers(server->gbm, (uint32_t)width, (uint32_t)height, format, &modifier, 1);
	if (bo == NULL) {
		return -1;
	}
	map = gbm_bo_map(bo, 0, 0, (uint32_t)width, (uint32_t)height,
			 GBM_BO_TRANSFER_READ | GBM_BO_TRANSFER_WRITE, &stride, &map_data);
	if (map == NULL || map == MAP_FAILED) {
		gbm_bo_destroy(bo);
		return -1;
	}
	fd = gbm_bo_get_fd(bo);
	if (fd < 0) {
		gbm_bo_unmap(bo, map_data);
		gbm_bo_destroy(bo);
		return -1;
	}
	offset = gbm_bo_get_offset(bo, 0);
	params = zwp_linux_dmabuf_v1_create_params(server->dmabuf);
	zwp_linux_buffer_params_v1_add(params, fd, 0, offset, stride,
				       (uint32_t)(modifier >> 32), (uint32_t)modifier);
	slot->buffer = zwp_linux_buffer_params_v1_create_immed(params, width, height, format, 0);
	zwp_linux_buffer_params_v1_destroy(params);
	if (slot->buffer == NULL) {
		close(fd);
		gbm_bo_unmap(bo, map_data);
		gbm_bo_destroy(bo);
		return -1;
	}
	slot->bo = bo;
	slot->map_data = map_data;
	slot->fourcc = format;
	slot->modifier = modifier;
	slot->dmabuf_fd = fd;	/* kept for DMA_BUF_IOCTL_SYNC; the params request dups its own */
	slot->pixels = map;
	slot->width = width;
	slot->height = height;
	slot->stride = (int)stride;
	slot->size = (size_t)stride * (size_t)height;
	slot->busy = 0;
	if (getenv("AG_WINDOW_DIAG") != NULL) {
		fprintf(stderr, "  DIAG dmabuf: %dx%d stride %u format 0x%08x modifier 0x%016llx\n",
			width, height, stride, format, (unsigned long long)modifier);
	}
	return 0;
}

/* **CPU WRITES HAVE TO BE VISIBLE BEFORE THE HANDOVER.** A GPU buffer is not ordinary memory: on an architecture
 * with a non-coherent mapping the writes sit in a cache until something flushes them, and the compositor would
 * sample a stale frame. `DMA_BUF_IOCTL_SYNC` is the protocol's own answer — START around the writes and END before
 * the commit — and a driver that does not need it answers the ioctl cheaply. */
static void ag_buffer_sync(struct AGBuffer *buffer, int start)
{
#ifdef __linux__
	if (buffer->bo != NULL && buffer->dmabuf_fd >= 0) {
		struct dma_buf_sync sync;

		memset(&sync, 0, sizeof sync);
		sync.flags = DMA_BUF_SYNC_WRITE | (start ? DMA_BUF_SYNC_START : DMA_BUF_SYNC_END);
		ioctl(buffer->dmabuf_fd, DMA_BUF_IOCTL_SYNC, &sync);
	}
#else
	(void)buffer;
	(void)start;
#endif
}

#else /* !AG_HAVE_DMABUF */

/* **CAN THE COMPOSITOR SAMPLE THIS PAIR?** The list came from `zwp_linux_dmabuf_v1`, and a buffer outside it is refused at
 * `create` time with no diagnosis — so an allocator that gets to choose the layout (the EGL one does) has to check. */
static int ag_dmabuf_pair_supported(AGWindowServer *server, uint32_t format, uint64_t modifier)
{
	int i;

	for (i = 0; i < server->dmabuf_format_count; i++) {
		if (server->dmabuf_formats[i].format == format &&
		    (server->dmabuf_formats[i].modifier == modifier || server->dmabuf_formats[i].modifier == 0)) {
			return 1;
		}
	}
	return 0;
}

static int ag_buffer_create_dmabuf(AGWindow *window, struct AGBuffer *slot, int width, int height)
{
	(void)window;
	(void)slot;
	(void)width;
	(void)height;
	return -1;
}

static void ag_buffer_sync(struct AGBuffer *buffer, int start)
{
	(void)buffer;
	(void)start;
}

#endif /* AG_HAVE_DMABUF */

static void ag_window_resize(AGWindow *window, int width, int height)
{
	/* **THE SIZE IS REMEMBERED WHATEVER HAPPENS, so a DEFERRED resize is not a lost one.** The window's own size
	 * is the record of what was asked for, and the drawing buffer's is what exists — the pair is the whole of the
	 * state a release needs to finish the job. */
	window->width = width;
	window->height = height;
	if (width <= 0 || height <= 0) {
		return;
	}
	/* **AND THIS MAKES THE DRAWING BUFFER, NEVER THE ONE ON THE GLASS.** The buffer the compositor is showing is
	 * not this process's to free — freeing it makes the surface have NO buffer at all, which the compositor draws
	 * as nothing and does not even hit-test; MEASURED, a window dragged by its edge FLICKERED for the whole drag
	 * when every resize freed the very buffer that was on screen. It also does not need remaking: it is replaced
	 * by the next `AGWindowEndFrame`, and the release that follows is when THIS slot — the one that was on the
	 * glass a moment ago — is made at the new size. */
	if (window->spare.busy) {
		if (getenv("AG_WINDOW_DIAG") != NULL) {
			fprintf(stderr, "  DIAG resize: DEFERRED to %dx%d (the drawing buffer %dx%d is still held)\n",
				width, height, window->spare.width, window->spare.height);
		}
		return;
	}
	if (window->spare.buffer != NULL) {
		double scale = window->scale > 0.0 ? window->scale : 1.0;
		int pixels_w = (int)((double)width * scale + 0.5);
		int pixels_h = (int)((double)height * scale + 0.5);

		if (window->spare.width == pixels_w && window->spare.height == pixels_h) {
			return;
		}
		ag_buffer_dispose(&window->spare);
	}
	if (ag_buffer_make(window, &window->spare, width, height) != 0) {
		/* A refused allocation leaves the slot empty, which `AGWindowBeginFrameSized` answers with a refused
		 * paint rather than a window that draws into nothing. */
		return;
	}
#ifdef AG_HAVE_DMABUF
	/* **AND THE OTHER SLOT IS MADE NOW, WHEN THE SLOT IS AN EGL BUFFER.** MEASURED: this machine's EGL exports a texture
	 * to a dma-buf happily, but refuses to export a SECOND one once the first buffer is being imported and rendered into
	 * by another context — so a lazily-made second slot fell back to GBM, whose buffers that same EGL then refused to
	 * import, and the whole point of the path was lost. Both slots are therefore allocated together, before either is
	 * drawn into, which is the arrangement the exports work in.
	 *
	 * The shared-memory path is untouched: its second slot is still made on the first swap, where it costs nothing. */
	if (window->spare.egl_texture != 0 && window->buffer.buffer == NULL) {
		if (ag_buffer_make(window, &window->buffer, width, height) != 0) {
			if (getenv("AG_WINDOW_DIAG") != NULL) {
				fprintf(stderr, "  DIAG resize: the second GPU slot could not be made; a swap will have to "
						"allocate later\n");
			}
		}
	}
#endif
}

/* **A RESIZE THAT WAS ASKED FOR UNDER A FRAME IS MADE HERE, ONCE THE DRAWING SLOT IS FREE.** There are two doors
 * into this and both matter: a release makes the slot free after a commit, and a window whose FIRST commit had
 * nothing to replace never gets a release at all — so the next `AGWindowBeginFrameSized` is the door that has to
 * look. MEASURED, without the second door: `tests/window.c` asked for 680x430 between two frames and went on
 * drawing 640-wide, because the only commit so far had no previous buffer to release. */
static void ag_window_apply_pending_resize(AGWindow *window)
{
	int width = window->width;
	int height = window->height;

	if (window->pending_width > 0) {
		width = window->pending_width;
		height = window->pending_height;
		window->pending_width = 0;
		window->pending_height = 0;
	}
	if (width != window->width || height != window->height ||
	    window->spare.width != width || window->spare.height != height) {
		ag_window_resize(window, width, height);
	}
}

/* **ONE BUFFER, MADE INTO WHICHEVER SLOT IS ASKED FOR.** It is the same allocation for the frame that is about to
 * be drawn and for the one that replaces it on the glass, because a swapchain's two halves are the same kind of
 * thing; what differs is only who owns them at a given moment, and that is `busy`. */
static int ag_buffer_make(AGWindow *window, struct AGBuffer *slot, int width, int height)
{
	/* **THE PARAMETERS ARE LOGICAL AND THE ALLOCATION IS NOT.** Every caller above this line thinks in points — the
	 * frame, the resize, the tests — so the multiplication happens exactly once, here, where pixels are made. It
	 * ROUNDS, because a point is 1/72 inch and 23 points at 57.97 dpi is 18.5 pixels: the client's buffer and the
	 * compositor's placement must agree on the integer that becomes, or the blit is a resample of a rounding error. */
	double scale = window->scale > 0.0 ? window->scale : 1.0;
	int stride;

	width = (int)((double)width * scale + 0.5);
	height = (int)((double)height * scale + 0.5);
	stride = width * 4;
	size_t size = (size_t)stride * (size_t)height;
	struct wl_shm_pool *pool;
	int fd;
	void *data;

	memset(slot, 0, sizeof *slot);
	/* **A GPU BUFFER IF THE COMPOSITOR CAN SAMPLE ONE, AND SHARED MEMORY OTHERWISE.** The choice is made per buffer
	 * rather than once at startup because the two paths differ only in how the pixels get made, and a compositor that
	 * stops offering the global — or a machine where GBM cannot open a device — must still get a window. */
	if (ag_buffer_create_dmabuf(window, slot, width, height) == 0) {
		wl_buffer_add_listener(slot->buffer, &buffer_listener, window);
		return 0;
	}
	fd = ag_create_shm_file(size);	if (fd < 0) {
		ag_server_error(window->server, "shm_open");
		return -1;
	}
	data = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		ag_server_error(window->server, "mmap");
		close(fd);
		return -1;
	}
	pool = wl_shm_create_pool(window->server->shm, fd, (int32_t)size);
	slot->buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride,
						 window->transparent ? WL_SHM_FORMAT_ARGB8888 : WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	if (slot->buffer == NULL) {
		munmap(data, size);
		return -1;
	}

	slot->pixels = data;
	slot->width = width;
	slot->height = height;
	slot->stride = stride;
	slot->size = size;
	slot->busy = 0;
	wl_buffer_add_listener(slot->buffer, &buffer_listener, window);
	return 0;
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


/* **THE SAME FRAME, HANDED OVER AS A DESCRIPTOR.** Everything above this door is shared with `AGWindowBeginFrameSized` —
 * the configured check, the spare slot, the resize that was asked for between frames — and the only difference is that a
 * GPU buffer's descriptor is what the caller gets instead of its mapping. That is why this is a separate door and not a
 * flag on the old one: the two return different KINDS of thing, and a caller that got the wrong one would either draw into
 * uncached memory or import a descriptor that does not exist. */
int AGWindowBeginFrameDMABUF(AGWindow *window, AGWindowFrameDMABUF *out)
{
	if (window == NULL || out == NULL || !window->configured) {
		return 0;
	}
	if (window->begun) {
		return 0;		/* a second frame cannot start inside the first */
	}
	if (window->spare.busy) {
		return 0;		/* the compositor still owns the drawing slot */
	}
	ag_window_apply_pending_resize(window);
	if (window->spare.buffer == NULL) {
		return 0;
	}
#ifdef AG_HAVE_DMABUF
	if (window->spare.dmabuf_fd < 0 || (window->spare.bo == NULL && window->spare.egl_texture == 0)) {
		/* Shared memory: this window was not asked for a GPU buffer, or the compositor imports nothing. The caller
		 * draws the ordinary way, which is why this is a return and not an error. */
		return 0;
	}
	out->fd = window->spare.dmabuf_fd;
	out->width = window->spare.width;
	out->height = window->spare.height;
	out->stride = window->spare.stride;
	/* **THE LAYOUT IS THE SLOT'S OWN RECORD**, not a guess from `transparent`: an EGL-exported buffer is ARGB8888 with a
	 * tiled modifier and no handle to ask afterwards. */
	out->fourcc = window->spare.fourcc;
	out->modifier = window->spare.modifier;
	window->begun = 1;
	window->begun_gpu = 1;
	return 1;
#else
	(void)out;
	return 0;			/* built without gbm: every window is shared memory */
#endif
}

void AGWindowCancelFrame(AGWindow *window)
{
	if (window == NULL || !window->begun) {
		return;
	}
	/* The slot was never attached to the surface, so giving it back is a flag and nothing else: the next BeginFrame
	 * finds it un-busy and draws into it, which is exactly the state a cancelled frame should leave behind. */
	window->begun = 0;
	window->begun_gpu = 0;
	window->damage_count = 0;
}
uint32_t *AGWindowBeginFrameSized(AGWindow *window, int *stride, int *width, int *height)
{
	if (window == NULL || !window->configured) {
		/* **AND THE REASON IS NAMED, BECAUSE A DIAGNOSTIC THAT GUESSES IS WORSE THAN NONE.** The window's draw
		 * used to report every refusal as "the compositor still holds its buffer" — WHICH WAS MY INTERPRETATION AND
		 * NOT THE CONDITION: this door refuses for three different reasons, and on a protocol with no configure the
		 * `configured` one is the one that fires. MEASURED, chasing the wrong two for two rounds. */
		if (getenv("APPKIT_DRAW_DIAG") != NULL) {
			fprintf(stderr, "  DIAG begin: refused — %s\n",
				window == NULL ? "no window"
				: "NOT CONFIGURED (and this protocol sends no configure)");
		}
		return NULL;
	}
	if (window->begun) {
		/* **A SECOND FRAME CANNOT START INSIDE THE FIRST.** A re-entrant handler is a caller that would be
		 * handed the same pixels while the outer one still intends to commit them — and the out-parameters are
		 * the buffer's, not the window's, so they are filled here too rather than left stale. */
		if (stride != NULL) {
			*stride = window->spare.stride;
		}
		if (width != NULL) {
			*width = window->spare.width;
		}
		if (height != NULL) {
			*height = window->spare.height;
		}
		return window->spare.pixels;
	}
	/* **THE FRAME IS DRAWN INTO THE BUFFER THE COMPOSITOR IS NOT SHOWING.** `buffer` is on the glass until the
	 * commit at the end of this frame replaces it, so painting there would put the repaint itself on the screen —
	 * the blink this swapchain exists for (see the top of this file). The slot is made on demand, at the window's
	 * own size, and a slot the compositor still holds is waited for rather than drawn into: the release is what
	 * makes it this process's again, and it arrives with the commit that replaced it. */
	if (window->spare.busy) {
		if (getenv("APPKIT_DRAW_DIAG") != NULL) {
			/* **THE RAW STATE, BECAUSE THE LABEL IS WHAT MISLED ME.** This branch's message sent two rounds into
			 * buffer lifetime; the numbers say which of the conditions is actually true, and a number cannot be
			 * misread the way a sentence can. */
			fprintf(stderr, "  DIAG begin: refused — frame_ready=%d busy=%d begun=%d configured=%d"
					" have_buffer=%d\n", window->frame_ready, window->spare.busy, window->begun,
				window->configured, window->spare.buffer != NULL);
		}
		return NULL;		/* the compositor still owns the drawing slot */
	}
	/* **A SIZE ASKED FOR BETWEEN FRAMES IS MADE HERE**, because the other door into it is a buffer release and a
	 * window's first commit never gets one — see `ag_window_apply_pending_resize`. */
	ag_window_apply_pending_resize(window);
	if (window->spare.buffer == NULL || window->spare.pixels == NULL) {
		/* **A WINDOW WITH NO PIXELS IS NOT A WINDOW TO DRAW ON.** The allocation refused — no shm file, no
		 * mapping — so this pass draws nothing and the next one asks again, which is the same answer a refused
		 * paint gives everywhere else. */
		if (getenv("APPKIT_DRAW_DIAG") != NULL) {
			fprintf(stderr, "  DIAG begin: refused — the drawing buffer could not be made (%dx%d)\n",
				window->width, window->height);
		}
		return NULL;
	}
	window->begun = 1;
	if (getenv("AG_WINDOW_DIAG") != NULL) {
		fprintf(stderr, "  DIAG frame: window %dx%d buffer %dx%d stride %d pixels %p%s\n",
			window->width, window->height, window->spare.width, window->spare.height,
			window->spare.stride, (void *)window->spare.pixels,
			window->spare.bo != NULL ? " (dmabuf)" : " (shm)");
	}
	/* **THE CPU'S WRITES BEGIN HERE.** See `ag_buffer_sync`: START before drawing and END at the commit is the pair
	 * a non-coherent mapping needs, and a shared-memory buffer makes both a no-op. */
	ag_buffer_sync(&window->spare, 1);
	if (stride != NULL) {
		*stride = window->spare.stride;
	}
	if (width != NULL) {
		*width = window->spare.width;
	}
	if (height != NULL) {
		*height = window->spare.height;
	}
	return window->spare.pixels;
}

uint32_t *AGWindowPreviousFrameSized(AGWindow *window, int *stride, int *width, int *height)
{
	if (window == NULL) {
		return NULL;
	}
	/* **A GPU BUFFER IS REFUSED, AND FOR TWO SEPARATE REASONS.** Its CPU reads are uncached — the same measurement
	 * that made shared memory the drawing default (see `ag_buffer_create_dmabuf`) — and its contents are only
	 * valid for the CPU after a `DMA_BUF_IOCTL_SYNC` read begin/end, which this door does not perform and must not
	 * perform behind a caller's back: a sync is a driver command with a cost, and a caller that is not going to read
	 * the pixels has no business paying it. A NULL here costs that caller a repaint and nothing else. */
	if (window->buffer.buffer == NULL || window->buffer.pixels == NULL || window->buffer.bo != NULL) {
		return NULL;
	}
	if (stride != NULL) {
		*stride = window->buffer.stride;
	}
	if (width != NULL) {
		*width = window->buffer.width;
	}
	if (height != NULL) {
		*height = window->buffer.height;
	}
	return window->buffer.pixels;
}

/* THE UNCHANGED DOOR, AND ITS THREE CALLERS KEEP IT.** The sized variant exists because the drawing surface IS the
 * frame now: CoreGraphics is told the buffer's own height, so a client that used the window's size instead would
 * write past the end of a buffer that had not caught up with a resize. */
uint32_t *AGWindowBeginFrame(AGWindow *window, int *stride)
{
	return AGWindowBeginFrameSized(window, stride, NULL, NULL);
}

void AGWindowDamage(AGWindow *window, int x, int y, int width, int height)
{
	if (window == NULL || !window->begun || width <= 0 || height <= 0) {
		return;
	}
	/* CLAMPED TO THE BUFFER HERE rather than at the commit: a caller working in device pixels can round outward past
	 * an edge, and a damage rectangle outside the surface is a protocol error (`wl_surface.damage_buffer` requires a
	 * non-empty region inside the buffer). */
	if (x < 0) {
		width += x;
		x = 0;
	}
	if (y < 0) {
		height += y;
		y = 0;
	}
	if (x + width > window->buffer.width) {
		width = window->buffer.width - x;
	}
	if (y + height > window->buffer.height) {
		height = window->buffer.height - y;
	}
	if (width <= 0 || height <= 0) {
		return;
	}
	if (window->damage_count < AG_WINDOW_DAMAGE_MAX) {
		window->damage[window->damage_count].x = x;
		window->damage[window->damage_count].y = y;
		window->damage[window->damage_count].w = width;
		window->damage[window->damage_count].h = height;
		window->damage_count++;
	} else {
		/* THE BUDGET IS FULL: the last slot grows to cover this one. Over-damage is a slower frame; a dropped
		 * rectangle is a stale pixel, and those are not the same mistake. */
		int *x0 = &window->damage[AG_WINDOW_DAMAGE_MAX - 1].x;
		int *y0 = &window->damage[AG_WINDOW_DAMAGE_MAX - 1].y;
		int *w0 = &window->damage[AG_WINDOW_DAMAGE_MAX - 1].w;
		int *h0 = &window->damage[AG_WINDOW_DAMAGE_MAX - 1].h;
		int right = (*x0 + *w0 > x + width) ? *x0 + *w0 : x + width;
		int bottom = (*y0 + *h0 > y + height) ? *y0 + *h0 : y + height;

		if (x < *x0) {
			*x0 = x;
		}
		if (y < *y0) {
			*y0 = y;
		}
		*w0 = right - *x0;
		*h0 = bottom - *y0;
	}
}

int AGWindowLastDamage(AGWindow *window, int index, int rect[4])
{
	if (window == NULL || index < 0 || index >= window->last_damage_count || rect == NULL) {
		return window != NULL ? window->last_damage_count : 0;
	}
	rect[0] = window->last_damage[index].x;
	rect[1] = window->last_damage[index].y;
	rect[2] = window->last_damage[index].w;
	rect[3] = window->last_damage[index].h;
	return window->last_damage_count;
}

void AGWindowEndFrame(AGWindow *window)
{
	struct AGBuffer drawn;

	if (window == NULL || !window->begun) {
		return;
	}
	/* **AND THE BUFFER IS DRAINED BEFORE A COMMIT IS QUEUED INTO IT.** This is where a frame becomes three or four
	 * requests, and the one place a burst can arrive while the buffer is still full — so it is the place that has to
	 * ask. A drain here is free when there is nothing to send and bounded when there is. */
	ag_flush_drain(window->server, 50);
	window->begun = 0;
	{
		int gpu_frame = window->begun_gpu;

		window->begun_gpu = 0;
		/* Captured before the swap below, and used after it: the buffer whose pixels were written by the GPU is the
		 * one being handed to the compositor, and it is `window->spare` until the swap makes it `window->buffer`. */
		if (gpu_frame) {
			window->gpu_frame_pending = 1;
		}
	}
	if (window->frame_cb == NULL) {
		/* REQUESTED BEFORE THE COMMIT IT IS MEANT TO FOLLOW, which is what the protocol requires. */
		window->frame_cb = wl_surface_frame(window->surface);
		wl_callback_add_listener(window->frame_cb, &frame_listener, window);
	}
	/* **THE FRAME JUST PAINTED BECOMES THE ONE ON THE GLASS, AND THE ONE THAT WAS BECOMES THE DRAWING SLOT.** The
	 * old one is not this process's yet: it stays `busy` until the compositor's release arrives, which it sends
	 * with THIS commit — the commit is what replaces it, and that is the moment the compositor has finished with
	 * it. Nothing is freed here; that pairing is what keeps a window from painting pixels the screen is showing. */
	drawn = window->spare;
	window->spare = window->buffer;
	window->buffer = drawn;
	window->buffer.busy = 1;
	/* **AND THE PIXELS LEAVE THIS PROCESS'S CACHE BEFORE THEY LEAVE THIS PROCESS.** The GPU may sample the buffer the
	 * moment the compositor sees the commit; END is what makes the writes in it visible. */
	if (window->gpu_frame_pending) {
		/* **A GPU FRAME IS FINISHED BY THE GPU, NOT BY A CACHE FLUSH.** The engine that wrote it called `glFinish`
		 * before the commit; `DMA_BUF_IOCTL_SYNC` here would be maintenance for a mapping nobody used. */
		window->gpu_frame_pending = 0;
	} else {
		ag_buffer_sync(&window->buffer, 0);
	}
	wl_surface_attach(window->surface, window->buffer.buffer, 0, 0);
	/* **WHAT THE CALLER SAID IT CHANGED, OR THE WHOLE BUFFER WHEN IT SAID NOTHING.** A caller that tracks its damage
	 * tells the compositor the rectangles it painted and the compositor blends only those; a caller that does not
	 * damages everything, which is what this door did for every frame before the rectangles existed. The rectangles
	 * are buffer pixels with a TOP-DOWN origin, which is what `wl_surface.damage_buffer` wants and what the client's
	 * own paint space is not (its windows are y-up), so the mirroring is the caller's to do. */
	window->last_damage_count = 0;
	if (window->damage_count == 0) {
		wl_surface_damage_buffer(window->surface, 0, 0, window->buffer.width, window->buffer.height);
		window->last_damage[0].x = 0;
		window->last_damage[0].y = 0;
		window->last_damage[0].w = window->buffer.width;
		window->last_damage[0].h = window->buffer.height;
		window->last_damage_count = 1;
	} else {
		int i;

		for (i = 0; i < window->damage_count && i < AG_WINDOW_DAMAGE_MAX; i++) {
			wl_surface_damage_buffer(window->surface, window->damage[i].x, window->damage[i].y,
						 window->damage[i].w, window->damage[i].h);
			window->last_damage[i] = window->damage[i];
		}
		window->last_damage_count = window->damage_count;
	}
	if (getenv("AG_WINDOW_DIAG") != NULL) {
		fprintf(stderr, "  DIAG commit: buffer=%p damage=%d size=%dx%d\n", (void *)window->buffer.buffer,
			window->last_damage_count, window->buffer.width, window->buffer.height);
	}
	window->damage_count = 0;
	wl_surface_commit(window->surface);
	/* WHEN THE CALLER CAME HERE FROM `AGWindowShow`, THE FLUSH ALREADY HAPPENED — before the frame was asked
	 * for and therefore before this commit. Flushing here means the frame just handed over does not wait for
	 * something else to push it out. */
	ag_flush_drain(window->server, 50);
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
	window->width = width;
	window->height = height;
	/* **THE DRAWING SLOT IS WHAT HAS TO MATCH THE CONFIGURED SIZE**, and `ag_window_resize` makes it when the
	 * compositor is not holding it — a window resized under a frame is made good on the release. */
	ag_window_resize(window, width, height);
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

/* **CANCELLING A REPEAT IS ONE ACT WITH SIX CALLERS, WHICH IS WHY IT IS ONE FUNCTION.** A held key must stop
 * repeating when it is released, when the keyboard focus moves away or the window is destroyed, when the keymap or
 * the seat's capabilities change, and when the connection goes away. Every one of those is a case where the key that
 * was repeating is no longer the key the user is holding — and a repeat that survives any of them types into
 * whatever came next. */
static void ag_repeat_cancel(AGWindowServer *server)
{
	server->repeat_active = 0;
	server->repeat_key = 0;
	server->repeat_due_ms = 0;
}

static void keyboard_keymap(void *data, struct wl_keyboard *keyboard, uint32_t format, int32_t fd,
			    uint32_t size)
{
	AGWindowServer *server = data;

	(void)keyboard;
	/* A NEW KEYMAP CHANGES WHAT EVERY HELD KEY MEANS, so the repeat stops rather than typing the new meaning of the
	 * old key code. */
	ag_repeat_cancel(server);
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
	/* THE TENURE BEGINS HERE, AND ONLY HERE. A repeat keeps the serial it was armed under, so a generated repeat is
	 * never mistaken for a press after a focus return. */
	server->focus_serial++;
	/* **AND A FOCUS CHANGE ENDS THE HELD KEY**, because the keys the compositor had down were released for us the
	 * moment it looked away — a repeat that continued would type into the window that now has the keyboard. */
	ag_repeat_cancel(server);
	/* **THE KEYBOARD IS THE ACTIVE STATE: the client that has it is the application in front**, which is what an
	 * application shows its menu bar for. */
	ag_server_set_active(server, server->keyboard_focus != NULL);
}

static void keyboard_leave(void *data, struct wl_keyboard *keyboard, uint32_t serial,
			   struct wl_surface *surface)
{
	AGWindowServer *server = data;

	(void)keyboard; (void)serial; (void)surface;
	ag_repeat_cancel(server);
	server->keyboard_focus = NULL;
	ag_server_set_active(server, 0);
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
	/* **THE ORIGIN OF THE TIMESTAMP, SAID OUT LOUD.** `wl_keyboard.key` carries the compositor's millisecond; a
	 * compositor that sends zero has told us nothing, and this process's clock is then the only time there is — a
	 * different fact, and one the caller has to be able to tell apart. */
	event.source_time_ms = time;
	event.has_source_time = (time != 0);
	event.focus_serial = server->focus_serial;
	event.keycode = key;
	event.pressed = state == WL_KEYBOARD_KEY_STATE_PRESSED;
	/* THE TRANSLATION IS UNCONDITIONAL, even on release: the caller may want the text of the key that went
	 * up, and the modifier mask is wanted either way. **AND SO IS THE KEYSYM**, for a stronger reason: a key that
	 * types nothing — an arrow, Home, an F key — has NO text to carry, so without this field the only thing a
	 * released arrow key says is which physical switch it was. */
	if (server->keyboard_state != NULL) {
		AGKeyboardTranslate(server->keyboard_state, key, event.text, sizeof event.text,
				    &event.modifiers);
		/* **AND THE SAME KEY WITH THE MODIFIERS OFF, BECAUSE A CONTROL CHARACTER DOES NOT NAME THE KEY.**
		 * `Ctrl+Shift+C` and `Ctrl+C` both type `0x03`, so the only thing that separates the copy shortcut from an
		 * interrupt is this string; a menu's key equivalent is matched against it and a terminal builds its
		 * modifier parameter from it. */
		AGKeyboardTranslateIgnoringModifiers(server->keyboard_state, key, event.text_plain,
						    sizeof event.text_plain, NULL);
		event.keysym = AGKeyboardKeysym(server->keyboard_state, key);
		event.modifier = AGKeyboardKeyIsModifier(server->keyboard_state, key);
	}
	ag_window_deliver(window, &event);
	/* **ARMING AND DISARMING, AFTER THE EVENT HAS GONE OUT.** A press arms the repeat with the event it produced —
	 * a repeat is that same keystroke again, so the characters and the modifiers are the ones the press had, not
	 * whatever the state is by the time it fires. A release cancels, and only for ITS OWN key: letting go of `a`
	 * while holding `shift` must not stop shift's own repeat (which its being a modifier prevents anyway) and, more
	 * to the point, releasing a key that is not the repeating one must not cancel it.
	 *
	 * THE KEYMAP GETS THE LAST WORD ON WHETHER A KEY REPEATS AT ALL: a modifier does not, and neither does a key the
	 * map gives no symbol to. */
	if (event.pressed) {
		if (server->repeat_rate > 0 && server->keyboard_state != NULL
		    && AGKeyboardKeyIsRepeatable(server->keyboard_state, key)) {
			server->repeat_active = 1;
			server->repeat_key = key;
			server->repeat_event = event;
			server->repeat_event.pressed = 1;
			server->repeat_event.repeat = 1;
			server->repeat_due_ms = ag_now_ms() + (uint32_t)server->repeat_delay;
		} else {
			ag_repeat_cancel(server);
		}
	} else if (server->repeat_active && server->repeat_key == key) {
		ag_repeat_cancel(server);
	}
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

/* **THE COMPOSITOR'S REPEAT POLICY, WHICH USED TO BE DROPPED ON THE FLOOR.** The event said nothing was listening:
 * `repeat_info` was an empty function, so a held key never repeated and no application could tell you why. A rate of
 * zero is a POLICY and not a missing value — it means "this seat does not repeat", and honouring it is what stops a
 * client from repeating where the session has said not to (an accessibility setting, or a compositor that synthesizes
 * repeats itself and would otherwise double them). */
static void keyboard_repeat_info(void *data, struct wl_keyboard *keyboard, int32_t rate, int32_t delay)
{
	AGWindowServer *server = data;

	(void)keyboard;
	server->repeat_rate = (rate > 0) ? rate : 0;
	server->repeat_delay = (delay > 0) ? delay : 0;
	if (server->repeat_rate == 0) {
		ag_repeat_cancel(server);
	}
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
	/* THE ABSOLUTE POSITION THE COMPOSITOR LAST SENT FOR THIS WINDOW, attached so the two travel together. */
	if (server->pointer_focus != NULL && server->pointer_focus->has_global) {
		event.global_x = server->pointer_focus->global_x;
		event.global_y = server->pointer_focus->global_y;
		event.has_global = 1;
	}
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
	/* AND WITH A BUTTON TOO, because a drag's GRAB POINT is a press. */
	if (server->pointer_focus != NULL && server->pointer_focus->has_global) {
		event.global_x = server->pointer_focus->global_x;
		event.global_y = server->pointer_focus->global_y;
		event.has_global = 1;
	}
	ag_window_deliver(server->pointer_focus, &event);

	/* **WHEN THE CLIENT ACTUALLY READ THE BUTTON.** The compositor stamps a press when it FORWARDS one; this
	 * stamps it when this client's socket delivered it, so the gap between the two is the transport and the gap
	 * between THIS and the view's `-mouseDown:` is the client's own queue. MEASURED once: 3302 ms from the
	 * compositor to the view with the run loop turning at 58 passes a second — a delay that has to live in one of
	 * those two halves, and this line is what tells them apart. */
	if (getenv("APPKIT_MENU_DIAG") != NULL) {
		struct timespec ts;

		clock_gettime(CLOCK_REALTIME, &ts);
		fprintf(stderr, "  DIAG platform %lld: button %u %s at (%d,%d)\n",
			(long long)ts.tv_sec * 1000LL + (long long)(ts.tv_nsec / 1000000L),
			(unsigned)button, event.pressed ? "pressed" : "released", event.x, event.y);
	}
}

/* **THE WHEEL ARRIVES IN PIECES AND IS DELIVERED AS A GESTURE.** `axis` is one axis of the motion, `axis_source`
 * says where it came from (once per frame, before the axes), and `frame` closes the batch. Nothing is delivered until
 * the frame, which is what makes a two-axis trackpad gesture one delivery instead of two unrelated ones — and what
 * keeps a client from acting on half a gesture. */
static void pointer_axis(void *data, struct wl_pointer *pointer, uint32_t time, uint32_t axis, wl_fixed_t value)
{
	AGWindowServer *server = data;

	(void)pointer; (void)time;
	if (axis == 0) {	/* WL_POINTER_AXIS_VERTICAL_SCROLL */
		server->axis.vertical += wl_fixed_to_double(value);
		server->axis.have_vertical = 1;
	} else {
		server->axis.horizontal += wl_fixed_to_double(value);
		server->axis.have_horizontal = 1;
	}
}

static void pointer_frame(void *data, struct wl_pointer *pointer)
{
	AGWindowServer *server = data;
	AGEvent event;

	(void)pointer;
	if (!server->axis.have_vertical && !server->axis.have_horizontal) {
		return;		/* a frame around motion or a button: nothing of the wheel's to deliver */
	}
	/* **THE TWO AXES ARE TWO EVENTS AND THEY CARRY THE SAME GESTURE'S NUMBERS.** A client's scroll handler takes one
	 * axis at a time — that is what `-deltaX` and `-deltaY` are — so a single event carrying both would have to pick
	 * a meaning for each accessor. */
	if (server->axis.have_vertical) {
		memset(&event, 0, sizeof event);
		event.type = AGEventPointerAxis;
		event.axis = AGAxisVertical;
		event.delta = server->axis.vertical;
		event.source = server->axis.source;
		event.discrete = server->axis.vertical_discrete;
		event.value120 = server->axis.vertical120;
		event.has_discrete = server->axis.have_discrete;
		/* **THE MODIFIERS, WHICH IS WHAT MAKES SHIFT-SCROLL AN APPLICATION'S DECISION.** `wl_pointer.axis` carries
		 * no modifier state — the protocol keeps modifiers on the KEYBOARD — so a client that wanted to turn Shift
		 * plus a vertical wheel into a horizontal scroll had nothing to test. The state is this client's own, from
		 * the compositor's `wl_keyboard.modifiers`, which is the same source every other event's flags come from. */
		event.modifiers = (server->keyboard_state != NULL)
			? AGKeyboardModifiers(server->keyboard_state) : 0;
		event.x = server->pointer_x;
		event.y = server->pointer_y;
		ag_window_deliver(server->pointer_focus, &event);
	}
	if (server->axis.have_horizontal) {
		memset(&event, 0, sizeof event);
		event.type = AGEventPointerAxis;
		event.axis = AGAxisHorizontal;
		event.delta = server->axis.horizontal;
		event.source = server->axis.source;
		event.discrete = server->axis.horizontal_discrete;
		event.value120 = server->axis.horizontal120;
		event.has_discrete = server->axis.have_discrete;
		event.modifiers = (server->keyboard_state != NULL)
			? AGKeyboardModifiers(server->keyboard_state) : 0;
		event.x = server->pointer_x;
		event.y = server->pointer_y;
		ag_window_deliver(server->pointer_focus, &event);
	}
	memset(&server->axis, 0, sizeof server->axis);
}

static void pointer_axis_source(void *data, struct wl_pointer *pointer, uint32_t source)
{
	AGWindowServer *server = data;

	(void)pointer;
	/* **ONCE PER FRAME, BEFORE THE AXES IT DESCRIBES** — which is the order the protocol states and the order the
	 * server sends. It is remembered rather than passed on immediately because the axes have not arrived yet. */
	server->axis.source = source;
}

static void pointer_axis_stop(void *data, struct wl_pointer *pointer, uint32_t time, uint32_t axis)
{
	(void)data; (void)pointer; (void)time; (void)axis;
}

/* **THE STEPS, WHICH ARE THE SAME MOTION SAID IN WHOLE NOTCHES.** A client bound at version 5-7 is sent
 * `axis_discrete`; at 8 and later, `axis_value120`. Only one of the two ever arrives, which is the server's job (see
 * `aws_seat_pointer_axis`), and this side simply records whichever came. The COUNT is kept apart from the distance
 * because they are not to be added together — the distance is the motion and the count is how many clicks it looked
 * like. */
static void pointer_axis_discrete(void *data, struct wl_pointer *pointer, uint32_t axis, int32_t discrete)
{
	AGWindowServer *server = data;

	(void)pointer;
	if (axis == 0) {
		server->axis.vertical_discrete += discrete;
	} else {
		server->axis.horizontal_discrete += discrete;
	}
	server->axis.have_discrete = 1;
}

static void pointer_axis_value120(void *data, struct wl_pointer *pointer, uint32_t axis, int32_t value120)
{
	AGWindowServer *server = data;

	(void)pointer;
	if (axis == 0) {
		server->axis.vertical120 += value120;
		/* A HIGH-RESOLUTION WHEEL MOVES IN FRACTIONS OF A NOTCH, so the whole-step count is derived and only
		 * when a whole one has been completed — 120ths below that are motion without a click. */
		server->axis.vertical_discrete = value120 / 120;
	} else {
		server->axis.horizontal120 += value120;
		server->axis.horizontal_discrete = value120 / 120;
	}
	server->axis.have_discrete = 1;
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
		/* **A SEAT THAT STOPS ADVERTISING A KEYBOARD ENDS THE HELD KEY**, for the same reason losing the focus
		 * does: the object that would have carried the release is being destroyed, so no release is coming. */
		ag_repeat_cancel(server);
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

/* **THE SCALE A WINDOW IS DRAWN AT, SENT THE WAY THIS COMPOSITOR UNDERSTANDS.** A server that speaks
 * `agora_window.set_buffer_scale_fixed` takes the real fraction, so the buffer is rasterised on the device grid and
 * placed 1:1; an older one (or a stock compositor) takes the rounded-up integer and resamples. The window object's
 * version is the test, because the request is `since="9"` and Wayland gives a child the parent's version. */
static void ag_window_send_scale(AGWindow *window)
{
	double scale;

	if (window == NULL || window->surface == NULL) {
		return;
	}
	scale = window->scale > 0.0 ? window->scale : 1.0;
	if (window->agora != NULL && agora_window_get_version(window->agora) >= 9) {
		agora_window_set_buffer_scale_fixed(window->agora, wl_fixed_from_double(scale));
	} else if (scale > 1.0) {
		wl_surface_set_buffer_scale(window->surface, (int32_t)(scale + 0.5));
	}
}

/* **"THIS SCREEN IS HiDPI", AND THE CLIENT'S HALF OF IT IS TO RENDER AT THAT RESOLUTION.** The factor is device pixels
 * per logical pixel: at 2, a 640x400 window is a 1280x800 buffer that the compositor places as 640x400. A client that
 * ignored this would still be the right SIZE — the compositor upscales — but every glyph would be drawn at half the
 * resolution the screen has, which is the difference between HiDPI and a magnifying glass.
 *
 * **IT IS THE FALLBACK NOW, NOT THE ANSWER.** `agora_output.preferred_scale` carries the display's real fraction and
 * arrives later in the connection; once it has, this integer ceiling is ignored rather than allowed to overwrite it.
 *
 * A TIGHTER FACTOR MAY ARRIVE WITH A TIGHTER WINDOW: the compositor sends it when the output is bound, which is before
 * this process has made a surface, but the protocol allows a change and the surfaces under it have to follow. */
static void output_scale(void *data, struct wl_output *output, int32_t factor)
{
	AGWindowServer *server = data;
	AGWindow *window;

	(void)output;
	if (server->have_fractional_scale) {
		return;
	}
	server->scale = (factor > 0) ? (double)factor : 1.0;
	for (window = server->windows; window != NULL; window = window->next) {
		if (window->scale != server->scale) {
			/* THE NEXT BUFFER IS THE ONE THAT MOVES: the buffer on the glass is not ours to free, and the one being
			 * drawn into is disposed here so that `AGWindowBeginFrameSized` rebuilds it at the new factor. */
			window->scale = server->scale;
			if (!window->spare.busy && window->spare.buffer != NULL) {
				ag_buffer_dispose(&window->spare);
			}
			ag_window_send_scale(window);
		}
	}
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

/* **THE REAL SCALE, WHICH IS THE WHOLE POINT OF `preferred_scale`.** The integer `wl_output.scale` can only say 2 for
 * a 1.333 output, and a client that renders at 2 is then resampled by the compositor — the soft picture this event
 * exists to remove. Here the client is told 1.333 (quantised to the 1/256 the wire carries), sizes its buffers at
 * `round(points * scale)`, and declares that same fraction back with `set_buffer_scale_fixed`; the compositor places
 * the result 1:1. */
static void agora_output_preferred_scale(void *data, struct agora_output *output, wl_fixed_t scale)
{
	AGWindowServer *server = data;
	AGWindow *window;
	double value = wl_fixed_to_double(scale);

	(void)output;
	if (!(value > 0.0)) {
		return;
	}
	server->scale = value;
	server->have_fractional_scale = 1;
	for (window = server->windows; window != NULL; window = window->next) {
		if (window->scale == value) {
			continue;
		}
		/* The drawing buffer is rebuilt at the new factor; the one on the glass is not ours to free. */
		window->scale = value;
		if (!window->spare.busy && window->spare.buffer != NULL) {
			ag_buffer_dispose(&window->spare);
		}
		ag_window_send_scale(window);
	}
}

static const struct agora_output_listener agora_output_listener = {
	/* **IN THE PROTOCOL'S OWN ORDER, WHICH IS WHAT A POSITIONAL INITIALISER MEANS.** `work_area`, `menu_bar_area` and
	 * `preferred_scale` (since version 2) are declared in that order, so these lines cannot be swapped — MEASURED:
	 * swapped, a client reads the bar's region as the work area and vice versa, and every consequence of that looks
	 * like the SERVER lying rather than like a struct in the wrong order. Every slot is filled because every event is
	 * sent: libwayland aborts on a NULL one. */
	agora_output_work_area,
	agora_output_menu_bar_area,
	agora_output_preferred_scale,
};

/* ============================================================================================ *
 * THE WINDOW'S OWN EVENTS, which are per-window where the output's are per-screen.               *
 *                                                                                                *
 * **THE POINTER'S ABSOLUTE POSITION IS THE ONE THAT MATTERS HERE.** See the protocol's            *
 * `pointer_global`: a title-bar drag MOVES the window, so the surface-relative `wl_pointer.motion`  *
 * becomes a moving target, and a client that used it drifted — MEASURED, a fast drag put the window *
 * hundreds of pixels past the pointer. The absolute position is kept on the window and attached to  *
 * the AGEvent the relative motion becomes, so the two travel together.                              *
 * ============================================================================================ */
static void agora_window_close(void *data, struct agora_window *window)
{
	AGWindow *w = data;
	AGEvent event;

	(void)window;
	memset(&event, 0, sizeof event);
	event.type = AGEventClose;
	ag_window_deliver(w, &event);
}

static void agora_window_work_area_changed(void *data, struct agora_window *window, int32_t x, int32_t y,
					   int32_t width, int32_t height)
{
	/* THE PER-WINDOW FORM OF WHAT THE OUTPUT'S `work_area` ALREADY SAID. The seam reads the OUTPUT's, because the
	 * work area is a property of the screen and the client constrains itself against it; this copy is the same
	 * answer and there is nothing to do with it here. */
	(void)data; (void)window; (void)x; (void)y; (void)width; (void)height;
}

static void agora_window_pointer_global(void *data, struct agora_window *window, int32_t x, int32_t y)
{
	AGWindow *w = data;

	(void)window;
	w->global_x = (int)x;
	w->global_y = (int)y;
	w->has_global = 1;
}

/* **THE SHELL ASKING FOR A WINDOW, WHICH IS THE ANSWER A DOCK CLICK NEEDS WHEN THERE IS NOTHING TO RAISE.** It is
 * delivered as an event rather than acted on here because what opens is the application's decision: the AppKit
 * turns it into its delegate's `-applicationShouldHandleReopen:hasVisibleWindows:` and nothing in this seam knows
 * what a window means to the program that owns it. */
static void agora_window_reopen(void *data, struct agora_window *window)
{
	AGWindow *w = data;
	AGEvent event;

	(void)window;
	memset(&event, 0, sizeof event);
	event.type = AGEventReopen;
	ag_window_deliver(w, &event);
}

/* **AND A SHELL ASKING FOR THIS APPLICATION'S DOCK MENU.** The answer is the application's — its delegate's
 * `-applicationDockMenu:` — so this hands the question up and says nothing itself; `AGWindowSetDockMenu` is the way
 * back. The AppKit answers from its own window-level handler, which is why the seam has no opinion here. */
static void agora_window_dock_menu_requested(void *data, struct agora_window *window)
{
	AGWindow *w = data;

	(void)window;
	if (w->dock_menu_request_fn != NULL) {
		w->dock_menu_request_fn(w->dock_menu_context, w);
	}
}

/* **AND THE PERSON CHOSE ONE OF THE ITEMS IT PUBLISHED.** The id is the one the application gave the item when it
 * answered, and turning it back into an object is the application's job for the same reason the menu was. */
static void agora_window_dock_menu_action(void *data, struct agora_window *window, int32_t item)
{
	AGWindow *w = data;

	(void)window;
	if (w->dock_menu_action_fn != NULL) {
		w->dock_menu_action_fn(w->dock_menu_context, w, (int)item);
	}
}

static const struct agora_window_listener agora_window_listener = {
	/* IN THE PROTOCOL'S OWN ORDER: `close`, `work_area_changed`, `pointer_global`, `reopen`,
	 * `dock_menu_requested`, `dock_menu_action`. */
	agora_window_close,
	agora_window_work_area_changed,
	agora_window_pointer_global,
	agora_window_reopen,
	agora_window_dock_menu_requested,
	agora_window_dock_menu_action,
};

/* ============================================================================================ *
 * THE WINDOW LIST, WHICH ONLY A SHELL COMPONENT ASKS FOR.                                              *
 * ============================================================================================ */
static void window_list_begin(void *data, struct agora_window_list *list)
{
	AGWindowServer *server = data;

	(void)list;
	server->list_count = 0;
	server->list_in_snapshot = 1;
}

static void window_list_window(void *data, struct agora_window_list *list, uint32_t id, const char *app_id,
			       const char *title, int32_t level, int32_t visible, int32_t active)
{
	AGWindowServer *server = data;
	AGWindowInfo *info;

	(void)list;
	if (server->list_count >= AG_WINDOW_LIST_MAX) {
		return;	/* truncated rather than allocated: see the header's note on the cap */
	}
	info = &server->list_rows[server->list_count++];
	info->id = id;
	snprintf(info->app_id, sizeof info->app_id, "%s", app_id != NULL ? app_id : "");
	snprintf(info->title, sizeof info->title, "%s", title != NULL ? title : "");
	info->level = (int)level;
	info->visible = (int)visible;
	info->active = (int)active;
}

static void window_list_done(void *data, struct agora_window_list *list)
{
	AGWindowServer *server = data;

	(void)list;
	server->list_in_snapshot = 0;
	/* **THE CALLBACK SEES A FINISHED SNAPSHOT AND NOT A STREAM.** A row that arrives without its `done` is a
	 * list that has not been told everything yet, and drawing it would make a window flicker out and back. */
	if (server->list_fn != NULL) {
		server->list_fn(server->list_context, server->list_rows, server->list_count);
	}
}

/* **THE BADGE ARRIVES BESIDE ITS WINDOW**, in its own event, so the row it belongs to is already in the snapshot; the id
 * is what pairs them, and a list that predates version 2 simply never gets the event. */
static void window_list_badge(void *data, struct agora_window_list *list, uint32_t id, const char *badge)
{
	AGWindowServer *server = data;
	int i;

	(void)list;
	for (i = 0; i < server->list_count; i++) {
		if (server->list_rows[i].id == id) {
			snprintf(server->list_rows[i].badge, sizeof server->list_rows[i].badge, "%s",
				 badge != NULL ? badge : "");
			return;
		}
	}
}

static const struct agora_window_list_listener window_list_listener = {
	window_list_begin,
	window_list_window,
	window_list_badge,
	window_list_done,
};

void AGWindowListSetHandler(AGWindowServer *server, AGWindowListFunction function, void *context)
{
	if (server == NULL) {
		return;
	}
	server->list_fn = function;
	server->list_context = context;
	if (function == NULL || server->shell == NULL) {
		return;
	}
	/* **ASKED FOR THE FIRST TIME HERE, AND ONLY HERE.** The snapshot is re-sent on every window change, so a client
	 * that never asks must not be sent one — which is every application. `get_window_list` is a version 3 request,
	 * so a compositor that speaks an older Agora protocol simply never answers, which is the same silence every
	 * other door this seam lacks has. */
	if (server->window_list == NULL) {
		if (wl_proxy_get_version((struct wl_proxy *)server->shell) < 3) {
			return;
		}
		server->window_list = agora_shell_get_window_list(server->shell);
		agora_window_list_add_listener(server->window_list, &window_list_listener, server);
	}
	wl_display_flush(server->display);
}

const AGWindowInfo *AGWindowListRows(AGWindowServer *server, int *count)
{
	if (server == NULL) {
		if (count != NULL) {
			*count = 0;
		}
		return NULL;
	}
	if (count != NULL) {
		*count = server->list_count;
	}
	return (server->list_count > 0) ? server->list_rows : NULL;
}

int AGWindowSetDockBadge(AGWindowServer *server, unsigned int id, const char *label)
{
	AGWindow *window;
	const char *app_id = NULL;
	int i;

	if (server == NULL || server->shell == NULL || id == 0) {
		return 0;
	}
	if (wl_proxy_get_version((struct wl_proxy *)server->shell) < 8) {
		return 0;	/* an older compositor has no set_badge; nothing to report */
	}
	/* **THE ID IS THE SERVER'S, SO THE SNAPSHOT IS WHERE IT MEANS SOMETHING.** The row names the application, and the
	 * application is what the badge belongs to; any window of it can carry the request. */
	for (i = 0; i < server->list_count; i++) {
		if (server->list_rows[i].id == id) {
			app_id = server->list_rows[i].app_id;
			break;
		}
	}
	if (app_id == NULL) {
		return 0;
	}
	for (window = server->windows; window != NULL; window = window->next) {
		if (window->agora != NULL && strcmp(window->app_id, app_id) == 0 &&
		    wl_proxy_get_version((struct wl_proxy *)window->agora) >= 8) {
			agora_window_set_badge(window->agora, label != NULL ? label : "");
			return 1;
		}
	}
	return 0;
}

void AGWindowActivate(AGWindowServer *server, unsigned int id)
{
	if (server == NULL || server->shell == NULL) {
		return;
	}
	if (wl_proxy_get_version((struct wl_proxy *)server->shell) < 3) {
		return;
	}
	agora_shell_activate_window(server->shell, id);
	wl_display_flush(server->display);
}

void AGWindowRequestClose(AGWindowServer *server, unsigned int id)
{
	if (server == NULL || server->shell == NULL) {
		return;
	}
	if (wl_proxy_get_version((struct wl_proxy *)server->shell) < 3) {
		return;
	}
	agora_shell_close_window(server->shell, id);
	wl_display_flush(server->display);
}

/* **THE REOPEN DOOR IS VERSION 5, AND A SHELL AT 4 SIMPLY NEVER HEARS IT.** `activate_window` and `close_window`
 * moved a window that already existed; this one asks an application to make another, which is `reopen_window` and
 * nothing older. */
void AGWindowReopen(AGWindowServer *server, unsigned int id)
{
	if (server == NULL || server->shell == NULL) {
		return;
	}
	if (wl_proxy_get_version((struct wl_proxy *)server->shell) < 5) {
		return;
	}
	agora_shell_reopen_window(server->shell, id);
	wl_display_flush(server->display);
}

/* ============================================================================================ *
 * A DOCK TILE'S MENU, FROM THE ASKING SIDE.
 *                                                                                                *
 * **THE ANSWER IS DELIVERED INSIDE THE DISPATCH THAT BROUGHT IT**, and the proxy is destroyed     *
 * before the handler runs — so a caller can wait for it with a plain loop that dispatches until   *
 * its own flag flips, which is what a right-click does: it cannot return to a run loop it is not *
 * in. The alternative, a queue of answers, would be a buffer for a question that is already       *
 * answered by the time the next frame is drawn.
 * ============================================================================================ */
static void dock_menu_menu(void *data, struct agora_dock_menu *object, const char *app_id, const char *menu)
{
	AGWindowServer *server = data;
	AGDockMenuFunction fn = server->dock_menu_fn;
	void *context = server->dock_menu_context;

	/* THE QUESTION IS OVER, WHATEVER THE CALLER DOES WITH THE ANSWER: the proxy goes now, so a second dispatch cannot
	 * deliver a second menu and a caller that forgets to cancel leaves nothing outstanding. */
	if (server->dock_menu == object) {
		agora_dock_menu_destroy(object);
		server->dock_menu = NULL;
	}
	if (fn != NULL) {
		fn(context, app_id != NULL ? app_id : "", menu != NULL ? menu : "");
	}
}

static const struct agora_dock_menu_listener dock_menu_listener = {
	dock_menu_menu,
};

void AGWindowServerSetDockMenuHandler(AGWindowServer *server, AGDockMenuFunction function, void *context)
{
	if (server == NULL) {
		return;
	}
	server->dock_menu_fn = function;
	server->dock_menu_context = context;
}

int AGWindowRequestDockMenu(AGWindowServer *server, unsigned int id)
{
	struct agora_dock_menu *menu;

	if (server == NULL || server->shell == NULL) {
		return 0;
	}
	/* **THE SHELL'S VERSION IS THE CAP, SO ASK FOR THE DOOR THAT EXISTS.** `get_dock_menu` is version 6; a
	 * compositor that speaks an older Agora protocol never answers, which is the silence every other door this seam
	 * lacks has — and it is reported here rather than waited out, because a right-click with nothing to wait for
	 * should show the Dock's own items now. */
	if (wl_proxy_get_version((struct wl_proxy *)server->shell) < 6) {
		return 0;
	}
	/* ONE QUESTION AT A TIME: a dock has one menu open, so an earlier ask is abandoned rather than queued. */
	AGWindowCancelDockMenu(server);
	menu = agora_shell_get_dock_menu(server->shell, id);
	if (menu == NULL) {
		return 0;
	}
	server->dock_menu = menu;
	agora_dock_menu_add_listener(menu, &dock_menu_listener, server);
	wl_display_flush(server->display);
	return 1;
}

void AGWindowCancelDockMenu(AGWindowServer *server)
{
	if (server == NULL || server->dock_menu == NULL) {
		return;
	}
	/* A DESTRUCTOR, AND THE SERVER FORGETS THE QUESTION WITH IT — so a timeout costs one round trip's worth of
	 * server state and nothing else. */
	agora_dock_menu_destroy(server->dock_menu);
	server->dock_menu = NULL;
	wl_display_flush(server->display);
}

void AGWindowActivateDockMenuItem(AGWindowServer *server, unsigned int id, int item)
{
	if (server == NULL || server->shell == NULL) {
		return;
	}
	if (wl_proxy_get_version((struct wl_proxy *)server->shell) < 6) {
		return;
	}
	agora_shell_dock_menu_action(server->shell, id, (int32_t)item);
	wl_display_flush(server->display);
}

void AGWindowSetDockMenuHandlers(AGWindow *window, AGDockMenuRequestFunction request,
				 AGDockMenuActionFunction action, void *context)
{
	if (window == NULL) {
		return;
	}
	window->dock_menu_request_fn = request;
	window->dock_menu_action_fn = action;
	window->dock_menu_context = context;
}

void AGWindowSetDockMenu(AGWindow *window, const char *menu)
{
	if (window == NULL || window->agora == NULL) {
		return;
	}
	if (wl_proxy_get_version((struct wl_proxy *)window->agora) < 6) {
		return;
	}
	agora_window_set_dock_menu(window->agora, menu != NULL ? menu : "");
	wl_display_flush(window->server->display);
}

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
#ifdef AG_HAVE_DMABUF
	} else if (strcmp(interface, zwp_linux_dmabuf_v1_interface.name) == 0) {
		/* **v3 IS THE FLAT LIST, AND THIS CLIENT NEEDS NOTHING MORE.** v4's feedback answers "which device and
		 * which modifiers are fast" — a multi-GPU question; a client on one GPU needs the list, and binding low
		 * enough to be understood is better than asking for events a server may not send. */
		server->dmabuf = wl_registry_bind(registry, name, &zwp_linux_dmabuf_v1_interface,
						 version < 3 ? version : 3);
		zwp_linux_dmabuf_v1_add_listener(server->dmabuf, &ag_dmabuf_listener, server);
#endif
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
		 * `AGWindowServerWorkArea` and through its frame being recorded rather than obeyed.
		 *
		 * **ASKED FOR AT THE HIGHEST VERSION THIS SEAM UNDERSTANDS, CAPPED BY THE COMPOSITOR'S.** The shell's own
		 * requests matter now: `get_window_list`, `activate_window` and `close_window` arrived in 3, `set_activatable`
		 * rides shell 4, `reopen_window` arrived in 5, and `get_dock_menu` and `dock_menu_action` arrived in 6 — and
		 * a window made from a shell bound at 2 is a version 2 window whose `set_reserved` is the last thing it has. */
		/* **NINE IS WHERE THE FRACTIONAL SCALE IS.** Below it the shell is bound at what the compositor offers and
		 * windows keep the integer `wl_output.scale` path — a little soft on a fractional output, but correct. The
		 * clipboard's seven and the fractional scale's nine are the two older fences this seam knows about, **TEN IS THE
		 * SHEET'S** (below it a window has no way to say it hangs from another window's title bar and a sheet is drawn as
		 * the rectangle it is), and **ELEVEN IS THE POINTER'S SHAPE**: below it there is no `set_cursor`, so every window
		 * shows the compositor's default. Asking for exactly what this seam understands matters here for the same reason
		 * it does at nine: the version a shell is bound at is the version every window it makes is capped to, and a
		 * request sent above it is a protocol error that kills the client rather than a call the server ignores. */
		server->shell = wl_registry_bind(registry, name, &agora_shell_interface,
						version < 11 ? version : 11);
	}
}

/* ==================================================================================================
 * THE SELECTION — five events, five calls, and every descriptor handed straight on.
 * ================================================================================================== */

static void selection_offer(void *data, struct agora_shell *shell, const char *mime_type)
{
	AGWindowServer *server = data;

	(void)shell;
	if (server->selection.offer != NULL) {
		server->selection.offer(server->selection.context, mime_type);
	}
}

static void selection_lost(void *data, struct agora_shell *shell)
{
	AGWindowServer *server = data;

	(void)shell;
	if (server->selection.lost != NULL) {
		server->selection.lost(server->selection.context);
	}
}

/* **AND THE DESCRIPTOR GOES TO THE HANDLER, WHICH OWNS IT.** Closing it here would leave the owner writing into a pipe
 * nobody is reading, and would make the handover a copy the seam had to manage. */
static void selection_requested(void *data, struct agora_shell *shell, const char *mime_type, int32_t fd)
{
	AGWindowServer *server = data;

	(void)shell;
	if (server->selection.requested != NULL) {
		server->selection.requested(server->selection.context, mime_type, (int)fd);
		return;
	}
	close(fd);	/* nobody wanted it, so it is ours to close */
}

static void selection_sent(void *data, struct agora_shell *shell, const char *mime_type, int32_t fd)
{
	AGWindowServer *server = data;

	(void)shell;
	if (server->selection.sent != NULL) {
		server->selection.sent(server->selection.context, mime_type, (int)fd);
		return;
	}
	close(fd);
}

static void selection_refused(void *data, struct agora_shell *shell, const char *mime_type, uint32_t reason)
{
	AGWindowServer *server = data;

	(void)shell;
	if (server->selection.refused != NULL) {
		server->selection.refused(server->selection.context, mime_type, reason);
	}
}

static const struct agora_shell_listener shell_listener = {
	selection_offer,
	selection_lost,
	selection_requested,
	selection_sent,
	selection_refused,
};

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

/* **THE PROCESS'S ONE CONNECTION.** Not thread-safe on purpose: AppKit is single-threaded here (the run loop is
 * the main thread's), and a lock would suggest a concurrency nobody has. A failed connect is not cached, so a
 * later attempt can succeed once there is a display. */
AGWindowServer *AGWindowServerShared(void)
{
	static AGWindowServer *s_shared;

	if (s_shared == NULL) {
		s_shared = AGWindowServerConnect();
	}
	return s_shared;
}

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
#ifdef AG_HAVE_DMABUF
	if (server->dmabuf != NULL) {
		zwp_linux_dmabuf_v1_destroy(server->dmabuf);
	}
	if (server->gbm != NULL) {
		gbm_device_destroy(server->gbm);
		if (server->gbm_fd >= 0) {
			close(server->gbm_fd);
		}
	}
#endif
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

int AGWindowServerGetFd(AGWindowServer *server)
{
	if (server == NULL || server->display == NULL) {
		return -1;
	}
	return wl_display_get_fd(server->display);
}

int AGWindowServerNextDeadlineMs(AGWindowServer *server)
{
	int32_t until;

	if (server == NULL || !server->repeat_active || server->repeat_rate == 0) {
		return -1;
	}
	until = (int32_t)(server->repeat_due_ms - ag_now_ms());
	return (until < 0) ? 0 : (int)until;
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
	if (wl_display_dispatch_pending(server->display) < 0) {
		ag_server_error(server, "wl_display_dispatch_pending");
		return -1;
	}
	/* **AND THE SEAM'S OWN CLOCK, WHICH THIS DOOR NOW TURNS AS WELL.** A held key's repeat is the compositor's
	 * policy, and a loop that watches the connection as a run-loop source never calls the timeout form that used to
	 * be the only place it was fired — so it is fired here, where every non-blocking dispatch comes through. */
	ag_repeat_fire_if_due(server);
	return 1;
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

/* **ONE DUE REPEAT, AND ONLY AFTER THE NATIVE INPUT HAS BEEN TAKEN.** The order is the whole of the contract's last
 * clause: a repeat is generated only once everything the compositor has already sent has been dispatched, so a real
 * key release that arrived while the repeat was pending is seen FIRST and cancels it — instead of the repeat being
 * synthesized into a window whose key is already up. And no burst: a machine that was asleep, or a loop that was busy
 * for a second, reschedules from NOW rather than replaying every interval that has passed, because a held key means
 * "keep typing", not "type the last second all at once". */
static void ag_repeat_fire_if_due(AGWindowServer *server)
{
	uint32_t now;

	if (!server->repeat_active || server->repeat_rate <= 0) {
		return;
	}
	now = ag_now_ms();
	if ((int32_t)(now - server->repeat_due_ms) < 0) {
		return;		/* not yet */
	}
	if (server->keyboard_focus == NULL) {
		ag_repeat_cancel(server);
		return;
	}
	server->repeat_event.time_ms = now;
	ag_window_deliver(server->keyboard_focus, &server->repeat_event);
	/* FROM NOW, NOT FROM THE DEADLINE THAT WAS MISSED — see above. */
	server->repeat_due_ms = now + (uint32_t)(1000 / server->repeat_rate);
}

int AGWindowServerDispatchTimeout(AGWindowServer *server, int timeout_ms)
{
	struct pollfd pfd;
	int ready;

	if (server == NULL) {
		return -1;
	}
	/* **THE WAIT IS CLAMPED TO THE NEXT REPEAT.** A caller waiting a full slice for input would otherwise hold a
	 * repeat back for the whole slice, and a held key would stutter at the loop's cadence rather than at the rate the
	 * compositor asked for. Waiting no longer than the repeat means the repeat decides when this returns, and a
	 * zero-timeout poll stays a poll. */
	if (server->repeat_active && server->repeat_rate > 0) {
		uint32_t now = ag_now_ms();
		int32_t until = (int32_t)(server->repeat_due_ms - now);

		if (until < 0) {
			until = 0;
		}
		if (timeout_ms < 0 || until < timeout_ms) {
			timeout_ms = (int)until;
		}
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
		if (wl_display_dispatch_pending(server->display) < 0) {
			return -1;
		}
		ag_repeat_fire_if_due(server);
		return 1;
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
	ag_repeat_fire_if_due(server);
	return 1;
}

/* **A FLUSH THAT CANNOT PUSH EVERYTHING WAITS FOR THE SOCKET INSTEAD OF KEEPING THE REMAINDER.** libwayland holds
 * the unsent bytes in a FIXED 4 KB buffer, and the request that does not fit in what is left CLOSES THE CONNECTION:
 * "Data too big for buffer (4096 + 20 > 4096), error in client communication", MEASURED — it took a whole session
 * down when the About window was opened over a menu that was repainting, and the desktop went with it.
 *
 * So every flush in this file drains: if `wl_display_flush` answers `EAGAIN` the descriptor is polled for writability
 * and the flush is tried again, a few times, for a bounded time. The bound is what keeps a compositor that has
 * stopped reading from becoming a client that hangs — after it, the caller is told the buffer is still full and can
 * decide, rather than queueing into it and dying.
 */
static int ag_flush_drain(AGWindowServer *server, int timeout_ms)
{
	int attempt;

	if (server == NULL || server->display == NULL) {
		return 0;
	}
	for (attempt = 0; attempt < 4; attempt++) {
		struct pollfd pfd;

		if (wl_display_flush(server->display) >= 0) {
			return 1;	/* everything is out */
		}
		if (errno != EAGAIN && errno != EWOULDBLOCK) {
			return 0;	/* a real failure; the caller's own error path owns it */
		}
		pfd.fd = wl_display_get_fd(server->display);
		pfd.events = POLLOUT;
		pfd.revents = 0;
		if (poll(&pfd, 1, timeout_ms) <= 0) {
			return 0;
		}
	}
	return 0;
}

int AGWindowServerCanWrite(AGWindowServer *server)
{
	/* **A FLUSH THAT COULD NOT PUSH EVERYTHING MEANS THE NEXT REQUEST MIGHT NOT FIT — AND THAT IS FATAL.**
	 * libwayland keeps the unsent remainder in a fixed 4 KB buffer and closes the connection when a request does
	 * not fit in what is left ("Data too big for buffer (4096 + 8 > 4096), error in client communication"),
	 * which MEASURED took a whole session down: the desktop vanished mid-click. So a caller with an expensive
	 * frame to hand over asks this first and waits for the output rather than queueing into a full buffer. The
	 * flush here is the question as well as the answer: it either empties the buffer or tells us it is full. */
	return ag_flush_drain(server, 50);
}

void AGWindowServerFlush(AGWindowServer *server)
{
	ag_flush_drain(server, 50);
}

const char *AGWindowServerLastError(AGWindowServer *server)
{
	return server != NULL ? server->error : "no connection";
}

int AGWindowServerIsActive(AGWindowServer *server)
{
	return server != NULL ? server->active : 0;
}

void AGWindowServerSetActivationHandler(AGWindowServer *server, AGActivationFunction function, void *context)
{
	if (server == NULL) {
		return;
	}
	server->activation_fn = function;
	server->activation_context = context;
}

/* ==================================================================================================
 * THE SELECTION'S PUBLIC DOORS
 * ================================================================================================== */

void AGWindowServerSetSelectionHandlers(AGWindowServer *server, const AGSelectionHandlers *handlers)
{
	if (server == NULL) {
		return;
	}
	/* **THE FIVE EVENTS ARE ONLY DELIVERED IF THE SHELL IS NEW ENOUGH TO SPEAK THEM**, and the listener is installed
	 * here rather than at connect time so that a program that never touches the clipboard never hears about one —
	 * the events are unsolicited, and a client that does not care should not pay for them. */
	if (handlers != NULL && server->shell != NULL &&
	    wl_proxy_get_version((struct wl_proxy *)server->shell) >= 7) {
		server->selection = *handlers;
		agora_shell_add_listener(server->shell, &shell_listener, server);
	} else if (handlers == NULL) {
		memset(&server->selection, 0, sizeof server->selection);
	}
}

int AGWindowServerSetSelection(AGWindowServer *server, const char *const *types, int count)
{
	struct wl_array array;
	int i;

	if (server == NULL || server->shell == NULL || count <= 0 ||
	    wl_proxy_get_version((struct wl_proxy *)server->shell) < 7) {
		return -1;
	}
	/* **THE ARRAY IS THE STRINGS' BYTES, NOT A LIST OF POINTERS**: an `array` is opaque to Wayland, so each type is
	 * copied with its NUL. Marshalling a `char **` sends this process's addresses, which the server cannot use and
	 * must not trust. */
	wl_array_init(&array);
	for (i = 0; i < count; i++) {
		size_t length;
		char *slot;

		if (types[i] == NULL) {
			continue;
		}
		length = strlen(types[i]) + 1;
		slot = (char *)wl_array_add(&array, length);
		if (slot == NULL) {
			wl_array_release(&array);
			return -1;
		}
		memcpy(slot, types[i], length);
	}
	agora_shell_set_selection(server->shell, &array);
	wl_array_release(&array);
	return 0;
}

void AGWindowServerClearSelection(AGWindowServer *server)
{
	if (server == NULL || server->shell == NULL ||
	    wl_proxy_get_version((struct wl_proxy *)server->shell) < 7) {
		return;
	}
	agora_shell_clear_selection(server->shell);
}

int AGWindowServerRequestSelection(AGWindowServer *server, const char *mime_type)
{
	if (server == NULL || server->shell == NULL || mime_type == NULL ||
	    wl_proxy_get_version((struct wl_proxy *)server->shell) < 7) {
		return -1;
	}
	agora_shell_request_selection(server->shell, mime_type);
	return 0;
}

uint32_t AGWindowServerFocusSerial(AGWindowServer *server)
{
	return (server != NULL) ? server->focus_serial : 0;
}

double AGWindowServerScale(AGWindowServer *server)
{
	return (server != NULL && server->scale > 0.0) ? server->scale : 1.0;
}

double AGWindowBufferScale(AGWindow *window)
{
	return (window != NULL && window->scale > 0.0) ? window->scale : 1.0;
}

void *AGWindowServerNativeDisplay(AGWindowServer *server)
{
	return (server != NULL) ? (void *)server->display : NULL;
}

void *AGWindowServerNativeGBMDevice(AGWindowServer *server)
{
	/* **THE DEVICE IS OPENED ON DEMAND, BECAUSE A CLIENT THAT NEVER ASKS FOR A GPU BUFFER NEVER NEEDS ONE.** This asks
	 * the same question `ag_buffer_create_dmabuf` asks, through the same code, so a renderer that builds its display on
	 * the answer is on the device the buffers will come from. */
	if (server == NULL) {
		return NULL;
	}
	if (!ag_gbm_ready(server)) {
		return NULL;
	}
	return (void *)server->gbm;
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
	/* **THE SCALE IS TAKEN BEFORE THE FIRST BUFFER AND ANNOUNCED BEFORE THE FIRST COMMIT.** `set_buffer_scale` is
	 * double-buffered, so it has to be said before the commit that attaches a buffer at that scale — and the output
	 * has already told this process what the screen is. A window made on a 2x output therefore renders at 2x from its
	 * very first frame, rather than for one frame at 1x and then again. */
	window->scale = server->scale > 0.0 ? server->scale : 1.0;
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
		/* **AND THE WINDOW'S OWN EVENTS ARE LISTENED FOR, WHICH IS WHAT CARRIES THE POINTER'S ABSOLUTE POSITION.**
		 * Without this the `pointer_global` events go nowhere and a drag is back to the moving target. */
		agora_window_add_listener(window->agora, &agora_window_listener, window);
		/* **THE SCALE GOES OUT BEFORE THE FIRST BUFFER IS COMMITTED**, exactly like `wl_surface.set_buffer_scale`:
		 * a fractional declaration that arrived after the attach would composite one frame at the wrong divisor. */
		ag_window_send_scale(window);
		if (title != NULL) {
			agora_window_set_title(window->agora, title);
		}
		if (window->app_id[0] != '\0') {
			agora_window_set_app_id(window->agora, window->app_id);
		}
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
		if (window->app_id[0] != '\0') {
			xdg_toplevel_set_app_id(window->toplevel, window->app_id);
		}
		/* A stock compositor has no fractional request, so this is the integer path — and it still has to be said
		 * before the commit that gives the surface its role. */
		ag_window_send_scale(window);
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
	/* **BOTH SLOTS, because a window owns two buffers now.** The one on the glass is destroyed too: the surface
	 * is going away in this same teardown, so there is nothing left to show it on. */
	ag_buffer_dispose(&window->spare);
	ag_buffer_dispose(&window->buffer);
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
	/* **AND IT DOES NOT COMMIT, WHICH IS THE WHOLE OF A BUG THIS TOOK A PERSON TO SPOT.** Wayland has no separate
	 * "map": a surface with a role and a committed buffer is shown — so committing HERE, before the caller has
	 * drawn anything, MAPS THE WINDOW EMPTY. The paint that follows is then one commit too late: the compositor has
	 * already seen this surface with nothing in it, and MEASURED, a menu opened this way does not appear on the
	 * click, its rows do not highlight as the pointer moves over them, and it shows up only after something else
	 * makes the window stale enough to be drawn twice. A WINDOW CREATED LONG BEFORE ITS FIRST PAINT NEVER SHOWED
	 * THE SYMPTOM — which is the menu BAR's window, and the asymmetry that gave it away.
	 *
	 * **THE MAC'S OWN ORDER IS DRAW FIRST AND SHOW AFTERWARDS**, and leaving the commit to the first
	 * `AGWindowEndFrame` is how a client gets that order for free: the first commit the compositor ever sees
	 * carries the buffer, so there is never a moment when the window is on the screen and empty. A window shown and
	 * never drawn is then never mapped at all, which is right — it has nothing to show. */
	if (getenv("AG_WINDOW_DIAG") != NULL) {
		fprintf(stderr, "  DIAG show: agora=%p xdg=%p configured=%d frame_ready=%d surface=%p\n",
			(void *)window->agora, (void *)window->xdg_surface, window->configured, window->frame_ready,
			(void *)window->surface);
	}
	wl_display_flush(window->server->display);
	if (window->agora != NULL) {
		/* **AND A WINDOW THAT IS SHOWN IS VISIBLE, WHICH THIS NEVER SAID.** `-orderOut:` was wired to a hide
		 * request when that door was built and THIS half was not wired to its opposite — so a window hidden once
		 * could NEVER BE SHOWN AGAIN: the server went on skipping it while the client drew into it, and MEASURED,
		 * from the server's own log, that is exactly what a menu's window looked like:
		 *
		 *     surface: mapped=1 visible=0 level=0 buffer=1
		 *
		 * mapped, at the right level, WITH a buffer, and skipped by the one guard nobody had asked about. The menu
		 * bar's window was never hidden, which is why it painted all along — the same asymmetry that has been
		 * pointing at this since the first report.
		 *
		 * A hide without a show is not a door, it is a trap. */
		agora_window_set_visible(window->agora, 1);
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
	/* **A RESIZE MAKES THE DRAWING SLOT AGAIN, AND LEAVES THE PIXELS ON THE GLASS ALONE.** A frame that replaces
	 * what is showing is committed when the next one is drawn, so the window never has to lose its buffer to
	 * change size — see `ag_window_resize`. */
	if (width > 0 && height > 0 && (width != window->width || height != window->height)) {
		if (window->begun) {
			/* **NOT UNDER A FRAME THAT IS BEING DRAWN.** The caller is mid-draw with the old buffer's pointer
			 * and pitch; changing the size now would make its `AGWindowWidth` disagree with its buffer. The
			 * request is remembered and made on the release — see `buffer_release`. */
			window->pending_width = width;
			window->pending_height = height;
		} else {
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

/* **THE STRIP OF SCREEN THIS WINDOW TAKES, WHICH IS THE DOCK'S ONE REAL REQUEST.** The server's work area is the
 * output minus the furniture; the menu bar is the server's own share and this is the client's. There is nothing to
 * remember on this side: the answer comes back on `agora_output.work_area`, which is what `AGWindowServerWorkArea`
 * reads, so a client that asks and then asks again is asking the screen rather than a cache it keeps.
 *
 * A stock `xdg-shell` compositor has no door for it, and this says so by doing nothing rather than by recording a
 * number nobody would ever read. A window has ONE reservation, so asking again moves it — see the protocol's
 * `set_reserved` and `NSWindow -cg_setReservedEdge:amount:`, which is the door AppKit puts on this. */
/* **AND WHETHER A CLICK ON THIS WINDOW MAY GIVE ITS APPLICATION THE KEYBOARD.** The Dock says no: clicking one of
 * its tiles must activate the application the tile names, and a Dock that took the keyboard would take the menu bar
 * with it. A window that says nothing keeps the ordinary behaviour. */
void AGWindowSetActivatable(AGWindow *window, int activatable)
{
	if (window == NULL || window->agora == NULL) {
		return;
	}
	agora_window_set_activatable(window->agora, activatable ? 1 : 0);
	wl_display_flush(window->server->display);
}

/* **AND THE ONE STATEMENT ABOUT TWO WINDOWS THIS SEAM CAN MAKE.** A sheet is an ordinary window with an ordinary
 * frame — the placement stays `AGWindowSetFrame`'s — but the server cannot tell a sheet from a window that merely
 * touches one, so the application says which it is. What the pair buys is the shape (the top corners are the parent's
 * title bar's seam, not the sheet's own edge) and the stack (the sheet is drawn and hit-tested immediately in front of
 * its parent whoever was raised).
 *
 * A PARENT WITH NO `AGWindow` YET DETACHES, and that is not a degradation: a window that has never been ordered onto
 * the screen has no surface for the server to draw above, so there is nothing to say about it. Both windows belong to
 * this client, which is why the parent is an object here and an id everywhere else in this protocol — see
 * `agora_window.set_sheet_parent`. */
void AGWindowSetSheetParent(AGWindow *window, AGWindow *parent, int seam)
{
	struct agora_window *parent_role = NULL;

	if (window == NULL || window->agora == NULL) {
		return;
	}
	if (parent != NULL) {
		parent_role = parent->agora;
	}
	agora_window_set_sheet_parent(window->agora, parent_role, seam > 0 ? seam : 0);
	wl_display_flush(window->server->display);
}

/* **THE POINTER'S SHAPE, WHICH IS ONE STRING AND NO PIXELS AT ALL.** See the header: the compositor resolves the name
 * against the theme it already loaded, so what an application sends is a shape and not a bitmap. NULL and "" are the same
 * request — the default — because the AppKit has no name for a custom image cursor (its pixels cannot cross yet) and the
 * compositor's default is the honest answer for it. */
void AGWindowSetCursor(AGWindow *window, const char *name)
{
	if (window == NULL || window->agora == NULL) {
		return;
	}
	agora_window_set_cursor(window->agora, name != NULL ? name : "");
	wl_display_flush(window->server->display);
}

void AGWindowSetReserved(AGWindow *window, int edge, int amount)
{
	if (window == NULL || window->agora == NULL) {
		return;
	}
	agora_window_set_reserved(window->agora, (uint32_t)edge, amount > 0 ? amount : 0);
	wl_display_flush(window->server->display);
}

/* **THE FORMAT IS CHOSEN WHEN THE BUFFER IS MADE, SO A BUFFER ALREADY MADE HAS TO GO.** A BUSY one is on screen
 * and is left alone — a window that flips transparency mid-life keeps its old buffer until the next one is made,
 * said here rather than assumed — but in practice this is called before the first frame, when there is none. */
void AGWindowSetTransparent(AGWindow *window, int transparent)
{
	int wanted = (transparent != 0);

	if (window == NULL || window->transparent == wanted) {
		return;
	}
	window->transparent = wanted;
	/* **THE DRAWING SLOT HAS THE OLD FORMAT, so it is let go AND REMADE.** MEASURED: the version that only let it
	 * go left the window with NO buffer at all, and `AGWindowBeginFrame` then refused to paint it for ever — which
	 * is what made an icon window show nothing. The remake is the same path a resize takes, so a window whose size
	 * is not yet known is remade by the frame set that follows. The buffer on the glass keeps its format until the
	 * next commit replaces it, which is one frame of the old one and the only alternative to dropping it. */
	if (window->spare.buffer != NULL && !window->spare.busy) {
		int width = window->width;
		int height = window->height;

		ag_buffer_dispose(&window->spare);
		ag_window_resize(window, width, height);
	}
}

void AGWindowSetPointerGrab(AGWindow *window, int grab)
{
	if (window == NULL) {
		return;
	}
	/* **AND NOTHING IS REMEMBERED HERE, WHICH IS THE DIFFERENCE FROM THE OTHER SETTERS.** A compositor that does
	 * not speak `agora_shell` has no door for this, and a client that recorded the request would believe it holds
	 * a pointer the compositor never gave it — so the request simply is not made, and the popup behaves as it did
	 * before: a click on the desktop goes nowhere. */
	if (window->agora != NULL) {
		agora_window_set_pointer_grab(window->agora, grab ? 1 : 0);
		wl_display_flush(window->server->display);
	}
}

void AGWindowSetPointerCapture(AGWindow *window, int capture)
{
	if (window == NULL) {
		return;
	}
	/* Nothing is remembered here, for the same reason the fallback remembers nothing: a compositor without
	 * `agora_shell` has no door for this, and a client that recorded the request would believe it held a pointer
	 * the compositor never gave it. */
	if (window->agora != NULL) {
		agora_window_set_pointer_capture(window->agora, capture ? 1 : 0);
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

void AGWindowLower(AGWindow *window)
{
	if (window != NULL && window->agora != NULL) {
		agora_window_lower(window->agora);
		wl_display_flush(window->server->display);
	}
}

void AGWindowTakeFocus(AGWindow *window)
{
	if (window == NULL || window->agora == NULL) {
		return;
	}
	/* **ASKED ONLY OF A COMPOSITOR THAT DECLARED IT.** An `xdg-shell` compositor has no such door and an older
	 * Agora one has no such request; sending it anyway is a protocol error on the connection this application
	 * shares with everything else it draws. */
	if (wl_proxy_get_version((struct wl_proxy *)window->agora) < 5) {
		return;
	}
	agora_window_take_focus(window->agora);
	wl_display_flush(window->server->display);
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
	if (window == NULL) {
		return;
	}
	/* **BOTH ROLES, BECAUSE A TITLE IS THE WINDOW'S AND NOT THE PROTOCOL'S.** This used to write to
	 * `window->toplevel` only, so on Agora's own server a window's title was whatever it was created with and a
	 * later `-setTitle:` went nowhere — which a shell listing titles would have shown as a window that never
	 * renames itself. */
	if (window->agora != NULL) {
		agora_window_set_title(window->agora, title != NULL ? title : "");
	} else if (window->toplevel != NULL) {
		xdg_toplevel_set_title(window->toplevel, title != NULL ? title : "");
	}
	wl_display_flush(window->server->display);
}

/* **AND THE APPLICATION'S OWN NAME, WHICH A SHELL GROUPS BY.** The Mac's vocabulary is the bundle identifier, and
 * AppKit supplies it from `NSBundle` without being asked. It is recorded on the window as well as sent, because a
 * window made before the caller could name it would otherwise reach the server anonymous — which is exactly what
 * the constant this replaces made every window. */
void AGWindowSetAppID(AGWindow *window, const char *app_id)
{
	if (window == NULL) {
		return;
	}
	snprintf(window->app_id, sizeof window->app_id, "%s", app_id != NULL ? app_id : "");
	if (window->agora != NULL) {
		agora_window_set_app_id(window->agora, window->app_id);
	} else if (window->toplevel != NULL) {
		xdg_toplevel_set_app_id(window->toplevel, window->app_id);
	}
	wl_display_flush(window->server->display);
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
