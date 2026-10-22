/*
 * NSOpenGL.m — declared, refused, and honest about it.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **A REFUSAL IS THE DISPOSITION THE PLAN ASSIGNS TO A11**, and the plan is explicit that it is a supported outcome
 * rather than a gap: "no GL, no QuickDraw, no movie decoder". Each door here answers its type's empty value AND names
 * what is missing, so a caller can tell "this tier cannot do that" from "this tier did it and the answer was zero".
 *
 * **`NSOpenGLGetVersion` IS THE ONE THAT COULD LIE MOST EASILY.** Answering `1, 1` would look like an old renderer and
 * send a caller looking for why its context will not create; answering `0, 0` is the truth — there is no GL library
 * here to have a version.
 */
#import <AppKit/NSOpenGL.h>
#import <AppKit/AppKitRefusal.h>

void NSOpenGLGetOption(NSOpenGLGlobalOption pname, GLint *param)
{
	(void)pname;
	if (param != NULL) {
		*param = 0;
	}
	fn_refuse_window("NSOpenGLGetOption", "an OpenGL implementation (this tier has no GL; the compositor speaks "
			 "Wayland and the drawing tier Core Graphics)");
}

void NSOpenGLSetOption(NSOpenGLGlobalOption pname, GLint param)
{
	(void)pname;
	(void)param;
	fn_refuse_window("NSOpenGLSetOption", "an OpenGL implementation");
}

void NSOpenGLGetVersion(GLint *major, GLint *minor)
{
	if (major != NULL) {
		*major = 0;
	}
	if (minor != NULL) {
		*minor = 0;
	}
	fn_refuse_window("NSOpenGLGetVersion", "an OpenGL implementation to report a version of");
}
