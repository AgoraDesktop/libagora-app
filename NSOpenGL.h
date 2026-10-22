/*
 * NSOpenGL.h — the three context-independent OpenGL doors, declared and refused.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THESE ARE THE ONLY GL NAMES THIS TIER DECLARES, AND THEY ARE DECLARED SO THEY CAN REFUSE BY NAME.** Agora has no
 * OpenGL: the compositor speaks Wayland and the drawing tier speaks Core Graphics, so `NSOpenGLContext`,
 * `NSOpenGLView`, `NSOpenGLPixelFormat` and the rest are absent by scope decision rather than oversight. A ported
 * caller that asks only these three gets a named refusal and its type's empty value, which is the same deal
 * `AppKitRefusal.h` states for the other unbacked doors — and a program that needs real GL is told so at the call
 * instead of at a link error it cannot read.
 *
 * The option values are Apple's, read from the 10.6 header, because a caller may pass one and the function must
 * recognise what it was handed.
 */

#ifndef APPKIT_NSOPENGL_H
#define APPKIT_NSOPENGL_H

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

/* **`GLint` WITHOUT OPENGL.** The doors take GL's integer type, and there is no GL header here to borrow it from. The
 * typedef is guarded three ways so that a caller who DOES bring `<OpenGL/gl.h>` gets the real one and no clash. */
#if !defined(GL_INT) && !defined(__gl_h_) && !defined(GLINT_DEFINED)
typedef int GLint;
#define GLINT_DEFINED 1
#endif

typedef enum {
	NSOpenGLGOFormatCacheSize  = 501,
	NSOpenGLGOClearFormatCache = 502,
	NSOpenGLGORetainRenderers  = 503,
	NSOpenGLGOResetLibrary     = 504
} NSOpenGLGlobalOption;

void NSOpenGLGetOption(NSOpenGLGlobalOption pname, GLint *param);
void NSOpenGLSetOption(NSOpenGLGlobalOption pname, GLint param);
void NSOpenGLGetVersion(GLint *major, GLint *minor);

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSOPENGL_H */
