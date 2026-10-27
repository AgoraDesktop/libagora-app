/*
 * AGGL.c — the client's one GPU door, implemented over EGL and GLES2.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * THE FOUR DECISIONS THIS FILE IS, in the order they constrain each other:
 *
 * 1. THE TARGET IS AN FBO, NOT A SURFACE. Agora's windows are shared-memory images the client draws and commits;
 *    there is no window system surface to render into and none is wanted. So EGL is used with no surface at all
 *    (`EGL_KHR_surfaceless_context`) and everything is drawn into a texture attached to an FBO. That is what makes
 *    a renderer's output a *picture* rather than a display connection, and it is why the readback below is a copy
 *    and not a swap.
 *
 * 2. THE EGL DISPLAY IS THE COMPOSITOR'S CONNECTION WHEN IT EXISTS, because a buffer allocated on another device is
 *    a dmabuf the compositor may or may not be able to sample, and "may not" is discovered at the worst moment. On
 *    the window server's own `wl_display`, an image exported here is importable there by construction.
 *
 * 3. EVERY EXTENSION ENTRY POINT IS RESOLVED, NEVER LINKED. `libEGL` exports the version 1.5 core and nothing else
 *    reliably; `eglCreateImageKHR` and its family are found by `eglGetProcAddress` or not at all, and asking a driver
 *    that does not have one is a NULL to check rather than a link error to read.
 *
 * 4. THE READBACK IS THE WINDOW BUFFER'S FORMAT, CONVERTED ON THE CPU. `GL_RGBA` is the only channel order GLES2
 *    guarantees, so the bytes arrive as R,G,B,A and are written out as `0x00RRGGBB` — the same integer the compositor
 *    reads and the same one `CGImageCreate` takes. A shader could write BGRA directly, but it would then have to be
 *    the caller's shader, and a renderer's output is not this file's to reorder.
 *
 * WHAT IS MEASURED HERE, AND WHAT IS NOT. The readback path is the one this build exercises: the probe in
 * `tests/gl_present.c` renders, reads back, presents into a window, and the compositor's own screenshot is what the
 * test asserts. The dmabuf door is exercised too — a texture is exported to a descriptor, the original is deleted,
 * and the frame is then rebuilt from the descriptor alone, so a test that passes cannot be passing on a retained
 * pointer. What is NOT measured here is a frame rate: no engine is linked yet, and a number invented now would be a
 * number in a comment nobody could reproduce.
 */

#include "AGGL.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef AG_HAVE_GL

/* **THE X11 HEADERS ARE NOT ON THIS PATH**, and EGL's platform header includes them by default on Linux. The window
 * server is Wayland-only; this define is how the same library is built on a machine with no Xlib development files at
 * all. `EGL_NO_X11` is Mesa's spelling and `MESA_EGL_NO_X11_HEADERS` is the older one; both are harmless.
 */
#ifndef EGL_NO_X11
#define EGL_NO_X11 1
#endif
#ifndef MESA_EGL_NO_X11_HEADERS
#define MESA_EGL_NO_X11_HEADERS 1
#endif

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

/* The two platform selectors are named here rather than relied on from a header version: `EGL/eglext.h` on an older
 * system does not carry them, and a duplicate definition is what `#ifndef` is for. */
#ifndef EGL_PLATFORM_WAYLAND_KHR
#define EGL_PLATFORM_WAYLAND_KHR 0x31D8
#endif
#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif

struct AGGLTexture {
	GLuint texture;
	EGLImageKHR image;	/* recorded so the texture's lifetime can be tied to it */
	int owns_image;		/* **WHO MAY DESTROY IT.** 1 for an image this file created from a descriptor, 0 for one a
				 * producer lent us — a `wpebackend-fdo` frame's image is the exportable's, and destroying it
				 * here would be this seam releasing another component's resource. */
};

struct AGGLContext {
	EGLDisplay display;
	EGLConfig config;
	EGLContext context;
	int ready;
	int wayland_display;
	int gbm_display;

	/* The extensions this context was actually given, not the ones the build hoped for. */
	int import_dmabuf;
	int import_modifiers;
	int gl_texture_image;
	int export_dmabuf;
	int surfaceless;

	int max_texture_size;
	char vendor[64];
	char renderer[64];
	char version[64];

	/* The offscreen target: one texture, one FBO, remade only when the size changes. */
	GLuint target_texture;
	GLuint target_framebuffer;
	int width;
	int height;

	/* The readback, sized on demand. */
	unsigned char *scratch;
	size_t scratch_size;

	/* The blit program, built the first time a texture is composited. */
	GLuint blit_program;
	GLint blit_position;
	GLint blit_uv;
	GLint blit_sampler;

	struct AGGLTexture *textures;
	int texture_count;

	/* Every extension entry point this file uses. NULL means the driver does not have it. */
	PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display;
	PFNEGLCREATEIMAGEKHRPROC create_image;
	PFNEGLDESTROYIMAGEKHRPROC destroy_image;
	PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target_texture;
	PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC export_dmabuf_query;
	PFNEGLEXPORTDMABUFIMAGEMESAPROC export_dmabuf_image;
};

/* ----------------------------------------------------------------------------------------------------------------
 * small helpers
 * ---------------------------------------------------------------------------------------------------------------- */

static int extension_has(const char *extensions, const char *name)
{
	size_t length;
	const char *at;

	if (extensions == NULL || name == NULL || name[0] == '\0') {
		return 0;
	}
	length = strlen(name);
	for (at = extensions; (at = strstr(at, name)) != NULL; at += length) {
		/* A SUBSTRING IS NOT A NAME: `EGL_KHR_image` is a PREFIX of `EGL_KHR_image_base`, and checking one for the
		 * other is how a driver without the base extension gets asked for an image. Both ends have to be a
		 * separator or the string itself. */
		if ((at == extensions || at[-1] == ' ') && (at[length] == '\0' || at[length] == ' ')) {
			return 1;
		}
	}
	return 0;
}

static void copy_string(char *destination, size_t size, const char *source)
{
	if (size == 0) {
		return;
	}
	snprintf(destination, size, "%s", source != NULL ? source : "");
}

/* **A FAILED CONTEXT IS DESTROYED RATHER THAN PARTIALLY RETURNED**, because every door below assumes a current
 * context and a caller has no way to ask "is this usable" before using it.
 *
 * Two functions rather than one because the platform choice in `AGGLContextCreate` brings a context up on the STACK to
 * find out what device a platform gives: releasing and freeing are separate acts, and `free` on a stack object is how
 * a probe like that becomes a crash. */
static void gl_context_release(AGGLContext *context)
{
	if (context == NULL) {
		return;
	}
	/* **THE GL HALF ONLY WHEN THERE IS A CONTEXT TO NAME IT TO.** A creation that failed before
	 * `eglMakeCurrent` has no current context, and `glDelete*` against none is undefined rather than harmless. */
	if (context->ready) {
		int i;

		for (i = 0; i < context->texture_count; i++) {
			if (context->textures[i].owns_image && context->textures[i].image != EGL_NO_IMAGE_KHR &&
			    context->destroy_image != NULL) {
				context->destroy_image(context->display, context->textures[i].image);
			}
			if (context->textures[i].texture != 0) {
				glDeleteTextures(1, &context->textures[i].texture);
			}
		}
		if (context->target_framebuffer != 0) {
			glDeleteFramebuffers(1, &context->target_framebuffer);
		}
		if (context->target_texture != 0) {
			glDeleteTextures(1, &context->target_texture);
		}
		if (context->blit_program != 0) {
			glDeleteProgram(context->blit_program);
		}
	}
	free(context->textures);
	free(context->scratch);
	if (context->display != EGL_NO_DISPLAY) {
		eglMakeCurrent(context->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		if (context->context != EGL_NO_CONTEXT) {
			eglDestroyContext(context->display, context->context);
		}
		/* **`eglTerminate` IS DELIBERATELY NOT CALLED, AND THE MEASUREMENT IS WHY.** An `EGLDisplay` is a
		 * PROCESS-WIDE object: two calls to `eglGetPlatformDisplay` for the same platform return the same handle, so
		 * terminating it when one context goes takes the device away from every other context in the process — which
		 * this file's own probe found the hard way, as a framebuffer that reported status 0 because the display under
		 * it had been terminated by a sibling's teardown. There is one device per process; the handle goes when the
		 * process does. */
	}
}

static void gl_context_teardown(AGGLContext *context)
{
	gl_context_release(context);
	free(context);
}

/* **"SOFTWARE" IS A WORD IN A RENDERER STRING, WHICH IS ALL A CLIENT IS GIVEN.** The names are the ones the drivers
 * actually report — `llvmpipe` and `softpipe` from Mesa, `swrast` from the classic paths, `Apple Software Renderer`,
 * and Zink on a software driver's back. It is a heuristic and it is only ever used to PREFER one platform over another
 * where both work, so a wrong answer costs a slower driver and never a wrong picture. */
static int gl_string_is_software(const char *renderer)
{
	static const char *names[] = { "llvmpipe", "softpipe", "swrast", "software", "zink" };
	size_t i;

	if (renderer == NULL) {
		return 1;
	}
	for (i = 0; i < sizeof names / sizeof names[0]; i++) {
		if (strstr(renderer, names[i]) != NULL) {
			return 1;
		}
	}
	return 0;
}

static int gl_is_software(void)
{
	return gl_string_is_software((const char *)glGetString(GL_RENDERER));
}

/* **A CANDIDATE CONTEXT SHARES THE ENTRY POINTS AND NOTHING ELSE.** The proc pointers are per-library and not
 * per-display, so a second display is brought up with the first one's table; everything else starts empty. */
static void egl_platform_candidate_init(AGGLContext *candidate, const AGGLContext *context)
{
	memset(candidate, 0, sizeof *candidate);
	candidate->get_platform_display = context->get_platform_display;
	candidate->create_image = context->create_image;
	candidate->destroy_image = context->destroy_image;
	candidate->image_target_texture = context->image_target_texture;
	candidate->export_dmabuf_query = context->export_dmabuf_query;
	candidate->export_dmabuf_image = context->export_dmabuf_image;
	candidate->display = EGL_NO_DISPLAY;
	candidate->context = EGL_NO_CONTEXT;
}

/* **ONE ATTEMPT AT A DISPLAY, IN THE ONE ORDER THAT WORKS.** Bind the API, choose a config, make a context, make it
 * current with no surface at all. Split out because it is tried TWICE — on the compositor's connection and then on the
 * surfaceless platform — and a half-initialised display is not something a caller can recover from. Each failure says
 * which step it was, because a NULL context is otherwise indistinguishable from "this machine has no GPU". */
static int gl_context_bring_up(AGGLContext *context, EGLenum platform, void *native,
			       const char *label, const EGLint *config_attributes,
			       const EGLint *context_attributes)
{
	int major = 0;
	int minor = 0;
	EGLint count = 0;

	context->display = context->get_platform_display(platform, native, NULL);
	if (context->display == EGL_NO_DISPLAY) {
		fprintf(stderr, "AGGL: no EGL display for %s\n", label);
		return 0;
	}
	if (!eglInitialize(context->display, &major, &minor)) {
		fprintf(stderr, "AGGL: eglInitialize failed for %s (0x%04x)\n", label, (unsigned)eglGetError());
		context->display = EGL_NO_DISPLAY;
		return 0;
	}
	if (!eglBindAPI(EGL_OPENGL_ES_API)) {
		fprintf(stderr, "AGGL: %s does not offer OpenGL ES\n", label);
		return 0;
	}
	/* **THE SURFACE-TYPE FILTER IS A HINT AND A LIAR.** A Wayland display offers WINDOW configs and no pbuffers, and
	 * the surfaceless platform is the reverse, so one attribute list cannot match both. It is tried as written and
	 * then without the filter at all: nothing here ever creates a surface, so what the config can back is irrelevant
	 * and its RGBA8/ES2 half is the whole question. */
	if (!eglChooseConfig(context->display, config_attributes, &context->config, 1, &count) || count < 1) {
		EGLint without_surface_type[16];
		int attribute = 0;
		int source = 0;

		while (config_attributes[source] != EGL_NONE) {
			if (config_attributes[source] == EGL_SURFACE_TYPE) {
				source += 2;
				continue;
			}
			without_surface_type[attribute++] = config_attributes[source++];
		}
		without_surface_type[attribute] = EGL_NONE;
		if (!eglChooseConfig(context->display, without_surface_type, &context->config, 1, &count) ||
		    count < 1) {
			fprintf(stderr, "AGGL: %s has no RGBA8 ES2 config\n", label);
			return 0;
		}
	}
	context->context = eglCreateContext(context->display, context->config, EGL_NO_CONTEXT,
					    context_attributes);
	if (context->context == EGL_NO_CONTEXT) {
		fprintf(stderr, "AGGL: %s could not make an ES2 context (0x%04x)\n", label,
			(unsigned)eglGetError());
		return 0;
	}
	/* **NO SURFACE IS THE POINT, SO THE EXTENSION IS THE DOOR.** Without `EGL_KHR_surfaceless_context` there is no
	 * legal way to make a context current without one, and a pbuffer would be a surface nobody shows — refused
	 * rather than papered over with a 1x1 pbuffer that would then be the thing all output went to. */
	if (!eglMakeCurrent(context->display, EGL_NO_SURFACE, EGL_NO_SURFACE, context->context)) {
		fprintf(stderr, "AGGL: %s cannot make a context current without a surface (0x%04x)\n", label,
			(unsigned)eglGetError());
		return 0;
	}
	return 1;
}

/* **THE GBM PLATFORM IS THE ONE THAT MATCHES A WINDOW'S BUFFERS**, so it is tried first when a device is given and the
 * display it makes is the one an import will be legal on. Everything after the bring-up is shared with the other
 * constructors: the same context attributes, the same extension probing, the same offscreen target. */
AGGLContext *AGGLContextCreateWithGBM(void *gbm_device)
{
	AGGLContext *context;
	const char *egl_extensions;
	EGLint config_attributes[] = {
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_NONE
	};
	EGLint context_attributes[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };

	if (gbm_device == NULL) {
		return NULL;
	}
	context = calloc(1, sizeof *context);
	if (context == NULL) {
		return NULL;
	}
	context->display = EGL_NO_DISPLAY;
	context->context = EGL_NO_CONTEXT;
	context->get_platform_display = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
	if (context->get_platform_display == NULL) {
		gl_context_teardown(context);
		return NULL;
	}
	context->create_image = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
	context->destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
	context->image_target_texture = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
		eglGetProcAddress("glEGLImageTargetTexture2DOES");
	context->export_dmabuf_query = (PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC)
		eglGetProcAddress("eglExportDMABUFImageQueryMESA");
	context->export_dmabuf_image = (PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC)
		eglGetProcAddress("eglExportDMABUFImageQueryMESA") != NULL ?
		(PFNEGLEXPORTDMABUFIMAGEMESAPROC)eglGetProcAddress("eglExportDMABUFImageMESA") : NULL;
	if (!gl_context_bring_up(context, EGL_PLATFORM_GBM_KHR, gbm_device, "the GBM device", config_attributes,
				 context_attributes)) {
		gl_context_teardown(context);
		return NULL;
	}
	context->gbm_display = 1;
	egl_extensions = eglQueryString(context->display, EGL_EXTENSIONS);
	context->import_dmabuf = extension_has(egl_extensions, "EGL_EXT_image_dma_buf_import");
	context->import_modifiers = extension_has(egl_extensions, "EGL_EXT_image_dma_buf_import_modifiers");
	context->gl_texture_image = extension_has(egl_extensions, "EGL_KHR_gl_texture_2D_image");
	context->export_dmabuf = extension_has(egl_extensions, "EGL_MESA_image_dma_buf_export");
	context->surfaceless = extension_has(egl_extensions, "EGL_KHR_surfaceless_context");
	copy_string(context->vendor, sizeof context->vendor, eglQueryString(context->display, EGL_VENDOR));
	copy_string(context->renderer, sizeof context->renderer, (const char *)glGetString(GL_RENDERER));
	copy_string(context->version, sizeof context->version, (const char *)glGetString(GL_VERSION));
	glGetIntegerv(GL_MAX_TEXTURE_SIZE, &context->max_texture_size);
	context->ready = 1;
	return context;
}

AGGLContext *AGGLContextCreate(AGWindowServer *server)
{
	AGGLContext *context;
	const char *egl_extensions;
	void *native_display;
	EGLint config_attributes[] = {
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_NONE
	};
	EGLint context_attributes[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	int brought_up = 0;

	context = calloc(1, sizeof *context);
	if (context == NULL) {
		return NULL;
	}
	context->display = EGL_NO_DISPLAY;
	context->context = EGL_NO_CONTEXT;

	context->get_platform_display = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
		eglGetProcAddress("eglGetPlatformDisplayEXT");
	if (context->get_platform_display == NULL) {
		/* The one extension this file cannot do without: `eglGetDisplay(EGL_DEFAULT_DISPLAY)` would name an X11
		 * display on a machine that may not have one, so a driver without the platform selector is refused
		 * rather than guessed at. */
		fprintf(stderr, "AGGL: this EGL has no eglGetPlatformDisplayEXT\n");
		gl_context_teardown(context);
		return NULL;
	}
	context->create_image = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
	context->destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
	context->image_target_texture = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)
		eglGetProcAddress("glEGLImageTargetTexture2DOES");
	context->export_dmabuf_query = (PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC)
		eglGetProcAddress("eglExportDMABUFImageQueryMESA");
	context->export_dmabuf_image = (PFNEGLEXPORTDMABUFIMAGEMESAPROC)
		eglGetProcAddress("eglExportDMABUFImageMESA");

	/* **THE COMPOSITOR'S CONNECTION FIRST, THE SURFACELESS PLATFORM SECOND.** The first shares the compositor's device
	 * and is what makes an exported image samplable by it; the second needs no display at all and is what a headless
	 * test — or a compositor that imports nothing — falls back to. The first failure is not printed: "the compositor
	 * imports nothing" is an ordinary state on the CPU renderer, and a warning there would be noise in every headless
	 * run. The second one is printed, because a machine with no GPU at all is the case a person needs explained. */
	native_display = AGWindowServerNativeDisplay(server);
	if (native_display != NULL) {
		brought_up = gl_context_bring_up(context, EGL_PLATFORM_WAYLAND_KHR, native_display,
						 "the compositor's display", config_attributes,
						 context_attributes);
		if (brought_up) {
			context->wayland_display = 1;
		} else {
			context->display = EGL_NO_DISPLAY;
			context->context = EGL_NO_CONTEXT;
		}
	}
	if (!brought_up) {
		brought_up = gl_context_bring_up(context, EGL_PLATFORM_SURFACELESS_MESA,
						 EGL_DEFAULT_DISPLAY, "the surfaceless platform",
						 config_attributes, context_attributes);
	}
	if (!brought_up) {
		gl_context_teardown(context);
		return NULL;
	}

	/* **A SOFTWARE RASTERISER ON THE SHARED CONNECTION IS NOT THE ANSWER; THE SURFACELESS PLATFORM MAY BE.** Measured
	 * at the top of this file: on this machine the Wayland EGL platform resolves to llvmpipe because the compositor
	 * offers no `wl_drm`, and the surfaceless platform resolves to the card. So a software renderer is a reason to try
	 * the other platform and, if that one is hardware, to keep it — a host that asked for a GPU is not served by being
	 * told its frames came from LLVM. The reverse trade is never made: a HARDWARE connection is kept even if surfaceless
	 * might be hardware too, because the connection is the one that can share.
	 *
	 * The candidate is brought up ON THE STACK, which is why releasing and freeing are separate functions: a platform
	 * probe is not a context anybody keeps. */
	if (context->wayland_display && gl_is_software()) {
		AGGLContext candidate;
		egl_platform_candidate_init(&candidate, context);
		if (gl_context_bring_up(&candidate, EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY,
					"the surfaceless platform", config_attributes, context_attributes)) {
			if (gl_is_software()) {
				/* Software on both: the shared connection stays, because sharing is what it was for. */
				candidate.ready = 1;
				gl_context_release(&candidate);
				eglMakeCurrent(context->display, EGL_NO_SURFACE, EGL_NO_SURFACE, context->context);
			} else {
				EGLDisplay previous_display = context->display;
				EGLContext previous_context = context->context;

				context->display = candidate.display;
				context->config = candidate.config;
				context->context = candidate.context;
				context->wayland_display = 0;
				/* The candidate's handles are the context's now: emptying it makes the release below a no-op
				 * rather than a destroy of what was just adopted. */
				memset(&candidate, 0, sizeof candidate);
				candidate.display = EGL_NO_DISPLAY;
				candidate.context = EGL_NO_CONTEXT;
				candidate.ready = 1;
				gl_context_release(&candidate);
				/* **THE OLD CONTEXT GOES BEFORE THE NEW ONE IS MADE CURRENT, AND THE ORDER IS THE WHOLE OF IT.** An
				 * `EGLDisplay` may be one object per process whatever platform asked for it — so un-currenting "the
				 * previous display" after making the new context current released the new one too, and MEASURED it as
				 * an EGL context that was current by the API's account and `NULL` to `glGetString`. So: release
				 * everything, destroy what is no longer wanted, and then make the keeper current. */
				eglMakeCurrent(previous_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
				eglDestroyContext(previous_display, previous_context);
				eglMakeCurrent(context->display, EGL_NO_SURFACE, EGL_NO_SURFACE, context->context);
			}
		}
	}

	egl_extensions = eglQueryString(context->display, EGL_EXTENSIONS);
	context->import_dmabuf = extension_has(egl_extensions, "EGL_EXT_image_dma_buf_import");
	context->import_modifiers =
		extension_has(egl_extensions, "EGL_EXT_image_dma_buf_import_modifiers");
	context->gl_texture_image = extension_has(egl_extensions, "EGL_KHR_gl_texture_2D_image");
	context->export_dmabuf = extension_has(egl_extensions, "EGL_MESA_image_dma_buf_export");
	context->surfaceless = extension_has(egl_extensions, "EGL_KHR_surfaceless_context");
	copy_string(context->vendor, sizeof context->vendor, eglQueryString(context->display, EGL_VENDOR));
	copy_string(context->renderer, sizeof context->renderer, (const char *)glGetString(GL_RENDERER));
	copy_string(context->version, sizeof context->version, (const char *)glGetString(GL_VERSION));
	glGetIntegerv(GL_MAX_TEXTURE_SIZE, &context->max_texture_size);
	context->ready = 1;
	return context;
}

void AGGLContextDestroy(AGGLContext *context)
{
	gl_context_teardown(context);	/* releases, then frees */
}

void AGGLContextInfo(const AGGLContext *context, AGGLInfo *info)
{
	if (info == NULL) {
		return;
	}
	memset(info, 0, sizeof *info);
	if (context == NULL) {
		return;
	}
	info->available = context->ready;
	info->wayland_display = context->wayland_display;
	info->gbm_display = context->gbm_display;
	info->import_dmabuf = context->import_dmabuf;
	info->import_dmabuf_modifiers = context->import_modifiers;
	info->gl_texture_image = context->gl_texture_image;
	info->export_dmabuf = context->export_dmabuf;
	info->surfaceless = context->surfaceless;
	info->max_texture_size = context->max_texture_size;
	memcpy(info->vendor, context->vendor, sizeof info->vendor);
	memcpy(info->renderer, context->renderer, sizeof info->renderer);
	memcpy(info->version, context->version, sizeof info->version);
}

int AGGLMakeCurrent(AGGLContext *context)
{
	if (context == NULL || !context->ready) {
		return 0;
	}
	return eglMakeCurrent(context->display, EGL_NO_SURFACE, EGL_NO_SURFACE, context->context) ? 1 : 0;
}

void AGGLContextHandles(const AGGLContext *context, void **display, void **config, void **context_out)
{
	if (display != NULL) {
		*display = (context != NULL) ? (void *)context->display : NULL;
	}
	if (config != NULL) {
		*config = (context != NULL) ? (void *)context->config : NULL;
	}
	if (context_out != NULL) {
		*context_out = (context != NULL) ? (void *)context->context : NULL;
	}
}

/* ----------------------------------------------------------------------------------------------------------------
 * the offscreen target
 * ---------------------------------------------------------------------------------------------------------------- */

int AGGLBeginFrame(AGGLContext *context, int width, int height)
{
	GLenum status;

	if (context == NULL || !context->ready || width <= 0 || height <= 0) {
		return 0;
	}
	if (width != context->width || height != context->height || context->target_framebuffer == 0) {
		if (context->target_texture != 0) {
			glDeleteTextures(1, &context->target_texture);
			context->target_texture = 0;
		}
		glGenTextures(1, &context->target_texture);
		glBindTexture(GL_TEXTURE_2D, context->target_texture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		/* **RGBA, BECAUSE GLES2 GUARANTEES NOTHING ELSE FOR A RENDER TARGET**, and a renderer's own frames are
		 * RGBA-or-premultiplied-BGRA in practice — the conversion to the window buffer's order happens on
		 * readback, in one place. */
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
		glBindTexture(GL_TEXTURE_2D, 0);

		if (context->target_framebuffer == 0) {
			glGenFramebuffers(1, &context->target_framebuffer);
		}
		glBindFramebuffer(GL_FRAMEBUFFER, context->target_framebuffer);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
				       context->target_texture, 0);
		status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
		if (status != GL_FRAMEBUFFER_COMPLETE) {
			fprintf(stderr, "AGGL: framebuffer incomplete 0x%04x at %dx%d\n", (unsigned)status,
				width, height);
			context->width = 0;
			context->height = 0;
			glBindFramebuffer(GL_FRAMEBUFFER, 0);
			return 0;
		}
		context->width = width;
		context->height = height;
	} else {
		glBindFramebuffer(GL_FRAMEBUFFER, context->target_framebuffer);
	}
	glViewport(0, 0, width, height);
	return 1;
}

void AGGLEndFrame(AGGLContext *context)
{
	if (context == NULL || !context->ready) {
		return;
	}
	/* **FINISH, BECAUSE EVERYTHING THAT READS THE TARGET IS A READBACK.** `glFlush` would be enough for a driver that
	 * only had to order commands, but the next call here is `glReadPixels` into process memory, so the sync is going
	 * to happen anyway; doing it here makes the frame boundary the place it happens rather than a surprise in the
	 * middle of a composite. */
	glFinish();
}

/* ----------------------------------------------------------------------------------------------------------------
 * readback
 * ---------------------------------------------------------------------------------------------------------------- */

/* **ONE READBACK, PLACED ANYWHERE IN ANY STRIDE.** `(sx, sy)` is a TOP-DOWN offset into the target; `(dx, dy)` is
 * where the rectangle lands in `dst`, whose rows are `dst_stride` bytes apart. The window buffer and a caller's own
 * bitmap are the same door with different arguments, which is why `AGGLReadPixels` and `AGGLPresentToWindow` are
 * three lines apart in this file and share this. */
static int gl_read_into(AGGLContext *context, int sx, int sy, int width, int height, uint32_t *dst,
			int dst_stride, int dx, int dy)
{
	size_t needed;
	int row;

	if (context == NULL || !context->ready || dst == NULL || width <= 0 || height <= 0) {
		return 0;
	}
	if (sx < 0 || sy < 0 || sx + width > context->width || sy + height > context->height) {
		return 0;
	}
	needed = (size_t)width * (size_t)height * 4u;
	if (needed > context->scratch_size) {
		unsigned char *grown = realloc(context->scratch, needed);

		if (grown == NULL) {
			return 0;
		}
		context->scratch = grown;
		context->scratch_size = needed;
	}

	glPixelStorei(GL_PACK_ALIGNMENT, 1);
	/* **GL'S Y IS THE FLIP, AND IT IS DONE ONCE, HERE.** The read starts at the rectangle's bottom row because GL
	 * counts rows upward from the bottom of the framebuffer; the top-down convention this seam uses everywhere else
	 * makes that `height - (sy + height)` rows up. The row loop then walks the scratch backwards, so the caller's
	 * first row is the image's top. */
	glReadPixels(sx, context->height - (sy + height), width, height, GL_RGBA, GL_UNSIGNED_BYTE,
		     context->scratch);
	if (glGetError() != GL_NO_ERROR) {
		return 0;
	}

	for (row = 0; row < height; row++) {
		const unsigned char *source = context->scratch + (size_t)(height - 1 - row) * (size_t)width * 4u;
		unsigned char *destination = (unsigned char *)dst + (size_t)(dy + row) * (size_t)dst_stride +
					     (size_t)dx * 4u;
		uint32_t *out = (uint32_t *)destination;
		int column;

		for (column = 0; column < width; column++) {
			out[column] = ((uint32_t)source[column * 4 + 0] << 16) |
				      ((uint32_t)source[column * 4 + 1] << 8) |
				      ((uint32_t)source[column * 4 + 2]);
		}
	}
	return 1;
}

int AGGLReadPixels(AGGLContext *context, int x, int y, int width, int height, uint32_t *dst,
		   int dst_stride_bytes)
{
	return gl_read_into(context, x, y, width, height, dst, dst_stride_bytes, 0, 0);
}

int AGGLPresentToWindow(AGGLContext *context, AGWindow *window, int x, int y)
{
	uint32_t *pixels;
	int stride = 0;
	int buffer_width = 0;
	int buffer_height = 0;
	int width;
	int height;
	int source_x = 0;
	int source_y = 0;
	int drew;

	if (context == NULL || !context->ready || window == NULL || context->width <= 0 || context->height <= 0) {
		return 0;
	}
	pixels = AGWindowBeginFrameSized(window, &stride, &buffer_width, &buffer_height);
	if (pixels == NULL) {
		/* The compositor still holds the buffer a frame would go in. Ordinary: draw again next frame. */
		return 0;
	}
	width = context->width;
	height = context->height;
	if (x < 0) {
		source_x = -x;
		width += x;
		x = 0;
	}
	if (y < 0) {
		source_y = -y;
		height += y;
		y = 0;
	}
	if (x + width > buffer_width) {
		width = buffer_width - x;
	}
	if (y + height > buffer_height) {
		height = buffer_height - y;
	}
	if (width <= 0 || height <= 0) {
		AGWindowEndFrame(window);
		return 0;
	}
	drew = gl_read_into(context, source_x, source_y, width, height, pixels, stride, x, y);
	if (drew) {
		AGWindowDamage(window, x, y, width, height);
	}
	AGWindowEndFrame(window);
	return drew;
}

/* ----------------------------------------------------------------------------------------------------------------
 * textures: images in, images out
 * ---------------------------------------------------------------------------------------------------------------- */

static struct AGGLTexture *gl_texture_record(AGGLContext *context, GLuint texture)
{
	int i;

	for (i = 0; i < context->texture_count; i++) {
		if (context->textures[i].texture == texture) {
			return &context->textures[i];
		}
	}
	return NULL;
}

static unsigned int gl_texture_register(AGGLContext *context, GLuint texture, EGLImageKHR image,
				       int owns_image)
{
	struct AGGLTexture *grown;

	grown = realloc(context->textures, (size_t)(context->texture_count + 1) * sizeof *grown);
	if (grown == NULL) {
		return 0;
	}
	context->textures = grown;
	context->textures[context->texture_count].texture = texture;
	context->textures[context->texture_count].image = image;
	context->textures[context->texture_count].owns_image = owns_image;
	context->texture_count++;
	return texture;
}

static unsigned int gl_texture_wrap(AGGLContext *context, EGLImageKHR image, int owns_image)
{
	GLuint texture = 0;

	if (image == EGL_NO_IMAGE_KHR || context->image_target_texture == NULL) {
		return 0;
	}
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	while (glGetError() != GL_NO_ERROR) {
		/* Drain: an error left over from a caller's own drawing is not this bind's verdict. */
	}
	context->image_target_texture(GL_TEXTURE_2D, (GLeglImageOES)image);
	if (glGetError() != GL_NO_ERROR) {
		glBindTexture(GL_TEXTURE_2D, 0);
		glDeleteTextures(1, &texture);
		return 0;
	}
	glBindTexture(GL_TEXTURE_2D, 0);
	if (gl_texture_register(context, texture, image, owns_image) == 0) {
		glDeleteTextures(1, &texture);
		return 0;
	}
	return texture;
}

unsigned int AGGLTextureFromPixels(AGGLContext *context, const uint32_t *pixels, int width, int height,
				   int stride_bytes)
{
	unsigned char *rgba;
	GLuint texture = 0;
	int x, y;

	if (context == NULL || !context->ready || pixels == NULL || width <= 0 || height <= 0 ||
	    width > context->max_texture_size || height > context->max_texture_size ||
	    stride_bytes < width * 4) {
		return 0;
	}
	rgba = malloc((size_t)width * (size_t)height * 4u);
	if (rgba == NULL) {
		return 0;
	}
	for (y = 0; y < height; y++) {
		const uint32_t *row = (const uint32_t *)((const unsigned char *)pixels +
							 (size_t)y * (size_t)stride_bytes);

		for (x = 0; x < width; x++) {
			unsigned char *out = rgba + ((size_t)y * (size_t)width + (size_t)x) * 4u;

			/* **0x00RRGGBB IN, R,G,B,A OUT, IN ONE PLACE.** The window buffer's integers are `0x00RRGGBB`, so on a
			 * little-endian machine the bytes in memory are B,G,R,0 — an upload of the buffer's bytes as if they
			 * were RGBA is the classic blue-for-red bug, and it is why this conversion exists rather than a
			 * `GL_BGRA` that GLES2 does not guarantee. */
			out[0] = (unsigned char)((row[x] >> 16) & 0xff);
			out[1] = (unsigned char)((row[x] >> 8) & 0xff);
			out[2] = (unsigned char)(row[x] & 0xff);
			out[3] = 0xff;
		}
	}
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
	glBindTexture(GL_TEXTURE_2D, 0);
	free(rgba);
	if (glGetError() != GL_NO_ERROR ||
	    gl_texture_register(context, texture, EGL_NO_IMAGE_KHR, 0) == 0) {
		glDeleteTextures(1, &texture);
		return 0;
	}
	return texture;
}

unsigned int AGGLTextureFromImage(AGGLContext *context, const void *egl_image, int width, int height)
{
	(void)width;
	(void)height;
	if (context == NULL || !context->ready || egl_image == NULL) {
		return 0;
	}
	/* **BORROWED, NOT ADOPTED.** The image belongs to whoever exported it: `wpe_view_backend_exportable_fdo_egl`'s
	 * client callback hands one over and the host RETURNS it with
	 * `wpe_view_backend_exportable_fdo_egl_dispatch_release_image` once the frame has been used, so destroying it
	 * from this door would free the engine's frame twice. The caller deletes this texture and then releases the image
	 * by its own contract, in that order. */
	return gl_texture_wrap(context, (EGLImageKHR)(uintptr_t)egl_image, 0);
}

/* **ONE PLACE BUILDS THE IMPORT ATTRIBUTES.** The texture door and the render-target door import the same kind of buffer
 * and would otherwise disagree about which plane attributes they send — the sort of difference that works on one driver
 * and fails on the next. */
static EGLImageKHR gl_image_from_dmabuf(AGGLContext *context, int fd, int width, int height, int stride,
					unsigned int fourcc, unsigned long long modifier)
{
	EGLint attributes[24];
	int at = 0;

	if (context == NULL || !context->ready || !context->import_dmabuf || context->create_image == NULL) {
		return EGL_NO_IMAGE_KHR;
	}
	if (fd < 0 || width <= 0 || height <= 0 || stride <= 0 || width > context->max_texture_size ||
	    height > context->max_texture_size) {
		return EGL_NO_IMAGE_KHR;
	}
	attributes[at++] = EGL_WIDTH;
	attributes[at++] = width;
	attributes[at++] = EGL_HEIGHT;
	attributes[at++] = height;
	attributes[at++] = EGL_LINUX_DRM_FOURCC_EXT;
	attributes[at++] = (EGLint)fourcc;
	attributes[at++] = EGL_DMA_BUF_PLANE0_FD_EXT;
	attributes[at++] = fd;
	attributes[at++] = EGL_DMA_BUF_PLANE0_OFFSET_EXT;
	attributes[at++] = 0;
	attributes[at++] = EGL_DMA_BUF_PLANE0_PITCH_EXT;
	attributes[at++] = stride;
	if (context->import_modifiers && modifier != 0ULL) {
		/* **THE MODIFIER IS ONLY SENT WHEN IT MEANS SOMETHING.** `EGL_DMA_BUF_PLANE0_MODIFIER_*` arrived with the
		 * modifiers extension, and a driver given the attribute without it is entitled to fail the image; linear is
		 * the absence of the attribute, which is why 0 is left out rather than sent as a pair of zeroes. */
		attributes[at++] = EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT;
		attributes[at++] = (EGLint)(modifier & 0xffffffffULL);
		attributes[at++] = EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT;
		attributes[at++] = (EGLint)(modifier >> 32);
	}
	attributes[at++] = EGL_NONE;
	return context->create_image(context->display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attributes);
}

unsigned int AGGLTextureFromDmabuf(AGGLContext *context, int fd, int width, int height, int stride,
				   unsigned int fourcc, unsigned long long modifier)
{
	EGLImageKHR image;
	unsigned int texture;

	image = gl_image_from_dmabuf(context, fd, width, height, stride, fourcc, modifier);
	if (image == EGL_NO_IMAGE_KHR) {
		return 0;
	}
	texture = gl_texture_wrap(context, image, 1);
	if (texture == 0 && context->destroy_image != NULL) {
		context->destroy_image(context->display, image);
	}
	return texture;
}

/* ----------------------------------------------------------------------------------------------------------------
 * render targets
 * ---------------------------------------------------------------------------------------------------------------- */

struct AGGLRenderTarget {
	GLuint framebuffer;
	GLuint texture;
	EGLImageKHR image;
	int width;
	int height;
};

AGGLRenderTarget *AGGLRenderTargetFromDmabuf(AGGLContext *context, int fd, int width, int height, int stride,
					     unsigned int fourcc, unsigned long long modifier)
{
	AGGLRenderTarget *target;
	EGLImageKHR image;
	GLuint texture = 0;
	GLuint framebuffer = 0;
	GLenum status;

	if (context == NULL || !context->ready) {
		return NULL;
	}
	image = gl_image_from_dmabuf(context, fd, width, height, stride, fourcc, modifier);
	if (image == EGL_NO_IMAGE_KHR) {
		/* **THE REASON, BECAUSE A FAILED IMPORT IS OTHERWISE A FRAME THAT NEVER ARRIVES.** The numbers are what the
		 * attributes were built from, and the extension flags say which half of the import is missing. */
		fprintf(stderr, "AGGL: cannot import %dx%d stride %d fourcc 0x%08x modifier 0x%llx (import=%d modifiers=%d "
				"renderer=%s)\n", width, height, stride, fourcc, modifier, context->import_dmabuf,
			context->import_modifiers, context->renderer);
		return NULL;
	}
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	while (glGetError() != GL_NO_ERROR) {
		/* Drain whatever the caller left behind, so the next check is this call's verdict. */
	}
	context->image_target_texture(GL_TEXTURE_2D, (GLeglImageOES)image);
	{
		GLenum error = glGetError();

		if (error != GL_NO_ERROR) {
			/* **THE BIND IS THE STEP THAT FAILS WHEN THE BUFFER AND THE CONTEXT ARE NOT REALLY THE SAME DEVICE.** The
			 * error code is the only thing that distinguishes "this driver will not sample that layout" from "this is not
			 * my memory", and without it the symptom is a frame that never arrives. */
			fprintf(stderr, "AGGL: an imported %dx%d buffer (fourcc 0x%08x) would not bind as a texture: GL error "
					"0x%04x\n", width, height, fourcc, (unsigned)error);
			glBindTexture(GL_TEXTURE_2D, 0);
			glDeleteTextures(1, &texture);
			context->destroy_image(context->display, image);
			return NULL;
		}
	}
	glBindTexture(GL_TEXTURE_2D, 0);
	glGenFramebuffers(1, &framebuffer);
	glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
	status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	if (status != GL_FRAMEBUFFER_COMPLETE) {
		fprintf(stderr, "AGGL: the imported buffer cannot be rendered into (status 0x%04x)\n", (unsigned)status);
		glDeleteFramebuffers(1, &framebuffer);
		glDeleteTextures(1, &texture);
		context->destroy_image(context->display, image);
		return NULL;
	}
	target = calloc(1, sizeof *target);
	if (target == NULL) {
		glDeleteFramebuffers(1, &framebuffer);
		glDeleteTextures(1, &texture);
		context->destroy_image(context->display, image);
		return NULL;
	}
	target->framebuffer = framebuffer;
	target->texture = texture;
	target->image = image;
	target->width = width;
	target->height = height;
	return target;
}

int AGGLBeginRenderTarget(AGGLContext *context, AGGLRenderTarget *target)
{
	if (context == NULL || !context->ready || target == NULL) {
		return 0;
	}
	glBindFramebuffer(GL_FRAMEBUFFER, target->framebuffer);
	glViewport(0, 0, target->width, target->height);
	return 1;
}

void AGGLEndRenderTarget(AGGLContext *context)
{
	if (context == NULL || !context->ready) {
		return;
	}
	glFinish();
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void AGGLRenderTargetDestroy(AGGLContext *context, AGGLRenderTarget *target)
{
	if (context == NULL || target == NULL) {
		return;
	}
	if (context->ready) {
		glDeleteFramebuffers(1, &target->framebuffer);
		glDeleteTextures(1, &target->texture);
	}
	if (target->image != EGL_NO_IMAGE_KHR && context->destroy_image != NULL) {
		context->destroy_image(context->display, target->image);
	}
	free(target);
}

unsigned int AGGLTargetTexture(AGGLContext *context)
{
	return (context != NULL) ? context->target_texture : 0;
}

void AGGLDeleteTexture(AGGLContext *context, unsigned int texture)
{
	struct AGGLTexture *record;
	int index;

	if (context == NULL || texture == 0) {
		return;
	}
	record = gl_texture_record(context, texture);
	if (record == NULL) {
		return;
	}
	index = (int)(record - context->textures);
	if (record->owns_image && record->image != EGL_NO_IMAGE_KHR && context->destroy_image != NULL) {
		context->destroy_image(context->display, record->image);
	}
	glDeleteTextures(1, &record->texture);
	context->textures[index] = context->textures[context->texture_count - 1];
	context->texture_count--;
}

int AGGLExportTextureDmabuf(AGGLContext *context, unsigned int texture, int width, int height, int *fd,
			    int *stride, unsigned int *fourcc_out, unsigned long long *modifier_out)
{
	EGLint attributes[] = { EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE };
	EGLImageKHR image;
	EGLint strides[4] = { 0, 0, 0, 0 };
	EGLint offsets[4] = { 0, 0, 0, 0 };
	int descriptors[4] = { -1, -1, -1, -1 };
	int fourcc = 0;
	int planes = 0;
	EGLuint64KHR modifier = 0;
	int plane;

	if (context == NULL || !context->ready || !context->gl_texture_image || !context->export_dmabuf ||
	    context->create_image == NULL || context->export_dmabuf_query == NULL ||
	    context->export_dmabuf_image == NULL) {
		return 0;
	}
	(void)width;
	(void)height;
	/* **THE FRAME HAS TO BE FINISHED BEFORE IT IS EXPORTED, AND THE EXPORT HAS TO BE FINISHED BEFORE THE CALLER LETS GO.**
	 * `eglExportDMABUFImageMESA` may produce the descriptor by a blit into new memory, and the source texture is the
	 * caller's to delete the moment this returns. MEASURED, on a hardware driver: exporting and deleting immediately
	 * gave a descriptor that imported as solid black, because the copy had not run yet — llvmpipe hides this by being
	 * synchronous, which is exactly the kind of difference a test on one machine cannot be trusted with. */
	glFinish();
	image = context->create_image(context->display, context->context, EGL_GL_TEXTURE_2D_KHR,
				      (EGLClientBuffer)(uintptr_t)texture, attributes);
	if (image == EGL_NO_IMAGE_KHR) {
		return 0;
	}
	if (!context->export_dmabuf_query(context->display, image, &fourcc, &planes, &modifier) ||
	    planes < 1) {
		context->destroy_image(context->display, image);
		return 0;
	}
	if (!context->export_dmabuf_image(context->display, image, descriptors, strides, offsets)) {
		context->destroy_image(context->display, image);
		return 0;
	}
	context->destroy_image(context->display, image);
	/* Only the first plane is handed on: the images this door is for are single-plane RGB, and a multi-plane one
	 * would have its other descriptors closed rather than leaked. */
	for (plane = 1; plane < planes && plane < 4; plane++) {
		if (descriptors[plane] >= 0) {
			close(descriptors[plane]);
		}
	}
	glFinish();
	if (descriptors[0] < 0) {
		return 0;
	}
	if (fd != NULL) {
		*fd = descriptors[0];
	} else {
		close(descriptors[0]);
	}
	if (stride != NULL) {
		*stride = (int)strides[0];
	}
	if (fourcc_out != NULL) {
		*fourcc_out = (unsigned int)fourcc;
	}
	if (modifier_out != NULL) {
		*modifier_out = (unsigned long long)modifier;
	}
	return 1;
}

/* ----------------------------------------------------------------------------------------------------------------
 * the blit
 * ---------------------------------------------------------------------------------------------------------------- */

static const char *blit_vertex_source =
	"attribute vec2 position;\n"
	"attribute vec2 uv;\n"
	"varying vec2 v_uv;\n"
	"void main() {\n"
	"	gl_Position = vec4(position, 0.0, 1.0);\n"
	"	v_uv = uv;\n"
	"}\n";

static const char *blit_fragment_source =
	"precision mediump float;\n"
	"uniform sampler2D image;\n"
	"varying vec2 v_uv;\n"
	"void main() {\n"
	"	gl_FragColor = texture2D(image, v_uv);\n"
	"}\n";

static GLuint gl_compile(GLenum type, const char *source)
{
	GLuint shader = glCreateShader(type);
	GLint compiled = 0;

	if (shader == 0) {
		return 0;
	}
	glShaderSource(shader, 1, &source, NULL);
	glCompileShader(shader);
	glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
	if (!compiled) {
		char log[512];

		glGetShaderInfoLog(shader, (GLsizei)sizeof log, NULL, log);
		fprintf(stderr, "AGGL: shader compile failed: %s\n", log);
		glDeleteShader(shader);
		return 0;
	}
	return shader;
}

static int gl_blit_prepare(AGGLContext *context)
{
	GLuint vertex;
	GLuint fragment;
	GLuint program;
	GLint linked = 0;

	if (context->blit_program != 0) {
		return 1;
	}
	vertex = gl_compile(GL_VERTEX_SHADER, blit_vertex_source);
	if (vertex == 0) {
		return 0;
	}
	fragment = gl_compile(GL_FRAGMENT_SHADER, blit_fragment_source);
	if (fragment == 0) {
		glDeleteShader(vertex);
		return 0;
	}
	program = glCreateProgram();
	glAttachShader(program, vertex);
	glAttachShader(program, fragment);
	glBindAttribLocation(program, 0, "position");
	glBindAttribLocation(program, 1, "uv");
	glLinkProgram(program);
	glDeleteShader(vertex);
	glDeleteShader(fragment);
	glGetProgramiv(program, GL_LINK_STATUS, &linked);
	if (!linked) {
		char log[512];

		glGetProgramInfoLog(program, (GLsizei)sizeof log, NULL, log);
		fprintf(stderr, "AGGL: program link failed: %s\n", log);
		glDeleteProgram(program);
		return 0;
	}
	context->blit_program = program;
	context->blit_position = glGetAttribLocation(program, "position");
	context->blit_uv = glGetAttribLocation(program, "uv");
	context->blit_sampler = glGetUniformLocation(program, "image");
	return 1;
}

int AGGLFillRect(AGGLContext *context, int x, int y, int width, int height, uint32_t rgb)
{
	int left;
	int top;
	int right;
	int bottom;
	int scissor_was_on;
	int blend_was_on;

	if (context == NULL || !context->ready || width <= 0 || height <= 0 || context->width <= 0 ||
	    context->height <= 0) {
		return 0;
	}
	left = x > 0 ? x : 0;
	top = y > 0 ? y : 0;
	right = x + width < context->width ? x + width : context->width;
	bottom = y + height < context->height ? y + height : context->height;
	if (left >= right || top >= bottom) {
		return 0;
	}
	scissor_was_on = glIsEnabled(GL_SCISSOR_TEST);
	blend_was_on = glIsEnabled(GL_BLEND);
	glDisable(GL_BLEND);
	glEnable(GL_SCISSOR_TEST);
	/* **TOP-DOWN IN, BOTTOM-UP OUT.** The rectangle's rows run from `top` down to `bottom` and GL counts from the bottom,
	 * so the scissor's origin is the distance from the bottom to the rectangle's LAST row. */
	glScissor(left, context->height - bottom, right - left, bottom - top);
	glClearColor((GLfloat)((rgb >> 16) & 0xff) / 255.0f, (GLfloat)((rgb >> 8) & 0xff) / 255.0f,
		     (GLfloat)(rgb & 0xff) / 255.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	if (!scissor_was_on) {
		glDisable(GL_SCISSOR_TEST);
	}
	if (blend_was_on) {
		glEnable(GL_BLEND);
	}
	return glGetError() == GL_NO_ERROR;
}

static int gl_blit(AGGLContext *context, unsigned int texture, int x, int y, int width, int height, int flip);
static int gl_blit(AGGLContext *context, unsigned int texture, int x, int y, int width, int height, int flip)
{
	GLfloat quad[16];
	GLfloat left;
	GLfloat right;
	GLfloat bottom;
	GLfloat top;
	int blend_was_on;

	if (context == NULL || !context->ready || texture == 0 || width <= 0 || height <= 0 ||
	    context->width <= 0 || context->height <= 0) {
		return 0;
	}
	if (x >= context->width || y >= context->height || x + width <= 0 || y + height <= 0) {
		return 0;
	}
	if (!gl_blit_prepare(context)) {
		return 0;
	}
	left = 2.0f * (GLfloat)x / (GLfloat)context->width - 1.0f;
	right = 2.0f * (GLfloat)(x + width) / (GLfloat)context->width - 1.0f;
	bottom = 2.0f * (GLfloat)y / (GLfloat)context->height - 1.0f;
	top = 2.0f * (GLfloat)(y + height) / (GLfloat)context->height - 1.0f;
	/* A triangle strip with the texture's own origin at the rectangle's bottom-left, which is GL's. A caller whose
	 * image is top-down flips the two V values — one line, at the caller, where the knowledge is. */
	quad[0] = left;  quad[1] = bottom; quad[2] = 0.0f; quad[3] = flip ? 1.0f : 0.0f;
	quad[4] = right; quad[5] = bottom; quad[6] = 1.0f; quad[7] = flip ? 1.0f : 0.0f;
	quad[8] = left;  quad[9] = top;    quad[10] = 0.0f; quad[11] = flip ? 0.0f : 1.0f;
	quad[12] = right; quad[13] = top;  quad[14] = 1.0f; quad[15] = flip ? 0.0f : 1.0f;

	blend_was_on = glIsEnabled(GL_BLEND);
	glDisable(GL_BLEND);
	glUseProgram(context->blit_program);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, texture);
	glUniform1i(context->blit_sampler, 0);
	glEnableVertexAttribArray((GLuint)context->blit_position);
	glEnableVertexAttribArray((GLuint)context->blit_uv);
	glVertexAttribPointer((GLuint)context->blit_position, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat),
			      quad);
	glVertexAttribPointer((GLuint)context->blit_uv, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(GLfloat),
			      quad + 2);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glDisableVertexAttribArray((GLuint)context->blit_position);
	glDisableVertexAttribArray((GLuint)context->blit_uv);
	glBindTexture(GL_TEXTURE_2D, 0);
	glUseProgram(0);
	if (blend_was_on) {
		glEnable(GL_BLEND);
	}
	return glGetError() == GL_NO_ERROR;
}

int AGGLBlitTexture(AGGLContext *context, unsigned int texture, int x, int y, int width, int height)
{
	return gl_blit(context, texture, x, y, width, height, 0);
}

int AGGLBlitTextureFlipped(AGGLContext *context, unsigned int texture, int x, int y, int width, int height)
{
	return gl_blit(context, texture, x, y, width, height, 1);
}

#else /* !AG_HAVE_GL */

/* **THE ABSENT BUILD STILL ANSWERS.** A machine without libEGL and GLESv2 compiles this file to these stubs, so a
 * caller never needs a `#ifdef` of its own and a build that cannot render web content says so at the call rather than
 * at a link error it cannot read. This is the same deal `AG_HAVE_DMABUF` makes for the GPU buffer path. */

AGGLContext *AGGLContextCreateWithGBM(void *gbm_device)
{
	(void)gbm_device;
	return NULL;
}

AGGLContext *AGGLContextCreate(AGWindowServer *server)
{
	(void)server;
	return NULL;
}

void AGGLContextDestroy(AGGLContext *context)
{
	(void)context;
}

void AGGLContextInfo(const AGGLContext *context, AGGLInfo *info)
{
	(void)context;
	if (info != NULL) {
		memset(info, 0, sizeof *info);
	}
}

int AGGLMakeCurrent(AGGLContext *context)
{
	if (context == NULL || !context->ready) {
		return 0;
	}
	return eglMakeCurrent(context->display, EGL_NO_SURFACE, EGL_NO_SURFACE, context->context) ? 1 : 0;
}

int AGGLMakeCurrent(AGGLContext *context)
{
	(void)context;
	return 0;
}

void AGGLContextHandles(const AGGLContext *context, void **display, void **config, void **context_out)
{
	(void)context;
	if (display != NULL) {
		*display = NULL;
	}
	if (config != NULL) {
		*config = NULL;
	}
	if (context_out != NULL) {
		*context_out = NULL;
	}
}

int AGGLBeginFrame(AGGLContext *context, int width, int height)
{
	(void)context;
	(void)width;
	(void)height;
	return 0;
}

void AGGLEndFrame(AGGLContext *context)
{
	(void)context;
}

int AGGLReadPixels(AGGLContext *context, int x, int y, int width, int height, uint32_t *dst,
		   int dst_stride_bytes)
{
	(void)context;
	(void)x;
	(void)y;
	(void)width;
	(void)height;
	(void)dst;
	(void)dst_stride_bytes;
	return 0;
}

int AGGLPresentToWindow(AGGLContext *context, AGWindow *window, int x, int y)
{
	(void)context;
	(void)window;
	(void)x;
	(void)y;
	return 0;
}

unsigned int AGGLTextureFromImage(AGGLContext *context, const void *egl_image, int width, int height)
{
	(void)context;
	(void)egl_image;
	(void)width;
	(void)height;
	return 0;
}

unsigned int AGGLTextureFromDmabuf(AGGLContext *context, int fd, int width, int height, int stride,
				   unsigned int fourcc, unsigned long long modifier)
{
	(void)context;
	(void)fd;
	(void)width;
	(void)height;
	(void)stride;
	(void)fourcc;
	(void)modifier;
	return 0;
}

void AGGLDeleteTexture(AGGLContext *context, unsigned int texture)
{
	(void)context;
	(void)texture;
}

int AGGLExportTextureDmabuf(AGGLContext *context, unsigned int texture, int width, int height, int *fd,
			    int *stride, unsigned int *fourcc_out, unsigned long long *modifier_out)
{
	(void)context;
	(void)texture;
	(void)width;
	(void)height;
	(void)fd;
	(void)stride;
	return 0;
}

int AGGLBlitTexture(AGGLContext *context, unsigned int texture, int x, int y, int width, int height)
{
	(void)context;
	(void)texture;
	(void)x;
	(void)y;
	(void)width;
	(void)height;
	return 0;
}

int AGGLBlitTextureFlipped(AGGLContext *context, unsigned int texture, int x, int y, int width, int height)
{
	(void)context;
	(void)texture;
	(void)x;
	(void)y;
	(void)width;
	(void)height;
	return 0;
}

AGGLRenderTarget *AGGLRenderTargetFromDmabuf(AGGLContext *context, int fd, int width, int height, int stride,
					     unsigned int fourcc, unsigned long long modifier)
{
	(void)context;
	(void)fd;
	(void)width;
	(void)height;
	(void)stride;
	(void)fourcc;
	(void)modifier;
	return NULL;
}

int AGGLBeginRenderTarget(AGGLContext *context, AGGLRenderTarget *target)
{
	(void)context;
	(void)target;
	return 0;
}

void AGGLEndRenderTarget(AGGLContext *context)
{
	(void)context;
}

void AGGLRenderTargetDestroy(AGGLContext *context, AGGLRenderTarget *target)
{
	(void)context;
	(void)target;
}

unsigned int AGGLTargetTexture(AGGLContext *context)
{
	(void)context;
	return 0;
}

int AGGLFillRect(AGGLContext *context, int x, int y, int width, int height, uint32_t rgb)
{
	(void)context;
	(void)x;
	(void)y;
	(void)width;
	(void)height;
	(void)rgb;
	return 0;
}

unsigned int AGGLTextureFromPixels(AGGLContext *context, const uint32_t *pixels, int width, int height,
				   int stride_bytes)
{
	(void)context;
	(void)pixels;
	(void)width;
	(void)height;
	(void)stride_bytes;
	return 0;
}

#endif /* AG_HAVE_GL */
