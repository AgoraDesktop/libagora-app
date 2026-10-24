/*
 * window — the seam, driven the way NSWindow will drive it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * THIS IS THE SPIKE, REWRITTEN AGAINST THE INTERFACE. It uses nothing but <AGWindowServer.h>: no Wayland
 * type, no xdg-shell name, no shm. That is the point of it — if the seam is ever reimplemented (Agora's own
 * window server, a nested backend, a different protocol), this program must not change.
 *
 * WHAT IT DRAWS, and why those shapes: a left-to-right gradient proves the pixels are ours; a RED square at
 * buffer (0,0) and a GREEN one at the bottom-right prove WHICH WAY IS UP, because a bottom-up buffer or a
 * stride in the wrong unit puts them in the wrong corners; and a bar that moves with time can only move if
 * the frame handler is being called again and again.
 *
 *   window [--title T] [--width W] [--height H] [--frames N]
 *
 * --frames N presents N frames and exits 0, which is what makes a headless run terminate and assert.
 */

#include "AGWindowServer.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define EVDEV_KEY_ESC 1

struct App {
	AGWindow *window;
	int frames;
	int max_frames;
	int done;
	/* **AND A RESIZE, WHICH IS THE ONE PATH WHERE THE SEAM DEFERS.** A resize cannot free the buffer the
	 * compositor is showing (the surface's current buffer is the last one ATTACHED, and a surface with none is not
	 * drawn at all), so the seam keeps the outgoing one and makes the new size when its release arrives. THAT
	 * DEFERRAL IS THE THING THAT CAN GO WRONG QUIETLY: a release that never finishes the job leaves a window that
	 * can never be drawn again. So the seam's own test asks for a size once and insists that a frame is presented
	 * at it. */
	int want_width;
	int want_height;
	int asked;
	int answered;
	int answered_width;
};

static uint32_t now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint32_t)((uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u);
}

static void draw(uint32_t *pixels, int stride_bytes, int width, int height, uint32_t time_ms)
{
	const int pitch = stride_bytes / 4;
	const int bar_width = width / 10;
	const int span = width + bar_width;
	const int bar_x = (int)((time_ms / 6u) % (uint32_t)(span > 0 ? span : 1)) - bar_width;
	const int bar_top = height / 5;
	const int bar_bottom = height - height / 5;
	int x, y;

	/* 1. the gradient */
	for (y = 0; y < height; y++) {
		for (x = 0; x < width; x++) {
			uint32_t r = (uint32_t)(32 + (200 * x) / (width > 0 ? width : 1));
			uint32_t g = (uint32_t)(40 + (120 * y) / (height > 0 ? height : 1));

			pixels[y * pitch + x] = (r << 16) | (g << 8) | 90u;
		}
	}
	/* 2. the two corner markers */
	for (y = 0; y < 48 && y < height; y++) {
		for (x = 0; x < 48 && x < width; x++) {
			pixels[y * pitch + x] = 0x00E03030u;
			pixels[(height - 1 - y) * pitch + (width - 1 - x)] = 0x0035C04Au;
		}
	}
	/* 3. the bar */
	for (y = bar_top; y < bar_bottom; y++) {
		for (x = 0; x < bar_width; x++) {
			int px = bar_x + x;

			if (px >= 0 && px < width) {
				pixels[y * pitch + px] = 0x00FFFFFFu;
			}
		}
	}
}

static void on_frame(void *context, uint32_t time_ms)
{
	struct App *app = context;
	int stride = 0;
	uint32_t *pixels = AGWindowBeginFrame(app->window, &stride);

	if (pixels == NULL) {
		return;			/* the compositor still holds the buffer; the handler will be called again */
	}
	/* **THE RESIZE IS ASKED FOR BETWEEN TWO FRAMES**, which is what a drag does, and the frame that follows it
	 * must be at the NEW size: the seam makes the buffer when the outgoing one's release arrives, and a frame
	 * drawn at the old width through a new buffer — or never drawn at all — is the failure this asks about. The
	 * STRIDE is where the answer lives: it is the buffer's row pitch, so it is the size that was actually given. */
	if (!app->asked) {
		app->want_width = AGWindowWidth(app->window) + 40;
		app->want_height = AGWindowHeight(app->window) + 30;
		AGWindowSetFrame(app->window, 0, 0, app->want_width, app->want_height);
		app->asked = 1;
	} else if (!app->answered) {
		app->answered = 1;
		/* **THE STRIDE IS DEVICE PIXELS, so the comparison below is against the asked-for width times the
		 * output scale.** On an ordinary screen those are the same number; on a HiDPI one the buffer is twice as
		 * wide as the window is, which is the whole point — so a test that compared them directly would be
		 * asserting that HiDPI does not work. */
		app->answered_width = stride / 4;
		/* AND THE RUN CARRIES ON: this client's contract is a frame count, and one that stopped here would be
		 * presenting two of the sixty the runner asks for. The answer is checked at the end. */
	}
	draw(pixels, stride, AGWindowWidth(app->window), AGWindowHeight(app->window),
	     time_ms != 0 ? time_ms : now_ms());
	AGWindowEndFrame(app->window);

	app->frames++;
	if (app->max_frames > 0 && app->frames >= app->max_frames) {
		app->done = 1;
	}
}

static void on_event(void *context, const AGEvent *event)
{
	struct App *app = context;

	switch (event->type) {
	case AGEventConfigure:
		fprintf(stderr, "window: configured %dx%d\n", event->x, event->y);
		break;
	case AGEventClose:
		fprintf(stderr, "window: the compositor asked the window to close\n");
		app->done = 1;
		break;
	case AGEventKey:
		if (event->pressed && event->keycode == EVDEV_KEY_ESC) {
			fprintf(stderr, "window: ESC, closing\n");
			app->done = 1;
		} else {
			fprintf(stderr, "window: key %u %s%s%s text=\"%s\"\n", event->keycode,
				event->pressed ? "down" : "up",
				(event->modifiers & AGModifierShift) ? " shift" : "",
				(event->modifiers & AGModifierControl) ? " control" : "", event->text);
		}
		break;
	case AGEventPointerEnter:
		fprintf(stderr, "window: pointer %s at %d,%d\n", event->pressed ? "entered" : "left",
			event->x, event->y);
		break;
	case AGEventPointerButton:
		fprintf(stderr, "window: pointer button %u %s at %d,%d\n", event->button,
			event->pressed ? "down" : "up", event->x, event->y);
		break;
	case AGEventPointerMotion:
		break;
	default:
		break;
	}
}

int main(int argc, char **argv)
{
	struct App app;
	AGWindowServer *server;
	const char *title = "Agora AppKit";
	int width = 640;
	int height = 400;
	int i;

	memset(&app, 0, sizeof app);
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--title") == 0 && i + 1 < argc) {
			title = argv[++i];
		} else if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
			width = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
			height = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
			app.max_frames = atoi(argv[++i]);
		} else {
			fprintf(stderr, "usage: %s [--title T] [--width W] [--height H] [--frames N]\n", argv[0]);
			return 2;
		}
	}

	server = AGWindowServerConnect();
	if (server == NULL) {
		fprintf(stderr, "window: could not connect: %s\n", AGWindowServerLastError(NULL));
		return 1;
	}
	app.window = AGWindowCreate(server, width, height, title);
	if (app.window == NULL) {
		fprintf(stderr, "window: could not create a window: %s\n", AGWindowServerLastError(server));
		AGWindowServerDisconnect(server);
		return 1;
	}
	AGWindowSetEventHandler(app.window, on_event, &app);
	AGWindowSetFrameHandler(app.window, on_frame, &app);
	AGWindowShow(app.window);

	while (!app.done) {
		if (AGWindowServerDispatch(server) < 0) {
			fprintf(stderr, "window: dispatch failed: %s\n", AGWindowServerLastError(server));
			AGWindowServerDisconnect(server);
			return 1;
		}
	}

	fprintf(stderr, "window: %d frame(s) presented\n", app.frames);
	AGWindowServerDisconnect(server);
	if (app.frames == 0) {
		fprintf(stderr, "window: NO FRAME WAS PRESENTED\n");
		return 1;
	}
	/* **AND THE FRAME AFTER THE RESIZE IS THE SIZE THAT WAS ASKED FOR**, which is the deferral's whole promise:
	 * the seam keeps the outgoing buffer so the window stays on screen, and makes the new size when its release
	 * arrives. A width that never catches up is a window that can never be drawn again. */
	if (app.asked && !app.answered) {
		fprintf(stderr, "window: A RESIZE WAS ASKED FOR AND NO FRAME FOLLOWED IT\n");
		return 1;
	}
	if (app.answered && app.answered_width != app.want_width * AGWindowBufferScale(app.window)) {
		fprintf(stderr, "window: the frame after the resize is %d device pixels wide, want %d x %d\n",
			app.answered_width, app.want_width, AGWindowBufferScale(app.window));
		return 1;
	}
	fprintf(stderr, "window: the frame after a resize to %dx%d points is %d device pixels wide (scale %d)\n",
		app.want_width, app.want_height, app.answered_width, AGWindowBufferScale(app.window));
	return 0;
}
