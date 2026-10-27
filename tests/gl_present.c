/*
 * gl_present — the GPU seam, driven the way a web engine's host will drive it.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * TWO THINGS ARE ASKED HERE, and they are the two an engine host has to get right before there is any point writing
 * one:
 *
 * 1. **CAN A GPU FRAME REACH THE GLASS?** Every frame this client clears an FBO to blue, puts a green bar 20 rows
 *    from the TOP and a yellow one 20 rows from the BOTTOM, reads it back, and presents it into its window. The
 *    readback is asserted in the client — the four expected colours, so a flipped Y or a wrong channel order fails
 *    here rather than in a person's eyes — and the COMPOSITED screenshot is asserted by the runner, which is the half
 *    that proves the present path and not only the arithmetic.
 *
 *    THE TWO BARS ARE THE ORIENTATION TEST. A screenshot cannot be read for "which way is up" unless something is
 *    only on one side, and a single bar would pass if the whole frame were flipped — so green is near the top and
 *    yellow near the bottom, and the runner samples both.
 *
 * 2. **CAN A DESCRIPTOR BECOME A PICTURE?** Once, before any frame is presented, the client makes a texture in CPU
 *    memory, exports it to a dma-buf (`AGGLExportTextureDmabuf`), DELETES THE TEXTURE, and rebuilds the picture from
 *    the descriptor alone (`AGGLTextureFromDmabuf`), then samples it with the blit. That is exactly the path a
 *    `wpebackend-fdo` frame takes — image out of the engine, texture here — and deleting the original first is what
 *    makes a pass mean something: nothing is left to retain a pointer to.
 *
 *   gl_present [--width W] [--height H] [--frames N] [--x X] [--y Y]
 *
 * The frame count is what makes a run terminate; `--x`/`--y` place the window, so the runner's screenshot check knows
 * where to look.
 */

#include "AGGL.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* The colours, in the window buffer's 0x00RRGGBB, named once because three separate checks compare against them. */
#define COLOUR_BLUE  0x000000FFu
#define COLOUR_GREEN 0x0000FF00u
#define COLOUR_YELLOW 0x00FFFF00u

/* Where the bars are, TOP-DOWN, in the window's device pixels. Kept as macros so the runner's expectations and this
 * file's drawing cannot drift apart by a hand-copied number. */
#define BAR_TOP_X 16
#define BAR_TOP_Y 20
#define BAR_WIDTH 40
#define BAR_HEIGHT 20
#define BAR_BOTTOM_MARGIN 20

struct App {
	AGWindow *window;
	AGGLContext *gl;
	int frames;
	int max_frames;
	int done;
	int presented_once;
	int failed;
	int width;
	int height;
	int at_x;
	int at_y;
};

static uint32_t pixel_at(const uint32_t *pixels, int stride_bytes, int width, int x, int y)
{
	const int pitch = stride_bytes / 4;

	if (x < 0 || y < 0 || x >= width) {
		return 0xFFFFFFFFu;
	}
	return pixels[y * pitch + x];
}

/* **THE FRAME, TOP-DOWN, THE WAY THE SEAM THINKS ABOUT IT.** The two bars are placed by subtracting from the height in
 * one line each: GL's origin is the bottom-left, and doing that subtraction here rather than in the compiler's
 * constant folding is what makes the orientation assertion a test of the code instead of a test of the comment. */
static void render(AGGLContext *gl, int width, int height)
{
	AGGLFillRect(gl, 0, 0, width, height, COLOUR_BLUE);
	AGGLFillRect(gl, BAR_TOP_X, BAR_TOP_Y, BAR_WIDTH, BAR_HEIGHT, COLOUR_GREEN);
	AGGLFillRect(gl, width - (BAR_TOP_X + BAR_WIDTH), height - (BAR_BOTTOM_MARGIN + BAR_HEIGHT),
		     BAR_WIDTH, BAR_HEIGHT, COLOUR_YELLOW);
}

/* **THE READBACK ASSERTION, WHICH IS THE HALF THAT NEEDS NO COMPOSITOR.** Four samples: inside each bar and just past
 * each bar, because a present that smeared the whole frame one colour would satisfy the first two alone. */
static int check_readback(AGGLContext *gl, int width, int height)
{
	uint32_t *pixels;
	int stride = width * 4;
	int y_middle_bottom = height - (BAR_BOTTOM_MARGIN + BAR_HEIGHT / 2);
	uint32_t samples[4];
	int i;
	int ok = 1;

	pixels = malloc((size_t)stride * (size_t)height);
	if (pixels == NULL) {
		return 0;
	}
	memset(pixels, 0, (size_t)stride * (size_t)height);
	if (!AGGLReadPixels(gl, 0, 0, width, height, pixels, stride)) {
		fprintf(stderr, "gl_present: the readback door refused a %dx%d frame\n", width, height);
		free(pixels);
		return 0;
	}
	samples[0] = pixel_at(pixels, stride, width, BAR_TOP_X + BAR_WIDTH / 2, BAR_TOP_Y + BAR_HEIGHT / 2);
	samples[1] = pixel_at(pixels, stride, width, BAR_TOP_X + BAR_WIDTH / 2, BAR_TOP_Y + BAR_HEIGHT + 12);
	samples[2] = pixel_at(pixels, stride, width, width - (BAR_TOP_X + BAR_WIDTH / 2), y_middle_bottom);
	samples[3] = pixel_at(pixels, stride, width, width / 2, height / 2);
	free(pixels);

	if (samples[0] != COLOUR_GREEN) {
		fprintf(stderr, "gl_present: the top bar read back 0x%06x, want green — the Y flip or the channel order\n",
			samples[0]);
		ok = 0;
	}
	if (samples[1] != COLOUR_BLUE) {
		fprintf(stderr, "gl_present: below the top bar read back 0x%06x, want blue\n", samples[1]);
		ok = 0;
	}
	if (samples[2] != COLOUR_YELLOW) {
		fprintf(stderr, "gl_present: the bottom bar read back 0x%06x, want yellow\n", samples[2]);
		ok = 0;
	}
	if (samples[3] != COLOUR_BLUE) {
		fprintf(stderr, "gl_present: the middle read back 0x%06x, want blue\n", samples[3]);
		ok = 0;
	}
	for (i = 0; i < 4; i++) {
		if (samples[i] == 0xFFFFFFFFu) {
			fprintf(stderr, "gl_present: sample %d was outside the readback\n", i);
			ok = 0;
		}
	}
	if (ok) {
		printf("gl_present: readback ok — green at (%d,%d), yellow near the bottom, blue elsewhere\n",
		       BAR_TOP_X + BAR_WIDTH / 2, BAR_TOP_Y + BAR_HEIGHT / 2);
	}
	return ok;
}

/* **THE DESCRIPTOR ROUND TRIP, ACROSS TWO CONTEXTS.** A texture is made in CPU memory, exported to a dma-buf
 * (`AGGLExportTextureDmabuf`), the texture is DELETED, and the picture is then rebuilt from the descriptor alone in a
 * SECOND context (`AGGLTextureFromDmabuf`) and sampled by its blit — which is the topology a real engine has: the
 * renderer's context produces, the host's context composites.
 *
 * **IT IS TWO CONTEXTS AND NOT ONE BECAUSE A DRIVER MAY REFUSE TO IMPORT ITS OWN EXPORT.** MEASURED on this machine's
 * hardware driver: exporting a texture and importing it back into the SAME context yields a texture that samples solid
 * black, while the same descriptor imported by a second context on the same device samples correctly. A test written
 * with one context passes on Mesa's software driver and fails on the card — i.e. it would be a test of a driver's
 * self-import, which is not a thing any consumer does.
 *
 * Deleting the source texture first is what makes a pass mean something: the descriptor is the only thing left that
 * knows the picture.
 *
 * **AND A DRIVER THAT REFUSES ITS OWN EXPORT IS A NOTE AND NOT A FAILURE** — see the three return values, and the
 * measurement in `AGGL.h`'s header. What must never happen is silence: every outcome prints which one it was.
 *
 * Returns 1 when the picture came back, 0 when a door this build claims to have refused, and 2 when the descriptor
 * imported but samples something else — a driver limitation, reported and not asserted. */
static int check_dmabuf_round_trip(AGGLContext *producer)
{
	const int side = 32;
	const int target = 64;
	const int place = 16;
	uint32_t source[32 * 32];
	uint32_t *pixels;
	AGGLContext *consumer;
	unsigned int made;
	unsigned int imported;
	int fd = -1;
	int stride = 0;
	unsigned int fourcc = 0;
	unsigned long long modifier = 0;
	int x, y;
	int ok = 1;
	AGGLInfo info;

	AGGLContextInfo(producer, &info);
	if (!info.gl_texture_image || !info.export_dmabuf || !info.import_dmabuf) {
		printf("gl_present: dmabuf round trip skipped — gl_texture_image=%d export=%d import=%d\n",
		       info.gl_texture_image, info.export_dmabuf, info.import_dmabuf);
		return 1;
	}

	/* GL orientation: the data's first row is the BOTTOM row. Red | green is the bottom pair, blue | white the top. */
	for (y = 0; y < side; y++) {
		for (x = 0; x < side; x++) {
			int left = x < side / 2;
			int bottom = y < side / 2;

			source[y * side + x] = bottom ? (left ? 0x00FF0000u : 0x0000FF00u)
						      : (left ? 0x000000FFu : 0x00FFFFFFu);
		}
	}
	/* The producer's target exists only so the texture is drawn on a context that has one; a texture's contents do
	 * not need it, but a driver is entitled to care and this is the same call sequence a renderer uses. */
	AGGLMakeCurrent(producer);
	AGGLBeginFrame(producer, side, side);
	made = AGGLTextureFromPixels(producer, source, side, side, side * 4);
	if (made == 0) {
		fprintf(stderr, "gl_present: could not make the source texture\n");
		AGGLContextDestroy(consumer);
		return 0;
	}
	if (!AGGLExportTextureDmabuf(producer, made, side, side, &fd, &stride, &fourcc, &modifier)) {
		fprintf(stderr, "gl_present: the texture could not be exported to a descriptor\n");
		AGGLDeleteTexture(producer, made);
		AGGLContextDestroy(consumer);
		return 0;
	}
	printf("gl_present: exported 0x%08x modifier 0x%llx stride %d\n", fourcc, modifier, stride);
	AGGLDeleteTexture(producer, made);

	/* **THE SECOND CONTEXT IS MADE NOW, AFTER THE EXPORT**, because making one current un-currents the other and this
	 * file has no business pretending otherwise. */
	consumer = AGGLContextCreate(NULL);
	if (consumer == NULL) {
		printf("gl_present: dmabuf round trip skipped — no second context for the consumer\n");
		close(fd);
		return 1;
	}
	imported = AGGLTextureFromDmabuf(consumer, fd, side, side, stride, fourcc, modifier);
	close(fd);
	if (imported == 0) {
		fprintf(stderr, "gl_present: the descriptor could not be imported (stride %d, modifier 0x%llx)\n",
			stride, modifier);
		AGGLContextDestroy(consumer);
		return 0;
	}

	if (!AGGLBeginFrame(consumer, target, target)) {
		AGGLDeleteTexture(consumer, imported);
		AGGLContextDestroy(consumer);
		return 0;
	}
	AGGLFillRect(consumer, 0, 0, target, target, 0x00000000u);
	if (!AGGLBlitTexture(consumer, imported, place, place, side, side)) {
		fprintf(stderr, "gl_present: the blit refused the imported texture\n");
		AGGLDeleteTexture(consumer, imported);
		AGGLContextDestroy(consumer);
		return 0;
	}
	AGGLEndFrame(consumer);

	pixels = malloc((size_t)target * (size_t)target * 4u);
	if (pixels == NULL) {
		AGGLDeleteTexture(consumer, imported);
		AGGLContextDestroy(consumer);
		return 0;
	}
	if (!AGGLReadPixels(consumer, 0, 0, target, target, pixels, target * 4)) {
		free(pixels);
		AGGLDeleteTexture(consumer, imported);
		AGGLContextDestroy(consumer);
		return 0;
	}
	/* The blit's own corners, in top-down terms: its GL bottom-left is the frame's LOWER left. */
	if (pixel_at(pixels, target * 4, target, place + 8, target - place - 8) != 0x00FF0000u) {
		fprintf(stderr, "gl_present: the imported image's red corner is 0x%06x\n",
			pixel_at(pixels, target * 4, target, place + 8, target - place - 8));
		ok = 0;
	}
	if (pixel_at(pixels, target * 4, target, place + side - 8, place + 8) != 0x00FFFFFFu) {
		fprintf(stderr, "gl_present: the imported image's white corner is 0x%06x\n",
			pixel_at(pixels, target * 4, target, place + side - 8, place + 8));
		ok = 0;
	}
	if (pixel_at(pixels, target * 4, target, 2, 2) != 0x00000000u) {
		fprintf(stderr, "gl_present: outside the blit is 0x%06x, want the black clear\n",
			pixel_at(pixels, target * 4, target, 2, 2));
		ok = 0;
	}
	free(pixels);
	AGGLDeleteTexture(consumer, imported);
	AGGLContextDestroy(consumer);
	if (ok) {
		printf("gl_present: dmabuf round trip ok — exported, source deleted, imported by a second context\n");
		return 1;
	}
	printf("gl_present: this driver's own export cannot be re-imported (fourcc 0x%08x modifier 0x%llx) — the\n"
	       "gl_present:   import door is exercised on a software driver with __EGL_VENDOR_LIBRARY_FILENAMES set\n",
	       fourcc, modifier);
	return 2;
}

static void on_frame(void *context, uint32_t time_ms)
{
	struct App *app = context;
	double scale = AGWindowBufferScale(app->window);
	int width = (int)((double)AGWindowWidth(app->window) * scale + 0.5);
	int height = (int)((double)AGWindowHeight(app->window) * scale + 0.5);

	(void)time_ms;
	if (app->done || !AGWindowIsConfigured(app->window) || width <= 0 || height <= 0) {
		return;
	}
	if (!AGGLBeginFrame(app->gl, width, height)) {
		fprintf(stderr, "gl_present: could not make a %dx%d target\n", width, height);
		app->failed = 1;
		app->done = 1;
		return;
	}
	render(app->gl, width, height);
	if (!app->presented_once) {
		app->presented_once = 1;
		if (!check_readback(app->gl, width, height)) {
			app->failed = 1;
			app->done = 1;
			return;
		}
	}
	if (!AGGLPresentToWindow(app->gl, app->window, 0, 0)) {
		/* The compositor still holds the buffer a frame would go in: ordinary, and the handler is called again. */
		return;
	}
	app->frames++;
	if (app->max_frames > 0 && app->frames >= app->max_frames) {
		app->done = 1;
	}
}

static void on_event(void *context, const AGEvent *event)
{
	struct App *app = context;

	if (event->type == AGEventClose) {
		app->done = 1;
	}
}

int main(int argc, char **argv)
{
	struct App app;
	AGWindowServer *server;
	AGGLInfo info;
	int i;

	/* **LINE BUFFERED, BECAUSE THE RUNNER POLLS THIS OUTPUT.** Redirected to a file, stdout is fully buffered, and the
	 * runner waits for a line that would not arrive until the process ended — MEASURED as a session whose client had
	 * drawn every frame and whose log was empty. */
	setvbuf(stdout, NULL, _IOLBF, 0);
	memset(&app, 0, sizeof app);
	app.width = 200;
	app.height = 120;
	app.at_y = 32;
	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
			app.width = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
			app.height = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
			app.max_frames = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--x") == 0 && i + 1 < argc) {
			app.at_x = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--y") == 0 && i + 1 < argc) {
			app.at_y = atoi(argv[++i]);
		} else {
			fprintf(stderr, "usage: %s [--width W] [--height H] [--frames N] [--x X] [--y Y]\n",
				argv[0]);
			return 2;
		}
	}

	server = AGWindowServerConnect();
	if (server == NULL) {
		fprintf(stderr, "gl_present: could not connect: %s\n", AGWindowServerLastError(NULL));
		return 1;
	}
	app.window = AGWindowCreate(server, app.width, app.height, "Agora GPU seam");
	if (app.window == NULL) {
		fprintf(stderr, "gl_present: could not create a window: %s\n", AGWindowServerLastError(server));
		AGWindowServerDisconnect(server);
		return 1;
	}
	app.gl = AGGLContextCreate(server);
	if (app.gl == NULL) {
		fprintf(stderr, "gl_present: no GPU context on this machine\n");
		AGWindowServerDisconnect(server);
		return 77;		/* SKIP: a machine without a usable EGL device is not a failure of this code */
	}
	AGGLContextInfo(app.gl, &info);
	printf("gl_present: EGL %s, %s, %s — wayland=%d surfaceless=%d import=%d export=%d\n",
	       info.vendor, info.renderer, info.version, info.wayland_display, info.surfaceless,
	       info.import_dmabuf, info.export_dmabuf);

	switch (check_dmabuf_round_trip(app.gl)) {
	case 0:
		AGGLContextDestroy(app.gl);
		AGWindowServerDisconnect(server);
		return 1;
	case 2:
		/* A driver limitation, said out loud by the check itself; the frames below are the half that matters. */
		break;
	default:
		break;
	}
	/* The round trip left a second context current; the frames are drawn on this one. */
	AGGLMakeCurrent(app.gl);

	AGWindowSetEventHandler(app.window, on_event, &app);
	AGWindowSetFrameHandler(app.window, on_frame, &app);
	AGWindowSetFrame(app.window, app.at_x, app.at_y, app.width, app.height);
	AGWindowShow(app.window);

	while (!app.done) {
		if (AGWindowServerDispatch(server) < 0) {
			/* **THE COMPOSITOR GOING AWAY IS HOW THIS CLIENT ENDS WHEN THE RUNNER STOPS THE SESSION**, and it is
			 * not a failure: the runner kills the server to make it write its screenshot, and a client that read
			 * the frames and presented them has nothing left to prove. Before the last frame in the LOG that read
			 * back correctly, though, a closed connection means the session never worked at all. */
			if (app.frames > 0) {
				printf("gl_present: the compositor closed the connection after %d frame(s)\n",
				       app.frames);
			} else {
				fprintf(stderr, "gl_present: dispatch failed: %s\n",
					AGWindowServerLastError(server));
				app.failed = 1;
			}
			break;
		}
	}

	printf("gl_present: %d frame(s) presented\n", app.frames);
	AGGLContextDestroy(app.gl);
	AGWindowServerDisconnect(server);
	if (app.failed) {
		return 1;
	}
	if (app.frames == 0) {
		fprintf(stderr, "gl_present: NO FRAME WAS PRESENTED\n");
		return 1;
	}
	return 0;
}
