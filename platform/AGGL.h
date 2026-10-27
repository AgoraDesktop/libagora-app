/*
 * AGGL.h — the client's one GPU door: an EGL display, an offscreen target, and the image doors a foreign
 * renderer needs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS EXISTS. The AppKit draws with the CPU, into shared memory, and that is a decision rather than a
 * limitation — `AGWindowServer.h` measures it (a destination read-modify-write is about 2 ns through shm and about
 * 2.4 µs through a GPU buffer, so blending into one is a hundredfold loss). But a *web engine* cannot be written
 * that way: WebKit, Servo and every other renderer of that size composite on the GPU and hand back images. There
 * are two ways to fit one into this desktop, and this file is the substrate for both:
 *
 *   1. THE ENGINE RENDERS OFFSCREEN AND THE PIXELS COME BACK. `AGGLBeginFrame` gives an FBO the size of the view,
 *      `AGGLReadPixels` reads it into the same `0x00RRGGBB` the window buffer holds, and a caller either blits that
 *      into a window (`AGGLPresentToWindow`) or wraps it in a `CGImage` and lets the AppKit draw it. Costs one
 *      GPU→CPU readback and one copy per frame, and needs no protocol change at all.
 *
 *   2. THE ENGINE'S IMAGES ARE IMPORTED AND COMPOSITED. `wpebackend-fdo` hands a host `EGLImage`s (or dmabuf
 *      descriptors) belonging to the EGL display the host gave it; `AGGLTextureFromImage` and
 *      `AGGLTextureFromDmabuf` turn those into textures on THIS display, and `AGGLBlitTexture` draws them into the
 *      target. That is the whole of what a WebKit host does with an exported frame, and it is why
 *      `AGGLContextHandles` exposes the EGL display/context for libwpe to be initialised against.
 *
 * **THE EGL DISPLAY IS THE COMPOSITOR'S CONNECTION WHEN THAT BUYS A DEVICE, AND ON THIS MACHINE IT DOES NOT.**
 * A display built on the window server's `wl_display` (`AGWindowServerNativeDisplay`) is the only path that CAN share
 * the compositor's device, so it is tried first; the surfaceless platform is the fallback and needs no display at all.
 * But a Wayland EGL platform learns which device to open from `wl_drm`, which this compositor does not offer, and
 * MEASURED here (NVIDIA GTX 1060, the compositor's GL renderer, 81 dmabuf format/modifier pairs advertised by the
 * server): the Wayland path resolves to Mesa's SOFTWARE driver and the surfaceless path to the real one — so a
 * software renderer is treated as a reason to try the next platform rather than a success. `AGGLContextInfo` reports
 * what was actually got (`wayland_display`, and `renderer`), because a host that needs sharing must be able to see
 * that it did not get it. Making the two genuinely share is window-server work — `wl_drm`, or
 * `zwp_linux_dmabuf_feedback_v1`'s device — and this file is where it will be noticed first.
 *
 * WHAT THIS IS NOT. It is not Core Graphics, not a scene graph and not a layer system: the AppKit's model is
 * unchanged, and a view that wants web content draws the readback pixels the same way it draws a bitmap. It is also
 * not in the AppKit proper — `NSOpenGL*` stays refused, because that is an era API this stack does not implement,
 * and a seam primitive used by one class is a different thing from an OpenGL surface other code is told to draw on.
 *
 * TWO MEASUREMENTS A CALLER SHOULD KNOW ABOUT, both recorded rather than left to be discovered.
 *
 * **A DRIVER MAY REFUSE TO IMPORT ITS OWN EXPORT.** On this machine's hardware driver, a texture exported with
 * `AGGLExportTextureDmabuf` and imported back with `AGGLTextureFromDmabuf` gives a texture that samples solid black at
 * the same context AND at a second context on the same device, while Mesa's software driver completes the same round
 * trip exactly (four quadrants, exported fourcc `AR24`, linear). The exported modifier is block-linear
 * (`0x0300000000cdb012`), so this reads as "the driver will not sample its own tiled allocation", not as a mistake in
 * the attributes. The import door therefore needs a descriptor from *another* producer to be exercised on that driver —
 * which is the direction every real consumer uses, and the one `tests/gl_present.c` prefers when the machine can do it.
 *
 * **THE TWO PLATFORMS DO NOT GIVE THE SAME DEVICE, AND THE INFO STRUCT SAYS WHICH ONE YOU GOT.** Measured above: the
 * compositor's connection resolves to Mesa's software driver because it publishes no `wl_drm`, and the surfaceless
 * platform resolves to the card. So "the EGL display is the compositor's connection" is a preference for sharing, not a
 * promise of it, and `wayland_display` plus `renderer` are the two fields that settle the question.
 *
 * BUILD. Everything here is behind `AG_HAVE_GL` (the CMake decision, like `AG_HAVE_DMABUF`): a build without
 * libEGL and GLESv2 compiles the stubs, every door answers "unavailable", and no caller needs a conditional.
 */

#ifndef AG_GL_H
#define AG_GL_H

#include <stdint.h>

#include "AGWindowServer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AGGLContext AGGLContext;

/* What this machine's GPU door can actually do. Every field is a measurement, not a build flag: a build with EGL
 * linked can still fail to find a device, and a caller that needs sharing must be able to tell. */
typedef struct AGGLInfo {
	int available;			/* 1 when a context exists and GL calls are legal */
	int wayland_display;		/* 1 when the EGL display is the window server's connection */
	int import_dmabuf;		/* EGL_EXT_image_dma_buf_import */
	int import_dmabuf_modifiers;	/* EGL_EXT_image_dma_buf_import_modifiers */
	int gl_texture_image;		/* EGL_KHR_gl_texture_2D_image — needs this to EXPORT a texture */
	int export_dmabuf;		/* EGL_MESA_image_dma_buf_export */
	int surfaceless;		/* EGL_KHR_surfaceless_context — the target is an FBO, not a window */
	int max_texture_size;
	char vendor[64];		/* EGL vendor, for a diagnostic */
	char renderer[64];		/* GL_RENDERER */
	char version[64];		/* GL_VERSION */
} AGGLInfo;

/* **THE CONTEXT, OR NULL.** `server` may be NULL, which asks for the surfaceless fallback and is what a test with no
 * compositor uses. The context makes itself current on the calling thread and stays current until it is destroyed;
 * GL is not thread-safe, so a second thread that wants to draw needs its own context, which this door does not
 * offer yet (a renderer with its own thread keeps its own, and shares through `AGGLContextHandles`). */
AGGLContext *AGGLContextCreate(AGWindowServer *server);
void AGGLContextDestroy(AGGLContext *context);

void AGGLContextInfo(const AGGLContext *context, AGGLInfo *info);

/* **MAKE THIS CONTEXT THE CURRENT ONE ON THE CALLING THREAD, WHICH IS WHAT A HOST WITH TWO OF THEM NEEDS.** A context
 * stays current until another one is made current on that thread, so a process that exports from one and imports into
 * another has to say which it means. MEASURED, as the bug this door was added for: a test made a texture on context A,
 * created context B, and then drew on A's handle — every call landed in B, and the export failed with no diagnostic
 * that mentioned contexts at all. Returns 1 when it worked, 0 for a context with no device behind it. */
int AGGLMakeCurrent(AGGLContext *context);

/* **THE NATIVE HANDLES, TYPED `void *` BECAUSE THIS HEADER NAMES NO EGL TYPE.** They are `EGLDisplay`, `EGLConfig`
 * and `EGLContext`, in that order, and any of the three may be NULL on request. This is the door a WPE host uses:
 * `wpe_fdo_initialize_for_egl_display(display)` and `wpe_view_backend_exportable_fdo_egl_create(..., context, ...)`
 * need exactly these three, and an image created on this display is one this context can import. */
void AGGLContextHandles(const AGGLContext *context, void **display, void **config, void **context_out);

/* **THE OFFSCREEN TARGET, IN DEVICE PIXELS.** Binds an FBO of that size (remaking it only when the size changes) and
 * sets the viewport to it, so a renderer draws in pixels with (0,0) at the BOTTOM LEFT — GL's own origin. The
 * contents are the previous frame's and are undefined on the first: a renderer that shows a whole page paints all of
 * it every frame, and one that does not is responsible for its own history.
 *
 * Returns 1 on success. A size of 0 or less, or a context with no device behind it, returns 0 and leaves the previous
 * target bound. */
int AGGLBeginFrame(AGGLContext *context, int width, int height);
void AGGLEndFrame(AGGLContext *context);

/* **THE READBACK, IN THE WINDOW BUFFER'S OWN FORMAT AND ORIENTATION.** `(x, y)` is the source rectangle with a
 * TOP-DOWN origin — the same space `AGWindowDamage` takes and the space the window buffer is laid out in — so a
 * caller never has to think about GL's flipped Y. Each pixel is written as `0x00RRGGBB`, rows at `dst_stride_bytes`
 * apart. Returns 1 when pixels were written.
 *
 * This is the door a `CGImage` is made from: the memory is already the layout `CGImageCreate` wants. */
int AGGLReadPixels(AGGLContext *context, int x, int y, int width, int height, uint32_t *dst,
		   int dst_stride_bytes);

/* **DRAW THE TARGET INTO A WINDOW, AND PRESENT IT.** `(x, y)` is in the window's BUFFER pixels, top-down. The whole
 * target is drawn, clipped to the window. Returns 0 when the compositor still holds the buffer a frame would go in,
 * which is ordinary — a caller simply draws again next frame and must NOT treat it as an error. This is route (1):
 * it owns the frame's begin/end, so it is for a window whose content IS the renderer's, not for a view inside a
 * CPU-drawn window. */
int AGGLPresentToWindow(AGGLContext *context, AGWindow *window, int x, int y);

/* **AN IMAGE FROM ELSEWHERE, AS A TEXTURE ON THIS CONTEXT.** `egl_image` is an `EGLImage` (typed `const void *` here
 * for the same reason the handles are) — what `wpe_fdo_egl_exported_image_get_egl_image` returns. Returns 0 on
 * failure. The texture is the caller's until `AGGLDeleteTexture`.
 *
 * **THE IMAGE IS BORROWED AND IS NEVER DESTROYED HERE, WHICH IS THE WHOLE CONTRACT OF THIS DOOR.** A producer keeps
 * ownership: `libwpe`'s exportable hands the host an image in `export_egl_image` and expects it back through
 * `wpe_view_backend_exportable_fdo_egl_dispatch_release_image` once the frame has been composited. So the order for a
 * host is `AGGLTextureFromImage` → `AGGLBlitTexture` (or `AGGLReadPixels`) → `AGGLDeleteTexture` → that release call.
 * An image this file created itself — from a descriptor, in `AGGLTextureFromDmabuf` — is owned and destroyed here, and
 * the difference is kept because a seam that destroyed a foreign image would be freeing somebody else's frame. */
unsigned int AGGLTextureFromImage(AGGLContext *context, const void *egl_image, int width, int height);

/* **THE SAME DOOR FOR A BARE DESCRIPTOR**, which is what a compositor or a `zwp_linux_dmabuf_v1` client hands over:
 * one plane, `stride` bytes a row, `fourcc` an XRGB8888/ARGB8888 fourcc, `modifier` the DRM modifier or 0 for linear.
 * The descriptor is NOT taken: it stays the caller's to close, and is only read while the image is created. */
unsigned int AGGLTextureFromDmabuf(AGGLContext *context, int fd, int width, int height, int stride,
				   unsigned int fourcc, unsigned long long modifier);
void AGGLDeleteTexture(AGGLContext *context, unsigned int texture);

/* **THE PRODUCER HALF, WHICH IS WHAT MAKES THE IMPORT TESTABLE AND WHAT A RENDERER NEEDS TO HAND A FRAME OUT.** A
 * texture is wrapped as an `EGLImage` (`EGL_KHR_gl_texture_2D_image`), exported to a dmabuf
 * (`EGL_MESA_image_dma_buf_export`), and the descriptor is the caller's to close. `width` and `height` are the
 * texture's, which the caller made and therefore knows. `*stride`, `*fourcc` and `*modifier` are the driver's answers
 * — a descriptor is only describable by that triple, and every one of them has to come back rather than be guessed: a
 * driver may export ABGR when asked for a texture made in RGBA, and it may export a TILED layout, which an importer
 * given modifier 0 (linear) is right to refuse. Returns 1 on success; 0 when the driver cannot export, which is a
 * capability and not a fault. */
int AGGLExportTextureDmabuf(AGGLContext *context, unsigned int texture, int width, int height, int *fd,
			    int *stride, unsigned int *fourcc, unsigned long long *modifier);

/* **A TEXTURE DRAWN INTO THE CURRENT TARGET, WHICH IS THE WHOLE OF "COMPOSITE AN ENGINE'S FRAME".** Straight copy: no
 * blending, no texture coordinates invented, (0,0) of the texture at the bottom-left of the rectangle, in target
 * pixels. Returns 1 when it drew. */
int AGGLBlitTexture(AGGLContext *context, unsigned int texture, int x, int y, int width, int height);

/* **THE TWO DOORS THAT LET A CALLER PAINT WITHOUT SPEAKING GL.** A host has to clear behind its engine and sometimes
 * upload a bitmap of its own (a placeholder, an engine's software path, a snapshot); both are three lines over GL here
 * and twenty in every caller, and the twenty are the ones that get the channel order wrong.
 *
 * `AGGLFillRect` fills in TARGET pixels with a TOP-DOWN origin and an `0xRRGGBB` colour — the same space and the same
 * integer the readback writes and `AGWindowDamage` expects. It ignores the caller's scissor and clear-colour state
 * (it saves and restores the first, and overwrites the second, which no caller may rely on afterwards).
 *
 * `AGGLTextureFromPixels` uploads `0xRRGGBB` rows, `stride_bytes` apart, and returns a texture id or 0. Nearest
 * filtering, because a caller handing over exact pixels means them. */
int AGGLFillRect(AGGLContext *context, int x, int y, int width, int height, uint32_t rgb);
unsigned int AGGLTextureFromPixels(AGGLContext *context, const uint32_t *pixels, int width, int height,
				   int stride_bytes);

#ifdef __cplusplus
}
#endif

#endif /* AG_GL_H */
